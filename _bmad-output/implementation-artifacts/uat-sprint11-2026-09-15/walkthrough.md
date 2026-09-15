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

## Findings and what was done

(filled in after the four review roles reported — see below)
