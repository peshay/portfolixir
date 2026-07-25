---
layout: docs
title: "ADR-0031: recorded tax-statement snapshots — capture the broker's tax pots, never derive them"
description: Decision to record German capital-gains tax pot balances (Verlustverrechnungstöpfe, Freistellungsauftrag, Quellensteuertopf, withheld taxes) as manually entered per-institution, per-tax-year, as-of snapshots in a new Portfolixir.Tax context, validated at read time against the statutory §32d EStG withholding formula as an advisory consistency check, with any forward projection deferred to a separate, explicitly-labelled-as-estimate slice.
---

# ADR-0031: recorded tax-statement snapshots — capture the broker's tax pots, never derive them

- **Status:** Proposed (decision gate per
  [ADR-0026](0026-epic-batch-workflow.html); owner sign-off pending)
- **Date:** 2026-07-25

## Context

The maintainer's recurring question when sizing a trim is: *how much realised
equity gain is still free of Kapitalertragsteuer this year?* In the German
retail-tax model that number is

```text
tax-free trim budget = unused equity loss pot + remaining Freistellungsauftrag
```

Both terms live on the broker's tax statement (the
`Verlustverrechnungstöpfe` / `Freistellungsauftrag` block of a comdirect-style
`Steuerreport` or `Erträgnisaufstellung`). Today they are re-read out of PDFs by
hand whenever the question comes up, and they are invisible to the allocation
and drift surfaces where the trim decision is actually made.

The obvious move — derive the loss pots from the ledger Portfolixir already has
— is **structurally impossible**, and that is the force behind this ADR.

### Why Portfolixir cannot derive the tax pots

**1. Cost-basis method mismatch (the disqualifier).** Portfolixir folds cost
basis as a **running average** (`Ledger.Projection` / `Ledger.TradeMatcher`;
[ADR-0011](0011-unified-ledger-projection.html),
[ADR-0004](0004-holdings-derived-from-transactions.html)). German capital-gains
taxation mandates strict **FIFO** per depot. For any position built in several
tranches and then partially sold, the average-cost gain and the FIFO taxable
gain diverge — not by rounding, but systematically and in an amount that depends
on the whole tranche history. A derived loss pot would therefore be *wrong*, and
wrong in a way nothing in the UI would reveal. An invisible wrong number is
worse than an absent one.

**2. Four inputs are simply not in the transaction data.** Even with FIFO lot
tracking, the pots would still not reconstruct, because these facts never enter
the ledger:

- **Teilfreistellung** — the 0 / 15 / 30 / 60 % partial exemption by fund type.
  It is a property of the fund's asset ratio, visible only because the broker
  prints it on the settlement.
- **Vorabpauschale** — the annual advance lump sum on accumulating funds, which
  is taxed in-year and later raises the basis at sale.
- **Freistellungsauftrag consumption** — allowance is consumed chronologically
  across *all* investment income at that institution, in the order the broker
  settled it.
- **Loss carry-forward from prior years** — certified balances that exist
  *before* the first transaction Portfolixir has ever seen.

**3. The pot is per institution, not per depot.** The pots are maintained by the
bank for a taxpayer at that bank. Portfolixir models depots and cash accounts,
not tax-reporting institutions, so there is no existing entity the derived
number could even hang off.

The repository already has the right precedent for exactly this situation:
[ADR-0009](0009-cash-as-balance-snapshots.html) records cash as a stated balance
rather than mirroring a second ledger, and
[ADR-0027](0027-plan-versions-and-depot-snapshots.html) records depot snapshots
as named markers. Both accept "recorded, dated, honest" over "computed,
plausible, subtly wrong".

## Decision

**Record the broker's tax-statement block verbatim as a dated snapshot. Compute
nothing that the statement does not state. Validate what was recorded against
the statutory withholding formula and surface disagreement as an advisory.**

### 1. New bounded context `Portfolixir.Tax`

Tax-jurisdiction rules are their own concern. They are not portfolio structure
(`Portfolios`), not instrument master data (`Catalog`), and emphatically not
ledger projection (`Ledger`) — the entire point of this ADR is that these rows
are *not* ledger entries and must never be reduced as if they were.

```text
Portfolixir.Tax                     # recorded tax-statement snapshots + consistency checks
Portfolixir.Tax.StatementSnapshot   # the schema
Portfolixir.Tax.Consistency         # pure engine, no Repo/clock (AR-2)
```

