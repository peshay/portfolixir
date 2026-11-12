# Sprint 29 planning boards

Drawn on 2026-11-12 by the Sprint 29 planning session, before any code, as
the sprint workflow's "UI changes are mocked first" asks. Each board says
on its first lines what is already decided (and by which record) and what
the board itself proposes; the plan
(`../../../../implementation-artifacts/sprint-plan-2026-11-12-sprint29.md`,
D-5 and D-6) names each proposal with the phrase that flips it.

| File | What it is |
|---|---|
| `01-crash-section.html` → `01-crash-section--light.png`, `--dark.png` | FR-54 (#1421), ADR-0058 §9 and its amendment of 2026-11-12: the „Crashes“ section on Vermögen › Risiko, drawn from idea board 03 — in the page after the portfolio metrics at 1200 px (P1 A), the window as a select in one labelled-controls bar (P2 A; B: chips), Verlierer „Im Depot“ against the crash benchmark's dashed line with the Pp. difference, „Ganzer Katalog“ with „im Depot“ marks, the ⓘ open, Erholer complete and provisional („vollständig am …“, „noch nicht“), an ongoing window with a provisional low, the windows disclosure (erkannt/manuell, longest gap, names without a window and the form that asks for the low), no crash benchmark (with and without manual windows), a window before the view's first day, the phone at 390 px (A bars, recommended; B rows) and the privacy mode (unchanged). |
| `02-benchmark-picker.html` → `02-benchmark-picker--light.png`, `--dark.png` | #1416, ADR-0046's amendment of 2026-11-07 and ADR-0058 §1: Bestände's „Benchmark…“ today (flagged only) and as proposed (A: „Benchmarks“ then „Im Bestand“ as labelled groups, recommended; B: plus a search over every security with quotes), „Nach dem Verkauf“'s select today and with two groups, and where the crash benchmark is chosen: inline in the Crashes section's disclosure, unset and changing (A, recommended), or a new page „Einstellungen“ under Verwaltung (B). |
| `03-research-entry.html` → `03-research-entry--light.png`, `--dark.png` | The two-way gap Sprint 28's close-out recorded (ADR-0044's amendment of 2026-11-06; ADR-0056 §8, A2, D8): the Research tab today and with the headline, the pin's glyph, „Ereignisart · Tonalität“ and „maschinell“ (A, recommended), the event type as a badge (B), at 390 px, a filter by event type (C, an option), and A in the app's frame. The research form's three fields (the plan's N4) are added here as a frame before their story starts. |
| `04-dq-held-first.html` → `04-dq-held-first--light.png`, `--dark.png` | #1417 (OQ-4 of the 2026-11-07 triage): the Overview's data-quality line and the KPI cell today and counted over held securities first, the catalogue count in parentheses (A, recommended) or as a last clause (B), at 390 px, and the state with every held count 0 (no section; where the catalogue count stays reachable). |
| `05-translucent-bands.html` → `05-translucent-bands--light.png`, `--dark.png` | Idea I33: the stacked chart's bands today, at 0.8 (recommended; the negative part 0.6) and at 0.65, each with a part below zero and a hovered band, and 0.8 in the privacy mode. |
| `06-control-bar.html` → `06-control-bar--light.png`, `--dark.png` | #1435 (built in Sprint 30, the plan's D-3): the bars that break "labelled controls start on one edge", measured on the review instance, before and after the shared component: the journal and the sale's comparison at 390 px, Wertpapiere and Transaktionen at 1200 px. |
| `06-control-bar-inventory.md` | #1435's inventory: every bar of labelled controls (file:line, page, controls, measured at 390 and 1200 px), the unlabelled bars the issue names, every free paragraph past one sentence, the proposed threshold and its exceptions. |
| `07-cycle-states.html` → `07-cycle-states--light.png`, `--dark.png` | ADR-0059 §4, §8, §11 and ADR-0060 §1, §4, §5, §11, §12: the states these records add to the I12 idea boards. „Halving-Kette“ in „Wertpapier bearbeiten“ (Bitcoin with the source's health, Litecoin by hand with „1 von 2“, a refused own URL), the question before halving events are deleted (A in the dialog, recommended; B a second dialog), the cycle bar at 1200 px (not bound, too few halvings A/B, without a source, current, fallback, stale, refused own URL A/B, „Jetzt lesen“), Max with the partial 2012 window and the count line, the range „Zyklus“ today with `one_price_relation` and the band states, `no_top_yet` and `too_few_observations` as of an earlier date, `parts_disjoint` on a labelled what-if variant (A parts inside the outlined hull, recommended; B hull only), and the bar at 390 px. Every figure computed by ADR-0060's rules from the idea boards' synthetic series. |
| `build-c.js`, `render-c.js` | Board 07: `build-c.js` writes `frames/07*` and the board; `render-c.js` measures and renders it (frame heights through `FRAME_SIZES_C`). |
| `build-a.js`, `render-a.js`, `shell-a.html` | Boards 01 and 02: `build-a.js` writes `frames/01*`, `frames/02*` and both boards; `render-a.js` measures the frames, rebuilds and renders the PNGs; `shell-a.html` is the Sprint 28 shell with „Nachrichten“ and the version foot added as `app_shell.ex` renders them. |
| `capture-b.js`, `capture-b-inventory.js` | Boards 03 to 06: capture the shell, the Research tab's head, the Overview's data-quality line, the held and catalogue counts and the bars (`*-b.html`, `counts-b.json`, `bars-b.json`), and measure every page's bars and paragraphs (`inventory-b.json`), from a review instance on port 4012. |
| `build-b.js`, `render-b.js` | Write `frames/03*` to `frames/06*` and boards 03 to 06; render them to PNG at 1x, light and dark (`frames/sizes-b.json`). |

Three agents drew the boards in parallel, so each part has its own scripts
and its own frame sizes; none reads another's files.

## Synthetic data only

The shells are captured from (or modelled on) the review instance on the
synthetic review seed (`priv/demo/finding_surfaces_seed.exs`) and carry
navigation only; the version foot reads a placeholder commit. Every
security, window, headline and figure on the boards is generic and
invented. No real portfolio, name or machine detail appears.

## Rebuilding

```bash
node build-a.js && node render-a.js     # boards 01 and 02
node capture-b.js                       # optional, a review instance on 4012
node capture-b-inventory.js             # optional, the same instance
node build-b.js && node render-b.js     # boards 03 to 06
node build-c.js && node render-c.js     # board 07
```

The render scripts need the Playwright that `test/browser` installs; set
`PLAYWRIGHT_CHROMIUM_EXECUTABLE` on a machine with a Chromium of its own.
