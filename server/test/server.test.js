import assert from 'node:assert/strict';
import test, { after, before } from 'node:test';

import { createHttpServer } from '../src/server.js';

const TOKEN = '{{SECRET_v5plfk3j}}';
const now = new Date('2026-11-02T12:00:00.000Z');

const car = {
  id: 1,
  name: 'Blue Thunder',
  model: '3',
  trim_badging: '74D',
  marketing_name: 'LR AWD',
  exterior_color: 'DeepBlue',
  wheel_type: 'Pinwheel18',
  spoiler_type: 'None'
};

const drive = {
  id: 10,
  start_date: new Date('2026-10-30T08:00:00.000Z'),
  end_date: new Date('2026-10-30T08:30:00.000Z'),
  distance_km: 12.5,
  duration_min: 30
};

const charge = {
  id: 5,
  start_date: new Date('2026-10-30T09:00:00.000Z'),
  end_date: new Date('2026-10-30T10:00:00.000Z'),
  charge_energy_added: 20.5,
  cost: 4.1
};

const point = {
  date: new Date('2026-10-30T08:00:00.000Z'),
  latitude: 30.1,
  longitude: 120.2,
  elevation: 10,
  speed: 30,
  power: 100,
  odometer: 1000,
  battery_level: 60,
  usable_battery_level: 59
};

function fakeDb() {
  return {
    async query(sql, params = []) {
      // Postgres rejects a statement that uses $7 when six values were bound; without this the
      // fake would happily answer and the mismatch would only show up at runtime.
      const highest = sql.match(/\$(\d+)/g)?.reduce((max, $) => Math.max(max, Number($.slice(1))), 0) ?? 0;
      assert.ok(params.length >= highest, `binds ${params.length} values but uses $${highest}`);

      if (sql.includes('FROM cars') && sql.includes('WHERE id = $1')) {
        return { rows: Number(params[0]) === 1 ? [car] : [] };
      }
      if (sql.includes('FROM cars')) return { rows: [car] };
      if (sql.includes('max(date)')) {
        return { rows: [{ last_position_at: new Date('2026-11-02T11:55:00.000Z') }] };
      }
      if (sql.includes('drive_buckets')) {
        return {
          rows: [
            {
              bucket: new Date('2026-10-30T00:00:00.000Z'),
              drive_count: 1,
              distance_km: 12.5,
              duration_min: 30,
              charge_count: 1,
              charge_energy_kwh: 20.5,
              charge_cost: 4.1
            }
          ]
        };
      }
      // Derived routes: matched before the broad table checks below.
      if (sql.includes('drive_energy')) {
        return {
          rows: [
            {
              id: 8,
              start_date: new Date('2026-08-01T08:00:00.000Z'),
              distance_km: 100,
              outside_temp_avg: 31,
              kwh: 15,
              version: '2026.26'
            },
            {
              id: 10,
              start_date: new Date('2026-10-30T08:00:00.000Z'),
              distance_km: 50,
              outside_temp_avg: 12,
              kwh: 9,
              version: '2026.40'
            }
          ]
        };
      }
      if (sql.includes('date_trunc')) {
        return {
          rows: [
            {
              date: new Date('2026-11-02T00:00:00.000Z'),
              is_today: true,
              regen_kwh: 0.8,
              consumed_kwh: 5.2,
              minutes: 12,
              peak_kw: 42
            }
          ]
        };
      }
      if (sql.includes('AS version')) {
        return { rows: [{ version: '2026.40', peak_kw: 42, regen_kwh: 0.8 }] };
      }
      if (sql.includes('sessions s')) {
        return {
          rows: [
            {
              start_date: new Date('2026-10-30T10:00:00.000Z'),
              end_date: new Date('2026-11-02T08:00:00.000Z'),
              energy_kwh: 0.72,
              start_level: 80,
              end_level: 78,
              start_range_km: 320,
              end_range_km: 312,
              odometer_km: 1012.5,
              outside_temp_avg: 14,
              states: ['asleep', 'online'],
              state_minutes: [4000, 560],
              place: '🏢 Office'
            }
          ]
        };
      }
      if (sql.includes('end_battery_level - cp.start_battery_level')) {
        return {
          rows: [
            {
              end_date: new Date('2026-10-01T10:00:00.000Z'),
              start_battery_level: 20,
              end_battery_level: 100,
              added: 57,
              end_rated: 356.25
            },
            ...Array.from({ length: 4 }, (_, index) => ({
              end_date: new Date(`2026-0${index + 1}-01T10:00:00.000Z`),
              start_battery_level: 20,
              end_battery_level: 100,
              added: 60,
              end_rated: 375
            }))
          ]
        };
      }
      if (sql.includes('max(odometer)')) return { rows: [{ odometer_km: 12_345.5 }] };
      if (sql.includes('energy_kwh')) return { rows: [{ energy_kwh: 2.5 }] };
      if (sql.includes('FROM drives d') && sql.includes('d.id = $2')) return { rows: [drive] };
      if (sql.includes('FROM drives d')) return { rows: [drive] };
      if (sql.includes('FROM charging_processes cp') && sql.includes('cp.id = $2')) {
        return { rows: [charge] };
      }
      if (sql.includes('FROM charging_processes cp')) return { rows: [charge] };
      if (sql.includes('FROM charges')) {
        return { rows: [{ date: point.date, battery_level: 50, charger_power: 11 }] };
      }
      if (sql.includes('FROM states')) {
        return { rows: [{ state: 'online', start_date: point.date, end_date: null }] };
      }
      if (sql.includes('FROM updates')) {
        return { rows: [{ version: '2026.40', start_date: point.date, end_date: null }] };
      }
      if (sql.includes('WITH drive_points')) return { rows: [{ ...point, drive_id: 10 }] };
      if (sql.includes('width_bucket')) return { rows: [point] };
      return { rows: [] };
    }
  };
}

