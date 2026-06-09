---
layout: docs
title: "ADR-0007: Currency conversion with exchange rates"
description: Decision to add a dated exchange-rate store, an ECB sync provider, and hub-based triangulation so multi-currency portfolios are valued precisely.
---

# ADR-0007: Currency conversion with exchange rates

- **Status:** Accepted
- **Date:** 2026-06-05

## Context

Portfolixir stores a `currency_code` on every security, cash account and
transaction, and a `base_currency_code` on every portfolio, but it has no
exchange rates and no conversion. The read-time valuation therefore sums raw
quote closes as if every holding shared one currency: 100 USD of one position
plus 100 EUR of another is reported as `200` with 50/50 weights. For a tool
whose whole point is precise, auditable numbers (Decimal everywhere,
[ADR-0003](0003-decimal-for-money.html)), that is wrong, not merely imprecise.

Constraints that apply:

- Money and rates are `Decimal`, never floats ([ADR-0003](0003-decimal-for-money.html)).
- Derived figures stay reproducible from stored data, not mutable running totals
  ([ADR-0004](0004-holdings-derived-from-transactions.html)).
- Price feeds are pluggable adapters behind a behaviour, and **no real HTTP runs
  in tests** ([ADR-0005](0005-quote-provider-split.html)).
- The supported currency set is a curated code list, not user free-text
  (`Portfolixir.Catalog.Currencies`), and includes the `GBX` (pence)
  pseudo-currency that Portfolio Performance uses.

## Decision

Introduce a dedicated bounded context `Portfolixir.Fx` that owns exchange rates
and conversion, kept separate from `Catalog` (securities/quotes) so FX is an
explicit, testable layer rather than overloaded onto the securities table.

**Stored rates — a dated upsert log, mirroring quotes:**

- New table `exchange_rates` keyed by `(base_currency, quote_currency, date)`
  with a `Decimal` `rate` and a `source`. Lookups use `at_or_before/3` so a
  valuation on any date uses the most recent published rate, exactly like
  `Catalog.Quotes.at_or_before/2`.
- Rates are stored against a single **hub currency, EUR**, matching the European
  Central Bank reference rates (`1 EUR = rate <quote>`). Any other pair is
  derived, so the store stays small and internally consistent (no conflicting
  cross-rates).

**Conversion — hub + triangulation, full precision:**

- `Fx.convert(amount, from, to, date)` returns `{:ok, Decimal}` or
  `{:error, :no_rate}`. Same-currency conversion is the identity (no division,
  so no rounding). Otherwise it triangulates through EUR:
  `amount / eur_rate(from) * eur_rate(to)`.
- `eur_rate(ccy)` resolves `EUR → 1`, looks up the stored EUR-based rate
  otherwise, and treats **`GBX` as `GBP × 100`** so pence fall out of the same
  arithmetic with no special case in the conversion path.
- All intermediate arithmetic stays at full `Decimal` precision; **rounding is a
  display concern only**, consistent with the valuation weights decision.

**Rates feed — ECB adapter behind a behaviour:**

- `Portfolixir.Fx.RateSync.Provider` behaviour, with
  `Portfolixir.Fx.RateSync.Ecb` fetching the ECB daily reference rates and a
  `Fake` registered in tests. A small opt-in scheduler
  (`Portfolixir.Fx.RateSync`) refreshes rates in prod, and `sync_now/0` plus an
  API endpoint trigger an immediate refresh — the same shape as
  `Catalog.QuoteSync`.

**Valuation integration:**

- The portfolio valuation converts each position's market value into the
  portfolio `base_currency_code` before summing. A position is `unvalued` when it
  has no quote **or** no rate path to the base currency, so a missing rate never
  silently distorts the total or the weights.

## Consequences

- Multi-currency portfolios are valued correctly: the total and weights are in
  the portfolio base currency, and a missing rate degrades one position to
  `unvalued` rather than corrupting the whole total.
- A new `exchange_rates` table, the `Portfolixir.Fx` context, an ECB provider +
  scheduler, an API/MCP surface to read and refresh rates, and conversion in the
  valuation. The single-currency caveat is removed from the integration docs.
- EUR is the storage hub. Supporting a non-EUR-derived pair, or sources beyond
  ECB, means adding rows/providers but not changing the conversion algorithm.
- `GBX` is handled as `GBP × 100`; no other pseudo-currencies are assumed.
- Cash-account balances were not part of the valuation when this ADR was
  written; they have since been folded in: `Portfolixir.Portfolios.Valuation`
  reports `total_cash` and `total_with_cash`, converting each cash account to the
  portfolio base currency through this same hub-and-triangulation path.
- The Portfolio Performance importer can later capture per-transaction exchange
  rates into this store; today it still discards them, which this ADR does not
  change.
