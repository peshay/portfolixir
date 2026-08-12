# AGENTS.md

These instructions apply to all coding agents working on Portfolixir.

## Project Goal

Portfolixir is a self-hosted portfolio system with **two first-class users: the
operator, and the LLM agent the operator runs.** Everything it knows is
reachable through the local JSON API and the MCP companion, and everything it
knows is also visible on a screen. One dataset, one instance, one operator — no
cloud, no tenancy, no broker. (Identity decided 2026-08-12 by the product brief
of that date, accepted as #663; the PRD's sections 1, 2 and 4 carry the full
statement.)

Keep the product focused on auditable local records:

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
- Analytics scope follows the **scope ladder** (identity gate B3.1,
  2026-08-12), which replaces the former blanket rule "do not add advanced
  reports or advanced classifications":
  - **(a) derived metrics** per security and per view — moving averages,
    volatility, drawdown, momentum, distance to extremes: **allowed**;
  - **(b) comparison and decomposition** — benchmark, contribution analysis,
    factor/sector/region exposure: **allowed**;
  - **(c) evaluation of decisions** — prediction calibration, rule evaluation,
    signal quality: **allowed**;
  - **(d) backtesting rules against stored price history: forbidden**, behind
    its own decision gate.
  Every metric in (a)–(c) must state its **computation basis** in its API and
  MCP payload: input series, window, reference series or benchmark where one
  exists, and the treatment of gaps. A metric whose basis is unstated cannot be
  reviewed — this is a review-blocking standard, not a documentation task.
  Advanced *classifications* remain out of scope; the ladder covers analytics
  only. **Boundary between the two, because level (b) brushes against it:**
  exposure decomposition may *report* a factor, sector or region breakdown from
  data the catalog already holds; it may not introduce stored partial-weight
  assignments of one security to several categories, which is what
  `CONTRIBUTING.md` defines as an advanced classification. A decomposition that
  can only be computed by adding such weights needs its own decision.
- Still gated, each behind its own decision gate and none of them openable by
  citing the ladder: **rule backtesting** (level (d)); **data acquisition
  beyond quotes and FX** (B3.3 — sources, failure behavior, retention,
  collector health); **push delivery to external endpoints** (B3.7 — request
  forgery surface, stored secrets, retry semantics); and **a local model**
  beyond the already-gated ADR-0021 PDF-intake path (B3.8).
- The permanent non-goals are identity, not backlog, and no capacity argument
  reopens them: no **order-placing** broker connection, no order creation or
  transmission, no automated trading or payment, no advice, no raw news
  archive, no external LLM calls from the app. The system prepares decisions;
  the operator executes them. **Two precisions, both narrowing ambiguity rather
  than permitting anything new:** (1) the ban is on a connection that can
  *act* — place, modify or transmit an order, or move money; **read-only** data
  acquisition from a broker or bank stays permitted in principle and gated in
  practice (Phase 3, which this document still forbids until its ADR and
  amendment land). (2) "No advice" does not retract ADR-0023's display-only
  rebalancing hints: showing an indicative corrective quantity beside a drift
  figure is arithmetic; advice is telling someone what to do with their money.
- **Machine-extracted data is a proposal until confirmed.** Anything extracted
  from an unstructured source carries its source link and a `machine_generated`
  marker, and lands only after a human or an agent confirms it — the same
  preview-then-apply shape the Portfolio Performance import uses. This holds
  independently of whether a local model is ever adopted.
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

Coverage runs **both ways** (amended 2026-08-12, identity gate B3.1). Either
direction may lead; neither may be silently skipped.

- Every new **user-visible** function must include API and MCP coverage, or the
  PR must explicitly document why coverage is not applicable.
- Every new **agent-visible** capability may ship over API and MCP alone, with
  no human view, provided the PR states why. The human view then lands in the
  **same or the next epic batch**, and its absence after that is a close-out
  finding. The deadline is the whole point: without it the rule degrades into
  "agent only, forever", which hollows out the operator half of the two-user
  identity in the Project Goal.

Rules that hold in both directions:

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

**Open the pull request as soon as the branch exists** (owner rule,
2026-08-12) — with the first commit, not when the work is finished. A branch
without a PR is invisible: the owner has to go looking for it, and CI does not
run on it. The benefit is the same for planning artifacts and for code: the
owner reads a diff instead of hunting a branch, and CI feedback arrives while
the work can still absorb it cheaply.

**Open it as a draft, and promote it yourself when it earns promotion** (owner
rule, 2026-08-12). A draft says "this is not asking for your time yet", which
is exactly true while the agent is still working — but a draft nobody ever
promotes is the same invisibility the rule above removes, just one step later.
The agent that opened the PR marks it ready for review when **all four** of
these hold:

1. the agentic review closing act has run and every confirmed finding is fixed
   on the branch;
