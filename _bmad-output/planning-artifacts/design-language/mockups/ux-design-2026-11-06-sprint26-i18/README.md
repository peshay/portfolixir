# Sprint 26 planning board 03: what a sale missed (I18, FR-50)

Drawn on 2026-11-06, before any code. The board draws the human view of
I18 modes 1 and 2, which today exist only as `GET /api/v1/sales/hindsight`
and the MCP tool `portfolixir.sales.hindsight` (Sprint 25 plan D-3), and
of mode 3, the comparison with the purchase the proceeds went into, which
the same sprint builds under ADR-0057 (drawn from the plan's description
while the ADR is being written).

| File | What it is |
|---|---|
| `03-sale-hindsight.html` → `03-sale-hindsight--1200.png` | The desktop board, rendered at 1200 px: the pick bar and legend; options A, B and C on Cashflow → Trades; C's ⓘ open, C without a comparison and with a fixed rate; C in dark; C on a security's Trades tab; mode 3; what the story builds and does not. |
| `03-sale-hindsight-390.html` → `03-sale-hindsight--390.png` | The phone board, rendered at 390 px: C light and dark, and mode 3. |
| `build.js` | Captures the frames from the running review instance, writes the proposal into the live DOM and writes `frames/` and both boards. The rows, the synthetic figures and the new German strings (`NEW`) live here. |
| `proposal.css` | What the story adds to `priv/static/app.css`; every frame carries it in `<style id="proposal">`. The rules marked "Option B only" are not built unless B is picked. |
| `board.js` | Lays out both boards from `frames/sizes.json`. |
| `render.js` | Renders both boards to PNG and reduces them to 256 colours. |
| `frames/` | One static page per frame; each links the real `priv/static/app.css`. |

## The frames

Desktop (a 1280 px window with the sidebar open, so a 1060 px frame):

- **`a`** — option A: four columns „1M · 3M · 12M · Bis heute“ after
  „Ergebnis“ on every trade row of „Alle Trades“, the chooser above the
  table. The table becomes 1,400 px in a 1,007 px scroller; „3M“ onward is
  off to the right.
- **`b`** — option B: a toggle „Nach dem Verkauf“ in each trade's name cell;
  the row under Wrenfield Gardens AG open, its four spans with all three
  figures (Wertpapier, Benchmark, Differenz).
- **`c`** — option C, recommended: a section „Nach dem Verkauf“ under the
  trades list, one row per sale booking (all ten of the seed), compared
  with the flagged security Kestrel Industrial Group NV Index. Pins: ① the
  chooser, ② a span that has not ended („läuft“, „bis 27.12.2026“), ③ a
  span without a figure and its reason („kein Startkurs“), ④ the ⓘ.
- **`c-info`** — C with its ⓘ open: the computation basis in German.
- **`c-none`** — C with „Ohne“: each span is the security's own price
  return.
- **`c-rate`** — C with „Fester Zins“ at 3,00 % p. a.: the rate field and
  „Anwenden“ beside the chooser.
- **`c-dark`** — `c` in the dark theme.
- **`security`** — C on the security page, Trades tab (Wrenfield Gardens
  AG): the same section under „Abgeschlossene Trades (FIFO)“, filtered to
  the security, without the security column.
