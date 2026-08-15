---
layout: docs
title: "ADR-0040: a target plan states its unallocated remainder"
description: A plan whose weights deliberately sum to less than 100% is a legitimate strategy, not an error. The remainder becomes an explicit, named part of the plan; drift is computed against the allocated portion so an intentionally unused category cannot smear a phantom deviation across its siblings; and the warning is reserved for the two states that really are wrong - a sum above 100% and a position-vs-category conflict.
---

# ADR-0040: a target plan states its unallocated remainder

- **Status:** Accepted (owner decision 2026-08-15, recorded in
  `_bmad-output/planning-artifacts/feedback-triage-2026-08-15.md` Round 2/A2;
  decision gate per [ADR-0026](0026-epic-batch-workflow.html))
- **Date:** 2026-08-15

## Context

The plan editor treats any weight sum other than 100 % as a mismatch: the Σ row
gains `is-target-mismatch`, a warning colour and a red ✗. That rule assumes
every plan intends to allocate everything.

The owner's plan does not, and the reason is ordinary strategy rather than an
oversight: one satellite category is deliberately not fully used, so the
top level is set a little short on purpose. The system has no way to express
that. It can only be silent (leave the gap and live with a standing red mark)
or lie (inflate a weight the owner does not intend).

Two further defects follow from the same missing concept, and they are worse
than the visual one:

1. **Drift is computed against a plan that does not add up.** Every category's
   actual weight is measured against a target set whose total is below 100 %, so
   the unallocated share is silently distributed as apparent overweight across
   the categories that *do* carry a target. The "Needs attention" card on the
   Overview ([ADR-0022](0022-task-oriented-information-architecture.html)) then
   surfaces deviations that are an artifact of the gap, not of the portfolio.
2. **An agent reading the plan sees weights that do not sum to 100 % and has to
   guess.** Under the two-audience identity (#663) that is a payload defect: the
   plan omits a fact the reader needs, so the reader invents one.

Nothing in [ADR-0020](0020-view-bound-soll-plans.html) (plans belong to a view),
[ADR-0027](0027-plan-versions-and-depot-snapshots.html) (plans are named and
versioned) or [ADR-0030](0030-position-level-soll-targets.html) (positions steer,
categories roll up) decided what a short sum *means*. It was implemented as an
error because that was the only unambiguous reading available at the time.

## Decision

### 1. The remainder is part of the plan, stated on purpose

A plan carries an **unallocated remainder**: `100 % − Σ(top-level effective
weights)`, surfaced as a named row rather than derived silently by each reader.
It is a first-class part of the plan's meaning — "this share is deliberately not
steered" — not a rounding artifact and not an error.

The remainder is **computed, never stored**. Storing it would create a second
number that can disagree with the weights it is derived from, which is the
failure [ADR-0004](0004-holdings-derived-from-transactions.html) exists to
prevent. It is materialized only where every other derived value is, under
[ADR-0039](0039-durable-derived-values.html)'s rules.

### 2. Drift is computed against the allocated portion

Where a plan carries a remainder, per-category drift compares each category's
actual weight against its target **within the allocated portion**, so the
unallocated share is not distributed across the targeted categories as phantom
deviation. The drift sign convention of
[ADR-0023](0023-drift-sign-and-display-only-rebalancing-hints.html) (positive =
overweight) is unchanged; only the base of the comparison is stated.

The alternative — leaving drift against the full 100 % — would mean the Overview
card keeps reporting deviations nobody can act on, which is the same "alarm
without an address" defect this feedback round found elsewhere.

### 3. The warning is reserved for the two states that really are wrong

The mismatch cue (`is-target-mismatch`, the ✗, the warning colour) applies to:

- **a sum above 100 %** — over-allocation is unsatisfiable by construction, so
  it is genuinely an error;
- **a position-vs-category conflict** — the explicit/position-sum divergence
  [ADR-0030](0030-position-level-soll-targets.html) §2 already stores and
  surfaces, whose `conflict` flag stays exactly as decided there.

A sum **below** 100 % is neither. It renders as the remainder row, at ordinary
weight, with no warning colouring.

The badge microcopy is in scope for the design engagement (#707): "Σ conflict"
is jargon and does not say which of the two conflicts it means.

### 4. It is in the payload, both directions

The plan read endpoint and its MCP tool carry the remainder alongside the
weights, as a Decimal string like every other financial value, with the same
allocated-portion basis stated for the drift figures that accompany it. An agent
must not have to subtract to discover that a plan is short on purpose, and must
not be able to read drift without knowing what it is drift against.

## Consequences

- Positive: a deliberate strategy becomes expressible; the Overview card stops
  reporting artifacts; the plan payload becomes self-describing; the warning
  regains meaning by firing only on real errors.
- Negative / accepted: two plans with identical weights but different intent are
  still indistinguishable — the remainder says *how much* is unsteered, not
  *why*. A reason field was considered and rejected as prose nobody maintains.
- Risk-tier attention ([ADR-0036](0036-risk-tier-rides-the-batch.html)): the
  drift-base change alters a number the operator steers by. Its own commit
  group, a verification pass on the drift arithmetic, and an explicit callout in
  the reviewer briefing. Existing drift tests pin the full-allocation case and
  must keep passing unchanged — a plan summing to 100 % has a zero remainder and
  is therefore untouched by §2 by construction.
- Migration: none. Existing plans that sum to 100 % gain a zero remainder and
  behave exactly as before; plans that are short stop being flagged.

## References

- [ADR-0020](0020-view-bound-soll-plans.html) — plans belong to a view
- [ADR-0023](0023-drift-sign-and-display-only-rebalancing-hints.html) — drift sign
- [ADR-0027](0027-plan-versions-and-depot-snapshots.html) — named plan versions
- [ADR-0030](0030-position-level-soll-targets.html) — position-level targets and
  the conflict rule this decision leaves intact
- [ADR-0039](0039-durable-derived-values.html) — how a derived value is kept
- Owner feedback triage 2026-08-15, Round 2/A2 (the decision), Part 2/D3 (the
  observation that led to it)
