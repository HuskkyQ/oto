# Odo vs Teskeeper — feature gap analysis

Status: analysis complete, not yet scheduled · 2026-11-04 · Owner: Steven
中文版：[`GAP-ANALYSIS.zh-CN.md`](GAP-ANALYSIS.zh-CN.md)
Inputs: [`REFERENCE-TETE.md`](REFERENCE-TETE.md) (21 screens, 37 screenshots) and an audit of the
current code (iOS: 4 tabs plus settings; server: 10 `/v1` routes).

This document answers one question: **against Teskeeper, what should Odo add next, and in what
order.** It does not replace [`PRD.md`](PRD.md) — the PRD defines what v1 promises; this file only
lists candidates beyond v1 and the reasoning behind them.

---

## 1. Conclusion

Odo's v1 backbone is complete: live, drives, charging, stats and history are all usable end to end,
and the drive detail is deeper than the reference app's (speed, power, battery and elevation on four
charts sharing one time axis).

The gaps are not about screen count. They cluster in three places:

1. **Turning available data into insight**: today's board, a 24-hour state timeline, parking,
   battery health, consumption analysis, trip calendar.
2. **List-row depth**: drives lack average speed, range efficiency and start/end SoC; charging lacks
   AC/DC and charging speed.
3. **Map interaction**: only fixed 7/30/90-day windows; no custom range, per-drive colours, summary
   card or image export.

The cheapest win is two endpoints that **already exist but are never called from the UI**:
`/states` and `/updates`. Their client methods and models are in place
(`APIClient.swift:144`, `APIClient.swift:155`); only the screens are missing.

---

## 2. Method

- Compared screen by screen against the 21 screens in the reference doc, not against feature nouns.
- Counted a capability as actionable only when the data is already in TeslaMate or already returned
  by an existing route. Anything needing an external data source, write access or hardware is listed
  as "not doing".
- Sizes cover implementation only — not tests, on-device acceptance or doc sync:
  **XS** ≤ 0.5 day, **S** 1–2 days, **M** 3–5 days, **L** 1–2 weeks or more.

---

## 3. Current state

| Area | Implemented | Where |
| --- | --- | --- |
| Live | 3 s polling, battery ring, charging card, location map, security row, climate, vehicle facts, route card, freshness banner | `Features/Live/` |
| Drives | 7/30/90 days, day grouping, sticky date headers, cursor paging, detail map, four charts, facts, consumption badge | `Features/Drives/` |
| Charging | 7/30/90 days, paging, SoC bar, missing-cost handling, detail charts, voltage/current/phases/connector | `Features/Charging/` |
| Stats | 7/30/90 days × day/month, four tiles, three bar charts, history entry | `Features/Stats/` |
| History | Full-screen map, start/end markers, summary sheet, coordinate correction, offline cache label | `Features/History/` |
| Settings | Server URL, token (Keychain), vehicle switch, coordinate offset, clear token | `Features/Settings/` |
| Server | 10 `/v1` routes, bearer auth, two rate limits, MQTT cache, 39 tests | `server/src/` |
| Ready but unused | `/v1/cars/:id/states` and `/v1/cars/:id/updates` have client methods and models | `APIClient.swift` |

---

## 4. Gap table

Legend: **Have** = covered and no weaker than the reference; **Partial** = structure exists, fields
or interactions missing; **Missing** = absent; **No** = conflicts with the read-only position, the
PRD scope or asset constraints.

