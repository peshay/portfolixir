---
layout: docs
title: "ADR-0028: corporate actions as ledger events — splits as a first-class kind"
description: Decision that corporate actions enter the ledger as first-class transaction kinds, starting with a split kind (ratio + effective date) whose projection scales positions multiplicatively, with quote-history continuity provided by append-only adjustment factors derived at read time — raw quotes are never mutated.
---

# ADR-0028: corporate actions as ledger events — splits as a first-class kind

- **Status:** Proposed (owner sign-off pending; per the [ADR-0026](0026-epic-batch-workflow.html)
  decision gate, no E17 implementation story starts before sign-off)
- **Date:** 2026-07-19

## Context

A stock split silently distorts every chart and holdings figure, and no
existing booking can compensate for it (E17, FR-23 sharpened, #338): the
delivery-pair workaround removes cost at the running average and re-adds
shares at zero cost, flags both legs as **external flows** (breaking TTWROR
continuity, [ADR-0019](0019-view-scoped-performance-boundary-flows.html)),
and leaves no machine-readable record that a split happened — so the quote
chart cannot be adjusted either. Corporate actions are **ledger events first,
wizard second**: the daily operator is an MCP agent that cannot reach a UI
wizard, and the event representation *is* projection semantics.

Constraints that bind this decision:

- Every read model folds `Ledger.Projection.effects/1`
  ([ADR-0011](0011-unified-ledger-projection.html)); an untaught kind raises
  (AR-7 no-catch-all), and migrations are immutable — a new kind means a new
  migration adding the enum value and check constraint, never an edit to an
  old one.
- Stored quote history is auditable input data (NFR-2): it is never mutated.
- Portfolio Performance CSV/JSON v1 has **no split transaction kind**, so the
  PP round-trip (FR-5/FR-29) needs an explicit mapping.
- Rounding follows [ADR-0016](0016-rounding-policy.html): full `Decimal`
  precision in compute, round only at boundaries.

### Prior art: how Portfolio Performance handles splits (verified 2026-07-19)

PP's split wizard (`StockSplitWizard`/`StockSplitModel.applyChanges()`) is a
**one-time destructive rewrite**, not an event mechanism: it multiplies the
share count of every stored transaction before the ex-date in place and
divides every stored quote before the ex-date in place (both default-on
checkboxes). The `STOCK_SPLIT` `SecurityEvent` it also records is purely
cosmetic — it draws a chart marker and is read by no calculation; deleting it
does not undo the rewrite. PP's own manual calls the operation "destructive…
not easily undone", warns that past transactions "will no longer accurately
reflect the actual transactions as documented in your paper files", and
documents a sell/buy-back workaround for users who want history kept intact.

PP can afford this because it makes no auditability promise and it keeps the
local series consistent with back-adjusted provider feeds (Yahoo delivers
split-adjusted history), with zero split-awareness anywhere else in its code.
Portfolixir cannot: NFR-2 requires every number to be reproducible from
immutable inputs, and stored transactions must keep matching broker records.
PP's model is therefore recorded here as the considered-and-rejected prior
art, and its known failure mode — double adjustment when the provider history
is already split-adjusted (portfolio-performance/portfolio#4223) — motivates
the provider-history caveat in the Consequences below.

Sources: `StockSplitModel.java` and `SecurityEvent.java` in
`portfolio-performance/portfolio`; help.portfolio-performance.info,
"Recording a stock split".

## Decision

### 1. A split is a first-class transaction kind, not a composed booking

A new ledger kind `split` records: the security, the effective date, and the
ratio as a pair of **positive integers** (`10:1` forward, `1:10` reverse) —
an integer pair keeps a `1:3` reverse split exact where a decimal ratio
cannot. It carries no cash leg, no price, no depot: a split is a
security-level fact that applies to every depot holding the security.

Its projection is one new `effects/1` clause introducing a **multiplicative
quantity leg** — conceptually
`quantities: [{:scale, security_id, ratio}], external: false` — following the
precedent of the non-additive `{:set, absolute}` cash leg from
[ADR-0009](0009-cash-as-balance-snapshots.html). Generic folds apply it by
scaling every position in that security; `external: false` because nothing
enters or leaves the portfolio, so TTWROR needs no flow neutralisation.
Within its day the split applies **first** (start-of-day, via
`intra_day_order/1`), so same-day trades are booked in post-split units,
matching broker statements.

Composed existing kinds (an outbound/inbound delivery pair) are **rejected**:
wrong cost basis (removal at running average, re-entry at zero), wrong
external-flow classification, no ratio on record for quote adjustment, and
two bookings where the domain has one event.

**PP round-trip mapping:** the native Portfolixir backup/export (FR-29)
carries `split` as a documented Portfolixir extension kind. The
**PP-compatible** CSV/JSON export degrades a split to the conventional PP
idiom — an outbound/inbound delivery pair on the effective date — tagged with
a stable marker in the notes field; the Portfolixir importer recognises that
marker and reconstitutes the first-class split (idempotent via the existing
content hash), so Portfolixir → PP → Portfolixir round-trips losslessly while
plain PP still imports a quantity-correct history.

### 2. Quote continuity via append-only adjustment factors, derived at read time

The split event never mutates stored quotes. But stored histories come in
**two bases**, and the adjustment engine must know which one it is looking
at — this is the trap Portfolio Performance fell into from the other side
(double adjustment, portfolio-performance/portfolio#4223):

- **Provider-synced rows** (`source` = sync): `QuoteSync.Yahoo` refetches the
  *full* history (`period1=0`) every cycle and `Quotes.upsert_many/2`
  overwrites existing closes, so these rows always mirror the provider's
  **current, back-adjusted** basis. After a real-world split the stored
  series becomes split-adjusted on the next sync, automatically. These rows
  are a *provider mirror*, not an immutable raw record — display applies
  **no** additional factor (the series is already continuous), and applying
  one would double-adjust.
- **Manual and import-sourced rows** (`source` = manual/import, never
  overwritten by a sync): raw as-traded prices, the auditable immutable
  input of NFR-2. For dates before an effective date, the displayed close is
  the raw close divided by the cumulative ratio of all later splits.

The per-row basis is derived from the existing `source` column — nothing new
is persisted; the factors remain a pure function of
`(quotes incl. source, split events)`, living in a pure adjustment engine in
the Catalog context (engines compute, the shell reads — AR-2). The security
chart **and** its chart-as-table show the series with the basis stated
("split-adjusted" / "provider-adjusted"; UX-DR10/11); stored values stay
reachable.

**Valuation** must use one consistent basis per date. For raw rows,
pre-split quantity × raw pre-split quote is correct as stored. For
provider-adjusted rows, pre-split dates value as
(quantity × cumulative later split ratio) × adjusted quote — the same fold,
applied to the quantity side. This is not optional polish: today, a split on
a synced security silently skews the historical valuation series (the
provider divides the stored quotes while booked quantities stay pre-split),
so booking the split event is what *repairs* history for synced securities.
With the basis handled per row, the daily valuation series and TTWROR are
continuous across the effective date by construction.

**Misclassification guard:** the booking preview (wizard UI and the MCP
tool's preview output) renders the stored closes around the effective date;
a visible jump indicates a raw basis, a continuous series an adjusted one.
If that contradicts the per-row `source` classification, the preview warns
instead of silently adjusting — no PP-style silent double adjustment.

### 3. Cost basis: quantity multiplies, total cost is invariant

In the moving-average cost fold, a split scales the lot's quantity by the
ratio and leaves the lot's total cost basis **unchanged**; the per-share
average cost divides accordingly. All arithmetic is exact `Decimal` at full
precision; where the division is inexact, [ADR-0016](0016-rounding-policy.html)
applies — no intermediate rounding, quantize only at the persistence or
display boundary. The FIFO trade matcher continues to consider only priced
`buy`/`sell` kinds; a split scales open FIFO lot quantities the same way.

### 4. Scope: splits only in this slice

This ADR decides **splits (and reverse splits) only**. Named follow-on
slices, each requiring its own ADR amendment before implementation:

- **Rename/ISIN change** — decided in the upcoming FR-34 ADR (E18, stable
  external identities and alias matching), cross-referenced here but
  explicitly **not** decided in this record.
- **Merger/spin-off** — exchange ratio plus optional cash compensation; a
  future amendment decides whether the delivery-pair idiom suffices there or
  a further first-class kind is warranted.

### 5. Binding acceptance criteria for the event layer

- Splits book **and** read identically through the JSON API and MCP (AR-11);
  MCP schemas expose the ratio integers and all financials as strings.
- Every split write is journaled ([ADR-0017](0017-append-only-audit-journal.html)).
- Projection/ledger changes land as **dedicated small risk-tier PRs** with
  real human review (AGENTS.md risk-tier exception), not inside an epic batch.
- The PP round-trip behavior of §1 is documented and covered by tests
  (export → re-import reconstitutes the split; content-hash idempotency).
- A TTWROR-continuity test replays a synthetic 10:1 split: quantity ×10,
  total cost basis unchanged, per-share cost /10, no jump in the daily
  series on the effective date — exact `Decimal` expectations.

## Consequences

- Positive: one auditable event per split, reproducible holdings and charts
  from immutable inputs (NFR-2 holds trivially — nothing stored beyond the
  event); the ratio on record is exactly what the later wizard UI and the
  merger/spin-off slices build on.
- Negative / accepted: the effect type grows a second non-additive leg shape,
  and every generic fold must handle scaling — mitigated by AR-7's
  no-catch-all gate failing loudly in every read model at once. Plain PP
  consumers of the compatible export see a delivery pair, not a split; that
  degradation is documented.
- A reverse split can leave fractional share remainders; they remain as
  fractional quantities (volume scale 6), and any cash-in-lieu is booked by
  the operator as a separate regular transaction — no hidden automation.
- Back-adjusted provider history is handled by the per-row basis policy of
  §2 (sync rows = provider basis, no extra factor; manual/import rows = raw,
  factor applies), guarded by the booking-preview warning. Residual risk:
  a sync that stops running right after a real-world split leaves the mirror
  on a stale basis until the next successful sync; `updated_at`/`source` on
  the rows make that state diagnosable.
- NFR-2 nuance made explicit: immutable-input auditability applies to
  manual/import quote rows and to the ledger itself; provider-synced rows
  are a refreshable mirror of an external source and are overwritten by
  design (existing `QuoteSync` behavior, unchanged by this ADR).

## References

- [ADR-0009](0009-cash-as-balance-snapshots.html) — precedent for a non-additive projection leg
- [ADR-0011](0011-unified-ledger-projection.html) — single per-kind reducer this extends
- [ADR-0016](0016-rounding-policy.html) — rounding policy for the inexact per-share division
- [ADR-0017](0017-append-only-audit-journal.html) — journaled financial writes
- [ADR-0019](0019-view-scoped-performance-boundary-flows.html) — why delivery pairs distort TTWROR
- [ADR-0026](0026-epic-batch-workflow.html) — decision-gate workflow this ADR follows
- FR-23 / #338 — corporate actions; FR-5/FR-29 — PP round-trip; FR-34 — E18 identity ADR (rename/ISIN slice)
- Epic tracking: E17 in `_bmad-output/planning-artifacts/epics.md`
