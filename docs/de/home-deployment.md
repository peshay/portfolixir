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
des Hosts und die Datenbank nie. In ihren Containern lauschen beide auf jeder
Schnittstelle; in Compose hält deshalb die Port-Zuordnung, nicht die
Anwendung, sie auf dem Loopback des Hosts („Erreichbarkeit“ unten).

## Voraussetzungen

- Docker Engine 28.3.3 oder neuer, mit Docker Compose. Ab 28.0 verhindert die
  Engine, dass andere Rechner im Netz einen auf `127.0.0.1` veröffentlichten
  Port direkt erreichen, und 28.3.3 schließt den Fall, in dem ein Neuladen der
  Firewall diesen Weg wieder öffnete (CVE-2025-54388). Mit einer älteren
  Engine halten die Loopback-Port-Zuordnungen die Instanz nicht auf diesem
  Rechner;
- ein Checkout dieses Repositories;
- eine `.env`-Datei mit den Geheimnissen (siehe unten);
- keine echten Portfolio-, Bank-, Broker-, Wallet- oder Abrechnungsdaten in
  Fixtures.

## Geheimnisse und Einstellungen

Lege die `.env` aus `.env.example` an, nur für dich lesbar, und lass es dabei:

```bash
install -m 600 .env.example .env
```

Der Stack startet nicht, solange ein Geheimnis fehlt, die Anwendung und der
MCP-Begleitdienst verweigern den Start mit einem Token, das kürzer als 32 Bytes
oder ein Platzhalter ist, und die Anwendung verweigert einen
`SECRET_KEY_BASE`, der kürzer als 64 Bytes, ein Platzhalter oder ein in diesem
Repository veröffentlichter Wert ist. Erzeuge jedes Token und
`SECRET_KEY_BASE` mit `openssl rand -base64 48` und `POSTGRES_PASSWORD` mit
`openssl rand -hex 32`:
die Compose-Datei setzt es in die Datenbank-URL ein, wo ein `/` oder `#` aus
Base64 die Verbindungszeichenkette zerlegen würde.

