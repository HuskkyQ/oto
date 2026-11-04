# Odo — UI Component Inventory

The reusable layer between `Design/Theme.swift` and the nine screens. Design rules live in
[`UI-DESIGN.md`](UI-DESIGN.md); this document says only **what the parts are, where each one is
used, and what is already built**. 中文版：[`UI-COMPONENTS.zh-CN.md`](UI-COMPONENTS.zh-CN.md).
Visual: [`mockups/components.html`](mockups/components.html) renders every component below with its
variants; C-39–C-44, added 2026-11-04, are drawn in [`mockups/gap-screens.html`](mockups/gap-screens.html).

Last updated: 2026-11-04

---

## How to read this

Four layers, each using only the one above it:

| Layer | Lives in | Contains |
|---|---|---|
| Tokens | `Design/Theme.swift` | colours, type ramp, spacing, radii |
| Primitives | `Components/` | background, glass surface — no content |
| Components | `Components/` | header, rows, charts, badges, forms (this document) |
| Screens | `Features/` | composition only; no drawing of its own |

- **IDs are stable.** A component that changes shape keeps its ID and gains a variant; nothing is
  ever renumbered. Docs, code and review all cite these IDs.
- **Reuse** counts the screens that show the component. `1` means single use: extract it only if it
  is long or carries state — otherwise leave it inline and revisit.
- **Built** names the implementing file, or `—` when nothing exists yet. A file may be partial; the
  note says how.

Screen abbreviations: **Onb** onboarding · **Live** realtime · **Drv** drives · **DrvD** drive
detail · **Chg** charging · **ChgD** charge detail · **Stats** statistics · **Hist** history ·
**Set** settings.

---

## 1. Chrome

The frame every screen sits in. These four decide whether the app feels like one app.

| ID | Component | What it is | Variants / states | Reuse | Built |
|---|---|---|---|---|---|
| C-01 | `ScreenBackground` | Navy gradient with a cyan / purple aurora for the glass to tint | default; top 120 pt stays neutral | 9 | `ScreenBackground.swift` |
| C-02 | `HeaderBar` | Pinned title + actions; one fixed full-bleed bar over the page | fixed | 8 | `HeaderBar.swift` |
| C-03 | `HeaderAction` | Plain icon button that rides inside the header | enabled / disabled / with label | 5 | `HeaderAction` in `HeaderBar.swift` |
| C-04 | `FilterRow` | Container directly under the header, scrolling away with the content | one control / two controls | 4 | — |
| C-05 | `SegmentedControl` | Plain text only; the selected label turns white and bolder | regular / small | 4 screens, 5 instances | `SegmentedControl.swift` |
| C-06 | `TabBar` | Floating glass capsule, four items, active tab as a glass pill | 4 items fixed | 4 | `TabBar.swift` — 设置 is not a tab; Live's header gear pushes it |
| C-07 | `StickyDayHeader` | "11月1日 周六 · 4.1 km" heading above its day's rows | — | 2 | `StickyDayHeader.swift` |
| C-08 | `MapBottomSheet` | Scrim + glass card floating over a full-bleed map | collapsed / expanded | 1 | — |

### 1.1 C-02 `HeaderBar` — the reference implementation

The one component with real behaviour, so it is specified in full. Everything else in this document
is static layout.

**One fixed state. Nothing moves inside it or around it.**

| | Fixed |
|---|---|
| Inset | full-bleed, aligned to the 16 pt content gutter |
| Radius | 0 |
| Padding | 14 / 16 / 12 |
| Surface | opaque page navy (`#0A0F1A`), full bleed to the status bar; no glass, rim or shadow |
| Height | 54 pt, the same on every screen |

- **It is pinned for the whole scroll**, not carried up with the content. Content passes *behind*
  it and ends at its opaque backdrop, so the title never collides with a row.
- **No capsule, no wrap.** An earlier draft wrapped the bar into an inset glass capsule once the
  page moved; it read as a second floating surface over the list, so the bar keeps one shape.
- **The title block never changes size**, so the bar has one height on every screen. A second glass
  row under it is what made earlier drafts read as stacked bands — the filter row (C-04) is content.
- **Actions are bare icons** (C-03): white 74 %, 36 pt, no circle, no border, no shadow.
- **设置 is a pushed page, not a tab.** Live's header carries a gear as its last action; the page
  opens full-screen with its own 返回 and the floating bar hidden.
