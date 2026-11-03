# Sprint 23 board, Lane I: I1's later pages before and after

The board commit of Sprint 23's Lane I (idea I1; #1351 closed with Sprint
22's three pages). It draws the nine pages Sprint 22's shrink order cut:

- Wealth's Allocation tab;
- the security page;
- Income (Cash flow → Trades), with Sprint 22 R5's exclusion sentences
  re-read against Sprint 23 board 02 ①d;
- Snapshots, Tax, Views, Classifications, Imports and Risk.

It also carries #1339 (the „Daten als Tabelle“ disclosure on Wealth and the
matched-securities list on Imports), and #1362's S2 line on Classifications.

**Synthetic data only.** Every frame is captured from the review instance
running the synthetic review seed (`priv/demo/finding_surfaces_seed.exs`).
The Imports frame previews the synthetic `priv/demo/portfolio_performance_demo.json`;
a preview stores nothing before its confirmation. R5's three reasons the
seed lacks carry board 02 ①d's synthetic names (Saltmarsh Mining plc,
Brightwater Tools AG, Fernhill Bonus AG). No real portfolio, name or figure
appears.

## The pick it inherits

**Nothing is picked here.** The anatomy is signed: variant R of the I1
prototype ([`../ux-design-2026-11-01-i1/`](../ux-design-2026-11-01-i1/README.md),
`proposal.js`), adopted by the owner on 2026-11-01. Sprint 22's board
([`../ux-design-2026-11-01-sprint22/`](../ux-design-2026-11-01-sprint22/README.md))
added its four Q1 corrections, and DESIGN.md's amendment of 2026-11-02
records them as built:

1. A note that names rows left out of a total never folds; it only clamps
   and keeps every count in its first line.
2. A note's remedy control stays visible under the clamp.
3. Classification is per text, not by length.
4. The section ⓘ panel is 26 rem wide.

Each page here is a conformance repair. The "After" frames use the markup
Sprint 22 built (`AppShell.section_info`, `data_note` with `clamp`,
`data_note_fold`), so `app.css` draws them as shipped.

Found while drawing, three readings of the rule. Each is the default, and
a review comment flips it:

1. **A section with no heading ends its kept basis line in the section's
   ⓘ** (the security page's Chart, Kurse, Research and Termine tabs), as a
   facet's basis line does on Cash flow. The line becomes a `div` with the
   same class and role, because a `<details>` is not phrasing content (Cash
   flow's `facet-basis` is a `div` for the same reason). The alternative, a
   heading per tab, repeats the tab's label.
2. **A method line that the heading's ⓘ already says leaves without a copy**
   (⑥): Views' two basis lines, and on Income the definition of a missing
   rate. Appending it would make the ⓘ say it twice.
3. **A data note that states no data fact is a method sentence** and moves
   into the ⓘ: Snapshots' „Der Vergleich ist brutto und nur Kursentwicklung
   — Dividenden sind noch nicht enthalten.“ (it also repeats the basis line).

## Files

| File | What it is |
|---|---|
| `01-i1-later.html` → `01-i1-later--1200.png` | The board, desktop. Each page is drawn as the shipped frame ("Before") and with R applied ("After"), main column 1060 px as in a 1280 px window. Also holds the anatomy legend and the found-while-drawing list. |
| `01-i1-later-390.html` → `01-i1-later--390.png` | The same frames at a 390 px phone width. The clamp, „mehr“ and the ⓘ shift are measured at that width. |
| `build.js` | Captures the frames from the running app, applies R as markup, and measures. Adapted from Sprint 22's `build.js`. |
| `board.js` | Lays out the artboard: the legend, each page's text, the findings. |
| `render.js` | Renders both HTML files to PNG (Sprint 22's, with the new file names). |

Both HTML files link the real `../../../../../priv/static/app.css`. The
`<style id="proposal">` block holds what the page stories add to `app.css`.
That is two rules: a category value's cell note (⑨), and the gap before an
ⓘ that ends a basis line (①). The `<style id="board">` block is artboard
chrome only. The pages run no script; the "After" frames are static markup.

To keep the PNGs small, every frame is cut the same way in Before and After,
and each cut is marked with a dashed placeholder: charts, the securities
list above the detail pane, list rows beyond the first few, entry forms,
and sections that do not change.

## Anatomy (pins on the board)

| | Rule |
|---|---|
| ① | **Section ⓘ** (Sprint 22 ①). Method sentences leave the page for one ⓘ beside the heading, label „Zu diesem Abschnitt“, one line each. New: a section with no heading ends its kept basis line in the ⓘ (reading 1). |
| ② | **The basis line stays** (UX-DR11). Only a line's method parts move; a mixed clause stays whole. |
| ③ | **Clamped data note** (Sprint 22 ③). Two lines, three under 560 px, „mehr“ only where cut. Its remedy control (a button, a disclosure, a link) sits in `.data-note__actions` below the text. |
| ④ | **Folded notes** (Sprint 22 ④). No block on these nine pages holds two or more foldable notes on the review seed, so nothing folds here. |
| ⑤ | **Problems lead** and never fold; they clamp. |
| ⑥ | **A method line the heading's ⓘ already says leaves without a copy** (reading 2). |
| ⑦ | **#1339.** The disclosure takes an `id` and `phx-hook="DisclosureState"`, so a LiveView patch no longer folds it shut. |
| ⑧ | **A count leads.** Snapshots' gaps note gains its count. On Income, with two or more reasons, the lead carries every count once and each reason names its sales without a second count (#1359's count-lead line). |
| ⑨ | **#1362's S2 line.** A category whose members are not all priced shows the sum of the priced ones and names how many it leaves out, as the category result's API read does (ADR-0041 §5), instead of „—“. |

## Per page

The classification is Sprint 22's, applied text by text (DESIGN.md,
amendment of 2026-11-02, "The classification rule"). Out of scope
everywhere, and not listed again: text inside a table or a row, a form's
field help, a dialog, and a disclosure's own body.

### Vermögen → Allokation (`/portfolio?tab=allocation`)

| Text (German UI) | Where | Class | Outcome |
|---|---|---|---|
| „Plan auf Strategies · Σ Soll oberste Ebene: 105,0% · Ansicht Alles · Stand 03.11.2026“ | `[data-role=allocation-basis]` | basis, with a data fact | stays whole (②) |
| „Die Top-Level-Ziele des Plans summieren sich auf 105,0 % — mehr als 100 %. Die Drift steuert weiter gegen die gespeicherten Gewichte; den Plan auf der Klassifizierungsseite kürzen.“ | `plan-overshoot-note` (attention) | data fact with its remedy | clamps (③). The link leaves the sentence for the actions as „Plan auf der Klassifizierungsseite kürzen“, and the sentence ends with a full stop. Two new strings. |
| target-conflict note (problem), stale-target note (attention) | `allocation-findings` | data facts with their remedies | not on the seed. The same treatment: the problem leads, the link goes to the actions, each needs a command of its own. |
| „Kein Soll-Plan für diese Ansicht — es wird nur die Ist-Aufteilung gezeigt.“ with its link | `[data-role=no-plan-hint]` | data fact with its remedy | not on the seed; stays |
| „Kategorie, Wert, Ist, Soll und Drift — der Sunburst als Zeilen.“, „Alle 6 Kategorien angezeigt.“, „30,6% der Bestände sind keiner Kategorie zugeordnet. …“ | inside „Daten als Tabelle“ | a disclosure's own body | out of scope, stays |
| „Unterkategorien: 15,0% von 15,0%“, the Drift ⓘ „Soll vs. Ist: …“ | the drift table | in a table | out of scope, stays |
| the view switcher's ⓘ, „Standard-Ansicht“ | page head | built in Sprint 22 | unchanged |

**Moves into an ⓘ:** nothing. **#1339 (⑦):** captured, not drawn. The
disclosure was opened and „Alle aufklappen“ pressed; the patch folded it
shut. With the hook it stays open.

### Wertpapier (`/securities/:id`)

| Text (German UI) | Where | Class | Outcome |
|---|---|---|---|
| „Kurs passt nicht zu den Buchungen: Kauf 06.06.2026 zu 4,12 EUR · Kurs …, das 10,00-Fache (…). Wert oder Einstand dieser Position ist daher falsch. Die Kursquelle prüfen (Ticker, Börse), dann die Buchung: Kurse · Transaktionen“ | Überblick, `implausible-quote-note` (problem), Tamarisk Systems Inc. | problem | leads, clamps (⑤); „Kurse · Transaktionen“ go to the actions |
| „Kein aktueller Kurs — in den Summen zum letzten eigenen Handelspreis von 71,00 EUR (01.07.2025) bewertet.“ | pane head, `detail-valuation-status` | data fact | stays |
| „Anlageklasse Aktie“ / „Anlageklasse ETF · frühere ISIN … · zusammengeführt am …“ | Überblick, `[data-role=overview-basis]` | data fact | stays (must-not-move) |
| „nur Kurs“, „+914,6% · gegen den Durchschnittseinstand“, „Demo Depot“ | Überblick, metric sub-lines | basis / data fact | stay |
| „Über alle Depots“ · „Gebühren und Steuern im G/V, nicht in Ø Kauf und Ø Verkauf“ · „Erträge während der Haltedauer nicht enthalten“ | Trades, `[data-role=trades-basis]` | basis (depots, gross/net) | stays (②) |
| „Einlieferungen eröffnen keinen Lot“, „p. a. erst ab 365 Tagen Haltedauer und nur, wo ein Zinssatz die Zahlungen löst“ | the same line | method | **move** into the ⓘ beside „Abgeschlossene Trades (FIFO)“ (①) |
| „1 Trade ohne Umrechnung: … Abhilfe: ein Wechselkurs für den 17.04.2026 — „Historische Wechselkurse nachladen“ unter Cashflow → „Trades“ … — oder der Gegenwert in USD an der Buchung.“ | Trades, `trades-unavailable` (attention), Arbolia Inc. | data fact; its „Abhilfe“ says where the remedy acts | clamps (③); the remedy sentence stays in the text (Sprint 22's exception) |
| „Über die eigenen splitbereinigten Schlusskurse dieses Wertpapiers in USD, nie umgerechnet.“ | Chart, `[data-role=metrics-basis]` | basis (series, currency) | stays (②) and ends in the ⓘ (①, reading 1) |
| „Ein Tag ohne gespeicherten Schlusskurs erzeugt keine Renditebeobachtung; nichts wird fortgeschrieben und differenziert.“ · „Die Volatilität ist die Grundgesamtheits-Standardabweichung … mit der Wurzel aus 252.“ · „Berichtet, nicht bewertet: hier wird kein Signal, kein Rating und keine Empfehlung abgeleitet.“ | the same line | method | **move** into that ⓘ |
| „kein Fenster gemessen · 0 Beobachtungen“, „365 Tage · 03.11.2025 – 03.11.2026 · 0 Beobachtungen“ | Chart, metric sub-lines | basis (window, count) | stay |
| „Zeitraum 1J · wie im Diagramm“ | Kurse, `quotes-range-basis` | basis | stays |
| „Kursbasis: wie erfasst.“ (twice) | Kurse, `[data-role=quotes-basis]` | basis | stays **once** (②, found while drawing 1) |
| „Die Spalte Gespeichert zeigt die unveränderten Werte.“ · „Wo ein Split einen Kurs angepasst hat, zeigt „gespeichert“ darunter den unveränderten Wert.“ | the same line | method | **move** into the line's ⓘ (①) |
| „Ein manueller Kurs in der gespeicherten Historie, am 03.11.2026; … Ein manueller Kurs hat Vorrang: Die Kursaktualisierung lässt ihn stehen, bis er freigegeben wird.“ | Kurse, `manual-quotes-note` (note), Harborline Freight Inc | data fact; the second sentence says why the remedy is needed | clamps (③); „Freigeben…“ goes to the actions |
| „Datierte, belegte Einträge zu diesem Wertpapier.“ | Research, `p.detail-tab-hint` | basis (the set) | stays (②) |
| „Einträge werden nie geändert oder entfernt; ein falscher Befund wird durch einen Widerruf zurückgezogen, der ihn ersetzt, und beide bleiben sichtbar.“ | the same line | method | **moves** into the line's ⓘ (①) |
| „Datierte Kalenderfakten zu diesem Wertpapier.“ | Termine, `[data-role=events-basis]` | basis (the set) | stays (②) |
| „Ein Termin bucht nichts: Wird eine Dividende tatsächlich gezahlt, wird sie wie immer über das Ledger gebucht und der Termin als bestätigt markiert.“ | the same line | method | **moves** into the line's ⓘ (①) |
| „Eine Kategorie je eigenem Baum; …“ / „Klassifizierungen verwalten“ | Klassifizierungen | already behind its ⓘ / a control | unchanged |
| „Kursbeitrag — …“ | Trades, Bestände | already behind a labelled ⓘ | unchanged |
| „Noch keine These erfasst.“, „Noch keine persönliche Notiz.“, „Noch keine Einträge.“, „Für dieses Wertpapier sind keine Termine erfasst.“ | empty states | data fact | stay |

Transaktionen and Bestände carry no text outside their tables.

### Income: Cash flow → Trades, Sprint 22 R5 re-read (`/cashflow?tab=realized`)

Sprint 22 built Cash flow under the rule, so the page is redrawn only where
R5 and #1359's two lines reach. The frames show the note expanded, as board
02 ①d draws it.

| Text (German UI) | Where | Class | Outcome |
|---|---|---|---|
| „Aus jeder Summe ausgeschlossen: 1 Verkauf ohne gespeicherten Wechselkurs; 1 Verkauf, dessen Kauf keinen Gegenwert in seiner Währung hat; 1 Verkauf in einer dritten Währung; 1 Verkauf, dessen Kauf in einer anderen Währung bezahlt wurde; 1 Verkauf, dessen Kauf einen Betrag von null hat.“ | `realized-excluded-counts` | data fact, every count | stays and leads (⑧) |
| „1 Verkauf konnte nicht konvertiert werden — kein gespeicherter Wechselkurs an seinem Schlussdatum — und ist aus jeder Summe ausgeschlossen: Harborline Freight Inc.“ (and the four other reason sentences, R5's three among them) | `realized-excluded-*` | the names are a data fact; the count repeats the lead; the clause between the dashes is method | with two or more reasons each becomes „‹reason›: ‹names›.“, for example „Dritte Währung: Saltmarsh Mining plc.“ The count is not repeated. One reason alone keeps today's sentence. |
| the clause between the dashes of the four reasons other than a missing rate | the same spans | method (what the reason means) | **moves** into the facet's ⓘ after a blank line, one reason per line (①) |
| „kein gespeicherter Wechselkurs an seinem Schlussdatum“ | the no-rate span | method | leaves without a copy: the facet's ⓘ already says it (⑥) |
| „Die tägliche Synchronisation der Wechselkurse kann einen vergangenen Tag nicht nachtragen. …“ and „Historische Wechselkurse nachladen“ | `fx-backfill-reason`, the actions | method that says why the remedy acts (the exception), and its control | stay, but render **only while a reason the backfill fixes is present**: no stored rate, or a buy without a figure in the sale's currency. With R5's reasons alone the note offers no remedy (#1359's backfill line). |

On board 02 ①d's question, the two sentences R5 added: each is a reason
sentence like the others, so each takes the same shape. Its names stay in
the note and its definition goes to the ⓘ. Its „no rate fixes it“ remains
in that definition, and the backfill and its button no longer follow it.

The Overview's trades card (`trades-card-excluded`) has the same lead and
sentences. It is not one of Lane I's pages, so its half of #1359's
count-lead line stays open on that list.

### Snapshots (`/snapshots`, the comparison)

| Text (German UI) | Where | Class | Outcome |
|---|---|---|---|
| „seit 05.08.2026“ · „in EUR“ · „brutto, nur Kursentwicklung“ | `[data-role=comparison-basis]` | basis | stays (②) |
| „Transaktionskosten = seitdem auf Handelsgeschäften gebuchte Gebühren und Steuern; eigenständige Gebühren, Steuern und Quellensteuer auf Dividenden bleiben auf beiden Seiten in der Rendite“ | the same line | method (a definition) | **moves** into a new ⓘ beside „Vergleich gegen „Vor Umschichtung““ (①) |
| „Der Vergleich ist brutto und nur Kursentwicklung — Dividenden sind noch nicht enthalten.“ | `comparison-limitation` (note) | method; no data fact (reading 3) | **moves** into the same ⓘ; the note goes |
| „Nicht enthalten (kein verwendbarer Kurs oder Wechselkurs zum Stichtag): Orchid Bay Pharmaceuticals plc, … (20 names)“ | `comparison-gaps` (attention) | data fact, names excluded rows | gains its count: „Nicht enthalten: 20 Positionen ohne verwendbaren Kurs oder Wechselkurs zum Stichtag — …“ (⑧, one new string); clamps, never folds (③) |
| „netto, alle Kosten enthalten“, „Buy-and-hold der am 05.08.2026 eingefrorenen Bestände: 47.301,57 → 47.834,43 EUR“, „Gebühren und Steuern auf Handelsgeschäfte ausgenommen“, „Wieder eingespielt? Ja“ | the stats | basis / data fact | stay (must-not-move) |
| „Alles · 05.08.2026“ | `comparison-scope` badge | basis | stays |
| „Ein Snapshot friert die Bestände eines Stichtags ein …“ | the „Snapshots“ heading's ⓘ | already behind its ⓘ | unchanged |

### Steuern (`/tax`)

| Text (German UI) | Where | Class | Outcome |
|---|---|---|---|
| „Freistellungsauftrag 640,00 von 1.000,00 verbraucht · Stand 31.12.2025 · Beispiel Direktbank (Abrechnung von: Agent), Example Bank“ | `[data-role=budget-basis]` | basis / data fact | stays (must-not-move) |
| „Veraltet — 12 steuerrelevante Buchungen seit dem Abrechnungsdatum verbrauchen Verlusttöpfe oder Freistellungsauftrag.“ | `budget-stale` (attention) | data fact | clamps (③); „Neue Abrechnung erfassen“ goes to the actions |
| „31.12.2025 · Steuerjahr 2025 · erfasst · Erfasst von: Agent“, „Steuerfreier Verkaufsspielraum bei diesem Institut: 2.860,00.“ | each statement | data fact | stay (must-not-move) |
| „Abgeführte Kapitalertragsteuer 800,00 gegen 878,00 aus der Abrechnung rekonstruiert — Abweichung 78,00. Zahl gegen die Abrechnung prüfen.“ | `statement-finding` (attention) | data fact | clamps (③); „Gegen die Abrechnung prüfen“ goes to the actions (found while drawing 2) |
| „Diese Töpfe werden aus der Abrechnung der Bank übernommen, …“ | the budget's ⓘ | already behind its ⓘ | unchanged |
| „Was je Institut beauftragt wurde — …“ | the orders disclosure | a disclosure's own body | out of scope |
| „Beträge ohne Vorzeichen; ein leeres Feld zählt als null.“, „Ein Verlusttopf ist …“ | the entry forms | field help | out of scope |

**Moves into an ⓘ:** nothing.

### Ansichten (`/buckets`)

| Text (German UI) | Where | Class | Outcome |
|---|---|---|---|
| „Gespeicherte Ein-/Ausschlussfilter über Buckets · gelten im Ansichtsumschalter auf Vermögen“ | `[data-role=views-basis]` | method; the „Ansichten“ ⓘ already says both | **leaves without a copy** (⑥) |
| „Überlappende Tags an Depots, Verrechnungskonten und Positionen · Werte je Bucket sind keine Summe“ | `[data-role=buckets-basis]` | method; the „Buckets“ ⓘ already says both | **leaves without a copy** (⑥) |
| „Standard-Buckets werden an der Kontozeile gesetzt → Konten & Depots. Broker Nord Verrechnung, … haben keinen Standard-Bucket.“ | `[data-role=assignment-basis]` | the pointer to the remedy, then a data fact | stays whole (must-not-move; found while drawing 4) |
| „Alle Depots, Verrechnungskonten und Positionen · keine Filter“, „1 Position direkt: Bitcoin · kein Standard“ | rows | in a row | out of scope |

### Klassifizierungen (`/classifications/1`, Anlageklasse)

| Text (German UI) | Where | Class | Outcome |
|---|---|---|---|
| „1 Wertpapier ist noch keiner Kategorie zugeordnet und fließt nicht in die SOLL-IST-Allokation ein.“ | `assignment-nudge` (attention) | data fact, names rows left out | clamps, never folds (③); „Nicht zugeordnet“ goes to the actions |
| „Ansicht Alles · in EUR · Ergebnis: heutige Zusammensetzung, keine Periodenrendite · Kurse: der neueste, ohne Kurs der letzte eigene Handelspreis“ | `[data-role=category-result-basis]` | basis | stays whole; it ends in its own ⓘ (②) |
| „3 Positionen sind in „Einstand“ und „Ergebnis“ nicht enthalten.“ | `category-result-excluded` (attention) | data fact, names rows left out | clamps, never folds (③); „Die 3 Positionen“ goes to the actions |
| „—“ in Wert for Equity and Bond | the tree's category rows | a figure (#1362's S2 line) | the sum of the priced members, „ohne N Position(en)“ beneath (⑨, one new string). Bond reads 14.897,35, as the API reports for that category. Equity reads 24.761,93 „ohne 2 Positionen“ by the same rule; that figure is the board's own sum of the member rows and was not read from the API. |
| „+12 ohne Bestand“, „Kinder Σ 15%“ | the tree, the Soll editor | row text / in a table | out of scope |

### Import, the preview (`/imports`)

| Text (German UI) | Where | Class | Outcome |
|---|---|---|---|
| „CSV oder JSON v1 · max. 20 MB · vor der Bestätigung wird nichts gespeichert“ | the drop zone | a form's field help | out of scope, stays |
| „Quellformat: JSON“ | the preview | basis | stays |
| „Alle 12 Einträge sind bereits importiert. Der Import legt nichts an: keine Buchung, kein Konto, kein Depot, kein Wertpapier.“ | `nothing-to-import` (note) | data fact | clamps (③); it fits at 1280 px |
| „Konfigurierte Wertpapiere, die dieser Import nicht berührt — Diese Wertpapiere tragen Strategie-Konfiguration …, passen aber zu keinem Eintrag dieser Datei — vermutlich eine Umbenennung oder ein ISIN-Wechsel in Portfolio Performance. Abhilfe: …“ and the linked names | `unmatched-config` (attention) | data fact with its remedy sentence | clamps (③); the remedy sentence stays in the text; the two security links, where the remedy is made, go to the actions |
| „Eintrag 2: Einlieferung mit Steuererstattung 0,40: …“ | `parser-warnings` (attention), other demo files | data fact | clamps the same way; not drawn |
| „Optional: ein Bucket-Tag …“, „Ein bestehender Bucket mit diesem Namen wird wiederverwendet. …“ | the bucket-tag field | field help | out of scope |
| „(über ISIN zugeordnet)“, „PP-Konto“, „PP-Depot“ | the mapping rows | in a row | out of scope |

**Moves into an ⓘ:** nothing. **#1339 (⑦):** „7 Wertpapiere passen zu
bestehenden Einträgen“ is drawn closed in Before, as a patch (a mapping
change) leaves it, and open in After. It was not captured as a patch
because the change would start a recount.

### Risiko (`/risk`)

| Text (German UI) | Where | Class | Outcome |
|---|---|---|---|
| „Ausgewertet beim Lesen, Stand 03.11.2026, auf der steuerbaren Basis der Ansicht „Alles“.“ | `[data-role=policy-rules-basis]` | basis (as-of, view) | stays (②) |
| „Jede Regel nennt die Kennzahl, aus der sie liest; eine Zahl, die sich nicht lesen lässt, ist nicht bestimmbar, nie eingehalten.“ · „Ein Befund sagt nicht, was zu tun ist.“ | the same line | method | **move** into a new ⓘ beside „Eigene Regeln“ (①) |
| „Grundlage: die um Zahlungen bereinigten täglichen Renditefaktoren der TTWROR-Kette, in EUR, annualisiert mit √365 — eine Einzahlung ist keine Rendite.“ | `[data-role=risk-basis]` | mixed: series and currency with method | stays whole (②) |
| „Ein Tag ohne Renditebasis liefert keine Beobachtung, nie eine Null.“ · „Korrelationen rechnen zuerst in EUR um und laufen über die 10 größten Einzelpositionen.“ | the same line | method | **move** into a new ⓘ beside „Kennzahlen des Portfolios“ (①) |
| „1 Jahr · 365 Beobachtungen · min. 20“, „05.06.2026 → 16.06.2026 · erholt 14.07.2026“, „risikofreier Satz 0,00 % · Rendite je Risikoeinheit“, „52 von 60 Beobachtungen“ | stat sub-lines | basis / data fact | stay |
| „0 · niedrig unter 1.500 · ab 2.500 konzentriert · 10.000“ | HHI | basis (thresholds) | stays |
| „· allgemeine Schwellen, keine eigenen Regeln“ | „Größte Einzelpositionen“ heading | basis | stays |
| „Keine Obergrenze konfiguriert — es gibt nichts zu überschreiten.“ | `[data-role=risk-caps]` empty state | data fact | stays (②) |
| „Obergrenzen werden pro Abfrage über die API gesetzt.“ | the same | method | **moves** into a new ⓘ beside „Anlageklassen-Obergrenzen“ (①) |
| „Pearson-Korrelation der Tagesrenditen über ein Jahr …“ | the correlations disclosure | a disclosure's own body | out of scope |

## Texts that carry data facts and must NOT move

These were found on these pages and are added to Sprint 22's list:

| Text | Where |
|---|---|
| „Plan auf Strategies · Σ Soll oberste Ebene: 105,0% · …“ | Allokation, `[data-role=allocation-basis]` |
| „Kein aktueller Kurs — in den Summen zum letzten eigenen Handelspreis von 71,00 EUR (01.07.2025) bewertet.“ | Wertpapier, pane head |
| „Anlageklasse ETF · frühere ISIN XS0000000017 (bis 15.06.2025) · zusammengeführt am …“ | Wertpapier, Überblick, `[data-role=overview-basis]` |
| „kein Fenster gemessen · 0 Beobachtungen“ and the other metric sub-lines | Wertpapier, Chart |
| „Veraltet — 12 steuerrelevante Buchungen …“ | Steuern, `budget-stale` (a note: clamps, never moves) |
| „Broker Nord Verrechnung, … haben keinen Standard-Bucket.“ with its pointer „→ Konten & Depots“ | Ansichten, `[data-role=assignment-basis]` |
| „Keine Obergrenze konfiguriert — es gibt nichts zu überschreiten.“ | Risiko, the caps' empty state |
| „52 von 60 Beobachtungen“, „erholt 14.07.2026“ | Risiko, stat sub-lines |
| „Quellformat: JSON“ | Import, the preview |

## Strings

Each was checked against `priv/gettext/de/LC_MESSAGES/default.po`.
`build.js` refuses to run if a "new" msgid already exists there (`NEW_CHECK`).

**Reused** (in the catalogue): „Zu diesem Abschnitt“ (msgid "About this
section"), „mehr“ / „weniger“ (`data-note clamp`), „Details anzeigen“ /
„Details ausblenden“, „%{count} Achtung“ / „%{count} Hinweis“ (`data-note
fold`), „Aus jeder Summe ausgeschlossen: %{counts}.“ and R5's five reason
labels („%{count} Verkauf in einer dritten Währung“ …).

**New: 15 msgids**, English drafts with their German:

| # | msgid (draft) | German |
|---|---|---|
| 1 | `The plan's top-level targets sum to %{sum} % — more than 100 %. Drift keeps steering against the stored weights.` | „Die Top-Level-Ziele des Plans summieren sich auf %{sum} % — mehr als 100 %. Die Drift steuert weiter gegen die gespeicherten Gewichte.“ |
| 2 | `Trim the plan on the Classifications page` | „Plan auf der Klassifizierungsseite kürzen“ |
| 3 | `Not included: %{count} position with no usable quote or exchange rate at the as-of date — %{names}` (plural `… %{count} positions …`) | „Nicht enthalten: %{count} Position ohne verwendbaren Kurs oder Wechselkurs zum Stichtag — %{names}“ / „… %{count} Positionen …“ |
| 4 | `%{reason}: %{securities}.` | „%{reason}: %{securities}.“ |
| 5 | `%{reason}: %{securities}` (the last name ends in a full stop, as `StoredText.ending_on` does) | „%{reason}: %{securities}“ |
| 6 | `No stored rate` | „Ohne gespeicherten Wechselkurs“ |
| 7 | `Buy without a figure in the sale's currency` | „Kauf ohne Gegenwert in der Währung des Verkaufs“ |
| 8 | `Third currency` | „Dritte Währung“ |
| 9 | `Buy paid in another currency` | „Kauf in anderer Währung bezahlt“ |
| 10 | `Buy of amount zero` | „Kauf mit Betrag null“ |
| 11 | `Buy without a figure in the sale's currency: a buy the sale closes has no figure in the sale's currency.` | „Kauf ohne Gegenwert in der Währung des Verkaufs: Ein Kauf, den der Verkauf schließt, hat keinen Gegenwert in der Währung des Verkaufs.“ |
| 12 | `Third currency: the sale or a buy it closes is priced in a currency that is neither the security's nor its account's; no rate fixes it.` | „Dritte Währung: Der Verkauf oder ein Kauf, den er schließt, ist weder in der Währung des Wertpapiers noch in der seines Kontos bepreist; kein Wechselkurs behebt das.“ |
| 13 | `Buy paid in another currency: a buy the sale closes was paid in another currency than the sale's, which no stored figure bridges; no rate fixes it.` | „Kauf in anderer Währung bezahlt: Ein Kauf, den der Verkauf schließt, wurde in einer anderen Währung als der des Verkaufs bezahlt, die kein gespeicherter Wert überbrückt; kein Wechselkurs behebt das.“ |
| 14 | `Buy of amount zero: a buy the sale closes has an amount of zero, which the rate backfill does not complete.` | „Kauf mit Betrag null: Ein Kauf, den der Verkauf schließt, hat einen Betrag von null, den das Nachladen der Kurse nicht ergänzt.“ |
| 15 | `without %{count} position` (plural `without %{count} positions`) | „ohne %{count} Position“ / „ohne %{count} Positionen“ |

The German of 11 to 14 is taken from R5's shipped sentences, clause for
clause. The allocation's two other notes need two more strings in the shape
of 1 and 2 when their story lands; the seed has neither note.

**Moved and kept clauses** keep today's wording. A split line is one msgid
today (for example the trades' basis line on the security page, the
metrics line, Risk's two lines), so the story cuts it into one msgid per
clause or sentence. No translation changes. The duplicate „Kursbasis: wie
erfasst.“ loses its second rendering.

## Lines the page stories fix

From the open polish trackers: #1355 Imports, #1359 Cash flow and Income,
#1362 Classifications and targets, #1365 Securities and the security page,
#1366 Wealth. Snapshots, Tax, Views and Risk have no tracker of their own;
#1321 names Risk and Snapshots.

"Rendering" says whether the fix changes what the screen shows. Where it
does and this board does not draw it, the story draws its frame before its
code, or the line stays open with that reason.

**Allocation (#1366):**

- #1339, the „Daten als Tabelle“ disclosure. Fixed; rendering: no. The
  disclosure only stays open (⑦).
- Wealth loads the twin accounts' portfolio tags in the page process. Fixed
  by the Allocation story, which touches `portfolio_live.ex`; rendering: no.
- #1322, the holdings table scrolls sideways at 1200 px. Not fixed:
  rendering yes, it needs a board, and it is on the Bestände tab, which is
  not Lane I's.

**Security page (#1365):**

- The Trades tab names only the first of two blocking reasons. Fixed:
  rendering yes, the note names each blocking lot. Not drawn: the seed has
  no such trade, and the note keeps the clamped shape drawn here.
- #1321 („300,00EUR“) on this page. Fixed: rendering yes, a space before
  the currency.
- #1334, a flag avatar for „XS“. Fixed (the detail pane's avatar): rendering
  yes, a letter avatar instead of a flag. Not drawn.
- #1341, the chart's hover readout. Not fixed: rendering yes, and its line
  says it needs a board.
- #1276, #1340, the locked-row logo offer and `render_cell`'s raw HTML are
  on the securities list, not the security page. They stay.

**Income (#1359):**

- The backfill follows every reason. Fixed and drawn (Income: R5's reasons
  alone); rendering yes.
- The count lead repeats every count. Fixed and drawn for Cash flow;
  rendering yes. The Overview card's half stays open.
- #1321 on Cash flow → Trades. Fixed; rendering yes.
- #1223, the Netto row. Not fixed: it is a new derived figure, which needs
  its computation basis in the API and MCP payload first. It is not a
  conformance repair.

**Classifications (#1362):**

- The S2 line, „Wert —“ beside the API's partial sum. Fixed and drawn (⑨);
  rendering yes.
- #1324, a dismissed result focused twice. Fixed; rendering: no.
- #1328, a move's confirmation out of view. Fixed; rendering: no if the
  page scrolls the confirmation into view and moves the focus. Moving the
  slot would need a frame.
- #1226, „… (copy)“ in English. Fixed by its recommendation, „… (Kopie)“;
  rendering yes, a name.
- #1329, an archived plan version's weights scroll out of view between 641
  and 1080 px. Rendering yes, a layout change, not drawn at those widths.
  The story draws it before its code, or the line stays.

**Snapshots and Risk:** #1321, fixed; rendering yes.

**Imports (#1355):**

- Rendering yes:
  - #1267, the unsupported-version error's length;
  - #1308, the dry run's stop named beside the withheld rows, by its
    recommendation;
  - #1325, a row's old count marked during a recount;
  - #1327, „1 Wertpapiere wurden manuell zugeordnet.“;
  - `parse_date`'s bare atom shown as a row error.
- Rendering no:
  - #925, bulk-preloaded hashes;
  - #1251, the parse moved off the page process;
  - #1265, a numeric cell of any length;
  - #1266, two tabs sharing a parked mapping;
  - #1300, `depot_needs_cash` on a delivery row;
  - #1303, „+ Create new“ not simulated for later rows;
  - #1304, the correction confirm's locked read;
  - #1326, a benchmark's id accepted as a mapping.

Imports alone carries 13 lines. Read with the plan's "every polish line on
a touched page is fixed", that exceeds Lane I's estimate of about 17
commits. This is not a defect; the shrink order applies if it bites.

## Found while drawing (severity per the sprint workflow §3)

1. **S3, Wertpapier → Kurse:** the basis line says „Kursbasis: wie
   erfasst.“ twice (two msgids rendered one after the other). The security
   page's repair fixes it: the line keeps it once.
2. **S3, Steuern:** the statement note reads „Zahl gegen die Abrechnung
   prüfen.“, and its button „Gegen die Abrechnung prüfen“ repeats it. Polish
   list „Wealth“ (#1366; Steuern is one of its area tabs).
3. **S3, Snapshots:** the gaps note names 20 securities with no count. This
   board fixes the count (⑧). Names that two securities share („Juniper Rail
   AG“, „Pinecrest Utilities SA“, …) appear twice with nothing to tell them
   apart. Polish list „Wealth“ (#1366).
4. **S3, Ansichten:** the assignment line lists 28 accounts without a
   default bucket in a basis line, which runs long at 390 px. A data fact
   outside a note does not clamp under the rule. Polish list „Accounts“
   (#1361, where the default buckets are set).
5. **S3, Klassifizierungen:** the predefined „Anlageklasse“ tree shows its
   categories by their stored English names („Equity“, „Bond“, „Government
   bond“, also in the exclusion note's list) under a German heading. The
   catalogue has „Aktie“, „Anleihe“, „Staatsanleihe“
   (`Catalog.AssetClasses.label/1`). Polish list „Classifications and
   targets“ (#1362).
6. **S3, Allokation:** the target-conflict and stale-target notes end in
   remedy links that are halves of their sentences. Under the clamp each
   needs a command of its own, as the overshoot note's gets here. The
   Allocation repair fixes them with two more strings.
7. **Note, not a defect:** none of the nine pages has a block of two or
   more foldable notes on the review seed, so ④ is not drawn here. Sprint
   22's Wealth frame shows it.
8. **Rule readings 1 to 3** (above), each a default a comment flips.

## How to regenerate

Run the review instance on port 4005 with the synthetic review seed, from
the repository root:

```bash
DATABASE_NAME=portfolixir_review_i PORT=4005 mix ecto.drop
DATABASE_NAME=portfolixir_review_i PORT=4005 mix ecto.create
DATABASE_NAME=portfolixir_review_i PORT=4005 mix ecto.migrate
DATABASE_NAME=portfolixir_review_i PORT=4005 PORTFOLIXIR_BACKGROUND_FETCH=off mix run priv/demo/finding_surfaces_seed.exs
DATABASE_NAME=portfolixir_review_i PORT=4005 PORTFOLIXIR_BACKGROUND_FETCH=off mix phx.server
```

Then, from this folder:

```bash
BASE=http://localhost:4005 node build.js   # captures 17 frames twice at 1280 and 390 px, writes both HTML files
node render.js                             # renders 01-i1-later--1200.png and 01-i1-later--390.png
```

The build sends GET requests and acts in the client only: it toggles
`<details>`, clicks a tab, presses „Alle aufklappen“ and previews the
synthetic demo export, which stores nothing before its confirmation. It
renders German (`?locale=de`). With `FRAMES_CACHE=<a file outside the
repository>` the build keeps the captured frames there, and `node board.js`
rebuilds the boards from them without the server. Run the build only
against an instance on the synthetic seed: the frames are its markup
verbatim.

## Not shown

- The **expanded** state of a clamped note („mehr“ pressed) is shown only
  on Income, as board 02 ①d draws it. Elsewhere its content is the "Before"
  note at full length.
- **Dark mode**, and the ⓘ's coarse-pointer sizes and 44 px ring. These are
  unchanged from Sprint 22.
- **The Overview**, whose trades card shares R5's sentences. It is not one
  of Lane I's pages.
