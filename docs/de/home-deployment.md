---
layout: docs
title: Home-Deployment
description: Lokales Docker-Compose-Setup, um Portfolixir zu Hause zu betreiben.
lang: de
lang_en: /home-deployment.html
lang_de: /de/home-deployment.html
---

# Home-Deployment

Portfolixir ist eine lokale, selbst gehostete Anwendung. Für einen kleinen
Betrieb zu Hause baust du das Produktions-Release mit Docker Compose und
stellst deinen eigenen Reverse-Proxy davor. Die Compose-Datei veröffentlicht
die Anwendung und den MCP-Begleitdienst nur auf der Loopback-Schnittstelle
des Hosts und die Datenbank nie.

## Voraussetzungen

- Docker und Docker Compose;
- ein Checkout dieses Repositories;
- eine `.env`-Datei mit den Geheimnissen (siehe unten);
- keine echten Portfolio-, Bank-, Broker-, Wallet- oder Abrechnungsdaten in
  Fixtures.

## Geheimnisse und Einstellungen

Kopiere `.env.example` nach `.env`. Der Stack startet nicht, solange ein
Geheimnis fehlt, die Anwendung und der MCP-Begleitdienst verweigern den Start
mit einem Token, das kürzer als 32 Bytes oder ein Platzhalter ist, und die
Anwendung verweigert einen `SECRET_KEY_BASE`, der kürzer als 64 Bytes, ein
Platzhalter oder ein in diesem Repository veröffentlichter Wert ist. Erzeuge jedes Token und `SECRET_KEY_BASE` mit
`openssl rand -base64 48` und `POSTGRES_PASSWORD` mit `openssl rand -hex 32`:
die Compose-Datei setzt es in die Datenbank-URL ein, wo ein `/` oder `#` aus
Base64 die Verbindungszeichenkette zerlegen würde.

| Variable | Pflicht | Wirkung |
|---|---|---|
| `SECRET_KEY_BASE` | ja | Signiert das Sitzungs-Cookie; die Signatur-Salze werden daraus abgeleitet. |
| `POSTGRES_PASSWORD` | ja | Das Datenbankpasswort; die Anwendung baut ihre Verbindungszeichenkette daraus. |
| `PORTFOLIXIR_API_TOKEN` | ja | Das Bearer-Token der JSON-API und der Upstream-Aufrufe des MCP-Begleitdienstes. |
| `PORTFOLIXIR_MCP_TOKEN` | ja | Das Bearer-Token, das ein MCP-Client dem Begleitdienst vorlegt. |
| `PORTFOLIXIR_UI_PASSWORD` | nein | Gesetzt verlangt die Web-Oberfläche eine Anmeldung (ADR-0045). Ungesetzt ist die Oberfläche offen — vertretbar nur hinter einer Authentifizierung des Reverse-Proxys. Eine Änderung beendet jede Anmeldung, die mit dem alten Passwort erfolgt ist. |
| `PORTFOLIXIR_SESSION_DAYS` | nein | Wie viele Tage eine Anmeldung gilt (Standard 30). Das Fenster wandert: die Nutzung der Instanz verlängert es, gefragt wird also erst nach einer vollen Periode ohne Nutzung. `0` beendet die Anmeldung mit dem Schließen des Browsers. |
| `PHX_HOST` | nein | Der Name, unter dem der Reverse-Proxy ausliefert (Standard `localhost`). Anfragen unter einem anderen `Host` werden mit 421 abgewiesen. |
| `PORTFOLIXIR_ALLOWED_HOSTS` | nein | Weitere Namen, kommagetrennt (eine LAN-Adresse, ein zweiter Proxy-Name). Die Compose-Datei ergänzt `app`, den Namen, unter dem der MCP-Begleitdienst die Anwendung erreicht. |
| `PHX_FORCE_SSL` | nein | `true` leitet unverschlüsseltes HTTP auf HTTPS um und setzt HSTS. Setze es, sobald der Reverse-Proxy TLS terminiert und `X-Forwarded-Proto` von Loopback oder von einer in `PORTFOLIXIR_TRUSTED_PROXIES` genannten Adresse sendet; standardmäßig aus, weil eine Loopback-Instanz kein TLS hat, auf das sie umleiten könnte, und die Anwendung TLS nie selbst terminiert. |
| `PORTFOLIXIR_TRUSTED_PROXIES` | nein | Adressen oder CIDR-Blöcke, kommagetrennt, deren `X-Forwarded-For` (die Quelle der Anmelde- und Token-Drossel) und `X-Forwarded-Proto` (das Schema) die Anwendung glaubt. Leer zählt die Drossel die verbindende Adresse, hinter einem Proxy also den Proxy, und nur ein Proxy auf Loopback kann eine Anfrage als HTTPS kennzeichnen. |
| `PORTFOLIXIR_MCP_ALLOWED_HOSTS` | nein | Weitere `Host`-Namen, unter denen der MCP-Begleitdienst antwortet (ein Proxy-Name), kommagetrennt. |

