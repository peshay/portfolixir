# AGENTS.md

These instructions apply to all coding agents working on Portfolixir.

## Project Goal

Portfolixir is a small self-hosted Phoenix application for local portfolio
tracking. Keep the product focused on auditable local records:

1. Create securities.
2. Create portfolios.
3. Create securities accounts/depots linked to cash accounts.
4. Record manual buy and sell transactions, plus the broader Portfolio
   Performance transaction kinds (dividend, interest, deposit, removal,
   fee, tax, tax refund, cash transfer, inbound delivery, outbound
   delivery, security transfer) when needed to round-trip an imported
   bookkeeping history.
5. Calculate current holdings from transactions.
6. Store and display quote history.
7. Show a security detail chart with price history.
8. Expose supported app functions through the JSON API and MCP companion.
9. Bulk-import Portfolio Performance transaction exports (CSV/JSON v1)
   via a dedicated Imports view: drag-and-drop file intake, parse,
   preview the records that would be created (transactions, missing
   securities, missing portfolios/depots/cash accounts) with user-driven
   mapping, then apply atomically with content-hash idempotency.
10. Organise securities into classification trees: custom trees plus
    built-in asset-class and currency trees derived from security data.
11. Value multi-currency portfolios by converting positions and cash
    balances through stored exchange rates (EUR hub).
12. Store per-category target weights and report the SOLL/IST allocation
    breakdown with per-category drift.

New functionality must stay small, reviewed, locally tested, and documented.

## Hard Rules

- Follow TDD strictly.
- Write tests before implementation.
- Work only on the requested story or story batch.
- Do not add adjacent features.
- Do not silently change architecture decisions.
- Do not commit real financial data.
- Use synthetic fixtures only.
- Do not make external network calls in tests.
- Never create atoms from external input with `String.to_atom/1`.
- Use `Decimal` for money, quantities, prices, fees, taxes, and FX rates.
- Do not use floats for persisted financial values.
- Do not implement document intake (binary `.portfolio`, PP XML, broker PDFs),
  broker sync, bank sync, trading, payment, order, rebalance, or LLM behavior
  unless a reviewed story explicitly changes scope. The Portfolio Performance
  CSV/JSON v1 import flow defined in goal #9 is an in-scope exception.
- Do not add advanced reports or advanced classifications.
- Do not claim production readiness.
- Public files must be normal readable multiline files.

## Active Architecture

Use a small modular Phoenix monolith plus a thin MCP API companion:

```text
Portfolixir.Catalog      # securities and security quotes
Portfolixir.Portfolios   # portfolios, cash accounts, depots
Portfolixir.Ledger       # transactions (13 PP kinds) and holdings
PortfolixirWeb           # LiveViews, router, JSON API, components
mcp-server/              # TypeScript MCP server wrapping the JSON API only
```

Keep domain modules separate from LiveViews, controllers, and MCP wrapper code.
MCP tools must call the public JSON API; they must not bypass it by talking
directly to the database or Elixir contexts.

## API And MCP Coverage

Every new user-visible function must include API and MCP coverage, or the PR
must explicitly document why coverage is not applicable.

- JSON API endpoints belong under `/api/v1`.
- API and MCP authentication must use local bearer tokens from environment
  configuration.
- API and MCP responses must serialize financial decimals as strings.
- MCP tool schemas must expose financial decimals as strings.
- API/MCP tests must use synthetic fixtures and fake providers only.
- The MCP companion must remain installable and runnable separately from Docker
  Compose.

## Testing Expectations

Every story must include tests.

For user-visible stories, start in the test file. Add a short user story
comment, then place the functional test for that story directly below it. Use
this shape unless a narrower format already exists in the touched test file:

```elixir
# User story:
# As a local portfolio maintainer,
# I want to record a manual buy transaction,
# so that my current holdings are derived from auditable local data.
#
# Acceptance criteria:
# - The transaction is stored with Decimal quantity and price values.
# - The holdings view includes the bought quantity.
test "records a manual buy transaction and updates holdings" do
  ...
end
```

Minimum test types:

- contexts and schemas: `DataCase`;
- web routes and LiveViews: `ConnCase` with `Phoenix.LiveViewTest`;
- JSON API routes: `ConnCase`;
- MCP companion: TypeScript tests in `mcp-server/test`;
- calculations: deterministic fixtures and exact `Decimal` expectations where
  practical.

Do not make real network calls in tests.

## Required Local Checks

Run these before opening a PR:

```bash
mix format
mix test
mix coveralls
pre-commit run --all-files
npm test --prefix mcp-server
npm run build --prefix mcp-server
```

If pre-commit is not installed:

```bash
pre-commit install --install-hooks
```

For every Agent-authored branch, include this footer in the commit message so
agent identity and reasoning budget are explicit:

```text
Model: <model-name>
Thinking level: <none|minimal|low|medium|high|xhigh>
```

## Branch Naming For Agent Work

Use agent branches with provider context:

- `agent/<provider>/<topic-slug>`

Examples:

- `agent/codex/product-documentation`
- `agent/claude/design-system`
- `agent/gemini/locale-copy`
- `agent/gemma/dev-guide`
- `codex/<topic-slug>` (legacy while existing work may still use this prefix)

## Story Workflow

1. User Story documented.
2. Functional test written directly below the User Story comment.
3. Test failure confirmed for the expected reason.
4. Smallest implementation code written.
5. API coverage reviewed and updated, or explicitly marked not applicable.
6. MCP coverage reviewed and updated, or explicitly marked not applicable.
7. User documentation reviewed and updated when visible behavior changed.
8. Security audit performed.
9. Required gates run.

For AI-assisted changes, the above cycle is required to run as distinct
iterations.

## AI Authoring Contract

Agent commits must follow this order and keep each iteration reviewable:

1. Write the user story and acceptance criteria.
2. Add the user-story-backed test cases first.
3. Implement only the minimal behavior needed by the tests.
4. Review and update API and MCP coverage.
5. Update docs when user-visible behavior changes.
6. Run a security review pass and harden risks introduced by the patch.

All AI-authored commits should document model and reasoning level in the commit
footer and use PR body structure that includes evidence for each iteration step.

Read the user-visible problem, expected behavior, affected screen, route, or
surface, severity, acceptance criteria, and non-goals before editing. Keep every
change inside the story scope. Every user-visible change updates user
documentation when behavior changes.

## Scope Lock

If you discover a larger design issue, leave a follow-up note instead of solving
it opportunistically.

## Security Boundaries

- no external LLM calls from the app;
- no market-data network calls in tests;
- no stored API keys in source;
- no `.env` writing from the web UI;
- no real bank, broker, wallet, payment, order, trading, or rebalance action;
- no automatic trading or payment functionality.

## Naming

- Project: `Portfolixir`
- Repo: `portfolixir`
- OTP app: `:portfolixir`
- Root module: `Portfolixir`
- Web module: `PortfolixirWeb`
- Database names: `portfolixir_dev`, `portfolixir_test`, `portfolixir_prod`
