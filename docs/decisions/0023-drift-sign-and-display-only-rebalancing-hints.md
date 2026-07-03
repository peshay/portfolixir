---
layout: docs
title: "ADR-0023: Drift sign convention and display-only rebalancing hints"
description: Flip allocation drift to positive-means-overweight, add a per-security drill-down, and allow display-only rebalancing hints as a reviewed scope clarification.
---

# ADR-0023: Drift sign convention and display-only rebalancing hints

- **Status:** Accepted
- **Date:** 2026-07-03

## Context

`Portfolixir.Portfolios.Allocation` computes category drift as
`target_weight − actual_weight`: a category holding **more** than its target
shows a **negative** drift. The owner reads drift the other way around —
positive means overweight ("too much in it"), matching the common
overweight/underweight convention and their pre-Portfolixir bookkeeping.

The allocation breakdown also stops at category level. For rebalancing, the
owner needs to open a category and see the member securities, each with its
contribution to the drift, and ideally what a corrective trade would look like
at the latest stored quote.

That last part collides with a standing rule: AGENTS.md forbids implementing
"rebalance" functionality unless a reviewed story changes scope. As with
broker-PDF intake (ADR-0021), the owner reviewed this and decided to draw the
boundary explicitly rather than leave it implicit.

## Decision

1. **Flip the drift sign convention** to `actual_weight − target_weight`
   everywhere: positive = overweight, negative = underweight. This applies
   uniformly to `drift_weight` and `drift_value` in the Allocation module, the
   UI, the JSON API, the MCP tool schemas, and the documentation. It is a
   **breaking API change**, shipped once, documented in the API docs and
   changelog — not a UI-only presentation flip, so no surface ever disagrees
   with another.
2. **Add a category drill-down:** expanding a category lists its member
   securities with actual weight/value and each security's share of the
   category drift.
3. **Allow display-only rebalancing hints** as a reviewed scope
   clarification: alongside the drift, the UI/API may show the quantity to
   buy or sell **at the latest stored quote** that would close the gap
   (rounded per ADR-0016). Constraints, mirroring ADR-0021's pattern:
   - Hints are **derived display data** — never persisted as orders, plans,
     or pending actions.
   - **No order generation, no execution, no broker/bank connectivity.** The
     "no automatic trading" security boundary is untouched.
   - Hints carry no fee/tax modelling; they are stated as indicative
     quantities, not advice. Fee/tax-aware suggestions are out of scope.

## Consequences

- One PR for the sign flip (module + UI + API + MCP + docs share files;
  stacked PRs would mis-merge). API/MCP consumers must adapt — acceptable for
  a self-hosted app with few consumers; the changelog entry states the flip.
- Drill-down and hints follow as separate stories with exact-`Decimal` test
  expectations and API/MCP coverage.
- AGENTS.md's "no rebalance" rule is **narrowed, not removed**: computation
  and display of indicative corrective quantities are in scope; anything that
  creates, stores, or transmits an order remains forbidden.
