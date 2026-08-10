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
  Display-only rebalancing hints are an in-scope exception per ADR-0023:
  computing and showing indicative corrective quantities next to the
  allocation drift is allowed, but anything that creates, stores, or
  transmits an order remains forbidden.
- Do not add advanced reports or advanced classifications.
- Do not claim production readiness.
- Public files must be normal readable multiline files.
- Write every repository artifact in English: issues, PR titles and
  descriptions, commit messages, ADRs, code comments, and documentation.
  Translated end-user documentation (the EN/DE docs site) keeps English
  as the source baseline.
- Never commit personal or private data. See "Privacy And Disclosure"
  below — it applies to every artifact, including agent-generated ones.

## Privacy And Disclosure

This is a public repository. Nothing that describes the maintainer's (or any
other real person's) private life or finances may be committed — in any
artifact: code, tests, fixtures, docs, ADRs, commit messages, issues text
mirrored into the repo, and especially agent-generated output (`_bmad-output/`
planning artifacts, design-session notes, decision logs, brainstorming
results, epics, implementation artifacts).

Forbidden in committed content:

- Real portfolio data: net worth, account balances, invested capital,
  performance/IRR figures, wealth multiples, credit lines, position
  quantities, real security positions, real transactions. Never label test
  data or examples as "the owner's real case" — synthetic data must be
  synthetic all the way down, including its description.
- Names of household members, partners, children, or pets, and any other
  family or personal details. Use generic placeholders (`Family`, `Guest`,
  "a non-owner") in examples and fixtures.
- The maintainer's personal banking relationships and private tooling:
  which banks/brokers hold their accounts, private sync scripts, credential
  or TAN setups. Naming a provider as a generic integration target
  ("a comdirect CSV export looks like …") is fine; attaching it to the
  owner's accounts is not.
- Local machine details: absolute home-directory paths, local usernames,
  hostnames, internal IPs.
- Personal configuration and agent memory: `_bmad/config.user.toml`,
  `_bmad/memory/**` (agent sanctums: `MEMORY.md`, `BOND.md`, `PERSONA.md`
  and friends), and any file whose header marks it as scoped to a person.
  These are gitignored — never force-add them.

Agent sessions (brainstorming, design sessions, PRD interviews, walkthroughs
on the live instance) routinely surface real data. Before committing any
session artifact, scrub it: replace real figures with qualitative wording
("absurdly high", "the credit line") and real names with placeholders. If a
document only works with the real numbers, it belongs on the live instance
or in a private note — not in this repo. When in doubt, leave it out.

## Active Architecture

Use a small modular Phoenix monolith plus a thin MCP API companion:

```text
Portfolixir.Catalog      # securities and security quotes
Portfolixir.Portfolios   # portfolios, cash accounts, depots
Portfolixir.Ledger       # transactions (13 PP kinds + balance snapshot) and holdings
Portfolixir.Tax          # recorded tax-statement snapshots and consistency checks
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

## Epic-Batch Workflow (ADR-0026)

Feature trees are delivered as epic batches by default; the maintainer
reviews decisions and behavior, agents review code:

1. **Decision gate:** an ADR or spec with acceptance criteria, signed off by
   the owner before the batch starts.
2. **Batch:** the feature tree is worked on ONE epic branch
   (`agent/<provider>/<epic-slug>`), one commit or small commit group per
   issue, every commit passing the local gates, the branch rebased onto
   `main` at least daily. Epic branches live days, not weeks. The Story
   Workflow above applies unchanged inside the batch.
3. **Agentic review closing act (mandatory):** multi-role adversarial review
   (at minimum correctness hunter, edge-case hunter, a UAT persona
   walkthrough on seeded synthetic data, and — for batches with user-visible
   surface — a design critic reviewing against the living design-language
   spec per ADR-0038), confirmed findings fixed on the branch, plus a
   reviewer briefing on the PR — what is new, what changed, where to look,
   deliberate trade-offs — with screenshots for UI work.
4. **Acceptance:** the owner reviews behavior against the briefing, feedback
   lands as a UAT fix round on the same branch, and the maintainer
   squash-merges. Agents never merge. No separate per-epic owner UAT
   session is assumed beyond this review (ADR-0038): day-to-day
   observations from live use reach the backlog at any time as
   unstructured owner dumps, which the PM agent triages into dated
   planning artifacts, dedups against the pipeline, and turns into thin
   issues after owner confirmation. The UX designer role owns the living
   design-language spec that design work and the design-critic review are
   held against.
5. **Bookkeeping close-out (mandatory, after the merge):** in the same pass
   as the post-merge cleanup, the batch's agent updates
   `sprint-status.yaml` and the epics document (including the FR Coverage
   Map), closes the story issues and the epic tracker, records a short
   retrospective section, confirms the merge's own CI runs — required
   checks included — are green, and **creates and pushes an annotated
   `vX.Y.Z` tag on the merge commit** (minor bump per sprint, patch
   reserved for hotfixes). The tag push triggers the Release workflow,
   which creates the GitHub Release with generated notes — the release is
   a rollback point for self-hosted instances plus a communicable
   changelog, never an installable artifact (issue #659, added
   2026-08-10). The batch ends at the merge; the epic ends here. (Added
   2026-07-31 from the combined E17–E19 retrospective: all observed
   process failures of that period sat in the unowned space after the
   merge.)

**Risk-tier work rides the batch (ADR-0036, 2026-08-04).** Ledger/money-domain
math and invariants, security-relevant changes, dependency updates, and
anything touching import idempotency or projection semantics ship inside the
epic batch like everything else — the former "dedicated small PR with real
human review" exception is withdrawn, because with one reviewer it produced a
queue of unread micro-PRs rather than review. "Risk-tier" is now an attention
label, and marking a change so means:

1. its own commit or commit group, never mixed into an unrelated commit, so it
   stays independently readable and revertable;
2. a dedicated verification pass in the agentic review on the invariant at
   stake (the money identity, the idempotency property, the projection
   semantics), findings verified before they are surfaced;
3. an explicit callout in the reviewer briefing — what changed, which
   invariant protects it, which test pins it;
4. the decision gate unchanged: semantics-changing risk-tier work still needs
   its ADR signed off before the batch starts.

The compensating controls are therefore blocking, not aspirational: TDD first
with exact `Decimal` expectations on money code, and every quality gate green.
Weakening a quality gate to make a batch pass is a review reject.

## Issue Tracking Convention

GitHub issues are thin pointers: the authoritative spec lives in the
ADR/epics document, never in the issue body. An issue carries a title, a
one-paragraph scope statement, links to the authoritative sections, and its
dependencies. Do not duplicate acceptance-criteria text into an issue —
copies drift, and the ADR/epics source is what reviewers hold the work
against.

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
