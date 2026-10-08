# AGENTS.md

The rules for every coding agent working on Portfolixir, and their single
source of truth. Claude Code, Codex, Copilot, Cursor and Gemini CLI read it
directly. **Do not add a `CLAUDE.md` or `CLAUDE.local.md`** (`/init` creates
one). *Why:* Claude Code reads `AGENTS.md` only while neither exists in the
working directory or above it, and a second file is a second copy to drift
(Claude Code docs, "How Claude remembers your project" → AGENTS.md).

**Every rule carries its reason** (*Why*) and its source. Justify an action by
the reason, not by the rule. When a reason no longer holds, propose changing
the rule in a PR with the new reason; do not follow it blindly or quietly
ignore it. A new rule lands only with its reason; *(inferred)* marks a reason
not yet recorded. *Why:* a rule whose reason is known can be questioned and
waived correctly, and a model follows an instruction better when it knows the
goal (ADR-0026, amendment of 2026-10-08).

**This file stays short; procedures are read when they apply.** *Why:* it loads
into every session, long instruction files are followed less well, and Codex
reads only the first 32 KiB, which once cut off the security and authorship
sections. Procedures: [sprint workflow](docs/development/sprint-workflow.md)
(planning, the sprint PR, closing act, close-out, owning a PR, UI boards, risk
tier, issues) and [story workflow](docs/development/story-workflow.md) (the
nine test-first steps); also the [development
guide](docs/development/guide.md), [CONTRIBUTING.md](CONTRIBUTING.md) and
[SECURITY.md](SECURITY.md).

**Sources:** `ADR-NNNN` is `docs/decisions/NNNN-*.md`; "brief" and "addendum"
are `_bmad-output/planning-artifacts/briefs/brief-portfolixir-2026-08-12/`;
"PRD" is
`_bmad-output/planning-artifacts/prds/prd-portfolixir-2026-06-12/prd.md`;
plans, retrospectives and the close-out log (`sprint-status.yaml`) are in
`_bmad-output/implementation-artifacts/`; the requirement registry is
`_bmad-output/planning-artifacts/epics.md`.

## What Portfolixir is

A self-hosted portfolio system with **two first-class users: the operator, and
the LLM agent the operator runs.** Everything it knows is reachable through the
local JSON API and the MCP companion, and visible on a screen. One dataset, one
instance, one operator: no cloud, no tenancy, no broker. *Why:* figures kept
next to the system drifted within days, and the agent recomputed what the
server could have handed over (product brief 2026-08-12; PRD §1–2).

Its scope is auditable local records: securities, portfolios, depots linked to
cash accounts, the Portfolio Performance transaction kinds and their import,
holdings derived from transactions, quotes and charts, classification trees,
multi-currency valuation through stored EUR-hub rates, target weights with
drift, and a per-security research log that is never rewritten (ADR-0044).
Stories and commits stay small; a sprint PR is large and briefed. *Why:* the
figures can be trusted only because they reproduce from the ledger (ADR-0004);
verification, not code, is the bottleneck (ADR-0026).

## Hard Rules

- **Test first.** Write the test, see it fail for the expected reason, then
  write the smallest code that passes, as the [story
  workflow](docs/development/story-workflow.md) orders it. *Why:* the owner
  does not read code, so a test that failed first stands in for that read (PRD
  §1 "Stakes and quality bar"; ADR-0036).
- **Stay in scope.** Work only on the requested story or sprint and add no
  adjacent feature. A larger design issue or a new idea found on the way is
  filed: file a new issue immediately rather than solving it opportunistically.
  *Why:* every change stays reviewable against a decision, and a session's
  memory ends with it while an issue does not (ADR-0022, Context; E17–E19
  retrospective §5).
- **Do not silently change architecture decisions**; amend the ADR. *Why:* the
  owner reviews decisions, not diffs, so a decision changed in code is changed
  unreviewed (ADR-0026 step 1).
- **Use `Decimal` for money, quantities, prices, fees, taxes and FX rates;
  never persist a float.** *Why:* binary floats cannot represent decimal
  amounts, and the drift is unacceptable in auditable records (ADR-0003).
