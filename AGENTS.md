# AGENTS.md

These instructions apply to all AI coding agents working on Portfolixir.

## Project goal

Build Portfolixir: a self-hosted Elixir/Phoenix portfolio analytics and wealth graph platform
for local, auditable portfolio modelling.

The current MVP path is intentionally narrow. Build in this order unless a story says otherwise:

1. securities workbench and security master data;
2. portfolio, depot/securities account, and linked cash-account setup;
3. manual buy/sell transaction entry with deterministic Decimal calculations;
4. quote history, valuations, and charts over stored data.

Import, document, broker, bank, payment, trading, order, rebalance, and production-readiness work
is deferred unless a story explicitly scopes a safe, read-only or mocked slice.

## Hard rules

- Follow TDD strictly.
- Write tests before implementation.
- Work on exactly the requested story or story batch.
- Do not add adjacent features.
- Do not silently change architecture decisions.
- Do not commit real financial data.
- Do not add real account numbers, wallet addresses, broker statements, personal names, or private
  portfolio files.
- Use synthetic fixtures only.
- Do not make external network calls in tests.
- Use provider behaviours, fakes, or mocks for market data.
- Never create atoms from external input with `String.to_atom/1`.
- Use explicit whitelists or strings for external values.
- Use `Decimal` for money, quantities, prices, and FX rates.
- Do not use floats for persisted financial values.
- Do not implement write-capable LLM/MCP tools in the MVP.
- Do not add broker, banking, trading, payment, order, or rebalance actions.
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

- contexts: unit/integration tests using `DataCase`;
- API endpoints: `ConnCase`;
- LiveView: `Phoenix.LiveViewTest` when UI is part of the story;
- market providers: behaviours plus fakes or Mox-style mocks, no real HTTP in tests;
- calculations: deterministic fixtures and explicit expected values.

For financial calculations, tests must include exact `Decimal` expectations where practical.

## Required local quality gate

Run the required local checks before opening a PR:

```bash
mix format
mix test
pre-commit run --all-files
```

If pre-commit is not installed yet, either install it with `pre-commit install --install-hooks`
or run the repository public-artifact guard directly through the documented replacement command
in `CONTRIBUTING.md`.

## Optional heavy checks

These checks are useful when the story touches riskier areas, but they are optional unless a story
or PR reviewer asks for them:

```bash
mix coveralls
mix credo --strict
mix dialyzer
mix sobelow
mix deps.audit
```

If a tool is not configured, do not configure it unless the story asks for that work.

## Story workflow

For each story:

1. Read the user-visible problem, expected behavior, affected route or surface, severity,
   acceptance criteria, and non-goals.
2. Add or update tests first.
3. Run tests and confirm they fail for the expected reason.
4. Implement the smallest code change.
5. Run tests again.
6. Refactor only within the story scope.
7. Summarize files changed and commands run.

## Scope lock

If you discover a larger design issue, create a follow-up note instead of solving it opportunistically.

## Security boundaries

This project handles sensitive financial data. For the MVP:

- no external LLM calls from the app;
- no market-data network calls in tests;
- no stored API keys in source;
- no `.env` writing from the web UI;
- no real bank, broker, wallet, payment, order, trading, or rebalance action;
- no automatic trading/payment functionality.

## Naming

- Project: `Portfolixir`
- Repo: `portfolixir`
- OTP app: `:portfolixir`
- Root module: `Portfolixir`
- Web module: `PortfolixirWeb`
- Database names: `portfolixir_dev`, `portfolixir_test`, `portfolixir_prod`
