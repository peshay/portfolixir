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
| `04-tops-flops.html` → `04-tops-flops--light.png`, `--dark.png` | Idea I32 (FR-59, ADR-0061 in progress): „Tops und Flops“ per calendar window for the Overview's scope, two rankings, Kursrendite (each held security's EUR price return from stored closes) and Beitrag (each position's money contribution, ADR-0051, sold positions marked „verkauft“). ① today, the Overview at 1200 px (`frames/04a*`); ② A, recommended: the card directly under the KPI strip, before „Abgeschlossene Trades“, the period chips (Tag · Woche · Monat · Quartal · YTD · 1J) as one group of the shared control bar, five highest over five lowest in each column, the contribution table's bar under each Beitrag, a count of what has no answer under each list, YTD on the seed's own figures (`04b*`), and the card with its ⓘ open (`04c*`); ③ at 390 px, A1 stacked (recommended) and A2 with a switch „Liste: Kursrendite · Beitrag“ in both states (`04e*` to `04g*`); ④ the privacy mode: percentages stay, every amount is the app's `pf-mask` bar, order and bars stay as the contribution table keeps them (`04d*`); ⑤ states: „Tag“ on Sunday 15.11.2026 with each row's two dates under its name, six securities (three over three; seven positions four over three; corrected in the closing act to the card as built, its link without `view=` and the sentence naming Wealth's other view, board 06 ④), a view without holdings (`04h*` to `04j*`); ⑥ B, not recommended: the same rankings under „Beitrag je Position“ on Vermögen › Performance (`04k*`). Flips „Tops/Flops auf Vermögen“, „Tops/Flops umschaltbar am Handy“, „Tops/Flops nur Kursrendite“, „Tops/Flops nur Beitrag“. |
| `05-crash-select-width.html` → `05-crash-select-width--light.png`, `--dark.png` | Drawn in the closing act after CI, by `render-05.js`, not from captured fragments: the Crashes bar's window select (Vermögen › Risiko) before and after its fixed 20.5rem cap gives way to the room it is given. ① 1200 px in Inter, one line, „Synthetic dip · … · manuell“ cut at 328 px today, whole in 355 px after (`frames/05a*`, `05b*`); ② 1100 px, the label column, the select at its longest option instead of 328 px (`05c*`, `05d*`); ③ DejaVu Sans at 1200 px, unchanged (`05e*`, `05f*`). Rendered in Playwright 1.65.0's headless shell (Chromium revision 1254), CI's browser; `frames/05-probes.json` holds what it measured. Flip: „Crashes-Auswahl in der Labelspalte bis 20,5rem“. |
| `06-closing-act.html` → `06-closing-act--light.png`, `--dark.png` | Drawn in the closing act, by `render-06.js`, before the design critic's fixes that change a screen (the sprint workflow: a closing-act fix gets its frame first): ① finding 1, Wealth's Total at „ab 0“ on a window with an overdraft, the line on its own axis (0 to 10.000) today and on the stack's (−2.500 to 10.000) after, the stack's top edge dashed over it, the stack at „Kategorien“ under it (`frames/06a*`, `06b*`); ② finding 2, the Crashes list's „ggü. ‹benchmark›“ head in one line today and wrapping after, with a long benchmark name (`06c*`, `06d*`); ③ finding 5, the Crashes basis line for every list and reference, today's copy and the shortened one, each with its word count, and the ⓘ's new line (`06e*`, `06f*`); ④ a correction of board 04's frame 04i: the movers card's link with `view=` as drawn, and as built, without it and with the sentence naming Wealth's other view (`06g*`, `06h*`, written by `build.js`); ⑤ the UAT persona's finding 2, the area under the line at „ab 0“ closing at the axis' floor after ① and standing on 0 after its fix (`06b*` beside `06i*`). `frames/06-probes.json` holds what it measured. |
| `render-06.js` | Writes board 06 and its frames 06a to 06f and 06i from `captured/06-*.html`, serves this repository on a loopback port as `render-05.js` does, measures each frame (`frames/06-probes.json`) and renders the board in both themes. Run `node build.js` first (frames 06g and 06h); `PLAYWRIGHT_CHROMIUM_EXECUTABLE` and `NODE_PATH` as for `render-05.js`. |
| `capture.js` | Captures the fragments the boards start from (`captured/*.html`, `captured/measures.json`) from the review instance, GET requests and clicks that only open a disclosure or the filter sheet. |
| `capture-d.js` | Board 04's fragments (`captured/d-*.html`, `captured/d-measures.json`): the Overview at 1200 and 390 px and in the privacy mode, Vermögen › Performance at YTD with the contribution table, every row of that table (one click opens „Alle N anzeigen“), and the names Positionen lists. GET requests only, besides that click. |
| `build.js` | Writes `frames/*` and the four boards from the captured fragments; the charts that change their axis are re-drawn by the app's own rules (`security_chart.ex`, `stacked_chart.ex`). |
| `render-05.js` | Writes board 05 and its frames, serves this repository on a loopback port so the frames load the app's own Inter from `/fonts/`, measures each frame's select (`frames/05-probes.json`) and renders the board in both themes. Run it with `PLAYWRIGHT_CHROMIUM_EXECUTABLE` naming the Chromium to draw in and `NODE_PATH` naming `test/browser/node_modules`. |
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
BASE=http://localhost:4013 node capture-d.js
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
a cash band of −11.865 on two days, all invented. On board 04, ② to ④ and ⑥ are the seed's own: the Kursrendite from the stored closes of the twelve securities with a close on 31.12.2025 and one after it, the Beitrag the contribution table's YTD rows; ⑤'s day and month figures are invented and the frames say „Zahlen erfunden“. No real portfolio, name
or machine detail appears.

Board 06's fragments (`captured/06-*.html`) are not the review
instance's: LiveViewTest rendered them in German from two test worlds,
`wealth_axis_start_live_test.exs`'s world with its overdraft (Alpha and
Beta Synthetic, the tree „Strategy“, the cash 1.000 below 0 on two days)
and `test/browser/crash_section_layout_test.exs`'s world with its crash
benchmark named „Synthetic All-World Crash Index UCITS ETF USD Acc“.
`06-gesamt-ab-0-neu.html` is the line as finding 1's fix draws it,
rendered from a scratch build of the fix; `06-gesamt-ab-0-uat.html` is the
same line after the UAT persona's finding 2, rendered from its fix on the
same day. ③'s „+3,4 %“ and „19.11.2026“
are invented; the frames of ④ are 04i's, its figures invented.

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
node capture-d.js                # optional, board 04's fragments
node build.js && node render.js  # boards 01 to 04 (or: node render.js 04-tops-flops)
node render-06.js                # board 06, after build.js
```

The render script needs the Playwright that `test/browser` installs; set
`PLAYWRIGHT_CHROMIUM_EXECUTABLE` on a machine with a Chromium of its own.
