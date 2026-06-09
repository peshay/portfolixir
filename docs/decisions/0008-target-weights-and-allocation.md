---
layout: docs
title: "ADR-0008: Target weights and SOLL/IST allocation"
description: Decision to store per-category target weights in Portfolixir and report the SOLL/IST allocation breakdown with drift in one read.
---

# ADR-0008: Target weights and SOLL/IST allocation

- **Status:** Accepted
- **Date:** 2026-06-08

## Context

[ADR-0006](0006-classifications-with-target-weights.html) added classification
trees but deliberately deferred weights: categories carried structure, not a
target. In practice the weekly review an operator (or the LLM over MCP) runs is a
SOLL/IST check — compare each strategy category's **target** weight against its
**actual** weight and act on the **drift**.

Without stored targets that comparison lives outside Portfolixir: the target
allocation sits in an external document, and producing drift means joining
holdings, classifications, and those external targets by hand on every review.
If Portfolixir is the single source of truth, the targets belong in it and the
breakdown should come from one call.

Constraints that apply:

- Derived figures stay reproducible from stored data, not mutable running totals
  ([ADR-0004](0004-holdings-derived-from-transactions.html)). The actual side is
  derived from the live valuation on read; only the targets are stored.
- Money and weights are `Decimal`, never floats
  ([ADR-0003](0003-decimal-for-money.html)).
- The MCP companion stays a thin wrapper over `/api/v1`
  ([ADR-0002](0002-thin-mcp-over-json-api.html)).
- Scope stays small: this records targets and reports drift; it does not place
  orders or rebalance.

## Decision

Store target weights and compute the SOLL/IST breakdown on read.

**Stored targets:**

- A `portfolio_targets` table and `Portfolixir.Portfolios.Target` schema hold one
  target weight per `(portfolio, classification, category)`. The weight is a
  `Decimal` fraction in `[0, 1]` (e.g. `0.25` for 25%), matching how the
  valuation reports actual weights. Targets are not required to sum to `1`: a
  portfolio may define only the categories it tracks.
- `Portfolixir.Portfolios.Targets` upserts (set the supplied categories, leave
  the rest), lists (optionally scoped to one classification), and deletes
  targets. A category must belong to the named classification.

**Derived allocation (SOLL/IST + drift), one call:**

- `Portfolixir.Portfolios.Allocation` groups the live valuation's valued
  positions into a chosen classification's categories (the IST side), joins each
  category's stored target (the SOLL side), and reports per category:
  `market_value`, `actual_weight` (its share of the valued total),
  `target_weight`, `drift_weight` (`target_weight - actual_weight`), and
  `drift_value` (the drift restated in the base currency — how much to buy or
  sell to reach the target). Securities held but unassigned in the tree are
  summed into an `unassigned` bucket. Weights mirror the valuation: shares of the
  valued positions' total, cash excluded. The breakdown works for custom and
  built-in classifications alike (e.g. asset-class drift).

**Surfaces:**

- JSON API: `GET/PUT /api/v1/portfolios/:id/targets`,
  `DELETE /api/v1/portfolios/:id/targets/:category_id`, and
  `GET /api/v1/portfolios/:id/allocation?classification_id=`.
- MCP tools: `portfolixir.targets.list`, `portfolixir.targets.set`,
  `portfolixir.targets.delete`, and `portfolixir.portfolios.allocation`.

## Consequences

- The weekly SOLL/IST check and per-category drift come from one read against
  Portfolixir, so the target allocation no longer has to be carried in an
  external document or joined by hand.
- New schema arrives: `portfolio_targets`. Only the targets are stored; the
  actual side stays derived from transactions, quotes, and exchange rates on
  read, consistent with [ADR-0004](0004-holdings-derived-from-transactions.html).
- Drift is reported as both a weight and a base-currency amount, but Portfolixir
  still does not place orders or rebalance — acting on the drift stays manual.
- Splitting one security across several categories with partial weights remains
  out of scope; a security still sits in at most one category per classification.
- More surface to keep consistent across context, API, MCP, tests, and docs.
