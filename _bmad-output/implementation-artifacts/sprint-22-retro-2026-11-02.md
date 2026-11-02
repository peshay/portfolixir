# Sprint 22 Retrospective — every S1 and S2, a severity on every finding, and a build in parallel worktrees (2026-11-02)

ADR-0026 step 5 for Sprint 22, written by the implementation session as the
stacked PR's last commits (sprint workflow §5), before either PR is merged.
The plan, `sprint-plan-2026-11-01-sprint22.md`, was adopted by #1354's
merge; the session ran from about 20:56 UTC on 2026-11-01 into 2026-11-02.
The close-out entry with every criterion and count is in
`sprint-status.yaml`; this file keeps what the sprint teaches.

## What shipped

Two PRs under the plan's D-7, each merged by the owner's button, in order.

- **The sprint PR #1367** (`agent/claude/sprint-22`, 60 commits, head
  `d715e76`, promoted 2026-11-02 02:28 UTC, CI green), 25 closes:
  - **Lane F**, the flake: #1345 (the log-noise harness's handler-list race
    on OTP 27), #1268 (the crashing provider's budget capped at 10 s, and
    the test configuration's search budget raised from 1000 to 10_000 ms,
    the same class), #1273 (`settle/1` with an explicit 10 s). Three green
    CI runs in a row on Lane F's head, none re-run.
  - **Lane M**, the maintenance lane: `version-report-2026-11-01-sprint22.md`.
  - **Lane R**, every S1 and the S2s on money, imports and gates: R1
    (#1291, ADR-0003 amended), R2 (#1269, #1272, #1271), R3 (#1306, #1305,
    #1307, #1219), R4 (#1313, ADR-0050 amended, X1 to X3), R5 (#1310,
    #1311, #1317), R6 (#1292, #1290), R7 (#1309, D-5), R8 (#1316, #1332,
    #1331, D-6), R9 (#1274, #1293), R10 (#1335, #1337, ADR-0015 amended,
    L1). Contract entry 21.
