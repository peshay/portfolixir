# Sprint 30 — tops and flops, the shipped font, where the axis starts, three polish passes, one lock order

**Status: ADOPTED by the merge of the Sprint 30 planning PR.**
The merge is the signature (ADR-0026 step 1, as amended on 2026-10-08). It
signs [ADR-0061](../../docs/decisions/0061-tops-and-flops-per-calendar-window.md)
(FR-59, idea I32, D-12), the decisions below, the four planning boards in
`design-language/mockups/ux-design-2026-11-15-sprint30/` and the story
workflow's two added rules (D-9). No other ADR is signed or amended, and
nothing in this sprint changes a booking or a stored money figure. A fresh implementation session builds the sprint on the branch its
environment assigns, or `agent/<provider>/sprint-30`, as **one sprint PR**
(D-8). The severity rule of ADR-0026's amendment of 2026-11-01 applies
unchanged.

## What you need to do

1. **Merge, to adopt the plan.** Nothing in it books or corrects a stored
   money figure. Two things change what you may have expected:
   - **One feature, I32, tops and flops per period** (D-12), as you asked
     on 2026-11-15 („ja mach I32 noch rein“). Its record ADR-0061 is on
     this PR, so your merge signs it. **Its one open question is answered
     by the plan's recommendation**, since you put it in without choosing:
     **both rankings side by side**, price return („Kursrendite“, what the
     security did) first, money contribution („Beitrag“, what it did for
     you) beside it. "Tops/Flops nur Kursrendite" or "Tops/Flops nur
     Beitrag" keeps one. ADR-0061 lists its other judgement calls with
     their flips („Tag“ is each security's last close against the one
     before; sold positions only in the contribution).
   - **Otherwise a consolidation sprint** (D-2): the font the layout gate
     depends on (#1221), where the Total chart's axis starts (I43), three
     polish lists as planned passes (Wealth, Shell, API and MCP), one
     suspected deadlock (#1457) and two flaky tests at their cause.
2. **Look at board 04** (I32's card on the Overview, D-12), **board 01**
   (I43, the idea this session works out, D-6), **board 02** (the Wealth
   polish pass) and **board 03** (the shipped font). D-6, D-7 and D-12
   list each proposal with the phrase that flips it; silence adopts the
   recommendation.
3. **Optional, for Sprint 31:** none asked. The next idea to go deep is
   I20 (usage hints in the MCP companion, D-10).
4. **Optional, still open from earlier plans:** ADR-0056 D10 (which prompt
   version the reads follow; recommended (a), a configured active version,
   before a second labeller runs); branch protection, which on 2026-11-12
   required no status check at all (not re-read here: the session's tools
   cannot read it); Dependabot's #1463 (Playwright 1.65.0) is taken by M1,
   and Dependabot closes it itself once `main` has the bump.

**Not asked:** everything else. **Not raised:** I31 (live prices, waiting
for your read of the source's terms), I35 (tidying the app, its inventory
first), I38 to I41 (one audit sprint, I41's question first), I42 and I44
(I44 waits for I43, as its row says), I25 and I26 (triaged, each with an
open question in its row).

**Verification basis:**

- **Sprint 29's merges, as its close-out asked this plan to record:** PR 1
  #1458 at 06:23 UTC and PR 2 #1461 at 06:24 UTC on 2026-11-13 (releases
  **2026.11.16** and **2026.11.17**, CI runs 2010 and 2011 green, as the
  close-out recorded); PR 3 #1462 at 11:47 UTC on 2026-11-13, CI run 2014
  green on `ae06fd9`, release **2026.11.18**. #1462's keyword closed
  #1450. `main` is at `ae06fd9`, unmoved since.
- **The open-issue list of 2026-11-15:** 33 open: 13 `agentic` (#1460,
  #1457, #1456 to #1451, #1396, #1070, #900, #899, and #1220 with
  `needs-decision`), 1 `needs-decision` (#1177), 2 `needs-uat` (#328,
  #354), 17 trackers (11 polish lists #1355 to #1366 without #1364;
  #991; the five area trackers #416 to #420). One Dependabot PR is open:
  #1463.
- **The polish lists' open lines on 2026-11-15:** API and MCP (#1356) 26,
  Securities (#1365) 15, Wealth (#1366) 13, Shell (#1357) 11, Imports
  (#1355) 10, History (#1360) 9, Cash flow (#1359), Accounts (#1361) and
  Merge pages (#1363) 5 each, Overview (#1358) and Classifications
  (#1362) 3 each: 105 in all.
- **Read against the code on `ae06fd9`**, each claim this plan rests on:
  - `app.css` names `Inter` first in `--font-sans` (line 3) and has no
    `@font-face`; `priv/static/` holds no font; the endpoint's
    `Plug.Static` serves only `apple-touch-icon.png app.css favicon.ico
    favicon.svg images theme-boot.js` (`endpoint.ex` 64); the CSP already
    says `font-src 'self'` (`content_security_policy.ex` 76). The CSS uses
    the weights 400, 500, 600, 650, 680, 700, 740 and 760. Hence F1 and a
    variable font.
  - `test/browser/fonts.js` fails a walk unless Inter and DejaVu Sans are
    installed on the machine; CI installs both (Sprint 29, #1461). Hence
    F1's change to the walks and the `AGENTS.md` fact it corrects.
  - The shared line chart (`security_chart.ex`) spans its axis from the
    padded lowest value to the highest (`pad_range/2`, `axis_floor/4`,
    586 to 593), a price axis never below 0; the stacked chart
    (`stacked_chart.ex`) starts at 0 with round steps. Neither draws a mark
    where the axis does not start at 0. Hence W1.
  - **The gettext resolver exists**: `scripts/merge_gettext.py`, since
    Sprint 22, with its section "Integrating gettext catalogues" in
    `docs/development/guide.md` and the merge-driver lines to register;
    the driver is not registered in a fresh checkout (`git config --get
    merge.gettext.driver` answers nothing here). Sprint 29's
    retrospective says the resolver "lived in the session's scratch, not
    in the repository": the session wrote a second one because nothing
    registered the first. Hence M3, and this line as the correction of
    carry-forward 3's fact.
  - The four sweeps Sprint 29's carry-forward 1 names live outside
    `test/invariants` and carry no tag a story agent could select them by.
    Hence M2 and D-9.
  - `News.Ingest` holds the feed row and then inserts items referencing
    the matched security; `News.reassign_feeds` (a security merge) holds
    the securities and then the feeds (#1457, unreproduced). Hence K1.
- **Boards:** three, drawn for this PR (D-6, D-7), on the shipped
  `app.css`, every series and name the review seed's.

## State of play, in five lines

1. **Sprint 29 is on `main`** (releases 2026.11.16 to 2026.11.18): the
   crash rankings, the news layer's first-fill fixes, the layout gate, the
   Bitcoin cycles.
2. **The layout gate measures two fonts** because the app ships none: an
   operator without Inter sees every bar in a fallback (#1221, which the
   Shell list says to do "first in any polish pass").
3. **105 polish lines** wait on ten lists; Sprint 29 added 15, and three
   lists hold over half of them.
4. **Two S2s from Sprint 29 are open**: a suspected deadlock between a
   news fetch and a security merge (#1457), and a flaky scheduler test
   (#1460); a third flaky test sits on the Shell list as an S2 line.
5. **I43 is the next deep idea** (Sprint 29 plan D-9), boarded here;
   **I32 joined the sprint** on 2026-11-15 at your word, worked out here
   as ADR-0061.

## Why this cut

- **I32, because you asked for it** (D-12), on machinery that exists:
  `WindowReturn` for the price side, ADR-0051's contribution for the
  money side, ADR-0058's ranking and tie order.
- **Otherwise no new feature, because the last three sprints were the
  largest the project has run** (Sprint 29: three stacked PRs, about 160 commits, four
  introduced S1s, all fixed) and every one left polish lines behind.
  Polish is kept, not closed away (ADR-0026, amendment of 2026-11-01): a
  planned pass takes one screen as one test-first story.
- **The font first**, because the layout gate and every width floor
  depend on it, and Sprint 29's carry-forward 4 asked this plan to weigh
  it: SIL OFL 1.1 permits bundling with the MIT-licensed app if the
  licence travels with the files; a variable font covers every weight the
  CSS uses in one file per subset (board 03 states the bytes).
- **I43, because it is the planned deep idea** and the confusion it
  settles came from your screenshots; W1 builds the board's answer.
- **Wealth, Shell, API and MCP as the passes**: Wealth because W1 touches
  its chart and most of Sprint 29's new lines are on it; Shell because
  F1 is its first line; API and MCP because it is the longest list and
  the agent is the second first-class user (and I45 is one of its lines).
- **#1457 and the flaky tests**, because an S2 the diff's code reaches is
  filed and fixed, and a flaky test trains everyone to ignore red.
- **What is left out, and why** (each flips by naming it): #1270, #1288,
  the risk read's `truncated`, the unreviewed list's count, the split
  ratio's 34th digit and the cascading deletes' `expect=` on #1356 (each
  needs a decision or is money math, A3's table); #1263 and the layout
  walk's blind spots on #1357 (F2's table); the polish lists not named;
  #1396, #899, #900, #1070, #1220, #1177, #328, #354 and #1451 to #1456
  keep their standing reasons (D-11).

## Lanes (one sprint PR, in this order: M, K, F, A, T, W)

**Lane M, maintenance and the build's own tools (first).**

| Story | Source | What it does | Commits |
|---|---|---|---|
| M1 | standing rule; #1463 | the version report `version-report-2026-11-…-sprint30.md`: Hex, npm (Playwright 1.65.0 in `test/browser`, #1463), Elixir/OTP, PostgreSQL, BMAD core and the external modules, each bump its own commit, what is declined with its reason | 1–3 |
| M2 | Sprint 29 retrospective, carry-forward 1 | **the project-wide sweeps carry one tag.** `@moduletag :sweep` on `localization_test.exs`, `input/text_sweep_test.exs`, `input/bounded_date_sweep_test.exs`, `field_label_test.exs` and every other test module that walks every route, template, schema or `lib/**` file (found by search, each named in the commit); an invariant asserts that a test reading `Path.wildcard("lib/**` or the router's routes carries the tag, with its attack case (an untagged copy, seen refused). `mix test test/invariants` and `mix test --only sweep` are then what a story agent runs (D-9) | 1 |
| M3 | Sprint 29 retrospective, carry-forward 3 | **the gettext merge driver is registered where every worktree starts**: `scripts/worktree.sh add` registers `merge.gettext.*` and the two `info/attributes` lines when absent (idempotent, local config only, as the guide's section says), `scripts/test_worktree.py` pins it; the guide says the helper does it | 1 |
| M4 | #1460 (S2, flaky) | **the cause first:** measure where the healthy feed spends its 2 s under `--max-cases` load (recorded in the commit), then a deadline per feed or a test that does not share the wall clock; a red loaded run seen first. **No deadline widened** without the measurement (sprint workflow, "a time bound is loosened only after its cause is found") | 1 |
| M5 | #1357's S2 line, filed as its own issue after the merge | `cascade_removals_test.exs` (line 68) times out at 60 s under load waiting on the file server in `Path.wildcard("lib/**/*.ex")`: the file list read once per module, not per test, or at compile time; a red loaded run seen first; the 60 s not raised | 1 |
| M6 | I34's step 2 (Sprint 29 plan D-9) | **the measurement step 2 is planned with**, no code: the Wealth chart's first paint and each period switch on the review seed, cold and with the memo warm, per period and level, written to `perf-2026-11-…-wealth-chart.md` with how it was measured | 1 |

**Lane K, one lock order** (#1457). **Risk tier: stored data** (a
deadlock aborts a merge or a fetch; a wrong fix could interleave a merge's
reassignment with a fetch's insert): its own commit group, a dedicated
verification pass, a callout in the briefing.

| Story | Source | What it does | Commits |
|---|---|---|---|
| K1 | #1457; ADR-0056 D4's lock order | a race test under `test/portfolixir/lock_race/` that parks a fetch after its feed lock and a merge after its security locks, each then asking for the other's rows: **red first** (`40P01`, or the test's own deadline). The fix registers one order in `test/support/lock_table.ex` and both paths take it (the merge's `reassign_feeds` locks the feed rows in the same order the fetch does, or the fetch takes the security rows before its feed, whichever the lock table's existing orders already imply; the commit names which and why). 50 loaded runs green | 2 |

**Lane F, the shipped font and the Shell polish pass** (#1221, #1357).

| Story | Source | What it does | Board | Commits |
|---|---|---|---|---|
| F1 | #1221; Sprint 29 retrospective, carry-forward 4 | **the app ships Inter.** The variable font (wght 100–900), latin and latin-ext subsets as woff2 under `priv/static/fonts/` with `OFL.txt` beside them, from a pinned upstream release named in the commit with its checksum; `@font-face` in `app.css` with `font-display: swap` and `unicode-range`; `Plug.Static` serves `fonts`; long cache headers as the other static files have. The walks: `fonts.js` checks that the page loaded **its own** Inter (`document.fonts`) and that DejaVu Sans is installed for the fallback measurement, which stays (a font file that fails to load is a real state, and no gate is weakened); CI's apt step then needs only `fonts-dejavu-core`, and `AGENTS.md`'s fact line changes with it (the maintenance lane's correction, with its evidence). A browser test with the font file blocked shows the page in the fallback, connected. **No `fonts.googleapis` or any outbound request**; the CSP stays `font-src 'self'` | 03 | 2 |
| F2 | #1357, a planned polish pass | **the Shell list, one functional test per line, each written first and seen failing for its line's reason:** #1256 (a live page's crash report prints no handler arguments or form values), #1262 (a swapped `token=name` entry never echoes the token as the name), #1264 (the handbook line on the login lifetime, English and German, the owner's recommended answer), #1302 (the unused `.chart rect` rule removed, the static check that finds it), #1319 (EXPERIENCE.md reads "an explicit sign (the house hyphen-minus)"; `Format` stays), `LinkDomain.of/1`'s dead branch, the digest cursor's database-wide lock replaced by one per consumer key. Each line ticked with its commit | — (no rendered change but #1302, which removes a rule nothing renders) | 2–3 |

Left on #1357, with the reason: #1263 (a password guess through LiveView
mounts on the run-from-source route needs a throttle design for the
socket, not a polish fix); the layout walk's three blind spots (a gate
widening, which gets its own attack lens before integration, Sprint 29's
carry-forward 6; best after F1, since it changes what the walks measure).

**Lane A, the API and MCP polish pass, I45 first** (#1356).

| Story | Source | What it does | Commits |
|---|---|---|---|
| A1 | I45 (a `no-brainer`, D-10); #1356's line | **`crashes.rankings` answers slim by default**: rows without the per-entry close blocks and without `benchmark_return` repeated per entry, `benchmark` once; `projection=full` returns today's answer **byte for byte** (a test compares it with a fixture captured before the change, seen identical); the basis states the projection; contract entry 30's A part; the MCP description and its schema budget (the read must shrink); the docs | 2 |
| A2 | #1356, the news lines | names whose first 19 characters agree read apart wherever a news answer cuts them (`news.list`, `news.digest`, `news.unlabeled`: the cut name and the ticker, or the WKN where there is no ticker); a feed deleted and registered again under the same URL does not store its items twice (the item identity does not include the feed row); `news.get`'s `note_ids` capped with `truncated`; `news.digest`'s "max 32" says it counts consumers; a refused redirect names the refused hop's host, normalized; ADR-0056 §5's wording follows the code ("refuses every fetch", a wording fix in the ADR's own text, no rule changes) and `news/health` shows `failures` and `retry_at`; `News.Promotion`'s unreachable fallback and its two 422s removed | 3 |
| A3 | #1356, the rest it takes | #951 (`maxLength` on the G02 free-text fields), #1258 (the reconcile cap's sentence), the three unique tie-breaks (`notes/unreviewed`, a security's quotes, the manual-quotes stretches), the costs test's wrong comment, a bound on `rate:`'s exponent at parse (both reads then echo a short rate), the companion token's 401 names which token the route expects (echoing nothing sent), `PATCH /securities/:id` with a field outside its wrapper answers 422 as the news writes do, `Settings.put_journaled/3`'s first-write race under the advisory lock `set_crash_benchmark` took, the Yahoo, ECB and logo adapters stop merging a caller's `req:` options | 3 |
| A4 | #1356's line; risk tier stored data | `transactions.taxes` gains its database CHECK (≥ 0) beside the changeset's: the migration counts violating rows first and **refuses to run while any exists** (none can, since the changeset refuses them; the migration names them if it finds one, and changes no row) | 1 |

Left on #1356, with the reason: #1270 (the journal read's filter by a
principal's name needs the name a token carries, ADR-0045's to say);
#1288 (which portfolio becomes the default is a rule, checked against
its ADR first); the risk read's `truncated` (a family decision for every
top-N section); `notes/unreviewed`'s count (ADR-0044 §7's to decide);
`QuoteAdjustment.divide_by_ratio`'s 34th digit (money math, a risk-tier
story of its own); the cascading deletes' `expect=` (a new write
contract over API and MCP, a story of its own with its recommended
answer on the line).

**Lane T, tops and flops per period** (FR-59, idea I32; ADR-0061; board
04). **Risk tier: money math** (a new derivation over `WindowReturn` and
ADR-0051's contribution: the windows, the split into halves, the money
side's `day`): its own commit group, a dedicated verification pass with
every pinned figure recomputed independently in exact decimal, a callout
in the briefing.

| Story | Source | What it does | Board | Commits |
|---|---|---|---|---|
| T1 | ADR-0061 §2 to §6 | **the read**, `Portfolios.Movers` (or the name the context's conventions give): the windows of §3 with their start days (a Monday, a month's first day, 1 January, 29 February, a quarter's first day each pinned), the price side by `WindowReturn` over the scope's securities held at `T`, `day` per security, the money side by ADR-0051's view and total reads over `S + 1` to `T` and `day`'s `D`, the halves without overlap (n = 0, 1, 6, 11), ties by ADR-0058 G1's full order, the unanswered reasons, the basis. Tests first with exact `Decimal`s; **a security's `week` here equals sale hindsight's `WindowReturn` over the same dates to the last digit, and a position's contribution equals Wealth's table for the same custom window** | — | 3 |
| T2 | ADR-0061 §9 | `GET /api/v1/views/:view_id/movers` and `GET /api/v1/movers`, an unknown `window` or field refused with 422 naming it; `portfolixir.views.movers` with its description and schema budget; contract entry 30's T part; `metrics_carry_no_verdict_test.exs` walks the payload; the docs (English and German) | — | 2 |
| T3 | ADR-0061 §9; board 04 A | **the Overview's card „Tops und Flops“**: the window chips on the shared control bar, the two columns, „verkauft“, the unanswered count, the basis line with its ⓘ, the links (the security; „In Vermögen ansehen“ with the window as a custom range), stacked under 560 px (A1), the privacy mode as board 04 ④ draws it; loaded in the background like the Overview's other cards, with its busy marker; **every figure on the card compared with the API's answer for the same window** in the test; `DESIGN.md` gains the anatomy | 04 | 2–3 |

**Lane W, Wealth: where the axis starts, and the Wealth polish pass**
(I43; #1366). Both change rendered output, so both are boarded here.

| Story | Source | What it does | Board | Commits |
|---|---|---|---|---|
| W1 | I43, worked out on board 01 (D-6) | **the axis says where it starts.** The shared line chart draws an axis-break mark at the axis' foot wherever its axis does not start at 0, on Wealth and on a security's chart; on Wealth's Total in „Wert“, the control bar gains „Achse: Ausschnitt · ab 0“, remembered in the address (`axis=zero`, dropped when it is the default), absent in „% (TTWROR)“ and in the privacy mode's percent axis. **„ab 0“ draws the line exactly where the stack's top edge is at Kategorien** for the same window (a test compares the two charts' points per day). `DESIGN.md` gains the anatomy; the API is not touched (an axis is not a figure), so no MCP change; the PR says so | 01 | 2–3 |
| W2 | #1366, a planned polish pass | **the Wealth list, one functional test per line, each written first and seen failing:** the holdings notes and the Depot column at 1200 px (board 02 ①), the stacked chart's axis values outside the plot (②), one tick below zero for a negative cash day (③), the Allocation tab's TTWROR figure busy while it loads (④), the touch tooltip that stays after a tap, `sync_rates`' server-side guard, the Crashes windows table at 390 px as rows (⑤), „Im Depot ansehen“ keeping `view`, the Risk page without a portfolio reaching the catalogue's lists (⑥), the names hint's two causes and the names table at 1200 px (⑦), the no-price link's `holding=held`, the test FX key on a moving date | 02 | 3 |

## Decisions

### D-1: what this sprint is for, and its exit criteria (recommended)

The sprint adds tops and flops per period (FR-59), leaves the app
reading the same on every machine, answers the axis question, and
empties three polish lists of what they can lose without a decision. Exit criteria:

1. **Every page draws in the app's own Inter on a machine without Inter
   installed**, and with the font file blocked the page draws in the
   fallback and connects; the walks still measure the fallback; no request
   leaves for a font.
2. **The axis says where it starts**: the mark is drawn wherever an axis
   does not start at 0 and nowhere else; at „ab 0“ the Total line meets the
   stack's top edge at Kategorien day by day; the default picture at Total
   is today's, plus the mark.
3. **Every polish line a pass takes is pinned by a test seen failing for
   its reason** and ticked on its list with its commit; a line found to be
   S1 or S2 is filed instead.
4. **A news fetch and a security merge take one lock order**: K1's race
   test red before, green on 50 loaded runs after.
5. **`crashes.rankings` is slim by default and today's answer under
   `projection=full`**, byte for byte; the read's schema bytes shrink.
6. **#1460's and the cascade test's flakiness is gone at its cause**: 20
   loaded runs of each green, no bound moved.
7. **Tops and flops reproduce** (FR-59): the price side equals
   `WindowReturn` for the same dates, the money side equals ADR-0051's
   read for the same window, no name is in both halves, every figure on
   the card equals the API's, and no payload carries a verdict key.
8. **Every gate by registration; regressions counted, none an S1 at
   promotion.**

### D-2: one feature, otherwise consolidation (your decision, with the plan's recommendation)

**A consolidation sprint with one feature, I32** (D-12), as you decided on
2026-11-15; the planning PR first proposed none. *Why the rest stays
consolidation:* Sprints 27 to 29 left 27 of their own findings as
polish lines (3, 9 and 15) beside the older ones they recorded, the
layout gate rests on a font the app does not ship, and a sprint of passes is reviewed against boards and lists, not against new
decisions, so it costs your attention little.

### D-3: the order of the work (recommended)

M first (M2 and M3 change how every later story is run and integrated),
then K (risk tier, small, before anything touches `news.ex`), then F (F1
changes what every walk measures, so T's and W's walks run on it), then
A, then T (risk tier, after A1 settled the rankings' projection pattern),
then W. Parallel story agents as in Sprint 29, each in its own worktree
from `scripts/worktree.sh` (now with the merge driver) and its own test
database: A, T and W may be built beside each other once F1 is
integrated, each rebased onto the branch before it; T1 gets its attack
lens before integration (D-5 item 5).

### D-4: Inter, as shipped (recommended)

The variable font in latin and latin-ext subsets (board 03 A), not static
weights (B): the CSS uses eight weights (KPI values 700, labels 650, table
headers 740, the brand 760), and B would draw 650, 740 and 760 as 700.
Drawing the board also found that **B is not even smaller**: the variable
font measures 47.1 KiB in latin and 83.1 KiB in latin-ext (130.2 KiB for
both), the static 400/600/700 set 70.8 and 105.0 KiB (`@fontsource-variable/inter`
and `@fontsource/inter` 5.3.0, as measured on the board). ⓘ, ≈ and → are
in neither subset and keep coming from the next font in the stack, as
today. In DejaVu Sans the positions table at 1200 px is 940 px in a 922 px
wrapper today (#1322 comes back in the fallback); in Inter it fits, one
more reason the font ships. `font-display: swap`, so a slow file never
hides text. The licence file ships beside the fonts and the docs' third-
party notice names it. The fallback stack after Inter stays as it is.
**JetBrains Mono** (`--font-mono`) is not shipped: it sets code and the
journal's raw values only, where no width floor is measured. **To flip:**
"Inter statisch" (B); "Schrift nicht ausliefern" drops F1, and the walks
keep requiring Inter on the machine.

### D-5: the closing act and the build (standing, with Sprint 29's carry-forwards)

Each lens reviews the PR's diff and reports at most five findings, ranked
by severity. The story workflow's section "What a story's own tests do
not cover" applies to every story, **with D-9's two added rules**.
Sprint 29's carry-forwards, applied:

1. **The sweeps beside the story's own tests**: M2 tags them; every story
   brief says `mix test test/invariants` and `mix test --only sweep`.
2. **Never stop a process by pattern**: every story brief says so (D-9).
3. **One gettext resolver at every integration**: M3 registers the one
   the repository has had since Sprint 22.
4. **The font is weighed and shipped**: F1 (D-4).
5. **The attack lens before integration, kept, and pointed again in the
   closing act at the same stories**: K1 (an agent other than its author
   tries a third path into the two rows, a merge of two securities that
   share a feed, a fetch of a feed the merge is moving), A4's migration
   (a violating row planted before it runs) and T1 (a window across a
   split, a 29 February, a Monday before the shares' closes, a security
   bought and sold inside the window, ties across every key, n = 1).
6. **A new gate gets its attack lens before it is integrated**: M2's
   invariant and F1's changed font check, each with its attack case.

Lenses for this PR: correctness; the money lens (T1, every pinned figure
recomputed in Python's `decimal` at the app's 34 digits); edge cases and
order (K1, A2, M4, M5, T1);
security (F1's static path and headers, F2's #1256 and #1262, A3's 401
and adapters); the agent's lens (A1 to A3 against the companion's
descriptions and the schema budget); the design critic against boards 01
to 04 and `DESIGN.md`; the UAT persona on the review seed at the end, on
a machine **without** Inter installed (D-1 criterion 1). A closing-act fix
that changes what a screen shows gets its frame on this sprint's board
folder first. The browser job runs locally before the closing act on the
integrated head. GitHub writes go through the MCP tools. This planning PR
carries no closing keyword (checked before it was opened); the sprint PR
names `Closes` for #1457, #1460, the cascade test's issue and FR-59's
issue (both filed after this merge); #1221 and the other polish lines' issues are already
closed as their lists' specifications, so their lines are ticked, not
closed; the polish lists stay open while they have lines.

### D-6: board 01, where the axis starts (I43; recommended)

Board 01 draws today (①), A the mark only (②), B the switch only (③), C
both (④, **recommended**), C at 390 px (⑤) and C in the privacy mode (⑥).
**C:** on Wealth's Total in „Wert“ the control bar carries „Achse:
Ausschnitt · ab 0“, default „Ausschnitt“ (today's picture, byte for byte,
plus the mark), remembered in the address like the level; wherever the
axis does not start at 0 the axis carries a break mark; the security
page's price chart takes the mark only. *Why:* the mark alone says the
axis is cut but leaves the comparison with the stack to the reader's head;
the switch alone fixes Wealth but leaves the security chart silent; a
stack cut above zero would show shares wrongly (I43's row), so the switch
is the line's, never the stack's. **To flip:** "I43 nur Markierung" (A),
"I43 nur Schalter" (B), "I43 Standard ab 0" (the switch defaults to
„ab 0“).

### D-7: boards 02 and 03 (recommended)

- **Board 02 (Wealth):** each line's before and after as listed in W2;
  ① A (the note's first phrase non-breaking, the note spanning under its
  figure cell, the Depot cell on one line with an ellipsis past 7rem, the
  name column's floor lowered from 12rem to 9.5rem) is recommended over B
  (the note behind an ⓘ on the figure): A brings the six noted rows from
  64–99 px to 49 px and the table to 922 px in 922, B still needs 932 px,
  and the note says why a figure is not in the sum, so it should stay
  visible. Without the lower name floor a one-line Depot makes the table
  956 px; the board says so. **To flip ①:** "Notiz hinter ⓘ" (B).
  ② widens the stacked chart's gutter from 56 to 88 viewBox units (33 to
  51 px at a 560 px chart; the values stay outside down to about 492 px).
  ⑦ splits „Namen ohne Fenster“ into one table per reason (changed
  closes; hidden because another crash benchmark is chosen), each fitting
  922 px; the wording is the board's. ③'s negative cash day and ⑤ to ⑦'s
  crash windows are drawn by hand on the seed's figures (the seed has no
  negative cash day and no crash benchmark), each frame labelled so; W2
  adds the two cases to the review seed so its tests and the UAT persona
  meet them. The other frames are conformance repairs (before and after,
  no choice).
- **Board 03 (the font):** the Overview's KPI strip, the holdings table at
  1200 px and Transaktionen's filter bar at 390 px, each in DejaVu Sans
  (today, without Inter installed) and in the shipped Inter; A
  recommended, D-4.

### D-8: one sprint PR, a cut prepared (recommended)

About 78 commits: Lane M 6 to 8, K 2, F 4 to 5, A 9, T 7 to 8, W 5 to 6,
the closing act's fixes about 32 (counted by its lenses, as Sprint 29's
PRs ran at about one fix per build commit), the UAT persona 2, the
close-out 4. Under the stacking threshold of about 90, so one PR. **The
cut is prepared after Lane A:** if the build passes 70 before the closing
act, the session stacks T and W with their closing act as `<its
branch>-pr2`, as `AGENTS.md` allows, so the risk-tier money math gets a
PR of its own, and says so in the PR's body.

### D-9: two rules added to the story workflow, signed here

The story workflow's section "What a story's own tests do not cover"
gains two rules on this PR (Sprint 29's carry-forwards 1 and 2), changed
only through this reviewed plan, as `AGENTS.md` asks:

- its first rule widens: **run `test/invariants` and the project-wide
  sweeps beside the story's own tests**, the sweeps by the tag M2 adds
  (until M2 lands, by the four files the rule names);
- a new rule: **stop only what you started, by its process id**, never
  by a pattern (`pkill -f`, `killall`).

**To flip:** "Regeln nicht ändern" removes the two edits from this PR; the
story briefs then carry them for this sprint alone.

### D-10: the ideas (the sprint workflow's "Ideas")

- **I43 goes deep in this session, on board 01** (Sprint 29 plan D-9):
  its row becomes `worked-out` with the board's recommendation, then a
  pointer to an issue under #418 filed after this merge, and `planned`
  with W1.
- **I45 is triaged a `no-brainer`** (one obvious answer, the pattern
  `securities.list` already has, inside scope, no money semantics) and
  planned as A1.
- **I34's step 2** is measured in M6 and planned with its numbers in
  Sprint 31.
- **I32 leaves the list**: worked out in this session as ADR-0061 and
  board 04, built as Lane T (D-12); its row becomes a pointer to FR-59.
- **The next idea to go deep is I20** (usage hints in the MCP companion),
  first in the list's recommended order.
- **I44** stays behind I43, as its row says: once the axes read the same,
  the drag is weighed again.

### D-11: what stays open, and why (standing)

#899, #900, #1070 and #1220 keep Sprint 22's reasons. #1177 waits for its
trigger. #328 and #354 wait for your check on real data. #1396 waits until
the sample can carry the split (ADR-0055 §9). #1451 to #1456 are the
asks ADR-0059 and ADR-0060 deferred, each waiting for its own decision or
a second chain source. The polish lists stay open while they have lines;
a story that touches a screen fixes its lines.

### D-12: I32 in this sprint, as ADR-0061 and board 04 (your decision; its shape recommended)

You put I32 into Sprint 30 on 2026-11-15. ADR-0061 decides its shape:
both rankings side by side, price return first (§1, the plan's
recommendation on the idea's one open question); the scope a view or
everything, the price side over today's holdings, the money side over
every position ADR-0051 lists (§2); six to-date windows, „Tag“ per
security on the price side (§3); the halves never sharing a name, ties by
ADR-0058 G1 (§4); the basis in every payload (§5); no verdict key (§7);
derived at every read (§8). **Board 04** draws the Overview's card (A,
recommended, stacked under 560 px, A1) against a section on Wealth's
Performance tab (B), the privacy mode and the states (fewer than ten held,
an empty view, a weekend's „Tag“). *Why the Overview:* it is the glance
the idea asks for, and Wealth's Performance tab has none of the short
windows and already ranks money in its contribution table. **To flip:**
ADR-0061's table; "Tops/Flops auf Vermögen" (B); "Tops/Flops umschaltbar
am Handy" (A2); "I32 nicht in Sprint 30" removes Lane T, ADR-0061 and
board 04 from this PR.

## Registry bookkeeping after the merge (the planning session's last step)

- File FR-59's issue under #418 (I32), pointing at ADR-0061, board 04
  and this plan's D-12; FR-59's coverage row in `epics.md` gains its
  number.
- File I43's issue under #418 (FR-53's chart, the board's answer C),
  pointing at board 01 and this plan's D-6.
- File the cascade test's flake (#1357's S2 line) as its own issue under
  #420, and turn the line into a pointer to it.
- No other closures by hand; no relabels.

## Checklist (the implementation session ticks it on the PR)

- [ ] Lane M: M1 the version report (#1463), M2 the sweep tag, M3 the
      merge driver, M4 #1460, M5 the cascade test, M6 the measurement
- [ ] Lane K: K1 the lock order (#1457), its attack lens before
      integration
- [ ] Lane F: F1 the shipped Inter (#1221), F2 the Shell pass (#1357)
- [ ] Lane A: A1 the slim rankings (I45), A2 the news lines, A3 the rest,
      A4 the taxes CHECK (#1356)
- [ ] Lane T: T1 the read, its attack lens before integration, T2 the
      routes and the tool, T3 the Overview's card (FR-59)
- [ ] Lane W: W1 the axis (I43), W2 the Wealth pass (#1366)
- [ ] Closing act: the lenses, the fixes, the re-check, the UAT persona
      without Inter installed
- [ ] Close-out, retrospective, briefing, promotion
