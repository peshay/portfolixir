---
layout: docs
title: "ADR-0047: derived metrics — a metric names the series it describes, and carries no verdict"
description: Design decision for FR-39 and FR-40 (scope-ladder level (a)), written for the Sprint 13 decision gate. Two input series that are never mixed — a security's split-adjusted close series in its own currency, and the portfolio's daily valuation walk in the base currency — with portfolio metrics reading the TTWROR chain's flow-adjusted factors so a deposit can never look like a return. A gap produces no observation rather than a zero return; below a stated minimum a metric refuses with a gap marker instead of a number. The float island widens by one named operation for the square root. No signal, no rule, no rating - level (a) reports, it does not evaluate.
---

# ADR-0047: derived metrics — a metric names the series it describes, and carries no verdict

- **Status:** Accepted — owner sign-off is the merge of the Sprint 13 planning
  PR ([ADR-0026](0026-epic-batch-workflow.html) step 1 as amended on PR #780:
  the merge is the signature).
- **Date:** 2026-09-19
- **Answers:** FR-39 (derived metrics per security) and FR-40 (derived metrics
  per portfolio or view), both released from the blanket advanced-reports rule
  on 2026-08-12 as **scope-ladder level (a)**.
- **Not a scope gate.** The ladder already released this level; nothing here
  opens anything that was closed. This is the *design* gate ADR-0026 step 1
  requires before a batch starts, and it is written as one because the
  arithmetic is the easy half. The asks it answers and defers are in §9, per
  [ADR-0043](0043-a-gate-closing-adr-names-its-asks.html).

## Context

The scope ladder released level (a) on 2026-08-12 and the FR Coverage Map has
said **"issue-ready now"** since the derived-value mechanism landed with #710
and #711 in Sprint 7. Four sprints later nothing is filed. That is not neglect:
what was missing was never a place to keep the values —
[ADR-0039](0039-durable-derived-values.html) supplies that — but a decision on
**what a metric is measured over**, and that decision cannot be taken inside a
story without the story taking it silently.

Two things already exist and constrain the answer.

- **`Portfolixir.Catalog.SecurityWithMetrics`** decorates the securities list
  with `latest_price`, the day change and `performance_1m` / `performance_1y`,
  computed from stored closes in one SQL round-trip and adjusted to the
  ADR-0028 §2 display basis before every ratio. It is the per-security metric
  surface that already works; FR-39 extends the idea to windows and
  distribution figures, it does not replace it.
- **`Portfolixir.Portfolios.Risk`** is a read-time concentration lens over the
  live valuation — Top-N single names, HHI with bands, asset-class cap
  violations — view-scopable through `ViewParam`, nothing stored. FR-40 says in
  as many words that it *extends the existing risk and concentration endpoint
  rather than replacing it*, and this record holds to that.

The metric-basis rule in `AGENTS.md` is review-blocking and already has a built
shape: `%{input_series, window: %{start_date, end_date}, reference, gaps}`,
serialized once by `JSON.computation_basis/1`, with
[ADR-0046](0046-benchmark-comparison.html) adding `assumptions` when a figure
rests on one. Nothing new is invented here for it.

What is left is the part that decides whether these numbers are **true**: which
series a metric reads, what a gap does to it, and whether a deposit can look
like a return. A volatility figure computed over the wrong series is not a
rough figure — it is a confident wrong one, and it is exactly the kind of
number an operator would act on.

## Decision

### 1. Two input series, named, never mixed

- **Per security (FR-39): the security's own split-adjusted close series, in
  the security's own currency.** `Catalog.Quotes.adjusted_range/3`, the
  ADR-0028 §2 display basis, so a window spanning a split carries no phantom
  move. Deliberately **not** converted to the base currency: a price metric is
  a statement about the instrument, and converting would fold the FX path into
  a figure that claims to be the instrument's own volatility.
- **Per portfolio or view (FR-40): the daily valuation walk of
  [ADR-0010](0010-ttwror-performance-series.html), in the base currency,**
  scoped by the active view ([ADR-0018](0018-buckets-tag-based-wealth-scoping.html))
  — the same walk the TTWROR and IRR of that scope read.

The two are **never averaged, summed, or combined into one figure.** A
portfolio's volatility is not the weighted mean of its positions' volatilities,
and this record does not offer a figure that pretends otherwise. The one place
the two series meet is §3's correlation matrix, which is explicit about
converting first and says so in its basis.

### 2. A deposit is not a return

This is the invariant the record exists for.

