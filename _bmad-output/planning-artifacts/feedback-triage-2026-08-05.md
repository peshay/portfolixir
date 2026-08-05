# Owner Feedback Triage — 2026-08-05

Source: an unstructured owner feedback dump from day-to-day use of the live
instance (a few sprints after the last full review). Raw observations were
delivered conversationally; this document is the PM triage. Real instance
data was not part of the feedback and none appears here.

Status: triaged; issue creation awaits owner confirmation of this triage
(see "Proposed next steps"). Nothing here is a committed scope decision.

---

## Part 1 — Working mode: how feedback reaches the backlog

The owner asked whether to report observations ad hoc ("kurzer Dienstweg")
or to batch them into a proper review when time allows.

**Recommendation: both channels, with distinct jobs.**

1. **Ad-hoc dumps are the default and are welcome unstructured.** Raw
   observations are most valuable fresh; the cost of structuring belongs to
   the agent, not the owner. Convention:
   - Owner drops observations at any time, in any form, any language, no
     sorting required — exactly like this session.
   - The PM agent triages into a dated
     `planning-artifacts/feedback-triage-YYYY-MM-DD.md` (this format),
     clusters, routes to existing epics/ADRs, and proposes issues.
   - The owner reviews only the triage (minutes, not hours) and confirms or
     corrects routing. Then thin issues are created per the issue-tracking
     convention (pointers to the authoritative spec, no duplicated
     acceptance criteria).
2. **The batched "proper review" stays, but as acceptance, not as
   collection.** ADR-0026 already prescribes a UAT persona walkthrough per
   epic batch and an owner behavior review at acceptance. That is where
   systematic, screen-by-screen evaluation belongs. Waiting to collect
   day-to-day observations until such a session loses signal for no gain.

Net effect: no observation waits for a review slot, and no review session
is spent on transcription.

## Part 2 — Triage of this dump

Five clusters, ordered by how I propose to treat them, not by how they were
reported.

### Cluster A — Bug: income view unusable on mobile

- On iPhone, the income ("Erträge") view cannot be scrolled horizontally;
  the charts are cut off and cannot be seen in full.
- Classification: **defect, not design polish** — a core view is partially
  unusable on mobile. Smallest scope of this dump, highest urgency.
- Routing: standalone fix candidate, does not need to wait for any design
  epic.

### Cluster B — Perceived performance and loading states

