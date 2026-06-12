---
stepsCompleted: [1, 2, 3, 4, 5, 6]
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
workflowType: 'architecture'
project_name: 'portfolixir'
user_name: 'Andi'
date: '2026-06-12'
---

# Architecture Decision Document

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

### Decision Priority Analysis

**Critical Decisions (block implementation):**
1. D1 — Audit-journal mechanics (FR-28)
2. D2 — Pure core / imperative shell as a binding, mechanically checked rule
3. D3 — Rounding-policy sequencing and oracle provenance (#344)

**Important Decisions (shape architecture):**
4. D4 — Graduated API/MCP token scopes (fail-closed)
5. D5 — API↔MCP contract artifact (generated shared fixtures)
6. D6 — Self-describing analytics envelope (incl. refusal contract)
7. D7 — MCP tool taxonomy (thin 1:1 wrapper; consolidation API-side)
8. D8 — Charts stay server-rendered SVG
9. D9 — NFR-8 measurement apparatus + caching trigger condition
10. D10 — IRR/XIRR numeric strategy at the Decimal boundary
11. D11 — Write idempotency for the agent-facing API

**Deferred Decisions (explicit, with rationale):**
- Phase-3 credential encryption — behind the scope gate, its own ADR
- Rounding-policy *content* — its own story/ADR (#344, owner: Andi); only sequencing
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
Issue #344 (owner: Andi) is decided **before** the golden-master corpus is scaled and
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
designed against the **golden question set** — a planning artifact (owner: Andi,
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
