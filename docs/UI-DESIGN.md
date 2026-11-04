# TeslaMate Viewer — UI Design

Native iOS 17 app, SwiftUI, Chinese-first copy, dark-only. This document is the design source of
truth for the SwiftUI implementation. Visual reference: [`mockups/index.html`](mockups/index.html).
中文版：[`UI-DESIGN.zh-CN.md`](UI-DESIGN.zh-CN.md).

---

## 1. Design intent

The app answers three questions in order:

1. **车现在怎么样？** — Live: battery, range, state, location, security.
2. **车最近去了哪、充了多少？** — Drives and Charging: a readable log, not a data dump.
3. **长期趋势如何？** — Stats and History: distance, energy, cost, tracks.

Principles:

- **Data first, chrome second.** No decorative gradients behind text, no oversized headers that
  push the battery number below the fold. The battery ring and range are the only "hero".
- **One accent.** Cyan is reserved for navigation, selection and the primary metric. Green/orange/
  red/purple only encode state (online, charging, warning, suspended).
- **Calm when nothing happens.** A parked, locked, sleeping car should look quiet: neutral cards,
  one green "在线/休眠" pill, no animation.
- **Never lie about freshness.** Every live screen shows when the data arrived; stale data is
  labelled, not hidden.
- **Thumb-first.** Primary actions live in the lower half or the nav bar; every target ≥ 44 pt.

---

## 2. Visual system

Tokens mirror `ios/TeslaMateViewer/Design/Theme.swift`.

| Token | Value | Use |
|---|---|---|
| `background` | gradient `#0A0F1A` → `#141A29` + cyan/purple aurora | every screen |
| `glassBody` | white 10% → 3% → 5.5%, 150° | every card, tile, bar |
| `glassBodySoft` | white 6.5% → 1.8% → 3.8%, 150° | nested surfaces |
| `glassRim` | white 50% → 10% → 3% → 20%, 150° | 1 pt specular edge |
| `glassHighlight` | white 18% inset, 1 pt from top | inner light |
| `glassShadow` | `0 14 34` black 26% | lift, cards only |
| `accent` | `#5CC7FF` | selection, links, primary metric |
| `green` | `#5CD98F` | online, charged, locked, low consumption |
| `orange` | `#FFAA4D` | charging, stale, warnings |
| `red` | `#FF6E6E` | errors, low battery |
| `purple` | `#AD8CFF` | suspended/updating |
| `textPrimary` | `#F5F7FA` | values, titles |
| `textSecondary` | `#EBF0FF` @ 55% | labels, captions |

Type (SF Pro):

| Role | Size / weight | Notes |
|---|---|---|
| Large number | 34 / bold, rounded | battery %, range, kWh |
| Title | 22 / semibold | screen titles |
| Section | 15 / semibold | card headers |
| Body | 15 / regular | addresses, rows |
| Caption | 12 / regular | labels, timestamps |
| Tabular | 15–34 / monospaced digits | every changing number |

Spacing: 4 / 8 / 12 / 16 / 24. Screen padding 16. Card padding 16, gap 12.
Radii: card 24, inner media 16, control 16–20, pill 999.
Elevation: glass surfaces carry one soft shadow (`0 14 34`, black 26%) and a 1 pt inner top
highlight; the map and charts sit inside glass cards.

Layout is a single scrolling column per screen; only the Drives/Charging lists use sections with
sticky day headers. No horizontal carousels: they hide data and break VoiceOver order.

### 2.1 Liquid Glass

Every surface is glass, nothing is a flat panel:

- **Backdrop first.** Each screen is a dark gradient with a faint white sheen at the very top and
  three low-saturation fields below it — cyan at the mid-left, purple at the right, teal at the
  bottom. Glass needs something to tint and blur; on a flat background it reads as gray plastic.
- **Keep colour out of the chrome band.** The top ~120 pt (status bar + header) stays
  neutral navy. A saturated field behind the status bar clashes with the glass and reads as a hard
  band; colour belongs in the content field, where the glass picks it up.
