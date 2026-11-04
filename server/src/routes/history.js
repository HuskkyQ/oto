import { badRequest, notFound } from '../errors.js';
import {
  parseCarId,
  parseResourceId,
  parseDateRange,
  parseInteger,
  parseEnum
} from '../params.js';

const DEFAULT_POINTS = 1000;
const MAX_POINTS = 5000;
const DEFAULT_LIMIT = 100;
const MAX_LIMIT = 500;
const MAX_OFFSET = 100_000;

export async function listCars({ db }) {
  const { rows } = await db.query(`
    SELECT id, name, model, trim_badging, marketing_name,
           exterior_color, wheel_type, spoiler_type
    FROM cars
    ORDER BY display_priority NULLS LAST, id
  `);

  return { cars: rows };
}

async function getCar(db, carId) {
  const { rows } = await db.query(
    `SELECT id, name, model, trim_badging, marketing_name,
            exterior_color, wheel_type, spoiler_type
     FROM cars
     WHERE id = $1`,
    [carId]
  );

  if (rows.length === 0) throw notFound('Car not found');
  return rows[0];
}

export async function liveSummary({ db, live, params, now }) {
  const carId = parseCarId(params.id);
  const car = await getCar(db, carId);

  const { rows } = await db.query(
    `SELECT max(date) AT TIME ZONE 'UTC' AS last_position_at
     FROM positions
     WHERE car_id = $1`,
    [carId]
  );

  return {
    car,
    ...live.snapshot(carId),
    last_position_at: rows[0]?.last_position_at ?? null,
    server_time: now.toISOString()
  };
}

async function positionsForCar(db, carId, from, to, maxPoints) {
  const { rows } = await db.query(
    `WITH drive_points AS (
       SELECT p.id, p.drive_id, p.date, p.latitude, p.longitude, p.elevation,
              p.speed, p.power, p.odometer, p.battery_level, p.usable_battery_level,
              row_number() OVER (PARTITION BY p.drive_id ORDER BY p.date, p.id) AS drive_row,
              count(*) OVER (PARTITION BY p.drive_id) AS drive_count
       FROM positions p
       WHERE p.car_id = $1
         AND p.date >= ($2::timestamptz AT TIME ZONE 'UTC')
         AND p.date < ($3::timestamptz AT TIME ZONE 'UTC')
         AND p.drive_id IS NOT NULL
         AND p.latitude IS NOT NULL AND p.longitude IS NOT NULL
     ), ranked AS (
       SELECT *,
              (drive_row = 1 OR drive_row = drive_count) AS endpoint
       FROM drive_points
     ), numbered AS (
       SELECT *, row_number() OVER (PARTITION BY endpoint ORDER BY date, id) AS sample_row,
              count(*) OVER (PARTITION BY endpoint) AS sample_count,
              count(*) FILTER (WHERE endpoint) OVER () AS endpoint_count
       FROM ranked
     ), budgeted AS (
       SELECT *, CASE WHEN endpoint THEN LEAST(endpoint_count, $4::bigint)
                      ELSE GREATEST($4::bigint - endpoint_count, 0) END AS slots
       FROM numbered
     )
     SELECT date AT TIME ZONE 'UTC' AS date, drive_id,
            latitude::float8 AS latitude, longitude::float8 AS longitude,
            elevation, speed, power, odometer, battery_level, usable_battery_level
     FROM budgeted
     WHERE slots >= sample_count
        OR (slots > 0 AND sample_row * slots / sample_count > (sample_row - 1) * slots / sample_count)
     ORDER BY date, id`,
    [carId, from, to, maxPoints]
  );

  return rows;
}

export async function listPositions({ db, params, query, now }) {
  const carId = parseCarId(params.id);
  await getCar(db, carId);

  const { from, to } = parseDateRange(query, { now });
  const maxPoints = parseInteger(query, 'max_points', {
    fallback: DEFAULT_POINTS,
    min: 10,
    max: MAX_POINTS
  });

  const points = await positionsForCar(db, carId, from, to, maxPoints);

  return {
    car_id: carId,
    from: from.toISOString(),
    to: to.toISOString(),
    max_points: maxPoints,
    points
  };
}

