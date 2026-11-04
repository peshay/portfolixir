# Sprint 24 board, Lane P: P1's two layout lines on Wealth, before and after

The board commit of Sprint 24's P1 (plan Lane P, D-8), drawn on
2026-11-05 before P1's code. It draws the two lines of #1366 (Polish:
Wealth) that change the picture:

- **line 2**, „Beitrag je Position“ under the performance chart scrolls
  sideways on a phone held upright, though its few columns would fit;
- **line 3**, #1322: Wealth's holdings table scrolls sideways at 1200 px on
  the review seed; long names and a 12-digit quantity push G&V off the
  scroller.

Line 1 (the sunburst returns to „Allokiert“ on a tap on the centre,
outside the chart or on the selected slice again, and on Escape) changes
behaviour and leaves the picture identical, so it has no frame (the sprint
workflow's exception; plan D-8).

| File | What it is |
|---|---|
| `01-wealth-tables.html` → `01-wealth-tables--1200.png` | The desktop board, rendered at 1200 px: the holdings table at 1200 px with the sidebar open, before, after and after in dark; the contribution table at 1024 px with the sidebar open (before, after, after in dark), at a 600 px phone (before, after) and at 1200 px (unchanged). |
| `01-wealth-tables-390.html` → `01-wealth-tables--390.png` | The phone board, rendered at 390 px: both tables are rows already, and stay so. |
| `build.js` | Captures the frames from the running review instance and measures each. Copied from `../ux-design-2026-11-04-sprint24/build.js` (Sprint 23's tooling); its header, the proposal CSS, a frame's own width per viewport and the probe differ. |
| `frames.js` | The frames: URL, viewport, the column pick, the rows kept, the story's class. |
| `board.js` | Lays out the boards; the measured figures in its text come from `frames/sizes.json`. |
| `render.js` | Renders both boards to PNG. |
| `frames/` | One static page per frame and width; each links the real `priv/static/app.css`. |

**Synthetic data only.** Every row is the synthetic review seed's
(`priv/demo/finding_surfaces_seed.exs`); nothing is invented. The seed
carries both things #1322 names: long security names („Microsoft
Corporation Registered Shares DL-,00000625“) and a quantity with twelve
decimals („0,333333333333“, Birchwood Global Savings Fund in the Sparplan
Depot). No real portfolio, name or machine detail appears.

## The picks

**Nothing is picked here.** Both lines are conformance repairs to
anatomies already signed (plan D-8):

- line 3 takes the accounts table's floor and break (#1145, DESIGN.md →
  `bucket-cell.card`, pick N15 = A of `ux-design-2026-10-09/05-accounts`);
- line 2 takes the phone rows the contribution table already has under
  560 px (DESIGN.md, Amendment 2026-10-03, „Under 560 px“), keyed on the
  block's own width, as #1145 keyed the accounts card.

Judgment calls inside them, each flippable by a review comment:

1. **The holdings name floor is 12 rem, not the accounts table's 13.5
   rem.** The floor is what #1322's eight columns leave of the 922 px
   scroller on the seed; 13.5 rem made the table 942 px.
2. **A holdings cell's note wraps between words** („Handelspreis ·
   03.02.2025“, „ohne Wechselkurs · nicht in der Summe“). On one line they
   made Letzter Kurs 196 px and Marktwert 246 px wide, more than the name's
   whole saving. Elsewhere `.cell-note` stays on one line.
3. **The quantity keeps every digit** (the plan's words), so #1322's
   alternative, a bound on the quantity's displayed digits, is not taken.
4. **Rows, not a narrower table, for line 2.** The table is already the
   reading table (the name at least 14ch and wrapping, six figures that
   never wrap); what is left to give is the figures.

## Measured (the frames' probes and the live page)

On the review instance in German, Playwright's Chromium, the sidebar open
(220 px) where the viewport is 880 px or wider.

**Line 3, #1322's eight columns** (Depot, Wertpapier, Stückzahl, Ø Kosten,
Letzter Kurs, Marktwert, G&V, G&V %; the picker without ISIN, WKN and
Währung), at 1200 px: the scroller is 922 px. On the live page with all
38 rows the table was 1,317 px; on the board's six rows 1,257 px, G&V out
of view. After: 922 px, G&V and G&V % in view. With all eleven columns the
table stays wider than the scroller (1,182 px on the seed) and keeps UX-DR15's
scroller; the three default columns fit before and after.

**Line 2, „Beitrag je Position“**: the German table needs 814 px of
columns on the seed (the English one 753 px), the same in every period and
with every row shown („Alle 41 anzeigen“); with the wrapper's 2 px border
the block needs 816 px. Measured by narrowing the window in 10 px steps
from 1200 to 540 px and reading the block's width, the wrapper's
`clientWidth` and its `scrollWidth`: the table scrolled sideways from a
1,090 px window down to 900 px with the sidebar open, and from 856 px down
to 561 px, where the sidebar leaves the layout. The bound is
`@container contribution (width < 820px)`: 816 px rounded up. At 1024 px
the block is 751 px live (757 px in the frame, which has no scrollbar
beside it); at a 600 px phone 568 px.

## Strings

None. Both lines change layout only; every string on a frame is the
page's own.

## The story's CSS (the frames' `<style id="proposal">`)

```css
#performance-contribution { container: contribution / inline-size; }
@container contribution (width < 820px) {
  #contribution-table-wrap { display: none; }
  #contribution-phone-rows { display: block; }
}
.data-table-wrapper > #holdings-positions-table { min-width: 0; width: 100%; }
#holdings-positions-table th.cell-name { min-width: 12rem; }
#holdings-positions-table td.cell-name { overflow-wrap: anywhere; }
#holdings-positions-table th.num,
#holdings-positions-table td.num { white-space: nowrap; }
#holdings-positions-table td .cell-note { white-space: normal; }
```

`#contribution-table-wrap` leaves the phone lists' 560 px block; the
Security column's head and cells carry `cell-name` (written into the
"Nachher" frames' markup).

## How to regenerate

Run a review instance on port 4011 with the synthetic review seed, from
the repository root:

```bash
DATABASE_NAME=portfolixir_review_p1 PORT=4011 mix ecto.create
DATABASE_NAME=portfolixir_review_p1 PORT=4011 mix ecto.migrate
DATABASE_NAME=portfolixir_review_p1 PORT=4011 PORTFOLIXIR_BACKGROUND_FETCH=off mix run priv/demo/finding_surfaces_seed.exs
DATABASE_NAME=portfolixir_review_p1 PORT=4011 PORTFOLIXIR_BACKGROUND_FETCH=off mix phx.server
```

Then, from this folder (`PLAYWRIGHT_CHROMIUM_EXECUTABLE` names a Chromium
of your own, if Playwright's is not installed):

```bash
node build.js    # captures every frame, writes frames/ and both boards
node render.js   # renders 01-wealth-tables--1200.png and 01-wealth-tables--390.png
```

The build sends GET requests only. The column pick is written to the
browser's own storage before the load, where the picker's ColumnPrefs hook
restores it. `ONLY=<regex>` recaptures the matching frames and keeps the
rest of `frames/sizes.json`.

**Cut for the board:** the holdings table keeps the six rows with the
longest names, the twelve-digit quantity and both cell notes; the
contribution table its first five positions. The rest is one elided line.

## Not shown

- Line 1, the sunburst's return (no rendered difference).
- The rail collapsed (72 px): the container query decides by the block's
  width, so it needs no frame of its own.
