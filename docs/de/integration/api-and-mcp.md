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

## Wertpapiere

- `GET /api/v1/securities` listet Wertpapiere. Optionale Query-Parameter: `query`,
  `sort`, `direction`, holding_status (`all`, `held` oder `not_held`) und
  `limit`/`offset` zur Paginierung (beides nichtnegative Ganzzahlen). Nutze diese,
  um große Kataloge zu paginieren, statt die ganze Tabelle auf einmal zu holen.
- `POST /api/v1/securities` legt ein Wertpapier mit einem `security`-Objekt an.
  `asset_class` ist ein stabiler String-Code: `equity`, `etf`, `fund`,
  `government_bond`, `bond`, `crypto`, `commodity`, `index`, `other`, plus die
  Zertifikat-/Hebel-Codes `warrant`, `knock_out`, `factor_certificate`,
  `discount_certificate`, `bonus_certificate`, `express_certificate`,
  `reverse_convertible`. Lass es leer, damit die Klasse beim Lesen aus
  Name/ISIN/Ticker inferiert wird. Das optionale Boolean
  `excluded_from_allocation_targets` (Standard `false`) hält eine Position aus der
  Allokations-Steuerbasis (den 100 %) und der Drift-Tabelle heraus, während sie in
  den Bewertungssummen und der Performance bleibt — z. B. ein als Wertspeicher
  gehaltener Bitcoin; ausgeschlossene Positionen erscheinen im `excluded`-Block der
  Allokation.
- `GET /api/v1/securities/:id` liefert ein Wertpapier.
- `PATCH /api/v1/securities/:id` aktualisiert ein Wertpapier mit einem
  `security`-Objekt (einschließlich `excluded_from_allocation_targets`).
- `DELETE /api/v1/securities/:id` löscht ein Wertpapier, wenn keine abhängigen
  Transaktionen oder keine Kurshistorie darauf verweisen; referenzierte
  Wertpapiere liefern `409 Conflict`.
- `GET /api/v1/securities/search` durchsucht konfigurierte
  Online-Wertpapieranbieter. Query-Parameter: `query`; optional `type` mit
  `security` oder `crypto`.

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

## Kurse

- `GET /api/v1/securities/:security_id/quotes` listet die Kurshistorie eines
  Wertpapiers. Optionale Query-Parameter: `from` und `to`, als ISO-Daten
  formatiert. Ungültige Datumsfilter liefern `422 Unprocessable Entity` mit
  Feldfehlern.
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

- `GET /api/v1/portfolios` listet Portfolios.
- `POST /api/v1/portfolios` legt ein Portfolio mit einem `portfolio`-Objekt an.
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
  verändern ihn, sodass Geld zwischen deinen eigenen Konten zu verschieben keine
  Übertragungsbuchung braucht. Unbekannte Konten liefern `404 Not Found`.
- `POST /api/v1/cash_accounts` legt ein Geldkonto mit einem `cash_account`-Objekt
  an. Das optionale Boolean `counts_toward_cash_quote` (Standard `true`) steuert,
  ob das Konto in die `cash_quote` der Bewertung eingeht; setze es auf `false` für
  ein reines Referenzkonto (z. B. ein Geschäftskonto), das sichtbar bleiben soll,
  ohne die private Quote zu verzerren.
- `GET /api/v1/cash_accounts/:id` liefert ein Geldkonto.
- `PATCH /api/v1/cash_accounts/:id` aktualisiert ein Geldkonto (`name`,
  `currency_code`, `notes`, `counts_toward_cash_quote`); `portfolio_id` kann nicht
  geändert werden.
- `DELETE /api/v1/cash_accounts/:id` löscht ein Geldkonto oder liefert
  `409 Conflict`, wenn eine Transaktion oder ein Wertpapierkonto noch darauf
  verweist.
- `GET /api/v1/securities_accounts` listet Depots/Wertpapierkonten.
- `POST /api/v1/securities_accounts` legt ein Depot/Wertpapierkonto mit einem
  `securities_account`-Objekt an.
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
- `POST /api/v1/transactions` legt eine manuelle Kauf- oder Verkauftransaktion mit
  einem `transaction`-Objekt an.
- `GET /api/v1/transactions/:id` liefert eine Transaktion.
- `PATCH /api/v1/transactions/:id` aktualisiert eine Transaktion (z. B. um eine
  falsch importierte Buchung zu korrigieren); die Validierung je Art gilt weiter.
