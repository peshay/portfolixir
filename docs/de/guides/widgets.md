---
layout: docs
title: Widget-Katalog
description: Jedes Dashboard-Widget in jeder Größe, hell und dunkel, mit dem, was es zeigt, und seiner Quell-Route.
lang: de
lang_en: /guides/widgets.html
lang_de: /de/guides/widgets.html
---

# Widget-Katalog

Jedes Widget, das ein Dashboard halten kann, in jeder Größe, die es im
Raster annimmt — Apples Familien S, M, L und XL und „Zeile“ —, so wie die
App es mit den synthetischen Daten des Review-Seeds zeichnet, hell und
dunkel (das Bild folgt dem Farbschema Ihres Systems). Jedes Widget zeigt
genau die Lesung, die seine Quell-Route antwortet, also liest Ihr Agent
über API und MCP dieselben Zahlen für dieselbe Ansicht und denselben
Zeitraum. Wie ein Dashboard angeordnet wird und wie Zeitraum und Ansicht
ein Widget erreichen, steht im
[Handbuch](/de/product-documentation.html).

Die Bilder zeigen die englische Oberfläche in doppelter Pixeldichte, jedes
auf seine Kachel zugeschnitten. Ändert sich ein Widget, entstehen sie neu
(Sprint 32, Plan D-13) mit

```bash
mix test test/browser/widget_gallery_test.exs --only gallery
```

## Gesamtwert

`total_value` · Größen S, M, L

Die Summe der Ansicht des Widgets mit ihrer Währung. **S** die Summe, ihre
Veränderung im Zeitraum (die TTWROR des Zeitraums) und eine Wertlinie; **M**
die Summe mit der TTWROR des Zeitraums und seinem Ergebnis nebeneinander;
**L** die Summe, ihre Veränderung und den Verlauf des Werts im Zeitraum. Was
die Summe auslässt, steht als eine Zeile im Fuß.

**Quelle:**

- `GET /api/v1/valuation`
- `GET /api/v1/views/:view_id/valuation`
- `GET /api/v1/performance`
- `GET /api/v1/views/:view_id/performance`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/total_value-s-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/total_value-s-light.png 2x" src="/assets/widgets/total_value-s-light.png" alt="Gesamtwert in S" loading="lazy">
</picture>
<figcaption>S</figcaption>
</figure>

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/total_value-m-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/total_value-m-light.png 2x" src="/assets/widgets/total_value-m-light.png" alt="Gesamtwert in M" loading="lazy">
</picture>
<figcaption>M</figcaption>
</figure>

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/total_value-l-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/total_value-l-light.png 2x" src="/assets/widgets/total_value-l-light.png" alt="Gesamtwert in L" loading="lazy">
</picture>
<figcaption>L</figcaption>
</figure>

## Datenqualität

`data_quality` · Größen S, L

Die Datenbefunde über die gehaltenen Wertpapiere und die Prüfungen des
Hauptbuchs. **S** die drei schwersten als kurze gezählte Zeilen und wie
viele weitere; **L** jeder Befund als Zeile mit seinem ganzen Satz,
darunter, was er an der Summe ändert, und die Schweregrade in Worten im
Kopf. Jede Zahl ist die Länge der Liste, die ihr Link öffnet.

**Quelle:**

- `GET /api/v1/securities`
- `GET /api/v1/transactions/cash_mismatch`
- `GET /api/v1/transactions/rate_only`
- `GET /api/v1/splits/incomplete`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/data_quality-s-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/data_quality-s-light.png 2x" src="/assets/widgets/data_quality-s-light.png" alt="Datenqualität in S" loading="lazy">
</picture>
<figcaption>S</figcaption>
</figure>

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/data_quality-l-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/data_quality-l-light.png 2x" src="/assets/widgets/data_quality-l-light.png" alt="Datenqualität in L" loading="lazy">
</picture>
<figcaption>L</figcaption>
</figure>

## Fällig

`due` · Größen S

Die datierten Fakten zu jedem Wertpapier im Katalog, gehalten oder nicht, in
den nächsten 30 Tagen: die nächsten zwei auf je einer Zeile, der Rest hinter
„+n weitere“.

**Quelle:**

- `GET /api/v1/events/upcoming`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/due-s-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/due-s-light.png 2x" src="/assets/widgets/due-s-light.png" alt="Fällig in S" loading="lazy">
</picture>
<figcaption>S</figcaption>
</figure>

