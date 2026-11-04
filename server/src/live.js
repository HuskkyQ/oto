import mqtt from 'mqtt';

const TOPIC_PATTERN = /^teslamate\/cars\/(\d+)\/([^/]+)$/;

const FIELD_TYPES = {
  state: 'string',
  since: 'string',
  healthy: 'bool',
  version: 'string',
  update_available: 'bool',
  update_version: 'string',
  update_status: 'string',
  download_perc: 'number',
  install_perc: 'number',

  display_name: 'string',
  model: 'string',
  trim_badging: 'string',
  marketing_name: 'string',
  exterior_color: 'string',
  wheel_type: 'string',
  spoiler_type: 'string',
  geofence: 'string',

  latitude: 'number',
  longitude: 'number',
  location: 'json',
  shift_state: 'string',
  power: 'number',
  speed: 'number',
  heading: 'number',
  elevation: 'number',
  odometer: 'number',

  battery_level: 'int',
  usable_battery_level: 'int',
  ideal_battery_range_km: 'number',
  est_battery_range_km: 'number',
  rated_battery_range_km: 'number',
  battery_heater: 'bool',
  battery_heater_on: 'bool',
  battery_heater_no_power: 'bool',

  plugged_in: 'bool',
  charge_port_door_open: 'bool',
  charging_state: 'string',
  charge_energy_added: 'number',
  charge_limit_soc: 'int',
  charger_actual_current: 'number',
  charger_phases: 'int',
  charger_pilot_current: 'number',
  charger_power: 'number',
  charger_voltage: 'number',
  charge_current_request: 'number',
  charge_current_request_max: 'number',
  scheduled_charging_start_time: 'string',
  time_to_full_charge: 'number',

  tpms_pressure_fl: 'number',
  tpms_pressure_fr: 'number',
  tpms_pressure_rl: 'number',
  tpms_pressure_rr: 'number',
  tpms_soft_warning_fl: 'bool',
  tpms_soft_warning_fr: 'bool',
  tpms_soft_warning_rl: 'bool',
  tpms_soft_warning_rr: 'bool',

  active_route_destination: 'string',
  active_route_latitude: 'number',
  active_route_longitude: 'number',
  active_route: 'json',

  center_display_state: 'int',
  service_mode: 'bool',
  locked: 'bool',
  sentry_mode: 'bool',
  windows_open: 'bool',
  driver_front_window_open: 'bool',
  driver_rear_window_open: 'bool',
  passenger_front_window_open: 'bool',
  passenger_rear_window_open: 'bool',
  doors_open: 'bool',
  driver_front_door_open: 'bool',
  driver_rear_door_open: 'bool',
  passenger_front_door_open: 'bool',
  passenger_rear_door_open: 'bool',
  sun_roof_state: 'string',
  sun_roof_installed: 'bool',
  sun_roof_percent_open: 'number',
  trunk_open: 'bool',
  frunk_open: 'bool',

  is_climate_on: 'bool',
  is_preconditioning: 'bool',
  climate_keeper_mode: 'string',
  inside_temp: 'number',
  outside_temp: 'number',
  is_user_present: 'bool',
  fan_status: 'int',
  driver_temp_setting: 'number',
  passenger_temp_setting: 'number',
  is_front_defroster_on: 'bool',
  is_rear_defroster_on: 'bool'
};

export const LIVE_FIELDS = Object.keys(FIELD_TYPES);

function toValue(type, raw) {
  const text = String(raw ?? '').trim();
  if (text === '') return null;

  switch (type) {
    case 'string':
      return text === 'nil' ? null : text;
    case 'number': {
      const value = Number(text);
      return Number.isFinite(value) ? value : null;
    }
    case 'int': {
      const value = Number(text);
      return Number.isInteger(value) ? value : null;
    }
    case 'bool':
      if (text === 'true') return true;
      if (text === 'false') return false;
      return null;
    case 'json':
      try {
        return JSON.parse(text);
      } catch {
        return null;
      }
    default:
      return null;
  }
}

export function createLiveCache({
  host,
  port,
  staleAfterMs = 300_000,
  now = () => Date.now(),
  connect = mqtt.connect,
  logger = console
} = {}) {
  const cars = new Map();
  let client = null;
  let connected = false;
  let lastError = null;

  function ingest(topic, payload, { retain = false } = {}) {
    const match = TOPIC_PATTERN.exec(String(topic));
    if (!match) return false;

    const carId = Number(match[1]);
    const field = match[2];
    if (!(field in FIELD_TYPES)) return false;

    let car = cars.get(carId);
    if (!car) {
      car = { fields: new Map(), lastReceivedAt: null };
      cars.set(carId, car);
    }

    const receivedAt = now();
    car.fields.set(field, { value: toValue(FIELD_TYPES[field], payload), receivedAt, retained: retain });
    car.lastReceivedAt = car.lastReceivedAt === null ? receivedAt : Math.max(car.lastReceivedAt, receivedAt);
    return true;
  }

  function start() {
    if (client) return client;

    client = connect(`mqtt://${host}:${port}`, {
      reconnectPeriod: 5_000,
      connectTimeout: 5_000,
      clean: true,
      clientId: `teslamate-ios-api-${process.pid}`
    });

    client.on('connect', () => {
      connected = true;
      lastError = null;
      client.subscribe('teslamate/cars/+/+', { qos: 1 }, (error) => {
        if (error) logger.error(`mqtt subscribe failed: ${error.message}`);
      });
    });
    client.on('close', () => {
      connected = false;
    });
    client.on('error', (error) => {
      lastError = error.message;
      logger.error(`mqtt error: ${error.message}`);
    });
    client.on('message', (topic, payload, packet) => ingest(topic, payload.toString(), packet));

    return client;
  }

  function stop() {
    if (!client) return;
    const active = client;
    client = null;
    connected = false;
    active.end(true);
  }

  function snapshot(carId) {
    const car = cars.get(carId);
    const values = {};
    const fieldMetadata = {};
    const snapshotAt = now();
    let oldestReceivedAt = null;

    if (car) {
      for (const [field, entry] of car.fields) {
        values[field] = entry.value;
        fieldMetadata[field] = {
          received_at: new Date(entry.receivedAt).toISOString(),
          retained: entry.retained,
          stale: entry.retained || snapshotAt - entry.receivedAt > staleAfterMs
        };
        oldestReceivedAt =
          oldestReceivedAt === null ? entry.receivedAt : Math.min(oldestReceivedAt, entry.receivedAt);
      }
    }

    const receivedAt = car?.lastReceivedAt ?? null;

    return {
      mqtt_connected: connected,
      values,
      received_at: receivedAt === null ? null : new Date(receivedAt).toISOString(),
      oldest_received_at:
        oldestReceivedAt === null ? null : new Date(oldestReceivedAt).toISOString(),
      stale: !connected || receivedAt === null || Object.values(fieldMetadata).some((field) => field.stale),
      field_metadata: fieldMetadata,
      observation_freshness: 'unknown',
      last_error: lastError
    };
  }

  return { start, stop, ingest, snapshot };
}
