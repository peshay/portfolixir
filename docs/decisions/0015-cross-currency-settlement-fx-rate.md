---
layout: docs
title: "ADR-0015: Cross-currency transaction settlement with a stored FX rate"
description: Decision to allow booking a security in its own currency while settling cash in a different account currency, persisting the settlement FX rate so per-position P&L is FX-honest.
---

# ADR-0015: Cross-currency transaction settlement with a stored FX rate

- **Status:** Accepted
- **Date:** 2026-06-14

## Context

Retail brokers such as comdirect display and settle everything in the account's
base currency. Buying a USD-denominated security through a EUR account produces a
EUR cash debit computed at **the broker's own FX rate**, while the security itself
is priced in USD. The broker confirmation shows both figures: the USD trade amount
*and* the EUR amount debited.

Two earlier decisions collide with this reality:

- Issue #343 (closed) chose to **reject** any transaction whose currency does not
  match its linked cash account, and explicitly put *"automatic FX conversion of
  stored amounts"* out of scope. That reject policy blocks the ordinary comdirect
  flow above.
- Holdings P&L is computed per security in the security's own currency
  ([ADR-0004](0004-holdings-derived-from-transactions.html)). But when a foreign
  trade is forced into the account currency, the stored `avg_cost` is EUR while the
  latest price is USD, so per-position P&L is off by the FX spread — a live case
  showed **+15.4% on day one with zero real movement** ("phantom P&L").

The alternative that would avoid any FX machinery — holding a native-currency cash
account per security currency — is not available at brokers that settle everything
in the base currency, so it cannot be required of users.

Constraints that apply:

- Money and rates are `Decimal`, never floats
  ([ADR-0003](0003-decimal-for-money.html)); decimal money/quote columns use
  precision/scale `20,6`.
- FX always triangulates through the EUR hub
  ([ADR-0007](0007-currency-conversion-with-exchange-rates.html)); no direct cross
  rates are stored or computed.
- Derived figures stay reproducible from stored data
  ([ADR-0004](0004-holdings-derived-from-transactions.html)); the ledger projection
  reducer is pure ([ADR-0011](0011-unified-ledger-projection.html)).
- A written rounding policy for FX conversion is still pending (#344).

## Decision

Allow a transaction whose **security currency differs from its cash account's
settlement currency**, by storing a **settlement FX rate** on the transaction
instead of rejecting the mismatch.

- **Persist three linked figures:** the trade amount in the security's own currency,
  the cash amount in the settlement (account) currency, and the settlement FX rate
  relating them, all `Decimal` (rate stored at scale `6`, consistent with the
  existing money/quote columns).
- **Source of the rate:** the broker's actual rate, derived as
  `settlement_amount / security_amount` when both legs are known (the comdirect
  case). When only one side is known, fall back to the EUR-hub rate for the date
  ([ADR-0007](0007-currency-conversion-with-exchange-rates.html)). The rate is never
  a direct cross rate.
- **Honest per-position P&L:** cost basis and P&L are computed in the security's own
  currency from the security-currency amount; the cash leg moves the settlement
  currency. The day-one foreign position reads ~0% on zero real movement.
- **Mismatch now requires a rate, not a rejection** (supersedes the #343 reject
  policy). If no usable rate exists for the pair, the position is marked
  unpriceable via the existing `valued`/`price_source` idiom — never reported with a
  wrong number.
- **EUR-hub valuation is unchanged.** This decision concerns transaction settlement
  and native cost basis only; base-currency totals still come from
  [ADR-0007](0007-currency-conversion-with-exchange-rates.html).

This supersedes the currency-mismatch **reject** policy shipped under issue #343
(which was an issue decision, not an ADR). Implementation is tracked by #388.

## Consequences

**Easier.** Real comdirect-style trades (USD security, EUR settlement) become
bookable; per-position P&L is FX-honest, removing phantom P&L; for the common case
the rate needs no manual entry because it is derivable from the two amounts the
broker already provides, and it is the broker's *actual* rate, the most accurate
available.

**Harder / accepted trade-offs.** New fields land on `Ledger.Transaction`, enlarging
the invariant surface of the auditability core — they must be written only through
`Ledger`/`Imports` public functions. The Portfolio Performance import path must map
PP's cross-currency representation (shares + exchange rate + account-currency amount)
onto the stored settlement FX, preserving import idempotency. Correctness depends on
the pending rounding policy (#344): until it is decided, the stored rate scale (6) is
the working rule and small residual rounding differences are possible.

**Off-limits.** Storing or computing direct cross rates (EUR-hub triangulation
stays authoritative); persisting an FX-distorted `avg_cost`; reintroducing the silent
EUR cost-basis comparison that produced phantom P&L.
