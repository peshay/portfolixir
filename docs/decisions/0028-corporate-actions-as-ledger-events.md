---
layout: docs
title: "ADR-0028: corporate actions as ledger events — splits as a first-class kind"
description: Decision that corporate actions enter the ledger as first-class transaction kinds, starting with a split kind (ratio + effective date) whose projection scales positions multiplicatively, with quote-history continuity provided by append-only adjustment factors derived at read time — raw quotes are never mutated.
---

# ADR-0028: corporate actions as ledger events — splits as a first-class kind

- **Status:** Accepted (owner sign-off 2026-07-19, after the three-method
  adversarial review round; [ADR-0026](0026-epic-batch-workflow.html)
  decision gate passed — E17 implementation stories may start)
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

**Why the PP-style rewrite is disqualified here** (not merely dispreferred):

1. **It breaks import idempotency.** The content hash that makes imports
   idempotent (FR-6) covers quantity and price. Rewriting stored
   transaction quantities detaches the ledger from the original PP export,
   so the FR-29 restore path ("restore = re-import") and any later
   re-import (FR-34) would see mismatching hashes and duplicate or skew the
   very history the rewrite touched. PP has no such idempotent-import
   contract to break; Portfolixir does.
2. **It contradicts the audit journal.** FR-28/NFR-2 promise that stored
   transactions keep matching broker records; a mass before/after rewrite
   of history is precisely what the journal exists to prevent.
3. **Rewriting quotes is futile here.** `QuoteSync` re-mirrors the full
   provider history every cycle and overwrites stored closes — a one-time
   local rewrite of synced quotes would simply be overwritten again. (PP is
   not exposed to this because its quote updates never replace existing
   dates.) Only manual rows outside the provider's range would keep a
   rewrite today — the sync currently replaces even manual rows inside
   that range, the very defect §2 requires fixing first — and for rows
   that do keep it, the display-time factor produces the same picture
   without destroying the original data.

The event approach is also strictly **reversible**: deleting a mistakenly
booked split (the whole per-portfolio group of §1) restores every chart and
figure, because nothing was ever mutated — the failure mode PP's forum is
full of (wrong ratio entered, no way back) cannot occur.

## Decision

### 1. A split is a first-class transaction kind, not a composed booking

A new ledger kind `split` records: the security, the effective date, and the
ratio as a pair of **positive integers** (`10:1` forward, `1:10` reverse) —
an integer pair keeps a `1:3` reverse split exact where a decimal ratio
cannot. The pair is **normalized to lowest terms at write time**; marker
encoding, import dedup identity, and event equality all use the normalized
pair. It carries no cash leg and no price.

To the operator a split is a security-level fact, but it is **booked as one
row per portfolio** holding a non-zero position in the security at the
effective date — the schema's required `portfolio_id` stays. The booking
shell (API, MCP tool, wizard) fans the single "split security X at ratio R"
request out atomically in one `Ecto.Multi`, one journal entry per row, under
a shared group identity, so the operator still books the split once. A
portfolio with zero position gets no row (and needs none); booking against a
security with no position anywhere is rejected in preview. Scale semantics
are scoped to the row's portfolio: in any fold, a split row scales only the
`{account, security}` positions belonging to its own portfolio — the global
one-pass fold (`positions_by_security`) stays single-application per account
even with N portfolio rows, and portfolio-scoped folds each see exactly
their own row.

Its projection is one new `effects/1` clause introducing a **multiplicative
quantity leg** — conceptually
`quantities: [{:scale, %{security_id: id, ratio: {p, q}}}], external: false`
— following the precedent of the non-additive `{:set, absolute}` cash leg
from [ADR-0009](0009-cash-as-balance-snapshots.html). The leg MUST be a
tagged, structurally distinct shape — never a 3-tuple: the additive quantity
leg is the 3-tuple `{account_id, security_id, delta}`, and scope filters
such as `qty_leg_in_scope?` silently drop same-arity tuples they do not
recognise (a verified failure mode); a distinct shape makes an untaught fold
fail loudly instead. Folds expand the leg to per-account scaling from each
account's own pre-split state within the row's portfolio;
`external: false` because nothing enters or leaves the portfolio, so TTWROR
needs no flow neutralisation. Within its day the split applies **first**
(start-of-day), so same-day trades are booked in post-split units, matching
broker statements — §3 makes this ordering load-bearing and names the shared
sort helper every quantity fold must adopt.

