# TeslaMate Viewer — Product Requirements (v1)

Status: draft, 2026-11-02 · Owner: Steven · Platform: iOS 17+ (iPhone), read-only

This document defines **what v1 must do and how we know it works**. Visual and interaction
details live in [`UI-DESIGN.md`](UI-DESIGN.md); the wire contract lives in [`API.md`](API.md).
Neither is repeated here. 中文版：[`PRD.zh-CN.md`](PRD.zh-CN.md).

---

## 1. Problem

TeslaMate already records live telemetry and full history, but its web UI is a desktop dashboard:
it needs a browser, a LAN or Tailscale URL, and a wide screen. Checking "is the car locked and
charged enough for the trip" on a phone means navigating a Grafana-style page.

The app replaces that with three questions, answered in order:

1. **车现在怎么样？** — current state, battery, range, location, security.
2. **车最近去了哪、充了多少？** — drives and charging sessions as a readable log.
3. **长期趋势如何？** — distance, energy, cost, tracks over 7/30/90 days.

## 2. Users

One user (the owner), one car, one Mac running TeslaMate. There is no account system, no sharing,
and no multi-tenant concern. That single user is usually standing next to the car or on the sofa,
on a phone, often one-handed.

Scenarios that drive requirements:

| # | Scenario | Screen |
|---|---|---|
| S1 | About to leave: is it locked, charged enough, where is it? | Live |
| S2 | Just parked: how much did that trip use? | Drives → Drive Detail |
| S3 | Public charger: how fast is it charging, when is it done? | Live (charging card) |
| S4 | End of month: how much did I drive, what did charging cost? | Stats |
| S5 | "Where did I go on Saturday?" | History |

## 3. Goals and success criteria

| Goal | Success criterion |
|---|---|
| Fast answer to S1 | Live data on screen within 1.5 s of a cold launch through the planned public HTTPS proxy |
| Live feels live | UI reflects a new MQTT value within 5 s while the screen is active |
| History is scannable | Any list or detail screen reachable in ≤ 2 taps from its tab; first page renders in < 300 ms after the API responds |
| Never misleading | No screen ever shows 0, "—" or stale numbers in a way that could be read as current truth (see §5.7) |
| Safe by construction | The app cannot write to TeslaMate; no VIN, DB password or MQTT credential ever reaches the phone |

## 4. Scope

In scope for v1:

- Onboarding, Settings (server URL, token, car, map offset, sign-out)
- Live status with polling, charging and active-route cards
- Drives list (7/30/90 d) + drive detail with map and charts
- Charging list (7/30/90 d) + charge detail with curves
- Stats (7/30/90 d, day/month buckets) with bar charts
- History track map, entered from Drives and Stats
- Maps on three surfaces — live position, drive polyline, history track — with WGS-84 → GCJ-02
  correction, no location permission and no offline tiles (FR-9)
- Read-only Node API on the Mac; iPhone sends a Bearer token over HTTPS to a planned public fixed-domain reverse proxy, which reaches the API over Tailscale. The phone does not need Tailscale

Out of scope for v1 (see also UI-DESIGN §8):

- Vehicle commands of any kind (lock, climate, charging) — the API is read-only by design
- Push notifications, widgets, Live Activities, Apple Watch
- Multiple cars in the UI (the API supports it; v1 selects one), multiple users
- iPad/landscape layouts, Android, web
- Offline map tiles; only last-response caching
- Tamper/alarm history, geofence editing
- Units other than km / kWh / °C

Deferred rather than out of scope: a 3D vehicle model on the Live screen that mirrors per-door state
(§10, DF-1), and manually recording what a third-party charging session cost (§10, DF-2).

## 5. Functional requirements

Requirement IDs are stable references for tests and review. "AC" = acceptance criteria.

### 5.1 Onboarding — FR-1

- FR-1.1 First launch, or after the token is cleared, shows onboarding instead of tabs.
  **AC** No tab bar is visible; both server URL and token fields are present.
- FR-1.2 "测试并保存" validates the URL scheme/host, saves the token to the Keychain, and calls
  `GET /v1/cars` before entering the app. **AC** A bad URL, a 401, and a timeout each produce
  their own message (UI-DESIGN §4.1); a 200 shows the car count and proceeds.
