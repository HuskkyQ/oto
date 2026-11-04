import { createServer } from 'node:http';
import { isIP } from 'node:net';

import { createRateLimiter, createTokenGuard } from './auth.js';
import { HttpError, methodNotAllowed, unauthorized } from './errors.js';
import * as derived from './routes/derived.js';
import * as history from './routes/history.js';

const ROUTES = [
  { method: 'GET', pattern: /^\/healthz$/, public: true, handler: () => ({ ok: true }) },
  { method: 'GET', pattern: /^\/v1\/cars$/, handler: history.listCars },
  {
    method: 'GET',
    pattern: /^\/v1\/cars\/(?<id>\d+)\/live$/,
    live: true,
    handler: history.liveSummary
  },
  { method: 'GET', pattern: /^\/v1\/cars\/(?<id>\d+)\/positions$/, handler: history.listPositions },
  { method: 'GET', pattern: /^\/v1\/cars\/(?<id>\d+)\/drives$/, handler: history.listDrives },
  {
    method: 'GET',
    pattern: /^\/v1\/cars\/(?<id>\d+)\/drives\/(?<driveId>\d+)$/,
    handler: history.getDrive
  },
  { method: 'GET', pattern: /^\/v1\/cars\/(?<id>\d+)\/charges$/, handler: history.listCharges },
  {
    method: 'GET',
    pattern: /^\/v1\/cars\/(?<id>\d+)\/charges\/(?<chargeId>\d+)$/,
    handler: history.getCharge
  },
  { method: 'GET', pattern: /^\/v1\/cars\/(?<id>\d+)\/states$/, handler: history.listStates },
  { method: 'GET', pattern: /^\/v1\/cars\/(?<id>\d+)\/updates$/, handler: history.listUpdates },
  { method: 'GET', pattern: /^\/v1\/cars\/(?<id>\d+)\/stats$/, handler: history.stats },
  { method: 'GET', pattern: /^\/v1\/cars\/(?<id>\d+)\/energy$/, handler: derived.energy },
  { method: 'GET', pattern: /^\/v1\/cars\/(?<id>\d+)\/regen$/, handler: derived.regen },
  { method: 'GET', pattern: /^\/v1\/cars\/(?<id>\d+)\/parking$/, handler: derived.parking },
  { method: 'GET', pattern: /^\/v1\/cars\/(?<id>\d+)\/battery$/, handler: derived.battery }
];

function sendJson(res, status, body) {
  const payload = JSON.stringify(body);
  res.statusCode = status;
  res.setHeader('content-type', 'application/json; charset=utf-8');
  res.setHeader('cache-control', 'no-store');
  res.setHeader('x-content-type-options', 'nosniff');
  res.setHeader('referrer-policy', 'no-referrer');
  res.end(payload);
}

export function createHttpServer({
  config,
  db,
  live,
  logger = console,
  now = () => new Date()
}) {
  const authorize = createTokenGuard(config.apiToken);
  const authorizeProxy = config.proxyToken ? createTokenGuard(config.proxyToken) : null;
  const allowRequest = createRateLimiter({ limit: 120, windowMs: 60_000 });
  const allowLiveRequest = createRateLimiter({ limit: 60, windowMs: 60_000 });

  const server = createServer(async (req, res) => {
    const started = Date.now();
    let path = '/';

    try {
      let url;
      try {
        url = new URL(req.url || '/', 'http://localhost');
      } catch {
        return sendJson(res, 400, { error: 'Bad request', code: 'BAD_REQUEST' });
      }

      path = url.pathname;
      const route = ROUTES.find((candidate) => candidate.pattern.test(path));

      if (!route) {
        return sendJson(res, 404, { error: 'Not found', code: 'NOT_FOUND' });
      }

      if (req.method !== route.method) {
        res.setHeader('allow', route.method);
        throw methodNotAllowed();
      }

      if (!route.public) {
        const proxyToken = req.headers['x-odo-proxy-token'];
        const forwardedIp = req.headers['x-odo-client-ip'];
        const trustedProxy = typeof proxyToken === 'string' && authorizeProxy?.(`Bearer ${proxyToken}`);
        const client = trustedProxy && typeof forwardedIp === 'string' && isIP(forwardedIp)
          ? forwardedIp
          : req.socket.remoteAddress || 'unknown';
        if (!allowRequest(client)) {
          return sendJson(res, 429, { error: 'Too many requests', code: 'RATE_LIMITED' });
        }
        if (!authorize(req.headers.authorization)) throw unauthorized();
        if (route.live && !allowLiveRequest(client)) {
          return sendJson(res, 429, { error: 'Too many requests', code: 'RATE_LIMITED' });
        }
      }

      const match = route.pattern.exec(path);
      const params = match?.groups ?? {};
      const body = await route.handler({
        db,
        live,
        params,
        query: url.searchParams,
        now: now()
      });

      if (!res.writableEnded) sendJson(res, 200, body);
    } catch (error) {
      if (error instanceof HttpError) {
        return sendJson(res, error.status, { error: error.message, code: error.code });
      }

      logger.error(`request failed: ${error.message}`);
      if (!res.writableEnded) {
        sendJson(res, 500, { error: 'Internal server error', code: 'INTERNAL_ERROR' });
      }
    } finally {
      logger.info(`${req.method} ${path} ${res.statusCode} ${Date.now() - started}ms`);
    }
  });

  return server;
}