## Abseits des Ziels

`off_target` · Größen S, L

Die Kategorien, die ±5 pp oder mehr von ihrem Sollgewicht abweichen, auf
jeder Ebene des Steuerungsbaums. **S** ihre Anzahl; **L** die Liste, jede
mit ihrer Drift als Balken und in Geld.

**Quelle:**

- `GET /api/v1/portfolios/:portfolio_id/allocation`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/off_target-s-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/off_target-s-light.png 2x" src="/assets/widgets/off_target-s-light.png" alt="Abseits des Ziels in S" loading="lazy">
</picture>
<figcaption>S</figcaption>
</figure>

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/off_target-l-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/off_target-l-light.png 2x" src="/assets/widgets/off_target-l-light.png" alt="Abseits des Ziels in L" loading="lazy">
</picture>
<figcaption>L</figcaption>
</figure>

## Wertentwicklung

`performance` · Größen S, L, XL

Die zeitgewichtete Rendite der Ansicht im Zeitraum. **S** („Rendite“) die
TTWROR und eine Linie des Tageswerts; **L** die TTWROR und den Verlauf des
Werts mit niedrigstem und höchstem Wert; **XL** das gestapelte Chart von
Vermögen nach Kategorien mit seiner Legende.

**Quelle:**

- `GET /api/v1/performance`
- `GET /api/v1/views/:view_id/performance`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/performance-s-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/performance-s-light.png 2x" src="/assets/widgets/performance-s-light.png" alt="Wertentwicklung in S" loading="lazy">
</picture>
<figcaption>S</figcaption>
</figure>

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/performance-l-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/performance-l-light.png 2x" src="/assets/widgets/performance-l-light.png" alt="Wertentwicklung in L" loading="lazy">
</picture>
<figcaption>L</figcaption>
</figure>

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/performance-xl-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/performance-xl-light.png 2x" src="/assets/widgets/performance-xl-light.png" alt="Wertentwicklung in XL" loading="lazy">
</picture>
<figcaption>XL</figcaption>
</figure>

## Tops und Flops

`movers` · Größen S, L

Welche Namen die Ansicht im Fenster des Zeitraums bewegt haben. **S** die
zwei höchsten und die zwei niedrigsten Kursrenditen, jede mit ihrem Balken;
**L** die höchsten und niedrigsten der Kursrendite oder des Beitrags (der
Schalter im Kopf), jede Zeile mit ihrem Balken.

**Quelle:**

- `GET /api/v1/movers`
- `GET /api/v1/views/:view_id/movers`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/movers-s-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/movers-s-light.png 2x" src="/assets/widgets/movers-s-light.png" alt="Tops und Flops in S" loading="lazy">
</picture>
<figcaption>S</figcaption>
</figure>

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/movers-l-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/movers-l-light.png 2x" src="/assets/widgets/movers-l-light.png" alt="Tops und Flops in L" loading="lazy">
</picture>
<figcaption>L</figcaption>
</figure>

## Snapshots

`snapshots` · Größen S, M

Das Datum des letzten Snapshots, wie viele es gibt und die echte TTWROR
seitdem, mit ihrer Tageslinie; **M** nennt auch den Snapshot.

**Quelle:**

- `GET /api/v1/snapshots`
- `GET /api/v1/portfolios/:portfolio_id/snapshots/:id/comparison`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/snapshots-s-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/snapshots-s-light.png 2x" src="/assets/widgets/snapshots-s-light.png" alt="Snapshots in S" loading="lazy">
</picture>
<figcaption>S</figcaption>
</figure>

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/snapshots-m-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/snapshots-m-light.png 2x" src="/assets/widgets/snapshots-m-light.png" alt="Snapshots in M" loading="lazy">
</picture>
<figcaption>M</figcaption>
</figure>

## Allokation und Drift

`allocation_drift` · Größen L

Jede Kategorie der obersten Ebene des Steuerungsbaums und Cash: Ist- und
Sollgewicht, die Drift mit ihrem Balken und in der Spalte „≈ zum Soll“ der
Betrag, der eine Lücke von ±5 pp oder mehr schlösse — Rechnung zur Anzeige,
nie ein Auftrag.

**Quelle:**