- **History** sits over a map with no scroll; the same opaque bar keeps the title readable there.
- **Legibility:** the opaque page black under the title matches the top of `ScreenBackground`, so
  12 pt captions inside keep 4.5 : 1.

> **Implementation note (iOS 17 target).** The bar is an overlay pinned to the top of the scroll
> view, with the content carrying a top inset equal to the bar height. Its background ignores the
> top safe area so the status bar band stays navy too.

---

## 2. Surfaces

Glass comes in exactly two weights. Anything that looks like a third is a bug.

| ID | Component | What it is | Variants / states | Reuse | Built |
|---|---|---|---|---|---|
| C-09 | `GlassCard` | The standard surface: body gradient + specular rim + inner top highlight, radius 24, padding 16 | normal / tinted (state colour in body and rim) | 8 | `GlassCard.swift` |
| C-10 | `ChartCard` | Softer body, tighter padding (14 / 16 / 8), header row of title + summary value | with / without summary | 3 | — |
| C-11 | `SettingsGroup` | Rounded container for a group of rows; rows draw their own separators | — | 1 screen, 4 groups | `SettingsGroup.swift` |
| C-12 | `SettingsRow` | Label, muted value, trailing control or chevron | value / chevron / toggle / destructive | 1 screen, N rows | `SettingsGroup.swift` |
| C-13 | `MapEntryCard` | Thumbnail, title, subtitle, chevron — a card that navigates | — | 1 | inline in `StatsView.swift` (single use, as below) |

- **C-09 vs C-10:** cards carry the outer shadow; cards *inside* cards (charts, tiles, groups) take
  the soft body and the inner highlight only. Stacking two shadows is what makes glass read as
  plastic.
- **Tinting is meaning, not decoration:** green for consumption, orange for warnings, red only for
  destruction — and it enters through the body and rim gradients, never as a flat colour fill.
- **C-13 is single-use today** (Stats → History). Keep it inline until a second screen needs it.

---

## 3. Data display

| ID | Component | What it is | Variants / states | Reuse | Built |
|---|---|---|---|---|---|
| C-14 | `BatteryRing` | 128 pt ring, 12 pt stroke, level colour, bolt while charging, "74%" centred | red ≤ 20 / orange ≤ 40 / green > 40 | 1 | — |
| C-15 | `StatTile` | Icon, caption, value in a soft glass tile | icon optional / unit suffix | 2 | `StatTile.swift` |
| C-16 | `StatStrip` | Three equal columns of number + label, no glass of its own | 2–3 columns | 2 | `StatStrip.swift` |
| C-17 | `InlineRow` | `icon? · label · value`, monospaced digits, one line | neutral / ok (green) / warn (orange) | 3 | partial — `DetailRow.swift` has no icon and no state |
| C-18 | `StateBadge` | Capsule pill with a 6 pt dot and a state colour | 在线 / 休眠 / 离线 / 充电中 / 行驶中 / 更新中 / 已暂停 | 1 | `StateBadge.swift` |
| C-19 | `EnergyBadge` | Tinted badge with a large number and a caption pushed right | ok (green < 18) / warn (orange ≥ 18) | 1 | — |
| C-20 | `SoCBar` | 6 pt track, gradient fill, percentage labels at both ends | single value / start → end | 2 | `SoCBar.swift` |
| C-21 | `FreshnessLine` | "最后更新 12 秒前" / "缓存于 11月1日 21:01" | neutral (asleep) / warning (stale) | 7 | — |
| C-39 | `StatusTimeline` | 24-hour state band: segments weighted by minutes, 0/6/12/18/24 ticks, legend | six states / no axis / fixed 24 h scale (`scaleMinutes`, for "today so far") | 3 (live, legend, parking detail) | `StatusTimeline.swift` |
| C-40 | `ProportionBar` | A stacked share bar with a legend row and one trailing note | 2–3 parts / no legend | 2 (parking, state mix) | `ProportionBar.swift` |
| C-42 | `ScoreRing` | 0–100 ring with the score and unit inside, rating and one line beside | 优秀 / 良好 / 偏低 / 异常 | 2 (battery health, range efficiency) | `ScoreRing.swift` |

- **C-17 is one component, not two.** `MiniRow` (icon + label + value) and `DetailRow` (label +
  value) in earlier drafts differ only by an optional icon; build one with `icon: String? = nil`.
