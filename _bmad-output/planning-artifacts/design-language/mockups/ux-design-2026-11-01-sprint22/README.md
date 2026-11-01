# Sprint 22 board — I1: explanations behind a section ⓘ, data notes clamped and folded

The board for **#1351** (idea I1, adopted by the owner on 2026-11-01). It
absorbs **#1350** (the view switcher's ⓘ opens as a plain paragraph) and
carries **#1336** (Cash flow's ⓘ panels open above the page top and past the
right edge at 390 px) and **#1342** (ⓘ panels close on Escape; the H45
picker's live region), because all four touch the ⓘ component.

**Synthetic data only.** Every frame is captured from the review instance
running the synthetic review seed (`priv/demo/finding_surfaces_seed.exs`).
No real portfolio, name or figure appears.

## The pick

**R is adopted; no other variant is drawn.** R is variant R of the
discussion prototype in [`../ux-design-2026-11-01-i1/`](../ux-design-2026-11-01-i1/README.md)
(`proposal.js`), which the owner adopted on 2026-11-01. This board draws R as
markup on the shipped pages, with the per-text classification the build
uses, so the story has a picture to build against and the design critic has
one to review against.

Found while drawing. Each correction is the default and a review comment can
flip it:

1. **A note that names rows left out of a total never folds; it only
   clamps.** R folded every attention note. On Cash flow → Trades that hid
   both exclusion notes behind „2 Achtung“, and on Wealth it hid three of the
   four. The owner's decision keeps the count of excluded rows visible
   (UX-DR25 holds; the names are one tap away), so those notes clamp and keep
   their count in their first line. As a result, Wealth's fold reads
   „1 Achtung · 1 Hinweis — Details anzeigen“, not the prototype's
   „4 Achtung · 1 Hinweis“. To flip it, comment „fold them too“.
2. **A note's remedy control stays visible under the clamp.** R clamped the
   whole note body, which put „Wechselkurse synchronisieren“ and
   „Historische Wechselkurse nachladen“ behind „mehr“. Now the text clamps
   and the button or disclosure does not (UX-DR17 clause 3: the remedy is a
   child of the note).
3. **Classification is per text, not by length.** The prototype kept
   clauses of up to 42 characters. With that rule, Fällig's first sentence
   (the set and the window) and the threshold of Ziel-Abweichungen would have been
   hidden. The table below keeps both.
4. **The section ⓘ panel is wider** than a term's ⓘ: 26 rem, still 1 rem
   inside a phone screen. A term's ⓘ keeps 18 rem.

## Files

| File | What it is |
|---|---|
| `01-i1.html` → `01-i1--1200.png` | The board, desktop: each page as the shipped frame ("Before") and with R applied ("After"), main column 1060 px as in a 1280 px window. Also holds the anatomy legend, the classification table and the must-not-move list. |
| `01-i1-390.html` → `01-i1--390.png` | The same pages, frames and tables at a 390 px phone width. The clamp, the "mehr" decision and the ⓘ shift are measured at that width. |
| `build.js` | Captures the frames from the running app, applies R as markup, and measures. |
| `board.js` | Lays out the artboard: legend, text, rule table. |
| `render.js` | Renders both HTML files to PNG. |

Both HTML files link the real `../../../../../priv/static/app.css`. The
`<style id="proposal">` block holds what the story adds to `app.css`; the
`<style id="board">` block is artboard chrome only. The pages run no script.
The "After" frames are static markup, not an injected script.

### What each frame shows

