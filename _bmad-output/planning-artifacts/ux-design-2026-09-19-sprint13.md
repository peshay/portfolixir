# UX Design Pass — 2026-09-19, the three surfaces Sprint 13 leaves unspecified

Scope: the **three** human surfaces Sprint 13 introduces that its two decision
records *place* but do not *design*. Everything else on the batch is already
specified — Part 4 says which and why it is not reopened here. Held against
the living design-language spec per
[ADR-0038](../../docs/decisions/0038-continuous-feedback-and-design-authority.html);
`DESIGN.md` and `EXPERIENCE.md` are the authority, this document proposes
against them.

Mockups: `design-language/mockups/ux-design-2026-09-19/` — one HTML board per
surface with every variant, rendered to PNG at 1200 px. They link the real
`priv/static/app.css`, so what they show are the shipped tokens, not an
approximation. Data is the committed synthetic seed's (`Nordic Timber Holdings
AB`, `Helios Solar Systems SE`) plus two further invented names in the same
style; no real instrument appears.

**Picked by the owner on 2026-09-19: D1-A, D2-B, D3-A.** Recorded here, on the
planning PR, and in the plan's D-8; the stories write each picked anatomy into
`DESIGN.md`.

| Surface | Mockup | Variants | Recommended | **Picked** |
|---|---|---|---|---|
| D1 — per-security metrics (ADR-0047, Lane A3) | `01-security-metrics` | strip + chart overlay · strip only · own tab | A | **A** |
| D2 — events on the detail pane (ADR-0048, Lane E3) | `02-detail-events` | in Research · own tab · on Overview | A | **B** |
| D3 — upcoming events across the catalog (ADR-0048 §5.2) | `03-upcoming-surface` | Overview card · + Securities facet · own route | A | **A** |

**The picked set spends exactly one tab, and that is within the budget Part 0
sets.** D1-A puts the metrics where the chart already is and spends none; D2-B
spends the one available tab on "Termine", which is the use Part 2 named for
it. The combination Part 0 advises against — D1-C together with D2-B, two tabs
— did not occur.

---

## Part 0 — The finding that governs the rest: the detail pane has a tab budget, and two lanes want to spend it

The securities detail pane carries **eight tabs** in a panel whose default
width is roughly 360 px. Sprint 13 adds two things to that pane — the metrics
block (Lane A3) and the events list (Lane E3) — and the obvious design for
each of them, taken on its own, is a new tab. Taken together that is a tenth
tab in the narrowest tab row in the application, in the same sprint in which
**#817 is repairing that row precisely because it already overflows.**

Neither story would notice. Each would look reasonable in its own review.
That is what a design pass is for, and it is the reason this document opens
with a budget rather than a layout:

> **At most one new tab on the detail pane this sprint, and the recommended
> set spends none.**

**Outcome (2026-09-19): the owner spent the one tab, on D2-B.** The budget did
its job — it made the choice explicit and singular instead of letting two
stories each take one. **A consequence rides with it: #817 stops being a
nicety.** The tab row now carries nine tabs in that ~360 px panel, so the D6
treatment #817 is applying — scroll-snap, the right-edge fade, no wrapping —
is what keeps the ninth tab reachable. #817 and Lane E3 should land in that
order.

UX-DR22 is not violated by a ninth tab — the rule is explicit that a
within-area tab row *scrolls*, never collapses and never wraps, and scrolling
is what it does. The cost is not a rule breach; it is that every tab after the
fifth is found by scrolling a row most readers do not know scrolls. That is a
price worth paying once, for the surface a reader goes looking for by name,
and not twice. Each variant below is argued on its own merits; the budget is
what makes the *combination* coherent.

---

## Part 1 — D1: the per-security metrics block

**What the record fixes and what it leaves open.** ADR-0047 §9 places the
figures "on the securities detail's chart tab, beside the price history it
already renders". That is a placement sentence. It does not say how six metric
families with windows and observation counts are laid out, what period they
follow, or — the question nobody has asked — **whether the moving averages are
drawn on the chart or only printed as numbers.**

That last one is the decision worth making deliberately, because it is the
difference between a figure that means something and a figure that does not.
"SMA 200 = 96,80 SEK" tells a reader nothing on its own. Its meaning is the
*distance* to the current price (a number) and the *crossing* with the shorter
average (a picture). A design that prints the value and omits both has shipped
a row of digits.

### Variant A — strip under the chart, moving averages drawn in it *(recommended · **PICKED**)*

The chart tab keeps its toolbar and price series; SMA-50 and SMA-200 render as
the second and third series — dashed and dotted, the UX-DR7 colour-independence
treatment the benchmark overlay already established — and the six metrics sit
underneath in a three-by-two grid of quiet bordered cells, the same idiom
#804's overview grid uses.

Three properties make it the recommendation:

1. **One period control, not two.** The metrics follow the range buttons the
   chart tab already owns. A second period vocabulary on one surface is
   exactly the drift UX-DR16's per-surface subsets exist to prevent.
2. **The `{components.data-as-table}` disclosure (UX-DR10) now covers three
   series instead of one** — price, SMA-50, SMA-200 per trading day — which is
   the accessibility alternative doing more work for the same control, not a
   second disclosure.
3. **Every cell carries its own window and observation count**, which is what
   ADR-0047 §6 requires the payload to provide: the shared basis (series,
   currency, gap rule, annualization) sits once in the basis line below, the
   part that varies sits on the cell.

Cost, stated plainly: three series in a chart that is ~330 px wide inside the
pane. The mockup shows it is legible; a design critic should re-check it at
390 px on a real render before the story closes.

### Variant B — strip only, the chart stays one series

Same grid, no overlay; the moving averages appear as value plus distance. It
is cheaper, the chart stays calm, and at panel width that is a real argument.
What it gives up is the crossing: a reader who wants to know whether the
short average has crossed the long one must compare two numbers and remember
which was which last week.

### Variant C — a ninth tab, "Kennzahlen"

Drawn in the mockup only to price it. It spends the tab budget Part 0 names,
and it separates the figures from the series they describe, which is the one
thing that makes them readable. Not recommended under any pick of D2.

### What all three must get right — the state that decides the block

A young security is the case this block lives or dies on. With 41 stored
closes, SMA-50 and SMA-200 are not computable, momentum has a 3M value and no
6M or 12M, and the "52-week" extremes are extremes of a series that is nine
weeks old. ADR-0047 §5 makes this renderable rather than mysterious: the
payload carries `insufficient_data: true` **and the observation count**, so the
cell can say *"braucht 50 Kurse, hat 41"* instead of a dash.

Two rules for that state, both from findings already on the record:

- A not-computable cell uses `{components.value-slot}`'s not-computable
  appearance — smaller and muted — and **never** value weight. The Sprint 12
  closing act found exactly that regression on the re-composed KPI band.
- **A computable value inside a partly-computable cell keeps full weight.**
  Momentum with a 3M figure and two missing windows renders the 3M figure as a
  figure. (The first draft of the mockup got this wrong and dimmed the whole
  cell; it is fixed there, and it is stated here because it is the easy
  mistake.)

---

## Part 2 — D2: events on the securities detail pane

ADR-0048's Consequences place the per-security list "on the securities detail
pane" and §7's shape note says the research timeline's form. Where exactly is
open.

### Variant A — a "Termine" section inside the existing Research tab *(recommended, **not picked**)*

The Research tab answers *what do I know about this security*. A date the
operator or the agent recorded is knowledge of the same kind, and the record
already makes them relatives rather than neighbours: ADR-0048 §6 **reuses
ADR-0044's four-value `source_quality` vocabulary** rather than inventing a
second scale. Same provenance, same scale, same row shape
(`.research-entry__facts`), same create affordance.

So the tab becomes *what I know and what is coming*, with two headed sections
above the research log: **Termine**, then **These**, then
**Forschungsprotokoll**. It spends no tab, it puts the unconfirmed-and-overdue
row next to the thesis it might invalidate, and it reuses shipped CSS.

The honest cost: the Research tab now holds two kinds of thing, and its label
says one of them. If that bothers the owner more than a scrolled tab row does,
B is the answer and the document says so rather than defending A to the end.

### Variant B — a ninth tab, "Termine" *(**PICKED**, owner 2026-09-19)*

Cleanest separation of concepts; costs the tab budget. Legitimate under
UX-DR22. **If the owner wants exactly one new tab this sprint, this is the one
to spend it on** — the events list is the thing a reader goes looking for by
name, while the metrics are found where the chart already is. That is the
pick, and it is the use the budget was being kept for.

What the pick changes, concretely:

- `detail_tabs/0` in `securities_live.ex` gains an `events` entry, and
  `@tabs` with it; the Research tab keeps exactly what it has today.
- **#817 becomes load-bearing rather than tidy** — nine tabs in a ~360 px
  panel means the D6 scroll-snap and edge fade are what make the last tab
  reachable at all. Land #817 before Lane E3.
- The events row shape still reuses the research timeline's
  (`.research-entry__facts`) and ADR-0044's source-quality vocabulary; only
  the container changes. Nothing in the row design is discarded by the pick.
- `DESIGN.md` gains the tab itself in the D2 anatomy (Part 6), not only the
  row.

### Variant C — a block on the Overview tab, beside thesis and note

Fits #804's reading surface — *what is this, how does it stand, what do I think*
gains *what is coming* — and is the shortest path to a date. Two costs: the
overview already carries six figures, a chart, a basis line and two cards, and
under 900 px the cards stack, so a fourth block pushes everything down; and the
events list is the only one of the three that **grows**, which is the wrong
property for a card on a summary tab.

---

## Part 3 — D3: upcoming events across the whole catalog

This is the only genuinely new *screen* in the batch, and the one ADR-0048's
Consequences already name as the half that may slip. It is also the surface
where a binding rule does most of the deciding.

**The governing constraint.** `EXPERIENCE.md` → Information Architecture
carries ADR-0024 as binding: *navigation reflects user tasks, not the storage
model — sidebar = tasks, entities = attributes; new entities do not get
sidebar entries by default.* A security event is an entity hanging off a
security. The precedent is one document down: Cash flow became a **tab under
Wealth** rather than a sidebar entry, because "a second entry would make Cash
flow compete with its own parent".

### Variant A — a "Fällig" attention card on the Overview *(recommended · **PICKED**)*

UX-DR2 makes the Overview the analysis home that carries "Off target" and data
quality — the surface that answers *what needs attention today*. An upcoming
date is that, and the near-miss the agent reported is precisely a date nobody
saw. The card joins the existing attention column: a horizon control
(14 / 30 / 90 days), the due entries with security, kind, date and timing
qualifier, each row linking to that security's detail pane, and a basis line.

The clause that carries the whole decision: **the default scope is the entire
catalog.** A row for a security with no position is marked *"ohne Bestand"* —
present and labelled, never filtered away. That is ADR-0048 §2 rendered, and it
is the difference between this card and the agent's own holdings-derived
calendar.

No new route, no new sidebar entry, no ADR-0024 conflict, and it is small
enough that it will not be the thing that slips.

### Variant B — additionally, a facet under Securities (`/securities?tab=events`)

The card's "Alle anzeigen" then leads somewhere: a real list surface with
filters for kind, horizon and held-only, plus the two reads that otherwise have
an endpoint and no surface — unconfirmed-and-past, and not-checked-in-N-days
(ADR-0048 §5.3 and §5.4).

It costs new structure: `/securities` has **no** second-level tab row today,
and this introduces one. In exchange the sidebar's Securities entry lights
correctly (UX-DR4) and the catalog is the honest scope.

**Recommendation: A now, B when the card outgrows itself** — and say that in
the plan rather than discovering it. A alone leaves §5.3 and §5.4 as
agent-only reads; that is allowed by the coverage rule for one batch, and the
close-out records the deadline rather than letting it drift.

### Variant C — a dedicated `/events` route with a sidebar entry

Drawn and rejected. It is the first idea anybody has and the only one that
breaks a binding rule. Changing that rule is an ADR-0024 amendment, which is a
decision and not a design — so if the owner wants it, it comes back as an
amendment, not as a pick here.

---

## Part 4 — What this pass deliberately does not design

Six of the nine user-visible items in Sprint 13 are **already specified**, and
reopening them would be the pass inventing work:

| Issue | Why it needs nothing |
|---|---|
| #806 | Mockup and target in the 2026-09-12 review; **variant A picked by the owner on 2026-09-14** |
| #807 | Mockup and target in the review (C10); the reconciliation decision is signed by Sprint 13's D-3 |
| #808 | Mockup and target in the review (C11) |
| #816 | Reuses #800's shipped filter sheet as it stands — the issue names the functions and the CSS block |
| #817 | Copies five declarations from `.area-tabs`; `DESIGN.md` → D6 *is* the specification |
| #814 | Reuses #732's column picker, whose anatomy is in `DESIGN.md` |

Nor does it design Lane A2's portfolio-scope metrics: D-7 moved them to
Sprint 14, and designing a surface a sprint before it is built is how a spec
gets ahead of its build — the finding Sprint 12 was cut to fix.

---

## Part 5 — How the picks are made

Same mechanism as the 2026-09-12 review, adopted as Sprint 12's D-2: **each
variant list leads with the recommendation, and a comment naming another
letter changes the pick; no comment by the time the lane opens means the
recommendation ships.** The picks are recorded on the Sprint 13 planning PR and
the story writes the picked anatomy into `DESIGN.md` → Components, so the
spine — not this document — carries the decision afterwards.

Three picks: **D1**, **D2**, **D3**. One dependency worth stating: picking
**D1-C and D2-B together** spends two tabs and Part 0 advises against it; every
other combination is coherent.

**Received 2026-09-19 (owner, in session): D1-A, D2-B, D3-A.** The silence
clause did not have to fire. One pick is off the recommendation — D2-B, the
dedicated "Termine" tab — and it is the alternative Part 2 named as the
legitimate use of the single available tab, so the budget holds. Every section
above carries its pick, and each surface's obligations to `DESIGN.md` follow
in Part 6.

## Part 6 — What the stories owe `DESIGN.md`

Whichever letters are picked, the lane that builds a surface writes its
anatomy into `DESIGN.md` → Components in the same commit group, as
Sprint 12's eight picks did. Specifically:

- **D1** — the metric cell (label, value, window-and-observations sub-line),
  the not-computable and partly-computable appearances, and, under A, the
  SMA series' dash pattern in the UX-DR7 swatch table.
- **D2** — **the "Termine" tab itself** (its place in `detail_tabs/0`, and the
  D6 treatment the now-nine-wide row depends on), plus the event row (date
  with its relative distance, kind, timing pill, checked-at, source line), the
  four timing-qualifier appearances, and the unconfirmed-and-past treatment.
- **D3** — the "Fällig" card's anatomy, the horizon control as a UX-DR16
  class-2 period control, and the *"ohne Bestand"* marker.

And the closing act verifies all of it under Sprint 13's D-5 conditions: DE, a
full pass at 390 px, light and dark, on `priv/demo/finding_surfaces_seed.exs`.
The one thing a mockup cannot settle is Variant D1-A's three series inside a
360 px pane; that is a real-render check, and the design critic owns it.
