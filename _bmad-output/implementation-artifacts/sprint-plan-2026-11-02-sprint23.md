# Sprint 23 — the debts that fall due: two S1s, the views the agent got first, the MCP SDK move, and the rest of I1

**Status: ADOPTED by the merge of the Sprint 23 planning PR.**
The merge is the signature (ADR-0026 step 1, as amended on 2026-10-08). A
fresh implementation session builds it on `agent/<provider>/sprint-23`, as
one sprint PR and one stacked PR (D-6). The severity rule of ADR-0026's
amendment of 2026-11-01 applies unchanged.

## What you need to do

1. **Merge, to sign one risk-tier decision: #1371, answer (b).**
   [ADR-0053, amended 2026-11-02](../../docs/decisions/0053-a-pp-csv-books-its-gesamtpreis.md):
   when you change the quantity, price, fees or taxes of a trade that
   stores its cash (an imported row), the edit must state the cash too, and
   the cash must agree with the new figures to the cent. The drawer shows
   the cash field prefilled with the derived figure; the API refuses the
   edit without it. Rows already edited the old way are not rewritten, but
   a read-only check lists them on the Overview, so you can see whether
   your instance has any. Today such an edit silently leaves two costs on
   one booking (cash 806.00, lot 816.00). It is yours because it changes how
   a stored money record is corrected. Comment "(a)" to have the cash
   re-derived silently instead.
2. **Optional, the idea that goes deep this time: I7, the position
   dossier** (D-9). One question only you can answer: is the dossier the
   agent's one-call read, with the security page as its human view (the
   recommendation), or do you want a new screen? Silence leaves I7 in
   `discussing` with that question in its row; nothing of I7 is built in
   this sprint either way.
3. **Look at board 04 and pick the number colours** (D-11). You raised it
   on 2026-11-02 and were unsure; the recommendation is C: the accent
   colours only controls; plain figures are in the text colour; a signed
   figure is teal when positive and coral when negative, whatever accent is
   set. Silence adopts C; comment "A" or "B" for the other two.
4. **Nothing else.** The other boards' picks (D-8) are the default unless a
   comment flips them. The ⓘ fix you reported (C1, D-11) needs no answer.

**Not asked:** everything else. Each decision below carries its reason and
flips by a comment. The announcement stays yours (Sprint 17's D-1).

**Verification basis:**

- **`main` and CI:** `main` at `6a737ce`, with CI 1841, Commit authorship
  855 and Release 29 green on it.
- **Sprint 22's merges, as its close-out asked this plan to record:** the
  sprint PR #1367 merged by rebase at 07:03 UTC on 2026-11-02 (release
  **2026.11.4**). The stacked PR #1372 was merged 8 seconds later **into its
  stacked base `agent/claude/sprint-22`, not into `main`**: GitHub had not
  retargeted it, so its 54 commits did not reach `main` and its 14 keywords
  closed nothing. They were reopened onto `main` as #1373, merged at 10:25
  UTC (release **2026.11.5**), whose 14 "Closes" lines did close them. D-6
  makes the retarget a step of its own.
