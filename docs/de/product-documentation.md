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

Eine Suche oder Filterkombination ohne Treffer zeigt einen
*Keine-Treffer*-Zustand, der die Suche bzw. die aktiven Filter benennt — die
Bedienelemente bleiben sichtbar; der Onboarding-Hinweis „noch keine
Wertpapiere" erscheint nur bei leerer Datenbank.

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

### Verlinkbare Filter

Der Filterzustand der Wertpapierliste liegt in der URL; jede gefilterte
Ansicht lässt sich als Lesezeichen speichern oder verlinken:

- `?q=…` — der Suchbegriff.
- `?holding=held|not_held` — der Bestandsstatus (die Chips *Im Bestand* /
  *Ohne Bestand*).
- `?filter[]=spalte:operator[:wert]` — ein oder mehrere Spaltenfilter, z. B.
  `?filter[]=asset_class:is_nil` (unklassifizierte Wertpapiere) oder
  `?filter[]=currency_code:eq:USD`. Die Operatoren entsprechen dem
  Filter-Popover; unbekannte Spalten oder Operatoren werden verworfen.
- `?cur[]=EUR&cur[]=USD` — die Währungs-Chips; mehrere kombinieren als
  Entweder-oder.
- `?class[]=etf` — die Anlageklassen-Chips, geschlüsselt auf die
  **effektive** Klasse (gespeichert oder abgeleitet), sie wählen also, was
  die Liste anzeigt.
- `?since=<ISO8601>` — der **Geändert-seit**-Schnitt (siehe unten); die Chips
  *Heute / 7 Tage / 30 Tage* schreiben hier ein konkretes ISO-Datum, sodass
  der Link bedeutet, was er beim Teilen bedeutete.
- `?dq=stale_quote|missing_quote|missing_logo|missing_fx` — die
  Datenqualitäts-Schnellfilter: kein Kurs in den letzten 7 Tagen (inklusive
  „gar kein Kurs"; stillgelegte Wertpapiere ausgenommen, ihr versiegter Kurs
  ist erwartet), gar kein Kurs, kein hinterlegtes Logo, und — Issue #717 —
  *Kein Wechselkurs*: bepreist, aber ohne gespeicherten Kurs von seiner
  Währung zur Basiswährung; das Speichern des Kurses leert die Menge.
  Dieselben Bedingungen sind im Filter-Bedienelement unter **Datenqualität**
  direkt wählbar — der Link von der Übersicht ist eine Abkürzung dorthin,
  nicht der einzige Weg. Der Agent fragt genau dieselben Mengen über
  `GET /api/v1/securities?data_quality=…` und das Werkzeug
  `portfolixir.securities.list` ab; alle beruhen auf einer Definition, sodass
  eine Zahl N immer eine Liste von N adressiert.