- **Make no external network call in a test; use synthetic fixtures and fake
  providers.** *Why (inferred):* tests stay deterministic and offline, and no
  token or data leaves the machine (ADR-0005, Consequences).
- **Never create atoms from external input with `String.to_atom/1`.** *Why
  (inferred):* atoms are never garbage-collected, so input-made atoms can fill
  the atom table and stop the VM (Sobelow flags it).
- Do not implement document intake (binary `.portfolio`, PP XML), broker sync,
  bank sync, trading, payment, order, rebalance, or LLM behavior unless a
  reviewed story explicitly changes scope. The Portfolio Performance CSV/JSON
  v1 import flow is an in-scope exception. Broker-PDF transaction intake is
  also an in-scope exception per ADR-0021, constrained to a sandboxed,
  text-extraction-only, per-broker, preview-then-confirm importer (binary
  `.portfolio` intake stays out of scope). Display-only rebalancing hints are
  an in-scope exception per ADR-0023: computing and showing indicative
  corrective quantities next to the allocation drift is allowed, but anything
  that creates, stores, or transmits an order remains forbidden. *Why:* each
  needs a decision not yet taken — sync stores bank credentials, PDFs are
  hostile input, an order or an in-app model would make the system act instead
  of prepare (PRD §4 gate table; ADR-0021; ADR-0023). Why the binary
  `.portfolio` format stays out is not recorded.
- Analytics scope follows the **scope ladder** (ADR reference: identity gate
  B3.1), which replaced the blanket "no advanced reports" rule:
  - **(a) derived metrics** per security and per view — moving averages,
    volatility, drawdown, momentum, distance to extremes: **allowed**;
  - **(b) comparison and decomposition** — benchmark, contribution analysis,
    factor/sector/region exposure: **allowed**;
  - **(c) evaluation of decisions** — prediction calibration, rule evaluation,
    signal quality: **allowed**;
  - **(d) backtesting rules against stored price history: forbidden**, behind
    its own decision gate.
  Level (c) scores what was recorded before its outcome was known; level (d)
  replays a counterfactual. If an analytic needs a history in which the rule
  was already there, it is (d). *Why:* the blanket rule was drawn before anyone
  knew where the line was; a replay manufactures a history the rule never ran
  against (PRD §4 "Scope ladder"; ADR-0049 §4).