- `DELETE /api/v1/transactions/:id` löscht eine Transaktion. Da Trades und
  Bestände abgeleitet sind, korrigiert oder entfernt das Korrigieren oder Entfernen
  der Transaktion auch sie.
- `GET /api/v1/portfolios/:portfolio_id/holdings` listet abgeleitete Bestände
  eines Portfolios, eine Zeile je (Depot, Wertpapier). Jede Zeile trägt
  `quantity`, einen gleitenden Durchschnitt `avg_cost` und `cost_basis`
  (preisbasiert, sodass Gebühren und Steuern nicht in die Stückkosten einfließen),
  den `latest_price`, `market_value` und `unrealized_pnl_abs`/`unrealized_pnl_pct`
  gegen diesen Preis, plus `security_name` und `currency_code`. Alle monetären
  Größen sind in der eigenen Währung des Wertpapiers (keine FX-Umrechnung — siehe
  die Bewertung für Summen in Basiswährung); ein Bestand, dessen Wertpapier keinen
  Kurs hat, liefert `null` für Preis, Marktwert und G/V. Die Antwort ist
  selbstbeschreibend (FR-13): sie trägt `currency_basis: "security_currency"`
  (sodass ein Client nie annehmen muss, ob FX angewendet wurde) und ein
  `as_of`-Datum. Bestände werden beim Lesen abgeleitet, ohne gespeicherten
  Snapshot, daher ist `as_of` das Lesedatum. Unbekannte Portfolios liefern
  `404 Not Found`. Optionale Filter: `security_id`, `securities_account_id`.
- `GET /api/v1/holdings/by_security` liefert die **globale Bewertung je
  Wertpapier** über **alle** Portfolios hinweg: eine `holdings`-Zeile je aktuell
  gehaltenem Wertpapier mit `security_id` (eine Ganzzahl), Gesamt-`quantity` und
  aktuellem `market_value`, umgerechnet in den **EUR-Hub**, plus ein
  `valued`-Flag. `valued` ist `false` (und `market_value` ist `null`), wenn das
  Wertpapier weder einen Kurs noch einen Handelspreis hat oder kein
  Wechselkurspfad nach EUR existiert, sodass ein fehlender Kurs oder Kurs einen
  Wert nie stillschweigend verfälscht. Die Zeilen sind nach `security_id`
  sortiert. Die Antwort ist selbstbeschreibend: ein `currency` auf oberster
  Ebene mit `"EUR"`, ein `as_of`-Lesedatum (der Bericht wird beim Lesen
  abgeleitet, daher ist `as_of` das heutige Datum, kein gespeicherter
  Zeitpunkt) und ein `note`, das die Hub-Umrechnung beschreibt. Dies ist das
  portfolioübergreifende Gegenstück in Basiswährung zur Bestandsliste eines
  einzelnen Portfolios (die in der eigenen Währung jedes Wertpapiers ohne FX
  bleibt); für Summen und Gewichte eines Portfolios nutze stattdessen den
  Bewertungs-Endpunkt.
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
  `base_value`/`valued` nach Umrechnung in die Basiswährung, und sein
  `counts_toward_cash_quote`-Flag), `total_cash` ist die Basiswährungssumme der
  bewerteten Geldkonten, und `total_with_cash` ist `total_value + total_cash`.
  `cash_quote` ist der Cash-Anteil des Portfolios, berechnet über die Konten, deren
  `counts_toward_cash_quote` `true` ist, als gäbe es die anderen Konten nicht
  (`counting_cash / (total_value + counting_cash)`, `0`, wenn noch nichts zu
  bewerten ist) — sodass ein reines Referenz-Geschäftskonto gelistet und in
  `total_cash` bleibt, ohne die Quote zu verzerren. Die Antwort liefert außerdem
  `counting_cash` (Decimal-String) — das Cash, das in die Quote eingeht — sodass
  ein Konsument die `cash_quote` selbst rekonstruieren kann. Ein Konto, dessen Währung
  keinen Kurspfad zur Basis hat, wird `valued: false` gemeldet und aus
  `total_cash` ausgeschlossen, spiegelnd, wie unbepreisbare Positionen behandelt
  werden. Die Antwort ist selbstbeschreibend (FR-13): sie trägt ein
  `as_of`-Datum (das Lesedatum — die Bewertung wird live ohne gespeicherten
  Snapshot berechnet) und eine `valuation_note`, die angibt, dass Summen in
  `base_currency` über den EUR-Hub vorliegen und dass die je Position geführten
  Felder `price_source` und `valued` die Preis-Aktualität anzeigen.
