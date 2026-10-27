# Sprint 21, amended — the security batch builds first, Sprint 21's plan after it

**Status: ADOPTED by the merge of this planning PR.**
The merge is the signature (ADR-0026 step 1, as amended on 2026-10-08). This
document amends
[`sprint-plan-2026-10-09-sprint21.md`](sprint-plan-2026-10-09-sprint21.md),
which stays adopted and stays the authority for everything this document
does not move. It adds one lane, **S**, the fix batch of the adopted
[security review triage of 2026-10-12](../planning-artifacts/security-review-triage-2026-10-12.md),
and recuts the sprint into three pull requests. A fresh implementation
session builds all three.

## What you need to do

1. **Merge, to adopt:**
   - **S builds first, as the sprint PR** (D-1, D-2). Sprint 21's α and β
     follow as the first stacked PR and γ as the second (D-3).
   - **Seven moves between the two plans** (D-4): four Sprint 21 items join
     the security group that already folds in their issue, and two
     security rows join the Sprint 21 story that rewrites the same code.
   - **The design picks Q1 onwards** on the security boards (D-8). Silence
     adopts each recommendation; a comment naming another variant changes
     it.
   - **The idea list and its rule** (D-11): a new planning artifact, an
     amendment of ADR-0042, and one rule in the sprint workflow.
2. **Two answers are already yours, given by your merge of #1238 without a
   comment:** T-19 (a cross-currency trade sent with only a settlement rate
   is refused until it carries an amount) and T-21 (a split scales every
   open lot of the security's FIFO queue, in the matcher, with no new
   bookings). Both change money figures, so this plan names them once more.
   A comment here before the implementation session starts flips either.
3. **When you start the implementation session,** attach the review's
   evidence package to its first message, as the triage's Part 6 and the
   handover say. It never enters the repository (D-6). The kickoff prompt is
   in this PR's description.