- FR-1.3 The token is never written to `UserDefaults`, logs, or source. **AC** Keychain is the only
  store; `SettingsStore` persists URL, car id and map-offset flag only.

### 5.2 Settings — FR-2

- FR-2.1 Changing the server or token re-validates with the same rules as onboarding.
  **AC** An invalid value does not replace the working configuration.
- FR-2.2 Changing the car clears every cached response and reloads all tabs.
  **AC** No data from the previous car remains on screen or in the cache.
- FR-2.3 "清除 Token" is destructive, asks for confirmation, and returns to onboarding.
  **AC** After confirming, the Keychain entry is gone and the app cannot fetch.
- FR-2.4 Map offset correction is on by default in China and is a user-visible switch.
  **AC** Toggling it re-renders maps without refetching.

### 5.3 Live — FR-3

- FR-3.1 Polls `GET /v1/cars/:id/live` every 3 s while `scenePhase == .active`.
  **AC** No requests are made in background or after leaving the tab; returning to foreground
  refreshes immediately.
- FR-3.2 Pull-to-refresh is always available and coexists with polling.
  **AC** A manual refresh does not cancel or duplicate the 3 s cycle.
- FR-3.3 Charging state inserts a charging card (power, energy added, SoC → limit, time to full)
  between battery and map. **AC** Card appears and disappears with `charging_state`, without a
  layout jump that hides the battery number.
- FR-3.4 An active route appends a navigation card; `{"error":"No active route available"}` is
  treated as "no route", not as an error. **AC** No error banner for a car with no route set.
- FR-3.5 Security row shows lock, sentry, windows and doors; any "open" state is orange and
  expandable. **AC** A single `false` value changes that item's color and makes the row tappable.
- FR-3.6 Last-updated time is always visible. **AC** It updates on every successful poll; it does
  not jump backwards on a failed poll.

### 5.4 Drives and drive detail — FR-4

- FR-4.1 List defaults to the last 30 days, with 7 / 30 / 90 switches. **AC** Switching refetches
  and keeps scroll at the top of the new result.
- FR-4.2 Rows group under sticky day headers; geofence name wins over address.
  **AC** A drive with both shows the geofence name only.
- FR-4.3 Pagination uses `limit=100`, loads at 80 % scroll, and ends with "没有更多行程".
  **AC** No duplicate rows across pages; no second request while one is in flight.
- FR-4.4 Summary strip (distance, count, duration) is computed from the loaded page, not the API.
  **AC** The sum matches the visible rows.
- FR-4.5 Detail renders map polyline, speed/power/SoC charts on one time domain, and the facts
  block. **AC** Charts share x-axis extent; a drive with no positions shows an error banner and
  back navigation, never a blank screen.
- FR-4.6 Consumption is `energy_kwh / distance_km × 100`, hidden under 0.5 km, green < 18,
  orange ≥ 18. **AC** Boundary values 17.9 / 18.0 color as specified; short drives hide the badge.
- FR-4.7 The elevation chart appears only when ≥ 30 % of points have elevation. **AC** A drive
  with terrain data disabled omits the chart entirely.

### 5.5 Charging and charge detail — FR-5

- FR-5.1 Same period control and pagination rules as Drives.
- FR-5.2 Each row shows a SoC bar plus kWh, duration and outside temperature.
  **AC** A session without cost shows "费用未记录", never "¥0.00".
- FR-5.3 Detail renders power, SoC and energy-added curves plus facts from the last valid sample
  (voltage, current, phases, connector). **AC** A session whose samples are all null shows the
  facts it has and omits the curves, without crashing.

### 5.6 Stats — FR-6

- FR-6.1 Period (7/30/90 d) and bucket (日/月) sit in one content row under the header.
  **AC** Changing either refetches without resetting scroll position.
- FR-6.2 Tiles show total distance, drive count, charge energy and charge cost from the `stats`
  sums. **AC** Values equal the API totals for the same range; cost shows "—" when no session in
  the range has a cost.
- FR-6.3 Charts are zero-filled for days with no data and share one x domain.
  **AC** A range with gaps shows continuous bars, not a compressed axis.
- FR-6.4 Tapping a bar is **not** in v1. **AC** Bars are not tappable.

### 5.7 History — FR-7

- FR-7.1 History is not a tab; it is pushed from Drives ("轨迹") and from the Stats map card, and
  the back button returns to the originating tab. **AC** The tab bar keeps exactly five items.
