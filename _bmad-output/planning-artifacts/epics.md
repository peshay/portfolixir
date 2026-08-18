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
- FR-42: **Exposure decomposition** (ladder level (b)): factor, sector and region exposure. Benchmark comparison is FR-9 and is not restated here. **Boundary against the still-forbidden advanced classifications** (`CONTRIBUTING.md`: splitting one security across categories with partial weights): this requirement *reports* a breakdown from data the catalog already holds. If a decomposition can only be computed by introducing stored partial-weight assignments, it is an advanced classification wearing a report's clothes and needs its own decision — the ladder released the analytics half of the old rule, not the classification half.
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
- NFR-4: Security boundaries — no in-app LLM calls; no trading/payment/order; read-only sync only; API/MCP via local bearer tokens; no secrets in source; web UI unauthenticated by design (trusted network / reverse-proxy; optional built-in auth OQ-8).
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
- AR-3 (D10/P3): IRR uses a contained float "island" (Newton's method) as the single named exception to Decimal discipline; boundaries convert back to Decimal. Must be encoded as an explicit, tested exception, not a loophole.
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
  never built, and the rule had contradicted the app since June.
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
| FR-5 | #333 | XML import **gated**; CSV/JSON shipped |
| FR-6 | — | shipped (preview/idempotent/atomic) |
| FR-7 | #326 | import gaps surfaced (logos) |
| FR-8 | #316, #577, #563, #568 (ADR-0034) | IRR; TTWROR shipped. **#577 shipped 2026-08-04** — TTWROR/IRR for a bucket view now cover the deduplicated account union across all portfolios, so the header total and the return always speak about the same accounts; the multi-portfolio scope disclaimer is gone. **#563 shipped** — previous-year/any-year and custom from-to periods, pure re-chains. #568 (net invested, wealth multiple, XIRR) has its design note in ADR-0034 but is **not implemented** |
| FR-9 | — | **future** (Phase 5; OQ-3 quote source). **Ungated 2026-08-12** — the scope ladder released it as level (b); the old advanced-reports gate no longer applies. Inherits the metric-basis rule |
| FR-10 | #331 | income report |
| FR-11 | #318, #329, #335, #334, #709 (ADR-0040), #712 (ADR-0041) | target hints, exclude flag, cash basis, classification view. **#709** — a target plan states its unallocated remainder explicitly and drifts against the allocated portion (ADR-0040, Accepted 2026-08-15). **#712** — a category row carries a money-weighted result roll-up, expandable to its member positions (ADR-0041, Accepted 2026-08-15); it is a statement about the *current composition*, so it needs no membership history and carries no restatement caveat |
| FR-12 | ADR-0023 | **partially landed** — display-only rebalancing hints (per-position drift share + indicative buy/sell quantity) shipped with the drift drill-down; the guidance-vs-action boundary is drawn in ADR-0023 + AGENTS.md. Ranked both-directions cash guidance remains open |
| FR-13 | #349 | analytics over API/MCP |
| FR-14 | **#355** | MCP data maintenance (new) |
| FR-15 | #355, #349 | LLM tool-choice descriptions |
| FR-16 | — | convention (API/MCP parity, PR review) |
| FR-17–21 | #320 | **gated** (Phase 3 sync, tracking) |
| FR-22 | #330 | bonds (Phase 4, discovery-first) |
| FR-23 | #338 (#588–#591) | corporate actions — ADR-0028 accepted 2026-07-19; #338 repurposed as the E17 tracker. #588–#591 shipped; #338 closed 2026-07-31 |
| FR-24, FR-25 | #340 | pension modeling (Phase 4, parked/discovery) |
| FR-26 | — | **future** (Phase 5 retirement projection). **Outside the scope ladder** — it projects forward rather than reporting the past, so the 2026-08-12 gate neither released nor gated it; open as PRD OQ-13. Not blocking: no issue, Phase 5 not started |
| FR-27 | #332 | what-if simulator. **Still gated after 2026-08-12**, on new grounds: blind-follow backtesting is ladder level (d), which is out for now and reopens after the policy-rules work (gate B3.6). OQ-11 (quotes for never-held securities) remains an independent blocker underneath |
| FR-28 | **#353** | audit journal (new) |
| FR-29 | #354 | **rescoped 2026-07-22**: documented `pg_dump` backup/restore only; PP export dropped |
| NFR-1 | #347, #348, #314, #344 | correctness suites + gates |
| NFR-2 | #353 | auditability = audit journal |
| NFR-3 | #346, #347, #350 | AI-agentic guards |
| NFR-4–6 | — | foundational (security, self-hosted, single-user) |
| NFR-7 | #313 | localization / docs site |
| NFR-8 | #562 (ADR-0032), #619 (ADR-0035) | cross-cutting perf; watch in perf-sensitive stories. ADR-0032 accepted 2026-07-29 — the daily TTWROR walk is memoized in volatile memory with warm-up, targeted invalidation and a labelled stale-serve. **#619 shipped 2026-08-04** (ADR-0035): the redundancy was removed rather than cached — market data is preloaded once per read and threaded through every valuation and allocation, replacing six re-derivations and hundreds of per-row lookups. Measured A/B: the warm dashboard block 1,105 ms → 265 ms and 2,614 → 115 queries, output identical. Nothing is memoized by this change; ADR-0032's memo is untouched |
| UX-DR1–20 | **#356** (tracker) + #414, #672 open, plus #701–#704, #707 filed 2026-08-15; #412, #491, #560, #565, #566 shipped | UX/a11y tracker. Rules are defined in `design-language/EXPERIENCE.md` and `DESIGN.md`, not in this document (ADR-0038). #336, #337, #339, #319 and #606 are closed. **#606 shipped 2026-08-04** — the impersonal microcopy voice rule, applied retroactively to all pre-rule UI strings and the EN/DE docs, and now part of DR11 rather than only an agent rule. DR15–DR20 were added by the 2026-08-05 design session; the alignment stories are cut from the spec |
| FR-30 | #582 | ISIN/WKN in holdings payloads (E6 DX batch, story 2) |
| FR-31 | #581 | MCP create: all 13 kinds, deliveries + price guard in AC (E6 DX batch, story 1) |
| FR-32 | #583 | booking-semantics docs incl. fix-it-hammer warnings (E6 DX batch, story 3) |
| FR-33 | #584 | slim `securities_list` projection, scope-locked (E6 DX batch, story 4) |
| FR-34 | #600, #601 | ADR-0029 accepted 2026-07-22 — identity ladder + alias record, risk-tier |
| FR-35 | #602 | ADR-0029 §6 verdict: build the read-only reconcile endpoint |
| FR-36 | #612 (gate), #621–#625 | recorded tax-statement snapshots — ADR-0031 accepted 2026-07-25. Stories 19.2–19.6 shipped: configuration layer, snapshot table, consistency engine, API/MCP parity, entry surface + EN/DE docs. Forward projection and `tax_bucket` (19.7) are deferred behind a separate gate |
| FR-37 | #665 | read ergonomics — sparse fieldsets, roll-up-only aggregates, server-side threshold filters. **Shipped 2026-08-14 (Sprint 6, PR #688)** with the −70 % volume cut pinned by test. Supersedes FR-33's scope lock for this family only. Agent-only; **the human view is due by the next batch per the two-way rule and is three obligations, not one** (`human-view-debt-2026-08-17.md`): `fields=` lives on the **transactions and holdings** endpoints and neither list has a column picker — the securities picker predates FR-37 and sits on the one list with no `fields=`, so it does **not** discharge this; the roll-up half is discharged by #712 if it ships; the threshold half is partial, with no drift control on the allocation surface |
| FR-38 | #666 | `?since=` delta reads. **Shipped 2026-08-14 (Sprint 6, PR #688)**, pull-only with the B3.7 boundary pinned by test; the push half stays gated at B3.7. Agent-only for now; the human view is due by the next batch per the two-way rule |
| FR-39, FR-40 | — (mechanism: #710, #711) | derived metrics per security / per view (ladder (a)). **Ungated by the ladder**, no issue yet — depended on the derived-value ADR (gate B3.2) for where the values live; ADR-0039 accepted 2026-08-12 supplies that home, and **the mechanism landed 2026-08-14 (C1–C5, Sprint 6, PR #688)** — these are issue-ready now. **#710 and #711 are the mechanism, not these metrics:** #710 moves the refresh onto the invalidating write, coalesced (ADR-0039 amendment §§1–3, **risk-tier** — an uncoalesced refresher turns one import into thousands of full recomputations, so import is the acceptance scenario), and #711 measures and activates the figures the operator actually waits on (§2 + amendment §4). Filing FR-39/FR-40 themselves is still open |
| FR-41, FR-42 | — | contribution analysis; factor/sector/region exposure (ladder (b)). **Ungated by the ladder**, no issue yet |
| FR-43 | — | policy rules as objects. **Gated: B3.6**, needs its own ADR (rules engine + rule-history retention) |
| FR-44 | — | security events as objects. **Gated: B3.4**; automatic population is B3.3. Distinct from ADR-0028 corporate actions |
| FR-45, FR-46 | — | thesis/conviction (**B4.1**) and prediction (**B4.2**) objects. Decided in principle by the identity gate |
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

## Epic List

Epics are organized by the PRD's five phases plus cross-cutting concerns, ordered by the maintainer priority (#321): **data completeness & correctness first, LLM-first consumption second, UI/sync/modeling later.** Each epic's stories are the GitHub issues above.

| Epic | Phase | Priority | Issues |
|---|---|---|---|
| **E1 — Correctness & invariant foundations** | 1 | now | #343, #344, #346, #347, #348, #350, #314 |
| **E2 — Auditability & data safety** | 1 | now | #353 (FR-28), #354 (FR-29) |
| **E3 — Account & portfolio lifecycle** | 1 | now | #327, #328, #326 |
| **E4 — Import completeness** | 1 | now (XML gated) | #333 |
| **E5 — Analytics engine** | 2 | next | #316, #331, #318, #329, #335, #334 |
| **E6 — LLM/MCP surface** | 2 | next | #349, #355 (FR-14) |
| **E7 — Rebalancing guidance** | 2 | gated | FR-12 (no issue — needs ADR first) |
| **E8 — Read-only sync** | 3 | gated/later | #320 |
| **E9 — Product-type modeling** | 4 | later (discovery-first) | #330, #338, #340 |
| **E10 — Planning & simulation** | 5 | later | #332, FR-9, FR-26 |
| **E11 — UX & accessibility** | — | priority 3 | #356, #336, #337, #339, #319 |
| **E12 — Localization & docs** | — | cross-cutting | #313 |
| **E13 — Buckets & views (ADR-0018)** | — | now | #448 (#443–#447) |
| **E14 — CSS consistency & design-system** | — | priority 3 | #451 (#449, #450) |
| **E15 — View-bound SOLL plans (ADR-0020)** | 2 | next | #463 (#464–#468) |
| **E16 — Plan versions & depot snapshots (ADR-0027)** | 2/5 bridge | next | ADR-0027 (decision gate; issues after sign-off) |
| **E17 — Corporate actions as ledger events** | 2/4 bridge | done (stories merged; tracker #338 closed 2026-07-31) | #338 (tracker), #588–#591 |
| **E18 — Stable identities & reconciliation** | 2 | done (stories merged; tracker #603 closed 2026-07-31) | #603 (tracker), #600–#602 |
| **E19 — Recorded tax-statement snapshots (FR-36)** | 2 | in progress (ADR-0031 accepted 2026-07-25, gate #612 signed off) | #621–#625 (19.2–19.6, merged); 19.7 deferred behind its own gate |

## Epic Detail

### Epic 1: Correctness & invariant foundations
Harden the money/ledger core and the mechanical guards that protect everything else (the owner does not read code, so gates are load-bearing). Currency consistency (#343), the rounding-policy ADR (#344, **decision needed from you**), CI quick wins (#346), invariant meta-tests (#347), domain-correctness suites (#348), the invisible-Unicode gate (#350), and the coverage ratchet (#314). FR-1/2/3, NFR-1/3.

### Epic 2: Auditability & data safety
The two foundational gaps from PRD review. **#353 (FR-28)** intercepts every write path with an append-only journal in the same DB transaction (architecture D1). **#354 (FR-29)** makes retiring external copies safe via backup/restore + a lossless PP-compatible roundtrip export. FR-28/29, NFR-2. Sequence #353 before #355 (MCP writes must be journaled).

### Epic 3: Account & portfolio lifecycle
Multiple portfolios usable end to end: switcher + move depots/accounts (#327), merge/rename/delete with transaction reassignment (#328), import data quality / logos (#326). FR-4, FR-7.

### Epic 4: Import completeness
Lossless PP XML import (#333) — **scope-gated**: requires the AGENTS.md amendment + ADR before implementation. CSV/JSON v1 is shipped. FR-5.

### Epic 5: Analytics engine
The read models the LLM consumes: IRR alongside TTWROR (#316), income report (#331), allocation mechanics — target-consistency hints (#318), per-security exclusion (#329), cash in the 100% basis (#335), classification value view (#334). FR-8/10/11.

### Epic 6: LLM/MCP surface
Make Portfolixir fully agent-operable. Expose precomputed analytics over API/MCP (#349, FR-13), and **#355 (FR-14)** for data-maintenance tools at API parity so an LLM replaces manual entry — gated by the audit journal (#353). FR-13/14/15/16.

**DX batch (added 2026-07-18, FR-30..33):** four small stories on the API/MCP
surface, ordered by operator pain: FR-31 (create all 13 kinds, delivery price
guard) → FR-30 (ISIN/WKN in holdings) → FR-32 (booking-semantics docs, incl.
fix-it-hammer warnings on `set_balance` and delivery tools) → FR-33
(scope-locked slim `securities_list`). **Entry criterion:** the
phantom-holdings fix branch (`claude/portfolixir-holdings-calculation-zfcqeh`)
is merged AND the operating LLM agent's live MCP re-verification (ledger
quantity vs. holdings per affected ISIN) is complete — FR-31 must not hand out
delivery-booking power against an instance still showing phantoms.
**Companion (not IN the batch):** a standalone risk-tier small PR making the
import applier persist the parsed `Kurs` on deliveries, so imported deliveries
stop entering the cost fold at zero — scheduled alongside the batch, reviewed
separately (projection semantics per AGENTS.md).

#### E6 DX batch stories (2026-07-18; each becomes one GitHub issue)

##### Story 6.DX-1: Book any transaction kind over MCP (FR-31)

As the operating LLM agent,
I want `transactions_create` to accept all 13 ledger kinds directly,
So that I can book dividends, deliveries and transfers without the
create-as-buy→update detour that transits through momentarily-wrong ledger
states.

**Acceptance Criteria:**

**Given** the MCP companion with a valid bearer token
**When** I call `transactions_create` with `type: "dividend"` (security, cash account, gross_amount)
**Then** the transaction is created in one call and the journal records the MCP actor
**And** the same holds for every one of the 13 kinds, explicitly including `inbound_delivery` and `outbound_delivery`
**Given** a delivery kind on MCP create
**When** I omit `price`
**Then** the MCP schema rejects the call (deliberately stricter than the JSON API, which stays PP-import-compatible)
**And** the tool description states: "a delivery without a price enters the cost basis at zero; supply the price for a correct cost basis"
**And** MCP tests cover one create per kind with synthetic fixtures; `balance_adjustment` stays excluded from the enum (the `set_balance` tool owns it)

##### Story 6.DX-2: Holdings carry stable identifiers (FR-30)

As the operating LLM agent,
I want ISIN and WKN on every holdings row (JSON API + MCP),
So that I can reconcile against broker data without a token-expensive
client-side join over `securities_list`.

**Acceptance Criteria:**

**Given** a portfolio with held positions
**When** I call `GET /api/v1/portfolios/:id/holdings` or the MCP holdings tool
**Then** each row includes `isin` and `wkn` (nullable, `null` when the security has none)
**And** the response shape stays backward-compatible (additive fields only)
**And** ConnCase + MCP tests assert the fields for a security with and one without ISIN

##### Story 6.DX-3: Booking semantics documented at the point of use (FR-32)

As the operating LLM agent,
I want the semantic traps written into the tool/schema descriptions I actually read,
So that I book correctly on the first attempt instead of learning by mis-booking.

**Acceptance Criteria:**

**Given** the MCP tool schemas
**When** I read the `transactions_create`/`transactions_update` descriptions
**Then** they state that a dividend's `gross_amount` is the NET cash credited (withheld taxes ride in `taxes`; the income report reconstructs gross)
**And** the `set_balance` and delivery tool descriptions carry the fix-it-hammer warning ("resolve differences by booking the missing transaction of the correct kind; balance snapshots and unpriced deliveries are last resorts that distort cost basis")
**And** no field is renamed (explicit non-goal)
**And** the API docs mirror the same semantics

##### Story 6.DX-4: Slim securities listing (FR-33)

As the operating LLM agent,
I want a slim default projection for `securities_list`,
So that routine listings stop paying tokens for logos and timestamps.

**Acceptance Criteria:**

**Given** the securities list endpoint/tool
**When** I request the default listing
**Then** rows carry a fixed slim whitelist (id, name, ISIN, WKN, ticker, currency, asset class) and omit logo/timestamp payloads
**And** the full projection stays reachable (parameter or dedicated detail call)
**And** scope lock holds: no generic field-selection framework — `securities_list` only

##### Story 6.C-1 (companion — standalone risk-tier PR, NOT in the batch): Imported deliveries keep their price

As a local portfolio maintainer importing PP history,
I want the applier to persist the parsed `Kurs` on delivery rows,
So that imported deliveries enter the cost fold with their real cost instead of zero.

**Acceptance Criteria:**

**Given** a PP CSV with an `Einlieferung` row carrying `Kurs`
**When** I apply the import
**Then** the created `inbound_delivery` stores that price and the holdings cost basis reflects it
**And** a `Kurs`-less delivery row still imports (price `nil`, zero cost — unchanged behavior)
**And** import idempotency is unaffected (content-hash regression test) — dedicated small PR, real human review

### Epic 7: Rebalancing guidance (gated)
FR-12, both-direction guidance ranked by drift. **No issue yet** — needs the guidance-vs-action ADR/AGENTS.md clarification first (it must never place or prepare orders). Create the issue after the scope decision.

### Epic 8: Read-only sync (Phase 3, gated)
comdirect/bunq/bitcoin.de/watch-only (FR-17–21), tracked in #320. **Hard scope gate:** AGENTS.md currently forbids broker/bank sync; entering this epic requires an ADR + AGENTS.md amendment limited to read-only acquisition. OQ-4 (bitcoin.de) and OQ-6 (unattended-sync feasibility) are open.

### Epic 9: Product-type modeling (Phase 4, discovery-first)
Bonds (#330) and German pension modeling (#340 parking lot). Per the PRD, **each modeling FR is preceded by its own discovery story** that fixes acceptance criteria before implementation. FR-22/24/25. *(Corporate actions — FR-23/#338 — moved to E17 on 2026-07-18; no double-tracking, #338 re-labels to E17.)*

### Epic 10: Planning & simulation (Phase 5)
What-if simulator (#332, FR-27), benchmark comparison (FR-9 — the founding "worth it?" question, needs OQ-3 quote source), retirement projection (FR-26 — backs Success Metric 3, discovery story fixes AC). Benchmark + retirement have no issues yet (future).

### Epic 11: UX & accessibility (priority 3)
Tracked in **#356** against the living design-language spec (`design-language/DESIGN.md` + `EXPERIENCE.md`), which since ADR-0038 is the authority a design-critic review holds every user-visible batch against. #336 (chart €/% toggle), #337 (dashboard v2), #339 (nav cleanup) and #319 (sunburst) are closed; open children are #414 (transactions overview), #471 (visible portfolio selector) and #672 (the `/cashflow` parent), plus #701–#704 and #707 filed 2026-08-15; #412 (forms and inputs), #491 (master-data creation UX), #565 (classification columns) and #566 (inline busy/result states instead of toasts) shipped 2026-08-14 in the Sprint 6 batch (PR #688), and **#560 (income chart on mobile) shipped 2026-08-10 via PR #656** — it was listed here as open until 2026-08-17, which is the error F5 of that day's reconciliation records. The 2026-08-05 design session supplies the specification these are held against, and DR15–DR20 name the drift families whose alignment stories are cut from it. Accessibility items (colour independence, contrast, modal focus, chart-as-table) break out as `agentic` issues when prioritized. UX-DR1–20.

### Epic 12: Localization & docs (cross-cutting)
Multilingual docs site (#313, NFR-7); UI de/en via gettext is shipped and enforced by `localization_test.exs`.

### Epic 13: Buckets & views (ADR-0018)
Tag-based wealth scoping from the 2026-06-18 design session (full decision in
ADR-0018). Separates **total wealth** (everything, counted once) from **per-view
subsets** (strategy, rebalancing, per-person) with one primitive: **buckets**
(overlapping tags on holdings; depot-default + per-position override) consumed by
named **views** (include/exclude filters; exclude wins; totals are single-count,
**never** the sum of buckets). Generalizes and will supersede ADR-0013 (the BTC
exclude flag). Tracked in **#448**; stories sequence #443 (data model) → #444
(engine scope) → #445 (API/MCP parity) → #446 (UI) → #447 (retire the old flag).
Holding removal ("remove a non-owner entirely") is explicitly out of scope → #328.

### Epic 14: CSS consistency & design-system hardening
The UI feels inconsistent not because the design system is missing but because
it **exists yet isn't enforced or complete**. Findings (2026-06-18): the
`--color-*` tokens exist but **57 raw hex colours** are hard-coded outside token
definitions; **no spacing scale** (`--space*`) or heading ramp (UX-DR14); a dead
`.mono` class. **Enforcement landed**: `test/invariants/css_token_discipline_test.exs`
ratchets raw hex down and fails the build on any new hard-coded colour. Tracked
in **#451**; stories #449 (hex→tokens, ratchet to zero) and #450 (4px spacing
scale + heading ramp, UX-DR14 break-out). Related: #412 (forms + dead `.mono`),
#411 (chart accent), #356 (UX tracker). UI priority 3 per #321, but the guard is
cross-cutting and already active.

### Epic 15: View-bound SOLL plans (ADR-0020)
From a design session 2026-06-20 (Andi), recorded in **ADR-0020**. Follow-on to
E13 (buckets & views, ADR-0018) and the retirement of the per-security exclude
flag (#447). Since #444 the **IST** side of the SOLL/IST allocation is
view-scoped, but the **SOLL** (target weights + the global `cash_target_weight`)
stayed global per classification — so two strategy views cannot each be a
coherent 100% plan (their targets collide to ~200%), and a category with a target
but no in-scope value renders as a ghost row under any view. ADR-0020 makes a
target **plan belong to a view**: targets keyed by `(view, classification,
category)` with `view_id NULL` = the portfolio-wide **Gesamt** plan; the cash
target moves into the plan; a view may carry its own plan or none (→ IST-only).
The active view loads only its own plan, fixing the 200%/ghost-row incoherence by
construction. Editing lives on the classifications page (with a view selector),
viewing on the portfolio page (driven by the #446 view switcher), with a deep-link
between them. Migration is loss-free (existing targets + cash target → the Gesamt
plan). Tracked in **#463**; stories sequence #464 (data model + migration) → #465
(engine) → #466 (API/MCP) → #467 (editor UI) → #468 (viewer UI + docs). Extends
FR-11; API/MCP parity per AR-11.

### Epic 16: Plan versions & depot snapshots (ADR-0027)
From the owner design conversation 2026-07-16, recorded in **ADR-0027**
(decision gate per ADR-0026 — signed off by the owner 2026-07-16). The owner's
workflow:
duplicate a target plan to restructure it while the old plan stays visible,
freeze the depot state at the strategy change, and later compare real
performance against "what if I had kept my old holdings?".

Three decisions: (1) a **snapshot is a ledger marker** — name + view scope +
as-of date, no copied data; holdings/cost basis derive by projecting the ledger
up to the date (ADR-0004 makes snapshots near-free); (2) the **v1
counterfactual is buy-and-hold** of the snapshot positions over real quote
history, compared against the view's real TTWROR since the as-of date (TTWROR
neutralises flows, so no fresh-money detection is needed; gross, price-return
only — distributions are a labeled follow-up); (3) **plans become named,
versioned entities** (active/draft/archived, duplicate-to-edit, at most one
active plan per ADR-0020 scope; loss-free migration). Journal-arming for the
Targets/Plans context (open ADR-0017 slice) rides in the same epic.

Story cut (issues created after sign-off): plan versioning (data model +
migration + journal arming) → snapshot entity (create/list/delete) → snapshot
valuation engine (pure engine, AR-2) → comparison view (chart + table,
UX-DR10/11) → API/MCP parity (AR-11) + docs. Deliberately NOT in scope:
old-plan rebalancing simulation and fictitious trades — that is FR-27 (#332),
which later layers scenario trades on a snapshot base (AR-8;
`audit_journal.scenario_id` forward-index). Extends FR-11 toward FR-27.

### Epic 17: Corporate actions as ledger events (FR-23, ADR-gated)
Extracted from E9 on 2026-07-18 (LLM field feedback + elicitation round;
priority "later" → "next"). **Ledger events first, wizard second** — the daily
operator is an MCP agent that cannot reach a UI wizard, and the event
representation IS projection semantics. The decision-gate ADR must settle:
(a) event representation — first-class kind vs. composed existing kinds — and
its `Projection.effects/1` clause (AR-7 no-catch-all, migration immutability,
PP round-trip FR-5/FR-29 impact); (b) quote-history continuity as APPEND-ONLY
adjustment factors, never mutated history (NFR-2); (c) the ISIN-change case,
cross-referenced with the FR-34 ADR. API/MCP booking + read parity (AR-11) is
an acceptance criterion of the event layer, not an afterthought. Delivery
split by risk tier: projection/ledger changes land as dedicated small PRs
(risk-tier per AGENTS.md); the guided wizard UI (split → rename/ISIN change →
merger/spin-off, in that slice order; splits ONLY in the first ADR slice) may
ride the epic batch. The E17 ADR may be DRAFTED in parallel to the E6 DX
batch, but at most one risk-tier review is in flight at any time.

#### E17 stories

> Status 2026-07-19: ADR-0028 drafted, hardened by a three-method adversarial
> review (red team vs blue team, pre-mortem, edge-case walk) and **accepted by
> the owner** — Story 17.1 is complete. Issues created as thin pointers (the
> ADR and this document stay the single source of truth): #338 (tracker),
> #588 (E17.0 sync-vs-manual-quotes precondition, added by the review),
> #589 (17.2), #590 (17.3), #591 (17.4).

##### Story 17.1: Corporate-actions decision ADR (gate)

As the accountable owner,
I want one ADR that settles how corporate actions live in the ledger,
So that every later slice implements a reviewed model instead of improvising
projection semantics.

**Acceptance Criteria:**

**Given** the pre-seeded question list
**When** the ADR is drafted (parallel to the E6 batch is allowed)
**Then** it decides: event representation (first-class kind vs. composed
kinds) incl. the `Projection.effects/1` clause, AR-7/migration-immutability
and PP round-trip (FR-5/FR-29) impact; quote-history continuity as
APPEND-ONLY adjustment factors (never mutated history, NFR-2); the
ISIN-change case cross-referenced with the FR-34 ADR; API/MCP booking + read
parity (AR-11) as a binding acceptance criterion of the event layer
**And** splits are the ONLY action modeled in this first slice (rename and
merger/spin-off are named follow-on slices)
**And** the owner signs off before any implementation story starts

##### Story 17.2: Book a split as a ledger event (risk-tier)

As a local portfolio maintainer (and the MCP agent acting for me),
I want to record a stock split as a reproducible ledger event via API and MCP,
So that quantities before and after the split are both true and derived, not
hand-edited.

**Acceptance Criteria:**

**Given** a held position of 10 shares and a recorded 1:10 split event per the ADR's representation
**When** holdings are derived
**Then** the position shows 100 shares with an unchanged total cost basis (per-share cost divided accordingly), exact-Decimal
**And** the event books identically through JSON API and MCP (AR-11), is journaled, and round-trips the PP export/import path or documents the mapping
**And** projection changes land as dedicated small PRs (risk-tier)

##### Story 17.3: Continuous charts across a split

As a local portfolio maintainer,
I want price history to display continuously across a split,
So that charts stop showing a fictitious 90% crash on split day.

**Acceptance Criteria:**

**Given** stored raw quotes and a split event
**When** the security detail chart renders
**Then** displayed history applies the append-only adjustment factor (raw quotes stay immutable, NFR-2)
**And** the chart-as-table view (UX-DR10) shows adjusted values with the basis stated (UX-DR11)

##### Story 17.4: Guided split wizard (UI layer)

As a local portfolio maintainer working in the UI,
I want a guided flow that records a split with preview,
So that I can book the event without knowing the ledger representation.

**Acceptance Criteria:**

**Given** a security detail page
**When** I start the split wizard, enter ratio and date, and confirm the previewed effect (quantities before/after)
**Then** the same ledger event as Story 17.2 is created — the wizard is a UI layer over the event, never a second write path
**And** the flow meets modal-accessibility requirements (UX-DR9)

### Epic 18: Stable identities & reconciliation (FR-34/35, ADR-gated)
A fresh PP import re-rolls IDs and orphans the owner's strategy configuration
(classifications, target plans, cash target — the accumulated E13/E15/E16
investment). One decision-gate ADR (FR-34) settles: ISIN-keyed stable identity
vs. strategy-config export/import, WITH the mandatory fallback question for
ISIN-less securities (crypto/watch-only) and the ISIN-changed case (E17
cross-reference). FR-35 (read-only reconcile, boundary pinned in its FR text:
user-supplied paste/file only, no network acquisition, nothing persisted,
resolution guidance embedded in the response) rides as a SECTION of that same
ADR — one owner decision session, not a second gate — and may close as
"documented procedure, no feature" if FR-30 plus the agent's established
reconcile procedure already covers the need. Epic ACs: the golden-path
re-import round-trip test (exact-Decimal survival of strategy config);
dependency on E16's Targets/Plans journal arming before any E18 write path.
Import idempotency → **risk-tier**; both E18 gates come strictly after the
E17 ADR (reviewer WIP limit — the owner is one person).

#### E18 stories (issues created after ADR sign-off)

##### Story 18.1: Stable-identity decision ADR (gate, includes the FR-35 section)

As the accountable owner,
I want one decision session that settles re-import identity AND the reconcile
question,
So that my strategy configuration stops being disposable without queueing two
separate gates on my desk.

**Acceptance Criteria:**

**Given** the FR-34 options (ISIN-keyed identity vs. strategy-config export/import)
**When** the ADR is drafted (after the E17 ADR, per the WIP rule, with a recommended option)
**Then** it decides the identity mechanism INCLUDING the fallback for ISIN-less securities (crypto/watch-only) and the ISIN-changed case (E17 cross-reference)
**And** its FR-35 section delivers a verdict: build the read-only reconcile endpoint (boundary as pinned in FR-35) OR close it as a documented agent procedure — both outcomes are acceptable
**And** the owner signs off in one session

##### Story 18.2: Strategy configuration survives a re-import (risk-tier)

As a local portfolio maintainer,
I want classifications, target plans and the cash target to survive a fresh PP import,
So that redoing my bookkeeping never destroys my strategy work.

**Acceptance Criteria:**

**Given** an imported fixture with attached classification, target plan and cash target
**When** I re-import a mutated version of the same PP export (the golden-path mutated re-import)
**Then** the surviving strategy configuration matches exactly (golden-path DataCase test, exact-Decimal equality)
**And** ISIN-less securities follow the ADR's fallback and any unmatched leftovers are SURFACED, not silently dropped (FR-7)
**And** all migration writes are journaled (depends on E16's Targets/Plans journal arming) and land as dedicated small PRs (risk-tier)

##### Story 18.3 (conditional on the 18.1 verdict): Read-only holdings reconcile

As the operating LLM agent,
I want to submit a user-supplied external position list and get a holdings diff,
So that discrepancies surface as bookable facts instead of guesses.

**Acceptance Criteria:**

**Given** pasted/file-supplied position data (ISIN + quantity)
**When** I call the reconcile endpoint/tool
**Then** I get per-ISIN deltas against ledger-derived holdings, read-only, with the external list never persisted and no network acquisition (NFR-4 boundary as pinned in FR-35)
**And** the response embeds the resolution guidance ("book the missing transaction of the correct kind; balance snapshots and unpriced deliveries are last resorts")
**And** API/MCP parity (AR-11) and synthetic-fixture tests hold

### Epic 19: Recorded tax-statement snapshots (FR-36, ADR-0031)

The number the owner actually hangs a trim decision on — how much realised
equity gain is still free of Kapitalertragsteuer this year — lives on the
broker's tax statement and is re-read out of PDFs by hand every time the
question comes up. It cannot be derived: Portfolixir folds cost basis as a
running average, German taxation mandates strict FIFO, and Teilfreistellung /
Vorabpauschale / chronological allowance consumption / prior-year carry-forward
are not in the transaction data at all. A derived pot would be wrong, and
invisibly so.

The epic therefore **records** the statement block as a dated snapshot per
(institution, holder, tax year, as-of) and validates it against the closed
§ 32d Abs. 1 EStG formula — a self-checking transcription at nearly zero extra
cost. Around it sit three configuration tables that exist because none of this
is constant: year-scoped statutory `tax_parameters` (the Sparer-Pauschbetrag
alone changed in 2023, so constants cannot validate an older statement), an
effective-dated `tax_profiles` row per taxpayer (church tax defaults to **not
liable**; state, marital status and church membership change on a date and must
not rewrite the past), and configured `allowance_orders` so the Freistellungs-
auftrag is comparable against what the bank actually applied. Forward projection and the `tax_bucket` security attribute it needs are
deliberately OUT of this epic and behind their own gate. Epic ACs: every write
journaled (FR-28/AR-1), every money column Decimal (ADR-0003), API/MCP parity
(AR-11), EN/DE documentation, and no number ever presented as a computed pot
balance. Not risk-tier — no ledger, projection or import-idempotency change —
but it is money-domain data and reviewed as such.

#### E19 stories (issue numbers backfilled 2026-07-31; 19.2–19.6 merged in 02dde3b)

##### Story 19.1 (#612): Tax-statement snapshot decision ADR (gate)

As the accountable owner,
I want the recorded-not-derived stance, the schema and the validation rules
settled in one decision,
So that the tax numbers enter the app as honest transcriptions instead of
plausible-looking derivations.

**Acceptance Criteria:**

**Given** the FIFO-vs-average-cost disqualifier and the four inputs absent from transaction data
**When** ADR-0031 is reviewed
**Then** it fixes the `tax_statement_snapshots` schema (identity keys, the eleven money columns, the magnitude sign convention, the uniqueness rule) and the `Portfolixir.Tax` context boundary including the `AGENTS.md` Active-Architecture amendment
**And** it fixes the configuration layer that has to survive time: year-scoped `tax_parameters`, effective-dated `tax_profiles` with church-tax liability defaulting to not-liable, and configured `allowance_orders`
**And** it fixes the hard-vs-advisory split of the consistency rules and the tolerance band
**And** it names forward projection and `tax_bucket` as deferred behind a separate gate
**And** the owner signs off in one session

##### Story 19.2 (#621): Tax parameters, taxpayer profile and configured Freistellungsaufträge

As a local portfolio maintainer,
I want the statutory numbers and my own tax situation to be data with a
validity period rather than constants in the code,
So that a statement from an earlier year still validates correctly and a change
in my situation does not rewrite the past.

**Acceptance Criteria:**

**Given** the seeded `tax_parameters` rows per (jurisdiction, tax_year)
**When** the consistency engine evaluates a snapshot
**Then** it receives the year's rates and Sparer-Pauschbetrag ceilings as an argument and hardcodes nothing — a pre-2023 statement validates against 801/1.602 €, a 2023+ statement against 1.000/2.000 €
**And** `tax_profiles` is effective-dated per (holder, valid_from): church-tax liability defaults to **not liable**, the rate is 0 in that case (DB CHECK), and single/joint assessment selects the ceiling
**And** a snapshot resolves the profile in force at its `as_of` and freezes the resulting church-tax rate on its own row, so later profile edits change future prefills and never a recorded transcription (asserted by test)
**And** `allowance_orders` records the instructed amount per (holder, institution, tax_year)
**And** all four write paths are journaled, including `tax_parameters` — a rate edit changes every finding for that year and must be traceable

##### Story 19.3 (#622): Record a tax-statement snapshot

As a local portfolio maintainer,
I want to record the tax block of a broker statement with its as-of date,
So that the loss pots and the remaining allowance are auditable local data
instead of a PDF I have to find again.

**Acceptance Criteria:**

**Given** the eleven statement figures for an institution, holder and tax year
**When** I record them with the statement's position date
**Then** the row is stored with Decimal values, non-negative magnitudes, and a unique (institution, holder, tax_year, as_of) key
**And** the write is journaled with the acting actor, enforced by the journal trigger (an unjournaled write fails loudly)
**And** a negative input and an `as_of` in the future are rejected with a message naming the convention — never silently normalised

##### Story 19.4 (#623): A recorded snapshot checks its own arithmetic

As a local portfolio maintainer,
I want a transposed digit or a stale statement to surface when I record it,
So that a wrong number does not sit in the app looking correct.

**Acceptance Criteria:**

**Given** a recorded snapshot
**When** the consistency engine evaluates it
**Then** `allowance_used > allowance_granted` and church tax withheld at a zero church-tax rate are hard changeset errors
**And** the withheld Kapitalertragsteuer, Solidaritätszuschlag and Kirchensteuer are reconstructed via `(e − 4q)/(4 + k)`, `× 5.5 %` and `× k`, with disagreement outside `max(1.00, 0.05 %)` reported as an advisory that names both numbers and the gap
**And** a later as-of reporting lower year-to-date withheld tax or allowance use raises the monotonicity advisory
**And** a recorded `allowance_granted` that disagrees with the configured `allowance_orders` row raises the instruction-vs-reality advisory (C7)
**And** configured allowance orders summing above the year's statutory ceiling for the profile's assessment type raise the budget advisory (C8)
**And** no advisory blocks the save, and no advisory proposes a corrected value
**And** the engine is pure — no Repo, no clock, no config (AR-2) — with exact-Decimal fixtures

##### Story 19.5 (#624): Trim budget over API and MCP

As the operating LLM agent,
I want the recorded snapshots and the derived trim budget over the API and MCP,
So that I can size a trim without scraping PDFs.

**Acceptance Criteria:**

**Given** recorded snapshots
**When** I list or fetch them over `/api/v1/tax/statement-snapshots` or the matching `portfolixir.tax_snapshots.*` tools
**Then** every financial decimal serialises as a string and the payload carries `allowance_remaining`, `tax_free_trim_budget`, the `as_of` basis and the consistency findings
**And** the tool description states that the pots are recorded, not derived, and why (FIFO), so the agent does not attempt to compute them from holdings
**And** create/update/delete reach full API/MCP parity (AR-11) with tests on synthetic fixtures only

##### Story 19.6 (#625): Entry surface and documentation

As a local portfolio maintainer,
I want to enter and review the snapshots in the app,
So that recording a new statement is a two-minute job once a year.

**Acceptance Criteria:**

**Given** the tax-snapshot surface
**When** I record, edit or review a snapshot
**Then** the pots render with the statement's printed sign so the row is visually comparable to the paper, while storage stays magnitudes
**And** the trim budget is stated with its as-of date and marked stale once newer investment income can have landed
**And** consistency advisories are shown as fact-plus-remedy, terse and impersonal, with domain terms behind ⓘ tooltips (UX-DR11)
**And** `product-documentation.md` and its German mirror gain a section stating that these numbers are recorded, that they are not tax advice, and that the recorded statement remains the authority

##### Story 19.7 (deferred, separate gate): Forward projection and `tax_bucket`

As a local portfolio maintainer,
I want an estimate of where the pots stand since the last statement,
So that a mid-year trim decision is not anchored on a months-old number.

**Acceptance Criteria:**

**Given** a separate accepted ADR for the projection
**When** the projection runs forward from the latest snapshot
**Then** securities carry a `tax_bucket` (`equity`/`other`/`tax_free`) set explicitly, never inferred from `asset_class`
**And** the result is labelled as an estimate with its drift basis and as-of ("estimated, drift since the snapshot of <date>"), never as a pot balance
**And** the display-only boundary (ADR-0023) is unchanged
