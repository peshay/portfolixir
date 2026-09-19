# Sprint 13 — the dates that were invisible, the numbers the history already holds, and E11 closed

**Status: ADOPTED by the merge of the Sprint 13 planning PR (2026-09-19).**
The merge is the signature (ADR-0026 step 1 as amended on PR #780): it adopts
the lane cut AND signs two decision gates — **[ADR-0047](../../docs/decisions/0047-derived-metrics-per-security-and-per-view.md)**
(derived metrics, FR-39/FR-40) and **[ADR-0048](../../docs/decisions/0048-security-events-as-first-class-objects.md)**
(security events, gate **B3.4**, FR-44) — together with **D-1** to **D-7** below. Nothing
in this PR is `DRAFT` or `Proposed`; a decision the owner rejects is removed
on the PR before the merge.

**Verification basis:** `main` at `1dc63d0` (the Sprint 12 close-out commit),
CI run 1527 green on it; the open-issue list of 2026-09-19 (30 open); the open
pull requests (one — Dependabot #819, the Node 26.8.2 image, opened
2026-09-18); the published releases (latest **0.10.0**, 2026-09-07); the
Sprint 11 and Sprint 12 retrospectives; the 2026-09-19 agent round
(`planning-artifacts/feedback-triage-2026-09-19.md`); and the code, read for
both ADRs and for that triage's claims rather than summarized from them.

## State of play, in five lines

1. **Sprint 12 merged and closed out.** PR #813 rebase-merged 2026-09-15,
   twenty-two issues closed, the retrospective written. E11's second alignment
   pass shipped; its tracker #356 stayed open deliberately, on seven issues.
2. **The remainder is small, named, and already declared.** #806–#809 were
   declared Sprint 13 candidates by Sprint 12's D-3 *before* that batch
   started; #815, #816 and #817 are its closing act's out-of-scope findings;
   #811 is Sprint 11's surface-check outlier. Nothing here is a surprise, and
   that is the point of having declared them.
3. **One item has a deadline, not a preference.** #814 is the human half of
   the holdings `fields=` fieldset, removed by #803 and filed the same day.
   The two-way coverage rule gives it the same or the next batch; this is the
   next batch. **Sprint 13's close-out must find #814 shipped or record a
   finding** — that is the rule's entire enforcement mechanism.
4. **Level (a) has been "issue-ready now" for four sprints with nothing
   filed.** The scope ladder released derived metrics on 2026-08-12 and the
   mechanism landed in Sprint 7. What was missing was a decision on what a
   metric is measured over, which is what ADR-0047 supplies and what this
   planning PR signs.
5. **The agent round of 2026-09-19 named one gap that hides risk rather than
   costing tokens**, and it was gated rather than unspecified: security
   events (FR-44, gate B3.4). Its calendar is built out of the holdings, so a
   security not yet owned has nowhere to keep a date. ADR-0048 closes that
   gate on this PR and Lane E builds it. The triage also refuted the round's
   most expensive claim for the third time (the research log does survive a
   re-import) and turned its `?since=` complaint into a precise, filable
   surface gap.

## Why this cut

- **The surface close finishes an epic, and most of it is small.** Seven items
  sit under #356. One (#815) is a duplicate that closes with its twin; three
  more reuse a mechanism that shipped last sprint — #816 reuses #800's filter
  sheet as it stands, #817 copies five declarations from `.area-tabs`, #809
  pre-fills the #803 drawer. That leaves #807 as the one real build and #806
  and #808 as contained surfaces. Closing them closes tracker #356 and ends
  the review cycle the 2026-09-12 whole-surface pass opened, rather than
  carrying a third alignment pass into the next quarter.
- **The events lane is the one item that hides risk, and it is now gated.**
  A dated calendar fact about a security that books nothing, tracked for the
  **whole catalog** rather than the holdings, entered by hand or by the agent
  and fetched by nobody. ADR-0048 closes B3.4 and says no, with reasons, to
  the three things such a table invites and nobody asked for.
- **The metrics lane is gated properly too, and it gives up half its scope to
  make room** (D-7). It ships behind a signed ADR with seven pinned
  identities, carries the **risk-tier attention label** (money math on the
  analytics surface), and extends surfaces that already exist rather than
  inventing new ones.
- **The two do not fight over files.** The metrics engine work is in
  `catalog/`, `portfolios/risk.ex`, the API layer and the MCP companion; Lane
  C is in LiveViews and `app.css`. They meet in exactly two files, and the
  sequencing below puts the metrics' human views *after* Lane C has finished
  with them. That is why this is one branch and not the two-branch
  ordering problem D-1 of Sprint 12 had to solve.
- **What waits, and why:** the level (b) requirements (FR-41 contribution,
  FR-42 exposure) stay unfiled — each needs its own argument, and FR-42's
  boundary against partial-weight advanced classifications is a decision, not
  a story. #328/#608 (lifecycle merges) and #354 (backup/restore) stay on the
  backlog; neither has a signed gate and neither was declared for this batch.

## Lanes

### Lane A — derived metrics (FR-39, FR-40; ADR-0047; risk-tier; first)

Four commit groups. Issues are **filed at branch opening, not now** — the
precedent is the 2026-08-15 round, where the decision items were held back
until their ADRs were signed so that no issue ever carried a title with no
spec behind it. This PR's merge is that signature; Lane Z files them and
records the numbers in the FR Coverage Map.

- **A1 — the per-security metrics engine and its read.** SMA-50/200 with the
  distance to each, realized volatility, maximum drawdown with peak/trough/
  recovery, momentum over 3M/6M/12M, distance to the 52-week extremes. Over
  the split-adjusted close series in the **security's own currency**
  (ADR-0047 §1). `GET /api/v1/securities/:security_id/metrics` and
  `portfolixir.securities.metrics`. TDD first with exact-`Decimal` fixtures;
  I2, I5 and I7 land here.
- **A2 — the portfolio and view figures on the risk read: MOVED TO SPRINT 14**
  by D-7, to make room for Lane E. Volatility, maximum drawdown with its
  window, risk-adjusted return and the Top-N correlation matrix, additive on
  `GET /api/v1/portfolios/:portfolio_id/risk` and `portfolixir.portfolios.risk`.
  It is the heavier half — it needs the TTWROR chain's flow-adjusted factors —
  and nobody is blocked on it. **ADR-0047 stays signed whole; only the build
  order moves**, and with A2 goes **I1**, the identity the record exists for
  (a deposit is not a return). I1 is pinned when A2 lands, not before, and
  Sprint 14's plan names it.
- **A3 — the human view, now one.** The per-security figures on the securities
  detail's **chart tab**, beside the price history it already renders. After
  Lane C (sequencing below), and on the same screen Lane E's event list
  lands on, so both go in one pass over one surface.
- **A4 — the boundary, mechanically.** The key-set meta-test of ADR-0047 §7:
  the metrics payload carries no signal, recommendation, rating, score or
  action key. Rides A1 rather than trailing it, because a boundary test
  written after the payload tends to describe the payload; it is extended to
  the portfolio payload when A2 lands.

**Named and filed, not built:** the per-security invalidation basis
(ADR-0047 §8). `BlastRadius.for_quote/1` answers *the portfolios that ever
transacted the security*, so a quote write for a security no portfolio has
ever held bumps nothing — which is why `security_metrics` registers at
lifetime `:none` and why any later move to `:request` or `:durable` needs
that basis first. Filed as its own issue in this lane (Scope Lock), with the
durable-activation measurement question attached to it.

### Lane B — the coverage debt with a deadline (#814)

The column picker for the holdings projection's valuation fields, on the
Wealth holdings positions table — the human half of `fields=` that left with
the Transactions holdings panel in #803. **Does not shrink.** The whole value
of the two-way rule is that its deadline is enforced somewhere, and the only
place it is enforced is this batch's close-out.

### Lane C — E11's close (#807, #809, #816, #817, #808, #806)

Six issues, one commit group each, closing tracker #356.

- **#807 — the Realized-gains facet becomes the Trades view.** Three figures
  (realised total, hit rate, average holding period), the closed round-trips
  from `Ledger.TradeMatcher` across all portfolios on the facet's FX basis,
  the year matrix behind a "Realisiert je Periode" disclosure. The largest of
  the six and the one that carries a decision (D-3). If the three figures are
  added to `/realized_gains` and its MCP twin they state their computation
  basis in the payload; if the UI derives them from rows already sent, the PR
  says so.
- **#809 — edit a booking from the history.** "Bearbeiten" in the row menu
  opens the #803 drawer pre-filled; saving carries `Ledger.update_transaction/3`
  and the derived holdings follow. **No new API or MCP surface** — this is the
  human view for a capability that has existed since before the coverage rule,
  which is why Sprint 12's close-out opened its ledger with it.
- **#816 — the transaction history's filter sheet.** Reuses `filter_families/1`,
  `family_chips/1` and the `open_filter_sheet` / `close_filter_sheet` /
  `reset_filters` events from `securities_live.ex` and the `.filter-sheet*`
  block as they stand. Desktop untouched above 560 px.
- **#817 — the detail pane's tab row to the D6 shipped form.** Five
  declarations copied from `.area-tabs`, `scroll-snap-align: start` on the
  tab, the `border-bottom` baseline swapped for the inset shadow.
- **#808 — the classifications index as rows** (and #815 closed with it,
  D-4): one row per tree with its category count, assigned/unassigned
  securities, the plan it carries, the kebab, and `+` in the heading instead
  of the full-width button. The counts come from existing reads; the PR
  states the API n/a or adds them.
