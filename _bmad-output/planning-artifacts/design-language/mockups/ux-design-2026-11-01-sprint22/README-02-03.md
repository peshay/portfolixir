# Boards 02 and 03 — Sprint 22's figures, booking drawer, import and accounts

Two boards for the Sprint 22 planning PR, drawn on 2026-11-01. Each is an
HTML artboard that links the real `priv/static/app.css` and is rendered to
PNG at 1200 px and 390 px (`<body data-widths="1200,390">`).

| Board | Files | Issues |
|---|---|---|
| 02 — figures on screen | `02-figures.html`, `02-figures--1200.png`, `02-figures--390.png` | #1316 + #1332, #1331, #1274 (+ #1293's tables), #1343 |
| 03 — booking drawer, import and accounts | `03-drawer-import.html`, `03-drawer-import--1200.png`, `03-drawer-import--390.png` | #1335 + #1337, #1313 (choice), #1219, #1299, #1333 |

**Data.** Synthetic only. The names and figures come from the synthetic
review seed (Helios Solar Systems SE, Meridian Global Equity ETF, Arbolia
Inc., Coupon-Cash), or are invented where the seed has no such case. The
invented cases are a USD dividend with a stored rate, a cash-only risk
view, a cash-only instance, two same-named accounts, and a file already
imported into „Anleihen“. No real portfolio data appears.

**How the frames are built.** Every frame is a `srcdoc` iframe. Its markup
was captured with Playwright from a running review instance in German.
Where the instance cannot be put into the state without a write, the frame
uses the template that renders it:

- the import preview, because no file was dropped;
- the cash-only history;
- the twin accounts.

The edit drawer of the imported Arbolia buy was opened and closed without
saving. „Heute“ frames render `app.css` as shipped. The other frames add the
board's `<style id="proposal">`. German strings are checked against
`priv/gettext/de`, and new strings are listed below. Dashed means new or
changed. A red ring marks a label that is wrong today. A circled number
ties a change to its section.

## Board 02 — figures on screen

All four sections are conformance repairs, drawn as before/after.

1. **#1316 + #1332, one valuation rule.**
   - **Today:**
     - The Bestände tab prints „—“ and „Gesamt 0,00 EUR“ for Helios, which
       has no quote, while the detail head says the position counts at its
       trade price.
     - Wealth's Positionen table prints „—“ for the eleven positions its
       total values at their last trade price.
   - **After:**
     - The holdings read takes the valuation's rule. A position with no
       quote is valued at its last own trade price, and `price_source` is
       named in the computation basis.
     - The row says so in a second line: „zum Handelspreis“ on the tab, and
       „Handelspreis · 01.07.2025“ in Wealth's price cell.
   - **1b:** a position with no price at all keeps its dash with „kein
     Preis“. Its total reads „—“ instead of a false 0,00, and an attention
     note under the total names the row (UX-DR25).
   - **New CSS:** one rule, `.data-table td .cell-note`, which is the
     contribution table's note lifted to any table cell.
2. **#1331, Brutto.**
   - **Today:** a dividend's Brutto on the security's Transaktionen tab is
     the cash credited (7,50).
   - **After:** Brutto is cash plus the withheld tax (9,48), Income's
     definition. No new string and no CSS.
3. **#1274, Income's currencies.**
   - **Today:** a converted payment prints base-currency figures under a
     foreign „Währung“ label („11,04 · 1,66 · 9,38 · USD“).
   - **After:**
     - Brutto, Steuern and Netto are the payment's own figures, in the
       currency the column names.
     - A new last column, „Netto (EUR)“, carries the converted figure that
       the totals sum.
     - An unconverted payment reads „—“ with „ohne Umrechnung“ there, and
       never a converted figure.
     - „Je Position“ takes the same shape.
4. **#1343, zero drawdown.**
   - **Today:** a drawdown of exactly 0 names an episode
     („01.11.2025 → 01.11.2025 · erholt 01.11.2025“).
   - **After:** the sub-line reads „kein Rückgang im Zeitraum“. A real
     drawdown that rounds to „-0,0“ keeps its dates.

