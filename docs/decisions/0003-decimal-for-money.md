---
layout: docs
title: "ADR-0003: Decimal for all financial values"
description: Decision to use Decimal for money and serialise decimals as strings.
---

# ADR-0003: Decimal for all financial values

- **Status:** Accepted
- **Date:** 2026-05-23

## Context

Portfolixir's primary goal is auditable, reproducible financial records.
Binary floating point cannot represent decimal monetary amounts exactly, which
leads to rounding drift that is unacceptable for money, quantities, and prices.

## Decision

Use `Decimal` for all persisted financial values: money, quantities, prices,
fees, taxes, and FX rates. Floats are not used for persisted financial values.
Across the JSON API and MCP boundary, decimals are serialised as strings (and
requests should send them as strings) so no precision is lost in transport.

## Consequences

- Exact arithmetic and stable, reproducible holdings and totals.
- Clients must treat financial fields as strings, not numbers, to avoid
  reintroducing float rounding.
- Calculations and tests use exact `Decimal` expectations with deterministic
  fixtures.
- `String.to_atom/1` on external input and float-backed financial fields are
  off-limits.
</content>
