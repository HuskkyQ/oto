import { HttpError } from './errors.js';

const DAY_MS = 86_400_000;

export function parseCarId(raw) {
  if (!/^\d{1,10}$/.test(String(raw ?? ''))) {
    throw new HttpError(404, 'Car not found', 'NOT_FOUND');
  }
  return Number(raw);
}

export function parseResourceId(raw, name) {
  if (!/^\d{1,10}$/.test(String(raw ?? ''))) {
    throw new HttpError(400, `invalid ${name}`, 'INVALID_PARAMETER');
  }
  return Number(raw);
}

function parseDate(raw, fallback, name) {
  if (raw === null || raw === undefined || String(raw).trim() === '') return fallback;
  const date = new Date(raw);
  if (Number.isNaN(date.getTime())) throw new HttpError(400, `invalid ${name}`, 'INVALID_DATE');
  return date;
}

export function parseDateRange(query, { now = new Date(), defaultDays = 30, maxDays = 366 } = {}) {
  const to = parseDate(query.get('to'), now, 'to');
  const from = parseDate(query.get('from'), new Date(to.getTime() - defaultDays * DAY_MS), 'from');

  if (from >= to) throw new HttpError(400, 'from must be before to', 'INVALID_RANGE');
  if (to.getTime() - from.getTime() > maxDays * DAY_MS) {
    throw new HttpError(400, `range must not exceed ${maxDays} days`, 'RANGE_TOO_LARGE');
  }

  return { from, to };
}

export function parseInteger(query, name, { fallback, min, max }) {
  const raw = query.get(name);
  if (raw === null || String(raw).trim() === '') return fallback;

  const value = Number(raw);
  if (!Number.isInteger(value) || value < min || value > max) {
    throw new HttpError(400, `invalid ${name}`, 'INVALID_PARAMETER');
  }
  return value;
}

export function parseEnum(query, name, values) {
  const raw = query.get(name) ?? values[0];
  if (!values.includes(raw)) {
    throw new HttpError(400, `invalid ${name}`, 'INVALID_PARAMETER');
  }
  return raw;
}
