# AGENTS.md

These instructions apply to all coding agents working on Portfolixir.

## Project Goal

Portfolixir is being rebooted as the smallest coherent self-hosted Phoenix
foundation for local portfolio tracking. This branch is a foundation reset, not
a finished MVP.

Build only this workflow until a story explicitly changes scope:

1. Create securities.
2. Create one portfolio.
3. Create one securities account/depot linked to one cash account.
4. Record manual buy and sell transactions.
5. Calculate current holdings from transactions.
6. Store and display quote history.
7. Show a security detail chart with price history.

Future MVP functionality must be added Epic-by-Epic with human review on
staging before production promotion.

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
- Do not implement imports, document intake, broker sync, bank sync, trading,
  payment, order, rebalance, LLM, or MCP behavior.
- Do not add advanced reports or advanced classifications.
- Do not claim production readiness.
- Public files must be normal readable multiline files.

## Active Architecture

Use a small modular Phoenix monolith:

```text
Portfolixir.Catalog      # securities and security quotes
Portfolixir.Portfolios   # portfolios, cash accounts, depots
Portfolixir.Ledger       # manual buy/sell transactions and holdings
PortfolixirWeb           # LiveViews, router, components
```

Keep domain modules separate from LiveViews and controllers.

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
- calculations: deterministic fixtures and exact `Decimal` expectations where
  practical.

Do not make real network calls in tests.

## Required Local Checks

Run these before opening a PR:

```bash
mix format
mix test
pre-commit run --all-files
```

If pre-commit is not installed:

```bash
pre-commit install --install-hooks
```

## Story Workflow

1. Read the user-visible problem, expected behavior, affected route or surface,
   acceptance criteria, and non-goals.
2. Write the user story as a comment in the relevant test file.
3. Write the functional test directly below the user story comment.
4. Run the test and confirm it fails for the expected reason.
5. Implement the smallest code change that fulfills the story and test.
6. Run the test suite again.
7. Review user documentation for consistency with the story and code.
8. Update user documentation when the story changes visible behavior. If the
   story only changes background behavior, note that user documentation was
   reviewed and no update was needed.
9. Refactor only within story scope.
10. Summarize files changed and commands run.

## Scope Lock

If you discover a larger design issue, leave a follow-up note instead of solving
it opportunistically.

## Security Boundaries

For the MVP:

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
