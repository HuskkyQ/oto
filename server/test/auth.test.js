import assert from 'node:assert/strict';
import test from 'node:test';

import { createRateLimiter, createTokenGuard } from '../src/auth.js';

const TOKEN = 'test-token-0123456789abcdef';

test('token guard accepts the configured bearer token', () => {
  const authorize = createTokenGuard(TOKEN);
  assert.equal(authorize(`Bearer ${TOKEN}`), true);
  assert.equal(authorize(`bearer ${TOKEN}`), true);
});

test('token guard rejects missing, wrong and malformed headers', () => {
  const authorize = createTokenGuard(TOKEN);
  assert.equal(authorize(undefined), false);
  assert.equal(authorize(''), false);
  assert.equal(authorize(TOKEN), false);
  assert.equal(authorize('Bearer wrong'), false);
  assert.equal(authorize(`Basic ${TOKEN}`), false);
});

test('rate limiter blocks after the limit inside the window and resets later', () => {
  let time = 1_000;
  const allow = createRateLimiter({ limit: 2, windowMs: 1_000, now: () => time });

  assert.equal(allow('a'), true);
  assert.equal(allow('a'), true);
  assert.equal(allow('a'), false);
  assert.equal(allow('b'), true);

  time += 1_001;
  assert.equal(allow('a'), true);
});