On acceptance this adds one line to the **Active Architecture** block in
`AGENTS.md`; that amendment rides in the first implementation PR, not before.

**Naming note:** the concept was drafted as `tax_ledger_snapshots`. It is
renamed to **`tax_statement_snapshots`** deliberately: `Ledger` is a bounded
context in this codebase, and reusing the word invites precisely the reading
this ADR forbids — that these rows are bookable, reducible ledger events. They
are transcriptions of an external document.

### 2. Schema — `tax_statement_snapshots`

Identity and provenance:

| Column | Type | Notes |
| --- | --- | --- |
| `institution` | `:string`, NOT NULL | The tax-reporting entity as printed on the statement. Free text, trimmed, non-empty. |
| `holder` | `:string`, NOT NULL | The taxpayer the statement is issued to. Free text (a placeholder label is fine); each taxpayer has their own Freistellungsauftrag. |
| `tax_year` | `:integer`, NOT NULL | CHECK `BETWEEN 1990 AND 2200` (int4 bound discipline, cf. ADR-0028 fix round). |
| `as_of` | `:date`, NOT NULL | The statement's stated position date. Not in the future — validated against a `today` injected by the context shell, never a clock inside the schema (AR-2). |
| `source` | `:string`, NOT NULL, default `"manual"` | `manual` today; `pdf_import` reserved for [ADR-0021](0021-pdf-transaction-intake.html) intake. `validate_inclusion` + DB CHECK. |
| `church_tax_rate` | `:decimal(6,4)`, NOT NULL, default `0` | `k` in the §32d formula below. CHECK `IN (0, 0.08, 0.09)`. |
| `note` | `:text`, nullable | Free-form provenance ("page 4 of the annual report"). |

The **eleven recorded money fields**, each `:decimal, precision: 20, scale: 6,
null: false, default: 0` per the money-column convention
([ADR-0003](0003-decimal-for-money.html)):

| Column | Statement line |
| --- | --- |
| `taxable_income` | Steuerpflichtige Kapitalerträge / Bemessungsgrundlage, before allowance |
| `allowance_granted` | Freistellungsauftrag erteilt |
| `allowance_used` | Freistellungsauftrag verbraucht |
| `loss_pot_equities` | Verlustverrechnungstopf Aktien — unused equity-loss volume |
| `loss_pot_other` | Verlustverrechnungstopf Sonstige — unused other-loss volume |
| `loss_carryforward_prior_years` | Certified Verlustvortrag brought into this tax year |
| `withholding_tax_pot` | Quellensteuertopf — creditable foreign withholding still available |
| `withholding_tax_credited` | Angerechnete ausländische Quellensteuer |
| `capital_gains_tax_withheld` | Abgeführte Kapitalertragsteuer |
| `solidarity_surcharge_withheld` | Solidaritätszuschlag |
| `church_tax_withheld` | Kirchensteuer |

**Uniqueness:** `unique_index(:tax_statement_snapshots, [:institution, :holder,
:tax_year, :as_of])`. All four are NOT NULL, so no `NULLS NOT DISTINCT` trap.
Re-recording the same statement is a conflict, not a silent duplicate; a
corrected re-issue for the same date is an update.

**Sign convention — magnitudes only.** Every money column carries a DB CHECK
`>= 0` and a changeset `validate_number(greater_than_or_equal_to: 0)`. A loss
pot is stored as the **volume of loss available for offsetting**, not as the
negative number the statement prints. This follows the ledger's
positive-magnitude discipline (`Transaction` amount guards) and keeps the
arithmetic in §3 free of sign bookkeeping.

A negative input is **rejected with a message naming the convention** — never
silently flipped. Silent normalisation of a sign on a money field is how a
transcription error becomes a permanently wrong number. The entry form labels
state the direction explicitly, and the display renders the pots with the
statement's sign so the recorded row is visually comparable to the paper.

**Nothing about a real position, security, or transaction is stored here.** The
row is a transcription of an aggregate statement block.

### 3. Consistency checks — the free win

The statement block is internally reconstructable, because withholding follows
the closed formula of **§ 32d Abs. 1 EStG**:

```text
e = taxable_income − allowance_used        (assessment base after allowance)
q = withholding_tax_credited               (creditable foreign withholding)
k = church_tax_rate                        (0, 0.08 or 0.09)

expected KESt = (e − 4q) / (4 + k)
expected Soli = capital_gains_tax_withheld × 0.055
expected KiSt = capital_gains_tax_withheld × k
```