## Board 03 — booking drawer, import and accounts

1. **#1335 + #1337.**
   - **The legless buy:** the imported cross-currency buy without
     settlement legs opens in its stored booking currency: „Preis (EUR)“,
     no settlement fieldset, „Währung: EUR“. A Hinweis says why, and that
     „Historische Wechselkurse nachladen“ under Cashflow → „Trades“ derives
     its USD figure. Saving keeps the buy in EUR and never re-books it as
     USD.
   - **The sell preview:** it prints „24,00 EUR“ and „2,5“, the history's
     rule, where it printed „24 EUR“ and „2.5“.
2. **#1313: the one choice on these boards.** Rows already imported into
   another portfolio are named and held back by default. The board draws
   today, variant A and variant B (the recommendation is below).
3. **#1219.** A refused row whose booking exists, imported or entered by
   hand and found on the economic layer, says „bereits gebucht“. It names
   the booking by date, kind, security, quantity, amount and account, notes
   that it was entered by hand, and ends „nicht noch einmal buchen“. A row
   with no match keeps its remedy.
4. **#1299.** On an instance with cash accounts and no depot, „Transaktion
   erfassen“ shows. The drawer opens on the cash form, and the type list
   holds the cash kinds only. The setup line says what needs a depot.
5. **#1333.** Two same-named accounts in different portfolios carry their
   portfolio's name, using #1155's twin tag in the accounts table and the
   history's Konto chips. Only twins carry it. **New CSS:** one rule,
   `.twin-id--portfolio`, which drops the tag's monospace.

## #1313 — recommendation: variant A

**A:** one collapsed group per other portfolio, an attention note at the
head of the preview: „Bereits im Portfolio „Anleihen“ importiert: 4 Einträge
— nicht übernommen“. It has a „Trotzdem übernehmen“ toggle, and the mapping
rows read „4 Buchungen in „Anleihen“ importiert · nichts anzulegen“.

**B:** the entries inline in a new list. Each entry is marked „bereits in
„Anleihen““ and is left unchecked.

**Recommended: A.** The reasons:

- **The decision is per portfolio, not per row.** „This history is
  already in Anleihen“ is one fact about a set of rows, so one sentence and
  one switch say it, with the consequence (a second copy in this portfolio)
  stated once.
  - B asks the same question once per row. A Portfolio Performance export
    holds the whole history, so the usual case is a file imported elsewhere
    in full: four rows here, hundreds in practice.
- **A fits the preview's anatomy.** The preview speaks in counts: the cards,
  „Anzahl pro Art“, the mapping counts and the nothing-to-import note. It
  has no row list. B would add the page's first row table, with a checkbox
  column that the apply must honour row by row.
- **B invites a partial copy.** Ticking some rows of an already-imported
  history books a fragment of it twice. A includes the whole group or
  nothing.
- **A hides nothing.** The group opens to list its entries (drawn at
  390 px).

B fits only if the owner expects files that mix rows from several
portfolios with new rows, and wants to pick among them. A comment naming
„#1313 B“ on the planning PR changes the pick, and silence adopts A.

## New strings (German drafts; the stories add the msgids)