- `GET /api/v1/portfolios/:portfolio_id/performance` liefert die **echte
  zeitgewichtete Rendite (TTWROR)** des Portfolios, berechnet auf die
  Portfolio-Performance-Art: das Portfolio wird täglich bewertet (Kurse am oder vor
  jedem Tag, zu den Kursen jenes Tages umgerechnet, plus Cash), externe Flüsse —
  Einzahlungen, Entnahmen, Lieferungen und Saldo-Snapshot-Sprünge — werden
  neutralisiert, und tägliche Renditen werden geometrisch verkettet (siehe
  ADR-0010). Optionale Query-Parameter: `period` (`ytd`, `1y`, `3y`, `5y`, `max` —
  Standard `max`; ein unbekannter Zeitraum liefert `422 Unprocessable Entity`) und
  `series=true`, um die täglichen Punkte aufzunehmen (`date`, `value`, `flow`,
  `cumulative_ttwror`). Die Antwort trägt `ttwror`, `start_date`/`end_date`,
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
  Portfolios liefern `404 Not Found`.
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
- `GET /api/v1/portfolios/:portfolio_id/targets` listet die gespeicherten
  Zielgewichte eines Portfolios (die SOLL-Seite der Allokation). Optionales
  `classification_id` schränkt die Liste auf einen Baum ein. Unbekannte Portfolios
  liefern `404 Not Found`.
- `PUT /api/v1/portfolios/:portfolio_id/targets` führt Zielgewichte für eine
  Klassifizierung ein (Upsert). Der Body ist `{"classification_id": id, "targets":
  [{"category_id": id, "target_weight": "0.25"}]}`. Jedes `target_weight` ist ein
  String-Bruch in `[0, 1]`; Ziele müssen sich nicht zu `1` summieren. Nur die
  übergebenen Kategorien werden geändert. Eine Kategorie aus einem anderen Baum
  liefert `422 Unprocessable Entity`, und eine unbekannte Klassifizierung liefert
  `404 Not Found`.
- `DELETE /api/v1/portfolios/:portfolio_id/targets/:category_id` entfernt das
  Zielgewicht eines Portfolios für eine Kategorie und liefert `{deleted}` (die Zahl
  der entfernten Zeilen).
- `GET /api/v1/portfolios/:portfolio_id/allocation` liefert die
  SOLL/IST-Aufschlüsselung für eine Klassifizierung (erforderlicher
  `classification_id`-Query-Parameter; ein fehlender liefert
  `422 Unprocessable Entity`). Für jede Kategorie meldet es `parent_id` und `depth`
  (die Kategorien bilden einen Baum), `color`, `own_market_value` (direkt
  zugeordnete Positionen), `market_value` (ihr ganzer aufgerollter Teilbaum),
  `actual_weight` (der aufgerollte Anteil an `total_value`), `target_weight`,
  `drift_weight` (`target_weight - actual_weight`) und `drift_value` (die Drift in
  Basiswährung neu ausgewiesen). Jede Zeile trägt zudem `child_target_sum`
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
  `market_value`, `weight` — größte zuerst, Wertpapiere über Depots
  zusammengeführt; das ist es, was der äußerste Ring des Sunburst rendert.
  Gehaltene, aber im Baum nicht zugeordnete Wertpapiere werden in `unassigned`
  summiert. Gewichte sind Anteile der **Steuerbasis**: der Gesamtwert der
  bewerteten Positionen abzüglich jedes als `excluded_from_allocation_targets`
  markierten Wertpapiers, **plus das Cash, das zur Cash-Quote zählt** (Konten,
  deren `counts_toward_cash_quote` `true` ist). `total_value` ist hier diese
  Steuerbasis (nicht die volle Bewertung). Die Antwort trägt ein `cash`-Objekt —
  `market_value` (das zählende Cash), `actual_weight` (sein Anteil an
  `total_value`), `target_weight` (das `cash_target_weight` des Portfolios oder
  `0`, wenn nicht gesetzt), `drift_weight` (`target_weight - actual_weight`) und
  `drift_value` (in Basiswährung neu ausgewiesen) — sodass Cash in derselben
  Drift-Logik wie die Kategorien gesteuert wird. Da Cash Teil der 100 %-Basis ist,
  schrumpfen die Kategorie-Prozentsätze entsprechend, sobald Cash vorhanden ist.
  Der `top_level_target_sum` ist die Summe der Ziele der Wurzelkategorien **plus
  das Cash-Ziel**, verglichen mit `1`. Als ausgeschlossen markierte Positionen
  verschwinden nicht: sie erscheinen in einem separaten `excluded`-Objekt
  (`market_value` plus `positions` je Wertpapier oder `null`, wenn nichts
  ausgeschlossen ist), sodass sie sichtbar bleiben, während die Prozentsätze und
  die Drift nur den gesteuerten Teil beschreiben. Die Bewertungs- und
  Performance-Endpunkte sind vom Flag unbeeinflusst. Unbekannte Portfolios oder
  Klassifizierungen liefern `404 Not Found`.
