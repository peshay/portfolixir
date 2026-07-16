---
layout: docs
title: "ADR-0027: named plan versions and ledger-marker depot snapshots"
description: Decision that target plans become named, versioned entities (active/draft/archived, duplicate-to-edit) and that a depot snapshot is a pure ledger marker (scope + as-of date, no copied data) whose buy-and-hold valuation over real quote history answers "would I have done better if I had kept my old holdings?".
---

# ADR-0027: named plan versions and ledger-marker depot snapshots

- **Status:** Accepted (owner sign-off 2026-07-16, decision gate per [ADR-0026](0026-epic-batch-workflow.html))
- **Date:** 2026-07-16

## Context

The owner's workflow (design conversation 2026-07-16): an allocation plan with
target weights exists; the owner wants to **restructure** it. That means (a)
editing a copy of the plan while the old one stays visible for reference, (b)
freezing the depot state at the moment the strategy changes, and (c) later
answering the founding question of the PRD's Phase 5: *"would I have performed
better if I had stayed with the old plan?"* — comparing the real (new-plan)
performance against the counterfactual of having kept the old holdings.

Two constraints shape the design:

1. **Plans are single per scope today.** Since [ADR-0020](0020-view-bound-soll-plans.html)
   a target plan belongs to `(portfolio, view, classification)` and a
   partial-NULL-aware unique index allows **at most one** plan per scope. Plans
   have no name and no status, so "old plan and new plan side by side in the
   same view" is not representable.
2. **Holdings are never stored.** Everything is a projection of the transaction
   ledger ([ADR-0004](0004-holdings-derived-from-transactions.html)); any
   historical depot state (quantities, cost basis) is exactly reproducible by
   projecting transactions up to a date. Copying trade history into a snapshot
   would duplicate the source of truth the architecture deliberately keeps
   single.

The full what-if simulator (FR-27, #332 — fictitious trades layered over real
quote history) is explicitly **not** the goal of this decision. The owner needs
the snapshot comparison first; the simulator remains a later phase and must be
able to build on the primitives introduced here.

## Decision

### 1. A depot snapshot is a ledger marker, not a copy

A **snapshot** is a named reference point: `(name, view scope, as-of date)` —
filesystem-snapshot semantics. It copies **no** transactions, quantities, or
prices. The snapshot's holdings and cost basis are derived on demand by
projecting the ledger up to the as-of date within the view's scope, exactly as
the existing holdings projection does for "today". Snapshots are cheap to
create, cheap to delete, and can never drift from the ledger.

### 2. The v1 counterfactual is buy-and-hold, compared via TTWROR

The comparison answers *"would I have done better if I had changed nothing?"*:

- **Snapshot side:** the positions held at the as-of date, frozen (no trades,
  no flows), valued over the **real stored quote history** from the as-of date
  forward.
- **Real side:** the view's actual TTWROR since the as-of date.

TTWROR neutralises deposits and withdrawals by construction, so the "how do we
recognise fresh money vs. reinvestment?" problem does not arise in v1 — no flow
classification is needed. The v1 comparison is **gross and price-return only**;
dividends the frozen positions would have paid are a documented follow-up
(requires per-security distribution history, which the app only has as the
owner's own booked transactions today). Every comparison surface labels this
basis explicitly (as-of date, gross, price-return — UX-DR11).

Simulating "rebalancing as the old plan would have prescribed" is **out of
scope** here; it is the what-if simulator's job (FR-27) and layers fictitious
scenario trades on top of a snapshot base later (scenario isolation per AR-8;
the `audit_journal.scenario_id` forward-index from
[ADR-0017](0017-append-only-audit-journal.html) anticipates exactly this).

### 3. Target plans become named, versioned entities

- A plan gains a **name** and a **status**: `active` / `draft` / `archived`.
- The ADR-0020 uniqueness tightens to: at most one **active** plan per
  `(portfolio, view, classification)`. Drafts and archived plans coexist freely
  in the same scope.
- **Duplicate-to-edit:** duplicating a plan copies its target weights and cash
  target into a new `draft`; activating a draft archives the previously active
  plan. The allocation/drift engine keeps consuming exactly one plan — the
  active one — so ADR-0020's coherence guarantees are untouched.
- Migration is loss-free: every existing plan becomes `active` with a default
  name.

### 4. Sequencing: journal-arming rides along

Plan writes are not yet journaled (open slice of the leaf-first
[ADR-0017](0017-append-only-audit-journal.html) rollout, noted in
`Portfolios.TargetPlan`). Introducing duplicate/activate/archive — new write
paths — without journaling would widen the auditability gap, so arming the
Targets/Plans context is part of the same epic, before or with the versioning
stories.

## Consequences

- Positive: snapshots are near-free and always consistent with the ledger; the
  counterfactual needs no new stored financial data (NFR-2 holds trivially);
  the primitives (snapshot base, scenario column) are the foundation FR-27
  builds on instead of throwaway work; plan history becomes explicit instead of
  living only in the audit journal's before/after images.
- Negative / accepted: v1's buy-and-hold counterfactual understates a
  disciplined old-plan strategy (no rebalancing simulation) and omits
  distributions — both are labeled on-surface and deferred deliberately.
- The quote history becomes load-bearing for past dates: valuing a snapshot
  needs quotes from the as-of date forward; gaps are surfaced with the existing
  gap-marker contract (AR-4), never silently interpolated.

## References

- [ADR-0004](0004-holdings-derived-from-transactions.html) — holdings derived, never stored
- [ADR-0017](0017-append-only-audit-journal.html) — audit journal, `scenario_id` forward-index
- [ADR-0020](0020-view-bound-soll-plans.html) — view-bound target plans (uniqueness refined here)
- [ADR-0026](0026-epic-batch-workflow.html) — decision-gate workflow this ADR follows
- FR-27 / #332 — what-if simulator (later phase, builds on these primitives)
- Epic tracking: E16 in `_bmad-output/planning-artifacts/epics.md`