- **Three layers per surface:** a translucent body (white 10% → 3% → 5.5% on a 150° diagonal, with a
  top-left sheen), a 1 pt specular rim drawn as a gradient border (white 50% at the lit corner → 3%
  at the dark one), and a single inset top highlight. No bevels, no long shadow stacks.
- **Blur and saturation together:** `.ultraThinMaterial`-equivalent = blur 24 pt + saturation 175%.
  Saturation is what stops frosted glass looking dirty.
- **Radii grow with the material:** cards 24, tiles and controls 22, segmented thumb 13, buttons 18.
  Glass reads as thicker than a tinted rectangle, so corners stay generous.
- **Tinting carries meaning, not decoration:** green for consumption, orange for warnings, red only
  for destructive actions, and those tints enter through the body and rim gradients — never as a
  flat colored fill.
- **Chrome floats.** The tab bar is a glass capsule inset 12 pt from the sides and 10 pt from the
  bottom; the header carries the title and its actions, borderless until the page scrolls and then
  wrapped in the same glass (see 2.2); segmented
  controls are glass tracks with a glass thumb. Content scrolls behind all of it.
- **Legibility outranks the effect.** Body text still sits on ≥ 3% white over a dark base, titles
  and captions inside the wrapped header sit on ≥ 5% white, and where backdrop blur is missing the
  header turns opaque rather than letting scrolled content ghost behind its title. If a surface
  would drop secondary text under 4.5:1, raise its body opacity instead of brightening the text.

### 2.2 Header bar and its wrap

The header carries identity and actions only; everything else belongs to the content.

- **One bar, title plus actions.** Every screen opens with the same row: back chevron and title on
  the left, trailing actions (refresh, map, share) on the right. No status band, no hairline, no
  background strip.
- **No chrome at rest.** At the top of the page the header is borderless and full-bleed: no glass,
  no rim, no radius. The title sits directly on the page, aligned with the 16 pt content gutter, so
  the header reads as the page's first line rather than a floating element.
- **It is pinned.** The header stays at the top of the scroll view for the whole scroll instead of
  travelling up with the content.
- **Scrolling wraps it.** Once the page moves (~8 pt), the same bar contracts into a glass capsule:
  12 pt side inset, 28 pt radius, 10/16 padding, glass body + specular rim + shadow, sitting right
  under the status bar. The wrap is a 220 ms `cubic-bezier(.32, .72, 0, 1)` transition on inset, padding
  and radius, with the glass fading in over 180 ms; scrolling back to the top unwraps it the same
  way. Nothing moves inside the bar — one header, two states.
