# Architecture review 2026-11: the proposed split per module

This file is section 7 of the architecture review of 2026-11 (I38): the split
it proposes for each of 19 oversized modules. It belongs to the triage of the
same date in this folder, `architecture-review-triage-2026-11-24.md`, which
holds sections 1 to 4, 6 and 8 to 13; "section 11 of the triage" and a
decision `AD-n` (its section 10) name that file. Section 5, the S1 and S2
findings in full, is `architecture-review-findings-2026-11-24.md`. An ID
`N-nn` is a finding of the security review of the same commit (lens 1), whose
triage is `security-review-triage-2026-11-11.md`.

**Status: PROPOSED** — part of the triage and adopted with it, by the merge of
this planning PR (ADR-0026 step 1 as amended on PR #780: the merge is the
signature). No split here is scheduled before that.

A finding held under the security triage's "Disclosure handling" appears here
by its ID and severity only. A held fix is never part of a move commit.
Whether a held finding meets a split, and at which step, is read from the
private report before that split's first move; no section of this file says
so. "The private report" is the complete report of this review or of the
security review; the owner holds both, and neither is committed.

A reproduction or scratch test that a section names lies in the private
evidence the triage describes, not in the repository.

Where two lanes found one defect, a section prints the key of the lane it
draws on, which is not always the key in the triage's index: R-001 (O8-01) is
R-001 (D2-01) there, R-048 (A2-07) is R-048 (D5-04), R-145 (O6-06) is
R-145 (M1-04) and R-152 (O6-07) is R-152 (V1-04). Section 12 of the triage
lists the merges.

Line counts and `file:line` references are at the audited commit `e014f284`.
`lib/portfolixir_web/live/dashboard_live.ex` has since grown from 1,544 lines
by about 3,000 added and 760 removed (the dashboards of ADR-0062), so its
proposal has to be read against the file again before it is used.

## 7. Proposed split per oversized module

I38 names six modules. The lanes read those and the others below,
because they share mechanisms with the six or hold the rules the six call.
Each proposal was written by the lane's reader and then recounted by an
independent reviewer. All nine reviews came out "sound with corrections". What
follows is the corrected proposal, not the first one. The sizes after the
split are the reviewers' estimates.

| Module | Lines at `e014f284` | Left after the split | New modules | Steps | Decision or ADR |
|---|---|---|---|---|---|
| `lib/portfolixir_web/live/securities_live.ex` | 7,738 | about 3,100 | 21 | 8 | ADR-0001 paragraph on pages (AD-5, AD-7); a line each in ADR-0047 and ADR-0035; one board line (R-024 (O1-02)); one decision on the period rule (R-052 (O1-07)) |
| `lib/portfolixir_web/live/portfolio_live.ex` | 6,201 | about 2,000 | 9 | 8 | ADR-0001 paragraph on pages (AD-5, AD-7); one sentence in ADR-0034; one decision on the data-quality counts (it changes an API answer); one board (the loading state of the positions) |
| `lib/portfolixir_web/live/imports_live.ex` | 5,365 | about 1,350 | 9 | 8 | A note on ADR-0050, for step 7 only; the owner decides whether step 7 happens |
| `lib/portfolixir_web/live/classifications_live.ex` | 3,717 | about 1,650 | 6 | 8 | ADR-0040 and ADR-0030, with AD-3 |
| `lib/portfolixir_web/live/transaction_management_live.ex` | 3,502 | about 1,050 | 10 | 8 | None; a board for the paged history; coverage is AD-4 |
| `lib/portfolixir_web/live/income_live.ex` | 1,811 | about 300 | 5 | 8 | None |
| `lib/portfolixir_web/live/portfolio_accounts_live.ex` | 1,693 | about 1,150 | 4 | 7 | None |
| `lib/portfolixir_web/live/dashboard_live.ex` | 1,544 | about 650 | 4 | 8 | None |
| `lib/portfolixir_web/live/securities/merge_preview.ex` | 1,780 | about 1,000 | 2 | 5 | None; one decision on a board |
| `lib/portfolixir_web/live/portfolio_accounts/merge_preview.ex` | 1,104 | about 700 | 1 | 5 | None; the same board decision |
| `lib/portfolixir_web/controllers/api/v1/json.ex` | 3,014 | about 100 | 17 | 8 | ADR-0001 paragraph on wire shapes (AD-5, AD-7) |
| `lib/portfolixir_web/controllers/api/v1/contract.ex` | 2,082 | about 120 | 28 | 4 | None for the split |
| `lib/portfolixir_web/layout_view.ex` | 2,548 | about 76 | 3 | 8 | Owner decision: the triage of 2026-09-05 prescribed this move, Sprint 11 shipped the nonce instead; moving reopens that choice (AD-7) |
| `lib/portfolixir_web/components/app_shell.ex` | 1,210 | about 400 | 5 | 8 | None |
| `lib/portfolixir/imports/applier.ex` | 3,245 | about 2,450 (2,300 with the optional step) | 4 | 6 | None; a dated note in ADR-0015 |
| `lib/portfolixir/lifecycle/security_merge.ex` | 2,801 | about 1,700 | 5 | 6 | None |
| `lib/portfolixir/portfolios/performance.ex` | 2,604 | about 1,100 | 4 | 5 | ADR-0010, with AD-2; ADR-0007 for step 4 |
| `lib/portfolixir/ledger.ex` | 2,345 | about 600 to 750 | 5 | 4 | Dated notes only (ADR-0001 and four others) |
| `mcp-server/src/tools.ts` | 6,054 | about 300 | 12 | 8 | A dated amendment of ADR-0002 |

How to read a section: "Jobs it does today" is what the module holds now.
"Proposed split" names each new module with what it takes. "Order of work" is
a sequence of commit groups, each meant to compile and pass on its own (the
reviewers traced the calls across each proposed boundary by reading; nothing
was compiled or run);
"move only" means no behaviour changes in that step. "Pins before the first
move" names the tests that hold the behaviour while code moves, and the pin
that is missing. "Do not" lists the traps the review found.

Two rules apply to every split:

