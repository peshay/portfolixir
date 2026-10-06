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

Der erste Build zieht die festgelegten Basis-Images und lädt Debian-Pakete,
Hex-Pakete von hex.pm und npm-Pakete aus der npm-Registry. Hinter einem Proxy
gib ihn mit Dockers vordefinierten Proxy-Build-Argumenten in den Build
(`HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`; etwa
`docker compose build --build-arg HTTPS_PROXY=http://proxy.example:3128`) oder
über die Proxy-Konfiguration des Docker-Clients. Hinter einem Proxy, der TLS
aufbricht, gib seine CA als Build-Secret `build_ca` in den Build: Beide
Dockerfiles vertrauen ihr für ihre Downloads, die Debian-Pakete eingeschlossen,
und lassen sie aus den Images heraus, die sie ausliefern. Ohne das Secret
bleiben die Builds unverändert. Docker rechnet ein Secret nicht in seinen
Build-Cache ein: Baue nach einem Wechsel oder Wegfall der CA einmal mit
`--no-cache`.

```bash
docker build --secret id=build_ca,src=/pfad/zu/proxy-ca.crt -f Dockerfile.release .
docker build --secret id=build_ca,src=/pfad/zu/proxy-ca.crt mcp-server
```

Mit Compose nenne das Secret in einer `docker-compose.override.yml` neben der
`docker-compose.yml`, die Compose von selbst liest, und baue wie gewohnt:

```yaml
services:
  app:
    build:
      secrets: [build_ca]
  mcp:
    build:
      secrets: [build_ca]
secrets:
  build_ca:
    file: /pfad/zu/proxy-ca.crt
```

### Debian-Pakete: ein Proxy auf Loopback, ein gesperrter Mirror

`Dockerfile.release` installiert in beiden Stages vor allem anderen
Debian-Pakete, über `docker/apt-install.sh`. Mit dem Secret `build_ca` holt apt
die Quellen, die `deb.debian.org` nennen, über HTTPS und prüft sie gegen diese
CA, die es dort liest, wo Docker sie einhängt; so trägt auch ein Proxy, der nur
HTTPS tunnelt, diese Downloads. Dann vertraut apt allein dieser CA, und
`build_ca` darf deshalb ein Bündel sein: für einen Proxy, der nur tunnelt, das
CA-Bündel des Systems; für einen, der manche Hosts neu signiert und den Rest
tunnelt, seine CA und das Bündel des Systems zusammen,
`cat proxy-ca.crt /etc/ssl/certs/ca-certificates.crt > build-ca.pem`. Ohne das
Secret lädt apt wie bisher von `http://deb.debian.org`. Drei Fälle brauchen
mehr:

- **Ein Proxy auf dem Loopback des Hosts.** Ein Build läuft in einem eigenen
  Netz, ein Proxy, der auf `127.0.0.1` lauscht, ist für ihn nicht erreichbar.
  Baue mit dem Netz des Hosts, `--network host` (unter Compose
  `network: host` im `build:` des Dienstes), und gib den Proxy als
  Build-Argument mit.
- **Ein Host, dessen ausgehender Verkehr `deb.debian.org` sperrt.** Nenne die
  Debian-Mirrors, die er erreicht, in zwei Build-Argumenten, jedes eine
  Basis-URL wie `http://mirror.example/`. Unter `DEBIAN_MIRROR` liefert der
  Mirror das Debian-Archiv unter `debian` (die Suites `bookworm` und
  `bookworm-updates`), unter `DEBIAN_SECURITY_MIRROR` das Sicherheitsarchiv
  unter `debian-security` (`bookworm-security`). Viele öffentliche Mirrors
  führen kein `debian-security`; das zweite Argument nennt deshalb einen, der
  es führt, und ist es leer, gilt `DEBIAN_MIRROR`. Gib die Basis an, nicht den
  Archivpfad: `http://ftp.example.org/`, nicht `http://ftp.example.org/debian/`,
  das der Build ablehnt. Jeder Mirror behält das Schema, das du schreibst, auch
  mit dem Secret, und apt prüft jedes Paket gegen Debians Archivschlüssel,
  gleich welcher Mirror es liefert. Ein `https://`-Mirror wird gegen
  `build_ca` geprüft, ohne das Secret gegen den CA-Speicher der Stage; die
  Runtime-Stage hat keinen, bevor sie `ca-certificates` installiert, und dort
  hält der Build vor apt mit einer Zeile an. Gib ein CA-Bündel als Secret mit,
  oder nenne den Mirror mit `http://`. Eine Mirror-URL steht in der
  Build-Historie des Images und trägt deshalb keine Zugangsdaten: Eine mit
  Benutzername oder Token lehnt der Build ab. Leer ändern beide Argumente
  nichts.
