# Sprint 10 — the security hardening batch (E21)

**Status: ADOPTED 2026-09-05** — the owner adopted the triage and signed
ADR-0045, D-3 and D-4 on PR #756 and asked for the whole batch in one sprint.
Verification basis: `main` at a48ed66 (the Sprint 9 close-out), the open-issue
list before this batch (24 open plus the 16 filed by the triage), no open pull
requests, no open Dependabot PRs at batch start.

This plan does not restate the lanes. **The authoritative lane plan is Part 3
of `_bmad-output/planning-artifacts/security-review-triage-2026-09-05.md`**,
which carries per lane the scope, the pinning test, the risk-tier callout and
the issue numbers. This document records only what the execution adds to it.

## What this sprint is

Lanes P, S, A, V, I, W and Z of the triage, in that order of dependency, on one
batch branch with one PR (ADR-0026). Lanes C (#382, CSP) and D (#772, Bandit)
are the next batch by the triage's own ruling and are not pulled forward.

## Branch

The batch rides the session-bound branch `claude/security-architecture-review-p42t07`
(restarted from `main` after the planning PR merged), the way Sprint 9's batch
rode its session branch — the agent session cannot push elsewhere. The
`agent/claude/…` convention in `AGENTS.md` is the intent; the session binding
is the mechanism.

## Execution notes the triage does not carry

- **Every commit group is risk-tier (ADR-0036):** one issue per commit or
  small commit group, the pinning test first, the invariant named in the
  commit message.
- **Lane M in this sprint:** no Dependabot PR is open at batch start; the
  #727 triggers are re-checked and reported; the version report is written
  at lane time.
- **The closing act** runs the four roles ADR-0026 step 3 names (correctness
  hunter, edge-case hunter, UAT persona on seeded synthetic data, design
  critic for the login page) plus a dedicated verification pass per risk-tier
  callout, and the briefing lists in one table every environment variable an
  operator has to set or change.
- **Disclosure:** the briefing and the commit messages name fixes, not
  exploits; the test fixtures carry the concrete cases.

## What "done" means

The triage's eight done criteria, unchanged, plus: the E21 row exists in the
Tracker Index and `sprint-status.yaml` (this commit), and `SECURITY.md` names
the batch as the hardening baseline.