- **#806 — the accounts-and-depots bucket cell**, variant A as picked
  2026-09-14: chips with a scope sub-line, "getrennt taggen" into the row
  menu, "Liquiditätsrolle" once in the head. `needs-uat`: the owner reads and
  edits one bucket cell at the closing act.

### Lane D — the API family's one outlier (#811)

`GET /api/v1/journal` moves off its own `limit_param/1` onto
`PortfolixirWeb.Api.V1.ListLimit.parse/3`, so an out-of-range limit answers
422 with the applied bound instead of clamping silently. The refusal is a
visible behaviour change, so it is recorded in the contract manifest (#752).

### Lane E — security events (FR-44; ADR-0048; gate B3.4; new)

The object the 2026-09-19 agent round ranks above everything else it asks
for, and the only one of its open items that hides risk rather than costing
tokens. Issues filed at branch opening with Lane A's, after the signature.

- **E1 — the table and its context.** `security_events` keyed on
  `security_id` and nothing else, **journaled from its first migration**
  (the ADR-0044 precedent — an agent writes these rows). `kind` as a fixed
  `Ecto.Enum` with a gettext label clause per member and no `to_string`
  fallback, the way Sprint 12's meta-test now requires; `timing` as the
  four-value qualifier (`exact`, `estimated`, `window`, `month`) so a guess
  is never stored as a filing; `source_quality` reusing ADR-0044's four-value
  vocabulary rather than inventing a second scale. No `Decimal` anywhere —
  an event carries no money.
- **E2 — the four reads, on API and MCP.** One security's events; **upcoming
  across the catalog within N days** (the read the agent is missing, whole
  catalog by default, `held_only=true` as an opt-in); unconfirmed events
  whose date has passed; events whose `checked_at` is older than N days. A
  `window` or `month` event is due when **any** day it could fall on is
  inside the horizon — conservative, because the failure being prevented is
  a missed date.
- **E3 — the per-security list on the detail pane**, in the shape the
  research timeline already uses. The catalog-wide upcoming surface is the
  half that may slip; if it does, **the close-out records the coverage
  deadline** rather than letting it inherit one quietly (ADR-0048
  Consequences).
- **E4 — the re-import guarantee, extended before anyone asks.**
  `reimport_preservation_test.exs` gains the event assertions and the
  integration documentation's Imports section gains the sentence. Cheap to
  hold, expensive to discover missing — and the round that prompted this lane
  spent three editions worrying about exactly this for the research log,
  where it was already true.

**Not risk-tier** (no money math, no projection semantics, no import
idempotency), but the journaling seam and the enum boundary are where the
review reads carefully.

### Lane M — maintenance (always present)

- **Dependabot #819 (Node 26.8.2-alpine3.24):** close with the reason Sprint
  11 gave #774 and Sprint 12 gave #782 — Node 26 is Current until October
  2026, the trigger is the LTS promotion, and the runtime is pinned in four
  places by an invariant test. **This is the third time the same PR is closed
  for the same reason**; if the October promotion has landed by lane time, it
  is applied instead, as its own commit.
- **#727 (Elixir 1.20.x / OTP 29):** both triggers re-checked at lane time, as
  in Sprint 11 and Sprint 12. Still its own branch and PR when it fires — the
  three-things-move-together argument in the issue is unchanged.
- **Hex, npm, PostgreSQL, BMAD and the external BMAD modules** reviewed; what
  passes the gates is applied as its own commit or commit group, and what is
  deliberately not updated is reported with its reason in
  `version-report-2026-09-XX-sprint13.md`, written **before** the closing act
  starts.

### Lane Z — registry (small)

- **E22 — Derived metrics** exists from this planning PR: the Tracker Index
  line and the `epic-22` / `epic-22-retrospective` keys in
  `sprint-status.yaml` are written here, so the close-out reconciles against a
  row rather than inventing one. **Lane Z files its tracker issue** at branch
  opening (area #418) and records the number on that line.
- The **FR-39 and FR-40 row** in the FR Coverage Map already names ADR-0047
  (written on this PR); Lane Z adds the story-issue numbers to its issue
  column once they are filed.
- **AR-3 is amended on this planning PR, not at branch opening** (ADR-0047
  §4): the float island is `:math.pow/2` in the IRR solver and in the
  benchmark's daily factor, plus `:math.sqrt/1` for the new deviation and
  correlation figures. The requirement said "single named exception" while the
  code already had two.
- **E23 — Security events** gets the same treatment as E22: the Tracker Index
  line and the `epic-23` keys are written on this planning PR, its tracker
  issue and stories are filed at branch opening, and FR-44's coverage row
  moves from **gated** to those numbers.
- **The 2026-09-19 triage's two filed items** are filed here as declared
  Sprint 14 candidates: FR-38's surface gap (`?since=` on the reads a
  scheduled run polls — it exists on two today) and the delivery finding
  (the re-import preservation guarantee belongs in the MCP tool descriptions
  of the reads it protects, not only in a documentation page).
- The close-out reconciles against these rows; **E11 closes here** if Lane C
  ships whole, and #356 is closed by hand with the evidence, since a tracker
  takes no closing keyword.

## Decisions

### D-1 — one branch, with the file order that makes it safe (recommended)

`agent/claude/derived-metrics-and-e11-close`, opened on `main` at or after
`1dc63d0`. Two epics on one branch is the exception, not the rule, and it is
taken here because the lanes touch disjoint files everywhere except two
LiveViews. The ordering in "Sequencing" is the whole safeguard: Lane C
finishes with `securities_live.ex` and the Wealth surface before Lane A's
human views open them. Rebased onto `main` at least daily (ADR-0026 step 2);
the branch lives days, not weeks.

### D-2 — what ships agent-first still gets its human view here (recommended)

ADR-0047 §9 and ADR-0048's Consequences both say the human views land in the
same batch as the API and MCP surface rather than taking the grace period
the coverage rule allows. The reason is #814 sitting in Lane B: an
agent-only capability whose view is "due next batch" is exactly the debt
this sprint is paying off, and creating two more in the same sprint would be
the rule satisfied on paper.

Concretely, after D-7 that means **two views, both on the securities detail
pane** — A3's per-security metrics on the chart tab, E3's event list in the
research timeline's shape — which is why the sequencing puts them in one
pass. The two that are allowed to slip are named rather than assumed: Lane
A2's portfolio figures go to Sprint 14 **with their API surface** (D-7), so
no gap is created; and Lane E3's catalog-wide upcoming surface is the one
place where API may land without its view, in which case **the close-out
records the deadline** rather than letting it inherit one quietly.

### D-3 — #807's decision is signed; the label comes off (recommended)

#807 carries its own rule: *leaving the issue as filed signs it; a comment
moves the list to a Securities-area surface instead.* No comment arrived
between 2026-09-12 and this plan. So the Realized-gains facet **is** the
Trades view, the reconciliation the 2026-08-15 triage asked for is complete,
and the `needs-decision` label comes off at this planning, as Sprint 12's D-3
said it would. One table, specified once.

### D-4 — #815 is closed as a duplicate of #808, by hand (recommended)

Both describe `/classifications` as a bare bullet list that should read as
list rows; #808 is the specified one (review C11, with mockups and
acceptance), #815 is the closing act finding it. One story builds it, and
**#815 is closed by hand with the evidence** rather than by a keyword — a
keyword would record "done" against work that was never separate work, which
is the exception the PR-lifecycle rules name.

