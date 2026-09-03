---
layout: docs
title: API und MCP
description: Referenz zur Portfolixir-JSON-API und zum MCP-Begleitdienst.
lang: de
lang_en: /integration/api-and-mcp.html
lang_de: /de/integration/api-and-mcp.html
---

# API und MCP

Portfolixir stellt den unterstützten lokalen Workflow über die JSON-API unter
`/api/v1` bereit. Der MCP-Begleitdienst in `mcp-server/` ist bewusst dünn:
MCP-Tools rufen ausschließlich die JSON-API auf und greifen nicht direkt auf die
Datenbank zu.

## Authentifizierung

API-Anfragen benötigen ein lokales Bearer-Token:

```text
Authorization: Bearer <PORTFOLIXIR_API_TOKEN>
```

Der MCP-Begleitdienst nutzt `PORTFOLIXIR_API_TOKEN`, um Portfolixir aufzurufen.
`PORTFOLIXIR_MCP_TOKEN` ist für den HTTP-Transport erforderlich, damit sich
lokale HTTP-Clients beim Begleitdienst authentifizieren können.

## Datenregeln

Alle Antworten nutzen JSON-Umschläge mit entweder `data` oder `errors`.
Finanz-Decimals werden als Strings serialisiert, einschließlich Mengen, Preise,
Gebühren, Steuern, Kurs-Schlusswerte und monetärer Summen. Request-Payloads für
diese Werte sollten ebenfalls Strings senden.

`DELETE /api/v1/securities/:id` ist die Erfolgs-Ausnahme: es liefert
`204 No Content` mit leerem Body. Clients sollten für diese erfolgreiche
Löschantwort keinen JSON-Body parsen.

**Delta-Reads (FR-38).** Die beiden wiederkehrenden Sync-Reads — `GET
/api/v1/transactions` und `GET /api/v1/securities` — akzeptieren
`?since=<ISO8601>` (Datetime mit Offset, naive UTC-Datetime oder ein reines
Datum als Tagesbeginn, UTC) und liefern dann nur die Zeilen, die strikt nach
diesem Zeitpunkt angelegt oder geändert wurden (nach `updated_at`). Die
Antwort spiegelt `since`, trägt `as_of` (den Lesezeitpunkt — als nächstes
`since` verwenden) und eine `delta_note` mit der Semantik. **Löschungen sind
in einem Delta-Read nicht repräsentiert**; wer Löschungen erkennen muss,
macht einen vollen Read. Ein ungültiges `since` ist ein `422`. Delta-Reads
sind **pull-only**: Push-Zustellung (Webhooks an einen konfigurierten
Endpunkt) ist eine separate, weiterhin gegatete Entscheidung (B3.7) und
bewusst nicht Teil dieser Oberfläche.