- `GET /api/v1/portfolios/:portfolio_id/allocation`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/allocation_drift-l-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/allocation_drift-l-light.png 2x" src="/assets/widgets/allocation_drift-l-light.png" alt="Allokation und Drift in L" loading="lazy">
</picture>
<figcaption>L</figcaption>
</figure>

## Crashes im Vergleich

`crashes` · Größen L

Die Fenster des Crash-Benchmarks, das neueste zuerst: der Fall jedes
Fensters und die niedrigste Rendite darin unter den heute gehaltenen
Wertpapieren oder im ganzen Katalog (der Schalter im Kopf), und wann es sich
erholt hat.

**Quelle:**

- `GET /api/v1/crashes`
- `GET /api/v1/crashes/:key/rankings`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/crashes-l-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/crashes-l-light.png 2x" src="/assets/widgets/crashes-l-light.png" alt="Crashes im Vergleich in L" loading="lazy">
</picture>
<figcaption>L</figcaption>
</figure>

## Bitcoin-Zyklus

`bitcoin_cycle` · Größen L, XL

Der Bereich, den die gespeicherten Zyklen von den heutigen Ankern aus
ergeben, für jedes Wertpapier mit der Zyklus-Ansicht: Fenster, Preisbereiche
und Stand des nächsten Tiefs und des nächsten Tops. **L** die Karte; **XL**
das Chart des Wertpapiers im Bereich „Zyklus“ mit seinen Bändern. Keine
Prognose.

**Quelle:**

- `GET /api/v1/securities/:security_id/cycles`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/bitcoin_cycle-l-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/bitcoin_cycle-l-light.png 2x" src="/assets/widgets/bitcoin_cycle-l-light.png" alt="Bitcoin-Zyklus in L" loading="lazy">
</picture>
<figcaption>L</figcaption>
</figure>

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/bitcoin_cycle-xl-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/bitcoin_cycle-xl-light.png 2x" src="/assets/widgets/bitcoin_cycle-xl-light.png" alt="Bitcoin-Zyklus in XL" loading="lazy">
</picture>
<figcaption>XL</figcaption>
</figure>

## Verkaufsrückblick

`sale_review` · Größen L, Zeile

Die fünf zuletzt abgeschlossenen Trades mit ihrem Ergebnis, FIFO über alle
Depots, in EUR; was die Liste auslässt, steht als eine Zeile im Fuß.
**Zeile** zeichnet dieselbe Liste über die ganze Breite.

**Quelle:**

- `GET /api/v1/realized_gains`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/sale_review-l-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/sale_review-l-light.png 2x" src="/assets/widgets/sale_review-l-light.png" alt="Verkaufsrückblick in L" loading="lazy">
</picture>
<figcaption>L</figcaption>
</figure>

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/sale_review-row-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/sale_review-row-light.png 2x" src="/assets/widgets/sale_review-row-light.png" alt="Verkaufsrückblick in Zeile" loading="lazy">
</picture>
<figcaption>Zeile</figcaption>
</figure>

## Abstand zum Hoch

`distance_to_high` · Größen L, XL

Die gehaltenen Wertpapiere nach ihrem Abstand zum 52-Wochen-Hoch, mit dem
größten Rückgang; **XL** mit mehr Zeilen und den ganzen Namen.

**Quelle:**

- `GET /api/v1/valuation`
- `GET /api/v1/views/:view_id/valuation`
- `GET /api/v1/securities/:security_id/metrics`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/distance_to_high-l-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/distance_to_high-l-light.png 2x" src="/assets/widgets/distance_to_high-l-light.png" alt="Abstand zum Hoch in L" loading="lazy">
</picture>
<figcaption>L</figcaption>
</figure>

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/distance_to_high-xl-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/distance_to_high-xl-light.png 2x" src="/assets/widgets/distance_to_high-xl-light.png" alt="Abstand zum Hoch in XL" loading="lazy">
</picture>
<figcaption>XL</figcaption>
</figure>

## Crash-Chart

`crash_chart` · Größen L, XL

Die Schlusskurse des Crash-Benchmarks im Zeitraum mit seinen Crash-Fenstern
schattiert, das laufende stärker; der Benchmark unter dem Titel genannt,
sein erster, niedrigster, höchster und letzter Schlusskurs unter dem Chart.

