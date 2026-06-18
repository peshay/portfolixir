# Contributing to Portfolixir

Keep changes small, tested first, and aligned with the local portfolio tracking
workflow.

All repository artifacts — issues, pull requests, commit messages, ADRs, code
comments, and documentation — are written in English. Translated end-user
documentation keeps English as the source baseline.

## Active Scope

Portfolixir currently focuses on:

- securities;
- portfolios;
- cash accounts;
- securities accounts linked to cash accounts;
- manual buy and sell transactions, plus the broader Portfolio Performance
  transaction kinds needed to round-trip an imported history;
- derived holdings, including moving-average cost basis and unrealized P&L;
- stored quote history;
- security detail price chart;
- classification trees (custom, plus built-in asset-class and currency trees);
- per-category target weights and SOLL/IST allocation with drift;
- multi-currency valuation through stored exchange rates;
- Portfolio Performance CSV/JSON v1 transaction import (preview, then apply);
- JSON API access for supported app functions;
- MCP companion tools that wrap the JSON API.

Out of scope unless a reviewed story explicitly changes it:

- document intake other than the Portfolio Performance CSV/JSON v1 export (broker
  PDFs, binary `.portfolio` workspaces, Portfolio Performance XML);
- broker sync;
- bank sync;
- trading, payment, order, or rebalance behavior;
- LLM features;
- advanced reports;
- advanced classifications (e.g. splitting one security across categories with
  partial weights).

## Local Setup

Docker workflow:

```bash
docker compose up --build
```

The Compose setup starts PostgreSQL, the Phoenix app, and the MCP companion.
Set local bearer tokens through `.env` or the shell:

```bash
PORTFOLIXIR_API_TOKEN=replace-me
PORTFOLIXIR_MCP_TOKEN=replace-me-too
```

Reset local Docker volumes when you need a clean database:

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

MCP companion workflow:

```bash
npm install --prefix mcp-server
npm run build --prefix mcp-server
PORTFOLIXIR_API_BASE_URL=http://127.0.0.1:4000 \
PORTFOLIXIR_API_TOKEN=replace-me \
npm start --prefix mcp-server
```

## Development Workflow

Each user-visible story must move in this order:

1. User Story documented.
2. Functional test written directly below the User Story comment.
3. Test failure confirmed for the expected reason.
4. Smallest implementation code written.
5. API coverage reviewed and updated, or explicitly marked not applicable.
6. MCP coverage reviewed and updated, or explicitly marked not applicable.
7. User documentation reviewed and updated when visible behavior changed.
8. Security audit performed.
9. Required gates run.

Open a PR with a short summary, story-comment evidence, test-first evidence,
API/MCP coverage notes, documentation review note, security audit note, coverage
evidence, and commands run.

## Commit Authorship And Accountability

Every commit is attributed to an accountable human under their own Git identity,
even when an LLM or coding agent produced the change. The agent is a tool; a
person owns the result and takes responsibility for it.

- Configure `git config user.name` / `user.email` to your own GitHub-verified
  identity (for example your `name@users.noreply.github.com` address).
- Do not commit under a bot/agent identity, and do not add `Co-authored-by:`
  lines, or `Model:` / `Thinking level:` / `Claude-Session:` /
  `claude.ai/code/session` footers that credit an AI agent. Record the model and
  reasoning level in the PR description if useful.
- Accountable identities are listed in
  [.github/commit-authorship-allowlist.txt](.github/commit-authorship-allowlist.txt);
  add a contributor by appending their GitHub-verified email.

A `commit-msg` hook (`scripts/check-commit-authorship.sh`) and the "Commit
authorship" CI workflow enforce this. CI re-checks every commit, so the rule
holds even if local hooks are skipped with `--no-verify`.

Use short, scoped branch names. Agent-assisted work may still use a provider
hint, but the commits themselves are authored by the human:

- `agent/<provider>/<topic-slug>`
- `fix/<topic-slug>`, `chore/<topic-slug>`

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

Use `ConnCase` and `Phoenix.LiveViewTest` for visible workflows. Use `ConnCase`
for JSON API routes. Use `DataCase` for schema and context behavior. Use
TypeScript tests in `mcp-server/test` for MCP tools. The first test for a story
should fail before implementation begins.

## API And MCP Coverage

Every new user-visible function must include JSON API and MCP companion coverage,
or the PR must explain why coverage is not applicable.

- API routes live under `/api/v1`.
- MCP tools live in `mcp-server/` and wrap the API only.
- Financial values are represented as strings in API and MCP payloads.
- API and MCP auth use local bearer tokens from environment configuration.

## User Documentation

User documentation moves with user-visible behavior. For each story:

- check [README.md](README.md) and any future user-facing docs for consistency;
- update docs when routes, workflows, labels, setup, API/MCP usage, or visible
  behavior change;
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
npm test --prefix mcp-server
npm run build --prefix mcp-server
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
agent/codex/api-mcp-wrapper
fix/security-quote-validation
chore/pre-commit
```

## PR Checklist

- [ ] The user story is written as a comment in the relevant test file.
- [ ] The functional test sits directly below the user story comment.
- [ ] Tests were written before implementation.
- [ ] The new or changed test failed for the expected reason before implementation.
- [ ] API coverage was reviewed and updated, or marked not applicable.
- [ ] MCP coverage was reviewed and updated, or marked not applicable.
- [ ] User documentation was reviewed for consistency.
- [ ] User documentation was updated, or the PR explains why no user docs changed.
- [ ] Security audit was performed.
- [ ] `mix format` was run.
- [ ] `mix test` was run.
- [ ] `mix coveralls` was run.
- [ ] `pre-commit run --all-files` was run.
- [ ] `npm test --prefix mcp-server` was run when MCP code or contracts changed.
- [ ] `npm run build --prefix mcp-server` was run when MCP code or contracts changed.
- [ ] No real financial data was added.
- [ ] No external network calls are used in tests.
- [ ] Financial values use `Decimal` where relevant.
- [ ] No external input is converted with `String.to_atom/1`.
- [ ] No import, trading, payment, order, rebalance, or LLM behavior was added.
- [ ] Scope stayed inside the story.

## Commit Style

Use conventional commits:

```text
feat(api): expose security quote history
feat(ledger): record manual trades
fix(portfolios): validate linked cash account
chore(repo): simplify pre-commit hooks
```
