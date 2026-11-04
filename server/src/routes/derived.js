import { notFound } from '../errors.js';
import { parseCarId, parseDateRange, parseEnum } from '../params.js';

/**
 * Derived views over TeslaMate's history: consumption by group, regenerative braking, parking
 * sessions and battery health.
 *
 * None of these is a stored table, so each one states its口径 in a comment and returns the raw
 * sample counts next to the estimate. The rules:
 *
 * - Energy is integrated from `positions.power` (kW) over consecutive samples no more than
 *   300 s apart, so a gap while the car slept is not charged to the next segment.
 * - Regeneration only counts while a drive is open: TeslaMate also records power flowing *into*
 *   the battery as negative, so a 5-minute charging sample would otherwise read as regen.
 * - Parking is the gap between drives and charging sessions, at least 10 minutes long. Its
 *   energy comes from the rated range lost, priced at the car's own Wh/km, because a sleeping
 *   car is not sampled and the power integral would undercount by an order of magnitude.
 * - Battery capacity comes from charges spanning at least 40 percentage points: where they end
 *   does not matter, the span is what makes the estimate stable. Charging losses inflate the
 *   figure by roughly 10 %, which the retention ratio cancels.
 */

const MAX_SAMPLE_GAP_SECONDS = 300;
const MIN_PARKING_MINUTES = 10;
const MAX_PARKING_SESSIONS = 60;

async function ensureCar(db, carId) {
  const { rows } = await db.query('SELECT id FROM cars WHERE id = $1', [carId]);
  if (rows.length === 0) throw notFound('Car not found');
}

export function seasonLabel(month) {
  if (month >= 3 && month <= 5) return '春季';
  if (month >= 6 && month <= 8) return '夏季';
  if (month >= 9 && month <= 11) return '秋季';
  return '冬季';
}

export function temperatureLabel(temp) {
  if (temp === null || temp === undefined) return '未知';
  if (temp < 0) return '0°C 以下';
  if (temp < 10) return '0 – 10°C';
  if (temp < 20) return '10 – 20°C';
  if (temp < 30) return '20 – 30°C';
  return '30°C 以上';
}

const SEASON_ORDER = ['春季', '夏季', '秋季', '冬季'];
const TEMPERATURE_ORDER = ['0°C 以下', '0 – 10°C', '10 – 20°C', '20 – 30°C', '30°C 以上', '未知'];

/** Rows → one entry per group, `wh_per_km` weighted by distance. */
export function groupEnergy(rows, group) {
  const buckets = new Map();

  for (const row of rows) {
    const km = Number(row.distance_km ?? 0);
    const kwh = Number(row.kwh ?? 0);
    if (!(km >= 1) || !(kwh > 0)) continue;

    let key;
    let label;
    if (group === 'version') {
      key = row.version ?? '__unknown__';
      label = row.version ?? '未知版本';
    } else if (group === 'season') {
      label = seasonLabel(new Date(row.start_date).getUTCMonth() + 1);
      key = label;
    } else {
      label = temperatureLabel(
        row.outside_temp_avg === null || row.outside_temp_avg === undefined
          ? null
          : Number(row.outside_temp_avg)
      );
      key = label;
    }

    const bucket = buckets.get(key) ?? {
      key,
      label,
      kwh: 0,
      km: 0,
      drive_count: 0,
      from_date: row.start_date,
      to_date: row.start_date
    };

    bucket.kwh += kwh;
    bucket.km += km;
    bucket.drive_count += 1;
    if (row.start_date < bucket.from_date) bucket.from_date = row.start_date;
    if (row.start_date > bucket.to_date) bucket.to_date = row.start_date;
    buckets.set(key, bucket);
  }

  const groups = [...buckets.values()].map((bucket) => ({
    key: bucket.key,
    label: bucket.label,
    wh_per_km: Math.round((bucket.kwh / bucket.km) * 1000),
    km: Math.round(bucket.km * 10) / 10,
    drive_count: bucket.drive_count,
    from_date: bucket.from_date,
    to_date: bucket.to_date
  }));

  if (group === 'version') {
    groups.sort((a, b) => (a.from_date < b.from_date ? 1 : -1));
  } else if (group === 'season') {
    groups.sort((a, b) => SEASON_ORDER.indexOf(a.key) - SEASON_ORDER.indexOf(b.key));
  } else {
    groups.sort((a, b) => TEMPERATURE_ORDER.indexOf(a.key) - TEMPERATURE_ORDER.indexOf(b.key));
  }

  const totalKm = groups.reduce((sum, item) => sum + item.km, 0);
  const totalKwh = [...buckets.values()].reduce((sum, item) => sum + item.kwh, 0);

  // A group needs 5 km before it can be called "best": a 1 km descent would win every time.
  const comparable = groups.filter((item) => item.km >= 5);
  const best = comparable.length > 0
    ? comparable.reduce((lowest, item) => (item.wh_per_km < lowest.wh_per_km ? item : lowest))
    : null;
  const worst = comparable.length > 0
    ? comparable.reduce((highest, item) => (item.wh_per_km > highest.wh_per_km ? item : highest))
    : null;
  const average = totalKm > 0 ? Math.round((totalKwh / totalKm) * 1000) : null;

  return {
    groups,
    total_km: Math.round(totalKm * 10) / 10,
    average_wh_per_km: average,
    best: best && worst && average
      ? {
          key: best.key,
          label: best.label,
          spread_percent: Math.round(((worst.wh_per_km - best.wh_per_km) / average) * 1000) / 10
        }
      : null,
    latest_key: groups.length > 0 && group === 'version' ? groups[0].key : null
  };
}

