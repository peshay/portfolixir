# Sprint 23 Retrospective — the debts that fell due: two S1s, the views the agent got first, the MCP SDK move and the rest of I1 (2026-11-03)

ADR-0026 step 5 for Sprint 23, written by the implementation session as the
stacked PR's last commits (sprint workflow §5), after the sprint PR's merge
and before the stacked PR's. The plan, `sprint-plan-2026-11-02-sprint23.md`,
was adopted by the merge of its planning PR, which signed ADR-0053's
amendment of 2026-11-02. The close-out entry with every criterion and count
is in `sprint-status.yaml`; this file keeps what the sprint teaches.

## What shipped

Two PRs under the plan's D-6, each merged by the owner's button, in order.

- **The sprint PR #1377** (`agent/claude/sprint-23`, 42 commits, promoted
  2026-11-03 at about 02:02 UTC, merged by the owner's rebase at 06:11 UTC;
  `main` at `6687a5a`, CI green in every job; release **2026.11.6**), five
  closes, each verified closed:
  - **Lane E**, the worktree build: E1 (#1364's S2 line: the gate-script
    test no longer flips `core.bare` in a linked worktree), E2 (a gettext
    merge tool), E3 (the worktree's links in its local exclude file, and a
    pre-commit hook that refuses a commit tracking a symlink).
  - **Lane M**, the maintenance lane: M1 (#1115, the companion on
    `@modelcontextprotocol/server` 2.4 with `@modelcontextprotocol/node`),
    Elixir 1.18.6, `version-report-2026-11-02-sprint23.md`. Dependabot's
    #1346 declined with its findings and closed; #1347 closed as
    superseded.
  - **Lane R**, the S1s and S2s: R1 (#1370, ADR-0053's dated note), R2
    (#1371, ADR-0053 amended: an edit of a stored-cash trade's figures
    states its cash, and the read-only check `cash_mismatch` lists the rows
    edited before), R3 (#1368) and R4 (#1369), both under ADR-0010.
    Contract entry 23.
- **The stacked PR #1379** (`agent/claude/sprint-23-ui`), rebased onto
  `main` after #1377's merge (38 commits, the tree byte-identical before
  and after) and retargeted to `main` before the owner's merge was asked
  for, as D-6 newly required:
  - **Lane V**, the views the agent got first: V1 (the Overview's three
    ledger findings and `/transactions?dq=`), V2 (the flow list in both
    merge previews, #957's human view), V3 (U2, the audit journal page).
  - **Lane C**, the owner's two reports of 2026-11-02: C1 (the ⓘ panels
    close one another and on a click elsewhere, pinned by the repository's
    first browser test) and C2 (board 04's rule C: the accent marks
    controls only, one green and one red).
  - **Lane I**, I1's later pages under one board commit: Wealth's
    Allocation tab, Income, Snapshots, the security page, Tax, Views, Risk,
    Classifications and Imports. Nothing was cut.
  - Commits: <<FILL: #1379's final commit count>> against an estimate of
    about 53.

## What went well

* **THE STACKED PR WAS RETARGETED BEFORE THE MERGE WAS ASKED FOR.** Sprint
  22's #1372 merged into its dead stacked base, so its commits and its 14
  keywords missed `main` until #1373 reopened them. This time #1379 was
  rebased onto `main` with `--force-with-lease` and retargeted to `main`
  as soon as #1377 merged, the tree byte-identical before and after. The
  step D-6 made explicit was done as written.
* **EVERY COMMIT RAN ITS HOOKS.** Lane E fixed the gate-script test that
  flipped `core.bare` (Sprint 22's reason for `--no-verify`) before any
  story ran in a worktree. R1, R2, R3, R4, Lane M's bumps and every
  stacked story were built in linked worktrees made by
  `scripts/worktree.sh`, M1 in a plain `git worktree add`; the shared
  `.git/config` kept `core.bare=false` throughout. No `--no-verify` in the
  sprint.
* **THE TWO-WAY CHECK RECORDS NOTHING, FOR THE FIRST TIME SINCE SPRINT
  19.** R6's two reads, R2's new read, A4's flow list and the journal all
  have their screen; the journal read had waited for one since before
  Sprint 19.
* **THE SDK MOVE CHANGED NOTHING AN AGENT DEPENDS ON.** A golden file
  captured from the v1 build over stdio was committed before the move;
  on v2 every tool, prompt, answer and the handshake are byte for byte the
  same, two protocol refusals excepted, which contract entry 23 states.
  The schema budget measured below the unchanged ceilings.
* **THE PLAN'S ESTIMATE HELD.** #1377 took 42 commits against about 39;
  #1379 <<FILL: its final commit count>> against about 53. The build order
  D-6 named mostly held: Lane M's two commits sit after R1 because R1
  finished first, and history stayed forward only.
* **THE JUDGMENT CALLS WENT TO THE OWNER, NOT INTO THE CODE SILENTLY.** The
  calls made inside the signed decisions (R2's rounding allowance, the
  cash-only check, R1's refusal of a time not in HH:MM) were put in #1377's
  briefing, each flippable by a comment.

## What did not go well

* **BOTH S1s WERE FOUND BY LENSES WALKING THE SCREEN, NOT BY THE STORIES'
  TESTS.** On #1377 the drawer kept a derived cash after a figure was
  changed and changed back, so a date-only save replaced the broker's
  cash. On #1379 V1's rate-only hint showed the amount including fees for
  a field that takes it before fees, so following the hint booked 1.869,80
  instead of the agent's 1.864,90. Both were fixed before promotion, and
  both sat in exactly the place a test that only checks what is rendered
  does not reach: what happens when the operator does what the screen says.
* **THE CONTAINER RESTARTED MID-SPRINT** and stopped a fix agent during its
  gates. It resumed from its transcript and nothing was lost, but only
  because the work so far had been committed.
* **BACKGROUND GATE MONITORS STALLED TWICE** in integration agents; the
  orchestrator had to ask for the gates to run in the foreground.
* **TWO PARALLEL AGENTS WROTE THEIR COMMIT MESSAGES TO THE SAME SCRATCHPAD
  FILE**, so one commit took the other's message. It was caught and amended
  before the push.
* **A FLAKY TEST TURNED CI RED ONCE, AND A FLAKY BROWSER TEST WAS FOUND
  ONLY AT INTEGRATION.** An async FX test turned #1377's head `7f116cf`
  red; it was fixed by a commit, not a re-run. C1's listener race (opening
  a panel by Enter while another's toggle was queued closed the new one)
  made the browser test flaky, 6 runs in 10; fixed, it passed 15 in 15.
* **THE FIRST BROWSER TEST RUNS OUTSIDE CI.** C1's test (`mix test
  test/browser --only browser`) is excluded from CI because CI installs no
  browser, so D-1's criterion 5 passes with that note.
* **AN S2 OLDER THAN THE SPRINT NEEDS A DECISION.** A journal `delete`
  entry's `after` repeats the deleted record; V3 checked it against
  ADR-0017, as D-8 asked, and filed it as #1378 because the fix is an
  amendment, not a small change.

## Two-way coverage

- **Due by the end of Sprint 23, landed:** R6's two reads (`GET
  /splits/incomplete`, `GET /transactions/rate_only`) and R2's
  `GET /transactions/cash_mismatch` in V1; A4's flow list in both merge
  previews in V2.
- **Standing since Sprint 19, landed:** U2, the audit journal, in V3.
- **New and agent-only this sprint:** none. Nothing is recorded.

## Maintenance

`version-report-2026-11-02-sprint23.md`, on `main` via #1377: M1 and
Elixir 1.18.6 taken; Sobelow 0.18 (#1346) and `decimal` 3.2.0 declined with
their reasons. The BMAD `tea` module is two majors behind (v1.27.2 against
v3.6.0), missed by Sprints 20 to 22; the report names it for Sprint 24's
planning.

## Carry-forwards for Sprint 24

1. **Commit before a long gate run**, so a restart of the container loses
   nothing that was not yet committed.
2. **An integration runs its gates in the foreground**, not behind a
   background monitor that can stall.
3. **A story's scratch files live in its own worktree or a story-named
   path**, never a shared scratch file another agent can overwrite.
4. **A story that adds a remedy hint tests it by following it literally**,
   and a drawer field's prefill is tested through a change and its
   reversal: the two places this sprint's S1s were found.
5. **Decide in Sprint 24's planning whether CI installs a pinned Chromium
   for `test/browser`**, or the closing act runs the browser tests by rule.
6. **The BMAD `tea` module**, two majors behind, in Sprint 24's
   maintenance lane.
7. **#1378** (S2, a journal delete entry's `after`), which needs an
   ADR-0017 amendment.
8. **I7's answer**, the owner's: is the security page the dossier's human
   view, or a new screen? The next plan builds the answer given.

## Close-out ledger

- Closes by keyword: 5 on #1377 (#1370, #1371, #1368, #1369, #1115), all
  verified closed; on #1379, <<FILL: its Closes lines, or "none">>.
- Closed by hand: #1346 (declined with its findings), #1347 (superseded).
- Filed: #1378.
- Ideas: I1 and U2 `built`; I7 `discussing`; I16 `triaged`.
- Merges and releases: #1377 merged, release 2026.11.6; #1379 PENDING on
  the owner, recorded by the next planning PR.
- Open issues, reported and not judged:
  <<FILL: the open count read through the API>>.
