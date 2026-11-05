#!/usr/bin/env node
/**
 * Fills TeslaMate's `addresses` table from AMap's reverse geocoder.
 *
 * TeslaMate geocodes through nominatim.openstreetmap.org, which this server
 * cannot reach (every request times out), so most drives keep a null
 * start/end address and the app falls back to "未知地点". AMap is domestic and
 * answers in tens of milliseconds, and its addresses are Chinese, which suits
 * this app better than the English Nominatim output.
 *
 * Runs on the host and reaches PostgreSQL through `docker exec ... psql`, so it
 * needs no driver and no network exposure of the database port. Only drives
 * whose address id is still null are touched: re-running is safe.
 *
 * Usage:
 *   AMAP_KEY=... node backfill-addresses.mjs --dry-run   # list, write nothing
 *   AMAP_KEY=... node backfill-addresses.mjs             # backfill
 */
import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';

const run = promisify(execFile);

const DB_CONTAINER = process.env.DB_CONTAINER || 'teslamate-database-1';
const DB_NAME = process.env.DB_NAME || 'teslamate';
const DB_USER = process.env.DB_USER || 'teslamate';
const AMAP_KEY = process.env.AMAP_KEY;
const DRY_RUN = process.argv.includes('--dry-run');
// AMap asks for no more than a few calls per second per key.
const REQUEST_GAP_MS = 350;

if (!AMAP_KEY && !DRY_RUN) {
  console.error('AMAP_KEY is required (Web服务 platform key)');
  process.exit(1);
}

function psqlArgs(...extra) {
  return [
    'exec', DB_CONTAINER, 'psql', '-U', DB_USER, '-d', DB_NAME,
    '-v', 'ON_ERROR_STOP=1', ...extra
  ];
}

async function query(text) {
  const { stdout } = await run('docker', psqlArgs('-t', '-A', '-F', '\t', '-c', text), {
    maxBuffer: 16 * 1024 * 1024
  });
  return stdout.split('\n').filter((line) => line !== '').map((line) => line.split('\t'));
}

/// The whole batch is one script, and the raw geocoder JSON makes it far too
/// large for an argv entry, so it goes in over stdin.
function execute(text) {
  return new Promise((resolve, reject) => {
    const child = spawn(
      'docker',
      ['exec', '-i', DB_CONTAINER, 'psql', '-U', DB_USER, '-d', DB_NAME, '-v', 'ON_ERROR_STOP=1', '-q']
    );
    child.on('error', reject);
    child.on('close', (code) => {
      if (code === 0) resolve();
      else reject(new Error(`psql exited with ${code}`));
    });
    child.stdin.end(text);
  });
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/// WGS-84 → GCJ-02, the same transform the app applies at render time.
const A = 6_378_245.0;
const EE = 0.006_693_421_622_965_943;

function isOutsideChina(lat, lon) {
  return lon < 72.004 || lon > 137.8347 || lat < 0.8293 || lat > 55.8271;
}

function transformLat(x, y) {
  let ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * Math.sqrt(Math.abs(x));
  ret += (20.0 * Math.sin(6.0 * x * Math.PI) + 20.0 * Math.sin(2.0 * x * Math.PI)) * 2.0 / 3.0;
  ret += (20.0 * Math.sin(y * Math.PI) + 40.0 * Math.sin(y / 3.0 * Math.PI)) * 2.0 / 3.0;
  ret += (160.0 * Math.sin(y / 12.0 * Math.PI) + 320.0 * Math.sin(y * Math.PI / 30.0)) * 2.0 / 3.0;
  return ret;
}

function transformLon(x, y) {
  let ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * Math.sqrt(Math.abs(x));
  ret += (20.0 * Math.sin(6.0 * x * Math.PI) + 20.0 * Math.sin(2.0 * x * Math.PI)) * 2.0 / 3.0;
  ret += (20.0 * Math.sin(x * Math.PI) + 40.0 * Math.sin(x / 3.0 * Math.PI)) * 2.0 / 3.0;
  ret += (150.0 * Math.sin(x / 12.0 * Math.PI) + 300.0 * Math.sin(x / 30.0 * Math.PI)) * 2.0 / 3.0;
  return ret;
}

function gcj02(lat, lon) {
  if (isOutsideChina(lat, lon)) return { lat, lon };

  const dLat0 = transformLat(lon - 105.0, lat - 35.0);
  const dLon0 = transformLon(lon - 105.0, lat - 35.0);
  const radLat = lat / 180.0 * Math.PI;
  const magic = 1 - EE * Math.sin(radLat) ** 2;
  const sqrtMagic = Math.sqrt(magic);

  return {
    lat: lat + (dLat0 * 180.0) / ((A * (1 - EE)) / (magic * sqrtMagic) * Math.PI),
    lon: lon + (dLon0 * 180.0) / (A / sqrtMagic * Math.cos(radLat) * Math.PI)
  };
}

function quote(value) {
  if (value === null || value === undefined) return 'null';
  return `'${String(value).replaceAll("'", "''")}'`;
}

async function regeo(lat, lon) {
  const point = gcj02(lat, lon);
  const url = 'https://restapi.amap.com/v3/geocode/regeo'
    + `?key=${AMAP_KEY}`
    // AMap takes longitude first.
    + `&location=${point.lon.toFixed(6)},${point.lat.toFixed(6)}`
    + '&extensions=all';

  const response = await fetch(url, { signal: AbortSignal.timeout(10_000) });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);

  const body = await response.json();
  if (body.status !== '1' || !body.regeocode) {
    throw new Error(`${body.info || 'unknown error'} (${body.infocode || '?'})`);
  }
  return body.regeocode;
}