| Variable | Pflicht | Wirkung |
|---|---|---|
| `SECRET_KEY_BASE` | ja | Signiert das Sitzungs-Cookie; die Signatur-Salze werden daraus abgeleitet. |
| `POSTGRES_PASSWORD` | ja | Das Datenbankpasswort; die Anwendung baut ihre Verbindungszeichenkette daraus. |
| `PORTFOLIXIR_API_TOKEN` | ja | Das Bearer-Token der JSON-API und der Upstream-Aufrufe des MCP-Begleitdienstes. |
| `PORTFOLIXIR_MCP_TOKEN` | ja | Das Bearer-Token, das ein MCP-Client dem Begleitdienst vorlegt. |
| `PORTFOLIXIR_UI_PASSWORD` | nein | Gesetzt verlangt die Web-Oberfläche eine Anmeldung (ADR-0045). Ungesetzt ist die Oberfläche offen — vertretbar nur hinter einer Authentifizierung des Reverse-Proxys. Eine Änderung beendet jede Anmeldung, die mit dem alten Passwort erfolgt ist. |
| `PORTFOLIXIR_SESSION_DAYS` | nein | Wie viele Tage eine Anmeldung gilt (Standard 30). Das Fenster wandert: die Nutzung der Instanz verlängert es, gefragt wird also erst nach einer vollen Periode ohne Nutzung. `0` schaltet den serverseitigen Ablauf ab: der Browser vergisst die Anmeldung beim Schließen, eine Kopie des Sitzungs-Cookies läuft aber nie ab; wähle deshalb lieber eine Zahl von Tagen. Eine Abmeldung beendet die Anmeldung nur in diesem Browser, eine vorher genommene Kopie des Sitzungs-Cookies bleibt gültig; um jede Anmeldung zu beenden, ändere `PORTFOLIXIR_UI_PASSWORD` oder rotiere `SECRET_KEY_BASE`. |
| `PHX_HOST` | nein | Der Name, unter dem der Reverse-Proxy ausliefert (Standard `localhost`). Anfragen unter einem anderen `Host` werden mit 421 abgewiesen. |
| `PORTFOLIXIR_ALLOWED_HOSTS` | nein | Weitere Namen, kommagetrennt (eine LAN-Adresse, ein zweiter Proxy-Name). Die Compose-Datei ergänzt `app`, den Namen, unter dem der MCP-Begleitdienst die Anwendung erreicht. |
| `PHX_FORCE_SSL` | nein | `true` leitet unverschlüsseltes HTTP auf HTTPS um und setzt HSTS. Setze es, sobald der Reverse-Proxy TLS terminiert und `X-Forwarded-Proto` von Loopback oder von einer in `PORTFOLIXIR_TRUSTED_PROXIES` genannten Adresse sendet; standardmäßig aus, weil eine Loopback-Instanz kein TLS hat, auf das sie umleiten könnte, und die Anwendung TLS nie selbst terminiert. |
| `PORTFOLIXIR_TRUSTED_PROXIES` | nein | Adressen oder CIDR-Blöcke, kommagetrennt, deren `X-Forwarded-For` (die Quelle der Anmelde- und Token-Drossel) und `X-Forwarded-Proto` (das Schema) die Anwendung glaubt. Leer zählt die Drossel die verbindende Adresse, hinter einem Proxy also den Proxy, und nur ein Proxy auf Loopback kann eine Anfrage als HTTPS kennzeichnen. |
| `PORTFOLIXIR_MCP_ALLOWED_HOSTS` | nein | Weitere `Host`-Namen, unter denen der MCP-Begleitdienst antwortet (ein Proxy-Name), kommagetrennt. |
| `PORTFOLIXIR_LOGO_DIR` | nein | Das absolute Verzeichnis, in dem gespeicherte Logos liegen. Das Release-Image setzt es auf `/var/lib/portfolixir/logos`, das Volume `portfolixir-logos`, weil das Release selbst für den Benutzer, unter dem es läuft, schreibgeschützt ist; in Compose nicht ändern. |

Ohne UI-Passwort und mit einem über Loopback hinaus geöffneten Port
protokolliert die Anwendung beim Start eine Warnung, die diese Tabelle nennt;
bei einem UI-Passwort unter 12 Zeichen warnt sie ebenfalls und startet
trotzdem.

### Erreichbarkeit

Ein allein gestartetes Release lauscht auf Loopback, solange `PHX_BIND_ALL`
nichts anderes sagt. Im Compose-Deployment lauscht die Anwendung in ihrem
Container auf jeder Schnittstelle, weil eine Port-Zuordnung an die
Netzwerkschnittstelle des Containers weiterleitet, nie an dessen Loopback, und
die Port-Zuordnung, nicht die Anwendung, hält sie auf dem Loopback des Hosts.
Erreichbar ist sie dort von diesem Host, über die Loopback-Zuordnung und über
die eigene Adresse des Containers, und von den anderen Containern des Stacks;
von nichts sonst im Netz, mit Docker Engine 28.3.3 oder neuer. Die Anwendung
kann das nicht von einem ins Netz geöffneten Port unterscheiden, ohne
UI-Passwort erscheint die Startwarnung deshalb in jeder Compose-Installation.
Setze für eine Compose-Installation `PORTFOLIXIR_UI_PASSWORD`: es sperrt die
Web-Oberfläche auch gegenüber den anderen Containern und gegenüber allem
anderen, was auf diesem Host läuft.

## Datenbankrollen (empfohlen für eine neue Installation)

Im Auslieferungszustand verbindet sich die Anwendung als Bootstrap-Superuser
der Datenbank, die Rolle, die das `db`-Image aus `POSTGRES_USER` anlegt und der
auch jede Tabelle gehört. Die Append-only- und Audit-Journal-Trigger binden dann
den Code der Anwendung, nicht ihre Zugangsdaten: ein Superuser oder der
Eigentümer einer Tabelle kann einen Trigger abschalten oder löschen. Die
empfohlene Einrichtung gibt der Datenbank drei Rollen mit je einer Aufgabe:

- den Bootstrap-Superuser, nur für die Verwaltung: Sicherungen,
  Wiederherstellungen und die Rechte unten;
- `portfolixir_owner`, kein Superuser, dem die Tabellen gehören und der die
  Migrationen ausführt;
- `portfolixir_app`, als die sich die Anwendung verbindet: sie liest und
  schreibt Zeilen, besitzt nichts und hat kein `TRUNCATE`, kann also weder eine
  Tabelle ändern noch einen Trigger abschalten oder löschen.

Das gilt für eine neue Installation, vor ihrem ersten Start. Eine bestehende
Instanz auf diese Rollen umzustellen ist eine Migration dieser Instanz und wird
hier nicht beschrieben.

1. Zwei Passwörter in die `.env` eintragen, jedes aus `openssl rand -hex 32`:
   `PORTFOLIXIR_OWNER_DB_PASSWORD` und `PORTFOLIXIR_APP_DB_PASSWORD`.
2. Nur die Datenbank starten und die Rollen anlegen. Die Passwörter erreichen
   `psql` über die Standardeingabe, nie über eine Befehlszeile:

   ```bash
   docker compose up -d db
   OWNER_PW=$(grep '^PORTFOLIXIR_OWNER_DB_PASSWORD=' .env | cut -d= -f2-)
   APP_PW=$(grep '^PORTFOLIXIR_APP_DB_PASSWORD=' .env | cut -d= -f2-)
   docker compose exec -T db psql -v ON_ERROR_STOP=1 -U portfolixir -d portfolixir_prod <<SQL
   CREATE ROLE portfolixir_owner LOGIN PASSWORD '$OWNER_PW';
   CREATE ROLE portfolixir_app LOGIN PASSWORD '$APP_PW';
   ALTER DATABASE portfolixir_prod OWNER TO portfolixir_owner;
   REVOKE ALL ON DATABASE portfolixir_prod FROM PUBLIC;
   GRANT CONNECT ON DATABASE portfolixir_prod TO portfolixir_app;
   REVOKE CREATE ON SCHEMA public FROM PUBLIC;
   GRANT USAGE ON SCHEMA public TO portfolixir_app;
   ALTER DEFAULT PRIVILEGES FOR ROLE portfolixir_owner IN SCHEMA public
     GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO portfolixir_app;
   ALTER DEFAULT PRIVILEGES FOR ROLE portfolixir_owner IN SCHEMA public
     GRANT USAGE, SELECT ON SEQUENCES TO portfolixir_app;
   SQL
   ```

   Die beiden Default-Privilege-Zeilen erreichen jede Tabelle, die eine
   Migration jetzt oder später anlegt: jede wird der Laufzeitrolle beim
   Anlegen durch den Eigentümer freigegeben, `TRUNCATE` nie.
3. Neben der `docker-compose.yml` eine `docker-compose.override.yml` anlegen;
   Compose liest sie bei jedem Befehl mit. Sie verbindet die Anwendung als
   Laufzeitrolle, startet das Release ohne den Migrationsschritt, den die
   Laufzeitrolle nicht ausführen kann, und ergänzt einen einmaligen
   `migrate`-Dienst, der die Migrationen als Eigentümer ausführt:

   ```yaml
   services:
     app:
       entrypoint: ["/opt/app/bin/portfolixir"]
       command: ["start"]
       environment:
         DATABASE_URL: postgres://portfolixir_app:${PORTFOLIXIR_APP_DB_PASSWORD:?set it in .env}@db:5432/portfolixir_prod

     migrate:
       build:
         context: .
         dockerfile: Dockerfile.release
       profiles: ["migrate"]
       depends_on:
         db:
           condition: service_healthy
       entrypoint: ["/opt/app/bin/portfolixir", "eval", "Portfolixir.Release.migrate()"]
       environment:
         DATABASE_URL: postgres://portfolixir_owner:${PORTFOLIXIR_OWNER_DB_PASSWORD:?set it in .env}@db:5432/portfolixir_prod
         SECRET_KEY_BASE: ${SECRET_KEY_BASE:?set SECRET_KEY_BASE in .env}
         PORTFOLIXIR_API_TOKEN: ${PORTFOLIXIR_API_TOKEN:?set PORTFOLIXIR_API_TOKEN in .env}
         PHX_HOST: ${PHX_HOST:-localhost}
   ```