export async function energy({ db, params, query, now }) {
  const carId = parseCarId(params.id);
  await ensureCar(db, carId);

  const { from, to } = parseDateRange(query, { now, defaultDays: 180 });
  const group = parseEnum(query, 'group', ['version', 'season', 'temperature']);

  const { rows } = await db.query(
    `WITH samples AS (
       SELECT drive_id, power,
              extract(epoch FROM (
                lead(date) OVER (PARTITION BY drive_id ORDER BY date) - date
              )) AS dt
       FROM positions
       WHERE car_id = $1
         AND date >= ($2::timestamptz AT TIME ZONE 'UTC')
         AND date < ($3::timestamptz AT TIME ZONE 'UTC')
         AND drive_id IS NOT NULL
         AND power IS NOT NULL
     ), drive_energy AS (
       SELECT drive_id, sum(power * dt) / 3600.0 AS kwh
       FROM samples
       WHERE dt IS NOT NULL AND dt > 0 AND dt <= $4
       GROUP BY drive_id
     )
     SELECT d.id,
            d.start_date AT TIME ZONE 'UTC' AS start_date,
            d.distance::float8 AS distance_km,
            d.outside_temp_avg::float8 AS outside_temp_avg,
            e.kwh,
            (SELECT u.version
               FROM updates u
              WHERE u.car_id = $1
                AND u.start_date <= d.start_date
                AND (u.end_date IS NULL OR u.end_date > d.start_date)
              ORDER BY u.start_date DESC
              LIMIT 1) AS version
     FROM drives d
     JOIN drive_energy e ON e.drive_id = d.id
     WHERE d.car_id = $1
       AND d.start_date >= ($2::timestamptz AT TIME ZONE 'UTC')
       AND d.start_date < ($3::timestamptz AT TIME ZONE 'UTC')
     ORDER BY d.start_date`,
    [carId, from, to, MAX_SAMPLE_GAP_SECONDS]
  );

  return {
    car_id: carId,
    from: from.toISOString(),
    to: to.toISOString(),
    group,
    ...groupEnergy(rows, group)
  };
}

