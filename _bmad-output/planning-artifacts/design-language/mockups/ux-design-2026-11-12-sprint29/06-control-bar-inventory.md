# Inventory for issue 1435: bars of labelled controls and open prose

Taken on 2026-11-12 by the Sprint 29 planning session, before any code,
for the plan and for board 06 (`06-control-bar.html`). Two sources:

- **Measured:** `capture-b-inventory.js` walked 28 page states of a review
  instance on the synthetic review seed (`priv/demo/finding_surfaces_seed.exs`)
  at 390 and 1200 px, read only, and wrote `inventory-b.json`. For every bar
  it records each row's first control and each group's first control (a
  group is a visible label and the controls after it), relative to the
  bar's left edge. The rule ("labelled controls start on one edge",
  `DESIGN.md`, amendment of 2026-11-08) holds when all of these agree within
  ±1 px once the bar has more than one row.
- **Read:** the templates under `lib/portfolixir_web/`, for the bars and
  paragraphs the seed does not render, and for the file and line of each.

Line numbers are those of the branch this planning PR starts from.

## 1. Bars of labelled controls

A *labelled* bar has a visible label beside a segmented control, a select, a
chip family or a field. "Spread" is the largest difference between the left
edges the rule compares.

| # | Bar | File:line | Page | Controls | 390 px | 1200 px | Shared component? |
|---|---|---|---|---|---|---|---|
| 1 | The stacked chart's bar | `live/portfolio/stacked_chart.ex:95` | Vermögen · Bestände, Wert (EUR) | 2 segmented, 1 select | holds: 3 rows, all at 100 px (A) | holds: one row | It *is* the rule's implementation (Sprint 28 S2), but not shared: markup in `StackedChart.bar/1`, CSS `.stack-bar*` (`priv/static/app.css` from 6406) |
| 2 | „Nach dem Verkauf“, Vergleich | `live/sale_hindsight_section.ex:322` | Cashflow · Trades (and a security's Trades tab) | 1 segmented, then a field („Fester Zins % p. a.“ + input + Anwenden) or a select (hidden label) | **breaks** in the rate mode: segmented 0, field 113 px; holds in the security mode (label above, B by accident) | holds: one row | no |
| 3 | Wertpapiere, the chip row | `live/securities_live.ex:4855` (families `:4867`, `components/changed_since.ex:87`) | Wertpapiere, every tab | 6 chip families (2 without a visible label) and „Weitere Filter“ | not shown (the filter sheet, row 4) | **breaks**: 3 rows, group edges 18, 18, 364, 854 px; „Währung“ ends row 1, its chips start row 2 | no |
| 4 | Wertpapiere, the filter sheet | `live/securities_live.ex:4863` | Wertpapiere, phone | the same families, each under its name | holds: B, every family at 0 px | — | no (holds by construction) |
| 5 | Transaktionen, the chip row | `live/transaction_management_live.ex:1735` | Transaktionen | 3 chip families (Konto, Typ, Geändert seit) | not shown (the filter sheet, row 6) | **breaks**: 5 rows, edges 52, 0, 0, 33, 0 px; „Geändert seit“ ends a row, its chips start the next | no |
| 6 | Transaktionen, the filter sheet | `live/transaction_management_live.ex:1744` | Transaktionen, phone | the same families | holds: B, all at 0 px | — | no |
| 7 | Journal, the chips | `live/journal_live.ex:239` | Journal | 2 chip families (Akteur, Vorgang) | **breaks**: 4 rows, edges 58, 0, 70, 0 px | holds: one row | no |
| 8 | Journal, the form | `live/journal_live.ex:284` | Journal | select (label hidden), field „Seit“, checkbox | **breaks**: 0, 29, 0 px | holds: one row | no |
| 9 | Prognosen, author and model | `live/predictions_live.ex:182` | Vermögen · Prognosen | 2 chip families (Autor, Modell) | not rendered on the seed (no prediction); the same flow as row 7, so it breaks wherever it wraps | not rendered | no |
| 10 | Allokation, the drift filter | `live/portfolio_live.ex:2766` | Vermögen · Allokation | 1 chip family („Abweichend um“) | not rendered on the seed (`has_plan` false for the shown tree); one family, so it breaks only if its chips wrap under the label | not rendered | no |

**Headline:** 10 labelled bars. 8 render on the seed; of those, **5 break**
the rule (rows 2, 3, 5, 7, 8: two at 390 px only, one in a mode at 390 px,
two at 1200 px only) and 3 hold (rows 1, 4, 6). The 2 the seed does not
render (rows 9, 10) are built as the same wrapping flow and are expected to
break where they wrap; the walk needs a seed state for each (a prediction
with a model, a plan on the shown tree). **None of the 10 uses a shared
component**, because none exists yet.

### Named in the issue, but not labelled bars

The issue lists `income_live.ex`, `portfolio_live.ex` and `tax_live.ex`
among the bars to migrate. Their controls carry **no visible label**: an
`aria-label` or a `.visually-hidden` label only. A bar without a visible
label cannot offset a control behind its label, and the walk measured
each at a shared edge.

| Bar | File:line | Controls | Measured |
|---|---|---|---|
| Cashflow facets | `live/income_live.ex:297` | 1 segmented (`aria-label`) | one control, no bar |
| Performance: series, period, custom range | `live/portfolio_live.ex:2103` | 2 segmented, 1 disclosure (`aria-label`) | 390 px: 3 rows, all at 0 px; 1200 px: one row |
| Allocation: view and tree | `live/portfolio_live.ex:2518` | 1 segmented, 1 select (`.visually-hidden` label) | one row at both widths |
| Tax: taxpayer and year | `live/tax_live.ex:636` | 2 segmented (`aria-label`) | one row at both widths |
| Prognosen: status | `live/predictions_live.ex:516` | 1 chip family, no label | not rendered on the seed |
| A security's chart options and toggles | `live/securities_live.ex:1196`, `:1303`, `:1913` | buttons and checkboxes | edges agree (±1 px) |
| Wertpapiere toolbar | `live/securities_live.ex:479` | search field, buttons | 390 px: field 41 px, buttons 10 px — the search icon's inset inside the field, not a label |

**Proposed:** these are registered exceptions of the static check (3) with
the reason "no visible label: not a labelled control", and the walk (2)
keeps measuring them, so one that gains a visible label falls under the
rule.

## 2. The component and its migration (proposal)

- **Extract** `.stack-bar__controls`, `.stack-bar__group`,
  `.stack-bar__label` and their container queries into a shared function
  component (for example `AppShell.control_bar/1` with a `:group` slot of
  `label` and control), CSS `.control-bar*`; the stacked chart's bar becomes
  its first caller with no visible change.
- **A chip family is one control** in the component: its chips wrap inside
  the control column, never under the label.
- **Every family names itself in the row**, as the phone sheet already does:
  „Bestand“ and „Datenqualität“ on Wertpapiere gain visible labels (board 06
  ③). Cost: two rows of height at 1200 px.
- **The journal's two bars become one** (board 06 ①); the kind select's
  label „Art“ becomes visible.
- **When the bar folds.** The stack bar folds at a measured width (760 px)
  through a container query, and a container query cannot read a variable.
  Proposed: the component takes the fold as one of a few named widths
  (`fold: 560 | 760 | 960 | :always`), each a class with its own container
  query; the chip rows of Wertpapiere and Transaktionen take `:always`, since
  their families never fit one line on the seed at 1200 px.
- **The browser walk (2)** reuses `capture-b-inventory.js`'s measure: per bar
  with more than one row, the first control of every row and of every group
  within ±1 px; at 390 and 1200 px; over the page states of the table above,
  with seed states added for rows 9 and 10.

## 3. Visible free paragraphs over one sentence

### Measured (the seed's page states, 54 distinct paragraphs)

Free paragraph: a visible `p`, `.hint`, `.detail-tab-hint` or
`.summary-basis` in `main`, outside a `details.metric-tooltip`, a data note,
a table, a list item, a dialog and the chart's tooltip. Sentences are
counted with abbreviations kept inside („z. B.“, „ggü.“, ordinals). A basis
line of facts joined by „·“ is one sentence.

Length: 43 of the 54 are one sentence by the splitter (44 with „ggü.“
kept inside); their words run 1 to 19, with one outlier at 37.

| Paragraph (`data-role`) | File:line | Page | Words | Sentences | Proposed |
|---|---|---|---|---|---|
| `positions-basis` | `live/portfolio_live.ex:3269` | Vermögen · Bestände | 26 | 2 | second sentence („Marktwert in EUR, wie ihn die Summe zählt.“) into the ⓘ |
| `stories-basis` | `live/securities/stories_tab.ex:56` | Wertpapier · Nachrichten | 20 | 2 | „Zeiten in UTC.“ as a „·“ fact |
| `chart-basis` | `live/securities_live.ex:1440` | Wertpapier · Diagramm | 11 | 2 | „Gespeicherte Kurse werden nie verändert …“ into the ⓘ |
| `predictions-basis` | `live/securities/predictions_tab.ex:49` | Wertpapier · Prognosen | 13 | 2 | the rule („Keine wird geändert oder gelöscht.“) into the ⓘ, as the Research tab does |
| `summary-basis` (transactions) | `live/transaction_management_live.ex:336` | Transaktionen | 37 | 1 | one sentence, but 37 words of method: its second clause into the ⓘ |
| `assignment-basis` | `live/buckets_live.ex:312` | Töpfe | 68 | 2 | a sentence and a list of account names: register (a list, not prose) |
| `cost-recovery` | `live/snapshots_live.ex:458` | Snapshots | 6 | 2 | a question and its answer as a figure's label: register |
| `empty-state` ×4 (`predictions-empty`, the stories tab's, the predictions tab's, the feeds tab's) | `live/predictions_live.ex:156`, `live/securities/stories_tab.ex:93`, `live/securities/predictions_tab.ex:85`, `live/news_live.ex:597` | several | 12–16 | 2 | register as a class: a state and where to act |
| `hs-legend` | `live/sale_hindsight_section.ex:504` | Cashflow · Trades | 21 | 1 | passes (the splitter must keep „ggü.“) |

### Read from the templates (states the seed does not show)

Two or more sentences in a free paragraph on a page (dialogs, flashes,
confirmations and form errors are left out: the walk opens none of them).

| File:line | Element | Words | Sentences |
|---|---|---|---|
| `live/securities/bond_strip.ex:50` | `p.detail-tab-hint` | 65 | 6 |
| `live/income_live.ex:112` | `span.muted` | 42 | 2 |
| `live/risk_live.ex:540` | `p.empty-state` | 35 | 2 |
| `live/imports_live.ex:941` | `p.form-help` | 33 | 2 |
| `live/transaction_management_live.ex:241` | `p.summary-basis` (changed since) | 31 | 2 |
| `live/predictions_live.ex:385` | `p.prediction-bands__why` | 30 | 2 |
| `live/securities_live.ex:663` | `p.summary-basis` (changed since) | 25 | 2 |
| `live/portfolio_live.ex:1681` | `p.hint` | 25 | 2 |
| `live/classifications_live.ex:370` | `p.hint` | 25 | 2 |
| `live/imports_live.ex:1072` | `p.muted` | 22 | 2 |
| `live/imports_live.ex:2924` | `span.mapping-basis` | 22 | 2 |
| `live/portfolio_live.ex:1754` | `article.stat--lead` | 20 | 2 |
| `live/transaction_management_live.ex:156` | `p` | 20 | 2 |
| `live/imports_live.ex:920` | `span.mapping-basis` | 18 | 2 |
| `live/news_live.ex:741` | `p.empty-state` | 18 | 2 |
| `live/portfolio_live.ex:2788` | `p.drift-filter-summary` | 17 | 2 |
| `live/imports_live.ex:644` | `p.muted` | 17 | 2 |
| `live/portfolio_accounts_live.ex:330` | `p.hint` | 15 | 2 |
| `live/dashboard_live.ex:314` | `small.recomputing-cue` | 14 | 2 |
| `live/portfolio_live.ex:2374`, `:2387`, `:2439` | `p.alert-error` | 4–10 | 2–3 |

A scan of all 3,884 gettext strings under `lib/portfolixir_web/` found 251
with more than one sentence: 121 are built in code (flashes, errors,
confirmations; a few reach a page through a function such as
`ledger_checks.ex` or `sale_hindsight_section.ex:547`), 37 sit in a data
note, 33 in an ⓘ, and the rest in dialogs or the rows above.

### The threshold, from the data

**One sentence of at most 25 words.** Every measured single sentence but one
is 19 words or fewer; 25 leaves room for a basis line's facts and catches
the 37-word one. "One sentence" alone would let a 37-word sentence of method
through, which is what I1 moves behind the ⓘ.

**Registered exceptions, each with its reason:**

1. `p.empty-state`: two sentences, the state and where to act (EXPERIENCE.md
   on empty states); at most 25 words each.
2. `p.alert-error` and `[role=alert]`: an error and its remedy.
3. A list of names (`assignment-basis`): data, not prose.
4. A figure's label (`cost-recovery`): a question and its answer.
5. `bond_strip.ex:50` until its own story moves the six sentences behind an
   ⓘ: the only paragraph past three sentences.

The remaining measured paragraphs over the threshold (`positions-basis`,
`stories-basis`, `chart-basis`, `predictions-basis`, the transactions'
`summary-basis`) are fixed rather than registered, each by moving its
method sentence into the section's ⓘ or into a „·“ fact; they are I1's
polish, one line each on the screens' polish lists. The template rows are
measured once the walk has a seed state for each, then fixed or registered
by the same rule.

## 4. Premises that do not hold

- **"The stacked chart's bar is its first user"** of a shared component:
  there is no shared component. The bar is `StackedChart.bar/1`
  (`live/portfolio/stacked_chart.ex:95`) with CSS of its own
  (`.stack-bar*`, `priv/static/app.css` from 6406). Extracting it is the
  first step of the migration.
- **`income_live.ex`, `portfolio_live.ex`, `tax_live.ex` as bars of labelled
  controls:** their controls have no visible label (table in §1). The
  labelled bars in `portfolio_live.ex` are the drift filter (`:2766`) and,
  through the stacked chart, the stack bar.
