# Sprint 26 — the screens Sprint 25 owes, what a switch cost, and the privacy mode

**Status: ADOPTED by the merge of the Sprint 26 planning PR.**
The merge is the signature (ADR-0026 step 1, as amended on 2026-10-08). It
signs [ADR-0057](../../docs/decisions/0057-what-a-switch-cost-the-purchase-the-money-went-into.md)
(I18 mode 3: a sale against the purchases its money went into, found by
rule), [ADR-0056's amendment of 2026-11-06](../../docs/decisions/0056-news-layer-fetched-matched-stored-labelled-outside.md#amendment-of-2026-11-06-the-owners-shape)
(the news layer as you settled it on 2026-11-06, built in Sprints 27 and
28), [ADR-0044's amendment of 2026-11-06](../../docs/decisions/0044-security-knowledge-as-an-append-only-log.md#amendment-of-2026-11-06-a-headline-an-event-type-and-a-tone-on-an-entry)
(a headline, an event type and a tone on a research entry, which the news
layer needs) and the picks of boards 01 to 05 (D-6). A fresh
implementation session builds the sprint on `agent/<provider>/sprint-26`
as **one** sprint PR (D-9). The severity rule of ADR-0026's amendment of
2026-11-01 applies unchanged.

## What you need to do

1. **Merge, to adopt the plan.** None of the three records books or
   corrects a stored money figure, so every choice in them is decided with
   its reason and flips by a comment. ADR-0056 was signed by your merge of
   #1399; this merge confirms it with the amendment you described on
   2026-11-06 (feeds as a 90-day staging area, a cheaper model tagging, an
   agent picking what lasts).
2. **Look at boards 02 to 05** (D-6). Board 01's pick is yours already: C,
   the soft bar. Each of the others carries a recommendation that silence
   adopts; a comment naming another option changes it.
3. **Optional, still open from Sprint 24:** the `browser` CI job as a
   required status check on `main` (Settings → Branches).
4. **Optional:** Dependabot's #1392 (`floki` 0.38.4 → 0.38.5, test only) is
   your merge, as the version reports have said since Sprint 23.

**Not asked:** everything else. **Not raised:** the Bitcoin cycles (I12),
held by you on 2026-11-06 until you explain them; no lane, board or
decision here touches them.

**Verification basis:**

- **Sprint 25's merge, as its close-out asked this plan to record:** the
  sprint PR #1398 was merged at 06:52 UTC on 2026-11-06; CI run 1901 green
  on `1b82d4d`; release **2026.11.10**. Its keywords closed #894, #1395
  and #1397 (#1390 had been closed by the planning PR's keyword, the
  retrospective's finding 4).
- **Since then on `main`:** `1b82d4d` (`AGENTS.md`: an agent rebases and
  force-pushes its own branch without asking, the owner's grant of
  2026-11-06). Before it, #1399 (ADR-0056) merged at 21:34 UTC on
  2026-11-05. `main` is at `1b82d4d`.
- **The open-issue list of 2026-11-06:** 25 open: 4 `agentic` (#1396,
  #1070, #900, #899), 1 `agentic` and `needs-decision` (#1220), 1
  `needs-decision` (#1177), 2 `needs-uat` (#328, #354), 17 trackers (11
  polish lists #1355 to #1366 without #1364; #991; the five area trackers
  #416 to #420). Two Dependabot PRs are open: #1391 (`sobelow` 0.18.1) and
  #1392 (`floki` 0.38.5).
- **Read against the code on `1b82d4d`**, each claim this plan rests on:
  - The security page's tabs are `overview chart transactions trades
    quotes holdings classifications research events`
    (`securities_live.ex`, `@tabs` and `detail_tabs/0`); there is no
    predictions tab. Predictions are read by `GET /api/v1/predictions`,
    `/:id` and `/calibration` (`PredictionController`) and four MCP tools.
  - "All trades" is the realized tab of Cashflow & Income
    (`/cashflow?tab=realized`, linked from the Overview); the hindsight
    read is `GET /api/v1/sales/hindsight`
    (`Portfolixir.Portfolios.Performance.SaleHindsight`), which shares
    `WindowReturn.price_return/3` with the predictions' resolution.
  - The three cascading deletes confirm with a browser `data-confirm`
    text that names no count (`classifications_live.ex`: the
    classification twice and the category; `buckets_live.ex`: the view);
    their API answers `dry_run=true` (`DryRunParam`). The app's own delete
    dialog anatomy is `booking_delete_dialog.ex` on the `ModalDialog` hook.
  - Every amount on a page goes through `PortfolixirWeb.Format.money/2`,
    percentages through `percent/2` (about 200 call sites of the first);
    quantities through `exact/2` and `decimal/3`.
  - A buy and a sell carry `cash_account_id`, `fees`, `taxes` and their
    settlement (`Ledger.Transaction`), which ADR-0057's rule reads.
  - #1365 has seven open lines; two of them (the pre-delete text that does
    not name predictions; the benchmark flag that can be removed under a
    recorded call) name Sprint 26's prediction view as their fixer.
    `render_cell`'s four `raw/1` clauses are the reason `sobelow` 0.18 was
    declined (version report of Sprint 25).
- **The schema budget in force** (Sprint 25's last row) and **the
  contract's head, entry 25**, as Sprint 25 left them; this sprint's
  contract entry is 26.
- **Boards 01 to 05** were captured from a review instance on the
  synthetic review seed; synthetic additions are marked on each board.

## State of play, in five lines

1. **Sprint 25 is on `main`** (release 2026.11.10). Three of its
   capabilities are agent-only with a deadline: F1 (predictions and the
   calibration report), I18 modes 1 and 2, F21's dry run. Their screens
   are due by the end of this sprint (Sprint 25 plan, D-7).
2. **I18 mode 3 is decided** (ADR-0057): no stored link, a rule.
3. **The privacy mode (I22) is worked out** and its look is picked (C).
4. **The news layer is settled** (ADR-0056 with its amendment) and is
   Sprints 27 and 28.
5. **The Bitcoin cycles (I12) are held** by you.

## Why this cut

- **The deadline first.** The two-way coverage rule gives F1, I18 and F21
  until the end of this sprint for their screens; a missing one is a
  close-out finding. Lane V builds all three.
- **Mode 3 with its screen, in the same sprint.** ADR-0057 adds one
  optional block to a read that exists, with no table and no migration;
  built beside I18's view, it ships with its screen, so no new deadline
  arises.
- **The privacy mode** is a screen change on every page with no money
  semantics; it rides the screen sprint, with a leak test over every page.
- **The news layer waits** (ADR-0056 A4): a new outbound surface and a
  hostile-input parser deserve their own closing act, and the deadline
  screens would compete with them in one review. Nothing is lost in
  between: the N1 convention lets your outside agent record news as notes
  today.
- **About 40 commits**, one PR, no stack (D-9).
- **What is left out, and why** (each flips by naming it): the news layer
  (Sprints 27 and 28); #1365's two lines that need a board of their own
  (the chart's hover readout, #1341; the locked logo's offer) and its
  notification line (#1276), which a polish pass on that screen takes
  with a board; I20 (usage hints), which waits for your examples; #899,
  #900, #1070, #1220, #1177, #328, #354 and #1396 keep their standing
  reasons (D-10).

## Lanes (one sprint PR, `agent/<provider>/sprint-26`, in this order)

**Lane M, maintenance (first).**

| Story | Source | What it does | Commits |
|---|---|---|---|
| M1 | #1365's line; Sprint 23 and 25 version reports | `securities_live.ex`'s `render_cell` clauses for `:badge`, `:code`, `:money_signed` and `:percent_signed` rewritten as HEEx (no rendered difference: a test pins each clause's markup before and after), then `sobelow` 0.16.0 → 0.18.1 with `mix sobelow --skip --exit` clean and no ignore added; the #1365 line ticked | 2 |
| M2 | standing rule | the version report `version-report-2026-11-…-sprint26.md`: Hex, npm, Elixir/OTP, PostgreSQL, BMAD core and the external modules, each bump its own commit, what is declined with its reason | 1–2 |

**Lane V, the screens Sprint 25 owes (two-way coverage, D-7 of Sprint 25).**

| Story | Source | What it does | Board | Commits |
|---|---|---|---|---|
| V1 | F1; ADR-0055 | the security page's **„Prognosen“ tab**: the security's predictions with day made, author and model, the claim, the benchmark and the status (open with days left, hit or miss with the excess, unresolved with its reason), the note that a prediction is permanent, the computation basis behind the ⓘ; the empty state. #1365's two prediction lines fixed in the files it touches: the pre-delete text names predictions; the benchmark flag's help text says recorded predictions keep the security as their benchmark | 02 | 3 |
| V2 | F1; ADR-0055 §4 | the **calibration report's** home, as board 02's pick places it: Brier with its standard error and the 0.25 reference, sharpness, the hit rate with its standard error, the five bands shown from 20 resolved (else the sentence why), the groups by author and model, the list of all predictions across securities | 02 | 3 |
| V3 | I18 modes 1 and 2; FR-50 | **what a sale missed** on "All trades" and on the security's Trades tab, as board 03's pick lays it out: the benchmark chooser (none, a fixed rate, a flagged security), the four spans, `pending` and `incomplete` with their reasons, the basis behind the ⓘ; no verdict word anywhere. **The review seed gains closes around three of its sales** (synthetic), because on today's seed every span reads „kein Startkurs“ and the page could not be checked against its board | 03 | 3 |
| V4 | F21; #894 | the three cascading deletes confirm in the app's own delete dialog, which lists from the dry run what the delete removes, or the refusal instead of a delete button, as board 04 draws it; `data-confirm` leaves the three controls | 04 | 3 |

**Lane R, what a switch cost (I18 mode 3, ADR-0057; risk tier: a money
derivation, its own commit group and verification pass).**

| Story | Source | What it does | Commits |
|---|---|---|---|
| R1 | ADR-0057 §§1–3 | the matching rule and the two sides as one pure function over the ledger and the closes, through `WindowReturn`. Pinned with exact `Decimal`s, each case seen failing first: one sale and one buy; a buy larger than the proceeds (funded in part); two sales whose proceeds compete for one buy (oldest first); a buy on day 31 (`no_buy_within_30_days`); a buy from another cash account (not matched); a sale in a USD account at a moving rate; a buy after a span's end (the money as cash); the sale's taxes apart and a tax refund (negative); fees inside; an orphan sell (`no_cash_account`) | 3 |
| R2 | ADR-0057 §4 | `include=reinvestment` on `GET /api/v1/sales/hindsight` and on `portfolixir.sales.hindsight`; an unknown `include` value refused with 422 (Sprint 25's carry-forward 2); the `computation_basis`; contract entry 26; the API reference and `docs/integration` | 2 |
| R3 | ADR-0057 §6 | mode 3 in V3's surface: the third comparison with the kept and switched sides, the difference, the fees inside, the taxes apart, the days to the first buy, `no_match` with its reason | 03 | 1 |

**Lane P, the privacy mode (I22; board 01, pick C; board 05).**

| Story | Source | What it does | Board | Commits |
|---|---|---|---|---|
| P1 | I22 | the switch in the top bar (beside the appearance menu, per browser, surviving a reload, never stored on the server) and the mask: while it is on, every figure rendered through `Format.money/2` and the quantity formatters is replaced, **on the server**, by one constant placeholder of a fixed width drawn as look C, so neither the digits nor their length reach the page; percentages, dates, counts and ratios stay. `DESIGN.md` gains the anatomy | 01 | 2 |
| P2 | I22 | charts while the mode is on, as board 05 draws them: a euro axis becomes percent from the window start, tooltips show no amount | 05 | 2 |
| P3 | I22 | **the leak test**: a browser test walks every page of the shell with the mode on, on the review seed, and fails on any text that matches a currency amount or a quantity, and on any amount in a chart's data attributes; seen failing first on one page left unmasked | — | 1 |

**Closing act** (D-8): the correctness hunter; the money lens on R1 (every
pinned case recomputed independently, the moving rate included); the
agent's lens on R2 (the tool says what the block means, before tax, price
only, by rule); the privacy lens on P (view source, the copied text, the
chart data, the phone width, a page the leak test does not list); the
design critic on V1 to V4, R3 and P against boards 01 to 05; the UAT
persona records a prediction through the test seam, reads it on its tab
and in the report, reads a sale's three comparisons, deletes a category
through its new dialog, and walks the Overview and Wealth with the mode
on in both themes. About 7 commits.

**Close-out** (the PR's last commits): `sprint-status.yaml`, `epics.md`'s
FR Coverage Map (FR-46, FR-47, FR-50 with its third comparison, FR-51)
and a dated reconciliation, the idea list (I18 mode 3, I22 `built`; F1,
I18 and F21's views recorded), the retrospective, the version report.
About 5 commits.

**Estimate:** M 3–4, V 12, R 6, P 5, closing act 7, close-out 5: **about
40**, with room for one review round under ADR-0026's 90.

## Decisions

### D-1: what this sprint is for, and its exit criteria (recommended)

1. **No agent-only capability is overdue at the close-out:** F1's tab and
   report, I18's view and F21's dialogs are on `main`'s branch, each built
   against its board.
2. **ADR-0057 is built as signed:** each case R1 names equals a hand
   computation in its test, with exact `Decimal`s, at a moving rate too;
   the rule matches the same buys for the same ledger, twice in a row.
3. **The privacy mode leaks nothing the leak test can see** on every page
   of the shell, in both themes, at 1200 and 390 px; the page source of a
   masked page contains no amount.
4. **`sobelow` 0.18.1 is in** with no ignore and no baselined finding.
5. **The regressions this sprint introduced are counted** apart from the
   older findings, and none is an S1 at promotion.

**No criterion counts open issues.** Reported, not judged: 25 open today.

**To flip by comment:** name a criterion to drop or add.

### D-2: ADR-0057, signed by this merge (recommended)

The ADR says it in full. The choices it makes that you did not make
yourself, each flippable by a comment naming its flip:

- **By rule, not by hand** (§1): the buys from the same cash account
  within 30 days take the proceeds, oldest first. Nobody can pick the
  flattering buy. "I18 manual link" adds a hand link under §7's
  conditions.
- **Taxes apart, both sides before tax** (§3): the kept position's latent
  tax is not known, so counting only the switch's tax would make every
  switch look worse. "I18 taxes inside" counts them.
- **No total over all switches** (§5): a total reads as a score of your
  switching and needs its own pass first. "I18 total" adds it.
- **Transfers are not followed** (§1): "I18 follow transfers".

### D-3: the news layer as you settled it (recommended)

ADR-0056's amendment writes down your shape of 2026-11-06 and adds four
things the signed record did not answer: **A1** a parser hardened against
hostile XML (no atoms from names, no entities, depth and count caps,
fixtures for each attack); **A2** a promoted story becomes a research
note with a headline, an event type and a tone (ADR-0044's amendment),
and the chart draws only such notes, never raw items; **A3** each feed's
yield over 30 days with a `low_yield` flag, and at most 200 stored items
per feed and day; **A4** Sprints 27 and 28. **To flip:** "News in 26", or
a number for the cap by comment.

### D-4: the privacy mode masks on the server (recommended)

**Why not CSS over the real figure:** a blurred or covered number is still
in the page source, in a copied selection and in a screen reader's
output, and blurred digits can be recovered by matching. Masking where
`Format.money/2` renders means the figure never leaves the server while
the mode is on. The switch is per browser (a cookie the layout reads),
because the mode belongs to the screen being shown, not to the dataset;
nothing about it is stored on the server, and it is not a security
boundary: anyone at the keyboard switches it off. **API and MCP are
untouched:** a presentation mode is no capability, so the two-way rule
does not apply (stated here as its reason). **To flip:** "I22 CSS only",
which keeps the figures in the page.

### D-5: I22's scope (recommended)

Every figure in a currency and every quantity is hidden, prices and
buy-in prices included, because one rule leaks less than a list of
exceptions (the idea list, 2026-11-06). **To flip:** "I22 prices", which
shows security prices.

### D-6: the boards and their picks

Under `_bmad-output/planning-artifacts/design-language/mockups/`:

- **Board 01, the privacy mode's look** (`ux-design-2026-11-06-sprint26-i22/`):
  **picked by you: C, the soft bar.**
- **Board 02, predictions** (`ux-design-2026-11-06-sprint26-f1/`): the tab „Prognosen“ after „Research“ in the
  research timeline's anatomy (open, hit, miss, unresolved with its reason;
  figures only once resolved; „verfehlt“ muted, not red), its empty state,
  and #1365's two lines (the delete confirmation names predictions; the
  note after removing a benchmark flag counts the predictions that keep
  measuring against it). **The report: A, recommended,** a Wealth tab
  „Prognosen“ with author and model filters, the calibration cards, the
  bands (below 20 the sentence why), the groups and „Alle Prognosen“
  across securities with the due query. *Why not B* (a block on Risiko):
  Risiko is read through the view, calibration measures an author across
  every security, and the list and the due query would have no place.
  „F1 B“ changes it.
- **Board 03, what a sale missed and what a switch cost**
  (`ux-design-2026-11-06-sprint26-i18/`): **C, recommended:** a section „Nach dem Verkauf“ of its
  own under the trades list (and on the security's Trades tab, filtered),
  one row per sale booking, a chooser „Vergleich“ (Ohne, Fester Zins,
  Wertpapier, Anschlusskauf for mode 3), the four spans with all three
  figures and no click. *Why not A or B* (a column group on each trade, or
  a row that opens): the read has one row per sale booking and "All
  trades" one row per FIFO round trip, so on the seed three of ten sales
  have no trade row, and one sale's figures would repeat on every lot it
  closes; A does not fit 1200 px either. Mode 3 sits in the same chooser
  because it compares the same rows over the same spans; its buys, the
  cost line, the taxes apart and `no_match` open under each sale.
- **Board 04, the delete dialogs** (`ux-design-2026-11-06-sprint26-f21/`): the three cascading deletes in the booking
  delete dialog's anatomy: „Das Löschen entfernt:“ with one line per kind
  and its count, what stays, the journal sentence; the refusal with the
  rules that block it and only „Schließen“; the changed-while-open state;
  the phone sheet. **A, recommended: counts only;** B adds names (two of
  nine assignments and „7 weitere“), which repeat the page behind the
  dialog and grow with the data. „F21 B“ changes it. Decided on the board,
  each flippable: the confirm deletes only if the delete removes exactly
  the ids the dialog showed, else it shows the changed state („F21 ohne
  Abgleich“ drops the check); a kind with no rows gets no line.
- **Board 05, charts in the privacy mode** (`02-privacy-charts` in the
  i22 folder): no pick, board 01's rule applied to every chart: a euro
  axis becomes percent of the window start (Wealth's „Wert“ becomes
  „Wert (%)“ with a line saying deposits and withdrawals count in it),
  the security chart is held in its own „Prozent“ view, cash-flow bars
  keep their heights and lose their amounts, every amount left in a
  tooltip or badge is look C. Two choices flip by comment: „I22 Wert aus“
  (hide the value series in the mode) and „I22 Balken in Prozent“ (label
  bars with their share).

Silence adopts each recommendation; a comment naming another option
changes it. Each story writes its anatomy into `DESIGN.md`.

### D-7: what Sprint 27 owes (standing; the close-out checks it)

Nothing agent-only is planned in this sprint, so no human view falls due
in Sprint 27. Sprint 27 builds ADR-0056's first half (agent-first, by
§11), whose human view is Sprint 28's, with its marker board on Sprint
28's planning PR.

### D-8: the closing act and the build (standing, with Sprint 25's carry-forwards)

Each lens reviews the PR's diff and reports at most five findings, ranked
by severity. The story workflow's section "What a story's own tests do
not cover" applies to every story; Sprint 23's four build rules stand.
Sprint 25's carry-forwards, applied:

1. **The adversarial pass at planning time** was run on ADR-0057 (its §7)
   before this merge signs it; the closing act's money lens attacks R1 as
   a party that wants a switch to look good.
2. **A safety parameter is refused when misspelled:** R2's `include`
   refuses an unknown value; V4's dialog sends `dry_run=true` and its test
   proves a misspelling cannot reach the real delete from the screen.
3. **A story's item in a shared file sits between its own markers:**
   contract entry 26, the contract test, `tools.ts` and the schema budget.
4. **This planning PR carries no closing keyword** (checked before it was
   opened); the sprint PR names what it closes.
5. **Every parallel agent runs on its own test database**
   (`DATABASE_NAME=…`), and a test that must run outside the sandbox gets
   its own scratch database.
6. **The rebase and the history cleanup** need no permission any more
   (`AGENTS.md`, 2026-11-06); a commit message states a count only once
   its run has finished.

### D-9: one PR, no stack (recommended)

About 40 commits, so one PR merged by your "Rebase and merge" button. The
build order is the lane order (M, V, R, P), so history goes forward only
and V3 exists before R3 extends it. A PR nearing 85 commits is cut at its
last finished lane into a stacked PR, named in the briefing.

### D-10: what stays open, and why (standing)

#899, #900, #1070 and #1220 keep Sprint 22's reasons. #1177 waits for its
trigger (a switcher's export with those two types). #328 and #354 wait for
your check on real data. #1396 (per-source calibration) waits until the
sample can carry the split (ADR-0055 §9). The polish lists stay open
while they have lines; a story that touches a screen fixes its lines.

## Registry bookkeeping after the merge (the planning session's last step)

- File, as thin pointers: **the predictions' views** (V1, V2; FR-46 and
  FR-47's human view) under #419; **what a sale missed, its view and mode
  3** (V3, R1 to R3; FR-50 and ADR-0057) under #418; **the delete dialogs
  from the dry run** (V4) under #417; **the privacy mode** (P1 to P3;
  FR-51) under #418; and, for Sprint 27, **the news layer's first half**
  (ADR-0056 §11 and A1, A3; FR-52) under #416.
- `epics.md` gains FR-51 (the privacy mode) and FR-52 (the news layer) in
  this PR; their tracker lines name the issues once filed.
- No closures by hand; no relabels.

## Checklist (the implementation session ticks it on the PR)

- [ ] Lane M: M1 `render_cell` as HEEx and `sobelow` 0.18.1, M2 version
      report
- [ ] Lane V: V1 the predictions tab, V2 the calibration report, V3 what a
      sale missed, V4 the delete dialogs
- [ ] Lane R: R1 the rule and its two sides, R2 the read, R3 its screen
- [ ] Lane P: P1 the switch and the mask, P2 the charts, P3 the leak test
- [ ] Closing act, fixes, re-check
- [ ] Close-out, retrospective, briefing, promotion
