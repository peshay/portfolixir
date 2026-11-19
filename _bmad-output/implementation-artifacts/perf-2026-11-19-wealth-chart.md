# The Wealth chart's first paint and period switch, measured (Sprint 30, M6)

- **Date:** 2026-11-19
- **Story:** M6 of the Sprint 30 plan, Lane M: I34's step 2 (Sprint 29 plan
  D-9). Measurement only; no code changed, nothing of the harness committed.
- **Baseline:** commit `7e7a1c7`, after I34's step 1 (Sprint 29, Lane P, P1):
  the stacked chart's bands read is its own analytic
  (`:performance_view_bands`, lifetime `:request`), memoised per fixed
  period and request.
- **What step 2 asks** (idea I34): warm the default period's bands with the
  existing warmup, and serve a memo hit without the "computing" flash. The
  numbers below are what the Sprint 31 plan decides with; this file decides
  nothing.

## What was measured

The Wealth page's Holdings tab (`PortfolixirWeb.PortfolioLive`, `/portfolio`)
on the review seed, the Everything scope (no view picked), base currency EUR.

- **First paint:** a fresh page load at a period and level, until the chart
  shows that period's data.
- **Period switch:** a click on a period token on an open page, until the
  chart shows the new period's data.
- Each **cold** (the derived memo emptied right before, as after a restart
  before any warmup, or after any write, which bumps the global basis every
  Wealth read is kept under) and **warm** (the same again at once, every read
  a memo hit).
- Per **period**, the five tokens the page offers (`Performance.periods/0`):
  `ytd`, `1y`, `3y`, `5y`, `max`.
- Per **level**, the five charts the bar above it draws:

| Level (this file) | Address | Chart | Reads behind the chart |
| --- | --- | --- | --- |
| Gesamt % | `/portfolio` (no level named: the arrival) | the TTWROR line, `#performance-figure` | `Performance.view_analysis/2` (the full walk, period-free) and `summarise/2` per period |
| Kategorien € | `?level=category` (the value series' default) | the stack, `#performance-figure-stack` | the above plus `Bands.for_view/2`, level `:category`, scale `:value` |
| Positionen € | `?level=security` | the stack | `Bands.for_view/2`, level `:security`, scale `:value` |
| Kategorien % | `?level=category&scale=ttwror` | the lines, `#performance-figure-lines` | `Bands.for_view/2`, level `:category`, scale `:ttwror` |
| Positionen % | `?level=security&scale=ttwror` | the lines | `Bands.for_view/2`, level `:security`, scale `:ttwror` |

"Gesamt €" (`?level=total`) reads exactly what "Gesamt %" reads and was not
measured separately. Under every chart, the contribution table
(`Contribution.for_view/2`, its own windowed walk per period) loads in
parallel; its time is reported beside the chart's, since it shows the same
"computing" skeleton.

Three clocks:

1. **Server** — from the connected LiveView's `mount` (first paint) or the
   `select_period` event (switch) to the first render of the page process in
   which the chart's data is assigned for the asked period: the performance
   summary not stale, and for a stacked level the bands landed for that
   period. LiveView's own telemetry, in the running server.
2. **Browser** — from the navigation's start (first paint) or the click
   (switch) to the first animation frame after the chart's SVG is in the
   DOM with no skeleton left and the asked period's token pressed. Chromium
   headless shell, CI's exact build (Playwright 1.65.0, revision 1254).
3. **Reads** — each read alone, timed with `:timer.tc/1` in a separate VM,
   cold and warm, to say which read the time goes to.

## Environment and load

- Dev configuration (`MIX_ENV=dev`, `mix phx.server`), Elixir 1.19.7 on
  OTP 27, PostgreSQL 16 on the same machine, 4 vCPUs (Xeon, 2.1 GHz),
  15 GiB RAM. The server's log level was raised to `:info` after boot (the
  dev default `:debug` logs every query, which a release does not). Dev
  assets are not minified, and the dev code reloader runs on every HTTP
  request (it logged a "Mix listener missing" warning on each); both weigh
  on the browser's first paint, not on the server's times or the switch.
