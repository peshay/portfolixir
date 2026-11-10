# Idea board: I12, the Bitcoin four-year cycle chart

Drawn on 2026-11-10 at the owner's request ("kannst du auf der basis schon
ein mock chart bauen?"), after the owner explained the idea the same day,
so the conversation that works it out starts from a picture. It is an
**idea board**, not a sprint's planning board; the idea's row in
`../../../ideas.md` carries its open questions.

| File | What it is |
|---|---|
| `01-cycle-chart.html` → `01-cycle-chart--light.png`, `--dark.png` | A (recommended): a "Zyklen" toggle on the security chart, shown only for a security with at least two halving events, with two modes: "Zeitachse" (halvings as vertical lines, the next one dashed as an estimate, tops and lows with date and close, an analog band for the next low and the next top) and "Ausgerichtet" (the cycles laid over each other from their halving, indexed to the halving-day close). Below it, the table of intervals with n per row. A's shortcut: a "Bitcoin-Zyklus" card on the dashboard that opens the chart with the toggle on. B (alternative): a "Zyklen" page in the navigation, worth it only once more than one security has halvings. Beside it, a shortened sketch of what `get_security_cycles` returns to an agent. |
| `02-connections-and-zoom.html` → `02-connections-and-zoom--light.png`, `--dark.png` | Drawn later the same day, after the owner adopted A and the band ("Ja find ich gut") and asked for lines between the tops and lows and a range in which the bands are large. Connections (recommended): three switches in the cycle bar, "Top ↔ Tief" on by default, "Top – Top" and "Tief – Tief" off; each segment carries its days and change; none runs past the last confirmed point. The same chart with all three on, to show the clutter. The zoom (recommended): a range "Zyklus" beside 1M to Max, only with cycles on, from three months before the last halving to four months after the top band; the axis reaches into the future, which no range does today, and the top band inherits the halving estimate's uncertainty. |
| `03-lines-into-bands.html` → `03-lines-into-bands--light.png`, `--dark.png` | Drawn after the owner asked that the lines continue and run into the bands. Recommended: each switched-on line continues from its last confirmed point as a **cone** into the band of its own relation (top → low, low → low, top → top), never as one line, because a band has no single target point. The table beside it lists every band with its basis and n, and shows that the two low bands exclude each other (top → low against low → low); low → top waits for a confirmed low. |
| `board.css` | The shared `mock-*` rules of the 2026-11-06 idea boards, then this board's `cy-*` rules. |
| `build.js` | Generates the synthetic series, computes the cycle figures the way the app would, and writes the three boards. |
| `render.js` | Renders the boards to PNG at 1x, light and dark, reduced to 256 colours. |

## What drawing it found

The obvious rule for a cycle's top, "the highest close between two
halvings", picks the wrong top for 2020–2024: the rally of March 2024
closed above the November 2021 top inside the same window, a month before
the next halving. The board therefore takes a window's top and low as the
peak and the trough of its **maximum drawdown**, and states that rule in
its basis line. The rule the app adopts belongs in the ADR that builds it.

## The band rule was corrected

The first draw took the price side of every band as the minimum to the
maximum of the past cycles. The owner noticed on board 03 that the two low
bands lay far apart. The cause was the rule, not the synthetic data:
every price factor has shrunk from cycle to cycle, so the next value fell
outside the old range each time. The price side now runs from the last
cycle's factor to that factor shrunk once more at its last rate, on the
logarithm; the time side keeps the minimum to the maximum. All three
boards are redrawn with it, and board 03 lists both rules side by side.

## One band per event

Two relations predict the same low (top → low and low → low), and two the
same top (halving → top and top → top). They share their data, so the
owner adopted on 2026-11-10 one combined band per event: the hull of its
parts in time and price, with the overlap of their price ranges shaded as
"both ways agree", and no average or intersection. With the line switches
on, the combined band is drawn as an outline and the cones show its parts.

## Synthetic data only

The price line is a seeded random walk bent through **public, rounded
anchor points**: the halving dates and the cycle tops and lows up to
October 2025. Everything after 2025-10-06 is **invented**, drawn dashed,
and so is the estimated date of the 2028 halving. Every figure on the
board is computed from that series. No portfolio figure, name or machine
detail appears.

## Rebuilding

```bash
node build.js
node render.js
```

`render.js` needs the Playwright that `test/browser` installs; set
`PLAYWRIGHT_CHROMIUM_EXECUTABLE` on a machine with a Chromium of its own.