Ohne UI-Passwort und mit einem über Loopback hinaus geöffneten Port
protokolliert die Anwendung beim Start eine Warnung, die diese Tabelle nennt;
bei einem UI-Passwort unter 12 Zeichen warnt sie ebenfalls und startet
trotzdem.

## Start

```bash
docker compose up --build
```

Der erste Start baut das Release-Image, führt die Migrationen aus und startet
die Anwendung. Öffne die App über deinen Reverse-Proxy oder direkt auf dem
Host unter:

```text
http://127.0.0.1:4000
```

Der MCP-Begleitdienst ist nur auf localhost erreichbar:

```text
http://127.0.0.1:4001/mcp
```

## Reverse-Proxy

Die Anwendung lauscht auf Loopback; ein Reverse-Proxy auf demselben Host
(Caddy, nginx, Traefik) terminiert TLS und leitet an `127.0.0.1:4000` weiter.
Er muss den ursprünglichen `Host`-Header durchreichen (setze `PHX_HOST` auf
diesen Namen) sowie `X-Forwarded-Proto: https`, das das Sitzungs-Cookie als
`Secure` markiert und das `PHX_FORCE_SSL` liest, und `X-Forwarded-For`. Nenne
die Adresse, von der aus der Proxy verbindet, in
`PORTFOLIXIR_TRUSTED_PROXIES` — über den veröffentlichten Port ist das das
Gateway der Docker-Bridge (`docker network inspect` zeigt es, ein Block wie
`172.16.0.0/12` deckt es ab) —, damit die Drossel den Client hinter dem Proxy
zählt und nicht den Proxy: ohne sie sperren zehn falsche Passwörter von
irgendwem, den der Proxy durchlässt, die Anmeldung für alle dahinter, den
Betreiber eingeschlossen. Dieselbe Einstellung entscheidet, wessen
`X-Forwarded-Proto` geglaubt wird: nur Loopback und die genannten Adressen.
Ein Proxy, der den Container über die Docker-Bridge erreicht, muss dort also
genannt sein, damit das Cookie `Secure` ist und `PHX_FORCE_SSL` HTTPS sieht.
Fehlgeschlagene Anmeldungen zählen außerdem über alle Quellen zusammen in einem
gleitenden Zeitfenster, damit auf viele Adressen verteilte Versuche sich nicht
vervielfachen; über dieser Obergrenze lässt die Anmeldung alle warten, den
Betreiber eingeschlossen, während bereits angemeldete Sitzungen weiterlaufen.
Authentifizierung am Reverse-Proxy und das eingebaute UI-Passwort ergänzen
sich: behalte eines oder beides.

### Der TLS-Vertrag

TLS ist ganz die Aufgabe des Proxys. Die Anwendung terminiert nie selbst TLS
und leitet nie von sich aus auf HTTPS um, weil ihr sicherer Standard eine
Loopback-Instanz ohne Zertifikat ist; was sie bietet, ist das Opt-in. Der
Vertrag in vier Zeilen:

1. Der Proxy terminiert TLS und leitet unverschlüsseltes HTTP an
   `127.0.0.1:4000` weiter.
2. Er reicht `Host`, `X-Forwarded-Proto` und `X-Forwarded-For` unverändert
   durch und leitet WebSocket-Upgrades auf `/live/websocket` weiter (Caddy tut
   das von sich aus; nginx braucht `proxy_set_header Upgrade $http_upgrade;`
   und `proxy_set_header Connection "upgrade";`) — die Live-Seiten laufen
   über diesen Socket.
3. Sobald das steht, lässt `PHX_FORCE_SSL=true` die Anwendung jede
   unverschlüsselte Anfrage, die sie noch sieht, auf HTTPS umleiten und auf
   den HTTPS-Antworten `Strict-Transport-Security` senden. Ohne die Variable
   liefert die Anwendung aus, was sie bekommt; mit ihr erzeugt ein Proxy, der
   `X-Forwarded-Proto` vergisst oder dessen Adresse weder Loopback ist noch in
   `PORTFOLIXIR_TRUSTED_PROXIES` steht, eine Umleitungsschleife — so sagt dir
   die Variable, dass der Header fehlt oder nicht geglaubt wird.
