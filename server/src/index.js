import { loadConfig } from './config.js';
import { createDb } from './db.js';
import { createLiveCache } from './live.js';
import { createHttpServer } from './server.js';

const config = loadConfig();
const db = createDb(config.database);
const live = createLiveCache({
  host: config.mqtt.host,
  port: config.mqtt.port,
  staleAfterMs: config.liveStaleMs
});

live.start();

const server = createHttpServer({ config, db, live });

server.listen(config.port, '0.0.0.0', () => {
  console.log(`teslamate-ios-api listening on :${config.port}`);
});

let shuttingDown = false;

function shutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;
  console.log(`received ${signal}, shutting down`);

  live.stop();
  server.close(() => {
    db.close().finally(() => process.exit(0));
  });

  setTimeout(() => process.exit(1), 10_000).unref();
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
