---
layout: docs
title: "ADR-0034: money-weighted metrics — net invested capital, wealth multiple, and a hand-rolled XIRR next to TTWROR"
description: Design decision for issue #568, consolidating the 2026-07-12 design session and the owner sign-off given the same day. Exactly four transaction kinds are external flows (deposit, removal, inbound delivery, outbound delivery, plus balance_adjustment as a signed external flow); the flow classifier is parameterized by scope so the benchmark comparison (#572) can reuse it. XIRR is hand-rolled with float64 confined to the solver and Decimal everywhere else, nothing persisted. Net invested at or below zero renders "n/a", never a negative multiple, and period-scoped invested capital is shown as two labeled numbers.
---

# ADR-0034: money-weighted metrics — net invested capital, wealth multiple, and a hand-rolled XIRR next to TTWROR

- **Status:** Accepted (owner sign-off 2026-07-12 on
  [#568](https://github.com/peshay/portfolixir/issues/568); this record
  consolidates the design-session memo and that sign-off — decision gate per
  [ADR-0026](0026-epic-batch-workflow.html))
- **Date:** 2026-08-02

## Context

The performance surface leads with TTWROR
([ADR-0010](0010-ttwror-performance-series.html)). TTWROR is cashflow-neutral:
it answers "how did the investments perform, as if deposits and withdrawals
never happened". For a portfolio with heavy later contributions, a max-period
TTWROR reads as a wealth multiple it is not — a cumulative percentage in the
thousands can coexist with a real wealth multiple in the single digits.
Portfolio Performance shows TTWROR and IRR side by side; Portfolixir should
too, with a one-line explanation of what each answers.

Issue [#568](https://github.com/peshay/portfolixir/issues/568) asks for three
figures next to TTWROR:

- **Net invested capital** — external inflows minus outflows over the period.
- **Wealth multiple** — current value divided by net invested capital.
- **Money-weighted return (IRR/XIRR)** — per annum for the period.

The engine prerequisite is settled:
[#545](https://github.com/peshay/portfolixir/issues/545) (trade-price
re-pricing inflating long-period TTWROR) was fixed and closed on 2026-07-25,
so the metric set explains numbers that are no longer about to change.

## Decision

Owner-confirmed on 2026-07-12, recorded here verbatim in substance:

### 1. Flow definition — PP-compatible, classifier parameterized by scope

At portfolio scope, exactly **four** transaction kinds are external flows:
`deposit`, `removal`, `inbound_delivery`, `outbound_delivery` — deliveries at
full transaction value, per the Portfolio Performance manual. Everything else
is internal: dividends and interest raise performance, fees and taxes reduce
it, buys/sells and transfers between own accounts net to zero.
`balance_adjustment` is an **external signed flow** — it fabricates value with
no internal counterpart.

The classifier takes the **scope as a parameter**: at per-security scope,
buy/sell/dividend invert their roles and taxes drop out (PP semantics).
Per-security IRR itself is deferred; the parameterization exists so the
benchmark comparison ([#572](https://github.com/peshay/portfolixir/issues/572))
and a later per-security view consume the same classifier instead of forking
the flow definition.

### 2. XIRR — hand-rolled, float64 confined to the solver

Existing Elixir XIRR packages are float-based and unmaintained; the solver is
hand-rolled (on the order of a hundred lines):

- Newton's method from initial guess `0.1` with the analytic derivative,
  falling back to bracketed bisection on `(−0.999999, +10]`.
- Day-count Act/365; convergence tolerance `1e-7` (Excel-compatible);
  iteration cap ~200.
- All flows of one sign → the metric renders "n/a"; no root is invented.
- Windows shorter than one year show the **non-annualized period MWR** —
  annualizing a short window explodes the figure (a known PP complaint).

**Precision policy — the explicit exception:** `Decimal` end-to-end for
flows, net invested capital, and the wealth multiple
([ADR-0003](0003-decimal-for-money.html)); **float64 only inside the XIRR
solver**, whose result returns as a rounded `Decimal` and is never persisted.
Matching Excel and Portfolio Performance (both float64) is the correctness
criterion; a pure-Decimal exp/ln implementation is complexity for
sub-display-precision benefit. The exception is documented in the solver's
module doc and ends at the solver boundary.

### 3. Denominator semantics and honest rendering

- Net invested capital at or below zero → wealth multiple and "% on invested"
  render **"n/a"**, never a negative or infinite multiple.
- Period-scoped invested capital is shown as **two labeled numbers** —
  opening value and net period flows — not one merged figure (PP's combined
  widget confuses its own forum).
- Multi-currency: each flow converts at flow-date FX through the EUR hub
  ([ADR-0007](0007-currency-conversion-with-exchange-rates.html)); the result
  is the EUR-investor IRR including FX, and the surface says so.

### Surface copy

> TTWROR: how well the investments performed, as if deposits and withdrawals
> never happened. IRR: how well the money actually grew, including when it
> was added or removed.

Presented per the microcopy standard (impersonal, terse; explanation in the
ⓘ tooltip, not in the sightline).

## Consequences

- A flow classifier lives in the performance context, parameterized by scope,
  shared by net invested capital, XIRR, and later #572.
- The Wealth view shows net invested capital, wealth multiple, and IRR next
  to TTWROR, each with its tooltip explanation; API and MCP expose the same
  figures as strings (AGENTS.md coverage rule).
- Deterministic `Decimal` test fixtures pin: the flow classification per
  kind, the XIRR solver against Excel-verified synthetic cases, the "n/a"
  paths (net invested ≤ 0, all-same-sign flows), the short-window
  non-annualized rendering, and flow-date FX conversion.
- [ADR-0010](0010-ttwror-performance-series.html) is untouched: TTWROR keeps
  its definition; these metrics are additions beside it.
- Implementation is ledger/money-domain math and therefore **risk-tier**
  ([ADR-0026](0026-epic-batch-workflow.html)): its own small PR with real
  human review.

## References

- Issue [#568](https://github.com/peshay/portfolixir/issues/568) — problem
  statement, design-session memo, and owner sign-off (2026-07-12)
- `_bmad-output/planning-artifacts/design-session-results-2026-07-12.md`,
  Session B — the underlying research memo
- [#572](https://github.com/peshay/portfolixir/issues/572) — benchmark
  comparison, the second consumer of the flow classifier
- [#545](https://github.com/peshay/portfolixir/issues/545) — the sequencing
  prerequisite, closed 2026-07-25
- [ADR-0003](0003-decimal-for-money.html), [ADR-0007](0007-currency-conversion-with-exchange-rates.html),
  [ADR-0010](0010-ttwror-performance-series.html),
  [ADR-0026](0026-epic-batch-workflow.html)
