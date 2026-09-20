# UX Design Pass — 2026-09-20, Sprint 14's five user-visible items

Scope: **every** user-visible change Sprint 14 proposes. Held against the
living design-language spec per
[ADR-0038](../../docs/decisions/0038-continuous-feedback-and-design-authority.html);
`DESIGN.md` and `EXPERIENCE.md` are the authority, this document proposes
against them.

Mockups: `design-language/mockups/ux-design-2026-09-20/` — one HTML board per
item with every variant, rendered to PNG at 1200 px. They link the real
`priv/static/app.css`, so what they show are the shipped tokens, not an
approximation. Data is the committed synthetic seed's (`Nordic Timber Holdings
AB`, `Helios Solar Systems SE`) plus two further invented names in the same
style; **no real instrument, position, weight or threshold appears** — every
figure on these boards is made up for the board.

**This pass runs before the batch opens, not at branch opening.** That is the
owner's instruction of 2026-09-20 and it is now a standing rule rather than
this sprint's arrangement: *a UI change gets a mockup, with options, before it
is built.* The rule is written into `AGENTS.md` on the same PR — see Part 6.

| # | Item | Mockup | Variants | Recommended |
|---|---|---|---|---|
| **E1** | The risk surface (ADR-0047 §9, Lane A4) | `01-wealth-risk-surface` | sixth area tab · facet on Allocation · metrics-only strip | **A** |
| **E2** | The bucket cell's `+N` overflow chip (#842) | `02-bucket-overflow-chip` | inline expand · row-menu section | **A** |
| **E3** | The column-picker fork (#835) | `03-column-picker` | `.popover` · `<details>` | **`.popover`** |
| **E4** | The detail pane's tab row (#837) | `05-detail-tablist` | keep `tablist` + roving tabindex · drop the role | **A** |
| — | `.num` and the kebab's focus ring (#833, #834) | `04-num-and-focus` | none — before/after | n/a |

---

## Part 0 — The finding that governs the rest: one item is design, four are the spec already having an answer

Sprint 13's pass opened on a budget, because two lanes each wanted to spend the
same scarce thing. This batch's shape is different and worth naming before the
variants, because it changes what the reader should look for:

> **E1 is the only item with real design freedom. E2, E3, E4, #833 and #834
> are places where `DESIGN.md` already says what the answer is and the built
> UI does not follow.**

That is not a reason to skip their boards — it is the reason they have one. A
conformance repair has a *before*, and the before is precisely what a reviewer
cannot reconstruct from a diff: `DESIGN.md:947` has named the `.num` defect in
words for two sprints and it kept shipping, because words about alignment do
not show a reader two columns of proportional digits. **Board 04 is the whole
argument for the standing rule in Part 6.**

**The one budget question returns, one level up.** Sprint 13 rationed the
*detail pane's* tab row at nine. E1's recommended variant spends a tab on the
**area** row — Wealth's sixth. That row is a different object with a different
budget, and the board argues it rather than assuming it: `.area-tabs` carries
`overflow-x: auto`, `scroll-snap-type: x proximity`, the 40 px right-edge mask
and `scrollbar-width: none`, with `flex: none` and `scroll-snap-align: start`
on `.area-tab`, all shipped since #790 and #702. A sixth tab is a list entry in
a row built to overflow. UX-DR22 is satisfied by construction — the row
scrolls, it does not wrap and does not collapse.

The cost is real and stated: every tab past the fifth is found by scrolling a
row most readers do not know scrolls. Variant B exists precisely to price that
against the alternative cost of a second navigation level.

---

## Part 1 — E1: the surface ADR-0047 §9 assumed already existed

**What the record fixes and what it turns out not to.** ADR-0047 §9 says the
portfolio figures land "on the Wealth risk surface". Read against the code on
2026-09-20, `Portfolixir.Portfolios.Risk` is referenced by
`risk_controller.ex`, the route and `mix portfolixir.derived.measure` — and by
nothing in `lib/portfolixir_web/live/**`. **There is no such surface.** The
concentration lens of FR-8/FR-9/FR-10 has been agent-only since it shipped,
which predates the two-way coverage rule, so nothing is in breach; it is the
older debt that rule exists to stop accumulating, sitting under a placement
sentence that assumed it had been paid.

So the question is not *how the four new figures are laid out*. It is **what
surface they land on, and whether the lens comes with them.** Three answers,
and they differ in size by a factor of several.

### Variant A — a sixth Wealth area tab, "Risiko" *(recommended)*

The lens and the new figures on one page: the four metrics as a row with window
and observation count, the Top-N table with its threshold column, the HHI with
its band on a scale that shows where 1.842 sits between 1.500 and 2.500, the
asset-class cap violations, and the correlation matrix behind a disclosure
rather than open by default (the precedent is #807's year matrix behind
"Realisiert je Periode").

**Why it is the recommendation, in three checkable claims.**

1. **The tab row is built for it** — Part 0, with the declarations named.
2. **The figures answer one question.** "How concentrated am I" and "how much
   does this portfolio move" are one screen's worth of thought. Splitting them
   puts a volatility figure on a page that cannot show what it is the
   volatility *of*.
3. **It is the only variant that reduces the debt rather than moving it.** B
   and C both end the sprint with something still agent-only.

**The threshold column is the lens's own vocabulary, not a verdict.** The board
renders `ok`/`warn`/`hard` as *"unter 25 %"*, *"über 7 %"*, *"über 10 %"* —
naming the threshold that was crossed rather than pronouncing on it. ADR-0047
§7 forbids a signal, rating or action in the *metric* payload; a configured cap
and the fact that a weight is above it are arithmetic and were already there.
Nothing on this surface recommends a trade, and ADR-0023's display-only
rebalancing hints are **not** built here.

**What the board could not settle and the batch must check:** the four-column
metric row at 390 px. It reflows to one column by the same rule the KPI band
uses, but "Risikoadjustierte Rendite" is a long label above a short number, and
the refused-state cell ("nicht berechenbar" with its `required` count) is the
longest of the four. The design critic checks it on a real render at 390 px
before the lane closes.

### Variant B — a facet on "Aufteilung & Ziele"

The same content behind the segmented control the Cash-flow tab has used since
#672 — the app's one facet mechanism, and the one `DESIGN.md` names ("Facet
navigation uses the segmented control, not a second tab level"). It spends no
area tab.

The price is honest and is why it is not the recommendation: risk then lives
under a heading that speaks of *targets*, and a reader looking for
concentration has to know that a second control exists inside that tab. A
facet is right when the facets are siblings of one subject — income, realised,
flows and costs are all cash flow. Allocation, targets and risk are not one
subject in the same way; risk is what the allocation *produces*, not another
view of it.

**If the owner picks B, nothing else in the plan changes** — the content,
the API surface and the sequencing are identical. Only the container moves.

### Variant C — the four figures only, on "Bestände"

A metric strip under the existing KPI band. Builds nothing new and formally
discharges ADR-0047 §9. What it does not do: Top-N, HHI and the caps stay
without a screen — the debt, now with four more figures on top of it and with
a two-way deadline attached to the new half only.

C is a legitimate outcome and the board draws it honestly rather than as a
straw man. It is the right pick if the owner's judgement is that the
concentration lens is genuinely agent-only work.

---

## Part 2 — E2: the `+N` chip still carries its meaning in a `title` (#842)

`bucket-cell.scope` (added by #806) says the scope sub-line is "readable
without interacting" and that it *replaces* the "Both" micro-label whose
meaning lived in a `title`. Three lines away in the same cell, the `+N`
overflow chip still carries one. Variant A of #806 removed one title-carried
meaning and left the other.

- **A *(recommended)*** — the chip becomes a real `<button>` with
  `aria-expanded` **as a string** (#836's fix applies here too), the 2px accent
  focus ring, the 44 px coarse-pointer floor, and a press that expands the cell
  in place. Reversible by the same control. No `title` survives.
- **B** — the row menu gains a "Buckets" section. Cheaper, no new table state.
  The price: two interactions to answer "which two?", and the row menu is where
  *actions* live — a list to read is a guest there.

---

## Part 3 — E3: two column-picker treatments, and the spec names one (#835)

`DESIGN.md` → Inventory → Overlays names `.popover` as the treatment for column
pickers and filters, which `PortfolixirWeb.Securities.ColumnPicker` implements:
`role="dialog"`, `aria-label`, a `.popover-head` heading, grouped
`<fieldset>`/`<legend>`. The transaction history's `#tx-column-picker` and
Wealth Positions' `#holdings-column-picker` are both a `<details>` with a flat
checkbox list.

**Recommendation: `.popover` wins and the spec is not amended to match the
drift.** Under ADR-0038 the living spec is the authority the design-critic
review holds work against; amending it because two surfaces diverged inverts
that relationship. The grouping is the difference that matters — at fourteen
columns a flat list is a search task.

**The board is the decision; the convergence is Sprint 15's build** (the plan's
D-4). Putting the two side by side is what makes "which one wins" a five-second
question instead of a paragraph, and it is why this item gets a board even
though nothing is built for it this sprint.

---

## Part 4 — E4: the detail pane's tab row (#837)

The row renders `role="tablist"` with nine `<button role="tab">` children, no
roving `tabindex`, no arrow-key handling, and `aria-controls` pointing at panel
ids that exist only while their tab is active. A screen-reader user is told
"tab 1 of 9" and then Arrow Right does nothing.

- **A *(recommended)*** — keep the role, complete the pattern: `tabindex="0"`
  on the selected tab and `-1` on the rest, Left/Right plus Home/End, the 2px
  accent focus ring, and `aria-controls` **only on the selected tab** — which
  is the half of the finding that is invalid markup today rather than missing
  keyboard support.
- **B** — drop the role; nine ordinary buttons, nothing invalid, nine tab
  stops. Cheaper, and it loses the "2 of 9" announcement and the fact that the
  nine switch *one* region.

**Why A.** The detail pane *is* a tab widget: it switches panels and changes no
route. The area tabs above it are `<a href>` inside a `<nav>` with
`aria-current="page"` and correctly carry no tablist role. The two are
different objects, which is exactly why one has the role and the other must
not; B would make the app's two tab rows disagree about what a tab row is.

---

## Part 5 — The two conformance repairs, as before/after (#833, #834)

No variant choice — `DESIGN.md` already specifies both. Board 04 exists so the
change is **seen** before it is built, which is the point Part 0 makes.

- **#833** — `app.css` carries 15 `.num` rules, every one descendant-scoped, so
  a plain `.data-table` renders `class="num"` with nothing behind it and
  `thead th { text-align: left }` is never overridden. `DESIGN.md:947` names
  the defect and its cause. One generic rule changes every table in the app,
  which is why it was out of Sprint 13's scope and is deliberately in this one.
  The board shows the same three rows under both regimes; the second column is
  the argument.
- **#834** — `.row-actions__kebab` and `.row-context-menu__item` both set
  `outline: none` with a background change as the substitute, which the Do's
  and Don'ts names as the "don't" and lists these two rules by name. The
  compliant example is `.filter-sheet-toggle:focus-visible` from Sprint 13.
  Separately the kebab's hit area is well under the 44 px floor, and Sprint 13
  put it on three more phone-reachable surfaces.

---

## Part 6 — The standing rule this pass makes explicit

Owner instruction, 2026-09-20: **when a change touches the UI, a mockup comes
first, and it carries comparison options.**

Written into `AGENTS.md` on the Sprint 14 planning PR (the plan's D-11) rather
than left as this sprint's arrangement, because the failure it prevents is a
recurring one and habits depend on someone remembering. What the rule says, in
short — the normative text lives in `AGENTS.md`:

1. Any story that changes rendered output gets a board **before** the code.
2. The board shows **at least two options** where there is a choice, and a
   **before/after** where there is not — a repair is still a UI change.
3. The recommendation is the default pick; a comment naming another option
   changes it; the story writes the picked anatomy into `DESIGN.md`.
4. Boards link the real `app.css` and use synthetic data only.

**What this pass is evidence for.** Three of the five items here are drift that
`DESIGN.md` had already described in words and that shipped anyway — twice, in
#833's case, into tables added by the very batch whose review found it. A
sentence in a spec is read by whoever is looking for it. A board is read by
whoever opens the PR.

---

## Part 7 — What this pass deliberately does not design

| Item | Why not |
|---|---|
| #836 (`aria-pressed` / `aria-expanded` as bare booleans) | Nothing renders differently — the attribute is either absent or valueless. A board would show two identical pictures. The fix is `to_string(…)` at six sites. |
| #844 (ADR front matter) | Not UI. |
| Lane A1/A2/A3, Lane B, Lane D | No rendered output: an engine, a payload field, a meta-test, three controller fixes, a query parameter and a tool description. |
| The correlation matrix's own layout | Drawn on board 01 only as a closed disclosure. If E1-A or E1-B is picked, the matrix's anatomy is the one thing the batch may design in-flight, against `{components.data-table}`; it is a table of pairs with an overlap count and has no variant worth boarding. |
| `.popover` convergence for the two `<details>` pickers | Decided here, built in Sprint 15 (plan D-4). The board is the decision record. |

## Part 8 — What the stories owe `DESIGN.md`

- **E1** — the picked container named, plus a `wealth-risk` (or facet) anatomy:
  the metric row's reflow, the threshold column's vocabulary, the HHI scale,
  the empty state for an unconfigured cap set, and the disclosure for the
  matrix.
- **E2** — `bucket-cell` amended: the overflow control's two states, and the
  sentence that the cell carries no `title`.
- **E3** — Inventory → Overlays states which level takes which treatment, and
  the convergence issue is filed with the picked treatment named.
- **E4** — the D6 tab-row paragraph gains the roving-tabindex keyboard contract
  and the `aria-controls` rule.
- **#833 / #834** — `DESIGN.md:947`'s defect note is replaced by the shipped
  rule, and the Do's and Don'ts entry stops listing these two rules as
  outstanding.
