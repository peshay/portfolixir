---
layout: docs
title: "ADR-0005: Split quote providers"
description: Decision to use different providers for security search and quote history.
---

# ADR-0005: Split quote providers — search vs. history

- **Status:** Accepted
- **Date:** 2026-05-23

## Context

Portfolixir needs two distinct capabilities from market-data providers:
discovering securities (search) and fetching daily close history. No single
free provider serves both well:

- Portfolio Performance's API exposes search but no price history.
- CoinGecko's free public API caps history at 365 days (`error_code 10012`).
- Yahoo Finance returns the full daily series, including crypto via the
  `<TICKER>-<CURRENCY>` symbol form (e.g. `BTC-USD`).

## Decision

Split provider responsibilities:

- **Search:** Portfolio Performance for stocks/ETFs/funds; CoinGecko for crypto.
- **Quote history:** Yahoo Finance for both asset kinds, queried with
  `period1=0` and `period2=<now>` to get the full daily history (`range=max`
  silently downsamples long histories to monthly).

Securities whose provider has no quote adapter, or whose adapter cannot run
because required fields such as ticker are missing, are reported as skipped with
a reason; failed adapter calls are reported separately from successful syncs.

## Consequences

- Full daily history for both equities and crypto, beyond CoinGecko's 365-day
  cap.
- A dependency on unofficial Yahoo behaviour (`period1=0`, symbol form); these
  endpoints can change and must be treated as a known risk.
- Two provider integrations to maintain, each behind its own adapter so one can
  change without disturbing the other.
- All provider calls are stubbed with fakes in tests; no real network calls.
