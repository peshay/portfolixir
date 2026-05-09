# DOCS-002: External Prototype Evaluation

## 1) Summary

The external prototype package was supplied outside the repository and was treated as **reference
material only**.

Observed contents include a full end-to-end Phoenix app with modules for:
- Security/account/transaction ledger modeling
- PP XML import and parser/normaliser pipeline
- Market-data fetching and price persistence
- REST API + OpenAPI docs + LiveView dashboard
- Read-only MCP tooling
- Optional AI chat + LLM provider adapters
- Deployment/runtime configuration (`fly.toml`, workers, `.env`)
- Process/documentation artifacts (`wiki/`, `docs/process/`, tests, fixtures)

It is not safe to merge or copy this release directly into the current repository because
architecture, naming, and persistence structure differ from the current Portfolixir scope and the
current story requirements.

This evaluation is therefore a **design extraction pass only**.

## 2) Safety and hygiene notes

- Do not commit `db_dump.sql`.
- Do not commit `.env` files.
- Do not use real portfolio data as fixtures.
- Do not add live external market-data calls in tests.
- Do not add write-capable AI/MCP tools.
- Do not send portfolio data to LLM providers without an explicit future security review.

Additional hard constraints from the prototype that align with policy:
- Prototype already carries `.env` placeholders for API keys and a `db_dump.sql` style file is not
  to be imported.
- Prototype includes synthetic fixtures already marked “100% fictional” and should remain the model
  for fixture hygiene.
- Market-data code includes live providers and should not be copied into MVP without boundaries.

## 3) Reusable ideas

### Dashboard UX

- **External artifacts:** `lib/portfolixir_web/live/dashboard_live.ex`,
  `lib/portfolixir_web/live/dashboard_live.html.heex`, dashboard tests.
- **Useful idea:** Rich portfolio-overview structure with portfolio selector,
  as-of date filter, holdings/cash panels, recent transactions, price refresh
  action, and chart range controls.
- **Reuse approach:** Reuse interaction patterns only after core ledger and
  valuation are in place. Build new component-level UX iteratively in the
  current app style.
- **Risk:** High until the core model emits stable derived values. Copying the
  full flow would be speculative and tightly coupled.

### Ledger/accounts model

- **External artifacts:** `lib/portfolixir/ledger/*`.
- **Useful idea:** Transaction-oriented schema with separate reference account,
  securities account, security, transaction, and portfolio aggregate concepts.
- **Reuse approach:** Use the concepts as design reference for the current
  `Portfolixir.Portfolios` boundary and future ledger context. Avoid direct
  schema or module copy.
- **Risk:** Medium/High because the prototype types and schema are UUID-based
  and outside current migration history.

### Transactions model

- **External artifacts:** `lib/portfolixir/ledger/transaction.ex`,
  `lib/portfolixir/ledger.ex`.
- **Useful idea:** Clear separation of transaction effects for position and cash
  calculations, with Decimal arithmetic and explicit type sets.
- **Reuse approach:** Extract accepted business rules and migrate them to the
  current bounded contexts.
- **Risk:** Medium. Direct copy risks mismatching current model boundaries and
  module names.

### Price/market data model

- **External artifacts:** `lib/portfolixir/market_data.ex`, `price.ex`,
  `fx_rate.ex`, workers.
- **Useful idea:** Clean split for price lookup, FX lookup, background workers,
  batch queries, and latest-on-date patterns.
- **Reuse approach:** Reuse the architecture direction after defining security
  metadata and data source boundaries in the current repo.
- **Risk:** Medium. Live provider usage and float-to-decimal conversion must be
  isolated and sanitized before any MVP use.

### Portfolio Performance XML import

- **External artifacts:** `lib/portfolixir/parser/pp_xml_parser.ex`,
  `lib/portfolixir/imports/normaliser.ex`, `normalise_worker.ex`, tests, and
  fixtures.
- **Useful idea:** Parser strategy, canonical mapping, conversion scale, import
  idempotency, staged normalization, and fixture-backed expectations.
- **Reuse approach:** Treat as a spike reference only and re-implement
  incrementally inside the current codebase.
- **Risk:** Medium. Current schema assumptions diverge from the present model.

### REST API

- **External artifacts:** `lib/portfolixir_web/controllers/api/v1/*`,
  `lib/portfolixir_web/router.ex`.
- **Useful idea:** Endpoint taxonomy, deterministic JSON shapes, and auth test
  coverage patterns.
- **Reuse approach:** Define endpoints only after backend domain stories are
  complete.
- **Risk:** Medium/High because of missing context parity and ledger coupling.

### MCP/read-only tools

- **External artifacts:** `lib/portfolixir/mcp/tools.ex`,
  `lib/portfolixir_web/controllers/mcp_controller.ex`.
- **Useful idea:** Read-only framing with parameter schemas and no write
  operations in the tool layer.
