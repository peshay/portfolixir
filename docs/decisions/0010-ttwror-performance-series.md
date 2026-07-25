---
layout: docs
title: "ADR-0010: Daily valuation series and TTWROR"
description: Decision to derive a daily portfolio valuation series on read and compute the true time-weighted rate of return the Portfolio Performance way.
---

# ADR-0010: Daily valuation series and TTWROR

- **Status:** Accepted
- **Date:** 2026-06-09

## Context

Portfolixir values the portfolio **now** ([valuation](0007-currency-conversion-with-exchange-rates.html))
but says nothing about how it performed. The figure operators actually use for
that — and the one Portfolio Performance leads with — is the **true
time-weighted rate of return (TTWROR)**: the return of the investments
themselves, with deposits and withdrawals neutralised, so it does not reward or
punish the timing of putting money in. Without it, judging performance still
requires opening Portfolio Performance.

Constraints that apply:

- Derived figures stay reproducible from stored data on read, never persisted
  as running totals ([ADR-0004](0004-holdings-derived-from-transactions.html)).
- Money, rates and returns are `Decimal` ([ADR-0003](0003-decimal-for-money.html));
  rounding is a display concern.
- Multi-currency values convert through the EUR-hub rates
  ([ADR-0007](0007-currency-conversion-with-exchange-rates.html)).
- The MCP companion stays a thin wrapper over `/api/v1`
  ([ADR-0002](0002-thin-mcp-over-json-api.html)).

## Decision

Derive a **daily valuation series** on read and chain **daily returns**
geometrically, the way Portfolio Performance computes TTWROR.

