---
layout: docs
title: "ADR-0033: per-position P&L decomposed — price return and currency return over a security-currency cost basis"
description: Proposed decision on how per-position P&L stops mixing price moves with purchase-date FX. Two candidates are worked through on the same synthetic fixture — (A) decompose each position's P&L into a price-return and a currency-return component that sum Decimal-exactly to the base-currency total, and (B) keep the cost basis in the security's own currency and convert both sides at the current rate — with the recommendation to adopt A, because it contains B as its price leg and is the only option whose per-position figures reconcile with the portfolio total without an extra aggregate line. Decision gate per ADR-0026; awaiting owner sign-off on issue #569.
---

# ADR-0033: per-position P&L decomposed — price return and currency return over a security-currency cost basis

- **Status:** Proposed (decision gate per
  [ADR-0026](0026-epic-batch-workflow.html); awaiting owner sign-off —
  [#569](https://github.com/peshay/portfolixir/issues/569))
- **Date:** 2026-07-31

## Context

### The problem

For a USD-quoted security bought through a EUR account, the per-position
"performance" figure currently mixes two different things: the price move of
the security and the FX effect between the purchase-date rate and today's
rate. Issue [#569](https://github.com/peshay/portfolixir/issues/569) names
the consequence: a phantom gain or loss that is an FX-spread artifact, not a
price move. Portfolio totals are internally consistent; the per-position P&L
is misleading — exactly the class of problem the owner's tracker
[#398](https://github.com/peshay/portfolixir/issues/398) (*surfaces that
agree and explain themselves*) and the owner priority in
[#321](https://github.com/peshay/portfolixir/issues/321) (correctness first)
exist for.

### Where the mixing happens in the code

The mechanism is concrete and sits on four surfaces, all fed by the same
blind comparison:

1. **The moving-average cost fold** (`cost_lots/1` in
   `lib/portfolixir/ledger.ex`) adds `quantity * price` for every buy and
   priced inbound delivery **without looking at the transaction's
   `currency_code`**. The docstring of `holdings_for_portfolio/2` states
   "every monetary figure is in the security's own currency" — but that is
   an assumption, not an invariant anything enforces.
2. **Per-position P&L** (`put_holding_valuation/2`, `decorate_holding/2` in
   the same file) computes `market_value - cost_basis`, where the market
   value comes from the latest quote close in the **security's** currency and
   the cost basis from the fold above in the **transaction's** currency.
3. **FIFO open lots** (`decorate_open_lot/2`) compare `lot.buy_price`
   (transaction currency) against the quote close the same way — the surface
   [#620](https://github.com/peshay/portfolixir/issues/620) is about to
   extend.
4. **The security-detail cost-basis chart overlay**
   (`cost_basis_series/3` in `lib/portfolixir_web/live/securities_live.ex`)
   folds `tx.price` blind to its currency onto a chart whose quote series is
   in the security currency.

The JSON API even asserts the broken assumption to consumers:
`lib/portfolixir_web/controllers/api/v1/json.ex` labels the holdings payload
`currency_basis: "security_currency"`.

### How the mismatch gets into the data

[ADR-0015](0015-cross-currency-settlement-fx-rate.html) already decided, for
**manual** bookings, that a cross-currency trade is booked in the security's
own currency (`currency_code` = security currency, `price` in security
currency) with the cash leg carried by `settlement_amount` /
`settlement_fx_rate`. Positions built that way have a security-currency cost
basis and honest native P&L — ADR-0015's own "phantom P&L" case (a live
foreign position showing a double-digit gain on day one with zero real
movement) is what that decision fixed.

The **import path never got the same treatment**. A Portfolio Performance
export books a trade in the *account* currency: the PP JSON/CSV parsers
(`lib/portfolixir/imports/portfolio_performance/`) set `entry.currency_code`
to the transaction currency and derive `price` as `amount / shares` in that
currency, and the applier (`lib/portfolixir/imports/applier.ex`) writes the
buy exactly so — `currency_code` EUR, price in EUR, no settlement fields.
Because the linked cash account is also EUR, the changeset validation of
ADR-0015 sees no mismatch and requires nothing. The result is a EUR-priced
buy of a USD-quoted security, whose EUR figure the cost fold then compares
against USD market values.

A second latent defect follows from the same blind fold: two buys of one
security in **different** transaction currencies are summed into a single
cost figure that is denominated in no currency at all. Any option chosen
here must make that impossible, not just unlikely.

### Constraints

- [ADR-0003](0003-decimal-for-money.html) / AGENTS.md — `Decimal`
  everywhere, no floats for financial values.
- [ADR-0007](0007-currency-conversion-with-exchange-rates.html) — FX
  triangulates through the EUR hub; `Portfolixir.Fx.convert/4` accepts a
  date and resolves the most recent stored rate at or before it.
- [ADR-0015](0015-cross-currency-settlement-fx-rate.html) — native cost
  basis for manual cross-currency bookings; rates are transaction data,
  "never looked up inside the pure reducer".
- [ADR-0016](0016-rounding-policy.html) — full precision in compute, round
  only at the human display.
- [ADR-0026](0026-epic-batch-workflow.html) — this is ledger/money-domain
  math and therefore **risk-tier**: it ships as a dedicated small PR with
  real human review, never inside an epic batch, and this decision gate
  precedes any implementation.
- [ADR-0010](0010-ttwror-performance-series.html) is untouched: TTWROR is a
  different measure with its own definition; this decision is about the
  per-position unrealised P&L only.

## Hard requirements — any option must meet all of these

1. **Reconciliation.** The per-position figures must sum, `Decimal`-exactly
   at full precision, to the portfolio's base-currency P&L over the same
   positions. No option may leave a gap between "what the rows say" and
   "what the total says" — that gap is precisely the #398 disease.
2. **Explainable on the surface.** Whatever number is shown must carry UI
   copy (tooltip/legend) and API field names that state what it is and what
   it is not. The `currency_basis` label in the API must become true.
3. **Decimal only.** All new figures are `Decimal`; API and MCP serialize
   them as strings; rounding happens at display only (ADR-0016).
4. **Honesty over availability.** A position whose decomposition cannot be
   computed (no stored rate for the purchase date, no security-currency
   leg derivable) is marked so via the existing `valued` / `price_source`
   idiom — never shown with a silently wrong number (the ADR-0015 rule).
5. **No mixed-currency cost figure can exist.** The cost fold must be
   well-defined in a named currency by construction.
6. **Risk-tier delivery.** Dedicated small PR, real human review, and a
   deterministic multi-currency test fixture (synthetic, as always) pinning
   the chosen behaviour — issue #569's own acceptance criterion.

## The shared synthetic fixture

All figures below are **synthetic**, chosen for exact decimal arithmetic.
EUR is the base and hub currency; rates are written as EUR per 1 USD.

- 2026-01-15 — buy 10 shares of a synthetic USD-quoted security at
  USD 100.00; rate 0.80 → cash leg EUR 800.00.
- 2026-07-31 (today) — quote USD 110.00; rate 0.90.

Derived, in full precision:

| Figure | Native (USD) | Base (EUR) |
| --- | --- | --- |
| Cost basis | 1,000.00 | 800.00 |
| Market value today | 1,100.00 | 990.00 |
| True price move | +100.00 (+10.00 %) | — |
| True total P&L in EUR | — | +190.00 (+23.75 %) |

**What the current code shows** for this position when the buy was imported
from a PP export (EUR-booked): `cost_basis` 800.00 (a EUR figure),
`market_value` 1,100.00 (a USD figure), `unrealized_pnl_abs` "+300.00" and
"+37.50 %" — a number denominated in no currency. In the day-one variant
(quote still USD 100.00) it shows "+25.00 %" on zero real movement: the
phantom P&L of ADR-0015, resurrected through the import path.

## Option A — decompose the FX contribution: price return and currency return per position

Keep the base-currency total P&L as the position's headline truth — it is
what actually happened to the owner's money — and split it into two named
components that sum exactly:

```text
total  = MV_native × r1 − base_cost                    (EUR P&L, what the owner experienced)
price  = (MV_native − native_cost) × r1                (the security's move, at today's rate)
currency = native_cost × r1 − base_cost                (the FX effect on the amount invested)

total = price + currency                               (identity, exact in Decimal)
```

where `MV_native` is quantity × latest close, `native_cost` is the
security-currency cost basis, `base_cost` is the base-currency amount
actually paid (settlement leg), and `r1` is today's hub rate. For a single
lot this is the algebraic identity
`p1·r1 − p0·r0 = (p1 − p0)·r1 + p0·(r1 − r0)` — **residual-free by
construction**, no cross-term to hide. The convention (price leg at the
current rate, currency leg on the invested native cost) must be fixed and
documented; the mirrored convention is equally exact but must not be mixed
with this one.

On the fixture:

| Component | Value | On EUR cost of 800.00 |
| --- | --- | --- |
| Price return | (1,100.00 − 1,000.00) × 0.90 = **EUR 90.00** | +11.25 % |
| Currency return | 1,000.00 × 0.90 − 800.00 = **EUR 100.00** | +12.50 % |
| Total | **EUR 190.00** | +23.75 % |

The component percentages share the EUR-cost denominator, so they add
exactly. The decomposition also tells the truth when FX hurts: at a rate of
0.70 the same +10 % price move reads price +EUR 70.00, currency
−EUR 100.00, total −EUR 30.00 — a position that is *up* in USD and *down*
in EUR, with the surface saying why.

Under the running-average cost model this needs the fold to carry a **cost
pair** — `native_cost` and `base_cost` — per lot, with removals taking
proportional slices of both. No purchase-date rate lookup is needed at read
time: the pair is folded from transaction data, and `r1` is the same
current rate the valuation already uses.

**Data demands.** Manual ADR-0015 bookings carry both legs already
(`price` native, `settlement_amount` base). Same-currency bookings are the
degenerate pair (both legs equal). Imported EUR-booked trades of a foreign
security carry only the base leg; the native leg must be derived from the
stored hub rate at the booking date — at **write/import time**, keeping the
reducer pure per ADR-0015 (rates are transaction data, not reducer
lookups). Where no rate exists for that date, requirement 4 applies: the
position's decomposition is reported unavailable, never invented.

**Pros.**

- The headline per-position figure equals the owner's real base-currency
  outcome, and the rows sum to the portfolio total with no adjustment line
  (requirement 1 holds natively).
- Both effects are visible and named — the strongest possible form of
  "surfaces that explain themselves".
- Contains Option B: the price leg *is* B's native P&L converted at today's
  rate, so a native-currency view on the security detail stays consistent
  for free.
- Fixes the mixed-currency fold defect: both legs of the cost pair are
  well-defined currencies.

**Cons.**

- More machinery: a cost pair in the fold, two new component fields on four
  surfaces, API/MCP additions.
- Needs the native leg backfilled or derived for existing imported
  cross-currency rows — a data-dependency the implementation PR must solve
  (persist the ADR-0015 settlement fields on import, plus a backfill for
  existing rows, is the ADR-0015-consistent route).
- Two numbers per position where there was one; the UI must present them
  without clutter.

## Option B — cost basis in the quote currency, both sides converted consistently

Compute the cost basis in the security's own currency (deriving the native
leg for imported account-currency bookings exactly as Option A must), and
make the per-position P&L purely native:

```text
native P&L = MV_native − native_cost        shown as-is, or × r1 as one consistent conversion
```

On the fixture: **USD 100.00, +10.00 %** (converted at today's rate:
EUR 90.00). The day-one phantom reads 0.00 % — correct.

**Pros.**

- The simplest mental model: per-position performance is the security's
  price performance, full stop. This is ADR-0015's already-accepted
  principle, extended to the import path.
- One number per position; smallest UI change.
- Same fold fix as A (the native leg), so the mixed-currency defect dies
  here too.

**Cons.**

- **Reconciliation fails without an extra line.** Summing the per-position
  P&L converted at today's rate gives EUR 90.00 where the portfolio's EUR
  position actually moved by 190.00; the EUR 100.00 currency effect
  vanishes from every row yet remains in the totals. Requirement 1 then
  forces an aggregate "currency effect" line at the portfolio level — at
  which point the FX contribution is being computed anyway, just shown less
  honestly (as one pooled figure instead of per position, where the
  decision to hold a foreign position is actually made).
- A position can be shown green while it lost the owner money in EUR (the
  0.70-rate case above), with the explanation living in a different row of
  a different table.
- The percentage figure changes meaning relative to today's display without
  gaining a second component that explains the difference.

## Decision

**Proposed, not decided — the owner signs this off (or overrules it), as
with the ADR-0031 and ADR-0032 gates.**

The recommendation is **Option A**: per-position P&L is decomposed into a
price-return and a currency-return component over a security-currency cost
basis, with the residual-free convention fixed above (price leg at the
current rate, currency leg on the invested native cost), the base-currency
total remaining the headline figure, and the native leg persisted at
write/import time via the ADR-0015 settlement fields.

The deciding argument is requirement 1: A is the only option whose
per-position rows reconcile with the portfolio total by construction.
B must grow an aggregate FX line to reconcile — computing the same quantity
A computes, while refusing to attribute it to the positions that caused it.
And since A's price leg is exactly B's figure, choosing A does not lose the
native view; the security detail can state "price return +10.00 % (USD)"
verbatim.

Surface copy (requirement 2), to be refined in the implementation PR but
committed to in substance:

> **Price return** — the change of the security's own price, converted at
> today's rate. **Currency return** — the effect of the exchange rate on
> the amount originally invested. Together they equal the position's total
> gain or loss in EUR.

## Consequences

If accepted as recommended:

- The cost fold in `lib/portfolixir/ledger.ex` carries a
  `{native_cost, base_cost}` pair per lot; sells, outbound deliveries and
  security transfers slice both proportionally; splits scale quantity and
  leave both costs invariant. The fold stays pure — rates enter as
  transaction data (ADR-0015), never as reducer lookups.
- The import applier populates the ADR-0015 settlement fields for
  cross-currency PP entries (security-currency leg derived via the stored
  hub rate at the booking date), and existing imported rows get a one-time
  auditable backfill. A row with no derivable native leg yields an
  honestly-unavailable decomposition, not a guess.
- All four surfaces in the Context section change together: holdings tables
  (portfolio and security detail), FIFO open lots, the chart cost-basis
  overlay, and the API/MCP payloads (new component fields as strings; the
  `currency_basis` label made truthful). Per AGENTS.md, API and MCP
  coverage move with the UI.
- A deterministic multi-currency fixture (this ADR's synthetic fixture is
  the candidate) pins: the decomposition identity, the day-one zero-phantom
  case, the FX-loss case (price up, total down), the same-currency
  degenerate case (currency component exactly zero), and reconciliation of
  row sums against the base-currency total.
- Delivery is risk-tier (ADR-0026): its own small PR, real human review,
  no epic batch.
- **Off-limits, reaffirmed:** persisting an FX-distorted cost basis;
  reintroducing any blind cross-currency comparison; direct cross rates
  (EUR-hub triangulation stays authoritative, ADR-0007); touching the
  TTWROR definition (ADR-0010).

### Interaction with #620 (FIFO lot consumption display)

[#620](https://github.com/peshay/portfolixir/issues/620) wants the FIFO
lots a sale consumes, and their gross gain, shown where the sale is
decided. That gross gain is per-lot P&L on exactly the surface this ADR
redefines — an open lot's `buy_price` has the same currency ambiguity as
the average cost basis. #620 is therefore **sequenced after this decision**
(as the sprint plan already does): its lot figures must adopt the same
currency basis and, for cross-currency lots, the same price/currency
decomposition, so the two surfaces cannot disagree from birth. Nothing in
this ADR changes #620's scope (gross gain, never a tax figure — ADR-0031).

## References

- Issue [#569](https://github.com/peshay/portfolixir/issues/569) — the
  problem statement and acceptance sketch; parent tracker
  [#398](https://github.com/peshay/portfolixir/issues/398); sibling
  [#406](https://github.com/peshay/portfolixir/issues/406) (valuation
  surfaces reconcile — same family, separate decision);
  [#620](https://github.com/peshay/portfolixir/issues/620) (sequenced
  after this gate)
- [ADR-0015](0015-cross-currency-settlement-fx-rate.html) — native cost
  basis and settlement FX for manual bookings; this decision extends its
  principle to the import path
- [ADR-0007](0007-currency-conversion-with-exchange-rates.html) — EUR-hub
  conversion; [ADR-0016](0016-rounding-policy.html) — rounding at display
  only; [ADR-0003](0003-decimal-for-money.html) — Decimal everywhere
- [ADR-0010](0010-ttwror-performance-series.html) — the performance series
  this decision deliberately does not touch
- [ADR-0026](0026-epic-batch-workflow.html) — decision gate and risk-tier
  delivery rules