- FR-7.2 The period selector is local to History and does not mutate Drives/Stats state.
- FR-7.3 Downsampling requests `max_points=2000` for 30 days and `5000` for 90 days.
  **AC** Request URLs match; a 400 from the API surfaces as an error banner, not an empty map.
- FR-7.4 Summary distance is haversine over displayed points and is labelled "约".
- FR-7.5 An empty range hides the map and shows "该时间段没有位置记录".

### 5.8 Cross-cutting behaviour — FR-8

- FR-8.1 **Freshness.** `stale == true` with a non-asleep state shows an orange banner; an asleep
  car shows a neutral "车辆休眠 · 数据停在 …" line. **AC** Neither case ever renders as current
  truth without a label.
- FR-8.2 **Caching.** The last successful response per screen is cached and shown when the network
  fails, labelled with its timestamp. **AC** Killing the API leaves the app usable and clearly
  marked offline.
- FR-8.3 **401.** Handled once per screen with a "去设置" action; no automatic retry loop.
- FR-8.4 **Empty states** carry one action (change period, retry) and never fake data.
- FR-8.5 **Loading.** First load shows skeletons; subsequent loads keep existing content and show
  a small spinner.

### 5.9 Maps — FR-9

Four surfaces carry a map and nothing else does. On every one of them the map is a second view of
data the screen already states in text, never the only carrier of it.

- FR-9.1 **Surfaces.** Live shows the last known position; Drive Detail shows one drive's polyline;
  History shows the selected range's track; Stats shows an entry card and no map.
  **AC** No other screen instantiates a map; the Stats card opens History with the current period
  carried over.
- FR-9.2 **Coordinates.** The API and storage are WGS-84. Rendering converts to GCJ-02 only when
  `mapOffsetCorrection` is on *and* the point is inside China; outside China nothing is applied.
  **AC** With the switch on, a known coordinate lands on its road; with it off, it is displaced by
  a consistent ~500 m in the same direction; toggling re-renders without any network request.
- FR-9.3 **Camera.** Every map opens fitted to its content with ≥ 12 % padding, pitch 0, rotation
  off. Live re-centres on new positions only while the user has not panned the map; after a pan, a
  recenter control appears and following stops until it is tapped. Drive Detail and History never
  move on their own. **AC** Opening a drive shows the whole polyline inside the frame; panning
  during an active drive does not snap back; the control restores the camera and resumes following.
- FR-9.4 **Line and markers.** One stroke for the track; start and end markers differ by shape, not
  only by colour. No charge pins, no geofences, no clustering in v1.
  **AC** Start and end remain distinguishable in greyscale and are each labelled.
- FR-9.5 **No location permission.** The app never asks for the user's location and never draws a
  user dot. **AC** No `NSLocation*` key exists in the built Info.plist; no prompt appears on any map
  surface, on first use or after.
- FR-9.6 **Volume.** The client draws the downsampled response as received and never aggregates raw
  positions itself. **AC** A 5 000-point track pans and zooms at 60 fps on the oldest supported
  device.
- FR-9.7 **Empty, error, offline.** A range with no positions hides the map frame entirely and
  shows one message with one action; a 400 shows a banner and keeps the previous state; offline
  shows the cached track over blank tiles, labelled with its timestamp.
  **AC** None of the three renders an empty map frame with no explanation.
- FR-9.8 **Accessibility.** Every map has a text alternative carrying distance and start/end names.
  **AC** VoiceOver announces the summary, and every fact visible on the map also exists as text
  outside it.
- FR-9.9 **Style.** Standard map, flat elevation, no traffic, no 3D.
  **AC** Every surface matches UI-DESIGN §7.

## 6. Non-functional requirements

