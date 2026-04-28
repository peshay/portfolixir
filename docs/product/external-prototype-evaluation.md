# DOCS-002: External Prototype Evaluation

## 1) Summary

The external prototype package was found at `/Users/ahu/Downloads/portfolixir-release.zip` and was treated as **reference material only**.

Observed contents include a full end-to-end Phoenix app with modules for:
- Security/account/transaction ledger modeling
- PP XML import and parser/normaliser pipeline
- Market-data fetching and price persistence
- REST API + OpenAPI docs + LiveView dashboard
- Read-only MCP tooling
- Optional AI chat + LLM provider adapters
- Deployment/runtime configuration (`fly.toml`, workers, `.env`)
- Process/documentation artifacts (`wiki/`, `docs/process/`, tests, fixtures)

It is not safe to merge or copy this release directly into the current repository because architecture, naming, and persistence structure differ from the current Portfolixir scope and the current story requirements.

This evaluation is therefore a **design extraction pass only**.

## 2) Safety and hygiene notes

- Do not commit `db_dump.sql`.
- Do not commit `.env` files.
- Do not use real portfolio data as fixtures.
- Do not add live external market-data calls in tests.
- Do not add write-capable AI/MCP tools.
- Do not send portfolio data to LLM providers without an explicit future security review.

Additional hard constraints from the prototype that align with policy:
- Prototype already carries `.env` placeholders for API keys and a `db_dump.sql` style file is not to be imported.
- Prototype includes synthetic fixtures already marked “100% fictional” and should remain the model for fixture hygiene.
- Market-data code includes live providers and should not be copied into MVP without boundaries.

## 3) Reusable ideas

| Area | External prototype artifact | What is useful | Reuse approach | Risk |
| --- | --- | --- | --- | --- |
| Dashboard UX | `lib/portfolixir_web/live/dashboard_live.ex`, `lib/portfolixir_web/live/dashboard_live.html.heex`, dashboard tests | Rich portfolio-overview structure: portfolio selector, as-of date filter, holdings/cash panels, recent transactions, price refresh action, chart range controls. | Reuse interaction patterns only (component organization, tests style, data-refresh flow) after core ledger and valuation are in place. Implement new component-level UX iteratively in our style. | High until core model emits stable derived values; current app has no ledger foundation yet, so copy of full flow would be speculative and tightly coupled. |
| Ledger/accounts model | `lib/portfolixir/ledger/*` | Transaction-oriented schema with separate `ReferenceAccount`, `SecuritiesAccount`, `Security`, `Transaction`, and portfolio aggregate. Includes typed buy/sell/fee/tax/deposit semantics. | Reuse concepts (accounts + transaction types + moving-average cost logic) as a design reference for our own `Portfolixir.Portfolios` + upcoming ledger context. Avoid direct schema/module copy. | Medium/High because types and schema are UUID-based and currently outside current modular context and migration history. |
| Transactions model | `lib/portfolixir/ledger/transaction.ex`, `lib/portfolixir/ledger.ex` | Clear separation of transaction effects for position and cash calculations. Good domain intent and Decimal arithmetic with explicit type sets. | Extract accepted business rules (date cutoffs, signed effects, security/account-specific validation, Decimal usage) and migrate to our bounded contexts. | Medium. Direct copy risks mismatching current model boundaries and module names. |
| Price/market data model | `lib/portfolixir/market_data.ex`, `price.ex`, `fx_rate.ex`, workers | Clean split for price lookup (`price_on`), FX lookup, and background workers. Useful batch-query and latest-on-date patterns for dashboards/performance. | Reuse architecture direction (single source of prices + FX rates + idempotent upserts + worker scheduling) after defining security metadata and data source boundaries in current repo. | Medium. Includes live Yahoo/Frankfurter usage and decimals from JSON conversion (`Decimal.from_float`) that should be isolated/sanitized in tests and MVP. |
| Portfolio Performance XML import | `lib/portfolixir/parser/pp_xml_parser.ex`, `lib/portfolixir/imports/normaliser.ex`, `normalise_worker.ex`, tests/fixtures | Strongest reusable area. Parser handles reference stubs, canonical mapping, conversion scale, import idempotency, staged normalisation, and fixture-backed expectations. | Reuse as a “spike reference” only: PP import parser strategy, fixture policy, idempotency checks, and worker orchestration. Re-implement incrementally inside current codebase. | Medium. Uses current schema assumptions that diverge from our present model; full copy would require large rewrite. |
| REST API | `lib/portfolixir_web/controllers/api/v1/*`, `lib/portfolixir_web/router.ex` | Endpoints for portfolios, balances, positions, performance, import lifecycle, holdings/transactions exports, and bearer-auth wrapper. Good API-coverage pattern. | Reuse endpoint taxonomy and tests structure (conn tests + 401 checks + deterministic JSON shape). Define new endpoints only after backend domain stories are complete. | Medium/High due to missing context parity and coupling to ledger module. |
| MCP/read-only tools | `lib/portfolixir/mcp/tools.ex`, `lib/portfolixir_web/controllers/mcp_controller.ex` | Clean read-only framing (`tools/list`, `tools/call`) with parameter schemas and no write operations in tool layer. | Reuse naming/discovery model once API/domain are stable. Keep first implementation behind clear security policy, with explicit allowlist and audit checks. | Medium-High. Current story priority puts this after ledger/API, and security boundaries must be finalized before adding tool exposure. |
| AI chat | `lib/portfolixir/llm_proxy.ex`, `lib/portfolixir_web/live/chat_live*`, adapter set in `lib/portfolixir/llm_proxy/adapters/*` | Useful for showing prompt/streaming UX patterns and provider abstraction (adapter concept). | Explicitly excluded for this story. Use only as a future architecture reference and postpone until security review plus explicit story approval. | High. Prototype includes direct provider networking, CLI command execution, API keys, and optional context injection of portfolio state. |
| Deployment | `fly.toml`, `Dockerfile`, `.env` template usage, workflow-like defaults | Useful for later hosting baseline and environment defaults. | Do not extract in this story. Record only conventions (build pipeline, cron workers if needed) as a planning note. | High for this milestone; conflicts with explicit MVP constraints (no Fly.io deployment requested). |
| Documentation/wiki/process docs | `wiki/*`, `docs/process/*`, `docs/product/*` | Valuable for story sequencing, acceptance style, and vocabulary alignment. Synthetic fixture guidance is especially reusable. | Reuse planning format and acceptance-test mindset; do not port full process docs verbatim. | Low. Mostly non-technical and mostly dated to prior prototype scope. |
| Tests/fixtures | `test/fixtures/*`, test suites across modules | Good quality signal: deterministic synthetic fixtures, coverage for parser, import idempotency, market-data worker behavior, API auth, dashboard states. | Reuse test intent and naming conventions, especially for parser/import and data-availability edge cases. Write new tests in current app structure only. | Low/Medium. Fixture structure and module names differ; test setup will need adaptation. |

