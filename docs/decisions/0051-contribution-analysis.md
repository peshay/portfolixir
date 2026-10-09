---
layout: docs
title: "ADR-0051: contribution analysis — which position made how much of a period's result"
description: "Design gate for FR-41 (scope-ladder level (b)), written in Sprint 16 and signed by the merge of the Sprint 17 planning PR. A money contribution per position over any period the performance walk already chains, scoped to a portfolio or a view, summing exactly in Decimal to the period's money result together with three itemised remainder lines. No share column, no currency split, no category grouping in v1, each deferred with a reason. Derived on read with a :request lifetime; the walk's existing outputs stay byte-identical."
---

# ADR-0051: contribution analysis — which position made how much of a period's result

- **Status:** Accepted. Owner sign-off is the merge of the Sprint 17 planning
  PR (ADR-0026 step 1, as amended on PR #780: the merge is the signature).
- **Date:** 2026-09-25 (written in Sprint 16; signed at Sprint 17's
  planning).
- **Amended:** 2026-10-03: what the building batch's review round found the
  record left open, with its notes of 2026-10-05 and 2026-10-06 (see
  "Amendment (2026-10-03)" below). 2026-10-09, adopted by the merge of the
  Sprint 21 planning PR: a security-linked interest booking is its
  position's income (#928; see "Amendment (2026-10-09)" below).
- **Answers:** FR-41, contribution analysis, scope-ladder level (b):
  *"which position produced how much of the return, over a selectable
  period, scoped to a view."*
- **This is not a scope gate.** Level (b) has been open since 2026-08-12.
  This is the design gate ADR-0026 step 1 requires before a batch starts, in
  the shape of [ADR-0047](0047-derived-metrics-per-security-and-per-view.html).
  Following [ADR-0043](0043-a-gate-closing-adr-names-its-asks.html), the
  closing table lists each ask as answered or deferred.

## Context

At Sprint 16's planning (D-7), the FR Coverage Map asked whether FR-41 is a
thin extension of [ADR-0041](0041-per-category-performance.html)'s category
result. **It is not.** ADR-0041's figure is defined by having no period ("no
period, no membership variant and no as-of qualifier to choose"). FR-41 asks
what each position produced **over a period, scoped to a view**. It needs four
things the category result lacks: a period, the positions sold inside it,
flows, and the view scope. ADR-0041 left out the first three on purpose.

The engine that has all four is the performance walk
([ADR-0010](0010-ttwror-performance-series.html)), `Portfolixir.Portfolios.Performance`.
The walk:

- values every security every day;
- applies every booking through the single per-kind reducer
  ([ADR-0011](0011-unified-ledger-projection.html));
- knows each day's external flow, the #545 basis step and the #708 trade
  costs;
- honours the view scope
  ([ADR-0019](0019-view-scoped-performance-boundary-flows.html),
  [ADR-0024](0024-buckets-and-views-replace-portfolios-in-the-ui.html));
- chains any period (a preset, a calendar year or a custom range) out of one
  walk, through `summarise/2`.

Then it **sums the per-security figures away** in three places:

- `portfolio_value/2` reduces the positions to one number per day;
- `trade_costs/2` keeps costs per day, not per security;
- `basis_adjustment/5` computes the basis step per security and then adds the
  steps up.

Mechanically, FR-41 is the walk **keeping those figures apart** inside a
window.

Two figures already on the Wealth performance surface constrain the answer:

- the **TTWROR**, which is time-weighted, with flows and basis steps
  neutralised;
- beside it, the period's **money result**, `end value − start value − net
  external flows`, shown as "+x EUR in the period".

A contribution table must agree **exactly** with one of them. Otherwise it is
a third number that nobody can reconcile.

One fact comes from the same sprint's bond discovery
(`planning-artifacts/bond-discovery-2026-09-25.md`). An interest booking
carries no security, so a bond's coupons reach the cash account with no link
to the bond. That matters for the income term in §1 and the remainder in §3.
*The 2026-10-09 amendment keeps the link on import (#928).*

## Decision

### 1. The method: a money contribution that sums exactly to the period's money result (Q1)

| Option | What it is |
|---|---|
| **A: money contribution** *(recommended)* | Per position, in the base currency: `contribution = end value − start value − net flows into the position + income − costs` over the window. The positions plus the remainder (§3) sum to the money result beside the TTWROR. |
| B: percentage-point contribution, linked to the TTWROR | Each day's return splits exactly across the positions, because they share the day's return base: `c(i,d) = (V(i,d) − V(i,d−1) − F(i,d) − B(i,d) + income(i,d) − cost(i,d)) ÷ (V(d−1) + F(d) + B(d))`. Across days, the geometric chain is not a sum, so the days need a linking method. |
| C: both | A in the table and B as a second column. |

**A for v1.** It answers the question in the operator's money. Every term is
an amount that can be traced to bookings and to two valuation days, so the
figure can be checked by hand. It agrees to the cent with a figure the screen
already shows. It also follows ADR-0041 §2's lesson: weight by money and
never average percentages.

**B is deferred, with a reason, and it is cheaper than D-7 feared.** Carino
linking uses logarithms and would need a float exception that AR-3 names. The
multiplicative linking (GRAP/Frongello) does not:
`linked(i) = Σ_d c(i,d) × ∏_{s<d} (1 + r(s))`. It telescopes to exactly
`∏(1 + r(d)) − 1`, the TTWROR, in `Decimal` alone. What stays expensive is the
rest:

- the walk has to keep flows and basis steps per security;
- the figure rests on a linking convention the reader cannot see in it;
- a contribution changes whenever an unrelated earlier day changes.

If a consumer asks for return attribution in percentage points, B builds on
the accumulators of §5 with multiplicative linking and no float. It is filed
as an issue at the signature.

The terms of A are defined as follows:

- **Start value.** The position's value in the base currency at the close of
  the last day the walk covers before the window. It is 0 when the position
  was not held then (§4).
- **End value.** The position's value at the window's last day. It is 0 when
  the position was sold out.
- **Net flows into the position.** A buy counts `+ price × quantity` and a
  sell `− price × quantity`. A delivery counts `±` the value the walk's
  `F(d)` gives it: the booked price, or else the day's price (#779). A
  security transfer counts 0 inside one scope; §6 covers the boundary. Each
  flow is converted at the booking day's rate, exactly as the walk converts.
- **Income.** Dividends as credited, meaning the booking's amount, which is
  the net after the withheld tax recorded on it. This is the Income facet's
  "net". *The 2026-10-09 amendment adds the interest bookings that name the
  position's security, as credited.*
- **Costs.** The fees and taxes carried by the position's own trades. These
  are #708's trade costs
  ([ADR-0027](0027-plan-versions-and-depot-snapshots.html) amendment
  2026-08-15 §1), kept per security instead of per day.

### 2. No share of the total; the size is a bar (Q2)

| Option | Verdict |
|---|---|
| **A: money only, sorted, with a diverging bar per row** *(recommended)* | The bar reuses the drift bar's anatomy (DESIGN.md, issue 798) and is scaled to the largest absolute contribution. It is decorative and `aria-hidden`: the figure carries the sign and the colour (UX-DR7). |
| B: share of the period result (`contribution ÷ Σ`) | **Rejected.** It is undefined near a zero result. It goes beyond ±100 % and flips sign whenever positions pull in opposite directions, which is the ordinary case, not the edge case. |
| C: share of gross movement (`contribution ÷ Σ │contribution│`) | **Rejected.** It is always defined, but it is a share of nothing the reader holds, so it needs its own explanation. |
| D: percentage points of invested capital (`contribution ÷ (start value + net period flows)`, [ADR-0034](0034-money-weighted-metrics.html)'s invested capital) | **Deferred, with a reason.** It is defined whenever invested capital is positive. But the column sums to a simple period return that is neither the TTWROR nor the MWR shown beside it, which makes a third return on one screen. UX-DR26's stated-difference clause would have to carry it. |

### 3. What the contributions sum to, and the remainder (Q3)

**The positions plus the remainder lines sum to `end value − start value −
net external flows`, exact in `Decimal`.** That is the "+x EUR in the period"
figure, not the TTWROR (§1).

The remainder is itemised. Each line is computed from its own bookings:

| Remainder line | What it holds |
|---|---|
| Interest | Every `interest` booking: account interest, and bond coupons, which carry no security link today (bond discovery 2026-09-25). *Since the 2026-10-09 amendment, only the interest bookings that name no security* |
| Standalone fees and taxes | `fee`, `tax` and `tax_refund` bookings that no trade carries, even when one names a security. This is #708's definition; the asymmetry of dividend withholding stays ADR-0027 §2's follow-up |
| Currency effect on cash | The revaluation of cash balances in foreign currencies, plus the settlement difference of a cross-currency trade between its cash leg and its security leg on the booking day ([ADR-0015](0015-cross-currency-settlement-fx-rate.html), [ADR-0033](0033-per-position-pnl-fx-decomposition.html)) |

**What the remainder does not hold, because the result never contains it:**
deposits, removals, the value of deliveries, and the residual jump of a
balance snapshot. All four are external flows under ADR-0010 and ADR-0011, so
they are already outside `end − start − flows`. D-7 listed snapshot jumps as
a candidate for the remainder. The answer is that they never reach the
result.

**No line is a plug.** The remainder is never computed as "the result minus
the positions". The identity is pinned by tests (I1), so a line that drifts
fails a test instead of being absorbed into a balancing figure.

### 4. Periods reuse the walk's terms and its baseline rule (Q4)

- **Periods.** The accepted periods are exactly those of
  `Performance.validate_period/1`: `ytd`, `1y`, `3y`, `5y`, `max`, one
  calendar year, or a custom range. They are spelled as the performance
  endpoint spells them: `period=`, `year=`, and `from=`/`to=` through
  `PeriodParam`.
- **Start and end values.** The baseline rule is the walk's: the start value
  is the close of the last day the walk covers before the window. A position
  opened inside the window starts at 0.
- **Sold positions.** A position closed inside the window ends at 0 and
  **appears in the table**. The category result leaves this case out by
  construction.
- **Clamping and empty windows.** The window is clamped to the history as
  the walk clamps it. An empty window is the walk's honest emptiness: an
  empty table and the empty-state sentence, never a table of zeros.

### 5. Flows per position: what the walk has to keep (Q5)

The walk already applies every leg per security. The contribution needs four
accumulators per security inside the window: net flow, income, costs, and the
values at the two ends.

| Booking kind | Flow into the position | Income | Cost |
|---|---|---|---|
| buy | `+ price × quantity`, at the booking day's rate | — | fees + taxes on the booking |
| sell | `− price × quantity` | — | fees + taxes on the booking |
| inbound / outbound delivery | `±` the value `F(d)` gives it (#779) | — | — |
| security transfer | 0 inside the scope; a boundary flow when one depot is out of view (§6) | — | — |
| split | 0 (a scale leg, [ADR-0028](0028-corporate-actions-as-ledger-events.html)) | — | — |
| dividend | — | `+` the credited amount | — |
| interest, fee, tax, tax refund | — (they go to the remainder, §3) | — | — |
| *interest naming a security (the 2026-10-09 amendment)* | — | `+` the credited amount | — |
| deposit, removal, cash transfer, balance snapshot | — (cash only) | — | — |

**#545's basis steps are part of a position's contribution.** They change the
position's money value, and the money result beside the TTWROR includes them,
because the walk never lets `B(d)` touch value or flows. Option B of §1 would
need the steps per security, and the walk already computes them per security.

**Hard requirement.** With the accumulators on, the TTWROR, the IRR, the
series and every other existing output of the walk stay **byte-identical**
(I9). The accumulators only read legs the walk applies anyway, and the walk's
computation version does not move.

### 6. View scope and the endpoint family (Q6, #901)

The contribution is scoped the way the walk is scoped: one portfolio,
optionally narrowed with `view=`, or a view across all portfolios
(ADR-0024). Inside a scoped walk, a leg that straddles the boundary is
already a boundary flow (ADR-0019). Per position, a security transfer from a
depot in view to one out of view is a flow out of that position at the moved
value. The position's contribution is therefore not charged with the move.

**The family, named now** so the close-out's surface check states it instead
of discovering it (AGENTS.md → Surface check):

- `GET /api/v1/portfolios/:portfolio_id/performance/contribution` with
  `view=`, `period=`, `year=` and `from=`/`to=`, and the MCP tool
  `portfolixir.portfolios.contribution`;
- `GET /api/v1/views/:view_id/performance/contribution` and the MCP tool
  `portfolixir.views.contribution`.

This mirrors the performance and benchmark families exactly: `performance`
and `performance/benchmark` exist under both `/portfolios/:portfolio_id/` and
`/views/:view_id/`.

**#901 is not a prerequisite.** It adds a view scope to the category result,
whose family (`category-results`) is a different one. #901 lands in Sprint
17's batch as well, in the same two-form shape, so the two reads over
positions take their scope the same way. Its own close-out names its own
family.

### 7. Currency: stated, not split (Q7)

| Option | Verdict |
|---|---|
| **A: base currency, currency move included, stated in the basis** *(recommended)* | The contribution of a foreign-currency position is its money result in the base currency, and the basis says that it includes the currency move. |
| B: a price and currency split per position over the period (ADR-0033's decomposition, taken over a window) | **Deferred, with a reason.** It needs per-security currency attribution every day, which doubles the accumulators, and it needs a definition of the currency return of a flow booked in mid-period. ADR-0033 defines neither. It is filed as an issue at the signature. |

A position in a currency with no rate path is handled by §10.

### 8. Grouping by category: none in v1 (Q8)

| Option | Verdict |
|---|---|
| **A: none, positions only** *(recommended)* | This is what FR-41 asks for. |
| B: by today's classification, with a basis line | **Deferred, with a reason.** It is honest if the basis line says "grouped by today's tree; a position that moved category carries its whole period contribution with it". But it applies a current-composition grouping to a period figure. That is exactly the tension ADR-0041 §1 removed from its own figure by dropping the period. "Which category made this period's result" belongs with the membership timeline. If the owner wants the grouping earlier, B is its shape. It is filed as an issue at the signature. |
| C: by membership over time | **Not here.** It needs ADR-0041 §6's membership timeline, which has its own gate. |

The contribution never appears in the classifications tree (§12).

### 9. ADR-0041 §5's slice two is not absorbed (Q9, #900)

| Option | Verdict |
|---|---|
| A: absorb it | FR-41's per-position income and realized result, grouped by category, would become slice two. |
| **B: keep it separate** *(recommended)* | Slice two is a current-composition statement on the category row: what the securities filed there today have made, realized results and income included. FR-41 is a period statement on the Wealth performance surface. |

ADR-0041 §5 itself warns that an aggregate whose meaning silently changes
between screens undoes its §3. Merging the two would hand one of the two
readers the wrong basis. **#900 therefore stays a separate story**, with its
scope unchanged (slice two on the category result), and FR-41's PR does not
close it. The two can share code, such as `TradeMatcher`'s realized results
and the income series, but not a figure.

### 10. Missing data contributes zero, and the affected positions are named (Q10)

| Option | Verdict |
|---|---|
| **A: keep the walk's "contributes zero"** *(recommended)* | The identity holds. Every affected position is named, with the number of window days on which it counted zero and the reason (no price, or no rate path). |
| B: follow ADR-0041 §4 and exclude underivable positions | **Rejected.** It breaks I1, and the table would disagree with the money result beside it, which contains the same zeros. |

The two ADRs do not conflict. ADR-0041's figure has no second number to agree
with, and this one does.

On the surface, the affected positions appear in an attention data note under
the table, with their count and names (UX-DR25), and each affected row
carries a marker. In the payload, each position carries `unvalued_days` and
`unvalued_reason`. A position that counted zero stays in the sum.

### 11. The payload (Q11)

- **Basis.** `computation_basis` has the standard shape
  (`JSON.computation_basis/1`):
  - `input_series`: the daily valuation walk of ADR-0010, per position;
  - `window`: the start and end dates;
  - `reference`: `null`;
  - `gaps`: "counts zero; the affected positions are listed with their days";
  - `assumptions` (ADR-0046's key): the definition in §1, the identity in
    §3, and "base currency, currency move included".
- **Positions.** Each position carries `security_id`, `name`, `isin`,
  `start_value`, `end_value`, `net_flows`, `income`, `costs`,
  `contribution`, `held_at_start`, `held_at_end`, `unvalued_days` and
  `unvalued_reason`.
- **Remainder and totals.** `remainder` carries `interest`,
  `standalone_fees_and_taxes` and `cash_currency_effect`. `totals` carries
  `result` (`end − start − net external flows`), `positions` and
  `remainder`.
- **Decimals and ordering.** Financial decimals are strings and dates are
  ISO. Positions are sorted by contribution, largest first. There is no rank
  or label key: no "top", "best" or "detractor".
- **No verdict key (I8).** The payload carries no signal, recommendation,
  rating, score or action key.
  `test/invariants/metrics_carry_no_verdict_test.exs` walks this payload too.
- **Contract.** Sprint 17's batch adds one entry to the contract manifest:
  the version after the last one Sprint 16 ships. The MCP schema mirror and
  the EN/DE integration doc lines land with it.

### 12. Storage lifetime and the screen (Q12)

**Storage** ([ADR-0039](0039-durable-derived-values.html)):

| Option | Verdict |
|---|---|
| **A: its own analytic per scope and period** *(recommended)* | `performance_contribution` (portfolio basis) and `performance_view_contribution` (global basis), computation version 1, default lifetime `:request`. They are keyed like the walk analytics, plus the period. |
| B: per-security running sums inside the stored `performance_analysis` | Any period would be cheap, but every stored walk grows by securities × days, for a read most requests never make, and the walk's computation version moves for every reader. |
| C: `:none` | This is what A becomes if the measurement says a memo is not worth it. |

The ADR-0039 C3 measurement decides any later move to `:durable`.

**Screen.** The board
(`_bmad-output/planning-artifacts/design-language/mockups/fr41-2026-09-25/01-contribution-surface.html`
and its PNG, invented data only) shows three options:

- **A** *(recommended)*: a contribution table in **Wealth → Holdings →
  Performance**, directly under the chart. It shares the section's period
  control and the page's view, and its sum row equals the money figure of the
  section's badge. With more than ten positions, the table shows the ten
  largest by absolute amount and a "show all N" control. The sum row always
  covers every position. Under 560 px the table becomes two-line rows
  (UX-DR27).
- **B**: a third chart-series segment, "Contribution", that swaps the time
  series for a diverging bar chart. The table sits behind the chart-as-table
  disclosure (UX-DR10).
- **C**: a period column in the Positions table. **Not recommended.** A
  position sold inside the period has no row there, so the column cannot sum
  to the result. It would put a period figure into the current-composition
  projection, and the per-depot rows split one security across lines.

**Never in the classifications tree** (§8 and ADR-0041). The board's argument
lives on the board. The picked anatomy is written into `DESIGN.md` by the
story that builds it.

## What this record does not do

- **No factor, sector or region attribution.** FR-42 was retired on
  2026-09-23.
- **No benchmark-relative attribution.** Allocation and selection effects
  need a benchmark's composition, which is data acquisition (B3.3). ADR-0046's
  benchmark is a price series, not a composition.
- **Several deferrals, each filed at the signature:** no category grouping
  (§8), no slice two (§9), no currency split (§7), no percentage-point
  contribution (§1, B) and no share column (§2).
- **No new persisted column.** Everything is derived on read.
- **No signal, no ranking label and no action.** Level (b) decomposes a
  result that happened; the operator decides what it means.

## The identities the building batch pins

| | Identity |
|---|---|
| I1 | The positions plus the remainder lines sum to `end − start − net external flows`, exact in `Decimal`, for every period and every scope. *Precision stated by the 2026-10-03 amendment.* |
| I2 | With unchanging prices and exchange rates, and no bookings inside the window except deposits and removals, every position contributes exactly `0`, and so does every remainder line. |
| I3 | A position in the base currency, bought and sold entirely inside the window with no quote in between, contributes exactly `(sell price − buy price) × quantity − costs`. It appears in the table although it is held at neither end. |
| I4 | A deposit or a removal changes no contribution and no remainder line. *Worded for the booking by the 2026-10-03 amendment.* |
| I5 | A split inside the window changes no contribution. *ADR-0028's quantity rounding stated by the 2026-10-03 amendment.* |
| I6 | A transfer between two depots of one portfolio changes no contribution. In a view that sees only one of the two depots, the moved value is a boundary flow of that position. |
| I7 | A position that counted zero keeps its place in the sum and carries its `unvalued_days`, and the payload lists it. |
| I8 | The payload carries no signal, recommendation, rating, score or action key (the meta-test). |
| I9 | With the accumulators on, the walk's TTWROR, IRR, series and every existing output are byte-identical. The existing walk tests pass unchanged. |

*I10 to I13 are added by the 2026-10-09 amendment, below.*

## The asks, answered and deferred (ADR-0043)

**Where the asks come from:** FR-41 in the requirements inventory, the twelve
questions of Sprint 16's D-7, the two side findings D-7 names, and the
metric-basis rule in `AGENTS.md`.

| Ask | Source | Verdict |
|---|---|---|
| Which position produced how much, over a selectable period, scoped to a view | FR-41 | **Answered.** §1, §4 and §6 |
| The contribution method | D-7 Q1 | **Answered.** §1: the money contribution (A) |
| Percentage points linked to the TTWROR | D-7 Q1 | **Deferred, with a reason.** §1: no float is needed with multiplicative linking, but it needs flows and basis steps per security and adds a hidden convention. Filed at the signature |
| A share, near a zero total or with mixed signs | D-7 Q2 | **Answered.** §2: no share; a bar carries the size |
| Percentage points of invested capital | D-7 Q2 | **Deferred, with a reason.** §2: it would be a third return on one screen. Filed at the signature |
| What the contributions sum to, and the remainder | D-7 Q3 | **Answered.** §3: they sum to the money result; three itemised lines; snapshot jumps never reach the result |
| Periods and the baseline rule | D-7 Q4 | **Answered.** §4 |
| Flows per position, trade costs per security | D-7 Q5 | **Answered.** §5 |
| The view scope and the endpoint family | D-7 Q6 | **Answered.** §6: two endpoints and two MCP tools, named for the close-out |
| The currency split | D-7 Q7 | **Deferred, with a reason.** §7: no definition exists for a mid-period flow's currency return. Stated in the basis, and filed at the signature |
| Grouping by category | D-7 Q8 | **Answered for v1 (none).** Today's tree is **deferred, with a reason** (§8, filed at the signature); membership over time belongs to ADR-0041 §6's gate |
| Absorbing ADR-0041 §5's slice two | D-7 Q9, #900 | **Answered.** §9: not absorbed; #900 stays its own story |
| Missing data: contributes zero, or exclude | D-7 Q10 | **Answered.** §10: contributes zero, and the affected positions are named |
| The payload: basis, strings, contract, no verdict | D-7 Q11, `AGENTS.md` metric rule | **Answered.** §11 |
| The storage lifetime and the screen | D-7 Q12 | **Answered.** §12: `:request`; the screen goes to the board, where A is recommended |
| The category result's view scope on API and MCP | #901 | **Answered as sequencing.** §6: not a prerequisite; it lands in the same batch in the same shape |

## Consequences

- **Risk-tier attention** ([ADR-0036](0036-risk-tier-rides-the-batch.html)).
  This is money math inside the walk. It ships in its own commit group, TDD
  first, with exact `Decimal` fixtures. The verification pass takes I1 to I9
  one at a time, and the reviewer briefing calls it out. I9 is the invariant
  that protects everything already shipped.
- **Registry.** FR-41's row in the FR Coverage Map changes from "no issue
  yet" to the issue numbers the building batch files. The Tracker Index gains
  the line. The sprint that builds it is the planning's call, not this
  record's: the Sprint 17 plan schedules the build for Sprint 18 (its D-4). The deferred asks are filed as issues in the signing pass, so
  "closed" never silently means "the parts nobody re-read" (ADR-0043).
- **Two-way coverage.** The human view lands in the same batch as the API
  and MCP read (the board's pick). The close-out's surface check names the
  family of §6.
- **No existing figure moves.** The walk analytics keep their computation
  version (I9), and the category result is untouched (§9).
- Nothing here creates, stores or transmits an order, and nothing acquires
  data the instance does not already hold.

## Amendment (2026-10-03): what the building batch's review round found the record left open

**Why.** The money lens of PR β's closing act took I1 to I9 one at a time
on fixtures the batch's own tests did not build. Nothing broke the money
result: every position and line still summed to it. Three identities are
worded more strongly than the arithmetic can carry, and one booking had no
row in §5's table. This amendment states them; it changes no figure the
signed sections define.

**§5 gains a row: a trade with no rate.** A buy or a sell priced in a
currency with no rate path to the base on its booking day would bring its
units in at zero. The position would then be credited with its whole value
the day a rate arrives, and the currency effect on cash would book the
purchase as a loss. Such a trade's flow into the position is **its cash leg
in the base currency** instead: what it cost, or what it raised. No
settlement difference is left for it, and its fees and taxes, priced in the
same currency, ride inside that cash rather than as costs. The position
counts zero until a rate arrives and is named for it (§10), as before.

**I1 is exact while the conversion quotients terminate.** The walk divides
by stored rates. A rate whose reciprocal does not terminate (1.0856, 0.9413)
makes the walk's own sums round at `Decimal`'s 34 significant digits, and
the positions plus the lines then differ from the money result by about
`1E-30`. Nothing balances the difference. The payload's basis already says
so; I1 now reads: *exact in `Decimal` whenever every conversion quotient
terminates, and to `Decimal`'s precision otherwise.* The screen's sum row
prints the walk's own result, so the sum and the badge never differ by that
residue.

**I4 holds for the booking, not for what the balance does afterwards.** A
deposit or a removal is kept nowhere (§3), so the booking itself changes no
contribution and no line. A deposit into a foreign-currency account becomes
part of the balance §3's currency effect on cash revalues from the next day
on, and that line moves with the rate. I4 now reads: *a deposit or a
removal is kept in no contribution and no remainder line; a foreign-currency
balance it changes is revalued from the next day on, like any balance.*

**I5 inherits ADR-0028's quantity rounding.** A split whose ratio does not
divide the held quantity rounds the post-split quantity at the volume
scale (six places), ADR-0028's named exception: ten units split 1:3 become
3.333333, and the position's contribution then differs from its unsplit
twin by the rounded units' value. I5 now reads: *a split inside the window
changes no contribution, save for ADR-0028's quantity rounding.*

**Stated, not changed.**

- The currency effect on cash holds a trade's settlement difference in a
  single-currency portfolio too, when the booked cash differs from price ×
  quantity plus costs (a gross amount entered by hand, an import that keeps
  the broker's rounding). §3 and the screen's sub-line already name
  settlement differences; the line's name is about cash, not about a
  currency having moved.
- A foreign-currency cash balance held before its currency's first stored
  rate counts zero, as in the walk, and the first rate brings its whole
  value into the currency effect on cash. The payload's basis states it, but
  §10 names positions only, so no account is named. Naming such accounts on
  the performance and the contribution reads is filed as its own story.

**Note (2026-10-05): the accounts are now named.** The story the last item
above filed is built (#1055, Sprint 19 PR α M3; board
`mockups/ux-design-2026-10-04/02-money-notes`, pick J2 A). Nothing it states
about the figures changes: such a balance still counts zero, its deposit is
still a flow of zero, and the first rate still brings its whole value into
the currency effect on cash and into the money result.

- **Both reads name the account.** The performance read and the
  contribution read, each in its portfolio and its view form, carry
  `unvalued_cash_accounts` for their window, and so do the two benchmark
  reads, which summarise the same walk: every cash account of the scope
  that held a non-zero balance and counted zero for want of a rate path on
  a window day or on the day before the window, whose close is the start
  value, with its native balance, its days (the day before the window, the
  start value, included), the reason (`no_rate`), whether it still counted
  zero on the window's last day, and the date its currency's first rate
  arrived when that falls inside the window while the account held money at
  zero the day before. The reads of one scope and window list the same
  accounts, and each basis's `gaps` names the field where the
  contribution's said that no account is named.
- **The walk records the days, the reads count them.** A walk point carries
  the accounts it counted zero only on such a day, and a walk with any such
  day stores the accounts' names and their currencies' first rate dates
  beside its series, so `summarise/2` stays pure. The first rate's date
  comes from the stored rates, not from the series: a day that leaves the
  list cannot tell a rate that arrived from a balance that went to zero.
  The walk payloads move to computation version 4, the contribution's to 2
  and the benchmark's to 3; every existing figure is byte-identical (I9).
- **The screen** follows the board: the note under the contribution table
  names the account in the positions' shape, adds where the balance went
  when its first rate came inside the period, and the "Währungseffekt auf
  Bargeld" line carries the account's marker. §10's naming now covers the
  accounts as well as the positions.

**Note (2026-10-06): costs are read in the cash account's currency.** #1051
(Sprint 19 PR α M4) found the walk converting a trade's fees and taxes from
its price currency. A cross-currency trade
([ADR-0015](0015-cross-currency-settlement-fx-rate.html)) records them in its
cash account's currency, the cash leg they are part of
(`Ledger.SettlementGuard`), so §1's costs are now read in that currency.

- **The no-rate row's premise was false.** The amendment's §5 row let a
  no-rate trade's fees ride inside its cash because they were "priced in the
  same currency". For a cross-currency trade they are not: they are in the
  account's currency, which can have a rate when the price currency has none.
  Such a trade's flow into the position is now its cash leg less its fees and
  taxes, and those are its costs, as on any trade, so the position's costs
  equal the walk's trade costs (§1, #708's trade costs kept per security).
  Its contribution and its settlement difference (zero) are unchanged.
- **The money result does not move, and I1 holds as before.** On a
  cross-currency trade whose price currency has a rate, the correction moves
  between the position's costs and the settlement difference on the currency
  effect on cash, which together are what they were. The walk's and the
  contribution's computation versions ride the ones the 2026-10-05 note
  moved.

## Amendment (2026-10-09): a security-linked interest booking is its position's income

**Status.** Signed by the merge of the Sprint 21 planning PR, as the Sprint
20 plan's answer to #928 (its D-4) said it would be. **Risk tier**
([ADR-0036](0036-risk-tier-rides-the-batch.html)): money, because an amount
moves between a position and the remainder; and import idempotency, because
the #533 key reads the security.

**Why.** The importer resolves the security an `INTEREST` row names, and
creates it when the catalog lacks it (`Imports.Applier`'s
`resolve_security`). Then it drops it: `build_transaction_attrs` writes only
the cash account for an interest booking, as for a deposit or a removal. §3
put every interest booking in the remainder for that reason, so a bond's
coupons never reach its position, and its contribution reads as its price
move alone. The Income facet cannot place them either (#928, bond discovery
2026-09-25).

**What changes.**

1. **The import keeps the security.** An imported interest booking stores
   the security its row names, from a Portfolio Performance JSON or CSV
   file alike, as a dividend, fee or tax booking does. It stores no depot,
   as today: a CSV interest row books to its cash account and names none
   (`CsvParser.map_accounts`), a JSON row's `portfolio` stays unread so no
   depot is created for a coupon (ADR-0050 §4), and the walk reads no depot
   for income. A row that names no security stores none.
2. **What the stored booking names decides, not how it was written.** The
   API has accepted a security on an interest booking all along: the
   changeset casts it for every kind, and an interest booking requires only
   its cash account and amount. Such a booking, written over the API or
   `portfolixir.transactions.create` before this amendment or after it, is
   read like an imported one from the build on. That tool's description
   gains a sentence: an interest booking may name the security whose
   coupon it is.
3. **§1, §3 and §5.** The income term reads: dividends, and the interest
   bookings that name the position's security, each as credited. §5's
   table gains the row "interest naming a security: + the credited amount
   as income", and its remainder row holds the interest naming none. §3's
   interest line holds the interest bookings that name no security: account
   interest, and every coupon stored without its bond. Scoped to a view, a
   coupon credited to an in-view account is its security's income even when
   the position sits outside the view, as a dividend is (§6); a coupon
   credited to an account outside the view is kept nowhere, as a dividend
   is. In the walk this is the interest clause of
   `Performance.keep_internal`, which today adds every interest booking to
   the line.
4. **The hash and the key.** The content hash reads the file's security
   (its ISIN, else its name) before anything resolves, never the resolved
   id (`ImportHash`), so every stored hash stays byte-identical and a
   re-drop is all hash hits (ADR-0050 §2–§3, O1). The #533 key reads
   `security_id` (`DedupKey.of`), so a coupon stored without its security
   keys apart from the same coupon imported now. The applier's pre-import
   check (`booked_before?` and `old_reading`) therefore also asks for an
   interest row's key **with no security**, under each cash reading it
   already asks for (ADR-0053 §4 and A4): a coupon stored before this
   amendment, before or after ADR-0053 changed its cash, is recognised in a
   drifted re-export and not booked twice. It errs towards "already
   booked", as those readings do, and the result names the row under
   `economics`. The in-run key reads the security too, so two coupons of
   two bonds, equal in date, amount, account and time, no longer collapse
   into one booking in a fresh import (ADR-0050 §6); a file applied before
   that collapsed such a pair still books nothing when dropped again.
5. **The payload.** No field changes. The basis's `assumptions` name the
   new income term and the narrower interest line. `performance_contribution`
   and `performance_view_contribution` move from computation version 3 to 4
   (`Derived.Registry`), so no value computed by the old clause is served
   (ADR-0039 §5); the view-less read uses the second. The batch's contract
   entry names the three contribution routes and their two tools, the
   income read, and the create tool's description. The EN and DE
   integration docs (the remainder's `interest`) and product documentation
   (the income term, the Income facet) follow, and so does the screen's
   note under the interest line, which says an interest booking carries no
   security.
6. **The Income facet's per-position table.** `Income.positions` groups
   dividends and interest together by security and booking currency, so a
   coupon that names its bond leaves the row without a security, shown as
   "Interest", and joins the bond's row. "Top contributors", the first five
   of those rows, follows, and the year detail names the bond where it read
   "Interest". The year × month matrix, the bars and the totals split by
   kind, not by security, and do not change. The income read
   (`GET /api/v1/portfolios/:portfolio_id/income`,
   `portfolixir.portfolios.income`) carries the same rows. The security's
   own Transactions tab lists the coupon, and the transactions list's
   security filter finds it; no figure moves there.

**Stated, not changed.**

- Cash, balances, and the walk's TTWROR, IRR, series, money result and
  computation version stay as they are: an interest booking moves cash only,
  with or without a security (`Projection.effects`), and a security that
  appears only on a coupon is priced but never held, so it adds nothing to
  any day's value or basis step (I9). The benchmark comparison and the
  portfolio metrics keep their versions.
- I1 holds as it did, to the same precision: the amount moves between a
  position's income and the interest line, converted at the booking day's
  rate either way (§1, as amended 2026-10-03).
- Rows stored before stay as they are: no repair and no backfill. A re-drop
  cannot repair them, because a hash hit changes nothing (ADR-0050 §3), and
  ADR-0053 §6's correction writes cash, price and settlement legs, never a
  security. They stay in the interest line, as its basis says. An operator
  who wants one under its bond can name the security on the booking
  (`PATCH /api/v1/transactions/:id`, journaled); nothing does it for them.
- A security merge moves a coupon with its security, as it moves a dividend
  (ADR-0050 §9). The bond characterization test's figures (the valuation,
  the cash and the walk) stand; only its `security_id == nil` flips.

**The identities the building batch pins.**

- **I10.** A fresh import of an `INTEREST` row that names a security stores
  that security on the booking and no depot, from a JSON and a CSV file
  alike; a row that names none stores none. The bond characterization
  test's `security_id == nil` becomes the bond's id on purpose, and its
  other expectations pass unchanged.
- **I11.** Every content hash is byte-identical before and after the
  build. Before the first change, on unchanged code, the digest list of
  `csv_hash_pin_test.exs` gains the rows of `bond_invented.json`, whose
  `INTEREST` row names its bond, and of I12's file. A file applied before
  the build (in the test, its coupon's security cleared, as today's import
  leaves it) inserts nothing when dropped again (zero transactions,
  accounts, depots and securities). Neither does a re-export of it with the
  coupon's time of day moved, which misses the hash and is found by the
  key's no-security reading, named under `economics`.
- **I12.** One EUR portfolio, invented throughout and imported from one
  Portfolio Performance JSON file. A bond, *Larkspur Rail AG 4,00 % Anleihe
  2031*, ISIN `XSLARKSPUR33` (its check digit holds, and no real `XS`
  number has letters in its national part), face value 10,000.00 held as
  100 shares, the bond discovery's hundredth reading. Its cash account
  takes a deposit of 10,000.00 on 2025-03-02 and pays for the buy on
  2025-03-10: 100 shares, amount 9,955.00 with a fee of 5.00, so priced
  99.50, leaving 45.00.
  Quotes: 99.00 on 2025-12-31, 100.25 on 2026-06-30. Inside the window
  2026-01-01 to 2026-06-30 (`from=`/`to=`): account interest of 1.10 naming
  no security on 2026-03-31, and the coupon, 400.00 (4.00 % of 10,000.00)
  naming the bond, on 2026-04-15. The start value is 9,945.00 (bond
  9,900.00, cash 45.00), the end value 10,471.10 (bond 10,025.00, cash
  446.10), and no external flow is in the window, so `totals.result` is
  **526.10**, before the build and after it. After: the bond's row has
  start 9,900.00, end 10,025.00, net flows 0, income **400.00**, costs 0
  and contribution **525.00**; the interest line is **1.10** and the other
  two lines 0; 525.00 + 1.10 = 526.10, exact (I1). The same coupon stored
  without a security reads as before: the bond **125.00**, the interest
  line **401.10**. On the Income facet the bond's row reads 400.00, one
  payment, last on 2026-04-15, and the row without a security 1.10, one
  payment, last on 2026-03-31, where one row read 401.10 with two; 2026's
  interest total stays 401.10.
- **I13.** On I12's fixture, a view that holds the cash account but not the
  depot counts the coupon as the bond's income: its row has start and end
  0, held at neither end, income and contribution **400.00**; the interest
  line is 1.10; the view's result is **401.10** (cash 45.00 to 446.10),
  which the interest line alone held before. A view that holds the depot
  but not the account keeps no coupon, before and after: the bond 125.00,
  every line 0, the result 125.00. Both contribution analytics are
  registered at computation version 4, so no value stored under version 3
  is served.

**Order.** I11's digests are taken first, on unchanged code, with its
re-drop and re-export tests, which pass there. The red tests of I10, I12 and
I13 come next. Then three commits: the attrs (I10 turns green, and I11's
re-export turns red, because the stored coupon has no security and the new
key has one); the key's no-security reading (I11 green again); and the
walk's interest clause with the basis and the computation version (I12 and
I13 green). The docs, the screen's note and a dated note in ADR-0029
pointing here follow. The verification pass takes I11 first, then I12 and
I13 against I1 and I9, and the reviewer briefing names all four.