**Write idempotency:** a retried timeout must not compound a multiplicative
event, so a partial unique index on `(portfolio_id, security_id, date)
where type = split` backs the write; a second same-day split for the same
security and portfolio is rejected, and the API/MCP error names the
existing event.

Composed existing kinds (an outbound/inbound delivery pair) are **rejected**:
wrong cost basis (removal at running average, re-entry at zero), wrong
external-flow classification, no ratio on record for quote adjustment, and
two bookings where the domain has one event.

**PP round-trip mapping:** the native Portfolixir backup/export (FR-29)
carries `split` as a documented Portfolixir extension kind. The
**PP-compatible** CSV/JSON export degrades a split to the conventional PP
idiom — an outbound/inbound delivery pair on the effective date — tagged with
a stable marker in the notes field; the Portfolixir importer recognises that
marker and reconstitutes the first-class split, so Portfolixir → PP →
Portfolixir round-trips losslessly while plain PP still imports a
quantity-correct history. Hardening, all binding: the marker encodes the
**normalized ratio explicitly** — never inferred from the pair's
quantities; an orphaned marker leg, or one whose quantities contradict the
encoded ratio, **fails the import preview with a warning** (the
plain-delivery fallback is taken only by explicit user choice); marker
pairs across N depots/portfolios sharing one group identity reconstitute
exactly **one split row per portfolio**; and the import dedup identity for
split rows is `(portfolio, security, date, normalized ratio)`, so importing
a file whose split already exists is a no-op.

Because a first-time PP import may carry history already destructively
rewritten by PP's own split wizard (see Prior art), the split booking
preview also shows the booked quantity immediately before and after the
effective date plus the resulting current position, and warns when the
effective date predates the imported history's earliest transaction — the
quantities may already be post-split.

