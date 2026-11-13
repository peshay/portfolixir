# Sprint 29 UAT persona on the review seed (2026-11-13)

The closing act's last bullet of the Sprint 29 plan
(`sprint-plan-2026-11-12-sprint29.md`), walked on head `833f6bdc`
(main with PR 1 and PR 2 merged, plus PR 3, Lane H) in Chromium, German,
device scale 2, 1200 px unless a name says `phone` (390 px). Every figure is
from the synthetic review seed (`priv/demo/finding_surfaces_seed.exs`);
nothing describes a real person or portfolio.

## How the walk ran

A temporary test (deleted afterwards) booted the endpoint on a free
loopback port in the test sandbox, evaluated the review seed, and added,
all synthetic:

- **news:** the news page world of `Portfolixir.NewsFixtures.page_world!/1`
  on the seed's most traded security („Meridian Global Equity ETF“), one
  aggregator feed with four items (two claiming `wire.example.com`, rated
  `primary` first, two claiming `gossip.example.net`), one of the wire items
  assigned to the security, and one issuer story whose only link is 300
  characters long;
- **Bitcoin closes:** a weekly synthetic path for the seed's „Bitcoin“
  around the fake chain's halvings (tops and lows placed by hand). The
  seed's own Bitcoin closes (about 45,000 to 60,000 EUR) stay stored beside
  them, so the chart's line saw-tooths between the two series; that is the
  harness, not the app;
- **chain source:** a fake Esplora answering `mempool.space` through
  `Portfolixir.Chains.NoNetwork` (synthetic block hashes, ten minutes a
  block, the tip at 939,256); no real network. A flag file made it refuse
  every connection for the stale step;
- **the derived layer** switched on for the walk (the test config keeps it
  off), and call counters on `Performance.view_contribution_analysis/4` to
  see whether a period switch computes the bands again.

The stale step backdated the chain state row's `last_ok_at` and
`last_tried_at` by 25 hours (a day of failed scheduled reads, which the
test configuration never runs), then pressed „Jetzt lesen“ with the fake
refusing.

## Screenshots

| # | File | What it shows |
|---|---|---|
| 01 | `01-light-news-queue-after-rating.png` | „Zuzuordnen“ after `wire.example.com` was rated down to awareness and `gossip.example.net` blocked over the API: 2 items left, both `awareness` |
| 02 | `02-light-news-sources-rated.png` | „Quellen“ with the two ratings by hand |
| 03 | `03-light-promotion-awareness-story-form.png` | „Ins Research-Log“ on the downgraded wire story: Quellenqualität „Wahrnehmung“ |
| 04 | `04-light-promotion-long-link-form.png` | The same form for the story whose only link is 300 characters: the link shown as its domain |
| 05 | `05-light-research-promoted-entries.png` | The Research tab: headline, „Zahlen · positiv“, „maschinell“, the link's domain |
| 06 | `06-phone-research-promoted-entries-390.png` | The same at 390 px, no sideways scroll |
| 07 | `07-light-holdings-benchmark-held-fund.png` | Holdings compared with a held fund (Vanguard FTSE All-World) through „Benchmark…“ › „Im Bestand“ |
| 08 | `08-light-crash-benchmark-form.png` | The crash benchmark chosen inline in the Crashes section |
| 09 | `09-light-crash-detected-window.png` | The detected window (19.06.2026, -11,5 %, läuft, gap 7 days) beside the seed's manual one |
| 10 | `10-light-crash-detected-losers.png` | The detected window's losers, im Depot, against the benchmark |
| 11 | `11-light-crash-windows-named-and-overlap.png` | The window named „Synthetic summer slide“ and an overlapping manual window „Synthetic overlap“ |
| 12 | `12-light-crash-benchmark-switched-name-hidden.png` | The benchmark switched to iShares Core MSCI World: no detected window, the name under „Name ohne Fenster“ (defects 1 and 2) |
| 13 | `13-light-crash-benchmark-back-name-restored.png` | Switched back: the name is on its window again |
| 14 | `14-light-im-depot-ansehen-holdings-range.png` | „Im Depot ansehen“ on the ongoing window: Holdings over 19.06.2026 – 13.11.2026 |
| 15 | `15-light-overview-data-quality-held-first.png` | The Overview's data-quality line, held first with „(im Katalog n)“ |
| 16 | `16-light-wealth-stack-period-back-1y.png` | Wealth's stack back on 1J after 3J, 1J, 3J: „berechnet 09:23 UTC“ unchanged |
| 17 | `17-phone-journal-narrowed-390.png` | The journal at 390 px narrowed to „Agent“: labels in one column, every control from one edge |
| 18 | `18-phone-securities-narrowed-390.png` | Wertpapiere's filter sheet at 390 px with „Im Bestand“ on |
| 19 | `19-phone-transactions-narrowed-390.png` | Transaktionen's filter sheet at 390 px with „Kauf“ on: one chip per row (defect 3) |
| 20 | `20-light-bitcoin-halving-chain-bind.png` | „Halving-Kette“ set to Bitcoin in the edit form |
| 21 | `21-light-bitcoin-edit-form-read-now.png` | After „Jetzt lesen“: 4 confirmed halvings, the next ≈ 21.12.2028 – 21.12.2028 (defect 5), the source line and the ten-minute wait |
| 22 | `22-light-bitcoin-cycle-chart-1200.png` | The chart on „Zyklus“ with cycles on: halvings, ▲ and ▼, both bands, the interval table (defect 4 at its top right) |
| 23 | `23-dark-bitcoin-cycle-chart-1200.png` | The same in the dark theme |
| 24 | `24-phone-bitcoin-cycle-chart-390.png` | The same at 390 px |
| 25 | `25-light-overview-bitcoin-cycle-card.png` | The Overview's card „Bitcoin-Zyklus“ |
| 26 | `26-light-chain-source-stale-after-failed-read.png` | The cycle bar after the fake stopped answering: „Kettenquelle seit 25 Std. ohne Antwort“ |

