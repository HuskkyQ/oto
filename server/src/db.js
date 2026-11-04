import pg from 'pg';

export function createDb(config, { logger = console } = {}) {
  const pool = new pg.Pool({
    host: config.host,
    port: config.port,
    database: config.database,
    user: config.user,
    password: config.password,
    max: 4,
    idleTimeoutMillis: 30_000,
    connectionTimeoutMillis: 5_000,
    application_name: 'teslamate-ios-api',
    options: '-c timezone=UTC'
  });

  pool.on('error', (error) => {
    logger.error(`postgres pool error: ${error.message}`);
  });

  return {
    query: (text, values) => pool.query(text, values),
    close: () => pool.end()
  };
}
