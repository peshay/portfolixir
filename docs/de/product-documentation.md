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
2. Lege ein Geldkonto und ein Depot an und verknüpfe sie (nirgendwo eine
   Portfolio-Entscheidung — siehe unten).
3. Erfasse manuelle Kauf- und Verkauftransaktionen mit Decimal-basierten Mengen-
   und Preiswerten.
4. Importiere optional einen Portfolio-Performance-Transaktionsexport über
   Imports, prüfe die Vorschau, ordne fehlende Konten zu und wende dann atomar an.
5. Öffne die Bestandsansicht, um die aktuelle Position je Wertpapier zu prüfen.
6. Erfasse Wertpapierkurse im Zeitverlauf und behalte die Historie für
   reproduzierbare Charts.
7. Prüfe aktuelle Bestände und das Verhalten der Kurscharts direkt in der App.

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
sich die Klasse direkt aus der Liste setzen lässt, ohne die
Wertpapier-Detailseite zu öffnen.

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

### ISIN-Wechsel (Früher-ISIN-Aliasse)

Wenn eine Kapitalmaßnahme einem Wertpapier eine neue ISIN gibt (eine
Fusions-Umbenennung, ein Sitzwechsel), den Wechsel aufzeichnen, statt die ISIN
direkt zu editieren: `POST /api/v1/securities/:security_id/isin-change` (oder
das MCP-Tool `portfolixir.securities.isin_change`) verschiebt die aktuelle
ISIN in einen journalisierten **Früher-ISIN-Alias** und schreibt die neue ISIN
auf dasselbe Wertpapier. Importe treffen danach in beide Richtungen weiter:
Ein alter Export mit der früheren ISIN löst über den Alias auf, ein neuer
Export mit der neuen ISIN über die aktuelle ISIN — kein dupliziertes
Wertpapier, keine duplizierten Buchungen (der Import markiert solche Zeilen
als „über frühere ISIN zugeordnet"). Aliasse sind korrigierbar: sie werden im
Wertpapier-Detail (`GET /api/v1/securities/:id`) gelistet und können
(journalisiert) gelöscht werden, wenn sie versehentlich aufgezeichnet wurden.
Eine bloße Umbenennung braucht keinen ISIN-Wechsel — sie ist nur eine
Namensänderung.

## Konten und Depots

Die Buchhaltungs-Entitäten sind Geldkonten und Depots:

- Geldkonto: verfolgt den Kontext der verfügbaren Liquidität
- Depot/Konto: speichert Wertpapierpositionen, verknüpft mit diesem Geldkonto

Die Seite **Konten & Depots** (Bereich Verwaltung) zeigt beide in **einer
Tabelle, ein Eintrag je Zeile**: jedes Depot bildet eine Zeile, sein
verknüpftes Verrechnungskonto sitzt eingerückt direkt darunter — mit der
Kontowährung und dem beschrifteten **Liquiditätsrollen**-Selektor je Konto
(freies Cash, Kreditlinie, Reserve); ein Geldkonto ohne verknüpftes Depot
bekommt eine eigene Zeile. Ein von mehreren Depots geteiltes Konto trägt
seine Bedienelemente nur unter seinem ersten Depot — spätere Zeilen zeigen
*geteilt — oben verwaltet*.

**Bucket-Chips (#559).** Jede Zeile zeigt ihre Bucket-Zugehörigkeiten als
Chips — den exklusiven **Scope**-Bucket als gefüllten Chip, freie **Tags**
als Umriss-Chips, eingefärbt mit der Bucket-Farbe, wenn eine gesetzt ist.
Tragen Depot und Verrechnungskonto dieselben Buckets, zeigt das Paar **eine
zusammengeführte Chip-Gruppe mit der Marke „Beide"** über beide Zeilen; der
Link **Getrennt taggen** daneben teilt die Gruppe, sodass jede Seite eigene
Tags bekommt (unterschiedliche Mengen erscheinen immer getrennt). Je Gruppe
sind höchstens vier Chips sichtbar — weitere klappen in einen **+N**-Chip,
und der Picker führt die vollständige Menge. Lange Namen (etwa
datumsgestempelte Import-Tags) werden gekürzt; der volle Name erscheint beim
Überfahren des Chips. Die Chips sind die Gruppierungs-UI: das **+** öffnet
ein kleines Picker-Popover mit den übrigen Buckets plus einem Inline-Feld
**Neuer Tag**, das einen Tag in einem Schritt anlegt und zuweist, und das
**×** auf einem Chip entfernt die Zugehörigkeit. Änderungen an einer
zusammengeführten Gruppe gelten für Depot und Verrechnungskonto gemeinsam.
Jede Änderung läuft durch den audit-journalisierten Bucket-Kontext; der
Versuch, einen zweiten Scope-Bucket zuzuweisen, wird mit einer Inline-Meldung
abgelehnt, denn die Scope-Dimension bleibt exklusiv (ADR-0024).

**Ein Anlage-Dialog (#491).** Der Knopf **Depot & Konto anlegen** öffnet
einen Dialog, der ein Depot zusammen mit seinem verknüpften
Verrechnungskonto in einem Fluss anlegt — oder ein Geldkonto allein, oder
ein Depot verknüpft mit einem bestehenden Konto. Optional vergibt der Dialog
**anfängliche Buckets**: bestehende Buckets ankreuzen und/oder einen neuen
Tag eintippen, und jeder vom Dialog angelegte Datensatz startet mit dieser
Zugehörigkeit.

**Nirgendwo ist eine Portfolio-Entscheidung nötig** (ADR-0024): Gruppierung
passiert ausschließlich über Buckets und Ansichten. Wird ein Depot oder
Geldkonto angelegt — im Dialog oder über API/MCP — löst sich die interne
Bindung deterministisch auf ein Standard-Portfolio auf (den ältesten
Datensatz, sonst ein frisch angelegtes „Default“), ohne nachzufragen.

Durchgearbeitete Beispiele — Haushalts-Aufteilung, Strategie-Ansichten mit
eigenen SOLL-Plänen, Übersetzen von Portfolio-Performance-Gewohnheiten und
das Ausschließen einer Position aus der Steuerung — stehen im Leitfaden
[Buckets & Ansichten](guides/buckets-and-views.html).

### Portfoliodatensätze (Kompatibilität)

Portfolios bleiben als **interne Kompatibilitätsdatensätze** im Schema, in der
JSON-API und im Importpfad erhalten. Die Seite **Konten & Depots** im
Administrationsbereich trägt ein eingeklapptes, schreibgeschütztes Panel
**Portfoliodatensätze (Kompatibilität)**, das jeden Datensatz auflistet —
Name, Basiswährung, Anlagedatum, Quelle (UI, API, Import oder Seed, abgeleitet
aus dem Audit-Journal) sowie die Zahl der gebundenen Depots und Geldkonten —
damit über API/MCP angelegte Datensätze nie unsichtbar werden. Es gibt keine
Anlage- oder Bearbeitungs-UI; die API-Schreibendpunkte sind veraltet (siehe
[API und MCP](integration/api-and-mcp.html)), und eine Folge-Story
verschmilzt die Datensätze nach zwei Releases ohne externe Portfolio-Writes
in Buckets und Ansichten.

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

Während ein **Verkauf** erfasst wird, zeigt das Formular eine Vorschau,
welche FIFO-Kauftranchen (Lots) der Verkauf verbrauchen würde und den
**Bruttogewinn** je Tranche und in Summe — Verkaufserlös minus
FIFO-Anschaffungskosten der verbrauchten Lots, vor Gebühren, zum
eingegebenen Preis (oder zum zuletzt gespeicherten Preis, bis einer getippt
ist). Die Zahl ist indikativ und keine Netto-Größe; das Buchen des Verkaufs
ändert nichts daran, wie der Einstand gespeichert wird (Bestände behalten
ihren gleitenden Durchschnitt, der Trades-Tab das FIFO-Matching). Lots
werden first-in, first-out über alle Depots gematcht, wie in der
Trades-Ansicht split-skaliert, und währungsübergreifende Tranchen tragen
dieselbe Kurs-/Währungszerlegung wie die Bestände — oder einen ehrlichen
Strich, wenn sie nicht ableitbar ist. Eine eingegebene Menge über den
offenen Lots wird mit dem ungedeckten Fehlbetrag markiert.

### Bestandsberechnung

Aktuelle Bestände werden nicht manuell erfasst. Sie werden aus allen
Transaktionen im Zeitverlauf abgeleitet, sodass der Zustand reproduzierbar und
nachvollziehbar ist. Gehaltene Mengen bewegen sich mit Käufen und Verkäufen, mit
ein-/ausgehenden **Lieferungen** (Anteile, die ohne Geld-Bein ein- oder
austreten, z. B. ein Depotübertrag von einer anderen Bank) und mit
**Wertpapierübertragungen** zwischen eigenen Depots. Jeder Bestand trägt
außerdem einen gleitenden Durchschnitts-Einstandswert und den nicht realisierten
Gewinn/Verlust (absolut und prozentual) gegen den zuletzt gespeicherten Preis, in
der eigenen Währung des Wertpapiers. Der Einstandswert wandert mit den Anteilen:
Käufe (und mit Preis erfasste Einlieferungen) fügen Einstand hinzu, Verkäufe und
Auslieferungen entnehmen ihn zum laufenden Durchschnitt, und eine
Wertpapierübertragung nimmt den Einstand der bewegten Anteile mit ins Zieldepot.
Eine ohne Preis erfasste Lieferung bewegt die Menge zum Einstand null, da für
sie kein eigener Anschaffungswert bekannt ist.

Für ein Wertpapier, das in einer anderen Währung notiert als das Geld, das es
bezahlt hat, zerlegt jeder Bestand seinen Gewinn oder Verlust in Basiswährung
zusätzlich in zwei benannte Teile (ADR-0033): den **Kursbeitrag** — die
Veränderung des eigenen Kurses des Wertpapiers, zum heutigen Wechselkurs
umgerechnet — und den **Währungsbeitrag** — die Wirkung des Wechselkurses auf
den ursprünglich investierten Betrag. Zusammen ergeben sie exakt den gesamten
Gewinn oder Verlust der Position in Basiswährung. Für Positionen in der
Basiswährung ist der Währungsbeitrag exakt null. Eine Position, deren
Zerlegung sich nicht aus den erfassten Buchungen ableiten lässt (etwa ein
importierter währungsübergreifender Handel ohne gespeicherten Kurs am
Buchungstag), zeigt einen Strich statt einer geratenen Zahl; die Aufgabe
`mix portfolixir.backfill_settlement_legs` leitet die fehlenden Beine für
historische Importe ab, sobald Kurse für die Buchungstage gespeichert sind.

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
mit dem gespeicherten Ziel und meldet die **Drift** — Ist minus Soll (positiv =
übergewichtet, negativ = untergewichtet; ADR-0023), sowohl als Gewicht als auch
als Betrag in Basiswährung, d. h. wie viel zu verkaufen (positiv) oder zu kaufen
(negativ) ist, um das Ziel zu erreichen. Gehaltene, aber im gewählten Baum nicht
zugeordnete
Wertpapiere werden in einem Topf für nicht Zugeordnetes summiert. Nur die Ziele
werden gespeichert; die Ist-Seite wird beim Lesen aus der Live-Bewertung
abgeleitet.

> **Ziele je Position (ADR-0030, #481).** Zielgewichte lassen sich nun bis auf
> eine **einzelne Position** setzen (ein Wertpapier unter einer Kategorie), nicht
> mehr nur je Kategorie. Positionen sind die Quelle der Wahrheit: das *effektive*
> Ziel einer Kategorie rollt aus ihren Positionen auf (deren Summe); trägt eine
> Kategorie zusätzlich ein eigenes explizites Gewicht, wird die Abweichung
> sichtbar gemacht statt stillschweigend verworfen. Der erste Schritt liefert
> das Datenmodell und die **API/MCP**-Oberfläche: ein Positionsziel setzt man,
> indem man einem Zieleintrag eine `security_id` hinzufügt; die Positionszeilen
> und die Kategorie-Aufrollung liest man über den Positions-Ziel-Endpunkt bzw.
> das entsprechende Werkzeug (siehe Integrationsleitfaden). Wird ein Wertpapier
> später umklassifiziert oder die Zuordnung entfernt, zählt sein Positionsziel
> weiter unter der Kategorie, unter der es abgelegt wurde, und wird beim Lesen
> der Positionsziele als *stale* (veraltet) markiert — zum Verschieben des
> Gewichts legt man es neu ab. Seit Schritt 2a **zeigt die Allokationsansicht**
> die Positions-Soll/Drift an — auch für noch nicht gehaltene Positionen (IST 0,
> Marker *ohne Bestand*) — und die Kategorie-Zeilen steuern nach der effektiven
> Aufrollung. Die Editor-Oberfläche für die Eingabe je Position und die
> gleichmäßige Auto-Verteilung folgen in späteren Schritten.

### Einen SOLL-Plan auf der Klassifizierungsseite bearbeiten

Zielgewichte sind nicht global: ein **SOLL-Plan gehört zu einer Sicht** (siehe
ADR-0020). Ein Plan wird auf der **Klassifizierungsseite** bearbeitet, im
Bereich **Soll-Plan** der Detailansicht eines eigenen Baums. Oben in diesem
Bereich wählt ein **Sicht-Selektor** („Soll-Plan für Sicht: [Gesamt ▾]“),
welcher Plan bearbeitet wird; die Voreinstellung **Gesamt** ist der
portfolioweite Plan, der sich wie ein einziges globales Zielset verhält. Wechselt
man den Selektor, werden die gespeicherten Gewichte und das Cash-Ziel dieses
`(Sicht, Klassifizierung)`-Plans geladen — Gesamt und jede benannte Sicht tragen
**unabhängige** Pläne, sodass derselbe Baum je Sicht einen anderen 100 %-Plan
oder gar keinen halten kann.

Die Zustände sind:

- **Noch kein Plan.** Der Bereich zeigt einen Leerzustand mit **Plan anlegen**
  und, wenn eine andere Sicht bereits einen Plan für diesen Baum hat, einen
  Selektor **Aus anderer Sicht übernehmen…**, der den Editor aus diesem
  Quellplan vorbefüllt. Bis zum Speichern wird nichts geschrieben.
- **Ein Plan existiert.** Jede Kategorie erhält ein **Soll %**-Feld, und darunter
  steht ein **Cash**-Zielfeld; **Plan speichern** schreibt den gesamten
  `(Sicht, Klassifizierung)`-Plan auf einmal. Eine Live-**Σ**-Fußzeile summiert
  die Kategoriegewichte plus das Cash-Ziel und zeigt bei genau 100 % ein ✓, sonst
  ein ✗ mit dem gelben Abweichungshinweis — und aktualisiert sich beim Tippen.
- **Plan löschen** entfernt den Plan der Sicht; die Vermögensseite fällt für
  diese Sicht dann auf **nur IST** zurück (kein SOLL, keine Drift).

Gewichte werden als **Prozentsätze** eingegeben und angezeigt (z. B. `60`) und als
Brüche in `[0, 1]` gespeichert. Die Felder sind beschriftet und per Tastatur
fokussierbar, und derselbe Plan ist über die API/MCP-Ziel-Endpunkte mit einem
`view`-Parameter gleichermaßen erreichbar.

### Plan-Versionen: duplizieren, Entwurf, aktivieren

Seit ADR-0027 ist ein Plan eine **benannte Version** mit Status — *aktiv*,
*Entwurf* oder *archiviert* — und je Geltungsbereich gibt es höchstens einen
aktiven Plan. So wird eine Strategie umgebaut, ohne den alten Plan zu verlieren:

- **Plan duplizieren** kopiert den aktuellen Plan (Kategoriegewichte und
  Cash-Ziel) in einen **Entwurf**; der Editor wechselt dorthin, und sobald ein
  Geltungsbereich mehr als eine Version hat, erscheint neben dem Sicht-Selektor
  ein **Plan-Versions-Selektor**.
- Einen **Entwurf** zu bearbeiten und zu speichern berührt den aktiven Plan
  nie — die Vermögensseite folgt weiter dem aktiven Plan, und ein Hinweis im
  Editor sagt das auch. Die **Cash-Ziel**-Zeile zeigt den aktiven
  Steuerungswert (er zählt in die Σ-Prüfung), ist aber gesperrt, solange eine
  Version bearbeitet wird — mit sichtbarem Hinweis: die Cash-Quote bleibt bis
  zum Wechsel bei der aktiven Steuerung (v1).
- **Diesen Plan aktivieren** schaltet den Entwurf scharf; der zuvor aktive
  Plan wird in derselben Transaktion archiviert — alter und neuer Plan bleiben
  nebeneinander einsehbar.
- **Umbenennen** benennt die ausgewählte Version um — z. B. um nach der
  Aktivierung ein „(Entwurf)"-Suffix loszuwerden.
- **Plan löschen** entfernt bei einem Entwurf oder archivierten Plan nur diese
  Version; beim aktiven Plan behält es die ADR-0020-Bedeutung (der
  Geltungsbereich fällt auf nur IST zurück).

Jede Plan-Änderung wird im Audit-Journal festgehalten.

> **Migrationshinweis (ADR-0020).** Der Wechsel zu Plänen je Sicht ist
> **verlustfrei**: alle bereits vorhandenen Zielgewichte und das frühere
> portfolioweite Cash-Ziel werden zum **Gesamt**-Plan (`view = null`). Am
> Verhalten ändert sich nichts — das bestehende Setup erscheint einfach unter
> *Gesamt*, und die Vermögensseite liest es unter der Sicht **Total** genau wie
> zuvor. Benannte Sichten starten **ohne Plan**, bis einer angelegt oder
> kopiert wird.

Um eine Position **aus der Allokations-Steuerbasis** herauszuhalten, während sie
weiterhin zum Gesamtvermögen zählt — zum Beispiel ein als langfristiger
Wertspeicher gehaltener Bitcoin statt Teil des gesteuerten Mix — das
Wertpapier mit einem **Bucket** versehen und **diesen Bucket aus der
Strategie-Ansicht ausschließen**; die Allokation dann unter dieser Ansicht lesen. Die
Position fällt dann aus dem Geltungsbereich der Ansicht: sie verschwindet aus den
100 % und der Drift-Tabelle und hebt den Ist-Prozentsatz jeder anderen Kategorie
konsistent an, während Gesamtwert, Bestände und Performance (ohne die Ansicht
gelesen) unverändert bleiben. (Dies ersetzt den früheren wertpapierbezogenen
Schalter „von Allokationszielen ausgeschlossen“; siehe ADR-0013/ADR-0018.)

Klassifizierungsbäume sind **hierarchisch**, und die Allokation rollt sie auf:
eine einer Unterkategorie zugeordnete Position zählt zu dieser Unterkategorie
**und jeder übergeordneten Kategorie darüber**. Hält *Growth* also ein Ziel von
50 % und sind Bestände nur seinen Unterkategorien zugeordnet (*Tech*, *Emerging*,
…), ist das Ist-Gewicht von *Growth* deren Summe — nicht 0 % — und seine Drift
wird gegen diese Summe gemessen. Die Drift-Tabelle listet Kategorien in
Baumreihenfolge mit unter ihren Eltern eingerückten Unterkategorien; da jede
übergeordnete Kategorie ihre Kinder bereits enthält, summieren sich die
angezeigten Ist-Prozentsätze nur über die Blätter (plus nicht Zugeordnetes) zu
100 %, nicht über jede Ebene.

Ziele bleiben **bewusst locker**: ein Gewicht kann auf oberster Ebene und auf
Unterebenen gesetzt werden, ohne dass die App sie zur Summe 100 % zwingt. Um diese
Freiheit zu bewahren und zugleich Abweichungen sichtbar zu machen, zeigt die
Vermögensseite zwei **beratende Konsistenzhinweise** — schreibgeschützt, ein
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
Allokation **Wertpapiere (innerhalb der aktiven Ansicht) + das Cash, das zur
Cash-Quote zählt** (die als *counts toward the cash quote* markierten Konten). Die
Drift-Tabelle zeigt dann eine eigene **Cash**-Zeile in eigener neutraler Farbe mit
Cash-Ist, -Ziel und -Drift, der Sunburst erhält ein Cash-Segment, und jeder
Kategorie-Prozentsatz schrumpft entsprechend, sobald Cash zur Basis hinzukommt.
Setze das Cash-Ziel im **Cash**-Feld des Plan-Editors auf der
Klassifizierungsseite (je Sicht), über die API (`PATCH /api/v1/portfolios/:id`)
oder MCP (`portfolixir.portfolios.set_cash_target`), oder lösche es mit `null`, um
die Steuerung einer Cash-Quote zu beenden.

**Währungsallokation: Cash nach Währung.** Ist die aktive Klassifizierung der
eingebaute **Währungs**-Baum, wird das Cash jedes Geldkontos seiner eigenen
Währungskategorie zugeordnet statt als separate „Cash"-Zeile zu erscheinen: EUR-Cash
fließt in die EUR-Kategorie, USD-Cash in USD usw. Fremdwährungs-Salden werden vor
der Addition über den EUR-Hub in die Basiswährung umgerechnet, sodass die Prozentsätze
in der Portfolio-Basiswährung bleiben. Die Gesamtbasis (Wertpapiere + verfügbares Cash)
bleibt unverändert — nur die *Zuordnung* von Cash zu einer Währungskategorie ändert sich.
Die Asset-Klassen-Ansicht ist davon unberührt: sie behält eine eigene **Cash**-Steuerzeile.

## Wechselkurse und Bewertung

Portfolios können Wertpapiere und Cash in mehreren Währungen halten. Wechselkurse
werden gegen einen EUR-Hub gespeichert (mit Synchronisierung der Europäischen
Zentralbank), und andere Paare werden darüber trianguliert. Die Live-Bewertung des
Portfolios rechnet den Marktwert jeder Position und jeden Cash-Saldo in die
Basiswährung des Portfolios um.

Ein Wertpapier ohne jeden Kurs wird mit dem **zuletzt eigenen Handelspreis
über alle Portfolios** bepreist — ein Kauf oder Verkauf ist eine
Preisbeobachtung, genau so, wie Portfolio Performance Preise aus Buchungen
ableitet — sodass ein frisch importiertes Portfolio nicht mit null bewertet
wird, während Kurse noch geholt werden. Der Fallback ist bewusst global: die
Portfoliosummen und die Wertpapier-Detailansicht lösen Preise mit derselben
Logik auf, sodass die beiden Ansichten nie uneinig sein können, ob ein Preis
existiert. Solche Positionen tragen `price_source: "trade"` in der API und
werden in `trade_priced_count` gezählt; die Vermögensseite markiert sie als
Datenqualitäts-Hinweis und die Detailansicht nennt den Handelspreis, mit dem
bewertet wird.

Eine Position mit weder Kurs noch Handelspreis oder ohne Kurspfad zur
Basiswährung wird als unbewertet gemeldet, sodass ein fehlender Preis oder
Kurs nie still den Gesamtwert oder die Gewichte verzerrt. Die beiden Fälle
werden ehrlich getrennt gemeldet (`unvalued_reason` in der API): **gar kein
Preis** (nichts auflösbar — kein Kurs und kein eigener Handel) oder **Preis
bekannt, aber kein Wechselkurs gespeichert** — der native Preis wird
weiterhin mit seiner Währung angezeigt, und eine Wechselkurs-Synchronisierung
holt die Position in die Summen. Eine Position mit Preis, aber ohne
Wechselkurs zählt in den Basiswährungs-Summen als *nicht bewertet*. Die
Detailansicht zeigt die passende Statuszeile ("Nicht in den Summen
berücksichtigt — …"), sodass beide Ansichten einen fehlenden Wert gleich
erklären.

## Cash und Cash-Quote

Cash ist Teil des Portfolios, kein Nachgedanke. Jedes Portfolio hat ein oder
mehrere Geldkonten, und die Live-Bewertung meldet das **gesamte Cash**, den
**Gesamtwert inklusive Cash** und die **Cash-Quote** — Cash als Anteil am
Gesamtportfolio — Liquidität und trockenes Pulver auf einen Blick,
umgerechnet in die Basiswährung des Portfolios.

Das Verrechnungs-Cash eines Depots bleibt von selbst aktuell: Käufe, Verkäufe,
Dividenden, Zinsen, Gebühren und Steuern bewegen es, sobald diese
Transaktionen erfasst werden, sodass das zum Investieren gehörende Cash keine
separate Pflege braucht.

Für externe Konten (ein Girokonto, Sparkonto, ein Geschäftskonto) ist das Ziel
Sichtbarkeit ohne Buchhaltung. Statt jede Buchung zu spiegeln, wird der
**Saldo eines Kontos direkt gesetzt** — die Zahl, die die Banking-App zeigt,
erfasst als datierter **Snapshot** (das Saldo-setzen-Formular auf der
Vermögensseite, `POST /api/v1/cash_accounts/:id/balance` oder das MCP-Tool
`cash_accounts.set_balance`). Der Saldo verankert sich dann an diesem Betrag, und
nur Buchungen mit einem Datum strikt nach dem Snapshot verändern ihn; so braucht
Geld zwischen eigenen Konten zu verschieben keine Übertragungsbuchung — jeder
Saldo wird nur ab und zu neu angegeben. Der Betrag darf negativ sein (ein
Überziehungskredit), und derselbe Snapshot kann später automatisch über die API
befüllt werden (ein Skript oder ein nur lesender Bankexport) — ohne Portfolixir in
eine Banking-App zu verwandeln. Dies folgt dem in
[ADR-0009](/decisions/0009-cash-as-balance-snapshots.html) festgehaltenen Entwurf.

Jedes Geldkonto trägt eine **Liquiditätsrolle** (`liquidity_role`; der Selektor
sitzt neben dem Konto auf der Seite Konten & Depots). Sie ist einer von drei Werten:
**free cash** (Standard — echtes verfügbares Cash), **credit line** (eine
Überziehungs- oder Lombard-Linie, deren negativer Saldo eine Verbindlichkeit ist
und deren ungenutzter Rahmen nie Liquidität ist) oder **reserve** (ein
sichtbarer, aber ausgeschlossener Topf, z. B. ein Geschäftskonto). Nur
free-cash-Konten mit nicht-negativem Saldo zählen als verfügbares Cash und gehen
in die Cash-Quote ein; eine Kreditlinie zählt nie (auch bei positivem Saldo —
der Typ schlägt das Vorzeichen), und eine Reserve ist immer ausgeschlossen. Jedes
Konto bleibt im gesamten Cash, sodass eine gezogene Kreditlinie das
Nettovermögen korrekt mindert, aber die Quote wird nur über das verfügbare Cash
berechnet und meldet nie Schein-Liquidität. Die Vermögensseite dämpft nicht
verfügbare Zeilen und beschriftet sie mit ihrer Rolle.

## Übersichts-Seite

Der Eintrag **Übersicht** (die Startseite) beantwortet „Hat sich etwas
geändert, braucht etwas meine Aufmerksamkeit?" (ADR-0022). Bei leerer
Datenbank ist sie der Onboarding-Assistent (der geordnete Workflow-Pfad plus
Zähler). Sobald Transaktionen existieren, zeigt sie eine **Wert-Karte,
eingegrenzt auf die Standard-Ansicht** — **Alles**, wenn keine gesetzt ist
(ADR-0024: Ansichten, nicht Portfolios, sind das, worüber die Übersicht
aggregiert) — mit dem Gesamtwert inkl. Cash, der **YTD-TTWROR** als
Änderungssignal und der Cash-Quote, eine Liste
**Braucht Aufmerksamkeit** — jede Kategorie mit Ziel, deren Allokations-Drift
**±5 Prozentpunkte** überschreitet (ADR-0023-Vorzeichen: positiv =
übergewichtet), schlimmste zuerst, jeweils verlinkt in den Tab „Allokation &
Ziele" des Vermögens-Bereichs — und die **Datenqualitäts-Karte** (Wertpapiere
ohne aktuellen Kurs, Anlageklasse oder Logo). Es gibt bewusst keinen
Aktivitäts-Feed: die forensischen Details gehören dem Audit-Journal.

## Vermögens-Seite

Der Eintrag **Vermögen** in der Navigation öffnet die Vermögensübersicht,
organisiert in Tabs (ADR-0022): **Bestände** (Wert, Performance, Datenqualität,
Cash), **Allokation & Ziele** (Sunburst und Drift-Tabelle) und **Erträge** (der
Bericht über erhaltene Dividenden und Zinsen). Der Bestände-Tab zeigt den
Gesamtwert inklusive Cash, die Cash-Quote sowie sowohl die TTWROR als auch den
geldgewichteten **IRR** für einen wählbaren Zeitraum (laufendes Jahr, ein/drei/fünf
Jahre oder seit der ersten Transaktion; ein Jahr ist die Voreinstellung) mit
dem kumulativen Performance-Chart. Daneben stehen das **eingesetzte
Kapital** — immer zwei beschriftete Zahlen, der Wert zum Periodenbeginn und
die externen Nettoflüsse (Einzahlungen minus Entnahmen, Einlieferungen zum
Transaktionswert), nie eine zusammengelegte Zahl — und der
**Vermögens-Multiplikator**: Endwert ÷ eingesetztes Kapital, das ehrliche
„was aus dem eingezahlten Geld geworden ist". Bei eingesetztem Kapital von
null oder darunter zeigt der Multiplikator `n/a` — nie einen negativen
Multiplikator. Für Zeiträume unter einem Jahr trägt die geldgewichtete
Kennzahl das Label **MWR** und zeigt die Periodenzahl statt einer
annualisierten, die ein kurzes Fenster aufblähen würde (ADR-0034). Neben den festen Buttons verkettet ein
Jahres-Dropdown jedes einzelne Kalenderjahr mit Daten, und ein Von/Bis-
Datumsbereich verkettet eine eigene Spanne — beides sind reine Neuverkettungen
der bereits berechneten Reihe, ehrlich auf die vorhandene Historie begrenzt
(ein rückwärts gerichteter Bereich wird mit kurzem Hinweis abgelehnt).
Auf dem Tab **Allokation & Ziele** zeigt der **Allokations-Sunburst** die Klassifizierung als
konzentrische Ringe — der innere Ring sind die obersten Kategorien, jeder äußere
Ring bricht eine Ebene weiter herunter mit in ihren Eltern verschachtelten
Unterkategorie-Bögen, und der **äußerste Ring zeigt die einzelnen Positionen** als
schattierte Bögen in der Farbe ihrer Kategorie (der Portfolio-Performance-Stil) —
mit einem grauen Segment für nicht zugeordnete Bestände. Kategorien ohne
gewählte Farbe erhalten automatisch unterscheidbare Palettenfarben, sodass
auch ein ungestylter Baum lesbar bleibt. Wie bei PP tragen die
Segmente keinen Text im Chart: das Überfahren eines Segments zeigt seinen Namen,
Anteil und Wert in einem **sofortigen, eigenen Tooltip**, der dem Zeiger folgt
(keine Browser-Hover-Verzögerung), und ein Segment kann **angetippt** werden, um
dasselbe unter dem Chart wiederzugeben (der mobile Ersatz für Hover). Mit
deaktiviertem JavaScript fallen die Segmente auf den nativen Browser-Tooltip
zurück. Der Chart skaliert auf die verfügbare Breite. Wähle einen beliebigen
Klassifizierungsbaum aus dem Selektor. Die Drift-Tabelle darunter listet jede
Kategorie in Baumreihenfolge mit **eingerückten Unterkategorien** unter ihren
Eltern und vergleicht das aufgerollte Ist-Gewicht mit dem gespeicherten Ziel,
wobei die Drift in der Basiswährung neu ausgewiesen wird. Der Baum startet eingeklappt auf der obersten Ebene; jede Zeile mit Kindern
trägt einen **Aufklapp-Pfeil (▸)** — die ganze Namenszelle ist klickbar —, der
ihre direkten Kinder zeigt — Unterkategorien wie Positionen (auch der graue
Eimer *Nicht zugeordnet* klappt so in seine Wertpapiere auf) —, und ein
einzelner Umschalter **Alles aus-/einklappen** über der Tabelle öffnet oder
faltet den ganzen Baum bis zur Einzelposition. Ein Umschalter **Baum |
Positionen** tauscht die Hierarchie gegen eine flache Rebalancing-Arbeitsliste:
eine Zeile je Wertpapier (inkl. Cash) mit der Kategorie als Kontext,
standardmäßig nach vorzeichenbehafteter Drift sortiert (stärkstes Übergewicht
zuerst, stärkstes Untergewicht zuletzt) und über die Spaltenköpfe (Wert, Drift
oder Kategorie) umsortierbar. Eine Kategorie mit direkt zugeordneten Wertpapieren klappt in
ihre Wertpapiere auf — jedes mit Wert, Gewicht, seinem Anteil an der
Kategorie-Drift und einem reinen **Anzeige-Rebalancing-Hinweis**: die indikative
Stückzahl, die zum Bewertungskurs zu verkaufen (positive Drift) oder zu kaufen
(negative) wäre, um die Lücke zu schließen (ADR-0023). Der Hinweis modelliert
keine Gebühren oder Steuern, und hinter ihm steht bewusst kein Order-Knopf —
das Handeln bleibt vollständig manuell.

**Positions-Ziele erscheinen im Plan (ADR-0030 Schritt 2a).** Trägt der aktive
Plan Soll-Gewichte je Position, zeigt jede solche Positions-Zeile ihr eigenes
Ziel und ihre eigene Drift (Ist-Gewicht minus ihr Ziel) — und eine Position
mit gesetztem Soll, aber **noch ohne Bestand**, erscheint
trotzdem: mit IST 0, dem Marker *ohne Bestand* (in einer benannten Ansicht
*ohne Bestand in dieser Ansicht*, denn die Ansicht sagt nichts über das ganze
Depot), der vollen Untergewichts-Drift und einem Kauf-Hinweis zum letzten
gespeicherten Kurs — der Tooltip des Hinweises nennt das Kursdatum, zu dem er
gepreist ist. Ganz ohne Kurs erklärt ein Chip *kein Kurs* den fehlenden
Stück-Hinweis (Kurs hinterlegen, um einen zu bekommen). „Im Bestand" heißt:
die Position wird überhaupt gehalten — ein gehaltenes Wertpapier, dessen Preis
sich nicht ermitteln lässt, behält seine Datenqualitäts-Hinweise und wird nie
als *ohne Bestand* umetikettiert. Ausgeblendet wird eine Positions-Zeile nur,
wenn ihr Soll 0 oder nicht gesetzt ist **und** ihr Bestand null ist. Die
Ziel-Spalte der Kategorie zeigt dann das **effektive** Ziel — die Summe ihrer
Positions-Ziele (Positionen sind die Quelle der Wahrheit); weicht das
gespeicherte Kategorien-Gewicht ab oder ist ein Positions-Ziel veraltet (sein
Wertpapier wurde verschoben oder die Zuordnung entfernt), erklärt ein kleines
Badge an der Kategorie-Zeile den Grund, und die betroffene Positions-Zeile
selbst trägt einen Chip *veraltetes Soll*. Ein gehaltenes, aber nicht
zugeordnetes Wertpapier mit einem (veralteten) Positions-Ziel zeigt dieses
Ziel auch an seiner Zeile im Bereich *Nicht zugeordnet*. Trägt keine
Top-Level-Kategorie ein Ziel, wohl aber tiefere Kategorien, ergänzt die
Σ-Kopfzeile die Summe der tieferen Ziele („Ziele tiefer im Baum") statt ein
nacktes 0 % zu zeigen. Der Cash-Abschnitt
listet den Saldo jedes Kontos und trägt das **Saldo-setzen-Formular**: den
Saldo eingeben, den die Bank zeigt, und der Snapshot wird ohne Buchung einzelner
Transaktionen erfasst.

**Die Seite ist auf eine Ansicht eingegrenzt (ADR-0024).** Die Kopf-Summen und
der Cash-Abschnitt folgen der **aktiven Ansicht über alle Portfolios hinweg** —
**Alles** (englisch *Everything*) ist die eingebaute Voreinstellung und zeigt
jede Position, jedes Konto genau einmal gezählt. Wähle eine Ansicht im
**Sicht-Umschalter** oben auf der Seite — sein **Verwalten…**-Link öffnet die
Ansichten-Seite, auf der Ansichten und ihre Buckets bearbeitet werden;
**Als Standard festlegen** merkt sich
die Wahl serverseitig, sodass Vermögensseite und Übersicht mit dieser Ansicht
öffnen, solange keine andere ausdrücklich gewählt ist (eine ausdrückliche
Wahl — auch von „Alles" — gewinnt immer). Teilen sich die Buckets der aktiven
Ansicht ein Konto, erinnert ein Badge neben der Summe — *Überlappende Buckets –
Konten nur einmal gezählt* — daran, dass sich Werte je Bucket überschneiden und
nicht summiert werden dürfen; die Summe selbst ist bereits dedupliziert.
Ansicht-bezogene Performance-Reihen tragen das Label *Zusammensetzung per
heute*: die aktuelle Bucket-Zuordnung der Ansicht gilt rückwirkend für die
gesamte Historie, und Bucket-Änderungen stehen im Audit-Journal. Nach der
einmaligen ADR-0024-Migration, die aus jedem Portfolio einen Bucket und eine
gleichnamige Ansicht gemacht hat, zeigt die Seite einen **schließbaren
Hinweis** mit den angelegten Ansichten; das Schließen wird gemerkt. (Leere
Datenbank migriert und Daten erst danach eingespielt? Einmal
`mix portfolixir.seed_scope_buckets` ausführen, um die fehlenden
Bucket/Ansicht-Paare anzulegen — der Befehl ist idempotent.) Die
Standard-Ansicht ist auch über die API (`GET`/`PUT
/api/v1/settings/default_view`) und die MCP-Tools
`portfolixir.settings.get_default_view` / `set_default_view` les- und setzbar.
Durchgearbeitete Klick-für-Klick-Setups (Haushalts-Aufteilung,
Strategie-Ansichten, PP-Migrationsgewohnheiten) stehen im Leitfaden
[Buckets & Ansichten](guides/buckets-and-views.html).

**Die SOLL-Seite folgt der aktiven Sicht (ADR-0020).** Die Spalten Ziel, Drift
und *Σ target top level* der Drift-Tabelle spiegeln den **Plan der aktiven
Sicht** für die gewählte Klassifizierung wider — IST und SOLL bewegen sich immer
zusammen. Beim Wechsel des **Sicht-Umschalters** oben auf der Seite springen
beide Seiten gleichzeitig auf den Plan dieser Sicht, sodass nie zwei Pläne zu
einer Σ über 100 % oder einer Geisterzeile vermischt werden. Die eingebaute
Ansicht **Alles** (früher *Total*) liest den portfolioweiten **Gesamt**-Plan. Ein dezenter Punkt auf einem
Sicht-Chip markiert die Sichten, die bereits einen Plan für die aktuelle
Klassifizierung tragen, sodass gesteuerte und reine IST-Sichten auf einen
Blick unterscheidbar sind.

**Kein Plan für die aktive Sicht?** Hat die aktive Sicht keinen Plan für die
gewählte Klassifizierung, bleibt die Allokation **nur IST**: Sunburst und die
Spalten Wert/Ist zeigen weiter die tatsächliche Aufteilung, aber es gibt keine
Spalten Ziel, Drift oder Σ. An ihrer Stelle erklärt ein Hinweis — *Kein Soll-Plan
für diese Sicht* — die leere SOLL-Seite und **verlinkt direkt in den
Klassifizierungs-Plan-Editor, mit dieser Sicht und Klassifizierung bereits
vorausgewählt**, sodass sich der Plan anlegen lässt, ohne beides erneut zu wählen.
Auch das Ziel der Cash-Zeile stammt aus dem Cash-Ziel des Plans der aktiven Sicht
(oder zeigt einen Strich, wenn keines gesetzt ist).

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
den Summen ausgenommen, namentlich gelistet), Positionen mit bekanntem Preis,
aber ohne Wechselkurs zur Basiswährung (aus den Summen ausgenommen; mit ihrem
nativen Preis gelistet, damit sichtbar ist, was eine Kurssynchronisierung
einbringen würde), Wertpapiere mit **negativer** abgeleiteter Bestandsmenge —
für einen echten Bestand unmöglich, meist Import-Altlasten aus einer nicht
modellierten Kapitalmaßnahme — je Depot gelistet mit der Gesamtmenge des
Wertpapiers über alle Depots und verlinkt auf die Transaktionen des
Wertpapiers, damit sich die Historie reparieren lässt (nichts wird
automatisch repariert; der Split-Assistent bleibt die einzige geführte
Reparatur), sowie Buchungen mit unplausiblen Daten (vor 1970), die
stattdessen am ersten plausiblen Tag angewendet wurden. Positionen mit
negativer Menge sind zusätzlich überall dort mit einem Chip „negative
Menge" markiert, wo sie auftauchen: in der Allokationstabelle, im
Klassifikationsbaum und im Bestände-Tab des Wertpapiers.

## Performance (TTWROR)

Portfolixir meldet die **echte zeitgewichtete Rendite** so, wie es Portfolio
Performance tut: das Portfolio wird ab der ersten Transaktion jeden Tag bewertet,
ein- oder ausgezahltes Geld (Einzahlungen, Entnahmen, Lieferungen und
Saldo-Snapshot-Sprünge), wird neutralisiert, und die täglichen Renditen werden
verkettet. Das Ergebnis misst, wie gut die **Investitionen** abgeschnitten haben,
unabhängig davon, wann Geld bewegt wurde — Dividenden, Zinsen, Gebühren und
Steuern zählen als Teil der Rendite.

**Positionen ohne Kurshistorie** werden mit ihrem eigenen letzten Handelspreis
bewertet (derselbe Rückfall, den die Datenqualitäts-Karte auflistet). Eine
solche Position liegt zwischen zwei Trades flach, und an dem Tag, an dem ein
neuer Trade einen anderen Preis setzt, würde die gesamte bereits gehaltene
Stückzahl in einem Schritt neu bewertet. Dieser Schritt ist ein Wechsel der
Bewertungsbasis, keine Marktbewegung, und wird deshalb genauso neutralisiert
wie eine Einzahlung — sonst verketten sich diese Sprünge zu einem Prozentsatz,
den kein Markt je hergegeben hat. Was weiter zählt: der **Verkauf**. Ein Verkauf
macht die Position zu echtem Geld, deshalb bleibt sein Gewinn gegenüber dem
Preis, zu dem die Position geführt wurde, in der Rendite und wird nie
verschluckt. Alles andere, was der Tag neu bewertet — die weiter gehaltene, die
gekaufte, die ausgelieferte Stückzahl — ist Basis. Das gilt für eine Position
**ganz ohne Kurs**. Sobald ein Kurs vorliegt, ist die Position gemessen: spätere
Lücken in der Kursreihe sind nur Lücken, und die Trades darin zählen wieder als
Rendite. Der **erste** Kurs zu einer bis dahin kurslosen Position ist selbst ein
Basis-Schritt und kein Tagessprung — sonst meldete eine Kurshistorie, die nur
die jüngste Zeit abdeckt, den über Jahre aufgelaufenen Versatz als Rendite eines
einzigen Tages. Wert, Netto-Zahlungsströme und
der €-Gewinn neben dem Prozentwert bleiben unberührt — sie melden das Geld
weiterhin so, wie es gebucht wurde. Ein rein handelspreisbewertetes Portfolio
kann daher einen deutlichen €-Gewinn neben einer TTWROR nahe null zeigen.

Daneben zeigt Portfolixir die **geldgewichtete Rendite (IRR)** — die einzelne
annualisierte Rate, die die datierten Einzahlungen, Auszahlungen und den Endwert
des Zeitraums auf null abzinst, die Zahl, die Portfolio Performance neben TTWROR
zeigt. Wo TTWROR das Timing der Geldflüsse ignoriert, spiegelt der IRR es wider,
sodass die beiden unterschiedlich ausfallen, wenn Geld zu guten oder schlechten
Zeitpunkten bewegt wurde. Der IRR zeigt `—`, wenn es keine Rate zu berechnen gibt
(keine Flüsse beider Vorzeichen oder der Solver konvergiert nicht).

Weil eine Max-Zeitraum-TTWROR in den Tausenden *kein* Vermögens-Multiplikator
ist (sie sagt, was aus einer Einheit vom ersten Tag geworden wäre, nicht, was
das tatsächliche Geld getan hat), trägt dieselbe Auswertung auch die
geldgewichteten Begleiter
([ADR-0034](/decisions/0034-money-weighted-metrics.html)): das **eingesetzte
Kapital** (Wert zum Periodenbeginn plus externe Nettoflüsse), den
**Vermögens-Multiplikator** (Endwert ÷ eingesetztes Kapital; `n/a` bei
eingesetztem Kapital von null oder darunter — nie ein negativer
Multiplikator) und die **Perioden-MWR**, die nicht annualisierte Form des
IRR, die kurze Fenster anzeigen. Genau vier Buchungsarten zählen als externe
Flüsse — Einzahlung, Entnahme, Ein- und Auslieferung (zum vollen
Transaktionswert) — plus der Sprung einer Saldo-Anpassung; alles andere
(Dividenden, Zinsen, Gebühren, Steuern, Käufe/Verkäufe, interne
Überträge) ist Performance, kein Fluss. Fremdwährungsflüsse werden zum
gespeicherten Kurs des Flussdatums über den EUR-Hub umgerechnet; das
Ergebnis ist die Rendite des EUR-Anlegers inklusive Währungseffekt. Die
API-Antwort und beide Performance-MCP-Tools liefern `invested_capital`,
`wealth_multiple` und `mwr` als Decimal-Strings neben `ttwror` und `irr`.

Die Performance wird auf der Vermögensseite gezeigt und ist je Zeitraum
verfügbar — laufendes Jahr, ein, drei oder fünf Jahre, seit der ersten
Transaktion, ein einzelnes Kalenderjahr (`year=YYYY`) oder ein eigener
`from`/`to`-Datumsbereich — über die API
(`GET /api/v1/portfolios/:id/performance`) und das
MCP-Tool `portfolixir.portfolios.performance`, optional mit der vollständigen
täglichen Bewertungsreihe zum Charting. Die Methode und ihre Abwägungen sind in
[ADR-0010](/decisions/0010-ttwror-performance-series.html) festgehalten.

### Während eine Kurve neu berechnet wird

Die tägliche Performance-Kurve wird zwischen Seitenaufrufen gemerkt und bei
Datenänderungen (Buchung, Kurs, Wechselkurs) neu berechnet. Während die
Neuberechnung läuft, zeigt die Seite die **zuletzt berechnete Kurve** statt
einer Ladeanzeige — immer beschriftet mit dem, was sie enthält: wie viele
Buchungen, bis zu welchem Datum, wann berechnet, mit welchem Stand. Die
Beschriftung ist der Vertrag: eine überholte Zahl erscheint nie ohne sie, der
Wechsel zur frischen Kurve passiert in einem Schritt, und schlägt die
Neuberechnung fehl, wird die Beschriftung zum Fehler statt die alte Zahl stehen
zu lassen. Die Vermögens-Kachel der Übersicht zeigt ihre zuletzt bekannte
YTD-Zahl auf dieselbe Weise. (ADR-0032.)

## Income (Dividenden und Zinsen)

Die **Income**-Seite ist der retrospektive Ertragsbericht: die bereits im
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

## Snapshots (was wäre, wenn ich es behalten hätte?)

Der Reiter **Snapshots** im Vermögensbereich friert „die Bestände, die ich
gerade habe" als benannten Marker ein und beantwortet später: **wäre ich besser
gefahren, wenn ich genau diese Bestände behalten hätte?** Lege einen Snapshot
an, bevor eine Strategie umgebaut wird, handle weiter, und komm zum Vergleich
zurück.

Ein Snapshot ist ein reiner **Ledger-Marker** — ein Name, ein Geltungsbereich
(eine Bucket-Sicht oder *Alles*) und ein Stichtag. Er kopiert **keine**
Transaktionen, Stückzahlen oder Kurse: der Zustand, den er repräsentiert, wird
bei Bedarf aus dem Transaktions-Ledger abgeleitet. Ein Snapshot kann also nie
von den Daten abweichen, und ihn zu löschen berührt nie eine Transaktion.
Namen sind je Geltungsbereich eindeutig; der Stichtag darf nicht in der
Zukunft liegen.

**Vergleichen** zeigt das Kontrafaktual:

- **Eingefrorener Wert damals / heute** — die Positionen des Snapshots zum
  Stichtag und heute bewertet, buy-and-hold über die echte gespeicherte
  Kurshistorie (tägliche Schlusskurse, EUR-Hub-Wechselkurse des jeweiligen
  Tags).
- **Snapshot-Rendite (Kurs)** gegen **Echte TTWROR seitdem** — die
  Kursrendite des eingefrorenen Bestands gegen die echte zeitgewichtete
  Performance seit dem Stichtag. TTWROR neutralisiert Ein- und Auszahlungen,
  frisches Geld verzerrt den Vergleich also nicht.
- Ein Chart mit beiden Serien, **indexiert auf 100 %** am Stichtag
  (durchgezogen = Snapshot, gestrichelt = echt), und dieselben Daten als
  Tabelle.

Der Vergleich ist in v1 **brutto und nur Kursentwicklung** — Ausschüttungen,
die die eingefrorenen Positionen gezahlt hätten, sind noch nicht enthalten;
die Seite sagt das auch. Wertpapiere ohne verwendbaren Kurs oder Wechselkurs
zum Stichtag werden **ausgeschlossen und aufgeführt**, statt still mit null
bewertet zu werden. Derselbe Vergleich steht über die
[API und MCP](../integration/api-and-mcp.html) bereit.

## Steuern (erfasste Bankabrechnungen)

Der Reiter **Steuern** im Vermögens-Bereich erfasst den Steuerblock einer
Bankabrechnung — den Abschnitt `Verlustverrechnungstöpfe` /
`Freistellungsauftrag` eines Steuerreports oder einer Erträgnisaufstellung —
und liest daraus den **steuerfreien Verkaufsspielraum** ab: wie viel
realisierter Aktiengewinn bei diesem Institut noch frei von
Kapitalertragsteuer ist.

**Diese Zahlen werden erfasst, nicht berechnet.** Portfolixir kann die
deutschen Steuertöpfe nicht aus dem Buchungsbestand herleiten und versucht es
auch nicht — aber nicht aus dem Grund, den man zuerst vermutet. Portfolixir
rechnet sehr wohl **FIFO**, also nach der Methode, die das deutsche Steuerrecht
vorschreibt: die [Trade-Liste](integration/api-and-mcp.html) weist aus, welche
Stücke ein Verkauf verbraucht hat und zu welchen Kosten. (Die Bestandsbewertung
nutzt daneben einen laufenden Durchschnitt, weil „was hat meine Position im
Schnitt gekostet" eine andere Frage ist; ADR-0004/ADR-0011.)

Was FIFO liefert, ist ein **Rohgewinn** — und ein Rohgewinn ist kein Steuertopf.
Dazwischen stehen vier Dinge, von denen keines in den Transaktionsdaten steht:
Teilfreistellung (die anteilige Befreiung je Fondstyp), Vorabpauschale, die
chronologische Verrechnung des Freistellungsauftrags über *alle* Erträge bei
dieser Bank, und der bescheinigte Verlustvortrag aus Jahren vor der ersten
erfassten Buchung. Hinzu kommt: die Töpfe führt die Bank je **Institut**,
Portfolixir modelliert Depots. Ein berechneter Topf wäre deshalb falsch, und
zwar unsichtbar falsch — deshalb wird die Abrechnung übernommen. **Maßgeblich
bleibt die Abrechnung; dies ist keine Steuerberatung.**

Erfasst werden je Institut, steuerpflichtiger Person, Steuerjahr und Stichtag:
die steuerpflichtigen Kapitalerträge, der erteilte und der verbrauchte
Freistellungsauftrag, die Verlustverrechnungstöpfe Aktien und Sonstige, der
bescheinigte Verlustvortrag, der Quellensteuertopf und die angerechnete
ausländische Quellensteuer sowie die abgeführte Kapitalertragsteuer, der
Solidaritätszuschlag und die Kirchensteuer.

**Alle Beträge ohne Vorzeichen eintragen.** Ein Verlusttopf wird als
*verrechenbares Verlustvolumen* gespeichert, nicht als die negative Zahl auf
dem Papier. Eine negative Eingabe wird mit einem entsprechenden Hinweis
abgelehnt statt still gedreht — stilles Umdrehen eines Vorzeichens macht aus
einem Übertragungsfehler eine dauerhaft falsche Zahl. Die Übersicht stellt die
Töpfe anschließend mit dem gedruckten Vorzeichen dar, damit eine erfasste Zeile
mit dem Papier vergleichbar bleibt.

**Der Verkaufsspielraum** ist der Verlusttopf Aktien plus der verbleibende
Freistellungsauftrag (`erteilt − verbraucht`). Er wird immer **mit seinem
Stichtag** gezeigt und als **veraltet** markiert, sobald ein späterer Tag
existiert: Dividenden und Zinsen verbrauchen den Freistellungsauftrag
chronologisch, die Zahl altert also ohne jedes Zutun. Über mehrere Institute
wird je Person und Jahr summiert — mit Angabe der erfassten Institute, dem
Stichtag der **ältesten** Teilzahl und dem Hinweis **unvollständig**, wenn für
ein Institut ein Freistellungsauftrag hinterlegt, aber keine Abrechnung erfasst
ist. Die Zahl ist eine **Entscheidungsgrundlage, keine Handlungsanweisung**:
Portfolixir erteilt, speichert und überträgt keine Orders.

**Selbstprüfende Übernahme.** Die Abgeltungsteuer folgt der geschlossenen
Formel des § 32d Abs. 1 EStG, eine erfasste Abrechnung kann ihre eigene
Arithmetik also prüfen. Zwei Widersprüche **verhindern das Speichern**: ein
verbrauchter Freistellungsauftrag über dem erteilten, und Kirchensteuer bei
einem Kirchensteuersatz von null. Alles andere ist ein **Hinweis**, der nichts
blockiert — die aus der Abrechnung rekonstruierte Kapitalertragsteuer, der
Solidaritätszuschlag und die Kirchensteuer, sinkende Jahreswerte zwischen zwei
Abrechnungen desselben Jahres, ein erfasster Freistellungsauftrag, der vom
hinterlegten abweicht, und hinterlegte Aufträge über dem gesetzlichen
Höchstbetrag des Jahres. Ein Hinweis nennt beide Zahlen und die Abweichung; er
schlägt nie einen „korrigierten" Wert vor. Eine Toleranz von
`max(1,00, 0,05 %)` fängt die Cent-Beträge ab, die sich aus der Rundung je
Abrechnungsvorgang legitim ansammeln.

**Die Konfiguration dahinter.** Die gesetzlichen Sätze und die
Sparer-Pauschbeträge sind **jahresbezogene Daten**, für 2009–2026 hinterlegt —
der Pauschbetrag stieg 2023 von 801/1.602 € auf 1.000/2.000 €, eine ältere
Abrechnung wird also gegen das Recht geprüft, das für sie galt. Ein Jahr ohne
Daten wird als fehlend gemeldet und nicht aus einem Nachbarjahr geschätzt. Die
eigene Situation ist ein **zeitlich gültiges Profil** je Person:
Kirchensteuerpflicht (Voreinstellung: nicht pflichtig) sowie Einzel- oder
Zusammenveranlagung. Eine erfasste Abrechnung friert den zum Stichtag geltenden
Kirchensteuersatz ein, ein späteres Ändern des Profils wirkt also nur nach vorn
und schreibt nie eine erfasste Abrechnung um.

Alles auf dieser Seite ist auch über
[API und MCP](integration/api-and-mcp.html) verfügbar.

## Imports

Die Imports-Seite akzeptiert Portfolio-Performance-Transaktionsexporte im Format
CSV oder JSON v1. Dateien werden in eine Vorschau geparst, bevor Datensätze
gespeichert werden. Die Vorschau zeigt übersetzte Transaktionsart-Labels, die
Datensätze, die angelegt würden, und Konto-/Depotzuordnungen für fehlende Ziele.

Statt nach einem Zielportfolio zu fragen, bietet die Vorschau einen editierbaren
**Bucket-Tag** für die Konten an, die der Import anlegen wird — vorbelegt mit
einem datumsgestempelten Standard wie `PP Import 2026-07-12`. Benenne ihn um,
gib den Namen eines bestehenden Buckets ein, um ihn wiederzuverwenden, oder
wähle *kein Tag*, um die neuen Konten ohne Bucket zu lassen (ein leeres Feld
verhält sich genauso). Konten, die bestehenden Einträgen zugeordnet sind,
behalten ihre aktuellen Tags, und ein Import, der keine neuen Konten anlegt,
erzeugt keinen Bucket. Die interne Portfolio-Bindung geschieht automatisch und
erfordert nie eine Auswahl (siehe den Abschnitt Portfolios).

Parser-Warnungen erscheinen in einem scrollbaren Feld mit Kopier-Button. Der
kopierte Text nutzt stabile `Row N: message`-Zeilen, sodass die Diagnose beim
Quell-Export verbleiben kann. Das Anwenden des Imports ist atomar und nutzt
Inhalts-Hashes, um Duplikate bei erneutem Lauf zu überspringen.

### Wertpapier-Matching und der Zuordnungsschritt

Wertpapiere in der Datei werden über eine deterministische **Leiter stabiler
Identitäten** (ADR-0029) gegen die bestehenden Einträge aufgelöst: zuerst
ISIN — aktuelle ISINs, dann erfasste Alt-ISIN-Aliase —, dann WKN, dann
Ticker+Währung, dann Name+Währung. Jede Stufe greift nur, wenn der
Identifikator auf beiden Seiten vorhanden ist und genau einen Kandidaten
auswählt. Das Matching verändert die Stammdaten des getroffenen Wertpapiers
nie: eine Umbenennung im Export ändert implizit nichts.

Das Vorschau-Panel **Wertpapiere aus dem Export** zeigt das Ergebnis:

- **Treffer** werden als aufklappbare Liste zusammengefasst, jeder mit der
  Stufe beschriftet, die ihn getroffen hat (zum Beispiel *über frühere ISIN
  zugeordnet* nach einem erfassten ISIN-Wechsel).
- **Einfache neue Wertpapiere** bleiben als Zusammenfassung eingeklappt;
  die Liste aufklappen, um einzelne stattdessen auf ein bestehendes
  Wertpapier umzumappen.
- **Entscheidungen** werden prominent angezeigt und blockieren den Import,
  bis sie aufgelöst sind: ein mehrdeutiger Identifikator (zwei Wertpapiere
  teilen eine WKN oder Name+Währung) oder ein Kandidat, der einem stärkeren
  Identifikator widerspricht — die typische Form eines noch nicht erfassten
  ISIN-Wechsels. Der Import wählt in diesen Fällen nie stillschweigend aus.
- **Konfigurations-Warnungen**: Wenn ein anzulegendes Wertpapier einem
  bestehenden ähnelt, das Kategorie-Zuordnungen oder Positionsziele trägt,
  verlangt die Zeile eine eigene ausdrückliche Bestätigung — ein Duplikat
  würde diese Konfiguration auf einer bestandslosen Zeile stranden lassen.

Wird ein Eintrag ummappt, dessen ISIN von der aktuellen ISIN des
gewählten Wertpapiers abweicht, bietet die Vorschau an, die Differenz im
selben Schritt **als ISIN-Wechsel zu erfassen**, sodass die Entscheidung für
künftige Importe erhalten bleibt statt jedes Mal wiederholt zu werden.

Ein zweites Panel listet jedes **konfigurierte Wertpapier, das der Import
nicht berührt**: Wertpapiere mit Zuordnungen oder Positionszielen, die zu
keinem Eintrag der Datei passen — vermutlich eine Umbenennung oder ein
ISIN-Wechsel in Portfolio Performance. Abhilfe: den ISIN-Wechsel am
Wertpapier erfassen (oder, ohne ISIN, das Wertpapier in der App passend
umbenennen bzw. in der Vorschau neu zuordnen), dann den Import erneut
starten.

Zwei weitere Sicherungen greifen beim Anwenden: Das Matching wird **in der
Import-Transaktion erneut geprüft**, und das Anwenden bricht zur Vorschau
ab, wenn sich etwas anders auflöst als im bestätigten Stand (Vorschauen können
länger offen stehen); und Zeilen, die sich zur **selben Buchung auf
demselben Wertpapier** auflösen — ein Export, der ein Papier unter alter
und neuer ISIN führt — werden zu einer Transaktion zusammengefasst und
ausgewiesen, nie doppelt importiert.

**Ein-/Auslieferungszeilen** behalten ihren geparsten Stückpreis (die
CSV-Spalte `Kurs`), sodass eine Einlieferung mit Preis mit ihrem echten
Einstand in den Einstandswert der Bestände eingeht. Eine Lieferzeile ohne
Preis wird weiterhin importiert und bewegt die Menge zum Einstand null, wie
unter Bestandsberechnung beschrieben.

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

Von Hand eingetragene Kurse gewinnen gegen synchronisierte: Die
Synchronisierung überschreibt nie eine gespeicherte Zeile mit der Quelle
`manual`, auch wenn die Anbieter-Historie dasselbe Datum abdeckt. Jede
Synchronisierung meldet, wie viele manuelle Zeilen sie unangetastet gelassen
hat, und protokolliert eine Warnung, wenn diese Zahl größer als null ist.
Wer einen Kurs von Hand bearbeitet, überschreibt weiterhin den gespeicherten
Wert — auch zuvor synchronisierte.

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
  überlagert — formcodierte Dreiecke (▲ Kauf, ▼ Verkauf), die Richtung ist
  also ohne Farbe erkennbar.
- Einem Button *Sync prices for this security*.

**Aktiensplits und die Kursbasis (ADR-0028).** Nach dem Buchen eines Splits
zeigen Chart und Kurse-Tab eine **split-bereinigte** Serie, die zur Lesezeit
abgeleitet wird: manuell erfasste (rohe, wie gehandelte) Schlusskurse vor dem
Wirksamkeitsdatum werden durch das kumulierte Verhältnis aller späteren
Splits geteilt, während anbieter-synchronisierte Zeilen — vom Anbieter
bereits rückwirkend angepasst — unverändert durchlaufen; nichts wird doppelt
angepasst. Die wirksame Basis („split-bereinigt“, „anbieterbereinigt“ oder
gemischt) steht unter dem Chart und auf dem Kurse-Tab, dessen Tabelle eine
Spalte *Gespeichert* mit den unveränderten Werten behält — gespeicherte
Kurshistorie wird nie verändert, und das Löschen eines versehentlich
gebuchten Splits stellt jeden Chart und jede Kennzahl exakt wieder her.
Bestände, Bewertungen, Performance-Serien, Snapshot-Vergleiche und die
Kennzahlen der Wertpapierliste preisen über dieselbe basisbewusste Engine,
sodass ein alter Vor-Split-Kurs (oder der Rückgriff auf den letzten eigenen
Handelspreis) eine Nach-Split-Position nie zum unbereinigten Preis bewertet.
Für Anbieter, die ihre Historie nie rückwirkend anpassen, bietet der
Overview-Tab des Wertpapiers den Schalter **Synchronisierte Kurse als roh
behandeln**, der die Roh-Basis für dessen synchronisierte Zeilen erzwingt.

**Einen Split erfassen.** Der Button **Split erfassen** in der Detailansicht
öffnet einen geführten Assistenten: Verhältnis als neu:alt eingeben (2:1
verdoppelt die Stückzahl, 1:10 ist ein Reverse Split) und den Stichtag
wählen — der Dialog zeigt die Wirkung live als Vorschau: Stückzahl vor und
nach dem Stichtag plus die resultierende aktuelle Position, eine Zeile je
betroffenem Portfolio — zusammen mit jeder Warnung, bevor irgendetwas
geschrieben wird: ein Stichtag vor der importierten Historie (die
Stückzahlen können bereits nach-Split sein) und die Kursbasis-Prüfung der
gespeicherten Schlusskurse rund um den Stichtag (Widerspruch oder zu wenige
Kurse zur Prüfung). Das Bestätigen bucht dasselbe erstklassige
Split-Ledger-Ereignis, das auch API und MCP-Werkzeuge anlegen — eine
journalisierte Transaktion je positioniertem Portfolio, atomar — und Chart,
Bestände und Transaktionen aktualisieren sich sofort. Ungültige Eingaben
(ein 1:1-Verhältnis, ein Datum in der Zukunft, keine gehaltene Position oder
ein zweiter Split am selben Tag, der unter Nennung des bereits gebuchten
Ereignisses abgelehnt wird) bleiben inline im Dialog.

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
  Wertpapiere, die nicht mehr gehalten werden (aktuelle Menge null), sodass alte oder
  vollständig verkaufte Zuordnungen den Baum nicht überladen. Nichts wird still
  verworfen: jede Kategorie zeigt einen Zähler **+N without holdings** für die
  verborgenen Wertpapiere, und das Ausschalten des Schalters zeigt sie wieder.
- Jede Kategoriezeile aggregiert den **Wert** und die **Positionsanzahl** der
  aktuell in ihr und ihren Unterkategorien sichtbaren Wertpapiere, sodass die
  Summen dem Schalter folgen.
- Die Seitenleiste ist in aufgabenorientierte Bereiche organisiert (ADR-0022):
  **Übersicht**, **Vermögen**, **Wertpapiere** und **Transaktionen** auf der
  obersten Ebene, plus eine Gruppe **Verwaltung** mit **Konten & Depots**,
  **Ansichten** und **Klassifizierungen**. Sie listet nur existierende
  Routen — keine deaktivierten Roadmap-Platzhalter. Erträge sind ein Tab des
  Vermögens-Bereichs und der Import ein Tab des Transaktions-Bereichs, keine
  eigenen Menüeinträge. Buckets haben keinen eigenen Seitenleisten-Eintrag
  (ADR-0024): sie werden als Chips auf den Zeilen von Konten & Depots und auf
  der Ansichten-Seite verwaltet, die der **Verwalten…**-Link des
  Sicht-Umschalters öffnet.
- Theme: System-, hell- und dunkel-Modus werden unterstützt.
- Akzent: violette, türkise und korallenfarbene Logo-Akzentwahlen werden
  unterstützt.
- Sprache: der erste Aufruf folgt der Browsersprache, wenn sie Englisch oder
  Deutsch ist. Explizite EN/DE-Links überschreiben die Browsersprache und sichern
  diese Wahl.
- Theme, Akzent und Sprache sind Nutzerpräferenzen und beeinflussen gespeicherte
  Finanzwerte nicht.
- Datumsfelder nehmen ISO-Daten (`YYYY-MM-DD`) entgegen und zeigen sie auch so
  an — dasselbe Format wie jedes angezeigte Datum; der lokalisierte
  Browser-Datumswähler kommt nicht zum Einsatz.
- Während Werte berechnet werden, zeigt der betroffene Platz einen
  Platzhalter plus den Hinweis „wird berechnet" statt eines Ladetexts;
  Kopfzahlen zählen kurz sichtbar hoch. Bei reduzierter Bewegung als
  Systemeinstellung entfällt alle dekorative Bewegung und Endwerte erscheinen
  sofort.
- Vorzeichenbehaftete Kennzahlen (TTWROR, IRR/MWR, Nettoflüsse, das
  Veränderungssignal der Übersicht) tragen ein explizites Vorzeichen und
  Gewinn-/Verlustfarbe auf jeder Ebene; vorzeichenlose Beträge behalten die
  Akzentfarbe.

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