- **The open-issue list of 2026-11-02:** 31 open: 8 `agentic` (#1368,
  #1369, #1370, #1115, #1070, #900, #899, #894), 2 `agentic` and
  `needs-decision` (#1371, #1220), 1 `needs-decision` (#1177), 2
  `needs-uat` (#328, #354), 18 trackers (12 polish lists, #1355 to #1366;
  #991 and the five area trackers #416 to #420). Of those, four are Sprint
  22's filings (#1368 S2, #1369 S2, #1370 S1, #1371 S1), #1115 is due
  before 2027-01-27, and #894, #899, #900, #1070 and #1220 stay open with
  the reasons Sprint 22's D-4 gave.
- **Two Dependabot PRs are open:** #1346 (Sobelow 0.18.0, declined by
  Sprint 22's Lane M with its findings, never closed) and #1347
  (`@types/node` 26.6.6, already on `main` by Sprint 22's Lane M, so
  superseded).
- **#1115 is buildable:** `@modelcontextprotocol/server` is published up to
  2.4.0; the companion is on `@modelcontextprotocol/sdk` 1.32.2, whose
  fixes run until at least 2027-01-27.
- **The schema budget in force** (Sprint 22's last row): 102,887 / 171,958
  / 206,513 bytes for read, book and full. **The contract's head is entry
  22, dated 2026-11-03**, so entry 23 is dated 2026-11-04 or later
  (`since=` compares strictly after a date).
- **Each S1 and S2 was read against the code on `6a737ce`:**
  `CsvParser.parse_datetime` still returns `nil` for an unreadable time
  (#1370); `SettlementForm.prepare/2`'s catch-all clause sends no
  `gross_amount`, so a one-currency edit keeps the stored cash (#1371);
  `CategoryResult` reads the holdings with `trade_fallback: false` (#1368);
  the Trades tab's open lots and the sell preview do not go through
  `Valuation.price_points/2` (#1369).
- **The boards this PR carries** were captured from the review instance on
  the synthetic seed with the shipped `priv/static/app.css` (D-8).

## State of play, in five lines

1. **Sprint 22 is on `main`** in two releases: every S1 and S2 of the
   severity pass, the agent's surface, I1 on three pages. 31 issues are
   open, 18 of them trackers.
2. **Two S1s are left, both found by Sprint 22's lenses in older code:**
   a CSV time that folds two rows into one (#1370, the same defect #1306
   fixed for JSON), and an edit that leaves two costs on one booking (#1371).
3. **Three human views fall due.** R6's two reads and A4's flow list
   shipped for the agent only in Sprint 22, so the two-way coverage rule
   makes them due by the end of this sprint; the audit journal (U2) has had
   no view since Sprint 19.
4. **The MCP SDK v1 line ends on 2027-01-27**, and the move to v2 is a
   package migration, not a bump (#1115).
5. **The worktree build has two known holes** (a gate test that flips
   `core.bare`, hand-merged gettext catalogues) that made Sprint 22's
   commits skip their hooks and caused its one red CI run.

## Why this cut

- **Tooling first, money second, views third.** The worktree holes are
  closed before any story is built in a worktree, so every commit runs its
  hooks; then the two S1s and the two S2s (risk tier); then the views and
  I1's later pages.
- **Every coverage debt is paid, not recorded again.** Recording U2 as a
  finding in four close-outs running is the decay the two-way rule exists
  to prevent ("agent only, forever"). This sprint builds all three views.
- **No new feature.** I7 is discussed, not built (D-9); the features Sprint
  22 kept open stay open with their reasons.
- **Both PRs stay well under 90 commits** (about 39 and 53), so both merge
  with GitHub's "Rebase and merge" button.
- **Your two reports of 2026-11-02 ride the stacked PR** (Lane C), ahead
  of Lane I, because both change every page Lane I then reworks.

## Lanes

### Sprint PR (`agent/<provider>/sprint-23`)

**Lane E, the worktree build (first commits, before any story runs in a
worktree).** Sprint 22's carry-forwards 1 and 2 and its symlink finding.

| Story | Issues | What it does | Commits |
|---|---|---|---|
| E1 | #1364's S2 line | `scripts/test_check_invisible_unicode.py` drops `GIT_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE` and `GIT_COMMON_DIR` from its `git init` subprocess; a test runs it from inside a linked worktree's hook environment and asserts `core.bare` stays unset (seen failing first) | 1 |
| E2 | Sprint 22 retrospective, carry-forward 2 | a gettext merge tool (`scripts/`, with its tests): it unions the stories' msgids, keeps every changed msgstr, refuses a fuzzy match, keeps the final newline; the development guide says to use it for every catalogue integration | 3 |
| E3 | Sprint 22 retrospective, the `deps` symlink | the worktree helper writes `deps`, `_build` and `node_modules` into the worktree's local exclude file, and the integration step refuses a commit that tracks a symlink (a pre-commit check, so CI holds it too) | 2 |

Proof: one story of Lane R is built in a linked worktree with its hooks
running, no `--no-verify` anywhere in the sprint (D-1 criterion 6).

**Lane M, maintenance** (the standing rule; a `version-report-*` file):

- **M1, #1115, the MCP SDK v2 move** (risk tier: a dependency, its own
  commit group and verification pass, ADR-0036). `@modelcontextprotocol/sdk`
  becomes `@modelcontextprotocol/server` at the newest 2.x that passes the
  gates; imports, the stdio transport and the tool registration move to
  v2's API; every tool's name, input schema and output shape stays byte-
  identical where v2 allows it, and where it does not, the contract entry
  says what an agent sees change. The schema-budget test measures v2's
  serialisation; the ceilings stay no higher than today's (D-1 criterion 4).
  The README's client snippets and `docs/integration` are checked against
  v2. About 5 commits.
- **#1346, Sobelow:** re-read on 0.18.x; taken only if `mix sobelow --skip
  --exit` stays green without a new skip, else declined with its findings
  and the PR closed with that comment, so it does not sit open a second
  sprint. **#1347** is closed as superseded by `main`.
- BMAD, Hex, npm, Elixir/OTP and PostgreSQL as every sprint; `decimal`
  3.2.0 stays declined until its own reviewed bump (Sprint 22's reason).
  About 4 commits.

**Lane R, the S1s and the S2s (risk tier: each its own commit group and
verification pass, ADR-0036).** Every story test-first with exact `Decimal`
fixtures.

| Story | Issues | What it does | Decision | Commits |
|---|---|---|---|---|
| R1 | #1370 | the CSV parser refuses an unreadable time as a named row error at preview, as #1306 did for JSON v1; a blank or absent time is still no time; every value read today reads as before, so no stored hash moves (a test over the fixture's times pins it) | ADR-0053's refusal list gains the CSV row (dated note) | 3 |
| R2 | #1371 | ADR-0053's amendment of 2026-11-02 on every write path: `PATCH /api/v1/transactions/:id` refuses the four-field edit without `gross_amount` (422 naming it), checks the stated cash against §2; the MCP tool's description says so; the drawer shows the prefilled cash field (board 02 ①a); the read-only check `GET /api/v1/transactions/cash_mismatch` with its MCP read; R10's L1 test follows the rule; contract entry 23 | ADR-0053, amended (yours) | 7 |
| R3 | #1368 | the category result values members by `Valuation.price_points/2` and names the price source, so its roll-up and Wealth's total agree (board 02 ①c) | none (ADR-0010, as Sprint 22's D-6) | 3 |
| R4 | #1369 | the Trades tab's open lots and the sell preview read the price through `Valuation.price_points/2` and name `price_source` (board 02 ①b) | none (ADR-0010) | 3 |

**Closing act of the sprint PR** (D-7): the money and idempotency lens on
R1 to R4, the correctness hunter, a dependency lens on M1 (every tool still
lists, validates and answers over stdio with a real client), the UAT
persona's round trips (R2's identity in the drawer and over the API, R1's
CSV with an unreadable time, R3's and R4's figures against Wealth). About
8 commits.

**Estimate:** E 6, M 9, R 16, closing act about 8: **about 39**.

### Stacked PR (`agent/<provider>/sprint-23-ui`)

**Lane V, the views the agent got first (two-way coverage, D-1 criterion
3).** Board 01 and board 03.

| Story | Issues | What it does | Commits |
|---|---|---|---|
| V1 | Sprint 22 R6 (#1292, #1290); R2's check | the Overview's data-quality line gains three findings, each shown only above zero: split events missing a portfolio, cross-currency trades with a rate and no cash, trades whose cash misses their figures; each links to the history filtered to exactly those rows (`/transactions?dq=…`), which shows the report's remedy sentence in a data note above them (board 01 ①a) | 5 |
| V2 | Sprint 22 A4 (#957) | the depot and the security merge previews show `flow_changes`: the dates and entries the collapse changes, an empty state, the basis behind the section's ⓘ (board 01 ①b) | 4 |
| V3 | idea U2 | the audit journal gets its page: newest first, the actor, the entity with a link to it, the change with its before and after in a fold, filters by entity type and actor, paged like the API (board 03) | 7 |

**Lane C, what you reported on 2026-11-02 (before Lane I, because both
touch every page).**

| Story | Source | What it does | Commits |
|---|---|---|---|
| C1 | owner, 2026-11-02 | the ⓘ panels behave as one popover: opening one closes any other, and a click or tap outside an open panel closes it (Escape already does, #1342); a click inside the panel leaves it open; the focus is not moved by a click-away. One capture listener in `layout_view.ex` beside #1336's and #1342's, so every `details.metric-tooltip` (about 25 sites, the view switcher's help included) gets it without an id. No rendered difference, so no board (the sprint workflow's exception) | 2 |
| C2 | owner, 2026-11-02 | the number colours by board 04's pick (C recommended, D-11): the tokens in all four theme blocks, DESIGN.md's colour and KPI rules, the contrast and token-parity invariants re-measured | 3 |

**Lane I, the explanations out of the way, the later pages (idea I1;
#1351 closed with Sprint 22's three pages; Sprint 22's board 01 and its
classification rule).**
The pages Sprint 22's shrink order cut: Wealth's Allocation tab, the
security page, Snapshots, Tax, Views, Classifications, Imports, Risk and
Income. The anatomy is signed (board 01, variant R with its Q1
corrections), so each page is a conformance repair: the implementation
session captures its before and after with Sprint 22's `build.js` as one
board commit before the first page's code, and the design critic reviews
against it. Income re-reads R5's two exclusion sentences against board 02
①d. #1339 (the "Daten als Tabelle" disclosure on Wealth and on Imports)
rides it, and every polish line on a touched page is fixed and ticked.
About 17 commits.

**Closing act of the stacked PR** (D-7): the correctness hunter, the
design critic against boards 01 to 03, Sprint 22's board 01 and the living
spec at 390 and 1200 px, light and dark, in German; the agent's lens on V1
(each count equals its read's row count); the UAT persona over every page
Lanes V and I touch. About 10 commits.

**Close-out** (the stacked PR's last commits): `sprint-status.yaml`,
`epics.md`'s dated reconciliation, the idea list (I1 and U2 `built`), the
retrospective, the version report. About 5 commits.

**Estimate:** V 16, C 5, I 17, closing act about 10, close-out 5: **about 53**.

## Decisions

### D-1: what this sprint is for, and its exit criteria (recommended)

1. **Both S1s close by keyword** (#1370, #1371), each identity pinned and
   seen failing first: R1's unreadable time refused while every accepted
   time keeps its hash; the amendment's 806.00 / 816.00 example on the API
   and in the drawer.
2. **Both S2s close by keyword** (#1368, #1369), each pinned by a security
   priced at its trade price reading the same figure as Wealth.
3. **No agent-only capability is overdue at the close-out:** R6's two reads,
   A4's flow list and the journal each have their screen. For the first
   time since Sprint 19 the close-out's two-way check records nothing.
4. **#1115 closes** with the companion on v2's server package, every tool
   answering over stdio, and the schema ceilings no higher than 102,887 /
   171,958 / 206,513 bytes.
5. **The built screens match boards 01 to 04 and Sprint 22's board 01**, by
   the design critic; at most one ⓘ panel is open on any page, and a click
   outside closes it (C1, pinned by a browser test).
6. **Every commit ran its hooks:** no `--no-verify` in the sprint, Lane E's
   proof recorded in the PR body.
7. **The regressions this sprint introduced are counted** apart from the
   older findings, and none is an S1 at promotion; no PR head needs a re-run
   to turn green.

**No criterion counts open issues.** Reported, not judged: 31 open today;
26 after this sprint's keywords close #1370, #1371, #1368, #1369 and
#1115 (polish trackers stay open while they have lines; I1's later pages
have no issue of their own, since #1351 closed with Sprint 22's three
pages).

**To flip by comment:** name a criterion to drop or add.

### D-2: #1371, answer (b), signed by this merge (recommended; yours)

[ADR-0053's amendment of 2026-11-02](../../docs/decisions/0053-a-pp-csv-books-its-gesamtpreis.md)
says it in full, with its identity and asks table. The choice was (a) the
edit re-derives the cash, or (b) the edit must state it. **(b)**, because
an imported row's cash is the broker's figure and a silent re-derivation
overwrites it on a typo fix; (b) keeps every figure the operator's or the
broker's. The amendment adds what #1371's (b) did not say: what happens to
rows already edited the old way. They are listed, not rewritten (R2's
read-only check, V1's finding), so a wrong cost on your instance becomes
visible instead of staying silent.

**To flip by comment:** "(a)". R2 then re-derives on every write path, the
drawer shows the figure read-only, and the check still lists the rows
edited before.

### D-3: R1 is a note, not an amendment (recommended)

#1370 refuses a value the parser could never read; it changes no booking
that was correct and no stored hash, exactly as #1306 did, which ADR-0053
recorded as a dated note. R1 does the same for the CSV row. **To flip by
comment:** "amend it", and R1's note becomes an amendment signed by the
next planning PR, R1 moving there.

### D-4: R3 and R4 follow ADR-0010, as Sprint 22's D-6 did (recommended)

One valuation rule on every surface: a position without a quote is valued
at its last own trade price, its `price_source` named. #1368's other option
(name the members the roll-up leaves out) would keep two rules where R8
made one. No ADR changes.

### D-5: U2 is built now, as one page (recommended)

The journal read has existed for the agent since before Sprint 19 and the
operator has never seen it, so the operator cannot answer "what did the
agent change this week?" without asking the agent. Board 03 draws a single
page (A) against a fold on every entity's page (B). **A is recommended:**
one surface that matches the API's shape, one place to answer the audit
question, and no change to the pages Lane I is reworking. **To flip by
comment:** "B", or "U2 later", which moves V3 to the next sprint and leaves
D-1 criterion 3 at two of three.

### D-6: the PR shape, and the stacked PR's retarget (recommended)

Two PRs, each under ADR-0026's budget of 90 commits, each merged by your
"Rebase and merge" button: the sprint PR (Lanes E, M, R; about 39) and the
stacked PR (Lanes V, C, I and the close-out), built on the sprint
PR's head (about 53 with Lane C). **New: once the sprint PR is merged, the implementation session
rebases the stacked PR onto `main` and retargets it to `main` before it
asks for your merge**, and the briefing says so. *Why:* Sprint 22's stacked
PR #1372 was merged into its dead stacked base, so its commits and its 14
keywords missed `main` until #1373 reopened them. A PR nearing 85 commits is
cut at its last finished commit group into a further stacked PR, named in
the briefing, as Sprint 22's D-7 said.

**The build order is the plan's order** (E, M, R1 to R4, then V1 to V3,
then I), so history goes forward only and no reorder is needed later
(Sprint 22's carry-forward: a session's auto mode may refuse a force-push).

### D-7: the closing acts and the parallel build (standing, with Sprint 22's carry-forwards)

Each lens reviews its PR's diff and reports at most five findings, ranked by
severity, as ADR-0026's amendment of 2026-11-01 says. Sprint 22's
carry-forwards apply:

- **a parallel build caps itself at the machine's headroom**, and a
  timeout seen only under local load is read as load before it is filed as
  a flake;
- **a story brief says in its first lines** that its first commit holds the
  failing test and the code together, the red output in the commit body,
  and the integration checks it before a cherry-pick;
- **every catalogue integration uses E2's tool;**
- one "Closes #n" line per issue; a money identity is checked at a moving
  rate too; every UI story's review takes a browser pass.

### D-8: the boards and their picks (recommended; silence adopts them)

Under `_bmad-output/planning-artifacts/design-language/mockups/ux-design-2026-11-02-sprint23/`,
captured from the review instance on the synthetic seed with the shipped
`priv/static/app.css`. The board folder's README lists every pick (Q1, Q2,
…) with its recommendation, every new string and what was drawn from a
template instead of captured.

- **Board 01, the coverage views:** ①a the three data-quality findings on
  the Overview and the filtered history (variant A recommended against a
  section on Imports); ①b the flow list in both merge previews, before and
  after.
- **Board 02, money on screen:** ①a the drawer's cash field under the
  amendment (b recommended, a drawn for contrast); ①b the open lots and the
  sell preview; ①c the category result; ①d R5's two exclusion sentences on
  Income and the Overview as Sprint 22 built them (Sprint 22's
  retrospective: they shipped without a board).
- **Board 03, the audit journal:** A, one page, recommended; B, a fold per
  entity.
- **Board 04, number colours** (D-11): today, A, B and C (recommended)
  under each accent, light and dark.

The picks are numbered Q1 to Q7 in the board folder's README, each with
its recommendation and the comment that flips it: Q1 (where the three
checks are read: A, the Overview's line), Q2 (their severity: problem), Q3
(the merge preview keeps its "Ändert auch" phrase), Q4 (#1371's (b), signed
by D-2), Q5 (the journal as one page), Q6 (its entry in the sidebar's
"Verwaltung" group) and Q7 (the number colours: C, D-11).

**Found while drawing, placed by the severity rule:** seven S3s (two
exclusion notes on Cash flow and the Overview that offer a remedy that
cannot act on R5's reasons, a count lead that repeats, "1 Transaktionen",
a booking without a URL of its own, and others), which go onto their
screens' polish lists after the merge; a `since=` filter on the journal
read, which goes into the idea list as I16; and a journal `delete` entry
whose `after` repeats the deleted record, which V3 checks against ADR-0017
first: fixed on V3's branch if small and confirmed, filed as an S2
otherwise, since V3's diff reads it.

The story that builds each surface writes its anatomy into `DESIGN.md`.

### D-9: the idea that goes deep: I7, the position dossier (recommended)

The idea list's recommended order puts I7 first. Its triage proposed one
read and one screen per position. **What the triage did not say: the
security page already is that screen.** It shows the holding, the metrics,
the notes, the events and the target of one security, each in its tab. What
the agent lacks is the one call; it reads `portfolixir.holdings.by_security`,
`portfolixir.securities.get`, `portfolixir.securities.metrics`,
`portfolixir.notes.list`, `portfolixir.events.list` and
`portfolixir.targets.list_positions` separately. **Recommended:** the dossier is one agent read
(`GET /api/v1/securities/:id/dossier` and its MCP tool, each part with the
computation basis it already carries), and its human view is the security
page as it stands, which satisfies the two-way rule without a new screen.
The open question, yours: is that enough, or do you want one screen with
everything at a glance? I7's row records the question; the next plan builds
the answer you give.

### D-10: what stays open, and why (standing)

#894, #899, #900, #1070 and #1220 keep Sprint 22's reasons. #1177 waits for
its trigger (a switcher's export with those two types). #328 and #354 wait
for your check on real data. The polish lists stay open while they have
lines; a story that touches a screen fixes its lines.

### D-11: your two reports of 2026-11-02 (C1 recommended as stated; C2 yours on board 04)

**C1, the ⓘ panels.** Today each ⓘ is a `<details>` that only its own
summary closes (and Escape since #1342), so two panels stay open side by
side and a click elsewhere leaves them open. A popover that explains a term
should close when the reader moves on. Built as one listener, so the ~25
call sites need no change; graded S2 (a panel covers figures until it is
clicked again). It ships with a browser test that opens two and clicks
away.

**C2, the number colours. Neither of your two options fixes what you
saw, because the clash does not come from the gain colour.** `DESIGN.md`
paints an unsigned KPI figure in the *active accent* and a signed one in
the gain or loss colour. With the teal accent, a plain figure is teal
(#0f766e) and a gain is emerald (#047857): your two greens. Option A (teal
gains, coral losses, unsigned figures still in the accent) leaves the teal
and the violet figures beside each other; option B (every figure in the
accent) removes the only colour that tells a gain from a loss at a glance,
and makes every figure look like a control, since the accent is what marks
a link, a selection and the focus.

**Recommended: C.** The accent marks controls only; an unsigned figure is
in the text colour; a signed figure is teal for a gain and coral for a
loss, the brand's own two hues, whatever accent is set; the gain and the
problem colours become aliases of those two, so the app has one green and
one red (dark mode already uses coral for problems). The sign stays a
glyph, so the colour is never the only carrier. **The cost, shown on board
04:** with the teal accent, a teal button can sit beside a teal gain, and
with the coral accent a coral control beside a loss. That collision is
smaller than today's, because figures no longer take the accent at all.

**To flip by comment:** "A" or "B" on board 04. C2 then builds that
variant; C1 is unaffected.

## Sequencing

1. Lane E, then Lane M (M1 before any story changes an MCP tool, so R2's
   tool change lands on v2 once), then R1 to R4.
2. The sprint PR's closing act, its fixes, its briefing; promotion under the
   four conditions; your merge.
3. The stacked PR, built on the sprint PR's head, rebased onto `main` and
   retargeted to `main` after that merge (D-6): Lane V, Lane C, Lane I,
   its closing act, the close-out.

## Shrink order (cut from the top, name the cut in the briefing)

1. Lane I's pages after the security page, Wealth's Allocation tab and
   Income: they follow in Sprint 24 under the same board.
2. V3, the journal page: D-1 criterion 3 then records it, a fifth time.
3. Never cut: Lane E, M1, any R story, V1, V2, Lane C, D-1's criteria 1,
   2, 4 and 6.

## What is deliberately not in this sprint

- **I7** is discussed, not built (D-9).
- **No other idea,** and no feature Sprint 22 kept open.
- **No polish pass of its own.** A story fixes the polish lines of the
  screens it touches; no screen is taken on its own.
- **No audit of older code:** ADR-0026's amendment makes that a scheduled
  lane, and this plan schedules none.

## What "done" means for this sprint

1. Both PRs merged in order, each by your button, the stacked one into
   `main`.
2. The amendment built as signed, its identity pinned and seen failing
   first; R1's note in ADR-0053.
3. D-1's seven criteria recorded, each with its evidence.
4. A calendar release per merge; contract entry 23 (R2, M1 if an agent
   sees a change, the new read) names what an agent sees change.
5. The surface check for V1's `dq=` filter: every history filter named with
   whether it carries it.
6. The close-out's two counts: the regressions the sprint introduced and
   the older findings, by severity.

## Implementation checklist (kept by the implementation session)

Sprint PR:

- [ ] E1 #1364's line · [ ] E2 gettext merge tool · [ ] E3 worktree links and the symlink refusal · [ ] a story built in a worktree with its hooks running
- [ ] M1 #1115 · [ ] #1346 taken or declined and closed · [ ] #1347 closed · [ ] version report
- [ ] R1 #1370 · [ ] R2 #1371 · [ ] R3 #1368 · [ ] R4 #1369
- [ ] closing act and its fixes · [ ] briefing · [ ] promotion

Stacked PR:

- [ ] rebased onto `main` and retargeted to `main` after the sprint PR's merge
- [ ] V1 · [ ] V2 · [ ] V3
- [ ] C1 the ⓘ click-away · [ ] C2 the number colours (board 04's pick)
- [ ] I: board commit · [ ] Allocation tab · [ ] security page · [ ] Income · [ ] Snapshots · [ ] Tax · [ ] Views · [ ] Classifications · [ ] Imports · [ ] Risk
- [ ] closing act and its fixes · [ ] close-out · [ ] briefing · [ ] promotion