Recent work (ADR-0035, one pricing pass per read, #619) reduced server-side
cost. The dump shows the remaining problem is **perceived latency and how
in-progress computation is displayed**, which is a different problem than
the one #619 solved:

- Overview: noticeable navigation delay, then a literal "Lädt …" text
  flashes for a fraction of a second before the number appears.
- Assets view: first numbers arrive fast, but TTWROR and IRR show three
  plain dots for several seconds.
- Allocation & targets: numbers load slowly, again dots as placeholders.

Owner's stated preference: proper loading affordances everywhere
(skeletons/animation instead of placeholder text), fully dynamic loading,
the sunburst filling progressively as numbers arrive, and — ideal case — a
live counting-up number with an indicator that the value is not final yet.

PM assessment:

- Skeleton states, progressive/async loading, and a consistent "computing"
  affordance are a clear, bounded improvement: candidate for a dedicated
  **loading-states story bundle** (LiveView async assigns exist; the UX
  layer is what is missing).
- The live count-up of *real* intermediate values needs a design decision
  before anyone builds it: streaming true partial results is expensive and
  can suggest false precision, while a purely cosmetic count-up to the
  final value is cheap but is animation, not information. Options and the
  "not final yet" indicator belong in a UX design pass (Cluster C) before
  implementation.

### Cluster C — Design system and visual polish (routes to E14, #451)

A recurring theme: functional but visually careless UI. Named instances:

- Assets view: top tabs are plain text, while the burger menu has icons —
  no visual language connecting them.
- Performance chart: period selector and date picker are bare text fields.
- Hint/footnote texts dumped as plain prose under the chart (TTWROR
  explanation, date range, composition-as-of-today note) and on the income
  view (EUR-hub conversion note). These are exactly what UX-DR11 says
  belongs in on-demand ⓘ tooltips, not permanently in the sightline.
- The contra-account ("Verrechnungskonten") value-setting UI under the
  chart.
- Snapshots view: general makeover wanted.
- Owner explicitly asked to "bring in a designer".

Routing: this is **E14 (CSS consistency & design-system)** becoming real.
Proposal: a UX design session (UX designer agent) that walks the named
views, defines the visual language (tabs, pickers, hints/tooltips, loading
affordances from Cluster B), and produces a design spec E14 stories can be
cut from. Not piecemeal per-view fixes without a spec — that is how the
current inconsistency happened.

- Side note, "Daten als Tabelle anzeigen" under the chart: owner sees no
  purpose. It is (or should be) the accessibility fallback for chart data.
  Decision for the design pass: keep but visually de-emphasize, and make
  its purpose evident — not delete.

### Cluster D — Allocation plans: ambiguity and missing "active plan"

- The overview's "Braucht Aufmerksamkeit" card reports categories with
  target ("SOLL") deviations — but with multiple views/buckets and multiple
  plans per allocation, it does not say **which view and which plan** the
  warning refers to. The owner currently has an outdated and a current plan
  side by side in strategy allocation.
- Owner proposal: mark exactly one plan per allocation as the **active
  plan**; context labels on aggregate warnings.
- Routing: this is squarely the **E15 (view-bound SOLL plans, ADR-0020) /
  E16 (plan versions & depot snapshots, ADR-0027)** territory. "Active plan"
  is a semantic/data-model requirement, so it goes through the E16 decision
  gate (ADR-0027 sign-off), not into an opportunistic UI fix. The overview
  card naming its view+plan context is a smaller labeling story that can
  ship independently once wording is decided.

### Cluster E — Feature gaps needing discovery before scoping

1. **Income view options.** Today only the bars-per-year view exists.
   Portfolio Performance offers several income views; owner wants "all of
   them". Discovery question before scoping: which PP income views does the
   owner actually use (per month? accumulated? by security? by
   period-comparison?) — "all of PP" is not a story, it is a wish. Needs a
   short interview, then scoping.
2. **Tax view rethink.** Owner verdict: worst UI of all, and — more
   fundamentally — unclear *who* would ever maintain this data by hand.
   Suggested directions: (a) treat MCP/LLM as the primary write path and
   reduce the UI to reviewing/confirming recorded snapshots, or (b) intake
   of a document with automatic recognition. Assessment: (a) is mostly a
   repositioning of what E19 already built (the MCP surface exists;
   the UI becomes read/confirm-first) and can be handled as a UX/scope
   decision. (b) is new intake scope: ADR-0021 covers broker PDF
   transaction intake only; tax-statement document intake would need its
   own decision gate before anything is built. Neither direction starts
   without an owner decision.

## Part 3 — Proposed next steps (owner confirms, then execution)

1. **Now:** fix Cluster A (mobile income view) as a standalone defect
   story.
2. **Next:** UX design session covering Cluster B affordances + Cluster C
   views → design spec → cut E14/E11 stories from it.
3. **Decision gates:** active-plan semantics via ADR-0027 (E16); tax-view
   direction (MCP-first vs. document intake) as its own decision; count-up
   animation semantics inside the design session.
4. **Discovery:** short owner interview on which PP income views matter.
5. **Standing convention:** feedback dumps → dated triage file → owner
   confirms → thin issues. This document is the first instance.

Open questions for the owner are embedded above: income-view selection
(E.1), tax-view direction (E.2), and whether the count-up should stream
real partial values or animate to the final value (B).

---

## Round 2 — owner responses and pipeline check (2026-08-05, same day)

The owner answered the open questions and extended the working-mode
discussion. Decisions recorded here; the pipeline was checked for existing
coverage before routing anything.

### Working mode — confirmed and formalized as ADR-0038 (proposed)

The owner confirmed the continuous-intake mode and sharpened it: short
feedback goes directly to the PM agent, the PM checks whether the item is
already in the pipeline, and if not, does proper design thinking and
produces the epics/issues/ADRs needed for a clean implementation. The owner
also flagged that the per-epic UAT walkthrough assumed by ADR-0026 has not
happened in practice (one partial pass in ~3 sprints) and that the UX role
was expected to critique design, aesthetics, and UX simplicity on an
ongoing basis — which never got wired into the workflow, producing the
visual drift this dump reported.

Both points are drafted as **ADR-0038 (Proposed)**: continuous feedback
intake with PM triage, acceptance staying at the merge, the UX designer
role as standing design authority over a living design-language spec, and
a design-critic role added to the agentic review closing act. Awaiting
owner sign-off.

### Pipeline check results (dedup before creating anything)

- **Cluster A (mobile income view) is already tracked: #560** — "Income
  chart: bars overflow/unreadable on mobile (no scroll or responsive
  handling)". No new issue; the owner re-reporting it from live use is a
  priority signal. Recommendation: pull #560 into the next sprint as a
  standalone defect fix.
- **Two of the owner's "insights" examples are already tracked:** #568
  (money-weighted metrics: net invested capital, wealth multiple, IRR/MWR —
  ADR-0034 accepted, covers "how much do I put in vs. take out" and the
  deposits/"Ersparnis" angle) and #572 (benchmark comparison vs. selectable
  indices and inflation — covers "my gain vs. an MSCI World"). Both sit in
  E5 (analytics engine, priority "next").