| ID | Requirement | Acceptance |
|---|---|---|
| NFR-1 | Read-only | Postgres role has `SELECT` only and no access to `private`; the app issues no mutation endpoint because none exists |
| NFR-2 | Transport | iPhone connects over HTTPS to a public fixed-domain reverse proxy with Bearer authentication; the proxy reaches the Mac API over Tailscale. The Mac API is not exposed directly to the public; the phone does not need Tailscale |
| NFR-3 | Secrets | Token only in the Keychain; VIN, DB and MQTT credentials never returned by the API or logged |
| NFR-4 | Request cost | 120 requests/minute per client, 60/minute for `/live`; a 3 s poll is 20/minute, so a manual refresh alongside polling never trips the limit |
| NFR-5 | Performance | Live screen interactive < 1.5 s cold; list/detail first render < 300 ms after the response; scrolling stays at 60 fps |
| NFR-6 | Data volume | A 90-day track is one downsampled response (≤ 5 000 points); no client-side aggregation of raw positions |
| NFR-7 | Reliability | API restart does not lose the app's ability to recover (next poll succeeds); stale data is always labelled, never silently trusted |
| NFR-8 | Accessibility | Dynamic Type, VoiceOver labels on charts and the battery ring, targets ≥ 44 pt, reduce-motion respected |
| NFR-9 | Localisation | Chinese-first copy for v1; all strings externalised so an English pass needs no layout change |
| NFR-10 | Compatibility | iOS 17+, iPhone portrait only; dark-only |

## 7. Dependencies and constraints

- TeslaMate's schema and MQTT topic names are external contracts. A TeslaMate upgrade that renames
  a topic degrades Live gracefully (missing values are omitted, not errors).
- The planned public reverse proxy must be reachable over HTTPS and able to reach the Mac API over
  Tailscale; the phone does not need Tailscale. There is no cloud data fallback.
