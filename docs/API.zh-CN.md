# API 参考

[English](API.md) | [简体中文](API.zh-CN.md)

Mac 上的本地基础 URL 为 `http://127.0.0.1:8080`。计划为 iPhone 使用具有固定公网域名的 HTTPS 反向代理作为基础 URL（例如 `https://api.example.com`）；代理通过 Tailscale 访问 Mac 上的 API，手机无需安装 Tailscale。代理部署和端到端验证尚未完成。

除 `/healthz` 外，所有路由均需要：

```
Authorization: Bearer <API_TOKEN>
```

数据路由在鉴权之前限流：每个客户端合计每分钟 120 次，其中 `/live` 另有每分钟 60 次的限制。
默认按套接字地址识别客户端；只有携带独立 `PROXY_TOKEN` 的代理请求才会信任
`X-Odo-Proxy-Token` 和 `X-Odo-Client-IP`（必须是单个合法 IP）。未做该配置的代理后方客户端
会共用同一个限额。

日期采用 ISO-8601 格式，时区为 UTC；范围过滤始终按 UTC 比较，不受数据库会话时区影响。单位如下：

| 字段 | 单位 |
|---|---|
| `distance_km`, `odometer`, `*_range_km` | km |
| `elevation` | m |
| `speed`, `speed_max` | km/h |
| `power`, `power_max`, `power_min`, `charger_power` | kW（正值表示耗能，负值表示能量回收） |
| `charge_energy_*`, `energy_kwh` | kWh |
| `*_temp`, `*_temp_avg` | °C |
| `duration_min` | 分钟 |
| `charger_voltage` / `charger_actual_current` | V / A |

TeslaMate 中没有值的字段（例如禁用地形数据时的 `elevation`）为 `null`；从未发布过的 MQTT 主题不会出现在 `values` 中。VIN、数据库凭据和 MQTT 凭据均不会返回。

## GET /healthz

无需身份验证。返回 `{"ok":true}`。

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

最近收到的 MQTT 值，以及最新的已存储位置时间（不限时间范围）。如果从未存储位置记录，`last_position_at` 为 null。

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

MQTT 断开、从未收到消息，或任一已接收字段过期时，`stale` 为 true。“过期”指该字段是保留消息，
或距接收已超过 `LIVE_STALE_SECONDS`（默认 300 秒）。休眠中的车辆出现旧数据属于正常情况；
可通过 `values.state` 将其与 API/MQTT 连接中断区分开来。MQTT 保留消息的时间戳记录的是消息送达时间，
而非原始观测时间，因此近期收到消息并不能保证车辆数据是最新的。`field_metadata` 给出每个字段的
送达时间、是否为保留消息以及是否过期。由于保留消息和实时消息都不携带观测时间，
`observation_freshness` 目前始终为 `"unknown"`。

车辆未设置目的地时，`values.active_route` 为 `{"error":"No active route available"}`；应将其视为“没有活动路线”，而不是故障。

## GET /v1/cars/:id/positions

查询参数：`from`、`to`（默认最近 30 天，最长 366 天）、`max_points`（10–5000，默认 1000）。

仅返回具有 `drive_id` 且坐标非空的行驶位置点，按有效位置点数量采样，优先保留每次行程在所选时间范围内的首尾点。若首尾点总数超过 `max_points`，则对首尾点继续采样；否则将剩余额度用于行程中间点。结果按时间排序，最多包含 `max_points` 条记录，可能遗漏中间峰值。可使用 `drive_id` 区分行程；没有行程编号的位置点会被排除。

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

查询参数：`from`、`to`（默认最近 90 天，最长 366 天）、`limit`（1–500，默认 100）、`offset`，或用
`before_id` 进行稳定翻页。

结果按 `start_date` 降序、再按 `id` 降序排列。整页返回时会给出 `next_before_id`；将其作为
`before_id`，并保持相同的 `from`/`to` 和 `limit`，即可获取下一页。这样在请求之间插入新记录时
不会产生重复。`before_id` 不能与非零 `offset` 同时使用（返回 400 `INVALID_PARAMETER`）。
仍支持 offset 翻页，但并发插入时可能发生偏移。两种方式都不是数据库快照：编辑或删除会改变结果，
删除游标所在记录会导致返回空页。

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

查询参数：`max_points`（10–5000，默认 1000）。

```json
{
  "car_id": 1,
  "drive": { "id": 10, "...": "..." },
  "positions": [ { "date": "...", "latitude": 30.1, "longitude": 120.2, "...": "..." } ],
  "energy_kwh": 2.5
}
```

