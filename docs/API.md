# API reference

[English](API.md) | [简体中文](API.zh-CN.md)

Local base URL: `http://127.0.0.1:8080` on the Mac. The planned iPhone base URL is the public fixed-domain HTTPS reverse proxy (for example, `https://api.example.com`); the proxy reaches the Mac API over Tailscale. The phone does not need Tailscale. Proxy deployment and end-to-end validation are pending.

All routes except `/healthz` require:

```
Authorization: Bearer <API_TOKEN>
```

Data routes are rate limited before authentication: 120 requests/minute per client in total,
plus 60/minute for `/live`. Limits are keyed by socket address unless the request comes from a
proxy that presents the separate `PROXY_TOKEN`; only then are `X-Odo-Proxy-Token` and
`X-Odo-Client-IP` (a single valid IP) trusted. Clients behind a proxy without that configuration
share one limit.

Dates are ISO-8601 UTC, and range filters are compared as UTC regardless of the database session
timezone. Units:

| Field | Unit |
|---|---|
| `distance_km`, `odometer`, `*_range_km` | km |
| `elevation` | m |
| `speed`, `speed_max` | km/h |
| `power`, `power_max`, `power_min`, `charger_power` | kW (positive = consuming, negative = regen) |
| `charge_energy_*`, `energy_kwh` | kWh |
| `*_temp`, `*_temp_avg` | °C |
| `duration_min` | minutes |
| `charger_voltage` / `charger_actual_current` | V / A |

Fields that TeslaMate has no value for (for example `elevation` when terrain data is disabled)
are `null`, and MQTT topics that have never been published are omitted from `values`.
VIN, database credentials and MQTT credentials are never returned.

## GET /healthz

No auth. Returns `{"ok":true}`.

## GET /v1/cars

```json
{
  "cars": [
    {
      "id": 1,
      "name": "Blue Thunder",
      "model": "3",
      "trim_badging": "74D",
      "marketing_name": "LR AWD",
      "exterior_color": "DeepBlue",
      "wheel_type": "Pinwheel18",
      "spoiler_type": "None"
    }
  ]
}
```

## GET /v1/cars/:id/live

Latest received MQTT values plus the newest stored position time, regardless of its age.
`last_position_at` is null when no position has been stored.

```json
{
  "car": { "id": 1, "name": "Blue Thunder", "model": "3", "...": "..." },
  "mqtt_connected": true,
  "values": {
    "state": "online",
    "battery_level": 68,
    "usable_battery_level": 66,
    "rated_battery_range_km": 320.4,
    "inside_temp": 21.5,
    "outside_temp": 14.0,
    "is_climate_on": false,
    "locked": true,
    "sentry_mode": false,
    "location": { "latitude": 30.1, "longitude": 120.2 }
  },
  "received_at": "2026-11-02T11:59:00.000Z",
  "oldest_received_at": "2026-11-02T11:58:00.000Z",
  "stale": false,
  "last_error": null,
  "field_metadata": {
    "battery_level": { "received_at": "2026-11-02T11:59:00.000Z", "retained": false, "stale": false }
  },
  "observation_freshness": "unknown",
  "last_position_at": "2026-11-02T11:55:00.000Z",
  "server_time": "2026-11-02T12:00:00.000Z"
}
```

`stale` is true when MQTT is disconnected, when no message has arrived, or when any received
field is stale: a retained delivery, or older than `LIVE_STALE_SECONDS` (default 300).
A sleeping car legitimately has old values; use `values.state` to distinguish that from a
broken API/MQTT connection. Retained MQTT messages are timestamped when delivered, not when
originally observed, so a recent receipt time does not guarantee fresh vehicle data.
`field_metadata` reports the delivery time, retained flag and staleness per field.
`observation_freshness` is currently always `"unknown"`, because neither retained nor live
deliveries carry an observation time.

When the car has no destination set, `values.active_route` is
`{"error":"No active route available"}`; treat it as "no active route" rather than as a failure.

## GET /v1/cars/:id/positions

Query: `from`, `to` (default: last 30 days, max 366 days), `max_points` (10–5000, default 1000).

Only positions with a `drive_id` and non-null coordinates are returned. Points are sampled by
position count, prioritizing each drive's first and last available point. If endpoints exceed
`max_points`, they are sampled as well; otherwise the remaining budget is used for interior points.
Results are chronological and may omit intermediate peaks. Use `drive_id` to separate drives;
points without one are excluded.