### D-5 — the closing act's conditions, plus Sprint 12's ordering fix (standing)

The #706 conditions stand unchanged: DE, one full pass at 390 px, light and
dark, on `priv/demo/finding_surfaces_seed.exs`, screenshots in a PR comment
rather than the PR body. Two additions this batch:

- **The patch-coverage listing is read from the last pre-promotion CI run.**
  Sprint 11 and Sprint 12 both found real defects in it and both landed the
  fixes *after* promotion, because the listing arrives with the promotion
  commit's own run. The fix is ordering, not discipline (Sprint 12 process
  finding 2), and this is the batch it applies to.
- **A risk-tier verification pass on Lane A**, taking ADR-0047's I1–I7 one at
  a time, findings verified before they are surfaced (ADR-0036 clause 2), with
  the callout in the reviewer briefing (clause 3).

### D-6 — the tags, including the two still outstanding (standing)

This sprint prepares **`0.13.0`**. Recorded once, plainly, because the
close-out mechanism cannot do it: **`0.11.0` and `0.12.0` were prepared by
their close-outs and have not been pushed** — the latest published release is
`0.10.0` of 2026-09-07, so two rollback points are missing for self-hosted
instances. The tag is an owner action by the 2026-09-07 decision and the
agent's credential cannot push one; the Sprint 13 close-out restates all
three commands in one block rather than adding a fourth in a new place.

