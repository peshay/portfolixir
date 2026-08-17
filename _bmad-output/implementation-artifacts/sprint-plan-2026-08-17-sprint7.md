# Sprint Plan — Sprint 7 (ADOPTED, 2026-08-17)

**Status: adopted.** No draft preceded it: the questions a draft would have
asked were answered by the pre-sprint reconciliation (PR #714) and by ADR-0042,
which the owner signed off the same day.

Ground truth: `main` at `1a88ad5`. Verified against the merge commits
(`f0beb8c..1a88ad5`), the open pull-request list (8, all Dependabot), the
open-issue list (40) and the Actions runs on `main` — not against
`sprint-status.yaml`, which was itself stale until PR #714.

## What this sprint is

**The UI closer, and the first sprint under one planning structure.**

Sprint 6's OQ-2 stated the consequence of its own scope cut plainly: *after
Sprint 6 the UI is aligned but not finished, and Sprint 7 is committed as the
closer.* That promise is kept here rather than rolled forward — see Lane A's
sequencing, which is the whole reason the lane is ordered the way it is.

## Decisions (2026-08-17)

**D-1 — ADR-0042 is signed off (owner).** The migration runs as Lane Z. Because
the gate was signed before this batch opened, Lane Z is execution, not
decision-making.

**D-2 — #414 and #672 are built in this sprint, after #707, not deferred again
(batch agent).** The triage instructs that both "should follow #707's output
rather than land on the pre-design-language screen". Sprint 6 read a similar
constraint as grounds for deferral. Deferring twice on the same reasoning turns
a sequencing constraint into a permanent excuse, and it would break OQ-2's
commitment for the second time. The constraint is satisfied *within* the batch
instead: **#707 ships its spec first**, and the two builds are held against it.
Design work is fast for an agent; it was the reviewer, not the designer, that
was scarce.

**D-3 — #708 and #709 are deferred to Sprint 8 (batch agent).** Both have
signed-off ADRs and neither is blocked; this is a capacity call, made up front
rather than mid-sprint. With Lane C carrying risk-tier projection semantics and
Lane D carrying the money-weighted roll-up, adding the snapshot comparison's
new pre-cost figures (#708) and the plan-drift denominator change (#709) would
put **four money-domain items in one batch** — precisely the WIP problem
ADR-0036 was written about, with the same single reviewer.

Why these two and not the other two: **#712 earns its place twice** — the owner
asked for it, and per PR #714's analysis it also discharges the roll-up half of
the FR-37 human-view obligation. **#710 earns its place** because its absence is
a live performance defect: an uncoalesced refresher turns one import into
thousands of full recomputations, and every other analytic sits on that
mechanism. #708 and #709 are wanted, but nothing degrades while they wait.

**D-4 — #572 stays out, third sprint running (batch agent).** The reasons from
Sprint 6's OQ-3 are unchanged and none has been worked on: its three design
questions are still unresolved, its inflation/CPI half still needs a source
gated at B3.3, and it is still money-domain analytics. **Recorded as a standing
recommendation rather than a repeated deferral:** #572 should not appear in a
sprint plan again until a short ADR section settles its semantics. Listing it as
a candidate each sprint and cutting it each sprint is bookkeeping theatre.

## Batch topology

Unchanged from Sprints 5 and 6: **all lanes in ONE batch** on one epic branch,
**one PR for the sprint**, rebase-merged per the ADR-0026 amendment. A lane
splits into its own PR only if it proves big during the batch — flagged in the
briefing, not asked mid-sprint.

Branch: `agent/claude/sprint7-ui-closer`.

## Lanes

### Lane R — Review conditions (#706), first, because it improves this batch's own review

The design-critic pass ran at desktop width, in EN, against data that triggered
no finding surface — and four of six defects in the 2026-08-15 round were
invisible under exactly those conditions. Fixing the *conditions* before running
this sprint's review is worth more than fixing them after.

Deliverable: the design-critic and UAT walkthroughs run in **DE**, at **≤390 px**
as well as desktop, against seed data that **triggers the finding surfaces**
(stale quotes, missing FX, unclassified securities, a plan short of 100 %).

### Lane Z — ADR-0042 migration

Mechanical, and it must precede any bookkeeping the other lanes touch.

1. Move each Epic Detail intent paragraph into its tracker issue body **before**
   deleting it — this is the migration's one real risk.
2. Delete the Epic List, Epic Detail and `##### Story` rows from `epics.md`;
   keep the Requirements Inventory, FR Coverage Map, scope-ladder boundaries and
   the dated reconciliations.
3. Narrow `sprint-status.yaml` to its close-out/reconciliation log; drop
   `development_status` and with it the five schema-invalid keys.
4. Preserve #321's "working agreement" section into `AGENTS.md`, then close #321
   **by hand with the reason** — invalidated, not implemented, so no keyword.
5. Amend `AGENTS.md` where it references the removed structures.

### Lane A — The UI closer (the committed lane)

Ordered, because the order is the point:

1. **#707 — the design engagement.** Control vocabulary, card naming, and the
   two surfaces that predate the design language (Transactions, Income).
   Delivers a **spec** against the living design-language document, not a build.
2. **#702 — Wealth tab row clips on a phone.** A #668 regression that leaves the
   fifth tab unreachable at 390 px. Ships the overflow fix; the "should these be
   burger sub-items" navigation question belongs to #707 and is not answered
   here.
3. **#700 — asset class: stored vs. effective.** Two parts: render an inferred
   class as visibly *derived*, and pick one of stored/effective for the count,
   the filter and the quick-assign affordance. **The decision taken here governs
   #705** — record it in the commit, since it is a semantic choice made in
   implementation.
4. **#701** — securities table headers through gettext, **plus** the meta-test
   extension asserting no field-definition label bypasses the catalog. Without
   the meta-test the next field table repeats it.
5. **#703** — the `trade_priced` row names its positions; Overview keeps the
   alarm, Wealth states the consequence and drops the restatement.
6. **#704** — the ADR citation leaves user-facing copy, the computation-basis
   content stays, **plus** a meta-test that no gettext msgid matches
   `ADR-\d{4}`.
7. **#414 and #672**, built against #707's spec.

### Lane B — Agent and operator surface

- **#705** — data-quality predicates over the filter builder, API and MCP.
  **Strictly after #700**: the predicate must mean what the count means.
- **The `?since=` human view** — the one genuinely undischarged part of the
  two-way coverage obligation (PR #714's analysis). Needs an issue filed first,
  per ADR-0038. Its shape follows `SinceParam`: an operator-chosen cut, the rows
  created or updated since it, and **the deletion gap stated on the surface** —
  the computation-basis rule makes gap treatment part of the contract, and the
  agent half already documents it.

### Lane C — Durable derived values, risk-tier

- **#710 — refresh on the invalidating write, coalesced.** **Risk-tier.**
  Invariant at stake: one import must not produce thousands of full
  recomputations. `BlastRadius` widens most resource types to `:all` and an
  import bumps the version per booking, so **import is the acceptance scenario
  by construction**, not an edge case.
- **#711 — measure and activate the figures the operator actually waits on.**
  Measurement precedes activation; activating without it is guessing.

### Lane D — Category result

- **#712** — money-weighted roll-up on the category row, expandable to its
  member positions. `Σ result ÷ Σ invested`, never a mean of percentages. Rows
  whose result cannot be derived are **excluded and named**, never silently
  counted as zero. No membership history, no restatement caveat, no as-of
  qualifier — the figure describes the current composition, which is what
  ADR-0041 established after its first version got this wrong.

### Lane M — Maintenance (mandatory, every batch)

The 8 open Dependabot PRs, four of them majors with real breakage risk: **zod
3→4** (validation/error-shape changes in the MCP companion), **TypeScript
5→7**, **`@types/node` 24→26**, and the Actions bumps (`checkout` 5→7, `cache`
4→6, `setup-python` 5→7, `upload-artifact` 4→7, `codecov-action` 5→7).

Each lands as its own commit or commit group, never folded into a feature
story. **What is deliberately not updated is reported with the reason** — that
report is part of the lane, not optional.

## Sequencing

```
Lane R  ──▶ (review conditions ready before the closing act)
Lane Z  ──▶ (bookkeeping surface stable before anything writes to it)
            │
            ├── Lane A: #707 ──▶ #702, #700, #701, #703, #704 ──▶ #414, #672
            │                        │
            │                        └──▶ Lane B: #705
            ├── Lane C: #710 ──▶ #711
            ├── Lane D: #712
            └── Lane M: independent throughout
```

Hard constraints, everything else is free:

- **#705 after #700** — semantic dependency, not preference.
- **#414/#672 after #707** — the whole of D-2.
- **#711 after #710** — measure the mechanism you actually shipped.
- **Lane Z before any epics.md/sprint-status.yaml write.**

## If this batch must shrink

Named up front so a mid-sprint cut needs no new decision round — this is the gap
Sprint 6 fell into. Cut in this order, and stop as soon as it fits:

1. **#672** (the `/cashflow` parent and its facets) — largest new surface.
2. **#414** — but cutting it breaks OQ-2's commitment for the second time, and
   that must be said in the briefing rather than absorbed.
3. **#711** — #710 alone still fixes the defect; measurement can follow.
4. **Nothing else.** Lanes R, Z, C's #710, and Lane A's defect set are not
   cuttable: R protects this batch's own review, Z is a signed decision, #710 is
   a live performance defect, and #702 leaves a phone tab unreachable.

## Explicitly out of scope

- **#708, #709** — deferred by D-3, Sprint 8, ADRs already signed.
- **#572** — D-4; needs an ADR section before it is planned again.
- **The ADR-0038 amendment** named in ADR-0042's consequences. It is a decision
  about how the project decides, so it belongs to the owner.
- **The Round 7 gate-closure rule** (F8) — same reason, still unanswered.
- **FR-39/FR-40 themselves.** Lane C ships the *mechanism*; the derived metrics
  that ride on it are not filed and are not in this batch.
- Anything behind B3.3, B3.4, B3.6, B3.7, B4.1, B4.2, or ladder level (d).

## Gates

Every commit passes the local gates; the branch rebases onto `main` at least
daily. Batch-level, per ADR-0026 step 3, with two additions this sprint:

- multi-role agentic review: correctness hunter, edge-case hunter, UAT persona
  walkthrough on seeded synthetic data, design critic against the living
  design-language spec — **all run under Lane R's corrected conditions**;
- a dedicated verification pass on **#710's invariant** (the import scenario),
  per ADR-0036's risk-tier requirement, findings verified before they surface;
- the reviewer briefing calls out the risk-tier change, the #700 semantic
  decision, and what Lane M did **not** update.

## What "done" means for this sprint

1. `epics.md` and `sprint-status.yaml` carry one structure, and
   `sprint_plan.py validate` no longer returns schema-invalid keys.
2. The UI closer is closed — or its remainder is named in the briefing with the
   OQ-2 consequence stated, not absorbed.
3. `?since=` has a human view, or its absence is recorded as the close-out
   finding the two-way rule prescribes.
4. #710's invariant is pinned by a test that fails without the coalescing.
5. The maintenance lane reports what it did not update, and why.
6. Close-out per ADR-0026 step 5, including an **annotated** `0.7.0` tag —
   annotated, because F4 of the 2026-08-17 reconciliation found both existing
   tags lightweight.