- `GET /api/v1/portfolios/:portfolio_id/risk` liefert eine
  **Risiko-/Konzentrationssicht** für ein Portfolio über die **Steuerbasis** (der
  Gesamtwert der bewerteten Positionen abzüglich jedes als
  `excluded_from_allocation_targets` markierten Wertpapiers — dieselbe Basis wie
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
- `PATCH /api/v1/portfolios/:portfolio_id` patcht die Stammdaten eines Portfolios.
  Der Body ist `{"portfolio": {...}}`. Nutze es, um den SOLL-Cash-Anteil mit
  `cash_target_weight` zu setzen — einem String-Bruch in `[0, 1]` (z. B. `"0.05"`
  für 5 %) oder `null`, um die Steuerung einer Cash-Quote zu beenden. Das Cash-Ziel
  speist die `cash`-Zeile der Allokation und den `top_level_target_sum`. Gewichte
  außerhalb des Bereichs liefern `422 Unprocessable Entity`; unbekannte Portfolios
  liefern `404 Not Found`. Das `cash_target_weight` ist auch in den von
  `GET`/`POST /api/v1/portfolios` zurückgegebenen Portfolio-Objekten enthalten.
- `GET /api/v1/securities/:security_id/trades` liefert FIFO-gematchte Trades eines
  Wertpapiers: offene Lots, geschlossene Round-Trips (mit realisiertem G/V und
  Haltedauer in Tagen) und etwaige verwaiste Verkäufe. Die Antwort ist
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
- `POST /api/v1/exchange_rates/sync` holt die neuesten Kurse vom konfigurierten
  Anbieter (standardmäßig die täglichen EZB-Referenzkurse) und liefert
  `{provider, status, upserted}`. Ein Anbieterfehler liefert `502 Bad Gateway`.

## Klassifizierungen

Klassifizierungsbäume ordnen Wertpapiere wie Ordner. Integrierte Bäume
(`asset_class`, `currency`) werden automatisch abgeleitet und ihre Struktur ist
gesperrt; das Bearbeiten der Struktur eines integrierten Baums liefert
`422 Unprocessable Entity`. Die **Mitgliedschaft** des **Anlageklassen**-Baums
ist jedoch nur eine Sicht auf das `asset_class`-Feld jedes Wertpapiers: in der UI
kannst du ein Wertpapier zwischen seinen Kategorien ziehen (was dieses Feld
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

## MCP-Tools

Der MCP-Begleitdienst stellt denselben lokalen Kontrakt als Tool-Aufrufe bereit.
Decimal-Eingaben in MCP-Schemata sind Strings.

- `portfolixir.securities.list`
- `portfolixir.securities.create`
- `portfolixir.securities.update`
- `portfolixir.securities.delete`
- `portfolixir.securities.search_online`
- `portfolixir.quotes.sync`
- `portfolixir.quotes.list`
- `portfolixir.quotes.upsert`
- `portfolixir.portfolios.list`
- `portfolixir.portfolios.create`
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
- `portfolixir.holdings.list`
- `portfolixir.holdings.by_security`
- `portfolixir.portfolios.valuation`
- `portfolixir.exchange_rates.list`
- `portfolixir.exchange_rates.sync`
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
- `portfolixir.portfolios.set_cash_target`
- `portfolixir.portfolios.income`
- `portfolixir.portfolios.performance`