- Distances and consumption are TeslaMate's numbers; the app must not re-derive them differently
  (History's haversine is explicitly labelled "约").
- `max_points` caps are API-enforced (10–5000); the client must not assume more.

## 8. Open questions

| # | Question | Impact |
|---|---|---|
| Q1 | Should the app remember the last period (7/30/90) per tab, or always reset to 30? | Minor UX; default is reset to 30 |
| Q2 | Is an English localisation needed for v1, or is externalised Chinese enough? | Strings only |
| Q3 | Should Live keep polling in the background for a few minutes after backgrounding? | Battery vs freshness; current spec says stop |
| Q4 | Should the Live map keep following the car for the whole drive, or stop after the first pan and only resume on tap? | Battery, and a camera that fights the user; current spec follows until the first pan |

## 9. Milestones

| Milestone | Content | Status |
|---|---|---|
| M1 Read-only API | All `/v1` routes, auth, rate limit, MQTT cache, 39 tests | Implemented and regression-tested; real-service validation pending |
| M2 UI design | Design system, 9 screens, 9 mockups, header wrap on scroll | Done |
| M3 Live screen | Polling, charging/route cards, stale handling, security row | Partially built — data layer and one screen only |
| M4 Log and trends | Drives, Charging, Stats (+ details) | Not started |
| M5 History | Track map, two entry points | Not started |
| M6 On-device validation | Public HTTPS proxy and Tailscale path, real data, coordinate check, accessibility pass | Not started |

**Current build state:** the API routes are implemented, and the audited gaps in cost totals, freshness, rate limiting, pagination and timezone handling have been fixed with regression tests. Validation against the real TeslaMate deployment remains outstanding. On iOS, `LiveView`, its view model and the shared shell compile; `DrivesView`, `ChargingView`, `StatsView` and `SettingsView` exist as placeholders.

## 10. Deferred (post-v1)

Requirements that are agreed in principle but **not built in v1**. They carry `DF-` IDs so they are
never mistaken for v1 commitments, and they are excluded from the completion tracker's totals.

### DF-1 Vehicle model on Live — deferred, no date

A 3D model of the car on the Live screen, reflecting per-part state: the four doors, trunk, frunk and
charge-port flap opening and closing to match the car. The data already exists — `/live` exposes
`driver_front_door_open`, `trunk_open`, `charge_port_door_open` and their siblings — so this is a
presentation problem, not a backend one.

- DF-1.1 **Scope.** The model replaces or sits beside the battery ring on Live and mirrors
  per-part state within one poll interval (~3 s). **AC** Opening any door on the car is visible on
  the model within 5 s.
- DF-1.2 **Rendering.** RealityKit with `RealityView` (available at the iOS 17 target), USDZ asset,
  on-demand rendering. SceneKit is deprecated from iOS 26; a three.js/`WKWebView` path is rejected
  (extra runtime, continuous frame loop, heavier cold start).
- DF-1.3 **Asset.** Per-part nodes with hinge-correct pivots; 1 unit = 1 m, Y-up; PBR materials
  authored for the dark palette; licensed for use — Tesla's own models and renders may not be used.
  **AC** In Blender each door is a separate object and rotates about its hinge.
- DF-1.4 **Unknown state.** A `null` field never animates a part into the closed position; the part
  holds its last known pose and the screen shows the normal freshness treatment (FR-8.1).
- DF-1.5 **Cost.** The scene is built once and mutated per poll, never rebuilt; must not regress
  NFR-5.
- DF-1.6 **Fallback.** If no rigged asset is available, tint the open part instead of moving it —
  same data, same layout, no rigging.

Open problems, unsolved and the reason this is deferred:

- **Far-side visibility.** From a 3/4 angle a left-rear door is hidden behind the body. Options are
  an automatic camera swing, a top-down inset, or accepting that the security row stays the source
  of truth. None is chosen.
- **Granularity.** The car reports booleans: no "ajar", no window height.
- **Asset cost.** The model, its pivots and its materials are the bulk of the work, not the code.

### DF-2 Charging cost at a third-party station — deferred, manual entry only

The car charges somewhere Oto has no price for, and the operator's completion notice carries the
amount. That notice is never an input: iOS gives no public API for reading another app's
notifications, and neither a Notification Service Extension nor a message filter extension may
store or forward their content. So the only path is for the user to supply the number, and the work
is to make that nearly free.

Oto already holds the session's energy, duration, start and end times, and location. The amount is
the single thing it cannot derive.

- DF-2.1 **Entry point.** Charge Detail carries one action, "记一笔费用". **AC** Reachable in one tap
  from the session; a session that already has a cost shows the cost instead of the action.
- DF-2.2 **Defaults.** The form presents the session's kWh, duration, station and start time as
  read-only context; the amount is the only input, with an optional note.
  **AC** No field asks the user to retype a value Oto already has.
- DF-2.3 **Clipboard pre-fill.** When the clipboard holds exactly one currency amount (e.g.
  `¥45.60`, `45.6元`), the amount field opens pre-filled, and the value stays visible and editable
  before saving. **AC** Text with no unambiguous amount leaves the field empty; nothing is saved
  without an explicit tap.
- DF-2.4 **Source labelling.** A manually entered amount is always labelled as manual and is never
  presented as a TeslaMate figure. **AC** Both the charging row and the detail carry the marker.
- DF-2.5 **Merge rule.** A TeslaMate `cost` and a manual amount are never silently combined; where
  both exist the API value is primary and the manual one is shown beneath it, labelled.
  **AC** Both are visible and distinguishable, and the Stats total never adds them together.

Rejected paths, and why:

- **OCR of a shared receipt.** Returns the real bill, but needs its own screen, a confirmation step
  and per-operator parsing — more work than the value it adds once clipboard pre-fill exists.
- **Operator APIs.** None are public.
- **The completion notification.** Impossible on iOS, not merely difficult.
- **Geofence tariffs.** TeslaMate's own `cost_per_unit` / `session_fee` remain the better answer for
  a fixed station, and need no Oto code at all — this item exists for the stations where that
  arithmetic does not match the bill.

Open problems, and the reason this is deferred:

- **Where the amount lives.** Oto is read-only by construction (NFR-1, SELECT-only role, no mutation
  route). Keeping manually entered costs in Oto's own store preserves that but creates two sources
  of truth: the Stats total has to merge local amounts with the API's, and a session that later
  gains a TeslaMate cost has to reconcile. The alternative — a narrow endpoint that `UPDATE`s only
  `charging_processes.cost` — gives one number and breaks NFR-1. Undecided, and it gates the item.
- **A wrong number is permanent.** Manual entry has no cross-check against energy or tariff; only
  the confirmation step stands between a typo and the historical record.

## 11. References

- [`UI-DESIGN.md`](UI-DESIGN.md) — design system, screens, states, accessibility
- [`UI-COMPONENTS.md`](UI-COMPONENTS.md) — the reusable components, their variants and what exists
- [`TECH-STACK.md`](TECH-STACK.md) — technologies, versions, and implementation status
- [`API.md`](API.md) — endpoints, units, error codes
- [`mockups/index.html`](mockups/index.html) — visual reference
- [`../README.md`](../README.md) — deployment, Tailscale, security notes