- Every metric in (a)–(c) must state its **computation basis** in its API and
  MCP payload: input series, window, reference series or benchmark where one
  exists, and the treatment of gaps. Review-blocking; a doc page does not
  satisfy it. *Why:* a metric whose basis is unstated cannot be checked by
  anyone, human or agent (brief addendum, "Every metric documents its
  computation basis").
- **Advanced classifications stay out of scope** — stored partial-weight
  assignments of one security to several categories (`CONTRIBUTING.md`). Level
  (b) may *report* a factor, sector or region breakdown from data the catalog
  already holds; a decomposition that needs such weights needs its own
  decision. *Why:* partial weights change the data model, not a report, and no
  decision has opened them (PRD §4).
- Gated, and none of them openable by citing the ladder: rule backtesting
  (level (d)); data acquisition beyond quotes and FX (B3.3); push delivery to
  external endpoints (B3.7); a local model beyond ADR-0021's PDF-intake path
  (B3.8). *Why:* B3.3 needs a design for sources, failures and retention, B3.7
  brings request forgery and stored secrets, and B3.8 should stay rare because
  deterministic code comes first (brief addendum, "Parked, with reasons").
- **Permanent non-goals — identity, not backlog**, and no capacity argument
  reopens them: no **order-placing** broker connection, no order creation or
  transmission, no automated trading or payment, no advice, no raw news
  archive, no external LLM calls from the app. The system prepares decisions;
  the operator executes them. Two precisions that narrow ambiguity without
  permitting anything new: the ban is on a connection that can *act* — place,
  modify or transmit an order, or move money, so **read-only** acquisition
  stays permitted in principle and gated in practice (Phase 3, still forbidden
  here until its ADR lands); and "no advice" does not retract ADR-0023's
  display-only rebalancing hints, which are arithmetic beside a drift figure.
  *Why:* they are what the product is: intelligence stays outside and
  replaceable, and the operator stays the one who acts (product brief, "Scope";
  PRD §1 "Cornerstone principle").
- **Machine-extracted data is a proposal until confirmed.** Anything extracted
  from an unstructured source carries its source link and a `machine_generated`
  marker and lands only after a human or an agent confirms it — the
  preview-then-apply shape the Portfolio Performance import uses. Independent
  of whether a local model is ever adopted. *Why:* an extractor can invent, and
  nothing it produces may land silently (PRD NFR-10).
- **Do not claim production readiness.** *Why:* there is no upgrade guarantee
  and one maintainer (launch readiness, Sprint 19).
- **Public files are normal, readable multiline files.** *Why (inferred):* a
  one-line or generated-looking file hides its changes from review; the
  pre-commit hooks guard line endings and invisible Unicode.
- **Write every repository artifact in English** — issues, PRs, commit
  messages, ADRs, code comments, documentation; the German docs translate the
  English source. *Why (inferred):* a public repository with one working
  language for agents and reviewers (PRD NFR-7; ADR-0014).

## Privacy And Disclosure

This repository is public. **Never commit anything that describes a real
person's private life or finances**, in any artifact: code, tests, fixtures,
docs, ADRs, commit messages, and above all agent output (`_bmad-output/` plans,
session notes, reviews). That means:

- no real portfolio data — balances, net worth, invested capital, performance
  figures, credit lines, positions, transactions; synthetic data stays
  synthetic all the way down, including its description;
- no names of household members, partners, children or pets; use placeholders
  such as `Family` or `Guest`;
- no personal banking relationships or private tooling (naming a provider as a
  generic integration target is fine);
- no local machine details: home paths, usernames, hostnames, internal IPs;
- no personal agent state: `_bmad/config.user.toml`, `_bmad/memory/**`
  (gitignored; never force-add).

Scrub session artifacts before committing; when in doubt, leave it out. *Why:*
agent sessions routinely surface real data, and Git history cannot be cleaned
afterwards — a rewrite breaks every clone and never reaches copies already
fetched; five committed records had to be scrubbed in Sprint 16 (Sprint 16 plan
D-11; [SECURITY.md](SECURITY.md)).

## Commit Authorship

Every commit is authored by the accountable human under their own GitHub
identity (`user.name`/`user.email`, ideally the `…@users.noreply.github.com`
address listed in `.github/commit-authorship-allowlist.txt`), even when an
agent wrote it. Never a bot or agent identity, never a `Co-authored-by:` that
credits an AI, never `Model:`, `Thinking level:`, `Claude-Session:` or
session-URL footers; put the model in the PR description. A `commit-msg` hook
and the "Commit authorship" CI workflow enforce it; do not work around them.
*Why:* a person owns the result and answers for it; the rule was re-examined
and kept (Sprint 17 plan D-10; `scripts/check-commit-authorship.sh`), and CI
re-checks because a local hook can be skipped.

## Security Boundaries

- **No secrets in source**; the API and the MCP companion authenticate with
  local bearer tokens from the environment. *Why:* the repository is public, so
  a committed key is a leaked key ([SECURITY.md](SECURITY.md);
  `test/invariants/scope_b1_no_stored_credentials_test.exs`).
- **No `.env` writing from the web UI.** *Why (inferred):* the UI runs without
  a login unless one is configured (ADR-0045), so a UI that writes `.env` would
  let anyone who reaches it change the secrets.
- No external LLM calls, orders, payments or trading: see Hard Rules.

## Architecture

- **A modular Phoenix monolith**: one context per domain under
  `lib/portfolixir/` (Catalog, Portfolios, Ledger, Imports, Knowledge,
  Lifecycle, Tax and the rest), the web layer in `lib/portfolixir_web/`, and
  `mcp-server/`, a TypeScript MCP companion. Contexts never depend on the web
  layer. *Why:* a single-user tool gains nothing from services but overhead,
  and clear seams keep the domain testable (ADR-0001).
- **MCP tools call the public JSON API only** — never the database or the
  Elixir contexts. *Why:* one integration contract and no second data path
  around the API's validation and auth (ADR-0002;
  `test/invariants/mcp_dependency_allowlist_test.exs`).