- **Filters are never in the header.** The 7/30/90 control (and Stats' 日/月) is a content row
  directly under the header that scrolls away with the rest of the page. The header stays one
  height on every screen; a second glass bar under it is what made the header read as stacked
  bands.
- **Actions are plain icons inside the header** (white 74%, 36 pt hit target, no background, no
  border, no shadow). A glass circle inside the glass capsule reads as a second material and is
  what makes a header look segmented.
- **Screens that never scroll never wrap** — Charging's header stays borderless because nothing
  passes behind it. **History is the exception**: it is map-first, its header sits over the map, so
  it is wrapped from the start; a borderless title over map colours is unreadable.
- **Drives day headers are the only other sticky level**: they stick to the top of the scroll view
  and pass under the wrapped header, never above it.
- **History is map-first**: the header and its filter row sit over the map, the map does not
  scroll, and the bottom sheet scrolls internally if its content ever exceeds its height.
- Where backdrop blur is unavailable, the wrapped header falls back to an opaque `#18222F` body
  with the same rim, so nothing ghosts behind the title. The rest state needs no fallback.
- The wrapped body stays above 5% white so 12 pt captions inside it keep 4.5:1 against the navy
  base; raising body opacity is the fix for legibility, not brightening the text.

---

## 3. Component inventory

Every component, its variants, the screens that use it and whether it exists in code is listed in
[`UI-COMPONENTS.md`](UI-COMPONENTS.md) — 44 components in five families (C-39–C-44 added 2026-11-04):

| Family | IDs | Covers |
|---|---|---|
| Chrome | C-01–C-08 | background, header and its scroll wrap, filter row, segmented control, tab bar, sticky day header, map bottom sheet |
| Surfaces | C-09–C-13 | glass card, chart card, settings group and row, map entry card |
| Content | C-14–C-24 | battery ring, stat tiles and strips, inline rows, badges, SoC bar, freshness line, list rows, list footer |
| Charts and maps | C-25–C-30 | line and bar charts, map surface, track layer, overlay pill, recenter control |
| Feedback and forms | C-31–C-38 | error banner, empty state, skeleton, glass field, primary and destructive buttons, toggle row, hero glyph |

`HeaderBar` (C-02) is specified in full there, because it is the only component with behaviour: two
states, one bar, and a wrap transition nothing else in the app imitates.

Screens beyond v1 (today's board, state legend, richer drive rows, trip calendar, parking list and
detail, battery health, consumption analysis, regen, track filter) are drawn in
[`mockups/gap-screens.html`](mockups/gap-screens.html). They reuse this document's tokens, header
rules and four-tab structure, and are not yet scheduled; the reasoning is in
[`GAP-ANALYSIS.md`](GAP-ANALYSIS.md).

---

## 4. Screens

### 4.1 Onboarding (first launch only)

Full-screen gradient, no tab bar.

```
            ◇ (car glyph, accent)
        连接你的 TeslaMate
   使用公网 HTTPS 地址和 Token 安全连接。

  ┌ 服务器地址  https://api.example.com ┐
  ┌ API Token   ••••••••••••••••••••••••  ┐
  [        测试并保存        ]
  填写已部署的公网 HTTPS 代理地址；手机无需 Tailscale。
```

- The proxy is planned, not yet deployed; `api.example.com` is an example address.
- URL keyboard, no autocapitalize/autocorrect; token field is `SecureField` with a reveal toggle.
- "测试并保存" validates scheme + host, writes the token to Keychain, calls `GET /v1/cars`,
  then shows "连接成功 · 1 辆车" before entering the app.
- Failure copy: invalid URL / 401 "Token 无效" / timeout "无法连接服务器，检查网络和服务器地址".

### 4.2 Live — 实时

Order: state → battery → location → motion/security → climate → vehicle → route.

```
★Roadster Lite™                    ⟳
● 在线            最后更新 12 秒前

┌───────────────┐  续航
│    ◯ 74%      │  382 km
│     电量      │  估算 419 km · 额定 382 km
└───────────────┘  充电枪 未连接

┌─────────────── 地图 200 pt ───────────────┐
│        ● 车辆位置                         │
│  杭州市 · 拱墅区                  查看 ↗  │
└───────────────────────────────────────────┘

┌ 速度 ┐ ┌ 功率 ┐
│ 0    │ │ 0.0  │
└──────┘ └──────┘
┌ 里程 ┐ ┌ 挡位 ┐
└──────┘ └──────┘

┌ 车锁 已锁 · 哨兵 关闭 · 车窗 已关 · 车门 已关 ┐
┌ 车内 25.0°C   车外 17.5°C   空调 关闭        ┐
┌ 软件 2026.26.200.11 · Model 3 LR AWD        ┐
```

Rules:

- Poll every 3 s while `scenePhase == .active`; stop in background; pull-to-refresh always works.
- If `charging_state == "Charging"`, insert a **充电中** card between battery and map: power,
  energy added, current SoC → limit, time to full. Move map below it.
- If `active_route.destination != nil`, append a navigation card; ignore
  `{"error":"No active route available"}`.
- `stale == true` and state ≠ asleep → orange banner "数据已过期，展示最后已知状态".
  State == asleep → neutral line "车辆休眠 · 数据停在 11月1日 21:01".
- Battery ring color follows level; the bolt shows only while charging.
- Security row compresses four booleans into one line of icon + label pairs; any "open" state
  turns orange and the whole line becomes tappable to expand details.

### 4.3 Drives — 行程

```
行程                              近 30 天 ▾
[ 7 天 ] [ 30 天 ] [ 90 天 ]

┌ 118.5 km      12 次行程      6 小时 42 分 ┐

11月1日 周六                        4.1 km
┌ 06:02  ● 祥符 · 拱墅区                  ┐
│        │                                │
│ 06:13  ○ 和美弄                 4.0 km  │
│                          11 分钟 · 消耗 4.4 km
└─────────────────────────────────────────┘
...
```

- Summary strip is computed client-side from the loaded page (distance, count, duration).
- Row: start time, vertical rail with green start dot and orange end dot, start/end titles
  (geofence name wins over address), right column distance + duration.
- Day header: `M月d日 周x` + that day's distance, sticky.
- Pagination: `limit=100`, load next page at 80% scroll; footer spinner; end state "没有更多行程".
- Nav-bar **轨迹** button (map icon + label) opens History with the current period selected.
- Tap → Drive Detail. Empty period → EmptyState with "切换时间段" action.

### 4.4 Drive Detail — 行程详情

```
‹ 行程详情
┌─────────── 地图 260 pt，路线 Polyline ───────────┐
│  ● 起点                                  ○ 终点  │
└──────────────────────────────────────────────────┘

  3.97 km        11 分钟        0.65 kWh
  16.3 kWh/100km（能耗徽章，绿色 <18，橙色 ≥18）

┌ 速度 ───────────────────────────── 最高 66 km/h ┐
│        ╱╲      ╱╲╲╱╲                            │
└──────────────────────────────────────────────────┘
┌ 功率 ─────────────────────────── 最低 -43 kW    ┐
└──────────────────────────────────────────────────┘
┌ 电量 ─────────────────────────────────── 74%    ┐
└──────────────────────────────────────────────────┘
起点 / 终点 · 车外均温 / 车内均温 · 爬升 / 下降 · 续航消耗
```

- Map fits all downsampled positions; start green, end orange; "全屏" opens a full-screen map.
- Consumption = `energy_kwh / distance_km * 100`; hide when distance < 0.5 km.
- Elevation chart only when at least 30% of points have non-null elevation.
- Charts share the same time domain so vertical reading is consistent.
- Missing drive → error banner + back, never a blank screen.

### 4.5 Charging — 充电

```
充电                              近 30 天 ▾
[ 7 天 ] [ 30 天 ] [ 90 天 ]

┌ 72.2 kWh 已充      3 次     费用未记录 ┐

11月1日 13:30 · 石祥路
  35% ▓▓▓▓▓▓░░░░░░ 81%        33.9 kWh
  29 分钟 · 车外 25°C                  ›
```

- SoC transition uses a small horizontal battery bar, not a number pair only.
- Rows with `cost == null` show "费用未记录", never ¥0.00.
- Detail: power curve (area), SoC curve (line), energy-added curve (line).
- Detail facts: start/end SoC, duration, voltage/current/phases from the last valid sample,
  connector type (`conn_charge_cable`), outside temperature, cost if present.

### 4.6 Stats — 统计

```
┌ 统计                               ↻ ┐   ← header, wrapped once the page scrolls
└──────────────────────────────────────┘
[ 7 天 ] [ 30 天 ] [ 90 天 ]      [ 日 ] [ 月 ]   ← content row, scrolls away

┌ 总里程 ┐ ┌ 行程次数 ┐
│ 118.5  │ │ 12       │
└────────┘ └──────────┘
┌ 充电电量 ┐ ┌ 充电费用 ┐

┌ 每日里程 ────────────────────────────────┐
│   ▁▂▅█▃▁▂▇▁  (accent bars)                │
└──────────────────────────────────────────┘

┌ 🗺 历史轨迹地图                            ┐
└─────────────────────────────────────────────┘
```

- Period and bucket share one row directly under the header, not inside it; changing either
  refetches without resetting scroll.
- Charts: 每日里程, 充电电量, 行程时长 — one card each, same x domain.
- Bars are zero-filled for missing days; month bucket uses month labels.
- Values are exactly the `stats` endpoint sums; cost tile shows "—" when no session has a cost.
- Tapping a bar is **v1.1** (filtered drive list); do not ship it half-done.

### 4.7 History — 历史轨迹

**Entry points.** History is not a tab; the five tabs stay 实时 / 行程 / 充电 / 统计 / 设置.

1. **Drives → nav-bar "轨迹"** (map icon + label) — the primary, thumb-reachable entry; carries the
   current 7/30/90-day period.
2. **Stats → "历史轨迹地图" card** at the bottom of the screen — the discovery entry when the user is
   already looking at aggregates.

Both push the same view; the back button returns to the originating tab. The period selector stays
local to History, so changing it there does not mutate the Drives/Stats filter.

```
‹ 历史轨迹                    [ 7 天 ] [ 30 天 ] [ 90 天 ]

┌──────────────────────────────────────────────┐
│            full-bleed map                    │
│        ╭──────╮  polyline in accent          │
│        ╰──╮   ╰────╮                         │
└──────────────────────────────────────────────┘
 118 km 轨迹 · 1,000 个采样点 · 10月3日–11月2日
 起点 ● 终点 ○           [ 标准 / 卫星 ]
```

- **Map-first layout:** the map fills all space below the period selector, edge to edge and under
  the home indicator. The summary card and the coordinate note float above it as a bottom sheet
  with a soft gradient scrim; nothing sits below the sheet, so there is no empty band.
- `max_points=2000` for 30 days, `5000` for 90 days.
- Distance in the summary is haversine over displayed points, labelled "约" to avoid implying
  TeslaMate's odometer precision.
- Empty range → map hidden, EmptyState "该时间段没有位置记录".
- Full-screen map supports pinch/rotate; exit returns to the sheet summary.

### 4.8 Settings — 设置

```
设置
服务器
  https://api.example.com          ›
  API Token  ••••••••                 ›
  ● 连接正常 · 1 辆车             测试连接

车辆
  ★Roadster Lite™  Model 3 LR AWD     ›

地图
  中国坐标偏移校正              [ on ]
  WGS-84 → GCJ-02；海外自动关闭

关于
  版本 0.1.0 · 只读 · HTTPS 安全连接

[ 清除 Token ]
```

- URL/token edits go through the same validation as onboarding; "测试连接" re-fetches cars and
  updates the picker.
- Changing the car clears caches and reloads every tab.
- "清除 Token" is destructive, requires confirmation, and returns to onboarding.
- Token is never displayed after saving; the field shows a masked placeholder.

---

## 5. States, motion, accessibility

| State | Treatment |
|---|---|
| First load | Skeleton cards matching final layout; no full-screen spinner |
| Refresh | Pull-to-refresh + small nav-bar spinner; existing data stays |
| Stale live data | Orange banner + "最后更新 X"; never blank |
| Network error | `ErrorBanner` with retry; cached content remains, labelled |
| 401 | Banner + "去设置" action; do not silently retry |
| Empty list | `EmptyState` with one action |
| Loading more | Footer spinner; disable duplicate requests |

Motion: 200–300 ms ease-out for ring/chart transitions; no shimmer after first load; charts do not
re-animate on every 3 s poll (animate only when the time range changes); respect
`accessibilityReduceMotion`.

Accessibility:

- Battery ring label: "电量 74%，续航 382 公里"; state pill announces "车辆状态：在线".
- Charts expose an accessibility summary ("速度，最高 66 公里每小时") and per-point values via
  `AXChartDescriptor` where feasible.
- Contrast: primary text on card ≥ 7:1; secondary ≥ 4.5:1.
- Dynamic Type supported for all text; large numbers cap at 34 pt but scale with `@ScaledMetric`.
- Every icon-only button has a label; targets ≥ 44×44 pt.

---

## 6. API mapping

| Screen | Endpoint | Fields used |
|---|---|---|
| Onboarding / Settings | `GET /v1/cars` | `id, name, model, trim_badging, marketing_name` |
| Live | `GET /v1/cars/:id/live` | `values.*`, `stale`, `received_at`, `last_position_at`, `mqtt_connected` |
| Drives list | `GET /v1/cars/:id/drives` | dates, distance, duration, addresses, geofences |
| Drive detail | `GET /v1/cars/:id/drives/:drive_id` | positions, `energy_kwh`, ascent/descent, temps |
| Charging list | `GET /v1/cars/:id/charges` | energy, SoC, duration, cost, address |
| Charge detail | `GET /v1/cars/:id/charges/:charge_id` | samples → power/SoC/energy curves |
| Stats | `GET /v1/cars/:id/stats` | buckets → totals + bar chart |
| History | `GET /v1/cars/:id/positions` | downsampled track |
| (optional) state timeline | `GET /v1/cars/:id/states` | not used in v1 |

## 7. Map and coordinates

### Where maps appear

| Surface | Height | Shows | Camera |
|---|---|---|---|
| Live | ~200 pt card, under the battery | last known position, one pin | last position; follows new positions until the user pans, then a recenter control appears |
| Drive Detail | ~260 pt card | that drive's polyline, start + end | fitted to the polyline, never moves on its own |
| History | full screen below the header | the selected range's track | fitted to the track, never moves on its own |
| Stats | none | a card that opens History | — |

Four surfaces, one map style. Nothing else in the app instantiates a map.

### Coordinates

- TeslaMate stores **WGS-84**. Apple Maps in mainland China renders **GCJ-02**.
- When `mapOffsetCorrection` is on *and* the point is inside China, convert before display; outside
  China, skip conversion. Raw WGS-84 stays in storage and in the API.
- The conversion happens at render time, so toggling the switch redraws without refetching.
- Verify one known coordinate lands on the correct road before release; if the conversion is wrong
  the error shows up as a consistent ~500 m shift in one direction, never as scattered drift.

### Camera

- Fitted to content with ≥ 12 % padding on every edge; pitch 0; rotation off; no 3D buildings.
- Live follows the car only while the user has not panned. The first pan stops following and shows
  a recenter control; tapping it restores the camera and resumes following.
- Drive Detail and History are static: a map that moves under a finger reading a finished drive is
  an annoyance, not a feature.

### Line and markers

- One stroke for the track, 3 pt, rounded joins, accent colour — no gradient, no glow.
- Start is a filled dot, end is a chevron; the two differ by **shape**, so they survive greyscale
  and colour-blindness.
- Not in v1: charge pins, geofence overlays, clustering, heat maps, tap-to-select a point.

### States

| State | Map does |
|---|---|
| No positions in range | nothing is drawn — the frame is replaced by one message and one action |
| API 400 | banner above the previous map; the last good track stays |
| Offline | cached track over blank tiles, with "缓存于 …" |
| Switching the offset toggle | same track, redrawn; no spinner, no request |

### Accessibility and privacy

- The app never requests location and never draws a user dot; there is no `NSLocation*` key.
- Each map carries a text alternative — "行程轨迹，12.4 公里，从 A 到 B" — and every fact it shows
  also exists as text outside it.
- Map style: standard, flat elevation, no traffic.

## 8. Out of scope for v1 UI

- Vehicle commands, push notifications, widgets, Live Activities.
- Android/iPad-specific layouts, landscape.
- Offline map tiles; offline cached JSON only (last successful response per screen).