export async function regen({ db, params, query, now }) {
  const carId = parseCarId(params.id);
  await ensureCar(db, carId);

  const { from, to } = parseDateRange(query, { now, defaultDays: 7 });

  // `drive_id IS NOT NULL` is not an optimisation: TeslaMate also records energy *into* the
  // battery as negative power while charging, and a 5-minute charging sample would otherwise be
  // counted as regeneration. The car only recovers energy while moving.

  const [{ rows: days }, { rows: versions }] = await Promise.all([
    db.query(
      `WITH samples AS (
         SELECT date, power,
                extract(epoch FROM (
                  lead(date) OVER (PARTITION BY drive_id ORDER BY date) - date
                )) AS dt
         FROM positions
         WHERE car_id = $1
           AND date >= ($2::timestamptz AT TIME ZONE 'UTC')
           AND date < ($3::timestamptz AT TIME ZONE 'UTC')
           AND power IS NOT NULL
           AND drive_id IS NOT NULL
       ), daily AS (
         SELECT date_trunc('day', date) AS day,
                COALESCE(sum(CASE WHEN power < 0 THEN -power * dt ELSE 0 END), 0) / 3600.0 AS regen_kwh,
                COALESCE(sum(CASE WHEN power >= 0 THEN power * dt ELSE 0 END), 0) / 3600.0 AS consumed_kwh,
                COALESCE(sum(CASE WHEN power < 0 THEN dt ELSE 0 END), 0) / 60.0 AS minutes,
                COALESCE(-min(power), 0) AS peak_kw
         FROM samples
         WHERE dt IS NOT NULL AND dt > 0 AND dt <= $4
         GROUP BY 1
       )
       SELECT day AT TIME ZONE 'UTC' AS date,
              -- Decided in SQL: comparing the server's local date with a UTC slice of "now"
              -- is wrong as soon as the two sit on either side of midnight.
              day = date_trunc('day', ($5::timestamptz AT TIME ZONE 'UTC')) AS is_today,
              regen_kwh, consumed_kwh, minutes, peak_kw
       FROM daily
       ORDER BY day`,
      [carId, from, to, MAX_SAMPLE_GAP_SECONDS, now]
    ),
    db.query(
      `WITH samples AS (
         SELECT date, power,
                extract(epoch FROM (
                  lead(date) OVER (PARTITION BY drive_id ORDER BY date) - date
                )) AS dt
         FROM positions
         WHERE car_id = $1
           AND date >= ($2::timestamptz AT TIME ZONE 'UTC')
           AND date < ($3::timestamptz AT TIME ZONE 'UTC')
           AND power IS NOT NULL
           AND drive_id IS NOT NULL
       )
       SELECT (SELECT u.version
                 FROM updates u
                WHERE u.car_id = $1
                  AND u.start_date <= samples.date
                  AND (u.end_date IS NULL OR u.end_date > samples.date)
                ORDER BY u.start_date DESC
                LIMIT 1) AS version,
              COALESCE(-min(power), 0) AS peak_kw,
              COALESCE(sum(CASE WHEN power < 0 THEN -power * dt ELSE 0 END), 0) / 3600.0 AS regen_kwh
       FROM samples
       WHERE dt IS NOT NULL AND dt > 0 AND dt <= $4
       GROUP BY 1
       ORDER BY 1 DESC`,
      [carId, from, to, MAX_SAMPLE_GAP_SECONDS]
    )
  ]);

  const normalisedDays = days.map((row) => ({
    date: row.date,
    is_today: row.is_today,
    regen_kwh: round(row.regen_kwh, 2),
    consumed_kwh: round(row.consumed_kwh, 2),
    minutes: Math.round(Number(row.minutes)),
    peak_kw: round(row.peak_kw, 1)
  }));

  const today = normalisedDays.find((day) => day.is_today) ?? null;
  for (const day of normalisedDays) delete day.is_today;

  const totalRegen = normalisedDays.reduce((sum, day) => sum + day.regen_kwh, 0);
  const totalConsumed = normalisedDays.reduce((sum, day) => sum + day.consumed_kwh, 0);

  return {
    car_id: carId,
    from: from.toISOString(),
    to: to.toISOString(),
    today,
    days: normalisedDays,
    total_regen_kwh: round(totalRegen, 2),
    share: totalRegen + totalConsumed > 0 ? round(totalRegen / (totalRegen + totalConsumed), 3) : null,
    week_peak_kw: normalisedDays.reduce((peak, day) => Math.max(peak, day.peak_kw), 0),
    versions: versions.map((row) => ({
      version: row.version,
      peak_kw: round(row.peak_kw, 1),
      regen_kwh: round(row.regen_kwh, 2)
    }))
  };
}

