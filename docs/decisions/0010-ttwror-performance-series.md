---
layout: docs
title: "ADR-0010: Daily valuation series and TTWROR"
description: Decision to derive a daily portfolio valuation series on read and compute the true time-weighted rate of return the Portfolio Performance way.
---

# ADR-0010: Daily valuation series and TTWROR

- **Status:** Accepted
- **Date:** 2026-06-09

## Context

Portfolixir values the portfolio **now** ([valuation](0007-currency-conversion-with-exchange-rates.html))
but says nothing about how it performed. The figure operators actually use for
that — and the one Portfolio Performance leads with — is the **true
time-weighted rate of return (TTWROR)**: the return of the investments
themselves, with deposits and withdrawals neutralised, so it does not reward or
punish the timing of putting money in. Without it, judging performance still
requires opening Portfolio Performance.

Constraints that apply:

- Derived figures stay reproducible from stored data on read, never persisted
  as running totals ([ADR-0004](0004-holdings-derived-from-transactions.html)).
- Money, rates and returns are `Decimal` ([ADR-0003](0003-decimal-for-money.html));
  rounding is a display concern.
- Multi-currency values convert through the EUR-hub rates
  ([ADR-0007](0007-currency-conversion-with-exchange-rates.html)).
- The MCP companion stays a thin wrapper over `/api/v1`
  ([ADR-0002](0002-thin-mcp-over-json-api.html)).

## Decision

Derive a **daily valuation series** on read and chain **daily returns**
geometrically, the way Portfolio Performance computes TTWROR.

- From the first transaction to the end date, each day's portfolio value is
  positions (quote close on or before the day, converted at that day's rates)
  plus cash, in the base currency.
- Each day's **external flow** is neutralised: deposits and removals, security
  deliveries in and out (valued at that day's quote), and the residual jump of
  a cash **balance snapshot** ([ADR-0009](0009-cash-as-balance-snapshots.html))
  — stating a balance is money appearing or leaving outside the recorded
  bookings. Dividends, interest, fees and taxes are **internal** (they are
  return); buys, sells, cash transfers and security transfers only move money
  inside the portfolio.
- Daily return and chaining, with flows at the start of the day:

      r_d = V_d / (V_{d−1} + F_d) − 1        TTWROR = ∏(1 + r_d) − 1

  A day with nothing invested contributes no return.
- **Periods**: `ytd`, `1y`, `3y`, `5y`, `max`. A period chains only its own
  days, starting from the value just before the period.
- Surfaces: `GET /api/v1/portfolios/:id/performance` (period and optional
  daily series) and the MCP tool `portfolixir.portfolios.performance`.

## Consequences

- Performance is finally readable from Portfolixir itself, period by period,
  consistent with the Portfolio Performance figure operators already know.
- The series is recomputed on read — auditable and always in sync with the
  ledger, at the cost of walking every day since the first transaction. For a
  personal portfolio this is cheap; a cache can come later without changing
  the contract.
- Accepted trade-offs: a security with no usable quote or rate path
  contributes zero value until one exists, and the later jump counts as
  return; deliveries without a quote enter as zero-valued flows. Both mirror
  how the live valuation treats unpriceable positions.
- The money-weighted return (IRR), which PP shows next to TTWROR, is a natural
  follow-up on the same series and stays out of scope here.