## API And MCP Coverage

- **Coverage runs both ways.** A new user-visible function gets API and MCP
  coverage, or the PR says why not. A new agent-visible capability may ship
  over API and MCP alone, with the reason stated, when its human view lands in
  the same or the next sprint; a missing view after that is a close-out
  finding. *Why:* both users are first-class, and without the deadline the rule
  decays into "agent only, forever" (brief addendum, "API and MCP Coverage
  becomes symmetric").
- **Endpoints live under `/api/v1`; financial decimals are strings** in API
  responses and in MCP tool schemas. *Why:* JSON numbers become binary floats
  in most clients and lose cents (ADR-0003).
- **The MCP companion installs and runs on its own, outside Docker Compose.**
  *Why (inferred):* MCP clients start it themselves as a local process (connect
  an agent).

## How Work Is Done

- **A sprint is two sessions and two PRs.** A planning session writes the
  planning PR, and the owner's merge is the signature; a fresh implementation
  session builds the whole sprint on one branch as one sprint PR, with the
  lanes as commit groups and the retrospective as its last commits. *Why:* two
  owner touchpoints per sprint instead of five, and a fresh session tests
  whether the plan is complete (ADR-0026, amendment of 2026-10-08; [sprint
  workflow](docs/development/sprint-workflow.md)).
- **A UI change is mocked on a board before it is built**, risk-tier work gets
  its own commit group and verification pass, and issues are thin pointers: see
  the sprint workflow for each rule and its reason.
- **A PR you open is yours until it is merged or closed**: subscribe to its
  events as soon as it exists (never offer to and wait for a yes), drive CI to
  green, keep it current with `main`. Never weaken a quality gate, never fix
  outside the PR's scope, **never merge**. *Why:* an offer declined by silence
  leaves the PR unwatched, and a lapsed watch makes no noise (Sprint 10
  retrospective); the gates stand in for the human read (ADR-0026,
  "Compensating controls"; ADR-0036), and the merge is the owner's acceptance
  (ADR-0026 step 4).
- **Ask the owner only what only the owner knows**: a fact on the owner's own
  instance, a change to how stored money data is booked or corrected, scope and
  non-goals. Decide everything else with its reason, flippable by a comment,
  and open every plan and PR body with "What you need to do". *Why:* the
  owner's attention is the scarcest resource (ADR-0038; ADR-0026, amendment of
  2026-10-08).
- **Branches** are `agent/<provider>/<topic>`, a sprint
  `agent/<provider>/sprint-<N>`; `codex/<topic>` is legacy. *Why (inferred):*
  the name shows which agent made a branch.
- **Stop the moment the owner says stop.**

## Required Local Checks

Run these before opening a PR and before every push. The list is CI's
`pre-commit`, `test` and `quality` jobs, so a branch that passes here passes
there. *Why:* a shorter list omitted eight of CI's checks, and a batch that
skipped two of them cost a round (Sprint 13 retrospective).

```bash
mix format
mix compile --force --warnings-as-errors
mix gettext.extract --check-up-to-date
mix test
mix coveralls
mix credo --strict
mix sobelow --skip --exit
mix dialyzer --format short
mix deps.unlock --check-unused
mix hex.audit
mix deps.audit
pre-commit run --all-files
npm test --prefix mcp-server
npm run build --prefix mcp-server
npm audit --audit-level=high --prefix mcp-server
```

`mix dialyzer` builds its PLT once, slowly. `mix hex.audit` and `mix
deps.audit` read a live advisory database, so a gate can turn red with nobody
pushing: that is a new advisory, not a regression. Install the hooks with
`pre-commit install --install-hooks`.
