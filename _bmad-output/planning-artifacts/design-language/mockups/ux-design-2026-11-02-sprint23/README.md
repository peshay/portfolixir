# Sprint 23 boards — coverage views, money on screen, the journal, number colours

Four boards for the Sprint 23 planning PR, drawn on 2026-11-02. Each is an
HTML artboard that links the real `priv/static/app.css` and is rendered to
PNG at 1200 px and at 390 px.

| Board | Files | Issues |
|---|---|---|
| 01 — the coverage views | `01-coverage.html`, `01-coverage-390.html`, `01-coverage--1200.png`, `01-coverage--390.png` | R6 #1292 #1290, the ADR-0053 amendment of 2026-11-02 (#1371's check), A4 #957 |
| 02 — money on screen | `02-money.html`, `02-money-390.html`, `02-money--1200.png`, `02-money--390.png` | #1371, #1369, #1368, R5 #1310 #1311 (after the fact) |
| 03 — U2, the audit journal viewer | `03-journal.html`, `03-journal-390.html`, `03-journal--1200.png`, `03-journal--390.png` | U2 (two-way coverage debt since Sprint 19) |
| 04 — number colours against the three accents | `04-number-colours.html`, `04-number-colours-390.html`, `04-number-colours--1200.png`, `04-number-colours--390.png` | owner request, 2026-11-02 |

**Synthetic data only.** The names and figures come from the synthetic
review seed (`priv/demo/finding_surfaces_seed.exs`) or are invented where
the seed has no such case; each invented case is listed below. No real
portfolio data, name or machine detail appears.

## How the frames are made

**Captured, not drawn by hand.** Every frame was captured with Playwright
from a review instance running in German on the synthetic review seed
(port 4003, database `portfolixir_review`, the seed's header gives the
commands). The build only reads:

- it sends GET requests;
- it opens `<details>` in the browser;
- it sends LiveView events that open a dialog or fill a form, and never
  submits: the booking drawer (an edit of the imported Arbolia buy, a sell
  of Helios typed in) and the two merge previews (step 2 of „Zusammenführen
  in…“);
- for board 04 it sets the browser's own column preference for Wealth's
  positions table (`localStorage`, the value columns on).

A frame's "after" state is the shipped markup with the proposal applied to
the live DOM as markup (the preps in `frames.js`). Each frame is written as
its own static page under `frames/` and placed on its board as an
`<iframe>`, so a drawer or a dialog keeps its own viewport. Desktop frames
are 1060 px wide, the main column of a 1280-px window; dialogs and the
drawer are 760 px wide, so their desktop rules apply. Phone frames are the
390-px viewport. No script runs on a board or a frame.

**"Heute" frames** render `app.css` as shipped. Proposal frames carry their
CSS in `<style id="proposal">`. Dashed means new or changed. An amber left
edge marks a synthetic row written into the shipped markup of a real one. A
circled number ties a change to its section's text.

**Invented where the seed has no such row** (each one is said on its board):

- 01 ①a: the three reports are empty on the seed, so their counts are 1
  each. The rows are the shipped markup of real rows with their figures
  rewritten:
  - the Arbolia buy, price 81,00 against cash 806,00, the ADR's example;
  - the Larkspur buy as a rate-only USD trade;
  - the Wexmoor split row as if its second portfolio's row were missing.
- 01 ①a variant B: the Imports section is built into the Imports page.
- 01 ①b: the seed's depot pairs have no equal bookings, so the depot
  preview carries two synthetic pairs and the three flow entries they would
  remove.
- 02 ①d: three exclusion sentences with synthetic names, in the live
  notes beside the seed's two real reasons.

Two figures were computed, not captured:

- 02 ①c: the category figures after the change, from the seed's holdings
  read with the trade-price fallback.
- 02 ①b: the open lots' results, 15 × (19,20 − 18,00) and 5 × 0.