- `PORTFOLIXIR_BACKGROUND_FETCH=off`: no outbound call, no background sync
  writing during the run. The boot warmup ran once at start; every cold
  measurement empties the memo after it.
- **The machine was shared.** Several other sessions ran test suites on
  the same 4 CPUs. The numbers below come from **run 3**, which started
  each repetition only once the 1-minute load average was below 5: every
  one of its 250 repetitions started at a load between 3.87 and 4.99
  (median 4.79), i.e. the 4 CPUs already about fully busy with other work.
  The run took 20:49–21:58 (most of it waiting for those windows; the load
  was 25–38 before). Treat every figure as an order of magnitude on a busy
  box, never as a budget.
- **Run 1** (20:14–20:27, the same harness without the gate) ran its
  first-paint rows for Gesamt, Kategorien € and Positionen € at a load of
  4.6–5.3 and agrees with run 3 there (within the spread); its later rows
  ran at a load of 15–45 and show what load does: a cold switch to 3 years
  at Kategorien € took a server median of 2,850 ms there against 963 ms in
  run 3, while the warm switch moved only from 70 to 85 ms. Cold times
  scale with load; warm times barely do.
- The reads harness (7 repetitions) ran 21:58–22:01 at a load of 5.2–8.9.

## The review seed

`priv/demo/finding_surfaces_seed.exs`, run once on an empty database, as its
header says. Synthetic throughout. What the walks see:

| Entity | Count |
| --- | --- |
| Portfolios | 5 |
| Depots / cash accounts | 10 / 20 |
| Securities | 50, of which 27 with quotes |
| Transactions | 96, 2023-01-02 to 2026-11-16 |
| Quotes | 958 (weekly), 2019-07-01 to 2026-11-19 |
| Exchange rates | 4 |
| Classifications / categories | 3 / 50 |
| Views | 2 (not picked: the Everything scope) |

`today` was 2026-11-19. The first booking is 2023-01-02, so the `5y` and
`max` windows are the same window on this seed (their payloads are the same
size below); `3y` starts 2023-11-19.

## How it was measured (to rerun)

The harness lives in a scratch directory (`<scratch>` below), not in the
repository.

1. **A database of its own, seeded.** In a checkout of the baseline:

   ```bash
   export DATABASE_NAME=portfolixir_perf PORT=4096 PORTFOLIXIR_BACKGROUND_FETCH=off
   mix ecto.create && mix ecto.migrate
   mix run priv/demo/finding_surfaces_seed.exs
   ```

2. **The server, with a node name** so a probe can be loaded into it:

   ```bash
   elixir --sname perfsrv --cookie perf -S mix phx.server
   ```

3. **The probe** (`<scratch>/probe.ex`), compiled into the running node over
   distributed Erlang from a second VM (`elixir --sname perfctl --cookie
   perf <scratch>/attach.exs <scratch>/probe.ex`, which also calls
   `Logger.configure(level: :info)` there). It attaches one handler to

   - `[:phoenix, :live_view, :mount, :start]` of the connected
     `PortfolioLive` mount,
   - `[:phoenix, :live_view, :handle_event, :start]` of `"select_period"`,
   - `[:phoenix, :live_view, :render, :stop]` of the page itself (metadata
     without a `:component` key),

   and records per event `System.monotonic_time(:microsecond)`, the page
   pid and, for a render, what the socket had assigned: `period`, the
   stack's `level` and `scale`, whether `performance`, `bands` and
   `contribution` were set, `performance_stale`, the period in `bands_for`,
   and the render's duration. It listens on `127.0.0.1:<port>` for three
   line commands: `reset` (calls `Portfolixir.Derived.Memo.reset/0` and drops
   the recorded events), `clear` (drops the events), `events` (returns them
   as JSON).

