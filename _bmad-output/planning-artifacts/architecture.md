---
stepsCompleted: [1, 2, 3, 4, 5, 6, 7, 8]
lastStep: 8
status: 'superseded-in-part'
completedAt: '2026-06-12'
revalidatedAt: '2026-08-12'
authority: 'seam-contract'
agentContext: false
inputDocuments:
  - '_bmad-output/planning-artifacts/prds/prd-portfolixir-2026-06-12/prd.md'
  - '_bmad-output/planning-artifacts/prds/prd-portfolixir-2026-06-12/addendum.md'
  - '_bmad-output/project-context.md'
  - 'docs/architecture.md'
  - 'docs/integration/api-and-mcp.md'
  - 'docs/product-documentation.md'
  - 'docs/decisions/0001-modular-phoenix-monolith.md'
  - 'docs/decisions/0002-thin-mcp-over-json-api.md'
  - 'docs/decisions/0003-decimal-for-money.md'
  - 'docs/decisions/0004-holdings-derived-from-transactions.md'
  - 'docs/decisions/0005-quote-provider-split.md'
  - 'docs/decisions/0006-classifications-with-target-weights.md'
  - 'docs/decisions/0007-currency-conversion-with-exchange-rates.md'
  - 'docs/decisions/0008-target-weights-and-allocation.md'
  - 'docs/decisions/0009-cash-as-balance-snapshots.md'
  - 'docs/decisions/0010-ttwror-performance-series.md'
  - 'docs/decisions/0011-unified-ledger-projection.md'
  - 'docs/decisions/0012-asset-class-inference-at-read-time.md'
revalidationInputs:
  - '_bmad-output/planning-artifacts/briefs/brief-portfolixir-2026-08-12/brief.md'
  - '_bmad-output/planning-artifacts/prds/prd-portfolixir-2026-06-21/prd.md'
  - '_bmad-output/planning-artifacts/epics.md'
  - 'docs/decisions/index.md (ADR-0013 … ADR-0038)'
workflowType: 'architecture'
project_name: 'portfolixir'
user_name: 'Andi'
date: '2026-06-12'
---

# Architecture Decision Document

> ## Read this before anything below it
>
> **Status: superseded in part (re-validated 2026-08-12).** The body of this
> document was written on 2026-06-12 against a corpus of 12 ADRs and a 29-FR
> requirement set. There are now 38 ADRs and 48 FRs. It is kept because part of
> it is still the only record of certain seams — not because it still describes
> the system.
>
> **Every statement in this document carries one of three authority levels.**
> The re-validation at the end of this document assigns them per decision; the
> distinction is the point, because mixing them is what let a decision be
> DECIDED here and OPEN elsewhere for two months:
>
> | Level | Meaning | How to treat it |
> |---|---|---|
> | **enforced** | a named test or CI gate is the authority | follow the test; this document is only a pointer |
> | **decided, not enforced** | an ADR decided it, nothing checks it | follow the ADR; this document is not the source |
> | **proposed** | no ADR, no gate, never built | **not citable in review**; treat as an idea, never as a description of the repository |
>
> **Precedence, in order:** `AGENTS.md` and `CLAUDE.md` bind unconditionally →
> the ADR corpus wins on everything it covers → `epics.md` is the live
> requirement registry (the founding PRD wins on intent and wording) → this
> document is authoritative **only** for seams no ADR has since covered.
>
> **What is still authoritative here:** the P9 write-path and P10 engine-call
> shapes, the anti-pattern table, the contract-fixture direction (D5), the
> analytics-envelope direction (D6/P7) **as a floor rather than a ceiling**, the
> idempotency direction (D11), and P5's scenario-isolation invariants (held for a
> feature that is now gated at ladder level (d)).
>
> **What this document is not:** it is not loaded as agent context — verified
> 2026-08-12, nothing in `CLAUDE.md`, `AGENTS.md` or the README references it —
> and it has no mandate over FR-37…FR-48. Those requirements get their
> architecture from their own gate ADRs, deliberately, because architecture
> written ahead of a requirement's known shape is what produced this document's
> drift in the first place.
>
> **The published human-facing architecture overview is `docs/architecture.md`.**
> That page is maintained and links to the ADR index. If you are looking for what
> Portfolixir's architecture *is*, read that, not this.

_This document builds collaboratively through step-by-step discovery. Sections are appended as we work through each architectural decision together._

## Project Context Analysis

### Requirements Overview

**Functional Requirements:**

29 FRs in seven categories, phased 1–5. Architecturally they split into four kinds of work:

1. **Extensions of the existing ledger-projection core** (most of the PRD): IRR (FR-8),
   benchmark comparison (FR-9), income analytics (FR-10), allocation mechanics (FR-11),
   rebalancing guidance (FR-12) all consume the same daily-valuation/projection
   infrastructure established by ADR-0010/0011. They add read models, not new sources
   of truth. FR-1 (ledger as sole source) is already the system's spine. Caveat: IRR is
   *not* "just another reducer neighbor" — see assumption A7.
2. **New cross-cutting components:** the append-only audit journal (FR-28) intercepts
   every write path (UI, API, MCP) with actor attribution — the first truly new
   architectural seam. The PP-compatible full export (FR-29) requires a serializer that
   is the importer's mirror, plus a documented backup/restore story — but backup and
   PP export are architecturally distinct deliverables (see Constraints).
3. **Gated expansions:** PP XML import (FR-5), rebalancing guidance wording (FR-12), and
   the whole read-only sync family (FR-17–21) each sit behind a scope gate (ADR +
   AGENTS.md amendment) that must land before the first affected story. Phase 3 adds
   encrypted credential storage, OAuth2/PhotoTAN flows, and per-provider adapters behind
   behaviours — following the existing QuoteSync/RateSync scheduler pattern.
4. **New domain depth:** product-type modeling (FR-22–25: bonds, corporate actions,
   German pensions) introduces per-type data, math, and representations; planning &
   simulation (FR-26–27) introduces overlay timelines that must be strictly isolated
   from the real ledger. Each modeling FR is preceded by its own discovery story.

**PRD delta (operator decision, 2026-06-12):** FR-9 benchmark comparison must support
an **after-cost / after-tax dimension**: trading fees and German capital-gains taxes
(Abgeltungsteuer, Vorabpauschale, Teilfreistellung) must be includable so the founding
"worth it?" question is not answered flatteringly pre-cost. Comparison scenarios include
"index bought once and held" and "index as a savings plan". Recommend updating the PRD
(FR-9 wording + a new OQ for the tax-model depth) — a pre-tax-only comparison is a
mischaracterization of the founding question.

**Non-Functional Requirements:**

- **NFR-1/2 (correctness, auditability)** are the architecture's prime directives:
  Decimal-only persistence, derived-on-read reproducibility, invariant gates. Silent
  financial corruption is the defining failure class. Auditability must be
  operationalized for **read paths too**: every served figure traceable to its inputs
  and method (provenance), not just every mutation journaled.
- **NFR-3 (AI-agentic guards)** makes mechanical enforcement (CI gates, meta-tests,
  scope locks) a load-bearing architectural concern, not process garnish — the owner
  does not read code. Consequence: architectural rules in this document must be
  formulated so they are mechanically checkable (gate-able), and conventions that
  cannot be gated must be named as residual risks.
- **NFR-4 (security boundaries):** no in-app LLM calls, no trading/payment, read-only
  sync only, bearer-token API auth, deliberately unauthenticated web UI (trusted
  network / reverse proxy). Extended by the MCP trust model below (graduated write
  scopes).
- **NFR-8 (performance):** p95 < 2 s on commodity hardware at hundreds of securities /
  tens of thousands of transactions — in tension with derive-everything-on-read.
  Caching *implementation* stays deferred (ADR-0004/0010), but the caching *capability*
  is a today-decision: pure engines over injected datasets plus a monotonic ledger
  version usable as a cache key ("seam now, mechanics later"). NFR-8 also needs a
  measurement apparatus (seeded volume generator, perf budget on named operations),
  otherwise it is a target nobody can miss.
- NFR-5/6/7: docker-compose self-hosting, single-user tenancy with portfolio-scoped
  views, de/en localization via gettext.

**Scale & Complexity:**

- Primary domain: backend-heavy full-stack web (Phoenix LiveView monolith + thin
  TypeScript MCP companion)
- Complexity level: medium — high domain depth (multi-currency Decimal-exact finance,
  projection semantics), low operational complexity (single user, single node, one
  deploy unit)
- Estimated architectural components: ~8 existing contexts/services extended, ~5 new
  (audit journal, PP export/backup, sync framework + per-provider adapters, pension/
  product-type modeling, scenario/series engine)

### Load-Bearing Assumptions (rated)

| # | Assumption | Confidence | Impact | Note |
|---|---|---|---|---|
| A1 | IRR/income analytics are additional consumers of the existing projection/daily-walk | High | Medium | ADR-0010 names IRR as a natural follow-up on the same series — but see A7 for the math caveat |
| A2 | The audit journal (FR-28) can intercept every write path | Medium | High | Assumes all writes go through Ledger/Imports public functions — context-boundary enforcement is currently convention only; FR-28 forces resolving it (boundary library vs. Repo-scan gate) as a prerequisite |
| A3 | PP-compatible roundtrip export (FR-29) is lossless | Medium | High | Portfolixir today discards data PP carries (e.g. per-transaction FX rates, ADR-0007); fidelity spike needed before Success Metric 1 depends on it. Roundtrip is not CI-automatable (see Constraints) |
| A4 | p95 < 2 s holds with derive-on-read | Medium | High | Proven for 2,755 bookings × 9 years (ADR-0010 amendment), but benchmark × what-if × daily walks stack; caching-ADR trigger metric undefined; no volume fixtures or benchmark exist in the repo today |
| A5 | What-if (FR-27) can reuse projection/valuation against virtual transactions | Medium | High | Projection.effects/1 is pure, but the daily walk/valuation must become callable with injected datasets instead of DB queries — same seam the caching capability needs |
| A6 | Portfolio scoping (FR-4) is "just a filter" everywhere | Low | Medium | Known debt: several flows assume one working portfolio (docs/architecture.md risks) — collides with FR-4/UJ-6 |
| A7 | IRR fits the Decimal-only discipline | Medium | High | XIRR needs iterative root-finding with fractional powers/logarithms — Decimal has neither. Decision needed: documented float-island at the math boundary vs. fixed-point Newton; plus an explicit failure contract (e.g. `{:error, :no_convergence}`) for non-converging cashflow patterns |
| A8 | Market-data state is stable enough to serve agents | Medium | High | Quote/FX ingestion exists (ADR-0005/0007: Yahoo, CoinGecko, ECB + schedulers) but retroactive provider corrections mean "same question, different answer tomorrow"; derived values are functions of (ledger state, market-data state) — the market-data state must be at least attributable (as-of) in responses |
| A9 | Quotes are fresh enough for agent autonomy | Medium | Medium | Success Metric 2 assumes current quotes/FX on a self-hosted box; staleness must be visible in responses (basis date), never silent |

### Technical Constraints & Dependencies

- **Stack is fixed:** Elixir/Phoenix (LiveView 0.20.x, no asset pipeline, server-
  rendered SVG charts), PostgreSQL as the only store, TypeScript MCP companion over
  the JSON API only (ADR-0002). No new dependencies inside feature stories — a new
  dep is a reviewed decision (project-context.md); XML parsing for FR-5 and a volume-
  fixture generator (StreamData) will each force one such decision explicitly.
- **12 accepted ADRs constrain all new work**; changing direction means superseding an
  ADR, never silent drift. Key invariants: holdings never stored (ADR-0004), single
  per-kind reducer with closed kind set (ADR-0011), EUR-hub FX (ADR-0007), cash as
  balance snapshots (ADR-0009), Decimal end-to-end with string serialization (ADR-0003).
