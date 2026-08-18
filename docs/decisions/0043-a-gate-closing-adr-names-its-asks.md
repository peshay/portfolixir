---
layout: docs
title: "ADR-0043: an ADR that closes a decision gate names the asks it answers — and the ones it does not"
description: A gate is opened on a set of asks and closed by an ADR, and nothing in ADR-0026 checks that the ADR answers what the gate was opened for. ADR-0039 proved the cost - it closed gate B3.2 on durability while the gate's second ask, push-on-write, fell out silently and survived the batch, the review closing act and the close-out, because every one of those holds the work against the ADR and the ADR was internally complete. The rule is one paragraph: a gate-closing ADR carries a list of the gate's asks, each marked answered or deferred with a reason. It costs a few lines and turns a silent drop into a written deferral.
---

# ADR-0043: an ADR that closes a decision gate names the asks it answers — and the ones it does not

- **Status:** Proposed — awaiting owner sign-off (this is itself a change to how
  the project decides, so it is the owner's, per
  [ADR-0026](0026-epic-batch-workflow.html))
- **Date:** 2026-08-17

## Context

[ADR-0026](0026-epic-batch-workflow.html) step 1 requires a decision gate — an
ADR or spec with acceptance criteria — signed off before a batch starts. In
practice a gate is *opened* by an owner asking for something, often several
things at once, recorded in a triage document or a product brief. It is *closed*
by an ADR written later.

**Nothing checks that the closing ADR answers what the gate was opened for.**

This is not hypothetical. It was diagnosed on 2026-08-15 (feedback triage, Round
7) with a worked example, and the example is the reason this ADR exists rather
than a note in a retrospective.

### What it cost, once

Gate **B3.2** was opened on two asks, both in the owner's words in the
2026-08-12 triage: derived values should be **durable**, and recomputation
should be **triggered by the write that invalidated it, or by a schedule — "so
that a read is never the thing that pays"**.

[ADR-0039](0039-durable-derived-values.html) decided durability. It is silent on
the push half. Nobody removed that ask and no one argued against it; it fell out
between the gate and the ADR.

The consequence is what makes this worth a rule. The drop survived:

- **the batch** — Sprint 6 Lane C shipped C1–C5 against the ADR;
- **the agentic review closing act** — six roles, every confirmed finding fixed;
- **the close-out** — ADR-0026 step 5, with gates green and a retrospective.

Every one of those holds the work against **the ADR**, and the ADR was
internally complete. There was no artifact anywhere in the chain that still knew
what the gate had been opened for. The owner discovered it by using the product
and asking why a "computing" cue still appears — three weeks and one release
later, and it cost the more visible half of the feature.

### Why the existing rules do not catch it

- The **Story Workflow**'s steps hold a story against its acceptance criteria,
  which come from the ADR.
- The **agentic review** holds the branch against the ADR and the design spec.
- The **close-out** reconciles issues, the FR map and the tracker.
- **ADR-0026 step 1** requires that a gate be signed off; it says nothing about
  what the signature is *for*.

Each is correct and none of them looks upstream of the ADR. The gap is
structural, not a lapse.

## Decision (proposed)

**An ADR that closes a decision gate carries a short list of the asks the gate
was opened on, each marked answered or deferred, with a one-line reason for
every deferral.**

That is the whole rule. Concretely:

1. **The list names its source** — the triage round, product brief section or
   issue where the asks were recorded, so a reader can check the list against
   what was actually asked.
2. **Every ask gets a verdict**: *answered by this ADR* (with the section), or
   *deferred* (with the reason and, where one exists, the gate or issue it moves
   to). "Not mentioned" stops being an available outcome.
3. **A deferred ask is a written deferral**, which means the close-out and the
   next planning round can see it. Today a dropped ask is invisible by
   construction.
4. **It is checked at the gate signature**, not later. The owner signing a gate
   is the last person who still remembers what they asked for, and the list is
   what makes the signature about that rather than about the ADR's internal
   coherence.

### What this is not

- **Not acceptance criteria.** Those belong to the stories and stay there. This
  is a list of *asks*, usually three to six lines.
- **Not a template section for every ADR.** Only ADRs that close a gate carry
  it. An ADR recording a design choice nobody gated has no asks to list.
- **Not a new gate, workflow step or artifact.** It is a required section in a
  document that already exists, which is why it is cheap enough to actually
  survive.

### Retroactive application: exactly one

**ADR-0039 gains the list**, since its missing half is the reason this rule
exists and the half is already filed (#710, #711). No other ADR is reopened —
auditing the back catalogue would cost more than the rule saves, and the rule is
preventive by design.

## Consequences

- A gate-closing ADR is a few lines longer, and the lines are the ones a
  reviewer most wants.
- **The owner's signature gets a checkable object.** The recurring complaint
  behind this — that sign-offs are the real load, four in one day on 2026-08-15
  — is not made worse: reading a five-line list of one's own asks is faster than
  reconstructing them from memory, which is the alternative.
- The close-out gains a place to look for deferred asks, which currently has no
  source.
- **A rule can be satisfied hollowly.** Someone can write "answered" against an
  ask the ADR does not really answer. This does not prevent that; it makes it a
  visible false statement rather than an absence. That is the whole of the
  improvement, and it is enough — the ADR-0039 drop was invisible, not disputed.

## What this does not decide

- **Whether gates should be smaller.** B3.2 carried two loosely related asks;
  one could argue for one gate per ask. That is a different decision and this
  rule works either way.
- **Anything about scope, the scope ladder or the permanent non-goals.** This is
  a rule about how a decision is recorded, not about what may be decided.
