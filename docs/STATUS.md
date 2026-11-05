# Oto — Completion Tracker

Living checklist for [`PRD.md`](PRD.md). Tick an item when it is built **and** its acceptance
criteria pass; a tick means "verified", not "written". IDs match the PRD and never change.

Last updated: 2026-11-03 · 中文版：[`STATUS.zh-CN.md`](STATUS.zh-CN.md)

---

## Progress

| Area | Done | Total |
|---|---|---|
| Server API (M1, 10 routes) | 10 | 10 |
| FR-1 Onboarding | 3 | 3 |
| FR-2 Settings | 4 | 4 |
| FR-3 Live | 6 | 6 |
| FR-4 Drives | 7 | 7 |
| FR-5 Charging | 3 | 3 |
| FR-6 Stats | 4 | 4 |
| FR-7 History | 5 | 5 |
| FR-8 Cross-cutting | 5 | 5 |
| FR-9 Maps | 8 | 9 |
| **Functional total** | **45** | **46** |

**Build state:** the iOS target compiles (verified with `xcodebuild` for the iOS Simulator).
Onboarding and Settings (`SettingsView`, `SettingsViewModel`, `ConnectionForm`) were exercised end to
end against the mock through a temporary UI-test target — the validation messages, the Keychain
save, the car switch, the offset switch and clearing the token — and pass. The Keychain only works in
a signed build: with `CODE_SIGNING_ALLOWED=NO` the save fails with `-34018` and the form says
`无法保存 Token（Keychain 错误 -34018）`, so those runs used ad-hoc signing. The Drives list and drive detail (`DrivesView`,
`DriveDetailView`, their view models, `TripRow`, `StickyDayHeader`, `ListFooter`) are implemented and
were exercised end to end against a temporary local mock through the same UI-test target — the
period switch, paging with a duplicate check, geofence-over-address, the summary sum, the
consumption boundaries, the elevation threshold and the no-positions banner all pass, so FR-4 is
complete. Live (FR-3) was exercised the same way: polling on and off the tab, backgrounding,
pull-to-refresh next to the 3 s cycle, the charging card, the route card, the security row and the
last-updated stamp. The Charging list and charge detail
(`ChargingView`, `ChargeDetailView`, their view models, `ChargeRow`, `SoCBar`, `StatStrip`) are
built and were exercised end to end the same way: the period switch, paging without duplicates, a
cost-less row, the last-valid-sample facts and the all-null session that omits every curve. Stats
(`StatsView`, `StatsViewModel`, `BarChart`) was exercised the same way: three UI tests plus three
view-model tests against the mock's gapped range — the filters in one row, the refetch parameters,
the four tiles, the "—" cost, the zero-filled buckets and a tap on a bar that goes nowhere. History (`HistoryView`, `HistoryViewModel`) is
built — a full-width map fitted to the track, start and end markers, and a summary sheet with the
distance, point count, range and coordinate note — and was rendered from both entry points plus its
empty and 400 states. Cross-cutting behaviour (FR-8) is built and was exercised against the same
mock: freshness banners, skeleton first loads, a per-screen session cache restored offline with its
timestamp, and one 401 path per screen into Settings. Maps (FR-9) are now one component: `MapSurface`
is the only place a `Map` is instantiated, `TrackLayer` draws the stroke, the start dot and the
chevron, and `MapOverlayPill` / `RecenterControl` carry the overlays. Live, drive detail and History
were moved onto it and exercised against the mock with a moving position, a 400 after a good load,
an offline reload and a coordinate-toggle redraw. The camera fit is covered by
`TeslaMateViewerTests/MapFittingTests`, run with `xcodebuild test`; a temporary UI-test target drove
a real drag on the Live map, read the accessibility labels and measured the frame rate, then was
removed once the run finished. History (FR-7) was exercised through the same target with seven UI
tests: both entry points and the return to the origin tab, the five-item tab bar, the period carried
in and kept local, a 400, an empty range and the haversine summary. The FR-3 – FR-7 runs were 28 UI
tests plus the five `MapFittingTests` and three temporary `StatsViewModel` tests, all passing
(`xcodebuild test` with ad-hoc signing); the UI-test target, the temporary tests and the mock were
removed once each run finished. FR-9.6 was measured separately, with two temporary UI tests driving
five real drags at 5 000 and at 200 points while a temporary `CADisplayLink` overlay on the History
map published its frame rate as an accessibility value — first on the simulator, then on a physical
iPhone 14 Pro Max reaching the mock over the LAN; both the overlay and the tests were removed after
the numbers were recorded below.

