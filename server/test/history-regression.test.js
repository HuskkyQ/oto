import assert from 'node:assert/strict';
import test, { before, after } from 'node:test';
import pg from 'pg';
import { getDrive, listDrives, listCharges, listPositions, liveSummary, stats } from '../src/routes/history.js';

// Set HISTORY_TEST_DATABASE_URL to a disposable PostgreSQL database. All tables are temporary.
const url = process.env.HISTORY_TEST_DATABASE_URL;
const integration = (name, fn) => test(name, { skip: !url }, fn);
const db = url ? new pg.Client({ connectionString: url }) : null;
const now = new Date('2026-11-02T12:00:00Z');
const params = { id: '1' };
const range = 'from=2026-09-30T00:00:00Z&to=2026-11-02T12:00:00Z';

before(async () => {
  if (!db) return;
  await db.connect();
  await db.query(`
    CREATE TEMP TABLE cars (id int, name text, model text, trim_badging text, marketing_name text, exterior_color text, wheel_type text, spoiler_type text);
    CREATE TEMP TABLE addresses (id int, name text, display_name text);
    CREATE TEMP TABLE geofences (id int, name text);
    CREATE TEMP TABLE drives (id int, car_id int, start_date timestamp, end_date timestamp, distance numeric, duration_min int, speed_max int, power_max int, power_min int, start_km numeric, end_km numeric, start_ideal_range_km numeric, end_ideal_range_km numeric, start_rated_range_km numeric, end_rated_range_km numeric, outside_temp_avg numeric, inside_temp_avg numeric, ascent int, descent int, start_address_id int, end_address_id int, start_geofence_id int, end_geofence_id int);
    CREATE TEMP TABLE charging_processes (id int, car_id int, start_date timestamp, end_date timestamp, charge_energy_added numeric, charge_energy_used numeric, start_battery_level int, end_battery_level int, duration_min int, start_ideal_range_km numeric, end_ideal_range_km numeric, start_rated_range_km numeric, end_rated_range_km numeric, outside_temp_avg numeric, cost numeric, address_id int, geofence_id int);
    CREATE TEMP TABLE positions (id int, car_id int, drive_id int, date timestamp, latitude numeric, longitude numeric, elevation int, speed int, power int, odometer numeric, battery_level int, usable_battery_level int);
    INSERT INTO cars (id) VALUES (1);
  `);
});

after(async () => { if (db) await db.end(); });

integration('stats distinguishes unrecorded costs, free charging, and drive-only buckets', async () => {
  await db.query(`TRUNCATE drives, charging_processes;
    INSERT INTO drives (id, car_id, start_date) VALUES (1, 1, '2026-10-01');
    INSERT INTO charging_processes (id, car_id, start_date, cost) VALUES
      (1, 1, '2026-10-02', NULL), (2, 1, '2026-10-03', 0),
      (3, 1, '2026-10-04', NULL), (4, 1, '2026-10-04', 2.5)`);
  const result = await stats({ db, params, query: new URLSearchParams(`${range}&bucket=day`), now });
  assert.deepEqual(result.buckets.map((bucket) => bucket.charge_cost), [null, null, 0, 2.5]);
});

integration('drive energy is a JSON number and missing usable intervals remain null', async () => {
  await db.query(`TRUNCATE drives, positions;
    INSERT INTO drives (id, car_id, start_date) VALUES (10, 1, '2026-10-01');
    INSERT INTO positions (id, car_id, drive_id, date, power) VALUES
      (1, 1, 10, '2026-10-01 00:00:00', 10), (2, 1, 10, '2026-10-01 00:30:00', 0)`);
  const request = { db, params: { ...params, driveId: '10' }, query: new URLSearchParams() };
  assert.equal(JSON.parse(JSON.stringify(await getDrive(request))).energy_kwh, 5);
  await db.query('UPDATE positions SET power = NULL');
  assert.equal((await getDrive(request)).energy_kwh, null);
  await db.query('UPDATE positions SET power = 0');
  assert.equal((await getDrive(request)).energy_kwh, 0);
  await db.query('DELETE FROM positions WHERE id = 2');
  assert.equal((await getDrive(request)).energy_kwh, null);
});

integration('drive detail never exceeds max_points, including the upper endpoint', async () => {
  await db.query(`TRUNCATE drives, positions;
    INSERT INTO drives (id, car_id, start_date) VALUES (10, 1, '2026-10-01');
    INSERT INTO positions (id, car_id, drive_id, date)
      SELECT n, 1, 10, timestamp '2026-10-01' + n * interval '1 second' FROM generate_series(0, 10) n`);
  const result = await getDrive({ db, params: { ...params, driveId: '10' }, query: new URLSearchParams('max_points=10') });
  assert.equal(result.positions.length, 10);
});