| Where | English (msgid draft) | German |
|---|---|---|
| 02 ①, the tab's value cell | at trade price | zum Handelspreis |
| 02 ①, Wealth's price cell | Trade price · %{date} | Handelspreis · %{date} |
| 02 ①, a row with no price | no price · not in the total | kein Preis · nicht in der Summe |
| 02 ①, the tab's no-price cell | no price | kein Preis |
| 02 ①, the note under the tab's total (`ngettext`) | %{count} position is missing from the total — no price is known for this security (no quote and no own trade): %{rows}. | %{count} Position fehlt in der Summe — für dieses Wertpapier ist kein Preis bekannt (kein Kurs und kein eigener Handel): %{rows}. |
| 02 ①, Wealth's positions basis (tail) | … or, without a quote, at the last own trade price | … oder, ohne Kurs, zum letzten eigenen Handelspreis |
| 02 ③, column | Net (%{currency}) | Netto (%{currency}) |
| 02 ③, purpose line (tail) | … in its currency, the net also in %{currency} | … in ihrer Währung, das Netto auch in %{currency} |
| 02 ④ | no decline in the period | kein Rückgang im Zeitraum |
| 03 ①, Hinweis | Booked in %{booking}, as imported — the security trades in %{security}, and this buy has no figure in %{security} yet. Saving keeps it in %{booking}. “Backfill historical rates” under Cash flow → “Trades” derives the figure. | In %{booking} gebucht, wie importiert — das Wertpapier notiert in %{security}, und dieser Kauf hat noch keinen Gegenwert in %{security}. Speichern lässt ihn in %{booking}. Den Gegenwert leitet „Historische Wechselkurse nachladen“ unter Cashflow → „Trades“ ab. |
| 03 ②, group (`ngettext`) | Already imported into portfolio “%{portfolio}”: %{count} entries — not taken over | Bereits im Portfolio „%{portfolio}“ importiert: %{count} Einträge — nicht übernommen |
| 03 ②, group taken over (`ngettext`, the closing act) | Already imported into portfolio “%{portfolio}”: %{count} entries — taken over | Bereits im Portfolio „%{portfolio}“ importiert: %{count} Einträge — werden übernommen |
| 03 ②, toggle | Take over anyway | Trotzdem übernehmen |
| 03 ②, toggle's consequence | books the %{count} entries a second time, in “%{target}”; “%{portfolio}” keeps its own. | bucht die %{count} Einträge ein zweites Mal, in „%{target}“; „%{portfolio}“ behält seine. |
| 03 ②, mapping count | %{count} bookings imported into “%{portfolio}” | %{count} Buchungen in „%{portfolio}“ importiert |
| 03 ③, row tail | already booked: %{booking}, entered by hand. Do not book the sale again. | bereits gebucht: %{booking}, von Hand erfasst. Den Verkauf nicht noch einmal buchen. |
| 03 ④, setup line | Buys and sells need a depot. Deposits, removals, interest, fees and taxes book on a cash account alone. | Käufe und Verkäufe brauchen ein Depot. Einlagen, Entnahmen, Zinsen, Gebühren und Steuern bucht ein Verrechnungskonto allein. |

These existing strings are reused unchanged: „ohne Umrechnung“ („not
convertible“), „bereits gebucht“ („already booked“), „nichts anzulegen“,
„Keine Zuordnung nötig: …“, the trade-price status line of the detail head,
and the no-price status line.

## Found while drawing (not filed; for the planning session to triage)

1. **The sell preview's lot table is cut at the drawer's width.**
   Bruttogewinn scrolls out of view at 1200 px, both in the live drawer and
   on the board. The table predates #1337.
2. **Je Position with two payment currencies.** Under 02 ③ the „Währung“
   column becomes the payment's currency, not the security's. A position
   paid in two currencies then needs one row per currency. The board says
   so but does not draw it.
3. **Wealth's Marktwert is in the security's currency.** The suffix is
   `row.currency_code`, so a USD position's row never adds to the EUR total
   whatever its price source. 02 ① draws EUR rows only. „The rows add up to
   the total“ holds for base-currency rows.
4. **#1333 reaches further.** The twin tag also belongs in the drawer's
   depot and account selects and in Wealth's cash table. These are listed
   on the board, not drawn.

## Not shown

- **#1293's zero-total year row.** It is a read change with no new
  anatomy.
- **#1313 A with the toggle on.** The counts return to „4 Buchungen neu“
  and the mapping selects come back.
- **#1219 with two matching bookings.** Both bookings are named and neither
  is chosen, in the correction section's existing words.
- **The 02 ① Wealth phone rows.** They show the quantity only and do not
  change.