---

## Server — read-only API

- [x] All ten `/v1` routes registered — `server/src/server.js:8-33`
- [x] Bearer auth, timing-safe compare, 401 without leaking detail — `server/src/auth.js`
- [x] Rate limit: 120/min per client including `/live`, plus 60/min for `/live`; trusted-proxy
      client identity via `PROXY_TOKEN` and validated headers
- [x] MQTT cache with per-field `field_metadata`; disconnect, retained and aged fields mark the
      snapshot stale, and `observation_freshness` stays `unknown` — `server/src/live.js`
- [x] Read-only Postgres role, no `private` schema
- [x] 39 tests; 7 history regressions run against a disposable PostgreSQL 18 instance and skip
      without `HISTORY_TEST_DATABASE_URL`

## FR-1 Onboarding — 3 / 3

- [x] **FR-1.1** First launch shows onboarding instead of tabs — *no tab bar; URL and token fields
      present*. `RootView` chooses `SettingsView(isOnboarding:)` when no client can be built; a UI
      test on a clean install asserts the absent tab bar and both fields.
- [x] **FR-1.2** "测试并保存" validates scheme/host, writes the Keychain, calls `GET /v1/cars`
      before entering — *bad URL, 401 and timeout each get their own message*. Each case was run
      against the mock (25 s delay on `/v1/cars` for the timeout), and a 200 showed
      `连接成功 · 2 辆车` before the tabs appeared. Transport errors other than a timeout used to
      fall through to the system's English text; they now use the same Chinese mapping as the rest
      of the app.
- [x] **FR-1.3** Token never reaches `UserDefaults`, logs or source — *Keychain is the only store*.
      The app's preferences hold `baseURL`, `carId` and `mapOffsetCorrection` and nothing else; the
      token survives a relaunch (the app opens straight to the tabs) and is gone once cleared.

## FR-2 Settings — 4 / 4

- [x] **FR-2.1** Changing server or token re-validates; a bad value never replaces a working one.
      An invalid URL in the editor showed its message and, after Cancel, the working server was
      still in the row.
- [x] **FR-2.2** Changing the car clears every cache and reloads all tabs. The car menu now drops
      `ScreenCache` on a change, and Stats starts from an empty chart for a different car; the
      mock log shows the drives refetched for the newly chosen car and its rows replaced the old
      car's.
- [x] **FR-2.3** "清除 Token" confirms, then returns to onboarding. A relaunch stayed on
      onboarding, so the Keychain entry is gone.
- [x] **FR-2.4** Map-offset switch is on by default in China and re-renders without refetching.
      The switch reports 开启 on a fresh install and toggles both ways; its redraw without a request
      was captured during the FR-9 coordinate-toggle run.

## FR-3 Live — 6 / 6

Verified with a temporary UI-test target against a mock whose `/live` payload could be switched at
runtime (`charging`, `route`, `route_error`, `open`, `fail`) and which counted every request.

- [x] **FR-3.1** Polls `/live` every 3 s while `scenePhase == .active` — `LiveView.swift:86-97`.
      UI test: requests stop after switching to another tab and after backgrounding, and resume
      within 2 s of coming back.