With `k = 0` this collapses to the familiar `e × 25 % − q`. Worked synthetic
example:

```text
taxable_income        12,000.00
allowance_used         1,000.00   →  e = 11,000.00
withholding_credited     200.00   →  q =    200.00
church_tax_rate               0   →  k =         0

expected KESt = (11,000.00 − 800.00) / 4 = 2,550.00
expected Soli =        2,550.00 × 5.5 %  =   140.25
```

`Portfolixir.Tax.Consistency` is a **pure engine** (no Repo, no clock, no
config — AR-2) returning a list of findings for a snapshot:

| Rule | Kind | Statement |
| --- | --- | --- |
| C1 | **hard** (changeset error) | `allowance_used ≤ allowance_granted` — definitional within one institution. |
| C2 | **hard** | `church_tax_rate = 0` ⟹ `church_tax_withheld = 0`. |
| C3 | advisory | recorded `capital_gains_tax_withheld` vs. expected KESt. |
| C4 | advisory | recorded `solidarity_surcharge_withheld` vs. expected Soli. |
| C5 | advisory | recorded `church_tax_withheld` vs. expected KiSt. |
| C6 | advisory | year-to-date monotonicity: for the same `(institution, holder, tax_year)`, a later `as_of` must not report a lower `capital_gains_tax_withheld` or `allowance_used`. Catches "recorded the wrong year's statement". |

**Tolerance band** for the advisory rules: `max(1.00, 0.05 % of expected)` in the
statement currency. Withholding is rounded to cents on every individual
settlement, so a year's worth of settlements legitimately accumulates a
few cents of drift against a single closed-form reconstruction. The band
absorbs that and still catches a transposed digit.

**Advisories never block a save.** Teilfreistellung applied at source, a
mid-year allowance change, and broker-side corrections can all break the simple
identity while the recorded numbers are perfectly correct. The checks are a
transcription-error detector, not a tax authority. A finding states which two
numbers disagree and by how much — it never proposes a "corrected" value.

Findings are computed **at read time** and are not stored
([ADR-0012](0012-asset-class-inference-at-read-time.html) precedent). Write
functions keep the plain `{:ok, struct}` / `{:error, changeset}` contract.

### 4. Derived read model

Two figures are derived from a snapshot, both carrying the snapshot's `as_of`
and its staleness:

```text
allowance_remaining  = allowance_granted − allowance_used
tax_free_trim_budget = loss_pot_equities + allowance_remaining
```

`tax_free_trim_budget` answers the question this feature exists for: the volume
of realised **equity** gain still free of Kapitalertragsteuer at that
institution. Its presentation is bound by two honesty rules:

- it is always stated **with its `as_of` date** and flagged stale once newer
  investment income can have landed (the allowance is consumed chronologically
  by dividends and interest, so the remaining allowance decays without any
  action by the maintainer);
- it is a **decision input, never an instruction**. The
  [ADR-0023](0023-drift-sign-and-display-only-rebalancing-hints.html) boundary
  holds unchanged: nothing here creates, stores, or transmits an order.

Placement next to the allocation drift is a named follow-on slice, not part of
the foundation.

### 5. Write path, API and MCP

Writes follow the established shape exactly — `Actor` as the first positional
argument, `Ecto.Multi` with `Journal.record/3` in the same DB transaction
([ADR-0017](0017-append-only-audit-journal.html), AR-1), and an
`arm_tax_statement_snapshots_journal` migration attaching the
`portfolixir_require_journal_actor` trigger so an unjournaled write fails loudly:

```elixir
Tax.create_statement_snapshot(actor, attrs, opts \\ [])
Tax.update_statement_snapshot(actor, snapshot, attrs, opts \\ [])
Tax.delete_statement_snapshot(actor, snapshot_or_id)
Tax.list_statement_snapshots(opts)      # filter: institution, holder, tax_year
Tax.fetch_statement_snapshot(id)
Tax.latest_statement_snapshot(institution, holder, tax_year)
```

Per **AR-11**, the JSON API gets `/api/v1/tax/statement-snapshots` (list,
create, show, update, delete) behind `ApiAuthPlug`, serialized through the
shared `Api.V1.JSON` presenter with every financial decimal as a
`Decimal.to_string(:normal)` string, and the MCP companion gets matching
`portfolixir.tax_snapshots.{list,create,update,delete}` tools with hand-written
JSON Schema plus parallel zod validators, calling the JSON API only
([ADR-0002](0002-thin-mcp-over-json-api.html)). Consistency findings and the
derived read model ride on the read payloads. The MCP tool description states
the recorded-not-derived nature and the FIFO reason, so an operating LLM does
not attempt to compute the pots from holdings.

