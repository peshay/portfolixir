# Sprint 11 — closing-act walkthrough (2026-09-15)

Design-critic and UAT persona pass of the agentic review closing act
(ADR-0026 step 3), run under section G's conditions of
`docs/development/pr-review-checklist.md`, on the synthetic demo dataset
(`priv/demo/`, no real data), against a development server started with
`PORTFOLIXIR_UI_PASSWORD` and `PORTFOLIXIR_API_TOKEN` set. The shots in this
directory are the retakes after the fix round; the findings below say what
the first takes showed.

## Conditions the walkthrough ran under (stated so the claim is checkable)

- **DE locale**: every touched screen was rendered in DE (`?locale=de`, the
  session then carries it); the EN desktop shot of the Wealth page is the
  comparison, not the pass.
- **390 px**: the Wealth page with two benchmarks active, the opened picker,
  the comparison card and the stale-quote finding at 390 × 844 in a mobile
  Chromium context (`isMobile`, coarse pointer, device scale 2). Touch
  targets were measured through `getBoundingClientRect` before any
  full-page capture — a full-page screenshot resizes the emulated viewport
  and drops the coarse pointer for the rest of the page's life, which is
  what made the first measurement read 34 px.
- **Seed data that fires the alarm surfaces**: the demo dataset carries a
  held security whose last quote is 35 days old (the stale-quote finding of
  Lane X fires on it), a held security with no price at all, and a
  settlement account in a currency without a stored rate; the benchmark's
  own history starts inside the `max` period, so the covered-window basis
  line of Lane B fires on the same data.
- **The operator's own path, not seeded flags**: the ETF was marked as a
  benchmark through the Securities page's row menu (and unmarked and marked
  again, so both directions ran), the selection was made through the
  picker's own GET form, and the stale holding was retired through the row
  menu — every write went through the LiveView, none through SQL.
- **Live perimeter checks** ran with `curl` against the same server and are
  listed under "What was checked live".
- The run is scripted (`uat.mjs`, Playwright against the booted instance)
  and reports console errors, page errors and CSP violations; the final run
  reported none.

## What was looked at

| Shot | Screen | What it shows |
| --- | --- | --- |
| `securities-mark-benchmark-de-desktop.png` | `/securities`, DE, 1280 px | the row menu's benchmark item and the "als Benchmark markiert" flash |
| `wealth-picker-open-de-desktop.png` | `/portfolio`, DE, 1280 px | the Benchmark… disclosure opened: the flagged securities as checkboxes, the fixed-rate field, Apply, "up to two" |
| `wealth-benchmark-de-desktop.png` | same, after Apply | the comparison card next to TTWROR/IRR, the two dashed overlays on the TTWROR chart with their legend, the picker summary naming what is active |
| `wealth-tooltip-de-desktop.png` | same, crosshair on the chart | the tooltip carrying the portfolio pair and both benchmarks' bought-once returns for the hovered day |
| `wealth-kpi-benchmark-max-de-desktop.png` | same, period `max` | the covered-window basis line ("ab 2025-06-18 — 1 früherer Fluss ausgelassen") under the ETF row |
| `wealth-benchmark-en-desktop.png` | `/portfolio`, EN, 1280 px | the comparison |
| `wealth-benchmark-de-390.png` | `/portfolio`, DE, 390 px | the whole page with two benchmarks active |
| `wealth-kpi-benchmark-de-390.png` | the comparison card, 390 px | one row per benchmark: swatch, name, delta, the two pairs |
| `wealth-picker-open-de-390.png` | the picker, 390 px | the controls at 44 px |
| `wealth-stale-finding-de-390.png` | the data-quality row, 390 px | the stale-quote finding naming the holding with the date of its price and the remedy |
| `securities-stale-filter-de-desktop.png` | `/securities?dq=stale_quote&holding=held` | the finding's link lands on the one held, stale-quoted security |
| `wealth-after-retire-de-desktop.png` | `/portfolio` after retiring it | the finding gone (after the fix round; see finding 1) |

## What was checked live

Against the development server with the UI password and an API token set,
from the host:

- `GET /health` with `Host: evil.example` → 421, before the router.
- `GET /portfolio` without a session → 302 to `/login?to=%2Fportfolio`.
- `GET /api/v1/portfolios` without a token → 401.
- `GET /api/v1/portfolios/1/performance/benchmark?benchmark=rate:0.02&period=1y`
  → 200; `benchmark.kind: rate`, the window `2025-09-15 – 2026-09-15`,
  `end_value_delta`, both IRRs, `computation_basis.frictionless: true`.
- `…?benchmark=security:4&period=max` → 200 with the requested window from
  the first booking (2023-01-02), the covered window from the day after the
  benchmark's first quote (2025-06-18) and the one earlier flow named in
  `excluded_flows`.
- `…?benchmark=security:1` (not flagged) → 422 `is not a benchmark security`;
  `…?benchmark=foo` → 422 `is invalid`; no `benchmark` → 422 `can't be blank`.
- `GET /api/v1/views/1/performance/benchmark?benchmark=rate:0` → 200.
- `GET /api/v1/contract` → version 4 naming both benchmark endpoints and
  both tools.
- `GET /login` → `content-security-policy` with a per-request nonce in
  `script-src` and no `unsafe-inline` for scripts; `GET /app.css` →
  `x-content-type-options: nosniff`.

- ADR-0037 boot check on every main route (`/`, `/portfolio`, both tabs,
  `/securities`, a security detail with its chart, `/transactions`,
  `/imports`, `/buckets`, `/classifications`, `/cashflow`, `/snapshots`,
  `/tax`, and `/portfolio` with two benchmarks selected): each renders,
  connects its LiveView socket, survives a forced disconnect and reconnects,
  under the nonce CSP, with no console error and no CSP violation.

