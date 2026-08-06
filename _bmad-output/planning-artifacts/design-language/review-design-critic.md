# Design-critic review — the design-language spec against the complaints that caused it

Role: design critic (ADR-0038 step 3, first instance). Unusual object of review: not a
diff against the spec, but **the spec against the feedback that motivated it**.

Reviewed: `DESIGN.md` and `EXPERIENCE.md` (both `status: draft`, updated 2026-08-05) and
`.decision-log.md`, against `feedback-triage-2026-08-05.md` (both rounds),
`sprint-plan-2026-08-05.md` Lane A, and ADR-0038's Context.

Method: every complaint traced to the passage that answers it; every answer tested for
whether a reviewer holding only this spec and a diff could return a verdict; source
claims spot-checked in code (`app.css`, `portfolio_live.ex`, `app_shell.ex`,
`ledger/trade_matcher.ex`, `classifications/category.ex`, gettext catalogue).

Findings are numbered DC-n and routed at the end: **spec gap**, **build defect**, or
**process observation**.

Short version: the coverage is real and the diagnosis is better than the complaint that
prompted it — all four drift examples ADR-0038 names are answered with named components,
not preferences. The failures are concentrated in one place: **the surfaces the owner
asked to be redesigned (income, cash flow) are the ones the spec specifies least**, and
the session's own most consequential decision (per-instrument income) never reached the
document at all.

---

## 1. Complaint-by-complaint traceability

Verdict column: **answered** (a builder could implement it and a reviewer could reject a
deviation), **partial** (direction is right, the buildable detail is missing),
**acknowledged only**, **missing**.

### Cluster A — mobile income view (#560)

| Complaint | Where answered | Verdict |
|---|---|---|
| Income view cannot be scrolled horizontally on iPhone; charts cut off | DR15 (EXPERIENCE:297-299), DESIGN "Every wide block owns its scroller" (369-379), Responsive table row (EXPERIENCE:213) | **answered** — the strongest rule in the document |

The spec correctly refuses to treat this as a per-view bug: `.workspace-page {
overflow-x: clip }` is named as the deliberate cause, and the rule is stated as a
property of every wide block, not of the income view. "A wide block without its own
scroller is a review reject regardless of whether it currently overflows" is the model
sentence for the rest of the spec — falsifiable, no judgement call.

### Cluster B — perceived performance and loading

| Complaint | Where answered | Verdict |
|---|---|---|
| "Lädt …" text flashes before the number | DR20, value-slot pending state; "six different loading verb strings ... are drift" (EXPERIENCE:161) | **answered** |
| TTWROR/IRR show three plain dots for seconds | value-slot four states; the `…`/`—` collision is named at `portfolio_live.ex:715-780` | **answered** |
| Allocation numbers load slowly, dots again | same | **answered** |
| Skeletons instead of placeholder text | pending → last-known-value dimmed, typographic skeleton fallback sized to the value footprint | **answered**, and better than the ask |
| Count-up with a visible "not final" indicator | Settling state, accent bar, count-up hook approved (DESIGN:526) | **answered** — the mechanism falsification (`counter()` renders `250000`) is the single best piece of work in the session |
| Sunburst filling progressively as numbers arrive | DESIGN:461, EXPERIENCE:152 | **partial — and dishonest in one word**, see DC-7 |
| **Noticeable navigation delay before anything appears** | "Cold load — server-rendered first paint: layout arrives complete" (EXPERIENCE:160); "Income, Tax and Snapshots ... *when they move to async* they inherit this pattern" (161) | **partial**, see DC-6 |

The last row matters more than its size suggests. The owner's first sentence in Cluster B
is about a *delay*, not about a placeholder. The spec specifies the placeholder
beautifully and leaves the delay to a subordinate clause with a conditional verb.

### Cluster C — design system and visual polish