export async function listDrives({ db, params, query, now }) {
  const carId = parseCarId(params.id);
  await getCar(db, carId);

  const { from, to } = parseDateRange(query, { now, defaultDays: 90 });
  const limit = parseInteger(query, 'limit', { fallback: DEFAULT_LIMIT, min: 1, max: MAX_LIMIT });
  const offset = parseInteger(query, 'offset', { fallback: 0, min: 0, max: MAX_OFFSET });
  const beforeId = query.has('before_id') ? parseResourceId(query.get('before_id'), 'before_id') : null;
  if (beforeId !== null && offset !== 0) throw badRequest('before_id cannot be combined with offset', 'INVALID_PARAMETER');

  const { rows } = await db.query(
    `SELECT d.id,
            d.start_date AT TIME ZONE 'UTC' AS start_date,
            d.end_date AT TIME ZONE 'UTC' AS end_date,
            d.distance::float8 AS distance_km,
            d.duration_min,
            d.speed_max,
            d.power_max,
            d.power_min,
            d.start_km::float8 AS start_km,
            d.end_km::float8 AS end_km,
            d.start_ideal_range_km::float8 AS start_ideal_range_km,
            d.end_ideal_range_km::float8 AS end_ideal_range_km,
            d.start_rated_range_km::float8 AS start_rated_range_km,
            d.end_rated_range_km::float8 AS end_rated_range_km,
            sp.battery_level AS start_battery_level,
            ep.battery_level AS end_battery_level,
            d.outside_temp_avg::float8 AS outside_temp_avg,
            d.inside_temp_avg::float8 AS inside_temp_avg,
            d.ascent,
            d.descent,
            sa.name AS start_address,
            sa.display_name AS start_address_display,
            ea.name AS end_address,
            ea.display_name AS end_address_display,
            sg.name AS start_geofence,
            eg.name AS end_geofence
     FROM drives d
     LEFT JOIN positions sp ON sp.id = d.start_position_id
     LEFT JOIN positions ep ON ep.id = d.end_position_id
     LEFT JOIN addresses sa ON sa.id = d.start_address_id
     LEFT JOIN addresses ea ON ea.id = d.end_address_id
     LEFT JOIN geofences sg ON sg.id = d.start_geofence_id
     LEFT JOIN geofences eg ON eg.id = d.end_geofence_id
     WHERE d.car_id = $1
       AND d.start_date >= ($2::timestamptz AT TIME ZONE 'UTC')
       AND d.start_date < ($3::timestamptz AT TIME ZONE 'UTC')
       AND ($6::bigint IS NULL OR (d.start_date, d.id) < (
         SELECT start_date, id FROM drives WHERE car_id = $1 AND id = $6
       ))
     ORDER BY d.start_date DESC, d.id DESC
     LIMIT $4 OFFSET $5`,
    [carId, from, to, limit, offset, beforeId]
  );

  return { car_id: carId, from: from.toISOString(), to: to.toISOString(), limit, offset, next_before_id: rows.length === limit ? rows[rows.length - 1].id : null, drives: rows };
}

export async function getDrive({ db, params, query }) {
  const carId = parseCarId(params.id);
  const driveId = parseResourceId(params.driveId, 'drive id');
  await getCar(db, carId);

  const { rows } = await db.query(
    `SELECT d.id,
            d.start_date AT TIME ZONE 'UTC' AS start_date,
            d.end_date AT TIME ZONE 'UTC' AS end_date,
            d.distance::float8 AS distance_km,
            d.duration_min,
            d.speed_max,
            d.power_max,
            d.power_min,
            d.start_km::float8 AS start_km,
            d.end_km::float8 AS end_km,
            d.start_ideal_range_km::float8 AS start_ideal_range_km,
            d.end_ideal_range_km::float8 AS end_ideal_range_km,
            d.start_rated_range_km::float8 AS start_rated_range_km,
            d.end_rated_range_km::float8 AS end_rated_range_km,
            sp.battery_level AS start_battery_level,
            ep.battery_level AS end_battery_level,
            d.outside_temp_avg::float8 AS outside_temp_avg,
            d.inside_temp_avg::float8 AS inside_temp_avg,
            d.ascent,
            d.descent,
            sa.name AS start_address,
            sa.display_name AS start_address_display,
            ea.name AS end_address,
            ea.display_name AS end_address_display,
            sg.name AS start_geofence,
            eg.name AS end_geofence
     FROM drives d
     LEFT JOIN positions sp ON sp.id = d.start_position_id
     LEFT JOIN positions ep ON ep.id = d.end_position_id
     LEFT JOIN addresses sa ON sa.id = d.start_address_id
     LEFT JOIN addresses ea ON ea.id = d.end_address_id
     LEFT JOIN geofences sg ON sg.id = d.start_geofence_id
     LEFT JOIN geofences eg ON eg.id = d.end_geofence_id
     WHERE d.car_id = $1 AND d.id = $2`,
    [carId, driveId]
  );

  if (rows.length === 0) throw notFound('Drive not found');

  const maxPoints = parseInteger(query, 'max_points', {
    fallback: DEFAULT_POINTS,
    min: 10,
    max: MAX_POINTS
  });

  const [{ rows: positions }, { rows: energyRows }] = await Promise.all([
    db.query(
      `WITH pts AS (
         SELECT p.*, extract(epoch FROM (p.date AT TIME ZONE 'UTC')) AS ts
         FROM positions p
         WHERE p.drive_id = $1
       ), bounds AS (
         SELECT min(ts) AS lo, max(ts) AS hi FROM pts
       )
       SELECT DISTINCT ON (bucket)
              s.date AT TIME ZONE 'UTC' AS date,
              s.latitude::float8 AS latitude,
              s.longitude::float8 AS longitude,
              s.elevation,
              s.speed,
              s.power,
              s.odometer,
              s.battery_level,
              s.usable_battery_level
       FROM (
         SELECT pts.*,
                LEAST($2, width_bucket(
                  pts.ts,
                  b.lo,
                  GREATEST(b.hi, b.lo + 1),
                  $2
                )) AS bucket
         FROM pts
         CROSS JOIN bounds b
       ) s
       ORDER BY bucket, s.date`,
      [driveId, maxPoints]
    ),
    db.query(
      `WITH pts AS (
         SELECT date, power, lead(date) OVER (ORDER BY date) AS next_date
         FROM positions
         WHERE drive_id = $1
       )
       SELECT (sum(power * extract(epoch FROM (next_date - date))) / 3600.0)::float8
              AS energy_kwh
       FROM pts
       WHERE next_date IS NOT NULL AND power IS NOT NULL`,
      [driveId]
    )
  ]);

  return {
    car_id: carId,
    drive: rows[0],
    positions,
    energy_kwh: energyRows[0]?.energy_kwh ?? null
  };
}

