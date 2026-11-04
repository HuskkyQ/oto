import assert from 'node:assert/strict';
import test from 'node:test';

import { createLiveCache } from '../src/live.js';

function fakeClient() {
  const handlers = new Map();
  return {
    on(event, handler) {
      handlers.set(event, handler);
      return this;
    },
    subscribe() {},
    end() {},
    emit(event, ...args) {
      handlers.get(event)?.(...args);
    }
  };
}

test('ingest types values and ignores unknown topics and fields', () => {
  let now = 1_000;
  const client = fakeClient();
  const live = createLiveCache({ now: () => now, connect: () => client });
  live.start();
  client.emit('connect');

  assert.equal(live.ingest('teslamate/cars/1/battery_level', '77'), true);
  assert.equal(live.ingest('teslamate/cars/1/locked', 'true'), true);
  assert.equal(live.ingest('teslamate/cars/1/location', '{"latitude":1.5,"longitude":2.5}'), true);
  assert.equal(live.ingest('teslamate/cars/1/not_a_field', 'x'), false);
  assert.equal(live.ingest('other/topic', 'x'), false);

  const snapshot = live.snapshot(1);
  assert.equal(snapshot.values.battery_level, 77);
  assert.equal(snapshot.values.locked, true);
  assert.deepEqual(snapshot.values.location, { latitude: 1.5, longitude: 2.5 });
  assert.equal(snapshot.stale, false);
  assert.equal(snapshot.received_at, new Date(now).toISOString());
});

test('empty payloads are observations of null', () => {
  const client = fakeClient();
  const live = createLiveCache({ now: () => 1_000, connect: () => client });
  live.start();
  client.emit('connect');
  live.ingest('teslamate/cars/1/speed', '');
  live.ingest('teslamate/cars/1/shift_state', '');

  const snapshot = live.snapshot(1);
  assert.equal(snapshot.values.speed, null);
  assert.equal(snapshot.values.shift_state, null);
  assert.equal(snapshot.stale, false);
});

test('snapshot becomes stale after the configured age', () => {
  let now = 1_000;
  const live = createLiveCache({ now: () => now, staleAfterMs: 5_000, connect: fakeClient });
  live.ingest('teslamate/cars/1/battery_level', '10');

  now += 5_001;
  const snapshot = live.snapshot(1);
  assert.equal(snapshot.stale, true);
  assert.equal(snapshot.values.battery_level, 10);
});

test('retained delivery has unknown observation freshness', () => {
  const client = fakeClient();
  const live = createLiveCache({ now: () => 1_000, connect: () => client });
  live.start();
  client.emit('message', 'teslamate/cars/1/battery_level', Buffer.from('77'), { retain: true });

  const snapshot = live.snapshot(1);
  assert.equal(snapshot.values.battery_level, 77);
  assert.equal(snapshot.received_at, new Date(1_000).toISOString());
  assert.equal(snapshot.stale, true);
  assert.deepEqual(snapshot.field_metadata.battery_level, {
    received_at: new Date(1_000).toISOString(), retained: true, stale: true
  });
  assert.equal(snapshot.observation_freshness, 'unknown');
});

test('a recent message does not make older fields fresh', () => {
  let now = 1_000;
  const live = createLiveCache({ now: () => now, staleAfterMs: 5_000, connect: fakeClient });
  live.ingest('teslamate/cars/1/battery_level', '77');
  now += 5_001;
  live.ingest('teslamate/cars/1/state', 'online');

  const snapshot = live.snapshot(1);
  assert.equal(snapshot.stale, true);
  assert.equal(snapshot.field_metadata.battery_level.stale, true);
  assert.equal(snapshot.field_metadata.state.stale, false);
  assert.equal(snapshot.observation_freshness, 'unknown');
});

test('a disconnected broker makes the snapshot stale', () => {
  const client = fakeClient();
  const live = createLiveCache({ now: () => 1_000, connect: () => client });
  live.start();
  client.emit('connect');
  client.emit('message', 'teslamate/cars/1/battery_level', Buffer.from('77'), { retain: false });
  assert.equal(live.snapshot(1).stale, false);
  client.emit('close');
  assert.equal(live.snapshot(1).stale, true);
});

test('unknown cars return an empty snapshot', () => {
  const live = createLiveCache({ now: () => 1_000, connect: fakeClient });
  const snapshot = live.snapshot(9);
  assert.deepEqual(snapshot.values, {});
  assert.equal(snapshot.received_at, null);
  assert.equal(snapshot.stale, true);
});