- **C-21 always carries an absolute time**, never "刚刚" alone. It is the only thing standing between
  a cached screen and the user believing it is live (FR-8.1, FR-8.2).

---

## 4. Rows

| ID | Component | What it is | Variants / states | Reuse | Built |
|---|---|---|---|---|---|
| C-22 | `TripRow` | Times · rail · places · distance / duration | normal / first in day / last in day | 1 screen, N rows | `TripRow.swift` |
| C-23 | `ChargeRow` | Icon chip · station and time · kWh and duration · SoC bar | with cost / without cost | 1 screen, N rows | `ChargeRow.swift` |
| C-24 | `ListFooter` | The end of a paged list | loading · end · error + retry | 2 | `ListFooter.swift` |

- **C-22's rail** is 2 pt at 6 % white between two 12 pt dots: green start, orange end, each with a
  3 pt halo at 12 % of its colour. It encodes order, so it survives greyscale.
- **C-23 without a cost reads "费用未记录"**, never `¥0.00` (FR-5.2). If DF-2 lands, the manual
  amount arrives here as a labelled variant of the same row.
- **C-24 never shows a spinner and the end message at the same time**, and the error state carries
  the retry — an empty footer that says nothing is the failure mode to avoid.

---

## 5. Charts

| ID | Component | What it is | Variants / states | Reuse | Built |
|---|---|---|---|---|---|
| C-25 | `LineChart` | Area (32 % → 2 %) plus a 2 pt line, four x labels, 6 % grid | with / without elevation; animated only on range change | 2 | partial — `MetricChart.swift`; the header takes a caller-supplied `summary` (Drives passes 最高 / 最低 / 电量 / 海拔) and a shared `xDomain`; range-change animation is missing |
| C-26 | `BarChart` | Bars with rounded tops, zero-filled gaps, shared x domain | day / month bucket; full / zoomed | 1 screen, 3 charts | `BarChart.swift` — bars at 60 % of their slot, capped at 36 pt so two monthly buckets do not fill the card; a caller-supplied `summary`; `unitWidth` choosing month-stride or automatic ticks. The domain covers whole months and the plot is inset, so neither the edge bars nor the edge date labels are clipped |
| C-41 | `MiniBars` | Six or seven compact bars, no axis and no grid, one short label each | default / one highlighted | 2 (live, regen) | `MiniBars.swift` |
| C-43 | `ComparisonRow` | One group per row: bar, value, delta, and a mean line across every row | best / normal | 1 (energy analysis) | stays inline |
| C-44 | `MonthCalendar` | Seven-column month grid; date, up to two marks and that day's distance | has events / today / empty | 1 (trip calendar) | stays inline |

- Charts **do not re-animate on the 3 s poll** — only when the time range changes. A chart that
  breathes every poll is noise on a screen someone is reading.
- Shared x domain across the charts of one screen while none is zoomed, so vertical reading lines up.
- **The time axis zooms.** Pinch scales the window around its centre (two buckets is the closest
  zoom), a horizontal drag pans it, and a double tap returns to the full period. Each chart keeps
  its own window, so zooming one leaves the others at the full period, and a period or bucket
  switch clears it. Drags that are mostly vertical are ignored so the page still scrolls.

---

## 6. Map

| ID | Component | What it is | Variants / states | Reuse | Built |
|---|---|---|---|---|---|
| C-27 | `MapSurface` | The only place a map is instantiated | in a card (220 / 260 pt) / full-bleed | 3 | `Components/MapSurface.swift` — fitted camera with ≥ 12 % padding, optional follow and recenter token, accessibility label, `interactive: false` for inline previews |
| C-28 | `TrackLayer` | One 3 pt stroke plus start dot and end chevron | track / single position pin | 2 | `TrackLayer` in `MapSurface.swift` — green dot and orange chevron, each labelled |
| C-29 | `MapOverlayPill` | Small glass capsule over the map | status (top-left) / place (bottom-left) / action (bottom-right) | 3 | `MapOverlayPill` — Live and History use the status slot, drive detail the place slot |
| C-30 | `RecenterControl` | C-29 pinned bottom-right, appearing only after a pan | shown / hidden | 1 | `RecenterControl` — the pill with an action, shown once following stops |

