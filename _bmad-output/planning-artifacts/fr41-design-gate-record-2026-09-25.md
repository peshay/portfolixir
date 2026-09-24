# The FR-41 design-gate record, for Sprint 17's planning PR

> **Where this record lives until it is signed.** This is the design-gate
> record Sprint 16's plan asks for in D-7
> (`implementation-artifacts/sprint-plan-2026-09-24-sprint16.md`), written in
> Sprint 16 together with its board. **It is not signed in this batch.** It
> moves into `docs/decisions/` as `0051-contribution-analysis.md` in the
> **opening commit of Sprint 17's planning PR**, and that PR's merge signs it
> (ADR-0026 step 1, as amended on PR #780: the merge is the signature).
> **0051** is the next free number, because `docs/decisions/` ends at
> ADR-0050 on 2026-09-25. If another record takes 0051 first, only the number
> changes.
>
> On the move, this preamble is dropped and front matter in ADR-0047's shape
> is added. The status line below stays as written. A planning PR is written
> as adopted, never as `Proposed`, and a decision the owner rejects is
> removed on the PR before the merge. Until the move, nothing here binds.
>
> **Board:** `design-language/mockups/fr41-2026-09-25/01-contribution-surface.html`
> and its PNG. It shows three placements, and **A** is recommended. It links
> the real `priv/static/app.css`, and all of its data is invented. Its labels
> and notes are in German, as on every board since the 2026-09-19 pass,
> because it pictures the German UI.
>
> **The two side findings D-7 names** were filed at Sprint 16's branch opening,
> and this record answers both:
>
> - **#900**: ADR-0041 §5's slice two (realized result and income per
>   category) has no issue. Answered by §9: slice two stays a separate story.
> - **#901**: the view scope ADR-0041 promised for the category result was
>   never built on the API and MCP side. Answered by §6: it lands next to
>   FR-41, in the same shape.

# ADR-0051: contribution analysis — which position made how much of a period's result

- **Status:** Accepted. Owner sign-off is the merge of the Sprint 17 planning
  PR (ADR-0026 step 1, as amended on PR #780: the merge is the signature).
- **Date:** 2026-09-25 (written in Sprint 16; signed at Sprint 17's
  planning).
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
  "net".
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
| Interest | Every `interest` booking: account interest, and bond coupons, which carry no security link today (bond discovery 2026-09-25) |
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

**Screen.** The board shows three options:

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
| I1 | The positions plus the remainder lines sum to `end − start − net external flows`, exact in `Decimal`, for every period and every scope. |
| I2 | With unchanging prices and exchange rates, and no bookings inside the window except deposits and removals, every position contributes exactly `0`, and so does every remainder line. |
| I3 | A position in the base currency, bought and sold entirely inside the window with no quote in between, contributes exactly `(sell price − buy price) × quantity − costs`. It appears in the table although it is held at neither end. |
| I4 | A deposit or a removal changes no contribution and no remainder line. |
| I5 | A split inside the window changes no contribution. |
| I6 | A transfer between two depots of one portfolio changes no contribution. In a view that sees only one of the two depots, the moved value is a boundary flow of that position. |
| I7 | A position that counted zero keeps its place in the sum and carries its `unvalued_days`, and the payload lists it. |
| I8 | The payload carries no signal, recommendation, rating, score or action key (the meta-test). |
| I9 | With the accumulators on, the walk's TTWROR, IRR, series and every existing output are byte-identical. The existing walk tests pass unchanged. |

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
  yet" to the issue numbers Sprint 17's batch files. The Tracker Index gains
  the line. The deferred asks are filed as issues in the signing pass, so
  "closed" never silently means "the parts nobody re-read" (ADR-0043).
- **Two-way coverage.** The human view lands in the same batch as the API
  and MCP read (the board's pick). The close-out's surface check names the
  family of §6.
- **No existing figure moves.** The walk analytics keep their computation
  version (I9), and the category result is untouched (§9).
- Nothing here creates, stores or transmits an order, and nothing acquires
  data the instance does not already hold.