const live = {
  snapshot(carId) {
    if (Number(carId) !== 1) {
      return {
        mqtt_connected: true,
        values: {},
        received_at: null,
        oldest_received_at: null,
        stale: true,
        last_error: null
      };
    }

    return {
      mqtt_connected: true,
      values: { battery_level: 60, state: 'online' },
      received_at: '2026-11-02T11:59:00.000Z',
      oldest_received_at: '2026-11-02T11:58:00.000Z',
      stale: false,
      last_error: null
    };
  }
};

let server;
let base;

before(async () => {
  server = createHttpServer({
    config: { apiToken: TOKEN },
    db: fakeDb(),
    live,
    now: () => now,
    logger: { info() {}, error() {} }
  });

  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  base = `http://127.0.0.1:${server.address().port}`;
});

after(() => new Promise((resolve) => server.close(resolve)));

const auth = { authorization: `Bearer ${TOKEN}` };

async function get(path, headers = auth) {
  const response = await fetch(`${base}${path}`, { headers });
  return { status: response.status, body: await response.json() };
}

test('healthz is public', async () => {
  const { status, body } = await get('/healthz', {});
  assert.equal(status, 200);
  assert.deepEqual(body, { ok: true });
});

test('v1 routes require the bearer token', async () => {
  assert.equal((await get('/v1/cars', {})).status, 401);
  assert.equal((await get('/v1/cars', { authorization: 'Bearer wrong' })).status, 401);
});

test('cars list never exposes VIN', async () => {
  const { status, body } = await get('/v1/cars');
  assert.equal(status, 200);
  assert.equal(body.cars.length, 1);
  assert.equal(body.cars[0].name, 'Blue Thunder');
  assert.equal('vin' in body.cars[0], false);
});

test('live summary merges MQTT values and the last stored position', async () => {
  const { status, body } = await get('/v1/cars/1/live');
  assert.equal(status, 200);
  assert.equal(body.car.id, 1);
  assert.equal(body.values.battery_level, 60);
  assert.equal(body.mqtt_connected, true);
  assert.equal(body.last_position_at, '2026-11-02T11:55:00.000Z');
  assert.equal(body.server_time, now.toISOString());
});

test('unknown cars return 404', async () => {
  assert.equal((await get('/v1/cars/2/live')).status, 404);
  assert.equal((await get('/v1/cars/2/drives')).status, 404);
});

test('positions are returned and invalid ranges are rejected', async () => {
  const ok = await get('/v1/cars/1/positions?from=2026-10-01&to=2026-10-02');
  assert.equal(ok.status, 200);
  assert.equal(ok.body.points.length, 1);
  assert.equal(ok.body.points[0].drive_id, 10);

  const bad = await get('/v1/cars/1/positions?from=not-a-date');
  assert.equal(bad.status, 400);
  assert.equal(bad.body.code, 'INVALID_DATE');
});

test('drives, drive detail, charges and charge detail', async () => {
  const drives = await get('/v1/cars/1/drives');
  assert.equal(drives.status, 200);
  assert.equal(drives.body.drives[0].id, 10);

  const detail = await get('/v1/cars/1/drives/10');
  assert.equal(detail.status, 200);
  assert.equal(detail.body.drive.id, 10);
  assert.equal(detail.body.energy_kwh, 2.5);
  assert.equal(detail.body.positions.length, 1);

  const charges = await get('/v1/cars/1/charges');
  assert.equal(charges.status, 200);
  assert.equal(charges.body.charges[0].id, 5);

  const chargeDetail = await get('/v1/cars/1/charges/5');
  assert.equal(chargeDetail.status, 200);
  assert.equal(chargeDetail.body.charge.id, 5);
  assert.equal(chargeDetail.body.samples.length, 1);
});

