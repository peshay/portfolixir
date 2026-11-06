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

Silence adopts B; a review comment "I22 A" or "I22 C" changes it.

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
