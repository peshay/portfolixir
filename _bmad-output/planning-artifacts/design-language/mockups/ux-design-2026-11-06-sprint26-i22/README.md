# Sprint 26 planning board 01: the privacy mode (idea I22)

Drawn on 2026-11-06, before any code, because the owner asked to see the
look of a hidden figure first ("sonst baust du was Hässliches in meine
hübsche UI"). The board shows three looks for a hidden figure beside
today's screen, on Wealth (Bestände) and on the Overview, each in the light
and the dark theme.

| File | What it is |
|---|---|
| `01-privacy-mode.html` → `01-privacy-mode--board.png` | The board, rendered at 1x: the pick bar, the rule table, then Wealth and the Overview, each as today, A, B and C, light beside dark. |
| `build.js` | Captures the frames from the running review instance, applies each proposal to the live DOM and writes `frames/` and the board. |
| `board.js` | Lays out the board from `frames/sizes.json`. |
| `render.js` | Renders the board to PNG; with `DETAIL_DIR` set, also each variant's pair at 2x into that folder (kept out of the repository for size). |
| `frames/` | One static page per page, look and theme; each links the real `priv/static/app.css` and carries its proposal in `<style id="proposal">`. |

**Synthetic data only.** Every row is the synthetic review seed's
(`priv/demo/finding_surfaces_seed.exs`). The data notes and the data
quality block are cut from the frames; their amounts would be hidden the
same way. No real portfolio, name or machine detail appears.

## The rule every look shares

- **Every figure in a currency and every quantity** (values, cash, cost,
  prices, gains in euro, net flows, quantities) is replaced by **one
  constant placeholder of a fixed width** (4.4 em, so it grows with the
  font size only). The real figure is not in the page, so it can neither be
  recovered from the blur nor guessed from its length: 88.307,02 and
  19.178,75 look the same.
- **What stays:** percentages (returns, share of a depot or a view,
  allocation, drift), dates, day counts, counts of positions, ratios such
  as the wealth multiplier. A figure keeps its colour (green, red); the
  percentages beside it show the sign anyway.
- **The switch** (dashed on the board) sits in the top bar beside the
  appearance menu, holds per browser, survives a reload and is never
  stored on the server.
- **Charts with a euro axis** switch to a percent axis and lose amounts in
  their tooltips; they get their own frame once the look is picked.

## The pick

- **A, Weichzeichner:** the placeholder blurred, nothing else. Closest to
  "a figure you cannot read". The blur has a floor of 3.5 px, because at
  table size a lighter blur left the placeholder's digits almost legible,
  which would show a reader a figure that is not there.
- **B, Milchglas (recommended):** the blurred placeholder in a faint
  capsule tinted by the figure's colour. It reads as "hidden on purpose",
  never as a rendering fault, in both themes.
- **C, Nebelbalken:** no digits, a soft bar in the figure's colour. The
  calmest, but in tables it reads like a loading state.

**Picked: C**, by the owner on 2026-11-06, against the recommendation B.
Its one known weakness, that a bar in a table can read as a loading state,
is answered by the switch in the top bar, which shows the mode is on; the
build keeps C's shape as drawn here. The board's text still names B as
recommended, as it stood when the owner chose.

## Rebuilding

Run a review instance on port 4011 with the synthetic review seed, from
the repository root:

```bash
DATABASE_NAME=portfolixir_review_i22 PORT=4011 mix ecto.create
DATABASE_NAME=portfolixir_review_i22 PORT=4011 mix ecto.migrate
DATABASE_NAME=portfolixir_review_i22 PORT=4011 PORTFOLIXIR_BACKGROUND_FETCH=off mix run priv/demo/finding_surfaces_seed.exs
DATABASE_NAME=portfolixir_review_i22 PORT=4011 PORTFOLIXIR_BACKGROUND_FETCH=off mix phx.server
```

Then, from this folder:

```bash
node build.js
node render.js
```

The build sends GET requests only. The theme and Wealth's column pick are
written to the browser's own storage before the load.

## Board 02: the charts in privacy mode

Drawn on 2026-11-06 after the owner picked C: what the charts do while
the mode is on, in look C. Board 01's files are untouched; board 02 has
its own scripts and frames (`frames/chart-*.html`,
`frames/sizes-charts.json`).

| File | What it is |
|---|---|
| `02-privacy-charts.html` → `02-privacy-charts--1200.png` | The board, rendered at 1200 px: the rule table, then each chart off (today) above on; Wealth's "Wert" also in the dark theme. |
| `build-charts.js` | Captures the chart frames from the review instance, switches the mode on in the live DOM (board 01's rule and look C, plus each chart's change), writes `frames/chart-*.html` and the board. Holds the proposed strings. |
| `board-charts.js` | Lays out board 02 from `frames/sizes-charts.json`. |
| `render-charts.js` | Renders board 02 to PNG. |

### The rule for charts

- **An axis in a currency switches to percent, indexed to the window's
  start**, and **no tooltip names an amount**; an amount that stays in a
  tooltip's line becomes the look C bar. Percentages, dates and the
  line's shape stay.
- **Wealth → Performance, "% (TTWROR)"** (the default): the axis is
  already percent and stays; the tooltip "+9,0% · 88.307,02 EUR" keeps
  its shape with the amount as fog, and so does the badge above.
- **Wealth → Performance, "Wert (EUR)"**: the series is renamed "Wert
  (%)", its axis shows the value in percent of the value on the window's
  first day, a line under the chart says deposits and withdrawals count
  in it (so it is no return), and the tooltip reads "+9,0% · Wert +12,3%"
  (TTWROR first, as today). Judgement, flippable: "I22 Wert aus" hides
  the series while the mode is on and shows TTWROR only.
- **A security's chart** (the Diagramm tab, and the small curve on the
  Übersicht tab): its own "Prozent" view, pressed and locked ("Im
  Privatsphäre-Modus immer an"), which already locks the log scale;
  moving averages and the cost line are re-based with it. The pane head's
  last price and SMA 50 are prices and become fog. A trade's tooltip line
  ("Kauf 30 zu 42,10 EUR") hides quantity and price.
- **Cashflow → Erträge** (years, months, accumulated): no axis to switch;
  the bars keep their heights (ratios, like the percentages the mode
  keeps), every amount in and under them becomes fog, a zero included,
  and a bar's native tooltip keeps its year and series without the
  amount. Judgement, flippable: "I22 Balken in Prozent" labels each bar
  with its share of the window instead.
- **Charts already in percent** (Snapshots' comparison, Risk,
  Allocation) keep their axes; their amounts follow board 01.
- **Built on the server**, like board 01's placeholder: the amount never
  reaches the page, so a percent axis is the server's (SecurityChart's
  `percent_mode?`, or the same re-basing for Wealth), never a relabelling
  in the browser.