test('states, updates and stats', async () => {
  const states = await get('/v1/cars/1/states');
  assert.equal(states.status, 200);
  assert.equal(states.body.states[0].state, 'online');

  const updates = await get('/v1/cars/1/updates');
  assert.equal(updates.status, 200);
  assert.equal(updates.body.updates[0].version, '2026.40');

  const stats = await get('/v1/cars/1/stats?bucket=day');
  assert.equal(stats.status, 200);
  assert.equal(stats.body.buckets[0].distance_km, 12.5);

  const bad = await get('/v1/cars/1/stats?bucket=week');
  assert.equal(bad.status, 400);
});

test('energy groups by version, season or temperature', async () => {
  const byVersion = await get('/v1/cars/1/energy?from=2026-07-01&to=2026-11-02');
  assert.equal(byVersion.status, 200);
  assert.equal(byVersion.body.group, 'version');
  assert.equal(byVersion.body.total_km, 150);
  assert.equal(byVersion.body.average_wh_per_km, 160);
  assert.deepEqual(
    byVersion.body.groups.map((group) => group.label),
    ['2026.40', '2026.26']
  );

  const bySeason = await get('/v1/cars/1/energy?from=2026-07-01&to=2026-11-02&group=season');
  assert.deepEqual(
    bySeason.body.groups.map((group) => [group.label, group.wh_per_km]),
    [['夏季', 150], ['秋季', 180]]
  );
  assert.equal(bySeason.body.best.label, '夏季');

  const byTemp = await get('/v1/cars/1/energy?from=2026-07-01&to=2026-11-02&group=temperature');
  assert.deepEqual(
    byTemp.body.groups.map((group) => group.label),
    ['10 – 20°C', '30°C 以上']
  );

  assert.equal((await get('/v1/cars/1/energy?group=week')).status, 400);
});

test('regen reports today, the daily series and the peak', async () => {
  const { status, body } = await get('/v1/cars/1/regen?from=2026-10-27&to=2026-11-02T12:00:00Z');
  assert.equal(status, 200);
  assert.equal(body.today.regen_kwh, 0.8);
  assert.equal(body.days.length, 1);
  assert.equal(body.week_peak_kw, 42);
  assert.equal(body.share, 0.133);
  assert.equal(body.versions[0].version, '2026.40');
});

test('parking turns the gaps between drives into sessions', async () => {
  const { status, body } = await get('/v1/cars/1/parking');
  assert.equal(status, 200);
  assert.equal(body.sessions.length, 1);

  const session = body.sessions[0];
  assert.equal(session.place, '🏢 Office');
  assert.equal(session.duration_min, 4200);
  // 8 km of rated range at the car's own 0.2 kWh/km (75 kWh over 375 km).
  assert.equal(session.energy_kwh, 1.6);
  assert.equal(session.average_power_w, 23);
  assert.equal(session.range_loss_km, 8);
  assert.deepEqual(session.state_minutes, [
    { state: 'asleep', minutes: 4000 },
    { state: 'online', minutes: 560 }
  ]);
  assert.equal(body.total_energy_kwh, 1.6);
});

test('battery health hides the rating when there are too few charges', async () => {
  const { status, body } = await get('/v1/cars/1/battery');
  assert.equal(status, 200);
  assert.equal(body.sample_count, 5);
  assert.equal(body.capacity_kwh, 75);
  assert.equal(body.full_range_km, 375);
  assert.equal(body.score, 100);
  assert.equal(body.rating, '优秀');
  assert.equal(body.odometer_km, 12345.5);
});

test('derived routes reject unknown cars', async () => {
  assert.equal((await get('/v1/cars/2/energy')).status, 404);
  assert.equal((await get('/v1/cars/2/regen')).status, 404);
  assert.equal((await get('/v1/cars/2/parking')).status, 404);
  assert.equal((await get('/v1/cars/2/battery')).status, 404);
});

test('unknown paths are 404 and wrong methods are 405', async () => {
  assert.equal((await get('/nope')).status, 404);

  const response = await fetch(`${base}/healthz`, { method: 'POST' });
  assert.equal(response.status, 405);
  assert.equal(response.headers.get('allow'), 'GET');
});
