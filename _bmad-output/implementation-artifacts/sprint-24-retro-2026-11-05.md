# Sprint 24 Retrospective — the dossier, the journal since a date, the costs beside the gap, and two owner reports (2026-11-05)

ADR-0026 step 5 for Sprint 24, written by the implementation session as the
sprint PR's last commits (sprint workflow §5). The plan,
`sprint-plan-2026-11-04-sprint24.md`, was adopted by the merge of its
planning PR, which signed ADR-0017's amendment of 2026-11-04 (#1378) and
ADR-0046's amendment of 2026-11-04 (I17). The close-out entry with every
criterion and count is in `sprint-status.yaml`; this file keeps what the
sprint teaches.

## What shipped

One PR under the plan's D-6: the sprint PR #1388
(`agent/claude/sprint-24`), 44 commits against an estimate of about
47, no stacked PR.

- **Lane M:** M1, the `browser` CI job on a Playwright pinned in
  `test/browser`'s own lockfile (green on its first run, under four
  minutes); M2, tea re-pinned to v1.27.3 and v3 declined with bmb's read
  (every tea 2.x/3.x tag needs the unreleased BMAD v7 core); M3, the
  version report; M4, Elixir 1.19.7 green in CI on a scratch branch
  (#1389, closed unmerged) only with a formatter layout and two struct
  matches, so filed as #1390 instead of taken.
- **Lane J:** J1 (#1378), J2 (the journal's paged `since=`), J3 (the page's
  „Seit“).
- **Lane D:** D1 (FR-49, #1386), the dossier and its tool.
- **Lane B:** B1 (`costs_paid`, #1387) and B2 (its line).
- **Lane P:** P1 (#1366's three lines, under one board commit) and P2
  (#1357's rail line).

## What went well

* **THE BROWSER TESTS RUN IN CI.** Sprint 23's carry-forward 5 is closed by
  the job, not by a rule someone has to remember. The job was green on its
  first run, and the two browser tests this sprint added (P1's sunburst,
  P2's rail) ran in it from their first push.
* **THE CLOSING ACT FOUND WHAT THE STORIES' TESTS COULD NOT, AND EVERY
  FINDING WAS FIXED ON THE BRANCH.** Six S2s and seven S3s, all on surfaces
  this PR changed, each fixed test-first; one S3 that needs a board went to
  #1366. Three lenses found the same S2 independently (the costs line hid a
  cost it could not convert), which is the kind of agreement the lenses
  exist for.
* **CARRY-FORWARD 4 PAID OFF.** The lenses followed the screens literally:
  typing a half date into „Seit“, pressing Enter in it, turning a phone,
  handing over a truncated cursor. Every S2 of the closing act was found
  that way, none by reading code.
* **THE MONEY HELD.** B1's four identities, a moving rate, the window
  bounds, the scope rule and the memo's invalidation all held under the
  money lens's probes; the cost facet's output is pinned unchanged by the
  refactor.
* **STORIES IN PARALLEL, HISTORY IN LANE ORDER.** J1, D1, B1 and Lane M were
  built at once in worktrees; D1 and B1 waited for Lane J and were then
  integrated in the plan's order. Conflicts were only ever in contract
  entry 24, the contract test, DESIGN.md and the gettext catalogues, and
  Sprint 23's merge tool settled the catalogues every time.

## What did not go well

* **AN INVARIANT CAUGHT J3 AT INTEGRATION, NOT IN ITS STORY.** J3 built the
  board's native date input; UX-DR19 refuses it app-wide, and two
  invariants turned the suite red on `7b660ba`, CI's only red head of the
  sprint (fixed by a commit, not re-run). The story's agent ran its own
  test files and not `test/invariants`.
* **J1 MISSED ONE SEEDED-UPGRADE TEST.** The rollback writers changed, a
  test in `test/portfolixir/seeded_upgrade/` still expected the old shape,
  and only the orchestrator's full run found it (folded into J1's commit
  before the push).
* **THE CONTAINER RESTARTED TWICE**, once mid cherry-pick and once with two
  fix agents running. Nothing was lost, because everything before was
  committed and the agents resumed from their transcripts; carry-forward 1
  held.
* **THE STORY TESTS PINNED WHAT WAS RENDERED, NOT WHAT THE OPERATOR DOES.**
  Again: B2's test compared the screen with an API call over a different
  period and passed only because the fixture's costs were recent; J3's
  tests never typed a half date.
* **A GATE THIS SPRINT ADDED CHECKED LESS THAN IT SAID.** D1's `raisedBy`
  rule measured only the last row and never asked whether a named tool was
  new. The correctness lens found it, and it was fixed before promotion.
* **AN OLDER TEST FLAKED UNDER THE FINAL COVERALLS RUN.**
  `securities_sync_rearm_test` saw four provider fetches for two
  securities once, under load, and passed five in five alone; it is outside
  the diff, so it is a line on #1365 with the question whether the test or
  the single flight races. The heap-cap test also failed once under
  four worktrees' load; both say the full suite is less deterministic under
  parallel load than CI's single runner shows.
* **NO HISTORY CLEANUP WAS POSSIBLE.** This session could not force-push,
  so the closing act's fixes stay as their own commits and the branch could
  not be rebased onto `main` had it moved. `main` did not move.
* **THE PLAN SAID "EXACTLY ONCE" WHERE THE FAMILY GIVES "AT LEAST ONCE".**
  D-1 criterion 2 holds for a settled journal; while a write is in flight
  the journal, like every paged delta read, may re-deliver and never skips.
  The agent's lens found the tool description silent about it; it now says
  so.

## Two-way coverage

- **New this sprint:** the dossier (its view is the security page and, for
  the targets, the Classifications page), the journal's `since` (the
  field „Seit“), `costs_paid` (the Performance line). Nothing is
  agent-only.
- **Overdue from earlier sprints:** none. Nothing is recorded.

## Maintenance

`version-report-2026-11-05-sprint24.md`: tea v1.27.3 taken; tea v3, floki
0.38.5, lazy_html 0.1.14, decimal 3.2.0, sobelow 0.18.1 and the transitive
drift declined with reasons; npm current; PostgreSQL unchanged. #727's two
triggers: the OTP one has not fired (Dialyzer on an OTP 28 PLT reports 117
opaqueness errors, and `logo_lookup.ex`'s `@issuers` does not compile on
OTP 28; noted on #1390); the Elixir one is #1390.

## Carry-forwards for Sprint 25

1. **A story runs `test/invariants` beside its own tests.** J3's red head
   came from an invariant no story agent ran.
2. **A story that changes a writer greps the whole suite for the shape it
   changes**, `seeded_upgrade/` included.
3. **A screen story's test drives the field as the operator does**: a half
   value, Enter, a resize, a link handed over; and a figure on the screen
   is compared with the API call for the same request, its period stated.
4. **A gate a story adds gets an attack case in its self-test**, the way
   the closing act's fix of `raisedBy` did.
5. **The owner's ask 3:** the `browser` job as a required check once it has
   run green on `main`.
6. **#1390, Elixir 1.19.7**, a candidate for Sprint 25's maintenance lane;
   **F21 (#894)** stays Sprint 25's first candidate (Sprint 24 D-11).

## Close-out ledger

- Closes by keyword on #1388: #1378 (J1), #1386 (D1), #1387 (B1 and B2).
- Filed: #1390 (the Elixir 1.19.7 move, M4).
- Closed by hand: none; the scratch PR #1389 closed unmerged.
- Polish lines ticked: #1366 (#1322, the sunburst, „Beitrag je
  Position“), #1357 (the rail). Added: #1366 (the holdings notes at
  1200 px; the sunburst tooltip on touch), #1356 (the cost facet test's
  comment), #1365 (the sync re-arm test that flaked once under load).
- Ideas: I7, I16 and I17 `built`; F1 stays `discussing` (D-10).
- Merges and releases: #1388 PENDING on the owner, recorded by the next
  planning PR.
- Open issues, reported and not judged: 29 open before the merge, 26 once
  #1388's three keywords close.
