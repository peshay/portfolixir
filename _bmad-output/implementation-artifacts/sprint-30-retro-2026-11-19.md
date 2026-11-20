# Sprint 30 Retrospective — tops and flops, the shipped Inter, where the axis starts, three polish passes and one lock order (2026-11-19)

ADR-0026 step 5 for Sprint 30, written by the implementation session as the
last commits of the sprint PR (sprint workflow §5). The plan,
`sprint-plan-2026-11-15-sprint30.md`, was adopted by the merge of its
planning PR, which signed ADR-0061 (FR-59, idea I32), the four planning
boards of `ux-design-2026-11-15-sprint30` and the story workflow's two
added rules (D-9). The close-out entry with every criterion and count is
in `sprint-status.yaml`; this file keeps what the sprint teaches.

## What shipped

One sprint PR, as the plan's D-8 decided, built by one implementation
session with parallel story agents:

| PR | Lanes | Commits (plan) | Closes | State at this record |
|---|---|---|---|---|
| #1471 | M, K, F, A, T, W, the closing act, the UAT persona, the close-out | 75 on `main`'s `8ec5723` after the history cleanup (every fixup folded into its commit), against the plan's about 78 | #1457, #1460, #1465, #1466, #1467, #1472 | draft, not merged |

The build reached 47 commits before the lenses' first fix, under D-8's
cut of 70, so the cut prepared after Lane A was not taken.

