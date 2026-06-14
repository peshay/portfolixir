---
layout: docs
title: Produktdokumentation
description: Portfolixir-Handbuch zum aktuellen Verhalten der lokalen Portfolioverwaltung.
lang: de
lang_en: /product-documentation.html
lang_de: /de/product-documentation.html
---

# Produktdokumentation

## Überblick

Portfolixir ist eine selbst gehostete, lokal-first Phoenix-Anwendung für die
Verwaltung eines einzelnen Portfolio-Workflows. Sie ist bewusst eng gefasst:

- Manuelles Anlegen von Wertpapieren, Portfolio, Konten und Transaktionen.
- Massenimport von Portfolio-Performance-Transaktionsexporten im Format
  CSV/JSON v1 über einen Vorschau-und-Anwenden-Workflow.
- Bestände werden aus der Transaktionshistorie abgeleitet, mit Einstandswert und
  nicht realisiertem Gewinn/Verlust.
- Klassifizierungsbäume ordnen Wertpapiere; Zielgewichte je Kategorie treiben
  eine SOLL/IST-Allokationsaufschlüsselung mit Drift.
- Mehrwährungs-Portfolios werden über gespeicherte Wechselkurse bewertet.
- Wertpapierpreise werden als Kurshistorie gespeichert und in einem
  Wertpapier-Detailchart angezeigt.
- Unterstützte Funktionen sind über die UI, die JSON-API und den
  MCP-Begleitdienst verfügbar.
- Keine Broker-Synchronisierung, keine Bank-Synchronisierung, keine
  Handels-Engine, kein Zahlungs-Flow, kein Order-Flow, kein Rebalancing, keine
  Dokumentenerfassung und kein KI-gestütztes Verhalten.

## Produktmodule

Die Codebasis ist in lokale Domänenmodule plus die Web-Schicht aufgeteilt:

- `Portfolixir.Catalog`
  - Wertpapiere und Kurs-Entitäten
  - Wertpapier-Metadaten und Kurssätze
- `Portfolixir.Portfolios`
  - Portfolios
  - Geldkonten
  - Depots
  - Zielgewichte und SOLL/IST-Allokation
- `Portfolixir.Ledger`
  - Manuelle Kauf-/Verkauftransaktionen
  - Bestandsberechnung aus unveränderlicher Historie
- `Portfolixir.Classifications`
  - Eigene und integrierte Klassifizierungsbäume und Zuordnungen
- `Portfolixir.Fx`
  - Wechselkurse und Mehrwährungsumrechnung
- `PortfolixirWeb`
  - Routen, Seiten, LiveViews und JSON-API
- `mcp-server/`
  - TypeScript-MCP-Begleitdienst, der die JSON-API kapselt

Integrationsdetails für `/api/v1` und `mcp-server/` sind separat unter
[API und MCP](integration/api-and-mcp.html) dokumentiert.

## Kern-Workflow

1. Lege ein oder mehrere Wertpapiere mit grundlegenden Identifikationsdaten an.
2. Lege ein Portfolio an.
3. Lege ein Geldkonto und ein Depot an und verknüpfe sie.
4. Erfasse manuelle Kauf- und Verkauftransaktionen mit Decimal-basierten Mengen-
   und Preiswerten.
5. Importiere optional einen Portfolio-Performance-Transaktionsexport über
   Imports, prüfe die Vorschau, ordne fehlende Konten zu und wende dann atomar an.
6. Öffne die Bestandsansicht, um die aktuelle Position je Wertpapier zu prüfen.
7. Erfasse Wertpapierkurse im Zeitverlauf und behalte die Historie für
   reproduzierbare Charts.
8. Prüfe aktuelle Bestände und das Verhalten der Kurscharts direkt in der App.

## Wertpapiere

Jedes Wertpapier ist ein erstklassiges Objekt mit stabilen Identitätsfeldern und
Markt-Metadaten. Sie bilden die Basis für alle Transaktions- und
Bestandsberechnungen.

### Inferenz der Anlageklasse

Jedes Wertpapier trägt ein Feld **asset class** (Anlageklasse). Sein Wert wird
zur Lesezeit von `Security.effective_asset_class/1` bestimmt: ist der gespeicherte
Wert nicht nil, wird er unverändert zurückgegeben; andernfalls werden Name, ISIN
und Ticker in dieser Prioritätsreihenfolge untersucht:

1. **government_bond** — ISIN-Länderpräfix in der Liste bekannter
   Staatsanleihen-Emittenten (DE, US, GB, FR, IT, ES, JP, …).
2. **etf** — Name enthält `ETF`, `UCITS ETF`, oder eine exakte ISIN, die mit
   `IE00` beginnt, kombiniert mit einem bekannten Fonds-Emittentenpräfix.