- **Reuse approach:** Reuse naming and discovery after API/domain boundaries are
  stable and protected by explicit allowlists.
- **Risk:** Medium-High. Security boundaries must be finalized before tool
  exposure.

### AI chat

- **External artifacts:** `lib/portfolixir/llm_proxy.ex`,
  `lib/portfolixir_web/live/chat_live*`, adapter modules.
- **Useful idea:** Provider abstraction and streaming UX patterns.
- **Reuse approach:** Exclude from this story. Keep as future architecture
  reference only after security review and explicit story approval.
- **Risk:** High because the prototype includes provider networking, command
  execution, API keys, and optional portfolio-context injection.

### Deployment

- **External artifacts:** `fly.toml`, `Dockerfile`, `.env` template usage, and
  workflow-like defaults.
- **Useful idea:** Later hosting baseline and environment-default conventions.
- **Reuse approach:** Do not extract in this story. Record only planning notes.
- **Risk:** High for this milestone; deployment is outside the requested MVP.

### Documentation/wiki/process docs

- **External artifacts:** `wiki/*`, `docs/process/*`, `docs/product/*`.
- **Useful idea:** Story sequencing, acceptance style, vocabulary alignment, and
  synthetic fixture guidance.
- **Reuse approach:** Reuse planning format and acceptance-test mindset; do not
  port full process docs verbatim.
- **Risk:** Low. Mostly non-technical and dated to prior prototype scope.

### Tests/fixtures

- **External artifacts:** `test/fixtures/*` and test suites across modules.
- **Useful idea:** Deterministic synthetic fixtures and coverage for parser,
  import idempotency, market-data workers, API auth, and dashboard states.
- **Reuse approach:** Reuse test intent and naming conventions in the current app
  structure only.
- **Risk:** Low/Medium. Fixture structure and module names differ.

## 4) Compatibility assessment with current Portfolixir

Current Portfolixir (local repo) currently exposes:
- `lib/portfolixir/catalog/*` (security and security-category assignment)
- `lib/portfolixir/taxonomies/*` (taxonomy model)
- `lib/portfolixir/portfolios/*` (portfolio aggregate)
- No `lib/portfolixir/ledger/*`, `market_data/*`, `imports/*`, `parser/*`, or `mcp/*` yet in this
  repo snapshot.

Therefore:
- **Catalog securities**, taxonomies, and security-category assignments are already in place and
  align with the MVP scope.
- The external prototype **does** include those ideas conceptually but uses different module layout
  and a separate `ledger` boundary.
- External schema is **UUID-heavy** with ledger-centric relations and already includes
  migration/state history (`db_schema.sql`, oban tables).
- External import/parser assumes those ledger tables (`securities`, `portfolios`,
  `reference_accounts`, `securities_accounts`, `transactions`, etc.) and direct worker integration.
- **Direct schema/code copy is risky**: IDs, naming, boundaries, and feature coupling are different;
  copy would create accidental architectural drift and migration conflicts.

## 5) Recommended extraction sequence

Safe sequence for the next stories:

1. **PFX-015 Create deposit accounts**
   - Add `Portfolixir.Portfolios.DepositAccount` (or equivalent) with strict schema/validation.
   - Keep IDs and associations independent of prototype table assumptions.

2. **PFX-016 Create securities accounts**
   - Add account entity for tradable holdings and attach to portfolios.

3. **PFX-017 Link securities account to reference deposit account**
   - Define explicit account relationships and ownership links.

4. **PFX-018 Record buy transaction**
   - Add `Transaction` write path with Decimal amounts, security/share semantics, and date handling.

5. **PFX-024 Calculate security positions from transactions**
   - Implement position and cash balance derivation with deterministic fixtures.

6. **PFX-026 Manual latest quote entry**
   - Add price storage entry point before live-provider integration.

7. **Later: Dashboard inspired by external prototype**
   - Implement a reduced dashboard MVP using prototype-inspired layout and filtering patterns only
     after position and pricing are stable.

8. **Later: PP XML import parser/fixtures spike**
   - Build a parser spike against synthetic PP-like fixtures first, then integrate normalisation
     carefully.

9. **Much later: read-only API + MCP**
   - Add REST API first, MCP tools only after API and domain invariants are stable and reviewed.

## 6) Concrete next recommended story

**Preferred next story: `PFX-015 Create deposit accounts`**

Why:
- Dashboard requires real derived snapshots (positions, balances, totals).
- Market-data needs stable symbol/security metadata and domain boundaries before live provider
  integration.
- AI chat and MCP need hardened security boundaries, request validation, and a read-only policy.
- Ledger/accounts + transaction recording is the core model that everything else depends on in this
  milestone.

## 7) Quality check run

Executed:
- `git status --short`

Expected state at this point: only `docs/product/external-prototype-evaluation.md` is changed.
