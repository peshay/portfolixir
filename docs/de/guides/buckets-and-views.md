---
layout: docs
title: Buckets & Ansichten – Leitfaden
description: Durchgearbeitete Anwendungsfälle für die Gruppierung des Vermögens mit Buckets und Ansichten.
lang: de
lang_en: /guides/buckets-and-views.html
lang_de: /de/guides/buckets-and-views.html
---

# Buckets & Ansichten – Leitfaden

Portfolixir gruppiert das Vermögen mit zwei Werkzeugen statt mit Portfolios:
ein **Bucket** ist ein Etikett an Depots und Verrechnungskonten, eine
**Ansicht** ist ein gespeicherter Filter über Buckets, der die Auswertungs-
Seiten eingrenzt und einen eigenen SOLL-Plan tragen kann. Dieser Leitfaden
arbeitet vier reale Gruppierungsbedürfnisse mit den exakten Klicks durch,
damit sich ein bestehendes Setup auf das Modell abbilden lässt, statt es
zurückzuentwickeln. Die Begründung des Modells steht in
[ADR-0024](/decisions/0024-buckets-and-views-replace-portfolios-in-the-ui.html)
(englisch); die Referenzbeschreibung liefert die
[Produktdokumentation](/de/product-documentation.html#konten-und-depots).

## Brauche ich einen Bucket oder eine Ansicht?

Ein **Bucket** beantwortet „Wozu gehört dieses Konto?" — er ist ein Etikett
an Depot- und Kontozeilen, nicht mehr. Eine **Ansicht** beantwortet „Was will
ich betrachten (und steuern)?" — sie ist ein gespeicherter Einschluss-/
Ausschlussfilter über Buckets, der im Sicht-Umschalter ausgewählt, als
Standard festgelegt und mit einem SOLL-Plan versehen wird. Faustregel:
Etikettiere die Realität mit Buckets und lege dann je wiederkehrender Frage
eine Ansicht an. Buckets allein ändern auf den Auswertungsseiten nichts; erst
eine Ansicht grenzt ein, was angezeigt wird.

## Anwendungsfall 1: „Mein Vermögen" vs. „ganzer Haushalt"

Szenario: Einige Konten sind mit einem Partner geteilt, und zwei Zahlen sind
gefragt: das eigene Vermögen und der ganze Haushalt — ohne dass ein
Gemeinschaftskonto je doppelt zählt.

1. Öffne **Konten & Depots** (Seitenleiste, Bereich Administration). Jede
   Zeile zeigt ihre Bucket-Zugehörigkeiten als Chips.
   <!-- screenshot: accounts-depots-bucket-chips -->
2. Klicke auf jeder ausschließlich eigenen Zeile den **+**-Chip (**Bucket
   hinzufügen**), tippe `Meins` in das Feld **Neuer Tag** und klicke **Tag
   anlegen**. Der Tag wird in einem Schritt erstellt und zugewiesen.
3. Markiere die Zeilen des Partners genauso mit einem neuen Tag
   `Partner`. Gemeinsame Konten bekommen **beide** Tags — Buckets sind freie,
   überlappende Etiketten, ein Gemeinschaftskonto darf `Meins` und `Partner`
   zugleich tragen.
4. Öffne **Ansichten** (Seitenleiste, Bereich Administration — dieselbe
   Seite, die der **Verwalten…**-Link des Sicht-Umschalters öffnet). Tippe
   unter **2. Ansichten** `Mein Vermögen` in **Neue Ansicht** und klicke
   **Neu anlegen**.
5. Klicke auf der neuen Zeile **Ansichts-Buckets bearbeiten**. Hake im Dialog
   **Buckets für Mein Vermögen** den Bucket `Meins` unter **Buckets
   einbeziehen** an und drücke **Speichern**.
   <!-- screenshot: views-page-edit-view-buckets -->
6. Wiederhole das für eine zweite Ansicht `Haushalt`, die `Meins` **und**
   `Partner` einbezieht (oder hake einfach **Alle Buckets einbeziehen** an).
7. Öffne **Vermögen**, wähle `Mein Vermögen` im Umschalter **Ansicht:** oben
   auf der Seite und klicke **Als Standard festlegen** unter
   **Standard-Ansicht**. Vermögensseite und Übersicht öffnen jetzt mit der
   persönlichen Zahl; der Umschalter wechselt weiterhin jederzeit zu
   `Haushalt` oder zur eingebauten Ansicht **Alles**.
   <!-- screenshot: wealth-view-switcher-set-default -->

**Die Einmal-Zählung ist garantiert.** In der Summe einer Ansicht wird jedes
Konto genau einmal gezählt, egal wie viele der einbezogenen Buckets es trägt. Das mit
`Meins` und `Partner` markierte Gemeinschaftskonto erscheint in `Haushalt`
einmal, nicht doppelt. Teilen sich die Buckets einer Ansicht ein Konto, zeigt
die Vermögensseite ein Badge neben der Summe — *Überlappende Buckets – Konten
nur einmal gezählt* — als Erinnerung, dass die Werte je Bucket überlappende
Facetten sind und nicht summiert werden dürfen; die Summe selbst ist bereits
dedupliziert.

## Anwendungsfall 2: eine Strategie-Ansicht mit eigenem SOLL-Plan

Szenario: Eine Altersvorsorge-Strategie läuft über Depots bei mehreren
Brokern und braucht eine eigene Zielallokation samt Drift-Verfolgung —
unabhängig von allem anderen im Bestand.

1. Markiere auf **Konten & Depots** jedes Depot der Strategie mit einem neuen
   Tag `Altersvorsorge` (der **+**-Chip → **Neuer Tag** → **Tag anlegen**),
   egal bei welchem Broker es liegt.
2. Lege auf **Ansichten** eine Ansicht `Altersvorsorge` an, die den Bucket
   `Altersvorsorge` einbezieht (Schritte 4–5 oben).
3. Öffne **Klassifizierungen**, wähle den eigenen Baum, nach dem gesteuert
   wird, und gehe in den Bereich **Soll-Plan** seiner Detailansicht. Wähle im
   Selektor **Soll-Plan für Sicht:** die Ansicht `Altersvorsorge`.
4. Klicke **Plan anlegen** (oder **Aus anderer Sicht übernehmen…**, um einen
   bestehenden Plan vorzubefüllen), trage je Kategorie ein **Soll %** plus
   das **Cash**-Ziel ein, bring die **Σ**-Fußzeile auf 100 % ✓ und drücke
   **Plan speichern**. Pläne sind an die Sicht gebunden (ADR-0020):
   `Altersvorsorge` trägt jetzt einen eigenen Plan, andere Ansichten
   behalten ihre — oder keinen.
   <!-- screenshot: classifications-target-plan-for-view -->
5. Öffne **Vermögen** und wechsle zu `Altersvorsorge`. Die SOLL- und
   Drift-Spalten messen jetzt nur die Bestände der Strategie gegen den Plan
   der Strategie; die Drift-Beträge zeigen, was innerhalb der Strategie zu
   trimmen oder aufzustocken ist.

## Anwendungsfall 3: Umstieg von Portfolio Performance

In Portfolio Performance dienen Depots oder Portfolios oft als
Kategorien — ein „Portfolio" je Strategie, Arbeitgeber oder
Familienmitglied. Buckets und Ansichten ersetzen diese Gewohnheit, ohne die
Buchhaltung aufzuspalten.

- **Was die einmalige Migration angelegt hat.** Bei der Migration (ADR-0024)
  wurde aus jedem früheren Portfolio **ein Bucket und eine gleichnamige
  Ansicht**, sodass jede vorher sichtbare Zahl weiterhin eine
  Ansicht hat, die sie zeigt. Die Vermögensseite hat das einmalig mit einem
  schließbaren Hinweis samt Liste der angelegten Ansichten angekündigt.
  Benenne beides frei auf der Seite **Ansichten** um (**Bucket umbenennen** /
  **Ansicht umbenennen**) — die Namen wurden nur übernommen, nichts hängt an
  ihnen.
- **Leere Datenbank migriert, Daten erst danach eingespielt?** Die einmalige
  Migration konvertiert nur die Portfolios, die sie vorfindet. Nach einem
  Upgrade gegen eine leere Datenbank mit später wiederhergestellten Daten
  einmal `mix portfolixir.seed_scope_buckets`
  ausführen — das legt den fehlenden Scope-Bucket samt Ansicht je Portfolio an und
  ist gefahrlos wiederholbar (bereits migrierte Portfolios werden
  übersprungen).
- **Was Importe jetzt tun.** Die Import-Vorschau fragt nicht mehr nach einem
  Ziel-Portfolio. Stattdessen bietet sie einen bearbeitbaren Bucket-Tag an —
  *Die von diesem Import angelegten Konten erhalten den Bucket-Tag:* —
  vorbefüllt mit einem datierten `PP Import <Datum>`. Behalte ihn, um die
  importierten Konten später wiederzufinden, tippe den Namen eines
  bestehenden Buckets, um ihn wiederzuverwenden, oder hake *Kein Tag – die
  neuen Konten bleiben ohne Bucket* an, um das Markieren zu überspringen.
  <!-- screenshot: import-preview-bucket-tag -->
- **Wo die Portfoliodatensätze geblieben sind.** Portfolios existieren
  weiterhin als interne Kompatibilitätsdatensätze, tragen in der Oberfläche
  aber kein Verhalten mehr. Die Seite **Konten & Depots** listet sie im
  eingeklappten, schreibgeschützten Panel **Portfoliodatensätze
  (Kompatibilität)**; ein Anlegen oder Bearbeiten in der Oberfläche gibt es
  nicht mehr.

Die PP-Gewohnheit „ein Depot je Kategorie" übersetzt sich also so: Lass die
Depots die buchhalterische Realität bleiben, zu der die Brokerauszüge
passen, und stecke die Kategorien in Bucket-Tags — ein Konto kann mehrere
tragen, was Depot-als-Kategorie nie konnte.

## Anwendungsfall 4: mitzählen, aber nicht steuern

Szenario: Bitcoin als langfristiger Wertspeicher gehalten. Er gehört ins
Gesamtvermögen, soll aber die Zielallokation der Strategie nicht
verzerren — der Auslöser von ADR-0018 (siehe
[ADR-0018](/decisions/0018-buckets-tag-based-wealth-scoping.html), englisch).

1. Markiere auf **Konten & Depots** das Depot (oder Konto) mit der Position
   mit einem neuen Tag, z. B. `Wertspeicher`.
2. Klicke auf **Ansichten** bei der Strategie-Ansicht **Ansichts-Buckets
   bearbeiten** und hake `Wertspeicher` unter **Buckets ausschließen** an.
   Ausschluss gewinnt immer: Selbst wenn das Konto auch einen einbezogenen
   Bucket trägt, bleibt es draußen. Drücke **Speichern**.
3. Prüfe das Ergebnis auf **Vermögen**: Unter der eingebauten Ansicht
   **Alles** zählt die Position wie bisher zur Gesamtsumme; unter der
   Strategie-Ansicht verschwindet sie aus der 100-%-Basis und der
   Drift-Tabelle, sodass die IST-Gewichte aller anderen Kategorien nur noch
   am gesteuerten Mix gemessen werden.

Nichts wird versteckt und nichts je Wertpapier geflaggt — dieselbe Position
liegt einfach innerhalb der einen Ansicht und außerhalb der anderen.

## Ehrlichkeitshinweis: Umtaggen schreibt die Historie um

Eine Ansicht löst ihre Buckets **per heute** auf. Wird ein Konto
umgetaggt, wird die gesamte historische Reihe der Ansicht mit der neuen
Zugehörigkeit neu berechnet — es gibt kein „getaggt seit"-Datum. Deshalb
tragen Ansicht-bezogene Performance-Reihen das Label *Zusammensetzung per
heute*: Das Chart beantwortet „Wie hätte sich diese Ansicht mit ihrer
heutigen Zusammensetzung entwickelt?", nicht „Was habe ich letztes Jahr
gesehen?". Bucket-Änderungen stehen im Audit-Journal; wann sich eine
Zugehörigkeit geändert hat, bleibt also nachvollziehbar — aber historische
Ansichtswerte bewegen sich, wenn Buckets umsortiert werden.