| Complaint | Where answered | Verdict |
|---|---|---|
| Top tabs plain text while the burger menu has icons — no shared visual language | DR16 / `{components.selected-nav}`: one icon set app-wide, sidebar = pill + marker ("where am I"), tabs = icon + label + underline ("which facet"), second-level tabs smaller and iconless | **answered in structure, blocked in fact** — the icon set is never enumerated (DC-8) |
| Period selector and date picker are bare text fields | `{components.period-control}` + DR19 native controls + ISO dates | **answered** for appearance; **partial** for vocabulary (DC-9) |
| Hint prose under charts (TTWROR, date range, composition-as-of) | DR11 amendment: "every candidate paragraph resolves to exactly one of: a tooltip, a data note, a basis line, or deletion" | **answered** — testable as written |
| Income EUR-hub conversion note | same rule, but the income surface is never walked paragraph by paragraph | **partial** |
| Contra-account value-setting UI under the chart | Component Patterns "Cash accounts", scoped to **Accounts & depots** | **partial / mislocated** (DC-4) |
| Snapshots makeover | "The comparison is the surface" (EXPERIENCE:134) | **answered** |
| "Bring in a designer" | the whole document | **answered** |
| "Daten als Tabelle" — sees no purpose | DR10 amended: one disclosure, one label, one styling, plus a purpose line; sunburst and securities detail chart must gain it | **answered** |

### Cluster D — allocation plan ambiguity

| Complaint | Where answered | Verdict |
|---|---|---|
| "Braucht Aufmerksamkeit" does not say which view and which plan | DR2 rewrite + "Needs attention" card row: a basis line naming view and plan, and explicit statement where several plans exist | **answered**, and correctly designed to work before E16/ADR-0027 lands and improve after |

### Cluster E — feature gaps

| Complaint | Where answered | Verdict |
|---|---|---|
| Bars per month / quarter / year | one clause, EXPERIENCE:79 | **acknowledged only** (DC-3) |
| Accumulated-per-month chart | same clause | **acknowledged only** — no chart type, no spec |
| Per-instrument breakdown (open design question) | **nowhere in either spine** | **missing** (DC-1) |
| Taxes/fees at overview level | Costs tab, "overview level only — no per-transaction cost ledger" | **answered** as a boundary; unspecified as a surface |
| Closed trades | Realized gains tab | **partial** — no mention that `TradeMatcher` closed trades already ship on securities detail (DC-10) |
| Deposits & withdrawals | own tab | **partial** — overlaps #568, which is Lane C of *this* sprint (DC-15) |
| Erträge vs Dividenden terminology | answered "by structure, not by a better label" (EXPERIENCE:77) | **partial** — the German labels are never chosen, and "Income" is msgstr "Erträge" today (DC-5) |
| Tax view: worst UI, unclear who maintains it | Tax surface row + `.tax-budget` inventory entry: budget dashboard + check list, MCP-first, forms behind disclosure, five prose paragraphs → tooltips | **answered** |

### The four drift examples ADR-0038 names

| ADR-0038 Context | Spec answer | Verdict |
|---|---|---|
| Text-only tabs beside an icon menu | DR16 | **answered** (icon set pending) |
| Bare text-field date pickers | DR19 + period control | **answered** |
| Explanatory prose under charts violating UX-DR11 | DR11 amendment | **answered** |
| Inconsistent loading placeholders | DR20 + value-slot | **answered** |

All four land. This is the part of the mandate the session executed well, and it should
be said plainly before the criticism below.

---

## 2. Does the spec prevent recurrence, or only describe the mess?

Test applied per drift family: *given only this spec and a diff, can a reviewer return a
clear verdict?*

| Family | Reviewer verdict possible? | Note |
|---|---|---|
| Selected states | **Yes** | "Every control in the app maps to exactly one" of three named classes; a fourth is a reject. Enumerable against a diff. |
| Data notes | **Yes for the taxonomy, no for the render** | Three severities, colour AND icon AND word. Blocked on DC-8: the icons do not exist, so "does this note comply" cannot be answered today. |
| Tabs | **Structurally yes, visually no** | Idiom is decided; the shared icon vocabulary it depends on is not written down anywhere. |
| Period controls | **Appearance yes, tokens no** | DC-9: the subset decision is delegated to each alignment story. |
| Loading affordances | **Yes** | Four states, four appearances, explicit "pending must not look like not-computable", reduced-motion behaviour stated per state. Best-specified area in the document. |
| Chart-as-table | **Yes** | One control, one label, one styling, purpose line, mandatory on every chart surface. The "one label" is [OPEN] on wording only. |
| Native controls | **Yes** | Enumerated control list, ISO dates in input, checkbox anatomy. |
| Scroll containers | **Yes** | DR15, and the only rule in the document that could be machine-gated cheaply. |
| Width reservation | **Yes, with a testable tolerance** | "tolerance: 0px — no measurable shift when selection moves". Exemplary. |
| Chart-as-a-whole (three hand-rolled SVGs) | **Yes** | "New chart work uses the shared component". |

