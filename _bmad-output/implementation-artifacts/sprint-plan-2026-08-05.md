# Sprint Plan — 2026-08-05

Companion to `sprint-status.yaml`. Sequences the open GitHub issues; the work
unit for the epics touched here is the issue (FR Coverage Map in `epics.md`).
Supersedes `sprint-plan-2026-08-01.md`.

Ground truth: `main` at `7495c4c` (Sprint 3 close-out merged). This plan rides
the feedback-triage PR (branch `claude/bmad-agent-feedback-dawtp4`); merging
that PR is the owner sign-off on ADR-0038, on the feedback-triage routing
(`feedback-triage-2026-08-05.md`, both rounds), and on this plan.

## Input that shapes this sprint

The 2026-08-05 owner feedback dump and its triage. Three structural facts:

1. **ADR-0038 (accepted with this PR's merge)** replaces the per-epic owner
   UAT expectation with continuous feedback intake, makes the UX designer
   role the standing design authority over a living design-language spec,
   and adds a design-critic role to the agentic review closing act.
2. **The pipeline already covered part of the dump** — #560 (mobile income
   chart defect), #568 (money-weighted metrics, ADR-0034 accepted), #572
   (benchmark comparison). The rest of the dump is design work that must
   not be implemented piecemeal: that is how the current drift happened.
3. **One reviewer, one batch** (ADR-0026/0036 unchanged): the sprint runs as
   one epic batch; risk-tier items are attention labels inside it.

## Sprint 4 — "The design gets an owner"

Run in a fresh session per lane start; epic branch
`agent/claude/sprint-4-design-foundation`.

### Lane A — Gate: UX design session (the sprint's centerpiece)

The UX designer role (Sally) runs a design session against the live surface
and produces the **living design-language spec** (refresh and promote the
2026-06-12 DESIGN.md + EXPERIENCE.md), covering at minimum:

- loading affordances: skeleton states, the count-up pattern (cosmetic
  count-up to the final value with a visible "still counting" state — owner
  decision 2026-08-05), progressive sunburst fill, replacement of "Lädt …"
  text and bare dot placeholders;
- navigation and controls: assets-view tabs (visual language shared with the
  icon menu), period selector, date picker;
- hint prose → ⓘ tooltips per UX-DR11 (performance-chart footnotes, income
  EUR-hub note), "chart as table" kept but de-emphasized as the
  accessibility fallback;
- contra-account value-setting UI, snapshots view makeover;
- income view set (owner-scoped in the triage: bars per month/quarter/year,
  accumulated-per-month chart, closed trades, deposits/withdrawals view;
  per-instrument breakdown is an open design question, not a requirement;
  explicit labeling of what "income" aggregates — dividends vs. interest);
- tax view as an MCP-first review/overview surface (owner decision
  2026-08-05, no document intake);
- overview "needs attention" card: naming its view + plan context.

Output: the spec is the decision gate for the implementation stories.
E14/E11 stories are cut from it and land as issues after the owner confirms
the spec — implementation of those stories is **Sprint 5**, not this sprint.

### Lane B — #560 mobile income chart defect

Standalone fix, TDD first, ships early in the batch. The owner re-reported
this from live use; a core view partially unusable on mobile does not wait
for the design spec.

### Lane C — #568 money-weighted metrics (capacity permitting)

ADR-0034 is accepted, so the gate is already done. Net invested capital,
wealth multiple, and IRR/MWR next to TTWROR also serve the owner's
"invested vs. withdrawn" ask from the dump. Risk-tier attention label
(money math): own commit group, dedicated verification pass on the metric
identities, exact `Decimal` expectations, explicit briefing callout.

### Explicitly not this sprint

- Implementing design-spec stories (Sprint 5, after the spec is confirmed).
- The "from data to information" insights direction — needs its product
  brief and a decision gate first (Hard Rule "no advanced reports" stands
  until deliberately amended). #572 stays queued in E5 behind #568.
- Active-plan-per-allocation semantics — E16/ADR-0027 decision gate.
- Anything from the parking lot (#340).

## Close-out duties (ADR-0026 step 5, unchanged)

Bookkeeping in the same pass as the merge: `sprint-status.yaml`, epics doc,
issue closes, retrospective section, CI green on the merge.
