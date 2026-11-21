# Sprint 31 — the first dashboard of widgets, one period above it, a price of 0 read as none, four S2s

**Status: ADOPTED by the merge of the Sprint 31 planning PR.**
The merge is the signature (ADR-0026 step 1, as amended on 2026-10-08). It
signs [ADR-0062](../../docs/decisions/0062-widgets-and-composed-dashboards.md)
(FR-60, idea I56, D-4), [ADR-0022's amendment of
2026-11-21](../../docs/decisions/0022-task-oriented-information-architecture.md)
(the menu of dashboards, „Pflege“, I47; D-7), [ADR-0051's amendment of
2026-11-21](../../docs/decisions/0051-contribution-analysis.md) (#1473, the
walk reads a close of 0 or below as no price; D-5), the identity sentence
of I46 in `AGENTS.md`, the brief, the PRD and the docs (D-6), the decisions
below, the I56 idea boards 01 to 06 in
`design-language/mockups/ux-design-2026-11-21-idea-i56/` and the planning
board `ux-design-2026-11-21-sprint31/01`. One change moves stored-figure
reads: D-5 changes which closes the performance walk values, on instances
that store a close of 0 or below; no booking changes and no stored row is
rewritten. A fresh implementation session builds the sprint on the branch
its environment assigns, or `agent/<provider>/sprint-31`, as **one sprint
PR** with a cut prepared (D-9). The severity rule of ADR-0026's amendment of
2026-11-01 applies unchanged.

## What you need to do

1. **Merge, to adopt the plan.** Everything in it you answered on
   2026-11-21 in the session that wrote it:
   - **I56, every function a widget** (ADR-0062, D-4): navigation A
     („Ja A finde ich super“), one period above every dashboard with
     pinned widgets (board 05 A, „Ja“), the width classes and compact forms
     (board 06; the type you found large is checked on a real phone in the
     UAT, as you said it is likely a drawing effect), the controls moving to
     the side on a short, wide window by the same rule. Sprint 31 builds the
     **first slice**: the Overview becomes the first dashboard, with its
     cards and the four functions you named as most read or hidden
     (Wertentwicklung, Allokation und Drift, Snapshots, Crashes). Wealth
     stays a page under „Entdecken“ until its own pass (board 01 ①).
   - **#1473** (D-5): a stored close of 0 or below counts as no price in
     the walk too, as everywhere else; a failure shows through the booking
     that removes the position at 0, never through a quote („hatten wir
     schon besprochen“).
   - **I46** (D-6): "self-hosted" leaves the identity sentence; it stays
     how Portfolixir runs today.
   - **I47** (D-7): no new write form on a reading screen; the forms move
     to „Pflege“ as their screens' passes reach them.
2. **Look at board 01 of `ux-design-2026-11-21-sprint31`** (what this
   sprint builds of I56, and what is transitional). D-4 and D-7 list each
   choice with the phrase that flips it; silence adopts the
   recommendation.
3. **Optional, for Sprint 32:** the next idea to go deep is **I48** (the
   colours and the card), before the second widget pass redraws the cards
   (D-10). Its board lets you decide by eye.

**Not asked:** everything else. **Not raised:** I31 (live prices, waiting
for your read of the source's terms), I44 (the drag, behind the widget
passes), I49 (behind the redesign, your word of 2026-11-19), I50 and I51
(each comes with its screen's pass), I53 step 1 (the home-screen hint,
after the compact layout ships), I55 (more crash windows, its own ADR-0058
amendment, best with the Risk pass), I38 to I41 (one audit sprint, I41's
question first).

**Verification basis:**

- **Sprint 30's merge, as its close-out asked this plan to record:** the
  sprint PR #1471 merged at 06:15 UTC on 2026-11-20 (`c897a62`), release
  **2026.11.20** published at 06:15 UTC from `main`; 2026.11.19 was
  published from `main` on 2026-11-19 at 09:51 UTC. #1471's keywords
  closed #1457, #1460, #1465, #1466, #1467 and #1472. `main` is at
  `c897a62`, unmoved since.