- **The stacked PR #1372** (`agent/claude/sprint-22-ui`, draft), 14 closes:
  - **Lane A**: A1 (#1254, every capped list read says its limit and
    whether it was cut), A2 (#1294, #1295), A3 (#1301, #1315), A4 (#957,
    the merge previews' flow changes, built at its smallest, not cut).
  - **Lane U**: U1 (#1299), U2 (#1333), U3 (#1330), U4 (#1343).
  - **Lane I**: I1 on board 01 for Wealth Holdings, the Overview and Cash
    flow (#1351, #1350, #1336, #1342; 13 commits). Contract entry 22.
- **The cut**, by the shrink order's item 3: Lane I's later pages (the
  Wealth Allocation tab, the security detail, Snapshots, Tax, Views and the
  rest), to Sprint 23 under board 01. #1339 stays on #1366.

## What the closing acts found

Both ran under ADR-0026's amendment of 2026-11-01 (idea I14): each lens
reviewed its diff, each finding carried a severity, and the close-out
counts the regressions the sprint introduced apart from the older findings.

- **#1367's closing act** (the money and idempotency lens, the correctness
  hunter, the security lens on R1 and R2, the UAT persona) fixed 12 findings
  on the PR's surface. The UAT persona's round trips all passed: X1 to X3,
  L1, R8, R7 and #1219.
- **The regressions #1367 introduced: 8, none an S1**, all found before
  promotion. The two S2s are the ones worth reading twice: a refused logo
  discovery could overwrite a manual logo file, and a held-back row could
  still create a security. Both sat on exactly the line a new rule draws
  (a lock check, a hold-back), which is where the lenses looked.
- **The older findings it passed**, recorded by severity, not withheld and
  not built: two S1s filed (#1370, a CSV time the parser cannot read folds
  rows; #1371, the drawer's price edit keeps an imported trade's cash,
  `needs-decision` with answer (b) recommended), two S2s filed (#1368,
  #1369, both quote-only figures), polish lines on #1355, #1364 and #1365.
  Four filings in a sprint that closes 39, against Sprint 21's 96 and 76.
- **The stacked PR's closing act** so far: the correctness hunter's two S3s
  and two of the agent's lens's three are regressions; the third (a view
  PATCH with a top-level include or exclude answering 200) is older. All
  fixed on the branch. The design critic, which also covers boards 02 and
  03, and the UAT persona: boards 02 and 03 match; board 01 matched
  except a note naming several excluded groups, which clamped every count
  after the first (S2, a regression, fixed: the note opens with all its
  counts); an opened fold still read "Details anzeigen" (S3, fixed); a
  Marktwert dash for a missing exchange rate had no cell note (S3, older,
  fixed). The UAT persona found every figure on the pages Lane I touched
  unchanged, every ⓘ inside a 390 px viewport, Escape closing each.

## Process findings

* **ONE SUBAGENT PER STORY, EACH IN ITS OWN WORKTREE.** Every story ran in
  its own git worktree with its own test database (`DATABASE_NAME`) and
  `_build`, up to three in parallel on a 4-core machine, while the
  orchestrating session integrated by cherry-pick. It worked, and it
  brought the defects below. Concurrent suites caused 60 s timeouts
  (`ApiV1IdRangeTest`) and a log-noise event in coverage runs, never seen on
  CI. Carry forward: a parallel build caps itself at the machine's
  headroom, and a timeout seen only under local load is read as load before
  it is filed as a flake.
* **A GATE-SCRIPT TEST FLIPS `core.bare` IN A LINKED WORKTREE.** When the
  hooks ran in a linked worktree, `scripts/test_check_invisible_unicode.py`
  set `core.bare` in the shared `.git/config`, twice. The worktree commits
  then ran with `--no-verify`, and every hook ran on the main checkout before
  each push, so no unchecked commit reached CI; the S2 line is on #1364.
  Carry forward: the test sets `GIT_DIR` to a throwaway repository (#1364's
  line), fixed before agents commit in worktrees again.
* **THE GETTEXT CATALOGUES WERE THE MAIN SOURCE OF MECHANICAL DEFECTS.**
  Integrating several stories' German catalogues by hand let a fuzzy-matched
  msgid keep an old German text, and the merge script dropped the file's
  final newline, the sprint's one red CI run (pre-commit on `36d1fda`, fixed
  by the next push). Sprint 21 carried forward that a `.po` resolver replays
  every msgstr change; this one still did not. A guarded push script now
  refuses unless every gate is green on the exact head. Carry forward: a
  gettext merge tool that unions the stories' msgids, keeps each changed
  msgstr, refuses a fuzzy match and keeps the final newline, used for every
  catalogue integration.
* **A WORKTREE COMMIT TRACKED THE `deps` SYMLINK.** A subagent's commit
  included the shared `deps` symlink, and cherry-picking it replaced the
  main checkout's `deps` with a self-symlink for about two minutes. It is
  Sprint 21's history accident again, in a new place. Carry forward: the
  worktree's `deps` and `node_modules` links are in its local exclude file,
  and the integration refuses a commit that tracks a symlink.
* **TWO STORIES' FIRST COMMITS HELD ONLY A RED TEST.** They were folded, so
  every commit passes the gates on its own, with the red output in the
  commit body. Carry forward: a story brief says it in its first lines, and
  the integration checks it before a cherry-pick.
* **FORCE-PUSH WAS REFUSED IN AUTO MODE, SO HISTORY WENT FORWARD ONLY.** The
  session's auto mode refused a `--force-with-lease`, so the R groups sit in
  build order (R1, R2, R6, R7, R5, R8, R4, R3, R9, R10), the second
  search-budget commit after R7, and every later fix is a commit of its own.
  The sprint workflow's history cleanup could not run. Carry forward: the
  plan names the build order it expects, and a reorder is asked for before
  the push that would need it, not after.
* **A UI CHANGE SHIPPED WITHOUT A BOARD.** R5 added two exclusion sentences,
  on Income and on the Overview, without a board; the close-out records it
  as a finding. A sentence is a UI change. Carry forward: the next story on
  those screens puts both sentences on a board.
* **THE SEVERITY RULE HELD.** The closing acts reviewed their diffs, each
  lens ranked what it found, the regressions were counted apart, and an
  older S1 was still filed (#1370, #1371). Four filings instead of 96, with
  the defects that mattered found (the two S2 regressions above). Carry
  forward: nothing; the rule stays.

## Two-way coverage

- **Due by the end of Sprint 23:** the human view of R6's two reads
  (`GET /splits/incomplete`, `GET /transactions/rate_only`) and of A4's flow
  list in the depot and security merge previews (#957, no screen yet).
- **Standing:** U2, the audit journal viewer, recorded since Sprint 19.

## Maintenance

The sprint PR's version report, `version-report-2026-11-01-sprint22.md`,
stands for the sprint: the stacked PR moved no dependency (`mix.lock`,
`mcp-server/package-lock.json`, `.github/pre-commit` and the Dockerfiles are
unchanged between `d715e76` and `d4c6156`).

## Carry-forwards for Sprint 23

1. **The gate-script `GIT_DIR` fix on #1364** (the S2 line:
   `scripts/test_check_invisible_unicode.py` flips `core.bare` in a linked
   worktree), before agents commit in worktrees again, so worktree commits
   run their hooks.
2. **A gettext merge tool** for integrating several stories' catalogues
   (union of msgids, every changed msgstr kept, no fuzzy match, the final
   newline kept).
3. **#1371's decision**, the owner's (`needs-decision`, answer (b)
   recommended); #1370 (S1) beside it.
4. **The human views of R6's two reads and A4's flow list**, due by the end
   of Sprint 23; a missing view is that close-out's finding.
5. **Lane I's later pages** under board 01: the Wealth Allocation tab, the
   security detail, Snapshots, Tax, Views and the rest, with #1339 from
   #1366.
6. **#1115, the MCP SDK v2 move**, in Sprint 23's maintenance lane, before
   v1 support ends on 2027-01-27.
7. **R5's two sentences** on a board when Income or the Overview is next
   touched.
8. **#1368 and #1369** (S2, quote-only figures), and the polish lists'
   lines when a story touches their screen.

## Close-out ledger

- Closes by keyword: 25 on #1367, 14 on #1372, one "Closes" line per issue.
- Filed: #1368, #1369, #1370, #1371.
- Ideas: I1 and I14 `built`; I15 dropped by the plan's D-7.
- Merges and releases: PENDING on the owner; the next planning PR records
  them.
- Open issues, reported and not judged: 70 on 2026-11-02 (66 after Lane Z
  plus the four filed); 31 after both merges' keywords.
