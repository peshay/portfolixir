# Sprint 24 boards — the journal since a date, the costs beside the benchmark gap

Two boards for the Sprint 24 planning PR, drawn on 2026-11-04. Each is an
HTML artboard that links the real `priv/static/app.css` and is rendered to
PNG at 1200 px and at 390 px.

| Board | Files | Source |
|---|---|---|
| 01 — I16, the journal since a date | `01-journal-since.html`, `01-journal-since-390.html`, `01-journal-since--1200.png`, `01-journal-since--390.png` | idea I16; the plan's D-4 |
| 02 — I17, the costs beside the benchmark gap | `02-benchmark-costs.html`, `02-benchmark-costs-390.html`, `02-benchmark-costs--1200.png`, `02-benchmark-costs--390.png` | idea I17; ADR-0046, amended 2026-11-04 |

**Synthetic data only.** The journal entries and the benchmark figures come
from the synthetic review seed (`priv/demo/finding_surfaces_seed.exs`); the
two cost totals on board 02 are invented and marked amber. No real
portfolio data, name or machine detail appears.

## How the frames are made

As the Sprint 23 boards: `build.js` (copied from
`ux-design-2026-11-02-sprint23/`, only its header and its proposal CSS
differ) captures each frame with Playwright from a review instance in
German on the synthetic seed (port 4003, database `portfolixir_review`, the
seed's header gives the commands). The build only sends GET requests; the
benchmark is picked by its URL parameter (`benchmark_rate=5`), which the
page only remembers. A frame's "after" state is the shipped markup with the
proposal applied to the live DOM (the preps in `frames.js`). Each frame is
a static page under `frames/`, placed on its board by `board.js` as an
`<iframe>`. Desktop frames are 1060 px wide, phone frames 390 px. No script
runs on a board or a frame.

```
node build.js    # captures every frame, writes frames/ and the boards
node render.js   # renders the boards to PNG (Chromium in de-DE, so the
                 # date field reads as the German page would)
```

Dashed means new or changed; amber marks an invented figure; a circled
number ties a change to its section's text.

**Cut for the board:** the journal table keeps its first five entries; the
rest is one elided line.

## The picks (silence adopts the recommendation)

| Pick | Recommended | Alternative drawn | Flip by comment |
|---|---|---|---|
| Q1 — the journal's time control | **A**, one date field „Seit“ in the filter form | B, a chip family „Zeitraum“ (Alle · Heute · 7 Tage · 30 Tage) | „Q1 B“ |
| Q2 — the costs beside the gap | **A**, one line under the benchmark rows, one ⓘ sentence | B, each row split into costs and a residual „Auswahl und Timing“ | „Q2 B“ (the residual is then labelled as what is left after the booked costs, never as selection and timing) |

The reasons are on each board and in the plan's D-4 and D-8.

## New strings (German as drawn, English msgid draft)

| German | English msgid draft | Where |
|---|---|---|
| Seit | Since | the journal's date field |
| seit %{date} (UTC) | since %{date} (UTC) | the journal's basis line |
| Zeitraum · Heute · 7 Tage · 30 Tage | Period · Today · 7 days · 30 days | board 01 B only |
| Im Zeitraum gezahlt: Gebühren %{fees} · Steuern %{taxes} — die Benchmark zahlt keine. | Paid in the period: fees %{fees} · taxes %{taxes}; the benchmark pays none. | the Performance block |
| Gezahlt im Zeitraum: die Gebühren und Steuern, die dieses Portfolio (diese Ansicht) im selben Zeitraum gebucht hat, umgerechnet zum Kurs ihres Buchungstags; Erstattungen mindern die Steuern. Nicht enthalten ist der Ertrag, den das gezahlte Geld sonst erwirtschaftet hätte. | Paid in the period: the fees and taxes this portfolio (this view) booked in the same period, converted at their booking day's rate; refunds reduce the taxes. Not included is the return the money paid would otherwise have earned. | the benchmark ⓘ |

The story that builds each string writes it into the catalogue with
`gettext`; the English source is the msgid, as `EXPERIENCE.md` asks.

## Found while drawing

- **The journal cannot be paged.** `GET /api/v1/journal` takes `limit` up
  to 1000 and no offset or cursor; the page's „Ältere Einträge zeigen“
  grows the same limit. That is why D-4 makes `since=` the family's paged
  delta rather than a bare filter (no separate filing: J2 fixes it).

**Frame 02-a-info** shows the ⓘ forced open in static markup; no script
runs in a frame, so its placement is not the page's (the placement hook
of #1336 decides that on the built screen).