export async function listCharges({ db, params, query, now }) {
  const carId = parseCarId(params.id);
  await getCar(db, carId);

  const { from, to } = parseDateRange(query, { now, defaultDays: 90 });
  const limit = parseInteger(query, 'limit', { fallback: DEFAULT_LIMIT, min: 1, max: MAX_LIMIT });
  const offset = parseInteger(query, 'offset', { fallback: 0, min: 0, max: MAX_OFFSET });
  const beforeId = query.has('before_id') ? parseResourceId(query.get('before_id'), 'before_id') : null;
  if (beforeId !== null && offset !== 0) throw badRequest('before_id cannot be combined with offset', 'INVALID_PARAMETER');

  const { rows } = await db.query(
    `SELECT cp.id,
            cp.start_date AT TIME ZONE 'UTC' AS start_date,
            cp.end_date AT TIME ZONE 'UTC' AS end_date,
            cp.charge_energy_added::float8 AS charge_energy_added,
            cp.charge_energy_used::float8 AS charge_energy_used,
            cp.start_battery_level,
            cp.end_battery_level,
            cp.duration_min,
            cp.start_ideal_range_km::float8 AS start_ideal_range_km,
            cp.end_ideal_range_km::float8 AS end_ideal_range_km,
            cp.start_rated_range_km::float8 AS start_rated_range_km,
            cp.end_rated_range_km::float8 AS end_rated_range_km,
            cp.outside_temp_avg::float8 AS outside_temp_avg,
            cp.cost::float8 AS cost,
            a.name AS address,
            a.display_name AS address_display,
            g.name AS geofence
     FROM charging_processes cp
     LEFT JOIN addresses a ON a.id = cp.address_id
     LEFT JOIN geofences g ON g.id = cp.geofence_id
     WHERE cp.car_id = $1
       AND cp.start_date >= ($2::timestamptz AT TIME ZONE 'UTC')
       AND cp.start_date < ($3::timestamptz AT TIME ZONE 'UTC')
       AND ($6::bigint IS NULL OR (cp.start_date, cp.id) < (
         SELECT start_date, id FROM charging_processes WHERE car_id = $1 AND id = $6
       ))
     ORDER BY cp.start_date DESC, cp.id DESC
     LIMIT $4 OFFSET $5`,
    [carId, from, to, limit, offset, beforeId]
  );

  return {
    car_id: carId,
    from: from.toISOString(),
    to: to.toISOString(),
    limit,
    offset,
    next_before_id: rows.length === limit ? rows[rows.length - 1].id : null,
    charges: rows
  };
}

