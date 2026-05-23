---
layout: docs
title: "ADR-0004: Holdings derived from transaction history"
description: Decision to derive holdings and trades from immutable transactions.
---

# ADR-0004: Holdings and trades derived from transaction history

- **Status:** Accepted
- **Date:** 2026-05-23

## Context

A portfolio's current position can either be stored as mutable running state or
recomputed from the transaction history. Stored running balances can drift out
of sync with the underlying records and are hard to audit after edits.

## Decision

Treat the manual transaction history as the immutable source of truth. Current
holdings (`Portfolixir.Ledger.Positions`) and FIFO-matched trades
(`Portfolixir.Ledger.TradeMatcher`) are derived from transactions on read, not
stored or entered manually.

## Consequences

- Holdings and realised P&L are always reproducible and traceable back to the
  transactions that produced them.
- Correcting a position means correcting its transactions, which keeps the
  audit trail honest.
- Derivation happens at read time; if data volume ever makes this expensive,
  caching or materialised views would be a future decision (new ADR).
</content>