- **Ein Host, der gar keinen Debian-Mirror erreicht.** Baue das Image der
  Anwendung auf einem Rechner, der einen erreicht, und bring es mit
  `docker save` und `docker load` hinüber. Portfolixir veröffentlicht kein
  Image: Ein Release ist ein Tag dieses Repositories, nie ein installierbares
  Artefakt, und das Image, das du hinüberbringst, ist dein eigener Build.

Ein Build über einen Proxy auf dem Loopback des Hosts, aus Mirrors:

```bash
docker build --network host --secret id=build_ca,src=/pfad/zu/build-ca.pem \
  --build-arg HTTPS_PROXY=http://127.0.0.1:3128 \
  --build-arg DEBIAN_MIRROR=http://mirror.example/ \
  --build-arg DEBIAN_SECURITY_MIRROR=http://security.example/ \
  -f Dockerfile.release .
```

Dasselbe unter Compose, in der `docker-compose.override.yml`:

```yaml
services:
  app:
    build:
      network: host
      secrets: [build_ca]
      args:
        HTTPS_PROXY: http://127.0.0.1:3128
        DEBIAN_MIRROR: http://mirror.example/
        DEBIAN_SECURITY_MIRROR: http://security.example/
  mcp:
    build:
      network: host
      secrets: [build_ca]
      args:
        HTTPS_PROXY: http://127.0.0.1:3128
secrets:
  build_ca:
    file: /pfad/zu/build-ca.pem
```

