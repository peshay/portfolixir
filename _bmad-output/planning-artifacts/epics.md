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
---

# Portfolixir - Epic Breakdown

## Overview

This document provides the complete epic and story breakdown for Portfolixir, decomposing the requirements from the PRD, UX Design, and Architecture into implementable stories.

**Brownfield note:** Portfolixir is an existing Elixir/Phoenix modular monolith — there is NO greenfield/starter-template story. Epic 1 builds on the established codebase (ledger projection, imports, JSON API, MCP companion). The architecture defines a delta tree of *additions* to existing contexts, not a new scaffold.

## Requirements Inventory

### Functional Requirements

**A. Ledger & data integrity**
- FR-1: All financial state derives from the transaction ledger (13 PP kinds + balance adjustments); holdings, balances, performance are projections, never stored.
- FR-2: The system rejects inconsistent records: currency mismatches (#343), invalid kinds, signed amounts where magnitudes are required.
- FR-3: A written rounding policy governs every Decimal operation (#344); all money math is Decimal-exact end to end.
- FR-4: Portfolios partition the wealth space; every view/analytic can be scoped to one portfolio (UJ-6). Depots and cash accounts move between portfolios (#327) and merge/rename/delete with transaction reassignment (#328).
- FR-28: Every write to financial data (UI/API/MCP) is recorded in an append-only audit journal: actor, timestamp, operation, before/after. Queryable via API and MCP; deletions remain traceable.

**B. Import & reconciliation**
- FR-5: PP exports import losslessly: CSV/JSON v1 (shipped) and XML with classifications, quote history, master data (#333). **Scope gate:** XML intake requires AGENTS.md amendment + ADR.
- FR-6: Imports are previewed, idempotent (content-hash; re-import no-op), and atomic.
- FR-7: Import gaps are surfaced, not silently defaulted: unclassified securities, missing logos (#326), unknown kinds.
- FR-29: Documented backup/restore + full PP-compatible export (roundtrip Portfolixir → PP → Portfolixir), via UI and MCP. Ships before/with the workflows it replaces.

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

**FR-23 sharpened (no new FR):** corporate actions are **ledger events first, wizard second** (reframed 2026-07-18 after stakeholder round table + inversion analysis: a UI wizard is unreachable for the MCP-first operator, and the event representation IS projection semantics). The E17 ADR must decide the event representation (first-class kind vs. composed existing kinds), its projection semantics, and quote-history continuity as APPEND-ONLY adjustment factors (never mutated history — NFR-2), and mandates API/MCP booking + read parity (AR-11) in the acceptance criteria. The guided wizard (split, rename/ISIN change, merger/spin-off) is the subsequent UI layer. Scope lock: splits ONLY in the first ADR slice; rename/ISIN-change (cross-referenced by the FR-34 ADR) and merger/spin-off are follow-on slices. Priority raised from "later" to "next": a split silently distorts every chart and holdings figure, and no delivery pair can compensate for that. The phantom-holdings defect formerly motivating urgency here was a projection bug, not a missing feature — fixed 2026-07-18 (see reconciliation below), NOT part of this feature scope.

### NonFunctional Requirements

- NFR-1: Correctness over features — Decimal-only persistence, exact-value tests, invariant meta-tests, quality-gate roadmap are release-blocking.
- NFR-2: Auditability — every number reproducible from immutable inputs; editing allowed, hidden state not; enforced by FR-28.
- NFR-3: AI-agentic development guards — CI gates incl. invisible-Unicode/Trojan-Source rejection (#350); scope changes only via ADR + AGENTS.md amendment.
- NFR-4: Security boundaries — no in-app LLM calls; no trading/payment/order; read-only sync only; API/MCP via local bearer tokens; no secrets in source; web UI unauthenticated by design (trusted network / reverse-proxy; optional built-in auth OQ-8).
- NFR-5: Self-hosted operations — docker-compose, PostgreSQL only store, always-on; MCP companion installable separately.
- NFR-6: Single-user tenancy — one instance, one operator; portfolio-scoped filtered views.
- NFR-7: Localization — UI de/en via gettext; repository artifacts in English.
- NFR-8: Performance — interactive views and MCP analytics p95 < 2 s at realistic scale (hundreds of securities, tens of thousands of transactions).

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

(From DESIGN.md + EXPERIENCE.md — paradigm: classic-but-decluttered, progressive disclosure)

- UX-DR1: Decluttered Classifications screen — the tree IS the surface; New-category form behind the `+` affordance; multiselect toolbar only with active selection; per-node edit/recolor/delete. (Worst-rated screen; the decluttering exemplar.)
- UX-DR2: Analysis-dashboard home — hero (total value + performance curve) with €/% series toggle; the four confirmed metric cards (cash quote, TTWROR vs. period, top drift category, transactions recency), each navigating to its owning surface.
- UX-DR3: Progressive-disclosure pass across all surfaces — creation/edit forms move out of primary sightline into modals/popovers/collapsed sections (generalize the `.inline-form` removal).
- UX-DR4: Hidden "Soon" nav items — sidebar shows only working surfaces; entries return when their surface ships.
- UX-DR5: Chart build-in motion — one-shot on load/data-change (~600ms–1.5s, ease-out), polish only, never looping; CSS/SVG techniques (stroke-dashoffset draw-in, scaleY bar grow, @property count-up); ALL motion gated behind `prefers-reduced-motion: no-preference`; loading cues stay (non-animated under reduce).
- UX-DR6: Touch targets ≥44px via `@media (pointer: coarse)`; desktop keeps 32–34px density.
- UX-DR7: Color independence (binding) — gain/loss, SOLL/IST drift, buy/sell never conveyed by hue alone: explicit +/− (or ▲/▼), ▲buy/▼sell marker shapes, stale-quote clock glyph + text.
- UX-DR8: Contrast commitments (binding) — `text-subtle` barred from content (disabled/decoration only); coral accent as large text only; documented contrast floors per surface in both themes; tx-buy darkened in light mode.
- UX-DR9: Modal accessibility — native `<dialog>`/`showModal()` (focus trap + Esc) or `role="dialog" aria-modal="true"` + focus-trap hook; focus to first field/heading on open; Esc-close + focus-return-to-trigger.
- UX-DR10: Chart-as-table (binding) — the data behind every chart is always also reachable as a table (makes single-`aria-label` + 9px axis acceptable); charts carry `role="img"` + `aria-label`.
- UX-DR11: Explanatory microcopy — domain terms (TTWROR, IRR, SOLL/IST drift, cash quote) carry focusable ⓘ tooltips (focus + tap, Esc-dismiss, hoverable per WCAG 1.4.13); numbers state basis (as-of date, currency, gross/net); de/en via gettext; `lang` follows active locale (binding).
- UX-DR12: Responsive behavior — breakpoints 900 (off-canvas sidebar) / 720 (single-column dialogs, bottom-sheet kebab) / 560 (14px base, hidden subtitles, horizontal table scroll); same IA across surfaces.
- UX-DR13: State patterns — filter/search no-match state ("No matches for X", controls visible); form error association (`aria-describedby`, `aria-invalid`, focus to first invalid, `role="alert"`); data-freshness display (as-of basis, stale tone + glyph).
- UX-DR14: Design-system foundations (redesign groundwork) — define the missing 4px-based spacing scale and the heading ramp between top-bar (15px) and page-title (28px+); locale-switcher pill text ≥11px.

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
| FR-8 | #316 | IRR; TTWROR shipped |
| FR-9 | — | **future** (Phase 5; OQ-3 quote source) |
| FR-10 | #331 | income report |
| FR-11 | #318, #329, #335, #334 | target hints, exclude flag, cash basis, classification view |
| FR-12 | ADR-0023 | **partially landed** — display-only rebalancing hints (per-position drift share + indicative buy/sell quantity) shipped with the drift drill-down; the guidance-vs-action boundary is drawn in ADR-0023 + AGENTS.md. Ranked both-directions cash guidance remains open |
| FR-13 | #349 | analytics over API/MCP |
| FR-14 | **#355** | MCP data maintenance (new) |
| FR-15 | #355, #349 | LLM tool-choice descriptions |
| FR-16 | — | convention (API/MCP parity, PR review) |
| FR-17–21 | #320 | **gated** (Phase 3 sync, tracking) |
| FR-22 | #330 | bonds (Phase 4, discovery-first) |
| FR-23 | #338 (#588–#591) | corporate actions — ADR-0028 accepted 2026-07-19; #338 repurposed as the E17 tracker |
| FR-24, FR-25 | #340 | pension modeling (Phase 4, parked/discovery) |
| FR-26 | — | **future** (Phase 5 retirement projection) |
| FR-27 | #332 | what-if simulator |
| FR-28 | **#353** | audit journal (new) |
| FR-29 | **#354** | backup + PP export (new) |
| NFR-1 | #347, #348, #314, #344 | correctness suites + gates |
| NFR-2 | #353 | auditability = audit journal |
| NFR-3 | #346, #347, #350 | AI-agentic guards |
| NFR-4–6 | — | foundational (security, self-hosted, single-user) |
| NFR-7 | #313 | localization / docs site |
| NFR-8 | — | cross-cutting perf; watch in perf-sensitive stories |
| UX-DR1–14 | **#356** + #336, #337, #339, #319 | UX/a11y tracker (UI = priority 3) |
| FR-30 | #582 | ISIN/WKN in holdings payloads (E6 DX batch, story 2) |
| FR-31 | #581 | MCP create: all 13 kinds, deliveries + price guard in AC (E6 DX batch, story 1) |
| FR-32 | #583 | booking-semantics docs incl. fix-it-hammer warnings (E6 DX batch, story 3) |
| FR-33 | #584 | slim `securities_list` projection, scope-locked (E6 DX batch, story 4) |
| FR-34 | tbd | **gated** — re-import identity ADR first (E18), risk-tier |
| FR-35 | tbd | **gated** — decided as a section of the FR-34 ADR (E18); may close as documented procedure |

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
| **E17 — Corporate actions as ledger events** | 2/4 bridge | next (ADR-0028 accepted) | #338 (tracker), #588–#591 |
| **E18 — Stable identities & reconciliation** | 2 | next (ADR-gated, after E17 ADR) | FR-34, FR-35 (issues after ADR sign-off) |

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
Tracked in **#356** against the DESIGN.md + EXPERIENCE.md spec, plus existing #336 (chart €/% toggle), #337 (dashboard v2), #339 (nav cleanup), #319 (sunburst). UI is deprioritized per #321; accessibility items (color independence, contrast, modal focus, chart-as-table) break out as `agentic` issues when prioritized. UX-DR1–14.

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
**When** I re-import a mutated version of the same PP export (the FR-29 "restore = re-import" path)
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