### How the "on" frames were made

- **The security chart** is the shipped component's own percent view,
  switched on in the live page with its "Prozent" toggle: no redraw.
- **Wealth's "Wert"** has no percent view on Wealth, so its five axis
  labels are relabelled in the page from the chart's own points, and the
  board labels that frame a redraw. It is exact: `percent_mode?`
  re-bases each value affinely, (v − v₀) / v₀, and pads the range by 5 %
  of its span, so line, fill and gridlines stay where the server drew
  them; the values come from the points' tooltip labels and the map from
  their positions (least squares).
- **Tooltips** are the live hook's, shown by resting the pointer over the
  chart; their text is then changed as the rule says. On the security
  chart the tooltip snaps to the close of 17.04.2026, three days before
  the seed's buy, so the trade's line is described, not shown.

### Strings (board 02)

Existing: "% (TTWROR)", "Wert (%{currency})" (the series as shipped),
"Prozent", "Logarithmische Skala", and board 01's switch ("Beträge
verbergen").

| English | German |
|---|---|
| Value (%) | Wert (%) |
| In privacy mode the axis shows the value in percent of the value at the window’s start, deposits and withdrawals included; the return is TTWROR. | Im Privatsphäre-Modus zeigt die Achse den Wert in Prozent des Werts am Fensterbeginn, Ein- und Auszahlungen eingeschlossen; die Rendite zeigt TTWROR. |
| Value %{percent} (tooltip) | Wert %{percent} |
| Always on in privacy mode (title of the locked "Percent") | Im Privatsphäre-Modus immer an |

### Rebuilding board 02

With the review instance running (above), from this folder:

```bash
node build-charts.js    # captures frames/chart-*.html, writes 02-privacy-charts.html
node render-charts.js   # renders 02-privacy-charts--1200.png
```

The build sends GET requests; its clicks change only what a page shows
(Wealth's series, the security chart's "Prozent", a year on Cashflow),
and the pointer rests over a chart for its tooltip. Nothing is submitted.