4. Der Proxy reicht die Antwort-Header der Anwendung unverändert durch und
   fügt den Seiten nichts hinzu. Jede Seite trägt eine Content-Security-Policy
   (nächster Abschnitt); ein Proxy, der ein Skript oder ein Stylesheet
   einfügt — ein Banner, ein Analytics-Tag —, sieht es im Browser blockiert,
   und einer, der den Header umschreibt, schaltet den Schutz ab.

## Content-Security-Policy

Jede Browser-Seite wird mit einem `Content-Security-Policy`-Header
ausgeliefert, der je Anfrage gebaut wird. Skripte laufen nur von der Instanz
selbst und aus den drei Boot-Skripten im `<head>` und `<body>` der Seite,
jedes zugelassen durch eine für diese Anfrage erzeugte Nonce; es gibt nirgends
einen Inline-Event-Handler, kein `eval` und kein Skript von einem anderen
Ursprung. Stile kommen aus dem Stylesheet der Instanz plus inline
`style`-Attributen (die Seiten färben Farbfelder und rücken Baumzeilen damit
ein); Bilder von der Instanz plus `data:`-URLs, die der Chart-Export zum
Zeichnen seines Bildes nutzt; Verbindungen gehen an die Instanz und an ihren
eigenen WebSocket-Ursprung unter dem Namen, unter dem der Browser sie
angesprochen hat; nichts wird eingebettet, keine fremde Seite rahmt die
Seiten ein, und Formulare senden nur an die Instanz.

Zu konfigurieren ist nichts. Zwei Dinge folgen daraus für den Betreiber: der
Proxy muss den `Host`-Header durchreichen, den der Browser gesendet hat (der
Socket-Ursprung in der Policy ist dieser Name, ein Proxy, der `Host`
umschreibt, lässt die Live-Seiten also nicht verbinden), und eine Seite, die
zwar rendert, sich aber nicht aktualisiert, mit
`Content-Security-Policy`-Fehlern in der Browser-Konsole, bedeutet, dass ein
Proxy oder eine Browser-Erweiterung Skript in sie eingefügt hat — die Policy
hat ihre Arbeit getan.

## Entwicklungs-Stack

Die Entwicklungskonfiguration — Quelltext eingebunden, Mix vorhanden,
Debug-Seiten, Origin-Prüfungen aus, der Datenbank-Port für lokale Werkzeuge
veröffentlicht — liegt in `docker-compose.dev.yml` und ist nie das
dokumentierte Deployment:

```bash
docker compose -f docker-compose.dev.yml up --build
```

## Sicherung und Wiederherstellung

Die ganze Instanz ist eine PostgreSQL-Datenbank, eine Sicherung ist also eine
`pg_dump`-Datei. Sie enthält **alle** Daten der Instanz: Wertpapiere, Kurse und
Wechselkurse, Portfolios, Depots und Geldkonten, jede Transaktion, die
Klassifizierungen mit ihren Zuordnungen, die SOLL-Pläne mit Kategorie- und
Positionszielen und die Cash-Ziele, die eigenen Regeln, Recherche-Log und
Termine, Steuerdaten und das Audit-Journal. Sie enthält **nicht** die `.env` —
diese Datei gehört ebenfalls an einen sicheren Ort: Ohne `POSTGRES_PASSWORD` und
die Tokens ist eine wiederhergestellte Datenbank zwar vollständig, die Instanz
muss aber neu konfiguriert werden.

Die Befehle unten laufen in dem Verzeichnis, das `docker-compose.yml` und `.env`
enthält. PostgreSQL-Werkzeuge auf dem Host sind nicht nötig: Sie laufen im
`db`-Container.

### Sicherung anlegen

Vor der Sicherung drei Zahlen notieren, gegen die die Wiederherstellung geprüft
wird (siehe „Wiederherstellung prüfen“ unten). Dann:

```bash
docker compose exec -T db \
  pg_dump -U portfolixir -d portfolixir_prod --format=custom \
  > portfolixir-$(date +%F).dump
```

Die Instanz läuft währenddessen weiter; die Datei ist ein konsistenter Stand
eines Zeitpunkts. Ob die Datei lesbar ist, zeigt ihr Inhaltsverzeichnis:

```bash
docker compose exec -T db pg_restore --list < portfolixir-2026-09-23.dump | head
```

Vor jedem Upgrade eine Sicherung anlegen: Migrationen sind additiv, und ein
Rollback über ein Release hinweg stellt die davor angelegte Sicherung wieder
her.

### Wiederherstellen

Eine Wiederherstellung ersetzt die Datenbank durch die Sicherung. Die Anwendung
migriert die Datenbank beim Start, deshalb wird sie vorher angehalten und erst
nach der vollständigen Wiederherstellung gestartet — auf einem neuen Host aus
demselben Grund nur die Datenbank starten:

```bash
# 1. Nur die Datenbank (auf einem neuen Host: `docker compose up -d db`).
docker compose stop app mcp

# 2. Eine leere Datenbank unter demselben Namen.
docker compose exec -T db dropdb -U portfolixir --if-exists portfolixir_prod
docker compose exec -T db createdb -U portfolixir portfolixir_prod

# 3. Die Sicherung.
docker compose exec -T db \
  pg_restore -U portfolixir -d portfolixir_prod --no-owner --exit-on-error \
  < portfolixir-2026-09-23.dump

# 4. Die Instanz; sie migriert die wiederhergestellte Datenbank nach vorn, wenn
#    die Sicherung aus einem älteren Release stammt.
docker compose up -d
```

`--exit-on-error` hält beim ersten Problem an, statt eine halb gefüllte
Datenbank zu hinterlassen. Eine Sicherung lässt sich in dieselbe oder eine
neuere PostgreSQL-Hauptversion zurückspielen; das `db`-Image aus
`docker-compose.yml` ist das richtige.

### Wiederherstellung prüfen

Drei Zahlen vor der Sicherung und nach der Wiederherstellung vergleichen: den
Gesamtwert, die Anzahl der Bestände und eine bekannte Position. Auf der
Vermögensseite sind das die Summe oben, die Zeilen der Positionstabelle und eine
beliebige Zeile daraus. Über die API (das Token ist `PORTFOLIXIR_API_TOKEN` aus
der `.env`; `1` ist die Portfolio-ID, die der erste Aufruf liefert):

```bash
TOKEN=$(grep '^PORTFOLIXIR_API_TOKEN=' .env | cut -d= -f2-)
API=http://127.0.0.1:4000/api/v1

curl -s -H "Authorization: Bearer $TOKEN" $API/portfolios
curl -s -H "Authorization: Bearer $TOKEN" $API/portfolios/1/valuation   # "total_value"
curl -s -H "Authorization: Bearer $TOKEN" $API/portfolios/1/holdings    # ein Eintrag je Bestand
```

Die Zahlen sind Dezimal-Strings in voller Genauigkeit; eine Wiederherstellung,
die nichts verloren hat, zeigt sie Zeichen für Zeichen gleich. Der Ablauf wurde
am 2026-09-23 vollständig gegen den synthetischen Review-Datensatz mit der
mitgelieferten `docker-compose.yml` durchgespielt: Sicherung, ein neues
Datenbank-Volume, Wiederherstellung, und die drei Zahlen, die Zeilenzahl des
Audit-Journals und die eigenen Regeln stimmten überein.

## Zurücksetzen

Soll die lokale Datenbank zurückgesetzt werden, entferne das Compose-Volume:

```bash
docker compose down -v
docker compose up --build
```

## Upgrade

Sichere die Datenbank vor einem Upgrade: Migrationen sind additiv, und ein
Rollback über ein Release hinweg spielt diese Sicherung zurück.

Nachdem du eine neue Version des Repositorys geholt hast, hole die Images,
baue neu und starte:

```bash
docker compose pull db
docker compose build --pull
docker compose up -d
```

Die Erlang/OTP- und Debian-Basis-Images der Anwendung sind im Repository per
Digest gepinnt; eine Laufzeit-Korrektur darin kommt also mit der neuen Version
selbst. Das Datenbank-Image und die Node-Basis des MCP-Begleiters sind per Tag
benannt: ein einfaches `docker compose up --build` verwendet die Kopien weiter,
die schon auf dem Host liegen, deshalb bringen erst `docker compose pull db`
und `--pull` deren Korrekturen. Die Release-Notes sagen, wann ein Upgrade eine
solche Korrektur enthält.

## Abgeleitete Werte neu aufbauen