`energy_kwh` 通过对本次行程的 `positions.power` 随时间积分计算得出。没有可用的功率区间时为
`null`；实测为零时仍为 `0`。`positions` 的条数不会超过 `max_points`。

## GET /v1/cars/:id/charges

查询参数：`from`、`to`（默认最近 90 天，最长 366 天）、`limit`、`offset`，或 `before_id`。翻页规则与行程相同。

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

返回充电会话及其所有已存储的采样记录：

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

查询参数：`from`、`to`（默认最近 30 天，最长 366 天）。

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

返回与查询区间**重叠**的状态：在 `from` 之前开始、跨越 `from` 的状态也会返回，`start_date` 早于 `from`，
绘制前按 `from` 裁剪。`end_date` 为 `null` 表示该状态仍在持续。

## GET /v1/cars/:id/updates

无查询参数。最多返回 100 条软件更新记录，按时间从新到旧排列。

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

查询参数：`from`、`to`（默认最近 30 天）、`bucket` = `day`（默认）| `month`。

只返回包含行程或充电记录的时间区间；客户端在绘制图表时将缺失日期补零。该区间内没有任何充电记录
登记费用时，`charge_cost` 为 `null`；实测为零时仍为 `0`；已知与未知费用混合时，只累加已知值。

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

查询参数：`from`、`to`（默认最近 180 天）、`group` = `version`（默认）| `season` | `temperature`。

按分组给出百公里能耗（Wh/km），按里程加权而非按行程次数平均。电量由 `positions.power` 积分得出，
只累加间隔不超过 300 秒的相邻采样，车辆休眠造成的数据空档不会算到下一段上；不足 1 km 的行程和
没有可用功率采样的行程不计入。最优/最差只在里程不少于 5 km 的组之间比较，否则一段 1 km 的下坡
会永远排第一。

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

`group=version` 用行程开始时正在运行的软件版本作为分组，TeslaMate 没有对应更新记录时为 `未知版本`。
`latest_key` 是最新的版本分组，供客户端标注「最近版本」。没有任何分组达到 5 km 时 `best` 为 `null`。

## GET /v1/cars/:id/regen

查询参数：`from`、`to`（默认最近 7 天）。

能量回收只在行程进行中统计。TeslaMate 也会把充电时流入电池的功率记为负值，一个 5 分钟的充电采样
否则会被算成 51 kW 的回收功率。

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

`today` 在所选区间不含今天时为 `null`。`share` = 回收 ÷（回收 + 消耗），两者都不存在时为 `null`。
没有行程的日期不返回记录而非返回零，由客户端补零。

## GET /v1/cars/:id/parking

查询参数：`from`、`to`（默认最近 7 天）。

一次停车是行程与充电会话之间的空档，最短 10 分钟，按所选区间裁剪，最多返回 60 段；跨午夜的停车不拆分。
`place` 取上一条行程的终点。车辆此后未再移动时，直到当前时间的空档即为正在进行的停车。

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

`energy_kwh` 是这段时间损失的标称续航乘以车辆自身的 Wh/km（取自最近完成的充电），**不是**对
`positions.power` 的积分：休眠中的车辆没有采样，积分会把一夜的耗电低估一个数量级。车辆还没有一次
跨度达到 40 个百分点的充电时该字段为 `null`，`average_power_w` 随之也为 `null`。
`state_minutes` 覆盖整段停车并按分钟数降序，未出现的状态不列出。`total_energy_kwh` 只累加有估算值的会话。

## GET /v1/cars/:id/battery

无查询参数。由充电记录推算电池健康度。

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

一个样本是一次跨度不少于 40 个百分点的充电，且充入电量大于 5 kWh；充到多少不影响结果，跨度才是
`充入电量 ÷ (Δ% ÷ 100)`稳定的原因。估算容量超出 20–150 kWh（或满电续航超出 100–1000 km）视为解码错误丢弃。
展示值取最近 10 个样本的中位数，基线取历史上最好的观测值，因此寒冷的一周不会被当成永久衰减。
`score` 取容量保持率与续航保持率中较差的一个，以百分比表示；`rating` 按 `优秀` ≥ 95、`良好` ≥ 90、
`偏低` ≥ 80，更低为 `异常`，样本不足 3 个或无合格充电时为 `null`。充电损耗会让容量估计偏高约 10%，
该偏差在保持率比值中相互抵消。

## 错误

| 状态码 | 响应体 |
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