### D-7 — Lane E goes in, and Lane A2 goes to Sprint 14 (recommended)

The agent round arrived after this sprint was cut, and taking its P0-4
seriously means the branch would carry **two new object families plus an epic
close** — more than "epic branches live days, not weeks" survives. So the
trade is made here rather than discovered by the shrink order halfway
through:

- **In:** Lane E (security events), whole — the table, the four reads on API
  and MCP, the per-security view, the re-import guarantee.
- **Out to Sprint 14:** Lane A2, the portfolio-scope metrics.

The argument is the agent's own and this plan adopts it: **a missing date
hides risk, a missing volatility figure costs tokens.** A2 is also the
heavier half of ADR-0047 and nobody is blocked on it, while A1 is the half
the agent's P1-5 actually asks for and it lands on the same screen as Lane
E's event list. ADR-0047 is signed whole either way; what moves is the build
order, and **I1 moves with A2** — the identity that a deposit is not a return
is pinned when the figures that could violate it exist, which is the right
time for it and the wrong time to forget it. Sprint 14's plan names it.

**To flip this by comment:** keeping A2 in means cutting Lane C to #807,
#809, #816 and #817 and moving #806 and #808 out. Either shape is a batch;
both in one is not.

## Sequencing

```
branch opens on main @ 1dc63d0 ──▶ Lane Z files the issues, the E22/E23 rows
Lane A1 ──── first: the per-security engine, its read, the MCP tool, A4
Lane E1/E2 ─ in parallel with A1: the table, the journaling, the four reads
Lane C ───── in parallel: LiveViews and app.css, no overlap with A1 or E1/E2
Lane B ───── #814 after C touches the Wealth surface
Lane A3 + E3 ─ ONE pass over the securities detail pane, AFTER C is done
              with securities_live.ex — the metrics on the chart tab, the
              events list in the research timeline's shape
Lane E4 ──── the re-import assertions and the docs sentence, any time after E1
Lane D ───── #811, independent, any time
Lane M ───── at lane time; the version report before the closing act
closing act ─ D-5's conditions, the risk-tier pass on Lane A, then promotion
```