## 4) Compatibility assessment with current Portfolixir

Current Portfolixir (local repo) currently exposes:
- `lib/portfolixir/catalog/*` (security and security-category assignment)
- `lib/portfolixir/taxonomies/*` (taxonomy model)
- `lib/portfolixir/portfolios/*` (portfolio aggregate)
- No `lib/portfolixir/ledger/*`, `market_data/*`, `imports/*`, `parser/*`, or `mcp/*` yet in this repo snapshot.

Therefore:
- **Catalog securities**, taxonomies, and security-category assignments are already in place and align with the MVP scope.
- The external prototype **does** include those ideas conceptually but uses different module layout and a separate `ledger` boundary.
- External schema is **UUID-heavy** with ledger-centric relations and already includes migration/state history (`db_schema.sql`, oban tables).
- External import/parser assumes those ledger tables (`securities`, `portfolios`, `reference_accounts`, `securities_accounts`, `transactions`, etc.) and direct worker integration.
- **Direct schema/code copy is risky**: IDs, naming, boundaries, and feature coupling are different; copy would create accidental architectural drift and migration conflicts.

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
   - Implement a reduced dashboard MVP using prototype-inspired layout and filtering patterns only after position and pricing are stable.

8. **Later: PP XML import parser/fixtures spike**
   - Build a parser spike against synthetic PP-like fixtures first, then integrate normalisation carefully.

9. **Much later: read-only API + MCP**
   - Add REST API first, MCP tools only after API and domain invariants are stable and reviewed.

## 6) Concrete next recommended story

**Preferred next story: `PFX-015 Create deposit accounts`**

Why:
- Dashboard requires real derived snapshots (positions, balances, totals).
- Market-data needs stable symbol/security metadata and domain boundaries before live provider integration.
- AI chat and MCP need hardened security boundaries, request validation, and a read-only policy.
- Ledger/accounts + transaction recording is the core model that everything else depends on in this milestone.

## 7) Quality check run

Executed:
- `git status --short`

Expected state at this point: only `docs/product/external-prototype-evaluation.md` is changed.
