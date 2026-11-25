# Planning boards: Sprint 32, the widget pass after the owner's feedback

Drawn on 2026-11-25 after the owner's feedback on Sprint 31's first slice
of I56 (boards 06 and 07 the same day, after the owner's questions on the
first five) („Im letzten großen Sprint hast du das ja hingeklatscht, aber das
sieht scheiße aus. Total unübersichtlich.“). The owner asked for five
things, each drawn here with its recommendation; the ideas are I57 to I61
in `../../../ideas.md`, the decisions ADR-0062's amendment of 2026-11-25 and
the Sprint 32 plan (`sprint-plan-2026-11-25-sprint32.md`).

| File | What it is |
|---|---|
| `01-resize.html` → `01-resize--light.png`, `--dark.png` | Resize and move in the edit mode. Today an overlap is refused and the message stands at the top of the page, far from the click (①). A (recommended): what is in the way moves down, then everything floats up until no gap is left; B: it moves down and gaps stay (②). The feedback stands at the widget, with „Rückgängig“ (③). „Gesamtwert“ in S, a new W and a redrawn M, with the rule that each size shows more of the same, never something else (④). |
| `02-starter-dashboards.html` → `02-starter-dashboards--light.png`, `--dark.png` | Wealth's tabs become starter dashboards that look like the tabs: each section a widget in the new size „Zeile“ (full width, as tall as its content), stacked in today's order (①); which section goes where, and which tabs come in the next widget pass (②); a „Zeile“ widget in the edit mode (③). Starter dashboards A (recommended): stored once on the update, then the operator's; B: shown until first changed. |
| `03-templates.html` → `03-templates--light.png`, `--dark.png` | „Neues Dashboard“ opens a gallery: „Leer“, the starter dashboards, then themes (Performance, Krypto Lover, Rücksetzer, Einkommen & Steuer), each card with its grid in miniature and its widgets (①); the dialog after the click, with a name and, where the template needs one, a view the dashboard stores as its own scope (②). The owner's question: may a shipped template be called „Buy The Dip“. |
| `04-periods.html` → `04-periods--light.png`, `--dark.png` | The period: a quick choice of up to six (the operator's ★) and one button that opens a menu in four groups, rolling, calendar, year and the operator's own saved periods (①, ②); the same menu pins a widget's period, with the table of how each kind answers a calendar period (③); for contrast, every choice as a chip (④, not recommended). |
| `05-new-widgets.html` → `05-new-widgets--light.png`, `--dark.png` | A preview for the next widget pass: the monthly-return heatmap and the trading activity, both ladder level (a) with their basis; both are new figures and get their own decision (ADR-0063) on that pass's planning PR. „Abstand zum Hoch“, which needs no new figure, comes in Sprint 32 for the two theme templates. |
| `06-real-app.html` → `06-real-app--light.png`, `--dark.png`, with `06-*.png` | Drawn after the owner asked to see Wealth and Allocation as dashboards: the running app on the synthetic review seed, its pages rearranged in the browser as board 02 proposes (the starter „Bestände“ as delivered, after a minute of editing, in the edit mode, and „Allokation & Ziele“), and three forms of the Kennzahlen widget: today, A (the owner's pick: the total with its split, Ergebnis, TTWROR and IRR on one line, the value bridge), B (one row of five). |
| `07-widget-look.html` → `07-widget-look--light.png`, `--dark.png`, with `07-heute-1.png`, `07-heute-2.png` | Drawn after the owner asked to check the look of every widget: all eleven kinds in all 21 sizes photographed in the running app (the two contact sheets), ten findings (the tenth after the owner's question on Tops und Flops' bars), the widget anatomy derived from A with its bar rule, and six widgets redrawn by it. |
| `08-alle-widgets.html` → `08-alle-widgets--light.png`, `--dark.png`, with `08-galerie/` | Every kind in every grid size, light and dark, as the running app draws it today on the review seed (42 single images, `<kind>-<size>-<light|dark>.png`), each with its stored and drawn size and a verdict; the docs' gallery is rebuilt by L4's script after Lane L. |
| `09-groessen-nach-apple.html` → `09-groessen-nach-apple--light.png`, `--dark.png`, with `09-*.png` | Today's sizes against Apple's widget families (small, medium, large, extra large), and the template „Überblick“ and the themes „Krypto Lover“ and „Rücksetzer“ (approximated with today's kinds) as they render today and on Apple's fixed tiles, simulated in the browser. |
| `10-abstand.html` → `10-abstand--light.png`, `--dark.png`, with `10-*.png` | Drawn after the owner disliked the space between widgets: the template „Überblick“ on Apple's tiles in four spacings (today; B „Luftig“; C „Apple“; D „Eine Fläche“), B, C and D also in dark. **The owner picked D** for the web app on 2026-11-25. |
| `11-vorlage-ruecksetzer.html` → `11-vorlage-ruecksetzer--light.png`, `--dark.png` | The template for falls as the owner described it: the Crash-Chart at 1J and pinned to 1M, Crashes im Vergleich with the running fall first, Tops und Flops pinned to 1W and 1M with bars, and the rebounders after the last three crashes side by side; on Apple's sizes and as one surface; synthetic data. |
| `real-app/` | The scripts behind boards 06 to 10 (`spacing.js` renders board 10's spacings, `gallery.js` photographs every widget light and dark from `all_sizes.exs`' dashboard, `templates.exs` stores the three dashboards of board 09 and `templates.js` photographs them today and on Apple's tiles): `dash.js` and `kpi.js` rearrange the running app's pages (nothing is stored, the LiveView socket is cut first), `all_sizes.exs` stores a throwaway dashboard with every kind in every size **on a throwaway review database only**, `widgets.js` photographs each widget. They need a local instance on the review seed at port 4003 (`priv/demo/README.md`). |
| `board.css` | The shared `mock-*` and `wd-*` rules of the I56 idea board, then this board's `sp-*` rules. |
| `build.js` | Generates the synthetic series (the I56 board's helpers) and writes the five boards. |
| `render.js` | Renders the boards to PNG at 1x, light and dark, reduced to 256 colours. |

## What drawing it found

* **The tabs are long, the grid is short.** A section such as „Beitrag je
  Position“ or the crash comparison has no fixed height, so no grid size
  draws it as the tab does. The size „Zeile“ answers that: it is 12 × 1 in
  the stored grid, so validation, reflow and the API stay as they are, and
  it is drawn at its content's height, the rows after it starting below.
* **Reflow makes most refusals disappear.** With A, the only refusals left
  are the 41st widget and a widget with no row left up to 200; both stand
  at the widget.
* **„Gesamtwert“ M was a second widget in the first one's frame.** Its four
  cells (TTWROR with IRR, cash, last booking, newest quote) answered four
  questions; the rule „each size shows more of the same“ keeps one.
* **A theme template needs a scope.** „Krypto Lover“ without a view shows
  everything; a dashboard therefore stores an optional view of its own.
* **Nineteen chips are the overload the owner wanted to avoid.** The quick
  choice is the operator's, the rest sits one click away, and the own
  periods are stored on the server, which reopens ADR-0062 §13's deferred
  ask at the owner's request.
* **„Buy The Dip“ is a name that tells the operator to buy.** It is asked,
  not decided: „keine Beratung“ is the owner's to read.

## Synthetic data only

Every name and figure is invented: generic security names, seeded random
walks, invented periods and windows. No portfolio figure, name or machine
detail appears. The colours and cards are today's (`app.css`).

## Rebuilding

```bash
node build.js
node render.js
```

`render.js` needs Playwright's Chromium; it reduces the PNGs to 256 colours
when python3 with Pillow is available.