- **Vermögen** (`/portfolio`, the part above the positions table).
  - Before: the view switcher's ⓘ is open and lays its text out as a
    paragraph that pushes the KPI cards down (#1350, ⑥). Eight data notes
    are stacked in Datenqualität. The contribution's method sentences sit
    under its table.
  - After: the ⓘ is a floating panel (⑥). The three problems lead (⑤). The
    three notes that name rows left out of the totals clamp (③), and the two
    others fold (④). The formula „Beitrag = …“, „Anfangswert: der Schluss des
    Vortags“ and the restposten sentence move into the ⓘ beside „Beitrag je
    Position“ (①). „je Position in EUR, einschließlich der
    Währungsbewegung“ and the performance period line stay (②).
- **Übersicht** (`/`).
  - The value card's note keeps „Nicht in der Summe: 3 Verrechnungskonten …“
    in its first line and clamps the names (③).
  - The KPI strip's basis line already ends in its own ⓘ, so it stays whole
    (②).
  - „Abgeschlossene Trades“ keeps „Die 5 zuletzt abgeschlossenen · Ergebnis
    in EUR · FIFO über alle Depots, unabhängig von der Ansicht“ (②). Its
    p. a. rule moves into the ⓘ, which is drawn open (①).
  - „Fällig“ keeps its first sentence and moves its second (①).
  - The data-quality line is a problem and stays (⑤).
- **Cashflow → Trades** (`/cashflow?tab=realized`, the facet ⓘ open).
  - Before: the panel starts 107 px (desktop) or 116 px (phone) above the
    screen, and on the phone it runs to x = 586. The hatched band is the part
    that cannot be read (#1336).
  - After: there is no room above, so the panel opens below. On the phone it
    is shifted to stay 1 rem inside the screen (⑦). It now also holds the
    method clauses of the trades' basis line, „Einlieferungen eröffnen keinen
    Lot“ and the p. a. rule (①). The gross/net clauses stay (②). Both
    exclusion notes clamp and keep their buttons (③).

To keep the PNGs small, every frame is cut the same way in Before and After,
and each cut is marked with a dashed placeholder: the chart, the second row
of KPI cards, list rows beyond the first one to three, and the sections below
the drawn part.

## Anatomy

| | Rule |
|---|---|
| ① | **Section ⓘ.** The section's method sentences leave the page and sit in one `details.metric-tooltip` beside the heading (`.section-title` wrapper, label „Zu diesem Abschnitt“), one source line per line. A facet whose basis line already ends in an ⓘ takes them there. |
| ② | **The basis line stays.** View, period, currency, as-of, gross/net, the set of rows and a threshold stay visible (UX-DR11). Only the method clauses of a line move. |
| ③ | **Clamped data note.** The note's text is clamped to two lines, three under 560 px. „mehr“ appears only where the text is cut. A remedy control stays visible under the text. A note that names excluded rows keeps its count in its first line. |
| ④ | **Folded notes.** Two or more attention/note items in one block that do not name excluded rows fold into one line with their counts, at the highest folded severity. |
| ⑤ | **Problems stay visible.** A problem never folds and leads its block. It clamps like every note. |
| ⑥ | **#1350.** `details.view-switcher__help` also takes `metric-tooltip metric-tooltip--inline`, so its panel floats like every other ⓘ panel. |
| ⑦ | **#1336.** A panel opens upward unless there is no room above, then below. It is shifted so that both edges stay 1 rem inside the viewport. A small hook measures on toggle and sets `data-place` and `--tip-shift`. |
| ⑧ | **#1342, no picture.** Escape closes an open ⓘ and returns the focus to its summary. The H45 picker's hit count and „Kein Wertpapier passt.“ go into a `role="status"` region. |

## How the build classifies a text

Classification is per text, not per CSS class: `.hint`, `.muted` and
`.summary-basis` carry all four classes today. The tests run top to bottom,
and the first test that holds decides. Anything inside a table, a row, a
form's field help or a dialog is out of scope and does not move.

| Class | Test | What the build does | Real examples (review seed) |
|---|---|---|---|
| **Problem** | A data note at severity problem. | Always visible: it never folds and it leads its block. It clamps like every note, with „mehr“ where the text is cut. | „2 Anleihen sind auf zwei Skalen bepreist (Kurse um 100, gebuchter Preis je Stück um 1) und zählen hundertfach zu hoch in den Summen; …“ (Vermögen) · „Eine gehaltene Position wird mit Kursen bewertet, die nicht zu ihren eigenen Buchungen passen …“ (Vermögen) · „29 Wertpapiere im Katalog ohne Kurs seit 7 Tagen · eins ohne Anlageklasse · …“ (Übersicht) |
| **Basis clause** (stays visible) | Names a parameter the figure was computed with: view, period or window, currency, as-of or computed-at, gross/net, the set of rows or depots, a threshold. It would read differently if the operator chose another parameter, not if the data changed. | Stays as the basis line. A clause that mixes a parameter with a method word stays whole. | „Ansicht Alles · Rendite über 1J bis 01.11.2026 · in EUR · Kurse: der neueste über die gehaltenen Positionen“ (Übersicht, ends in its own ⓘ) · „FIFO über alle Depots, unabhängig von der Ansicht“ (Übersicht) · „Gebühren und Steuern in Einstand und Erlös · Erträge während der Haltedauer nicht enthalten“ (Cashflow, gross/net) · „Datierte Fakten zu jedem Wertpapier im Katalog — gehalten oder nicht —, die in den nächsten 30 Tagen anstehen.“ (Übersicht, set and window) · „Kategorien, die mehr als ±5 pp von ihrem Soll-Gewicht abweichen.“ (Übersicht, threshold) |
| **Data fact** (a data note, clamped) | Changes when the stored records change: a count, a name, an amount, a record's date, a yes/no. | Inside a data note, it clamps. It folds when two or more attention/note items share a block, unless the note names rows left out of a total (UX-DR25); then it only clamps. Outside a note, it stays where it is. | „Nicht in der Summe: 3 Verrechnungskonten ohne Wechselkurs zu EUR — USD Settlement (1.850,00 USD), …“ (Übersicht, excluded rows: clamps, never folds) · „11 gehaltene Positionen werden zum letzten Handelspreis bewertet, die Gesamtsumme ist daher nicht aktuell: …“ (Vermögen, folds) · „2 gehaltene Positionen werden mit Kursen bewertet, die älter als 7 Tage sind; …“ (Vermögen, folds) |
| **Method sentence** (moves into the section ⓘ) | True on any instance with any data: how a figure is computed, what a term means, what a control does. | Moves into the section's ⓘ: the heading's, or the facet's where the section has no heading. Exception: a sentence inside a note that says why its remedy can or cannot act stays in the note (UX-DR25 clause 3) and clamps with it, for example „Die tägliche Synchronisation der Wechselkurse kann einen vergangenen Tag nicht nachtragen. …“ | „Beitrag = Endwert − Anfangswert − Zu-/Abflüsse + Erträge − Kosten · Anfangswert: der Schluss des Vortags“ (Vermögen) · „p. a. erst ab 365 Tagen Haltedauer und nur, wo ein Zinssatz die Zahlungen löst“ (Übersicht, Cashflow) · „Ein als Zeitraum oder Monat angegebener Termin gilt als fällig, sobald irgendein Tag, auf den er fallen kann, im Horizont liegt.“ (Übersicht) · „Einlieferungen eröffnen keinen Lot“ (Cashflow) |

### `.hint` / `.muted` / basis texts that carry data facts and must NOT move

These were scanned on every page of the review seed.

| Text | Where |
|---|---|
| „Wieder eingespielt? Ja“ | Snapshots, comparison: `small.hint[data-role=cost-recovery]` |
| „Buy-and-hold der am 03.08.2026 eingefrorenen Bestände: 47.301,57 → 47.834,43 EUR“ | Snapshots, comparison: `small.hint` |
| „netto, alle Kosten enthalten“, „Gebühren und Steuern auf Handelsgeschäfte ausgenommen“ | Snapshots, comparison: `small.hint`, the basis of a stat |
| „31.12.2025 · Steuerjahr 2025 · erfasst · Erfasst von: Agent“ | Steuern, recorded statements: `span.hint` |
| „Steuerfreier Verkaufsspielraum bei diesem Institut: 0,00.“ | Steuern, recorded statements: a figure in `p.summary-basis` |
| „Freistellungsauftrag 640,00 von 1.000,00 verbraucht · Stand 31.12.2025 · …“ | Steuern, budget: `[data-role=budget-basis]` |
| „netto 120,00“ | Cashflow, Erträge, Top-Beiträge: `span.muted` |
| „Standard-Ansicht“ | Vermögen, view switcher: `span.hint[data-role=default-view-marker]` |
| „Σ Soll oberste Ebene: 105,0%“ | Allokation: a figure in `[data-role=allocation-basis]` |
| „Broker Nord Verrechnung, Broker Süd Verrechnung, …“ | Ansichten, Buckets: the account names in `[data-role=assignment-basis]`. Its first sentence is a method sentence. |
| „Anlageklasse Fonds“ | Wertpapier, Überblick: `[data-role=overview-basis]` |
| „am Ende nicht mehr im Bestand“, „zu Beginn nicht im Bestand“ | Vermögen, Beitrag je Position: row text. Nothing in a table or a row moves. |

## Strings

The build needs these German strings; each was checked against
`priv/gettext/de/LC_MESSAGES/default.po`.

- „Zu diesem Abschnitt“ is new (the section ⓘ's `aria-label`). It follows
  „Zu dieser Facette“ and „Zu dieser Zahl“.
- „mehr“ is new. The existing „weniger“ (msgid "Show fewer") is its
  counterpart once a note is expanded.
- „Achtung“ and „Hinweis“ exist (the data-note words). The plural
  „Hinweise“ and the fold's toggle „Details anzeigen“ (the wording of #1351)
  are new.
- The moved and kept clauses are today's wording, unchanged. Each split
  basis line is one msgid today (for example the Trades basis line, and
  Fällig's two sentences in one msgid), so the story cuts it into one msgid
  per clause. No translation changes.

## How to regenerate

The review instance must run on port 4003 with the synthetic review seed (the
seed's header gives the database). The build only reads: it sends GET
requests and toggles `<details>` elements in the client, so it writes nothing.
Run from this folder:

```bash
node build.js    # captures the three pages twice at 1280 and 390 px, writes both HTML files
node render.js   # renders 01-i1--1200.png and 01-i1--390.png
```

`BASE=http://localhost:4000 node build.js` points the build at another
instance. Run the build only against an instance on the synthetic seed: the
frames are its markup verbatim.

## Not shown

- **#1342**: Escape and the live region change no pixels. The Imports
  picker (H45) is not drawn.
- The **expanded** state of a clamped note („mehr“ pressed, showing
  „weniger“) and an **opened** fold are not drawn. Their content is the
  "Before" note at full length.
- **Dark mode** is not drawn. The fold line uses the attention note's
  tokens, which already have dark values.
- The ⓘ's **coarse-pointer** sizes and the 44 px ring are not drawn (the
  render uses a fine pointer). They are unchanged.
