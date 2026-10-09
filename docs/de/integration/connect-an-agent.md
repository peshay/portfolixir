---
layout: docs
title: Einen Agenten verbinden
description: MCP-Client-Konfigurationen zum Kopieren für den Portfolixir-Begleitdienst, über stdio und über HTTP.
lang: de
lang_en: /integration/connect-an-agent.html
lang_de: /de/integration/connect-an-agent.html
---

# Einen Agenten verbinden

Der MCP-Begleitdienst in `mcp-server/` gibt einem Agenten die Tools von
Portfolixir und zwei Prompts. Er ruft die JSON-API der Instanz mit
`PORTFOLIXIR_API_TOKEN` auf und sonst nichts. Verbinden Sie ihn auf einem von
zwei Wegen: Der Client des Agenten startet ihn als lokalen Prozess (stdio),
oder der Client erreicht den Begleitdienst, den der Compose-Stack ohnehin
betreibt (HTTP).

Die Konfigurationen unten nutzen die Form `mcpServers`, die die meisten
MCP-Clients lesen. Die Schlüsselnamen unterscheiden sich zwischen Clients ein
wenig (etwa der Transport-Schlüssel eines HTTP-Servers); prüfen Sie die
Schreibweise in der Dokumentation Ihres Clients.

## Zuerst ein Profil wählen

`PORTFOLIXIR_MCP_PROFILE` entscheidet, welche Tools der Agent sieht und
aufrufen darf:

| Profil | Der Agent kann |
|---|---|
| `read` | alles lesen und nichts ändern |
| `book` | lesen, anlegen und die ersetzenden Schreibzugriffe ausführen (Ändern, Upsert, Setzen), die derselbe Schreibzugriff mit dem früheren Wert rückgängig macht; kein Entfernen, Zusammenführen, keine ISIN-Änderung, kein Stilllegen einer Regel und keine Kursfreigabe |
| `full` (Standard) | jedes Tool aufrufen |

Zwei der Schreibzugriffe, die `book` behält, hinterlassen einen Rest, den ihr
Gegenstück nicht beseitigt: Eine Rückbenennung stellt den Namen eines Kontos
wieder her, behält aber den Zwischennamen als früheren Namen, und ein Upsert
über einem Datum mit Anbieterdaten hinterlässt dort einen manuellen Kurs; nur
die Admin-Tools `remove_former_name` und `portfolixir.quotes.release`
beseitigen sie.