- From the first transaction to the end date, each day's portfolio value is
  positions (quote close on or before the day, converted at that day's rates)
  plus cash, in the base currency.
- Each day's **external flow** is neutralised: deposits and removals, security
  deliveries in and out (valued at that day's quote), and the residual jump of
  a cash **balance snapshot** ([ADR-0009](0009-cash-as-balance-snapshots.html))
  — stating a balance is money appearing or leaving outside the recorded
  bookings. Dividends, interest, fees and taxes are **internal** (they are
  return); buys, sells, cash transfers and security transfers only move money
  inside the portfolio.
- Daily return and chaining, with flows at the start of the day:

      r_d = V_d / (V_{d−1} + F_d) − 1        TTWROR = ∏(1 + r_d) − 1

  A day with nothing invested contributes no return.
- **Periods**: `ytd`, `1y`, `3y`, `5y`, `max`. A period chains only its own
  days, starting from the value just before the period.
- Surfaces: `GET /api/v1/portfolios/:id/performance` (period and optional
  daily series) and the MCP tool `portfolixir.portfolios.performance`.

## Consequences

- Performance is finally readable from Portfolixir itself, period by period,
  consistent with the Portfolio Performance figure operators already know.
- The series is recomputed on read — auditable and always in sync with the
  ledger, at the cost of walking every day since the first transaction. For a
  personal portfolio this is cheap; a cache can come later without changing
  the contract.
- Accepted trade-offs: a security with no usable quote or rate path
  contributes zero value until one exists, and the later jump counts as
  return; deliveries without a quote enter as zero-valued flows. Both mirror
  how the live valuation treats unpriceable positions.
- The money-weighted return (IRR), which PP shows next to TTWROR, is a natural
  follow-up on the same series and stays out of scope here.

## Amendment (2026-06-10): real-world import hardening

Validating the page against a real Portfolio Performance export (2,755
bookings over nine years) surfaced three failure modes; the engine now guards
against all three without changing the method:

- **Trade-price fallback.** A security with no quote was valued at zero, so
  every buy looked like instant value destruction and the chained TTWROR
  exploded to absurd values. A buy or sell *is* a price observation — exactly
  how Portfolio Performance seeds prices from bookings — so the engine (and
  the live valuation) now price quoteless securities at the latest own trade
  price. A quote wins over a trade on the same day; positions valued this way
  are flagged (`price_source: :trade`) and counted, never silent.
- **Implausible dates.** One booking dated `0217-12-05` (a typo for 2017)
  made the daily walk span ~660,000 days. Bookings dated before 1970 are now
  applied on the first plausible day and reported as `suspect_dates`; the
  importers additionally reject such rows per-row with a clear message, so
  the fix happens in the source and re-import stays idempotent.
- **Zero-or-negative return base.** `r_d` is only chained when
  `V_{d−1} + F_d > 0`; otherwise the day contributes no return instead of
  dividing by a meaningless base.

Performance work in the same change, contract untouched: the expensive daily
walk (`analysis/2`) is computed once and every period is a pure `summarise/2`
over it; quotes, own trade prices and FX-rate series are preloaded so the walk
issues no per-day queries.

## Amendment (2026-06-13): money-weighted return (IRR)

The IRR follow-up noted above is now implemented on the same series, additive
to the contract. `summarise/2` carries an `irr` field next to `ttwror`: the
single annualised rate solving `NPV(r) = Σ cf/(1+r)^(days/365) = 0` over the
period's dated external flows plus the terminal value, with the initial value
as the first outflow (the cashflow signs follow the series `flow` convention,
where a positive `flow` is money entering the portfolio, i.e. an investor
contribution / negative cashflow). It is surfaced on the performance endpoint,
the MCP tool and the Portfolio page next to TTWROR.

The root-find uses **bisection** on a bracket that must show a sign change of
`NPV`; it is derivative-free and deterministic. Fractional exponentiation is
impractical in pure `Decimal`, so the solver converts the cashflow amounts to
floats **only at its numeric boundary** and returns the rate as a `Decimal`
rounded to six places. This does not violate the Decimal rule (ADR-0003): the
IRR is a derived, displayed ratio, not a persisted financial value, and the
cashflows themselves stay `Decimal`. Degenerate inputs — fewer than two flows,
all flows the same sign, no sign change across the bracket, or non-convergence
within the iteration budget — return `nil` (`null` over the API), never an
error.

## Amendment (2026-07-24): trade-price basis steps are not return

Issue #545. Portfolios holding securities **without quote history** produced an
absurd `max` TTWROR — thousands of percent with no real market move.

A position with no quotes is valued at its own **last trade price**
(`Ledger.latest_trade_prices`). It then sits flat between trades, and on the day
a new trade sets a different price the **entire previously-held quantity
re-prices at once**. Because a buy or a sell is an internal cash↔security move,
that day's external flow is zero, so the formula above scored the whole
re-pricing as a one-day market return — and over a long history those steps
compound geometrically. A synthetic four-year fixture (buys at 100 → 1,000 →
8,000) chained to **+2,567.5 %**.

The re-pricing of an already-held position is a change of valuation **basis**,
not a market move: nothing was observed except the price of the portfolio's own
trade. It is therefore neutralised the way an external flow already is, as a
third component `B_d` of the return base:

    r_d = V_d / (V_{d−1} + F_d + B_d) − 1

`B_d` is decided by **one gate** and then measured by **replaying the day**.
Both work off explicitly threaded price provenance
(`price_source: :trade | :quote`) and the day's actual bookings, never a
re-derived heuristic.

**The gate — is the security measured?** A basis step is emitted only for a
security that carries **no quote from any earlier day**. Such a position is
priced by the portfolio's own bookings alone: every re-pricing of it restates a
fabricated basis, including the arrival of its **first quote ever**. Once a
quote has landed the security is *measured*; from then on gaps in the feed are
just gaps, and the trade prices filling them stay return. That asymmetry is
deliberate: it is what keeps a quoted portfolio's TTWROR byte-identical, and it
stops the documented remedy ("load quote history") from re-creating the very
explosion this amendment removes — a forward-only quote load, the normal shape
when a feed only covers recent dates, would otherwise discharge years of
accumulated drift as a single day of four-digit return.

**The measurement — a lot queue per day.** For each stepping security the day is
replayed as a queue of lots: the sleeve carried in from yesterday at the old
price `from`, plus whatever the day's quantity legs added at their own price (a
buy or sell at its booked price; a delivery or depot transfer at the day's
price, which is what values it in `F_d` or in the counter depot). A disposal
consumes the **most recently acquired** lot first, so what a day buys nets
against what the same day sells and only the residual reaches yesterday's
sleeve. Then

    B_d = Σ  quantity × (to − lot basis)

over every unit that ends the day marked at the day's price **without having
become cash**: the retained sleeve, the quantity acquired today, and the
quantity delivered out. A **sale** contributes nothing — it turned its slice
into real cash, and its gain against the basis it consumed is genuine return
that must not be swallowed. With exactly one trade point on the day this reduces
to `retained × (to − from)`.

Replacing the earlier "net the day's quantity" shortcut fixed four defects found
in review, each reproduced numerically: several trade points on one day (a
same-day sell-and-rebuy read −66.7 % where nothing happened), sign-blind
netting (an oversell into a short read +300 % instead of +100 %, and buying that
short back at a loss reported no loss at all), an outbound delivery being
treated as a realisation (+66.7 % for a removal that produced no cash), and the
first-quote transition above (+4,900 %).

**Currency.** `B_d` restates *yesterday's* closing value into the new price
basis, so it is converted at **yesterday's** rates. Converting it at the day's
rate would cancel the retained sleeve's own exchange-rate move out of the
return: a position whose currency halved on the same day a buy re-priced it read
−47.6 % instead of the correct −50 %. A currency whose rate series starts today
has no carried rate and falls back to today's, so the step is still converted
rather than collapsing to zero on the walk's first day.

`B_d` enters the return chain only. `value`, `start_value`, `end_value` and
`net_external_flows` are untouched, so the money facts and the €-gain derived
from them stay exactly as booked.

**Composition with splits** ([ADR-0028](0028-corporate-actions-as-ledger-events.html) §2):
the carried opening price is captured *after* the day's rank −1 rescale points,
so the opening price and the price replacing it are already in the same
post-split as-traded basis, and a rescaled trade price stays a trade price. A
split replays first within the day (`intra_day_order`), so its scale leg meets a
queue holding only the opening sleeve, already at the rescaled price — the leg
scales lot quantities and leaves lot prices alone. A pure split day emits no
basis step: no price point is consumed, and the rescale and the quantity scale
cancel by construction.

`day_factor/2` is now public and shared: the ADR-0027 snapshot comparison
previously carried a duplicate of the old formula and would otherwise have kept
reporting the uncorrected figure.

**Accepted consequence.** For a purely trade-priced portfolio the TTWROR now
reads near 0 % next to a large positive €-gain and a large IRR. That divergence
is truthful — an unquoted holding has no observed market return, while the cash
from a sale is genuinely there — and it is documented in the user
documentation. Subtracting `B_d` from the €-gain to force reconciliation was
considered and **rejected**: after a real sale it would understate an actual
realised gain. The operational remedy remains loading quote history (goals
#6/#7); this amendment makes the figure degrade gracefully when quotes are
missing instead of exploding.

**Known residuals.** Each is the conservative direction and is tracked as a
follow-up rather than special-cased:

- A security that *was* quoted and later loses its feed keeps booking its
  trade-price steps as return. Forced by the byte-identical guarantee for
  quoted portfolios.
- On the day a security's first quote ever lands, quantity bought that same day
  is marked to the quote and that difference is neutralised with the rest. The
  whole day is the transition from unmeasured to measured, and the day's own
  move cannot be separated from the drift it discharges.
- A partial write-off and a full one do not report the same percentage: selling
  4 of 10 at price 0 reads −28.6 %, selling all 10 reads −50 %. Only the sold
  slice is realised; the retained slice's mark-down restates the base instead of
  counting as loss. This follows directly from treating trade-price marks as
  basis and sales as realisation, so no zero-price special case was added.
- Same-day netting follows the ledger's replay order (`{date, kind, id}`), so a
  day that both buys and sells the same unmeasured security splits its change
  between return and basis according to the order the bookings were recorded in.
  The order is stable and re-import-idempotent, but it is an ordering
  convention, not a law.