## Steps and how they compared

| Step | Seen | Against the API or board |
|---|---|---|
| Rate a domain down, block another | journal: `items_rerated` 3, `items_removed` 2; the queue from 4 to 2 items, the wire items `awareness` | matches `GET /news/stories` and the journal |
| Read a promotion | the downgraded story proposes and stores „Wahrnehmung“ | entry #13 `source_quality: awareness` |
| Promote a story with only long links | saved; the entry keeps the 300-character link, shows its domain | entry #14 `source_url` 300 characters, `primary` |
| Research tab | headline, event type and tone in words, „maschinell“ only on labelled entries | matches `GET /securities/:id/notes` |
| Held fund as comparison benchmark | +3,8 % vs. +0,3 %, IRR +7,5 % vs. +0,1 %, Sparplan +6.021,10 EUR | `GET /performance/benchmark?period=1y`, `benchmark_security: held` |
| Held fund as crash benchmark | one detected window, -11,5 %, provisional | `GET /crashes`: decline 0.11515…, `max_gap_days` 7 |
| Each list against the API | losers, winners, rebounders, im Depot and Katalog, the detected and the manual window, after each switch | every rank, return, points and `days_back` equal; the counts without an answer equal |
| Name, overlap, switch and back | name hidden as `unmatched_names` under iShares, back on its window under Vanguard | matches `GET /crashes` each time |
| „Im Depot ansehen“ | Holdings from the high to today (window ongoing) | as `holdings_link/3` and ADR-0058 §9 state |
| Overview held-first counts | 18 (im Katalog 26) stale, 35 (48) without logo, 2 implausible | `GET /securities?data_quality=…` with and without `holding_status=held` |
| Wealth period back and forth | the bands computed once per period; no call on the switches back | API `as_of` 09:23:01 on three 1y reads, no compute counted |
| 390 px bars | every label on one edge, every control on one edge (journal at 77 px; the sheets at 17 px) | board 06 |
| Bind Bitcoin, read halvings | four halvings 2013-01-01, 2016-12-29, 2020-12-26, 2024-12-24 from the fake | `GET /securities/57/cycles` |
| Cycles and both bands to the digit | Tief-Band 29.333,37 – 73.142,86 EUR, 25.10.–24.11.2026, erreicht; Top-Band 143.380,71 – 201.666,63 EUR, 17.09.–06.12.2029, offen; every interval in the table | equal to the API, and recomputed independently from the closes (log step from the six-place factors) |
| Dashboard card | both events, states and n as on the chart; opens the chart on „Zyklus“ with cycles on | equal to the API |
| Source goes stale | the stale line; both hosts tried; nothing else changed | `GET /chains`: `stale: true`, `last_error` names both hosts |

## Defects

1. **S3** „Name ohne Fenster“ always says „Die Kurse haben sich geändert …“,
   also when the name is hidden only because another crash benchmark is
   chosen (screenshot 12).
2. **S3** The same table needs 1,059 px in a 922 px wrapper at 1200 px; its
   actions („Löschen“) are reachable only by scrolling the table sideways
   (screenshot 12).
3. **S3** Transaktionen's phone filter sheet stacks every chip on its own
   row (31 rows, the sheet 1,355 px tall); Wertpapiere's sheet wraps them.
   From L2 (`504dddcb`) (screenshot 19).
4. **S3** On the cycle chart at 1200 px the estimated halving's label runs
   into the Top-Band's label and is cut off at the plot's right edge
   (screenshot 22).
5. **S3** A next-halving window whose two ends fall on one day reads
   „21.12.2028 – 21.12.2028“ (edit form, chart label); seen with the fake's
   exact 600 s blocks (screenshot 21).
6. **S3** The journal shows the crash-benchmark change as raw ids
   („value: 55 → 56“) rather than the securities' names.
7. **S3, older** A research entry promoted from an aggregator's story links
   the aggregator's redirect (`search.example.com`), not the rated domain.

Defects 4 and 5 are fixed on PR 3 (#1462; the Termine tab's one-day label
stays a polish line); 1 to 3 and 6 are lines on their screens' polish
lists, 7 on the Securities list as an older finding.
