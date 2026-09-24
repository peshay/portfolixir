---
stepsCompleted: [1, 2, 3, 4]
inputDocuments:
  - '_bmad-output/planning-artifacts/prds/prd-portfolixir-2026-06-12/prd.md'
  - '_bmad-output/planning-artifacts/architecture.md'
  - '_bmad-output/planning-artifacts/ux-designs/ux-portfolixir-2026-06-12/DESIGN.md'
  - '_bmad-output/planning-artifacts/ux-designs/ux-portfolixir-2026-06-12/EXPERIENCE.md'
amendments:
  - date: '2026-07-18'
    source: 'MCP field feedback (owner LLM agent), code-verified; owner-confirmed FR-30..FR-35'
    stepsCompleted: [1, 2, 3, 4]
    elicitation: 'inversion analysis + stakeholder round table (subagents); findings applied with owner approval'
  - date: '2026-07-22'
    source: 'owner decisions (FR-29 rescope) + ADR-0029 review-hardening + backlog hygiene'
    stepsCompleted: [1, 2, 3, 4]
    elicitation: 'three-method adversarial review of ADR-0029 (red team vs blue team, pre-mortem, edge-case walk; subagents)'
  - date: '2026-07-25'
    source: 'owner design conversation on German capital-gains tax pots; captured as FR-36 + Epic 19, decision gate ADR-0031 (proposed, sign-off pending)'
    stepsCompleted: [1, 2, 3, 4]
    elicitation: 'derivability analysis (FIFO vs. average cost; missing-input inventory) and internal-reconstruction check against the closed § 32d Abs. 1 EStG formula'
---

# Portfolixir - Epic Breakdown

## Overview

This document provides the complete epic and story breakdown for Portfolixir, decomposing the requirements from the PRD, UX Design, and Architecture into implementable stories.

**Brownfield note:** Portfolixir is an existing Elixir/Phoenix modular monolith — there is NO greenfield/starter-template story. Epic 1 builds on the established codebase (ledger projection, imports, JSON API, MCP companion). The architecture defines a delta tree of *additions* to existing contexts, not a new scaffold.

## Requirements Inventory

### Functional Requirements