3. **crypto** — Name passt zu einem bekannten Coin-Namen (Bitcoin, Ethereum,
   Ripple, Cardano, Solana, Dogecoin, Avalanche, Tron, …) oder der Ticker passt
   zu einem bekannten Krypto-Symbol (BTC, ETH, XRP, ADA, SOL, DOGE, AVAX, TRX, …).
4. **commodity** — Name ist ein exakter, reiner Metallname: Gold, Silber, Silver,
   Platin, Platinum. (Zusammengesetzte Namen wie „Barrick Gold Corp" greifen hier
   nicht und fallen auf equity durch.)
5. **derivative** — Name enthält `Knock-Out`, `Zertifikat` oder `Turbo`
   (einschließlich einbuchstabiger Suffixe wie TurboP, TurboC, TurboA).
6. **knock_out** — Name enthält `Turbo` (beliebiges einbuchstabiges Suffix),
   `Knockout` oder ein `KO`-Muster. In der Praxis wird die Turbo-Prüfung mit dem
   derivative-Zweig geteilt; die Klasse `knock_out` wird explizit gespeichert,
   wenn die Nutzerin die Inferenz korrigiert.
7. **equity** — Name enthält ein Rechtsform-Suffix (Corporation, Company, Co.,
   Aktiengesellschaft, AG, S.A., S.p.A., A/S, ASA, KGaA, Azioni, Acciones,
   Aktier, Ltd., PLC, Inc., GmbH, NV, SA) oder einen Hinterlegungsschein-Marker
   (ADR, GDR, Sp.ADR, Depos. Receipts, INH.ON, Registered Part. Shares).
8. **fund** — Name beginnt mit oder enthält ein bekanntes
   Fonds-Emittentenpräfix (iShares, Vanguard, Lyxor, Amundi, AIS-AM, Xtrackers,
   SPDR, Invesco, WisdomTree, VanEck, Fidelity, Deka), passte aber nicht zum
   ETF-Muster oben.
9. **nil** — keine Heuristik griff; das Wertpapier gilt als nicht klassifiziert.

Da die Inferenz zur Lesezeit läuft, klassifiziert eine verbesserte Heuristik im
Code alle passenden Wertpapiere rückwirkend neu, ohne Datenmigration.

#### Nicht klassifizierte Wertpapiere finden und korrigieren

Die Wertpapierliste akzeptiert einen Filter **„is unclassified"** auf der
Anlageklasse-Spalte (`operator: :is_nil`). Er liefert alle Zeilen, bei denen der
gespeicherte Wert nil ist und `effective_asset_class` ebenfalls nil ergab — d. h.
die Heuristiken haben keine sichere Übereinstimmung. Für jede solche Zeile zeigt
die Anlageklasse-Zelle ein eingebettetes **Schnellzuweisungs-Dropdown**, sodass
du die Klasse direkt aus der Liste setzen kannst, ohne die Wertpapier-Detailseite
zu öffnen.

Eine gespeicherte Klasse ist eine dauerhafte Überschreibung: einmal gesetzt, wird
sie von `effective_asset_class` zurückgegeben, unabhängig davon, was die
Heuristiken erzeugen würden, sodass die Schnellzuweisung künftige
Heuristik-Änderungen überlebt.

#### Buchstaben-getrennte Namen aus Portfolio Performance

Portfolio Performance exportiert Namen manchmal mit einem Leerzeichen zwischen
jedem Zeichen — z. B. `I b e r d r o l a S . A . A c c i o n e s`. Der
JSON-Parser erkennt dieses Muster (die Mehrheit der durch Leerzeichen getrennten
Tokens sind einzelne Zeichen, mindestens vier Tokens) und führt die Tokens
zusammen, bevor die Heuristiken laufen, sodass Rechtsform-Suffixe auch aus
solchen Exporten zuverlässig erkannt werden.

## Portfolios und Konten

Das Portfolio besitzt eine Arbeitsgruppe von Kontomodellen:

- Geldkonto: verfolgt den Kontext der verfügbaren Liquidität
- Depot/Konto: speichert Wertpapierpositionen, verknüpft mit diesem Geldkonto

## Transaktionen und Bestände

### Manuelle Transaktionen

Transaktionen sind explizit und nachvollziehbar. Eine Transaktion definiert:

- Datum
- Wertpapier
- Richtung (Kauf/Verkauf)
- Menge (Decimal)
- Stückpreis (Decimal)
- optionale Steuern, Gebühren und Notizen

Eine Transaktion wird in der Währung ihres verknüpften Geldkontos gebucht. Ihre
Währung muss der dieses Geldkontos entsprechen (und bei einer Geldübertragung
auch der des Gegen-Geldkontos); eine Buchung mit Währungs-Konflikt wird abgelehnt
statt stillschweigend umgerechnet. Buche gegen ein Geldkonto in derselben Währung
oder lege eines an. Hier findet keine Wechselkursumrechnung gespeicherter Beträge
statt — Wechselkurse werden nur angewendet, wenn ein Portfolio in seiner
Basiswährung bewertet wird.