Teure Auswertungen (derzeit der tägliche Performance-Lauf) werden als
dauerhafte abgeleitete Werte gehalten (ADR-0039): reine, jederzeit neu
berechenbare Materialisierungen des Buchungsjournals, versioniert gegen jede
Schreiboperation. Sie lassen sich mit einem Befehl verwerfen und aus dem
Journal neu aufbauen; der Befehl meldet seine eigene Laufzeit:

```bash
mix portfolixir.derived.rebuild
# im Release-Container:
docker compose exec app bin/portfolixir eval "Portfolixir.Release.rebuild_derived()"
```

Das berührt nie Finanzdaten — das Journal wird gelesen, nie geschrieben. Es
ist der Wiederherstellungsschritt, falls ein abgeleiteter Wert je als veraltet
oder beschädigt gilt; im Normalbetrieb ist die Invalidierung automatisch.
Die Aktualität ist immer sichtbar: die Basiszeile des Performance-Charts und
jede Performance-Antwort von API und MCP tragen `as_of` und ein
`stale`-Kennzeichen.

### Aktualisierung im Hintergrund

Eine Schreiboperation markiert die betroffenen Zahlen nicht nur als veraltet —
sie plant ihre Neuberechnung. Kurz nach einer Buchung, einem Import oder
einer Kursaktualisierung werden die betroffenen Werte im Hintergrund neu
materialisiert, sodass die nächste geöffnete Seite eine Zahl zeigt statt eines
„wird berechnet“-Hinweises. Buchungen werden gesammelt und gemeinsam
abgearbeitet: ein großer Export kostet eine Aktualisierung, nicht eine je
Zeile.

Zwei Einstellungen steuern das, beide in `config/config.exs`:

| Einstellung | Standard | Wirkung |
|---|---|---|
| `quiet_ms` | `500` | Wie lange der Refresher auf das Ende des Schreibens wartet, bevor er neu berechnet. |
| `max_delay_ms` | `10_000` | Die längste Wartezeit, damit auch ein durchgehender Strom von Schreiboperationen abgearbeitet wird. |

Die Aktualisierung optimiert *wann* die Arbeit stattfindet, nie ob die Zahl
stimmt: ein veralteter Wert wird beim Lesen trotzdem neu berechnet, ein
langsamer, fehlschlagender oder abgeschalteter Refresher kostet also Latenz
und nie Aktualität.

## Separate MCP-Installation

Der MCP-Server wird in diesem Repository entwickelt, lässt sich aber getrennt
installieren und starten:

```bash
npm install --prefix mcp-server
npm run build --prefix mcp-server
PORTFOLIXIR_API_BASE_URL=http://127.0.0.1:4000 \
PORTFOLIXIR_API_TOKEN=replace-me \
npm start --prefix mcp-server
```

## Versionen und Rollback

Jeder Sprint-Merge wird getaggt (`vX.Y.Z`, beginnend bei `v0.5.0`) und
automatisch als GitHub-Release mit generierten Notizen veröffentlicht. Ein
Release ist ein bekannt guter Stand, auf den sich eine selbst gehostete
Instanz festlegen oder zurücksetzen lässt (vor dem Bauen das Tag auschecken),
plus ein lesbares Änderungsprotokoll — nie ein installierbares Artefakt.
Migrationen sind additiv; beim Rollback über ein Release hinweg, das
Migrationen hinzugefügt hat, spielst du die vor diesem Upgrade angelegte
Datenbanksicherung zurück.

## Hinweise

- Dieses Setup nutzt die `docker-compose.yml` im Wurzelverzeichnis (ein
  Produktions-Release aus `Dockerfile.release`); `docker-compose.dev.yml` ist
  der Entwicklungs-Stack.
- Die Web-Oberfläche ist standardmäßig offen und wird mit einer Variablen
  (`PORTFOLIXIR_UI_PASSWORD`) gesperrt; die Instanz bindet Loopback und weist
  fremde `Host`-Namen ab (ADR-0045).
- Der MCP-Begleitdienst kapselt die lokale JSON-API und greift nicht direkt
  auf die Datenbank zu.
- Dieses Setup konfiguriert keine Broker-Synchronisation, keine
  Bank-Synchronisation, keine Dokumentenaufnahme (über den Portfolio-
  Performance-CSV/JSON-Import hinaus), kein Trading, keine Zahlungen, keine
  Orders, kein Rebalancing und keine LLM-Funktionen.
- Die öffentliche Dokumentation wird mit GitHub Pages unter `portfolixir.app`
  veröffentlicht.