4. **The browser driver** (`<scratch>/driver.js`, Node 22, the Playwright
   that `test/browser/package.json` pins, `PLAYWRIGHT_CHROMIUM_EXECUTABLE`
   naming the headless shell). One browser context for the run, so assets
   are cached as for a returning operator; one throwaway load first. Every
   address names its period (`?period=…`), so the browser's period memory
   (#1432) never redirects a load. An init script installs a
   `MutationObserver` before the page's own scripts; it marks the moment the
   chart's selector (`#performance-figure svg`, `#performance-figure-stack
   svg` or `#performance-figure-lines svg`) is present, neither
   `[data-role=stack-skeleton]` nor `[data-role=performance-skeleton]` is,
   and `[data-role=period-tokens] button[aria-pressed=true]` is the asked
   period; then the next `requestAnimationFrame`. It also marks
   `.phx-connected` and the contribution table's skeleton leaving, and the
   driver counts the websocket bytes received.

   - First paint, per level, period and repetition: `reset`, load the page
     (cold); `clear`, load it again (warm).
   - Switch, per level, period P and repetition: open the page at a base
     period B (`1y`, or `ytd` when P is `1y`) and wait for its chart;
     `reset`; click P (cold); click B; click P again (warm). The click is
     dispatched from inside the page right after taking the start time.
   - Five repetitions each: 250 first-paint and 250 switch measurements.
     `LOAD_MAX=5` holds each repetition until the 1-minute load average is
     below 5 (with a wait budget for the whole run).

   ```bash
   PW_MODULE=test/browser/node_modules/playwright \
   PLAYWRIGHT_CHROMIUM_EXECUTABLE=<headless shell> LOAD_MAX=5 WAIT_BUDGET_MIN=60 \
     node <scratch>/driver.js http://127.0.0.1:4096 <port> 5 run.json
   ```

5. **The reads** (`<scratch>/reads.exs`), in a VM of its own on the same
   database: `mix run <scratch>/reads.exs 7`. Per fixed period and request:
   `Memo.reset/0`, then the read under `:timer.tc/1` (cold), then the same
   read again (warm), seven times each; the windowed walk
   (`Performance.view_contribution_analysis/4`, with and without
   `bands: true`) timed alone; the payload's size as
   `:erts_debug.flat_size/1` words × 8 bytes; and `Memo.usage/0` once every
   period and request is warm.

All figures are **median (min–max) in milliseconds** over the repetitions.

## The numbers

### First paint (run 3, 5 repetitions per cell)

"Table" is the contribution table under the chart (server clock); "renders"
is the page's own render time summed from the mount to the chart's render,
warm; "ws" the websocket bytes received for the load, warm.

| Level | Period | browser cold | browser warm | server cold | server warm | table cold | table warm | renders warm | ws KiB |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Gesamt % | ytd | 479 (446–664) | 524 (406–567) | 149 (93–247) | 120 (84–137) | 379 (317–469) | 62 (39–124) | 40 | 128 |
| Gesamt % | 1y | 625 (458–757) | 473 (434–649) | 166 (102–229) | 88 (77–141) | 436 (423–576) | 59 (34–145) | 32 | 133 |
| Gesamt % | 3y | 615 (474–805) | 515 (486–751) | 176 (141–203) | 100 (82–117) | 644 (592–724) | 47 (39–101) | 32 | 132 |
| Gesamt % | 5y | 516 (481–629) | 519 (475–610) | 157 (109–321) | 116 (89–164) | 635 (471–743) | 47 (38–69) | 34 | 132 |
| Gesamt % | max | 502 (443–598) | 493 (417–603) | 129 (105–163) | 108 (99–117) | 560 (523–645) | 41 (34–53) | 32 | 132 |
| Kategorien € | ytd | 926 (871–1103) | 551 (392–579) | 658 (586–759) | 141 (79–160) | 466 (333–510) | 82 (37–102) | 31 | 147 |
| Kategorien € | 1y | 941 (854–1081) | 498 (484–537) | 657 (612–738) | 98 (85–206) | 427 (414–536) | 39 (33–133) | 25 | 153 |
| Kategorien € | 3y | 1301 (1126–1570) | 545 (345–587) | 1101 (945–1291) | 124 (94–165) | 572 (551–747) | 66 (50–80) | 32 | 155 |
| Kategorien € | 5y | 1387 (1312–1413) | 470 (391–517) | 1120 (1099–1158) | 120 (98–158) | 644 (599–730) | 54 (32–106) | 30 | 154 |
| Kategorien € | max | 1474 (1262–1844) | 602 (420–804) | 1213 (1085–1390) | 139 (83–220) | 636 (595–751) | 57 (39–128) | 24 | 154 |
| Positionen € | ytd | 1070 (966–1253) | 642 (439–694) | 640 (594–866) | 94 (89–167) | 503 (429–693) | 57 (50–109) | 33 | 175 |
| Positionen € | 1y | 1205 (987–1436) | 528 (502–645) | 903 (767–1013) | 117 (105–180) | 624 (552–758) | 72 (41–121) | 42 | 186 |
| Positionen € | 3y | 1622 (1530–1763) | 631 (545–688) | 1287 (1200–1527) | 154 (118–161) | 823 (737–1004) | 93 (43–166) | 60 | 187 |
| Positionen € | 5y | 1662 (1631–1859) | 591 (590–672) | 1405 (1258–1436) | 167 (105–213) | 819 (753–850) | 56 (42–80) | 66 | 185 |
| Positionen € | max | 1657 (1577–1777) | 649 (456–822) | 1336 (1239–1427) | 152 (109–254) | 790 (751–815) | 69 (47–111) | 42 | 185 |
| Kategorien % | ytd | 828 (787–904) | 450 (399–466) | 604 (492–622) | 101 (64–116) | 375 (281–427) | 38 (32–58) | 24 | 140 |
| Kategorien % | 1y | 1112 (868–1382) | 541 (366–599) | 802 (615–873) | 105 (93–141) | 568 (458–592) | 46 (32–108) | 27 | 145 |
| Kategorien % | 3y | 1461 (1310–1611) | 521 (473–639) | 1180 (1054–1234) | 171 (136–184) | 605 (551–770) | 70 (44–94) | 44 | 145 |
| Kategorien % | 5y | 1807 (1364–1908) | 693 (544–795) | 1414 (1086–1567) | 187 (154–254) | 809 (545–883) | 59 (34–138) | 94 | 144 |
| Kategorien % | max | 1583 (1473–1879) | 603 (477–714) | 1302 (1194–1564) | 158 (115–216) | 752 (553–935) | 66 (36–137) | 45 | 144 |
| Positionen % | ytd | 931 (877–1105) | 527 (483–721) | 653 (589–787) | 85 (66–87) | 469 (394–487) | 55 (35–88) | 25 | 186 |
| Positionen % | 1y | 788 (737–995) | 427 (356–681) | 538 (501–640) | 96 (80–129) | 407 (319–520) | 43 (37–59) | 33 | 197 |
| Positionen % | 3y | 1131 (1039–1187) | 435 (410–485) | 902 (768–928) | 127 (119–155) | 566 (513–678) | 46 (42–58) | 51 | 179 |
| Positionen % | 5y | 1185 (1175–1370) | 429 (381–561) | 983 (951–1117) | 133 (114–219) | 660 (570–701) | 57 (42–225) | 52 | 171 |
| Positionen % | max | 1217 (1209–1302) | 462 (410–616) | 957 (927–1016) | 134 (107–138) | 583 (573–683) | 111 (40–143) | 46 | 172 |

The LiveView connected after a median of **381 ms** from the navigation's
start (213–691, n = 250): the dead render, the scripts and the socket's
join, before the server's clock starts. Browser first paint ≈ that plus the
server's time plus the patch.

### Period switch (run 3, 5 repetitions per cell)

"ws" is the websocket bytes the warm switch received.

| Level | Period (from) | browser cold | browser warm | server cold | server warm | table cold | table warm | renders warm | ws KiB |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Gesamt % | ytd (1y) | 170 (98–189) | 172 (100–197) | 35 (29–40) | 31 (26–45) | 271 (221–322) | 37 (29–52) | 22 | 51 |
| Gesamt % | 1y (ytd) | 142 (110–167) | 137 (91–164) | 40 (29–58) | 45 (30–50) | 339 (285–346) | 49 (35–78) | 29 | 55 |
| Gesamt % | 3y (1y) | 151 (137–211) | 149 (137–242) | 81 (48–148) | 70 (50–94) | 556 (492–767) | 79 (53–104) | 45 | 55 |
| Gesamt % | 5y (1y) | 223 (160–250) | 159 (136–174) | 55 (46–77) | 53 (47–93) | 520 (464–554) | 57 (51–96) | 28 | 54 |
| Gesamt % | max (1y) | 182 (178–209) | 183 (158–201) | 61 (48–74) | 68 (52–115) | 542 (530–615) | 84 (56–127) | 28 | 54 |
| Kategorien € | ytd (1y) | 600 (443–630) | 211 (133–233) | 561 (417–595) | 38 (29–49) | 359 (287–380) | 19 (13–24) | 22 | 72 |
| Kategorien € | 1y (ytd) | 568 (544–688) | 233 (184–266) | 538 (508–646) | 44 (40–50) | 297 (281–384) | 18 (15–21) | 27 | 78 |
| Kategorien € | 3y (1y) | 991 (886–1137) | 231 (218–254) | 963 (857–1095) | 70 (56–101) | 565 (473–640) | 34 (25–65) | 27 | 79 |
| Kategorien € | 5y (1y) | 966 (879–1085) | 204 (151–210) | 939 (851–1054) | 58 (50–72) | 485 (455–520) | 26 (25–27) | 22 | 78 |
| Kategorien € | max (1y) | 976 (925–1011) | 236 (207–246) | 948 (897–983) | 64 (55–75) | 507 (489–518) | 30 (26–37) | 29 | 78 |
| Positionen € | ytd (1y) | 572 (488–614) | 207 (102–212) | 537 (459–555) | 45 (37–50) | 312 (243–352) | 27 (13–51) | 29 | 101 |
| Positionen € | 1y (ytd) | 579 (549–658) | 209 (101–223) | 547 (508–614) | 47 (35–56) | 362 (329–418) | 35 (15–53) | 29 | 111 |
| Positionen € | 3y (1y) | 1020 (906–1116) | 218 (198–234) | 987 (864–1084) | 85 (78–104) | 484 (441–572) | 32 (27–90) | 49 | 111 |
| Positionen € | 5y (1y) | 1047 (1025–1101) | 220 (207–235) | 1013 (995–1067) | 78 (69–83) | 519 (497–581) | 37 (25–97) | 37 | 109 |
| Positionen € | max (1y) | 1047 (1000–1179) | 222 (196–251) | 1017 (970–1133) | 86 (76–128) | 547 (499–552) | 32 (27–45) | 45 | 109 |
| Kategorien % | ytd (1y) | 451 (419–505) | 112 (81–181) | 423 (392–476) | 25 (24–29) | 238 (236–287) | 11 (11–14) | 16 | 64 |
| Kategorien % | 1y (ytd) | 479 (476–512) | 112 (73–197) | 450 (448–486) | 30 (26–46) | 264 (250–306) | 12 (11–18) | 18 | 69 |
| Kategorien % | 3y (1y) | 920 (861–994) | 215 (179–228) | 894 (834–967) | 54 (49–57) | 449 (435–460) | 24 (22–28) | 31 | 70 |
| Kategorien % | 5y (1y) | 1060 (997–1101) | 241 (232–277) | 1030 (968–1055) | 71 (66–112) | 504 (471–569) | 30 (24–38) | 44 | 68 |
| Kategorien % | max (1y) | 1068 (1063–1171) | 238 (150–253) | 1034 (1028–1140) | 72 (62–189) | 551 (515–603) | 30 (23–52) | 42 | 68 |
| Positionen % | ytd (1y) | 487 (463–636) | 112 (73–221) | 444 (424–596) | 45 (29–69) | 307 (242–440) | 35 (16–63) | 30 | 112 |
| Positionen % | 1y (ytd) | 557 (516–579) | 185 (81–213) | 514 (470–530) | 34 (31–52) | 332 (276–373) | 16 (12–37) | 25 | 123 |
| Positionen % | 3y (1y) | 813 (779–983) | 204 (83–287) | 781 (746–944) | 77 (59–104) | 477 (436–567) | 30 (23–111) | 43 | 105 |
| Positionen % | 5y (1y) | 893 (818–990) | 219 (200–221) | 847 (779–953) | 73 (64–102) | 493 (476–547) | 30 (27–39) | 52 | 97 |
| Positionen % | max (1y) | 832 (796–889) | 197 (192–229) | 804 (767–846) | 70 (64–92) | 482 (456–515) | 26 (23–31) | 50 | 97 |

At "Gesamt %" the chart re-chains the analysis the page holds
(`summarise/2`, in the event handler), so cold and warm are the same; only
the table under it waits for a walk.

### The reads alone (7 repetitions each, ms)

| Read | ytd | 1y | 3y | 5y | max |
| --- | ---: | ---: | ---: | ---: | ---: |
| `view_analysis` (full walk), cold | 16 (11–26), period-free | | | | |
| `view_analysis`, warm | 1.1 (0.8–4.7), period-free | | | | |
| `summarise/2` (in the page process) | 5.6 | 7.4 | 17.0 | 20.7 | 17.6 |
| Contribution table, cold | 227 | 252 | 414 | 441 | 452 |
| Contribution table, warm | 0.3 | 0.2 | 0.3 | 0.2 | 0.2 |
| Windowed walk alone (no bands) | 210 | 228 | 417 | 443 | 393 |
| Windowed walk alone, `bands: true` | 277 | 337 | 572 | 630 | 640 |
| Bands Kategorien €, cold | 396 | 419 | 790 | 974 | 884 |
| Bands Positionen €, cold | 360 | 419 | 830 | 966 | 989 |
| Bands Kategorien %, cold | 415 | 442 | 1011 | 1028 | 944 |
| Bands Positionen %, cold | 372 | 372 | 667 | 768 | 841 |
| Bands Kategorien € / %, warm | 4.3 / 2.8 | 3.1 / 2.9 | 3.0 / 2.9 | 2.9 / 3.2 | 7.8 / 2.6 |
| Bands Positionen € / %, warm | 0.6 / 0.3 | 0.5 / 0.3 | 0.9 / 0.9 | 1.4 / 0.8 | 1.2 / 0.6 |
| Band colours' allocation read (mount only) | 22 (15–86), period-free | | | | |

The spreads of the cold bands reads ran to about +55 % of the median in the
worst cells (3y Kategorien €: 790, 752–1192; 5y Positionen €: 966,
790–1491). A warm "Kategorien" hit costs
3–8 ms where a "Positionen" hit costs under 1.5: the default
classification is resolved (the active plans' targets, read across every
portfolio) before the memo is asked.

**Payload and memo footprint** (`flat_size` × 8; the memo keeps the
value as it is):

| Entry | ytd | 1y | 3y | 5y | max |
| --- | ---: | ---: | ---: | ---: | ---: |
| Bands Kategorien € (5 bands) | 564 KiB | 638 KiB | 1.9 MiB | 2.4 MiB | 2.4 MiB |
| Bands Positionen € (8 bands) | 929 KiB | 1.0 MiB | 3.0 MiB | 3.9 MiB | 3.9 MiB |
| Bands Kategorien % (3 lines) | 217 KiB | 245 KiB | 678 KiB | 860 KiB | 860 KiB |
| Bands Positionen % (8 lines) | 408 KiB | 461 KiB | 1.1 MiB | 1.3 MiB | 1.3 MiB |
| Contribution table | 42 KiB | 42 KiB | 43 KiB | 43 KiB | 43 KiB |

With the analysis, the five contribution tables and all twenty bands entries
of this one scope warm (26 entries), `Memo.usage/0` read **29 MiB**
(30,349,576 bytes) of the memo's 128 MiB budget (5,000 entries).

## What dominates

- **Cold, at a stacked level: the bands read.** The server's cold first
  paint and cold switch follow the bands read's own cost almost one to one
  (switch to 3y at Kategorien €: 963 ms on the server, the read alone
  790 ms). The read is the windowed walk with `bands: true` (277–640 ms)
  plus building the bands from it (about 80–440 ms more). The contribution
  table walks the same window again in parallel, without the bands
  (210–443 ms), and on 4 busy CPUs the two compete. The full walk the badge
  and the Gesamt line use costs 11–26 ms; the windowed walks cost about 13 to
  40 times that.
- **Cold, at Gesamt: nothing on the chart.** The line re-chains the held
  analysis in 6–21 ms; the chart's first paint is the mount and the full
  walk (server 129–176 ms cold). What still waits is the contribution table
  under it: 380–640 ms cold on first paint, 270–560 ms on a switch.
- **The longer windows cost twice the short ones.** `3y`, `5y` and `max`
  read 1.8–2.5× what `ytd` read, cold; on this seed `5y` and `max`
  are one window.
- **Warm, the reads are not the cost.** A hit is 0.2–8 ms. A warm switch
  still takes 25–86 ms on the server and 110–240 ms in the browser: the
  async round trip (`CappedAsync.start_latest/3`, a task, `handle_async`),
  the page's renders (16–52 ms summed), and the diff on the wire (64–123 KiB
  at a stacked level). The page clears the bands (and the table) to `nil`
  before the read even on a hit, so every warm switch renders and sends the
  skeleton first and the chart second.