### Bestandsberechnung

Aktuelle Bestände werden nicht manuell erfasst. Sie werden aus allen
Transaktionen im Zeitverlauf abgeleitet, sodass der Zustand reproduzierbar und
nachvollziehbar ist. Gehaltene Mengen bewegen sich mit Käufen und Verkäufen, mit
ein-/ausgehenden **Lieferungen** (Anteile, die ohne Geld-Bein ein- oder
austreten, z. B. ein Depotübertrag von einer anderen Bank) und mit
**Wertpapierübertragungen** zwischen deinen eigenen Depots. Jeder Bestand trägt
außerdem einen gleitenden Durchschnitts-Einstandswert und den nicht realisierten
Gewinn/Verlust (absolut und prozentual) gegen den zuletzt gespeicherten Preis, in
der eigenen Währung des Wertpapiers; Einstandswert und G/V berücksichtigen nur
bepreiste Kauf-/Verkauftrades, da eine Lieferung keinen eigenen Einstand trägt.

## Klassifizierungen, Ziele und Allokation

Wertpapiere können in **Klassifizierungsbäume** geordnet werden. Eigene Bäume
sind frei gestaltbare Ordner mit Farben; integrierte Bäume für **Anlageklasse**
und **Währung** werden aus jedem Wertpapier abgeleitet und sind immer vorhanden.
Der Anlageklassen-Baum ist eine editierbare Taxonomie: die Klasse eines
Wertpapiers wird aus einem inferierten Standard vorbelegt und durch Ziehen
zwischen Kategorien korrigiert.

Jedes Portfolio kann ein **Zielgewicht** je Kategorie speichern (ein Anteil am
Portfolio, zum Beispiel 25 %). Die **Allokations**-Aufschlüsselung vergleicht dann
je Kategorie das tatsächliche Gewicht (seinen Anteil an den bewerteten Positionen)
mit dem gespeicherten Ziel und meldet die **Drift** — sowohl als Gewicht als auch
als Betrag in Basiswährung, d. h. wie viel zu kaufen oder zu verkaufen ist, um das
Ziel zu erreichen. Gehaltene, aber im gewählten Baum nicht zugeordnete
Wertpapiere werden in einem Topf für nicht Zugeordnetes summiert. Nur die Ziele
werden gespeichert; die Ist-Seite wird beim Lesen aus der Live-Bewertung
abgeleitet.

Ein Wertpapier kann als **von Allokationszielen ausgeschlossen** markiert werden
(der Schalter in der Wertpapierverwaltung; das API/MCP-Feld ist
`excluded_from_allocation_targets`). Eine ausgeschlossene Position — zum Beispiel
ein als langfristiger Wertspeicher gehaltener Bitcoin statt Teil des gesteuerten
Mix — zählt weiterhin in den Gesamtwert, die Bestände und die Performance, wird
aber **aus der Allokations-Steuerbasis** (den 100 %) und der Drift-Tabelle
herausgenommen. So hebt das Einschalten eines Schalters den Ist-Prozentsatz jeder
anderen Kategorie konsistent an, ohne den Gesamtwert zu ändern. Die
ausgeschlossenen Positionen verschwinden nicht: die Drift-Tabelle zeigt sie in
einer separaten Zeile *Outside the steering basis* mit ihrem summierten Wert.

Klassifizierungsbäume sind **hierarchisch**, und die Allokation rollt sie auf:
eine einer Unterkategorie zugeordnete Position zählt zu dieser Unterkategorie
**und jeder übergeordneten Kategorie darüber**. Hält *Growth* also ein Ziel von
50 % und du ordnest Bestände nur seinen Unterkategorien zu (*Tech*, *Emerging*,
…), ist das Ist-Gewicht von *Growth* deren Summe — nicht 0 % — und seine Drift
wird gegen diese Summe gemessen. Die Drift-Tabelle listet Kategorien in
Baumreihenfolge mit unter ihren Eltern eingerückten Unterkategorien; da jede
übergeordnete Kategorie ihre Kinder bereits enthält, summieren sich die
angezeigten Ist-Prozentsätze nur über die Blätter (plus nicht Zugeordnetes) zu
100 %, nicht über jede Ebene.

Ziele bleiben **bewusst locker**: du kannst ein Gewicht auf oberster Ebene und auf
Unterebenen setzen, ohne dass die App sie zur Summe 100 % zwingt. Um diese
Freiheit zu bewahren und zugleich Abweichungen sichtbar zu machen, zeigt die
Portfolio-Seite zwei **beratende Konsistenzhinweise** — schreibgeschützt, ein
Speichern nie blockierend:

- Eine dezente Zeile unter jeder übergeordneten Kategorie mit Kind-Zielen lautet
  *subcategories: X% of Y%*, wobei X die Summe der direkten Kind-Ziele und Y das
  eigene Ziel der Elternkategorie ist. Sie wird **gelb**, wenn X und Y abweichen.
- Der Allokations-Header zeigt *Σ target top level: Z%* — die Summe der Ziele der
  obersten Kategorien **plus das Cash-Ziel** — hervorgehoben, wenn Z nicht 100 %
  ist.

Gleichheit wird exakt geprüft (auf die gespeicherte Gewichts-Präzision), sodass
ein Hinweis nur dann hervorhebt, wenn die Zahlen wirklich abweichen. Die Hinweise
sind reine Orientierung; der Speicherpfad der Ziele ist unverändert und lehnt frei
gewählte Gewichte nie ab.

**Cash ist Teil der Allokation.** Ein Portfolio kann ein **Cash-Ziel** speichern
(`cash_target_weight`, z. B. 5 %) — den SOLL-Anteil von Cash innerhalb derselben
100 %-Basis wie die Kategorien. Mit gesetztem Cash-Ziel ist die 100 %-Basis der
Allokation **Wertpapiere (abzüglich ausgeschlossener) + das Cash, das zur
Cash-Quote zählt** (die als *counts toward the cash quote* markierten Konten). Die
Drift-Tabelle zeigt dann eine eigene **Cash**-Zeile in eigener neutraler Farbe mit
Cash-Ist, -Ziel und -Drift, der Sunburst erhält ein Cash-Segment, und jeder
Kategorie-Prozentsatz schrumpft entsprechend, sobald Cash zur Basis hinzukommt.
Setze das Cash-Ziel über die API (`PATCH /api/v1/portfolios/:id`) oder MCP
(`portfolixir.portfolios.set_cash_target`), oder lösche es mit `null`, um die
Steuerung einer Cash-Quote zu beenden.

## Wechselkurse und Bewertung

Portfolios können Wertpapiere und Cash in mehreren Währungen halten. Wechselkurse
werden gegen einen EUR-Hub gespeichert (mit Synchronisierung der Europäischen
Zentralbank), und andere Paare werden darüber trianguliert. Die Live-Bewertung des
Portfolios rechnet den Marktwert jeder Position und jeden Cash-Saldo in die
Basiswährung des Portfolios um.

Ein Wertpapier ohne jeden Kurs wird mit deinem **zuletzt eigenen Handelspreis**
bepreist — ein Kauf oder Verkauf ist eine Preisbeobachtung, genau so, wie
Portfolio Performance Preise aus Buchungen ableitet — sodass ein frisch
importiertes Portfolio nicht mit null bewertet wird, während Kurse noch geholt
werden. Solche Positionen tragen `price_source: "trade"` in der API und werden in
`trade_priced_count` gezählt; die Portfolio-Seite markiert sie als
Datenqualitäts-Hinweis. Eine Position mit weder Kurs noch Handelspreis oder ohne
Kurspfad zur Basiswährung wird als unbewertet gemeldet, sodass ein fehlender Preis
oder Kurs nie still den Gesamtwert oder die Gewichte verzerrt.

## Cash und Cash-Quote

Cash ist Teil des Portfolios, kein Nachgedanke. Jedes Portfolio hat ein oder
mehrere Geldkonten, und die Live-Bewertung meldet das **gesamte Cash**, den
**Gesamtwert inklusive Cash** und die **Cash-Quote** — Cash als Anteil am
Gesamtportfolio — sodass du Liquidität und trockenes Pulver auf einen Blick
siehst, umgerechnet in die Basiswährung des Portfolios.

Das Verrechnungs-Cash eines Depots bleibt von selbst aktuell: Käufe, Verkäufe,
Dividenden, Zinsen, Gebühren und Steuern bewegen es, sobald du diese
Transaktionen erfasst, sodass das zum Investieren gehörende Cash keine separate
Pflege braucht.

Für externe Konten (ein Girokonto, Sparkonto, ein Geschäftskonto) ist das Ziel
Sichtbarkeit ohne Buchhaltung. Statt jede Buchung zu spiegeln, **setzt du den
Saldo eines Kontos direkt** — tippe die Zahl ein, die deine Banking-App zeigt, als
datierten **Snapshot** (das Saldo-setzen-Formular auf der Portfolio-Seite,
`POST /api/v1/cash_accounts/:id/balance` oder das MCP-Tool
`cash_accounts.set_balance`). Der Saldo verankert sich dann an diesem Betrag, und
nur Buchungen mit einem Datum strikt nach dem Snapshot verändern ihn; so braucht
Geld zwischen deinen eigenen Konten zu verschieben keine Übertragungsbuchung — du
gibst jeden Saldo nur ab und zu neu an. Der Betrag darf negativ sein (ein
Überziehungskredit), und derselbe Snapshot kann später automatisch über die API
befüllt werden (ein Skript oder ein nur lesender Bankexport) — ohne Portfolixir in
eine Banking-App zu verwandeln. Dies folgt dem in
[ADR-0009](/decisions/0009-cash-as-balance-snapshots.html) festgehaltenen Entwurf.

