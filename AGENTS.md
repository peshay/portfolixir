# AGENTS.md

These instructions apply to all AI coding agents working on Portfolixir.

## Project goal

Build Portfolixir: a self-hosted Elixir/Phoenix portfolio analytics and wealth graph platform.

The initial milestone is:

- category/taxonomy management with descriptions
- security creation with symbol/currency/exchange metadata
- buy transaction history
- position calculation from transaction history
- simple quote lookup via symbol and provider candidates
- portfolio valuation in base currency

## Hard rules

- Follow TDD strictly.
- Write tests before implementation.
- Work on exactly the requested story or story batch.
- Do not add adjacent features.
- Do not silently change architecture decisions.
- Do not commit real financial data.
- Do not add real account numbers, wallet addresses, broker statements, customer names or private
  portfolio files.
- Use synthetic fixtures only.
- Do not make network calls in tests.
- Use provider behaviours and mocks for market data.
- Never create atoms from external input with `String.to_atom/1`.
- Use explicit whitelists or strings for external values.
- Use `Decimal` for money, quantities, prices and FX rates.
- Do not use floats for persisted financial values.
- Do not implement write-capable LLM/MCP tools in the MVP.
- Do not claim production readiness.

## Preferred architecture

Use a modular Phoenix monolith:

```text
Portfolixir.Catalog      # currencies, exchanges, securities
Portfolixir.Taxonomies   # taxonomies, categories, assignments
Portfolixir.Portfolios   # portfolios, accounts, base currency
Portfolixir.Ledger       # transactions, lots/effects later
Portfolixir.MarketData   # provider behaviour, symbol search, quotes
Portfolixir.Valuation    # positions and portfolio value
PortfolixirWeb           # controllers, LiveViews, components
```

Keep domain modules separate from web/controllers whenever possible.

## Testing expectations

Every story must include tests.

Minimum test types:

- contexts: unit/integration tests using `DataCase`
- API endpoints: `ConnCase`
- LiveView: `Phoenix.LiveViewTest` when UI is part of the story
- market providers: behaviours + Mox/fakes, no real HTTP in tests
- calculations: deterministic fixtures and explicit expected values

For financial calculations, tests must include exact Decimal expectations where practical.

## Coverage goal

The long-term goal is 100% meaningful coverage for domain, importer and calculation modules.
Generated Phoenix boilerplate may be excluded only if documented.

## Quality gate

Run these whenever available:

```bash
mix format
mix test
mix coveralls
mix credo --strict
mix dialyzer
mix sobelow
mix deps.audit
```

If a tool is not yet configured, do not configure unrelated tools unless the story asks for it.

## Story workflow

For each story:

1. Read the story and acceptance criteria.
2. Add or update tests first.
3. Run tests and confirm they fail for the expected reason.
4. Implement the smallest code change.
5. Run tests again.
6. Refactor only within the story scope.
7. Summarize files changed and commands run.

## Scope lock

If you discover a larger design issue, create a follow-up note instead of solving it
opportunistically.

## Security boundaries

This project handles sensitive financial data. For the MVP:

- no external LLM calls from the app
- no market-data network calls in tests
- no stored API keys in source
- no `.env` writing from the web UI
- no bank, broker or wallet signing actions
- no automatic trading/payment functionality

## Naming

- Project: `Portfolixir`
- Repo: `portfolixir`
- OTP app: `:portfolixir`
- Root module: `Portfolixir`
- Web module: `PortfolixirWeb`
- Database names: `portfolixir_dev`, `portfolixir_test`, `portfolixir_prod`
