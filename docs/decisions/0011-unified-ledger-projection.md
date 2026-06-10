---
layout: docs
title: "ADR-0011: Unified ledger projection"
description: Decision to define each booking kind's effect once, in a single per-kind reducer that feeds every derived read model.
---

# ADR-0011: Unified ledger projection (single per-kind reducer)

- **Status:** Accepted
- **Date:** 2026-06-10

## Context

ADR-0004 derives every read model from the immutable transaction history, so
each model must interpret the booking kinds. That interpretation had grown
into three independent `case kind` blocks: `Ledger.cash_balances` (signed
cash deltas plus the ADR-0009 snapshot anchoring), `Ledger.Positions`
(quantity deltas), and the `Portfolios.Performance` daily walk (cash,
quantities **and** external-flow classification for TTWROR).

When the `balance_adjustment` kind (ADR-0009) was introduced, several of
these had to be changed in lockstep — a silent-drift risk: forgetting one
place would not fail loudly, it would quietly make cash, positions and
performance disagree about the same ledger. Every future kind (e.g. one
flagged for IRR/cash-flow purposes) multiplies that risk.

## Decision

Define the effect of each booking kind **once**, in
`Portfolixir.Ledger.Projection`, and make every derived read model a generic
fold over that effect.

- `Projection.effects/1` maps a transaction to its canonical effect: signed
  **cash legs** (`{:add, delta}`, or `{:set, absolute}` for an ADR-0009
  balance snapshot), signed **quantity legs** per
  `{securities_account, security}`, and an **external** flag stating whether
  the booking is an external flow that a time-weighted return must
  neutralise.
- The projection also owns the replay-order rule that snapshots apply after
  the other bookings of their day (`intra_day_order/1`) and the pure
  cash-balance fold (`Projection.cash_balances/1`).
- `Ledger.cash_balances`, `Ledger.Positions.calculate` and the
  `Portfolios.Performance` daily walk consume effects; none of them
  dispatches on the kind anymore.
- A kind the projection has not been taught **raises** instead of being
  silently ignored, so an incompletely added kind fails loudly in every read
  model at once.

Deliberately outside the reducer: the moving-average holdings view and the
FIFO trade matcher. They are cost-basis views that by definition consider
only the priced `buy`/`sell` kinds — they filter to two kinds rather than
interpreting all of them, so routing them through the projection would
change behaviour (deliveries carry no own cost).

## Consequences

- Adding a booking kind means one `effects/1` clause (plus the
  `Transaction` validation); cash balances, positions and performance pick
  it up consistently with no further code. The projection test suite
  iterates over `Transaction.kinds/0` generically, so it covers new kinds
  without modification.
- The read models can no longer drift apart on what a kind means; the
  trade-off is that a kind whose semantics cannot be expressed as cash legs,
  quantity legs and an external flag would force the effect shape to grow
  (a deliberate speed bump — that is a semantic change worth an ADR
  amendment).
- This is a refactor, not a feature: TTWROR, valuation and allocation
  results are unchanged, and balances remain derived on read (ADR-0004).
  Caching or persisting projections stays a future decision.
