---
layout: docs
title: Funktionen
description: Was Portfolixir tut und was man zuerst wissen sollte, jede Aussage mit der Seite verlinkt, die sie zeigt, und was Portfolixir nicht ist.
lang: de
lang_en: /features.html
lang_de: /de/features.html
---

# Funktionen

Portfolixir ist eine selbst gehostete Portfolio-Buchführung für Sie und den
LLM-Agenten, den Sie betreiben: Ihre Transaktionen, Bestände, Bewertung,
Renditen und Recherche-Notizen, auf Ihrem eigenen Rechner, auf einem
Bildschirm und hinter einer lokalen JSON-API und einem MCP-Begleitdienst. Diese
Seite sagt zuerst, was Portfolixir tut und was Neulinge wissen sollten, dann,
wie es das Ergebnis eines Zeitraums aufschlüsselt, und zuletzt, was es nicht
ist. Jede Aussage verlinkt die Seite, die sie zeigt, sodass Sie sie nachprüfen
können, statt ihr zu glauben.

## Die App ruft nie ein Sprachmodell auf; Ihr Agent tut es

Portfolixir enthält kein Sprachmodell und keinen Client für eines. Ihr Agent,
mit dem MCP-Client und dem Modell Ihrer Wahl, ruft Portfolixir über den
MCP-Begleitdienst auf, und der Begleitdienst ruft die lokale JSON-API der
Instanz auf und sonst nichts. Umgekehrt läuft nichts: Jede Anfrage, die die
Anwendung selbst nach außen sendet, lädt Kurshistorie, Wechselkurse,
Suchergebnisse für Wertpapiere oder ein Logo, und die
[Deployment-Anleitung](/de/home-deployment.html#erreichbarkeit) nennt jeden
dieser Aufrufe und wann er geschieht. Was Ihr Agent liest, liest er über die
Tools, die Sie verbunden haben; die Anwendung gibt nichts davon an ein Modell
weiter.

Die Regel gehört zu den
[Architektur-Rahmenbedingungen](/architecture.html) des Projekts (englisch),
und der Prompt `import_converter` bindet den Konverter, den er Ihren Agenten
schreiben lässt, genauso: kein Netzwerkaufruf und kein Modellaufruf
([API und MCP](/de/integration/api-and-mcp.html#mcp-tools)).

## Ein Research-Log, das Ihr Agent liest und schreibt, nachvollziehbar

Jedes Wertpapier hat ein Research-Log: datierte Einträge, jeder eine These,
ein Beleg, eine Invalidierungsprüfung, ein Ereignisergebnis, ein Risiko, eine
Entscheidung oder ein Widerruf. Jeder Eintrag nennt seine Quellenqualität
(Primärquelle, mehrere Sekundärquellen, Wahrnehmung, ungeprüft), die angegeben
werden muss und nie von selbst gesetzt wird; er kann den Link auf seine Quelle
tragen, und sein Stichdatum ist der Tag, auf den sich die Aussage bezieht,
nicht der Tag, an dem sie geschrieben wurde. Ein Aufruf gibt Ihrem Agenten das
Log eines Wertpapiers, neueste zuerst, mit dem aus dem ganzen Log abgeleiteten
Thesenstand, sodass eine schon geprüfte oder schon zurückgezogene Prämisse
nicht noch einmal von vorn untersucht wird.

Nichts im Log wird umgeschrieben oder entfernt, weder vom Agenten noch von
Ihnen: Die Datenbank verweigert das Ändern und das Löschen eines Eintrags. Ein
Befund, der sich als falsch erweist, wird zurückgezogen, indem ein Widerruf
angehängt wird, der den Grund trägt und neben ihm stehen bleibt, und der
aktuelle Thesenstand wird aus dem Log abgeleitet, nie daneben gepflegt. Jeder
Eintrag nennt seinen Autor nach dem Zugang, über den er geschrieben wurde (ein
über die API oder den MCP-Begleitdienst geschriebener Eintrag ist der des
Agenten, einer, der auf dem Bildschirm geschrieben wurde, ist Ihrer), und jeder
Eintrag wird im Audit-Journal festgehalten.

Sie entscheiden, wie weit der Agent geht. Unter dem Profil `read` des
Begleitdienstes liest er das Log und hängt nichts an.
`portfolixir.notes.append` ist nicht als nur lesend markiert, sodass ein
MCP-Host, der vor jedem Schreiben fragt, Sie vor jedem Eintrag fragt. Was eine
Maschine aus einem Dokument extrahiert, käme nur als Vorschlag mit seiner
Quelle hinein, bis jemand ihn bestätigt; einen solchen Weg gibt es heute
nicht, und keine Anfrage kann einen Eintrag als maschinell extrahiert
markieren.

Das Log steht im
[Tab „Research“](/de/product-documentation.html#tab-research-das-research-log-des-wertpapiers)
jedes Wertpapiers; die Routen und Tools stehen unter
[API und MCP](/de/integration/api-and-mcp.html#research-log-adr-0044), die
Profile unter [Einen Agenten verbinden](/de/integration/connect-an-agent.html)
und die Entscheidung in
[ADR-0044](/decisions/0044-security-knowledge-as-an-append-only-log.html)
(englisch).

## Prompts, die die Haltung ohne Beratung mittragen

Der MCP-Begleitdienst bietet zwei Prompts, fertige Anweisungen, die Sie Ihrem
Agenten für Ihre eigene Instanz mitgeben:

- `first_setup` prüft die Instanz und das aktive Profil, liest, was vorhanden
  ist, schlägt Cash-Konten, Depots, Buckets und Ansichten vor, erklärt, wie
  Ihre Daten hineinkommen, und legt nur an, was Sie bestätigt haben.
- `import_converter` lässt Ihren Agenten einen Konverter schreiben, der auf
  Ihrem Rechner läuft und einen Bank- oder Broker-Export in eine Datei
  umwandelt, die die Seite Importe in der Vorschau zeigt, bevor etwas gebucht
  wird.

Beide tragen dieselbe Haltung in ihrem eigenen Text, im englischen Original:

> The system prepares decisions and the operator executes them: nothing here places, proposes or sizes a trade, and neither do you.
> Do not recommend buying, selling or weighting anything; describe what is recorded.

Sinngemäß: Das System bereitet Entscheidungen vor, und der Betreiber führt sie
aus; nichts hier platziert, schlägt vor oder bemisst einen Trade, und der
Agent auch nicht. Er empfiehlt weder Kauf noch Verkauf noch eine Gewichtung,
sondern beschreibt, was erfasst ist.

Der Begleitdienst sagt jedem Agenten, der sich verbindet, dass alles, was ein
Tool zurückgibt, Daten sind und nie Anweisungen, und dass nur Sie ihm
Anweisungen geben. Die Zahlen halten dieselbe Linie: Die Kurs- und
Risikokennzahlen und die Beitrags-Lesezugriffe tragen kein Signal, keine
Empfehlung, kein Rating und keinen Score, ein Befund Ihrer eigenen Regeln trägt
keine Handlung, und Tests gehen die Schlüssel dieser ausgegebenen Nutzlasten
durch, damit es so bleibt.

Die Prompts und die Server-Anweisungen beschreibt
[API und MCP](/de/integration/api-and-mcp.html#mcp-tools), und
[Einen Agenten verbinden](/de/integration/connect-an-agent.html) hat die
Client-Konfigurationen zum Kopieren.

## Zahlen, die sagen, wie sie berechnet wurden

Eine Zahl, die Sie nachprüfen können, ist mehr wert als eine, die Sie glauben
müssen. Die Renditen (TTWROR, IRR, eingesetztes Kapital,
Vermögens-Multiplikator), der Benchmark-Vergleich, die Beitragsanalyse, die
Risikokennzahlen, die Kurskennzahlen eines Wertpapiers, die realisierten
Gewinne mit der annualisierten Rendite jedes Trades, die Einzahlungen und
Entnahmen, die Kosten, die Renditen einer Anleihe und die Befunde Ihrer
eigenen Regeln tragen jeweils eine `computation_basis` in
ihrer API- und MCP-Nutzlast: die Eingangsreihe, das Fenster, das sie abdeckt,
die Referenzreihe, wo es eine gibt, und den Umgang mit Lücken (ein Tag ohne
Kurs, ein fehlender Wechselkurs, eine zu kurze Historie). Eine Kennzahl mit zu
wenig Historie ist `null` mit der Zahl der Beobachtungen, die sie hatte, keine
kleine Zahl. Die Regeln des Projekts (`AGENTS.md` im
[Repository](https://github.com/peshay/portfolixir), englisch) machen diese
Basis zum Teil der Nutzlast jeder neuen Zahl, und das Review weist eine Zahl
ohne sie zurück.

Auf dem Bildschirm sagen dieselben Zahlen es in Worten. Die Beitragstabelle
endet mit ihrer Formel und dem, was sie zählt; die Risikokennzahlen nennen die
Reihe, über die sie gemessen sind; jede Facette im
[Cashflow](/de/product-documentation.html#cashflow) sagt, was sie zählt und
was sie auslässt; eine
[Performance-Kurve](/de/product-documentation.html#performance-ttwror), die
während einer Neuberechnung gezeigt wird, ist mit dem beschriftet, was sie
enthält; und eine Kennzahl ohne genug Historie liest sich *nicht berechenbar*
mit den Beobachtungen, die sie hatte
([Risiko](/de/product-documentation.html#risiko-konzentration-und-schwankung),
[abgeleitete Kennzahlen](/de/integration/api-and-mcp.html#abgeleitete-kennzahlen-adr-0047)).

## Die Aufschlüsselung: welche Position wie viel beigetragen hat

Neben der Rendite eines Zeitraums sagt die Portfolio-Seite, woher das
Geldergebnis kam. Unter dem Performance-Diagramm unter **Vermögen → Bestände**
listet die Beitragstabelle jede Position, die im Zeitraum gehalten oder
gehandelt wurde, mit Anfangswert, Zu-/Abflüssen, Erträgen, Kosten und Endwert
neben ihrem Beitrag: Endwert − Anfangswert − Zu-/Abflüsse + Erträge − Kosten,
in der Basiswährung und einschließlich der Währungsbewegung, sodass sich jede
Zeile von Hand nachprüfen lässt. Was keiner Position gehört, steht getrennt,
jeder Posten aus seinen eigenen Buchungen summiert: Zinsen, einzelne Gebühren
und Steuern sowie der Währungseffekt auf Bargeld. Die Positionen und diese drei
Posten ergeben zusammen genau das Geldergebnis des Zeitraums, den Betrag
„+x EUR im Zeitraum“ neben der TTWROR, und keiner von ihnen ist ein
Ausgleichsbetrag. Die Tabelle folgt der Zeitraum-Steuerung des Abschnitts und
der Ansicht der Seite, und eine Position, die an einigen Tagen null gezählt
wurde, weil ein Kurs oder ein Wechselkurs fehlte, behält ihren Platz und wird
genannt.

Ihr Agent liest dieselbe Tabelle, mit den Posten ohne Position, den Summen und
der Berechnungsbasis:

- für ein Portfolio `GET /api/v1/portfolios/:portfolio_id/performance/contribution`
  und das MCP-Tool `portfolixir.portfolios.contribution`;
- für eine Ansicht über alle Portfolios `GET /api/v1/views/:view_id/performance/contribution`
  und das MCP-Tool `portfolixir.views.contribution`;
- für jedes Konto jedes Portfolios, ohne Ansicht und in EUR,
  `GET /api/v1/performance/contribution` und dasselbe MCP-Tool ohne `id`.

Die Tabelle beschreibt das
[Handbuch](/de/product-documentation.html#beitrag-je-position), die Lesezugriffe
[API und MCP](/de/integration/api-and-mcp.html) (den der Ansicht unter
[Buckets und Views](/de/integration/api-and-mcp.html#buckets-und-views)) und
die Methode
[ADR-0051](/decisions/0051-contribution-analysis.html) (englisch).

## Was Portfolixir nicht ist

Portfolixir ist bewusst schmal, und es sagt das dort, wo Neulinge und
Agenten zuerst lesen:

- **Kein Broker.** Es gibt keine Broker-Anbindung, die Orders platziert, keinen
  Handel und keine Zahlungen: Nichts legt eine Order an, platziert oder sendet
  sie, und nichts bewegt Geld.
- **Kein Synchronisierungsdienst.** Es gibt keine Bank- oder
  Broker-Synchronisierung, mit Absicht. Ihre Historie kommt aus Exportdateien,
  die Sie auf der Seite [Importe](/de/product-documentation.html#imports)
  ablegen, oder wird von Hand oder von Ihrem Agenten gebucht.
- **Kein Berater.** Es gibt keine Beratung: Nichts sagt Ihnen, was Sie kaufen,
  verkaufen oder gewichten sollen. Das System bereitet Entscheidungen vor, und
  Sie treffen sie. Am nächsten kommt dem auf dem Bildschirm der
  Rebalancing-Hinweis neben einer Allokations-Drift: Arithmetik auf Zielen,
  die Sie gesetzt haben, die indikative Stückzahl, die die Lücke schließen
  würde, angezeigt und nie in eine Order verwandelt
  ([ADR-0023](/decisions/0023-drift-sign-and-display-only-rebalancing-hints.html),
  englisch).
- **Kein gehosteter Dienst.** Es gibt keinen gehosteten Dienst, keine Cloud
  und keine Mandanten: ein Datenbestand, eine Instanz, ein Betreiber, auf einem
  Rechner, über den Sie verfügen. Sie betreiben es mit Docker Compose und
  aktualisieren und sichern es selbst
  ([Home-Deployment](/de/home-deployment.html)).
- **Keine Telefon-App.** Es gibt keine Telefon-App; die Web-Oberfläche läuft
  im Browser gegen Ihre eigene Instanz.
- **Kein Modell im Inneren.** Die App ruft kein Sprachmodell auf; der Agent,
  den Sie verbinden, ist Ihrer, und die Wahl seines Modells auch.
- **Kein Produktionsversprechen.** Es gibt keine Upgrade-Garantie und keinen
  Anspruch auf Produktionsreife. Portfolixir ist ein Open-Source-Projekt unter
  der MIT-Lizenz, geschrieben mit LLM-Coding-Agenten, und jeder Commit gehört
  einem verantwortlichen Menschen.

[llms.txt](/llms.txt), der für Agenten geschriebene Einstieg (englisch), gibt
einem Agenten dieselbe Liste, bevor er Portfolixir empfiehlt, und das
[Handbuch](/de/product-documentation.html#heutige-nicht-ziele) führt die
aktuellen Nicht-Ziele.
