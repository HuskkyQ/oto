# Odo 欧豆 — Name and Mark

Status: naming decided, mark still open · 2026-11-02 · Owner: Steven

Working note for the app's identity. Product requirements live in [`PRD.md`](PRD.md); visual
language in [`UI-DESIGN.md`](UI-DESIGN.md). This file only covers what the app is *called* and what
it *looks like as an icon*.

---

## 1. The name

| | |
|---|---|
| English | **Odo** |
| Chinese | **欧豆** |
| Colloquial | 小豆, 豆子 |
| Bundle id | `com.sevan.TeslaMateViewer` → `com.sevan.odo` (not yet changed) |

**Why this and not a descriptive noun.** People get attached to a creature, not a concept.
"Odograph" is a beautiful word — it is the real name of an instrument that records distance — and
completely forgettable. "Odo" is three letters, one syllable, sayable in Chinese, and it can hold
a face. The choice is: character names are stickier but date faster; instrument names age better
and get forgotten. We chose sticky.

**Why 欧豆 specifically.** It is phonetically almost exactly "Odo", and 豆 gives the mascot a shape
for free. It also reads as a name rather than a label, so empty states and errors can speak in it.

### Voice

The name buys a tone. Use it in copy, not just on the icon:

- Empty state: 「小豆还没醒」 (not 「暂无数据」)
- Loading: 「小豆正在数里程」
- Stale: 「小豆联系不上车了」
- Never: exclamation marks, emoji, or baby-talk beyond this.

### Names considered and rejected

| Name | Type | Why not |
|---|---|---|
| Odograph | instrument | exact meaning, zero recall; nobody says it out loud |
| Tessera | coinage (mosaic tile) | a Tesla nod without the mark — but derivative, and two companies already hold it |
| Tally | verb | friendly, generic, heavily used |
| Coulomb | unit | precise but narrow — says *charging*, not *drives* |
| 奥多 | transliteration | reads like a person's name; flat next to 欧豆 |
| 车志 | semantic (car chronicle) | the best adult option — accurate, puns on 日志 — but cold, no character |
| 表弟 | pun (meter + little brother) | funniest of the set, unusable as a shipping name; keep as an easter egg |

**Trademark note:** "Tesla" in the name is rejected by App Store review under guideline 5.2.1
(third-party trademark). Fine for TestFlight or a personal build, unusable in the store. Every name
above clears that. The shipping name is Odo / 欧豆, not "TeslaMate Viewer".

---

## 2. The mark

Four rounds so far. Rounds 1–3 are rejected; round 4 (lightning bolt) is the current direction and
is **not settled**.

### Round 1 — glass bean face (rejected)

Gradient body, specular rim, catchlights, smile, battery ring. Five ideas fighting inside a 60 px
square. At that size nobody reads any of them. Rejected: decoration was hiding the character.

### Round 2 — flat ball (rejected)

Round body, two white eyes, black ground, no mouth — the Grok Bot language. Correct restraint, but
it landed on the "AI little ball" shape that Grok Bot, Kimi and a dozen others already own, and it
is a character mark in an app whose subject is data.

### Round 3 — red ball with poses (rejected)

Same ball in Tesla red, with leaning / peeking / bouncing poses and eye-only expression states
(醒着 / 开心 / 休眠 / 充电中 / 注意). The poses worked; the character did not survive the brief —
an EV information display reads better as an instrument than as a mascot.

### Round 4 — lightning bolt (current)

A stock bolt is the most-used symbol in electric everything, so the work is not drawing a bolt; it
is deciding what the bolt is made of and what it sits on. Four treatments were drawn:

| | Treatment | Verdict |
|---|---|---|
| A | white bolt on a full red tile | loudest, unbreakable at 29 px — and the most generic; this is the default charging-app icon |
| **B** | **red bolt on a black tile** | **recommended.** Same bolt inverted; sits inside the app's own dark palette. Rarer on a home screen and keeps red as the signal colour, not the background |
| C | bolt drawn as a navigation line, start and end dots | **failed.** Thickened with mitre joins it reads as a bent red bar with two dots, not lightning. Concept was right, execution is not — do not ship |
| D | leaning bolt with a fading dot trail | still moving, and the dots survive at 60 px but vanish at 29. A detail, not a differentiator |

**Open:** round 4 has not been chosen. B is the recommendation, A is the fallback if more punch on
the home screen matters more than distinctiveness.

---

## 3. Colour

| Token | Value | Use |
|---|---|---|
| Tesla red | `#E82127` | the mark, charging states, destructive-ish emphasis |
| Safer red | `#D6232A` | swap in if the trademark collision becomes a concern |
| App accent | `#5CC7FF` | unchanged — the UI's own accent, from UI-DESIGN §1 |

`#E82127` is consistent across every third-party source, but **no Tesla brand guideline confirms
it**; the Pantone values circulating (485 C, 1788 C, 185 C) are all derived from the hex. It is a
live trademark signal of a company this app does not belong to — acceptable for a personal build,
a knowing risk if it ever ships.

---

## 4. Open items

- [ ] Pick a mark (round 4: A or B — or a new direction)
- [ ] Cut the 1024 px asset and the `AppIcon` entries in the Xcode asset catalog
- [ ] Rename `project.yml`: `name`, `PRODUCT_NAME`, `PRODUCT_BUNDLE_IDENTIFIER`, display name
- [ ] Display name is currently `TeslaMate` — it claims to *be* the upstream project
- [ ] Localised display name: `INFOPLIST_KEY_CFBundleDisplayName` takes one string, so 欧豆 on a
      Chinese phone and Odo on an English one needs `zh-Hans.lproj/InfoPlist.strings`
- [ ] Wordmark: "odo 欧豆" in the current mockup is the system font, not a designed lockup

## 5. Assets

- [`mockups/logo.html`](mockups/logo.html) — the live exploration page (round 4)
- [`mockups/logo-sheet.png`](mockups/logo-sheet.png) — rendered sheet, 1024 / 180 / 60 / 29 px

---

## 中文摘要

- **名字**：Odo / 欧豆，口语「小豆」。选角色名不选仪器名——好记优先于耐看。
- **语气**：名字要进文案，不只是进图标。「小豆还没醒」而不是「暂无数据」。
- **图标**：探索了四轮。前三轮（玻璃豆脸、扁平小球、红色小球表情）均已否决；第四轮是闪电，
  其中 **B（黑底红闪电）推荐**，C（路线闪电）已判定失败，不再候选。
- **颜色**：`#E82127` 是第三方一致的"特斯拉红"，但没有官方规范确认；介意商标可用 `#D6232A`。
- **待办**：图标尚未定稿，资源目录、工程改名、中英文显示名都还没动。
