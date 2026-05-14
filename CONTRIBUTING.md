# Contributing to Portfolixir

Portfolixir is in a controlled foundation reset. Keep changes small, tested
first, and aligned with the manual portfolio tracking workflow.

This branch is not a finished MVP. Future MVP functionality is added through
human-reviewed Epics and local quality gates.

## MVP Scope

Active scope:

- securities;
- one portfolio;
- cash accounts;
- securities accounts linked to cash accounts;
- manual buy and sell transactions;
- derived holdings;
- stored quote history;
- security detail price chart.

Out of scope:

- PDF import;
- CSV import;
- document intake;
- broker sync;
- bank sync;
- trading, payment, order, or rebalance behavior;
- MCP or LLM features;
- advanced reports;
- advanced classifications.

## Local Setup

Docker workflow:

```bash
docker compose up --build
```

For prototype-era Docker volumes, reset before first reboot use:

```bash
docker compose down -v
docker compose up --build
```

Host workflow:

```bash
mix deps.get
mix ecto.setup
mix phx.server
```

For prototype-era host databases, run `mix ecto.reset` once before starting the
app.

## Development Workflow

Each user-visible story must move in this order:

1. User Story documented.
2. Functional test written directly below the User Story comment.
3. Test failure confirmed for the expected reason.
4. Smallest implementation code written.
5. Required gates run.
6. User documentation reviewed and updated when visible behavior changed.

Open a PR with a short summary, story-comment evidence, test-first evidence,
documentation review note, coverage evidence, and commands run.

## Story And Test Format

User-visible stories should start in the test file. Keep the story comment close
to the test that proves it:

```elixir
# User story:
# As a local portfolio maintainer,
# I want to record a manual sell transaction,
# so that my current holdings reflect the sale.
#
# Acceptance criteria:
# - The sell transaction is stored with Decimal quantity and price values.
# - The holdings calculation subtracts the sold quantity.
test "records a manual sell transaction and updates holdings" do
  ...
end
```

Use `ConnCase` and `Phoenix.LiveViewTest` for visible workflows. Use `DataCase`
for schema and context behavior. The first test for a story should fail before
implementation begins.

## User Documentation

User documentation moves with user-visible behavior. For each story:

- check [README.md](README.md) and any future user-facing docs for consistency;
- update docs when routes, workflows, labels, setup, or visible behavior change;
- leave docs unchanged for internal-only changes only after explicitly reviewing
  them.

The detailed story workflow lives in
[docs/development/story-workflow.md](docs/development/story-workflow.md).

## Required Local Checks

```bash
mix format
mix test
mix coveralls
pre-commit run --all-files
```

Install hooks once:

```bash
pre-commit install --install-hooks
```

The pre-commit setup uses standard hygiene hooks and `mix format --check-formatted`.

## Test Rules

- Use synthetic data only.
- Do not add real financial data.
- Do not make external network calls in tests.
- Use `Decimal` for financial values.
- Avoid floats for persisted financial values.
- Never use `String.to_atom/1` on external input.

## Branch Naming

Use short, scoped names:

```text
story/manual-buy-sell
fix/security-quote-validation
chore/pre-commit
```

## PR Checklist

- [ ] The user story is written as a comment in the relevant test file.
- [ ] The functional test sits directly below the user story comment.
- [ ] Tests were written before implementation.
- [ ] The new or changed test failed for the expected reason before implementation.
- [ ] User documentation was reviewed for consistency.
- [ ] User documentation was updated, or the PR explains why no user docs changed.
- [ ] `mix format` was run.
- [ ] `mix test` was run.
- [ ] `pre-commit run --all-files` was run.
- [ ] No real financial data was added.
- [ ] No external network calls are used in tests.
- [ ] Financial values use `Decimal` where relevant.
- [ ] No external input is converted with `String.to_atom/1`.
- [ ] No import, sync, trading, payment, order, rebalance, MCP, or LLM behavior
      was added.
- [ ] Scope stayed inside the story.

## Commit Style

Use conventional commits:

```text
feat(catalog): add security quote history
feat(ledger): record manual trades
fix(portfolios): validate linked cash account
chore(repo): simplify pre-commit hooks
```