- **Lane M:** M1, the version report `version-report-2026-11-19-sprint30.md`:
  Playwright 1.65.0 in `test/browser` (Dependabot #1463), PostgreSQL 18.7
  in Compose and CI (its security release, 99 CVEs), `sobelow` 0.19.0;
  bandit 1.15.0 and Playwright 1.65.1 declined with their reasons, #1392
  closable. M2, the project-wide sweeps carry `@moduletag :sweep` (twenty
  modules), held by `test/invariants/sweep_tag_test.exs`. M3, the worktree
  helper registers the gettext merge driver. M4, #1460's flaky scheduler
  test at its cause (a cold VM's code server, then a shared sandbox
  connection), 20 of 20 loaded runs green. M5, the cascade test reads `lib`
  at compile time (#1467), 20 of 20 loaded runs green. M6, the Wealth
  chart's first paint and period switch measured, `perf-2026-11-19-wealth-chart.md`.
- **Lane K, one lock order** (#1457; risk tier stored data): a fetch takes
  its feed's security (or category) before the feed; K1's attack lens found
  two more cycles (a feed's re-binding, the matcher) that K2 closed with the
  same order. The closing act's order lens added a promotion and a label
  write. Lock table rows 23, 25 and 26.
- **Lane F:** F1, the app ships Inter (variable, latin and latin-ext, normal
  and italic, `@fontsource-variable/inter` 5.3.0 by checksum, `OFL.txt`
  beside it, `?vsn=5.3.0` long-cached); the walks require the page's own
  Inter, CI installs only DejaVu Sans, `AGENTS.md`'s fact line corrected.
  F2, the Shell list: #1256, #1262, #1264, #1302, #1319 and
  `LinkDomain.of/1`'s dead branch, each pinned by a test seen failing.
- **Lane A** (#1356): A1, `crashes.rankings` slim by default,
  `projection=full` byte for byte (I45); A2, the news lines; A3, the rest
  the list could lose without a decision (#951's `maxLength`, #1258, the
  tie-breaks, `rate:`'s exponent, the 401's expected token, the closed
  security PATCH, `put_journaled`'s first-write race, the adapters' `req:`);
  A4, the database refuses negative taxes, the migration refusing while any
  row violates.
- **Lane T, tops and flops per calendar window** (FR-59, #1465; risk tier
  money math): T1, `Performance.Movers.read/3` with its attack lens before
  integration; T2, `GET /api/v1/views/:view_id/movers`, `GET /api/v1/movers`
  and `portfolixir.views.movers`; T3, the Overview's card „Tops und Flops“.
- **Lane W:** W1, the axis says where it starts (I43, #1466): the
  axis-break mark on the shared line chart, „Achse: Ausschnitt · ab 0“ on
  Wealth's Total. W2, the Wealth list (#1366), twelve lines and the review
  seed's step 25 (a negative cash day, a crash benchmark).
- **The closing act:** the lenses for correctness, money, order, security,
  the agent and design; the fixes test-first, each screen change boarded
  first (boards 05 and 06, frame 04i); the UAT persona on a machine without
  Inter.

## What went well

* **THE ATTACK LENS BEFORE INTEGRATION FOUND THE WORST FINDINGS AGAIN.**
  K1's lens found two deadlocks K1's own race module never tried (a feed's
  re-binding and the matcher, each against a merge), fixed by K2 before Lane
  K was integrated. T1's lens found #1472, an older S1: a position whose
  first close arrived on the window's first day read its whole value as its
  contribution, unmarked, at the top of „Höchste“. Both were found by a
  session that did not write the code, before any screen showed it
  (Sprint 29's carry-forward 5).
* **EVERY PINNED FIGURE WAS RECOMPUTED, NOT TRUSTED.** T1's tests, its
  attack lens and the money lens recomputed every expected figure in
  Python's `decimal` at 34 digits; a security's week equals sale
  hindsight's `WindowReturn` to the last digit, and each contribution
  equals Wealth's table term for term. The money lens's two findings came
  from that habit: a legacy close of 0 as #1472's second route (S1, older),
  and a sign claim in ADR-0061 §6.7 that a stale close's exchange rate
  breaks.
* **BOTH FLAKY TESTS WERE FIXED AT THEIR CAUSE, NO BOUND MOVED.** M4
  measured the healthy feed's 2 s under load (the code server releasing
  three cold requests at once, then a sandbox connection shared past the
  ownership proxy's poll) before it changed the test; M5 reproduced the
  cascade test's timeout with a file-server hammer, red at 60 s, and moved
  the scan to compile time. Twenty loaded runs of each are green.
* **A GATE EXCEPTION WAS REMOVED, NOT KEPT.** W2 excused the Crashes basis
  line from the open-prose rule (`crash-basis` in `control_bar.js`, up to
  40 words). The design critic shortened the copy to one sentence of at
  most 24 words and the exception was deleted; the walk is green without
  it.
* **THE CLOSING ACT DREW BEFORE IT FIXED.** CI's select finding got board
  05 before its fix, the design critic's three screen changes and the
  movers card's link got board 06 and frame 04i, each rendered in CI's
  headless shell with the shipped Inter (Sprint 28's carry-forward 3 held
  for the whole closing act).
* **THE FONT IS SHIPPED AND THE UAT PROVED IT WITHOUT INTER INSTALLED.**
  The persona ran in CI's headless shell under a fontconfig with no Inter:
  the page drew in its own Inter from `/fonts/`, in DejaVu Sans with
  `/fonts/*` blocked, connected both times, and no request left the app.
  Every figure on the screens matched the API.
* **THE SLIM DEFAULT SHRANK WHAT AN AGENT READS.** A1's default answer is
  25 % smaller for eight losers and 32 % for eight rebounders, the tool's
  schema 4 bytes smaller, and `projection=full` returns the old answer byte
  for byte against fixtures captured before the change.
* **ONE PR STAYED ONE PR.** The build stayed under D-8's cut, and the sprint
  ends well under GitHub's 100-commit limit.

## What did not go well

* **THE MACHINE WAS OVERLOADED BY PARALLEL AGENTS.** Story, lens and fix
  agents ran side by side on 4 CPUs; the load average reached 40 to 47.
  Agents' runs met their own time bounds (the privacy route walk at 58.2 s
  of 60, the matcher test at 15.17 s of 15), M6 had to wait for a quiet
  machine, and M4 and M5 measured under load the agents themselves made.
  No bound was moved for it, but each slow run cost a re-run and a
  judgement whether the PR had caused it.
* **THREE CI REDS THAT LOCAL RUNS DID NOT SHOW.**
  1. *The browser job:* CI runs Playwright 1.65.0's chromium-headless-shell
     (revision 1254), which lays the shipped Inter out in whole-pixel glyph
     advances; the session's walks ran a full Chrome, where the Crashes
     window's select fit by 3 px. In CI's shell it needed 332 px in 328.
     F1 and M1 each passed locally. The brief was changed to run the walks
     in CI's exact shell from then on.
  2. *The test job, a fix that broke an older rule:* the correctness lens's
     fix for the movers card's link added `view=` to it, which #1081's rule
     forbids on every Overview link (`dashboard_total_excluded_test.exs`).
     The fix agent ran its own files and the invariants, not the suite.
  3. *The test job, the database's collation:* the review seed drew its
     closes in the order the database sorts names; local test databases are
     C.UTF-8 and CI's en_US.utf8, so W2's crash benchmark detected a window
     locally and none in CI, in every CI run. Fixed by sorting in Elixir;
     the gap itself is filed as #1475.
* **THE LOCK-ORDER FIX INTRODUCED A REGRESSION.** K2's feed write took the
  feed's old and new category before the feed; a category's subtree delete
  takes them child first, so a re-binding from a parent to its child closed
  a new cycle. The order lens caught it (S2), and the write now takes only
  the category it binds. Two more cycles of the #1457 family (a promotion
  and a label write against a merge) were older and found only by the
  closing act, not by K1 or its attack lens.
* **D-1 CRITERION 2 FAILED UNTIL THE DESIGN CRITIC.** W1's test compared
  „ab 0“ with the stack on worlds with no band below zero; on the review
  seed's overdraft days the stack's floor sits one step below 0 and the
  line stood on another axis. The fix draws the line on the stack's axis.
  Its area fill still ran to the floor (the UAT's finding 2), fixed after
  the UAT.
* **A GATE WAS WEAKENED BY A STORY AND RESTORED BY A LENS.** W2's
  `crash-basis` exception (above) is the shape the gates forbid; it was
  caught, but by the design critic, not by the story's own review.
* **ONE PLANNED LINE WAS NOT DONE.** F2's digest cursor lock, one per
  consumer key instead of one database-wide, breaks the 32-consumer cap
  (an attack test with 34 consumers); the line stays on #1357 with that
  reason.
* **THE WORKTREE HELPER SHARES `deps` READ-WRITE.** `scripts/worktree.sh`
  links every worktree's `deps` to the main checkout's; a lane that fetched
  a dependency changed every other lane's. The brief worked around it with
  a copy on a lock mismatch; the helper does not prevent it.
* **A CONTAINER RESTART TOOK THE WORKTREES, AND A CHECK RAN IN THE MAIN
  CHECKOUT.** The session's container restarted near the end; the
  worktrees' directory was gone, and a background per-commit check whose
  `cd` into a vanished worktree failed went on with `;` and checked out
  commits in the main checkout. Nothing was lost (the branch ref and a
  backup ref held), but a script that walks commits now starts with
  `set -e` and a fresh worktree.
* **NOT EVERY COMMIT PROVES ITS INVARIANTS, ONLY THE TIP.** The sprint
  workflow asks a history rebuild to prove every commit's invariants. The
  lanes were built on different bases and integrated in another order, so
  some intermediate commits carry gettext templates whose source
  references a later commit refreshed (W2's Crashes commit among them),
  and the correctness lens's `view=` fix for the movers card fails
  `dashboard_total_excluded_test.exs` until the commit after it replaces
  it. Folding the two together or regenerating the templates at every
  commit was tried and abandoned: a reordered fold broke the catalogues of
  the commits between, and a regenerating rebase compiled incrementally
  and wrote a template without the movers card's entries. The tip passes
  every gate; `git bisect` across these commits should skip a gettext or
  that one dashboard failure. *Carry-forward:* integrate each lane's
  catalogue refresh into the lane's own last commit at integration time.

The re-check after the fixes verified each of the closing act's nineteen
fixes by mutation (its key line reverted, its test seen red, restored) and
ran every local gate on the integrated head: the full suite (7,101 tests,
0 failures), `dialyzer`, `credo`, `sobelow`, the companion's tests and
build, and `pre-commit`, all clean. It noted three S3 for the record
only: a task crash report's withheld arguments pinned by no test; the
movers basis's `gaps` text silent on a close of 0 or below (the contract
and the API docs say it); „ab 0“ reading the stack's axis without its
chosen tree.

## The regressions, counted apart

The sprint workflow §3 and ADR-0026's amendment of 2026-11-01: the
regressions this sprint introduced are counted apart from the older
findings it passed. Counted at this record, from the build agents' reports,
the lenses' findings and the UAT's README.

| | S1 | S2 | S3 | Fixed on the branch |
|---|---|---|---|---|
| The build and the integration (T1's tie order restated, not shared; T1's held benchmark ranked but untested; K2's matcher giving up after three attempts, untested and unreachable; the review seed's alias placement; the movers card's background read logging in the privacy walk) | 0 | 0 | 5 | 0 |
| CI (the Crashes select 4 px short in CI's headless shell; the review seed's closes in the database's collation; the movers link's `view=` breaking #1081's rule) | 0 | 1 | 2 | 3 |
| T1's attack lens (day `D` without an age bound; identical twins in both halves at n = 2; marked phantom gains filling „Höchste“, by ADR-0061 §4's rule) | 0 | 0 | 3 | 1 |
| The correctness lens (M2's sweep check blind to a piped, captured or attribute walk, F2's CSS check untagged; the movers link opening Wealth in another view; the merge driver's refusal dropping theirs' entries silently) | 0 | 2 | 1 | 3 |
| The security lens (a crash report's values on every terminate path but a socket message; a 32-character name that may be a token printed; the endpoint's comment naming `?vsn=<release>`) | 0 | 1 | 2 | 3 |
| The agent's lens (the movers basis nesting the table's; ADR-0061 §9's `view_id`; `news.health`'s past `retry_at`; ADR-0058 H1's wording) | 0 | 0 | 4 | 4 |
| The money lens (ADR-0061 §6 item 7's sign claim) | 0 | 0 | 1 | 1 |
| The order lens (K2's feed write against a category's subtree delete) | 0 | 1 | 0 | 1 |
| The design critic (at „ab 0“ the line off the stack's floor, D-1 criterion 2; contributions of 0,00 filling „Niedrigste“; the `crash-basis` exception and its copy; the positions table at 922.8 px in 922; frame 04i drawing `view=`) | 0 | 0 | 5 | 4 |
| The UAT persona („Tag“'s previous close without an age bound; „ab 0“'s area to the floor; the crash rankings' axis at 390 px; the names table at 390 px; the basis's catalogue clause under „Im Depot“; the selected phone row's padding) | 0 | 0 | 6 | 2 |
| **Introduced, total** | **0** | **5** | **29** | **22 of 34** |
| Older, fixed on the branch (#1472, an unvalued baseline day read as contribution, and its second route, a legacy close of 0 or below; a feed's re-binding and the matcher against a merge, from K1's lens; a promotion and a label write against a merge, from the order lens; the security search's `req:`; the „ggü.“ head's `nowrap` cascade) | 2 | 4 | 2 | 8 |
| Older, filed (#1470, a recluster and a merge may take clusters and items in opposite orders, suspected; #1474, the privacy route walk's breadth under load; #1475, the local and CI collations) | 0 | 3 | 0 | filed |
| Older, recorded as polish lines (fees, settlement and security amounts without a database CHECK; `news.list`'s standard fields with uncapped `note_ids`; a feed's tombstones deleted with it; `reassign_feeds` without a source check; three lib-scanning invariants slow under load; a changeset and a socket printed by two crash reports; the stacked chart's TTWROR basis test flaky under load; the days column's head with the same `nowrap` cascade; „4,00 %“ breaking in the positions table) | 0 | 0 | 10 | recorded |

The two UAT fixes counted above (the area fill at „ab 0“, the basis's
universe clause) land in the batch after the UAT persona's commit; the
other 19 are on the branch at this record.

**No introduced S1.** The two older S1s are fixed on the branch: #1472 by
T1's attack lens, its second route by the money lens; the walk's own
reading of a close of 0 or below as a price is a decision, filed as #1473
(`needs-decision`), not a defect count. The twelve introduced findings not
fixed are all S3, each a polish line: #1356 (T1's tie order restated; the
held benchmark ranked untested; the matcher's give-up untested), #1357 (the
review seed's alias; a 32-character name
accepted silently, SEC-2's remainder, with its choice), #1358 (the privacy
walk's log noise from the card's read; twins in both halves; marked phantom
gains in „Höchste“ and „Tag“'s unbounded previous close, both with an
ADR-0061 question), #1366 (the positions table at 922.8 px, with the
critic's recommendation; the rankings' axis, the names table and the
selected row's padding at 390 px).

**Not counted**, because they are process findings and not defects in the
product: CI's headless shell measuring otherwise than the local browser
(the brief now runs CI's shell); the worktree helper's shared `deps`; the
machine's load. **Watched, not counted** until a run fails on it: the
matcher test at 15.17 s against its 15 s under a load average of 40.
Nothing is withheld to make a count.

## Exit criteria (D-1)

| # | Criterion | Verdict | Evidence |
|---|---|---|---|
| 1 | Every page draws in the app's own Inter without Inter installed; blocked, the fallback connects; the walks measure the fallback; no request leaves for a font | **PASS** | F1, `shipped_font_test.exs`, `no_external_font_host_test.exs`; CI installs only DejaVu Sans and `ci_test.exs` refutes `fonts-inter`; the UAT's font check in CI's headless shell under a fontconfig without Inter |
| 2 | The mark wherever an axis does not start at 0 and nowhere else; at „ab 0“ the Total line meets the stack's top edge day by day; the default picture is today's plus the mark | **PASS** after the design fix | W1's tests; the design critic found the line off the stack's floor on a window with a band below 0, fixed (the line on the stack's axis, day by day, the band's depth on the overdraft days); the UAT: the edge on 364 of 366 days and exactly the overdraft's depth on the other two; the area fill to 0 after the UAT |
| 3 | Every polish line a pass takes is pinned by a test seen failing for its reason and ticked; an S1 or S2 line filed | **PASS** | F2 (six #1357 lines), A1 to A4 (#1356), W2 (twelve #1366 lines), each commit naming its red run; the digest cursor's lock left on #1357 with its reason; the ticks written on the lists with their commits at promotion |
| 4 | A news fetch and a security merge take one lock order: red before, green on 50 loaded runs after | **PASS** | K1: 3 of 4 cases `40P01` before, 51 runs green after beside loaded news and lifecycle runs; K2 and the order lens took the feed write, the matcher, a promotion and a label write into the same order, each red first and its race module 51 times green |
| 5 | `crashes.rankings` slim by default, today's answer under `projection=full` byte for byte; the schema bytes shrink | **PASS** | A1: the fixtures captured before the change equal `projection=full`; the default 25 % to 32 % smaller; the tool 1,219 to 1,215 bytes |
| 6 | #1460's and the cascade test's flakiness gone at the cause: 20 loaded runs green, no bound moved | **PASS** | M4 and M5, each cause measured and written in its commit, 20 of 20 loaded runs green, the 2 s and 60 s unchanged |
| 7 | Tops and flops reproduce; no name in both halves; every figure on the card equals the API's; no verdict key | **PASS** | T1's equalities with `WindowReturn` and Wealth's table to the last digit, recomputed at 34 digits; T2's API equal to `Movers.read/3`; T3's card compared with the API per window; `metrics_carry_no_verdict_test.exs` walks both routes; the UAT: all six windows equal |
| 8 | Every gate by registration; regressions counted, none an S1 at promotion | **PASS** at this record | above: no introduced S1, both older S1s fixed; the new gates (the sweep tag check, widened by the correctness lens; the shipped-font check; the external-font-host check; the unused-class check) each with its attack cases; W2's gate exception removed; no time bound moved |

## UAT persona

The operator's walk on the review seed, recorded in
`uat-sprint30-2026-11-19/` (30 screenshots and a README), in CI's
headless shell with no Inter on the machine: the font check with and
without `/fonts/`; „Tops und Flops“ on every window, its basis, its ⓘ, its
link into Wealth, the privacy mode and the phone layout; Wealth's axis
switch and the overdraft days; the Wealth polish lines; Risk › Crashes
with its windows and names tables; a security's chart with the axis mark.
Every figure a screen showed matched the API's answer for the same read:
the card's six windows, Wealth's contribution rows and sums, the KPIs and
the stack's legend, and all twelve crash lists.

It found seven S3 and nothing worse. Two are the closing act's own and are
fixed after the UAT: at „ab 0“ the area under the line ran to the stack's
floor, and the Crashes basis line said „nur Wertpapiere im Katalog“ also
under „Im Depot“, a slip of the shortened copy. Four are polish lines: on
„Tag“ a row's previous close may be months old (an ADR-0061 question,
#1358), the crash rankings' axis at 390 px, the names table at 390 px and
the selected phone row's padding (#1366). One is older: „4,00 %“ breaks in
the positions table's name column (#1366). The walk read what no test
reads: two of the seven are visible only in a screenshot.

## Carry-forwards for Sprint 31

1. **Run the browser walks in CI's headless shell, by default.** The
   repository's launcher and the guide name Playwright's
   chromium-headless-shell of the pinned release, not a full Chrome.
   *Owner:* the next maintenance lane. *Why:* the shell lays the shipped
   Inter out differently, and a full Chrome's 3 px margin hid CI's red.
2. **Match the test database's collation to CI's** (#1475, S2). *Owner:* the
   next plan. *Why:* a name-order dependency passed in every local run and
   failed in every CI run.
3. **Cap the parallel agents by the machine's CPUs.** At most two agents
   running tests at once on 4 CPUs, the rest reading or writing. *Owner:*
   the implementation session. *Why:* a load average of 40 to 47 made
   bounds look flaky and runs repeat.
4. **Run the full suite after every closing-act fix batch, before the
   push.** *Owner:* the implementation session. *Why:* a fix that passed its
   own files and the invariants broke #1081's rule in CI.
5. **#1473's decision** (`needs-decision`): whether the contribution walk
   keeps reading a stored close of 0 or below as a price. *Owner:* the
   owner, through the next plan's recommendation. *Why:* the count now marks
   it, but the walk's figure still values the units at it.
6. **#1474, #1470 and #1475**, the S2s this sprint filed. *Owner:* the next
   plan. *Why:* an S2 the next diff reaches is fixed, not carried again.
7. **I34's step 2 planned from M6's numbers.** Warming the default period's
   bands and the 1-year table costs about 0.7 s of CPU and 0.7 MiB of memo
   per scope and saves about 560 ms of a cold first paint at Kategorien €
   1y on the server; a warm switch's read is under 10 ms of 25 to 86 ms, so
   a hit served without the skeleton is the other target; one scope warmed
   fully is 29 MiB of the memo's 128. *Owner:* the next planning session.
8. **The polish lines this sprint recorded** (above: twelve of its own,
   ten older) **and F2's digest cursor lock**, which needs a design that
   keeps the 32-consumer cap. *Owner:* the passes that take those screens.
9. **The worktree helper keeps `deps` from being changed through a link.**
   *Owner:* the next maintenance lane. *Why:* one lane's fetch changed every
   lane's dependencies.
10. **The attack lens before integration, kept, and pointed at every lock
    order a fix introduces.** *Why:* K1's lens found two cycles, and K2's
    own order introduced a third that only the closing act's order lens
    found.