export async function parking({ db, params, query, now }) {
  const carId = parseCarId(params.id);
  await ensureCar(db, carId);

  const { from, to } = parseDateRange(query, { now, defaultDays: 7 });

  const [{ rows }, efficiency] = await Promise.all([
    db.query(
      `WITH events AS (
       SELECT d.start_date AS s, COALESCE(d.end_date, d.start_date) AS e
       FROM drives d
       WHERE d.car_id = $1
         AND d.start_date >= (($2::timestamptz AT TIME ZONE 'UTC') - interval '1 day')
         AND d.start_date < ($3::timestamptz AT TIME ZONE 'UTC')
       UNION ALL
       SELECT c.start_date, COALESCE(c.end_date, c.start_date)
       FROM charging_processes c
       WHERE c.car_id = $1
         AND c.start_date >= (($2::timestamptz AT TIME ZONE 'UTC') - interval '1 day')
         AND c.start_date < ($3::timestamptz AT TIME ZONE 'UTC')
     ), ordered AS (
       SELECT s, e,
              CASE WHEN s <= lag(e) OVER (ORDER BY s, e) THEN 0 ELSE 1 END AS starts
       FROM events
     ), islands AS (
       SELECT min(s) AS start_date, max(e) AS end_date
       FROM (SELECT s, e, sum(starts) OVER (ORDER BY s, e) AS grp FROM ordered) grouped
       GROUP BY grp
     ), gaps AS (
       SELECT lag(end_date) OVER (ORDER BY start_date) AS start_date, start_date AS end_date
       FROM islands
       UNION ALL
       -- The car may still be parked: the time since the last event is a gap too.
       SELECT max(end_date) AS start_date, ($4::timestamptz AT TIME ZONE 'UTC') AS end_date
       FROM islands
       HAVING max(end_date) < ($4::timestamptz AT TIME ZONE 'UTC')
     ), sessions AS (
       SELECT greatest(start_date, ($2::timestamptz AT TIME ZONE 'UTC')) AS start_date,
              least(end_date, ($3::timestamptz AT TIME ZONE 'UTC')) AS end_date
       FROM gaps
       WHERE start_date IS NOT NULL
         AND end_date > ($2::timestamptz AT TIME ZONE 'UTC')
         AND start_date < ($3::timestamptz AT TIME ZONE 'UTC')
     )
     SELECT s.start_date AT TIME ZONE 'UTC' AS start_date,
            s.end_date AT TIME ZONE 'UTC' AS end_date,
            v.start_level, v.end_level, v.start_range_km, v.end_range_km,
            v.odometer_km, v.outside_temp_avg,
            st.states, st.state_minutes,
            loc.place
     FROM sessions s
     LEFT JOIN LATERAL (
       SELECT (array_agg(battery_level ORDER BY date) FILTER (WHERE battery_level IS NOT NULL))[1] AS start_level,
              (array_agg(battery_level ORDER BY date DESC) FILTER (WHERE battery_level IS NOT NULL))[1] AS end_level,
              (array_agg(rated_battery_range_km ORDER BY date) FILTER (WHERE rated_battery_range_km IS NOT NULL))[1] AS start_range_km,
              (array_agg(rated_battery_range_km ORDER BY date DESC) FILTER (WHERE rated_battery_range_km IS NOT NULL))[1] AS end_range_km,
              (array_agg(odometer ORDER BY date DESC) FILTER (WHERE odometer IS NOT NULL))[1]::float8 AS odometer_km,
              avg(outside_temp)::float8 AS outside_temp_avg
       FROM positions
       WHERE car_id = $1 AND date >= s.start_date AND date < s.end_date
     ) v ON true
     LEFT JOIN LATERAL (
       -- Every state gets a share, not just asleep/online: a car whose MQTT link dropped spends
       -- its parking time "offline", and calling that "awake" would overstate the drain.
       SELECT array_agg(per_state.state ORDER BY per_state.minutes DESC) AS states,
              array_agg(round(per_state.minutes) ORDER BY per_state.minutes DESC) AS state_minutes
       FROM (
         SELECT st.state,
                sum(extract(epoch FROM (
                  least(COALESCE(st.end_date, ($4::timestamptz AT TIME ZONE 'UTC')), s.end_date)
                  - greatest(st.start_date, s.start_date)))) / 60.0 AS minutes
         FROM states st
         WHERE st.car_id = $1
           AND st.start_date < s.end_date
           AND (st.end_date IS NULL OR st.end_date > s.start_date)
         GROUP BY st.state
       ) per_state
     ) st ON true
     LEFT JOIN LATERAL (
       SELECT COALESCE(g.name, a.name, a.display_name) AS place
       FROM drives d
       LEFT JOIN geofences g ON g.id = d.end_geofence_id
       LEFT JOIN addresses a ON a.id = d.end_address_id
       WHERE d.car_id = $1 AND d.end_date <= s.start_date
       ORDER BY d.end_date DESC
       LIMIT 1
     ) loc ON true
     WHERE extract(epoch FROM (s.end_date - s.start_date)) >= $5
     ORDER BY s.start_date DESC
     LIMIT $6`,
      [
        carId,
        from,
        to,
        now,
        MIN_PARKING_MINUTES * 60,
        MAX_PARKING_SESSIONS
      ]
    ),
    ratedConsumption(db, carId)
  ]);

  const sessions = rows.map((row) => {
    const durationMin = Math.round(
      (new Date(row.end_date).getTime() - new Date(row.start_date).getTime()) / 60000
    );
    const rangeLossKm =
      row.start_range_km !== null && row.end_range_km !== null
        ? Number(row.start_range_km) - Number(row.end_range_km)
        : null;
    // A parked car is only sampled while awake, so integrating `positions.power` undercounts a
    // night's drain by an order of magnitude. The rated range it lost is measured at both ends
    // of the session, so the estimate uses that, priced with the car's own Wh/km.
    const energyKwh = rangeLossKm !== null && efficiency !== null
      ? Math.max(0, rangeLossKm) * efficiency
      : null;

    return {
      start_date: row.start_date,
      end_date: row.end_date,
      place: row.place,
      duration_min: durationMin,
      energy_kwh: energyKwh === null ? null : round(energyKwh, 3),
      average_power_w: energyKwh !== null && durationMin > 0
        ? Math.round((energyKwh / (durationMin / 60)) * 1000)
        : null,
      start_battery_level: row.start_level,
      end_battery_level: row.end_level,
      start_range_km: row.start_range_km === null ? null : round(row.start_range_km, 1),
      end_range_km: row.end_range_km === null ? null : round(row.end_range_km, 1),
      range_loss_km: rangeLossKm === null ? null : round(rangeLossKm, 1),
      range_loss_per_hour_km: rangeLossKm !== null && durationMin > 0
        ? round(rangeLossKm / (durationMin / 60), 2)
        : null,
      state_minutes: (row.states ?? []).map((state, index) => ({
        state,
        minutes: Math.round(Number(row.state_minutes?.[index] ?? 0))
      })),
      outside_temp_avg: row.outside_temp_avg === null ? null : round(row.outside_temp_avg, 1),
      odometer_km: row.odometer_km
    };
  });

  const totalMinutes = sessions.reduce((sum, item) => sum + item.duration_min, 0);
  const measured = sessions.filter((item) => item.energy_kwh !== null);
  const totalEnergy = measured.reduce((sum, item) => sum + item.energy_kwh, 0);
  const measuredMinutes = measured.reduce((sum, item) => sum + item.duration_min, 0);

  return {
    car_id: carId,
    from: from.toISOString(),
    to: to.toISOString(),
    total_minutes: totalMinutes,
    total_energy_kwh: measured.length > 0 ? round(totalEnergy, 2) : null,
    average_power_w: measuredMinutes > 0
      ? Math.round((totalEnergy / (measuredMinutes / 60)) * 1000)
      : null,
    sessions
  };
}