## Findings and what was done

The four review roles (correctness hunter, edge-case hunter, risk-tier
verification pass on Lanes X and B, design critic against the living
design-language spec) and the UAT persona pass reported together
thirty-odd confirmed items; every one in the batch's scope was fixed on the
branch in the review-round commits, tests first. The ones a reviewer should
know about:

1. **Fixed (blocking, correctness hunter, edge-case hunter, risk-tier
   pass):** a benchmark comparison built from the *superseded* walk — the
   one the Wealth page renders while the fresh walk computes — was
   memoised under the current data version and then served as fresh, so
   after any write the delta ignored what the TTWROR beside it already
   showed. The engine never memoises from a stale analysis and keys on the
   walk's own compute instant; the memo suite now runs with the derived
   layer on, which the async engine suite never did (the test config keeps
   the layer off).
2. **Fixed (blocking, both hunters):** a rate a hair above −100 % or beyond
   the float range crashed the daily factor — 500 on the API and, stored in
   the year-long cookie, a Wealth page that died on every mount. One bound,
   the IRR solver's own domain (−0.999999 .. 10), is shared by the engine,
   the API parser and the selection plug; the plug also keeps one spelling
   per rate and refuses an id beyond int8, which the database encoder used
   to raise on.
3. **Fixed (high, risk-tier pass):** a priced delivery entered `F_d` at its
   booked price but was no price observation, so a security with no price
   yet was valued at 0 the same day and a delivery as a portfolio's first
   booking read as a total loss for ever. A delivery now seeds the price of
   a security that has none — and re-prices a retired one whose carried
   quote is no measurement, as a basis step like a trade — while an
   already priced position keeps the day's price. Three exact fixtures pin
   it; ADR-0010's amendment records the refinement.
4. **Fixed (UAT persona, first take):** retiring the stale-quoted holding
   through the row menu left the Wealth finding standing and the count
   unchanged, although retiring is the remedy the finding names. A retired
   holding leaves the count, the finding and the securities list's
   `stale_quote` predicate (which the finding links to; the edge-case
   hunter found the count and the list disagreeing once one was retired).
5. **Fixed (should-fix, design critic, edge-case hunter):** the card
   hard-coded "IRR" next to a sibling card that switches to the period MWR
   for windows under a year; the payload now carries `portfolio_mwr` and
   `benchmark_mwr` and the row picks and labels the pair over the
   comparison's own window.
6. **Fixed (should-fix, design critic):** the headline figure had no name
   ("Benchmark comparison", "savings plan: …"); the two overlays existed
   only in the SVG (UX-DR10 — one table column per drawn benchmark, and the
   chart's accessible name lists them); the legend and card swatches
   differed by hue only (UX-DR7 — slot 2 is dotted everywhere; the rule's
   table gained the row); the value chart dropped the overlays silently
   (UX-DR26 — a hint says they are drawn in the % view only); the picker's
   active echo was plain text (chips carrying the swatch, and the limit
   states that the first two ticked apply); at 390 px the two rows had two
   compositions (one three-line composition now).
7. **Fixed (should-fix, design critic, DE):** "einmal gekauft" → the broker
   vocabulary's "Einmalanlage"; the stale finding named an action the app
   calls something else ("als eingestellt markieren" → "stilllegen … Kurse
   aktualisieren"), said "Gesamtsumme" where its siblings say "Summen", and
   wrote a locale date where its siblings write ISO; the ⓘ text reworded in
   both languages ("Anfangswert" like the sibling card, the pair order
   stated); "auf der Seite Wertpapiere" like the classifications hint.
8. **Fixed (small, correctness hunter):** a benchmark without a quote
   rendered "from  — 1 earlier flow left out" with a blank date; the row
   now says nothing is covered and how many flows lie before the
   benchmark's first priced day, and the covered case says the earlier
   flows enter through the opening value (the risk-tier pass showed a flow
   dated *on* the rebase day was listed although it is invested at that
   day's close; only the flows before it are named now).
9. **Fixed (small):** a stored close of 0 divided by zero on the rebase day
   (it is not a price now; the previous positive close carries past it); a
   delivery accepted a negative price (refused like a trade's); the
   computation basis did not disclose the rebase rule, the float-derived
   daily factor, that a missing rate path makes a day unpriced, or that an
   excluded flow enters through the opening value (it does, and
   `window.rebase_day` is on the wire); the IRR solver returned a signed
   zero (`-0.000000`) for a rate of exactly 0 %; the picker's checkbox rows,
   rate field and Apply measured under 44 px on a coarse pointer (44 px
   now, measured live).
10. **Recorded, not changed:** the identity "benchmark = the single
    holding with the same flows" is exact when the base-currency price
    terminates; with a foreign-currency benchmark the valuation's
    `(qty × close) × rate` and the engine's `units × (close × rate)` can
    differ by one unit in the 34th significant digit — in the engine's
    moduledoc as a precision statement. A benchmark's memo key composes its
    own computation version, not the walk's; a future bump of the walk's
    version must bump the comparison's too (noted in the registry). Money
    figures on the wire are unrounded Decimals like the walk's own values
    (the page rounds). The UX-DR17 data-note treatment the Wealth
    data-quality list still owes is inherited, not new.
11. **Not exercised live:** the release image was not built in this session
    (no Docker daemon); the walkthrough ran against the development server.
    The API token and UI password used were generated for the session and
    never left the sandbox.