Jedes Geldkonto trägt einen Schalter dafür, ob es zur Cash-Quote zählt
(standardmäßig an; der Schalter sitzt neben dem Konto auf der Portfolios-Seite,
und das API/MCP-Feld ist `counts_toward_cash_quote`). Ein abgeschaltetes Konto —
etwa ein Geschäftskonto — bleibt mit seinem Saldo gelistet und im gesamten Cash,
aber die Quote wird berechnet, als gäbe es es nicht, sodass es deine private Quote
nie verzerrt. Die Portfolio-Seite markiert solche Konten als „not in cash quote".

## Portfolio-Seite

Der Eintrag **Portfolio** in der Navigation öffnet die Portfolio-Übersicht: den
Gesamtwert inklusive Cash, die Cash-Quote sowie sowohl die TTWROR als auch den
geldgewichteten **IRR** für einen wählbaren Zeitraum (laufendes Jahr, ein/drei/fünf
Jahre oder seit der ersten Transaktion) mit dem kumulativen Performance-Chart.
Darunter zeigt der **Allokations-Sunburst** die Klassifizierung als
konzentrische Ringe — der innere Ring sind die obersten Kategorien, jeder äußere
Ring bricht eine Ebene weiter herunter mit in ihren Eltern verschachtelten
Unterkategorie-Bögen, und der **äußerste Ring zeigt die einzelnen Positionen** als
schattierte Bögen in der Farbe ihrer Kategorie (der Portfolio-Performance-Stil) —
mit einem grauen Segment für nicht zugeordnete Bestände. Wie bei PP tragen die
Segmente keinen Text im Chart: das Überfahren eines Segments zeigt seinen Namen,
Anteil und Wert in einem **sofortigen, eigenen Tooltip**, der dem Zeiger folgt
(keine Browser-Hover-Verzögerung), und ein Segment kann **angetippt** werden, um
dasselbe unter dem Chart wiederzugeben (der mobile Ersatz für Hover). Mit
deaktiviertem JavaScript fallen die Segmente auf den nativen Browser-Tooltip
zurück. Der Chart skaliert auf die verfügbare Breite. Wähle einen beliebigen
Klassifizierungsbaum aus dem Selektor. Die Drift-Tabelle darunter listet jede
Kategorie in Baumreihenfolge mit **eingerückten Unterkategorien** unter ihren
Eltern und vergleicht das aufgerollte Ist-Gewicht mit dem gespeicherten Ziel,
wobei die Drift in der Basiswährung neu ausgewiesen wird. Der Cash-Abschnitt
listet den Saldo jedes Kontos und trägt das **Saldo-setzen-Formular**: tippe den
Saldo ein, den deine Bank zeigt, und der Snapshot wird ohne Buchung einzelner
Transaktionen erfasst.

Die Seite zeichnet sich sofort und berechnet ihre Zahlen **asynchron**; jeder
Abschnitt füllt sich, sobald seine Daten bereit sind. Der teure tägliche
Performance-Lauf läuft einmal und wird auf der Seite zwischengespeichert — ein
Zeitraumwechsel verkettet die zwischengespeicherte Reihe neu, sodass die
Zeitraum-Buttons sofort reagieren. Der Chart wird auf eine begrenzte Punktzahl
heruntergerechnet, sodass ein Jahrzehnt täglicher Historie im Browser leicht
bleibt. Geld und Prozente folgen der gewählten Sprache (Deutsch `1.234.567,89`,
Englisch `1,234,567.89`; Geld immer mit zwei Nachkommastellen).

Ein **Datenqualitäts-Panel** erscheint über dem Chart, wenn etwas die Zahlen
sonst still verzerren würde: Positionen, die mit ihrem letzten Handelspreis
bewertet werden, weil noch kein Kurs existiert, Positionen ganz ohne Preis (aus
den Summen ausgenommen, namentlich gelistet) und Buchungen mit unplausiblen Daten
(vor 1970), die stattdessen am ersten plausiblen Tag angewendet wurden.

## Performance (TTWROR)

Portfolixir meldet die **echte zeitgewichtete Rendite** so, wie es Portfolio
Performance tut: das Portfolio wird ab der ersten Transaktion jeden Tag bewertet,
Geld, das du ein- oder auszahlst (Einzahlungen, Entnahmen, Lieferungen und
Saldo-Snapshot-Sprünge), wird neutralisiert, und die täglichen Renditen werden
verkettet. Das Ergebnis misst, wie gut die **Investitionen** abgeschnitten haben,
unabhängig davon, wann Geld bewegt wurde — Dividenden, Zinsen, Gebühren und
Steuern zählen als Teil der Rendite.