/// kWh per kilometre of rated range, from the car's own recent full charges. `null` until the
/// car has completed one, which is why parking energy is `null` rather than zero before then.
async function ratedConsumption(db, carId) {
  const { rows } = await db.query(
    `SELECT cp.end_date AT TIME ZONE 'UTC' AS end_date,
            cp.start_battery_level,
            cp.end_battery_level,
            cp.charge_energy_added::float8 AS added,
            cp.end_rated_range_km::float8 AS end_rated
     FROM charging_processes cp
     WHERE cp.car_id = $1
       AND (cp.end_battery_level - cp.start_battery_level) >= 40
       AND cp.charge_energy_added > 5
       AND cp.end_date IS NOT NULL
     ORDER BY cp.start_date DESC
     LIMIT 10`,
    [carId]
  );

  const summary = summariseBattery(rows);
  if (!summary.capacity_kwh || !summary.full_range_km) return null;
  return summary.capacity_kwh / summary.full_range_km;
}

/** Charges that reached ≥ 95 % → capacity and full range. Public for the tests. */
export function batterySamples(rows) {
  const samples = [];

  for (const row of rows) {
    const start = Number(row.start_battery_level);
    const end = Number(row.end_battery_level);
    const added = Number(row.added);
    if (!Number.isFinite(start) || !Number.isFinite(end) || !Number.isFinite(added)) continue;
    if (end - start <= 0 || added <= 0) continue;

    const capacity = added / ((end - start) / 100);
    const range = row.end_rated === null || row.end_rated === undefined
      ? null
      : Number(row.end_rated) / (end / 100);

    // A capacity outside 20–150 kWh is a decoding problem, not a battery.
    if (capacity < 20 || capacity > 150) continue;
    if (range !== null && (range < 100 || range > 1000)) continue;

    samples.push({
      end_date: row.end_date,
      start_battery_level: start,
      end_battery_level: end,
      energy_added_kwh: round(added, 2),
      capacity_kwh: round(capacity, 1),
      full_range_km: range === null ? null : round(range, 0)
    });
  }

  return samples;
}

