---
layout: docs
title: "ADR-0042: one planning structure — the requirement registry and the work breakdown stop competing"
description: Two parallel epic structures have coexisted since June and drifted apart measurably - 19 of 40 open work items have no row in the document that claims to break work down, and the tracking file generated from it is formally invalid against its own schema. This proposes splitting the two jobs those structures were both trying to do: epics.md keeps the requirement registry it is actually good at, the GitHub tracker set owns the work breakdown it already carries, and the sprint lane plan becomes the named execution artifact instead of an undocumented habit. The cost is stated rather than hidden - the BMAD tracking generator stops being applicable, and what replaces it is named here.
---

# ADR-0042: one planning structure — the requirement registry and the work breakdown stop competing

- **Status:** Proposed — awaiting owner sign-off (decision gate per
  [ADR-0026](0026-epic-batch-workflow.html))
- **Date:** 2026-08-17

## Context

Portfolixir carries two structures that both claim to organise the work, and
has done since June:

- **`epics.md` E1–E19** — nineteen epics with an Epic List, Epic Detail
  sections and, for four of them, `##### Story` rows. It also carries the
  Requirements Inventory (FR/NFR/UX-DR) and the FR Coverage Map.
- **The GitHub tracker set** — `#416` (data), `#417` (portfolio structure),
  `#418` (analytics), `#419` (LLM/MCP), `#420` (engineering quality), `#470`
  (transactions/imports UX), `#356` (UX and accessibility), with `#321` as a
  roadmap index and `#320`/`#340` as parking lots.

The tension has been recorded as a finding at every reconciliation since
2026-07-25, most recently as F2 (2026-08-12) and F7 (2026-08-17), each time
noting that the structural decision is the owner's and still open. Recording it
five times has not resolved it, and the drift is no longer theoretical.

### What is measurably true as of 2026-08-17

- **`epics.md` breaks down 19 stories across 4 of its 19 epics.** E19 has 7,
  E6 has 5, E17 has 4, E18 has 3. **Fifteen epics have none.** Five epics
  marked `in-progress` have zero stories, which `sprint_plan.py status`
  reports as five separate risks.
- **The GitHub trackers carry the real work.** All 40 open issues attach to
  them, including all thirteen filed on 2026-08-15. Sub-issue parentage is
  live in the API — `#700` reports `parent: #417`, `#701`–`#704` and `#707`
  report `#356`, `#705` reports `#419`, `#706` reports `#420`.
- **The generated tracking file is formally invalid against its own schema.**
  `sprint_plan.py validate` returns `valid: false` with five unrecognized keys
  (`6-dx-1-…` through `6-c-1-…`): the E6 batch used a story-key shape the
  generator cannot parse. The file has been invalid since that batch and no
  gate caught it.
- **The tool's recommendation is actively wrong.** With one backlog story row
  in the whole file, `sprint_plan.py status` recommends building
  `19-7-forward-projection-and-tax-bucket` — the one story deliberately
  deferred behind its own decision gate. It is not a bug in the script; it is
  the correct answer to a question asked of a document that no longer
  describes the work.
- **Sprints 3–6 were not run from either structure.** They were run from
  `sprint-plan-*.md` lane documents, which no ADR describes and no gate
  checks. The artifact that actually governs execution is the one with no
  recorded status.

The drift is therefore not a tidiness problem. A planning document that
answers "what should I build next" with a gated story, and a tracking file that
fails its own validator, are load-bearing artifacts giving wrong answers — and
this project's gates are load-bearing precisely because the owner does not read
code.

### Why now

Sprint 7 cannot be planned cleanly on top of it. Every one of the thirteen
candidate issues is a GitHub issue with no `epics.md` story row, so generating
tracking would add nothing and leave the same wrong recommendation standing.
The choice was going to be forced by the next batch regardless.

## Options considered

**A — Dissolve `epics.md` E1–E19 into the tracker set.** Delete the Epic List
and Epic Detail; the trackers become the only structure. *Rejected:* it throws
away the Requirements Inventory and FR Coverage Map, which are the parts that
demonstrably work — the FR map is what every reconciliation actually reads, and
it is where the two-way coverage rule and the scope ladder are enforced.
Deleting the epic sections is right; deleting the document is not.