Portfolio-level metrics read the **flow-adjusted daily return factors of the
TTWROR chain**, never the day-over-day change of the portfolio's value. A
€10,000 deposit into a €50,000 portfolio moves the value by 20 % and the return
by nothing; a volatility computed over the value series would read that day as
a 20 % move and report a portfolio far more volatile than it is — and the error
grows with how actively the operator saves, which inverts the figure's meaning
for exactly the user it is for.

Pinned, exactly (§10, I1): a portfolio whose prices never move, with any number
of deposits and withdrawals, has volatility exactly `0` and maximum drawdown
exactly `0`.

### 3. The metrics, v1

**Per security**, over the windows `30d`, `90d`, `365d` unless the metric names
its own:

| Metric | What it is |
|---|---|
| `sma_50`, `sma_200` | simple moving averages over the stored closes, each with the latest close's distance to it in percent |
| `volatility` | annualized standard deviation of **simple** daily returns (§4) |
| `max_drawdown` | the largest peak-to-trough decline in the window, with `peak_date`, `trough_date` and `recovery_date` (null while unrecovered) |
| `momentum` | trailing return over `3m`, `6m`, `12m` |
| `distance_to_extremes` | the 52-week high and low with their dates, and the latest close's distance to each |

**Per portfolio or view**, on the existing risk read:

| Metric | What it is |
|---|---|
| `volatility` | annualized standard deviation of the chain's daily return factors (§2) |
| `max_drawdown` | over the chained return index, not the value series, with `peak_date`, `trough_date`, `recovery_date` |
| `risk_adjusted_return` | `(annualized chain return − risk_free) / volatility` |
| `correlations` | pairwise Pearson correlation of daily returns among the Top-N single names the lens already computes |

Two of those four need their input stated rather than assumed.

**`risk_adjusted_return` takes its risk-free rate as a request parameter**
(`risk_free_rate=`, a Decimal string), reusing ADR-0046's fixed-rate kind and
its daily-compounding convention, and **defaults to `0`**. At the default the
figure is return per unit of risk and the payload's `reference` says so in
those words. No rate is inferred, fetched or stored — inferring one would be a
data-acquisition decision (B3.3), and a Sharpe ratio whose risk-free rate the
reader cannot see is a number with a hidden argument in it.

**`correlations` converts first.** Each Top-N security's daily returns are
taken in the **base currency**, which is the deliberate opposite of §1's
per-security rule, because the question is "do the things I own move together
*in my money*", and two USD holdings held by a EUR operator share an FX leg
that is part of the answer. The payload states the conversion in its own basis
line; a pair is computed over the days on which **both** securities have a
stored close, and the overlap count travels with each pair.

### 4. Annualization, the float island, and the scale

- **Annualization is by `√(observations per year of the series being
  measured)`** — `√252` for the stored-close series, `√365` for the calendar
  walk. The two differ because the series differ, and each states its factor in
  its basis rather than leaving the reader to guess which convention was used.
- **Standard deviation and correlation need a square root, and `Decimal` has
  none.** The contained float island of AR-3 widens by **exactly one named
  operation, `:math.sqrt/1`**. AR-3's wording — the IRR solver as "the single
  named exception" — is already historical: ADR-0046's daily compounding factor
  was the second exception (`:math.pow/2`, `benchmark.ex:480`). **The same PR
  that adopts this record amends AR-3** so the architecture requirement stops
  disagreeing with the code it describes; silently widening it would be the
  "do not silently change architecture decisions" rule broken in the smallest
  possible way.
- **The boundary convention is the IRR solver's:** Decimals in, `:math.sqrt/1`
  on the float island, `Decimal.from_float/1` then `Decimal.round/2` at
  **scale 6** on the way out (`irr.ex:302`). Nothing float is persisted, so the
  no-float persistence gate (`decimal_persistence_test.exs`) is untouched — and
  a durable row, if one is ever activated, stores the rounded Decimal.

### 5. A gap produces no observation, never a zero

Carry-forward is the right gap treatment for a **valuation** and the wrong one
for a **return series**. Carrying a price forward and then differencing
manufactures a 0 % day: it does not leave the answer rough, it drags the
standard deviation toward zero and makes a thinly quoted security look calm.

So: **a day with no stored close produces no return observation.** The walk's
own carry-forward (ADR-0010) is unchanged and stays what the valuation reads;
the return series derived from it skips the day instead of scoring it.

Every metric carries its `observations` count, and below its minimum it is
`null` with `insufficient_data: true` — AR-4's gap-marker contract, HTTP 200,
never a guess and never a 500:

| Metric | Minimum |
|---|---|
| `volatility` | 20 return observations in the window |
| `correlations` (per pair) | 60 overlapping observations |
| `max_drawdown` | 2 points |
| `sma_n` | `n` points |
| `momentum`, `distance_to_extremes` | a close at each end of the window |

### 6. The payload says what it measured

- The three parts of the basis that are **shared** — `input_series`,
  `reference`, `gaps` — sit once on the payload, in the existing
  `computation_basis` shape. The one part that **varies** — `window` — sits on
  each metric, together with its `observations`.
- **Both halves are required.** A metric without its window is an incomplete
  basis, and the rule is review-blocking: a reviewer and an agent both read the
  payload, and neither reads a doc page.

### 7. No verdict, no signal — the level (a)/(d) boundary, mechanically

**No metric payload carries a signal, a recommendation, a rating, a score or an
action.** An SMA-50 above an SMA-200 is reported as two numbers and a distance;
the *rule* that reads a cross-over is FR-43 and is gated at B3.6, and scoring
whether such a rule works is level (c) or — if it needs a history in which the
rule was already there — level (d), which is out.

This is pinned by a **key-set meta-test** over the two payloads
(`test/invariants/`), so the boundary is mechanical rather than remembered
(NFR-9's own complaint is that only one of three named backstops exists; this
adds one where a new surface creates the need for it).

### 8. Registry, lifetime, and the seam that is missing

Two analytics register with [ADR-0039](0039-durable-derived-values.html) §2, at
computation version 1:

- **`portfolio_metrics` — default lifetime `:request`,** like its neighbours.
  It rides the walk's existing basis: `Invalidation.after_write/3` bumps the
  portfolios a write can affect, and this analytic keys under
  `DataVersion.portfolio_basis/1` exactly as `performance_analysis` does.
- **`security_metrics` — default lifetime `:none`, and the reason is the
  point.** Its invalidation seam **does not exist yet**.
  `Invalidation.after_quote_write/1` resolves through
  `BlastRadius.for_quote/1`, which answers *the portfolios that have ever
  transacted the security*. For a security **no portfolio has ever held** — a
  benchmark, a watch-only candidate, precisely the security whose research
  metrics are most wanted — that list is empty, so the write bumps **nothing**,
  and any memo of its metrics would be stale with no counter able to say so.
  Registering it at `:none` keeps ADR-0039's four properties true today;
  ADR-0035 already says a value merely computed more often than necessary gets
  computed once rather than cached.

  **The follow-up is named, not implied:** a per-security basis key
  (`DataVersion.security_basis/1`, bumped by `after_quote_write/1` alongside
  the portfolio bases) is the prerequisite for ever moving this analytic to
  `:request` or `:durable`. The batch files it as its own issue; the measurement
  that would justify the move (ADR-0039 C3) cannot be acted on before it lands.

### 9. Surfaces, agent first — and the whole family named

- `GET /api/v1/securities/:security_id/metrics` and
  `portfolixir.securities.metrics`.
- The portfolio and view figures **extend** `GET /api/v1/portfolios/:portfolio_id/risk`
  and `portfolixir.portfolios.risk`, additively.
- **The risk family has exactly one endpoint.** Unlike valuation, there is no
  `/views/:id/risk`; the view arrives as the `?view=` parameter the lens already
  honours. That sentence is written here so the close-out's surface check can
  state it rather than discover it — FR-37 shipped on the portfolio scope and
  skipped the view scope, which became #740, and the remedy the 2026-08-27
  round proposed was naming the family at the close-out.
- **The human views land in the same batch**, not deferred by default: the
  per-security figures on the securities detail's chart tab beside the price
  history it already renders, the portfolio figures on the Wealth risk surface.
  If the shrink order takes one, the close-out records the deadline the two-way
  coverage rule gives it.

### 10. What this record does not do

- **No backtest, no rule, no alert, no signal** (§7) — level (d) stays gated.
- **No new data acquisition.** Every series is already stored; B3.3 is
  untouched and no provider is added.
- **No exposure decomposition.** FR-42 (factor, sector, region) is level (b)
  and stays where the FR map has it, not least because the boundary against
  partial-weight advanced classifications needs its own argument.
- **No benchmark-relative metric.** That is FR-9 and ADR-0046; nothing here
  restates or extends it.
- **No per-position contribution.** That is FR-41, level (b), its own story.
- **No new persisted column.** Everything is derived on read.