- [x] **FR-3.2** Pull-to-refresh coexists with polling — `.refreshable` plus an independent loop.
      UI test: a pull adds exactly one request; the following 6 s still hold 1–3 polls (observed 2),
      so the cycle is neither cancelled nor doubled.
- [x] **FR-3.3** Charging card between battery and map — `LiveView.swift:174-202`.
      UI test: 充电功率 / 已充入 / 74% → 90% / 预计充满 45 分 appear with `charging_state`, disappear when
      it changes, and the battery ring keeps showing 74% in both states.
- [x] **FR-3.4** Route card; "No active route available" is treated as no route, not as an error —
      `LiveView.swift:302-324`. UI test: the card appears with `destination`, and the
      `{"error": …}` payload removes it without any error banner.
- [x] **FR-3.5** Security row: lock, sentry, doors and windows on one line; any open state turns it
      orange and makes it expandable — `LiveView.swift:393-479`. UI test: `locked=false` with
      `doors_open`/`windows_open=true` reads "有未关闭的项目", expands to 行李厢 / 前备厢, and returns to
      "全部正常", non-tappable, once every value is closed.
- [x] **FR-3.6** Last-updated is always visible and refreshes per poll — `LiveView.swift:139-141`
      (`live.lastUpdated`). UI test: the stamp follows a successful poll and keeps its value across
      failed polls, with the last good values still on screen.

## FR-4 Drives — 7 / 7

Verified with the same UI-test target against a mock of eight drives whose start geofence and start
address differ, paged four at a time.

- [x] **FR-4.1** 7/30/90 switch, default 30, refetch and scroll to top. UI test: the first request
      spans 30 days from now; 7 天 issues a new request spanning 7 days and the list is back at its
      first row afterwards.
- [x] **FR-4.2** Sticky day headers; geofence name wins over address. UI test: a drive with both
      reads 家 → 公司 and never shows 文三路.
- [x] **FR-4.3** `limit=100`, load at 80 %, ends with "没有更多行程", no duplicates. UI test with
      four drives per page: two requests (`limit=100`, the second carrying `before_id=27`), eight
      rows with each id once, footer "没有更多行程".
- [x] **FR-4.4** Summary strip computed from the loaded rows — UI test: eight drives read
      77.7 km / 8 次, the sum of the rows rather than an API figure.
- [x] **FR-4.5** Detail: polyline, speed/power/SoC charts on one time domain, facts block; a drive
      with no positions shows a banner and still navigates back — UI test: `positions: []` renders
      这段行程没有位置数据 and 返回 returns to the list.
- [x] **FR-4.6** Consumption `energy_kwh / distance_km × 100`; hidden under 0.5 km; green < 18,
      orange ≥ 18. UI test: 17.9 reads 正常 (green), 18.0 reads 偏高 (orange), a 0.3 km drive shows
      no badge. The level also sits in the accessibility value, so colour is not the only channel.
- [x] **FR-4.7** Elevation chart only when ≥ 30 % of points carry elevation. UI test: a full track
      shows 海拔; a track with elevation on 10 % of its points omits it.

## FR-5 Charging — 3 / 3

Verified with a temporary UI-test target against a mock of eight sessions paged four at a time: one
without a cost, one whose sample metrics are all null, and one where voltage, current and phases
last appear in different samples.

- [x] **FR-5.1** Same period control and pagination rules as Drives. UI test: the first request
      spans 30 days with `limit=100`; two requests, the second with `before_id=5`; eight rows and the
      footer 没有更多充电记录, each session once. 7 天 refetches a 7-day window and the summary drops
      to 7 次 / 122.2 kWh / ¥39.90.
- [x] **FR-5.2** SoC bar, kWh, duration and outside temperature per row; no cost reads
      "费用未记录", never "¥0.00". UI test: a row reads 电量 35% 到 81% · 33.9 kWh · 29 分 ·
      车外 22.5°C · ¥29.00, and the cost-less row reads 费用未记录.
