---
layout: docs
title: "ADR-0003: Decimal for all financial values"
description: Decision to use Decimal for money and serialise decimals as strings.
---

# ADR-0003: Decimal for all financial values

- **Status:** Accepted; **amended 2026-11-01** (a write refuses a JSON number
  in a financial field; the Sprint 22 planning PR, #1291)
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

## Amendment: a write refuses a JSON number in a financial field (2026-11-01, the Sprint 22 planning PR; #1291)

**Why.** "Requests should send them as strings" was a recommendation, and
the API honoured it only by accident. A JSON number in a money field is
decoded as a binary float and cast through `Decimal.from_float`, so a value
past about 17 significant digits is stored as a different number than the
one sent (`1234567890.12345678` is stored as `1234567890.1234567`). The
MCP companion already sends strings; a hand-written client does not have
to. A float that only usually round-trips is the drift this record exists
to rule out (the Sprint 21 closing act's money lens, #1291).

**What changes.** Every write under `/api/v1` refuses a JSON number in a
money, quantity, price, fee, tax or exchange-rate field with a 422 that
names the field ("must be a decimal string"). A string that parses as a
decimal is accepted as before; an integer sent as a JSON number is refused
too, because one rule is easier to state and to test than a rule with an
exception. Reads are unchanged: they already serve strings.

**Consequences.**

- A client that sends numbers gets a named 422 instead of a silently
  rounded value. The contract gains an entry that says so, and the API
  reference says it in both languages.
- Nothing stored changes, and no stored row is re-read.
- **What would reopen it:** a client that cannot send JSON strings for
  these fields and has no way to adapt.