- **Warm first paint: the connect.** 381 ms of a warm browser first paint of
  430–690 ms pass before the LiveView is connected; the server then needs
  85–190 ms, most of it the mount's other reads and renders (the overview's
  valuation and allocation run beside the chart's reads, and the band
  colours read the allocation once more at mount because the page does not
  hold it yet), not the chart's memo hits.

## What step 2 could target (numbers only)

1. **Warming the default period's bands.** The boot and midnight warmup
   (and the refresher after a write) warms the full walks only
   (`Performance.analysis/2` per portfolio, `view_analysis/2`); no
   contribution table and no bands. The arrival (`/portfolio`, Gesamt %,
   1 year) reads no bands at all but reads the 1-year table cold: 436 ms
   cold against 59 ms warm on the server. The value series' default
   (Kategorien €, 1 year) paints in 657 ms cold against 98 ms warm on the
   server (941 against 498 ms in the browser). Warming both entries costs
   about 0.7 s of CPU per scope (bands Kategorien € 1y 419 ms, table 1y
   252 ms) and about 0.7 MiB of memo; every write bumps the global basis
   all of them are kept under, so a warm-after-write pays that per write.
2. **Serving a hit without the "computing" flash.** A warm switch's read is
   under 10 ms of a server time of 25–86 ms and a browser time of
   110–240 ms; the rest is the round trip and the second render and diff the
   skeleton forces. What a synchronous hit would save is not measured here
   (it needs the change); the ceiling is that round trip.
3. **The memo budget.** One scope's every period and request warm is 29 MiB
   of 128 MiB; a bands entry is 0.2–3.9 MiB, largest at Positionen € over
   the long windows. Each further view, sort, category filter or
   classification adds its own entries, so about four scopes warmed this
   fully reach the budget on this seed; a larger ledger's entries grow with
   the window's days and the bands' count.
4. **Not step 2, but in the numbers:** the cold cost is the windowed walk
   run twice per period (once for the table, once with bands), each
   about 13–40 times the full walk.

## Not measured

- A release build (minified assets, no code reloader, `:info` logging by
  default): the browser's connect time would differ; the server's would
  hardly.
- A view picked, a category filter, a classification other than the
  default, the `change` sort, a custom range or calendar year (computed on
  every read, never memoised).
- A ledger larger than the review seed; ADR-0039's
  `mix portfolixir.derived.measure` seeds one for the analysis reads, not
  for the bands.
- The time a synchronous memo hit would take (it needs the code step 2
  would write).
