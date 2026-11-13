# Sprint 29 Retrospective — the crash rankings, the news layer's first-fill fixes, the layout gate and the Bitcoin cycles (2026-11-13)

ADR-0026 step 5 for Sprint 29, written by the implementation session as the
last commits of the sprint's third PR (sprint workflow §5). The plan,
`sprint-plan-2026-11-12-sprint29.md`, was adopted by the merge of its
planning PR #1449, which signed ADR-0059 and ADR-0060 (FR-58), ADR-0048's
amendment of 2026-11-12, the amendments of ADR-0056 and ADR-0058 of
2026-11-12 and the scope ladder's analog band. The close-out entry with
every criterion and count is in `sprint-status.yaml`; this file keeps what
the sprint teaches.

## What shipped

Three stacked PRs built by one implementation session, as the plan's D-10
decided, each promoted only after its own closing act and merged in order:

| PR | Lanes | Commits (plan) | Closes | State at this record |
|---|---|---|---|---|
| #1458 | M, N, B, C | 68 (about 64) | #1416, #1421, #1439, #1440, #1443, #1444, #1459 | merged 2026-11-13, release 2026.11.16 |
| #1461 | D, P, L | 35 (about 31) | #1413, #1414, #1417, #1435 | merged 2026-11-13, release 2026.11.17 |
| #1462 | H, the UAT persona, the close-out | 55 (about 48) | #1450 | not merged |

