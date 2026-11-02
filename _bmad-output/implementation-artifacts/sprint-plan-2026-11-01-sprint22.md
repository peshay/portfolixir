# Sprint 22 — severity first: the eleven S1s, the twenty S2s, and the explanations out of the way

**Status: ADOPTED by the merge of the Sprint 22 planning PR.**
The merge is the signature (ADR-0026 step 1, as amended on 2026-10-08). A
fresh implementation session builds it on `agent/<provider>/sprint-22`, as
one sprint PR and one stacked PR (D-7). This is the first plan written
under [ADR-0026's amendment of
2026-11-01](../../docs/decisions/0026-epic-batch-workflow.md) (idea I14),
which this PR carries: every finding carries a severity, and a closing act
reviews its diff.

## What you need to do

1. **Merge, to sign the rule change and four risk-tier decisions:**
   - **I14, the severity rule** (D-2):
     [ADR-0026, amendment of 2026-11-01](../../docs/decisions/0026-epic-batch-workflow.md),
     with `AGENTS.md`'s "Stay in scope" and the sprint workflow's §3 in
     their new words. This sprint's own closing acts already run under it.
   - **[ADR-0003](../../docs/decisions/0003-decimal-for-money.md), amended
     2026-11-01:** a write refuses a JSON number in a financial field with
     a named 422 (#1291). Hand-written clients that send numbers get an
     error instead of a silently rounded value.
   - **[ADR-0050](../../docs/decisions/0050-lifecycle-merges-under-a-reimport-contract.md),
     amended 2026-11-01:** the import preview names a row already imported
     into **another** portfolio and holds it back by default; you can
     include it deliberately (#1313, board 03, pick Q2).
   - **[ADR-0015](../../docs/decisions/0015-cross-currency-settlement-fx-rate.md),
     amended 2026-11-01:** a cross-currency row stored without its
     settlement legs is corrected in the currency it is stored in, never
     re-booked as USD in place (#1335).
   - **Income reads the withheld tax on interest as it does on dividends**
     (#1309, D-5): an interest row booked with taxes reads gross = net +
     tax. Today the stored tax is never counted.

   Each of the four changes how a stored money figure is booked, corrected
   or read, so each is yours (ADR-0026's two-PR amendment, item 4). Each
   carries the recommended answer from its issue; a comment before the
   implementation session starts flips any of them.
2. **Your merge is also the go for the registry pass (Lane Z, D-4)**, which
   this planning session runs right after the merge: twelve "Polish:
   <screen>" trackers created, 53 S3 issues moved onto them and closed by
   hand with a pointer, seven issues closed with their evidence. Sprint
   21's bulk issue writes were refused without such a go; this sentence is
   it. A comment "no Lane Z" stops it.
3. **Nothing else.** After Lane Z this session starts the fresh
   implementation session itself, with this plan as its brief.

**Not asked:** everything else. Each decision below carries its reason and
flips by a comment. The announcement stays yours (Sprint 17's D-1) and this
sprint neither waits for it nor changes it.

**Verification basis:**

- **`main` and CI:** `main` at `ad2f052` (#1353's merge, idea I14), with
  CI 1825 and Commit authorship 839 green.
- **Sprint 21's three merges, as its close-out asked this plan to record:**
  #1296 fast-forwarded at 09:24 UTC on 2026-11-01 (release **2026.11.1**),
  #1318 at 09:32 (**2026.11.2**), #1344 at 09:46 (**2026.11.3**), each on
  your go in the session and each with CI green on its head. Three
  docs-only pushes followed (6d8a0f0, 5ada8a3 and ad2f052), none with a
  release, as docs-only pushes make none.
- **CI 1820 on `6d8a0f0` was red** in the `test` job, on a diff that
  touches only the close-out records. That is the flake class Lane F fixes
  first; the next two runs on `main` passed.
- **Sprint 21's two owner questions** were answered by your merges without a
  comment, so the builds' defaults stand: T-19 (a cross-currency trade sent
  with only a settlement rate is refused until it carries an amount) and
  A12 (a booking made by hand is "edited by hand" and the correction leaves
  it alone, #1318's decision 1).
- **The open-issue list of 2026-11-01:** 114 open: 95 `agentic`, 10
  `agentic` and `needs-decision`, 1 `needs-decision` (#1177), 6 trackers,
  2 `needs-uat`. Three Dependabot pull requests are open (#1346 Sobelow
  0.18.0, #1347 `@types/node` 26.6.6, #1348 `pre-commit-hooks` 6.0.0).
- **Every one of the 106 non-tracker, non-UAT issues was read with its
  comments and checked against the code on `ad2f052`** by four read-only
  triage passes (import and money; security, API and engineering; screens
  with figures and forms; layout and accessibility). Each got a severity
  under D-2's definitions, file:line evidence and a commit estimate. The
  result is the [severity pass](sprint-plan-2026-11-01-sprint22-severity-pass.md),
  one row per issue. Seven do not reproduce (D-4).
- **The boards this PR carries** were drawn on the review seed with the
  shipped `priv/static/app.css` (D-9).

## State of play, in five lines

1. **Sprint 21 is on `main`** in three releases, and its money, security and
   UI batches are built as signed. What it left is 96 filings.
2. **The filings are mostly not the sprint's own.** Of the 86 open filings
   from Sprint 21, 30 say outright that they predate it, and most of the
   rest name older code beside a story. The closing acts audited the code
   they passed, with no budget and no end (idea I14).
3. **The severity pass sorts them:** 11 S1, 20 S2, 61 S3, 7 that do not
   reproduce, 6 features. The S1s are real: a float crosses the API's money
   boundary (#1291), a gate checks 7 writers of 62 (#1269), a double booking
   the preview calls new (#1313), a drawer that re-books EUR as USD (#1335),
   four screens that print a wrong figure (#1316, #1331, #1274) or a tax
   they never count (#1309).
4. **I1 is worked out** (#1351, adopted 2026-11-01) and this PR carries its
   board.
5. **The flake is real:** CI 1820 failed on a docs-only diff. Its root cause
   is found (#1345: OTP's logger handler list races an async test).

## Why this cut

- **Every S1 and every S2 is built; no S3 is built on its own.** That is
  D-2's rule applied once to the whole backlog: an S3 goes onto its
  screen's polish list, and a story that touches that screen fixes its
  lines. Seven S3s ride a story because they sit in the function the story
  rewrites (#1307, #1272, #1271, #1293, #1337, #1350, #1342).
- **Money first, then the agent's surface and the screens.** The sprint PR
  carries the flakes, the maintenance lane and every S1 (risk tier); the
  stacked PR carries the API honesty S2s, the screen S2s, I1 and the
  close-out. The money fixes reach your instance with the first merge.
- **Both PRs stay under 90 commits** (D-7), so both merge with GitHub's
  "Rebase and merge" button and nobody fast-forwards by hand.

## Lanes

### Sprint PR (`agent/<provider>/sprint-22`)

**Lane F, the flakes (first commits, before anything else).** A red run must
mean what it says before a risk-tier lane runs.

| Story | Issues | What it does | Commits |
|---|---|---|---|
| F1 | #1345 | `log_noise_test.exs` becomes `async: false` with the reason in a comment: OTP's `logger_server` writes back a stale handler list on `remove_handler`, and ExUnit's capture server removes handlers while that file adds its own | 1 |
| F2 | #1268 | the crashing-provider test gets an explicit `timeout_ms` above its own budget; the capture runs after the same handler fix | 1 |
| F3 | #1273 | `settle/1` passes an explicit timeout to each `render_async` | 1 |

Proof: the suite runs green three times in a row in CI on the lane's head
(three pushes or three re-runs of the head, each recorded in the PR body).

**Lane M, maintenance** (the lanes' standing rule; a `version-report-*`
file): BMAD re-pinned to v6.12.4 or newer as the sprint branch's first
commit after Lane F, with the module set the manifest records (Sprint 21's
report deferred it here); Dependabot #1346 (Sobelow 0.18.0: taken only if
`mix sobelow --skip --exit` stays green without a new skip, else declined
with its findings), #1347, #1348; OTP 27.3.4.19 and the Debian date only if
a `hexpm/elixir` 1.18.5 image on them exists by then; `decimal` 3.2.0
(#1279) stays declined until its own reviewed bump. About 6 commits.

**Lane R, the S1s (risk tier: each its own commit group and verification
pass, ADR-0036).** Every story test-first with exact `Decimal` fixtures.

| Story | Issues | What it does | Decision | Commits |
|---|---|---|---|---|
| R1 | #1291 | every `/api/v1` write refuses a JSON number in a money, quantity, price, fee, tax or rate field with a 422 naming the field; contract entry 21; the API reference in both languages | ADR-0003, amended | 4 |
| R2 | #1269, #1272, #1271 | the write-actor gate's classifier accumulates instead of overwriting, so it reads all 62 writers; the writers it then flags are fixed in the same group (`Settings.put/2`/`delete/1` made private behind the journaled path; the page's logo update goes through the locked-security check) | none | 8 |
| R3 | #1306, #1305, #1307, #1219 | a JSON v1 `time` the parser cannot read is a named row error, never "no time"; a row missing its security is a row error at preview; a negative cash `amount` is named at preview with the right reason; a refused row whose booking exists says "bereits gebucht" and names it instead of "book it by hand" (board 03) | ADR-0053's refusal list gains the time row (dated note) | 9 |
| R4 | #1313 | the preview reads hashes across portfolios, names a row already imported into another portfolio and holds it back by default; identities X1 to X3 | ADR-0050, amended | 5 |
| R5 | #1310, #1311, #1317 | a trade with a lot or sale priced in a third currency reads `unavailable` with a reason of its own and `proceeds: null`; a zero-amount lot (a free allotment) is not counted "no rate"; the realized-gains `computation_basis` names the settlement-legs path | none (ADR-0015 point 3 already says unavailable) | 7 |
| R6 | #1292, #1290 | a read-only data-quality check lists stored split events that miss a portfolio holding the security, and a read lists the stored cross-currency trades with a rate and no amounts (T-19's rows), over the API and MCP, with a remedy sentence | none (reads only) | 6 |
| R7 | #1309 | Income reads the withheld tax on an interest row as on a dividend (gross = net + tax), coupons included; its computation basis and the API reference say so | D-5 (yours) | 3 |
| R8 | #1316, #1332, #1331 | one valuation rule on the security page and Wealth, ADR-0010's: a position without a quote is valued at its last trade price with its `price_source` named, so rows add up to the total, and a row the total leaves out is named beside it; a dividend's Brutto on the Transaktionen tab is cash + withheld tax (board 02) | none (conformance to ADR-0010) | 6 |
| R9 | #1274, #1293 | Income's drilled-year and per-position tables print native figures in their currency with the converted figure beside them; a year whose payments are all unconverted keeps its row (board 02) | none | 4 |
| R10 | #1335, #1337 | the drawer opens a legless cross-currency row in its stored currency with the backfill pointer; the sell preview prints "24,00 EUR" (board 03); identity L1 | ADR-0015, amended | 5 |

**Closing act of the sprint PR** (D-8): the money and idempotency lens, the
correctness hunter, a security lens on R1 and R2, the UAT persona's round
trips (X1 to X3, L1, R8's figures, R7's interest row) on the review seed.
About 10 commits of on-surface fixes.

**Estimate:** F 3, M 6, R 57, closing act about 10: **about 76**.

### Stacked PR (`agent/<provider>/sprint-22-ui`)

**Lane A, the agent's surface tells the truth (S2).**

| Story | Issues | What it does | Commits |
|---|---|---|---|
| A1 | #1254 | every capped list read outside the five delta reads carries `truncated` and echoes its `limit` | 6 |
| A2 | #1294, #1295 | the securities list breaks sort ties by id, so offset paging neither skips nor repeats; a delta read refuses `offset` beside a cursor | 4 |
| A3 | #1301, #1315 | a malformed `classification_id` beside `plan_id` is refused; `PUT /views/:id/buckets` and an unwrapped `PATCH /views/:id` honour `include_all=false` or refuse it | 4 |
| A4 | #957 | the merge preview lists the external-flow and time-weighted-return effects of a depot or security collapse | 5 |

**Lane U, screen S2s.**

| Story | Issues | What it does | Commits |
|---|---|---|---|
| U1 | #1299 | "Buchung erfassen" is offered on an instance with cash accounts and no depot, opening the cash form (board 03) | 2 |
| U2 | #1333 | two same-named accounts read with their portfolio's name on Accounts and in the history's account filter (board 03) | 3 |
| U3 | #1330 | the collapsed rail keeps its state across patches (a hook-held state, not a bare checkbox) | 2 |
| U4 | #1343 | a zero drawdown's sub-line names no peak, trough or recovery (board 02) | 1 |

**Lane I, the explanations out of the way (#1351, idea I1; board 01).**
Section method sentences into one ⓘ at the heading; short basis clauses
stay visible; data notes clamped and collected; problems always visible.
The first commit is the per-text classification table in `DESIGN.md`
(board 01's rule), then the shared parts, then the pages, Wealth first.
It absorbs #1350 (the view switcher's ⓘ as a popover) and carries #1336
(an ⓘ panel stays inside the viewport) and #1342 (Escape closes it; the
picker's hit count gets a live region), because they share the component.
About 18 commits.

**Closing act of the stacked PR** (D-8): the correctness hunter, the agent's
lens on Lane A, the design critic against boards 01 to 03 and the living
spec, the UAT persona over every page I touches. About 10 commits.

**Close-out** (the stacked PR's last commits): `sprint-status.yaml`,
`epics.md`'s dated reconciliation, the idea list (I1 and I14 `built`), the
retrospective, the version report. About 5 commits.

**Estimate:** A 19, U 8, I 18, closing act about 10, close-out 5: **about 60**.

### Lane Z — registry (this planning session, right after the merge)

See D-4. Nothing in Lane Z touches code.

## Decisions

### D-1: what this sprint is for, and its exit criteria (recommended)

The sprint builds every S1 and every S2 the severity pass found, and I1.
Its exit criteria:

1. **Every S1 closes by keyword** (11 issues), each with its identity
   pinned: R1's refusal per field family, R2's classifier reading all 62
   writers, X1 to X3, L1, and R8's rows adding up to the total.
2. **Every planned S2 closes by keyword** (20 issues).
3. **The built screens match boards 01 to 03**, by the design critic at 390
   and 1200 px, light and dark, in German.
4. **The regressions this sprint introduced are counted** apart from the
   older findings, and none of them is an S1 at promotion.
5. **The flake is gone:** no PR head of this sprint needs a re-run to turn
   green.

**No criterion counts open issues** (the sprint workflow's §3 as amended;
Sprint 21's retrospective). The count after Lane Z is reported, not judged:
66 open (the 39 issues this sprint builds, 7 that stay open, 2 `needs-uat`
and 18 trackers, 12 of them polish trackers). About 27 remain after this
sprint's keywords close its 39.

*Corrected 2026-11-01 by the implementation session:* this sentence first
read "about 27 open, of which 12 are polish trackers" for the count after
Lane Z. That was the count after this sprint's merges; the count after Lane
Z, recounted when Lane Z finished, is 66.

**To flip by comment:** name a criterion to drop or add.

### D-2: the severity rule, signed by this merge (recommended; idea I14)

[ADR-0026's amendment of 2026-11-01](../../docs/decisions/0026-epic-batch-workflow.md)
says it in full; `AGENTS.md` and the sprint workflow say it in their words.
In short:

- **S1:** a figure, booking, stored record or derivation can be wrong; a
  security boundary can be crossed; a gate silently checks nothing.
  **S2:** a defect met in normal use (a crash, a flow that cannot finish, a
  figure contradicted between two surfaces, an API answer that misleads, a
  flaky test). **S3:** polish.
- A closing act reviews its diff; a lens reports at most five findings,
  ranked; a re-check files nothing new unless it finds an S1.
- On the PR's surface, anything small is fixed on the branch. Off it, an
  S1 is filed always, an S2 is filed when the diff's code reaches it, and
  everything else goes onto its screen's polish list. Nothing is withheld.
- A polish list is one `tracking` issue per screen. A story that touches the
  screen fixes its lines; a polish pass takes a screen at a time under one
  test-first story whose functional test pins every line it fixes, written
  first and seen failing for each line's reason. An S2 keeps a red test of
  its own.

Of the three open questions on I14: **test-first in a polish pass** is one
functional test per screen, written first and red for every line (the
test-first rule holds; its unit is the screen); **where the lists live** is
the tracker, not the idea list (ADR-0042); **today's S3s** move onto the
lists in Lane Z (D-4).

The change is pinned by `test/portfolixir/workflow_docs_test.exs` ("a
finding carries a severity, and a closing act reviews its diff"), seen
failing first on this PR.

**To flip by comment:** "keep filing everything". The amendment, the two
rule texts and the test are then removed from this PR before the merge.

### D-3: the severity pass, and what it decided per issue (recommended)

[`sprint-plan-2026-11-01-sprint22-severity-pass.md`](sprint-plan-2026-11-01-sprint22-severity-pass.md)
has one row per issue: its severity and where it goes. The triage was
strict by design: a race that needs two concurrent writers on a
single-operator instance and changes no stored money is S3 (#1252, #1288,
#1304); a hardening with no reachable exploit is S3 (#1256, #1262, #1263);
a screen that prints a **wrong** figure is S1, one that only omits it is S2.
Two triage passes rated #1291 differently (S1 and S2); the plan takes S1,
because the stored value differs from the value sent, which is the drift
ADR-0003 exists to rule out.

**To flip by comment:** name an issue and its severity. An S3 raised to S2
joins the stacked PR if the budget allows (D-7), else the next sprint.

### D-4: Lane Z, the registry pass (recommended; your merge is its go)

Run by this planning session after the merge, one write at a time through
the issue tools:

1. **Twelve polish trackers**, labelled `tracking`, each under its area
   tracker: Imports (12 lines), Shell and global (7), Engineering and
   tests (7), Accounts (4), Classifications and targets (4), Securities (4),
   API and MCP (3), History and drawer (3), Merge pages (3), Overview (2),
   Cash flow and Income (2), Wealth (2). Each line names its issue, its
   one-sentence defect and its severity.
2. **The 53 S3 issues on those lists are closed by hand** as "not planned",
   each with one comment naming its tracker line. The issue's text stays the
   specification the line points at.
3. **Seven issues are closed with their evidence** (they do not reproduce or
   are done): #1253 (the composite foreign key of the first migration forbids
   its precondition), #1297 and #1298 (fixed by #1318, with tests), #971 (its
   measurement is on the issue; the fix is #925, now on the Imports list),
   #1258 (the cap is enforced, declared and tested; the missing API sentence
   is a line on the API list), #1275 (the name is capped at 255 characters),
   #1278 (fixed by K14, pinned by `account_dialog_all_or_nothing_test.exs`).
4. **Stays open, not planned, with the reason on the issue:** the features
   #894 (F21 on the idea list), #899 (the widening phase, your comment of
   2026-10-02), #900 (its own story after the launch), #1070 (an ADR-0050
   reading first), #1115 (the SDK v2 move, due before v1 support ends on
   2027-01-27: Sprint 23's maintenance lane); #1177 (two new ledger kinds,
   yours, on its trigger: a switcher's export); #1220 (fails closed,
   deferred by design); #328 and #354 (`needs-uat`); the six area trackers.
5. **The `needs-decision` label comes off** every issue this plan answers
   (#1219, #1291, #1309, #1313, and #1226, #1251, #1264, #1308, #1319 with
   their recommended answers recorded on their polish lines).

**To flip by comment:** "no Lane Z" (the severity pass then stands as a
document only), or name an issue to keep open.

### D-5: #1309, Income reads the tax on interest (recommended; yours)

An interest row booked with withheld taxes stores them (the API and the
drawer accept them), and Income reads interest as carrying no withholding,
so gross, tax and net disagree with the ledger. The two answers were: Income
reads the taxes (its basis changes), or the writes refuse taxes on interest.
**Recommended: Income reads them**, because a bank does withhold tax on
interest and on coupons, and refusing the field would make that booking
impossible to record. The computation basis, the API reference and the
contract say so; nothing stored changes. It is yours because it changes a
money figure the Income page and the API report.

**To flip by comment:** "refuse taxes on interest". R7 then refuses them on
every write path and the drawer drops the field for that kind.

### D-6: the valuation rule on screen is ADR-0010's (recommended)

ADR-0010 values a position without quotes at its own last trade price,
flagged by `price_source`, and Wealth's total counts it that way. The
security page's Bestände tab and Wealth's rows do not, so the rows and the
total disagree (#1316, #1332). R8 makes both screens follow ADR-0010 and
name the source; no ADR changes. A dividend's Brutto on the security page
follows Income's definition, cash plus withheld tax (#1331).

### D-7: two PRs, each under 90 commits, merged by your button (recommended; answers idea I5's merge question)

The sprint PR is estimated at about 76 commits and the stacked PR at about
60, each under ADR-0026's budget of 90, so both merge by "Rebase and merge"
on GitHub, which you click. Sprint 21 missed its estimate by a factor of
four; this one counts three commits per story and bounds the closing acts'
follow-ups by D-2's five findings per lens.

**When a PR nears 85 commits before its closing act,** the implementation
session cuts the PR at the last finished commit group and moves the rest
into a further stacked PR, named in the briefing. It never asks for a
fast-forward by hand. The idea list's row on "an owner go stands in for the
merge button" is answered by this and set `dropped`, reopened by a sprint
that cannot be cut.

### D-8: the closing acts under the new rule (standing, D-2)

Each lens reviews its PR's diff and reports at most five findings, ranked by
severity. On-surface findings are fixed on the branch test-first; off it, an
S1 is filed, an S2 the diff reaches is filed, everything else is a line on
its screen's polish list. The briefing names, per PR, the regressions the PR
introduced and the older findings separately. The carry-forwards of Sprint
21's retrospective apply: a money identity is checked at a moving rate too;
every UI story's review takes a browser pass; one "Closes #n" line per
issue; a `.po` resolver replays every msgstr change.

### D-9: the boards and their picks (recommended; silence adopts them)

Under `_bmad-output/planning-artifacts/design-language/mockups/ux-design-2026-11-01-sprint22/`,
drawn over the review seed with the shipped `priv/static/app.css`:

- **Board 01, I1 (#1351, #1350, #1336, #1342):** Wealth, Overview and Cash
  flow before and after, the anatomy numbered, and the classification rule
  that decides per text whether it is a basis clause, a method sentence, a
  data fact or a problem, with the texts that must not move. Variant R was
  adopted by you on 2026-11-01; no other variant is drawn. **Q1, three
  corrections found while drawing R on the real markup, the default unless
  a comment flips them:** a note that names rows left out of a total never
  folds, it only clamps (otherwise R would hide the excluded rows' count
  the owner kept visible); a note's remedy control stays visible under the
  clamp; texts are classified one by one, not by the prototype's clause
  length.
- **Board 02, figures on screen (#1316, #1332, #1331, #1274, #1293,
  #1343):** before and after.
- **Board 03, drawer, import and accounts (#1335, #1337, #1313, #1219,
  #1299, #1333):** before and after. **Q2, #1313's held-back rows: variant
  A is recommended,** one collapsed group per other portfolio, held back,
  with a "Trotzdem übernehmen" toggle and its rows one tap away. "Already in
  that portfolio" is one fact about a set of rows; variant B (each row
  marked inline) asks it once per row, adds the preview's first row table,
  and invites a partial copy of a history. Say "B" to flip it.
- **Found while drawing, placed by D-2's rule:** Wealth's Marktwert is in
  the security's currency, so a USD row never adds up to the EUR total
  (S2, on R8's surface: R8 shows the base figure the total sums); Income's
  "Je Position" needs one row per payment currency (R9); the twin-account
  name belongs in the drawer's account selects and Wealth's cash table too
  (U2); the sell preview's lot table cuts off Bruttogewinn at the drawer's
  width (S3, on R10's surface).

The story that builds each surface writes its anatomy into `DESIGN.md`.

### D-10: the idea list after this plan (recommended)

- **I14** is `planned` (this sprint), **I1** is `planned` (#1351).
- The duplicate number **I5** is resolved: the passkey idea keeps I5; the
  merge-go idea becomes **I15** and is `dropped` by D-7.
- **The next idea to go deep is I7**, a position dossier (one read and one
  screen per position: holding, metrics, notes, events, target). You asked
  for it, it needs no gate, and I6 and I13 build on it. The next planning
  session proposes it.

## Sequencing

1. Lane F, then Lane M, then R1 and R2 (the boundary and the gate first, so
   every later write is checked by a gate that checks), then R3 to R10 in
   order. R4 before R3's #1219 if they touch the same preview code.
2. The sprint PR's closing act, its fixes, its briefing; promotion under the
   four conditions; your merge.
3. The stacked PR is built on the sprint PR's head and rebased onto `main`
   after that merge: Lane A, Lane U, Lane I, its closing act, the close-out.

## Shrink order (cut from the top, name the cut in the briefing)

1. A4 (#957), the largest S2, the least used.
2. A1 (#1254): the truncation flag is honest, but every list read changes.
3. Lane I's later pages (after Wealth, Overview and Cash flow): the rest
   follow in Sprint 23 under the same board.
4. Never cut: Lane F, any R story, D-1's criteria.

## What is deliberately not in this sprint

- **Every S3 not riding a story.** They are on their screens' polish lists
  (D-4) and are fixed when a story next touches the screen, or in a polish
  pass a later plan schedules.
- **The features** (#894, #899, #900, #1070, #1115) and **#1177**, for the
  reasons in D-4.
- **No new idea is built.** I7 is proposed for the next session (D-10).
- **No audit of older code.** D-2 makes that a lane a plan schedules; this
  plan schedules none, because the severity pass just read the whole
  backlog.

## What "done" means for this sprint

1. Both PRs merged in order, each by your button.
2. The four amendments and D-5 built as signed, each identity pinned and
   seen failing first.
3. D-1's five criteria recorded, each with its evidence.
4. Lane Z done and recorded in the close-out: the twelve trackers, the 53
   closes with their pointers, the seven closes with their evidence.
5. A calendar release per merge; contract entries 21 and 22 name what an
   agent sees change.
6. The schema budget's ceilings no higher than Sprint 21's (102,909 /
   171,980 / 206,535 bytes for read, book and full).
7. The surface check for every read-ergonomics change (A1's `truncated` and
   `limit`, A2's tie-break and refusal): every endpoint of its family named
   with whether it carries it.
8. The close-out's two counts: the regressions the sprint introduced and
   the older findings, by severity.

## Implementation checklist (kept by the implementation session)

The implementation session's state, ticked as each commit group lands on
`agent/claude/sprint-22` (the sprint PR) or `agent/claude/sprint-22-ui`
(the stacked PR). Lane Z was done by the planning session: polish trackers
#1355 to #1366.

Sprint PR (#1367):

- [x] F1 #1345 · [x] F2 #1268 (and the test configuration's search budget, the same class) · [x] F3 #1273 · [x] three green CI runs on Lane F's head (`4046548`, `13c7b13`, `14c70d7`, none re-run)
- [x] M: [x] BMAD 6.12.4 · [ ] #1346 (declined with its findings) · [x] #1347 · [x] #1348 · [x] OTP 27.3.4.19 and bookworm 20261027 · [x] version report
- [x] R1 #1291 · [x] R2 #1269 #1272 #1271 · [x] R3 #1306 #1305 #1307 #1219
- [x] R4 #1313 · [x] R5 #1310 #1311 #1317 · [x] R6 #1292 #1290
- [x] R7 #1309 · [x] R8 #1316 #1332 #1331 · [x] R9 #1274 #1293
- [x] R10 #1335 #1337
- [x] closing act (money and idempotency lens, correctness hunter, security lens, UAT persona) and its fixes · [x] briefing · [ ] promotion

Filed by the closing act and the stories (ADR-0026's amendment of 2026-11-01): #1368 (S2), #1369 (S2), #1370 (S1), #1371 (S1, needs-decision); polish lines on #1355, #1364 and #1365.

Stacked PR:

- [ ] A1 #1254 · [ ] A2 #1294 #1295 · [ ] A3 #1301 #1315 · [ ] A4 #957
- [ ] U1 #1299 · [ ] U2 #1333 · [ ] U3 #1330 · [ ] U4 #1343
- [ ] I #1351 #1350 #1336 #1342
- [ ] closing act and its fixes · [ ] close-out · [ ] briefing · [ ] promotion