integration('positions sample valid drive points and preserve endpoints within the total budget', async () => {
  await db.query(`TRUNCATE positions;
    INSERT INTO positions (id, car_id, drive_id, date, latitude, longitude)
      SELECT n, 1, CASE WHEN n <= 20 THEN 1 ELSE 2 END,
             timestamp '2026-10-01' + n * interval '1 second', 1, 1
      FROM generate_series(1, 40) n;
    INSERT INTO positions (id, car_id, drive_id, date, latitude, longitude) VALUES
      (41, 1, NULL, '2026-10-01 00:00:00', 1, 1),
      (42, 1, 3, '2026-10-01 00:00:00', NULL, 1),
      (43, 2, 4, '2026-10-01 00:00:00', 1, 1)`);
  const result = await listPositions({ db, params, now, query: new URLSearchParams(`${range}&max_points=10`) });
  assert.equal(result.points.length, 10);
  assert.deepEqual([...new Set(result.points.map((point) => point.drive_id))], [1, 2]);
  assert.deepEqual(result.points.filter((point) => [1, 20, 21, 40].includes(new Date(point.date).getUTCSeconds())).map((point) => new Date(point.date).getUTCSeconds()), [1, 20, 21, 40]);
});

integration('positions retain all valid points below the limit and return an empty result otherwise', async () => {
  await db.query(`TRUNCATE positions;
    INSERT INTO positions (id, car_id, drive_id, date, latitude, longitude) VALUES
      (1, 1, 1, '2026-10-01', 1, 1), (2, 1, 1, '2026-10-01', 1, 1),
      (3, 1, NULL, '2026-10-01', 1, 1), (4, 1, 1, '2026-10-01', 1, NULL)`);
  const request = { db, params, now, query: new URLSearchParams(`${range}&max_points=10`) };
  assert.equal((await listPositions(request)).points.length, 2);
  await db.query('UPDATE positions SET drive_id = NULL');
  assert.deepEqual((await listPositions(request)).points, []);
});

integration('positions remain capped when drive endpoints exceed the budget', async () => {
  await db.query(`TRUNCATE positions;
    INSERT INTO positions (id, car_id, drive_id, date, latitude, longitude)
      SELECT n, 1, (n + 1) / 2, timestamp '2026-10-01' + n * interval '1 second', 1, 1
      FROM generate_series(1, 40) n`);
  const result = await listPositions({ db, params, now, query: new URLSearchParams(`${range}&max_points=10`) });
  assert.equal(result.points.length, 10);
  assert.ok(result.points.every((point) => point.drive_id !== null));
});

for (const [name, table, list, field] of [
  ['drives', 'drives', listDrives, 'drives'],
  ['charges', 'charging_processes', listCharges, 'charges']
]) {
  integration(`${name} cursor pagination is stable across ties and newer inserts`, async () => {
    await db.query(`TRUNCATE ${table}; INSERT INTO ${table} (id, car_id, start_date) VALUES
      (1, 1, '2026-10-01'), (2, 1, '2026-10-02'), (3, 1, '2026-10-03'), (4, 1, '2026-10-03')`);
    const page1 = await list({ db, params, now, query: new URLSearchParams(`${range}&limit=2`) });
    assert.deepEqual(page1[field].map((row) => row.id), [4, 3]);
    assert.equal(page1.next_before_id, 3);
    await db.query(`INSERT INTO ${table} (id, car_id, start_date) VALUES (5, 1, '2026-10-04')`);
    const page2 = await list({ db, params, now, query: new URLSearchParams(`${range}&limit=2&before_id=${page1.next_before_id}`) });
    assert.deepEqual(page2[field].map((row) => row.id), [2, 1]);
    const offset = await list({ db, params, now, query: new URLSearchParams(`${range}&limit=2&offset=1`) });
    assert.deepEqual(offset[field].map((row) => row.id), [4, 3]);
    await assert.rejects(list({ db, params, now, query: new URLSearchParams(`${range}&before_id=3&offset=1`) }), { status: 400 });
  });
}

integration('UTC range bounds ignore the database session timezone', async () => {
  await db.query("SET TIME ZONE 'Asia/Shanghai'");
  try {
    await db.query(`TRUNCATE drives;
      INSERT INTO drives (id, car_id, start_date) VALUES
        (1, 1, '2026-09-30 23:59:59'), (2, 1, '2026-10-01 00:00:00')`);
    const result = await listDrives({
      db,
      params,
      now,
      query: new URLSearchParams('from=2026-10-01T00:00:00.000Z&to=2026-10-01T00:00:01.000Z&limit=10')
    });
    assert.deepEqual(result.drives.map((row) => row.id), [2]);
  } finally {
    await db.query("SET TIME ZONE 'UTC'");
  }
});

integration('live summary returns the latest stored position even when it is old', async () => {
  await db.query(`TRUNCATE positions; INSERT INTO positions (car_id, date) VALUES (1, '2020-01-01'), (1, '2020-01-02')`);
  const result = await liveSummary({ db, params, now, live: { snapshot: () => ({}) } });
  assert.equal(new Date(result.last_position_at).toISOString(), '2020-01-02T00:00:00.000Z');
});