- [x] **FR-5.3** Detail: power / SoC / energy-added curves plus facts from the last valid sample.
      UI test: a normal session shows 功率, 电量 and 已充电量 charts with 230 V · 16 A · 3 相 and IEC;
      the partial session reads 230 V · 8 A · 1 相 (each field from its own last valid sample) and
      hides the `<invalid>` connector; the all-null session shows no curves, keeps 22% / 55% / 45 分
      and still returns to the list.

## FR-6 Stats — 4 / 4

- [x] **FR-6.1** Period and bucket in one content row under the header — *changing either refetches
      without resetting the scroll*. One `HStack` holds both `SegmentedControl`s; a UI test asserts
      all five segments share one centre line (±10 pt) and sit above the tiles. Tapping 月 sent
      `bucket=month`, tapping 90 天 sent a `from` exactly 90 days back, and the tiles followed
      (231.8 → 452.1 km) while the filter row and the tiles kept their y. The controls scroll out of
      reach with the content, so scroll preservation was measured with the pinned header 刷新 — the
      same `model.load` the filters call: after a reload the chart was still where the swipe left it.
      `ScreenScaffold` is given no `scrollResetToken` here, so nothing changes the scroll view's
      `.id`. A filter change *while scrolled* cannot be driven from the UI, since the controls are
      offscreen by then; the refresh path is the proxy.
- [x] **FR-6.2** Four tiles equal the API totals; cost shows "—" when no session has a cost.
      Verified with mock buckets: 231.8 km, 17 drives, 32.7 kWh and ¥4.10 at 30 days, 63.2 km / 9
      drives at 7 days, 452.1 km at 90 days, all equal to the sums; a range whose every
      `charge_cost` is null shows "—" both in the tile and in `totalCost`.
- [x] **FR-6.3** Zero-filled buckets sharing one x domain. A 30-day range with data on 8 days
      yields 31 buckets of which 23 are zero — so the empty days stay empty instead of being
      compressed — and 30-day month buckets yield 2. All three charts are fed from that same array,
      so they share one domain. Month buckets label 10月 / 11月.
- [x] **FR-6.4** Bars are not tappable. No tap gesture or link is attached to a bar; a tap inside
      the chart area left the screen unchanged, with no 返回 button.

## FR-7 History — 5 / 5

- [x] **FR-7.1** Pushed from Drives and Stats, not a tab; back returns to the origin tab — *the tab
      bar keeps exactly five items*. UI tests: the bar is 实时 / 行程 / 充电 / 统计 / 设置 with no
      历史轨迹 item; the 轨迹 header action on Drives and the 历史轨迹地图 card on Stats each open the
      screen, the tab bar is gone while it is up (`tabBars.count == 0`), and 返回 lands back on the
      originating tab with five items restored and no refetch of that tab's list.
- [x] **FR-7.2** Period selector is local to History. Drives at 90 天 opened History on 90 days
      (`from` 90 days back, `max_points=5000`); switching to 7 天 inside History sent one 7-day
      request and nothing else; after 返回 the Drives filter still reads 90 天 and the list made no
      new request. The same round trip from Stats carried 30 天 in and left Stats on 30 天. The
      origin's period is passed by value into `HistoryViewModel(period:)`, and the segment buttons now
      carry `.isSelected`, so the assertion reads the selection rather than guessing from geometry.
- [x] **FR-7.3** `max_points` 2000 / 5000 by range; a 400 surfaces as an error banner. The mock's
      request log shows `max_points=2000` for 7 and 30 days and `5000` for 90; a 400 renders the
      orange banner with 重试 over the background and no map.
- [x] **FR-7.4** Summary distance is haversine over displayed points, labelled "约". 200 mock points
      read 6.9 km under 约轨迹长度 with 200 samples and the legend's 距离为采样点估算; the same points
      come to 6.924 km by hand.
- [x] **FR-7.5** Empty range hides the map and shows 该时间段没有位置记录. With zero points the map
      element is absent, the empty card reads that title and offers 切换时间段.