- **C-28 differs by shape, not colour:** a filled dot for the start, a chevron for the end, so they
  stay distinguishable in greyscale and for colour-blind users (FR-9.4).
- **The Live map card is a preview**, not a map: it renders with `interactive: false` so the page
  scrolls normally, and tapping it pushes `LiveMapView` — a full-screen map with its own back
  control, pan/zoom, and the C-30 recenter pill.
- The app never requests location and never draws a user dot (FR-9.5); C-27 takes a camera and
  points, and nothing else.

---

## 7. Feedback

| ID | Component | What it is | Variants / states | Reuse | Built |
|---|---|---|---|---|---|
| C-31 | `ErrorBanner` | Orange icon + message on tinted glass | message / message + cached time + retry | 7 | `ErrorBanner.swift`; `AuthBanner` is its 401 variant with a 去设置 action |
| C-32 | `EmptyState` | 36 pt symbol, headline, one sentence | with action (required) | 4 | `EmptyStateView` in `ErrorBanner.swift` — action slot is required |
| C-33 | `Skeleton` | Card-shaped placeholder with a 1.2 s shimmer | one card / a list of cards | 8 | `Components/Skeleton.swift` |

- **C-32 must carry one action** (FR-8.4, UI-DESIGN §5). Every call site now passes one — a retry, a
  period switch or 去设置; the component's action parameter is non-optional.
- **C-31 does not retry by itself.** The banner takes an optional `cachedAt` (rendered as
  "显示 HH:mm 的数据") and an optional retry closure; the view model owns both.

---

## 8. Forms and actions

| ID | Component | What it is | Variants / states | Reuse | Built |
|---|---|---|---|---|---|
| C-34 | `GlassField` | Labelled input well | text / masked / focused / error | 2 | `GlassField.swift` |
| C-35 | `PrimaryButton` | Full-width accent action, 50 pt | enabled / disabled / loading | 2 | `PrimaryButton.swift` |
| C-36 | `DestructiveButton` | Red-tinted action that always asks first | — | 2 | `PrimaryButton.swift` |
| C-37 | `ToggleRow` | Label plus a 45 × 27 glass switch | on / off | 1 | `ToggleRow.swift` |
| C-38 | `HeroGlyph` | 78 pt accent-tinted rounded square holding one icon | — | 1 | `HeroGlyph.swift` |

- **C-36 asks for confirmation at the call site, not inside itself** — the component draws, the
  screen owns the dialog. Same for C-35's loading state: the screen owns the in-flight flag.

---

## 9. Reuse matrix

Filled dot = present. White circle = a variant of the same component.

| Component | Onb | Live | Drv | DrvD | Chg | ChgD | Stats | Hist | Set |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| C-01 `ScreenBackground` | ● | ● | ● | ● | ● | ● | ● | ● | ● |
| C-02 `HeaderBar` | | ● | ● | ● | ● | ● | ● | ● | ● |
| C-03 `HeaderAction` | | ● | ● | ● | | | ● | ● | |
| C-05 `SegmentedControl` | | | ● | | ● | | ● | ● | |
| C-06 `TabBar` | | ● | ● | | ● | | ● | | |
| C-09 `GlassCard` | | ● | ● | ● | ● | ● | ● | ● | ● |
| C-17 `InlineRow` | | ● | | ● | | ● | | | |
| C-20 `SoCBar` | | ● | | | ● | | | | |
| C-21 `FreshnessLine` | | ● | ● | ● | ● | ● | ● | ● | |
| C-25 `LineChart` | | | | ● | | ● | | | |
| C-27 `MapSurface` | | ● | | ● | | | | ● | |
| C-31 `ErrorBanner` | | ● | ● | ● | ● | ● | ● | ● | |
| C-32 `EmptyState` | | | ● | | ● | | ● | ● | |
| C-33 `Skeleton` | | ● | ● | ● | ● | ● | ● | ● | ● |
| C-34 `GlassField` | ● | | | | | | | | ● |
| C-35 `PrimaryButton` | ● | | | | | | | | ● |

Ten components do the heavy lifting; the rest appear once or twice and are allowed to stay small.

---

## 10. Build order

1. **The shell** — C-01, C-09, C-02, C-05. Everything else sits inside these, and C-02 is the only
   component with animation.