```json
{
  "car_id": 1,
  "from": "2026-10-03T12:00:00.000Z",
  "to": "2026-11-02T12:00:00.000Z",
  "max_points": 1000,
  "points": [
    {
      "date": "2026-10-30T08:00:00.000Z",
      "drive_id": 42,
      "latitude": 30.1,
      "longitude": 120.2,
      "elevation": 10,
      "speed": 30,
      "power": 100,
      "odometer": 1000.5,
      "battery_level": 60,
      "usable_battery_level": 59
    }
  ]
}
```

## GET /v1/cars/:id/drives

Query: `from`, `to` (default: last 90 days, max 366 days), `limit` (1–500, default 100), `offset`,
or `before_id` for stable paging.

Results are ordered by `start_date` descending, then `id` descending. A full page returns
`next_before_id`; pass it as `before_id` with the same `from`/`to` and `limit` to fetch the next
page. This avoids duplicates when newer rows are inserted between requests. `before_id` cannot be
combined with a nonzero `offset` (400 `INVALID_PARAMETER`). Offset paging remains supported but
can shift when rows are inserted concurrently. Neither mode is a database snapshot: edits or
deletions can change results, and deleting the cursor row produces an empty page.

```json
{
  "car_id": 1,
  "from": "...",
  "to": "...",
  "limit": 100,
  "offset": 0,
  "next_before_id": null,
  "drives": [
    {
      "id": 10,
      "start_date": "2026-10-30T08:00:00.000Z",
      "end_date": "2026-10-30T08:30:00.000Z",
      "distance_km": 12.5,
      "duration_min": 30,
      "speed_max": 88,
      "power_max": 120,
      "power_min": -40,
      "start_km": 1000.0,
      "end_km": 1012.5,
      "start_ideal_range_km": 300.0,
      "end_ideal_range_km": 285.0,
      "start_rated_range_km": 320.0,
      "end_rated_range_km": 305.0,
      "start_battery_level": 78,
      "end_battery_level": 71,
      "outside_temp_avg": 14.0,
      "inside_temp_avg": 21.0,
      "ascent": 120,
      "descent": 90,
      "start_address": "Home",
      "start_address_display": "西湖区, 杭州市",
      "end_address": "Office",
      "end_address_display": "滨江区, 杭州市",
      "start_geofence": "🏡 Home",
      "end_geofence": "🏢 Office"
    }
  ]
}
```

## GET /v1/cars/:id/drives/:drive_id

Query: `max_points` (10–5000, default 1000).

```json
{
  "car_id": 1,
  "drive": { "id": 10, "...": "..." },
  "positions": [ { "date": "...", "latitude": 30.1, "longitude": 120.2, "...": "..." } ],
  "energy_kwh": 2.5
}
```

`energy_kwh` integrates `positions.power` over time for this drive. It is `null` when the drive
has no usable power interval; a measured value of zero stays `0`. `positions` never exceeds
`max_points`.

## GET /v1/cars/:id/charges

Query: `from`, `to` (default: last 90 days, max 366 days), `limit`, `offset`, or `before_id`. Paging
follows the same rules as drives.

```json
{
  "car_id": 1,
  "from": "...",
  "to": "...",
  "limit": 100,
  "offset": 0,
  "next_before_id": null,
  "charges": [
    {
      "id": 5,
      "start_date": "2026-10-30T09:00:00.000Z",
      "end_date": "2026-10-30T10:00:00.000Z",
      "charge_energy_added": 20.5,
      "charge_energy_used": 1.2,
      "start_battery_level": 40,
      "end_battery_level": 80,
      "duration_min": 60,
      "start_ideal_range_km": 200.0,
      "end_ideal_range_km": 300.0,
      "start_rated_range_km": 210.0,
      "end_rated_range_km": 320.0,
      "outside_temp_avg": 12.0,
      "cost": 4.1,
      "address": "Office",
      "address_display": "滨江区, 杭州市",
      "geofence": "🏢 Office"
    }
  ]
}
```

## GET /v1/cars/:id/charges/:charge_id

Returns the session plus every stored sample:

```json
{
  "car_id": 1,
  "charge": { "id": 5, "...": "..." },
  "samples": [
    {
      "date": "2026-10-30T09:00:00.000Z",
      "battery_level": 40,
      "usable_battery_level": 39,
      "charge_energy_added": 0.4,
      "charger_actual_current": 16,
      "charger_phases": 3,
      "charger_pilot_current": 16,
      "charger_power": 11.0,
      "charger_voltage": 230,
      "conn_charge_cable": "IEC",
      "fast_charger_present": false,
      "fast_charger_brand": "<invalid>",
      "fast_charger_type": "<invalid>",
      "ideal_battery_range_km": 200.0,
      "rated_battery_range_km": 210.0,
      "outside_temp": 12.0
    }
  ]
}
```

## GET /v1/cars/:id/states

Query: `from`, `to` (default: last 30 days, max 366 days).

```json
{
  "car_id": 1,
  "from": "...",
  "to": "...",
  "states": [
    { "state": "online", "start_date": "...", "end_date": "..." },
    { "state": "asleep", "start_date": "...", "end_date": null }
  ]
}
```

Returns every state that **overlaps** the window: a state that began before `from` is included with
its original `start_date`, so clip it to `from` before drawing. `end_date: null` means the state is
still current.

## GET /v1/cars/:id/updates

No query parameters. Returns up to 100 software updates, newest first.

```json
{
  "car_id": 1,
  "updates": [
    {
      "version": "2026.26.200.11",
      "start_date": "2026-07-01T08:00:00.000Z",
      "end_date": "2026-07-01T08:40:00.000Z"
    }
  ]
}
```

## GET /v1/cars/:id/stats

Query: `from`, `to` (default: last 30 days), `bucket` = `day` (default) | `month`.

Only buckets that contain a drive or a charge are returned; the client zero-fills missing
dates for charts. `charge_cost` is `null` when no charge in the bucket has a recorded cost;
a recorded zero stays `0`, and mixed known/unknown costs sum the known values.

```json
{
  "car_id": 1,
  "from": "...",
  "to": "...",
  "bucket": "day",
  "buckets": [
    {
      "bucket": "2026-10-30T00:00:00.000Z",
      "drive_count": 2,
      "distance_km": 42.3,
      "duration_min": 75,
      "charge_count": 1,
      "charge_energy_kwh": 20.5,
      "charge_cost": 4.1
    }
  ]
}
```

## GET /v1/cars/:id/energy

Query: `from`, `to` (default: last 180 days), `group` = `version` (default) | `season` |
`temperature`.

Consumption per group, in Wh/km, weighted by distance rather than by drive count. Energy comes
from integrating `positions.power` over samples at most 300 s apart, so a gap while the car slept
is not charged to the next segment; drives under 1 km and drives with no usable energy sample are
left out. Best and worst use only groups that cover at least 5 km — otherwise a 1 km descent on a
charge would win every time.

```json
{
  "car_id": 1,
  "from": "...",
  "to": "...",
  "group": "season",
  "total_km": 150,
  "average_wh_per_km": 160,
  "best": { "key": "夏季", "label": "夏季", "spread_percent": 18.8 },
  "latest_key": null,
  "groups": [
    {
      "key": "夏季",
      "label": "夏季",
      "wh_per_km": 150,
      "km": 100,
      "drive_count": 4,
      "from_date": "2026-08-01T08:00:00.000Z",
      "to_date": "2026-08-21T08:00:00.000Z"
    }
  ]
}
```

`group=version` labels a drive with the software version that was running when it started, or
`未知版本` when TeslaMate has no update record covering it. `latest_key` is the newest version
group, so the client can point at "最近版本". `best` is `null` when no group reaches 5 km.

## GET /v1/cars/:id/regen

Query: `from`, `to` (default: last 7 days).

Regeneration is only counted while a drive is open. TeslaMate also records power flowing *into*
the battery as negative while charging, and a five-minute charging sample would otherwise read as
51 kW of regen.

```json
{
  "car_id": 1,
  "from": "...",
  "to": "...",
  "today": { "date": "2026-11-02T00:00:00.000Z", "regen_kwh": 0.8, "consumed_kwh": 5.2, "minutes": 12, "peak_kw": 42 },
  "days": [ { "date": "2026-11-02T00:00:00.000Z", "regen_kwh": 0.8, "consumed_kwh": 5.2, "minutes": 12, "peak_kw": 42 } ],
  "total_regen_kwh": 0.8,
  "share": 0.133,
  "week_peak_kw": 42,
  "versions": [ { "version": "2026.40", "peak_kw": 42, "regen_kwh": 0.8 } ]
}
```