Where the spec states a preference rather than a testable rule — the most valuable
findings, with proposed testable versions:

**DC-6 (spec gap). First paint is described, not required.**
> "Cold load | Overview, Wealth | Server-rendered first paint: layout arrives complete."
> "Income, Tax and Snapshots load synchronously in `mount/3` and have no pending state at
> all; **when they move to async** they inherit this pattern rather than inventing one."

That is a description of a hoped-for future plus a conditional. The owner's complaint was
a delay before anything renders. Verified: `portfolio_live.ex` already uses
`start_async/3` for `:overview`, `:allocation`, `:performance`; income, tax and snapshots
do not. Proposed testable rule:

> **No `mount/3` blocks first paint on a priced or aggregated read.** Every surface
> renders its complete layout with value slots in the pending state, and every computed
> value arrives through `assign_async`/`start_async`. A LiveView whose `mount/3` performs
> a valuation, aggregation or pricing read is a review reject.

Without this, the loading vocabulary can be implemented perfectly on three surfaces and
the owner will still wait on the other three.

**DC-7 (spec gap). The sunburst sweep promises arrival that does not exist.**
> "Progressive chart fill — sequential sweep ... **Segments appear clockwise as their
> values arrive.** ... the shape moves during the build, so the chart briefly shows
> proportions it does not have."

Verified: the allocation lands as a single `start_async(:allocation, ...)` result
(`portfolio_live.ex:363`); `Allocation.for_portfolio/3` computes the whole tree in one
pass. Segments cannot arrive individually. What will actually be built is a **cosmetic
reveal after all values are known** — the exact analogue of the count-up ruling.

This matters beyond wording, because the spec applies a strict honesty standard to digits
and waives it for geometry two paragraphs later. DR20: "a number on screen during
settling is never a truthful intermediate result, and must be visually evident as
not-yet-final." Then the sunburst is permitted to "briefly show proportions it does not
have" with no corresponding not-yet-final cue. Proposed testable version:

> The sunburst reveal is **cosmetic**, drawn from the complete result, like the count-up.
> While the reveal runs, the chart carries the same not-yet-final indication as a settling
> value slot, and the legend does not render until the geometry is complete.

The owner accepted a cost ("the shape moves") on the understanding that it buys real
progressive feedback. It does not. He should be told, and the sweep still probably wins
on merit — it just wins as polish, under the rule the spec already wrote for polish.

**DC-9 (spec gap). The period vocabulary is delegated to the stories.**
> "[OPEN] The per-surface token subsets are not yet decided; each alignment story declares
> its surface's subset in the story and the answer lands back here."

N independent stories each choosing a subset, with the spec updated afterwards, is the
drift mechanism this document exists to end — it is how four range patterns and two token
sets arose in the first place. Proposed: the spec names the subset per surface now (there
are five time-series surfaces; it is a ten-minute decision), and a story that needs a
token outside its declared subset is a spec change, not a story detail.

**DC-8 (spec gap). Two new rules rest on an inventory that does not exist.** DR16
mandates "one icon set app-wide ... a glyph may not carry a second meaning"; DR17 requires
"icon + the word" per severity; DESIGN:218 and 430 both carry "[OPEN] ... the set is
undecided". No icon inventory exists in either spine. Until the glyphs are enumerated,
neither rule is reviewable and the data-note component cannot be built. This is a
designer's decision, not an owner's — it should not have left the session open.

---

## 3. What was decided that should not have been, and not decided that should have

### DC-1 (spec gap, most serious). The per-instrument income decision never reached the spec

The decision log records it as decided:
> "2026-08-05 — **Per-instrument income: I2, stacked bars with an aggregated remainder.**
> Largest six instruments individually, everything else as one 'Sonstige' segment."

Neither spine contains the strings "per-instrument", "stacked", "Sonstige", "top-6" or
"remainder". Grep-verified across both files.

The log itself names this exact failure mode two sections earlier, as the reason ADR-0038
exists:
> "**A decided design was never recorded and never built:** session C decided the dashboard
> shows data quality as ONE line ... No ADR, no issue comment ... Precisely the failure
> mode ADR-0038 exists to stop."