- **FR-29 splits into two deliverables:** backup (lossless by definition — boring:
  documented dump/restore of the full store) and PP-compatible export (a reporting
  artifact over the ledger, allowed to be best-effort where PP's model is narrower).
  Compatibility direction is fixed: **PP follows Portfolixir's model, never the
  reverse** — the PP format must not become a shadow schema constraining the ledger.
- **PP roundtrip is not CI-automatable:** Portfolio Performance is a desktop Java app
  with no headless mode. Mechanically testable: export-schema conformance + re-import
  idempotency (Portfolixir → file → Portfolixir). The PP-in-the-middle step stays a
  manual/fixture-based check with PP-version drift as a named risk.
- **Rounding policy #344 is a sequencing blocker,** not an open detail: golden masters
  frozen before the rounding decision must be mass-regenerated after it — the moment
  real regressions slip through. Decide #344 before scaling the golden-master corpus;
  FR-29 losslessness is only verifiable after it.
- **Chart rendering needs an ADR before the first chart-heavy story:** no asset
  pipeline means no npm chart lib without an architecture decision (options:
  server-rendered SVG as today, vendored JS hook, or introducing a pipeline).
- **Single-portfolio assumption debt:** several existing flows assume one working
  portfolio; FR-4 (scoping everywhere) and UJ-6 (family view) require retiring this
  debt — an explicit workstream, not an incidental fix.
- **FR-28 prerequisite:** the audit journal is only trustworthy if context-boundary
  enforcement becomes mechanical (boundary library or web-layer Repo-scan gate,
  quality-gate roadmap item 5) — schedule it before or with the journal.
- **Scope gates:** AGENTS.md currently forbids XML intake and broker/bank sync;
  FR-5/FR-12/Phase 3 each require an ADR + AGENTS.md amendment first (OQ-1).
- **External providers are unofficial/fragile** (Yahoo, CoinGecko, PP search) — every
  provider sits behind a behaviour with a test fake; no network in tests. Phase 3 adds
  official APIs (comdirect REST, bunq) with their own auth complexity (OQ-6).
- **CI quality gates are release-blocking** (Credo strict, Dialyzer zero-ignore,
  Sobelow, coverage ratchet, meta-tests); gates only ratchet downward.

### Architectural Principles Derived from Context

1. **Pure core, imperative shell — as a mechanically checked rule.** All computation
   engines (valuation, daily walk, allocation, IRR, scenarios) are pure functions over
   injected datasets and an injected clock; DB access and `Date.utc_today()` live in
   the shell only. One decision solves three problems: FR-27 isolation becomes
   structural instead of conventional, the caching seam exists before caching does,
   and the engines become property-testable. AI agents *will* bury `Date.utc_today()`
   in engines unless a gate forbids it.
2. **Read-path provenance.** Every analytic response states method, as-of date,
   currency, conversion basis, and data-quality flags (trade-priced positions, suspect
   dates, stale quotes). Auditability covers answers, not only mutations — the likelier
   damage scenario is a wrong number trusted, not a wrong write.
3. **Refusal contract for MCP tools.** When data is missing or unpriceable, tools say
   so explicitly (machine-readable gap markers) instead of returning silently partial
   numbers an agent will narrate as truth.
4. **Graduated MCP write scopes (operator decision, 2026-06-12).** Direction: token
   scopes with read-only default and explicit write grant — actor attribution in the
   journal (FR-28) is only as trustworthy as the token model behind it. Today's
   single-agent deployment writes; the scope model is built in from the start, not
   retrofitted.
5. **Journal semantics fixed up front (operator decision, 2026-06-12):** journal is
   active from its activation date, **no backfill** — pre-existing records have no
   genesis entries, and the first `before` value of a record may reference
   never-journaled state. Append-only is enforced at the DB level (trigger or
   `REVOKE UPDATE, DELETE`), not by convention. Actor attribution is a deliberate
   signature change through all context write functions (its own sequenced refactor;
   smuggling the actor through the process dictionary is forbidden). The journal's
   interaction with bulk imports (one import = many entries, actor = import session,
   atomicity of business-write + journal-write) and with what-if scenario persistence
   (journaled or exempt) must be defined in the FR-28 ADR.

### Cross-Cutting Concerns Identified

1. **Audit journal (FR-28):** every financial write across UI/API/MCP, with actor
   attribution and before/after values — touches all write paths, becomes part of the
   API/MCP parity surface, and needs a retention/index strategy (unbounded growth).
2. **API/MCP parity (FR-13–16):** every analytic must surface through JSON API + MCP
   with self-describing metadata; parity is currently a PR-review convention — at ~42
   tools and growing it needs a **contract artifact** (schema generation from one
   source, or shared JSON fixtures both sides test against). Zod + hand-written
   schemas in TypeScript vs. `Api.V1.JSON` in Elixir is the largest unguarded seam in
   the system.
3. **Decimal discipline:** exact arithmetic end-to-end, string serialization at every
   boundary, rounding policy pending (#344, FR-3) — will govern every analytics FR;
   IRR forces an explicit boundary decision (A7).
4. **Projection extension protocol:** new booking kinds or analytics go through
   Projection.effects/1 / the daily-walk infrastructure; closed kind set raises on
   unknown kinds by design.
5. **Scope-gate sequencing:** gated FRs need their ADR + amendment story scheduled
   before implementation stories.
6. **Dual-consumer output contract:** every number serves the LLM agent (machine-
   consumable) and the human (understandable: method, context, visualization).
7. **Localization & docs as tested artifacts:** gettext de/en completeness and the
   published docs site are guarded by meta-tests; user-visible changes ripple into
   product-documentation.md.
8. **Scenario/series engine cluster:** benchmark comparison (FR-9), retirement
   projection (FR-26), and what-if simulation (FR-27) are all "generate an
   alternative time series and compare against the real one" — a shared series/
   scenario engine is the biggest hidden architectural opportunity in the PRD.
   Likewise FR-5 (XML import) and FR-29 (PP export) share one PP-format layer
   (note: PP XML uses internal `idref` cross-references — a reference resolver, not a
   flat parse), and Phase-3 sync is architecturally "import from another source"
   (reuse the preview/idempotency/validation/journal pipeline).
9. **MCP tool economy:** ~42 tools exist; FR-13 grows the surface. Response size,
   paging, and tool-choice quality are first-class architectural requirements —
   a consolidation-vs-1:1-mapping decision is needed before analytics exposure
   balloons the tool count. A **golden question set** (the real questions the operator
   answers in spreadsheets today) should drive tool design instead of designing blind.
10. **Ledger-spine clarification:** pension entitlements (FR-24/25) are not
    transactions. FR-1's "all financial state derives from the ledger" needs an
    explicit carve-out for stored configuration/entitlement facts (precedent:
    targets, ADR-0008) — otherwise pension modeling invites fake-transaction hacks.
    Pension math additionally needs **versioned external constants** (Rentenwert
    changes yearly — data vs. code, and who maintains it).
11. **Valuation timing semantics:** trade date vs. value date, which FX fixing, the
    daily-walk day boundary — must be pinned down once, in writing, before further
    analytics build on the walk (the classic portfolio-tool trap).
12. **Verification gaps named as architecture concerns:** (a) **oracle problem** —
    golden masters drawn from an AI-generated implementation nobody reads ratify bugs;
    new math needs independent reference values (PP cross-check, hand-computed cases);
    (b) **PP-parity harness** — Success Metric 1's real trust threshold is "same
    portfolio, same figures as PP within stated tolerance", which needs to exist as a
    checkable artifact; (c) engines need **property-test density** as the quality bar
    (line coverage does not detect silent financial corruption; uniform 90% coverage is
    effort without risk reduction); (d) **migration safety** — schema migrations are a
    first-class corruption vector for a brownfield ledger: post-migration invariant
    checks (bookings sum to zero, idempotent re-derivation) belong in the gate suite;
    (e) FR-27 isolation needs a **negative invariant test** (simulator runs produce
    zero writes to ledger tables, mechanically counted).

### Identified Risks (pre-mortem)

| Failure path (12-month horizon) | Countermeasure |
|---|---|
| Audit journal lands late; an agent edit corrupts data unattributed; trust lost | Keep FR-28 early in Phase 1 (confirmed phasing) |
| Roundtrip export turns out lossy; Numbers/PP never retired (Success Metric 1 fails) | Fidelity spike before committing FR-29 acceptance criteria; split backup from PP export; PP-parity harness as the trust threshold |
| Performance collapses when series computations stack; caching added in panic without invariants | Pure-engine seam + ledger-version cache key now; volume generator + perf budget; cache must be provably derivable/invalidatable (NFR-2) |
| MCP tool sprawl degrades agent tool-choice | Tool-taxonomy decision before Phase-2 analytics exposure, driven by a golden question set |
| Pension modeled as fake transactions; ledger semantics diluted | FR-1 carve-out decision (stored entitlements vs. derived projections) before Phase 4 |
| New math (XIRR/benchmark/projection) ships with subtle errors ratified by self-derived golden masters | Independent oracles: PP cross-checks, hand-computed reference cases, property invariants |
| Agent serves stale or retroactively-corrected market data as current truth | As-of/basis-date attribution in every response; staleness visible, never silent |
| Schema drift between API and MCP companion goes unnoticed across two languages | Contract artifact (generated schemas or shared fixtures) instead of PR-review convention |

## Starter Template Evaluation

### Primary Technology Domain

Backend-heavy full-stack web application (Phoenix LiveView monolith + thin TypeScript
MCP companion), self-hosted via docker-compose. Brownfield: the project is live with
12 accepted ADRs, CI quality gates, and real operator data.

### Starter Options Considered

None — deliberately. This is an established brownfield codebase; the "starter
template" is the existing repository. Evaluating greenfield starters would be
meaningless, and replatforming is out of scope (stack choice is a recorded,
motivated decision: always-on self-hosted BEAM app + LLM/MCP attachment).

### Selected Starter: Existing Codebase (brownfield baseline)

**Rationale for Selection:**
The repository itself is the foundation every new story builds on. Its architectural
decisions are binding and recorded — this document extends them rather than re-making
them.

**Initialization Command:** n/a — no project initialization story. The first
implementation stories build directly on the existing repo.

**Architectural Decisions Provided by the Baseline:**

- **Language & Runtime:** Elixir 1.18.3 / OTP 27 (CI is authoritative; do not use
  language features beyond the CI version). TypeScript for the MCP companion.
  Version truth lives in `mix.lock`, `mcp-server/package-lock.json`, and
  `.github/workflows` — never hardcoded in planning documents.
- **Web Framework:** Phoenix with LiveView 0.20.x (NOT 1.x idioms); no CoreComponents;
  inline `~H` render/1, LiveComponents in per-view subdirectories.
- **Styling Solution:** hand-written CSS in `priv/static/app.css`; no asset pipeline,
  no Tailwind, no JS bundler; charts are server-rendered SVG.
- **Persistence:** PostgreSQL via ecto_sql/postgrex as the only data store;
  Decimal-only financial values with explicit precision/scale.
- **Testing Framework:** ExUnit with DataCase/ConnCase split, fake providers (no Mox),
  Req `plug:` stubs, meta-tests guarding repo invariants; PostgreSQL required for
  tests; `node --test` via tsx for the companion.
- **Quality Tooling:** mix format, Credo (strict, grandfathered thresholds), Dialyzer
  (zero-ignore), Sobelow (documented ignores), excoveralls → Codecov; pre-commit hooks
  with commit-footer enforcement.
- **Code Organization:** modular monolith with bounded contexts (Catalog, Portfolios,
  Ledger, Classifications, Fx, Imports + PortfolixirWeb + mcp-server/); one-way
  dependency direction (web/MCP → contexts).
- **Development Workflow:** AGENTS.md as binding contract; conventional commits;
  squash-merge to main; ADRs for architecture changes; BMad artifacts committed under
  `_bmad-output/`.

**Note:** No initialization story exists. Any new architectural component decided in
this document lands as stories inside the existing repository structure.

## Core Architectural Decisions

All decisions below extend the brownfield baseline (12 ADRs + project-context.md);
nothing already decided there is re-decided. No new technology versions are chosen
here — new dependencies are reviewed decisions per repo policy. Decisions were
stress-tested in two elicitation rounds and an agent roundtable (Winston/Murat/
Amelia personas); fail-closed mechanical enforcement is the recurring theme: every
rule an implementing agent must follow has a meta-test that fails when it is broken.

### Decision Status (assigned 2026-08-12 — read this before any D below)

The original priority ranking is preserved at the end of this subsection for the
record, but it is no longer how to read D1–D11. **This table is.** A decision
marked *proposed* describes nothing that exists; citing it in a review is a
finding, not an argument.

| # | Decision | Authority level | Where the truth lives now |
|---|---|---|---|
| D1 | Audit journal | **enforced** | ADR-0017 + `write_actor_test.exs` (grandfather list empty, shrink-only), journal append-only tests. Rollout complete, per-context arming executed as Amendment 1 said |
| D2 | Pure core / imperative shell | **proposed** | Nothing. `engines/` holds one module, no `engine_data/`, no purity gate. `Portfolixir.Clock.today/0` sits in the impurity class D2 governs and passed every check, because there was none. See re-validation Critical Gap 3 for the replacement that does not require a namespace move |
| D3 | Rounding sequencing + oracle provenance | **decided, not enforced** | ADR-0016 — and it decided the *opposite* locus D3 assumed: full precision in compute, rounding only at the human display. The oracle-provenance rule survives and is unenforced |
| D4 | Graduated token scopes | **proposed** | Nothing. Router has `:api` / `:api_auth`; one shared bearer token grants full ledger write. Recorded here as "decided" in error — the same question is an open decision (OD-4) in the Data-Import PRD. See Critical Gap 4 |
| D5 | API↔MCP contract artifact | **proposed** | Nothing built; the direction remains right and the seam has widened (37 API controllers, one shared presenter). Highest discovery latency in the system |
| D6 | Self-describing analytics envelope | **proposed, and now under a stricter mandate** | Nothing built. `AGENTS.md` now makes the computation basis (input series, window, reference series, gap treatment) a review-blocking acceptance criterion on every metric — a stricter contract than P7's key set. P7 is a floor |
| D7 | MCP tool taxonomy | **superseded in effect** | FR-37 (#665) and FR-38 (#666) are the shipped-shape answer. The golden question set was never produced; the agent-side success criteria (≤ 5 calls, −70 % volume) supply the measurable target it wanted |
| D8 | Charts stay server-rendered SVG | **enforced by absence** | No asset pipeline exists; unchanged and still correct |
| D9 | NFR-8 measurement apparatus + caching trigger | **proposed** | Nothing built. ADR-0032 and ADR-0035 were both decided on a felt symptom instead. The trigger mechanism never governed anything; it is revived only by a named rebuild-time budget in the gate B3.2 ADR |
| D10 | IRR/XIRR numeric strategy | **decided, not enforced** | ADR-0034 — Newton with analytic derivative, bracketed bisection on (−0.999999, +10], Act/365, tolerance 1e-7, ~200 iterations, float64 confined to the solver, nothing persisted. **Failure contract differs from D10's text:** all flows of one sign render "n/a"; windows under a year show non-annualized period MWR |
| D11 | Write idempotency | **proposed** | Nothing built. FR-DI-13 restates the requirement and pins its relation to content hashing: the key dedupes the *request*, the hash dedupes the *records*, and both hold |

**Original priority ranking, kept for the record (2026-06-12):** critical — D1,
D2, D3; important — D4 … D11. Two of the three "critical" decisions turned out
never to be built, which is the finding the ranking itself could not surface.

**Deferred Decisions (explicit, with rationale):**
- Phase-3 credential encryption — behind the scope gate, its own ADR
- Rounding-policy *content* — its own story/ADR (#344, owner: maintainer); only sequencing
  and required content scope are fixed here
- Pension data model details and **versioned pension constants** (Rentenwert changes
  yearly) — the FR-24/25 discovery story
- **PP-XML idref reference resolver** design — the FR-5 scope-gate ADR
- Caching *implementation* — the seam is built now (D2); the caching ADR defines its
  own cache key when the D9 trigger fires (no ledger-version column is added today)

### Data Architecture

**D1 — Audit journal (FR-28).**
- Append-only journal table. Append-only is enforced at the DB level by Postgres
  triggers raising on `UPDATE`, `DELETE`, **and `TRUNCATE`** (REVOKE alone is
  insufficient — the app role owns the table). Residual risk (superuser, migrations)
  is documented, with a **named legitimate escape hatch** for data-fix migrations
  (e.g. `session_replication_role`) so the first data-fix PR does not improvise.
  A standing test attempts a real UPDATE/DELETE against the journal table and expects
  the raise — a migration that loses the trigger turns CI red.
- **Single entry point:** all journal writes go through one fixed module (an
  `Ecto.Multi` helper); contexts never hand-roll journal inserts. Journal entry and
  business write commit in the **same DB transaction** — both or neither.
  Completeness is a testable invariant (no committed financial write without a
  journal entry), stated as an acceptance criterion of the journal story.
- **Actor attribution:** an explicit actor struct passed as a parameter in a fixed
  position (convention: first argument) of every public context write function.
  Closed actor taxonomy: `owner_ui`, `api_token_rw`, `api_token_ro`,
  `import_session`, `system_job` — extended only by amending this decision. An AST
  meta-test asserts every public write function carries the actor parameter; the
  refactor lands as sequenced per-context PRs. Smuggling the actor through the
  process dictionary is forbidden.
- **Scope:** only committed writes are journaled (changeset rejections, constraint
  violations, and domain-rule rejections never reach the journal — nothing committed,
  nothing journaled). Persisted what-if scenario writes ARE journaled with a scenario
  marker; journal queries default-filter to real writes. Bulk imports journal
  per-record entries with actor = `import_session`. Journal is active from
  activation, **no backfill** (operator decision, 2026-06-12). Retention/index
  strategy is part of the FR-28 ADR (unbounded growth is named).

**D2 — Pure core, imperative shell (binding rule).**
- All computation engines (valuation, daily walk, allocation, IRR, benchmark,
  scenario/series) are pure functions over injected datasets and explicit `as_of`
  date parameters (the domain is day-granular — no Clock behaviour, plain `Date`
  arguments).
- **New engines live under `Portfolixir.Engines.*`**; an AST meta-test holds an
  explicit module list (seeded with existing pure modules such as
  `Ledger.Projection`) and forbids inside engines: `Repo.*`, `DateTime.utc_now`,
  `Date.utc_today`, `System.*_time`, `:rand`/`:crypto.strong_rand_bytes`, HTTP
  clients, `Process.*`. The counterpart is named too: datasets are built in declared
  loader modules in the shell, so queries cannot leak into "helper" modules beside
  the engines.
- **FR-27 isolation invariants, both directions:** (write) simulator runs produce
  zero writes to ledger tables — asserted via row-count comparison; (read)
  **analytics output is identical with and without persisted scenarios in the
  database** — a property test over engine inputs, guarding against a forgotten
  scenario filter silently corrupting real analytics (NFR-1).
- No ledger-version column is introduced now; the future caching ADR defines its own
  key. The seam IS the purity: cacheable = pure function of (datasets, as_of).

**D3 — Rounding sequencing and oracle provenance.**
Issue #344 (owner: maintainer) is decided **before** the golden-master corpus is scaled and
before FR-29 export acceptance criteria are frozen. The policy must name the Decimal
rounding mode AND the application locus (per-operation vs. display-only). **Oracle
provenance rule:** every golden-master expectation carries an independent source (PP
export cross-check, hand calculation, or external tool) — golden masters derived from
our own implementation ratify bugs instead of finding them.

### Authentication & Security

**D4 — Graduated token scopes (fail-closed).**
Two bearer tokens via environment: the existing read-write token
(`PORTFOLIXIR_API_TOKEN`) and a new optional read-only token. Scope hierarchy is
explicit: rw ⊇ ro (a rw token passes every ro check). Classification is
**per endpoint, not per HTTP verb** — market-data sync triggers (quote/FX sync) are
read-scope; financial-record writes require rw — with the router pipeline as the
single source of truth and **default-deny**: a meta-test fails on any route without
an explicit scope classification. Scope violations return 403 (distinct from 401).
Token comparison uses constant-time comparison (`Plug.Crypto.secure_compare`).
Default posture for new agent integrations: read-only until write access is
deliberately granted (operator decision, 2026-06-12).

### API & Communication Patterns

**D5 — Contract artifact for API↔MCP parity.**
Shared JSON fixtures, **generated from real API responses** by a mix task through
the full HTTP stack (ConnTest — not serializer units), stored at one path, with
Elixir as producer and source of truth; the TypeScript companion suite consumes them
read-only. One owner, one regeneration command, one path. Escalation to OpenAPI
codegen only if fixture maintenance becomes the bottleneck. The D6 envelope schema is
itself one of these fixtures (couples D5 and D6 to one source of truth).

**D6 — Self-describing analytics envelope.**
Every analytics response carries a top-level additive `meta` object — `method`,
`as_of` (basis date), `currency`, conversion basis, data-quality flags, and gap
markers — added **beside** existing fields (no breaking `data` re-nesting). Flags
and gap markers form a **closed, enumerated vocabulary** (same philosophy as the
closed kind set in ADR-0011): an unknown marker is a test failure, not a new string.
Refusal contract: partial-but-flagged data returns **200 + gap markers** (a partial
answer is a valid response); 422 stays for invalid requests. Implementation is a
thin presenter helper in the existing `Api.V1.JSON` pattern — no macro framework.
Existing analytics endpoints (valuation, performance, allocation) get a phased
additive retrofit (FR-13 demands every analytic); each retrofit's definition of done
includes a negative test where degraded data quality forces a marker instead of a
fabricated number.

**D7 — MCP tool taxonomy.**
The companion stays a thin 1:1 wrapper (ADR-0002 untouched). Consolidation happens
API-side: a small number of aggregate analytics endpoints (briefing-style reads)
designed against the **golden question set** — a planning artifact (owner: maintainer,
stored under `_bmad-output/planning-artifacts/`) listing the real questions the
operator answers in spreadsheets today. The question set is a prerequisite of the
aggregate-endpoint stories. Tool-count growth is controlled at the API design level,
not by fattening the wrapper.

**D11 — Write idempotency for the agent-facing API.**
LLM agents retry on timeouts — that is their normal behaviour, and a double-booked
transaction is the most expensive failure the ledger has. Financial write endpoints
accept an optional client-supplied `Idempotency-Key`; the server deduplicates
(unique index; a replay returns the original result instead of writing twice).
Boring, proven technique; rides along with the D1 actor refactor instead of being
retrofitted across all contexts later.

### Frontend Architecture

**D8 — Charts stay server-rendered SVG.**
Allocation, benchmark, and projection charts follow the existing `security_chart`
pattern: server-rendered SVG in LiveView, no asset pipeline, no npm chart library.
Revisit (as an ADR) only when a feature genuinely requires client-side interactivity
that SVG-over-LiveView cannot deliver.

### Analytics Numerics

**D10 — IRR/XIRR numeric strategy.**
Iterative root-finding (XIRR) cannot be done in pure Decimal (no fractional `pow`,
no `ln`). Decision: **float-internal root-finding only**, with Decimal at every
boundary — inputs converted at the engine edge, the found rate re-validated and
rounded into Decimal per the #344 policy, the float island documented in the engine
module. Explicit failure contract: cashflow patterns without convergence (e.g. no
sign change) return `{:error, :no_convergence}` — never a guessed number. Property
tests verify against independently hand-computed oracle cases (D3 provenance rule).

### Infrastructure & Deployment

**D9 — NFR-8 measurement apparatus.**
- Seeded volume-fixture generator producing realistic ledgers; **reference volume
  pinned now: 500 securities, 50,000 transactions, 10 years of history, 5 cash
  accounts.** Fixed seed checked into the repo. StreamData as the generator base is
  **pre-approved here** (test-only dependency) and lands as its own dedicated dep PR.
- Operator measurement is a **one-command mix task** (the owner doesn't read code —
  measurement must be a command, not a procedure), run on operator hardware.
- CI perf smoke measures **relative regression** against its own baseline with
  generous budgets, starts non-blocking/scheduled (runner variance), becomes blocking
  only once variance is known.
- **Caching trigger:** measured p95 > 1 s at reference volume on operator hardware on
  any budgeted operation (valuation, performance walk, allocation, holdings via the
  JSON API) → the caching ADR becomes due (cache must be provably
  derivable/invalidatable per NFR-2).

Hosting, CI/CD, environment configuration, and deployment are unchanged brownfield
decisions (docker-compose, three-job CI, env-based config) — not re-decided.

### Decision Impact Analysis

**Implementation sequence (dependency-ordered):**
1. D2 pure-core rule (namespace + AST gate) and D9 volume generator — foundations
   every engine story needs
2. Actor-struct refactor (D1 prerequisite) with D11 idempotency keys riding along,
   then journal table + interception (D1), with D4 token classes feeding actor
   attribution
3. #344 rounding policy + D3 oracle-provenance rule — before golden masters and
   FR-29 acceptance criteria
4. D6 envelope standard — before the first new analytics endpoint (IRR/D10, FR-8)
5. D5 fixture generation — with the first endpoint that ships under the new envelope
6. Golden question set (operator artifact), then D7 aggregate endpoints (Phase 2)
7. D8 applies per chart story; no upfront work

**Cross-component dependencies:**
- D1 atomicity + D2 purity together keep the journal out of the engines: engines
  compute, the shell writes and journals.
- D2's injected datasets serve three masters: FR-27 scenario overlays, the D9 perf
  fixtures, and the future cache seam.
- D5 and D6 are coupled by design: the envelope schema is a fixture, so envelope
  drift between API and MCP companion is mechanically caught.
- D4 token classes are what make D1's actor attribution meaningful for MCP writes;
  D11 idempotency makes agent retries safe before agents get write grants.
- D10 depends on #344 (D3) for its boundary rounding and on D3's provenance rule for
  its oracle cases.

## Implementation Patterns & Consistency Rules

Baseline rule: existing conventions are binding and are NOT restated here —
project-context.md (60 rules) plus the named exemplar files define naming, test
placement, presenter usage, LiveView style, error idioms, and MCP tool authoring.
The patterns below (P1–P12) cover only the NEW seams introduced by D1–D11, where
implementing agents could still legitimately diverge. Patterns carry stable IDs so
stories can reference them ("follow P9").

### Routing Table — read this first

| What you are building | Pattern | Read BEFORE writing code |
|---|---|---|
| Any context write function | P1, P2, P9 | `lib/portfolixir/ledger.ex` (write idioms) |
| A new analytics computation | P3, P4, P10 | `lib/portfolixir/ledger/projection.ex` |
| Anything what-if/scenario | P5 | `lib/portfolixir/ledger/projection.ex` |
| A new API endpoint | P6, P7, P8 | `lib/portfolixir_web/controllers/api/v1/security_controller.ex` + `json.ex` |
| A new MCP tool | P12 | `mcp-server/src/tools.ts` |
| API/analytics tests | P11 | `test/` meta-test exemplars (`ci_test.exs`) |
| A LiveView page/section | (existing rules) | `lib/portfolixir_web/live/transaction_management_live.ex` |

A CI meta-test asserts every exemplar file referenced here still exists.

### P1 — Audit journal mechanics

- Table `audit_journal`, context `Portfolixir.Journal`, schema `Journal.Entry`.
  Columns: `actor_type`, `actor_label`, `operation`, `resource_type`, `resource_id`,
  `before`/`after` (JSONB), `scenario_id` (nullable), `inserted_at`. No `updated_at`.
- `operation` is a closed enum: `"create" | "update" | "delete" | "upsert"`
  (upsert exists because `on_conflict` writes cannot deterministically report
  create-vs-update).
- `resource_type` is a closed list of stable STRING codes (e.g. `"transaction"`,
  `"cash_account"`) — never module names (codes survive refactors).
- **Single entry point:** `Journal.record/3` takes an `Ecto.Multi`, returns an
  `Ecto.Multi` — it appends the journal step. `before` = the changeset's `data`
  serialized; `after` = built in a function step from the Multi results. No journal
  insert exists outside this module.
- **Serialization:** one module, `Journal.Serializer`, owns the JSONB encoding —
  Decimals as strings (Jason's default would emit numbers), dates as ISO strings.
- **Completeness is mechanical, not conventional:** journaled tables carry a guard
  trigger requiring a transaction-local session variable
  (`SET LOCAL portfolixir.journal_actor = …`) that only `Journal.record/3` and the
  allowlisted non-journaled paths set. A raw `Repo.update` on a journaled table
  fails loudly. The allowlist of non-journaled write paths (quote/FX sync
  schedulers — market-data ingestion only) is one module guarded by a meta-test:
  the exception set is closed, never grown silently.
- Bulk imports journal **per-record** entries (a 5k-row import = 5k entries),
  actor = `import_session`.

### P2 — Actor struct and the write classifier

- `Portfolixir.Actor` (top-level), fields `type` + `label`. `type` is the closed
  taxonomy:

  ```elixir
  :owner_ui | :api_token_rw | :api_token_ro | :import_session | :system_job
  ```

  Phase-3 sync extends this list only via an amendment to this document (expected:
  per-provider actor types).
- The actor is always the FIRST positional argument of public context write
  functions: `Ledger.create_transaction(actor, attrs)`.
- **Write classifier (for the AST gate):** a "write function" is any public context
  function that transitively reaches `Repo.insert/update/delete/insert_all/
  update_all/delete_all` or `Repo.transaction` with a writing Multi — name prefixes
  are NOT the classifier. Pre-existing functions are grandfathered in an explicit
  list that only shrinks (same mechanism as Credo baselines).

### P3 — Engines (pure core)

- `Portfolixir.Engines.<Name>` (e.g. `Engines.Irr`, `Engines.Benchmark`,
  `Engines.Scenario`). Entry point `run/2`: `run(%Engines.<Name>.Input{}, as_of)`
  with `as_of :: Date`. Shared structs live in `Engines.Types`.
- Existing pure modules (`Ledger.Projection`) stay where they are; the purity gate
  holds an explicit module list seeded with them.
- **Purity gate = dependency whitelist, not call blacklist:** engine modules may
  reference only `Portfolixir.Engines.*` and an explicit allowed-module list
  (`Enum`, `Map`, `List`, `Stream`, `String`, `Integer`, `Date`, `Decimal`,
  `Kernel` minus IO). Additionally a function-level deny list inside engines:
  `Date.utc_today/0`, `DateTime.now/utc_now`, `System.*_time`, `:rand`, `IO`.
  Documented per-module exception: `Engines.Xirr` may use `:math`/`Float`
  (the D10 float island).
- Failure contract: tagged tuples with documented atoms
  (`{:error, :no_convergence}`) — engines never raise for data-shaped failures.
- Engines assume valid input; validation happens in the loaders (P4).

### P4 — Dataset loaders (shell)

- `Portfolixir.EngineData.<Name>`, paired 1:1 with its engine. Repo allowed here;
  loaders build AND validate the engine's `Input` struct.
- `Date.utc_today()` is computed only at the shell boundary
  (controller/LiveView/scheduler) and passed down — never inside loaders' pure
  helpers, never inside engines.

### P5 — Scenario isolation

- All what-if tables carry the `scenario_` prefix (`scenarios`,
  `scenario_transactions`). A meta-test asserts every `Portfolixir.Scenarios.*`
  schema maps to a `scenario_`-prefixed table.
- A test-env Ecto-telemetry guard asserts query sources per context: live-context
  queries never touch `scenario_` tables; scenario-context queries never write
  non-`scenario_` tables. (The D2 read/write isolation invariants are the
  property-level complement.)

### P6 — Route scopes

- Router pipelines `:api_read` and `:api_write` are the D4 scope classification.
  Every `/api/v1` route passes through exactly one — a fail-closed meta-test
  rejects unclassified routes. Market-data sync triggers are `:api_read`;
  financial-record writes are `:api_write`.

### P7 — Analytics meta envelope

- Fixed keys, additive top-level `meta` object:

  ```json
  "meta": {
    "method": "ttwror",
    "as_of": "2026-06-12",
    "currency": "EUR",
    "basis": "eur_hub_rates",
    "flags": ["trade_priced_positions"],
    "gaps": [{"code": "missing_quote", "detail": "security 42"}]
  }
  ```

- `flags` and `gaps[].code` come from closed enums defined in ONE module:
  `PortfolixirWeb.Api.V1.Meta`. Adding a value happens there + in the contract
  fixture — nowhere else; an unknown value is a test failure. `gaps[].detail` is
  OPTIONAL and is omitted when absent — never `null` (fixture determinism).

### P8 — Idempotency (writes)

- Optional standard `Idempotency-Key` request header on financial write endpoints.
- Scope: uniqueness per `(token, key)`, enforced by a DB unique constraint (races
  resolve in the database, not in app logic). The request body hash is stored;
  same key + different body → `422`. Replay returns the STORED original response
  (byte-identical, not recomputed) plus the response header
  `Idempotency-Replay: true`. Retention: 24 h.

  ```text
  POST /api/v1/transactions          POST /api/v1/transactions   (retry)
  Idempotency-Key: abc-123      →    Idempotency-Key: abc-123
  201 {data: …}                      201 {data: …}  + Idempotency-Replay: true
  ```

### P9 — The write path (one shape, every context)

1. Build the changeset (per-kind validation as today).
2. Open an `Ecto.Multi` with the business operation.
3. Pipe through `Journal.record(multi, actor, opts)`.
4. `Repo.transaction/1`.
5. Return the tagged tuple (`{:ok, _} | {:error, changeset}`).

No context write happens outside this shape once the context is journaled.

### P10 — The engine call path (one shape, every analytic)

1. Shell (controller/LiveView) computes `as_of` and authorization.
2. `EngineData.<Name>` loads and validates the `Input` struct.
3. `Engines.<Name>.run(input, as_of)` computes (pure).
4. Presenter wraps the result + `meta` (P7).

LiveViews and API controllers share loader + engine — computation is never
duplicated in a view. Engine outputs are plain structs/maps of Decimals and Dates;
formatting, strings, and gettext live in the presentation layer only.

### P11 — Test discipline for degraded data and fixtures

- ConnTest helper pair `assert_ok_clean/1` and `assert_ok_degraded/2
  (expected gaps)`; a meta-test forbids bare `json_response(conn, 200)` assertions
  in analytics endpoint tests — silent degradation must be asserted, not ignored.
- Contract-fixture generation (D5) is deterministic by spec: frozen clock,
  deterministic IDs, canonical JSON key ordering — regeneration produces diffs only
  on real contract changes.
- Volume fixtures (D9): generator under `test/support/volume/`, fixed committed
  seed.

### P12 — MCP tools and mix tasks

- MCP tools continue `portfolixir.<resource>.<verb>`; analytics are reads
  (`portfolixir.portfolios.irr`, `portfolixir.portfolios.briefing`).
- Mix tasks are namespaced: `mix portfolixir.contract.gen` (fixture regeneration),
  `mix portfolixir.perf` (D9 operator measurement). Never bare task names.

### Enforcement — rule-to-test mapping

| Pattern | CI gate (meta-test) |
|---|---|
| P1 journal completeness | guard-trigger test + completeness property test |
| P1 non-journaled allowlist | `journal_allowlist_test.exs` |
| P2 actor on writes | `write_actor_test.exs` (AST, classifier above) |
| P3 engine purity | `engine_purity_test.exs` (whitelist + deny list) |
| P5 scenario prefix | `scenario_schema_test.exs` + telemetry query guard |
| P6 route scopes | `route_scope_test.exs` (fail-closed) |
| P7 closed enums | enum module + contract fixtures |
| P11 assertion discipline | analytics-test meta-check |
| Routing-table exemplars | exemplar-existence meta-test |

Pattern changes are PR-visible amendments to this document — never silent drift.

### Anti-patterns

| Forbidden | Instead |
|---|---|
| Actor via process dictionary | Actor struct as first argument (P2) |
| Journal insert outside `Portfolixir.Journal` | `Journal.record/3` in the Multi (P1, P9) |
| `Repo`/clock/HTTP inside `Portfolixir.Engines.*` | Loaders load (P4), shell passes `as_of` (P10) |
| Computation duplicated in a LiveView | Call the shared loader + engine (P10) |
| Ad-hoc flag/gap strings | Extend the enum module + fixture (P7) |
| Floats in financial code | Decimal everywhere; only `Engines.Xirr` is the documented float island (P3/D10) |
| New endpoint without scope, MCP mirror, fixture | Classify (P6), mirror or explicit n/a, add fixture (D5) |
| Bare 200 assertions on analytics endpoints | `assert_ok_clean` / `assert_ok_degraded` (P11) |

## Project Structure & Boundaries

> **⚠️ This section describes a repository that does not exist. Do not build from it.**
>
> Verified against `main` on 2026-08-12. The delta tree below was written as a plan
> and reads as a description, which is the specific way it causes damage: an agent
> that follows it does not discover the mismatch, it *builds* the missing half and
> creates a second architecture beside the real one.
>
> | Path below | Reality on 2026-08-12 |
> |---|---|
> | `engines/irr.ex`, `xirr.ex`, `benchmark.ex`, `income.ex`, `scenario.ex` | `engines/` contains exactly one module, `bucket_resolution.ex`. Analytics live in the ordinary contexts |
> | `engine_data/` loaders (1:1 paired) | **Never created.** The 1:1 pairing is additionally withdrawn as a rule — see re-validation Critical Gap 3: three loaders sharing an FX/date basis must agree with each other, which is duplicated query logic over Decimal money |
> | `exports/portfolio_performance.ex` | **The PP-compatible export was dropped** (owner decision 2026-07-22, FR-DI-18). Portfolixir is a one-way import destination; egress is the JSON API. Backup/restore survives separately (#354) |
> | `scenarios.ex`, `scenario_` tables | Never created. What-if against stored price history is now ladder level (d) and **gated** |
> | `idempotency.ex`, `plugs/idempotency.ex` | Never created |
> | `controllers/api/v1/meta.ex` | Never created. 37 API controllers render through the single presenter `json.ex` |
> | `router.ex` with `:api_read` / `:api_write` | Never created. `:api` / `:api_auth` only |
> | `mix portfolixir.contract.gen`, `mix portfolixir.perf` | Never created. Existing tasks: `portfolixir.backfill_settlement_legs`, `portfolixir.seed_scope_buckets` |
> | `test/engine_purity_test.exs`, `route_scope_test.exs`, `fixtures/contract/`, `support/volume/` | Never created |
> | — | **Missing from the tree entirely:** the shipped contexts `buckets/`, `tax/`, `settings/`, and `clock.ex` |
>
> **What did land as written:** `actor.ex`, `journal/` (`entry.ex`, `serializer.ex`,
> `allowlist.ex`), `write_actor_test.exs`, and `boundary_test.exs` — shipped as
> `test/invariants/web_repo_boundary_test.exs`.
>
> The routing table earlier in this document points at several of the paths above.
> Those pointers are dead. Until a path-existence test guards them (re-validation
> Repair Options, O4), treat every path in this section as unverified.

The existing repository structure is authoritative and unchanged. This section maps
only the NEW components (D1–D11) into it. Paths not listed here follow the existing
conventions. The gated XML import (FR-5) moves INTO the existing `imports/` context
— it is not a new boundary.

### New/Extended Directory Structure (delta tree)

    lib/portfolixir/
    ├── actor.ex                        # P2 — standalone value module (no context)
    ├── journal.ex                      # P1 — context, Journal.record/3 (Multi)
    ├── journal/
    │   ├── entry.ex                    #   schema (audit_journal)
    │   ├── serializer.ex               #   single JSONB encoder (Decimal→string)
    │   └── allowlist.ex                #   closed list of non-journaled write paths
    ├── engines/                        # P3 — pure core (whitelist-gated)
    │   ├── types.ex                    #   shared structs
    │   ├── irr.ex                      #   Decimal orchestration + Input struct
    │   ├── xirr.ex                     #   documented float island (root finding)
    │   ├── benchmark.ex                #   FR-9 (incl. after-cost/after-tax dimension)
    │   ├── income.ex                   #   FR-10
    │   └── scenario.ex                 #   FR-27 overlay series (pure; persistence
    │                                   #   lives in the scenarios/ context)
    ├── engine_data/                    # P4 — shell loaders, paired 1:1
    │   ├── series.ex                   #   shared series/query helpers (quote, FX,
    │   │                               #   transaction scopes — at_or_before etc.)
    │   ├── irr.ex
    │   ├── benchmark.ex
    │   ├── income.ex
    │   └── scenario.ex
    ├── scenarios.ex                    # P5 — context module (CRUD, persistence)
    ├── scenarios/
    │   ├── scenario.ex                 #   schema (scenario_ tables)
    │   └── scenario_transaction.ex
    ├── exports/
    │   └── portfolio_performance.ex    # FR-29 export — serializer = importer's
    │                                   # mirror (grep for module collisions first;
    │                                   # backup half = docs/backup-restore.md)
    ├── idempotency.ex                  # P8 — context module (plug delegates here;
    ├── idempotency/                    #   web layer never touches Repo)
    │   └── key.ex                      #   schema, unique (token, key)
    ├── sync/                           # Phase 3 ONLY — created by its first story
    │                                   # after the scope-gate ADR (planned boundary)
    └── pensions/                       # Phase 4 ONLY — after the discovery story
                                        # (planned boundary)

    lib/portfolixir_web/
    ├── controllers/api/v1/meta.ex      # P7 — closed flag/gap enums, beside json.ex.
    │                                   # PROJECTS domain enums, never defines them;
    │                                   # contract.gen asserts envelope ≡ schema enums
    ├── controllers/api/v1/briefing_controller.ex  # D7 aggregate (only new controller)
    ├── plugs/idempotency.ex            # P8 — delegates to Portfolixir.Idempotency
    └── router.ex                       # P6 — :api_read / :api_write pipelines

    New analytics actions (e.g. GET /portfolios/:id/irr) live in the EXISTING
    resource controllers beside their siblings (performance, valuation). ALL new
    actions render through the single presenter
    lib/portfolixir_web/controllers/api/v1/json.ex — no per-controller JSON modules
    (no briefing_json.ex).

    lib/mix/tasks/
    ├── portfolixir.contract.gen.ex     # D5 — deterministic fixture regeneration
    └── portfolixir.perf.ex             # D9 — operator measurement (one command)

    priv/repo/migrations/
    ├── *_create_audit_journal.exs      # + append-only & guard triggers (P1).
    │                                   # Triggers are raw SQL — the test DB must be
    │                                   # built via migrations (no schema-dump path)
    ├── *_create_idempotency_keys.exs   # unique (token, key)
    └── *_create_scenario_tables.exs    # scenario_ prefix (P5)

    test/
    ├── engine_purity_test.exs          # P3 gate (whitelist + deny list, Xirr
    │                                   #   exception encoded explicitly)
    ├── write_actor_test.exs            # P2 gate (classifier + grandfather list)
    ├── route_scope_test.exs            # P6 gate (fail-closed)
    ├── boundary_test.exs               # NEW gate: web layer never references Repo
    │                                   #   (was convention-only; FR-28 prerequisite)
    ├── portfolixir/journal/allowlist_test.exs   # mirror path (module unit test)
    ├── portfolixir/scenarios/          # mirror path incl. schema/prefix test
    └── support/
        ├── volume/                     # D9 generator + committed seed
        ├── fixtures/contract/          # D5 generated+committed fixtures; CI
        │                               #   freshness check (regenerate, diff, fail);
        │                               #   TS reads via ONE config constant
        ├── fixtures/golden/            # analytics oracles, provenance per file (D3)
        └── fixtures/scenarios/         # scenario test fixtures (day one)

    mcp-server/src/tools.ts             # new tools mirror new endpoints (P12)
    docs/backup-restore.md              # FR-29 backup half (published site —
                                        # docs_test.exs ripple applies)

### Requirements-to-Structure Mapping

| FR category | Lands in |
|---|---|
| A — Ledger & integrity (FR-1–4, 28) | `journal/`, `actor.ex`, existing contexts (actor refactor) |
| B — Import & reconciliation (FR-5–7, 29) | existing `imports/` (XML behind gate ADR), `exports/`, `docs/backup-restore.md` |
| C — Analytics engine (FR-8–12) | `engines/` + `engine_data/` + actions in existing API controllers |
| D — LLM/MCP surface (FR-13–16) | `controllers/api/v1/meta.ex`, presenter, `mcp-server/`, contract fixtures |
| E — Read-only sync (FR-17–21) | `sync/` — Phase 3, created only after the scope-gate ADR |
| F — Product types (FR-22–25) | `catalog/` extensions, `pensions/` — Phase 4, after discovery |
| G — Planning & simulation (FR-26–27) | `scenarios/`, `engines/scenario.ex` (+ retirement engine later) |

### Architectural Boundaries

- **Dependency direction (unchanged + extended):** web/MCP → contexts → Repo.
  New: contexts → `Journal` (write path); shell/`engine_data/` → `engines/`
  (never the reverse; input types live in `Engines.Types`); `engines/` → nothing
  impure (P3 whitelist).
- **Web→Repo abstinence is now a gate**, not a convention: `boundary_test.exs`
  scans `lib/portfolixir_web/` for `Repo` references (closes the open invariant
  named in project-context.md and required by FR-28).
- **Journal boundary:** the only module touching `audit_journal` is
  `Portfolixir.Journal`; DB guard triggers enforce it below the app layer.
- **Scenario boundary:** the `scenarios` context persists; the scenario engine only
  computes. Scenarios write only `scenario_` tables; live contexts never read
  `scenario_` tables (telemetry guard, P5).
- **MCP boundary (ADR-0002, unchanged):** `mcp-server/` speaks only to `/api/v1`;
  its only repo coupling is the read-only contract-fixture path (one constant).
- **Enum source of truth:** domain schemas own enums; `Api.V1.Meta` projects them;
  the fixture generator asserts equality — drift is a CI failure.
- **Gated boundaries:** `sync/` and `pensions/` are planned boundaries — creating
  files there requires the respective scope-gate ADR / discovery story first.

### Data Flow (one line each)

- Write: UI/API/MCP → context (actor-first, P9) → Multi + Journal → PostgreSQL.
- Analytic: shell → loader (P4) → engine (P3) → presenter + meta (P7) → UI/API/MCP.
- Scenario: loader (live read) → scenario engine → `scenarios` context persists to
  `scenario_` tables / overlay response — never the real ledger.
- Export: `exports/` reads via contexts → PP-format file; backup = documented
  dump/restore (FR-29 split).

## Architecture Validation Results

Validation was hardened in two rounds: a five-method elicitation pass
(self-consistency, inversion, critical challenge, assumption audit, cascading
failure) and an independent three-agent implementation review (architect, test
architect, implementing engineer as separate subagents). Findings that sharpen
or amend D/P content are recorded as Binding Spec Amendments below.

### Coherence Validation ✅

**Decision Compatibility:**
D1–D11 were checked pairwise against each other and against the 12 accepted ADRs;
no contradictions found. The load-bearing combinations hold up: D1 (journal in the
same DB transaction) + D2 (pure engines) keep journaling strictly in the shell —
engines compute, the shell writes and journals. D10's float island is the single,
explicitly encoded exception to the Decimal discipline (P3 carries it as a named
per-module exception, not a loophole). D6's 200-plus-gap-markers refusal contract
is additive to the existing `Api.V1.JSON` shape, so no existing consumer breaks.
D4 (scopes), D1 (actor taxonomy), and D11 (idempotency) form one coherent
write-safety story and ride the same refactor. No new technology versions are
introduced anywhere — version truth stays in `mix.lock`/`package-lock.json`/CI,
which is itself a recorded decision. One detail resolved during validation: the
`idempotency_keys` table is operational state, not financial data — it is NOT
journaled and does not carry the P1 guard trigger (it never appears in the
journal allowlist because the allowlist governs only journaled-table writers).

**Pattern Consistency:**
Every pattern P1–P12 traces back to at least one decision D1–D11, and every
decision that constrains implementation has at least one pattern operationalizing
it. Naming is uniform: closed taxonomies everywhere (actor types, operation enum,
resource-type codes, flag/gap vocabularies, engine whitelist) — the same
closed-set philosophy as ADR-0011's kind set, applied consistently to every new
seam. The routing table gives implementing agents a deterministic entry point per
task type, and the exemplar-existence meta-test keeps it from rotting.

**Structure Alignment:**
The delta tree maps every new component to a concrete path inside the existing
modular-monolith layout; dependency direction (web/MCP → contexts → Repo,
shell → engines, engines → nothing impure) extends the existing one-way rule
without exception. Gated boundaries (`sync/`, `pensions/`) are declared as
planned-but-empty, which prevents premature scaffolding. Scenario isolation is
structural (table prefix + telemetry guard + property tests), not conventional.

### Requirements Coverage Validation ✅

**Functional Requirements Coverage (29 FRs, 7 categories):**

| Category | Coverage |
|---|---|
| A — Ledger & integrity (FR-1–4, 28) | FR-1 is the existing spine + the FR-1 carve-out concern (CC-10) for stored entitlements; FR-2 via existing validation + #343 (tracked); FR-3 via D3 sequencing (#344 content deliberately deferred, owner named); FR-4 named as explicit single-portfolio-debt workstream; FR-28 fully designed (D1, P1, P2, P9) |
| B — Import & reconciliation (FR-5–7, 29) | FR-5 behind scope-gate ADR incl. idref-resolver note; FR-6/7 existing, preserved by D11 + journal; FR-29 split into backup (docs) + PP export (`exports/`), losslessness gated on #344, PP-in-the-middle named as not CI-automatable |
| C — Analytics engine (FR-8–12) | Engines/loaders architecture (D2, P3, P4, P10); FR-8 IRR via D10; FR-9 incl. after-cost/after-tax delta and shared scenario/series engine (CC-8); FR-10/11 as engine + existing allocation extensions; FR-12 wording behind its gate |
| D — LLM/MCP surface (FR-13–16) | D5 contract fixtures, D6 envelope, D7 taxonomy, P7, P12; parity becomes mechanical instead of PR-review convention |
| E — Read-only sync (FR-17–21) | Phase-3 planned boundary behind scope-gate ADR; provider-behaviour pattern, credential encryption deferred to its own ADR — deliberate, not missing |
| F — Product types (FR-22–25) | Phase-4 planned boundary; each FR preceded by discovery story; pension-constants versioning named (CC-10) |
| G — Planning & simulation (FR-26–27) | `scenarios/` context + scenario engine + isolation invariants (P5, D2); FR-26 retirement engine joins the same engine family after its discovery story |

All six user journeys map onto covered FRs (UJ-1/3 → C+D, UJ-2 → B, UJ-4 → F+G,
UJ-5 → G, UJ-6 → FR-4 workstream). All three success metrics have their
architectural enablers (1 → FR-29 split + PP-parity harness, 2 → D5/D6/D7,
3 → Phase-4/5 boundaries + discovery stories).

**Non-Functional Requirements Coverage:**
NFR-1/2 are the document's prime directives (D1, D3, oracle provenance,
read-path provenance via D6). NFR-3 is operationalized by the enforcement
mapping — every architectural rule has a named CI gate. NFR-4 is extended by D4
(graduated scopes, fail-closed). NFR-5/6/7 are unchanged brownfield decisions.
NFR-8 gets a measurement apparatus plus an explicit caching trigger (D9) instead
of an unverifiable target.

### Implementation Readiness Validation ✅

**Decision Completeness:**
All 11 decisions are documented with rationale, scope, and named residual risks;
deferred decisions are listed explicitly with their trigger conditions and owners
— nothing is silently open. No-new-versions is itself the recorded versioning
policy for this brownfield repo.

**Structure Completeness:**
Delta tree covers every new module, migration, test gate, mix task, and doc file
down to file level, including mirror test paths and fixture locations. Existing
structure is referenced, not restated — consistent with the baseline rule.

**Pattern Completeness:**
The routing table plus P1–P12 plus the anti-pattern table close the known
divergence points. Mechanically gated: P1, P2, P3, P5, P6, P7, P11 (meta-tests
per the enforcement mapping) and P8 (DB unique constraint). Convention-guided:
P4 (loader pairing), P9/P10 (call shapes), P12 (naming) — named as accepted
residual convention, mitigated by the routing table and exemplar files.

### Gap Analysis Results

**Critical Gaps:** none. No architectural decision required for Phase-1/2
implementation is missing or unowned.

**Important Gaps (sequenced, with owners — not blocking the document):**

1. **PRD amendment for FR-9** (after-cost/after-tax dimension + tax-depth OQ) is
   recommended in this document but not yet applied to the PRD. Owner: maintainer.
   Risk if skipped: epics inherit the flattering pre-cost wording.
2. **Golden question set** does not exist yet; it is the declared prerequisite of
   the D7 aggregate-endpoint stories (Phase 2). Owner: maintainer.
3. **#344 rounding policy** remains the single sequencing blocker — and not only
   for golden-master scaling and FR-29 acceptance criteria: D10's boundary
   rounding depends on it, making #344 a critical-path item for the FIRST
   Phase-2 analytics story (IRR, #316). Owner: maintainer. The architecture is
   deliberately complete without its content.
4. **P2 write-classifier feasibility spike:** the classifier requires detecting
   that a public function transitively reaches `Repo.*` writes — call-graph
   analysis, not plain AST pattern-matching, and static analysis (AST or
   `mix xref`) systematically misses writes hidden in closures
   (`Ecto.Multi.run/3` anonymous functions), producing silent false negatives.
   The spike must therefore combine a static gate with a runtime check in the
   test env (telemetry on every Repo write asserting actor presence). Spike
   lands before the actor refactor starts; named fallback: explicit annotation
   plus grandfather list, recorded as the weaker guarantee if chosen. This is
   the technically riskiest meta-test in the document, and D1's completeness
   guarantee leans on it — it is a prerequisite, not a backlog item.

**Nice-to-Have Gaps:**

- A worked end-to-end example of one engine story (loader + engine + envelope +
  fixtures) would help the first implementing agent; the routing table plus
  exemplar files mitigate this.
- The FR-4 single-portfolio-debt workstream has no pattern of its own — it lives
  in existing contexts under existing conventions; first story should confirm.

### Binding Spec Amendments (from validation)

The following amendments sharpen D/P content and are binding — stories reference
them like patterns. They originate from the three-agent implementation review.

1. **Guard-trigger arming is per-context, not big-bang (amends P1/D1 sequencing).**
   Each context's journaled tables are armed by their own migration as soon as
   that context is fully actor-first. Refactor order is leaf-first:
   Catalog/Fx → Portfolios/Classifications → Ledger → Imports. A meta-test
   couples the two mechanically: if a context's grandfather list is empty but
   its tables are not armed, CI fails. Writes before arming are a documented
   audit-trail gap (consistent with the no-backfill decision).
2. **Sandbox semantics (P1).** The guard trigger reads
   `current_setting('portfolixir.journal_actor', true)` (missing_ok — absence
   must raise the defined guard exception, not
   `unrecognized configuration parameter`). `Journal.record/3` prepends the
   `SET LOCAL` step via `Ecto.Multi.prepend/2` AND resets the variable in a
   final step — under the Ecto sandbox a test's outer transaction would
   otherwise keep the variable alive past the business transaction (false
   negatives). Guard-trigger tests run `async: false` outside the sandbox
   (dedicated tag, real commit + cleanup).
3. **Test fixtures go through real actor-first context writes (P1/P2).** No
   test entry in the journal allowlist, no GUC-setting test helper — anything
   else re-opens the bypass P2 exists to close.
4. **`Journal.record/3` semantics (P1).** The caller declares what to journal:
   arg 3 is opts carrying `resource_type` and the named Multi steps to journal.
   `before` comes from changeset `data`; `after` is built in a `Multi.run` step
   placed after the named business steps. No Multi introspection magic.
5. **P8 idempotency mechanics.** Body comparison: SHA-256 over the raw request
   body (custom `:body_reader` in `Plug.Parsers`). Replay restores status,
   body, and an explicit header allowlist (`content-type`, plus
   `Idempotency-Replay: true`) — never request-scoped headers. Concurrency:
   reserve-first (`pending` row insert; the unique constraint decides);
   a concurrent request hitting a `pending` key gets `409` + `Retry-After`.
   Only final responses (2xx/4xx) are stored; a 5xx frees the key.
6. **D5 determinism is specified, not hoped for.** Canonical serialization
   (sorted JSON keys), frozen clock, fixed seed data — and a meta-test that
   runs the generator twice and asserts byte-identical output. Without this,
   the freshness check flakes, gets demoted, and D5 becomes theater.
7. **Meta-enforcement gate.** In an agent-edited repo, every enforcement
   artifact the agent can edit is soft. PRs that change enforcement artifacts
   (contract fixtures, purity whitelist, grandfather/allowlists, golden
   masters) together with code require an explicit marker; CI fails on silent
   co-modification. Stale grandfather entries (entries that no longer match a
   violation) fail the test — shrink is forced, not hoped for.
8. **Golden-master tolerance policy (amends D3).** Decimal-exact expectations
   everywhere except the XIRR float island, which carries a documented
   per-metric epsilon. PP cross-checks require a documented convention mapping
   (day-count, rounding) — otherwise deviations are convention mismatches, not
   bugs, and the oracle is no oracle. A meta-test asserts every golden fixture
   carries a provenance reference (committed derivation artifact).
9. **FR-27 write-isolation gate is schema-driven (amends D2/P5).** The
   zero-writes assertion enumerates tables from `information_schema` with a
   `scenario_` allowlist — everything is protected by default; a hardcoded
   table list would rot. The read-isolation property compares the FULL
   envelope (including flags/gaps), with caching ruled out as a trivializer.
10. **D9 additions.** The CI perf smoke gets an explicit promotion criterion
    (non-blocking → blocking after N runs under a variance threshold; median
    over repetitions). The generated dataset's checksum is committed and
    asserted — StreamData seed stability across versions is not guaranteed.
11. **Restore/DR procedure (P1).** `docs/backup-restore.md` documents restore
    against the journal triggers (`session_replication_role = replica`) — the
    first disaster recovery must not be the discovery. Partitioning is named
    as the intended answer to journal growth (pre-empting a future ADR debate).
12. **P11 inverted to whitelist; serializer mapping pinned.** Analytics test
    directories allow ONLY the two assert helpers (blacklisting
    `json_response(conn, 200)` is bypassable via helper indirection).
    `Journal.Serializer` carries an explicit type-mapping table (Decimal,
    Date, atoms, nested structs) with a fallback `raise` on unmapped types.

### Validation Issues Addressed

- **Idempotency-table journaling status** was undefined → resolved as a binding
  clarification amending P1/P8: `idempotency_keys` is operational state, not
  financial data — NOT journaled, carries no guard trigger, never appears in
  the journal allowlist (which governs only journaled-table writers).
- **Journal activation order** was initially specified as big-bang arming after
  the last context refactor → superseded by Amendment 1 (per-context arming
  with mechanical coupling), on convergent architect + engineer review findings:
  big-bang leaves the longest unprotected window and hides process state
  outside the code.
- **FR-26 engine placement** was implicit → confirmed: retirement engine joins
  `Portfolixir.Engines.*` after its discovery story; no structural change needed.
- No contradictions between decisions, patterns, and structure were found.

### Architecture Completeness Checklist

**Requirements Analysis**

- [x] Project context thoroughly analyzed
- [x] Scale and complexity assessed
- [x] Technical constraints identified
- [x] Cross-cutting concerns mapped

**Architectural Decisions**

- [x] Critical decisions documented with versions (brownfield: version truth
      deliberately delegated to lockfiles/CI — a recorded decision, not an omission)
- [x] Technology stack fully specified
- [x] Integration patterns defined
- [x] Performance considerations addressed

**Implementation Patterns**

- [x] Naming conventions established
- [x] Structure patterns defined
- [x] Communication patterns specified
- [x] Process patterns documented

**Project Structure**

- [x] Complete directory structure defined
- [x] Component boundaries established
- [x] Integration points mapped
- [x] Requirements to structure mapping complete

### Architecture Readiness Assessment

**Overall Status:** READY FOR IMPLEMENTATION

**Confidence Level:** Medium-High — high in the design, medium in its
enforceability until the named spec amendments land. The verdict was
independently re-derived three ways (checklist-driven, blocker-driven,
risk-driven) with consistent outcome, then stress-tested by a five-method
elicitation and an independent three-agent implementation review; all three
reviewers converged on READY-with-conditions. Phase-2 analytics start is
explicitly conditional on #344 and the P2 feasibility spike. Named residual:
D9's numeric per-operation budgets are deliberately TBD in the D9 story — the
apparatus is decided, the numbers are not.

**Key Strengths:**

- Fail-closed mechanical enforcement: every rule an agent must follow has a
  meta-test that fails when broken — matching NFR-3's "owner does not read code"
  reality.
- One seam, three payoffs: the pure-engine architecture (D2) simultaneously
  delivers FR-27 isolation, the future caching seam, and property-testability.
- Honest verification posture: oracle provenance, PP-parity harness, and the
  named limits (PP roundtrip not CI-automatable) prevent self-ratifying tests.
- Closed-taxonomy discipline applied uniformly to every new vocabulary.
- The meta-enforcement gate (Amendment 7) closes the loop the whole concept
  hangs on: enforcement artifacts themselves cannot drift silently.

**Areas for Future Enhancement:**

- Phase-3 sync architecture (provider adapters, credential encryption, OAuth2/
  PhotoTAN) — deliberately deferred behind the scope-gate ADR.
- Pension data model + versioned external constants — the FR-24/25 discovery story.
- Caching implementation — trigger condition defined in D9; ADR due when it fires.
- Escalation from JSON fixtures to OpenAPI codegen if fixture maintenance becomes
  the bottleneck (named in D5).

### Implementation Handoff

**AI Agent Guidelines:**

- Follow all architectural decisions exactly as documented
- Use implementation patterns consistently across all components
- Respect project structure and boundaries — and the Binding Spec Amendments,
  which override the unamended pattern text where they touch the same mechanism
- Refer to this document for all architectural questions

**First Implementation Priority:**
No initialization step (brownfield). Per the dependency-ordered sequence:
D2 pure-core rule (engine namespace + AST purity gate) and the D9 volume
generator land first — they are the foundations every engine story needs;
the P2 feasibility spike (Gap 4) runs before the actor refactor begins.
In parallel, the operator items: PRD FR-9 amendment, #344 decision, golden
question set.

---

## Architecture Re-Validation Results (2026-08-12)

This section re-validates everything above against the requirement base as it
stands on 2026-08-12. It does not replace the 2026-06-12 validation; it records
what that validation can no longer claim.

**Base of this re-validation:** founding PRD (2026-06-12, revised 2026-08-12 by
identity gate B3.1), PRD — Data Import & Sync (2026-06-21, revised 2026-07-25),
product brief 2026-08-12 (accepted as #663), `epics.md` as the live requirement
registry (FR-30…FR-48), ADR-0001…ADR-0038, and the code on `main`.

**Method.** Sequential validation, then a four-role adversarial roundtable
(architect, test architect, implementing engineer, product manager), then five
elicitation passes (reframing, weighted comparison, second-order effects,
inversion, steelmanning). Where the roles disagreed, the disagreement is
recorded rather than averaged away.

### Baseline Corrections (facts stated wrongly above)

| Stated above | Correct as of 2026-08-12 | Source |
|---|---|---|
| "LiveView 0.20.x (NOT 1.x idioms)" | Phoenix 1.8.9 / LiveView 1.2.8; the framework moved, the app's own patterns did not | ADR-0037, `project-context.md` |
| "12 accepted ADRs constrain all new work" | 38 ADRs; ADR-0013 superseded by ADR-0018 | `docs/decisions/index.md` |
| Closed kind set = 13 PP kinds + `balance_adjustment` | 15 kinds — `split` is first-class | ADR-0028, `ledger/transaction.ex` |
| FR-4 as a "single-portfolio-debt workstream" | Views are the user-facing grouping, buckets group within a view, portfolios are an internal compatibility record only | ADR-0024, ADR-0018, FR-4 (rev. 2026-08-12) |
| #344 rounding is the open sequencing blocker | Decided: full precision in compute, round only at the human display | ADR-0016 (2026-06-14) |
| FR-29 PP-compatible export + `exports/` | **Dropped** 2026-07-22; one-way import destination, egress is the JSON API | PRD-DI Feature E, #354 |
| 29 FRs in seven categories | FR-1…FR-48; `epics.md` is the registry | PRD status note, `epics.md` |

### Coherence Validation ⚠️ — partially superseded

Per-decision status is in the **Decision Status** table under "Core Architectural
Decisions". Summary: of eleven decisions, **one shipped** (D1), **one holds by
absence** (D8), **two were decided elsewhere with different content** (D3 → ADR-0016,
D10 → ADR-0034), **one was superseded in effect** (D7), and **six were never built**
(D2, D4, D5, D6, D9, D11) — one of which (D4) is additionally recorded as an open
decision in another document.

**Pattern consistency.** P1, P2, P9 are in force and gated. P3, P4, P7, P8 and the
contract-fixture half of P11 describe machinery that does not exist. P5 describes
isolation for a feature since gated at ladder level (d). P10 is followed in spirit —
loaders and read models exist — but not under the declared namespaces, so the routing
table points at paths a reader will not find.

**Structure alignment.** See the warning block on "Project Structure & Boundaries".

### Requirements Coverage Validation ❌ — the registry outgrew the document

| Requirement family | Architectural support here |
|---|---|
| FR-30…FR-36 (DX batch, identity ladder, tax snapshots) | None — all shipped since under ADR-0029/0030/0031, outside this document |
| FR-37, FR-38 (read ergonomics, `?since=` deltas) | None. Ungated, ship-now, and the agent-side success criteria attach to them directly |
| FR-39, FR-40 (derived metrics, ladder (a)) | None; the registry records them as dependent on the gate B3.2 derived-value ADR |
| FR-41, FR-42 (contribution, exposure — ladder (b)) | None |
| FR-43…FR-46 (knowledge objects) | None. Verified: they are **not** blocked by the journal rollout — that asserted dependency is false |
| FR-47, FR-48 (calibration, rule evaluation — ladder (c)) | None |
| FR-DI-1…FR-DI-21 (intake domain) | Partial and coincidental: the preview→apply shape matches; identity ladder, two-layer idempotency, PDF sandbox and per-broker parsers are all outside this document |

**Non-functional coverage.** NFR-1/2 hold and were strengthened by ADR-0016 and
ADR-0017. NFR-3 is this document's strongest surviving contribution — the gate
philosophy demonstrably materialized, and the pattern of *which* gates survived is
the most useful thing it produced (see "What sticks in this repository"). NFR-4 is
**weakened relative to the document's claim**: D4 asserts a decided scope model that
does not exist. NFR-8 is now governed by ADR-0032/0035 rather than by D9.

### Implementation Readiness Validation ❌

**Decision completeness.** Eleven decisions across five different authority levels,
and a reader could not tell which was which from the document itself. That is the
readiness defect, more than any individual gap — and it is the direct cause of D4
being DECIDED here and OPEN elsewhere for two months.

**Pattern completeness.** The routing table's premise — "read this before writing
code" — fails where it points at `Portfolixir.Engines.*` and `Portfolixir.EngineData.*`
for analytics work that lives elsewhere. The exemplar-existence meta-test it relies on
was never built either.

### Gap Analysis Results

#### Critical Gaps

**1. No architecture for the durable derived layer (gate B3.2) — and the three
decisions around it are one decision, not three.**

ADR-0032 (volatile memo), ADR-0035 (one pricing pass per read) and D2 (purity) were
each decided against a separate symptom. They collapse onto one axis: *a derived
value is a pure function value over a versioned, named input; everything else is how
long the result is kept.*

| Lifetime | Mechanism |
|---|---|
| `:none` | recompute every time |
| `:request` | ADR-0032, process-local memo |
| `:durable` | B3.2, table carrying `as_of` + data version |

The cache-key question is identical in all three cases, and it is FR-1's four
properties word for word: rebuildable = the function is reproducible from named
inputs; versioned = the key carries the data-version counter; never silent about
freshness = `as_of` travels with the value; never authoritative for a write = the
materialization is a cache, not a record.

**ADR-0035 is inherited, not opposed.** Removing a redundant call is strictly better
than caching it, because a cache costs invalidation and a deleted call costs nothing.
Materialization is admissible only for what remains after de-duplication. ADR-0032 is
genuinely superseded — it is the `:request` case of the same axis.

**OQ-A3 resolved: B3.2 is read speed only.** The question "must it conserve historical
values no longer reconstructable from today's transactions, e.g. the FX rate of that
day?" was posed as a threat to "rebuildable". It is not. Such a value fails *two* of
the four properties at once — not rebuildable, and the cache would be authoritative
for it — and an element failing a requirement on two independent counts is
misclassified, not evidence of a broken requirement. The FX rate of a given day is an
**observation**, not a derived value; it looks derived only because the valuation
pipeline consumed it without recording which rate row it used. The conservation
requirement therefore moves **upstream**: bind the valuation to its rate row with an
`as_of`, as a first-class stored fact with identity and provenance — the same shape
FR-43…FR-46 introduces for four other families. "Rebuildable" then becomes true again,
because the rebuild reads the rate stored *then*, not the rate today. This also
supplies the real acceptance criterion for drop-and-rebuild: a fixture with historical
rates must reproduce historical numbers exactly. A rebuild tested only against today's
rates does not test the property B3.2 promises.

**Which values are materialized is a measurement question**, and D9's apparatus — which
would answer it — was never built. Two caching-adjacent ADRs were already decided on a
felt symptom for that reason. A B3.2 ADR without a falsifiable trigger produces the
same situation a third time.

**2. No structural home for the knowledge objects — and the four-gate split
decomposes by data model where it should decompose by job.**

The job that broke is "I read a fact and know whether it still holds"; the four
properties that make a fact hold — identity, provenance, as-of, history — are stated
identically for all four objects. That is one structural decision plus four cheap
instances, not four decisions.

**Proposed first cut: security events alone** — the only one of the four whose success
is externally falsifiable without an opinion ("a purchase candidate with no holdings is
monitored for upcoming dates exactly like a held position"), and the one carrying the
hardest structural claim: it applies to **every security in the catalog, not only held
positions**, and it is **distinct from corporate actions** (ADR-0028). If both
boundaries survive implementation, the architecture has proven it can hold facts that
do not hang off the ledger. Predictions come last: their success criterion needs ten
resolved predictions and is measurable only months after the merge.

**Constraint on the first cut:** it must not ship "fast, without the frame". An object
landing without provenance and history does not prove the thesis — it creates a fifth
place where facts rot.

**3. D2 is a rule without a gate, and it was specified against the wrong thing.**

`engine_purity_test.exs` was never written; `Portfolixir.Clock.today/0` was introduced
afterwards and reads the host's local calendar date — the exact impurity class D2
governs, while D2's deny list names only `Date.utc_today`. The hole is the argument
*for* a gate, not against it: a deny list forbids **names** and ages against every new
source of non-determinism.

But the deeper finding is that both sides of the original disagreement — "move the code
into an engine namespace" versus "the contexts already suffice" — shared an unexamined
premise: **that purity is enforced statically, over the location of code.** It is not a
property of locations. Reproducibility under a named basis is a **behavioural property
of a value**, and the architect's own strongest argument ("the rebuild test *is* the
purity test") contradicts the statically-inspected namespace they proposed. That is why
this sat unresolved for two months: the only proposal on the table required a migration
with no story behind it, and the gate that needs no migration was never proposed.

A second premise underneath: both treat "today" as one quantity. There are two time
axes — `as_of` (the business day being valued) and **knowledge time** (when the answer
was produced). The bug that forced `Clock.today/0` — an event dated today judged to lie
in the future — is a bitemporality bug: "future" is a judgement relative to knowledge
time, not to the valuation date. `Clock.today/0` felt both necessary and impure because
it did knowledge-time work inside a valuation-time model.

**Resolution — adopt the property, drop the migration:**

1. Every analytic takes an explicit basis struct (`as_of`, `knowledge_date`,
   `data_version`, series, window, reference, gap treatment) and **echoes it in the API
   and MCP payload**. This is not a new rule: `AGENTS.md` already makes the computation
   basis a review-blocking criterion on every ladder-(a)–(c) metric. A computation basis
   *is* the enumeration of a function's inputs, so the project has already decided input
   explicitness in prose; this is its mechanical enforcement — and the story behind it is
   every metric story, past and future.
2. **Gate 1 (behavioural, blocking):** a meta-test enumerates registered analytics and
   asserts (a) complete basis in the payload, (b) reproducibility under two injected wall
   clocks, (c) equality after drop-and-rebuild. B3.2's cache key is then immediately
   writable: `(analytic_id, basis_hash, data_version)`.
3. **Gate 2 (static, whitelist):** permitted calls inside registered analytics — applied
   to the registration, not to a directory.
4. `Clock.today/0` stays, is demoted and renamed (`Clock.knowledge_date/0`), is permitted
   only in the shell and in validation, is forbidden inside registered analytics by the
   whitelist, and supplies an explicit field of the basis.
5. The `Engines.*` namespace drops from precondition to cleanup convention. **The 1:1
   loader pairing is withdrawn outright:** three loaders sharing an FX and cut-off basis
   would have to agree with each other, and duplicated query logic over Decimal money is
   the precise error class `AGENTS.md` demands exact expectations against. Shared dataset
   builders are explicitly allowed.

Named cost of this resolution: existing analytics probably violate the computation-basis
rule today, and retrofitting reproducibility tests for them is work without a feature.
That is a finding, not a nice-to-have.

**4. Write authorization: a decision was recorded as taken that was never taken — and the
answer turns out to be smaller than the gap suggested.**

Not a document conflict to reconcile: this document wrote "decided" where "assumed"
belonged, while the Data-Import PRD carried the same question as open (OD-4). Aligning the
two documents would be bureaucracy; writing the decision down is the deliverable.

**What the gap is *not* about, settled 2026-08-12:** whether the agent may write the
ledger. It may, it does, and the capability was deliberately widened after this document
was written. See the withdrawn recommendation below — it is recorded because how it was
nearly adopted is a more useful finding than the correction itself. What remains is
narrower and is about **attribution**, not permission.

Three findings frame that remainder:

- **The perimeter today is the network, not the token.** The web UI is deliberately
  unauthenticated, so whoever reaches `/api/v1` also reaches the LiveViews and writes the
  ledger with no token at all. Token scoping reduces reachable authority by zero — a lock
  on one of two doors to the same room. An `:api_read`/`:api_write` split over a single
  token is therefore not merely useless but harmful: a reviewer infers least privilege
  from it. In an NFR-3 regime, a **false** mechanical signal is worse than a missing one.
- **The journal actor is currently self-asserted.** With one shared token the actor is a
  claim by the caller, so the audit trail — the product's core — is exactly as trustworthy
  as the identity behind it. This is the one part that **cannot be retrofitted**: the
  identity of every write already made is not recoverable later.
- **If routes are ever classified, the deadline is earlier than it looks.** The ≤ 5-calls
  criterion will be met with **composite endpoints** that read *and* write, and such an
  endpoint is no longer classifiable at the router, by a test, or by a reviewer. With
  permission settled this is no longer a reason to classify — but it is the reason that,
  if classification is wanted for journal granularity, it cannot be deferred past the
  efficiency work.

The general principle this yields: *the governing timepoint is the last one at which a
control can still be introduced without migrating history or breaking contracts* — not the
point of need, and not the point of cheapest construction. Controls that are
information- or contract-shaped (stored identity, recorded history, wire contracts,
endpoint shape) must precede their consumers; controls that are purely enforcement-shaped
cost the same whenever they land and should wait.

**A recommendation this validation withdrew before merge — recorded, because the way it
was nearly adopted is the more useful finding.**

An earlier draft of this gap recommended **propose-then-confirm for agent-originated
ledger writes**, reasoning from the house rule "machine-extracted data is a proposal
until confirmed" and arguing that the ledger is not different from the import. The owner
rejected it on 2026-08-12, and the rejection is correct on three independent counts, each
checkable in the repository:

- **The rule does not reach this case.** `AGENTS.md` says *"anything extracted from an
  **unstructured source**"* — PDF intake, OCR, a broker statement. An agent booking a
  transaction on the operator's instruction extracts nothing from an unstructured source.
  The draft's move from "extracted" to "machine-originated" was an unargued widening.
- **It contradicts the identity.** Two first-class users, the agent the *primary*
  consumer, capabilities may ship agent-first. A confirmation gate on the agent's own
  write path demotes one of the two users.
- **It would roll back shipped behaviour that was deliberately widened.**
  `portfolixir.transactions.create` / `.update` / `.delete` ship today; FR-31 (#581)
  expanded `create` from `buy`/`sell` to all 13 kinds *precisely because* the
  create-as-buy→update-to-dividend detour was operator pain; and the reconcile tool's own
  description instructs the agent to resolve a difference by booking the missing
  transaction via `transactions.create`. Asking "may the agent create transactions?" was
  asking whether to withdraw the answer to "how do transactions get into the system for an
  MCP-first operator".

**The general lesson, which outranks the specific correction:** the analysis reached this
recommendation through a chain of individually sound arguments and never checked it
against shipped product state. Adversarial review and elicitation are good at internal
consistency and bad at noticing that the thing being reasoned about already exists and
works. **Any recommendation that would narrow an existing capability must cite the code or
requirement it narrows, before it is written down.** That check is cheap and was skipped
here.

**Resolution, with no owner question outstanding:**

1. **No `:api_read`/`:api_write` pipelines.** D4 as recorded is superseded; the
   contradictory OD-4 "open" note is closed with it.
2. **The agent writes the ledger directly. This is settled product identity, not an open
   question** — one token, full authority, deliberately. The ADR writes down today's
   posture *as a decision* with its threat model: the real perimeter is the network plus a
   deliberately unauthenticated UI, so a token scope would decorate rather than protect.
3. **Named principals — the one item that survives, and it is about attribution, not
   permission.** Token configuration becomes a list of `{name, token}` with exactly one
   entry today, and the journal actor is derived from the *matching entry* rather than
   supplied by the caller. Today the actor is a claim by the caller, so the audit trail is
   exactly as trustworthy as the identity behind it. This is worth doing on its own terms
   and is **independent of who may write**: it is the only part that cannot be
   retrofitted, because the identity of writes already made is not recoverable later.
4. **Route classification is downgraded to optional.** With permission settled, its
   remaining value is attribution granularity in the journal, which is thin. It is no
   longer recommended as its own work; if the composite-endpoint work for the ≤ 5-calls
   criterion lands anyway, classify the routes then, as a map and never as a control.
5. **Deadline for named principals:** the same or the next epic batch as the first
   knowledge-object family, enforced as a close-out finding — the project's own two-way
   coverage pattern.

The second-order analysis behind the withdrawn recommendation still holds where it was not
about permission: an unattended 03:00 run has no human, so any confirmation step becomes an
inbox that is either left to rot or rubber-stamped — a control that looks like protection
and is not. That argument is now an argument *for* direct writes, and `AGENTS.md`'s "a
human **or an agent** confirms" reading is left alone rather than tightened.

#### Important Gaps

5. **The delta tree retains `exports/portfolio_performance.ex`** for a feature dropped
   2026-07-22, and the FR-29 apparatus built around it (fidelity spike, PP-parity harness,
   "roundtrip is not CI-automatable") is void. ADR-0029 already depends structurally on the
   rescope.
6. **D9's apparatus was skipped and its trigger never fired.** Either it is genuinely
   wanted — then it is unowned work — or the trigger model should be retired rather than
   left standing as governance nobody uses. It is revived by exactly one thing: a named
   rebuild-time budget for B3.2, because drop-and-rebuild is the emergency procedure and an
   emergency procedure with unknown runtime is not one.
7. **D10's failure contract is wrong as written** (`{:error, :no_convergence}` versus
   ADR-0034's "n/a"), as is the implied placement.
8. **P7's envelope is narrower than the identity gate now requires** — see Critical Gap 3,
   resolution step 1.
9. **FR-27 what-if is now ladder level (d)**, forbidden behind its own gate and revisited
   after the policy-rules work (B3.6). P5's isolation invariants remain sound and should be
   preserved for whenever the gate opens.

#### Nice-to-Have Gaps

10. The golden question set (D7) was never produced and is no longer the binding artifact.
11. D5's contract fixtures remain the largest unguarded cross-language seam.

### Repair Options

The precedence rule this validation first proposed repairs *contradictions*. The document
has three defect classes and only one is a contradiction:

- **Superseded** (D1, D3, D10, partly D4): a later ADR decided otherwise. Precedence
  repairs this cleanly.
- **Never redeemed** (D2, D9): nothing was revised, nothing was built. There is no winning
  ADR to point at, so precedence leaves the rule standing — and, worse, its own wording
  ("the document stays authoritative for seams no ADR covers") *raises* the authority of an
  unredeemed build order.
- **Never addressed** (FR-37…FR-48, B3.2): precedence cannot speak about what is absent.

| Option | What it does | Cost | Weighted score |
|---|---|---|---|
| **1 — Precedence rule alone** | states ADR-wins, registry-wins | ~1 hour | 2.75 |
| **2 — Reduce to a seam contract** | precedence, plus delete superseded decisions to one-line pointers, plus move D2/D9 into the gate ADR that needs them | ~1 day | 3.35 |
| **3 — Full architecture re-run** | rewrite sections 1–6 | days | 1.95 |
| **4 — Mechanical repair first** | a test asserting every referenced path exists; structure section deleted rather than annotated until green | ~half a day | 4.20 |
| **4 + 1 combined** | the test tilts the never-redeemed class, precedence covers the superseded class | ~half a day + 1 hour | **4.55** |

Criteria and weights: agent-implementer misdirection 0.25, mechanical enforceability
(NFR-3) 0.20, owner time and attention 0.15, twelve-month decay resistance 0.15,
preservation of the still-load-bearing seams 0.10, connection to B3.2/FR-37…48 0.10,
reversibility under a wrong assumption 0.05. Three analysts scored independently; four
scoring disagreements were recorded and **none changes the ranking**. A sensitivity test
granting the long-horizon analyst their maximum re-weighting still yields O4 3.80, O2 3.40,
O1 2.45, O3 2.15. **No plausible weighting makes Option 3 win** — its problem is not price
but decay resistance: it buys a half-life demonstrably measured at two months, at the
highest price in the field.

**Decision taken here: options 4 + 1, executed in this document as of 2026-08-12**, with
option 2 deferred into the batch that opens gate B3.2 rather than paid for separately —
because moving D2 and D9 into that ADR requires an owner sign-off that is due anyway when
the gate opens, and buying it twice is waste. The path-existence test is named as follow-up
work rather than written here; until it exists, the warning block on the structure section
is the interim measure.

**The two answers that made this decision available**, both verified rather than assumed:

- **OQ-A1 — is this document loaded as agent context? No.** Nothing in `CLAUDE.md`,
  `AGENTS.md` or `README.md` references it; the README points at the maintained
  `docs/architecture.md`. It reaches an agent only when a human names it.
- **OQ-A2 — does it still have a mandate for FR-37…FR-48? No.** `epics.md` is the registry
  and the ADR chain is the decision authority. Its job is now the seam contract described in
  the header block.

Both answers being negative is precisely the case in which archival, not repair, is the
economically correct action. It is **not** taken, for one reason: a handful of seams here —
the P9/P10 call shapes, the anti-pattern table, D5's direction, D11's direction, P5's
isolation invariants — exist in no other document, and archival would lose them with no
recovery path. That is a deliberate exception to the analysis, recorded so it can be
revisited: once those seams have ADRs of their own, this document should be archived rather
than maintained.

### What Sticks in This Repository (the most useful finding)

The pattern of what survived two months and what did not is more valuable than any single
gap, because it predicts which future rules will hold.

**Survived and load-bearing:** `write_actor_test.exs` (empty, shrink-only grandfather list),
`web_repo_boundary_test.exs`, `decimal_persistence_test.exs`, `projection_no_catch_all_test.exs`,
`mcp_dependency_allowlist_test.exs`, the journal append-only tests that issue a real
UPDATE/DELETE and assert the raise, and the closed-taxonomy discipline — the kind set
absorbed `split` through exactly the extension protocol this document described.

**Died:** the purity gate, contract fixtures, the exemplar-existence meta-test, the
assertion-style whitelist, the measurement apparatus, and both meta-amendments.

The dividing line is neither importance nor effort. **A rule sticks here when all three
hold:** (i) it is expressible as a test today, without a structure having to exist first;
(ii) it checks a property, not a list of names; (iii) ordinary agent work hits it constantly,
so it proves itself continuously. It dies when it needs apparatus first, when it enumerates
instead of characterizing, or when its only enforcement is that someone remembers.

Applied to this document's own repair proposals, that rule predicted the ranking the weighted
matrix produced independently — which is the strongest evidence available that the criterion
is real.

### Failure Paths (inversion, twelve-month horizon)

| # | Path | Earliest observable symptom |
|---|---|---|
| **F1** | **Enumeration erosion — the gate stays green, the rule is dead.** Already occurred (`Clock.today/0`). Next candidates write themselves: an FX cache with a last-known fallback, `System.monotonic_time` in a window calculation, `Ecto.UUID.generate` in an idempotency chain | a new module wrapping a host resource, in a diff touching no file with `allowlist`/`denylist`/`purity` in its name |
| **F2** | **Meta-debt moves into an ADR and never gets an issue.** Occurred twice already. The mechanism is batch economics: batches close issues by keyword, and an ADR without an issue never enters a batch. Meta-work loses structurally, not through negligence | an accepted ADR with no `sprint-status.yaml` entry and no open issue after two close-outs |
| **F3** | **The document is never in an agent's context path** — confirmed today (OQ-A1) | zero hits for its filename or a `D`-number across the last twenty reviewer briefings, while ADR numbers appear in nearly all |
| **F4** | **Growth-only until it falls below the attention threshold.** The precedence rule alone actively legitimizes not deleting | six months of `git log --numstat` on the file with no net-negative commit |
| **F5** | **Golden masters without provenance ratify a convention forever.** FR-37…48 is exactly the work that copies its own output into the assertion, freezing an annualization convention or a drawdown sign | an assertion with more significant digits than any external source would yield, with no note on origin |
| **F6** | **The derived layer opens a second write path beside the journal.** The first materialization table raises a question this document never answers: who is the actor of a cache refresh? Answered ad hoc, the grandfather list loses its meaning **without gaining an entry** | the first migration creating a computed-value table together with `insert_all`/`update_all`, with `write_actor_test.exs` unchanged |
| **F7** | **Contract drift Elixir ↔ MCP, noticed by the agent rather than by CI** | a field name a controller test expects that appears nowhere in `mcp-server/` |
| **F8** | **Amplifier: the only human channel is structure-blind.** NFR-3 means the owner checks behaviour against a briefing. Structural drift produces no signal there by construction | none — that is the point |

**Most likely and most damaging: F1.** A missing gate costs protection; a **dead** gate
costs protection *and* trustworthiness, and once a second one is found the question stops
being "which gate is broken" and becomes "which gate can I still believe".

**Cheapest early warning, and the recommended first follow-up:** give every enforcement test
a **negative probe** — a synthetic violation fixture the same test must catch, failing if it
does not. Roughly ten lines per gate, no new infrastructure, immediately applicable to all
existing gates. It generalizes the one gate that demonstrably stayed sharp (the journal
append-only test issues a real UPDATE and asserts the raise). The resulting count — *"gates
with a negative probe: 3/9"* — belongs in every reviewer briefing from the next batch on,
because a number falling from 9/9 to 8/9 is the only thing an owner who reads no code can
see, and it reveals a dead gate before it has been lying green for two months.

**Honest limit on all counter-measures:** no artifact in this repository is agent-safe,
because the agent has write access everywhere and the owner reads no code. Hardening is
therefore not impossibility but **visibility in the one channel that works** — the reviewer
briefing. This is why Amendment 7's checkbox marker is replaced rather than built: an agent
ticks a checkbox reliably. What it cannot do unnoticed is omit an automatically generated
metric line, because its absence is itself the signal.

### Gate Triage

Principle: **a gate earns CI only when a breach is silent and expensive.** Loud and cheap
belongs in review; everything else is ballast that eventually gets a gate switched off — and
then all gates are negotiable.

**Build:** the analytics reproducibility gate and its whitelist (Critical Gap 3); contract-fixture
freshness (D5) — the MCP companion is a second consumer of an independently moving producer,
and the only person who would notice a field-name drift does not read code, so discovery
latency today runs until the agent is wrong in live operation. No contract broker: one
producer and one consumer in one repository do not need one, and inventing a format is
precisely why the fixtures never got built. Elixir API tests write their response bodies to a
directory; `npm test` reads those files. It lands in the same batch as the next API change.

**Bury honestly:** the exemplar-existence meta-test (documentation hygiene dressed as a gate —
a missing exemplar causes a search, not silent corruption; the path-existence test replaces it
at lower cost); the P11 assertion-style whitelist (second-order, and doubly covered by the
adversarial review); D9 as general performance testing (revived only by B3.2's rebuild budget).

**Replace Amendment 7 (right worry, wrong mechanism):** enforcement artifacts are a named file
set, and any diff touching one produces a visible, automatically generated line in the reviewer
briefing. Plus **one** CI-blocking rule: **a grandfather or allowlist may never grow, only
shrink** — overridable only by a deliberate owner decision in an ADR. That encodes the property
the repository is currently proud of, instead of hoping it holds. Pride is not a control.

### Invariant Suite Required Before the B3.2 ADR Is Signed Off

The defining property of the derived layer is an equation, and equations are tested as
invariants, not as examples.

| # | Invariant |
|---|---|
| I1 | **Rebuild equivalence** — `derived == rebuild_from_scratch(transactions)` for any ledger state. Property-based, exact `Decimal` equality, no tolerance |
| I2 | **Incremental ≡ full** — `apply_incremental(D, tx) == rebuild(transactions ++ [tx])`. Where such layers die in practice: divergence after a correcting booking, a backdated transaction, a deletion |
| I3 | **Backdating** — a transaction dated before the last materialized point invalidates everything downstream. Its own property; a generator otherwise rolls backdated inserts too rarely |
| I4 | **Freshness honesty is structural** — the read returns `{:fresh, v}` or `{:stale, v, as_of}`; no path may claim freshness without checking the version counter, and a meta-test asserts no API or MCP serialization drops the field. The agent cannot look at a warning triangle |
| I5 | **Version-counter monotonicity and non-bypassability** — every write path bumps it. Same gate type as `write_actor_test.exs` |
| I6 | **Drop-and-rebuild is a tested operation** — the test actually drops and rebuilds, against a fixture carrying historical rates. No mock |
| I7 | **The derived layer is never a write source** — no write path reads from it. Same construction as `web_repo_boundary_test.exs` |

**Four sign-off conditions:** (1) the rebuild-equivalence property is written before the layer
exists — red first; if nobody can write the equation, the semantics are undecided; (2) a named
rebuild time budget; (3) an explicit answer to what happens on a schema or formula change
deploy, since the version counter covers data and not code — a computation version in the key,
or a reasoned rejection; (4) golden masters against an independent source, because a layer whose
purpose is conserving numbers must not ratify its first implementation. Add (5) from F6: decide
the actor of a materialization write, and if it is not journaled, `write_actor_test` must know
that table class **explicitly** — implicit non-coverage is the failure case.

### Validation Issues Addressed

- **Whether the journal rollout blocks the knowledge objects** — asserted in the brief's
  addendum, **verified false** against ADR-0017's "Rollout complete" section, the empty
  grandfather list, `Journal.record/3` calls in `portfolios.ex` / `classifications.ex` /
  `ledger.ex` / `imports/applier.ex`, and shipped MCP create/update/delete tools. FX is unarmed
  **deliberately** — market-data ingestion is allowlisted, never journaled. Recorded so the claim
  is not re-derived a third time.
- **Whether a re-validation can repair this document** — it cannot on its own. Sections 1–6
  analyze a superseded corpus. The repair actually applied is the header block, the decision
  status table, and the structure warning; the rest is follow-up work named below.
- **Why both open disagreements were still open after two months** — both decisions were written
  as **artifacts rather than invariants** (a namespace, two pipelines), with no gate, no trigger
  and no deadline. In a project whose own NFR-3 says mechanical enforcement is load-bearing
  because the owner reads no code, a decision recorded only in prose is a decision not taken.
  Artifacts produce taste debates that cannot be falsified ("do we need this directory?");
  invariants produce tests that pass or fail ("can two identical calls return different
  numbers?"). **Proposed standing rule: an ADR whose acceptance criteria cannot be written as an
  initially failing test is not accepted, or must state explicitly why not — and every decision
  gate names its invariant, its gate, and its deadline.**

### Architecture Completeness Checklist (2026-08-12)

**Requirements Analysis**

- [ ] Project context thoroughly analyzed — against the 2026-06-12 corpus; the identity gate is not reflected
- [x] Scale and complexity assessed — single node, single operator, medium domain complexity: unchanged and still correct
- [ ] Technical constraints identified — see Baseline Corrections
- [ ] Cross-cutting concerns mapped — derived-layer freshness, the computation-basis mandate and knowledge-object provenance are unmapped

**Architectural Decisions**

- [ ] Critical decisions documented with versions — the document pins LiveView 0.20.x, violating its own "version truth lives in lockfiles" rule
- [ ] Technology stack fully specified — same defect
- [ ] Integration patterns defined — P7's envelope is narrower than the mandated computation basis
- [ ] Performance considerations addressed — D9's apparatus was never built; ADR-0032/0035 govern instead

**Implementation Patterns**

- [x] Naming conventions established
- [x] Structure patterns defined
- [ ] Communication patterns specified — pending the FU-6 ADR (named principals); the write-permission half is settled
- [x] Process patterns documented — P9/P10/P11 call shapes remain sound

**Project Structure**

- [ ] Complete directory structure defined — see the warning block on that section
- [x] Component boundaries established — and strengthened: `web_repo_boundary_test.exs` shipped
- [ ] Integration points mapped
- [ ] Requirements to structure mapping complete — FR-30…FR-48 unmapped

### Architecture Readiness Assessment (2026-08-12)

**Overall Status:** NOT READY — as an architecture document. **READY** as the seam contract
described in the header block, which is the role it is hereby reduced to.

This is not a verdict on the design. D1's journal, the closed-taxonomy discipline and the gate
philosophy went into the product and held. The verdict is about this document's fitness to guide
implementation of the **current** requirement set: four Critical Gaps are open and eight of
sixteen checklist items fail, including items in Requirements Analysis and Architectural
Decisions.

**Confidence Level:** High. Every claim is backed by a named ADR, a PRD line, or a verified path
in the repository; the findings were reviewed by four independent roles and stress-tested by five
elicitation passes, and the two substantive disagreements were resolved by locating a shared
premise rather than by picking a side.

**Key Strengths (what survived contact with two months of implementation):** see "What Sticks in
This Repository". In short: fail-closed mechanical enforcement was the right bet, D1 shipped as
specified including its riskiest meta-test, closed taxonomies held everywhere they were applied,
and the honest naming of unverifiable claims aged well.

**Areas for Future Enhancement:** the gate B3.2 derived-value ADR is the next architectural
decision of consequence and must argue against ADR-0035 rather than around it; knowledge objects
need one structural boundary decision before their first story; and the FU-6 ADR should write
today's write posture down as a decision and add named principals, so the journal actor stops
being a claim by the caller.

### Follow-Up Work (not done in this pass, deliberately)

| # | Item | Why it is not done here |
|---|---|---|
| FU-1 | Path-existence meta-test over every structural claim in this document | Code, needs TDD and the gates; the structure warning block is the interim measure |
| FU-2 | Negative probe per enforcement gate, plus the `n/m` count in the reviewer briefing | Code and a process change; the cheapest defence against F1 and the highest-value follow-up on this list |
| FU-3 | `gates.yaml` inventory (`id`, `status`, `test_path`, `owning_adr`) with a test that every `enforced` entry has an existing `test_path` | Defence against F2 — the failure mode that already occurred twice |
| FU-4 | Contract fixtures: Elixir API tests write response bodies, `mcp-server` tests read them | Belongs in the same batch as the next API change, per its own argument |
| FU-5 | Gate B3.2 derived-value ADR, carrying I1–I7 and the five sign-off conditions | Owner decision gate |
| FU-6 | ADR superseding D4 and OD-4: writes down today's posture as a decision (agent writes the ledger directly, one token, stated threat model) and introduces **named principals** so the journal actor is derived from the credential rather than claimed by the caller | No owner question outstanding — the identity settles it. Not done here because it is an ADR, and this diff is a validation |
| FU-7 | Knowledge-object structural decision, security events as the first falsifiable cut | Owner decision gate |

### Open Questions — all closed

| # | Question | Status |
|---|---|---|
| OQ-A1 | Is this document loaded as agent context? | **Answered from the repository: no.** Nothing in `CLAUDE.md`, `AGENTS.md` or `README.md` references it |
| OQ-A2 | Does it still have a mandate for FR-37…FR-48? | **Answered: no.** `epics.md` is the registry; the ADR chain is the decision authority |
| OQ-A3 | Is B3.2 read speed only, or must it conserve historical values? | **Answered: read speed only.** The conservation requirement is an input-capture problem and moves upstream — see Critical Gap 1 |
| OQ-A4 | May the agent create ledger transactions autonomously? | **Closed 2026-08-12 by the owner: yes, and the question should not have been asked.** It is settled by the product identity (two first-class users, the agent primary), and the capability ships today — `portfolixir.transactions.create` / `.update` / `.delete`, widened to all 13 kinds by FR-31 (#581), with the reconcile tool telling the agent to book the missing transaction. Withdrawing it would have removed the route by which transactions reach an MCP-first operator's ledger at all. See Critical Gap 4 for how the validation nearly recommended the opposite and what check would have caught it |

### Implementation Handoff (revised 2026-08-12)

**Precedence, so an implementing agent is not misled by the sections above:**

1. `AGENTS.md` and `CLAUDE.md` bind unconditionally.
2. The ADR corpus (0001–0038) is the authority on every decision it covers; where an ADR and this
   document disagree, **the ADR wins** — D1 → ADR-0017, D3 → ADR-0016, D10 → ADR-0034, caching →
   ADR-0032/0035, grouping → ADR-0018/0024, kinds → ADR-0028.
3. `epics.md` is the live requirement registry; the founding PRD wins on intent, scope boundaries
   and requirement wording.
4. This document is authoritative only for the seams listed in the header block — and only for
   those marked **enforced** or **decided, not enforced** in the Decision Status table. Anything
   marked **proposed** is not citable in review.

**First priority:** not an implementation story. FU-5 (gate B3.2) is the open decision that
changes what any subsequent architecture says; FU-2 (a negative probe per enforcement gate) is
the cheapest work with the highest protective value and needs no decision at all; FU-6 is an ADR
that records a settled posture rather than opening a question.

**A standing check this pass earned the hard way:** any recommendation that would narrow an
existing capability must cite the code or requirement it narrows, before it is written down.
This validation produced one such recommendation through a chain of individually sound
arguments and did not notice it contradicted shipped, deliberately widened behaviour. Internal
consistency is not a substitute for reading what exists.
