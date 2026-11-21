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
| `04-devices.html` → `04-devices--light.png`, `--dark.png` | Marked "später": native widgets on an iOS home screen, a macOS desktop and a visionOS wall; they pull the API with their own token, so they need no push delivery (B3.7). Its first draw also showed the app on a phone, which the owner found squeezed and hard to read; that view moved to board 06, redrawn. |
| `05-period.html` → `05-period--light.png`, `--dark.png` | Drawn after the owner's doubt about a period per widget (two periods side by side against all dashboards on one period). A (recommended): one period in the top bar that holds across dashboards and is remembered; a widget follows it („folgt · 3M“) until its ⋯ menu pins its own („📌 eigener: Max“); a widget that lacks the period translates it and says so („3M → Quartal“), one that has none says „ohne Zeitraum“. B (a period per widget) and C (a period per dashboard) in a table. |
| `06-screens.html` → `06-screens--light.png`, `--dark.png` | Drawn after the owner's remarks on the squeezed phone and on the iOS screen formats, the folding iPhone included. One rule: the available width picks the layout, never the device model (compact under 600 pt, one column of compact widget forms and a tab bar; medium 600 to 1000 pt, two columns; wide from 1000 pt, board 03's grid). Every widget has its own compact form with phone type (text 15 to 17 pt, figures 22 to 30 pt, nothing under 12 pt, rows of at least 44 pt, one name and one figure per line). Drawn 1 : 1 in points: three iPhone sizes (375 × 667, about 400 × 870, 440 × 956), the folding iPhone folded and unfolded (**its sizes assumed**, 360 × 640 and 760 × 580, to be checked against the real device before a build), and an iPad portrait at 60 %. |
| `board.css` | The shared `mock-*` rules of the earlier idea boards, then this board's `wd-*` rules. |
| `build.js` | Generates the synthetic series and writes the four boards. |
| `render.js` | Renders the boards to PNG at 1x, light and dark, reduced to 256 colours. |

## What drawing it found

* **The view selector moves to the dashboard.** Today each screen picks its
  depot or view; on a dashboard one selector („Gesamt ▾“) sets it for all
  widgets, and a widget may override it in its ⋯ menu.
* **Edit mode answers I47's open question.** With dashboards edited in a
  mode, the maintenance place for the forms needs no edit mode of its own:
  it is one quiet area.
* **The phone needs a compact form per widget, not a narrower desktop
  widget.** The first draw of board 04 stacked the desktop widgets and
  was unreadable (the owner, 2026-11-21); board 06 gives each widget a
  compact form with phone type and one name and one figure per line, the
  second figure below it, and the tops and flops as a two-way switch.
* **The width class, not the device, picks the layout,** so a folding
  phone, a split iPad screen or a narrow desktop window falls into a class
  without a device list in the code.
* **The period belongs above the widgets, with a pinned exception.** The
  first idea (the period inside every widget) made a period change many
  clicks and left dashboards on different periods; board 05 keeps the
  owner's side-by-side case as a pinned widget, marked so a pinned figure
  is never read as the top bar's.
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