**Quelle:**

- `GET /api/v1/crashes`
- `GET /api/v1/securities/:security_id/quotes`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/crash_chart-l-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/crash_chart-l-light.png 2x" src="/assets/widgets/crash_chart-l-light.png" alt="Crash-Chart in L" loading="lazy">
</picture>
<figcaption>L</figcaption>
</figure>

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/crash_chart-xl-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/crash_chart-xl-light.png 2x" src="/assets/widgets/crash_chart-xl-light.png" alt="Crash-Chart in XL" loading="lazy">
</picture>
<figcaption>XL</figcaption>
</figure>

## Erholer nach Crashes

`rebounders` · Größen L, XL

Nach jedem der letzten Crash-Fenster, deren Fall vorbei ist, die
Wertpapiere, die binnen drei Monaten am stärksten von ihrem eigenen Tief
gestiegen sind, jedes mit seinem Balken; heute gehalten oder der ganze
Katalog (der Schalter im Kopf). Keine Prognose; das Überlebensbias steht
hinter ⓘ.

**Quelle:**

- `GET /api/v1/crashes`
- `GET /api/v1/crashes/:key/rankings`
- `GET /api/v1/views/:view_id/valuation`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/rebounders-l-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/rebounders-l-light.png 2x" src="/assets/widgets/rebounders-l-light.png" alt="Erholer nach Crashes in L" loading="lazy">
</picture>
<figcaption>L</figcaption>
</figure>

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/rebounders-xl-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/rebounders-xl-light.png 2x" src="/assets/widgets/rebounders-xl-light.png" alt="Erholer nach Crashes in XL" loading="lazy">
</picture>
<figcaption>XL</figcaption>
</figure>

<!-- S32 W2 begin -->

## Kennzahlen-Zeile

`summary_line` · Größen Zeile

Die Zeile über dem Tab „Allokation & Ziele“ in Vermögen: Gesamt inkl. Cash,
die Cashquote und die TTWROR des Zeitraums, dazu der Weg zu allen
Kennzahlen unter Bestände. **Zeile** zeichnet sie über die ganze Breite,
wie der Tab; auf dem Handy bricht sie um. Sie folgt dem Zeitraum des
Dashboards oder ihrem eigenen. Nicht „Kennzahlen“ (`wealth_key_figures`),
das Band des Tabs Bestände.

**Quelle:**

- `GET /api/v1/valuation`
- `GET /api/v1/views/:view_id/valuation`
- `GET /api/v1/performance`
- `GET /api/v1/views/:view_id/performance`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/summary_line-row-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/summary_line-row-light.png 2x" src="/assets/widgets/summary_line-row-light.png" alt="Kennzahlen-Zeile in Zeile" loading="lazy">
</picture>
<figcaption>Zeile</figcaption>
</figure>

## Allokation

`allocation` · Größen Zeile

Der Abschnitt „Allokation“ aus Vermögen, wie der Tab ihn zeichnet: Baum
oder Positionen, das Sunburst mit seiner Legende, die Drift-Tabelle (je
Kategorie Wert, Ist- und Sollgewicht und die Drift, eine Kategorie öffnet
ihre Wertpapiere), die Drift-Chips und die Wahl des Baums. Die Hinweise
neben einer Drift („Verkauf ≈ 3,20 Stück“) sind Rechnung zum Kurs der
Bewertung, nur zur Anzeige, nie ein Auftrag (ADR-0023). Die Bedienelemente
ändern nur dieses Widget, solange die Seite offen ist; gespeichert wird
nichts. Die Sollwerte werden auf der Seite Klassifikationen bearbeitet, die
die Plan-Zeile verlinkt. **Zeile** zeichnet den Abschnitt über die ganze
Breite; auf dem Handy nimmt er die schmale Form des Abschnitts.

**Quelle:**

- `GET /api/v1/portfolios/:portfolio_id/allocation`

<figure class="widget-gallery">
<picture>
<source srcset="/assets/widgets/allocation-row-dark.png 2x" media="(prefers-color-scheme: dark)">
<img srcset="/assets/widgets/allocation-row-light.png 2x" src="/assets/widgets/allocation-row-light.png" alt="Allokation in Zeile" loading="lazy">
</picture>
<figcaption>Zeile</figcaption>
</figure>

<!-- S32 W2 end -->