**Die häufigen Filter sind One-Tap-Chips** (Issue #717): eine feste, benannte
Zeile über der Tabelle — *Im Bestand · Ohne Bestand · Ohne Anlageklasse ·
Kurs veraltet · Kein Kurs · Kein Wechselkurs*, dazu je ein Chip pro genutzter
Währung und Anlageklasse. Chips sind Schalter; verschiedene Familien
kombinieren als UND, mehrere Chips der Währungs- oder Klassenfamilie als
Entweder-oder. Zwei davon tragen eine bewusste Unterscheidung: **Ohne
Anlageklasse** ist auf die *gespeicherte* Klasse geschlüsselt (eine nur
abgeleitete Klasse zählt weiter als unklassifiziert, denn eine Ableitung ist
eine Vermutung, kein festgehaltener Fakt), während die
**Anlageklassen-Chips** auf die *effektive* Klasse geschlüsselt sind — sie
wählen genau, was die Liste anzeigt. Der generische
Spalte/Operator/Wert-Baukasten ist hinter **Weitere Filter** am Ende der
Zeile zurückgestuft; er kann weiterhin alles ausdrücken, was er vorher
konnte, und trägt eine Anzahl, sobald er Bedingungen hält, die die Chips
nicht ausdrücken können — ein zurückgestuftes Bedienelement verbirgt nie
aktiven Zustand.

Suchen, einen Chip schalten oder Filter anwenden aktualisiert die URL;
die Auswahl eines Wertpapiers behält die aktiven Filter bei. Die
Datenqualitätszeile der Übersicht verlinkt mit vorangewendetem Filter
hierher.

**Geändert seit** (Issue #731) beantwortet „was hat sich zuletzt bewegt?"
aus demselben Schnitt, mit dem der Agent pollt: die Chips verengen die Liste
auf Wertpapiere, die strikt nach dem Schnitt angelegt oder geändert wurden —
nach dem Änderungszeitpunkt des Datensatzes. Die Seite nennt die Eigenschaft,
die so ein Delta ehrlich macht: **Löschungen werden nicht angezeigt**; Filter
entfernen für die vollständige Liste. Der URL-Parameter ist das `?since=` der
API mit denselben akzeptierten Formen, ein Agenten-Link öffnet also genau die
gelesene Scheibe; ein unlesbarer Wert degradiert zur ungefilterten Liste,
statt sie stillschweigend zu verengen.

**Auf dem Telefon** (Issue #799, UX-DR27; Issue #800): unter 560 px weicht
die Tabelle zweizeiligen Zeilen — der Name über Ticker, ISIN und
Anlageklasse (das Zuordnen-Steuerelement, wo die Klasse fehlt), rechts der
letzte Kurs über der Tagesänderung, die Veraltet-Markierung unter dem Kurs,
„kein Kurs", wo nichts die Zeile bepreist — sodass nichts seitwärts scrollt;
die Zeile öffnet weiterhin das Detail, ihr Kebab weiterhin das Zeilenmenü,
und die Spaltenauswahl behält oberhalb von 560 px ihre Bedeutung. Die
Chip-Familien wandern hinter ein **Filter (n)**-Steuerelement, das die Zahl
der aktiven Chips trägt und ein Bottom Sheet öffnet — einen Dialog mit den
Familien untereinander unter ihren Namen, dem Weitere-Filter-Builder,
**Zurücksetzen** und **Fertig**; ein Chip im Sheet wirkt sofort, genau wie
in der Zeile.

### Klassifikations-Spalten

Neben den Attribut- und Kursspalten bietet die Spaltenauswahl der
Wertpapierliste einen Eintrag pro Klassifikationsbaum **und Ebene** — für
eigene Bäume ebenso wie für die eingebauten Anlageklassen- und
Währungsbäume, analog zu den Klassifikations-Spalten von Portfolio
Performance. Eine aktivierte Spalte zeigt je Wertpapier die zugeordnete
Kategorie auf dieser Ebene: Ein tiefer einsortiertes Wertpapier zeigt seinen
Vorfahren auf der gewählten Ebene, ein oberhalb der Ebene (oder gar nicht)
einsortiertes bleibt leer. Klassifikations-Spalten sortieren wie jede andere
Spalte — nicht einsortierte Wertpapiere stets zuletzt — und werden zusammen
mit der übrigen Spaltenauswahl im Browser gespeichert. Es sind reine
Anzeige-Spalten; Filter bleiben auf den Attributspalten.

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

### Identitätsfelder, die einfrieren (ADR-0050 §11)

Die **Währung eines Wertpapiers friert ein, sobald es eine Transaktion oder
einen Kurs hat**: Buchungen und Kurshistorie sind in dieser Währung
angegeben, eine Änderung würde sie stillschweigend umdenominieren. Jeder Weg
lehnt die Änderung mit einem Feldfehler ab, der zählt, was sie einfriert —
*is frozen once referenced (120 quotes, 3 transactions)* — und schreibt
nichts: das Bearbeiten-Formular (unter der Währungsauswahl), im Suchdialog
**Online-Felder übernehmen** und **Vorhandenes aktualisieren**, wenn das
gewählte Listing in einer anderen Währung handelt (ein Xetra-Listing in EUR
eines in USD gebuchten Wertpapiers ist eine andere Kursreihe, keine
Korrektur), sowie `PATCH /api/v1/securities/:id` mit dem MCP-Tool darüber
(`422`). Die übrigen Felder bleiben änderbar, und ein Wertpapier ohne
Buchungen und Kurse wechselt die Währung weiterhin. Dieselbe Regel gilt für
Konten, siehe *Konten und Depots* unten.

### Abgeleitete Kennzahlen im Chart-Tab (ADR-0047)

Der **Chart**-Tab des Detailbereichs trägt die abgeleiteten Kennzahlen des
Wertpapiers unter der Kurshistorie, die sie beschreiben: **SMA-50** und
**SMA-200** mit dem Abstand des letzten Schlusskurses zu beiden — als zweite
und dritte Serie im Chart gezeichnet, damit eine Kreuzung sichtbar ist —
sowie **Volatilität**, **maximaler Drawdown**, **Momentum** und der Abstand
zum **52-Wochen**-Hoch und -Tief.

Ein Zeitraum-Steuerelement: die Kennzahlen folgen den Bereichs-Buttons des
Charts. Die gespeicherten Fenster sind 30, 90 und 365 Tage; ein Bereich
rastet auf das nächstkleinere, und **jede Zelle nennt das verwendete Fenster**
samt **Beobachtungszahl**. Unterhalb ihres Minimums liest sich eine Kennzahl
als *nicht berechenbar* und zeigt trotzdem, wie viele Beobachtungen vorlagen.

Die Zahlen stehen über den **eigenen** splitbereinigten Schlusskursen in der
**eigenen** Währung, nie umgerechnet. Ein Tag ohne gespeicherten Schlusskurs
erzeugt keine Renditebeobachtung. **Der Block berichtet, er bewertet nicht** —
es gibt kein Signal, kein Rating und keine Empfehlung darin.

### Tab „Termine" (der Kalender des Wertpapiers, ADR-0048)

Der Tab **Termine** listet die datierten Kalenderfakten des Wertpapiers —
Geschäftszahlen, Ex-Dividenden- und Zahltag, Ende einer Haltefrist,
Indexüberprüfung, Hauptversammlung, Behördenentscheidung, Prognoseanpassung —
in der Form der Research-Zeitleiste. Jede Zeile sagt, wie gut das Datum
bekannt ist (*angekündigt*, *geschätzt*, *innerhalb eines Zeitraums*, *Monat
bekannt, Tag nicht*), woher es stammt (mit dem Quellenqualitäts-Vokabular des
Research-Logs), ob es *stattgefunden hat* und wann es zuletzt geprüft wurde.

Die letzten beiden sind verschiedene Aussagen, und die Beschriftungen halten
sie bewusst auseinander. *Angekündigt* heißt: eine Quelle hat diesen Tag
gesetzt. *Hat stattgefunden* heißt: das Ereignis ist tatsächlich eingetreten.
Ein Termin kann Monate im Voraus angekündigt sein und trotzdem noch
ausstehen, und ein nie angekündigter Termin kann genauso vergehen — deshalb
zeigt der Tab „Termine“ eine Zeile mit *Angekündigt* ohne Kennzeichen *Hat
stattgefunden*, und das ist kein Widerspruch.

Ein Termin **bucht nichts**: wird eine Dividende tatsächlich gezahlt, läuft
die Buchung wie immer über das Ledger und der Termin wird als stattgefunden
markiert.

Was im **gesamten Katalog** ansteht — gehaltene Wertpapiere und Kandidaten
gleichermaßen — erscheint als Karte **Fällig** auf der Übersicht, neben
*Abweichung vom Ziel* und der Datenqualität. Ein Wertpapier ohne Position
wird mit *ohne Bestand* markiert statt herausgefiltert.

### Tab „Research“ (das Research-Log des Wertpapiers)

Der Tab **Research** im Detailbereich ist die menschliche Sicht auf das
Research-Log des Wertpapiers (ADR-0044): was Betreiber oder Agent über ein
Wertpapier wissen, als datierte, belegte Einträge, die **nie geändert und nie
entfernt** werden. Oben steht der abgeleitete **Thesenstand** — Status
(*Keine*, *Intakt*, *Zurückgezogen*), der aktuelle Thesentext, die
Überzeugungsstufe, die Invalidierungsbedingung, der Zeitstopp, wann und von
wem zuletzt geprüft wurde und aus welchem Eintrag er abgeleitet ist —,
darunter die Zeitleiste **neueste zuerst**. Jeder Eintrag zeigt seine Art
(These, Beleg, Invalidierungsprüfung, Ereignisergebnis, Risiko, Widerruf,
Entscheidung), seine Quellenqualität (Primärquelle, mehrere Sekundärquellen,
Wahrnehmung, ungeprüft), sein Stichdatum und seinen Autor (Betreiber, Agent
oder lokales Modell; ein maschinell erzeugter Vorschlag ist als solcher
markiert).

Ein falscher Befund wird zurückgezogen, indem ein **Widerruf** angehängt
wird, der ihn ersetzt: Der Widerruf liest sich als „Widerruft #n“ mit der
Begründung, der ersetzte Eintrag bleibt in der Liste mit „Ersetzt durch #n“
markiert, und eine zurückgezogene These wird über der Zeitleiste mit dem
Grund des Widerrufs hervorgehoben. Nichts auf der Oberfläche ändert oder
löscht einen Eintrag — absichtlich, denn die Aufzeichnung des Irrtums ist der
Zweck des Logs.

Das Formular **Eintrag anhängen** schreibt einen Eintrag als Betreiber: Art
wählen, Quellenqualität angeben (sie wird gesetzt, nie geraten), das
Stichdatum eintragen (den Stand der Aussage, nicht das heutige Datum, wenn
beide auseinanderfallen) und optional den Quellenlink, ein „Gültig bis“ für
eine datierte Sperre und den Eintrag, den dieser ersetzt. Die Art *These*
blendet die Thesenfelder ein (Überzeugung, Invalidierungsbedingung,
Zeitstopp). Dasselbe Log ist über API und MCP lesbar und beschreibbar
(`/api/v1/securities/:id/notes` und die `portfolixir.notes.*`-Tools),
einschließlich der drei Hygiene-Reads — gehaltene Positionen ohne Eintrag
seit N Tagen, Einträge, die noch bestätigt werden müssen, und datierte
Sperren, die in N Tagen ablaufen.

**Benchmark-Wertpapiere.** Ein Wertpapier lässt sich aus seinem Zeilenmenü
als Benchmark markieren („Als Benchmark markieren“): eine Referenzreihe, mit
der das Portfolio verglichen wird — ein Index über einen ETF, Gold über einen
ETC —, gespeist aus der gewöhnlichen Kurssynchronisation, es gibt also keine
zweite Kursquelle. Eine Benchmark wird in keinem Buchungsformular angeboten,
und die Datenqualitäts-Hinweise des Katalogs (veralteter oder fehlender
Kurs, fehlendes Logo) lassen sie in Ruhe; sie kann trotzdem gehalten werden
und ist dann einfach beides. Die API listet Benchmarks mit
`is_benchmark=true`. Was der Vergleich zeigt, steht unter Performance.

## Konten und Depots

Die Buchhaltungs-Entitäten sind Geldkonten und Depots:

- Geldkonto: verfolgt den Kontext der verfügbaren Liquidität
- Depot/Konto: speichert Wertpapierpositionen, verknüpft mit diesem Geldkonto

Die Seite **Konten & Depots** (Bereich Verwaltung) zeigt beide in **einer
Tabelle, ein Eintrag je Zeile**: jedes Depot bildet eine Zeile, sein
verknüpftes Verrechnungskonto sitzt eingerückt direkt darunter — mit der
Kontowährung und dem **Liquiditätsrollen**-Selektor je Konto (freies Cash,
Kreditlinie, Reserve) — die Spaltenüberschrift beschriftet ihn einmal für die
ganze Tabelle, statt in jeder Zeile daneben zu stehen (Issue #806); ein Geldkonto ohne verknüpftes Depot
bekommt eine eigene Zeile. Ein von mehreren Depots geteiltes Konto trägt
seine Bedienelemente nur unter seinem ersten Depot — spätere Zeilen zeigen
*geteilt — oben verwaltet*.

**Bucket-Chips (#559).** Jede Zeile zeigt ihre Bucket-Zugehörigkeiten als
Chips — den exklusiven **Scope**-Bucket als gefüllten Chip, freie **Tags**
als Umriss-Chips, eingefärbt mit der Bucket-Farbe, wenn eine gesetzt ist.
Seit Issue #806 nennt jede Gruppe ihren **Geltungsbereich** als Unterzeile
unter den Chips — *Gilt für Depot und Verrechnungskonto*, *Gilt für das
Depot*, *Gilt für das Verrechnungskonto* —, sodass eine Zelle gelesen werden
kann, ohne sie anzufassen; eine leere Menge liest sich als *Kein Bucket*
statt als leere Zelle. **Getrennt taggen** ist aus der Zelle in das
**Kebab-Menü** der Zeile gewandert.
Tragen Depot und Verrechnungskonto dieselben Buckets, zeigt das Paar **eine
zusammengeführte Chip-Gruppe mit der Marke „Beide"** über beide Zeilen; der
Link **Getrennt taggen** daneben teilt die Gruppe, sodass jede Seite eigene
Tags bekommt (unterschiedliche Mengen erscheinen immer getrennt). Je Gruppe
sind höchstens vier Chips sichtbar — weitere klappen in ein Bedienelement
**+2 anzeigen**; ein Druck darauf klappt die Zelle an Ort und Stelle auf und
zeigt alle Buckets, **weniger** klappt sie wieder zu. Auch der Picker führt die
vollständige Menge. Lange Namen (etwa
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

**Währung und Bindung frieren ein, sobald verwiesen** (ADR-0050 §11). Die
Währung eines Geldkontos und seine interne Portfolio-Bindung frieren ein,
sobald eine Transaktion über eines ihrer beiden Konten auf das Konto
verweist oder ein Depot es verknüpft; die Bindung eines Depots friert ein,
sobald eine Transaktion darauf verweist. Eine Änderung wird mit einem
Feldfehler abgelehnt, der die Verweise zählt, und schreibt nichts —
gebuchte Historie wird nie umdenominiert oder verschoben. Name, Notizen und
Liquiditätsrolle bleiben änderbar. Die API verschiebt ein Konto oder Depot
ohnehin nie in ein anderes Portfolio.

**Namen und frühere Namen** (ADR-0050 §4). Zwei Verrechnungskonten teilen nie
einen Namen, und zwei Depots auch nicht: Ein Name, den ein anderes Konto der
Art als Namen oder als einen seiner früheren Namen trägt, wird beim Anlegen
und Umbenennen abgelehnt, weil ein Portfolio-Performance-Import, der ihn nennt,
schon auf jenes Konto bucht. Ein umbenanntes Konto behält seinen bisherigen
Namen als **früheren Namen**, sodass ein Export, der noch das alte Konto
nennt, auf das umbenannte bucht; die Rückbenennung auf einen früheren Namen
nimmt ihn zurück. Solange ein anderes Konto der Art den alten Namen noch als
Namen trägt, wird der alte Name nicht behalten, und ein Import, der ihn nennt,
bucht auf jenes andere Konto. Konten, die sich schon vor dieser Regel einen
Namen teilten, bleiben, wie sie sind; eines davon umzubenennen beendet die
Mehrdeutigkeit. Die früheren Namen stehen in den API- und MCP-Nutzlasten
(`former_names`) und lassen sich dort entfernen; ein Import, der einen
entfernten Namen noch nennt, legt dann ein neues Konto an. Die Bedienelemente
zum Umbenennen und Entfernen auf dieser Seite folgen mit dem Zeilenmenü der
Konten.

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

**Eine Buchung erfassen** (Issue #803; C6 des Reviews vom 2026-09-12,
Variante C): die Seite öffnet auf der Historie, und **Transaktion erfassen**
im Kopf der Historie öffnet eine seitliche Schublade in der Form des
Wertpapier-Detailbereichs — Art, Datum, das Depot, auf das die Buchung
**bucht** (sein Geldkonto setzt die Währung), Wertpapier, Stückzahl und
Preis, Kosten und Notiz hinter einer Aufklappung, darunter die
Lot-Vorschau — auf dem Telefon ein Bottom Sheet. Das Erfassen schließt die
Schublade und zeigt das Ergebnis über der Historie; Abbrechen oder Esc
verwirft den Entwurf und gibt den Fokus an das Steuerelement zurück.

**Eine Buchung korrigieren** (Issue #809): jede Zeile der Historie trägt ein
Kebab-Menü, und **Bearbeiten** darin öffnet dieselbe Schublade, vorbefüllt
mit der Buchung — dieselben Felder, dieselbe Prüfung, dieselbe Lot-Vorschau.
Das Speichern korrigiert die Zeile **an Ort und Stelle**: es entsteht keine
zweite Buchung, die abgeleiteten Bestände folgen, und die Änderung wird mit
den vorherigen Werten im Audit-Journal festgehalten. Das ist die menschliche
Sicht auf eine Fähigkeit, die API und MCP-Begleiter schon vor der
Zwei-Wege-Regel hatten; an beiden wurde nichts ergänzt.

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

### Die Historie lesen

Die Transaktionshistorie wird über **Chips** oberhalb der Tabelle gefiltert:
einer je Geldkonto und einer je Transaktionsart, die tatsächlich vorkommt.
Chips sind Schalter. Zwei Chips derselben Familie bedeuten „eines von beiden"
— zwei Konten zeigen die Buchungen beider Konten; je ein Chip aus zwei
Familien schränkt auf die Schnittmenge ein. Die selteneren Bedingungen —
Wertpapier, Zeitraum, Freitextsuche — liegen hinter **Weitere Filter**, das
eine Anzahl trägt, sobald dort eine Bedingung aktiv ist. So verbirgt ein
zurückgestuftes Bedienelement nie, was die Liste gerade filtert.

Die Einschränkung auf **genau ein Konto** blendet eine Spalte **Saldo** ein:
den Stand des Kontos nach jeder Buchung, in der Währung des Kontos. Zwei
Eigenschaften dieser Spalte sind wichtig:

- sie rechnet genauso wie der Kontosaldo selbst, die jüngste Zeile entspricht
  also dem Wert auf der Kontenseite;
- sie wird über die **gesamte** Historie des Kontos gebildet, nicht über die
  angezeigten Zeilen. Ein Datumsfilter ändert, welche Zeilen Sie sehen, nie
  den damaligen Saldo.

Eine Zeile, die das gewählte Konto nicht bewegt — eine Einlieferung, ein Split
— zeigt einen Gedankenstrich statt den Wert der Vorzeile zu wiederholen.

Die Zeilen sind nach Monaten gegliedert, und sowohl die Monatssummen als auch
die Zusammenfassung über der Tabelle nennen **eine Summe je Währung**. Die
Beträge sind die gebuchten Bruttobeträge; sie werden nie umgerechnet oder über
Währungen hinweg addiert — eine Umrechnung wäre eine andere Kennzahl und
bräuchte ihre eigene Kursbasis.

Neben den Konto- und Art-Chips sitzen die **Geändert-seit**-Chips (*Heute /
7 Tage / 30 Tage*, Issue #731): sie verengen die Historie auf Transaktionen,
die strikt nach dem Schnitt angelegt oder geändert wurden — **nach
Datensatzänderung, nicht nach Buchungsdatum**: eine bearbeitete alte Buchung
taucht auf, eine unberührte junge fällt heraus. Die Notiz unter den Chips
nennt den Schnitt und die Eigenschaft, die ein Delta ehrlich macht:
**Löschungen werden nicht angezeigt**. Der Schnitt liegt in der URL als
`?since=<ISO8601>` — Parameter, Formen und Semantik des API-Delta-Reads, ein
vom Agenten weitergegebener Link öffnet also genau die gelesene Scheibe; ein
unlesbarer Wert degradiert zur vollständigen Historie. Die Spalte **Saldo**
bleibt von diesem Filter wie von jedem anderen unberührt: sie wird immer über
die gesamte Historie des Kontos gebildet.

**Spalten** (Issue #732) öffnet die Spaltenwahl der Historie — die
menschliche Hälfte der schlanken `fields=`-Feldauswahl der API. Jenseits des
Standardsatzes (Datum, Art, Wertpapier, Menge, Kurs, Währung) bietet sie die
Felder an, die jede Buchung schon trägt, die die Tabelle aber nie zeigte:
Bruttobetrag, Gebühren, Steuern und Notizen. Die Wahl wird im Browser
gespeichert und übersteht ein Neuladen. Die Spalte **Saldo** steht bewusst
nicht in der Auswahl: sie folgt weiter ihrer eigenen Regel — sie erscheint
genau dann, wenn die Chips auf ein Konto verengen —, denn eine Auswahl, die
sie außerhalb dieser Verengung herbeiholen könnte, zeigte eine bedeutungslose
Zahl. Das frühere Panel **Aktuelle Bestände** hat diese Seite mit Issue #803
verlassen: es doppelte Vermögen → Bestände, und die Bewertungsfelder der
Bestände-Projektion bleiben über die schlanke `fields=`-Feldauswahl der
Bestände-API lesbar.

**Auf dem Telefon** (Issue #799, UX-DR27): unter 560 px weicht die Historie
zweizeiligen Zeilen unter denselben Monatsköpfen — Datum und Art über dem
Wertpapier oder Konto, das die Buchung berührt hat, rechts der Betrag mit
Vorzeichen und Währung über der Größe (Stückzahl × Kurs, die Stückzahl
allein, das Verhältnis eines Splits), darunter der laufende Saldo, solange
die Chips auf ein Konto eingrenzen — sodass nichts seitwärts scrollt; die
Spaltenauswahl behält oberhalb von 560 px ihre Bedeutung.

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

**Im Formular buchen** (Issue #395). Weicht die Währung des Wertpapiers von
der des Geldkontos am gewählten Depot ab, zeigt die Buchungsleiste einen Block
„Abrechnung in EUR“ (benannt nach der Kontowährung) mit zwei verbundenen
Feldern: dem Abrechnungsbetrag in Kontowährung und dem Kurs — Einheiten der
Kontowährung je einer Einheit der Wertpapierwährung. Wer eines einträgt, sieht
das andere abgeleitet, und das zuletzt eingetragene bleibt, wie es ist: Nach dem
Betrag aus der Abrechnung passt eine geänderte Stückzahl oder ein geänderter
Preis den Kurs an, nie den Betrag; eine Notiz, eine Gebühr oder ein Datum ändert
keines von beiden. Beide sind aus den gespeicherten Wechselkursen
am oder vor dem Buchungstag vorbelegt und sagen das — ein Vorschlag, die
Abrechnung des Brokers gilt; ohne gespeicherten Kurs sagt der Block auch das und
wartet auf den Betrag der Abrechnung. Der Preis wird in der Wertpapierwährung
eingegeben, Gebühren und Steuern in der Kontowährung. Gespeichert ist die
Buchung in der Wertpapierwährung, und ihr Geldbetrag wird aus Abrechnung,
Gebühren und Steuern berechnet — das Formular erzeugt also nie eine Buchung, die
die folgende Regel ablehnt. Ein Handel ohne Wert (eine Gratiszuteilung zum Preis
0) wird ohne Geldbetrag gebucht. Wird eine solche Buchung auf ein Wertpapier in
der Kontowährung geändert, entfallen ihre Abrechnungsangaben, und der Geldbetrag
folgt der neuen Stückzahl, dem Preis und den Gebühren. Vor Sprint 15 buchte das Formular einen solchen
Handel in der Kontowährung und las den Preis des Wertpapiers, als wäre er in
Euro.

**Geldbetrag und Abrechnung stimmen überein** (Issue #395). Ein
währungsübergreifender Kauf hält den bewegten Geldbetrag fest (`gross_amount`,
einschließlich Gebühren und Steuern) und daneben den Handelswert in der
Kontowährung (`settlement_amount`); ein Verkauf den zugeflossenen Betrag, nach
Gebühren und Steuern. Seit Sprint 15 wird eine Buchung abgelehnt, wenn beide um
mehr als einen Cent auseinanderliegen — beim Kauf muss der Geldbetrag die
Abrechnung plus Gebühren und Steuern sein, beim Verkauf die Abrechnung abzüglich
dieser — und die Meldung nennt den Betrag, den die Abrechnung ergibt. Die Prüfung
läuft beim Erfassen einer Buchung und bei einer Änderung, die einen dieser
Beträge oder die Art ändert; das Bearbeiten der Notiz oder des Datums einer
älteren Buchung wird deswegen nie abgelehnt. Ältere Buchungen, die die Regel
verfehlen, listet diese Abfrage auf — nur lesend, nichts wird geändert:

```bash
docker compose exec db psql -U portfolixir portfolixir_prod -c "
SELECT id, date, type, gross_amount, settlement_amount, fees, taxes
FROM transactions
WHERE type IN ('buy', 'sell')
  AND settlement_amount IS NOT NULL AND gross_amount IS NOT NULL
  AND abs(gross_amount - CASE type
        WHEN 'buy' THEN settlement_amount + coalesce(fees, 0) + coalesce(taxes, 0)
        ELSE settlement_amount - coalesce(fees, 0) - coalesce(taxes, 0)
      END) > 0.01
ORDER BY date, id;"
```

Eine aufgelistete Buchung zu korrigieren ist eine Entscheidung über die eigenen
Aufzeichnungen: ihre Beträge in der Transaktionshistorie oder über die API
bearbeiten.

## Klassifizierungen, Ziele und Allokation

Die **Klassifizierungs-Übersicht** (`/classifications`, Issue #808) ist eine
Zeile je Baum, und jede Zeile sagt, was dieser Baum enthält: wie viele
Kategorien und Ebenen er nutzt, wie viele Wertpapiere in ihm zugeordnet sind —
mit der Zahl der nicht zugeordneten daneben — und den Zielplan, den er trägt:
dessen Name steht unter dem Namen des Baums, dessen Status als kurzes Wort in
der rechten Spalte. Die Zeile selbst öffnet den Baum; das Kebab-Menü am Ende
trägt Öffnen und, bei eigenen Bäumen, Löschen; **+** in der Überschrift legt
einen neuen an. Gibt es gar keine Bäume, sagt die Übersicht das, statt eine
leere Liste zu zeigen.

Wertpapiere können in **Klassifizierungsbäume** geordnet werden. Eigene Bäume
sind frei gestaltbare Ordner mit Farben; integrierte Bäume für **Anlageklasse**
und **Währung** werden aus jedem Wertpapier abgeleitet und sind immer vorhanden.
Die Namen der integrierten Bäume werden über die Locale angezeigt (Issue #729 —
englisch *Asset class* / *Currency*), geschlüsselt auf den stabilen Key des
Baums; eigene Bäume behalten in jeder Sprache den Namen, den du ihnen gegeben
hast.
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

Ein Plan muss **nicht** 100 % ergeben. Ihn bewusst kürzer zu lassen — etwa weil
eine Satelliten-Kategorie absichtlich nicht voll genutzt wird — ist ein
legitimer Plan, und die Lücke wird als **nicht zugeteilter Rest** ausgewiesen:
ein benannter Teil des Plans mit der Bedeutung „dieser Anteil wird bewusst nicht
gesteuert“, kein Fehler. Die Abweichung wird dann gegen den tatsächlich
gesteuerten Anteil gemessen, damit der nicht zugeteilte Rest nicht als
Abweichung auf die Kategorien mit Ziel verteilt wird, mit der man nichts
anfangen kann. Eine Warnung bleibt den beiden Zuständen vorbehalten, die
wirklich falsch sind: einer Summe **über** 100 % und einem Konflikt zwischen
Positions- und Kategoriegewicht.

Jede Kategorie auf der Seite **Klassifikationen** weist außerdem aus, was sie
**gekostet** hat, was sie heute **wert** ist und was sie **erwirtschaftet** hat —
in Euro und in Prozent. Der Prozentwert ist geldgewichtet: die Summe der
Ergebnisse geteilt durch die Summe des investierten Kapitals, nie der Mittelwert
der Einzelprozente. Sonst würde eine winzige Position mit +300 % eine Kategorie
dominieren, die in Euro unverändert ist.

Die Basis steht einmal über dem Baum: Diese Zahlen umfassen **die heute in der
Kategorie eingeordneten Positionen**. Es ist eine Aussage über die aktuelle
Zusammensetzung, keine Periodenrendite — verschiebt man ein Wertpapier in eine
andere Kategorie, wandert sein gesamtes Ergebnis mit. Eine Position, deren
Ergebnis sich nicht ableiten lässt (kein brauchbarer Kurs oder kein Wechselkurs
zur Basiswährung), bleibt auf **beiden** Seiten der Summe außen vor und wird in
der Markierung „abgedeckt von gesamt" mitgezählt, statt als Null zu gelten, was
die Kategorie still kleinrechnen würde.

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
> Aufrollung. Seit Sprint 15 nimmt der Plan-Editor auf der Klassifizierungsseite
> auch Positionsziele entgegen (siehe „Positionsziele im Plan-Editor“ unten);
> eine gleichmäßige Auto-Verteilung ist nicht geplant.

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

**Positionsziele im Plan-Editor** (Issue #481, Sprint 15). Jede Kategorie mit
zugeordneten Wertpapieren bietet neben ihrem Namen **Positionen (n)** an; das
öffnet ihre Wertpapiere als Zeilen derselben Tabelle, jede mit eigenem
**Soll %**-Feld — dasselbe Formular, ein **Plan speichern**, eine Live-**Σ**.
Eine Kategorie öffnet sich von selbst, sobald eine ihrer Positionen ein Ziel
trägt. Trägt eine Position unter einer Kategorie ein Ziel, wird das Feld der
Kategorie zur gestrichelten, schreibgeschützten Anzeige **Σ Positionen**: Die
Kategorie *ist* die Summe ihrer Positionen (ADR-0030 §2), und die Σ-Fußzeile
zählt diese Summe an ihrer Stelle. Beim Speichern wird auch das eigene Gewicht
der Kategorie auf diese Summe gesetzt, sodass der Hinweis der Vermögensseite
„Positionsziele und Kategoriegewicht weichen ab“ durch das Speichern hier erledigt
ist. **Ein leeres Positionsfeld bedeutet „kein Positionsziel“** — nie null: Wer
das Feld einer gespeicherten Position leert und speichert, löscht dieses Ziel und
gibt die Steuerung an die Kategorie zurück; `0` ist ein Ziel von null und bleibt
erhalten. Das Zuklappen der Positionen einer Kategorie blendet die Zeilen nur
aus; ihre Werte werden weiter gespeichert.

Ein Speichern ist **eine Transaktion**: Ein abgelehntes Speichern — ein Ziel über
100 %, ein Wertpapier unter einer Kategorie, in der es nicht mehr liegt — ändert
nichts, auch nicht die Leerungen. Leert ein Speichern das **letzte** Positionsziel
einer Kategorie und ist für die Kategorie kein Gewicht eingetragen, fällt das
Gewicht der Kategorie, das nur der Summe folgte, mit weg: Die Kategorie steht
dann ohne Ziel da statt mit einer Zahl, die niemand eingetragen hat. Eine
**veraltete** Positionszeile (ihr Wertpapier wurde inzwischen einer anderen
Kategorie zugeordnet) erscheint weiter dort, wo sie abgelegt wurde; unverändert
zurückgeschickt bleibt sie, wie sie ist, eine Änderung wird mit dem Grund
abgelehnt — leere sie stattdessen dort. **Das Übernehmen eines Plans aus einer
anderen Sicht** übernimmt auch dessen Positionsziele.

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

Eine bepreiste Position, deren Kursquelle versiegt ist, ist der leisere
Fall: ihr letzter Schlusskurs bewertet sie weiter, als wäre er von heute.
Jede Position trägt deshalb das Datum, von dem ihr Preis stammt
(`price_date` in der API), die Bewertung zählt die gehaltenen Positionen,
deren Kurs älter ist als die Datenqualitäts-Schwelle (`stale_priced_count`),
und der Datenqualitäts-Abschnitt der Vermögensseite nennt sie mit diesem
Datum und dem Mittel: das Wertpapier als **eingestellt** markieren, wenn
seine Notierung endete, oder seine Kurse synchronisieren — und einmal
eingestellt, verlässt die Position Zählung und Befund, weil ihr alter
Schlusskurs dann erwartet ist. Dieselbe Schwelle markiert den Kurs überall
dort, wo er gelesen wird: ein älterer Kurs zeigt „veraltet · Datum" unter
dem Kurs in der Zeile der Wertpapierliste und im Kopf des Wertpapiers sowie
neben dem Wert in der Positionstabelle der Vermögensseite, in Achtung-Ton
mit Glyphe und Wort, und die Tagesänderung zeigt „—" statt einer aus einem
veralteten Schlusskurs berechneten Änderung. Das
Eingestellt-Kennzeichen ist zugleich das, worauf die Performance-Zahl
reagiert — der veraltete Kurs einer eingestellten Position gilt nicht mehr
als Marktbeobachtung, eine spätere Buchung stellt also die Basis neu fest,
statt die Lücke als Rendite zu melden (ADR-0010, Ergänzung vom 2026-09-15).
Eine Einlieferung oder Auslieferung mit gebuchtem Preis wird im
Performance-Lauf zu diesem Preis bewertet, sodass ein Totalverlust, der zu 0
ausgebucht wurde, als der Verlust erscheint, der er ist.

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
erfasst als datierter **Snapshot** (der Dialog **Saldo setzen** an der
Kontozeile auf Konten & Depots, `POST /api/v1/cash_accounts/:id/balance`
oder das MCP-Tool `cash_accounts.set_balance`). Der Saldo verankert sich dann an diesem Betrag, und
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
aggregiert) — mit dem Gesamtwert inkl. Cash und der **YTD-TTWROR** als
Änderungssignal — darunter die **Kennzahlenleiste** (UX-DR2 in der Fassung
vom 2026-09-14, Issue #798): vier Zellen, jede verlinkt auf die Oberfläche,
der die Zahl gehört — die **TTWROR 1J** mit ihrem IRR (bei kürzerer
Historie die Perioden-MWR) führt zum Vermögen, die **Cashquote** mit dem
Cash-Betrag zum Vermögen, die **letzte Buchung** mit Datum, Art und Konto
oder Wertpapier zu den Transaktionen, und die **Kursaktualität**, das Datum
des neuesten gespeicherten Kurses über die gehaltenen Positionen, zur auf
veraltete Kurse vorgefilterten Wertpapierliste; ihre Unterzeile „n veraltet"
erscheint nur, wenn es veraltete Kurse gibt (sonst das Datum allein — ein
Fakt, kein „alles in Ordnung"), und eine Basiszeile unter der Leiste nennt
Ansicht, Zeitraum und Währung — eine Liste
**Ziel-Abweichungen** (Issue #718 — die Karte ist nach ihrem Inhalt benannt,
gemäß UX-DR21) — jede Kategorie mit Ziel, deren Allokations-Drift
**±5 Prozentpunkte** überschreitet (ADR-0023-Vorzeichen: positiv =
übergewichtet), schlimmste zuerst, jede Zeile mit einem dekorativen
Drift-Balken um die Null neben ihrem Text und verlinkt in den Tab
„Allokation & Ziele" des Vermögens-Bereichs, unter einer Basiszeile, die Ansicht,
Klassifikationsbaum und aktiven Plan nennt, gegen den die Drift gerechnet
wird (oder dass mehrere Pläne aktiv sind oder keiner) — und die
**Datenqualitätszeile**: ein Hinweis,
der die Wertpapiere ohne aktuellen Kurs, Anlageklasse oder Logo aufzählt,
wobei jeder Zähler auf die exakt darauf vorgefilterte Wertpapierliste
verlinkt. Die Zeile erscheint nur, wenn mindestens ein Zähler größer als null
ist; ein sauberer Katalog zeigt nichts (kein grünes „alles in Ordnung"). Es
gibt bewusst keinen Aktivitäts-Feed: die forensischen Details gehören dem
Audit-Journal.

## Vermögens-Seite

Der Eintrag **Vermögen** in der Navigation öffnet die Vermögensübersicht,
organisiert in Tabs (ADR-0022): **Bestände** (Wert, Performance, Positionen,
Datenqualität, Cash), **Allokation & Ziele** (Sunburst und Drift-Tabelle) und **Cashflow**
(der Bericht über erhaltene Dividenden und Zinsen). Der Bestände-Tab beginnt
mit dem **Kennzahlen-Band in zwei Ebenen** (Issue #797): drei Leitkennzahlen
in voller Größe — der Gesamtwert inklusive Cash mit seiner Zusammensetzung
aus Wertpapieren und Cash, die TTWROR mit dem absoluten Ergebnis des
Zeitraums und der geldgewichtete **IRR** mit seiner Basiszeile — über vier
Nebenkennzahlen in halber Höhe: Wertpapierwert, Cashquote mit dem
Cash-Betrag, Anfangswert mit den Nettoflüssen und Vermögens-Multiplikator.
Die Währung steht als kleines Suffix hinter den Ziffern, sodass keine Zahl
umbricht. Die Renditen gelten für einen wählbaren Zeitraum (laufendes Jahr,
ein/drei/fünf Jahre oder seit der ersten Transaktion; ein Jahr ist die
Voreinstellung) mit dem kumulativen Performance-Chart. Der Tab „Allokation &
Ziele" wiederholt das Band nicht: er trägt eine Zeile — Gesamt, Cashquote,
TTWROR — mit Link zurück zu Bestände. Unter den Nebenkennzahlen stehen das
**eingesetzte Kapital** — immer zwei beschriftete Zahlen, der Wert zum Periodenbeginn und
die externen Nettoflüsse (Einzahlungen minus Entnahmen, Einlieferungen zum
Transaktionswert), nie eine zusammengelegte Zahl — und der
**Vermögens-Multiplikator**: Endwert ÷ eingesetztes Kapital, das ehrliche
„was aus dem eingezahlten Geld geworden ist". Bei eingesetztem Kapital von
null oder darunter zeigt der Multiplikator `n/a` — nie einen negativen
Multiplikator. Für Zeiträume unter einem Jahr trägt die geldgewichtete
Kennzahl das Label **MWR** und zeigt die Periodenzahl statt einer
annualisierten, die ein kurzes Fenster aufblähen würde (ADR-0034).

**Positionen** (Issue #814) listet die Bestandsprojektion, die diese Instanz
über die API ausliefert — eine Zeile je Depot und Wertpapier, bewertet zum
zuletzt gespeicherten Preis — mit einer **Spalten**-Auswahl über die Felder
genau dieser Projektion: neben den Vorgaben Depot, Wertpapier und Stückzahl
ISIN, WKN, Währung, durchschnittlicher Einstand, letzter Preis, Marktwert und
das unrealisierte Ergebnis in Geld und Prozent. Es sind dieselben Felder, die
ein Agent über `fields=` der Bestands-API auswählt, aus derselben Projektion
gelesen — mit den Trennzeichen Ihrer Sprache und mit der Währung der Zeile
hinter jedem Geldbetrag, damit ein Marktwert seine Währung nennt, auch wenn
die Spalte Währung abgeschaltet ist. Die Auswahl liegt im Browser und
übersteht ein Neuladen; alle Haken zu entfernen fällt auf die Vorgaben
zurück. Die Auswahl steht über der Tabelle und erscheint nur, wenn es eine
Tabelle zu konfigurieren gibt. Neben den festen Buttons verkettet ein
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
Segmente keinen Text im Chart: die **Mitte** des Charts trägt den Bezugswert
(die allokierte Summe) oder, beim Überfahren oder Antippen, Name, Wert und
Ist-Anteil gegen Soll des berührten Segments — der Tooltip des
Touch-Geräts — während ein Zeiger zusätzlich einen **sofortigen, eigenen
Tooltip** erhält, der ihm folgt (keine Browser-Hover-Verzögerung). Die
Legende zeigt zu jedem Anteil seinen Wert, und die Basiszeile des Charts
nennt den Plan, die Σ seiner obersten Soll-Ebene, die Ansicht und den
Stichtag. Die Drift-Tabelle darunter sitzt hinter dem Aufklappen **Daten als
Tabelle**, das jedes Chart trägt. Mit
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
faltet den ganzen Baum bis zur Einzelposition. Daneben stehen die
**Abweichungs-Chips** — *Abweichung ab ≥ 1 pp / ≥ 2 pp / ≥ 5 pp*: Ein Klick
verengt die Tabelle auf die Kategorien, die tatsächlich um mindestens so viel
abweichen — in beide Richtungen —, ein erneuter Klick auf den aktiven Chip hebt
die Auswahl wieder auf. Drei Dinge sind wissenswert. Die Stufe 5 pp ist
dieselbe Schwelle, die die Aufmerksamkeitsliste des Dashboards verwendet;
Warnungen und Tabelle sind sich also einig, was Aufmerksamkeit braucht. Eine
gefilterte Tabelle ist **flach** — eine erhaltene Kategorie erscheint auch
dann, wenn ihr Elternteil unter der Schwelle liegt und damit fehlt — und sie
behält immer die Zeilen *Cash* und *Nicht zugeordnet*; die Zeile über der
Tabelle sagt das zusammen mit „wie viele von wie vielen Kategorien" an.
Schließlich steht die Schwelle in der URL (`?drift=5`), ein gemerkter oder
geteilter Link öffnet also wieder dieselbe gefilterte Ansicht; es ist derselbe
Filter, den API und MCP als `min_drift=` anbieten (dort ein Gewichtsanteil:
5 pp sind `min_drift=0.05`).

Worauf sich die Prozentpunkte beziehen, ist wichtig, wenn ein Plan bewusst
nicht auf 100 % summiert: Die Chips nutzen **dieselbe Drift** wie die
Drift-Spalte und die Aufmerksamkeitsliste des Dashboards — und die wird nach
ADR-0040 gegen den auf den zugeordneten Anteil normierten Plan gemessen, nicht
gegen die rohe Soll-Spalte. Bei einem Plan mit 83 % Summe ist eine Kategorie
mit 21,2 % Ist gegen 55 % gespeichertes Soll also 45 pp entfernt, nicht 34 —
und Chips, Drift-Spalte, Dashboard und `min_drift=` sind sich über diese Zahl
einig. Ein Umschalter **Baum |
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
Wertpapier wurde verschoben oder die Zuordnung entfernt), nennt eine
**Datennotiz über der Tabelle** den Befund und die betroffenen Kategorien
(Issue #719 — Befunde erscheinen als Notizen, nie als Pillen in Datenzellen;
ein Konflikt mit Schweregrad Problem, ein veraltetes Ziel mit Achtung), und
die betroffene Positions-Zeile selbst trägt einen Chip *veraltetes Soll*. Ein gehaltenes, aber nicht
zugeordnetes Wertpapier mit einem (veralteten) Positions-Ziel zeigt dieses
Ziel auch an seiner Zeile im Bereich *Nicht zugeordnet*. Trägt keine
Top-Level-Kategorie ein Ziel, wohl aber tiefere Kategorien, ergänzt die
Σ-Kopfzeile die Summe der tieferen Ziele („Ziele tiefer im Baum") statt ein
nacktes 0 % zu zeigen. Der Cash-Abschnitt
listet den Saldo jedes Kontos nur lesend und verlinkt auf **Konten & Depots**:
dort zeigt jede Geldkonto-Zeile ihren Saldo mit Stand-Datum und öffnet einen
kleinen Dialog **Saldo setzen**, in dem das Konto bereits gewählt ist — den
Saldo eingeben, den die Bank zeigt, und der Snapshot wird ohne Buchung
einzelner Transaktionen erfasst.

**Die Seite ist auf eine Ansicht eingegrenzt (ADR-0024).** Die Kopf-Summen und
der Cash-Abschnitt folgen der **aktiven Ansicht über alle Portfolios hinweg** —
**Alles** (englisch *Everything*) ist die eingebaute Voreinstellung und zeigt
jede Position, jedes Konto genau einmal gezählt. Wähle eine Ansicht im
**Sicht-Umschalter** oben auf der Seite — sein Link **Ansichten** (Issue
#720: umbenannt von „Verwalten…", die Auslassungspunkte entfallen, weil er
navigiert statt einen Dialog zu öffnen) öffnet die
Ansichten-Seite, auf der Ansichten und ihre Buckets bearbeitet werden. Diese
Seite liest sich listenorientiert: jede Ansichten-Zeile sagt, was sie tut
(ihre Ein-/Ausschluss-Buckets als Chips) und was sie umfasst (Summe,
Positionen und Konten im Geltungsbereich), die eingebaute Zeile **Alles**
ist als Standard markiert; jede Bucket-Zeile trägt ihre Farbe und ihre
Verwendung (die Konten, auf denen sie Standard ist, die erbenden
Positionen, die direkt getaggten Positionen). Zeilenaktionen sitzen im
Zeilenmenü, die Anlegen-Formulare öffnen sich über **+**, die Zwei-Schritte-
Erklärung ist das ⓘ an jeder Überschrift, und Standard-Buckets werden an der
Kontozeile von Konten & Depots gesetzt, auf die die Basiszeile des
Bucket-Abschnitts verlinkt.
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
Zeitraumauswahl sofort reagiert. Die Zeitraum-Tokens (YTD, 1Y, 3Y, 5Y, Max)
und der %/Wert-Umschalter sind segmentierte Controls; ein Von/Bis-Zeitraum
(ISO-Daten, `YYYY-MM-DD`) und die durchlaufenen Kalenderjahre liegen hinter
dem Bedienelement **Benutzerdefinierter Zeitraum …** daneben. Es öffnet ein
kleines Popover am Bedienelement selbst (Issue #801): das Von/Bis-Paar in
einer Zeile, je ein Chip pro Jahr mit Daten, **Abbrechen** und **Anwenden**
— die Abschnittsüberschrift und der Chart bleiben, wo sie sind. Ein
Jahres-Chip wendet beim Klick an; Esc oder Abbrechen schließt das Popover und
gibt den Fokus an das Bedienelement zurück. Das Von/Bis-Paar ist beschriftet
und validiert als Zeitraum (Issue #721): eine verdrehte oder unlesbare
Eingabe wird mit der Meldung am korrigierbaren Feld abgelehnt, und das
Popover bleibt offen, bis sie korrigiert ist; ein angewendeter Zeitraum oder
ein Jahr schließt es und zeigt sich als aktiver Chip mit den aufgelösten
Daten (oder dem Jahr) in der Zeitraumauswahl — das Bedienelement beantwortet
immer „was sehe ich gerade". Der Custom-Zeitraum des Wertpapier-Detailcharts
verhält sich genauso. Der Chart wird auf
eine begrenzte Punktzahl
heruntergerechnet, sodass ein Jahrzehnt täglicher Historie im Browser leicht
bleibt. Die Aufklappung **Daten als Tabelle** unter dem Chart enthält
zusammenfassende Zeilen — eine je Jahr, bei Zeiträumen bis zu einem Jahr je
Monat — mit Start- und Endwert, der TTWROR des Abschnitts und seinen
externen Nettoflüssen, statt eines täglichen Dumps. Geld und Prozente folgen der gewählten Sprache (Deutsch `1.234.567,89`,
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
stattdessen am ersten plausiblen Tag angewendet wurden. Jeder Befund ist
eine Notiz in seiner eigenen Stufe — Hinweis für den Handelspreis-Rückfall,
Achtung für ausgenommene und veraltete Positionen, Problem für negative
Bestände — und trägt sein Mittel in der Notiz: das Bedienelement
**Wechselkurse synchronisieren** steht im Befund zum fehlenden Wechselkurs,
und ein Verrechnungskonto, das mangels Kurs ausgenommen ist, ist auch in der
Cash-Tabelle mit *kein Wechselkurs* markiert. Positionen mit
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

**Benchmark-Vergleich**
([ADR-0046](/decisions/0046-benchmark-comparison.html), FR-9) — *war der
Aufwand das wert?* Unter **Benchmark…** im Performance-Abschnitt lassen
sich bis zu zwei Benchmarks wählen: ein auf der Wertpapierseite als
Benchmark markiertes Wertpapier (ein Index über einen ETF, Gold über einen
ETC, per gewöhnlichem Kurs-Sync) oder ein fester Jahreszins als Prozentwert
(die Tagesgeld-Alternative; in dieser Version auch die Ausdrucksform der
Inflation). Die Wahl steht in der URL und wird wie die aktive View gemerkt;
ein Zins wird nur behalten, wenn der Vergleich ihn exakt verwenden kann
(zwischen −99,9999 % und 1000 % p. a., als Bruch mit höchstens 15
Nachkommastellen), und ein gemerkter Zins, der das nicht mehr erfüllt,
fällt beim nächsten Aufruf weg. Zwei Vergleiche erscheinen, beide so, wie Portfolio Performance sie zeigt.
**Einmal gekauft** — die auf den Periodenbeginn rebasierte Benchmark als
gestrichelte Linie über dem TTWROR-Chart, mit eigener Legende und im
Chart-Tooltip — beantwortet, ob die Auswahl den Index geschlagen hat.
**Sparplan** — Eröffnungswert des Zeitraums und jede Einzahlung oder Entnahme
am selben Tag zum Kurs jenes Tages in die Benchmark investiert, ohne Gebühren
und Steuern — ergibt einen Endwert; der Vergleichsblock neben TTWROR/IRR
zeigt den realen Endwert minus diesem Wert als Kennzahl, daneben das
Einmal-gekauft-Paar und die beiden IRRs auf identischen Flüssen. Ein Fluss
vor dem ersten Kurs der Benchmark bleibt außen vor, und der Block nennt das
abgedeckte Fenster. Das synthetische Portfolio ist reibungsfrei, was den
Vergleich gegen das reale Portfolio verzerrt — die konservative Richtung.
Nichts wird gespeichert: beide Vergleiche werden beim Lesen abgeleitet, je
Zeitraum und je View, und stehen über die API (`…/performance/benchmark`)
und die MCP-Tools `portfolixir.portfolios.benchmark` und
`portfolixir.views.benchmark` bereit.

## Cashflow

Der Bereich **Cashflow** (`/cashflow`) ist der Ort, an dem Geldbewegungen
rückblickend gelesen werden. Er ist ein Bereich und keine einzelne
„Erträge"-Seite, weil drei der hier gehörenden Auswertungen gar keine Erträge
sind — realisierte Gewinne aus Verkäufen, Ein- und Auszahlungen sowie Kosten —
und sie unter ein Label zu stellen genau die Mehrdeutigkeit reproduziert, die
diese Anwendung vermeiden soll. Jede Auswertung ist ein eigener benannter
Bereich, und ein Bereich erscheint erst, wenn seine Daten existieren; nichts
wird als leere Hülle gezeigt. **Income** ist der Standard-Bereich, und
`/income` funktioniert weiterhin — die Adresse leitet hierher weiter, sodass
ältere Links und Lesezeichen erhalten bleiben. Seit Issue #724 trägt der
Bereich einen zweistufigen Facetten-Umschalter.

**Realisierte Gewinne** (`/cashflow?tab=realized`, Issues #724 und #807)
beantwortet „was hat Verkaufen tatsächlich gebracht" — und ist seit Issue #807
**die Trades-Ansicht**: die Facette öffnet mit drei Zahlen — der realisierten
Summe, der **Trefferquote** (dem Anteil der abgeschlossenen Trades mit Gewinn;
ein Nullergebnis zählt nicht als Treffer) und der **durchschnittlichen
Haltedauer** — gefolgt von den abgeschlossenen Rundläufen selbst, neuester
Schluss zuerst, je Zeile das Wertpapier (verlinkt auf seinen Trades-Tab),
gekauft → verkauft, die Haltedauer, die Stückzahl, die Kosten, der Erlös und
das Ergebnis in Geld und Prozent, das Ergebnis in seiner Vorzeichenfarbe. Die
Jahres-/Monatsmatrix, mit der die Facette früher öffnete, behält jede Zahl —
jetzt unter **Realisiert je Periode** hinter der Aufklappung **Matrix nach
Jahr und Monat** unter der Liste. Konnte ein Verkauf nicht konvertiert
werden, führt der Hinweis, wie viele und welche, den Abschnitt an — über den
drei Zahlen, die er einschränkt, samt seiner Nachlade-Schaltfläche — statt
unter den Zahlen zu stehen, um die es geht.

Ohne abgeschlossene Trades lesen sich Trefferquote und Haltedauer als
abwesend statt als 0 % und 0 Tage. Alle drei Zahlen stammen aus
FIFO-gematchter realisierter G&V über alle Wertpapiere, gruppiert nach dem
**Schlussdatum** jedes Verkaufs. Die FX-Basis steht auf der Oberfläche und reist in der
API-Payload mit (Entscheidung D-1): jeder Verkauf konvertiert über den
EUR-Hub zum Kurs **seines eigenen Schlusstags** —
die Basis des Income-Bereichs, denn eine realisierte Zahl ist ein historischer
Fakt an ihrem Datum. Ein Verkauf **ohne** gespeicherten Kurs zu diesem Datum
wird **aus jeder Summe ausgeschlossen und benannt** (Achtung-Notiz mit Anzahl
und Wertpapieren) — nie zum Kurs eines Nachbardatums konvertiert, nie still
verworfen. Die tägliche Kurssynchronisation holt *aktuelle* Kurse und kann
einen vergangenen Tag nicht nachtragen; die Notiz trägt daher die Abhilfe, die
es kann: **Historische Kurse nachladen** holt die historische EZB-Reihe
einmalig, speichert jeden veröffentlichten Tag und liest die Facette neu — der
ausgeschlossene Verkauf konvertiert zum Kurs seines eigenen Schlusstags,
sobald dieses Datum einen hat (Issue #737). Die verbleibende Grenze steht
neben der Schaltfläche: Ein Tag, den die EZB nicht veröffentlicht hat (ein
Wochenende, eine nicht gelistete Währung), bleibt ausgeschlossen und benannt.
Dasselbe Backfill ist `scope=history` am Wechselkurs-Sync-Endpunkt und
MCP-Tool; die Facetten Ein- & Auszahlungen und Kosten tragen dieselbe
Schaltfläche in ihren Ausschluss-Hinweisen.

**Ein- & Auszahlungen** (`/cashflow?tab=flows`, Issue #725) ist die
„Ersparnis": was eingezahlt und entnommen wurde, je Periode, als zwei Serien
mit Jahresnetto — getrennt von dem, was das Portfolio erwirtschaftet hat.
Gezählt werden nur die **gebuchten** Ein- und Auszahlungen, und das steht
dort: ein-/ausgelieferte Wertpapiere und Saldo-Snapshot-Sprünge stecken nicht
in dieser Zahl, wohl aber im investierten Kapital der Performance — die
Oberfläche nennt den Unterschied, statt zwei widersprechende Zahlen zum
Entdecken zu lassen. Gleiche FX-Basis und gleiche
Ausschluss-und-Benennungs-Regel wie die Schwester-Facetten; unkonvertierbare
Flüsse werden nach Verrechnungskonto benannt.

**Kosten** (`/cashflow?tab=costs`, Issue #726) ist, was das Portfolio im
Betrieb gekostet hat: Gebühren und Steuern je Periode, als zwei Serien mit
Jahressumme — **nur auf Übersichtsebene**, bewusst kein Kosten-Journal je
Transaktion. Summiert werden die Gebühren- und Steuer-**Nebenbeträge** jeder
Transaktion plus die eigenständigen Gebühren- und Steuerbuchungen;
Steuererstattungen werden gegen die Steuern verrechnet. Bruttobeträge werden
nie summiert — beim Kauf enthält das Brutto die Nebenbeträge, beim Verkauf
ist es um sie gemindert — und die Oberfläche nennt diese Regel in ihrer
Zusammensetzungszeile. Gleiche FX-Basis und gleiche
Ausschluss-und-Benennungs-Regel wie die Schwester-Facetten; unkonvertierbare
Kosten werden nach Währung benannt.

Jede Kennzahl des Bereichs nennt, was sie enthält: der Income-Bereich schreibt,
dass er *Dividenden und Zinsen* abdeckt und realisierte Gewinne, Ein- und
Auszahlungen sowie Kosten **ausschließt**. Das ist keine Dekoration — genau
diese Auslassungen sind der Grund, warum es die anderen Bereiche gibt, und wer
sie nicht kennt, liest die Seite als „alles Geld, das hereinkam".

### Income (Dividenden und Zinsen)

Der **Income**-Bereich ist der retrospektive Ertragsbericht: die bereits im
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

Die Jahresbalken über der Matrix sind **gestapelt**, nicht summiert:
Dividenden und Zinsen sind zwei Segmente, sodass Chart und Tabelle sich nie
darüber uneinig sein können, was die Zahl ist. Eine Legende benennt die
beiden Reihen, ein ausreichend hohes Segment trägt seinen Wert als Text;
jedes Jahr zwischen der ersten und der letzten Buchung hat seinen Platz, ein
leeres als Grundlinien-Strich mit „–"; Null-Zellen der Matrix lesen sich als
stilles „–", damit die Zellen mit Werten das sind, was das Auge findet; und
sowohl die Matrix als auch die Zahlungen eines aufgeklappten Jahres sitzen
hinter dem Aufklappen **Daten als Tabelle**, das jedes Chart trägt. Beim Aufklappen eines Jahres
kommt eine **kumulierte** Reihe über dessen Monate hinzu — der laufende
Gesamtstand, sodass ein ruhiger Monat als Plateau statt als Lücke gelesen wird
und die Kurve „wo stand das Jahr im April" beantwortet statt „was kam im April
herein".

Beträge werden in der Basiswährung des Portfolios ausgewiesen; die
ursprüngliche Währung bleibt je Zeile sichtbar. Die Umrechnungsmethodik
(EUR-Hub zum gespeicherten Kurs des jeweiligen Buchungsdatums — dieselbe
Umrechnung wie die Bewertung) steht hinter dem ⓘ neben der Währungszeile.
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

**Der Vergleich ist die Oberfläche.** Mit mindestens einem Snapshot öffnet
die Seite auf dem Vergleich des neuesten; die Liste darunter wählt, welcher
Snapshot verglichen wird (die verglichene Zeile ist markiert, die URL trägt
`?snapshot=`). Der Vergleich zeigt das Kontrafaktual:

- **Real (TTWROR seit Stichtag)** gegen **Eingefroren (Halten)** — die echte
  zeitgewichtete Performance seit dem Stichtag gegen die Kursrendite des
  eingefrorenen Bestands; die eingefrorene Kennzahl trägt die Positionen des
  Snapshots zum Stichtag und heute bewertet, buy-and-hold über die echte
  gespeicherte Kurshistorie (tägliche Schlusskurse, EUR-Hub-Wechselkurse des
  jeweiligen Tags). TTWROR neutralisiert Ein- und Auszahlungen, frisches
  Geld verzerrt den Vergleich also nicht.
- Das gemeinsame Chart mit beiden Serien als **prozentuale Veränderung seit
  dem Stichtag** (durchgezogen = eingefroren, gestrichelt = real) mit
  Legende, einer Basiszeile, die nennt, was auf welcher Basis verglichen
  wird, und denselben Daten hinter dem Aufklappen **Daten als Tabelle**.

**Die beiden Seiten werden nicht auf derselben Basis gemessen, und die Seite
sagt das.** Die eingefrorene Seite handelt nicht und hat keine Flüsse: sie
zahlt nie etwas. Die echte Seite ist TTWROR, und dort gehören Gebühren und
Steuern zur Rendite — jede Handelskosten seit dem Stichtag drücken sie also,
und die eingefrorene Seite gewinnt automatisch, solange diese Kosten nicht
wieder eingespielt sind. Genau in diesem Zeitfenster wird der Vergleich
üblicherweise gelesen.

Wenn Handelsgeschäfte tatsächlich etwas gekostet haben, erscheinen daher drei
weitere Kennzahlen gemeinsam:

- **Echte TTWROR vor Transaktionskosten** — derselbe Tageslauf, bei dem die
  Handelsgebühren und -steuern des Zeitfensters als abfließendes Geld statt
  als Verlust gewertet werden;
- **Transaktionskosten** — deren Summe in der Basiswährung;
- **Wieder eingespielt?** — *Ja*, wenn die echte Rendite bereits vor der
  eingefrorenen liegt; *Noch nicht*, mit dem verbleibenden Abstand, wenn sie
  vor Kosten vorne liegt und nach Kosten nicht; und *Auch vor Kosten zurück*,
  wenn die Kosten nicht der Grund sind und sich die Änderungen aus eigener
  Kraft nicht ausgezahlt haben.

Sie werden immer zusammen gezeigt und nie die Vor-Kosten-Zahl allein — für
sich genommen ist sie eine Zahl, die schmeichelt. **Transaktionskosten** sind
die *auf einem Handelsgeschäft* gebuchten Gebühren und Steuern. Eigenständige
Gebühren- und Steuerbuchungen bleiben auf beiden Seiten in der Rendite, denn
eine Depotgebühr wird nicht von einem Handel verursacht und der eingefrorene
Halter hätte sie ebenso gezahlt; die Quellensteuer auf Dividenden bleibt
ebenfalls drin, sie gehört zur Dividendenlücke unten und nicht hierher.

Der Vergleich erscheint zuerst und groß, die Snapshot-Liste darunter mit
**Löschen** im Zeilenmenü jeder Zeile, das Anlegen-Formular hinter dem
geschlossenen Aufklappen **Neuer Snapshot** und die Erklärung hinter dem ⓘ
an der Überschrift. Der Vergleich ist in v1 **brutto und nur
Kursentwicklung** — Ausschüttungen, die die eingefrorenen Positionen gezahlt
hätten, sind noch nicht enthalten; die Seite sagt das als Hinweis neben den
Zahlen. Wertpapiere ohne verwendbaren Kurs oder Wechselkurs zum Stichtag
werden in einem Achtung-Hinweis **ausgeschlossen und aufgeführt**, statt
still mit null bewertet zu werden. Derselbe Vergleich steht über die
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
einem Übertragungsfehler eine dauerhaft falsche Zahl. Die Liste der
Abrechnungen stellt die Töpfe anschließend mit dem gedruckten Vorzeichen dar,
damit eine erfasste Zeile mit dem Papier vergleichbar bleibt.

**Die Seite ist eine Budget-Anzeige plus Prüfliste.** Steuerpflichtige Person
und Steuerjahr sind segmentierte Steuerelemente (der Bereich steht in der
URL, `?holder=…&year=…`). Das Budget erscheint als Füllstandsanzeige: der
verbleibende Betrag als Wert, die Ausschöpfung des Freistellungsauftrags als
Füllstand ohne Schwellenfärbung, Stichtag und erfasste Institute auf der
Basiszeile, daneben die Zusammensetzung — Verlusttopf Aktien, verbleibender
Freistellungsauftrag, gesetzlicher Höchstbetrag — mit einem ⓘ zur Regel
„erfasst, nicht berechnet". Ein veraltetes oder unvollständiges Budget ist
eine Datennotiz neben der Anzeige mit dem Mittel darin („Neue Abrechnung
erfassen"). Die erfassten Abrechnungen sind eine Liste; jeder Prüfbefund ist
eine Datennotiz an seiner Zeile mit dem Prüf-Bedienelement darin, und
„Korrigieren" und „Löschen" sitzen im Zeilenmenü. Beide Eingabeformulare
öffnen sich aus einem Aufklappen und sind standardmäßig geschlossen; die
Vorzeichenregel ist Feldhilfe an den Betragsfeldern, und die hinterlegten
Freistellungsaufträge sitzen hinter einem Aufklappen, das ihren Zweck nennt.

**Der Verkaufsspielraum** ist der Verlusttopf Aktien plus der verbleibende
Freistellungsauftrag (`erteilt − verbraucht`). Er wird immer **mit seinem
Stichtag** gezeigt und erst dann als **veraltet** markiert, wenn die
Alterung belegt ist: wenn steuerrelevante Buchungen nach dem
Abrechnungsdatum Verlusttöpfe oder Freistellungsauftrag verbrauchen, oder
wenn die Abrechnung älter als 90 Tage ist. Der Hinweis nennt seinen Grund —
ein ruhiges Buchungsjournal hält eine ältere Abrechnung nutzbar, statt sie
dauerhaft zu markieren. Über mehrere Institute
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

## Risiko (Konzentration und Schwankung)

Der Reiter **Risiko** im Bereich Vermögen zeigt zwei Dinge, die eine Frage
beantworten — wie konzentriert ist das Portfolio, und wie stark schwankt es —
über der **steuerbaren Basis** der aktiven Ansicht (die Ansicht steht im Kopf).

- **Eigene Regeln** ganz oben: die Obergrenzen, Untergrenzen und Bänder des
  Betreibers (ADR-0049) mit ihren Befunden, verletzte und nicht bestimmbare
  zuerst. Der **Name einer Regel ist ein Link** und öffnet ihren Dialog, den
  einen Ort, an dem die Regel geändert (eine neue Version ab einem Datum; die
  bisherige bleibt lesbar), **umbenannt** oder beendet wird. Umbenennen ändert
  nur die Bezeichnung: Es entsteht keine Version, der neue Name gilt für die
  Regel mit allen Versionen, und das Audit-Journal behält den bisherigen
  Namen. Eine beendete Regel wird genauso aus der Liste der beendeten Regeln
  umbenannt. „Risiko“ zeigt die Regeln der aktiven Ansicht; eine Regel, die in
  einer anderen Ansicht gilt, steht in jener Ansicht. Wird das Löschen einer
  Ansicht, einer Kategorie, einer Klassifizierung oder eines Wertpapiers
  abgelehnt, weil Regeln es lesen, nennt die Ablehnung die Regeln mit Stand und
  Ansicht, und jeder Name führt auf „Risiko“ in der Ansicht, in der die Regel
  gilt.
- **Kennzahlen des Portfolios**, ein Jahr: die annualisierte **Volatilität**,
  der **maximale Rückgang** mit Beginn, Tiefpunkt und Erholung, die
  **risikoadjustierte Rendite** (bei einem risikofreien Satz von 0 ist sie
  Rendite je Risikoeinheit) und die höchste **Korrelation** unter den größten
  Positionen. Gemessen wird über die um Zahlungen bereinigten Tagesrenditen der
  TTWROR-Kette: eine Einzahlung oder Entnahme zählt nie als Schwankung, wer
  spart, liest bei gleichen Kursen dasselbe Risiko wie wer nur hält. Eine Zahl
  ohne ausreichende Historie sagt **„nicht berechenbar“** mit der Zahl der
  vorhandenen und der nötigen Beobachtungen, statt eine Zahl zu zeigen.
- **Größte Einzelpositionen** mit Gewicht und der Schwelle, über oder unter der
  sie liegen — über 10 % für eine Einzelaktie (7 % ist die erste Linie), über
  25 % für einen ETF. Die Schwelle wird genannt, nicht bewertet.
- **Klumpenrisiko (HHI)** auf der Skala 0–10.000 mit Band (niedrig unter
  1.500, konzentriert ab 2.500).
- **Anlageklassen-Obergrenzen**, sofern über die API gesetzt.
- **Korrelationen** der größten Positionen hinter einer Aufklappfläche, zuerst
  in die Basiswährung umgerechnet und nur über Tage mit Kurs für beide. Die
  Grundlagenzeile nennt, über wie viele der größten Positionen sie laufen: die
  Matrix erfasst höchstens die 20 größten, wie lang die Liste auch ist.

Die Seite berichtet, sie empfiehlt nicht. Dieselben Zahlen liefert
`GET /api/v1/portfolios/:portfolio_id/risk` und das MCP-Werkzeug
`portfolixir.portfolios.risk`, mit allen drei Fenstern.

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

### Dateien und Zeilen, die die Vorschau ablehnt

Eine Datei, die die Vorschau nicht sicher halten kann, wird als Ganzes
abgelehnt, bevor etwas für den nächsten Besuch aufbewahrt wird. Der Grund steht
mit seiner Abhilfe im Meldungsband über dem Ablagefeld, und das Ablagefeld
nimmt sofort die nächste Datei:

- **Eine Datei, die nicht in UTF-8 kodiert ist**, wie sie oft entsteht, wenn
  eine Tabellenkalkulation einen Export neu gespeichert hat: in Portfolio
  Performance neu exportieren und die Datei ablegen, ohne sie vorher in einer
  Tabellenkalkulation zu öffnen.
- **Eine Datei mit zu vielen unterschiedlichen Konto-, Depot- oder
  Wertpapiernamen** für eine Vorschau, weit mehr, als ein gewöhnlicher Export
  enthält: in Portfolio Performance kleinere Exporte anlegen, etwa je Konto
  oder Depot, und nacheinander importieren.
- **Eine Datei, die mehr Einträge ergibt, als der Import fasst**, gezählt
  jede Zeile und jede Steuererstattung, die eine Zeile abspaltet: den Export in
  Portfolio Performance teilen, etwa nach Jahren.

Eine einzelne Zeile, die der Import nie buchen könnte, ist stattdessen eine
Parser-Warnung: Sie steht mit ihrer Zeilennummer im Warnungsfeld, zählt nicht
zu den Einträgen, und der Rest der Datei wird angezeigt und importiert. Ein
Wertpapiereintrag, der nichts benennt (kein Name, keine ISIN, WKN oder kein
Ticker), ist eine solche Zeile: *Wertpapier ohne Name und ohne ISIN — Zeile
nicht übernommen*. Ebenso eine Zeile mit einem Wert, den keine Spalte des
Ledgers hält (ein Betrag, eine Gebühr, eine Steuer, eine abgespaltene
Steuererstattung oder ein abgeleiteter Kurs mit mehr Stellen vor dem Komma,
als die Spalte nach dem Runden auf ihre Nachkommastellen fasst), eine Zahl, die
der Parser nicht lesen kann, und eine Transaktion mit mehr Gebühren- und
Steuerpositionen, als eine Buchung trägt: Jede wird mit Feld und Zeile
benannt und lässt den Import nach dem Bestätigen nie scheitern. Ein Eintrag nur mit WKN oder nur mit Ticker ist ein
Wertpapier wie jedes andere und wird über die Zuordnungsleiter unten
aufgelöst. Eine Vorschau wird für den nächsten Besuch (Sprachwechsel,
Neuladen) erst aufbewahrt, wenn sie einmal angezeigt wurde.

### Was ein erneuter Import bewahrt

Das erneute Anwenden **desselben** Portfolio-Performance-Exports ist ein
**No-op per Inhalts-Hash**: Jede bereits vorhandene Transaktionszeile wird
als Duplikat übersprungen, kein Wertpapier wird doppelt angelegt, und nichts,
was nach dem ersten Import in Portfolixir gepflegt wurde, wird angefasst.
Auf synthetischen Fixtures verifiziert und als dauerhafter Regressionstest
festgehalten, überstehen die folgenden Dinge einen erneuten Import
unverändert, mit denselben ids und exakten Werten:

- Klassifizierungs-Zuordnungen (eigene Bäume und die Kategorien, in denen ein
  Wertpapier sitzt);
- jede Zielplan-Version mit ihren Kategorie- und Positionszielgewichten sowie
  das Cash-Ziel;
- die Notiz und die Attribute jedes Wertpapiers, einschließlich eigener
  Attributschlüssel;
- das Research-Log des Wertpapiers (die Einträge des Tabs „Research“ und der
  daraus abgeleitete Thesenstand);
- Wertpapier-ids und ihr `updated_at` — nichts wird stillschweigend
  überschrieben.

Ein **veränderter** erneuter Import (ein umbenanntes Wertpapier, ein erfasster
ISIN-Wechsel) hält dieselbe Garantie für die zugeordneten Wertpapiere; die eine
wirklich neue Buchung landet, sonst ändert sich nichts. Was diese Garantie
**nicht** abdeckt, ist eine in der Quelle geänderte Buchung: Eine bearbeitete
Transaktion hasht anders und wird als neue Zeile neben der alten importiert —
die alte Buchung von Hand entfernen oder korrigieren. Dieselbe Aussage steht
in der [API- und MCP-Referenz](integration/api-and-mcp.html), damit ein Agent
sie dort liest, wo er die Endpunkte liest.

### Was ein erneuter Import zuerst prüft (ADR-0050)

Der Inhalts-Hash jeder Zeile wird geprüft, **bevor irgendetwas aufgelöst oder
angelegt wird**. Eine Zeile, die die Datenbank schon hält, steht bei den bereits
gebuchten Datensätzen und legt nichts an: kein Wertpapier, kein Konto, keine
Transaktion. Dasselbe gilt für eine Zeile, die eine Zusammenführung entfernt
hat: Ihr Hash bleibt als **stillgelegter Inhalts-Hash** erhalten, und das
Ergebnis nennt ihn so.

Verrechnungskonten und Depots entstehen **mit ihrer ersten importierten
Buchung**, nie vorab. Ein Konto, das auf *+ Neu anlegen* zugeordnet ist und
dessen Zeilen alle schon gebucht oder aus einem anderen Grund übersprungen
sind, wird nicht angelegt, und der Bucket-Tag landet auf genau den Konten, die
der Import angelegt hat. Ein importiertes Konto umzubenennen und denselben
Export erneut abzulegen, legt kein leeres Konto unter dem alten Namen an.

**Konten werden über den Namen gefunden, dann über einen früheren Namen.** Die
Vorschau belegt jedes Verrechnungskonto und Depot der Datei mit dem Konto
genau dieses Namens vor, sonst mit dem Konto, das ihn als früheren Namen trägt
(siehe [Konten und Depots](#konten-und-depots)). Eine Umbenennung behält den
bisherigen Namen, sodass auch ein Export, der sich in Portfolio Performance
verändert hat (eine andere Nachkommagenauigkeit, eine bearbeitete Buchung),
das umbenannte Konto findet und nichts doppelt bucht. Ein Name, den zwei
Konten tragen, wird mit nichts vorbelegt: Die Auswahl zeigt *Entscheiden…*,
und der Import wartet, bis das Konto gewählt ist; er rät nie. Wird eine
Vorbelegung auf ein Konto anderen Namens geändert, wird die Zuordnung
standardmäßig **gemerkt**: Der Name wird früherer Name dieses Kontos, und der
nächste Import belegt ihn selbst vor. Eine unveränderte Vorbelegung merkt
nichts. Ist der Name der Name eines anderen Kontos, gilt die Wahl nur für
diesen Import. Ist er früherer Name eines anderen Kontos, gilt die Wahl
vorerst ebenfalls nur für diesen Import: Die Importseite verschiebt einen
früheren Namen erst dann auf ein anderes Konto, wenn die Vorschau das vor dem
Bestätigen sagen kann. Um ihn zu verschieben, zuerst aus den früheren Namen
des anderen Kontos entfernen (über API oder MCP) und dann erneut zuordnen.
Wird ein in der Vorschau zugeordnetes Konto vor dem
Bestätigen zusammengeführt oder gelöscht, hält der Import an, bevor er etwas
schreibt, und die Kontenzuordnung wird neu vorbelegt.

Umbenennungen von vor diesem Release werden ebenfalls gemerkt: das Update
spielt die Umbenennungen nach, die das Audit-Journal hält. Einen Namen, den
ein neueres Konto schon trägt (etwa ein leeres Konto, das ein früherer Import
unter dem alten Namen angelegt hat), protokolliert das Update und lässt ihn,
wo er ist; dieses Konto in das umbenannte zusammenzuführen, behebt das. Eine
Umbenennung, die älter ist als das Audit-Journal der Konten, hat keine Spur
hinterlassen; ihr alter Name wird einmal von Hand zugeordnet.

Eine **Umbuchung, deren beide Seiten auf dasselbe Konto oder Depot führen**
(etwa zwei Portfolio-Performance-Konten, die auf ein Portfolixir-Konto
zugeordnet sind), ist nichtig. Sie wird übersprungen und bei den internen
Umbuchungen mit Zeile, Art, Datum und beiden Namen aus der Datei aufgeführt,
und der Rest der Datei wird importiert; sie lässt nicht mehr den ganzen Import
scheitern.

Das Ergebnis listet jeden übersprungenen Datensatz mit der Prüfung, die ihn
übersprungen hat: eine identische, schon importierte Zeile (gespeicherter
Inhalts-Hash), eine Zeile, die eine Zusammenführung entfernt hat
(stillgelegter Inhalts-Hash), oder eine bestehende Buchung mit demselben Datum,
Wertpapier, derselben Stückzahl und demselben Betrag.

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
ausgewiesen, nie doppelt importiert. Zusammengefasst werden nur Zeilen
desselben Portfolio-Performance-Kontos: Zwei gleiche Buchungen aus zwei
verschiedenen Konten der Datei, die auf ein Konto zugeordnet sind (etwa zwei
gleiche Gebühren), werden beide importiert.

**Ein-/Auslieferungszeilen** behalten ihren geparsten Stückpreis (die
CSV-Spalte `Kurs`), sodass eine Einlieferung mit Preis mit ihrem echten
Einstand in den Einstandswert der Bestände eingeht. Eine Lieferzeile ohne
Preis wird weiterhin importiert und bewegt die Menge zum Einstand null, wie
unter Bestandsberechnung beschrieben.

Zeilen mit **unplausiblen Daten** (vor 1900, z. B. ein `0219-03-07`-Tippfehler für
2019) werden je Zeile mit einer klaren Meldung abgelehnt, statt jede abgeleitete
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
  Performance für Aktien/ETFs/Fonds und CoinGecko für Krypto. Der
  Anlage-Dialog bietet zusätzlich **Manuelle Eingabe** (auch aus dem
  Suchschritt verlinkt) für Instrumente, die kein Anbieter kennt — direkt
  zum Detailformular, gespeichert mit dem Provider-Marker `manual`. Handelt
  ein gefundenes Wertpapier an mehreren Märkten, wird der **empfohlene
  Markt** (XETR, sonst der erste EUR-Markt) zuerst mit seinem
  Börsen-Klarnamen angeboten; die übrigen Märkte liegen hinter einer
  Aufklappung *Weitere Märkte*.
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

Die Reiterzeile des Detailbereichs ist ein einziger Tastaturstopp: **Tab**
landet auf dem gewählten Reiter, **Pfeil links/rechts** wechseln zum vorigen
oder nächsten Reiter (am Ende geht es von vorn weiter), **Pos1** und **Ende**
springen zum ersten und letzten, und der Reiter, der den Fokus erhält, öffnet
seinen Bereich.

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
Für Anbieter, die ihre Historie nie rückwirkend anpassen, bieten die
Stammdaten des Wertpapiers (hinter **Bearbeiten** in der Kopfzeile der
Detailansicht) den Schalter **Synchronisierte Kurse als roh behandeln**, der
die Roh-Basis für dessen synchronisierte Zeilen erzwingt. Die Splits eines
Wertpapiers, jeder mit seinem eigenen Betrag gezählt (2:1 und 1:2 zählen
beide 2), multiplizieren sich auf höchstens 10^12: Der Split-Assistent lehnt
ein Verhältnis darüber ab und bucht nichts, denn keine echte Aktienhistorie
kommt in die Nähe.

**Der Reiter Übersicht liest, Bearbeiten schreibt.** Die Detailansicht
öffnet auf **Übersicht**, einer Lesefläche (Issue #804): sechs Kennzahlen —
letzter Kurs mit Datum oder Veraltet-Marker, Tagesänderung, die
Ein-Jahres-Kursrendite, die gehaltene Stückzahl mit dem Depot, der Wert der
Position und das unrealisierte Ergebnis mit seinem Prozentsatz gegen den
Durchschnittseinstand — darunter der Kursverlauf als kleiner Chart und eine
Basiszeile mit Kursquelle, Anlageklasse, der zugeordneten Kategorie eines
eigenen Klassifizierungsbaums sowie WKN und Börse, die die Kopfzeile nicht
trägt. Der aus dem Research-Log abgeleitete Thesenstand (ADR-0044) und die
persönliche Notiz stehen als Karten daneben; die Thesenkarte führt zum
Reiter Research, und die Notiz zeigt erst nach **Hinzufügen** oder
**Bearbeiten** ein Feld. Vorher rendert der Reiter kein Eingabefeld. Die
Stammdaten — Name, Identifikatoren, Währung, Börse, Anlageklasse,
Kursquelle und deren URL, der Roh-Kurse-Schalter und die Notiz — liegen im
Dialog, den **Bearbeiten** in der Kopfzeile öffnet; es ist derselbe Dialog
wie im Zeilenmenü der Liste.

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
- Aktions-Feedback erscheint **im Seitenfluss, nicht als schwebender Toast**:
  Während eine Hintergrund-Aktion läuft (Kurs-Sync, Logo-Suche), zeigt das
  auslösende Bedienelement einen Beschäftigt-Zustand, und das Ergebnis
  erscheint im Seitenfluss nahe den Bedienelementen — Erfolg als Hinweis, ein
  Fehlschlag als Problem-Hinweis mit Begründung. Ein Ergebnis bleibt sichtbar
  bis zur nächsten Aktion, einer Navigation oder dem expliziten
  Schließen-Knopf; nichts verschwindet über einen Timer.
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
  Summen dem Schalter folgen. Seit Issue #805 (C8 des Reviews vom 2026-09-12,
  Variante A) stehen die Zahlen in benannten, rechtsbündigen Spalten unter
  einem Kopf — **Positionen · Wert · Einstand · Ergebnis** — eine leere
  Kategorie zeigt in jeder Spalte „—" statt einer Reihe Nullen, der Zähler
  der verborgenen Positionen ist ein gedämpftes Suffix des Kategorienamens,
  und die Basis des Ergebnisses („heutige Zusammensetzung, keine
  Periodenrendite") ist eine Basiszeile mit ⓘ; auf dem Telefon behält die
  Zeile Wert und Ergebnis.
- Die Seitenleiste ist in aufgabenorientierte Bereiche organisiert (ADR-0022):
  **Übersicht**, **Vermögen**, **Wertpapiere** und **Transaktionen** auf der
  obersten Ebene, plus eine Gruppe **Verwaltung** mit **Konten & Depots**,
  **Ansichten** und **Klassifizierungen**. Sie listet nur existierende
  Routen — keine deaktivierten Roadmap-Platzhalter. Erträge sind ein Tab des
  Vermögens-Bereichs und der Import ein Tab des Transaktions-Bereichs, keine
  eigenen Menüeinträge. Buckets haben keinen eigenen Seitenleisten-Eintrag
  (ADR-0024): sie werden als Chips auf den Zeilen von Konten & Depots und auf
  der Ansichten-Seite verwaltet, die der Link **Ansichten** des
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
- Aufwändige Kennzahlen werden von der Buchung neu berechnet, die sie
  ungültig gemacht hat, nicht von der nächsten Seite, die Sie öffnen: nach
  einer Buchung, einem Import oder einer Kursaktualisierung werden sie im
  Hintergrund aufgefrischt, sodass der obige Hinweis normalerweise einmal
  erscheint statt nach jeder Änderung. Ein Schwung von Schreibvorgängen — der
  Import eines ganzen Exports — kostet eine Auffrischung, nicht eine pro
  Zeile. Bis sie eintrifft, wird der vorherige Wert gezeigt, beschriftet mit
  dem Zeitpunkt seiner Berechnung.
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

Das Löschen eines Geldkontos, eines Depots oder eines Wertpapiers nimmt nie
stillschweigend etwas mit (ADR-0050 §11). Eine Zeile, auf die noch Buchungen
verweisen — bei einem Wertpapier auch Kurse, Recherche-Notizen oder
Ereignisse —, wird gar nicht gelöscht: Der Weg ist dann, sie mit der Zeile
zusammenzuführen, die bleibt. Bei einer unreferenzierten Zeile werden
Bucket-Verknüpfungen, Positions-Overrides und Kategorie-Zuordnungen vorher
entfernt, jeweils über ihren eigenen journalisierten Schreibpfad, sodass das
Journal jede Mitgliedschaft zeigt, die das Löschen beendet hat.

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