`today` is `null` when the range does not include today. `share` is recovered ÷ (recovered +
consumed) over the range, `null` when neither is known. Days without a drive are absent, not
zero; the client zero-fills.

## GET /v1/cars/:id/parking

Query: `from`, `to` (default: last 7 days).

A parking session is the gap between drives and charging sessions, at least 10 minutes long,
clipped to the requested range and capped at 60 sessions. Sessions are not split at midnight.
`place` comes from where the preceding drive ended. If the car has not moved since, the time
until now is the current session.

```json
{
  "car_id": 1,
  "from": "...",
  "to": "...",
  "total_minutes": 4200,
  "total_energy_kwh": 1.6,
  "average_power_w": 23,
  "sessions": [
    {
      "start_date": "2026-10-30T10:00:00.000Z",
      "end_date": "2026-11-02T08:00:00.000Z",
      "place": "🏢 Office",
      "duration_min": 4200,
      "energy_kwh": 1.6,
      "average_power_w": 23,
      "start_battery_level": 80,
      "end_battery_level": 78,
      "start_range_km": 320,
      "end_range_km": 312,
      "range_loss_km": 8,
      "range_loss_per_hour_km": 0.11,
      "state_minutes": [ { "state": "asleep", "minutes": 4000 }, { "state": "online", "minutes": 560 } ],
      "outside_temp_avg": 14,
      "odometer_km": 1012.5
    }
  ]
}
```

`energy_kwh` is the rated range lost during the session priced at the car's own Wh/km (from its
recently completed charges), **not** an integration of `positions.power`: a sleeping car is not
sampled, and the integral undercounts a night's drain by an order of magnitude. It is `null`
until the car has completed one charge spanning at least 40 percentage points, and
`average_power_w` follows it. `state_minutes` covers the whole session and is ordered by
duration; states not seen are absent. `total_energy_kwh` sums only the sessions that have an
estimate.

## GET /v1/cars/:id/battery

No query parameters. Battery health from the car's charges.

```json
{
  "car_id": 1,
  "sample_count": 6,
  "capacity_kwh": 67.5,
  "full_range_km": 375,
  "baseline_capacity_kwh": 75,
  "baseline_range_km": 375,
  "capacity_retention": 0.9,
  "range_retention": 1,
  "score": 90,
  "rating": "良好",
  "last_charge_date": "2026-10-01T10:00:00.000Z",
  "odometer_km": 12345.5
}
```

A sample is a charge spanning at least 40 percentage points and adding more than 5 kWh; where it
ends does not matter, the span is what makes `added ÷ (Δ% ÷ 100)` stable. Estimates outside
20–150 kWh (or a full range outside 100–1000 km) are discarded as decoding errors. The headline
is the median of the 10 most recent samples; the baseline is the best ever observed, so a cold
week cannot look like permanent degradation. `score` is the worse of the two retentions, as a
percentage. `rating` follows `优秀` ≥ 95, `良好` ≥ 90, `偏低` ≥ 80, `异常` below that, and is
`null` under three samples or when no charge qualifies. Charging losses inflate the capacity by
roughly 10 %, which the retention ratio cancels.

## Errors

| Status | Body |
|---|---|
| 400 | `{"error":"Bad request","code":"BAD_REQUEST"}` |
| 400 | `{"error":"invalid from","code":"INVALID_DATE"}` |
| 400 | `{"error":"before_id cannot be combined with offset","code":"INVALID_PARAMETER"}` |
| 400 | `{"error":"from must be before to","code":"INVALID_RANGE"}` |
| 400 | `{"error":"range must not exceed 366 days","code":"RANGE_TOO_LARGE"}` |
| 401 | `{"error":"Unauthorized","code":"UNAUTHORIZED"}` |
| 404 | `{"error":"Car not found","code":"NOT_FOUND"}` |
| 404 | `{"error":"Drive not found","code":"NOT_FOUND"}` |
| 404 | `{"error":"Charging session not found","code":"NOT_FOUND"}` |
| 404 | `{"error":"Not found","code":"NOT_FOUND"}` |
| 405 | `{"error":"Method not allowed","code":"METHOD_NOT_ALLOWED"}` |
| 429 | `{"error":"Too many requests","code":"RATE_LIMITED"}` |
| 500 | `{"error":"Internal server error","code":"INTERNAL_ERROR"}` |
