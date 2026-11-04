import assert from 'node:assert/strict';
import test from 'node:test';

import {
  batterySamples,
  groupEnergy,
  ratingFor,
  seasonLabel,
  summariseBattery,
  temperatureLabel
} from '../src/routes/derived.js';

function drive(overrides = {}) {
  return {
    start_date: '2026-10-30T08:00:00.000Z',
    distance_km: 50,
    outside_temp_avg: 15,
    kwh: 8,
    version: '2026.40',
    ...overrides
  };
}

test('energy groups skip drives shorter than a kilometre and drives without energy', () => {
  const result = groupEnergy(
    [
      drive(),
      drive({ distance_km: 0.4, kwh: 1 }),
      drive({ kwh: 0 })
    ],
    'season'
  );

  assert.equal(result.groups.length, 1);
  assert.equal(result.groups[0].label, '秋季');
  assert.equal(result.groups[0].drive_count, 1);
  assert.equal(result.total_km, 50);
  assert.equal(result.average_wh_per_km, 160);
});

test('energy weights capacity by distance, not by drive count', () => {
  const result = groupEnergy(
    [
      drive({ distance_km: 100, kwh: 20 }),
      drive({ distance_km: 10, kwh: 5 })
    ],
    'season'
  );

  assert.equal(result.groups[0].wh_per_km, 227);
  assert.equal(result.groups[0].km, 110);
});

test('best and worst ignore groups under five kilometres', () => {
  const result = groupEnergy(
    [
      drive({ version: 'A', start_date: '2026-06-01T00:00:00.000Z', distance_km: 100, kwh: 20 }),
      drive({ version: 'B', start_date: '2026-07-01T00:00:00.000Z', distance_km: 100, kwh: 24 }),
      drive({ version: 'C', start_date: '2026-08-01T00:00:00.000Z', distance_km: 2, kwh: 0.1 })
    ],
    'version'
  );

  assert.equal(result.best.key, 'A');
  assert.equal(result.groups.find((group) => group.key === 'C').wh_per_km, 50);
  assert.equal(result.latest_key, 'C');
});

test('version groups fall back to a label when TeslaMate has no update record', () => {
  const result = groupEnergy([drive({ version: null })], 'version');
  assert.equal(result.groups[0].label, '未知版本');
});

test('season and temperature buckets cover the year', () => {
  assert.equal(seasonLabel(1), '冬季');
  assert.equal(seasonLabel(3), '春季');
  assert.equal(seasonLabel(7), '夏季');
  assert.equal(seasonLabel(11), '秋季');

  assert.equal(temperatureLabel(-3), '0°C 以下');
  assert.equal(temperatureLabel(5), '0 – 10°C');
  assert.equal(temperatureLabel(15), '10 – 20°C');
  assert.equal(temperatureLabel(25), '20 – 30°C');
  assert.equal(temperatureLabel(35), '30°C 以上');
  assert.equal(temperatureLabel(null), '未知');
});

function charge(overrides = {}) {
  return {
    end_date: '2026-10-01T10:00:00.000Z',
    start_battery_level: 20,
    end_battery_level: 100,
    added: 60,
    end_rated: 375,
    ...overrides
  };
}

test('battery samples drop charging sessions a capacity estimate cannot trust', () => {
  const samples = batterySamples([
    charge(),
    charge({ added: 200 }), // 0 → 100 % is not a real capacity
    charge({ start_battery_level: 100 }), // charged nothing
    charge({ end_battery_level: 80, added: 40 }), // still 50 kWh, accepted
    charge({ end_rated: 40 }) // 40 km at 100 % is a decoding error
  ]);

  assert.equal(samples.length, 2);
  assert.equal(samples[0].capacity_kwh, 75);
  assert.equal(samples[0].full_range_km, 375);
  assert.equal(samples[1].capacity_kwh, 66.7);
});

test('battery health compares the recent median against the best ever seen', () => {
  const rows = [
    charge({ added: 48 }),
    charge({ added: 48 }),
    charge({ added: 48 }),
    charge({ added: 60 }),
    charge({ added: 60 }),
    charge({ added: 60 })
  ];

  const summary = summariseBattery(rows);
  assert.equal(summary.sample_count, 6);
  assert.equal(summary.capacity_kwh, 67.5);
  assert.equal(summary.baseline_capacity_kwh, 75);
  assert.equal(summary.capacity_retention, 0.9);
  assert.equal(summary.score, 90);
  assert.equal(summary.rating, '良好');
  assert.equal(summary.last_charge_date, '2026-10-01T10:00:00.000Z');
});

test('battery health refuses to rate two charges', () => {
  const summary = summariseBattery([charge(), charge()]);
  assert.equal(summary.sample_count, 2);
  assert.equal(summary.score, 100);
  assert.equal(summary.rating, null);
});

test('battery health reports nothing rather than zero without samples', () => {
  const summary = summariseBattery([]);
  assert.equal(summary.sample_count, 0);
  assert.equal(summary.score, null);
  assert.equal(summary.rating, null);
});

test('ratings follow the documented thresholds', () => {
  assert.equal(ratingFor(96), '优秀');
  assert.equal(ratingFor(95), '优秀');
  assert.equal(ratingFor(94), '良好');
  assert.equal(ratingFor(90), '良好');
  assert.equal(ratingFor(89), '偏低');
  assert.equal(ratingFor(80), '偏低');
  assert.equal(ratingFor(79), '异常');
});