- **A split is scheduled, never done on the way** (I38: "an architecture
  change is an ADR amendment, never a silent refactor"; AGENTS.md, "Stay in
  scope"). Moving markup into function-component modules changes no recorded
  decision, but ADR-0001 is silent on how a page is organised. The page
  paragraph of its amendment (AD-5, worded in AD-7) is written once and
  lands before the first page split, as the securities and Wealth sections
  ask; it covers the other page sections too, whose "none" means none
  beyond it. Where a step changes another decision, its section says which
  ADR.
- **Figure fixes first.** Section 11 of the triage schedules the fixes of 25 of the 29 S1
  and S2 before any split (its steps 1 to 3), so a move cannot bury them.
  The other four: the paging of the Transactions history (R-011 (O4-04)), which is
  no figure fix and stays that split's last step, after a board;
  R-020 (O6-03), whose small step section 11 lets ride with lens 1's
  Batch 1; and two held S2 (R-018, R-019), which are scheduled from the
  private report. A split section lists each of the other fixes before its first move, or
  says why not; if the fix has landed by then, that part of the step falls
  away.

Seven "modules with several jobs" findings have no split section, because
the lane that read them had another question: `lib/portfolixir/buckets.ex` (five
jobs in 1,536 lines, R-107 (A6-06)), the four News files (R-111 (G4-05)), the `Portfolios`
context as a whole, whose Performance sub-tree is a context in all but name
(R-106 (A5-08)), the four Cash-flow reports (R-108 (D4-07)), the cash and the depot merge as
one protocol written twice (R-110 (G4-01)), the API's refusal helpers (R-121 (O6-02)), and
`lib/portfolixir/portfolios/targets.ex` (seven jobs in 1,595 lines, R-109 (G1-07)).

### `lib/portfolixir_web/live/securities_live.ex` (7,738 lines at e014f284)

**Jobs it does today.** One LiveView (a server-rendered interactive page) holds the securities list and the detail pane of one security with its eleven tabs. It has 73 event clauses, 19 message clauses and 81 pieces of page state. Below, "the page" is this file and a bare `:123` is one of its lines.

| Job | About lines | What it does |
|---|---|---|
| Frame and address | 516 | Starts the page, shows the one result message of an action, reads the URL as the list's filter state and the selection, and follows a security that was merged away. |
| List | 967 | Toolbar, table rows and phone rows, column choice, sorting, the cells, the read of the list. |
| Filters | 641 | Filter chips as a row and as a phone sheet, the filter builder, removable chips, the two-scales notes. |
| Row actions and dialogs | 550 | The row menu and its actions, seven hosted dialogs, the note for a row that vanished meanwhile. |
| Logo and price sync | 646 | Logo display, fallback, upload dialog and retry; the price sync of one or all securities. Both run as watched background tasks. |
| Detail frame and load | 565 | Head, status line, tab row, selecting and clearing a security, and one load that reads the data of nine of the eleven tabs on every URL change (Predictions and News are read only while their tab is open). |
| Overview tab | 529 | Six figures, a small chart, the thesis card and a note. It sums the position itself. |
| Chart tab | 829 | Range and toggles, the overlays (moving averages, cost line, note pins), the metric grid. |
| Trades, Transactions, Holdings, Quotes tabs | 1,413 | Open lots and closed trades, the bookings, rows per depot with a total and buckets, the quote table with the manual-quote release. |
| Classification, Research, News, Predictions, Dates tabs; number formatting | 1,082 | A category per tree, the research log and its form, the stories' load and note form, the dates list; sign colours and signed figures that six jobs call. |

**Proposed split.** New files sit under `lib/portfolixir_web/live/securities/` unless a full path is given. A function-component module is markup only: no state, no read. A plain module is ordinary functions. A context function lives in the domain layer under `lib/portfolixir/`. Every web-module row is a move without a behaviour change.

| New module (path) | Kind | Takes | About lines |
|---|---|---|---|
| `lib/portfolixir_web/figures.ex` | plain module | Sign colours, signed percent, decimal display, unit counts, the "no return" sentence. Page-neutral: Income and Transactions hold private twins (`lib/portfolixir_web/live/income_live.ex:1730`, `lib/portfolixir_web/live/transaction_management_live.ex:2175`) and can adopt it later. The unit count calls the Transactions page's plural rule (`TransactionManagementLive.plural_count/1`, the page's `:2814`; a second call at `:3862` goes with the Holdings tab). The review names the call and leaves it open. If the rule moves here too, its four call sites outside this page are re-pointed in the same commit (`lib/portfolixir_web/live/transaction_management_live.ex:2264`, `lib/portfolixir_web/live/portfolio_live.ex:3628`, `lib/portfolixir_web/live/income_live.ex:1791`, `lib/portfolixir_web/live/transactions/booking_delete_dialog.ex:492`). Three other splits move their sign-colour clauses into `lib/portfolixir_web/format.ex` (Wealth step 6, Cash flow step 2, Overview step 3), and two move `plural_count/1` there (Transactions step 1, Cash flow step 2). The plan picks one home before the first of these steps; if it is `format.ex`, the sign colours and the unit count of this row go there and `figures.ex` keeps the rest. | 125 |
| `lib/portfolixir_web/research_label.ex`, `lib/portfolixir_web/quote_source_label.ex`, `detail_labels.ex` | plain module | Three label modules: research entry labels (replaces the copies in `predictions_tab.ex` and `stories_tab.ex`), quote source labels (ends three calls from two child modules back into the page), chart range and series-basis labels. | 97 |
| `trades_tab.ex` | function-component module | Open lots, closed trades and their notes, and the "no return" table cell that the Holdings tab also uses. The sale-hindsight section stays in the page's slot. | 665 |
| `transactions_tab.ex`, `events_tab.ex` | function-component module | The bookings table; the dates list. No event, no state. | 230 |
| `quotes_tab.ex`, `classifications_tab.ex` | function-component module | The quote table; the category rows. Their events stay on the page by name. | 210 |
| `research_tab.ex` | function-component module | Thesis state, timeline and the entry form's markup. The form's five clauses stay on the page. | 290 |
| `holdings_tab.ex` | function-component module | Rows per depot, the total row, bucket controls. It prints the ledger's total and has no sum of its own. | 300 |
| `overview_tab.ex` | function-component module | The six figures, small chart, thesis card and note. It prints the ledger's total and has no sum of its own. | 470 |
| `chart_tab.ex` | function-component module | The chart panel and the metric grid. It takes 18 values; the page builds overlays, pins and the metric block and passes them in. | 455 |
| `list_url.ex` | plain module | Pure: URL parameters to list state, list state to a path. It takes the list state as a value. | 150 |
| `columns.ex` | plain module | The column registry and the two row accessors, which three event handlers, the toolbar, the logo patching and the row menu also call. | 140 |
| `lib/portfolixir_web/security_logo.ex` | function-component module | Logo, fallback and the country table of the flag fallback. | 130 |
| `list_table.ex` | function-component module | Table rows, phone rows and the cells. | 470 |
| `filter_chips.ex` | function-component module | Chip rows, phone sheet, counts, and one public data-quality label. Today the label exists twice with different clauses (`:7693-7703`, `lib/portfolixir_web/live/securities/filter_popover.ex:253-266`). | 320 |
| `sync_result.ex`, `research_form.ex`, `story_promotion.ex` | plain module | Pure halves: the sync's result sentence; form input to attributes and errors, for the research entry and for the story note. Their handlers stay on the page. | 230 |
| `lib/portfolixir/ledger.ex` | context function | `holdings_for_security/2` (a security's rows per depot) also answers the total and names the rows each figure leaves out (R-024 (O1-02)). | 40 |
| `lib/portfolixir/catalog/quotes.ex` | context function | `attach_metrics/1` (the list's figures) refuses the 1M and 1Y return of a frozen series, as the engine's momentum does (R-021 (O1-01)). The change is in the catalog; the page loses nothing. | 0 |
| `lib/portfolixir/catalog/security_metrics.ex` | context function | A moving-average series over the whole stored history, cut to the chart's range by the page (R-025 (O1-04)). | 15 |
| `lib/portfolixir/catalog/data_quality.ex` | context function | The two staleness readings (the marker, and "this close is old"), under new names: that file already has a `stale_quote?/2` with other arguments (its lines 127-131). | 25 |
| Ledger, Catalog, Classifications, Knowledge, News, Buckets, Valuation, QuoteSync | context function | The detail read per tab on one pricing pass (R-062 (O1-03)); list filter and sort options (R-105 (O1-06)); the cost line (R-009 (A2-02)); period dates, first quote date, category per tree, chart pins, story defaults, status currencies, ISIN country, logo path, bucket state, the sync's crash result. | 330 |
| none now | LiveComponent | Deferred; see "Decision or ADR". | 0 |
| `lib/portfolixir_web/live/securities_live.ex` | stays in place | Start-up, the URL read with the merged notice, all 73 event and 19 message clauses in their order, the result slot, row actions, the loaders, two render frames. One page on `/securities`, as `docs/decisions/0022-task-oriented-information-architecture.md:50` fixes. | 3,100 |

**What is left.** The page holds about 3,450 lines after the moves (steps 2 to 7; the figure does not subtract what step 1 takes out) and about 3,100 after the context moves (steps 1 and 8). It still owns start-up, the URL, every event and message handler, the result slot, the loaders and all 81 pieces of state; it no longer owns the markup of a tab or of the list, and after step 8 it computes no figure.

**Order of work.** The planning PR carries the decision lines named under "Decision or ADR" before any step. Every step re-extracts the translation references it moves.

1. Changes behaviour. The figure fixes as the risk-tier commit group, a story each, test first: the cost line from the Ledger's fold (R-009 (A2-02), the one S1 in this file), the position total from the ledger (R-024 (O1-02)), the 1M and 1Y refusal (R-021 (O1-01)), the moving-average series (R-025 (O1-04)). R-024 (O1-02) and R-021 (O1-01) must land before step 4; otherwise the two opposite total rules (`:2028-2057`, `:3835-3840`) move into two new files. R-009 (A2-02) and R-025 (O1-04) block no move; no move step takes the cost fold (`:3998-4135`, 138 lines). The page sizes given in steps 2 to 7 are the review's and do not subtract what this step takes out of the page.
2. Move only. `Figures`, the three label modules, the staleness readings into the catalog. The page imports them, so no template changes. The later steps do not compile without it: the tabs call labels and the staleness check that are private today (`:3728`, `:1811`, `:1845`, `:1208`). Page at about 7,490.
3. Move only. `TradesTab`, `TransactionsTab`, `EventsTab` (no event, no state), then `QuotesTab`, `ClassificationsTab`, `ResearchTab` (nine events stay on the page by name). Page at about 6,090.
4. Move only. `HoldingsTab`, `OverviewTab`. Page at about 5,320.
5. Move only. `ChartTab`. Zoom and export are checked by hand in a browser, because four names are shared with JavaScript. Page at about 4,890.
6. Move only. `ListUrl`, with unit tests. Its module description states that it does not carry foreign URL keys. That is today's behaviour: the three keys of the sale-hindsight section (`lib/portfolixir_web/live/sale_hindsight_section.ex:68-70`) are dropped on every URL change the page makes. Carrying them is its own line. Page at about 4,740.
7. Move only. `SecurityLogo`, `Columns`, `ListTable`, `FilterChips`. Then `SyncResult`, `ResearchForm`, `StoryPromotion`. The row loop stops receiving the page's whole state, so one frame of what the server re-sends is measured before and after. Page at about 3,450.
8. Changes behaviour. The remaining context moves, one story and one test each: the detail read per tab on one pricing pass (R-062 (O1-03)), list options (R-105 (O1-06)), then the small rules of R-052 (O1-07). Page at about 3,100.

**Pins before the first move.** Existing: about 40 test files named for the page under `test/portfolixir_web/live/` (about 350 tests) read rendered ids and survive a move that keeps the markup. By step: `securities_trades_tab_test.exs`, `unconvertible_trade_live_test.exs`, `security_metrics_events_panel_test.exs`, `securities_quote_release_live_test.exs`, `securities_research_tab_test.exs` (3); `security_detail_overview_test.exs`, `zero_cost_basis_screens_test.exs` (4); `securities_cost_basis_overlay_test.exs`, `test/browser/note_pins_phone_test.exs` (5); `securities_url_filters_test.exs`, `live_url_params_test.exs` (6); `securities_filter_chips_test.exs`, `column_picker_convergence_test.exs`, `securities_logo_render_test.exs`, `securities_sync_rearm_test.exs`, `security_stories_tab_test.exs` (7). Across all steps: the event sweeps `live_event_payload_test.exs` and `live_component_payload_test.exs`, and the browser tests `test/browser/securities_polish_test.exs`, `closing_act_layout_test.exs`, `privacy_leak_test.exs`. Two pins name the page's path and change once: `test/invariants/displayed_dates_test.exs:40` (step 3) and `test/portfolixir_web/live/securities_render_cell_test.exs:22` (step 7). Missing, to write first: the failing tests of the four figure fixes (a priced delivery in, for the cost line; two depots with one cost missing; a series frozen for over a year; the 200-day line on a 6M chart, which no test names today); unit tests for each new public helper, with its move; every new file added to the translation scan's list (`test/portfolixir/localization_test.exs:130-136` names five files and stops covering moved code without failing); one measured frame of the list's re-send size before step 7, which no test sees.

**Do not.**

- Do not move a handler that writes into a LiveComponent (a part of a page with its own state and events) now. A component's events skip the page's login re-check on every event (`lib/portfolixir_web/live_event_guard.ex:16-19`, `lib/portfolixir_web/live_ui_auth.ex:41-43`); the research entry (`lib/portfolixir_web/live/securities_live.ex:5586`), the story note (`:5639`) and the logo upload and removal (`:6336`, `:6035`) would lose it.
- Do not move the row loops or the detail head before `ListUrl`, and never hand it the page's whole state. They call the private path builder with that state (`lib/portfolixir_web/live/securities_live.ex:813`, `:869`, `:1129`); inside a component the map is the component's own, and `list_state/1` (`:397-407`, collects the filter state) crashes on the missing key.
- Do not put a database read or a state writer into a module called pure or markup-only. `load_metric_block/1` (`lib/portfolixir_web/live/securities_live.ex:4281-4286`, reads the metric block) and `assign_securities/2` (`:4500-4504`, writes the list) stay on the page; so do `merged_notice/2` (`:295-303`) and the note for a vanished row (`:7159`, `:7187`), which read the merge records and the catalog.
- Do not move a URL-parameter read out of the page, and do not route an event through a generic clause. Two test sweeps read the page's own source (`test/support/live_source.ex:19-33` for events, `test/support/live_source.ex:64-89` for URL keys); a moved read such as `merged_from` (`lib/portfolixir_web/live/securities_live.ex:295`) leaves `test/portfolixir_web/live/live_url_params_test.exs:64` without a failure.
- Do not repair anything inside a move. Three suspected defects (read, not run) and one known gap each get their own line and test: the Overview note editor closed by any reload (`lib/portfolixir_web/live/securities_live.ex:6659`), a refused research entry drawn into the next security's form (`:6611-6615` against `:6646-6647`), the Quotes tab naming a range it does not show (`:1507`, `:3728`), the Overview's two links dropping the list filters (`:1735`, `:1737`).

**Decision or ADR.** An ADR amendment is needed before step 2: one paragraph in `docs/decisions/0001-modular-phoenix-monolith.md`, which is silent on how a page is organised (`docs/decisions/0001-modular-phoenix-monolith.md:28-31`), because `AGENTS.md` rules "Do not silently change architecture decisions; amend the ADR". Its content: a page keeps its URL, its process messages and its result slot; a tab body is a markup-only module that reads nothing; a figure comes from a context function; state leaves to a LiveComponent only where one job owns it, and a handler that writes stays on the page until component events carry the login re-check. Lane A2's R-078 (A2-08) amends the same ADR; the two belong in one. Step 1 is risk-tier work under `docs/decisions/0036-risk-tier-rides-the-batch.md`; it needs a line in `docs/decisions/0047-derived-metrics-per-security-and-per-view.md` (which coverage rule the list's returns follow; the moving-average series only if the API serves it) and one board line at `_bmad-output/planning-artifacts/design-language/DESIGN.md:7731-7737` for R-024 (O1-02): one rule for the result total on both tabs, either the board's partial sum with a note naming the rows left out, or the Overview's dash. Step 8 needs a line in `docs/decisions/0035-one-pricing-pass-per-read.md` and a decision on which dates a period token means (R-052 (O1-07)). Owner decision, later: the first proposal had three LiveComponents (research form, story note form, logo dialog); the review defers them until the fix of security finding N-57 is built (component events do not pass the login re-check; decided, not yet built). The logo dialog also carries the one image intake and three test pins on file paths.

**Findings that ride along.** R-024 (O1-02), R-021 (O1-01), R-025 (O1-04): fixed in step 1, before the tabs that print them move. R-113 (O1-05): this split is its fix. R-062 (O1-03), R-105 (O1-06), R-052 (O1-07): fixed in step 8. R-009 (A2-02) (the cost line folded in the page): fixed in step 1, risk tier. R-078 (A2-08) (which context modules are public to the web layer): same ADR-0001 amendment. R-081 (A5-02) (the pricing pass is not handed on): with R-062 (O1-03). R-031 (A6-05) (the category read loads every tree): with the category move of R-052 (O1-07). N-57: before any LiveComponent takes a handler that writes.

---

### `lib/portfolixir_web/live/portfolio_live.ex` (6,201 lines at e014f284)

**Jobs it does today.** The file is the Wealth page. One module serves two tabs, Holdings and Allocation, that never share a page process, because the tab is fixed when the page opens (`:126`). It holds 249 hand-written functions, 38 event clauses (the code that answers a click), 15 landing clauses (the code that takes the result of a background read) and 54 assigns (values the page keeps for drawing). By line ranges about 1,940 lines serve only the Allocation tab, about 2,860 only Holdings, about 1,360 both. Line numbers without a path are this file's.

| Job | About lines | What it does |
|---|---|---|
| Page shell and address | 579 | Opens the page on a tab; keeps the tab, view and language links; shows the migration, view-gone and tree-gone notices and the empty state; holds the plan dots of the view switcher. |
| Period | 435 | The period tokens, year chips and custom range; keeps the period on the address and in the browser's memory. |
| KPI band | 362 | Total, TTWROR, IRR or MWR, cash quote, opening value and net flows, multiple; the Allocation tab's summary line. |
| Line chart | 477 | The return or value line with its tooltip, the per-year or per-month table under it, the stale and failed banners, the basis lines. |
| Stacked chart, series switch, contribution wiring | 534 | Level, tree, sort and filter of the stacked chart on the address; its load, colours, drill and breadcrumb; the switch between the two series; the wiring of the contribution table. |
| Benchmark | 483 | Picks up to two benchmarks; the redirect and note for one that was merged away; the comparison block, the chart overlays, the costs line. |
| Allocation tab | 1,867 | The sunburst (the ring chart) and its centre, the legend, drift tree, flat worklist, plan findings and drift threshold. |
| Positions and cash accounts | 471 | The view's holdings table with its column picker and phone rows; the read-only cash table. |
| Data quality and rate sync | 534 | Lists what distorts the totals, each with its remedy; the on-demand exchange-rate sync. |
| Loads | 421 | Starts the background reads, takes their results, drops stale ones, falls back to "Everything" when a view is gone, shows failures, keeps the badge and the contribution table in step. |

The rows add to 6,163 lines; the rest is blank lines between the ranges.

**Proposed split.** Two tracks. The web track moves markup and helpers into modules beside the three that exist under `lib/portfolixir_web/live/portfolio/`; it changes no pixel and no figure. The context track (rows C1 to C11) moves figures and rules out of the web layer into the domain code under `lib/portfolixir/`; each row changes a figure or an API payload and is its own test-first story. A function-component module is stateless markup that the page calls with named inputs.

| New module (path) | Kind | Takes | About lines |
|---|---|---|---|
| `lib/portfolixir_web/live/portfolio/sunburst.ex` | plain module | The geometry of the allocation ring chart: segments, nodes, sector paths and legend entries (`:5592-5884`), with its three size constants. It formats money and percent, which read the privacy mode of the page process, so it is called while the page renders, as today. | 295 |
| `lib/portfolixir_web/live/portfolio/performance_chart.ex` | function-component module | The line chart `performance_chart/1` with five declared inputs, its series and label helpers, the privacy base, the two benchmark-overlay cells it draws, and the sampling rule `downsample/1` (thins a long series to 400 points), moved as it is and public because the page calls it too (`:2450`). | 245 |
| `lib/portfolixir_web/live/portfolio/data_quality_section.ex` | function-component module | The findings list `data_quality/1` with eight declared inputs, the bond-scale and implausible-quote entries, the rate-sync button and its messages, the helpers that build the entries. `two_scales_entries/1` (the rows of the bond-scale finding) is public here; its two callers on the Securities page and one test are re-pointed. | 480; about 405 after C2 and C9 |
| `lib/portfolixir_web/live/portfolio/positions_section.ex` | function-component module | The holdings table, its cells and phone rows (`:3231-3350`, `:3408-3422`, `:3512-3665`); the column keys, defaults and browser storage key as functions. Markup only: the read of the rows stays in the page. | 300 |
| `lib/portfolixir_web/live/portfolio/allocation_section.ex` | function-component module | The markup of the whole Allocation tab with 13 declared inputs: the sunburst's wrapper, drawing and centre as one unit, the legend, drift tree, flat worklist, chips, hints and findings. The valuation enters as one currency string. | 1,200 |
| `lib/portfolixir_web/live/portfolio/kpi_band.ex` | function-component module | The KPI band with a slot where the benchmark comparison stands, the Allocation tab's summary line, the IRR-or-MWR labels, the check whether the view's accounts overlap. | 340 |
| `lib/portfolixir_web/live/portfolio/benchmark_block.ex` | function-component module | The comparison block, the benchmark picker, the merged-away note, names, pairs, the costs line, the coverage note and the chart overlays. | 330 |
| `lib/portfolixir_web/live/portfolio/period_control.ex` | function-component module | The period tokens and the custom-range popover (`:2129-2253`); the period and range labels. | 170 |
| `lib/portfolixir_web/live/portfolio/address.ex` | plain module | Every reader and builder of the page's address for both tabs: period, tab, view, allocation, stack, the holdings link and the plan-editor link. The one canonical order of address parts gets one home instead of three. | 430 |
| `lib/portfolixir_web/live/portfolio/category_colors.ex` (exists) | plain module | The stacked chart's band colours, taking the sunburst's colour map as an input (the allocation read stays in the bands load), and a fallback colour. | 55 more |
| `lib/portfolixir_web/format.ex` (exists) | plain module | The three functions that pick the style class of a positive or negative figure, beside `displayed_sign/2`, which they wrap (`lib/portfolixir_web/format.ex:243-252`); two one-line aliases are dropped. | 15 more |
| `lib/portfolixir/portfolios/performance.ex` | context function | C1 the rows of the chart's table, the first row starting from the period's own start value. C3 which money-weighted figure applies (IRR, or the period MWR under one year); the Overview page's copy of the rule goes too. C8 the period's money result as a field. C10 which of two reads answered from older data. | about 80 leave the page |
| `lib/portfolixir/portfolios/valuation.ex` | context function | C2 the lists behind its data-quality counts (no price, priced at the last trade, stale quote), under one rule for retired holdings. | about 60 |
| `lib/portfolixir/portfolios/` (one new public read) | context function | C4 the view's holdings across every portfolio, shared with the private copy in `lib/portfolixir/portfolios/category_result.ex:183-197`. Not in `Ledger` (the bookings context), which calls no view-scope function today. | about 25 |
| `lib/portfolixir/portfolios/targets.ex` | context function | C5 which views carry a plan, by Wealth's own rule (an active plan or a cash target), in one query. | about 15 |
| `lib/portfolixir/portfolios/performance/bands.ex`, `lib/portfolixir/portfolios/performance/benchmark.ex` | context function | C6 the stacked chart's answer carries the filter's ancestor path. C8 the anchored level the page draws for a benchmark (`anchored_returns/2`, `:4536-4556`), as a named series with its basis; it is not the bought-once return (R-022 (G2-01)). C7 the rule for a merged-away benchmark, in the home that finding R-044 (A1-04) settles. | about 135 |
| `lib/portfolixir/portfolios/bonds.ex`, `lib/portfolixir/portfolios/quote_plausibility.ex`, `lib/portfolixir/portfolios/allocation.ex`, `lib/portfolixir/ledger.ex` | context function | C9 the bond-scale and implausible-quote findings among a valuation's positions, and the negative holdings grouped per security. C11 the allocation row carries the scaled target that the drift tooltip divides out itself today (`:5218`). | about 30 |
| `test/support/live_source.ex` | test helper | `LiveSource.param_keys/1`, which lists the address keys a page reads for the malformed-address sweep, follows calls into helper modules, so the sweep still sees the keys once `address.ex` exists. | not sized |
| `lib/portfolixir_web/live/portfolio_live.ex` | stays in place | See "What is left". | about 2,300 |

Rules for every section module: its inputs are declared; it takes labels as ready strings and never calls another section; it is never handed the page's whole state; it sends events and handles none.

**What is left.** About 2,300 lines after steps 3 to 7, about 2,000 after the context track and step 8. The file still owns the page process: opening the page and reading its address, the five loads and their landings with the rule that keeps badge and table in step, all 38 event clauses whole, the period's state changes, and the page template with the frame of the performance section.

**Order of work.** The ADR amendment named below lands in the planning PR before step 1.

1. Changes behaviour. The context stories that must not wait behind the moves, each test first in its context: C1 (the table's first row, finding R-010 (O2-01); risk-tier work with its own commit group and verification pass), C2 (the data-quality lists, R-053 (O2-02); after the owner's ruling) and C3 (the IRR-or-MWR rule, R-054 (O2-05); needed before step 6). With C1 and C2 ahead of steps 3 and 4, the lines they remove (about 110) are never moved into a section first. Also here, as a page fix with its tests red first: the one view-gone function, with the two drifted branches repaired (R-026 (O2-04); size S). It changes only the loads and their landings (`:1257-1274`, `:1292-1509`), which no step before 8 moves.
2. Move only (tests and comments, no production logic). The missing pins listed below. The eight comment blocks that stand above code they do not describe are re-attached, so each rule moves with its own reason (`:2331-2336`, `:4390-4393`, `:4725-4726`, `:4971-4973`, `:5097-5099`, `:5346-5347`, `:5900-5901`, `:6125-6126`).
3. Move only. `sunburst.ex` with the fallback colour in `category_colors.ex`, then `performance_chart.ex`. The page keeps two call sites for the ring geometry (`:2638`, `:2643`), the chart's call, and the stale labels with their banners.
4. Move only. `data_quality_section.ex`, with the two Securities-page calls and `test/portfolixir_web/live/bond_master_data_live_test.exs:575` re-pointed in the same commit; then `positions_section.ex`. The page keeps the rate-sync event, its three landing clauses, the flash timer, the rows' read, the four column-picker event clauses and the two functions that pick the bond-scale and implausible-quote findings for the overview load (`:5468-5482`).
5. Move only. `allocation_section.ex`, alone because it is the largest diff. The page keeps the tab's 13 event clauses, its load and its landing.
6. Move only. `kpi_band.ex` and `benchmark_block.ex` in one step, because the comparison is nested in the band (`:1720`, `:1954-2035`); the sign classes go to `format.ex`. The page keeps the computation of the comparisons and the merged-away redirect.
7. Move only. `period_control.ex`, then `address.ex` with the band colours into `category_colors.ex`; `test/invariants/displayed_dates_test.exs:46` is edited in the same commit. The page keeps the eight period event clauses, the period's state changes and the canonical address patch.
8. Changes behaviour. The loads, as a story of their own with a board for the positions' loading state: the overview's result as a named map instead of a seven-part tuple, loads by tab, the positions read (C4) inside the Holdings overview load, a default for every value a landing fills. The view-gone function of step 1 stays the only one. Whether a shared load helper is built is decided here, not before.

Steps 3 to 7 each re-extract the translation template (`priv/gettext/default.pot`) and ship alone. The other context rows (C5 to C11) are stories of their own and wait for no step.

**Pins before the first move.** Holding today: about 500 tests in 53 files open `/portfolio` or name the module, and almost all select by element id and `data-role`, which a pure move keeps. Per step, under `test/portfolixir_web/live/`: step 3 `portfolio_live_test.exs`, `performance_table_summary_test.exs`, `privacy_charts_live_test.exs` and `test/browser/sunburst_centre_return_test.exs`; step 4 `portfolio_data_quality_test.exs`, `wealth_holdings_columns_test.exs`, `wealth_phone_twins_test.exs`, `column_picker_convergence_test.exs` and `test/invariants/scope_b5_system_writers_and_schedulers_test.exs:108-109`; step 5 `allocation_positions_mode_test.exs`, `wealth_allocation_explanations_live_test.exs`; step 6 `wealth_kpi_band_test.exs`, `portfolio_benchmark_live_test.exs`, `performance_stale_serve_test.exs`; step 7 `performance_period_control_test.exs`, `custom_range_popover_test.exs`, `wealth_period_address_live_test.exs`, `wealth_stacked_chart_live_test.exs`, `live_url_params_test.exs`.

Missing, written in steps 1 and 2: (a) a context test for the start value of the table's first row; no test pins that cell today (`test/portfolixir_web/live/performance_table_summary_test.exs:52` asserts a figure that is true of two cells); (b) an expected list of the page's 15 address keys and 24 events with their keys, so that a sweep that shrinks fails instead of passing; (c) the two sweeps (`live_event_payload_test.exs`, which fires every event at each page, and `live_url_params_test.exs`, which sends malformed addresses) also open `/portfolio?tab=allocation`, which neither does today; (d) the `live_source.ex` change above; (e) the section modules join the fast translation guard (`test/portfolixir/localization_test.exs:130-136`). Written in step 1, red first: one test per drifted branch of R-026 (O2-04). The two pins on the private shape of the overview landing (`test/portfolixir_web/live/portfolio_live_test.exs:3403-3407`, `:3428-3432`) are kept until step 8 and rewritten once there.

**Do not.**

- Do not make a section a LiveComponent (a stateful section with events of its own). The column picker's browser hook sends to the page, not to a component (`lib/portfolixir_web/layout_view.ex:263`), the picker takes no event target (`lib/portfolixir_web/components/column_picker.ex:27-44`), the page resets the allocation's display state (`:471-472`, `:1286-1287`), and a component's events skip the session re-check (`lib/portfolixir_web/live_ui_auth.ex:41`, finding N-57).
- Do not give the positions a load of their own, and do not land the valuation apart from its companions before each has a default. A row's market value must be the valuation's own figure (`:3470-3477`); the cash table's account tags are written only by that landing and have no default (`:1346`, `:3369`), so the table would crash; rows that are still empty reach a loop at `:3486`.
- Do not thin or reorder the event clauses. The event sweep reads each clause's own pattern and body (`test/portfolixir_web/live/live_event_payload_test.exs:62`), and one event is already invisible to it because it hands its payload on (`:4763-4764`). Order decides behaviour at `:4710-4715`, at `:5069`, and at `:1431` above `:1437`.
- Do not fold look-alikes during a move: the two sampling rules (`:5959-5967`; `lib/portfolixir_web/live/portfolio/stacked_chart.ex:1126-1132`), the two privacy bases (`:4014-4020`; `stacked_chart.ex:806-816`), and Wealth's plan dots with the Classifications page's, whose difference is recorded (`lib/portfolixir/portfolios/targets.ex:353-365`).
- Do not add a dependency a move does not need: no forwarding stub in this file for `two_scales_entries/1` (`lib/portfolixir_web/live/securities_live.ex:5209`, `:5221` are re-pointed); no constant in a new module's head filled by a call into another module (`:542`, `:5033`; each is a compile-time dependency, and the file has 3 today); the band colours do not take their allocation read into `category_colors.ex` (`:1112`, `:1160`).

**Decision or ADR.** One ADR amendment, in the planning PR before step 1: ADR-0001 (`docs/decisions/0001-modular-phoenix-monolith.md:28-31`), which says what the web layer is made of, gains the page shape (one page process, sections as function-component modules, one address module, the loads in the page, no LiveComponent for a section and why). Why: an architecture change is an ADR amendment, never a silent refactor (`AGENTS.md`, Hard Rules; idea row I38, `_bmad-output/planning-artifacts/ideas.md:47`), and the four other page modules above 3,500 lines would follow the same shape. Owner decisions: (1) for C2, which rule the valuation payload's data-quality counts follow, retired holdings in or out and positions or securities as the unit, because it changes an API answer; (2) if step 8 still wants a load helper shared by seven pages, it is recorded as a decision, not as a module comment, because seven pages would depend on it; (3) a route of its own for the Allocation tab is not part of this split: it waits for the board of idea row I35 (`ideas.md:50`) and would amend ADR-0022 (`docs/decisions/0022-task-oriented-information-architecture.md:92`). Rules that already apply: C3 adds one sentence to ADR-0034 §2 (`docs/decisions/0034-money-weighted-metrics.md:72-73`); every payload field from C1, C3, C6, C8 and C11 states its computation basis and gets a contract entry, and C4's read gets an API and MCP twin or the PR says why not (`AGENTS.md`, Hard Rules and "API And MCP Coverage"); C1 is risk-tier work and step 8's loading state needs a board (`docs/development/sprint-workflow.md`, "Risk-tier attention" and "UI changes are mocked first").

**Findings that ride along.**

- R-010 (O2-01): fixed first, by C1; the table's first row stops showing a first-day deposit in its start value and again in its net flows.
- R-053 (O2-02): fixed by C2 after the owner's ruling; the page and the API then count the same lists.
- R-054 (O2-05): fixed by C3; the under-one-year rule gets one holder, and the payload names the figure that applies.
- R-063 (O2-03): fixed in step 8 with C4; each tab pays only for what it draws, and the positions read leaves the opening of the page.
- R-026 (O2-04): fixed in step 1; one view-gone function, the two drifted branches repaired, a test for each.
- R-114 (O2-06): this split, steps 3 to 7.
- R-012 (D2-03), R-013 (A2-03) (which category counts as targeted): not fixed by this split; their fixes land before step 5 (section 11 of the triage, step 2). The page's own "targeted" rules sit in the Allocation markup that step moves (`:2880`, `:2898-2915`, `:2984`, `:2995`, `:5103-5123`, `:5154`, `:5331`, `:5343`).
- R-028 (G1-04) (the "Create a plan" link on a built-in tree): not fixed by this split; its fix lands before step 5 (section 11 of the triage, step 2). The hint and its link sit in the Allocation markup that step moves (`:2604-2621`); the link's builder `plan_editor_path/2` (`:5981-5983`) goes to `address.ex` in step 7.
- R-022 (G2-01), R-023 (G2-02) (the benchmark figure in the chart's tooltip and in the table's column): not fixed by this split; their fixes land before step 3 (section 11 of the triage, step 3). `performance_chart.ex` takes the tooltip and the column's cell in that step (`:4227-4233`, `:4492-4497`); the anchored level they print is C8 (`:4536-4556`).
- R-048 (A2-07) (C1, C8): the figures the page derives itself move into the context. R-031 (A6-05) (C6): the page's own walk up the category tree goes. R-032 (A6-07) (C4): the fifth copy of the view-scope pipeline goes. R-044 (A1-04) (C7): the benchmark rule gets its home.
- R-081 (A5-02): eased, not fixed, by step 8, where the positions read uses the overview load's pricing context. N-57: the reason no section is a LiveComponent; not fixed here.

---

### `lib/portfolixir_web/live/imports_live.ex` (5,365 lines at e014f284)

**Jobs it does today.** Twelve jobs, merged here to ten rows; the line counts partition the file. The module has 234 functions and 35 values it keeps between events (34 it assigns itself, and `uploads`), and the jobs call each other at 153 sites. Nothing was run: counts come from reading the file at e014f284 and from pattern scans, and every test named as "to write" is unwritten. A line number without a path, such as `:1399`, is a line of this file. Two terms recur. The mapping is the operator's choice of a target for each cash account, depot and security the file names. The dry run is a background count of what the import would book under that mapping; it writes nothing.

| Job | About lines | What it does |
|---|---|---|
| Page shell, stage and upload | 359 | Mounts the page, switches between drop zone, preview and done page, discards; takes the file, shows progress, parses it and words file errors. |
| Parking and remount | 121 | Keeps the preview, the mapping and nine derived values in a server-side store, so a reload or a language switch does not lose them. |
| Preview head | 526 | Format, counts, kinds, parser warnings, the "nothing to import" note, the groups held back as already imported into another portfolio. One block in it (`:263-302`) computes 13 derived values, 9 of them for other jobs. |
| Account rows | 653 | The bucket tag and the cash and depot panels: each row's target choice, its count, its notes and its "remember" box. |
| Security rows and picker | 700 | Matched, created and undecided security rows, the search picker, the offer to record an ISIN change, the note on leftover configuration. |
| Mapping form state | 233 | The mapping as the form sends it: blank, filled with proposed choices, merged from each change. |
| Dry-run counts and recount | 362 | First counts, the background dry run, the release of names held back at first, the recount under the operator's mapping and its "recomputing" cue. |
| Completeness, confirm and apply | 652 | The "still to map" hint, the confirm button, the translation of the mapping into the import's parameters, the import's outcomes and its error sentences. |
| Correction section and dialog | 1,094 | Bookings already imported with a different amount: list, totals, dialog, confirm, result (ADR-0053 §6). |
| Done page and row wording | 665 | What the import did, as counts and nine lists; and the words "Row N" or "Entry N" by file format with the kind label, which every other job uses. |

**Proposed split.** Nine new web modules, all in a new directory `lib/portfolixir_web/live/imports/` and named `PortfolixirWeb.Imports.<Name>`, as the 28 modules beside other pages are (`lib/portfolixir_web/live/securities/merge_preview.ex:1`). A function-component module holds markup functions with named inputs; it adds no element to the page and keeps no state.

| New module (path) | Kind | Takes | About lines |
|---|---|---|---|
| `lib/portfolixir_web/live/imports/rows.ex` | plain module | Row wording, the row list and row descriptions, and the sentences two pages share: the money formatter, the held-back sentence, the words for a booked row and for a parser warning. 25 functions. The page's one compile-time tie to the ledger (`:1313`) goes with it. | 275 |
| `lib/portfolixir_web/live/imports/error_words.ex` | plain module | The sentences for file errors, parse errors, apply errors, bucket-tag errors and correction refusals. | 190 |
| `lib/portfolixir_web/live/imports/done_page.ex` | function-component module | The done page and its 14 list helpers, with 6 named inputs. The held-back count per portfolio is computed when the page draws, so the stored copy (`held_back_result`) goes. | 520 |
| `lib/portfolixir_web/live/imports/correction_section.ex` | function-component module | The correction's section and dialog and 30 sentence functions. It exports two builders the LiveView still calls (one correction line, the result line), because the result line is markup a task answer stores (`:1627`). | 910 |
| `lib/portfolixir_web/live/imports/preview_head.ex` | function-component module | The head's markup, the held-back groups, the "nothing to import" note, the pointer to the correction section. | 310 |
| `lib/portfolixir_web/live/imports/mapping_form.ex` | plain module | The mapping as one map: the blank map, the merge of each change, the read functions every panel uses, and the one parser that turns a choice string such as "existing:12" into the import's terms. 25 functions, no page state, no sentence. | 235 |
| `lib/portfolixir_web/live/imports/counts.ex` | plain module | Read access to the dry run's answer, which keeps its name and shape: a row's counts, its resolution, whether a name is new to the stored history, whether a count is provisional or waits for a recount. | 105 |
| `lib/portfolixir_web/live/imports/account_rows.ex` | function-component module | The bucket tag, cash and depot panels; the count display (the security rows draw it too), the "+ Create new" option, the row notes and their sentences. | 525 |
| `lib/portfolixir_web/live/imports/security_rows.ex` | function-component module | The security panel, the picker with its search forms and cards, the ISIN-change offer, and the four checks that decide what the picker draws. | 470 |
| `lib/portfolixir/imports/mapping.ex` (exists, 96 lines) | context function | The import rules the page decides today: the proposed choice per row, with the rule that a name new to the stored history gets none; the fill of a row once the dry run releases its name; whether each row is decided and the mapping complete; the translation for the import, with the rule which names are remembered; the translation for the dry run. They take and answer the import's own terms. | 510 leave the page |
| `lib/portfolixir/imports/correction.ex` (exists) | context function | The correction's totals per account and overall, answered in one read with the amounts a later set balance absorbs. | 25 |
| `lib/portfolixir/imports.ex` (exists) | context function | Which kinds of duplicate count as already imported and whether a file books nothing; the entry count; the import's portfolio for display. | 30 |
| `lib/portfolixir_web/live/imports_live.ex` | stays in place | Mount, the shell and the drop zone, the skeleton of the preview (the one apply form, the hint, the confirm), the upload, the parking, all 28 handlers of events, messages and task answers, the dry run's start and answer, the picker's reads, the helpers that re-derive the page's state. 42 functions. | 1,350 |

Lines are today's lines by their new home; about 65 lines of component calls and reason-to-sentence clauses come back into the LiveView, so the column adds up to more than 5,365. Three more figures should move into the context and are neither sized nor ordered by the review: the regrouping of a skipped duplicate as "with a different amount" (`:4017-4037`), the held-back count per portfolio on the import's result (`:2611-2623`), and the marking of a refused row the stored history replaced (`:5261-5267`).

**What is left.** After step 8 the file is about 1,350 lines and 42 functions: the handlers, the parking, the one apply form, the dry run's start and answer, and the helpers that derive the page's state. The six hand-ordered chains that re-derive that state (`:59-78`, `:140-154`, `:1410-1423`, `:1553-1562`, `:1667-1689`, `:1704-1720`) survive every step; folding them into one ordered function is an optional later step (about 1,300 lines after it), and only after it may the dry run's state become one struct, which changes the parking list (`:122-132`) and the remount test.

**Order of work.**

1. Changes behaviour. Fix R-154 (O3-02) first; nothing moves. The function that rebuilds the mapping from what the browser sends (`mapping_from_params/2`, `:4288-4316`) carries the recount flag, the mark that the operator changed a choice, as it already carries the record of proposed choices (`:4313`). The function that reads accounts and counts again after the database changed (`refresh_accounts/1`, `:1667-1689`) re-derives the correction's waiting state and rebuilds the mapping before it starts the dry run. A count on the screen can change; no booking does.
2. Move only. `rows.ex` and `error_words.ex`, one commit group. About 4,900 lines left. Both translation catalogues are extracted again; each holds 323 references to this file.
3. Move only. `done_page.ex`. About 4,380 left.
4. Move only, then one commit that changes behaviour. First `correction_section.ex`, markup unchanged. Then the totals move into `lib/portfolixir/imports/correction.ex`, and the ledger read behind the dialog happens once when the dialog opens (`:1439-1447`) instead of each time it draws (`:3884`). The picture stays the same. About 3,450 left.
5. Move only. `preview_head.ex`; the checks for "already imported" move into `lib/portfolixir/imports.ex`, beside the import's own count of the same three kinds (`lib/portfolixir/imports/applier.ex:193`). The head's markup calls two functions that stay private to the page until step 6 (`held_back_groups/1` at `:354`, `included_portfolios/1` at `:356`); in this step the page passes both values in as named inputs. About 3,130 left.
6. Move only. `mapping_form.ex` and `counts.ex`. No stored value is renamed and nothing parked changes. About 2,790 left. Without this step neither step 7 nor step 8 compiles: the row markup calls 17 functions that would stay private to the page, and the 36 rule functions call 14 page functions at 26 sites.
7. Changes behaviour: the rules change their home. Risk tier. The rules move into `lib/portfolixir/imports/mapping.ex`, and the five test files that carry a hand copy of the proposed choices (`test/portfolixir/imports/reimport_contract_test.exs:974-993` and four more) call it. Own commit group, the ADR-0050 note signed first, a verification pass on the ten probe cases P1 to P10 and the re-import invariants of ADR-0050 §16. About 2,350 left.
8. Move only. `account_rows.ex` and `security_rows.ex`. About 1,350 left. What the browser patches changes, so the browser test of the open picker is written first.

Steps 3, 4 and 5 do not depend on each other once step 2 is in.

**Pins before the first move.** Existing: 23 page test files, 12,625 lines, 199 tests (22 files `test/portfolixir_web/live/imports_*_test.exs` and `test/portfolixir_web/live/import_then_sell_round_trip_test.exs`), and five more that open the page (`test/portfolixir_web/live/privacy_open_states_test.exs`, `test/portfolixir_web/live/info_tips_test.exs`, `test/portfolixir_web/live/navigation_test.exs`, `test/invariants/scope_b6_intake_formats_test.exs`, `test/browser/privacy_leak_test.exs`). They read ids, `data-role` values and visible text; none reads the file by path or calls a private function, so a move that keeps the markup breaks none. `test/portfolixir_web/live/imports_parked_preview_remount_test.exs:303-362` compares a restored page with a fresh upload value by value. `test/portfolixir/imports/unseen_name_probe_test.exs` holds the signals the rules read. The check that the translation catalogues are current fails loudly at every step until they are extracted again. Missing, each to write before its step:

- Step 1: the R-154 (O3-02) test, a confirm the page refuses keeps the recount flag, added to `test/portfolixir_web/live/imports_recount_live_test.exs` and seen red first.
- Step 2: a first unit test of the row wording for a CSV and a JSON file.
- Step 4, second commit: context tests of the totals with exact `Decimal` values. `absorbing_balances/1`, the function that sums a correction per cash account, has no direct test today.
- Step 6: unit tests of the mapping merge on malformed input.
- Step 7: context tests of the moved rules, and one test that the two translations agree on every complete mapping.
- Step 8: a browser test of the open picker: focus after a pick, the disclosure still open after a patch. No server test sees focus or open state.

**Do not.**

- No LiveComponent (a part with its own state, events and root element) and no second page, for any part. The two writes stay page events (`:1399` the import, `:1486` the correction); a root element breaks seven stylesheet rules that select by child or sibling (`priv/static/app.css:4852`, `:4979` among them); a value that moves into a component leaves the remount test quiet instead of red (`test/portfolixir_web/live/imports_parked_preview_remount_test.exs:303-362`).
- Do not let the context module parse the form's strings or build a sentence. The test that forbids a page to parse an id by itself scans the web layer only (`test/portfolixir_web/live/live_param_sweep_test.exs:76-78`), so an id parsed in `lib/portfolixir/imports/mapping.ex` escapes it. The seven error sentences stay in the page (`:4793`, `:4806`, `:4810`, `:4830`, `:4874`, `:4881`, `:4898`); a rule answers a reason.
- Do not merge the two translations while moving them. They differ on purpose: the dry run takes every readable choice, the import only complete rows (`:1971-1982` against `:4865-4899`); the dry run counts a flagged creation the operator has not confirmed, the import refuses it (`:2006-2007` against `:4802-4807`).
- Do not change what is parked, and rename nothing: no stored value (`:122-132`), id, `data-role` or class. Two tests build the parked mapping by hand (`test/portfolixir_web/live/imports_parked_preview_cost_test.exs:114-127`, `test/portfolixir_web/live/imports_security_mapping_bound_test.exs:174`). For the same reason the R-154 (O3-02) fix must not keep the flag beside the dry run's answer: the mapping is parked on every change (`:1335`), and a remount reads the flag from it (`:171`, `:1958-1961`). Keep each security row's hidden choice field before its cards (`:850`).
- Do not move the dry run's start out of the page, and keep the two catch-all handlers (`:1464`, `:1515`), which answer an unknown event or message with no effect. The start schedules a message to the page (`:1891`) and the page handles the answer (`:1522-1548`); the list of modules allowed to schedule names the page (`test/invariants/scope_b5_system_writers_and_schedulers_test.exs:110`). A test requires the catch-all for events (`test/portfolixir_web/live/live_param_sweep_test.exs:59-75`).

**Decision or ADR.** Both. An amendment note on ADR-0050 (`docs/decisions/0050-lifecycle-merges-under-a-reimport-contract.md`) is signed before step 7, because that step moves the mapping rules out of the page while the ADR names the page as their home (ADR-0050 `:1079`), says "Apply refuses the name unmapped" although only the page's confirm refuses it (ADR-0050 `:770-771`), and lists what a later import route inherits without these rules (ADR-0050 `:609-610`). Remembering "on by default" (ADR-0050 `:242-243`) stays as decided. The project's rules ask for the note: `AGENTS.md` ("Do not silently change architecture decisions") and `docs/development/sprint-workflow.md:302-320` (import idempotency is risk tier). Steps 2 to 6 and 8 need no ADR and no board, since the picture is identical (`docs/development/sprint-workflow.md:295-297`); step 1 is a behaviour fix and needs no ADR either. The owner decides whether step 7 happens: the alternative keeps the rules in the page, corrects the description at `lib/portfolixir/imports/mapping.ex:2-9` and accepts the five test copies. Without step 7 the file stays at about 2,790 lines after step 6; whether step 8 can follow without it was not checked.

**Findings that ride along.**

- R-154 (O3-02): fixed first, in step 1: a confirm that stays on the preview drops the recount flag, and the re-read of accounts starts the dry run too early.
- R-056 (O3-04): the correction's totals, computed twice, get one home in step 4; the held-back count per portfolio, also computed twice, has no step yet.
- R-055 (O3-01): fixed by step 7: `lib/portfolixir/imports/mapping.ex` gets the two jobs its description claims, and the five test copies go.
- R-137 (O3-03): the ADR-0050 note before step 7 says who refuses an unmapped new name and what an import route inherits; step 7 gives the nine rules one home.
- R-115 (O3-05): the size and the twelve jobs; the whole split is its fix, the six chains excepted.
- Security lens N-22, N-41, N-50, N-57: not fixed here; the two writes stay on the page and the dry run's start stays beside its answer, so their remedies still fit.

---

**What applies to the next two files (`lib/portfolixir_web/live/classifications_live.ex`, `lib/portfolixir_web/live/transaction_management_live.ex`).**
Two boundary tests read each screen module's (LiveView's) own source through
`test/support/live_source.ex` and send bad input to every event and URL key they find there (`live_event_payload_test.exs:62`,
`live_url_params_test.exs:64`); a third checks from the same source that the module ends with a catch-all event clause
(`live_param_sweep_test.exs:70`). All three are under `test/portfolixir_web/live/`. If an event clause
(the function that answers one click or form change) hands its work to another module, the first two check less and stay green.
So every event clause and its payload reads stay in the screen module's file; only markup without state of its own
(function components), pure helpers and state builders move. In each section a bare `:123` is a line of that section's file.