export async function getCharge({ db, params }) {
  const carId = parseCarId(params.id);
  const chargeId = parseResourceId(params.chargeId, 'charge id');
  await getCar(db, carId);

  const { rows } = await db.query(
    `SELECT cp.id,
            cp.start_date AT TIME ZONE 'UTC' AS start_date,
            cp.end_date AT TIME ZONE 'UTC' AS end_date,
            cp.charge_energy_added::float8 AS charge_energy_added,
            cp.charge_energy_used::float8 AS charge_energy_used,
            cp.start_battery_level,
            cp.end_battery_level,
            cp.duration_min,
            cp.start_ideal_range_km::float8 AS start_ideal_range_km,
            cp.end_ideal_range_km::float8 AS end_ideal_range_km,
            cp.start_rated_range_km::float8 AS start_rated_range_km,
            cp.end_rated_range_km::float8 AS end_rated_range_km,
            cp.outside_temp_avg::float8 AS outside_temp_avg,
            cp.cost::float8 AS cost,
            a.name AS address,
            a.display_name AS address_display,
            g.name AS geofence
     FROM charging_processes cp
     LEFT JOIN addresses a ON a.id = cp.address_id
     LEFT JOIN geofences g ON g.id = cp.geofence_id
     WHERE cp.car_id = $1 AND cp.id = $2`,
    [carId, chargeId]
  );

  if (rows.length === 0) throw notFound('Charging session not found');

  const { rows: samples } = await db.query(
    `SELECT date AT TIME ZONE 'UTC' AS date,
            battery_level,
            usable_battery_level,
            charge_energy_added::float8 AS charge_energy_added,
            charger_actual_current,
            charger_phases,
            charger_pilot_current,
            charger_power::float8 AS charger_power,
            charger_voltage,
            conn_charge_cable,
            fast_charger_present,
            fast_charger_brand,
            fast_charger_type,
            ideal_battery_range_km::float8 AS ideal_battery_range_km,
            rated_battery_range_km::float8 AS rated_battery_range_km,
            outside_temp::float8 AS outside_temp
     FROM charges
     WHERE charging_process_id = $1
     ORDER BY date`,
    [chargeId]
  );

  return { car_id: carId, charge: rows[0], samples };
}

export async function listStates({ db, params, query, now }) {
  const carId = parseCarId(params.id);
  await getCar(db, carId);

  const { from, to } = parseDateRange(query, { now });
  const { rows } = await db.query(
    `SELECT state,
            start_date AT TIME ZONE 'UTC' AS start_date,
            end_date AT TIME ZONE 'UTC' AS end_date
     FROM states
     WHERE car_id = $1
       AND start_date < ($3::timestamptz AT TIME ZONE 'UTC')
       AND (end_date IS NULL OR end_date > ($2::timestamptz AT TIME ZONE 'UTC'))
     ORDER BY start_date`,
    [carId, from, to]
  );

  return { car_id: carId, from: from.toISOString(), to: to.toISOString(), states: rows };
}

export async function listUpdates({ db, params }) {
  const carId = parseCarId(params.id);
  await getCar(db, carId);

  const { rows } = await db.query(
    `SELECT version,
            start_date AT TIME ZONE 'UTC' AS start_date,
            end_date AT TIME ZONE 'UTC' AS end_date
     FROM updates
     WHERE car_id = $1
     ORDER BY start_date DESC
     LIMIT 100`,
    [carId]
  );

  return { car_id: carId, updates: rows };
}

export async function stats({ db, params, query, now }) {
  const carId = parseCarId(params.id);
  await getCar(db, carId);

  const { from, to } = parseDateRange(query, { now, defaultDays: 30 });
  const bucket = parseEnum(query, 'bucket', ['day', 'month']);

  const { rows } = await db.query(
    `WITH drive_buckets AS (
       SELECT date_trunc($4, start_date) AS bucket,
              count(*)::int AS drive_count,
              COALESCE(sum(distance), 0)::float8 AS distance_km,
              COALESCE(sum(duration_min), 0)::int AS duration_min
       FROM drives
       WHERE car_id = $1
         AND start_date >= ($2::timestamptz AT TIME ZONE 'UTC')
         AND start_date < ($3::timestamptz AT TIME ZONE 'UTC')
       GROUP BY 1
     ), charge_buckets AS (
       SELECT date_trunc($4, start_date) AS bucket,
              count(*)::int AS charge_count,
              COALESCE(sum(charge_energy_added), 0)::float8 AS charge_energy_kwh,
              sum(cost)::float8 AS charge_cost
       FROM charging_processes
       WHERE car_id = $1
         AND start_date >= ($2::timestamptz AT TIME ZONE 'UTC')
         AND start_date < ($3::timestamptz AT TIME ZONE 'UTC')
       GROUP BY 1
     )
     SELECT COALESCE(d.bucket, c.bucket) AT TIME ZONE 'UTC' AS bucket,
            COALESCE(d.drive_count, 0) AS drive_count,
            COALESCE(d.distance_km, 0) AS distance_km,
            COALESCE(d.duration_min, 0) AS duration_min,
            COALESCE(c.charge_count, 0) AS charge_count,
            COALESCE(c.charge_energy_kwh, 0) AS charge_energy_kwh,
            c.charge_cost AS charge_cost
     FROM drive_buckets d
     FULL JOIN charge_buckets c ON d.bucket = c.bucket
     ORDER BY 1`,
    [carId, from, to, bucket]
  );

  return {
    car_id: carId,
    from: from.toISOString(),
    to: to.toISOString(),
    bucket,
    buckets: rows
  };
}
