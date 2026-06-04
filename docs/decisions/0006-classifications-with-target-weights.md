---
layout: docs
title: "ADR-0006: Classifications with target weights"
description: Decision to add editable classification trees with target weights, derived actual weights, and per-category descriptions.
---

# ADR-0006: Classifications (taxonomies) with target weights

- **Status:** Proposed
- **Date:** 2026-06-04

## Context

Today Portfolixir describes a security's nature with a single flat
`asset_class` enum of nine fixed codes
(`Portfolixir.Catalog.AssetClasses`). That is enough to label a row, but it
cannot express how a maintainer actually *organises* a portfolio:

- There are no user-defined strategy or category **hierarchies**. Portfolio
  Performance calls these "Klassifizierungen" (taxonomies) and treats them as
  the central organising concept.
- There is no notion of a **target weight** ("SOLL") per category, and no way to
  break a target down across sub-levels.
- There is no **actual weight** ("IST") computed from live-valued holdings, so
  no target-vs-actual drift is available.
- There is no place for a free-text **description per category** to capture the
  intent of a strategy bucket.

This gap also limits the primary near-term goal: an LLM connected over MCP
should be able to see all transactions, the maintainer's strategy/category
levels, the SOLL/IST weights, and live values, so it can reason about drift and
suggest rebalancing. None of that data exists or is exposed yet. The Portfolio
Performance importer already *receives* a `taxonomies` block but currently
discards it (`Portfolixir.Imports.PortfolioPerformance.JsonParser` does not
read it).

Constraints that apply:

- Money and weights are `Decimal`, never floats ([ADR-0003](0003-decimal-for-money.html)).
- Auditable state should be reproducible, not stored as mutable running totals
  ([ADR-0004](0004-holdings-derived-from-transactions.html)).
- The MCP companion stays a thin wrapper over `/api/v1`
  ([ADR-0002](0002-thin-mcp-over-json-api.html)), so any new surface lands in the
  JSON API first.
- Scope stays small; this must not turn Portfolixir into a rebalancing or
  trading platform. It records and reports intent — it does not place orders.

## Decision

Introduce a new bounded context `Portfolixir.Classifications` that models
editable taxonomy trees, alongside a read-time portfolio **valuation** that
turns holdings plus latest quotes into market values and actual weights.

**Stored, editable definitions:**

- **Classification** — a named tree (e.g. "Asset Classes", "Regions", "My
  Strategy"). Has a name and optional description.
- **Category** — a node within one classification, forming a tree via a
  nullable `parent_id`. Carries a name, optional **description**, an optional
  **`target_weight`** (`Decimal`, expressed as a fraction of its parent so that
  targets break down naturally down the tree), a display order, and an optional
  colour.
- **Assignment** — an n:m link from a `Security` to a `Category` with a
  `weight` (`Decimal`, default `1`), so one security can be split across
  categories (e.g. an ETF that is 60% North America / 40% Europe).

**Derived, never stored:**

- **Valuation** — each holding's market value (`quantity × latest close`) and
  its share of the portfolio total, computed on read from transactions and
  quote history.
- **Actual weight (IST)** per category — each holding's market value is
  distributed across its category assignments by assignment weight, aggregated
  per category, and divided by the portfolio total.
- **Effective target (SOLL)** per category — the product of `target_weight`
  along the path from the root, so a parent's target is divided among its
  children.
- **Drift** — effective target minus actual weight per category.

These definitions, valuations, and weights are exposed through `/api/v1` and
then mirrored by MCP tools, so an LLM client sees categories, descriptions,
SOLL, IST, and drift over the existing thin MCP boundary.

## Consequences

- The maintainer can model arbitrary strategy/category hierarchies with
  per-category descriptions and target weights, including breaking a target
  down across sub-levels — capabilities Portfolio Performance does not offer in
  the same way.
- Actual weights and drift stay reproducible from transactions and quotes,
  consistent with [ADR-0004](0004-holdings-derived-from-transactions.html); only
  the *definitions* (trees, targets, assignments, descriptions) are mutable
  configuration.
- An LLM over MCP gains a single coherent view of strategies, SOLL/IST, and live
  values to base rebalancing suggestions on. Portfolixir still records and
  reports — it never places orders or rebalances.
- The Portfolio Performance importer can map its `taxonomies` block onto
  classifications, categories, and assignments instead of discarding it, which
  also improves how imported securities are classified.
- New schema arrives: `classifications`, `categories`, and
  `security_category_assignments` tables, plus the read-time valuation code. The
  existing flat `asset_class` field stays as a lightweight built-in label and is
  not removed by this decision.
- Cost: more surface to keep consistent across context, API, MCP, tests,
  translations, and docs. The work is therefore split into small TDD stories
  (see the planning notes accompanying this ADR) rather than one large change.
- Target weights are stored relative to the parent. Validation must keep sibling
  targets within `0..1`; surfacing a "remaining/over-allocated" hint is left to
  the UI stories.
