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
12. Store per-category target weights and report the target/actual allocation
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
- Do not implement document intake (binary `.portfolio`, PP XML),
  broker sync, bank sync, trading, payment, order, rebalance, or LLM behavior
  unless a reviewed story explicitly changes scope. The Portfolio Performance
  CSV/JSON v1 import flow defined in goal #9 is an in-scope exception.
  Broker-PDF transaction intake is also an in-scope exception per ADR-0021,
  constrained to a sandboxed, text-extraction-only, per-broker, preview-then-
  confirm importer (binary `.portfolio` intake stays out of scope).
- Do not add advanced reports or advanced classifications.
- Do not claim production readiness.
- Public files must be normal readable multiline files.
- Write every repository artifact in English: issues, PR titles and
  descriptions, commit messages, ADRs, code comments, and documentation.
  Translated end-user documentation (the EN/DE docs site) keeps English
  as the source baseline.

## Active Architecture

Use a small modular Phoenix monolith plus a thin MCP API companion:

```text
Portfolixir.Catalog      # securities and security quotes
Portfolixir.Portfolios   # portfolios, cash accounts, depots
Portfolixir.Ledger       # transactions (13 PP kinds + balance snapshot) and holdings
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

Commit under the accountable human's own Git identity (their GitHub account).
An LLM or coding agent commits AS that person; it must not introduce a bot
author/committer, a `Co-authored-by:` line that credits itself, or `Model:` /
`Thinking level:` / `Claude-Session:` footers. Record the model and reasoning
level in the pull request description instead, where they do not become part of
the permanent commit authorship record. See "Commit Authorship And
Accountability" below.

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

All AI-assisted commits are authored under the accountable human's own Git
identity (see "Commit Authorship And Accountability"). Document the model and
reasoning level in the PR description, not in the commit, and use a PR body
structure that includes evidence for each iteration step.

Read the user-visible problem, expected behavior, affected screen, route, or
surface, severity, acceptance criteria, and non-goals before editing. Keep every
change inside the story scope. Every user-visible change updates user
documentation when behavior changes.

## Commit Authorship And Accountability

Every commit must be attributable to an accountable human. An LLM or coding
agent is a tool: it drafts changes, but a person owns the result and commits
under their own Git identity (the name and email of their GitHub account).

- Configure Git so `user.name` and `user.email` resolve to the human running
  the agent. Prefer a GitHub-verified address, e.g. the
  `name@users.noreply.github.com` address GitHub provides.
- Never commit under a bot/agent identity (for example `Claude`, `Codex`,
  `OpenClaw`, or generic `agent@…` addresses).
- Never add a `Co-authored-by:` trailer that credits an AI agent, and never add
  `Model:`, `Thinking level:`, `Claude-Session:`, or `claude.ai/code/session`
  footers. Record model and reasoning level in the PR description if useful.
- Accountable identities live in `.github/commit-authorship-allowlist.txt`. Add
  a teammate by appending their GitHub-verified email.

Enforcement (do not work around it):

- Local: a `commit-msg` hook (`scripts/check-commit-authorship.sh`, wired through
  `.pre-commit-config.yaml`) rejects non-human authors and AI-identity trailers.
- CI: the "Commit authorship" workflow re-checks every commit in a push or pull
  request, so the rule holds even when local hooks are bypassed.

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
