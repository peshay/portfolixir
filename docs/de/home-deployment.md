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
Geheimnis fehlt, und die Anwendung verweigert den Start mit einem Token, das
kürzer als 32 Bytes oder ein Platzhalter ist. Erzeuge jedes Token mit
`openssl rand -base64 48` und `POSTGRES_PASSWORD` mit `openssl rand -hex 32`:
die Compose-Datei setzt es in die Datenbank-URL ein, wo ein `/` oder `#` aus
Base64 die Verbindungszeichenkette zerlegen würde.

| Variable | Pflicht | Wirkung |
|---|---|---|
| `SECRET_KEY_BASE` | ja | Signiert das Sitzungs-Cookie; die Signatur-Salze werden daraus abgeleitet. |
| `POSTGRES_PASSWORD` | ja | Das Datenbankpasswort; die Anwendung baut ihre Verbindungszeichenkette daraus. |
| `PORTFOLIXIR_API_TOKEN` | ja | Das Bearer-Token der JSON-API und der Upstream-Aufrufe des MCP-Begleitdienstes. |
| `PORTFOLIXIR_MCP_TOKEN` | ja | Das Bearer-Token, das ein MCP-Client dem Begleitdienst vorlegt. |
| `PORTFOLIXIR_UI_PASSWORD` | nein | Gesetzt verlangt die Web-Oberfläche eine Anmeldung (ADR-0045). Ungesetzt ist die Oberfläche offen — vertretbar nur hinter einer Authentifizierung des Reverse-Proxys. |
| `PORTFOLIXIR_SESSION_DAYS` | nein | Wie viele Tage eine Anmeldung gilt (Standard 30). Das Fenster wandert: die Nutzung der Instanz verlängert es, gefragt wird also erst nach einer vollen Periode ohne Nutzung. `0` beendet die Anmeldung mit dem Schließen des Browsers. |
| `PHX_HOST` | nein | Der Name, unter dem der Reverse-Proxy ausliefert (Standard `localhost`). Anfragen unter einem anderen `Host` werden mit 421 abgewiesen. |
| `PORTFOLIXIR_ALLOWED_HOSTS` | nein | Weitere Namen, kommagetrennt (eine LAN-Adresse, ein zweiter Proxy-Name). Die Compose-Datei ergänzt `app`, den Namen, unter dem der MCP-Begleitdienst die Anwendung erreicht. |
| `PHX_FORCE_SSL` | nein | `true` leitet unverschlüsseltes HTTP auf HTTPS um und setzt HSTS. Setze es, sobald der Reverse-Proxy TLS terminiert und `X-Forwarded-Proto` weiterreicht; standardmäßig aus, weil eine Loopback-Instanz kein TLS hat, auf das sie umleiten könnte, und die Anwendung TLS nie selbst terminiert. |
| `PORTFOLIXIR_TRUSTED_PROXIES` | nein | Adressen oder CIDR-Blöcke, kommagetrennt, deren `X-Forwarded-For` die Anmelde- und Token-Drossel glaubt. Leer zählt die Drossel die verbindende Adresse, hinter einem Proxy also den Proxy. |
| `PORTFOLIXIR_MCP_ALLOWED_HOSTS` | nein | Weitere `Host`-Namen, unter denen der MCP-Begleitdienst antwortet (ein Proxy-Name), kommagetrennt. |

Ohne UI-Passwort und mit einem über Loopback hinaus geöffneten Port
protokolliert die Anwendung beim Start eine Warnung, die diese Tabelle nennt.

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
Betreiber eingeschlossen. Authentifizierung am Reverse-Proxy und das
eingebaute UI-Passwort ergänzen sich: behalte eines oder beides.

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
   `X-Forwarded-Proto` vergisst, eine Umleitungsschleife — so sagt dir die
   Variable, dass der Header fehlt.
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

## Zurücksetzen

Soll die lokale Datenbank zurückgesetzt werden, entferne das Compose-Volume:

```bash
docker compose down -v
docker compose up --build
```

Sichere die Datenbank vor einem Upgrade: Migrationen sind additiv, und ein
Rollback über ein Release hinweg spielt diese Sicherung zurück.

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