| Reference feature | Status | What to add | Data source | Size |
| --- | --- | --- | --- | --- |
| Home overview | Partial (Live tab carries it) | Today's board, 24 h state timeline, monthly mileage, tyre comparison card | `/live`, `/states`, `/stats` | M |
| Today's board | Missing | Drive count, distance, duration and energy for the day; date picker and "back to last 24 h" | `/stats` day buckets, `/states` | S |
| State timeline + legend | Missing | Driving / online / asleep / charging bars; legend screen | `/states` (ready) | S |
| 3D car and full screen | No (DF-1 deferred) | — | Needs a hinged USDZ asset | — |
| HUD overlay | No | — | Needs background refresh and system overlay | — |
| Desktop / home widget | Missing (excluded by PRD) | WidgetKit small/medium; App Group for token and cache | `/live` | M |
| Drive rows | Partial | Average speed, range efficiency, start/end SoC and range, per-drive Wh/km | `/drives` needs `battery_level`; Wh/km needs energy | S |
| Drive detail | Have (stronger) | Max-speed marker, share, map style | `speed_max`, `positions` | S |
| Merge trips / distance filter | Missing | Merge as a read-only aggregate view; distance filter is client-side | `/drives` | S |
| Charging rows | Partial | AC/DC badge, distance since last charge | `/charges` needs aggregated `fast_charger_present` | S |
| Charging detail | Partial | Added range, charging speed in km/h, average power | `samples` suffice, client-side | S |
| Parking sessions | Missing | Duration, sleep share, average power, energy and range loss | Derived from `states`, `positions` and the gaps between drives/charges | L |
| Battery health | Missing | Capacity and range degradation, retention, rating; define the estimate first | Estimated from `charging_processes` + `positions` | L |
| Trip calendar | Missing | Month heat map (distance, drives, charges) plus monthly totals | `/stats` day buckets (some totals need energy and parking) | M |
| Track map | Partial (7/30/90 only) | Custom range, per-drive colours, start/end markers, summary card, image export | `/positions` already accepts any `from`/`to` | M |
| Charging-station map | Missing | Own-station aggregation (coordinates + peak power); "shared network" needs an external POI source | `charging_processes` + `addresses` coordinates | M |
| Consumption analysis | Missing | Group by software version / season / temperature, with a season-correction toggle | `/updates` (ready) joined to `drives` by time | M |
| Regenerative braking | Missing | Recovered energy, peak/average power, weekly view, driving-profile radar | Integral of `positions.power < 0` | M |
| Card management | Missing (depends on home) | Toggles and drag ordering; only meaningful after a home exists | Local preferences | S |
| Bluetooth key | No | — | Needs BLE vehicle-command and write access | — |
| Disclaimer / about | Missing | In-app text or web view | — | XS |
| Notifications | Missing (excluded by PRD) | APNs plus server events; the reference app retired its own notifications, so re-check demand | MQTT events | L |
| Find my car | Partial (map only) | Zero-permission option: navigate to the car in system Maps; a compass needs location permission | Vehicle coordinates | XS |
| Dashcam viewer | No | — | Needs a USB drive and car-side files | — |
| Vehicle automation | No | — | Write operations, violates NFR-1 | — |
| Appearance / skins | No | — | Needs 3D assets and an editor | — |

---

> **Update 2026-11-04 — five rows above are now built.** The Live today board with the 24 h state
> band (`Features/Live/TodayBoard.swift`, `TodayViewModel.swift`), its legend sheet, the richer drive
> rows (`Components/TripRow.swift`; `/drives` gained `start_battery_level` / `end_battery_level`),
> the trip calendar (`Features/Drives/TripCalendarView.swift`) and the track's custom time range
> (`Features/History/HistoryFilterSheet.swift`). `/states` now returns every state that overlaps the
> window, so a band that starts at midnight is not blank. Still open: per-drive Wh/km, parking,
> battery health, consumption analysis, regen, charging-station map.

> **Update 2026-11-05 — the four P1 screens and two new routes are built.** `server/src/routes/derived.js`
> adds `/energy` (Wh/km grouped by software version, season or temperature, weighted by distance),
> `/regen` (negative power inside drives only — otherwise a five-minute charging sample reads as
> 51 kW of regen), `/parking` (gaps between drives and charges, ≥ 10 minutes, at most 60 sessions)
> and `/battery` (charges spanning ≥ 40 percentage points; the recent median against the best value
> ever seen). The screens are in `Features/Insights/`, reachable from Stats and Drives. Response
> shapes and口径 are in [`API.md`](API.md).
>
> Deliberately not built: the 季节修正 switch (needs a seasonal normalisation model; the groups are
> shown side by side instead), the 驾驶习惯画像 meters (regen share / peak intensity / stability are
> not quantities `positions` supports reliably), and 哨兵模式 in the parking detail (TeslaMate keeps
> no sentry history). The parking detail has no `/parking/:id`: the list row already carries every
> field. And `/parking`'s energy is **not** an integral of `positions.power` — a sleeping car is not
> sampled, so the integral undercounts by an order of magnitude; it is the rated range lost, priced
> at the car's own Wh/km.

## 5. Priority

### P0 — quick wins (reuse existing routes, 1–3 days)

