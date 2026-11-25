# Sprint 32 — the widgets make room, Wealth's tabs ship as dashboards, the periods are the operator's

**Status: ADOPTED by the merge of the Sprint 32 planning PR.**
The merge is the signature (ADR-0026 step 1, as amended on 2026-10-08). It
signs [ADR-0062's amendment of
2026-11-25](../../docs/decisions/0062-widgets-and-composed-dashboards.md)
(ideas I57 to I59 and I61, the owner's review of Sprint 31's first slice),
the decisions below, and the planning boards 01 to 10 in
`design-language/mockups/ux-design-2026-11-25-sprint32/`. No change moves a
stored figure: every widget draws a read that exists today, and a layout,
a saved period and a seed record hold no money data. A fresh implementation
session builds the sprint on the branch its environment assigns, or
`agent/<provider>/sprint-32`, as **two stacked PRs** (D-9). The severity
rule of ADR-0026's amendment of 2026-11-01 applies unchanged.

## What you need to do

1. **Merge, to adopt the plan.** It answers your message of 2026-11-25
   point by point:
   - **„dann sollen die sich einfach alle verschieben“** (I58, D-4, board
     01): a resize or a move always succeeds; what is in the way moves
     down, then everything floats up until no gap is left, and the message
     stands at the widget you clicked, with „Rückgängig“.
   - **„Gesamtwert auf M ist total unübersichtlich“** (D-4, board 01 ④):
     each size shows more of the same, never something else. Gesamtwert M
     becomes the figure and its course; a new W carries three key figures.
   - **„jedes ein eigenes Dashboard, das zum Start mitkommt“** (I57, D-6,
     D-7, board 02): Wealth's tabs become starter dashboards that look like
     the tabs, each section a widget in the new size „Zeile“. This sprint:
     Bestände, Allokation & Ziele, Snapshots, Risiko; Cashflow, Steuer and
     Prognosen in the next widget pass (D-8).
   - **„Vorlagen zur Auswahl“** (I61, D-6, board 03): „Neues Dashboard“
     opens a gallery with the starters and the themes „Krypto Lover“ and
     „Rücksetzer“.
   - **„Das Kennzahlen-Widget sieht nicht übersichtlich aus“** (board
     06): you picked **A** („Ja, A sieht super aus“): the total with its
     split into securities and cash, three return figures on one line
     (Ergebnis, TTWROR, IRR), the value bridge Anfang + Nettoflüsse +
     Ergebnis = heute below, one ⓘ for the widget (D-12).
   - **„den Look von allen Widgets prüfen“** (board 07): all eleven kinds
     in all 21 sizes photographed and checked; ten findings and one
     widget anatomy derived from A, built as Lane L before the Wealth
     widgets, so they are born in it (D-12).
   - **„Verfolgen wir Apples Empfehlungen für die Sizes?“** (boards 08,
     09): today only half, and that is what makes dashboards look
     chaotic: rows grow with their content, and L and T are no multiple of
     S. The sizes become Apple's families S, M, L, XL with fixed heights;
     every widget in every size, light and dark, is on board 08, and the
     templates with widgets on them, today and on Apple's tiles, on board
     09 (D-13).
   - **„Mir gefällt der Widget-Abstand nicht“** (board 10): you picked
     **D „Eine Fläche“** for the web app („Ich will da nicht so viel Platz
     verschwenden“): a dashboard is one surface, its widgets separated by
     hairlines instead of gaps; separate cards stay for native widgets
     later (D-14).
   - **Zeiträume** (I59, D-5, board 04): a quick choice of up to six that
     you pick with ★, one button with the menu (rolling, calendar with
     MTD, quarters Q1 to Q4 and the rest, years, your own), your own
     periods stored on the server and usable on the whole dashboard or
     pinned to one chart.
2. **One question only you can answer: may a shipped template be called
   „Buy The Dip“?** The name tells the operator to buy, and „no advice“ is
   one of Portfolixir's permanent non-goals (`AGENTS.md`). Recommended:
   ship it as **„Rücksetzer“** with the same widgets; your own copy can be
   renamed to anything. Silence adopts „Rücksetzer“; „Buy The Dip heißt Buy
   The Dip“ flips it.
