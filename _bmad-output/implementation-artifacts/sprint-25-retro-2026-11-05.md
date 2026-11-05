# Sprint 25 Retrospective — predictions that score the agent, what a sale missed, dry-run deletes, and the home-screen icon (2026-11-05)

ADR-0026 step 5 for Sprint 25, written by the implementation session as the
sprint PR's last commits (sprint workflow §5). The plan,
`sprint-plan-2026-11-05-sprint25.md`, was adopted by the merge of its
planning PR #1394, which signed ADR-0055 (gate B4.2, idea F1) and the story
workflow's section "What a story's own tests do not cover". The close-out
entry with every criterion and count is in `sprint-status.yaml`; this file
keeps what the sprint teaches.

## What shipped

One PR under the plan's D-9: the sprint PR #1398
(`agent/claude/sprint-25`), 37 commits before the close-out's four, about
41 in all against an estimate of about 40, no stacked PR.

- **Lane M:** M1, Elixir 1.18.6 → 1.19.7 on OTP 27.3.4.19 (#1390's three
  commits, plus one test struct match the scratch run had missed because CI
  compiles tests without `--warnings-as-errors`); M2, the sync re-arm
  flake reproduced on repeat 133 under load and named: the test raced, not
  the single flight; M3, the version report and Debian bookworm 20261104
  in both images.
- **Lane W:** W1, the iPhone home-screen icon, an opaque 180 × 180 PNG
  from the shipped icon in the light palette (board 01, A), served without
  a session, its render script reproducible byte for byte.
- **Lane S:** S1, one window-return function in EUR; S2, FR-50
  (`GET /api/v1/sales/hindsight` and `portfolixir.sales.hindsight`, I18's
  modes 1 and 2).
- **Lane F:** F1 (the `predictions` table, append-only and journal-armed,
  locked against merge and delete), F2 (resolution at read), F3 (the
  calibration report), F4 (four routes, four MCP tools), F5 (the
  `position_review` prompt).
