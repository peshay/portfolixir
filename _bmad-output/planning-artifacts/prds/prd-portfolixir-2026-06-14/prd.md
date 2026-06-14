---
title: "Portfolixir PRD — FX-Correct Settlement & Risk/Concentration Endpoint"
status: final
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

FRs carry globally stable IDs. Every new API endpoint or field ships with a
matching MCP tool/field (ADR-0002); financial values stay Decimal strings
end-to-end.

### Feature 1 — FX-Honest Settlement & Position P&L (FR-B Phase 1, a+b)

- **FR1.** A transaction can be booked **in the security's own currency** with a
  **stored settlement FX rate**. The persisted booking exposes: the
  security-currency amount, the settlement-currency cash amount, and the stored
  settlement FX rate (Decimal strings) — rather than forcing the whole transaction
  into the account's currency. A test can assert all three fields on the stored row.
- **FR2.** Per-position cost basis and P&L are computed **in the security's own
  currency** (moving-average avg-cost in native currency), eliminating phantom P&L
  from the FX spread. The day-one foreign-currency position reads ~0% on zero real
  movement, not +15.4%.
- **FR3.** **Currency-mismatch guard (closes #343).** When a transaction's currency
  differs from its cash account's currency, a settlement FX rate is **required**;
  the system validates the pair instead of silently storing a mismatched avg_cost.
- **FR4.** **FX-availability precondition.** FX-corrected P&L is served only when at
  least one usable FX rate exists for the pair. When none exists, the position is
  marked **unpriceable/unvalued** (explicit flag) — never reported with a wrong
  number. (Reuses existing `valued`/`price_source` flag idiom.)

### Feature 2 — Truthful Liquidity (FR-B Phase 1, c)

- **FR5.** Each cash account carries a **`liquidity_role`** ∈ {`free_cash`,
  `credit_line`, `reserve`}, settable via API/MCP. `free_cash` is the default.
- **FR6.** **Deployable cash** is defined as the sum of the balances of `free_cash`
  accounts whose balance ≥ 0, converted to base currency (EUR) via the EUR hub.
  `credit_line` accounts never count as free liquidity (type beats sign); `reserve`
  accounts are excluded and shown as a labelled overlay. This computation rule is the
  definition; today's ~5.33% cash artefact disappearing is one worked example of it.
- **FR7.** A **drawn credit_line (negative balance)** is treated as a liability that
  reduces net worth. **Unused credit headroom is not liquidity**; it may optionally
  be surfaced separately as "available leverage", explicitly outside the cash quote.

### Feature 3 — Risk & Concentration Endpoint (FR-D Slice A)

- **FR8.** A **single MCP call** returns the portfolio's risk lens over the
  **steerable basis** (excludes positions flagged `excluded_from_allocation_targets`):
  - **Single-name concentration Top-N** — default **N = 10**, overridable per call;
    each entry carries the security, its weight (% of steerable basis as a Decimal
    string), and a severity (`ok` / `warn` / `hard`) per FR10.
  - **HHI** — Herfindahl-Hirschman Index on the steerable single-name weights,
    reported on the **0–10000** scale (sum of squared percentage weights). The call
    returns the raw value plus a band: `low` < 1500, `moderate` 1500–2500,
    `concentrated` > 2500 (bands overridable per call). A `concentrated` HHI counts
    as a surfaced breach for SM4.
- **FR9.** The same call reports **asset-class cap violations**. Caps are
  **configurable per asset class** (no shipped defaults — a cap is opt-in config).
  Each violation record carries: asset class, current weight (%), configured cap (%),
  and overage (current − cap, in percentage points). Only classes over their cap are
  returned.
- **FR10.** Concentration evaluation is **instrument-type-aware** with shipped
  **defaults, overridable per call**: single stock WARN > 7% / HARD > 10%; an ETF is
  held to its own higher default threshold WARN > 25% (no HARD) so a World-core ETF
  at 20% reads as target, not risk. **ETF detection reuses the existing asset-class
  signal** (ETF is already a distinct asset class) — no new per-security field.
- **Out of MVP (explicit):** drawdown/volatility per position/portfolio (needs
  quote-history time-series math) → FR-D Slice B. Category/theme-leaf drift flags
  (> 3pp over target / > 150% of target) overlap allocation steering → **deferred to
  FR-C**. Risk-overlap/correlation matrix and region/sector look-through → future,
  data-source-gated (see `addendum.md`).

## Cross-Cutting NFRs

- **NFR1 — MCP parity (ADR-0002).** Every new endpoint/field above has a matching
  MCP tool or field; the agent reaches all of this via MCP only.
- **NFR2 — Decimal discipline.** All money, quantities, prices and FX rates are
  Decimal, serialized as `:normal` strings end-to-end; no float P&L, no tolerance
  assertions (ADR-0003).
- **NFR3 — FX hub preserved.** FX always triangulates through the EUR hub
  (ADR-0007); settlement rates are stored, never computed as direct cross rates.
- **NFR4 — Determinism.** The risk endpoint is a pure derivation from current
  valuation + classifications — same inputs yield the same output, no hidden state.
- **NFR5 — Auditability.** Bookings are written only through `Ledger`/`Imports`
  public functions; holdings/P&L remain derived, never stored (ADR-0004).

## Glossary

- **Deployable cash** (= *cash quote numerator*, *free liquidity*): the canonical
  figure from FR6 — Σ balances of `free_cash` accounts with balance ≥ 0, in EUR via
  the EUR hub. The terms "deployable depot cash" / "deployable depot liquidity" /
  "real settlement balance" all refer to this single figure; use **deployable cash**.
- **`liquidity_role`**: per-account classification ∈ {`free_cash`, `credit_line`,
  `reserve`} (FR5). `free_cash` = counts toward deployable cash when ≥ 0;
  `credit_line` = Lombard/Dispo/Margin, never free liquidity; `reserve` = earmarked,
  excluded from deployable cash, shown as overlay.
- **Steerable basis**: the position set used for concentration/targets — the whole
  portfolio minus positions flagged `excluded_from_allocation_targets` (e.g. crypto,
  third-party depots).
- **`excluded_from_allocation_targets`**: existing per-security flag keeping a
  position in totals/performance but out of the steerable basis.
- **HHI**: Herfindahl-Hirschman Index over steerable single-name weights, 0–10000
  scale (FR8).
- **Settlement FX rate**: the FX rate stored with a transaction (FR1) linking the
  security currency to the cash account's settlement currency; always triangulated
  through the EUR hub (NFR3).

## Out of Scope (this PRD)

- FX auto-sync scheduler (FR-B Phase 2) — fast-follow.
- Drawdown / volatility (FR-D Slice B).
- FR-A forward-event calendar; FR-C custom-strategy classification & region/sector
  auto-tagging (sequenced after this slice).
