# Sprint 13 — the numbers the price history already holds, and E11 closed

**Status: ADOPTED by the merge of the Sprint 13 planning PR (2026-09-19).**
The merge is the signature (ADR-0026 step 1 as amended on PR #780): it adopts
the lane cut AND signs **[ADR-0047](../../docs/decisions/0047-derived-metrics-per-security-and-per-view.md)**
(derived metrics, FR-39/FR-40) together with **D-1** to **D-6** below. Nothing
in this PR is `DRAFT` or `Proposed`; a decision the owner rejects is removed
on the PR before the merge.

**Verification basis:** `main` at `1dc63d0` (the Sprint 12 close-out commit),
CI run 1527 green on it; the open-issue list of 2026-09-19 (30 open); the open
pull requests (one — Dependabot #819, the Node 26.8.2 image, opened
2026-09-18); the published releases (latest **0.10.0**, 2026-09-07); the
Sprint 11 and Sprint 12 retrospectives; and the code, read for ADR-0047 rather
than summarized from prior claims.

## State of play, in four lines

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

## Why this cut

- **The surface close finishes an epic, and most of it is small.** Seven items
  sit under #356. One (#815) is a duplicate that closes with its twin; three
  more reuse a mechanism that shipped last sprint — #816 reuses #800's filter
  sheet as it stands, #817 copies five declarations from `.area-tabs`, #809
  pre-fills the #803 drawer. That leaves #807 as the one real build and #806
  and #808 as contained surfaces. Closing them closes tracker #356 and ends
  the review cycle the 2026-09-12 whole-surface pass opened, rather than
  carrying a third alignment pass into the next quarter.
- **The metrics lane is the batch's substance, and it is gated properly.** It
  ships behind a signed ADR with seven pinned identities, carries the
  **risk-tier attention label** (money math on the analytics surface), and
  extends two surfaces that already exist rather than inventing a third.
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
- **A2 — the portfolio and view figures on the risk read.** Volatility,
  maximum drawdown with its window, risk-adjusted return (risk-free as an
  explicit parameter defaulting to 0), and the Top-N correlation matrix in
  the base currency. **Additive** on `GET /api/v1/portfolios/:portfolio_id/risk`
  and `portfolixir.portfolios.risk`, both honouring the existing `?view=`.
  **I1 is this lane's reason to exist and its first test:** the figures read
  the TTWROR chain's flow-adjusted factors, so a portfolio with unchanging
  prices and any number of deposits has volatility exactly `0`.
- **A3 — the two human views.** The per-security figures on the securities
  detail's **chart tab**, beside the price history it already renders; the
  portfolio figures on the **Wealth risk surface**. Both after Lane C
  (sequencing below).
- **A4 — the boundary, mechanically.** The key-set meta-test of ADR-0047 §7:
  neither metric payload carries a signal, recommendation, rating, score or
  action key. Rides A1/A2 rather than trailing them, because a boundary test
  written after the payload tends to describe the payload.

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

### D-2 — the metrics' human views ride this batch (recommended)

ADR-0047 §9 says the two views land in the same batch as the API and MCP
surface rather than taking the grace period the coverage rule allows. The
reason is #814 sitting in Lane B: an agent-only capability whose view is
"due next batch" is exactly the debt this sprint is paying off, and creating
a second one in the same sprint would be the rule being satisfied on paper.
If the shrink order takes A3's portfolio half, **the close-out records the
deadline** — it does not quietly inherit one.

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

## Sequencing

```
branch opens on main @ 1dc63d0 ──▶ Lane Z files the issues and the E22 row
Lane A1/A2 ── first: the engine, the reads, the MCP tools, the meta-test (A4)
Lane C ───── in parallel: LiveViews and app.css, no overlap with A1/A2
Lane B ───── #814 after C touches the Wealth surface
Lane A3 ──── the human views, AFTER C is done with securities_live.ex
Lane D ───── #811, independent, any time
Lane M ───── at lane time; the version report before the closing act
closing act ─ D-5's conditions, the risk-tier pass on Lane A, then promotion
```

## Shrink order (cut from the bottom, name the cut in the briefing)

1. **#806** (the bucket cell) → Sprint 14; pick A stands whenever it is built.
2. **#808** (the classifications index) → Sprint 14; #815 then stays open
   rather than being closed as its duplicate.
3. **A3's portfolio half** (the Wealth risk figures' human view) → Sprint 14,
   and the close-out records the coverage deadline (D-2).

**Lanes A1/A2/A4, B, D and the rest of C do not shrink.** #814's deadline is
this batch by rule. #807 has been deferred once already, by a triage that
deferred it so it could be specified once — deferring it a second time would
reproduce exactly the "the spec has been ahead of the build for four sprints"
finding Sprint 12 was cut to fix. #816, #817 and #811 are single-file reuses
of mechanisms that already shipped; if they do not fit, nothing does.

## What is deliberately not in this sprint

- **FR-41 (contribution) and FR-42 (exposure decomposition)** — level (b),
  ungated, unfiled, and each needs its own argument. FR-42 in particular has a
  boundary to draw against partial-weight advanced classifications, which is a
  decision and not a story.
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

1. The per-security metrics read and the portfolio/view figures ship on the
   API **and** MCP, every metric carrying its window and observation count
   over a payload-level `computation_basis`, and ADR-0047's I1–I7 are pinned
   by tests — I1 (a deposit is not a return) by an exact-`Decimal` fixture.
2. The two human views render, or the close-out names the one that was shrunk
   and the deadline it inherits.
3. **#814 is shipped** — or the close-out records it as a finding, which is
   the rule working, not the rule being waived.
4. #807, #809, #816, #817, #808 and #806 are closed by the merge's keywords;
   #815 is closed by hand as #808's duplicate; **tracker #356 is closed** with
   the evidence, and E11 is done.
5. #811 is on the shared limit parser and the contract manifest records the
   refusal.
6. Lane M's report exists; #819 is closed with the LTS reason or applied if
   the promotion landed; #727's triggers are re-checked and the result
   recorded either way.
7. The closing act ran under D-5's conditions, the patch-coverage listing was
   read **before** promotion, and the risk-tier pass on Lane A is in the
   briefing.
8. The `0.13.0` command is in the close-out, together with the still-unpushed
   `0.11.0` and `0.12.0`.
