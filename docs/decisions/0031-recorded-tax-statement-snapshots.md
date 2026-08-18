---
layout: docs
title: "ADR-0031: recorded tax-statement snapshots — capture the broker's tax pots, never derive them"
description: Decision to record German capital-gains tax pot balances (Verlustverrechnungstöpfe, Freistellungsauftrag, Quellensteuertopf, withheld taxes) as manually entered per-institution, per-tax-year, as-of snapshots in a new Portfolixir.Tax context, validated at read time against the statutory §32d EStG withholding formula as an advisory consistency check, with statutory rates and allowance ceilings held as year-scoped parameters, the taxpayer's church-tax liability and assessment type as an effective-dated profile, the Freistellungsauftrag configured per institution, and any forward projection deferred to a separate, explicitly-labelled-as-estimate slice.
---

# ADR-0031: recorded tax-statement snapshots — capture the broker's tax pots, never derive them

- **Status:** Accepted (decision gate per
  [ADR-0026](0026-epic-batch-workflow.html); owner sign-off 2026-07-25, issue
  #612)
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

> **Correction (2026-07-29, owner review).** The first version of this section
> called the cost-basis method "the disqualifier" and stated that Portfolixir
> has no FIFO. **That was wrong**, and the error mattered because it made the
> whole decision rest on a premise that does not hold. Portfolixir has carried
> a real FIFO lot matcher (`Ledger.TradeMatcher`) since before this ADR,
> surfaced at `GET /api/v1/securities/:id/trades`. The decision is unchanged —
> the reasons below are sufficient on their own — but its argument is not the
> one originally written down. Point 1 is restated accordingly.

**1. Cost-basis method mismatch (a real gap, not the disqualifier).**
Portfolixir maintains **two** cost models, each for its own question:

- `Ledger.cost_lots/1` folds a **running average** for holdings valuation
  ([ADR-0011](0011-unified-ledger-projection.html),
  [ADR-0004](0004-holdings-derived-from-transactions.html)) — "what did the
  position I hold cost on average?";
- `Ledger.TradeMatcher` matches **FIFO, lot by lot**, including split scaling —
  "which stock did this sale actually consume?".

German capital-gains taxation mandates strict FIFO per depot, so the *taxable*
question is the matcher's, not the average's. Reading the average-cost gain as
a tax figure would be systematically wrong for any position built in tranches
and partly sold.

But that is a **presentation** gap, not a derivation blocker: the FIFO gross
gain per sale is already computed. What the matcher yields is a **gross gain**,
and a gross gain is not a tax pot. Points 2 and 3 are what actually disqualify
derivation, and they hold no matter how exact the lot matching is.

**2. Four inputs are simply not in the transaction data (the disqualifier).**
Even with the exact FIFO lot tracking Portfolixir already has, the pots do not
reconstruct, because these facts never enter the ledger at all:

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
| `church_tax_rate` | `:decimal(6,4)`, NOT NULL, default `0` | `k` in the §32d formula below; `0` means not liable, which is the default. CHECK `>= 0 AND < 1` — a *range*, not a value list, because the rate is not a constant of nature (see §3). Prefilled from the holder's tax profile in force at `as_of`, then frozen on the row. |
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

### 3. Configuration that changes over time — parameters, profile, allowance orders

Tax rates, statutory allowances and a person's own tax situation are **not
constants**. They change by legislation, by where the taxpayer lives, and by
what happens in their life. Two consequences follow, and both are binding.

**Nothing statutory is hardcoded in the engine.** A new table
`tax_parameters`, keyed by `(jurisdiction, tax_year)` and unique on that pair,
carries the numbers the consistency checks need:

| Column | Meaning | German values today |
| --- | --- | --- |
| `jurisdiction` | ISO country code; `"DE"` is the only value today | — |
| `tax_year` | the year the row governs | — |
| `capital_gains_tax_rate` | Kapitalertragsteuer | `0.25` |
| `solidarity_surcharge_rate` | Solidaritätszuschlag on the withheld KESt | `0.055` (unchanged for Abgeltungsteuer by the 2021 partial abolition) |
| `saver_allowance_single` | Sparer-Pauschbetrag, single assessment | `801.00` through 2022, `1000.00` from 2023 |
| `saver_allowance_joint` | Sparer-Pauschbetrag, joint assessment | `1602.00` through 2022, `2000.00` from 2023 |
| `church_tax_rates` | the rates in force, for prefill and an advisory | `{0.08, 0.09}` — 8 % in Bavaria and Baden-Württemberg, 9 % elsewhere |

Rows are **seeded** with the known German history and are editable by the
operator, so a rate change never requires a code release. The allowance history
is not academic: recording a statement for a year before 2023 against a
hardcoded 1.000 € would flag every correct transcription as inconsistent.
`Tax.Consistency` takes the resolved parameter row as an **argument** — it stays
a pure engine with no config lookup inside (AR-2). Rows for a closed tax year
are not edited; a legislative correction is a new row for the affected year.

**The taxpayer's own situation is effective-dated.** A second table
`tax_profiles`, keyed by `(holder, valid_from)`, records what is true of a
person from a date onwards:

| Column | Meaning |
| --- | --- |
| `holder` | the taxpayer label, same key as the snapshot |
| `valid_from` | `:date`, NOT NULL — the row governs from here until the next row's `valid_from` |
| `jurisdiction` | `"DE"` today |
| `church_tax_liable` | `:boolean`, NOT NULL, default `false` — **not liable is the default**; no church tax is the plain, unremarkable case |
| `church_tax_rate` | `:decimal(6,4)`, NOT NULL, default `0`; CHECK `>= 0 AND < 1`, and CHECK `church_tax_liable OR church_tax_rate = 0` |
| `assessment_type` | `single` or `joint` — selects which `saver_allowance_*` ceiling applies |

Effective dating is the point, not decoration: moving between federal states
changes 9 % to 8 %, marrying changes the assessment type and doubles the
allowance ceiling, joining or leaving a church changes liability. Each of those
happens on a date, and **none of them may retroactively rewrite what a past
statement reconstructs to**. A snapshot resolves the profile in force at its
`as_of` and freezes the resulting `church_tax_rate` onto its own row (§2), so
editing a profile later changes future prefills and never a recorded
transcription. This is the same as-of discipline quotes and exchange rates
already follow.

**The Freistellungsauftrag is configured, not only observed.** The statutory
allowance is one budget per taxpayer that they distribute across their banks by
instruction. A third table `allowance_orders`, unique on
`(holder, institution, tax_year)`, records that instruction:

| Column | Meaning |
| --- | --- |
| `holder`, `institution`, `tax_year` | the key |
| `amount_granted` | `:decimal(20,6)`, NOT NULL, CHECK `>= 0` — the amount instructed to that bank |
| `note` | free-form |

This is deliberately a **separate axis** from the snapshot's recorded
`allowance_granted`: the order is what the taxpayer instructed, the snapshot is
what the bank reports it applied. Holding both is what makes the comparison in
§4 possible — a divergence means either the instruction never landed or the
configuration is stale, and either way it is worth knowing before the allowance
is silently missed for a year.

### 4. Consistency checks — the free win

The statement block is internally reconstructable, because withholding follows
the closed formula of **§ 32d Abs. 1 EStG**:

```text
e = taxable_income − allowance_used        (assessment base after allowance)
q = withholding_tax_credited               (creditable foreign withholding)
k = church_tax_rate                        (0 when not liable — the default)
s = solidarity_surcharge_rate              (from tax_parameters for the year)

expected KESt = (e − 4q) / (4 + k)
expected Soli = capital_gains_tax_withheld × s
expected KiSt = capital_gains_tax_withheld × k
```

`k` and `s` are **resolved, never hardcoded**: `k` from the snapshot's own
frozen rate (§2), `s` and the allowance ceilings from the `tax_parameters` row
for `(jurisdiction, tax_year)` (§3). The `4` in the formula is the statute's
own algebra for the 25 % rate, so a future change of the capital-gains rate
means a new formula clause keyed to the year, not an edited constant — the ADR
that changes it is the place to decide that.

With `k = 0` — no church tax, the default case — this collapses to the familiar
`e × 25 % − q`. Worked synthetic example:

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
| C7 | advisory | **instruction vs. reality:** the snapshot's recorded `allowance_granted` matches the `allowance_orders` row for the same `(holder, institution, tax_year)`. A divergence means the instruction never landed at the bank, or the configuration is stale. |
| C8 | advisory | **allowance budget:** `SUM(allowance_orders.amount_granted)` over `(holder, tax_year)` does not exceed the `saver_allowance_single` / `saver_allowance_joint` ceiling for that year, selected by the profile's `assessment_type`. Over-allocating across banks is an error the taxpayer must correct with the banks — the app states it, it does not fix it. Advisory rather than hard, because the recorded set of institutions may be incomplete and a planned redistribution can legitimately overlap for a moment. |

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

### 5. Derived read model

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

Across institutions, the same two figures roll up per `(holder, tax_year)` —
the loss pots summed, and the allowance budget taken from the year's statutory
ceiling for the profile's `assessment_type` minus the consumption the snapshots
report. That roll-up is what makes cross-taxpayer allowance comparison a
listing rather than a project, and it is only correct when a snapshot exists
for every institution: the roll-up therefore always states **which institutions
it covers and as of when**, and is marked incomplete when an `allowance_orders`
row exists for an institution with no snapshot for that year.

Placement next to the allocation drift is a named follow-on slice, not part of
the foundation.

### 6. Write path, API and MCP

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

Tax.list_parameters(opts) / Tax.fetch_parameters(jurisdiction, tax_year)
Tax.upsert_parameters(actor, attrs)

Tax.list_profiles(holder) / Tax.profile_in_force(holder, on_date)
Tax.create_profile(actor, attrs) / Tax.update_profile(actor, profile, attrs)

Tax.list_allowance_orders(opts)
Tax.put_allowance_order(actor, attrs) / Tax.delete_allowance_order(actor, order)
```

`tax_parameters` is **statutory reference data, not financial state** — it is
seeded, jurisdiction-wide, and describes the law rather than the maintainer's
money. It is journaled anyway, because an edit to a rate changes what every
consistency finding for that year says, and an unexplained flip of findings is
exactly the kind of thing the journal exists to make traceable.
`tax_profiles` and `allowance_orders` are the taxpayer's own configuration and
are journaled on the same grounds as any other financial write.

Per **AR-11**, the JSON API gets `/api/v1/tax/statement-snapshots`,
`/api/v1/tax/parameters`, `/api/v1/tax/profiles` and
`/api/v1/tax/allowance-orders` (list, create, show, update, delete) behind
`ApiAuthPlug`, serialized through the
shared `Api.V1.JSON` presenter with every financial decimal as a
`Decimal.to_string(:normal)` string, and the MCP companion gets matching
`portfolixir.tax_snapshots.*`, `portfolixir.tax_parameters.*`,
`portfolixir.tax_profiles.*` and `portfolixir.tax_allowance_orders.*` tools with hand-written
JSON Schema plus parallel zod validators, calling the JSON API only
([ADR-0002](0002-thin-mcp-over-json-api.html)). Consistency findings and the
derived read model ride on the read payloads. The MCP tool description states
the recorded-not-derived nature and the FIFO reason, so an operating LLM does
not attempt to compute the pots from holdings.

### 7. Explicitly deferred — forward projection (Layer B)

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

### 8. Scope lock

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
- **Configuration cost — accepted.** The feature is four tables, not one:
  the snapshot plus year-scoped statutory parameters, an effective-dated
  taxpayer profile, and the allowance orders. That is more than the "cheap"
  first sketch, and it is the minimum that survives contact with time. The
  alternative — constants in the engine — cannot record a pre-2023 statement
  correctly, cannot represent a taxpayer who is not liable for church tax
  without a special case, and silently rewrites the meaning of past records
  whenever the maintainer's situation changes. Seeded reference data is its
  own small risk: a wrong `tax_parameters` row makes every finding for that
  year wrong, which is why those writes are journaled and why the seed carries
  the German history rather than leaving the operator to type it.
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
- FR-36 in the Requirements Inventory, and E19 in the Tracker Index, of `_bmad-output/planning-artifacts/epics.md` (E19's Epic Detail and story rows were removed by ADR-0042; this ADR is the spec)
- § 32d Abs. 1 EStG — the closed withholding formula the consistency checks reconstruct
