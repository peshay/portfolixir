# Sprint 12 — closing-act walkthrough (2026-09-15)

Design-critic and UAT persona pass of the agentic review closing act
(ADR-0026 step 3), run under D-4's conditions of the Sprint 12 plan, on the
synthetic review dataset (`priv/demo/finding_surfaces_seed.exs`, no real
data), against a development server started with `PORTFOLIXIR_UI_PASSWORD`
and `PORTFOLIXIR_API_TOKEN` set. The shots in this directory are the retakes
after the fix round; the findings below say what the first takes showed.

## Conditions the walkthrough ran under (stated so the claim is checkable)

- **DE locale.** Every screen was rendered with `?locale=de`; the batch's own
  strings were read in German, not in the msgid.
- **1440 px and 390 px, light and dark.** Thirteen routes were walked in three
  contexts each — 1440 × 1000 light, 390 × 844 light, 1440 × 1000 dark — for
  39 route renders, each checked for horizontal overflow (document scroll
  width against the viewport), for console and page errors, and for raw
  uppercase constants reaching visible text. The interaction surfaces (the
  booking drawer, the filter sheet, the custom-range popover, the master-data
  dialog, the note card) were opened and closed in both widths on top of that.
- **Seed data that fires every alarm surface.** The review seed carries a held
  position whose newest close is 35 days old (the stale-quote finding fires on
  it), a delivered position with no price and no asset class, a watch-list
  security with no classification, a USD settlement account with a balance and
  no stored rate, a target plan whose top level leaves a remainder, a snapshot,
  a recorded tax statement, and a research log whose risk entry is superseded
  by a retraction.
- **The operator's own path, not seeded rows.** The transaction booked in the
  walkthrough was booked through the drawer at 390 px — type, depot, security,
  date, quantity, price, submit — and read back from the history's phone rows.
  Nothing was written through SQL.
- The run is scripted (`uat-sprint12.mjs`, `uat-interactions.mjs`,
  `book-uat.mjs` — Playwright against the booted instance) and reports console
  errors, page errors and overflow; the final run reported none.

## What was looked at

| Shot | Screen | What it shows |
| --- | --- | --- |
| `overview-strip-de-1440.png` | `/`, DE, 1440 px | the four-cell key-figure strip under the value card, its basis line, the drift bars in the off-target rows |
| `overview-strip-de-390.png` | same, 390 px | the strip as two by two, the basis line wrapping under it |
| `wealth-band-de-1440.png` | `/portfolio`, DE, 1440 px | the band in two tiers: three lead figures over four compact ones, the currency as a suffix, the sub-lines, the ⓘ in the label row |
| `wealth-band-de-390.png` | same, 390 px | the lead tier stacked, the support tier two by two |
| `wealth-allocation-summary-de-1440.png` | `/portfolio?tab=allocation` | one summary line instead of a second band, with the link back to Holdings; the sunburst with its basis line, legend values and data-as-table |
| `securities-phone-rows-de-390.png` | `/securities`, DE, 390 px | two-line rows: name over identifiers, price and day change right, the "Filter" control above them |
| `securities-filter-sheet-de-390.png` | same, sheet open | the families stacked in the bottom sheet, Reset and Done in its foot |
| `wealth-data-quality-de-1440.png` | `/portfolio`, DE, 1440 px | the data-quality notes as notes: the stale holding with its remedy, the unvalued settlement account with the sync control |
| `securities-stale-marker-de-1440.png` | `/securities`, DE, 1440 px | the stale row: the price, "veraltet · 2026-08-11" under it, the day change blanked |
| `securities-de-1440-dark.png` | same, dark | the list in dark, the derived-class control on the unclassified row |
| `security-detail-overview-de-1440-dark.png` | `/securities/:id?tab=overview` | the reading surface: six figures, the small chart, the thesis and note cards, the basis line — and no input element |
| `security-master-data-dialog-de-1440.png` | same, after **Bearbeiten** | the master data whole in the dialog, the raw-quotes toggle with its ⓘ |
| `transactions-phone-rows-de-390.png` | `/transactions`, DE, 390 px | the history as two-line rows under the summary, grouped by month |
| `booking-drawer-de-1440.png` | same, drawer open | the drawer beside the history, non-modal, the history still readable |
| `booking-drawer-de-390.png` | same, 390 px | the drawer as a modal bottom sheet, costs and note behind one disclosure |
| `booking-drawer-after-booking-de-390.png` | same, after submit | the drawer closed, "Transaktion erfasst", the new booking as the top row |
| `tree-rows-de-1440.png` | `/classifications/:id` | the column head over the rows, the figures right-aligned, the result stacked over its percentage, the basis line with its ⓘ |
| `tree-rows-de-390.png` | same, 390 px | the row keeping name, value and result |
| `custom-range-popover-de-1440-dark.png` | `/portfolio`, dark | the range popover on its trigger: the labelled pair, the year chips, Cancel and Apply |
| `tax-budget-de-390.png` | `/tax`, DE, 390 px | the budget meter, the two attention notes, the composition list |
| `views-de-390.png` | `/buckets`, DE, 390 px | the view rows with rule and coverage, the bucket rows with usage |