Daneben zeigt Portfolixir die **geldgewichtete Rendite (IRR)** — die einzelne
annualisierte Rate, die die datierten Einzahlungen, Auszahlungen und den Endwert
des Zeitraums auf null abzinst, die Zahl, die Portfolio Performance neben TTWROR
zeigt. Wo TTWROR das Timing deines Geldes ignoriert, spiegelt der IRR es wider,
sodass die beiden unterschiedlich ausfallen, wenn Geld zu guten oder schlechten
Zeitpunkten bewegt wurde. Der IRR zeigt `—`, wenn es keine Rate zu berechnen gibt
(keine Flüsse beider Vorzeichen oder der Solver konvergiert nicht).

Die Performance wird auf der Portfolio-Seite gezeigt und ist je Zeitraum
verfügbar — laufendes Jahr, ein, drei oder fünf Jahre oder seit der ersten
Transaktion — über die API (`GET /api/v1/portfolios/:id/performance`) und das
MCP-Tool `portfolixir.portfolios.performance`, optional mit der vollständigen
täglichen Bewertungsreihe zum Charting. Die Methode und ihre Abwägungen sind in
[ADR-0010](/decisions/0010-ttwror-performance-series.html) festgehalten.

## Income (Dividenden und Zinsen)

Die **Income**-Seite ist der retrospektive Ertragsbericht: die bereits in deinem
Ledger gebuchten Dividenden und Zinsen, ohne externe Daten oder Prognose. Sie
zeigt einen **Jahresüberblick** — eine Jahr-×-Monat-Matrix, aufgeteilt in eine
*Dividends*- und eine *Interest*-Reihe, jedes Jahr mit einer Summenspalte — und
eine **Pro-Position-Tabelle** mit, für jedes Wertpapier, dem Brutto-Gezahlten, der
einbehaltenen Steuer, dem Netto, der Anzahl der Zahlungen und dem Datum der
letzten. Das **Brutto** einer Dividende ist das gutgeschriebene Netto-Cash plus
die auf der Transaktion erfasste einbehaltene Steuer; Zinsen
(Portfolio-Performance INTEREST: Kontozinsen oder Anleihekupons) tragen keine
Quellensteuer und werden als eigene Reihe neben Dividenden geführt. Ein Klick auf
ein Jahr öffnet das Detail je Transaktion für dieses Jahr.

Beträge werden in der Basiswährung des Portfolios ausgewiesen, umgerechnet über
den EUR-Hub zum gespeicherten Kurs des jeweiligen Buchungsdatums (dieselbe
Umrechnung wie die Bewertung); die ursprüngliche Währung bleibt je Zeile sichtbar.
Der Bericht ist auch über die API (`GET /api/v1/portfolios/:id/income`) und das
MCP-Tool `portfolixir.portfolios.income` verfügbar.

## Imports

Die Imports-Seite akzeptiert Portfolio-Performance-Transaktionsexporte im Format
CSV oder JSON v1. Dateien werden in eine Vorschau geparst, bevor Datensätze
gespeichert werden. Die Vorschau zeigt übersetzte Transaktionsart-Labels, die
Datensätze, die angelegt würden, und Konto-/Depotzuordnungen für fehlende Ziele.

Parser-Warnungen erscheinen in einem scrollbaren Feld mit Kopier-Button. Der
kopierte Text nutzt stabile `Row N: message`-Zeilen, sodass die Diagnose beim
Quell-Export verbleiben kann. Das Anwenden des Imports ist atomar und nutzt
Inhalts-Hashes, um Duplikate bei erneutem Lauf zu überspringen.

Zeilen mit **unplausiblen Daten** (vor 1900, z. B. ein `0217-12-05`-Tippfehler für
2017) werden je Zeile mit einer klaren Meldung abgelehnt, statt jede abgeleitete
Kennzahl zu vergiften — korrigiere die Buchung in der Quelle und importiere
erneut; die Inhalts-Hashes halten den Wiederholungslauf frei von Duplikaten. Nach
einem Import läuft die Kurs- und Logo-Anreicherung für die angelegten Wertpapiere
als ein gedrosselter Hintergrund-Job, sodass die App reaktionsschnell bleibt,
während Hunderte Wertpapiere synchronisiert werden.

## Kurse und Charts

### Kurshistorie

Jeder Kurseintrag erfasst ein Datum und einen Decimal-Schlusskurs. Die
Preishistorie wird persistiert, sodass Wertpapier-Detailcharts aus lokalen
Datensätzen gebaut werden.

Zwei Wege, auf denen Kurse ins System gelangen:

- **Automatische Synchronisierung**: ein Hintergrund-Scheduler tickt alle sechs
  Stunden (konfigurierbar in
  `config :portfolixir, Portfolixir.Catalog.QuoteSync`) und zieht tägliche
  Schlusskurse vom konfigurierten Anbieter jedes Wertpapiers.
- **Jetzt synchronisieren**: der Button *Sync prices* in der Toolbar (und der
  Button je Wertpapier auf der Detailseite) löst eine sofortige Synchronisierung
  aus, ohne auf den nächsten Tick zu warten.

Kursquellen in dieser Iteration:

- Der Suchschritt (aus welchem Katalog das Wertpapier stammt) nutzt Portfolio
  Performance für Aktien/ETFs/Fonds und CoinGecko für Krypto.
- Neue Wertpapiere starten bei Konfiguration eine Hintergrund-Kurs-/Logo-
  Anreicherung. Die Logo-Erkennung läuft über eine einzelne Hintergrund-
  Warteschlange, scannt beim Start fehlende Logo-Kandidaten und wird auch nach
  Importen ausgelöst. Die ETF-Logo-Erkennung probiert bekannte Emittentennamen
  vor dem einzelnen Fondsnamen (zum Beispiel iShares, Vanguard, Lyxor, Amundi,
  Xtrackers, SPDR, Invesco). Staatsanleihen nutzen die Anlageklasse
  `government_bond` für ISIN-Länderflaggen-Fallbacks.
- Der Kurshistorien-Abruf nutzt Yahoo Finance für beide. Zwei Gründe:
  - PPs eigene API bietet nur Suche, keine Preishistorie.
  - CoinGeckos kostenlose öffentliche API begrenzt die Historie auf 365 Tage
    (`error_code 10012`); Yahoo liefert die volle tägliche Reihe für Krypto über
    die Symbolform `<TICKER>-<CURRENCY>` (z. B. `BTC-USD`).
- Portfolio Performance search can provide symbols for some bonds and leveraged
  products. Yahoo remains usable when a suitable symbol exists und auf dem
  Wertpapier gespeichert ist.
- Ariva is not used as a quote adapter. Sein historischer Endpunkt für
  Hebelprodukte ist derzeit für diesen lokalen Standard-Anwendungsfall blockiert.
- Bundesbank is relevant for German federal securities and yield data, not a
  general ISIN quote provider.
- No API-key-based providers und keine inoffizielle Scraping-Abhängigkeit werden
  als Standard-Kursquellen verwendet.
- No new bond or leveraged-product quote adapter is implemented in this batch.

Yahoo wird mit `period1=0` und `period2=<now>` abgefragt, sodass es die volle
verfügbare tägliche Historie liefert — `range=max` rechnet bei Tickern mit langer
Historie still auf monatlich herunter.

Wertpapiere, deren Anbieter keinen Kurs-Adapter hat oder deren Adapter nicht
laufen kann, weil Pflichtfelder wie der Ticker fehlen, werden mit einem Grund als
übersprungen gemeldet. Fehlgeschlagene Adapter-Aufrufe werden getrennt von
erfolgreichen Synchronisierungen gemeldet.

### Wertpapier-Detailchart

Ohne ausgewähltes Wertpapier füllt die Wertpapierliste den Arbeitsbereich der
Seite. Ein Klick auf eine Zeile öffnet `/securities/:id` in einem vertikal
geteilten Arbeitsbereich: die Liste bleibt im oberen scrollbaren Bereich und der
gewählte Detailbereich öffnet sich darunter. Der horizontale Trenner kann am
Desktop gezogen oder per Tastatur angepasst werden; mobil wird ein gestapeltes
Layout genutzt.

Der Detailbereich zeigt einen serverseitig gerenderten SVG-Preischart mit:

- Zeitraum-Buttons (1M / 3M / 6M / YTD / 1Y / 3Y / 5Y / MAX).
- Einem Schalter *Log scale* (logarithmische Y-Achse).
- Einem Schalter *Show transactions*, der Kauf-/Verkauf-Marker aus dem Ledger
  überlagert.
- Einem Button *Sync prices for this security*.

## Verhalten der Oberfläche

- Der aktive Seitentitel und eine kurze Kontextzeile leben in der oberen Leiste.
  Der Seiteninhalt beginnt direkt mit einem Arbeitsbereich über die volle Breite,
  sodass jede aktive Menü-Route den verfügbaren Platz ohne wiederholte
  Seitenüberschrift oder äußere Seitenränder nutzt.
- Die Wertpapierliste nutzt einen Arbeitsbereich über die volle Breite statt
  generischer Panel-Optik; die Toolbar bleibt am oberen Rand des Arbeitsbereichs
  fixiert, und die Tabelle nutzt darunter die volle horizontale Breite.
