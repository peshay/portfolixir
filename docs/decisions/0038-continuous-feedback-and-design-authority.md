---
layout: docs
title: "ADR-0038: continuous owner feedback loop and a standing design authority"
description: Amends ADR-0026's acceptance practice. The per-epic owner UAT walkthrough assumed by the epic-batch workflow did not happen in practice — one partial pass in roughly three sprints — while day-to-day use kept producing observations with no defined intake. Feedback intake becomes continuous (unstructured owner dumps, PM triage, pipeline dedup, owner confirms routing), owner acceptance stays at the merge, and the agentic review closing act gains a standing design-critic role reviewing against a living design-language spec owned by the UX designer role, so visual drift becomes a review finding instead of an owner discovery months later.
---

# ADR-0038: continuous owner feedback loop and a standing design authority

- **Status:** Accepted (owner sign-off is the merge of the PR that carries
  this ADR, 2026-08-05)
- **Date:** 2026-08-05
- **Amends:** [ADR-0026](0026-epic-batch-workflow.html) (the acceptance
  practice in step 4 and the review-role roster in step 3; the batch
  mechanics, decision gates, and bookkeeping close-out stand unchanged)

## Context

[ADR-0026](0026-epic-batch-workflow.html) step 4 assumes the owner reviews
behavior per epic batch — effectively a UAT walkthrough at each acceptance.
Practice after roughly three sprints: that walkthrough happened once, partially.
This is not a discipline failure to be exhorted away; it is the same structural
fact ADR-0026 and [ADR-0036](0036-risk-tier-rides-the-batch.html) already
recognized — one owner, whose attention is the scarcest resource in the
project. A process step that requires a scheduled block of owner time per batch
will keep not happening.

Meanwhile the opposite channel works without being designed: day-to-day use of
the live instance produces a steady stream of concrete observations (loading
affordances, visual drift, ambiguous warnings, missing view options). Until
2026-08-05 these had no defined intake — the owner's choice was to interrupt
with unstructured notes or to sit on them until a review session that rarely
comes. The first triaged dump
(`_bmad-output/planning-artifacts/feedback-triage-2026-08-05.md`) showed the
mode works: of the observations reported, several were already tracked
(#560, #568, #572) — pipeline dedup is exactly the work an agent should be
doing, not the owner.

The same dump confirmed a second structural gap. The project has a design
spec from one early session (DESIGN.md + EXPERIENCE.md, 2026-06-12, tracked
in #356) but no standing role that holds a consistent design language while
features ship. The owner's expectation of the UX role — that it critiques
aesthetics, consistency, and UX simplicity on an ongoing basis — was never
wired into the workflow. The result is visible drift: text-only tabs next to
an icon-based menu, bare text-field date pickers, explanatory prose dumped
under charts in violation of the project's own UX-DR11 tooltip rule,
inconsistent loading placeholders. Every one of these passed review, because
no review role was looking.

## Decision

1. **Feedback intake is continuous, and the agent carries the structuring
   cost.** The owner drops observations at any time, in any form, unsorted.
   The PM agent triages each dump into a dated
   `planning-artifacts/feedback-triage-YYYY-MM-DD.md`: cluster, check the
   pipeline for existing coverage, route to epics/ADRs/decision gates, and
   propose next steps. The owner reviews the triage — minutes, not hours —
   and confirms or corrects routing. Only then are thin issues created per
   the issue-tracking convention. Design-affecting items go through a design
   pass before implementation stories are cut.
2. **Owner acceptance stays at the merge, unchanged.** The behavior review
   against the reviewer briefing (ADR-0026 step 4) remains the acceptance
   act. What this ADR removes is the fiction of an additional per-epic owner
   UAT session; systematic screen-by-screen evaluation happens when the
   owner chooses to do it, and its findings enter through the same feedback
   intake.
3. **The UX designer role becomes the standing design authority.** It owns a
   living design-language spec (starting by refreshing and promoting the
   2026-06-12 DESIGN.md + EXPERIENCE.md), and design decisions route through
   it the way architecture decisions route through ADRs.
4. **The agentic review closing act gains a design-critic role.** Alongside
   the correctness hunter, edge-case hunter, and UAT persona (ADR-0026
   step 3), every batch with user-visible surface is reviewed against the
   design-language spec for visual consistency, aesthetic quality, and UX
   simplicity. Design drift becomes a review finding on the branch, not an
   owner discovery months later.

## Consequences

- No observation waits for a review slot, and no owner session is spent on
  transcription or deduplication.
- The owner's recurring costs shrink to two small, well-defined acts:
  confirming a triage and accepting a batch.
- Design consistency gets an enforcement point with teeth (a review role and
  a spec to hold work against) instead of an aspiration.
- On acceptance of this ADR, AGENTS.md's Epic-Batch Workflow section is
  updated in the same PR: step 3's role roster gains the design critic, and
  step 4 drops the implied per-epic owner walkthrough.
- Risk: triage documents accumulate as paperwork. Mitigation: they stay
  short, live in `planning-artifacts/`, and items the owner does not confirm
  within a reasonable time are dropped rather than carried forward — the
  live instance will resurface anything that still hurts.