3. **One ordering you may want to flip: widgets now, the audit's money
   figures next.** The architecture triage of 2026-11-24 proposes its step
   1 (ten S1 figure fixes in the domain, about nine agent-days) as the next
   work; you asked for the widgets today. Recommended: this sprint is the
   widget pass you asked for, Sprint 33 the audit's step 1, the rest of the
   widget pass after it (D-2). „Audit zuerst“ swaps Sprints 32 and 33.

**Not asked:** everything else. Each decision below names its flip phrase.
**Not raised:** the compact type on a real phone (Sprint 31's
carry-forward 1, still yours when a phone is at hand), I48 (no longer a
precondition, D-8), #1484 and #1485 (the audit's step 2 carries them).

**Verification basis:**

- **`main` on 2026-11-25** is at `07ff2c1`. Sprint 31's stacked PR #1486
  merged on 2026-11-23; since then the audit's lens 1 and lens 2 fixes
  merged in #1488 (release 2026.11.24) and #1489 (release 2026.11.25), and
  `db_connection` 2.10.3 for EEF-CVE-2026-133555 (`e2528d5`).
- **The open-issue list of 2026-11-25:** 87 open, among them twelve S1 from
  the 2026-11 audit (#1490 to #1492, #1508 to #1516), the two S1 candidates
  #1484 and #1485 (`needs-decision`, the same title twice), #1481 and
  #1482 (ADR-0062's deferred asks; #1482 is answered by the amendment,
  D-11), eight audit trackers (#1534 to #1541) and the polish lists. One
  Dependabot PR is open: #1477 (Playwright 1.65.1 in `test/browser`).
- **Read against the code on `07ff2c1`**, each claim this plan rests on:
  - `Portfolixir.Dashboards.Edit.resize/3` refuses a size that overlaps
    („can't take size …: it would overlap …“), and the refusal is drawn
    in the page's top flash. Hence Lane E.
  - The registry (`lib/portfolixir/dashboards/widgets.ex`) holds eleven
    kinds; `total_value` takes S and M, and its M is drawn in
    `dashboard_live.ex` (about line 1815) as the total, the change and a
    strip of four cells (TTWROR with IRR, cash quote, last booking, newest
    quote). Hence E4.
  - `Portfolixir.Dashboards.Templates` holds „Überblick“ only; the
    `dashboards` table has `name`, `position`, `layout`, `lock_version`
    and no scope. Hence S1 and S3.
  - `PortfolixirWeb.Api.V1.PeriodParam.resolve/1` already takes `period`,
    `year` and `from`/`to`, and `Performance.summarise/2` any
    `{:range, from, to}`; eight routes read it (performance, benchmark,
    bands, contribution, each also per view). The dashboard's own list is
    `1d 1w 1m 3m ytd 1y 3y max` and has no `5y`. Hence Lane T and its
    surface check.
  - The Wealth tabs (`AppShell.wealth_tabs/1`) and their sections, read
    top to bottom on 2026-11-25: Holdings six (key figures, data notes,
    performance with its contribution table, positions, cash accounts),
    Allocation two (the summary line, the allocation tree or positions
    with its drift table), Snapshots two (the comparison, the list with
    its form), Risk six (own rules, portfolio metrics, crashes, largest
    single names, concentration, asset-class caps), Cash flow four facets
    with about ten sections, Tax two, Predictions two. Only five of them
    have a widget that comes close. Hence Lane W and D-8.
  - No read returns returns per calendar month or sums trades per period
    (`portfolio_live.ex`'s private `table_summary/1` slices the walk for
    the table only). Hence I60 waits for its decision (D-8).
- **Boards:** planning boards 01 to 05, drawn on 2026-11-25 on the shipped
  `app.css`, every name and figure invented; boards 06 and 07 from the
  running app on the synthetic review seed, rearranged in the browser
  (06) and photographed kind by kind (07); board 08 every kind in every
  size, light and dark; board 09 three dashboards today and on Apple's
  tiles, simulated in the browser; the scripts in the board's `real-app/`
  folder.

## State of play, in five lines

1. **Sprint 31 is on `main`**: the first dashboard, the widget catalogue,
   one period above it, the edit mode, the menu of dashboards.
2. **You reviewed it on 2026-11-25** and asked for five changes (above).
3. **The 2026-11 audit's two lenses are triaged**; its held rows are fixed
   (#1488, #1489), its S1 and S2 filed, its steps proposed.
4. **Wealth is still a page of seven tabs**, and most of its sections have
   no widget yet.
5. **The dashboard periods are eight fixed chips**; Wealth's custom range
   exists only on Wealth.

## Why this cut

- **The edit mode first**, because it is what made the first slice
  unusable to you, and every later pass relies on it.
- **The periods**, because every starter dashboard reads them, and Wealth's
  custom range must not be lost when its sections become widgets.
- **The starters, the gallery and the size „Zeile“**, because they are how
  a tab becomes a dashboard that looks like the tab.
- **Four tabs, not seven**: Bestände, Allokation & Ziele, Snapshots and
  Risiko have 16 sections; Cashflow alone has four facets and about ten
  sections, among them the 991-line „Nach dem Verkauf“ component. All
  seven would pass 200 commits with the closing act. „alle sieben in
  Sprint 32“ flips it, at a third stacked PR.
- **What is left out, and why** (each flips by naming it): Cashflow,
  Steuer and Prognosen, the heatmap and the trading activity (the next
  widget pass, D-8); the audit's figure fixes on Wealth's sections (its step 3, D-7);
  the Datenqualität hint for legacy closes of 0 (with the Datenqualität
  kinds' merge, D-8); I48; the other polish lists; #1396, #899, #900,
  #1070, #1220, #1177, #328, #354 and #1451 to #1456 keep their standing
  reasons.

## Lanes (two stacked PRs: M, E, T, S, then L and W)

**Lane M, maintenance (first).**

| Story | Source | What it does | Commits |
|---|---|---|---|
| M1 | standing rule; #1477 | the version report `version-report-2026-11-…-sprint32.md`: Hex, npm (Playwright 1.65.1 in `test/browser`, #1477), Elixir/OTP, PostgreSQL, BMAD core and the external modules; each bump its own commit, what is declined with its reason | 1–3 |

**Lane E, the others make room** (I58; ADR-0062 amendment 1 to 3; board 01).

| Story | Source | What it does | Board | Commits |
|---|---|---|---|---|
| E1 | amendment 1 | **the arrangement as a pure function in the context**: `Portfolixir.Dashboards.Arrange` (or the name the conventions give) takes a validated layout and one action (resize, move, add) and returns the arranged layout: the acted-on item keeps its place, what it covers moves down in reading order, then every item floats up; the result always validates. Tests first: board 01 ②'s case to the cell, a chain of three pushed items, a „Zeile“ item in the way, the 40-item and row-200 refusals; a property test over generated layouts (no overlap, no item above where it could float, the acted-on item unmoved) | 01 ② | 2 |
| E2 | amendment 1 | **the edit mode uses it**: resize, move (pointer and arrow keys) and add arrange instead of refusing; the moved widgets are marked until the next action; the feedback stands at the acted-on widget, announced (`aria-live`), with „Rückgängig“ for that step and Ctrl+Z; „Zurücksetzen“ as before; the top flash carries no edit message any more. Browser test: board 01 ①'s click at the page's foot shows its feedback in the viewport | 01 ①, ③ | 2–3 |
| E3 | amendment 2 | **`arrange: "push"` on `PUT /api/v1/dashboards/:id`** with the changed item's index, applied before validation; without it an overlap is still 422; the MCP `portfolixir.dashboards.put` takes the same flag; contract entry and docs (English and German) | — | 1 |
| E4 | amendment 3, Apple's families and „each size shows more of the same“ | **the sizes become S, M, L, XL with fixed heights** (board 09): the registry's dimensions (S 3 × 2, M 6 × 2, L 6 × 4, XL 12 × 4, plus „Zeile“ from S2), a fixed 7 rem row at the wide class, the compact class with two S side by side; stored layouts read with S → S, W → M, M → L, T → L, L → XL and the rows doubled, arranged by E1 on the next save (a test reads Sprint 31's stored „Überblick“ and finds no overlap and no item lost); the API and MCP catalogue name the families; `total_value` takes S, M and L as board 01 ④ draws them (its W, M); every kind's sizes read against the rule, a size that adds nothing removed; `DESIGN.md` gains the families and the rule | 01 ④; 09 ① | 3–4 |

**Lane L, one look for every widget** (I62; boards 07 to 09; D-12, D-13;
the head of the second PR). The anatomy of board 07 ② on the eleven
registered kinds, each with its own layout per family (a fixed tile shows
what fits), before Lane W builds the Wealth widgets in it. Each story is test-first: a functional test per
finding it fixes, seen failing for that finding's reason; the figures each
widget draws stay equal to its route's (the existing per-kind tests).

| Story | Source | What it does | Board | Commits |
|---|---|---|---|---|
| L1 | board 07 ②; board 10 B | **the anatomy as shared components**: the surface by board 10 D (the dashboard one surface with one frame of radius 16 px; its widgets separated by 1 px hairlines in `--color-border`, no gap, no card border, no shadow; 16 × 18 px inside; the same in the medium class, and in the compact class one surface with a hairline between the compact forms), as tokens in `app.css`; the edit mode's dashed outline and handles sit inside each cell; the widget head on one line (title, ⓘ, the period mark „1J“ or „📌 …“, the widget's switch, ⋯), the headline figure (label over figure; S 28, W and M 34, secondary 24 px; colour only for plus and minus), the list row (name, figure, a second muted line; numbers never cut), the bar under a row of comparable figures (the contribution table's: centre 0, the largest listed fills 45 %, kept in the compact forms, where `.drift-bar` hides it under 560 px today), the warning line, the one-line footer (scope left, one link named for its target); `DESIGN.md` gains the anatomy and its measures; a browser walk fails a widget whose head wraps, whose figure is clipped or which carries a warning box | 07 ② | 2–3 |
| L2 | board 07 ① 1–5, 7–10 | **the eleven kinds on the anatomy**: findings 1 to 5 and 7 to 10 fixed kind by kind (Gesamtwert, Datenqualität, Fällig, Abseits des Ziels, Wertentwicklung, Tops und Flops with its bars in both views and both columns, as the old Overview card drew them, Snapshots, Allokation und Drift with „≈ zum Soll“ as a column, Crashes, Bitcoin-Zyklus, Verkaufsrückblick); the basis sentences move behind ⓘ (I1's rule), the warning boxes become footer lines, the Overview's template keeps its layout | 07 ③ | 3–4 |
| L3 | board 07 ① 6; board 09 | **each kind fills its tiles**: Tops und Flops S a list of four that fits its tile; Bitcoin-Zyklus XL draws the existing cycle chart; Crashes keeps L only; Allokation und Drift takes L; the templates „Überblick“, „Krypto Lover“ and „Rücksetzer“ set on the families and photographed against board 09 before the story closes | 07 ③; 09 ②, ③ | 2–3 |
| L4 | D-13; the owner, 2026-11-25 („das brauchen wir auch für die Doku“) | **the widget gallery for the docs**: a script in the repository (beside the browser walks) that stores a throwaway dashboard of every kind in every family on the review seed and photographs each, light and dark, at 2×, into `docs/assets/widgets/<kind>-<size>-<theme>.png`; run once at the close-out, after Lane L, and again by any later story that changes a widget; the docs' widget catalogue page (English and German) shows each kind with its sizes, what it draws and its source route | 08 | 2 |

**Lane T, the periods** (I59; amendment 6; board 04).

| Story | Source | What it does | Board | Commits |
|---|---|---|---|---|
| T1 | amendment 6, the vocabulary | **`Portfolixir.Periods`**: every key of the amendment resolved against `Clock.today()` into a term the reads take; a quarter not yet begun refused; tests per key on fixed dates (month and quarter ends, 29 February, 1 January, the first day of a quarter); **every route that takes `PeriodParam` accepts the keys** (the close-out's surface check names all eight and the movers' own window rule); the dashboard's list becomes the vocabulary, with `6m` and `5y` added; the translation rules of tops and flops extended as the amendment states | — | 2 |
| T2 | amendment 6, saved periods | **stored periods**: table and migration (name, `from`, `to` or until today, `lock_version`), at most 50, every refusal a test seen red first (an empty or 41-character name, a control character, `from` after `to`, the 51st), journaled per write; `GET/POST/PUT/DELETE /api/v1/periods`; MCP: the list rides on `portfolixir.dashboards.list`, writes on one `portfolixir.periods.put` (create, replace, delete) within the schema budget; `saved:<id>` accepted where the vocabulary is; docs | — | 3 |
| T3 | amendment 6, the quick choice | **the quick choice stored**: up to six keys, default `1w mtd ytd 1y max`, read and written over `GET/PUT /api/v1/periods/quick` and the same MCP tool; a key that names a deleted period drops from it, said once in the menu | — | 1 |
| T4 | board 04 ①, ② | **the top bar and its menu**: the quick choice as chips, one button with the active period's name (and its dates beside it when it is an own period), the menu in four groups with ★ to add or remove a quick choice, „Eigenen Zeitraum anlegen …“ with its dialog; keyboard path and screen-reader names; the compact class shows the quick choice as its strip and the menu as a sheet | 04 ①, ② | 2–3 |
| T5 | amendment 6, pins | **a pin by reference**: the ⋯ menu's „Zeitraum festpinnen“ opens the same menu; a pin on an own period stores `saved:<id>`; a deleted period leaves the pin dangling, read as the top bar's period with „eigener Zeitraum gelöscht · folgt …“ in the footer, dropped on the next save (as a stale view is); per kind a test that its figures equal its route's for a calendar key and for a saved period | 04 ③ | 2 |

**Lane S, starters, the gallery and the size „Zeile“** (I57, I61;
amendment 3 to 5; boards 02, 03).

| Story | Source | What it does | Board | Commits |
|---|---|---|---|---|
| S1 | amendment 4 | **a dashboard's own scope and its origin**: `view_id` and `template_key` on `dashboards` (migration), the scope read before the address's and the default view, overridden by an item's; a deleted view read as the default and said in the top bar; API, MCP and docs | 03 ② | 2 |
| S2 | amendment 3 | **the size „Zeile“** (`row`): registered for the kinds that take it, 12 × 1 in validation and in E1's arrangement, drawn at its content's height (the grid split into bands at each „Zeile“ item, the rows after it starting below); compact and medium classes draw the section's own narrow layout; a browser test measures that a „Zeile“ widget is as tall as its content at 1200 px and at 393 pt | 02 ①, ③ | 2 |
| S3 | amendment 5 | **starters stored once**: a seed table by template key; a boot task under `Actor.system_job/1` stores each starter of the release not yet seeded, journaled, and records it; an instance that stores any dashboard counts „Überblick“ as seeded; a deleted starter is never stored again (a test deletes one and restarts the task); a read still never writes (Sprint 31's test kept) | 02 | 2 |
| S4 | amendment 5; board 03 | **the gallery**: „Neues Dashboard“ opens it (Leer, the starters, the themes; each card its grid in miniature, its widget count and names), a template whose kinds are not all built is not shown; the dialog with the name (a taken name suggests „… (2)“) and, for a template that names one, the scope; „Anlegen“ stores one copy and opens it; API: `POST /api/v1/dashboards` with `template` and `view_id`, as the MCP `put` | 03 ①, ② | 2–3 |
| S5 | I61; board 03, board 05's last paragraph | **the themes**: the kind „Abstand zum Hoch“ (the securities of the scope with their distance to the 52-week high and their largest drawdown, sorted by distance, from `securities.metrics`, ADR-0047; its basis that read's; M and L; its compact form; no verdict word, `metrics_carry_no_verdict_test.exs` walks it); the templates „Krypto Lover“ (Bitcoin-Zyklus L, Wertentwicklung, Tops und Flops, Abstand zum Hoch, Crashes; asks for a scope) and „Rücksetzer“ (Abstand zum Hoch, Crashes im Vergleich, Tops und Flops pinned to 1W, Wertentwicklung), the second named as your answer to „What you need to do“ 2 | 03 ①; 05 | 2–3 |

**Lane W, Wealth's tabs as starter dashboards** (I57; amendment 3, 5 and
7; board 02; the second stacked PR). Every section widget draws the section
as the tab draws it today, **from the same read, with its code moved, not
rewritten**: a test per widget compares its figures with its route's, and
a browser test compares each starter's rendered sections, in order, with
the tab's on the review seed. Each widget gets its ⓘ (the source's basis),
its compact form (the section's narrow layout) and its catalogue entry.

| Story | Source | What it does | Board | Commits |
|---|---|---|---|---|
| W1 | board 02 ①, ②; board 06 ① A | **Bestände**: the kinds Kennzahlen (Zeile, drawn as board 06's variant A: the total with its securities-to-cash bar, Ergebnis, TTWROR and IRR on one line, the value bridge Anfang + Nettoflüsse + Ergebnis = heute with the multiplier, which must add up to the cent from the reads' own figures, pinned by a test; also S and M as amendment 3 allows), Datenhinweise (Zeile, drawn only when a note exists), Performance (Zeile: the % or value toggle, the level, the benchmark picker and „Daten als Tabelle“; its period the top bar's, Wealth's custom range now an own period), Beitrag je Position (Zeile, L, XL), Positionen (Zeile, with its column picker), Verrechnungskonten (Zeile, S); the starter „Bestände“ | 02 ① | 7–8 |
| W2 | board 02 ② | **Allokation & Ziele**: Kennzahlen-Zeile (the summary line), Allokation (Zeile: tree or positions, the sunburst, the drift table, the display-only hints of ADR-0023, the classification choice); the starter | 02 ② | 3–4 |
| W3 | board 02 ②; amendment 7 | **Snapshots**: Vergleich gegen einen Snapshot (Zeile), Snapshot-Liste (Zeile, with „Neuer Snapshot →“ linking to the page that keeps the form); the starter | 02 ② | 3 |
| W4 | board 02 ② | **Risiko**: Eigene Regeln (Zeile; the rule dialog stays on the page, linked), Kennzahlen des Portfolios (Zeile, M), Crashes (Zeile: today's full section; the existing „Crashes im Vergleich“ stays as its compact relative), Größte Einzelpositionen, Klumpenrisiko (S), Anlageklassen-Obergrenzen; the starter | 02 ② | 6–7 |
| W5 | amendment 5, 7; ADR-0022 amendment | **the menu and the polish**: the four starters in the menu after „Überblick“; Wealth's tab bar links each passed tab to its dashboard, the page stays under „Entdecken“ for the three not passed; **Wealth's polish list (#1366) fixed in the widgets that carry its lines**, one functional test per line seen failing first, each line ticked; `DESIGN.md` (the size „Zeile“, the section widget), `EXPERIENCE.md` (the edit mode's arrangement, the period menu); the docs' navigation and screenshots (English and German) | 02 | 3 |

## Decisions

### D-1: what this sprint is for, and its exit criteria (recommended)

1. **A resize or a move never asks you to delete anything**: E1's property
   holds, the feedback stands at the widget, „Rückgängig“ undoes one step;
   the API refuses an overlap unless asked to arrange.
2. **Every size of every kind is one of Apple's families with a fixed
   height, and passes the size rule and board 07's anatomy**, Gesamtwert as board 01 ④ draws it, the Kennzahlen as board
   06's A; the browser walk finds no wrapped head, clipped figure or
   warning box in any widget.
3. **Bestände, Allokation & Ziele, Snapshots and Risiko look like their
   tabs**: the same sections in the same order, each a widget whose
   figures equal its route's; each starter is stored once and then yours.
4. **The gallery offers only what exists**, and a theme asks for its scope.
5. **Every period key resolves the same on every route**, own periods and
   the quick choice are stored, journaled and reachable over the API and
   MCP, a pin follows its own period's change.
6. **Every gate by registration; regressions counted, none an S1 at
   promotion**; the UAT persona walks the five boards' frames on the review
   seed at the widths of Sprint 31's walk.

### D-2: the widget pass now, the audit's step 1 next (your decision, with the plan's recommendation)

You asked for the widgets on 2026-11-25; the architecture triage of
2026-11-24 proposes its step 1 (one owner per figure in the domain: R-001,
R-002, R-004, R-007, R-008, R-035, AD-1 and AD-2) as the next work. The two
touch different layers: step 1 the contexts and the walk, this sprint the
web layer and the dashboard context. *Why widgets first:* it is your ask,
and it moves Wealth's sections into widget modules without touching a
figure, which also does part of the triage's step 5 (the Wealth page's
split, R-063) before step 3 fixes the page figures in their new place.
*Why one might flip it:* the ten S1 figures are wrong today, on both users'
reads. **To flip:** „Audit zuerst“ (Sprint 32 becomes the audit's step 1
under its own planning PR; this plan moves to Sprint 33 unchanged).

### D-3: the order of the work (recommended)

M first; then E (E1 before E2 and E3, E4 after E2), T (T1 before the rest,
T2 before T3 and T5, T4 after T2 and T3) and S (S1 and S2 before S3, S4,
S5) beside each other, at most two story agents running tests at once
(Sprint 30's carry-forward 3); the first PR's closing act; then on the second PR L (L1 before L2
and L3, L4 after them), then W, W1 to W4 in parallel pairs once L1 is on
its base, W5 last; the second PR's closing act and the close-out. Every story agent
names the test files it ran, and the orchestrator re-runs them at
integration and reads every gate's exit directly (Sprint 31's
carry-forward 7). No gate ships with a baseline or exemption
(carry-forward 8). A closing-act fix that changes the screen gets its frame
first (carry-forward 9).

### D-4: the others make room (I58; board 01 A; recommended)

Board 01 A: push down, then close the gaps; the feedback at the widget; the
API strict unless asked; each size more of the same. *Why not B (gaps
stay):* every change would leave you tidying holes. *Why not keep the
refusal:* it asks you to delete what you meant to keep. **To flip:**
„Lücken stehen lassen“, „Überlappung verweigern“, „API ordnet immer“.

### D-5: the periods (I59; board 04 A; recommended)

Board 04 A: the quick choice, one menu, own periods and the quick choice on
the server, the active period per browser and in the address. *Why not B
(every key a chip):* nineteen chips, before your own, is the overload you
wanted to avoid. *Why the active period stays per browser:* a phone and a
desk may look at different windows at the same time; what you built (the
own periods, the quick choice) follows you. This answers #1482 (D-11).
**To flip:** „alle Tasten zeigen“, „aktiver Zeitraum auf dem Server“.

### D-6: starters, the gallery and the themes (I57, I61; boards 02 A, 03; recommended)

Starters stored once on the update and yours from then on; the gallery with
„Leer“, the starters and the themes; a dashboard's own scope for a theme
that needs one. *Why not board 02 B (shown until changed):* deleting a
starter would need a second memory for „deleted“, and an agent's list
would mix stored and unstored dashboards. **To flip:** „Start-Dashboards
erst beim Ändern speichern“; the theme's name by your answer to „What you
need to do“ 2.

### D-7: a section widget moves code, not figures (recommended)

W moves each section's rendering and its read into a widget module and
changes no figure. The audit's S2 on Wealth's sections (#1526, #1527,
#1528, #1529, #1530, and R-024's board) stay with the triage's step 3,
which boards them; W names each in the briefing where it moved the code
that carries it, so step 3 finds it. Write forms stay on their pages,
linked from the widget (ADR-0022's amendment of 2026-11-21, point 3). The
Wealth page keeps working, unchanged, as the full view. *Why:* a pass that
moves and fixes at once cannot be reviewed against either decision.
**To flip:** „Wealth-Fehler gleich mit beheben“ (adds step 3's Wealth half,
with its boards, to the second PR).

### D-8: what waits, and why

- **Cashflow, Steuer, Prognosen** and the end of the Wealth page: the
  next widget pass, after the audit's step 1 by D-2's order.
- **The heatmap and the trading activity** (I60, board 05): two new
  figures, each with its decision record ADR-0063 on that pass's
  planning PR; the themes „Performance“ and „Einkommen & Steuer“ come with
  them.
- **The Datenqualität hint for legacy closes of 0** (Sprint 31's
  carry-forward 3): when the two data-quality surfaces (the widget's
  `Catalog.DataQuality` count and Holdings' data notes, which W1 moves as
  they are) are merged into one kind, which needs its own board.
- **I48 is no longer a precondition**: you asked to keep today's look, so
  no card is redrawn by these passes (the Sprint 31 plan's D-10 is
  superseded).

### D-9: two stacked PRs (recommended)

Estimate: M 1–3, E 8–10, T 10–11, S 10–12, L 9–12, W 22–25 build
commits; the closing act at about one and a half fixes per build commit on
a new surface (E, T, S) and about a half on reworked or moved code (L, W):
about 45 and 18. **PR 1** (M, E, T, S and their closing act) about 80
commits; **PR 2** (L, W, their closing act, the close-out and the
retrospective) about 70. The second branch is
`<the first>-pr2`, based on the first; both merged in order in one sitting.
Every story's commits whole, so a stop at the weekly usage limit loses
nothing (Sprint 31's carry-forward 10). **To flip:** „ein PR“ (only if the
estimate falls under 90 at the first PR's close).

### D-10: Sprint 31's carry-forwards

1 (the compact type on a phone): yours, unchanged. 2 (#1485): the audit's
step 2 carries it with #1484, its duplicate. 3 (the legacy-0 hint): D-8.
4 (I48 first): superseded, D-8. 5 (Lane P's two S3): onto the Wealth polish
list by W5, fixed there if the lines fall in moved code. 6 (the recorded
S3s): onto their lists by the implementation session's first commit. 7 to
9: D-3. 10: D-9. 11 (one lock-table row per lane): T2 and S3 each reserve
one row in `test/support/lock_table.ex` if they take a lock, named in
their story.

### D-11: bookkeeping after the merge (the planning session)

- **#1482** closed by hand as answered by the amendment's point 6, with
  the link; **#1481** stays open (one layout per device class).
- **One issue for this sprint's work**, under #418: „FR-60, the second
  slice: the others make room, the periods, the starters (Sprint 32)“,
  pointing at this plan, the amendment and the boards; the sprint PRs
  close it.
- **One issue for I60** under #418, pointing at board 05 and naming its
  decision gate (ADR-0063), so the next plan finds it.
- `epics.md`'s FR-60 line already points at the amendment (this PR); the
  idea rows I57 to I61 are on this PR.

### D-12: one look for every widget, and the Kennzahlen as A (your picks of 2026-11-25; boards 06, 07)

You found the Kennzahlen widget cluttered and picked variant A on board 06;
then you asked to check the look of every widget. Board 07 photographs all
eleven kinds in all 21 sizes in the running app and finds ten things
(the period on its own line, basis sentences in the body, warning boxes,
Tops und Flops' bars hidden behind „Beitrag“ — your question of the same
day: „das war hilfreich“ —,
a card inside a card with clipped figures, five headline sizes, sizes
that add nothing, nine footer wordings, a paragraph where a column
belongs, switches in two places). The anatomy of board 07 ② answers them
all, from A's measures. *Why before Lane W:* the sixteen Wealth widgets are
then built in it once, not redrawn after. *Why not wait for I48:* the
anatomy decides structure and type, not colour; I48's colour question
stays open and touches none of it. „Ergebnis“, not „Gewinn“, because
„Beitrag je Position“ already names that figure so. **To flip:** „Look
erst nach Vermögen“ (L moves after W), „Kennzahlen B“ (board 06 ① B).

### D-13: Apple's widget families, fixed heights, and a gallery for the docs (your questions of 2026-11-25; boards 08, 09)

You asked whether the sizes follow Apple's recommendations and whether the
templates still look good with widgets on them. Board 08 shows every kind
in every size, light and dark; board 09 sets three dashboards on today's
sizes and, simulated in the browser, on Apple's tiles. Today the sizes
follow the pattern only half: W is two S, M two W, but S is not square,
L (8 columns) and T (4) are no multiple of S, and no size has a fixed
height, so a row grows to its tallest widget (Tops und Flops S is 593 px)
and a dashboard looks ragged. **Recommended:** Apple's families S, M, L,
XL with fixed heights (amendment 3), each kind with its own layout per
family (Lane L), and the gallery of board 08 rebuilt by a script for the
docs after Lane L (L4). Board 09's right column shows why both halves are
needed: fixed tiles alone calm the grid but cut or empty today's content.
*Why Apple's:* they are a tested size system, and the native widgets of
I53 can then take the same families. **To flip:** „Größen wie bisher“.

### D-14: one surface with hairlines (your pick of 2026-11-25; board 10)

You did not like the spacing. Board 10 set the template „Überblick“ on
Apple's tiles in four spacings, in the running app; today's gap (12 px) is
smaller than the inner padding (16 px), so the cards look glued together.
The plan recommended B „Luftig“; **you picked D „Eine Fläche“** for the
web app: „Ich will da nicht so viel Platz verschwenden. Widgets als
einzelnes Element auf iOS wäre was anderes für später.“ A dashboard is one
surface with one rounded frame, its widgets separated by 1 px hairlines,
without gaps, card borders or shadows; checked in light and dark on board
10. Separate cards with gaps stay for the native widgets of I53. Built in
L1 as tokens. **To flip:** „Abstand B“, „Abstand C“, „Abstand wie
bisher“.