/// AMap answers with `[]` where an optional field is absent, so the empty
/// array has to collapse to null before it reaches the database.
function text(value) {
  return typeof value === 'string' && value.trim() !== '' ? value : null;
}

/// Short label for the app's one-line row. The closest AOI (the compound, mall
/// or campus the car is parked in) reads better than the road it sits on, but
/// only when the car is actually inside or beside it.
function shortName(regeocode) {
  const aoi = (regeocode.aois || [])
    .filter((candidate) => Number(candidate.distance) <= 80)
    .sort((a, b) => Number(a.distance) - Number(b.distance))[0];
  if (text(aoi?.name)) return aoi.name;

  const component = regeocode.addressComponent || {};
  return text(component.streetNumber?.street)
    || text(component.neighborhood?.name)
    || text(component.township)
    || text(regeocode.formatted_address);
}

async function main() {
  // Every drive still missing an address, one row per endpoint, with the
  // coordinates of its first/last position.
  const rows = await query(`
    select d.id, 'start', p.latitude, p.longitude
      from drives d join positions p on p.id = d.start_position_id
     where d.start_address_id is null
    union all
    select d.id, 'end', p.latitude, p.longitude
      from drives d join positions p on p.id = d.end_position_id
     where d.end_address_id is null`);

  if (rows.length === 0) {
    console.log('nothing to backfill');
    return;
  }

  // Many drives start where another one ended, so ask AMap once per point.
  const points = new Map();
  for (const [driveId, side, lat, lon] of rows) {
    const key = `${Number(lat).toFixed(6)},${Number(lon).toFixed(6)}`;
    let point = points.get(key);
    if (!point) {
      point = { lat: Number(lat), lon: Number(lon), starts: [], ends: [] };
      points.set(key, point);
    }
    (side === 'start' ? point.starts : point.ends).push(Number(driveId));
  }

  const endpoints = rows.length;
  console.log(
    `${endpoints} endpoints across ${new Set(rows.map((r) => r[0])).size} drives `
    + `resolve to ${points.size} distinct coordinates`
  );

  const outside = [...points.values()].filter((p) => isOutsideChina(p.lat, p.lon));
  for (const point of outside) {
    console.log(`skip (outside China): ${point.lat},${point.lon}`);
  }

  if (DRY_RUN) {
    let index = 0;
    for (const point of points.values()) {
      if (outside.includes(point)) continue;
      index += 1;
      const g = gcj02(point.lat, point.lon);
      console.log(
        `${index}. wgs ${point.lat.toFixed(6)},${point.lon.toFixed(6)} `
        + `→ gcj ${g.lat.toFixed(6)},${g.lon.toFixed(6)} `
        + `(starts ${point.starts.length}, ends ${point.ends.length})`
      );
    }
    console.log('dry run: nothing written');
    return;
  }

  const statements = ['begin;'];
  let done = 0;
  let addressable = 0;
  const failures = [];

  for (const point of points.values()) {
    if (outside.includes(point)) continue;
    addressable += 1;

    let regeocode;
    try {
      regeocode = await regeo(point.lat, point.lon);
    } catch (error) {
      failures.push(`${point.lat},${point.lon}: ${error.message}`);
      console.error(`[${addressable}/${points.size}] failed ${point.lat},${point.lon}: ${error.message}`);
      await sleep(REQUEST_GAP_MS);
      continue;
    }

    const component = regeocode.addressComponent || {};
    const displayName = text(regeocode.formatted_address);
    const name = shortName(regeocode);
    // 直辖市 report no city, only a province.
    const city = text(component.city) || text(component.province);

    const updates = [];
    if (point.starts.length) {
      updates.push(`update drives set start_address_id = aid where id in (${point.starts.join(',')});`);
    }
    if (point.ends.length) {
      updates.push(`update drives set end_address_id = aid where id in (${point.ends.join(',')});`);
    }

    statements.push(`do $$
declare aid integer;
begin
  insert into addresses
    (display_name, latitude, longitude, name, road, neighbourhood, city,
     state, state_district, country, raw, inserted_at, updated_at)
  values
    (${quote(displayName)}, ${point.lat.toFixed(6)}, ${point.lon.toFixed(6)},
     ${quote(name)}, ${quote(text(component.streetNumber?.street))},
     ${quote(text(component.neighborhood?.name))}, ${quote(city)},
     ${quote(text(component.province))}, ${quote(text(component.district))},
     ${quote(text(component.country))}, ${quote(JSON.stringify(regeocode))}::jsonb,
     (now() at time zone 'utc'), (now() at time zone 'utc'))
  returning id into aid;
  ${updates.join('\n  ')}
end $$;`);

    done += point.starts.length + point.ends.length;
    console.log(`[${addressable}/${points.size}] ${displayName}`);
    await sleep(REQUEST_GAP_MS);
  }

  if (!DRY_RUN && statements.length > 1) {
    statements.push('commit;');
    await execute(statements.join('\n'));
  }

  console.log(`updated ${done} endpoints; ${failures.length} failed`);
  if (failures.length) process.exitCode = 1;
}

await main();