1. **Today's board + 24 h state timeline.** Put it at the top of the Live page; do not add a fifth
   tab. Use `/stats?bucket=day` for count, distance, duration and charging, and `/states` for the
   timeline and legend. The date picker only changes the query window. Note: Wh/km and energy
   consumed are not in `/stats`; either omit them in v1 or show "—".
2. **List-row fields.**
   - Drives: average speed (distance ÷ duration, client-side), range efficiency (start minus end
     ideal range ÷ distance), start/end range (already returned).
   - Charging: charging speed in km/h (range delta ÷ time from `samples`, detail page).
   - Two server fields: start/end SoC on `drives`, fast-charger flag on `charges`. Neither changes
     the response shape.
3. **Trip calendar.** Build the month grid and monthly totals from `/stats` day buckets. The
   consumption split in the reference's nine stats needs energy and parking data; defer it.
4. **Zero-permission find-my-car + disclaimer.** "Navigate to the car" hands coordinates to Maps
   without requesting location permission, so FR-9.5 stays intact.

### P1 — medium term (new routes or definitions, about 1–2 weeks)

1. **Parking sessions.** Derive intervals from the gaps between `drives` and `charging_processes`,
   then overlay `states` for sleep share. Define "how long counts as parking", "which samples feed
   average power" and "split at midnight?" before building.
2. **Consumption analysis.** Join `/updates` version windows to `drives.start_date` and aggregate
   Wh/km by version, season and temperature. Needs one aggregation route and a written definition
   of season correction.
3. **Track map enhancements.** Custom range, colour by `drive_id`, start/end markers and summary
   card; export via `MapSnapshotter`, no server involvement.
4. **Battery health.** Only estimate when there are enough samples; show the sample count and the
   word "estimate" on screen so the "never mislead" goal holds. Define the method before the UI.
5. **Regenerative braking.** Aggregate negative-power integrals per day on the server; do the weekly
   view on the client. The radar profile comes last.

### P2 — scope change first

- **Widget**: PRD §4 excludes widgets; doing it means changing the PRD and the token-sharing model.
- **Notifications**: needs APNs, server events and a permission prompt; the reference app retired
  its own, so validate demand first.
- **Shared charging network**: needs an external POI source with quotas and licensing; not a fit for
  the self-hosted path.

### Not doing

Vehicle automation and BLE keys (write operations), dashcam (hardware and USB), 3D car and skins
(assets), HUD overlay (background and system capabilities), shared charging network (external data).

---

## 6. Three decisions to make first

1. **A home screen or not.** The reference app has no tab bar and aggregates everything on one long
   home page; Odo has four tabs. The recommendation is no home and no fifth tab — put today's board
   and the timeline at the top of Live. A home screen only makes card management meaningful.
2. **The Wh/km definition.** TeslaMate's `drives` table has no energy column, so list-level Wh/km
   means integrating `positions.power`. Either pre-compute and cache it per drive on the server, or
   keep it on the detail page only. This decides how far P0 item 2 goes.
3. **Location permission or not.** A compass needs the user's location, while FR-9.5 states the app
   requests none. The zero-permission fallback is "navigate in system Maps", one notch worse in
   experience but no scope change.

---

## 7. Cost and risks

- **Every new route costs three things**: SQL and parameter validation, the `API.md` /
  `API.zh-CN.md` contract, and server tests (39 today). Estimate by "routes × 3", not by screens.
- **Derived data needs a written definition first**: parking, battery health and regen have no
  TeslaMate table. Different definitions produce numbers that disagree with TeslaMate Web, and the
  PRD's goal is "never mislead".
- **Do not hide gaps behind estimates**: show "—" when energy is unavailable; never back Wh/km out
  of a battery-percentage delta.
- **Accessibility and offline fallback are the existing baseline**: new screens must reuse
  `ScreenCache`, `AuthBanner`, `EmptyStateView` and the map's text alternative, not just the
  "data exists" path.
- **Verify the same way as today**: temporary UI test target against a mock, removed afterwards. The
  PRD numbering stays stable — add an FR before implementing.

---

## 8. What not to copy

- The reference app's charging cost is a placeholder on the detail screen; Odo's "cost not recorded"
  is the correct behaviour.
- Its "shared charging map" depends on its cloud service and an external station database; the
  self-hosted path cannot reproduce it.
- Its notification feature is retired in the app itself, so it is not evidence of a required feature.
- It has no tab bar and pushes everything onto one home page; Odo's four-tab structure is clearer.
  Do not dismantle it in the name of parity.
