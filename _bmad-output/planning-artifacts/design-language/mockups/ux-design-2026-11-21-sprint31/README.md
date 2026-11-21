# Sprint 31 planning board: the first slice of ADR-0062 (I56)

Drawn on 2026-11-21 for the Sprint 31 planning PR. The idea boards 01 to
06 of `../ux-design-2026-11-21-idea-i56/` are adopted with the plan as the
shape of FR-60 (the owner's picks: navigation A, the period A, the width
classes); this board draws only what Sprint 31 builds of it and what is
transitional in it.

| File | What it is |
|---|---|
| `01-first-slice.html` → `01-first-slice--light.png`, `--dark.png` | ① A fresh instance: the template „Überblick“ read-only with „Anpassen“, in the transitional menu (Dashboards; Entdecken with Wealth until its sections are widgets, Securities, News, „Alle Widgets“; Pflege at the foot), with the slice's eleven widgets and the period above them. ② „Alle Widgets“, the catalogue page: what Sprint 31 builds, and, dashed, what comes with each screen's pass. ③ „Neues Dashboard“: empty or from a template. ④ The compact tab bar and its „Mehr“ sheet at 393 pt, 1 : 1. |
| `build.js` | Writes the board; it reuses the widgets and the page shell of the I56 idea board's `build.js`. |
| `render.js` | Renders it to PNG at 1x, light and dark, reduced to 256 colours. |

Every name and figure is invented, as on the idea boards. The colours and
cards are today's; I48 is its own question.

```bash
node build.js
node render.js
```