## FR-8 Cross-cutting — 5 / 5

- [x] **FR-8.1** Freshness: `stale` shows an orange banner; asleep shows a neutral line —
      `LiveView.swift:106-125`. Verified against the mock: `stale` with MQTT up renders
      "数据已过期，展示最后已知状态", MQTT down renders "MQTT 未连接，展示最后已知状态", and `asleep`
      renders the neutral "车辆休眠 · 数据停在 …".
- [x] **FR-8.2** Last successful response cached per screen and shown offline with its timestamp —
      `ScreenCache` (session-scoped, in memory) plus a restore branch in all seven view models.
      Verified on Drives: after a successful load the mock was stopped and a reload failed; the list
      stayed with "显示 11:11 的数据" and a retry action. The other screens share the same helper and
      branch but were not taken offline one by one.
- [x] **FR-8.3** 401 handled once per screen with a "去设置" action — `AuthBanner`,
      `Error.isUnauthorized`, `SettingsStore.wantsSettings`. Verified with every route returning 401:
      Live, Drives, Charging and Stats each show the banner or a 去设置 empty state, nothing retries,
      and the Settings sheet opens over the tabs.
- [x] **FR-8.4** Empty states carry one action — Drives "切换时间段", Live "重试" or "去设置",
      Charging and Stats "去设置", History "切换时间段".
- [x] **FR-8.5** Skeleton on first load, content plus small spinner afterwards — `Skeleton` in
      `Components/Skeleton.swift`. Verified with a 4 s mock delay: five card skeletons while empty,
      then the list. Stats keeps its charts and shows a small `ProgressView` while a period reloads
      (`StatsView.swift:58`); that state was not captured on screen.

## FR-9 Maps — 8 / 9

`Components/MapSurface.swift` holds the only `Map` in the app; `TrackLayer` draws the stroke and the
markers, `MapOverlayPill` and `RecenterControl` carry the overlays. Live, drive detail and History
all render through it.

- [x] **FR-9.1** Four surfaces only: Live position, Drive polyline, History track, Stats entry card.
      The Stats card is C-13, a `NavigationLink` into History, so it draws no map of its own.
- [x] **FR-9.2** WGS-84 → GCJ-02 only inside China with the switch on; toggling redraws without a
      request. Both states were captured, with one positions request in the mock log.
- [x] **FR-9.3** Camera fitted with ≥ 12 % padding; Live follows until the first pan, then shows a
      recenter control; Detail and History never move on their own. `MapFittingTests` asserts the
      1.4× span (20 % per edge) and both minimum spans; a UI test dragged the Live map, saw the
      recenter control appear and tapped it away; Detail and History pass no `follows` and refit
      only when their data changes.
- [x] **FR-9.4** One stroke; start and end differ by shape, not only colour; no pins or clustering.
      A filled green dot at the start and an orange chevron at the end.
- [x] **FR-9.5** No location permission and no user dot — no `NSLocation*` key in the built plist.
- [ ] **FR-9.6** 5 000-point track at 60 fps; no client-side aggregation of raw positions. Nothing is
      aggregated: a 90-day range asks for `max_points=5000`, the strip reads 5 000 采样点, and
      `TrackLayer` hands that same array to `MapPolyline` — no stride, no sampling. Re-measured with a
      temporary `CADisplayLink` probe read through an accessibility value while five real drags ran.
      On the simulator (iPhone 18 Pro Max): at rest 60.0 fps with a 60.0 worst frame (two runs), across
      the drags 48.7 and 51.9 fps with single frames down to 13.7, and a 200-point track over the same
      drags averaging 51.2 with an 18.7 worst frame. On a physical iPhone 14 Pro Max (iOS 27.2) against
      the mock over the LAN, with `max_points=5000` in the mock's query log: at rest 60.0 fps with a
      60.0 worst frame (two runs, one 59.8), across the drags 58.3 and 58.6 fps with the worst frame at
      20.0 and 25.0, and back to 60.0 once the drags settled; the 200-point baseline over the same
      drags averages 59.0 with a 24.2 worst frame. The point count therefore costs about half a frame
      per second — the rest of the dip is the gesture and tile cost. It still does not hold a flat
      60 during drags, and the AC names the oldest supported device (iPhone XS, the oldest iOS 17
      phone), which was not available — a run on an A12-class device is what closes this, so it stays
      open.