> **Note 2026-07-22 (FR-29 rescope, owner decision, #354):** the
> PP-compatible export was dropped entirely — Portfolixir is a one-way
> import destination; backup/restore is a documented `pg_dump`. The
> export-side marker degradation and the import-side marker reconstitution
> above therefore have no producer and are **dropped from the E17.2 scope**
> (they remain recorded here as the spec should a PP-compatible export ever
> return). The PP-rewritten-history preview behavior in the previous
> paragraph is unaffected and stays binding.

### 2. Quote continuity via append-only adjustment factors, derived at read time

The split event never mutates stored quotes. But stored histories come in
**two bases**, and the adjustment engine must know which one it is looking
at — this is the trap Portfolio Performance fell into from the other side
(double adjustment, portfolio-performance/portfolio#4223):

- **Provider-synced rows** (`source` in `coingecko`/`portfolio_performance`
  — both labels are served by the same `QuoteSync.Yahoo` adapter today, the
  label only selects the symbol format): the sync refetches the *full*
  history (`period1=0`) every cycle and `Quotes.upsert_many/2` overwrites
  existing closes, so these rows always mirror the provider's **current,
  back-adjusted** basis. After a real-world split the stored series becomes
  split-adjusted on the next sync, automatically. These rows are a
  *provider mirror*, not an immutable raw record — display applies **no**
  additional factor (the series is already continuous), and applying one
  would double-adjust.
- **Manual rows** (`source` = `manual`): raw as-traded prices, the
  auditable immutable input of NFR-2. For dates strictly before an
  effective date, the displayed close is the raw close divided by the
  cumulative ratio of all later splits; a quote dated **on** the effective
  date is post-split basis — "later splits" means strictly later dates.
  (PP CSV/JSON v1 imports carry no quote history, so today manual entry is
  the only raw source; the gated XML import (FR-5) would add an
  import-sourced raw class under the same rule.)

**Required precondition — manual rows do not survive a sync today.** The
premise that manual rows are sync-immune is false in the current code:
`Quotes.upsert_many/2` replaces close **and** source on conflict, and the
sync pushes the full provider history every cycle, so a manual row inside
the provider's date range is silently overwritten. The sync upsert must be
changed to **skip rows whose stored source is `manual`** (manual rows win),
with a data-quality notice surfaced when a sync skipped manual rows; until
that behavior change lands, §2 must not be implemented. The
manual-inside-provider-range overlap case joins the §5 test matrix.

Basis mapping is **total and enforced**: every value of `Quote.sources`
(including the legacy `auto`, which no code writes today and which maps to
the provider-mirror basis) has an explicit basis in the adjustment engine —
no catch-all clause, in the spirit of AR-7, so adding a quote source or a
new `QuoteSync` adapter without declaring its basis (adjusted mirror vs.
raw) fails tests instead of guessing. Totality covers **every pricing
source the valuation and performance walks merge**, not only
`Quote.sources`: both fall back to raw as-traded transaction prices
(`latest_trade_prices`, and the trade points merged into the pricing
stream), and those fallback prices are **always raw basis** — a fallback
trade price is divided by the cumulative ratio of splits effective after
the trade's date.

The per-row basis is derived from the existing `source` column — nothing new
is persisted; the factors remain a pure function of
`(quotes incl. source, split events)`, living in a pure adjustment engine in
the Catalog context (engines compute, the shell reads — AR-2). The security
chart **and** its chart-as-table show the series with the basis stated
("split-adjusted" / "provider-adjusted"; UX-DR10/11); stored values stay
reachable.

The adjustment engine is **authoritative for every read of stored closes**,
not only the chart pair. The implementation PR must enumerate every call
site that reads or ratios closes — `Quotes.latest`, `at_or_before`,
`performance/2`, the `attach_metrics` day-change/1M/1Y tiles, holdings
market value — and route each through the engine or document why it is
basis-safe. The same obligation applies, named explicitly, to the
[ADR-0027](0027-plan-versions-and-depot-snapshots.html)
`SnapshotComparison` engine: it does not dispatch through
`Projection.effects/1`, so nothing fails loudly there; its frozen-quantity
side must apply split scaling at the effective date (raw basis) / scale
pre-split quantities (adjusted basis), with its own acceptance-criteria
test.

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
instead of silently adjusting — no PP-style silent double adjustment. When
too few quotes exist around the effective date, the preview states
"insufficient quotes to verify basis" instead of implying a clean check.
And as the escape hatch for provider listings that never — or only
belatedly — back-adjust, a **per-security override flag** ("treat this
synced series as raw") forces the raw basis for that security's synced
rows; the preview warning names the flag.

### 3. Cost basis: quantity multiplies, total cost is invariant

In the moving-average cost fold, a split scales the lot's quantity by the
ratio and leaves the lot's total cost basis **unchanged**; the per-share
average cost divides accordingly. All arithmetic is exact `Decimal` at full
precision; where the division is inexact, [ADR-0016](0016-rounding-policy.html)
applies — no intermediate rounding, quantize only at the persistence or
display boundary — with one **narrow, named exception**: the scale leg's
resulting *quantity* is quantized once, deterministically, at volume
scale 6 at the fold, so a subsequent broker-stated sell (e.g. `3.333333`
after `10 × 1:3`) zeroes the position exactly instead of leaving an
undroppable dust row. Prices and cost totals keep full precision to the
usual boundaries.

The FIFO trade matcher continues to consider only priced `buy`/`sell` kinds
for matching; a split scales open FIFO lot quantities the same way, and an
open lot's per-share `buy_price` **divides by the ratio** so the lot's cost
stays invariant (`decorate_open_lot` computes quantity × buy_price).
Matched trades whose buy and sell straddle the effective date compare in
one basis.

**The AR-7 loud-failure gate covers only folds that dispatch through
`Projection.effects/1`.** Two folds do not: the moving-average cost fold
(its `apply_cost_effect` ends in a catch-all) and the FIFO `TradeMatcher`
(its `_ -> acc` catch-all) — both are named **mandatory change sites**,
each with its own post-split partial-sell test, plus an invariant test that
enumerates `Transaction.kinds/0` and asserts every kind is either
explicitly handled or explicitly listed as cost-neutral in the cost fold.

**Intra-day ordering is load-bearing:** multiplicative legs do not commute
with additive ones, so the split's before-all-same-day-trades ordering
(§1) is enforced through a shared sort helper —
`{date, intra_day_order, id}` — that **every** quantity-fold consumer
adopts. Today only the cash fold (`cash_balances`) and the performance
walk's within-day sort apply `intra_day_order/1`; the quantity folds order
by `{date, id}` alone (verified). Acceptance criterion: a same-day buy plus
split yields identical results across positions, holdings, FIFO, and the
performance walk.

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
  (export → re-import reconstitutes the split; split rows dedup on the §1
  identity `(portfolio, security, date, normalized ratio)`, content-hash
  idempotency for all other rows). *Dropped 2026-07-22 with the FR-29
  rescope — see the §1 note; no PP-compatible export exists to round-trip.*
- A TTWROR-continuity test replays a synthetic 10:1 split: quantity ×10,
  total cost basis unchanged, per-share cost /10, no jump in the daily
  series on the effective date — exact `Decimal` expectations.
- A deterministic quote-basis test matrix covers: raw-only series,
  provider-adjusted series, a mixed series (manual rows outside **and
  inside** the provider's range plus synced rows — the inside case
  exercising the §2 sync-skip precondition), sequential splits, and a
  reverse split — each asserting chart continuity **and** valuation
  correctness with exact `Decimal` expectations, plus the no-catch-all
  basis-mapping invariant test and a delete-the-event test proving full
  restoration, extended to the §1 per-portfolio fan-out (deleting the
  group removes all rows).
- Review-driven additions (details in the referenced sections): the §3
  same-day ordering cross-model equality test; the §2 `SnapshotComparison`
  split test on both bases; the §2 close-reading call-site sweep,
  enumerated in the implementation PR with each site routed through the
  engine or documented basis-safe; the §2 manual-overlap sync-skip test;
  the §2 trade-price-fallback era test; the §1 unique-index rejection
  test; the §1 import-of-existing-split no-op test; the §1 orphan-marker
  preview-warning test; a future-dated effective date rejected (or
  hard-warned) in preview; and the §3 kinds-enumeration cost-fold
  invariant test.

## Consequences

- Positive: one auditable event per split, reproducible holdings and charts
  from immutable inputs (NFR-2 holds trivially — nothing stored beyond the
  event); the ratio on record is exactly what the later wizard UI and the
  merger/spin-off slices build on.
- Negative / accepted: the effect type grows a second non-additive leg shape,
  and every generic fold must handle scaling — mitigated by AR-7's
  no-catch-all gate failing loudly in every fold that dispatches through
  `Projection.effects/1`; the sites outside that dispatch
  (`apply_cost_effect`, `TradeMatcher`, `SnapshotComparison`) are named
  mandatory change sites in §2/§3, not covered by the gate. Plain PP
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
  manual/import quote rows and to the ledger itself — noting that manual
  rows become truly immutable only once the §2 sync-skip precondition
  lands (today the sync overwrites them); provider-synced rows are a
  refreshable mirror of an external source and remain overwritten by
  design.
- This ADR was hardened by a three-method adversarial review
  (red-team/blue-team, pre-mortem, edge-case walk) on 2026-07-19, with
  every finding code-verified; the review-confirmed gaps are incorporated
  in the sections above.

## References

- [ADR-0009](0009-cash-as-balance-snapshots.html) — precedent for a non-additive projection leg
- [ADR-0011](0011-unified-ledger-projection.html) — single per-kind reducer this extends
- [ADR-0016](0016-rounding-policy.html) — rounding policy for the inexact per-share division
- [ADR-0017](0017-append-only-audit-journal.html) — journaled financial writes
- [ADR-0019](0019-view-scoped-performance-boundary-flows.html) — why delivery pairs distort TTWROR
- [ADR-0026](0026-epic-batch-workflow.html) — decision-gate workflow this ADR follows
- [ADR-0027](0027-plan-versions-and-depot-snapshots.html) — the `SnapshotComparison` engine, a named §2 change site outside `effects/1` dispatch
- FR-23 / #338 — corporate actions; FR-5/FR-29 — PP round-trip; FR-34 — E18 identity ADR (rename/ISIN slice)
- Epic tracking: E17 in `_bmad-output/planning-artifacts/epics.md`