### `lib/portfolixir_web/live/classifications_live.ex` (3,717 lines at e014f284)

**Jobs it does today.** Seven jobs cover 3,683 of the file's 3,717 lines.

| Job | About lines | What it does |
|---|---|---|
| Page shell, scope and result | 456 | Opens a tree in the active view's scope, starts the two background reads (holdings and category results), shows the page's one result message, falls back to "Everything" when the view is gone. |
| Tree index and create | 262 | Lists every tree with its size, assignment state and plan; creates a tree. |
| Category editing | 371 | Adds, renames, moves and recolours a category; refuses a parent past the depth bound. |
| Assignment and tree model | 442 | Search, "current positions only", drag and bulk move, unassign, the Unsorted list; builds the tree the screen draws. |
| Category results | 510 | Positions, Value, Cost and Result per row; the basis line; the note that names members left out. |
| Target-plan editor | 1,456 | Target weights per category and per position, the cash target, the live Σ, plan versions, copy from another view, refusals named by row. |
| Delete dialog glue | 186 | Opens the delete preview for a tree or a category, confirms it, re-checks it. |

**Proposed split.**

| New module (path) | Kind | Takes | About lines |
|---|---|---|---|
| `lib/portfolixir_web/live/classifications/excluded_note.ex` | function-component module | The note that names the members a category result leaves out, with its 13 helpers (`:845-1095`). | 255 |
| `lib/portfolixir_web/live/classifications/plan_form.ex` | plain module | Parsing and conversion of the plan form's inputs, nothing else (`:3057-3109`, `:3209-3309`); `blank_position?/3`, which tells a cleared position input from an absent one (`:3180-3193`); `put_in_nested/4`, a small map helper. | 190 |
| `lib/portfolixir_web/live/classifications/plan_sums.ex` | plain module | The plan's Σ, its remainder, the children's Σ and the weights the plan steers by (`:2376-2396`, `:2470-2536`, `:2569-2614`), as steps 1 and 2 leave them on the page: the call into the context's function and the conversion of the form's values. The tree's shape comes in as an argument and is never stored. | 140 at e014f284, fewer after step 2 |
| `lib/portfolixir_web/live/classifications/tree_view.ex` | plain module | `build_view/4`, which builds the tree the screen draws, and its node functions (`:2749-2962`); the lookups three jobs share (a category's name, its ancestors, the parent choices, the indent). Each row's counts and value are computed once per node. | 260 |
| `lib/portfolixir_web/live/classifications/tree_components.ex` | function-component module | `category_node/1`, one tree row with its edit form, result cells and drop-zone attributes; the security row, the figure cells, the labels and the colour swatch; the Unsorted block (`:562-598`) and the tree head (`:526-536`), without a wrapper element. | 420 |
| `lib/portfolixir_web/live/classifications/plan_editor.ex` | function-component module | `soll_editor/1`, the plan editor's markup (`:1286-1619`); `build_soll/5`, which builds the editor's state for the page to keep; copy from another view; `refused_input/1`, which names the input a refusal points at, beside the markup that defines those ids; the refusal texts (`:3518-3629`). | 720 |
| a shared home for the plan status label (path chosen in step 5) | plain module | `plan_status_label/1`, the words "active", "draft" and "archived" (`:3205-3207`), and the same three words at `lib/portfolixir_web/live/securities/merge_preview.ex:862-865` (`plan_status/1`, which takes atoms and passes an unknown status through, where this one takes strings and reads any other status as "archived"). The shared function has to settle both differences. | 10 |
| `lib/portfolixir_web/live/delete_preview_dialog.ex` (exists; plain functions added) | plain module | The cancel, confirm and re-check glue that this page (`:1758-1784`, `:3407-3456`) and `lib/portfolixir_web/live/buckets_live.ex` (`:763-783`, `:1002-1047`) both repeat. About 70 lines leave each page. | 60 added |
| `lib/portfolixir/classifications.ex` | context function | `get_tree/1`, a read of one tree where the page reads all trees today (`:2617`); `tree_summaries/0`, the counts and depth per tree, with 0 levels for an empty tree (`:226-242`, `:259-280`, `:3468-3479`). | about 60 |
| a new function in the Portfolios context, under `lib/portfolixir/portfolios/` | context function | A plan's Σ, remainder and children's Σ over fractions, called by the allocation engine and by the page's sum code, which step 3 moves to `plan_sums.ex`. New code, not a move. | new code |
| `lib/portfolixir/portfolios/targets.ex` | context function | The plan save's three write rules, inside `Targets.edit_plan/5` (the save of a whole plan in one transaction): the category follows its positions, the last cleared position takes the category row with it, an unchanged stale row is not sent (`:3111-3178`). With them goes the rule step 1 adds to `soll_clears/4` for R-014 (G1-01): a stored category row sent back blank is deleted. | about 70 |
| the index and create pages (`:610-793`) | stays in place | Optional last step: a screen module of its own, `PortfolixirWeb.ClassificationIndexLive`, with 3 events. | 240 if taken |

Two more context moves are listed without a step: one pure module in the Classifications context for the tree's shape (order, children by parent, ancestors, depth), which the page and three contexts each compute for themselves today, and the rule for what a tree allows (edit, assign, reclassify; `:2800-2806`).

**What is left.** About 1,650 lines after steps 1 to 7, about 1,400 with the optional step 8; the 33 event clauses alone are 340 lines (`:1621-1960`). The file still owns mount and routing, the scope, the two background reads, the one result message, every event clause, the tree page's template with its toolbar and forms, the plan's write glue and the decision what an edit reloads.

**Order of work.**

1. Changes behaviour, in place, before any move. Three fixes, each with its failing test first. The plan editor takes the tree's shape, the members and the assigned counts from the unfiltered tree on every render and stores none of them. That ends the stale Σ after a tree edit (R-015 (O4-02)) and the search text that changes the plan's warning. The third fix is R-014 (G1-01)'s: a few lines in `soll_clears/4` (`:3141-3161`), so that the save deletes a stored category row the form sent back blank.
2. Changes behaviour, risk tier (work on a money figure, with its own commit group and verification pass), before any move. The plan sums into the context, with a failing test first; the engine and the page's sum code (`:2470-2536`, `:2569-2614`) call the one function (R-003 (O4-01)). It waits for the owner's decision on R-003 (O4-01) and the ADR-0040 amendment, and the moves of steps 3 to 5 wait for it.
3. Move only. Three leaf modules, one commit each: `excluded_note.ex`, then `plan_form.ex` (parsing only, no markup changes), then `plan_sums.ex` (the sum code as step 2 left it, a caller of the context's function; `put_sum/1`, which writes the Σ into the editor's state, shrinks to formatting the result). The first commit edits the path in `test/invariants/css_status_region_test.exs:20`.
4. Move only. `tree_view.ex` with the shared lookups; then the missing pin test, which passes today (see Pins); then `tree_components.ex`. The page keeps its template with the toolbar and the forms.
5. Move only. `plan_editor.ex`: markup and state builder. The 11 plan event clauses and the write glue stay on the page. Before the move, the plan status label and the page's two error-wording helpers that the refusal texts call (`:3546`, `:3550`) need a home another module can reach. `_bmad-output/planning-artifacts/design-language/DESIGN.md:5350-5351` names `soll_editor/1` in this file and is updated here.
6. Changes behaviour (fewer queries, same screen). `get_tree/1` and `tree_summaries/0` in the context; `reload/1`, the page's re-read after an edit or a keystroke, reads one tree and no longer all of them.
7. Changes behaviour, risk tier. The three write rules, and with them step 1's rule for a blanked category row, into `Targets.edit_plan/5`; the page hands over the parsed rows. ADR-0030 is amended first, and the PR states the API and MCP coverage. A plan that schedules the plan fixes ahead of the split (section 11 of the triage) can take this step with steps 1 and 2: the rules stay on the page through steps 3 to 6.
8. Optional, move only. The delete glue into `delete_preview_dialog.ex` for both pages, and a home another module can reach for the result helpers the create event (`:1637`) and the create page (`:617`) call (`failure/2` and `page_result/2`, `:3311-3326`; `changeset_error/1` got its home in step 5); then `ClassificationIndexLive`, which changes the router and needs a catch-all event clause (the last clause, which takes any unknown event), or `test/portfolixir_web/live/live_param_sweep_test.exs:57-73` fails.

**Pins before the first move.** The existing tests sit under `test/portfolixir_web/live/` unless a path says otherwise.

- Step 3: `classifications_result_reload_test.exs` (8 tests) and `classification_tree_rows_test.exs:213` for the note; `classifications_position_targets_test.exs` (11) and `target_weight_legacy_test.exs` for the parsing; `classifications_plan_remainder_test.exs` and `classifications_live_test.exs:860-917` for the sums.
- Step 4: `classification_tree_rows_test.exs` (6), `classifications_view_scope_test.exs` (18), `classifications_partial_value_test.exs`, `classifications_polish_live_test.exs`, `classification_cost_tooltip_test.exs`.
- Step 5: `classifications_plan_versions_test.exs` (11) and the plan tests of step 3; tests address the form `#soll-plan-form` 29 times.
- Steps 6 and 8: step 4's tests and `classifications_index_rows_test.exs`; `delete_preview_dialog_live_test.exs`, `shared_components_live_test.exs:122`, `live_id_range_test.exs:43`.
- Missing, to be written before `tree_components.ex` moves: a test for the drop-zone attributes (the markers the drag-and-drop script reads) of every category, of Unsorted and of the workspace, and for which blocks are direct children of `.classifications-detail`. No test asserts a drop-zone attribute today, and no browser test drags. The failing tests of steps 1 and 2 are also new: three in step 1 (the third is R-014 (G1-01)'s reproduction with its assertions inverted) and R-003 (O4-01)'s in step 2. The plan's warning has one test today, without a search text (`classifications_live_test.exs:74-122`).
- A pure move breaks `test/invariants/css_status_region_test.exs:20`, which names this file, and the translation template `priv/gettext/default.pot` (192 reference lines name this file; re-extract with every move). `test/invariants/destructive_confirmations_test.exs:12` holds as long as the selection toolbar stays on the page. `test/portfolixir/localization_test.exs:133` lists this file by name; strings that move to a new file leave that check without a failure.

**Do not.**

- No LiveComponent (a page part with its own state and events) for the tree or the plan editor, now or later, until the page's result is a message and N-57 is fixed. The drag-and-drop script pushes to the page (`lib/portfolixir_web/layout_view.ex:2168-2206`) and 29 test pushes name the tree's events; a plan write also changes the page's result, the view switcher's plan dots (`:2243`) and the scope (`:128-143`, `:1976`).
- No wrapper element around a moved block. The stylesheet addresses the page's direct children (`priv/static/app.css:6130`, `:6141`, `:6145`); `test/invariants/css_layout_sweep_test.exs:114-120` pins the rules, not which elements are direct children.
- Do not keep the tree's shape or the assignments in the editor's state (`:2346-2369`, `:2354`). That copy is R-015 (O4-02), and the editor's second read of "what is filed in this category" (`:2540-2564`) goes stale after an assignment.
- Do not move `put_sum/1` into a context as it is: it formats for the page (`:2488`, `:2491`, `:2498`) and reads percent values that are strings after a load (`:2307`) and decimals after a keystroke (`:2403`). `visible_value/1`, the value of the visible rows (`:2935-2945`), stays in the web layer. Do not merge `tree_summaries/0` with the context's private depth function, which answers 1 for an empty tree on purpose (`lib/portfolixir/classifications.ex:169-183`); the page answers 0 (`:3470-3477`).
- Do not derive the editor's position rows from the write rule, and do not hand the save's snapshots into the context. The editor offers a security under the category it is assigned to (`:2541-2548`); the write accepts it under any ancestor too (`lib/portfolixir/portfolios/targets.ex:1492-1500`). The stored and stale position rows (`:2356`, `:2357-2363`) must be read inside the transaction.

**Decision or ADR.** Steps 1, 3 to 6 and 8 need none: they are fixes in place, web-internal moves or an added read. Step 2 needs an owner decision and then an amendment of `docs/decisions/0040-unallocated-remainder-in-target-plans.md` (§1 and §2), because the editor rolls up the children of a top-level category without a weight of its own and the allocation engine does not, and one rule has to win for Σ, "Not allocated" and the base every drift is measured against. The new function must also agree on two rules the editor and the engine each hold today: the engine adds no cash target on the currency tree (`lib/portfolixir/portfolios/allocation.ex:519-525`) and the editor has no such branch (`:2485`); and "positions win over the category row" (`lib/portfolixir/portfolios/targets.ex:191-216`, `:2518-2536`). Step 7 needs an amendment of ADR-0030, because `docs/decisions/0030-position-level-soll-targets.md:76-78` says no row is overwritten while the built editor overwrites the category row with its positions' sum, and `docs/decisions/0030-position-level-soll-targets.md:175-177` still calls the editor deferred; the same amendment takes the sentence for step 1's blank rule (R-014 (G1-01)), which no ADR states today. Both steps are risk tier under `docs/decisions/0036-risk-tier-rides-the-batch.md`, and `AGENTS.md` ("Do not silently change architecture decisions") rules out either step without its amendment.

**Findings that ride along.**

- R-003 (O4-01) (S1): the editor's Σ and the engine's Σ differ for a top-level category without a weight of its own; fixed by step 2, before the first move.
- R-015 (O4-02) (S2): the plan editor keeps the tree it read before a tree edit; fixed by step 1.
- R-014 (G1-01) (S2): a stored category weight blanked in the editor is not deleted by "Save plan"; fixed by step 1. Its code then moves with the split: `parse_weight_entries/1` (`:3059-3078`) to `plan_form.ex` in step 3, and the rule in `soll_clears/4` (`:3141-3161`) into `Targets.edit_plan/5` in step 7, as a fourth write rule.
- R-027 (G1-03) (S2) and R-029 (G1-05) (S2): "Delete plan" leaves the view's cash target steering, and deletes by the status the editor loaded. Not fixed by this split; their fixes land before step 5 (section 11 of the triage, step 2). That step moves the code they change: the Cash row, the confirm text and the empty state inside `soll_editor/1` (`:1517-1541`, `:1568-1575`, `:1592-1601`). `delete_soll_plan/1` (`:2073-2098`) is write glue and stays on the page.
- R-028 (G1-04) (S2): on a built-in tree the page renders no plan control and nothing in its place (`:2270-2271`). Not fixed by this split; the site stays on the page. Its fix lands with section 11 of the triage, step 2.
- R-057 (O4-03): the plan save's write rules live in the page, and the API has no plan edit in one transaction; fixed by step 7.
- R-064 (O4-05): every search keystroke reloads all trees; fixed by step 6.
- R-149 (O4-09): two event handlers without a sender, and six test pushes that use them; independent of the moves, best done before step 4 so that the tests drive the events a drag really sends.
- No key yet (found while reviewing the split): any search text makes the plan editor warn "no assigned positions" for every targeted category without a matching security (`:2770`, `:2809`, `:2905-2916`). Predicted, not run; S2 if it reproduces; fixed by step 1.
- N-57 (events sent to a LiveComponent skip the per-event session re-check): the reason for function components; not fixed here.
- N-70 (two crafted events crash the tree page): fixed in place by its own remedy; it is no reason for step 8.

### `lib/portfolixir_web/live/transaction_management_live.ex` (3,502 lines at e014f284)

**Jobs it does today.** Nine rows cover 3,462 of the file's 3,502 lines. With its three helper files under `lib/portfolixir_web/live/transactions/` the screen is 5,027 lines.

| Job | About lines | What it does |
|---|---|---|
| Page shell and data load | 195 | Frame, tabs, the one result message, the URL filters; reloads the whole ledger after every write. |
| History list and filters | 1,148 | Table and phone rows by month, the summary per kind and currency, the filter chips and the phone's filter sheet, the column picker, the row menu, the running balance, the rows of a ledger check. |
| Row figures | 151 | The money a booking moved, its sign, currency and size. Five other web modules call public functions of this file, 11 call sites in all. |
| Trade drawer | 844 | Books and corrects a buy or sell, with the cross-currency settlement. |
| Stated cash | 149 | The stored cash field of a buy or sell that stores its cash and no settlement amount, and its restate note. |
| Sell preview | 184 | The lots a sale would consume, oldest first. |
| Cash drawer | 316 | Books and corrects the seven one-amount cash kinds, such as deposit, dividend and fee. |
| Notes-only drawer | 391 | Shows a booking of a kind the screen does not book: the facts fixed, the note editable. |
| Delete | 84 | Opens and confirms the delete dialog; the dialog itself is `lib/portfolixir_web/live/transactions/booking_delete_dialog.ex`. |

**Proposed split.**

| New module (path) | Kind | Takes | About lines |
|---|---|---|---|
| `lib/portfolixir_web/format.ex` (exists) | plain module | The three number formats other screens use: `stored_figure/1` (a stored price with the digits it was stored with), `plural_count/1` (whether a quantity reads "unit" or "units"), `format_quantity/1` (a quantity as shown). Removes the copy at `lib/portfolixir_web/live/transactions/booking_delete_dialog.ex:796-800`. | 55 |
| `lib/portfolixir_web/live/transactions/figures.ex` | plain module | A booking's money as the history shows it: amount, sign, currency, size, split ratio (`:2123-2127`, `:2219-2221`, `:2233-2268`, `:2280-2369`). Removes the copy of the split ratio label at `lib/portfolixir_web/live/securities_live.ex:3896-3900`. | 140 |
| `lib/portfolixir_web/live/transactions/booking_drawer.ex` | function-component module | One drawer shell with a slot, where two copies exist today (`:2447-2475`, `:2828-2873`); the three parts every form uses: the field error, the security option label, the date field value. | 100 |
| `lib/portfolixir_web/live/transactions/notes_form.ex` | function-component module | The note form, the fixed facts and the help lines of the notes-only drawer (`:2476-2539`, `:2544-2717`, `:2754-2765`). | 290 |
| `lib/portfolixir_web/live/transactions/history_filters.ex` | function-component module | The filter chips and "More filters" (`:1719-1876`), the filter options (`:1992-2014`), and the pure matchers that filter the loaded history in memory (`:1582-1654`). | 255 |
| `lib/portfolixir_web/live/transactions/sell_preview.ex` | function-component module | The computation of the lots a sale consumes, and the lot table (`:2129-2196`, `:3160-3275`). | 185 |
| `lib/portfolixir_web/live/transactions/stated_cash_field.ex` | plain module | The stated-cash field and its restate note (`:1317-1435`, `:2791-2803`); the two currencies of a cross-currency trade come in as an argument. `stored_cash/1` (`:1300-1315`) is one of the drawer's mode decisions and goes to `drawer.ex`. | 130 |
| `lib/portfolixir_web/live/transactions/cash_form.ex` | function-component module | The cash form's markup, its "Credited to / Debited from" line and its security options (`:3280-3484`). | 205 |
| `lib/portfolixir_web/live/transactions/trade_form.ex` | function-component module | The trade form alone (`:2889-3159`) and the depot labels (`:2371-2383`). | 285 |
| `lib/portfolixir_web/live/transactions/history_table.ex` | function-component module | The summary, the table, the phone rows, the month groups (computed once, not once per list), the column registry, the account names, the row's menu button (`:324-543`, `:1656-1692`, `:1894-1990`, `:2028-2116`, `:2198-2207`, `:2230-2231`). | 460 |
| `lib/portfolixir_web/live/transactions/drawer.ex` | schema or struct | The drawer's nine pieces of state as one value with pure transitions (closed, new, edit of a stored row, changed, refused), and the decisions which form a stored row opens in (`:1015-1072`, `:1277-1315`). | 180 |
| `lib/portfolixir/ledger/projection.ex`, `lib/portfolixir/ledger.ex`, `lib/portfolixir/ledger/transaction.ex` | context function | Which way a kind moves cash; a booking's displayed money and the sums per kind; which kinds name a security or carry taxes; the shape of a stored row that decides how it may be corrected; the attributes of a cross-currency booking; portfolio and currency of a new booking; what a delete changes. Each with its API and MCP change. | new code |
| the filter sheet (`:266-322`), the row menu (`:554-589`), the three dialogs, the save paths | stays in place | The page renders the sheet and the menu after both lists. `save_cash/3`, the cash save, works on the page's state and calls three functions that stay (`:1089-1104`). | see below |

**What is left.** About 1,200 lines after steps 1 to 6, about 1,050 after step 7; the 24 event clauses alone are 286 lines (`:632-917`). The file still owns mount and the URL filters, `load_state/1` (the full reload after every write), applying the filters, the page's template with the filter sheet, the row menu and the three dialogs, every event clause and the save paths.

**Order of work.**

1. Move only. The three number formats into `format.ex`, then `figures.ex`. This changes the 11 call sites in 5 other modules and 4 test lines; it removes two duplicate functions and the delete dialog's call back into the page (`lib/portfolixir_web/live/transactions/booking_delete_dialog.ex:355-356`). One of the 11 call sites is `lib/portfolixir_web/live/income_live.ex:1791`: step 2 of the Cash flow split names the same move of `plural_count/1`, and the split that runs first makes it.
2. Move only. `booking_drawer.ex`, one shell for both drawers with the shared form parts, then `notes_form.ex`. The `save_note` event stays on the page, and the notes-only guard clause of `save_transaction` (`:635-640`) stays before the clause at `:856`. The entry in `test/invariants/displayed_dates_test.exs:44` moves once.
3. Move only. `history_filters.ex`, `sell_preview.ex`, `stated_cash_field.ex`. Applying the filters stays on the page; the order inside `form_changed`, the event for every change of the form (`:686-707`), does not change.
4. Move only. `cash_form.ex`, then `trade_form.ex`. The drawer's state and the save paths stay on the page.
5. Changes behaviour. First a failing test for the drawer's mode after a save into a deleted row. Then `drawer.ex`: one value for the drawer and one way to close it. The test needs none of steps 1 to 4 and can be run first to learn whether the defect is real.
6. Move only. `history_table.ex`, both lists, no paging. The filter sheet, the row menu and the dialogs stay on the page.
7. Changes behaviour, risk tier for the money rules (their own commit group and verification pass). The context moves, each with its API and MCP change; the save paths and `figures.ex` get thinner. N-32 and N-05 come before the row classification.
8. Changes behaviour. Paging (R-011 (O4-04)), with its own decision and board. The eight kinds of reader that use the whole loaded history each get a read of their own. It stays last although R-011 (O4-04) is an S2: it changes the structure after an owner decision and a board, and it is no figure fix that a move could bury.

**Pins before the first move.** The existing tests sit under `test/portfolixir_web/live/` unless a path says otherwise.

- Step 1: `test/portfolixir_web/format_test.exs`, `transaction_history_sign_price_test.exs`, `privacy_open_states_test.exs`. Four test lines call the page's functions and change with the move: `transaction_history_cash_moved_test.exs:202`, `:203`, `:287` and `privacy_open_states_test.exs:392`.
- Step 2: `transaction_notes_drawer_live_test.exs` (7 tests); tests address `#booking-drawer` 65 times in 14 files.
- Step 3: `changed_since_view_test.exs`, `transaction_filter_sheet_test.exs`, `transaction_history_u1_live_test.exs`, `transaction_sell_preview_test.exs` (8), `booking_drawer_stated_cash_test.exs` (10).
- Steps 4 and 5: `booking_drawer_cash_kinds_live_test.exs` (8), `transaction_settlement_form_test.exs` (10), `decimal_inputs_live_test.exs` (10), `booking_drawer_legless_row_test.exs`; for step 5 also `transaction_management_live_test.exs` (34).
- Step 6: `phone_rows_live_test.exs`, `column_picker_view_test.exs`, `ledger_checks_live_test.exs`; tests address `#transaction-list` 70 times in 18 files.
- Missing: no test covers the drawer's mode after a save into a deleted row; step 5 writes it first. The order inside `form_changed` is held only through end results, and only a browser run sees where the focus returns after a drawer closes. The translation template `priv/gettext/default.pot` names this file in 181 reference lines; re-extract with every move.

**Do not.**

- Not three drawer modules with a shell each: one shell, three forms. Two dialogs share the id `booking-drawer` (`:2448`, `:2829`) and two forms the id `transaction-form` (`:2891`, `:3314`); tests address them 65 and 103 times.
- Not the drawer's nine pieces of state divided among the forms. The reset is written four times (`:661-673`, `:994-1005`, `:1197-1209`, `:1218-1225`), and the fourth resets three of the nine.
- No LiveComponent for the drawers or the table before N-57 is fixed: 27 test pushes name the page's drawer events, the column-preferences script and the row menu push to the page (`lib/portfolixir_web/layout_view.ex:263`, `:743`), and the reload after every write is the page's.
- Not paging inside the table's move, and not the filters into the query before the paging decision. Eight kinds of reader rely on the whole history in memory, among them the running balance (`:1575`), the delete dialog's context (`:1182`) and the filter option lists (`:1768`, `:1786`, `:1837`).
- Not the table's cell classes or the phone row's subject line (`:2198-2207`, `:2230-2231`) into `figures.ex`: they call the history's account names (`:2081-2103`), so `figures.ex` and `history_table.ex` would call each other. The money rules stay in one function of `figures.ex` until step 7 and are not spread on the way to the context.

**Decision or ADR.** Steps 1 to 6 need none: they are web-internal. Step 5's defect, if it reproduces, breaks the amendment of 2026-11-01 to `docs/decisions/0015-cross-currency-settlement-fx-rate.md`, which keeps the stored-currency form for a stored row only; that is a fix, not an amendment. Step 7 needs no owner decision of its own: AD-4 decides that the cash a booking moved, the sums per kind and what a delete changes go onto the API and MCP (R-059 (O4-08)), and a comment flips it; `AGENTS.md` ("Coverage runs both ways") says a user-visible function gets that coverage or the PR says why not. The cash direction needs no amendment, because `docs/decisions/0011-unified-ledger-projection.md` already says each kind's effect is defined once. Step 7 changes the API contract and both integration documents. Step 8 needs an owner decision whether the history is paged, and a board first (`docs/development/sprint-workflow.md`: a UI change is mocked on a board before it is built).

**Findings that ride along.**

- R-116 (O4-06): five other web modules use this page as a formatting library, and the delete dialog calls back into it; fixed by step 1.
- R-058 (O4-07): which way a kind moves cash is kept in two hand-written lists beside the ledger's one reducer; fixed by step 7, and until then it stays in one function of `figures.ex`.
- R-059 (O4-08): three figures of this screen have no twin on the API or MCP; step 7, as AD-4 decides.
- R-011 (O4-04) (S2): the history has no paging and every row is rendered twice; step 6 computes the month groups once, step 8 is the paging.
- No key yet (found while reviewing the split): after an edit is saved into a row that is gone, the drawer keeps that row's mode (`:1218-1225`, `:651-659`), so the next new booking can go to the ledger in the deleted row's currency and without the settlement path. Predicted, not run; S2 if it reproduces, S1 if the ledger accepts the write; fixed by step 5.
- N-32 (the settlement mode travels in a hidden field) and N-05 (the scope of the stated-cash rule): they land in the same code and come before step 7's row classification.
- N-57 (events sent to a LiveComponent skip the per-event session re-check): the reason for function components; not fixed here.

---

**What applies to the next five files (`lib/portfolixir_web/live/income_live.ex`, `lib/portfolixir_web/live/portfolio_accounts_live.ex`, `lib/portfolixir_web/live/dashboard_live.ex`, `lib/portfolixir_web/live/securities/merge_preview.ex`, `lib/portfolixir_web/live/portfolio_accounts/merge_preview.ex`).**
Every new web module is a function-component module (markup functions, no state, no events); a
context is a domain module under `lib/portfolixir/`. Every event, message and background-result clause stays written out in the file
that owns the state: the test that fires malformed events reads the clauses from that file (`test/support/live_source.ex:19-33`).
None becomes a LiveComponent (a part with state and events of its own): its events skip the per-event session re-check (security
finding N-57, `lib/portfolixir_web/live_ui_auth.ex:41`). Each move shifts source references in the translation catalogue (`priv/gettext`):
re-extract in the same step; a diff of reference lines only proves a pure move. Known defects are fixed in place, test first, before their code moves.

### `lib/portfolixir_web/live/income_live.ex` (1,811 lines at e014f284)

**Jobs it does today.**

| Job | About lines | What it does |
|---|---|---|
| Page frame and facet switch | 130 | Title, area tabs, the switch between the four facets (the sub-pages Income, Trades, Deposits & withdrawals, Costs), the empty state. |
| Income facet | 665 | Year bars, the year × month table, the drilled year, top contributors, the list per position. Owns the two year events. |
| Trades facet | 595 | The sales left out of the totals and why, three figures, the trades table, "After the sale", the year × month table. |
| Deposits & withdrawals facet | 90 | Its exclusion note and its year × month table. No function of its own. |
| Costs facet | 95 | Its exclusion note and its year × month table. No function of its own. |
| Rate backfill | 110 | The button that fetches missing exchange rates, its background run, and the re-read of every loaded facet afterwards. |
| Shared helpers | 25 | Three formatters (a table cell, a month name, a money figure) and the list of months. All four facets use them. |

**Proposed split.**

| New module (path) | Kind | Takes | About lines |
|---|---|---|---|
| `lib/portfolixir_web/live/cashflow/parts.ex` | function-component module | The three formatters, the months list, the backfill's reason sentence and its button. In step 7 two table parts: the twelve month headers and the twelve month cells. | 110 |
| `lib/portfolixir_web/live/cashflow/flows_facet.ex` and `costs_facet.ex` | function-component module | The Deposits & withdrawals facet (857-945) and the Costs facet (947-1040), one module each. | 95 each |
| `lib/portfolixir_web/live/cashflow/trades_facet.ex` | function-component module | The Trades facet with its sentences. The call that hosts "After the sale" stays inside it, between the same sections. | 600, about 500 after step 8 |
| `lib/portfolixir_web/live/cashflow/income_facet.ex` | function-component module | The Income facet with its bar geometry, and the bars and top-contributors computations that today run on every render of every facet (279-283). | 670 |
| `lib/portfolixir_web/excluded_sales.ex` (exists; names the reasons a sale is left out) | plain module | The reason sentences as two functions, one for Cash flow and one for the Overview. The 20 sentences stay written out. | 170 more |
| `lib/portfolixir_web/format.ex` (exists; the shared number formatter) | plain module | The four sign-colour clauses (1718-1725) and `plural_count/1` (picks singular or plural for a displayed quantity), which today lives on the Transactions page; step 1 of that page's split names the same move. | about 20 more |
| answer of `Portfolixir.Portfolios.Income.for_portfolio/2` (the income read the API serves) | context function | Three figures the page derives: top contributors (1543-1555), the running total per month (1655-1670), "no payment of this year is converted" (1592-1593). | about 30 leave the page |
| `lib/portfolixir_web/live/income_live.ex` | stays in place | Mount, address handling, the three loaders, the three events, the three background-result clauses, the re-read after a backfill, the frame. | 300 |

**What is left.** `income_live.ex` at about 300 lines. It owns the page's state, its three events (`select_year`, `clear_year`,
`backfill_rates`), the loaders, the re-read after a backfill and a frame with one call per facet. The three context figures follow
later, each as its own story with its computation basis in the API payload.

**Order of work.**

1. Check the lead on "After the sale": a backfill re-reads the trades list, but the hindsight part reloads only when the address
   changes (`lib/portfolixir_web/live/sale_hindsight_section.ex:82-91`), so it may keep figures from older rates. Read, not run.
   If it holds, fix it in place with a failing test first. Changes behaviour.
2. The four sign-colour clauses become functions of `Format` (one commit group with the Overview's step 3), and `plural_count/1` with them
   unless step 1 of the Transactions split has already moved it. Move only.
3. `Cashflow.Parts`: the shared helpers and the two backfill pieces become public; no markup changes. Move only. Leaves about 1,715 lines.
4. `FlowsFacet` and `CostsFacet`. Move only. Leaves about 1,545.
5. `TradesFacet`. Move only. Leaves about 965.
6. `IncomeFacet` with the two computations of 279-283, which then run only while the Income facet is open. Move only. Leaves about 300.
7. Month headers and month cells replace 4 header loops and 8 cell loops in the four tables. Move only, but the markup is produced
   differently: compare the rendered HTML before and after. Saves about 45 lines.
8. The reason sentences move into `ExcludedSales`, together with the Overview's closed-trades card. Move only, same comparison; the
   catalogue diff shows no changed sentence.

**Pins before the first move.** 22 LiveView test files open `/cashflow`; all select by id or `data-role`, which a move keeps. Under
`test/portfolixir_web/live/`: `cashflow_backfill_test.exs` and `income_live_test.exs:808-812` hold step 3; `income_live_test.exs:554`,
`:604`, `:644-648`, `cashflow_facets_live_test.exs` and `zero_figure_unsigned_test.exs:195-202` hold step 4; `realized_trades_live_test.exs`,
`cashflow_trades_exclusions_live_test.exs`, `sale_hindsight_live_test.exs:260` and `unconvertible_trade_live_test.exs` hold step 5;
`income_live_test.exs`, `income_unconverted_only_test.exs` and `privacy_charts_live_test.exs` hold step 6; `dashboard_trades_card_test.exs`
holds step 8. Missing, to write first: (a) a test that "After the sale" is fresh after a backfill (step 1; no test covers it);
(b) an assertion on the Deposits & withdrawals net row, which spans twelve columns (`income_live.ex:936`), and on the header rows,
before step 7; (c) the new module paths in the hand-kept list of `test/portfolixir/localization_test.exs:131-136`, in the step of
each move, or that check covers a tenth of the sentences it covers today. The two privacy wrappers (`income_live.ex:552`, `:1443`)
are read by the browser privacy walk only; run it at steps 5 and 6.

**Do not.**

- One slotted table for the four year × month tables. They differ in six places (`income_live.ex:829-833`, `:936`, `:1029-1031`,
  `:1270-1277`, `:1284`); four tables with shared headers and cells read better.
- One merged "left out" note for Cash flow and the Overview. They are two texts by decision
  (`lib/portfolixir_web/excluded_sales.ex:13-14`); one note needs a board first.
- A starting value of "nothing" for the three lazily loaded reads. The page tells "loaded" from the value's absence
  (`income_live.ex:259-261`); a default makes every backfill compute three more reports. Each facet is called inside the facet switch.
- A LiveComponent or a route per facet. One backfill refreshes everything the session loaded (`income_live.ex:249-255`), and the
  facets are query state on one route (`income_live.ex:67-71`).
- A facet module that still calls the Transactions page. `units/1` (`income_live.ex:1785-1794`) calls `plural_count/1` on a
  3,502-line page module; step 2, or step 1 of the Transactions split, removes that before step 5.

**Decision or ADR.** None. ADR-0022 (`docs/decisions/0022-task-oriented-information-architecture.md`) keeps the facets on one route
and the split follows it; the three later context figures fall under the computation-basis rule in `AGENTS.md`.

**Findings that ride along.**

- R-119 (O5-06): fixed by steps 3 to 6 (four facets in one render of about 1,250 lines).
- R-118 (O5-05): step 2 gives the sign-colour clauses and `plural_count/1` one home; step 8 does the same for the "left out" sentences.
- R-048 (A2-07): the top contributors and the running total, derived in the page, move into the income read after the split.
- A lead without a key (step 1): "After the sale" may stay stale after a backfill; S2 if a run confirms it.

### `lib/portfolixir_web/live/portfolio_accounts_live.ex` (1,693 lines at e014f284)

**Jobs it does today.**

| Job | About lines | What it does |
|---|---|---|
| Table and reload | 525 | One band per depot and cash account with balances, merge lines and merge records; the single reload after every write; the one result line. |
| Term info | 40 | The ⓘ explanation of a term. The table head, the liquidity-role select and the bucket cell use it. |
| Bucket chips | 310 | Add, remove and create a tag (bucket), the overflow, tagging a depot and its cash account separately. 8 event clauses. |
| Set balance | 145 | The dialog and the page's one ledger write. 3 event clauses. |
| Row lifecycle | 415 | The row menu, hosting the rename, merge and create dialogs, delete and its refusal. 8 event clauses and 7 message clauses. |
| Liquidity role | 50 | The in-row select and its write. 1 event clause. |

**Proposed split.**

| New module (path) | Kind | Takes | About lines |
|---|---|---|---|
| `lib/portfolixir_web/live/portfolio_accounts/balance_dialog.ex` | function-component module | The set-balance dialog's markup (386-462) and its example placeholder. It receives the account, the error, the invalid fields and the privacy mode. The three events and the ledger write stay on the page. | 95 |
| `lib/portfolixir_web/live/portfolio_accounts/term_info.ex` | function-component module | The ⓘ explanation of a term (707-746), which three jobs use. | 45 |
| `lib/portfolixir_web/live/portfolio_accounts/bucket_cell.ex` | function-component module | The chip list and one chip (782-950), the chip colour guard with its colour pattern, the limit of visible chips. The eight bucket events stay on the page. | 190 |
| `lib/portfolixir_web/live/portfolio_accounts/row_menu.ex` | function-component module | The row menu (583-662), which receives "this pair is tagged separately" from the page; the delete-refused dialog (664-705); the two functions that name a menu's and a menu button's DOM id; the menu's sentences (1325-1401). | 215 |
| `Portfolixir.Buckets.global_assignments/0` (exists, `lib/portfolixir/buckets.ex:995`; answers every account's tags at once) | context function | Replaces the tag reads at 1580, 1583 and 1601, which run one query per depot and per cash account at each of 13 reload sites. No new function. | 0 new |
| `Portfolixir.Lifecycle.Delete.referenced_by/1` (says what still refers to an account), or a filtered `Portfolios` list | context function | The names of the depots linked to a cash account, which the page finds by loading every depot (1301-1311). The page's own check before a delete (1259-1261) goes: the delete answers the same refusal itself. | about 15 leave the page |
| a new function in `Portfolixir.Buckets` beside `set_view_buckets/5` (`lib/portfolixir/buckets.ex:870`) | context function | A pair's tag set written to the depot and to its cash account as one locked write, in place of two writes and a repair on the page (1412-1429, 1450-1463). | about 30 leave the page |
| `lib/portfolixir_web/live/portfolio_accounts_live.ex` | stays in place | All 22 event clauses and 7 message clauses, the table, the writes, the reload, the result line, and `build_rows/3` (arranges the accounts into the bands on screen). | 1,150 |

**What is left.** `portfolio_accounts_live.ex` at about 1,150 lines. Its 29 event and message clauses (about 280 lines) and its table
(about 300 lines) are the page and cannot leave; the moves take out about 540 lines.

**Order of work.**

1. R-155 (O5-03)'s fix in `changeset_error/1` (builds the error sentence of a refused form), in place, with a failing test first. Both
   callers get it, the balance dialog and the tag picker. Changes behaviour.
2. `BalanceDialog`: the dialog's markup. Move only. Leaves about 1,620 lines.
3. `TermInfo`, then `BucketCell`. Move only. Leaves about 1,400.
4. `RowMenu`. The table then calls the DOM-id function instead of its two written-out ids (189, 573), and the site list of
   `test/invariants/destructive_confirmations_test.exs:13` names the new file. Move only. Leaves about 1,195.
5. `build_rows/3` reads `Buckets.global_assignments/0`. Move only in effect: the same bands from one query instead of one per account.
6. The check before a delete goes, and the linked depots' names come from the context. Changes behaviour in the context's answer;
   the screen's wording stays. Leaves about 1,180.
7. The pair write as one transaction: its own story, test first, its own commit group. Changes behaviour: a refused pair edit then
   leaves nothing half-written. Leaves about 1,150.

**Pins before the first move.** Under `test/portfolixir_web/live/` unless a path says otherwise. Step 2: `decimal_inputs_live_test.exs:470-495`
and `:567-590`, `portfolio_accounts_live_test.exs:1405-1450`, `stored_names_isolated_test.exs:152-153`, `privacy_open_states_test.exs:335-348`,
`test/browser/privacy_leak_test.exs:278-279`. Step 3: `accounts_bucket_cell_test.exs`, `accounts_card_band_test.exs` and the 10 bucket
events that tests push to the page by name. Step 4: `accounts_delete_confirm_test.exs`, `accounts_lifecycle_live_test.exs`,
`test/invariants/destructive_confirmations_test.exs:13` (fails loudly until its path follows), `test/browser/securities_polish.js:95-117`
(focus return, which runs in the browser only). Steps 5 and 6: `portfolio_accounts_live_test.exs`, `accounts_card_band_test.exs` and the
two delete tests. `test/invariants/native_dialog_test.exs` counts dialogs and their opening script hook per file, so each dialog moves
with its hook. Missing, to write first: (a) a test of the error sentence's text, since today's tests assert only that the error
element exists: R-155 (O5-03)'s reproduction with its assertions inverted, before step 1; (b) a test of the refused second write of a pair
edit (`portfolio_accounts_live.ex:1456-1461`), before step 7.

**Do not.**

- A LiveComponent for the balance dialog before N-57 is fixed. It holds the page's one ledger write
  (`portfolio_accounts_live.ex:974`) and reads the privacy mode (`:446`), which a component does not inherit.
- A LiveComponent for the row menu or the bucket cell. The shared menu script closes a menu with an event that reaches the page
  only (`lib/portfolixir_web/layout_view.ex:743`), and tests push 14 events to the page by name.
- R-155 (O5-03)'s fix inside the moved dialog. The helper has a second caller, the tag picker (`portfolio_accounts_live.ex:1188`), which
  would stay raw or get a copy.
- The row menu moved as it is. It asks the page whether a pair is tagged separately (`:599`); the page computes that and passes
  it. `menu_open?/3` (`:1316-1317`) and `scope_line/1` (`:1631-1633`) belong to the table and stay.
- `build_rows/3` in a context. It decides which band shows a shared cash account's controls so that no DOM id appears twice
  (`:1565-1566`): a screen matter.

**Decision or ADR.** No ADR amendment and no owner decision for steps 1 to 6. Step 7 is risk-tier work on journaled writes under
ADR-0017 (`docs/decisions/0017-append-only-audit-journal.md`) and ADR-0036 (`docs/decisions/0036-risk-tier-rides-the-batch.md`): own
commit group, own verification pass, and its PR states the changed outcome of a refused pair edit.

**Findings that ride along.**

- R-155 (O5-03): fixed first (step 1): the raw, untranslated error sentence in the balance dialog and the tag picker.
- R-119 (O5-06): fixed as far as the page allows; it stays long because its event clauses and its table are the page.
- R-118 (O5-05): not fixed here; the result line is still written two ways (`:1017`, `:1225`) and the reload stays private to the page.
- N-57 and N-65 (security triage): N-57 is why no part becomes a LiveComponent; the chip colour guard N-65 names moves together
  with its colour pattern.

### `lib/portfolixir_web/live/dashboard_live.ex` (1,544 lines at e014f284)

**Jobs it does today.**

| Job | About lines | What it does |
|---|---|---|
| Frame, mode switch, failure | 120 | Chooses onboarding or overview by whether any booking exists, starts the two background reads, holds the load-failed note. |
| Onboarding | 50 | The workflow path and the counts on an empty database. |
| Value card | 265 | Total, year-to-date return, the last known figure while computing, what the total leaves out. |
| Key-figure strip | 180 | One-year return, cash quote, last booking, quote freshness. |
| Closed trades | 260 | The newest five closed trades and their exclusions. Its own background read with its own three states. |
| Off target | 215 | Categories more than 5 percentage points from target, decided by a rule written in the page. |
| Due | 85 | Dated facts in the next 30 days. |
| Data quality | 290 | One line of findings with links, and the ten counts behind it. |
| Shared sign helpers | 15 | The colour class of a positive or negative figure. The card, the strip and the trades card use it. |

**Proposed split.**

| New module (path) | Kind | Takes | About lines |
|---|---|---|---|
| `lib/portfolixir_web/format.ex` (exists; the shared number formatter) | plain module | The sign-colour clauses (1252-1259), together with Cash flow's copy. | 12 more |
| `lib/portfolixir_web/live/dashboard/data_quality_line.ex` | function-component module | The findings line and its sentence and link clauses (616-656, 1261-1476). | 255 |
| `lib/portfolixir_web/live/dashboard/closed_trades_card.ex` | function-component module | The closed-trades card (661-887). | 230, about 140 once its "left out" sentences are in `ExcludedSales` |
| `lib/portfolixir_web/live/dashboard/kpi_strip.ex` | function-component module | The key-figure strip (376-486, 971-979, 1004-1042). | 165 |
| `lib/portfolixir_web/live/dashboard/wealth_card.ex` | function-component module | The value card with its status region (290-374, 889-969). | 170 |
| `lib/portfolixir_web/live/dashboard/attention_lists.ex` (optional) | function-component module | The markup of "Off target" and "Due" (490-614, 1066-1089, 1142-1165, 1197-1214). | 200 |
| a new read in `Portfolixir.Portfolios.Allocation` (computes targets and drift) | context function | The off-target list: targeted rows beyond the threshold over every portfolio, sorted, cut to five, with threshold and cap in its answer. The cash row is marked by kind and named by the page. | about 65 leave the page |
| a new counts function in `Portfolixir.Catalog.DataQuality`; direct calls to the three `Portfolixir.Ledger` check reports | context function | The seven catalog counts (1491-1502), and the three ledger-check counts that today go through a web module (1503-1505). | about 15 leave the page |
| a new read in `Portfolixir.Knowledge.Events` (dated facts per security) | context function | The due rows with the security's name and whether it is held (1224-1238). Removes a load of the whole catalog. | about 15 leave the page |
| `lib/portfolixir_web/live/dashboard_live.ex` | stays in place | Mount, the two background reads and their loads, the results, the failure state, the frame, onboarding, the newest booking. | 650, or 450 with the optional module |

**What is left.** `dashboard_live.ex` at about 650 lines, about 450 with the optional module. It owns the mount, the two background
reads with their loads and results, the failure state, the frame and onboarding.

**Order of work.**

1. The fix of R-013 (A2-03), and of R-012 (D2-03) as far as it reaches this page, in place, with a failing test first: the page's own drift rule (`dashboard_live.ex:1192-1195`) gives way to the
   context's rule and its "has a target" mark. Changes behaviour: a held category with an explicit 0 % target appears in "Off
   target". Whether exactly 5.0 percentage points counts is decided with the fix: the context's rule is inclusive
   (`lib/portfolixir/portfolios/allocation.ex:154-159`), R-013 (A2-03)'s fix leaves "or its exclusive twin" open, and the card's sentences
   say "more than ±5 pp" and "within ±5 pp" (`dashboard_live.ex:509`, `:523`); the wording follows the bound. Risk tier.
2. R-156 (O5-04)'s fix in place, with a failing test first: the four strip cells and the "Off target" block follow the value card's rule
   and stop saying "loading" after a failed read. Changes behaviour.
3. The sign-colour clauses move into `Format` (one commit group with Cash flow's step 2). Move only. Leaves about 1,534 lines.
4. `DataQualityLine`. Move only. Leaves about 1,285.
5. `ClosedTradesCard`. Move only. Leaves about 1,060.
6. `KpiStrip`. Move only. Leaves about 905.
7. `WealthCard` with its status region; the path list of `test/invariants/css_status_region_test.exs:19` follows. Move only. Leaves about 745.
8. The context reads, one at a time: the due rows, the counts, the off-target list last. Changes behaviour where the API gains a
   field. `_bmad-output/planning-artifacts/design-language/DESIGN.md:447` names `dashboard_live.ex` `@max_alerts` and follows the
   off-target read. Leaves about 650. The optional `AttentionLists` move follows (move only) and leaves about 450.

**Pins before the first move.** Under `test/portfolixir_web/live/` unless a path says otherwise. `dashboard_test.exs` (its data-quality
roles; `:264-267` states today's drift rule and changes with step 1) and `overview_explanations_live_test.exs` hold step 4;
`dashboard_trades_card_test.exs`, `dashboard_trades_card_cost_test.exs` and `dashboard_trades_card_failure_test.exs` hold step 5;
`dashboard_kpi_strip_test.exs`, `zero_figure_unsigned_test.exs` and `test/invariants/busy_placeholders_test.exs` hold steps 3 and 6;
`dashboard_total_excluded_test.exs` and `test/invariants/css_status_region_test.exs:19` and `:66` hold step 7; `dashboard_upcoming_test.exs`
and `test/portfolixir/portfolios/drift_threshold_test.exs` hold step 8. 16 test files select a `#dashboard-…` or `wealth-card-…` id.
Missing, to write first: (a) a test for R-013 (A2-03), with a held category at an explicit 0 % target and one at exactly 5.0 percentage
points, before step 1; (b) a test of the failed-load state, which no test reads today: R-156 (O5-04)'s reproduction with its assertions
inverted, before step 2. Not visible to server tests: the count-up element `#count-wealth-card` (`dashboard_live.ex:341-347`) must
keep its id or the count-up restarts; look at it in a browser at step 7.

**Do not.**

- The page's drift rule in a context. `dashboard_live.ex:1192-1195` is the rule R-013 (A2-03) finds wrong, and the context has its own
  (`lib/portfolixir/portfolios/allocation.ex:154-159`). Fix first, then the new read builds on the context's rule.
- A translated word inside the background read or a context. `gettext("Cash")` at `dashboard_live.ex:1172` runs in the background
  read, which has no language set; it goes unnoticed only because the German word is also "Cash".
- Four background reads in place of one as the fix for R-156 (O5-04). The value card and the drift list share one pricing pass by decision
  (ADR-0035, `dashboard_live.ex:84-88`); the failure rule belongs in the template.
- A context function for the newest booking (`dashboard_live.ex:1048` already calls one), or ledger counts that go through a web
  module (`dashboard_live.ex:1503-1505`).
- A reshaped status region in the value card. `test/invariants/css_status_region_test.exs:66` pins the note directly after the
  region's opening tag (`dashboard_live.ex:368`); region and note move together in that form.

**Decision or ADR.** No ADR amendment. Two rules in `AGENTS.md` bind step 8: a metric states its computation basis in its payload,
so the off-target read returns its threshold and its cap and the sentence at `dashboard_live.ex:523` takes the number instead of
the written-out "±5 pp"; and each new read says whether the API gains the field. Step 1 changes a drift rule and is risk-tier work
(`docs/decisions/0036-risk-tier-rides-the-batch.md`).

**Findings that ride along.**

- R-013 (A2-03) (S2): fixed first; a held category with an explicit 0 % target is missing from "Off target" and the card gives a false all-clear.
- R-012 (D2-03) (S2): the same predicate is the Overview's own rule for a category without a target; it goes in step 1. The domain half (no drift and no hint for such a row, ADR-0023) is section 11 of the triage, step 2.
- R-156 (O5-04): fixed second; five regions keep saying "loading" after a failed read.
- R-119 (O5-06): fixed by steps 4 to 8 (seven blocks and four domain reads in one page).
- R-118 (O5-05): step 3 gives the sign-colour clauses one home; the "left out" sentences move with Cash flow's step 8.
- R-048 (D5-04): the off-target list is one of the page-derived figures it counts; it becomes a context read in step 8, as do the due rows' "held" mark and
  the counts, which are figures of the same kind.

### `lib/portfolixir_web/live/securities/merge_preview.ex` (1,780 lines at e014f284)

**Jobs it does today.**

| Job | About lines | What it does |
|---|---|---|
| Shell of the step and the pair's cards | 120 | The two live regions (announced by a screen reader: the stale-plan note and the problem alert), the source → target cards, the button row with Back, confirm and Close. |
| Preview body | 925 | What the merge will do: ISIN choice, holdings sum, FIFO restatement, counts, equal bookings, quote collisions, settings, events, master data, notes. |
| Refusal in the operator's words | 575 | Why the merge is refused and what to do about it: a reason and a remedy per guard (a precondition the merge checks). |
| Sentences the dialog uses | 100 | The missing-choice line, the result line, what changed since the preview was opened. |

**Proposed split.**

| New module (path) | Kind | Takes | About lines |
|---|---|---|---|
| `lib/portfolixir_web/live/securities/merge_refusal.ex` | function-component module | The refusal (1107-1680): 24 functions behind one entry point, no call back into the body. Four of the file's seven database reads during render go with it, unchanged. | 590 |
| `lib/portfolixir_web/live/merge/preview_parts.ex` (shared with the accounts preview) | function-component module | Step 3: the pieces that are the same in both previews today, namely the two live regions, the button row, the signed quantity and the bucket-name list (written twice in this file). Step 4, after a board: the sum block, the counts list, the equal-bookings fieldset, the before → after table. The sentences stay in each preview. | 80 at first, 300 at the end |
| `lib/portfolixir_web/live/merge/flows.ex` (taken from the accounts preview) | function-component module | Nothing from this file. Its four calls into the accounts preview (205, 268, 285, 688) point to the new module. | 0 from here |
| answer of `Portfolixir.Lifecycle.preview_security_merge/2` (the read that computes the preview) and its API serializer `merge_json.ex` | context function | What the screen reads beside the preview today: the names of depots, cash accounts and buckets (196, 757-758, 1589); the refusing guard's facts (1249, 1289-1291, 1313); each side's holdings over every depot and its booking count, read by the dialog (`securities/merge_dialog.ex:462-477`). | 7 read sites leave |
| a new `Portfolixir.Lifecycle` read of the merge candidates | context function | The first step's "not selectable" reasons, which the dialog decides a second time today (`securities/merge_dialog.ex:416-425`). | about 10 leave the dialog |
| `lib/portfolixir_web/live/securities/merge_preview.ex` | stays in place | The pair's cards, the body with the securities' own sentences, the sentences the dialog uses. | 1,000 |

**What is left.** `securities/merge_preview.ex` at about 1,000 lines: the preview body in the securities' own words, the pair's cards
and the sentences its dialog uses. It has no events and no state; those stay in `securities/merge_dialog.ex`.

**Order of work.**

1. The refusal moves to `Securities.MergeRefusal`. Move only. Leaves about 1,205 lines here. (Steps 1 to 5 are one sequence over
   both preview files.) `_bmad-output/planning-artifacts/design-language/DESIGN.md:3183-3185` names the dialog's modules and gains
   `MergeRefusal`, later `Merge.Flows` and `Merge.PreviewParts`.
2. The external-flows block moves out of the accounts preview into `Merge.Flows`; here the four calls follow. Move only.
3. `PreviewParts` with the four pieces that are the same today. The path list of `test/invariants/css_status_region_test.exs:14-17`
   follows. Move only. Leaves about 1,170.
4. A board on the four visible differences between the two previews, then the fieldset, the sum block, the counts list and the
   tables. Changes behaviour wherever the board picks one form. Leaves about 1,000.
5. The reads move into the preview's answer and the API payload (R-065 (O5-02)). Changes behaviour: the API gains fields; the screen shows
   the same. Risk tier under ADR-0050 §10.

**Pins before the first move.** `test/portfolixir_web/live/securities_merge_live_test.exs` (1,354 lines; its refusal cases hold step 1),
`accounts_merge_live_test.exs` and `merge_records_phrase_test.exs`; they select by `data-role`. `test/invariants/css_status_region_test.exs:14-17`
names both preview files and `:66` pins the form of the regions' markup. `test/invariants/merge_refusal_identifiers_test.exs:16-19`
reads the context's refusal sentences; in step 5 the guard's facts arrive as data fields and the words stay in the web layer.
Missing: nothing committed compares the whole picture, and this is the screen on which the operator consents to an irreversible
write. For steps 1 to 3 the PR's verification pass compares the rendered HTML of both previews before and after on the suite's
fixtures and reads the translation-catalogue diff for reference lines only; not a committed markup test (idea row I39 asks for fewer
of those). The two-line rows under 720 px sit beside every table and server tests see both renderings at once, so a dropped narrow
row passes them: check step 4 in a browser at phone width.

**Do not.**

- A shared refusal, a shared "Check again" or a shared amount for an equal booking before a board. The previews differ there
  today: every failed guard here (`securities/merge_preview.ex:1116`) against the first only (`portfolio_accounts/merge_preview.ex:901`);
  "Check again" only when it can help (`:1132`) against always (`:916`); quantity × price (`:738-739`) against "N shares" (`:561-562`).
- A form inside the shared fieldset. This file's form wraps every choice (`securities/merge_preview.ex:212`); the fieldset keeps
  the input name `merge[collapse]`, which the dialog's `choose` clause reads (`securities/merge_dialog.ex:334`).
- The notes passed into the shared regions as slots. `test/invariants/css_status_region_test.exs:66` pins the note directly after
  the region's opening tag; the shared part takes the stale sentence as a value (`securities/merge_preview.ex:70`).
- The shared module under `portfolio_accounts/`, or delegates left in the old module. That is how this file came to call the
  accounts page's module (`securities/merge_preview.ex:205`, `:268`, `:285`, `:688`).
- A shared sum block that reads. It takes numbers; today the sum is fed by the dialog's own ledger read
  (`securities/merge_dialog.ex:462-477`). And no LiveComponent for a preview.

**Decision or ADR.** One owner decision, on a board before step 4 (`docs/development/sprint-workflow.md`, UI boards): which form both
previews show at each of the four differences. No ADR amendment: the verified finding R-065 (O5-02) showed that the plan digest (the hash
the confirm checks) already covers the bookings behind the holdings sum (`lib/portfolixir/lifecycle/security_merge.ex:664-667`,
`:2223`), so ADR-0050 §10 (`docs/decisions/0050-lifecycle-merges-under-a-reimport-contract.md`) stands and step 5's fields are additive.

**Findings that ride along.**

- R-117 (O5-01): fixed by steps 2 to 4 (one anatomy written twice). About 150 lines are saved over both files; the gain is one place to change.
- R-065 (O5-02): fixed by step 5 (7 database reads during render here, and a sum fed from beside the preview). Until then the module's
  opening comment, "and nothing else", should say what is read beside the preview.
- R-118 (O5-05): `quote_source_label/1` (names a quote's source) lives on the 7,738-line Securities page and is called here (`:788`,
  `:792`); it moves to a helper module.

### `lib/portfolixir_web/live/portfolio_accounts/merge_preview.ex` (1,104 lines at e014f284)

**Jobs it does today.**

| Job | About lines | What it does |
|---|---|---|
| Shell of the step | 75 | The two live regions, the pair's head, the button row. |
| Cash preview | 185 | What merging two cash accounts does: the sum block and the counts. |
| Depot preview | 150 | What merging two depots does: the counts and the positions table, before → after. |
| Equal bookings | 155 | The keep-or-remove choice for bookings that exist on both sides, and what removing them changes elsewhere. |
| External flows | 220 | The deposits and withdrawals a merge removes or moves. Both previews use it, and one test calls it directly. |
| Notes, refusal, labels, what changed | 270 | The note and the deletion warning, the refusal with reason and remedy, labels, the "changed since opening" list. |

**Proposed split.**

| New module (path) | Kind | Takes | About lines |
|---|---|---|---|
| `lib/portfolixir_web/live/merge/flows.ex` | function-component module | The external-flows block (616-833) with its three public functions and their helpers, unchanged, including its three database reads during render. | 225 |
| `lib/portfolixir_web/live/merge/preview_parts.ex` (the same module as in the securities section) | function-component module | Step 3: the two live regions, the button row, the signed quantity, the bucket-name list. Step 4, after a board: the sum block, the counts list, the equal-bookings fieldset, the before → after table. The sentences stay in each preview. | 80 at first, 300 at the end |
| answers of `Portfolixir.Lifecycle.preview_cash_merge/2` and `preview_depot_merge/2` (the reads that compute the previews) and the API serializer `merge_json.ex` | context function | The names of the securities, depots, cash accounts and views the screen shows, read today during render, some once per row (456, 577-578, 794-804). | 6 read sites leave |
| a new `Portfolixir.Lifecycle` read of the merge candidates | context function | The first step's "not selectable" reasons, which the dialog decides a second time today (`portfolio_accounts/merge_dialog.ex:418-452`). | about 35 leave the dialog |
| `lib/portfolixir_web/live/portfolio_accounts/merge_preview.ex` | stays in place | The cash and depot preview bodies with the accounts' own sentences, the refusal, the labels, the "changed since opening" list. | 700 |

**What is left.** `portfolio_accounts/merge_preview.ex` at about 700 lines: the cash and depot preview bodies in the accounts' own
words, the refusal, the labels and the "changed since opening" list. Events and state stay in `portfolio_accounts/merge_dialog.ex`.

**Order of work.**

1. Securities preview only: its refusal moves out. Nothing changes in this file. Move only. (Steps 1 to 5 are one sequence over
   both preview files.)
2. The external-flows block moves to `Merge.Flows`, and the alias in `test/portfolixir_web/live/accounts_merge_live_test.exs:22`
   follows in the same commit. Move only. Leaves about 885 lines here.
3. `PreviewParts` with the four pieces that are the same today; the invariant's path list follows. Move only. Leaves about 850.
4. The board, then the fieldset, the sum block, the counts list and the tables. Changes behaviour wherever the board picks one
   form. Leaves about 700.
5. The reads move into the previews' answers and the API payload (R-065 (O5-02)). Changes behaviour: the API gains fields. The test at
   `accounts_merge_live_test.exs:973-1004` changes shape: today it passes ids and expects names that the render reads from the database.

**Pins before the first move.** `test/portfolixir_web/live/accounts_merge_live_test.exs` (1,267 lines; `:973` and `:1000` call
`flow_changes/1` by module name and fail at step 2 with `UndefinedFunctionError` until the alias follows), `securities_merge_live_test.exs` and
`merge_records_phrase_test.exs`. `test/invariants/css_status_region_test.exs:14-17` names both preview files and `:66` pins the form
of the regions' markup. Missing: the same as for the securities preview. Nothing committed compares the whole picture of this
consent screen; the PR's verification pass compares the rendered HTML before and after for steps 1 to 3, and step 4 is checked in a
browser at phone width because server tests cannot tell that a narrow row was dropped.

**Do not.**

- Step 2 without the test's alias. Two calls name this module (`test/portfolixir_web/live/accounts_merge_live_test.exs:973`,
  `:1000`); the file still compiles, with a warning, and both tests fail at run time (read, not run).
- A form inside the shared fieldset. This file's form wraps only the equal pairs (`portfolio_accounts/merge_preview.ex:475`); the
  radios keep the name `merge[collapse]` (`:519`, `:539`), which the dialog reads (`portfolio_accounts/merge_dialog.ex:267`).
- The notes passed into the shared regions as slots. `test/invariants/css_status_region_test.exs:66` pins the note directly after
  the region's opening tag; the stale sentence differs from the securities' by its noun (`portfolio_accounts/merge_preview.ex:60`).
- A shared shell with one root element. `step/1` returns two siblings, the body and the button row
  (`portfolio_accounts/merge_preview.ex:50`, `:93`); they stay siblings.
- The shared modules left under `portfolio_accounts/`, or delegates left in this file. The securities page would keep calling the
  accounts page's module (`securities/merge_preview.ex:205`).

**Decision or ADR.** The same as for the securities preview: one owner decision on a board before step 4
(`docs/development/sprint-workflow.md`, UI boards); no ADR amendment, because ADR-0050 §10 stands as written and step 5's fields are additive.

**Findings that ride along.**

- R-117 (O5-01): fixed by steps 2 to 4; this file gives the shared flows block a home of its own.
- R-065 (O5-02): fixed by step 5 (6 database reads during render here, three of them once per row).
- R-016 (G4-03) (S2): the cash step prints only the absorbed lines of its flow list (`:591-592`, `:622-629`), and the external-flows list is rendered in the depot step alone (`:433`). Not fixed by this split; its fix (section 11 of the triage, step 3) makes the cash step render the shared list and lands before step 2 moves that block.

---

**What applies to the next two files (`lib/portfolixir_web/controllers/api/v1/json.ex`, `lib/portfolixir_web/controllers/api/v1/contract.ex`).**
Neither file holds a process, an event or a socket, so every new piece is a plain module of functions. Both files
keep their module name. Code moves without a forwarding function left behind: callers are re-pointed in the commit
that moves it. Both files change often (30 and 94 commits in the 31 days before e014f284), so a part is moved only
while no other branch has it open. A change to what the API answers (R-121 (O6-02), R-020 (O6-03), R-151 (O6-05), R-042 (O6-08), R-060 (O6-09)) is never part
of a move commit. The review recounted the first reading's inventory from the source and it held (the job rows, the
function counts, the 328 call sites, the 28 entries, both churn figures). For `json.ex` it corrected the caller counts
of five of the eight extraction steps, one function wrongly called a copy, the order, two of the moves into a context
and the decisions touched. The corrections to both files are applied below.

### `lib/portfolixir_web/controllers/api/v1/json.ex` (3,014 lines at e014f284)

**Jobs it does today.** The file turns internal records into the JSON the API answers. It holds 17 resource families behind one module name: 75 public and 96 private functions. 59 other modules depend on it (328 call sites, 197 of them on the five shared functions).

| Job | About lines | What it does |
|---|---|---|
| Shared kernel | 95 | Writes decimals, dates and timestamps as strings, validation errors as text and fixed internal names as strings; writes the standard block that says how a metric was computed. Includes the 34-line head that names 34 other modules. |
| Securities, quotes, research log | 400 | Security rows with findings, bond reading, aliases, logo and search hits; quote rows; thesis state, log entries, events. Holds the list of fields a caller may select for a security. |
| Accounts, classifications, FX, journal, buckets and views | 180 | Portfolio, cash account and depot; classification trees and assignments; exchange rates and their sync result; one journal row; buckets and saved views. |
| Ledger | 355 | Bookings, split preview, trades, holdings. Holds the selectable-field lists for bookings and holdings. |
| Ledger data quality and reconcile | 240 | Four finding reports, and the result of comparing an outside position list with the ledger's holdings. |
| Valuation, targets, plans, snapshots | 365 | Valuation of a portfolio and of a view with their notes; holdings by security; target rows, plans, a snapshot and its comparison. |
| Allocation, category result, risk, metrics | 455 | The drift tree with its filter; the result per category; the risk lens; the metrics per security and the risk read's metrics block. |
| Cash-flow reports | 190 | Realized gains, flows, costs, income. |
| Performance family | 550 | Performance, benchmark, contribution and bands, each for a portfolio and for a view; sale hindsight. |
| Tax | 155 | Parameters, profile, allowance order, statement snapshot with four derived values, staleness, finding, trim budget. |

**Proposed split.** The 17 new modules sit beside the controllers that call them and are named like the three serializers that already left the file (`merge_json.ex`, `policy_json.ex` and `prediction_json.ex` in the same directory). Each imports by name the kernel functions its bodies call, as `lib/portfolixir_web/controllers/api/v1/body_object.ex:24` imports one function: the string writers it uses, `atom/1` in the seven families that call it (31 call sites) and `computation_basis/1` in the performance family (3 call sites). That way every function body moves byte for byte, and the 428 calls of the four string writers stay as written. Line ranges are those of `json.ex`. Rows of kind "context function" are rules that leave the web layer; they are not part of a move (see R-060 (O6-09) below).

| New module (path) | Kind | Takes | About lines |
|---|---|---|---|
| `lib/portfolixir_web/controllers/api/v1/json.ex` | stays in place | The kernel: `decimal/1`, `date/1`, `timestamp/1`, `datetime/1` (each writes one kind of value as a string), `errors/1` (validation errors as text), a public `atom/1` (a fixed internal name as a string), a public `computation_basis/1` (the standard "how this was computed" block), and by default `journal_entry/1` (one journal row). Gains a module description. | 100 |
| `lib/portfolixir_web/controllers/api/v1/account_json.ex` | plain module | Portfolio, cash account, depot (376-422) | 50 |
| `lib/portfolixir_web/controllers/api/v1/classification_json.ex` | plain module | Tree, classification, category, assignment (2560-2603) | 45 |
| `lib/portfolixir_web/controllers/api/v1/bucket_json.ex` | plain module | Bucket, saved view, the echoed active view (2658-2697) | 40 |
| `lib/portfolixir_web/controllers/api/v1/fx_json.ex` | plain module | Exchange rates, sync result (2605-2641) | 40 |
| `lib/portfolixir_web/controllers/api/v1/target_json.ex` | plain module | Target rows, effective targets, plans, snapshot and its comparison (1264-1417) | 155 |
| `lib/portfolixir_web/controllers/api/v1/valuation_json.ex` | plain module | Portfolio and view valuation with their notes (1076-1262); holdings by security (810-834) | 215 |
| `lib/portfolixir_web/controllers/api/v1/metrics_json.ex` | plain module | Metrics per security (2901-2980) and the risk read's metrics block (1726-1770), whose entry function becomes public | 125 |
| `lib/portfolixir_web/controllers/api/v1/risk_json.ex` | plain module | The rest of the risk lens: weights, concentration, violations (1707-1724, 1772-1800) | 50 |
| `lib/portfolixir_web/controllers/api/v1/tax_json.ex` | plain module | The tax family (2699-2851) | 155 |
| `lib/portfolixir_web/controllers/api/v1/cashflow_json.ex` | plain module | Realized gains, flows, costs, income (1802-1991) | 190 |
| `lib/portfolixir_web/controllers/api/v1/ledger_quality_json.ex` | plain module | Four finding reports and the reconcile result (836-1074) | 240 |
| `lib/portfolixir_web/controllers/api/v1/allocation_json.ex` | plain module | The drift tree with its filter (1419-1483, 1619-1705) | 155 |
| `lib/portfolixir_web/controllers/api/v1/category_result_json.ex` | plain module | The result per category with its two fixed sentences (1485-1617) | 135 |
| `lib/portfolixir_web/controllers/api/v1/knowledge_json.ex` | plain module | Thesis state, log entries, events (269-324, 2877-2899) | 80 |
| `lib/portfolixir_web/controllers/api/v1/security_json.ex` | plain module | Security rows, findings, quotes, search hits (36-267, 329-374, 676-702, 3001-3013), the security field list, and `provider/1` (writes a search provider's name) unchanged | 320 |
| `lib/portfolixir_web/controllers/api/v1/ledger_json.ex` | plain module | Bookings, split preview, trades, holdings (424-674, 704-805), with both field lists | 355 |
| `lib/portfolixir_web/controllers/api/v1/performance_json.ex` | plain module | The performance family, whole (1993-2031, 2046-2558) | 555 |
| `lib/portfolixir/portfolios/quote_plausibility.ex` | context function | The rounding, half up at six places, of an implausible-quote finding's ratio (`json.ex:179`). The API reads the finding from this module (`lib/portfolixir_web/controllers/api/v1/security_controller.ex:115`), and the module's own basis text already promises the rounding (`lib/portfolixir/portfolios/quote_plausibility.ex:187-189`). | 1 |
| `lib/portfolixir/portfolios/reconcile.ex` | context function | The order of reconcile matches, lowest input row first (`json.ex:996-999`, `1055-1057`) | 7 |
| `lib/portfolixir/portfolios/valuation.ex`, `lib/portfolixir/portfolios/risk.ex` | context function | The read date of the valuation, the view valuation and the risk lens (`json.ex:1088`, `1155`, `1715`), as an `as_of` key of each result. Additive, but the allocation, the policy findings and the risk lens read those results too. | 3 |
| `lib/portfolixir/tax.ex` | context function | One function that derives a tax statement's four values (allowance remaining, tax-free trim budget, expected capital gains tax, stale) for a snapshot and a day (`json.ex:2763`, `2779-2782`). The Tax page calls one of them itself (`lib/portfolixir_web/live/tax_live.ex:974`). | 5 |
| Each rule's own context file (`lib/portfolixir/ledger.ex`, `lib/portfolixir/portfolios/valuation.ex`, `lib/portfolixir/portfolios/risk.ex` and the others) | context function | The "how this was computed" sentences written in the serializer, verbatim: 11 places from `json.ex:523` to `json.ex:2477`. `lib/portfolixir/ledger.ex:1280-1284` already holds one such sentence beside its rule. | 86 |

**What is left.** `json.ex` at about 100 lines: the kernel and the one journal row. It keeps its name, so 197 outside call sites keep their spelling, and 30 modules that depend on 3,014 lines today depend on a module of 40 to 555 lines.

**Order of work.** Three rules hold for steps 3 to 8. A family moves only while no other branch has it open. The commit deletes every alias (a line that gives another module a short name) the move leaves unused, in `json.ex` (31 alias lines, `:4-34`) and in callers that no longer use the kernel, because the build fails on an unused alias. Tests and comments that name a moved function are re-pointed in the same commit.

1. Record the decision. No code moves: the amendment under "Decision or ADR" lands as a planning change, and the owner's merge is the go-ahead. Move only.
2. Put the kernel in place. `json.ex` gets a module description. Three identical private functions that write a fixed internal name as a string (`reason/1`, `enum_string/1`, `tax_author/1`) become one public `atom/1`, 31 call sites inside the file. `computation_basis/1` becomes public. Leaves about 3,010 lines. Move only.
3. The eight low-risk families, one commit per module: `AccountJSON`, `ClassificationJSON`, `BucketJSON` and `FxJSON` first (records in, maps out, no call into the domain), then `TargetJSON`, `ValuationJSON`, and `MetricsJSON` with `RiskJSON` (no commit in 31 days). Touches 15 controllers, `ViewParam` (reads a request's `view` parameter) and `SecurityDossier` (assembles the one-security read from several families; edited again in steps 6 and 7); 56 call sites. Leaves about 2,300. Move only.
4. `TaxJSON` alone. It is the one family that computes while it writes, and the allocation read calls it (`lib/portfolixir_web/controllers/api/v1/allocation_controller.ex:74`). 3 controllers, 12 call sites. Leaves about 2,150. Move only.
5. `CashflowJSON`, `LedgerQualityJSON`, `AllocationJSON`, `CategoryResultJSON`. 9 controllers, 11 call sites. Leaves about 1,440. Move only.
6. `KnowledgeJSON` and `SecurityJSON` together, because the security row calls the thesis state. 7 controllers and `SecurityDossier`, 30 call sites; one controller reads the field list while it compiles. Leaves about 1,040. Move only.
7. `LedgerJSON` with both field lists. 6 caller modules, 12 call sites; two controllers read the lists while they compile. Leaves about 690. Move only.
8. `PerformanceJSON`, last because it changes most (8 of the last 30 commits). 9 controllers, 9 call sites. Leaves about 100. Move only.

**Pins before the first move.** These hold the behaviour: the HTTP tests in `test/portfolixir_web/controllers/api_v1_*_test.exs` (they read the answer through the route, so a move does not touch them); `test/portfolixir_web/controllers/api_v1_error_renderer_test.exs` (validation errors); `test/portfolixir_web/controllers/api_v1_read_ergonomics_test.exs:369-385` (each selectable-field list equals the keys its serializer writes); `test/invariants/metrics_carry_no_verdict_test.exs` (both metric payloads, over the wire). Five test files call a moving function by module name and are re-pointed in its step: `test/portfolixir_web/controllers/api_v1_total_valuation_test.exs:99` (step 3); the read-ergonomics test above at `:383-384` and `test/portfolixir/catalog/security_search/search_payload_bounds_test.exs:97` (step 6); the read-ergonomics test at `:371-379` (step 7); `test/portfolixir_web/controllers/api/v1/json_freshness_meta_test.exs:39-44`, which holds the freshness fields of three performance functions, and `test/portfolixir_web/live/wealth_phone_twins_test.exs:470` (step 8). Thin, counted as test files that name the read's route: buckets 3, plans 2, category results 1, reconcile 3, bands 3, sale hindsight 3.

Missing, to write first. (1) Coverage of `json.ex` per clause was not measured. Measure it before step 3 and write an HTTP test for every clause no test reaches. One named doubt is the category result's scope sentence (four clauses, `json.ex:1555-1577`), whose view-scoped form the first reading called unreached. A lost clause compiles and fails only on the request that needs it, and moved lines count as changed lines against the 90 % coverage target for changed lines (`codecov.yml:24-26`). (2) Before steps 6 and 7: the test of R-145 (O6-06) that holds the companion's three hand-kept field lists to the API's lists. (3) Not a test, but stated in every move PR: the move check. The lines deleted from `json.ex` are the lines added to the new module, apart from the module frame; `git diff --color-moved=dimmed-zebra` shows it. It is the only guard against a dropped clause or a dropped optional key.

**Do not.**

- Do not fold `provider/1` into `atom/1`. It has a third clause (`json.ex:3001-3003`) because a search provider may be text, not a fixed name (`lib/portfolixir/catalog/security_search/search_result.ex:161-162`); folded, it raises on such a provider.
- Do not change a function body in a move commit: not the rounding (`json.ex:179`), not the ordering (`json.ex:996-999`), not a read date, not a sentence, and no merge of the two copies of `window_end/1`, which writes the end point of a return window (`json.ex:2286-2298`, `lib/portfolixir_web/controllers/api/v1/prediction_json.ex:128-138`). A move that also edits cannot be checked as a move.
- Do not call Phoenix's `render/3` or `put_view` (its built-in way to pick a view module by name) in an API controller. `lib/portfolixir_web.ex:5` makes `XJSON` the view of `XController`, nine new names match an existing controller, and their functions take records, not what Phoenix would pass. No API controller calls `render/3` today.
- Do not build a shared freshness helper in the kernel. The key `stale` means three things: a superseded stored result (`json.ex:2018`), a position's price age (`json.ex:1687`) and a tax statement's age (`json.ex:2782`).
- Do not batch a gate edit or a wire-text change with the moves. Moving the journal row renames a key in the registry of the scope gate that lists which modules may name the journal's unused `scenario_id` column (`test/invariants/scope_b5_system_writers_and_schedulers_test.exs:135`, checked both ways at `:170-172`). The shared refusal module of R-121 (O6-02) changes the text of a 404 (`lib/portfolixir_web/controllers/api/v1/tax_snapshot_controller.ex:145-147`).

**Decision or ADR.** An ADR amendment is needed, and it is step 1. ADR-0001 (`docs/decisions/0001-modular-phoenix-monolith.md`) gains a paragraph: wire shapes live in one plain module per family beside the controllers, called explicitly and never through `render/3`; the kernel keeps the string writers, `errors/1`, `atom/1` and `computation_basis/1`; the three modules that already left are named. ADR-0031 (`docs/decisions/0031-recorded-tax-statement-snapshots.md:377-379`) gets a dated note when `TaxJSON` lands, and `_bmad-output/planning-artifacts/architecture.md:896-900` and `:610` are marked superseded. Why: the only written rule on where wire shapes live says the opposite ("no per-controller JSON modules", restated as today's reality at `:829`), three modules already departed from it without a record, and `AGENTS.md` (Hard Rules) says an architecture decision is amended, not changed silently. ADR-0047 (`:46-48`) and ADR-0051 (`:290-291`) name `JSON.computation_basis/1` and stay true because it stays in the kernel. One default the owner may flip: the journal row stays in the kernel, because moving 15 lines edits a scope gate. If it should move to `lib/portfolixir_web/controllers/api/v1/journal_json.ex`, that is one more commit after step 8, with the gate's key renamed in the same commit and named in the PR text; the kernel then ends at about 85 lines.

**Findings that ride along.**

- R-120 (O6-01) (17 families behind one module name, three serializer conventions side by side): fixed by this split.
- R-145 (O6-06) (the companion's hand-kept copies of the three field lists are only spot-checked): its pin is written before steps 6 and 7 move the lists.
- R-152 (O6-07) (the freshness test names three serializer functions by hand): re-pointed in step 8; its gap is a separate change.
- R-042 (O6-08) (`decimal/1` writes a signed zero as `"-0"`): the function stays in the kernel; the fix changes wire text and is its own commit, never inside a move.
- R-060 (O6-09) (rules and one rounding live in the serializer): the five "context function" rows. Each is its own commit after its family has landed, changes what a context returns, and is pinned by comparing the payload before and after. The holdings' read date (`json.ex:722`) does not go to a context: `Ledger.holdings_for_portfolio/1`, the ledger's holdings read, returns a plain list to 6 call sites in 5 modules, so the controller reads the clock once and passes the day in. Three things stay in the serializer because they hold no rule and no figure: the drift filter (`json.ex:1436-1439`), `logo_status/1` (reads a logo's state from the security record) and `span_labels/0` (a fixed list of labels).
- R-121 (O6-02) (37 and 35 private copies of the two refusal helpers, one 404 in three spellings): not part of this split.
- R-012 (D2-03) and R-013 (A2-03) (S2): their fixes change what this file writes. The allocation rows carry `has_target` and a `null` drift for a row without a target (`json.ex:1434-1438`, `:1637-1653`). Not part of this split and never inside a move commit: each lands before its family moves (allocation in step 5), or afterwards in the family's own module.

### `lib/portfolixir_web/controllers/api/v1/contract.ex` (2,082 lines at e014f284)

**Jobs it does today.** The file is the manifest that `GET /api/v1/contract` serves: a dated list of what the API and the MCP companion offer. It has one job and one kind of bulk. The case for a split is the cost of reading and merging it, not behaviour.

| Job | About lines | What it does |
|---|---|---|
| The manifest's data | 1,992 | 28 dated entries (lines 46-2037). Each entry is one record: its version and date, six lists of names (endpoints, tools and prompts, added and removed) and its prose (`summary` and `parameters`). The prose is 81 % of the file's bytes. |
| The accessors | 45 | Seven functions (lines 2039-2081): the whole list, the newest version, its date, the entries after a given day, and three sets of what exists today, with removals applied. |
| The maintenance contract | 40 | The head comment and the entry's type (lines 2-43). They tell an author how to add an entry, and they tell two outside readers which lines must stay one per line. |

**Proposed split.** One file per entry, and a committed fixture (a data file that tests read) for the two readers that parse the Elixir source as text today.

| New module (path) | Kind | Takes | About lines |
|---|---|---|---|
| `lib/portfolixir_web/controllers/api/v1/contract.ex` | stays in place | The head comment, the entry type, the same seven functions, and an explicit list of the 28 entry modules, newest first | 120 |
| `lib/portfolixir_web/controllers/api/v1/contract/entry_001.ex` to `entry_028.ex` | plain module | One entry each, whole: version, date, the six lists and the prose stay in one record, returned by one function `entry/0` | 30 to 285 each (entry 28: 284; entry 1: 235; entry 8: 149 lines and 52 KB) |
| `mcp-server/test/fixtures/contract/inventory.json` | test helper | Per entry: version, date, tools added, tools removed. An Elixir test writes and compares it; the companion's budget test and the release workflow read it. Not shipped. | 1 file |
| Three new tests: one in `test/portfolixir/ci_test.exs`, the fixture test, the list test | test helper | The release's version rule, the fixture's content, and that the list names every entry file | not estimated |

What the split buys: the open entry becomes a file of about 20 KB instead of the head of a 277 KB file with lines of up to 3,004 characters, and two branches that both add the next entry collide on one file name. What it does not buy: the 80 story marker lines (comment lines that fence each story's part of an entry, `contract.ex:56-493`) stay, because the stories of one sprint still share one entry, and the merge hot spot moves to that entry's file.

**What is left.** `contract.ex` at about 120 lines: the head comment, the type, the seven functions and the list. The 1,992 lines of data are the same bytes in 28 files; only the content rule of R-150 (O6-04) makes them fewer.

**Order of work.**

1. Pin the release's rule. A test in `test/portfolixir/ci_test.exs`, which already reads the release workflow, applies the workflow's text rule (`.github/workflows/release.yml:129`) to the file the workflow names and expects the manifest's current version. Move only: a test is added, nothing else changes.
2. Put the two text readers on the fixture. An Elixir test writes and compares `inventory.json`. `contractToolDebuts`, the companion's test helper that dates each tool by the entry that added it, reads the fixture instead of the source, and its text patterns are deleted (`mcp-server/test/support/schema-budget.ts:778-790`). The release step reads the newest version from the fixture. The sentence "keep those keys one per line" (`contract.ex:14-18`) is deleted. Move only: no answer of the API changes. The workflow edit first runs for real at the next release; step 1's test, now over the fixture, checks it in the build.
3. Move the 27 closed entries into files, in one commit. `Contract` lists the modules by hand. The same commit adds the list test: every `contract/entry_*.ex` file is named in the list and the list names nothing else, and each file's number equals its `version`. Step 4 adds the last file; from then on there are as many files as entries. Move only.
4. Move the newest entry at a sprint boundary, when no branch has it open. Move only.

**Pins before the first move.** These hold the behaviour: `test/portfolixir_web/controllers/api_v1_contract_meta_test.exs:25-118` (endpoint, tool and prompt names against the router and the companion, in both directions; versions in order and unique); `test/portfolixir_web/controllers/api_v1_contract_test.exs` (543 checks of the prose, through the module's functions and the route; a move of the data does not touch it); `mcp-server/test/schema-budget.test.ts:806-818` (the tool names parsed from the source equal the companion's whole tool list, so a move fails loudly there until step 2).

Missing, to write first. (1) Step 1's test. Nothing in the build runs the release's rule today. Without it, a moved or reformatted file fails the release job on `main`, after the owner's merge. (2) The fixture test of step 2. (3) The list test of step 3. 12 of the 28 entries add neither a route nor a tool (versions 3, 6, 9, 13, 14, 16 to 20, 22 and 26), so an entry file left off the list would be missing with no failing test.

**Do not.**

- Do not move or reformat the file before steps 1 and 2. The release reads it by path and by text pattern (`.github/workflows/release.yml:129`); the companion's budget reads it by path and by indentation (`mcp-server/test/support/schema-budget.ts:769`, `:781-789`).
- Do not bundle `since_version=` (R-151 (O6-05)) or a smaller default answer (R-020 (O6-03)) into the split. Both change the read and need an amendment of ADR-0044 §8 (`docs/decisions/0044-security-knowledge-as-an-append-only-log.md:162-172`), a contract entry, the tool description and the API reference in two languages.
- Do not export under `priv/` and do not add a mix task. The repository's pattern is a test that writes and compares a fixture under `mcp-server/test/fixtures/` (`test/portfolixir_web/controllers/api_v1_news_budget_test.exs:8-14`, `:31`); files under `priv/` ship in the release image and trigger a release (`.github/workflows/release.yml:28`).
- Do not find the entry modules at run time, and do not count on `test/portfolixir_web/controllers/api_v1_contract_meta_test.exs:120-121` to notice a wrong list. Those two lines compare the version and the date with the first entry of the list, which is how both are defined (`contract.ex:2045`, `2049`); they cannot fail. Only `:112` catches a wrong order.
- Do not rewrite a closed entry while it moves, and do not split an entry by key. 543 checks read those sentences (`test/portfolixir_web/controllers/api_v1_contract_test.exs:30-2032`), and the sets of what exists today are built from whole entries, oldest first (`contract.ex:2072-2081`).

**Decision or ADR.** No ADR amendment for steps 1 to 4: they change no answer of the read, so ADR-0044 §8 stands. A dated note records the split and says that step 2 is the first use, for the contract, of direction D5 in `_bmad-output/planning-artifacts/architecture.md:489-495` (Elixir produces shared fixtures, the companion's tests only read them; "proposed, nothing built" at `:393`). The manifest's own maintenance text (`contract.ex:23-29`) gains the sentence that a new entry is a new file and one line in the list. The fixture is written pretty-printed, one name per line, under the rule "Public files are normal, readable multiline files" in `AGENTS.md`. One owner decision stays open and blocks only the split of the 2,040-line contract test: what an entry may hold (R-150 (O6-04), an amendment of ADR-0044 §8). Splitting that test first would move prose the rule may delete.

**Findings that ride along.**

- R-150 (O6-04) (the manifest's prose is pinned only by a test that repeats it): not fixed by the split. Step 2 removes the two text readers it names; its content rule is the open owner decision.
- R-020 (O6-03) (the unfiltered read answers the whole manifest, about as many bytes as the full tool list; S2): a separate change of the read. It neither needs the split nor waits for it.
- R-151 (O6-05) (two entries with one date hide the second from a poller): a separate change of the read, with the same independence.
- R-145 (O6-06) (the companion's three field lists): the fixture pattern of step 2 is the way to pin them.

---

**What applies to the next two files (`lib/portfolixir_web/layout_view.ex`, `lib/portfolixir_web/components/app_shell.ex`).**
The review confirmed both inventories: every line range, the 20 hooks (a hook is a small browser script that LiveView
attaches to one element of a page), the 283 uses of the shared components, the 23 test files.
Both verdicts are "sound with corrections", and the corrections are to order, pins and decisions. No figure is wrong in this
lane. Nothing moves into a context (a domain module under `lib/portfolixir/`): neither file computes a figure or reads the
database. The fixes for R-157 (O7-01) and R-158 (O7-02) are their own stories; they need none of the steps below and block none. The two splits
do not line up: cut into several files, the script would hold the browser half of three shared components in two files each.

### `lib/portfolixir_web/layout_view.ex` (2,548 lines at e014f284)

**Jobs it does today.** One Elixir function of 58 lines around three inline scripts of 2,490 lines.

| Job | About lines | What it does |
|---|---|---|
| Root document (the only Elixir) | 58 | builds the `<html>` frame every page and the login page share: language, remembered sidebar state, privacy word, the request-forgery (CSRF) token, stylesheet, the two LiveView scripts |
| Theme | 129 | a 14-line boot script applies the stored light or dark mode and accent before the first paint; a 115-line control script runs the top bar's two menus and stores the choice |
| Boot and registry | 16 | reads the CSRF token; the guard stops everything after it when the LiveView client is missing; `Hooks` is the list of hooks; `LiveSocket` connects the page to the server |
| Page-wide listeners | 132 | `data-confirm` asks before a destructive click; copy to clipboard; an OS notification when a long job ends in a hidden tab; the focus lands on a result |
| Charts | 614 | three hooks: `ChartCrosshair` (crosshair, tooltip, drag zoom), `ChartScale` (axis label size), `SunburstTooltip` (hover text of the allocation ring); the SVG/PNG export; the writer that masks figures in privacy mode; a 6-line comment for a hook that no longer exists |
| Tab rows and sidebar rail | 342 | three hooks: `AreaTabs` and `DetailTabs` keep the active tab in view on a phone, `SidebarRail` keeps the collapsed sidebar across reloads |
| Overlays | 473 | four hooks: `PositionedMenu` (row menus placed on their button), `ModalDialog` (dialogs and focus return), `PopoverDisclosure` and `DisclosureState` (open panels stay open across updates); the block that places the ⓘ panels |
| Notes and results | 288 | three hooks: `NoteClamp` ("more" on a cut note), `InlineResult` (the × on a result gives the focus back), `CountUp` (a total counts to its next value) |
| Per-browser preferences | 142 | three hooks: `ColumnPrefs`, `PeriodMemory`, `SecuritySplitPane` remember the chosen columns, Wealth's period and the Securities split height |
| One page each | 319 | four hooks: `RemapCards` (import mapping cards), `MergeFocus` (an opened merge record), `PPImportDrop` (the import drop zone), `ClassificationDnD` (classification drag and drop) |

**Proposed split.** The first four rows are the whole split. The rows marked "option" apply only if the decision record chooses several files.

| New module (path) | Kind | Takes | About lines |
|---|---|---|---|
| `lib/portfolixir_web/layout_view.ex` | stays in place | the root document and the 14-line theme boot, which stays inline because it must run before the stylesheet paints, and keeps its nonce (the per-request token by which the policy accepts an inline script) | 76 |
| `priv/static/theme.js` | plain module | the theme control script's body (`:2430-2542`; `:2429` and `:2543` are its `<script>` tags), byte for byte | 113 |
| `priv/static/app.js` | plain module | the whole client script (`:69-2427`), byte for byte first, de-indented in a later commit | 2,359 |
| `test/support/client_source.ex` | test helper | the one place a test asks for the client's text: first `all/0` (the whole text), later `hook/1`, `method/2`, `block/1` (one hook, one of its methods, one named block), each failing on a missing marker | 60 |
| option: `priv/static/js/core.js`, first on the page | plain module | `data-confirm`, the guard, the hook list as `window.Portfolixir.Hooks`, clipboard, notifications, focus on a result | 145 |
| option: `priv/static/js/charts.js` | plain module | the mask writer, the export with its click listener, the three chart hooks | 615 |
| option: `priv/static/js/navigation.js` | plain module | `AreaTabs`, `DetailTabs`, `SidebarRail` | 340 |
| option: `priv/static/js/overlays.js` | plain module | the four overlay hooks and the ⓘ block | 475 |
| option: `priv/static/js/feedback.js` | plain module | `InlineResult`, `NoteClamp`, `CountUp` | 290 |
| option: `priv/static/js/pages.js` | plain module | the three preference hooks and the four one-page hooks | 465 |
| option: `priv/static/js/boot.js`, last on the page | plain module | the token read, the `LiveSocket` and its connect | 12 |

None of the report's kinds fits a browser script. "Plain module" stands here for a static script file, served by `Plug.Static` (Phoenix's file server) under the `script-src 'self'` rule the Content-Security-Policy already has. No bundler, no dependency.

**What is left.** About 76 lines (about 88 with seven script tags): the root document and the 14-line theme boot, the one inline script that keeps its nonce.

**Order of work.**

1. Move only (no code; a document). The decision record: a new ADR on where the browser client lives and how it is tested. It names the triage's ruling of 2026-09-05 for one static file, the nonce Sprint 11 shipped instead, the alternatives (one file or several; browser-native script modules; hooks written beside their component, which LiveView calls colocated hooks; the boot inline or as a blocking script in `<head>`) and N-86 (the security lens's finding that two gates which read source text are narrower than the guard they name). Nothing below starts before the owner merges it.
2. Move only (tests only). `ClientSource.all/0` returns today's text. The 27 path reads in 23 test files change their source expression and nothing else. N-86's widened gate reads `all/0` and `priv/static/*.js`. A new test holds every `phx-hook` name (the attribute that attaches a hook) in a template to a registered hook and the reverse (20 = 20 today). Two new browser tests pass on today's inline client: every live route boots, connects and leaves an empty console; the theme menu changes `<html data-theme>` and the choice survives a reload.
3. Move only. The theme control to `priv/static/theme.js`, byte for byte. The same commit adds the file to the list served ahead of the login (`lib/portfolixir_web/endpoint.ex:64`), takes the inline count from 3 to 2, and updates the two other policy pins named below and the policy's moduledoc (`lib/portfolixir_web/plugs/content_security_policy.ex:5-7`).
4. Move only. The client to `priv/static/app.js`, byte for byte at its present indentation. `all/0` reads the file; `test/portfolixir_web/live/info_tips_test.exs:164-169` reads `GET /app.js`; the inline count goes from 2 to 1. The PR body shows that lines 69 to 2427 of the old file equal the new file. Medium risk: every page's boot path. The first load is about 116 KB uncompressed.
5. Move only (a gate). `node --check priv/static/*.js`, a syntax check, in a CI job that pins Node (`.github/workflows/ci.yml:193`), and a line in the Required Local Checks of `AGENTS.md` with its reason.
6. Move only (shape). De-indent `app.js` by 10 spaces. The helper gains `hook/1`, `method/2`, `block/1`, and the 11 test files that cut by absolute indentation move to them in the same commit. Delete the orphaned comment (`:1128-1133`). A diff that ignores whitespace (`git diff -w`) shows the deleted comment only. This is the owner's stopping point: one cached, checked file.
7. Move only, and only if the ADR chose several files and the one file has run for a sprint. First the hook list onto `window`, then the head (`core.js`) and the tail (`boot.js`); then `pages.js`, `charts.js`, `navigation.js`, `feedback.js`, `overlays.js`, one commit each. Each file opens with its own guard. Step 2's smoke test runs on every route at every commit.
8. Changes behaviour. One story each, with its own test, and a board where the operator sees a change: `AreaTabs` and `DetailTabs` share the 56 lines one copied from the other; the sunburst's centre sentence is composed on the server only (`:1202-1209`); the server sends the privacy stand-in text instead of a second copy in the script (`:103`).

**Pins before the first move.** Holding today: 23 Elixir test files that read the client's source text (7 under `test/invariants/`, 3 under `test/portfolixir_web/components/`, 13 under `test/portfolixir_web/live/`; 27 reads by path and one over HTTP at `test/portfolixir_web/live/info_tips_test.exs:164-169`). Three policy pins: `test/invariants/csp_inline_script_test.exs:44` (the count of inline scripts), `test/portfolixir_web/plugs/content_security_policy_test.exs:38` (the script ids), `test/portfolixir_web/plugs/static_headers_test.exs:41` (the static file list). `test/portfolixir_web/controllers/error_view_test.exs:214-231` holds the inline boot equal to `priv/static/theme-boot.js`. The browser suite under `test/browser` is the only place the client runs.

Missing, written in step 2: a browser test that clicks the theme menus (no test reads or runs the control script); a browser smoke test over every live route, the gate `docs/decisions/0037-phoenix-18-liveview-1x.md:112-114` asked for; the hook-name test. Two gates only `refute` over this one file and check nothing after a move (`test/invariants/tooltip_dom_construction_test.exs:16-21`, `test/portfolixir_web/live/securities_live_test.exs:2603`); N-86's widened gate closes that. Nothing pins the guard (`:90-92`); that pin is written before step 7.

**Do not.**

- Do not re-indent in the commit that moves. Eleven test files cut their piece of the script out by absolute indentation (`test/invariants/css_chart_axis_test.exs:42`, `test/portfolixir_web/live/info_tips_test.exs:199`), and one test pins the name `Hooks` (`test/invariants/css_chart_axis_test.exs:242-243`).
- Do not version the script with `?vsn=` from `BuildVersion` (the build's version value). `Plug.Static` then answers with a one-year immutable cache (`deps/plug/lib/plug/static.ex:185`, `:374`), and the value is one per commit, or "unknown" (`lib/portfolixir/build_version.ex:1-30`). Let the browser ask on every load whether the file changed (ETag), as it does for `app.css` (`lib/portfolixir_web/layout_view.ex:59`).
- Do not cut the middle out first. The hook list sits at the head (`:94`) and the `LiveSocket` at the tail (`:2300-2303`, `:2425`). Each cut file needs its own copy of the guard (`:90-92`), or five blocks start running without the LiveView client. `data-confirm` stays in the first script (`:83`). No `async` and no `type="module"` on a script tag (`:2534`).
- Do not move the theme control before its browser test exists. The browser walk sets the theme through storage (`test/browser/privacy_leak.js:389-396`), which runs the boot, not the control. A missing entry at `lib/portfolixir_web/endpoint.ex:64` leaves both menus dead with every gate green.
- Do not put `node --check` into the pre-commit job. That CI job sets up Python and Elixir only (`.github/workflows/ci.yml:28-60`); Node is pinned in three other jobs (`:193`, `:286`, `:357`).

**Decision or ADR.** An owner decision before any move, recorded as a new ADR or an amendment of ADR-0037 (the Phoenix 1.8 upgrade, which describes the hand-written client). Why: the security triage of 2026-09-05 prescribed the move to a static file (`_bmad-output/planning-artifacts/security-review-triage-2026-09-05.md:79`, `:266-271`), and the Sprint 11 plan, adopted by the owner's merge, set a per-request nonce instead, which Sprint 11 shipped (`_bmad-output/implementation-artifacts/sprint-plan-2026-09-07-sprint11.md:67-75`). The plan does not name the static-file shape or give a reason, and no ADR records either shape. The move would return to the triage's shape, so it reopens what Sprint 11 decided. The owner decides two things: whether the client moves at all, and one file or several. The first proposal cut the client into seven files, one job each; the review stops at one file, because the cut adds load order and six guards and removes nothing a test can see. The rule at `_bmad-output/project-context.md:38-40` ("No asset pipeline", no bundler) holds either way and gets the scripts' names. The policy text sent to the browser does not change; its descriptions do (`lib/portfolixir_web/plugs/content_security_policy.ex:5-7`, `lib/portfolixir_web/router.ex:4-7`, `SECURITY.md:55-58`), and so does the design language's hook count (`_bmad-output/planning-artifacts/design-language/DESIGN.md:830`, `:1186`; `EXPERIENCE.md:54`).

**Findings that ride along.**

- R-122 (O7-03): this split is its fix; the client is sent once and cached, a tool checks its syntax, and tests stop depending on where it lives.
- R-158 (O7-02): the chart hook sends one page's two zoom events from all three pages that draw the chart; its own story, never inside a move commit.
- R-157 (O7-01) and R-158 (O7-02) together: a test that every event a shared component or hook names has a handler on each page is red today; the two fixes land before it or with it.
- N-86: the widened gate over every static script is the same edit as step 2's; it is done once, under N-86.

### `lib/portfolixir_web/components/app_shell.ex` (1,210 lines at e014f284)

**Jobs it does today.** Function components only: the file keeps no state and handles no event. About 87 % of its call sites are for the shared kit (icons, notes, results, row menus), not for the shell.

| Job | About lines | What it does |
|---|---|---|
| Shell frame | 246 | `shell/1` draws the sidebar, the top bar (title, privacy switch, theme and accent menus, language switch) and the main area; it reads the locale, the privacy mode, the login setting and the build version |
| Navigation table | 190 | `nav_groups/0` lists the sidebar entries; `nav_current?/2` says which entry a page address belongs to; `wealth_tabs/1` and `transactions_tabs/1` list the tabs of two areas |
| Version foot | 46 | `version_foot/1` shows the installed version at the sidebar's foot, linked to its release or commit |
| Area tab row | 46 | `area_tabs/1` draws the tab row inside Wealth, Transactions and News |
| Inline result | 112 | `inline_result/1` shows the busy line and the result note beside the control that started an action; its × sends `dismiss_result` to the page |
| Data notes | 128 | `data_note/1` is the one note in three severities, with the clamp; `data_note_fold/1` folds several notes into one line |
| Invisible-text note | 79 | `invisible_text_note/1` marks stored text that carries invisible characters and spells them out |
| Row menu | 94 | `row_kebab/1` is the three-dot button named for its row, `row_menu/1` the menu behind it, `row_name/1` the row's name for both |
| Section ⓘ and stale-quote marker | 44 | `section_info/1` puts a section's method sentences behind one ⓘ; `quote_stale/1` prints "stale · date" under a price |
| Icon set | 203 | `icon/1` draws one of 49 named glyphs, or a fallback circle for an unknown name |

**Proposed split.** The review names the modules; the paths are proposed here, in the folder of the existing components.

| New module (path) | Kind | Takes | About lines |
|---|---|---|---|
| `PortfolixirWeb.Icon` (`lib/portfolixir_web/components/icon.ex`) | function-component module | `icon/1` and its glyph paths (`:1007-1209`); the sidebar's own wrapper `nav_icon/1` goes, and its two calls become `icon/1` at size 14 | 215 |
| `PortfolixirWeb.DataNote` (`lib/portfolixir_web/components/data_note.ex`) | function-component module | `data_note/1`, `data_note_fold/1`, `invisible_text_note/1`, the severity words and glyphs (`:684-880`, `:995-1005`) | 215 |
| `PortfolixirWeb.InlineResult` (`lib/portfolixir_web/components/inline_result.ex`) | function-component module | `inline_result/1` and its note (`:543-654`); it uses `DataNote` | 115 |
| `PortfolixirWeb.RowMenu` (`lib/portfolixir_web/components/row_menu.ex`) | function-component module | `row_menu/1`, `row_kebab/1`, `row_name/1` (`:882-975`) | 100 |
| `PortfolixirWeb.Navigation` (`lib/portfolixir_web/navigation.ex`), with idea I35 | plain module | the two tab lists, `nav_groups/0`, `nav_current?/2` (`:310-500`), in the shape I35's board decides | 195 |
| `lib/portfolixir_web/components/app_shell.ex` | stays in place | `shell/1`, `version_foot/1`, `area_tabs/1`, the theme, locale and privacy helpers, `section_info/1`, `quote_stale/1` | 590, then 400 |

**What is left.** About 590 lines once the four kit modules have left, and about 400 once the navigation table leaves with I35. It still owns the shell, the version foot, the tab row and two small components (`section_info/1`, `quote_stale/1`), which its one-line description (the moduledoc) then has to name.

**Order of work.**

1. Move only (a test, nothing moves). One test renders the shell and holds each sidebar entry's glyph to the output of `icon/1` at size 14. It passes on today's `nav_icon/1`.
2. Move only. `Icon`: 105 tags in 29 other files and 13 inside the file. The two `nav_icon/1` calls (`:58`, `:68`) change to `icon/1` in the same commit. The comment that tells Sobelow, the security scanner, why the raw markup is safe (`:1016`) stays directly above `icon/1`. Leaves about 1,000 lines. The widest diff, and first because every later module draws icons.
3. Move only. `DataNote`: 93 opening and 93 closing tags in 23 files. Leaves about 790 lines.
4. Move only. `InlineResult`: 11 result slots in 9 files. Leaves about 680 lines.
5. Move only. `RowMenu`: 21 call sites and 8 closing tags in 7 files. `test/invariants/row_menu_keyboard_test.exs:81` names the new file in the same commit. Leaves about 590 lines.
6. Move only (text). The counts and the rules that name the file: `_bmad-output/planning-artifacts/design-language/DESIGN.md:826-827`, `:894`; `EXPERIENCE.md:54`; `_bmad-output/project-context.md:118-119`; the moduledoc, naming `section_info/1` and `quote_stale/1`; the comment-only mentions in tests.
7. Move only. `Navigation`, together with I35 (the idea to tidy the app's organisation, which may redraw the Wealth tabs) and after its board. A change of the lists' shape is I35's story, not this step's. Leaves about 400 lines.
8. Changes behaviour. Follow-ups, each its own commit with its own test: a `values:` list on the icon's `name`, so a misspelt literal name warns at compile time; `Securities.RowContextMenu.menu/1` (the Securities page's own copy of the menu shell) on the shared shell; the Views glyph (R-159 (O7-05)).

Every step regenerates both translation catalogs (70 reference lines to this file in each). Steps 2 to 5 are about 340 textual edits in 36 files, 160 of them in the six largest LiveViews. They land as one commit group before the LiveView splits of the other lanes or after them, never between two of their steps.

**Pins before the first move.** Holding today, under `test/portfolixir_web/components/`: `data_note_clamp_test.exs`, `data_note_fold_test.exs`, `inline_result_test.exs`, `section_info_test.exs`, `version_foot_test.exs`. Under `test/portfolixir_web/live/`: `navigation_test.exs`, `area_tabs_design_test.exs`, `shared_components_live_test.exs`, and `quote_freshness_live_test.exs:185-188`, which pins the clock glyph's path data. Also `test/portfolixir/input/default_ignorable_characters_test.exs:278`, `:287`; `test/portfolixir/agent_entry_docs_test.exs:726-727`; and `test/invariants/row_menu_keyboard_test.exs:81-94`, which allows one three-dot button in the web layer, by file path. Outside the test suite: `mix compile --warnings-as-errors` catches a call site left behind in `lib/`, `mix gettext.extract --check-up-to-date` the moved references, `mix sobelow --skip --exit` a separated skip comment.

Missing, written in step 1: no test renders a sidebar glyph. A test that names a moved function fails when it runs, not when it compiles. Three mentions in comments go stale without a failure (`test/portfolixir_web/live/imports_live_test.exs:140`, `test/portfolixir_web/live/floor_second_pass_live_test.exs:39`, `test/invariants/row_menu_keyboard_test.exs:77`).

**Do not.**

- Do not treat the icon step as a pure rename. `nav_icon/1` (`lib/portfolixir_web/components/app_shell.ex:537-541`) calls the private `icon_paths/1` (`:540`) that leaves with `Icon`. The `values:` list is a second change and a separate commit.
- Do not leave forwarding stubs (`defdelegate`) in `AppShell`. A call through a stub is not checked against the component's declared attributes (for example `lib/portfolixir_web/components/app_shell.ex:589`), so 283 tags would lose their unknown-attribute and missing-attribute warnings.
- Do not turn `inline_result/1` or `row_menu/1` into a LiveComponent (a component with its own state and events) to own the dismiss R-157 (O7-01) found missing (`lib/portfolixir_web/live/snapshots_live.ex:171`). The result lives in page state at 11 slots in 9 pages, and a component's events skip the per-event session re-check (N-57).
- Do not build one table of areas, tabs and routes before I35's board. The tab list has three producers and two consumers; `lib/portfolixir_web/live/portfolio_live.ex:372-377` matches on its links and `lib/portfolixir_web/live/news_live.ex:267-283` holds the third list. A changed shape breaks Wealth's period links without a compile error.
- Do not change markup inside a move: not the Securities menu shell (`lib/portfolixir_web/live/securities/row_context_menu.ex:23-33`; whether it gets the phone caption of `lib/portfolixir_web/components/app_shell.ex:925-927` is open), and not the 24 hand-written tooltip blocks that `section_info/1` could replace on 11 pages.

**Decision or ADR.** No ADR and no owner decision for steps 1 to 6. The agents' rule at `_bmad-output/project-context.md:118-119` ("Function components: `app_shell`, `security_chart` only") names the module list and is reworded in step 6, because four new component modules make it false. Step 7 waits for idea I35 (`_bmad-output/planning-artifacts/ideas.md`, row I35); it touches ADR-0022 (the areas and their tabs) only if I35 moves a tab between areas.

**Findings that ride along.**

- R-123 (O7-04): this split is its fix; the kit leaves the module that holds the sidebar, and 19 of the 39 calling files stop depending on the shell.
- R-157 (O7-01): a small fix of its own, independent of the split (S3 after the second reading; AD-8 puts it on the Snapshots polish list): one `dismiss_result` clause in `SnapshotsLive` (the Snapshots page) and one test over all nine pages that render a result slot.
- R-159 (O7-05): the sidebar's Views entry draws the funnel the design language gave to "filter"; a follow-up in step 8, on a board or the Views polish list.
- N-57: stays untouched, because no LiveComponent is introduced.

---

**What applies to the next four files (`lib/portfolixir/imports/applier.ex`, `lib/portfolixir/lifecycle/security_merge.ex`, `lib/portfolixir/portfolios/performance.ex`, `lib/portfolixir/ledger.ex`).** None of the four is a page, so no new part is a LiveComponent: each is a plain module of functions, a function in another context, or a struct. Nothing was run; sizes are estimates from reading the files at e014f284.
A line number without a path, such as `:578`, means the file of its section. A delegate is a one-line forward that keeps an old public name working after its code has moved; a facade is a module made of such forwards. A gate is a test that reads source code and fails when a rule is broken. An actor is the named party a write is recorded under: the operator, an agent or an import.
A payload sentence, the text an API answer carries to say how a figure is computed, moves with the rule it states and never into a module of texts. R-001 (O8-01) is such a sentence that drifted from its rule.
Delegates keep public names only. Decision records also cite private functions by name, so each section names the dated notes it needs; a dated note says where the named code now lives and changes no decision.
Nothing forces callers through a facade: the web layer already calls nine `Ledger.*` and six `Performance.*` submodules directly, and the one boundary gate (`test/invariants/web_repo_boundary_test.exs`) guards database access only.
Risk tier means code where a mistake changes money figures, quantities or import idempotency; ADR-0036 (`docs/decisions/0036-risk-tier-rides-the-batch.md`) gives such a step its own commit group and verification pass.

### `lib/portfolixir/imports/applier.ex` (3,245 lines at e014f284)

**Jobs it does today.** The module turns a parsed import file into bookings, in one database transaction. Its dry run is the same row loop with the writes switched off; the counts the Imports page shows before the confirm come from it. The line counts partition the file.

| Job | About lines | What it does |
|---|---|---|
| Contract | 290 | The description of the re-import contract, the result record (what an import did, as counts and lists), the types, and the time limit of one import's transaction. |
| Entry and run modes | 295 | Starts an import, with the operator's mapping or automatic, or its dry run, in one transaction under the locks. Holds the two `economic_keys` reads, which tell the import correction the key each new row would be booked under, without writing. |
| Preview counts | 455 | `reimport_counts/3`: what the file would do (new, already imported, held back) before anything is written, for the Imports page and the import correction. |
| Row identities, hash layers, held-back glue | 175 | Each row's content hash; which stored layer already holds it (a live booking, or a hash a merge retired); hits in other portfolios; three helpers that hold a row back when another portfolio already has it. |
| Run state and after-commit | 80 | Builds the map the loop carries from row to row; starts enrichment, logos and the rate backfill after the commit. |
| Portfolio choice and account planning | 415 | Picks or creates the portfolio; binds the file's account names to accounts (the operator's choices, remembered names, unmapped names); reports matches by a former name; puts created accounts into a tagged bucket. |
| Row loop, outcome recorders, counters | 415 | Judges each row in the contract's fixed order and records what happened to it and why. |
| Security resolution and mappings | 385 | Finds a row's security by the ladder of identifiers or the operator's mapping, or creates it. |
| Account resolution and lazy creation | 215 | Finds a row's accounts; creates an account together with its first inserted row. |
| Booking attributes, legs, insert, anchors | 495 | Turns a row into a booking by kind; derives the settlement legs of a cross-currency trade (the amount in the security's currency, the amount paid, the rate between them); inserts with the journal entry; skips duplicates by content; reports a row behind a restated balance anchor. |

**Proposed split.** Four new files, three functions into modules that exist. The apply itself stays one module.

| New module (path) | Kind | Takes | About lines |
|---|---|---|---|
| `lib/portfolixir/imports/applier/result.ex` | schema or struct | The result record under its unchanged name; 28 test files match it by that name. | 45 |
| `lib/portfolixir/buckets.ex` (exists) | context function | The bucket tag for the accounts an import created (`:1641-1695`), as one function that takes the actor, the tag and the two lists of account ids. | 55 leave the file |
| `lib/portfolixir/ledger/settlement_guard.ex` (exists) | context function | The settlement-leg rule, once: the trade amount or quantity times price, the conversion at the booking date, the ratio to six places. It answers the legs, "no rate" or "converts to zero" as three different answers. The copy in `lib/portfolixir/ledger/settlement_backfill.ex:143-185` goes. | 20 leave the file |
| `lib/portfolixir/imports/entry.ex` (exists) | schema or struct | `unimportable_reason/1`, the rule that says why a row cannot be imported at all, with its two lists of kinds (`:1834-1842`, `:1876-1892`). It reads one parsed row and nothing else, so it goes to the row's own module. | 30 |
| `lib/portfolixir/imports/row_identity.ex` | plain module | The row hashes (`row_hashes/2`), the hashes of rows split off a row, both readers of "which stored layer holds this hash" (one per file, one per row), and the hits in other portfolios (`cross_portfolio_hits/2`). | 190 |
| `lib/portfolixir/imports/reimport_counts.ex` | plain module | `reimport_counts/3` and its 16 private functions. A read; it runs the Applier's dry run through one opened function. | 430 |
| `lib/portfolixir/imports/account_plan.ex` (optional) | plain module | The six planning functions and four helpers that bind file names to accounts without touching the run state. | 125 |
| `lib/portfolixir/imports/applier.ex` | stays in place | Both run modes with the two `economic_keys` reads, the run state, the row loop with its recorders, security and account resolution, booking attributes, the insert, the anchors; delegates for the public names that left. | 2,450; 2,300 with the optional step |

The review also lists reads that belong to other contexts and gives them no step: which stored rows hold a set of content hashes (`:1188-1192`, `:1906-1907`; a Ledger read and a Lifecycle read), the portfolio of an account and a portfolio's first cash account (`:1425`, `:2626-2635`; Portfolios), portfolio ids and names (`:1021-1023`, `:1037-1040`; the existing `Portfolios.list_portfolios/0`, `lib/portfolixir/portfolios.ex:17`), and the two after-commit Catalog calls (`:1258-1259`; one documented Catalog function). Until they move, the new modules of steps 4 and 5 query other contexts' tables directly, as the Applier does today.

**What is left.** About 2,450 lines after steps 1 to 5, about 2,300 with step 6. The file still owns the transaction and its locks, both run modes, the row loop in the contract's order, security and account resolution and the one insert. A remainder of 1,150 lines would need two more modules, which are not proposed (first bullet under "Do not").

**Order of work.**

1. Move only. The result record into its own file. The Applier gains one short-name line for it.
2. Move only. The bucket tag into `Buckets`. One call stays (`:334`), with the function that trims the tag's text. The moved function receives the actor as an argument (`:1651`).
3. Move only (two copies become one function; no stored value may change). Risk tier, its own commit group. The leg rule into the Ledger. The Applier and the import correction (`lib/portfolixir/imports/correction.ex:924`) treat both refusals as "no legs"; the backfill keeps counting them apart. The pin of R-043 (O8-02) is written first and kept.
4. Move only. `unimportable_reason/1` to the row's module; `RowIdentity` with both readers of the hash layers. Delegates stay for `row_hashes/2` (6 outside call sites) and `unimportable_reason/1` (1). The loop still asks the hash layer at `:1756` and `:1859`, in today's order.
5. Move only. `ReimportCounts`. A delegate stays for `reimport_counts/3`, which ADR-0050 and ADR-0053 cite 7 times and which row 20 of the lock table names (`test/support/lock_table.ex:70`; the lock table is the test file that lists which function takes which locks in which order). The Applier opens one function, its dry run, for the counts (`:687`); the two modules then call each other, and that is said here, not hidden. The three types the counts define (`:767`, `:952`, `:1107`) stay in the Applier. Two small helpers are used on both sides of the new boundary (portfolio names `:1021`, the list of included portfolios `:1075`); the review does not place them, and this step has to.
6. Move only, optional. The pure account planning. 10 call sites stay in the run modes. Skip it if the sprint ends at step 5.

No step needs the next. Moving the booking's write behind the Ledger (`:3026-3084`, `:3185-3209`) is finding R-030 (A4-03)'s step and not one of these.

**Pins before the first move.** Existing, all under `test/portfolixir/imports/`: `applier_test.exs`, `reimport_contract_test.exs`, `applier_mapping_test.exs`, `reimport_counts_mapping_test.exs`, `held_back_reimport_test.exs`, `import_hash_test.exs`, `applier_settlement_test.exs` (`:373`, `:408` call the counts by name), `refused_row_booked_test.exs:150` (calls the row hashes by name); 14 test files name the counts. For the leg rule: `test/portfolixir/ledger/settlement_backfill_test.exs:140`, `:177-180`, which hold the backfill's two refusals, and `test/portfolixir/fx/history_backfill_test.exs:765-767`, which compares the import's legs with the backfill's for one file. The lock table's rows 9, 10 and 20 (`test/support/lock_table.ex:59-60`, `:70`) name the Applier's functions; the delegates keep them true. No test that reads this file by path breaks in steps 1 to 6. Missing:

- Step 3: the pin of R-043 (O8-02). One test runs both paths today (`test/portfolixir/fx/history_backfill_test.exs:765-767`), with two rows at one exact rate (1 EUR = 1.25 USD), so it cannot see a change of the rounding in one copy. The pin adds a rate that does not divide evenly, a sale with taxes, a triangulated pair, GBX and the zero amount; the three stored fields are equal on both paths.
- Step 5: not a test but a check that must run: the type check (`mix dialyzer`), because `lib/portfolixir/imports.ex:75`, `:86`, `:132-137` name the three types.

**Do not.**

- Do not split out security resolution and account resolution as modules. They write the loop's outcome (`:2348`, `:2476`), call its recorders and counters at 10 sites (`:2127`, `:2043`, `:2098`, `:2400-2402`, `:2573-2574`, `:2646-2647`) and share the helper that fakes a stored row in the dry run (`:2428`, called at `:2661`). As modules they would be the row loop in three files.
- Do not move the two `economic_keys` reads with the counts. One of them runs the automatic mode itself, inside the caller's transaction (`:578`). They are run modes and stay; then the counts need one opened function at one site (`:687`).
- Do not let the one leg rule lose the difference between "no rate" and "converts to zero". The Applier answers both alike (`:2828-2829`); the backfill tests the zero amount first and counts the two apart (`lib/portfolixir/ledger/settlement_backfill.ex:149-153`, `:162-176`).
- Do not move the insert out of this file as a "move". `:3063` is the file's only write call. The day it leaves, the gate that checks that every writer names its actor no longer sees the import as a writer (`test/write_actor_test.exs:88-91`, `:280-295`), and a second gate names the insert by this path (`test/invariants/import_hash_writers_test.exs:43`). That step changes two gates.
- Do not reorder the row checks or spread the recorders. The order of the checks is the re-import contract (`:1844-1846`). The six recorders, the functions that note a row's outcome, prepend to lists that are reversed once after the commit (`:1241-1252`); recorder, counter and list stay in one file.

**Decision or ADR.** No owner decision and no amendment. Step 3 adds a dated note to ADR-0015 (`docs/decisions/0015-cross-currency-settlement-fx-rate.md:231`, `:377`), which cites the Applier's leg function by name, unless a delegate keeps that name; `AGENTS.md` asks for it ("Do not silently change architecture decisions"). Step 3 is risk tier under ADR-0036 because the three legs are stored money fields.

**Findings that ride along.**

- R-126 (O8-05): fixed by steps 4 and 5; the preview's counts leave the Applier.
- R-043 (O8-02): fixed by step 3; one leg rule instead of two copies held together by one ADR sentence and one test at one exact rate.
- R-138 (O8-06): `cross_portfolio_hits/2` leaves the Applier's public names in step 4 and has two outside callers in its new module.
- #925 (polish list, Imports): the two readers of "which layer holds this hash" land in one file in step 4; the per-row queries stay as they are.
- Finding R-030 (A4-03): the importer's own copy of the booking write; its own step, with both gates changed in it.
- No key yet (review, S3): the dry run builds an account record through a variable (`:2661`), which the gate that lists every such builder cannot see; its list has the builder of a security (`test/invariants/identity_freeze_writers_test.exs:103`) and no entry for the account's. Not part of the split.

### `lib/portfolixir/lifecycle/security_merge.ex` (2,801 lines at e014f284)

**Jobs it does today.** One use case in phases: merge security S into security T, so that every booking of S becomes a booking of T. The module answers a preview (what the merge would do, with a digest, the checksum the apply must present again) and applies it in one transaction. The line counts partition the file.

| Job | About lines | What it does |
|---|---|---|
| Contract | 300 | The module's description (202 lines, restating ADR-0050 §9), the names of the guards, what a merge carries, the ten apply steps. |
| Entry, consent, transaction, locks | 255 | Answers a preview; takes the operator's consent and choices; opens the transaction and locks both securities and their depots in a fixed order. |
| Build and remedy | 100 | Builds the plan, evaluates the opposite direction, names the remedy when a guard refuses. |
| Loading, under the row locks | 190 | Reads every booking, quote, category assignment, target, event and alias of both securities; during an apply it locks these rows as it reads them. |
| Plan, memberships, outcome, linearity | 295 | Pairs equal rows, plans splits and bucket memberships, folds positions and FIFO trades (sales matched to the oldest purchases) for both values of the operator's choice, and checks that the quantities add up. |
| Guards | 425 | The 13 refusals and the linearity guard, each with the sentence an operator or an agent reads. |
| Identity resolvability and its read-back | 225 | Proves that every identifier of both securities still leads to the target, before the writes and again after them. |
| Identifiers and carry | 240 | Which identifiers the target takes over; which quotes, assignments, targets and events move. |
| Preview shape and digest | 260 | The map the page and the API show; the checksum over it. |
| Writes and record | 505 | The ten write steps, the read-back checks, the snapshot of the source and the stored record of the merge. |

**Proposed split.** Five new modules by phase; the file stays the transaction script. The paths below use a new directory, which needs step 1 first; flat beside the existing merge modules in `lib/portfolixir/lifecycle/` works too. Each new module imports the two shared merge helpers the file imports (the guard builder `MergeFlow` and the figure sampler `MergeFigures`).

| New module (path) | Kind | Takes | About lines |
|---|---|---|---|
| `lib/portfolixir/lifecycle/security_merge/terms.ex` | plain module | Six one-line helpers that several phases use: a split ratio and its display form, a split event's display form, the name of a depot and of a portfolio, and "is this value filled". | 25 |
| `lib/portfolixir/lifecycle/security_merge/resolvability.ex` | plain module | The identity guard with the 15 functions under it, and its read-back after the writes (`:2602-2623`). | 225 |
| `lib/portfolixir/lifecycle/security_merge/identifiers.ex` | plain module | Identifiers and carry, with the two lists of fields the target may adopt and fields that follow (`:282`, `:285`). It reads no database. | 240 |
| `lib/portfolixir/lifecycle/security_merge/preview_shape.ex` | plain module | The function that builds the preview map (`view/2`) and the eight display functions left after `Terms`. It reads no database. | 200 |
| `lib/portfolixir/lifecycle/security_merge/guards.ex` | plain module | The 13 guards, the linearity guard and their sentences. | 420 |
| `lib/portfolixir/lifecycle/security_merge.ex` | stays in place | Entry, locks, loading, plan, outcome and linearity, digest, writes, record. | 1,700 |

Three unlocked reads belong to other contexts and have no step in the review: the identity an importer recorded when it created a security (`:791-814`, today the merge's own query on the audit journal's table; a Journal read), the count of research notes that name a security (`:693`, `:834-842`, by a raw table name; a Knowledge function, as the prediction count beside it already is, `:694`), and all portfolio ids for the identity lock (`:444`; a Portfolios read). Not proposed: one template for the three merge modules (security, cash account, depot). 27 private function names recur in all three, but the lock order differs per kind and has to be readable in one place.

**What is left.** About 1,700 lines, 202 of them the module's description. The file still owns the transaction, the lock order with the loading in it, the plan with both outcomes and their read-back, the digest, the ten writes and the record. A remainder of 1,000 lines would need a `Plan` module (loading, plan and outcome in one module), which is rejected (first bullet under "Do not").

**Order of work.**

1. Move only (no product code changes). The gate that forbids a refusal sentence to write a stored identifier (ISIN, WKN, ticker) into its text scans `lib/portfolixir/lifecycle/*.ex` (`test/invariants/merge_refusal_identifiers_test.exs:17`). The pattern becomes recursive, so it reaches the new directory.
2. Move only. `Terms`. 21 call sites gain a module name.
3. Move only. `Resolvability` with its read-back. Two calls stay: one in the guard list (`:1156`), one among the write steps.
4. Move only. `Identifiers`. Two calls stay (`:869`, `:565`). The gate that lists every place the code builds a write of a security or account record names a function of this block by this file's path (`test/invariants/identity_freeze_writers_test.exs:101`); it fails loudly and is edited in the step.
5. Move only. `PreviewShape`. One call stays in the function that builds the plan (`:568`), before the digest.
6. Move only. `Guards`. One call stays in the plan (`:889`). Never before step 1.

Every step is risk tier (the module says so itself, `:5`) and leaves the merge as it is. Every step also adds its new file, in the same commit, to each test list that names the merge modules by path.

**Pins before the first move.** Existing: the six files `test/portfolixir/lifecycle/security_merge_test.exs`, `security_merge_chain_test.exs`, `security_merge_reimport_test.exs`, `security_merge_carry_test.exs`, `security_merge_legacy_split_test.exs` and `security_merge_news_test.exs`; `test/portfolixir_web/controllers/api/v1/security_merge_controller_test.exs` for the preview over the API; the digest test at `test/portfolixir/lifecycle/security_merge_test.exs:1133` (two previews of an unchanged pair carry the same digest). Two gates name functions that stay in the file and are not touched (`test/invariants/identity_freeze_writers_test.exs:262`, `test/invariants/import_hash_writers_test.exs:405`). Missing:

- Step 6: step 1 is the missing pin. Without it the moved sentences are no longer scanned and the test stays green.
- Step 5: a test that fixes the preview's set of keys. A key added to the preview changes every digest; the digest test compares two previews made by the same code and would not notice. No such test was found.

**Do not.**

- No `Plan` module. The loader takes the row locks itself (`:772`, `:664-702`); it is the station "their bookings" of the lock order (`test/support/lock_table.ex:63`). And the plan's fold of both outcomes (`:997-1102`) has to stay with its read-back after the writes (`:2359-2401`); both use the same sampling functions and nothing else does.
- Do not move the guards before step 1. The pattern at `test/invariants/merge_refusal_identifiers_test.exs:17` does not reach a subdirectory, and `:43` only asserts that this one file is in the list. 31 guard functions and their 14 sentences would leave the gate unseen.
- Do not move the locked reads (`:661-714`) into the other contexts one by one, as finding R-080 (A4-05) proposes. The lock order would be spread over five contexts. If they move, each read takes a lock option and one function here still calls them in today's order.
- Do not name the preview module `View`. In this file "view" already means the bucket view a depot belongs to (`:950`).
- Do not leave the six one-liners behind and do not cut the description in a move step. The ratio's display form is called from four guards (`:1809`, `:1810`, `:1873`, `:1897`) and the event's display form from the stored record (`:2665`, `:2791`, `:2792`), so without `Terms` the guards and the record call into the preview. A docs test reads a sentence of the description (`test/portfolixir/docs_test.exs:4048`).

**Decision or ADR.** None. No decision record names a private function of this file. Two existing rules apply: ADR-0036 (`docs/decisions/0036-risk-tier-rides-the-batch.md`), under which each step is its own commit group, and ADR-0054 §4 (`docs/decisions/0054-the-agents-surface-one-authority-named-principals-escaped-text.md`), the rule the gate of step 1 serves.

**Findings that ride along.**

- No O8 finding is about this file; the lane's verdict is one long transaction script that can be split by phase.
- Finding R-080 (A4-05) (Lifecycle's own queries on other contexts' tables): the locked reads stay here; the three unlocked reads above can move.
- Idea row I9: the 202-line description restates ADR-0050 §9; which of the two counts when they differ is open and not part of this split. R-017 (A4-02) found one such difference, in `MergeFifo`'s description (`lib/portfolixir/lifecycle/merge_fifo.ex:18-22`), not in this file.
- Lead, not traced: every preview builds the whole plan of the opposite direction and reads only its guards (`:617-626`); no timing was taken.

### `lib/portfolixir/portfolios/performance.ex` (2,604 lines at e014f284)

**Jobs it does today.** The module computes the performance series. "The walk" is its day-by-day pass over a portfolio's bookings that values every day; the return figures, the chart, the contribution table and the stacked chart all read it. 16 public names, 44 call sites in 11 modules outside. The line counts partition the file.

| Job | About lines | What it does |
|---|---|---|
| Memo shells and contribution entries | 260 | Serve the walk for one portfolio and for a view across portfolios through the derived layer (the store of computed figures), with a read of the previous result; two unlisted entries run the walk with a window for the contribution table and the stacked chart. |
| Head, walk assembly, loaders | 235 | The description; runs one portfolio's walk, names cash that could not be valued, stamps the result with its booking count and compute time; reads the portfolio's rows. |
| View walk and view merge | 160 | Walks each portfolio of a view on its own rows and sums the results per day. |
| Period summary | 345 | Chains a period's daily returns, the money-weighted return, the wealth figures, the basis sentence, unvalued cash; the period terms (where "this year" or "max" starts and ends). |
| Daily walk | 520 | Applies each day's bookings, values the day, records flows and trade costs. |
| Price cursor | 320 | Each security's price per day, from stored closes and the walked portfolio's own trade prices; the latest point on or before the day counts. |
| Basis steps | 125 | The part of a day's value change that only restates a price no market showed; it is taken out of the return the way a deposit is. |
| Day valuation and rate series | 130 | Values quantities and cash in the base currency from exchange rates loaded once before the walk; a missing rate path counts zero. |
| Kept figures and their merge | 480 | The contribution table's sums per position and the stacked chart's terms per day, kept while the walk runs; their merge across a view's portfolios. |

**Proposed split.** Four new modules, one move into `Fx` (the context that owns exchange rates), and one price reader whose home the owner's decision sets. The walk stays in the file with its memo.

| New module (path) | Kind | Takes | About lines |
|---|---|---|---|
| `lib/portfolixir/portfolios/performance/summary.ex` | plain module | The period summary and the period terms; one public function for the start and end of a period, which is written twice today (`:660-663`, `:2115-2121`); the test "is this day in the window"; the list of periods; the parts of the basis sentence about the money-weighted return and unvalued cash. It reads no database. | 350 |
| `lib/portfolixir/portfolios/performance/view_merge.ex` | plain module | The per-day sum of a view's portfolio walks: `merge_analyses/4` and the six functions under it. | 120 |
| `lib/portfolixir/fx.ex` (exists) | context function | A dated rate between two currencies from the stored euro rates (the hub series) loaded once, pence sterling (GBX) included: load, advance, rate, first date with a path. Beside the existing functions that compute a rate from hub rates loaded once (`lib/portfolixir/fx.ex:145-212`). It replaces `:1947-1982`, `:1993-2017`, `:287-303` and the copies in `lib/portfolixir/portfolios/snapshot_comparison.ex:215`, `:322-370` and `lib/portfolixir/portfolios/performance/benchmark.ex:633-687`. R-036 (D2-04) counts a fourth copy, `lib/portfolixir/portfolios/risk_metrics.ex:236-296`, which this row does not take. Not named "cursor": that word means a paging token in this code base. | 95 leave the file |
| the price of a security on a day; home set by the ADR-0010 amendment | plain module | The price cursor (`:1438-1759`), as the one reader the walk and the valuation (`lib/portfolixir/portfolios/valuation.ex:708-715`) both use, with the part of the basis sentence about prices. | 320 |
| `lib/portfolixir/portfolios/performance/day_value.ex` | plain module | The value of a day's quantities and cash, the conversion that counts a missing rate path zero (`to_base/3`), the two functions that say why a position counted zero, the value of a booking's legs and the cost of a trade. | 150 |
| `lib/portfolixir/portfolios/performance/kept.ex` | plain module | The contribution's sums and its table of booking kinds, the stacked chart's day terms, and the four functions that merge kept figures across portfolios (`:2495-2557`). | 475 |
| `lib/portfolixir/portfolios/performance.ex` | stays in place | Both memo shells, the two entries, walk assembly, the view walk's orchestration, the daily walk, the basis steps; delegates for the names that left. | 1,100; 2,130 with only `Summary` and `ViewMerge` out |

**What is left.** About 1,100 lines after all five steps; about 2,130 if only `Summary` and `ViewMerge` have left. The file still owns the two memoised reads with their keys, the daily walk and the basis steps: one job with its memo. A remainder of 300 lines would need the daily walk in a `Walk` module of its own, which is not proposed (first bullet under "Do not").

**Order of work.** The fix of R-001 (O8-01) (S1) is step 1, before any move. The fix of R-004 (D4-01) (S1) is no step of this split; it lands before step 5 (section 11 of the triage, step 1; decided as AD-6).

1. Changes behaviour. The fix of R-001 (O8-01), in three parts. First the three missing pins below. Then the sentence, which moves no figure: the walk's basis sentence says a security without a quote is priced by its own latest trade (`:803-805`). That is the valuation's rule. The walk's rule is: closes and the walked portfolio's own priced buys and sells form one list by date, the latest point on or before the day prices the position, a priced delivery prices a security that has no price yet, and a held security without any point counts zero. Correct the sentence, and its copy in the contribution payload (`lib/portfolixir/portfolios/performance/contribution.ex:400-402`). Then the one price reader, which waits for the ADR-0010 amendment, with its failing test first: the pin of the difference, rewritten to the rule the amendment decides. Three calls stay in the walk (`:946`, `:1037`, `:1040`). If the walk's figures move, the computation version of the five walk analytics rises (`lib/portfolixir/derived/registry.ex:52-53`, `:75-76`, `:88`); that number keeps stored results of older code from being served.
2. Move only. Risk tier. `Summary`. Seven delegates stay (21 outside call sites, 3 more for the list of periods, which `lib/portfolixir/portfolios/performance/contribution.ex:166` reads while compiling). Four helpers the walk's assembly uses stay with the walk: the empty result (`:857-867`), the first day to walk, the list of suspect dates, and the stamp of booking count and compute time (`:619-625`).
3. Move only. `ViewMerge`. Two calls stay (`:450`, `:460`).
4. Move only (three copies become one; no figure may change). The dated rates into `Fx`. This is the fix of R-036 (D2-04) for three of its four copies. Each caller keeps its own treatment of a missing rate and its own seed date, because the copies differ in both. Needs the amendment of ADR-0007 that R-036 (D2-04) asks for.
5. Move only. `DayValue`, then `Kept`. Three hooks, the calls by which the walk hands a booking or a day to the kept figures, stay in the walk at four sites (`:950`, `:1064`, `:1216`, `:1267`), and the window calls stay in the two entries. After step 1 of idea row I34 (register the stacked chart's read in the derived layer), which edits the same lines (`:403-452`). Dated notes in ADR-0051 (`:584`) and ADR-0015 (`:127`), which cite two private functions that move.

In step 1 the pins and the sentence need no decision; the price reader waits for the owner's, and steps 2 to 5 come after it. Steps 2 and 3 need nothing after them. Step 4 does not wait for steps 2 and 3.

**Pins before the first move.** Existing: `test/portfolixir/portfolios/performance/walk_payload_pin_test.exs` holds the walk's reads to the last digit. Beside it `test/portfolixir/portfolios/performance_test.exs`, `performance_unvalued_cash_test.exs`, `performance_view_test.exs` and `performance_fx_test.exs` (GBX for the walk); under `test/portfolixir/portfolios/performance/`: `irr_test.exs`, `trade_price_basis_test.exs`, `retired_securities_test.exs`, `split_basis_test.exs`, `contribution_test.exs`, `bands_test.exs`, `contribution_memo_test.exs`, `benchmark_test.exs` and `walk_memory_bound_test.exs`, which must stay in the run of step 1 because a price reader that loads more passes every figure test and fails only there; `test/portfolixir/portfolios/snapshot_comparison_test.exs` for step 4. No test that names this file by path breaks while the memo stays in it. Missing, all written first in step 1:

- A stacked-chart read in the payload pin. The pin has none, and step 5 moves the chart's day terms.
- A GBX position in the payload pin. Its only foreign currency is USD (`:111-120` of the pin), step 4 moves the GBX rule, and no contribution or stacked-chart test covers GBX.
- The scratch test of R-001 (O8-01), kept as a pin of the difference: the walk's last value against the valuation's total for the same holdings. Today only the bond file compares the two (`test/portfolixir/portfolios/valuation_bond_characterization_test.exs:70-80`).

**Do not.**

- No separate `Walk` module. The gate that lists the files allowed to name the derived layer lists this path (`test/invariants/derived_never_a_write_source_test.exs:29`); the file that holds the memoised reads stays the file that walks.
- Do not move the rate series or the price cursor (`:1438-1759`) before the amendment: the rule change would then read as a rewrite of a new file. And never move `to_base/3` into `Fx`: it holds the walk's own rule that a missing rate path counts zero (`:1984-1991`), where `Fx` answers an error.
- Do not put the basis steps (`:1761-1883`) with the price cursor, and do not part the value functions from their twins. The basis steps value a day's legs at yesterday's rates (`:1820`) and belong to the walk's day. The function that values a position (`:1912-1920`) and the one that names its two ways of counting zero (`:2308-2320`) go into `DayValue` together, as do the conversion and its test for a rate path (`:1083`); the stacked chart's day terms (`:2235`) keep calling the functions the day's total sums (`:1890-1899`).
- Do not send the four merge functions of the kept figures (`:2495-2557`) to the view merge. They restate the kept record's first shape (`:2498-2504` against `:2149-2158`) and go with `Kept`.
- Do not let a daily point gain a key without raising the computation version (`lib/portfolixir/derived/registry.ex:52-53`, `:75-76`): the stored tier would serve the old shape and no test in these steps fails. A moved function receives today's date as an argument and never reads the clock itself; the file reads it once per read, at 8 default sites.

**Decision or ADR.** An owner decision, recorded as an amendment of ADR-0010 (`docs/decisions/0010-ttwror-performance-series.md`), before the price reader of step 1 and so before every move: which rule says what a position is worth on a day. The valuation takes the latest stored close, however old, and only without any close the latest own trade across all portfolios; the walk takes the newer of close and own trade of the walked portfolio. For the same holdings on the same day the two give different values (R-001 (O8-01), S1), so one has to yield. Either the valuation takes the newer of close and own trade, or the walk stops letting a trade re-price a quoted security; the second moves the return of quoted portfolios and changes the pinned test at `test/portfolixir/portfolios/performance/trade_price_basis_test.exs:135`. The amendment also corrects the ADR's `:129-130`, which names a price source the walk does not call. Step 4 also needs the amendment of ADR-0007 (`docs/decisions/0007-currency-conversion-with-exchange-rates.md`) that R-036 (D2-04) asks for: the dated form in memory becomes part of what `Fx` owns. Steps 2, 3 and 5 need no decision of their own.

**Findings that ride along.**

- R-001 (O8-01) (S1): fixed in step 1, before any move. In the run recorded under that finding the two rules differ by 400.00 on 10,200.00 where a buy follows the last stored close; a delivered position the walk values at 500.00 counts 0 in the valuation; a position the valuation values at 700.00 counts 0 in the walk.
- R-125 (O8-04): fixed by steps 2, 3 and 5; the rules of the contribution table and of the stacked chart leave the walk's file.
- R-138 (O8-06): the read of one portfolio's previous walk (`previous_analysis/2`, `:170-187`) has callers in tests only; keeping or removing it needs the owner's word on per-portfolio pages. The finding's fourth name, the list of cash accounts that could not be valued (`unvalued_cash_accounts/3`, `:737`), is public with one caller in its own module and one test.
- R-004 (D4-01) (S1): a view's trade-cost rule asks whether the cash account is in the view (`trade_cost_in_scope?/2`, `:1132-1142`, called by `trade_cost/2`); AD-6 decides that it asks for the shares. Fixed with section 11 of the triage, step 1, before step 5 moves `trade_cost/2`. The fix moves the computation versions of the two performance analytics.
- Idea row I34: the stacked chart's read is never memoised; its step 1 comes before step 5 here.
- R-036 (D2-04): the dated EUR-hub conversion stands in four modules beside `Fx`. Step 4 is its fix for the walk, the snapshot comparison and the benchmark; the fourth copy (`lib/portfolixir/portfolios/risk_metrics.ex:236-296`) is not in the review's step and is added there or left with a reason.

### `lib/portfolixir/ledger.ex` (2,345 lines at e014f284)

**Jobs it does today.** The top module of the ledger context: bookings, the holdings derived from them and FIFO trades (sales matched to the oldest purchases). 34 public names; 99 call sites in 40 modules outside reach every job through this one file, 52 of them from the web layer. The write path shares no private function with any read. About 50 lines of head are not in the table.

| Job | About lines | What it does |
|---|---|---|
| Lists and counts | 150 | Lists, filters and counts bookings for pages, the API and other contexts; reads one booking. |
| Cash balances | 55 | Each cash account's balance and the date of its last activity. |
| FIFO trades, open lots, sale preview | 600 | Closed trades, the lots still open, which lots a sale would consume; three payload sentences about these figures. |
| Holdings rows | 425 | Holdings per portfolio and per security with cost, price and the split of profit into price and currency; three payload sentences about the rows. |
| Moving-average cost fold | 330 | The running average cost of each position, booking by booking; the position costs the merges read. |
| Write path and checks | 520 | Creates, updates and deletes a booking, sets a cash balance, writes derived settlement legs; each with its journal entry, its locks and its refusals. |
| Positions and negative holdings | 145 | Held quantities per portfolio and per security; the data-quality report of positions below zero. |
| Latest trade prices | 60 | The most recent own trade price per security, the valuation's fallback for a security without a quote. |

**Proposed split.** `Ledger` stays the facade and keeps all 34 names; the jobs move into five modules.

| New module (path) | Kind | Takes | About lines |
|---|---|---|---|
| `lib/portfolixir/ledger/listing.ex` | plain module | Lists, filters, counts, the read of one booking and the shared ordering of bookings. Named `Listing`, not `Transactions`: that is one letter from `Ledger.Transaction`, the booking's own record, which most of the code names. | 150 |
| `lib/portfolixir/ledger/writes.ex` | plain module | The write path and its checks, with the comments that argue the lock order (`:1796-1805`, `:1915-1945`). | 520 |
| `lib/portfolixir/ledger/cost_basis.ex` | plain module | The cost fold, the position costs, the list of booking kinds that leave cost untouched (`:747`), and the six helpers the fold and both read engines share: a booking's unit price in the security's currency, the currency of its settlement leg, the average unit cost, the lot of a position and two smaller ones. It reads no database. | 360 |
| `lib/portfolixir/ledger/holdings.ex` | plain module | The holdings read with its three sentences. The row decoration that exists twice under two key names (`:535-566`, `:999-1028`) becomes one. | 420 |
| `lib/portfolixir/ledger/trades.ex` | plain module | The FIFO read, the open lots and the sale preview, with their three sentences. | 650 |
| `lib/portfolixir/ledger/settlement_guard.ex` (exists) | context function | The settlement-leg rule comes in from the importer and the backfill (R-043 (O8-02); step 3 of the Applier's section). | 20 come in |
| `lib/portfolixir/ledger.ex` | stays in place | The facade: 34 names in 44 forms as delegates with their descriptions; the cash balances; the latest trade prices; the position reads until they have a home. | 600 to 750 |

Two reads belong to other contexts and have no step in the review: a portfolio's base currency (`:403-408`, a Portfolios read) and the names of securities and depots (`:2190-2202`, Catalog and Portfolios reads). The importer's copy of the booking write (finding R-030 (A4-03)) would come into `Writes`.

**What is left.** About 1,350 lines after steps 1 to 3; about 600 to 750 after step 4. The file is then the facade: every public name with its description, because the 99 call sites and the decision records look there, plus the cash balances, the latest trade prices and, until they have a home, the position reads. Without the descriptions it would be about 250 lines; that version is not proposed.

**Order of work.**

1. Move only. `Listing`. Nine delegates stay with their descriptions; the FIFO read and the position reads call the new module.
2. Move only. Risk tier, its own commit group; no figure can move. `Writes`. Six delegates stay: the five writers, each with its first parameter named `actor`, and the locking read `locked_cash_account_currencies/1`; the delegate of the create keeps its default third argument. The gate that lists every writer of an import hash names a function by this file's path (`test/invariants/import_hash_writers_test.exs:42`) and is edited in the step.
3. Move only. Risk tier. `CostBasis` with the shared helpers. The position costs stay as a delegate (4 outside call sites, the merges); the read engines call 6 names at 9 sites. The gate that checks every booking kind is named in the fold reads this file's source (`test/invariants/cost_fold_kind_coverage_test.exs:22`); it fails loudly (`:29-30`) and is edited in the step. Dated notes in ADR-0033, ADR-0031 and ADR-0028.
4. Move only. `Holdings` and `Trades` with their sentences. Waits for finding R-081 (A5-02), which decides who prices a holding. Dated notes in ADR-0015, ADR-0033 and ADR-0028.

Steps 1 to 3 each ship alone.

**Pins before the first move.** Existing: for step 1 `test/portfolixir/ledger_transactions_filter_test.exs` and the API's list tests; for step 2 `test/write_actor_test.exs` (five writers of this file, a floor of 72 writers in all), the 35 test files under `test/portfolixir/ledger/` and the lock table's rows 2, 3, 4 and 17 (`test/support/lock_table.ex`); for step 3 `test/invariants/cost_fold_kind_coverage_test.exs` and `test/portfolixir/ledger_holdings_for_portfolio_test.exs`; for step 4 `test/portfolixir/ledger_holdings_for_security_test.exs`, `test/portfolixir/ledger_trades_test.exs` and the API contract tests of the six sentences. 277 test files call the Ledger through the facade and notice no move. Missing: the review names no test to write. One gate gets weaker in step 2 and nothing replaces it (third bullet below).

**Do not.**

- No module of texts. The six payload sentences state the rules beside them (`:1217`, `:1263`, `:1323` for the FIFO figures; `:1280`, `:1292`, `:1310` for the holdings rows) and move with their engines in step 4.
- Do not move the cost fold without its helpers and its list. The fold calls the unit-price helper (`:707`, defined at `:1334` among the FIFO helpers) and the average unit cost (`:691`); without them step 3 does not compile. The list of cost-neutral kinds (`:747`, `:812`) moves in the same commit, because the gate reads list and fold from one file (`test/invariants/cost_fold_kind_coverage_test.exs:22-27`).
- Do not write the writers' forwards as hand-made wrapper functions. The gate judges a forwarded writer by the text of its first parameter (`test/write_actor_test.exs:805-810`), which must be named `actor`. A delegate cannot carry the check of the actor's type, so after step 2 the gate reads the name only. A wrapper that drops the create's default argument passes the gate unseen.
- No `Ledger.PricePoint` module and no position reads in `Ledger.Positions`. The price helper (`:586-591`) is the Ledger's call up into the valuation, whose reader calls back down into the Ledger's latest trade prices; a module would give that cycle a name before finding R-081 (A5-02) decides it. `Ledger.Positions` is a fold without queries (`lib/portfolixir/ledger/positions.ex:25`, `:41`), while the three position reads load the whole ledger (`:2086`, `:2113`).
- Do not part the writers that share one lock order, and keep the cash-balance write and the leg write in the same file as the writers they call: the gate follows calls inside one file only (`test/write_actor_test.exs:213-217`, `:627-629`). The write path's reads of two other contexts' tables (`:1973`, `:1978`, `:2005`) are part of the lock order and stay.

**Decision or ADR.** No amendment; no decision changes. One point is the owner's, taken by merging a dated note in ADR-0001 (`docs/decisions/0001-modular-phoenix-monolith.md:27`): a context's top module may be a facade over submodules, which nothing written settles today. Further dated notes, because the records cite private functions by name: ADR-0033 (`:35-36`, `:298`), ADR-0031 (`:47`) and ADR-0028 (`:313`, `:390`) in step 3; ADR-0033 (`:45`), ADR-0028 (`:299`) and ADR-0015 (`:131`, `:304`, `:346`) in step 4. Step 4 waits for finding R-081 (A5-02).

**Findings that ride along.**

- R-124 (O8-03): fixed by this split.
- R-043 (O8-02): the leg rule comes into the Ledger; independent of steps 1 to 4.
- R-138 (O8-06): the latest trade prices of one portfolio (`latest_trade_prices/1`, `:2224-2243`) have one test as their only caller; remove them and correct the description, which names the walk as a reader (`:2227-2228`) although the walk does not call it. With the ADR-0010 amendment of R-001 (O8-01).
- R-001 (O8-01) (S1): the holdings rows and the open lots are priced by the valuation's rule (`:379-385`, `:586-591`); the amendment decides whether that rule stays.
- R-002 (D1-01) (S1): under AD-1's recommended option the as-of cut goes into this file's current reads. `cash_balances/1` (`:149-154`) and the position reads (`:2064-2074`, `:2085-2091`) stay in the facade; `cost_lots/1` moves in step 3 and the trades read in step 4. Its fix lands first (section 11 of the triage, step 1).
- R-005 (A4-01) (S1): the cost fold the depot merge reads (`position_costs/1`, `:661-670`) gets the function that folds every booking of the affected securities. It lands before step 3 moves the fold (section 11 of the triage, step 3).
- R-024 (O1-02) (S2): `holdings_for_security/2` (`:613-641`) answers the total and names the rows left out. It lands before step 4 moves the holdings read (step 1 of the securities split).
- Finding R-081 (A5-02): who prices a holding; it gates step 4.
- Finding R-030 (A4-03): the importer's copy of the booking write; it would come into `Writes`, with two gates changed.

---

### `mcp-server/src/tools.ts` (6,054 lines at e014f284)

**Jobs it does today.** The file holds all 166 tools of the MCP companion. A tool is one named operation an agent can call; each ends in exactly one request to the JSON API. The jobs stand one after another, so the parts of one tool family lie up to 3,000 lines apart, and a new tool touches up to five places. Line numbers without a path are this file's.

| Job | About lines | What it does |
|---|---|---|
| Types and the builder | 46 | the shape of a tool record, and `tool()`, the function every tool is declared with |
| Shared prose and primitives | 102 | sentences that several descriptions repeat, and small argument checks such as a bounded date or capped text; 25 constants, 17 of them used by more than one family |
| Input contracts | 3,459 | each tool's argument schema and its validator; 315 constants. `COMPACT_ANSWER_TOOLS`, the list of seven tools that answer without indentation, sits in the middle (`:3464-3489`) |
| Declarations | 1,289 | the 166 tool records with the name, title and description an agent reads; 46 % of the file's bytes and all 73 lines longer than 500 characters. By the ten families proposed below, the tools interleave in 25 runs (a run is a stretch of one family's tools) |
| Hints | 122 | the four flags a host reads per tool: reads only, destroys, safe to repeat, reaches outside. They follow the HTTP method, which the file learns by running its own router once per tool when the companion starts; five exception lists name 14 tools |
| Dispatch | 60 | `listTools` and `allTools` (what a host is shown) and `callTool`, which checks the profile (the set of tools this companion admits), validates the arguments and picks a read-only client before a request leaves |
| Routing | 867 | `apiCall`, one switch with 166 cases; each case is one API request (82 GET, 31 POST, 24 DELETE, 16 PUT, 13 PATCH) |
| Route and schema helpers | 102 | eight small functions that build a query string, a path or a request body; two are shared, six serve one family |

**Proposed split.** Twelve source files and one test helper. The registry stays in `tools.ts`; one module of shared pieces and ten family modules go under `mcp-server/src/tools/`. A family module holds its tools' schemas, validators, declarations and routes together: constants, one exported list of declarations per run, and one exported route function. It holds no hint, no profile and no validation call. A family imports `shared.ts`, the validation library (`zod`) and the API client's type, and nothing else. Only `tools.ts` imports a family.

| New module (path) | Kind | Takes | About lines |
|---|---|---|---|
| `mcp-server/src/tools.ts` | stays in place | the registry: the hints with their five lists, the tool list built at start, `listTools`, `allTools`, `callTool`, `COMPACT_ANSWER_TOOLS`, the lookup from a tool's name to its route, and today's order as 25 spreads (a spread puts one family's list into the full list at that place, so no name is typed again) | 300 |
| `mcp-server/src/tools/shared.ts` | plain module | the two record types, `tool()`, `objectWith()` (adds properties to a schema), `withQuery()` (builds a query string) and the 24 constants that two or more families use: the id, empty-object, dry-run-delete, date, capped-text, benchmark, bucket-list and merge schemas and the sentences they share | 190 |
| `mcp-server/src/tools/system.ts` | plain module | contract, version, journal, merges: 4 tools | 130 |
| `mcp-server/src/tools/catalog.ts` | plain module | securities, quotes, exchange rates, trades, sales: 21 tools, with `isinChangeBody` (the body of an ISIN change) | 810 |
| `mcp-server/src/tools/knowledge.ts` | plain module | events, notes, predictions: 16 tools | 660 |
| `mcp-server/src/tools/accounts.ts` | plain module | cash accounts and depots: 19 tools, with the rename and re-import sentences (`:2783-2815`) | 570 |
| `mcp-server/src/tools/ledger.ts` | plain module | transactions, splits, holdings, cashflow: 17 tools, with both halves of the rule that an inbound delivery needs a price (`:394-434`, `:1047-1061`) | 520 |
| `mcp-server/src/tools/portfolios.ts` | plain module | the 14 `portfolios.*` tools (12 reads, 2 writes) and the five figure reads of a view, their declared twins: 19 tools, with the twin sentences, the schemas of the two bands reads and `riskPath` (builds the risk read's path) | 800 |
| `mcp-server/src/tools/planning.ts` | plain module | classifications, targets, policy rules, plans, snapshots: 31 tools | 950 |
| `mcp-server/src/tools/scoping.ts` | plain module | buckets, the six other `views.*` tools, settings: 13 tools | 245 |
| `mcp-server/src/tools/tax.ts` | plain module | the four tax families: 15 tools, with `withoutKeys` (drops keys from a request body) | 460 |
| `mcp-server/src/tools/news.ts` | plain module | news: 11 tools, two of them the news labeller's (a second agent profile) | 490 |
| `test/support/mcp_source.ex` | test helper | the one place an Elixir test asks for the companion's text: the tool names over every source file, their count held to the contract manifest (the API's own list of endpoints and tools), and the tools text over `tools.ts` and `tools/` | 60 (the writer's estimate; the review gives none) |

The five view reads sit beside their portfolio twins because the pairs share sentences and schemas (`:61-99`; `mcp-server/test/scope-twins.test.ts`). Leaving them in scoping costs seven more shared names and nothing else. The families follow the tool-name prefix, the only cut a scan can check; the API reference groups differently.

**What is left.** After step 6 `mcp-server/src/tools.ts` is about 300 lines, about 280 after step 7: the registry, which owns the hints, the order of the published list and the checks before every call. The largest family module is planning at about 950 lines. The 73 long lines are not cured; they move into the family files.

**Order of work.** No figure fix waits in this file. One S2 fix is a commit of its own and never inside a move: R-020 (O6-03), which says in the description of the contract read what a read without `since` answers and so changes published bytes. Section 11 of the triage lets R-020's small step ride with lens 1's Batch 1. The one gate fix, the tool half of R-144 (M1-01), lands in step 2, before any text moves.

1. Move only (no code; a document). A dated amendment to ADR-0002 in the planning PR: the layout, the import rule, and where invariant B2 reads (the test that holds the companion to one way out, the API client). Nothing below starts before the owner merges it.
2. Move only (tests only; the source is unchanged). `test/support/mcp_source.ex` is written. The Elixir read sites (ten, in eight test files) read through it, except `test/portfolixir/docs_test.exs:4044`, which names the file in a list of paths and follows its text in step 6. `mcp-server/test/published.test.ts:124` reads the same set of files. The path scan demands one request site per tool (`test/invariants/scope_b2_outbound_chokepoint_test.exs:758`), and the import rule becomes a check in that invariant. An order test over all 166 names is added. Each new check gets an attack case, an input it must refuse (`docs/development/story-workflow.md:77-81`). This edits invariant B2, so it is its own commit group with its own verification pass (the risk tier of `docs/development/sprint-workflow.md`).
3. Move only. `shared.ts`. `tools.ts` is then about 5,890 lines. Low risk.
4. Move only. News. First, in a commit of its own, remove the one marker pair a move would tear apart (a marker pair is two comment lines that fence one story's item): "Sprint 27 N7" opens at `:3318` and closes inside `COMPACT_ANSWER_TOOLS` at `:3469`. Then 31 constants, 11 declarations and 11 cases move. This step sets the shape for every later one: the declared list ends in a spread, and `apiCall` looks the route up by name and keeps its message for an unknown tool (`:5940`). About 5,400 lines after. Low risk: news is the last run of the order and has the densest tests (12 test files).
5. Move only. Tax, knowledge, ledger, one commit each: the families declared in one run. About 3,770 lines after. Low to medium risk: the constants of knowledge and ledger are many small blocks between `:111` and `:3232`.
6. Move only. System, scoping, accounts, then catalog, planning, portfolios, one commit each: the families with two to six runs, the three largest last. `test/portfolixir/docs_test.exs:4044` is pointed at `accounts.ts` in the accounts commit. The last commit updates the three documents that tell an agent where a tool is added (`docs/architecture.md:120`; `_bmad-output/project-context.md:142`, `:154`; `_bmad-output/planning-artifacts/architecture.md:611`, `:930`). About 300 lines after. Medium risk.
7. Changes behaviour (own decision; a rewrite, not a move). Routes as data: a tool's method, path and body become trailing arguments of its `tool(...)` call, and one request site remains in `tools.ts`. The start-up run of the router (`routedMethod`, `:4969-4989`) and the families' route functions go. An agent sees no change. Two gates are rewritten in the same change (`mcp-server/test/published.test.ts:123-136`; `test/invariants/scope_b2_outbound_chokepoint_test.exs:2075-2122`). The call stays positional: the four scans that collect tool names and `test/portfolixir/ledger/kind_prose_sync_test.exs:35-40` read name, title and description as three literals in that order. Medium to high risk.
8. Changes behaviour (own decision). Family order: 25 spreads become 10. The published list changes its order and nothing else. The stored copy of that list (the golden surface, under Pins) is captured again, `mcp-server/test/tools.test.ts:13-188` is rewritten, and a contract entry says what an agent sees change.

Each commit of steps 3 to 6 can be checked without reading it: the sorted lines of `tools.ts` before equal the sorted lines of `tools.ts` and the new files after, apart from import, export and spread lines.

**Pins before the first move.** Holding today, in the companion's own suite: the golden surface (`mcp-server/test/transport.test.ts:502-538` with `mcp-server/test/fixtures/stdio-surface.json`), a stored copy of the published tool list that is compared byte for byte; `mcp-server/test/published.test.ts:351` (one route per published tool, read from the source); the strict TypeScript build (`mcp-server/test/transport.test.ts:432-440`); the schema budget (`mcp-server/test/schema-budget.test.ts`), which caps the size of the published list; `mcp-server/test/scope-twins.test.ts`; and the 20 of 28 companion test files that import `../src/tools.js` and need no edit. In the Elixir suite, loud when text moves: `test/portfolixir_web/controllers/api_v1_contract_meta_test.exs:44-58` (tool names against the manifest), `test/portfolixir_web/controllers/api_v1_target_batch_test.exs:128-136`, `test/invariants/scope_b2_outbound_chokepoint_test.exs:753-764` and `:2075-2122`, `test/portfolixir/ledger/kind_prose_sync_test.exs:32-40`, `:51-58`, `test/portfolixir/docs_test.exs:4044-4046`.

Missing, written in step 2. No scan forbids a module from calling a family's route past `callTool`; the import check is that pin. The golden surface and `mcp-server/test/tools.test.ts:13-188` hold 164 names: the labeller's two tools (`mcp-server/src/profiles.ts:38-47`) have their place in the order pinned by nothing (`mcp-server/test/news-labels.test.ts:59-64` sorts before it compares), and step 4 moves them first; the order test over all 166 names closes that. The golden surface proves the published list, not the routes; the routes rest on `mcp-server/test/published.test.ts:351` and `mcp-server/test/tools.test.ts`.

**Do not.**

- Do not add a barrel (a file that only re-exports), a `registry.ts`, or an explicit list of the 166 names for the order, and let no family import another family or the registry. The registry calls every family's route function while it loads (`:4969-4989`, `:5002-5013`), so an import cycle stops the companion at start; and `test/portfolixir_web/controllers/api/v1/policy_rule_version_hints_test.exs:21`, `:44-52` reads three hint lists from this path.
- Do not run a formatter, rewrap the 73 long lines, rename, reorder cases or declarations, or strip the 126 marker lines (comments that fence one story's item) in a move commit. Tests pin the shape of the text, not only its path (`test/portfolixir/ledger/kind_prose_sync_test.exs:35-40`, `:54-58`; `test/portfolixir/docs_test.exs:4044-4046`; `test/portfolixir_web/controllers/api_v1_target_batch_test.exs:130-135`), and the order of cases differs from the order of declarations at 24 positions that nothing pins (`:5106-5127`, `:5330-5359`, `:5672-5734`).
- Do not move a hint list, the compact-answer list or a profile list into a family (`:4898-4949`, `:3464-3489`; `mcp-server/src/profiles.ts:144-336`). The hint also appends a sentence to a tool's description and picks the read-only client (`:5005-5009`, `:5065`), so the hints, that sentence and `callTool` are one unit, evaluated after every family.
- Do not change a rule or a pin inside the split. The two halves of the delivery-price rule move word for word (`:394-434`, `:1047-1061`); the five maxima that refuse where the API caps stay as they are (`:1335`, `:3368`, `:3434`, `:3556`, `:3598`); `mcp-server/test/tools.test.ts` (5,991 lines) and the fixtures stay; no generated file replaces the copied sets (`AGENTS.md:154-156`).
- Do not point the path scan and the route read at all of `mcp-server/src`. `mcp-server/src/api-client.ts:131` holds a request call the scan would report as unreadable (`test/invariants/scope_b2_outbound_chokepoint_test.exs:2076`, `:2101-2102`). They read `tools.ts` and `tools/`; only the name scan reads every source file.

**Decision or ADR.** A dated amendment to ADR-0002 (`docs/decisions/0002-thin-mcp-over-json-api.md`, which has none today), in the planning PR, with no decision reversed. Why: the single-egress invariant names this file (`test/invariants/scope_b2_outbound_chokepoint_test.exs:753-764`), and the project's rule is that an architecture decision is not changed silently (`AGENTS.md`, Hard Rules; I38, the idea row behind this audit). R-097 (M1-02)'s three classes of what a tool may add to forwarding belong in the same amendment. Steps 1 to 7 need no contract entry; step 8 needs one (ADR-0044 §8, the surface says when it changed; `mcp-server/test/transport.test.ts:343-345`). The owner decides three things: whether step 7 is done, whether step 8 is done, and, outside the split, whether the delivery-price rule stays in the companion alone (so decided, `_bmad-output/planning-artifacts/epics.md:80`) or moves into the ledger, which changes how money data is booked. Decided here and flippable by a comment: the five view reads beside their twins. The marker rule of the Sprint 25 retrospective names `tools.ts` as a shared file (`_bmad-output/implementation-artifacts/sprint-25-retro-2026-11-05.md:193-198`); after the split its list of files needs restating. ADR-0054 (profiles, hints) and ADR-0056 §9 (compact answers) are untouched while their lists stay where they are.

**Findings that ride along.**

- R-112 (M1-05): this split is its fix. A family's four parts stand in one file, and a new tool touches one family file and, where it applies, one list in the registry.
- R-144 (M1-01) (S3): the docs gate reads 40 of the 166 tool names. That half is closed in step 2, before any move; its route half (170 of the 182 routes) and the substring match are not part of this split.
- R-145 (M1-04): the pin that holds the 28 closed sets copied from the application reads them by constant name through step 2's helper. The sets stay in TypeScript, each in its family.
- R-097 (M1-02): the five requests the companion answers differently from the API are not changed inside the split. Each family carries its rule word for word; the fixes are their own stories.
- N-57 (the security lens's finding of a second way in that skips the per-call check), in the companion's form: after the split the families export their route functions, a way to send a request past the checks of `callTool` (`:5049-5065`). Step 2's import check guards it; step 7 removes it.
- F31 (merge the `views.*` and `portfolios.*` twins): not a precondition. It is triaged with its trigger (`_bmad-output/planning-artifacts/ideas.md:129`) and becomes a change inside `portfolios.ts`.
- I39 (the tests on trial): whether `mcp-server/test/tools.test.ts` splits is its question, not this split's.