### 6. Explicitly deferred — forward projection (Layer B)

Projecting the pots forward from the last snapshot (booked `tax` /`tax_refund`
amounts plus a coarse per-bucket gain estimate) is **not** part of this
decision. It needs a new `tax_bucket` attribute on securities
(`equity` / `other` / `tax_free`) — physically-backed gold via an exchange-traded
commodity belongs in `tax_free` after the twelve-month holding period, which no
heuristic over `asset_class` can infer — and it inherits the FIFO error this ADR
was written to avoid.

If it is ever built, two constraints are binding from here:

- the result is **never labelled as a pot balance**. It reads as an estimate
  with its drift basis stated ("estimated, drift since the snapshot of
  &lt;date&gt;"), never "Verlustverrechnungstopf: X";
- it is a separate ADR with its own decision gate, because it is the point at
  which a computed number re-enters the picture.

### 7. Scope lock

This feature records numbers and checks their internal arithmetic. It does not:

- track tax lots or implement FIFO matching (the reason it exists);
- compute a tax liability, a Teilfreistellung, or a Vorabpauschale;
- produce anything filed with, or transmitted to, any authority or broker;
- constitute tax advice — the recorded statement remains the authority;
- make any network call.

## Consequences

- **Positive.** The number the trim decision hangs on becomes a first-class,
  dated, auditable record instead of a PDF re-read. It is cheap: one table, one
  pure engine, the existing write/API/MCP machinery. Because the block is
  internally reconstructable, every recorded snapshot validates itself on save —
  a transposed digit or a stale statement surfaces immediately, at close to zero
  implementation cost. The `holder` key makes cross-taxpayer allowance
  comparison (two depots, two Freistellungsaufträge) a listing, not a project.
- **Negative / accepted.** This is manually maintained data that goes stale
  silently between statements; `as_of` plus staleness display is the whole
  mitigation, and the maintainer owns re-recording. `institution` and `holder`
  are free text with no referential integrity — deliberate, since Portfolixir
  has no institution entity and inventing one for this is heavier than the
  feature; if one ever lands, these become FKs in a follow-up migration.
  The advisory band cannot detect a statement transcribed *correctly* for the
  wrong period beyond the C6 monotonicity rule.
- **Jurisdiction coupling — the real trade-off.** These are the first columns in
  Portfolixir that encode one country's tax law. That is accepted because the
  alternative (a generic "tax attributes" bag) would be unvalidatable, and the
  §32d reconstruction is exactly what makes the feature worth building. The
  containment rule is that it stays inside `Portfolixir.Tax`: a second
  jurisdiction gets its own table and its own engine, never nullable columns
  bolted onto this one.
- **Delivery.** One epic batch under [ADR-0026](0026-epic-batch-workflow.html):
  the table and context, the consistency engine, API/MCP coverage, the entry
  surface plus EN/DE documentation. It introduces no ledger, projection, or
  import-idempotency change, so it is not a risk-tier exception — but every
  write is journaled and every money column is Decimal, exactly as the money
  domain requires.

## References

- [ADR-0003](0003-decimal-for-money.html) — Decimal for all financial values
- [ADR-0004](0004-holdings-derived-from-transactions.html) / [ADR-0011](0011-unified-ledger-projection.html) — the average-cost projection this cannot reproduce under FIFO
- [ADR-0009](0009-cash-as-balance-snapshots.html) — the recorded-balance precedent
- [ADR-0012](0012-asset-class-inference-at-read-time.html) — derived values computed at read time, not stored
- [ADR-0017](0017-append-only-audit-journal.html) — journaled financial writes
- [ADR-0021](0021-pdf-transaction-intake.html) — the sandboxed PDF intake a later `source: "pdf_import"` would reuse
- [ADR-0023](0023-drift-sign-and-display-only-rebalancing-hints.html) — display-only boundary the trim budget stays inside
- [ADR-0026](0026-epic-batch-workflow.html) — decision gate and batch delivery
- [ADR-0027](0027-plan-versions-and-depot-snapshots.html) — the as-of snapshot precedent
- FR-36 and Epic 19 — `_bmad-output/planning-artifacts/epics.md`
- § 32d Abs. 1 EStG — the closed withholding formula the consistency checks reconstruct
