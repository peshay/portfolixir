---
layout: docs
title: Eigene Regeln – Leitfaden
description: Eigene Obergrenzen, Untergrenzen und Bänder auf der Risiko-Seite anlegen, ändern und lesen.
lang: de
lang_en: /guides/own-rules.html
lang_de: /de/guides/own-rules.html
---

# Eigene Regeln – Leitfaden

Eine **eigene Regel** hält eine Grenze fest, an die sich das Portfolio halten
soll — „kein einzelnes Wertpapier über 10 %“, „Cash nie unter 5 %“, „Anleihen
innerhalb von 3 Prozentpunkten ihres Ziels“ —, damit sie bei jedem Lesen der
Risiko-Seite geprüft wird, statt im Kopf oder im Prompt eines Agenten zu
stehen, wo Grenzen verrutschen. Der Abschnitt **Eigene Regeln** oben auf
**Vermögen → Risiko** listet die Regeln der aktiven Ansicht mit dem, was jede
feststellt. Dieser Leitfaden geht durch, wie man eine Regel anlegt, ihren
Befund liest, sie ändert und beendet, mit den Bezeichnungen des Bildschirms.
Die Entscheidung hinter dem Modell steht in
[ADR-0049](/decisions/0049-policy-rules-as-first-class-objects.html)
(englisch); die Referenzbeschreibung der Risiko-Seite liefert die
[Produktdokumentation](/de/product-documentation.html#risiko-konzentration-und-schwankung),
und dieselben Regeln, wie dein Agent sie liest und schreibt, beschreibt
[API und MCP](/de/integration/api-and-mcp.html#eigene-regeln-adr-0049).

Alle Namen und Zahlen unten sind Beispiele.

## Was eine Regel ist

Eine Regel liest **eine Zahl**, die die App ohnehin zeigt, für eine Sache, und
zieht eine Grenze dagegen. Sie hat eine von drei Arten:

- **Obergrenze** — verletzt, wenn die Zahl echt darüber liegt. „Kein
  einzelnes Wertpapier über 10 %“ ist eine Obergrenze bei 10.
- **Untergrenze** — verletzt, wenn die Zahl echt darunter liegt. „Cash nie
  unter 5 %“ ist eine Untergrenze bei 5.
- **Band** — verletzt, wenn die Zahl außerhalb des Bereichs von **Von** bis
  **Bis** liegt. „Anleihen innerhalb von ±3 Prozentpunkten ihres Ziels“ ist
  ein Band von -3 bis 3 auf der Drift.

„Echt“ zählt: Eine Zahl genau auf der Grenze liegt innerhalb, so wie auch die
allgemeinen Schwellen weiter unten auf der Risiko-Seite eine Grenze lesen.

Eine Regel gehört zu der **Ansicht, in der sie angelegt wurde**. Sie wird auf
der steuerbaren Basis dieser Ansicht ausgewertet, und „Risiko“ listet sie nur,
solange diese Ansicht aktiv ist. Eine unter **Alles** angelegte Regel gilt
portfolioweit.

## Welche Zahlen eine Regel lesen kann

Eine Regel rechnet nichts selbst: Jede Zahl ist eine, die die App ohnehin an
anderer Stelle liefert, gelesen in der Ansicht der Regel.

| Kennzahl | Bezug | Die Grenze wird eingegeben als |
|---|---|---|
| **Gewicht** | ein Wertpapier, eine Kategorie, Cash oder eine Ansicht | Prozent der steuerbaren Basis der Ansicht, 0 bis 100 |
| **Drift** | eine Kategorie oder ein Wertpapier | Prozentpunkte, Ist minus Ziel im aktiven Plan der Ansicht, -100 bis 100 |
| **Klumpenrisiko (HHI)** | **Gesamte Basis** | 0 bis 10.000 |
| **Volatilität** | **Gesamte Basis**, mit einem **Fenster** von 30, 90 oder 365 Tagen | Prozent, annualisiert, 0 oder mehr |
| **Maximaler Drawdown** | **Gesamte Basis**, mit einem **Fenster** | Prozent als die negative Zahl, die er ist, -100 bis 0 |

- **Der Bezug folgt der Kennzahl.** Die Liste **Bezug** bietet nur an, wofür
  die gewählte Kennzahl gelesen werden kann; der Dialog kann also kein Paar
  speichern, zu dem es keine Zahl gibt.
- **Das Gewicht eines Wertpapiers** ist sein Einzeltitel-Gewicht,
  zusammengefasst über alle Depots — die Zahl, die die Tabelle *Größte
  Einzelpositionen* zeigt.
- **Die Drift eines Wertpapiers** braucht eine weitere Wahl, **Plan der
  Klassifizierung**: Ein Positionsziel steht im Plan einer Klassifizierung,
  und die Drift ist erst eine Zahl, wenn der Plan benannt ist.
- **Ein Bucket wird über eine Ansicht begrenzt.** „Der spekulative Bucket
  bleibt unter 5 % von allem“ ist eine **Gewicht**-Obergrenze, deren Bezug die
  Ansicht ist, die diesen Bucket auswählt, angelegt, während **Alles** die
  aktive Ansicht ist.
- **Ein Drawdown ist negativ** („-12,0 %“). „Nie mehr als 20 % im Minus“ ist
  deshalb eine **Untergrenze** bei -20. Eine positive Grenze wird abgelehnt,
  weil ein Drawdown nie über 0 steigt.

## Eine Regel anlegen

1. Öffne **Vermögen → Risiko**. Der Seitenkopf nennt die aktive Ansicht
   („Konzentration und Schwankung · Ansicht: Alles“). Die neue Regel gehört zu
   dieser Ansicht. Für eine Regel in einer anderen Ansicht wähle diese zuerst
   im Sicht-Umschalter auf **Vermögen → Bestände**; die Wahl gilt auf jedem
   Vermögens-Reiter.
2. Klicke **Regel anlegen**. Die erste Zeile des Dialogs nennt die Ansicht
   noch einmal: *Ausgewertet in der Ansicht „Alles“, auf ihrer steuerbaren
   Basis.*
3. Trage unter **Name** ein, wie du die Regel nennst, zum Beispiel
   `Einzeltitel höchstens 10 %`. Der Name ist nur eine Bezeichnung: Er wird
   nie inhaltlich gelesen, und zwei Regeln dürfen denselben tragen.
4. Wähle die **Kennzahl**, dann den **Bezug** und bei einer Volatilität oder
   einem Drawdown das **Fenster**.
5. Wähle die **Art**. Gib die **Grenze** in der Einheit ein, die ihre
   Bezeichnung nennt („Grenze (%)“, „Grenze (Pp)“) — bei einem Band **Von**
   und **Bis** —, so geschrieben, wie die Seite Zahlen schreibt („7,5“).
6. Wähle den **Schweregrad**: **Warnung** oder **hart**.
7. **Gilt ab** steht auf heute. Ein späteres Datum plant die Regel; ein
   früheres wird abgelehnt, denn eine Regel wird nie auf eine Vergangenheit
   angewandt, in der es sie nicht gab.
8. Ergänze bei Bedarf eine Notiz und klicke **Regel speichern**.

<!-- screenshot: risk-own-rules-new-rule-dialog -->

Ein durchgerechnetes Beispiel: eine Regel `Anleihen nahe am Ziel` mit
**Kennzahl** Drift, **Bezug** die Kategorie *Anleihen* im Baum
*Anlageklasse*, **Art** Band, **Von** -3 und **Bis** 3, **Schweregrad**
Warnung. Sie bleibt eingehalten, solange die Anleihen-Kategorie höchstens drei
Prozentpunkte von ihrem Ziel im aktiven Plan entfernt liegt, und ist nicht
bestimmbar, solange die Ansicht keinen aktiven Plan hat.

## Die Befunde lesen

Jede geltende Regel wird bei jedem Lesen von „Risiko“ ausgewertet; ein Befund
wird nie gespeichert und nirgendwohin geschickt. Die Überschrift des
Abschnitts zählt sie („· 1 verletzt · 1 nicht bestimmbar · 3 eingehalten“),
und die Tabelle hat eine Zeile je Regel: die **Regel** (ihr Name, darunter
ihre Wortzeile — Kennzahl, Fenster, Bezug, Art und Schweregrad), die
**Gemessen**-Zahl, die **Grenze** und den **Stand**. Verletzte Zeilen kommen
zuerst, dann nicht bestimmbare, dann eingehaltene; innerhalb jeder Gruppe hart
vor Warnung.

- **eingehalten** — die Zahl wurde gelesen und liegt auf der richtigen Seite
  der Grenze.
- **verletzt** — die Zahl wurde gelesen und liegt echt jenseits der Grenze.
  Das Badge trägt den vorzeichenbehafteten Abstand zur nächsten Grenze
  („verletzt · +2,4 Pp“). Das ist Arithmetik, keine Anweisung.
- **nicht bestimmbar** — die Zahl ließ sich nicht lesen. Das Badge ist
  gestrichelt, und der Grund steht darunter: „12 von 20 Beobachtungen“ bei
  einer Volatilität ohne genug Historie, „kein aktiver Plan“ oder „kein Ziel
  im Plan“ bei einer Drift ohne Ziel, „nichts zu gewichten“ bei einer leeren
  Ansicht, „gehalten, aber nicht bewertbar“ bei einer Position ohne nutzbaren
  Kurs oder Wechselkurs, „der Bezug existiert nicht mehr“, „die Zahl ist nicht
  definiert“ oder „nicht gemessen“.

Eine Regel, die erst später beginnt, steht bis dahin unter **Geplante Regeln**
mit ihrem Beginn und ihrer Grenze. Eine geplante Änderung einer geltenden
Regel zeigt sich in deren Zeile („Ab 01.06.2026: Grenze 8,0 %“).

<!-- screenshot: risk-own-rules-findings -->

### Warum „nicht bestimmbar“ nie eingehalten ist

Eine Regel, deren Zahl fehlt, hat nichts geprüft. Zählte sie als eingehalten,
stünde ein Regelwerk genau dann auf Grün, wenn die Hälfte seiner Eingaben
fehlt — dasselbe stille Verrutschen, das die Regeln ersetzen sollen, mit einem
Haken daran. Ein nicht bestimmbarer Befund wird deshalb nie als eingehalten
gezählt, nie ausgeblendet und nennt immer seinen Grund. Ein Wertpapier, das du
nicht hältst, ist ein anderer Fall: Sein Gewicht ist 0, und das *ist* eine
Lesung; eine Untergrenze darauf kann also verletzt sein. Nicht bestimmbar ist
nur ein Bezug, den es nicht mehr gibt.

### Was der Schweregrad tut — und was ein Befund nicht tut

Der **Schweregrad** ändert, wie eine Verletzung aussieht und wo sie einsortiert
wird: Eine harte Verletzung trägt die Gefahrenfarbe, eine Warnung die
Warnfarbe. Sonst hängt nichts daran. Keine Regel blockiert eine Buchung, einen
Import oder eine andere Änderung, und kein Befund sagt, was zu tun ist: Er
trägt keine Stückzahl, keinen Trade und keinen Vorschlag. Was eine Verletzung
bedeutet, entscheidest du.

Der Abschnitt *Größte Einzelpositionen* darunter heißt „allgemeine Schwellen,
keine eigenen Regeln“. Seine Grenzen (eine Einzelaktie über 10 %, 7 % als
erste Linie, ein ETF über 25 %) sind die allgemeine Heuristik der App. Deine
Regeln ändern sie nicht, und sie lesen deine Regeln nicht: Eine Position kann
zugleich eine verletzte Regel von dir und ein allgemeines „über 10 %“ tragen,
als zwei getrennte Aussagen.

## Eine Regel ändern: eine neue Version ab einem Datum

Der Name einer Regel in der Tabelle ist ein Link. Er öffnet den Dialog
*Regel ändern — „…“*, den einen Ort, an dem eine Regel geändert wird. Eine Änderung
überschreibt nie: Speichern legt **eine neue Version** ab dem Datum in **Gilt
ab** an, und der Dialog sagt das vor dem Speichern — „Speichern legt Version 2
an. Version 1 (10,0 %) gilt seit 01.03.2026, endet am Tag vor der neuen und
bleibt lesbar.“ Der Knopf heißt **Neue Version speichern**. Unter den Feldern
listet **Versionen** jede Version der Regel mit ihrem Zeitraum, ihrer Grenze,
ihrem Schweregrad und wer sie geschrieben hat.

- Die neue Version beginnt standardmäßig heute, oder morgen, wenn die
  geltende Version erst heute begonnen hat: Eine Version, die begonnen hat,
  ist der Maßstab dieses Tages und behält ihn. Ein späteres Datum plant die
  Änderung.
- Eine Version, die gegolten hat, wird nie geändert und nie gelöscht; ihr
  Zeitraum endet am Tag, bevor ihre Nachfolgerin beginnt. Eine Version, die
  noch nicht begonnen hat, lässt sich noch ändern: Der Dialog öffnet sich auf
  ihr, und Speichern ersetzt sie.
- Die Frage „Was war meine Grenze im März?“ hat also eine Antwort, die man
  lesen kann: Die Versionsliste zeigt, welche Grenze an welchen Tagen galt.

## Umbenennen: keine neue Version

Der Name ist die Bezeichnung der Regel, nicht Teil ihres Maßstabs. Änderst du
nur das Feld **Name**, sagt der Dialog „Nur der Name ändert sich: Speichern legt
keine neue Version an. …“, und der Knopf heißt **Namen speichern**. Beim
Umbenennen entsteht keine Version: Der neue Name gilt für die Regel mit allen
Versionen, und das Audit-Journal behält den bisherigen Namen. Änderst du Name
und Grenze zusammen, bekommt der Versionshinweis die Zeile „Der neue Name gilt
für die Regel mit allen Versionen.“; ein Speichern schreibt beides oder nichts.
Eine beendete Regel wird genauso umbenannt.

## Eine Regel beenden

- **Regel beenden** (im Dialog, mit Rückfrage) beendet die Regel: Sie wird ab
  heute nicht mehr ausgewertet, und eine Version, die erst heute begonnen hat,
  endet heute Abend. Eine geplante Änderung entfällt mit. Die Regel und alle
  ihre Versionen bleiben unter **Beendete Regeln anzeigen** lesbar, und eine
  beendete Regel öffnet denselben Dialog. Eine dort gespeicherte neue Version
  nimmt die Regel ab dem Datum dieser Version wieder auf.
- **Regel löschen** steht statt **Regel beenden** da, solange keine Version der
  Regel gegolten hat — etwa bei einer Regel, die erst später beginnt. An ihr
  wurde nie gemessen, also muss von ihr nichts bleiben.

## Was eine Regel schützt

Ein Wertpapier, eine Kategorie, eine Klassifizierung oder eine Ansicht, die
eine Regel liest, lässt sich nicht löschen, solange die Regel existiert. Die
Ablehnung — im Meldungsband der Seiten Ansichten und Klassifizierungen, im
Dialog **Kann nicht gelöscht werden** auf der Wertpapierseite — nennt jede
Regel mit Stand und Ansicht, etwa „Einzeltitel höchstens 10 %“ (gilt,
Ansicht „Alles“), und jeder Name führt auf „Risiko“ in der Ansicht, in der die
Regel gilt. Der Link macht diese Ansicht auf jedem Vermögens-Reiter zur
aktiven, so wie die Wahl im Sicht-Umschalter.

Eine Regel zu beenden stoppt ihre Auswertung, gibt das Objekt aber nicht frei:
Eine Version, die gegolten hat, behält ihren Bezug als Beleg dafür, was der
Maßstab war. Nur das Löschen einer Regel, die nie gegolten hat, gibt es frei.
Ein Wertpapier, das eine Regel liest, lässt sich weiterhin stilllegen, aber
nicht in ein anderes Wertpapier zusammenführen.

## Die Regeln deines Agenten

Dein Agent schreibt Regeln über die API oder MCP mit seinem Token, und es sind
dieselben Regeln, die du auf dieser Seite schreibst. Sie gelten wie deine;
nichts wartet auf deine Zustimmung. Was sie unterscheidet, ist ein Wort: Eine
Regel, deren geltende Version der Agent geschrieben hat, endet ihre Wortzeile
mit „· Agent“, ebenso geplante und beendete Regeln, deren Version vom Agenten
stammt. Im Dialog nennt jeder Eintrag unter **Versionen** seinen Autor,
**Operator** oder **Agent**. Deine eigenen Regeln tragen kein Wort; eine Seite
ohne Regeln des Agenten liest sich also wie zuvor. Das Audit-Journal nennt das
Token, das jede Version geschrieben hat.

Eine Regel des Agenten wird wie jede andere geändert, umbenannt und beendet.
Eine Version, die du auf dieser Seite speicherst, ist deine, und das Wort folgt
der geltenden Version, nicht dem Namen: Umbenennen verschiebt kein Wort.

## Was Regeln nicht tun

- **Nichts wird zugestellt.** Ein Befund existiert, während er gelesen wird:
  auf dieser Seite oder wenn dein Agent die verletzten Befunde liest. Es gibt
  keine Benachrichtigung und keine Mail.
- **Kein Blick zurück.** Eine Regel wird nur für heute ausgewertet und nie für
  einen Tag vor dem **Gilt ab** ihrer Version — eine Regel an einer
  Vergangenheit zu prüfen, in der es sie nicht gab, wäre ein Backtest, und den
  macht Portfolixir nicht.
- **Keine Beratung.** Eine Regel ist dein Maßstab, ausgewertet; sie schlägt
  nie einen Trade, eine Größe oder eine Order vor.
