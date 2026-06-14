# Addendum — Portfolixir PRD (FX-Correct Settlement & Risk/Concentration)

User-contributed depth captured during discovery that belongs to *future* scope or
downstream documents — kept out of the current MVP PRD on purpose so the first
slice (FR-B Phase 1 + FR-D Slice A) stays small and data-source-independent.

## Resolved during discovery

- **[OPEN-B] ETF detection (FR10) — RESOLVED.** Andi already models ETF as its own
  **asset class**. FR10 therefore exempts ETFs from the single-name threshold by
  reusing the existing asset-class signal — no new per-security field, no extra
  maintenance.
- **[OPEN-A] Theme/category drift — DEFERRED.** Risk endpoint MVP warns on
  single-name concentration + HHI + asset-class caps only. Theme/plan-drift moves to
  FR-C (allocation steering).

## Future ideas parked (all share one blocker: an external data source, free only)

Andi's recurring observation: every item below fails on the same question — "where
does the data come from?" — and there is a hard constraint of **no paid providers**.
Recommendation: run ONE small data-source feasibility spike ("which free source is
good enough — justETF.com or similar?") and hang all of these behind it.

1. **Automatic Region & Sector classification.** Especially for ETFs, which must be
   split **percentage-wise** across multiple region/sector classes (look-through).
   Portfolio Performance supports this but only manually, with high upkeep.
   Candidate free-ish source: justETF.com (feasibility/ToS unknown). Stocks need a
   source too.
2. **Region = market exposure, not HQ.** Region risk should reflect the markets a
   company operates in, not where it is headquartered. Example: Apple is not pure
   "US risk" — it carries China, Europe, Africa, Australia exposure. (Revenue-based
   geographic exposure — a richer model than single-country tagging.)
3. **Risk-overlap / correlation matrix.** A view of how positions overlap in risk —
   which holdings share similar exposures vs. which are truly diversifying. Data
   source TBD (look-through holdings and/or correlation data). Sits beyond FR-D
   Slice B (drawdown/volatility).

## Cross-cutting strategic note

FR-A (forward-event calendar), FR-C (region/sector auto-tagging), and the
overlap-matrix idea above are **all** gated by the same missing free external data
source. They should not be scoped or committed until the data-source spike confirms
a viable free, permitted, reliable source. The current MVP deliberately needs none.