The session diagnosed the disease and reproduced it inside the same document. This is the
finding I would put first in the reviewer briefing.

### DC-2 (spec gap). The one-accent rule and I2 are not compatible, and the spec papers over it

The log flagged the constraint honestly and then left it unresolved:
> "Carries a constraint to verify: the one-accent-at-a-time rule means seven
> distinguishable segments must be built from tints and shades of the active accent plus a
> neutral. ... whether it holds at the readability limit is a DESIGN.md question, flagged
> not assumed."

DESIGN.md answers it nowhere. Worse, three positions on categorical colour now coexist and
none references the others:

1. **DESIGN.md, stated:** "[ASSUMPTION] The existing token set is treated as closed; no new
   hues are introduced beyond the tokens above." Contrast commitments cover only
   "meaningful graphics ≥ 3:1 against `{colors.chart-surface}`" — a segment-to-surface
   floor, never a segment-to-segment floor.
2. **The build, verified:** category colour is a free-form user-chosen hex
   (`classifications/category.ex:15,20` — `~r/^#[0-9a-fA-F]{6}$/`), rendered directly into
   the sunburst (`portfolio_live.ex:1804`, `fill={segment.color}`). The allocation visuals
   have carried arbitrary non-token hues since before this session. The "closed token set"
   assumption is already false on the app's most colourful surface, and the spec's
   Allocation-visuals inventory row does not mention it.
3. **The session decision:** seven segments from tints of one accent plus a neutral.

On the arithmetic: with a total white-to-accent range around 5:1, six intermediate steps
land near 1.3:1 between neighbours. Adjacent stacked segments at that separation are not
distinguishable, and DR7 (colour independence, binding) would in any case forbid hue as
the sole channel for seven categories. **I2 as decided is not buildable under the spec's
own colour rules.** Saying "the mockup attempts it" is not a resolution.

My recommendation, plainly, for the owner to accept or overrule: **drop hue as the
segment channel for per-instrument income.** Six-plus-remainder is a small-multiples or
sorted-column problem, not a stacked-bar problem — the sparkline-column candidate (I1) or
the instrument filter solve it without touching the identity system. If stacked bars are
kept, then the spec needs a real categorical ramp, that is a change to the brand system,
and it is an owner decision, not a designer one.

Either way the spec must gain a **categorical colour section** governing sunburst, donut,
drift swatches and any multi-series chart, with a stated segment-to-segment minimum and a
stated cap on how many hue-distinguished categories are permitted before the encoding
changes. Today that section does not exist, and the built surface fills the vacuum with
user hex.

### DC-13 (authority). The Cash-flow restructure is an IA amendment taken on designer authority

Is it specification or scope creep? **Content: legitimate.** Every one of the four facets
traces to an explicit owner statement in Round 2 (closed trades keep, deposits/withdrawals
wanted, taxes/fees overview level, income bars keep). The reasoning is also the best in
the session — three of the five analyses genuinely are not income, and answering the
terminology complaint with structure rather than a better label is the right instinct.

**Vehicle: wrong.** Restructuring the Wealth tab set and introducing a second tab level is
an information-architecture change. The built set lives in `app_shell.ex` `wealth_tabs/1`
under ADR-0022's task-oriented IA, and ADR-0024 governs what earns a navigation entry. The
spec cites ADR-0024 in support but never says which ADR it amends, and no decision gate
was opened. ADR-0026 step 1 requires a signed-off decision before a batch works a feature
tree; ADR-0038 gives the designer authority over the *design language*, not over the
route/navigation model.

**Honesty about data: partially there, imprecise.** EXPERIENCE:79 is the right instinct —
"they must not ship as empty shells without their read" — but the supporting claim is
wrong in detail (DC-10), and the IA table marks three rows "**specified, unbuilt**" while
the tab-set line above declares the new set flatly as "decided 2026-08-05, replaces the
built set". A reader cutting Sprint 5 stories sees a decided five-tab bar with four
sub-tabs; only one of the five has a route and only one sub-tab has a read.

Recommended handling: keep the structure, restate it as **proposed**, route it through a
short ADR amendment for owner sign-off, and mark the three facets "specified, not
scheduled" so no Sprint 5 story can cut a shell. Also note the spec cannot currently say
where the Cash-flow parent lives — DR4 defers exactly that to "an owner ruling on the
Cash-flow parent" (EXPERIENCE:266) while the tab set that depends on it is presented as
settled.