- In einem Klassifizierungsbaum sind Kategorien standardmäßig eingeklappt (klicke
  eine Kategorie, um sie aufzuklappen); die Suche klappt die passenden Kategorien
  auf. Lange Wertpapiernamen werden auf eine Zeile gekürzt, mit dem vollen Namen
  beim Überfahren, und der Ticker wird neben dem Namen gezeigt.
- Jedes zugeordnete Wertpapier zeigt seine **aktuelle Menge** (über jedes
  Wertpapierkonto jedes Portfolios summiert) und seinen **aktuellen Marktwert** im
  EUR-Hub, bewertet aus dem letzten Kurs (mit Rückfall auf den zuletzt eigenen
  Handelspreis, wie die Portfoliobewertung). Bestände und Werte werden **einmal**
  für den ganzen Baum geladen, nachdem die Seite verbunden ist, sodass ein großer
  Baum nie eine Abfrage je Zeile auslöst.
- Ein Schalter **Current positions only** ist standardmäßig an. Er verbirgt
  Wertpapiere, die du nicht mehr hältst (aktuelle Menge null), sodass alte oder
  vollständig verkaufte Zuordnungen den Baum nicht überladen. Nichts wird still
  verworfen: jede Kategorie zeigt einen Zähler **+N without holdings** für die
  verborgenen Wertpapiere, und das Ausschalten des Schalters zeigt sie wieder.
- Jede Kategoriezeile aggregiert den **Wert** und die **Positionsanzahl** der
  aktuell in ihr und ihren Unterkategorien sichtbaren Wertpapiere, sodass die
  Summen dem Schalter folgen.
- Die Seitenleiste listet nur existierende Routen plus die wenigen geplanten
  Funktionen mit einem offenen Issue dahinter. Zwei Einträge werden deaktiviert
  mit einer „Soon"-Plakette gezeigt: **Watchlist** und **Returns & risk**. Der
  **Income**-Bericht ist ein aktiver Eintrag (erhaltene Dividenden und Zinsen).
  Allocation, Holdings und Performance sind keine eigenen Menüeinträge — die Seite
  **Portfolio** deckt Asset-Allokation (den Sunburst), Bestände und
  TTWROR-Performance bereits ab.
- Theme: System-, hell- und dunkel-Modus werden unterstützt.
- Akzent: violette, türkise und korallenfarbene Logo-Akzentwahlen werden
  unterstützt.
- Sprache: der erste Aufruf folgt der Browsersprache, wenn sie Englisch oder
  Deutsch ist. Explizite EN/DE-Links überschreiben die Browsersprache und sichern
  diese Wahl.
- Theme, Akzent und Sprache sind Nutzerpräferenzen und beeinflussen gespeicherte
  Finanzwerte nicht.

## Audit-Journal

Jede Änderung an Finanzdaten wird in einem append-only Audit-Journal in derselben
Datenbanktransaktion wie die Änderung selbst festgehalten, sodass jedes Anlegen,
Bearbeiten oder Löschen zurechenbar (wer und wann) und durch Einsicht
nachvollziehbar bleibt (Werte vorher/nachher) — das Sicherheitsnetz dafür, einen
Agenten über die API/MCP schreiben zu lassen. Marktdaten-Synchronisierung (Kurse
und Wechselkurse) ist betrieblich und wird nicht journalisiert. Das Journal ist
über `GET /api/v1/journal` und das passende MCP-Tool `portfolixir.journal.list`
abfragbar (siehe [API und MCP](integration/api-and-mcp.html)). Es deckt derzeit
Wertpapier-Stammdaten ab; die übrigen Schreibbereiche folgen nacheinander. Eine
eigene Ansicht in der App ist als Folgeschritt geplant.

## Heutige Nicht-Ziele

- Kein automatischer Handel und keine Orderausführung.
- Keine Bank-, Broker- oder Wallet-Integrationen.
- Keine Zahlungsplanung oder Abwicklungs-Workflows.
- Keine Broker-PDFs, keine binären Portfolio-Performance-Arbeitsbereiche, keine
  Bank-Synchronisierung, keine Broker-Synchronisierung und keine
  Dokumentenerfassung über den Portfolio-Performance-CSV/JSON-v1-
  Transaktionsexport-Workflow hinaus.

Sparpläne werden bewusst nicht unterstützt. Ein Sparplan beschreibt nur einen
*beabsichtigten* wiederkehrenden Beitrag, und seine Zielwerte weichen
unweigerlich von den realen Ausführungen ab, die ein Broker durchführt —
typischerweise um Cent-Unterschiede bei Preis, Gebühr und Menge. Portfolixir
behandelt die importierten, realen Transaktionen als einzige Quelle der Wahrheit
für Bestände und Performance, sodass das Modellieren separater Sparplan-Ziele
einen parallelen Satz Zahlen hinzufügen würde, der nie ganz zur Realität passt.
Wiederkehrende Beiträge werden daher schlicht als die Transaktionen erfasst, die
sie tatsächlich erzeugt haben.