4. Als Eigentümer migrieren, dann starten:

   ```bash
   docker compose run --rm --build migrate
   docker compose up --build -d
   ```

Mit diesen Rollen ändern sich zwei Abläufe weiter unten. Ein Upgrade führt nach
dem Bauen und vor `docker compose up -d` `docker compose run --rm --build
migrate` aus, weil die Anwendung beim Start nicht mehr migriert. Eine
Wiederherstellung gibt die neue Datenbank nach ihrem Schritt 2 an den
Eigentümer zurück, stellt in Schritt 3 als Eigentümer wieder her, indem
`pg_restore` `--role=portfolixir_owner` erhält, damit die Tabellen ihren
Eigentümer und ihre Rechte behalten, und migriert vor Schritt 4 wie beim
Upgrade:

```bash
docker compose exec -T db psql -v ON_ERROR_STOP=1 -U portfolixir -d portfolixir_prod <<'SQL'
ALTER DATABASE portfolixir_prod OWNER TO portfolixir_owner;
REVOKE ALL ON DATABASE portfolixir_prod FROM PUBLIC;
GRANT CONNECT ON DATABASE portfolixir_prod TO portfolixir_app;
SQL
```

Das Rezept wurde mit den PostgreSQL-Werkzeugen und dem Release außerhalb von
Compose geprüft: die Laufzeitrolle schreibt journalisierte Datensätze und wird
bei `TRUNCATE`, beim Abschalten und Löschen eines Triggers und beim Anlegen
einer Tabelle abgewiesen; eine als Eigentümer wiederhergestellte Sicherung
behält jeden Trigger und jedes Recht.

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

Die Anwendung ist auf dem Loopback des Hosts erreichbar; ein Reverse-Proxy auf
demselben Host (Caddy, nginx, Traefik) terminiert TLS und leitet an
`127.0.0.1:4000` weiter.
Er reicht den ursprünglichen `Host`-Header durch (setze `PHX_HOST` auf diesen
Namen) und setzt die beiden Weiterleitungs-Header selbst: Er setzt
`X-Forwarded-Proto` auf das Schema, das der Browser benutzt hat — das markiert
das Sitzungs-Cookie als `Secure` und wird von `PHX_FORCE_SSL` gelesen —, und er
hängt die verbindende Adresse an `X-Forwarded-For` an oder überschreibt den
Header mit dieser Adresse. Er reicht nie einen Wert durch, den der Client
geschickt hat: ein Weiterleitungs-Header, der die Anwendung so erreicht, wie
der Client ihn geschrieben hat, lässt den Client die Quelle der Drossel wählen.

Nenne die genaue Adresse, von der aus der Proxy verbindet, in
`PORTFOLIXIR_TRUSTED_PROXIES`. Über den veröffentlichten Port ist das das
Gateway der Docker-Bridge, das `docker network inspect` zeigt, zum Beispiel
`PORTFOLIXIR_TRUSTED_PROXIES=172.18.0.1`. Nenne die eine Adresse statt eines
privaten Blocks: jede Adresse in einem genannten Block wird geglaubt, ein Block
vertraut also auch allem anderen in diesem Netz. Mit der genannten Adresse
zählt die Drossel den Client hinter dem Proxy und nicht den Proxy: ohne sie
sperren zehn falsche Passwörter von irgendwem, den der Proxy durchlässt, die
Anmeldung für alle dahinter, den Betreiber eingeschlossen. Dieselbe
Einstellung entscheidet, wessen
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
2. Er reicht `Host` durch, setzt `X-Forwarded-Proto` selbst und hängt die
   verbindende Adresse an `X-Forwarded-For` an oder überschreibt den Header;
   er reicht nie einen Wert durch, den der Client geschickt hat. Außerdem
   leitet er WebSocket-Upgrades auf `/live/websocket` weiter — die Live-Seiten
   laufen über diesen Socket. Caddys `reverse_proxy` tut all das von sich aus.
   nginx braucht:

   ```nginx
   proxy_http_version 1.1;
   proxy_set_header Host $host;
   proxy_set_header X-Forwarded-Proto $scheme;
   proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
   proxy_set_header Upgrade $http_upgrade;
   proxy_set_header Connection "upgrade";
   ```

   HAProxy braucht die Zeilen unten, `option forwardfor` ohne `if-none`, das
   einen vom Client geschickten Header behalten würde:

   ```text
   option forwardfor
   http-request set-header X-Forwarded-Proto https if { ssl_fc }
   http-request set-header X-Forwarded-Proto http if !{ ssl_fc }
   ```

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