## What was checked live

- **No horizontal overflow** on any of the 39 route renders, and none with the
  drawer, the sheet or the popover open. One overflow was found and fixed
  during the pass (the detail header's action row at 390 px, see finding 2).
- **No console errors and no page errors** in the final run.
- **No raw constant on screen**: the scan for uppercase identifiers in visible
  text returned only labels the stylesheet upper-cases (KATEGORIE, ERGEBNIS,
  CASHQUOTE and friends) plus ISIN and TTWROR — no stored enum value, feed
  identifier or slug reached a screen.
- **The booking path end to end** at 390 px: drawer open, six fields, submit,
  drawer closed, result note, the booking as the history's top row with its
  size and running balance.
- **The stale surface**: `Nordic Timber Holdings AB`, newest close 2026-08-11,
  renders in the securities list as "42,64 · veraltet · 2026-08-11" with the
  day change blanked, and Wealth carries its attention data note ("Eine
  gehaltene Position wird mit einem Kurs bewertet, der älter als 7 Tage ist…")
  with the remedy inside it, beside the unvalued-cash note for the USD
  settlement account.
- **Gates on the branch head**: `mix format --check-formatted`,
  `mix compile --warnings-as-errors`, 2317 tests and 8 properties green,
  `mix credo --strict` clean, `mix sobelow --skip --exit` clean,
  `mix dialyzer` 0 errors, `mix coveralls` 91.6 %, `npm test` 87 passing,
  `npm run build`, `pre-commit run --all-files`.

## Findings

Three adversarial roles read the batch — a correctness hunter, an edge-case
hunter and a design critic — each reproducing a candidate before reporting it;
the UAT persona walkthrough above is the fourth. Every confirmed finding below
was reproduced, then fixed on the branch unless the row says otherwise. The
fix round is one commit, "the closing act's fix round".

### Fixed on the branch

| # | Role | What was wrong | Fix |
| --- | --- | --- | --- |
| 1 | UAT | The review seed destroyed its own stale-quote surface on a re-run: the quote seed prices every security up to today, the deliberately stale one included. | The seed drops the closes newer than its stale window after the quote seed runs; verified stale on a first and a second run. |
| 2 | UAT | The detail header's action row overflowed the 390 px viewport once **Edit** joined it. | The row wraps instead of overflowing. |
| 3 | Correctness | The Overview strip's "N stale" counted the active view's priced holdings while its link opened the catalog-wide list — two numbers for one finding on one page. | The cell renders the count the link resolves to, the shared predicate (#705). |
| 4 | Correctness | The note editor survived a change of security: opened on one, it handed over a filled form on the next. | Reset where every selection path passes; pinned by a test. |
| 5 | Correctness | The classification tree printed `0.00` for every category while the holdings loaded, and summed an unpriceable position as zero afterwards. | A total is a total only when every visible row carries the figure; otherwise a dash. Pinned by a test. |
| 6 | Correctness / design | The phone rows dropped the currency from the price and showed it only for a security with neither ticker nor ISIN. | The price carries its currency as the value slot's suffix on both lists, the running balance too; a row with no identifier says so. |
| 7 | Edge case | A retired security's old close was still being turned into a day change on three surfaces — the figure the stale marker exists to suppress. | The marker rule and the close rule are separate predicates; pinned by a test. |
| 8 | Edge case | Seven new date renders printed ISO in German, the stale marker among them — and the history's own date column, which #786 had left ISO while localizing the numbers beside it, disagreed with the phone row under it. | All through `Format.date/1`; the test that pinned the ISO form now pins the German one. ISO stays where a date is an input value. |
| 9 | Edge case | The allocation basis line printed the built-in tree's English seed name, eight lines under a control that localizes it. | The stored key travels with the name so the view localizes it (#729). |
| 10 | Edge case | The custom range's year group rendered as an empty labelled ARIA group with no history. | Rendered only where the walk has a year to offer; the period-control test covers both states. |
| 11 | Edge case | The Wealth IRR card asserted "annualized · as of …" under a figure that does not exist. | The sub-line goes with the figure. |
| 12 | Edge case | The Overview strip's basis line claimed a one-year window for a younger ledger. | It names the walked window's start. |
| 13 | Edge case | The unrealised sub-line printed a stray separator when the percentage is a dash. | The separator belongs to the percentage. |
| 14 | Edge case | The detail overview's basis line could render as an empty paragraph. | Rendered only when it says something. |
| 15 | Edge case | Two controls on the detail pane both read "Edit"; the phone kebab dropped `aria-expanded` when closed. | Both controls name what they edit; the attribute survives its false state. |
| 16 | Edge case | Both column pickers stayed on screen under 560 px, where their tables are hidden. | Hidden with the tables they configure. |
| 17 | Edge case | "Retired" was carried on the phone row by dimming alone. | A word in the row, per UX-DR27. |
| 18 | Edge case | The booking drawer's security select printed an empty parenthesis for a security with no ticker. | The parenthetical is omitted. |
| 19 | Edge case | A long category name clipped with no way to read it and could push the hidden-positions count out of the row. | The full name is the title; the count keeps its width. |
| 20 | Design critic | The not-computable dash rendered at value weight in the brand accent on both new tiers — the one state the re-composition exists to separate from "still computing". | The quiet muted dash the value-slot rule prescribes. |
| 21 | Design critic | TTWROR, IRR and the cash quote landed on the home screen with no definition anywhere on the page. | One ⓘ on the strip's basis line carries all three, reusing the Wealth band's sentences. |
| 22 | Design critic | The value suffix reached four call sites and not the product's largest number. | Applied at the Overview value card, the history's amount column and the snapshot cost; the rule unscoped from `.stat`. |
| 23 | Design critic | Both new bottom sheets showed the light backdrop to a default-theme user on a dark OS. | They join the dark-scheme media block the other modals use. |
| 24 | Design critic | The transactions phone row's two children landed in the four tracks meant for four. | Its own two tracks, so the elastic column is under the body. |
| 25 | Design critic | The booking drawer's disclosure shipped the raw browser triangle beside the house chevron. | The defined chevron. |
| 26 | Design critic | Cancel in the custom-range popover dropped focus to the document. | Both Cancel controls close through the hook, which returns focus to the summary. |
| 27 | Design critic | The tree head's radius was a fourth value off the three-step scale. | On the scale. |
| 28 | Design critic | Two fallback clauses printed a raw enum value — the shape the rule this batch wrote forbids. | Both de-slug to words, the answer `Feeds.label/1` gives. |
| 29 | Design critic | The spine's overlay inventory still claimed the build had zero `<dialog>` elements and seven `aria-modal` attributes. | It has nine and none; the bullet records what was built. |

### Recorded, not fixed here

| Finding | Why it is an issue and not a commit |
| --- | --- |
| The detail pane's tab row is held to none of the D6 shipped form (no snap, no fade, the forbidden `border-bottom` baseline). | The review filed the tab-row work against the Wealth row alone (#790 item 4); this row is inherited. Filed as **#817**. |
| The transaction history's filter chips need the phone sheet the securities list got. | C4 named the securities toolbar; the same reason applies to the history, which makes it a follow-up rather than a preference. Filed as **#816**, and named in the close-out's surface check. |
| The `/classifications` index is a bare bullet list over an empty workspace. | Outside the batch's issue set; the tree behind it was in scope, its index was not. Filed as **#815**. |
| Three spacing and token observations (off-scale gaps in the new CSS, `{rounded.full}` naming a token that does not exist, the bottom-sheet up-shadow written by hand three times). | Each is a one-line decision for the spine rather than a change to this diff; recorded here so the next batch does not re-decide them. |
| Two spec tensions the critic named: the forced-colors clause of the value slot against the #723 sub-second amendment, and whether the securities detail's custom range should carry year chips. | The *spec* is what should change, not the build. |
