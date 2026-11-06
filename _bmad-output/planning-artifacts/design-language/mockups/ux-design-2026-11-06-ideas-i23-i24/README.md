# Idea boards: I23 (a stacked chart with levels) and I24 (what a market dip hit)

Drawn on 2026-11-06 while the two ideas were triaged, at the owner's
request ("mach noch visuelle mockups zu den ideen"), so the conversation
that works them out starts from a picture. They are **idea boards**, not a
sprint's planning boards: nothing is picked yet, and each idea's row in
`../../../ideas.md` carries its open questions.

| File | What it is |
|---|---|
| `01-stacked-chart.html` → `01-stacked-chart--light.png`, `--dark.png` | I23: today's Performance chart, then A (recommended: a level bar with Gesamt · Kategorien · Einzelwerte, the classification, and the sort), A after a click on a category, B (a third series "Anteil %", 100 % stacked) and C (a "Beitrag" series, flow-neutral, a diverging stack). |
| `02-dip-bars.html` → `02-dip-bars--light.png`, `--dark.png` | I24: A (recommended: horizontal bars per position over a stored shock window, sorted by fall, with the market's fall as a dashed line), A at the category level with one category open, B (a matrix of positions × windows to compare shocks) and C (indexed lines, rejected). |
| `build.js` | Generates the synthetic series and writes both boards. |
| `render.js` | Renders both boards to PNG at 1x, light and dark, reduced to 256 colours. |

## How these differ from the sprint boards

Neither surface exists yet, so nothing is captured from the review
instance. The charts are inline SVG drawn by `build.js` from a seeded
random walk; the chrome around them (sections, segmented controls, tokens)
uses the app's own classes and links the real `priv/static/app.css`. When
an idea is worked out, its planning board is drawn the usual way, from the
running app.

## Synthetic data only

Every security name is generic and every figure is invented. The shock
windows in I24 carry **public market dates** (the pandemic crash, the
outbreak of the war in Ukraine, the tariff shock of April 2025, the sell-off
of 5 and 6 November 2026); every move shown inside them is made up and is
not a historical return. No real portfolio, name or machine detail appears.

## Rebuilding

```bash
node build.js
node render.js
```

`render.js` needs the Playwright that `test/browser` installs; set
`PLAYWRIGHT_CHROMIUM_EXECUTABLE` on a machine with a Chromium of its own.
