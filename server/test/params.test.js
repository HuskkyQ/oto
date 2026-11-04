import assert from 'node:assert/strict';
import test from 'node:test';

import {
  parseCarId,
  parseDateRange,
  parseEnum,
  parseInteger,
  parseResourceId
} from '../src/params.js';

const now = new Date('2026-11-02T12:00:00.000Z');
const query = (values) => new URLSearchParams(values);

test('parseCarId accepts positive integers and rejects everything else', () => {
  assert.equal(parseCarId('1'), 1);
  assert.throws(() => parseCarId('0abc'), { status: 404 });
  assert.throws(() => parseCarId('-1'), { status: 404 });
});

test('parseResourceId rejects malformed ids with 400', () => {
  assert.equal(parseResourceId('42', 'drive id'), 42);
  assert.throws(() => parseResourceId('x', 'drive id'), { status: 400 });
});

test('parseDateRange defaults to the last 30 days', () => {
  const { from, to } = parseDateRange(query({}), { now });
  assert.equal(to.toISOString(), now.toISOString());
  assert.equal(from.toISOString(), '2026-10-03T12:00:00.000Z');
});

test('parseDateRange rejects inverted, malformed and oversized ranges', () => {
  assert.throws(
    () => parseDateRange(query({ from: '2026-11-02', to: '2026-11-01' }), { now }),
    { status: 400, code: 'INVALID_RANGE' }
  );
  assert.throws(() => parseDateRange(query({ from: 'not-a-date' }), { now }), {
    status: 400,
    code: 'INVALID_DATE'
  });
  assert.throws(
    () => parseDateRange(query({ from: '2020-01-01', to: '2026-01-01' }), { now }),
    { status: 400, code: 'RANGE_TOO_LARGE' }
  );
});

test('parseInteger enforces bounds', () => {
  assert.equal(parseInteger(query({ limit: '10' }), 'limit', { fallback: 1, min: 1, max: 20 }), 10);
  assert.throws(() => parseInteger(query({ limit: '50' }), 'limit', { fallback: 1, min: 1, max: 20 }));
  assert.throws(() => parseInteger(query({ limit: '1.5' }), 'limit', { fallback: 1, min: 1, max: 20 }));
});

test('parseEnum only accepts listed values', () => {
  assert.equal(parseEnum(query({}), 'bucket', ['day', 'month']), 'day');
  assert.equal(parseEnum(query({ bucket: 'month' }), 'bucket', ['day', 'month']), 'month');
  assert.throws(() => parseEnum(query({ bucket: 'week' }), 'bucket', ['day', 'month']));
});