**B — Dissolve the trackers into `epics.md`.** Give all 40 open issues story
rows. *Rejected:* it is large mechanical work whose output would immediately
re-drift, because issues are filed on GitHub and would have to be mirrored by
hand forever. It also inverts the issue convention: `AGENTS.md` says issues are
thin pointers and the ADR/epics document is authoritative for *specs* — not
that the document must restate the *backlog*.

**C — Split the two jobs, and name the execution artifact.** `epics.md` keeps
the requirement registry; the tracker set owns the work breakdown; the sprint
lane plan becomes a named, described artifact. *Recommended* — see below.

**D — Keep both and keep recording the finding.** *Rejected:* this is the
status quo, and five recordings across seven weeks are sufficient evidence that
it does not converge.

## Decision (proposed)

### 1. `epics.md` is the requirement registry, and stops being a work breakdown

It keeps — and remains authoritative for — the Requirements Inventory
(FR/NFR/UX-DR), the FR Coverage Map, the scope ladder boundaries, and the
dated Implementation Status reconciliations. These are the sections every
review actually reads.

It **loses** the Epic List, the Epic Detail sections and the `##### Story`
rows. What is worth keeping from them — an epic's intent paragraph — moves into
its tracker issue's body, which is where someone looking at the work will find
it.

### 2. The GitHub tracker set is the work breakdown

A unit of work is an issue; its parent is a tracker. That is already true in
the data and merely stops being contradicted. The issue convention is
unchanged: thin pointers, with the spec in the ADR or in `epics.md`.

Requirement-to-work traceability lives in **one** place — the FR Coverage Map's
issue column, which already carries it.

### 3. The sprint lane plan is the execution artifact

`sprint-plan-<date>-sprint<N>.md` gains recorded status: lanes, the issues in
each, sequencing constraints, risk-tier markings, and the open questions the
batch must answer. It is what Sprints 3–6 already used; this only makes it
describable and reviewable.

### 4. `sprint-status.yaml` is retired as a story tracker

This is the honest cost of the decision and is stated rather than buried:
**`bmad-sprint-planning`'s `generate` path stops being applicable to this
project**, because it derives story rows from `epics.md` sections that will no
longer exist.

What replaces each thing it provided:

| Provided by the tracking file | Replacement |
|---|---|
| story status | GitHub issue state, verified against merge commits on `main` |
| epic status | tracker issue state |
| the close-out / reconciliation log | **kept** — this is the part with real value |
| next-action recommendation | the sprint lane plan |

The file is therefore **not deleted**. It is narrowed to what it does well: the
dated close-out and reconciliation log, which is the project's memory of what
was verified when, and which no other artifact carries. Its
`development_status` block goes, along with the five invalid keys.

### 5. `#321` closes

Its "working agreement" section is preserved into `AGENTS.md` first, per the
condition recorded in the 2026-08-04 reconciliation. It is then closed by hand
with the reason, not by a keyword — it is invalidated rather than implemented.

## Consequences

- One structure to update, so a reconciliation stops being an act of
  translation between two.
- The BMAD sprint-planning skill is used for its **readiness gate and status
  view**, not its generator. That is a real capability loss and is accepted
  deliberately: a generator that produces an invalid file recommending a gated
  story is not providing the capability its name suggests.
- `bmad-retrospective` and `bmad-story-automator` read story rows and will need
  checking against this change before their next use. **Not resolved here** —
  flagged as the one piece of follow-up this decision creates rather than
  removes.
- The Epic Detail prose must be moved before it is deleted, or context is lost.
  This is the migration's only substantive risk and belongs in the batch that
  executes it, not in this ADR.

## What this does not decide

- **Whether the 2026-08-15 issue family gains FR numbers.** Most of the
  thirteen are defects and design work, which have never carried FRs; `#708`–
  `#712` derive from ADRs and may deserve them. That is a requirement-registry
  question, decidable after this one and independent of it.
- **Anything about scope, gates or the scope ladder.** This is a decision about
  where work is written down, not about what work is permitted.