### DC-14 (authority). DR2 reverses an explicit owner confirmation, inside one session

The log, first:
> "**UX-DR2** — the 'four confirmed metric cards' never shipped as written ... Either the
> rule follows the build or the build follows the rule; it cannot stay as is. **Flagged for
> the owner, not silently rewritten.**"

The log, later the same day:
> "2026-08-05 — **UX-DR2 follows the build.** The rule is rewritten to the Overview as it
> exists ... The contradiction has stood since June; this ends it."

EXPERIENCE.md now presents this as ruled (`DR2 ... rewritten`), and DESIGN.md retires the
hero component downstream of it. The four metric cards were an explicit owner
confirmation on 2026-06-13 ("Dashboard card set confirmed as drafted"). Reversing a
recorded owner decision is an owner act. I agree with the outcome — a rule contradicted by
the build for two months is not a rule — but the file should say the owner is being asked
to ratify it, not that it is settled. Same applies to the retired hero and to the
now-stale `key-dashboard.html`.

### DC-15 (coordination). Deposits & withdrawals overlaps #568, which is running in this sprint

The triage says so explicitly: "Overlaps with #568's net invested capital; the view belongs
to the same story family." Sprint plan Lane C is #568, capacity permitting, in this batch.
Neither spine mentions #568 or #572. The spec therefore specifies a new home for numbers
another lane of the same sprint is placing on the Wealth KPI band. One of the two has to
give, and the spec is the document that should say which.

### DC-16 (authority, inverted). Deferrals to the owner that a designer should have closed

- The three data-note icons (DESIGN:218, 430; EXPERIENCE:315) — blocks DR17 entirely.
- The disclosure label wording (DESIGN:229, "[OPEN] one wording app-wide") — copy is the
  design role's own output.
- Per-surface period token subsets (DC-9).
- Note-level tone: "[ASSUMPTION] Neutral = `{colors.text-muted}` on `{colors.bg-muted}`;
  the log does not fix the note-level tone" — the spine may simply decide this.

Correctly routed to the owner, by contrast: the bilingual domain-label ruling
(`Gesamt (total)`, Freistellungsauftrag, Verlustverrechnungstopf, SOLL/IST). That is
product voice and the spec is right to hold it open.

### DC-17 (scope boundary). The "from data to information" gate is never named in the spec

The sprint plan puts the insights direction behind a product brief and reaffirms the Hard
Rule "no advanced reports". The spec introduces a Costs facet and a Realized-gains facet
without ever citing that boundary. As specified — "overview level only, no per-transaction
cost ledger" — I read both as inside the owner's confirmed scope and *not* advanced
reports. But the spec is the document a Sprint 5 story is cut from, and it should carry
the boundary sentence so a reviewer can reject the story that quietly grows a
cost-attribution report.

### DC-4 (spec gap). The contra-account complaint is answered on the wrong surface

The complaint names the UI "under the chart". Verified: the global set-balance form is on
Wealth — Holdings, `portfolio_live.ex:1510`, `<form phx-submit="set_balance"
class="inline-form balance-form">` with an account `<select>` at 1513 — i.e. the account
picker the spec's fix is designed to eliminate.

