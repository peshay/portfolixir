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

**Benannte Tokens** (E25). `PORTFOLIXIR_API_TOKENS` fügt weitere Tokens als
`name=token`-Einträge hinzu, durch Kommas getrennt (`scripts=<token>`; ein Name
hat 1 bis 32 Zeichen aus `a-z`, `0-9`, `_` und `-`, beginnend mit einem Buchstaben
oder einer Ziffer). Ein Schreibzugriff mit
einem davon wird mit diesem Namen als `actor_label` im Journal verbucht
(`GET /api/v1/journal`), und eine damit ausgeführte Zusammenführung hält den
Namen in ihrem Protokoll fest (`GET /api/v1/merges`), genommen aus dem Eintrag,
zu dem das vorgelegte Token passt, nie aus der Anfrage. `PORTFOLIXIR_API_TOKEN` bleibt der Standard und
wird wie bisher ohne Label verbucht, es sei denn, `PORTFOLIXIR_API_PRINCIPAL`
benennt ihn; das Compose-Deployment nennt ihn so `mcp`, die Schreibzugriffe
des Begleitdienstes lauten also `mcp`. Jeder
Eintrag wird beim Start wie das eine Token geprüft, und ein Name oder ein Token
darf nur einmal vorkommen. Ein Name ordnet einen Schreibzugriff zu, er
beschränkt nicht, was das Token darf: Jedes Token hat dieselbe volle Befugnis.
Warum, und die Grenze für gespeicherten Text weiter unten, entscheidet
[ADR-0054](/decisions/0054-the-agents-surface-one-authority-named-principals-escaped-text.html) (englisch).

Der MCP-Begleitdienst nutzt `PORTFOLIXIR_API_TOKEN`, um Portfolixir unter
`PORTFOLIXIR_API_BASE_URL` aufzurufen, und folgt dort keiner Weiterleitung:
Eine `3xx`-Antwort wird als `ApiRedirectError` abgelehnt, der die Anfrage und
die Variable nennt, damit der Body einer Anfrage und das Token nie dorthin
erneut gesendet werden, wohin die Weiterleitung zeigt. Richten Sie
`PORTFOLIXIR_API_BASE_URL` auf die Adresse, unter der die API ohne
Weiterleitung antwortet.
`PORTFOLIXIR_MCP_TOKEN` ist für den HTTP-Transport erforderlich, damit sich
lokale HTTP-Clients beim Begleitdienst authentifizieren können. Es folgt der
Regel des API-Tokens: Der Begleitdienst startet nicht mit einem Token, das
kürzer als 32 Bytes oder ein Platzhalter ist, und nennt dabei die Variable.
Ein `PORTFOLIXIR_MCP_PORT`, das keine ganze Zahl von 1 bis 65535 ist, oder ein
Port, den der Listener nicht bekommt (ein anderer Prozess hält ihn), stoppt
den Begleitdienst mit dem Exit-Status 1 und einer Zeile, die die Variable und
ihren Wert nennt oder die Adresse und die Ursache, etwa `EADDRINUSE`. Ein
leeres `PORTFOLIXIR_MCP_HOST` bindet `127.0.0.1` wie ein nicht gesetztes, nie
jede Schnittstelle (#1137), und ebenso ein leeres Klammerpaar (`[]`), das wie
ein leerer Wert als Loopback-Standard gilt; eine IPv6-Adresse, an die er
bindet, gilt in Klammern (`[::1]:4001`), dem `Host`, den ein Client für die
URL schickt, die der Begleitdienst ausgibt. Wiederholt falsche Tokens von einer verbindenden Adresse sperren sie für ein
wachsendes Intervall, in dem jedes weitere falsche Token von ihr mit `429` und
`Retry-After` beantwortet wird und die Sperre verlängert. Das Token wird
zuerst verglichen: Ein richtiges Token kommt durch, solange seine Adresse
gesperrt ist (#974), sodass hinter dem veröffentlichten Port, wo jeder Client
über die Docker-Bridge verbindet, ein Rater oder ein veralteter Client dort
den Agenten nicht aussperrt. Die Bearer-Prüfung der API selbst verhält sich
genauso, solange jedes konfigurierte Token die Mindestlänge von 32 Bytes
erreicht; ein aus dem Quellcode gestarteter Server, der nur
`PORTFOLIXIR_API_TOKEN` liest, hält es an keine, und mit einem kürzeren Token
prüft sie zuerst die Sperre. Die API zählt IPv6-Adressen außerdem je /64, und
über einer stündlichen Obergrenze für erste Fehlversuche von Adressen, die sie
noch nicht kennt, wird schon das erste falsche Token von einer solchen Adresse
mit `429` und `Retry-After` beantwortet statt mit `401`. Vor allem anderen prüft der
Begleitdienst den `Host`-Header genau, Name und Port: Eine Anfrage unter einem
`Host`, auf den der Listener nicht antwortet (die Loopback-Namen und seine
gebundene Adresse mit seinem Port sowie die Namen in
`PORTFOLIXIR_MCP_ALLOWED_HOSTS`), wird mit `403` beantwortet, bevor ihr
Origin oder ihr Token betrachtet wird, und zählt als kein Fehlversuch. Die
Loopback-Namen sind `127.0.0.1`, `localhost` und `[::1]`, jeweils nur mit dem
Port des Listeners. Ein Name in `PORTFOLIXIR_MCP_ALLOWED_HOSTS` gilt mit
diesem Port und ohne Port, wie ihn ein Proxy auf Port 443 durchreicht; ein
Eintrag mit eigenem Port gilt nur unter diesem Port, etwa `127.0.0.1:14001` für
eine Compose-Zuordnung, die den Begleitdienst auf einem anderen Host-Port als
seinem eigenen veröffentlicht. Die Namen, der des gebundenen Hosts und die in
`PORTFOLIXIR_MCP_ALLOWED_HOSTS`, werden in Kleinbuchstaben verglichen, wie ein
Browser sie schickt, sodass ein Eintrag mit Großbuchstaben die Prüfung des
Begleitdienstes und die des MCP-SDK besteht. Das `Origin` einer Browser-Anfrage wird danach
als Ganzes verglichen, Schema, Name und Port (#956): Es gilt als `http://` auf
einem Loopback-Namen oder der gebundenen Adresse mit dem Port des Listeners
oder als `http://` oder `https://` auf einem `Host`-Wert aus
`PORTFOLIXIR_MCP_ALLOWED_HOSTS`. Jedes andere Origin, eine Seite auf einem
anderen Port derselben Maschine eingeschlossen, wird mit `403` beantwortet
(`origin not allowed`), bevor sein Token betrachtet wird. Um einen MCP-Client
im Browser zuzulassen, der von einem anderen Origin ausgeliefert wird, nenne
Host und Port dieses Origins in `PORTFOLIXIR_MCP_ALLOWED_HOSTS`:
`localhost:6274` lässt einen Client zu, der unter `http://localhost:6274`
ausgeliefert wird. Ein Client, der kein Browser ist, sendet kein `Origin` und
besteht diese Prüfung. Das Token wird geprüft, bevor der Body der Anfrage
gelesen wird. Die Fehler, die der Begleitdienst selbst
beantwortet, ein unbekannter Pfad eingeschlossen, haben die Form der API,
`{"errors": {"detail": "Bad Request"}}`, ohne Stacktrace und ohne lokalen
Pfad; die Ablehnungen des MCP-Protokolls selbst auf `/mcp` behalten dessen
JSON-RPC-Fehlerform.

## Datenregeln

Alle Antworten nutzen JSON-Umschläge mit entweder `data` oder `errors`.
Finanz-Decimals werden als Strings serialisiert, einschließlich Mengen, Preise,
Gebühren, Steuern, Kurs-Schlusswerte und monetärer Summen. Request-Payloads
senden diese Werte ebenfalls als Strings.

**Decimal-Strings beim Schreiben.** Jeder Schreibzugriff unter `/api/v1`
(`POST`, `PUT`, `PATCH`, `DELETE`) lehnt eine JSON-Zahl — eine
Gleitkommazahl ebenso wie eine ganze Zahl — in einem Geld-, Mengen-, Preis-,
Gebühren-, Steuer- oder Wechselkursfeld mit `422` ab, das das Feld nennt,
`{"errors": {"price": ["must be a decimal string"]}}`, und speichert nichts
(ADR-0003, Ergänzung vom 2026-11-01). Eine JSON-Zahl wird als binäre
Gleitkommazahl dekodiert, sodass ein Wert mit mehr als etwa 17 signifikanten
Stellen als eine andere Zahl gespeichert würde als die gesendete:
`"1234567890.12345678"` als String gesendet wird exakt gespeichert, derselbe
Wert als Zahl wird abgelehnt, statt auf `1234567890.1234567` gerundet zu
werden. Die Regel liest den Body in beliebiger Tiefe — in einem
Hüllobjekt wie `transaction`, in jeder Zeile einer Liste wie `quotes` eines
Kurs-Batches und in jedem Eintrag einer Liste von Sätzen wie
`church_tax_rates` — und nennt jedes betroffene Feld einmal. Die Felder:
`amount`, `gross_amount`, `security_amount`, `settlement_amount`,
`face_value`, `amount_granted`, die Freibeträge eines Steuerjahrs, die
Geldfelder und einbehaltenen Steuern eines Bescheinigungs-Snapshots,
`quantity`, `price`, `close`, `fees`, `taxes`, die Steuersätze
(`capital_gains_tax_rate`, `solidarity_surcharge_rate`, `church_tax_rate`,
`church_tax_rates`), `settlement_fx_rate` und `coupon_rate` sowie jedes Feld
mit der Endung `_amount`, `_price`, `_rate`, `_rates` oder `_withheld`. Ein
Decimal-String wird wie bisher angenommen, und ein JSON-`null` behält seine
bisherige Antwort; IDs, Jahre, Glieder eines Split-Verhältnisses,
Zielgewichte und Schwellen von Regeln fallen nicht unter diese Regel, und
Lesezugriffe bleiben unverändert. Die Tools des MCP-Begleiters senden diese
Felder bereits als Strings.

Die Fehler, die der Server selbst statt eines Endpunkts beantwortet, nutzen
denselben Umschlag mit ihrem eigenen Status: ein unlesbarer Body, oder einer, der
Arrays und Objekte mehr als 100 Ebenen tief verschachtelt, ist `400`, ein Body
über der Größengrenze des Servers von 2.000.000 Bytes `413`, eine unbekannte Route `404`, ein
interner Fehler `500`, jeweils als `{"errors": {"detail": "Bad Request"}}` mit
der englischen Statusbezeichnung.

`DELETE /api/v1/securities/:id` ist die Erfolgs-Ausnahme: es liefert
`204 No Content` mit leerem Body. Clients sollten für diese erfolgreiche
Löschantwort keinen JSON-Body parsen.

**IDs.** Jede ID ist eine positive Ganzzahl, die in ein PostgreSQL-`bigint`
passt (höchstens `9223372036854775807`). Eine Pfad-ID, die fehlerhaft,
unbekannt oder jenseits dieser Grenze ist, liefert `404`; eine ID jenseits der
Grenze in einem Query-String oder einem JSON-Body (in beliebiger Tiefe, als Zahl
oder als String) liefert `422` mit dem Namen des Schlüssels — derselbe
Feldfehler, den eine fehlerhafte ID erhält. Keine ID wird je mit `500`
beantwortet. Die freie `attributes`-Map eines Wertpapiers sowie die Textfelder
`online_id` und `resource_id` sind keine IDs und werden nicht geprüft.

Die Seiten halten dasselbe Versprechen: Ein ID-förmiger Query-Parameter
jenseits der Grenze (`id`, `*_id`, `*_ids`, `view`) wird durch eine
Weiterleitung auf dieselbe Seite ohne ihn verworfen, und eine Pfad-ID jenseits
der Grenze (`/securities/:id`, `/classifications/:id`) leitet auf die Übersicht
um, gleich was der Query-String enthält — nie ein Serverfehler. Jeder andere
ID- oder Ganzzahl-Parameter einer Seite wird nach derselben ID-Regel gelesen
und gilt als nicht angegeben, wenn er den Wert nicht fassen kann:
`/snapshots?snapshot=` öffnet den neuesten Snapshot und
`/tax?year=` (ein Jahr außerhalb von `1`–`9999`) das voreingestellte Jahr. Ein
Ereignis, das eine Seite oder einen ihrer Dialoge mit einer Nutzlast erreicht,
die kein Objekt ist, mit einer ID jenseits der Grenze in beliebiger Tiefe
(dieselbe Regel, die die API mit `422` beantwortet), mit einem Feld in falscher
Form oder mit einem unbekannten Namen, ändert nichts: Die Seite bleibt, wie sie
war.

**Begrenzte Ganzzahlen.** `offset` auf der Wertpapierliste nimmt höchstens
`1000000` an, `days` auf den Research-Log-Abfragen `unreviewed` und `expiring`
höchstens `3650` (zehn Jahre); ein Wert über der Grenze oder einer, der keine
nicht-negative Ganzzahl ist, liefert `422` mit dem Namen des Parameters.
`limit` behält seinen Vertrag (gekappt und zurückgemeldet), ebenso `days` bei
den Wertpapier-Terminen. Ein Jahr außerhalb von `1`–`9999` gilt als
fehlerhaftes Jahr.

**Ein begrenzter Listen-Read sagt, wenn er gekürzt wurde (#1254).** Jeder
Listen-Read, der seine Zeilen mit `limit` begrenzt — die fünf Delta-Reads
unten, das Journal, die Merge-Einträge, die Wechselkurse, die Kurse eines
Wertpapiers und seine Strecken manueller Kurse, die Snapshots, die drei
Cashflow-Auswertungen (deren `limit` die Jahre der Jahresmatrix zählt) und die
Warteschlangen der Notizen und Ereignisse (unreviewed, uncorroborated,
expiring, upcoming, unconfirmed, stale) — spiegelt das angewandte `limit`, den
Standard, wenn keines gesendet wurde, und `truncated`: `true`, wenn mehr
Zeilen passten, als die Antwort enthält, sodass eine volle Antwort nie für die
ganze gehalten wird. Beide stehen neben `data`, wenn `data` die Liste ist, in
`data`, wenn es ein Objekt ist; ein älteres Echo (`meta.limit`,
`meta.filters.limit`) bleibt. Den Rest liest, wer `limit` bis zum Maximum des
Reads erhöht oder die Filter enger fasst; nur die Delta-Reads blättern mit
einem Cursor.

**Datumsangaben.** Jedes Datum, das ein Schreibzugriff speichert — das
`date` einer Buchung, `valid_from` einer Regelversion und `valid_until` einer
Stilllegung, `as_of` eines Snapshots, die Daten eines Research-Log-Eintrags,
eines Termins, eines Steuerprofils, eines ISIN-Wechsels, eines Kurses und eines
Splits — ist ein ISO-8601-Kalenderdatum (`YYYY-MM-DD`) von `1900-01-01` bis
`2999-12-31`. Ein Datum außerhalb dieses Bereichs oder in anderer Form (ein
Objekt aus Teilen, ein Datum mit Uhrzeit) liefert `422` mit dem Namen des Felds
und speichert nichts; das gespeicherte, gemeldete und im Journal festgehaltene
Datum ist also das gesendete. Ein Portfolio-Performance-Import nennt eine Zeile
mit einem Datum außerhalb des Bereichs in der Vorschau, statt sie zu buchen.
Ein Datumsfilter eines Lesezugriffs — `from` und `to` bei den Buchungen, Kursen
und Trades, `as_of` bei den Kennzahlen eines Wertpapiers und den Regeln — folgt
derselben Regel: Alles andere liefert `422` mit dem Namen des Parameters.

**Buchungsbeträge.** Die Geldfelder und Preise einer Buchung (`gross_amount`,
`price`, `fees`, `taxes`, `security_amount`, `settlement_amount`,
`settlement_fx_rate`) halten 6 Nachkommastellen, ihre `quantity` 12
(ADR-0016). Ein feinerer Wert wird **vor** der Prüfung kaufmännisch auf diese
Stellenzahl gerundet; gespeichert, gemeldet und im Journal festgehalten wird
also der gerundete Wert, und ein positiver Betrag, der auf `0` rundet, liefert
`422`. Ein Wert mit mehr als 14 Stellen vor dem Komma (eine Menge mit mehr als
18) liefert `422` mit dem Namen des Felds, statt in der Datenbank zu scheitern.

**Andere gespeicherte Beträge.** Dieselbe Regel gilt für jeden anderen Betrag,
den ein Schreibzugriff speichert: den `close` eines Kurses (6
Nachkommastellen), einen Wechselkurs (15) sowie die Geldfelder (6) und Sätze
(4) der Steuer-Schreibzugriffe — die Töpfe und einbehaltenen Steuern einer
Steuerbescheinigung, `amount_granted` eines Freistellungsauftrags, die
Freibeträge und Sätze eines Steuerjahrs, `church_tax_rate` eines Profils —
sowie `coupon_rate` und `face_value` einer Anleihe (6). Ein
feinerer Wert wird vor der Prüfung kaufmännisch auf seine Stellenzahl
gerundet; ein positiver `close`, der auf `0` rundet, liefert also `422` und
wird nie als Null gespeichert. Ein Geldwert mit mehr als 14 Stellen vor dem
Komma liefert `422` mit dem Namen des Felds.

**Text.** Ein Name, eine Kennung oder jeder andere einzeilige Text, den ein
Schreibzugriff speichert, ist höchstens so lang wie seine Spalte — 255 Zeichen,
sofern keine andere Grenze genannt ist (der Name eines Buckets oder einer
Ansicht 100, der eines Plans oder Snapshots 120, die `source_url` eines
Research-Eintrags oder eines Termins 2.048), gezählt in
Unicode-Codepunkten, der Einheit der Datenbank — und enthält weder Steuerzeichen
noch Zeilenumbrüche. Freitext (die `notes` einer Buchung, ein
Research-Log-Eintrag, die `note` eines Termins oder einer Regelversion, eine
Beschreibung) behält Tabulatoren und Zeilenumbrüche, aber kein anderes
Steuerzeichen, auch kein NUL, und ist höchstens 10000 Zeichen lang (der
`body` eines Research-Log-Eintrags 20000, die `description` einer Kategorie
2000), gezählt in Codepunkten; auch die Datenbank lehnt einen längeren Wert
ab. Kein Text, einzeilig oder frei, trägt ein **unsichtbares Zeichen** (E25):
irgendeinen der standardmäßig ignorierbaren Codepunkte von Unicode — ein
Tag-Zeichen und den Rest seines Blocks (U+E0000–U+E00FF, U+E01F0–U+E0FFF),
ein Steuerzeichen der Schreibrichtung (U+061C, U+200E, U+200F,
U+202A–U+202E, U+2066–U+2069), ein anderes unsichtbares Formatzeichen (das
weiche Trennzeichen U+00AD, das Leerzeichen und die Verbinder der Breite
null U+200B–U+200D, U+2060–U+2065, U+206A–U+206F, die Byte-Order-Mark
U+FEFF, U+FFF9–U+FFFB, U+1BCA0–U+1BCA3, U+1D173–U+1D17A), den kombinierenden
Graphemverbinder U+034F, einen Hangul-Füller (U+115F, U+1160, U+3164,
U+FFA0), U+17B4–U+17B5, U+180B–U+180F oder U+FFF0–U+FFF8 — oder einen
Variantenselektor ohne eine Basis, die er variieren kann. Ein Selektor aus
U+FE00–U+FE0F ist erlaubt nach einem Piktogramm (die Darstellung eines
Emojis), der Ziffer, `#` oder `*` einer Tastenkappe, einem CJK-Ideogramm,
einem mathematischen Operator, einem CJK-Satzzeichen voller Breite (U+3001,
U+3002, U+FF01, U+FF0C, U+FF0E, U+FF1A, U+FF1B, U+FF1F), einem
typografischen Anführungszeichen (U+2018, U+2019, U+201C, U+201D) oder einem
Buchstaben von Myanmar, Phags-pa, Manichäisch oder den ägyptischen
Hieroglyphen; einer aus U+E0100–U+E01EF
nur nach einem CJK-Ideogramm; ein Selektor neben einem anderen nie. Ein Verbinder der Breite null U+200D ist erlaubt, wo er zwei
Piktogramme verbindet, wie in einem Emoji aus mehreren (eine Person am
Laptop, eine Familie, die Regenbogenflagge): Das Zeichen vor ihm ist ein
Piktogramm oder ein VS16 direkt nach einem, und das Zeichen nach ihm ist
eines. Die drei Flaggen der Landesteile (England, Schottland, Wales) bestehen
aus Tag-Zeichen und bleiben abgelehnt, ebenso der Nicht-Verbinder der Breite
null U+200C, den Wörter mancher Schriften (Persisch, mehrere indische
Schriften) tragen. Sie werden als nichts angezeigt, erreichen einen Agenten
aber unverändert; der Fehler nennt sie darum mit Codepunkt: `must not contain
invisible characters (U+200B); retype the text without them`. Die eine
Ausnahme ist der Name eines Wertpapiers: Seine standardmäßig ignorierbaren
Zeichen, Variantenselektoren eingeschlossen, werden beim Speichern entfernt,
wie bisher seine Formatzeichen. Alles andere liefert `422` mit dem Namen des Felds, nie einen
Serverfehler. Ein Portfolio-Performance-Import nennt eine Zeile, deren Namen
oder Notiz gegen dieselbe Regel verstoßen, in der Vorschau. Die freie
Zuordnung `attributes` eines Wertpapiers erfüllt die Regel in jeder Tiefe:
Jeder Schlüssel ist einzeiliger Text mit höchstens 255 Zeichen, und jeder
Textwert, auch in einem verschachtelten Objekt oder einer Liste, ist
Freitext; sonst liefert der Schreibzugriff `422` auf `attributes`. Die
Zuordnung, wie sie gespeichert wird — zusammengeführt mit den vorhandenen
Attributen —, ist als kompaktes JSON höchstens 65536 Byte groß; ein
Schreibzugriff darüber liefert `422` auf `attributes` und speichert nichts.
`market_cap_rank`, das Attribut, das die Wertpapierliste als Zahl sortiert,
ist eine ganze Zahl oder ihr Text und wird als Zahl gespeichert; alles andere
liefert `422` auf `attributes` („market_cap_rank must be a whole number“),
und ein Wert eines Suchanbieters, der keine ganze Zahl ist, wird verworfen.
Eine Änderung, die nichts ändert, schreibt keine Zeile und hinterlässt keinen
Journaleintrag. Eine
Eigenschaft eines Suchanbieters, die gegen die Regel verstößt, wird verworfen,
bevor sie die Attribute erreicht. Ein Textfilter eines Lesezugriffs — `query`
bei den Wertpapieren, `resource_type` und `resource_id` im Journal, `holder`,
`institution` und `jurisdiction` bei den Steuer-Lesezugriffen — ist
einzeiliger Text mit höchstens 255 Zeichen; alles andere, auch eine Liste,
liefert `422` mit dem Namen des Parameters.

**Eingepackte Rümpfe.** Ein Schreibzugriff, dessen Attribute unter einem
Schlüssel reisen — `{"transaction": {…}}`, `{"view": {…}}`, `{"rule": {…}}`
und ihre Geschwister — liefert `422` mit dem Namen dieses Schlüssels, wenn
sein Wert kein JSON-Objekt ist (ein String, eine Zahl, eine Liste).

**Delta-Reads (FR-38).** Die beiden wiederkehrenden Sync-Reads — `GET
/api/v1/transactions` und `GET /api/v1/securities` — akzeptieren
`?since=<ISO8601>` (Datetime mit Offset, naive UTC-Datetime oder ein reines
Datum als Tagesbeginn, UTC) und liefern dann nur die Zeilen, die strikt nach
diesem Zeitpunkt angelegt oder geändert wurden (nach `updated_at`). Die
Antwort spiegelt `since`, trägt `as_of` — als nächstes `since` verwenden —
und eine `delta_note` mit der Semantik. `as_of` liegt eine Sekunde vor dem
Lesezeitpunkt oder vor dem Beginn der ältesten Transaktion, die geschrieben
hat und noch offen ist, je nachdem, was früher liegt: Eine Zeile wird
gestempelt, wenn ihre Transaktion sie schreibt, nicht wenn diese committet,
sodass ein Cursor zum Lesezeitpunkt eine Zeile überspränge, die ein langer
Schreibvorgang (ein Import) nach dem Read committet. Der nächste Read kann
eine Zeile daher erneut liefern, überspringt aber keine.

**Ein begrenzter Delta-Read ist eine Seite (K17).** Die Delta-Reads mit
`limit` — Buchungen, Wertpapiere, die Notizen und Ereignisse eines
Wertpapiers, die Policy-Regeln eines Portfolios, das Audit-Journal — liefern ihre Zeilen nach
ältester Änderung zuerst, und jeder ihrer Reads, Delta oder voll, spiegelt
`limit` und `truncated` (wahr, wenn mehr Zeilen passten, als die Antwort
enthält). Passten mehr Zeilen, als die Seite enthält, trägt ein Delta-Read
zusätzlich `has_more: true`, und sein `as_of` ist dann ein Cursor auf die
letzte Zeile der Seite,
`<ISO8601-Zeitpunkt>~<id>`: als nächstes `since` übergeben und sofort weiter
lesen. Zeilen mit demselben Stempel (ein Import schreibt Tausende in einer
Sekunde) unterscheidet die id, sodass eine Seitengrenze zwischen ihnen keine
überspringt und keine wiederholt. Ein Cursor liegt nie hinter der obigen
Grenze: Ist die letzte Zeile der Seite neuer, ist `as_of` die Grenze, ohne
`~<id>`, und `has_more` bleibt wahr — der Rest wartet hinter einem noch
laufenden Schreibvorgang, also später erneut abfragen, nicht sofort: Bis
dieser endet, liefert ein sofortiger Read dieselbe Seite. Eine Seite, hinter
der nichts mehr wartet, trägt `has_more: false` und die Grenze, wie bisher —
auch wenn sie genau `limit` Zeilen enthält. Ein Cursor gehört zu dem Read,
der ihn geliefert hat: Er trägt dessen Zeilen-id, sodass ein anderer Read mit
ihm seine eigenen Zeilen in der Sekunde des Cursors überspränge. Mit `since`
nach `as_of` blättern, nie mit `offset`: Auf jedem der fünf Reads wird
`offset` neben einem Cursor (einem `since`, das auf `~<id>` endet) mit `422`
`errors.offset` `["is not used with a cursor; page by as_of"]` abgelehnt,
weil der Offset Zeilen nach dem Cursor überspränge (Issue #1295); ein
`since` als reiner Zeitpunkt behält das `offset` der Wertpapierliste. Ein fehlerhafter Cursor ist dasselbe `422` wie
jedes ungültige `since`.

**Löschungen sind
in einem Delta-Read nicht repräsentiert**; wer Löschungen erkennen muss,
macht einen vollen Read. Ein ungültiges `since` ist ein `422`. Delta-Reads
sind **pull-only**: Push-Zustellung (Webhooks an einen konfigurierten
Endpunkt) ist eine separate, weiterhin gegatete Entscheidung (B3.7) und
bewusst nicht Teil dieser Oberfläche.

**Welche Reads `since` tragen (Issue #830, Sprint 14 D-5).** `since` ist ein
*Zeilen-Delta*-Parameter und passt deshalb nur auf Reads, die eine Sammlung von
Zeilen mit Änderungsstempel liefern. Die Familie zerfällt in drei Teile:

- **Tragen ihn — die Zeilensammlungen, die ein geplanter Lauf pollt:**
  `GET /api/v1/transactions`, `GET /api/v1/securities`,
  `GET /api/v1/securities/:security_id/notes` (nach `inserted_at`: das
  Research-Log ist append-only, ein Eintrag ändert sich nach dem Schreiben nie;
  der abgeleitete `thesis_state` deckt weiterhin das ganze Log ab),
  `GET /api/v1/securities/:security_id/events` (nach `updated_at`, ein
  verschobener Termin kommt also als seine geänderte Zeile zurück) sowie
  `GET /api/v1/portfolios/:portfolio_id/targets` und `/position_targets`
  (eine Zielzeile gilt als geändert, wenn **sie oder ihr Plan** nach dem
  Schnitt geändert wurde — das Aktivieren einer anderen Planversion tauscht die
  steuernden Zeilen, ohne eine davon zu bearbeiten; der Roll-up
  `effective_targets` des Positions-Reads deckt immer den ganzen Plan ab, und
  `min_drift` greift nach dem Schnitt) und `GET /api/v1/journal` (nach
  `inserted_at`, auf die Mikrosekunde: das Journal ist append-only; siehe
  [Audit-Journal](#audit-journal)). Ihre MCP-Zwillinge nehmen denselben
  `since`-String: `portfolixir.transactions.list`,
  `portfolixir.securities.list`, `portfolixir.notes.list`,
  `portfolixir.events.list`, `portfolixir.targets.list`,
  `portfolixir.targets.list_positions` und `portfolixir.journal.list`. Die Konfigurationssammlungen
  (Portfolios, Konten und Depots, Buckets, Sichten, Klassifikationen, Pläne,
  Steuerparameter, -profile und Freistellungsaufträge, Snapshots) tragen ihn
  nicht: Sie sind klein und vom Betreiber gepflegt, und mehrere tragen pro
  Zeile Werte, die aus anderen Tabellen abgeleitet sind (ein Kontosaldo, die
  Veraltung einer Steuerbescheinigung) und sich ändern, ohne dass sich das
  `updated_at` der Zeile ändert.
- **Abgeleitete Projektionen tragen ihn nicht — sie brauchen einen anderen
  Mechanismus:** Bewertung, Allokation, Performance, Benchmark, Erträge und
  Risiko haben keine Zeilen und damit kein `updated_at`. „Hat sich die
  Bewertung seit meinem letzten Read geändert" ist eine Frage nach der Version
  ihrer **Basis**, die die Instanz intern bereits führt (ADR-0039), aber nicht
  exponiert; sie zu beantworten ist ein Conditional-Read-Mechanismus (ein ETag
  oder ein Basis-Token), der nicht gebaut ist.
- **Zeitabgeleitete Queues dürfen ihn nicht tragen:** `/notes/unreviewed`,
  `/notes/expiring`, `/notes/uncorroborated`, `/events/upcoming`,
  `/events/stale` und `/events/unconfirmed`. Ihre Mitgliedschaft ändert sich,
  **weil Zeit vergeht**, ohne dass sich eine Zeile ändert — eine Position wird
  über Nacht ungeprüft, ein Termin rückt in den Horizont. Ein Schnitt auf
  `updated_at` würde genau die Zeilen stillschweigend verwerfen, die ein
  Poller braucht; diese Reads ignorieren `since` deshalb wie jeden Parameter,
  den sie nicht definieren (volle Antwort, kein Delta-Umschlag), und ihre
  MCP-Tools akzeptieren ihn nicht.

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
  `logo_status` (`missing` oder `present` — die bloße Logo-Bedingung;
  `missing` schließt Zeilen aus, die ausdrücklich auf „kein Logo“ gesetzt
  sind, und schließt ein gespeichertes Logo ein, dessen Datei fehlt, wie auch
  immer es gesperrt ist, Issue #933; `present` ist ein gespeichertes Logo,
  dessen Datei nicht fehlt), `data_quality` (`stale_quote` — kein Kurs neuer
  als 7 Tage, **einschließlich** nie bepreister Wertpapiere; `missing_quote` —
  gar kein Kurs, die engere Menge darin; `missing_logo` — kein hinterlegtes
  Logo und nicht auf „kein Logo“ gesetzt, oder ein gespeichertes Logo, dessen
  Datei fehlt, die Menge, die die Übersicht „Wertpapiere ohne Logo“ zeigt;
  `missing_fx` — Issue #717: bepreist, aber ohne
  gespeicherten Kurs von seiner Währung zum EUR-Hub, das Speichern des Kurses
  leert also die Menge. Eine Benchmark und ein stillgelegtes Wertpapier sind
  in keiner der ersten drei Mengen, die sie schon in der Abfrage auslassen,
  vor `limit`/`offset`: Das Stilllegen eines ausverkauften oder delisteten
  Wertpapiers nimmt es aus allen drei heraus, Reaktivieren bringt es in die
  zurück, auf die es passt. `missing_fx` behält beide; `two_scales` — Issue
  #1068: jede Anleihe, die der Zwei-Skalen-Wächter nennt, in beiden
  Richtungen und über den ganzen Katalog, die Menge, die die
  Datenqualitätszeile der Übersicht zählt; Regel und welche Wertpapiere als
  Anleihe gelten, siehe `bond.two_scales` unten. Auch sie behält eine
  Benchmark und ein stillgelegtes Wertpapier, denn deren Zahlen sind so
  falsch wie zuvor; `implausible_quote` — Issue #1101: jedes **gehaltene**
  Wertpapier, bei dem ein Kauf, ein Verkauf oder eine bepreiste Einlieferung
  einen gespeicherten Kurs hat, am Tag der Buchung oder der letzte innerhalb
  von 7 Tagen davor, der unter der Hälfte oder über dem Doppelten des
  Preises je Stück der Buchung in der Währung des Wertpapiers liegt (eine
  Buchung in anderer Währung mit `security_amount` ÷ `quantity`), gelesen
  auf der Split-Basis der Buchung (ADR-0028 §2), sodass ein erfasster Split
  nicht genannt wird und ein nicht erfasster schon; eine Buchung zum Preis 0
  oder ohne Kurs im Fenster wird nicht verglichen, und ein Wertpapier, das
  `two_scales` nennt, wird nicht noch einmal gezählt. Es ist die Menge, die
  die Datenqualitätszeile der Übersicht zählt, und behält eine gehaltene
  Benchmark oder ein gehaltenes stillgelegtes Wertpapier. Darunter ergänzt
  der Umschlag `findings`, je gelistetem Wertpapier eines — `security_id`,
  `kind` (`buy`, `sell` oder `inbound_delivery`), `date`, `price`,
  `currency_code`, `quote_date`, `close` (auf der Split-Basis der Buchung),
  `ratio` (Kurs ÷ Preis, kaufmännisch auf 6 Stellen gerundet) und
  `bookings_outside`, wobei die letzte Buchung außerhalb des Bandes die
  genannte ist — und `computation_basis`, das `input_series`, `reference`,
  `window`, `gaps`, `threshold` und `assumptions` nennt; `currency_mismatch`
  — Issue #1415: jedes Wertpapier, dessen gespeicherte `provider_currency`,
  die Währung, die sein Kursanbieter bei der Synchronisierung nannte, die
  sie gespeichert hat, vorhanden ist und von seinem `currency_code`
  abweicht, verglichen wie geschrieben (`GBp`, Pence, weicht von `GBP` ab).
  Die Kurssynchronisierung speichert sie bei jeder Synchronisierung, die
  eine liest, auch bei einer abgelehnten Antwort (Issue #1411), und nur,
  wenn sie sich ändert; `provider_currency_at` ist also die Zeit des Lesens,
  das sie gespeichert hat. Ein Wertpapier, für das noch keine
  Synchronisierung eine Währung gelesen hat, ist noch unbekannt und nie in
  der Menge. Wie die ersten drei lässt sie eine Benchmark aus, und ein
  stillgelegtes Wertpapier, solange es nicht gehalten ist: Der Wert eines
  gehaltenen ist so falsch wie zuvor, wie `implausible_quote` es behält. Die
  Datenqualitätszeile der Übersicht zählt sie. Darunter ergänzt der Umschlag `findings`, je gelistetem
  Wertpapier eines — `security_id`, `currency_code`, `provider_currency` und
  `provider_currency_at` (ISO 8601, UTC) — und `computation_basis` mit
  denselben sechs Schlüsseln. Nichts wird umgerechnet: Die Abhilfe (der
  Ticker, eine Synchronisierung, die gespeicherten Kurse) liegt bei Ihnen),
  `projection`
  (`slim`/`full`) und `limit`/`offset` zur
  Paginierung (`limit` eine positive Ganzzahl, Standard 5000, max. 20000, seit
  #771; `offset` nichtnegativ). Nutze diese, um große
  Kataloge zu paginieren, statt die ganze Tabelle auf einmal zu holen. Eine
  `data_quality`-Menge wird gefiltert, bevor `limit`/`offset` sie
  paginieren, sodass nur ihre letzte Seite kurz ist (Issue #1113). Ein `sort`
  auf eine Kurskennzahl (`latest_price`, `latest_price_date`, `day_change_abs`,
  `day_change_pct`, `performance_1m`, `performance_1y`) sortiert die ganze
  Menge, mit oder ohne `data_quality`-Menge, ein Wertpapier ohne die Kennzahl
  in beiden Richtungen zuletzt und Gleichstände nach Namen, und
  `limit`/`offset` paginieren danach (Issue #1186). Jede Sortierung
  entscheidet ihre letzten Gleichstände nach `id`, in beiden Richtungen
  aufsteigend, sodass ein Gang mit `limit`/`offset` über Zeilen mit gleichem
  Sortierwert (etwa alle Wertpapiere ohne Wert für ein Attribut) keine
  überspringt und keine wiederholt (Issue #1294). Die
  **menschliche Sicht** dieser Verengungen ist die One-Tap-Chipzeile auf der
  Wertpapierseite (Issue #717): ihre Chips fahren auf demselben URL-Zustand
  (`holding=`, `dq=`, `filter[]=asset_class:is_nil`, plus `cur[]=` und
  `class[]=` für die Währungs- und Effektivklassen-Familien), sodass ein
  vorgefilterter Link und ein API-Read dieselbe Menge beschreiben.
  `is_benchmark=true` beschränkt die Abfrage auf die als Benchmark markierten
  Wertpapiere (ADR-0046: die Referenzreihen des Benchmark-Vergleichs),
  `is_benchmark=false` lässt sie weg; das Kennzeichen ist ein Feld der vollen
  Projektion und von `fields=`, und `POST`/`PATCH` nehmen es an.
  `is_retired=true` beschränkt die Abfrage auf die stillgelegten Wertpapiere
  (Issue #1103): Ein Wertpapier, das aus den Hygiene-Mengen stillgelegt
  wurde, ist so wieder zu finden und mit `PATCH`
  `{"security": {"is_retired": false}}` zu reaktivieren; `is_retired=false`
  lässt sie weg. Beide Kennzeichen nehmen `true` oder `false` (leer zählt als
  nicht gesetzt, alles andere ist ein `422`, das das Kennzeichen nennt) und
  verengen zusammen mit den anderen Parametern: Neben einer
  `data_quality`-Menge, die solche Wertpapiere auslässt, trifft
  `is_retired=true` oder `is_benchmark=true` nichts.
  **Gehalten** (`holding_status=held` und jeder andere Gehalten-Filter: die
  unreviewten Positionen des Research-Logs und `held_only` der Ereignisse)
  bedeutet eines: eine von null verschiedene Nettomenge über alle Depots,
  bewegt durch `buy`, `sell`, `inbound_delivery` und `outbound_delivery` — ein
  eingeliefertes Depot ist ab seiner Ankunft gehalten; ein `security_transfer`
  zwischen eigenen Depots gleicht sich zu null aus.

  Ein gespeichertes Logo, dessen Datei fehlt (Issue #933), meldet die
  Logo-Abfrage `GET /api/v1/securities/:security_id/logo` mit
  `file_missing: true` und `has_logo: false`, während `path`, `source` und
  `locked` wie gespeichert bleiben: Die Prüfung beim Start der Instanz fand im
  Logo-Verzeichnis keine Datei zum gespeicherten Pfad. Ein gefundenes Logo
  wird erneut gesucht, ein manuelles bleibt gesperrt und wartet darauf, erneut
  gesetzt zu werden. Speichern oder Entfernen eines Logos hebt die Markierung
  auf, ebenso der nächste Start, sobald die Datei zurück ist.
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
  `changed_on`, `note`). Ein Wertpapier, das eine Zusammenführung entfernt
  hat, antwortet `404` mit `errors.merged_into`
  `{"kind": "security", "id": …}`, dem Wertpapier, auf dem seine Historie
  jetzt liegt — über jede spätere Zusammenführung bis zum lebenden verfolgt
  —, und einem Detail, das beide nennt (ADR-0050 §12); eine ID, die keine
  Zusammenführung nennt, antwortet mit dem einfachen `404`, ebenso eine,
  deren Kette an einer seither gelöschten Zeile endet (ein Überlebender darf
  gelöscht werden, sobald er nichts mehr hält) — ohne `merged_into`, mit
  einem Detail, das diese Zeile nennt. Jede Route unter
  `/api/v1/securities/:security_id/` antwortet einer zusammengeführten ID
  ebenso — die Lesezugriffe auf Kurse, Trades, Kennzahlen, Notizen, Termine
  und Logo, ihre Schreibzugriffe, der ISIN-Wechsel und das Löschen eines
  Kennzeichen-Alias.
- `PATCH /api/v1/securities/:id` aktualisiert ein Wertpapier mit einem
  `security`-Objekt. Das Boolean `treat_quotes_as_raw` (Standard `false`) ist
  die ADR-0028-Notluke für Anbieter, die ihre Historie nach einem
  Aktiensplit nie rückwirkend anpassen: Mit gesetztem Flag werden die
  synchronisierten Kurszeilen des Wertpapiers als roh (wie gehandelt)
  behandelt, sodass die Split-Anpassungsfaktoren auch auf sie wirken. Das
  Boolean `is_retired` legt ein ausverkauftes oder delistetes Wertpapier
  still, `false` hebt das auf: Ein stillgelegtes Wertpapier verlässt die
  Mengen `stale_quote`, `missing_quote` und `missing_logo`, und sein
  veralteter Kurs zählt in der Performance nicht mehr als Preismessung, was
  seine TTWROR-Historie neu feststellen kann (#610). Wie jede Änderung eines
  Wertpapiers wird sie unter dem aufrufenden Token journalisiert. Der
  `currency_code` eines Wertpapiers **friert ein**, sobald es eine
  Transaktion oder einen Kurs hat (ADR-0050 §11): Eine Änderung liefert dann
  `422` mit `errors.currency_code`, das beides zählt, etwa
  `["is frozen once referenced (120 quotes, 3 transactions)"]`, und nichts
  wird geschrieben. Die gespeicherte Währung erneut zu senden ist keine
  Änderung, und die übrigen Felder bleiben änderbar.
  Sie nimmt auch die News-Identität (ADR-0056 §2): `news_identity`
  `{"cik": ..., "aliases": [{"token", "context", "case"}]}` und das Boolean
  `news_watch`; siehe [News-Pflege](#news-pflege-adr-0056).
- `DELETE /api/v1/securities/:id` löscht ein Wertpapier, wenn nichts darauf
  verweist. Liest eine Policy-Regel es, antwortet der Aufruf mit
  `409 Conflict` und `errors.policy_rules`. Buchungen, Kurshistorie,
  Recherche-Notizen, Wertpapier-Ereignisse, Regelversionen oder Prognosen
  (über das Wertpapier oder gegen es als Benchmark gewertet) ergeben
  `409 Conflict` mit `errors.referenced_by` (die verweisenden Tabellen,
  gezählt, etwa `{"transactions": 3, "security_quotes": 120}`),
  `errors.remedy` und `errors.remedy_route`: `merge` für ein Duplikat, dessen
  Route die Zusammenführungs-Vorschau
  `GET /api/v1/securities/:id/merge_preview?target_id=` ist, ergänzt um die
  ID des Wertpapiers, das bleibt, oder `retire`, wenn Recherche-Notizen,
  Regelversionen oder Prognosen darauf verweisen, weil eine Zusammenführung sie nicht
  mitnehmen kann (die Route ist `PATCH /api/v1/securities/:id` mit
  `is_retired: true`). Bevor ein unreferenziertes Wertpapier gelöscht wird,
  werden seine Kategorie-Zuordnungen, Positionsziele,
  Positions-Bucket-Overrides und ISIN-Aliasse entfernt, jeweils
  journalisiert; keine Datenbank-Kaskade entfernt sie (ADR-0050 §11). Ein
  bereits gelöschtes Wertpapier liefert `404`. Ein Löschen, das einen Wettlauf mit einem
  gleichzeitigen Schreibvorgang verliert und danach keinen Verweis mehr
  findet, antwortet mit `409 Conflict` und allein `errors.detail` und löscht
  nichts: den Datensatz neu lesen und erneut versuchen (#954).
- `GET /api/v1/securities/search` durchsucht konfigurierte
  Online-Wertpapieranbieter. Query-Parameter: `query`; optional `type` mit
  `security` oder `crypto`. Jedes Feld eines Treffers stammt vom Anbieter und
  wird auf seinen Typ geprüft und in der Größe begrenzt: Ein Feld mit falschem
  Typ oder über seiner Grenze fehlt, ein Treffer ohne verwendbaren Namen
  entfällt, ein Handelsplatz behält nur begrenzte Felder und skalare
  Eigenschaften, und `raw` trägt nur `type` und `market_cap_rank`, nie den
  ganzen Eintrag des Anbieters. Die Attribute, die ein Treffer in ein
  Wertpapier schreibt, sind genauso begrenzt, und ein Name oder eine
  Kursquellen-URL über 255 Zeichen ist bei jedem Schreiben eines Wertpapiers
  ein `422`.

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
  `identifier_aliases`. Eine `new_isin`, die nicht zwölf Zeichen in der Form
  einer ISIN hat (zwei Buchstaben, neun Buchstaben oder Ziffern und eine
  Prüfziffer) oder deren Prüfziffer nicht stimmt, liefert `422` auf
  `new_isin`, eine `note` über 255 Zeichen `422` auf `note`. Abgelehnt mit `422` und benanntem Konflikt, wenn
  `new_isin` der aktuellen ISIN entspricht, auf einem anderen Wertpapier live
  ist oder als frühere ISIN eines anderen Wertpapiers aufgezeichnet ist; ein
  Wechsel zurück auf eine eigene frühere ISIN verbraucht diesen Alias (ein
  Revert). Jeder Wertpapier-ISIN-Schreibpfad — Anlegen, Aktualisieren und der
  Anlege-Pfad des Imports — lehnt symmetrisch eine ISIN ab, die als Alias
  existiert, und benennt das Alias-Wertpapier. Ein Konflikt benennt das
  andere Wertpapier mit seiner id (`security #12`), nie mit seinem
  gespeicherten Namen (siehe „Ein Datensatz in einem Satz“ unten).
- Ein Kennzeichen, das `PATCH /api/v1/securities/:id` an einem bestehenden
  Wertpapier **ändert**, erfüllt dieselben Katalogregeln, sonst `422` mit dem
  Feldnamen: eine `isin` in ISIN-Form mit stimmender Prüfziffer, eine `wkn`
  aus sechs Buchstaben oder Ziffern, ein `ticker_symbol` nur aus druckbarem
  ASCII. Ein Doppelgänger (ein Buchstabe aus einer anderen Schrift, ein
  unsichtbares Zeichen, eine falsche Prüfziffer) ersetzt so nie das
  Kennzeichen, das die Exporte tragen. Den gespeicherten Wert erneut zu senden
  ist keine Änderung, und ein neues Wertpapier behält, womit es angelegt wird.
  Der `name` eines Wertpapiers wird ohne Unicode-Formatzeichen gespeichert
  (Nullbreiten-Leerzeichen und -Verbinder, Steuerzeichen der Schreibrichtung).
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

### Ein doppeltes Wertpapier zusammenführen (ADR-0050 §9)

Eine zweite Kopie eines Instruments — ein Export mit neuerer ISIN, der
importiert wurde, bevor der Wechsel aufgezeichnet war, ein von Hand angelegtes
Wertpapier, das der nächste Import noch einmal anlegte — wird repariert,
indem man das Duplikat (die **Quelle**) in das Wertpapier zusammenführt, das
bleibt (das **Ziel**). Der Dialog des Operators auf der Wertpapierseite
(**Zusammenführen in…** im Zeilenmenü) liest diese Vorschau und bestätigt mit
demselben `plan_digest`, sodass beide denselben Plan sehen.

- `GET /api/v1/securities/:id/merge_preview?target_id=` zeigt die
  Zusammenführung des Wertpapiers in `target_id` als Vorschau — ein Lesen,
  das nichts schreibt (`portfolixir.securities.merge_preview`). Beide müssen
  in derselben Währung gehandelt werden, beide oder keines ein Benchmark
  sein, und das Ziel darf nicht stillgelegt sein, solange die Quelle lebt;
  solange die Quelle Kurse hat, müssen beide ihre synchronisierten Kurse
  gleich behandeln (`treat_quotes_as_raw`). Eine Quelle mit
  Recherche-Notizen, eine, die eine Prognose nennt (als bewertetes
  Wertpapier oder als Benchmark), oder eine, die eine eigene Regel liest,
  wird abgelehnt, weil eine Notiz und eine Prognose weder wandern noch
  verschwinden können und eine Regelversion ihr Subjekt behält
  (`research_notes`, `predictions`, `policy_rules` mit
  `errors.policy_rules`); wo die Zusammenführung in die andere Richtung
  gelänge, sagt das Detail es. Jede Position der Quelle in einem Depot muss
  ihre Ansichtszugehörigkeit behalten (`position_buckets_mismatch`). Ein
  Split der Quelle, den das Ziel im selben Portfolio am selben Tag mit
  demselben Verhältnis trägt, fällt zusammen; ein anderes Verhältnis wird
  abgelehnt (`split_ratio_mismatch`), ebenso ein Split, der einer Seite
  fehlt, während sie davor eine Buchung oder einen Kurs hat
  (`split_event_mismatch`), oder ein Split, der Buchungen neu skalieren
  würde, die er vorher nicht skaliert hat (`split_linearity`), oder ein
  Split, den die Zusammenführung verschieben müsste und der noch einen
  Import-Hash aus einer Umwandlung vor der Import-Hash-Artprüfung trägt
  (`legacy_hashed_split`, mit `errors.splits`; seine Art zurücksetzen oder ihn
  löschen — einen, den die Zusammenführung zusammenlegt, löscht sie und legt
  seinen Hash still). Eine ISIN der Quelle mit falscher Prüfziffer wird
  abgelehnt (`invalid_source_isin`, der gespeicherte Wert in
  `errors.source_isin`): Die Zusammenführung würde sie auf das
  Ziel schreiben, was der Katalog für ein gespeichertes Wertpapier ablehnt;
  sie ist daher zuerst an der Quelle zu korrigieren oder zu leeren. Schließlich
  muss jede Identität beider Wertpapiere nach der Zusammenführung das Ziel
  finden (`identity_unresolvable`, mit `errors.unresolvable`): die
  gespeicherte Identität, die Identität, die der Portfolio-Performance-Import
  beim Anlegen des Wertpapiers aufgezeichnet hat (Name, ISIN, WKN, Ticker und
  Währung — eine Datei löst über das auf, was sie trägt, nicht über Kennzeichen,
  die seither dazukamen), jede frühere ISIN und, für jedes Wertpapier, das
  zuvor in eines der beiden zusammengeführt wurde (und in jene, die ganze
  Kette hinab), seine gespeicherte und seine importierte Identität
  (`merged_stored`, `merged_imported`, unter der ID des weggefallenen
  Wertpapiers): Ein Überlebender, der seinerseits zusammengeführt wird, muss
  jeden früheren Import weiter zur Historie führen. Ein nur über den Namen
  importiertes Wertpapier, das danach einen Ticker bekam und dessen Name vom
  Ziel abweicht, ist so ein Fall; ebenso ein Name, den ein anderes lebendes
  Wertpapier auch trägt. Jede Ablehnung ist ein `409 Conflict` mit
  `errors.code`, `errors.detail` und `errors.guards`; eine unbekannte Quelle
  antwortet `404`, eine schon zusammengeführte `409` `already_merged` mit
  `errors.merged_into`, eine fehlende `target_id` `422`. Das `200` enthält:
  - `plan_digest`, den Digest, den die Zusammenführung nimmt;
  - `source` und `target`, jeweils mit Name, Währung, `isin`, `wkn`,
    `ticker_symbol`, `feed`, `asset_class`, Flags, `transaction_count` und
    `split_events`; `guards`; `reverse`, ob die andere Richtung gelänge;
  - `key_equal_pairs` und `choice_required` wie bei einer
    Konto-Zusammenführung, und `splits` (`collapsed`, `moved`) mit den
    `split_events` davor und danach;
  - `position_buckets`: je Depot, in dem die Quelle hält oder einen Override
    trägt, beide wirksamen Bucket-Mengen, beide Overrides und die `action`;
  - `quotes`: `source_count`, `moved_count` (Kurse der Quelle an Tagen ohne
    Kurs des Ziels; sie wandern und behalten ihre Quelle), `collision_count`
    (Tage, an denen beide einen haben: Der Kurs des Ziels gewinnt, der
    Schlusskurs der Quelle geht ins Protokoll der Zusammenführung) und
    `manual_collisions`, jeder kollidierende, von Hand erfasste Kurs der
    Quelle mit `date`, `source_close`, `target_close` und `target_source`;
  - `configuration`: `category_assignments` (je Klassifizierung der Quelle
    `move`, wo das Ziel dort keine hat, sonst `drop` — die des Ziels
    gewinnt — mit beiden Kategorien) und `position_targets` (jedes
    Positionsziel der Quelle in einem aktiven, Entwurfs- oder archivierten
    Plan, mit Plan, `plan_status`, Kategorie und `target_weight`, und
    `move` oder `drop` mit dem `reason` `collides` — das Ziel hat in dem
    Plan schon eine Zeile — oder `stale` — die Zeile läge nicht mehr unter
    der Kategorie des Ziels);
  - `events`: die Termine, die wandern, und `possible_duplicates`, ein
    Termin der Quelle und einer des Ziels gleicher Art am selben Tag (beide
    bleiben);
  - `identifiers`: `choice_required` (beide tragen eine ISIN), dann
    `after_by_identity_choice` mit `keep_target_isin` und
    `adopt_source_isin` — oder `after`, wenn es nichts zu wählen gibt —,
    jeweils `isin`, `wkn`, `ticker_symbol`, `feed`, `name`, `asset_class` und
    `former_isins` des Ziels danach; `adopted`, was das Ziel von der Quelle
    übernimmt (eine fehlende WKN, einen fehlenden Ticker oder Feed, eine ISIN,
    die nur die Quelle trägt); `differences`, jeden Wert der Quelle, der
    stattdessen dem Ziel folgt (Name, Anlageklasse, Logo, eine WKN, ein Ticker
    oder Feed, den das Ziel schon hat, und eine WKN oder ein Ticker, den die
    Regeln des Katalogs bei einer Änderung ablehnen — nie übernommen, mit
    `null` für das Ziel; und `provider_currency`, die Währung, die der
    Kursanbieter der Quelle nannte, wann immer sie vom `currency_code` des
    Ziels oder von dessen eigener gespeicherter abweicht — mit ihrer Zeit
    auf ein Ziel übernommen, dessen `target` `null` ist, sonst bleibt die
    des Ziels); `aliases_reassigned`, die früheren ISINs der Quelle;
  - `outcome_by_collapse_key_equal` mit `"false"` und `"true"`: die
    `transaction_count` des Ziels danach, `moved_transaction_ids`,
    `deleted` (`collapsed_duplicate` oder `collapsed_split`), `positions`
    (je Depot, in dem die Quelle hält: `source`, `target` und `after`,
    jeweils `quantity`, `cost_basis`, `avg_cost` und `realized_result`),
    `fifo_realized`, `rounding_differences`, `cash_accounts` und
    `flow_changes`, mit `positions_basis` und `flow_basis` wie bei einer
    Depot-Zusammenführung (ein Eintrag `removed` oder `boundary_removed`
    nennt das Quell-Wertpapier); `reimport_note` sagt, was die
    Zusammenführung für den nächsten Import bedeutet;
  - `fifo_realized`, in jedem Ergebnis: die realisierten Gewinne nach FIFO,
    die die Zusammenführung neu feststellt (Sicherheitsprüfung 2026-10-12,
    K11). Die realisierten Gewinne der App (`GET /api/v1/realized_gains`,
    die Trades eines Wertpapiers) laufen nach FIFO über eine Reihe je
    Wertpapier über alle Depots; die Zusammenführung legt beide Reihen
    zusammen, sodass ein Verkauf den älteren Posten des anderen Wertpapiers
    schließen kann. `years` nennt je Abschlussjahr und Währung das
    realisierte Ergebnis der Quelle und des Ziels, jeweils über die eigene
    Reihe vorher (`null`, wo es in dem Jahr keinen Trade schließt), des
    Ziels über die zusammengeführten Buchungen danach, und die Änderung
    (`change`); `open_lots` den Einstand der offenen Posten ebenso;
    `unmatched_sells` die Verkäufe, die kein Posten deckt, je Seite;
    `unchanged` ist wahr, wenn sich kein realisierter Betrag und kein
    offener Einstand ändert — welchen Posten ein Verkauf schließt, und mit
    ihm Haltedauern und annualisierte Renditen, kann sich dennoch ändern. Beträge stehen in der
    Währung jedes Trades, nie umgerechnet; `fifo_basis` nennt die Regel.
    `realized_result` in `positions` ist das Ergebnis des Depots nach
    gleitendem Durchschnitt, nicht diese Zahl.

  Jede Stückzahl, jeder Kurs, jedes Gewicht und jede Dezimalzahl ist ein
  String. Der Digest deckt beide Wertpapiere, jede Buchung beider, ihre
  Kurse, Kategorie-Zuordnungen, Positionsziele, Termine und früheren ISINs
  mit ihrem `updated_at`, die Identitäten, die die Importe aufgezeichnet
  haben, jede Zahl und die Guards ab; die Wahlen gehören nicht dazu, sodass
  ein Paar einen Digest hat, und ein Kurs, den der Sync zwischen Vorschau und
  Zusammenführung speichert, ein geänderter Plan ist.
- `POST /api/v1/securities/:id/merge` mit `{"target_id": …, "plan_digest":
  …, "collapse_key_equal": …, "identity_choice": …, "isin_changed_on": …}`
  führt unter dem Token zusammen (`portfolixir.securities.merge`).
  `collapse_key_equal` ist Pflicht, wenn die Vorschau `key_equal_pairs`
  nennt, und `identity_choice`, wenn beide Wertpapiere eine ISIN tragen —
  ohne sie jeweils ein `422`, und nie vorausgewählt: Frag den Operator. Die
  Ablehnung zu `identity_choice` nennt die ISINs nach ihrer Art und trägt
  beide in `errors.isins` (`source_isin`, `target_isin`).
  `keep_target_isin` behält die ISIN des Ziels und zeichnet die der Quelle
  als frühere ISIN des Ziels auf; `adopt_source_isin` gibt dem Ziel die ISIN
  der Quelle und zeichnet seine alte als frühere ISIN auf (die Reparatur des
  Duplikats in falscher Reihenfolge aus ADR-0029 §3, zusammen mit
  `collapse_key_equal: true`). `isin_changed_on` (`YYYY-MM-DD`, optional)
  ist das `changed_on` dieser früheren ISIN, sonst das Datum der
  Zusammenführung. Eine unbekannte `identity_choice` oder ein
  `isin_changed_on`, das kein Datum ist, antwortet `422`. Sie antwortet
  `201 Created` mit dem Protokoll der Zusammenführung (`kind` `security`,
  `portfolio_id` `null`; sein `manifest` nennt jede verschobene oder
  gelöschte Buchung, jeden verschobenen Kurs und jeden verworfenen mit seinem
  Schlusskurs und dem des Ziels, der gewann, die verschobenen oder
  verworfenen Zuordnungen, Positionsziele und Termine, die umgehängten und
  angelegten früheren ISINs, die übernommenen Kennzeichen, die Unterschiede
  und die Wahlen — `collapse_key_equal` nur, wo die Vorschau
  `key_equal_pairs` nannte, `identity_choice` und `isin_changed_on` nur, wo
  die Zusammenführung diese Wahl getroffen hat, weil beide Wertpapiere eine ISIN
  trugen, sonst `null`, was die Anfrage auch schickte) und
  `already_applied: false`. In einer Transaktion, ein
  Audit-Journal-Eintrag je Zeile: Mit `true` werden die gepaarten Buchungen
  der Quelle gelöscht und ihre Inhalts-Hashes stillgelegt; ein Split, den
  das Ziel am selben Tag im selben Portfolio trägt, wird gelöscht; jede
  andere Buchung geht auf das Ziel über; die Stückzahl jedes Depots wird an
  jedem Tag gegen die Buchungen beider Wertpapiere geprüft
  (`409 identity_check_failed` sonst); der Bucket-Plan wird geschrieben; die
  Kurse füllen die Lücken des Ziels — **nicht journalisiert**, das Protokoll
  der Zusammenführung ist ihr Nachweis — und die abgeleiteten Werte beider
  Wertpapiere werden verworfen; Zuordnungen, Positionsziele und Termine
  wandern oder entfallen, wie die Vorschau sie genannt hat; die früheren
  ISINs der Quelle gehen an das Ziel, ihre ISIN wird nach der Wahl
  geschrieben, WKN, Ticker und Feed dort, wo sie dem Ziel fehlen; die Quelle
  wird gelöscht; und die Identitäten werden am Katalog, wie die
  Zusammenführung ihn hinterlassen hat, noch einmal geprüft
  (`409 identity_unresolvable` mit `errors.unresolvable` rollt sie sonst
  zurück). Danach bucht ein Portfolio-Performance-Import, der die Quelle
  über eines ihrer Kennzeichen nennt, auf das Ziel, und ein erneut
  angewendeter, schon importierter Export legt nichts an. Ein geänderter
  Plan antwortet `409` `plan_changed` mit der frischen Vorschau in
  `errors.preview`; eine Wiederholung einer abgeschlossenen Zusammenführung
  desselben Paars antwortet `200` mit dem ursprünglichen Protokoll und
  `already_applied: true`; eine in ein anderes Wertpapier zusammengeführte
  Quelle `409` `already_merged`. Ein Rückgängigmachen gibt es nicht.

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
`event_result`, `risk`, `retraction`, `decision`), `body`, `source_url` (eine
`http(s)`-URL mit höchstens 2.048 Zeichen, der eigenen Grenze des
Nachrichten-Parsers (ADR-0056 E2); andere Schemata, längere Links und ein
Link mit einem Backslash, den ein Browser als `/` liest und der so einen
anderen Host öffnen würde als den angezeigten, sind ein `422`),
`source_quality` (`primary`, `secondary_multi`, `awareness`, `unverified` —
**gesetzt, nicht geraten**), `as_of` (das Stichdatum der Aussage, getrennt
von `inserted_at`: ein heute geschriebener Eintrag über das letzte Quartal
trägt das Datum des Quartals), `author` und `machine_generated` — `author`
(`operator` oder `agent`) wird aus dem Zugang abgeleitet, der den Eintrag
schreibt, `agent` für jedes API-Token, und `machine_generated` ist einem Pfad
mit lokalem Modell vorbehalten, den es noch nicht gibt (ein extrahierter
Eintrag wäre ein Vorschlag bis zur Bestätigung und trüge seine
`source_url`); beide werden in einem Body ignoriert, ein Body kann also
keines von beiden beanspruchen —, `supersedes_id` (der frühere Eintrag desselben Wertpapiers, den
dieser ersetzt; Pflicht bei einem Widerruf), `valid_until` (eine datierte
Sperre wie ein Lock-up oder eine selbst auferlegte Kaufsperre), — nur
bei `thesis`-Einträgen — `conviction` (`low`, `medium`, `high`),
`invalidation_condition` und `time_stop` und — nur bei `evidence`- und
`event_result`-Einträgen (Änderung von ADR-0044 vom 2026-11-06) —
`headline` (Klartext mit höchstens 80 Zeichen, eine Zeile, kein unsichtbares
Zeichen), `event_type` (`earnings`, `guidance`, `capital_measure`, `legal`,
`m_and_a`, `product`, `regulatory`, `macro`) und `tone` (`-1`, `0`, `1`, die
Lesart des Schreibenden für das Wertpapier: Sie färbt eine Markierung im
Chart und ist nie Filter, Sortierschlüssel oder Signal); bei einer anderen
Art liefert jedes davon `422` mit dem Feldnamen. Wie jedes Feld werden sie
einmal gesetzt: Das Log hängt nur an. Ein Eintrag ohne sie liest sie als
`null`, und `news_label_id` nennt das Nachrichten-Label, aus dem ein aus
einer Story geschriebener Eintrag seinen Ereignistyp oder seinen Ton nahm
(die Herkunftsangabe des Servers, nie aus einem Body übernommen). Jeder
Eintrag in einer Antwort trägt zudem `superseded_by_ids` und ein `superseded`-Flag, sodass ein
ersetzter Eintrag als ersetzt gezeigt statt verborgen wird. Alle festen
Wertemengen werden geprüft; ein unbekannter Wert ist ein `422` mit dem
Feldnamen, und aus Eingaben entsteht nie ein Atom.

- `GET /api/v1/securities/:security_id/notes` — das Log, neueste zuerst
  (nach `as_of`, dann Schreibzeit), mit dem abgeleiteten `thesis_state` und
  einer `log_note`, die den Nur-anhängen-Kontrakt benennt.
  `limit` behält die neuesten Einträge, in einem Delta-Read die ältesten nach
  `since` (Standard 1000, max. 10000); `thesis_state` leitet sich immer aus
  dem ganzen Log ab, und die Antwort nennt das angewandte `limit`.
- `POST /api/v1/securities/:security_id/notes` — hängt einen Eintrag aus
  einem `note`-Objekt an (`201`); journalisiert unter dem API-Token-Akteur.
  Ein `as_of` nach heute (dem Kalendertag der Instanz) liefert `422` auf
  `as_of` („must not be in the future“): Das Log hängt nur an, ein vertipptes
  Jahr in der Zukunft ließe sich nie zurücknehmen. `valid_until` und
  `time_stop` dürfen in der Zukunft liegen. `body` fasst höchstens 20000
  Zeichen, `invalidation_condition` höchstens 10000 (Unicode-Codepoints); ein
  längerer Wert liefert `422` mit dem Feld, und auch die Datenbank lehnt ihn
  ab.
- `GET /api/v1/notes/unreviewed?days=N` — gehaltene Wertpapiere
  (Nettostückzahl ungleich null über alle Depots), deren neuester Eintrag
  älter als `N` Tage ist (Standard 90) oder die keinen haben; Zeilen tragen
  `last_entry_as_of` und `days_since_last_entry` (`null`, wenn nie geprüft).
  Ein Eintrag zählt als Prüfung an seinem `as_of`, aber nicht später als am
  Tag nach seinem Anlegen; ein Eintrag, der vor der Ablehnung mit einem
  `as_of` in der Zukunft gespeichert wurde, hält seine Position also nicht
  aus dieser Liste. `last_reviewed_at` des Thesenstands folgt derselben
  Regel, und der Eintrag selbst behält sein `as_of`.
  `limit` behält die am längsten überfälligen Positionen (Standard 1000, max.
  10000).
- `GET /api/v1/notes/uncorroborated` — Einträge, deren `source_quality`
  nicht `primary` ist, neueste zuerst; ersetzte Einträge werden übersprungen,
  sofern nicht `include_superseded=true`; optional `security_id`.
  `limit` behält die neuesten Einträge (Standard 1000, max. 10000).
- `GET /api/v1/notes/expiring?days=N` — Einträge, deren `valid_until` in die
  nächsten `N` Tage fällt (Standard 30), früheste zuerst, mit
  `days_until_expiry`; aufgehobene (ersetzte) Sperren werden übersprungen;
  optional `security_id`.
  `limit` behält die am frühesten ablaufenden Einträge (Standard 1000, max.
  10000).

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

**Eine Story wird nur durch einen bestätigten Schreibvorgang zum Eintrag**
(ADR-0056 §8, A2): `POST /api/v1/securities/:security_id/notes`
mit `note.cluster_id` (eine Story dieses Wertpapiers) und einem `body`
schreibt einen Eintrag, den der Server aus der Story vorbelegt: `kind`
`evidence` (`event_result` darf stattdessen gesendet werden; eine andere Art
liefert `422` mit `kind`); `as_of` der Tag, an dem die Story veröffentlicht
wurde (die Veröffentlichung ihres Repräsentanten, wie `news.get` sie
antwortet); `source_url` der Link ihres Mitglieds der besten Stufe, der erste,
der in 2.048 Zeichen passt; `source_quality` nach der Regel von ADR-0056 §3 (ein
`primary`-Mitglied ergibt `primary`, zwei oder mehr verschiedene
`secondary`-Domains `secondary_multi`, eine `unverified`, sonst
`awareness`), jedes Mitglied mit der Stufe, die ihm die Quellentabelle jetzt
gibt, sodass eine zweite Übernahme nach einer Neubewertung die neue Stufe
nennt, und ein Mitglied, dessen Domain jetzt gesperrt ist, bleibt außen vor
(bei der Qualität und beim Link; ADR-0056 E1 Regel 5); `headline` ihr Titel,
an einer Wortgrenze auf 80 Zeichen
gekürzt; `event_type` und `tone` aus ihrem aktiven Label der neuesten
Prompt-Version (ein `noise`-Label ergibt keinen Ereignistyp), und der Eintrag
behält die Id dieses Labels als `news_label_id`. Die Vorbelegung ist ein
Vorschlag: `kind`, `headline`, `event_type` und `tone` neben `cluster_id`
ersetzen sie, und `null` lässt eines weg; `as_of`, `source_url` und
`source_quality` gehören der Story, und eines davon neben `cluster_id`
liefert `422` mit dem Feldnamen. Ein Titel mit einem unsichtbaren Zeichen
wird als Schlagzeile abgelehnt, mit `headline`; dann eine eigene senden.
Danach ist jedes Mitglied der Story `promoted` und nennt den Eintrag in
`note_ids` (`news.get`, `news.list` mit `fields=std`), sodass es die
Aufbewahrungsfrist überdauert; eine zweite Übernahme hängt einen weiteren
Eintrag an, und die Story nennt beide. Eine Story eines anderen Wertpapiers,
die Story einer Kategorie, eine Id ohne Story oder eine Story, deren
Mitglieder alle aus jetzt gesperrten Domains stammen, liefert `422` mit
`cluster_id`. Nichts in der News-Schicht schreibt von sich aus einen Eintrag,
einen Termin oder eine Prognose.

**Eine Nachricht von einem externen Aggregator** (Idee I13; Sprint-25-Plan
D-5), die die News-Schicht nicht hält, wird als gewöhnlicher Eintrag
festgehalten: `kind` `evidence`; `as_of` das Datum, an dem die Nachricht öffentlich
wurde, also das Stichdatum der Aussage, sodass sie neben dem Schlusskurs
dieses Tages steht; `source_url` der Artikel; `source_quality`, wie der
Aggregator sie beurteilt hat; `body` eine Zusammenfassung und der Link, **nie der Artikel** —
Portfolixir führt kein Nachrichtenarchiv. Eine Richtung, die der Aggregator
aus der Nachricht liest (positiv, negativ), kommt nicht in den Eintrag: Sie
wird als Prognose festgehalten (`POST /api/v1/predictions`,
`portfolixir.predictions.create`) mit `note_id` auf den Eintrag, sodass die
Einschätzung wie jede andere aufgelöst und bewertet wird. Die Aggregation
läuft außerhalb der App; Portfolixir ruft selbst keine Nachrichten ab. Für
`GET /api/v1/notes/unreviewed` (`portfolixir.notes.unreviewed`) ist ein
Nachrichten-Eintrag ein Eintrag wie jeder andere: Er nimmt seine Position von
dieser Liste. Ob die These selbst überprüft wurde, sagt `last_reviewed_at` im
Thesenstand, das nur Einträge der Art `thesis` und `invalidation_check`
bewegen.

Die menschliche Sicht ist der Tab **Research** im Wertpapier-Detailbereich
auf `/securities/:id`: der Thesenstand oben, die Einträge neueste zuerst mit
sichtbarer Art und Quellenqualität, ersetzte Einträge als ersetzt markiert,
Widerrufe lesbar und ein Formular, das einen Eintrag als Betreiber anhängt.

### Prognosen (ADR-0055)

Eine **Prognose** ist ein dauerhafter Datensatz einer Einschätzung zu einem
Wertpapier: Es entwickelt sich bis `resolves_on` besser (`outperform`) oder
schlechter (`underperform`) als eine Benchmark, mit einer genannten
Wahrscheinlichkeit. **Sie lässt sich nicht bearbeiten, zurückziehen oder
löschen**, von niemandem: Es gibt absichtlich kein `PATCH` und kein `DELETE`.
Eine irrtümliche Prognose bleibt und zählt; eine Korrektur ist eine neue
Prognose, und beide zählen. Status, Ergebnis und Zahlen werden bei jedem Lesen
aus gespeicherten Schlusskursen abgeleitet und nie gespeichert, sodass ein
später korrigierter Kurs das Ergebnis sichtbar ändert. Stufe (c): Bewertet
wird, was festgehalten wurde, bevor sein Ergebnis bekannt war. Kein Feld
trägt eine Order, eine Größe oder ein Limit, und nichts schlägt eines vor.

- `POST /api/v1/predictions` — hält eine Prognose aus einem
  `prediction`-Objekt fest (`201`): `security_id`; `direction`
  (`outperform`, `underperform`); `probability`, ein **Dezimal-String** von
  `"0.50"` bis `"0.99"` in Schritten von `0.01` (eine JSON-Zahl liefert
  `422`; `"0.49"` liefert `422` mit der Gegenrichtung, denn eine Prognose
  unter 50 % ist die entgegengesetzte über 50 %, und `"1.00"` wird
  abgelehnt, weil sich eine als sicher genannte Prognose nicht bewerten
  lässt); `benchmark`, geschrieben wie `benchmark=` — `security:<id>`
  jedes Wertpapiers mit einem gespeicherten Kurs, mit oder ohne
  `is_benchmark` (nicht des Wertpapiers selbst; eines ohne Kurs liefert
  `422`, `has no stored quote`; Ergänzung von ADR-0046 vom 2026-11-07)
  oder `rate:<dezimal>`, ein fester Jahreszins als **Bruch** von
  `-0.999999` bis `1` (`rate:0.02` sind 2 % im Jahr; ein Zins über 1 liefert
  `422` mit der Bruchschreibweise, denn `rate:5`, gemeint als 5 %, wären
  500 % im Jahr auf einem Datensatz, der sich nie korrigieren lässt), wobei
  `rate:0` die Prognose absolut macht; `resolves_on`, 7 bis 1.830 Tage nach
  dem UTC-Tag, an dem
  sie abgegeben wird; `model`, das Modell, auf dem ein Agent läuft
  (höchstens 100 Zeichen), **Pflicht für ein API-Token**, abgelehnt für die
  Seiten des Betreibers; optional `note_id`, ein Research-Log-Eintrag
  desselben Wertpapiers (seine These, seine Entscheidung, seine Nachricht);
  optional `rationale` (höchstens 4.000 Zeichen). `made_at` ist die Uhr des
  Servers, `author` (`agent` für jedes API-Token) und `actor` (der Name des
  Tokens) stammen aus dem Zugang: Ein Body mit einem der drei liefert `422`
  mit diesem Feld, denn eine in die Vergangenheit datierte Prognose ist eine,
  die mit dem Ergebnis vor Augen abgegeben wurde. Jede Ablehnung ist ein
  `422` mit allen Feldfehlern zugleich; gespeichert wird nichts. Der
  Schreibvorgang wird als `prediction` / `create` unter dem Token
  journalisiert. Eine Prognose bewahrt außerdem ihr Wertpapier und ihr
  Benchmark-Wertpapier davor, je zusammengeführt oder gelöscht zu werden;
  stattdessen wird eines stillgelegt.
- `GET /api/v1/predictions/:id` — eine Prognose mit ihrer `resolution`,
  einer `permanence_note` und der `computation_basis` der Auflösungsregel;
  `404` für eine unbekannte ID.
- `GET /api/v1/predictions` — die Prognosen, neueste zuerst, jede gelesen
  wie oben, mit `as_of`, den wiedergegebenen `filters`, `limit` (Standard
  100, max. 500) und `truncated`, der `permanence_note` und der
  `computation_basis`. Optionale Filter: `security_id`, `status` (`open`,
  `resolved`, `unresolved`, beim Lesen abgeleitet; `limit` zählt dann die
  Prognosen, die der Status behält), `author` (`operator`, `agent`), `model`
  (genau wie genannt) und `due_before`, **die Fälligkeitsabfrage**: die
  offenen Prognosen, deren `resolves_on` auf oder vor dem Datum liegt,
  einschließlich einer, deren Datum vorbei ist und die noch auf ihren
  Endkurs wartet. Ein fehlerhafter Filter liefert `422` mit seinem Namen.
- `GET /api/v1/predictions/calibration` — der Kalibrierungsbericht über die
  Prognosen, die die Filter nennen, jede zum heutigen Tag aufgelöst:
  `counts` (`total`, `open`, `resolved` und `unresolved` nach Grund);
  `brier` — der Brier-Score über alle aufgelösten Prognosen (der Mittelwert
  von `(probability − outcome)²`, outcome 1 für einen Treffer und 0 für einen
  Fehlschlag; niedriger ist besser), sein `standard_error` und die
  `reference` `"0.25"`, der Score, wenn man zu allem 50 % sagt;
  `sharpness`, der Mittelwert von `probability − 0.50`, daneben, denn wer zu
  allem 50 % sagt, ist perfekt kalibriert und sagt nichts; `hit_rate`
  (`rate`, `hits`, `mean_probability` und ihr `standard_error`); fünf
  `bands` (`0.50`–`0.59` bis `0.90`–`0.99`), jedes mit `count` und
  `mean_probability` und einer `hit_rate` erst ab 20 aufgelösten Prognosen:
  darunter ist sie der String `"too_few"`; `groups`, derselbe Block je
  `author` und je `model`; und die ganze `computation_basis`. Ohne
  aufgelöste Prognose ist jede Zahl `null`, und ein Standardfehler ist
  `null` mit `standard_error_reason` `no_resolved` oder, bei einer,
  `one_resolved`. Offene und unaufgelöste Prognosen gehen in keinen Score
  ein und werden gezählt. Optionale Filter: `author`, `model` sowie `from` /
  `to`, ein Bereich über `resolves_on`, beide einschließlich; `to` vor
  `from` liefert `422` auf `to`. **Rechnen Sie lange mit `too_few`**: Der
  Gesamtscore mit seinem Standardfehler trägt ab den ersten Auflösungen
  Bedeutung.

Eine gelesene Prognose trägt `id`, `security_id`, `direction`,
`probability`, `benchmark`, `resolves_on`, `made_at`, `made_on` (ihr
UTC-Tag), `author`, `actor`, `model`, `note_id`, `rationale` und
`resolution`:

- `status` — `open`, solange der Kalendertag der Instanz auf oder vor
  `resolves_on` liegt, und danach, **bis ihr Endkurs da ist**: bis das
  Wertpapier und ein Benchmark-Wertpapier je einen gespeicherten Schlusskurs
  mit Datum an oder nach `resolves_on` haben (der Beleg, dass die Daten des
  Tages da sind, nie in der Messung verwendet) oder bis 7 Tage nach
  `resolves_on` vergangen sind. So kippt eine aufgelöste Prognose nie, wenn
  der Schlusskurs von `resolves_on` spät eintrifft. Danach `resolved` mit
  `outcome` `hit` oder `miss` oder `unresolved` mit `reason`
  `no_start_close`, `no_end_close`, `no_benchmark_close` oder `no_fx_rate`,
  nie geschätzt (ADR-0055, Ergänzung vom 2026-11-05);
- `start_on` — der UTC-Tag der Abgabe: Der Startkurs ist der letzte
  Schlusskurs **an oder vor** diesem Tag, sodass eine Prognose nach dem
  Tagesschluss vom Kurs ausgeht, den sie kannte, und eine davor von einem
  Schlusskurs, der nach ihr kommt: Keine Prognose wird für eine Bewegung
  bewertet, die sie schon gesehen hatte; `end_on` —
  `resolves_on`, der Endkurs der letzte an oder vor diesem Tag; ein
  Schlusskurs, der mehr als 7 Tage älter ist als das Datum, für das er
  steht, ist kein Kurs;
- `security` — `security_id`, `currency_code`, `start` und `end` (jeweils
  `stands_for`, `date`, `close`, `stored_close`, `source`, `fx_rate` und
  `eur_value`, der Kurs zum gespeicherten EUR-Hub-Kurs seines eigenen Datums
  in EUR umgerechnet) und `return`, der EUR-Wert am Ende durch den am Start
  minus 1, berechnet als eine Division exakter Produkte
  (`(Endkurs × Hub-Kurs am Start) / (Startkurs × Hub-Kurs am Ende) − 1`),
  sodass zwei gleiche Bewegungen in einer Währung bis zur letzten Stelle
  gleiche Renditen ergeben; `null`, solange offen oder wenn diese Seite
  keine Antwort hat;
- `benchmark` — die Seiten einer Wertpapier-Benchmark nach derselben Regel
  oder `{kind: "rate", rate, from, to, days, return}`, der Zins täglich
  verzinst über die Tage zwischen den beiden Daten, für die die Kurse des
  Wertpapiers stehen;
- `excess` — die Rendite des Wertpapiers minus die der Benchmark: Eine
  `outperform`-Prognose trifft, wenn er über 0 liegt, eine
  `underperform`-Prognose, wenn er unter 0 liegt, und 0 ist für beide ein
  Fehlschlag. Nur Kursrenditen: Ausschüttungen zählen auf keiner Seite.

Beispiel-Payload zum Festhalten:

```json
{
  "prediction": {
    "security_id": 12,
    "direction": "outperform",
    "probability": "0.65",
    "benchmark": "security:7",
    "resolves_on": "2027-05-03",
    "model": "example-model-1",
    "note_id": 41,
    "rationale": "Der Hochlauf des Werks aus dem Thesen-Eintrag zeigt sich in den nächsten zwei Quartalen."
  }
}
```

### Wertpapier-Termine (ADR-0048)

Ein **Wertpapier-Termin** ist eine datierte Aussage darüber, dass einem
Wertpapier etwas bevorsteht oder zugestoßen ist: Geschäftszahlen, ein
Ex-Dividenden- oder Zahltag, das Ende einer Haltefrist, eine Indexüberprüfung,
eine Hauptversammlung, eine Behördenentscheidung, eine Prognoseanpassung.

Es ist **keine** Kapitalmaßnahme. Ein Split *verändert eine Position* und ist
deshalb ein Ledger-Ereignis (ADR-0028); ein Termin für Geschäftszahlen
verändert nichts, bis sich ein Kurs bewegt — und eine Kursbewegung ist bereits
ein Kurs. `security_events` ist eine eigene Tabelle, und die Ledger-Projektion
sieht keine dieser Zeilen. Wird aus dem Termin eine Buchung — die Dividende
wird tatsächlich gezahlt —, läuft die Buchung wie immer über das Ledger und der
Termin wird als `confirmed` markiert: **ein Termin wird nie in eine Transaktion
umgewandelt.**

**Der Katalog, nicht der Bestand.** Termine hängen an `security_id` und an
nichts sonst, und die katalogweiten Reads umfassen standardmäßig **jedes**
Wertpapier. `held_only=true` grenzt ein und ist nie die Voreinstellung: ein aus
der Positionsliste abgeleiteter Kalender kann für ein noch nicht gehaltenes
Wertpapier keinen Termin führen — und das ist genau das Wertpapier, dessen
Termine zählen.

**Ein Datum wird qualifiziert.** `timing` ist `exact`, `estimated`, `window`
(zwischen `date` und `date_end`, nur hier erlaubt) oder `month` (der Monat ist
bekannt, der Tag nicht). Eine Schätzung darf nicht wie eine Meldung aussehen.

**Änderbar und journalisiert**, bewusst nicht append-only: ein verschobener
Termin macht das alte Datum nicht zu einem zweiten Fakt, sondern falsch. Eine
Korrektur ist ein `PATCH` auf derselben Zeile; die Änderungshistorie liegt im
Audit-Journal.

Die Reads:

- `GET /api/v1/securities/:security_id/events` — die Termine eines
  Wertpapiers, die nächsten zuerst, mit `limit` (Standard 1000, max. 10000).
- `GET /api/v1/events/upcoming?days=N` — alles, was in den nächsten `N` Tagen
  (Standard 30) im **gesamten Katalog** ansteht. Ein `window`- oder
  `month`-Termin ist fällig, sobald **irgendein** Tag, auf den er fallen kann,
  im Horizont liegt. Optional `kind`, `held_only`, `limit`. `days` ist
  begrenzt wie `limit`: Werte über zehn Jahre werden gekappt und gekappt
  zurückgemeldet.
- `GET /api/v1/events/unconfirmed` — Termine, deren Zeitraum vorbei ist und
  die niemand bestätigt hat. Optional `security_id`, `kind`, `held_only`,
  `limit`; bewusst **kein** `days`, denn ein unbestätigter vergangener Termin
  gehört in die Liste, egal wie alt er ist.
- `GET /api/v1/events/stale?days=N` — Termine, deren `checked_at` älter als
  `N` Tage (Standard 90) ist oder die nie geprüft wurden (`days_since_checked` ist dann
  `null`). Ein Termin, dessen gespeichertes `checked_at` nach morgen liegt
  (vor der Ablehnung unten geschrieben), steht ebenfalls darin, mit
  negativem `days_since_checked`.

Die Writes: `POST /api/v1/securities/:security_id/events` (`201`),
`PATCH /api/v1/security_events/:id` und `DELETE /api/v1/security_events/:id`
(`204`). Beim Anlegen gilt: `security_id` kommt aus dem Pfad, nie aus dem
Body; `machine_generated` ist reserviert und wird im Body ignoriert.
`event.news_id` (ADR-0056 §8) nennt einen Nachrichten-Eintrag
dieses Wertpapiers als Quelle des Termins: Sein Link wird `source_url`, die
Stufe, die ihm die Quellentabelle jetzt gibt, `source_quality` (`primary`,
`secondary` als `unverified`,
`awareness`); `source_url` oder `source_quality` daneben liefert `422` mit
dem Feldnamen, und ein Eintrag eines anderen Wertpapiers, einer, den es nicht
gibt, einer aus einer jetzt gesperrten Domain oder einer mit einem Link über
2.048 Zeichen liefert `422` mit `news_id`.
Der Eintrag wird nicht übernommen: Was von Nachrichten bleibt, ist ein
Research-Eintrag. Das Wertpapier, zu dem ein Termin gehört, lässt sich nicht
ändern. Auf beiden schreibenden Wegen liefert ein `checked_at` nach morgen
(Kalendertag der Instanz plus ein Tag für Zeitzonen) `422` auf `checked_at`,
und nichts wird geschrieben. Die `note` eines Termins fasst höchstens 10000
Zeichen (Unicode-Codepoints); eine längere liefert `422` auf `note`. `source_quality` verwendet dieselben vier Werte wie das Research-Log.
Ein Termin trägt **kein Geld**.

**Was diese Fläche nicht ist.** Nichts ruft einen Kalender ab — Eintrag von
Hand oder durch den Agenten. Der Fälligkeits-Read wird **abgefragt**: es gibt
keine Benachrichtigung und keine Zustellung nach außen, und keine Regel liest
diese Zeilen.

### Abgeleitete Kennzahlen (ADR-0047)

Stufe **(a)** der Scope-Leiter: die Preiskennzahlen eines Wertpapiers, beim
Lesen aus der bereits gespeicherten Kurshistorie abgeleitet. Nichts wird
gespeichert, nichts abgerufen.

- `GET /api/v1/securities/:security_id/metrics` — `sma_50` und `sma_200` mit
  der `distance_pct` des letzten Schlusskurses zu jedem; `volatility` und
  `max_drawdown` über die Fenster `30d`, `90d` und `365d`; `momentum` über
  `3m`, `6m` und `12m`; `distance_to_extremes`, das 52-Wochen-Hoch und -Tief
  mit ihren Daten und dem Abstand zu beiden. Der Drawdown trägt `peak_date`,
  `trough_date` und `recovery_date` (`null`, solange die Reihe unter dem Hoch
  liegt; alle drei `null`, wenn der Drawdown genau `0` ist: es gab keinen
  Rückgang, also wird keiner datiert). Optionales `as_of` (ISO-Datum, Standard heute) begrenzt die Reihe:
  Schlusskurse danach werden nicht gelesen. Ein unbekanntes Wertpapier ist
  `404`, ein ungültiges `as_of` ist `422`.

**Die Reihe ist die des Wertpapiers selbst.** Gelesen werden die gespeicherten
Schlusskurse in der Anzeigebasis nach ADR-0028 §2 (splitbereinigt beim Lesen;
die gespeicherten Zeilen bleiben unverändert) und in der **eigenen Währung**
des Wertpapiers — bewusst *nicht* in die Basiswährung umgerechnet, denn eine
Preiskennzahl ist eine Aussage über das Instrument, und eine Umrechnung würde
den Wechselkurspfad hineinfalten.

**Eine Lücke erzeugt keine Beobachtung, niemals eine Null.** Renditen werden
zwischen aufeinanderfolgenden gespeicherten Schlusskursen gebildet; ein Tag
ohne Kurs wird nicht fortgeschrieben und anschließend differenziert. Jede
Kennzahl trägt daher ihre `observations` und das `window`, über das sie
gemessen wurde, und die Antwort trägt einmal `computation_basis`
(`input_series`, `window`, `reference`, `gaps`, `assumptions`).

**Unterhalb ihres Minimums verweigert eine Kennzahl.** `value` ist `null` mit
`insufficient_data: true` und der vorhandenen Beobachtungszahl, bei `200` —
eine Lückenmarkierung, kein Fehler. Eine Volatilität, deren Quadratwurzel
jenseits dessen liegt, was der eine Gleitkommaschritt tragen kann — eine
Größenordnung, die nur unplausible gespeicherte Schlusskurse erreichen —, ist
`null` **ohne** `insufficient_data`: undefiniert, nicht zu wenige Daten, und
nie ein Fehler.

**Jede Kennzahl sagt, was sie gebraucht hätte** (ADR-0047 §6, ergänzt am
2026-09-19): `required` trägt die Mindestzahl an `observations` auf **jeder**
Kennzahl, ob berechnet oder verweigert — `n` für `sma_n`, `20` für
`volatility`, `2` für `max_drawdown` und `momentum`, `1` für
`distance_to_extremes`. Für Momentum und Extremwerte ist die Zahl nur die
Untergrenze; die Abdeckungsregel (ein Kurs an jedem Ende des Fensters) bleibt
in `computation_basis.gaps`. Ein verweigerter `sma_n` trägt `window: null`,
weil seine Spanne erst aus den jüngsten `n` Kursen entsteht.

Die Volatilität ist die
**Grundgesamtheits**-Standardabweichung der einfachen Tagesrenditen des
Fensters, annualisiert mit `√252`; Abstände, Momentum und Volatilität sind
Verhältniszahlen statt Prozentwerte (`0.05` ist +5 %), gerundet auf sechs
Nachkommastellen.

**Diese Fläche berichtet, sie bewertet nicht.** Es gibt kein Signal, keine
Empfehlung, kein Rating, keinen Score und keine Handlung in der Antwort. Eine
Regel über einer Kennzahl ist FR-43 und bleibt verschlossen.

### Crash-Fenster (ADR-0058)

Ein Crash-Fenster ist ein Rückgang um 10 % oder mehr in den gespeicherten
Schlusskursen des **Crash-Benchmarks** (`PUT /api/v1/settings/crash_benchmark`,
unten unter Einstellungen), von der Regel `peak_trough_v1` beim Lesen erkannt
und nie gespeichert, oder ein **manuelles** Fenster, das eine Person gezogen
hat. Der Betreiber oder ein Agent benennt ein erkanntes Fenster nur; seine
Daten sind die der Regel, sodass jeder Agent und der Bildschirm dieselben
Fenster lesen. Je Fenster vergleichen drei Ranglisten die Kursbewegungen der
Wertpapiere darin. Stufen (a) und (b) der Leiter: eine abgeleitete Bewegung
je Wertpapier und ein Vergleich mit einem Benchmark, nie das Nachspielen
einer Regel (ADR-0058 §8). Jede Antwort sind Daten, nie ein Rat: Kein
Schlüssel sagt, was zu kaufen, zu verkaufen oder zu halten ist, und
`metrics_carry_no_verdict_test.exs` durchläuft diese Antworten.

**Die Regel.** Über den gespeicherten Schlusskursen des Crash-Benchmarks in
seiner eigenen Währung, in der aktuellen Darstellungsbasis (ein gebuchter
Split ist kein Fall), nur positive Kurse, ein Tag ohne Kurs übersprungen und
nie interpoliert: Der Lauf führt das laufende Hoch (unter gleichen Hochs das
**späteste**, sodass ein Fenster am letzten Tag am Hoch beginnt); ein Fenster
öffnet beim ersten Kurs, für den `(peak − close) / peak ≥ 0.10` gilt, exakt
in `Decimal` verglichen (ein Rückgang um genau 10,00 % öffnet eines, 9,99 %
nicht); sein Tiefpunkt ist der niedrigste Kurs, bevor die Reihe zum ersten
Mal wieder auf oder über dem Hoch schließt (unter gleichen Tiefs das
**früheste**); es schließt mit diesem ersten Kurs (`recovered_on`), und der
Lauf geht von dort weiter, sodass erkannte Fenster sich nie überlappen. Ein
Fenster, das bis zum letzten Kurs nicht erholt ist, ist **vorläufig**
(`provisional`): Sein Tiefpunkt ist der niedrigste Kurs bisher und wandert,
solange die Kurse weiter fallen. Die Schwelle ist fest: `threshold` `"0.10"`.

**Schlüssel.** Ein erkanntes Fenster ist `d:<benchmark_security_id>:<start>`
(das Datum seines Hochs, ISO 8601), stabil, solange die Kurse des Benchmarks
vor dem Fall es sind; ein manuelles Fenster ist `m:<id>`. Ein Schlüssel wird
genau so geschrieben, wie der Lesezugriff ihn schreibt: eine führende Null,
ein kurzes Datum oder ein anderes Präfix nennt nichts und ergibt `404`.

Jede Route verlangt den Bearer-Token: Ohne gültigen ergibt sie `401` wie
jede Route unter `/api/v1` (siehe Authentifizierung). Jeder Lese- und
Schreibzugriff ist geschlossen: ein Parameter oder Feld, das er nicht nimmt,
ergibt `422`, das es nennt (`"is unknown: …"` und die Felder, die er nimmt),
nie stillschweigend verworfen. Jeder Schreibzugriff wird unter dem Token
journalisiert (`resource_type` `crash_window_name` für einen Namen,
`crash_manual_window` für ein manuelles Fenster, mit Vorher-Abbild bei einer
Änderung oder einem Löschen). Bei einer Ablehnung wird nichts geschrieben.

**`GET /api/v1/crashes`**

Die Fenster, wie jeder Leser sie liest. Er nimmt keinen Parameter (jeder
ergibt `422`, das ihn nennt). `data` trägt:

- `benchmark` — der Crash-Benchmark: `{id, name, isin, currency_code,
  benchmark_security}` (`benchmark_security` ist `flagged`, `held` oder
  `unheld`, wie das Schreiben der Einstellung es liefert), oder `null`.
- `reason` — `null`, oder warum nichts erkannt wird: `no_crash_benchmark`
  (keiner gewählt: `detected` ist `[]`, manuelle Fenster gelten trotzdem)
  oder `crash_benchmark_unavailable` (das gewählte Wertpapier wurde seither
  wegfusioniert; sein Überlebender wird nie geraten übernommen).
- `detected` — der früheste Start zuerst, je mit `key`, `kind` `detected`,
  `name` (`null`, solange unbenannt), `start` (das Datum des Hochs),
  `peak_close`, `trough`, `trough_close`, `decline` (der Fall vom Hoch zum
  Tiefpunkt als Bruch, negativ; die Kurse und der Rückgang als
  Dezimal-Strings in der eigenen Währung des Benchmarks), `recovered_on`
  (`null`, solange es läuft), `provisional` und `max_gap_days`, der längste
  Abstand in Kalendertagen zwischen zwei aufeinanderfolgenden Kursen vom
  Start bis zur Erholung (oder, solange vorläufig, bis zum letzten Kurs),
  sodass ein Fenster über einer veralteten Strecke als solches lesbar ist.
- `manual` — der früheste Start zuerst, je mit `key` `m:<id>`, `kind`
  `manual`, `id`, `name`, `start`, `trough`, `author` (`operator` oder
  `agent`, aus der anlegenden Berechtigung), `actor` (der Name des
  anlegenden Tokens), `created_at` und `updated_at`. Gelistet, ob ein
  Crash-Benchmark gewählt ist oder nicht. Seine Daten hat eine Person
  gewählt, die das Ergebnis gekannt haben kann; `kind` sagt es bei jedem
  Lesen.
- `unmatched_names` — die gespeicherten Namen, deren Schlüssel zu keinem
  jetzt erkannten Fenster passt, der früheste Start zuerst, je mit ihrem
  gespeicherten `key`, `name`, `benchmark_security_id`, `benchmark_name`
  (`null`, wenn das Wertpapier fort ist), `start` und
  `for_current_benchmark`: `true`, wenn er für den jetzt gewählten
  Crash-Benchmark vergeben wurde (die Kurse haben sich geändert, und sein
  Fenster hat sich verschoben oder ist verschwunden), `false`, wenn für einen
  anderen (wird jener wieder gewählt, kehrt er zurück). Ein Name wird nie
  geraten einem anderen Fenster zugeordnet (ADR-0058 §3).
- `computation_basis` — die der Regel: `rule` (`peak_trough_v1`),
  `threshold` (`"0.10"`), `comparison`, `peak_ties`, `trough_ties`,
  `input_series`, `currency` (die des Benchmarks, oder `null`),
  `currency_note`, `split_adjustment`, `gaps` und `recovery`.

**`GET /api/v1/crashes/:key/rankings`**

Eine Liste des Fensters `key`, beim Lesen abgeleitet und nie gespeichert.
Query-Parameter, jeder optional:

- `list` — `losers` (Vorgabe), `winners` oder `rebounders`;
- `universe` — `catalogue` (Vorgabe): jedes Wertpapier im Katalog, nicht
  wegfusioniert und nicht mit `is_benchmark` markiert, ohne den
  Crash-Benchmark selbst; oder `view:<id>`: davon die Wertpapiere, die die
  Ansicht **heute** hält (eine Position in einem Depot der Ansicht, deren
  Menge über diese Depots summiert nicht null ist). Heute gehalten, nicht zu
  den Daten des Fensters;
- `limit` — Vorgabe 8, eine positive ganze Zahl; über 50 wird sie bei 50
  gekappt, und das `limit` der Antwort sagt es;
- `include_unanswered` — `true` fügt `unanswered_entries` hinzu; `false`
  oder fehlend lässt sie weg.

**Verlierer und Gewinner** ordnen die **EUR-Kursrendite jedes Wertpapiers
von `start` bis `trough`** mit der Fensterrendite-Funktion, die auch der
Verkaufsrückblick und die Auflösung der Prognosen nutzen, sodass eine
Crash-Rendite und die Rückblick-Rendite eines Verkaufs über dieselben Daten
bis auf die letzte Stelle übereinstimmen: Der Kurs, der für ein Datum steht,
ist der letzte positive gespeicherte Kurs an oder vor ihm, höchstens 7
Kalendertage älter (`staleness_days`), in der Darstellungsbasis, jeder zum
gespeicherten EUR-Hub-Kurs seines eigenen Datums umgerechnet, eine Division.
Verlierer kommen niedrigste zuerst, Gewinner höchste zuerst; die
Gewinnerliste behält negative Renditen mit ihrem Vorzeichen, wenn wenige
Wertpapiere stiegen. Eine Kursrendite: Ausschüttungen zählen nicht.

**Erholer** ordnen den Anstieg jedes Wertpapiers von seinem **eigenen
Tief** — seinem niedrigsten Kurs an einem Tag von `start` bis `trough`, unter
gleichen Tiefs das früheste — bis zum Ende der **Erholungsspanne**, `trough`
plus drei Kalendermonate (ein Tag, den der Monat nicht hat, wird sein letzter
Tag: der 30. November endet am 28. Februar; `recovery_span_months` `3`), in
EUR mit derselben Funktion, höchster zuerst. Daneben: `days_back`, die
**Kalendertage** (`days_back_unit` `calendar_days`, F3 des Nachtrags:
Handelstage unterscheiden sich je Börse) von seinem eigenen Tief bis zu
seinem ersten Kurs auf oder über seinem Kurs, der für `start` steht, `0`,
wenn das Tief nicht darunter liegt, oder `null` mit `not_yet` `true`, wenn
kein Kurs bis heute ihn erreicht.

**Gleichstände** in einer Liste: nach der Zahl, dann nach dem Namen des
Wertpapiers ohne Groß- und Kleinschreibung, seiner ISIN, seinem Ticker, seiner
WKN und seiner Währung (eines ohne nach denen mit). Einträge, die in allen
diesen gleich sind, teilen sich einen `rank` und stehen untereinander in der
Reihenfolge, in der die Wertpapiere angelegt wurden; eine id entscheidet
keinen Rang (ADR-0058 §5, Ergänzung vom 2026-11-12, Teil 2).

`data` trägt:

- `window` — `{key, kind, name, start, trough, provisional, recovered_on,
  max_gap_days}` (die letzten beiden `null` bei einem manuellen Fenster);
- `list`, `universe` und `limit`, zurückgegeben;
- die gemessenen Daten: `from` und `to` bei Verlierern und Gewinnern (`start`
  und `trough` des Fensters); `low_from`, `low_to` (die Tage, aus denen ein
  eigenes Tief gelesen wird), `span_end` (der Tiefpunkt plus drei Monate) und
  `measured_to` bei Erholern;
- `provisional` — `true`, solange das Fenster nicht erholt ist (sein
  Tiefpunkt und damit jede Liste wandert mit), und bei Erholern auch, solange
  die Erholungsspanne nicht vorbei ist: Die Liste ist dann bis heute gemessen
  (`measured_to`), und `completes_on` nennt den Tag, an dem die Spanne endet
  (`null`, solange das Fenster noch fällt, weil dieser Tag noch nicht
  feststeht). Eine Erholung wird nie über eine kürzere Spanne als die
  genannte geordnet, ohne dass es gesagt wird;
- `benchmark` — der Crash-Benchmark `{id, name, isin, currency_code,
  benchmark_security}`, oder `null`;
- `reference` — der Crash-Benchmark, mit derselben Regel und Funktion
  gemessen wie jeder Eintrag (über dieselben Daten bei Verlierern und
  Gewinnern, von seinem eigenen Tief bei Erholern): `{security_id, return,
  start, end}`, bei Erholern mit `low`; oder `null`, und `reference_reason`
  sagt warum: `no_crash_benchmark`, `crash_benchmark_unavailable`,
  `no_benchmark_close` oder `no_fx_rate`;
- `entries` — höchstens `limit`, je mit `rank` (ab 1; in jedem Schlüssel
  gleiche Einträge teilen ihn, der nächste nimmt seine Position), `security` (`{id,
  name, isin, currency_code}`), `held` (`true`, wenn ein Depot es heute hält,
  sodass eine Katalogliste es markieren kann), `return`, `start` und `end`
  (je Kurs: `stands_for`, `date`, `close`, `stored_close`, `source`,
  `fx_rate`, `eur_value`), `benchmark_return` und `vs_benchmark_pp`, die
  Differenz `(return − benchmark_return) × 100` in Prozentpunkten,
  ungerundet; bei Erholern auch `low` (`{date, close}`), `start_close`
  (`{stands_for, date, close}`), `back_on`, `days_back` und `not_yet`. Jede
  Zahl ist ein Dezimal-String;
- `answered` — wie viele Wertpapiere des Universums eine Antwort haben;
- `unanswered` — die übrigen nach Grund gezählt, jeder Schlüssel immer
  vorhanden: `no_close_at_start` (kein Kurs, der für den Start steht; bei
  einem Erholer auch keiner von Start bis Tiefpunkt), `no_close_at_end`
  (keiner innerhalb von 7 Tagen vor dem Ende, oder ein Wertpapier, das
  jünger ist als das Fenster) und `no_fx_rate` (ein Kurs ohne gespeicherten
  Kursweg nach EUR). Ein Wertpapier ohne Antwort steht in keiner Liste und
  wird nie als Null geordnet;
- `unanswered_entries` — nur mit `include_unanswered=true`: je `{security,
  held, reason}`, in der obigen Gleichstandsordnung;
- `computation_basis` — `benchmark`, `reason`, `reference`, `window`,
  `rule` und `threshold` (`null` bei einem manuellen Fenster), `dates` (die
  der Regel, oder von einer Person gewählt), `universe`, `list`, `figure`,
  `input_series`, `currency` (`EUR`), `detection_currency`, `currency_note`,
  `close_lookup`, `staleness_days` (`7`), `split_adjustment`, `fx`,
  `recovery_span_months`, `recovery_span`, `days_back_unit`, `days_back`,
  `gaps`, `ties`, `provisional` und `survivorship`.

**Ohne Crash-Benchmark** (F2 des Nachtrags) antworten die Listen eines
manuellen Fensters ohne Referenz: `benchmark` und `reference` sind `null`,
`reference_reason` ist `no_crash_benchmark`, `benchmark_return` und
`vs_benchmark_pp` jedes Eintrags sind `null`, und die Basis sagt
`benchmark: null` mit `reason`. Die Rangfolge bleibt dieselbe: Ein
manuelles Fenster ist die eigene Spanne des Betreibers, und die Wertpapiere
darin zu ordnen braucht keine Marktlinie.

**Survivorship.** Der Katalog hält, was noch geführt wird: ein Wertpapier,
das scheiterte und entfernt wurde, steht in keiner Liste, sodass die Listen
besser aussehen als der Markt war, und die Erholer am meisten.
`computation_basis.survivorship` sagt es in jeder Antwort.

Ablehnungen, jede bevor etwas gelesen wird: eine `list` außer den dreien
ergibt `422` mit `errors.list` `["is invalid: losers, winners or
rebounders"]`; ein `universe` außer `catalogue` oder `view:<id>` (eine
führende Null oder ein Vorzeichen eingeschlossen) `errors.universe` `["is
invalid: catalogue or view:<id>"]`; ein `limit` von null, negativ oder keine
Zahl `errors.limit` `["is invalid: a positive integer, at most 50"]`; ein
`include_unanswered` außer `true` oder `false` `errors.include_unanswered`
`["is invalid: true or false"]`; jeder andere Parameter `422`, das ihn nennt.
Ein Schlüssel, der kein jetzt erkanntes und kein manuelles Fenster nennt,
ergibt `404`, ebenso ein `view:<id>`, dessen Ansicht es nicht gibt.

**`PUT /api/v1/crashes/:key`**

Body `{"window": {...}}`. Bei einem erkannten Schlüssel (`d:`) benennt er das
Fenster oder benennt es um: der Body nimmt nur `name` (höchstens 80 Zeichen,
die Textregeln von ADR-0054 §4, Pflicht). Der Schlüssel muss ein Fenster
nennen, das die Regel jetzt über dem aktuellen Crash-Benchmark erkennt; ein
Name wird nie einem Fenster gegeben, das niemand lesen kann. Ein Name
verschiebt nie die Daten des Fensters. Bei einem manuellen Schlüssel (`m:`)
ändert er das Fenster: beliebige von `name`, `start` und `trough`, am
geänderten Fenster nach den Regeln von `POST` geprüft; der anlegende Token
bleibt der des Anlegers. Die Antwort ist das geschriebene Fenster: bei einem
Namen `{key, kind: "detected", name, benchmark_security_id, start}`, bei
einem manuellen Fenster die Form, die `manual` liest.

Ablehnungen: Ein Schlüssel, der weder `d:` noch `m:` ist, ein erkannter
Schlüssel, der kein jetzt erkanntes Fenster nennt, oder ein manueller, der
kein manuelles Fenster nennt, ergibt `404`; ein Feld, das die Art des
Schlüssels nicht nimmt (`start` bei einem erkannten Schlüssel), ergibt `422`,
das es nennt; ein leerer oder zu langer `name` (oder keiner, wo das Fenster
noch keinen Namen hat) oder ein Datum, das nach den Regeln von `POST`
abgelehnt wird, `422`, das das Feld nennt; ein `window`, das kein JSON-Objekt
ist, `422`, das `window` nennt.

**`POST /api/v1/crashes`**

Body `{"window": {"name", "start", "trough"}}` zieht ein **manuelles
Fenster** (`201`): `name` höchstens 80 Zeichen, die Textregeln von ADR-0054
§4; `start` und `trough` ISO-Kalenderdaten, der Tiefpunkt nach dem Start
(`errors.trough` `["must be after start"]`), keiner in der Zukunft (`["must
not be in the future"]`), jedes Pflicht. Es darf ein erkanntes oder ein
anderes manuelles Fenster überlappen: Ein manuelles Fenster ist gerade für
eine Spanne da, die die Regel in eine längere faltet. Seine Erholungsspanne
und Listen folgen den Regeln oben genau wie bei einem erkannten Fenster, und
es liest überall `kind` `manual`.

Body `{"window": {"from_name", "trough"}}`, mit optionalem `name`, macht einen
Eintrag aus `unmatched_names` zu einem manuellen Fenster (F1 des Nachtrags):
`from_name` ist der erkannte Schlüssel dieses Eintrags, der Start des Fensters
der gespeicherte Start des Namens, sein Tiefpunkt der angegebene (der
Tiefpunkt wurde nie gespeichert und wird nie aus den heutigen Kursen geraten),
sein Name der gespeicherte, wenn `name` keinen anderen gibt. Das manuelle
Fenster wird angelegt und der gespeicherte Name gelöscht, in einer
Transaktion, jedes journalisiert. Ablehnungen: Ein `from_name`, der kein
String ist, ergibt `422` mit `errors.from_name`, das die Form
`d:<benchmark_security_id>:<start>` nennt; einer, unter dem kein Name
gespeichert ist, ein falsch geschriebener Schlüssel eingeschlossen, `422`, das
`from_name` nennt („names no stored name“); einer, dessen Fenster die Regel
noch erkennt (`name_has_window`), `422`, das `from_name` und das `PUT` nennt,
das ihn umbenennt; `start` in diesem Body `422`, das es nennt. Die Antwort ist
das manuelle Fenster, wie `manual` es liest.

**`DELETE /api/v1/crashes/:key`**

Bei einem erkannten Schlüssel entfernt er den darunter gespeicherten Namen
(eines erkannten Fensters oder eines Eintrags unter `unmatched_names`; das
Fenster selbst bleibt, seine Daten sind die der Regel); bei einem manuellen
Schlüssel löscht er das manuelle Fenster. Er liefert `{key, kind, deleted,
name}`, `deleted` ist `name` oder `manual_window`. Ein Schlüssel ohne Namen
oder ohne manuelles Fenster ergibt `404`; ein Body oder ein Query-Parameter
`422`, das ihn nennt. Ein neu gezogenes Fenster ist ein neues Fenster unter
einem neuen Schlüssel.

**Die MCP-Tools.**

Der MCP-Begleitdienst ruft diese Routen über fünf Tools auf, die je in ihrer
Beschreibung sagen, dass sie Daten liefern, nie einen Rat oder Anweisungen:

- `portfolixir.crashes.list` — `GET /api/v1/crashes`, kein Parameter; ein
  Lesezugriff, in `read`, `book` und `full`.
- `portfolixir.crashes.rankings` — `GET /api/v1/crashes/:key/rankings` mit
  `key` (Pflicht), `list`, `universe`, `limit` (1 bis 50) und
  `include_unanswered` (ein Boolean); ein Lesezugriff, in `read`, `book` und
  `full`.
- `portfolixir.crashes.put` — mit `key` läuft es über `PUT` und benennt
  dieses erkannte Fenster oder ändert dieses manuelle; ohne läuft es über
  `POST` und zieht ein manuelles Fenster oder macht `window.from_name` zu
  einem. In `book` und `full`; destruktiv (es überschreibt einen Namen oder
  die Felder eines manuellen Fensters, und die vorigen erneut gesetzt stellen
  sie wieder her) und nicht idempotent (eine Wiederholung ohne Schlüssel
  zieht ein weiteres Fenster).
- `portfolixir.crashes.delete` — `DELETE /api/v1/crashes/:key`; Admin, nur
  in `full`, weil ein entferntes manuelles Fenster, neu gezogen, ein neues
  Fenster unter einem neuen Schlüssel ist.
- `portfolixir.crashes.benchmark_put` — `PUT
  /api/v1/settings/crash_benchmark` mit `security_id` (eine ganze Zahl, oder
  `null` zum Zurücksetzen); in `book` und `full`, und den vorigen Benchmark
  erneut zu setzen stellt ihn und die für ihn vergebenen Namen wieder her.

Jedes Tool prüft sein Schema vor jeder Anfrage: Ein Schlüssel, auf den das
Muster des Begleitdienstes nicht passt, eine `list` oder ein `universe`
außerhalb ihrer Werte oder ein Feld, das das Tool nicht nimmt, wird dort
abgelehnt, mit Namen.

### Das Positionsdossier (FR-49)

Ein Lesezugriff je Wertpapier, der trägt, was ein Agent für eine Entscheidung
über eine Position sonst aus acht Lesezugriffen zusammensetzt. Hier wird
nichts berechnet: Jeder Teil entsteht aus der Funktion, die sein eigener
Lesezugriff nutzt, und trägt dessen Berechnungsgrundlage oder Hinweis, sodass
ein Teil immer gleich dem ist, was sein Lesezugriff antwortet.

- `GET /api/v1/securities/:id/dossier` (`portfolixir.securities.dossier`, in
  jedem Profil) — nur lesend, ohne Parameter. Die
  Antwort trägt `security_id`, `as_of` (heute), `parts` (je Teil der
  Lesezugriff, den er spiegelt) und acht Teile:
  - `security` — der Datensatz, den `GET /api/v1/securities/:id` antwortet,
    samt früheren ISINs, `thesis_state` und `bond` mit seiner Grundlage;
  - `holdings` — `rows`, eine Zeile je Depot, das das Wertpapier hält, über
    alle Portfolios hinweg, so wie
    `GET /api/v1/portfolios/:portfolio_id/holdings?security_id=:id` sie
    antwortet, mit `currency_basis`, `currency_basis_note` und
    `computation_basis` dieses Lesezugriffs; `total`, die Zeile des
    Wertpapiers aus `GET /api/v1/holdings/by_security` (EUR, `valued`,
    `unvalued_reason`), `null`, wenn nichts gehalten wird, mit `total_basis`
    (`currency`, `note`);
  - `metrics` — `GET /api/v1/securities/:security_id/metrics` mit seinem
    voreingestellten `as_of`, samt `computation_basis`;
  - `research` — die 5 neuesten Einträge des Research-Logs, so wie
    `GET /api/v1/securities/:security_id/notes?limit=5` sie antwortet, mit
    `has_more`, der `log_note` und `rest`, dem Lesezugriff, der den Rest
    blättert;
  - `events` — `upcoming`, jeder Termin, dessen letzter möglicher Tag heute
    oder später liegt, der früheste zuerst, und `past`, die 5 neuesten
    übrigen, der neueste zuerst, beide aus
    `GET /api/v1/securities/:security_id/events`, mit `has_more`, der
    `events_note` und `rest`;
  - `categories` — eine Zeile je Klassifizierung aus
    `GET /api/v1/classifications` (`classification_id`, `classification_name`,
    `classification_key`, `built_in`) mit `category` (`id`, `name`, `key`
    und `path`, die Kategorien von der Wurzel bis zu ihr), `null`, wo das
    Wertpapier nicht eingeordnet ist;
  - `targets` — `rows`, die Positionsziel-Zeilen aus
    `GET /api/v1/portfolios/:portfolio_id/position_targets`, die das
    Wertpapier nennen, je Portfolio, im aktiven Plan der View-losen Sicht
    (den Plan einer View liest derselbe Lesezugriff mit `view=`; das sagt
    auch `parts.targets`), und `drift`, das den Lesezugriff nennt, der die Abweichung jeder Zeile
    angibt: Das Dossier berechnet keine;
  - `news` (ADR-0056 §9) — `count_7d`, die Storys des
    Wertpapiers, bei denen ein Mitglied in den letzten 7 Tagen in ihren
    Bereich kam (wie `GET /api/v1/news/stories?security_id=:id&since=` 7
    Tage zurück sie listet), `primary_7d`, die davon mit der besten Stufe
    `primary`, `max_materiality`, die höchste Materialität ihrer aktiven
    Labels der neuesten Prompt-Version (`null` ohne eines), und
    `newest_primary`, die neueste primäre Story des Wertpapiers, gleich wie
    alt (`id`, `title` auf 50 Zeichen gekürzt, `at`; `null` ohne eine). Etwa
    50 Token; der Begleiter antwortet das Dossier als kompaktes JSON, wie
    die News-Lesezugriffe.

Bewusst ausgelassen: Kurse, Trades, Lots und Transaktionen, jeweils eine lange
Reihe mit eigenem geblättertem Lesezugriff, und die Abweichung, die je
Portfolio eine Klassifizierung und eine Bewertung braucht. Ein Wertpapier, zu
dem nichts erfasst ist, antwortet jeden Teil leer mit `200`. Ein in ein
anderes zusammengeführtes Wertpapier antwortet `404` mit `errors.merged_into`
(`kind`, `id`), wie `GET /api/v1/securities/:id`; eine unbekannte ID antwortet
das schlichte `404`. Die menschliche Ansicht ist die Wertpapierseite für jeden
Teil außer `targets`, dessen Ansicht die Klassifizierungsseite ist.

### Anleihen: Stammdaten und Anleihe-Lesung (ADR-0052)

Die Stammdaten einer Anleihe sind sechs nullbare Felder des Wertpapiers,
setzbar mit `POST /api/v1/securities` und `PATCH /api/v1/securities/:id`,
in jeder Wertpapier-Antwort enthalten (und mit `fields=` wählbar):

- `coupon_rate` — der Kupon in **Prozent vom Nennwert pro Jahr**, ein
  Decimal-String von 0 bis 100 (`"2.5"`, nicht `"0.025"`);
- `coupon_frequency` — `annual` oder `semi_annual`;
- `maturity_date` und `issue_date` — ISO-Daten, die Fälligkeit nach dem
  Emissionstag;
- `face_value` — die Stückelung, ein Decimal-String über 0;
- `face_value_currency_code` — die Währung der Stückelung, ein ISO-4217-Code
  aus der Menge, die `currency_code` annimmt.

`coupon_rate` und `face_value` halten 6 Nachkommastellen, nach der Regel,
der jeder gespeicherte Betrag folgt (**Andere gespeicherte Beträge** oben):
Ein feinerer Wert wird vor der Prüfung kaufmännisch gerundet, `"3.1234567"`
wird also als `"3.123457"` gespeichert und gemeldet. Gesendet werden sie als
Strings, wie jedes Decimal; eine JSON-Zahl liefert `422` mit dem Namen des
Felds (**Decimal-Strings beim Schreiben** oben).

`null` löscht ein Feld, Pflicht ist keines, ein unmöglicher Wert ist ein
`422`, der sein Feld nennt, ohne dass etwas geschrieben wird, und die Felder
bleiben erhalten, wenn die Anlageklasse wechselt. Gelesen werden sie,
solange die effektive Anlageklasse `bond` oder `government_bond` ist, und —
seit Issue #1068 — solange das Wertpapier **keine** Anlageklasse hat, weder
gespeichert noch abgeleitet (sein `asset_class` ist `null`, und die Namens-
und Logo-Regeln leiten keine ab), ein `maturity_date` oder eine
`coupon_rate` trägt und einen Namen hat, den die Inferenz nicht als
strukturiertes Produkt liest: Die Namensinferenz erkennt Namen von
Staatsanleihen und, seit Issue #1127, die ausdrücklichen Anleihe-Wörter
(Anleihe, Schuldverschreibung, Pfandbrief, Notes, Obligation), also macht
erst dieser Stammdatensatz eine Unternehmensanleihe ohne ein solches Wort
und ohne Klasse als Anleihe kenntlich. Ein Wertpapier mit einer anderen
Klasse, gespeichert oder abgeleitet, ist keine Anleihe, welche Stammdaten es
auch trägt; eine Anleihe, deren Name die Rechtsform ihres Emittenten und
kein Anleihe-Wort trägt, wird beim Anlegen als `equity` gespeichert, ebenso
eine mit Anleihe-Wort, die vor Issue #1127 gespeichert wurde, und braucht
`asset_class` `bond`. Die MCP-Tools `portfolixir.securities.create` und
`portfolixir.securities.update` nehmen sie entgegen (das Update auch
`null`).

`GET /api/v1/securities/:id` eines solchen Wertpapiers trägt `bond`, beim
Lesen berechnet und nie gespeichert (Stufe (a) der Scope-Leiter); für jedes
andere Wertpapier und in Listen und Schreibantworten ist es `null`:

- `as_of` und `quantity` (die gehaltenen Stück über alle Depots);
- `nominal_held` — `amount`, **Stück × 100**, in `currency_code` (der des
  Nennwerts, sonst der des Wertpapiers): Ein Portfolio-Performance-Export
  bucht die Stückzahl einer prozentnotierten Anleihe als **ein Hundertstel
  des Nominals**, darum ist ein Kurs zugleich Prozent vom Nennwert und Preis
  je Stück;
- `remaining_term` — `days` von `as_of` bis zur Fälligkeit, `years` (Tage ÷
  365, kaufmännisch auf sechs Nachkommastellen gerundet), `whole_years` und
  `whole_months`, `matured` ab dem Fälligkeitstag;
- `current_yield` — Kupon ÷ Kurs, und `yield_to_maturity` — die **lineare
  Näherung** (Kupon + (100 − Kurs) ÷ Restlaufzeit in Jahren) ÷ Kurs, ohne
  Zinseszins; jeweils eine Verhältniszahl, kaufmännisch auf sechs
  Nachkommastellen gerundet (`0.025707` ist 2,5707 %) und wie jedes Decimal
  ohne nachgestellte Nullen gesendet (`"0.03685"`, `"0"`), mit dem
  verwendeten `price` (`value`, `date`,
  `source`: `quote` für den letzten gespeicherten Kurs, `trade` für den
  letzten eigenen Handelspreis, solange es keinen gibt);
- `two_scales` — `null` oder der Befund, dass die Anleihe **auf zwei Skalen
  bepreist** ist: ihre `direction`, ihr `latest_quote`, die Zahl der
  `unit_scale_bookings` und die `last_unit_scale_booking` sowie die `rule`.
  - `direction: "forward"` — ein letzter Kurs vom 20- bis 500-Fachen eines
    gebuchten Preises je Stück (eines Kaufs oder einer mit Preis erfassten
    Einlieferung): Kurse um 100 neben Buchungen um 1. Jeder Geldbetrag
    einer solchen Anleihe ist hundertfach zu hoch, und die TTWROR zeigt es
    nicht.
  - `direction: "reverse"` (Issue #1068) — ein letzter Kurs von 1/500 bis
    1/20 eines gebuchten Preises je Stück, beide Enden eingeschlossen, und
    selbst höchstens 5: Kurse um 1 neben Buchungen um 100. Die gespeicherten Kurse sind kein Prozent
    vom Nennwert, und die Anleihe zählt hundertfach zu niedrig in jeder
    Summe.

  Die beiden Buchungsschlüssel behalten in beiden Richtungen ihre Namen und
  enthalten die Buchungen im Band; liegen Buchungen einer Anleihe in beiden
  Bändern, wird der Befund `forward` gemeldet. Die `rule` nennt beide Bänder
  und welche Wertpapiere als Anleihe gelesen werden. Umgerechnet wird
  nichts, in keiner Richtung.

Jede Kennzahl trägt ihre eigene `computation_basis` (`input_series`,
`window`, `reference`, `gaps`, `assumptions`). Eine Zahl ohne ihren Eingang
ist `null` mit `insufficient_data: true` und den fehlenden Eingängen in
`missing` (`coupon_rate`, `maturity_date`, `price`); die Renditen einer
fälligen Anleihe sind `null` mit `matured: true`. Eine Rendite, deren Kurs
der letzte eigene Handelspreis von **höchstens 5** ist — das Spiegelbild
des Zwei-Skalen-Bands, 100 ÷ 20, der Preis je Stück einer Buchung, die das
Nominal als Stückzahl erfasst hat —, ist `null` mit
`price_on_unit_scale: true`, weder `insufficient_data` noch `matured`: Ein
solcher Preis ist kein Prozent vom Nennwert, Kupon ÷ Kurs wäre also keine
Rendite. Ein gespeicherter Kurs ist in jeder Höhe ein Prozentkurs und wird
immer verwendet; bei jeder anderen Rendite ist `price_on_unit_scale`
`false`. Stückzinsen, Gebühren und Steuern sind nicht enthalten; die Lesung
berichtet, sie bewertet nicht.

### News-Pflege (ADR-0056)

Die News-Schicht (ADR-0056) ruft registrierte Feeds ab, ordnet jeden
Eintrag nach Regel einem Wertpapier oder einer Kategorie zu, bündelt
Dubletten zu Storys und liefert sie knapp; ein Modell außerhalb der App
kann die Storys einordnen. Ihre Oberfläche hat vier Teile: die
Pflege-Schreibzugriffe hier, die [Lesezugriffe](#news-lesezugriffe-adr-0056),
[Lese- und Schreibzugriff des Labellers](#news-labels-adr-0056-7) und den
Schritt von der Story zum Wissen, nämlich `notes.append` mit einer
`cluster_id` im [Research-Log](#research-log-adr-0044), `news_id` an einem
[Wertpapier-Termin](#wertpapier-termine-adr-0048) und den News-Block des
[Dossiers](#das-positionsdossier-fr-49). Die menschliche Sicht ist die Seite
Nachrichten und der Reiter Nachrichten jedes Wertpapiers
([Produktdokumentation](../product-documentation.html#nachrichten)): Jeder
Bereich liest, was der Lesezugriff derselben Anfrage antwortet; der einzige
Schreibzugriff der Seite ist die Zuordnung unten, der des Reiters ein
Research-Eintrag aus einer Story; Feeds und Quellen werden nur hier
angelegt, geändert und entfernt, und die Seite zeigt sie.

Die Schreibzugriffe, die die News-Schicht pflegen (§9, B1). Jeder wird unter
dem aufrufenden Token journalisiert und ist geschlossen: Ein Feld, das er
nicht nimmt, ergibt `422`, das es nennt. Die Antworten sind knapp: kurze
Codes, leere Felder weggelassen.

- `PUT /api/v1/news/feeds` registriert oder ändert einen Feed aus einem
  `feed`-Objekt: `class` (`issuer`, `regulatory`, `aggregator`, `thematic`),
  `url`, `security_id` (issuer und regulatory) oder `category_id` (thematic;
  ein Aggregator bindet an keins), `interval_minutes` (1 bis 1.440, sonst der
  Standard der Klasse), `language` und `enabled`. Mit `id` ändert er diesen
  Feed; ohne den unter `url` registrierten, sonst legt er einen an (`201`).
  Ein nicht gesendeter Schlüssel behält seinen gespeicherten Wert. Eine für
  den Feed neue URL wird sofort mit Namensauflösung geprüft (B2): Eine, die
  nicht https ist, einen Benutzernamen trägt, nicht auflöst oder auf eine
  private, Loopback-, Link-Local- oder reservierte Adresse auflöst, ergibt
  `422` auf `url` mit ihrem Code, etwa `url_not_allowed:private_address`.
  Klasse, Bindung (`security_id`, `category_id`) und Sprache eines Feeds mit
  gespeicherten Einträgen ändern sich nicht: `422` auf dem Feld.
- `DELETE /api/v1/news/feeds/:id` entfernt einen Feed und seine
  Tageszähler; seine Einträge bleiben, abgehängt, bis zur Aufbewahrungsfrist.
  Antwortet `id` und `items_detached`.
- `PUT /api/v1/news/sources` bewertet eine Domain von Hand aus einem
  `source`-Objekt, `domain` und `tier` (`primary`, `secondary`, `awareness`,
  `blocked`); kein späterer Seed überschreibt das. Zwei gleichzeitige
  Schreibzugriffe auf eine neue Domain landen beide, der spätere auf der
  Zeile des früheren. Ein Schreibzugriff, der die Stufe der Domain ändert,
  stuft in derselben Transaktion jeden gespeicherten Eintrag neu ein, über
  den die Zeile der Domain entscheidet (die Domain und ihre Subdomains,
  sofern keine spezifischere Zeile über sie entscheidet), auf die Stufe,
  die ihm ein Abruf jetzt gäbe, den eines Aggregators höchstens auf
  `secondary`, und der Repräsentant jeder Meldung folgt den neuen Stufen
  (ADR-0056 E1). Ein in einen Research-Eintrag übernommener Eintrag behält
  seine Stufe; `blocked` entfernt die übrigen aus ihren Meldungen, und ein
  späterer Abruf, der einen wieder listet, verwirft ihn als gesperrt. Die
  Antwort bleibt `domain`, `tier` und `set_by`; der Journaleintrag des
  Schreibzugriffs (`news_source`) trägt neben der Stufe `items_rerated`,
  `items_removed` und `items_kept_promoted`. Ein Abruf, der währenddessen
  Einträge der Domain speichert, wird entweder vom Schreibzugriff neu
  eingestuft oder liest die neue Stufe, und eine währenddessen übernommene
  Meldung behält die Stufen, mit denen sie übernommen wurde.
- `PUT /api/v1/news/items/:id/assignment` (`news.assign`) ordnet einen
  Aggregator-Eintrag von Hand zu, aus einem `assignment`-Objekt mit
  `security_id` (Pflicht); `null` gibt den Eintrag an die jetzige Antwort
  des Matchers zurück: `assigned`, wenn sein Titel ein Wertpapier nennt,
  `unassigned` bei keinem, `ambiguous` mit seinen `candidates` bei mehreren.
  Der Eintrag verlässt seine Story, und die Storys des Wertpapiers, das er
  verlässt, und desjenigen, zu dem er kommt, werden in derselben Transaktion
  neu gebündelt, sodass er sofort in der richtigen Story steht; er tritt mit
  der Zuordnung in seinen neuen Bereich ein (`since` liest ihn dann). Ein
  Emittenten-, Regulierungs- oder thematischer Eintrag gehört durch
  Konstruktion seinem Feed und ergibt `422` mit `news_id`, ebenso ein im
  Research-Log behaltener Eintrag (`promoted`, die Quelle einer Notiz, die
  beim Wertpapier dieser Notiz bleibt); ein Wertpapier,
  das es nicht gibt, ergibt `422` mit `security_id`; ein unbekannter Eintrag
  `404`. Eine Zuordnung, die der Eintrag schon hat, ändert und protokolliert
  nichts. Antwortet `id`, `story_id`, `assignment`, `security_id` und
  `candidates` des Eintrags. Die `suggested_security_id` eines Labels ordnet
  nichts zu; ein nicht zugeordneter oder mehrdeutiger Eintrag steht in
  keiner Story, kein Label erreicht ihn, und seine Zeile trägt keinen
  Vorschlag (eine offene Frage der Ergänzung von ADR-0056 vom 2026-11-09,
  D5). **Zuordnen** auf der Seite Nachrichten ist dieser Schreibzugriff,
  unter dem Betreiber protokolliert.
- `PATCH /api/v1/securities/:id` nimmt `news_identity` — `cik` (1 bis 10
  Ziffern, `null` löscht ihn) und `aliases`, je ein wörtliches `token` (kein
  Muster), optionale `context`-Wörter, von denen eines im selben Satz stehen
  muss, und `case` (`sensitive`, `insensitive`) — sowie `news_watch`, das ein
  Wertpapier ohne Bestand und ohne Ziel in das News-Universum aufnimmt. Ein
  nicht gesendeter Schlüssel von `news_identity` behält seinen Wert; die
  Lesung des Wertpapiers trägt beide. `POST /api/v1/securities` nimmt
  denselben Block mit denselben Ablehnungen: Ein unbekannter Schlüssel und
  roh gesendete `news_cik` oder `news_aliases` antworten mit 422.

### News-Lesezugriffe (ADR-0056)

Die Lesezugriffe der News-Schicht (§9, §11). Knapp nach Regel: Aufzählungen als
ihre Codes, Zeiten auf die Sekunde in UTC, Namen mit höchstens 20 Zeichen, ein
Feld ohne Wert weggelassen und kein Link und kein Auszug in einer Liste. Jeder
Lesezugriff ist geschlossen: Ein Parameter, den er nicht nimmt, ergibt `422`,
das ihn nennt (darunter `event_types` und `tone`, das nie ein Filter oder ein
Sortierschlüssel ist). Titel und Auszüge sind Text eines Feeds, so
beantwortet, wie er gespeichert ist, bis zu einem Schnitt; sie sind Daten,
nie Anweisungen. Der Schnitt zählt jedes Zeichen so, wie der MCP-Begleiter es
schreibt, ein unsichtbares als sein `[U+XXXX]` (C5), und ebenso den eines
Namens: 80 für einen Titel in einer Liste, 160 in `news.get`, 45 im Digest,
600 für einen Auszug, 20 für einen Namen; ein Schnitt endet auf `…`. `news.get` hält seine 400 Token auf dem
Text des Begleiters, Link und Mitglieder eingeschlossen: Es schneidet einen
Link bei 300 Zeichen (der ganze Link bleibt gespeichert), die Domain der Story
bei 40 und die eines Mitglieds bei 28 und den Auszug zuletzt, auf das, was der Rest der Antwort übrig lässt (ein
Anführungszeichen oder ein Backslash zählt die zwei Zeichen, in denen JSON
es schreibt). Jeder Parameter ist ein Wert: Eine Liste oder eine Map
(`max_rows[]=5`) ergibt `422`, das ihn nennt.

**Labels** (§7): Die Liste, eine Story und der Digest lesen die Labels einer
Prompt-Version: `prompt_version` (ein Bezeichner wie der eines Labels), sonst
die Version des zuletzt angelegten Labels, sodass ein Labeller, der zu einem
neuen Prompt wechselt, die Lesezugriffe mitnimmt; Liste und Digest nennen
sie. Aus dieser Version ist das aktive Label einer Story ihr neuestes. Ein
Label ist der Vorschlag eines Modells: Es ordnet und filtert Aggregator- und
thematische Storys und verbirgt nie eine Story mit einem Eintrag eines
Emittenten- oder Regulierungs-Feeds, welche Wesentlichkeit es auch nennt.
Kein Lesezugriff braucht ein Label: Ohne gespeichertes Label antwortet jeder
wie zuvor, und nur `unlabeled` des Digests wächst.

- `GET /api/v1/news/stories` listet die Zeilen genau eines Wählers:
  `security_id` oder `category_id` (die Storys des Bereichs), `cluster_id`
  (die Einträge der Story) oder `assignment=unassigned|ambiguous` (die
  Aggregator-Einträge, die kein Wertpapier oder mehrere beanspruchen). Eine
  Story-Zeile ist `id`, `title` (der ihres Repräsentanten, gekürzt auf 80
  Zeichen, wie der Begleiter sie schreibt, damit eine Zeile 60 Token hält;
  die Antwort der Story kürzt bei 160), `tier`, `at` (die
  Veröffentlichung des Repräsentanten, auf seine erste Sichtung begrenzt) und
  `count`; eine Eintragszeile ist `id`, `title`, `tier`, `at`, `domain` und,
  wenn mehrdeutig, `candidates` (Wertpapier-IDs). Eine Story-Zeile mit Label
  ergänzt `materiality` und `event_type`. `fields=std` ergänzt `url`
  (bei 300 Zeichen gekürzt wie in `news.get`) und `note_ids`, bei einer Story-Zeile auch die `domain` ihres
  Repräsentanten, gekürzt auf 40 Zeichen, wie der Begleiter sie schreibt
  – die Quelle, die der Reiter „Nachrichten“ des
  Wertpapiers zeigt. Die Zeilen kommen neueste zuerst nach dem Zeitpunkt, zu dem
  sie in ihren Bereich kamen; Zeilen desselben Zeitpunkts (ein Abruf stempelt
  seine Einträge gleich) nach Stufe, primäre zuerst, dann nach neuester
  Veröffentlichung, dann nach Link, nie nach ID. `since` liest diesen Zeitpunkt, `scope_at`, die
  Uhr des Servers, nie die Angabe des Feeds (B4, C3): die erste Sichtung eines
  Eintrags oder den Zeitpunkt, zu dem ihn ein späterer Neuabgleich, eine
  Zusammenführung von Wertpapieren oder ein allein verbliebener Kandidat
  zuordnete. Eine Story ist dabei, wenn einer ihrer Einträge danach in ihren
  Bereich kam, und `as_of` ist das nächste `since` (es liegt etwas früher, sodass ein
  Lesen eine Story wiederholen, aber nie überspringen kann). `tier_min`
  (`primary`, `secondary`, `awareness`) lässt die Stufen darunter weg.
  `min_materiality` (0 bis 3, standardmäßig 0) lässt die Aggregator- und
  thematischen Storys weg, deren Label darunter liegt, und über 0 die ohne
  Label; es liest Storys, mit `cluster_id` oder `assignment` ergibt es also
  `422`. `limit` ist standardmäßig 20 und höchstens 100; passten mehr Zeilen, ist `truncated`
  `true` und `cursor` setzt die Seite fort.
- `GET /api/v1/news/stories/:id` beantwortet eine Story, die einzige Stelle mit
  ihrem Link und Auszug: `title`, `url`, `domain`, `excerpt`, `tier`,
  `language`, `published_at`, `first_seen_at`, `count`, höchstens fünf
  `members` (`id`, `domain` auf 28 Zeichen gekürzt, `tier`, `at`; der Repräsentant zuerst),
  `note_ids`, ihr `security` oder `category` (`id`, `name`) und ihr aktives
  `label` (`event_type`, `materiality`, `tone`, `confidence` als String,
  `thesis_note_id` und `clause_idx`, wenn gesetzt, `machine_generated` immer
  `true`); `prompt_version` wählt die Version. Das Label zählt zu den 400
  Token, und der Auszug weicht ihm.
- `GET /api/v1/news/items/:id` beantwortet einen Eintrag ebenso, mit seiner
  `story_id`, `class`, `assignment`, `status` und, wenn mehrdeutig, seinen
  `candidates`.
- `GET /api/v1/news/health` beantwortet je Feed `id`, `class`, `enabled`,
  `last_ok_at`, `last_error`, `items_24h`, `err_24h`, `stale` (24 Stunden kein
  erfolgreicher Abruf; ein abgeschalteter Feed ist nie veraltet), `items_30d`,
  `promoted_30d` (die übernommenen Storys, in denen seine Einträge stehen,
  jede einmal), `yield_30d` (`promoted_30d` geteilt durch `items_30d`, ein
  Dezimal-String auf 4 Stellen gerundet, fehlt bei einem Feed ohne Einträge)
  und `low_yield` (`true` für einen Feed mit mindestens 50 Einträgen in 30
  Tagen, von dessen Storys keine übernommen wurde; A3). Nichts schaltet einen
  Feed von selbst ab: Der Betreiber entscheidet. Dazu die Tageszähler
  `unassigned`, `ambiguous`, `dropped`
  (`cap`, `no_source`, `old`) und `blocked`.
- `GET /api/v1/news/digest` beantwortet, was neu ist, eine Zeile je
  Wertpapier: mit `view_id` die Wertpapiere, die diese Sicht hält, ohne sie
  das News-Universum (gehalten, mit einem Zielgewicht oder beobachtet).
  `since` (standardmäßig 24 Stunden vor jetzt) liest `scope_at` wie die Liste,
  und `as_of` ist das nächste `since`. Eine Zeile ist `id`, `name`, `count`
  (ihre neuen Storys), die höchste `materiality` ihrer Storys mit Label und
  deren `event_types` (höchstens zwei, die wesentlichsten zuerst) und `top`
  (`id`, `title` auf 45 Zeichen gekürzt, `tier`, `at`): die beste Stufe, dann
  die neueste. Die Zeilen kommen nach ihrer höchsten Wesentlichkeit, von 3
  bis 1, dann eine Zeile mit Rauschen (0) oder ohne Label nach ihrer
  Top-Story. Eine Story mit einem Eintrag eines Emittenten- oder
  Regulierungs-Feeds zählt immer; eine Story nur aus Aggregator-Einträgen und
  eine thematische Story zählen, wenn die Wesentlichkeit ihres Labels
  `min_materiality` (0 bis 3, standardmäßig 2) erreicht, oder ohne Label mit
  `include_unlabeled=true`, die thematischen je Kategorie unter `categories`.
  `hidden` zählt die seitdem neuen Aggregator- und thematischen Storys, die
  beide wegließen (C5), `unlabeled` die neuen Storys ohne Label, und ein Wertpapier, dessen einzige
  Nachricht eine solche Story ist, zählt nicht als `quiet`, das die
  Wertpapiere ohne Zeile und ohne eine solche zählt; `unassigned` und
  `ambiguous` die seitdem so gewordenen Aggregator-Einträge, die kein
  Wertpapier oder mehrere beanspruchen. Mit einer `view_id` ist der Digest der
  der Sicht: `categories` und `unassigned` fehlen (eine Sicht hält
  Wertpapiere), `hidden` zählt nur die Storys ihrer Wertpapiere und
  `ambiguous` nur die Einträge, die eines davon nennen. `max_rows`
  (standardmäßig 10, womit der Digest auch mit jeder ID in ihrer größten Breite
  in seinem Budget bleibt; höchstens 40)
  begrenzt die Zeilen; `truncated` und `more` sagen, wie viele weggelassen
  wurden. `tier_min` wird nicht genommen (`422`): Klasse und Label
  entscheiden, was zählt, und `hidden` zählt, was sie wegließen, was eine
  Stufen-Untergrenze daneben nicht täte. Die Seite Nachrichten liest diesen
  Digest ohne `consumer` und verschiebt so keine Leseposition.

  **Der Verbraucher-Cursor** (§9, mindestens einmal): mit `consumer` (ein
  Bezeichner wie das Modell eines Labels) hält der Server die bestätigte
  Position dieses Lesers und liest ab ihr, beantwortet sie als `since` und
  trägt einen `cursor` statt `as_of`. Ein neuer Verbraucher beginnt
  24 Stunden zurück. Die Position rückt nur vor, wenn der nächste Aufruf den
  Cursor einer verarbeiteten Antwort mit `ack_cursor` bestätigt: ein Aufruf
  ohne ihn liest erneut ab der bestätigten Position, sodass ein Lauf, der
  nach dem Lesen abbricht, nichts verliert; der Preis ist eine doppelt
  gelesene Story. Für einen Verbraucher ist eine Story auch dann neu, wenn
  ihr Label der Prompt-Version des Lesens nach der Position geschrieben
  oder ersetzt wurde, sodass eine Story, die beim Bestätigen als
  unbeschriftet verborgen war, gelesen wird, sobald ihr Label sie zeigt.
  Ein Cursor, der älter ist als die gespeicherte Position,
  ändert nichts; einer, den der Server nicht diesem Verbraucher ausgegeben
  hat (gefälscht, verändert oder der eines anderen Verbrauchers), ergibt
  `422` mit `ack_cursor`, und nichts rückt vor. Zwei Verbraucher verschieben
  einander nie. `since` neben `consumer` und `ack_cursor` ohne ihn ergeben
  `422`. Der Server hält höchstens 32 Verbraucher; ein neuer darüber hinaus
  ergibt `422` mit der Obergrenze. Die tägliche Aufbewahrung löscht einen
  Verbraucher, dessen letzte Bestätigung (oder, nie bestätigt, seine
  Anlage) mehr als 90 Tage zurückliegt, sodass ein Name, den kein Lauf mehr
  nutzt, seinen Platz freigibt; erneut genannt, beginnt er als neuer, 24
  Stunden zurück. Ein Cursor ist mit einem aus
  `SECRET_KEY_BASE` abgeleiteten Schlüssel signiert: ändert sich dieses
  Geheimnis, ergibt ein gespeicherter Cursor `422`, und ein Aufruf ohne
  `ack_cursor` liest ab der bestätigten Position weiter. Ohne `consumer`
  hält der Digest keinen Zustand.

  **Die gekürzte Antwort eines Verbrauchers wird geblättert** (Closing
  Act, AT5): Sie trägt `next_page`, ein Seiten-Token, und keinen `cursor`;
  der Verbraucher sendet es als `page` (mit `consumer`, ohne `ack_cursor`)
  und erhält die nächsten Zeilen, jede Seite im Budget des Digests, bis zur
  letzten Seite, die den zu bestätigenden `cursor` trägt. So überspringt
  eine Bestätigung nie eine Zeile, die eine Antwort weggelassen hat. Die
  Seiten lesen nach den bereits beantworteten Zeilen weiter, nach ihrem
  Platz in der Reihenfolge, und der Cursor der letzten Seite ist der
  Zeitpunkt der ersten, sodass, was während des Blätterns eintraf, nach der
  Bestätigung gelesen wird. Blättern verschiebt keine Position. Ein
  Seiten-Token ist für diesen Verbraucher und seine Position mit einem
  eigenen Schlüssel signiert: ein verändertes, das eines anderen
  Verbrauchers oder eines als `ack_cursor` gesendet (und ein Cursor als
  `page`) ergibt `422`. Ein Seiten-Token einer Position, über die der
  Verbraucher seither hinaus bestätigt hat, ergibt die erste Seite ab der
  neuen Position mit `restarted: true`. Bei gleicher Materialität und
  gleichem Rang und gleicher Veröffentlichung ihrer Top-Story entscheidet
  die Wertpapier-ID über die Reihenfolge der Zeilen. Mit `since` behält eine
  gekürzte Antwort `truncated` und `more` wie bisher.
- `GET /api/v1/news/registry` (`news.registry`) listet, was
  die Reiter Feeds und Quellen der Nachrichten-Seite zeigen, gelesen über
  dieselbe Funktion: jeden registrierten Feed nach ID (`id`, `url`, gekürzt
  auf 300 Zeichen, wie der Begleiter sie schreibt, `class`, `security_id`
  oder `category_id` (keine bei einem Aggregator), `language`, `enabled`),
  danach jede bewertete Quelle nach Domain (`domain`, `tier`, `set_by`
  `hand` oder `seed`; eine Domain ohne Zeile gilt als `awareness`). `limit`
  (Standard 40, höchstens 100) zählt Feeds und Quellen zusammen; eine Seite,
  hinter der weitere Zeilen liegen, antwortet mit `truncated: true` und
  einem `cursor` zum Zurückgeben. Eine Seite beim Standardlimit hält
  höchstens etwa 4.500 Tokens, wie lang Links und Domains auch sind. Den
  Zustand jedes Feeds liefert `news.health`. Anlegen, Ändern und Entfernen
  bleiben bei der [News-Pflege](#news-pflege-adr-0056); ein
  unbekannter Parameter ergibt `422` mit seinem Namen.

### News-Labels (ADR-0056 §7)

Ein Modell außerhalb der App vergibt Labels über ein Skript auf dem Rechner
des Betreibers, das ein eigenes benanntes Token hält
(`PORTFOLIXIR_API_TOKENS`, z. B. `labeller=<token>`), sodass jedes Label
unter diesem Namen im Journal steht. Das Modell hält das Token nie: Es gibt
dem Skript JSON zurück, und das Skript ruft diese beiden Routen und sonst
nichts auf, direkt oder über einen Begleitdienst mit
`PORTFOLIXIR_MCP_PROFILE=label`, dem Profil, das als einziges die beiden
Tools listet ([MCP-Tools](#mcp-tools)). Ein Label ist ein Vorschlag
(`machine_generated` ist immer wahr): Es ordnet und filtert Aggregator- und
thematische Storys in den [Lesezugriffen](#news-lesezugriffe-adr-0056),
verbirgt nie die Story eines Emittenten oder einer Aufsicht und verschiebt,
ordnet zu oder schreibt sonst nichts; seine `suggested_security_id` ordnet
nichts zu. Ohne Label antwortet jeder Lesezugriff wie zuvor. Ein Labeller,
der seinen Prompt ändert, ändert `prompt_version`: Die Lesezugriffe folgen
der Version des zuletzt angelegten Labels, und die Storys der neuen Version
kommen in `unlabeled` zurück, bis sie eingeordnet sind. Zwei Labeller mit
verschiedenen Versionen lassen jeden Lesezugriff ohne `prompt_version` dem
folgen, der zuletzt ein Label anlegte; betreiben Sie also einen zur Zeit
oder nennen Sie die Version (Ergänzung von ADR-0056 vom 2026-11-09, D10).

- `PUT /api/v1/news/labels` speichert ein Label aus einem `label`-Objekt:
  `cluster_id` (eine Story), `model` und `prompt_version` (1 bis 64
  Buchstaben, Ziffern oder `. _ : / @ + -`, beginnend mit Buchstabe oder
  Ziffer), `event_type` (`earnings`, `guidance`, `capital_measure`, `legal`,
  `m_and_a`, `product`, `regulatory`, `macro`, `noise`), `materiality` 0 bis
  3, `tone` -1, 0 oder 1, `confidence` als Dezimal-String von 0 bis 1 mit
  höchstens vier Nachkommastellen, und optional `thesis_note_id` (die
  aktuelle intakte These des Wertpapiers der Story, die der Lesezugriff auf
  unbeschriftete Storys anbietet; eine abgelöste oder zurückgezogene
  ergibt `422`), `clause_idx` (eine ihrer Klauseln, nummeriert
  wie der Lesezugriff auf unbeschriftete Storys sie nummeriert) und
  `suggested_security_id`. Ein neues Label ergibt `201`; ein Put mit
  denselben `cluster_id`, `model` und `prompt_version` ersetzt es an Ort und
  Stelle, als vollständiger Ersatz, im Journal
  als Änderung, und ergibt `200`; ein Put gleich dem gespeicherten Label
  schreibt nichts. Das Schema ist geschlossen: Ein Feld außerhalb, in
  `label` oder daneben, ergibt `422` mit seinem Namen, ebenso ein falscher
  JSON-Typ, eine als Zahl gesendete `confidence` (`"must be a decimal
  string"`) und eine Story, ein Wertpapier, eine These oder Klausel, die es
  nicht gibt.
- `GET /api/v1/news/unlabeled?prompt_version=` liefert die Storys ohne Label
  dieser Version von irgendeinem Modell, neueste zuerst, `limit` 10
  (höchstens 25) mit `truncated`: je Zeile `id`, `security_id` oder
  `category_id`, `title`, `excerpt`, `domain`, `tier` und `at`; einmal je
  Antwort das `universe` (`id`, `name` mit höchstens 20 Zeichen, `isin`), die
  `categories` der Zeilen und je Wertpapier der Zeilen mit intakter These
  ihre `note_id` und die `clauses` (`idx`, `text`) der
  Invalidierungsbedingung, getrennt an Zeilenumbrüchen und Semikolons, sechs
  aufgeführt, `more` zählt den Rest. Ein anderer Parameter ergibt `422` mit
  seinem Namen. Beim Standardlimit hält die Antwort mit einem Universum von
  40 Wertpapieren etwa 6.000 Token; das Universum ist das ganze
  Nachrichten-Universum, ein größeres kostet also mehr.

### Logos

Jedes Wertpapier kann ein Logo tragen, automatisch ermittelt (CoinGecko für
Krypto, Wikipedia und danach companieslogo.com für Aktien, ETFs und Fonds,
das Logo des Emittenten für ein strukturiertes oder Hebelprodukt) oder von
Hand gesetzt. Ein manuelles Logo oder ein ausdrückliches „kein Logo“
*sperrt* das Wertpapier, sodass die Logo-Suche im Hintergrund die Wahl nie
überschreibt.

- `GET /api/v1/securities/:security_id/logo` liefert den Logo-Status:
  `{ "data": { "security_id", "path", "source", "has_logo", "locked", "file_missing" } }`.
  `source` ist `coingecko`, `wikipedia`, `companieslogo` oder `manual`;
  solange es kein Logo gibt, ist es `null`. `file_missing` (Issue #933) ist
  `true`, wenn die Prüfung beim Start der Instanz im Logo-Verzeichnis keine
  Datei zum gespeicherten `path` fand; `has_logo` ist dann `false`, während
  `path`, `source` und `locked` wie gespeichert bleiben. Ein so markiertes
  gefundenes Logo wird erneut gesucht, ein manuelles bleibt gesperrt und
  wartet darauf, erneut gesetzt zu werden, und `logo_status=missing` und
  `data_quality=missing_logo` führen beide. Speichern oder Entfernen eines
  Logos hebt die Markierung auf, ebenso der nächste Start, sobald die Datei
  zurück ist.
- `PUT /api/v1/securities/:security_id/logo` setzt ein manuelles Logo aus einer
  Bild-URL (`{ "logo": { "url": "https://…" } }` oder `{ "url": "https://…" }`).
  Das Bild wird einmal heruntergeladen, geprüft (png/jpg/jpeg/webp, höchstens
  256 KiB) und lokal gespeichert; das Wertpapier wird auf die manuelle Wahl
  gesperrt. Eine fehlende URL liefert `422` mit `errors.url`; ein Bild, das
  sich nicht laden lässt oder die Prüfung nicht besteht, liefert `422` mit
  `errors.logo`, einer festen Meldung, die weder Adresse noch Status nennt.
  Der Journaleintrag nennt den Prinzipal des Tokens, und sein Nachher-Abbild
  trägt `logo_source_host`, den Host, den die URL nannte.
- `DELETE /api/v1/securities/:security_id/logo` entfernt das Logo und hält die
  ausdrückliche Entscheidung „kein Logo“ fest (die Zeile zeigt wieder ihre
  Initialen oder ihre Flagge); auch das sperrt das Wertpapier gegen die Suche.
  Journalisiert unter dem Prinzipal des Tokens, wie das manuelle Logo und die
  erneute Suche; nur die Suche im Hintergrund wird als Systemjob `logo`
  journalisiert.
- `POST /api/v1/securities/:security_id/logo/discover` startet die
  automatische Suche erneut („Erneut suchen“). Die Antwort enthält ein
  `result`: `updated`, `no_source` oder `failed`. Gesperrte Wertpapiere bleiben
  unberührt und antworten mit `no_source`.

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
  `limit` behält die neuesten Zeilen des Fensters, weiterhin aufsteigend
  (Standard 20000, max. 50000; null, negativ oder nicht numerisch ist ein
  `422`).
- `PUT /api/v1/securities/:security_id/quotes` führt manuelle Kurszeilen ein
  (Upsert). Jede Zeile wird mit der Quelle `manual` gespeichert, gleich welche
  `source` sie nennt: Ein über die API geschriebener Kurs ist ein manueller
  Kurs, und die Anbieterquellen setzt allein die Kurssynchronisierung. Ein
  manueller Kurs hat Vorrang vor Anbieterdaten, deshalb ersetzt das Schreiben
  eine gespeicherte Zeile jeder Quelle an seinen Daten, und die
  Synchronisierung lässt eine manuelle Zeile stehen, bis sie freigegeben wird
  (unten). Das Schreiben wird unter dem Token journalisiert
  (`resource_type=security_quotes`, unter der Id des Wertpapiers, Operation
  `upsert`), mit den ersetzten gespeicherten Zeilen — ihren Kursen und
  Quellen — als Vorher-Abbild. Die Antwort ist
  `{"upserted": n, "replaced": [Daten]}`: `upserted` zählt die Zeilen, die
  nun wie übergeben gespeichert sind, `replaced` nennt die ISO-Daten, deren
  gespeicherte Zeile das Schreiben geändert hat (ein neues Datum steht nicht
  darin). Ein Schreiben, das nichts ändert, hinterlässt keinen
  Journaleintrag.
  Jede Kurszeile, manuell oder synchronisiert, ist begrenzt: ein
  `close`, der auf seine 6 Nachkommastellen gerundet positiv ist und höchstens
  14 Stellen vor dem Komma hat, an einem `date`, das nicht nach morgen liegt (dem
  Kalendertag der Instanz plus einem Tag für Zeitzonen). Eine Zeile außerhalb
  der Grenze liefert `422` mit dem Feld, und eine Synchronisierung verwirft
  einen solchen Anbieterpunkt, statt den Lauf scheitern zu lassen. Die
  Lesepfade für den jüngsten Kurs (der Bewertungskurs, der jüngste Kurs im
  Katalog und die Prüfung auf veraltete Kurse) nutzen nie eine gespeicherte
  Zeile nach dieser Grenze. Ein Stapel nennt jedes Datum einmal und enthält
  nur Kursobjekte: Ein wiederholtes Datum liefert `422` mit `errors.date`, das
  es nennt, eine Zeile, die kein Objekt ist, `422` auf `quotes`, und nichts
  wird geschrieben.
- `POST /api/v1/securities/:security_id/quotes/release` gibt die
  **manuellen** Kurse eines Wertpapiers von `from` bis `to` (beide Pflicht,
  einschließlich, im Body oder in der Query) an die Anbieterdaten zurück: Die
  manuellen Zeilen des Zeitraums werden entfernt, unter dem Token
  journalisiert (Operation `delete`) mit den freigegebenen Zeilen als
  Vorher-Abbild, und die Antwort ist
  `{"security_id", "from", "to", "released": [Daten]}`. Anbieterzeilen im
  Zeitraum bleiben, und ein Zeitraum ohne manuelle Zeilen ändert nichts und
  schreibt keinen Eintrag. Die nächste Kurssynchronisierung speichert den
  Anbieterkurs für ein freigegebenes Datum; ein Wertpapier ohne Anbieter
  behält dafür keinen Kurs. Ein fehlendes oder ungültiges Datum liefert `422`
  mit dem Feld, `to` vor `from` `422` auf `to`, ein unbekanntes Wertpapier
  `404`. Der Operator gibt im Tab „Kurse“ des Wertpapiers frei
  (**Freigeben…**, Sprint 17), über dasselbe Schreiben.
- `GET /api/v1/securities/:security_id/quotes/manual` liest die
  **manuellen** Kurse eines Wertpapiers über seine ganze gespeicherte
  Historie — der Lesezugriff, auf dem eine Freigabe steht (Sprint 17,
  `portfolixir.quotes.manual`): `count`, `first` und `last` (das erste und
  letzte manuelle Datum, `null` ohne eines), `stored_count` (jeder
  gespeicherte Kurs, gleich welcher Quelle), `stretches` — jeder Abschnitt
  eine Folge manueller Kurse ohne Kurs einer anderen Quelle dazwischen,
  `{"from", "to", "count"}`, aufsteigend, die jüngsten `limit` davon (die
  Listen-Familie: Standard 100, gedeckelt bei 1000, in `meta.limit` gespiegelt)
  —, `stretch_count` (alle) und `sync_adapter`: ob die Kurssynchronisierung
  das Wertpapier abfragen kann — ein Adapter für seinen Anbieter, der es
  abfragen kann (Yahoo braucht einen Ticker), und ein `feed` außer `MANUAL`
  oder `NONE`, die Prüfungen, die sie vor jedem Abruf macht. Bei `false` behält ein freigegebenes Datum keinen Kurs; bei
  `true` kann ein Abruf trotzdem scheitern. `from` und/oder `to` (einschließlich; eine fehlende Grenze ist
  offen) fügen `range` `{"from", "to", "count"}` hinzu: die manuellen Kurse,
  die eine Freigabe genau dieses Zeitraums entfernen würde. `to` vor `from`
  liefert `422` auf `to`, ein ungültiges Datum `422` mit dem Feld, ein
  unbekanntes Wertpapier `404`.
- `POST /api/v1/securities/:security_id/sync_quotes` löst die
  Kurssynchronisierung eines Wertpapiers aus. Die Antwort enthält `status` (`ok`,
  `skipped` oder `error`); übersprungene und Fehler-Antworten können einen
  `reason` wie `missing_ticker` oder `no_provider_adapter` enthalten, und
  `persist_failed`, wenn die geholten Kurse nicht gespeichert werden konnten.
  Ein Wertpapier, dessen `feed` `MANUAL` oder `NONE` ist, wird mit
  `manual_feed` übersprungen, und kein Anbieter wird gefragt: Dieser Feed
  hält die Kurssynchronisierung auf jedem Weg an, bei diesem Aufruf, der
  geplanten Synchronisierung und der Synchronisierung aller Wertpapiere auf
  der Seite. `PATCH /api/v1/securities/:id`
  (`portfolixir.securities.update`) mit diesem Feed ist also der Weg, die
  Anbieterkurse eines Wertpapiers anzuhalten, dessen Kurse Sie von Hand
  pflegen. Ein ausgemustertes Wertpapier synchronisiert dieser Aufruf; die
  geplante Synchronisierung und die aller Wertpapiere überspringen es mit
  `retired` (#1410). Beides zählt als übersprungen. Eine Anbieterantwort,
  die eine andere Währung nennt als den `currency_code` des Wertpapiers,
  speichert keinen Kurs und liefert `status` `error` mit `reason`
  `currency_mismatch` (#1411): verglichen wie geschrieben, Yahoos `GBp`
  (Pence) ist also nicht `GBP`; eine Antwort ohne Währung wird gespeichert
  wie bisher. Ein genannter Wert, der nicht aus drei Buchstaben besteht, ist
  kein Währungscode: Er speichert keinen Kurs und liefert `reason`
  `invalid_currency`, und die von einer früheren Synchronisierung
  festgehaltene Anbieterwährung bleibt stehen.
  Eine Historie beliebiger Länge wird in einer Synchronisierung gespeichert,
  und in der geplanten Synchronisierung ist ein scheiterndes Wertpapier der
  Fehler dieses Wertpapiers, während die übrigen weiter synchronisiert werden.
  Eine Synchronisierung eines Wertpapiers läuft zur Zeit: Während eine läuft,
  gleich über welchen Weg, liefert eine zweite `409 Conflict` und ruft keinen
  Anbieter auf. Die Kurshistorie eines neu angelegten Wertpapiers wird im
  Hintergrund über eine Warteschlange geholt, ein Wertpapier nach dem anderen,
  ob es über die API, die Seite oder einen Import entstand.

Beispiel-Payload für Kurs-Upsert:

```json
{
  "quotes": [
    {
      "date": "2026-05-15",
      "close": "123.45"
    }
  ]
}
```

Beispiel-Antwort für Kurs-Upsert, dessen erstes Datum eine synchronisierte
Zeile ersetzt hat:

```json
{
  "data": {
    "upserted": 2,
    "replaced": ["2026-05-15"]
  }
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
  abgelehnt. Ein `name`, den ein anderes Geldkonto im Portfolio als Namen oder
  als einen seiner früheren Namen trägt, antwortet `422` mit `errors.name`,
  weil ein Import, der ihn nennt, schon auf jenes Konto bucht (ADR-0050 §4).
- Jede Nutzlast eines Geld- oder Wertpapierkontos trägt **`former_names`**
  (ADR-0050 §4), eine Liste von Strings: die Namen, unter denen das Konto
  bekannt war. Der Portfolio-Performance-Import löst den Kontonamen einer Datei
  zuerst über den aktuellen Namen auf, dann über die früheren Namen, sodass
  eine Zeile, die einen früheren Namen nennt, auf dieses Konto bucht. Zwei
  Konten einer Art in einem Portfolio teilen nie einen aktuellen oder früheren
  Namen; Namen, die zwei Konten schon vor dieser Regel teilten, lösen auf keines
  der beiden auf, und der Import wartet, bis der Betreiber eines wählt. Ein
  Name wird ohne führende und abschließende Leerzeichen gespeichert, so wie der
  Import ihn liest; ein Name, der sich von dem eines anderen Kontos nur durch
  sie unterscheidet, ist dieser Name.
- `GET /api/v1/cash_accounts/:id` liefert ein Geldkonto. Ein Konto, das eine
  Zusammenführung entfernt hat, antwortet `404` mit `errors.merged_into`
  `{"kind": "cash_account", "id": …}`, dem Konto, auf dem seine Historie
  jetzt liegt, über jede spätere Zusammenführung verfolgt (ADR-0050 §12).
- `PATCH /api/v1/cash_accounts/:id` aktualisiert ein Geldkonto (`name`,
  `currency_code`, `notes`, `liquidity_role`); `portfolio_id` kann nicht
  geändert werden. Der `currency_code` **friert ein**, sobald eine
  Transaktion über eines ihrer beiden Konten auf das Konto verweist oder ein
  Wertpapierkonto es verknüpft (ADR-0050 §11): Eine Änderung liefert dann
  `422` mit `errors.currency_code`, das die Verweise zählt, etwa
  `["is frozen once referenced (1 securities account, 12 transactions)"]`,
  und nichts wird geschrieben — gebuchte Historie wird nie umdenominiert.
  Eine Umbenennung behält den bisherigen Namen in `former_names`, und die
  Rückbenennung auf einen früheren Namen verbraucht ihn. Solange ein anderes
  Geldkonto im Portfolio den bisherigen Namen noch als aktuellen Namen trägt,
  wird der bisherige Name nicht behalten: Ein Import, der ihn nennt, bucht auf
  jenes andere Konto (jenes Konto zusammenführen oder umbenennen, um das zu
  ändern). Ein neuer Name, den ein anderes Geldkonto als aktuellen oder
  früheren Namen trägt, antwortet `422` mit `errors.name`.
- `DELETE /api/v1/cash_accounts/:id/former_names?name=` entfernt einen
  früheren Namen, journalisiert, und antwortet mit dem Konto
  (`portfolixir.cash_accounts.remove_former_name`). Ein Import, der '<name>'
  noch nennt, legt dann ein neues Konto an. Ein Name, den das Konto nicht
  trägt, antwortet `404`, ein fehlender `name` `422`. Ein Name, der vor der
  Ablehnung unsichtbarer Zeichen gespeichert wurde, darf in der Schreibweise
  angegeben werden, in der der MCP-Begleitdienst ihn auflistet, jedes solche
  Zeichen als `[U+XXXX]`; ein gespeicherter Name aus genau diesen Buchstaben
  wird zuerst getroffen (E25).
- `DELETE /api/v1/cash_accounts/:id` löscht ein Geldkonto, auf das keine
  Transaktion über eines ihrer beiden Konten verweist und das kein
  Wertpapierkonto verknüpft. Sonst liefert es `409 Conflict` mit
  `errors.referenced_by` (etwa `{"transactions": 12, "securities_accounts": 1}`),
  `errors.remedy` `merge` und `errors.remedy_route`, der
  Zusammenführungs-Vorschau
  `GET /api/v1/cash_accounts/:id/merge_preview?target_id=`, ergänzt um die ID
  des Kontos, das bleibt: Eine Zusammenführung verschiebt die Historie, ein
  Löschen verwirft sie nie. Die Bucket-Verknüpfungen eines unreferenzierten
  Kontos werden vorher entfernt, journalisiert (ADR-0050 §11). Ein Löschen, das einen Wettlauf mit einem
  gleichzeitigen Schreibvorgang verliert und danach keinen Verweis mehr
  findet, antwortet mit `409 Conflict` und allein `errors.detail` und löscht
  nichts: den Datensatz neu lesen und erneut versuchen (#954).
- `GET /api/v1/cash_accounts/:id/merge_preview?target_id=` zeigt die
  Zusammenführung des Kontos (der **Quelle**) in `target_id` (das **Ziel**,
  das Konto, das bleibt) als Vorschau — ein Lesen, das nichts schreibt
  (ADR-0050 §7, §10; `portfolixir.cash_accounts.merge_preview`). Beide
  Konten müssen Portfolio, Währung, Liquiditätsrolle und Bucket-Menge teilen;
  sonst antwortet sie `409 Conflict` mit `errors.code` (`same_account`,
  `not_live`, `portfolio_mismatch`, `currency_mismatch`,
  `liquidity_role_mismatch`, `buckets_mismatch`,
  `legacy_hashed_anchor` für einen gesetzten Saldo, der noch einen
  Import-Hash aus der Zeit vor der Import-Hash-Artprüfung trägt und angepasst
  oder verschoben werden müsste, oder `unstorable_anchor` für einen gesetzten
  Saldo, dessen angepasster Betrag mehr als die 6 Nachkommastellen der
  Betragsspalte bräuchte — der Saldo des anderen Kontos trägt den Bruchteil
  eines Kaufs, der ohne Betrag gebucht wurde; erst diesen Betrag erfassen,
  dann die Vorschau erneut abrufen), `errors.detail` und `errors.guards`; bei
  den letzten beiden nennt `errors.anchors` jeden gesetzten Saldo (`id`,
  `date`, `cash_account_id`), und bei `unstorable_anchor` nennt
  `errors.bookings` die Käufe, die ohne Betrag gebucht wurden. Eine
  unbekannte Quelle antwortet `404`, eine bereits zusammengeführte `409`
  `already_merged` mit `errors.merged_into`, eine fehlende `target_id` `422`.
  Die `200`-Antwort trägt:
  - `plan_digest`, den Digest, den die Zusammenführung erwartet;
  - `source` und `target`, jeweils mit `balance` (die Faltung aller
    Buchungen, wie `GET /api/v1/cash_accounts` sie meldet),
    `transaction_count`, `bucket_ids` und `former_names`; `guards`;
    `linked_depots` (die der Quelle, die zum Ziel wechseln);
  - `internal_transfers`: die Umbuchungen zwischen beiden, die die
    Zusammenführung löscht — beide Seiten werden ein Konto;
  - `key_equal_pairs`: eine Buchung der Quelle, deren Tag, Art und Beträge
    denen einer Buchung des Ziels gleichen, eins zu eins gepaart, kleinste
    ID zuerst, und `choice_required`, sobald es eine gibt;
  - `former_names`: die Namen, die das Ziel hinzugewinnt (`appended`), die,
    die schon ein anderes Konto trägt (`not_kept`, mit `held_by`), und die
    Liste des Ziels danach (`after`);
  - `outcome_by_collapse_key_equal` mit `"false"` (beide Buchungen eines
    Paars behalten) und `"true"` (die der Quelle löschen): `balance` und
    `transaction_count` des Ziels danach, `moved_transaction_ids`, `deleted`
    (jeweils mit `reason`: `internal_transfer`, `collapsed_duplicate` oder
    `folded_anchor`), `restated_anchors` (jeder gesetzte Saldo, der danach
    auf dem Ziel steht, als `stated` + `other_balance` = `after`: der Saldo
    des anderen Kontos am Ende dieses Tages, aus seinen Buchungen vor der
    Zusammenführung; an einem Tag mit gesetzten Salden auf beiden Konten
    trägt der letzte des Ziels beide, die übrigen entfallen), `flow_changes`
    (die externen Flüsse, die das Entfernen der Duplikate streicht — `kind`
    `removed` — oder in einen späteren gesetzten Saldo des Kontos verschiebt,
    auf dem die Buchung stand — `kind` `absorbed`, der Quelle selbst oder bei
    einer entfernten Umbuchung des dritten Kontos —, je mit
    `cash_account_id`, der `transaction_id` des Saldos oder der Buchung,
    `date`, `change` und `collapsed_transaction_id`), `other_accounts` und
    `positions` (was eine entfernte Umbuchung oder ein entfernter Kauf
    anderswo ändert);
  - `balance_basis`, die Rechengrundlage der Salden und der angepassten
    gesetzten Salden: Ein Saldo ist die Faltung jeder Buchung des Kontos,
    wie `GET /api/v1/cash_accounts` ihn meldet; ein angepasster gesetzter
    Saldo ist sein genannter Betrag plus der Saldo des anderen Kontos am
    Ende dieses Tages, aus dessen Buchungen vor der Zusammenführung;
  - `reimport_note`, was die Zusammenführung für den nächsten
    Portfolio-Performance-Import bedeutet: Die Namen der Quelle führen dorthin
    (außer einem, den ein anderes Konto noch trägt, `former_names.not_kept`),
    und ein erneut angewendeter Export legt nichts an.

  Jeder Dezimalwert ist ein String. Der Digest umfasst beide Konten, jede
  Buchung, auf die eines verweist, mit ihrem `updated_at`, jede Zahl und die
  Prüfungen; die Wahl gehört nicht dazu, ein Paar hat also einen Digest.
- `POST /api/v1/cash_accounts/:id/merge` mit `{"target_id": …,
  "plan_digest": …, "collapse_key_equal": …}` führt unter dem Token zusammen
  (`portfolixir.cash_accounts.merge`). `collapse_key_equal` ist Pflicht,
  sobald die Vorschau `key_equal_pairs` aufführt — ohne antwortet sie `422`
  und nennt, wie viele —, und nie vorbelegt: den Operator fragen. Die
  Antwort ist `201 Created` mit dem **Zusammenführungsprotokoll** (`id`,
  `kind`, `source_id`, `target_id`, `portfolio_id`, `source_snapshot`,
  `manifest` — jede verschobene, angepasste oder gelöschte Buchung, die
  umgehängten Depots, die entfernten Bucket-Verknüpfungen, die angehängten
  Namen, die Wahl, `null`, wo die Vorschau keine `key_equal_pairs` nannte
  —, `plan_digest`, `actor_type`, `actor_label`,
  `inserted_at`) und `already_applied: false`. In einer Transaktion, ein
  Audit-Journal-Eintrag je Zeile: Die Umbuchungen zwischen beiden und, mit
  `true`, die gepaarten Buchungen der Quelle werden gelöscht, ihre
  Inhalts-Hashes stillgelegt; jeder gesetzte Saldo wird angepasst, wie die
  Vorschau es sagte; jede andere Buchung der Quelle und ihre verknüpften
  Depots wechseln zum Ziel; der zusammengeführte Saldo wird an jedem Tag,
  an dem eines der Konten eine Buchung hat, und heute gegen die Summe beider
  Konten geprüft (sonst rollt `409 identity_check_failed` die
  Zusammenführung zurück — eine Prüfung auf einen Fehler, nie eine erwartete
  Antwort); die Bucket-Verknüpfungen der Quelle werden entfernt und die
  Quelle gelöscht; ihr Name und ihre früheren Namen werden frühere Namen des
  Ziels, außer einem Namen, den ein anderes Geldkonto noch als Namen oder
  früheren Namen trägt: Er wird nicht übernommen (`former_names.not_kept` in
  der Vorschau) und führt einen Import weiter zu jenem Konto. Hat sich seit
  der Vorschau eine Buchung, eine Zahl oder eine Prüfung
  geändert, antwortet sie `409` mit `errors.code` `plan_changed` und der
  frischen Vorschau in `errors.preview` und schreibt nichts. Eine
  Wiederholung einer abgeschlossenen Zusammenführung desselben Paars
  antwortet `200` mit dem ursprünglichen Protokoll und
  `already_applied: true` und journalisiert nichts; eine Quelle, die schon in
  ein anderes Konto zusammengeführt wurde, antwortet `409` `already_merged`
  mit `errors.merged_into`. Ein fehlender `plan_digest` oder eine fehlende
  `target_id` oder ein `collapse_key_equal`, der kein Boolean ist, antwortet
  `422`. Ein Rückgängigmachen gibt es nicht: Protokoll und die Vorher-Bilder
  des Journals rekonstruieren, was eine Zusammenführung getan hat. Der
  Operator führt über das Zeilenmenü auf Konten & Depots zusammen
  (**Zusammenführen in…**), das diese Vorschau zeigt und sie mit ihrem Digest
  anwendet.
- `GET /api/v1/securities_accounts` listet Depots/Wertpapierkonten.
- `POST /api/v1/securities_accounts` legt ein Depot/Wertpapierkonto mit einem
  `securities_account`-Objekt an. `portfolio_id` ist optional (ADR-0024):
  fehlt sie, wird das Depot an das deterministische interne Standard-Portfolio
  gebunden. Ein `name`, den ein anderes Depot im Portfolio als Namen oder als
  einen seiner früheren Namen trägt, antwortet `422` mit `errors.name`
  (ADR-0050 §4).
- `GET /api/v1/securities_accounts/:id` liefert ein Wertpapierkonto. Ein
  Depot, das eine Zusammenführung entfernt hat, antwortet `404` mit
  `errors.merged_into` `{"kind": "securities_account", "id": …}`, über jede
  spätere Zusammenführung verfolgt (ADR-0050 §12).
- `PATCH /api/v1/securities_accounts/:id` aktualisiert ein Wertpapierkonto
  (`name`, `notes`, `cash_account_id`); `portfolio_id` kann nicht geändert werden.
  Eine Umbenennung behält den bisherigen Namen in `former_names` nach denselben
  Regeln wie bei einem Geldkonto: Die Rückbenennung verbraucht ihn, ein
  bisheriger Name, den ein anderes Depot noch als aktuellen Namen trägt, wird
  nicht behalten, und ein Name, den ein anderes Depot als aktuellen oder
  früheren Namen trägt, antwortet `422` mit `errors.name`.
- `DELETE /api/v1/securities_accounts/:id/former_names?name=` entfernt einen
  früheren Namen eines Depots, journalisiert, und antwortet mit dem Depot
  (`portfolixir.securities_accounts.remove_former_name`). Ein Import, der
  '<name>' noch nennt, legt dann ein neues Depot an. Der Name wird wie beim
  Geldkonto getroffen, die Schreibweise `[U+XXXX]` eingeschlossen.
- `DELETE /api/v1/securities_accounts/:id` löscht ein Wertpapierkonto, auf das
  keine Transaktion über eines ihrer beiden Konten verweist. Sonst liefert es
  `409 Conflict` mit `errors.referenced_by`, `errors.remedy` `merge` und
  `errors.remedy_route`, der Zusammenführungs-Vorschau
  `GET /api/v1/securities_accounts/:id/merge_preview?target_id=`. Die
  Standard-Buckets und Positions-Overrides eines unreferenzierten Depots
  werden vorher entfernt, journalisiert: ein Eintrag für die Standardmenge,
  einer je Position. Ein Löschen, das einen Wettlauf mit einem
  gleichzeitigen Schreibvorgang verliert und danach keinen Verweis mehr
  findet, antwortet mit `409 Conflict` und allein `errors.detail` und löscht
  nichts: den Datensatz neu lesen und erneut versuchen (#954).
- `GET /api/v1/securities_accounts/:id/merge_preview?target_id=` zeigt die
  Vorschau, das Depot (die **Quelle**) in `target_id` (das **Ziel**, das Depot,
  das bleibt) zusammenzuführen — ein Lesen, das nichts schreibt (ADR-0050 §7,
  §10; `portfolixir.securities_accounts.merge_preview`). Beide Depots müssen
  im selben Portfolio liegen und dieselbe Standard-Bucket-Menge haben, und
  jede Position muss ihre Ansichts-Zugehörigkeit behalten: Für jedes
  Wertpapier, das die Quelle hält, müssen, wo auch das Ziel es hält, beide
  wirksamen Bucket-Mengen gleich sein; wo das Ziel es nicht hält, wird die
  Menge der Quelle übertragen. Sonst antwortet sie `409 Conflict` mit
  `errors.code` (`same_account`, `not_live`, `portfolio_mismatch`,
  `buckets_mismatch` oder `position_buckets_mismatch`, dessen
  `errors.detail` jede Position und beide Bucket-Mengen nennt — oder einen zu
  übertragenden Override mit mehr als einem Scope-Bucket, den die Position im
  Ziel nicht aufnehmen kann),
  `errors.detail` und `errors.guards`. Eine unbekannte Quelle antwortet `404`,
  eine schon zusammengeführte Quelle `409` `already_merged` mit
  `errors.merged_into`, eine fehlende `target_id` `422`. Die `200` enthält:
  - `plan_digest`, den Digest, den die Zusammenführung nimmt;
  - `source` und `target`, je mit `cash_account_id`, `bucket_ids` (der
    Standardmenge), `former_names` und `transaction_count`; `guards`;
  - `internal_transfers`: die Wertpapierumbuchungen zwischen beiden, die die
    Zusammenführung löscht — beide Seiten werden ein Depot;
  - `key_equal_pairs`: eine Buchung der Quelle, deren Tag, Art, Wertpapier,
    Verrechnungskonto und Beträge denen einer Buchung des Ziels gleichen,
    eins zu eins gepaart, niedrigste ID zuerst, jede mit beiden Depot-Seiten
    (`securities_account_id`, `counter_securities_account_id`), und
    `choice_required`, wenn es eine gibt;
  - `position_buckets`: je Wertpapier, das die Quelle hält oder für das sie
    einen Override trägt, beide wirksamen Bucket-Mengen, beide Overrides
    (`null` für eine Position, die die Standardmenge ihres Depots erbt, `[]`
    für einen bewusst leeren) und die `action`: `carry` (der Override der
    Quelle geht auf das Ziel über), `drop_redundant` (das Ziel zeigt die
    Position schon in denselben Buckets), `drop_unheld` (die Quelle hält keine
    Buchung davon), `clear_target` (der Override des Ziels für ein Wertpapier,
    das es nicht hält, wird entfernt, damit die verschobenen Buchungen die
    Standardmenge behalten) oder `none`;
  - `former_names`: `appended`, `not_kept` und die Liste `after` des Ziels;
  - `outcome_by_collapse_key_equal` mit `"false"` und `"true"`: die
    `transaction_count` des Ziels danach, `moved_transaction_ids`, `deleted`
    (je mit `reason`: `internal_transfer` oder `collapsed_duplicate`),
    `positions` (jedes Wertpapier, das die Quelle hält, je mit `source`,
    `target` und `after`, je `quantity`, `cost_basis`, `avg_cost` und
    `realized_result`; `target` ist `null`, wo das Ziel keine Buchung davon
    hält), `rounding_differences`, `cash_accounts` (jedes
    Verrechnungskonto, das eine entfernte gleiche Buchung ändert, mit
    `balance_before` und `balance_after`) und `flow_changes` (jeder externe
    Fluss, den das Entfernen gleicher Buchungen wegnimmt oder verschiebt,
    damit die Änderung der zeitgewichteten Rendite sichtbar ist; jeder
    Eintrag trägt `kind`, `cash_account_id`, `securities_account_id`,
    `security_id`, `view_id`, `transaction_id`, `date`, `quantity`,
    `change`, `currency_code`, `valued_at` und `collapsed_transaction_id`,
    `null`, wo ein Schlüssel nicht zutrifft: `removed`, eine entfernte
    Ein- oder Auslieferung, ihr Depot und Wertpapier, `quantity` die
    Änderung der Stücke, die der Fluss dieses Tages trägt, und `change` ihr
    Wert zum gebuchten Kurs der Lieferung in `currency_code` (`valued_at`
    `booked_price`), oder `null`, wo die Lieferung keinen Kurs trägt und
    die Performance-Rechnung die Stücke zum Kurs des Tages bewertet
    (`valued_at` `market`); `boundary_removed`, eine entfernte Umbuchung,
    ein entfernter Kauf oder Verkauf, von deren Teilen genau einer in der
    Sicht `view_id` liegt, ein Fluss über die Grenze dieser Sicht und
    keiner des Portfolios selbst, ein Eintrag je Sicht, deren Grenze sie
    kreuzt: Eine Umbuchung nennt das Depot in der Sicht und wird zum Kurs
    des Tages bewertet; ein Kauf oder Verkauf nennt sein Verrechnungskonto
    und sein Depot, und `change` ist der gebuchte Wert, den der Fluss der
    Sicht nicht mehr trägt, in der `currency_code` des Verrechnungskontos
    (`valued_at` `booked_value`: der Geld-Anteil mit umgekehrtem Vorzeichen,
    wo das Verrechnungskonto in der Sicht liegt, der Geld-Anteil selbst, wo
    die Position darin liegt); `absorbed`, der Geld-Anteil einer
    entfernten Buchung, den ein späterer gesetzter Saldo ihres
    Verrechnungskontos nun aufnimmt, mit der `transaction_id` des Saldos,
    `date` und `change` in der `currency_code` des Verrechnungskontos,
    wie in der Vorschau einer
    Geldkonto-Zusammenführung) und `other_depots` (jedes dritte Depot, das
    eine entfernte Umbuchung nennt, je Wertpapier mit
    `securities_account_name`, `security_name`, `quantity_before` und
    `quantity_after`: Das Entfernen einer Umbuchung ändert auch seinen
    Bestand);
  - `positions_basis`, die Rechengrundlage dieser Zahlen: Die Stückzahl ist
    die Positionsfaltung, in der jeder Split die Position einmal skaliert,
    gerundet auf die Stückzahl-Genauigkeit 6 (ADR-0028 §3); `cost_basis` und
    `avg_cost` sind der gleitende Durchschnitt der Kosten, den
    `GET /api/v1/portfolios/:id/holdings` nennt, in der Währung des
    Wertpapiers, ohne Gebühren und Steuern — nach der Zusammenführung bilden
    die Käufe beider Depots einen gemeinsamen Durchschnitt, die Kosten ändern
    sich also zu Recht, und ein Verkauf, den das Ziel zwischen zwei Käufen
    getätigt hat, verbraucht danach den gemeinsamen Durchschnitt;
    `realized_result` ist das Ergebnis des Depots nach gleitendem
    Durchschnitt, nicht die realisierten Gewinne der App: über die Verkäufe
    der Position die Stückzahl jedes Verkaufs mal sein Kurs in der Währung
    des Wertpapiers, abzüglich der Kosten, die er zum laufenden Durchschnitt
    entnommen hat, und `null`, wo dieser Kurs oder diese Kosten nicht
    ableitbar sind. Die realisierten Gewinne nach FIFO
    (`GET /api/v1/realized_gains`, die Trades eines Wertpapiers) ändern sich
    bei einer Depot-Zusammenführung nicht, außer gleiche Buchungen werden als
    Duplikate entfernt, was sie aus der Reihe nimmt: Die FIFO-Reihe gehört
    dem Wertpapier, nicht dem Depot;
    `rounding_differences` nennt je Position und Split-Datum jeden Split
    eines betroffenen Wertpapiers, bei dem die gemeinsam einmal gerundete
    Position am Ende des Split-Tags von den zwei getrennt gerundeten
    abweicht, mit beiden Stückzahlen und ihrer Differenz — erwartet und nie
    eine Ablehnung, und an keine Schranke je Split gebunden: Wo Splits
    aufeinander aufbauen, skaliert der nächste die Differenz, die einer
    hinterlässt (ADR-0050, Ergänzung vom 2026-10-08);
  - `flow_basis`, die Rechengrundlage von `flow_changes`: Der Fluss eines
    genannten Tages (`GET /api/v1/portfolios/:id/performance`, und
    `GET /api/v1/views/:id/performance` für `boundary_removed`) ändert sich
    allein um seine Einträge; die Rendite dieses Tages und der folgenden
    liest auch die entfernten Stücke, die nicht mehr gehalten werden, darum
    nennt die Vorschau die Flüsse, keine neu berechnete Rendite; die
    Zugehörigkeit zu Sichten gilt, wie sie steht, und die Zusammenführung
    lässt sie unverändert;
  - `reimport_note`, was die Zusammenführung für den nächsten
    Portfolio-Performance-Import bedeutet, wie bei einem Geldkonto.

  Jede Stückzahl und jede Dezimalzahl ist ein String. Der Digest deckt beide
  Depots ab, jede Buchung, die eines von beiden nennt, und die Splits des
  Portfolios für deren Wertpapiere mit ihrem `updated_at`, jede Zahl (den
  Bucket-Plan eingeschlossen) und die Prüfungen; die Wahl gehört nicht dazu,
  ein Paar hat also einen Digest.
- `POST /api/v1/securities_accounts/:id/merge` mit `{"target_id": …,
  "plan_digest": …, "collapse_key_equal": …}` führt unter dem Token zusammen
  (`portfolixir.securities_accounts.merge`). `collapse_key_equal` ist
  Pflicht, wenn die Vorschau `key_equal_pairs` nennt — ohne antwortet sie
  `422` mit ihrer Anzahl — und ist nie vorausgewählt: Frag den Operator. Sie
  antwortet `201 Created` mit dem Protokoll der Zusammenführung (wie bei
  einem Geldkonto; sein `manifest` nennt jede verschobene oder gelöschte
  Buchung, die Overrides `carried`, `dropped` und `cleared`, die entfernten
  Standard-Buckets, die angehängten Namen, die Rundungsdifferenzen und die
  Wahl, `null`, wo die Vorschau keine `key_equal_pairs` nannte) und
  `already_applied: false`. In einer Transaktion, ein
  Audit-Journal-Eintrag je Zeile: Die Umbuchungen zwischen beiden und, mit
  `true`, die gepaarten Buchungen der Quelle werden gelöscht und ihre
  Inhalts-Hashes stillgelegt; jede andere Buchung der Quelle geht auf das
  Ziel über, auf der Depot-Seite, die die Quelle nennt, und behält ihr
  Verrechnungskonto — das Ziel behält sein eigenes verknüpftes
  Verrechnungskonto, das der Quelle bleibt als eigenes Konto bestehen; die
  Stückzahl jedes Wertpapiers im Ziel wird an jedem Tag, an dem eines der
  beiden eine Buchung hat, an jedem Split-Tag und heute gegen die Buchungen
  beider Depots geprüft (`409 identity_check_failed` rollt die
  Zusammenführung sonst zurück — eine Prüfung auf einen Fehler, nie eine
  erwartete Antwort); der Bucket-Plan wird geschrieben, ein Journal-Eintrag
  je Position; die Standard-Buckets der Quelle werden entfernt und die Quelle
  gelöscht; ihr Name und ihre früheren Namen werden frühere Namen des Ziels,
  außer einem Namen, den ein anderes Depot noch trägt
  (`former_names.not_kept`). Ein geänderter Plan antwortet `409`
  `plan_changed` mit der frischen
  Vorschau in `errors.preview`; eine Wiederholung einer abgeschlossenen
  Zusammenführung desselben Paars antwortet `200` mit dem ursprünglichen
  Protokoll und `already_applied: true`; eine in ein anderes Depot
  zusammengeführte Quelle `409` `already_merged`; ein fehlender `plan_digest`
  oder eine fehlende `target_id` oder ein `collapse_key_equal`, der kein
  Boolean ist, `422`. Ein Rückgängigmachen gibt es nicht. Der Operator führt
  über das Menü der Depotzeile auf Konten & Depots zusammen
  (**Zusammenführen in…**), mit derselben Vorschau.
- `GET /api/v1/merges` listet die **Zusammenführungsprotokolle**, das
  neueste zuerst (`inserted_at`, dann `id`) — der Audit-Lesezugriff auf einen
  zerstörenden Schreibvorgang (ADR-0050 §12; `portfolixir.merges.list`).
  Jedes Protokoll trägt `id`, `kind` (`cash_account`, `securities_account`
  oder `security`), `source` `{id, name}` (der Name, den die
  Zusammenführung festgehalten hat, weil die Quelle nicht mehr existiert),
  `target` `{id, name, merged_into}` (`merged_into` ist `null`, solange das
  Ziel existiert, sonst die id, in die eine spätere Zusammenführung es
  überführt hat, bis zum lebenden Ende verfolgt), `portfolio_id` (`null` für
  ein Wertpapier), `actor_type`, `actor_label` (bei einem API-Token der Name
  des Token-Eintrags, der sie ausgeführt hat, wie im Journal), `inserted_at`
  und `manifest_summary`: das `manifest` des Protokolls, in dem jede Liste durch
  ihre Anzahl ersetzt ist — verschobene, angepasste und gelöschte Buchungen,
  angehängte Namen, verschobene und verworfene Kurse —, neben
  `transactions.deleted` (weiterhin jede Buchung, die die Zusammenführung
  entfernt hat) `transactions.deleted_by_reason`, dieselben Zeilen je Grund
  gezählt (`internal_transfer`, `collapsed_duplicate`, `folded_anchor`,
  `collapsed_split`; nur die vorkommenden Gründe, `{}` wenn keine), und die
  Wahl des Operators, wie gegeben — `collapse_key_equal` nur, wo die
  Zusammenführung gleiche Buchungspaare hatte, bei einer
  Wertpapier-Zusammenführung `identity_choice` und `isin_changed_on` nur, wo
  sie diese Wahl getroffen hat (ein Protokoll einer früheren Version kann sie
  tragen, wie sie geschickt wurden). `meta` trägt `order`, `count` und `limit`. `limit`
  folgt der Listen-Familie: Standard 100, gedeckelt bei 1000, und null, eine
  negative Zahl oder keine Zahl antwortet `422`. Der Operator liest dieselben
  Protokolle mit denselben Zahlen unter **Zusammenführungen** am Ende von
  „Konten & Depots“ (Sprint 17; das Datum in der Zeile „zusammengeführt aus“
  des Überlebenden führt zu seinem Eintrag).

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
  `limit` behält die neuesten Zeilen (Standard 10000, max. 50000; null,
  negativ oder nicht numerisch ist ein `422`).
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
  der Wertpapierwährung), `settlement_amount` (der Handelsbetrag in der
  Kontowährung, vor Gebühren und Steuern, die ebenfalls in der Kontowährung
  erfasst werden) und `settlement_fx_rate` (Einheiten der
  Kontowährung je einer Einheit der Wertpapierwährung). Fehlt der Kurs, werden
  jedoch beide Beträge geliefert, wird er als `settlement_amount / security_amount`
  abgeleitet (der tatsächliche Kurs des Brokers); eine Währungsabweichung ohne Kurs
  und ohne Beträge zur Ableitung wird abgelehnt. Die Einstandsbasis bleibt in der
  Wertpapierwährung, sodass die positionsbezogene G/V währungsehrlich ist. Alle
  drei sind Decimal-Strings und bei Buchungen in gleicher Währung `null`.
  **Geldbetrag und Abrechnung müssen übereinstimmen** (#395): Das `gross_amount`
  eines währungsübergreifenden Kaufs (der gezahlte Betrag, einschließlich
  Gebühren und Steuern) muss `settlement_amount + fees + taxes` sein, das eines
  Verkaufs (der erhaltene Betrag) `settlement_amount - fees - taxes`, auf 0,01
  genau bei voller Genauigkeit verglichen; sonst antwortet der Schreibzugriff mit
  422 und einem `gross_amount`-Fehler, der den abgeleiteten Betrag nennt.
  **Ohne `gross_amount`** bucht das Hauptbuch `quantity × price` (bei einem
  Kauf zuzüglich, bei einem Verkauf abzüglich Gebühren und Steuern) als
  Geldbetrag, und genau das wird verglichen: Ein Handel, der in der Währung des
  Wertpapiers bepreist und ohne Geldbetrag gesendet wird, antwortet mit 422
  auf `gross_amount` und nennt den Betrag, der gebucht würde, und den, den die
  Abrechnung ergibt — sende den Betrag, den der Broker abgerechnet hat. Ein
  Handel, der einen `settlement_fx_rate` trägt, aber weder `gross_amount`
  noch `settlement_amount`, wird ebenso abgelehnt, mit 422 auf
  `gross_amount` und dem Betrag, der gebucht würde: Ein Kurs ist nicht der
  Betrag, den der Broker abgerechnet hat, und nichts wird aus ihm
  abgeleitet. Die Prüfung läuft beim Anlegen und bei einem `PATCH`, das `gross_amount`,
  `settlement_amount`, `fees`, `taxes`, `type`, `currency_code`,
  `cash_account_id` oder `securities_account_id` ändert, oder bei einer
  Buchung ohne `gross_amount` ihre `quantity` oder ihren `price` — ein `PATCH`
  der Notiz oder des Datums einer älteren Buchung wird deswegen nie
  abgelehnt.
- `GET /api/v1/transactions/:id` liefert eine Transaktion.
- `PATCH /api/v1/transactions/:id` aktualisiert eine Transaktion (z. B. um eine
  falsch importierte Buchung zu korrigieren); die Validierung je Art gilt weiter.
  Eine importierte Zeile behält ihren Inhalts-Hash, und ein Saldo-Snapshot
  oder ein Split trägt nie einen (ADR-0050 §1): Wird der `type` einer
  importierten Zeile auf `balance_adjustment` oder `split` geändert, antwortet
  die API mit 422 auf `errors.type`. Eine gespeicherte **Split**-Zeile ändert
  nur ihre `notes` (E25 S6): Eine Änderung an `date`, `security_id`,
  `portfolio_id`, `type` oder am Verhältnis antwortet mit 422 und nennt das
  Feld, denn ein Split wird über `POST /api/v1/splits` gebucht, dessen
  Prüfungen eine allgemeine Änderung umgehen würde. Ein falscher Split wird
  als Ganzes gelöscht (`DELETE /api/v1/splits/:transaction_id`, unten) und
  neu gebucht. Ein Kauf oder Verkauf, der seinen Betrag (`gross_amount`) und
  keinen `settlement_amount` speichert, hält seinen Betrag mit seinen Zahlen
  zusammen (ADR-0053, Ergänzung vom 2026-11-02, #1371): Eine Änderung von
  `quantity`, `price`, `fees` oder `taxes` oder des `type` zwischen Kauf
  und Verkauf muss auch `gross_amount` angeben,
  sonst antwortet die API mit 422 auf `errors.gross_amount` ("is required
  when quantity, price, fees, taxes or buy/sell change on a booking that
  stores its cash"); der angegebene Betrag muss zu Menge × Kurs plus Gebühren und
  Steuern bei einem Kauf, abzüglich bei einem Verkauf, passen, sonst
  antwortet sie mit 422 "does not match quantity × price, fees and taxes —
  expected <Betrag>". Passen heißt: beide Seiten auf zwei Stellen gerundet,
  wie ADR-0053 §2 eine importierte Zeile vergleicht, höchstens 0,01 plus
  |Menge| × eine halbe Einheit der letzten Stelle des Kurses (gelesen auf
  zwei bis sechs Stellen) auseinander, die Rundung eines importierten
  Kurses, erlaubt nur, solange die Änderung den Kurs so lässt, wie er
  gespeichert ist: Ein Kurs, den die Änderung setzt, ist exakt und wird
  daher auf den Cent geprüft (10 neu zu 81,00: 0,01; eine korrigierte
  Gebühr bei 10 zu gespeicherten 80,00: 0,06). Ein allein angegebener
  `gross_amount`, der vom gespeicherten abweicht, wird ebenso gegen die
  gespeicherten Zahlen geprüft. Eine Änderung keiner davon
  (eine Notiz, ein Datum, ein Konto) braucht keinen Betrag. Der gespeicherte
  Betrag ist die Zahl des Brokers und wird nie neu abgeleitet; eine
  Fremdwährungszeile ohne ihre Beine wird in der Währung geprüft, in der sie
  gespeichert ist. Eine Änderung, die mit einem gleichzeitigen Schreibvorgang auf
  denselben Zeilen kollidiert, etwa einer Kontozusammenführung, und dabei
  unterliegt, antwortet mit **409** und nur `errors.detail`: Es wurde nichts
  gespeichert; die Transaktion neu lesen und die Änderung wiederholen.
- `DELETE /api/v1/transactions/:id` löscht eine Transaktion. Da Trades und
  Bestände abgeleitet sind, korrigiert oder entfernt das Korrigieren oder Entfernen
  der Transaktion auch sie. Mit einer importierten Buchung geht ihr
  Inhalts-Hash, ein erneuter Import derselben Datei bucht sie also wieder
  (einen Hash legt nur eine Zusammenführung still, ADR-0050 §3). An einer
  Split-Zeile löscht der Aufruf nur diese Zeile; die übrigen Zeilen des
  Splits halten das Ereignis.
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
  zweiter Split am selben Tag für dasselbe Wertpapier wird mit `422` an
  `date` abgelehnt und benennt das bestehende Ereignis, seine Transaktion und
  sein Portfolio mit ihren ids (ein wiederholter Timeout kann den
  multiplikativen Effekt nicht verdoppeln); ein Datum in der
  Zukunft und ein Wertpapier ohne Bestand am Wirksamkeitsdatum werden
  ebenfalls mit `422` abgelehnt. Die Splits eines Wertpapiers, jeder mit
  seinem eigenen Betrag gezählt (`2:1` und `1:2` zählen beide 2), dürfen sich
  einschließlich des neuen auf höchstens `10^12` multiplizieren; ein
  Verhältnis darüber liefert bei Vorschau und Buchung `422` an `ratio`, und
  nichts wird geschrieben (E25 S4). Der generische Endpunkt
  `POST /api/v1/transactions` lehnt die Art `split` ab — nur diese beiden
  Routen buchen einen Split.
- `DELETE /api/v1/splits/:transaction_id` löscht einen Split so, wie er
  gebucht wurde, als eine Tatsache (Sprint 18 U1, #912): von einer beliebigen
  seiner Zeilen aus jede `split`-Zeile mit demselben Wertpapier, Datum und
  gekürzten Verhältnis — eine je Portfolio — in einer Transaktion, jede Zeile
  mit ihrem Vorher-Bild journalisiert. Die Antwort ist `200` mit
  `data.transactions`, den gelöschten Zeilen im regulären Transaktionsformat,
  nach Portfolio geordnet. Danach trägt kein Portfolio das Ereignis mehr:
  Bestände zählen ohne ihn, die Kurs-Lesepfade bereinigen nicht mehr um ihn,
  und `POST /api/v1/splits` bucht das korrigierte Verhältnis am selben Tag.
  Eine unbekannte oder schon gelöschte Zeile liefert `404`; eine Buchung
  anderer Art liefert `422` an `transaction_id` und nennt
  `DELETE /api/v1/transactions/:id`; scheitert eine Zeile, wird nichts
  gelöscht. Die übrigen Splits des Wertpapiers bleiben.
- `GET /api/v1/portfolios/:portfolio_id/holdings` listet abgeleitete Bestände
  eines Portfolios, eine Zeile je (Depot, Wertpapier). Jede Zeile trägt
  `quantity`, einen gleitenden Durchschnitt `avg_cost` und `cost_basis`
  (preisbasiert, sodass Gebühren und Steuern nicht in die Stückkosten einfließen),
  den `latest_price`, `market_value` und `unrealized_pnl_abs`/`unrealized_pnl_pct`
  gegen diesen Preis, plus `security_name` und `currency_code`. Diese Größen
  sind in der **eigenen** Währung des Wertpapiers — durch das Kostenpaar der
  Ledger-Faltung erzwungen (ADR-0033), nicht länger eine Annahme. Seit den
  Issues #1316 und #1332 wird eine Zeile nach der Regel bepreist, die die
  Summe der Bewertung verwendet (ADR-0010): der letzte Schlusskurs, sonst
  der letzte eigene Handelspreis (ein Kauf oder Verkauf, über alle
  Portfolios; ein in einer anderen Währung gebuchter Handel wird zum
  zuletzt gespeicherten Kurs in die des Wertpapiers umgerechnet), sodass
  die Zeilen diese Summe ergeben. Jede Zeile nennt sie in `price_source`
  (`"quote"` oder `"trade"`) und `price_date`, und
  `computation_basis.latest_price` nennt die Regel. Nur ein Bestand ohne
  Kurs und ohne eigenen Handel liefert `null` für Preis, Marktwert und
  G/V, mit `price_source` `null`: er steht in keiner Summe. Jede Zeile
  trägt zusätzlich die
  ADR-0033-Zerlegung des G/V in Basiswährung: `base_cost` (der
  Abrechnungsbetrag, das gezahlte Geld vor Gebühren und Steuern, mit seiner
  `base_currency`),
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
  benennt, welches Feld in welcher Währung ist, und ein `as_of`-Datum. Seit
  Issue #1142 behält ein Bestand mit `cost_basis` `"0"` (Stücke, die ohne
  Kosten eingeliefert wurden, etwa aus einem Spin-off, oder zu einem Kurs
  von 0 gekauft) sein `unrealized_pnl_abs` und liest `unrealized_pnl_pct`
  `null`, nie `"0"`: Eine Rendite auf keine Kosten ist unbestimmt, und `0`
  läse sich als unverändert. `computation_basis.unrealized_pnl_pct` der
  Antwort nennt die Regel. Ebenso liest ein Bestand mit `base_cost` `"0"`
  `price_return_pct`, `currency_return_pct` und `total_return_base_pct`
  `null` neben seinen drei Beträgen, und `computation_basis.decomposition_pct`
  nennt die Regel.
  Seit Issue #1212 sagt `computation_basis.fees_and_taxes_in_figures`, was
  die Kosten zählen: `cost_basis`, `avg_cost` und `base_cost` sind ohne
  Gebühren und Steuern der Käufe, und G/V und Zerlegung messen gegen sie,
  während die `basis` eines geschlossenen Trades im Trades-Endpunkt sie
  enthält, sobald die Stücke verkauft sind. Keine Zahl hat sich geändert:
  Ein Kauf von 10 zu 100 USD, abgerechnet mit 790,00 EUR und 6,00 EUR
  Gebühren und Steuern, liest `base_cost` `"790"`.
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
  `limit` begrenzt die Jahresmatrix auf ihre neuesten Jahre (Standard 100,
  max. 1000); `computation_basis.window` nennt den Schnitt, wenn Jahre
  wegfielen, und die Antwort nennt das angewandte `limit`.

  Seit Issue #807 trägt die Payload zusätzlich **`trades`** — die
  abgeschlossenen Rundläufe selbst, neuester Schluss zuerst, je mit
  `security_id`, `security_name`, `open_date`, `close_date`,
  `holding_period_days`, `quantity`, `basis`, `proceeds`,
  `realized_pnl_abs`/`_pct` in der Währung des Trades und `realized_base` in
  der Basiswährung — und **`summary`**: `realized_total`, `hit_rate` (der
  Anteil der Trades mit streng positivem Ergebnis; ein Nullergebnis zählt
  nicht als Treffer) und `average_holding_period_days`. Die drei Zahlen
  stammen aus **derselben** konvertierten Menge wie die Matrix; ohne
  abgeschlossene Trades sind `hit_rate` und `average_holding_period_days`
  `null` statt `0`. `limit` schneidet nur die Jahre der Matrix.

  Seit Issue #984 trägt jeder Trade zusätzlich **`annualized_return`**: die
  geldgewichtete Rendite des Rundlaufs pro Jahr, als Bruch (`"0.304701"` sind
  30,47 % im Jahr). Es ist der XIRR-Löser aus ADR-0034 §2 (Act/365) über die
  eigenen Zahlungen des Trades — der Kauf jedes verbrauchten Lots an seinem
  Eröffnungstag mit seinen anteiligen Kosten (Stückzahl × Kaufkurs plus
  Kaufgebühren und -steuern anteilig zur entnommenen Stückzahl) und der Erlös
  des Verkaufs am Schlusstag — in der Währung des Trades; annualisiert wird
  also `realized_pnl_pct`, nicht `realized_base`. Gerundet auf 6 Stellen,
  und ein Verlust bleibt über −1. Der Wert ist `null` mit
  **`annualized_return_reason`** `no_cost_basis`, wenn `basis` des Trades
  `"0"` ist (seit Issue #1142; dieser Grund kommt zuerst, denn ohne Kosten
  gibt es nichts zu annualisieren, wie lange der Trade auch gehalten wurde),
  `null` mit `holding_period_under_365_days`, wenn die
  `holding_period_days` des Trades unter 365 liegen (ADR-0034 §2 annualisiert
  kein Fenster unter einem Jahr: 5 % in 14 Tagen wären rund 257 % im Jahr),
  und `null` mit dem Grund des Lösers (`no_sign_change`, darunter ein
  Totalverlust; `no_root`; `amount_out_of_range`), wenn kein Satz die
  Zahlungen löst. Dividenden und Zinsen während der Haltedauer sind nicht
  enthalten. `computation_basis.annualized_return` nennt die Regel.

  Seit Issue #1142 liest ein Trade mit `basis` `"0"` — ein Kauf zu einem Kurs
  von 0 ohne Gebühren oder Steuern, eine Bonus- oder Gratisaktie —
  `realized_pnl_pct` `null`, nie `"0"`: `realized_pnl_abs` und
  `realized_base` nennen das Ergebnis weiter, aber eine Rendite auf keine
  Kosten ist unbestimmt, und `0` läse sich als unveränderter Trade.
  `computation_basis.realized_pnl_pct` nennt die Regel.

  Seit Issue #984 nennt die Payload außerdem die Verkäufe, denen der
  FIFO-Matcher keinen Kauf zuordnen konnte, in **`unmatched_sells`**: ein
  `count` und, neueste zuerst, je Verkauf `security_id`, `security_name`,
  `date` und die `quantity`, die kein Lot deckte. Stücke aus einer
  Einlieferung eröffnen keinen Lot, ihr Verkauf ist also kein abgeschlossener
  Trade; ein Verkauf über die gekauften Stücke hinaus schließt, was er kann,
  und der Rest steht hier. Beides fehlt in den Kennzahlen, der Liste und der
  Matrix; `computation_basis.unmatched_sells` sagt es. Der Trades-Read des
  Wertpapiers unten führt dieselben Verkäufe als `orphan_sells`.

  Seit Issue #1108 (die Ergänzung von ADR-0015 vom 07.10.2026) werden die
  Gebühren und Steuern eines Trades in der Währung seines
  Verrechnungskontos gelesen, der Währung des Geldbeins, zu dem sie gehören:
  Ein währungsübergreifender Trade, gebucht in der Wertpapierwährung, rechnet
  sie zu seinem eigenen gespeicherten `settlement_fx_rate` (Gebühr ÷ Kurs,
  Kontoeinheiten je einer Wertpapiereinheit) in diese um, nie zu einem
  Hub-Kurs, bevor sie in `basis` und `proceeds` eingehen. `basis`,
  `proceeds`, `realized_pnl_abs` und `realized_pnl_pct` stehen also im
  `currency_code` des Trades, und `realized_base` ist das Geld, das die Runde
  bewegt hat, wenn Broker- und Hub-Kurs übereinstimmen und der Hub-Kurs
  sich zwischen Kauf und Verkauf nicht bewegt hat: 10 Stück, gekauft zu
  100 USD für 800,00 EUR mit 6,00 EUR Gebühren und Steuern und verkauft zu
  120 USD für 960,00 EUR mit 3,00 EUR Gebühren, lesen `basis` `"1007.5"`,
  `proceeds` `"1196.25"`, `realized_pnl_abs` `"188.75"` und `realized_base`
  `"151"`. Ein Trade in der Kontowährung (die Form eines Portfolio-
  Performance-Imports) addiert sie wie erfasst. Seit Issue #1198 (die
  Ergänzung von ADR-0015 vom 09.10.2026) steht ein geschlossener Trade im
  `currency_code` seines Verkaufs, gleich wie seine Lots gebucht wurden:
  Jedes Lot geht über seine eigenen gespeicherten Beine in diese Währung
  ein, nie über einen nachgeschlagenen Kurs — ein importiertes Lot, in der
  Wertpapierwährung verkauft, zu `security_amount` ÷ Stückzahl, seine
  Gebühren und Steuern ÷ seinem eigenen `settlement_fx_rate`; ein Lot aus
  dem Buchungsformular, in der Kontowährung verkauft, zu
  `settlement_amount` ÷ Stückzahl, seine Gebühren und Steuern wie erfasst.
  Ein importierter Kauf, über das Buchungsformular verkauft, liest so
  `basis` `"1007.5"`, `realized_pnl_abs` `"188.75"` USD und `realized_base`
  `"151"`. Ein solcher Trade, dessen Verkauf ein in einer anderen Währung
  gebuchtes Lot schließt, liest `realized_base` als das Geld, das seine
  Buchungen bewegt haben, wo der Verkauf und jedes Lot, das er schließt, ihr
  gespeichertes Bein in der Basiswährung tragen: die Abrechnung des
  Verkaufs abzüglich der der Lots (anteilig), Gebühren und Steuern wie
  erfasst, ohne nachgeschlagenen Kurs (die Notiz vom 31.10.2026 zur
  Ergänzung von ADR-0015). Hat sich der Hub-Kurs zwischen Kauf und Verkauf
  bewegt, ist das nicht das Ergebnis des Trades zum Kurs des Schlussdatums:
  Eine Franken-Aktie, für 1.004,00 EUR bei 0,94 Franken je Euro importiert
  und über das Buchungsformular für 1.154,90 EUR bei 0,95 verkauft, liest
  `realized_base` `"150.9"`, wo die Umrechnung ihrer 153,39 CHF zum
  Schlussdatum 161,46 las. Jeder Trade nennt seinen Weg in
  **`realized_base_source`**, `"settlement_legs"` oder `"close_date_rate"`
  (jeder andere Trade, einer, dessen Verkauf und Lots in einer Währung
  gebucht sind), und `computation_basis.realized_base` nennt beide. Seit
  Issue #1317 nennen auch `computation_basis.reference` und
  `computation_basis.gaps` beide Wege: Die Referenz ist für
  `close_date_rate` der am Schlussdatum gespeicherte Hub-Kurs (nie der
  eines Nachbartags) und für `settlement_legs` kein Kurs, und die Lücken
  sagen, dass ein über seine Abrechnungsbeine gelesener Trade nie unter
  `no_rate` ausgeschlossen wird. Ein
  Lot ohne das nötige Bein (oder in der Währung eines anderen
  Kontos gebucht) oder ein Lot oder Verkauf in einer dritten Währung (eine
  vor Issue #1199 gespeicherte Zeile, auch wenn beide sie teilen) macht den
  Trade unverfügbar: Der Trades-Read behält ihn mit den eigenen Zahlen seines
  Verkaufs (`proceeds`, `sell_fees`, `avg_sell_price`), `null` für
  `basis`, `avg_buy_price`, `buy_fees`, `buy_taxes`, `realized_pnl_abs`,
  `realized_pnl_pct` und `annualized_return`, `unavailable_reason`
  `"missing_settlement_leg"` und `lots_missing_leg` (`open_date`,
  `currency_code` jedes solchen Lots; ein Verkauf in einer dritten Währung
  nennt jedes Lot, das er schließt); `GET /api/v1/realized_gains` lässt
  ihn aus `trades`, der Matrix und der Zusammenfassung und zählt ihn in
  `excluded`, dessen `by_reason` `missing_settlement_leg` von `no_rate`
  (ein Verkauf ohne Kurs am Schlussdatum) unterscheidet. Jeder verfügbare
  Trade trägt `unavailable_reason` `null` und `lots_missing_leg` `[]`.
  `computation_basis.fees_and_taxes` nennt die Regel. Ein neuer Kauf oder
  Verkauf in weder der Währung seines Wertpapiers noch der seines
  Verrechnungskontos antwortet 422 auf `currency_code` und nennt beide
  (Issue #1199).
  Seit Issue #1310 unterscheidet ein unverfügbarer Trade seine beiden
  Ursachen. `unavailable_reason` ist `"third_currency"`, wo der Verkauf
  oder ein Lot, das er nennt, weder in der Währung des Wertpapiers noch in
  der seines Kontos bepreist ist (eine vor Issue #1199 gespeicherte Zeile),
  was kein Kurs behebt: Abhilfe ist, Währung oder Beträge der gespeicherten
  Buchung zu korrigieren. Sonst ist er `"missing_settlement_leg"`, dessen
  Abhilfe ein Kurs für das Datum des Lots ist oder der Gegenwert in der
  Währung des Verkaufs auf der Buchung. Jeder Eintrag von
  `lots_missing_leg` trägt seinen eigenen `reason`, einen der beiden, sodass
  ein Trade, der ein Lot ohne Bein und ein Lot in einer dritten Währung
  schließt, jedes benennt. Ist der Verkauf selbst in einer dritten Währung
  bepreist, sind auch `proceeds`, `sell_fees` und `sell_taxes` `null`, denn
  seine Gebühren stehen in der Währung seines Kontos, und keine Zahl unter
  dem Währungscode des Verkaufs könnte sie nennen;
  `annualized_return_reason` liest den Grund des Trades.
  `GET /api/v1/realized_gains` zählt einen solchen Trade unter
  `excluded.by_reason.third_currency`, getrennt von
  `missing_settlement_leg` und `no_rate`.
  Zwei weitere Ursachen, die kein Kurs behebt, haben eigene Werte, je am
  Trade, am Lot und unter `excluded.by_reason`:
  `"other_account_currency"`, wo ein Lot über ein Konto bezahlt wurde, das
  weder in der Währung des Wertpapiers noch in der des Verkaufs geführt ist,
  sodass keines seiner Beine je in der Währung des Verkaufs stehen kann
  (eine Dollar-Aktie, über ein Dollar-Konto gekauft und über ein Euro-Konto
  verkauft; das Nachladen gibt dem Verkauf seine Beine, und der Trade bleibt
  unverfügbar; Abhilfe: Währung oder Beträge der gespeicherten Buchungen
  korrigieren), und `"zero_amount"`, wo einem Lot mit Betrag null, einer
  Gratiszuteilung, sein Bein fehlt, das das Nachladen der Kurse nicht
  ergänzt (Issue #1311; Abhilfe: die Beträge von Hand auf der Buchung
  erfassen). Der Grund eines Trades ist der erste, den seine Lots nennen,
  aus `third_currency`, `other_account_currency`, `zero_amount` und
  `missing_settlement_leg`.
- `GET /api/v1/external_flows` (Issue #725) liefert das
  Ein-/Auszahlungs-Rollup: die gebuchten externen **Cash**-Flüsse (`deposit`
  und `removal`) über alle Portfolios, je Jahr und Monat mit Einzahlungen,
  Auszahlungen und Netto. Bewusst enger als das `invested_capital` des
  Performance-Laufs, das zusätzlich ein-/ausgelieferte Wertpapiere zum
  Marktwert und Saldo-Snapshot-Residuen zählt — der Unterschied steht in
  `computation_basis.excludes`. FX-Basis wie in der Schwester-Facette:
  EUR-Hub zum Kurs des eigenen Buchungstags, unkonvertierbare Flüsse
  ausgeschlossen und nach Verrechnungskonto benannt. Jeder Fluss wird in der
  Währung seines Verrechnungskontos gelesen, nie in der der Buchung: eine in
  einer anderen Währung mit gespeichertem Abrechnungskurs (ADR-0015) erfasste
  Einzahlung ist das Geld, das dem Konto gutgeschrieben wurde, und
  `computation_basis.currency` nennt die Regel (Issue #1107). Die menschliche
  Sicht ist `/cashflow?tab=flows`.
  `limit` begrenzt die Jahresmatrix auf ihre neuesten Jahre (Standard 100,
  max. 1000); `computation_basis.window` nennt den Schnitt, wenn Jahre
  wegfielen, und die Antwort nennt das angewandte `limit`.
- `GET /api/v1/costs` (Issue #726) liefert das Kosten-Rollup: Gebühren und
  Steuern über alle Portfolios, **nur auf Übersichtsebene**, je Jahr und
  Monat mit Jahressummen für Gebühren, Steuern und beides zusammen. Seit
  Issue #1210 trägt jeder Monat neben `fees` und `taxes` seine eigene Summe
  `total` — die Gebühren plus die Steuern dieses Monats, als Decimal-Strings
  (`{"fees": "5", "taxes": "1", "total": "6"}`) —, und
  `computation_basis.totals` nennt, wie die Summe eines Monats und eines
  Jahres gebildet wird. Die
  Serie summiert die Gebühren- und Steuer-**Nebenbeträge** jeder Transaktion
  plus die eigenständigen `fee`-/`tax`-Buchungen; `tax_refund` wird gegen
  die Steuern verrechnet. Bruttobeträge werden nie summiert — das Brutto
  eines Kaufs **enthält** seine Nebenbeträge, das eines Verkaufs ist um sie
  **gemindert**, eine Bruttosumme beschriebe also etwas anderes. Diese Regel
  steht in `computation_basis.series`. FX-Basis wie in den
  Schwester-Facetten: EUR-Hub zum Kurs des eigenen Buchungstags,
  unkonvertierbare Kosten ausgeschlossen und nach **Währung** benannt. Seit
  Issue #1107 wird jeder Kostenbetrag in der Währung seines
  Verrechnungskontos gelesen, der Währung des Geldbeins, zu dem er gehört,
  so wie der Performance-Lauf die Handelskosten liest: Die Gebühren und
  Steuern eines währungsübergreifenden Trades werden aus der Kontowährung
  umgerechnet, nie aus der Wertpapierwährung, und ein unkonvertierbarer
  Betrag wird nach der Währung des Verrechnungskontos benannt; eine Buchung
  ohne Verrechnungskonto wird in ihrer eigenen gelesen.
  `computation_basis.currency` nennt die Regel. Die
  menschliche Sicht ist `/cashflow?tab=costs`.
  `limit` begrenzt die Jahresmatrix auf ihre neuesten Jahre (Standard 100,
  max. 1000); `computation_basis.window` nennt den Schnitt, wenn Jahre
  wegfielen, und die Antwort nennt das angewandte `limit`.
- `GET /api/v1/sales/hindsight` (`portfolixir.sales.hindsight`, in jedem
  Profil; FR-50, Idee I18; Sprint-25-Plan D-3)
  beantwortet, **was jedem Verkauf entging**: eine Zeile je Verkaufsbuchung
  (Typ `sell`, ein Verkauf ohne vorherigen Kauf eingeschlossen; eine
  Auslieferung ist kein Verkauf, sie bewegt Stücke ohne Preis), neueste
  zuerst, mit der Kursrendite des verkauften Wertpapiers in EUR über vier
  Spannen nach dem Verkauf. Nur lesend; nichts wird gespeichert, jeder
  Lesezugriff leitet die Zahlen aus den in diesem Moment gespeicherten
  Schlusskursen und Kursen ab. Optionale `portfolio_id`, `security_id`,
  `from` und `to` (das Verkaufsdatum, beide einschließlich) grenzen die
  Zeilen ein; `limit` deckelt sie (Standard 100, höchstens 500), und die
  Antwort nennt es mit `truncated`. Ein optionales `benchmark=` ist das des
  Benchmark-Vergleichs (ADR-0046): `rate:<decimal>`, ein fester Jahreszins
  mit täglicher Verzinsung, oder `security:<id>`, jedes Wertpapier mit einem
  gespeicherten Kurs, mit oder ohne `is_benchmark`, abgelehnt wie beim
  Vergleich unten; `computation_basis.benchmark_security` nennt seine Art wie
  dort (`null` ohne Wertpapier); ohne es nennt jede
  Spanne nur die eigene Rendite des Wertpapiers. Die Antwort ist `{as_of,
  spans, benchmark, include, rows, limit, truncated, computation_basis}`,
  wobei `include` das angewandte `include` nennt (`[]` ohne eines). Eine Zeile
  trägt `sale_id` (die Transaktions-ID der Buchung), `portfolio_id`,
  `securities_account_id`, `date`, `security` `{id, name, currency_code}`,
  die gebuchten `quantity`, `price`
  und `currency_code` und `start`: den Schlusskurs, der für den
  Verkaufstag steht (der letzte positive Schlusskurs an oder vor ihm,
  höchstens 7 Tage älter), `{stands_for, date, close, stored_close, source,
  fx_rate, eur_value}`, oder `null` mit `start_reason`. Der gebuchte Preis
  steht daneben und geht in keine Zahl ein: Beide Seiten werden von einem
  Schlusskurs aus gemessen. Jede der vier `spans` trägt `span` (`1m`, `3m`,
  `12m`: der Verkaufstag um Kalendermonate verschoben; `latest`: das Datum
  des neuesten gespeicherten Schlusskurses des Wertpapiers, höchstens
  heute), `end_on`, `days`, `status`, `reason`, `security` `{return, start,
  end}`, `benchmark` `{return, start, end}` (`start` und `end` bei einem
  Zins `null`) und `difference`, die Rendite des Wertpapiers minus die der
  Benchmark. `status` ist `complete`, `pending` (die Spanne endet nach
  heute; keine Zahl) oder `incomplete` mit `reason` `no_start_close`,
  `no_end_close`, `no_fx_rate` oder `no_benchmark_close`, wobei die eigene
  Zahl des Wertpapiers erhalten bleibt. Ein Verkauf bei einem Schlusskurs
  von 100, dem einen Monat später 110 folgen, ergibt für `1m` `"0.1"`;
  gegen eine Benchmark von 200 auf 210 eine Benchmark-Rendite von `"0.05"`
  und eine Differenz von `"0.05"`. Es ist eine Kursrendite: Ausschüttungen
  nach dem Verkauf sind nicht gebucht, sodass das Entgangene eines
  Dividendenzahlers unterschätzt ist, und `computation_basis`
  (Eingangsreihe, Fenster, Referenz, Lücken, `price_only`, `sales`,
  `booked_price`) sagt das. Kein Feld fällt ein Urteil. Eine ungültige ID,
  ein ungültiges Datum, `limit` oder `benchmark` ergibt `422` mit ihrem
  Namen, `to` vor `from` `422` auf `to`; eine unbekannte ID ergibt keine
  Zeilen. Die Ansicht für den Menschen ist **Nach dem Verkauf** unter der
  Trade-Liste von `/cashflow?tab=realized` und im Trades-Tab eines
  Wertpapiers (Sprint 26), berechnet von derselben Funktion.

  **Was ein Umschichten kostete** (`include=reinvestment`; I18 Modus 3,
  ADR-0057): Jede Zeile erhält `reinvestment`, die Käufe, in die das Geld
  des Verkaufs floss, **per Regel gefunden, nie ausgewählt**. Der Erlös (der
  gebuchte Geldbetrag des Verkaufs auf seinem Konto, nach Gebühren und
  Steuern) geht in die Käufe, die dasselbe Konto belasten, datiert vom
  Verkaufsdatum bis 30 Kalendertage danach, in ein anderes Wertpapier als
  das verkaufte; der älteste Erlös zuerst (nach Verkaufsdatum), jeder Kauf
  nimmt höchstens seine eigene Belastung, sodass ein größerer Kauf nur
  teilweise finanziert ist. Verkäufe desselben Tages und Käufe desselben
  Tages teilen **anteilig** (jeder Verkauf nach seinem verbleibenden Erlös,
  jeder Kauf nach seiner verbleibenden Belastung), nie nach Buchungs-ID:
  Eine Buchung, die gelöscht und unverändert neu gebucht wird, bewegt keine
  Zahl. Ein `tax_refund` des verkauften Wertpapiers am Verkaufsdatum auf
  demselben Konto gehört zum Erlös dieses Verkaufs, gleich in welcher
  Reihenfolge beide gebucht wurden. Der Block trägt `status`
  (`matched` oder `no_match`), `reason` (`no_buy_within_30_days`,
  `proceeds_taken_by_earlier_sale`, `no_cash_account`), `cash_account_id`,
  `currency_code` (die des Kontos), `proceeds`, `buys` (`buy_id`, `date`,
  `security`, `quantity`, `cash_debit`, `amount_taken`, `share_of_buy`),
  `days_to_first_buy` (Kalendertage vom Verkaufsdatum bis zum ersten
  zugeordneten Kauf, `0` am Verkaufstag), `share_of_proceeds_matched` (das
  `a` der ADR: die Summe, die die Käufe nahmen, durch den Erlös) und
  `unallocated` (Geld, das wartete, bleibt außen vor). Je FR-50-Spanne ist `kept` `a` × die verkaufte
  Stückzahl × der Schlusskurs des verkauften Wertpapiers am Ende, `switched`
  der Anteil jedes Kaufs × seine Stückzahl × der Schlusskurs des gekauften
  Wertpapiers am Ende (ein Kauf nach dem Ende zählt als Geld in der Währung
  seines Kontos zum Kurs des Endes), und `difference` ist `switched +
  taxes_apart − kept`, beides in EUR und **vor Steuern**: Die Gebühren
  stecken darin und sind als `fees_inside` genannt (die eigenen Steuern
  eines Kaufs sind Teil seiner Belastung, also in der Differenz und nicht in
  `fees_inside`); die Steuern des Verkaufs sind als `taxes_apart` genannt
  (eine Erstattung negativ) und werden zurückaddiert, weil die latente
  Steuer der behaltenen Position nicht gebucht ist. Sie werden als Geld zum
  Nennwert zurückaddiert, es ist also kein vollständiger Vergleich vor
  Steuern: Die Differenz weicht um etwa `−taxes_apart` × die Rendite des
  gekauften Wertpapiers seit dem Kauf ab. Ein Verkauf, dessen gebuchter
  Geldbetrag nicht positiv ist (eine Ausbuchung zum Preis 0), ergibt
  `no_cash_account`. Es ist **nur Kurs**: `income_apart` nennt die Ausschüttungen
  der gekauften Positionen und wird nie addiert. Eine Spanne ist `pending`
  oder `incomplete` mit `side` (`kept` oder `switched`) und ihrem Grund. Ein
  Verkauf über 1000, dessen Geld 5 Stück zu 200 kaufte, bei einem
  verkauften Schlusskurs von 100 auf 110 und einem gekauften auf 210, ergibt
  für `1m` `kept` `"1100"`, `switched` `"1050"` und `difference` `"-50"`.
  `computation_basis.reinvestment` nennt die Regel, das Fenster, die
  Reihenfolge, die Spannen, die Kurse, vor Steuern, nur Kurs, dass Geld
  austauschbar ist (eine Einzahlung dazwischen hätte den Kauf bezahlen
  können), dass Buchungen keine Uhrzeit tragen und dass ein `cash_transfer`
  nicht verfolgt wird. `benchmark=` und `include=reinvestment` lassen sich
  kombinieren. Jeder andere `include`-Wert, ein leerer oder eine Liste
  (`include=reinvestmnt`, `include=`), ergibt `422` auf `include`, sodass
  ein falsch geschriebener `include`-Wert den Block nie stillschweigend
  weglässt. Ein unbekannter Schlüssel wird ignoriert, wie bei jedem Lesen
  (`includ=reinvestment` antwortet `200` ohne den Block); `data` nennt das
  angewandte `include` (`[]` oder `["reinvestment"]`), wie es `benchmark`
  nennt, sodass ein fehlender Block nie stillschweigend fehlt. Kein Urteil
  und keine Summe über alle Umschichtungen.
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
- `GET /api/v1/splits/incomplete` liefert die **Prüfung unvollständiger
  Splits** (#1292): jedes gespeicherte Split-Ereignis (seine Zeilen teilen
  Wertpapier, Datum und gekürztes Verhältnis), dem eine Zeile für ein
  Portfolio fehlt, das das Wertpapier zum Stichtag hielt — die Menge, für die
  `POST /api/v1/splits` bucht. Die FIFO-Lots eines solchen Portfolios
  skaliert der Split, seinen Bestand nicht. Jede Zeile nennt das Wertpapier
  (`security_id`, `security_name`, `isin`), das `date`, die ganzzahligen
  `ratio_numerator` und `ratio_denominator`, die `booked_portfolio_ids` und
  `transaction_ids` der gebuchten Zeilen und `missing_portfolios`, jedes mit
  `portfolio_id`, `portfolio_name` und `quantity_before` (ein
  Decimal-String). Selbstbeschreibend mit `as_of`, `note` und `remedy`:
  buche denselben Split erneut über `POST /api/v1/splits`, das nur die
  fehlenden Zeilen ergänzt, oder lösche ein falsches Ereignis mit
  `DELETE /api/v1/splits/:transaction_id`. Rein lesend und ohne Obergrenze,
  wie der Bericht zu negativen Beständen; nichts wird gebucht oder
  umgeschrieben.
- `GET /api/v1/transactions/rate_only` liefert die **Trades nur mit Kurs**
  (#1290): jeden gespeicherten Kauf oder Verkauf in einer anderen Währung als
  der seines Verrechnungskontos, der einen `settlement_fx_rate`, aber weder
  `gross_amount` noch `settlement_amount` trägt — die Form, die ein neuer
  Schreibzugriff abgelehnt bekommt (H35) —, unabhängig von der Größe der
  Abweichung. Jede Zeile trägt ihre IDs, `security_name`,
  `cash_account_currency_code`, `date`, `type`, `currency_code` und als
  Decimal-Strings `quantity`, `price`, `fees`, `taxes`,
  `settlement_fx_rate`, `booked_cash` (Menge × Kurs plus Gebühren und
  Steuern bei einem Kauf, abzüglich bei einem Verkauf: das Geld, das das
  Ledger bucht), `expected_cash` (dasselbe mit Menge × Kurs × Rate als
  Abrechnungsbetrag) und `difference` (`booked_cash - expected_cash`).
  Selbstbeschreibend mit `as_of`, `note` und `remedy`: trage den vom Broker
  abgerechneten Betrag als `gross_amount` des Trades ein
  (`PATCH /api/v1/transactions/:id`), danach erscheint die Zeile nicht mehr;
  der Settlement-Backfill fasst diese Zeilen nicht an. Rein lesend und ohne
  Obergrenze.
- `GET /api/v1/transactions/cash_mismatch` liefert die **Trades, deren
  Betrag nicht zu ihren Zahlen passt** (#1371; ADR-0053, Ergänzung vom
  2026-11-02): jeden gespeicherten Kauf oder Verkauf mit `gross_amount` und
  ohne `settlement_amount`, dessen Betrag nicht zu Menge × Kurs plus
  Gebühren und Steuern (Kauf) bzw. abzüglich (Verkauf) passt, wie der PATCH
  oben Passen liest (`tolerance_rule` sagt wie) — eine Zeile, die vor der Regel bearbeitet wurde und deren
  Kontostand den gespeicherten Betrag liest, während ihre FIFO-Lots und
  realisierten Gewinne die Zahlen lesen. Jede Zeile trägt ihre IDs,
  `security_name`, `cash_account_id`, `date`, `type`, `currency_code` und
  als Decimal-Strings `quantity`, `price`, `fees`, `taxes`, `stored_cash`,
  `derived_cash`, `difference` (`stored_cash - derived_cash`) und ihre
  `tolerance`; sortiert nach Datum, dann ID. Eine Zeile, die §2 beim Import
  bestanden hat, erscheint nicht. Selbstbeschreibend mit `as_of`, `note` und `remedy`:
  den Betrag im Buchungsformular (Bearbeiten) oder als `gross_amount` mit
  `PATCH /api/v1/transactions/:id` angeben, den abgerechneten oder den, den
  die Zahlen ergeben; eine innerhalb ihrer Toleranz angegebene Zeile
  verlässt die Liste. Rein lesend und ohne Obergrenze; nichts wird umgeschrieben.

  Diese drei Prüfungen haben eine Ansicht für Menschen (Sprint 23): Die
  Datenqualitätszeile der Übersicht nennt jede oberhalb von null, ihr Zähler
  ist die Zeilenzahl des Reads, und verlinkt auf die Transaktionshistorie,
  gefiltert auf genau die Zeilen des Reads — `/transactions?dq=cash_mismatch`,
  `?dq=rate_only`, `?dq=incomplete_split` (die `transaction_ids` eines
  Split-Ereignisses) —, sodass ein Agent dem Betreiber diesen Link geben kann.
  `dq=` ist der Parameter der Seite, nicht der API: `GET /api/v1/transactions`
  kennt keinen solchen Filter, denn diese drei Reads sind seine Zwillinge und
  tragen die Zahlen, die die Seite zeigt.
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
  trägt `price_source: "quote"`. Jede Position trägt `price_date`, das Datum,
  von dem ihr Preis stammt, und das Top-Level `stale_priced_count` zählt die
  Positionen, deren Kurs älter ist als die Datenqualitäts-Schwelle (dieselbe
  Tageszahl wie `?dq=stale_quote`) — das Mittel ist das `is_retired`-Kennzeichen
  des Wertpapiers, auf das der Performance-Lauf reagiert, oder eine
  Kurssynchronisation; eine eingestellte Position wird deshalb nicht gezählt,
  ihr alter Schlusskurs ist erwartet. Das Top-Level `newest_quote_date` ist
  das Datum des neuesten gespeicherten Kurses über die bepreisten, nicht
  eingestellten Positionen (`null`, wenn keine per Kurs bepreist ist) — der
  Aktualitäts-Fakt, den die Kennzahlenleiste der Übersicht zeigt; die
  View-Bewertung trägt beide Felder ebenfalls. Eine Position mit weder Preis **oder** ohne
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
  werden. `unvalued_cash_count` (#1081) zählt solche Konten mit einem Saldo
  ungleich null — das Geld, das `total_cash` und `total_with_cash` auslassen;
  ein leeres steht mit `valued: false` in der Liste und zählt nicht — in jeder
  Form der Abfrage, mit und ohne `include_positions`, sodass auch die
  Roll-up-Abfrage die Lücke nennt; die `valuation_note` nennt die Regel. Die
  Antwort ist selbstbeschreibend (FR-13): sie trägt ein
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
  der Solver konvergiert nicht) oder ein Betrag außerhalb des Bereichs liegt, den
  der eine Gleitkommaschritt des Solvers trägt, was nur unplausible gespeicherte
  Daten erreichen; die Abfrage scheitert an einem solchen Betrag nie, und
  `computation_basis.gaps` nennt diese Fälle (E25 S4). Wertpapiere ohne Kurse werden mit dem zuletzt
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
  Umgang mit Lücken. Ein Verrechnungskonto in einer Fremdwährung zählt an
  jedem Tag null, an dem es Geld hält, während seine Währung keinen Kurspfad
  zur Basiswährung hat, und am Tag des ersten Kurses kommt sein ganzer Saldo
  in den Endwert, ohne ein Fluss zu sein: `unvalued_cash_accounts` nennt jedes
  solche Konto des Scopes, das an einem Fenstertag oder am Tag vor dem
  Fenster, dessen Schluss der Anfangswert ist, null zählte (#1055, ADR-0051
  §10) — `cash_account_id`, `name`, `currency_code`, `balance` (sein nativer
  Saldo am letzten solchen Tag, ein Decimal-String in dieser Währung, nie
  umgerechnet), `unvalued_days` (seine Tage, der Tag vor dem Fenster (der
  Anfangswert) eingeschlossen), `unvalued_reason` (`no_rate`),
  `unvalued_through_end` (`true`, wenn es am letzten Tag des Fensters noch
  null zählte) und `first_rate_date` (das ISO-Datum, an dem der erste
  Wechselkurspfad der Währung kam, wenn es im Fenster liegt und das Konto am
  Tag davor Geld hielt und null zählte, sonst `null`) — nach Name sortiert,
  `[]`, wenn jeder Saldo bewertet war; `computation_basis.gaps` nennt das
  Feld.
- `GET /api/v1/portfolios/:portfolio_id/performance/benchmark` liefert den
  **Benchmark-Vergleich** (ADR-0046, FR-9): die eigenen externen Flüsse des
  Portfolios in eine Benchmark nachgebucht — die Antwort auf „war der
  Aufwand das wert?". `benchmark=` ist Pflicht — `rate:<decimal>` für einen
  festen effektiven Jahreszins, der täglich von Basis 1 aufzinst (Act/365;
  `rate:0.02` sind 2 % p. a., die Tagesgeld-Baseline und in v1 auch die
  Ausdrucksform der Inflation; akzeptiert zwischen `-0.999999` und `10`, dem
  Definitionsbereich des IRR-Solvers), oder `security:<id>` für **jedes
  Katalog-Wertpapier mit mindestens einem gespeicherten Kurs, mit oder ohne
  `is_benchmark`** (Ergänzung von ADR-0046 vom 2026-11-07, #1416: ein
  gehaltener Fonds kann die Benchmark sein und bleibt buchbar und in jeder
  Datenqualitätsprüfung; `GET /api/v1/securities?is_benchmark=true` listet
  die markierten Referenzinstrumente). Ein Wertpapier ohne gespeicherten
  Kurs liefert `422`, `{"errors": {"benchmark": ["has no stored quote"]}}`;
  eine unbekannte ID liefert `422`, `{"errors": {"benchmark": ["is not a
  benchmark security"]}}`. Ein Wertpapier, das eine Zusammenführung entfernt
  hat, wird ebenso abgelehnt; hat der Überlebende am lebenden Ende seiner
  Zusammenführungskette einen gespeicherten Kurs, ergänzt der Body
  `merged_into` `{"kind": "security", "id": …}` mit ihm, wie ihn die Abfragen
  zusammengeführter IDs nennen, und ein neuer Versuch mit dieser ID vergleicht
  (#959). Ein Überlebender ohne gespeicherten Kurs, eine Kette, die an einer
  inzwischen gelöschten Zeile endet, und eine ID, die keine Zusammenführung
  nennt, antworten ohne ihn. Der View- und der
  view-lose Vergleich unten antworten genauso. `period`, `year`, `from`/`to`, `view=` und `series=true`
  verhalten sich wie beim Performance-Endpunkt. Die Antwort trägt
  `benchmark` (`kind`, dann `annual_rate` oder `security_id`/`name`/
  `currency_code`), `requested_window` und `window` — die Tage, die der
  Vergleich tatsächlich abdeckt, mit `window.rebase_day`, dem Schlusskurs,
  auf den die Benchmark rebasiert wird (der Schlusskurs vor dem Fenster oder
  der erste Tag des Fensters, wenn es ohne Wert beginnt): ein Fluss vor dem
  ersten *bepreisten* Tag der Benchmark (ein Schlusskurs und ein Kurspfad
  zur Basiswährung; ein gespeicherter Schlusskurs von 0 ist kein Preis) wird
  nicht an seinem eigenen Tag nachgebucht — er geht über den Anfangswert des
  Fensters ein und wird in `excluded_flows` (`date`, `flow`) benannt — und
  beide Seiten werden über das abgedeckte Fenster verkettet — und dann die
  beiden Vergleiche, die Portfolio Performance zeigt. `bought_once` ist
  flussneutral: `benchmark_return`, die Benchmark auf `rebase_day`
  rebasiert, neben `portfolio_ttwror` über dasselbe Fenster; mit
  `series=true` zusätzlich die täglichen `cumulative_return`-Punkte für ein
  Chart-Overlay. `savings_plan` ist flussgleich: `invested_capital`,
  `portfolio_end_value` und `benchmark_end_value` — Anfangswert des Fensters
  und jeder externe Fluss zum Kurs jenes Tages in die Benchmark investiert
  (fester Zins: zu pari) — `end_value_delta` (real minus synthetisch, die
  Zahl, die die Frage beantwortet), `portfolio_irr` und `benchmark_irr` (der
  XIRR von ADR-0034 auf identischen datierten Flüssen), `portfolio_mwr` und
  `benchmark_mwr` (die nicht annualisierten Periodenraten, die ein Fenster
  unter einem Jahr stattdessen liest) und `benchmark_units`. Alle Finanzwerte
  sind Decimal-Strings; `as_of`/`stale` tragen die Frische des Walks
  (ADR-0039) und `computation_basis` nennt Eingangsreihe, Fenster, Referenz,
  Lückenbehandlung und die `assumptions` — das synthetische Portfolio ist
  reibungsfrei (`frictionless: true`: keine Gebühren, keine Steuern), was
  den Vergleich gegen das reale Portfolio verzerrt. Die Basis nennt ein
  Benchmark-Wertpapier als `security <id> (<Währung>)`, nie mit seinem
  gespeicherten Namen, der nur als Datum in `benchmark.name` steht (E25),
  und `computation_basis.benchmark_security` sagt, welche Art sie gelesen
  hat: `flagged` (mit `is_benchmark` markiert, gehalten oder nicht), `held`
  (nicht markiert, heute in einem Depot gehalten) oder `unheld`; `null` für
  einen festen Zins. Ein fehlendes oder
  fehlerhaftes `benchmark` ist `422`; ein Portfolio ohne Buchungen oder eine
  Benchmark ohne Kurs im Fenster antwortet mit `null`-Werten,
  `window.start_date: null` und jedem Fluss in `excluded_flows`. Ein
  Verrechnungskonto, dessen Saldo vor dem ersten Wechselkurs seiner Währung
  null zählte — der Sprung, den dieser Kurs bringt, steckt in
  `portfolio_ttwror` und `end_value_delta` —, wird in
  `unvalued_cash_accounts` genannt, den Einträgen des Performance-Endpunkts
  für das abgedeckte Fenster (`[]` ohne eines; #1055). `costs_paid`
  (ADR-0046, ergänzt am 2026-11-04) nennt, was die reibungsfreie Benchmark
  nie zahlt: die `fees` (Gebühren) und `taxes` (Steuern), die das reale
  Portfolio im `requested_window` gebucht hat, beide Tage eingeschlossen,
  als Decimal-Strings in der Basiswährung, nach der Regel der
  Kostenauswertung (`GET /api/v1/costs`: die Gebühren- und Steuerbeine jeder
  Buchung plus die eigenständigen `fee`- und `tax`-Buchungen, `tax_refund`
  gegen die Steuern verrechnet, jede zum EUR-Hub-Kurs ihres eigenen
  Buchungstags umgerechnet). Eine Kostenposition zählt dort, wo das
  Verrechnungskonto zählt, das sie bezahlt hat: im Portfolio, dem das Konto
  gehört, in einer Ansicht, deren Buckets das Konto enthalten, in der
  Gesamtsicht immer; eine Gebühr auf einen Kauf, dessen Depot in der Ansicht
  liegt und dessen Verrechnungskonto nicht, liegt außerhalb der Ansicht. Der
  Wert ist für jede Benchmark einer Anfrage derselbe. Eine Kostenposition
  ohne gespeicherten Kurs an ihrem Tag fehlt in beiden Summen und wird in
  `excluded` (`count`, `currencies`) genannt; `costs_paid.window` und die
  eigene `computation_basis` nennen die Regel. Er wird nicht von
  `end_value_delta` abgezogen, und es wird kein Rest genannt: eine früh
  gezahlte Gebühr hätte sich bis zum Fensterende verzinst, was die gebuchte
  Zahl nicht enthält. Eine Gebühr von 5,00 EUR auf einen Kauf im Fenster
  liest `fees` `"5"`, `taxes` `"0"`. Nichts wird
  gespeichert: der Vergleich wird beim Lesen abgeleitet und wie der Walk
  memoisiert, von dem er abhängt.
- `GET /api/v1/portfolios/:portfolio_id/performance/contribution` liefert die
  **Beitragsanalyse** (FR-41, ADR-0051): welche Position wie viel zum
  Geldergebnis des Zeitraums beigetragen hat, der Zahl „+x EUR im Zeitraum“
  neben der TTWROR. `period`, `year`, `from`/`to` und `view=` verhalten sich
  wie beim Performance-Endpunkt, ebenso seine Fehler (fehlerhafte `view` oder
  fehlerhafter Zeitraum `422`, unbekanntes Portfolio oder unbekannte View
  `404`). Jede Zeile von `positions` trägt `security_id`, `name`, `isin`,
  `start_value`, `end_value`, `net_flows`, `income`, `costs` und
  `contribution` — `end_value − start_value − net_flows + income − costs`, in
  der Basiswährung, die Währungsbewegung eingeschlossen, wobei `income` die
  Dividenden und die Zinsbuchungen sind, die das Wertpapier der Position
  nennen (der Kupon einer Anleihe), jeweils wie gutgeschrieben; ein Kupon auf
  ein Konto in der View zählt auch, wenn die Position außerhalb der View
  liegt (#928, Amendment von ADR-0051 vom 2026-10-09; Berechnungsversion 4) —
  dazu
  `held_at_start`, `held_at_end`, `unvalued_days` und `unvalued_reason`
  (`no_price`, `no_rate` oder `null`). `costs` sind die Gebühren und Steuern
  der eigenen Käufe und Verkäufe der Position, umgerechnet aus der Währung des
  Verrechnungskontos des jeweiligen Handels, in der sie erfasst sind (#1051);
  ein Handel ohne Kurs für seine Preiswährung fließt mit seinem Geldbetrag
  abzüglich dieser Kosten zu. Eine im Fenster gekaufte und wieder
  verkaufte Position steht in der Tabelle, obwohl sie an keinem Ende gehalten
  wird. Ein Tag, an dem eine gehaltene Position keinen Preis oder keinen
  Kurspfad hat, zählt null, wie im Walk; die Position bleibt in der Summe und
  wird mit ihren Tagen benannt. Ein Fremdwährungssaldo vor dem ersten
  Wechselkurs seiner Währung zählt ebenso null, und der erste Wechselkurs
  bringt seinen ganzen Wert in `cash_currency_effect`:
  `unvalued_cash_accounts` nennt das Konto, genau wie der
  Performance-Endpunkt desselben Scopes und Fensters, mit seinem nativen
  `balance`, seinen `unvalued_days` (der Tag vor dem Fenster eingeschlossen),
  `unvalued_through_end` und dem `first_rate_date` (#1055). Die Zeilen sind nach Beitrag sortiert, der
  größte zuerst, ohne Anteil, Rang oder Etikett. `remainder` hält, was keine
  Position hält, jede Zeile aus ihren eigenen Buchungen summiert und nie ein
  Ausgleichsposten: `interest` (die Zinsbuchungen ohne Wertpapier:
  Kontozinsen und jeder Kupon, der ohne seine Anleihe gebucht ist),
  `standalone_fees_and_taxes` (Gebühren-, Steuer- und
  Steuererstattungsbuchungen, die kein Trade trägt) und
  `cash_currency_effect` (die Neubewertung von Fremdwährungsguthaben, die
  Abrechnungsdifferenz eines Trades zwischen seinem Geldbein und Preis ×
  Stückzahl plus Kosten und was ein Geldübertrag zwischen Währungen
  hinterlässt). `totals` trägt `result` (`end_value − start_value −
  net_external_flows` des Performance-Endpunkts über dasselbe Fenster),
  `positions` und `remainder`, und `positions + remainder = result`, exakt in
  Decimal, solange die Umrechnungsquotienten abbrechen, sonst auf 34
  signifikante Stellen. Die Antwort trägt `portfolio_id`, `view_id` (`null`
  ohne View; eine `view` spiegelt zusätzlich `view: {id, name}`), `period`,
  `base_currency`, `start_date`/`end_date`, `as_of`/`stale` und
  `computation_basis` mit `assumptions`; alle Finanzwerte sind
  Decimal-Strings. Ein Fenster ohne gewalkten Tag — ein künftiges Jahr, ein
  Zeitraum vor der Historie — liefert `start_date: null`, keine Positionen
  und `"0"` als Zeilen und Summen, wie der Performance-Endpunkt es liefert.
  Nichts wird gespeichert.
- `GET /api/v1/portfolios/:portfolio_id/performance/bands`,
  `GET /api/v1/views/:view_id/performance/bands` und
  `GET /api/v1/performance/bands` liefern die **Bänder des gestapelten
  Wertcharts** (I23, FR-53) neben der Beitragsabfrage, in ihren drei Formen
  und mit ihren Zeitraumparametern (und `view=` in der Portfolio-Form): die
  Wertreihe der Performance-Abfrage, in Bänder geteilt, die sich an jedem Tag
  exakt zu ihr summieren (auf der Kategorie-Ebene bis auf eine Einheit der
  34. signifikanten Stelle je Tag, wenn ein Umrechnungsquotient nicht
  abbricht, wie `computation_basis.input_series` sagt). Die View- und die View-lose Form antworten in EUR
  oder in `base_currency=` (ein unterstützter Währungscode, als
  `base_currency` zurückgegeben): die Vermögen-Seite fragt in der
  Basiswährung ihrer Seite, so stimmen beide überein, wenn gleich gefragt;
  die Portfolio-Form antwortet in der Basiswährung des Portfolios. `level` ist `total` (ein Band, die Reihe),
  `category` (Standard: ein Band je Wurzelkategorie der Klassifikation, dazu
  `cash` und `unclassified`) oder `security` (ein Band je Wertpapier plus
  `cash`). Ein Aufruf ohne `level` antwortet mit `category`; die
  Standardebene der Vermögen-Seite ist deren eigene Wahl und ändert die der
  API nicht. **`category_id=` filtert jede Ebene** (FR-56) auf den Teilbaum
  dieser Kategorie, ohne `cash` und `unclassified`, sodass sich die Bänder
  zum Band der Kategorie eine Ebene höher summieren: auf `total` ein Band,
  die Linie der Kategorie (Schlüssel `category:<id>`); auf `category` ein
  Band je direkter Unterkategorie über ihren Teilbaum und ein Band der Art
  `direct` (Schlüssel `direct:<id>`, ID und Name der Kategorie selbst,
  `color` null) für die Wertpapiere, die direkt in der Kategorie stehen,
  fehlend, wenn dort keins steht, oder für eine Kategorie ohne
  Unterkategorien ein Band, ihr eigenes; auf `security` ihre Wertpapiere.
  `category_id=unclassified` filtert auf die Wertpapiere, die der Baum
  nirgends einordnet: ein Band `unclassified` auf `total` und `category`,
  ein Band je Wertpapier auf `security`. Das Band `direct` trägt den
  schlichten Namen; die Oberfläche beschriftet es „‹Name› (direkt)“ in
  ihrer Sprache. Die Antwort gibt `category_id` (die ID, `"unclassified"`
  oder `null`) und `computation_basis.filter` zurück. `classification_id=` wählt
  den Baum; ohne ihn stapelt die Kategorie-Ebene nach dem Baum der
  Zielgewichte des Bereichs, sonst nach der ersten eigenen Klassifikation,
  sonst nach den eingebauten Anlageklassen, und `classification.chosen_by`
  sagt, welcher (`requested`, `targets`, `default`, `category`). `sort` ist
  `size` (Wert des letzten Tages, größter zuerst, Standard) oder `change`.
  Die Antwort trägt `level`, `sort`, `classification`, `category_id`,
  `category`, `dates` und `bands`; jedes Band hat `key`, `kind`, `id`, `name`, `color` (die
  eigene Farbe der Kategorie, sonst `null`), `tree_index`, `values`
  (Decimal-Strings passend zu `dates`), `start_value`, `end_value`,
  `net_flows`, `share` (am letzten Tag, ein Nettoanteil: über 1 oder
  negativ, wenn ein Band negativ ist) und `change` (`(end_value −
  start_value − net_flows) / start_value`, `null` ohne positiven Startwert;
  die Nettoflüsse eines Wertpapiers sind die aus ADR-0051). Mehr als acht
  Bänder fassen die kleinsten zu `other` (mit `members`) zusammen, bei
  Gleichstand nach Name, nie nach ID; `cash` und `unclassified` bleiben
  eigene Bänder, und `other` ist immer das letzte Band, oben im Stapel,
  welche Sortierung auch gilt. Ein Tag ohne Kurs zählt null, wie in der Reihe, und ein
  Wertpapier steht das ganze Fenster in seiner heutigen Kategorie;
  `computation_basis` nennt jede Regel. **`scale=ttwror`** (FR-57; `scale`
  ist `value`, der Standard und die Antwort oben, oder `ttwror`, als
  `scale` zurückgegeben) liefert jedes Band stattdessen als Linie: seine
  eigene zeitgewichtete Rendite im Fenster, nicht gestapelt, denn Renditen
  addieren sich nicht. Seine Flüsse sind die Nettoflüsse seiner Wertpapiere
  aus ADR-0051 je Tag (Käufe, Verkäufe, Ein- und Auslieferungen,
  Grenzflüsse; die einer Gruppe die Summe ihrer Mitglieder); der
  Nettofluss des Tages zählt zu Tagesbeginn, wenn er ein Zufluss ist,
  `1 + r = V / (V_vor + F + B)`, und zu Tagesende, wenn ein Abfluss,
  `1 + r = (V − F) / (V_vor + B)`, `B` der Basissprung des Tages aus
  Handelspreisen wie im Walk, und ein Tag ohne positive Basis trägt keine
  Rendite bei. Ein Band mit Wert zum Schluss des Tages vor dem Fenster
  verkettet ab dort, wie die Linie der Ansicht; sonst beginnt seine Linie
  bei 0 % an seinem ersten Tag mit Wert. Nach dem Start hat ein Tag, an dem
  es nichts hält und nichts bewegt, keinen Punkt, also endet ein im
  Fenster ausverkauftes Band am Verkaufstag. Dividenden, Zinsen und
  Handelskosten sind kein Fluss: sie bewegen Cash, das keine Linie hat.
  Höchstens acht Linien, die größten nach Wert am letzten Tag des
  Fensters, bei Gleichstand nach Name, nie nach ID (Bänder gleich in Wert
  und Name am Schnitt fallen beide weg); nie `other`, und ohne
  `category_id` kein `cash` und kein `unclassified`. Jede Linie hat `key`,
  `kind`, `id`, `name`, `color`, `tree_index`, `start_value`, `end_value`,
  `net_flows`, `returns` (die kumulierte Rendite bis zu jedem Tag aus
  `dates`, ein Decimal-String, `null`, wo die Linie keinen Punkt hat) und
  `ttwror` (ihr letzter Punkt); `sort=change` ordnet die Linien nach
  `ttwror`. `parent` ist die Linie eine Ebene darüber: ohne `category_id`
  die TTWROR der Ansicht selbst (genau die Reihe `cumulative_ttwror` der
  Performance-Abfrage), mit ihr das Band des Filters; `null` bei
  `scale=value`. `computation_basis` nennt `flows`, `start_rule` und
  `selection_rule` statt `merge_rule`. Ein unbekanntes `level`, `sort`
  oder `scale`, eine fehlerhafte oder unbekannte `classification_id` oder `category_id`
  (alles außer einer ID oder genau `unclassified`) oder eine Kategorie eines
  anderen Baums liefert `422` mit dem Parameter, ebenso eine nicht
  unterstützte `base_currency`. Nichts wird gespeichert.
- `GET /api/v1/portfolios/:portfolio_id/income` liefert den **retrospektiven
  Ertragsbericht**: die bereits im Ledger gebuchten Dividenden und Zinsen, auf drei
  Arten aggregiert (keine Prognose — der Dividendenkalender ist eine separate
  Funktion). `annual` ist eine Liste von Jahren (neueste zuerst), jedes mit
  `months` (eine Map mit Monatszahl-Schlüsseln `"1"`–`"12"`, jeweils mit
  `dividends` und `interest`) und je Jahr `dividends_total`, `interest_total`,
  `total` und `excluded_count`, die Zahlungen des Jahres, die mangels
  Wechselkurs in keiner Summe stehen (unten); ein Jahr, dessen Zahlungen alle
  ausgeschlossen sind, behält seine Zeile mit `"0"` als Summen (#1293).
  `positions` ist die Pro-Position-Tabelle, eine Zeile je Wertpapier und
  Zahlungswährung, der Währung des Verrechnungskontos (#1274): eine Zinsbuchung, die ein Wertpapier nennt
  (der Kupon einer Anleihe), ist die Zeile dieses Wertpapiers, und die Zinsen
  ohne Wertpapier teilen sich die Zeile mit `security_id` `null` (#928):
  `security_id`,
  `security_name`, `security_currency` (die eigene Währung des Wertpapiers;
  auf einer Zeile ohne Wertpapier die Zahlungswährung), `currency` (die
  Zahlungswährung), `native_gross`, `native_tax` und `native_net` (in
  `currency`), `gross`, `tax` (die auf der Transaktion gespeicherte
  einbehaltene Steuer, einer Dividende oder einer Zinsbuchung) und `net`
  (`gross - tax`), umgerechnet in die Basiswährung, `payment_count` und
  `last_payment`. Ein USD-Wertpapier, einmal auf ein USD- und einmal auf ein
  EUR-Konto gezahlt, hat zwei Zeilen. `transactions` ist das Detail je Transaktion
  für eine Jahres-Aufschlüsselung (`kind`, `date`, `year`,
  `security_id`/`security_name`, `currency`, das native `native_gross`/
  `native_tax`/`native_net`, das `gross`/`tax`/`net` in Basiswährung und
  `converted`). Das Brutto einer Dividende ist ihr Netto-Cash (`gross_amount`) plus
  die einbehaltene Steuer (`taxes`), und eine Zinsbuchung, der Kupon einer
  Anleihe eingeschlossen, wird genauso gelesen: eine mit einbehaltener Steuer
  gebuchte Zinszeile liest `gross` = Netto + Steuer, `tax` = die gespeicherte
  Steuer, `net` = das gutgeschriebene Cash; eine ohne Steuer gebuchte hat
  `gross` gleich `net` (#1309). Gespeichert ändert sich nichts, und die
  Schreibpfade nehmen Steuern auf Zinsen weiter an. Alle Beträge sind
  Decimal-Strings in der `base_currency` des Portfolios, umgerechnet über den
  EUR-Hub zum letzten gespeicherten Wechselkurs an oder vor dem jeweiligen
  Buchungsdatum (dieselbe Mechanik wie der Bewertungs-Endpunkt), mit
  beibehaltener ursprünglicher Währung. Eine Buchung ohne solchen
  Wechselkurspfad ist
  aus jeder Summe (`annual`, seine Monate, `positions`) ausgeschlossen und in
  `excluded` genannt (`count`, und je Währung `currency_code`, `count`,
  `securities` und `interest_count`, ihre Zahlungen ohne Wertpapier), wie bei den anderen Cashflow-Lesungen; `transactions` behält
  sie mit `converted: false`, ihren nativen Beträgen und `null` für `gross`,
  `tax` und `net` in Basiswährung — nie ihr nativer Betrag zur Parität
  (Sicherheitsprüfung 2026-10-12, K07). `unconverted_count` zählt sie, `conversion_note` nennt die
  Basis und `computation_basis` (`series`, `currency`, `window`, `reference`,
  `gaps`, `positions`) die Regel. Bargeld und einbehaltene Steuer einer
  Buchung werden in der Währung ihres Verrechnungskontos gelesen, der
  Währung, in der sie gutgeschrieben wurden (die Ergänzung von ADR-0015 vom
  07.10.2026): Die Dividende eines USD-Wertpapiers, einem EUR-Konto
  gutgeschrieben, wird aus Euro umgerechnet, und ihre `transactions`-Zeile
  wie ihre `positions`-Zeile nennt in `currency` EUR, die Währung ihrer
  `native_*`-Beträge.
  Unbekannte Portfolios liefern `404 Not Found`.
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
  `classification_id` schränkt die Liste auf einen Baum ein; eines, das keine
  ID ist, liefert `422` (`{"classification_id": ["is invalid"]}`, Issue
  #1301), auf diesem Lesepfad und auf `/position_targets`, neben `plan_id` oder
  allein; optionales `view` wählt den Plan (weggelassen = Gesamt); optionales `plan_id` liest diese
  Planversion, einen Entwurf oder den aktiven Plan, mit den `422` des `PUT`
  unten (Issue #1185). Unbekannte Portfolios liefern `404 Not Found`.
- `PUT /api/v1/portfolios/:portfolio_id/targets` führt Zielgewichte für eine
  Klassifizierung ein (Upsert). Der Body ist `{"classification_id": id, "targets":
  [{"category_id": id, "target_weight": "0.25"}]}` und kann ein optionales
  `"view": id` tragen, um den Plan dieser View zu schreiben (weggelassen =
  Gesamt). Jedes `target_weight` ist ein String-Bruch in `[0, 1]` mit höchstens
  6 Nachkommastellen (vier in Prozent); ein feineres Gewicht liefert `422` auf
  `target_weight`, und die Datenbank lehnt es ebenfalls ab, sofern die Instanz
  beim Upgrade nicht schon ein feineres Gewicht hielt (das Upgrade protokolliert
  dann, wie viele). Das Duplizieren eines Plans oder sein Speichern im
  SOLL-Editor rundet ein solches gespeichertes Gewicht kaufmännisch auf 6
  Nachkommastellen. Ein Gewicht, das wegen seiner Genauigkeit oder als Wert
  außerhalb von `[0, 1]` abgelehnt wird, nennt auch seine Zeile, wie der
  Plan-Editor die abgelehnte Zeile voranstellt: `errors.row` ist
  `{"category_id": id, "security_id": id}`, mit `security_id` `null` bei einer
  Kategoriezeile, neben `errors.target_weight` (Issue #1143). Ziele müssen sich nicht zu `1` summieren. Nur die übergebenen Kategorien werden geändert.
  Eine Kategorie aus einem anderen Baum liefert `422 Unprocessable Entity`, und
  eine unbekannte Klassifizierung liefert `404 Not Found`. Ein Stapel nennt jede
  Kategoriezeile einmal und trägt höchstens eine Zeile je Kategorie und eine je
  in der Klassifizierung zugeordnetem Wertpapier, nie mehr als `10000` Zeilen;
  eine wiederholte Kategoriezeile oder ein größerer Stapel liefert `422`
  (`errors.detail` nennt die Kategorie, `errors.targets` die Grenze) und
  schreibt nichts.
  **Positions-Soll (ADR-0030):** Ein Zieleintrag, der zusätzlich eine
  `"security_id"` trägt, setzt ein Gewicht auf diese einzelne Position unter
  der Kategorie (das Wertpapier muss darunter stehen, sonst `422`); ein
  Kategorieeintrag (ohne `security_id`) und seine Positionseinträge werden
  nebeneinander gespeichert. Eine angegebene `security_id` ist eine positive
  Ganzzahl oder `null` (`null` = Kategoriezeile) — alles andere (ein
  nicht-numerischer String, eine Gleitkommazahl) liefert `422`, statt zu einem
  Schreibvorgang auf die Kategorie umgedeutet zu werden. Ein Plan trägt
  höchstens **eine Positionszeile je Wertpapier**: Ein Wertpapier unter einer
  zweiten Kategorie abzulegen oder dasselbe Paar `(category, security)`
  zweimal in einem Stapel zu nennen, liefert `422`. Die Datenbank hält diese
  Regel ebenfalls, sodass auch ein Schreibvorgang, der das Rennen um dasselbe
  Wertpapier unter einer anderen Kategorie verliert, `422` liefert und nichts
  speichert. Jedes serialisierte Ziel trägt `security_id` (`null` bei einer
  Kategoriezeile).
  **Eine Planversion (Issue #1133):** Ein optionales `"plan_id": id` schreibt
  diese Planversion — einen Entwurf aus `POST /api/v1/plans/:id/duplicate`
  oder den aktiven Plan — statt des aktiven Plans der View, sodass die
  Kategorie- und Positionsziele eines Entwurfs über die API bearbeitet werden
  wie im SOLL-Editor und er aktiviert wird, wenn er fertig ist; die beiden
  Ziel-Lesezugriffe nehmen dasselbe `plan_id` (Issue #1185) und folgen ohne es
  dem aktiven Plan. Der Plan muss einer dieses Portfolios sein,
  dieser Klassifizierung und, wenn `view` angegeben ist, dieser View, und er
  darf nicht `archived` sein: Eine archivierte Version steuert nichts und wird
  wiederverwendet, indem man sie aktiviert oder in einen Entwurf dupliziert.
  Eine fehlerhafte id, ein unbekannter Plan oder der eines anderen Portfolios,
  einer anderen Klassifizierung, einer anderen View und ein archivierter
  liefern je `422` auf `plan_id` (`is invalid`, `is not a plan of this
  portfolio`, `is a plan of another classification`, `is a plan of another
  view`, `is archived: activate it, or duplicate it into a draft`) und
  schreiben nichts.
- `DELETE /api/v1/portfolios/:portfolio_id/targets/:category_id` entfernt das
  **Kategorie**-Zielgewicht eines Portfolios für eine Kategorie und liefert
  `{deleted}` (die Zahl der entfernten Zeilen). Die Positionszeilen der
  Kategorie bleiben bestehen. Optionales `view` wählt den Plan (weggelassen =
  Gesamt); optionales `plan_id` adressiert eine Planversion wie beim `PUT`,
  mit denselben `422`.
- `GET /api/v1/portfolios/:portfolio_id/position_targets` listet die SOLL-Ziele
  eines Portfolios auf **Positionsebene** (ADR-0030): `{"position_targets":
  [...], "effective_targets": [...]}`. Jede `position_targets`-Zeile ist ein
  Ziel auf einem Wertpapier unter einer Kategorie (mit `security_id` und
  `security_name`); jeder `effective_targets`-Eintrag ist der Roll-up einer
  Kategorie — `explicit` (das Gewicht der Kategoriezeile oder `null`),
  `position_sum` (die Summe der direkt unter ihr abgelegten Positionszeilen —
  die Zeilen von Unterkategorien rollen in ihre eigene Kategorie auf),
  `effective` (das aufgelöste Steuergewicht — die Positionssumme gewinnt) und
  `conflict` (`true`, wenn explizites Gewicht und Positionssumme voneinander
  abweichen, sodass die Abweichung sichtbar wird). Jede Positionszeile trägt
  zudem `stale` (`true`, wenn ihr Wertpapier nicht mehr unter der
  gespeicherten Kategorie steht — umklassifiziert oder nicht zugeordnet; die
  Zeile zählt weiter dort, wo sie abgelegt wurde, und das erneute Ablegen ist
  die Abhilfe) und jeder Roll-up `has_stale`. Gewichte sind Decimal-Strings.
  Optionales `classification_id` / `view` grenzen ein wie oben.
  Lese-Ergonomie (FR-37, Issue #740): `min_drift=` — die Schwelle der
  Allokationsabfrage, gleich geschrieben (ein nicht-negativer Decimal-String
  auf `|drift_weight|`) — liefert nur die Positionszeilen, deren Drift sie
  erreicht; `drift_weight` ist das tatsächliche Gewicht des Wertpapiers in der
  Steuerbasis minus sein Positionsziel, renormiert, wie die Allokation einen
  bewusst kurzen Plan renormiert (ADR-0040), genau wie die Allokation es
  rechnet (ein Prädikat, zwei Oberflächen). Behaltene Zeilen tragen
  `drift_weight`, Zeilen ohne Drift werden mitgefiltert, und die Antwort
  benennt das angewandte `min_drift`, `position_targets_total` (die
  Zeilenzahl vor dem Filter) und einen Satz `drift_basis`. Ohne `min_drift`
  tragen die Zeilen kein `drift_weight`, und die Form ist unverändert. Eine
  ungültige Schwelle ist ein `422`. Optionales `plan_id` liest diese Planversion, mit den `422`
  des `PUT` (Issue #1185): ihre Zeilen, ihre `effective_targets` und, mit
  `min_drift`, die Drift gegen ihre Ziele, wie die Allokation sie mit dieser
  Version aktiv in ihrer View messen würde; bei einem Entwurf sagt
  `drift_basis` das und nennt den Plan.
- `DELETE /api/v1/portfolios/:portfolio_id/position_targets/:category_id/:security_id`
  entfernt ein Positionsziel und liefert `{deleted}`. Die Kategoriezeile und
  die übrigen Positionen der Kategorie bleiben unberührt. Optionales `view`
  wählt den Plan; optionales `plan_id` adressiert eine Planversion wie beim
  `PUT`.
- `GET /api/v1/portfolios/:portfolio_id/plans` listet die SOLL-**Planversionen**
  eines Portfolios (ADR-0027): zuerst die aktive, dann Entwürfe und
  archivierte Pläne, jeweils mit `name`, `status` (`active` / `draft` /
  `archived`), ihrem Geltungsbereich (`view_id`, `classification_id`) und
  `cash_target_weight` als Decimal-String. Optionales `classification_id`
  schränkt auf einen Baum ein; ein Wert, der keine id ist, wird ignoriert,
  und alle Pläne werden gelistet. Nur der **aktive** Plan eines Geltungsbereichs
  steuert die Allokation.
- `POST /api/v1/plans/:id/duplicate` kopiert eine Planversion (Kategorie- und
  Positionsziele sowie das Cash-Ziel) in einen neuen **Entwurf** desselben
  Geltungsbereichs und liefert ihn mit `201 Created`. Ein optionaler Body
  `{"name": "Plan 2027"}` benennt die Kopie (Standard:
  `"<source name> (copy)"`).
- `POST /api/v1/plans/:id/activate` macht eine Entwurfs- oder archivierte
  Version zum aktiven Plan ihres Geltungsbereichs und archiviert den bisher
  aktiven Plan in derselben Transaktion. Den bereits aktiven Plan zu
  aktivieren ist ein No-op.
- `PATCH /api/v1/plans/:id` benennt eine Planversion um (`{"name": "..."}`).
- `DELETE /api/v1/plans/:id` löscht eine Planversion (gleich welchen Status)
  samt ihrer Kategorie- und Positionsziele. Wird der aktive Plan gelöscht,
  bleibt der Geltungsbereich ohne Plan (die Allokation fällt auf nur IST
  zurück). Jedes Ziel wird als eigene `target`-Löschung vor der
  `target_plan`-Löschung des Plans journalisiert.
- `GET /api/v1/portfolios/:portfolio_id/category-results?classification_id=<id>` —
  das **Ergebnis** je Kategorie (ADR-0041 Teil eins, #712): `invested` (die
  Summe der `base_cost` der Mitglieder, ohne Gebühren und Steuern der Käufe,
  das Ergebnis also vor ihnen; `basis_note` sagt es seit Issue #1212),
  `current_value`,
  `result_abs` und `result_pct` je Kategorie, dazu die `positions`, die es
  ergeben, und die `excluded`-Zeilen, die es nicht abdecken konnte. Die Basis
  steht in einer Zeile (`basis: "current_composition"`, ausgeschrieben in
  `basis_note`): eine Aussage über die Positionen, die **heute** unter jeder
  Kategorie stehen, ohne Zeitraum und ohne Stichtag, und keine zeitgewichtete
  Renditereihe. `result_pct` ist `Σ Ergebnis ÷ Σ investiert`, **nie** ein
  Mittel der Prozente der Mitglieder. Ein Mitglied, dessen Ergebnis nicht
  ableitbar ist, fehlt auf **beiden** Seiten der Summe und steht mit seinem
  `reason` unter `excluded`; es zählt nie als null. MCP:
  `portfolixir.portfolios.category_results`.

  **Ein Mitglied wird bewertet, wie die Bewertung es bewertet** (ADR-0010,
  #1368): zu seinem neuesten Kurs, ohne Kurs zu seinem letzten eigenen
  Handelspreis. So ergeben `current_value`, `invested` und `result_abs` einer
  Kategorie, was `GET /api/v1/portfolios/:portfolio_id/valuation` und die
  Bestandsabfrage für dieselben Positionen liefern. Jede `positions`-Zeile
  nennt die Quelle in `price_source` (`"quote"` oder `"trade"`) und
  `price_date`, und `basis_note` nennt die Regel. Nur ein Mitglied ohne Kurs
  und ohne eigenen Handelspreis fehlt als `no_usable_price`.

  **Der View-Bereich (#901)** kommt in den zwei Formen der Performance-Familie
  (ADR-0051 §6). `?view=<id>` grenzt die Portfolio-Abfrage auf die zur View
  passenden Positionen des Portfolios ein und spiegelt sie als
  `view: {id, name}`; eine fehlerhafte View ist ein `422`, eine unbekannte ein
  `404`. Die View-Abfrage unten reicht über jedes Portfolio, und
  `GET /api/v1/category-results` über jedes Portfolio ohne View (#1091). Jede
  Antwort nennt den Bereich, über den sie gerechnet wurde: `scope`
  (`portfolio`, `view` oder `all`), `portfolio_id`, `view_id`,
  `base_currency` (die Währung jedes Geldwerts: die des Portfolios bei der
  Portfolio-Abfrage, `EUR` bei der View-Abfrage und bei der Abfrage über jedes
  Portfolio, `scope: "all"`) und einen Schlusssatz von `basis_note`, der ihn
  benennt. Das MCP-Tool nimmt denselben Bereich:
  `portfolio_id`, das `view` eingrenzt, `view` allein für die View über jedes
  Portfolio, oder keines von beiden für jedes Portfolio.

  **Jede Form nennt einmal, was sie auslässt** (#1091): `excluded_members`
  führt jedes ausgeschlossene Mitglied genau einmal über den ganzen Baum,
  gleich in wie viele Ebenen es einrollt, nach Namen sortiert ohne Rücksicht
  auf Groß- und Kleinschreibung (bei Gleichstand nach `security_id`), mit
  `security_id`, `security_name`, `category_id` (die Kategorie, unter der es
  steht), `reason` und `native_costs` — `[{amount, currency}]`, die
  Einstandskosten in der Währung, in der sie bezahlt wurden, Beträge als
  Decimal-Strings, wenn nur diese Währung das Mitglied aus einer EUR-Summe
  hält, sonst `[]`. Ein Wertpapier in einem EUR- und einem Nicht-EUR-Portfolio
  bleibt ganz heraus und trägt einen Eintrag je Währung, die Währung des
  Ergebnisses zuerst, dann die übrigen nach Code. Jede `basis_note` nennt die
  Liste; die `excluded`-Zeilen je Kategorie bleiben unverändert.
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
  sind ohne Plan, für `unassigned`-Positionen ohne eigenes Positions-Soll und
  für eine mit `0` bewertete Position ohne eigenes Soll `null`, die keinen
  Anteil an der Drift ihrer Kategorie hat (E25 S4); die Seite zeigt „—“ und
  sortiert eine solche Zeile hinter die Zeilen mit Drift. Mit den
  Positionszeilen nennt `computation_basis` im Payload die Grundlage des
  Drift-Anteils (`drift_value`) und diese Lücken. Einträge kommen größte zuerst, Wertpapiere über Depots
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
  Filter). Ungültige Werte sind ein `422`, ebenso ein Wert, der keine
  endliche Dezimalzahl ist (`NaN`, `Infinity`), hier und bei
  `position_targets`. Die Allokationsseite trägt
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
  Eintrag je Inhaber-Identität mit erfassten Auszügen (Schreibweisen einer
  Person, die sich nur in Groß- und Kleinschreibung unterscheiden, sind ein
  Eintrag; Institute werden ebenso abgeglichen), jeweils mit seiner
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
    Standard **N = 10** (überschreibbar mit dem `top_n`-Query-Parameter).
    `top_n` folgt dem Vertrag der Listen-Abfragen: höchstens `1000`, ein
    größerer Wert wird gekappt, und die Antwort nennt das angewandte `top_n`
    (E25 S4). Jeder
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

  **Die abgeleiteten Kennzahlen des Portfolios reisen auf derselben Abfrage**
  (ADR-0047, FR-40, Stufe (a) der Scope-Leiter) unter `metrics`, additiv. Die
  Risiko-Familie hat **genau einen Endpunkt**: es gibt kein
  `/views/:id/risk`, die Sicht kommt über den `view`-Parameter.
  - `volatility`, `max_drawdown` (mit `peak_date`, `trough_date`,
    `recovery_date`; `recovery_date` ist `null`, solange der Index unter dem
    Hoch liegt, und alle drei sind `null`, wenn der Drawdown genau `0` ist:
    es gab keinen Rückgang, also wird keiner datiert) und
    `risk_adjusted_return`, je über `30d`, `90d` und `365d`. Sie lesen die **flussbereinigten Tagesrenditefaktoren der
    TTWROR-Kette** — nie die Wertänderung von Tag zu Tag —, eine Einzahlung
    oder Entnahme ist also keine Rendite: ein Portfolio, dessen Kurse sich nie
    bewegen, hat Volatilität und Drawdown von genau `0`, egal wie viel Geld
    fließt. Ein Tag ohne Renditebasis erzeugt keine Beobachtung statt einer
    Nullrendite. Die Volatilität ist die Grundgesamtheits-Standardabweichung
    der Tagesrenditen, annualisiert mit `√365` (Kalenderreihe); der Drawdown
    läuft über den verketteten Renditeindex.
  - `risk_adjusted_return` ist die mittlere tägliche Überrendite über dem
    risikofreien Anteil, mal 365, geteilt durch die annualisierte
    Volatilität. Der Query-Parameter **`risk_free_rate`** ist ein
    Decimal-Bruch (`0.02` = 2 % p. a.), täglich verzinst wie der Festzins-
    Benchmark aus ADR-0046, gleich begrenzt, und **standardmäßig `0`** — dann
    ist die Zahl Rendite je Risikoeinheit, und
    `computation_basis.reference` sagt das. Kein Zins wird erschlossen,
    geladen oder gespeichert. Ein ungültiger Zins ist ein `422`. Bei einer
    Volatilität von genau `0` ist der Quotient `null` ohne
    `insufficient_data`: undefiniert, nicht zu wenige Daten.
  - Eine Zahl, deren Quadratwurzel jenseits dessen liegt, was der eine
    Gleitkommaschritt tragen kann — eine Größenordnung, die nur unplausible
    gespeicherte Kurse oder Wechselkurse erreichen —, ist ebenfalls `null`
    ohne `insufficient_data`: diese Volatilität und die risikobereinigte
    Rendite daneben oder dieses Korrelationspaar. Die Abfrage scheitert an
    solchen Daten nie und liefert über ihnen nie eine Zahl; die Risiko-Seite
    zeigt ein solches Paar als „nicht berechenbar“ mit seinen Beobachtungen.
  - `correlations` ist die Pearson-Matrix der Tagesrenditen **höchstens der
    20 führenden** Top-N-Einzeltitel (`leading_names` nennt, über wie viele
    sie lief; die Zahl der Paare wächst mit dem Quadrat der Titel, darum ist
    die Matrix begrenzt, die Liste nicht, und `computation_basis` sagt es),
    mit `security_ids` in Top-N-Reihenfolge und `pairs` mit `security_id_a`,
    `security_id_b`, `value`, über ein `365d`-Fenster. Die
    Kurse werden **zuerst in die Basiswährung umgerechnet**, und ein Paar
    liest nur Tage, an denen **beide** Wertpapiere einen Kurs haben. Ein
    Wertpapier ohne gespeicherten Wechselkurspfad fehlt in der Matrix und
    steht in `excluded` mit `reason: "no_rate_path"`.
  - Jede Kennzahl trägt `window`, `observations`, `required` und
    `insufficient_data`; unterhalb des Minimums — 20 Beobachtungen für
    Volatilität und risikobereinigte Rendite, 2 Indexpunkte für den Drawdown,
    60 gemeinsame Renditen je Korrelationspaar — ist `value` `null` bei
    `200`. `metrics.computation_basis` trägt die Berechnungsgrundlage einmal.
  - **Die Abfrage berichtet, sie bewertet nicht.** Kein Schlüssel in
    `metrics` ist ein Signal, eine Empfehlung, ein Rating, ein Score oder eine
    Handlung.
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
  gibt den gespeicherten Wert zurück. Gewichte außerhalb des Bereichs und
  Gewichte mit mehr als 6 Nachkommastellen liefern `422 Unprocessable Entity`
  auf `cash_target_weight`, neben `errors.row` `"cash"`, der Zeile, die der
  Plan-Editor nennt (Issue #1143). Das Cash-Ziel speist die `cash`-Zeile der Allokation
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
  liefern `404 Not Found`. Das Cash-Ziel wird **nur geschrieben, wenn der
  Rumpf `cash_target_weight` trägt**, in derselben Transaktion wie der Rest des
  Patches: Ein Patch ohne das Feld (etwa ein Umbenennen) lässt das gespeicherte
  Cash-Ziel und sein Journal unberührt, und ein abgelehntes Schreiben des
  Cash-Ziels antwortet mit `422`, ohne dass etwas geschrieben wird, auch nicht
  der Rest des Patches. Die Antwort trägt das Cash-Ziel, wie es nach dem
  Schreiben gespeichert ist. Das `cash_target_weight` ist auch in den von
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
  statt eines blinden währungsübergreifenden Vergleichs. Seit Issue #1369
  wird ein offenes Lot nach der Regel des Bestandslesens bepreist
  (ADR-0010): sein `latest_price` ist der letzte Schlusskurs, sonst der
  letzte eigene Handelspreis über alle Portfolios, in der eigenen Währung
  des Wertpapiers, und das Lot nennt ihn in `price_source` (`quote` |
  `trade`) und `price_date`, `null` ohne Preis;
  `computation_basis.latest_price` nennt die Regel. Ein Wertpapier ohne
  Kurs, gekauft 15 zu 18,00 und 5 zu 19,20, liest `latest_price` 19,20 mit
  `price_source` `trade` auf beiden Lots und `unrealized_pnl_abs` 18,00 und
  0,00, die Zahl seines Bestands. Die Antwort ist
  selbstbeschreibend (FR-13): sie trägt `method: "fifo"`, sodass ein Client nie
  annehmen muss, wie Lots gegen Verkäufe gepaart wurden. Da ein Verkauf das
  älteste Lot verbraucht, gleich welches Portfolio es gekauft hat, skaliert ein
  Split an seinem Datum jedes offene Lot des Wertpapiers einmal, sodass die
  Lots den gehaltenen Stücken folgen. Optionales `from`/`to`
  (ISO-Daten) filtert jedes Bein nach seinem eigenen Datum: offene Lots nach
  Eröffnungsdatum, geschlossene Round-Trips nach Schlussdatum, verwaiste Verkäufe
  nach Verkaufsdatum.
  Es gibt kein `limit`: `from`/`to` sind die Grenze (der FIFO-Matcher braucht
  die ganze Historie, und jedes Bein wird danach nach seinem eigenen Datum
  gefiltert), genannt im `basis` der Antwort.
  Seit Issue #984 trägt jeder geschlossene Round-Trip `annualized_return` und
  `annualized_return_reason`, dieselbe Zahl nach derselben Regel wie das
  Realisiert-Rollup oben, und die Antwort trägt
  `computation_basis.annualized_return`.
  Seit Issue #1108 stehen `buy_fees` und `buy_taxes` eines offenen Lots und
  `buy_fees`, `buy_taxes`, `sell_fees` und `sell_taxes` eines geschlossenen
  Round-Trips in seinem `currency_code`, wie `basis` und `proceeds`: Ein
  währungsübergreifender Trade, gebucht in der Wertpapierwährung, rechnet sie
  zu seinem eigenen gespeicherten `settlement_fx_rate` aus der Währung des
  Verrechnungskontos um, wie beim Realisiert-Rollup oben beschrieben, und
  `computation_basis.fees_and_taxes` nennt die Regel.
  Seit Issue #1142 liest ein geschlossener Round-Trip mit `basis` `"0"`
  `realized_pnl_pct` `null` mit `annualized_return_reason` `no_cost_basis`,
  wie im Realisiert-Rollup, und ein offener Lot, dessen Kosten (`quantity` ×
  `buy_price_native`) `"0"` sind, behält sein `unrealized_pnl_abs` und liest
  `unrealized_pnl_pct` `null`, nie `"0"`;
  `computation_basis.realized_pnl_pct` und
  `computation_basis.unrealized_pnl_pct` nennen die Regeln. Wie beim
  Bestands-Endpunkt liest ein offener Lot mit `base_cost` `"0"` die drei
  Prozentwerte der Zerlegung ebenfalls `null`, und
  `computation_basis.decomposition_pct` nennt die Regel.
  Seit Issue #1212 sagt `computation_basis.fees_and_taxes_in_figures`,
  welche Zahlen Gebühren und Steuern tragen: `buy_price`,
  `buy_price_native`, `base_cost` und `unrealized_pnl_*` eines offenen Lots
  sind ohne sie; seine `buy_fees` und `buy_taxes` sind die des ganzen
  Kaufs, für `original_quantity`, die Stückzahl, mit der das Lot eröffnet
  wurde (split-bereinigt), und der Anteil, der schon in der `basis` eines
  geschlossenen Round-Trips steckt, steht in dessen `buy_fees` und
  `buy_taxes`. Die `basis` eines geschlossenen Round-Trips enthält die
  Kaufgebühren und -steuern der Lots, die er schließt, anteilig, seine
  `proceeds` sind abzüglich der des Verkaufs, und `realized_pnl_abs` ist
  nach allen vieren.
  Keine Zahl hat sich geändert.
- `GET /api/v1/snapshots` listet Depot-**Snapshot-Marker** (ADR-0027): jeder
  ist ein `name`, ein Geltungsbereich (`view_id`, `null` = alles) und ein
  `as_of`-Datum. Ein Snapshot kopiert keine Finanzdaten — die Bestände, die er
  repräsentiert, werden bei Bedarf aus dem Buchungsjournal abgeleitet.
  `limit` behält die neuesten Snapshots (Standard 1000, max. 10000); die
  Antwort nennt das angewandte `limit`.
- `POST /api/v1/snapshots` legt einen Marker an
  (`{"name": "...", "as_of": "2026-02-15", "view_id": 3}`; `view_id`
  optional). Ein `as_of` in der Zukunft oder ein doppelter Name im selben
  Geltungsbereich liefert `422 Unprocessable Entity`.
- `DELETE /api/v1/snapshots/:id` löscht einen Marker; Transaktionen und
  Bestände bleiben unberührt.
- `GET /api/v1/portfolios/:portfolio_id/snapshots/:id/comparison` beantwortet
  „Wäre ich besser gefahren, hätte ich behalten, was ich hatte?“: Die
  eingefrorenen Bestände des Snapshots werden **buy-and-hold** über die
  gespeicherte Kurshistorie bewertet (täglich, Wechselkurse über den EUR-Hub)
  und der echten TTWROR des Geltungsbereichs seit dem Stichtag
  gegenübergestellt. Die Antwort trägt `as_of_value`, `current_value`,
  `snapshot_return`, `real_ttwror`, eine tägliche `series` (`snapshot_value`,
  `snapshot_indexed`, `real_indexed`), eine Liste `gaps.unvalued_securities`
  der Wertpapiere, die mangels Kurs oder Wechselkurs zum Stichtag
  ausgeschlossen sind, und eine selbstbeschreibende `basis` (brutto, in v1 nur
  Kursentwicklung; sie trägt das `window`, die `base_currency` sowie
  `costs_removed` / `costs_kept`, die nennen, welche Kostenarten aus der
  Rendite genommen wurden). Alle Finanzwerte sind Decimal-Strings.

  **Die beiden Seiten stehen nicht auf derselben Basis, und der Payload sagt
  das** (#708, Ergänzung zu ADR-0027): Die eingefrorene Seite zahlt nie
  etwas, während die echte TTWROR nach den tatsächlich gebuchten Gebühren und
  Steuern gerechnet ist. Die Antwort trägt deshalb zusätzlich
  `real_ttwror_before_costs` (derselbe Lauf, in dem die Gebühren und Steuern
  der **Handelsgeschäfte** des Zeitfensters als externe Flüsse gewertet
  werden — eigenständige Gebühren- und Steuerbuchungen und die Quellensteuer
  auf Dividenden bleiben bewusst in der Rendite, weil der eingefrorene Halter
  sie ebenso gezahlt hätte), `transaction_costs` (deren Summe in der
  Basiswährung) und `cost_recovery` mit `state`: `recovered`,
  `partly_recovered` (vor Kosten vorne, nach Kosten noch nicht; `outstanding`
  nennt den Abstand), `not_recovered` (auch vor Kosten hinten, die Kosten sind
  also nicht der Grund) oder `not_comparable` (die eingefrorene Seite hat zum
  Stichtag keinen Wert — etwa ein Snapshot nur aus Cash —, es gibt also
  nichts, vor dem die echte Seite liegen könnte; die Kosten werden trotzdem
  gemeldet). Lesen Sie die drei zusammen: `real_ttwror_before_costs` allein
  schmeichelt.

### Erfasste Steuerbescheinigungen (ADR-0031)

**Diese Töpfe werden erfasst, nicht hergeleitet** — und der Grund ist *nicht*
ein fehlendes FIFO. Portfolixir ordnet Lots bereits nach FIFO zu (`GET
/api/v1/securities/:id/trades`), und das ergibt einen **Rohgewinn**. Ein
Rohgewinn ist kein Steuertopf: Teilfreistellung, Vorabpauschale, die
chronologische Verrechnung des Freistellungsauftrags und der bescheinigte
Verlustvortrag aus Vorjahren stehen gar nicht in den Transaktionsdaten, und
die Töpfe werden je meldendem Institut geführt, das Portfolixir nicht
modelliert. Ein hergeleiteter Topf wäre falsch, und zwar unsichtbar falsch —
deshalb übernehmen diese Endpunkte eine Bankabrechnung und berechnen nie eine
aus den Beständen. Jeder Geldwert ist ein Decimal-String als **positiver
Betrag**: Ein Verlusttopf ist das zur Verrechnung verfügbare Verlustvolumen,
nicht die negative Zahl, die die Abrechnung druckt, und eine negative Eingabe
wird abgelehnt statt still umgedreht. Nichts hier ist Steuerberatung, und
maßgeblich bleibt die erfasste Abrechnung. (Eine Steuer, die einem Geldkonto
tatsächlich wieder gutgeschrieben wird — etwa nach einem Verlustverkauf —,
ist ein Ledger-Ereignis, kein Topf: Sie wird als eigene
`tax_refund`-Transaktion gebucht, wie oben unter „Transaktionen und Bestände“
beschrieben.)

- `GET /api/v1/tax/parameters` listet die jahresbezogenen gesetzlichen
  Parameter (optionales `jurisdiction`, derzeit nur `DE`):
  `capital_gains_tax_rate`, `solidarity_surcharge_rate` und die Höchstbeträge
  `saver_allowance_single` / `saver_allowance_joint`. Sätze sind
  Decimal-String-**Brüche** (`"0.25"`, nie `"25"`). Hinterlegt für 2009–2026;
  ein Jahr ohne Zeile fehlt schlicht — die API setzt nie den Höchstbetrag
  eines Nachbarjahres ein.
- `PUT /api/v1/tax/parameters` legt die Parameter eines Jahres an oder
  ersetzt sie (`{"parameters": {"tax_year": 2027, ...}}`).
- `GET /api/v1/tax/profiles` listet die zeitlich gültigen Steuerprofile einer
  Person (Pflichtparameter `holder`; fehlt er, folgt `422 Unprocessable
  Entity`), das neueste `valid_from` zuerst. Für ein Datum gilt die Zeile mit
  dem größten `valid_from` an oder vor diesem Datum — nie ein exakter
  Treffer. Die Kirchensteuerpflicht steht standardmäßig auf **nicht
  pflichtig** mit Satz `0`.
- `POST /api/v1/tax/profiles` erfasst ein Profil ab einem Datum
  (`{"profile": {"holder": "...", "valid_from": "2024-01-01"}}`). Ein
  `church_tax_rate` ungleich null auf einem nicht pflichtigen Profil wird
  abgelehnt.
- `PATCH /api/v1/tax/profiles/:id` korrigiert eine Profilzeile. Um eine
  *Änderung* der Situation festzuhalten, wird eine neue Zeile mit späterem
  `valid_from` angelegt — Bearbeiten schreibt die Geschichte um, Hinzufügen
  nicht.
- `DELETE /api/v1/tax/profiles/:id` löscht eine Profilzeile. Bereits erfasste
  Snapshots behalten ihren eingefrorenen Kirchensteuersatz und bleiben
  unberührt.
- `GET /api/v1/tax/allowance_orders` listet die Freistellungsaufträge, die die
  steuerpflichtige Person **erteilt** hat (optionales `holder`, `institution`,
  `tax_year`; Freitextfilter ignorieren Groß- und Kleinschreibung, sodass
  `comdirect` und `Comdirect` ein Institut sind). Jedes `holder` und
  `institution`, das die Steuer-Endpunkte schreiben oder nach dem sie filtern,
  wird auf eine Weise normalisiert — nach NFC zusammengesetzt, unsichtbare
  Formatzeichen entfernt, jede Folge von Unicode-Leerzeichen ein Leerzeichen,
  ein Wert, der nur aus solchen Zeichen besteht, ein `422` — und auf beiden
  Seiten über die Groß-/Kleinschreibungsfaltung der Datenbank abgeglichen,
  die Faltung der eindeutigen Indizes (E25 S6).
- `PUT /api/v1/tax/allowance_orders` erfasst oder ersetzt den erteilten
  Betrag für ein `(holder, institution, tax_year)`
  (`{"allowance_order": {...}}`).
- `DELETE /api/v1/tax/allowance_orders/:id` löscht einen hinterlegten
  Auftrag.
- `GET /api/v1/tax/statement_snapshots` listet erfasste Bescheinigungen
  (optionales `holder`, `institution`, `tax_year`), das neueste `as_of`
  zuerst. Jede Zeile trägt die elf erfassten Zahlen plus
  `allowance_remaining`, `tax_free_trim_budget`, `expected_capital_gains_tax`,
  das `as_of`, auf dem sie beruhen, ein `stale`-Flag und die beratenden
  `findings`. Jede Zeile trägt außerdem die aktivitätsbewusste
  `staleness`-Bewertung (#667): Veraltung als Funktion der Aktivität, nicht
  nur des Kalenders. Sie nennt ihre eigene Berechnungsbasis — `age_days`
  gegen `age_threshold_days` (90), `activity_since_count` (die
  Ledger-Transaktionen der `activity_kinds` — `sell`, `dividend`, `interest`,
  `tax`, `tax_refund` — mit Datum strikt nach `as_of`), die beiden
  Teilwarnungen und die kombinierte `warning`, dazu einen `basis`-Hinweis,
  der festhält, dass Buchungen keinem Institut und keinem Steuerjahr
  zugeordnet werden. `warning` ist das Signal zum Handeln; das bloße
  `stale`-Flag kippt am Tag nach jedem `as_of` und bleibt aus
  Kompatibilitätsgründen erhalten.
- `POST /api/v1/tax/statement_snapshots` erfasst eine Bescheinigung
  (`{"statement_snapshot": {"institution": "...", "holder": "...",
  "tax_year": 2025, "as_of": "2025-12-31", ...}}`). `as_of` darf nicht in der
  Zukunft liegen. Ohne `church_tax_rate` gilt der Satz des zum `as_of`
  geltenden Profils der Person; der aufgelöste Satz wird dann auf der Zeile
  eingefroren, sodass eine spätere Profiländerung nie eine erfasste
  Übertragung umschreibt. Dasselbe `(institution, holder, tax_year, as_of)`
  erneut zu erfassen ist ein `422`, kein stilles Duplikat. Die Quelle einer
  erfassten Steuerbescheinigung setzt das System (`manual`); eine `source` im
  Body einer Anlage oder einer Korrektur wird ignoriert. Wer sie geschrieben
  hat, ist ein eigenes Paar (Sicherheitsprüfung K12): `author` ist, wer sie
  erfasst hat, und `corrected_by`, wer sie zuletzt korrigiert hat (`null`
  bis zu einer Korrektur), jeweils `operator` für die Steuern-Seite und
  `agent` für ein API- oder MCP-Token, abgeleitet aus dem Zugang des
  Schreibzugriffs und nie aus dem Body gelesen. Eine Änderung, die nichts
  ändert, setzt kein `corrected_by`. Ein Freistellungsauftrag trägt dasselbe
  Paar für sein erstes Erfassen und sein letztes Ersetzen. Zeilen von vor
  den Autoren erhalten, was ihr Anlegen und ihre letzte Korrektur im Journal
  nennen, `null` ohne einen solchen Eintrag.
- `GET /api/v1/tax/trim_budget` rollt die jeweils neueste Bescheinigung je
  Institut zu einer Person und einem Jahr auf (Pflichtparameter `holder` und
  `tax_year`); Institute werden nach der Groß-/Kleinschreibungsfaltung der
  Datenbank gruppiert, sodass eine spätere Bescheinigung unter einer anderen
  Schreibweise derselben Bank die frühere ersetzt. Die Antwort nennt, welche
  `institutions` sie abdeckt, welche davon auf einer Bescheinigung beruhen,
  die der Agent erfasst oder zuletzt korrigiert hat (`agent_institutions`,
  K12), das `as_of` ihres **ältesten** Bestandteils, die
  summierten `allowance_granted` und `allowance_used`, aus denen der
  Füllstand auf der Steuern-Seite gelesen wird (neben `allowance_remaining`),
  und `complete: false` mit `missing_institutions`, wenn ein hinterlegter
  Freistellungsauftrag für das Jahr keine erfasste Bescheinigung hat — die
  Summe ist dann ein Teilbild und sagt das. Die Antwort trägt dieselbe
  `staleness`-Bewertung, berechnet gegen das (älteste) `as_of` des Rollups.
- `GET /api/v1/tax/statement_snapshots/:id` liest eine erfasste
  Bescheinigung.
- `PATCH /api/v1/tax/statement_snapshots/:id` korrigiert eine erfasste
  Bescheinigung an Ort und Stelle — der Fall der neu ausgestellten
  Bescheinigung.
- `DELETE /api/v1/tax/statement_snapshots/:id` löscht eine erfasste
  Bescheinigung.

Prüfbefunde sind beratend und werden beim Lesen berechnet. Ein Befund nennt
die `recorded` und die `expected` Zahl und die `gap`; er schlägt nie einen
korrigierten Wert vor und blockiert nie einen Schreibvorgang. Zwei Regeln sind
dagegen hart und kommen als `422`-Changeset-Fehler zurück: verbrauchter
Freistellungsauftrag über dem erteilten, und einbehaltene Kirchensteuer bei
einem Kirchensteuersatz von null.

## Eigene Regeln (ADR-0049)

Eine **eigene Regel** ist ein gespeicherter Maßstab über eine Zahl, die das
Produkt ohnehin liefert: „kein Einzeltitel über 10 %", „Barmittel nie unter
5 %", „die Kategorie Anleihen innerhalb von ±3 Prozentpunkten ihres Ziels",
„die 90-Tage-Volatilität des Portfolios unter 15 %". Sie wird als Objekt
gespeichert, statt als Fließtext in einem geplanten Prompt zu stehen — dort,
wo solche Grenzen bisher auseinanderliefen. Der Betreiber legt Regeln auf der
Seite Risiko an, ein Agent über die API mit seinem Token; eine Regel ist also
eine gespeicherte Regel, wer sie auch geschrieben hat: Das Audit-Journal
(`resource_type` `policy_rule` und `policy_rule_version`) sagt, wer jede Regel
und jede Version geschrieben hat, und die `rules_note` der Liste verweist
dorthin. Jede Version trägt zudem **`author`** (E25): `operator` für eine auf
der Seite Risiko gespeicherte Version, `agent` für eine mit einem API- oder
MCP-Token geschriebene, abgeleitet aus dem Zugang des Schreibzugriffs und nie
aus dem Body gelesen; ein Befund trägt den `author` der gültigen Version.
Eine Version von vor den Autoren erhält den Autor, den ihr Anlegen im Journal
nennt, `null` nur ohne einen solchen Eintrag. `author` gilt für die Version,
nicht für den Namen: Eine Umbenennung ist keine Version, darum trägt die
Regel ihren eigenen **`name_author`** (Sicherheitsprüfung H14), wer sie
zuletzt benannt hat, ebenso gesetzt beim Anlegen und bei jeder Umbenennung;
ein Befund trägt ihn als `rule_name_author`. Eine Regel von vor den
Namensautoren erhält den Autor ihrer letzten Umbenennung im Journal, sonst
den der Version, die mit ihrem Namen geschrieben wurde, `null` nur ohne
beides. Risiko markiert die Regeln des Agenten mit dem Wort „Agent", hinter
dem Namen, wo der Agent die Regel benannt hat; ab wann eine Regel gilt,
hängt nicht von ihrem Autor ab.

**Was eine Regel ist.** Eine Aussage über **eine benannte Kennzahl**, für
einen Bezug, in einem Auswertungskontext:

- der **Kontext** ist das Portfolio plus eine optionale `view_id` (`null` ist
  der portfolioweite Kontext, wie bei Zielplänen); die Kennzahl wird auf der
  steuerbaren Basis dieses Kontexts gelesen;
- der **Bezug** ist `basis`, `security` (`security_id`), `category`
  (`classification_id` + `category_id`), `view` (`subject_view_id`) oder
  `cash`;
- die **Kennzahl** ist eine dieser, und jede wird aus einer Antwort gelesen,
  die das Produkt schon liefert — Regeln berechnen keine eigene Zahl:

  | `measure` | Bezüge | Skala der Grenzen |
  |---|---|---|
  | `weight` | security, category, cash, view | Prozent, `0`–`100` |
  | `drift` | category, security | Prozentpunkte, `−100`–`100` (Ist − Ziel des aktiven Plans) |
  | `hhi` | basis | `0`–`10000` |
  | `volatility` | basis, mit `window` (`30d`, `90d`, `365d`) | Prozent, annualisiert, `≥ 0` |
  | `max_drawdown` | basis, mit `window` | Prozent im eigenen Vorzeichen, `−100`–`0` |

  Ein `security`-Bezug für `drift` nennt zusätzlich die `classification_id`,
  deren Plan sein Positionsziel trägt. Ein `view`-Bezug ist die Art, einen
  **Bucket** zu begrenzen: „der spekulative Bucket bleibt unter 5 % von allem"
  ist eine `weight`-Obergrenze auf der View, die diesen Bucket auswählt,
  ausgewertet im portfolioweiten Kontext.
- die **Art** ist `cap` (verletzt strikt oberhalb von `threshold`), `floor`
  (strikt unterhalb) oder `band` (außerhalb von `[lower, upper]`) — dieselbe
  Lesart einer Linie wie die Risikolinse;
- der **Schweregrad** ist `warn` oder `hard`; `name` und `note` sind die
  Worte der Regel, wer sie auch geschrieben hat, und werden nie ausgewertet. Der `name` ist eine
  **Bezeichnung der Regel**, nicht Teil ihrer Identität: Er lässt sich jederzeit
  ohne neue Version ändern (siehe das Umbenennen unten) und muss nicht
  eindeutig sein.

Grenzen sind Decimal-Strings (ADR-0016). Eine Aussage, die nicht zu ihrer
Kennzahl passt — ein Bezug außerhalb der Tabelle, ein fehlendes oder
überflüssiges `window`, ein Band mit `lower > upper`, eine Grenze außerhalb der
Skala — ist ein `422`, das Feld unter `version` benannt.

**Versioniert und mit Gültigkeitsdatum.** Eine Regel hat eine feste Identität
und eine oder mehrere **Versionen**, jede der Maßstab ihres eigenen Zeitraums
`[valid_from, valid_until]`. Eine **Änderung legt eine Version an** ab
`valid_from` (standardmäßig heute, nie früher) und beendet die vorige am Tag
davor; beide bleiben lesbar, sodass „welcher Maßstab galt am Tag D" eine
Abfrage ist (`as_of=`) und keine Recherche im Audit-Journal. Eine Version, die
schon gegolten hat, wird **nie geändert und nie gelöscht** — die Datenbank
lehnt es ab, ebenso zwei sich überschneidende Versionen einer Regel. Eine erst
geplante Version wird ersetzt, indem man eine Version ab demselben Datum
anlegt. Die Datenbank lehnt außerdem bei jeder Version eine Änderung ihrer
Regel, ihrer Aussage oder ihres Startdatums ab, bei jeder Regel eine Änderung
ihres Portfolios oder ihrer View, und ein `TRUNCATE` beider Tabellen. Das
Enddatum einer Version und der Name einer Regel bleiben schreibbar, über das
Beenden, die Änderung und das Umbenennen. Jeder Schreibvorgang wird
journalisiert.

Die Lesezugriffe:

- `GET /api/v1/portfolios/:portfolio_id/policy_rules` — die Regeln des
  Portfolios, jede mit `status` (`in_force`, `scheduled` oder `retired`,
  bezogen auf `as_of`), `version_in_force` und `next_version`. `as_of`
  (ISO-Datum, standardmäßig heute) liest den Maßstab eines Tages;
  `include_retired=true` nimmt beendete Regeln dazu; `view` beschränkt auf
  einen Auswertungskontext (ohne: alle Kontexte); `since` ist die Zeilen-Delta
  (eine Regel gilt als geändert, wenn ihre Zeile oder eine ihrer Versionen
  geändert wurde); `limit` (Standard 1000, höchstens 10000).
- `GET /api/v1/policy_rules/:id` — eine Regel mit ihrer **ganzen
  Versionsgeschichte**, älteste zuerst.

Die Schreibzugriffe:

- `POST /api/v1/portfolios/:portfolio_id/policy_rules` — Rumpf
  `{"rule": {"name", "view_id", "version": {…}}}`; legt die Regel mit ihrer
  ersten Version an (`201`).
- `POST /api/v1/policy_rules/:id/versions` — Rumpf `{"version": {…}}`; die
  Änderung (`201`). Auf beiden fasst die `note` einer Version höchstens 10000
  Zeichen (Unicode-Codepoints); eine längere liefert `422` auf `note`.
- `PATCH /api/v1/policy_rules/:id` — Rumpf `{"name": "…"}`; das
  **Umbenennen**, eine Änderung an der Regel selbst **außerhalb der
  Versionen**: Es entsteht keine Version, keine wird geändert, und der neue
  Name gilt für die Regel mit allen Versionen (`200`, die Regel mit ihren
  Versionen). Das Journal hält den bisherigen Namen und wer ihn geändert hat.
  Auch bei einer beendeten Regel erlaubt. Gelesen wird nur `name`, wie bei
  `PATCH /api/v1/plans/:id`: Ein leerer, fehlender oder nicht-textueller Name
  ist ein `422` auf `name`; ein Feld der Aussage, eine `version`, die
  Versionsschlüssel der eigenen Leseform der Regel (`version_in_force`,
  `next_version`, `versions`) oder der Kontext (`view_id`, `portfolio_id`) im
  selben Rumpf ist ein `422`, das jedes solche Feld nennt, und nichts wird
  geschrieben — eine neue Linie ist eine neue Version, und eine Regel in einem
  anderen Kontext ist eine neue Regel. Jeder andere Schlüssel wird ignoriert.
  Eine Regel, die seit dem Lesen gelöscht wurde, ist ein `404`.
- `POST /api/v1/policy_rules/:id/retire` — optional `valid_until`; beendet
  die geltende Version standardmäßig gestern (heute Abend, wenn sie erst heute
  begann) und verwirft danach geplante Versionen. Die Regel bleibt mit
  `include_retired=true` lesbar. Eine Regel, deren keine Version je gegolten
  hat, oder eine schon beendete, ist ein `409`.
- `DELETE /api/v1/policy_rules/:id` — nur, solange **keine** Version je
  gegolten hat (`204`); sonst `409`, und der Ausweg ist, sie zu beenden.

Eine neue Version, ein Beenden und ein Löschen halten die Regel jeweils,
während sie deren Versionen lesen; zwei davon auf derselben Regel kommen daher
nacheinander dran: Eine Version, die hinzukommt, während ein Beenden läuft,
wartet darauf und wird gegen die beendete Regel geprüft, statt sie zu
überdauern. Eine Regel, die seit dem Lesen gelöscht wurde, ist bei allen drei
ein `404`.

**Was eine Regel liest, ist geschützt.** Das Löschen eines Wertpapiers, einer
Kategorie, einer Klassifizierung oder einer View, auf die eine Regelversion
(oder der Kontext einer Regel) verweist, antwortet mit **`409`** und
`errors.policy_rules` — `id`, `name` und `status` jeder Regel — sowie einem
`detail`, das jede Regel mit ihrer id und ihrem Status nennt
(`policy rule(s): #7 (in_force)`), nie mit ihrem Namen (#965), und den Ausweg
nennt. Eine Version, die gegolten hat, behält ihren Bezug als
Aufzeichnung dessen, was der Maßstab war; eine Regel zu beenden stoppt ihre
Auswertung, gibt das Objekt aber nicht frei. Nur eine Regel, deren keine
Version je gegolten hat, lässt sich löschen, und das gibt es frei. Ein
Wertpapier bleibt wie bisher stilllegbar (`is_retired`).

**Die Befunde.** `GET /api/v1/portfolios/:portfolio_id/policy_findings`
wertet die **heute** geltenden Regeln eines Auswertungskontexts (`view`; ohne:
die portfolioweiten Regeln) über die Zahlen aus, die das Produkt schon liefert,
und antwortet mit einem **Befund** je Regel, sortiert verletzt, nicht
bestimmbar, eingehalten:

- `state` ist `breached` (strikt jenseits der Linie), `ok` oder
  `undetermined` — die Zahl ließ sich nicht lesen. **Nicht bestimmbar ist nie
  bestanden** und wird standardmäßig nie ausgefiltert; es trägt seinen Grund
  `reason`: `insufficient_data` (eine verweigerte Portfolio-Kennzahl, mit
  `required` und `observations` aus ADR-0047), `undefined`, `no_active_plan`
  oder `no_target` (eine Abweichung ohne Ziel), `empty_basis` (ein Gewicht von
  nichts ist nicht 0 %), `unvalued` (der Gegenstand wird gehalten, seine
  Position lässt sich aber nicht bewerten, etwa ein Kurs ohne gespeicherten
  Wechselkurs), `subject_not_found` oder `not_measured`. Ein
  Wertpapier, das man schlicht nicht hält, hat das Gewicht `0` — das ist ein
  Messwert.
- jeder Befund trägt Identität und Worte der Regel, die Version, die Grenzen,
  den gemessenen `value` und den vorzeichenbehafteten Abstand `distance` zur
  nächsten Linie (Wert − Linie, auf der Skala der Kennzahl) sowie seine eigene
  `computation_basis` mit der gelesenen Quelle; die Antwort trägt `summary`
  (Anzahl je Zustand) und eine `computation_basis` mit Eingangsreihe, Fenster,
  Bezug und Umgang mit Lücken.
- `status` schränkt auf eine kommagetrennte Menge von Zuständen ein:
  `status=breached` ist die **abrufbare Alarmliste**. Sie wird abgerufen;
  nichts wird irgendwohin geschickt. Ein unbekannter Zustand ist ein `422`;
  `since` gilt bewusst nicht, weil Befunde eine abgeleitete Projektion sind
  und keine Zeilen.

Die Kennzahlen werden gelesen, nie berechnet: Einzeltitelgewicht und HHI der
Risikolinse, Kategorie- und Barmittelgewicht und die Abweichung des aktiven
Plans aus der Aufteilung (Anteile × 100), die Bewertung für den Anteil einer
View, und Volatilität und maximaler Drawdown der Portfolio-Kennzahlen im
Fenster der Regel (Verhältnisse × 100). Die Abfrage ist unter der
Datenversion des Portfolios und seinem Regelzähler zwischengespeichert; eine
geänderte Grenze wird beim nächsten Lesen ausgewertet.

**Was diese Schnittstelle nicht ist.** Eine Regel ist ein Maßstab, nie eine
Anweisung, und ein Befund trägt **keine Handlung** — keine Stückzahl, kein
Handelsverb, keinen Vorschlag; ein Meta-Test prüft die gerenderte Antwort
darauf. Hier wird kein Trade platziert, vorgeschlagen oder bemessen, nichts
wird irgendwohin geschickt, und keine Regel wird über einen Zeitraum vor ihrem
`valid_from` zurückgerechnet (das wäre Backtesting, Stufe (d) der
Scope-Leiter).

## Wechselkurse

- `GET /api/v1/exchange_rates` listet gespeicherte Wechselkurse. Kurse werden
  gegen den EUR-Hub gehalten (`1 base_currency = rate quote_currency`); andere
  Paare werden durch Triangulation abgeleitet, und `GBX` (Pence) wird als
  `GBP × 100` behandelt.
  `limit` behält die jüngsten Kurse (Standard 50000, max. 200000).
  Jeder Wechselkurs, den ein Schreibweg speichert, ist wie ein Kurs begrenzt:
  positiv, auf seine 15 Nachkommastellen gerundet, und nicht nach morgen
  datiert. Eine Synchronisierung verwirft einen Anbieterkurs außerhalb der
  Grenze, statt den Lauf scheitern zu lassen, und die Lesepfade für den
  jüngsten Wechselkurs nutzen nie eine gespeicherte Zeile nach dieser
  Grenze. Ein Kurs, den eine Version vor 2026.10.1 als 0 speichern konnte
  (ein Wert feiner als die Spalte), ist für jede Umrechnung kein Kurs: Die
  Zahl, die ihn braucht, schließt die Buchung aus und nennt sie oder meldet
  den Kurs als fehlend, wie an einem Tag ohne Kurs. Die Zeile wird weder
  gelöscht noch geändert — sie bleibt in dieser Liste, ein Nachladen der
  Historie ersetzt sie an einem Tag, den der Anbieter veröffentlicht, und
  das Startprotokoll nennt jede solche Zeile (Sicherheitsprüfung
  2026-10-12, K06).
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
  Anbieterfehler oder Kurse, die die Datenbank nicht speichern kann, liefern
  `502 Bad Gateway`, und nichts wird gespeichert. Ein Backfill läuft zur Zeit:
  Während einer läuft, liefert ein zweiter `409 Conflict`. Die menschliche
  Sicht ist die
  Schaltfläche **Historische Wechselkurse nachladen** in den Ausschluss-Hinweisen
  auf `/cashflow`. Seit Issue #1120 (Sprint-20-D-5) führt die Instanz dieses
  Backfill auch **von selbst** aus, einmal, nach ihrem Start-Abgleich und
  nach einem Import, wenn eine Buchung oder ein Verrechnungskonto in einer
  Nicht-EUR-Währung vor dem frühesten gespeicherten Kurs dieser Währung
  liegt, außer die Hintergrund-Downloads sind abgeschaltet
  (`PORTFOLIXIR_BACKGROUND_FETCH=off`). `scope=history` bleibt für einen
  Lauf von Hand: wo der automatische den Anbieter nicht erreicht hat, auf
  einer Instanz mit abgeschalteten Hintergrund-Downloads oder aus jedem
  anderen Grund für ein erneutes Holen; während der automatische läuft,
  antwortet es wie jedes zweite Backfill mit `409`. Es kommt kein Parameter
  hinzu, und kein Tool ändert sich.
  Seit Issue #1196 (Sprint-21-α2, Nachtrag zu ADR-0015 vom 2026-10-09,
  Punkt 6) leitet ein Historien-Lauf, der Kurse gespeichert hat, im selben
  Single-Flight-Lauf auch die Abrechnungsbeine jedes Kaufs und Verkaufs ab,
  der in der Währung seines Verrechnungskontos gebucht ist und keines der
  drei Beine gespeichert hat, im Journal unter dem Systemakteur
  `settlement_backfill`, wie `mix portfolixir.backfill_settlement_legs`.
  Die Antwort trägt `settlement_legs`: `{status, derived, skipped_no_rate,
  skipped_changed, stopped_at_transaction_id}`, wobei `status` `completed`
  ist (`derived` Buchungen haben ihre Beine bekommen, `skipped_no_rate`
  haben noch keinen Kurs für ihren Tag, `skipped_changed` haben nach dem
  Lesen des Laufs ein Bein bekommen, ihr Betrag oder eine andere Grundlage
  ihrer Beine wurde geändert, oder sie wurden gelöscht, und sie bleiben,
  wie sie sind, bis zu einem neuen Lauf), `not_run` (kein Kurs wurde gespeichert, jede Zählung `0`) oder
  `stopped` (das Hauptbuch hat eine Buchung abgelehnt: die Kurse bleiben
  gespeichert, die Zählungen sind `null`, `stopped_at_transaction_id` nennt
  sie, und ein neuer Lauf leitet den Rest ab; nach einem angehaltenen
  automatischen Lauf versucht es die Instanz nicht von selbst erneut, also
  ist der neue Lauf dieser Aufruf oder die Mix-Aufgabe). `scope=latest` antwortet mit `settlement_legs: null`: die tägliche
  Synchronisierung leitet keine Beine ab. Eine Buchung, die schon ein Bein
  trägt oder in einer dritten Währung bepreist ist, bleibt immer unberührt.
  Seit Issue #1311 trägt `settlement_legs` auch `skipped_zero_amount`
  (`null` bei einem Halt, `0`, wenn der Lauf nichts abgeleitet hat): die
  Buchungen, deren Handelsbetrag null ist, etwa eine Gratiszuteilung zum
  Preis 0, die kein Kurs in ein Bein umrechnet, sodass ein neuer Lauf sie
  nie ändert. `skipped_no_rate` zählt sie nicht mehr und zählt nur die
  Buchungen, deren Tag noch keinen Kurs hat; die Mix-Aufgabe listet die
  Zeilen mit Betrag null getrennt auf, nach ID und Datum.

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
- `DELETE /api/v1/classifications/:id` löscht eine eigene Klassifizierung mit
  ihren Kategorien, ihren gespeicherten Zuordnungen und jedem Plan darauf samt
  dessen Zielen. Jede dieser Zeilen wird als eigene Löschung journalisiert,
  bevor die Klassifizierung gelöscht wird; keine Zeile verschwindet allein
  durch eine Datenbank-Kaskade.
- `POST /api/v1/classifications/:classification_id/categories` fügt einer eigenen
  Klassifizierung eine `category` hinzu (`name`, optional `color`, `description`,
  `parent_id`, `position`).
- `PATCH /api/v1/classifications/:classification_id/categories/:id` patcht eine
  `category` (`name`, `color`, `description`, `parent_id`, `position` — alle
  optional). Die `classification_id` der Kategorie kann so nicht geändert werden.
  Bei beiden Schreibzugriffen muss `parent_id` eine Kategorie derselben
  Klassifizierung sein, die weder die Kategorie selbst noch eine ihrer
  Unterkategorien ist; jede andere Oberkategorie liefert `422` an `parent_id`,
  und nichts wird geschrieben, sodass ein Baum nie im Kreis läuft (E25 S4).
  Ein Baum hat höchstens 32 Ebenen: Eine Oberkategorie, unter der die
  geschriebene Kategorie oder die tiefste Kategorie des Teilbaums, den ein
  `PATCH` verschiebt, unter Ebene 32 läge, liefert ebenfalls `422` an
  `parent_id` und nennt die Ebene („would put a category on level 33; a
  classification has at most 32 levels“, Issue #940).
  Eine `position`, an einer Klassifikation oder einer Kategorie, ist eine
  ganze Zahl von -2147483648 bis 2147483647 (der Bereich der Spalte); jede
  andere liefert `422` an `position`, und nichts wird geschrieben. Die Schemas
  des Begleitdienstes tragen dieselben Grenzen.
- `DELETE /api/v1/classifications/:classification_id/categories/:id` löscht eine
  Kategorie mit den Kategorien darunter, den dort zugeordneten Wertpapieren und
  den dort abgelegten Zielen; jede Zeile wird als eigene Löschung
  journalisiert, die untersten Kategorien zuerst und die Kategorie selbst
  zuletzt.
- `?dry_run=true` an den drei kaskadierenden Löschungen (den beiden
  `DELETE`-Routen oben und `DELETE /api/v1/views/:id`) löscht nichts: Die
  echte Löschung läuft in einer Transaktion, die immer zurückgerollt wird,
  sodass die Antwort genau das ist, was die Löschung täte, nie eine daneben
  berechnete Zählung (Issue #894). Sie antwortet `200` mit, je Art von
  Zeile, die die Löschung erreicht, der Anzahl und den ids (aufsteigend),
  die sie entfernen würde; jede Art wird genannt, `0`, wo keine ginge. Der
  Probelauf einer Kategorie etwa:

  ```json
  {"data": {"dry_run": true, "would_remove": {"categories": {"count": 2, "ids": [12, 13]}, "assignments": {"count": 1, "ids": [40]}, "targets": {"count": 2, "ids": [21, 22]}}}}
  ```

  Eine Klassifizierung antwortet `classifications`, `categories`,
  `assignments`, `target_plans` und `targets`; eine Kategorie `categories`
  (sie selbst und die darunter), `assignments` und `targets`; eine View
  `views`, `view_include_buckets`, `view_exclude_buckets`, `target_plans`,
  `targets` und `depot_snapshots`. Eine Löschung, die der Server ablehnt,
  lehnt ihr Probelauf mit demselben Status und Body ab: `422` für eine
  eingebaute Klassifizierung, `409` mit den Regeln, die sie lesen, `404` für
  eine unbekannte id. Nichts wird geschrieben, auch nicht ins Audit-Journal.
  Die Transaktion des Probelaufs ist `REPEATABLE READ`, sodass seine
  Lesungen vor und nach der Löschung einen Snapshot sehen und eine Zeile,
  die eine gleichzeitige Transaktion inzwischen gelöscht hat, nie genannt
  wird; ein Probelauf, der auf eine solche Änderung trifft, liefert `409`
  `{"errors": {"code": "concurrent_change", "detail": "..."}}`, nichts wird
  gelöscht, und ein erneuter Versuch entscheidet.
  Fehlt der Wert oder ist er `false`, ist es die Löschung selbst; jeder
  andere Wert, auch ein leeres `dry_run=`, liefert `422`
  `{"errors": {"dry_run": ["is invalid"]}}`, und jeder andere
  Query-Parameter (`dryRun`, `dry-run`, ...) liefert `422` mit seinem Namen,
  `{"errors": {"dryRun": ["is unknown: this delete takes only dry_run"]}}`;
  beides löscht nichts, sodass ein Tippfehler die Frage nie zur Löschung
  macht. Die MCP-Tools lehnen einen falsch geschriebenen Schlüssel vor jeder
  Anfrage ab.
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
Zuordnungs-Schreibvorgänge werden journalisiert (ADR-0017). Die Definition
einer View ebenfalls (ADR-0018 §5 in der Fassung von Sprint 16), weil eine
gültige Richtlinienregel sie liest: `PATCH /api/v1/views/:id`, `PUT
/api/v1/views/:id/buckets` und `DELETE /api/v1/views/:id` hinterlassen je
einen Eintrag mit `resource_type=view` unter der View, dessen `before` und
`after` die ganze Definition tragen — `name`, `include_all`,
`include_bucket_ids` und `exclude_bucket_ids`; wer die gespeicherte
Definition erneut sendet, hinterlässt keinen. Das Anlegen einer View wird
nicht journalisiert: Noch keine Regel kann sie lesen.

- `GET /api/v1/buckets` listet Buckets (`id`, `name`, `color`).
- `POST /api/v1/buckets` legt einen Bucket aus einem `bucket`-Objekt an (`name`
  erforderlich, optionales `color`). Ein leerer oder doppelter Name ergibt `422`.
- `GET /api/v1/buckets/:id` liefert einen Bucket; unbekannte ids ergeben `404`.
- `PATCH /api/v1/buckets/:id` ändert `name`/`color` eines Buckets.
- `DELETE /api/v1/buckets/:id` löscht einen Bucket (`204 No Content`). Zuvor
  wird er aus jeder View und jeder Zuordnung, die ihn nennt, über deren
  journalisierten Schreibweg entfernt, sodass jeder betroffene Eigentümer
  seinen eigenen Eintrag erhält: die Sets jeder View vorher und nachher, jedes
  Standard-Set eines Depots und Set eines Geldkontos, jede Positions-Zuordnung.
  **Eine Position, deren bestimmte Buckets nur aus diesem bestehen, bleibt
  ausdrücklich leer** („keine Buckets“) und erbt nicht vom Depot; sie gerät so
  in keine View, in der sie vorher nicht war. Der `delete`-Eintrag des Buckets
  trägt seine Zeile und jede Zugehörigkeit, die er hatte (`memberships`:
  `view_include`, `view_exclude`, `depot_defaults`, `cash_accounts`,
  `position_overrides`). Auch ein Bucket, den die View einer Richtlinienregel
  liest, wird gelöscht; ein schon gelöschter Bucket antwortet mit `404`. Das
  Entfernen des Buckets aus einem Set prüft die exklusive Scope-Dimension nicht
  erneut, sodass ein Set, das gespeichert wurde, bevor diese Regel galt, das
  Löschen nie blockiert; ein Set, aus dem der Bucket nicht entfernt werden
  kann, antwortet mit `422`, und nichts wird gelöscht.
- `GET /api/v1/views` listet Views. Jede View trägt `include_all`, das aufgelöste
  `include`-Set (das Literal `"all"` unter `include_all`, sonst eine Liste von
  Bucket-ids) und die `exclude`-Liste von Bucket-ids.
- `POST /api/v1/views` legt eine View aus einem `view`-Objekt an (`name`
  erforderlich, optionales `include_all`, Standard `true`).
- `GET /api/v1/views/:id` liefert eine View mit ihrem aufgelösten Filter.
- `PATCH /api/v1/views/:id` ändert `name`/`include_all` einer View, gesendet
  in einem `view`-Objekt. Eines der Felder auf oberster Ebene des Bodys,
  außerhalb davon, ergibt `422` mit dem Feldnamen (`{"include_all": ["must be
  sent inside the view object"]}`) und ändert nichts (Issue #1315). Ebenso
  ein `include` oder `exclude` auf oberster Ebene, die Bucket-Sets, die `PUT
  /api/v1/views/:id/buckets` setzt (`{"include": ["is set with PUT
  /api/v1/views/:id/buckets"]}`).
- `DELETE /api/v1/views/:id` löscht eine View und ihre Bucket-Sets (`204`); die
  auf sie bezogenen Pläne samt Zielen und ihre Depot-Schnappschüsse werden je
  als eigene Löschung journalisiert, bevor die View gelöscht wird. Mit
  `?dry_run=true` löscht sie nichts und antwortet `200` mit dem, was sie
  entfernen würde, wie bei den Löschungen der Klassifizierungen oben
  beschrieben.
- `PUT /api/v1/views/:id/buckets` ersetzt die Include-/Exclude-Bucket-Sets einer
  View. Body: `{"include": [..], "exclude": [..], "include_all": false}` (die
  Sets optional, Standard `[]`, Listen von Bucket-ids). Optionales
  `include_all` wird mit beiden Sets im selben journalisierten Schreibvorgang
  gespeichert, wie die Bucket-Auswahl es speichert: `false` verengt eine View,
  die `"all"` einschließt, auf die Include-Liste, `true` weitet sie wieder;
  weggelassen oder `null` bleibt das Flag, wie es ist (Issue #1315). Eine
  fehlerhafte id-Liste oder ein `include_all`, das kein Boolean ist, ergibt
  `422` mit dem Feldnamen; ein Bucket, der in einer Liste zweimal steht, zählt
  einmal.
- `GET /api/v1/views/:view_id/valuation` liefert die Live-Bewertung einer View
  **über alle Portfolios** (ADR-0024) in der Form der Portfolio-Bewertung mit
  `view_id` statt `portfolio_id`; jedes zur View passende Konto zählt genau
  einmal, `overlap` nennt die Konten mit mehreren eingeschlossenen Buckets,
  und `unvalued_cash_count` zählt die zur View passenden Geldkonten ohne
  Kurspfad mit einem Saldo ungleich null, wie bei der Portfolio-Bewertung.
  `include_positions=false` (FR-37, #740 — derselbe Parameter wie bei der
  Portfolio-Bewertung) liefert nur den Roll-up: Summen, Cash-Salden und
  Cash-Quote ohne die Positionszeilen; die Antwort benennt
  `positions_included`. Ein ungültiger Wert ist ein `422`.
- `GET /api/v1/valuation` liefert die **Summe über jedes Portfolio** ohne View
  (#1007): die unbegrenzte Vereinigung aller Depots, Positionen und
  Geldkonten, jedes einmal gezählt, immer in EUR, und die erste Zahl, die eine
  frische Instanz beantworten kann, da sie noch keine View hat. Sie entspricht
  der Summe der Übersicht, wenn das erste Portfolio die Basiswährung EUR hat
  und keine Standard-Ansicht gesetzt ist; die Übersicht bewertet ihre Karte in
  dieser Währung und folgt der Standard-Ansicht, sonst können beide Zahlen
  abweichen. Die Form ist die der View-Bewertung mit
  `view_id: null` und ohne `view`-Spiegelung (`overlap` meldet keine
  Überschneidung, `matches_no_accounts` ist `false`), und die
  `valuation_note` benennt den Bereich. `include_positions=false` liefert nur
  den Roll-up, wie bei der View-Abfrage; ein ungültiger Wert ist ein `422`.
  MCP: `portfolixir.views.valuation` ohne `id`. Performance,
  Benchmark-Vergleich und Beitragsanalyse haben dieselbe Form ohne View
  (#1056), unten nach ihren View-Abfragen aufgeführt.
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
- `GET /api/v1/views/:view_id/performance/benchmark` liefert den
  Benchmark-Vergleich der View **über alle Portfolios** (ADR-0046 §3):
  derselbe deduplizierte Konten-Scope, den View-Bewertung und
  View-Performance abdecken, sodass Gesamtwert, Rendite und Benchmark der
  View über dieselben Konten sprechen. `benchmark=` ist Pflicht, `period`,
  `year`, `from`/`to` und `series=true` verhalten sich wie beim
  Portfolio-Benchmark-Endpunkt; die Antwort spiegelt dessen Form mit
  `view_id` statt `portfolio_id`. Unbekannte und fehlerhafte View-ids
  liefern `404`, ein fehlerhafter Zeitraum oder eine fehlerhafte Benchmark
  `422`.
- `GET /api/v1/views/:view_id/performance/contribution` liefert die
  Beitragsanalyse der View **über alle Portfolios** (FR-41, ADR-0051 §6):
  derselbe deduplizierte Konten-Scope, den die View-Performance abdeckt, in
  EUR, sodass `totals.result` deren Geldergebnis ist und eine in mehreren
  Portfolios gehaltene Position eine Zeile ist. `period`, `year` und
  `from`/`to` verhalten sich wie beim Portfolio-Beitragsendpunkt; die Antwort
  hat dessen Form mit `portfolio_id: null`, `view_id` und der gespiegelten
  View. Unbekannte und fehlerhafte View-ids liefern `404`, ein fehlerhafter
  Zeitraum `422`.
- `GET /api/v1/performance`, `GET /api/v1/performance/benchmark` und
  `GET /api/v1/performance/contribution` sind die drei Abfragen oben **ohne
  View** (#1056): jedes Konto jedes Portfolios, jedes einmal gezählt, der
  Bereich, den die Vermögensseite „Alles“ nennt, lesbar, bevor es eine View
  gibt. Jede nimmt die Parameter ihrer View-Abfrage (`benchmark=` bleibt beim
  Vergleich Pflicht) und antwortet in deren Form mit `view_id: null` (und
  `portfolio_id: null` bei der Beitragsanalyse) und ohne `view`-Spiegelung;
  ein fehlerhafter Zeitraum ist ein `422`, eine fehlende oder abgelehnte
  Benchmark ein `422` auf `benchmark`. Keine nimmt einen Bereich: `view=`
  und `portfolio_id=` werden ignoriert, wie bei `GET /api/v1/valuation`.
  **Sie antworten in EUR**, über den
  EUR-Hub, wie die View-Abfragen und `GET /api/v1/valuation`. Die
  Vermögensseite rechnet ihre Alles-Zahlen in der Basiswährung des ersten
  Portfolios, sodass beide abweichen, wenn diese nicht EUR ist, und jede
  Antwort sagt das: `computation_basis.input_series` schließt mit dem Bereich
  (jedes Konto jedes Portfolios, keine View) und der Währung. Eine View mit
  `include_all` und ohne Ausschluss liefert dieselben Zahlen. MCP:
  `portfolixir.views.performance`, `portfolixir.views.benchmark` und
  `portfolixir.views.contribution` ohne `id`.
- `GET /api/v1/views/:view_id/category-results?classification_id=<id>`
  liefert das Ergebnis je Kategorie (ADR-0041) der zur View passenden
  Positionen **über alle Portfolios**, jedes Konto einmal gezählt (#901). Die
  Form ist die der Portfolio-Abfrage mit `scope: "view"`, `portfolio_id: null`
  und gespiegelter View. Die Werte sind in EUR: Der investierte Betrag eines
  Mitglieds ist der tatsächlich gezahlte Abrechnungsbetrag (ADR-0033), also
  hat ein Mitglied aus einem Portfolio mit anderer Basiswährung als EUR keine
  EUR-Kosten zum Addieren und fehlt mit `missing_base_cost`, statt über
  Währungen hinweg summiert zu werden. Unbekannte und fehlerhafte View-ids
  liefern `404`, eine fehlende `classification_id` `422`, eine unbekannte
  `404`. MCP: `portfolixir.portfolios.category_results` mit `view` und ohne
  `portfolio_id`.
- `GET /api/v1/category-results?classification_id=<id>` liefert das Ergebnis
  je Kategorie **jedes Portfolios, ohne View** (#1091): den Roll-up, den die
  Klassifizierungsseite zeigt, in der Form der Portfolio-Abfrage mit
  `scope: "all"`, `portfolio_id: null`, `view_id: null`,
  `base_currency: "EUR"` und ohne `view`-Spiegelung. Die EUR-Regel der
  View-Abfrage gilt: Ein Mitglied aus einem Portfolio mit anderer
  Basiswährung als EUR fehlt mit `missing_base_cost`, und `excluded_members`
  nennt es mit seinen Einstandskosten in der Währung, in der sie bezahlt
  wurden; `basis_note` schließt mit dem Bereich. Sie nimmt keinen Bereich:
  `view=` und `portfolio_id=` werden ignoriert, wie bei
  `GET /api/v1/valuation`. Eine fehlende `classification_id` ist ein `422`,
  eine unbekannte ein `404`. MCP:
  `portfolixir.portfolios.category_results` ohne `portfolio_id` und ohne
  `view`.
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

Die vier Zuordnungs-Schreibvorgänge oben halten das Depot oder Geldkonto,
während sie sein Set ersetzen. Zwei Schreibvorgänge auf dasselbe Konto kommen
daher nacheinander dran: Es bleibt das Set dessen, der zuletzt festschreibt,
nie eine Mischung aus beiden. Ein Konto, das gelöscht wird, während der
Schreibvorgang wartet, antwortet mit `404` und es wird nichts geschrieben. Die
beiden Schreibvorgänge der Positions-Überschreibung halten nach dem Depot auch
das Wertpapier; ein Wertpapier, das gelöscht wird, während sie warten,
antwortet ebenso mit `404` (#919).

Die Analyse-Endpunkte akzeptieren einen optionalen `view`-Query-Parameter (eine
View-id), um das Ergebnis auf die Bestände der View einzugrenzen:

- `GET /api/v1/portfolios/:portfolio_id/valuation?view=<id>`
- `GET /api/v1/portfolios/:portfolio_id/allocation?classification_id=<id>&view=<id>`
- `GET /api/v1/portfolios/:portfolio_id/performance?view=<id>`
- `GET /api/v1/portfolios/:portfolio_id/performance/contribution?view=<id>`
- `GET /api/v1/portfolios/:portfolio_id/risk?view=<id>`
- `GET /api/v1/portfolios/:portfolio_id/category-results?classification_id=<id>&view=<id>`

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
(ADR-0024): die **Standard-Ansicht**, mit der Vermögensseite und Übersicht
öffnen, wenn in der UI keine Ansicht ausdrücklich gewählt wurde, und den
**Crash-Benchmark**, den die Crash-Regel liest (ADR-0058 §1). Finanzielle
Decimals kommen hier nicht vor.

- `GET /api/v1/settings/default_view` liefert die aktuelle Voreinstellung:
  `{"data": {"view_id": null, "view": null}}` wenn keine gesetzt ist (die
  eingebaute Alles-Sicht), sonst die id plus ein `view: {id, name}`-Echo.
- `PUT /api/v1/settings/default_view` setzt sie. Body: `{"view_id": <id>}` mit
  einer existierenden View-id, oder `{"view_id": null}` zum Zurücksetzen auf
  Alles. Eine unbekannte View-id liefert `404` (nichts wird geschrieben); eine
  fehlerhafte `view_id` liefert `422`. Die Antwort entspricht dem `GET`-Format.
  Eine Änderung wird unter dem Prinzipal des Tokens journalisiert
  (`resource_type` `setting`, ein `upsert`, beim Zurücksetzen ein `delete`),
  sodass die vorige Voreinstellung in ihrem Vorher-Abbild steht.
- `PUT /api/v1/settings/crash_benchmark` benennt den **Crash-Benchmark**
  (ADR-0058 §1), das Wertpapier, dessen Schlusskurse die Crash-Regel liest.
  Body: `{"security_id": <id>}` mit einem beliebigen Wertpapier, das
  mindestens einen gespeicherten Kurs hat, mit `is_benchmark` markiert oder
  nicht, oder `{"security_id": null}` zum Zurücksetzen; eine Voreinstellung
  gibt es nicht. Die Antwort ist `{"data": {"security_id", "security": {id,
  name, is_benchmark, benchmark_security}}}` (`benchmark_security` ist
  `flagged`, `held` oder `unheld`), beim Zurücksetzen beide `null`. Ein
  Wertpapier ohne gespeicherten Kurs liefert `422` mit `errors.security_id`
  `["has no stored quote"]`; eine unbekannte id `["is not a benchmark
  security"]`, eine wegfusionierte dasselbe mit `errors.merged_into`
  `{kind, id}`, das den Überlebenden nennt; eine fehlerhafte oder fehlende
  `security_id` und jedes andere Feld liefern `422`, das es nennt. Bei einer
  Ablehnung wird nichts geschrieben. Die Änderung wird unter dem Prinzipal
  des Tokens journalisiert (`resource_type` `setting`). Sie gilt für den
  Bildschirm und jeden Agenten gleich: Ein Wechsel ändert die erkannten
  Fenster, die für den früheren Benchmark vergebenen Namen wandern nach
  `unmatched_names` und kehren zurück, wenn er wieder gewählt wird, und das
  Zurücksetzen lässt die manuellen Fenster stehen (siehe Crash-Fenster
  oben). Das MCP-Tool ist `portfolixir.crashes.benchmark_put`.

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
  übersprungene Anzahl. Der Hash ist eindeutig (zwei verschiedene Zeilen
  teilen nie einen), und jeder Hash, der vorher gespeichert wurde, wird weiter
  gefunden. Eine von einer Zeile abgespaltene Steuererstattung wird mit dieser
  Zeile gehasht und über ihre eigenen Hashes und ihren wirtschaftlichen
  Schlüssel geprüft, sodass zwei gleiche Erstattungen zweier verschiedener
  Verkäufe beide gebucht werden, eine bereits importierte Erstattung unter
  beiden Formeln gefunden wird und eine Erstattung, die zu einer schon
  importierten Zeile hinzukam, gebucht wird; eine Erstattung, deren Zeile nicht
  importiert wird, wird mit ihr übersprungen.
- **Eine Umbenennung ist sicher für den nächsten Import (ADR-0050 §3, §4).**
  Der Hash wird geprüft, bevor irgendetwas aufgelöst wird, und ein
  Verrechnungskonto oder Depot entsteht erst mit seiner ersten neuen Buchung,
  sodass eine Umbenennung über
  `PATCH /api/v1/cash_accounts/:id` oder `PATCH /api/v1/securities_accounts/:id`
  (`portfolixir.cash_accounts.update`, `portfolixir.securities_accounts.update`,
  deren Beschreibungen das sagen) kein leeres Konto unter dem alten Namen
  hinterlässt. Die Umbenennung behält den alten Namen in `former_names`, und der
  Import löst den Kontonamen einer Datei zuerst über den aktuellen Namen auf,
  dann über die früheren Namen, sodass auch ein Export, der sich in Portfolio
  Performance verändert hat (andere Nachkommastellen, eine bearbeitete
  Buchung), auf das umbenannte Konto bucht und nichts doppelt. Was außen
  bleibt: Ein alter Name, den ein anderes Konto noch als aktuellen Namen trägt,
  bucht auf jenes Konto, und eine Umbenennung, die älter ist als das
  Audit-Journal der Konten, hat nichts zum Merken hinterlassen. Ändert der
  Operator eine Vorbelegung in der Vorschau auf ein Konto anderen Namens, wird
  die Zuordnung standardmäßig als früherer Name dieses Kontos gemerkt. Ist
  der Name früherer Name eines anderen Kontos, verschiebt die Importseite ihn
  erst, nachdem seine Zeile das vor dem Bestätigen gesagt hat, und das
  Ergebnis nennt das Konto, das ihn abgab;
  `DELETE /api/v1/cash_accounts/:id/former_names?name=` (oder das Gegenstück
  unter `securities_accounts`) entfernt einen früheren Namen weiterhin von
  Hand. Eine Umbuchung, deren beide Seiten auf ein Konto führen, wird
  übersprungen und aufgeführt, nie ein gescheiterter Import.
- **Eine Zusammenführung von Geldkonten ist sicher für den nächsten Import
  (ADR-0050 §2, §7).** Nach `POST /api/v1/cash_accounts/:id/merge` legt ein
  erneut angewendeter, schon importierter Export nichts an, byte-gleich oder
  verändert: Die verschobenen Buchungen behalten ihre Inhalts-Hashes, jede
  Buchung, die die Zusammenführung gelöscht hat, hat ihren Hash stillgelegt,
  der Name der Quelle führt als früherer Name zum Ziel, und eine Umbuchung
  zwischen beiden wird als intern übersprungen. Neue Zeilen eines späteren
  Exports, die das zusammengeführte Konto nennen, werden einmal gebucht, auf
  das Ziel. Zwei Grenzen werden genannt, nicht versteckt: Eine neue Zeile,
  deren wirtschaftlicher Schlüssel einer vorhandenen Buchung des Ziels
  gleicht, gilt als diese Buchung (gemeldet mit der Ebene `economics`), und
  eine Zeile, die auf oder vor einem gesetzten Saldo datiert ist, den die
  Zusammenführung angepasst hat, wird gebucht, aber von diesem Saldo
  aufgefangen — der Import führt sie als hinter einem angepassten gesetzten
  Saldo gebucht auf, mit dem Saldo.
- **Eine Zusammenführung von Depots ist sicher für den nächsten Import
  (ADR-0050 §2, §7).** Nach `POST /api/v1/securities_accounts/:id/merge` legt
  ein erneut angewendeter, schon importierter Export nichts an, byte-gleich
  oder verändert: Die verschobenen Buchungen behalten ihre Inhalts-Hashes,
  jede Buchung, die die Zusammenführung gelöscht hat, hat ihren Hash
  stillgelegt, der Name des Quelldepots führt als früherer Name zum Ziel, und
  eine Wertpapierumbuchung zwischen beiden wird als intern übersprungen. Neue
  Zeilen eines späteren Exports, die das zusammengeführte Depot nennen,
  werden einmal gebucht, auf das Ziel. Eine neue Zeile, deren
  wirtschaftlicher Schlüssel einer vorhandenen Buchung des Ziels gleicht,
  gilt als diese Buchung (gemeldet mit der Ebene `economics`).
- **Eine Zusammenführung von Wertpapieren ist sicher für den nächsten Import
  (ADR-0050 §2, §9).** Nach `POST /api/v1/securities/:id/merge` legt ein
  erneut angewendeter, schon importierter Export nichts an, byte-gleich oder
  verändert, welche ISIN er auch trägt und bei jeder der beiden
  Identitätswahlen: Die verschobenen Buchungen behalten ihre Inhalts-Hashes,
  jede Buchung, die die Zusammenführung gelöscht hat, hat ihren Hash
  stillgelegt, und jede Identität der Quelle — ihre ISIN (jetzt die des Ziels
  oder eine frühere ISIN des Ziels), ihre früheren ISINs, die Identität, die
  ihr Import aufgezeichnet hat — führt zum Ziel. Neue Zeilen eines späteren
  Exports, die das zusammengeführte Wertpapier über eine davon nennen, werden
  einmal gebucht, auf das Ziel. Die Zusammenführung wird abgelehnt, statt
  eine Identität unaufgelöst zu lassen (`identity_unresolvable`).
- **Was einen erneuten Import unverändert übersteht, gleiche ids, exakte
  `Decimal`-Werte:** Klassifizierungs-Zuordnungen; jede Zielplan-Version mit
  ihren Kategorie- und Positionszielen sowie dem Cash-Ziel; `note` und
  `attributes` jedes Wertpapiers einschließlich eigener Schlüssel; das
  **Research-Log** (`/api/v1/securities/:id/notes` — die nur anhängbaren
  Einträge und der daraus abgeleitete `thesis_state`, ADR-0044); die
  **Wertpapier-Termine** (`/api/v1/securities/:id/events` — jeder datierte
  Kalenderfakt mit seiner Qualifizierung, seiner Bestätigung und seinem
  `checked_at`, ADR-0048 §7); die **eigenen Regeln**
  (`/api/v1/portfolios/:id/policy_rules` — jede Regel und jede Version mit
  ihren Bezugs-ids, Grenzen und Zeiträumen, ADR-0049 §8); Wertpapier-ids und
  `updated_at`. Festgehalten in
  `test/portfolixir/imports/reimport_preservation_test.exs` seit Issue #664
  (Research-Log ergänzt durch #748, Wertpapier-Termine durch #829, eigene
  Regeln durch #864).
- **Ein veränderter erneuter Import** (eine Umbenennung, ein erfasster
  ISIN-Wechsel, der über einen Alias oder eine explizite Zuordnung aufgelöst
  wird) hält dieselbe Garantie für die zugeordneten Wertpapiere; nur die
  wirklich neuen Buchungen landen.
- **Dort ausgesprochen, wo ein Agent liest (Issue #831).** Die Beschreibungen
  der acht MCP-Reads, die die Garantie schützt — `portfolixir.notes.list`,
  `.unreviewed`, `.uncorroborated`, `.expiring` und `portfolixir.events.list`,
  `.upcoming`, `.unconfirmed`, `.stale` — tragen den Satz „A Portfolio
  Performance re-import does not destroy the research log or the security
  events", sodass ein Agent die Antwort in der Tool-Liste findet, die er
  ohnehin liest, statt auf dieser Seite. Der veränderte Pfad hält neben den
  Terminen auch das Research-Log fest. Die Regel-Reads
  (`portfolixir.policy_rules.list`, `.get` und
  `portfolixir.portfolios.policy_findings`) tragen den eigenen Satz „A
  Portfolio Performance re-import does not destroy the policy rules", und der
  veränderte Pfad hält eine Regel über das Wertpapier mit neuer ISIN fest.
- **Nicht abgedeckt:** eine in der Quelle geänderte Buchung. Eine bearbeitete
  Transaktion hasht anders und wird als neue Zeile neben der alten importiert;
  die alte Buchung wird über `PATCH`/`DELETE /api/v1/transactions/:id`
  entfernt oder korrigiert. Die Garantie betrifft, was Portfolixir rund um
  die Historie pflegt, nicht den Abgleich zweier Versionen der Historie
  selbst.

Ein Research-Log, ein Kalender, eine Regel, ein Plan oder eine Zuordnung „verschwindet“
also nie beim nächsten Import; ein Agent, der etwas anderes beobachtet, hat einen Defekt
gefunden, keine dokumentierte Grenze.

## Kontraktversion

Die Oberfläche sagt, was sie ist, damit ein Konsument bemerkt, wenn sie sich
ändert (ADR-0044 §8). Eine Tool-Beschreibung wird einmal beim Verbinden
gelesen; dieser Read ist der Weg, auf dem ein Agent erfährt, dass die Liste
oder die Beschreibungen sich bewegt haben.

- `GET /api/v1/contract` liefert das **Kontrakt-Manifest**: `version` (eine
  ganze Zahl, die des neuesten Eintrags), `last_changed_at` (ISO-Datum),
  `endpoints_total`, `tools_total` und `entries` neueste zuerst — jeder mit
  `version`, `date`, `summary`, den `endpoints` (`"VERB /api/v1/pfad"`) und
  `tools`, die die Änderung hinzugefügt hat, `parameters` (ein Satz je
  Parameter, der zu einem bestehenden Read kam) sowie etwaigen
  `removed_endpoints` / `removed_tools`. Optionales `since=JJJJ-MM-TT`
  verengt die Einträge auf die **streng nach** diesem Tag datierten und
  beantwortet `changed` — die `?since=`-Idee auf den Kontrakt statt auf die
  Zeilen angewandt: `last_changed_at` speichern, damit abfragen und Tool-Liste
  und Beschreibungen neu lesen, wenn `changed` `true` ist. Ein ungültiges
  `since` ist ein `422`.
- Das Manifest wird **im Code gepflegt** (`PortfolixirWeb.Api.V1.Contract`),
  und ein Meta-Test bindet das `/api/v1`-Inventar des Routers und das Tool-
  und das Prompt-Inventar des MCP-Begleitdienstes in beiden Richtungen daran,
  sodass eine ohne Manifest-Eintrag hinzugefügte, umbenannte oder entfernte
  Route, ein solches Tool oder ein solcher MCP-Prompt den Build scheitern
  lässt; ein Eintrag nennt einen Prompt in seinem `summary` und seinen
  `parameters`. Der erste Eintrag hält die Sprint-9-Ergänzungen fest — das
  Research-Log, den Thesenstand, die Parameter `include_positions` /
  `min_drift` auf View-Ebene und Positionsebene (#740), den historischen
  Backfill-Scope (#737) und diesen Read.

## Version der Instanz

Die Instanz sagt, aus welcher Version sie gebaut wurde (FR-55), damit ein
Agent weiß, mit welchem Release er spricht, ohne den Betreiber zu fragen.

- `GET /api/v1/version` liefert `kind`, `value` und `url`: `release` (das
  Kalender-Tag `YYYY.M.N`, auf dem der Build genau steht; `url` seine
  Versionshinweise auf GitHub), `build` (`Branch · kurzer Hash · Commit-Datum`,
  ohne Branch bei einem abgehängten Checkout; `url` der Commit auf GitHub)
  oder `unknown` (`value` `"unknown"`, `url` `null`). Daneben `tag`, `branch`,
  `commit` (der volle Hash, wo er bekannt ist), `date` (das eigene Datum des
  Commits, ISO), `source` (`build_arguments`, `git` oder `none`) und eine
  `version_note`. Die Version wird **einmal beim Kompilieren** gelesen: aus den
  Build-Argumenten `PORTFOLIXIR_VERSION`, `PORTFOLIXIR_COMMIT` und
  `PORTFOLIXIR_BUILD_DATE`, wenn eines gesetzt ist (der Weg des
  Release-Images, [Home-Deployment](../home-deployment.html), „Upgrade“),
  sonst von `git` im Quell-Checkout, sonst `unknown` — nie
  geraten. Dem Link in `url` folgt der Betreiber; die App fragt nichts an.

## Audit-Journal

Jeder finanzielle Schreibvorgang (Anlegen, Ändern, Löschen) wird in einem
append-only Audit-Journal in derselben Datenbanktransaktion wie der Schreibvorgang
selbst festgehalten, sodass jede Änderung — auch Löschungen — nachvollziehbar und
zurechenbar bleibt. Marktdaten-Synchronisierung (Kurse und Wechselkurse) ist
betriebliche Datenpflege und wird bewusst **nicht** journalisiert. Ein Kurs,
den jemand schreibt, ist keine Synchronisierung: Der Kurs-Upsert und die
Freigabe manueller Kurse werden unter `resource_type=security_quotes`
journalisiert, unter der Id des Wertpapiers, mit den ersetzten oder
freigegebenen Zeilen als Vorher-Abbild.

- `GET /api/v1/journal` listet Journal-Einträge, neueste zuerst. Jeder Eintrag
  trägt `actor_type` (`owner_ui`, `api_token_rw`, `api_token_ro`,
  `import_session`, `system_job`) und ein optionales `actor_label` (bei einem
  API-Token der Name seines `PORTFOLIXIR_API_TOKENS`-Eintrags; `null` beim
  unbenannten Standard), die
  `operation` (`create`, `update`, `delete`, `upsert`), den betroffenen
  `resource_type`/`resource_id` sowie die `before`/`after`-Schnappschüsse
  (Decimal-Werte sind Strings). Optionale Filter: `resource_type`,
  `resource_id`, `actor_type`, `operation`, `limit` (Standard 100, max. 1000)
  und `include_scenarios` (`true`, um persistierte Was-wäre-wenn-Schreibvorgänge
  einzuschließen; standardmäßig nur echte Schreibvorgänge). Die Antwort ist
  selbstbeschreibend: ein `meta`-Objekt nennt den `as_of`-Zeitpunkt, die
  Sortierung `order` (`inserted_at:desc,id:desc`), die Anzahl `count` und die
  angewandten `filters`.
  Die Seite Audit-Journal (`/journal`) nimmt dieselben Parameter und listet
  dieselben Einträge, sodass ein Agent dem Operator einen Link auf die
  gelesenen Zeilen geben kann: `/journal?actor_type=api_token_rw&operation=delete`.
- `since` (ein Datum, ein Zeitpunkt oder der Cursor, den eine volle Seite als
  `as_of` beantwortet hat) macht den Read zum seitenweisen Delta, wie jeden
  begrenzten Delta-Read (K17, oben): die Einträge, die streng nach dem
  Schnitt geschrieben wurden, **älteste zuerst** (`meta.order`
  `inserted_at:asc,id:asc`), mit `since`, `has_more`, einer `delta_note` und
  einem `as_of` auf oberster Ebene, das das nächste `since` ist — auf einer
  vollen Seite ein Cursor an ihrem letzten Eintrag,
  `2026-10-28T09:15:02.250000Z~48`, sein Zeitpunkt auf die Mikrosekunde, wie
  das Journal stempelt. `meta.as_of` bleibt der Zeitpunkt des Reads, nicht
  der Cursor. Es kombiniert sich mit den fünf Filtern, `meta.filters.since`
  spiegelt es, und `limit` behält Standard und Höchstwert. Ein Lauf ab
  `since=1970-01-01`, der jedes `as_of` zurückgibt, erreicht jeden Eintrag
  mindestens einmal und überspringt keinen, auch die jenseits der neuesten
  1000, die ein Read ohne `since` nicht zeigen kann. Eine volle Seite, die
  einen noch laufenden Schreibvorgang erreicht, antwortet ein `as_of` ohne
  `~<id>`, die In-flight-Grenze: später erneut abfragen, nicht sofort, und
  damit rechnen, dass der nächste Read schon gelesene Einträge erneut
  liefert, wie die `delta_note` der Antwort sagt. Ohne `since` bleibt der Read unverändert,
  neueste zuerst. Die Seite nimmt dasselbe `since`
  (`/journal?since=2026-10-28`, oder den Zeitpunkt oder Cursor, den der Read
  beantwortet hat) und listet dieselben Einträge, neueste zuerst.
  SOLL-Ziel-Schreibvorgänge (Kategorie- und Positionszeilen gleichermaßen)
  werden unter `resource_type=target` journalisiert, Schreibvorgänge an
  Planversionen unter `resource_type=target_plan`.
- Das `before` einer Änderung oder Löschung ist die Zeile, wie sie gespeichert
  war, als der Schreibvorgang sie gesperrt hat, und das `after` einer Änderung
  die Zeile, wie sie danach gespeichert ist — Dezimalwerte in der Skala ihrer
  Spalte. Zwei Schreibvorgänge auf Grundlage eines Lesevorgangs reihen sich
  daher aneinander: Das `before` des zweiten ist das `after` des ersten. Ein
  Schreibvorgang auf einen inzwischen gelöschten Datensatz antwortet mit `404`
  und hinterlässt keinen Eintrag.
- Der Eintrag einer Bucket-Zuordnung (`depot_bucket_assignment`,
  `cash_account_bucket_assignment`, `position_bucket_override`) bildet die
  Menge ab, wie sie gespeichert ist, ihre `bucket_ids` nach id geordnet:
  `before` ist die Menge, als der Schreibvorgang ihr Konto gesperrt hat,
  `after` die Menge, die er gespeichert hat. Bei einer Positionsausnahme ist
  `before` `null`, wo die Position die Menge ihres Depots geerbt hat, und
  `[]`, wo sie keine Buckets hatte. Wer die gespeicherte Menge erneut sendet,
  hinterlässt keinen Eintrag, und ebenso, wer die Ausnahme einer Position
  aufhebt, die schon erbt (#953).
- Das `after` einer Löschung ist `null`, gleich was gelöscht wurde: Nach ihr
  steht nichts mehr, und der gelöschte Datensatz ist ihr `before`, gelesen
  unter der Sperre des Schreibvorgangs. Das gilt für jeden Schreibpfad ab dem
  Release, das Sprint 24 ausliefert (ADR-0017, Ergänzung vom 2026-11-04;
  #1378). Einträge von davor, geschrieben von Release 2026.11.8 und früheren,
  sind append-only und behalten eine von zwei älteren Formen: Die Löschung
  einer Zeile wiederholt den gelöschten Datensatz in `after`, und die Löschung
  einer Menge speichert die geleerte Menge — eine Freigabe manueller Kurse
  (`security_quotes`) `{"security_id": …, "quotes": []}`, eine aufgehobene
  Positionsausnahme (`position_bucket_override`) die Position ohne ihre
  `bucket_ids`, `{"id": null, "securities_account_id": …, "security_id": …}`.
  Einen gelöschten Datensatz liest man in jedem Fall aus `before`.

Jeder Schreibkontext mit Finanzdaten journalisiert: Die Einführung, die
ADR-0017 in Schritten geplant hat, ist abgeschlossen. Jede Tabelle mit
Finanzdatensätzen trägt einen Guard-Trigger, der einen Schreibvorgang ohne
Akteur ablehnt; ein Schreibpfad, der das Journal vergisst, scheitert also,
statt eine Lücke zu hinterlassen. Die Einträge stehen unter diesen
`resource_type`-Codes:

- Wertpapiere und ihre ISIN-Aliasse: `security`, `security_identifier_alias`;
  die Kurse, die jemand schreibt: `security_quotes`;
- Portfolios, Geldkonten und Depots: `portfolio`, `cash_account`,
  `securities_account`;
- Buchungen, auch die eines angewandten Imports (Akteur `import_session`):
  `transaction`;
- Klassifizierungen: `classification`, `category`,
  `security_category_assignment`;
- SOLL-Pläne: `target`, `target_plan`;
- Steuerdaten: `tax_parameters`, `tax_profile`, `allowance_order`,
  `tax_statement_snapshot`;
- das Research-Log und die Wertpapier-Termine: `security_note`,
  `security_event`;
- eigene Regeln: `policy_rule`, `policy_rule_version`;
- die Zusammenführungen des Lebenszyklus: `merge_record`,
  `retired_import_hash`;
- Buckets, Views und Depot-Snapshot-Marker: `bucket`, `view`,
  `depot_bucket_assignment`, `cash_account_bucket_assignment`,
  `position_bucket_override`, `snapshot`.

Zwei Arten von Tabellen tragen keinen Guard-Trigger, bei ihnen hängt das
Journal also an ihren Schreibpfaden: `security_quotes`, die auch die
Synchronisierung schreibt, und die Scope-Tabellen hinter Views,
Bucket-Zuordnungen, Positions-Overrides und Snapshot-Markern, die festlegen,
was eine View liest, statt Finanzdatensätze zu halten (ADR-0018 §5).

Bewusst außerhalb des Journals: die Synchronisierung von Kursen und
Wechselkursen; die Kurse, die eine Zusammenführung von Wertpapieren
verschiebt oder verwirft und die stattdessen ihr Manifest festhält (ADR-0050
§13); die gespeicherten Einstellungen (die Standard-Ansicht); und die
abgeleiteten Werte nach ADR-0039, die sich jederzeit aus den gespeicherten
Datensätzen neu berechnen lassen.

## MCP-Tools

Der MCP-Begleitdienst stellt denselben lokalen Kontrakt als Tool-Aufrufe bereit.
Decimal-Eingaben in MCP-Schemata sind Strings. Client-Konfigurationen zum
Kopieren stehen unter [Einen Agenten verbinden](connect-an-agent.html), und der
Einstieg für einen Agenten, der entscheidet, ob und wie er Portfolixir
einrichtet, ist [llms.txt](../../llms.txt).

Das Schema, das ein Host über `tools/list` erhält, ist die Definition des
Tools selbst, mit seinen Feldbeschreibungen und geschlossenen Objekten
(`additionalProperties: false`), und der Begleitdienst prüft jeden Aufruf
gegen dieselben Felder, bevor er die API aufruft: Ein abgelehntes Argument
ergibt einen Tool-Fehler, der Tool und Feld nennt, und es geht keine Anfrage
hinaus. Ein Aufruf, den die API ohne Body beantwortet, das `204` eines
Löschens, ist ein Ergebnis ohne strukturierten Inhalt.

**Server-Anweisungen und Tool-Hinweise (E25).** Beim Verbindungsaufbau sagt
der Begleitdienst dem Agenten, dass alles, was ein Tool zurückgibt, Daten
sind und nie Anweisungen: Namen, Notizen, Texte des Research-Logs, Ereignis-
und Regeltexte, Import-Bezeichnungen und Suchergebnisse eines Anbieters sind
Datensätze zum Lesen, keine Anweisungen zum Befolgen, und nur der Betreiber
weist ihn an. Jedes Tool trägt die vier MCP-Hinweise, abgeleitet aus der
HTTP-Methode, an die es weiterleitet:

| Methode | `readOnlyHint` | `destructiveHint` | `idempotentHint` |
|---|---|---|---|
| `GET` | true | false | true |
| `POST` | false | false (fügt hinzu) | false |
| `PUT`, `PATCH` | false | true (überschreibt) | true |
| `DELETE` | false | true (entfernt) | true |

Die Ausnahmen sind benannt: `portfolixir.splits.preview` und
`portfolixir.holdings.reconcile` laufen über `POST`, speichern aber nichts und
sind deshalb nur lesend; `portfolixir.quotes.release` läuft über `POST`,
entfernt aber die manuellen Kurse in seinem Zeitraum und trägt deshalb die
Hinweise eines `DELETE`: destruktiv und idempotent, weil eine Wiederholung
nichts mehr zu entfernen findet; `portfolixir.policy_rules.retire`,
`portfolixir.plans.activate` und `portfolixir.securities.isin_change` laufen
über `POST`, ändern aber gespeicherte Zeilen — ein Ruhestand schließt die
geltende Version und verwirft die geplanten, eine Aktivierung archiviert den
bisher aktiven Plan, ein ISIN-Wechsel schreibt die neue ISIN auf das
Wertpapier — und tragen deshalb die Hinweise eines `PUT`: destruktiv und
idempotent, weil eine Wiederholung nichts weiter ändert (ein zweiter Ruhestand
antwortet mit `409`, eine zweite Aktivierung ändert nichts, ein zweiter
ISIN-Wechsel ist ein benannter Konflikt); `portfolixir.policy_rules.add_version`
läuft über `POST` und fügt eine Version an, schließt aber die geltende Version
und ersetzt jede geplante ab ihrem Datum und ist deshalb destruktiv und nicht
idempotent, weil eine Wiederholung eine weitere Version anfügt;
`portfolixir.crashes.put` läuft mit einem Schlüssel über `PUT` (ein Name oder
die Felder eines manuellen Fensters werden überschrieben) und ohne über `POST`
(ein neues manuelles Fenster) und ist deshalb destruktiv und nicht idempotent,
weil eine Wiederholung ohne Schlüssel ein weiteres Fenster anfügt;
`openWorldHint` ist wahr für
`portfolixir.securities.search_online`, `portfolixir.quotes.sync` und
`portfolixir.exchange_rates.sync`, die einen externen Anbieter erreichen, und
für `portfolixir.securities.create`, das bei eingeschalteter Anreicherung der
Instanz einen Kursnachlauf beim Anbieter und eine Logo-Suche anstößt.
Die nur anfügenden Schreibvorgänge, `portfolixir.notes.append`, eine neue
Regel (`portfolixir.policy_rules.create`) und eine Prognose
(`portfolixir.predictions.create`), sind nicht destruktiv, und ihre
Beschreibungen sagen, dass das Angefügte dauerhaft ist.

**Ohne Rückfrage freigebbare Lesezugriffe.** Ein Host darf jedes Tool mit
`readOnlyHint: true` ohne Rückfrage ausführen: Keines davon verändert die
Instanz. `portfolixir.securities.search_online` gehört dazu, sendet seine
Anfrage aber an den konfigurierten Anbieter; lassen Sie es hinter einer
Rückfrage, wenn Ihnen das wichtig ist. Ein Host, der vor jedem anderen Tool
fragt, mindestens aber vor jedem mit `destructiveHint: true`, behält jeden
Schreibvorgang im Blick.

**Nur-Lese-Modus.** Mit `PORTFOLIXIR_MCP_READ_ONLY=true` läuft der
Begleitdienst nur lesend: `tools/list` listet dann nur die Tools mit
`readOnlyHint: true`, und ein Aufruf jedes anderen Tools, gelistet oder nicht,
wird als Tool-Fehler abgelehnt, der den Schalter nennt, bevor eine Anfrage
hinausgeht. Standardmäßig ist er aus, und jeder andere Wert als `true`,
`false`, `1`, `0` oder leer stoppt den Begleitdienst mit dem Namen der
Variable. Der Schalter schränkt den Begleitdienst ein, nicht das Token:
`PORTFOLIXIR_API_TOKEN` behält seine volle Befugnis über die API.

**Tool-Profile.** `PORTFOLIXIR_MCP_PROFILE` nimmt `read`, `book` oder `full`
(Standard), in beliebiger Schreibweise. `read` ist der Nur-Lese-Modus oben.
`full` listet und ruft jedes Tool außer den zwei des News-Labellers. Ein
viertes Profil, `label`, listet `portfolixir.news.unlabeled` und
`portfolixir.news.label_put` und sonst nichts, und kein anderes Profil
listet sie: Es ist für das Skript eines Labellers, das einen eigenen
Begleitdienst mit eigenem benannten Token betreibt (ADR-0056 §7), und jede
Seite lehnt die Tools der anderen beim Aufruf ab. `book` listet die
Lesezugriffe, jedes Anlegen
und die ersetzenden Schreibzugriffe und lässt die **Admin-Menge** weg, eine
ausdrückliche Liste im Begleitdienst (`mcp-server/src/profiles.ts`), gezogen
nach einer Linie, wie sie umgesetzt ist: entfernende Tools sind Admin,
ersetzende Schreibzugriffe bleiben in `book`. Jedes Entfernen ist Admin (jedes
Löschen, das Entfernen eines früheren Namens und eines ISIN-Alias, das
Aufheben einer Klassifikationszuordnung, das Löschen einer
Positions-Überschreibung, die Freigabe manueller Kurse), auch wo ein späteres
Schreiben eine gleiche Zeile zurückbringen könnte, ebenso die drei
Zusammenführungen, die ISIN-Änderung, eine neue Version einer Regel (sie
schließt die geltende Version und ersetzt die geplanten) und das Stilllegen
einer Regel. Ein
ersetzender Schreibzugriff (ein Ändern, ein Upsert, eine Bucket-Menge, das
Aktivieren eines Plans) bleibt in `book`, weil derselbe Schreibzugriff mit dem
früheren Wert ihn rückgängig macht; eine enger gesendete Bucket-Menge oder
eine auf `[]` gesetzte Positions-Überschreibung bleibt ebenfalls, das Löschen
der Überschreibung ist Admin. Drei behaltene Schreibzugriffe hinterlassen
einen Rest, den ihr Gegenstück nicht beseitigt: eine Rückbenennung stellt den
Namen wieder her, behält aber den Zwischennamen als früheren Namen, den kein
neues Konto annehmen darf und auf den ein späterer Import bucht, bis
`portfolixir.cash_accounts.remove_former_name` (oder der Depot-Zwilling), ein
Admin-Tool, ihn entfernt; ein Upsert über einem Datum mit Anbieterdaten
lässt dieses Datum manuell, was nur `portfolixir.quotes.release`, ein
Admin-Tool, zurückgibt; und `portfolixir.news.sources_put`, das eine Domain
von `blocked` zurückstuft, stellt ihre Stufe wieder her und stuft ihre
gespeicherten Einträge neu ein, aber die Einträge, die die Sperre entfernt
hat, kommen erst zurück, wenn ein Feed sie wieder listet (ADR-0056 E1:
gespeicherte Nachrichteneinträge sind ein Zwischenlager, das ein Abruf
wieder füllt, deshalb bleibt die Bewertung ein Ersetzen). Die
Schreibzugriffe, die `book` behält, stehen als
zweite Liste neben der Admin-Menge, jeder mit seinem Grund, und ein Test des
Begleitdienstes schlägt für jedes Tool mit `destructiveHint: true` fehl, das in
keiner der beiden steht. Unter `book` wird ein Aufruf eines Admin-Tools,
gelistet oder nicht, als Tool-Fehler abgelehnt, der das Profil und
`PORTFOLIXIR_MCP_PROFILE=book` nennt, bevor eine Anfrage hinausgeht, und die
Server-Anweisungen nennen das Profil in einem Satzteil.
`PORTFOLIXIR_MCP_READ_ONLY=true` ist `read`: allein oder neben
`PORTFOLIXIR_MCP_PROFILE=read` stimmt es überein, und neben
`PORTFOLIXIR_MCP_PROFILE=book` oder `full` stoppt es den Begleitdienst und nennt
beide Variablen; `PORTFOLIXIR_MCP_READ_ONLY=false`, der ausgelieferte Standard,
heißt nur, dass der Schalter aus ist, und widerspricht nie. Jeder andere Wert
stoppt den Begleitdienst mit dem Namen der Variable. Ein Profil schränkt den
Begleitdienst ein, nicht das API-Token. Es hält einen unbeaufsichtigten
Agentenlauf davon ab, über den Begleitdienst zu löschen oder zusammenzuführen;
ein Agent, der die API mit dem Token erreicht, kann weiterhin jede Route
aufrufen.

**Bereichs-Zwillinge.** Bewertung, Performance, Benchmark-Vergleich und
Beitragsanalyse gibt es in zwei Bereichen, und jedes Tool eines Paares nennt
das andere in seiner
Beschreibung mit dem Unterschied (Sprint 17, D-6): `portfolixir.portfolios.*`
gilt für einen Portfolio-Datensatz in seiner Basiswährung, sein `view` grenzt
innerhalb dieses Portfolios ein; `portfolixir.views.*` gilt für eine View über
jedes Portfolio, jedes Konto einmal gezählt, in EUR. Die Summe über jedes
Portfolio braucht keine View: `portfolixir.views.valuation` ohne id liest sie
(`GET /api/v1/valuation`, #1007), immer in EUR über jedes Konto — die Summe der
Übersicht, wenn das erste Portfolio die Basiswährung EUR hat und keine
Standard-Ansicht gesetzt ist —, also ist eine Summe von Portfolio-Bewertungen
nie der Weg dorthin. Auch die Tools für
View-Performance, View-Benchmark und View-Beitragsanalyse brauchen keine
View: Ohne id liest jedes jedes Konto in EUR (`GET /api/v1/performance`,
`/performance/benchmark`, `/performance/contribution`, #1056), also ist eine
Rendite oder ein Beitrag über alles eine Abfrage, nie eine Summe von
Portfolios — Renditen mehrerer Portfolios addieren sich nie. Die
Vermögensseite rechnet ihre Alles-Zahlen in der Basiswährung des ersten
Portfolios, sodass sie von diesen abweichen, wenn diese nicht EUR ist, wie
die `computation_basis` jeder Antwort sagt.

**Prompts.** Der Begleitdienst bietet drei MCP-Prompts (`prompts/list`,
`prompts/get`), unter jedem Profil dieselben, und jeder trägt den Rahmen ohne
Beratung in seinem eigenen Text: Das System bereitet Entscheidungen vor, der
Betreiber führt sie aus, und nichts platziert, schlägt vor oder bemisst einen
Trade.

- `first_setup` prüft die Instanz (`portfolixir.contract.get`) und nennt das
  aktive Profil, liest, was vorhanden ist, schlägt Cash-Konten, Depots, Buckets
  und Views vor (keine für die Summe über jedes Portfolio, die keine View
  braucht), erklärt, wie Daten hineinkommen, und schreibt nichts ohne die
  Bestätigung des Betreibers.
- `import_converter` (optionales Argument `export_file`) leitet den Agenten
  des Nutzers an, auf dem Rechner des Betreibers einen Konverter von einem
  Bank- oder Broker-Export zu schreiben und auszuführen, der eine
  Portfolio-Performance-CSV-v1-Datei, die der Betreiber auf der Import-Seite
  ablegt, erzeugt; die Seite zeigt sie in der Vorschau und übernimmt sie
  idempotent. Er nennt das Format genau: die Kopfzeile, `;`, Daten als
  `YYYY-MM-DD`, deutsche Zahlen, die deutschen Typ-Bezeichnungen, `Betrag` als
  Bargeldwirkung jeder Zeile, `Konto` und `Gegenkonto` je Typ, die Regel nur
  in EUR und die JSON-v1-Variante für andere Währungen und für ISINs, mit je
  einem synthetischen Beispiel, das ein Test durch die echte Import-Seite
  führt. Er nennt die Zeilen, die die Vorschau ablehnt: eine Umbuchung ohne
  beide Seiten, einen Kauf oder Verkauf ohne sein Verrechnungskonto, eine
  ISIN ohne gültige Prüfziffer und, in JSON
  v1, eine Währung außer denen, die der Wertpapier-Dialog anbietet. Er bindet
  den Agenten: kein Broker-Sync, kein Netzwerk- und kein Modellaufruf, nur
  synthetische Beispiele, und die umgewandelten Zeilen einzeln über
  `portfolixir.transactions.create` zu buchen, ist kein Ersatz, weil das die
  Vorschau und die Idempotenz über den Inhalts-Hash übergeht.
- `position_review` (optionales Argument `security_id`; ADR-0055 §5) führt
  den Agenten durch eine Position: das Dossier
  (`portfolixir.securities.dossier`), die offenen Thesen und ihre
  Invalidierungsbedingungen (`portfolixir.notes.list`), die anstehenden
  Termine (`portfolixir.events.list`) und die bereits festgehaltenen
  Prognosen (`portfolixir.predictions.list`); dann fragt er nach Prognosen
  (Richtung, eine Wahrscheinlichkeit von `"0.50"` bis `"0.99"`,
  `resolves_on` und eine Benchmark) oder nach keiner, wo der Agent keine
  Sicht hat, jede festgehalten mit `portfolixir.predictions.create` unter dem
  Modell des Agenten und, wo es einen gibt, der `note_id` der These. Sein Text
  sagt, dass eine Prognose dauerhaft ist und eine festgehaltene Einschätzung,
  nie ein Trade: keine Order und keine Größe. Passen zwei Katalogzeilen auf
  das Wertpapier, fragt er den Betreiber vor dem Festhalten, welche bleiben
  soll, denn eine Prognose bewahrt ihr Wertpapier und ihre Benchmark vor
  einer Zusammenführung; er prüft mit `portfolixir.quotes.list`, dass das
  Wertpapier und ein Benchmark-Wertpapier einen gespeicherten Schlusskurs in
  den letzten 7 Tagen haben, und nimmt sonst eine `rate:`-Benchmark. Unter
  dem Profil `read` hält er nichts fest und gibt dem Betreiber die Liste.

Die Prompts gibt es nur über MCP: Ein Prompt ist eine Anweisung an den
Agenten des Nutzers, und die API hat nichts, dem sie ihn liefern könnte.

**Unsichtbare Zeichen.** Jeder Schreibzugriff lehnt die Zeichen ab, die der
Betreiber nicht sehen kann (siehe „Text“ oben), aber eine Zeile von vor dieser
Regel kann sie noch tragen. Der Begleitdienst ist der Ort, an dem sie sichtbar
werden: Jeder String einer API-Antwort, ein Wert oder ein Schlüssel in jeder
Tiefe, erreicht den Agenten mit jedem solchen Zeichen als `[U+XXXX]`
(`[U+200B]` für ein Leerzeichen der Breite null) — dieselbe Schreibweise, die
die Oberfläche dem Betreiber für diese Zeile zeigt, und die
Server-Anweisungen sagen es. Die JSON-API selbst liefert gespeicherten Text,
wie er gespeichert ist. Ein Text, den der Agent zurückschreibt, trägt die
Kürzel als die sichtbaren Buchstaben, die sie sind.

**Ein Datensatz in einem Satz (#965).** Ein Satz, den die App schreibt,
benennt einen anderen Datensatz mit seiner Art und id, nie mit seinem
gespeicherten Namen, damit ein Name, der sich wie eine Anweisung liest, nie in
den eigenen Worten der App steht: Eine Ablehnung eines ISIN-Wechsels oder
Alias nennt `security #12`, eine Ablehnung wegen eines früheren Namens beim
Schreiben eines Geldkontos oder Depots nennt `cash account #5` oder
`securities account #5` (`errors.former_names`: „include the name of cash
account #5 in this portfolio“), und das Detail einer Prüfung beim
Zusammenführen von Wertpapieren nennt Regeln, Depots, Buckets und Portfolios
mit ihren ids (`policy rule(s): #7 (in_force)`, `In depot #3`,
`in portfolio #1`) und Namen und Kennungen einer Identität nach ihrer Art
(„its recorded name“, „its stored ISIN“), und
ein erneut gebuchter Split nennt das Portfolio des bestehenden Ereignisses mit
seiner id (`for portfolio #1`). Ein Löschen, das abgelehnt wird, weil eine Richtlinienregel das Objekt liest
(`409`), nennt die Regeln ebenso, und das Detail einer Prüfung beim
Zusammenführen von Geldkonten oder Depots nennt Buckets und eine Position mit
ihren ids (`the buckets #3, #7`, `security #12 sits in the bucket #9`). Der
Name ist ein Feld des Datensatzes, über seine id zu lesen (der eines Depots
über `GET /api/v1/securities_accounts/:id`, eines Buckets über
`GET /api/v1/buckets/:id`, einer Regel über `GET /api/v1/policy_rules/:id`,
eines Wertpapiers über `GET /api/v1/securities/:id`, eines Portfolios über
`GET /api/v1/portfolios`). Die `errors` einer Ablehnung tragen einen Namen
neben dem Detail nur an zwei Stellen: `errors.policy_rules[].name`, mit `id`
und `status` jeder Regel, und `errors.unresolvable[].ref.name`, den erfassten
Namen der Identität; ein Depot, ein Portfolio und ein Bucket stehen dort nur
mit ihren ids. Die Ablehnung einer Wertpapier-Zusammenführung trägt ISIN, WKN
und Ticker einer Identität ebenfalls als Daten neben dem Satz:
`errors.unresolvable[].ref`, `errors.source_isin` und `errors.isins`. Die Oberfläche von Portfolixir nennt ihn weiter beim Namen.

**Ein Schreibvorgang ohne Antwort.** Jeder API-Aufruf hat eine Frist von 30
Sekunden. Ein Lesezugriff, der sie verpasst — ein `GET` oder eines der über
`POST` laufenden Tools, die nichts ändern (`readOnlyHint: true`) —, ändert
nichts und ergibt `ApiReadTimeoutError`, darf also wiederholt werden; jeder
andere Aufruf, der sie verpasst, ergibt `ApiOutcomeUnknownError`: Der
Begleitdienst hat aufgehört zu warten, der Server kann den Schreibvorgang aber
trotzdem übernommen haben, also lesen Sie vor einer Wiederholung neu, was er
geändert hätte. Eine blinde Wiederholung eines Schreibvorgangs, der einen
Datensatz anfügt, kann ein Duplikat speichern, und jedes solche Tool (jeder
nicht idempotente Schreibvorgang) sagt das in seiner Beschreibung; die
Server-Anweisungen sagen es einmal für jeden Schreibvorgang.

**Ein Schreibvorgang, dessen Verbindung scheitert**, ohne dass sich zeigt,
dass die Anfrage nie abging (ein Reset, ein Socket, der sich schließt, während
die Antwort ankommt, ein TLS-Fehler, ein Fehler ohne Code), ergibt ebenso
`ApiOutcomeUnknownError`, mit dem Code des Fehlers in der Meldung: Die Anfrage
kann gesendet worden sein, und der Server kann sie übernommen haben. Ein
Fehler, der zeigt, dass die Anfrage die API nie erreicht hat (Verbindung
abgelehnt, Name nicht aufgelöst, Host oder Netz nicht erreichbar,
Adressfamilie nicht unterstützt oder keine lokale Adresse verfügbar,
Verbindungsaufbau selbst abgelaufen, eine Basis-URL, die sich nicht als URL
lesen lässt), bleibt ein gewöhnlicher Fehler und darf wiederholt werden,
ebenso jeder Fehler eines Lesezugriffs. Löst ein Name in mehrere Adressen auf,
gilt die Anfrage nur dann als nie gesendet, wenn der Verbindungsaufbau an
jeder von ihnen so gescheitert ist; sonst nennt die Meldung den Code jeder
Adresse.

**Ein Gateway-Fehler oder eine Antwort, die kein JSON ist.** Hinter einem
Reverse Proxy ergibt ein Schreibvorgang, der mit `502`, `504` oder Cloudflares
`520` oder `524` beantwortet wird, `ApiOutcomeUnknownError`: Die Meldung
sagt, dass das Gateway anstelle des Servers mit diesem Status geantwortet hat,
und der Server kann den Schreibvorgang trotzdem übernommen haben, also lesen
Sie vor einer Wiederholung neu, was er geändert hätte. Die Ausnahme ist ein
`502` in der eigenen JSON-Fehlerhülle der API, einem Body mit genau einem
Schlüssel, `errors`, der ein nicht leeres Objekt enthält: Die API antwortet so
mit `502`, wenn der Wechselkursanbieter bei `portfolixir.exchange_rates.sync`
scheitert, und nichts wird gespeichert; das ist also die Antwort des Servers,
am Schreibvorgang ist nichts unbekannt, und sie bleibt der gewöhnliche Fehler
`Portfolixir API request failed: 502 {…}` mit der Angabe der API. Ein leeres
`errors`-Objekt oder eines neben weiteren Schlüsseln stammt von einem Gateway.
Keinen der drei anderen Status liefert die API, sie stammen also von einem
Gateway, gleich welcher Body. Ein Lesezugriff, der mit einem der vier
beantwortet wird, ändert nichts; er bleibt ein gewöhnlicher Fehler, der den
Status nennt oder sagt, dass die Antwort keinen Body hatte, und sagt, dass eine
Wiederholung sicher ist. Ein `503` gilt nicht als unbekannter Ausgang: Ein
Proxy, der `503` liefert, hat die Anfrage meist nicht weitergeleitet, manche
Proxys (Envoy, Istio) antworten aber erst nach der Weiterleitung mit `503`,
also lesen Sie vor der Wiederholung eines Schreibvorgangs, der ein `503`
erhielt, neu. Eine Antwort, deren Body kein JSON ist (eine HTML-Fehlerseite,
das `413` eines Proxys), wird nie als Parse-Fehler weitergereicht: Ihr Fehler
nennt den Status und zitiert höchstens 120 Zeichen des Bodys, so gezählt, wie
die Meldung sie trägt, JSON-Escapes eingerechnet, der Leerraum von JSON
zusammengefasst und unsichtbare Zeichen sowie jedes andere Leerzeichen (ein
geschütztes Leerzeichen, ein Seitenvorschub) ausgeschrieben, mit der Länge des
Bodys in Bytes, wenn er gekürzt wurde. Das API-Token des Begleiters und jeder
`Bearer`-Wert lauten in diesem Zitat und in einem zitierten JSON-Fehler
`[redacted]`, damit eine Proxy-Seite, die die Header der Anfrage
zurückspiegelt, das Token nicht weitergeben kann. Ein Schreibvorgang, der mit
`2xx` und einem solchen Body beantwortet wird, ergibt ebenfalls
`ApiOutcomeUnknownError`: Die API kann ihn übernommen haben, und ihre Antwort
lässt sich nicht lesen.

- `portfolixir.contract.get` — der Kontraktversions-Read (ADR-0044 §8): was
  die Oberfläche bietet und wann sie sich zuletzt geändert hat, abfragbar mit
  `since=`.
- `portfolixir.version` — die Version, aus der diese Instanz gebaut wurde
  (FR-55): `GET /api/v1/version`, ohne Argument.
- `portfolixir.securities.list`
- `portfolixir.securities.get` — vollständiger Datensatz eines Wertpapiers
  einschließlich seiner `identifier_aliases` (aufgezeichnete frühere ISINs)
  und seines abgeleiteten `thesis_state` (ADR-0044), für eine Anleihe ihre
  Lesung `bond` mit der `computation_basis` jeder Kennzahl und dem
  Zwei-Skalen-Befund (ADR-0052); ein zusammengeführtes
  Wertpapier antwortet `404` mit `errors.merged_into`, und die Beschreibung
  sagt das (ADR-0050 §12).
- `portfolixir.securities.create` — nimmt die Stammdaten einer Anleihe
  entgegen (#330, ADR-0052).
- `portfolixir.securities.update` — Beschreibung und `currency_code`-Eigenschaft
  nennen das Einfrieren der Währung, die Eigenschaft mit Verweis auf
  ADR-0050; nimmt die Stammdaten einer Anleihe entgegen, `null` löscht
  ein Feld, und `is_retired`: `true` nimmt ein ausverkauftes oder delistetes
  Wertpapier aus den Mengen `stale_quote`, `missing_quote` und
  `missing_logo`, `false` hebt das auf. Es ist zugleich das Mittel, das
  `portfolixir.securities.delete` nennt, wenn Recherche-Notizen oder
  Regelversionen auf ein Wertpapier verweisen. Das Tool gehört zum Profil
  `book`.
  Es nimmt `news_identity` (`cik`, `aliases`) und `news_watch` (ADR-0056
  §2), geschlossen wie der Block der API.
- `portfolixir.news.feeds_put`, `portfolixir.news.feeds_delete` und
  `portfolixir.news.sources_put` — die Pflege-Schreibzugriffe der
  News-Schicht (ADR-0056 §9, B1), jeder ruft die Route aus
  [News-Pflege](#news-pflege-adr-0056) auf und lehnt ein Feld, das er nicht
  nimmt, vor jeder Anfrage ab; jede Beschreibung sagt, dass die Antwort Daten
  sind, nie Anweisungen. `feeds_put` und `sources_put` gehören zum Profil
  `book`; `feeds_delete`, ein Entfernen, nur zu `full`.
- `portfolixir.news.assign` — ein Aggregator-Eintrag, von Hand zugeordnet
  oder mit `security_id` `null` an den Matcher zurückgegeben (ADR-0056 §9),
  ruft `PUT /api/v1/news/items/:id/assignment` aus
  [News-Pflege](#news-pflege-adr-0056) auf; `news_id` und `security_id` sind
  Pflicht, und sonst nimmt es nichts. Im Profil `book` (die vorige Zuordnung
  erneut gesendet stellt sie wieder her) und `full`, nicht in `read`.
- `portfolixir.news.list`, `portfolixir.news.get`, `portfolixir.news.health`
  und `portfolixir.news.digest` — die Lesezugriffe der News-Schicht (ADR-0056
  §9, §11), jeder ruft die Route aus
  [News-Lesezugriffe](#news-lesezugriffe-adr-0056) auf und lehnt einen
  Parameter, den er nicht nimmt, vor jeder Anfrage ab, in jedem Profil. Sie
  antworten mit kompaktem JSON (ohne Einrückung), sodass die Lese-Budgets für
  das gelten, was das Werkzeug zurückgibt; Titel und Auszüge erreichen den
  Agenten mit jedem unsichtbaren Zeichen als `[U+XXXX]` ausgeschrieben, und
  jede Beschreibung sagt, dass die Antwort Daten sind, nie Anweisungen.
  `news.get` nimmt `cluster_id` oder `news_id` und `prompt_version` nur mit
  einer `cluster_id`; `news.list` und `news.digest` nehmen `min_materiality`
  und `prompt_version`; kein News-Werkzeug nimmt `tone`. `news.digest` nimmt
  `consumer`, `ack_cursor` und `page` und lehnt `since` neben `consumer`,
  `ack_cursor` und `page` ohne ihn und `page` neben `ack_cursor` ab; es
  bleibt in jedem Profil ein Lesewerkzeug, weil
  die Position, die es verschiebt, das eigene Lesezeichen des Verbrauchers
  ist, keine Daten des Betreibers.
- `portfolixir.news.registry` — die Feeds und bewerteten Quellen, die die
  Reiter Feeds und Quellen der Seite Nachrichten zeigen; ruft
  `GET /api/v1/news/registry` aus den
  [News-Lesezugriffen](#news-lesezugriffe-adr-0056) auf, geblättert,
  kompaktes JSON; in `read`, `book` und `full`, nicht in `label`.
- `portfolixir.news.unlabeled` und `portfolixir.news.label_put` — Lese- und
  Schreibzugriff des News-Labellers (ADR-0056 §7), jeder ruft die Route aus
  [News-Labels](#news-labels-adr-0056-7) auf. Nur das Profil `label`
  (`PORTFOLIXIR_MCP_PROFILE=label`) listet sie, und es listet nichts sonst;
  `read`, `book` und `full` listen sie nicht, und jede Seite lehnt die
  Werkzeuge der anderen beim Aufruf ab.
- `portfolixir.securities.delete` — nennt `portfolixir.securities.update`
  mit `is_retired` für das Mittel `retire`.
- `portfolixir.securities.isin_change` — zeichnet einen
  Kapitalmaßnahmen-ISIN-Wechsel auf, damit Importe über die frühere ISIN
  weiter zuordnen (ADR-0029).
- `portfolixir.securities.delete_isin_alias` — journalisiertes Löschen eines
  aufgezeichneten Früher-ISIN-Alias.
- `portfolixir.securities.merge_preview` — die Vorschau einer
  Wertpapier-Zusammenführung, ein Lesen (ADR-0050 §9, §10): die Positionen je
  Depot für beide Ausgänge der Frage nach den gleichen Buchungen, die Kurse
  mit den manuellen Kollisionen, Konfiguration und Termine, die Kennzeichen
  nach jeder Identitätswahl und der `plan_digest`.
- `portfolixir.securities.merge` — die Wertpapier-Zusammenführung unter einem
  freigegebenen Digest; als destruktiv und idempotent markiert (eine
  Wiederholung antwortet mit dem ursprünglichen Protokoll). Die Beschreibung
  sagt, dass `identity_choice` Pflicht ist, wenn beide eine ISIN tragen, und
  nie vorausgewählt, was jeder Wert tut, dass die Kurse die Lücken des Ziels
  füllen und bei einer Kollision der des Ziels gewinnt, dass Konfiguration
  und Termine wandern, und was die Zusammenführung für den nächsten Import
  bedeutet: Jede Identität der Quelle führt zum Ziel, ein späterer Import, der
  sie nennt, bucht dorthin, ein erneut angewendeter Export legt nichts an, und
  eine Zusammenführung, die eine Identität unaufgelöst ließe, wird abgelehnt.
- `portfolixir.securities.search_online`
- `portfolixir.events.list`, `portfolixir.events.create`,
  `portfolixir.events.update`, `portfolixir.events.delete` — der Kalender
  eines Wertpapiers und seine drei Schreibzugriffe (ADR-0048). Das `event`
  von `events.create` nimmt `news_id`, einen Nachrichten-Eintrag des
  Wertpapiers als Quelle: Der Begleiter lehnt `source_url` oder
  `source_quality` daneben ab, ebenso einen Termin ohne `news_id` und ohne
  `source_quality`, vor jeder Anfrage.
- `portfolixir.events.upcoming` — was in den nächsten N Tagen im **gesamten
  Katalog** ansteht; `held_only` grenzt ein und ist nie die Voreinstellung.
- `portfolixir.events.unconfirmed` — vergangene Termine, die niemand bestätigt
  hat.
- `portfolixir.events.stale` — Termine, die niemand seit N Tagen erneut
  geprüft hat.
- `portfolixir.securities.metrics` — die abgeleiteten Preiskennzahlen eines
  Wertpapiers (ADR-0047) über seine eigene splitbereinigte Kursreihe:
  gleitende Durchschnitte, Volatilität, maximaler Drawdown, Momentum und der
  Abstand zu den 52-Wochen-Extremen, jede mit Fenster und Beobachtungszahl.
- `portfolixir.securities.dossier` — das Positionsdossier eines Wertpapiers
  (FR-49): Datensatz, Bestände, Kennzahlen, neueste Research-Log-Einträge,
  anstehende und jüngste Termine, Kategorien, Positionsziele und seine
  Nachrichten der Woche in einem Lesezugriff, jeder Teil so, wie
  sein eigener Lesezugriff ihn antwortet, und mit dessen Namen. Es antwortet
  kompaktes JSON (ohne Einrückung), sodass das Budget des News-Blocks von
  etwa 50 Token für den Text gilt, den der Agent erhält.
- `portfolixir.notes.list` — das Research-Log eines Wertpapiers, neueste
  zuerst, mit dem abgeleiteten Thesenstand; die Beschreibung benennt, dass
  Einträge nie verschwinden (ADR-0044).
- `portfolixir.notes.append` — der einzige Schreibzugriff auf das Log; ein
  Widerruf mit `supersedes_id` zieht einen Befund zurück. Es nimmt
  `headline`, `event_type` und `tone` bei einem evidence- oder
  event_result-Eintrag, und `cluster_id`: eine Story, mit dem `body` des
  Agenten festgehalten, den Rest setzt der Server, wie
  [Research-Log](#research-log-adr-0044) sagt; der Begleiter lehnt
  `as_of`, `source_url` oder `source_quality` neben `cluster_id` ab, ebenso
  einen Eintrag ohne `cluster_id`, dem `kind`, `source_quality` oder `as_of`
  fehlt, vor jeder Anfrage. Eine Zusammenfassung, nie der Artikel, und eine
  Richtung zum Bewerten als Prognose mit `note_id`.
- `portfolixir.notes.unreviewed` — gehaltene Positionen ohne Eintrag seit N
  Tagen.
- `portfolixir.notes.uncorroborated` — Einträge, deren Quellenqualität nicht
  `primary` ist.
- `portfolixir.notes.expiring` — datierte Sperren, die in N Tagen ablaufen.
- `portfolixir.predictions.create` — hält eine Prognose fest (ADR-0055), ein
  Schreibvorgang in den Profilen `book` und `full`; seine Beschreibung sagt
  vor dem ersten Feld, dass sich eine Prognose nicht bearbeiten,
  zurückziehen oder löschen lässt, dass eine irrtümliche bleibt und zählt
  und dass eine Korrektur eine neue Prognose ist, und fordert den Agenten
  auf, sein Modell zu nennen, das das Schema verlangt; die
  Wahrscheinlichkeit ist ein String von `"0.50"` bis `"0.99"` (`"0.49"`
  wird vor jeder Anfrage abgelehnt: die Gegenrichtung mit `"0.51"`
  festhalten), eine `rate:`-Benchmark ist ein Bruch bis 1, und ein
  `made_at`, `author` oder `actor` wird vor jeder Anfrage abgelehnt. Sie
  sagt, dass der Startkurs der letzte an oder vor dem UTC-Tag der Abgabe
  ist, dass eine Prognose nach `resolves_on` offen bleibt, bis ihr Endkurs
  da ist (höchstens 7 Tage), und dass eine Prognose ihr Wertpapier und ihre
  Benchmark vor Zusammenführung und Löschung bewahrt.
- `portfolixir.predictions.list` — die Prognosen mit ihrem Status beim
  Lesen, gefiltert wie `GET /api/v1/predictions`, darunter die
  Fälligkeitsabfrage (`due_before`).
- `portfolixir.predictions.get` — eine Prognose mit ihrer Auflösung und den
  verwendeten Kursen.
- `portfolixir.predictions.calibration` — der Kalibrierungsbericht; die drei
  Lesezugriffe sind schreibgeschützt, in jedem Profil, und sagen kurz, dass
  eine Prognose dauerhaft ist.
- `portfolixir.quotes.sync`
- `portfolixir.quotes.list`
- `portfolixir.quotes.upsert` — jede Zeile wird als manuell gespeichert; das
  Schema bietet nur `source: manual`, und die Antwort nennt die ersetzten
  Daten.
- `portfolixir.quotes.manual` — die manuellen Kurse eines Wertpapiers über
  die ganze Historie: Anzahl, erstes und letztes Datum, die Abschnitte, die
  Anzahl eines Zeitraums und ob die Synchronisierung ein freigegebenes Datum
  wieder füllen kann; ein Lesen.
- `portfolixir.quotes.release` — die journalisierte Freigabe der manuellen
  Kurse eines Zeitraums an die Anbieterdaten; das Bedienelement des Operators
  ist **Freigeben…** im Tab „Kurse“ des Wertpapiers.
- `portfolixir.portfolios.list` — veraltet (ADR-0024): die Beschreibung
  verweist auf Buckets/Ansichten.
- `portfolixir.portfolios.create` — veraltet (ADR-0024): nur Kompatibilität;
  bevorzuge `portfolixir.buckets.create` / `portfolixir.views.create`.
- `portfolixir.cash_accounts.list`
- `portfolixir.cash_accounts.create`
- `portfolixir.cash_accounts.update` — Beschreibung und
  `currency_code`-Eigenschaft nennen das Einfrieren der Währung (ADR-0050 §11).
- `portfolixir.cash_accounts.delete`
- `portfolixir.cash_accounts.set_balance`
- `portfolixir.cash_accounts.remove_former_name` — entfernt einen früheren
  Namen (ADR-0050 §4); die Beschreibung sagt, was das kostet: Ein Import, der
  ihn noch nennt, legt dann ein neues Konto an.
- `portfolixir.cash_accounts.merge_preview` — die Vorschau einer
  Zusammenführung, ein Lesen (ADR-0050 §7, §10): beide Ausgänge der Frage
  nach den gleichen Buchungen und der `plan_digest`.
- `portfolixir.cash_accounts.merge` — die Zusammenführung unter einem
  freigegebenen Digest; als destruktiv und idempotent markiert (eine
  Wiederholung antwortet mit dem ursprünglichen Protokoll). Die Beschreibung
  sagt, was die Zusammenführung für den nächsten Import bedeutet: Die Namen
  der Quelle werden frühere Namen des Ziels, ein späterer Import, der sie
  nennt, bucht dorthin — außer einem Namen, den ein anderes Konto noch trägt;
  er wird nicht übernommen —, und ein erneut angewendeter Export legt nichts
  an.
- `portfolixir.securities_accounts.list`
- `portfolixir.securities_accounts.create`
- `portfolixir.securities_accounts.update`
- `portfolixir.securities_accounts.delete`
- `portfolixir.securities_accounts.remove_former_name` — dasselbe für ein
  Depot.
- `portfolixir.securities_accounts.merge_preview` — die Vorschau einer
  Depot-Zusammenführung, ein Lesen (ADR-0050 §7, §10): jede betroffene
  Position vorher und danach für beide Ausgänge der Frage nach den gleichen
  Buchungen, der Bucket-Plan, `positions_basis` und der `plan_digest`.
- `portfolixir.securities_accounts.merge` — die Depot-Zusammenführung unter
  einem freigegebenen Digest; als destruktiv und idempotent markiert (eine
  Wiederholung antwortet mit dem ursprünglichen Protokoll). Die Beschreibung
  sagt, dass Buchungen ihr Verrechnungskonto behalten, dass jede Position
  ihre Ansichts-Zugehörigkeit behält, und was die Zusammenführung für den
  nächsten Import bedeutet: Die Namen der Quelle werden frühere Namen des
  Ziels, ein späterer Import, der sie nennt, bucht dorthin — außer einem
  Namen, den ein anderes Depot noch trägt; er wird nicht übernommen —, und
  ein erneut angewendeter Export legt nichts an.
- `portfolixir.transactions.list`
- `portfolixir.transactions.create`
- `portfolixir.transactions.update`
- `portfolixir.transactions.delete` — eine Zeile; an einem Split nennt es
  `portfolixir.splits.delete`
- `portfolixir.splits.preview`
- `portfolixir.splits.create`
- `portfolixir.splits.delete` — den ganzen Split von einer beliebigen seiner
  Zeilen aus, die Zeile jedes Portfolios in einem journalisierten Schritt
  (#912); ein Admin-Werkzeug, das Profil `book` lässt es also weg
- `portfolixir.holdings.list`
- `portfolixir.cashflow.realized_gains` — das #724-Rollup mit erklärter
  FX-Basis und Ausschluss-und-Benennung bei Kurslücken, und der annualisierten
  Rendite je Trade (#984)
- `portfolixir.cashflow.external_flows` — das #725-Rollup mit erklärtem
  Unterschied zum investierten Kapital
- `portfolixir.cashflow.costs` — das #726-Rollup mit erklärter
  Nebenbeträge-statt-Brutto-Regel
- `portfolixir.sales.hindsight` — was jedem Verkauf entging (FR-50):
  `GET /api/v1/sales/hindsight` mit seinen Filtern und dem optionalen
  `benchmark`, nur lesend in jedem Profil; die Beschreibung sagt, dass es
  nichts bewertet und kein Urteil fällt. Sein `include` (`reinvestment`)
  fügt hinzu, was ein Umschichten kostete, und die Beschreibung sagt, was
  dieser Block ist: per Regel gefunden, vor Steuern, nur Kurs
- `portfolixir.holdings.by_security`
- `portfolixir.holdings.negative`
- `portfolixir.splits.incomplete` — die Prüfung unvollständiger Splits
  (#1292), rein lesend, mit ihrer Abhilfe
- `portfolixir.transactions.rate_only` — die gespeicherten Trades nur mit
  Kurs (#1290), rein lesend, mit ihrer Abhilfe
- `portfolixir.transactions.cash_mismatch` — die gespeicherten Trades, deren
  Betrag nicht zu ihren Zahlen passt (#1371), rein lesend, mit ihrer Abhilfe
- `portfolixir.holdings.reconcile` — rein lesender Vergleich einer
  eingefügten externen Positionsliste mit dem Ledger; die Tool-Beschreibung
  lenkt den Agenten darauf, die fehlende Transaktion der richtigen Art zu
  buchen statt Saldo-Snapshots oder unbepreiste Einlieferungen zu nutzen.
- `portfolixir.portfolios.valuation` — Bereichs-Zwilling von `portfolixir.views.valuation`
  (siehe „Bereichs-Zwillinge“ oben). Beide reichen `unvalued_cash_count`
  durch, mit und ohne `include_positions` (#1081).
- `portfolixir.exchange_rates.list`
- `portfolixir.exchange_rates.sync` — `scope=latest` (täglicher Feed) oder
  `scope=history` (das einmalige historische Backfill, Issue #737).
- `portfolixir.classifications.list`
- `portfolixir.classifications.create`
- `portfolixir.classifications.categories.create`
- `portfolixir.classifications.update`
- `portfolixir.classifications.delete` — ein Aufruf entfernt den Baum mit
  jeder Kategorie, jeder Zuordnung eines Wertpapiers darin, jedem Zielgewicht
  auf seinen Kategorien und jedem Zielplan dazu; die Beschreibung nennt jedes
  davon und dass das Audit-Journal jede dieser Zeilen als eigene Löschung
  vor der Klassifizierung festhält (E25). `dry_run: true` löscht nichts und
  antwortet `would_remove`, je Art die Anzahl und die ids, oder die Ablehnung
  der Löschung (Issue #894).
- `portfolixir.classifications.categories.update`
- `portfolixir.classifications.categories.delete` — ein Aufruf entfernt die
  Kategorie mit ihren Unterkategorien in jeder Tiefe, den Zuordnungen zu
  einer davon und den Zielgewichten auf einer davon; das Journal hält jede
  als eigene Löschung fest, die Kategorie selbst zuletzt. `dry_run: true`
  antwortet, was ginge, wie bei der Löschung der Klassifizierung.
- `portfolixir.classifications.assign`
- `portfolixir.classifications.assign_bulk`
- `portfolixir.classifications.unassign`
- `portfolixir.trades.list`
- `portfolixir.targets.list`
- `portfolixir.targets.set`
- `portfolixir.targets.delete`
- `portfolixir.targets.list_positions`
- `portfolixir.targets.delete_position`
- `portfolixir.portfolios.allocation`
- `portfolixir.portfolios.category_results` — ein Portfolio, das `view`
  eingrenzt, `view` allein für die View über jedes Portfolio (#901), oder
  keines von beiden für jedes Portfolio in EUR (#1091).
- `portfolixir.portfolios.risk`
- `portfolixir.policy_rules.list` — die gespeicherten Regeln mit der am
  `as_of` geltenden Version (ADR-0049); die Beschreibung weist den Agenten an,
  sie hier zu lesen, statt sie zu wiederholen, nennt jede eine gespeicherte
  Regel, wer sie auch geschrieben hat, und verweist für ihren Autor auf das
  Audit-Journal.
- `portfolixir.policy_rules.get` — eine Regel mit ihrer ganzen
  Versionsgeschichte.
- `portfolixir.policy_rules.create` — legt eine Regel mit ihrer ersten Version
  an; die Beschreibung enthält die Kennzahl-Tabelle und die Skalen und sagt,
  dass eine Version dauerhaft ist, sobald sie gilt: Die Regel lässt sich dann
  nur noch beenden.
- `portfolixir.policy_rules.add_version` — die Änderung: eine neue Version,
  nie ein Überschreiben, und dauerhaft, sobald sie gilt. Sie schließt die
  geltende Version am Vortag und ersetzt jede geplante ab ihrem Datum; deshalb
  ist sie als destruktiv markiert und gehört zu den Admin-Tools.
- `portfolixir.policy_rules.rename` — nur der Name; die Beschreibung sagt,
  dass Umbenennen keine Version anlegt und die Versionen unverändert bleiben.
- `portfolixir.policy_rules.retire` — beendet die geltende Version; alles
  bleibt lesbar.
- `portfolixir.policy_rules.delete` — nur für eine Regel, an der nie gemessen
  wurde.
- `portfolixir.portfolios.policy_findings` — wurde eine Linie überschritten?
  Die heute geltenden Regeln als Befunde; `status=breached` ist die
  Alarmliste, und die Beschreibung sagt, dass nicht bestimmbar nie bestanden
  ist.
- `portfolixir.portfolios.cash_target`
- `portfolixir.portfolios.set_cash_target`
- `portfolixir.portfolios.income`
- `portfolixir.portfolios.performance` — Bereichs-Zwilling von `portfolixir.views.performance`.
- `portfolixir.portfolios.benchmark` — Bereichs-Zwilling von `portfolixir.views.benchmark`.
- `portfolixir.portfolios.contribution` — Bereichs-Zwilling von `portfolixir.views.contribution`;
  welche Position wie viel zum Geldergebnis eines Zeitraums beigetragen hat
  (FR-41).
- `portfolixir.portfolios.bands` — Bereichs-Zwilling von `portfolixir.views.bands`;
  die Wertreihe in Bänder geteilt, nach Gesamt, Kategorie oder Wertpapier,
  für den gestapelten Chart (I23, FR-53); mit `scale: "ttwror"` die eigene
  TTWROR jedes Bandes als Linie (FR-57).
- `portfolixir.journal.list`
- `portfolixir.merges.list` — die Zusammenführungsprotokolle, das neueste
  zuerst, jedes mit dem, was wohin ging, wer es tat, wann, und dem
  zusammengefassten Manifest (ADR-0050 §12), die entfernten Buchungen auch je
  Grund; ein Lesen — die Liste des Operators ist **Zusammenführungen** auf
  „Konten & Depots“.
- `portfolixir.buckets.list`
- `portfolixir.buckets.get`
- `portfolixir.buckets.create`
- `portfolixir.buckets.update`
- `portfolixir.buckets.delete`
- `portfolixir.views.list`
- `portfolixir.views.get`
- `portfolixir.views.create`
- `portfolixir.views.update`
- `portfolixir.views.delete` — ein Aufruf entfernt die View mit ihren
  Bucket-Mengen, jedem auf sie bezogenen Zielplan und jedem in ihrem Bereich
  angelegten Depot-Snapshot; das Journal hält jede als eigene Löschung vor
  der View fest. `dry_run: true` antwortet, was ginge, wie bei der Löschung
  der Klassifizierung.
- `portfolixir.views.set_buckets`
- `portfolixir.views.valuation` — Bereichs-Zwilling von `portfolixir.portfolios.valuation`;
  ohne `id` die Summe aller Konten (#1007).
- `portfolixir.views.performance` — Bereichs-Zwilling von `portfolixir.portfolios.performance`.
- `portfolixir.views.benchmark` — Bereichs-Zwilling von `portfolixir.portfolios.benchmark`.
- `portfolixir.views.contribution` — Bereichs-Zwilling von `portfolixir.portfolios.contribution`.
- `portfolixir.views.bands` — Bereichs-Zwilling von `portfolixir.portfolios.bands`.
- `portfolixir.securities_accounts.set_buckets`
- `portfolixir.cash_accounts.set_buckets`
- `portfolixir.securities_accounts.set_position_buckets`
- `portfolixir.securities_accounts.clear_position_buckets`
- `portfolixir.settings.get_default_view`
- `portfolixir.settings.set_default_view`
- `portfolixir.plans.list`
- `portfolixir.plans.duplicate`
- `portfolixir.plans.activate`
- `portfolixir.plans.rename`
- `portfolixir.plans.delete`
- `portfolixir.snapshots.list`
- `portfolixir.snapshots.create`
- `portfolixir.snapshots.delete`
- `portfolixir.snapshots.comparison`
- `portfolixir.tax_parameters.list`
- `portfolixir.tax_parameters.upsert`
- `portfolixir.tax_profiles.list`
- `portfolixir.tax_profiles.create`
- `portfolixir.tax_profiles.update`
- `portfolixir.tax_profiles.delete`
- `portfolixir.allowance_orders.list`
- `portfolixir.allowance_orders.put`
- `portfolixir.allowance_orders.delete`
- `portfolixir.tax_snapshots.list`
- `portfolixir.tax_snapshots.get`
- `portfolixir.tax_snapshots.create`
- `portfolixir.tax_snapshots.update`
- `portfolixir.tax_snapshots.delete`
- `portfolixir.tax_snapshots.trim_budget`
- `portfolixir.news.feeds_put`
- `portfolixir.news.feeds_delete`
- `portfolixir.news.sources_put`
- `portfolixir.news.list`
- `portfolixir.news.get`
- `portfolixir.news.health`
- `portfolixir.news.digest`
- `portfolixir.news.assign`
- `portfolixir.news.registry`
- `portfolixir.news.unlabeled` (nur Profil `label`)
- `portfolixir.news.label_put` (nur Profil `label`)

`portfolixir.views.performance` berechnet die passende portfolioübergreifende
TTWROR/IRR für denselben Konten-Scope; Geld, das die View-Grenze überquert,
wird als externer Fluss behandelt (ADR-0019). Ohne `id` liest es die Rendite
jedes Kontos, in EUR (#1056).

`portfolixir.portfolios.benchmark` und `portfolixir.views.benchmark` sind
die Zwillinge der beiden Benchmark-Endpunkte (ADR-0046): `benchmark` ist
`rate:<decimal>` oder `security:<id>`, die Zeitraum-, View- und
Series-Parameter sind die der Performance-Tools, und die Antwort trägt
beide Vergleiche, das abgedeckte Fenster, die ausgeschlossenen Flüsse und
die Berechnungsbasis mit der benannten Reibungsfreiheits-Annahme. Das
View-Tool ohne `id` vergleicht jedes Konto, in EUR (#1056). Eine abgelehnte
Benchmark kommt als `422`-Body der API zurück, bei einem zusammengeführten
Wertpapier, dessen Überlebender eine Benchmark ist, mit `merged_into` (#959).

`portfolixir.portfolios.contribution` und `portfolixir.views.contribution`
sind die Zwillinge der beiden Beitragsendpunkte (FR-41, ADR-0051): die
Zeitraum- und View-Parameter sind die der Performance-Tools (ein `series`
gibt es nicht), und die Antwort trägt den Beitrag jeder Position, die drei
Restzeilen, die Summen — `positions` plus `remainder` ist `result`, das
Geldergebnis des Performance-Endpunkts — und die Berechnungsbasis mit ihren
benannten Annahmen. Beide sind Lesezugriffe, also listet jedes Profil sie.
Das View-Tool ohne `id` liest jedes Konto, in EUR (#1056).

`portfolixir.settings.get_default_view` /
`portfolixir.settings.set_default_view` lesen und setzen die
Standard-Ansicht-Voreinstellung (ADR-0024): eine `view_id` pinnt eine Ansicht,
`null` (oder weglassen) setzt auf die eingebaute Alles-Sicht zurück.

Die Tools `portfolixir.portfolios.valuation`,
`portfolixir.portfolios.allocation`, `portfolixir.portfolios.performance`,
`portfolixir.portfolios.contribution`, `portfolixir.portfolios.risk` und
`portfolixir.portfolios.category_results` akzeptieren ein optionales `view`
(eine View-id), das das Ergebnis auf die
Bestände der Bucket-View eingrenzt; die Antwort spiegelt dann die aktive View
wider. `portfolixir.portfolios.category_results` nimmt `view` auch ohne
`portfolio_id`: die View über jedes Portfolio, in EUR (#901); ohne beide
liest es jedes Portfolio, in EUR (#1091).

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

Seit ADR-0030 (#481) tragen dieselben Tools das SOLL auf **Positionsebene**:
Ein Eintrag von `portfolixir.targets.set`, der eine `security_id` hinzufügt,
setzt ein Gewicht auf diese einzelne Position unter ihrer Kategorie,
`portfolixir.targets.list_positions` liest die Positionszeilen und den
effektiven Roll-up jeder Kategorie (explizites Gewicht, Positionssumme,
effektives Steuergewicht und ein `conflict`-Flag, das eine Abweichung
zwischen explizitem Gewicht und Positionen sichtbar macht — dazu die Flags
`stale` je Zeile und `has_stale` je Kategorie für Zeilen, deren Wertpapier
nicht mehr unter der gespeicherten Kategorie steht), und
`portfolixir.targets.delete_position` entfernt ein Positionsziel. Aufrufe nur
mit Kategorien bleiben unverändert.

Seit ADR-0027 verwalten die Plan-Tools (`portfolixir.plans.list`,
`portfolixir.plans.duplicate`, `portfolixir.plans.activate`,
`portfolixir.plans.rename`, `portfolixir.plans.delete`) benannte
Plan-**Versionen**: den aktiven Plan in einen Entwurf duplizieren, den Entwurf
bearbeiten, indem seine id als `plan_id` an `portfolixir.targets.set`,
`portfolixir.targets.delete` und `portfolixir.targets.delete_position` geht
(Issue #1133; ohne sie schreiben sie den aktiven Plan der View, und ein
archivierter Plan wird abgelehnt), oder im SOLL-Editor, ihn mit demselben
`plan_id` über `portfolixir.targets.list` und
`portfolixir.targets.list_positions` zurücklesen (Issue #1185) und ihn dann
aktivieren. Die Snapshot-Tools (`portfolixir.snapshots.list`,
`portfolixir.snapshots.create`, `portfolixir.snapshots.delete`,
`portfolixir.snapshots.comparison`) frieren einen Depotstand als Marker ein
und lesen den kontrafaktischen Vergleich; jeder Finanzwert im Vergleich ist
ein Decimal-String, und die Antwort benennt ihre Basis (brutto, nur
Kursentwicklung).