Die **menschliche Sicht** desselben Schnitts (Issue #731) liegt auf
`/transactions?since=` und `/securities?since=` als *Geändert-seit*-Chips:
gleicher Parametername, gleiche akzeptierte Formen, gleicher
Strikt-nach-`updated_at`-Schnitt — ein Link, den der Agent weitergibt, öffnet
also genau die Scheibe, die er gelesen hat. Die eine Abweichung ist bewusst:
wo die API ein ungültiges `since` mit `422` ablehnt, degradieren die Seiten
zur ungefilterten Liste — ein veraltetes Lesezeichen darf nie stillschweigend
verengen, was der Betreiber sieht.

## Wertpapiere

- `GET /api/v1/securities` listet Wertpapiere. Zeilen kommen standardmäßig als
  schlanke Projektion — die feste Whitelist `id`, `name`, `ticker_symbol`,
  `isin`, `wkn`, `currency_code`, `asset_class` — damit Routineabfragen klein
  bleiben; `projection=full` liefert den vollständigen Datensatz (Notizen,
  Feed-Konfiguration, Attribute, Zeitstempel). Ein optionales `fields=`
  (Issue #732, erweitert FR-37, kommagetrennt) wählt eine schlanke
  Feldauswahl, aufgelöst gegen die Feldliste der **vollen** Projektion; ein
  gesetztes `fields=` **ersetzt `projection=`**, denn eine schlanke
  Feldauswahl ist selbst eine Projektion, Feld für Feld gewählt. Ein
  unbekannter Name ist ein `422`, nie ein stiller Fallback.
  Optionale Query-Parameter:
  `query`, `sort`, `direction`, holding_status (`all`, `held` oder `not_held`),
  `data_quality` (`stale_quote` — kein Kurs neuer als 7 Tage, **einschließlich**
  nie bepreister Wertpapiere; `missing_quote` — gar kein Kurs, die engere Menge
  darin; `missing_logo`; `missing_fx` — Issue #717: bepreist, aber ohne
  gespeicherten Kurs von seiner Währung zum EUR-Hub, das Speichern des Kurses
  leert also die Menge), `projection` (`slim`/`full`) und `limit`/`offset` zur
  Paginierung (beides nichtnegative Ganzzahlen). Nutze diese, um große
  Kataloge zu paginieren, statt die ganze Tabelle auf einmal zu holen. Die
  **menschliche Sicht** dieser Verengungen ist die One-Tap-Chipzeile auf der
  Wertpapierseite (Issue #717): ihre Chips fahren auf demselben URL-Zustand
  (`holding=`, `dq=`, `filter[]=asset_class:is_nil`, plus `cur[]=` und
  `class[]=` für die Währungs- und Effektivklassen-Familien), sodass ein
  vorgefilterter Link und ein API-Read dieselbe Menge beschreiben.
- `POST /api/v1/securities` legt ein Wertpapier mit einem `security`-Objekt an.
  `asset_class` ist ein stabiler String-Code: `equity`, `etf`, `fund`,
  `government_bond`, `bond`, `crypto`, `commodity`, `index`, `other`, plus die
  Zertifikat-/Hebel-Codes `warrant`, `knock_out`, `factor_certificate`,
  `discount_certificate`, `bonus_certificate`, `express_certificate`,
  `reverse_convertible`. Lass es leer, damit die Klasse beim Lesen aus
  Name/ISIN/Ticker inferiert wird. Um eine Position aus der
  Allokations-Steuerbasis (den 100 %) und der Drift-Tabelle herauszuhalten,
  während sie in den Bewertungssummen und der Performance bleibt — z. B. ein als
  Wertspeicher gehaltener Bitcoin —, die Position mit einem Bucket versehen und
  diesen Bucket aus einer Ansicht ausschließen; die Allokation dann unter
  dieser Ansicht lesen.
- `GET /api/v1/securities/:id` liefert ein Wertpapier, einschließlich seiner
  `identifier_aliases` — der über den ISIN-Wechsel-Endpunkt unten
  aufgezeichneten früheren ISINs (jeweils mit `id`, `former_isin`,
  `changed_on`, `note`).
- `PATCH /api/v1/securities/:id` aktualisiert ein Wertpapier mit einem
  `security`-Objekt. Das Boolean `treat_quotes_as_raw` (Standard `false`) ist
  die ADR-0028-Notluke für Anbieter, die ihre Historie nach einem
  Aktiensplit nie rückwirkend anpassen: Mit gesetztem Flag werden die
  synchronisierten Kurszeilen des Wertpapiers als roh (wie gehandelt)
  behandelt, sodass die Split-Anpassungsfaktoren auch auf sie wirken.
- `DELETE /api/v1/securities/:id` löscht ein Wertpapier, wenn keine abhängigen
  Transaktionen oder keine Kurshistorie darauf verweisen; referenzierte
  Wertpapiere liefern `409 Conflict`.
- `GET /api/v1/securities/search` durchsucht konfigurierte
  Online-Wertpapieranbieter. Query-Parameter: `query`; optional `type` mit
  `security` oder `crypto`.

### ISIN-Wechsel (Identifier-Aliasse)

Wenn eine Kapitalmaßnahme einem bestehenden Wertpapier eine neue ISIN gibt,
den Wechsel aufzeichnen, statt die ISIN direkt zu editieren: Die frühere ISIN
wird ein journalisierter Alias, und das ISIN-Matching des Imports prüft erst
aktuelle ISINs, dann die Aliasse — Re-Importe alter Exporte (frühere ISIN) und
neuer Exporte (neue ISIN) treffen so weiter dasselbe Wertpapier, statt ein
Duplikat anzulegen (ADR-0029). Eine bloße Umbenennung braucht keinen
ISIN-Wechsel — sie ist nur eine Namensänderung.

- `POST /api/v1/securities/:security_id/isin-change` zeichnet den Wechsel mit
  einem `isin_change`-Objekt auf: Pflichtfeld `new_isin` (normalisiert auf
  getrimmte Großschreibung), optional `changed_on` (ISO-Datum, Standard heute)
  und `note`. Liefert das aktualisierte Wertpapier einschließlich seiner
  `identifier_aliases`. Abgelehnt mit `422` und benanntem Konflikt, wenn
  `new_isin` der aktuellen ISIN entspricht, auf einem anderen Wertpapier live
  ist oder als frühere ISIN eines anderen Wertpapiers aufgezeichnet ist; ein
  Wechsel zurück auf eine eigene frühere ISIN verbraucht diesen Alias (ein
  Revert). Jeder Wertpapier-ISIN-Schreibpfad — Anlegen, Aktualisieren und der
  Anlege-Pfad des Imports — lehnt symmetrisch eine ISIN ab, die als Alias
  existiert, und benennt das Alias-Wertpapier.
- `DELETE /api/v1/securities/:security_id/identifier_aliases/:id` löscht einen
  aufgezeichneten Alias (journalisiert), wenn ein ISIN-Wechsel versehentlich
  aufgezeichnet wurde; liefert `204 No Content` oder `404`, wenn der Alias
  nicht zu dem Wertpapier gehört.

Beispiel-Payload für einen ISIN-Wechsel:

```json
{
  "isin_change": {
    "new_isin": "IE000XZSV718",
    "changed_on": "2026-07-01",
    "note": "merger rename"
  }
}
```

Beispiel-Payload zum Anlegen:

```json
{
  "security": {
    "name": "Example ETF",
    "ticker_symbol": "EXM",
    "currency_code": "EUR"
  }
}
```

### Research-Log (ADR-0044)

Was Betreiber oder Agent über ein Wertpapier wissen, wird als **nur
anhängbare** datierte Einträge festgehalten — das Research-Log des
Wertpapiers — und der aktuelle Thesenstand wird daraus **abgeleitet**, nie
daneben gepflegt. Einträge werden nie geändert und nie gelöscht: Ein
widerlegter Befund wird zurückgezogen, indem eine `retraction` angehängt
wird, die ihn ersetzt; beide bleiben lesbar, sodass der nächste Lauf zuerst
den Widerruf sieht statt eine erledigte Prämisse erneut zu prüfen. Es gibt
absichtlich kein `PATCH` und kein `DELETE` für einen Eintrag.

Jeder Eintrag trägt `kind` (`thesis`, `evidence`, `invalidation_check`,
`event_result`, `risk`, `retraction`, `decision`), `body`, `source_url`,
`source_quality` (`primary`, `secondary_multi`, `awareness`, `unverified` —
**gesetzt, nicht geraten**), `as_of` (das Stichdatum der Aussage, getrennt
von `inserted_at`: ein heute geschriebener Eintrag über das letzte Quartal
trägt das Datum des Quartals), `author` (`operator`, `agent`, `local_model`;
die API setzt standardmäßig `agent`), `machine_generated` (ein extrahierter
Eintrag ist ein Vorschlag bis zur Bestätigung und muss seine `source_url`
tragen), `supersedes_id` (der frühere Eintrag desselben Wertpapiers, den
dieser ersetzt; Pflicht bei einem Widerruf), `valid_until` (eine datierte
Sperre wie ein Lock-up oder eine selbst auferlegte Kaufsperre) und — nur
bei `thesis`-Einträgen — `conviction` (`low`, `medium`, `high`),
`invalidation_condition` und `time_stop`. Jeder Eintrag in einer Antwort
trägt zudem `superseded_by_ids` und ein `superseded`-Flag, sodass ein
ersetzter Eintrag als ersetzt gezeigt statt verborgen wird. Alle festen
Wertemengen werden geprüft; ein unbekannter Wert ist ein `422` mit dem
Feldnamen, und aus Eingaben entsteht nie ein Atom.

- `GET /api/v1/securities/:security_id/notes` — das Log, neueste zuerst
  (nach `as_of`, dann Schreibzeit), mit dem abgeleiteten `thesis_state` und
  einer `log_note`, die den Nur-anhängen-Kontrakt benennt.
- `POST /api/v1/securities/:security_id/notes` — hängt einen Eintrag aus
  einem `note`-Objekt an (`201`); journalisiert unter dem API-Token-Akteur.
- `GET /api/v1/notes/unreviewed?days=N` — gehaltene Wertpapiere
  (Nettostückzahl ungleich null über alle Depots), deren neuester Eintrag
  älter als `N` Tage ist (Standard 90) oder die keinen haben; Zeilen tragen
  `last_entry_as_of` und `days_since_last_entry` (`null`, wenn nie geprüft).
- `GET /api/v1/notes/uncorroborated` — Einträge, deren `source_quality`
  nicht `primary` ist, neueste zuerst; ersetzte Einträge werden übersprungen,
  sofern nicht `include_superseded=true`; optional `security_id`.
- `GET /api/v1/notes/expiring?days=N` — Einträge, deren `valid_until` in die
  nächsten `N` Tage fällt (Standard 30), früheste zuerst, mit
  `days_until_expiry`; aufgehobene (ersetzte) Sperren werden übersprungen;
  optional `security_id`.

Der **Thesenstand** (`thesis_state` im Wertpapier-Detail und im Log-Read) ist
die B4.1-Projektion: `status` (`none`, `intact`, `retracted`), der aktuelle
Thesentext, `conviction`, `invalidation_condition`, `time_stop`, `as_of`,
`last_reviewed_at` und `last_reviewed_by` (der neueste `thesis`- oder
`invalidation_check`-Eintrag), `derived_from_entry_id` (der Thesen-Eintrag,
aus dem er liest) und `retracted_by_entry_id` (der Widerruf, dessen `body`
den Grund trägt), dazu ein `basis`-Satz, der die Ableitung benennt. Die
neueste These, die keine andere These ersetzt, ist die aktuelle; ein
Widerruf, der sie ersetzt, setzt `retracted`.

Beispiel-Payload zum Anhängen:

```json
{
  "note": {
    "kind": "retraction",
    "body": "10-Q am 2026-08-02 geprüft: kein Lieferantenstreit offengelegt. Zurückgezogen.",
    "source_url": "https://example.invalid/sec/10-q",
    "source_quality": "primary",
    "as_of": "2026-08-02",
    "supersedes_id": 41
  }
}
```

Die menschliche Sicht ist der Tab **Research** im Wertpapier-Detailbereich
auf `/securities/:id`: der Thesenstand oben, die Einträge neueste zuerst mit
sichtbarer Art und Quellenqualität, ersetzte Einträge als ersetzt markiert,
Widerrufe lesbar und ein Formular, das einen Eintrag als Betreiber anhängt.

## Kurse

- `GET /api/v1/securities/:security_id/quotes` listet die Kurshistorie eines
  Wertpapiers. Optionale Query-Parameter: `from` und `to`, als ISO-Daten
  formatiert. Ungültige Datumsfilter liefern `422 Unprocessable Entity` mit
  Feldfehlern. Jede Zeile beschreibt ihren Split-Status selbst (ADR-0028):
  `close` ist der **gespeicherte** Wert (wird nie verändert),
  `adjusted_close` der split-bereinigte Anzeigewert, `basis` die
  Speicherbasis der Zeile (`raw` für wie gehandelt erfasste manuelle Zeilen,
  `provider_mirror` für rückwirkend angepasste Sync-Zeilen) und `adjusted`,
  ob ein Split-Faktor angewendet wurde. Charts und Bewertungen nutzen
  `adjusted_close`; Audits prüfen gegen `close`. Ein Wertpapier, dessen
  Anbieter nie rückwirkend anpasst, lässt sich mit `treat_quotes_as_raw`
  markieren (siehe Wertpapiere), was die Roh-Basis für seine
  synchronisierten Zeilen erzwingt.
- `PUT /api/v1/securities/:security_id/quotes` führt manuelle Kurszeilen ein
  (Upsert).
- `POST /api/v1/securities/:security_id/sync_quotes` löst die
  Kurssynchronisierung eines Wertpapiers aus. Die Antwort enthält `status` (`ok`,
  `skipped` oder `error`); übersprungene und Fehler-Antworten können einen
  `reason` wie `missing_ticker` oder `no_provider_adapter` enthalten.

Beispiel-Payload für Kurs-Upsert:

```json
{
  "quotes": [
    {
      "date": "2026-05-15",
      "close": "123.45",
      "source": "manual"
    }
  ]
}
```

Beispiel-Antwort für Kurssynchronisierung:

```json
{
  "data": {
    "status": "skipped",
    "reason": "missing_ticker"
  }
}
```

## Portfolios und Konten

> **Portfolio-Writes sind veraltet (ADR-0024) — nur Kompatibilität; nutze
> Buckets/Ansichten zur Gruppierung.** Portfolios wurden zu internen
> Kompatibilitätsdatensätzen herabgestuft: die UI gruppiert ausschließlich
> über Buckets und Ansichten, und Depots/Geldkonten brauchen keine
> `portfolio_id` mehr (ein deterministisches internes Standard-Portfolio wird
> automatisch gebunden). `POST /api/v1/portfolios` und
> `PATCH /api/v1/portfolios/:portfolio_id` funktionieren weiter, antworten
> aber mit dem Response-Header `Deprecation: true`. Sunset-Hinweis: nach zwei
> Releases ohne externe Portfolio-Writes verschmilzt eine Folge-Story die
> Datensätze in Buckets und Ansichten (das Exit-Kriterium des ADR) — plane
> Migrationen auf `POST /api/v1/buckets` und `POST /api/v1/views` jetzt.
> Jeder hier geschriebene Datensatz bleibt in der schreibgeschützten
> Admin-Liste „Portfoliodatensätze (Kompatibilität)“ der UI sichtbar, nichts
> wird unsichtbar.

- `GET /api/v1/portfolios` listet Portfolios (Kompatibilitätsdatensätze).
- `POST /api/v1/portfolios` legt ein Portfolio mit einem `portfolio`-Objekt an.
  **Veraltet** — antwortet mit `Deprecation: true`; bevorzuge
  Buckets/Ansichten.
- `GET /api/v1/cash_accounts` listet Geldkonten. Jedes trägt einen `balance`
  (Decimal-String, in der eigenen Währung des Kontos), der beim Lesen aus dem
  Ledger abgeleitet wird: Beträge werden als positive Größen gespeichert und der
  Transaktions-`type` impliziert die Richtung (Einzahlungen, Dividenden, Zinsen,
  Steuererstattungen und Verkäufe fügen Cash hinzu; Entnahmen, Gebühren, Steuern
  und Käufe entfernen es; eine Geldübertragung belastet ihr Konto und schreibt dem
  Gegenkonto gut). Ein `balance_adjustment`-Snapshot (siehe unten) verankert den
  Saldo an einem genannten absoluten Betrag zu seinem Datum, wonach nur spätere
  Buchungen ihn anpassen.
- `POST /api/v1/cash_accounts/:id/balance` erfasst einen absoluten
  **Saldo-Snapshot** für ein Konto (ADR-0009): den aktuellen Saldo zu einem Datum,
  statt jede Buchung zu spiegeln. Body `{"date": "2026-06-01", "amount":
  "4250.00"}` (`notes` optional); `amount` ist ein Decimal-String und darf negativ
  sein (ein Überziehungskredit). Es speichert eine
  `balance_adjustment`-Transaktion und gibt sie zurück. Der Saldo verankert sich
  dann an diesem Betrag, und nur Buchungen mit einem Datum strikt nach dem Snapshot
  verändern ihn, sodass Geld zwischen eigenen Konten zu verschieben keine
  Übertragungsbuchung braucht. Unbekannte Konten liefern `404 Not Found`.
- `POST /api/v1/cash_accounts` legt ein Geldkonto mit einem `cash_account`-Objekt
  an. `portfolio_id` ist optional (ADR-0024): fehlt sie, wird das Konto an das
  deterministische interne Standard-Portfolio gebunden; eine explizite id
  gewinnt weiterhin (Kompatibilität). Das optionale `liquidity_role` (Standard `free_cash`) klassifiziert das
  Konto: `free_cash` ist echtes verfügbares Cash; `credit_line` ist eine
  Überziehungs-/Lombard-Linie, deren negativer Saldo eine Verbindlichkeit ist und
  deren ungenutzter Rahmen nie Liquidität ist (sie zählt nie zum verfügbaren
  Cash, auch nicht mit positivem Saldo — der Typ schlägt das Vorzeichen);
  `reserve` ist ein sichtbarer, aber ausgeschlossener Topf. Nur `free_cash`-Konten
  mit nicht-negativem Saldo gehen in das verfügbare Cash der Bewertung und ihre
  `cash_quote` ein. Ein unbekannter Wert wird mit `422 Unprocessable Entity`
  abgelehnt.
- `GET /api/v1/cash_accounts/:id` liefert ein Geldkonto.
- `PATCH /api/v1/cash_accounts/:id` aktualisiert ein Geldkonto (`name`,
  `currency_code`, `notes`, `liquidity_role`); `portfolio_id` kann nicht
  geändert werden.
- `DELETE /api/v1/cash_accounts/:id` löscht ein Geldkonto oder liefert
  `409 Conflict`, wenn eine Transaktion oder ein Wertpapierkonto noch darauf
  verweist.
- `GET /api/v1/securities_accounts` listet Depots/Wertpapierkonten.
- `POST /api/v1/securities_accounts` legt ein Depot/Wertpapierkonto mit einem
  `securities_account`-Objekt an. `portfolio_id` ist optional (ADR-0024):
  fehlt sie, wird das Depot an das deterministische interne Standard-Portfolio
  gebunden.
- `GET /api/v1/securities_accounts/:id` liefert ein Wertpapierkonto.
- `PATCH /api/v1/securities_accounts/:id` aktualisiert ein Wertpapierkonto
  (`name`, `notes`, `cash_account_id`); `portfolio_id` kann nicht geändert werden.
- `DELETE /api/v1/securities_accounts/:id` löscht ein Wertpapierkonto oder liefert
  `409 Conflict`, wenn eine Transaktion noch darauf verweist.

Beispiel-Payloads für Konten:

```json
{
  "portfolio": {
    "name": "Household Portfolio",
    "base_currency_code": "EUR"
  }
}
```

```json
{
  "cash_account": {
    "portfolio_id": 1,
    "name": "Settlement EUR",
    "currency_code": "EUR"
  }
}
```

```json
{
  "securities_account": {
    "portfolio_id": 1,
    "cash_account_id": 1,
    "name": "Main Depot"
  }
}
```

## Transaktionen und Bestände

- `GET /api/v1/transactions` listet Transaktionen. Optionale Filter: `from`/`to`
  (ISO-Daten, inklusive), `portfolio_id`, `security_id`, `securities_account_id`.
  Ungültige Filter liefern `422 Unprocessable Entity` mit dem betreffenden Feld.
  Ein optionales `fields=` (FR-37, kommagetrennt) wählt eine schlanke
  Feldauswahl: Jede Zeile trägt dann genau die angefragten Felder. Die Namen
  werden gegen die Feldliste des Serializers validiert — ein unbekannter Name
  ist ein `422`, nie ein stiller Fallback. Die **menschliche Sicht** von
  `fields=` (Issue #732) ist die Spaltenwahl auf der Transaktionshistorie und
  dem Bestände-Panel: dieselben Projektionen, Spalte für Spalte auf der Seite
  gewählt — und die Wertpapierliste, deren Spaltenwahl älter als FR-37 ist,
  bekam die Gegenrichtung als eigenes `fields=` (siehe Wertpapiere).
  Ein optionales `running_balance_for=<cash_account_id>` ergänzt jede Zeile um
  einen `running_balance` — den Saldo dieses Verrechnungskontos nach der
  Buchung, als Decimal-String in der Kontowährung — plus ein `running_balance_basis`
  auf oberster Ebene, das Konto, Währung und Berechnungsgrundlage benennt. Zwei
  Eigenschaften, von denen die Zahl abhängt: Der Lauf umfasst immer die
  **gesamte** Historie des Kontos, eine eingeschränkte Abfrage (ein `from`, ein
  Filter) zeigt also echte Salden statt einer Teilsumme; und eine Zeile, die
  das Konto nicht bewegt, trägt `null` statt den vorherigen Wert zu
  wiederholen, was sich wie "hier ist nichts passiert" läse. Ein unbekanntes
  oder nicht-numerisches Konto ist ein `422` mit dem Feld
  `running_balance_for`. Das ist das API- und MCP-Gegenstück zur Saldospalte
  auf der Transaktionsseite.
- `POST /api/v1/transactions` legt eine Transaktion beliebiger buchbarer Art mit
  einem `transaction`-Objekt an (die pro Buchungsart erforderlichen Felder werden
  serverseitig validiert). Die buchbaren `type`-Werte sind `buy`, `sell`,
  `dividend`, `interest`, `deposit`, `removal`, `fee`, `tax`, `tax_refund`,
  `cash_transfer`, `inbound_delivery`, `outbound_delivery` und
  `security_transfer` (`balance_adjustment` wird über den dedizierten
  Kontostand-Snapshot-Endpunkt geschrieben, `split` über die Split-Routen
  weiter unten). Buchungssemantik, die man vor dem ersten Schreiben
  kennen sollte: `gross_amount` einer Dividende ist der NETTO-Geldzufluss auf dem
  Konto — einbehaltene Steuern gehören in `taxes`, der Einnahmenbericht
  rekonstruiert brutto als netto plus einbehaltene Steuer. Eine ohne `price`
  erfasste Einlieferung (`inbound_delivery`) geht mit Einstand null in die
  Kostenbasis ein — der Anschaffungskurs sollte mitgegeben werden, wenn er
  bekannt ist; eine Auslieferung (`outbound_delivery`) entnimmt den Einstand
  zum laufenden Durchschnitt, ihr Kurs ist rein informativ. Bei einer
  Abgleichdifferenz sollte die fehlende Buchung der richtigen Art nachgetragen
  werden — Kontostand-Snapshots und unbepreiste Einlieferungen sind letzte Mittel,
  die Zahlen richtig aussehen lassen und dabei den Einstand verzerren. Beträge
  sind positive Größen — die Buchungsart bestimmt die Richtung; nur
  `balance_adjustment` darf einen negativen (absoluten) Betrag tragen. Eine
  **Steuererstattung** — etwa die bei einem Verlustverkauf gutgeschriebene
  Steuer — ist deshalb nie ein negativer `taxes`-Wert auf dem Verkauf: Der
  Verkauf wird mit den tatsächlich einbehaltenen Steuern (oder `0`) gebucht,
  dazu eine separate `tax_refund`-Transaktion, deren positiver `gross_amount`
  der dem Konto gutgeschriebene Betrag ist (`cash_account_id` und
  `gross_amount` sind ihre Pflichtfelder; das Changeset lehnt ein negatives
  `taxes` mit genau diesem Hinweis ab). Ein
  Wertpapier, das über ein Geldkonto in einer
  anderen Währung abgerechnet wird (zum Beispiel ein USD-Wertpapier über ein
  EUR-Konto), wird in der eigenen Währung des Wertpapiers gebucht und trägt die
  Felder zur währungsübergreifenden Abrechnung: `security_amount` (Handelsbetrag in
  der Wertpapierwährung), `settlement_amount` (im Geldkonto in Kontowährung
  belasteter oder gutgeschriebener Betrag) und `settlement_fx_rate` (Einheiten der
  Kontowährung je einer Einheit der Wertpapierwährung). Fehlt der Kurs, werden
  jedoch beide Beträge geliefert, wird er als `settlement_amount / security_amount`
  abgeleitet (der tatsächliche Kurs des Brokers); eine Währungsabweichung ohne Kurs
  und ohne Beträge zur Ableitung wird abgelehnt. Die Einstandsbasis bleibt in der
  Wertpapierwährung, sodass die positionsbezogene G/V währungsehrlich ist. Alle
  drei sind Decimal-Strings und bei Buchungen in gleicher Währung `null`.
- `GET /api/v1/transactions/:id` liefert eine Transaktion.
- `PATCH /api/v1/transactions/:id` aktualisiert eine Transaktion (z. B. um eine
  falsch importierte Buchung zu korrigieren); die Validierung je Art gilt weiter.
- `DELETE /api/v1/transactions/:id` löscht eine Transaktion. Da Trades und
  Bestände abgeleitet sind, korrigiert oder entfernt das Korrigieren oder Entfernen
  der Transaktion auch sie.
- `POST /api/v1/splits/preview` zeigt eine Aktiensplit-Buchung (ADR-0028) als
  Vorschau, ohne etwas zu schreiben. Die Anfrage trägt `security_id`, das
  Wirksamkeitsdatum `date` (ISO, nicht in der Zukunft) und das Verhältnis als
  Paar positiver Ganzzahlen `ratio_numerator`/`ratio_denominator` (`10:1`
  vorwärts, `1:10` Reverse-Split; auf kleinste Terme normalisiert, `10:5`
  wird also als `2:1` gebucht). Die Antwort zeigt je Portfolio mit Bestand
  die Stückzahl unmittelbar vor und nach dem Wirksamkeitsdatum sowie den
  resultierenden aktuellen Bestand (alles Decimal-Strings; die
  Verhältnis-Teile bleiben Ganzzahlen), plus `warnings`:
  `effective_date_before_history` bedeutet, dass das Wirksamkeitsdatum vor
  der frühesten erfassten Transaktion des Wertpapiers liegt — die
  gespeicherten Stückzahlen können bereits post-split sein (der
  Split-Assistent von Portfolio Performance schreibt die Historie destruktiv
  um), eine Buchung würde dann doppelt anpassen. Vor dem Buchen die Vorschau
  prüfen. Die Vorschau zeigt außerdem die gespeicherten Schlusskurse rund um
  das Wirksamkeitsdatum (`quotes_around`) und einen `quote_basis_check`
  (Fehlklassifikations-Wächter, ADR-0028 §2): ein sichtbarer Sprung deutet
  auf eine Roh-Serie hin, Kontinuität auf eine bereits angepasste; steht das
  im Widerspruch zur Klassifikation über die `source` der Zeilen, warnt die
  Vorschau mit `quote_basis_contradiction` (für Sync-Serien, die nie
  rückwirkend anpassen, das Flag `treat_quotes_as_raw` des Wertpapiers
  setzen statt blind zu buchen), und bei zu wenigen Kursen auf einer Seite
  meldet sie `insufficient_quotes_to_verify_basis`, statt eine saubere
  Prüfung zu suggerieren.
- `POST /api/v1/splits` bucht den Split: **ein** Aufruf fächert das Ereignis
  über alle Portfolios mit Bestand am Wirksamkeitsdatum auf — eine
  journalisierte `split`-Zeile je Portfolio, atomar eingefügt — und liefert
  die erzeugten Transaktionen (`201`, reguläres Transaktionsformat). Ein
  Portfolio ohne Bestand am Wirksamkeitsdatum erhält keine Zeile. Ein
  zweiter Split am selben Tag für dasselbe Wertpapier wird mit `422`
  abgelehnt und benennt das bestehende Ereignis (ein wiederholter Timeout
  kann den multiplikativen Effekt nicht verdoppeln); ein Datum in der
  Zukunft und ein Wertpapier ohne Bestand am Wirksamkeitsdatum werden
  ebenfalls mit `422` abgelehnt. Der generische Endpunkt
  `POST /api/v1/transactions` lehnt die Art `split` ab — diese beiden Routen
  sind der einzige Schreibpfad für Splits.
- `GET /api/v1/portfolios/:portfolio_id/holdings` listet abgeleitete Bestände
  eines Portfolios, eine Zeile je (Depot, Wertpapier). Jede Zeile trägt
  `quantity`, einen gleitenden Durchschnitt `avg_cost` und `cost_basis`
  (preisbasiert, sodass Gebühren und Steuern nicht in die Stückkosten einfließen),
  den `latest_price`, `market_value` und `unrealized_pnl_abs`/`unrealized_pnl_pct`
  gegen diesen Preis, plus `security_name` und `currency_code`. Diese Größen
  sind in der **eigenen** Währung des Wertpapiers — durch das Kostenpaar der
  Ledger-Faltung erzwungen (ADR-0033), nicht länger eine Annahme; ein
  Bestand, dessen Wertpapier keinen Kurs hat, liefert `null` für Preis,
  Marktwert und G/V. Jede Zeile trägt zusätzlich die
  ADR-0033-Zerlegung des G/V in Basiswährung: `base_cost` (der tatsächlich
  gezahlte Abrechnungsbetrag, mit seiner `base_currency`),
  `price_return_abs`/`price_return_pct` (die eigene Kursbewegung des
  Wertpapiers, zum heutigen Kurs umgerechnet),
  `currency_return_abs`/`currency_return_pct` (der Wechselkurseffekt auf den
  ursprünglich investierten Betrag) und
  `total_return_base_abs`/`total_return_base_pct` — wobei
  `total = price + currency` Decimal-exakt gilt. Eine Zeile, deren Zerlegung
  nicht ableitbar ist, meldet `decomposed: false` mit einem
  `undecomposed_reason` (`"missing_native_cost"` — kein
  Wertpapierwährungs-Leg in der erfassten Buchung, dann sind auch
  `cost_basis`/`avg_cost`/G/V `null`; `"missing_base_cost"` — das
  Abrechnungs-Leg ist nicht in der Basiswährung; `"missing_fx"` — kein
  gespeicherter aktueller Kurs; `"no_price"`) und niemals eine geratene
  Zahl. Die Antwort ist selbstbeschreibend (FR-13): sie trägt
  `currency_basis: "security_currency"` plus eine `currency_basis_note`, die
  benennt, welches Feld in welcher Währung ist, und ein `as_of`-Datum.
  Bestände werden beim Lesen abgeleitet, ohne gespeicherten Snapshot, daher
  ist `as_of` das Lesedatum. Unbekannte Portfolios liefern `404 Not Found`.
  Optionale Filter: `security_id`, `securities_account_id`. Ein optionales
  `fields=` (FR-37, kommagetrennt) wählt eine schlanke Feldauswahl je Zeile,
  validiert gegen die Feldliste des Serializers; ein unbekannter Name ist
  ein `422`.
- `GET /api/v1/realized_gains` (Issue #724) liefert das Realisiert-Rollup des
  Cash-flow-Bereichs: FIFO-gematchte realisierte G&V über **alle** Wertpapiere
  und Portfolios, gruppiert nach dem **Schlussdatum** jedes Verkaufs in eine
  Jahres-/Monatsmatrix in der Basiswährung. FX-Basis ist D-1 (signiert
  2026-08-20): jeder Verkauf konvertiert über den **EUR-Hub** zum jüngsten
  gespeicherten Kurs seines eigenen Schlusstags; ein Verkauf **ohne**
  gespeicherten Kurs zu diesem Datum wird **aus jeder konvertierten Summe
  ausgeschlossen und benannt** (`excluded`: `count` + `securities`) — nie zum
  Kurs eines Nachbardatums konvertiert, nie still verworfen. Die Payload
  trägt `computation_basis` (Serie, Fenster, Referenz, Lücken) und eine
  `conversion_note`; die menschliche Sicht ist `/cashflow?tab=realized`.
- `GET /api/v1/external_flows` (Issue #725) liefert das
  Ein-/Auszahlungs-Rollup: die gebuchten externen **Cash**-Flüsse (`deposit`
  und `removal`) über alle Portfolios, je Jahr und Monat mit Einzahlungen,
  Auszahlungen und Netto. Bewusst enger als das `invested_capital` des
  Performance-Laufs, das zusätzlich ein-/ausgelieferte Wertpapiere zum
  Marktwert und Saldo-Snapshot-Residuen zählt — der Unterschied steht in
  `computation_basis.excludes`. FX-Basis wie in der Schwester-Facette:
  EUR-Hub zum Kurs des eigenen Buchungstags, unkonvertierbare Flüsse
  ausgeschlossen und nach Verrechnungskonto benannt. Die menschliche Sicht
  ist `/cashflow?tab=flows`.
- `GET /api/v1/costs` (Issue #726) liefert das Kosten-Rollup: Gebühren und
  Steuern über alle Portfolios, **nur auf Übersichtsebene**, je Jahr und
  Monat mit Jahressummen für Gebühren, Steuern und beides zusammen. Die
  Serie summiert die Gebühren- und Steuer-**Nebenbeträge** jeder Transaktion
  plus die eigenständigen `fee`-/`tax`-Buchungen; `tax_refund` wird gegen
  die Steuern verrechnet. Bruttobeträge werden nie summiert — das Brutto
  eines Kaufs **enthält** seine Nebenbeträge, das eines Verkaufs ist um sie
  **gemindert**, eine Bruttosumme beschriebe also etwas anderes. Diese Regel
  steht in `computation_basis.series`. FX-Basis wie in den
  Schwester-Facetten: EUR-Hub zum Kurs des eigenen Buchungstags,
  unkonvertierbare Kosten ausgeschlossen und nach **Währung** benannt. Die
  menschliche Sicht ist `/cashflow?tab=costs`.
- `GET /api/v1/holdings/by_security` liefert die **globale Bewertung je
  Wertpapier** über **alle** Portfolios hinweg: eine `holdings`-Zeile je aktuell
  gehaltenem Wertpapier mit `security_id` (eine Ganzzahl), Gesamt-`quantity` und
  aktuellem `market_value`, umgerechnet in den **EUR-Hub**, plus ein
  `valued`-Flag. `valued` ist `false` (und `market_value` ist `null`), wenn das
  Wertpapier weder einen Kurs noch einen Handelspreis hat oder kein
  Wechselkurspfad nach EUR existiert, sodass ein fehlender Kurs oder Kurs einen
  Wert nie stillschweigend verfälscht. Jede Zeile trägt außerdem den
  aufgelösten nativen `latest_price` mit `price_currency` und `price_source`
  sowie einen `unvalued_reason`, der sagt, *warum* eine Zeile unbewertet ist:
  `"no_price"` (nichts auflösbar) oder `"missing_fx"` (der Preis ist bekannt,
  aber kein gespeicherter Kurspfad erreicht EUR); `null`, wenn bewertet. Die
  Zeilen sind nach `security_id` sortiert. Die Antwort ist selbstbeschreibend: ein `currency` auf oberster
  Ebene mit `"EUR"`, ein `as_of`-Lesedatum (der Bericht wird beim Lesen
  abgeleitet, daher ist `as_of` das heutige Datum, kein gespeicherter
  Zeitpunkt) und ein `note`, das die Hub-Umrechnung beschreibt. Dies ist das
  portfolioübergreifende Gegenstück in Basiswährung zur Bestandsliste eines
  einzelnen Portfolios (die in der eigenen Währung jedes Wertpapiers ohne FX
  bleibt); für Summen und Gewichte eines Portfolios nutze stattdessen den
  Bewertungs-Endpunkt.
- `GET /api/v1/holdings/negative` liefert den **Datenqualitätsbericht zu
  negativen Beständen**: jede (Depot, Wertpapier)-Position mit abgeleiteter
  Menge unter null — Import-Altlasten aus nicht modellierten
  Kapitalmaßnahmen — als `rows` (mit `depot_name`, `security_name`, `isin`,
  `portfolio_id` und der negativen `quantity` als Decimal-String) plus
  `totals` mit der Gesamtmenge jedes gelisteten Wertpapiers über **alle**
  Depots, sodass Transfer-Altlasten (negativ in einem Depot, positiv in
  einem anderen) von einer wirklich negativen Gesamtmenge unterscheidbar
  sind. Selbstbeschreibend mit `as_of`-Lesedatum und `note`. Nichts wird
  automatisch repariert; korrigiere die Transaktionshistorie des
  Wertpapiers.
- `POST /api/v1/holdings/reconcile` vergleicht eine **vom Nutzer gelieferte
  externe Positionsliste** (Brokerauszug oder Depotübersicht, clientseitig in
  Zeilen geparst) mit den aus dem Ledger abgeleiteten Beständen — **strikt
  lesend**: die Liste kommt ausschließlich im Request-Body an, wird nie
  gespeichert oder geloggt, und es werden keine Daten von irgendwoher geholt
  (ADR-0029 §6, FR-35). Jede Zeile ist `{identifier, quantity}` mit optionaler
  `currency` und optionalem festnagelndem `security_id`; `quantity` muss ein
  **kanonischer Dezimal-String mit Punkt** sein (alles andere —
  Komma-Dezimalzahlen, Tausendertrennzeichen, Exponenten — ist ein `422`, das
  die Zeile benennt; Locale-Parsing ist Aufgabe des Clients), und eine leere
  `rows`-Liste ist ein `422`. Identifier laufen durch dieselbe
  Identitätsleiter wie der Import: ein ISIN-förmiger String (Format und
  Prüfziffer) matcht nur über die ISIN-Stufe (aktuelle ISINs zuerst, dann
  erfasste frühere ISINs — `matched_via: "former_isin"`); jeder andere String
  wird gegen WKN, Ticker+Währung und Name+Währung geprüft, mit der
  Genau-eine-Regel über die Vereinigung dieser Stufen — ein String, der die
  WKN des einen und den Ticker eines anderen Wertpapiers trifft, landet unter
  `ambiguous` mit den Kandidaten, nie als stille Wahl, und eine Zeile ohne
  Währung kann nicht über Ticker oder Name matchen (`unmatched` mit Grund
  `currency_required`). Die Antwort ist selbstbeschreibend (`basis` mit
  `as_of`, `scope` und einer Delta-Notiz) und liefert: `matched`-Zeilen (eine
  je Wertpapier — Zeilen, die auf dasselbe Wertpapier auflösen, werden
  aggregiert, externe Mengen summiert, die beitragenden Zeilen gelistet) mit
  der `matched_via`-Stufe (`isin`, `former_isin`, `wkn`, `ticker`, `name`
  oder `pinned`), `ledger_quantity`, `external_quantity` und `delta`
  (`extern - Ledger`) als exakte Decimal-Strings — Ticker-/Name-Treffer
  tragen `weak_match: true` und den Hinweis, das Wertpapier vor jeder Buchung
  zu bestätigen —, `ambiguous`- und `unmatched`-Zeilen sowie
  `missing_from_list` (gehaltene Ledger-Positionen, die die externe Liste
  nicht abdeckt). Die eingebettete `guidance` ist Teil des Vertrags: eine
  Differenz wird durch Buchen der fehlenden Transaktion der richtigen Art
  gelöst; Saldo-Snapshots und unbepreiste Einlieferungen sind letzte Mittel,
  die die Kostenbasis verzerren. Optionaler Scope: `portfolio_id` oder `view`
  (eine View-Id; sich gegenseitig ausschließend — beide zugleich sind ein
  `422`), Standard ist die gesamte Instanz; ein unbekanntes Portfolio oder
  eine unbekannte View ist ein `404`.
- `GET /api/v1/portfolios/:portfolio_id/valuation` liefert eine Live-Bewertung
  eines Portfolios: jede gehaltene Position bepreist aus ihrem letzten
  Kurs-Schlusswert, ein `total_value` und das `weight` jeder bewerteten Position
  (ihr Anteil am Gesamtwert). Der Marktwert jeder Position wird aus gespeicherten
  Wechselkursen in die `base_currency` des Portfolios (Top-Level-Feld) umgerechnet;
  je Position zeigt `security_currency` die native Währung. Ein Wertpapier ohne
  jeden Kurs wird mit dem zuletzt eigenen Handelspreis bepreist (`price_source:
  "trade"`, gezählt im Top-Level `trade_priced_count`); eine bepreiste Position
  trägt `price_source: "quote"`. Eine Position mit weder Preis **oder** ohne
  Wechselkurspfad zur Basiswährung wird mit `valued: false`, `price_source: null`
  und `null` für Marktwert und Gewicht zurückgegeben, sodass ein fehlender Preis
  oder Kurs den Gesamtwert nie verzerrt. Unbekannte Portfolios liefern
  `404 Not Found`. Gewichte sind rohe Anteile (`market_value / total_value`),
  ausgegeben in voller Decimal-Präzision; da sie normalisierte Verhältnisse sind,
  müssen sie sich nicht exakt zu `1` summieren (für die Anzeige runden).
  Marktwerte und `total_value` sind exakt. Die Bewertung trägt auch Cash:
  `cash_balances` listet jedes Geldkonto (`balance` in eigener Währung, plus
  `base_value`/`valued` nach Umrechnung in die Basiswährung, sein
  `liquidity_role` und ein `deployable`-Flag), `total_cash` ist die
  Basiswährungssumme der bewerteten Geldkonten (sodass der negative Saldo einer
  gezogenen Kreditlinie ihn weiterhin mindert), und `total_with_cash` ist
  `total_value + total_cash`. `cash_quote` ist der Anteil des verfügbaren Cash am
  Portfolio: verfügbares Cash ist die Summe der `free_cash`-Konten mit
  nicht-negativem Saldo (`deployable: true`), und die Quote wird berechnet, als
  gäbe es die anderen Konten nicht (`counting_cash / (total_value +
  counting_cash)`, `0`, wenn noch nichts zu bewerten ist) — sodass ein
  Reserve-Konto oder eine Kreditlinie gelistet und in `total_cash` bleibt, ohne
  je Schein-Liquidität zu melden. Die Antwort liefert außerdem
  `counting_cash` (Decimal-String) — das verfügbare Cash, das in die Quote eingeht — sodass
  ein Konsument die `cash_quote` selbst rekonstruieren kann. Ein Konto, dessen Währung
  keinen Kurspfad zur Basis hat, wird `valued: false` gemeldet und aus
  `total_cash` ausgeschlossen, spiegelnd, wie unbepreisbare Positionen behandelt
  werden. Die Antwort ist selbstbeschreibend (FR-13): sie trägt ein
  `as_of`-Datum (das Lesedatum — die Bewertung wird live ohne gespeicherten
  Snapshot berechnet) und eine `valuation_note`, die angibt, dass Summen in
  `base_currency` über den EUR-Hub vorliegen und dass die je Position geführten
  Felder `price_source` und `valued` die Preis-Aktualität anzeigen. Ein
  optionales `include_positions=false` (FR-37) liefert nur den Roll-up —
  Summen, Cash-Salden und Cash-Quote ohne die Positionszeilen; die Antwort
  benennt die gelieferte Form über `positions_included`.
- `GET /api/v1/portfolios/:portfolio_id/performance` liefert die **echte
  zeitgewichtete Rendite (TTWROR)** des Portfolios, berechnet auf die
  Portfolio-Performance-Art: das Portfolio wird täglich bewertet (Kurse am oder vor
  jedem Tag, zu den Kursen jenes Tages umgerechnet, plus Cash), externe Flüsse —
  Einzahlungen, Entnahmen, Lieferungen und Saldo-Snapshot-Sprünge — werden
  neutralisiert, und tägliche Renditen werden geometrisch verkettet (siehe
  ADR-0010). Optionale Query-Parameter: `period` (`ytd`, `1y`, `3y`, `5y`, `max` —
  Standard `max`; ein unbekannter Zeitraum liefert `422 Unprocessable Entity`),
  `year=YYYY` für ein einzelnes Kalenderjahr, `from=`/`to=` (ISO-Daten, beide
  erforderlich, `from <= to`) für einen freien Zeitraum — beide ehrlich auf die
  vorhandene Historie begrenzt, ein rückwärtiger oder fehlerhafter Zeitraum
  liefert `422` — und `series=true`, um die täglichen Punkte aufzunehmen
  (`date`, `value`, `flow`, `cumulative_ttwror`). Die Antwort trägt `ttwror`, `start_date`/`end_date`,
  `start_value`/`end_value`, `net_external_flows` als Decimal-Strings und
  `suspect_dates` — Daten von Buchungen älter als 1970 (Import-Tippfehler), deren
  Effekte am ersten plausiblen Tag angewendet wurden. Neben `ttwror` trägt die
  Antwort auch die **geldgewichtete Rendite** `irr` — die einzelne annualisierte
  Rate, die die datierten externen Flüsse und den Endwert des Zeitraums auf null
  abzinst (`NPV(r) = Σ cf/(1+r)^(days/365) = 0`), die Zahl, die Portfolio
  Performance neben TTWROR zeigt. Es ist ein Decimal-String oder `null`, wenn keine
  Rate existiert (weniger als zwei Flüsse, alle Flüsse mit gleichem Vorzeichen oder
  der Solver konvergiert nicht). Wertpapiere ohne Kurse werden mit dem zuletzt
  eigenen Handelspreis bepreist (siehe den Bewertungs-Endpunkt). Unbekannte
  Portfolios liefern `404 Not Found`. Da der tägliche Walk aus einem dauerhaft
  materialisierten abgeleiteten Wert bedient werden kann (ADR-0039), schweigt
  die Antwort **nie über ihre Frische**: `as_of` (ISO-8601-Zeitstempel) ist
  der Berechnungszeitpunkt des Walks — möglicherweise älter als die Anfrage,
  wenn sich die zugrunde liegenden Daten seither nicht geändert haben — und
  `stale` (Boolean) markiert einen überholten Wert, der ausgeliefert wird,
  während ein frischer berechnet wird; ein gespeicherter Wert wird von jedem
  Schreibvorgang invalidiert, der ihn beeinflussen kann, `stale: false`
  bedeutet also aktuell gegenüber dem Ledger. Die Antwort nennt außerdem die
  **Berechnungsbasis** der Metrik (`computation_basis`): Eingangsreihe,
  wirksames Fenster, Referenzreihe (`null` — TTWROR/IRR haben keine) und den
  Umgang mit Lücken.
- `GET /api/v1/portfolios/:portfolio_id/income` liefert den **retrospektiven
  Ertragsbericht**: die bereits im Ledger gebuchten Dividenden und Zinsen, auf drei
  Arten aggregiert (keine Prognose — der Dividendenkalender ist eine separate
  Funktion). `annual` ist eine Liste von Jahren (neueste zuerst), jedes mit
  `months` (eine Map mit Monatszahl-Schlüsseln `"1"`–`"12"`, jeweils mit
  `dividends` und `interest`) und je Jahr `dividends_total`, `interest_total` und
  `total`. `positions` ist die Pro-Position-Tabelle: `security_id`,
  `security_name`, `security_currency` (die ursprüngliche Buchungswährung),
  `gross`, `tax` (die einbehaltene Steuer, aus den auf der Transaktion
  gespeicherten TAX-Einheiten der Dividende), `net` (`gross - tax`),
  `payment_count` und `last_payment`. `transactions` ist das Detail je Transaktion
  für eine Jahres-Aufschlüsselung (`kind`, `date`, `year`,
  `security_id`/`security_name`, `currency`, das native `native_gross`/
  `native_tax`/`native_net`, das `gross`/`tax`/`net` in Basiswährung und
  `converted`). Das Brutto einer Dividende ist ihr Netto-Cash (`gross_amount`) plus
  die einbehaltene Steuer; Zinsen tragen keine Quellensteuer. Alle Beträge sind
  Decimal-Strings in der `base_currency` des Portfolios, umgerechnet über den
  EUR-Hub zum gespeicherten Kurs des jeweiligen Buchungsdatums (dieselbe Mechanik
  wie der Bewertungs-Endpunkt), mit beibehaltener ursprünglicher Währung;
  `unconverted_count` zählt Buchungen ohne Kurspfad (zur Parität umgerechnet), und
  `conversion_note` nennt die Basis. Unbekannte Portfolios liefern
  `404 Not Found`.
  Seit ADR-0020 gehört ein SOLL-Zielplan zu einer **Sicht (View)**: Die
  Lese-/Schreib-Endpunkte für Ziele akzeptieren ein optionales `view` (eine
  View-id). Wird es weggelassen (oder als `null` gesendet), adressiert es den
  portfolioweiten **Gesamt**-Plan — das Verhalten vor Einführung der Views. Eine
  View trägt ihren eigenen Plan, sodass dieselbe Klassifizierung pro View einen
  anderen Plan halten kann, ohne dass sich die Pläne übereinander summieren. Ein
  fehlerhaftes `view` liefert `422 Unprocessable Entity` (`{"view": ["is
  invalid"]}`) und eine unbekannte View-id liefert `404 Not Found` — derselbe
  strukturierte Vertrag wie bei den Analyse-Endpunkten.
- `GET /api/v1/portfolios/:portfolio_id/targets` listet die gespeicherten
  Zielgewichte eines Portfolios (die SOLL-Seite der Allokation). Optionales
  `classification_id` schränkt die Liste auf einen Baum ein; optionales `view`
  wählt den Plan (weggelassen = Gesamt). Unbekannte Portfolios liefern `404 Not
  Found`.
- `PUT /api/v1/portfolios/:portfolio_id/targets` führt Zielgewichte für eine
  Klassifizierung ein (Upsert). Der Body ist `{"classification_id": id, "targets":
  [{"category_id": id, "target_weight": "0.25"}]}` und kann ein optionales
  `"view": id` tragen, um den Plan dieser View zu schreiben (weggelassen =
  Gesamt). Jedes `target_weight` ist ein String-Bruch in `[0, 1]`; Ziele müssen
  sich nicht zu `1` summieren. Nur die übergebenen Kategorien werden geändert.
  Eine Kategorie aus einem anderen Baum liefert `422 Unprocessable Entity`, und
  eine unbekannte Klassifizierung liefert `404 Not Found`.
- `DELETE /api/v1/portfolios/:portfolio_id/targets/:category_id` entfernt das
  Zielgewicht eines Portfolios für eine Kategorie und liefert `{deleted}` (die Zahl
  der entfernten Zeilen). Optionales `view` wählt den Plan (weggelassen = Gesamt).
- `GET /api/v1/portfolios/:portfolio_id/allocation` liefert die
  SOLL/IST-Aufschlüsselung für eine Klassifizierung (erforderlicher
  `classification_id`-Query-Parameter; ein fehlender liefert
  `422 Unprocessable Entity`). Für jede Kategorie meldet es `parent_id` und `depth`
  (die Kategorien bilden einen Baum), `color`, `own_market_value` (direkt
  zugeordnete Positionen), `market_value` (ihr ganzer aufgerollter Teilbaum),
  `actual_weight` (der aufgerollte Anteil an `total_value`), `target_weight`,
  `drift_weight` (`actual_weight - target_weight`: positiv = übergewichtet,
  negativ = untergewichtet; ADR-0023) und `drift_value` (die Drift in
  Basiswährung neu ausgewiesen — wie viel zu verkaufen (positiv) oder zu kaufen
  (negativ) ist, um das Ziel zu erreichen). Jede Zeile trägt zudem `child_target_sum`
  (Decimal-String): die beratende Summe der Ziele ihrer **direkten** Kinder, oder
  `null`, wenn kein direktes Kind ein Ziel trägt — ein Konsistenzhinweis, den die
  UI gegen das eigene `target_weight` der Zeile abgleichen kann. Eine einem Kind
  zugeordnete Position zählt zu
  diesem Kind **und jedem Vorfahren**, sodass eine übergeordnete Kategorie mit Ziel
  gegen ihren Teilbaum verglichen wird, statt 0 % zu zeigen; die Zeilen kommen in
  Baumreihenfolge zurück (Eltern vor ihren Kindern). Da Eltern ihre Kinder
  aggregieren, summieren sich die `actual_weight`-Werte je Kategorie bewusst nicht
  über die Ebenen zu 1 — nur die Blätter plus `unassigned` tun es. Jede Kategorie
  (und `unassigned`) trägt außerdem `positions`: die Aufschlüsselung je Wertpapier
  ihres **eigenen** (direkt zugeordneten) Werts — `security_id`, `security_name`,
  `quantity`, `market_value`, `weight`, plus die reinen Anzeige-Hinweise fürs
  Rebalancing (ADR-0023): `drift_value` (der proportionale Anteil der Position an
  der Kategorie-Drift) und `rebalance_quantity` (indikative Stückzahl, die zum
  impliziten Stückpreis der Bewertung zu verkaufen (positiv) oder zu kaufen
  (negativ) wäre; ohne Gebühren-/Steuermodell, nie eine Order). Beide Hinweise
  sind ohne Plan und für `unassigned`-Positionen ohne eigenes Positions-Soll
  `null`. Einträge kommen größte zuerst, Wertpapiere über Depots
  zusammengeführt; das ist es, was der äußerste Ring des Sunburst rendert.
  **Positions-Soll (ADR-0030 Slice 2a):** die `positions` einer Kategorie sind
  die Vereinigung ihrer gehaltenen Positionen und der Positions-Ziel-Zeilen des
  aktiven Plans, je Wertpapier zusammengeführt. Jeder Eintrag trägt zusätzlich
  `target_weight` (sein Positions-Soll, `null` ohne eines), `drift_weight`
  (`IST-Gewicht − SOLL-Gewicht`, ADR-0023-Vorzeichen) und `held`. Ein Eintrag
  mit eigenem Soll leitet `drift_value` und `rebalance_quantity` aus dieser
  eigenen Drift ab statt aus dem Kategorie-Anteil. Eine Position mit Soll > 0
  ohne Bestand erscheint mit IST 0 (`held: false`, Menge/Wert/Gewicht `"0"`)
  und voller Untergewichts-Drift — „hier muss gekauft werden" — mit ihrer
  indikativen Stückzahl zum **letzten gespeicherten Kurs** (`null` ohne Kurs;
  keiner wird erfunden); `quote_date` nennt das Datum dieses Kurses (`null`,
  wenn der Hinweis nicht kursbasiert ist). `held` heißt Bestand vorhanden: ein
  gehaltenes Wertpapier ohne ermittelbaren Preis wird nie als ohne Bestand
  gemeldet (es bleibt auf den Unbewertet-Flächen). Jeder Eintrag trägt zudem
  `stale` (`true`, wenn seine abgelegte Positions-Ziel-Zeile nicht mehr zur
  aktuellen Kategorie des Wertpapiers passt). Eine Position wird nur
  ausgeblendet, wenn ihr Soll 0/fehlend ist **und** ihr Bestand null. Jede
  Kategorie-Zeile trägt zudem `conflict` (explizites Gewicht und
  Positions-Summe weichen ab — die Summe steuert) und `has_stale` (eine hier
  abgelegte Positions-Zeile ist veraltet), und die Aufschlüsselung trägt
  `deep_target_sum` — die Summe der effektiven Ziele auf der obersten
  gezielten Ebene je Teilbaum, die eine `top_level_target_sum` von `0` über
  einem tiefer gesteckten Plan erklärt.
  Gehaltene, aber im Baum nicht zugeordnete Wertpapiere werden in `unassigned`
  summiert; auch `unassigned`-Einträge tragen ihr Positions-Soll.
  Gewichte sind Anteile der **Steuerbasis**: der Gesamtwert der
  bewerteten Positionen (eingeschränkt durch die aktive `view`, sofern angegeben),
  **plus das verfügbare Cash** (`free_cash`-Konten mit
  nicht-negativem Saldo). `total_value` ist hier diese
  Steuerbasis (nicht die volle Bewertung). Die Antwort trägt ein `cash`-Objekt —
  `market_value` (das zählende Cash), `actual_weight` (sein Anteil an
  `total_value`), `target_weight` (das Cash-Ziel des Plans der aktiven View oder
  `0`, wenn nicht gesetzt; siehe die Cash-Ziel-Endpunkte unten), `drift_weight`
  (`actual_weight - target_weight`, ADR-0023),
  `drift_value` (in Basiswährung neu ausgewiesen) und `distributed` (Boolean) —
  sodass Cash in derselben Drift-Logik wie die Kategorien gesteuert wird. Ist die
  aktive Klassifizierung der eingebaute **Währungs**-Baum, wird das Cash jedes
  Geldkontos seiner eigenen Währungskategorie zugeordnet statt als eigene
  Cash-Zeile zu erscheinen (EUR-Cash → EUR-Kategorie, USD-Cash → USD usw.); in
  diesem Fall ist `cash.distributed` `true` und Konsumenten sollten die separate
  Cash-Zeile weglassen. Da Cash Teil der 100 %-Basis ist, schrumpfen die
  Kategorie-Prozentsätze entsprechend, sobald Cash vorhanden ist. Der
  `top_level_target_sum` ist die Summe der Ziele der Wurzelkategorien **plus das
  Cash-Ziel** (außer im Währungs-Baum, wo Cash in Kategorien verteilt wird),
  verglichen mit `1`. Um einen Bestand aus der Steuerbasis herauszuhalten,
  während er weiterhin zum Gesamtvermögen zählt, den Bestand mit einem
  Bucket versehen und diesen Bucket aus der `view` ausschließen, unter der die
  Allokation gelesen wird — er fällt dann aus den eingeschränkten Positionen. Seit
  ADR-0020 spiegelt die **SOLL**-Seite den **Plan der aktiven View** wider: Mit
  `view=<id>` werden die Zielgewichte, das Cash-Ziel und der
  `top_level_target_sum` dieser View ausgewiesen (ohne `view` der Gesamt-Plan),
  sodass die Drift-Tabelle pro View gegen einen kohärenten 100 %-Plan steuert.
  Die `target_weight`-Werte der Kategorien sind die **effektiven** Ziele
  (ADR-0030): die Summe der Positions-Zeilen einer Kategorie, sobald welche
  existieren (Positionen sind die Quelle der Wahrheit), sonst ihr explizites
  Kategorien-Gewicht — die Σ-Werte verwenden dieselben effektiven Zahlen. Für
  die rohen Positions-Ziel-Zeilen und den Roll-up je Kategorie (die
  Pflege-Sicht) dient der `position_targets`-Endpunkt oben. Unbekannte
  Portfolios oder Klassifizierungen liefern `404 Not
  Found`. Lese-Ergonomie (FR-37): `include_positions=false` lässt die
  Positionszeilen je Kategorie (und in `unassigned`) für einen reinen
  Roll-up weg, und `min_drift=<decimal>` (eine absolute Drift-Schwelle,
  z. B. `0.02`) liefert nur die Kategoriezeilen, deren `|drift_weight|` sie
  erreicht — ziellose Kategorien tragen keine Drift und werden mitgefiltert;
  behaltene Zeilen kommen flach zurück (ein Vorfahre unter der Schwelle
  fehlt). Die Antwort benennt ihre eigene Basis: `positions_included`, das
  angewandte `min_drift` und `categories_total` (die Zeilenzahl vor dem
  Filter). Ungültige Werte sind ein `422`. Die Allokationsseite trägt
  denselben Filter als Abweichungs-Chips (ein gemeinsames Prädikat, die
  beiden Oberflächen können also keine unterschiedlichen Kategorien
  auswählen); die Chips sprechen Prozentpunkte, `≥ 5 pp` auf dem Bildschirm
  ist hier also `min_drift=0.05`. Dieselbe Schwelle, gleich geschrieben,
  gilt eine Ebene tiefer (#740): `GET
  /api/v1/portfolios/:portfolio_id/position_targets?min_drift=<decimal>`
  liefert nur die Positions-Ziel-Zeilen, deren `|drift_weight|` sie erreicht
  — `drift_weight` ist das tatsächliche Gewicht des Wertpapiers in der
  Steuerbasis minus sein Positionsziel, genau wie die Allokation es rechnet;
  behaltene Zeilen tragen `drift_weight`, Zeilen ohne Drift werden
  mitgefiltert, und die Antwort benennt `min_drift`, `position_targets_total`
  (die Zeilenzahl vor dem Filter) und `drift_basis`. Ohne `min_drift` ist die
  Form unverändert. `tax_context=true` (#667) hängt
  zusätzlich die steuerfreien Trim-Budgets des laufenden Jahres an — ein
  Eintrag je Inhaber mit erfassten Auszügen, jeweils mit seiner
  aktivitätsbewussten `staleness` — sodass der Steuer-Spielraum dort lesbar
  ist, wo die Trim-Entscheidung fällt; der Block benennt, dass er je
  `(Inhaber, Steuerjahr)` über Institute rollt und nie auf Portfolio oder
  View eingeschränkt ist.
- `GET /api/v1/portfolios/:portfolio_id/risk` liefert eine
  **Risiko-/Konzentrationssicht** für ein Portfolio über die **Steuerbasis** (der
  Gesamtwert der bewerteten Positionen, eingeschränkt durch die aktive `view` —
  dieselbe Basis wie
  die Allocation-Drift). Ein über mehrere Depots gehaltenes Wertpapier wird zu
  einer Einzeltitel-Position zusammengeführt. Gewichte, Caps und der HHI liegen
  alle auf einer **0-100-Prozentskala** (Decimal-Strings, volle Präzision, keine
  Rundung):
  - `steerable_basis` ist die Basis, deren Anteil die Gewichte sind, und
    `base_currency` die Basiswährung des Portfolios.
  - `top_holdings` sind die größten Einzeltitel-Positionen, größte zuerst,
    Standard **N = 10** (überschreibbar mit dem `top_n`-Query-Parameter). Jeder
    Eintrag trägt `security_id`, `security_name`, `asset_class`, `market_value`,
    `weight` und einen `severity` (`ok`/`warn`/`hard`). Der `severity` ist
    **instrumententyp-abhängig**: eine Einzelaktie warnt über `7` und wird hart
    über `10`; ein **ETF** (die Anlageklasse `etf`) warnt über `25` und wird nie
    hart. Überschreibe die Standardwerte mit den Query-Parametern
    `stock_thresholds[warn]`/`stock_thresholds[hard]` und `etf_thresholds[warn]`.
  - `hhi` trägt den Herfindahl-Hirschman-Index der Einzeltitel-Gewichte (`value`
    = Summe der quadrierten Prozentgewichte, auf der `0-10000`-Skala) plus ein
    `band`: `low` (`< 1500`), `moderate` (`[1500, 2500]`) oder `concentrated`
    (`> 2500`). Überschreibe die Schwellen mit `hhi_bands[low]` und
    `hhi_bands[high]`.
  - `asset_class_violations` sind **opt-in** Anlageklassen-Cap-Verletzungen: es
    gibt keine voreingestellten Standardwerte, Caps werden pro Aufruf mit dem
    Query-Parameter `asset_class_caps[<asset_class>]` (ein Prozentwert, z. B.
    `asset_class_caps[equity]=50`) konfiguriert. Nur Klassen, deren aktuelles
    Prozentgewicht den Cap übersteigt, kommen zurück, je mit `asset_class`,
    `current_weight`, `cap` und `overage` (aktuell − Cap, in Prozentpunkten).

  Die Sicht ist eine reine Lese-Ableitung der Live-Bewertung und der
  Anlageklassen-Klassifizierung — nichts wird gespeichert, sie ist also
  deterministisch beim Lesen. Eine ungültige Überschreibung (z. B. ein
  nicht-positiver `top_n`) liefert `422 Unprocessable Entity`; unbekannte
  Portfolios liefern `404 Not Found`.
- `GET /api/v1/portfolios/:portfolio_id/cash_target` liest das Cash-Ziel eines
  Plans, den SOLL-Cash-Anteil an der 100 %-Basis der Allokation (Wertpapiere +
  zählendes Cash). Die Antwort ist `{"cash_target_weight": "0.05"}` (ein
  String-Bruch in `[0, 1]` oder `null`, wenn keines gesteuert wird). Optionales
  `view` wählt den Plan (weggelassen = der Gesamt-Plan). Unbekannte Portfolios
  liefern `404 Not Found`, ein fehlerhaftes `view` liefert `422` und eine
  unbekannte View-id `404`.
- `PUT /api/v1/portfolios/:portfolio_id/cash_target` setzt (oder löscht mit
  `null`) das Cash-Ziel eines Plans. Der Body ist `{"cash_target_weight":
  "0.05"}` und kann ein optionales `"view": id` tragen (weggelassen = Gesamt). Es
  gibt den gespeicherten Wert zurück. Gewichte außerhalb des Bereichs liefern
  `422 Unprocessable Entity`. Das Cash-Ziel speist die `cash`-Zeile der Allokation
  und den `top_level_target_sum` der adressierten View.
- `PATCH /api/v1/portfolios/:portfolio_id` patcht die Stammdaten eines Portfolios.
  **Veraltet (ADR-0024)** — antwortet mit `Deprecation: true`; nur
  Kompatibilität, nutze Buckets/Ansichten zur Gruppierung. Der Body ist
  `{"portfolio": {...}}`. **Umzug des Cash-Ziels (ADR-0020):** Das
  Cash-Ziel ist vom Portfolio-Objekt auf den View-gebundenen SOLL-Plan gewandert
  und wird über die beiden `cash_target`-Endpunkte oben bedient. Aus
  **Kompatibilitätsgründen** stellt das Portfolio-Objekt weiterhin
  `cash_target_weight` bereit — einen String-Bruch in `[0, 1]` (z. B. `"0.05"`
  für 5 %) oder `null`, um die Steuerung einer Cash-Quote zu beenden — und das
  Patchen liest/schreibt das Cash-Ziel des **Gesamt**-Plans (`view` weggelassen).
  Ein Client, der nur das alte Feld kennt, funktioniert also unverändert weiter;
  nutze `PUT /cash_target?view=<id>` für ein View-spezifisches Cash-Ziel. Gewichte
  außerhalb des Bereichs liefern `422 Unprocessable Entity`; unbekannte Portfolios
  liefern `404 Not Found`. Das `cash_target_weight` ist auch in den von
  `GET`/`POST /api/v1/portfolios` zurückgegebenen Portfolio-Objekten enthalten
  (das Gesamt-Cash-Ziel).
- `GET /api/v1/securities/:security_id/trades` liefert FIFO-gematchte Trades eines
  Wertpapiers: offene Lots, geschlossene Round-Trips (mit realisiertem G/V und
  Haltedauer in Tagen) und etwaige verwaiste Verkäufe. Jedes offene Lot trägt
  `buy_price` (wie erfasst, Transaktionswährung) plus `buy_price_native` — die
  Basis in Wertpapierwährung, gegen die sein `unrealized_pnl_*` gerechnet wird
  (ADR-0033) — und dieselben Zerlegungsfelder in Basiswährung wie die
  Bestandszeilen (`base_cost`, `price_return_*`, `currency_return_*`,
  `total_return_base_*`, `decomposed`/`undecomposed_reason`, gegen den
  EUR-Hub, da FIFO-Lots je Wertpapier über Portfolios hinweg gematcht
  werden). Ein Lot ohne ableitbares Wertpapierwährungs-Leg meldet `null`-G/V
  statt eines blinden währungsübergreifenden Vergleichs. Die Antwort ist
  selbstbeschreibend (FR-13): sie trägt `method: "fifo"`, sodass ein Client nie
  annehmen muss, wie Lots gegen Verkäufe gepaart wurden. Optionales `from`/`to`
  (ISO-Daten) filtert jedes Bein nach seinem eigenen Datum: offene Lots nach
  Eröffnungsdatum, geschlossene Round-Trips nach Schlussdatum, verwaiste Verkäufe
  nach Verkaufsdatum.

## Wechselkurse

- `GET /api/v1/exchange_rates` listet gespeicherte Wechselkurse. Kurse werden
  gegen den EUR-Hub gehalten (`1 base_currency = rate quote_currency`); andere
  Paare werden durch Triangulation abgeleitet, und `GBX` (Pence) wird als
  `GBP × 100` behandelt.
- `POST /api/v1/exchange_rates/sync` holt Kurse vom konfigurierten Anbieter
  (standardmäßig EZB) und liefert `{provider, status, upserted, scope}`.
  `scope=latest` (Standard) holt den **täglichen** Feed — die heutigen Kurse,
  nichts aus der Vergangenheit. `scope=history` (Issue #737, Sprint-9-D-1)
  führt das **einmalige Backfill** der historischen EZB-Reihe
  (`eurofxref-hist.xml`) über denselben Upsert-Pfad aus: jeden
  veröffentlichten Tag auf einmal, sodass eine datierte Umrechnung (ein
  realisierter Gewinn, eine Kosten- oder Flussbuchung, die die
  Cashflow-Facetten wegen eines fehlenden Buchungstagskurses ausgeschlossen
  und benannt haben) ihren Kurs findet. Die Regel zur Kursverfügbarkeit
  bleibt unverändert — ein Tag, den die EZB nicht veröffentlicht hat (ein
  Wochenende, eine nicht gelistete Währung), bleibt ausgeschlossen und
  benannt; das Backfill füllt Daten, es lockert die Basis „exakter
  Buchungstagskurs“ nicht. Ein unbekannter `scope` ist ein `422`, ein
  Anbieter ohne Historie antwortet mit `422` und benennt `scope`, ein
  Anbieterfehler liefert `502 Bad Gateway`. Die menschliche Sicht ist die
  Schaltfläche **Historische Kurse nachladen** in den Ausschluss-Hinweisen
  auf `/cashflow`.

## Klassifizierungen

Klassifizierungsbäume ordnen Wertpapiere wie Ordner. Integrierte Bäume
(`asset_class`, `currency`) werden automatisch abgeleitet und ihre Struktur ist
gesperrt; das Bearbeiten der Struktur eines integrierten Baums liefert
`422 Unprocessable Entity`. Die **Mitgliedschaft** des **Anlageklassen**-Baums
ist jedoch nur eine Sicht auf das `asset_class`-Feld jedes Wertpapiers: in der UI
wird ein Wertpapier zwischen seinen Kategorien gezogen (was dieses Feld
setzt), und derselbe Effekt wird über die API mit `PATCH /api/v1/securities/:id`
(`{"security": {"asset_class": "etf"}}`) oder dem MCP-Tool `securities.update`
erzielt. Setze es auf leer/`null` für „automatisch", was die Klasse beim Lesen aus
Name/ISIN/Ticker neu inferiert. Der Währungsbaum bleibt intrinsisch und kann nicht
neu zugeordnet werden.

- `GET /api/v1/classifications` listet jede Klassifizierung als Baum mit ihren
  `categories` und `assignments` (`{security_id, category_id}`). Integrierte Bäume
  tragen `built_in: true` und einen `key`.
- `POST /api/v1/classifications` legt eine eigene Klassifizierung aus einem
  `classification`-Objekt an (`name`, optional `position`, `description`).
- `PATCH /api/v1/classifications/:id` aktualisiert das `classification`-Objekt
  einer eigenen Klassifizierung (`name`, `position`, `description` — alle optional).
- `DELETE /api/v1/classifications/:id` löscht eine eigene Klassifizierung und
  kaskadiert ihre Kategorien und Zuordnungen.
- `POST /api/v1/classifications/:classification_id/categories` fügt einer eigenen
  Klassifizierung eine `category` hinzu (`name`, optional `color`, `description`,
  `parent_id`, `position`).
- `PATCH /api/v1/classifications/:classification_id/categories/:id` patcht eine
  `category` (`name`, `color`, `description`, `parent_id`, `position` — alle
  optional). Die `classification_id` der Kategorie kann so nicht geändert werden.
- `DELETE /api/v1/classifications/:classification_id/categories/:id` löscht eine
  Kategorie und kaskadiert ihre Unterkategorien und Zuordnungen.
- `PUT /api/v1/classifications/:classification_id/assignments` ordnet ein
  Wertpapier einer Kategorie zu (`security_id`, `category_id`) und ersetzt jede
  bestehende Zuordnung dieses Wertpapiers in der Klassifizierung. Die Antwort trägt
  einen `status` von `created`, `moved` oder `unchanged` plus
  `previous_category_id`.
- `PUT /api/v1/classifications/:classification_id/assignments/bulk` ordnet viele
  Wertpapiere in einem Aufruf einer Kategorie zu (`category_id`, `security_ids`)
  und liefert `{assigned, category_id, security_ids}`.
- `DELETE /api/v1/classifications/:classification_id/assignments/:security_id`
  entfernt die Zuordnung eines Wertpapiers aus der Klassifizierung.

Beispiel-Payload für eine Transaktion:

```json
{
  "transaction": {
    "portfolio_id": 1,
    "securities_account_id": 1,
    "security_id": 1,
    "type": "buy",
    "date": "2026-05-15",
    "quantity": "10.00000000",
    "price": "123.45",
    "fees": "1.50",
    "taxes": "0",
    "currency_code": "EUR"
  }
}
```

## Buckets und Views

Buckets sind überlappende Tags, die auf Bestände (Depots, Geldkonten und
einzelne Wertpapier-Positionen) angewendet werden, um Vermögen tag-basiert
einzugrenzen. Views sind benannte, globale Filter über diese Buckets: ein
Bestand passt, wenn er eingeschlossen ist (immer unter `include_all`, sonst wenn
er einen der Include-Buckets der View trägt) und keinen der Exclude-Buckets der
View trägt — Exclude gewinnt immer. Bucket-Definitions- und
Zuordnungs-Schreibvorgänge werden journalisiert (ADR-0017);
View-Definitions-Schreibvorgänge bewusst nicht (ADR-0018 §5).

- `GET /api/v1/buckets` listet Buckets (`id`, `name`, `color`).
- `POST /api/v1/buckets` legt einen Bucket aus einem `bucket`-Objekt an (`name`
  erforderlich, optionales `color`). Ein leerer oder doppelter Name ergibt `422`.
- `GET /api/v1/buckets/:id` liefert einen Bucket; unbekannte ids ergeben `404`.
- `PATCH /api/v1/buckets/:id` ändert `name`/`color` eines Buckets.
- `DELETE /api/v1/buckets/:id` löscht einen Bucket und entfernt ihn aus jeder
  Zuordnung und jedem View-Set, Antwort `204 No Content`.
- `GET /api/v1/views` listet Views. Jede View trägt `include_all`, das aufgelöste
  `include`-Set (das Literal `"all"` unter `include_all`, sonst eine Liste von
  Bucket-ids) und die `exclude`-Liste von Bucket-ids.
- `POST /api/v1/views` legt eine View aus einem `view`-Objekt an (`name`
  erforderlich, optionales `include_all`, Standard `true`).
- `GET /api/v1/views/:id` liefert eine View mit ihrem aufgelösten Filter.
- `PATCH /api/v1/views/:id` ändert `name`/`include_all` einer View.
- `DELETE /api/v1/views/:id` löscht eine View und ihre Bucket-Sets (`204`).
- `PUT /api/v1/views/:id/buckets` ersetzt die Include-/Exclude-Bucket-Sets einer
  View. Body: `{"include": [..], "exclude": [..]}` (beide optional, Standard
  `[]`, Listen von Bucket-ids). Eine fehlerhafte id-Liste ergibt `422`.
- `GET /api/v1/views/:view_id/valuation` liefert die Live-Bewertung einer View
  **über alle Portfolios** (ADR-0024) in der Form der Portfolio-Bewertung mit
  `view_id` statt `portfolio_id`; jedes zur View passende Konto zählt genau
  einmal, `overlap` nennt die Konten mit mehreren eingeschlossenen Buckets.
  `include_positions=false` (FR-37, #740 — derselbe Parameter wie bei der
  Portfolio-Bewertung) liefert nur den Roll-up: Summen, Cash-Salden und
  Cash-Quote ohne die Positionszeilen; die Antwort benennt
  `positions_included`. Ein ungültiger Wert ist ein `422`.
- `GET /api/v1/views/:view_id/performance` liefert TTWROR und geldgewichtete
  Rendite (IRR) der View **über alle Portfolios**: exakt der deduplizierte
  Konten-Scope, den auch die View-Bewertung abdeckt, sodass Gesamtwert und
  Rendite immer über dieselben Konten sprechen. Geld, das die View-Grenze
  überquert, zählt als externer Fluss (ADR-0019); Geld zwischen zwei Konten
  innerhalb der View saldiert sich. `?period=` (`ytd|1y|3y|5y|max`, Standard
  `max`), `?year=YYYY`, `?from=`/`?to=` (freier Zeitraum) und `?series=true`
  verhalten sich wie beim Portfolio-Performance-Endpunkt; die Antwort spiegelt
  dessen Form mit `view_id` statt `portfolio_id`, alle Finanzwerte sind
  Decimal-Strings. Unbekannte und fehlerhafte View-ids liefern `404`, ein
  fehlerhafter Zeitraum `422`.
- `PUT /api/v1/securities_accounts/:id/buckets` ersetzt das Standard-Bucket-Set
  eines Depots (die Buckets, die jede Position erbt, sofern nicht überschrieben).
  Body: `{"bucket_ids": [..]}`.
- `PUT /api/v1/cash_accounts/:id/buckets` ersetzt das Bucket-Set eines
  Geldkontos. Body: `{"bucket_ids": [..]}`.
- `PUT /api/v1/securities_accounts/:id/positions/:security_id/buckets` setzt die
  Positions-Überschreibung für ein Wertpapier in einem Depot. Ein leeres
  `bucket_ids` speichert den **explizit-leeren** Zustand (bewusst keine Buckets),
  unterschieden vom Erben des Depot-Standards; die Überschreibung gewinnt immer
  gegenüber dem Depot-Standard. Die Antwort nennt das aufgelöste `override`
  (`inherit`, `explicit_empty` oder `explicit`) und die `effective_bucket_ids`.
- `DELETE /api/v1/securities_accounts/:id/positions/:security_id/buckets` setzt
  die Überschreibung zurück, sodass die Position wieder den Depot-Standard erbt.

Die Analyse-Endpunkte akzeptieren einen optionalen `view`-Query-Parameter (eine
View-id), um das Ergebnis auf die Bestände der View einzugrenzen:

- `GET /api/v1/portfolios/:portfolio_id/valuation?view=<id>`
- `GET /api/v1/portfolios/:portfolio_id/allocation?classification_id=<id>&view=<id>`
- `GET /api/v1/portfolios/:portfolio_id/performance?view=<id>`
- `GET /api/v1/portfolios/:portfolio_id/risk?view=<id>`

Bei gesetztem `view` spiegelt die Antwort die aktive View als `view: {id, name}`
wider (FR-13); der Aufruf ohne View ist unverändert und trägt kein `view`-Feld.
Eine fehlerhafte View-id ergibt `422`, eine unbekannte `404`. Derselbe
`view`-Scope (und derselbe `422`/`404`-Vertrag) gilt für die SOLL-Ziel-Endpunkte
— `GET`/`PUT /api/v1/portfolios/:portfolio_id/targets`, `DELETE
/api/v1/portfolios/:portfolio_id/targets/:category_id` und die
Cash-Ziel-Endpunkte `GET`/`PUT /api/v1/portfolios/:portfolio_id/cash_target` —,
wo eine View den SOLL-Plan wählt (weggelassen = der Gesamt-Plan). Der Bestände-
Endpunkt (`GET /api/v1/portfolios/:portfolio_id/holdings`) ist **nicht**
view-eingegrenzt: er liefert die Roh-Zeilen pro (Depot, Wertpapier) in der
jeweiligen Wertpapierwährung, sodass ein Client das Buckets/Views-Modell selbst
anhand von `securities_account_id` und `security_id` jeder Zeile anwenden kann.

## Einstellungen

Ein minimaler Schlüssel-Wert-Speicher trägt die nutzerseitigen Voreinstellungen
(ADR-0024). Heute gibt es eine: die **Standard-Ansicht**, mit der Vermögensseite
und Übersicht öffnen, wenn in der UI keine Ansicht ausdrücklich gewählt wurde.
Finanzielle Decimals kommen hier nicht vor.

- `GET /api/v1/settings/default_view` liefert die aktuelle Voreinstellung:
  `{"data": {"view_id": null, "view": null}}` wenn keine gesetzt ist (die
  eingebaute Alles-Sicht), sonst die id plus ein `view: {id, name}`-Echo.
- `PUT /api/v1/settings/default_view` setzt sie. Body: `{"view_id": <id>}` mit
  einer existierenden View-id, oder `{"view_id": null}` zum Zurücksetzen auf
  Alles. Eine unbekannte View-id liefert `404` (nichts wird geschrieben); eine
  fehlerhafte `view_id` liefert `422`. Die Antwort entspricht dem `GET`-Format.

## Importe

Portfolio-Performance-Importe (CSV/JSON v1) laufen ausschließlich über die
**Import-Ansicht**: Es gibt absichtlich keinen Import-Endpunkt unter
`/api/v1` und kein MCP-Tool dafür — der Vorschau-dann-Anwenden-Schritt mit
seinen Zuordnungsentscheidungen ist eine Betreiber-Handlung (ADR-0029). Was
API- und MCP-Konsumenten wissen müssen, ist die **Bewahrungsgarantie beim
erneuten Import**, denn alles, was ein Agent über diese API schreibt, liegt
neben der importierten Historie:

- **Dasselbe Export erneut anwenden ist ein No-op per Inhalts-Hash.** Jede
  bereits vorhandene Transaktionszeile wird als Duplikat übersprungen; kein
  Wertpapier wird doppelt angelegt; die Antwort des Anwendens meldet die
  übersprungene Anzahl.
- **Was einen erneuten Import unverändert übersteht, gleiche ids, exakte
  `Decimal`-Werte:** Klassifizierungs-Zuordnungen; jede Zielplan-Version mit
  ihren Kategorie- und Positionszielen sowie dem Cash-Ziel; `note` und
  `attributes` jedes Wertpapiers einschließlich eigener Schlüssel; das
  **Research-Log** (`/api/v1/securities/:id/notes` — die nur anhängbaren
  Einträge und der daraus abgeleitete `thesis_state`, ADR-0044);
  Wertpapier-ids und `updated_at`. Festgehalten in
  `test/portfolixir/imports/reimport_preservation_test.exs` seit Issue #664
  (Research-Log ergänzt durch #748).
- **Ein veränderter erneuter Import** (eine Umbenennung, ein erfasster
  ISIN-Wechsel, der über einen Alias oder eine explizite Zuordnung aufgelöst
  wird) hält dieselbe Garantie für die zugeordneten Wertpapiere; nur die
  wirklich neuen Buchungen landen.
- **Nicht abgedeckt:** eine in der Quelle geänderte Buchung. Eine bearbeitete
  Transaktion hasht anders und wird als neue Zeile neben der alten importiert;
  die alte Buchung wird über `PATCH`/`DELETE /api/v1/transactions/:id`
  entfernt oder korrigiert. Die Garantie betrifft, was Portfolixir rund um
  die Historie pflegt, nicht den Abgleich zweier Versionen der Historie
  selbst.

Ein Research-Log, ein Plan oder eine Zuordnung „verschwindet“ also nie beim
nächsten Import; ein Agent, der etwas anderes beobachtet, hat einen Defekt
gefunden, keine dokumentierte Grenze.

## Audit-Journal

Jeder finanzielle Schreibvorgang (Anlegen, Ändern, Löschen) wird in einem
append-only Audit-Journal in derselben Datenbanktransaktion wie der Schreibvorgang
selbst festgehalten, sodass jede Änderung — auch Löschungen — nachvollziehbar und
zurechenbar bleibt. Marktdaten-Synchronisierung (Kurse und Wechselkurse) ist
betriebliche Datenpflege und wird bewusst **nicht** journalisiert.

- `GET /api/v1/journal` listet Journal-Einträge, neueste zuerst. Jeder Eintrag
  trägt `actor_type` (`owner_ui`, `api_token_rw`, `api_token_ro`,
  `import_session`, `system_job`) und ein optionales `actor_label`, die
  `operation` (`create`, `update`, `delete`, `upsert`), den betroffenen
  `resource_type`/`resource_id` sowie die `before`/`after`-Schnappschüsse
  (Decimal-Werte sind Strings). Optionale Filter: `resource_type`,
  `resource_id`, `actor_type`, `operation`, `limit` (Standard 100, max. 1000)
  und `include_scenarios` (`true`, um persistierte Was-wäre-wenn-Schreibvorgänge
  einzuschließen; standardmäßig nur echte Schreibvorgänge). Die Antwort ist
  selbstbeschreibend: ein `meta`-Objekt nennt den `as_of`-Zeitpunkt, die
  Sortierung `order` (`inserted_at:desc,id:desc`), die Anzahl `count` und die
  angewandten `filters`.

Das Journal deckt derzeit die Kontexte Catalog/Fx ab (Wertpapier-Stammdaten);
die übrigen Schreibkontexte werden nacheinander scharfgeschaltet.

## MCP-Tools

Der MCP-Begleitdienst stellt denselben lokalen Kontrakt als Tool-Aufrufe bereit.
Decimal-Eingaben in MCP-Schemata sind Strings.

- `portfolixir.securities.list`
- `portfolixir.securities.get` — vollständiger Datensatz eines Wertpapiers
  einschließlich seiner `identifier_aliases` (aufgezeichnete frühere ISINs)
  und seines abgeleiteten `thesis_state` (ADR-0044).
- `portfolixir.securities.create`
- `portfolixir.securities.update`
- `portfolixir.securities.delete`
- `portfolixir.securities.isin_change` — zeichnet einen
  Kapitalmaßnahmen-ISIN-Wechsel auf, damit Importe über die frühere ISIN
  weiter zuordnen (ADR-0029).
- `portfolixir.securities.delete_isin_alias` — journalisiertes Löschen eines
  aufgezeichneten Früher-ISIN-Alias.
- `portfolixir.securities.search_online`
- `portfolixir.notes.list` — das Research-Log eines Wertpapiers, neueste
  zuerst, mit dem abgeleiteten Thesenstand; die Beschreibung benennt, dass
  Einträge nie verschwinden (ADR-0044).
- `portfolixir.notes.append` — der einzige Schreibzugriff auf das Log; ein
  Widerruf mit `supersedes_id` zieht einen Befund zurück.
- `portfolixir.notes.unreviewed` — gehaltene Positionen ohne Eintrag seit N
  Tagen.
- `portfolixir.notes.uncorroborated` — Einträge, deren Quellenqualität nicht
  `primary` ist.
- `portfolixir.notes.expiring` — datierte Sperren, die in N Tagen ablaufen.
- `portfolixir.quotes.sync`
- `portfolixir.quotes.list`
- `portfolixir.quotes.upsert`
- `portfolixir.portfolios.list` — veraltet (ADR-0024): die Beschreibung
  verweist auf Buckets/Ansichten.
- `portfolixir.portfolios.create` — veraltet (ADR-0024): nur Kompatibilität;
  bevorzuge `portfolixir.buckets.create` / `portfolixir.views.create`.
- `portfolixir.cash_accounts.list`
- `portfolixir.cash_accounts.create`
- `portfolixir.cash_accounts.update`
- `portfolixir.cash_accounts.delete`
- `portfolixir.cash_accounts.set_balance`
- `portfolixir.securities_accounts.list`
- `portfolixir.securities_accounts.create`
- `portfolixir.securities_accounts.update`
- `portfolixir.securities_accounts.delete`
- `portfolixir.transactions.list`
- `portfolixir.transactions.create`
- `portfolixir.transactions.update`
- `portfolixir.transactions.delete`
- `portfolixir.splits.preview`
- `portfolixir.splits.create`
- `portfolixir.holdings.list`
- `portfolixir.cashflow.realized_gains` — das #724-Rollup mit erklärter
  FX-Basis und Ausschluss-und-Benennung bei Kurslücken
- `portfolixir.cashflow.external_flows` — das #725-Rollup mit erklärtem
  Unterschied zum investierten Kapital
- `portfolixir.cashflow.costs` — das #726-Rollup mit erklärter
  Nebenbeträge-statt-Brutto-Regel
- `portfolixir.holdings.by_security`
- `portfolixir.holdings.negative`
- `portfolixir.holdings.reconcile` — rein lesender Vergleich einer
  eingefügten externen Positionsliste mit dem Ledger; die Tool-Beschreibung
  lenkt den Agenten darauf, die fehlende Transaktion der richtigen Art zu
  buchen statt Saldo-Snapshots oder unbepreiste Einlieferungen zu nutzen.
- `portfolixir.portfolios.valuation`
- `portfolixir.exchange_rates.list`
- `portfolixir.exchange_rates.sync` — `scope=latest` (täglicher Feed) oder
  `scope=history` (das einmalige historische Backfill, Issue #737).
- `portfolixir.classifications.list`
- `portfolixir.classifications.create`
- `portfolixir.classifications.categories.create`
- `portfolixir.classifications.update`
- `portfolixir.classifications.delete`
- `portfolixir.classifications.categories.update`
- `portfolixir.classifications.categories.delete`
- `portfolixir.classifications.assign`
- `portfolixir.classifications.assign_bulk`
- `portfolixir.classifications.unassign`
- `portfolixir.trades.list`
- `portfolixir.targets.list`
- `portfolixir.targets.set`
- `portfolixir.targets.delete`
- `portfolixir.portfolios.allocation`
- `portfolixir.portfolios.risk`
- `portfolixir.portfolios.cash_target`
- `portfolixir.portfolios.set_cash_target`
- `portfolixir.portfolios.income`
- `portfolixir.portfolios.performance`
- `portfolixir.journal.list`
- `portfolixir.buckets.list`
- `portfolixir.buckets.get`
- `portfolixir.buckets.create`
- `portfolixir.buckets.update`
- `portfolixir.buckets.delete`
- `portfolixir.views.list`
- `portfolixir.views.get`
- `portfolixir.views.create`
- `portfolixir.views.update`
- `portfolixir.views.delete`
- `portfolixir.views.set_buckets`
- `portfolixir.views.performance`
- `portfolixir.securities_accounts.set_buckets`
- `portfolixir.cash_accounts.set_buckets`
- `portfolixir.securities_accounts.set_position_buckets`
- `portfolixir.securities_accounts.clear_position_buckets`
- `portfolixir.settings.get_default_view`
- `portfolixir.settings.set_default_view`

`portfolixir.views.performance` berechnet die passende portfolioübergreifende
TTWROR/IRR für denselben Konten-Scope; Geld, das die View-Grenze überquert,
wird als externer Fluss behandelt (ADR-0019).

`portfolixir.settings.get_default_view` /
`portfolixir.settings.set_default_view` lesen und setzen die
Standard-Ansicht-Voreinstellung (ADR-0024): eine `view_id` pinnt eine Ansicht,
`null` (oder weglassen) setzt auf die eingebaute Alles-Sicht zurück.

Die Tools `portfolixir.portfolios.valuation`,
`portfolixir.portfolios.allocation`, `portfolixir.portfolios.performance` und
`portfolixir.portfolios.risk` akzeptieren ein optionales `view` (eine View-id),
das das Ergebnis auf die Bestände der Bucket-View eingrenzt; die Antwort spiegelt
dann die aktive View wider.

Seit ADR-0020 akzeptieren auch die SOLL-Ziel-Tools (`portfolixir.targets.list`,
`portfolixir.targets.set`, `portfolixir.targets.delete`) und die Cash-Ziel-Tools
(`portfolixir.portfolios.cash_target` zum Lesen,
`portfolixir.portfolios.set_cash_target` zum Setzen oder Löschen) ein optionales
`view` (eine View-id), das den SOLL-Plan wählt; ohne `view` wird der
portfolioweite Gesamt-Plan adressiert. Das Cash-Ziel ist vom Portfolio-Objekt auf
den Plan gewandert, aber `portfolixir.portfolios.set_cash_target` ohne `view`
steuert weiterhin das Gesamt-Cash-Ziel und hat damit dieselbe Wirkung wie das
alte Portfolio-Feld `cash_target_weight`. Alle Cash-Ziele und Zielgewichte werden
als Decimal-Strings ausgegeben und akzeptiert.
