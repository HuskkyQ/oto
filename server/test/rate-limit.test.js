import assert from 'node:assert/strict';
import test from 'node:test';
import { createHttpServer } from '../src/server.js';
import { loadConfig } from '../src/config.js';

test('proxy authentication key must be distinct and sufficiently long', () => {
  const env = { API_TOKEN: 'a'.repeat(32), DATABASE_PASS: 'fixture', PROXY_TOKEN: 'b'.repeat(32) };
  assert.equal(loadConfig(env).proxyToken, env.PROXY_TOKEN);
  assert.throws(() => loadConfig({ ...env, PROXY_TOKEN: 'short' }));
  assert.throws(() => loadConfig({ ...env, PROXY_TOKEN: env.API_TOKEN }));
});

async function withServer(run, config = {}) {
  const server = createHttpServer({
    config: { apiToken: 'test-token', ...config },
    db: { async query() { return { rows: [{ id: 1 }] }; } },
    live: { snapshot() { return {}; } },
    logger: { info() {}, error() {} }
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  try {
    await run(base);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

async function request(base, path, token = 'test-token', headers = {}) {
  const response = await fetch(`${base}${path}`, { headers: { authorization: `Bearer ${token}`, ...headers } });
  await response.body?.cancel();
  return response.status;
}

test('live requests count towards the total request limit', async () => {
  await withServer(async (base) => {
    for (let i = 0; i < 60; i++) assert.equal(await request(base, '/v1/cars/1/live'), 200);
    for (let i = 0; i < 60; i++) assert.equal(await request(base, '/v1/cars'), 200);
    assert.equal(await request(base, '/v1/cars'), 429);
  });
});

test('invalid tokens are subject to the total request limit', async () => {
  await withServer(async (base) => {
    for (let i = 0; i < 120; i++) assert.equal(await request(base, '/v1/cars', 'invalid'), 401);
    assert.equal(await request(base, '/v1/cars', 'invalid'), 429);
  });
});

test('authenticated proxy identifies distinct clients', async () => {
  await withServer(async (base) => {
    const proxy = { 'x-odo-proxy-token': 'proxy-test-key', 'x-odo-client-ip': '192.0.2.1' };
    for (let i = 0; i < 120; i++) assert.equal(await request(base, '/v1/cars', undefined, proxy), 200);
    assert.equal(await request(base, '/v1/cars', undefined, proxy), 429);
    assert.equal(await request(base, '/v1/cars', undefined, { ...proxy, 'x-odo-client-ip': '192.0.2.2' }), 200);
  }, { proxyToken: 'proxy-test-key' });
});

test('untrusted forwarded identities cannot bypass the socket limit', async () => {
  await withServer(async (base) => {
    for (let i = 0; i < 120; i++) {
      const headers = { 'x-odo-proxy-token': 'invalid', 'x-odo-client-ip': `192.0.2.${i + 1}` };
      assert.equal(await request(base, '/v1/cars', undefined, headers), 200);
    }
    assert.equal(await request(base, '/v1/cars', undefined, {
      'x-odo-proxy-token': 'invalid', 'x-odo-client-ip': '192.0.2.200'
    }), 429);
  }, { proxyToken: 'proxy-test-key' });
});

test('malformed client IP falls back to the socket address', async () => {
  await withServer(async (base) => {
    const headers = { 'x-odo-proxy-token': 'proxy-test-key', 'x-odo-client-ip': '192.0.2.1, 192.0.2.2' };
    for (let i = 0; i < 120; i++) assert.equal(await request(base, '/v1/cars', undefined, headers), 200);
    assert.equal(await request(base, '/v1/cars'), 429);
  }, { proxyToken: 'proxy-test-key' });
});

test('live requests have their own additional limit', async () => {
  await withServer(async (base) => {
    for (let i = 0; i < 60; i++) assert.equal(await request(base, '/v1/cars/1/live'), 200);
    assert.equal(await request(base, '/v1/cars/1/live'), 429);
    assert.equal(await request(base, '/v1/cars'), 200);
  });
});