`book` passt zu einem Agenten, der eine Instanz einrichtet und in sie bucht,
`read` zu einem, der nur berichtet. Ein Profil schränkt den Begleitdienst ein,
nicht das API-Token: Ein Agent mit einer Shell und dem Token kann weiterhin
jede Route der API aufrufen. Die Admin-Menge, die `book` weglässt, und warum,
steht in [API und MCP](api-and-mcp.html#mcp-tools).

## Über stdio: Der Client startet den Begleitdienst

Bauen Sie den Begleitdienst einmal, mit Node 24:

```bash
npm ci --ignore-scripts --prefix mcp-server
npm run build --prefix mcp-server
```

Tragen Sie ihn dann in die Konfiguration des Clients ein, mit dem absoluten
Pfad Ihres Checkouts und, als `PORTFOLIXIR_API_TOKEN`, dem Token, mit dem die
Instanz läuft: aus der `.env` für Compose, dem Wert, den Sie für einen aus dem
Quellcode gestarteten Server exportiert haben:

```json
{
  "mcpServers": {
    "portfolixir": {
      "command": "node",
      "args": ["/absoluter/pfad/zu/portfolixir/mcp-server/dist/index.js"],
      "env": {
        "PORTFOLIXIR_API_BASE_URL": "http://127.0.0.1:4000",
        "PORTFOLIXIR_API_TOKEN": "<das Token, mit dem die Instanz läuft>",
        "PORTFOLIXIR_MCP_PROFILE": "book"
      }
    }
  }
}
```

stdio ist der Standard-Transport des Begleitdienstes, `PORTFOLIXIR_MCP_TRANSPORT`
braucht also keinen Wert. Das Token steht jetzt auch in der
Konfigurationsdatei des Clients: Halten Sie diese Datei nur für Sie lesbar.

## Über HTTP: Der Begleitdienst des Compose-Stacks

`docker compose up --build -d` startet den Begleitdienst mit der Anwendung, auf
der Loopback-Schnittstelle des Hosts. Setzen Sie das Profil in der `.env`
(`PORTFOLIXIR_MCP_PROFILE=book`), erstellen Sie den Dienst mit
`docker compose up -d mcp` neu und richten Sie den Client darauf aus:

```json
{
  "mcpServers": {
    "portfolixir": {
      "type": "http",
      "url": "http://127.0.0.1:4001/mcp",
      "headers": {
        "Authorization": "Bearer <PORTFOLIXIR_MCP_TOKEN aus .env>"
      }
    }
  }
}
```

Der Transport ist MCP Streamable HTTP: Jede JSON-RPC-Nachricht ist ein `POST`
an `/mcp`, ihr `Accept`-Header muss `application/json` und `text/event-stream`
nennen (eine Anfrage, die nur eines nennt, wird mit `406` beantwortet), und die
Antwort kommt als Event-Stream zurück. Der Begleitdienst betreibt ihn
zustandslos: Er vergibt keine `Mcp-Session-Id`, baut für jede Anfrage einen
frischen Server und sendet zwischen Anfragen keine Benachrichtigung. Ein
MCP-Client erledigt das alles, sobald URL und Header gesetzt sind.

Jede Anfrage trägt den Header `Authorization: Bearer
<PORTFOLIXIR_MCP_TOKEN>`. Ein falsches Token ergibt `401`, und wiederholt
falsche Tokens von einer Adresse sperren diese Adresse für eine wachsende
Zeit, beantwortet mit `429`; die Sperre trifft nur falsche Tokens: Ein
richtiges Token kommt durch, solange sie gilt (#974). Hinter dem
veröffentlichten Port ist jeder Client des Hosts diese eine Adresse;
`docker compose restart mcp` setzt die Zählung zurück. Der
Begleitdienst antwortet nur unter den Loopback-Namen mit seinem Port
(`127.0.0.1:4001`, `localhost:4001`, `[::1]:4001`) und nimmt die Anfrage
eines Browsers nur von diesen Origins über `http://` an. Tragen Sie in
`PORTFOLIXIR_MCP_ALLOWED_HOSTS` hinter einem Reverse Proxy dessen Namen ein,
die Adresse mit ihrem Port, wenn der Begleitdienst auf einem anderen Host-Port
veröffentlicht ist (`127.0.0.1:14001`), oder Host und Port eines MCP-Clients
im Browser, der von einem anderen Origin ausgeliefert wird
(`localhost:6274`).

## Die Variablen des Begleitdienstes

| Variable | Standard | Was sie tut |
|---|---|---|
| `PORTFOLIXIR_API_TOKEN` | keiner, Pflicht | Das API-Token, mit dem der Begleitdienst die Instanz aufruft. |
| `PORTFOLIXIR_API_BASE_URL` | `http://127.0.0.1:4000` | Wo die API der Instanz antwortet, ohne Weiterleitung. |
| `PORTFOLIXIR_MCP_TRANSPORT` | `stdio` | `stdio`, oder `http` für den eigenen Listener des Begleitdienstes. |
| `PORTFOLIXIR_MCP_TOKEN` | keiner, Pflicht für `http` | Das Bearer-Token, das HTTP-Clients vorlegen: mindestens 32 Bytes und nie ein Platzhalter (`openssl rand -base64 48`). |
| `PORTFOLIXIR_MCP_HOST` | `127.0.0.1` | Die Adresse, an die der HTTP-Listener bindet; nicht gesetzt, leer oder nur Leerzeichen ist `127.0.0.1`, nie jede Schnittstelle. Eine IPv6-Adresse (`::1`) antwortet in Klammern, `[::1]:4001`. |
| `PORTFOLIXIR_MCP_PORT` | `4001` | Der Port, an den der HTTP-Listener bindet, eine ganze Zahl von 1 bis 65535; jeder andere Wert oder ein Port, den ein anderer Prozess hält, stoppt den Begleitdienst mit dem Exit-Status 1 und einer Zeile, die die Ursache nennt. |
| `PORTFOLIXIR_MCP_ALLOWED_HOSTS` | leer | Weitere `Host`-Namen, unter denen der HTTP-Listener antwortet, durch Kommas getrennt, jeder auch als Browser-Origin über `http://` oder `https://` zugelassen: ein Proxy-Name oder ein `Host:Port` wie ein veröffentlichter Port oder das Origin eines Browser-Clients. |
| `PORTFOLIXIR_MCP_PROFILE` | leer, also `full` | `read`, `book` oder `full`. |
| `PORTFOLIXIR_MCP_READ_ONLY` | `false` | `true` ist das Profil `read`; neben `book` oder `full` stoppt es den Begleitdienst. |

Die Compose-Datei setzt Transport, Host und Port für ihren eigenen Dienst; ein
Begleitdienst, den Sie selbst starten, liest sie aus seiner Umgebung.

## Erste Schritte

Bitten Sie den Agenten, den Prompt `first_setup` auszuführen: Er prüft die
Instanz und das Profil, liest, was vorhanden ist, schlägt eine Struktur aus
Konten, Depots, Buckets und Views vor und schreibt nichts ohne Ihre
Bestätigung. Für einen Bank- oder Broker-Export, den Portfolixir nicht liest,
nutzen Sie den Prompt `import_converter`: Der Agent schreibt einen Konverter,
der auf Ihrem Rechner läuft, und übergibt Ihnen eine Datei für die
Import-Seite (Transaktionen → Import, `/imports`), wo Sie sie in der Vorschau
prüfen und übernehmen.
