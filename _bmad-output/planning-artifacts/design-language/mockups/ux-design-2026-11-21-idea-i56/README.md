# Idea board: I56, every function a widget, dashboards composed from them

Drawn on 2026-11-21 at the owner's request ("Das UI Konzept wollten wir
sowieso überdenken, also mach Vorschläge und ggfs Mockups"), after the
owner set the direction the same day: all functions move onto a widget
basis, the operator composes their own dashboard, the project proposes
curated ones, and the principle carries into native widgets later. It is an
**idea board**, not a sprint's planning board; the idea's row in
`../../../ideas.md` (I56, with I35, I47, I50, I51, I53 and I55) carries its
open questions.

| File | What it is |
|---|---|
| `01-widget.html` → `01-widget--light.png`, `--dark.png` | The widget as the building block: its five parts (title and ⓘ with the payload's computation basis, its own controls such as the period, the ⋯ menu for size, view and removal, the content, the footer with its scope and the way into the full view); the sizes S, M, L and the full page, drawn on the performance chart; the catalogue, today's functions grouped by topic with where each lives today, the three the owner called hidden (snapshots, drift, crashes) marked. Maintenance is no widget: it moves to one quiet place (I47). |
| `02-navigation.html` → `02-navigation--light.png`, `--dark.png` | The owner's open question, both ways at the same width. A (recommended): the menu is the list of dashboards (curated and own), then "Entdecken" (securities, news, the widget catalogue), then "Pflege" at the foot. B: today's areas stay, each tab becomes a fixed widget dashboard, own dashboards beside them. Flip phrase: „Bereiche behalten“. |
| `03-dashboard.html` → `03-dashboard--light.png`, `--dark.png` | „Mein Überblick“ composed from what the owner reads most (the main chart by categories with the period in the widget, the drift table beside it, tops and flops, crashes, the cycle chart in its default „all cycles plus the projection“, rated news only, snapshots, income) on a 12-column grid; the same screen in edit mode (handles, size switch, ×, a drop target, the catalogue panel; the layout stored on the server and journaled, so the agent can compose one too); the five curated templates. |
| `04-devices.html` → `04-devices--light.png`, `--dark.png` | The same widgets on a phone (stacked, S two to a row) and, marked "später", as native widgets on an iOS home screen, a macOS desktop and a visionOS wall; native widgets pull the API with their own token, so they need no push delivery (B3.7). |
| `board.css` | The shared `mock-*` rules of the earlier idea boards, then this board's `wd-*` rules. |
| `build.js` | Generates the synthetic series and writes the four boards. |
| `render.js` | Renders the boards to PNG at 1x, light and dark, reduced to 256 colours. |

## What drawing it found

* **The period belongs in the widget.** The owner's most frequent move is
  shortening the main chart's period and going back to 1y, YTD and Max;
  with the chips inside the widget that is one click on any dashboard,
  and two widgets can show two periods side by side.
* **The view selector moves to the dashboard.** Today each screen picks its
  depot or view; on a dashboard one selector („Gesamt ▾“) sets it for all
  widgets, and a widget may override it in its ⋯ menu.
* **Edit mode answers I47's open question.** With dashboards edited in a
  mode, the maintenance place for the forms needs no edit mode of its own:
  it is one quiet area.
* **The phone needs widget-specific narrow layouts,** not only stacking:
  the tops-and-flops halves go one under the other, the chart's chips
  drop below the title, a table's bars shrink. Each widget therefore
  states its narrow layout, as it states its sizes.
* **Not every function fits a small size.** The security dossier, the full
  chart with its levels and the positions table stay full pages, reached
  from their widgets.

## Synthetic data only

Every name and figure is invented: the security names are generic
("Halbleiter AG", "Welt-ETF"), the series are seeded random walks, the
total is the sum of the invented category bands, and the crash windows'
falls are illustrative, not measured. No portfolio figure, name or machine
detail appears. The colours, the cards and the accent are today's
(`app.css`); the colour question is I48's own board.

## Rebuilding

```bash
node build.js
node render.js
```