function median(values) {
  if (values.length === 0) return null;
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 0
    ? (sorted[middle - 1] + sorted[middle]) / 2
    : sorted[middle];
}

export function summariseBattery(rows) {
  const samples = batterySamples(rows);
  if (samples.length === 0) {
    return {
      sample_count: 0,
      capacity_kwh: null,
      full_range_km: null,
      baseline_capacity_kwh: null,
      baseline_range_km: null,
      capacity_retention: null,
      range_retention: null,
      score: null,
      rating: null,
      last_charge_date: null
    };
  }

  // Newest first: the headline is the recent median, the baseline is the best the car ever
  // showed, so a cold week cannot look like permanent degradation.
  const recent = samples.slice(0, 10);
  const capacity = median(recent.map((sample) => sample.capacity_kwh));
  const ranges = recent.map((sample) => sample.full_range_km).filter((value) => value !== null);
  const range = median(ranges);
  const baselineCapacity = Math.max(...samples.map((sample) => sample.capacity_kwh));
  const baselineRange = ranges.length > 0
    ? Math.max(...samples.map((sample) => sample.full_range_km ?? 0))
    : null;

  const capacityRetention = capacity && baselineCapacity ? Math.min(1, capacity / baselineCapacity) : null;
  const rangeRetention = range && baselineRange ? Math.min(1, range / baselineRange) : null;
  const scoreParts = [capacityRetention, rangeRetention].filter((value) => value !== null);
  const score = scoreParts.length > 0
    ? Math.round(Math.min(...scoreParts) * 100)
    : null;

  return {
    sample_count: samples.length,
    capacity_kwh: round(capacity, 1),
    full_range_km: range === null ? null : Math.round(range),
    baseline_capacity_kwh: round(baselineCapacity, 1),
    baseline_range_km: baselineRange === null ? null : Math.round(baselineRange),
    capacity_retention: capacityRetention === null ? null : round(capacityRetention, 3),
    range_retention: rangeRetention === null ? null : round(rangeRetention, 3),
    score,
    // Under three samples the number moves too much to carry a verdict.
    rating: samples.length < 3 || score === null ? null : ratingFor(score),
    last_charge_date: samples[0].end_date
  };
}

export function ratingFor(score) {
  if (score >= 95) return '优秀';
  if (score >= 90) return '良好';
  if (score >= 80) return '偏低';
  return '异常';
}

export async function battery({ db, params }) {
  const carId = parseCarId(params.id);
  await ensureCar(db, carId);

  const [{ rows }, { rows: odometerRows }] = await Promise.all([
    db.query(
      `SELECT cp.end_date AT TIME ZONE 'UTC' AS end_date,
              cp.start_battery_level,
              cp.end_battery_level,
              cp.charge_energy_added::float8 AS added,
              cp.end_rated_range_km::float8 AS end_rated
       FROM charging_processes cp
       WHERE cp.car_id = $1
         AND cp.start_battery_level IS NOT NULL
         AND cp.end_battery_level IS NOT NULL
         AND (cp.end_battery_level - cp.start_battery_level) >= 40
         AND cp.charge_energy_added IS NOT NULL
         AND cp.end_date IS NOT NULL
         AND cp.charge_energy_added > 5
       ORDER BY cp.start_date DESC
       LIMIT 50`,
      [carId]
    ),
    db.query('SELECT max(odometer)::float8 AS odometer_km FROM positions WHERE car_id = $1', [carId])
  ]);

  return {
    car_id: carId,
    ...summariseBattery(rows),
    odometer_km: odometerRows[0]?.odometer_km ?? null
  };
}

function round(value, digits) {
  if (value === null || value === undefined || Number.isNaN(Number(value))) return null;
  const factor = 10 ** digits;
  return Math.round(Number(value) * factor) / factor;
}