2. **Cheap and everywhere** — C-17, C-21, C-31, C-32, C-33.
3. **Numbers and lists** — C-15, C-16, C-14, C-22, C-23, C-24.
4. **Charts and maps** — C-25, C-26, C-27, C-28, C-29, C-30.
5. **Forms** — C-34, C-35, C-36, C-37, C-38.

---

## 11. Rules that keep it reusable

- **A component never fetches.** It takes data, callbacks and nothing else; the view model stays in
  the screen.
- **A component never knows its screen.** No `if screen == .live` anywhere in `Components/`.
- **Copy is passed in** (NFR-9). `StateBadge` currently maps `state` → Chinese label internally;
  that map belongs in a formatter so the view stays language-neutral.
- **One accent.** A component that needs a second accent colour is a design error, not a parameter.
- **Colour means state.** Cyan selects, green is healthy, orange warns, red is destruction. A colour
  chosen because the screen is that screen is the beginning of a theme nobody can change.
- **Extract at the second use**, or when the piece is ≥ ~40 lines or carries its own animation.
  C-13 and C-14 are single-use today; C-14 earns its file by being stateful, C-13 does not.
- **A component with eight parameters is three components.** Variants are capped at three; a fourth
  means the abstraction is wrong.

---

## 12. Gaps between the spec and the code

Recorded so the gap does not survive the next screen built on top of it.

The shell pass resolved the first two: `Theme.swift` now carries the design tokens, and
`GlassCard.swift` replaces the flat `card()` with `GlassStyle`, so padding and radius are a style
rather than a hardcoded modifier.

The Drives pass resolved the next two: `EmptyStateView` now takes an optional `actionTitle` and
action, and `MetricChart` takes a caller-supplied `summary` instead of always printing the last
value, so §4.4's 最高 / 最低 are expressible.

The FR-8 pass resolved the last one: `Skeleton` now exists in `Components/Skeleton.swift`, so a first
load shows card placeholders instead of a full-screen spinner, and `ErrorBanner` carries an optional
cached timestamp and retry supplied by the view model.

The FR-9 pass removed the duplicated map plumbing: `MapSurface` owns the camera fit and the only
`Map`, `TrackLayer` owns the stroke and markers, and the coordinate conversion moved to
`GeoPoint.mapCoordinate`, so `DriveDetailView`, `HistoryView` and `LiveView` no longer repeat it.

1. **`StateBadge` owns Chinese copy**; move the label map to a formatter (NFR-9).

The 2026-11-04 gap screens landed the Live today board (`Features/Live/TodayBoard.swift` with
`TodayViewModel`, including the 6-month `MiniBars` card and the state legend sheet), the richer
`TripRow` meta line, the trip calendar (`Features/Drives/TripCalendarView.swift`, C-44 inline) and
the track filter sheet (`Features/History/HistoryFilterSheet.swift`). `StatusTimeline` gained a
`scaleMinutes` variant so a day in progress fills only the hours that have happened.

The same pass added four components: `StatusTimeline` (C-39), `ProportionBar` (C-40),
`MiniBars` (C-41) and `ScoreRing` (C-42). All four colour themselves from Theme tokens, carry an
accessibility summary, and fetch nothing. `ComparisonRow` (C-43) and `MonthCalendar` (C-44) stay
inline under the "extract on the second use" rule — each serves one screen, and extracting them
would only add a parameter layer.

The 2026-11-05 pass added the four derived screens under `Features/Insights/`: 能耗分析, 动能回收,
停车记录 / 停车详情 and 电池报告. It put C-40 and C-42 to work for the first time (parking's state
split, the battery score) and reused C-41 for the week's regen peaks. Two things stayed inline: the
mean-line comparison row in `EnergyView` (one screen, and C-43's rule is to extract on the second
use) and `ParkingStateLegend`, which is shared by the parking list and its detail rather than by
type. One shared change came out of it: `TabBarChrome` now counts hide requests instead of setting
a flag, because pushing a full-height detail marks its parent as disappeared and a plain `= false`
would bring the bar back over the detail.

---

## 13. References

- [`UI-DESIGN.md`](UI-DESIGN.md) — tokens, screens, states, accessibility
- [`mockups/index.html`](mockups/index.html) — the visual source for every number above
- [`mockups/components.html`](mockups/components.html) — every component, rendered with all of its
  variants and a composed screen at the end
- [`STATUS.md`](STATUS.md) — which screens are actually built