Der Stack läuft mit öffentlichen Entwicklungsgeheimnissen — dem Datenbankpasswort
`postgres` und dem in `config/dev.exs` eingecheckten `SECRET_KEY_BASE` —,
deshalb sind seine beiden Ports, der der Anwendung und der der Datenbank, nur
auf der Loopback-Schnittstelle des Hosts veröffentlicht, und er enthält nur
synthetische Daten.

### Umzug vom Entwicklungs-Stack

Vor dem Produktions-Release (Sprint 10, #760) war das dokumentierte Deployment
dieser Entwicklungs-Stack, damals `docker-compose.yml` genannt, mit auf jeder
Schnittstelle offenen Ports. Eine Instanz, die noch so läuft, zieht per
Sicherung und Wiederherstellung auf den Produktions-Stack um, nicht an Ort und
Stelle: die Produktionsdatenbank wird nur auf einem leeren Volume angelegt, und
das alte Volume behält den Entwicklungsbenutzer. Im Checkout, nachdem die
aktuelle Version geholt ist:

```bash
# 1. Eine Sicherung der Entwicklungsdatenbank, solange sie noch läuft.
umask 077
mkdir -p ~/portfolixir-backups
docker compose -f docker-compose.dev.yml exec -T db \
  pg_dump -U postgres -d portfolixir_dev --format=custom \
  > ~/portfolixir-backups/portfolixir-dev.dump

# 2. Die Datei zeigt ihr Inhaltsverzeichnis; erst dann den Entwicklungs-Stack
#    samt Volumes entfernen, womit die Sicherung die einzige Kopie ist.
docker compose -f docker-compose.dev.yml exec -T db \
  pg_restore --list < ~/portfolixir-backups/portfolixir-dev.dump | head
docker compose -f docker-compose.dev.yml down -v

# 3. Die Produktionsdatenbank, auf einem neuen Volume.
docker compose up -d db
```

Dann diese Datei ab Schritt 3 von „Wiederherstellen“ unten zurückspielen und
die Wiederherstellung prüfen.

## Sicherung und Wiederherstellung

Die ganze Instanz ist eine PostgreSQL-Datenbank, eine Sicherung ist also eine
`pg_dump`-Datei. Sie enthält **alle** Daten der Instanz: Wertpapiere, Kurse und
Wechselkurse, Portfolios, Depots und Geldkonten, jede Transaktion, die
Klassifizierungen mit ihren Zuordnungen, die SOLL-Pläne mit Kategorie- und
Positionszielen und die Cash-Ziele, die eigenen Regeln, Recherche-Log und
Termine, Steuerdaten und das Audit-Journal. Sie enthält **nicht** die `.env` —
diese Datei gehört ebenfalls an einen sicheren Ort: Ohne `POSTGRES_PASSWORD` und
die Tokens ist eine wiederhergestellte Datenbank zwar vollständig, die Instanz
muss aber neu konfiguriert werden. Sie enthält auch nicht die gespeicherten
Logos: Die sind Dateien im Volume `portfolixir-logos`, außerhalb der Datenbank
und des Release, und ein hochgeladenes oder von Hand gewähltes Logo gibt es nur
dort; das Volume wird deshalb neben dem Dump gesichert.

Die Befehle unten laufen in dem Verzeichnis, das `docker-compose.yml` und `.env`
enthält. PostgreSQL-Werkzeuge auf dem Host sind nicht nötig: Sie laufen im
`db`-Container. Sie schreiben die Sicherungen nach `~/portfolixir-backups`,
außerhalb des Checkouts, unter `umask 077`, damit nur du sie lesen kannst: ein
Dump enthält alle Daten der Instanz. `umask 077` gilt für den Rest dieser
Shell-Sitzung. Eine Kopie, die diesen Rechner verlässt, auf einer Platte oder
in einem Cloud-Ordner: vorher verschlüsseln, zum Beispiel mit `age -p` oder
`gpg --symmetric`.

### Sicherung anlegen

Vor der Sicherung die drei Zahlen und die Zahl der Trigger notieren, gegen die
die Wiederherstellung geprüft wird (siehe „Wiederherstellung prüfen“ unten).
Dann:

```bash
umask 077
mkdir -p ~/portfolixir-backups
docker compose exec -T db \
  pg_dump -U portfolixir -d portfolixir_prod --format=custom \
  > ~/portfolixir-backups/portfolixir-$(date +%F).dump
```

Die Instanz läuft währenddessen weiter; die Datei ist ein konsistenter Stand
eines Zeitpunkts. Ob die Datei lesbar ist, zeigt ihr Inhaltsverzeichnis:

```bash
docker compose exec -T db \
  pg_restore --list < ~/portfolixir-backups/portfolixir-2026-09-23.dump | head
```

Die gespeicherten Logos, aus dem laufenden Anwendungs-Container:

```bash
docker compose exec -T app tar -C /var/lib/portfolixir/logos -cf - . \
  > ~/portfolixir-backups/portfolixir-logos-$(date +%F).tar
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

# 3. Die Sicherung, in einer Transaktion: ganz oder gar nicht.
docker compose exec -T db \
  pg_restore -U portfolixir -d portfolixir_prod --no-owner --exit-on-error \
  --single-transaction < ~/portfolixir-backups/portfolixir-2026-09-23.dump \
  && echo "restore complete"

# 4. Nur wenn Schritt 3 ohne Fehler endete („restore complete“): die Instanz;
#    sie migriert die wiederhergestellte Datenbank nach vorn, wenn die
#    Sicherung aus einem älteren Release stammt.
docker compose up -d

# 5. Die gespeicherten Logos, in den laufenden Anwendungs-Container.
docker compose exec -T app tar -C /var/lib/portfolixir/logos -xf - \
  < ~/portfolixir-backups/portfolixir-logos-2026-09-23.tar
```

`--single-transaction` macht die Wiederherstellung zu einem Ganz-oder-gar-nicht:
beim ersten Fehler (`--exit-on-error`) wird alles zurückgerollt, was sie getan
hat, und die Datenbank bleibt leer statt halb gefüllt — einer halb gefüllten
können die Append-only- und Audit-Journal-Trigger fehlen, die die Daten
schützen und mit den Tabellen zurückkommen. Starte die Instanz erst nach einer
Wiederherstellung, die ohne Fehler endete: auf einer leeren Datenbank würde sie
die Migrationen ausführen und ohne Daten starten. Suche die Ursache und
wiederhole ab Schritt 2. Eine Sicherung lässt sich in dieselbe oder eine
neuere PostgreSQL-Hauptversion zurückspielen; das `db`-Image aus
`docker-compose.yml` ist das richtige.

### Wiederherstellung prüfen

Drei Zahlen vor der Sicherung und nach der Wiederherstellung vergleichen: den
Gesamtwert, die Anzahl der Bestände und eine bekannte Position. Auf der
Vermögensseite sind das die Summe oben, die Zeilen der Positionstabelle und eine
beliebige Zeile daraus. Vergleiche auch die Zahl der Trigger der Datenbank,
darunter die Append-only- und Audit-Journal-Wächter; eine Wiederherstellung,
die keinen verloren hat, zeigt dieselbe Zahl:

```bash
docker compose exec -T db psql -U portfolixir -d portfolixir_prod -tAc \
  "SELECT count(*) FROM pg_trigger WHERE NOT tgisinternal"
```

Über die API (das Token ist `PORTFOLIXIR_API_TOKEN` aus
der `.env`; `1` ist die Portfolio-ID, die der erste Aufruf liefert):

```bash
TOKEN=$(grep '^PORTFOLIXIR_API_TOKEN=' .env | cut -d= -f2-)
API=http://127.0.0.1:4000/api/v1
# Das Token erreicht curl über die Standardeingabe, nie über die Befehlszeile,
# wo jeder lokale Benutzer es in der Prozessliste lesen könnte.
api() { printf 'Authorization: Bearer %s\n' "$TOKEN" | curl -s -H @- "$API$1"; }

api /portfolios
api /portfolios/1/valuation   # "total_value"
api /portfolios/1/holdings    # ein Eintrag je Bestand
```

Die Zahlen sind Dezimal-Strings in voller Genauigkeit; eine Wiederherstellung,
die nichts verloren hat, zeigt sie Zeichen für Zeichen gleich. Der Ablauf wurde
am 2026-09-23 vollständig gegen den synthetischen Review-Datensatz mit der
mitgelieferten `docker-compose.yml` durchgespielt: Sicherung, ein neues
Datenbank-Volume, Wiederherstellung, und die drei Zahlen, die Zeilenzahl des
Audit-Journals und die eigenen Regeln stimmten überein. Die eine Transaktion
und die Trigger-Zahl kamen später hinzu (2026-09-25) und wurden mit denselben
PostgreSQL-Werkzeugen außerhalb von Compose geprüft, an einer
Wiederherstellung, die gelingt, und an einer, die abgewiesen wird.

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

Jedes Image, auf dem der Stack läuft, ist im Repository per Tag und Digest
gepinnt — die Erlang/OTP- und Debian-Basis-Images der Anwendung, die Node-Basis
des MCP-Begleiters und das Datenbank-Image —; eine Korrektur darin kommt also
mit der Version, die ihren Digest bewegt, und die Release-Notes sagen, wann ein
Upgrade eine solche Korrektur enthält. `docker compose pull db` und `--pull`
holen genau die Images, die die neue Version nennt.

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
  (`PORTFOLIXIR_UI_PASSWORD`) gesperrt. Ein allein gestartetes Release bindet
  Loopback; in Compose hält die Port-Zuordnung es auf dem Loopback des Hosts
  („Erreichbarkeit“ oben). In beiden Fällen weist es fremde `Host`-Namen ab
  (ADR-0045).
- Der MCP-Begleitdienst kapselt die lokale JSON-API und greift nicht direkt
  auf die Datenbank zu.
- Das Release protokolliert auf der Stufe `info`: die Anfragezeilen, den
  Socket-Verbindungsaufbau jeder Live-Seite mit herausgefiltertem CSRF-Token,
  Warnungen und Fehler. Die Datenbankabfragen, die Parameter jeder Anfrage
  und jedes Seitenereignisses und die Sitzungsinhalte, die die Stufe `debug`
  schreibt, bleiben aus dem Log.
- Das Release startet ohne Erlang-Distribution und öffnet deshalb keinen
  Listener zu den anderen Containern: `bin/portfolixir eval` funktioniert im
  Container, `remote` und `rpc` nicht.
- Dieses Setup konfiguriert keine Broker-Synchronisation, keine
  Bank-Synchronisation, keine Dokumentenaufnahme (über den Portfolio-
  Performance-CSV/JSON-Import hinaus), kein Trading, keine Zahlungen, keine
  Orders, kein Rebalancing und keine LLM-Funktionen.
- Die öffentliche Dokumentation wird mit GitHub Pages unter `portfolixir.app`
  veröffentlicht.