## Shrink order (cut from the bottom, name the cut in the briefing)

D-7 already spent the first cut (Lane A2 is out). What is left to give, in
order:

1. **#806** (the bucket cell) → Sprint 14; pick A stands whenever it is built.
2. **#808** (the classifications index) → Sprint 14; #815 then stays open
   rather than being closed as its duplicate.
3. **Lane E3's catalog-wide upcoming surface** → Sprint 14, and **the
   close-out records the coverage deadline** (ADR-0048 Consequences, D-2).
   The per-security list stays: it is the cheap half and it rides A3's pass.
4. **A3** (the per-security metrics view) → Sprint 14 with the same recorded
   deadline. Last, because it costs one screen and discharges ADR-0047's
   same-batch clause.

**Lanes A1, A4, B, E1/E2/E4, D and the rest of C do not shrink.** #814's
deadline is this batch by rule. E1/E2 are the point of Lane E — an event
table nobody can read is not half a feature, it is none. E4 is four
assertions and a sentence. #807 has been deferred once already, by a triage
that deferred it so it could be specified once; deferring it a second time
would reproduce exactly the "the spec has been ahead of the build for four
sprints" finding Sprint 12 was cut to fix. #816, #817 and #811 are
single-file reuses of mechanisms that already shipped; if they do not fit,
nothing does.

