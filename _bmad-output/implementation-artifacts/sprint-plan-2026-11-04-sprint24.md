# Sprint 24 — the dossier, the journal since a date, the costs beside the benchmark gap, and two owner reports

**Status: ADOPTED by the merge of the Sprint 24 planning PR.**
The merge is the signature (ADR-0026 step 1, as amended on 2026-10-08). It
signs two decisions written as amendments:
[ADR-0017, amended 2026-11-04](../../docs/decisions/0017-append-only-audit-journal.md)
(#1378: a delete's `after` is null) and
[ADR-0046, amended 2026-11-04](../../docs/decisions/0046-benchmark-comparison.md)
(I17: the costs the real portfolio paid, beside the gap). A fresh
implementation session builds the sprint on `agent/<provider>/sprint-24` as
**one** sprint PR (D-6). The severity rule of ADR-0026's amendment of
2026-11-01 applies unchanged.

## What you need to do

1. **Merge, to adopt the plan.** Neither amendment is one of your own
   questions (no stored money figure is booked or corrected differently),
   so each is decided below with its reason and flips by a comment.
2. **Optional, the idea that goes deep this time: F1, predictions and
   calibration** (D-10). One question only you can answer: **do you accept
   "measure the agent" at the small shape, with the four conditions D-10
   adds?** "Yes" opens gate B4.2, and the next planning PR writes its ADR;
   nothing is built in this sprint either way. "No" parks F1 with your
   reason. Silence leaves F1 `discussing` with the question in its row.
3. **Optional, a setting only you can change:** once the new `browser` CI
   job (D-5) has been green on `main` once, add it to `main`'s required
   status checks (Settings → Branches). Until then it runs and reports, but
   a red run does not block a merge.

**One correction to what you were told on 2026-11-02.** Sprint 23's D-9
said the security page already shows "the holding, the metrics, the notes,
the events and the target". **It does not show the target.** Its nine tabs
are Overview, Chart, Transactions, Trades, Quotes, Holdings,
Classifications, Research and Dates; a position's SOLL row is shown on the
Classifications page, and its drift on Wealth's Allocation tab. Your answer
A stands as given: the dossier carries the targets, and their human view is
the Classifications page (D-2). If you want the target on the security page
too, comment "I7 target on the security page"; that needs a board and
moves to Sprint 25.

**Not asked:** everything else. Each decision below carries its reason and
flips by a comment. The announcement stays yours (Sprint 17's D-1).

**Verification basis:**

- **`main` and CI:** `main` at `1c2d8e1`, CI 1867 green on it.
- **Sprint 23's second merge, as its close-out asked this plan to record:**
  the stacked PR #1379 was rebased onto `main` and retargeted before the
  merge (D-6 of Sprint 23, done as written) and merged by the owner's
  rebase at 19:50 UTC on 2026-11-03; CI 1858 green on `72423d5`; release
  **2026.11.7**. Its keywords closed #1375 and #1376.
- **Since then on `main`:** #1380, #1382 and #1384 (the idea list: I7
  answered, F1 worked through, I19), and #1383, ecto 3.14.2 → 3.14.3 for
  EEF-CVE-2026-118391 (closes #1381; CI 1865 green on `02d7336`; release
  **2026.11.8**). CI 1864 on `1702757` was red in `advisories` for that
  advisory, published with nobody pushing; #1383 turned it green.
- **The open-issue list of 2026-11-04:** 26 open: 4 `agentic` (#1070,
  #900, #899, #894), 2 `agentic` and `needs-decision` (#1378, #1220), 1
  `needs-decision` (#1177), 2 `needs-uat` (#328, #354), 17 trackers (11
  polish lists #1355 to #1366 without #1364; #991; the five area trackers
  #416 to #420).
- **Read against the code on `1c2d8e1`**, each claim this plan rests on:
  - `GET /api/v1/journal` takes no `since` and **no paging at all**:
    `JournalQuery.parse/1` reads five filters and `limit` (default 100, at
    most 1000), and `Journal.list_entries/1` orders newest first with no
    offset or cursor. An entry older than the newest 1000 a filter matches
    is unreachable; the page's "Ältere Einträge zeigen" grows the limit to
    the same 1000. I16's row said "answered by paging"; there is no paging.
  - The cost facet (`Portfolios.Costs.report/1`, `GET /api/v1/costs`) is
    **global only**, a yearly and monthly matrix, "overview level only" by
    #726's requirement. The benchmark comparison reads a portfolio, a view
    or the total over any `period`, `year` or `from`/`to`. **They do not
    cover the same window or scope**, so I17 cannot reuse the facet's
    figures; it reuses its series rule (ADR-0046's amendment, point 2).
  - The quote sync (`QuoteSync.sync_all/1`) walks
    `Catalog.list_securities/0`, every catalogue security with an adapter
    and a ticker, **held or not**: I18's open question is answered yes.
  - The security page's tabs (`SecuritiesLive.detail_tabs/0`) carry no
    target (the correction above).
  - `audit_journal.after` is a nullable `map` column, so #1378's (a) needs
    no migration.
  - ecto 3.14.3's changelog (in `deps/ecto`) lists four query-cache and
    hint fixes and no opaqueness or Dialyzer entry: **#727's OTP trigger
    has not fired** (D-7).
  - BMAD `tea` is installed at v1.27.2 (`_bmad/_config/manifest.yaml`,
    channel pinned); Sprint 23's version report names v3.6.0 as current.
  - The browser tests (`test/browser/`, two today) are excluded by
    `test/test_helper.exs` and `require("playwright")` from Node's module
    path; nothing in the repository pins a Playwright version.
- **The schema budget in force** (Sprint 23's last row): 102,874 / 171,929
  / 206,484 bytes for read, book and full, under the unchanged ceilings
  102,887 / 171,958 / 206,513. **The contract's head is entry 23.**
- **The boards this PR carries** were captured from a review instance on
  the synthetic seed with the shipped `priv/static/app.css` (D-8).

## State of play, in five lines

1. **Sprint 23 is on `main`** in two releases (2026.11.6 and 2026.11.7),
   and ecto's advisory in a third (2026.11.8). Nothing is agent-only and
   overdue, for the first time since Sprint 19.
2. **I7 is answered** (A, 2026-11-03): one agent read, no new screen. It
   needs its field list and its registry row, both below.
3. **Two reads lie about their reach.** The journal cannot be paged past
   1000 entries, and the benchmark gap never says how much of it the
   portfolio paid in fees and taxes.
4. **You reported two screen defects on 2026-11-04** (the rail forgets it
   was collapsed; Wealth's sunburst cannot return to the total), and a
   third on Wealth's performance table on a phone.
5. **The first browser test runs outside CI**, and the BMAD `tea` module
   is two majors behind.

## Why this cut

- **Smaller than Sprint 23** (42 + 49 commits): one PR of **about 50**,
  no stacked PR.
- **One feature from the ladder:** I17 is level (b), a decomposition that
  reports what was booked. I7 and I16 are read ergonomics, not ladder
  analytics.
- **Every new read gets its screen in the same PR** (I16's filter, I17's
  line) or names the screen it already has (I7), so the close-out's two-way
  check again records nothing.
- **What is left out, and why** (each flips by naming it):
  - **F6's buy-only half:** it needs an ADR-0023 amendment first. ADR-0023
    allows corrective quantities *beside a drift*; "new cash X goes here,
    then there" is an order of preference, which sits on the "no advice"
    line and needs its own decision, not a story.
  - **F21, dry-run deletes (#894):** inside scope and ready, but not due,
    not ladder work, and it would push the sprint back to Sprint 23's size.
    First candidate for Sprint 25.
  - **I18, what a sale missed:** its quote question is answered (above),
    its spans are not; an idea not worked out is not built. It stays
    `triaged` with the answer in its row.
  - **#1177, #1220, #328, #354, #894, #899, #900, #1070** keep their
    standing reasons (Sprint 22's D-4, Sprint 23's D-10).

## Lanes (one sprint PR, `agent/<provider>/sprint-24`, in this order)

**Lane M, maintenance and the CI browser job (first, so every later story
runs its browser test in CI).**

| Story | Source | What it does | Commits |
|---|---|---|---|
| M1 | retro carry-forward 5; D-5 | `test/browser/package.json` and its lockfile pin `playwright` exactly; a CI job `browser` runs `npm ci --prefix test/browser`, installs that version's Chromium (`npx playwright install --with-deps chromium`) and `mix test test/browser --only browser`; the scripts take an optional `PLAYWRIGHT_CHROMIUM_EXECUTABLE` so a machine with its own Chromium (this cloud container's) runs them unchanged; `npm audit --audit-level=high --prefix test/browser` joins the `advisories` job and `AGENTS.md`'s Required Local Checks; the test helper's comment says CI runs them | 3 |
| M2 | retro carry-forward 6; D-7 | BMAD `tea` v1.27.2 → the newest v3.x, **read first with bmb** (the module builder's validate/analyze over the new version): which `bmad-testarch-*` skills are renamed or removed, what `docs/` and `_bmad/custom` reference, what a `.claude/skills` reinstall changes. Taken if every reference resolves and the install is clean; declined with the read's findings otherwise. The read goes into the version report either way | 2 |
| M3 | standing rule; D-7 | the version report `version-report-2026-11-…-sprint24.md`: ecto 3.14.3 (#1381, through #1383, release 2026.11.8) as its first row; #727's two triggers re-checked (D-7); Hex, npm, Elixir/OTP, PostgreSQL, BMAD core and the other external modules as every sprint, each bump its own commit | 3 |
| M4 | #727's closing note (Sprint 20 D-4) | **one attempt at Elixir 1.19.x**, never tried: CI's pins, the Dockerfile and the PLT key moved together on a scratch branch; if `MIX_ENV=test mix coveralls.json` and every gate pass in CI, a new issue carries the move (taken in this lane only if it is the mechanical three-place bump and nothing else); if not, the report records the failure with its output | 1–2 |

**Lane J, the journal (risk tier for J1: an audit record's shape, its own
commit group and verification pass, ADR-0036).**

| Story | Source | What it does | Decision | Commits |
|---|---|---|---|---|
| J1 | #1378 | `Journal.record/3` stores `after: null` for every `delete`; a test per writer kind (a row delete, a set delete, a cascading delete through `Lifecycle.Delete`) pins `after` null and `before` unchanged, seen failing first; the API reference states the two older shapes and the release that ended them; the MCP `portfolixir.journal.list` description gains the sentence; contract entry 24 | ADR-0017, amended 2026-11-04 (D-3) | 3 |
| J2 | I16 | `GET /api/v1/journal` and `portfolixir.journal.list` take `since=` through `SinceParam.parse_page/1` (a date, an instant, or the cursor a full page answered as `as_of`): with `since`, rows strictly after the cut, **oldest first**, `has_more` and a cursor `as_of`, as every paged delta read (K17); without it, unchanged. `meta.filters` echoes `since`; contract entry 24; the surface check names every journal read (`GET /api/v1/journal`, its MCP tool, and the page) and that all three carry it | D-4 | 3 |
| J3 | I16 | the journal page takes `since` in its URL and in a date field „Seit“ beside the kind (board 01, A); newest first within the cut; the basis line names the cut; a link `/journal?since=…` opens the slice; `DESIGN.md` gains the field's anatomy | D-4, board 01 | 3 |

**Lane D, the position dossier (I7, FR-49).**

| Story | Source | What it does | Commits |
|---|---|---|---|
| D1 | I7 (A, 2026-11-03) | `GET /api/v1/securities/:id/dossier` and `portfolixir.securities.dossier`, the field list of D-2, each part built by the function its own read uses (no second computation), each part carrying the `computation_basis` its read carries; a merged security answers 404 with `errors.merged_into` as `securities.get` does; the schema budget measured, ceilings no higher than today's plus the new tool's own schema (D-2); contract entry 24; `docs/llms.txt` (its per-profile figures re-measured by `llms-entry.test.ts`) and `docs/integration` name the tool | 5 |

**Lane B, the costs beside the benchmark gap (I17; risk tier: money math
on the performance surface, its own commit group and verification pass).**

| Story | Source | What it does | Decision | Commits |
|---|---|---|---|---|
| B1 | I17 | `costs_paid` in every benchmark comparison payload (portfolio, view, total; API and MCP): fees and taxes by the cost facet's series rule over the comparison's window and scope, the scope following the paying cash account, excluded costs named, its `computation_basis` stating the rule and what it leaves out; the amendment's four identities pinned with exact `Decimal`s, seen failing first; contract entry 24 | ADR-0046, amended 2026-11-04 (D-5) | 4 |
| B2 | I17 | the Performance block's line „Im Zeitraum gezahlt: …“ once under the benchmark rows and the ⓘ's sentence (board 02, A); hidden while the comparison computes; `DESIGN.md` gains the line | board 02 | 2 |

**Lane P, the owner's screen reports (polish, test-first, one functional
test per screen pinning every line it fixes).**

| Story | Source | What it does | Board | Commits |
|---|---|---|---|---|
| P1 | #1366's three open lines | **Wealth, one pass:** (1) the sunburst returns to „Allokiert“ on a tap on the centre, outside the chart or on the selected slice again, and on Escape; (2) „Beitrag je Position“ takes its phone rows below the width where its columns stop fitting, measured on the seed, instead of 560 px; (3) #1322: the holdings table's name column gets the floor-and-wrap anatomy the accounts table got in #1145, so G&V stays in view at 1200 px; the quantity keeps every digit it has. Each line ticked on #1366 | (1) none, no rendered difference; (2) and (3) a before/after board, one commit before the code (D-8) | 1 + 3 |
| P2 | #1357's rail line | the rail's collapsed state survives a full page load and a live redirect: the toggle writes a `SameSite=Lax` cookie the layout reads at render (no expanded flash), as the benchmark selection already does; a browser test (D-5) collapses it, follows a sidebar link on a phone viewport and finds it still collapsed. Line ticked on #1357 | none, no rendered difference (the collapsed state exists) | 2 |

**Closing act** (D-9): the correctness hunter; the money and idempotency
lens on B1 (and J1's audit shape); the agent's lens on D1, J2 and B1 (each
part equals its own read; a cursor walk of the journal from `since=1970-01-01`
reaches every entry once); the design critic against boards 01 and 02 and
P1's board at 390 and 1200 px, light and dark, in German; the UAT persona
over the journal page, Wealth's Performance and Allocation tabs and the
rail on a phone viewport. About 6 commits.

**Close-out** (the PR's last commits): `sprint-status.yaml`, `epics.md`'s
FR Coverage Map (FR-49) and a dated reconciliation, the idea list (I7, I16,
I17 `built`), the retrospective, the version report. About 5 commits.

**Estimate:** M 9–10, J 9, D 5, B 6, P 6, closing act 6, close-out 5:
**about 47**, under ADR-0026's 90 with room for one review round.

## Decisions

### D-1: what this sprint is for, and its exit criteria (recommended)

1. **I7 ships as FR-49:** one call answers every part of D-2's field list,
   each part equal to its own read on the seed (a test per part), the
   schema ceilings raised by no more than the new tool's own schema.
2. **The journal is reachable end to end:** a cursor walk from
   `since=1970-01-01` returns every entry exactly once, on a fixture with
   more than one page; the page's `since` and the API's name the same rows.
3. **#1378 closes by keyword**, J1's three writer kinds pinned.
4. **I17's four identities are pinned**, and the comparison's payload and
   screen state the same two figures.
5. **#1366's three open lines and #1357's rail line are ticked**, each
   pinned by its screen's functional test or the browser test, seen
   failing first.
6. **The browser tests run in CI** (the `browser` job green on the PR's
   head) and no PR head needs a re-run to turn green.
7. **The regressions this sprint introduced are counted** apart from the
   older findings, and none is an S1 at promotion.

**No criterion counts open issues.** Reported, not judged: 26 open today;
25 after #1378's keyword (the polish lists stay open while they have
lines).

**To flip by comment:** name a criterion to drop or add.

### D-2: I7's field list (recommended)

`GET /api/v1/securities/:id/dossier`, MCP `portfolixir.securities.dossier`,
read-only, `as_of` and a `parts` note naming the read each part mirrors.

| Part | What it carries | Built by (no second computation) |
|---|---|---|
| `security` | the record as `securities.get` answers it: identifiers and former ISINs, `thesis_state`, `bond` with its basis | the securities read |
| `holdings` | one row per portfolio holding it, as `holdings.list` filtered by `security_id` (quantity, cost basis, price with `price_source`, value, P&L and ADR-0033's decomposition, `computation_basis`), plus `total`, the security's `holdings.by_security` row (EUR, `valued`, `unvalued_reason`) | the two holdings reads |
| `metrics` | the derived metrics at the read's default window, with their `computation_basis` | `securities.metrics` |
| `research` | the newest 5 log entries, `has_more`, and the read that pages the rest | `notes.list` |
| `events` | every upcoming event and the newest 5 past ones, `has_more` | `events.list` |
| `categories` | each classification the security is filed in, with its category path (`null` where it is not filed) | `Classifications.list_trees/0`, which the security page's Classifications tab reads; today an agent assembles this from one tree read per classification, so this part is new to the agent |
| `targets` | every position SOLL row naming the security (portfolio, classification, category, `target_weight`, `stale`), and the read that states its drift | `targets.list_positions` |

**Left out, deliberately:** quotes, trades, lots and transactions (each a
long series with its own paged read), and drift (it needs a classification
and a valuation per portfolio; the allocation read states it, and the
`targets` part names that read). **Human view:** the security page as it
stands for every part but `targets`, whose view is the Classifications page
(the correction at the top). **To flip by comment:** name a part to add or
drop, or "I7 drift", which computes each SOLL row's drift in the dossier.

### D-3: #1378, answer (a), signed by this merge (recommended)

[ADR-0017's amendment of 2026-11-04](../../docs/decisions/0017-append-only-audit-journal.md)
says it in full. A delete's `after` is null from the cut-over release on,
for every writer, set in one place; the older entries keep their two shapes
and the API reference documents them with the release that ended them.
**Why (a):** `after` then means one thing for every operation, "what stands
after the write"; the deleted record stays in `before`. **To flip by
comment:** "#1378 (b)", which documents both shapes and changes no writer.

### D-4: I16 is the family's `since=`, and the page filters by date (recommended)

**I16 is not the no-brainer its row said.** Its premise, "answered by
paging", is wrong: the journal has no paging, so `since=` is the only way an
agent can reach entries past the newest 1000. The shape is therefore the
family's paged delta (K17), not a bare filter: oldest first with a cursor,
so a walk from any date reaches everything once. **The page stays newest
first** within the cut, because a screen answers "what changed this week"
and a poller walks forward; the rows are the same. **Board 01 picks A**, one
date field „Seit“ (Q1): any cut the agent hands over shows as itself, which
a chip row cannot. **To flip by comment:** "Q1 B" (the chip family), or "I16
newest first", which keeps the API newest first under `since` and leaves
entries past 1000 unreachable.

### D-5: the browser tests run in CI, with a pinned Chromium (recommended)

Sprint 23's retrospective asked: CI installs a pinned Chromium for
`test/browser`, or the closing act runs the browser tests by rule.
**CI, because a rule that depends on someone remembering is the failure the
maintenance lane was created for** (sprint workflow §5), and C1's flake was
found only at integration, not by the closing act. The cost is one job of a
few minutes and a lockfile Dependabot watches. The pin lives in
`test/browser`'s own lockfile, not in `mcp-server`, because the companion
must stay installable on its own (`AGENTS.md`). P2 is the second browser
test and runs in the same job. Required-check status is a repository
setting, so it is your optional ask 3. **To flip by comment:** "browser by
rule": M1 shrinks to a sentence in the sprint workflow's §3, and D-1
criterion 6 drops its first half.

### D-6: one PR, no stack (recommended)

About 47 commits, so one PR merged by your "Rebase and merge" button; the
stacked-PR step of Sprint 23's D-6 does not arise. The build order is the
plan's lane order (M, J, D, B, P), so history goes forward only. A PR
nearing 85 commits is cut at its last finished lane into a stacked PR,
named in the briefing, and retargeted to `main` before its merge is asked
for, as Sprint 23's D-6 said.

### D-7: the maintenance lane's three questions (recommended)

- **#727's OTP trigger has not fired.** ecto 3.14.3 is a patch with four
  query-cache fixes and no opaqueness entry, and ecto_sql is unchanged at
  3.14.0. The changelog read is weaker than the trigger's own test ("a
  `mix dialyzer` on an OTP 28+ PLT comes back clean"), so M3 runs that
  test once if an OTP 28 build is installable in the session, and says
  which it did.
- **#727's Elixir half was only ever tested at 1.20.x.** M4 tries 1.19.x
  once; a green run in CI turns it from a blocked trigger into a move.
- **BMAD `tea`:** read with bmb before the bump, because two majors can
  rename the `bmad-testarch-*` skills the docs and the agents call; the
  read is the evidence for taking or declining it.

### D-8: the boards and their picks (recommended; silence adopts them)

Under `_bmad-output/planning-artifacts/design-language/mockups/ux-design-2026-11-04-sprint24/`,
captured from a review instance on the synthetic seed with the shipped
`priv/static/app.css`; the README lists the picks, the new strings and what
was invented.

- **Board 01, the journal since a date (I16):** today; **A**, a date field
  „Seit“ (Q1, recommended); B, a chip family „Zeitraum“.
- **Board 02, the costs beside the gap (I17):** today; **A**, one line
  under the rows and one ⓘ sentence (Q2, recommended); B, each row split
  into costs and a residual labelled "selection and timing", drawn to show
  why not: the residual is not that (ADR-0046's amendment, point 4).

**What needs no board, and why:** P1's sunburst return and P2's rail
persist change behaviour and leave the picture identical (the sprint
workflow's exception). **What gets its board in the sprint:** P1's two
layout lines are conformance repairs to anatomies already signed (#1145's
name column; the phone rows Wealth's other tables use), so the
implementation session captures their before and after as one board
commit before P1's code, with Sprint 23's tooling, as Sprint 23 did for
Lane I.

### D-9: the closing act and the build (standing, with Sprint 23's carry-forwards)

Each lens reviews the PR's diff and reports at most five findings, ranked
by severity. Sprint 23's carry-forwards apply as rules of this build:

1. **commit before a long gate run**, so a container restart loses nothing;
2. **an integration runs its gates in the foreground**;
3. **a story's scratch files live in its worktree or a story-named path**;
4. **a remedy or a prefill is tested by following it literally**: J3's
   link `/journal?since=…` is opened as the agent would hand it over, and
   the cursor the API answers is fed back as the next `since`.

Every catalogue integration uses Sprint 23's E2 tool; one "Closes #n" line
per issue; a money identity is checked at a moving rate too.

### D-10: the idea that goes deep: F1, predictions and calibration (your question)

F1's row holds the use case worked through on 2026-11-03: **measure the
agent**, not trade better. The small shape: a prediction entry (direction,
probability, resolution date, benchmark, author, the decision it belongs
to), resolved automatically against stored quotes, and a calibration
report per probability band and per author. Its open question is yours: is
"measure the agent" at this shape accepted, which opens B4.2?

**The recommendation is yes, with four conditions the row does not have
yet**, because without them the report measures noise:

1. **The sample is the binding constraint, not the code.** FR-47's
   acceptance says "after ten resolved predictions"; ten predictions over
   five probability bands is two per band, and a hit rate of two is not a
   calibration. The headline is therefore one score over all predictions
   (Brier, with its uncertainty), and a band is shown only above a minimum
   count the payload states. Expect the first year to read mostly "too few
   to tell"; that is the honest answer, not a defect.
2. **"The agent" is not one author.** Models change under the same token.
   The author is the actor label plus the model the agent states at write
   time, so the report can split by model; otherwise it averages several
   forecasters into none.
3. **Calibration alone rewards hedging.** An agent that knows it is scored
   can say 50 % to everything and be perfectly calibrated. The report
   shows sharpness (how far the stated probabilities sit from 50 %) beside
   calibration.
4. **Resolution needs a quote on the resolution date** for the security
   and the benchmark. The sync keeps fetching quotes for securities no
   longer held (verified above), so a sold position still resolves; a
   security with manual quotes only does not, and is named unresolved
   rather than guessed.

**What "yes" commits to:** the next planning PR writes B4.2's ADR (FR-46
and FR-47 narrowed to this shape, the four conditions, the ladder (c)
basis, no LLM in the app) for your signature by merge; a later sprint
builds it. **"No"** parks F1 with your reason in its row. Silence leaves it
`discussing`.

### D-11: what stays open, and why (standing)

#894 (F21) is Sprint 25's first candidate. #899, #900, #1070 and #1220 keep
Sprint 22's reasons. #1177 waits for its trigger (a switcher's export with
those two types). #328 and #354 wait for your check on real data. The
polish lists stay open while they have lines; a story that touches a
screen fixes its lines.

## Registry bookkeeping after the merge (the planning session's last step)

- File I7's issue (FR-49, pointing at D-2 and `epics.md`) and I17's issue
  (pointing at ADR-0046's amendment and board 02), each under its area
  tracker (#419 and #418); I16 rides #416 with J2 and J3 named; relabel
  #1378 from `needs-decision` to `agentic` only (answered by D-3).
- No closures by hand.

## Checklist (the implementation session ticks it on the PR)

- [ ] Lane M: M1 browser job, M2 tea (read, then taken or declined), M3
      version report, M4 the 1.19 attempt
- [ ] Lane J: J1 (#1378), J2 (API `since`), J3 (the page's field)
- [ ] Lane D: D1 (the dossier)
- [ ] Lane B: B1 (`costs_paid`), B2 (the line)
- [ ] Lane P: P1's board commit, P1 (Wealth), P2 (the rail)
- [ ] Closing act, fixes, re-check
- [ ] Close-out, retrospective, briefing, promotion