Der Umzug: Compose startet die Anwendung aus dem Image `<projekt>-app`, in den
Befehlen unten `portfolixir-app`; `docker compose config --images`, auf dem
Host ausgeführt, nennt den Namen, den es erwartet. Baue das Image unter diesem
Namen auf dem anderen Rechner, aus einem Checkout desselben Release und für die
Plattform des Hosts: `--platform linux/amd64` oder `linux/arm64`, je nachdem,
was `docker version` auf dem Host unter `OS/Arch` nennt, denn ein Image für eine
andere Plattform läuft dort nicht. Lade es auf dem Host, baue dort nur den
Begleitdienst, der keine Debian-Pakete installiert, und starte den Stack ohne
Build. Wiederhole den Umzug für jedes Release: Auf diesem Weg greift das
`docker compose build --pull` aus [Upgrade](#upgrade) nicht.

```bash
# Auf dem Rechner, der einen Mirror erreicht, für die Plattform des Hosts:
docker build --platform linux/amd64 -t portfolixir-app -f Dockerfile.release .
docker save -o portfolixir-app.tar portfolixir-app
# Auf dem Host, mit der hinüberkopierten portfolixir-app.tar:
docker load -i portfolixir-app.tar
docker compose build mcp
docker compose up -d --no-build
```

Das Entwicklungs-Image (`Dockerfile`) behält sein schlichtes `apt-get` von
`http://deb.debian.org`: `--network host` und der Umzug erreichen es;
`build_ca`, `DEBIAN_MIRROR` und `DEBIAN_SECURITY_MIRROR` nicht.

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
Base64 die Verbindungszeichenkette zerlegen würde. Erzeuge
`PORTFOLIXIR_UI_PASSWORD`, die Anmeldung der Web-Oberfläche, mit
`openssl rand -base64 24`, oder wähle eine Passphrase und setze sie in der
`.env` in einfache Anführungszeichen (`PORTFOLIXIR_UI_PASSWORD='…'`), denn
Compose liest ein `$` in einem Wert ohne Anführungszeichen als Variable. Leer
ist die Web-Oberfläche offen.

| Variable | Pflicht | Wirkung |
|---|---|---|
| `SECRET_KEY_BASE` | ja | Signiert das Sitzungs-Cookie; die Signatur-Salze werden daraus abgeleitet. |
| `POSTGRES_PASSWORD` | ja | Das Datenbankpasswort; die Anwendung baut ihre Verbindungszeichenkette daraus. |
| `PORTFOLIXIR_API_TOKEN` | ja | Das Bearer-Token der JSON-API und der Upstream-Aufrufe des MCP-Begleitdienstes. Die Compose-Datei gibt es der Anwendung unverändert und nennt es über `PORTFOLIXIR_API_PRINCIPAL` `mcp`, das Audit-Journal nennt also `mcp` für jeden Schreibzugriff des Begleitdienstes. |
| `PORTFOLIXIR_API_PRINCIPAL` | nein | Der Name, den das Audit-Journal für einen Schreibzugriff mit `PORTFOLIXIR_API_TOKEN` verbucht (1 bis 32 Zeichen aus `a-z`, `0-9`, `_` und `-`). Die Compose-Datei setzt ihn auf `mcp`; lass ihn dort unverändert. Ohne ihn tragen die Schreibzugriffe dieses Tokens keinen Namen. Ein Name, den auch `PORTFOLIXIR_API_TOKENS` verwendet, stoppt die Anwendung beim Start. |
| `PORTFOLIXIR_API_TOKENS` | nein | Weitere API-Tokens als `name=token`-Einträge, durch Kommas getrennt (`scripts=<token>`; ein Name hat 1 bis 32 Zeichen aus `a-z`, `0-9`, `_` und `-`; ein Token hier kann kein Komma enthalten, das `openssl rand -base64 48` nie ausgibt; Leerzeichen um einen Namen, ein Token und ein Komma werden ignoriert). Ein Schreibzugriff mit einem davon wird unter seinem Namen im Journal verbucht. Jedes Token folgt denselben Regeln, und ein Name oder ein Token darf nur einmal vorkommen, `PORTFOLIXIR_API_TOKEN` eingeschlossen, sonst startet die Anwendung nicht und nennt den Eintrag. Jedes Token hat dieselbe volle Befugnis; der Name ordnet zu, er beschränkt nicht. |
| `PORTFOLIXIR_MCP_TOKEN` | ja | Das Bearer-Token, das ein MCP-Client dem Begleitdienst vorlegt. |
| `PORTFOLIXIR_UI_PASSWORD` | nein | Gesetzt verlangt die Web-Oberfläche eine Anmeldung (ADR-0045); erzeuge es mit `openssl rand -base64 24`. Ungesetzt oder leer ist die Oberfläche offen — vertretbar nur hinter einer Authentifizierung des Reverse-Proxys. Eine Änderung beendet jede Anmeldung, die mit dem alten Passwort erfolgt ist. |
| `PORTFOLIXIR_SESSION_DAYS` | nein | Wie viele Tage eine Anmeldung gilt (Standard 30). Das Fenster wandert: die Nutzung der Instanz verlängert es, gefragt wird also erst nach einer vollen Periode ohne Nutzung. `0` schaltet den serverseitigen Ablauf ab: der Browser vergisst die Anmeldung beim Schließen, eine Kopie des Sitzungs-Cookies läuft aber nie ab; wähle deshalb lieber eine Zahl von Tagen. Eine Abmeldung beendet die Anmeldung nur in diesem Browser, eine vorher genommene Kopie des Sitzungs-Cookies bleibt gültig; um jede Anmeldung zu beenden, ändere `PORTFOLIXIR_UI_PASSWORD` oder rotiere `SECRET_KEY_BASE`. |
| `PHX_HOST` | nein | Der Name, unter dem der Reverse-Proxy ausliefert (Standard `localhost`). Anfragen unter einem anderen `Host` werden mit 421 abgewiesen. |
| `PORTFOLIXIR_ALLOWED_HOSTS` | nein | Weitere Namen, kommagetrennt (eine LAN-Adresse, ein zweiter Proxy-Name). Die Compose-Datei ergänzt `app`, den Namen, unter dem der MCP-Begleitdienst die Anwendung erreicht. |
| `PHX_FORCE_SSL` | nein | `true` leitet unverschlüsseltes HTTP auf HTTPS um und setzt HSTS. Setze es, sobald der Reverse-Proxy TLS terminiert und `X-Forwarded-Proto` von Loopback oder von einer in `PORTFOLIXIR_TRUSTED_PROXIES` genannten Adresse sendet; standardmäßig aus, weil eine Loopback-Instanz kein TLS hat, auf das sie umleiten könnte, und die Anwendung TLS nie selbst terminiert. `localhost` und `127.0.0.1` werden nie umgeleitet: der Health-Check des Containers und ein MCP-Begleitdienst außerhalb von Compose unter seiner Standard-Basis-URL `http://127.0.0.1:4000`. |
| `PORTFOLIXIR_FORCE_SSL_EXCLUDED_HOSTS` | nein | Host-Namen, durch Kommas getrennt, die `PHX_FORCE_SSL` bei unverschlüsseltem HTTP belässt: keine Umleitung und kein HSTS für eine Anfrage unter ihnen. Die Compose-Datei setzt sie auf `app`, den Namen, unter dem der MCP-Begleitdienst die Anwendung im Compose-Netz ohne TLS aufruft; lass sie in Compose unverändert. Nenne hier nur interne Namen, nie den, den der Reverse-Proxy ausliefert. |
| `PORTFOLIXIR_TRUSTED_PROXIES` | nein | Adressen oder CIDR-Blöcke, kommagetrennt, deren `X-Forwarded-For` (die Quelle der Anmelde- und Token-Drossel) und `X-Forwarded-Proto` (das Schema) die Anwendung glaubt. Leer zählt die Drossel die verbindende Adresse, hinter einem Proxy also den Proxy, und nur ein Proxy auf Loopback kann eine Anfrage als HTTPS kennzeichnen. |
| `PORTFOLIXIR_MCP_ALLOWED_HOSTS` | nein | Weitere `Host`-Namen, unter denen der MCP-Begleitdienst antwortet (ein Proxy-Name), kommagetrennt. |
| `PORTFOLIXIR_MCP_READ_ONLY` | nein | `true` macht den MCP-Begleitdienst nur lesend: Er listet und ruft nur die Tools auf, die nichts ändern (standardmäßig aus; jeder andere Wert als `true`, `false`, `1`, `0` oder leer stoppt ihn mit dem Namen der Variable). Er schränkt den Begleitdienst ein, nicht `PORTFOLIXIR_API_TOKEN`, das über die API weiterhin schreiben kann. Er ist dasselbe wie `PORTFOLIXIR_MCP_PROFILE=read`. |
| `PORTFOLIXIR_MCP_PROFILE` | nein | Das Tool-Profil des MCP-Begleitdienstes: `read` (nur die Tools, die nichts ändern), `book` (die Lesezugriffe, das Anlegen und die ersetzenden Schreibzugriffe, die derselbe Schreibzugriff mit dem früheren Wert rückgängig macht, außer dass eine Rückbenennung den Zwischennamen als früheren Namen behält und ein Upsert über einem Anbieterdatum bis zur Admin-Kursfreigabe manuell bleibt; kein Entfernen, Zusammenführen, keine ISIN-Änderung und kein Stilllegen einer Regel) oder `full` (jedes Tool). Leer ist `full`, oder `read` bei `PORTFOLIXIR_MCP_READ_ONLY=true`; neben diesem Schalter stoppen `book` oder `full` den Begleitdienst mit beiden Variablennamen, ebenso jeder andere Wert. Es schränkt den Begleitdienst ein, nicht `PORTFOLIXIR_API_TOKEN`. Siehe [API und MCP](integration/api-and-mcp.html). |
| `TZ` | nein | Die Zeitzone, die entscheidet, welcher Tag „heute“ ist, als tz-Name (`Europe/Berlin`); leer ist UTC. Jede Datumsprüfung — eine Abrechnung oder ein Kurs nicht in der Zukunft, eine Regelversion nicht rückdatiert — liest den Kalendertag der Anwendung in dieser Zone, und jede Datenbanksitzung übernimmt beim Verbinden dieselbe Zone, sodass die Datumsprüfungen der Datenbank mit ihr übereinstimmen; die Einstellung `timezone` des Datenbankservers spielt dann keine Rolle. Ein Wert, den die Datenbank nicht als Zonennamen kennt, wird beim Start einmal protokolliert, und die Sitzung behält die Zone des Servers. |
| `PORTFOLIXIR_BACKGROUND_FETCH` | nein | `off` (oder `0`, `false`, `no`) lässt die Logo-Suche und die geplanten Kurs- und Devisen-Downloads ab dem Start aus, sodass die Instanz nur nach außen verbindet, wenn jemand sie darum bittet. Nicht gesetzt oder jeder andere Wert lässt sie an; der Schalter kann das Laden nur abschalten. |
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

Nach außen lädt die Anwendung Logos und folgt Weiterleitungen eines Anbieters
nur zu öffentlichen Adressen (`SECURITY.md`). Nach eigenem Zeitplan lädt das
Release außerdem die Euro-Referenzkurse der EZB
(`https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml`), fünf
Sekunden nach dem Start und dann alle 12 Stunden, und alle 6 Stunden die
Kurshistorie jedes Wertpapiers, das einen Kursanbieter hat. Beide Zeitpläne
und die Logo-Suche sind in einem Release eingeschaltet (`config/prod.exs`).
`PORTFOLIXIR_BACKGROUND_FETCH=off` lässt alle drei ab dem Start aus: Die schon
gespeicherten Kurse und Devisenkurse bleiben, wie sie sind, und jede Zahl wird
aus ihnen berechnet. Der Schalter stoppt, was die Instanz von sich aus tut,
nicht, worum jemand sie bittet. Ein Kurs- oder Devisenabgleich, den jemand auf
einer Seite oder über den Agenten startet, eine Logo-Aktualisierung und die
Wertpapiersuche erreichen ihre Anbieter weiterhin. Ein Host, der sie gar nicht
erreichen darf, braucht deshalb weiterhin eine Sperre für ausgehende
Verbindungen. Nutze auf einem
reinen IPv6-Host hinter DNS64 das bekannte NAT64-Präfix `64:ff9b::/96`: Eine Adresse
darin wird nach der IPv4-Adresse beurteilt, die sie trägt. Das Präfix für
lokale Übersetzung `64:ff9b:1::/48` ist wie die privaten Bereiche ein Block für
besondere Zwecke; jede Adresse, die ein DNS64 darin bildet, wird deshalb
abgelehnt, und Logo-Downloads und weitergeleitete Anbieteranfragen scheitern.

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

Über einen veröffentlichten Port erreicht jeder Client auf dem Host einen
Container von der einen Gateway-Adresse der Docker-Bridge aus (siehe
„Reverse-Proxy“ unten). Der MCP-Begleitdienst zählt fehlgeschlagene Tokens je
verbindender Adresse, so wie die Anwendung fehlgeschlagene Anmeldungen zählt;
für ihn ist also jeder Client auf dem Host eine Quelle: ein Prozess auf dem
Host, der ein falsches Token schickt, sperrt auch deinen Agenten aus, nach
wiederholten Fehlschlägen und mit jedem weiteren länger bis zu einer
Obergrenze, und solange die Sperre gilt, wird auch ein richtiges Token mit
`429` beantwortet. Die Zählungen liegen
nur im Speicher:
`docker compose restart mcp` löscht sie sofort.

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
`PORTFOLIXIR_TRUSTED_PROXIES=172.18.0.1`. Docker wählt diese Adresse, wenn es
das Netzwerk des Stacks anlegt; prüfe sie erneut, wann immer das Netzwerk des
Stacks neu angelegt wird, etwa nach einem `docker compose down`: Eine Adresse,
die nicht mehr passt, ist so gut wie keine. Nenne die eine Adresse statt eines
privaten Blocks: jede Adresse in einem genannten Block wird geglaubt, ein Block
vertraut also auch allem anderen in diesem Netz. Auch die eine Adresse wird
geteilt: über einen veröffentlichten Port kommt nicht nur der Proxy, sondern
jeder Client auf dem Host kommt von derselben Adresse, und wer sie nennt,
glaubt den Weiterleitungs-Headern jedes Prozesses auf dem Host. Ein solcher
Prozess kann dann die Adresse wählen, unter der die Drossel seine
fehlgeschlagenen Anmeldungen zählt, oder das Schema setzen. Um allein dem
Proxy zu glauben, hänge den Proxy an das Netzwerk des Stacks und nenne seine
Container-Adresse (`docker network inspect` zeigt sie; auch sie wird erneut
geprüft, wenn das Netzwerk neu angelegt wird); sonst nenne das Gateway im
Wissen, dass damit jeder Prozess auf dem Host vertraut wird. Mit der genannten Adresse
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
Ein Neustart der Anwendung löscht die Zählungen, die der Obergrenze
eingeschlossen, weil sie nur im Speicher liegen: `docker compose restart app`
gibt die Anmeldung sofort wieder frei. `PORTFOLIXIR_UI_PASSWORD` in `.env` zu
ändern und `docker compose up -d` auszuführen, legt den Container neu an und
löscht sie ebenso.
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
   die Variable, dass der Header fehlt oder nicht geglaubt wird. Den einen
   Fall, den die Anwendung selbst sehen kann, nennt eine Warnung beim Start:
   `PHX_FORCE_SSL` an, der Listener über Loopback hinaus gebunden
   (`PHX_BIND_ALL`, wie in Compose) und `PORTFOLIXIR_TRUSTED_PROXIES` nicht
   gesetzt, nicht lesbar oder ohne Adresse jenseits von Loopback in der
   IP-Familie des Listeners (eine Adresse der anderen Familie passt nie).
   Eine zweite Warnung zitiert
   jeden Eintrag der Variable, den sie nicht lesen konnte, gleich wie der Rest
   eingestellt ist; die Anwendung startet trotzdem. Der
   MCP-Begleitdienst ruft die Anwendung im Compose-Netz unverschlüsselt unter
   `app` auf, das `PORTFOLIXIR_FORCE_SSL_EXCLUDED_HOSTS` ausnimmt; seine Aufrufe
   werden also nie umgeleitet. Ein Begleitdienst außerhalb von Compose ruft
   `127.0.0.1` auf, das ebenfalls nie umgeleitet wird. Eine Umleitung lehnt
   der Begleitdienst mit Namen ab, statt ihr zu folgen (E25).
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

Er ist ein eigenes Compose-Projekt, `portfolixir-dev`, mit einem eigenen
Datenbank-Volume (#932): Seine Container und sein Zurücksetzen berühren nie
einen Produktions-Stack, der aus demselben Checkout gestartet wurde. Beide
veröffentlichen dieselben Ports auf dem Host, es läuft also immer nur einer.
Das Zurücksetzen der Entwicklung entfernt nur die Entwicklungsdatenbank:

```bash
docker compose -f docker-compose.dev.yml down -v
```

### Umzug vom Entwicklungs-Stack

Vor dem Produktions-Release (Sprint 10, #760) war das dokumentierte Deployment
dieser Entwicklungs-Stack, damals `docker-compose.yml` genannt, mit auf jeder
Schnittstelle offenen Ports. Eine Instanz, die noch so läuft, zieht per
Sicherung und Wiederherstellung auf den Produktions-Stack um, nicht an Ort und
Stelle: die Produktionsdatenbank wird nur auf einem leeren Volume angelegt, und
das alte Volume behält den Entwicklungsbenutzer.

Eine solche Instanz, wie auch ein Entwicklungs-Stack, der in einem Checkout vor
#932 gestartet wurde, läuft unter dem Compose-Projekt des Checkout-Verzeichnisses,
demselben, das der Produktions-Stack verwendet, und hält ihre Datenbank in dem
Volume, das der Produktions-Stack `portfolixir-postgres-data` nennt. Die
Entwicklungsdatei benennt seit #932 ein eigenes Projekt und erreicht dieses
Volume nicht mehr; die Befehle unten sprechen die alte Instanz deshalb über
`docker-compose.yml` an. Im Checkout, nachdem die aktuelle Version geholt und
`.env` geschrieben ist (siehe „Geheimnisse und Einstellungen“ oben):

```bash
# 1. Eine Sicherung der Datenbank der alten Instanz, solange sie noch läuft.
umask 077
mkdir -p ~/portfolixir-backups
docker compose exec -T db \
  pg_dump -U postgres -d portfolixir_dev --format=custom \
  > ~/portfolixir-backups/portfolixir-dev.dump

# 2. Die Datei zeigt ihr Inhaltsverzeichnis; erst dann die alten Container
#    samt ihrem Datenbank-Volume entfernen, womit die Sicherung die einzige
#    Kopie ist.
docker compose exec -T db \
  pg_restore --list < ~/portfolixir-backups/portfolixir-dev.dump | head
docker compose down -v

# 3. Die Produktionsdatenbank, auf einem neuen Volume.
docker compose up -d db
```

Dann diese Datei ab Schritt 3 von „Wiederherstellen“ unten zurückspielen und
die Wiederherstellung prüfen. Die beiden Build-Caches des alten Stacks,
`app-deps` und `app-build`, bleiben als Volumes unter dem Projektnamen des
Checkouts zurück: `docker volume ls` listet sie, `docker volume rm` entfernt
sie.

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
und die Trigger-Zahl kamen später hinzu (2026-09-24) und wurden mit denselben
PostgreSQL-Werkzeugen außerhalb von Compose geprüft, an einer
Wiederherstellung, die gelingt, und an einer, die abgewiesen wird.

## Zurücksetzen

Ein Zurücksetzen löscht die Daten der Instanz: `docker compose down -v`
entfernt die Volumes des Stacks, das Datenbank-Volume
`portfolixir-postgres-data` mit allen Einträgen und das Logo-Volume
`portfolixir-logos`, und der nächste Start legt eine leere Datenbank an. Lege
vorher eine Sicherung an, wie unter „Sicherung anlegen“ oben, solange die
Instanz noch läuft:

```bash
umask 077
mkdir -p ~/portfolixir-backups
docker compose exec -T db \
  pg_dump -U portfolixir -d portfolixir_prod --format=custom \
  > ~/portfolixir-backups/portfolixir-$(date +%F).dump
docker compose exec -T app tar -C /var/lib/portfolixir/logos -cf - . \
  > ~/portfolixir-backups/portfolixir-logos-$(date +%F).tar
docker compose exec -T db \
  pg_restore --list < ~/portfolixir-backups/portfolixir-$(date +%F).dump \
  > /dev/null && echo "backup reads"
```

Erst wenn der letzte Befehl `backup reads` ausgegeben hat, zurücksetzen. Die
Sicherung ist danach die einzige Kopie der Daten, und „Wiederherstellen“ oben
spielt sie zurück:

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

Beim Upgrade von 0.15.x oder älter erreichen vier Änderungen des
Sicherheitsdurchgangs eine Instanz, die schon läuft. Prüfe sie vor dem `up`:

- **Die Adresse des Proxys.** `X-Forwarded-Proto` wird jetzt nur noch von
  Loopback und von den in `PORTFOLIXIR_TRUSTED_PROXIES` genannten Adressen
  geglaubt. Ein Reverse-Proxy, der den Container über die Docker-Bridge
  erreicht, wie es jeder Proxy über den veröffentlichten Port tut, ist keins
  von beidem, bis er genannt ist. Ohne ihn leitet `PHX_FORCE_SSL=true` jede
  Anfrage in einer Schleife um, und ohne `PHX_FORCE_SSL` verliert das
  Sitzungs-Cookie `Secure`, ohne dass etwas darauf hinweist. Nenne das
  Bridge-Gateway oder die eigene Adresse des Proxys im Netzwerk des Stacks vor
  dem Upgrade („Reverse-Proxy“ oben).
- **Eine Anmeldung.** Eine Sitzung ist jetzt an das UI-Passwort gebunden, und
  eine Sitzung aus einem früheren Release trägt keine Bindung; jeder Browser
  meldet sich nach dem Upgrade einmal neu an.
- **Die Untergrenze des MCP-Tokens.** Der Begleitdienst weist jetzt ein
  `PORTFOLIXIR_MCP_TOKEN` ab, das kürzer als 32 Bytes oder ein Platzhalter
  ist, wie die Anwendung ein solches API-Token schon abwies, und hält mit dem
  Namen der Variable an.
- **Die Untergrenze des geheimen Schlüssels.** Die Anwendung weist einen
  `SECRET_KEY_BASE` ab, der kürzer als 64 Bytes, ein Platzhalter oder ein in
  diesem Repository committeter Wert ist, und hält mit dem Namen der Variable
  an. Ein neuer `SECRET_KEY_BASE` beendet jede Sitzung.

Ersetze einen abgewiesenen Wert durch die Ausgabe von
`openssl rand -base64 48`, wie „Geheimnisse und Einstellungen“ oben
beschreibt.

Zwei Migrationen desselben Durchgangs prüfen die Daten, die eine Instanz schon
hält. Das Release migriert, bevor es startet; eine Migration, die anhält,
verhindert also den Start des neuen Release:

- **Eine Positionszeile je Wertpapier in einem Plan.** Ein Plan, der ein
  Wertpapier unter zwei Kategorien führt, hält das Upgrade mit einem Fehler
  an, der jeden Plan, jedes Wertpapier und jede `portfolio_targets`-Zeile
  nennt; welche Zeile bleibt, entscheidest du. Spiele die vor dem Upgrade
  genommene Sicherung zurück, starte darauf das vorige Release (seinen Tag
  auschecken, bauen, `up`), entferne in dessen Plan-Editor alle Zeilen jedes
  genannten Paars bis auf eine, nimm eine neue Sicherung und führe das Upgrade
  erneut aus. Wer vor dem Upgrade jeden Plan auf ein doppelt geführtes
  Wertpapier prüft, spart sich den Umweg.
- **Schreibweisen von Steuerpflichtigen und Banken.** Namen von Inhabern und
  Instituten, die mit einem geschützten Leerzeichen, einem unsichtbaren
  Zeichen oder einem zerlegten Buchstaben erfasst wurden, werden so
  gespeichert, wie ein neuer Schreibvorgang sie speichert, jede Änderung im
  Prüfprotokoll. Ein Name, der danach einem anderen Eintrag desselben
  Schlüssels gliche, bleibt, wie er war, und wird im Log genannt
  (`tax identity backfill`); das Upgrade läuft weiter, und du korrigierst oder
  entfernst einen der beiden Einträge auf der Steuerseite.

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
installieren und starten. `npm ci` installiert genau die Versionen aus
`package-lock.json`, und `--ignore-scripts` verhindert, dass beim Installieren
Skripte der Abhängigkeiten auf Ihrem Rechner laufen — dieselbe Installation,
die CI und das Image des Begleitdienstes ausführen:

```bash
npm ci --ignore-scripts --prefix mcp-server
npm run build --prefix mcp-server
```

Über stdio startet der MCP-Client den Begleitdienst, nicht eine Shell: Der
Client führt `node mcp-server/dist/index.js` mit der Adresse und dem Token der
API in seiner Umgebung aus. [Einen Agenten verbinden](integration/connect-an-agent.html)
gibt die Client-Konfiguration für jeden Transport.

## Versionen und Rollback

Jeder Merge, der ausgelieferten Code ändert, wird mit einer
Kalenderversion getaggt (`YYYY.M.N`, das `N`-te Release des Monats; bis
September 2026 lautete das Schema `X.Y.Z` und endet bei `0.14.0`) und
automatisch als GitHub-Release mit generierten Notizen und der ausgelieferten
API-Vertragsversion veröffentlicht. Ein
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
- Jede Anfrage und jede offene Seite läuft in einem eigenen Prozess unter
  einer Heap-Grenze von 512 MiB, die die großen Binärdaten des Prozesses
  mitzählt: Eine Anfrage, die darüber wächst, scheitert allein und wird
  protokolliert, statt den Speicher der Maschine zu erschöpfen. Kein
  gewöhnliches Lesen oder Schreiben kommt in ihre Nähe; `max_heap_bytes`
  unter `PortfolixirWeb.HeapCap` in `config/config.exs` ändert sie. Der
  Arbeitsspeicher-Cache abgeleiteter Kennzahlen hält sein eigenes Budget ein
  (5000 Einträge, 128 MiB).
- Das Release startet ohne Erlang-Distribution und öffnet deshalb keinen
  Listener zu den anderen Containern: `bin/portfolixir eval` funktioniert im
  Container, `remote` und `rpc` nicht.
- Dieses Setup konfiguriert keine Broker-Synchronisation, keine
  Bank-Synchronisation, keine Dokumentenaufnahme (über den Portfolio-
  Performance-CSV/JSON-Import hinaus), kein Trading, keine Zahlungen, keine
  Orders, kein Rebalancing und keine LLM-Funktionen.
- Die öffentliche Dokumentation wird mit GitHub Pages unter `portfolixir.app`
  veröffentlicht.
