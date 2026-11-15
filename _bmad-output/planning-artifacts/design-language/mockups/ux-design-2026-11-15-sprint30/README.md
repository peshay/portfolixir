# Sprint 30 planning boards

Drawn on 2026-11-15 by the Sprint 30 planning session, before any code, as
the sprint workflow's "UI changes are mocked first" asks. Each board says
on its first lines what is already decided (and by which record) and what
the board itself proposes, with the comment that flips each proposal. Every
"today" frame is the review instance's own markup; every "after" frame is
that markup edited by hand, the proposal's CSS in the frame's
`<style id="proposal">`, a new element outlined (`mock-new`).

| File | What it is |
|---|---|
| `01-axis-start.html` → `01-axis-start--light.png`, `--dark.png` | Idea I43 (`ideas.md`): where the Total chart's axis starts. ① today, the same window (1J, view Alles, „Wert (EUR)“) at „Gesamt“ (axis 76.033 to 88.892, the line filling 91 % of the height) and at „Kategorien“ (the stack from 0, steps of 20.000, its top edge moving 13 %), side by side (`frames/01a*`, `01b*`); ② A, the mark only: a double zigzag ≈ breaking the bottom grid line where the plot begins (`01c*`); ③ B, the switch only: „Achse: Ausschnitt · ab 0“ after „Ebene“ in the shared control bar, both states, „ab 0“ on the stack's axis (0 to the highest value plus 5 %, round steps; `01d*`, `01e*`); ④ C, recommended: B on Wealth's Gesamt plus A wherever an amount axis does not start at 0, both states, and a security's price chart with the mark only (`01f*` to `01h*`); ⑤ C at 390 px, labels above their controls under the bar's floor, the mark in the empty gutter (`01i*`, `01j*`); ⑥ C in the privacy mode, the percent axis with the mark and no switch (`01k*`). Recommended default „Ausschnitt“, remembered as `axis=zero`; flips „I43 nur Markierung“, „I43 nur Schalter“, „I43 Standard ab 0“. |
| `02-wealth-polish.html` → `02-wealth-polish--light.png`, `--dark.png` | „Polish: Wealth“ (#1366), before and after for each line whose fix changes the picture: ① the positions table at 1200 px, eight columns, the six rows with a note (rows 65, 99, 65, 65, 99, 64 px today; A, recommended: the note's first phrase never breaks and the note reaches 9rem left under its neighbour, the depot on one line, the name column's floor 12rem → 9.5rem, rows 49 px, the table 922 px in 922; B: the note behind an ⓘ, 932 px in 922; `02a*` to `02c*`); ② the stacked chart's gutter 56 → 88 viewBox units, 33 → 51 px at the 560 px chart beside its legend, the values outside the plot (`02d*`, `02e*`); ③ a cash band below 0 shallower than one step, one round step below zero labelled („−25.000“; `02f*`, `02g*`); ④ Allokation's TTWROR while a new window loads, the app's busy placeholder (`02h*`, `02i*`); ⑤ the crash windows table at 390 px (756 px in 358 on the page) as phone rows (`02j*`, `02k*`); ⑥ Risiko without a portfolio, the catalogue's crash lists under the empty line (`02l*`, `02m*`); ⑦ „Namen ohne Fenster“, one table per reason under its own sentence, fitting its 922 px wrapper (1,062 px before; `02n*`, `02o*`). The lines without a picture change are listed on the board's head. Flip: „Positionen B“. |
| `03-shipped-font.html` → `03-shipped-font--light.png`, `--dark.png` | #1221, the app ships Inter: the Overview's KPI strip at 1200 px in DejaVu Sans (what a device without Inter draws today), in the variable Inter (A, recommended) and in three static weights (B) (`03a*` to `03c*`); Wealth's positions table at 1200 px (`03d*`, `03e*`; in DejaVu Sans 940 px in 922, in Inter 922); Transaktionen at 390 px with the filter sheet open, drawn in the page's flow (`03f*`, `03g*`). The head states the measured woff2 sizes, the weights the CSS uses and the licence. Flip: „Schrift B“. |
| `capture.js` | Captures the fragments the boards start from (`captured/*.html`, `captured/measures.json`) from the review instance, GET requests and clicks that only open a disclosure or the filter sheet. |
| `build.js` | Writes `frames/*` and the three boards from the captured fragments; the charts that change their axis are re-drawn by the app's own rules (`security_chart.ex`, `stacked_chart.ex`). |
| `render.js` | Measures every frame (`frames/sizes.json`, `frames/probes.json`: heights, table widths, row heights, the stacked chart's gutter), rebuilds, renders each board at 1x in both themes and reduces the PNGs to 256 colours; writes `font-sizes.json`. |

## The review instance

The fragments were captured from a review instance on the synthetic review
seed (`priv/demo/finding_surfaces_seed.exs`), on a database of its own so
no development or test database was touched, offline:

```bash
DATABASE_NAME=portfolixir_board30 PORT=4013 mix ecto.create
DATABASE_NAME=portfolixir_board30 PORT=4013 mix ecto.migrate
DATABASE_NAME=portfolixir_board30 PORT=4013 PORTFOLIXIR_BACKGROUND_FETCH=off mix run priv/demo/finding_surfaces_seed.exs
DATABASE_NAME=portfolixir_board30 PORT=4013 PORTFOLIXIR_BACKGROUND_FETCH=off mix phx.server
BASE=http://localhost:4013 node capture.js
```

A frame for a 1200 px window is 980 px wide (the window less the 220 px
menu), with the section's padding pinned to the 28 px it has at 1200 px.
The positions frames keep all 38 rows in the markup and collapse the 32
without a note (`visibility: collapse`), so the columns keep the widths
the page gives them.

## Synthetic data only

Every name and figure is the seed's, except where a frame says it was drawn
by hand: on board 02, two detected crash windows („Herbstdelle“ and an
unnamed one), the crash benchmark line, three names without a window, and
a cash band of −11.865 on two days, all invented. No real portfolio, name
or machine detail appears.

## Inter is not in the repository

Board 03's Inter frames load the face from `frames/inter/`, which does not
exist here. `render.js` serves it there from the npm packages
`@fontsource-variable/inter@5.3.0` and `@fontsource/inter@5.3.0` (SIL Open
Font License 1.1), unpacked into `INTER_DIR` (by default a directory under
the system's temporary directory; fetched with `npm pack` when missing).
Opened directly in a browser, those frames fall back to an installed Inter,
or to the next font of `--font-sans`.

## Rebuilding

```bash
node capture.js                  # optional, a review instance on 4013
node build.js && node render.js  # all three boards
```

The render script needs the Playwright that `test/browser` installs; set
`PLAYWRIGHT_CHROMIUM_EXECUTABLE` on a machine with a Chromium of its own.