- **Lane M:** M1, the version report, `dialyxir` 1.4.9 and the companion
  image on Node 26.13.1; M2, one settle helper for every browser walk,
  asserted (Sprint 28's carry-forward 1); M3, the heap-cap flake (#1440),
  which found #1459 (S1: two import tests set the heap cap under a key
  nothing reads); M4, blocked site storage no longer stops the page from
  connecting (#1439).
- **Lane N, the news layer's first-fill fixes** (risk tier stored data): N1,
  a rating re-rates the unpromoted items it covers in its transaction
  (#1444); N2, links of 2,048 characters (#1443); N3 and N4, the Research
  tab's headline, event type and tone, read and written, the view Sprint
  28's close-out found owed.
- **Lane B, any security with a stored quote as a benchmark** (#1416): one
  rule for every read and setting; both pickers grouped.
- **Lane C, the crash rankings** (FR-54, #1421; risk tier money math): the
  setting, the rule `peak_trough_v1`, names and manual windows, the three
  lists from `WindowReturn`, five routes and five tools, the Crashes section
  on Wealth › Risk, the docs.
- **Lane D:** `implausible_quote` over every security with a priced booking
  (#1414); the Overview's held count first (#1417); the logo tools (#1413).
- **Lane P:** the bands read memoised per fixed period and request (I34's
  step 1); translucent bands (I33).
- **Lane L, the layout gate** (#1435): one shared control bar, seven bars
  moved onto it, a walk over every page in two fonts, a static check, the
  open-prose rule.
- **Lane H, the Bitcoin cycles** (FR-58, #1450; risk tier outbound caller):
  the chain registry and binding, the event kind `halving`, the Esplora
  adapter, the reader's run, the cycles read with its bands, three tools,
  the „Zyklen“ chart, the range „Zyklus“, the card and the form.
- **The closing acts:** an attack lens before integration on N1 and H2;
  per PR, lenses for correctness, money, edge cases and order, the agent,
  security and the design critic on the sprint's boards; the fixes,
  test-first; a re-check on each integrated head.

## What went well

* **THREE STACKED PRS IN ONE SESSION HELD.** The plan's D-10 cut the sprint
  where the money-math group ends; PR 1 was reviewable and merged while PR 3
  was still being built, and the owner merged PR 1 and PR 2 in one sitting,
  a minute apart, each green on `main`. No PR came near GitHub's 100-commit
  limit, and the 2026-11-12 stacking rule needed no exception.
* **PARALLEL STORY AGENTS, EACH IN ITS OWN WORKTREE AND TEST DATABASE.**
  Lanes D, P and L were built beside Lane C, and Lane H beside PR 2's
  closing act, then rebased onto the PR before them (D-4). No agent's test
  run read another's rows.
* **A CONTAINER RESTART LOST NOTHING.** The session's container restarted
  mid-sprint; the state lived in the worktrees, the plan's checklist and
  the PR bodies (D-10's "what keeps it reviewable"), and the session
  continued from them.
* **THE ATTACK LENS BEFORE INTEGRATION PAID OFF AGAIN.** N1's lens found
  that a block's removal must stand (an ADR-0056 E1 precision); H2's found
  that a non-own URL could name any host and that an out-of-bounds tip or
  out-of-order blocks failed the whole run, each fixed before Lane H was
  integrated. The two S1s the closing acts found on the sprint's own code
  sat on the same two stories (below): the surfaces an attack lens is
  pointed at are where the worst findings live.
* **EVERY FLAKY TEST WAS FIXED FROM ITS ROOT CAUSE, NOTHING LOOSENED.** Six
  flaky tests came with the sprint's code (below); none got a longer
  timeout or a retry. One of them was not a test defect at all: the walk
  that held the socket's messages to force the race showed LiveView
  patches closing a `<details>` the server did not render open, so the
  shell's `DisclosureState` and `PopoverDisclosure` hooks now read the
  state in `beforeUpdate`, a real app bug in Holdings' benchmark picker
  and in the custom range's popover.
* **THE MONEY MATH WAS RECOMPUTED, NOT TRUSTED.** Every pinned crash figure
  was recomputed independently in Python's `decimal` at the app's 34
  digits; the money lens found that exactly 10 % across a 3:1 split opened
  no window because a split factor was a rounded quotient, and split
  factors are now exact fractions. Lane H's figures were recomputed at 34
  digits after the analytics lens noticed the first run used 28.
* **THE CLOSING ACTS DREW BEFORE THEY FIXED** (Sprint 28's carry-forward
  3): boards 02, 06 and 07 gained before-and-after frames for the picker's
  groups at 390 px, the folds, the basis-line ⓘ and the cycle chart's five
  findings, and CI's fallback-font finding was drawn on board 06 before
  the folds moved. One state escaped the rule in the build, not the
  closing act: B2's „Weitere“ group was drawn on board 02 after the build
  found it.

## What did not go well

* **STORY AGENTS RAN ONLY THEIR OWN TESTS, AND THE SWEEPS FOUND THE REST.**
  The brief told each story agent to run its own files and `test/invariants`,
  not the full suite (ten minutes). The project-wide sweeps live outside
  `test/invariants`, so the full suite found three gate failures after PR
  1's integration (the ngettext check, the text sweep and the bounded-date
  sweep, all in the crash lane) and six after Lane H's (the text,
  bounded-date and field-label sweeps, two localization checks and the
  privacy value base). Each was a small fix; each cost an integration
  round.
* **SIX FLAKY TESTS CAME WITH THE SPRINT'S CODE.** Two async tests met on
  one unique FX row; eight async modules chose the one instance-wide crash
  benchmark setting; the id-range sweep ran 5,832 dispatches in one
  60-second test; the news scheduler's fetch tasks lost their shared
  sandbox connection while waiting on N1's tier lock and the matcher lock;
  the picker walk (the app bug above); the basis-line ⓘ walk placed its
  line before the page settled. *Cause:* shared state a story's own run
  does not exercise (one setting, one FX key, one sandbox connection) only
  collides under the full suite's concurrency.
* **THE FOLDS WERE TUNED IN ONE FONT.** Lane L measured every bar in Inter,
  which the session's machine has; the app names Inter first in
  `--font-sans` and ships no `@font-face`, and CI's runner drew it in
  DejaVu Sans, where the Crashes bar's line and the stacked chart's label
  column no longer fit. The rule broke for every operator without Inter,
  and the walk could not see it until CI ran it. The walks now measure
  both fonts (`test/browser/fonts.js`) and CI installs both; the app still
  depends on the operator's installed fonts.
* **THE CLOSING ACTS FOUND THREE S1S, ALL FIXED.** Two on the sprint's own
  code: a second promotion of a story kept a now-blocked member's tier (N1)
  and a forged chain tip ahead of the real chain was stored and would have
  locked honest sources out (H2). One in a gate: a labelled bar under an
  unknown class passed both of Lane L's gates, a gate that checked nothing
  for it. The gate got its own attack lens only in the closing act.
* **ONE AGENT KILLED THE OTHERS' TEST RUNS.** A story agent ran `pkill -f
  "mix test"` to stop its own stuck run and killed every parallel agent's
  run with it; those agents re-ran and reported late.
* **EVERY INTEGRATION CONFLICTED IN THE GETTEXT CATALOGUES.** Each lane
  extracts its strings into the same `.pot` and `.po` files, so every
  replay conflicted there; a resolver script (both sides' entries kept,
  then `mix gettext.extract --merge`) settled them, but it lived in the
  session's scratch, not in the repository.

## The regressions, counted apart

The sprint workflow §3 and ADR-0026's amendment of 2026-11-01: the
regressions this sprint introduced are counted apart from the older
findings it passed. PR 3's rows stand at this record.

| | S1 | S2 | S3 | Fixed on the branch |
|---|---|---|---|---|
| PR 1, the build, the full suite and CI (four flaky tests; the picker closing under the operator; the ngettext, text and bounded-date sweeps) | 0 | 5 | 3 | 8 |
| PR 1, N's attack lens (E1: a block's removal stands) | 0 | 0 | 1 | 1 |
| PR 1, N's correctness hunter (a second promotion's tier; a `\` before `@` in a link) and design critic (board 03) | 1 | 2 | 2 | 5 |
| PR 1, the B/C money lens (split factors; the full tie; a close of 0) and the edge and order lens (twins, the reload, the first setting write; its fourth the full tie, counted once) | 0 | 1 | 5 | 6 |
| PR 1, the B/C agent's lens (wording, a residue, the rankings mostly audit trail) and design critic (boards 01, 02) | 0 | 0 | 8 | 7 |
| PR 1, polish lines from the build and the closing act (the Crashes table at 390 px; „Im Depot ansehen“ drops the view; no section without a portfolio; a negative net quantity held; `News.Promotion`'s dead fallback; `LinkDomain.of/1`'s dead branch) | 0 | 0 | 6 | 0 |
| PR 2, the build, the full suite and CI (a flaky ⓘ walk; folds in Inter alone; the Overview's ngettext; the docs' "held"; Wealth's note link) | 0 | 1 | 4 | 5 |
| PR 2, the D+P lens (`no_source`'s wording; a sold security's note) | 0 | 0 | 2 | 2 |
| PR 2, L's attack lens (an unknown class; an `sr-only` label; cousin blocks; a sentence ending in a number; unswept widths; M2's settle check blind to four ways of leaving) | 1 | 2 | 3 | 6 |
| PR 2, the design critic (boards 04 to 06) and the re-check (the ⓘ on a short window opens upward), with the gate's named limits | 0 | 0 | 5 | 3 |
| PR 3, the build (three ADR precisions; a halving write's basis bump; the help and the comments) and the integration (six gate failures; H's bar and prose on L4 and L5) | 0 | 0 | 13 | 13 |
| PR 3, the security lens (a forged tip; the own URL's path stored; the throttle bypassed; an IPv6 refusal) and the order and agent lens (the state row moving backwards; the aligned date; `halving_chain`'s description) | 1 | 2 | 4 | 7 |
| PR 3, the analytics lens (next_halving's inputs; the basis text; the dossier's basis; the float-island gate) and the design critic (board 07's five), and two fixes' own slips caught by their gates | 0 | 1 | 10 | 11 |
| PR 3, the re-check (a first run's forged tip; a failure's text crashing its record; the own link's port and IPv6 brackets) | 1 | 1 | 1 | 3 |
| PR 3, the UAT persona (the estimate's label; a one-day window on the form and chart; the names hint; the names table at 1200 px; Transaktionen's phone filter sheet; the journal's raw ids for the crash benchmark) | 0 | 0 | 6 | 2 |
| PR 3, the fixes' residue (the labels' boxes between 560 and 1000 px; the „heute“ line through the floor label) | 0 | 0 | 2 | 0 |
| **Introduced, total** | **4** | **15** | **75** | **79 of 94** |
| Older, fixed on the branch (#1459, the heap cap under a key nothing reads; the custom range's popover closing under a patch) | 1 | 1 | 0 | 2 |
| Older, filed (#1457, a news fetch and a security merge may deadlock, suspected; #1460, the scheduler's real-path test on a shared 2-second clock) | 0 | 2 | 0 | filed |
| Older, recorded as polish lines (two tests flaky under load; the UAT's aggregator redirect as an entry's link; `put_journaled`'s first-write race; a test FX key on a moving date; Wealth's no-price link; the digest cursor's database-wide lock) | 0 | 2 | 5 | recorded |

The four introduced S1s are fixed before each PR's promotion, and the older
S1, #1459, on PR 1. The fifteen introduced findings not fixed are all S3
and each a polish line: #1356 (the rankings' default answer, also idea I45;
`News.Promotion`'s fallback), #1357 (`LinkDomain.of/1`'s branch; the layout
walk's blind spots: prose set as bare text in `<main>`, a bar that appears
only after a click, link-only controls), #1365 (a negative net quantity
counted as held; the Nachrichten tab's ⓘ at 1200 × 1000; the Termine tab's
one-day window; the cycle labels between 560 and 1000 px; the „heute“ line
through the floor label), #1366 (the Crashes table at 390 px; the view
pair; no section without a portfolio; the names hint; the names table at
1200 px) and #1360 (Transaktionen's phone filter sheet; the journal's raw
ids for a crash-benchmark change). Not counted, because it is a decision
and not a defect: a source that lies within both of ADR-0059 §7's bounds
still stores its tip; the ADR names the limit, its remedy and its flip.
Nothing is withheld to make a count.

## Exit criteria (D-1)

| # | Criterion | Verdict | Evidence |
|---|---|---|---|
| 1 | No unpromoted item keeps a tier its domain no longer has; promoted items keep theirs; races end as E1 states | **PASS** | `retier_test.exs`, `lock_race/news_retier_order_test.exs`, the attack lens's 25 cases; the second promotion's S1 fixed and pinned in `promotion_test.exs` |
| 2 | A story whose every link fits 2,048 characters becomes an entry | **PASS** | N2 on notes and events; a `\` before `@` refused at every writer |
| 3 | The operator sees and writes the Research tab's headline, event type and tone | **PASS** | N3, N4; board 03's three fixes |
| 4 | Any security with a stored quote is a benchmark in every read that takes `benchmark=` | **PASS** | B1's one rule; the basis names flagged, held or unheld; a close of 0 is no quote |
| 5 | The same closes give the same windows; 10.00 % opens, 9.99 % does not | **PASS** | C2, every ADR-0058 §7 case with exact `Decimal`s; the split case with exact factors |
| 6 | The lists are reproducible and honest | **PASS** | C4; the full tie by ticker, WKN and currency; a crash return and a sale-hindsight return agree to the last digit |
| 7 | The Crashes section answers as the API | **PASS** | C6 pinned against the API; the UAT persona's every figure matched the API |
| 8 | The chain source can only be read, and a lying answer writes nothing | **PASS** at this record | H2's attack lens before integration; the forged tip bounded by the stored tip; the own URL's path never stored; the throttle claimed before the read; the gate sentence widened with its registry entry (H3) |
| 9 | The cycles reproduce and never forecast | **PASS** at this record | H4 and H5 with exact `Decimal`s recomputed at 34 digits; no single date or price in a payload; `as_of` refused; `next_halving` with its stored basis |
| 10 | A memo hit equals a fresh read | **PASS** | P1 after each write kind, both scopes, two levels; the money lens's six extra kinds |
| 11 | `implausible_quote` names a sold security's unit error; the Overview counts held first | **PASS** | D1, D2 |
| 12 | Every browser walk leaves a page through the shared settle helper | **PASS** | M2's invariant, widened by L's attack lens to four more ways of leaving |
| 13 | Every labelled bar starts its controls on one edge; no open paragraph past one sentence | **PASS** | L1 to L5; L's attack lens's S1 fixed; both fonts measured |
| 14 | Every gate by registration; regressions counted, none an S1 at promotion | **PASS** | above; B2's Esplora entry with its self-test; the float-island gate names `:math.log/1`; no time bound moved |

## UAT persona

The operator's walk on the review seed, recorded in
`uat-sprint29-2026-11-13/` (26 screenshots and a README): the news queue
after a rating and a block, two promotions, the Research tab's entry, a
held fund as a benchmark, the Crashes section on Wealth › Risk, the
Overview's held count, Wealth's bands across period switches, the moved
bars at 390 px, and the „Zyklen“ chart, the range „Zyklus“, the card and
the halving form, down to a chain source gone stale.
Every figure a screen showed matched the API's answer for the same read.

It found seven S3 and nothing worse. Two are fixed on PR 3: the next
halving's estimate ran into the Top band's label and past the plot at
1200 px, and a one-day window read „d – d“ on the form and the chart. Four
are polish lines: the hint under the names without a window blames
changed closes also when another crash benchmark hides the name, and that
table is too wide at 1200 px (#1366); Transaktionen's filter sheet on a
phone puts one chip per row, a regression of L2's bar, and the journal
names a crash-benchmark change by raw ids (#1360). One is older: an entry
promoted from an aggregator's story links the aggregator's redirect, not
the rated domain (#1365). The walk is what the lenses did not do: it read
the screens as the operator reads them, and the two fixed findings were
visible in a screenshot and in no test.

## Carry-forwards for Sprint 30

1. **A story agent runs `test/invariants` and the project-wide sweeps beside
   its own tests:** `test/portfolixir/localization_test.exs`,
   `test/portfolixir/input/text_sweep_test.exs`,
   `test/portfolixir/input/bounded_date_sweep_test.exs` and
   `test/portfolixir_web/field_label_test.exs`. *Owner:* the implementation
   session's story brief. *Why:* the full suite found three sweep failures
   after PR 1's integration and six after Lane H's, each an integration
   round a story's own run would have saved.
2. **Never stop a process by pattern.** A story agent stops only what it
   started, by its own process id; `pkill -f` and `killall` are out.
   *Owner:* the story brief. *Why:* one agent's `pkill -f "mix test"`
   killed every parallel agent's run.
3. **One resolver for the gettext catalogues at every integration**, kept
   where the next session finds it (both sides' entries, then `mix
   gettext.extract --merge`), not rewritten per conflict. *Owner:* the
   implementation session. *Why:* every lane's replay conflicted in the
   same catalogues.
4. **The walks measure both fonts (done in PR 2); the next plan weighs
   shipping the font.** Inter served as a web font would make the app
   read the same on every device, against the bytes it adds and a
   licence to check. *Owner:* the next planning session. *Why:* the
   folds were tuned in a font the operator may not have.
5. **The attack lens before integration — keep, and point the closing
   act's lenses at the same stories again.** *Why:* it found holes in N1
   and H2 before integration, and the closing acts' three S1s on the
   sprint's own code were on those same two stories.
6. **A new gate gets its attack lens before it is integrated,** as a new
   writer does. *Why:* Lane L's walk and static check passed a labelled bar
   under an unknown class, an S1 found only in the closing act.