The spec's answer is filed in the Component Patterns row scoped to **Accounts & depots**
(EXPERIENCE:133) — a different surface (`/portfolios`) — while the IA row for Wealth —
Holdings still lists "cash accounts" as part of that surface (EXPERIENCE:53), and
DESIGN:483 states the rule with no surface at all ("a cash balance is set from the account
row, not from a global form"). Three passages, no ruling on the question a builder has to
answer: **does the Wealth cash-accounts section keep an edit affordance, become read-only,
or disappear?** Unanswerable from the spec today.

### DC-5 (spec gap). The terminology fix is monolingual

"The terminology problem is therefore answered by **structure**, not by a better label."
That only holds if the labels exist in both shipped locales. Verified: today's msgstr for
Income is exactly the contested word — `priv/gettext/de/LC_MESSAGES/default.po:2280`,
`msgstr "Erträge"`. The spec never names German labels for Cash flow, Income, Realized
gains, Deposits & withdrawals or Costs. If "Income" keeps rendering as "Erträge" beneath a
parent whose German name is undecided, the owner's complaint survives the restructure.
This also collides with the open bilingual-label ruling, and both should be closed
together.

### DC-3 (spec gap). The income surface has no controls specified

Owner scope: bars per **month / quarter / year**, plus an **accumulated-per-month**
series. The spec's only period control is a *range* vocabulary — `1M 3M 6M YTD 1Y 3Y 5Y
Max` — and the section states "a surface never invents a token outside the set and never
reorders it". Month/quarter/year is a **granularity** choice, not a range. The spec
therefore forbids the obvious control and supplies no alternative, and specifies no chart
type for the accumulated series.

This is the single most likely place for the next drift: a builder cutting the income
story has an explicit prohibition, no sanctioned control, and a deadline. Proposed: define
a **granularity control** as a second instance of `{components.selected-segment}` with its
own token set (Month · Quarter · Year), state that granularity and range are independent
controls, and name the accumulated series a cumulative area on the shared chart component.

### DC-10 (spec gap, sizing). "Only Income has data today" is not accurate

Verified: `Ledger.TradeMatcher` produces `closed_trades` (FIFO round-trips with weighted
average cost basis), it is called from `Ledger` (`ledger.ex:170, 955`), and closed trades
already render on the securities detail pane (`securities_live.ex:1064-1081`). The ledger
also carries `deposit`, `removal`, `fee` and `tax` kinds (`transaction.ex:11-17`). So:
Realized gains needs a **portfolio-level aggregation over an existing matcher**, not a new
computation; Costs needs a grouped sum over existing kinds; Deposits & withdrawals overlaps
work already gated by ADR-0034 (#568).

The difference between "unbuilt" and "aggregate an existing read" is the difference between
an epic and a story, and Sprint 5 estimates come off this page. The spec should also note
that closed trades already have a home, so the Realized-gains tab is a second view of them
rather than their first.

---

## Routing

**Spec gaps — must be closed in the spec (blocking or near-blocking for Sprint 5):**
DC-1 (per-instrument decision absent), DC-2 (categorical colour / one-accent conflict),
DC-3 (income granularity + accumulated series), DC-4 (which surface owns setting a
balance), DC-5 (German labels), DC-6 (async first-paint rule), DC-7 (sunburst sweep is
cosmetic), DC-8 (icon inventory), DC-9 (period token subsets), DC-10 (data-availability
accuracy), DC-12 (Cash-flow navigation parent, self-flagged at DR4).

Additionally self-flagged by the spec and correctly so: the **contrast table still lives in
an archived session folder** (DESIGN:322) while DR8 is binding. The spec is right that a
binding table nothing maintains is fragile, and right to refuse to retype it from memory.
It must close before `status: draft` lifts. **(DC-11)**

**Authority / scope — need an owner act, not a designer edit:**
DC-13 (Cash-flow IA restructure → ADR amendment + sign-off), DC-14 (DR2 reversal → ask for
ratification rather than presenting as settled), DC-15 (#568 overlap → one home for the
numbers), DC-17 (state the "no advanced reports" boundary in the spec), and the DC-2
recommendation if stacked bars are retained.

**Build defects — route to issues, not into the spec text.** The spec has found a genuinely
valuable list: the ungated `.section-skeleton` shimmer, `nav_current?/2` missing
`/snapshots`, `SecurityChart`'s hard-coded English empty state, four `gettext`/`ngettext`
plural bugs, accent-coloured negative KPI values, light-only `warning-soft`, three
referenced-but-undefined tokens, six hard-coded violets, five `outline: none`
substitutions, the allocation header boxes, the broken checkbox stack, the `MM/DD/YYYY`
date input, the viewport-height sidebar, the double-meaning funnel icon, and the ~1100px
gap between a data-quality problem and its remedy. These belong in issues per the
sprint-plan decision "defects ship now, drift ships from the spec".

**Structural note on where they are recorded (DC-18, process):** they currently live
*inside* the spec, in sections like "Violations in the built UI". A living spec that also
serves as a defect register ages badly — once fixed, each entry is a paragraph describing a
state of the world that no longer exists, and the next reader cannot tell target state from
historical complaint. Recommend the spec keep the **rule** and a pointer to the issue, and
let the issue carry the file-and-line evidence.

**Process observations:**

- **DC-19.** The design critique underpinning much of this refresh comes from six
  **light-mode** screenshots with **no loading state captured**, as the log itself admits:
  "Not verifiable from this set: loading placeholders ... and dark-theme behaviour." The
  spec's largest new area (loading) and its full dark token set are therefore specified
  without observation. The first design-critic pass on a Sprint 5 diff needs dark-theme and
  loading-state captures, or it will hold the build against unvalidated assumptions.
- **DC-20.** `mockups/key-dashboard.html` is declared stale in DESIGN.md but still sits in
  `mockups/` beside the living spec. A stale artifact in the canonical folder re-creates
  "newest thing wins", which is the drift the permanent-home decision was meant to end.
  Retire or re-render it; the same applies to `.working/` candidates now that picks are
  made.
- **DC-21.** No machine gate is proposed. `project-context.md` requires gates to land as
  dedicated stories, which the log correctly notes — but DR15 is the cheapest, highest-value
  gate available (a wide block without an `overflow-x` container), and DR14 already has a
  precedent in `test/invariants/css_spacing_scale_test.exs`. One gate story in Sprint 5
  would convert the spec's best rule from review discipline into a test.
- **DC-22.** Nothing in the spec traces back to the triage clusters. The check performed in
  section 1 above is not reproducible without redoing it by hand. A short coverage table in
  the spec (complaint → rule) would let the next design critic verify recurrence in
  minutes.

---

## Verdict

**Is this spec fit to be the authority ADR-0038 designates? Yes, conditionally — and it is
already far more of an authority than what it replaces.** It names one solution per
recurring job for nine of the ten drift families; it converts three owner complaints
(scrollers, width reservation, pending-vs-not-computable) into rules with zero-tolerance,
falsifiable phrasing; it corrects a mechanism assumption (`counter()` cannot format money)
that would otherwise have been discovered mid-implementation; and it absorbs UX-DR1..14
into the document that ADR-0038 actually points reviewers at, which closes a governance
hole 33 files were depending on. A design critic given this spec and a Sprint 5 diff could
return real verdicts on selected states, prose fallback, native controls, scroll
containers, chart-as-table, loading vocabulary and width reservation. That is the job
ADR-0038 created, and the spec can support it today.

The conditions are three, and they are not cosmetic. First, **the session's own most
contested decision never landed in the document** (DC-1), and the constraint it was
flagged against is unresolved and, on my reading, unsatisfiable as decided (DC-2) — the
spec must gain a categorical-colour section, and per-instrument income should probably drop
hue as its channel. Second, **the Cash-flow restructure is an IA amendment wearing a design
spec's clothes** (DC-13): good reasoning, wrong vehicle, and it needs an owner act before
stories are cut from it. Third, **the surfaces the owner complained about most are the ones
specified least** — income has no granularity control (DC-3), the cash-balance fix is filed
on the wrong surface (DC-4), the terminology fix is monolingual (DC-5), and the icon
vocabulary two new rules depend on does not exist (DC-8).

**Is it fit to cut Sprint 5 stories from? Partly, and the split is clean.** Cuttable today:
DR15 scrollers, DR16 selected-state unification, DR18 width reservation, DR19 native
controls, DR11 prose-to-tooltip conversion, DR10 chart-as-table, DR20 loading vocabulary
(with the stored-previous-value consequence correctly flagged as state work, not CSS), the
Tax surface rework, and the Snapshots comparison. Blocked until the conditions close: the
whole income/cash-flow family (DC-1, DC-2, DC-3, DC-5, DC-10, DC-13), anything requiring
the icon set (DC-8, and therefore DR17's render), and the period-control alignment stories
until their token subsets are decided centrally rather than story by story (DC-9).

One closing observation, offered as the design critic's core judgement rather than as a
finding. ADR-0038's diagnosis is that drift happened because no role was looking and no
spec existed to look against. This session proves the diagnosis by reproducing the disease
under observation: it documented, in its own log, a design decided in July that was never
recorded and never built — and then decided per-instrument income and did not record it.
The lesson for the workflow is that a decision log is not a spec, and a session is not
finished when the decisions are made. The close-out act for a design session should be the
same shape as ADR-0026's bookkeeping close-out for a batch: **every logged decision is
traced into the spec, or it did not happen.**