- **The open-issue list of 2026-11-21:** 35 open: the four S2s Sprint 30
  filed or carried (#1470, #1474, #1475, and #1473 with `needs-decision`,
  answered by D-5); `agentic` #899, #900, #1070, #1396, #1451 to #1456;
  `needs-decision` #1177 and #1220; `needs-uat` #328 and #354; 17 trackers
  (11 polish lists #1355 to #1366 without #1364; #991; the five area
  trackers #416 to #420). #1469 (the `plug` advisory) is closed. Three
  Dependabot PRs are open: #1392 (floki 0.38.5, closable per Sprint 30's
  M1), #1476 (bandit 1.15.0) and #1477 (Playwright 1.65.1), both declined
  by Sprint 30's M1 with their reasons and weighed again by M1 here.
- **The polish lists' open lines on 2026-11-21:** Securities (#1365) 16,
  API and MCP (#1356) 13, Imports (#1355) 10, Shell (#1357) 9, History
  (#1360) 9, Overview (#1358) 7, Wealth (#1366) 7, Cash flow (#1359),
  Accounts (#1361) and Merge pages (#1363) 5 each, Classifications (#1362)
  3: 89 in all.
- **Read against the code on `c897a62`**, each claim this plan rests on:
  - The walk values every stored quote: `held_quotes/3` (line 1532) and
    `carried_seed/5` (1575) in `lib/portfolixir/portfolios/performance.ex`
    take no bound on the close, while `WindowReturn`, the crash rankings and
    the cycles read only positive closes (`security_cycles.ex` 307:
    "positive closes only"). `Derived.Registry` holds
    `performance_analysis` and `performance_view_analysis` at computation
    version 4, `performance_contribution` and `performance_view_contribution`
    at 6, the bands at 1. Hence Z1 and its version moves.
  - The Overview (`dashboard_live.ex`) draws its cards as sections: the
    value KPI, Data quality, Due, Off target, Tops and flops
    (`dashboard/movers_card.ex`), the cycle card, Closed trades and the
    workflow path. Wealth already remembers its period in the browser
    (`portfolio_live.ex` 294, `period-memory`), the theme does
    (`priv/static/theme-boot.js`); the default period is `"1y"`. Hence D3
    and D5's storage.
  - The menu is built in `components/app_shell.ex` (groups from line 386:
    Overview, Wealth, Securities, News; Transactions, Accounts & depots,
    Views, Classifications, Audit journal). Hence D7.
  - The browser walks launch Playwright's default Chromium or
    `PLAYWRIGHT_CHROMIUM_EXECUTABLE` (`test/browser/launch.js` 13); CI runs
    the pinned release's headless shell. Hence M2 (Sprint 30's
    carry-forward 1).
  - `scripts/worktree.sh` links every worktree's `deps` to the main
    checkout's (its header, line 11). Hence M4 (carry-forward 9).
- **Boards:** the six I56 idea boards, drawn and answered with you on
  2026-11-21, and the planning board 01 for this sprint's slice, on the
  shipped `app.css`, every name and figure invented.

## State of play, in five lines

1. **Sprint 30 is on `main`** (release 2026.11.20): tops and flops, the
   shipped Inter, the axis mark, three polish passes, one lock order.
2. **You set the next sprints on redesigning what exists** (intake of
   2026-11-18) and gave it its shape on 2026-11-21: every function a widget,
   dashboards composed from them (I56).
3. **Four S2s wait**: the walk's price of 0 (#1473, answered), a suspected
   recluster–merge deadlock (#1470), the local and CI collations (#1475),
   the privacy walk near its bound (#1474).
4. **I34's step 2 is measured** (Sprint 30's M6) and waits to be built.
5. **89 polish lines** wait on eleven lists; this sprint takes the
   Overview's, since the Overview becomes the first dashboard.

## Why this cut

- **I56's first slice, because it is the redesign's foundation** and you
  asked for it: the widget contract, the storage, the API and MCP, the
  period, the edit mode, the width classes and the menu are built once;
  every later pass is then one screen's sections turned into widgets. The
  Overview first, because it is already a page of cards, and the four
  widgets you named, so the first dashboard holds what you look for.
- **Wealth stays a page this sprint** (board 01 ①), because turning all of
  it into widgets doubles the sprint; it is the next pass, after I48
  decides the cards' look. „Vermögen sofort auflösen“ flips it.
- **#1473, because it is S1 by its figure and answered**, and the money
  lens found it in the walk every money read rests on.
- **#1470, #1474 and #1475, because an S2 the next diff reaches is fixed**
  (Sprint 30's carry-forward 6), and #1475 failed every CI run of the seed.
- **I34's step 2, because its numbers are in** and the first dashboard's
  largest widget is the chart it speeds up.
- **The Overview's polish list, because its cards become widgets**: its
  lines are fixed in the widgets, not carried into them.
- **What is left out, and why** (each flips by naming it): Wealth's and the
  other screens' passes (after I48); the remaining four templates (their
  widgets are not built yet, ADR-0062 §3); the other polish lists; #1396,
  #899, #900, #1070, #1220, #1177, #328, #354 and #1451 to #1456 keep their
  standing reasons (D-11).

## Lanes (one sprint PR, in this order: M, K, Z, P, D)

**Lane M, maintenance and the build's own tools (first).**

| Story | Source | What it does | Commits |
|---|---|---|---|
| M1 | standing rule; #1392, #1476, #1477 | the version report `version-report-2026-11-…-sprint31.md`: Hex, npm (Playwright 1.65.1 in `test/browser`, #1477, weighed against M2's shell), Elixir/OTP, PostgreSQL, BMAD core and the external modules, bandit (#1476) and floki (#1392), each bump its own commit, what is declined with its reason | 1–3 |
| M2 | Sprint 30 retrospective, carry-forward 1 | **the walks run in CI's headless shell by default**: `test/browser/launch.js` launches the pinned Playwright release's `chromium-headless-shell` unless `PLAYWRIGHT_CHROMIUM_EXECUTABLE` names another browser, and says which it launched; the guide and `AGENTS.md`'s browser note say so (the maintenance lane's fact correction); a test pins the launcher's choice | 1 |
| M3 | #1475 (S2) | **one collation for the test database, local and CI**: the test database is created with an explicit collation that every machine has (an ICU collation, or `C.UTF-8` in CI as well, whichever the commit argues), an invariant asserts the running test database's collation, and the seed's name order no longer depends on it (Sprint 30 already sorts in Elixir; the invariant keeps the next one from depending on it) | 1 |
| M4 | Sprint 30 retrospective, carry-forward 9 | **a worktree's `deps` cannot change the main checkout's**: `scripts/worktree.sh` gives each worktree its own `deps` copy when the lock file differs, or links it read-only otherwise, and `scripts/test_worktree.py` pins both; the guide says so | 1 |
| M5 | #1474 (S2, flaky) | **the privacy-mode route walk at its cause**: measure where its 25 to 38 s go under load (Sprint 30 saw `/portfolio`'s stack views), recorded in the commit, then the fix at that cause; 20 loaded runs green, **the 60 s bound not moved** | 1 |

**Lane K, one lock order** (#1470). **Risk tier: stored data** (a recluster
and a security merge may take clusters and items in opposite orders): its
own commit group, a dedicated verification pass, a callout in the
briefing.

| Story | Source | What it does | Commits |
|---|---|---|---|
| K1 | #1470; `test/support/lock_table.ex` | a race test under `test/portfolixir/lock_race/` that parks a recluster after its cluster locks and a merge after its item locks: **red first** (`40P01`, or the test's own deadline), or, if no interleaving deadlocks, a commit that records why and closes #1470 as not reproducible with the evidence. A fix registers one order in the lock table and both paths take it; 50 loaded runs green; its attack lens before integration | 1–2 |

**Lane Z, a close of 0 or below is no price in the walk** (#1473; ADR-0051,
amendment of 2026-11-21; D-5). **Risk tier: money math**: its own commit
group, a dedicated verification pass with every pinned figure recomputed in
Python's `decimal` at 34 digits, a callout in the briefing.

| Story | Source | What it does | Commits |
|---|---|---|---|
| Z1 | ADR-0051's amendment of 2026-11-21 | **the walk skips a non-positive close as it skips a missing one**: `held_quotes/3` and `carried_seed/5` read only closes above 0, the last positive close carries, a position with none counts zero by §10; the count's special case of 2026-11-19 goes with it; every analytic the registry derives from the walk moves one computation version (the commit lists them from `Derived.Registry`); tests first: the issue's synthetic case (10, a legacy 0, 11) reads a contribution of 1 and a price side of +10 %, a series with a legacy 0 equals the same series without that row to the last digit, a position whose only close is 0 counts zero with `no_price`; `walk_payload_pin_test.exs`'s digests unchanged; the attack lens before integration (a 0 on the baseline day, on the window's last day, a negative close, a 0 on a split day, a 0 as the only close in a currency without a rate) | 2–3 |

**Lane P, faster charts, step 2** (I34; Sprint 30's M6 numbers).

| Story | Source | What it does | Commits |
|---|---|---|---|
| P1 | I34's step 2; `perf-2026-11-19-wealth-chart.md` | **warm the default period** (1J) for every scope a screen opens with (everything, each view): the stacked chart's bands and the 1-year contribution table, in the background after boot and after a write that bumps the basis, bounded by the memo's budget (one scope warmed fully is 29 MiB of 128, so the bands and the table only, about 0.7 MiB per scope), never blocking a request; a test asserts a hit after the warmup and none served across a basis bump | 1–2 |
| P2 | I34's step 2 | **a memo hit renders without the skeleton**: the read checks the memo before it schedules the background read, and a hit draws the chart in the same render; a browser test sees no `stack-skeleton` on a warm switch; the before and after medians on the review seed recorded in the commit, measured as M6 measured them | 1 |

**Lane D, every function a widget: the first slice** (FR-60, idea I56;
ADR-0062; ADR-0022's amendment; the I56 boards 01 to 06 and planning board
01). Every story that renders gets its frame on the boards; each widget's
figures are compared with its source route's answer in its test.

| Story | Source | What it does | Board | Commits |
|---|---|---|---|---|
| D1 | ADR-0062 §1 to §3 | **the context**: `Portfolixir.Dashboards` (or the name the conventions give) with the widget registry (kinds as strings, sizes, source route, period rule, scope, compact form flag), the `dashboards` table and its migration, the layout's validation (every refusal of §2 a test seen red first: unknown kind, missing size, off-grid, overlap, unknown `view_id`, pin on a kind without a period, 41 items, 51 dashboards, a 61-character or control-character name), the journal entry per write, `lock_version` with 409, the template „Überblick“ in code; **no atom from a stored or sent key** (a test sends an unknown kind and finds no new atom) | — | 3 |
| D2 | ADR-0062 §8 | **the API and MCP**: `GET /api/v1/widgets`; `GET /api/v1/dashboards` (stored and templates, marked), `GET /:id`, `POST` (create or copy a template), `PUT` (with `lock_version`), `PATCH`, `DELETE` with `dry_run`; `portfolixir.dashboards.list`, `.get`, `.put`, `.delete` within the schema budget; contract entries; the docs (English and German); `metrics_carry_no_verdict_test.exs` walks the catalogue | — | 3 |
| D3 | ADR-0062 §4, §6, §12; ADR-0022 amendment 4 | **the dashboard page at `/`**: the template read-only on a fresh instance with „Anpassen“ (a read never writes: a test reads `/` on an empty table and finds it still empty), the stored dashboards by `position`, the grid in the wide class, two columns in the medium class, one column of compact forms in the compact class, the short-wide window's side rail, chosen in CSS by width and height (an invariant: no user agent is read anywhere in `lib/portfolixir_web`); the widgets of today's Overview turned into kinds (Gesamtwert, Datenqualität, Fällig, Abseits des Ziels, Tops und Flops, Bitcoin-Zyklus, Verkaufsrückblick), each with its compact form; **the Overview's polish list (#1358) fixed in its widgets**, one functional test per line, seen failing first, each line ticked; the workflow path stays a first-run card on the template until the depot pair exists | I56 03, 06; 01 ① | 4–5 |
| D4 | ADR-0062 §12 | **the four widgets you named**: Wertentwicklung (S, M, L; full view: Wealth's chart), Allokation und Drift (M, T; with the display-only arithmetic of ADR-0023), Snapshots (S, W), Crashes im Vergleich (M; „Im Depot · Katalog“), each with its compact form, its ⓘ the source's basis, its figures equal to its route's | I56 01, 03, 06 | 5–6 |
| D5 | ADR-0062 §5 | **one period above every dashboard**: the selector in the top bar, remembered per browser and kept across dashboards, `period=` in the address when it is not 1J; „folgt · …“, the pin in the ⋯ menu stored in the item's `settings` and drawn as „📌 eigener: …“, the translation labels („3M → Quartal“) by each kind's stated rule, „ohne Zeitraum“; tests for each, and a switch from one dashboard to another keeping the period | I56 05 | 2 |
| D6 | ADR-0062 §7 | **the edit mode**: „Bearbeiten“, handles, the size switch with the kind's sizes, ×, the catalogue panel, „Zurücksetzen“, „Fertig“ as one write (one journal entry per save, a test counts them), the keyboard path (arrows move, the switch's buttons size, Delete removes), announced to a screen reader; reorder, size and remove only in the compact class; a stale save shows the 409's stored layout and offers to load it | I56 03 | 4 |
| D7 | ADR-0022 amendment 1 to 5 | **the menu**: Dashboards (stored, or the template; „Neues Dashboard“), Entdecken (Vermögen, Wertpapiere, Nachrichten, „Alle Widgets“), Pflege at the foot; the catalogue page „Alle Widgets“ with the slice's kinds and, dashed, the kinds each later pass brings; „Neues Dashboard“ (empty or from a template); the compact tab bar with „Mehr“; every old route still answers; the docs' navigation section and screenshots of the changed screens (English and German) | 01 ② to ④ | 3 |
| D8 | ADR-0062 §1, `DESIGN.md` | `DESIGN.md` gains the widget's anatomy, the sizes, the compact type floor and the width classes; `EXPERIENCE.md` the period rule and the edit mode; the walks measure the compact forms at 375, 393 and 440 pt, the medium class at 760 × 580 and 834 pt, the wide grid at 1200 px, and fail a compact text under 12 pt | — | 2 |

## Decisions

### D-1: what this sprint is for, and its exit criteria (recommended)

The sprint builds the redesign's foundation and its first dashboard, reads a
price of 0 as none in every read, and closes four S2s. Exit criteria:

1. **Every widget draws its source's figures**: per kind, a test compares
   every figure the widget shows with its route's answer for the same scope
   and period; no widget carries a figure of its own or a verdict word.
2. **A dashboard is stored, validated and journaled**: every refusal of
   ADR-0062 §2 is pinned by a test seen red first; a stale write answers 409
   with the stored layout; a read never writes; the template is never
   stored and never edited; the API and MCP answer what the screen shows.
3. **One period above every dashboard**: remembered per browser, kept
   across dashboards, carried in the address; a pinned widget is marked; a
   translated or absent period is labelled.
4. **The width picks the layout, never the device**: compact, medium and
   wide by width and height, no user agent read; the walks measure the
   compact forms at three phone widths and fail type under 12 pt; the UAT
   checks the type on a real phone or, where none is at hand, says so.
5. **The edit mode works by pointer and by keyboard**, and one save is one
   journal entry.
6. **A close of 0 or below is no price in the walk** (#1473): the synthetic
   cases reproduce in Python's `decimal`, the pinned digests stay, every
   analytic reading the walk moves its computation version.
7. **The four S2s are closed at their cause**: #1470 red before and green
   on 50 loaded runs after (or shown not reproducible with the evidence),
   #1475's collation one and asserted, #1474 green on 20 loaded runs with
   its bound unmoved, the walks in CI's headless shell.
8. **I34's step 2**: the default period served from the warm memo after the
   warmup, a hit drawn without the skeleton, the before and after medians
   recorded.
9. **Every gate by registration; regressions counted, none an S1 at
   promotion.**

### D-2: the redesign's foundation, with consolidation beside it (your decision, with the plan's recommendation)

You set the next sprints on redesigning what exists (2026-11-18) and gave
it its shape on 2026-11-21. This sprint builds the shape once, on the
screen that is already a page of cards, and adds four widgets so the first
dashboard holds what you named. *Why not more screens now:* every widget
pass after this one is a screen's sections turned into widgets; doing
Wealth in the same sprint would build its widgets before the contract has
met a real screen, and before I48 decides the cards' look.

### D-3: the order of the work (recommended)

M first (M2 and M4 change how every later story is run, M3 how its seed
sorts), then K and Z (risk tier, small, each with its attack lens before
integration), then P (it touches the read D4's Wertentwicklung draws),
then D in its order: D1 and D2 (the contract and its API) before D3 (the
page), D4 and D5 beside each other once D3 is integrated, then D6, D7, D8.
Parallel story agents as in Sprint 30, **at most two running tests at once**
on a four-CPU machine (Sprint 30's carry-forward 3), each in its own
worktree from `scripts/worktree.sh` and its own test database.

### D-4: ADR-0062's first slice and its boards (recommended; the shape is your decision of 2026-11-21)

ADR-0062 records the shape you picked. The slice (§12) and the boards:

- **The I56 idea boards 01 to 06 are adopted as the shape**, with two
  boards superseding parts of earlier ones: board 05's period above the
  dashboard replaces the period chips inside each widget that boards 01
  and 03 draw, and board 06's compact forms replace board 04's first phone
  (removed from board 04 on the same day).
- **Planning board 01** draws what this sprint builds: ① a fresh instance
  showing the template read-only in the transitional menu, ② „Alle
  Widgets“ with the later kinds dashed, ③ „Neues Dashboard“, ④ the compact
  tab bar and „Mehr“.
- **Wealth stays under „Entdecken“** until its pass (ADR-0022's amendment,
  point 1). *Why:* most widgets come from Wealth, and its pass is its own
  sprint.
- **The template „Überblick“ only**: the other four templates are offered
  when their widgets exist (ADR-0062 §3), so no template promises a widget
  that is not there.

**To flip:** „Vermögen sofort auflösen“ (Wealth's tabs become widgets in
this sprint, which then stacks into two PRs and grows by about 40
commits); „Pflege oben“ (the maintenance group before „Entdecken“);
ADR-0062's own table for the shape.

### D-5: #1473, a close of 0 or below is no price in the walk (your decision, 2026-11-21)

You asked why the last close should carry when a security is worth 0; the
answer recorded in ADR-0051's amendment of 2026-11-21: a real security
does not close at 0, a stored 0 is a feed's placeholder from before the
plausibility bounds, and a failure is booked as a removal at 0, which the
walk already reads as −100 % (ADR-0010). You took the recommendation on
2026-11-21. The data-quality hint that lists such closes for removal is
drawn once, in the Datenqualität widget's pass (ADR-0062 §13), not on
today's card. **To flip:** „Nullkurs als Kurs werten“ (removes Lane Z and
the amendment from this PR).

### D-6: I46's identity sentence, on this PR (your decision, 2026-11-19)

The identity sentence is reworded once, the same in each place:
`AGENTS.md` ("What Portfolixir is"), the brief's executive summary, the
PRD §1, the README's headline and "What is Portfolixir", `docs/index.md`,
`docs/features.md` and `docs/de/features.md`: a portfolio tracker with two
first-class users, one dataset, one instance, one operator, no tenancy, no
broker, always on and reachable by the operator's agent; self-hosted today,
which is how it runs, not what it is. The README's further rework stays
I36's, after the screens settle. **To flip:** „Selbst gehostet als
Identität“ (reverts the seven edits).

### D-7: the menu of dashboards and „Pflege“ (your decision on board 02; the transition recommended)

ADR-0022's amendment of 2026-11-21 replaces its table of areas with three
groups, Dashboards, Entdecken and Pflege (board 02 A, your pick), and
records I47: the screen is a view, the forms move to „Pflege“ as their
screens' passes reach them, and the guardrail asks a new function for its
widget kind. Transitional, recommended: Wealth under „Entdecken“ until its
pass; every old route keeps answering, so a bookmark and the docs' links do
not break. **To flip:** „Bereiche behalten“ (board 02 B), „Pflege oben“.

### D-8: the closing act and the build (standing, with Sprint 30's carry-forwards)

Each lens reviews the PR's diff and reports at most five findings, ranked
by severity. The story workflow's section "What a story's own tests do
not cover" applies to every story. Sprint 30's carry-forwards, applied:

1. **The walks in CI's headless shell**: M2 makes it the default.
2. **One collation**: M3 (#1475).
3. **At most two agents running tests at once** on four CPUs (D-3).
4. **The full suite after every closing-act fix batch, before the push**:
   every fix brief says so.
5. **#1473's decision**: D-5.
6. **#1470, #1474, #1475**: K1, M5, M3.
7. **I34's step 2 planned from M6's numbers**: Lane P.
8. **The polish lines**: the Overview's in D3; the rest with their screens'
   passes.
9. **The worktree helper's `deps`**: M4.
10. **The attack lens before integration, pointed at every lock order and
    every money change a story introduces**: K1, Z1 and D1 (the layout's
    validation and the 409 against two concurrent writers: the screen and
    an agent's `put` on the same `lock_version`).
11. **Integrate each lane's catalogue refresh into the lane's own last
    commit** (Sprint 30's "Not every commit proves its invariants"), so
    every commit's gettext is current.

Lenses for this PR: correctness; the money lens (Z1, every pinned figure
recomputed in Python's `decimal` at 34 digits; D4's widgets against their
routes); edge cases and order (K1, Z1, D1, D6); security (D1's layout
input, D2's routes and tokens, the no-atom rule, the name's escaping); the
agent's lens (D2's catalogue and tools against the companion's
descriptions and the schema budget: can an agent compose „ein Dashboard
für kurzfristige Bewegungen“ from `list`'s answer alone?); accessibility
(D6's keyboard path and announcements, the compact type floor); the design
critic against the I56 boards, planning board 01 and `DESIGN.md`; the UAT
persona on the review seed at the end, in every width class, and on a real
phone if one is at hand (D-1 criterion 4). A closing-act fix that changes
what a screen shows gets its frame on this sprint's board folder first. The
browser job runs locally before the closing act on the integrated head.
GitHub writes go through the MCP tools. This planning PR carries no closing
keyword (checked before it was opened); the sprint PR names `Closes` for
#1470, #1473, #1474, #1475 and FR-60's issue (filed after this merge); the
Overview's polish lines are ticked on #1358, which stays open while it has
lines.

### D-9: one sprint PR, a cut prepared (recommended)

About 88 commits: Lane M 5 to 7, K 1 to 2, Z 2 to 3, P 2 to 3, D 26 to 28,
the closing act's fixes about 35 (counted by its lenses at about one fix
per build commit, more for the new surface), the UAT persona 2, the
close-out 4. At the stacking threshold of about 90, so **the cut is
prepared after Lane P**: if the build passes 60 before Lane D's D6, the
session stacks D with its closing act as `<its branch>-pr2`, as `AGENTS.md`
allows, so the risk-tier work merges on its own PR first, and says so in
the PR's body.

### D-10: the ideas (the sprint workflow's "Ideas")

- **I56 went deep in this session**, on its idea board with you, and leaves
  the list: worked out as ADR-0062, FR-60 in `epics.md`, planned as Lane D;
  its row is a pointer. **I35** is planned as its shape, **I47** as
  ADR-0022's amendment, **I46** on this PR.
- **I34's step 2** is planned as Lane P.
- **I55** (more crash windows, sector crashes) was recorded and triaged on
  2026-11-21; it needs an ADR-0058 amendment and is best planned with the
  Risk pass.
- **I50 and I51** took your words of 2026-11-21 into their rows; each
  comes with its screen's widget pass.
- **The next idea to go deep is I48** (the colours and the card), before
  the second widget pass redraws the cards.

### D-11: what stays open, and why (standing)

#899, #900, #1070 and #1220 keep Sprint 22's reasons. #1177 waits for its
trigger. #328 and #354 wait for your check on real data. #1396 waits until
the sample can carry the split (ADR-0055 §9). #1451 to #1456 are the asks
ADR-0059 and ADR-0060 deferred. The polish lists stay open while they have
lines; a story that touches a screen fixes its lines. ADR-0062's two
deferred asks (one layout per device class; the period on the server) are
filed after this merge (below).

### D-12: I34's step 2, what is warmed (recommended)

Warm the default period's **bands and 1-year contribution table**, not the
whole walk per period: M6 measured one scope warmed fully at 29 MiB of the
memo's 128, the bands and the table at about 0.7 MiB and 0.7 s of CPU per
scope, saving about 560 ms of a cold first paint at Kategorien € 1y on the
server; a warm switch's read is under 10 ms of 25 to 86 ms, so the other
half of the gain is drawing a hit without the skeleton (P2). The scopes
warmed are everything and each view, the ones a screen opens with. **To
flip:** „Alle Zeiträume vorwärmen“ (every period, bounded by the memo's
budget, measured before it lands).

## Registry bookkeeping after the merge (the planning session's last step)

- File FR-60's issue under #418 (I56), pointing at ADR-0062, the I56
  boards, planning board 01 and this plan's D-4; FR-60's coverage row in
  `epics.md` gains its number.
- File ADR-0062 §13's two deferred asks as issues under #418 (one layout
  per device class; the period stored on the server), each with its
  recommended answer and what reopens it.
- Relabel #1473: `needs-decision` removed (answered by D-5).
- Close #1392 by hand if Dependabot has not, per Sprint 30's M1, with the
  evidence; no other closures.

## Checklist (the implementation session ticks it on the PR)

- [ ] Lane M: M1 the version report (#1392, #1476, #1477), M2 the walks in
      CI's headless shell, M3 one collation (#1475), M4 the worktree's
      `deps`, M5 the privacy walk (#1474)
- [ ] Lane K: K1 the recluster–merge lock order (#1470), its attack lens
      before integration
- [ ] Lane Z: Z1 a close of 0 or below is no price in the walk (#1473),
      its attack lens before integration
- [ ] Lane P: P1 the warm default period, P2 a hit without the skeleton
      (I34)
- [ ] Lane D: D1 the context, its attack lens before integration, D2 the
      API and MCP, D3 the dashboard page with the Overview's widgets
      (#1358), D4 the four widgets, D5 the period, D6 the edit mode, D7 the
      menu, D8 the design documents and the width walks (FR-60)
- [ ] Closing act: the lenses, the fixes, the full suite after each batch,
      the re-check, the UAT persona in every width class
- [ ] Close-out, retrospective, briefing, promotion
