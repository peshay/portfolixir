# Sprint 31 planning board: the first slice of ADR-0062 (I56)

Drawn on 2026-11-21 for the Sprint 31 planning PR. The idea boards 01 to
06 of `../ux-design-2026-11-21-idea-i56/` are adopted with the plan as the
shape of FR-60 (the owner's picks: navigation A, the period A, the width
classes); this board draws only what Sprint 31 builds of it and what is
transitional in it.

| File | What it is |
|---|---|
| `01-first-slice.html` → `01-first-slice--light.png`, `--dark.png` | ① A fresh instance: the template „Überblick“ read-only with „Anpassen“, in the transitional menu (Dashboards; Entdecken with Wealth until its sections are widgets, Securities, News, „Alle Widgets“; Pflege at the foot), with the slice's eleven widgets and the period above them. ② „Alle Widgets“, the catalogue page: what Sprint 31 builds, and, dashed, what comes with each screen's pass. ③ „Neues Dashboard“: empty or from a template. ④ The compact tab bar and its „Mehr“ sheet at 393 pt, 1 : 1. |
| `02-closing-act.html` → `02-closing-act--light.png`, `--dark.png` | The closing act's accessibility (Y1 to Y5) and design (DS1 to DS5) findings on the dashboard, each visible change before and after, drawn before the code builds it: ① the frame (title 15 px in the wide form, the ⓘ on the title's line, the period tag under it, „ohne Zeitraum“ only in the edit mode and the ⋯ menu, the footer at the frame's foot, the height budgets S ≈ 112, M ≈ 236, T and L ≈ 360 px), „Gesamtwert“ at S drawing its figure itself, „Abseits des Ziels“ at S as a count and at the new size M as the list; ② „Tops und Flops“ at M, one ranking at a time; ③ no blank band under the bar; ④ the edit mode at 1200 px with the catalogue as a drawer; ⑤ the crash figures unbroken and the cycle widget's sub-line and footer link; ⑥ the compact class's 44 px targets and no hidden tab stops; ⑦ „Alle Widgets“' search, the short-wide rail's labels, „Leer beginnen“; ⑨ (added before its code, the coordinator's follow-up) the S forms of „Gesamtwert“ (the note one line), „Datenqualität“ (three counted lines, „+n weitere · Prüfen →“) and „Fällig“ (a short basis, two dated lines, the rest unfolding in the widget). ⑧ holds two changes fix batch 1 had already built — „Allokation und Drift“'s effective target with the basis line „Σ Soll oberste Ebene …“ and „Gesamtwert“ at M following the period („TTWROR · 3M“): **drawn after the code**, not before it. |
| `build.js` | Writes the boards; it reuses the widgets and the page shell of the I56 idea board's `build.js`. Board 02's frames are in `board02.js`. |
| `render.js` | Renders them to PNG at 1x, light and dark, reduced to 256 colours. |

Every name and figure is invented, as on the idea boards. The colours and
cards are today's; I48 is its own question.

```bash
node build.js
node render.js
```