**The journal frames (board 03)** are a page that does not exist yet. The
build puts its markup into the shell of a shipped page (the topbar and the
workspace of `/transactions`), using the app's own classes. Its entries are
the seed's journal as stored: the seven writes of the API token named
„review seed“.

## Board 01 — the coverage views

### ①a: R6's two reads and the cash check, on the Overview's data-quality line

- **Today:** `GET /api/v1/splits/incomplete`, `GET
  /api/v1/transactions/rate_only` and (ADR-0053, 2026-11-02) `GET
  /api/v1/transactions/cash_mismatch` have no human view.
- **After (A):**
  - Each check with a count above zero adds one finding to the
    data-quality line, in the line's shape: the count with its noun as the
    link, then what it does to the figures (`data-effect-of`, #1121).
  - The link opens the history filtered `?dq=cash_mismatch`,
    `?dq=rate_only` or `?dq=incomplete_split`. The filter is URL-driven like
    `?since=` and shows exactly the report's rows.
  - Above the rows sits a clamped problem note with the report's `note`
    and `remedy` in the operator's words, and „Alle Buchungen zeigen“ in its
    actions.
  - A row's second line gives the figure the check compares.

**Q1 — where the three checks are read. Recommended: A.**

- **A:** three findings on the Overview's data-quality line, each opening
  the filtered history.
- **B:** a „Datenqualität“ section on the Imports page, listing the rows
  inline.

The reasons for A:

- **One finding surface.** The Overview's data-quality line is where the
  operator already reads what is wrong (UX-DR2).
- **It is the existing pattern.** Every finding links to the list
  pre-filtered to its rows (#561, #651), and the history row already has
  „Bearbeiten“, the remedy.
- **No new page and no second booking table.**
- **The agent's reads stay one-to-one.** Each finding is one API read.

B would fit only if these checks were tied to imports. They are not: a hand
edit (#1371) or an agent's PATCH can produce a cash mismatch too. A comment
„Q1 B“ flips the pick.

**Q2 — the three findings' severity. Recommended: problem**, because each
can make a figure wrong (`dq_severity/1` takes them before the stale
quote). A comment „Q2 attention“ flips it.

### ①b: A4's flow changes in the merge previews (conformance repair, before/after)

- **Today:** the API serves `flow_changes` with `flow_basis`. The screens
  show only the absorbed flows, as a phrase in „Ändert auch“.
- **After:**
  - A section „Externe Zu- und Abflüsse — bei „als Duplikate entfernen““
    follows the choice of the equal bookings.
  - Its table has the columns Datum · Wirkung · Buchung · wo · Stück ·
    Fluss, and the flow cell names what the amount is valued at.
  - Under 720 px the table becomes the preview's two-line rows.
  - The `flow_basis` method sentences sit behind the section's ⓘ (I1). The
    short basis stays visible.
- **Empty state:** a single basis line, the anatomy the preview already uses
  for an unchanged FIFO result: „Externe Zu- und Abflüsse: Keiner entfällt
  oder wandert; die Rendite liest dieselben Flüsse.“

**Q3 — „Ändert auch“ keeps its absorbed phrase. Recommended: keep it**,
because it is what the operator reads while choosing. A comment „Q3 drop
it“ flips it.

## Board 02 — money on screen

### ①a: #1371, the cash of an imported trade

**Q4 — answer (b), adopted by the ADR-0053 amendment of 2026-11-02.**

- The drawer shows „Betrag (EUR)“ on a buy or a sell that stores its cash
  and has no settlement legs. „Betrag (EUR)“ is the drawer's existing label
  for the cash, the cash form's and the history column's word.
- When quantity, price, fees or taxes change, the field is prefilled with
  what the new figures derive (816,00). An attention note gives the sum.
- Saving states the cash, because the field is part of the form. A figure
  off by more than a cent is refused with the field's own error.
- Today's state is drawn too: price 81 with the cash left at 806,00, with
  no cash field anywhere on the screen.
- Variant (a), the cash re-derived silently, is drawn for contrast.

A comment „(a)“ flips the pick, as the ADR says.

### ①b: #1369, open lots and the sell preview at the last own trade price

- Helios has no quote, and its head already says it counts at 19,20 EUR
  (14.03.2025).
- **After:**
  - The Trades tab's „Letzter“ reads 19,20 with „Handelspreis ·
    14.03.2025“, and every result column follows.
  - The sell preview says „Bepreist zum letzten eigenen Handelspreis: 19,20
    (14.03.2025).“, and Bruttogewinn reads +6,00 EUR.

### ①c: #1368, the category result at the last own trade price

- **After:**
  - ETF: Einstand 21.749,40, Ergebnis −256,20 (−1,2 %) over all 15
    positions, where today it is 2 of 15.
  - Fund: 451,11 / 0,00.
  - Each trade-priced member names „zum Handelspreis“.
  - The excluded note keeps the three positions no rule can value.
  - The basis line names the price rule.

### ①d: Sprint 22 R5, drawn after the fact

R5 added three exclusion sentences to Cash flow → Trades
(`realized-excluded`) and to the Overview's closed trades card
(`trades-card-excluded`):

- a third currency;
- a buy paid in another currency;
- a buy of amount zero.

They are drawn as built, with the notes expanded.

## Board 03 — U2, the audit journal viewer

**Q5 — Recommended: A**, one page „Audit-Journal“ (`/journal`).

- **A:**
  - Newest first.
  - Filters by actor and operation as chips, the kind as a select, and the
    what-if scenarios as a checkbox. These are exactly the API's filters.
  - Each row has a fold of its stored before/after values, reduced to the
    changed fields.
  - Each row links to its entity's page where one exists. „Nur dieser
    Eintrag“ filters to that entity (`resource_type` + `resource_id`).
- **B:** a „Verlauf“ fold on each entity's own page, drawn on Meridian
  Global Equity ETF.

The reasons for A:

- The operator's question is global: „what did the agent change this
  week?“
- The page matches the API's shape.
- It is one surface. B needs a fold on every entity page, and a booking has
  no page of its own, so B cannot show the most frequent entry at all.
- A gives B's per-entity view through „Nur dieser Eintrag“.

A comment „Q5 B“ flips the pick.

**Q6 — where the entry sits. Recommended: the sidebar's „Verwaltung“
group**, after „Klassifizierungen“. No Settings page exists, and a
Transactions tab would claim the journal is about bookings only. A comment
„Q6 tab“ flips it.

## Board 04 — number colours against the three accents

**The complaint.** With the teal accent:

- Wealth's unsigned KPI value is teal (`#0f766e`) and the gains are another
  green (`#047857`).
- With coral, a coral total sits beside a red loss.

The rule today (DESIGN.md, stat-card `value-color`): a KPI value takes the
active accent, except signed money, which takes
`--color-positive`/`--color-danger`. The Overview's KPI strip already shows
unsigned figures in `--color-text`, against that rule.

**Frames.** Wealth (tabs, lead KPI row, four positions with signed G&V) and
the Overview's KPI strip, captured once and written under each look:

- today, A, B and C, each under violet, teal and coral, light;
- today and C dark under teal, and C dark under coral;
- the strip under teal for every variant.

**Q7 — Recommended: C.** The accent is for controls only.

- Unsigned figures take `--color-text`.
- A gain takes brand teal and a loss brand coral, whatever the accent:
  light `#0f766e` / `#ce1b42`, dark `#2dd4bf` / `#fb7185`.
- `--color-positive` and `--color-danger` become aliases of those, so the
  app has one green and one red.

Where C still collides, drawn honestly: under the teal accent the active
tab and links are teal beside teal gains, and under coral they are coral
beside coral losses. The collision moves from figure against figure to
control against figure, and a control is told apart by its shape.

- **A:** gains always teal, losses always coral; unsigned KPI values keep
  the accent. A teal total then reads as a gain.
- **B:** every figure in the accent; the sign carried by its glyph alone.

A comment „Q7 A“ or „Q7 B“ flips the pick.

**Contrast.** WCAG 2.x, computed from app.css tokens by the method of
`test/invariants/css_accent_contrast_test.exs`. The table is on the board.

| | on bg | on bg-elevated | on the problem tint |
|---|---|---|---|
| teal, light | 5,11 | 5,47 | 4,56 |
| coral, light | 5,08 | 5,44 | 4,53 |
| teal, dark | 10,32 | 9,40 | 8,51 |
| coral, dark | 7,14 | 6,50 | 5,89 |

Every value clears 4,5:1. Coral on the problem tint in light mode has the
smallest margin (4,53).

**The sign is never colour alone.** Every signed figure on the frames
carries its glyph („+9,0%“, „+75,00“, „-975,15“).

**What C recolours beyond the figures.** Every consumer of
`--color-positive` and `--color-danger` in `priv/static/app.css`:

- **Positive:**
  - `.tx-badge--buy`, `.chart-tooltip__tx--buy`, `.security-chart .tx-buy`
  - `.is-positive` and its table, stat, overview-metric, perf-badge,
    kpi-summary and kpi-strip forms, `.decimal-positive`
  - `.import-done .success-icon`
  - `.badge--thesis-intact`
  - `.soll-ok`
  - `.drift-bar__fill.is-over`
- **Danger:**
  - `.field-error`, `[aria-invalid="true"]`, `input[pattern]:invalid`
  - `.alert-error`
  - `.data-note--problem` (border and text)
  - `.row-context-menu__item--danger`, `.button-danger`, `.chip-remove`
  - `.tx-badge--sell`, `.chart-tooltip__tx--sell`, `.security-chart
    .tx-sell`
  - `.is-negative` and its forms, `.decimal-negative`
  - `.import-stat-card.warning .value`
  - `.badge--thesis-retracted`, `.badge--danger`
  - `.research-entry-form__errors`, `.fx-sync-error`,
    `.bucket-inline-error`, `.form-error`
  - `.drift-bar__fill.is-under`
  - `.merge-pair__role--gone`

The soft tints (`--color-danger-soft`) stay as they are. Dark danger
already equals dark coral, so C changes nothing for danger in dark mode. The
story writes the new rule into DESIGN.md's stat-card entry and extends the
contrast invariant to the aliases.

## New strings (German drafts; the stories add the msgids)

Checked against `priv/gettext/de/LC_MESSAGES/default.po`. Existing strings
on the frames are read from the catalogue by `build.js` (`de()`), never
retyped.

| Where | English (msgid draft) | German |
|---|---|---|
| 01 ①a, finding (`ngettext`) | one booking whose cash misses its quantity × price, fees and taxes / %{count} bookings whose cash misses their quantity × price, fees and taxes | eine Buchung, deren Betrag nicht zu Menge × Preis, Gebühren und Steuern passt / %{count} Buchungen, deren Betrag nicht zu Menge × Preis, Gebühren und Steuern passt |
| 01 ①a, its effect | — so the cash balance and the cost read different amounts | — Kontostand und Einstand lesen daher verschiedene Beträge |
| 01 ①a, finding (`ngettext`) | one cross-currency buy or sell with a rate and no cash amount / %{count} cross-currency buys or sells with a rate and no cash amount | ein Kauf oder Verkauf in Fremdwährung mit Wechselkurs, aber ohne Betrag / %{count} Käufe oder Verkäufe in Fremdwährung mit Wechselkurs, aber ohne Betrag |
| 01 ①a, its effect (`ngettext`) | — it books quantity × price to the account unconverted / — they book … | — er bucht Menge × Preis ohne Umrechnung aufs Konto / — sie buchen … |
| 01 ①a, finding (`ngettext`) | one split missing a portfolio that held the security / %{count} splits each missing a portfolio that held the security | ein Split, dem ein Portfolio fehlt, das das Wertpapier hielt / %{count} Splits, denen je ein Portfolio fehlt, das das Wertpapier hielt |
| 01 ①a, its effect | — there the lots are split and the holding is not | — dort sind die Lots geteilt, der Bestand nicht |
| 01 ①a, the filtered history's action | Show all bookings | Alle Buchungen zeigen |
| 01 ①a, note `dq=cash_mismatch` (`ngettext` lead) | Filtered: %{count} buy or sell whose cash misses its quantity × price, fees and taxes — so the cash balance and the cost read different amounts. State the cash in the booking form (Edit): the amount settled, or the one the figures give. Nothing is changed automatically. | Gefiltert: %{count} Kauf oder Verkauf, dessen Betrag nicht zu Menge × Preis, Gebühren und Steuern passt — Kontostand und Einstand lesen daher verschiedene Beträge. Den Betrag im Buchungsformular angeben (Bearbeiten): den abgerechneten, oder den, den die Zahlen ergeben. Nichts wird automatisch geändert. |
| 01 ①a, note `dq=rate_only` | Filtered: %{count} cross-currency buy or sell with a rate and no cash amount — the ledger books quantity × price with fees and taxes, in the security's currency, as the account's cash, and never applies the rate. Enter the settlement amount in the booking form (Edit): the amount before fees and taxes, from which the form books the cash; backfilling rates does not change these bookings. Nothing is changed automatically. | Gefiltert: %{count} Kauf oder Verkauf in Fremdwährung mit Wechselkurs, aber ohne Betrag — das Hauptbuch bucht Menge × Preis mit Gebühren und Steuern in der Währung des Wertpapiers als Bargeld des Kontos und wendet den Kurs nie an. Den Abrechnungsbetrag im Buchungsformular eintragen (Bearbeiten): den Betrag vor Gebühren und Steuern, aus dem das Formular das Bargeld bucht; das Nachladen der Wechselkurse ändert diese Buchungen nicht. Nichts wird automatisch geändert. |
| 01 ①a, note `dq=incomplete_split` | Filtered: %{count} split missing a portfolio — %{security} · %{ratio} · %{date}: “%{portfolio}”, which held %{quantity} shares before, is missing. There the FIFO lots are split and the holding is not. Record the split again with the same date and ratio (“Record split” on the security): it adds only the missing rows. If the split is wrong, delete the whole split. Nothing is changed automatically. | Gefiltert: %{count} Split, dem ein Portfolio fehlt — %{security} · %{ratio} · %{date}: es fehlt „%{portfolio}“, das vorher %{quantity} Stück hielt. Dort sind die FIFO-Lots geteilt, der Bestand nicht. Den Split mit demselben Datum und Verhältnis erneut erfassen („Split erfassen“ beim Wertpapier): Er ergänzt nur die fehlenden Zeilen. Ist der Split falsch, den ganzen Split löschen. Nichts wird automatisch geändert. |
| 01 ①a, a row's second line | from its figures: %{amount} | aus den Zahlen: %{amount} |
| 01 ①a, a row's second line | settlement amount at its own rate %{rate}: %{amount} | Abrechnungsbetrag zum eigenen Kurs %{rate}: %{amount} |
| 01 ①b, heading | External flows | Externe Zu- und Abflüsse |
| 01 ①b, heading's qualifier | with “remove as duplicates” | bei „als Duplikate entfernen“ |
| 01 ①b, basis | One entry per flow of the time-weighted return that removing the duplicates drops or moves · amounts in the account's currency | Je Eintrag ein Fluss der zeitgewichteten Rendite, der beim Entfernen der Duplikate entfällt oder wandert · Beträge in der Währung des Kontos |
| 01 ①b, ⓘ line 1 | Removed: a collapsed inbound or outbound delivery, an external flow of its portfolio on its date. Quantity: the change in the units of that flow; the amount at the booked price, without a price at the day's price. | Entfällt: eine zusammengeführte Ein- oder Auslieferung, ein externer Fluss ihres Portfolios an ihrem Tag. Stück: die Veränderung der Stücke dieses Flusses; der Betrag zum gebuchten Preis, ohne Preis zum Tageskurs. |
| 01 ①b, ⓘ line 2 | View boundary: a transfer, buy or sell with exactly one leg in the view, a flow across its boundary and none of the portfolio's; one entry per view. | Ansichtsgrenze: eine Umbuchung, ein Kauf oder Verkauf mit genau einem Bein in der Ansicht, ein Fluss über deren Grenze und keiner des Portfolios; ein Eintrag je Ansicht. |
| 01 ①b, ⓘ line 3 | Set balance: the cash of a removed booking that its account's next set balance absorbs as its residual. | Gesetzter Saldo: der Geldbetrag einer entfernten Buchung, den der nächste gesetzte Saldo ihres Kontos als Rest aufnimmt. |
| 01 ①b, ⓘ line 4 | Each listed day's flow changes by these entries alone; the return from that day on also reads the removed units no longer held. The preview therefore lists the flows, not a recomputed return. | Der Fluss jedes genannten Tages ändert sich nur um diese Einträge; die Rendite ab diesem Tag liest zudem die entfernten Stücke nicht mehr. Die Vorschau nennt daher die Flüsse, keine neu gerechnete Rendite. |
| 01 ①b, ⓘ line 5 | View membership is read as it stands; the merge does not change it. | Die Zugehörigkeit zu Ansichten gilt, wie sie steht; das Zusammenführen ändert sie nicht. |
| 01 ①b, columns | Effect · Booking · where · Flow | Wirkung · Buchung · wo · Fluss |
| 01 ①b, effects | removed · removed at the view boundary · absorbed by the set balance | entfällt · entfällt an der Ansichtsgrenze · vom gesetzten Saldo aufgenommen |
| 01 ①b, valued at | at the booked price · at the booked value · at the day's price | zum gebuchten Preis · zum gebuchten Wert · zum Tageskurs |
| 01 ①b, empty state | External flows: none is removed or moved; the return reads the same flows. | Externe Zu- und Abflüsse: Keiner entfällt oder wandert; die Rendite liest dieselben Flüsse. |
| 02 ①a, the cash field's help | The cash the account moves. Stored: %{amount} (as imported). | Das Geld, das das Konto bewegt. Gespeichert: %{amount} (wie importiert). |
| 02 ①a, attention note | Quantity, price, fees or taxes changed: the amount does not follow by itself. Suggested: %{derived} = %{quantity} × %{price} + %{fees} + %{taxes}. Saving takes what the field states — enter the amount settled if it differs. | Menge, Preis, Gebühren oder Steuern geändert: Der Betrag folgt nicht von selbst. Vorgeschlagen sind %{derived} = %{quantity} × %{price} + %{fees} + %{taxes}. Speichern übernimmt, was im Feld steht — den abgerechneten Betrag eintragen, wenn er abweicht. |
| 02 ①a, field error | does not match quantity × price, fees and taxes — expected %{expected} | passt nicht zu Menge × Preis, Gebühren und Steuern — erwartet %{expected} |
| 02 ①a, variant (a) only | Amount derived from the new figures: %{new} instead of %{old} (as imported). | Betrag aus den neuen Zahlen abgeleitet: %{new} statt %{old} (wie importiert). |
| 02 ①b, sell preview | Priced at the last own trade price: %{price} (%{date}). | Bepreist zum letzten eigenen Handelspreis: %{price} (%{date}). |
| 02 ①c, basis clause | prices: the latest quote, without one the last own trade price | Kurse: der neueste, ohne Kurs der letzte eigene Handelspreis |
| 03, page title / subtitle | Audit journal · Every stored change, who made it and what stood before | Audit-Journal · Jede gespeicherte Änderung, wer sie machte und was vorher stand |
| 03, labels | Entries · Actor · Operation · Entry · Change · Time (UTC) · All · All kinds | Einträge · Akteur · Vorgang · Eintrag · Änderung · Zeit (UTC) · Alle · Alle Arten |
| 03, operations | Changed · Deleted · Created or replaced (Created exists) | Geändert · Gelöscht · Angelegt oder ersetzt (Angelegt existiert) |
| 03, checkbox | Include what-if scenarios | Was-wäre-wenn-Szenarien einbeziehen |
| 03, basis | Newest first · %{count} entries · actor %{actor} · without what-if scenarios · times in UTC | Neueste zuerst · %{count} Einträge · Akteur %{actor} · ohne Was-wäre-wenn-Szenarien · Zeiten in UTC |
| 03, fold | Stored values · Before (Field and After exist) | Gespeicherte Werte · Vorher (Feld und Danach existieren) |
| 03, delete / link | deleted, with every value · Only this entry | gelöscht, mit allen Werten · Nur dieser Eintrag |
| 03, B only | History | Verlauf |

Reused unchanged from the catalogue, among others: „Datenqualität“,
„Betrag (%{currency})“, „Handelspreis · %{date}“, „zum Handelspreis“,
„Split erfassen“, „als Duplikate entfernen“, „beide behalten“, „Ändert auch:
%{changes}“, „ein gesetzter Saldo von %{name} am %{date} nimmt %{amount}
auf“, R5's sentences and counts, „Operator“, „Agent“, „Import“, „System“,
„Angelegt“, „Feld“, „Danach“, „Stück“. Board 04 adds no string.

## Found while drawing (severity per the sprint workflow §3)

1. **S3, Cash flow → Trades:** the backfill's method sentence and the
   „Historische Wechselkurse nachladen“ button follow every exclusion
   reason. R5's three reasons say no rate fixes them, so with only those
   reasons the note offers a remedy that cannot act (UX-DR25 clause 3).
   Polish list „Cash flow“.
2. **S3, Overview:** in the closed trades card the pointer „Das Nachladen
   der Wechselkurse steht unter „Alle Trades““ sits after the missing-leg
   sentence. With R5's sentences after it, it reads as if it covered them.
   Polish list „Overview“.
3. **S3, Cash flow and Overview:** with five reasons the count lead repeats
   every count, and the realized note runs to nine lines at 1200 px.
4. **S3, Transactions:** the history's summary reads „1 Transaktionen“: the
   label after the count is a plain `gettext("transactions")`, not an
   `ngettext`. Polish list „Transactions“.
5. **S3, idea:** `GET /api/v1/journal` has no time filter, so the operator's
   „this week?“ is answered by paging. A `since=` (API, MCP, then the page)
   needs its own story; it goes into the idea list.
6. **S3:** a booking has no URL of its own. The journal, and any agent
   hand-over, can link a transaction only to the history as a whole.
7. **S3, to check against the API reference:** in the seed's journal a
   `delete` entry's `after` repeats the deleted record instead of being
   empty, so a before/after comparison shows no change. The page reads the
   operation, not the diff.
8. **Note, not a defect:** the Overview's KPI strip already shows unsigned
   figures in `--color-text`, against DESIGN.md's stat-card rule. Board 04's
   C makes the rule match the strip.

## How to regenerate

The review instance must run on port 4003 with the synthetic review seed
(the seed's header gives the database and the commands). Then, from this
folder:

```bash
node build.js    # captures every frame into frames/ and writes the boards
node render.js   # renders the eight boards to PNG (256 colours with Pillow)
node board.js    # rebuilds the boards alone from frames/sizes.json
```

`ONLY=<regexp> node build.js` re-captures matching frames and keeps the
others' sizes. `BASE=http://localhost:4000 node build.js` points the build
at another instance. Run the build only against the synthetic seed: the
frames are its markup verbatim.

## Not shown

- **Dark mode** is drawn only on board 04. The other boards' new notes and
  cells use existing tokens that have dark values.
- **The incomplete-split and rate-only filtered histories at 390 px.**
  They take the cash check's phone anatomy.
- **The security merge preview with flow entries.** It takes the depot's
  section unchanged.
- **02 ①c's category tree before the change at 390 px.** It is the
  desktop frame's content in the shipped phone layout, which hides
  „Einstand“.
