---
layout: docs
title: "ADR-0001: Modular Phoenix monolith"
description: Decision to structure Portfolixir as a modular monolith with bounded contexts.
---

# ADR-0001: Modular Phoenix monolith with bounded contexts

- **Status:** Accepted
- **Date:** 2026-05-23

## Context

Portfolixir is a small, self-hosted, single-user portfolio tracker. The scope
is intentionally narrow and the project values smallness and readability over
extensibility. A distributed or service-oriented design would add deployment
and operational overhead with no matching benefit at this scale.

## Decision

Build a single Phoenix application structured as a modular monolith with a few
bounded domain contexts:

- `Portfolixir.Catalog` — securities, quotes, sync, search, logos
- `Portfolixir.Portfolios` — portfolios, cash accounts, depots
- `Portfolixir.Ledger` — transactions, derived holdings, FIFO trades
- `Portfolixir.Imports` — Portfolio Performance import flow
- `PortfolixirWeb` — LiveViews, JSON API, components

Domain contexts stay separate from web and wrapper code. The web layer depends
on contexts; contexts do not depend on the web layer.

## Consequences

- Simple to run and reason about: one app, one database, one deploy unit.
- Clear seams make it possible to split a context out later if scope ever grows.
- Discipline is required to keep web/MCP code from leaking into contexts; this
  is enforced by review and the rules in `AGENTS.md`.
- Cross-context features must respect the one-way dependency direction.
</content>