- **Lane N:** N1, the news convention on `notes.append` (I13; no field).
- **Lane X:** X1 (#894, F21), `dry_run` on the three cascading deletes, the
  real delete rolled back.
- **The closing act:** five lenses; nine fix commits and ADR-0055's
  amendment of 2026-11-05 (the start close, finality, the rate cap).

## What went well

* **THE RULES WERE FIXED BEFORE ANYTHING WAS STORED.** Three of the closing
  act's four S2s were in ADR-0055 itself, and a prediction is a record
  that can never be corrected. They were found and amended on the branch,
  before any prediction existed on any instance, and because the outcome
  is derived at read, nothing needs a migration of data: every call
  re-resolves under the amended rules.
* **THE MONEY HELD.** The money lens recomputed every pinned value of the
  window return, the resolution and the scores independently, and all
  matched; D-8's moving-rate check was run on a USD security whose rate
  moves between the two closes. Its one money S3 (1E-33 rounding noise
  that turned identical moves into a hit) was fixed by computing the
  return as one division of exact products.
* **F1'S PERMANENCE WAS ATTACKED, NOT ONLY ASSERTED.** D-8's six attacks
  (an `UPDATE`, a `DELETE`, a caller-supplied `made_at`, 0.49, 1.00, an
  agent write without `model`) are each refused by a test, `TRUNCATE`
  too.
* **A FLAKE GOT A CAUSE.** M2 reproduced the re-arm flake under
  `--repeat-until-failure` and load instead of retrying it away, found two
  races in the test (the sweep freed too early, a fixed registered name in
  the setup) and none in the single flight, and ran 300 of 300 green.
* **SPRINT 24'S BUILD RULES HELD.** Every story brief carried its
  carry-forwards 1 and 2 (`test/invariants` beside the story's tests; a
  whole-suite grep for a changed shape), and CI was green on every pushed
  head, nine jobs, with no red head to fix.
* **THE COVERAGE GATE FOUND A DEFECT.** codecov/patch, a status beside
  the nine jobs, read 85.6 % against its 90 %; the tests written to cover the gap found that a whole-second
  `made_at` was not stored (now padded to microseconds), and the patch
  reads about 97 %.
* **PARALLEL STORIES IN WORKTREES WORKED.** M, W, S, F, N and X were built
  by separate agents, each on its own test database, and integrated in
  lane order, so history goes forward only and S1 sits before F2.

## What did not go well

* **THREE DEFECTS WERE IN THE SIGNED RULE.** The start close strictly
  before the made day let a caller score a move it had already seen
  (closes Monday 100 and Tuesday 110, a call on Tuesday at 22:00 UTC scored
  from 100); a resolved outcome flipped when the `resolves_on` close
  landed late; `rate:5`, meant as 5 %, was accepted as 500 % a year.
  *Cause:* the ADR was read for what it records, never attacked as a game
  by the party it scores, and a story's tests pin the rule as written, so
  no story test could find a defect in the rule. The closing act's UAT
  persona and money lens were the first adversarial readers.
* **A MISSPELLED DRY RUN RAN THE REAL DELETE.** `dryRun`, `dry-run` or an
  empty `dry_run` on the three cascading deletes deleted for real (S2,
  arguably S1). *Cause:* the companion's schemas stripped unknown keys
  instead of refusing them, and the routes ignored unknown parameters;
  X1's tests pinned `dry_run=true` and the real delete, never a typo.
  Fixed: a strict schema on the tools, a 422 for any other key and for an
  empty `dry_run`.
* **FOUR TEXTS PROMISED WHAT THE TOOLS DID NOT DO** (S3, the agent's lens):
  create promised a 422 its own schema pre-empts; the prompt did not check
  that the benchmark has a recent close; neither said that a prediction
  freezes its security and benchmark; N1 did not say that a news entry
  counts for `notes.unreviewed`.
* **THE PLANNING PR CLOSED #1390.** #1394's body carried a closing keyword
  for an issue the sprint PR implements, so #1390 closed on 2026-11-05
  when only its plan merged, and D-1's criterion 5 ("#1390 closes by
  keyword") could not be met as written. *Cause:* the sprint workflow's
  rule ("a keyword is only for issues this diff finishes") was not checked
  against the planning PR's body.
* **A SHARED TEST DATABASE FAILED 88 TESTS.** The orchestrator's first
  full run failed on rows a half-run, unboxed test of its own had left in
  the shared test database before the predictions migration ran. The
  database was rebuilt and the rerun was clean, so it is not a regression,
  but it cost a full run.
* **INTEGRATION BY CHERRY-PICK NEEDED HAND RESOLUTION THREE TIMES**, in the
  files every story extends: contract entry 25's summary, the contract
  test, `tools.ts` and the schema budget. *Cause:* every story appended to
  the same string and the same lists; once each story's item sat between
  its own markers, the merges were mechanical.
* **NO FORCE-PUSH, SO NO CLEANUP AND NO REBASE.** The session's permission
  classifier refused the force-push the history cleanup and the rebase onto
  `main` (one docs-only commit, `f36f29f`) need. The closing act's fixes
  stay as their own commits, and M2's message keeps "261 repeats", written
  while the run was still going; the final count was 300 of 300.
* **ONE LOG LINE WAS NOT REPRODUCED.** A "maximum heap size reached (256)"
  line under `SecuritiesLiveTest` appeared once while four story builds
  loaded the machine (W1's report) and did not recur; as in Sprint 24, the
  suite is less deterministic under parallel load than on CI's runner.

## The regressions, counted apart

The sprint workflow §3 and ADR-0026's amendment of 2026-11-01: the
regressions this sprint introduced are counted apart from the older
findings it passed.

| | S1 | S2 | S3 | Fixed on the branch |
|---|---|---|---|---|
| Introduced, found in the build (F2's whole-second `made_at`; F4's published-writes list) | 0 | 0 | 2 | 2 |
| Introduced, found by the closing act | 0 | 4 | 8 | 12 |
| **Introduced, total** | **0** | **4** | **10** | **14** |
| Older, recorded on polish lists (#1365: the pre-delete text names no predictions; a benchmark can be un-flagged under a recorded call. #1356: an extreme rate exponent echoed two ways; `notes.unreviewed` counts a news entry) | 0 | 0 | 4 | not on the diff's surface |

None is an S1 at promotion, and nothing from the sprint's own code is open.
The four S2s are each arguably an S1: a typo that deletes, and three rules
that would have let a permanent score be gamed or move.

## Exit criteria (D-1)

| # | Criterion | Verdict | Evidence |
|---|---|---|---|
| 1 | ADR-0055 built as signed | **PASS**, as signed and as amended | the trigger refuses `UPDATE`, `DELETE` and `TRUNCATE` (pinned); resolution and report pinned with exact `Decimal`s, at a moving rate too; §9's deferred ask filed as #1396; the money lens's independent recomputation matched |
| 2 | I18 modes 1 and 2 answer for every sale | **PASS** | each span equals a hand computation for no benchmark, a rate and a security; an unreached span reads `pending`; the UAT persona checked one by hand |
| 3 | A dry run equals its delete | **PASS** | row for row on the three deletes; every touched table and the journal counted before and after, unchanged |
| 4 | The icon | **PASS** | linked, 180 × 180, colour type 2, served without a session under the UI password; on an emulated iPhone 15; pixel-identical to board 01, A |
| 5 | Elixir 1.19.7 on `main`, every CI job green; #1390 by keyword | **PASS on the branch**; on `main` pending the merge; the keyword half not met | #1390 was closed by #1394's keyword (above) |
| 6 | The re-arm flake has a named cause | **PASS** | the test's two races, fixed in the test; 300 of 300; #1365's line ticked |
| 7 | Regressions counted, none an S1 at promotion | **PASS** | the table above |

## Two-way coverage

- **New this sprint, agent-only by D-7 with its reason** (data that
  accumulates comes first): F1 (a security's predictions on its page; the
  calibration block), I18 (the sale rows with their spans), F21 (delete
  confirmations that name what a delete removes). Their views are due by
  the **end of Sprint 26**; a missing one then is Sprint 26's close-out
  finding. The `position_review` prompt is an agent workflow with no view
  of its own; N1's notes already show on the research timeline.
- **Overdue from earlier sprints:** none.

## Maintenance

`version-report-2026-11-05-sprint25.md`: Elixir 1.19.7 (M1) and Debian
bookworm 20261104 taken; decimal 3.2.0, sobelow 0.18.1 (#1391, which the
owner could close with Sprint 23's findings), floki 0.38.5 (#1392),
lazy_html 0.1.14, playwright 1.65.0, Elixir 1.20, OTP 28, BMAD v7, tea v3,
bmb v2 and the transitive drift declined with reasons. Its gate table
predates the closing act's fixes, which is what it says it is.

## Carry-forwards for Sprint 26

Each is a rule with its reason and its source; the sixth is an ask, not a
rule.

1. **A rule that scores or records something permanently gets an
   adversarial pass at planning time**: can the scored party game it
   (measure from a price it has seen, pick a unit that flatters it), and
   can the score move after the fact without a correction? The planning PR
   answers both in the ADR before the merge signs it. *Why:* three of
   this sprint's four S2s were in the signed ADR-0055 and were found only
   by the closing act's UAT persona and money lens, and a story's tests
   pin the rule as written, so they cannot find a defect in it; a record
   that can never be corrected cannot wait for the closing act (Sprint 25
   closing act; ADR-0055, amendment of 2026-11-05).
2. **A safety parameter is refused when it is misspelled**: every
   destructive MCP tool has a strict schema, and every destructive route
   answers 422 for an unknown query or body key; a story's test sends a
   misspelling and an empty value. *Why:* a dry run that silently becomes
   the real delete is worse than no dry run, because the caller believes
   nothing happened (UAT persona's S2; X1's fix "a misspelled or empty
   dry_run is refused, never the real delete").
3. **A story's item in a shared file sits between its own markers**: one
   item per story in contract entry 25's successor, the contract test,
   `tools.ts` and the schema budget, each fenced by the story's ID. *Why:*
   integrating parallel stories by cherry-pick took hand conflict
   resolution three times while every story appended to the same string;
   with markers it became mechanical (the orchestrator's integration).
4. **A planning PR carries no closing keyword for an issue the sprint PR
   implements**: its body says "built by the sprint PR" instead, and the
   planning session checks the body before opening. *Why:* #1394 closed
   #1390 when only its plan merged, so the sprint's criterion 5 could not
   be met as written; the sprint workflow already says a keyword is only
   for issues the diff finishes ("Issues and the registry").
5. **Every parallel agent runs on its own test database, and a test that
   must run outside the sandbox gets its own scratch database.** *Why:*
   parallel builds collide on a shared database, and an unboxed test that
   fails half-way leaves rows behind: the orchestrator's first full run
   failed 88 tests for it (`DATABASE_NAME=…`; X1's lock-race test already
   runs on a scratch database).
6. **The ask: a force-push for the promotion.** The history cleanup and
   the rebase onto `main` need one `--force-with-lease`, which this
   session's permission classifier refused; the owner grants it on #1398,
   or rebases. Beside it, one practice that needs no permission: a commit
   message states a count only once its run has finished. *Why:* without a
   force-push nothing on a pushed branch can be reworded, and M2's message
   says 261 repeats where the run reached 300 of 300.

## Close-out ledger

- Closes by keyword on #1398 (one "Closes" line each in the briefing):
  #894 (X1), #1395 (F1 to F5), #1397 (S1 and S2). #1390 (M1) was already
  closed by #1394's keyword.
- Filed: none by this sprint; the planning session filed #1395, #1396 and
  #1397. #1396 (per-source calibration) stays open under #419.
- Closed by hand: none.
- Polish lines ticked: #1357 (the CountUp comment, W1), #1365 (the re-arm
  flake, with its cause, M2). Added: #1365 (the security page's pre-delete
  text; un-flagging a benchmark under a recorded call), #1356 (the rate
  exponent echoed two ways; `notes.unreviewed` and a news entry).
- Ideas: F1, F21, I18's modes 1 and 2 and I13's convention `built`; F32's
  first prompt built; I18's mode 3 stays `worked-out`, its ADR owed by
  Sprint 26's planning PR.
- Decisions made in the sprint, each flippable by a comment: ADR-0055's
  amendment ("ADR-0055 start before", "ADR-0055 finality", "ADR-0055 rate
  cap"); the rest in #1398's briefing.
- Merges and releases: #1398 PENDING on the owner, recorded by the next
  planning PR.
- Open issues, reported and not judged: 28 open at this record, 25 once
  #1398's three keywords close.
