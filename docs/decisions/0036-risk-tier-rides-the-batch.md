---
layout: docs
title: "ADR-0036: risk-tier work rides the batch — the dedicated-small-PR exception is withdrawn"
description: Amends ADR-0026. The risk-tier exception required ledger/money math, security-relevant changes, dependency updates and idempotency/projection work to ship as dedicated small PRs with real human review. With one reviewer that rule did not buy review, it bought queue: the micro-PRs were not being read. Risk-tier work now rides the epic batch like everything else, and "risk-tier" survives as an attention label that raises review depth and briefing emphasis, not as a delivery mode. The compensating controls become mandatory rather than aspirational.
---

# ADR-0036: risk-tier work rides the batch — the dedicated-small-PR exception is withdrawn

- **Status:** Accepted (owner decision 2026-08-04)
- **Date:** 2026-08-04
- **Amends:** [ADR-0026](0026-epic-batch-workflow.html) (the "Risk-tier
  exceptions" clause only; the rest of ADR-0026 stands unchanged)

## Context

[ADR-0026](0026-epic-batch-workflow.html) moved feature trees onto epic
branches accepted in one behavior-level review, and carved out an exception:

> **Risk-tier exceptions — these keep dedicated small PRs with real human
> review:** ledger/money-domain math and domain invariants, security-relevant
> changes, dependency updates, and anything touching the import idempotency or
> projection semantics.

The exception assumed those small PRs would actually be read closely. Six
weeks of practice say otherwise, and the reason is structural: this project
has exactly **one** reviewer, and ADR-0026 itself was written because that
reviewer's attention is the scarce resource. Carving the highest-risk changes
into their own queue did not add review capacity; it produced a backlog of
micro-PRs competing for the same attention that was already the bottleneck.

Sprint 3 made the cost concrete. The plan (`sprint-plan-2026-08-01.md`)
serialized three risk-tier items behind one reviewer and stated plainly that
"three risk-tier PRs plus one large cross-cutting batch do not review in
parallel through one person". The owner then directed all lanes to run in
parallel and land as one PR, and the same again for the #619 follow-on and
for a dependency update that blocked CI — three deviations from the same
clause within two days. A rule deviated from every time it binds is not a
control; it is paperwork that makes the record less honest.

The owner's own framing (2026-08-04): many small PRs simply do not get
reviewed, so the choice is not between a carefully-read small PR and a skimmed
large one. It is between an unread small PR and a large one whose risk-tier
content is deliberately surfaced. With
TDD-first discipline and the mandatory agentic review, a regression in
money-domain code should be caught by a failing test and an adversarial
reviewer, not by a human reading a diff they did not have time to read.

## Decision

**The risk-tier delivery exception is withdrawn.** Ledger/money-domain math,
security-relevant changes, dependency updates and import-idempotency /
projection work ship inside the epic batch like everything else, on the same
branch, in the same PR.

**"Risk-tier" survives as an attention label, not a delivery mode.** Marking a
change risk-tier now means:

1. **Its own commit or commit group**, never mixed into an unrelated commit,
   so it stays independently readable, revertable and cherry-pickable.
2. **Deeper agentic review.** The ADR-0026 closing act is mandatory anyway;
   for risk-tier content it must include a dedicated verification pass on the
   invariant at stake — the money identity, the idempotency property, the
   projection semantics — with findings verified against code, tests and the
   governing ADR before they are surfaced.
3. **Explicit callout in the reviewer briefing**, naming what changed, which
   invariant protects it, and which test pins it — so the owner's
   behavior-level acceptance is aimed at the risky part instead of spread
   evenly.
4. **Decision gate unchanged.** ADR-0026 step 1 still applies: risk-tier work
   that changes semantics needs its ADR signed off before the batch starts.
   Withdrawing the *delivery* exception does not withdraw the *decision* gate.

**The compensating controls stop being aspirational.** ADR-0026 listed them as
things the workflow "leans on"; they are now the substitute for the withdrawn
human read, and therefore blocking:

- TDD is not optional on risk-tier code: the test comes first, fails for the
  stated reason, and pins exact `Decimal` expectations where money is
  involved.
- Every quality gate green — `mix test`, `credo --strict`, `sobelow`,
  `dialyzer`, the migration and invariant meta-tests, the coverage ratchet,
  and the dependency audits. Weakening a gate to make a batch pass remains a
  review reject; that clause of ADR-0026 is reaffirmed, not relaxed.
- The multi-role adversarial review runs with verification-before-surfacing,
  and its confirmed findings are fixed on the branch before the owner sees
  the PR.

## Consequences

- **Accepted risk, stated plainly:** a silent money-math or idempotency error
  is invisible in a behavior walkthrough, and no human now reads those lines.
  The project accepts that exposure in exchange for review actually happening
  at all. The mitigation is mechanical (tests, gates, agentic verification),
  and its adequacy is itself reviewable — if a defect of that class reaches
  `main`, the retrospective must ask whether the mechanical controls or the
  briefing failed, and this ADR is the thing to revisit.
- Dependency updates ride the batch. The audit gates (`mix deps.audit`,
  `mix hex.audit`, `npm audit --audit-level=high`) remain blocking, and a
  transitive **major** version bump must be named explicitly in the briefing
  even when it arrives inside a lockfile-only change.
- **Known gap in that control, recorded rather than glossed over.** On
  2026-08-04, while this ADR was being written, `mix hex.audit` on an
  advisory-aware Hex reported **15 advisories on `main`, five of them HIGH**
  (mint, hpax, cowlib, phoenix) — none of which either Elixir audit gate had
  surfaced. `mix hex.audit` runs pinned to Hex 2.4.1 by deliberate design
  (`ci.yml`: 2.5's advisory gating has no ignore mechanism, so a permanently
  unpatched upstream advisory would hard-fail CI with no recourse), which
  makes that step retirement-only; and `mix deps.audit`'s database did not
  carry the advisories, so the stated posture — "all HIGH/moderate Hex
  advisories are cleared by upgrades, not by ignores" — had quietly stopped
  being true. Eleven of the fifteen were closed by the dependency update in
  this same batch, and the remaining HIGH (phoenix `EEF-CVE-2026-56811`) by
  the Phoenix 1.8 upgrade that followed it in the same batch
  ([ADR-0037](0037-phoenix-18-liveview-1x.html)) — the tree is now down to two
  advisories, neither HIGH, both without an upstream fix. **The gate itself is
  still weaker than this ADR's reliance on it assumes**, and after the upgrade
  the reason is purely the tooling: `mix hex.audit` on Hex 2.5+ sees
  advisories but has no ignore mechanism, so arming it would hard-fail on the
  two unfixable cowlib entries, while `mix deps.audit` has the ignore list but
  its database does not carry them. Until one of the two grows the missing
  half, an advisory-aware step can be visible but not blocking. Closing this
  properly remains the first follow-up this decision owes.
- The MCP companion's own gates (`npm test`, `npm run build`) are added to CI
  by this batch: AGENTS.md mandated them locally, but CI ran only the npm
  audit, so an MCP-only change rested on an unverifiable local claim — not
  acceptable once "every gate green" replaces the human read.
- PR size grows further. That is the intended direction: fewer, larger,
  briefed review units instead of many unread ones.
- AGENTS.md's "Epic-Batch Workflow" section is updated to match; ADR-0026 is
  marked as amended here rather than rewritten (AGENTS.md: decisions change by
  new ADR, never by silent edit).
- First application: PR #631, which already carries the Sprint 3 batch, the
  #619 follow-on and the dependency fix under three recorded deviations —
  those deviations become the normal path as of this decision.

## References

- [ADR-0026](0026-epic-batch-workflow.html) — the amended decision; its
  economics argument is the same one that now removes its own exception
- `_bmad-output/implementation-artifacts/sprint-plan-2026-08-01.md` — the
  capacity statement that made the exception's cost explicit
- [ADR-0028](0028-corporate-actions-as-ledger-events.html),
  [ADR-0029](0029-stable-identities-and-reimport-survival.html),
  [ADR-0030](0030-position-level-soll-targets.html),
  [ADR-0033](0033-per-position-pnl-fx-decomposition.html),
  [ADR-0035](0035-one-pricing-pass-per-read.html) — risk-tier decisions whose
  "dedicated small PR with real human review" **delivery** clauses are
  superseded by this ADR; their technical content is untouched. ADR-0028,
  -0029 and -0030 carry *undelivered* follow-on slices, so their delivery
  bullets are annotated in place — a future agent reading them must not
  follow a withdrawn rule.
