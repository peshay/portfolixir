# UX Design Pass — 2026-09-23, Sprint 15's user-visible items

Scope: **every** user-visible change Sprint 15 proposes, held against the
living design-language spec per
[ADR-0038](../../docs/decisions/0038-continuous-feedback-and-design-authority.html).
`DESIGN.md` and `EXPERIENCE.md` are the authority, and this document proposes
against them. It runs **on the planning PR, before the batch**, as the standing
rule of 2026-09-20 requires (AGENTS.md → "A UI change is mocked before it is
built").

Mockups: `design-language/mockups/ux-design-2026-09-23/`, one HTML board per
item with every variant, rendered to PNG at 1200 px (device scale 2) with
Playwright. The render reported no console error and no horizontal overflow
on any board. The boards link the real `priv/static/app.css`. The data is
the committed synthetic seed's names (`Nordic Timber Holdings AB`,
`Helios Solar Systems SE`) plus invented ones in the same style (`Meridian
Global Equity ETF`, `Kestrel Industrial Group NV`, a view called "Spekulativ").
**No real instrument, position, weight, threshold, account or rate appears.**
Every figure is made up for the board.

| Pick | Item | Board | Variants | Recommended |
|---|---|---|---|---|
| **F1** | The policy-rules surface (ADR-0049 §9, Lane A4) | `01-policy-rules-surface` | section on Wealth → Risk · seventh area tab · Risk section + Overview card | **A** |
| **F2** | Position-level SOLL entry (#481 rescoped, Lane D1) | `02-position-soll-entry` | positions inline in the SOLL table · a dialog per category | **A** |
| **F3** | Cross-currency settlement inputs (#395, Lane D2) | `03-settlement-inputs` | a fieldset shown when currencies differ · always-present optional fields | **A** |
| — | The active area tab at 390 px (#857) and one disclosure marker (#854) | `04-tab-row-and-disclosure` | none (before/after) | n/a |
| — | The row menu reachable by keyboard (#858) | `05-row-menu-focus` | none (before/after) | n/a |

**#850** (the column-picker convergence) already has its board: Sprint 14's
`ux-design-2026-09-20/03-column-picker`, pick **E3 = `.popover`**, written into
`DESIGN.md` → Inventory → Overlays on 2026-09-23. It is not redrawn: the pick
is made, and the design critic holds the build against that board.

**Items with no board.** None this sprint. Every Lane C item
changes what renders, including #858. A menu whose first item carries the
focus ring looks different from one whose kebab does, which is why it has a
before/after board and does not fall under the "no rendered difference"
exception.

---

## Part 0 — What governs this pass

Two of the three picks are **old debt, not new design**. F2 and F3 are both
surfaces the product's records assume exist and the code does not have (the
2026-09-23 triage §2). They are the same kind of finding as Sprint 14's D-2.
Their boards therefore start with a **before** that shows the dead end: the
Wealth page sends the operator to a page that has no field, and the booking
form returns an error that no field can satisfy. The variants come after it.

F1 is the only pick with real design freedom, and its governing constraint
comes from ADR-0049 §7: **the lens's generic thresholds and the operator's own
rules are two mechanisms, and the surface must never let them read as one.**

---

## Part 1 — F1: where the operator's rules live

**Variant A (recommended): a section "Eigene Regeln" at the top of Wealth →
Risk.** Findings sort breached first, then undetermined, then ok (ADR-0049 §9).
Each row shows the rule's name, its words (measure · subject · kind ·
severity), the measured value, the line, and the state. A `breached` state
carries the signed distance ("+2,4 Pp"). An `undetermined` state carries its
reason, for a refused metric "14 von 20 nötigen Beobachtungen", which is
ADR-0047's `required` rendered, not paraphrased. The lens's Top-N table below
is retitled **"allgemeine Schwellen, nicht deine Regeln"** so that the
same weight with two badges (the rule says breached at 10 %, the generic
threshold says "über 10 %") reads as two statements, not a contradiction.
Create, edit and retire use a native `<dialog>` (UX-DR9). The edit dialog
states that saving creates a new version and names what the old one was,
because ADR-0049 §4 is invisible otherwise, and an operator who thinks they
overwrote a cap will not look for its history.

**Variant B: a seventh area tab "Regeln".** More room, and a drift rule no
longer sits under a heading that says "Risiko". It costs a seventh tab in a
row whose active tab is already off-screen at 390 px (#857), and it separates
the finding from the figures it judges.

**Variant C: A plus an Overview card** listing only breached and undetermined
rules, beside "Fällig" (Sprint 13, D3-A). This is the most visible option: the
operator sees a breach without looking for it. The card can be added later
without undoing A, so it is a variant rather than the core. The Overview gains
a card per epic, and that growth deserves its own look.

**Why A.** The question a rule answers ("am I inside my limits?") is the
question the Risk tab exists for, and a finding is most legible next to the
number it reads. The "Risk vs. Allocation" parent problem B solves is real but
small: of v1's five measures, four are exposure figures and only `drift` is an
allocation figure. The rule's words name the measure, so a drift rule on the
Risk tab is not ambiguous.

**What the build must also do** (not a variant; ADR-0049 §9 and the spec):
the rules section is **scoped by the active view** like everything on the tab
(UX-DR26), the version list is reachable from the edit dialog, and a retired
rule stays readable behind a disclosure. Its anatomy goes into `DESIGN.md`
with the story.

---

## Part 2 — F2: position-level SOLL entry

**Before:** the SOLL table on the Classifications page takes category weights
and the cash target. Nothing else. The Wealth page's hint "align the position
targets and the category weight on the Classifications page" points at a page
with no such field.

**Variant A (recommended): positions inline, per category, behind a
disclosure.** Each category with assigned securities gets "Positionen (n)". It
opens by default where any position already carries a target. Position rows
are inputs in the **same form**, so there is one save, one live Σ and one
journaled write. The rule of ADR-0030 §2 becomes visible: once a position
carries a target, the category's input turns into a dashed read-only
"Σ Positionen". An empty position input means *no position target*, not zero,
and the story pins that distinction with a test, because the difference
changes the roll-up.

**Variant B: a dialog per category.** It keeps the table short, but it creates
two writes with two states, the main form's Σ is wrong until the dialog
closes, and no view ever shows all position targets at once. That last cost
is decisive: an all-positions view is the pivot #481 was written for.

**Why A.** It is the maintainer's own model (#481: "per-position SOLL summing
to 100 %, a pivot with per-category sums"), it uses the form the page already
has, and it needs no second save path.

---

## Part 3 — F3: cross-currency settlement in the booking form

**Before:** a buy whose security currency differs from the depot's cash
account fails with `settlement_fx_rate "is required for a cross-currency
settlement"`, and the form has no field that could satisfy it.

**Variant A (recommended): a fieldset "Abrechnung in <account currency>" that
appears when the currencies differ**, and is then required. Two fields,
settlement amount and rate, each derived from the other as the operator
types, prefilled from the stored hub rate at the booking date and marked as a
suggestion. One sentence states the owner's 2026-07-19 guard ("the cash amount
must equal the settlement amount, net of fees and taxes") so the risk-tier
validation Lane D2 adds never arrives as a surprise 422.

**Variant B: three always-present optional fields** under "Kosten und Notiz".
Simpler to build, but it adds three empty fields to nearly every booking, and
on the one booking that needs them they are collapsed. Today's error would
stay the first hint.

**Why A.** It shows the fields exactly when they are required, and the form
already derives the currency from the selected depot
(`data-role="derived-currency"`), so the condition is already computed.

---

## Part 4 — The two conformance boards

- **#857.** The active area tab is scrolled into view on mount, with no
  animation under `prefers-reduced-motion`. **The board found one thing the
  issue does not say:** scrolled to the end of the row, the D6 40 px right mask
  sits on the active tab itself. So the repair also drops the right mask when
  the row is at its end, and adds the left fade when it is not at its start.
  Otherwise the fix only moves the tab under the mask.
- **#854.** Keep the chevron icon, which rotates on open; drop the
  `::before` triangle. `DESIGN.md` → "Data as table — one disclosure" already
  names one chevron.
- **#858.** Opening the menu moves focus to the first item. ↑/↓ move, Home/End
  jump, Esc closes and returns focus to the kebab, Tab closes. This is the
  WAI-ARIA menu pattern `role="menu"` already promises.

---

## Part 5 — What the design critic holds the batch to

Each built surface against its board **and** against `DESIGN.md` /
`EXPERIENCE.md`:

- DE;
- one full pass at 390 px;
- light and dark;
- on `priv/demo/finding_surfaces_seed.exs`, extended by the stories with
  rules in every state (ok, breached, undetermined from a refused metric,
  undetermined from a missing target) and with position targets in at least
  one category.

The picked anatomy for F1, F2 and F3 is written into `DESIGN.md` by the story
that builds it. A UI item that lands without its board is a close-out
finding.
