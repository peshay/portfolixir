# Sprint 28 planning boards

Drawn on 2026-11-08 by the Sprint 28 planning session, before any code, as
the sprint workflow's "UI changes are mocked first" asks. Each board says
on its first lines what is already decided (by ADR-0056 §10 and A2, or by
the owner's work-out of I27 to I29) and what the board itself proposes; the
plan (`../../../../implementation-artifacts/sprint-plan-2026-11-08-sprint28.md`)
names each proposal with the phrase that flips it.

| File | What it is |
|---|---|
| `01-news-view.html` → `01-news-view--light.png`, `--dark.png` | ADR-0056 §10 and A2 (#1420): A (recommended), a page "Nachrichten" in the main navigation with the tabs Meldungen (the health line, the queue with "Zuordnen", the digest per security), Feeds and Quellen; B, the same spread over Verwaltung and a filter on Wertpapiere; a tab "Nachrichten" on a security with "Ins Research-Log"; the note markers as pins at the top edge (A, recommended) or as dots on the line (B). |
| `02-stack-filter.html` → `02-stack-filter--light.png`, `--dark.png` | FR-56 (#1427) on a two-level tree: Kategorien as the default, a filter on „Aktien“ at both levels, „Nicht zugeordnet“ as a filter; and #1426, a band that changes sign, today and as proposed. |
| `03-ttwror-levels.html` → `03-ttwror-levels--light.png`, `--dark.png` | FR-57 (#1428): one line per band in the TTWROR mode, the view's line bold, at the category level and with the filter, a late band starting at 0 %. |
| `04-version.html` → `04-version--light.png`, `--dark.png` | FR-55 (#1429): the version at the foot of the sidebar in its three states (a release, a development build, unknown) and at the bottom of the phone's menu. |
| `05-currency-mismatch.html` → `05-currency-mismatch--light.png`, `--dark.png` | #1415: the Overview's data-quality line today and with the new clause for the `currency_mismatch` set, and its filter chip on Wertpapiere; captured from the review instance (`dq-line.html`, `dq-chips.html`) and changed in place. |
| `06-privacy-stack.html` → `06-privacy-stack--light.png`, `--dark.png` | #1433, the Sprint 28 amendment's D-A2: the stacked chart in the privacy mode today (a 100 % stack) and as you asked on 2026-11-08 (the value chart's shape, the axis in percent of the window's first day, no amount). |
| `07-basis-and-bar.html` → `07-basis-and-bar--light.png`, `--dark.png` | The Sprint 28 amendment's D-A4 and D-A5: the stacked chart's basis today and behind its ⓘ (I1), and its bar at 390 px today, with a label column (A, recommended) and with every label above its control (B). |
| `capture.js` | Captures the shell (sidebar, top bar, the main element emptied) from the review instance into `shell.html`. |
| `capture-dq.js` | Captures the Overview's data-quality block and the Wertpapiere filter chips into `dq-line.html` and `dq-chips.html`. |
| `build.js` | Generates the synthetic series and writes `frames/` and the seven boards. |
| `render.js` | Measures the frames, rebuilds, and renders each board to PNG at 1x, light and dark, reduced to 256 colours. |

## Synthetic data only

The shell is captured from the review instance on the synthetic review seed
(`priv/demo/finding_surfaces_seed.exs`) and carries navigation only. Every
security, feed, domain and headline on the boards is generic and every
figure is invented (a seeded random walk); the domains end in `.example`.
No real portfolio, name or machine detail appears.

## Rebuilding

Optionally re-capture the shell from a review instance on port 4011 (see
the Sprint 26 boards' README for the four commands), then:

```bash
node capture.js      # optional
node capture-dq.js   # optional
node build.js
node render.js
```

`render.js` needs the Playwright that `test/browser` installs; set
`PLAYWRIGHT_CHROMIUM_EXECUTABLE` on a machine with a Chromium of its own.