### 11. The identities this batch pins

| | Identity |
|---|---|
| I1 | A portfolio with unchanging prices and any number of external flows has volatility exactly `0` and maximum drawdown exactly `0` (§2). |
| I2 | Maximum drawdown over a monotonically rising series is exactly `0`; over a series that halves and recovers it is exactly `-0.5` at scale 6. |
| I3 | A series correlated with itself is `1` at scale 6; with its own negation, `-1`. |
| I4 | The annualization factor of each series is the one §4 names, and the payload's basis says which. |
| I5 | A window below its §5 minimum answers `null` with `insufficient_data: true` and its `observations` count — HTTP 200, never a number and never a 500. |
| I6 | Neither metric payload carries a signal, recommendation, rating, score or action key (§7, meta-test). |
| I7 | A security's metrics are computed in the security's own currency; the correlation matrix in the base currency. Both stated in the basis, and a security whose currency has no stored rate path is absent from the matrix rather than silently unconverted. |

## The asks, answered and deferred (ADR-0043)

**Source of the asks:** the scope ladder's own wording for level (a) (identity
gate B3.1, 2026-08-12), FR-39 and FR-40 in the requirements inventory, and the
metric-basis rule added to `AGENTS.md` by the same gate.

| Ask | Source | Verdict |
|---|---|---|
| Moving averages, per security | ladder (a), FR-39 | **Answered** — §3, SMA-50 and SMA-200 with the distance to each |
| Realized volatility, per security | ladder (a), FR-39 | **Answered** — §3, §4 |
| Drawdown | ladder (a), FR-39, FR-40 | **Answered** — §3, both scopes, with peak/trough/recovery dates |
| Momentum | ladder (a), FR-39 | **Answered** — §3, trailing 3M/6M/12M |
| Distance to extremes | ladder (a), FR-39 | **Answered** — §3, the 52-week high and low |
| Volatility per portfolio or view | FR-40 | **Answered** — §3, over the chain, never the value series (§2) |
| Risk-adjusted return | FR-40 | **Answered** — §3, with the risk-free rate as an explicit parameter defaulting to 0 |
| Maximum drawdown **with its window** | FR-40 | **Answered** — §3, the window and all three dates |
| Correlation among the largest positions | FR-40 | **Answered** — §3, over the lens's existing Top-N, in the base currency |
| "Extends the existing risk endpoint" | FR-40 | **Answered** — §9, additively; no second endpoint |
| Computation basis in the payload | `AGENTS.md` metric rule | **Answered** — §6, reusing the built shape |
| Which observation counts and gap rule | this record | **Answered** — §5 |
| Durable activation of either analytic | ADR-0039 C3 | **Deferred, with a reason** — it is a measurement decision, and for `security_metrics` it is *blocked* until the per-security invalidation basis of §8 exists. Filed as its own issue by the batch. |
| Correlation over **all** holdings rather than Top-N | this record | **Deferred** — the Top-N is the set the lens already resolves and the pairs grow quadratically; widening it is a measurement question once the figure is in use. |
| Log returns instead of simple returns | this record | **Deferred, and narrowly** — simple returns keep the whole computation in `Decimal` but for the square root (§4). Log returns would put a second float operation on every observation for a difference that is immaterial at daily frequency. Revisit only if a consumer needs additivity across time. |
| Exposure decomposition, contribution, benchmark-relative risk | FR-41, FR-42, FR-9 | **Out of scope, not deferred** — §10; each has its own requirement and level. |

## Consequences

- **Risk-tier attention label** ([ADR-0036](0036-risk-tier-rides-the-batch.html)):
  this is money math on the analytics surface. It ships in its own commit
  group, TDD-first with exact-`Decimal` fixtures, with the dedicated
  verification pass in the agentic review taking I1–I7 one at a time, and an
  explicit callout in the reviewer briefing.
- **AR-3 is amended in the adopting PR** (§4). The float island is now three
  named operations in two modules plus this one; the requirement says so.
- The FR Coverage Map's **FR-39 and FR-40 rows** move from "no issue yet" to
  the issue numbers the batch files at branch opening, and the Tracker Index
  gains the epic row for them.
- **`SecurityWithMetrics` is not replaced.** The list's four figures stay the
  list's; the new read is the windowed one behind the detail surface, and the
  two agree on the display basis because both go through the ADR-0028 §2
  adjustment.
- Nothing here creates, stores or transmits an order, and nothing acquires data
  the instance does not already hold. Level (a) reports what was recorded; the
  operator still decides.