2. CI is green on the head commit, including the required checks;
3. every question put to the owner has been answered — see the distinction
   below;
4. the branch is up to date with `main`, free of conflicts, and the agent
   judges the work mergeable as it stands.

**Not every open question blocks promotion, and conflating the two would keep
every PR in draft forever.** A question *put to the owner and unanswered*
blocks: the diff cannot be judged without it. A question the work *deliberately
records* — an `OQ-n` in the PRD, a `[NOTE FOR PM]`, a follow-up the reviewer
briefing names — does not block; it is part of the deliverable, and holding the
PR hostage to it would mean never shipping a document that is honest about what
it does not know.

Two limits. **Ready for review is not a merge request** — only the maintainer
merges, and promotion changes nothing about that. And **do not flip the status
back and forth**: if CI goes red or a review lands after promotion, fix it on
the branch and leave the PR ready. Return it to draft only if the work turns
out to need a decision the owner has not yet taken, and say on the PR why.

**The agent that opens a pull request owns it until it is merged or closed**
(owner rule, 2026-08-12). Opening a PR and walking away puts the work back on
the owner, which is the cost this whole section exists to remove. Ownership
means three standing duties:

1. **Watch it.** Subscribe to the PR's activity as soon as it exists, so CI
   results, review comments and mergeability changes arrive without anyone
   asking. Never poll by sleeping or by re-checking on a timer — wait for the
   events.
2. **Drive CI to green.** Every failing check gets diagnosed and fixed on the
   branch, round after round, until the checks pass — not one attempt, and not
   a summary of what someone else could do. Push the fix; the diff is the
   report. Reply on the PR only when a round resolves the failure, hits a real
   blocker, or raises a question the owner must answer.
3. **Resolve conflicts and stale bases.** A merge conflict or a base branch
   that moved is the PR owner's work: merge or rebase, resolve, re-run the
   gates locally, push. Ask only when both sides changed the same logic and
   picking one would lose behavior.

Four limits make this safe, and none of them is optional:

- **Never weaken a quality gate to make CI pass.** Lowering a threshold,
  adding an ignore, deleting or skipping a test, or baselining a new finding to
  get green is a review reject, not a fix — the same rule the epic-batch
  section states, restated here because a red check at midnight is exactly when
  it is tempting.
- **Never fix outside the PR's scope.** If the failure is real but belongs to
  another story, say so on the PR and leave it. Scope Lock applies to
  firefighting too.
- **Never merge.** Only the maintainer merges. Getting to green is the duty;
  merging is not.
- **A failure that reproduces on the base branch is not silently yours** — say
  so once on the PR, and act on it when the base recovers. That is the one
  legitimate "not mine" outcome, and it is still not silence.

Stop the moment the owner says stop.

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

The nine steps above are the canonical order. `workflow_docs_test.exs` asserts
each step string against the **concatenation** of this file, `README.md`,
`CONTRIBUTING.md` and `docs/development/story-workflow.md`, so one document
carrying a step satisfies the test for all of them — renumbering here would
pass CI while silently disagreeing with `docs/development/story-workflow.md`.
Treat the numbering as shared state and change it in every document that
carries it, or in none. Two clarifications ride the existing steps rather than
adding a tenth:

- **Steps 5 and 6 run in both directions** per "API And MCP Coverage": a
  user-visible function needs API/MCP coverage, and an agent-visible capability
  needs its human view in the same or the next batch.
- **A story that adds or changes a metric** must state that metric's
  **computation basis** in the API and MCP payload (series, window, reference,
  gap treatment) before step 9 passes. Review-blocking; a code comment or a
  documentation page does not satisfy it, because the payload is where the
  reviewer and the agent both read it.

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

   **Maintenance lane (owner decision 2026-08-12, issue #675).** Every batch
   carries a lane that reviews available updates for Hex, npm, Elixir/OTP,
   PostgreSQL, BMAD and the external BMAD modules, applies what passes the
   gates, and **reports what it deliberately did not update, with the
   reason**. It attaches here, to the close-out. It is a step in this
   document rather than a scheduling habit, because habits depend on someone
   remembering. The lane *reviews and decides* inside the batch; an update
   itself still lands as its own commit or commit group, never mixed into a
   feature story. Read that together with ADR-0036 below rather than against
   it: ADR-0036 withdrew the separate-PR-with-human-review ceremony for
   risk-tier work, not the requirement that a dependency bump stay
   independently readable and revertable.

   **Close-out check that the two-way coverage rule needs:** this same pass is
   where an agent-only capability from an earlier batch is checked for its
   human view. A capability whose view has not landed by the end of the next
   batch is a finding recorded here — which is what gives the deadline in "API
   And MCP Coverage" a place to be enforced instead of a place to be intended.

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