**A. Ledger & data integrity**
- FR-1: All financial state derives from the transaction ledger (13 PP kinds + balance adjustments); holdings, balances, performance are projections of it. **Reworded 2026-08-12 (identity gate B3.1)** — previously ended "never stored", which forbade keeping any derived value and is stricter than auditability requires. A derived value may be materialized provided it stays a materialization of the single truth: **rebuildable** from transactions alone (drop-and-rebuild supported and tested), **versioned** against the data-version counter, **never silent about freshness** (`as_of` plus an explicit stale marker, in the UI *and* the API/MCP payload), and **never authoritative for a write** (no booking, import decision or consistency finding reads it instead of the ledger). Which values are materialized is decided by the derived-value ADR (gate B3.2), which must supersede or amend ADR-0032 and argue explicitly against ADR-0035. **Settled 2026-08-12: ADR-0039 is accepted** — one mechanism with a lifetime per analytic (`:none`/`:request`/`:durable`), every registered analytic eligible, activation decided by measurement; it supersedes ADR-0032 (whose memo becomes the `:request` lifetime) and inherits ADR-0035 as the first line of defence. Risk-tier: projection semantics.
- FR-2: The system rejects inconsistent records: currency mismatches (#343), invalid kinds, signed amounts where magnitudes are required.
- FR-3: A written rounding policy governs every Decimal operation (#344); all money math is Decimal-exact end to end.
- FR-4: Portfolios partition the wealth space; every view/analytic can be scoped to one portfolio (UJ-6). Depots and cash accounts move between portfolios (#327) and merge/rename/delete with transaction reassignment (#328).
- FR-28: Every write to financial data (UI/API/MCP) is recorded in an append-only audit journal: actor, timestamp, operation, before/after. Queryable via API and MCP; deletions remain traceable.

**B. Import & reconciliation**
- FR-5: PP exports import losslessly: CSV/JSON v1 (shipped) and XML with classifications, quote history, master data (#333). **Scope gate:** XML intake requires AGENTS.md amendment + ADR.
- FR-6: Imports are previewed, idempotent (content-hash; re-import no-op), and atomic.
- FR-7: Import gaps are surfaced, not silently defaulted: unclassified securities, missing logos (#326), unknown kinds.
- FR-29: Documented backup/restore + full PP-compatible export (roundtrip Portfolixir → PP → Portfolixir), via UI and MCP. Ships before/with the workflows it replaces. **Rescoped 2026-07-22 (owner decision):** the PP-compatible export is dropped — Portfolixir is a one-way import destination; backup/restore = documented `pg_dump` (which also restores strategy configuration wholesale); data egress for external consumers = the JSON API (#354).

**C. Analytics engine**
- FR-8: Performance: TTWROR (shipped) and IRR/money-weighted (#316) per portfolio, depot, security, over selectable periods.
- FR-9: Benchmark comparison vs. configurable alternative (fixed-rate baseline or index/security series), with after-cost/after-tax dimension (Abgeltungsteuer, Vorabpauschale, Teilfreistellung; depth OQ-9). Index scenarios "bought once" and "savings plan". Fixed-rate first, index second (OQ-3).
- FR-10: Income analytics: dividends and interest, gross/net, per year and position (#331).
- FR-11: Allocation: classification trees with target weights, SOLL/IST drift (shipped), target-consistency hints (#318), cash in the 100% basis (#335), per-security exclusion flags (#329).
- FR-12: Rebalancing guidance, both directions (where new cash goes / where needed cash comes from), ranked by drift. Guidance only, never executable orders. **Scope gate:** AGENTS.md amendment clarifies guidance vs. action.

**D. LLM/MCP surface**
- FR-13: Every analytic is exposed via JSON API and MCP (#349); responses self-describing (method, as-of date, currency, conversion basis); financial values as strings.
- FR-14: MCP tools cover data maintenance (create/update) as well as reads, within the same validation, every write captured by FR-28.
- FR-15: Tool descriptions written for LLM tool-choice; paging/limits keep responses small.
- FR-16: MCP companion stays a thin wrapper over the public JSON API (ADR-0002); API/MCP parity reviewed every PR.

**E. Read-only sync (Phase 3, behind scope ADR)**
- FR-17: comdirect depot positions/transactions via official REST API; reconciliation + preview before apply.
- FR-18: bunq account balances/transactions for cash accounts.
- FR-19: bitcoin.de executed trades into the ledger — conditional on OQ-4 spike.
- FR-20: Watch-only crypto balance tracking for offline-wallet addresses/xpubs; private keys permanently out of scope.
- FR-21: Sync is read-only as implemented/audited; credentials stored locally + encrypted; residual risk documented; same validation/idempotency as imports (FR-2, FR-6) + audit journal (FR-28).

**F. Product-type modeling (Phase 4 — each FR preceded by a discovery story)**
- FR-22: Product types carry their own data, math, AND representations (bonds: coupon, maturity, face value, percent-of-nominal, yield — #330 first case).
- FR-23: Corporate actions as guided manual wizards: split, rename/ISIN change, merger/spin-off (#338); history reproducible.
- FR-24: German statutory pension: Rentenpunkte as tracked asset with projected payout.
- FR-25: Private pension/insurance policies: payout options modeled (lump-sum vs. monthly, eligibility ages), comparable against depot withdrawal.

**G. Planning & simulation (Phase 5)**
- FR-26: Retirement projection: wealth-at-age and sustainable-withdrawal curves under named scenario parameter sets (discovery story fixes AC; backs Success Metric 3).
- FR-27: What-if simulator: virtual trade scenarios as overlay timelines vs. real quote history, incl. blind-follow series + aggregate per-source verdict; strictly separated from the real ledger (#332).

**H. LLM-DX & data resilience (added 2026-07-18, source: MCP field feedback from the owner's LLM agent, each claim code-verified; confirmed by the owner and re-reviewed by the reporting agent)**
- FR-30: Holdings payloads (JSON API + MCP) carry the stable security identifiers ISIN/WKN, so external reconciliation needs no client-side join over `securities_list`. (Verified gap: `Api.V1.JSON.holding/2` serializes id/name only.)
- FR-31: The MCP `transactions_create` tool accepts all 13 ledger kinds at parity with the JSON API. Acceptance criteria MUST name `inbound_delivery`/`outbound_delivery` explicitly — together with the holdings-quantity fix (see 2026-07-18 reconciliation) this completes the minimal phantom-position workflow over MCP: book the delivery, holdings are right. FR-23 events/wizards are the comfort layer on top. (Verified gap: create schema allows `buy`/`sell` only while update allows all 13 — forcing a create-as-buy→update-to-dividend detour.) **Delivery cost-basis guard (inversion finding #1):** the schema validates deliveries WITHOUT a price, and an unpriced delivery enters the cost fold at zero — so (a) the MCP tool description must state "a delivery without a price enters the cost basis at zero; supply the price for a correct cost basis", and (b) MCP create REQUIRES a price for `inbound_delivery` (deliberately stricter than the API, which keeps PP-import compatibility). Refined 2026-07-19 after the PR-review UAT round: `outbound_delivery` is exempt — the cost fold removes cost at the running average and ignores its price, so forcing one would persist a fabricated number; the type-change bypass on update is guarded the same way.
- FR-32: Booking semantics are documented where the LLM reads them (MCP tool/schema descriptions + API docs): `gross_amount` on a dividend is the NET cash credited (withheld taxes ride separately; the income report reconstructs gross). Explicitly NOT a field rename — that would be breaking.
- FR-33: Response-size control for token economy: a slim default projection or FIXED field whitelist for `securities_list` so logos/timestamps don't ride along on every listing. Scope lock: `securities_list` ONLY — explicitly no generic field-selection framework across endpoints. Extends FR-15.
- FR-34: Strategy configuration (classifications, target plans, cash target) survives a PP re-import. Decision gate ADR: stable external identity (ISIN-keyed matching at import) vs. strategy-config export/import. Mandatory ADR questions: identity fallback for ISIN-less securities (crypto/watch-only — ISIN is optional and only unique-when-present, so ISIN-only matching silently orphans exactly those positions), and the ISIN-changed case (cross-reference the E17 rename slice). Epic AC: a golden-path round-trip DataCase test (import fixture → attach classification/target/cash-target → re-import mutated fixture → exact-Decimal equality of surviving strategy config). Dependency: E16's journal arming for Targets/Plans completes before E18 write paths land. Touches import idempotency → **risk-tier** (dedicated small PRs, real human review).
- FR-35: Read-only holdings reconciliation against an external position list (preview-style compare, no write-back). Boundary pinned NOW, not deferred to the ADR: the external list arrives ONLY as user-supplied paste/file content — no network acquisition, no credential storage, the external list is never persisted (NFR-4). The reconcile response embeds resolution guidance ("resolve a difference by booking the missing transaction of the correct kind; balance snapshots and unpriced deliveries are last resorts that distort cost basis") so the operating LLM is steered away from the fix-it hammer at the moment of temptation; FR-32's doc story extends the same warning into the `set_balance` and delivery tool descriptions. The decision rides as a SECTION of the FR-34 ADR (one owner decision session, not a separate gate) and must explicitly re-evaluate whether FR-30 plus the established agent reconcile procedure already covers the need — "close as documented procedure, no feature" is an acceptable outcome.

**I. Tax position recording (added 2026-07-25, source: owner design conversation; decision gate ADR-0031)**
- FR-36: The broker's German capital-gains tax block — the loss pots (Aktien / Sonstige), the certified prior-year carry-forward, the Freistellungsauftrag granted/used, the Quellensteuertopf and credited foreign withholding, and the withheld Kapitalertragsteuer / Solidaritätszuschlag / Kirchensteuer — is **recorded** as a dated snapshot per (institution, holder, tax year, as-of), never derived. **The derivation is structurally impossible and the ADR must say so:** Portfolixir folds cost basis as a running average while German taxation mandates strict FIFO, so any multi-tranche position that was partially sold yields a systematically wrong — and invisibly wrong — pot; and Teilfreistellung, Vorabpauschale, chronological allowance consumption, and prior-year carry-forward are not present in transaction data at all. Each recorded snapshot is validated at read time against the closed § 32d Abs. 1 EStG withholding formula `(e − 4q)/(4 + k)` plus the Soli and church-tax ratios, as an **advisory** transcription-error check inside a `max(1.00, 0.05 %)` band that never blocks a save (Teilfreistellung applied at source and mid-year allowance changes legitimately break the identity). **Nothing statutory is hardcoded and nothing personal is assumed:** rates and the Sparer-Pauschbetrag ceilings live in a seeded, operator-editable `tax_parameters` table keyed by `(jurisdiction, tax_year)` — the allowance was 801/1.602 € through 2022 and 1.000/2.000 € from 2023, so a hardcoded ceiling cannot even validate a pre-2023 statement; the taxpayer's own situation lives in an **effective-dated** `tax_profiles` table keyed by `(holder, valid_from)` carrying church-tax liability (**default: not liable**), the rate (8 % in Bavaria and Baden-Württemberg, 9 % elsewhere) and single/joint assessment, so that moving state, marrying, or joining/leaving a church takes effect from a date and never retroactively rewrites what a past statement reconstructs to — the snapshot freezes the resolved rate on its own row. The Freistellungsauftrag is **configured**, not only observed: an `allowance_orders` table per `(holder, institution, tax_year)` records what the taxpayer instructed each bank, which the checks compare against what the bank reports it applied (C7) and against the year's statutory ceiling across all banks (C8). Derived and displayed with its as-of date and staleness: `tax_free_trim_budget = loss_pot_equities + (allowance_granted − allowance_used)` — the volume of realised equity gain still free of Kapitalertragsteuer, which is decision input only and stays inside the ADR-0023 display-only boundary. The `holder` key exists so a second taxpayer's depot can be compared for allowance optimisation. **Deferred to its own gate:** forward projection from the last snapshot and the `tax_bucket` security attribute (`equity`/`other`/`tax_free`) it needs — a projection may never be labelled as a pot balance, only as an estimate with its drift basis stated. Scope lock: no tax-lot/FIFO tracking, no liability computation, nothing filed or transmitted, not tax advice.

**FR-23 sharpened (no new FR):** corporate actions are **ledger events first, wizard second** (reframed 2026-07-18 after stakeholder round table + inversion analysis: a UI wizard is unreachable for the MCP-first operator, and the event representation IS projection semantics). The E17 ADR must decide the event representation (first-class kind vs. composed existing kinds), its projection semantics, and quote-history continuity as APPEND-ONLY adjustment factors (never mutated history — NFR-2), and mandates API/MCP booking + read parity (AR-11) in the acceptance criteria. The guided wizard (split, rename/ISIN change, merger/spin-off) is the subsequent UI layer. Scope lock: splits ONLY in the first ADR slice; rename/ISIN-change (cross-referenced by the FR-34 ADR) and merger/spin-off are follow-on slices. Priority raised from "later" to "next": a split silently distorts every chart and holdings figure, and no delivery pair can compensate for that. The phantom-holdings defect formerly motivating urgency here was a projection bug, not a missing feature — fixed 2026-07-18 (see reconciliation below), NOT part of this feature scope.

**J. Agent-native capabilities (added 2026-08-12, source: product brief 2026-08-12 / identity gate B3.1; the PRD describes these as families in its section 5H, this section is the registry entry)**

Cross-cutting rule for FR-39 through FR-42, FR-47 and FR-48, from the identity gate: **every metric ships with its computation basis in its API and MCP payload** — input series, window, reference series or benchmark where one exists, and the treatment of gaps. This is an acceptance criterion on each of those requirements, not a documentation task: a metric whose basis is unstated cannot be reviewed, because there is nothing to check the implementation against. The existing risk and concentration endpoint is the precedent.

- FR-37: Read ergonomics — per-endpoint **field selection and projections**, **roll-up-only aggregates** that omit the position rows, and **server-side threshold filters** so a caller receives the deviating rows rather than all of them. **Constraint is part of the requirement:** field selection is a validated per-endpoint whitelist — never a passthrough to a query builder, and never an atom created from input (`String.to_existing_atom/1` at the boundary). Generalizes FR-33, whose scope lock confined slim projections to `securities_list`; that lock is superseded for this family and only for it. Acceptance attaches to the agent-side success criteria in the PRD (−70 % response volume on the four heaviest reads, with a field inventory proving nothing load-bearing was cut). Issue #665.
- FR-38: **`?since=` delta reads** — a caller asks what changed since a timestamp or version instead of re-reading full state. The push half (outbound delivery to a configured endpoint) stays gated at B3.7 and must not be scoped into the same story. Issue #666.
- FR-39: **Derived metrics per security** (ladder level (a)): moving averages, realized volatility, drawdown, momentum, distance to extremes.
- FR-40: **Derived metrics per portfolio or view** (ladder level (a)): volatility, risk-adjusted return, maximum drawdown with its window, correlation among the largest positions. Extends the existing risk and concentration endpoint rather than replacing it.
- FR-41: **Contribution analysis** (ladder level (b)): which position produced how much of the return, over a selectable period, scoped to a view.
- FR-42 *(retired 2026-09-23, backlog triage §3.6: sector/region is the classification allocation, factor exposure is out of scope)*: **Exposure decomposition** (ladder level (b)): factor, sector and region exposure. Benchmark comparison is FR-9 and is not restated here. **Boundary against the still-forbidden advanced classifications** (`CONTRIBUTING.md`: splitting one security across categories with partial weights): this requirement *reports* a breakdown from data the catalog already holds. If a decomposition can only be computed by introducing stored partial-weight assignments, it is an advanced classification wearing a report's clothes and needs its own decision — the ladder released the analytics half of the old rule, not the classification half.
- FR-43: **Policy rules as first-class objects** (gate B3.6): type (cap / floor / warning band / protected / budget), scope (category, bucket, security), threshold, severity, validity period, and history so a changed rule is visible after the fact. Caps and floors live today as prose inside scheduled prompts, which is exactly where the observed drift came from. Evaluated server-side into structured findings; a violated rule is the retrievable alarm list, which is the pull half of B3.7. **Needs its own ADR** — it introduces a rules engine whose output drives warnings, and rule history is a data-retention decision.
- FR-44: **Security events as first-class objects** (gate B3.4): security, type, date, timing qualifier, confirmed flag, source, source quality, checked-at, note. **Two boundaries are structural, not technical:** events are tracked for **every security in the catalog, not only held positions** — a purchase candidate with zero holdings is precisely the security whose upcoming dates matter most — and they are **distinct from corporate actions** (ADR-0028, shipped), which are ledger events that change a position; these are calendar facts that book nothing. Sharing a table would be a shortcut that costs later. Manual and agent entry only; *automatic* population is gate B3.3.
- FR-45: **Thesis and conviction as first-class objects**: thesis text, status, conviction tier, invalidation condition, time stop, last reviewed and by whom, with history so a flip is visible afterwards. The free-text `note` field is a better home than a local file but cannot be queried, which is the gap. **Three queries are the acceptance criteria in disguise:** theses unreviewed for 90+ days, positions whose thesis is damaged, and time stops falling due in the next 30 days.
- FR-46: **Predictions as first-class objects**: thesis, stated probability, check date, invalidation, action if right, action if wrong, outcome, resolved-at, resolution note, plus a query for due check dates.
- FR-47: **Prediction calibration report** (ladder level (c)): hit rate per stated-probability band against the stated probability. Depends on FR-46. Acceptance: available without manual work after ten resolved predictions. This is the honest failure mode the system should have more of — a number that can embarrass its author.
- FR-48: **Rule evaluation and signal quality** (ladder level (c)): whether the policy rules of FR-43 are producing findings that turn out to matter. Depends on FR-43.

**The asserted sequencing dependency on FR-43 through FR-46 does not exist — verified against the code 2026-08-12.** The product brief's addendum states that the audit-journal rollout (FR-28) is incomplete (Catalog and FX armed; Portfolios, Classifications, Ledger and Imports unjournaled; MCP write tools blocked behind it) and concludes that #677 is a prerequisite for the knowledge objects. Every part of that premise is false: ADR-0017 carries a "Rollout complete" section; `test/write_actor_test.exs` pins `@grandfathered MapSet.new([])` on a shrink-only list where a stale entry fails the gate; `Journal.record/3` is called from `portfolios.ex`, `classifications.ex`, `ledger.ex` and `imports/applier.ex`; MCP `create`/`update`/`delete` tools ship today; and FX is not armed but deliberately allowlisted as never-journaled market data. The claim is a copy of the superseded 2026-06-18 reconciliation. **FR-43..FR-46 are not blocked by #677**, and #677 needs rescoping or closing — its body repeats the same premise. The requirement underneath survives and is already met: agent-written objects need attribution, and FR-28 supplies it.

**Deliberately excluded from this section:** limit-price suggestions (order preparation rather than allocation guidance; needs an explicit ADR-0023 amendment on its own merits) and estimated per-trade tax (needs a documented method first; ADR-0031 covers *recorded* snapshots and deferred forward projection to its own gate). Both were cut from the rebalancing digest's first version. Ladder level (d), rule backtesting, stays gated.

### NonFunctional Requirements

- NFR-1: Correctness over features — Decimal-only persistence, exact-value tests, invariant meta-tests, quality-gate roadmap are release-blocking.
- NFR-2: Auditability — every number reproducible from immutable inputs; editing allowed, hidden state not; enforced by FR-28.
- NFR-3: AI-agentic development guards — CI gates incl. invisible-Unicode/Trojan-Source rejection (#350); scope changes only via ADR + AGENTS.md amendment.
- NFR-4: Security boundaries — no in-app LLM calls; no trading/payment/order; read-only sync only; API/MCP via local bearer tokens; no secrets in source; web UI unauthenticated by default, authenticated by one variable (`PORTFOLIXIR_UI_PASSWORD`); loopback by default; Host-validated (ADR-0045 answered OQ-8, 2026-09-05).
- NFR-5: Self-hosted operations — docker-compose, PostgreSQL only store, always-on; MCP companion installable separately.
- NFR-6: Single-user tenancy — one instance, one operator; portfolio-scoped filtered views.
- NFR-7: Localization — UI de/en via gettext; repository artifacts in English.
- NFR-8: Performance — interactive views and MCP analytics p95 < 2 s at realistic scale (hundreds of securities, tens of thousands of transactions). Still **aspirational**: no instrument measures it. FR-1's durable derived layer is the structural answer to the felt version of this NFR; it does not supply the missing instrument.
- NFR-9: Mechanical scope backstop — the hard gates **must be** backed by meta-tests in the invariant suite, each removable only in the same PR as its ADR and `AGENTS.md` amendment. *(Entered the PRD on 2026-07-25 via #615 and was missing from this inventory until 2026-08-12; recorded here to close the drift.)* Since the identity gate the guarded set is Phase 3 sync, FR-5 XML intake, the permanent non-goals and the level-(d) backtesting gate, in place of the retired blanket analytics gate — a gate that lifts *partially* is exactly the kind a reader mistakes for lifted entirely. **Unbuilt:** of the three backstops the PRD names, only `mcp_dependency_allowlist_test` (ADR-0002) exists; there is no credential-schema test, no bank-domain-HTTP test and no non-goal test. This is a requirement, not an inventory.
- NFR-10: Machine-extracted data is a proposal until confirmed (added 2026-08-12) — anything extracted from an unstructured source carries its source link and a `machine_generated` marker and lands only after a human or an agent confirms it. The preview-then-apply shape the PP import already uses, applied to every future intake path (ADR-0021 PDF extraction, and whatever gates B3.3/B3.4 collect). Standing rule, independent of whether a local model is ever adopted.

### Additional Requirements

(Technical requirements from Architecture that shape stories — D = decision, P = pattern)

- AR-1 (D1): Audit-journal write happens in the SAME DB transaction as the financial write (`Ecto.Multi`), in the context shell; engines never journal. Actor taxonomy: UI session vs. API/MCP token.
- AR-2 (D2/P3/P4): Analytics are pure engines + loaders — engines compute, the shell reads/writes/journals. No Repo/clock/config inside engines.
- AR-3 (D10/P3): Decimal discipline admits a **contained float "island"** for the operations `Decimal` does not have, and **only for those, each one named here**; every boundary converts back to `Decimal` (`Decimal.from_float/1` then `Decimal.round/2` at the analytic's declared scale — 6 in the IRR solver) and nothing float is ever persisted. Each must be encoded as an explicit, tested exception, not a loophole. **Amended 2026-09-19 (ADR-0047 §4):** the requirement said "the single named exception" while the code already had two — `:math.pow/2` in the IRR solver (Newton's method, `irr.ex`) and `:math.pow/2` for the daily compounding factor of a fixed-rate benchmark (ADR-0046, `benchmark.ex:480`). ADR-0047 adds the third and last one for now: `:math.sqrt/1`, for the standard deviation and correlation of FR-39/FR-40. Widening this list needs an ADR; widening it silently is the loophole this requirement exists to prevent.
- AR-4 (D6): API/MCP analytics use an additive gap-marker refusal contract (HTTP 200 + explicit gap markers) layered on the existing `Api.V1.JSON` shape — no existing consumer breaks.
- AR-5 (D11): Idempotency-keys table is operational state — NOT journaled, NOT under the P1 journal-allowlist guard.
- AR-6 (D4/D1/D11): Portfolio scoping, actor taxonomy, and idempotency form one write-safety refactor and ride together.
- AR-7 (Invariant gates): meta-tests enforce no-float persistence, MCP dependency allowlist (ADR-0002), context boundaries (web/MCP never touch Repo), `Ledger.Projection.effects/1` no-catch-all, migration immutability, exemplar-existence (routing table stays valid).
- AR-8 (P5): What-if scenario isolation — `scenario_*` tables / overlay responses, strictly never the real ledger.
- AR-9: Gated boundaries `sync/` and `pensions/` are declared planned-but-empty until their scope ADR lands (no premature scaffolding).
- AR-10: No new technology versions introduced anywhere; version truth stays in `mix.lock`/`package-lock.json`/CI. Dependencies only via dedicated update PRs.
- AR-11 (FR-13/FR-14 parity): every new API endpoint requires a matching MCP tool (or an explicit n/a note in the PR).

### UX Design Requirements

**Defined in the living design-language spec, not here** (ADR-0038, 2026-08-05).

Authoritative source:

- [`design-language/EXPERIENCE.md` → Design Rules](design-language/EXPERIENCE.md) — the complete DR1..DR20 index and the full text of every behavioral rule.
- [`design-language/DESIGN.md`](design-language/DESIGN.md) — the full text of the visual rules (DR5 motion, DR8 contrast, DR14 spacing and heading ramp, DR16 selected-state appearance, DR18 width-reserved active states, DR19 native-control appearance).

Until 2026-08-05 this section carried the definitions while the spines carried
the design language, so 33 files — `app.css`, eight LiveViews, ADR-0027/0028/0038
and `test/invariants/css_spacing_scale_test.exs` — cited rule numbers that the
spec they derive from did not own. The rules moved into the spec; this section
became a pointer. Where this pointer and the spec disagree, **the spec wins**.

Changes made when the rules moved, so nobody reads a stale number here:

- **DR2 was rewritten** to the Overview as built (value + change, "Needs
  attention", data quality). The four metric cards confirmed on 2026-06-13 were
  never built, and the rule had contradicted the app since June. **Amended
  2026-09-14** by the owner's pick C2-B of the 2026-09-12 UX review: the
  Overview also carries a four-cell KPI strip (three of the 2026-06-13 metrics
  return under a new shape, plus quote freshness); built by #798.
- **DR4 was rewritten** from "which Soon items are hidden" to "which shipped
  surfaces are reachable only by a path the sidebar does not show".
- **DR5's mechanism note is corrected:** the `@property` count-up it named
  cannot render locale-formatted money (`counter()` yields `250000`, never
  `250.000,00`). An inline LiveView hook drives the count instead.
- **DR10, DR11, DR12 were extended** — one uniform chart-data disclosure with a
  stated purpose; prose is not the fallback for what the design did not solve,
  and the 2026-07-23 impersonal-voice rule is part of DR11 now; DR12
  cross-references the new scroll-container rule.
- **DR15..DR20 are new**, from the 2026-08-05 live-surface survey and design
  critique: every wide block owns its scroller (the verified root cause of
  #560); three selected-state classes; three data-note severities;
  width-reserved active states; native controls inherit the design language;
  pending and settling are different states.

### FR Coverage Map

Each requirement maps to a GitHub issue (the executable story unit — "one issue = one chat = one PR"). The PRD/epics are authoritative; issues track implementation. `shipped` = already in the codebase; `gated` = needs ADR + AGENTS.md amendment first; `future` = later phase, discovery-first.

| Req | Issue(s) | Notes |
|---|---|---|
| FR-1 | — | shipped (ledger projection, ADR-0011) |
| FR-2 | #343 | currency consistency |
| FR-3 | #344 | rounding-policy ADR (needs-decision) |
| FR-4 | #327, #328 | portfolio switcher; merge/rename/delete |
| FR-5 | #333 | XML import **gated**; CSV/JSON shipped. **#333 closed 2026-09-23** by the backlog triage (§3.4, adopted by the Sprint 15 planning PR): classifications are Portfolixir-owned and survive a re-import (E18), quote history has an API (`PUT /api/v1/securities/:security_id/quotes`), master data is maintained here; XML intake stays forbidden by the hard rule |
| FR-6 | — | shipped (preview/idempotent/atomic) |
| FR-7 | #326 | import gaps surfaced (logos) |
| FR-8 | #316, #577, #563, #568 (ADR-0034) | IRR; TTWROR shipped. **#577 shipped 2026-08-04** — TTWROR/IRR for a bucket view now cover the deduplicated account union across all portfolios, so the header total and the return always speak about the same accounts; the multi-portfolio scope disclaimer is gone. **#563 shipped** — previous-year/any-year and custom from-to periods, pure re-chains. #568 (net invested, wealth multiple, XIRR) has its design note in ADR-0034 but is **not implemented**. **Sprint 11 Lane X (PR #810, merged 2026-09-15; #779 and #610 closed; D-3, risk-tier):** a priced delivery enters F_d and the lot queue at its booked price and seeds an unpriced security's price, a retired security's stale quote is not a measurement (its next own trade restates the basis), `price_date` per position and `stale_priced_count` on the valuation with the Wealth page naming the holdings to retire; ADR-0010 amended 2026-09-15, registry computation version 3 |
| FR-9 | #572 (ADR-0046) | **Shipped 2026-09-15 (Sprint 11 Lane B, PR #810; #572 closed)** — ADR-0046 executed as signed (gate Accepted 2026-09-07 by the merge of PR #780): two benchmark kinds (a fixed effective annual rate compounding daily Act/365, or an `is_benchmark` security through the existing sync — OQ-3 answered: no new quote source), two comparisons ("bought once" rebased next to TTWROR, "savings plan" replay of ADR-0034 §1's flows with an end-value delta, two IRRs and the period MWR pair), portfolio-wide and per view, on `GET /portfolios/:id/performance/benchmark` and `GET /views/:id/performance/benchmark` with their MCP tools first and the Wealth page's picker, overlays and comparison block in the same batch (DE and EN). The three identities of ADR-0046 are pinned by exact-Decimal tests; the computation basis is in the payload (metric-basis rule). **Ungated 2026-08-12** — the scope ladder released it as level (b). Deferred by ADR-0046 §6: a dated CPI table, the after-tax dimension (OQ-9), a stored per-view default |
| FR-10 | #331 | income report |
| FR-11 | #318, #329, #335, #334, #709 (ADR-0040), #712 (ADR-0041) | target hints, exclude flag, cash basis, classification view. **#709 shipped 2026-08-19 (Sprint 7, PR #716)** — a target plan states its unallocated remainder explicitly and drift is measured against the allocated portion (ADR-0040); the payload names its `drift_basis`. **#712 shipped 2026-08-19 (Sprint 7, PR #716)** — the per-category money-weighted result (ADR-0041 slice one), on the classifications tree, the API and MCP; a statement about the *current composition*, underivable rows excluded and named |
| FR-12 | ADR-0023 | **partially landed** — display-only rebalancing hints (per-position drift share + indicative buy/sell quantity) shipped with the drift drill-down; the guidance-vs-action boundary is drawn in ADR-0023 + AGENTS.md. Ranked both-directions cash guidance remains open |
| FR-13 | #349 | analytics over API/MCP |
| FR-14 | **#355** | MCP data maintenance (new) |
| FR-15 | #355, #349 | LLM tool-choice descriptions |
| FR-16 | — | convention (API/MCP parity, PR review) |
| FR-17–21 | — | **gated** (Phase 3 sync, B3.3). The former tracker #320 is **closed 2026-09-23** as superseded item by item (backlog triage §3.2); the external-agent route (read-only tooling outside the app, booking through MCP) is the working answer and keeps credentials out of the product |
| FR-22 | #330 | bonds (Phase 4, discovery-first) |
| FR-23 | #338 (#588–#591) | corporate actions — ADR-0028 accepted 2026-07-19; #338 repurposed as the E17 tracker. #588–#591 shipped; #338 closed 2026-07-31 |
| FR-24, FR-25 | #340 | pension modeling (Phase 4, parked/discovery) |
| FR-26 | — | **future** (Phase 5 retirement projection). **Outside the scope ladder** — it projects forward rather than reporting the past, so the 2026-08-12 gate neither released nor gated it; open as PRD OQ-13. Not blocking: no issue, Phase 5 not started |
| FR-27 | #332 | what-if simulator. **Still gated after 2026-08-12**, on new grounds: blind-follow backtesting is ladder level (d), which is out for now and reopens after the policy-rules work (gate B3.6). OQ-11 (quotes for never-held securities) remains an independent blocker underneath | **Retired 2026-09-23** by the backlog triage (§3.3, adopted by the Sprint 15 planning PR): its differentiating half is ladder level (d) and its simple half is answered by ADR-0027's snapshot counterfactual and ADR-0046's benchmark; #332 closed by hand. A future simulator needs a new gate |
| FR-28 | **#353** | audit journal (new) |
| FR-29 | #354 | **rescoped 2026-07-22**: documented `pg_dump` backup/restore only; PP export dropped. **The procedure shipped 2026-09-24 (Sprint 15, PR #867)**: backup, restore and the restore check in `docs/home-deployment.md` (EN/DE), verified end to end with Docker on the demo seed. #354 stays open under `needs-uat` for the owner's restore on the real instance |
| NFR-1 | #347, #348, #314, #344 | correctness suites + gates |
| NFR-2 | #353 | auditability = audit journal |
| NFR-3 | #346, #347, #350 | AI-agentic guards |
| NFR-4–6 | **#757** (E21 tracker; #758–#772), gate **ADR-0045** Accepted 2026-09-05 | foundational (security, self-hosted, single-user). **NFR-4's perimeter shipped with E21** (Sprint 10, PR #773 merged 2026-09-06, #758–#771 closed): Host guard answering 421, loopback by default with a startup warning, session cookie attributes and derived salts, opt-in `PHX_FORCE_SSL`, a production release image with no secret defaults, the deny-by-default URL policy and bounded HTTP client on every outbound fetch, constant-time token comparison with a per-source throttle, system-set provenance, and the optional built-in UI authentication of ADR-0045 (OQ-8 answered). **The family closed with Sprint 11 (PR #810, merged 2026-09-15):** #772 (Bandit serves the endpoint, cowlib and its three advisories out of the tree, the Hex pin gone from CI, every Action pinned to a SHA), #382 (the per-request CSP nonce, no inline handler left, `force_ssl` off by default and opt-in through `PHX_FORCE_SSL` — D-2 — so Sobelow runs with no ignore) and #776 (`limit` on the nine remaining collection reads and their MCP tools; the journal read's own parser is #811). Nothing in the family stays open |
| NFR-7 | #313 | localization / docs site |
| NFR-8 | #562 (ADR-0032), #619 (ADR-0035) | cross-cutting perf; watch in perf-sensitive stories. ADR-0032 accepted 2026-07-29 — the daily TTWROR walk is memoized in volatile memory with warm-up, targeted invalidation and a labelled stale-serve. **#619 shipped 2026-08-04** (ADR-0035): the redundancy was removed rather than cached — market data is preloaded once per read and threaded through every valuation and allocation, replacing six re-derivations and hundreds of per-row lookups. Measured A/B: the warm dashboard block 1,105 ms → 265 ms and 2,614 → 115 queries, output identical. Nothing is memoized by this change; ADR-0032's memo is untouched |
| UX-DR1–20 | **#356** (tracker) + #414, #672 open, plus #701–#704, #707 filed 2026-08-15; #412, #491, #560, #565, #566 shipped | UX/a11y tracker. Rules are defined in `design-language/EXPERIENCE.md` and `DESIGN.md`, not in this document (ADR-0038). **Sprint 7 (PR #716, merged 2026-08-19) closed #414, #672, #701–#704, #706 and #707**; the 2026-08-18 design engagement filed #717–#721 and #723, and the Sprint-7 walkthrough filed #729 and #730 — all attach here. **Sprint 8 (PR #735, merged 2026-08-22) closed all eight** (#717–#721, #723, #729, #730) and added UX-DR25 (an excluded row is named where the total is read) and UX-DR26 (a deliberate limit is stated on the surface that lacks it) to the living spec. #336, #337, #339, #319 and #606 are closed. **#606 shipped 2026-08-04** — the impersonal microcopy voice rule, applied retroactively to all pre-rule UI strings and the EN/DE docs, and now part of DR11 rather than only an agent rule. DR15–DR20 were added by the 2026-08-05 design session; the alignment stories are cut from the spec. **Sprint 12 (PR #813, rebase-merged 2026-09-15, `main` at `5ea57ea3`) shipped the second E11 alignment pass and closed all twenty-two of its issues, #784–#805 contiguous** — cut from the 2026-09-12 whole-surface review (`planning-artifacts/ux-review-2026-09-12.md`), which filed #784–#808 with #809 following on 2026-09-14, across Lanes F (defect sweep), N (data notes and freshness), S (Tax, Snapshots, Views, sunburst, income chart), K (Wealth KPI band, Overview strip), P (phone rows, filter sheet), T (booking drawer) and D (detail pane, tree rows, custom range). UX-DR27 (phone list rows) was added by the 2026-09-12 spine amendment and UX-DR2 amended 2026-09-14 for the Overview strip (#798-B); `DESIGN.md` names all eight owner picks (C1-A, C2-B, C3-A, C4-B, C5-A, C6-C, C7-A, C8-A). **Still open under #356:** #806, #807, #808, #809 (Sprint 13 candidates declared by D-3 before the batch started) and the closing act's three findings #815 (the `/classifications` index is a bare bullet list), #816 (the transaction history needs the phone filter sheet the securities list got) and #817 (the detail pane's tab row is held to none of the D6 shipped form). **E11 CLOSED 2026-09-19 (Sprint 13, PR #832, `main` at `6e7de6ef`)**: all six shipped — #806 (the bucket cell saying what a set applies to, variant A), #807 (the Realized-gains facet as the Trades view), #808 (the Classifications index as rows), #809 (edit a booking from the history), #816 (the history's filter sheet under 560 px) and #817 (the tab row on the D6 form, now pinned by `css_layout_sweep_test.exs`) — with #815 closed by hand as #808's duplicate and **tracker #356 closed with the evidence**. The design-critic review of this batch added `bucket-list`, `bucket-cell`, `security-metric-grid`, `security-events-tab` and `due-card` to DESIGN.md and restated the D6 tab-row paragraph as a rule. Its findings that fell outside the PR's scope are filed rather than widened: #833 (`.num` has no generic rule), #834 (the kebab's focus ring and coarse-pointer floor), #835 (two column-picker treatments), #836 (`aria-pressed`/`aria-expanded` as bare booleans), #837 (the tablist's roving tabindex) and #842 (the `+N` chip's `title`). **E11 does not reopen** — further UX work is held against the living spec by the standing design-critic gate (ADR-0038), not by a tracker |
| FR-30 | #582 | ISIN/WKN in holdings payloads (E6 DX batch, story 2) |
| FR-31 | #581 | MCP create: all 13 kinds, deliveries + price guard in AC (E6 DX batch, story 1) |
| FR-32 | #583 | booking-semantics docs incl. fix-it-hammer warnings (E6 DX batch, story 3) |
| FR-33 | #584 | slim `securities_list` projection, scope-locked (E6 DX batch, story 4) |
| FR-34 | #600, #601 | ADR-0029 accepted 2026-07-22 — identity ladder + alias record, risk-tier |
| FR-35 | #602 | ADR-0029 §6 verdict: build the read-only reconcile endpoint |
| FR-36 | #612 (gate), #621–#625 | recorded tax-statement snapshots — ADR-0031 accepted 2026-07-25. Stories 19.2–19.6 shipped: configuration layer, snapshot table, consistency engine, API/MCP parity, entry surface + EN/DE docs. Forward projection and `tax_bucket` (19.7) are deferred behind a separate gate |
| FR-37 | #665 | read ergonomics — sparse fieldsets, roll-up-only aggregates, server-side threshold filters. **Shipped 2026-08-14 (Sprint 6, PR #688)** with the −70 % volume cut pinned by test. Supersedes FR-33's scope lock for this family only. Human-view status after Sprint 7 (PR #716): the **threshold half is discharged** — drift-threshold chips on the allocation table share one predicate (`Allocation.drift_at_least?/2`) with the API's `min_drift=`; the **roll-up half is discharged by #712** (shipped). The last obligation — the `fields=` column picker on the transactions and holdings lists (#732) — **shipped 2026-08-22 (Sprint 8, PR #735)**: key-scoped pickers on both tables, `fields=` on `GET /api/v1/securities` and the MCP tool, a sparse fieldset superseding `projection`. FR-37 is fully discharged in both directions on the endpoints it reached — and the 2026-08-27 agent round found that it did not reach all of them: `views.valuation` takes no `include_positions` in either half, and `targets.list_positions` has no threshold filter (**#740**). The requirement is done; its surface is not, which is the same shape as the human-view debt on a second axis. **#740 shipped 2026-09-03 (Sprint 9, PR #754)**: `include_positions` on `GET /views/:id/valuation` and `min_drift` on `GET /portfolios/:id/position_targets`, both halves, through one parser and the allocation's own drift predicate; the close-out's surface check names every endpoint of both families as carrying its parameter. FR-37 is discharged on every read it applies to |
| FR-38 | #666 | `?since=` delta reads. **Shipped 2026-08-14 (Sprint 6, PR #688)**, pull-only with the B3.7 boundary pinned by test; the push half stays gated at B3.7. The human view (#731) **shipped 2026-08-22 (Sprint 8, PR #735)**: `?since=` on the transactions and securities lists with one-tap windows, sharing the API's own `SinceParam`, the deletions clause stated on the surface. FR-38's pull half is discharged in both directions; the push half stays gated at B3.7. **Scheduled Sprint 14 as #830** (2026-09-19 agent round, the parameter's surface rather than the parameter): the plan's D-5 splits the complaint into three shapes and only one of them is this parameter's. `?since=` is a **row delta** over `updated_at`, so it extends to the row-collection reads a scheduled run polls. It does **not** extend to the **derived projections** — valuation, allocation, performance, risk have no rows, and "has this changed since I last read it" is a basis-version question ADR-0039's `DataVersion.portfolio_basis/1` already answers internally, so exposing it is a conditional-read decision, filed rather than built. And it must **not** extend to the **time-derived queues** (`/notes/unreviewed`, `/notes/expiring`, `/notes/uncorroborated`, `/events/upcoming`, `/events/stale`, `/events/unconfirmed`), whose membership changes because time passes with no row changing: a `?since=` there would silently drop the note that became unreviewed overnight without being touched. The close-out's surface check names all three sets — the same shape as Sprint 13's deliberate absence of `days=` from `/events/unconfirmed`. **In the Sprint 14 batch (2026-09-23, PR #846):** #830 carries `?since=` on the per-security notes read (cut on `inserted_at`, the log being append-only), the per-security events read, and the targets and position-targets reads (a row counts as changed when it **or its plan** changed, so a plan activation is not missed); the six time-derived queues deliberately ignore it; the derived projections' conditional read is **filed as #849** (needs a decision). The configuration collections, quotes and the journal are named in the close-out's surface sentence with their reasons. **#830 shipped 2026-09-23 (Sprint 14, PR #846, `main` at `c0746222`)** in exactly that scope; the close-out's surface sentence names the family in full (sprint-status.yaml, Sprint 14 entry) |
| FR-39, FR-40 | #821 (tracker), #823, #824, #825, #838, #847, #848; mechanism: #710, #711 | derived metrics per security / per view (ladder (a)). **Ungated by the ladder**, no issue yet — depended on the derived-value ADR (gate B3.2) for where the values live; ADR-0039 accepted 2026-08-12 supplies that home, and **the mechanism landed 2026-08-14 (C1–C5, Sprint 6, PR #688)** — these are issue-ready now. **#710 and #711 shipped 2026-08-19 (Sprint 7, PR #716)** — the refresh now runs on the invalidating write, coalesced (one refresh per basis on an import, mutation-verified), and the cross-portfolio walk is activated `:durable` on measured figures (recorded in ADR-0039). These were the mechanism, not the metrics. **The decision landed 2026-09-19: [ADR-0047](../../docs/decisions/0047-derived-metrics-per-security-and-per-view.md), signed by the merge of the Sprint 13 planning PR** — two input series that are never mixed (a security's split-adjusted closes in its own currency; the portfolio's daily valuation walk in the base currency), the portfolio figures read off the TTWROR chain's flow-adjusted factors so an external flow cannot read as a return, a gap producing no observation rather than a zero, a stated minimum below which a metric refuses with a gap marker, the float island widened by exactly `:math.sqrt/1` (AR-3 amended in the same PR), and no signal, rating or action in either payload (pinned by a key-set meta-test). The metrics are E22 and are scheduled as Sprint 13's Lane A; **the story issues were filed at branch opening, after the signature**: #823 (the per-security engine, its `GET /api/v1/securities/:security_id/metrics` read and `portfolixir.securities.metrics`), #824 (the human view on the chart tab, design pick D1-A) and #825 (the per-security invalidation basis of §8, filed and not built). **Lane A2 — the portfolio and view figures — moved to Sprint 14 by the plan's D-7**, together with identity I1, to make room for the security-events lane; ADR-0047 stays signed whole and only the build order moved. **Lane A1 shipped 2026-09-19 (Sprint 13, PR #832, rebase-merged, `main` at `6e7de6ef`)**: `Portfolixir.Engines.PriceMetrics` as a pure engine over an injected close series, its shell `Catalog.SecurityMetrics` loading the split-adjusted series in the security's own currency, `GET /api/v1/securities/:security_id/metrics`, `portfolixir.securities.metrics` and the metric strip under the price chart (#823, #824 closed). Identities I2, I5, I6 and I7 are pinned by tests; the risk-tier pass found **two of them unpinned when it started** — I2's *at scale 6* clause (the helper compared with `Decimal.equal?/2`, which ignores scale) and the I6 meta-test's blind spot (it deleted `computation_basis` before walking, although it collects keys and never values) — both mutation-verified red, then fixed. **§6 was amended in the same batch** on the owner's decision of 2026-09-19 (#838): a computed metric carries the span it measured, a refused one carries what it had and, as `required`, what it needed, with `window` `null` where the metric is defined over a count of closes. The wording is adopted; the payload half rides A2. **Still open under E22:** Lane A2 with I1 and I4's portfolio half, #825, and #838's payload half. **Sprint 14 (planned 2026-09-20) closes E22** on Lane A2 with #838 and #825, and its plan's **D-2 corrects §9 against the code**: the record places the portfolio figures "on the Wealth risk surface" and **there is none**. `Portfolixir.Portfolios.Risk` is referenced by `risk_controller.ex`, the route and `mix portfolixir.derived.measure`, and by nothing in `lib/portfolixir_web/live/**`; the only strings naming concentration, HHI or a cap violation are `risk.ex`'s moduledoc and `json.ex`'s basis prose, neither of them UI copy. So FR-8/FR-9/FR-10's concentration lens has been **agent-only since it shipped** — which predates the two-way coverage rule of 2026-08-12, so no deadline was ever missed and nothing is in breach; it is the older debt the rule exists to stop accumulating, sitting under an ADR clause that assumed it had been paid. The plan's recommended option **A** is a sixth Wealth tab carrying the existing lens together with A1's four figures (the area tab row already carries the D6 scroll-snap form #817 copied from, so a sixth tab costs a list entry); B leaves the lens agent-only, C defers both with the coverage deadline recorded. The design pass for that surface runs at branch opening, before the view is built. **Sprint 14's story issues, filed at branch opening (2026-09-23, Lane Z):** #847 (the portfolio and view figures on the risk read, I1/I3/I4/I7, A3 riding it) and #848 (the human view: design pick **E1-A**, a sixth Wealth tab "Risk" carrying the concentration lens and the four figures). #838 and #825 keep their numbers and ride the same batch. **Shipped 2026-09-23 (Sprint 14, PR #846, rebase-merged, `main` at `c0746222`) — E22 DONE; FR-39 and FR-40 are discharged in both directions.** #847: volatility, max drawdown and risk-adjusted return over 30d/90d/365d on the one risk read, over the TTWROR chain's flow-adjusted factors (each factor rounded at 15 places so Decimal division residue is not a return), `risk_free_rate=` defaulting to 0, and the Top-N correlation matrix converted to the base currency first; `portfolio_metrics` registered at `:request` under the portfolio basis. #838: `required` on every metric of both payloads in both states. #848: the Wealth **Risk** tab (E1-A) — the concentration lens's first human view together with the four figures. #825: `DataVersion.security_basis/1`, with `security_metrics` left at `:none` and the C3 measurement available, not taken. I1, I3, I4 and I7 are pinned end to end and were mutation-verified by the lane and again by the closing act's correctness hunter, which also found I1 broken through currency conversion (residue) and fixed it on the branch. Tracker #821 closed by hand |
| FR-41, FR-42 | — | contribution analysis; factor/sector/region exposure (ladder (b)). **Ungated by the ladder**, no issue yet. **FR-41:** decided at Sprint 16's planning, checked against ADR-0041 first (it may be a thin extension of the category result), built in Sprint 17. **FR-42 retired 2026-09-23** (backlog triage §3.6): sector and region exposure is the allocation breakdown over a classification tree (goals 10 and 12, shipped); factor exposure needs partial-weight assignments (advanced classifications, out of scope) or external factor data (B3.3). Nothing is left that is both allowed and new |
| FR-43 | ADR-0049; E24 #861 (#862 rules and versions, #863 findings, #864 identity and survival, #865 the operator's view; flow rules deferred as #866) | policy rules as objects. **Gate B3.6 CLOSED 2026-09-23** by [ADR-0049](../../docs/decisions/0049-policy-rules-as-first-class-objects.md), signed by the merge of the Sprint 15 planning PR: a rule is a stored predicate (cap / floor / band, severity warn / hard) over one named measure an existing read already produces (weight, drift, HHI, portfolio volatility, max drawdown), in a context (portfolio, view) on a subject (basis, security, category, view, cash); versioned and effective-dated so the standard in force on a date is a read, a version in force immutable, versions never overlapping; evaluated at read into findings with three states where `undetermined` never passes; findings carry a computation basis and no action (key-set meta-test). The bucket scope is answered through the `view` subject. **Deferred with reasons (ADR-0043):** `protected` and `budget` (predicates over flows, filed as #866), rules over events, rules over `risk_adjusted_return` / correlations / per-security metrics, historical findings (FR-48's input), the lens defaulting its caps from rules. B3.5, B3.7 and level (d) stay shut. Scheduled as Sprint 15 Lane A. **Shipped 2026-09-24 (Sprint 15, PR #867, rebase-merged, `main` at `096b80e5`) — E24 DONE; FR-43 is discharged in both directions for caps, floors and bands.** #862: `PolicyRule` and `PolicyRuleVersion`, journaled, a version in force immutable and versions never overlapping (a context guard plus a DB trigger and an exclusion constraint), six `/api/v1` routes and six `portfolixir.policy_rules.*` tools. #863: the findings read (`GET /portfolios/:portfolio_id/policy_findings`, `portfolixir.portfolios.policy_findings`), `undetermined` never a pass and always with its reason (`unvalued` added by the closing act for a subject held but not valued), a drift finding's `drift_basis` in its computation basis, and the key-set meta-test for no action. #864: a delete of anything a rule reads answers 409 by name, and rules survive a Portfolio Performance re-import. #865: the operator's view on Wealth → **Risk** (pick F1-A) — findings, scheduled rules, retired rules, one dialog for create and edit. Contract version 7. The mutation passes found M4 and M6 unpinned at first and both are now pinned; M7 is layered behind the DB constraint by design. Tracker #861 closed by hand; the flow rules stay #866 |
| FR-44 | ADR-0048; #822 (tracker), #826, #827, #828, #829 | security events as objects. **Gate B3.4 CLOSED 2026-09-19** by [ADR-0048](../../docs/decisions/0048-security-events-as-first-class-objects.md), signed by the merge of the Sprint 13 planning PR, on the 2026-09-19 agent round's P0-4 — the agent's calendar is built out of the holdings, so a security not yet owned has nowhere to keep a date, and a purchase candidate's reporting date came close to being missed. The decision: a dated calendar fact in its own table that books nothing (never a ledger effect, distinct from ADR-0028), keyed on `security_id` alone so the **catalog is the default scope and `held_only` is the opt-in**, a four-value timing qualifier so a guess is never stored as a filing, **mutable and journaled rather than append-only** (a fact's history is an audit trail, and ADR-0017 is the audit trail — the argued difference from ADR-0044), `source_quality` reusing ADR-0044's vocabulary, four reads as the acceptance criteria, and the re-import guarantee extended in the same batch. **Automatic population stays at B3.3**, alerting and push at B3.7, rules over events at B3.6 — §8 names each. Scheduled as Sprint 13 Lane E; **the issues were filed at branch opening**: #826 (the journaled table, its enum boundary and its timing qualifier), #827 (the four reads plus the three writes on API and MCP), #828 (the "Termine" tab — design pick D2-B — and the "Fällig" Overview card — D3-A) and #829 (the re-import preservation guarantee). Both human surfaces landed **in the same batch**, so the Consequences' deferred-view clause did not have to fire. **Shipped whole 2026-09-19 (Sprint 13, PR #832, `main` at `6e7de6ef`)** — #826, #827, #828 and #829 closed: the journaled table with its closed sets cast by hand so an unknown value is `"is invalid"` and never a new atom, the four reads and three writes on API and MCP with the catalog as the default scope, the Dates tab and the Fällig card. The closing act's confirmed findings on this family were fixed before the merge: deleting a security that carries an event answers **409** rather than raising (the new `:restrict` FK had no `foreign_key_constraint`), `held_only` counts every kind the canonical projection moves quantity with rather than buys and sells alone — which is §2's own failure one layer down, a delivered depot reported as unheld — `days=` is capped at ten years and echoed capped, an over-long `source_url` is a 422, and a write to a vanished row is a 404. **FR-44 is discharged in both directions; E22 and E23 are the batch, and only E22 stays open** |
| FR-45, FR-46 | **#747** (E20 tracker; #748–#752), gate **ADR-0044** Accepted | thesis/conviction (**B4.1**) and prediction (**B4.2**) objects. Decided in principle by the identity gate. **FR-45's gate is signed**: ADR-0044 (2026-08-27, owner sign-off 2026-09-03) decides the thesis state and the append-only research log behind it as one object family — the log is the truth, the state is its projection, a retraction is an entry rather than a deletion. **Shipped 2026-09-03 (Sprint 9, PR #754, E20 done)**: #748 the `security_notes` table and context, journal-armed at creation; #749 the thesis state as a projection in the security read; #750 API and MCP append plus the four reads; #751 the research timeline on the security detail pane (the signed same-batch clause); #752 the contract-version read. FR-46 stays at B4.2, adjacent and deliberately separate |
| FR-47, FR-48 | — | calibration report (needs FR-46); rule evaluation (needs FR-43). Ladder (c) — scores what was recorded before the outcome was known, never a replayed counterfactual, which is level (d) |
| NFR-9 | — | mechanical scope backstop — guarded set revised 2026-08-12. **Unbuilt requirement, not inventory:** only `mcp_dependency_allowlist_test` exists of the three named backstops |
| NFR-10 | — | machine-extracted data is a proposal until confirmed; first binding use is ADR-0021 PDF intake |

### Backlog beyond the FR set — the 2026-08-15 triage (reconciled 2026-08-17)

The owner feedback round of 2026-08-15 (`feedback-triage-2026-08-15.md`) produced
thirteen issues and four accepted decisions. It is best read as **the acceptance
round for Sprint 6's design lane** rather than as new backlog: five of the six
design issues filed on 2026-08-12 had shipped days earlier, and the owner was
looking at exactly those surfaces. Under ADR-0026 step 4 and ADR-0038 that
day-to-day observation *is* the acceptance channel.

Most of these carry **no FR number**, and none is invented here — they attach to
the GitHub trackers instead. Whether this family should gain FR numbers and an
epic row is part of the standing structural finding (F2/F7 in
`sprint-status.yaml`), which is an owner decision and still open.

| Issue | What | Attaches to | Basis |
|---|---|---|---|
| #700 | asset class: stored vs. effective, and the dead quick-assign affordance | #417 | triage F1 — the dashboard counts `asset_class IS NULL` while the list renders an *inferred* class, so the count says "unclassified", every row says "Equity", and the remediation dropdown (built by #561) never renders. The fix loop is dead on arrival |
| #701 | securities table headers bypass gettext, stay English on a DE instance | #356 | triage F2 |
| #702 | Wealth tab row clips on a phone and cannot be scrolled | #356 | triage F3 — regression from #668 |
| #703 | "no current quote" withholds its positions; Overview/Wealth say it twice | #356 | triage F4 — `trade_priced` is the one data-quality row that states a count and stops |
| #704 | an internal ADR identifier is printed in user-facing copy on Snapshots | #356 | triage F5 |
| #705 | data-quality predicates over the filter builder, API and MCP | #419 | triage F6 — **depends on #700**: the predicate must mean what the count means |
| #706 | design-critic and UAT walkthroughs run under conditions that hide the defects they exist to catch | #420 | triage 0.2 — the pass ran at desktop width, in EN, against data that triggered no finding surface; four of six defects were invisible under exactly those conditions |
| #707 | the design engagement: control vocabulary, card naming, and the two surfaces that predate the design language | #356 | triage Part 2 + Part 4 (D1–D6, Transactions, Income). **#414 and #471 should follow its output** rather than land on the pre-design-language screen |
| #708 | snapshot comparison states its transaction costs, and whether they are earned back | E16 | **ADR-0027 amendment**, Accepted 2026-08-15 |
| #709 | target plans: explicit unallocated remainder, drift against the allocated portion | FR-11 / E15 | **ADR-0040**, Accepted 2026-08-15 |
| #710 | derived values refresh on the invalidating write, coalesced | NFR-8 | **ADR-0039 amendment** §§1–3, Accepted 2026-08-15. **Risk-tier** |
| #711 | measure and activate the figures the operator actually waits on | NFR-8 | ADR-0039 §2 + amendment §4 |
| #712 | category result: money-weighted roll-up on the category row, expandable | FR-11 | **ADR-0041**, Accepted 2026-08-15 |

**Filed deliberately late, and why it matters.** The three decision items were
held back from Round 3 and filed only once their ADRs were signed off, so no
issue ever carried a title with no spec behind it. That is the issue convention
working as designed, and it is why all four decisions below are gate-complete
for scheduling purposes.

**Not filed, on purpose:** the **Trades view**, which must first be reconciled
against the "how well did I sell" cash-flow facet from the 2026-08-12 round, so
one table is specified once rather than twice under two names.

**The finding worth carrying:** *generalising a request before satisfying it
manufactures its own difficulties.* The category figure was asked for as a table
column and first built as a return series; every hard question it raised — the
membership-over-time basis, the restatement marker — came from that framing, and
none of them survived building what was actually asked for. Both are recorded in
ADR-0041 as **withdrawn, not deferred**.

### Backlog beyond the FR set — the 2026-08-27 agent round

The owner's portfolio agent submitted the **second edition** of its requirements
document (`feedback-triage-2026-08-27.md`). Most of it is the 2026-08-11 round
unchanged, and the pipeline had moved under it: P0-1 and the pull half of P1-6
shipped as FR-37/FR-38 on 2026-08-14, the tax-staleness warning as #667, the
"how well did I sell" surface as Sprint 8's Cash-flow facets — none of which the
agent knew.

| Issue | What | Attaches to | Basis |
|---|---|---|---|
| #740 | the read-ergonomics parameters skipped the view-scoped reads | FR-37 / #419 | triage §0.3 — `views.valuation` has no `include_positions` in API or MCP while its portfolio-scoped twin does, and `targets.list_positions` has no threshold filter. Two of the four reads the agent measures |
| #741 | the re-import preservation guarantee exists only as a test | FR-34/FR-35 / #470 | triage Part 4 — #664 refuted the destroys-classification claim on 2026-08-14 and pinned it, but nothing outside the test file says so, which is why the refuted claim survived into a second edition |

**The finding worth carrying:** *a coverage rule stated per requirement lets a
requirement be done while its surface is half-done.* FR-37 was rolled out
endpoint by endpoint and its row in the map above said "fully discharged in both
directions" while two of the agent's four heaviest reads still cost full price.
The proposed remedy is a surface check at the close-out — when a
read-ergonomics parameter lands, the close-out names every endpoint of that
family and states which ones carry it — rather than a second rule.

**Decided in the triage rather than asked of the owner** (Part 5): limit-price
suggestions stay out, already answered by ADR-0023 and the permanent non-goals;
agent discoverability is a product defect this system owns and rides ADR-0044 §8
as a contract-version read. **One item is the owner's alone:** the signature on
ADR-0044.

### Backlog beyond the FR set — the 2026-09-19 agent round

The owner's portfolio agent submitted the **third edition** of its
requirements document (`feedback-triage-2026-09-19.md`), reading Contract v4
against its own list of 2026-08-27. Five shipped items are correctly ticked
off. What is left sorts by **what stands between the request and the work**,
which is the only ordering a plan can act on — and on that reading only one
item needed anything from this round.

| Item | What | Attaches to | Verdict |
|---|---|---|---|
| P0-4 | security events as objects — the agent's calendar is built out of the holdings, so an unheld purchase candidate has nowhere to keep a date | FR-44 / E23 | **Gate closed here.** [ADR-0048](../../docs/decisions/0048-security-events-as-first-class-objects.md) signed 2026-09-19; Sprint 13 Lane E builds it. The agent's own ranking — the only gap that hides risk rather than costing tokens — is adopted |
| P1-6 (delta half) | `?since=` delta reads | FR-38 / #419 | **Half refuted, half filed.** `?since=` shipped 2026-08-14; it exists on `GET /securities` and `GET /transactions` only (verified: `SinceParam` is aliased in those two controllers and nowhere else). The complaint is really that it is missing from the reads a scheduled run polls — **the #740 shape again**, filed as the FR-38 surface gap, Sprint 14 candidate |
| P1-6 (trigger half) | threshold alarms | FR-43 / B3.7 | **Gated.** A retrievable alarm list is FR-43's output (B3.6); outbound delivery is B3.7 |
| P0-2 | rebalancing digest | B3.5 | **Gated**, and additionally dependent on the policy rules having something to evaluate |
| P0-3 | policy rules — caps and floors live as prose in scheduled prompts, and the agent reports observed drift | FR-43 / B3.6 | **Gated.** The round supplies a *second independent observation* of the drift FR-43 already names, which is the strongest argument yet for opening B3.6 — recorded as evidence for Sprint 14 planning, not opened here. Two gates in one planning PR is the limit of what an owner reads and signs in one sitting |
| P1-5 | derived metrics and indicators | FR-39/FR-40 / E22 | **Already in flight** — ADR-0047 signed on the same PR; Sprint 13 builds the per-security half. The agent's list and the pipeline moved past each other again |
| P1-2 | prediction calibration | FR-47 / B4.2 | **Gated** behind FR-46: calibration with no recorded predictions has nothing to score |
| P1-3 | collector / signals | B3.3 | **Gated** — acquisition beyond quotes and FX |
| P2-2 | backtesting | ladder (d) | **Out** — a boundary, not a backlog item |
| Appendix B, Q1 | "does the research log survive a PP re-import?" | — | **Refuted, third consecutive edition.** It survives, identical and mutated, pinned by `reimport_preservation_test.exs` (which asserts the research-log snapshot, the note count and the derived `thesis_state`) and documented in `docs/integration/api-and-mcp.md` → Imports, which names the research log and closes with "an agent that observes otherwise has found a defect, not a documented limitation". #664 refuted the classification/targets half on 2026-08-14; #741 documented it |

**The finding worth carrying:** *a machine-readable "what changed" is not the
same as a machine-read "what is guaranteed".* The contract-version read of
ADR-0044 §8 was built after the 2026-08-27 round found an agent had no way to
learn the surface changed, and it works — this edition cites Contract v4 and
ticks off five shipped items. Yet the document's most expensive claim is
false for the third time, because the agent re-derives its list from its own
previous edition rather than from the integration documentation. A guarantee
a consumer must not get wrong belongs **where the consumer reads by
construction** — in the tool description or the payload — which is the same
rule the metric-basis requirement already states for metrics ("a doc page
does not satisfy it"). Filed as a Sprint 14 candidate: the re-import
preservation guarantee gains a sentence in the MCP tool descriptions of the
reads it protects.

## Implementation Status — reconciled with code (2026-06-18)

> The sections above are the **authoritative planning intent** as captured on
> 2026-06-12 (issues referenced up to #356). The codebase has since advanced to
> ~#442. This section reconciles the plan with what is **actually in `main`**, so
> downstream agentic work is steered by reality, not a stale map. It is additive
> — it corrects status, it does not rewrite the original requirements.
>
> Ground truth at time of writing: `mix compile --warnings-as-errors` clean;
> **735 tests, 0 failures**; gated boundaries (`sync/`, `pensions/`) empty as
> designed (AR-9 ✓); Decimal discipline intact, IRR float-island the only
> exception (AR-3 ✓).

### Shipped beyond the 2026-06-12 doc (status: DONE)

These were `now`/`next` and are delivered with code **and** tests:

- **FR-1/2/3** ledger projection, currency-consistency validation (#362), rounding
  policy ADR-0016 (#394).
- **FR-6** import preview / idempotent / atomic.
- **FR-8** TTWROR **and** IRR (`portfolios/performance/irr.ex`, #364).
- **FR-10** income analytics (`portfolios/income.ex`, #374).
- **FR-11** allocation: target hints, exclusion flags, cash-in-basis, classification
  value view (#365/#367/#371/#372).
- **FR-13/15/16** self-describing analytics over API/MCP (#384/#386); risk &
  concentration endpoint (`portfolios/risk.ex`, #391); FX-correct cross-currency
  settlement (#393).
- **NFR-1/3** invariant meta-tests live (`test/invariants/*`), CI gates green.
- **NFR-7 / E12** bilingual docs site (#380) + gettext de/en (`localization_test`).

### In-flight by design — the main source of "half-finished" feel (status: PARTIAL)

- **FR-28 / FR-14 — Audit journal (ADR-0017, sequenced slice rollout).**
  - Slice 0 (infra) ✓ and Slice 1 (Catalog/Fx armed, actor-first) ✓.
  - **Not yet:** Portfolios/Classifications → Ledger → Imports. Writes in those
    contexts run **unjournaled** today, so the FR-28/NFR-2 "every write is
    auditable" guarantee is **not yet actually met**.
  - **MCP data-maintenance writes (FR-14)** are blocked behind this: arming MCP
    write tools before the journal rollout completes would let an agent edit
    transactions/accounts/classifications **without an audit trail**. Finish the
    rollout *before* enabling agent writes.
  - Note: the `scenario_id` column on `audit_journal` is an **intentional**
    forward-index for FR-27 (documented in ADR-0017), not stray scaffolding.

### Genuine open gaps (status: MISSING / not started)

- **FR-29 — Backup/restore + PP-compatible export.** No code, no tracking issue
  in-repo. PRD requires it to ship *before* external copies are retired →
  data-safety gap. Needs a conscious "plan now" vs. "explicitly later" decision.
- **FR-4 — Depot/cash move + merge/rename/delete (#327/#328).** Portfolio
  scoping exists; the lifecycle ops are **not implemented** (no `move_*`/`merge_*`
  functions in `portfolios.ex`). Decide if still wanted.
- **AR-11 minor parity gap:** generic `portfolio.update` API write has no MCP
  counterpart.

### Correctly gated — no code, as designed (status: GATED, do not "fix")

FR-5 (XML import), FR-9 (benchmark), FR-12 (rebalancing), FR-17–21 (sync),
FR-22–26 (product types, pensions, retirement). Each still needs its scope
ADR + AGENTS.md amendment (and, for FR-22–26, a discovery story) before code.

## Implementation Status — reconciled with code (2026-07-16)

> Second additive reconciliation (the 2026-06-18 section above stays as the
> historical record). Ground truth: `main` at #576 (buckets & views replace
> portfolios in the UI, ADR-0024); 1122 tests + 6 properties, 0 failures.

### Newly shipped since 2026-06-18 (status: DONE)

- **E13 — Buckets & views (ADR-0018)**: complete, including the ADR-0024
  follow-through that replaced portfolios as the user-facing grouping (#576)
  and view-scoped performance boundary flows (ADR-0019).
- **E15 — View-bound SOLL plans (ADR-0020)**: complete (`TargetPlan` with
  `view_id`, Gesamt plan, per-view cash target).
- **E14 — CSS consistency**: complete — raw-hex ratchet is at **0**, the 4px
  spacing scale + heading ramp landed (UX-DR14), both guarded by invariant
  meta-tests.
- **E2 (partial → mostly done) — audit journal (ADR-0017)**: rollout now covers
  Catalog/Fx, **Ledger, Portfolios, Imports**. Open slice: **Targets/Plans**
  (noted in `TargetPlan`'s moduledoc) — rides with E16.
- **E6 — LLM/MCP surface**: MCP data-maintenance writes (FR-14/#355) are
  broadly shipped (securities/accounts/transactions/classifications/targets
  create-update-delete), unblocked by the journal rollout above.
- **E7 (partial)**: display-only rebalancing hints + drift drill-down
  (ADR-0023); ADR-0021 PDF intake and ADR-0022 IA landed alongside.

### Remaining genuine gaps (status: MISSING)

- **FR-29 — backup/restore + PP-compatible export**: still no code. PM
  recommendation 2026-07-16 (owner confirmation pending): keep `pg_dump` as
  the operational backup (documented, docker-compose sidecar) and build the
  application-level piece as the lossless PP-compatible export that
  round-trips through the existing idempotent import (restore = re-import).
- **E7 rest**: ranked both-direction cash guidance (needs its scope decision).
- **E16 — plan versions & depot snapshots (ADR-0027)**: new, decision gate
  signed off by the owner 2026-07-16 — in implementation on
  `agent/claude/plan-snapshots-adr`.

## Implementation Status — reconciled with code (2026-07-18)

> Third additive reconciliation. Trigger: MCP field feedback from the owner's
> LLM agent surfaced a wrong-number defect and four DX gaps; all claims were
> verified against the code before planning.

- **Phantom-holdings defect: FIXED on branch, pending owner merge.** The
  moving-average holdings views (`holdings_for_portfolio/2`,
  `holdings_for_security/2`) derived quantities from the `buy`/`sell` stream
  only, so positions exited via `inbound_delivery`/`outbound_delivery`/
  `security_transfer` lingered with stale quantities (an FR-1 violation — the
  canonical `Positions` fold already counted these kinds; the two views did
  not). Fixed fast-lane, no ADR gate, on
  `claude/portfolixir-holdings-calculation-zfcqeh`:
  - `e6508aa` — holdings quantities now come from the canonical
    `Ledger.Positions` fold (deliveries + transfers move them); a synthetic
    takeover case (buy, then takeover booked as outbound delivery)
    is a committed regression test.
  - `5ed3f13` — follow-up from the mandatory adversarial review (3 agents:
    correctness, edge-case, UAT persona): the cost basis now follows the
    shares (transfers carry cost into the counter depot, removals take cost
    out at the running average, unpriced deliveries enter at zero cost, P&L
    percentage can no longer sign-flip on negative positions). Docs EN/DE
    updated.
  - **Owner actions:** review + merge the branch (ledger math = risk-tier,
    agents never merge), then have the reporting LLM agent re-verify live
    over MCP (ledger quantity vs. holdings for the affected ISINs) as UAT
    evidence. Until merge, the running instance still shows the phantom.
- Import applier note (feeds E17/E18 design): the PP CSV parser reads a
  `Kurs` for deliveries but the applier persists only `quantity` — imported
  deliveries therefore carry no price and enter the cost fold at zero cost.
  Carrying the price through is a candidate story in the E6 DX batch or E17.

## Owner decisions and review round — 2026-07-22

- **FR-29 rescoped (owner decision):** the PP-compatible export is dropped.
  Portfolixir is a one-way import destination; whoever needs data out builds
  their own exporter against the JSON API. Remaining #354 scope: a
  documented, verified `pg_dump` backup/restore for the compose deployment —
  which also covers fresh-database restore of strategy configuration
  (ADR-0029's former "FR-29 native export" references were amended
  accordingly). Success Metric 1 is now backed by pg_dump plus the E18
  re-import survival work, not an export roundtrip.
- **ADR-0029 review-hardened:** the three-method adversarial review (red
  team vs blue team, pre-mortem, edge-case walk) ran; all six decisions
  survived. Confirmed findings amended into the ADR: the ADR-0030
  position-target class was missing from the §4 survival contract
  (blocker), a stronger-identifier veto for weaker ladder tiers (blocker),
  a bidirectional alias-uniqueness guard shipping in the same PR as the
  alias-consulting tier (blocker), the wrong-ordering double-insert repair
  path (blocker), preview→apply revalidation, a pre-apply inverse check for
  signal-free renames, identifier normalization, and a hardened reconcile
  request/response contract. The ADR awaits owner sign-off.
- **UAT-label audit:** `needs-uat` kept on #328, #330, #332, #333, #354,
  #412, #564 (owner judgment or risk-tier); #414, #561, #563, #565, #566
  relabeled `agentic` (objective acceptance criteria, agent UAT-persona
  walkthrough suffices); #471 de-labeled (parked pending its ADR-0024
  re-cut). Backlog trackers (#321, #338, #417–#419, #481, #398) reconciled
  with the real issue states; #399 closed as complete.

## Implementation Status — reconciled with code (2026-07-31)

> Fourth additive reconciliation. Trigger: a status check before Sprint 2
> planning found the planning artifacts describing a state two weeks behind
> `main`. Verified against the merge commit, the closed-issue list and the
> (empty) open-PR list — the lesson from the 2026-07-25 plan revision, applied.

Ground truth: `main` at `02dde3b`.

- **Sprint 1 landed in full — all three lanes, not only the epic batch.**
  Lane A: E19 stories 19.2–19.6 (`#621`–`#625`), ADR-0031 flipped to
  *Accepted*, `Portfolixir.Tax` amended into the AGENTS.md Active
  Architecture. Lane B: `#607` (scoped leftover check) and `#609` (local date
  boundary, reconcile response ordering, name-differs hint). Lane C: `#562`,
  the memoized daily walk.
- **ADR-0032 is new and had no home in this document.** Accepted 2026-07-29:
  the daily TTWROR walk is memoized in volatile memory with warm-up, targeted
  invalidation on writes and a labelled stale-while-revalidate serve. It is
  cross-cutting performance work, so it is recorded against NFR-8 rather than
  given an epic of its own. Two follow-ups were opened deliberately *before*
  measuring, so the findings do not get lost: `#619` (the dashboard's other
  three mount computations) and `#620` (show which FIFO lots a sale consumes).
- **E17/E18 trackers closed.** `#338` and `#603` had all children merged and
  their review debt cleared; both closed 2026-07-31.
- **The commit-authorship gate has been red on `main` since 2026-07-24.** Not
  a flake and not an author problem: a squash-merge through the GitHub UI sets
  the *committer* to `GitHub <noreply@github.com>`, which
  `scripts/check-commit-authorship.sh` rejects. The author is correct on every
  commit. ADR-0026 prescribes owner squash-merge, so the policy and its
  enforcement currently contradict each other by construction. Owner decision
  pending: exempt GitHub's merge committer, or move merges local. Left open
  here rather than silently patched — weakening a quality gate to make a batch
  pass is a review reject (ADR-0026), and so is weakening one to make a merge
  button work.
- **Still open, unchanged from the 2026-07-25 standing findings:** `epics.md`
  defines E1–E19 while GitHub carries a separate tracker set (`#416`–`#420`,
  `#470`, `#398`, `#356`), and roughly twenty open issues hang off neither —
  now including `#619` and `#620`. `#321` (roadmap index) is stale. One
  reconciliation pass is still owed; it is Sprint 2 work, not a side effect of
  this one.

## Implementation Status — reconciled with code (2026-08-01)

> Fifth additive reconciliation, part of the Sprint 2 Lane A bookkeeping
> close-out (the closing-act step added by the combined E17–E19 retro).

Ground truth: `main` at `ba6a046`.

- **Sprint 2 Lane A merged (`ba6a046`, PR #629).** `#406` — the "no price"
  warning now distinguishes two honest states ("no price at all" vs. "price
  available, no exchange rate to the base currency stored"), and securities
  detail and portfolio totals unify on the same price-resolution semantics
  (global trade-price fallback on both surfaces). `#570` — negative holdings
  are listed in the data-quality report per depot and total, link to the
  security's transactions, and are visibly marked on allocation, valuation and
  classification surfaces. Shipped as one combined PR per the owner override
  recorded in the sprint plan; UAT persona walkthrough archived under
  `implementation-artifacts/uat-sprint2-lane-a-2026-08-01/`. Tracker `#398`
  closed with both sub-issues complete.
- **ADR-0033 accepted (2026-08-01, `58c90f5`).** Per-position P&L decomposes
  into price return and currency return over a security-currency cost basis
  (Option A). Unblocks the `#569` implementation and `#620` — both Sprint 3,
  each risk-tier.
- **The commit-authorship gate is green again.** `ee51260` accepts GitHub's
  web-flow merge committer for the committer role only, and only when the
  author is allowlisted. The first squash-merge after the fix (`ba6a046`)
  passed on 2026-08-01 — the policy-vs-enforcement contradiction recorded in
  the 2026-07-31 reconciliation is resolved.

## Implementation Status — reconciled with code (2026-08-04)

> Sixth additive reconciliation, part of the Sprint 3 bookkeeping close-out
> (ADR-0026 step 5).

Ground truth: `main` at `1903913` (PR #631, squash-merged 2026-08-04).

- **Sprint 3 shipped as one bundle.** `#569` (per-position P&L decomposed into
  price return and currency return per ADR-0033, with the cost fold carrying a
  native/base pair, settlement legs persisted on import and an auditable
  backfill for existing rows), `#620` (the FIFO tranches a sale consumes, shown
  where the sale is decided — gross gain, never a tax figure), `#577`
  (cross-portfolio performance walk), `#563` (period picker), `#606` (microcopy
  voice sweep) and `#619` (one pricing pass per read). All six issues closed.
- **Four ADRs accepted.** ADR-0034 (money-weighted metrics — design note for
  `#568`, no implementation), ADR-0035 (one pricing pass per read),
  ADR-0036 (risk-tier work rides the batch — amends ADR-0026), ADR-0037
  (Phoenix 1.8 / LiveView 1.x as a security upgrade).
- **The risk-tier delivery rule was withdrawn mid-sprint (ADR-0036).** The
  ADR-0026 exception requiring ledger/money math, security changes and
  dependency updates to ship as dedicated small PRs with real human review did
  not survive contact with a single reviewer: it was deviated from three times
  in two days on this one branch. Risk-tier is now an attention label
  governing review depth, not PR granularity, and the compensating controls
  (TDD-first with exact `Decimal` expectations, every gate green) became
  blocking. ADR-0028, -0029 and -0030 carried undelivered follow-on slices
  still citing the withdrawn clause; their delivery bullets are annotated in
  place.
- **Dependency security was in a materially worse state than anyone knew.**
  An advisory-aware `mix hex.audit` reported **15 advisories on `main`, five
  HIGH** (mint, hpax, cowlib, phoenix) that **neither CI audit gate caught**:
  `hex.audit` runs pinned to Hex 2.4.1 by deliberate design (2.5's advisory
  gating has no ignore mechanism), making it retirement-only, and
  `mix deps.audit`'s database does not carry them. The batch closed 13 of 15
  — the tree is down to two cowlib entries, neither HIGH, both without an
  upstream fix and already documented as tolerated in `ci.yml`.
- **Phoenix 1.8 cost almost nothing, against expectation.** The last HIGH
  (`EEF-CVE-2026-56811`) had no fix in the 1.7 line, so the upgrade was
  unavoidable. It changed **no application code** — the codebase already used
  the idioms LiveView 1.x requires — and needed only `lazy_html` as a test
  dependency plus unlocking an orphaned `castore`. Because `ConnTest` and
  `LiveViewTest` bypass the HTTP server and never run JavaScript, acceptance
  included a real Chromium session confirming the LiveView client connects on
  four routes with no console errors.
- **CI gained the gates it was documented to have.** The MCP companion's
  `npm test` / `npm run build` had been required by AGENTS.md but never run in
  CI; they run now, with `--ignore-scripts` on the install. Both workflows
  declare least-privilege `permissions`.
- **Structural finding, unchanged and now overdue.** The two parallel epic
  structures (`epics.md` E1–E19 vs. the GitHub tracker set) were partly
  reconciled during this sprint — 17 previously unattached issues were
  attached to their trackers — but the structural decision itself (cross-
  reference the two, or dissolve one) is still the owner's and still open.
  `#321` (roadmap index) remains stale; closing it needs its "working
  agreement" section preserved somewhere first.
## Implementation Status — reconciled with code (2026-08-19, Sprint 7 close-out)

Verification basis: the merge commits on `main` (bb3d728..80d3e7e, PR #716
rebase-merged), the post-merge open-issue list, and the remote tag list.

**Shipped by Sprint 7** — sixteen issues closed by the merge's keywords:
the review conditions (#706), the five-defect UI set (#700–#704), the design
engagement spec (#707), the transaction history rework (#414), the
`/cashflow` parent (#672), the data-quality predicates (#705), refresh-on-
write for derived values (#710, #711), the three signed decisions (#708,
#709, #712), and the PerformanceTest flake (#722). #471 was closed by hand as
invalidated (ADR-0024), #321 by hand as superseded (ADR-0042). Tag `0.7.0`
(annotated) on `80d3e7e`.

**The FR Coverage Map above is updated in this pass** (FR-11, FR-37, FR-38,
FR-39/40, UX-DR row): the two-way-rule debt that survives Sprint 7 is exactly
#731 (`?since=` human view) and #732 (`fields=` column picker), both due by
the end of the next batch. The Sprint-7 walkthrough findings #729 and #730
and the design-engagement issues #717–#721/#723 attach to #356.

Retrospective: `sprint-7-retro-2026-08-19.md`. Close-out ledger and the
process findings live there and in `sprint-status.yaml`'s log; this section
records only what changed in the requirement registry.

## Implementation Status — reconciled with code (2026-09-24, Sprint 15 close-out)

Verification basis: the commits on `main` (`165dfec..096b80e`, PR #867
rebase-merged, 31 commits linear, zero merge commits), the Actions runs on the
merge push (Commit authorship 607 and CI 1593, verified green before this entry
was written), the post-merge issue list, and the diff of the merged tree
against the pre-merge head `0607a78e` (empty).

**Shipped by Sprint 15** — fourteen issues closed by the merge's keywords under
the plan adopted by the merge of the Sprint 15 planning PR; nothing was taken
from the shrink order. **E24 closes.**

- **E24** (#862, #863, #864, #865) — policy rules as versioned,
  effective-dated objects, the findings read with `undetermined` never a pass,
  delete protection by name and re-import survival, and the operator's view on
  Wealth → Risk. Contract version 7.
- **The correctness debt** (#851, #853, #855, #856) — the invalidation radius
  as the union of both images, a wrapped body that is not an object refused,
  no id past the bigint range reaching the database from a page, `offset` and
  `days` bounded.
- **The operator floor** (#854, #857, #858, #850) — one disclosure marker, the
  active area tab in view on arrival, the row menu reachable by keyboard, one
  grouped column-picker popover on every table.
- **The surfaces the records assumed** — position-level SOLL entry in the plan
  editor (#481, pick F2-A; settable only over the API since 2026-07-21) and the
  settlement inputs of a cross-currency trade in the booking form with the
  cash/settlement guard (#395, pick F3-A, risk-tier; ADR-0015's guard on the
  owner's 2026-07-19 decision). The closing act moved the Portfolio Performance
  importer and the settlement backfill onto the guard's inverse, so imported
  and backfilled rows meet it by construction.
- **FR-29** — the backup and restore procedure (#354), verified; the issue
  stays open under `needs-uat` for the owner's restore.

**Registry rows this batch moves:** **FR-43** records E24 as done and
discharged in both directions; **FR-29** records the verified procedure. The
Tracker Index's **E24** line is marked done.

**Two-way coverage:** every capability this batch added reached a screen in
the same batch, and two older debts are paid — position-level SOLL and the
cross-currency booking, each API-only before. No deadline carries into
Sprint 16.

**Surface check (the 2026-09-03 owner decision):** `since=` now also carries
on the policy-rules list (a rule changed when its row or any version changed)
and is **deliberately absent** from the findings read, a derived projection
(#849). `status=` on the findings read and `as_of=` / `include_retired=` on
the rules list are families of one endpoint each.

**Closing-act findings filed (Scope Lock):** #868–#876; #872 needs a decision.

## Implementation Status — reconciled with code (2026-09-23, Sprint 14 close-out)

Verification basis: the commits on `main` (`d085572..c074622`, PR #846
rebase-merged, 30 commits linear, zero merge commits), the Actions runs on the
merge push (Commit authorship 585 and CI 1571, verified green before this entry
was written), the post-merge issue list, and the diff of the merged tree
against the pre-merge head `67abe49` (empty).

**Shipped by Sprint 14** — sixteen issues closed by the merge's keywords under
the plan adopted by the merge of the Sprint 14 planning PR; nothing was taken
from the shrink order. **E22 closes.**

- **E22's remainder** (#847, #838, #848, #825) — the portfolio and view
  figures on the risk read, `required` on both metric payloads, the Wealth
  **Risk** tab (the concentration lens's first human view), and the
  per-security invalidation basis.
- **The error contract** (#840, #841, #839, #852) — one id parser and a range
  guard on `/api/v1`, `source_url` bounded in codepoints, one "is it held?"
  predicate that answers a security with a split from the canonical fold.
- **Design conformance** (#833, #834, #836, #842, #837, #844) — the generic
  `.num` rule, the kebab focus ring and coarse floor, ARIA states as strings,
  the `+N` chip as an in-place disclosure, the detail pane's tablist, eight ADR
  front matters quoted (four more than filed had been publishing truncated).
- **The agent's surface** (#830, #831) — `?since=` on the row collections a
  scheduled run polls, the re-import guarantee in the tool descriptions.
- **Contract version 6**, one bump for the sprint.

**Decided and filed, not built:** #835 is decided (D-4 / E3, `.popover`) and
closed by hand; its convergence is #850. The derived-projection delta read is
#849 (needs a decision).

**Registry rows this batch moves:** **FR-39/FR-40** records E22 as done and
discharged in both directions; **FR-38** records #830 in the scope D-5 set. The
Tracker Index's **E22** line is marked done.

**Two-way coverage:** every figure this batch added reached a screen in the
same batch, and the older debt D-2 found — the concentration lens, agent-only
since it shipped — is paid. No deadline carries into Sprint 15.

**Surface check (the 2026-09-03 owner decision):** `risk_free_rate=` lands on
a family of exactly one endpoint (the view is `view=`, ADR-0047 §9).
`since=` is carried by the securities, transactions, per-security notes and
events, targets and position-targets reads; it is **deliberately absent** from
the six time-derived queues, whose membership changes because time passes;
the derived projections need a basis-version read (#849); the configuration
collections, quotes and the journal do not carry it, each for a stated reason.

**Closing-act findings filed (Scope Lock):** #851, #853–#858.

## Implementation Status — reconciled with code (2026-09-19, Sprint 13 close-out)

Verification basis: the commits on `main` (`2131fe0..6e7de6e`, PR #832
rebase-merged, 23 commits linear, zero merge commits), the Actions runs on the
merge push (CI 1552 and Commit authorship 566, verified green before this entry
was written), the post-merge issue list, and the diff of the merged tree
against the pre-merge head `aa5e7db` (empty). The rebase replayed the commits,
so `main`'s SHAs differ from the branch's; tree equality is the check that
holds.

**Shipped by Sprint 13** — fourteen issues closed by the merge's keywords,
under the plan adopted by the merge of the Sprint 13 planning PR and its eight
decisions. Two object families and an epic close:

- **E22, Lane A1** (#823, #824) — `Portfolixir.Engines.PriceMetrics` as a pure
  engine over an injected close series: SMA-50/200 with the distance to each,
  realized volatility, maximum drawdown with peak/trough/recovery dates,
  3M/6M/12M momentum, distance to the 52-week extremes. Its shell loads the
  split-adjusted series in the security's own currency and attaches the
  computation basis; `GET /api/v1/securities/:security_id/metrics`,
  `portfolixir.securities.metrics`, and the metric strip under the price chart.
- **E23, whole** (#826–#829) — the journaled `security_events` table with its
  closed sets cast by hand, the four reads and three writes on API and MCP with
  the catalog as the default scope, the Dates tab, the Fällig card, and the
  re-import guarantee extended.
- **E11's remainder** (#806–#809, #816, #817) — the accounts bucket cell, the
  Realized-gains facet as the Trades view, the Classifications index as rows,
  editing a booking from the history, the history's filter sheet under 560 px,
  and the detail pane's tab row on the D6 shipped form.
- **Lane B** (#814) — the holdings projection's own positions on Wealth with a
  column picker over its fields.
- **Lane D** (#811) — the journal read onto the shared `ListLimit` parser.

**Registry rows this batch moves:** **FR-39/FR-40** records Lane A1 as shipped
and names what stays open under E22; **FR-44** is discharged in both
directions; the **UX-DR1–20** row records the third alignment pass and E11's
close. The Tracker Index's **E11** and **E23** lines are marked done; **E22**
stays open on Lane A2.

**Two-way coverage — the deadline Sprint 12 set was met.** That close-out
recorded #803 removing the Transactions holdings panel, and with it the column
picker that was the human half of the holdings API's `fields=` sparse fieldset,
with the human view due in the same or the **next** epic batch. This is the
next batch and **#814 shipped in it**. The rule fired, was tracked across a
sprint boundary, and was discharged on time — the first time the deadline has
been exercised end to end. Nothing in this batch is agent-only: E23's two human
surfaces landed in the same batch as its reads, and E22's human view landed
with its engine.

**Surface check (the 2026-09-03 owner decision):** one new bounded parameter
landed, `days=` on the events family, and the family is named in full. Its
three horizon-capable reads are `GET /api/v1/events/upcoming`, `/stale` and
`/unconfirmed`; `days=` is carried by the first two and is **deliberately
absent from `unconfirmed`**, because that queue has no horizon — every
unconfirmed past date belongs in it however old it is. The absence is what the
check is for: the MCP tool advertised `days=` on `unconfirmed` anyway, the
correctness hunter caught it, and the tool now has its own schema with a test
pinning the property set. `limit=` became uniform in the same batch (#811), so
the bounded-list family has one parser and no second copy to drift.

**An owner decision was taken inside the batch (#838).** ADR-0047 §6 said both
halves of a metric's basis are required, and a refused count-based metric
renders `window: null`. The owner chose variant C on 2026-09-19 and §6 is
amended: a computed metric carries the span it measured; a refused one carries
what it had and, as `required`, what it needed, with `window` the requested
span where the metric is defined over a date range and `null` where it is
defined over a count of closes. The amendment also names the wider gap the same
review exposed — **no refusal states its threshold today** — and one limit it
will not paper over: where the requirement is a coverage rule rather than a
count (`momentum`, `distance_to_extremes`), `required` carries the floor only.
The wording is adopted; the payload half rides Lane A2 into Sprint 14, so the
surface takes one contract bump instead of two.

## Implementation Status — reconciled with code (2026-09-15, Sprint 12 close-out)

Verification basis: the merge commits on `main` (d6466f7d..5ea57ea3, PR #813
rebase-merged, 28 commits linear, no merge commits), the Actions runs on the
merge push (CI 1525 and Commit authorship 539, verified green), the post-merge
issue list (30 open, each of the batch's twenty-two verified closed/completed),
and the diff of the merged tree against the pre-merge head `ceef8665` (empty).
The rebase-merge replayed the commits, so `main`'s SHAs differ from the
branch's; tree equality is the check that holds.

**Shipped by Sprint 12** — twenty-two issues closed by the merge's keywords,
`#784`–`#805` contiguous, under the Sprint 12 plan adopted by the merge of PR
#783 and its five decisions. E11's **second alignment pass**, cut from the
2026-09-12 whole-surface UX review: the defect sweep (Lane F — the top bar's
diacritics, one localized label per transaction kind with no raw-value
fallback, the history's numbers under the locale, the UX-DR15 scroller tail,
the layout sweep, sixteen strings that stopped addressing the reader), data
notes and freshness (Lane N — Wealth's data quality as data notes with the
remedy inside, a stale quote marked at all three call sites where a price is
read, every Cash-flow facet naming itself), the four specified surfaces and
both chart gaps (Lane S — Tax as a budget meter plus check list, Snapshots
where the comparison *is* the surface, Views list-first, the allocation
sunburst's basis line and readable centre, the income chart's legend and direct
labels), and the six picked variants: the Wealth two-tier KPI band and the
Overview key-figure strip (Lane K, picks A and B, `newest_quote_date` joining
both valuation reads on the API and in MCP), two-line phone rows and the filter
bottom sheet under 560 px (Lane P, picks A and B, UX-DR27), Transactions
opening on its history with the booking form as a side drawer (Lane T, pick C),
and the detail pane's reading surface, the tree's column rows and the custom
range popover (Lane D, picks A, A, A).

**Registry rows this batch moves:** the **UX-DR1–20** row records the second
alignment pass as shipped and names what remains under #356. No FR or NFR row
changes state — every issue in the batch is a UX-DR alignment item, which is
why the FR Coverage Map is otherwise untouched.

**Two-way coverage — the rule fired for the first time, on this batch's own
removal.** #803 removed the Transactions "Current holdings" panel as a
duplicate of Wealth → Holdings; that panel carried the column picker #732 added
as the human half of the holdings API's `fields=` sparse fieldset. The
projection's valuation fields are now readable over the API and MCP with no
human view. That is allowed for the batch that creates the gap provided the PR
says why (#813's briefing does), with the human view due in the same or the
next epic batch. This batch is the "same"; **Sprint 13 is the "next", and its
close-out must find #814 shipped or record a finding.** #814 was filed the day
the gap was created. Nothing else in the batch is agent-only: #798's
`newest_quote_date` shipped with its human view in the same commit.

**Surface check:** no new read-ergonomics parameter landed, so there is no
parameter family to enumerate. The one payload field added passes on both
scopes rather than one — `newest_quote_date` is on the portfolio scope and the
view scope, in the API and in both MCP tools. That is the same family FR-37
shipped half of (portfolio scope only, which became #740); not repeated here.
The surface gap the batch did leave is human and filed: the phone filter sheet
landed on the securities list (#800) and not on the transaction history
(#816).

**Filed by the batch, open:** #814 (the `fields=` human half, due Sprint 13),
#815 (the `/classifications` index is still a bare bullet list), #816 (the
transaction history needs the phone filter sheet), #817 (the detail pane's tab
row is held to none of the D6 shipped form). **Declared out by D-3 before the
batch started:** #806, #807, #808, #809 — Sprint 13 candidates.

E11's tracker **#356 stays open**: the review's remainder and the closing act's
three findings attach to it, so the epic is not finished.

Retrospective: `sprint-12-retro-2026-09-15.md`. Close-out ledger and the
process findings live there and in `sprint-status.yaml`'s log; this section
records only what changed in the requirement registry.

## Implementation Status — reconciled with code (2026-09-15, Sprint 11 close-out)

Verification basis: the merge commits on `main` (cc70b9f..c2164f54, PR #810
rebase-merged, 23 commits linear), the Actions runs on the merge push (CI 1506
and Commit authorship 520, verified green), and the post-merge open-issue list
(48 open).

**Shipped by Sprint 11** — six issues closed by the merge's keywords, under
the Sprint 11 plan adopted by the merge of PR #780 and its four decisions:
E21's remainder (#772 Bandit serves the endpoint, cowlib and its three
advisories leave the tree, CI installs the current Hex with `mix deps.audit`
unignored, every Action pinned to a SHA; #382 a per-request CSP nonce with no
inline handler left in any template and `connect-src` naming the validated
Host's socket, the HTTPS posture configured and opt-in — D-2 — so Sobelow runs
with no ignore; #776 `limit` on the nine remaining collection reads and their
MCP tools, every bounded payload echoing the limit it applied), the walk on
retired securities (#779 a priced delivery enters F_d and the lot queue at its
booked price and seeds an unpriced security's price; #610 a retired security's
stale quote is not a measurement, `price_date` per position and
`stale_priced_count` on the valuation, the Wealth page naming the holdings to
retire — D-3, risk-tier, ADR-0010 amended 2026-09-15, registry computation
version 3), and the founding question (#572 the benchmark comparison per
ADR-0046 — D-1, risk-tier, executed as signed: the `is_benchmark` flag, the
engine with its three identities pinned by exact-Decimal tests, the two API
reads with their MCP tools and the contract manifest v4 entry, the Wealth
page's picker, overlays and comparison block, DE and EN). Lane M's report
(`version-report-2026-09-15.md`) applied the Bandit swap's dependency moves,
mint 1.10.0, phoenix 1.8.14, dialyxir 1.4.8 and the MCP lockfile, and left the
toolchain, the Node image, the Hex image pin, PostgreSQL and BMAD with reasons.
No tracker to close by hand: the sprint had no epic of its own.

**The FR Coverage Map above is updated in this pass** (FR-9 row: shipped;
FR-8 row: Lane X; NFR-4–6 row: the family closed; Tracker Index E10 and E21
lines). The two-way-coverage ledger stays **empty**: Lane B shipped API and
MCP first and the human view in the same batch, Lane X's fields ship with the
Wealth finding that names them, and Lane W's bounds are a machine-read
parameter with no human view by nature (as #771 was treated at the Sprint 10
close-out). Deliberately not closed: #727 (both toolchain halves blocked
upstream; triggers re-checked 2026-09-15, none fired; #775 closed with the
reason), #811 (filed by the surface check, a Sprint 13 candidate), #314 (the
ratchet rides every batch: patch coverage 96.7 % on the merged head).

**The surface check, third use, names the `limit` family complete but for one
read.** Carried by `GET /transactions`, `/securities`, `/exchange_rates`,
`/securities/:id/quotes` (Sprint 10) and `/securities/:security_id/notes`,
`/notes/unreviewed`, `/notes/uncorroborated`, `/notes/expiring`, `/snapshots`,
`/realized_gains`, `/external_flows`, `/costs` (this batch), MCP twins alike;
`/securities/:security_id/trades` is bounded by `from`/`to` and says so in its
basis; `/journal` parses its own `limit` and clamps where `ListLimit` refuses —
filed as **#811**, checked against the route table rather than the briefing.

**One finding of the close-out's own:** the Codecov report on the promoted
head listed 45 changed lines without a test, above the 90 % patch target and
therefore no red gate — and half of them were documented behaviour paths,
several in risk-tier code (the engine's GBX pricing through GBP, its unpriced
days before the first stored FX rate, the year period, the covered-window note
on the page), that the four review roles had not asked for. Pinned in one
tests-only commit before the merge (`c2164f54`); the closing act's inputs gain
the patch-coverage listing (retrospective).

Retrospective: `sprint-11-retro-2026-09-15.md`. Close-out ledger and process
findings live there and in `sprint-status.yaml`'s log; this section records
only what changed in the requirement registry.

## Implementation Status — reconciled with code (2026-09-06, Sprint 10 close-out)

Verification basis: the merge commits on `main` (22913af..b701613a, PR #773
rebase-merged, 25 commits linear), the Actions runs on the merge push (CI 1483
and Commit authorship 497, verified green), and the post-merge open-issue list.

**Shipped by Sprint 10** — fourteen issues closed by the merge's keywords, the
E21 hardening batch under ADR-0045 and the 2026-09-05 security-review triage:
the perimeter (#758 Host guard, loopback by default, exposure warning; #759
session cookie attributes, per-installation derived salts, opt-in force_ssl;
#760 the production Compose file and release image with no secret defaults;
#761 bearer-token hygiene on API and companion), egress (#762 a deny-by-default
URL policy before every server-side fetch of a caller- or provider-supplied
URL, with per-source host lists and every redirect hop re-checked; #763 a
single bounded HTTP client — streamed byte cap, connect timeout, request
deadline — plus magic-byte checks on stored images), provenance (#766 the
import hash, note author and logo bookkeeping are system-set and refused from
a request; #767 the unarmed tables as one closed named list), imports (#768
parser robustness, a row cap and a bounded preview store; #769 the skipped-row
report), web/API hygiene (#770 generic errors and input validation; #771
`limit` on four list reads, an upsert cap, and a per-source auth throttle), and
authentication (#764 the optional single-password UI login; #765 confirmations
on the four bare destructive controls). Tracker #757 closed by hand.

**The FR Coverage Map above is updated in this pass** (NFR-4–6 row: the
perimeter shipped, with what is still open named). The two-way-coverage ledger
stays **empty**: the batch's agent-visible capabilities shipped on API and MCP
together, and its human-only surfaces (the login, the confirmations, the
imports skip report) are human-only by nature. Deliberately not closed: #382
(CSP) and #772 (Bandit — the swap that removes cowlib and its three
advisories), both the next batch by the triage's own ruling; #727 (both
toolchain halves blocked upstream, triggers re-checked, none fired).

**The surface check caught its first gap.** `limit` reached
`GET /transactions`, `/securities`, `/exchange_rates` and
`/securities/:id/quotes` with their four MCP tools, and `/journal` has an
older bound of its own — but `/securities/:id/notes`, the three note-hygiene
reads, `/securities/:id/trades`, `/realized_gains`, `/snapshots`,
`/external_flows` and `/costs` grow with the ledger and carry none. The PR
briefing claimed the family was complete; checked against `mix phx.routes` at
close-out it was not. Filed as **#776** — the second read-ergonomics family to
ship half-done after FR-37 (#740), which is the pattern the clause was added
to catch.

Retrospective: `sprint-10-retro-2026-09-06.md`. Close-out ledger and process
findings live there and in `sprint-status.yaml`'s log; this section records
only what changed in the requirement registry.

## Implementation Status — reconciled with code (2026-09-03, Sprint 9 close-out)

Verification basis: the merge commits on `main` (8771702..6de32ff, PR #754
rebase-merged, 17 commits linear), the Actions runs on the merge push
(verified green), and the post-merge open-issue list.

**Shipped by Sprint 9** — ten issues closed by the merge's keywords: the
E20 knowledge batch under ADR-0044 (#748 the append-only `security_notes`
log journal-armed at creation, #749 the thesis state as a projection in the
security read, #750 append and the four reads over API and MCP, #751 the
Research tab on the detail pane in the same batch, #752 the contract-version
read with its inventory meta-test; tracker #747), the agent-round debt (#740
FR-37 on the view and position scopes, #741 the re-import guarantee
documented, #738 the README levelled), and the historical FX gap (#737, D-1:
the ECB series as a one-shot backfill, `scope=history`, a live control in the
Cash-flow exclusion notes). Sprint 9's Lane Z added the **surface check**
clause to AGENTS.md step 5 and `Portfolixir.Knowledge` to the architecture.

**The FR Coverage Map above is updated in this pass** (FR-37 row: #740
shipped, the family discharged on every read; FR-45 row: shipped, E20 done).
The two-way-coverage ledger stays **empty**: every agent-visible capability
of the batch shipped with its human view. Deliberately not closed: #727
(both toolchain halves blocked upstream; triggers re-checked, none fired).
FR-46 stays at gate B4.2; FR-39/FR-40 remain issue-ready and unfiled — the
research log now gives derived metrics a place to be cited from.

Retrospective: `sprint-9-retro-2026-09-03.md`. Close-out ledger and process
findings live there and in `sprint-status.yaml`'s log; this section records
only what changed in the requirement registry.

## Implementation Status — reconciled with code (2026-08-22, Sprint 8 close-out)

Verification basis: the merge commits on `main` (5fe43f6..125d656, PR #735
rebase-merged, 24 commits linear), the Actions run on the merge push
(verified green), and the post-merge open-issue list.

**Shipped by Sprint 8** — fourteen issues closed by the merge's keywords:
the two-way-rule debt (#731 `?since=` human view, #732 `fields=` column
picker — **discharged inside the deadline Sprint 7 set**), the #707
design-language execution (#717 filter chips as primary filter, #718 drift
card named, #719 Σ-pill retired for data notes, #720 view switcher named,
#721 custom range validation, #723 the earned computing cue), the Sprint-7
walkthrough findings (#729 locale-spoken built-in trees, #730 the reachable
subject column), the three Cash-flow facets (#724 realized gains under
decision D-1, #725 deposits & withdrawals, #726 costs at overview level by
requirement), and the Node pin (#728, with the `@types/node` major declined
and recorded). Sprint 8's closing act added **UX-DR25** and **UX-DR26** to
the living spec.

**The FR Coverage Map above is updated in this pass** (FR-37, FR-38, UX-DR
row): the two-way-coverage ledger is **empty** — no agent-only capability
awaits a human view, because the batch's new agent surfaces (three facet
endpoints and tools, `fields=` on securities) shipped with their views in the
same batch. Deliberately not closed: #727, now carrying **both** toolchain
halves blocked upstream — the OTP move on dialyzer opaqueness, and the
Elixir 1.20.3 move reverted mid-batch because `:cover` cannot instrument its
BEAMs, so the coverage gate cannot run (evidence and re-check triggers on
the issue). Filed from the batch: #737 (no path to store a historical FX
rate) and #738 (README predates Snapshots/Tax/performance).

Retrospective: `sprint-8-retro-2026-08-22.md`. Close-out ledger and process
findings live there and in `sprint-status.yaml`'s log; this section records
only what changed in the requirement registry.

## Implementation Status — structural migration (2026-08-18)

**ADR-0042 executed (Sprint 7, Lane Z).** This document stops being a work
breakdown and becomes the requirement registry.

- **Removed:** the Epic List table, all Epic Detail sections, and every
  `##### Story` row (E6's DX batch, E17, E18, E19 — 19 rows in total, which were
  the whole of this document's story breakdown across four of nineteen epics).
- **Added:** the Tracker Index below, condensing each epic's intent paragraph
  into one line with its tracker issue.
- **Kept unchanged:** the Requirements Inventory (FR/NFR/UX-DR), the FR Coverage
  Map, the scope-ladder boundaries, and every dated Implementation Status
  reconciliation above — the sections every review actually reads.
- **Elsewhere in the same pass:** `sprint-status.yaml` lost its story rows and
  now validates (`valid: true`, from `valid: false` on five schema-invalid keys);
  #321's working agreement moved into `AGENTS.md`; ADR-0027/0028/0029/0031 and
  `docs/development/pr-review-checklist.md` were repointed off the deleted
  sections; ADR-0039 gained its gate-B3.2 ask list per ADR-0043.

The standing two-parallel-structures finding — recorded at every reconciliation
from 2026-07-25 (F2, later F7) onward — is closed by this pass. #321 is closed
by hand with the reason: it was invalidated rather than implemented, so no
closing keyword applies to it.

## Tracker Index

**This section replaces the former Epic List and Epic Detail sections**
(ADR-0042, Accepted 2026-08-17). One line per epic: its name, its tracker issue
where one exists, and its intent. It is deliberately **not** a work breakdown —
that is the GitHub tracker set's job, and the two competing with each other is
the drift this decision removed. Requirement-to-work traceability lives in one
place, the FR Coverage Map's issue column above.

Ordering follows the PRD's five phases plus cross-cutting concerns, by the
maintainer priority: **data completeness & correctness first, LLM-first
consumption second, UI/sync/modeling later.**

Epic *status* is not carried here. It lives in `development_status` in
`_bmad-output/implementation-artifacts/sprint-status.yaml`, verified against
issue state and the merge commits on `main`.

- **E1 — Correctness & invariant foundations** — *phase 1, now.* No single
  tracker (issue list: #343, #344, #346, #347, #348, #350, #314). Harden the
  money/ledger core and the mechanical guards that protect everything else: the
  owner does not read code, so the gates are load-bearing. FR-1/2/3, NFR-1/3.
- **E2 — Auditability & data safety** — *phase 1, now.* No single tracker (#353
  FR-28, #354 FR-29). The two foundational gaps from the PRD review: an
  append-only journal intercepting every write path in the same DB transaction
  (architecture D1), and backup/restore plus a lossless PP-compatible roundtrip
  export so external copies can be retired safely. FR-28/29, NFR-2. #353
  sequences before #355 — MCP writes must be journaled.
- **E3 — Account & portfolio lifecycle** — *phase 1, now.* Tracker **#417**
  (portfolio structure). Multiple portfolios usable end to end: switcher and
  moving depots/accounts (#327), merge/rename/delete with transaction
  reassignment (#328), import data quality and logos (#326). FR-4, FR-7.
- **E4 — Import completeness** — *phase 1, XML gated.* Tracker **#470**
  (transactions/imports UX); the gated item is #333. Lossless PP XML import,
  **scope-gated**: it requires the AGENTS.md amendment plus an ADR before any
  implementation. CSV/JSON v1 is shipped. FR-5.
- **E5 — Analytics engine** — *phase 2, next.* Tracker **#418** (analytics). The
  read models the agent consumes: IRR alongside TTWROR (#316), income report
  (#331), and the allocation mechanics — target-consistency hints (#318),
  per-security exclusion (#329), cash in the 100 % basis (#335), classification
  value view (#334). FR-8/10/11.
- **E6 — LLM/MCP surface** — *phase 2, next.* Tracker **#419** (LLM/MCP). Make
  Portfolixir fully agent-operable: precomputed analytics over API and MCP (#349,
  FR-13) and data-maintenance tools at API parity (#355, FR-14) so an agent
  replaces manual entry — gated by the audit journal (#353). The 2026-07-18 DX
  batch (FR-30..33: all 13 kinds bookable, stable holding identifiers,
  booking semantics documented at the point of use, slim securities listing)
  shipped and closed. Its agent-native successors are FR-37/FR-38 in section J.
  FR-13/14/15/16.
- **E7 — Rebalancing guidance (gated)** — *phase 2, gated.* **No tracker and no
  issue** — it needs the guidance-vs-action scope decision first. FR-12,
  both-direction guidance ranked by drift. The binding constraint on any future
  issue: **it must never place or prepare orders.** ADR-0023 permits
  display-only corrective quantities beside the drift figure and nothing beyond.
- **E8 — Read-only sync (gated)** — *phase 3, gated/later.* No tracker (the former
  umbrella #320 closed 2026-09-23 as superseded, backlog triage §3.2).
  comdirect / bunq / bitcoin.de / watch-only acquisition (FR-17–21). **Hard
  scope gate B3.3:** AGENTS.md forbids broker/bank sync, and entering this epic
  requires an ADR plus an AGENTS.md amendment limited to *read-only* acquisition
  — the permanent non-goal is a connection that can act. OQ-4 (bitcoin.de) and
  OQ-6 (unattended-sync feasibility) are open.
- **E9 — Product-type modeling** — *phase 4, later, discovery-first.* No single
  tracker (#330 bonds, #340 pension parking lot). Per the PRD, **each modeling
  FR is preceded by its own discovery story** that fixes acceptance criteria
  before implementation. FR-22/24/25. Corporate actions (FR-23) moved to E17 on
  2026-07-18 — no double-tracking.
- **E10 — Planning & simulation** — *phase 5, later.* No single tracker (#332).
  What-if simulator (FR-27, gated at ladder level (d) since 2026-08-12),
  benchmark comparison (FR-9 — the founding "was it worth it?" question,
  ungated 2026-08-12 as ladder level (b), filed as #572; **its first shipped
  item**: the benchmark comparison, ADR-0046 signed 2026-09-07 and executed
  as signed in Sprint 11 — PR #810 merged 2026-09-15, #572 closed), retirement
  projection (FR-26, backs Success Metric 3, discovery-first).
- **E11 — UX & accessibility** — *cross-cutting, priority 3.* Tracker **#356**.
  Held against the living design-language spec (`design-language/DESIGN.md` +
  `EXPERIENCE.md`), which since ADR-0038 is the authority the design-critic
  review holds every user-visible batch against. UX-DR1–20; DR15–DR20 name the
  drift families the alignment stories are cut from. The first alignment pass
  was Sprints 7–8; **the second shipped with Sprint 12 (PR #813, merged
  2026-09-15), closing #784–#805**, cut from the 2026-09-12 whole-surface review
  (`planning-artifacts/ux-review-2026-09-12.md`, #784–#809 under this tracker).
  **The third pass closed the epic: Sprint 13 (PR #832, rebase-merged
  2026-09-19, `main` at `6e7de6ef`) shipped all six of the remainder** —
  #806–#809 plus the Sprint 12 closing act's #815–#817 — with #815 closed by
  hand as #808's duplicate and **tracker #356 closed with the evidence**.
  E11 does not reopen: further UX work is held against the living spec by the
  standing design-critic gate every user-visible batch passes (ADR-0038), not
  by a tracker, and this batch's own design findings that fell outside its
  scope are filed as #833–#837 and #842.
- **E12 — Localization & docs** — *cross-cutting.* No tracker (#313, closed).
  Multilingual docs site (NFR-7); the UI's de/en gettext coverage is shipped and
  enforced by `localization_test.exs`.
- **E13 — Buckets & views** — *now.* Tracker **#448**; decision in **ADR-0018**.
  Tag-based wealth scoping: separates **total wealth** (everything, counted
  once) from **per-view subsets** (strategy, rebalancing, per-person) with one
  primitive — overlapping **buckets** on holdings, consumed by named **views**
  whose totals are single-count and **never** the sum of buckets. Supersedes
  ADR-0013's per-security exclude flag.
- **E14 — CSS consistency & design-system hardening** — *priority 3.* Tracker
  **#451**. The UI read as inconsistent not because the design system was
  missing but because it existed and was neither enforced nor complete: tokens
  present alongside 57 hard-coded hex colours, no spacing scale, no heading
  ramp (UX-DR14). Enforcement is live —
  `test/invariants/css_token_discipline_test.exs` ratchets raw hex downward and
  fails the build on any new hard-coded colour.
- **E15 — View-bound SOLL plans** — *phase 2, next.* Tracker **#463**; decision
  in **ADR-0020**. A target **plan belongs to a view**: targets keyed by
  `(view, classification, category)` with `view_id NULL` as the portfolio-wide
  Gesamt plan, and the cash target moved into the plan. This fixes by
  construction the incoherence where two strategy views collided to ~200 % and a
  category with a target but no in-scope value rendered as a ghost row. Extends
  FR-11; API/MCP parity per AR-11.
- **E16 — Plan versions & depot snapshots** — *phase 2/5 bridge, next.* No
  tracker; decision in **ADR-0027** (signed off 2026-07-16, amended 2026-08-15
  for transaction costs → #708). Three decisions: a **snapshot is a ledger
  marker** (name, view scope, as-of date, no copied data — holdings derive by
  projecting the ledger, which ADR-0004 makes near-free); the **v1
  counterfactual is buy-and-hold** of the snapshot positions over real quote
  history against the view's real TTWROR since the as-of date; and **plans are
  named, versioned entities** (active/draft/archived, at most one active plan
  per ADR-0020 scope). Explicitly not in scope: old-plan rebalancing simulation
  and fictitious trades — that is FR-27.
- **E17 — Corporate actions as ledger events** — *phase 2/4 bridge.* Tracker
  **#338** (closed 2026-07-31); decision in **ADR-0028**. **Ledger events first,
  wizard second** — the daily operator is an MCP agent that cannot reach a UI
  wizard, and the event representation *is* projection semantics. Quote-history
  continuity is append-only adjustment factors, never mutated history (NFR-2).
  FR-23.
- **E18 — Stable identities & reconciliation** — *phase 2.* Tracker **#603**
  (closed 2026-07-31); decision in **ADR-0029**. A fresh PP import re-rolled IDs
  and orphaned the accumulated E13/E15/E16 strategy configuration. The epic makes
  that configuration survive a re-import, with the ISIN-less case (crypto,
  watch-only) and the ISIN-changed case settled in the same ADR. FR-34/35;
  import idempotency is risk-tier.
- **E19 — Recorded tax-statement snapshots** — *phase 2.* No tracker; decision in
  **ADR-0031** (gate #612 signed off 2026-07-25). The number a trim decision
  hangs on — how much realised equity gain is still free of
  Kapitalertragsteuer this year — **cannot be derived**: Portfolixir folds cost
  basis as a running average, German taxation mandates strict FIFO, and
  Teilfreistellung, Vorabpauschale, chronological allowance consumption and
  prior-year carry-forward are not in the transaction data at all. A derived pot
  would be wrong, and invisibly so. The epic therefore **records** the statement
  block as a dated snapshot and validates it against the closed § 32d Abs. 1
  EStG formula — a self-checking transcription. Forward projection and the
  `tax_bucket` attribute it needs sit behind their own gate. FR-36.
- **E20 — Security knowledge log** — *phase 3 (agent-first).* Tracker **#747**
  (#748–#752); decision in **ADR-0044** (signed 2026-09-03), scheduled by the
  Sprint 9 plan as Lane A. What an agent knows about a security is recorded as
  an **append-only** research log — dated, sourced, typed entries that are
  never updated and never deleted; a refuted finding is withdrawn by a
  retraction that supersedes it and both stay readable — and the B4.1 thesis
  state (thesis, status, conviction, invalidation condition, time stop, last
  reviewed) is a **projection** over that log, never maintained beside it.
  Four reads are the acceptance criteria (a security's log, positions
  unreviewed for N days, uncorroborated entries, blocks expiring within N
  days), the human timeline lands in the same batch, the table is journaled
  from its first migration, and the surface gains a contract-version read so
  an agent can notice the contract changed. FR-45 (FR-46 stays at B4.2).
- **E23 — Security events** — *phase 3 (agent-first), now.* Tracker **#822**,
  filed at branch opening (Sprint 13 Lane Z), with stories #826 (the journaled
  table), #827 (the four reads on API and MCP), #828 (the "Termine" tab and the
  "Fällig" card) and #829 (the re-import guarantee); decision in **ADR-0048** (gate B3.4,
  signed 2026-09-19 by the merge of the Sprint 13 planning PR), scheduled by
  the Sprint 13 plan as Lane E. A dated calendar fact about a security —
  earnings, ex-dividend and payment dates, lockup expiries, index reviews,
  shareholder meetings, regulatory decisions, guidance — that **books
  nothing**, and is therefore its own table rather than a ledger event
  (ADR-0028 is the other thing: a split changes a position). Two boundaries
  are structural: it covers **every security in the catalog by default**,
  because a purchase candidate with zero holdings is exactly the security
  whose dates matter, and entry is **manual or agent only** — nothing fetches
  a calendar (B3.3 stays shut), nothing alerts (B3.7) and nothing evaluates
  rules over it (B3.6). Four reads are the acceptance criteria; the table is
  journaled from its first migration and survives a PP re-import, pinned in
  the same batch. FR-44. **Done 2026-09-19 (PR #832, `main` at `6e7de6ef`)**:
  all four stories shipped with both human surfaces in the same batch, so
  ADR-0048's deferred-view clause never had to fire.
- **E22 — Derived metrics per security and per view** — *phase 2, done.* Tracker
  **#821**, filed at branch opening (Sprint 13 Lane Z), with stories #823 (the
  per-security engine, its read and its MCP tool) and #824 (the human view on
  the chart tab); #825 files the per-security invalidation basis that ADR-0047
  §8 names as the prerequisite for ever caching `security_metrics`; decision in **ADR-0047**
  (signed 2026-09-19 by the merge of the Sprint 13 planning PR), scheduled by
  the Sprint 13 plan as Lane A. Scope-ladder **level (a)**: moving averages,
  realized volatility, drawdown, momentum and distance to extremes per
  security; volatility, risk-adjusted return, maximum drawdown with its window
  and correlation among the largest positions per portfolio or view, added to
  the existing risk read rather than a second endpoint. The ladder released
  this level on 2026-08-12 and the derived-value mechanism landed in Sprint 7;
  what was missing for four sprints was a decision on **what a metric is
  measured over**, which is what the ADR settles — including the one invariant
  the epic exists for, that a deposit is not a return. Risk-tier. FR-39, FR-40;
  FR-41 and FR-42 are level (b) and stay unfiled, each needing its own
  argument. **Done 2026-09-23 (PR #846, `main` at `c0746222`)**: the per-
  security half shipped in Sprint 13, the portfolio and view half (#847),
  `required` (#838), the Risk tab (#848) and the per-security basis (#825) in
  Sprint 14; tracker #821 closed by hand.
- **E21 — Security hardening: perimeter, egress, provenance** — *cross-cutting,
  now.* Tracker **#757** (#758–#772); decisions in **ADR-0045** (signed
  2026-09-05) and the 2026-09-05 security review triage (D-3, D-4), scheduled
  by the Sprint 10 plan. The 2026-09-03 whole-system review found the system
  sound inside its trust boundary and the boundary itself unenforced: prod
  binds every interface, the documented deployment is the development
  configuration, nothing validates the request's Host, and an operator-supplied
  URL is fetched unchecked. The epic makes the perimeter real (Host guard,
  loopback by default, hardened session, production Compose, optional
  single-password UI authentication), bounds every outbound request, makes
  provenance fields system-set, and hardens the import parsers. CSP (#382),
  the Bandit swap (#772) and the `limit` surface (#776) shipped in Sprint 11
  (PR #810, merged 2026-09-15); the family is closed. NFR-4, NFR-2, NFR-10.
- **E24 — Policy rules** — *phase 3 (agent-first), done.* Tracker **#861**,
  filed at branch opening (Sprint 15 Lane Z) under area #418; decision in **ADR-0049** (gate
  B3.6, signed by the merge of the Sprint 15 planning PR), scheduled by the
  Sprint 15 plan as Lane A. The operator's caps, floors and bands stop living
  as prose in scheduled prompts: a rule is a stored predicate over a figure the
  product already serves, **versioned and effective-dated** so the standard in
  force on a date is a read rather than journal forensics, and evaluated at
  read into findings whose `undetermined` state never passes. A finding names
  the rule and the measured value and **carries no action** (key-set
  meta-test); the lens's generic thresholds and the operator's rules stay two
  mechanisms that never read each other. The operator's view lands in the same
  batch (pick F1). Flow rules (`protected`, `budget`) are deferred and filed;
  the rebalancing digest (B3.5), push delivery (B3.7) and replay (level (d))
  stay shut. FR-43; FR-48 becomes reachable without a findings store. **Done
  2026-09-24 (PR #867, `main` at `096b80e5`)**: all four stories shipped with
  the operator's view in the same batch as the API and MCP reads.
