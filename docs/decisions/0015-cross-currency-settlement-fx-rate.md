---
layout: docs
title: "ADR-0015: Cross-currency transaction settlement with a stored FX rate"
description: Decision to allow booking a security in its own currency while settling cash in a different account currency, persisting the settlement FX rate so per-position P&L is FX-honest.
---

# ADR-0015: Cross-currency transaction settlement with a stored FX rate

- **Status:** Accepted
- **Date:** 2026-06-14
- **Amended:** 2026-10-07: a cross-currency booking's fees and taxes are in
  its cash account's currency, and a security-currency figure converts them
  at the trade's own rate (#1108, #1107; see "Amendment (2026-10-07)"
  below). Adopted by the merge of the Sprint 20 planning PR.

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

## Amendment (2026-10-07): fees and taxes are in the cash account's currency, and a security-currency figure converts them at the trade's own rate

**Status:** adopted by the merge of the Sprint 20 planning PR; risk-tier
(money), so it is signed before the batch that builds it.

### Why

This record stores three linked figures for a cross-currency trade (the
security amount, the settlement amount and the rate) and says nothing about
the currency of its fees and taxes. The ledger has always read them in the
cash account's currency:

- the settlement guard (`Ledger.SettlementGuard`): a purchase's cash is
  settlement + fees + taxes, a sale's settlement − fees − taxes, "read in the
  account currency, the currency of the cash leg they are part of";
- the performance walk, since #1051 (`Performance.trade_cost/2`).

Three readers do not:

- **The trade matcher** (#1108). `Ledger.transaction_for_matcher/2` hands
  the matcher the raw fees and taxes, and `TradeMatcher` adds them to
  quantity × price in the security's currency. A closed trade's basis,
  proceeds and realized result therefore mix two currencies. It reaches the
  security's Trades tab, Income's realized list, the Overview's closed-trades
  card, the trades and realized-gains reads, and `TradeReturn`.
- **The Costs report** (#1107). `Portfolios.Costs` converts fees and taxes
  from the booking's currency, which on a manual cross-currency trade is the
  security's, and a missing rate names the wrong currency.
- **The income report**, found while triaging #1107. `Income` converts a
  booking's cash and taxes from the booking's currency, so a dividend of a
  foreign security credited to an account in another currency is converted
  from the wrong one. The building story proves it with a red test before it
  changes anything.

### What changes

1. **A booking's fees and taxes are in its cash account's currency**, as its
   cash leg is. Every reader converts them, and a cross-currency booking's
   cash, from that currency, never from the booking's or the security's.
2. **A figure kept in the security's currency converts them at the trade's
   own stored `settlement_fx_rate`** (fee ÷ rate): a FIFO lot's basis, and a
   closed trade's proceeds and realized result. That rate is the broker's
   rate for that cash leg, which this record already makes the trade's rate.
   It is transaction data, so the matcher stays pure (ADR-0033's fold rule:
   rates enter as transaction data, never as reducer lookups). A row without
   a stored rate is a same-currency row and is not converted.
3. **A figure in the base currency** (the Costs report, the income report)
   converts them from the account's currency at the hub rate of the
   booking's date, as the walk has done since #1051.
4. **The figures that change move their computation version**, the payloads'
   basis says so, and the API contract gains an entry.

**Why the trade's own rate, not a hub rate.** The hub rate of the trade date
is a second, different conversion of cash that was converted once already,
at the broker's rate. Only the trade's own rate makes a closed trade's
realized result in the base currency equal the cash it moved when broker
and hub agree (identity 1). The hub-rate alternative differs from it
whenever they do not (identity 3 tells the two apart).

### The identities the building batch pins

With 1 EUR = 1.25 USD on every date and the rate stored as EUR per USD:

1. **A closed trade, broker rate equal to the hub's.** Buy 10 at 100 USD,
   settled 800.00 EUR, fees 5.00 and taxes 1.00 EUR (cash 806.00). Sell 10
   at 120 USD, settled 960.00 EUR, fees 3.00 EUR (cash 957.00). Basis
   **1,007.50 USD**, proceeds **1,196.25 USD**, realized **188.75 USD =
   151.00 EUR = 957.00 − 806.00**. Today: 1,006, 1,197 and 191 USD, 152.80
   EUR.
2. **The Costs report.** Buy 10 at 100 USD settled 790.00 EUR, fees 5.00 and
   taxes 1.00 EUR: the month reads fees **5.00**, taxes **1.00**, total
   **6.00 EUR** (today 4.00, 0.80 and 4.80). The total equals the walk's
   trade costs for that day and the cash minus the settlement (796.00 −
   790.00).
3. **Broker rate unequal to the hub's.** Buy 10 at 100 USD settled 750.00
   EUR, fees 6.00 and taxes 1.50 EUR; sell as in identity 1 with fees 4.00
   EUR. Basis **1,010.00 USD**, realized **185.00 USD**, 148.00 EUR at the
   sale date's hub rate. The hub-rate alternative gives 148.50; today gives
   150.80. Mutation check: converting the fees at the hub rate turns this
   identity red.
4. **A same-currency trade** reads byte-identical figures before and after.

### Consequences of the amendment

- **Risk-tier attention:** one commit group per reader (the matcher, the
  Costs report, the income report), each starting from its red test; the
  verification pass takes identities 1 and 3 first.
- **ADR-0033 is unchanged.** Its fold already reads the rate as transaction
  data; this amendment only says which currency the fees enter that fold in.
- Nothing here creates, stores or transmits an order, and nothing calls out.
