---
title: "Portfolixir PRD — FX-Correct Settlement & Risk/Concentration Endpoint"
status: draft
created: 2026-06-14
updated: 2026-06-14
---

# Portfolixir PRD — FX-Correct Settlement & Risk/Concentration Endpoint

## Vision & Goals

### Context

Portfolixir is consumed **exclusively by an autonomous portfolio agent ("Jordan")
via MCP** as its sole source-of-truth. The user of this product is therefore a
*deciding agent*, not a human browsing a UI — so quality is measured by the
**correctness of the decisions the data enables**, not by engagement or UX.

### Problem

Today Jordan can describe the portfolio but cannot trust its own numbers. Three
failure modes make it *confidently wrong*:

1. **Phantom P&L.** A foreign-currency position's per-position P&L is wrong by the
   FX spread — `avg_cost` is stored in the cash account's currency (EUR) but
   compared against the security's native price (USD). Live case: a position showed
   **+15.4% on day one with zero real movement**. Jordan could report a holding as
   "in profit" and trigger a sell/hold on a lie. (Known invariant gap **#343**:
   currency mismatch between transaction and account is not validated.)
2. **Fake cash.** The cash quote lumps a negative-balance (Lombard/overdraft)
   account together with savings and reserves, reporting ~5% "healthy" liquidity
   while real deployable depot liquidity is negative. Jordan could green-light a
   purchase that is not actually funded.
3. **Invisible concentration.** Valuation gives weights but no risk lens.
   Single-name and asset-class concentration grow unseen (e.g. EM ~8% via a single
   59k ETF) until they hurt.

### Vision

After this slice, Jordan shifts from *"describes the portfolio"* to *"makes a
covered, FX-honest, risk-aware call it can stand behind."* It speaks a position's
true gain/loss and acts on it; it only recommends deploying cash that really
exists (credit and reserves cleanly separated); it sees cluster/cap breaches
**before** they bite and routes the trim proactively. The core behaviour change:
Jordan stops producing confidently-wrong numbers, so Andi no longer has to
re-check the basics behind a call.

### Goals (decision-correctness)

- **G1 — FX-honest per-position P&L.** Every per-position P&L reflects the
  security's own currency with a stored settlement FX; phantom P&L is eliminated.
- **G2 — Truthful liquidity.** Negative/credit balances are classified out of the
  liquidity/cash quote; reported deployable cash equals real settlement balance.
- **G3 — Risk lens in one call.** Single-name concentration (Top-N + HHI) and
  asset-class cap violations are surfaced in a single MCP call.

### Success Metrics (observable after ~2 weeks of use)

- **SM1 — Phantom P&L = 0.** No position whose reported per-position P&L deviates
  more than **0.5pp** from the FX-adjusted true P&L. (Hard pass/fail; today the
  SpaceX-type position fails this.)
- **SM2 — Cash truth.** Negative-balance accounts no longer appear in the
  liquidity/cash quote; reported deployable depot cash equals the real settlement
  balance. Observable: today's ~5.33% cash artefact disappears.
- **SM3 — Settlement coverage (leading indicator).** 100% of FX-settled trades
  booked in the security's currency with a stored settlement FX (today: 0%).
- **SM4 — Risk endpoint pays off.** ≥1 previously-invisible concentration/cap
  breach is surfaced **and** turned into a concrete trim recommendation
  (e.g. the EM 59k cluster or a single name over threshold).
- **SM5 — Decision confidence.** Share of Jordan's buy/trim calls where Andi must
  re-check "is the cash / the P&L even right?" trends toward 0.

### Counter-Metrics (must not regress)

- **CM1 — No hidden liquidity.** Real, available cash must not be mis-classified as
  credit; chasing SM2 must not understate deployable liquidity.
- **CM2 — Valuation stability.** Existing EUR-hub base-currency valuation totals
  for same-currency positions stay unchanged; the FX fix is surgical and preserves
  the EUR-hub triangulation (ADR-0007).
- **CM3 — Actionable flags only.** Concentration/cap flags stay actionable — a flag
  means a real threshold breach, not noise; no alert spam.

## Features & Requirements

> _In progress — drafted next in the coaching session._
