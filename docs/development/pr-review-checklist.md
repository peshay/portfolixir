# Portfolixir PR Review Rubric (verified, agent-runnable)

Mechanical gates (CI) already cover a lot: `pre-commit`, `mix format`,
`mix compile --warnings-as-errors`, `credo --strict`, `sobelow`, `dialyzer`,
`mix deps.audit` / `hex.audit` / `npm audit`, migration immutability, coverage
ratchet, and the invariant meta-tests under `test/invariants/`.

This rubric covers what CI **cannot** check: whether an agent-authored change is
actually correct *in intent*, stayed in scope, and respects the load-bearing
architecture promises. It exists because the maintainer does not read code in
detail — so a wrong detail that slips past CI reaches production.

## How to use it (the verify-before-surface protocol)

The point of this gate is **not** to dump every suspicion on the maintainer. It
is to surface only **confirmed, decision-worthy** findings.

1. **Review** the diff against the load-bearing checks below.
2. **Verify** each candidate finding against the *actual code, tests, and ADRs*
   before reporting it. A finding that turns out to be intentional/documented
   (e.g. `audit_journal.scenario_id` is a documented forward-index in ADR-0017,
   not stray scaffolding) is **dropped**, not surfaced.
3. **Surface** only what survives verification, grouped by severity, each with
   `file:line`, the rule it breaks, and a one-line recommended decision.
4. If nothing survives, say so plainly ("no confirmed findings"). Silence is a
   valid, valuable result.

## Load-bearing checks (Portfolixir-specific)

These are the things that have actually bitten this project. Check each against
the diff; verify before reporting.

### A. Decimal discipline (NFR-1, ADR-0003)
- No float arithmetic (`/`, `*`, `:math`, `Float.`, `Kernel.round/1`) on money,
  quantities, prices, fees, taxes, or FX rates.
- The **only** sanctioned float island is Newton's method in
  `lib/portfolixir/portfolios/performance/irr.ex` — boundaries convert back to
  `Decimal`. Any other float in engine/financial code is a finding.
- No float persisted (the `decimal_persistence_test` invariant guards this — but
  check the diff didn't add an `:float`/`:integer` money column).

### B. Audit-journal completeness (FR-28, NFR-2, ADR-0017)
- ADR-0017 rolls out per-context in slices. Slice 0 (infra) and Slice 1
  (Catalog/Fx) are armed; **Portfolios/Classifications → Ledger → Imports are
  not yet**.
- If the diff **adds or changes a write path** in an *already-armed* context, it
  MUST be actor-first and routed through `Journal.record/3` in the same
  `Ecto.Multi`. A new unjournaled write in an armed context is a finding.
- Journaling lives in the context (imperative shell) — **never** in engines or
  read-model loaders (ADR-0011, architecture D2).
- **Do not arm MCP/API write tools for a context whose journal slice has not
  landed** — that lets an agent write without an audit trail.

### C. Scope lock (AGENTS.md "Hard Rules" + "Scope Lock")
- Change touches only the requested story; no adjacent features bolted on.
- No gated capability leaked in: document intake other than PP CSV/JSON v1
  (PP XML, broker PDFs, `.portfolio`), broker/bank sync, trading/payment/order,
  rebalancing, what-if simulator, benchmark, LLM behavior — each needs a scope
  ADR + AGENTS.md amendment first.
- Directories `lib/portfolixir/sync/` and `lib/portfolixir/pensions/` stay empty
  until their scope ADR lands (AR-9).
- Architecture not silently changed; larger issues discovered → follow-up note,
  not opportunistic fix.

### D. API / MCP parity (AR-11, ADR-0002, AGENTS.md "API And MCP Coverage")
- Every new user-visible function has an API endpoint **and** an MCP tool, or the
  PR explicitly documents why coverage is n/a.
- MCP tools call the public JSON API only — never the DB or Elixir contexts
  directly (guarded by `mcp_dependency_allowlist_test`, but verify the intent).
- Financial decimals serialized as **strings** in both API responses and MCP
  schemas.

### E. TDD honesty (AGENTS.md "AI Authoring Contract", PR template)
- A user-story comment exists in the touched test file with the functional test
  directly below it.
- Tests were written first and failed-first for the expected reason. If the PR
  checklist claims this, spot-check the diff/commits actually reflect it — a
  checked box that the diff contradicts is a finding.
- Calculations use deterministic synthetic fixtures and exact `Decimal`
  expectations; no live network calls in tests.

### F. Docs & truthfulness
- User-visible behavior change → user docs updated (or PR explains why not).
- No production-readiness claims; no real financial data committed.
- Repository artifacts in English.
- Plan drift: if the change materially completes/changes an FR, the reconciliation
  section of `_bmad-output/planning-artifacts/epics.md` may be stale — note it.

## Severity guidance

- **Blocker** — breaks a load-bearing invariant (unjournaled write in an armed
  context, float on money, gated-feature leak, MCP bypassing the API).
- **Should-fix** — scope drift, missing API/MCP parity without an n/a note,
  TDD-order not actually followed, missing tests on risky code.
- **Note** — stale plan/docs, minor inconsistency, follow-up worth tracking.

Surface Blockers and Should-fix items. Roll Notes into a short trailing list.
