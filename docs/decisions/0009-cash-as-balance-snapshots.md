---
layout: docs
title: "ADR-0009: Cash as balance snapshots, not a mirrored ledger"
description: Decision to track cash with periodic absolute-balance snapshots (plus a cash quote) instead of mirroring every bank booking, keeping cash visible with near-zero upkeep and a clean path to later API automation.
---

# ADR-0009: Cash as balance snapshots, not a mirrored ledger

- **Status:** Accepted
- **Date:** 2026-06-09

## Context

Portfolixir wants cash to be **visible** — so an operator can see liquidity and
compute a **cash quote** (cash as a share of the whole portfolio) — without
turning into a banking app.

Today cash works like Portfolio Performance: a cash account's balance is
**derived from every booking** (deposit, removal, dividend, interest, fee, tax,
buy, sell, transfer). That is fine for a depot's settlement account, whose cash
only moves when a trade or dividend is recorded anyway. It is painful for a real
external account: to keep a current-account (Girokonto) balance correct you would
have to enter every salary, rent, and grocery booking, and every transfer between
your accounts (Tagesgeld, Girokonto, Geschäftskonto, …). That is exactly the
upkeep operators do not want, and chasing it toward live bank sync would pull the
whole project into "needs every bank" banking-app territory — explicitly out of
scope (see `AGENTS.md` security boundaries).

The forces:

- Cash and the cash quote must be visible.
- Upkeep must be near zero; mirroring external accounts is not acceptable.
- Several cash accounts must be supported without maintaining transfers between
  them.
- A later, optional **read-only** automation (a script or bank API filling the
  numbers) should fit without redesign — but no payments, orders, or live sync.

## Decision

Track cash with **absolute-balance snapshots** instead of (only) a derived
ledger.

- **Balance snapshot.** A new transaction kind states a cash account's
  **absolute** balance as of a date ("Girokonto = 4,250 € today"). The operator
  types the number their banking app shows; Portfolixir anchors it. Because each
  account states its own balance, **moving money between accounts needs no
  booking** — the next snapshot of each account already reflects it. This stays
  within [ADR-0004](0004-holdings-derived-from-transactions.html): a snapshot is
  a stored, dated fact, so balances remain reproducible from transactions, not
  mutable running totals.
- **Trades stay informational for cash.** Buy/sell/dividend bookings continue to
  drive holdings, cost basis, and performance. For a snapshot-tracked account the
  **cash truth comes from the snapshot**, not from deriving the account out of
  trades — so an account that is both a depot settlement account and a daily
  current account does not have to be reconciled by hand.
- **"Counts toward the cash quote" flag.** Each cash account can be marked as
  counting toward the cash quote (`counts_toward_cash_quote`, default on), or as
  reference-only — so a business account can be visible without distorting the
  private cash quote. A reference-only account stays listed and inside the total
  cash; only the quote is computed as if it did not exist.
- **Cash quote in the valuation.** The valuation reports
  `cash_quote = total_cash / total_with_cash` next to the existing totals, so the
  figure does not have to be re-derived by every caller.

Delivery is incremental: the **cash quote** shipped first (computable from the
totals that already exist), then the **balance-snapshot** kind (the
`balance_adjustment` transaction, `POST /api/v1/cash_accounts/:id/balance`, and
the anchored balance derivation), then the **counts-toward** flag as its own
small story.

## Consequences

- External accounts cost almost nothing to keep: type the current balance now and
  then, instead of mirroring a ledger. Cash and the cash quote stay visible.
- Several cash accounts are supported with **no transfer bookkeeping**.
- **Trade-off:** snapshots give up strict double-entry. Portfolixir tracks *how
  much* cash is *where now*, not *where money moved*. That is the right trade for
  private portfolio tracking and the wrong one for accounting; operators who want
  a full ledger can still book every cash movement as before.
- A later, optional automation that reads balances (a script, a bank's CSV
  export, or a read-only bank API) writes the same snapshots through the API — so
  manual-now and automated-later use one model, with no payments or orders and no
  live banking integration.
- New surface: a snapshot transaction kind, a cash-account flag, and a cash-quote
  field, each with API/MCP coverage, tests, and user documentation.
