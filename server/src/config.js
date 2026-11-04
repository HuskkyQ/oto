function integer(value, fallback, name, min, max) {
  if (value === undefined || value === null || String(value).trim() === '') return fallback;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < min || parsed > max) {
    throw new Error(`${name} must be an integer between ${min} and ${max}`);
  }
  return parsed;
}

function required(value, name) {
  if (typeof value !== 'string' || value.trim() === '') throw new Error(`${name} is required`);
  return value.trim();
}

export function loadConfig(env = process.env) {
  const apiToken = required(env.API_TOKEN, 'API_TOKEN');
  if (apiToken.length < 24) throw new Error('API_TOKEN must be at least 24 characters');
  const proxyToken = env.PROXY_TOKEN ? required(env.PROXY_TOKEN, 'PROXY_TOKEN') : null;
  if (proxyToken && (proxyToken.length < 24 || proxyToken === apiToken)) {
    throw new Error('PROXY_TOKEN must be at least 24 characters and differ from API_TOKEN');
  }

  return {
    proxyToken,
    port: integer(env.PORT, 8080, 'PORT', 1, 65535),
    apiToken,
    liveStaleMs:
      integer(env.LIVE_STALE_SECONDS, 300, 'LIVE_STALE_SECONDS', 10, 86_400) * 1000,
    database: {
      host: env.DATABASE_HOST || 'database',
      port: integer(env.DATABASE_PORT, 5432, 'DATABASE_PORT', 1, 65535),
      database: env.DATABASE_NAME || 'teslamate',
      user: env.DATABASE_USER || 'teslamate_ro',
      password: required(env.DATABASE_PASS, 'DATABASE_PASS')
    },
    mqtt: {
      host: env.MQTT_HOST || 'mosquitto',
      port: integer(env.MQTT_PORT, 1883, 'MQTT_PORT', 1, 65535)
    }
  };
}