- **No existing issue covers loading states/affordances** — new scope, goes
  into the design session below.
- #340 (parking lot: wealth-management vision) exists for the far-out ideas.

### Decisions from the owner

- **Count-up:** a cosmetic count-up animation to the final value is
  acceptable and wanted, provided it is visually evident that the number is
  still counting and not final. Anything beats staring at three dots with
  no sense of when the value will arrive. → Design detail for the design
  session; no streaming of real partial values required.
- **Tax view:** MCP/LLM is the primary write path; the UI is reduced to a
  visual review/overview surface. Document intake is rejected as too
  complicated — no decision gate needed, the direction is settled. UI
  rework rides the design session.
- **Design session (UX designer):** confirmed as overdue. Owner's diagnosis
  matches the triage: early one-off design input, then nobody formulating
  and holding a consistent design language, hence repeated drift while
  work stayed "just functional" with incomplete CSS foundations.

### Income view — scoping input from the owner (PP walkthrough)

What the owner actually uses/values in Portfolio Performance's income area:

- **Bar charts per month / quarter / year: keep, good.** The existing
  bars-per-year view points the right direction but is not enough.
- **Accumulated-per-month chart: wanted, "great as a chart".**
- **Per-instrument tables (month/quarter/year × instrument): too much;**
  even PP's tables are not readable. Open design question whether a clean
  visualization per instrument exists at all — for the design session, not
  a committed requirement.
- **Taxes and fees views: overview level is enough** for the owner; the
  full view matrix PP offers is not a priority ("someone will need it" is
  not scope).
- **Closed trades: valued, keep.**
- **Deposits/withdrawals ("Ersparnis" in PP): wanted** — external in/out
  flows are interesting numbers. Overlaps with #568's net invested capital;
  the view belongs to the same story family.
- Terminology note to resolve in the UI: PP distinguishes "Erträge" (all
  earnings: dividends + interest) from "Dividenden" (security dividends
  only) — the owner found this distinction unclear in PP itself. Our income
  view must label what it aggregates explicitly rather than inheriting the
  ambiguity.

### New product direction flagged — "from data to information"

The owner's broader point: collecting the numbers is table stakes; the
system should increasingly extract *information* — analyses sorted by
relevance to the user, visually presented, with raw numbers still
reachable. Examples beyond #568/#572: net effect of taxes and fees on
returns ("is this worth it"), what-if framings (cheaper broker, more
tax-efficient trading).

PM assessment: this is a product-direction statement, not a story. It
tenses against the standing Hard Rule "do not add advanced reports" and
partially against E10's "later" placement (planning & simulation), so it
needs a deliberate decision gate (product brief → PRD update → ADR if
accepted) rather than opportunistic scoping. What-if simulations
(broker switch, tax-optimized trading) additionally depend on data the
system does not hold (fee schedules) and border the advice boundary —
parked in #340 until the direction gate. #568 and #572 proceed regardless;
they are already gated and scoped.

### Updated next steps

1. **Now:** prioritize #560 (mobile income chart defect) into the next
   sprint.
2. **Now:** owner signs off (or amends) ADR-0038; AGENTS.md workflow
   section updates ride the acceptance.
3. **Next:** UX design session covering: design language refresh
   (DESIGN.md/EXPERIENCE.md as living spec), loading affordances incl. the
   count-up pattern, tabs/pickers/hints (UX-DR11 tooltips), contra-account
   UI, snapshots view, income view set (scoped above), tax view as
   review/overview surface. Stories for E14/E11 are cut from the resulting
   spec.
4. **Then:** product brief "from data to information" as the decision gate
   for the insights direction.
5. **Standing:** feedback dumps → dated triage → owner confirms → thin
   issues (per ADR-0038 once accepted).
