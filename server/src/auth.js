import { createHash, timingSafeEqual } from 'node:crypto';

function digest(value) {
  return createHash('sha256').update(String(value)).digest();
}

export function createTokenGuard(token) {
  const expected = digest(token);

  return function authorize(header) {
    const match = /^Bearer\s+(.+)$/i.exec(String(header || '').trim());
    if (!match) return false;
    return timingSafeEqual(digest(match[1].trim()), expected);
  };
}

export function createRateLimiter({
  limit = 120,
  windowMs = 60_000,
  maxKeys = 10_000,
  now = () => Date.now()
} = {}) {
  const buckets = new Map();

  return function allow(key) {
    const time = now();
    const bucket = buckets.get(key);

    if (!bucket || time - bucket.start >= windowMs) {
      if (buckets.size >= maxKeys) {
        for (const [candidate, entry] of buckets) {
          if (time - entry.start >= windowMs) buckets.delete(candidate);
        }
        if (buckets.size >= maxKeys) buckets.delete(buckets.keys().next().value);
      }
      buckets.set(key, { start: time, count: 1 });
      return true;
    }

    bucket.count += 1;
    return bucket.count <= limit;
  };
}