4. **Keep holding the live correction** (Sprint 21's ask 3) until the
   **first stacked PR** merges, because that PR now carries α7 (#1194,
   #1205). Not a question.

**Not asked:** everything else. Each decision below carries its reason and
flips by a comment.

**Verification basis:**

- **`main` and CI:** `main` at `35665ea`. CI 1798 and Commit authorship 812
  on it are green. The T-11 hotfix (Bandit 1.14.0, `plug_crypto` 2.2.1,
  `decimal` 3.1.2 and the companion's npm locks) is on `main`, and its
  merge made a calendar release.
- **Sprint 21 was planned and not built.** No sprint branch and no build PR
  exist. Its Lane Z ran at its merge: #1182 and #1190 are closed, and its
  filings are open on the tracker.
- **The open-issue list of 2026-10-27:** 91 open: 82 `agentic` (three of
  them also `needs-decision`), 1 `needs-decision` alone (#1177), 6
  trackers, 2 `needs-uat`. Five Dependabot pull requests are open (#1232,
  #1233, #1234, #1235, #1237).
- **The review was run against `2171847`,** the Sprint 21 planning head.
  Every file the triage's rows name is unchanged on `main` except
  `mix.exs`, `mix.lock` and the companion's lock file, which the hotfix
  moved.
- **The overlaps in D-4 were read in both plans and in the code** they
  touch: `TradeMatcher`, `Ledger.SettlementGuard`, the import applier's dry
  run, `CappedAsync`, the booking drawer, the Imports page's mapping rows,
  the merge previews and the release workflow.

## State of play, in five lines

1. **Sprint 21 has waited eighteen days for its build,** and the security
   review ran in that window against Sprint 21's own planning head.
2. **The review found nothing critical or high.** Four medium findings share
   one class, what the listener accepts before any credential is checked,
   and their fixes are configuration and bounds (triage Part 0 §2).
3. **The two plans meet in seven places** (D-4). Building them as two
   sprints in two sessions would rebase one onto the other's rewrite of
   the same functions.
4. **The money lane changes meaning in two places the review also
   touches:** the settlement guard (α1 and H35) and the FIFO queue (α3 and
   K09). Each pair is ordered in D-5.
5. **The idea list starts here** (D-11), because two of the ideas raised
   while this plan was written (simulation accounts, a process switch)
   touch what this sprint builds.

## D-1: why the security batch builds first (recommended)

- **Severity.** The four medium rows (H01, H02, H58, and T-12's listener
  bounds behind H27) sit on the unauthenticated listener or kill the
  Imports page on an ordinary export. Every one is a bound or a
  configuration line, so they cost hours, not days.
- **The ledger's shape.** T-20 (lock order), T-19 (H35) and T-21 (K09)
  decide how the ledger locks and what the FIFO queue scales. α builds on
  both. Building them first means α's identities are pinned once, on the
  final shape.
- **The gates.** H63 splits the live-feed audits out of the quality job, so
  a new advisory turns one check red instead of silencing Credo, Sobelow,
  Dialyzer and the companion's tests. Every later push in this sprint
  benefits.
- **The triage's Part 6 holds either way.** A reproduction test becomes a
  regression test in the same push as its fix, never before it (D-6).

**To flip by comment:** "α first". Then S becomes the first stacked PR and
the order of D-5's pairs reverses.

## D-2: Lane S, the security batch (risk tier where the triage says so)

The rows are the triage's Part 3; this plan copies none of them. Each row
is built test-first: its reproduction test from the evidence package is
promoted into the suite, run red, then the smallest fix turns it green
(story workflow; triage Part 1, "Verification").

**Order inside the sprint PR:**

1. **S0, the gate order (H63), one commit.** The live-feed audits move to a
   job of their own, so the rest of the sprint runs every deterministic
   gate on every push.
2. **S-medium: H01 (T-13), H02, H58, H09 with T-12.** Four commit groups,
   the triage's "they ship first".
3. **S6, the audit trail and integrity (risk tier).** Two commit groups,
   each with its own verification pass:
   - **S6a, lock order (T-20):** the lock-order table first (Sprint 21's
     D-7, now written here), then #1214 (Sprint 21's α10, moved), H60 and
     H54, each checked against every row of the table and pinned in both
     orders by the lock-race harness;
   - **S6b, money and integrity:** H35 (T-19, refuse), K09 (T-21, the
     matcher), K11, K07, K17, H44, K14, K10, H17, H10, H61 and H62 (T-16).
4. **S1, credentials, sessions and the perimeter (risk tier):** with #1202
   and its docs (Sprint 21's β6, moved; T-17 decides the floor stays a
   length check and the boot warns).
5. **S4, input bounds and cost:** the rest of S4, with #1204's wrapper
   inside `CappedAsync` (Sprint 21's β7, moved) before K08, because K08
   runs the background walks under the heap cap and #1204 decides what a
   capped load reports when the cap fires. The design issue T-18 names is
   filed here.
6. **S5:** H54 has moved to S6a and H53 to α9 (D-4); H56 and H57 remain.
7. **S2, S3, S7,** in that order. S2 changes the deployment guide and the
   companion guide in both languages.
8. **S8:** the rest, with #1189 (Sprint 21's β4, moved) and #1218 folded
   in, as the triage's Part 2 rules.
9. **S's closing act** (D-9), then the record: the triage's Part 7 lists
   every row with its status and the commit that carries it, and
   `SECURITY.md` gains the line naming this batch the third hardening
   baseline. H53 and H45 read "rides α9" and "rides γ7"; the close-out
   completes their lines.

**Issues.** The triage's Part 5 work ledger is filed at branch opening: one
tracker issue per group (two for S4), thin pointers to the triage's rows,
each under its area parent after a title search. Each closes by keyword
with its group. A row deferred by the shrink order (D-10) gets its own
issue and its Part 7 line says so.

**Refuted rows** (H24, H29, H48, K15) get no build. H24's one-line
correction of the architecture document rides S7.

## D-3: three pull requests (standing rule, stated with its count)

| PR | Branch | Commit groups | Estimate | Why this order |
|---|---|---|---|---|
| **sprint PR** | `agent/<provider>/sprint-21` | Lane M, Lane S and the four items moved into it, S's closing act | about 80 | the listener bounds and the ledger's lock order and FIFO shape land first (D-1) |
| **stacked PR 1** | `agent/<provider>/sprint-21-money` | α (without α10) with H53 in α9, β (without β4, β6, β7), their closing acts | about 58 | Sprint 21's money fixes, on the final ledger shape |
| **stacked PR 2** | `agent/<provider>/sprint-21-ui` | γ with H45 in γ7, its closing act, the close-out | about 65 | the screens build on α's drawer and labels, as Sprint 21's D-8 says |

About 200 commits in all, each PR under the 90 that GitHub's rebase merge
allows. Each stacked PR opens on the head of the one before it as soon as
that one's closing act is done, and its base moves to `main` when the one
below merges. You merge all three in order, each by rebase, and each merge
makes a calendar release.

**Contract entries renumber:** entry 18 is the sprint PR's (S's changed
answers and fields: H30's and H31's 422s, K17's page cursor, K11's preview
fields, K07's income basis, K12's and H14's author fields, H13's hints,
#1214's retryable answer); entry 19 is stacked PR 1's (Sprint 21's α and β
list, without #1214); entry 20 is stacked PR 2's (#1210's Costs total).

## D-4: the seven moves (recommended; each flips by naming its item)

| Item | From | To | Why |
|---|---|---|---|
| **#1214** (α10) | α | S6a | T-20 folds it in: the same lock-order class as H60 and H54, one table, one verification pass |
| **#1202** (β6) | β | S1 | T-17 and H20 answer the same question; the docs, the boot warning and ADR-0045's dated note land together |
| **#1204** (β7) | β | S4 | K08 runs the background walks under the heap cap; #1204 decides what a capped load reports, so it lands first |
| **#1189** (β4) | β | S8 | the triage's Part 2 folds it into S8's workflow-file group |
| **#1218** | backlog | S8 | the same; the CI database image moves to an authenticated or mirrored pull |
| **H53** | S5 | α9 | α8 (#1195), α9 (#1203) and H53 all rewrite the import preview's dry run; α9's in-memory simulation of the run's creations is the basis H53's lock-free dry run needs, so one commit group builds both after α8 |
| **H45** | S4 | γ7 | the Imports page's mapping rows are γ7's surface on board 07; the shared picker is drawn on top of board 07's adopted state (D-8) |

**What does not move:** the triage's group labels. A row's Part 7 line
names the group it shipped in.

## D-5: where the two plans touch the same code (standing order)

| Pair | Order | What the second one must keep |
|---|---|---|
| H35 (S6b) and α1 (#1199) in the settlement guard | H35 first | α1 adds its refusal beside H35's, on the same insert-and-update triggers; neither weakens the other's 422 |
| K09 (S6b) and α3 (#1198) in `TradeMatcher` | K09 first | α3's identity 4, the diff of every payload, is taken on K09's head, so it shows α3's change alone |
| K11 (S6b) and α3 | K11 first | the merge preview's realized figures go through the same matcher; α3's unavailable state appears in the preview's after-figure, named |
| K10 (S6b) and α6 (#1052, #1206) in the booking drawer | K10 first | α6's kind select is drawn without a split kind (board Q-K10 on top of board 03's N12) |
| H58, H59 (S-medium, S4) and α5 (#1188) in the two parsers | H58, H59 first | K25's hash list is taken on their head; every stored hash stays byte-identical |
| H07, H08 (S4) and α7, α8 on the parked preview | S4 first | α7's correction lines and α8's release survive a remount from the parked state |
| H38 (S3) and γ2 (board 02) on a security's page | H38 first | γ2's redraw keeps the upload control of H38's board |

## D-6: the evidence stays out of the repository (standing; triage Part 6)

- The evidence package (reproduction tests, verdicts, the private report)
  is attached by the owner to the implementation session's first message,
  unpacked into the session's scratch directory, and never copied into the
  repository, an issue, a PR text or a commit message.
- **A reproduction test enters the repository only in the push that also
  carries its fix,** as a regression test with a user-story comment, red
  first in the commit order. No push ever carries a red reproduction
  alone.
- Commit messages, PR bodies and issues name the identifier, the class and
  the fix, never a path to the weakness, a payload, a threshold or a request
  sequence. The closing act greps the branch's PR text and messages for
  them, as the audit's own verification did.
- The private report is filed or discarded by the owner after the sprint
  PR merges (handover, step 5).

## D-7: Lane M (always present)

- **Node 26 is taken:** it becomes LTS on 2026-10-28, and Sprint 21's
  Lane M deferred it to the first sprint that runs on or after that date,
  which this build does; a session that starts earlier takes it on that
  date. One commit
  across the four pinned places, with `@types/node` 26 (Dependabot #1234 and
  #1232 close with it).
- **The other Dependabot bumps** ride Lane M with the full check list:
  `phoenix` 1.8.16 (#1237), `phoenix_live_view` 1.2.13 (#1235), the
  pre-commit group (#1233). A bump that fails a gate is dropped, named in
  the briefing, and its PR stays open.
- **The version report** runs before S's closing act, as Sprint 21's Lane M
  says, and re-checks the T-11 hotfix's three locks.

## D-8: the design picks Q (recommended; silence adopts them)

**The security rows that change rendered output get boards** on this PR,
under `planning-artifacts/design-language/mockups/ux-design-2026-10-27/`,
argued in
[`ux-design-2026-10-27-sprint21-security.md`](../planning-artifacts/ux-design-2026-10-27-sprint21-security.md).
The pick letter is **Q**.

<!-- PICKS-TABLE -->

## D-9: the closing acts (standing, Sprint 21's D-13 extended)

| Group | Lenses |
|---|---|
| **S** | correctness hunter; **a security re-check lens** per group: every promoted reproduction test passes, no gate was weakened (`.sobelow-skips` unchanged, no skip tag, no deleted test, no raised ceiling), and the fix did not widen scope; **the lock-race lens** over S6a against the lock-order table; **a money lens** over H35, K09, K11 and K07, one identity at a time; a **design critic** against the Q boards in German at 390 and 1200 px, light and dark; an **agent lens** over K17's paging and H13's hints through the companion |
| **α, β** | Sprint 21's D-13 rows, unchanged, with α9's group adding H53's lock-free dry run to the edge-case hunter |
| **γ** | Sprint 21's D-13 row, with γ7's design critic checking H45's picker against its Q board |

## D-10: shrink order (cut from the top; name the cut in the briefing)

1. Sprint 21's shrink order, steps 1 to 5, unchanged.
2. **S's informational hygiene rows,** in this order: K05, K04, H66, H68,
   H10. Each cut gets an issue and a Part 7 line reading "deferred".

**What does not shrink:** Sprint 21's list, plus every medium row, S6a and
S6b, S1, and S's closing act.

## D-11: the idea list starts with this PR (recommended)

**What lands:**

- [`planning-artifacts/ideas.md`](../planning-artifacts/ideas.md): every
  idea that is not yet shaped enough to build, harvested from the
  repository's planning artifacts and the open issues, each with a kind
  and a status. Its first entries include the owner's ideas of
  2026-10-20 to 2026-10-27.
- **An amendment of ADR-0042** that admits the list as the stage *before*
  the registry: an idea lives there until it is worked out, then moves into
  `epics.md` or an issue and its line becomes a pointer. *Why:* ADR-0042
  exists because two structures claiming the same job drifted apart; a
  list that holds only unshaped ideas claims no job the registry has.
- **One rule in the sprint workflow** ("Ideas"), and one line in
  `AGENTS.md` that points to it.

**What it changes for a planning session:** it reads the list, proposes at
most one idea to work through with the owner, and may pull a `no-brainer`
straight into its plan.

## D-12: the review seed (Sprint 21's D-14, extended)

Each S story that draws on a page adds its shape to the review seed in the
commit that builds it: an agent-renamed rule, an agent-recorded tax
statement, a security merge whose two sides both closed trades, an income
booking without a rate path, and a split held across two portfolios. The
seed stays synthetic, and a second run leaves every row alone (#1126).

## Sequencing

```text
after the merge ── Lane Z: sprint-status, the ideas list's first triage
sprint PR opens ─▶ Lane M ─▶ S0 (H63) ─▶ S-medium (H01, H02, H58, H09)
                   ─▶ S6a (table ▶ #1214 ▶ H60 ▶ H54) ─▶ S6b
                   ─▶ S1 (+ #1202) ─▶ S4 (+ #1204 ▶ K08) ─▶ S5 ─▶ S2
                   ─▶ S3 ─▶ S7 ─▶ S8 (+ #1189, #1218)
                   S's closing act ─▶ Part 7, SECURITY.md ─▶ promoted
stacked PR 1 ────▶ (on the sprint PR's head) α1 … α9 with H53, α11; β
                   α's and β's closing acts, round trips 1–5 ─▶ promoted
stacked PR 2 ────▶ (on stacked PR 1's head) γ1 … γ8 with H45 in γ7
                   γ's closing act ─▶ close-out records ─▶ promoted
the owner ──────── merges the three in order (three releases)
```

## What "done" means for this sprint

Sprint 21's "done" list holds, with these changes:

1. **All three PRs are merged in order,** each green on its head, each with
   its closing act and its briefing.
2. **Every row of the triage's Part 3 has a Part 7 line:** shipped with its
   commit, or deferred with its issue. No medium row and no risk-tier row is
   deferred.
3. **Every promoted reproduction test was red before its fix** in the
   commit order and is green at the head, and no gate was weakened.
4. **`SECURITY.md` names the third hardening baseline,** and the deployment
   guide and `SECURITY.md` say what S1 and S2 made true, in both languages
   where a German mirror exists.
5. **Contract entries 18, 19 and 20** name what changed (D-3).
6. **Sprint 21's D-1 criterion 4, the count,** keeps its threshold: fewer
   than 60 open issues at the close-out. S files about ten issues and
   closes them with their groups, and #1218 closes, so the arithmetic of
   Sprint 21's plan stands.
7. **The idea list exists,** ADR-0042 carries its amendment, and the
   close-out moves each idea this sprint built to `built`.
