---
layout: docs
title: "ADR-0016: Rounding policy — full precision in compute, round only at the human display"
description: Decision to carry full Decimal precision through all computation and persistence, rounding only at the human-facing display boundary, with scale and mode fixed per value class.
---

# ADR-0016: Rounding policy — full precision in compute, round only at the human display

- **Status:** Accepted
- **Date:** 2026-06-14

## Context

Portfolixir stores every monetary value, quantity, price, fee, tax and FX rate as
`Decimal` ([ADR-0003](0003-decimal-for-money.html)), but it has **no written
rounding policy** (#344): which scale and which rounding mode apply, and at which
point in a calculation rounding is allowed. Without one, different code paths could
round at different places and drift apart — a price × quantity feeds a cost basis,
which feeds an unrealized P&L, which is time-weighted across partial days and summed;
each premature rounding step accumulates error until a cash balance is off by a cent
or the "bookings of a transaction sum to zero" invariant breaks.

Constraints that apply:

- Money and rates are `Decimal`, never floats
  ([ADR-0003](0003-decimal-for-money.html)). Decimal columns carry explicit
  precision/scale: money/quotes/rates `20,6`, volume `30,6`.
- FX conversion already keeps **intermediate arithmetic at full precision** and
  treats rounding as a display concern; same-currency conversion is the identity
  ([ADR-0007](0007-currency-conversion-with-exchange-rates.html)). This ADR
  generalises that rule from FX to **all** operations.
- The JSON API and MCP companion return financial values as Decimal `:normal`
  **strings**, full precision, end to end ([ADR-0002](0002-thin-mcp-over-json-api.html));
  their consumer is a program (e.g. an agent), not a human reading two decimals.
- Derived figures must stay reproducible from stored data
  ([ADR-0004](0004-holdings-derived-from-transactions.html)).

## Decision

**Compute and persist at full precision; round only at the human display.**

1. **Intermediate arithmetic — never round.** Every multi-step computation
   (price × quantity, FX triangulation, cost basis, realized/unrealized P&L,
   time-weighting, aggregation) carries full `Decimal` precision from start to end.
   No rounding between steps. This extends [ADR-0007](0007-currency-conversion-with-exchange-rates.html)
   from FX to all operation classes.

2. **Persistence — quantize to the column scale, mode `:half_up`.** Stored values
   are quantized only to the column's declared scale (6 for money/quotes/rates, 6
   for volume) using `:half_up`. Because scale 6 is finer than any real-world input,
   this is effectively lossless; the rule exists for the rare derived value written
   back. Stored amounts are never pre-rounded to a presentation scale.

3. **Machine boundary (JSON API / MCP) — no rounding.** Responses serialize the
   full-precision stored/computed `Decimal` as `:normal` strings. The consumer
   decides how to present. (Reaffirms [ADR-0002](0002-thin-mcp-over-json-api.html).)

4. **Human boundary (LiveView/SVG UI and human-facing exports) — round here, and
   only here**, with scale per value class and mode `:half_up` (kaufmännische
   Rundung, matching the broker and tax statements users reconcile against; also the
   `Decimal` default context):
   - **Money:** 2 decimal places (currency minor unit; 2 is the baseline — see
     open refinement below).
   - **Percentages** (weights, P&L %, allocation drift): 2 decimal places.
   - **FX rates:** 6 decimal places.
   - **Quantities:** up to 6 decimal places, trailing zeros trimmed.

5. **Invariants are checked at full precision, never on display-rounded values.**
   The sum-to-zero of a transaction's legs, cash reconciliation, and import
   idempotency are evaluated on stored full-precision `Decimal`. A display-rounded
   figure never feeds back into a stored value or an invariant check.

6. **Displayed breakdowns that must total a displayed sum** (e.g. allocation
   percentages shown as summing to 100 %) use the **largest-remainder method** on the
   already-rounded display figures, at the human boundary only — never persisted and
   never fed back into computation.

## Consequences

**Easier.** Errors cannot accumulate through a calculation, because nothing rounds
mid-stream; cash balances and the sum-to-zero / idempotency invariants reconcile
exactly. The agent (via MCP) always sees raw precision and can apply its own policy.
Humans see clean two-decimal money that matches their broker statement.

**Harder / accepted trade-offs.** Every human-display code path must apply the
rounding explicitly at the edge — there is no "round early and forget" shortcut; a
property test (no rounding drift; legs sum to zero) guards this. Displayed parts can
look like they don't add up unless the largest-remainder rule is applied, which is
extra display logic. Money display is fixed at 2 places as a baseline; true
per-currency minor units (e.g. JPY = 0, the existing `GBX` pence pseudo-currency
handled in [ADR-0007](0007-currency-conversion-with-exchange-rates.html)) are a
later refinement, not part of this decision.

**Off-limits.** Rounding intermediate results; persisting presentation-rounded
amounts; rounding inside the JSON API/MCP responses; using float tolerance anywhere
in money math (assertions stay Decimal-exact, [ADR-0003](0003-decimal-for-money.html)).
