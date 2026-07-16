---
stepsCompleted: [1, 2, 3, 4]
inputDocuments:
  - '_bmad-output/planning-artifacts/prds/prd-portfolixir-2026-06-12/prd.md'
  - '_bmad-output/planning-artifacts/architecture.md'
  - '_bmad-output/planning-artifacts/ux-designs/ux-portfolixir-2026-06-12/DESIGN.md'
  - '_bmad-output/planning-artifacts/ux-designs/ux-portfolixir-2026-06-12/EXPERIENCE.md'
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
| FR-23 | #338 | corporate actions |
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
  written, owner sign-off pending.

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

### Epic 7: Rebalancing guidance (gated)
FR-12, both-direction guidance ranked by drift. **No issue yet** — needs the guidance-vs-action ADR/AGENTS.md clarification first (it must never place or prepare orders). Create the issue after the scope decision.

### Epic 8: Read-only sync (Phase 3, gated)
comdirect/bunq/bitcoin.de/watch-only (FR-17–21), tracked in #320. **Hard scope gate:** AGENTS.md currently forbids broker/bank sync; entering this epic requires an ADR + AGENTS.md amendment limited to read-only acquisition. OQ-4 (bitcoin.de) and OQ-6 (unattended-sync feasibility) are open.

### Epic 9: Product-type modeling (Phase 4, discovery-first)
Bonds (#330), corporate actions (#338), German pension modeling (#340 parking lot). Per the PRD, **each modeling FR is preceded by its own discovery story** that fixes acceptance criteria before implementation. FR-22–25.

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
(decision gate per ADR-0026 — owner sign-off pending). The owner's workflow:
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