- [x] **FR-9.7** No positions hides the frame; a 400 keeps the previous map under a banner; offline
      draws the cached track over blank tiles with its timestamp. The 400, the connection failure and
      the offline reload were each run against the mock.
- [x] **FR-9.8** Each map has a text alternative with distance and start/end names. A UI test read
      the accessibility tree: History exposes `历史轨迹，6.9 km，…` and Live `车辆最后位置，…`;
      drive detail names the distance and both places. VoiceOver speech itself was not run.
- [x] **FR-9.9** Standard map, flat, no traffic, no 3D, on every surface —
      `.standard(elevation: .flat, pointsOfInterest: .excludingAll)` in the one `Map`.

---

## Non-functional

Not ticked at the same granularity as FRs — most are properties of the finished app, not standalone
tasks. Keep them visible so they are not discovered at the end.

| ID | Requirement | State |
|---|---|---|
| NFR-1 | Read-only throughout | Server side done; app side structural |
| NFR-2 | Public HTTPS proxy → Tailscale → Mac API; phone needs no Tailscale | Proxy deployment and end-to-end validation pending |
| NFR-3 | Secrets only in Keychain | `TokenStore` exists; audit outstanding |
| NFR-4 | Rate limits | Done server-side |
| NFR-5 | Live < 1.5 s, first render < 300 ms, 60 fps | Unmeasured |
| NFR-6 | 90-day track in one ≤ 5000-point response | Server side done |
| NFR-7 | API restart recoverable; stale always labelled | Partially in place |
| NFR-8 | Dynamic Type, VoiceOver, 44 pt targets, reduce-motion | Design specified only |
| NFR-9 | Chinese-first, strings externalised | Hard-coded Chinese strings in views |
| NFR-10 | iOS 17+, iPhone portrait, dark only | Configured in `project.yml` |

---

## Milestones

- [x] **M1** Read-only API — all routes, auth, rate limit, MQTT cache, 39 tests; real-deployment
      validation pending
- [x] **M2** UI design — design system, 9 screens, 9 mockups, header wrap on scroll
- [ ] **M3** Live screen — polling and cards exist; security row and freshness treatment unfinished
- [ ] **M4** Log and trends — Drives, Charging, Stats (+ details)
- [ ] **M5** History — track map, two entry points
- [ ] **M6** On-device validation — public HTTPS proxy and Tailscale path, real data, coordinate check, accessibility pass

---

## Deferred (not counted)

Agreed but not in v1 — deliberately kept out of the totals above so the percentage stays honest.

- **DF-1 Vehicle model on Live** (PRD §10) — a 3D car mirroring per-door state. Data already exists
  in `/live`; blocked on a rigged, licensed USDZ asset and an unresolved decision about seeing the
  far-side door. Revisit only if the asset budget appears.
- **DF-2 Charging cost at a third-party station** (PRD §10) — manual entry with smart defaults on
  Charge Detail, chosen over receipt OCR and operator APIs. Blocked on where the amount is stored: a
  local store creates a second source of truth, and writing back to `charging_processes.cost` breaks
  NFR-1.

---

## How to update

1. Change `- [ ]` to `- [x]` only when the acceptance criteria in the PRD have been run.
2. Bump the matching row in §Progress, and the functional total.
3. Update `Last updated`.
4. If an item turns out to need several commits, split it into sub-bullets under the same ID rather
   than inventing new IDs — the PRD's IDs are stable references.
