# Sprint 29 — the crash rankings, the news layer's first-fill fixes, the Research tab's owed view, the layout gate, the Bitcoin cycles

**Status: ADOPTED by the merge of the Sprint 29 planning PR.**
The merge is the signature (ADR-0026 step 1, as amended on 2026-10-08). It
signs [ADR-0056's amendment of 2026-11-12](../../docs/decisions/0056-news-layer-fetched-matched-stored-labelled-outside.md#amendment-of-2026-11-12-what-the-first-fill-found)
(E1, a rating re-rates the stored items it covers, #1444; E2, an entry's
link holds 2,048 characters, #1443),
[ADR-0058's amendment of 2026-11-12](../../docs/decisions/0058-crash-windows-detected-by-rule-ranked-by-price.md#amendment-of-2026-11-12-what-drawing-the-screen-found)
(F1 to F5, what drawing the Crashes screen found), the two records idea
I12 needs (ADR-0059, the chain source, with ADR-0048's amendment of
2026-11-12, the event kind `halving`; ADR-0060, the cycles read and the
projection's ladder entry, with the `AGENTS.md` ladder item it adds,
D-11; **built in this sprint's third PR**, D-2), the seven planning boards in
`design-language/mockups/ux-design-2026-11-12-sprint29/` and the decisions
below. A fresh implementation session builds the sprint on the branch its
environment assigns, or `agent/<provider>/sprint-29`, as **three stacked
sprint PRs** (D-10), under the stacking rule of the rule PR #1448. The severity rule of ADR-0026's amendment of 2026-11-01 applies
unchanged.

## What you need to do

1. **Merge, to adopt the plan.** Nothing in it books or corrects a stored
   money figure. Three things change what you expected:
   - **I12, the Bitcoin cycles, is built in this sprint as its third
     stacked PR** (D-2), as you decided on 2026-11-12. Its two records are
     on this PR, so your merge signs them. ADR-0059 **opens gate B3.3 for
     one more source**, the
     Bitcoin chain's block heights and times, as ADR-0056 opened it for
     news feeds; ADR-0060 **adds one item to the scope ladder in
     `AGENTS.md`** (an analog band, never a single date or price, D-11).
     Both are scope decisions only you can sign. ADR-0060 lists its
     judgement calls with their flips (the 20 % fall that anchors the
     current top, the next halving as a window with the ten-minute target
     as its slow end, Bitcoin Cash and Litecoin registered without a
     source, a node on your home network deferred). Board 07 draws the
     states the two records add.
   - **Sprint 29 is three stacked PRs, and the layout gate (#1435) stays
     in it** (D-3, D-10), as you decided on 2026-11-12: PR 1 carries Lanes
     M, N, B and C, PR 2 Lanes D, P and L, PR 3 Lane H (I12). **It is the
     largest sprint the project has run** (about 140 commits, three
     risk-tier groups); D-10 says what keeps it reviewable. **Merge the rule PR #1448
     first**: its standing grant lets the implementation session push the
     second PR's branch, and a fresh session reads it only from `main`.
   - **ADR-0056 E1 re-rates stored news items when a domain's rating
     changes**, the answer you adopted on 2026-11-10; one precision is
     the plan's: a seed write that changes a default re-rates too (a seed
     never overwrites your hand rating). "news retier hand only" drops
     that half.
2. **Look at board 01**, the Crashes section on the Risk tab (ADR-0058 §9
   asks for it on this PR), and **board 02**, the benchmark picker. D-5
   lists each proposal with the phrase that flips it; silence adopts the
   recommendation. Drawing board 01 found five gaps in ADR-0058, decided
   in its amendment (F1 to F5): the most visible is F2, a manual window
   without a crash benchmark is ranked without a market line.
3. **The I9 table** (`_bmad-output/planning-artifacts/rule-review-2026-11-12.md`)
   is answered: your directions of 2026-11-12 are the rule PR #1448, to
   merge before this sprint is built (D-10).
4. **Optional, still open from earlier plans:**
   - ADR-0056 D10 (which prompt version the reads follow): the plan
     recommends **(a) a configured active prompt version** before you run
     a second labeller; until then, one labeller at a time is safe.
     Silence keeps it open and builds nothing.
   - **Branch protection:** the API answers that `main` requires **no**
     status check at all (`required_status_checks.contexts` and `.checks`
     both empty; read on 2026-11-12). Earlier plans asked for the
     `browser` job to be added; if the empty answer is true, none of the
     jobs is required. Settings → Branches shows which.
   - Dependabot's #1392 (`floki` 0.38.5) is still open; Sprint 28's M1
     took the bump, so it can be closed.

**Not asked:** everything else. **Not raised:** I31 (live prices, waiting
for your read of the source's terms), I35 (tidying the app, its inventory
first), I38 to I41 (audits and process, each a lane a plan schedules with
its budget), I42 to I44 (triaged, each needs a board).

**Verification basis:**

- **Sprint 28's merge, as its close-out asked this plan to record:** the
  sprint PR #1436 was merged at 06:37 UTC on 2026-11-10; CI run 1976 green
  on `7d53be4`; release **2026.11.13**. Its keywords closed #1410, #1411,
  #1415, #1420, #1424, #1425, #1426, #1427, #1428, #1429, #1432, #1433 and
  #1438.
- **Since then on `main`:** the idea list's triage of I33 to I41 and I34's
  cause (docs only; CI run 1979 green on `4d0a518`); #1445 (#1442, the
  feed parser reads ISO-8859-1, US-ASCII and a UTF-8 BOM, with the first
  fill's triage; CI run 1982 green on `4a15b9a`, release **2026.11.14**);
  #1446 (I12 worked out, I42 recorded; docs only; CI run 1984 green on
  `e014f28`); then on 2026-11-12 a stack-bar fix (`e228b64`, `bbe7f55`:
  the level control starts at the bar's left edge at every level), I43 and
  I44 recorded, and `9114ffb`, the level-switch walk waiting for its loads
  after CI's browser job failed on the same mid-load exit as Sprint 28's
  twice; CI run 1987 green on `9114ffb`, release **2026.11.15**. `main` is
  at `9114ffb`.
- **The open-issue list of 2026-11-12:** 35 open: 15 `agentic` (#1444,
  #1443, #1440, #1439, #1435, #1421, #1417, #1416, #1414, #1413, #1396,
  #1070, #900, #899, and #1220 with `needs-decision`), 1 `needs-decision`
  (#1177), 2 `needs-uat` (#328, #354), 17 trackers (11 polish lists #1355
  to #1366 without #1364; #991; the five area trackers #416 to #420).
  One Dependabot PR is open: #1392.
- **Read against the code on `9114ffb`**, each claim this plan rests on:
  - `News.Sources.put_source/4` writes the row under its lock (#1424) and
    journals it; nothing touches `news_items`. `Ingest.tier_and_block/2`
    stores each item with `Sources.tier(class, rated)` at ingest.
    `Promotion` caps an entry's link at `@source_url_max 255` and derives
    `source_quality` from the stored members' tiers. `source_url` on
    `security_notes` and `security_events` is `:string` (255). Retention
    removes items through `Stories.remove/5`. Hence Lane N's N1 and N2.
  - The Research tab draws `.research-timeline` entries; the four columns
    D6 added (`headline`, `event_type`, `tone`, `news_label_id`) are
    written and drawn as chart pins, and the tab shows none of them.
    Hence N3.
  - `BenchmarkParam` accepts `security:<id>` only for a security with
    `is_benchmark: true` (`benchmark_param.ex` 73, 81), and so does
    `Predictions` (145). Hence Lane B, which ADR-0058 §1 builds on.
  - `Portfolios.Performance.WindowReturn` exists (sale hindsight and the
    prediction resolution share it). `Portfolixir.Settings` is a keyed
    store with one public helper per key and actor; there is no crash
    setting. Wealth's Risk tab is the page `/risk` (`wealth_tabs/1` in
    `app_shell.ex`). Hence Lane C.
  - `Bands.for_portfolio/2` and `for_view/2` call
    `Performance.contribution_analysis/3` and
    `view_contribution_analysis/3` directly (`bands.ex` 167, 201), not
    through `Derived`, so no bands answer is memoised (I34's cause,
    confirmed). `.stack-band` fills opaque (`app.css` 6552). Hence Lane P.
  - `DataQuality.list_opts("implausible_quote")` narrows to
    `holding_status: :held` (`data_quality.ex` 166). `tools.ts` has no
    logo tool. Hence Lane D.
  - The browser walks: `period_memory.js`, `privacy_leak.js`,
    `privacy_leak_settle.js`, `closing_act_layout.js` and
    `info_tips_click_away.js` each wait for busy markers their own way;
    the other walks do not, and nothing asserts that a walk does. Hence M2.
- **The rule PR #1448** (opened 2026-11-12 from this session, your
  answers to the rule review): the stacking rule and the standing push
  grant D-10 builds on.
- **Boards:** seven, drawn for this PR (D-5, D-6), on the shipped `app.css`,
  every series and name synthetic.

## State of play, in five lines

1. **Sprint 28 is on `main`** (release 2026.11.13): the quote sync's
   gaps, the news layer's second half with its screens, the version, the
   stacked chart's filter and TTWROR lines.
2. **The news layer met real feeds** on 2026-11-10: the parser's half is
   fixed (#1445); two record-level gaps remain, one bordering an S1
   (#1444: an entry can claim a better source than your table now allows).
3. **One view is owed** by the end of this sprint: the Research tab shows
   no headline, event type or tone (Sprint 28's close-out finding).
4. **I24's record is signed** and its screen boarded here; **I12 is worked
   out** and its records are written here.
5. **CI's browser job failed a third time on 2026-11-12** for Sprint 28's
   cause, in a walk that had not taken the rule.

## Why this cut

- **#1444 first.** It is an S2 bordering an S1 in a log that is never
  rewritten: every promotion from a downgraded domain writes a lasting
  wrong `source_quality`. Its record is signed here, so it builds first.
- **The owed view, because it is due.** The coverage rule makes the
  Research tab's gap a close-out finding after this sprint.
- **I24, because it was promised and is ready.** ADR-0058 was signed by
  Sprint 28's planning merge for this sprint; #1416 (any security as a
  benchmark) is its prerequisite (§1) and rides in front of it.
- **The data-quality pair, because you answered it on 2026-11-07** and it
  is small: #1414 widens a set, #1417 changes the Overview's count; #1413
  closes an agent flow that cannot be completed (S2).
- **I34's first step and I33, because they are no-brainers** you raised:
  every period switch recomputes the stack; the bands are opaque.
- **M2, because the cause failed CI three times** after it was found.
- **The layout gate (#1435), because the rule it enforces broke again** on
  2026-11-12 (`bbe7f55`) and its inventory is drawn: five of ten labelled
  bars break the shared edge today.
- **I12, because you asked for it in this sprint** (D-2), as its own PR,
  so the new outbound caller gets a closing act of its own.
- **What is left out, and why** (each flips by naming it): ADR-0056 D10 (your answer,
  above); #1396, #899, #900, #1070, #1220, #1177, #328, #354 keep their
  standing reasons (D-12); the polish lists other than the lines the
  touched files reach.

## Lanes (three stacked sprint PRs, in this order: M, N, B, C in PR 1; D, P, L in PR 2; H in PR 3)

**Lane M, maintenance (first).**

| Story | Source | What it does | Commits |
|---|---|---|---|
| M1 | standing rule | the version report `version-report-2026-11-…-sprint29.md`: Hex, npm, Elixir/OTP, PostgreSQL, BMAD core and the external modules, each bump its own commit, what is declined with its reason | 1–2 |
| M2 | Sprint 28 retrospective, carry-forward 1 | **one settle helper** in `test/browser/` (waits until no busy marker is left and no load is in flight, generalising `privacy_leak_settle.js`), used by every walk before it leaves a page; **a test asserts that every walk script uses it** (a walk that navigates without it fails the test, an exception registered with its reason). A red run of the assertion against today's walks seen first | 1 |
| M3 | #1440 (S2, flaky) | the heap-cap tests keep their cap local to the task they test, or wait for every capped task before the capture closes; a red full run under `--max-cases` load seen first. **No allowance widened** | 1 |
| M4 | #1439 (S2) | the theme boot script (`layout_view.ex` and `priv/static/theme-boot.js`) and the theme control wrap every storage access in `try/catch`; a browser test whose context throws on `localStorage` shows the page connected in the system theme. No rendered difference (D-6) | 1 |

**Lane N, the news layer's first-fill fixes and the owed view** (#1444,
#1443; ADR-0056 E1, E2; the coverage finding). **Risk tier: stored data**
(a tier that becomes a lasting `source_quality`): N1 and N2 their own
commit group, a dedicated verification pass, a callout in the briefing.

| Story | Source | What it does | Board | Commits |
|---|---|---|---|---|
| N1 | #1444, E1 | **a rating re-rates what it covers.** A write that changes a row's tier re-rates, in its transaction, the unpromoted items it now decides (longest suffix, B5's caps), removes a newly blocked domain's unpromoted items through `Stories.remove/5`, chooses each touched story's representative again by C2, leaves promoted items alone, and journals the three counts. Tests first: a downgrade, an upgrade, a block, a more specific row elsewhere, a promoted member, a seed write onto a hand row (no-op); **two order tests**: a fetch interleaved with a rating (no item stored with the old tier after the rating committed) and a promotion racing a rating (whichever commits first wins, as E1 states) | — | 3 |
| N2 | #1443, E2 | `source_url` on `security_notes` and `security_events` to 2,048 characters: one migration, no row rewritten, the changesets, D6's two 422s, the companion's descriptions. A story whose every link is 300 characters is promoted, seen failing first; a 2,049-character link still refused | — | 1 |
| N3 | Sprint 28 close-out; board 03 A | **the Research tab shows what the agent reads:** the headline as the entry's first line behind the pin's glyph, „Ereignisart · Tonalität“ in words under it (the pin's tooltip, the same two lines), „maschinell“ only where `news_label_id` is set (`machine_generated` stays reserved for a local model, ADR-0044), a superseded entry saying it is not on the chart; the link's domain opening the link (never the link in full, E2); an older entry without them unchanged. `DESIGN.md` gains the anatomy. The privacy mode keeps them (no amount) | 03 | 2 |
| N4 | the second gap board 03 found | **the research form takes them too:** the note form (`securities_live.ex`, the Research tab's form) gains an optional headline (≤ 80, ADR-0054 §4), event type and tone on `evidence` and `event_result` entries, the same validation as `notes.append`; today the operator can set them only by promoting a story, while an agent can write them on any entry. **Boarded first** as a frame added to board 03 before the story starts (D-8 item 3) | 03 (frame added) | 2 |

**Lane B, any security as a benchmark** (#1416; ADR-0046's amendment of
2026-11-07; board 02). Lane C builds on it.

| Story | Source | What it does | Board | Commits |
|---|---|---|---|---|
| B1 | #1416 | every read that takes `benchmark=security:<id>` accepts any security with at least one stored quote, flagged or not (a merged-away one answers 422 naming `merged_into`, as today); comparisons, sale hindsight and predictions take it the same way; the basis names whether the benchmark is flagged; the MCP descriptions that say "flagged `is_benchmark`" change with it. `is_benchmark` keeps its meaning. Tests first, a held fund as the benchmark of each read | — | 2 |
| B2 | #1416, board 02, ADR-0058 F5 | the two screen pickers as board 02 draws them (Holdings' „Benchmark…“, „Nach dem Verkauf“'s select), and **their resolvers** (`resolve_benchmark_security/1` in `portfolio_live.ex`, the section's lookup in `sale_hindsight_section.ex`) taking B1's rule, so a held security picked is never dropped to "not selected"; a test per picker, seen failing first | 02 | 2 |

**Lane C, the crash rankings** (FR-54, #1421; ADR-0058 in full; board 01).
**Risk tier: money math** (returns every list ranks): its own commit
group, the money lens, a callout in the briefing. Exact `Decimal`
expectations, each seen failing first.

| Story | Source | What it does | Board | Commits |
|---|---|---|---|---|
| C1 | §1 | `crash_benchmark_security_id`: one `Settings` helper with the actor, journaled; any security with a stored quote (Lane B's rule), a merged-away one refused; `PUT /api/v1/settings/crash_benchmark` and its tool; unset, the read answers `detected: []`, `reason: "no_crash_benchmark"` | — | 1 |
| C2 | §2, §7 | **the rule** `peak_trough_v1`, derived at read: the latest of equal peaks, the earliest of equal lows, `≥ 0.10` compared exactly, one window per fall, an ongoing window `provisional`, `max_gap_days` in the basis, the key `d:<benchmark>:<start>`. **Every case of §7 pinned:** a read in another order, exactly 10.00 % and 9.99 %, a split inside a fall, a gap over the fall, a fall in two legs without a recovery, a series ending inside a fall | — | 2 |
| C3 | §3, §4, F1 | names keyed per benchmark and start, `unmatched_names` when a key loses its window (never re-attached by a guess), a benchmark switch hiding and restoring names; manual windows (name ≤ 80 under ADR-0054 §4, `start` before `trough`, neither in the future; a name without a window becomes one only with a trough the caller gives, F1), overlapping allowed, `kind: manual` on every read; create, rename, delete, journaled; an unknown field 422 naming it | — | 2 |
| C4 | §5, §6, F2, F3 | **the lists** over `catalogue` or `view:<id>`: losers and winners by `WindowReturn.price_return/3` from `start` to `trough` with the benchmark's return and the difference in points; rebounders from each security's own low to `trough` + 3 calendar months (month-end rule), `days_back` in calendar days (F3) or `not_yet`, `provisional` with its completion date; ties by figure, name, ISIN; no answer counted per reason, never a zero; survivorship in the basis; with no crash benchmark, a manual window's lists carry no reference and say why (F2). **A crash return and a sale-hindsight return over the same dates agree to the last digit**, pinned | — | 3 |
| C5 | §9 | `GET /api/v1/crashes`, `GET …/:key/rankings`, `PUT`, `POST`, `DELETE`; the five `portfolixir.crashes.*` tools, each saying it returns data; the contract entry 29 part C; the schema budget grows by the five tools' own bytes only. Budgets measured on the companion's text from the first commit | — | 2 |
| C6 | §9, F4, board 01 | **the Crashes section** on Wealth's Risk tab as board 01 draws it, every state the record adds (no benchmark, provisional, a name without a window, a manual window); „Im Depot ansehen“ links Holdings with the window as a custom range, and for a window before the view's first booking shows one line instead (F4); the crash benchmark chosen inline in the windows' disclosure (board 02 Q2); at 1200 and 390 px; the privacy mode leaves the percentages. `DESIGN.md` gains the anatomy | 01 | 3 |
| C7 | coverage rule | the API reference, `docs/integration` (English, then German), the operator guide's passage on the section and the setting | — | 1 |

**Lane D, the data-quality pair and the logo tools** (#1414, #1417,
#1413; board 04).

| Story | Source | What it does | Board | Commits |
|---|---|---|---|---|
| D1 | #1414 | `implausible_quote` runs over every security with a priced booking, held or not, each finding with `held: true\|false`; benchmarks and retired securities left out as in every set; the basis says what it covers. Tests first, a sold security's backwards-adjusted series | — | 1 |
| D2 | #1417, board 04 A | the Overview counts each security set over held securities first, its link opening Wertpapiere with `holding=held` (the screen's parameter; the API's is `holding_status`), „(im Katalog n)“ after it as its own link where the two counts differ, the effect text without its "if held" wording, the KPI cell „n gehaltene veraltet“; no section when every held count is 0, the catalogue count still reachable on Wertpapiere's chips and over the API. The ledger checks (cash mismatch, rate only, incomplete split) count bookings and stay as they are | 04 | 2 |
| D3 | #1413 | `portfolixir.securities.logo_put` (`{url}`, https only), `logo_delete`, `logo_discover` in the book profile, routed to the existing endpoints, `openWorldHint` on the two that fetch; companion tests against a fake API; contract entry 29 part D | — | 1 |

**Lane P, the stack faster and lighter** (I34 step 1, I33; board 05).
P1 caches a figure every screen reads, so it gets the money lens.

| Story | Source | What it does | Board | Commits |
|---|---|---|---|---|
| P1 | I34 step 1 | the bands read registered as its own analytic at the default `:request` lifetime (ADR-0039; no C3 activation), keyed as the contribution table is plus the request's level, sort, scale, category and classification, fixed periods only, with its computation version. **A memo hit equals a fresh read**, byte for byte, after each kind of write that invalidates it (a booking, a quote, a category change, an FX rate, a classification edit), pinned; a switch back to a period already seen is a hit, pinned. No rendered difference | — | 1–2 |
| P2 | I33, board 05 | `.stack-band` at `fill-opacity: 0.8`, the legend's swatches with it; `.stack-band--negative` set explicitly to 0.6 (its `fill-opacity` replaces the base's, it does not multiply); the hover's `opacity: 0.85` unchanged (it multiplies, landing at 0.68); both themes, the privacy mode | 05 | 1 |

**Lane L, the layout gate** (#1435; `DESIGN.md`'s amendment of 2026-11-08;
board 06 and its inventory `06-control-bar-inventory.md`). A gate this
lane adds gets an attack lens before integration (D-8 item 5).

| Story | Source | What it does | Board | Commits |
|---|---|---|---|---|
| L1 | #1435 (1), inventory §1 | **the shared component**: `StackedChart.bar/1` and its CSS extracted into one component for a bar of labelled controls (a label column, A; labels above, B, as the floor where A does not fit), the stacked chart's bar its first user, rendered byte-identical, pinned | 06 | 1 |
| L2 | #1435 (1), board 06 | the five bars that break today move onto it: the journal's chips and form as one bar at 390 px, „Nach dem Verkauf“'s comparison with labels above, Wertpapiere's and Transaktionen's chip rows with a label column and every family named; the two the seed does not render (Prognosen' author and model, the allocation's drift filter) move too, each with a seed state the walk can reach | 06 | 2 |
| L3 | #1435 (2) | **the walk:** every page with a labelled bar at 390 and 1200 px, controls whose groups sit on different rows sharing their left edge (±1 px); a red run against today's journal seen first; it uses M2's settle helper | — | 1 |
| L4 | #1435 (3) | **the static check:** no labelled segmented control, select or chip family outside the component; the bars without a visible label (`income_live.ex`, `portfolio_live.ex`'s performance and allocation bars, `tax_live.ex`, Prognosen' status) registered as exceptions with that reason, as the inventory found them | — | 1 |
| L5 | #1435 (4), inventory §2 | **open prose:** the walk asserts that no visible free paragraph outside a `details.metric-tooltip`, a data note or a registered basis line runs past one sentence of at most 25 words (the inventory's threshold); the five paragraphs over it move behind their ⓘ (`positions-basis`, `stories-basis`, `chart-basis`, `predictions-basis`, the transactions summary) and `bond_strip.ex`'s, each before/after on board 06's frames; empty states, alerts, a list of names and a figure's label registered as exceptions with their reasons | 06 (frames added) | 2 |

**Lane H, the Bitcoin cycles** (FR-58, idea I12; ADR-0059, ADR-0048's
amendment of 2026-11-12, ADR-0060; the idea boards
`ux-design-2026-11-10-idea-i12/` 01 to 03 as adopted, and board 07 for the
states the records add). **Risk tier: security** (a new outbound caller,
gate B3.3 opened for it) **and analytics** (a projection, the float
island widened by `:math.log/1`): its own PR, a dedicated verification
pass, a callout in the briefing. Exact `Decimal` expectations, each seen
failing first; no network in any test (fake Esplora answers).

| Story | Source | What it does | Board | Commits |
|---|---|---|---|---|
| H1 | ADR-0059 §2, §4; ADR-0048's amendment | **the registry and the binding:** the chains as protocol constants in code (Bitcoin and Bitcoin Cash 210,000 blocks, Litecoin 840,000; Zcash not registered); `halving_chain` on the security through `securities.update`, journaled, an unknown value 422 naming it; the event kind `halving` (§8 of ADR-0048 narrowed, confirmed halvings out of the staleness read, a security merge never duplicating a halving); unbinding or rebinding deletes that security's halving events after the confirmation | 07 | 2 |
| H2 | ADR-0059 §3, §7, §10 | **the Esplora adapter** on `Portfolixir.Net.Http`: only `/blocks/tip/height`, `/block-height/:h`, `/block/:hash`; mempool.space first, blockstream.info only when the first fails, `PORTFOLIXIR_BITCOIN_ESPLORA_URL` replacing both under the URL policy; every answer checked before anything is written (the tip not more than 6 behind, the block echoes, the timestamp bounds, the genesis hash once a day); both sources failing changes nothing. **B2 registration with its attack self-test** (a host it did not name, a redirect, a plain-http or private own URL), attacked by another agent before integration (D-8 item 5) | — | 2 |
| H3 | ADR-0059 §5, §6, §8, §9, §10, §12 | **the run:** past halvings confirmed after six confirmations, `source_quality` primary, the UTC date of the block, never re-read; the next one an unconfirmed window (the last 2,016 blocks' mean block time to the ten-minute target), written at most once a day; every 6 hours where the quote sync runs, only while a security is bound to Bitcoin; one state row per chain; stale after 24 hours; the B5 system-writer entry `chain_read`; **the gate sentence widened** in `AGENTS.md` and PRD §4 in the same commit as the registry entry (§12), never ahead of the code | — | 2 |
| H4 | ADR-0060 §1, §2, §3, §12, §13 | **the cycles read's past:** the windows from one halving to the next (the halving day's close in the new window), the top and the low as the peak and trough of each window's maximum drawdown (latest peak, earliest trough), the partial 2012 window's low marked `partial`, the open window's top anchored after a 20 % fall, its low only when the window closes; the six intervals with n, min and max; **2020–2024 pinned with the March 2024 close above the November 2021 top**, seen failing under "highest close" first | — | 2 |
| H5 | ADR-0060 §4 to §10; AR-3's amendment | **the bands:** time from min to max, price from f₂ to f₂^(ln f₂ / ln f₁) (min to max where undefined, stated), at least two observations per part; one band per event as the hull, `agree` the overlap of parts with their own price side; the cones from the last anchor; the states (open, running, reached, missed) from stored closes, none for a band whose inputs postdate its window; `not_a_forecast: true`; **no `as_of`** (422, pinned); `:math.log/1` registered as AR-3's fourth float operation with its test; the computation basis in every payload; the payload in `metrics_carry_no_verdict_test.exs`'s key walk | — | 3 |
| H6 | ADR-0059 §11; ADR-0060 §11 | `GET /api/v1/chains`, `POST /api/v1/chains/:chain/refresh` (once per 10 minutes, 429 `retry_after`, 422 `no_source`), `GET /api/v1/securities/:security_id/cycles` with `include=aligned`; `portfolixir.chains.list`, `portfolixir.chains.refresh`, `portfolixir.securities.cycles` and the dossier's `cycles` line (about 40 tokens, measured on the companion's text); contract entry 29 part H; the schema budget grows by the new tools' own bytes only | — | 2 |
| H7 | ADR-0060 §11; idea boards 01 to 03; board 07 | **the chart:** the „Zyklen“ toggle where the view exists, „Zeitachse“ and „Ausgerichtet“, halvings, ▲ and ▼, the bands with „beide Wege“, the three line switches („Top ↔ Tief“ on) continuing as cones, the interval table with n and the count, the chain's health line; every state of board 07; at 1200 and 390 px, both themes, the privacy mode (prices are amounts: hidden as on the chart today, the axis in percent). `DESIGN.md` gains the anatomy | 01–03, 07 | 3 |
| H8 | ADR-0060 §11; ADR-0059 §11 | the range „Zyklus“ reaching past today while cycles are on (the axis empty right of today but for the halving window and the bands); the dashboard card „‹Name›-Zyklus“ opening the chart with cycles on in one click; the „Halving-Kette“ choice in the security's edit form with §4's confirmation | 01, 07 | 2 |
| H9 | coverage rule | the API reference, `docs/integration` (English, then German), the operator guide's passage on binding a chain, the own URL and reading the band | — | 1 |

**Closing act** (D-8), one per risk class when its group is done, counted
by its lenses (D-10):

- **Lane N:** the **order lens** on N1 (a fetch, a promotion, an
  assignment and two overlapping ratings interleaved), the correctness
  hunter, the design critic against board 03.
- **Lanes B and C:** the **money lens** (every pinned return recomputed
  independently; a split, an FX day, a gap, a security younger than the
  window, an ongoing crash), the edge-case hunter, the **order lens** on
  the rule and the ties, the **agent's lens** (the budgets, the wording,
  each tool's answer reading as data), the design critic against boards
  01 and 02 in both themes at 1200 and 390 px.
- **Lanes D and P:** the money lens on P1 (a stale memo after each write
  kind), the correctness hunter, the design critic against boards 04 and
  05.
- **Lane H:** the **security lens** on H2 and H3 (a hostile or lying
  Esplora answer: a tip that runs backwards, a block that echoes another
  height, a timestamp in the future, a testnet genesis, a redirect, an own
  URL on a private address; nothing written in any of them), the **money
  and analytics lens** on H4 and H5 (every top, low, interval and band
  recomputed independently; a gap over a top, a split, the partial window,
  a part with one observation, `f₁ = 1`), the **order lens** (two runs
  racing, a refresh during a scheduled run, a rebinding during a run), the
  **agent's lens** (the budgets, that "not a forecast" and n are in every
  answer), and the design critic against the idea boards and board 07.
- **Lane L:** the **attack lens** on L3 to L5 before integration (a bar
  that wraps only at 768 px, a label set in CSS, a paragraph split into two
  elements, an exception added without its reason), and the design critic
  against board 06 on every migrated bar at 390 and 1200 px.
- **The UAT persona** on the review seed: rates a domain down and blocks
  another and reads the queue and a promotion; promotes a story with only
  long links; reads a promoted entry on the Research tab; chooses a held
  fund as the comparison benchmark and as the crash benchmark; reads a
  detected window, names it, makes an overlapping manual one, switches the
  benchmark and back, and compares each list with the API; opens „Im Depot
  ansehen“; reads the Overview's held-first count; switches Wealth's
  period back and forth and sees no second computation; narrows the
  journal, Wertpapiere and Transaktionen at 390 px and finds every label's
  control on one edge; binds the synthetic Bitcoin security to its chain
  against a fake Esplora, reads the halvings, the cycles and both bands on
  the chart and over the API to the digit, opens the dashboard card, sees
  the source go stale when the fake stops answering.

**Close-out** (the last commits of PR 3): `sprint-status.yaml`, `epics.md`'s
FR Coverage Map (FR-54 complete) and a dated reconciliation, the idea list
(I24 built; I33 built; I34 step 1 built), the retrospective, the version
report.

**Estimate** (D-10), counted by lenses, per PR:

- **PR 1** (M, N, B, C): build about 31 (M 4–5, N 8, B 4, C 14); lenses
  eight (N 3, B and C 5) at Sprint 28's rate of about 3.7 fixes each,
  about 30; integration and CI about 3: **about 64**.
- **PR 2** (D, P, L): build about 14 (D 4, P 2–3, L 7); lenses four (D and
  P 2, L 2), about 15; integration and CI about 2: **about 31**.
- **PR 3** (H): build about 19; lenses six (H 5, the UAT 1), about 22;
  integration and CI about 3; the close-out about 4: **about 48**.
- **About 143 in all**, each PR well under 100. No cut line: the stack
  replaces it (D-10).

## Decisions

### D-1: what this sprint is for, and its exit criteria (recommended)

1. **No unpromoted news item keeps a tier its domain no longer has**
   after a rating commits; promoted items keep theirs; a fetch or a
   promotion racing a rating ends as E1 states, pinned by order tests.
2. **A story whose every link fits 2,048 characters can become an entry.**
3. **The operator sees and writes on the Research tab what the agent
   reads and writes**: an entry's headline, event type and tone.
4. **Any security with a stored quote can be a benchmark** in every read
   that takes `benchmark=`, and the basis says whether it is flagged.
5. **The same closes give the same windows**: every case of ADR-0058 §7
   pinned with exact `Decimal`s; 10.00 % opens a window, 9.99 % does not.
6. **The lists are reproducible and honest**: ties by figure, name and
   ISIN, never an id; no answer is never a zero; survivorship in every
   payload; a crash return and a sale-hindsight return over the same
   dates agree to the last digit.
7. **The Crashes section answers the same as the API** for the same
   window, list and universe.
8. **The chain source can only be read, and a lying answer writes
   nothing**: every check of ADR-0059 §7 pinned against a fake Esplora,
   the B2 registration attacked; the gate sentence widened with its
   registry entry and never ahead of it.
9. **The cycles reproduce and never forecast**: every top, low, interval
   and band pinned with exact `Decimal`s, 2020–2024's top the November
   2021 peak; no single date or price in any payload; `as_of` refused.
10. **A memo hit equals a fresh read** after every kind of write that
   invalidates it.
11. **`implausible_quote` names a sold security's unit error**, and the
   Overview counts held findings first.
12. **Every browser walk leaves a page through the shared settle helper**,
    asserted by a test.
13. **Every labelled bar starts its controls on one edge** at 390 and
    1200 px, and no open paragraph runs past one sentence, each held by a
    gate with its exceptions registered (#1435).
14. **Every gate holds by registration, not by weakening**, and the
    regressions this sprint introduced are counted apart from the older
    findings, none an S1 at promotion.

**No criterion counts open issues.** Reported, not judged: 35 open today.

**To flip by comment:** name a criterion to drop or add.

### D-2: I12 is built in this sprint, as its third PR (your decision)

You worked I12 out on 2026-11-10 and asked the next planning session to
write its records; ADR-0059 and ADR-0060 are on this PR, with FR-58 in
`epics.md` and its issue filed after the merge. A draft of this plan put
the build in Sprint 30, because it opens gate B3.3 for a new outbound
caller and the sprint's closing act is already the largest the project
has run; **you decided on 2026-11-12 to build it here, as an extra PR**.
So Lane H is PR 3, after the other two, with its own closing act and the
UAT persona and the close-out at its end. **The risk, named once:** about
143 commits across three PRs and three risk-tier groups (the news log,
the crash returns, the chain caller) in one implementation session; D-10
says what keeps it reviewable. **To flip:** "I12 in 30" moves Lane H back
and PR 2 carries the close-out.

### D-3: the layout gate (#1435) stays in Sprint 29 (your decision)

The Sprint 28 amendment's D-A5 placed #1435 here. A draft of this plan
moved it to Sprint 30 to stay under a self-imposed cap of 90 commits; you
rejected the cap on 2026-11-12, and the rule PR #1448 replaces it with
a stack at a lane-group boundary. So Lane L builds it in PR 2, from the
inventory (`06-control-bar-inventory.md`) and board 06 on this PR. The
inventory corrects the issue in two points (D-6): no shared component
exists yet, and three of the bars it names carry no visible label.

### D-4: the order of the work (recommended)

PR 1: M, N, B, C; PR 2: D, P, L; PR 3: H; inside a lane the story order, so
history goes forward only. N before B and C because #1444 borders an S1 in
a log that is never rewritten; B before C because ADR-0058 §1 reads Lane
B's rule; M first because L3's walk and every later walk take M2's settle
helper. PR 2's lanes may be built in parallel beside C on their own
worktrees (no shared file but the contract entry, `tools.ts`, the schema
budget, gettext and `app.css`, each between its markers) and are rebased
onto PR 1's head before PR 2 opens; Lane H likewise onto PR 2's head before
PR 3 opens. C2 to C4 wait for C1; C6 waits for C5; L2 to L5 wait for L1;
H3 waits for H1 and H2, H5 for H4, H6 for H3 and H5, H7 and H8 for H6.

### D-5: boards 01 and 02 (recommended)

ADR-0058 §9 and its amendment fix the section's content; the boards fix
the anatomy and the states. Each point below is the board's
recommendation; the phrase after it flips it.

- **01 P1** the section after „Kennzahlen des Portfolios“ („Crashes ans
  Ende“); **P2** the window a select, the first control of one bar of
  labelled controls („Crash-Fenster als Chips“); **P3** the screen opens
  on „Im Depot“, the API's default stays the catalogue („Crashes ganzer
  Katalog zuerst“); **P4** it opens on the newest window, the choice kept
  in the address („Crash-Start tiefstes Fenster“); **P5** on a phone the
  bars stay, two lines per entry („Crashes am Handy als Tabelle“); in the
  catalogue a held security carries „im Depot“ („Katalog ohne
  Depot-Marke“). P6 to P9 are ADR-0058's F1 to F4.
- **02 Q1** both pickers show two labelled groups, „Benchmarks“ then
  „Im Bestand“ (held today in any depot, with a stored quote, by name),
  no search („Benchmark-Suche“ adds one over every security with quotes;
  „Im Bestand je Ansicht“ narrows the group to the view); **Q2** the
  crash benchmark is chosen inline in the Crashes section's windows
  disclosure, no settings page („Einstellungsseite“).
- The privacy mode changes nothing in the section: it holds percentages,
  dates and day counts only (`PortfolixirWeb.PrivacyMode` hides amounts
  and quantities).

### D-6: what boards 03 to 05 fix (recommended)

- **Board 03 (the Research tab):** A, the headline first with the pin's
  glyph and „Ereignisart · Tonalität“ under it; the link shown as its
  domain (E2). „Research B“ puts the event type as a badge in the entry's
  head; „Research-Filter“ adds C, a filter by event type, which then needs
  `event_type` on `GET …/notes` and `notes.list` under the coverage rule
  (about two commits more).
- **Board 04 (#1417):** A, „(im Katalog n)“ after each held count where
  they differ. „DQ Katalog am Ende“ gathers the catalogue counts as one
  last clause (B).
- **Board 05 (I33):** 0.8, the negative part 0.6. „Bänder 0.65“ picks the
  lighter one, which the board shows fading yellow and green on white and
  bringing the negative part close to a hovered band.
- **Board 06 (#1435, Lane L):** the journal's chips and form as one bar
  at 390 px, the sale comparison's „Fester Zins“ with labels above (the
  floor B), Wertpapiere and Transaktionen with a label column and every
  family named. „Journal zwei Leisten“ and „Wertpapiere ohne
  Familiennamen“ flip two of them. The inventory corrects #1435: no shared
  component exists yet (`StackedChart.bar/1` has to be extracted first),
  and the bars it names in `income_live.ex`, `portfolio_live.ex` and
  `tax_live.ex` carry no visible label, so they are registered exceptions,
  not breaches; it proposes one sentence of at most 25 words as the
  paragraph threshold, with five paragraphs to fix.
- **M4 (#1439) has no board:** the page looks the same and now connects
  with storage blocked; the sprint workflow's exception ("identical
  picture").

Each flips by naming the board and the point.

### D-7: ADR-0056 E1's seed precision (recommended)

You adopted "a hand `sources_put` re-rates". E1 applies the same rule to a
seed write onto a domain without a hand row, because a seed that changes a
default after items are stored would otherwise leave the frozen tier E1
removes. A seed write onto a hand row stays a no-op. **To flip:** "news
retier hand only".

### D-8: the closing act and the build (standing, with Sprint 28's carry-forwards)

Each lens reviews the PR's diff and reports at most five findings, ranked
by severity. The story workflow's section "What a story's own tests do
not cover" applies to every story; Sprint 23's four build rules stand.
Sprint 28's carry-forwards, applied:

1. **One settle helper for every browser walk**, asserted by a test: M2,
   first, so every later walk takes it.
2. **A story agent runs its own tests under `mix coveralls`**, CI's cover
   mode, beside `mix test`, before it hands its result back.
3. **A closing-act fix that changes what a screen shows gets its board
   first**, as a frame added to this sprint's board folder, before the
   fix is committed.
4. **The closing act is counted by its lenses** (D-10), per PR.
5. **The attack lens before integration, kept:** N1's re-rating is
   attacked by an agent other than its author (a rating that wants to
   move a promoted item, a domain that covers another's items, a block
   racing a fetch) before it is integrated.

And the older ones that still apply: a story's item in a shared file
sits between its own markers (contract entry 29 with an N, a B, a C and a
D part; the contract test; `tools.ts`; the schema budget; `news.ex`'s
per-story markers); every parallel agent runs on its own test database;
the browser job runs locally before each closing act on the integrated
head; GitHub writes go through the MCP tools; this planning PR carries no
closing keyword (checked before it was opened), and the sprint PRs name
`Closes` for what each finishes: PR 1 #1416, #1421, #1439, #1440, #1443
and #1444; PR 2 #1413, #1414, #1417 and #1435; PR 3 FR-58's issue, filed
after this PR's merge.

### D-9: the ideas (the sprint workflow's "Ideas")

- **I12 leaves the list** as its row asked: FR-58, its records ADR-0059 and
  ADR-0060, built in this sprint's PR 3 (D-2). Its row becomes a pointer.
- **I24** stays a pointer, built here.
- **I33 and I34's step 1 are no-brainers** and built here (Lane P). I34's
  step 2 (warming the default period and serving a hit without the
  spinner) is measured after step 1 and planned with its numbers.
- **I9 was held on 2026-11-12** in this planning session, on its table
  (`rule-review-2026-11-12.md`): your answers are the rule PR #1448. The
  rows you did not take up (merging the duplicated texts, the two drops)
  stay in the table for a later pass. **The next deep conversation: I43**,
  where the Total chart's axis starts, with its board first.
- **I43 and I44** each need a board with the choice the row names; I43
  comes first (it settles the confusion that raised both).

### D-10: three stacked PRs, cut after Lane C and after Lane L (your decision)

About 143 commits in all: **PR 1** (Lanes M, N, B and C with their closing
acts, about 64) on the branch the environment assigns; **PR 2** (Lanes D,
P and L with their closing acts, about 31) on `<that branch>-pr2`, based
on PR 1's head; **PR 3** (Lane H with its closing act, the UAT persona and
the close-out, about 48) on `<that branch>-pr3`, based on PR 2's head, as
the rule PR #1448 allows. All open as drafts; a later PR targets the one
before it until that one merges, then is rebased onto `main` and
retargeted. You merge them in order, each by "Rebase and merge", ideally
in one sitting. **What keeps it reviewable:** each PR is promoted only
when its own closing act is done, with its own briefing, so PR 1 can be
reviewed and merged while PR 3 is still being built; the session's state
lives in the plan's checklist and the PRs' bodies, so a session that runs
out of context continues from them. The
cut sits where the money-math group ends, so PR 1 is the risk-tier half
and PR 2 the screens and the gate. A closing-act fix inside one story's
own code folds into that story's commit (the rule PR's history rule). If
the rule PR is not merged when Sprint 29 starts, the session builds PR 1
alone and PR 2 waits for it, named in PR 1's briefing.

### D-11: one `AGENTS.md` change, signed here

ADR-0060 §8 adds one item to the scope ladder in `AGENTS.md` (and its
twin in the PRD §4), with three small edits around it, all on this PR: an
**analog band** for a coming event is allowed (the range the stored past
cycles' intervals and factors give, with n and both ends, never a single
date or price, never fitted); scoring the band's rule on past cycles is
level (d); the computation-basis rule covers every analog band. The rule
changes only through this reviewed PR, as `AGENTS.md` asks; it permits a
shape and gates nothing, so it can stand before the code. ADR-0059's gate
sentence (§12: B3.3 opened for the chain source) changes in PR 3 (H3)
with the code and the gate registry, as ADR-0056 B8 did. No
other rule changes on this PR: your answers to the rule review are the
separate rule PR #1448. **To flip:** "Analog-Band nein" removes the item and
ADR-0060's band, and I12 ships without a projection.

### D-12: what stays open, and why (standing)

#899, #900, #1070 and #1220 keep Sprint 22's reasons. #1177 waits for its
trigger. #328 and #354 wait for your check on real data. #1396 waits until
the sample can carry the split (ADR-0055 §9).
The polish lists stay open while they have lines; a story
that touches a screen fixes its lines.

## Registry bookkeeping after the merge (the planning session's last step)

- File FR-58's issue under #418 (I12), pointing at ADR-0059, ADR-0060 and
  this plan's D-2, and the six asks the two records defer, per ADR-0043,
  each a thin pointer with its record's section: an own node or instance
  on a private address (a URL-policy amendment); chain sources for
  Bitcoin Cash and Litecoin; a security aligned on another chain's
  halvings; a price-level or event-date prediction kind (an ADR-0055
  amendment); a „Zyklen“ page (board option B); markers for every event
  kind and for resolved predictions on the chart.
- #1421's body names this plan; #1435's names Lane L, board 06 and the
  inventory's two corrections;
  #1444's notes that E1 is signed.
- No closures by hand; no relabels.

## Checklist (the implementation session ticks it on the PR)

- [ ] Lane M: M1 the version report, M2 the settle helper, M3 #1440,
      M4 #1439
- [ ] Lane N: N1 the re-rating (#1444), N2 the long links (#1443), N3 the
      Research tab's entry, N4 the research form's three fields
- [ ] Lane B: B1 any security as a benchmark (#1416), B2 the picker
- [ ] Lane C: C1 the setting, C2 the rule, C3 names and manual windows,
      C4 the lists, C5 the reads and tools, C6 the section, C7 the docs
      (#1421)
- [ ] PR 1: closing acts of N, B and C, fixes, re-check, briefing,
      promotion
- [ ] Lane D: D1 `implausible_quote` (#1414), D2 the Overview (#1417), D3
      the logo tools (#1413)
- [ ] Lane P: P1 the bands memo, P2 the translucent bands
- [ ] Lane L: L1 the component, L2 the five bars and two more, L3 the walk,
      L4 the static check, L5 open prose (#1435)
- [ ] PR 2: closing acts of D, P and L, fixes, re-check, briefing,
      promotion
- [ ] Lane H: H1 the registry and the binding, H2 the Esplora adapter, H3
      the run and the gate sentence, H4 the cycles' past, H5 the bands, H6
      the reads and tools, H7 the chart, H8 the range, the card and the
      form, H9 the docs (FR-58)
- [ ] PR 3: closing act of H, fixes, re-check, the UAT persona
- [ ] Close-out, retrospective, briefing, promotion