- **`m3`** — mode 3, C's fourth choice „Anschlusskauf“: per span the
  difference „gewechselt − behalten“ in EUR with both values under it;
  „Angelegt“ (the part of the proceeds the buys took, and its share); under
  each matched sale ⑤ the buys with their dates and the days after the sale
  (one pro rata) and the cost line (fees inside the difference, the sale's
  taxes apart and not inside it, the buys' income named, not added); ⑥ a
  sale with no follow-on purchase, with the rule as its reason.

Phone (390 px):

- **`c-390`** — C under the trades list: the chooser spans the row, each
  sale is a row with its four spans as a 2 × 2 grid (label, lead figure,
  sub-line), so the phone shows every figure the table row has.
- **`c-390-dark`** — the same in the dark theme.
- **`m3-390`** — mode 3 on the phone: the grid, then the buys and the cost
  line; a sale with no follow-on purchase says so in the grid's place.

**Legend:** dashed accent outline (`mock-new`) = new UI; amber left stripe
(`mock-synth`) = a synthetic figure, invented for the board; magenta pins
tie a frame to its note on the board.

## The pick

- **A, a column group on „Alle Trades“:** four columns of differences on
  each trade row. Closest to where closed trades are read today, but the
  table already fills its scroller, only one of the three figures fits per
  span, and the rows are FIFO round trips, not sales.
- **B, a row that opens under a trade:** all three figures per span, the
  table as wide as today; but one sale at a time, the same trade-versus-sale
  mismatch, and a toggle in a table that has none.
- **C, a section of its own, one row per sale (recommended):** the read
  answers one row per *sale booking*; „Alle Trades“ lists closed FIFO round
  trips. On the seed, three of the ten sales have no trade row (Harborline
  Freight Inc and Arbolia Inc. are excluded from the totals, Saltmarsh
  Logistics SE matched no buy), and a sale that closes two lots would
  repeat its figures in A and B. C lists every sale, leaves the trades
  table as it is, and shows every figure without a click. The security's
  Trades tab carries the same section, filtered to it.

**Silence adopts the recommendation (C).** A review comment naming A or B
changes it.

**Mode 3's place:** the fourth choice of C's chooser, „Anschlusskauf“,
beside „Fester Zins“ and „Wertpapier“, not a block of its own: it compares
the same rows over the same four spans with one more thing, and a second
block would repeat every sale.

## What the story builds

- „Nach dem Verkauf“ on Cashflow → Trades (`/cashflow?tab=realized`),
  under the trades list and before „Realisiert je Periode“; the same
  section on a security's Trades tab (`/securities/:id?tab=trades`),
  filtered with `security_id`, heading an h3 with the section ⓘ.
- The chooser: „Vergleich: Ohne · Fester Zins · Wertpapier · Anschlusskauf“
  in the shipped segmented control, as query state; „Wertpapier“ offers the
  securities flagged `is_benchmark` (ADR-0046, unchanged), or the shipped
  hint when there is none; „Fester Zins“ the rate and „Anwenden“.
- The table: Wertpapier; Verkauf (date over quantity × booked price in its
  currency); Startkurs (the close in EUR, its date where it is not the sale
  day, and the close in its own currency where that is not EUR); the four
  spans as a column group whose head names the lead figure. A span cell is
  the lead figure (the difference, or the security's own return without a
  comparison) over „Wertpapier ggü. Benchmark“; a span that has not ended
  is „läuft“ over its end date; a span the read cannot measure is the muted
  dash with its reason in words and the long reason as the cell's title,
  the security's own figure kept where only the benchmark is missing.
  Signed and coloured as every return, `.num`, tabular figures; the table
  fits its wrapper (#1322's anatomy) and keeps the scroller for the rest.
- The ⓘ with the computation basis (idea I1: the method clauses there, the
  gross/net line under the table); mode 3 adds its three clauses.
- Mode 3 as drawn in `m3`, from the ADR-0057 read.
- Under 560 px the phone rows with the 2 × 2 span grid.
- The anatomy goes into `DESIGN.md` with the story (sprint workflow).

## What it does not build

- No change to the trades table, its figures or its notes; no column on a
  trade row (A), no toggle (B).
- No verdict anywhere: no „zu früh verkauft“, no „richtig“, no colour on a
  row, no ranking, no sum of what all sales missed (no advice).
- No second benchmark and no benchmark beyond `is_benchmark` (the plan's
  flip „I18 any security“ stays a flip); no distributions after the sale
  (price only; the basis says so); no latent tax of the kept side; no link
  between a sale and a buy chosen or stored by hand.

## New German strings (proposals)

Existing strings come from `priv/gettext/de/LC_MESSAGES/default.po`
(„Wertpapier“, „Benchmark“, „Fester Zins % p. a.“, „Anwenden“, „kein
Wechselkurs“, „Zu diesem Abschnitt“, „Noch keine Benchmark-Wertpapiere —
eines auf der Seite Wertpapiere markieren.“). New:

| English source (proposed msgid) | German |
|---|---|
| After the sale | Nach dem Verkauf |
| Price move per sale in EUR · from the sale day · one row per sale booking | Kursentwicklung je Verkauf in EUR · ab dem Verkaufstag · eine Zeile je Verkaufsbuchung |
| Comparison | Vergleich |
| None | Ohne |
| Fixed rate | Fester Zins |
| Security | Wertpapier (the chooser's option; the msgid exists) |
| Follow-on purchase | Anschlusskauf |
| Sale | Verkauf |
| Start close | Startkurs |
| Invested | Angelegt |
| 1M · 3M · 12M · To date | 1M · 3M · 12M · Bis heute |
| latest close | letzter Kurs |
| The security's price move | Kursentwicklung des Wertpapiers |
| Difference to %{name} | Differenz zu %{name} |
| Difference to %{rate} % p.a. | Differenz zu %{rate} % p. a. |
| Difference switched − kept, in EUR | Differenz gewechselt − behalten, in EUR |
| vs. | ggü. |
| running | läuft |
| until %{date} | bis %{date} |
| Close %{date} | Schluss %{date} |
| no start close | kein Startkurs |
| no end close | kein Endkurs |
| no benchmark close | kein Benchmark-Kurs |
| No close on the sale day and none in the 7 days before | Kein Schlusskurs am Verkaufstag und keiner in den 7 Tagen davor |
| No close at the span's end and none in the 7 days before | Kein Schlusskurs am Ende der Spanne und keiner in den 7 Tagen davor |
| No stored rate to EUR for one of the two closes | Kein gespeicherter Wechselkurs nach EUR für einen der beiden Kurse |
| The benchmark security has no close for the start or the end; the security's figure stays | Das Benchmark-Wertpapier hat keinen Kurs für den Start oder das Ende; die Zahl des Wertpapiers bleibt |
| kept / switched | behalten / gewechselt |
| %{share} of the proceeds | %{share} des Erlöses |
| No follow-on purchases found: no buy from the sale's cash account within 30 days of the sale day | Keine Anschlusskäufe gefunden: kein Kauf vom Verrechnungskonto des Verkaufs binnen 30 Tagen ab dem Verkaufstag |
| Proceeds invested in | Erlös angelegt in |
| bought %{date} | gekauft %{date} |
| %{count} day(s) after the sale | %{count} Tag / Tage nach dem Verkauf |
| pro rata %{part} of %{amount} EUR | anteilig %{part} von %{amount} EUR |
| Fees, inside the difference | Gebühren, in der Differenz |
| Sale / Buy / Buys | Verkauf / Kauf / Käufe |
| The sale's taxes, not inside the difference | Steuern des Verkaufs, nicht in der Differenz |
| The buys' income, not added | Erträge der Käufe, nicht addiert |
| none | keine |
| Per span the difference to %{name}, below it security vs. benchmark | Je Spanne die Differenz zu %{name}, darunter Wertpapier ggü. Benchmark |
| Per span the sold security's price return | Je Spanne die Kursrendite des verkauften Wertpapiers |
| Per span the difference to %{rate} % p.a., below it security vs. rate | Je Spanne die Differenz zu %{rate} % p. a., darunter Wertpapier ggü. Zins |
| Per span switched − kept in EUR, both before tax | Je Spanne gewechselt − behalten in EUR, beide vor Steuern |
| Price return: distributions after the sale not included | Kursrendite: Ausschüttungen nach dem Verkauf nicht enthalten |
| Difference (option B only) | Differenz |

The ⓘ text, six clauses for modes 1 and 2 and three more for mode 3, is
`NEW.info` and `NEW.infoSwitch` in `build.js`; the story takes it from
there into the catalogue.

## Synthetic data only

The rows are the synthetic review seed's ten sale bookings as the read
answers them on the review instance: security, sale date, quantity,
booked price and currency, and the span dates, which decide „läuft“
(today is 06.11.2026). The seed stores no closes around its sales, so the
read answers every span „incomplete, no_start_close“ there; every figure
on the board (start closes, returns, benchmark returns, mode 3's values,
buys, fees, taxes and income) is invented for the board and marked with
the amber stripe. Harborline Freight Inc and Tamarisk Mining Ltd keep the
read's own answer („kein Startkurs“) and carry no stripe. The figures were
read with the context function in a read-only `mix run`, not over the
API: the review instance runs without an API token. No real portfolio,
name or machine detail appears.

## Rebuilding

Run a review instance on port 4011 with the synthetic review seed, from
the repository root (the database of board 01, `portfolixir_review_i22`,
serves as well):

```bash
DATABASE_NAME=portfolixir_review_i18 PORT=4011 mix ecto.create
DATABASE_NAME=portfolixir_review_i18 PORT=4011 mix ecto.migrate
DATABASE_NAME=portfolixir_review_i18 PORT=4011 PORTFOLIXIR_BACKGROUND_FETCH=off mix run priv/demo/finding_surfaces_seed.exs
DATABASE_NAME=portfolixir_review_i18 PORT=4011 PORTFOLIXIR_BACKGROUND_FETCH=off mix phx.server
```

Then, from this folder (`PLAYWRIGHT_CHROMIUM_EXECUTABLE` names a Chromium
of your own, if Playwright's is not installed):

```bash
node build.js    # captures every frame, writes frames/ and both boards
node render.js   # renders 03-sale-hindsight--1200.png and 03-sale-hindsight--390.png
```

The build sends GET requests only; the theme is written to the browser's
own storage before the load. `ONLY=<regex>` recaptures the matching frames
and keeps the rest of `frames/sizes.json`; `node board.js` alone rebuilds
both boards from it.