## What is deliberately not in this sprint

- **ADR-0047's portfolio-scope metrics (Lane A2)** — moved to Sprint 14 by
  D-7, with I1. Named here so its absence is the plan and not an oversight.
- **FR-41 (contribution) and FR-42 (exposure decomposition)** — level (b),
  ungated, unfiled, and each needs its own argument. FR-42 in particular has a
  boundary to draw against partial-weight advanced classifications, which is a
  decision and not a story.
- **Everything else the 2026-09-19 agent round asks for**, each for a reason
  in the triage: the rebalancing digest (B3.5, and it needs the rules first),
  policy rules (**B3.6** — the round supplied a second independent
  observation of prose-rule drift, which is the strongest argument yet for
  opening that gate and is recorded as evidence for Sprint 14's planning),
  a collector or signal feed (**B3.3**), prediction calibration (FR-47, needs
  FR-46 at **B4.2**), and backtesting (ladder level **(d)**, a boundary
  rather than a backlog item). Two gates in one planning PR is the limit of
  what can be read and signed in one sitting; a rules engine deserves the
  care ADR-0047 and ADR-0048 got.
- **FR-38's surface gap and the triage's delivery finding** — filed by Lane
  Z as declared Sprint 14 candidates, not built here.
- **Durable activation of either new analytic** — a measurement decision
  (ADR-0039 C3), and for `security_metrics` blocked behind the invalidation
  basis Lane A files.
- **#328 / #608 (lifecycle merges), #354 (backup/restore), #333, #332, #330,
  #573, #567, #395, #314** — unchanged from Sprint 12's list. #314's ratchet
  rides this batch as it rides every batch.
- **Anything with a verdict in it.** No signal, no rule, no rating, no
  alert — ADR-0047 §7, pinned by A4's meta-test. A rule over a metric is FR-43
  and stays gated at B3.6.

## What "done" means for this sprint

1. The **per-security** metrics read ships on the API **and** MCP, every
   metric carrying its window and observation count over a payload-level
   `computation_basis`, and ADR-0047's I2, I5, I6 and I7 are pinned by tests.
   I1, I3 and I4's portfolio half ride A2 into Sprint 14 by D-7, and the
   close-out says so rather than letting the ADR look half-built.
2. **Security events exist as an object**: the journaled table with its enum
   label coverage and its timing qualifier, the four reads on API and MCP
   with the catalog — not the holdings — as the default scope, and the
   re-import guarantee extended and pinned (E4).
3. The human views render on the securities detail pane, or the close-out
   names the one that was shrunk and the deadline it inherits.
4. **#814 is shipped** — or the close-out records it as a finding, which is
   the rule working, not the rule being waived.
5. #807, #809, #816, #817, #808 and #806 are closed by the merge's keywords;
   #815 is closed by hand as #808's duplicate; **tracker #356 is closed** with
   the evidence, and E11 is done.
6. #811 is on the shared limit parser and the contract manifest records the
   refusal.
7. Lane M's report exists; #819 is closed with the LTS reason or applied if
   the promotion landed; #727's triggers are re-checked and the result
   recorded either way.
8. The closing act ran under D-5's conditions, the patch-coverage listing was
   read **before** promotion, and the risk-tier pass on Lane A is in the
   briefing.
9. The contract-version read reports both new surfaces, and the answers the
   triage's Part 6 owes the agent have gone back to it.
10. The `0.13.0` command is in the close-out, together with the still-unpushed
    `0.11.0` and `0.12.0`.
