# Architecture review 2026-11: the S1 and S2 findings in full

This file is section 5 of the architecture review of 2026-11: its ten S1 and nineteen S2 findings.
The ten S1 and seventeen of the S2 stand in full. Two S2, R-018 and R-019, are held, as the "Disclosure handling" of `security-review-triage-2026-11-11.md` orders: they stand here by ID and severity only, and each is filed with its fix.
It belongs to the triage of the same date in this folder, `architecture-review-triage-2026-11-24.md`, which holds sections 1 to 4, 6 and 8 to 13; section 7 is `architecture-review-splits-2026-11-24.md`.
Its file:line references are at the audited commit `e014f284`.

**Status: PROPOSED** with the triage it belongs to — adopted by the merge of the planning PR that carries both (ADR-0026 step 1 as amended on PR #780: the merge is the signature).

**What is printed here and what is not.** The security triage's "Disclosure handling" does not publish the security report's reproductions. This file reads that rule as follows. The two held entries are withheld whole. For the other 27 the scratch test sources and the run commands are withheld: they are in private evidence held by the owner, not in the repository. What stays is each entry's description of its run and what the run printed, on synthetic fixtures and seeded ledgers only. The 27 are correctness and structure findings that the review does not hold, and a finding about a figure cannot be judged without the figures. That reading is decided here, and the owner can flip it on the planning PR before the merge: a wrong figure in a system with one operator is not a way in, and each fix begins with the test its reproduction describes.

**Words the entries use.** A "test slot" (or "the slot") is one of the audit's isolated containers, and `test/audit_scratch/` is the scratch directory inside its throwaway copy of the repository. `arch_calls.tsv` is the audit's call table, the compiled call graph of the project's own modules; it is a working file of the audit and not in the repository. Section 2 of the triage describes them. A decision `AD-n` is in section 10 of the triage. An ID `N-nn` is a finding of the security review of the same commit (lens 1 of the audit, "the security lens" in the entries), whose triage is `security-review-triage-2026-11-11.md`.

## 5. S1 and S2 findings in full

Each entry that is not held: what is wrong, how it was reproduced, what the run printed, what it costs to leave it, the proposed fix, and the second reading. The text is the verifier's; where the second reading or a later check corrects it, an audit lead's note says so.

### R-001 (D2-01), S1: The valuation and the performance walk resolve today's price of a held security by two rules, so the Wealth total and the walk's end value state different amounts for the same holdings, on one page and in two API reads

- **Class:** duplicate computation (two price rules for one figure); ADR drift
- **Stands against:** `lib/portfolixir/portfolios/valuation.ex:189-192`: "There is no switch to price by quotes alone: the per-category result [...] reads this rule too since #1368, so no surface prices a position two ways."; `docs/integration/api-and-mcp.md:2899-2900` (the performance read): "Securities without quotes are priced at the latest own trade price (see the valuation endpoint)."; `docs/decisions/0010-ttwror-performance-series.md:84-86`: "so the engine (and the live valuation) now price quoteless securities at the latest own trade price. A quote wins over a trade on the same day". Each rule alone is written down (the walk's at `docs/decisions/0010-ttwror-performance-series.md:153-155` and `:268-276`, the valuation's at `lib/portfolixir/portfolios/valuation.ex:14-21`); nothing records that they answer different amounts for one day.
- **Locations:** `lib/portfolixir/portfolios/valuation.ex:710-715`, `:729-734`, `:789-794`; `lib/portfolixir/portfolios/pricing_context.ex:143`; `lib/portfolixir/ledger.ex:2212-2222`, `:2232-2243`; `lib/portfolixir/portfolios/performance.ex:1508-1510`, `:1607-1622`, `:1702-1732`, `:1912-1920`; `lib/portfolixir_web/live/portfolio_live.ex:1722-1731`, `:4562-4566`; `lib/portfolixir_web/live/portfolio/contribution_table.ex:217`
- **Who meets it:** the operator on the Wealth page (`/portfolio`): the header "Total incl. cash" is the valuation's figure, the period's absolute result beside the TTWROR and the contribution table's end value per position are the walk's. The agent on `GET /api/v1/portfolios/:id/valuation` against `GET /api/v1/portfolios/:id/performance` (and the MCP tools over them).
- **Fix size:** L. **ADR amendment:** ADR-0010
- **Also reported as:** D1-02, O8-01 (same defect found by another lane, merged here)
- **On the later `main` (read, not run):** still stands. Both price rules (the valuation and the performance walk) are byte-identical. Only the Wealth page module changed, elsewhere; its header total and period result still read the two figures, 5 and 68 lines lower.
- **Audit lead's note:** The observed output below is an excerpt: blocks a2, b and c leave out the `total_value` line the scratch test printed, and a2 also its holdings line. The audit lead's re-run printed every line.

**What is wrong.**

1. The valuation's rule is `override || latest quote || latest trade` (`lib/portfolixir/portfolios/valuation.ex:710-715`). Any stored quote wins whatever its age (`:729-734`). The trade fallback is `Ledger.latest_trade_prices/0` (`lib/portfolixir/portfolios/pricing_context.ex:143`): buys and sells with a price, across all portfolios (`lib/portfolixir/ledger.ex:2212-2222`, the filter at `:2215`). A priced delivery is not in that set.
2. The walk's rule is one date-sorted list of price points per security: the quotes plus the walked portfolio's own priced buys, sells and deliveries (`lib/portfolixir/portfolios/performance.ex:1508-1510`, `:1607-1622`). Every point on or before the day replaces the carried price (`:1721-1732`); a quote wins over a trade only on the same day (rank 1 after rank 0). A delivery point seeds a security that has no price (`:1702-1719`). A day's value reads the carried price (`:1912-1920`).
3. Shape (a), a buy or sell dated after the newest stored close: the walk values the whole position at the trade price, the valuation and the holdings row at the older close.
4. Shape (b), a priced inbound delivery, no quote, no buy or sell: the walk values the position at the booked price; the valuation reports `valued: false`, `unvalued_reason: :no_price` and leaves it out of the total.
5. Shape (c), no quote, held in portfolio A by a price-less delivery, bought only in portfolio B: the valuation values A's units at B's trade price ("deliberately global (#406)", `lib/portfolixir/portfolios/valuation.ex:14-21`); A's walk has no price point and counts zero.
6. Both figures are on one page: `@valuation.total_with_cash` in the header (`lib/portfolixir_web/live/portfolio_live.ex:1722-1731`), `performance.end_value − start_value − net_external_flows` as the period's absolute result (`:4562-4566`), and `position.end_value` in the contribution table (`lib/portfolixir_web/live/portfolio/contribution_table.ex:217`).
7. `Ledger.latest_trade_prices/1` (`lib/portfolixir/ledger.ex:2232-2243`) says in its doc "the valuation and the performance walk fall back to it"; neither calls it. Its only callers are three lines of one test.

**Reproduction.**

Two scratch files under `test/audit_scratch/` (removed after the run), each run in a test slot.

`d2_01_test.exs` (domain and API, one fixture per shape):

_(scratch test source and run command: in the private evidence held by the owner)_

`d2_01_live_test.exs` (the Wealth page, shapes a and b, same bookings as above):

_(scratch test source and run command: in the private evidence held by the owner)_

**Observed output.**

`d2_01_test.exs`: `4 tests, 0 failures`.

```
[a: buy after last quote]
  Valuation.for_portfolio total_with_cash = 9800.000000000000000000
  Valuation.for_portfolio total_value     = 2000.000000000000000000
  Valuation positions = [{true, nil, :quote, "100.000000", "2000.000000000000000000"}]
  Ledger.holdings rows = [quote: "2000.000000000000000000"]
  Performance.for_portfolio end_value     = 10200.000000000000000000
  GET /valuation   -> total_with_cash="9800" total_value="2000"
  GET /performance -> end_value="10200" end_date="2026-11-11"

[a2: buy today at 104, close yesterday 100]
  Valuation.for_portfolio total_with_cash = 9960.000000000000000000
  Valuation positions = [{true, nil, :quote, "100.000000", "2000.000000000000000000"}]
  Performance.for_portfolio end_value     = 10040.000000000000000000
  GET /valuation   -> total_with_cash="9960" total_value="2000"
  GET /performance -> end_value="10040" end_date="2026-11-11"

[b: priced inbound delivery, no quote]
  Valuation.for_portfolio total_with_cash = 0
  Valuation positions = [{false, :no_price, nil, nil, nil}]
  Ledger.holdings rows = [nil: nil]
  Performance.for_portfolio end_value     = 500.000000000000000000
  GET /valuation   -> total_with_cash="0" total_value="0"
  GET /performance -> end_value="500" end_date="2026-11-11"

[c: delivered price-less into A, traded only in B]
  Valuation.for_portfolio total_with_cash = 700.000000000000000000
  Valuation positions = [{true, nil, :trade, "70.000000", "700.000000000000000000"}]
  Ledger.holdings rows = [trade: "700.000000000000000000"]
  Performance.for_portfolio end_value     = 0
  GET /valuation   -> total_with_cash="700" total_value="700"
  GET /performance -> end_value="0" end_date="2026-11-11"
```

`d2_01_live_test.exs`: `2 tests, 0 failures`.

```
[a] one render of /portfolio?period=max
  #kpi-total                      : ["9,800.00EUR"]
  [data-role=period-gain]         : ["+200.00 EUR in the period"]
  contribution table rows         : ["Stale Quote Co not held at the start 0.00+2,200.000.000.002,400.00+200.00", ...]

[b] one render of /portfolio?period=max
  #kpi-total                      : ["0.00EUR"]
  [data-role=period-gain]         : ["0.00 EUR in the period"]
  contribution table rows         : ["Delivered Co not held at the start 0.00+500.000.000.00500.000.00", ...]
```

In (a) the page states a total of 9,800.00 (10,000 deposited, so 200 below the money put in) and a result of +200.00 for the period; the contribution table gives the position an end value of 2,400.00 where the valuation gives it 2,000.00. In (b) the page states a total of 0.00 and a position with an end value of 500.00.

**Cost of leaving it.**

- 2 price-resolution rules in 2 modules: `price_for/4` with its three helpers in `lib/portfolixir/portfolios/valuation.ex` (about 30 lines) plus the trade read in `lib/portfolixir/ledger.ex:2212-2222`, against the price cursor of `lib/portfolixir/portfolios/performance.ex:1438-1759` (about 320 lines).
- Reads on the valuation's rule: the Wealth header total, the holdings rows (`Ledger.holdings_for_portfolio/2`), `GET .../valuation`, and through `Valuation.for_portfolio/2` the allocation, the risk lens and the rules read (`allocation.ex:254`, `risk.ex:126`, `policy_findings.ex:178`). Reads on the walk's rule: `GET .../performance` `end_value`, the Wealth page's absolute result, the contribution table, and by code reading the stacked chart's bands and the benchmark's `portfolio_end_value` (`performance/bands.ex:167`, `performance/benchmark.ex:403`).
- The differences in the fixtures: 400 on 10,200 (a), 80 on 10,040 (a2), 500 against 0 (b), 700 against 0 (c). Both figures are computed on every Wealth page mount.
- One test in the suite holds a walk's value beside a valuation's (`test/portfolixir/portfolios/valuation_bond_characterization_test.exs`), for a quoted bond; `test/portfolixir/portfolios/performance/trade_price_basis_test.exs:135-162` pins the walk's side alone.

**Proposed fix.**

One function that answers "the price of this security on day D" (which points count: quote, own trade, priced delivery; whose trades; the order among them), read by the valuation with D = today and by the walk per day. Which rule wins is the owner's call, because either choice moves a served money figure: the valuation following the walk changes Wealth totals for positions traded after their last close and values priced deliveries; the walk following the valuation changes the TTWROR history that `trade_price_basis_test.exs:135` pins. The smallest step that removes shape (b) alone: `Ledger.latest_trade_prices/0` counts a priced delivery as the walk has since #779. Size L (risk tier, ADR-0036; the walk's computation version moves under ADR-0039). Needs an amendment of ADR-0010, whose amendments of 2026-06-10, 2026-07-24 and 2026-09-15 state the rule for one engine each; the computation-basis sentences of the performance and contribution payloads (`performance.ex:803-805`, `performance/contribution.ex:400-402`) follow. `Ledger.latest_trade_prices/1` goes with it.

**Second reading.**

- Lens: reach (can the operator or the agent get there?). Refuted: no. Severity it would defend: S1.

  Reach holds; I found no concrete ground to refute.

  - No unreal booking. Shape (a) is an ordinary buy or sell dated after the newest close. Shape (b) is what the PP CSV import writes: an "Einlieferung" keeps its Kurs as `price` (lib/portfolixir/imports/applier.ex:2738-2749).
  - No guard. Booking writes no quote; any stored quote beats a later trade in the valuation (valuation.ex:710-715), while the walk lets the later trade replace it (performance.ex:1721-1732). `latest_trade_prices/0` excludes deliveries (ledger.ex:2215).
  - Real callers. The reproduction used the HTTP reads and one LiveView render with default arguments.
  - Same question. One render of the Wealth page shows the header total (portfolio_live.ex:1722-1731) and the same position's walk end value (contribution_table.ex:217). The performance doc itself points to the valuation endpoint for the price rule (api-and-mcp.md:2899-2900).
  - Not a documented convention. Each rule is documented alone (product-documentation.md:1838-1840, 2362-2364); the performance payload's own basis text (performance.ex:803-805) does not state the trade-after-quote rule.

  What reach narrows, without removing:
  - For a synced security the gap should close at the next sync: 6 h interval (config/config.exs:62), and the Yahoo adapter does not drop today's bar — from code reading, not run.
  - For a stopped feed it persists; the valuation marks the price stale only after 7 days (data_quality.ex:101).
  - In (b) the valuation declares the position unvalued.

  Severity: the owner's own pass rated a printed wrong total S1 (#1316, sprint22-severity-pass.md:115) and a missing figure S2 (#1332, :129). Here two printed amounts disagree, so S1.

- Lens: decided (is it already decided or tracked?). Refuted: no. Severity it would defend: S1.

  Not refuted through the DECIDED lens. Checked ADR-0010 with its four amendments, ADR-0035/0051/0052, idea rows I1 to I42 and the F rows, the three security triages, N-01 to N-93, the Sprint 11, 22 and 23 plans and retrospectives, the product documentation, the API reference and the module docs.

  Each rule is recorded alone. The walk lets a trade replace an older quote (ADR-0010:154-156, pinned by trade_price_basis_test.exs:135) and seeds from a priced delivery (:270-276). The valuation keeps a close of any age and flags it (:297-302), falls back globally (valuation.ex:14-21) and counts buys and sells only (api-and-mcp.md:2375-2381). docs/product-documentation.md:1838-1855 describes both behaviours for a stopped feed in one paragraph, the nearest thing to a record, but it never says the amounts differ.

  No record accepts differing amounts, and several bind both paths to one rule: ADR-0010:68-71 and :84-86 ("the engine (and the live valuation)"), api-and-mcp.md:2899-2900 ("see the valuation endpoint"), and Sprint 23 D-4 (sprint-plan-2026-11-02-sprint23.md:273-278). So this is drift against a decision, not a decided difference.

  Severity: the best counter-ground is the ladder's own S2 example, "a figure contradicted between two surfaces" (docs/development/sprint-workflow.md:116-118), with the same class filed S2 for #1332, #1368 and #1369 (sprint-status.yaml:1546). It does not carry: #1316, a printed total wrong by the same rule drift, was S1 (sprint22-severity-pass.md:115), and the performance read tells the agent its rule is the valuation's, so neither side declares the difference. S1 stands under the audit's rubric.

**Audit lead's re-run.** The scratch test was run again by the audit lead on 2026-11-16 in a clean slot; it passed and printed the figures above.

### R-002 (D1-01), S1: A booking dated after today counts at once in the cash balance, the positions, the holdings, the held set and the valuation, and on no day of the performance walk; the two reads state different portfolio values for today, and no read names such a booking

- **Class:** duplicate computation (two rules for "which bookings count today") / missing decision
- **Stands against:** nothing written decides it; a change would amend ADR-0004 (what "current" holdings and balances are) or ADR-0010. Each side in its own words: `lib/portfolixir/ledger.ex:131-133` "Returns the current cash balance of each cash account, keyed by `cash_account_id`, derived on read from the stored transactions"; `lib/portfolixir/ledger.ex:2060-2062` "Pass `as_of:` (a `%Date{}`) to project only transactions up to that date [...]; omit it for the current holdings."; `lib/portfolixir/portfolios/valuation.ex:5` "Prices each currently held position from its latest quote close"; `lib/portfolixir/portfolios/performance.ex:894-896` "No transactions (or only future-dated ones) mean there is nothing to walk yet."; `docs/decisions/0010-ttwror-performance-series.md:38-40` "From the first transaction to the end date, each day's portfolio value is positions (...) plus cash". For one kind the decision exists: `docs/decisions/0028-corporate-actions-as-ledger-events.md:376-377` "a future-dated effective date rejected (or hard-warned) in preview", built at `lib/portfolixir/ledger/splits.ex:471`.
- **Locations:** `lib/portfolixir/ledger/transaction.ex:335`, `lib/portfolixir/input/bounded_date.ex:28-29`, `lib/portfolixir/ledger.ex:149-154`, `lib/portfolixir/ledger.ex:2064-2074`, `lib/portfolixir/ledger.ex:2085-2091`, `lib/portfolixir/ledger/held_securities.ex:46-63`, `lib/portfolixir/ledger/trade_matcher.ex:106-119`, `lib/portfolixir/portfolios/pricing_context.ex:89-91`, `lib/portfolixir/portfolios/valuation.ex:399`, `lib/portfolixir/portfolios/performance.ex:897-907`, `lib/portfolixir/portfolios/performance.ex:938`, `lib/portfolixir/portfolios/performance.ex:953`, `lib/portfolixir_web/live/portfolio_live.ex:1729-1731`, `lib/portfolixir_web/live/portfolio_live.ex:4562-4566`
- **Who meets it:** the agent on `GET /api/v1/portfolios/:id/valuation` (`total_with_cash`) against `GET /api/v1/portfolios/:id/performance` (`end_value`), and the MCP tools over the two routes; the operator on the Wealth page, where the header's total with cash is the valuation's figure and the chart's last day and the period's absolute result are the walk's; for a buy dated ahead also on the holdings, the catalog's "held" filter, the research log's unreviewed positions and the news universe.
- **Fix size:** M. **ADR amendment:** ADR-0004 (or ADR-0010)
- **On the later `main` (read, not run):** still stands. Ledger reads, valuation, walk and date bounds are unchanged. f9fa1c1d adds a per-view held-set read that also folds every stored row. The page still shows both figures; no check against today was added.

**What is wrong.**

1. A booking's date is bounded only by 1900-01-01 to 2999-12-31 (`lib/portfolixir/ledger/transaction.ex:335`, `lib/portfolixir/input/bounded_date.ex:28-29`). The booking form's date field is a text input with an ISO pattern and no upper bound (`lib/portfolixir_web/live/transaction_management_live.ex:2908-2915`, the edit form's at `:3340`). In the run the API accepted a deposit dated today + 5 with 201. The split flow refuses a date after today (`lib/portfolixir/ledger/splits.ex:471`), as the research log does (`lib/portfolixir/knowledge/security_note.ex:233`); the ledger's 14 other kinds do not, and neither the transaction changeset nor the importers compare a date with today (`grep -rn "Clock.today" lib/portfolixir/imports lib/portfolixir/ledger/transaction.ex` prints nothing).
2. Path "every stored row": `Ledger.cash_balances/1` folds every row of the portfolio (`lib/portfolixir/ledger.ex:149-154`); `Ledger.positions_for_portfolio/2` folds every row unless `as_of:` is passed (`lib/portfolixir/ledger.ex:2064-2074`), and one of its seven call sites passes it (`lib/portfolixir/portfolios/snapshot_comparison.ex:102`); `Ledger.positions_by_security/0` folds every row (`lib/portfolixir/ledger.ex:2085-2091`); `HeldSecurities.totals_query/0` sums every row in SQL (`lib/portfolixir/ledger/held_securities.ex:46-63`); `TradeMatcher.match/1` matches every row (`lib/portfolixir/ledger/trade_matcher.ex:106-119`).
3. The valuation reads those positions and balances through its pricing context (`lib/portfolixir/portfolios/pricing_context.ex:89-91`) and adds them into `total_with_cash` (`lib/portfolixir/portfolios/valuation.ex:399`), so the total includes the dated-ahead booking.
4. Path "rows up to today": the walk groups the bookings by day and reduces over `Date.range(from, today)` (`lib/portfolixir/portfolios/performance.ex:938`, `:953`); a later day's bookings are applied on no walked day. With only dated-ahead rows there is no walk at all (`:897-907`).
5. Both figures are on one page: `@valuation.total_with_cash` in the header (`lib/portfolixir_web/live/portfolio_live.ex:1729-1731`), and `performance.end_value - start_value - net_external_flows` as the period's absolute result (`:4562-4566`).
6. No read names the booking. The performance payload's only date warning is `suspect_dates`, which lists dates before 1970 (`lib/portfolixir/portfolios/performance.ex:94`, `:909-914`); it was `[]` in the run, and the valuation payload has no key of the kind.

**Reproduction.**

Scratch test `test/audit_scratch/d1_01_future_dated_test.exs` in the slot's checkout (removed after the run).

_(scratch test source and run command: in the private evidence held by the owner)_

Call-site counts over the audit's call table (the compiled call graph of the triage's section 2; `arch_calls.tsv`, a working file of the audit that is not in the repository; columns: caller module, file, caller function, kind, callee module, callee function, arity, line):

```
for f in cash_balances positions_for_portfolio positions_by_security holdings_for_portfolio holdings_for_security; do
  awk -F'\t' -v f=$f '$5=="Portfolixir.Ledger" && $6==f' arch_calls.tsv | wc -l; done
awk -F'\t' '$5=="Portfolixir.Ledger.HeldSecurities"' arch_calls.tsv | wc -l
```

**Observed output.**

```
POST /api/v1/transactions (date = today + 5): status 201
today                                   = 2026-11-16
Ledger.cash_balances                    = 1500.000000
Valuation.for_portfolio total_cash      = 1500.000000
Valuation.for_portfolio total_with_cash = 1500.000000
Performance.for_portfolio end_value     = 1000.000000
Performance (default today) end_value   = 1000.000000
Performance net_external_flows          = 1000.000000
Performance last series day             = %{value: Decimal.new("1000.000000"), date: ~D[2026-11-16], basis: Decimal.new("0"), flow: Decimal.new("0"), cumulative_ttwror: Decimal.new("0"), trade_costs: Decimal.new("0")}
GET valuation   total_with_cash         = "1500"
GET performance end_value               = "1000"
GET performance keys matching future|suspect|warn: ["suspect_dates"]
GET performance suspect_dates           = []
GET valuation keys matching future|suspect|warn:   []

--- buy 5 @ 100 dated today + 5, quote 120 yesterday, deposit 1000 ten days ago
holdings rows                  = [true: Decimal.new("5.000000000000")]
HeldSecurities.held_ids has it = true
positions (no as_of)           = [Decimal.new("5.000000000000")]
positions as_of today          = %{}
Valuation total_value          = 600.000000000000000000
Valuation total_cash           = 500.000000000000000000
Valuation total_with_cash      = 1100.000000000000000000
Performance end_value          = 1000.000000
Contribution positions         = []

--- one deposit of 500 dated today + 5 and nothing else
Valuation total_with_cash = 500.000000
Performance end_value     = Decimal.new("0"); series length 0

3 tests, 0 failures
```

Call-site counts: `cash_balances` 7, `positions_for_portfolio` 7 (one with `as_of:`, `lib/portfolixir/portfolios/snapshot_comparison.ex:102`), `positions_by_security` 2, `holdings_for_portfolio` 6, `holdings_for_security` 2, `HeldSecurities` 10.

**Cost of leaving it.**

- Two rules for one question. Rule "every stored row": 24 call sites of the five ledger reads above in 15 files, plus 9 held-set reads in 5 files (the tenth `HeldSecurities` call is `quantity_kinds/0`). Rule "rows up to today": the walk and what is served from it, 5 of the 8 registered derived analytics (`performance_analysis`, `performance_view_analysis`, `performance_contribution`, `performance_view_contribution`, `benchmark_comparison`; `lib/portfolixir/derived/registry.ex:52-88`).
- The figure read wrongly: for a deposit of 500 dated ahead, the header total and the cash balance are 500 above the walk's end value. For a buy dated ahead, the holding is listed and valued (600 at the quote) and its cash is already spent (500 left), so the valuation says 1,100 while the walk says 1,000 of cash and no position; the contribution read lists no position. Which side is the wrong one is undecided.
- No test books a ledger row after today against either side: `grep -rn -E "(deposit!|buy!|sell!)\(.*Date\.add\((today|Clock\.today\(\)), *[1-9]" test` prints nothing.

**Proposed fix.**

Decide it once, as an amendment of ADR-0004 (or ADR-0010). It is a question about how stored money data is read, so it is the owner's. Three shapes:

- (a) a booking counts from its date: the ledger's current reads fold rows dated up to `Clock.today/0` (`filter_up_to/2` exists for positions; `cash_balances/1`, `cost_lots/1`, `HeldSecurities` and the trades read need the same cut). Size M, risk tier (ADR-0036). No walk figure moves, so no computation version moves.
- (b) every stored row counts and the walk is the exception: a read names the bookings dated after today beside `suspect_dates`. Size S.
- (c) the ledger writers refuse a date after today, as the split flow and the research log do. Size S; rows already stored and imported rows remain to decide.

Owner of the rule: the Ledger (one "counts as of" cut that the valuation and the walk both read). Size M overall; needs an amendment of ADR-0004.

**Second reading.**

- Lens: decided (is it already decided or tracked?). Refuted: no. Severity it would defend: S1.

  Not refuted through the DECIDED lens. Searched docs/decisions/, ideas.md (I and F rows), the three security triages, the feedback and backlog triages, the security lens (N-01 to N-93), plans, retrospectives, sprint-status.yaml, module docs and the API reference for a booking dated after today. No record decides it.

  Nearest records, each short of it:
  - F70 bounds every stored date to 1900-2999, but lib/portfolixir/input/bounded_date.ex:22-23 names the future dates it keeps as "a scheduled rule, an expected event, a time stop"; a booking is not among them.
  - F26, F44 and G09 refuse or cap future dates for quotes, rates, research entries and event checks; ADR-0028 §6 for splits. The other ledger kinds were never ruled on.
  - Sprint 6's retro knowingly left future-dated bookings counting in the tax staleness badge as backlog: a sibling read, not this divergence.
  - ADR-0057's "buy dated after the end" concerns a span's end, not today.

  The records lean against "intended": ADR-0027 (:47-49) describes the holdings projection as projecting the ledger "for today", and valuation.ex:154 reports as_of as Clock.today, while ledger.ex:149-154 and :2064-2074 fold every row without a cut. The walk's side is deliberate (performance.ex:894-896, ADR-0010:38).

  Severity: the repository ladder lists "a figure contradicted between two surfaces" under S2 (docs/development/sprint-workflow.md:116-118), and the reach is narrow and ends on the booked day. But two derivations answer 1,500 and 1,000 for today's value on the same rows, which is this audit's S1 definition, so S1 holds.

- Lens: reach (can the operator or the agent get there?). Refuted: no. Severity it would defend: S1.

  Not refuted on reach.

  No guard exists: the changeset's only date rule is BoundedDate (transaction.ex:335; 1900 to 2999, bounded_date.ex:28-29). The booking form's date is free text with an empty default (transaction_management_live.ex:75, :2908-2915). The PP importers refuse only dates past 2999 (csv_parser.ex:711-713). No ledger check names such a row (ledger_checks.ex:46-50).

  The reproduction wrote through POST /api/v1/transactions and read both GET routes: real callers, real arguments. The walk's own comment expects the state ("only future-dated ones", performance.ex:895-896).

  A default-configuration route exists as well: TZ ships empty, meaning UTC (.env.example:59, docs/home-deployment.md:224), so east of UTC a booking typed with the local date just after local midnight is dated ahead until UTC midnight.

  Both figures answer "value today" on one page: the header total (portfolio_live.ex:1729-1731) and the chart's last point, whose tooltip carries the walk's value in either mode (:4195-4203).

  No ADR, idea row or triage entry decides it.

  One narrowing of the evidence: the period's absolute result (:4562-4566) is not itself a contradicting figure for a deposit (zero under either rule); the visible contradiction is the chart's last value and the API pair.

  Severity: reach is narrow (a mistyped or value-dated booking, an agent booking ahead, the midnight window) and ends on the booked day, and the repository ladder lists "a figure contradicted between two surfaces" under S2 (sprint-workflow.md:117-119). But a holding and cash stated for today against the ledger's own dates is a figure that can be wrong (:113), so S1 holds.

**Audit lead's re-run.** The scratch test was run again by the audit lead on 2026-11-16 in a clean slot; it passed and printed the figures above.

### R-003 (O4-01), S1: The plan editor and the allocation engine sum one plan by two rules; for a plan with a blank top-level category over targeted children the editor reads "100% ✓" while Wealth, the Overview, the API and MCP read Σ 60 %, 40 % unallocated, and the engine divides every target by that 60 %, so a portfolio held exactly on plan is reported 40.0, 16.7 and 10.0 pp below target

- **Class:** duplicate computation (two paths, different figures)
- **Stands against:** `docs/decisions/0040-unallocated-remainder-in-target-plans.md:49-50`: "A plan carries an **unallocated remainder**: `100 % − Σ(top-level effective weights)`, surfaced as a named row rather than derived silently by each reader."; `lib/portfolixir/portfolios/allocation.ex:93-94`: "The Σ figures (`child_target_sum`, `top_level_target_sum`) consume the same effective values, so no surface disagrees with another."; the editor's own comment, `lib/portfolixir_web/live/classifications_live.ex:2376-2378`: "The running Σ counts only these, mirroring the allocation engine's `top_level_target_sum`"
- **Locations:** `lib/portfolixir_web/live/classifications_live.ex:2477-2492` (`put_sum/1`), `:2497-2499` (`remainder/1`), `:2501-2506`, `:2571-2583` (`effective_weight/3`), `:1548-1558` (the Σ row); `lib/portfolixir/portfolios/allocation.ex:456-459`, `:519-525`, `:599-602` (`top_level_target_sum/2`), `:611-634` (`deep_target_sum/2`), `:940-943` (`drift_base/1`), `:945-948`, `:967-970`; `lib/portfolixir_web/live/portfolio_live.ex:2581-2593`, `:5320-5325`; `lib/portfolixir_web/live/dashboard_live.ex:1167-1195`; `lib/portfolixir_web/controllers/api/v1/json.ex:1462`, `:1468`, `:1472`
- **Who meets it:** the operator, who reads "100% ✓" in the plan editor on Classifications and "Σ target top level: 60.0% — drift against the allocated portion" on Wealth → Allocation and "Core 40.0 pp below target · -400.00 EUR" on the Overview's "Off target" card; the agent on `GET /api/v1/portfolios/:id/allocation` and the MCP tool over it
- **Fix size:** M. **ADR amendment:** ADR-0040 (§1, §2), with a note on ADR-0030 §4
- **Also reported as:** A2-01 (same defect found by another lane, merged here)
- **On the later `main` (read, not run):** still stands. The plan editor's sum and the allocation engine's sum are untouched. The Wealth page, the Overview card and the API serialiser changed elsewhere; their cited lines only moved (Overview filter now 1204-1231, API fields 1468-1478).
- **Audit lead's note:** The two second readings were written against the first verification's run, whose files were lost (`architecture-review-triage-2026-11-24.md`, section 13). The run printed below has no plan C: plans A and B and the control were all written through `Targets.set_targets`, none through the editor form.
- **Audit lead's note:** The observed output below is an excerpt: it leaves out plan B's Core and Satellite rows and its Overview line, and the control's two untargeted rows. The audit lead's re-run printed them.

**What is wrong.**

1. The editor sums the top-level categories' effective weights, where a category's effective weight is its own weight when set, else the recursive sum of its children's (`lib/portfolixir_web/live/classifications_live.ex:2571-2583`); `put_sum/1` adds the cash target and derives `complete?` (✓ at exactly 100), `mismatch?` and `remainder` from that sum (`:2477-2492`, `:2497-2499`).
2. The engine sums only the roots that carry a target themselves, no roll-up: `top_level_target_sum/2` is `sum_targets(roots, targets)` (`lib/portfolixir/portfolios/allocation.ex:599-602`, `:638-645`), plus the cash target (`:519-525`).
3. From its sum the engine derives `unallocated_remainder` (`:945-948`) and `drift_base` (`:940-943`: the sum itself whenever it lies strictly between 0 and 1), and every category row's drift is `actual − target / drift_base` (`:967-970`, `drift_target/2` at `:952-953`).
4. The engine also holds the rolled-up figure, as a third number, `deep_target_sum` (`:611-634`); Wealth prints it only when the top-level sum is exactly 0 (`lib/portfolixir_web/live/portfolio_live.ex:5320-5325`, `:2584-2588`), and nothing uses it for the base.
5. So for "Core 60 %, Satellite blank, Satellite's children 25 % and 15 %" the editor answers 100 % ✓ with no "Not allocated" row; the engine answers 0.6 / 0.4 unallocated / `allocated_portion` and scales Core's target to 0.6 / 0.6 = 100 % and the children's to 41.67 % and 25 % (166.67 % in sum). The Overview's card lists a row when `target_weight > 0` and `|drift_weight| > 0.05` (`lib/portfolixir_web/live/dashboard_live.ex:1192-1195`), so all three targeted categories are listed for a portfolio that holds exactly 60 / 25 / 15.
6. Both rules are pinned by green tests: the roll-up by `test/portfolixir_web/live/classifications_live_test.exs:919` and `:1021` ("Σ mixes an explicit top-level weight with a rolled-up blank parent"), the roots-only sum by `test/portfolixir/portfolios/allocation_test.exs:1946`. The story above `classifications_live_test.exs:872` still says the editor's Σ counts "exactly like the portfolio page's allocation engine".

**Reproduction.**

Scratch test `test/audit_scratch/o4_01_plan_sum_test.exs` (removed after the run), run in a test slot.

_(scratch test source and run command: in the private evidence held by the owner)_

**Observed output.**

```
===== PLAN A (mixed) =====
EDITOR  soll-sum: "100% ✓"  remainder row: nil
ENGINE  top_level_target_sum=0.6 unallocated_remainder=0.4 deep_target_sum=1.00 drift_basis=allocated_portion
ENGINE  row Core       actual=0.6000 target=0.6 has_target=true drift_weight=-0.4000 drift_value=-400.00
ENGINE  row Satellite  actual=0.4000 target=0 has_target=false drift_weight=0.4000 drift_value=400.00
ENGINE  row Sat one    actual=0.2500 target=0.25 has_target=true drift_weight=-0.1667 drift_value=-166.67
ENGINE  row Sat two    actual=0.1500 target=0.15 has_target=true drift_weight=-0.1000 drift_value=-100.00
API     top_level_target_sum=0.6 unallocated_remainder=0.4 deep_target_sum=1 drift_basis=allocated_portion
WEALTH  Σ target top level: 60.0% — drift against the allocated portion
OVERVIEW Off target View Everything · plan “Plan” on Strategy · Categories drifting more than ±5 pp from their target weight. Core 40.0 pp below target · -400.00 EUR Sat one 16.7 pp below target · -166.67 EUR Sat two 10.0 pp below target · -100.00 EUR

===== CONTROL (flat 60/40) =====
EDITOR  soll-sum: "100% ✓"  remainder row: nil
ENGINE  top_level_target_sum=1.0 unallocated_remainder=0 deep_target_sum=1.0 drift_basis=full_plan
ENGINE  row Core       actual=0.6000 target=0.6 has_target=true drift_weight=0.0000 drift_value=0.00
ENGINE  row Satellite  actual=0.4000 target=0.4 has_target=true drift_weight=0.0000 drift_value=0.00
API     top_level_target_sum=1 unallocated_remainder=0 deep_target_sum=1 drift_basis=full_plan
WEALTH  Σ target top level: 100.0%
OVERVIEW Off target View Everything · plan “Plan” on Strategy · Categories drifting more than ±5 pp from their target weight. All targets within ±5 pp — nothing needs rebalancing.

===== PLAN B (children only) =====
EDITOR  soll-sum: "100% ✓"  remainder row: nil
ENGINE  top_level_target_sum=0 unallocated_remainder=1 deep_target_sum=1.0 drift_basis=full_plan
ENGINE  row Sat one    actual=0.2500 target=0.6 has_target=true drift_weight=-0.3500 drift_value=-350.00
ENGINE  row Sat two    actual=0.1500 target=0.4 has_target=true drift_weight=-0.2500 drift_value=-250.00
API     top_level_target_sum=0 unallocated_remainder=1 deep_target_sum=1 drift_basis=full_plan
WEALTH  Σ target top level: 0.0% — targets deeper in the tree: 100.0%

3 tests, 0 failures
```

The same holdings (600 / 250 / 150 of 1,000, no cash) under the flat control plan read zero drift; under plan A, which the editor marks complete with the same 60 % on Core, they read -400.00, -166.67 and -100.00 EUR. In plan B the drifts are plain `actual − target` (the holdings were not set to that plan); what differs there is Σ and the remainder only.

**Cost of leaving it.**

- Three definitions of one plan's sum: the editor's (about 115 lines, `classifications_live.ex:2470-2583`, recomputed in the web layer on every keystroke through `soll_sum`, `:1854-1856`), `top_level_target_sum/2` and `deep_target_sum/2`.
- Every reader of `Allocation.for_portfolio/3` carries the engine's figure: 7 call sites in `arch_calls.tsv`, among them `PortfolioLive.allocation_for/3` (Wealth's basis line and drift columns), `DashboardLive.alerts_for/4` (the Overview's card), `PolicyFindings.allocations/4`, `AllocationController.index/2` and `TargetController.position_drifts/3`, and the MCP tools over the last two.
- The figure read wrongly: the drift of every targeted category of a mixed plan (here 40.0, 16.7 and 10.0 pp, 666.67 EUR of drift in sum on a 1,000 EUR portfolio that is on plan), and the indicative rebalancing quantities that follow the drift (ADR-0023).
- ADR-0040 §4 promises the agent a remainder it "must not have to subtract"; the agent is handed "0.4" (plan A) or "1" (plan B) for plans the screen calls complete.

**Proposed fix.**

One pure function for a plan's sums in the Portfolios context (inputs: the categories, the effective targets, the cash target; outputs: the top-level sum, the rolled-up sum, the remainder, the children sums), called by `Allocation.build/5` and by the editor on load and on `soll_sum`; the context owns the rule. Which rule it is (a blank root rolls up everywhere, or nowhere) is the owner's decision, because it moves the drift base. Size M. Risk tier (ADR-0036: the drift base is a number the operator steers by). Needs an amendment of ADR-0040 (§1, what "top-level effective weights" means for a blank root; §2, the base of the drift) and a note on ADR-0030 §4, which introduced `deep_target_sum`.

**Second reading.**

- Lens: reach (can the operator or the agent get there?). Refuted: no. Severity it would defend: S1.

  Reach could not be refuted; each escape route is closed in the code.

  - **State is producible, and shipped.** The built-in asset-class tree has flat roots beside two group roots whose children are the only assignable codes (classifications.ex:57-79). Typing targets where the securities sit (ETF at the root, Knock-out under Leverage) is plan A on any instance.
  - **State is designed for.** The editor's own user story asks for an explicit root mixed with a blank parent rolled up from its child (classifications_live_test.exs:1003-1013).
  - **No guard.** `set_targets` checks batch size, classification, categories and positions, nothing about levels (targets.ex:434-447). The editor's save goes through the same function (classifications_live.ex:2039) and writes no row for the blank root. A blank parent gets no mismatch cue (classifications_live.ex:3048-3055).
  - **Real callers.** The reproduction's `Targets.set_targets` call is the API controller's call (target_controller.ex:343); plan C submitted the editor form.
  - **Same question.** The editor comment says its Σ mirrors `top_level_target_sum` (classifications_live.ex:2376-2379); Wealth prints that figure as "Σ target top level".
  - **Not a convention.** The root-only sum is documented (api-and-mcp.md:3576-3580), but dividing a child's target by a base that excludes it (allocation.ex:940-953, 967-970) follows from no ADR-0040 reading. The Overview alert states no basis (dashboard_live.ex:1167-1185).

  Reach is wider than the fixture: the cash target alone puts the top-level sum in (0,1) (allocation.ex:519-525), so a plan steered wholly below blank roots plus a cash target is divided by the cash weight.

  S1 holds: the wrong drift, not only the contradiction.

- Lens: decided (is it already decided or tracked?). Refuted: no. Severity it would defend: S1.

  Not refuted through the DECIDED lens. Checked ADR-0040, ADR-0030 (with slice 2a), ADR-0020, the 2026-08-15 triage (A2, D3), Sprint 7 and 18 plans, UX designs for Sprints 16 and 18, the 2026-09-23 backlog triage, ideas.md, the security lens, the API reference and the product documentation.

  What is decided: the engine's roots-only Σ for a plan with no root target ("stays honest", allocation_test.exs:1945; ADR-0030:163-165), and ADR-0040 §2's arithmetic (target renormalised, actual left alone, allocation.ex:926-935). Core's -40 pp alone is that decided arithmetic applied to a plan the engine reads as 60 %.

  What is not decided anywhere: that the editor may sum by another rule. The only record that touches it says the opposite: Sprint 18 H8.4, "One formula ... so the two agree" (ux-design-2026-10-02-sprint18.md:1526-1529), checked for the currency tree only. The editor's comments still claim parity (classifications_live.ex:2376-2379, 2494-2496). The product documentation describes the editor Σ as "sums the category weights plus the cash target" (product-documentation.md:1619-1620) with no roll-up, and the engine's Σ as roots plus cash (1745-1747). ADR-0040 never says what a blank root over targeted children is; ADR-0030 §1 defines "effective" as position sum or explicit row "or none", which the engine follows and the editor does not.

  Also undecided: children under a blank root are divided by a base that excludes them (0.25/0.6), so drift targets sum to 166.67 %. That is a derivation fault on its own, so S1 holds. No save-time guard exists (targets.ex, save_soll_plan).

**Audit lead's re-run.** The scratch test was run again by the audit lead on 2026-11-16 in a clean slot; it passed and printed the figures above.

### R-004 (D4-01), S1: In a view-bound snapshot comparison a trade's fee is a "transaction cost" by where its cash account is, not by whether it reduced the view's return: a fee that left the view inside a boundary outflow is taken out a second time, and a fee the view's return did bear is no cost at all

- **Class:** duplicate computation (three scope rules for one named figure, "#708's trade costs") with a wrong derivation in its one consumer
- **Stands against:** `docs/decisions/0027-plan-versions-and-depot-snapshots.md:191` "Real return before transaction costs | The **same daily walk** with window trade fees and taxes reclassified as **external** flows, so they neither reduce the return nor count as performance"; `docs/decisions/0019-view-scoped-performance-boundary-flows.md:50-51` "For a trade the quantity side is valued at the negated total cash movement" and `:57-58` "buying an out-of-view security with in-view cash is an **outflow** (money left the slice)"; `docs/decisions/0051-contribution-analysis.md:128-131` "**Costs.** The fees and taxes carried by the position's own trades. These are #708's trade costs" and `:530-531` "so the position's costs equal the walk's trade costs"; `lib/portfolixir/portfolios/snapshot_comparison.ex:407-409` "both chains read the same `daily` points, so the two can never disagree about anything except the one classification under test"
- **Locations:** `lib/portfolixir/portfolios/performance.ex:1103-1104`, `:1125-1142`, `:1227-1268`, `:1320-1333`, `:2062-2070`, `:2391-2394`, `:2406-2419`; `lib/portfolixir/portfolios/snapshot_comparison.ex:381-383`, `:410-441`, `:500-522`; `lib/portfolixir/portfolios/performance/contribution.ex:36-40`, `:66-70`; `lib/portfolixir/portfolios/costs.ex:109-113`; `lib/portfolixir_web/live/snapshots_live.ex:226-244`, `:435-460`
- **Who meets it:** the operator on `/snapshots` (the group "Real before transaction costs", "Transaction costs" and "Earned back?") for a snapshot bound to a view; the agent on `GET /api/v1/portfolios/:portfolio_id/snapshots/:id/comparison` and the MCP tool `portfolixir.snapshots.comparison`
- **Fix size:** M. **ADR amendment:** ADR-0027 (one sentence in ADR-0051 §1)
- **On the later `main` (read, not run):** still stands. Only the contribution module changed: two memo-key helpers became public, outside the cited lines. The walk's rule that counts a trade's fee by its cash account, and the snapshot comparison that subtracts it, are unchanged.
- **Audit lead's note:** Point 6 and the first cost bullet read as if the page showed run C's state. It does not: the page renders the cost group only when the transaction costs are not zero (`lib/portfolixir_web/live/snapshots_live.ex:226-229`), so run C's `not_recovered` reaches the API and MCP payload only, as the verifier's notes and the second reading (reach) say. On the page the two figures and "Earned back?" stand for runs A and B.

**What is wrong.**

1. In a scoped walk `trade_cost_in_scope?/2` counts a buy or sell when its cash account is in the view and reads nothing else: `not is_nil(tx.cash_account_id) and Buckets.cash_in_scope?(scope, tx.cash_account_id)` (`lib/portfolixir/portfolios/performance.ex:1132-1140`). The comment gives visibility as the reason: "only a trade whose CASH leg is in view moved money the view can see" (`:1103-1104`).
2. For a buy paid from an in-view cash account into an out-of-view position, the scoped `apply_transaction/3` keeps the cash leg and no quantity leg, so the booking straddles and the day's flow is the whole kept cash leg (`performance.ex:1231-1255`, `:1320-1333`). A buy's cash leg is its `gross_amount`, fees and taxes included (`lib/portfolixir/ledger/projection.ex:77-81`, `:361-362`).
3. The view's value falls by the same amount, so the day's factor `value / (prev + flow + basis)` is exactly 1 (`performance.ex:2062-2070`): the fee left the view inside the boundary outflow and reduced no return. Observed: `flow=-405`, `day_factor=1` (run B).
4. The same day's point still carries `trade_costs = fees + taxes` (`performance.ex:1058`, hop 1). Observed: `trade_costs=5`.
5. `SnapshotComparison.real_side/4` walks the snapshot's view (`lib/portfolixir/portfolios/snapshot_comparison.ex:381-383`) and chains the pre-cost factor as `day_factor(point, prev - cost)` (`:435-441`). With the fee already inside `flow` it is subtracted again: the factor is above 1 on a day nothing was earned. `transaction_costs` sums the same points (`:415-420`), and `cost_recovery/3` reads both (`:500-522`). Observed (run A): net return 0, return before costs +0.502513 %, costs 5, although the view's value and flow show no cost. Observed (run B): a view that lags its frozen holdings through idle cash alone (net +0.667 % against frozen +1 %) reads `partly_recovered`, "ahead before costs" (+1.124 %), where the pre-cost return without the double count equals the net one and the state is `not_recovered`.
6. The mirror case is wrong the other way. For a buy of an in-view position paid from an out-of-view cash account the units come in at "the cash they cost, fees included" (`performance.ex:1323-1333`; `lib/portfolixir/portfolios/performance/contribution.ex:67-69`), so the day's factor is `1200 / 1205`, below 1 by the fee; hop 1 answers false, `trade_costs` is 0, and the comparison states no cost for a fee the view's return did bear. Observed (run C): net −0.414938 %, before costs −0.414938 %, costs 0, state `not_recovered` ("Behind even before costs" on the page, `snapshots_live.ex:243-244`) for a top-up whose only gap to the frozen side is the fee: the answer `snapshot_comparison.ex:506-513` calls "false, and false in the direction that discourages a correct decision".
7. The contribution keeps a cost only for a trade wholly inside the scope (`performance.ex:2391-2394` sends every straddle to `add_flows` alone; `contribution.ex:38-39` "counted when the whole trade is inside the scope"). For hop 2's trade the walk's `trade_costs` of the day is 5 and the sum of the contribution's `costs` is 0 (run A), although ADR-0051 calls them one figure. The benchmark's `costs_paid` follows the cash account by decision (ADR-0046, amended 2026-11-04, point 3; `lib/portfolixir/portfolios/costs.ex:109-113`) and subtracts nothing, so it is not part of the defect; it is the third scope rule.
8. Read whole, without a view, the same bookings are right: net −0.414938 %, before costs 0, costs 5 (run A, second line).

**Reproduction.**

Scratch test `test/audit_scratch/d401_test.exs` (removed after the run), three worlds: A the reader's (in-view cash account, buy into a second depot outside the view), B the same shape with idle cash so that the recovery state flips, C the mirror (depot in the view, its cash account outside).

_(scratch test source and run command: in the private evidence held by the owner)_

**Observed output.**

```
C view walk 2026-03-14 value=1000 | 2026-03-15 value=1200 flow=205 trade_costs=0 day_factor=0.99585062
C contribution (view) costs per position=["0"] result=-5
C snapshot comparison (view): real_ttwror=-0.00414938 before_costs=-0.00414938 transaction_costs=0 snapshot_return=0 recovery=not_recovered outstanding=0.00414938
.B view walk 2026-03-24 value=1510 | 2026-03-25 value=1105 flow=-405 trade_costs=5 day_factor=1
B snapshot comparison (view): real_ttwror=0.00666667 before_costs=0.01124242 transaction_costs=5 snapshot_return=0.01 recovery=partly_recovered outstanding=0.00333333
.A view walk 2026-03-14 value=1000 | 2026-03-15 value=1000 flow=0 trade_costs=5 day_factor=1
A contribution (view) costs per position=["0"] result=0
A snapshot comparison (view): real_ttwror=0 before_costs=0.00502513 transaction_costs=5 snapshot_return=0 recovery=recovered outstanding=0
A snapshot comparison (whole portfolio): real_ttwror=-0.00414938 before_costs=0 transaction_costs=5 snapshot_return=0 recovery=partly_recovered outstanding=0.00414938
.
Finished in 0.5 seconds (0.00s async, 0.5s sync)
3 tests, 0 failures
```

Counts re-run on the checkout:
- `grep -rn "trade_costs" lib --include='*.ex' | grep -v "lib/portfolixir/portfolios/performance.ex"` printed 4 lines: three comment lines in `lib/portfolixir/derived/registry.ex` (29, 47, 49) and `lib/portfolixir/portfolios/snapshot_comparison.ex:415`, the one consumer.
- `grep -c -i "view\|bucket" test/portfolixir/portfolios/trade_costs_test.exs test/portfolixir/portfolios/snapshot_transaction_costs_test.exs` printed 0 and 0: neither test file of the figure uses a view.

**Cost of leaving it.**

- Three figures of one payload read wrongly: `real_ttwror_before_costs` (run A: +0.50 % where 0 is right), `transaction_costs` (5.00 where the view bore none; 0 where it bore 5.00) and `cost_recovery.state` (run B: `partly_recovered` for `not_recovered`; run C: `not_recovered` where the fee is the whole gap). The page prints the first two with "Earned back?" beside them.
- One 4-line function decides (`performance.ex:1132-1140`); `trade_costs` has one consumer (`snapshot_comparison.ex:415`); three scope rules exist for one named figure (cash account in view: the walk and `Costs.paid/4`; whole trade in scope: the contribution; nothing for the units' side).
- A straddle is ordinary for a tag-based view: depot defaults, cash-account buckets and per-position overrides are set independently (`lib/portfolixir/buckets.ex:1060-1078`), a buy must use its depot's linked cash account (`lib/portfolixir/ledger.ex:2296-2303`), and a view of positions whose cash account carries no tag makes every buy and sell of the view a straddle (run C). The portfolio's own seeded scope view (ADR-0024) tags depots and accounts together and is not affected.
- No test of the figure uses a view (0 and 0 above), and `test/portfolixir/portfolios/performance/contribution_test.exs:1240-1242` pins only "a trade whose cash account is out of view is still not counted" for a trade wholly outside.

**Proposed fix.**

Decide the scope rule of the trade-cost figure in an amendment of ADR-0027 (its 2026-08-15 amendment defines the figure and says nothing about views), with one sentence in ADR-0051 §1 naming which rule "the walk's trade costs" means. The runs show which rule makes the derivation true: a trade's fee reduces a view's return exactly when the trade's unit leg is kept (runs A and B: units outside, factor 1; run C: units inside, factor below 1 by the fee), so `trade_cost_in_scope?/2` should read the kept quantity leg (`Buckets.position_in_scope?/3`), not the cash account. The narrower alternative, the contribution's rule (count only a trade wholly in scope), repairs runs A and B and leaves run C's fee stated in the basis as inside the boundary flow. The walk (`Performance.trade_cost_in_scope?/2`) should own the rule, and the contribution keeps reading it. `trade_costs` on stored points changes, so the computation versions of the two performance analytics move (ADR-0039 §5). Pins: the three scratch worlds above as red tests. `Costs.paid/4` keeps its cash-account rule (ADR-0046, decided). Size M (S for the code; the amendment, the red tests, the basis text and the version move make it a day). Risk tier (money, ADR-0036). Needs the ADR-0027 amendment.

**Second reading.**

- Lens: decided (is it already decided or tracked?). Refuted: no. Severity it would defend: S1.

  Not refuted through the DECIDED lens. Read at e014f284, nothing run.

  Records searched: ADR-0019, ADR-0027 with its 2026-08-15 amendment and 2026-10-06 note, ADR-0046, ADR-0051, ideas.md, the three security triages, the security lens (N-ids), Sprint 7 plan and retrospective, feedback triage 2026-08-15, the API reference (api-and-mcp.md:3417-3442), product documentation and the #708 commit message (2f637bb2).

  What is recorded: the cash-account rule for which costs count in a view. ADR-0046 point 3 even gives run C's case as its example, but for costs_paid alone, and point 4 says that figure is not subtracted. performance.ex:1103-1104 and contribution_test.exs:1240-1242 state the same rule for the walk's trade costs; the test's out-of-view trade is wholly outside, not a straddle. So run C's transaction_costs = 0 follows a recorded rule; its not_recovered state does not.

  What is not recorded anywhere: that the pre-cost chain subtracts a fee already inside a boundary outflow. ADR-0027's amendment never mentions a view. Its line 191 says the reclassified fees must not "count as performance"; in run A they do (+0.50 % on a day with factor 1). snapshot_comparison.ex:435-441 assumes the value fell by the fee as a loss, which is false for a straddle (performance.ex:1231-1255 books the whole cash leg as flow). The Contribution moduledoc (contribution.ex:66-70) records the opposite reading: such a trade "is kept nowhere".

  Severity stays S1: a derivation is wrong and cost_recovery.state flips (run B). The mirror half alone would be S2.

- Lens: reach (can the operator or the agent get there?). Refuted: no. Severity it would defend: S1.

  Not refuted through reach.

  No guard on the path: `Snapshot.changeset` casts `view_id` freely (snapshot.ex:38), the create form offers every view (snapshots_live.ex:625), `for_snapshot/3` loads the scope and walks it without a straddle check (snapshot_comparison.ex:58-83), and `trade_cost_in_scope?/2` reads the cash account alone (performance.ex:1132-1140).

  The straddle is no fixture artifact. ADR-0018's own example view, `Strategie = exclude {Krypto, Family}` (0018:67), with a per-position override from the Securities page (securities_live.ex:7041), keeps the depot's untagged cash account in view and the excluded position out. Every buy or sell of that position is run A's shape. A sell carries its withheld tax in `taxes`, so the error is cost over base, not a rounding. The fixture's own shape, a second depot on an existing cash account, is offered by the account dialog (account_form_dialog.ex:400-405).

  The reproduction called the public `for_snapshot/3` as the controller does; `today:` only fixes the date.

  No record decides the rule: ADR-0027's amendment is silent on views, ideas.md and the triages hold no row, and contribution_test.exs:1278-1300 pins the cash rule only for trades wholly inside or outside the view.

  Limits of reach: the "Everything" scope, the seeded portfolio views and pair-tagged depots (portfolio_accounts_live.ex:1412 writes depot and cash together) are unaffected. Run C's false `not_recovered` reaches only the API and MCP payload, because the page hides the cost group at zero costs (snapshots_live.ex:226).

  S1 holds by the ladder's wording, "a figure ... or derivation can be wrong" (sprint-workflow.md:113).

**Audit lead's re-run.** The scratch test was run again by the audit lead on 2026-11-16 in a clean slot; it passed and printed the figures above.

### R-005 (A4-01), S1: The depot-merge preview folds a position's cost from the two depots' bookings only, so shares that reached either depot by a transfer from a third depot are stated at zero cost, before and after, while the holdings read states what was paid

- **Class:** duplicate computation (one fold, two row sets); seam crossed (a caller builds the input of a Ledger fold)
- **Stands against:** ADR-0050 §16 invariant 12, `docs/decisions/0050-lifecycle-merges-under-a-reimport-contract.md:699`: "The preview's after-figures equal the API reads right after the apply."; the payload's own basis, `lib/portfolixir_web/controllers/api/v1/merge_json.ex:54-56`: "cost_basis and avg_cost: the moving-average cost GET /api/v1/portfolios/:id/holdings states"; and the contract in `lib/portfolixir/ledger.ex:661-667` ("A position's figures depend only on its own bookings and its portfolio's split rows of the security"), which is false for a `security_transfer`
- **Locations:** lib/portfolixir/lifecycle/depot_merge.ex:406-416, lib/portfolixir/lifecycle/depot_merge.ex:483, lib/portfolixir/lifecycle/depot_merge.ex:622, lib/portfolixir/lifecycle/depot_merge.ex:710-728, lib/portfolixir/ledger.ex:661-667, lib/portfolixir/ledger.ex:796-799, lib/portfolixir/ledger.ex:951-997, lib/portfolixir/ledger.ex:370-377, lib/portfolixir/ledger.ex:415-423, lib/portfolixir_web/controllers/api/v1/merge_json.ex:52-56
- **Who meets it:** the operator in the depot merge dialog on Accounts & depots (`lib/portfolixir_web/live/portfolio_accounts/merge_preview.ex:365-395`); the agent on `GET /api/v1/securities_accounts/:id/merge_preview` and the MCP tool `portfolixir.securities_accounts.merge_preview`
- **Fix size:** S to M. **ADR amendment:** none
- **On the later `main` (read, not run):** still stands. The depot-merge module and the Ledger cost fold are unchanged. Only the merge payload file changed: f55c644f adds a list of dropped halvings to the security merge; the cost-basis text at lines 52-56 is intact.
- **Audit lead's note:** The two second readings were written against the first verification's run, whose files were lost (`architecture-review-triage-2026-11-24.md`, section 13). The figure they cite, the source's cost of 0 against 300 over the API, is also in the run printed below (test B).

**What is wrong.**

1. `DepotMerge.load/3` reads the bookings that name the source or the target depot through either depot leg, and the portfolio's split rows of their securities; nothing else (`lib/portfolixir/lifecycle/depot_merge.ex:406-428`).
2. The plan hands exactly those rows to the cost fold for the before-figures (`lib/portfolixir/lifecycle/depot_merge.ex:483`), the outcome hands the relabelled rows to it for the after-figures (`lib/portfolixir/lifecycle/depot_merge.ex:622`), and `positions/2` shows what comes back (`lib/portfolixir/lifecycle/depot_merge.ex:710-728`).
3. A `security_transfer` from a third depot X into the source S is in that set (S is its counter leg). X's buys are not: they name X only.
4. The fold moves a transfer's cost out of the sending depot's lot and into the receiving one (`lib/portfolixir/ledger.ex:796-799`). With X's buys missing, X's lot is `empty_lot()` (`lib/portfolixir/ledger.ex:990-997`: quantity 0, cost 0, `cost_known: true`), so `remove_cost/3` answers a moved cost of 0, marked known (`lib/portfolixir/ledger.ex:951-985`).
5. S's lot gains the quantity at cost 0. The preview states `cost_basis` 0 and `avg_cost` 0 (a figure, not `null`), and a later sale from that position reads its whole proceeds as `realized_result` (`lib/portfolixir/ledger.ex:704-715`). The after-figure on the target inherits the missing cost.
6. The other path: `Ledger.holdings_for_portfolio/2` folds every booking of the portfolio (`lib/portfolixir/ledger.ex:370-377`, `:415-423`), so X's buys are in its input and the transfer carries X's cost. The two paths disagree before the merge and after it.
7. The apply recomputes the plan from the same short row set and compares digests (`lib/portfolixir/lifecycle/depot_merge.ex:246-259`), so the digest matches and nothing notices. The merge itself moves the right rows: the stored ledger and the holdings read afterwards are right.
8. Control: the same shares bought on the source itself read the same in both paths (test C below), so the difference is the row set, not the fold.

**Reproduction.**

Scratch test `test/audit_scratch/a4_01_test.exs` in the slot checkout (removed afterwards).

_(scratch test source and run command: in the private evidence held by the owner)_

**Observed output.**

```
Portfolixir.AuditScratch.A401Test [test/audit_scratch/a4_01_test.exs]
  * test A: the reader's scenario, context level [L#41]A guards all passed: true
A before: holdings read (source depot) = quantity=4 cost_basis=400 avg_cost=100
A before: preview.source              = quantity=4 cost_basis=0 avg_cost=0
A preview.target                      = nil
A preview.after                       = quantity=4 cost_basis=0 avg_cost=0
A after:  holdings read (target depot) = quantity=4 cost_basis=400 avg_cost=100
A equal before? false  equal after? false
  * test B: over the API, with a later sale and an own lot on the target [L#71]B GET holdings, source depot before : quantity=3 cost_basis="300" avg_cost="100"
B GET merge_preview .source         : quantity=3 cost_basis="0" avg_cost="0" realized_result="150"
B GET holdings, target depot before : quantity=6 cost_basis="660" avg_cost="110"
B GET merge_preview .target         : quantity=6 cost_basis="660" avg_cost="110" realized_result="0"
B GET merge_preview .after          : quantity=9 cost_basis="594" avg_cost="66" realized_result="84"
B GET holdings, target depot after  : quantity=9 cost_basis="954" avg_cost="106"
B GET holdings, third depot after   : quantity=6 cost_basis="600" avg_cost="100"
  * test C: control, the same shares bought on the source itself [L#110]C before: holdings read = quantity=4 cost_basis=400 avg_cost=100  preview.source = quantity=4 cost_basis=400 avg_cost=100

3 tests, 0 failures
```
(The tests print and assert nothing about the figures; "0 failures" means they ran to the end, the merge included.)

Reading of B: the third depot bought 10 at 100.00 and transferred 4 to the source; the target bought 6 at 110.00; the source sold 1 at 150.00. The holdings read states the source at 3 for 300 and, after the merge, the target at 9 for 954 (average 106). The preview states the source at 3 for 0 with a realized result of 150 (by arithmetic on the holdings read's average, 150 - 100 = 50), and promises the target 9 for 594 (average 66) with a realized result of 84 (by the same arithmetic on the pooled average, 150 - 106 = 44). The promised cost basis is 360 short: the 400 the four transferred shares cost, less the tenth the sale removed.

**Cost of leaving it.**

- 2 call sites in one module (`depot_merge.ex:483`, `:622`), 3 surfaces (dialog, API route, MCP tool), 3 figures per affected position and side (`cost_basis`, `avg_cost`, `realized_result`).
- It shows on every depot-merge preview in which either depot holds a security that arrived by a transfer from a depot outside the pair. The operator and the agent are asked to confirm an irreversible merge against a cost restatement the app will not read afterwards; in the run the promised average cost is 66 where the holdings read 106.
- The other two folds of the preview are not affected: quantities come from `Positions` over the same rows and are right (a transfer adds quantity to its counter depot without the sender's rows); the security merge loads every booking of both securities (`lib/portfolixir/lifecycle/security_merge.ex:664-668`).
- No test covers it: the two third-depot tests of `test/portfolixir/lifecycle/depot_merge_test.exs:240-303` assert quantities, and the invariant-12 test on the wire (`test/portfolixir_web/controllers/api/v1/depot_merge_controller_test.exs:200-243`) uses a world without a third depot.

**Proposed fix.**

The Ledger owns the rule and its input: one function that, given the portfolio and the affected securities, folds every booking of those securities in the portfolio (a transfer's counter depot is in the same portfolio by foreign key) and answers the per-depot figures; the depot merge calls it for the before-figures and, with the source's rows relabelled, for the after-figures. No caller can then pass a short set. The plan digest reads the wider row set too, and the apply reads it under its locks. Correct the `@doc` at `lib/portfolixir/ledger.ex:661-667`. Test first: test B above as an assertion over the API beside `depot_merge_controller_test.exs:200`, and A in `depot_merge_test.exs`. Size S to M; risk tier (a money figure, ADR-0036). No ADR amendment is needed for the fix (ADR-0050 §7 and invariant 12 already ask for it); a sentence in ADR-0050 §10 that the digest covers the third depots' rows the cost fold reads would record the wider read.

**Second reading.**

- Lens: reach (can the operator or the agent get there?). Refuted: no. Severity it would defend: S1.

  Through the reach lens I found no ground to refute.

  Booking: a `security_transfer` between depots of one portfolio is produced by the importer (lib/portfolixir/imports/portfolio_performance/csv_parser.ex:79 "Umbuchung (Wertpapier)", json_parser.ex:71; written at lib/portfolixir/imports/applier.ex:2751-2757 in exactly the shape the reproduction seeds) and by the agent (mcp-server/src/tools.ts:4123 lists the kind for portfolixir.transactions.create). The repository's own user stories name the state: "the operator whose merged-away depot exchanged shares with a third depot" (test/portfolixir/lifecycle/depot_merge_test.exs:228-240, 256-268).

  Guard: the five guards (depot_merge.ex:301-323, 355-366) look at identity, liveness, portfolio and buckets; none looks at a third depot. The dialog and the controller call `Lifecycle.preview_depot_merge/2` directly (merge_dialog.ex:366, merge_controller.ex:139).

  Same question: the payload's basis sentence names the holdings read for cost_basis and avg_cost (merge_json.ex:54-56). Not a convention: ADR-0050's "cost basis is legitimately restated, because lots combine" (docs/decisions/0050-...md:363-365) covers the after-figure of S plus T, not the source's before-figure (0 against 300, nothing combined yet), and invariant 12 (:699) fails on the wire.

  Reproduction: over the real routes (GET merge_preview, POST merge, GET holdings); no internal call with unreal arguments. Code agrees: load reads only rows naming S or T (depot_merge.ex:409-416), so X's lot is empty and the transfer moves cost 0, known (ledger.ex:796-799, 951-960, 990-997).

  Narrowing only: positions list source-held securities (depot_merge.ex:714), merges are rare, nothing stored is wrong. That limits frequency, not the tier: a served money figure is wrong against its stated basis. No idea row, triage or N-finding tracks it (N-29 and F29 are other matters).

- Lens: decided (is it already decided or tracked?). Refuted: no. Severity it would defend: S1.

  Not refuted through the DECIDED lens: every record I found asks for the opposite of the observed behaviour, and none tracks it.

  Checked:
  - ADR-0050 §7 (:363-365): the only declared restatement is "cost basis is legitimately restated, because lots combine" (S and T lots). It cannot cover the source's before-figure (0 against 300), where nothing has combined. §10 (:483-495) scopes the digest, not the cost input. §16 invariant 12 (:699) requires after-figures to equal the API reads. The four amendments (2026-10-07, -08, -09, 2026-11-01) do not touch the cost figures.
  - Served basis and API reference name the holdings read as the basis (lib/portfolixir_web/controllers/api/v1/merge_json.ex:52-57; docs/integration/api-and-mcp.md:2076-2082). The Ledger @doc (lib/portfolixir/ledger.ex:661-667) and commit b3f4a537 promise the same; no doc states a two-depot limit as intended.
  - ideas.md F29 (:127; #957 flow effects, #1070 bond fields): different matter.
  - Security triage 2026-10-12 K11 (:305): FIFO restatement on a security merge; it extended the after-figure test, which reinforces invariant 12.
  - Security lens N-29, N-52, N-53, N-54 (`security-review-triage-2026-11-11.md`, Lane M): dropped transfer's fees and taxes, ticker, feeds, stray counter leg; none is the cost fold's input.
  - Sprint 16 plan L3 (:214) and sprint-status: no accepted limit. An issue search (cost, position_costs, third depot) found only #957 and #1285, both closed and unrelated.

  Code confirms the mechanism (depot_merge.ex:409-416, :483, :622; ledger.ex:796-799, :951-960, :990-997).

  Severity: S1 holds by the audit's definition (two reads, different figures, same data). Limits: preview only, nothing stored wrong.

**Audit lead's re-run.** The scratch test was run again by the audit lead on 2026-11-16 in a clean slot; it passed and printed the figures above.

### R-006 (G4-02), S1: The cash merge preview states the position change of a collapsed trade as the booking's own units, without the portfolio's splits; after a 2:1 split the depot loses 6 where the preview, the API and the dialog say -3

- **Class:** duplicate computation (a rule one twin lacks)
- **Stands against:** the story's acceptance criterion, `test/portfolixir/lifecycle/cash_merge_test.exs:354-358`: "The collapse outcome lists the depot and security of each collapsed trade with its quantity change ... After the apply with collapse, the depot holds exactly that much less"; ADR-0050 §16 invariant 12, `docs/decisions/0050-lifecycle-merges-under-a-reimport-contract.md:699`: "The preview's after-figures equal the API reads right after the apply"; the code's own comment, `lib/portfolixir/lifecycle/cash_merge.ex:802`: "A collapsed trade removes its quantity from its depot's position"; the depot twin's rule, `lib/portfolixir/lifecycle/depot_merge.ex:630-634`: "its quantity at the end, before and after the collapse, from the ledger's own fold over the depot's rows and the portfolio's splits of the security"
- **Locations:** `lib/portfolixir/lifecycle/cash_merge.ex:803-818` (the figure), `:474-496` (the load reads no split row), `:644` (its place in the outcome); `lib/portfolixir_web/controllers/api/v1/merge_json.ex:783-790`; `lib/portfolixir_web/live/portfolio_accounts/merge_preview.ex:575-585`, `:533-534`
- **Who meets it:** the operator on Accounts & depots, step 2 of "Merge into…" for a cash account, in the line under "remove as duplicates" ("Also changes: … -3 shares"); the agent on `GET /api/v1/cash_accounts/:id/merge_preview` (`outcome_by_collapse_key_equal.true.positions[].quantity_change`) and `portfolixir.cash_accounts.merge_preview`
- **Fix size:** S. **ADR amendment:** none
- **On the later `main` (read, not run):** still stands. Cash merge module, depot merge module and dialog are unchanged. The API serialiser gained 11 lines for dropped halving events of the security merge; the cash positions serialiser that passes quantity_change on is untouched.

**What is wrong.**

1. A cash merge pairs a source row with a target row of equal #533 key; only balance anchors and splits are excluded (`cash_merge.ex:576`), so a pair can be a buy or a sell: two buys in one depot, one settled on each cash account (the rename zombie of ADR-0050 §8).
2. For the collapse outcome, `positions/1` sums the negated quantity legs of the collapsed rows per depot and security and calls the sum `quantity_change` (`cash_merge.ex:803-818`, used at `:644`).
3. `load/3` reads the bookings that name either cash account and the source's linked depots (`cash_merge.ex:477-488`). A split names no account, so no split row is in the plan, and nothing in the module reads one.
4. A split dated after the collapsed trade scales that trade's units in every position read (`Ledger.positions_for_portfolio/1`). Removing a buy of 3 before a 2:1 split removes 6 from the position; before a 1:10 reverse split it removes 0.3.
5. The serialiser passes the raw figure on (`merge_json.ex:783-790`), the dialog prints it as "%{security} in %{depot} %{change} shares" under "Also changes:" (`merge_preview.ex:575-585`, `:533-534`). The plan digest covers the figure and the apply recomputes it the same way, so nothing notices.
6. The other path: the depot merge states a collapsed trade's position through the ledger's fold with the portfolio's splits (`depot_merge.ex:611-622`, `:681-687`). For the same shape (a buy of 3 in each depot, a 2:1 split, collapse) it states 6 and 6 before and 6 after, and the read after the apply is 6.

**Reproduction.**

Three scratch tests, synthetic data, removed after the run; modelled on `test/portfolixir/lifecycle/cash_merge_test.exs` ("a collapsed trade names the position it changes") and `test/portfolixir_web/live/accounts_merge_live_test.exs`.

`test/audit_scratch/g4_02_test.exs` (the figure in the context and on the wire, for a 2:1 split, a 1:10 reverse split and no split):

_(scratch test source and run command: in the private evidence held by the owner)_

`test/audit_scratch/g4_02_live_test.exs` (the dialog's sentence, and the depot twin for the same shape):

_(scratch test source and run command: in the private evidence held by the owner)_

**Observed output.**

```
G4-02 [2:1 split] held before=12 held after=6 actual change=-6 preview quantity_change=-3 agree=false
G4-02 [2:1 split] API positions (outcome true): [
  %{
    "quantity_change" => "-3",
    "securities_account_id" => 121,
    "security_id" => 496
  }
]
G4-02 [1:10 reverse split] held before=0.6 held after=0.3 actual change=-0.3 preview quantity_change=-3 agree=false
G4-02 [1:10 reverse split] API positions (outcome true): [
  %{
    "quantity_change" => "-3",
    "securities_account_id" => 123,
    "security_id" => 498
  }
]
G4-02 [no split] held before=6 held after=3 actual change=-3 preview quantity_change=-3 agree=true
G4-02 [no split] API positions (outcome true): [
  %{
    "quantity_change" => "-3",
    "securities_account_id" => 125,
    "security_id" => 500
  }
]
G4-02 dialog, the remove-duplicates option says: ["Also changes: Synthetic Collapse ETF in Depot 1 -3 shares"]
G4-02 position read before the merge=12 after=6
G4-02 depot twin, collapse=true: source before=6 target before=6 target after=6
G4-02 depot twin, position read after the apply=6
10 tests, 0 failures
```

(The ten tests are this lane's five scratch files run together; the tests print and do not assert the defect.)

**Cost of leaving it.**

1 function of 16 lines, 3 surfaces (the dialog, the API read, the MCP tool). The operator confirms an irreversible merge from a line that says "-3 shares" while the holding falls by 6, off by the product of the split ratios booked after the trade. It shows on every cash merge that collapses a buy or sell (the rename zombie and the double import, the shapes ADR-0050 §8 names as the reason for the choice) of a security with a later split in that portfolio. Nothing stored is wrong: the merge deletes the right row, the position read afterwards is right, and the merge record's manifest does not carry the figure (`cash_merge.ex:1165-1219`). No test of the cash merge books a split (`grep -n "split" test/portfolixir/lifecycle/cash_merge_test.exs` prints nothing), so the story's criterion "the depot holds exactly that much less" is pinned only without one.

**Proposed fix.**

The cash merge's position line is computed as the depot merge computes a third depot's: the ledger's fold over the depot's rows and the portfolio's splits of the security, before and after the collapse; one function in `MergeFigures`, called by both (R-110 (G4-01)'s first step). The payload carries `quantity_before` and `quantity_after`, with `quantity_change` kept as their difference so no reader breaks; one manifest entry in the API contract; the dialog prints the difference it already prints. Test first: the scratch test with an assertion that the held quantity changes by exactly the preview's `quantity_change`, red today for both splits, and the same over the API. Size S; risk-tier (ADR-0036). No ADR amendment: ADR-0050 §16 invariant 12 and the story's criterion already ask for it. The rule belongs to the ledger's fold (`Ledger.Positions`), reached through `MergeFigures`.

**Second reading.**

- Lens: decided (is it already decided or tracked?). Refuted: no. Severity it would defend: S1.

  Not refuted through the DECIDED lens: no record decides or tracks it.

  Checked: ADR-0050 with all five amendments (2026-10-07 to 2026-11-01); ADR-0028; ideas.md I1 to I42 and the F rows; the three security triages; the audit's security lens N-01 to N-93; Sprint 15/16/22/23 plans, retrospectives, the Sprint 22 severity pass; DESIGN.md and board 13; the module doc, API reference and MCP text; the open polish lists (#1361, #1363, #1356) and an issue search.

  Nearest records, none covering it: F29/#957 (flow effects, depot and security previews only), N-29 (a dropped transfer's fees), N-51 to N-54, K11 (FIFO restatement in the security preview).

  The only text that reads like a decision is the story's criterion "a buy's quantity, negated" (test/portfolixir/lifecycle/cash_merge_test.exs:354-356). The same story's next line requires "the depot holds exactly that much less", and no cash-merge test books a split, so it describes the no-split case rather than choosing booked units. The records point the other way: ADR-0050 §10 (:489) says the preview states "the balances or positions after either collapse value"; board 13 note 2 and the API reference (docs/integration/api-and-mcp.md:1925-1926) call the line what the collapse changes in a position.

  Code confirms the claim: cash_merge.ex:576 excludes only anchors and splits from pairing; :477-488 loads no split row; :803-818 sums raw legs.

  Severity holds by recorded precedent: the adopted Sprint 22 severity pass rates display-only wrong figures S1 (#1316, #1331, #1274) and an omitted preview effect S2 (#957). This is a stated wrong figure on an irreversible confirm.

- Lens: reach (can the operator or the agent get there?). Refuted: no. Severity it would defend: S1.

  Not refuted; every reach escape fails on the code.

  Fixture: the scratch buy (import_changeset, Multi.insert, journal under import_session) is the importer's own write (applier.ex:3050-3069). The importer takes a trade's cash account from the file row's account name, not the depot's link (applier.ex:2447, :2696-2702); test/portfolixir/lifecycle/depot_merge_test.exs:1504-1507 records that shape for a rename zombie. The one limiter, "must match the selected depot" (ledger.ex:2299), runs on create only (sole call site :1624); the importer and an edit moving a booking to another cash account (:1703) skip it.

  Guards: the cash merge's guards name no split, pairable?/1 excludes only anchors and splits (cash_merge.ex:576), and the importer has no check for a trade dated before a booked split. The reproduction used the public preview, the serialiser, the LiveView and the apply.

  Same question: the dialog's comment says "a position's quantity" (merge_preview.ex:567), the MCP description "positions a collapsed booking changes" (mcp-server/src/tools.ts:3970), the story "the depot holds exactly that much less" (cash_merge_test.exs:357-358). No ADR, idea row, triage row or issue states booked units or tracks this. The gap is the split factor, not rounding.

  Reach is narrower than the evidence's cost line: both copies must carry pre-split units and the split must come from Portfolixir's own flow (ADR-0028: PP's wizard rewrites quantities, so no pair forms), and since ADR-0050 §4 a rename alone creates no zombie. That lowers frequency, not the ladder's "can be wrong". N-29 (S2, same preview) was an unstated effect; here a stated figure is wrong, so S1 holds.

**Audit lead's re-run.** The scratch test was run again by the audit lead on 2026-11-16 in a clean slot; it passed and printed the figures above.

### R-007 (V1-01), S1: The memoised policy findings are keyed under their own portfolio's basis, while the valuation they are read off prices an unquoted security at the latest trade in any portfolio; a trade elsewhere, or a rate write in that trade's currency, leaves a finding served that its rebuild contradicts

- **Class:** derived-layer invalidation gap (the basis misses an input the value reads; ADR drift)
- **Stands against:** `docs/decisions/0049-policy-rules-as-first-class-objects.md:216-220` ("keyed under `DataVersion.portfolio_basis/1` **and** a rules counter that every rule write bumps. A finding that outlived an edited cap would be a stale answer to the only question the read exists for."); `docs/decisions/0039-durable-derived-values.md:154` (I1: "`derived == rebuild_from_scratch(transactions)` for any ledger state"); `lib/portfolixir/portfolios/policy_findings.ex:40-43` ("keyed under `Derived.portfolio_basis/1` — every write that moves a measure bumps it")
- **Locations:** lib/portfolixir/portfolios/policy_findings.ex:89-95, lib/portfolixir/portfolios/policy_findings.ex:113-116, lib/portfolixir/portfolios/policy_findings.ex:175-182, lib/portfolixir/portfolios/pricing_context.ex:143, lib/portfolixir/ledger.ex:2212-2222, lib/portfolixir/portfolios/valuation.ex:14-21, lib/portfolixir/portfolios/valuation.ex:365-372, lib/portfolixir/portfolios/valuation.ex:710-715, lib/portfolixir/derived/blast_radius.ex:65, lib/portfolixir/derived/blast_radius.ex:238-240, lib/portfolixir/derived/blast_radius.ex:216-220, lib/portfolixir/derived/invalidation.ex:46-60, lib/portfolixir_web/live/risk_live.ex:71, lib/portfolixir_web/live/risk_live.ex:88, lib/portfolixir_web/live/risk_live.ex:197, lib/portfolixir_web/controllers/api/v1/policy_finding_controller.ex:67-75
- **Who meets it:** the operator on `/risk` (the rules' findings beside the concentration lens, which is not memoised); the agent on `GET /api/v1/portfolios/:portfolio_id/policy_findings` and the MCP tool `portfolixir.portfolios.policy_findings`, whose `status=breached` is the alarm list (ADR-0049 §5, line 207-208)
- **Fix size:** S. **ADR amendment:** ADR-0049 (§5, the basis)
- **On the later `main` (read, not run):** still stands. The radius module gained crash-window and halving clauses; the Risk page gained a Crashes section. A trade still bumps only its own portfolio, and the findings memo, its portfolio basis and the any-portfolio trade-price fallback are unchanged.
- **Audit lead's note:** The observed output below is an excerpt: the layer-off control leaves out its `before`, `write` and `version` lines and two of its `after` lines, which repeat the first block's. The audit lead's re-run printed them.

**What is wrong.**

1. `PolicyFindings.for_portfolio/2` memoises its findings through `Derived.fetch/4` under the basis `portfolio:<id>` with the entry key `view|as_of|rules` (lib/portfolixir/portfolios/policy_findings.ex:89-95, :113-116). Lifetime `:request`, an ETS table every request shares until the VM stops (lib/portfolixir/derived/memo.ex:9-12).
2. The compute values the context once, through `PricingContext.for_portfolio/2` and `Valuation.for_portfolio/2` (lib/portfolixir/portfolios/policy_findings.ex:175-182); weight, HHI, cash share, drift and view share are read off that valuation (:153-173).
3. The pricing context loads `Ledger.latest_trade_prices()` (lib/portfolixir/portfolios/pricing_context.ex:143): the latest buy or sell of each security over **every** portfolio, no `portfolio_id` in the `where` (lib/portfolixir/ledger.ex:2212-2222). The valuation falls back to it for a security without a quote (lib/portfolixir/portfolios/valuation.ex:710-715), on purpose (#406, lib/portfolixir/portfolios/valuation.ex:14-21, :365-368).
4. A buy or sell in portfolio B resolves to the radius `[B]` (lib/portfolixir/derived/blast_radius.ex:65, :238-240), so `Invalidation.after_write/4` bumps `portfolio:B`, `global` and the security's basis (lib/portfolixir/derived/invalidation.ex:46-60). `portfolio:A` keeps its version.
5. The next findings read for A is a memo hit with the old weight and the old state. On the same page mount the lens (`Risk.for_portfolio/2`, lib/portfolixir_web/live/risk_live.ex:71, :197) values A afresh and shows the new weight beside the findings (:88). The API route answers the same memo (lib/portfolixir_web/controllers/api/v1/policy_finding_controller.ex:67), and its payload carries the evaluation day as `as_of` and no `stale` key (:75; see R-152 (V1-04)), so nothing in it dates the computation.
6. The same holds for an exchange-rate write: the fallback price is in the other portfolio's trade currency (lib/portfolixir/ledger.ex:2218), and `BlastRadius.for_exchange_rate/0` resolves A only when A has a foreign account or security of its own (lib/portfolixir/derived/blast_radius.ex:216-220, :254-271).

**Reproduction.**

Scratch test `test/audit_scratch/v101_findings_trade_price_test.exs` (removed after the run), run in a test slot.
3 tests, 0 failures: the assertions pin the defect (served `ok` 20 against rebuilt `breached` 50 with the layer on; equal with it off).

_(scratch test source and run command: in the private evidence held by the owner)_

**Observed output.**

```
== layer on ==
before  finding(memo read)   = {:ok, "20.00"}
before  lens weight of X     = 20.00
before  API finding          = {"ok", "20", %{"breached" => 0, "ok" => 1, "undetermined" => 0}, false, "2026-11-16"}
write   buy 1 X @ 400 in portfolio B
version portfolio A basis    = 409719 -> 409719 (moved: false)
version portfolio B basis    = 409711 -> 409725 (moved: true)
after   finding(served)      = {:ok, "20.00"}
after   lens weight of X     = 50.00
after   API finding          = {"ok", "20", %{"breached" => 0, "ok" => 1, "undetermined" => 0}, false, "2026-11-16"}
after   API risk weight of X = "50"
after   finding(rebuilt, layer off) = {:breached, "50.00"}
served == rebuilt?           = false

== layer off ==   (control: the same writes)
after   finding(served)      = {:breached, "50.00"}
after   lens weight of X     = 50.00
after   API finding          = {"breached", "50", %{"breached" => 1, "ok" => 0, "undetermined" => 0}, false, "2026-11-16"}
served == rebuilt?           = true

== layer on, rate write ==
before  finding(memo read)   = {:ok, "20.00"}
write   EUR/USD 1.25 -> 0.50
radius  for_exchange_rate    = A in radius: false, B in radius: true
version portfolio A basis    = moved: false; portfolio B basis moved: true
after   finding(served)      = {:ok, "20.00"}
after   finding(rebuilt, layer off) = {:breached, "38.46"}

3 tests, 0 failures
```
The fourth element of each "API finding" tuple is `Map.has_key?(data, "stale")`: false, the payload has no such key.

**Cost of leaving it.**

- 1 of 8 registered analytics; 2 surfaces (the Risk page; the findings route and its MCP tool). The alarm list (`status=breached`) answers empty while the rule is breached, and the page shows 50 % in the lens beside a finding that says 20 %, `ok`.
- The wrong answer lasts until any write whose radius holds A (a booking in A, a quote for a security A ever transacted, any write that widens to every portfolio), the day rollover (the key carries `as_of`), a memo flush or a restart: hours rather than days on an instance with a daily quote sync.
- What the memo buys: `PolicyFindings.for_portfolio/2` with one weight rule, layer off, took 12.8 ms and 10.9 ms on the measure task's synthetic ledger (50 securities, 1,000 bookings, 10 years; timing run recorded in R-066 (V1-03)'s and R-067 (V1-06)'s evidence). Rules over walk metrics ride `portfolio_metrics`' own memo.

**Proposed fix.**

Key `policy_findings` under the global basis, as the benchmark comparison is (lib/portfolixir/portfolios/performance/benchmark.ex:48-52: "every quote, rate or ledger write bumps the global basis"), or carry the global version in the entry key beside the rules counter; the findings then recompute after any write on the instance, at the roughly 11 ms measured above. Registering it at `:none` is the other honest shape at that cost. Add the two-portfolio case and the rate case to `test/portfolixir/portfolios/policy_findings_memo_test.exs`. Widening `transaction_radius/1` to every portfolio that ever traded the security would re-walk each of them on every trade and is the costlier choice. Size S (hours). Needs an amendment of ADR-0049 §5, which names the basis.

**Second reading.**

- Lens: decided (is it already decided or tracked?). Refuted: no. Severity it would defend: S1.

  Not refuted through the DECIDED lens. I searched docs/decisions, ideas.md (I1 to I42, F rows), the three security triages, the security lens (N-01 to N-93), sprint plans, retrospectives, sprint-status.yaml and the API reference.

  The two halves are each decided, their interaction is not. ADR-0049 §5 (216-220) and the Sprint 15 plan (A2, line 116) key the findings under the portfolio basis, but with the reason that a stale finding "would be a stale answer to the only question the read exists for"; the API reference (docs/integration/api-and-mcp.md:3957) repeats the keying without accepting staleness. The global fallback is #406 (epics.md:580-582). ADR-0032 §3.2 fixes a transaction's radius at its own portfolio, but for the walk, and lists "caching valuation or allocation" as not decided (line 325-328); it names a too-narrow radius as the danger, not a trade-off.

  The records point the other way: ADR-0039 I1 (line 154), the registry's benchmark entry keyed globally because its input lies outside the portfolio's radius (lib/portfolixir/derived/registry.ex), and the memo test's story that a memoised answer never says "ok" for a breached rule (test/portfolixir/portfolios/policy_findings_memo_test.exs:41-45). Triage items F46, F47 and Sprint 15's closing act fixed sibling stale-memo gaps as defects; none ruled "no action".

  Code read confirms the path (pricing_context.ex:143, ledger.ex:2212-2222, blast_radius.ex:238-240); the layer is on by default (derived.ex enabled?/0).

  Severity: S1 holds by the audit's own definition and the ladder's "derivation can be wrong"; the reach is narrow, which the ladder does not discount.

- Lens: reach (can the operator or the agent get there?). Refuted: no. Severity it would defend: S1.

  Not refuted. Read at e014f284: the memo is keyed on the portfolio basis plus the rules counter (policy_findings.ex:89-95), its valuation loads the unscoped Ledger.latest_trade_prices/0 (pricing_context.ex:143; ledger.ex:2212-2222), and a buy or sell bumps its own portfolio only (blast_radius.ex:238-240). The layer is on outside tests (derived.ex:50-54); the repro read through the page's and the route's own calls (risk_live.ex:88; policy_finding_controller.ex:67).

  Strongest reach ground: a second portfolio is a compatibility-only state. ADR-0024 (docs/decisions/0024-buckets-and-views-replace-portfolios-in-the-ui.md:43-45) demoted the entity; no screen creates one, imports and account creates bind to the one default (portfolios.ex:79-83; imports/applier.ex:1290-1302), and POST /portfolios is deprecated. The fixture built both with Portfolios.create_portfolio under the UI actor. With one portfolio neither variant exists: a new trade's currency must be the security's or the cash account's (ledger/transaction.ex:154-162), so a rate write reaches it.

  That narrows reach without closing it. Multi-portfolio instances are on record as normal use: #1333 was ranked S2 and built (sprint-plan-2026-11-01-sprint22-severity-pass.md:130), the booking drawer lists other portfolios' depots (docs/product-documentation.md:767-774), the demo seed holds one security in two portfolios (priv/demo/finding_surfaces_seed.exs:1806), and the split radius already spans portfolios (blast_radius.ex:226-228). There an ordinary drawer booking produces it, until the next write reaching the portfolio or midnight. The class is the ladder's S1 ("can be wrong", docs/development/sprint-workflow.md:113); reach does not demote it. ADR-0024's pending merge of the records would remove the precondition; nothing tracks the defect.

**Audit lead's re-run.** The scratch test was run again by the audit lead on 2026-11-16 in a clean slot; it passed and printed the figures above.

### R-008 (V1-02), S1: An exchange-rate write does not reach a portfolio whose only foreign-currency touch is a delivery's own price currency; the stored walk is served unchanged and marked fresh, also from the durable row after the memo is emptied

- **Class:** derived-layer invalidation gap (the radius reads two of the three currency sets the walk reads)
- **Stands against:** `docs/decisions/0039-durable-derived-values.md:154` (I1: "`derived == rebuild_from_scratch(transactions)` for any ledger state"); `lib/portfolixir/derived/blast_radius.ex:213` ("A single-currency portfolio is never converted, so a rate cannot move it."); `lib/portfolixir/derived/blast_radius.ex:29` ("no path exists in which a write silently affects nothing"). The rule as decided is `docs/decisions/0032-derived-series-memoization.md:146` ("Exchange-rate upsert | every portfolio whose base currency differs from the currency of any account or ever-held security"), which the code implements; the walk reads one currency more than that row names
- **Locations:** lib/portfolixir/derived/blast_radius.ex:208-220, lib/portfolixir/derived/blast_radius.ex:254-271, lib/portfolixir/derived/invalidation.ex:114-116, lib/portfolixir/portfolios/performance.ex:155-166, lib/portfolixir/portfolios/performance.ex:1189-1191, lib/portfolixir/portfolios/performance.ex:1607-1622, lib/portfolixir/portfolios/performance.ex:1929-1936, lib/portfolixir/portfolios/performance.ex:1947-1957, lib/portfolixir/ledger/transaction.ex:144-166, lib/portfolixir/ledger/transaction.ex:526-530, lib/portfolixir/ledger/settlement_guard.ex:70, test/invariants/blast_radius_widening_test.exs:23-24, test/portfolixir/portfolios/performance_blast_radius_test.exs:146-166, config/config.exs:95-96
- **Who meets it:** the agent on `GET /api/v1/portfolios/:portfolio_id/performance` (and the contribution and risk reads keyed under the same portfolio basis) for a portfolio holding such a booking; the operator on that portfolio's chart; nobody on the cross-portfolio reads, which are keyed under the global basis
- **Fix size:** S. **ADR amendment:** ADR-0039 (dated note widening the exchange-rate row carried from ADR-0032 §3.2)
- **On the later `main` (read, not run):** still stands. The radius module gained unrelated clauses and the config an unrelated block. The exchange-rate resolver, which picks the portfolios a rate write refreshes, still reads only foreign cash accounts and foreign securities, not a booking's own currency.
- **Audit lead's note:** The second reading narrows the reach stated in this entry. The Wealth chart and the Overview read the view walk under the global basis, which a rate write does move, so they are not affected; the operator meets it on the Risk and Snapshots pages only, the agent on the per-portfolio performance read. The importers cannot write the shape: it needs a delivery booked over the API or MCP, or a buy or sell stored before #1199.

**What is wrong.**

1. The walk preloads a rate series for "account, security/trade and transaction currencies plus the base": `init_fx/4` takes each booking's own `currency_code` and its security's currency (lib/portfolixir/portfolios/performance.ex:1947-1957).
2. It converts in a booking's own currency in three places: the lot price of a trade or priced delivery (`quantity_leg/2`, :1189-1191), a priced delivery's external flow (`leg_value/4`, :1929-1936), and every trade or delivery price point that seeds a security without a quote (`trade_points/2`, :1607-1622).
3. `BlastRadius.for_exchange_rate/0` resolves portfolios from two sets only: a cash account whose currency differs from the base (lib/portfolixir/derived/blast_radius.ex:254-261) and a security ever transacted whose currency differs from the base (:263-271). A booking's own `currency_code` is not read.
4. The write path lets the three differ. The third-currency refusal covers buy and sell only (lib/portfolixir/ledger/settlement_guard.ex:70, lib/portfolixir/ledger/transaction.ex:154-166), and a delivery validates its security, depot, quantity and a price of 0 or more, and no currency (lib/portfolixir/ledger/transaction.ex:526-530). The run below books one through `Ledger.create_transaction/2`, the function the API's create calls (lib/portfolixir_web/controllers/api/v1/transaction_controller.ex:154).
5. For such a portfolio a rate write bumps `global` only (lib/portfolixir/derived/invalidation.ex:114-116); the walk's key under `portfolio:<id>` is unchanged, and `Performance.analysis/2` serves the pre-rate series with `stale: false` (lib/portfolixir/portfolios/performance.ex:155-166), from the memo and, with the memo emptied, from the durable row (config/config.exs:95-96).
6. The gate that pins the widening rule excludes this resolver ("Arity-0 entry points are excluded: with no arguments there is no clause to fall through", test/invariants/blast_radius_widening_test.exs:23-24), and the radius test covers the account case and the security case only (test/portfolixir/portfolios/performance_blast_radius_test.exs:146-166).

**Reproduction.**

Scratch test `test/audit_scratch/v102_fx_radius_test.exs` (removed after the run), run in a test slot.
2 tests, 0 failures: the assertions pin the defect (800 served, 500 rebuilt) and the control.

_(scratch test source and run command: in the private evidence held by the owner)_

**Observed output.**

```
lifetime of performance_analysis = :durable
write   inbound_delivery 10 @ 100 USD into an EUR portfolio, EUR security: :ok
before  served flow 01-10 = 800.00  value 01-10 = 800.00  value 01-31 = 800.00  stale = false  computed_at = 2026-11-16 19:08:04Z
write   EUR/USD 2.00 dated 2024-01-08 (1.25 before)
radius  for_exchange_rate() contains the portfolio: false
version portfolio basis moved: false; global basis moved: true
after   served flow 01-10 = 800.00  value 01-10 = 800.00  value 01-31 = 800.00  stale = false  computed_at = 2026-11-16 19:08:04Z
after   memo emptied (restart): served flow 01-10 = 800.00  value 01-10 = 800.00  stale = false  computed_at = 2026-11-16 19:08:04Z
rebuild layer off:        flow 01-10 = 500.00  value 01-10 = 500.00  value 01-31 = 500.00

control EUR-priced delivery portfolio in radius: false; USD-security portfolio in radius: true
control USD-security portfolio served flow 01-10: 800.00 -> 500.00

2 tests, 0 failures
```

**Cost of leaving it.**

- 3 of 8 registered analytics are keyed under the portfolio basis and read this walk (`performance_analysis`, durable; `performance_contribution` and `portfolio_metrics`, `:request`). The two view analytics and the benchmark comparison are keyed under `global` and are not affected, so the cross-portfolio chart moves while the portfolio's own does not.
- Wrong figures: the delivery day's external flow and, for a security without a quote, every day's value from the delivery on (both 800 against 500 in the run), hence TTWROR, invested capital and the contribution rows built from them.
- Duration: until the next write whose radius holds the portfolio or the next day (the key carries `today`). A daily rate sync after the day's first read leaves the day's walk on yesterday's rate for the rest of the day; a backfilled or corrected rate history stays unseen for the same span.
- Rows that can carry it: deliveries priced in a third currency (API, MCP, import), and buy or sell rows stored before the #1199 refusal. The booking form derives the currency from the depot's cash account (lib/portfolixir_web/live/transaction_management_live.ex:934, :2386-2393), which the first set already covers.

**Proposed fix.**

Add a third set to `for_exchange_rate/0`: portfolios with a booking whose `currency_code` differs from the portfolio's base (one query beside the two), so the radius reads the currencies `init_fx/4` reads; pin it in `test/portfolixir/portfolios/performance_blast_radius_test.exs` and correct the sentence at lib/portfolixir/derived/blast_radius.ex:213. Size S (hours). It widens the exchange-rate row of ADR-0032 §3.2 that ADR-0039 carries, so a dated note in ADR-0039 naming the third set. Refusing a delivery's third currency at the write instead is a change to how bookings are validated and the owner's to decide.

**Second reading.**

- Lens: decided (is it already decided or tracked?). Refuted: no. Severity it would defend: S1.

  Not refuted through the DECIDED lens. I searched for a record that accepts or tracks this and found none.

  - ADR-0032 §3.2 (line 146) decides the exchange-rate radius as "account or ever-held security", and blast_radius.ex:216-220, 254-271 implements exactly that. The same ADR promises "No read is ever served a pre-write series silently" (lines 191-194) and says the design fails toward recomputation (123-126). The row is narrower than the walk's read set; it does not accept a stale figure.
  - ADR-0039 I1 (line 154) requires rebuild equivalence. None of its amendments narrows the rate case.
  - The ADR-0015 amendment of 2026-10-09 refuses a third currency for "a new buy or sell" only (lines 272-282); `@guarded_types ["buy", "sell"]` at settlement_guard.ex:70. Deliveries are not mentioned, and transaction.ex:526-530 checks no currency.
  - The ADR-0010 amendment of 2026-09-15 (lines 253-277) gave deliveries a booked price in the walk without touching the radius. docs/integration/api-and-mcp.md:2054-2057 documents a delivery's booked price "in `currency_code`", so the shape is intended input.
  - ideas.md (I and F rows), the three security triages, the feedback triages, the sprint plans and retrospectives, and the security lens (N-01 to N-93) hold nothing on the rate radius. The nearest are F47 and F53 (other radius matters) and ADR-0035:91-93 (an earlier, fixed defect of the same class).

  The code reads as the evidence says: performance.ex:1189-1191, 1929-1936, 1947-1957 convert in the booking's own currency; invalidation.ex:114-116 bumps only the resolver's answer.

  Severity stays S1 under sprint-workflow.md:113 ("a figure ... or derivation can be wrong"). The reach is small, and the ladder has no reach qualifier.

- Lens: reach (can the operator or the agent get there?). Refuted: no. Severity it would defend: S1.

  Not refuted: one well-formed API request produces the state. A delivery's currency has no rule (transaction.ex:526-530), the API create calls the function the reproduction called (transaction_controller.ex:154), and GET /api/v1/portfolios/:id/performance reads the portfolio-basis walk (performance_controller.ex:19, performance.ex:155-161). The radius reads accounts and securities only (blast_radius.ex:216-219).

  The reach is narrower than the evidence states, in three places:

  1. Import cannot carry the shape, which the evidence lists but did not run. A JSON delivery is never priced (json_parser.ex:1054; ideas.md:142), and every CSV row books EUR (csv_parser.ex:428). The UI books no delivery (transaction.ex:15-18). The MCP description says "the security's or the account's, else 422" (tools.ts:4123), but nothing enforces it for a delivery. The producers are a raw API or MCP create or patch, and API trades stored before #1199.

  2. The operator's portfolio chart and dashboard are not affected: both read view_analysis under the global basis (portfolio_live.ex:967, dashboard_live.ex:984). The operator meets it only on the Risk and Snapshots pages; the agent on the per-portfolio performance family.

  3. The window is often hours: the key carries today (performance.ex:194), and a quote-sync write for any security the portfolio ever transacted bumps it (quotes.ex:642, six-hour cadence). The only production rate writer is RateSync (rate_sync.ex:434). The daily file moves the newest day only; the reproduction's mid-history change needs a history backfill over gap days.

  S1 stands by kind: the ladder says "can be wrong" (sprint-workflow.md:113). It is the floor of S1.

**Audit lead's re-run.** The scratch test was run again by the audit lead on 2026-11-16 in a clean slot; it passed and printed the figures above.

### R-009 (A2-02), S1: The security chart's "Cost basis" line is a second moving-average cost fold in the LiveView; it ignores deliveries and pools all depots, so it draws another average cost than the Holdings tab of the same page

- **Class:** duplicate computation / missing pin
- **Stands against:** `docs/decisions/0033-per-position-pnl-fx-decomposition.md:308`: "All four surfaces in the Context section change together: holdings tables (portfolio and security detail), FIFO open lots, the chart cost-basis overlay, and the API/MCP payloads"; `lib/portfolixir/ledger.ex:741-743`: "Every kind in `Transaction.kinds/0` must be either handled by an `apply_cost_effect` clause or listed here — there is deliberately no catch-all (ADR-0028 §3)"; `docs/decisions/0028-corporate-actions-as-ledger-events.md:311-316` names two folds outside `Projection.effects/1` as mandatory change sites; the web fold is a third and is named nowhere.
- **Locations:** `lib/portfolixir_web/live/securities_live.ex:3998` (`cost_basis_series/4`), `:4017` (`Projection.replay_sort/1` feeding the web fold), `:4046` (`native_priced_for_overlay/2`), `:4104`, `:4120`, `:4128` (`apply_cost_basis_point/2` for buy, sell, split), `:4135` (`defp apply_cost_basis_point(_tx, acc), do: acc`), `:1397-1405` (the call from the chart template), `:6678-6680` (the rows it folds), `:6700` and `:3077` (the Holdings tab's average cost); `lib/portfolixir/ledger.ex:613-643` (`holdings_for_security/2`), `:786-813` (`apply_cost_effect/3`), `:946-975` (`remove_cost/3`); `test/invariants/cost_fold_kind_coverage_test.exs:23`.
- **Who meets it:** the operator on a security's detail page, Chart tab, with "Cost basis" switched on, for a security that has a delivery or is held in more than one depot. The agent does not: no payload carries the line.
- **Fix size:** M. **ADR amendment:** ADR-0028 §3 (dated note: its "ends in a catch-all" is out of date); otherwise none if the fold moves into the Ledger
- **On the later `main` (read, not run):** still stands. The chart's own cost fold (cost_basis_series with its catch-all clause) is identical, moved to lines 4221-4358. The security page gained a cycle view around the call; the ledger's fold and the invariant test are untouched.
- **Audit lead's note:** The two second readings were written against the first verification's run, whose files were lost (`architecture-review-triage-2026-11-24.md`, section 13). The run printed below has a control and cases 1 to 5: no case 6, no oversold case, and no line value of 20. Its counterpart to "case 6 draws 20" is case 3, where the line stays at 85, the average of shares that were never held together, against the ledger's 70.00.

**What is wrong.**

1. The Holdings tab of the security page reads `Ledger.holdings_for_security/1` (`lib/portfolixir_web/live/securities_live.ex:6700`) and prints `h.avg_cost` (`:3077`). That figure comes from the ledger's fold, per depot: a buy and a priced inbound delivery add cost (`lib/portfolixir/ledger.ex:786-790`), a sell and an outbound delivery remove cost at the lot's running average (`:792-794`), a transfer carries cost to the other depot (`:796-799`), a closed or oversold lot resets to a zero basis (`:964-966`).
2. The Chart tab reads every booking of the security (`securities_live.ex:6678-6680`, `Ledger.list_transactions_for_security/1`), and with the toggle on folds them itself (`:1397-1405` → `:3971` → `cost_basis_series/4` at `:3998`), in one running lot for the whole security (`:4018`, the accumulator is one `{qty, avg, points}`).
3. That fold has three kind clauses, buy (`:4104`), sell (`:4120`) and split (`:4128`), and ends in `defp apply_cost_basis_point(_tx, acc), do: acc` (`:4135`). An inbound delivery, an outbound delivery and a security transfer change neither its quantity nor its average and emit no point.
4. So a priced delivery moves the ledger's average and not the line; a position that came in by delivery alone has an average cost in the table and no line at all; shares that left by delivery stay in the line's running quantity and dilute the next buy; and because the lot is pooled, a sale from one of two depots leaves the line at the pooled average while the only position left carries its own.
5. The invariant test that forbids a catch-all in the cost fold reads `lib/portfolixir/ledger.ex` only (`test/invariants/cost_fold_kind_coverage_test.exs:23`); `grep -c securities_live` over it answers 0. The three tests that touch the overlay (`securities_cost_basis_overlay_test.exs`, `securities_pnl_decomposition_test.exs:160-212`, `securities_live_test.exs:1453-1494`) book buys and splits only. A new booking kind with cost semantics fails the ledger's gate and passes this fold silently.

**Reproduction.**

Scratch test `test/audit_scratch/a2_02_cost_line_test.exs` (removed after the run), modelled on `test/portfolixir_web/live/securities_cost_basis_overlay_test.exs`. The line's values are decoded from the polyline's y coordinates with the chart's own geometry (`lib/portfolixir_web/components/security_chart.ex:70-75`, `:561-565`: height 320, padding 16 top and 28 bottom, the quote range 60..110 padded by 5 %); the control case reads back 100 and 75 exactly, which checks the decoding.

_(scratch test source and run command: in the private evidence held by the owner)_

Counts: `grep -n "defp apply_cost_basis_point" lib/portfolixir_web/live/securities_live.ex`, `grep -n "defp apply_cost_effect" lib/portfolixir/ledger.ex`, `grep -c "securities_live" test/invariants/cost_fold_kind_coverage_test.exs`.

**Observed output.**

```
== control: buy 10 @ 100, buy 10 @ 50
ledger holdings {depot, quantity, avg_cost}: [{"C0 Depot", "20", "75.00"}]
holdings tab, first money cell per row: ["75.00", "1,200.00"]
chart cost-basis line values: [100.0, 75.0, 75.0]

== case 1: buy 10 @ 100, inbound delivery 10 @ 50
ledger holdings {depot, quantity, avg_cost}: [{"C1 Depot", "20", "75.00"}]
holdings tab, first money cell per row: ["75.00", "1,200.00"]
chart cost-basis line values: [100.0, 100.0]

== case 2: priced inbound delivery only, 10 @ 80
ledger holdings {depot, quantity, avg_cost}: [{"C2 Depot", "10", "80.00"}]
holdings tab, first money cell per row: ["80.00", "600.00"]
chart cost-basis line values: :no_line

== case 3: buy 10 @ 100, outbound delivery 10, buy 10 @ 70
ledger holdings {depot, quantity, avg_cost}: [{"C3 Depot", "10", "70.00"}]
holdings tab, first money cell per row: ["70.00", "600.00"]
chart cost-basis line values: [100.0, 85.0, 85.0]

== case 4: depot A buy 10 @ 100, depot B buy 10 @ 70, depot A sells its 10
ledger holdings {depot, quantity, avg_cost}: [{"C4 Depot B", "10", "70.00"}]
holdings tab, first money cell per row: ["70.00", "600.00"]
chart cost-basis line values: [100.0, 85.0, 85.0, 85.0]

== case 5: buy 10 @ 100, sell 10 @ 90, buy 10 @ 70
ledger holdings {depot, quantity, avg_cost}: [{"C5 Depot", "10", "70.00"}]
holdings tab, first money cell per row: ["70.00", "600.00"]
chart cost-basis line values: [100.0, 100.0, 70.0, 70.0]

6 tests, 0 failures
```

The first cell of each holdings row is the Avg cost column, the second the current value. The greps: 4 `apply_cost_basis_point` clauses (4104, 4120, 4128, 4135), the last a catch-all; 6 `apply_cost_effect` clauses (786, 789, 792, 796, 804, 812), none a catch-all; 0 mentions of `securities_live` in the invariant test.

**Cost of leaving it.**

- 138 lines of cost arithmetic in the LiveView (`securities_live.ex:3998-4135`), a third cost fold beside the two ADR-0028 §3 names, covered by no gate.
- Wrong line in four booking shapes, three of them shown above with figures: a priced delivery in (75.00 against 100), a position from a delivery alone (80.00 against no line), a delivery out before a later buy (70.00 against 85), a security in two depots after a sale from one (70.00 against 85). The plain single-depot buy, sell and split history agrees (control and case 5).
- The fold runs on every render of the Chart tab while the toggle is on (the toggle is off on load, `securities_live.ex:154`).
- 9 of the 15 kinds in `Transaction.kinds/0` are cost-neutral by name in the ledger; of the 6 with cost semantics the web fold knows 3.

**Proposed fix.**

The ledger answers the series: a function beside `cost_lots/1` and `position_costs/1` (`lib/portfolixir/ledger.ex:670`) that emits, per booking date, the average cost of what is held across the security's depots (total cost of the open lots over their quantity) from the pinned fold; `cost_basis_series/4` keeps only the display rebasing (`display_basis_point/2`) and the extension to the last quote. The ledger owns the rule; the web fold and its catch-all go. Size M, risk tier (cost basis, ADR-0036). No ADR amendment if the fold moves; if it stays, ADR-0028 §3 has to name it as a third mandatory change site and the invariant test has to read it. ADR-0028 §3's sentence that the ledger's `apply_cost_effect` "ends in a catch-all" (`0028-…:313`) is out of date either way: the ledger's fold has none today.

**Second reading.**

- Lens: reach (can the operator or the agent get there?). Refuted: no. Severity it would defend: S1.

  Not refuted: every reach argument fails for the delivery case.

  - **Bookings are real.** The CSV importer maps "Einlieferung"/"Auslieferung" to delivery kinds (`csv_parser.ex:77-78`) and persists the price so it enters the cost fold (`applier.ex:2738-2748`). The MCP create tool requires a price on an inbound delivery for the same reason (`mcp-server/src/tools.ts:425-430`).
  - **No guard.** The chart is fed every booking of the security (`securities_live.ex:1397-1404`, `:6679`); deliveries fall through the catch-all at `:4135`.
  - **Real callers.** The reproduction drove the real route and toggle, with bookings through `Ledger.create_transaction`.
  - **No documented convention.** The product documentation's chart section (`docs/product-documentation.md:4369-4378`) does not mention the toggle. ADR-0033 names the overlay as a cost-basis surface (`:49`), and the code comment wants it "unavailable rather than wrong" (`securities_live.ex:4000-4003`). Only commit 28cdbb94's message calls it a "weighted-average buy price".
  - **Same question.** For one depot, "Cost basis" (German "Einstandspreis") and "Avg cost" are the same figure: 100 against 75.

  Reach is narrow, as the verifier said: the toggle is off on each load (`:154`), the line carries no printed value, the figures sit on different tabs (`:1189`, `:1513`), nothing is stored or served by API/MCP.

  S1 rests on deliveries alone. The oversell case needs a negative holding the page already flags for repair (`:3058-3070`); the two-depot case is partly definitional.

  Residual doubt: the repository ladder lists "a figure contradicted between two surfaces" under S2 (`docs/development/sprint-workflow.md:116-118`). The audit brief's S1 wording covers this shape, so I keep S1.

- Lens: decided (is it already decided or tracked?). Refuted: no. Severity it would defend: S1.

  Not refuted through the DECIDED lens. I searched docs/decisions/, ideas.md (I, D and F rows), the three security triages, the feedback and backlog triages, every sprint plan and retrospective, sprint-status.yaml, the product documentation and the security lens (N-01 to N-93) for the overlay, its function names and its toggle.

  - One decision names the fold: ADR-0033 (:49-52, :308-310) lists the chart overlay as a fourth cost-basis surface that must "change together" with the holdings tables. That supports the finding.
  - ADR-0028 §3 (:312) counts two folds outside `Projection.effects/1` and omits this one.
  - No idea, triage or N-row covers it. N-85 is about a script guard. D6 (ideas.md:142) decides only the importer side of an unpriced JSON delivery.
  - No doc states the behaviour as intended. The product documentation's chart section (:4370-4378) does not list the toggle, and :1332-1336 states the cost-follows-shares rule the line breaks.
  - History shows an omission, not a decision. The overlay (28cdbb94) used the trade-stream average the holdings then used. Commit a830f448 recorded that average as a defect and fixed the ledger, but left the overlay on the old rule.

  I re-read lib/portfolixir_web/live/securities_live.ex:3998-4135; the four clauses and the catch-all are as described.

  Severity: S1 stands. The counter-reading is docs/development/sprint-workflow.md:116-118, which lists "a figure contradicted between two surfaces" under S2. But case 6 draws 20, a cost no share ever had, so the derivation itself is wrong. Reach is small: a line with no printed number, toggle off by default, nothing stored, no API or MCP field.

**Audit lead's re-run.** The scratch test was run again by the audit lead on 2026-11-16 in a clean slot; it passed and printed the figures above.

### R-010 (O2-01), S1: The performance table's first row prints the close of the window's first day as its "Start value", so a window that opens on a flow shows that flow in "Start value" and again in "Net flows", and contradicts the "Opening value" card on the same page

- **Class:** duplicate computation (a figure derived in the LiveView beside the context's own, with a different answer); missing pin
- **Stands against:** the function's own contract, "Each row: start value (the value at the slice boundary, i.e. the previous slice's last point)" (`lib/portfolixir_web/live/portfolio_live.ex:5905-5906`); the module doc, "All figures come from the same derived reads the API exposes" (`lib/portfolixir_web/live/portfolio_live.ex:6-7`); ADR-0051's baseline rule, "the start value is the close of the last day the walk covers before the window" (`docs/decisions/0051-contribution-analysis.md:174-175`).
- **Locations:** `lib/portfolixir_web/live/portfolio_live.ex:5911-5938` (`table_summary/1`), `:5922` (the first row's start), `:2451` (the call, which hands over the series only), `:4161` (the cell), `:1902` (the card); `lib/portfolixir/portfolios/performance.ex:664-665`, `:678`, `:694`, `:2021-2028` (the period's own start value and flows)
- **Who meets it:** the operator on Wealth → Holdings, opening "Data as table" under the performance chart (the chart's accessible fallback, UX-DR10); the agent never (no payload carries the rows)
- **Fix size:** S. **ADR amendment:** none
- **On the later `main` (read, not run):** still stands. Seven commits touched the Wealth page file, none the table builder. On origin/main the first row still starts at the first day's close (line 5990) and the card still prints the summary's start value (line 1907).
- **Audit lead's note:** The observed output below is an excerpt: the Max block shows two of the seven lines the scratch test printed; the other five repeat the default block's figures. The audit lead's re-run printed them.

**What is wrong.**

1. `Performance.summarise/2` splits the walk at the window's start (`lib/portfolixir/portfolios/performance.ex:664-665`) and takes the period's start value from the day before the window: `start_value = baseline(before)` (`:678`), where `baseline([])` is 0 and otherwise the last earlier day's value (`:2027-2028`). The flows of every in-window day, the first included, are summed into `net_external_flows` (`:694`, `chain_day/2` at `:2021-2025`). `series` holds the in-window days only (`:680-683`).
2. The page prints that start value on the "Opening value · net flows" card: `Format.money(@performance.start_value)` (`lib/portfolixir_web/live/portfolio_live.ex:1902`).
3. The table under the same chart is built in the LiveView from the series alone: `summary={table_summary(@performance.series)}` (`:2451`). For every slice after the first the start is `prev.value`, the close before the slice (`:5922`). For the first slice there is no `prev`, and the code takes `chunk_first.value` (`:5922`): the close of the window's FIRST day, after that day's flows and price moves.
4. The first row's other columns still measure from the day before the window: its TTWROR chains from `start_cum = 0` (`:5923`, `:5930`) and its net flows sum the whole chunk, the first day's flow included (`:5931`).
5. So a flow on the window's first day is inside the row's "Start value" and inside its "Net flows". The row no longer reconciles: start + net flows + result = end fails by exactly the first day's flow.
6. No test pins the cell: `grep -rn "Start value" test/portfolixir_web/live/*.exs` prints the column head only (`test/portfolixir_web/live/performance_table_summary_test.exs:46`); the file's one figure assertion, `assert table =~ "10,000.00"` (`:52`), is true of the start-value cell and of the net-flows cell alike.

**Reproduction.**

Scratch test `test/audit_scratch/o2_01_first_slice_test.exs` (the fixture of `test/portfolixir_web/live/performance_table_summary_test.exs`, plus one mid-history range), removed after the run:

_(scratch test source and run command: in the private evidence held by the owner)_

**Observed output.**

```
== O2-01 default (/portfolio) ==
card #kpi-invested > strong      : 0.00 EUR
card #kpi-invested (whole)       : Opening value · net flows (1Y) ⓘ [...] 0.00 EUR net flows +10,000.00 EUR
table row 1 [label,start,end,ttwror,flows]: ["2026-01", "10,000.00", "10,000.00", "0.0%", "10,000.00"]
table row 2 [label,start,end,ttwror,flows]: ["2026-02", "10,000.00", "10,050.00", "0.0%", "0.00"]
context for_view(nil, max).start_value         : 0
context for_view(nil, max).net_external_flows  : 10000.000000
context first series point (date,value,flow): {~D[2026-01-02], Decimal.new("10000.000000"), Decimal.new("10000.000000")}

== O2-01 max (/portfolio?period=max) ==
card #kpi-invested > strong      : 0.00 EUR
table row 1 [label,start,end,ttwror,flows]: ["2026-01", "10,000.00", "10,000.00", "0.0%", "10,000.00"]

== O2-01 range 2026-02-02..2026-03-10 ==
card #kpi-invested (tail)        : f the wealth multiple. 10,000.00 EUR net flows +5,000.00 EUR
table row 1 [label,start,end,ttwror,flows]: ["2026-02", "15,000.00", "15,000.00", "0.0%", "5,000.00"]
context start_value / net_external_flows / end_value: 10000.000000 / 5000.000000 / 15000.000000

3 tests, 0 failures
```

Read: on one page, for one period, the card says the period opens at 0.00 with +10,000.00 of flows; the table's first row says it opens at 10,000.00 with 10,000.00 of flows and ends at 10,000.00. In the mid-history range the card says 10,000.00 and the row 15,000.00, the difference being the 5,000.00 deposit of the window's first day.

**Cost of leaving it.**

- One wrong cell on every render of the table: the first row, every period. The size of the error is the first day's flows plus its price move. It is the whole first deposit for Max and for every period that reaches back to the first booking, which includes the default 1 year on any instance younger than a year (first run above); it is a later deposit whenever a custom range or a year opens on a flow day (third run); otherwise it is one day's price move.
- The operator who reads the row as a bridge (start + flows + result = end) is off by the first day's flow; the row beside the card looks like a second opinion on the opening value.
- 1 function (`table_summary/1`, 28 lines) and `slice_ttwror/2` live in the web layer with no context test; 0 assertions on the cell's value in `test/`.

**Proposed fix.**

The first slice starts at the summary's `start_value`: either `table_summary/2` takes the summary (or its `start_value`) and uses it where `prev` is `nil`, or, as lane R-048 (A2-07) proposes for the sibling figures, the slices become a function of the summary in `Portfolixir.Portfolios.Performance`, tested there, and the LiveView only formats them. `Performance` should own the rule: it already owns the baseline. Size S for the fix with a test that pins the cell (a window opening on a deposit; expected first-row start = the card's opening value); M if the slices also become a payload field (then with a computation basis and a contract entry). No ADR amendment.

**Second reading.**

- Lens: decided (is it already decided or tracked?). Refuted: no. Severity it would defend: S1.

  Not refuted through the DECIDED lens: no record decides, accepts or tracks the first row's start value.

  Checked: docs/decisions/ (ADR-0010, 0034, 0041, 0051); ideas.md (I and F rows); feedback, backlog and security triages; the security lens (N-ids); sprint plans, retrospectives and sprint-status.yaml; DESIGN.md and EXPERIENCE.md (UX-DR10 fixes the disclosure's control, label and purpose line, not the row arithmetic); docs/product-documentation.md:2301-2304 and the API reference (the table is in no payload). Issue #564 asks only for "start/end value" per slice; commit 37f28f54 says "the value at the slice boundary". The Wealth polish list (#1366) has no line for it. test/portfolixir_web/live/performance_table_summary_test.exs:52 pins "10,000.00" as the net flow, not the start cell.

  The records point the other way. The function's own comment defines the start as "the previous slice's last point" (portfolio_live.ex:5905-5906), which for the first slice is the day before the window, i.e. the summary's start_value (performance.ex:678, 2027-2028); line 5922 takes chunk_first.value instead while the same row's TTWROR (5923) and flows (5931) measure from before that day. ADR-0034 (docs/decisions/0034-money-weighted-metrics.md:88-90) decides opening value and net period flows as two separate numbers; the row merges the first-day flow into both.

  Severity: the ladder's S1 wording ("a figure ... or derivation can be wrong", docs/development/sprint-workflow.md:113) fits a cell wrong by its own contract. The S2 clause "a figure contradicted between two surfaces" is the only downgrade argument and is weaker, since the row also fails its own bridge. Reach is narrow: one display-only cell behind a disclosure.

- Lens: reach (can the operator or the agent get there?). Refuted: no. Severity it would defend: S1.

  Not refuted; each reach argument fails on the code.

  1. Fixture: the repository's own (test/portfolixir_web/live/performance_table_summary_test.exs:26-29), a deposit then a buy. Every instance's first walked day carries its first flow, so on Max (and 1Y/3Y/5Y while the instance is younger) the card reads 0.00 and row 1 the first-day close.
  2. Guard: none. At the default level `stacked?/1` is false (portfolio_live.ex:635), so plain /portfolio renders the line chart and its table. The call hands over the series only (:2451), so `table_summary/1` cannot know the baseline (:5922).
  3. Same question: rows 2..n start at the previous close, which is the card's rule. The comment (:5905-5906) and commit 37f28f54 both say "value at the slice boundary"; no record documents a first-point convention.
  4. Not rounding: the gap is the first day's flow plus its price move.
  5. The reproduction rendered the LiveView through addresses the period control itself writes (:226-283); no internal call with foreign arguments.

  Real limits: one cell, behind a collapsed disclosure, never stored, in no API or MCP payload. On a mature instance at 1Y the gap is one day's price move unless the window opens on a flow day.

  Severity: S1 holds. ADR-0026:300-303 files a figure "contradicted between two surfaces" as S2, but this cell is wrong by its own contract and breaks the row's bridge. Sprint 22 ranked single display cells printing a wrong figure S1 (#1331, #1274; sprint-plan-2026-11-01-sprint22.md:96).

  Not tracked: no ADR, idea row, issue or line on the Wealth polish list (#1366) names it.

**Audit lead's re-run.** The scratch test was run again by the audit lead on 2026-11-16 in a clean slot; it passed and printed the figures above.

### R-011 (O4-04), S2: The transaction history has no paging: the whole ledger is read, kept on the socket and rendered twice per booking on every open and after every write; at 10,000 bookings the page is a 34.8 MB response and its process is killed by the 512 MiB heap cap in 2 of 4 runs, at 12,500 in 2 of 2

- **Class:** structure (unbounded read and render)
- **Stands against:** `lib/portfolixir_web/heap_cap.ex:12-13`: "Defence in depth, not the bound itself: the inputs, lists, memo and walks are bounded where they arrive."; `_bmad-output/planning-artifacts/prds/prd-portfolixir-2026-06-12/prd.md:760-762`: "a single interactive view or MCP analytic response completes within p95 < 2 s on commodity home-server hardware at realistic scale (hundreds of securities, tens of thousands of transactions)" (called aspirational at `:763`); the choice itself is recorded only in a code comment, `lib/portfolixir_web/live/transaction_management_live.ex:1534-1536`: "the local ledger is bounded, so a client-side narrow is instant"; nothing else written, a change needs no ADR
- **Locations:** `lib/portfolixir_web/live/transaction_management_live.ex:109` (mount), `:1482-1515` (`load_state/1`), `:1547-1563` (`apply_current_filters/1`), `:397`, `:413-414` (table rows), `:489`, `:497-501` (phone rows), `:476`, `:537` (`@row_menu_id` inside both walks), `:891`, `:906-908`, `:968`, `:984`, `:1209`, `:1225` (`load_state/1` after a write); `lib/portfolixir/ledger.ex:50-56`; `lib/portfolixir_web/controllers/api/v1/transaction_controller.ex:21-23`
- **Who meets it:** the operator on Transactions, on every open, every booking, correction and delete, and every row menu; nobody as a crash today unless the ledger nears 10,000 bookings
- **Fix size:** L. **ADR amendment:** none
- **On the later `main` (read, not run):** still stands. The Transactions page file changed only in its filter-chip row and summary text. load_state (the page's data loader) still reads the whole ledger unbounded; both row walks and the nine call sites remain; no paging or streams.
- **Audit lead's note:** The second reading was written against the first verification's run, whose files were lost (`architecture-review-triage-2026-11-24.md`, section 13). The run printed below has no 20,000 row: the counterpart of its "20,000 HTTP kill" is the 15,000 row, where the request process was killed after the endpoint's stop event, in the test adapter's response path; that kill is not claimed for a real server. For its "under about 4,000 bookings" read the printed table: 2,000, 5,000 and 7,500 bookings open without a kill.

**What is wrong.**

1. `mount/3` calls `load_state/1` (`lib/portfolixir_web/live/transaction_management_live.ex:109`), which reads `Ledger.list_transactions()` with no limit and three preloads (`:1488`; `lib/portfolixir/ledger.ex:50-56`) and assigns the list to the socket (`:1509`). A LiveView mounts twice (the HTTP render and the socket), so the ledger is read and rendered twice per page open, synchronously.
2. `load_state/1` runs again after every write and every refused delete: 8 more call sites (`:891`, `:906`, `:907`, `:908`, `:968`, `:984`, `:1209`, `:1225`).
3. The template walks `grouped_by_month(@filtered_transactions)` twice, once for the table (`:397`, rows at `:413-414`) and once for the phone rows (`:489`, `:497-501`), so every booking is in the page twice; CSS shows one.
4. `@row_menu_id` is read inside both walks (`:476`, `:537`), so opening one row's menu re-evaluates both for the whole history and sends a diff that grows with it.
5. The filters are an in-memory copy of the query (`:1582-1654`); `Ledger.list_transactions/1` takes portfolio, security, depot, from, to, since and limit (`lib/portfolixir/ledger.ex:58-67`) and has no kind, cash-account or text filter. The file has 0 uses of `stream(` or `temporary_assigns`.
6. The page's process and the request's process run under the heap cap (`lib/portfolixir_web/heap_cap.ex:1-29`, 512 MiB by default), so past a size the page does not get slow, it is killed.

**Reproduction.**

Scratch test `test/audit_scratch/o4_04_history_size_test.exs` (removed after the run): a synthetic ledger of N bookings (three deposits to one buy, one security), then the page's HTTP render in a process of its own, the socket mount, and one `open_row_menu`; server-side durations from the `[:phoenix, :endpoint, :stop]` and `[:phoenix, :live_view, …, :stop]` telemetry events, the diff's size from a send trace on the page's process, kills from the runtime's "maximum heap size reached" report.

_(scratch test source and run command: in the private evidence held by the owner)_

One count over the source beside it:

```
grep -cE 'stream\(|temporary_assigns' lib/portfolixir_web/live/transaction_management_live.ex
```

**Observed output.**

The grep prints `0`. The test, trimmed to one line per run (`http` = the endpoint's duration for `GET /transactions`; `socket` = mount and first render on the socket; `mem` = the page process after mount; `menu` = server render and diff for opening one row's menu):

```
bookings  response    table/phone rows  http     socket mount+render  mem       menu render  menu diff   outcome
     200  0.83 MB     200 / 200         70 ms    3.8 + 11.3 ms        7.3 MB    2.3 ms       22 kB       ok
   2,000  7.07 MB     2,000 / 2,000     101 ms   19.1 + 77.4 ms       40.3 MB   8.9 ms       205 kB      ok
   5,000  17.47 MB    5,000 / 5,000     274 ms   72.0 + 221.6 ms      98.8 MB   26.2 ms      511 kB      ok
   7,500  26.14 MB    7,500 / 7,500     456 ms   115.1 + 357.8 ms     141.9 MB  39.7 ms      766 kB      ok
  10,000  34.79 MB    10,000 / 10,000   416 ms   -                    -         -            -           page process killed (1 heap-cap report)
  10,000  34.79 MB    10,000 / 10,000   465 ms   214.2 + 426.8 ms     170.1 MB  46.8 ms      1,019 kB    ok
  10,000  34.79 MB    10,000 / 10,000   534 ms   -                    -         -            -           page process killed (1 heap-cap report)
  10,000  34.79 MB    10,000 / 10,000   475 ms   237.8 + 441.9 ms     170.1 MB  41.4 ms      1,019 kB    ok
  12,500  43.40 MB    12,500 / 12,500   686 ms   -                    -         -            -           page process killed (1 heap-cap report)
  12,500  43.40 MB    12,500 / 12,500   528 ms   -                    -         -            -           page process killed (1 heap-cap report)
  15,000  -           -                 850 ms   -                    -         -            -           request process killed (1 heap-cap report)
  30,000  -           -                 (none)   -                    -         -            -           request process killed during the render (1 heap-cap report)

12 tests, 0 failures
```

Verbatim, the first killed run and the last:

```
%{
  transactions: 10000,
  heap_cap_kill_reports_logged: 1,
  list_transactions_ms: 26,
  http_render_ms: [415.9],
  http_wall_ms: 480,
  html_bytes: 34786311,
  table_rows: 10000,
  phone_rows: 10000,
  socket_connect_wall_ms: 992,
  page_process: {:died, :exit, :killed}
}
%{
  transactions: 30000,
  heap_cap_kill_reports_logged: 1,
  list_transactions_ms: 112,
  http_render_ms: nil,
  http_wall_ms: 776,
  http_request_process: {:killed_by_heap_cap, :killed}
}
```

The runtime's report of one such kill (from an earlier execution without the log capture): `Context: maximum heap size reached`, `Max Heap Size: 67108864` (words, 512 MiB), `Total Heap Size: 71764430`, with the stack inside `PortfolixirWeb.TransactionManagementLive.render/1` under `Phoenix.LiveView.Diff.traverse_keyed/8`.

**Cost of leaving it.**

- Per booking: about 3.5 kB of HTML (two rows), about 17 kB of page-process memory at rest, about 100 bytes of diff on every row-menu open.
- Per page open: the whole ledger read twice and rendered twice; per write: read and rendered again (9 call sites of `load_state/1` with the mount).
- At 10,000 bookings the page opens in about half of the runs; at 12,500 it did not open in either run. The query is not the cost: `Ledger.list_transactions/0` took 26 to 112 ms from 10,000 to 30,000 rows.
- The API bounds the same read (`@default_limit 10_000`, `@max_limit 50_000`, `transaction_controller.ex:22-23`); the screen has no bound.

**Proposed fix.**

Page the history (a limit with "load more", or LiveView streams), render one row per booking where the two layouts allow it, filter in the query (`Ledger.list_transactions/1` gains kinds, a cash-account filter that includes a transfer's receiving side, and a text filter), and take the summary from a context aggregate; the running balance stays `Projection.cash_balance_series/2` over the whole history. Size L. No ADR amendment; a paged list changes the screen, so it needs a board.

**Second reading.**

- Lens: reach and decided. Refuted: no. Severity it would defend: S2.

  Not refuted. Code as claimed: mount ends in load_state/1 (transaction_management_live.ex:109; no connected? guard, no async), Ledger.list_transactions() carries no limit (:1488; ledger.ex:83), two walks (:397, :489), @row_menu_id inside both (:476, :537). No guard keeps a ledger under 10,000: the importer takes 100,000 rows per file (imports/portfolio_performance.ex:28), the API serves up to 50,000 (transaction_controller.ex:23), the architecture's reference volume is 50,000 (architecture.md:550). Decided: nothing names this page. #771 bounds the API only, N-26 is the journal, G05/#1204/K08 the cap; polish list #1360 has no line; EXPERIENCE.md:351 prefers paging. Caveats that narrow without refuting: (1) NFR-8's 2 s is aspirational and performance gates are deliberately not adopted (prd.md:763; project-context.md:270), so the wait alone is S3; S2 rests on the kill. (2) transaction_controller.ex:21 calls 10,000 'above a realistic ledger'; under about 4,000 bookings only cost is met, as the evidence itself says. (3) The 20,000 HTTP kill is one run, and the test adapter flattens the body inside the capped process (plug test adapter, send_resp), so that threshold is less certain in production; the browser's behaviour after the kill was not observed.

### R-012 (D2-03), S2: A held category the plan does not target carries a full-weight drift and a sell-everything hint in the domain and over the API, passes the shared threshold predicate, and is blanked or dropped by a rule of its own on the Wealth page, the Overview and the rules read

- **Class:** duplicate computation (the rule "no target, no drift" is written three times outside the domain row and not in it); ADR drift
- **Stands against:** `lib/portfolixir/portfolios/allocation.ex:149-152`: "A category without a target carries `drift_weight: nil` — it has nothing to deviate from, so a threshold never selects it."; `docs/integration/api-and-mcp.md:3600-3603`: "returns only the category rows whose `|drift_weight|` meets it — targetless categories carry no drift and are filtered out with it"; `mcp-server/src/tools.ts:4301`: "targetless categories drop out"; `lib/portfolixir_web/live/portfolio_live.ex:784-786`: "one number across chips, column, dashboard and API"; `lib/portfolixir/portfolios/allocation.ex:985-988`: "a drift against no target is undetermined, not a drift against zero" (ADR-0049 §3).
- **Locations:** `lib/portfolixir/portfolios/allocation.ex:155-159`, `:967-996`, `:1009-1060`; `lib/portfolixir_web/controllers/api/v1/json.ex:1434-1438`, `:1647-1649`; `lib/portfolixir_web/live/portfolio_live.ex:773-774`, `:800-801`, `:2898-2915`, `:5103-5123`; `lib/portfolixir_web/live/dashboard_live.ex:1192-1195`; `lib/portfolixir/portfolios/policy_findings.ex:348-351`; `test/portfolixir/portfolios/drift_threshold_test.exs:24`, `:47-49`
- **Who meets it:** the agent on `GET /api/v1/portfolios/:id/allocation` (with or without `min_drift=`) and the MCP allocation tool; the operator on Wealth, tab "Allocation & targets", with a drift chip pressed.
- **Fix size:** M. **ADR amendment:** ADR-0023
- **On the later `main` (read, not run):** still stands. Three cited files changed elsewhere (drift chip bar markup, other serializers, Overview cards). The row builder, the threshold predicate, the API filter, both Wealth-page blanking rules and the Overview's own predicate read the same on origin/main.
- **Audit lead's note:** S2, not S1: against a plan that sums to 100 % an untargeted holding is arithmetically overweight, so the figure is right on the basis target = 0. What is wrong is the written statement that such a row carries no drift, and each page's own rule for hiding it.

**What is wrong.**

1. `Allocation.row/5` computes a drift for every category row: `target_weight = values.target || @zero` (`lib/portfolixir/portfolios/allocation.ex:969`), `drift_weight = Decimal.sub(actual, drift_target(target_weight, drift_base))` (`:970`), and sets `has_target: not is_nil(values.target)` beside it (`:989`). No category row carries `drift_weight: nil`; the only `nil` is on position entries (`:693`).
2. So the `nil` clause of `drift_at_least?/2` (`:156`) never fires for a real row. Its test feeds a hand-made map `%{drift_weight: nil}` (`test/portfolixir/portfolios/drift_threshold_test.exs:24`, `:47-49`), which no caller builds.
3. `JSON.allocation/2` filters `allocation.categories` with that predicate (`lib/portfolixir_web/controllers/api/v1/json.ex:1434-1438`) and serialises `drift_weight` and `drift_value` for every row (`:1647-1649`); `has_target` is not in the payload, so the agent cannot tell "no target" from "target 0".
4. With a plan present, `with_rebalance_hints/2` (`allocation.ex:1009-1027`) gives each position of the untargeted row its share of that drift: `drift_value` is its whole market value, `rebalance_quantity` its whole quantity (`:1033-1060`).
5. The Wealth page filters and counts with the same predicate (`lib/portfolixir_web/live/portfolio_live.ex:773-774`, `:800-801`), then prints a dash where `target_weight` is 0 (`:2898-2915`) and blanks the positions' drift and hint (`:5103-5123`): the rule "untargeted means no drift" exists there, in the web layer, on `target_weight == 0`.
6. The Overview has its own predicate, `target_weight > 0` and `|drift| > 0.05` strict (`lib/portfolixir_web/live/dashboard_live.ex:1192-1195`); the rules read has a third, `has_target: true`, else `{:undetermined, :no_target}` (`lib/portfolixir/portfolios/policy_findings.ex:348-351`).

**Reproduction.**

Scratch file `test/audit_scratch/d2_03_test.exs` (removed after the run), run in a test slot.

_(scratch test source and run command: in the private evidence held by the owner)_

**Observed output.**

`1 test, 0 failures`.

```
[D2-03 domain] plan: Core 100 %, no row for Loose; each holds 1000 of 2000
  has_plan=true drift_basis=full_plan
  Loose: has_target=false target_weight=0 actual=0.5 drift_weight=Decimal.new("0.5") drift_value=Decimal.new("1000.0000000000000000000")
  Allocation.drift_at_least?(Loose, 0.05) = true
  Loose Co position: drift_value=Decimal.new("1000.000000000") rebalance_quantity=Decimal.new("10.00000000000") (quantity held 10.000000000000)

[D2-03 API] GET /allocation?classification_id=..&min_drift=0.05
  min_drift="0.05" categories_total=2 returned=2
  rows = [%{"drift_value" => "-1000", "drift_weight" => "-0.5", "name" => "Core", "target_weight" => "1"}, %{"drift_value" => "1000", "drift_weight" => "0.5", "name" => "Loose", "target_weight" => "0"}]
  Loose positions = [%{"drift_value" => "1000", "quantity" => "10", "rebalance_quantity" => "10", "security_name" => "Loose Co"}]
  keys of a category row = ["actual_weight", "category_id", "child_target_sum", "color", "conflict", "depth", "drift_value", "drift_weight", "has_stale", "market_value", "name", "own_market_value", "parent_id", "positions", "target_weight"]

[D2-03 Wealth, Allocation tab, chip ">= 5 pp" clicked]
  summary line : ["Showing 2 of 2 categories, those deviating by at least 5 pp. Cash and unassigned always show."]
  table rows   : ["▸ Core 1,000.0050.0% 100.0% -1,000.00 EUR", "▸ Loose 1,000.0050.0% — —", "Cash 0.000.0% — —"]

[D2-03 Overview, card "Off target"]
  items : ["Core 50.0 pp below target · -1,000.00 EUR"]

[D2-03 rules read] drift rule on Loose: state=undetermined value=nil reason=:no_target
```

The API returns the untargeted category under `min_drift=0.05` with `"drift_weight": "0.5"` and its one position with `"rebalance_quantity": "10"` (all 10 units). The Wealth page counts it among "those deviating by at least 5 pp" and prints "— —" for its target and drift. The Overview lists Core only. The rules read says undetermined, `no_target`.

**Cost of leaving it.**

- 3 predicates for "drifts beyond a threshold" in 3 files (`allocation.ex:155-159`, `dashboard_live.ex:1192-1195`, `policy_findings.ex:348-351`), 2 web-layer blanking rules (about 25 lines, `portfolio_live.ex:2898-2915`, `:5103-5123`) standing in for a domain rule, 1 dead clause with 2 tests that pin it on a hand-made map.
- 4 written statements the code does not keep (the predicate's doc, the API reference, the MCP tool description, the comment at `json.ex:1421-1423`); `has_target` computed at `allocation.ex:989` and not served.
- Every allocation read with a plan and a held category without a target row is affected: the agent reads a drift of the category's whole weight and hints to sell all of it; the chips' count line and the rows it counts disagree with the dash in the row.
- No test puts an untargeted, held category under a threshold (`test/portfolixir_web/controllers/api_v1_read_ergonomics_test.exs:264-288` and `test/portfolixir_web/live/portfolio_live_test.exs:135-205` target every category).

**Proposed fix.**

The domain row states the rule once: for a row with `has_target: false`, `drift_weight` and `drift_value` are `nil` and its positions get no category-share hint; the serializer writes `null` (and serves `has_target`); the two blanking rules in `portfolio_live.ex` and the Overview's own predicate go, and all call sites use `drift_at_least?/2`. Size M (two API fields become nullable for untargeted rows, a release note; the allocation is not risk tier but ADR-0023's hints move). Needs an amendment of ADR-0023 (one sentence: a category without a target has no drift and no hint), which also settles the explicit-target-0 case: the Wealth page prints a dash for it, the Overview drops it, the rules read evaluates it.

**Second reading.**

- Lens: reach and decided. Refuted: no. Severity it would defend: S2.

  Not refuted. Reach: a held category without a target row is ordinary. The suite builds one itself ("a plan summing to 1.0 is untouched, even with untargeted holdings", test/portfolixir/portfolios/allocation_test.exs:2062-2120), and a plan that targets only parents or only leaves produces such rows (dashboard_live.ex:1095-1096 names "an untargeted parent"). No guard intervenes: row/5 sets the target to 0 and always computes a drift (allocation.ex:969-970), a held row is kept, and JSON.allocation/2 filters with a predicate whose nil clause no row reaches (json.ex:1434-1438). Decided only in part: ADR-0049 §3 (:130-132) rules "no target" undetermined for the rules read, and the Overview's target-only rule is a recorded criterion (test/portfolixir_web/live/dashboard_test.exs:266-267). Nothing decides the API row; the records state the opposite of the behaviour: FR-37's criterion (api_v1_read_ergonomics_test.exs:257-259), the API reference (docs/integration/api-and-mcp.md:3600-3603), the predicate's doc (allocation.ex:149-152). ADR-0023 and ADR-0040 are silent. S2 holds by the ladder's own examples: an API answer that misleads, a figure contradicted between two surfaces. One caveat for the fix: under a full plan an untargeted holding is arithmetically overweight against it, so which side is right needs the amendment, not a silent null.

### R-013 (A2-03), S2: Both screens decide "is this category targeted" by `target_weight == 0` instead of the row's `has_target`, so a held category with an explicit 0 % target reads "—" on Wealth and "All targets within ±5 pp" on the Overview while the engine, the API filter and the policy read count it 8 pp off target

- **Class:** seam crossed (a domain predicate re-decided in the web layer)
- **Stands against:** `lib/portfolixir/portfolios/allocation.ex:985-986`: "Whether the active plan steers this category at all — the one fact `target_weight` (0 when absent) cannot tell apart from a target of 0."; `lib/portfolixir_web/live/dashboard_live.ex:1095`: "Only rows that carry a target count"; `lib/portfolixir_web/live/portfolio_live.ex:784-786`: "one number across chips, column, dashboard and API beats a chip that agrees with the columns and with nothing else"; `test/portfolixir_web/live/classifications_position_targets_test.exs:139`: "\"0\" is a target of zero and is stored as one."
- **Locations:** `lib/portfolixir_web/live/dashboard_live.ex:36` (`@drift_threshold`), `:1192-1195` (`targeted_beyond_threshold?/1`), `:522-524` (the all-clear line); `lib/portfolixir_web/live/portfolio_live.ex:2880`, `:2898`, `:2909`, `:5108`, `:5331`, `:5343` (category rows), `:2984`, `:2995`, `:5154` (cash row), `:774`, `:801` (the chips, on the context's predicate); `lib/portfolixir/portfolios/allocation.ex:154-159` (`drift_at_least?/2`), `:968-990` (`row/5`, `has_target` at `:989`), `:566-579` (`cash_row/5`, no `has_target`); `lib/portfolixir/portfolios/policy_findings.ex:349`; `lib/portfolixir_web/controllers/api/v1/json.ex:1438`, `:1637-1653` (the category row, without `has_target`); `lib/portfolixir/portfolios/target.ex:91-94`.
- **Who meets it:** the operator on the Overview's "Off target" card and on Wealth, Allocation tab, with a plan that sets a held category to 0 %. The agent reads the drift (0.08) but cannot tell an explicit 0 from no target: the API row has no `has_target`.
- **Fix size:** S to M. **ADR amendment:** none
- **On the later `main` (read, not run):** still stands. Three cited files changed, none in the cited lines: the Overview card and Wealth's nine cells still decide 'targeted' from the weight being zero, and the API allocation row still omits has_target (the row's steered-or-not flag).
- **Audit lead's note:** The second reading was written against the first verification's run, whose fixture differed (`architecture-review-triage-2026-11-24.md`, section 13). In the run printed below the drift is 8 pp, not 7, and the plans were written through `Targets.set_targets`, not through `#soll-plan-form`.
- **Audit lead's note:** Fix size S is the screens alone. With the API field and the cash row, which the proposed fix includes, it is M.

**What is wrong.**

1. A target weight of 0 is storable (`lib/portfolixir/portfolios/target.ex:91-94`, 0 ≤ weight ≤ 1), and the plan editor's own test pins that "0" is stored as zero while an empty field stores no row (`test/portfolixir_web/live/classifications_position_targets_test.exs:130-159`).
2. The allocation row for such a category carries `has_target: true`, `target_weight: 0` and `drift_weight` = its whole actual weight (`lib/portfolixir/portfolios/allocation.ex:968-990`). An untargeted category carries `has_target: false` and the same two figures.
3. The Overview keeps a row only when `target_weight > 0` and `|drift_weight| > 0.05` (`lib/portfolixir_web/live/dashboard_live.ex:1192-1195`). The explicit-0 row is dropped; when nothing else passes, the card prints "All targets within ±5 pp — nothing needs rebalancing." (`:522-524`).
4. Wealth prints "—" for the row's Target and Drift (`lib/portfolixir_web/live/portfolio_live.ex:2898`, `:2909`), and the flat worklist blanks its positions' drift and hints (`:5108`, `:5343`), by `Decimal.equal?(row.target_weight, 0)`.
5. The "≥ 5 pp" chip on the same table calls `Allocation.drift_at_least?/2` (`:774`, `:801`), which keeps the row: the filtered table lists a category as "deviating by at least 5 pp" with a dash in its Drift cell.
6. The API's `min_drift=` filter calls the same predicate (`lib/portfolixir_web/controllers/api/v1/json.ex:1438`) and answers the row with `target_weight "0"`, `drift_weight "0.08"`. The policy read evaluates the row as targeted (`lib/portfolixir/portfolios/policy_findings.ex:349`, `%{has_target: true, drift_weight: drift}`).
7. `grep -rn has_target lib/portfolixir_web` finds one use (`portfolio_live.ex:5209`, the basis tooltip's example); ten web sites decide "targeted" from the weight (7 for categories, 3 for cash).

**Reproduction.**

Scratch test `test/audit_scratch/a2_03_zero_target_test.exs` (removed after the run). Case 1 is the candidate; case 2 the control with no target at all; case 3 the threshold's boundary.

_(scratch test source and run command: in the private evidence held by the owner)_

Counts: `grep -n "Decimal.equal?(row.target_weight, 0)\|Decimal.equal?(@allocation.cash.target_weight, 0)\|Decimal.equal?(cash.target_weight, 0)" lib/portfolixir_web/live/portfolio_live.ex` and `grep -rn "has_target" lib/portfolixir_web`.

**Observed output.**

```
== case 1: plan Core 50 / Satellite 50 / Legacy explicit 0; held 46 / 46 / 8
engine: top_level_target_sum=100.0 drift_basis=full_plan
engine row Core: has_target=true target=50.0 actual=46.0 drift=-4.0 pp drift_at_least?(0.05)=false
engine row Satellite: has_target=true target=50.0 actual=46.0 drift=-4.0 pp drift_at_least?(0.05)=false
engine row Legacy: has_target=true target=0.0 actual=8.0 drift=8.0 pp drift_at_least?(0.05)=true
API min_drift=0.05 rows {name, target_weight, drift_weight, has_target}: [{"Legacy", "0", "0.08", :absent}]
Overview alerts: []
Overview all-clear line: "All targets within ±5 pp — nothing needs rebalancing."
Wealth table [Category, Value, Actual, Target, Drift]:
  ["▸ Core", "4,600.00", "46.0%", "50.0%", "-400.00 EUR"]
  ["▸ Satellite", "4,600.00", "46.0%", "50.0%", "-400.00 EUR"]
  ["▸ Legacy", "800.00", "8.0%", "—", "—"]
  ["Cash", "0.00", "0.0%", "—", "—"]
Wealth table, chip >= 5 pp [Category, Value, Actual, Target, Drift]:
  ["▸ Legacy", "800.00", "8.0%", "—", "—"]
  ["Cash", "0.00", "0.0%", "—", "—"]

== case 2: plan Core 50 / Satellite 50 / Legacy untargeted; held 46 / 46 / 8
engine row Legacy: has_target=false target=0.0 actual=8.0 drift=8.0 pp drift_at_least?(0.05)=true
API min_drift=0.05 rows {name, target_weight, drift_weight, has_target}: [{"Legacy", "0", "0.08", :absent}]
Overview alerts: []
Overview all-clear line: "All targets within ±5 pp — nothing needs rebalancing."
Wealth table, chip >= 5 pp [Category, Value, Actual, Target, Drift]:
  ["▸ Legacy", "800.00", "8.0%", "—", "—"]
  ["Cash", "0.00", "0.0%", "—", "—"]

== case 3: plan Core 50 / Satellite 50; held 55 / 45 (drift exactly 5 pp)
engine row Core: has_target=true target=50.0 actual=55.0 drift=5.0 pp drift_at_least?(0.05)=true
engine row Satellite: has_target=true target=50.0 actual=45.0 drift=-5.0 pp drift_at_least?(0.05)=true
API min_drift=0.05 rows {name, target_weight, drift_weight, has_target}: [{"Core", "0.5", "0.05", :absent}, {"Satellite", "0.5", "-0.05", :absent}]
Overview alerts: []
Overview all-clear line: "All targets within ±5 pp — nothing needs rebalancing."
Wealth table, chip >= 5 pp [Category, Value, Actual, Target, Drift]:
  ["▸ Core", "5,500.00", "55.0%", "50.0%", "500.00 EUR"]
  ["▸ Satellite", "4,500.00", "45.0%", "50.0%", "-500.00 EUR"]
  ["Cash", "0.00", "0.0%", "—", "—"]

3 tests, 0 failures
```

The first grep prints 9 lines (2880, 2898, 2909, 2984, 2995, 5108, 5154, 5331, 5343); the second prints one web line (`portfolio_live.ex:5209`).

**Cost of leaving it.**

- In case 1 the operator's plan says "none of Legacy", 8 % of the wealth sits in it, and the Overview answers that nothing needs rebalancing; Wealth shows the stored 0 % target as "—" and no drift, although its own "≥ 5 pp" chip lists the row.
- 10 web sites decide "targeted" without `has_target` (7 for categories: `dashboard_live.ex:1193`, `portfolio_live.ex:2880`, `:2898`, `:2909`, `:5108`, `:5331`, `:5343`; 3 for cash: `:2984`, `:2995`, `:5154`); one threshold lives as a module attribute of a LiveView (`dashboard_live.ex:36`) beside the context's predicate.
- Runs on every load of `/` and of the Allocation tab for a plan with such a row.

**Proposed fix.**

The Overview's card filters with `row.has_target and Allocation.drift_at_least?(row, threshold)` or its exclusive twin, the threshold named once beside the predicate in `Allocation`; the Wealth cells, `subcategory_mismatch?/1`, `position_drift_shown?/2` and `flat_positions/2` read `row.has_target`. The cash row needs the same fact from the context (`cash_row/5` answers none today; an explicit cash target of 0 is the same case). The API's category row gains `has_target` (it is absent, as the run shows), with its contract entry and the MCP schema. Size S for the screens, M with the API field and the cash row. No ADR amendment: ADR-0023 and ADR-0040 are untouched; the predicate's owner is `Portfolixir.Portfolios.Allocation`.

**Second reading.**

- Lens: reach and decided. Refuted: no. Severity it would defend: S2.

  Not refuted.

  Reach: a typed 0 is stored by the real editor (classifications_live.ex:3064-3076, 3209-3216; target.ex:91-94; the evidence's second run went through `#soll-plan-form`). No guard sits between the engine row (`has_target: true`, allocation.ex:989) and dashboard_live.ex:1192-1195 or the dash cells (portfolio_live.ex:2898, 2909, 5108). The docs put the surfaces under one question: alerts and chips "agree on what needs attention" (product-documentation.md:2136-2138).

  Decided: nothing. The docs call 0 "a target of zero" that "is kept" (:1649) and the card "every targeted category" (:1964); dashboard_test.exs:266 says "categories that carry a target"; ADR-0030 section 4 equates 0 and absent only for hiding unheld positions. The screen predicates date from June/July, `has_target` from 2026-09-23 (798a7986): an unmigrated proxy, not a choice.

  Limits, which put it at the low end of S2: the all-clear needs the 0 % category held above 5 pp and no counterpart beyond 5 pp; the demo seeds carry no 0 % target; the API's figure is right and `GET /targets` separates the two states, so the agent half is weak. By code read (not run), the policy read (policy_findings.ex:349) reports 7 pp where the Overview says all clear: a figure contradicted between surfaces, which the ladder names as S2.

### R-014 (G1-01), S2: A stored category weight blanked in the plan editor is not deleted by "Save plan": the save answers "Plan saved", the row stays and the field fills again; on the screen a category target leaves a plan only as an explicit 0, through a two-save detour over a position, or with the whole plan, and "Copy from another view…" over an existing plan stores the union of both plans

- **Class:** dead control (a write the screen shows and does not make); rule held in the web layer
- **Stands against:** `docs/product-documentation.md:1618-1619`: "**Save plan** writes the whole `(view, classification)` plan at once."; `docs/product-documentation.md:1646-1648`: "**An empty position field means "no position target"** — never zero: clearing a stored position's field and saving deletes that target" (the category field of the same table has no such sentence); `lib/portfolixir_web/live/classifications_live.ex:3139-3140`: "the steering goes back to the category, which then has no target, as the editor shows"; `docs/product-documentation.md:1615-1616`: "prefills the editor from that source plan … Nothing is written until the plan is saved." No ADR says what a blank category field means; the only written rule is the code comment `lib/portfolixir_web/live/classifications_live.ex:3060`: "Blank inputs are skipped."
- **Locations:** `lib/portfolixir_web/live/classifications_live.ex:3059-3078` (`parse_weight_entries/1`), `:2032-2049` (`save_soll_plan/2`), `:3141-3161` (`soll_clears/4`), `:2401-2408` (`recompute_soll_sum/2`), `:3223-3232` (`parse_percent_map/1`), `:1469-1478` (the category input), `:1579-1591` (the copy picker beside an existing plan), `:2412-2454` (`copy_soll_from/2`), `:2114-2124` (`soll_cash_opts/2`); `lib/portfolixir/portfolios/targets.ex:459-473` (`edit_plan/5`), `:484-491` (`clear_categories/4`), `:596-602` (`delete_target/4`); `lib/portfolixir_web/controllers/api/v1/target_controller.ex:83` (its one caller outside the module)
- **Who meets it:** the operator on the Classifications page, section "Target plan", when removing one category's target, when moving a parent's weight down to its children, or when copying another view's plan over an existing plan. The agent does not: `DELETE /api/v1/portfolios/:portfolio_id/targets/:category_id` (`portfolixir.targets.delete`) removes the row.
- **Fix size:** S. **ADR amendment:** none on its own; one sentence in R-057 (O4-03)'s ADR-0030 amendment
- **On the later `main` (read, not run):** unchanged. None of the three cited files changed: the plan editor screen, the targets context that stores plan rows, and the targets API controller are identical on origin/main.

**What is wrong.**

1. The category field is a plain input named `weights[<category_id>]` (`lib/portfolixir_web/live/classifications_live.ex:1469-1478`). Emptied, the form posts `weights[<id>] = ""`.
2. While typing, `recompute_soll_sum/2` (`:2401-2408`) rebuilds the weights from the form with `parse_percent_map/1` (`:3223-3232`), which drops a blank. The Σ footer therefore counts the field as "no target": 100 % becomes 60 % with "Not allocated 40 %".
3. On submit, `parse_weight_entries/1` turns a blank into no entry (`:3068-3070`; the comment at `:3060`: "Blank inputs are skipped").
4. `soll_clears/4` (`:3141-3161`) builds `clear_categories` only from categories whose stored position rows were all sent back blank (`:3144-3152`). A category row without position rows can never be in it. `grep -rn "clear_categories" lib/portfolixir_web` prints one line, `:3154`.
5. `Targets.edit_plan/5` (`lib/portfolixir/portfolios/targets.ex:459-473`) receives neither an entry nor a clear for that category, writes the other rows and commits; the page answers "Plan saved" (`classifications_live.ex:2049`).
6. `load_soll/1` reads the stored plan again (`:2303-2310`): the field shows the old weight and Σ is back at 100 %.
7. Three blank fields of the one form mean three things (run 2): a blank Cash field clears the view's cash target (`:2120-2121`, `parse_percent_fraction("")` is `nil`, then `targets.ex:1003-1004` writes `nil`); a blank position field deletes the position row and, when it was the category's last, the category row that followed it (`classifications_live.ex:3144-3154`, `targets.ex:464-465`); a blank category field is ignored.
8. Moving a parent's weight down to its children is the same case (run 5). The editor supports a blank parent whose Σ rolls up from its children (`:2470-2477`, pinned by `test/portfolixir_web/live/classifications_live_test.exs:919`), and shows 90 % while the operator blanks the parent (60) and types 30 and 20 for the children. The save keeps the parent's 60: the stored plan is again 100 % at the top level, with "children Σ 50%" beside the parent.
9. "Copy from another view…" is offered beside an existing plan too (`:1579-1591`). `copy_soll_from/2` (`:2445-2453`) replaces the shown weights with the source's and leaves every other field empty; the save keeps the rows the form showed empty, so the stored plan is the union of both plans (run 3: the editor showed 100 % ✓ before the save and 140 % ✗ after it).
10. The context has the delete: `Targets.delete_target/4` (`targets.ex:596-602`), journaled per row. Outside its own module it has one caller, the API (`target_controller.ex:83`); no screen calls it.
11. What the screen has instead: typing `0`, which stores an explicit zero target (`has_target: true`, target 0; run 4, the rows R-013 (A2-03) is about); a detour of two saves for a category with an assigned security (type a position target and save, blank it and save: the category row goes with it, run 6); deleting the category itself; "Delete plan".

**Reproduction.**

Scratch test `test/audit_scratch/g1_01_test.exs` in the slot's checkout (removed after the run), modelled on `test/portfolixir_web/live/classifications_position_targets_test.exs`. Run 1 is the reader's reproduction with its assertions; runs 2 to 6 are the verifier's.

_(scratch test source and run command: in the private evidence held by the owner)_

Counts, from the repository root (read over the slot's checkout and the audit's call table):

```
grep -rn --include='*.ex' "Targets.delete_target(" lib
grep -rn "clear_categories" lib/portfolixir_web
awk -F'\t' '$0 ~ /Portfolios.Targets/ && $0 ~ /delete_target\t/' arch_calls.tsv      # the audit's call table
grep -rn -E '"weights"' test --include='*.exs' | grep -E '=> ""[ ,}]' | grep -v -E '"cash_target" => ""'
grep -rn -A4 -E '"weights" => %\{$' test --include='*.exs' | grep -E '=> ""'
grep -rn -E '"weights" =>' test --include='*.exs' | wc -l
git log --format='%h %ad %s' --date=short -S"Blank inputs are skipped" -- lib/portfolixir_web/live/classifications_live.ex
```

**Observed output.**

```
Running ExUnit with seed: 0, max_cases: 24
Excluding tags: [:browser]

T1 loaded:        bonds field=40? true  sum=100% ✓
T1 while typing:  sum=60%  not-allocated=40%
T1 submit answer: Plan saved
T1 stored rows:   [{31536, "0.6"}, {31537, "0.4"}]  (equity=31536, bonds=31537)
T1 after save:    bonds field=40? true  sum=100% ✓  remainder row? false
.T2 before: categories=[{31538, "0.5"}, {31539, "0.4"}] positions=[{31538, 25093, "0.5"}] cash=Decimal.new("0.1")
T2 submit answer: Plan saved
T2 after:  categories=[{31539, "0.4"}] positions=[] cash=nil  (equity=31538, bonds=31539)
.T3 loaded (named view):  stored=[{31541, "0.4"}] sum=40%
T3 after copy (unsaved): equity field=100? true  bonds field empty? true  sum=100% ✓
T3 submit answer: Plan saved
T3 after save: stored=[{31540, "1"}, {31541, "0.4"}] sum=140% ✗  (equity=31540, bonds=31541)
.T4 submit answer: Plan saved
T4 stored rows after typing 0: [{31542, "0.6"}, {31543, "0"}]  (equity=31542, bonds=31543)
T4 allocation row for Bonds {name, has_target, target_weight}: [{"Bonds", true, "0"}]
T4 Targets.delete_target/4 (the API's call): deleted=1 stored=[{31542, "0.6"}]
.T5 loaded:       sum=100% ✓
T5 while typing: sum=90%  not-allocated=10%
T5 submit answer: Plan saved
T5 stored rows:  [{31544, "0.6"}, {31545, "0.4"}, {31546, "0.3"}, {31547, "0.2"}]  (equity=31544, bonds=31545, world=31546, emerging=31547)
T5 after save:   equity field=60? true  sum=100% ✓  remainder row? false  children hint=children Σ 50%
T5 allocation top_level_target_sum=1
.T6 save 1 (position typed 40): [{31548, "0.6"}, {31549, "0.4"}]
T6 save 2 (position blanked):  [{31548, "0.6"}]  (equity=31548, bonds=31549)
.
Finished in 0.4 seconds (0.00s async, 0.4s sync)
6 tests, 0 failures
```

The counts:
- `Targets.delete_target(` in `lib`: 1 line, `lib/portfolixir_web/controllers/api/v1/target_controller.ex:83`. The audit's call table has the same single row for `Portfolixir.Portfolios.Targets.delete_target/4` (caller `PortfolixirWeb.Api.V1.TargetController.delete/2`, line 83).
- `clear_categories` in `lib/portfolixir_web`: 1 line, `classifications_live.ex:3154`.
- Test lines that submit a blank category weight: 0 (both greps print nothing), of 35 lines in `test/` that submit a `"weights"` map.
- `git log -S"Blank inputs are skipped"`: `9a97aa75 2026-06-21 feat(web): per-view SOLL/drift viewer with no-plan empty state on the portfolio page (#468) (#480)`.

**Cost of leaving it.**

- Every category field of every plan: one input per category row, one rule (`parse_weight_entries/1`, 1 call site) that every "Save plan" runs.
- Three figures the operator reads and the save does not store: Σ 60 % with "Not allocated 40 %" against a stored 100 % (run 1); Σ 90 % against a stored 100 % with "children Σ 50%" beside a 60 % parent (run 5); Σ 100 % ✓ after a copy against a stored 140 % ✗ (run 3). Each is followed by "Plan saved".
- One form, three meanings of an empty field (run 2): cash cleared, position row deleted, category row kept.
- 1 context function for the removal (`Targets.delete_target/4`) with 1 caller outside its module, the API; 0 on a screen.
- 0 of 35 test submits of a `"weights"` map send a blank weight, so no test pins either behaviour; the rule is as old as the first editor (9a97aa75, 2026-06-21) and predates the position rule of #481 that made "empty means no target" the form's stated meaning.
- The substitute the screen offers, `0`, produces the explicit zero rows (`has_target: true`, target 0; run 4) that R-013 (A2-03) shows drawn as dashes on Wealth and left out of the Overview's card.

**Proposed fix.**

A category row the form carried and sent back blank is deleted in the save's transaction, as a blank position is; a field the form did not carry (a category shown as "Σ positions", a disabled input of an archived version, a submit without the key) is left alone; a blank field without a stored row stays a no-op, so the blank-parent roll-up is unchanged. The smallest form is a few lines in `soll_clears/4`, which already hands `clear_categories` to `Targets.edit_plan/5`; if the save rules move into the context as R-057 (O4-03) and R-057 (A2-04) propose, this rule moves with them. One red test first (run 1 with the assertions inverted, plus run 3 for the copy), one sentence in `docs/product-documentation.md` beside the position rule. Size S (hours). No ADR amendment on its own: no ADR states the blank rule today; it is one sentence in the ADR-0030 amendment R-057 (O4-03) asks for ("what a save writes").

**Second reading.**

- Lens: reach and decided. Refuted: no. Severity it would defend: S2.

  Not refuted.
  Reach: nothing unusual is needed. The category input is a plain `weights[<id>]` field (classifications_live.ex:1469-1478); emptied it posts "", `parse_weight_entries/1` drops it (:3068-3070), `soll_clears/4` fills `clear_categories` only from cleared stored positions (:3144-3154), and `Targets.edit_plan/5` upserts the rest (targets.ex:459-473). No guard sits between; the reproduction drives the rendered form, not an internal function. The live sum (:3223-3232) counts the blank as removed, so the screen teaches the reading the save ignores. A typed 0 is no substitute on a parent: `effective_weight/3` (:2571-2583) takes it as explicit and stops the children's roll-up. The copy picker beside an existing plan dates from the first editor (9a97aa75).
  Decided: no record covers the screen's blank category field. ADR-0008:51-53 fixes only the context's upsert ("leave the rest"); the product documentation gives the blank rule for positions alone (:1646-1649) and says a save "writes the whole plan" (:1618-1619); polish list #1362 has no line; ideas, triages and N-01 to N-93 are silent.
  S2 holds (a flow that cannot be completed, a misleading answer); not S1: no stored figure is wrong. Unverified clause: "the field fills again" rests on LiveViewTest; no browser ran.

### R-015 (O4-02), S2: After a tree edit on the page the plan editor keeps the tree shape, weights and position rows it read before: Σ stays "100% ✓" after a targeted category is deleted (stored plan: 60 %), a weight typed for a category just created is not counted (the form holds 110 %, the Σ shows "100% ✓", the save stores 110 %), and a security just assigned is not offered as a position row

- **Class:** stale state (two jobs of one LiveView share the tree, one of them keeps a copy)
- **Stands against:** `docs/product-documentation.md:1620-1621`: "A live **Σ** footer sums the category weights plus the cash target, updating on input"; the page's own rule for its other derived read, `lib/portfolixir_web/live/classifications_live.ex:2160-2163`: "the category result is a statement about the current composition, so an edit that changes the tree computes it again -- a create (the result lists every category), a delete, an assignment, a move."; nothing written names the plan there, and a change needs no ADR
- **Locations:** `lib/portfolixir_web/live/classifications_live.ex:2167` (`reload_composition/1`), `:2239-2245` (`load_soll/1`), `:2346-2369` (the `soll` map), `:2401-2408` (`recompute_soll_sum/2`), `:2477-2492`, `:2501-2506`, `:1414` (the plan table's rows from `@flat`), `:1548-1558` (Σ from `@soll`), `:1647`, `:1920`, `:1933`, `:2132`, `:2139`, `:2147`, `:2152`, `:2180`, `:3448`, `:3461`
- **Who meets it:** the operator on Classifications → a custom tree, editing the tree and its target plan in one visit
- **Fix size:** S. **ADR amendment:** none
- **On the later `main` (read, not run):** unchanged. The Classifications page file has no diff between the audited commit and origin/main; the tree-edit reload still does not reload the plan editor's copy of the tree.
- **Audit lead's note:** The second reading was written against the first verification's run, whose files were lost (`architecture-review-triage-2026-11-24.md`, section 13). It names the edit form's parent select, which is the move case; the run printed below has the delete, the create and the assign case and did not run the move.

**What is wrong.**

1. `build_soll/5` copies the tree's shape into the `soll` assign: `top_level_ids` and `children_by_parent` (`lib/portfolixir_web/live/classifications_live.ex:2366-2367`), `members` (the securities each category offers as position rows, `:2354`), and the stored `weights` and `position_weights` (`:2353`, `:2355`).
2. `load_soll/1` is the only caller that rebuilds it; it has 10 call sites (`:141`, `:209`, `:1796`, `:1811`, `:1824`, `:1837`, `:2026`, `:2049`, `:2060`, `:2094`): the route, a view that is gone, and the plan's own events.
3. Every tree edit ends in `reload_composition/1` (`:2167`), which is `reload/1` plus `restart_results/1`: create (`:1647`), move (`:2180`), delete (`:3448`, `:3461`), assign and unassign (`:1920`, `:1933`, `:2132`, `:2139`, `:2147`, `:2152`). None of the 10 call sites reloads the plan.
4. The plan table's rows come from the fresh tree (`flat={@tree.flat}` at `:379`, walked at `:1414`); its Σ, ✓ and "Not allocated" row come from the stale `soll` (`:1548-1558`).
5. Delete: a category delete removes its targets in the context, the table loses the row, and `soll.weights` still holds its 40.
6. Create: `recompute_soll_sum/2` (`:2401-2408`) replaces the weights with the form's, but `put_sum/1` reduces over the stale `top_level_ids` (`:2478`, `:2501-2506`), so the new root's weight is never added.
7. Assign: `soll.members` is stale, so "Positions (n)" (`:1438-1455`, shown only where `@soll.members` has the category) does not appear for the category until the plan reloads.

**Reproduction.**

Scratch test `test/audit_scratch/o4_02_stale_plan_test.exs` (removed after the run). The delete goes through the page's own controls (the category's × and the dialog's confirm button), the create through the page's form, the weight through `#soll-plan-form`, the assignment through the event the drag-and-drop hook pushes.

_(scratch test source and run command: in the private evidence held by the owner)_

**Observed output.**

```
===== CASE 1: delete Bonds (40 %) =====
before         %{sigma: "100% ✓", remainder: nil, mismatch?: false, plan_rows: ["Equity no assigned positions", "Bonds no assigned positions", "Cash"]}
stored targets [{16, "0.6"}]  (Equity id 16)
same socket    %{sigma: "100% ✓", remainder: nil, mismatch?: false, plan_rows: ["Equity no assigned positions", "Cash"]}
fresh mount    %{sigma: "60%", remainder: "40%", mismatch?: false, plan_rows: ["Equity no assigned positions", "Cash"]}
after 1 keystroke in the plan form %{sigma: "60%", remainder: "40%", mismatch?: false, plan_rows: ["Equity no assigned positions", "Cash"]}

===== CASE 2: create Gold, type 10 =====
after create   %{sigma: "100% ✓", remainder: nil, mismatch?: false, plan_rows: ["Equity no assigned positions", "Bonds no assigned positions", "Gold", "Cash"]}
typed 60/40/10 %{sigma: "100% ✓", remainder: nil, mismatch?: false, plan_rows: ["Equity no assigned positions", "Bonds no assigned positions", "Gold no assigned positions", "Cash"]}
stored targets [{18, "0.6"}, {19, "0.4"}, {20, "0.1"}]  (Gold id 20)
after save     %{sigma: "110% ✗", remainder: nil, mismatch?: true, plan_rows: ["Equity no assigned positions", "Bonds no assigned positions", "Gold no assigned positions", "Cash"]}

===== CASE 3: assign a security to Equity =====
before assign  positions toggle present? false
stored assignment %{386 => 21}  (security 386 -> Equity 21)
same socket    positions toggle present? false
fresh mount    positions toggle present? true

3 tests, 0 failures
```

Case 1: one row (Equity 60) over "Σ 100% ✓" on the socket that deleted Bonds; a fresh mount of the same page reads "60%" and "Not allocated 40%". Case 2: the form holds 60 + 40 + 10, the Σ row reads "100% ✓" without the mismatch class, the save stores 110 % and only the reload after it shows "110% ✗".

**Cost of leaving it.**

- 10 call sites of `reload_composition/1` leave 5 keys of `soll` stale (`top_level_ids`, `children_by_parent`, `members`, `weights`, `position_weights`).
- The figure read wrongly: the plan's Σ, its ✓ and the "Not allocated" row, on the screen where the plan is written; in the create case the operator saves a plan above 100 % (an error by ADR-0040 §3) under a ✓.
- It is the coupling a split of the file must not copy: a plan editor that keeps the tree's shape in its own state has this defect by construction.

**Proposed fix.**

`reload_composition/1` also refreshes what the plan takes from the tree (`top_level_ids`, `children_by_parent`, `members`, and drops the weights of categories that are gone) without discarding typed, unsaved inputs, then `put_child_sums/1` and `put_sum/1`. In a split the plan editor receives the tree shape as an input on every render and never stores it. Size S. No ADR amendment.

**Second reading.**

- Lens: reach and decided. Refuted: no. Severity it would defend: S2.

  Not refuted. Reach: plan editor and tree share one page (classifications_live.ex:375, :434). Every tree edit ends in reload_composition/1 (:2167), whose load_show/2 (:2616-2629) assigns only the tree; soll is rebuilt only by load_soll on plan events. put_sum/1 reduces over the stored top_level_ids (:2478, :2503), so a weight typed for a category created since is dropped. No guard intervenes: the page has no handle_info or subscription, and a save accepts more than 100%. The reproduction uses the page's own controls and payloads (create form, delete dialog, the edit form's parent select at :1221, the drop hook's assign_securities). Adding a category to a planned tree and typing its weight is the ordinary way to extend a plan. Decided: nothing. Sprint 20 B6 (#1110) scopes the reload to the category result and is silent on the plan; ADR-0040, #874, #467, ideas.md and the polish list #1362 hold no line; product-documentation.md:1619 promises a live sum. Severity: S2 holds (a check mark beside a form summing to 110%, in normal use). Not S1: the stored plan and the engine's figures stay right, and a save or reload heals it. The assignment case alone would be S3.

### R-016 (G4-03), S2: A cash merge's collapse lists no flow across a view's boundary: a view's flow of the day halves (880 to 440, or 200 to 100) while the preview's `flow_changes` is empty; the rule #957 gave the depot and the security merge is missing from the cash twin

- **Class:** duplicate computation (a rule one twin lacks)
- **Stands against:** ADR-0050 §16 invariant 9, the cash invariant, `docs/decisions/0050-lifecycle-merges-under-a-reimport-contract.md:685-687`: "with collapse, they change by the collapsed rows alone, and the preview lists every flow a collapse removes or moves"; the reading #957 gave "flow" for the other two merges, `lib/portfolixir/lifecycle/merge_figures.ex:272-279`: "`:boundary_removed` — a collapsed security transfer, buy or sell with exactly one leg in view `view_id`: a flow across that view's boundary", and its user story, `test/portfolixir/lifecycle/depot_merge_test.exs:566-571`: "so that a view's time-weighted return never moves without my seeing it"; the cash merge's own comment, `lib/portfolixir/lifecycle/cash_merge.ex:700-705`: "§16 invariant 9: the external flows a collapse removes ... or moves"
- **Locations:** `lib/portfolixir/lifecycle/cash_merge.ex:706-745` (`flow_changes/4`), `:642`; `lib/portfolixir/lifecycle/merge_figures.ex:286-306`, `:336-381` (the rule the others use); `lib/portfolixir/lifecycle/depot_merge.ex:625`, `lib/portfolixir/lifecycle/security_merge.ex:1039` (its two callers); `lib/portfolixir_web/controllers/api/v1/merge_json.ex:639-650` (the cash shape, six keys, no `view_id`) against `:654-672`
- **Who meets it:** the operator on Accounts & depots, step 2 of "Merge into…" for a cash account, when the instance has a view narrower than the whole wealth; the agent on `GET /api/v1/cash_accounts/:id/merge_preview` (`outcome_by_collapse_key_equal.true.flow_changes`) and `portfolixir.cash_accounts.merge_preview`, then on `GET /api/v1/views/:id/performance`
- **Fix size:** S to M. **ADR amendment:** ADR-0050 (dated note under §16 invariant 9)
- **On the later `main` (read, not run):** still stands. The cash merge's flow list (cash_merge.ex flow_changes) and the shared rule in MergeFigures are unchanged. The one commit added dropped halving events to the security merge and its serializer; the cash payload shape is identical, moved 11 lines.
- **Audit lead's note:** The cost section says the depot merge's preview lists the change for the same collapsed pair. No depot or security merge preview was run on that pair, and none receives it: the run called the shared rule directly, and `MergeFigures.collapse_flow_effects/1` answers `boundary_removed`, -440 for the view. So no two surfaces disagree, as the second reading says; the rule is missing from the cash twin.

**What is wrong.**

1. The cash merge's `flow_changes/4` lists, per collapsed row, `:removed` when the row itself is an external flow with a cash leg on the source (`cash_merge.ex:711-723`) and `:absorbed` for a later balance anchor of the source or of a third account (`:725-741`). Nothing else.
2. A key-equal pair of a cash merge can be a buy or a sell (`cash_merge.ex:576`): two buys in one depot, one settled on the source and one on the target.
3. Where a view holds the depot's position and not the cash accounts, each buy is a flow across that view's boundary (`merge_figures.ex:353-381`). The cash guard keeps both cash accounts in the same buckets (`cash_merge.ex:322-328`), so both buys straddle the same views.
4. Collapsing the pair deletes one buy: the view's flow of that day falls by its booked value. `flow_changes` for that outcome is `[]`: a buy is not an external flow of the portfolio, and no anchor follows.
5. The same holds for a collapsed `cash_transfer` between the source and a third cash account that is in a view the pair is not in: the view's flow falls by the transfer, `flow_changes` is `[]`. (Here the preview does list the third account's balance in `other_accounts`, 200 to 100.)
6. The other path: the depot and the security merge call `MergeFigures.collapse_flow_effects/1` (`depot_merge.ex:625`, `security_merge.ex:1039`). Called on the very pair of step 2 it answers one `:boundary_removed` change of -440 for the view; the cash merge never calls it. It has no clause for a `cash_transfer` (step 5 needs one more).

**Reproduction.**

A scratch test, synthetic data, removed after the run; modelled on `test/portfolixir/lifecycle/depot_merge_test.exs` ("a collapsed buy straddling a view is a listed boundary flow at its booked value").

`test/audit_scratch/g4_03_test.exs`:

_(scratch test source and run command: in the private evidence held by the owner)_

**Observed output.**

```
G4-03a view flow on 2025-07-01 before=880 after=440; cash preview flow_changes=[]; API flow_changes=[]
G4-03a MergeFigures.collapse_flow_effects for the same pair=[{:boundary_removed, true, "-440", :booked_value}]
G4-03b view flow on 2025-07-01 before=200 after=100; cash preview flow_changes=[]; other_accounts=[{"Reserve", Decimal.new("2E+2"), Decimal.new("1E+2")}]
10 tests, 0 failures
```

(The ten tests are this lane's five scratch files run together; the tests print and do not assert the defect.)

**Cost of leaving it.**

1 function of 40 lines, 3 surfaces (the dialog, the API read, the MCP tool). Every cash merge that collapses a key-equal buy, sell or third-account transfer on an instance with a view that holds one leg of it: that view's flow of the day, and with it the view's time-weighted return from that day on, moves with nothing listed. For the same collapsed pair the depot merge's preview lists the change (-440 in view N). The API reference repeats the narrower claim for the cash preview (`docs/integration/api-and-mcp.md:1920-1925`: only `removed` and `absorbed`), and the cash payload has no `view_id` and no `flow_basis`.

**Proposed fix.**

The cash merge's collapse figures come from `MergeFigures` (R-110 (G4-01)'s first step): `collapse_flow_effects/1` already answers a buy, a sell and an absorbed leg; a collapsed `cash_transfer` with exactly one leg in a view needs one more clause, and the cash merge's `:removed` case of an external cash row moves there. The cash payload takes the twelve keys of `merge_json.ex:654-672` and the `flow_basis`; one manifest entry in the API contract; the dialog renders the shared list as it does for the other two merges. Test first: the scratch test above with the expected `boundary_removed` line of -440 and the transfer's line, red today. Size S to M; risk-tier (ADR-0036). ADR: a dated note under ADR-0050 §16 invariant 9 that a flow across a view's boundary counts for all three merges, the reading #957 took and which today is written only in code and in the #957 manifest entry.

**Second reading.**

- Lens: reach and decided. Refuted: no. Severity it would defend: S2.

  Not refuted. Reach: the run used Lifecycle.preview_cash_merge/2 and merge_cash_account/4, as the controller does (merge_controller.ex:136). The fixture is the repository's own story (cash_merge_test.exs:349, "a buy both cash accounts paid for") and ADR-0050 §8's repair case ("the pairs are the whole copy", :384); the importer books a trade's cash from the file's Gegenkonto (csv_parser.ex:726), nothing ties it to the depot's linked account, and the buckets guard (cash_merge.ex:322) only keeps S and T on one side of a view, so a collapsed trade can straddle; the scoped walk books that as flow (performance.ex:1253). Decided: nothing. #957 was scoped to depot and security merges and its body assumed the cash list already met invariant 9; contract.ex:880 says only "unchanged"; no ADR amendment, idea row, triage or N-id accepts the gap. S2 holds by the ladder ("an API answer that misleads": tools.ts:3970 promises "the external flows a collapse removes or moves") and by #957's rating, at the low end. Overstated: the cash dialog states nothing false (the "none is removed" line renders in the depot step only, merge_preview.ex:433), and collapse_flow_effects/1 never receives this pair from its real callers, so no two surfaces disagree; positions and other_accounts disclose the collapsed legs.

### R-017 (A4-02), S2: The security-merge preview's FIFO basis says the realized-gains read converts its figures "at each close date"; for a pooled trade whose sale closes a lot booked in another currency that read takes the cash the bookings moved, so the base-currency result after the merge is not the preview's after-figure converted

- **Class:** ADR drift (a stated computation basis that no longer describes the read it names); duplicate computation (two aggregations of the same closed trades into "realized", one of which knows `cash_result`)
- **Stands against:** AGENTS.md:113-116, "Every metric in (a)–(c) must state its **computation basis** in its API and MCP payload ... Review-blocking"; the basis served, `lib/portfolixir_web/controllers/api/v1/merge_json.ex:161-163`: "never converted; the realized-gains read converts them at each close date."; ADR-0015, note of 2026-10-31, `docs/decisions/0015-cross-currency-settlement-fx-rate.md:423-429`: such a trade "reads `realized_base` as the cash its bookings moved ... no rate looked up and none needed on the close date"; the story the restatement was built for, `test/portfolixir_web/controllers/api/v1/merge_fifo_restatement_test.exs:68-69`
- **Locations:** lib/portfolixir/lifecycle/merge_fifo.ex:18-22, lib/portfolixir/lifecycle/merge_fifo.ex:121-141, lib/portfolixir/portfolios/realized_gains.ex:450-463, lib/portfolixir/ledger/trade_matcher.ex:285, lib/portfolixir/ledger/trade_matcher.ex:342-353, lib/portfolixir_web/controllers/api/v1/merge_json.ex:153-169, lib/portfolixir_web/controllers/api/v1/contract.ex:1061
- **Who meets it:** the agent on `GET /api/v1/securities/:id/merge_preview` and the MCP tool `portfolixir.securities.merge_preview` (both carry `fifo_basis`); the operator only indirectly: the dialog states the trade-currency figures and makes no claim about the base currency (`lib/portfolixir_web/live/securities/merge_preview.ex:374-379`), and the realized-gains page then moves by an amount the dialog did not show
- **Fix size:** S. **ADR amendment:** ADR-0015 (a note naming the preview as a reader); ADR-0050 §9 only if the preview also states the base-currency result (then size M)
- **On the later `main` (read, not run):** still stands. Two cited files gained lines elsewhere; the basis sentence 'converts them at each close date' still stands in the payload text, the module note and the contract entry (now line 1310), and the realized-gains read is unchanged.
- **Audit lead's note:** The second reading was written against the first verification's run, whose files were lost (`architecture-review-triage-2026-11-24.md`, section 13). The one figure it cites, the 161.46 EUR computed from the basis sentence, is also in the run printed below (line 6).

**What is wrong.**

Confirmed in a narrower form than the reader's title: the preview's own figure (the trade-currency sum) is right and equals the trades read after the apply; what fails is the basis sentence, and with it the base-currency result the preview lets its reader derive.

1. Both paths start from one matcher. The preview: `SecurityMerge.outcome/2` → `MergeFifo.restatement/4` (`lib/portfolixir/lifecycle/security_merge.ex:1033`) → `MergeFifo.side/2` → `Ledger.match_trades/2` (`lib/portfolixir/lifecycle/merge_fifo.ex:121-122`, `lib/portfolixir/ledger.ex:266`). The read: `RealizedGains.report/1` → `Ledger.list_trades_for_security/2` (`lib/portfolixir/ledger.ex:223`). There is no second matcher.
2. `MergeFifo.side/2` sums `trade.realized_pnl_abs` per close year and trade currency and never reads `trade.cash_result` (`lib/portfolixir/lifecycle/merge_fifo.ex:128-132`).
3. `RealizedGains.convert_trade/2` reads `cash_result.realized` when the trade carries one in the base currency (`lib/portfolixir/portfolios/realized_gains.ex:450-452`, source `:settlement_legs`) and converts `realized_pnl_abs` at the close date only otherwise (`:454-463`, source `:close_date_rate`). The matcher sets `cash_result` on a trade whose sale closes a lot booked in another currency (`lib/portfolixir/ledger/trade_matcher.ex:285`, `:342-353`). That rule landed on 2026-10-31 (commit `4f30d6ac`, #1198); the restatement's basis sentence is of 2026-10-28 (commit `056784cd`, K11; `git log -S"converts them at each close date"` on `merge_json.ex` names that commit alone) and was not changed with it.
4. A security merge pools two queues. In the run below the survivor's sale, which closed its own franc lot before the merge (one currency, close-date conversion), closes the duplicate's older euro-booked lot afterwards and gains a `cash_result`. The preview states the year in francs (97.15 → 153.39, change 56.24) and its basis says the realized-gains read converts that at the close date, which gives 161.46 EUR. The read answers 150.90 EUR from `settlement_legs`. The euro total the app reads moves by 48.64, not by the 59.20 the preview's change converts to.
5. The same sentence stands in the module's `@moduledoc` (`lib/portfolixir/lifecycle/merge_fifo.ex:18-22`) and in the contract entry (`lib/portfolixir_web/controllers/api/v1/contract.ex:1061`: "which GET /api/v1/realized_gains then converts at each close date").
6. The pin does not reach it: the invariant-12 test for the restatement compares the preview's after-figure with `GET /api/v1/realized_gains` in a world where every booking is in EUR (`test/portfolixir_web/controllers/api/v1/merge_fifo_restatement_test.exs:44-55`, `:72-125`), where both rules agree.

**Reproduction.**

Scratch test `test/audit_scratch/a4_02_test.exs` in the slot checkout (removed afterwards), the figures of `test/portfolixir/ledger/closed_trade_currency_test.exs:872-954` with the imported lot on a duplicate security.

_(scratch test source and run command: in the private evidence held by the owner)_

**Observed output.**

```
Portfolixir.AuditScratch.A402Test [test/audit_scratch/a4_02_test.exs]
  * test the merge preview's FIFO after-figure, its basis sentence, and the realized-gains read [L#66]1 guards all passed: true
2 fifo_basis says: Amounts in each trade's or lot's currency, the security's unless a booking was priced in another, never converted; the realized-gains read converts them at each close date.
3 GET realized_gains before: realized_pnl_abs=97.15 CHF  realized_base=102.26 EUR  source=close_date_rate  summary.realized_total=102.26
4 preview year 2026 CHF: source=nil target=97.15 after=153.39 change=56.24  unchanged=false unavailable=%{"after" => 0, "source" => 0, "target" => 0}
5 GET realized_gains after:  realized_pnl_abs=153.39 CHF  realized_base=150.90 EUR  source=settlement_legs  summary.realized_total=150.90
6 the preview's after converted at the close date (1 EUR = 0.95 CHF), as fifo_basis says the read does: 161.46 EUR
7 change of the EUR total the app reads: 48.64; the preview's change at the close date: 59.20
8 GET realized_gains annual 2026 total=150.90
9 GET securities/:id/trades after: realized_pnl_abs=153.39 CHF
  * test the merge preview's FIFO after-figure, its basis sentence, and the realized-gains read (154.4ms) [L#66]

1 test, 0 failures
```
(The test prints; its one assertion is that the merge applied.)

**Cost of leaving it.**

- One false sentence in 3 places: the `fifo_basis` of the API payload (relayed by the MCP tool), the `@moduledoc` and the contract entry.
- One figure the preview cannot state: the base-currency realized result, which is what the realized-gains page, its yearly matrix (line 8: 150.90) and the Overview card read. In the run a reader who follows the basis expects 161.46 EUR for the year and reads 150.90, 6.5 % less; the change is overstated by 10.56 EUR on a 1,000 EUR lot for a one-point move of the rate.
- The preview's own figures are not wrong: line 4's 153.39 CHF is line 9's trades read, and for one-currency trades the after-figure is pinned against the realized-gains read.
- It shows only where a duplicate security in a foreign currency has a lot booked in the account's currency and the pooled sale in the security's: the "one copy imported, one booked by hand" duplicate ADR-0050's Context names, restricted to foreign-currency securities.

**Proposed fix.**

Either (a) the sentence says what the read does, in the three places: "the realized-gains read converts them at each close date, or, where a sale closes a lot booked in another currency, reads the base-currency cash its bookings moved (`realized_base_source`)". Size S. Or (b) the restatement also states the base-currency result per close year, through the rule `RealizedGains` uses: `convert_trade/2`'s choice between `cash_result` and the close-date rate moves to one function both call, owned by `Portfolios.RealizedGains` (or by the Ledger beside `cash_result`), and the invariant-12 test gains this scratch world. Size M, risk tier (a money figure, ADR-0036). (b) is what K11's story asks ("the after-figure equals GET /api/v1/realized_gains right after the apply"). Either way a note: ADR-0015's note of 2026-10-31 names the merge preview as a reader of the rule; ADR-0050 has no sentence on the FIFO restatement at all (it came from the security triage of 2026-10-12, K11), so (b) would add one under §9.

**Second reading.**

- Lens: reach and decided. Refuted: no. Severity it would defend: S2.

  Not refuted. Lens 1: the fixture is ADR-0015's own pinned walk (an imported euro-booked lot, a booking-form franc sale; ADR-0015:418-423) placed on ADR-0050's situation 5 (:82-83). Preview, merge and read ran over the API, and no guard refuses a same-currency pair. merge_json.ex:161-163 serves the clause live; realized_gains.ex:450-452 contradicts it for that class. Two corrections narrow the reach. The operator's dialog carries no such clause (merge_preview.ex:374-378 names only the currency and the queues), so only an API or MCP reader meets it. No surface serves 161.46 EUR: the evidence's own at_close computes it, while the read names its path per row (realized_base_source) and in computation_basis.realized_base. The preview's own figures and their basis are right, so AGENTS.md's basis rule is not what breaks. Lens 2: ADR-0015's note decides the read and that trade-currency figures are unchanged, not the preview's sentence; ADR-0050 has no paragraph on the restatement; F29, N-52 and N-54 are other merge-preview matters. Severity: S3 is arguable (a cross-reference, no wrong figure), but the repository's own pass graded the same staleness on the realized-gains basis S2 (#1317). S2, low end, agent-only.

### R-018, S2

Held (see the head of this file); filed with its fix.

### R-019, S2

Held (see the head of this file); filed with its fix.

### R-020 (O6-03), S2: The contract read without `since` answers the whole manifest, 241,722 bytes, more than the full profile's entire tool list is allowed to be, and step 1 of the `first_setup` prompt calls it that way as a connection check

- **Class:** ADR drift (ADR-0044 §8, the read's own user story), caused by structure (the manifest's prose is served whole)
- **Stands against:** `test/portfolixir_web/controllers/api_v1_contract_test.exs:16-18`: "As the operating agent, I want one cheap read that says what the surface offers and when it last changed, pollable with since="; `lib/portfolixir_web/controllers/api/v1/contract_controller.ex:8-10`: "so an agent that cached its tool descriptions at connect time can notice a change with one cheap poll"; `docs/decisions/0044-security-knowledge-as-an-append-only-log.md:164-165`; and the budget beside it, `docs/llms.txt:177-179` ("`full`: 164 tools, at most 228,339 bytes, about 57,000 to 66,000 tokens")
- **Locations:** `lib/portfolixir_web/controllers/api/v1/contract_controller.ex:17-21`, `:32-47`, `:49-60`; `lib/portfolixir_web/controllers/api/v1/contract.ex:46-2037`; `mcp-server/src/prompts.ts:127-128`; `mcp-server/src/tools.ts:3247-3255`, `:3464`, `:3604-3606`, `:5068-5073`, `:5078-5079`, `:6042-6054`; `mcp-server/src/server.ts:142-144`
- **Who meets it:** the agent on `portfolixir.contract.get` and `GET /api/v1/contract` whenever it has no stored date to pass, which is every first call and step 1 of the `first_setup` prompt
- **Fix size:** M. **ADR amendment:** ADR-0044 §8 for a summary default; the prompt fix alone (size S) needs none
- **On the later `main` (read, not run):** still stands. The contract controller is unchanged; the manifest gained entry 29 (about 249 lines), so the unfiltered answer grew. first_setup step 1 still calls contract.get without since; its description still omits the first-read cost; not a compact-answer tool.

**What is wrong.**

1. Without `since`, `show/2` serialises every entry (`lib/portfolixir_web/controllers/api/v1/contract_controller.ex:19-20`), each with its `summary` and its `parameters` list whole (`:53`, `:56`).
2. The manifest holds 28 entries with 43,233 bytes of `summary` and 180,707 bytes of `parameters` in 245 items (the longest 2,985 bytes) beside 11,488 bytes of endpoint and tool names. Entry 8 alone serialises to 50,297 bytes.
3. The served body is 241,722 bytes (measured through the endpoint, below). The companion holds its whole `tools/list` answer for the full profile to 228,339 bytes by a test (`mcp-server/test/schema-budget.test.ts:588`), and paid for one comma "by tightening contract.get's wording by one byte" (`:516`).
4. The companion's tool takes `since` as optional (`mcp-server/src/tools.ts:3247-3255`), leaves it out of the query when absent (`:6047`), forwards the call (`:5078-5079`), and answers the payload as indented text (`:5068`; the tool is not in `COMPACT_ANSWER_TOOLS`, `:3464`) and again as `structuredContent` (`:5072`, `mcp-server/src/server.ts:142-144`). Indented, the payload is 251,460 bytes; both forms together 493,182. `mcp-server/src/api-client.ts` puts no bound on an answer's size.
5. The `first_setup` prompt's step 1 is "Call portfolixir.contract.get. It answers the API contract's version, and that the companion reaches the API." (`mcp-server/src/prompts.ts:127-128`): no `since`, and a fresh agent has no `last_changed_at` to pass. The same check exists as `portfolixir.version`, whose answer is 565 bytes; it is a read in every profile since contract entry 28.
6. The tool's description tells the agent to `Poll it with since=<the last_changed_at you stored>` (`mcp-server/src/tools.ts:3606`) and says nothing about what the first read costs.
7. The body grows with every entry: the newest alone is 14,835 bytes, entry 25 is 15,114; `since=<the day before the newest entry>` answers 15,332 bytes.

**Reproduction.**

Scratch test `test/audit_scratch/o6_03_test.exs` (removed after the run), run in a test slot.

_(scratch test source and run command: in the private evidence held by the owner)_

**Observed output.**

```
O6-03 unfiltered body bytes: 241722
O6-03 the same payload with two-space indentation (the companion's text form): 251460
O6-03 indented text plus the payload again as structuredContent: 493182
O6-03 since=last_changed_at body bytes: 498
O6-03 since=the day before (the newest entry only) body bytes: 15332
O6-03 GET /api/v1/version body bytes: 565
O6-03 entries: 28
O6-03 summary bytes: 43233; parameters items: 245, bytes: 180707, longest item: 2985; endpoint and tool name bytes: 11488
O6-03 largest entries {version, bytes}: [{8, 50297}, {18, 18784}, {17, 17255}, {25, 15114}, {28, 14835}, {19, 13807}]
O6-03 tokens by the companion's rule (bytes/4 .. bytes/3.5), served body: 60431 .. 69064
O6-03 tokens, indented text form: 62865 .. 71846
O6-03 full-profile tools/list ceiling (mcp-server/test/schema-budget.test.ts:588): 228339

  1) test O6-03 size of the unfiltered contract read (PortfolixirWeb.AuditScratch.O603Test)
     test/audit_scratch/o6_03_test.exs:12
     Assertion with < failed
     code:  assert byte_size(full) < 50000
     left:  241722
     right: 50000
```

**Cost of leaving it.**

- One call costs 241,722 bytes on the wire and 251,460 bytes as the companion's text: 60,000 to 72,000 tokens by the companion's own rule of thumb (`mcp-server/test/support/schema-budget.ts:823-829`), and up to twice that in a client that reads both the text and the structured form. That is more than connecting with every tool schema of the full profile (at most 228,339 bytes), which the project counts to the byte.
- It is paid at the first step of the first setup, before the agent has read a single account, and by any agent that calls the read without a stored date. A client that caps a tool result will cut or refuse the answer; what a given client does was not run here.
- It grows with every entry: the eight newest (versions 21 to 28, 2026-11-02 to 2026-11-09) serialise to 10,678, 8,351, 8,561, 9,024, 15,114, 3,578, 3,390 and 14,835 bytes, 73,531 in eight days.
- The 485-fold difference between the two forms (241,722 against 498 bytes) is stated nowhere an agent reads.

**Proposed fix.**

Two steps. Size S: `first_setup` step 1 calls `portfolixir.version` (565 bytes, in every profile), and the tool description of `portfolixir.contract.get` says that a read without `since` answers the whole manifest and what to pass on a first read. Size M: the read answers a summary form by default (`version`, `last_changed_at`, the totals, and per entry `version`, `date`, the `endpoints` and `tools` lists and the first sentence of `summary`), with the full `summary` and `parameters` only under `since=` or an explicit `detail=full`; a contract entry, the tool description and the API reference follow. The M step changes what #752's acceptance line promises ("the entries newest first, each naming endpoints, tools and parameters", `test/portfolixir_web/controllers/api_v1_contract_test.exs:23-24`), so it needs an amendment of ADR-0044 §8, which today says nothing about the read's size. The cause, entries that carry the behaviour in full instead of one sentence, is R-150 (O6-04).

**Second reading.**

- Lens: reach and decided. Refuted: no. Severity it would defend: S2.

  Not refuted. Reach holds: README.md:363 and connect-an-agent.md:151 send every new operator's agent to first_setup, whose step 1 (prompts.ts:128) calls the read without since; neither contract_controller.ex:17-21 nor the companion (tools.ts:5068-5073) bounds the answer. Decided: nothing found. ADR-0044 section 8, the idea list, the three triages and N-01 to N-93 are silent on the answer's size; only ADR-0056's news reads carry an answer budget.

  What narrows it: the S2 rests on the prompt step alone. That the read without since answers every entry is specified (api_v1_contract_test.exs:23-24; api-and-mcp.md:4484-4489), and the 'cheap' of contract_controller.ex:8-10 is the poll, which holds at 498 bytes. The 228,339 ceiling counts tools/list only (docs/llms.txt), so no recorded budget is broken; the endpoint's size is the cost face of R-150 (O6-04) (S3). No MCP client was run, and four recorded first_setup runs completed step 1 at contract versions 10 to 17 (sprint-status.yaml:2216-2218, 2579-2582, 2893-2894, 3118), at roughly a third to half of today's size by source share, so no blocked flow is shown.

  I still defend S2, at its lower edge: the documented first step spends more context than the whole full-profile connection the project counts to the byte, and a 565-byte check exists since entry 28.

### R-021 (O1-01), S2: For a security whose newest close is older than a year the Overview's "1Y" tile reads "0.0%" and the Chart tab's "Momentum · 12 months" reads "not computable"; the list's 1M and 1Y columns print the same "0.0%" beside the stale marker

- **Class:** duplicate computation (two paths, different answers)
- **Stands against:** `lib/portfolixir/engines/price_metrics.ex:269-271`: "a series that stops before the period even begins resolves `opening` to the same point as `latest`, and the honest answer is "no figure", not "0 % over zero days"."; `lib/portfolixir/engines/price_metrics.ex:45-49`: "**A metric refuses in both directions.**"; `docs/decisions/0047-derived-metrics-per-security-and-per-view.md:312-315`: "**`SecurityWithMetrics` is not replaced.** The list's four figures stay the list's; the new read is the windowed one behind the detail surface, and the two agree on the display basis" (the ADR promises agreement on the display basis only; it does not decide the coverage rule, and the Overview tile puts a list figure on the detail surface)
- **Locations:** `lib/portfolixir/catalog/quotes.ex:723-724`, `lib/portfolixir/catalog/quotes.ex:741-768`, `lib/portfolixir/catalog/quotes.ex:807-821`, `lib/portfolixir/catalog/quotes.ex:673-688`, `lib/portfolixir/engines/price_metrics.ex:266-290`, `lib/portfolixir_web/live/securities_live.ex:1844-1850`, `lib/portfolixir_web/live/securities_live.ex:6694-6698`, `lib/portfolixir_web/live/securities_live.ex:4172-4178`, `lib/portfolixir_web/live/securities_live.ex:4823-4827`, `lib/portfolixir/catalog/security_fields.ex:116-127`
- **Who meets it:** the operator on Securities → a security → Overview (the default tab) against the same pane's Chart tab, and in the securities list with the optional "1M performance" or "1Y performance" column shown; the agent only as a sort key (`GET /api/v1/securities?sort=performance_1y` ranks a frozen security at 0), the figure itself is not serialised
- **Fix size:** S. **ADR amendment:** ADR-0047
- **On the later `main` (read, not run):** still stands. Quotes module, metrics engine and field registry are unchanged. The securities page changed in 15 commits; the 1Y tile, its attach_metrics read, the Momentum cell and the stale day-change guard are identical, only moved.
- **Audit lead's note:** S2 on one ground: the price tile of the same strip carries "stale" and the close's date, which dates the input of the 0.0 %. The verifier graded it S1 by the ladder's letter; a reader who does not accept the marker will too.

**What is wrong.**

1. `Quotes.attach_metrics/1` sets `cutoff_1m = Date.add(today, -30)` and `cutoff_1y = Date.add(today, -365)` (`lib/portfolixir/catalog/quotes.ex:723-724`), reads the newest close of all as `latest` (`:741-747`) and the newest close on or before each cutoff as `one_m` and `one_y` (`:755-768`), and answers `performance_1m: ratio(latest_close, m_close)` and `performance_1y: ratio(latest_close, y_close)` (`:819-820`). Nothing checks that `latest` lies after the cutoff.
2. For a security whose newest close is older than the cutoff both subqueries return the same row, so the ratio is exactly 0.
3. The page reads this for the selected security (`lib/portfolixir_web/live/securities_live.ex:6694-6698`) and the Overview prints it as "1Y … price only" (`:1844-1850`).
4. The same pane's Chart tab prints the engine's `momentum["12m"]` (`:4172-4178`), which is refused in exactly this case: `reaches_forward?` is false when `latest.date` is not after the period's start (`lib/portfolixir/engines/price_metrics.ex:272-281`).
5. The tile to the left does blank the day change computed from a stale close (`lib/portfolixir_web/live/securities_live.ex:1834-1840`), and the list does it for its two day-change cells through `stale_change?/2`, whose guard names `[:day_change_abs, :day_change_pct]` only (`:4823-4827`). The `performance_1m` and `performance_1y` columns (`lib/portfolixir/catalog/security_fields.ex:116-127`, not shown by default) have no such guard.
6. A third implementation, `Quotes.performance/2` (`lib/portfolixir/catalog/quotes.ex:673-688`), has the same rule and no caller under `lib/`; it answers 0 for the same fixture.
7. The start anchors differ as well: today minus 365 days (`quotes.ex:724`) against `Date.shift(as_of, month: -12)` (`price_metrics.ex:267`), one day apart whenever the span holds a 29 February. Read, not run.

**Reproduction.**

Two scratch tests, run in the slot and removed afterwards: `test/audit_scratch/o1_01_one_year_test.exs` and `test/audit_scratch/o1_01b_list_test.exs`.

_(scratch test sources and run commands: in the private evidence held by the owner)_

Also: `grep -rn 'Quotes.performance(' lib` (no output) and `grep -rn 'performance_1y\|performance_1m' lib mcp-server/src`.

**Observed output.**

```
PATH1 attach_metrics performance_1y=Decimal.new("0") performance_1m=Decimal.new("0") latest_price_date=2025-10-07 today=2026-11-11
PATH3 Quotes.performance(id, 365)=Decimal.new("0")
PATH2 momentum[12m]=%{value: nil, required: 2, window: %{end_date: ~D[2026-11-11], start_date: ~D[2025-11-11]}, insufficient_data: true, observations: 2}
OVERVIEW 1Y tile text: 1Y 0.0% price only
OVERVIEW 1Y tile html: <div class="overview-metric" data-role="overview-1y"><dt>1Y</dt><dd class="is-flat"> 0.0% <small class="overview-metric__sub">price only</small></dd></div>
OVERVIEW day-change tile text: Day change—
CHART cell: Momentumnot computable12 months·2025-11-11 – 2026-11-11 · 2 observations
LIST rows: 1
LIST row: F Frozen Co FRZ EUR ETF50.00stale · 2025-10-07 —
STALE40 performance_1m=Decimal.new("0") performance_1y=nil
STALE40 momentum[3m]=%{value: nil, required: 2, window: %{end_date: ~D[2026-11-11], start_date: ~D[2026-08-11]}, insufficient_data: true, observations: 1}
2 tests, 0 failures
```

```
HEAD: ["", "Name ↑", "Latest price", "Day change %", "1M performance", "1Y performance"]
ROW: ["", "F Frozen Co", "50.00stale · 2025-10-07", "—", "0.0%", "0.0%"]
ROW: ["", "L Live Co", "50.00", "+11.1%", "+11.1%", "+25.0%"]
ROW: ["", "S Stale Co", "50.00stale · 2026-10-02", "—", "0.0%", ""]
1 test, 0 failures
```

The fixture's price moved from 40 to 50 before the feed stopped; both surfaces read the same two closes. The Overview says "1Y 0.0%", the Chart tab of the same pane says "Momentum not computable". In the list the day change of the stale rows is a dash and the 1M and 1Y cells beside it are "0.0%".

`grep -rn 'performance_1y\|performance_1m' lib mcp-server/src` names the tile (`securities_live.ex:1846-1847`), the two computations (`quotes.ex:819-820`), the field registry (`security_fields.ex:116`, `:122`), the struct and the sort-key sentence of the contract (`lib/portfolixir_web/controllers/api/v1/contract.ex:1007`); nothing under `json.ex` and nothing in `mcp-server/src`.

**Cost of leaving it.**

- Three implementations of one figure: `attach_metrics/1`, the engine's `momentum/4`, and `Quotes.performance/2` (16 lines, no caller under `lib/`, two calls in `test/portfolixir/catalog/quotes_test.exs`).
- The operator reads "1Y 0.0%" on the default tab of every security whose feed stopped more than a year ago (a delisted or frozen holding, the case idea row I25 names), and "0.0%" in the list's 1M column for every security stale for more than 30 days once that column is shown (the stale threshold is 7 days). The columns are off by default; the Overview tile is always shown.
- Idea row I32 (top and flop positions per period) plans to rank by `performance_1m` and `performance_1y`; a frozen security would rank at 0.0% instead of dropping out. `sort=performance_1y` on the API already ranks it so.

**Proposed fix.**

One coverage rule for the trailing price return, owned by the engine's rule (`reaches_forward?`): `Quotes.attach_metrics/1` answers `nil` for `performance_1m` and `performance_1y` when the newest close does not lie after the cutoff (the SQL already returns `latest_date`), so the tile, the list cells and the API sort all read "no figure". Delete `Quotes.performance/2` and its two tests. Size S. It needs an amendment of ADR-0047 (the consequence "`SecurityWithMetrics` is not replaced": name the coverage rule the list's figures follow and which figure the detail's Overview shows); analytics money math, so risk tier (ADR-0036).

**Second reading.**

- Lens: decided (is it already decided or tracked?). Refuted: no. Severity it would defend: S2.

  Not refuted: no record decides or tracks the 0.0%.

  Checked and found nothing that covers it:
  - ADR-0047:312-315 keeps `SecurityWithMetrics` beside the windowed read; it is silent on a series that stops before the cutoff.
  - Issue #789 scoped stale suppression to the day change (`securities_live.ex:4803-4808`, `:4821-4825`).
  - Idea rows I25 and I32 and triage 2026-11-07 B7/B9 name the frozen security and the consumer, not the rule.
  - The `SecurityWithMetrics` moduledoc lists only the too-young case as nil; `Quotes.performance/2`'s doc (`quotes.ex:667-672`) does not state the stale case.
  - The API reference (`api-and-mcp.md:442-446`) documents the sort only.
  - No test pins 0 for a stale series; no N-id matches.
  - The tracker (searched read-only) has no issue, and polish list #1365 has no line.

  The project's own Sprint 13 review fixed the identical symptom in the engine as a defect (commit b3698cd9; `price_metrics.ex:269-271`), so "intended" is not arguable.

  Severity: I would defend S2, on three grounds.
  - The repository ladder files "a figure contradicted between two surfaces" under S2 (`sprint-workflow.md:116-118`).
  - The Chart tab does not answer a different figure; it refuses. ADR-0047 makes the two reads separate figures by decision, so this is one misleading answer, not two competing figures.
  - Reach is narrow: display only, nothing stored, not serialised to the agent (a sort key only), and it needs a newest close older than 365 days, with the stale marker and its date in the adjacent tile.

  The S1 case rests on the engine's own comment calling a zero-day 0 % not honest.

- Lens: reach (can the operator or the agent get there?). Refuted: no. Severity it would defend: S2.

  Reach holds; I could not refute it. The reproduction wrote closes through `Quotes.upsert_many` (the real writer, test/support/fixtures/world_fixtures.ex:262-267) and rendered the real LiveView. No guard sits between `attach_metrics` (lib/portfolixir/catalog/quotes.ex:819-820) and the tile (lib/portfolixir_web/live/securities_live.ex:1844-1850). The state is produced by design: the full sync skips retired securities and manual feeds (lib/portfolixir/catalog/quote_sync.ex:203-209), and idea row I25 records a held, delisted security with a frozen quote. The documentation calls the tile "the one-year price return" (docs/product-documentation.md:4403-4404), so it is the same question as 12-month momentum.

  The severity does not hold; I would defend S2.
  - The repository's ladder names "a figure contradicted between two surfaces" as S2 (docs/development/sprint-workflow.md:116-118).
  - The Chart tab answers a refusal, not a second figure, so the audit's S1 clause "two paths that answer DIFFERENT figures" is not met literally.
  - The project classed the identical symptom in the engine under "Edge cases", below "Blocking" and "Correctness" (commit b3698cd9, 2026-09-19).
  - The close's date is printed two tiles to the left, as a stale marker or in parentheses for a retired security, and the day change is blanked (securities_live.ex:1810-1840).
  - Nothing is stored and no total reads it. The figure is not serialised by the API or MCP (no match in json.ex or mcp-server/src); only the sort order is exposed.
  - The list's 1M and 1Y columns are off by default (lib/portfolixir/catalog/security_fields.ex:116-127).

  ADR-0047:312-315 keeps both paths but does not decide the coverage rule, so it is not a decided matter.

The verifier graded this S1. The second reading defends S2, with the reasons above; the audit lead follows it.

### R-022 (G2-01), S2: For a benchmark whose stored history starts inside the shown period, the Wealth chart's tooltip and the table's benchmark column print the anchored level `(1 + the portfolio's return up to the benchmark's first close) x (1 + r) - 1` under the benchmark's bare name, beside the card's and the API's `r`: "+15.5%" against "+10.0%" from one fixture

- **Class:** duplicate computation (a figure derived in the LiveView, another answer than the context's on the same page)
- **Stands against:** `lib/portfolixir_web/live/portfolio_live.ex:4225-4226`, the tooltip's own comment: "The crosshair tooltip names each benchmark's bought-once return on the hovered day, after the portfolio's own pair (ADR-0046 §4)."; `docs/decisions/0046-benchmark-comparison.md:71-72`: "**Bought once** — the benchmark rebased to the period start, drawn next to the portfolio's cumulative TTWROR on the same chart."; `lib/portfolixir/portfolios/performance/benchmark.ex:21-23`: "**bought once** — the benchmark rebased to the close before the window (or to the window's first day when the window opens with no value)". Nothing written decides the printed figure of a late benchmark: `grep -c -i anchor docs/decisions/0046-benchmark-comparison.md` prints 0; the one built story is about the drawn line only (`test/portfolixir_web/live/portfolio_benchmark_live_test.exs:275-277`: "the overlay to start from my own chain's level on that day"). A change would amend ADR-0046.
- **Locations:** `lib/portfolixir_web/live/portfolio_live.ex:4536-4556` (`anchored_returns/2`), `:4514-4532` (`benchmark_overlays/3`), `:2454` (its one caller), `:4084-4088` and `:4183-4184` (the two lookups read `p.fraction`), `:4227-4233` (`overlay_labels/2`, the tooltip), `:4153-4155`, `:4167-4169`, `:4492-4497` (the table column, `overlay_cell/2`), `:1989-1992` (the card, `bought_once.benchmark_return`); `lib/portfolixir/portfolios/performance/benchmark.ex:318-334` (`coverage/2`), `:365-372` (the series), `:397` (`benchmark_return`); `lib/portfolixir_web/controllers/api/v1/json.ex:2099`, `:2110`; `lib/portfolixir_web/layout_view.ex:998`, `:1060` (the hook prints `points[i][1]` as sent)
- **Who meets it:** the operator on Wealth (Holdings, the TTWROR chart with a benchmark selected whose stored quotes begin inside the shown period): hovering the chart, and in "Data as table". The agent does not: `GET /api/v1/portfolios/:id/performance/benchmark` and the view routes serve the context's series.
- **Fix size:** S. **ADR amendment:** ADR-0046
- **On the later `main` (read, not run):** still stands. The Wealth page's anchored_returns (the anchored overlay level), its tooltip and table readers and the context's coverage rule are unchanged. a52ce51f lets any quoted security be a benchmark, which widens who can meet the defect.
- **Audit lead's note:** S2: the printed number is the plotted level of a line whose anchoring is a built story, and both figures of the tooltip carry the same factor, so who is ahead reads the same. What is wrong is the bare benchmark name over a figure that is not the benchmark's own return. The verifier graded it S1.
- **Audit lead's note:** The "Stands against" bullet is too strong for the table, as the second reading (decided) says. The built story's acceptance criterion reads "The overlay is drawn, with its legend entry and its table column" (`test/portfolixir_web/live/portfolio_benchmark_live_test.exs:271-282`), and the column's comment says "as plotted (UX-DR10)" (`lib/portfolixir_web/live/portfolio_live.ex:4151-4152`). So the table's anchored cell is decided in part; the tooltip's figure and the bare benchmark name are not.

**What is wrong.**

1. When the benchmark has no price on the day the comparison wants to rebase to, `coverage/2` shifts the window: the rebase day is the benchmark's first priced day and `window.start_date` the day after (`lib/portfolixir/portfolios/performance/benchmark.ex:318-334`).
2. Path one, the context: `cumulative_return = price(day) / price(rebase day) - 1` (`benchmark.ex:365-372`), 0 on the first covered day while the close is carried; `bought_once.benchmark_return` is the series' last point (`:397`). The API serialises exactly these (`lib/portfolixir_web/controllers/api/v1/json.ex:2099`, `:2110`), and the card prints `benchmark_return` (`lib/portfolixir_web/live/portfolio_live.ex:1989-1992`).
3. Path two, the page: `anchored_returns/2` takes `anchor_day = window.start_date - 1` (the rebase day), reads the portfolio's cumulative TTWROR of the *requested* period on that day and builds `fraction = (1 + portfolio cumulative) x (1 + cumulative_return) - 1` (`portfolio_live.ex:4538-4548`). The comment above it describes the drawn line ("the overlay starts where the portfolio then stood instead of pretending both began at zero", `:4508-4513`).
4. `fraction` is not only the line's y value (`:4553`). The same map of points is turned into two lookups by date (`:4084-4088`, `:4183-4184`) that feed the tooltip (`:4204` -> `:4227-4233`: `" · <name> +x%"`) and the table's benchmark column (`:4167-4168` -> `:4492-4497`), both under the benchmark's bare name (`:4526`, `:4153-4155`). The chart hook prints the string as sent (`lib/portfolixir_web/layout_view.ex:998`, `:1060`).
5. While the benchmark covers the whole window the series has no point on `anchor_day`, the lookup misses and the anchor is 1 (`portfolio_live.ex:4542-4545`), so the three agree. The suite's one late-benchmark fixture (`test/portfolixir_web/live/portfolio_benchmark_live_test.exs:32`, `:288-289`) has a portfolio that stands at 0 on the rebase day, so the anchor is 1 there as well (control run below): no test reaches a case in which the two paths differ.

**Reproduction.**

A scratch test, saved as `test/audit_scratch/g2_01_test.exs` in the slot's checkout (removed afterwards), modelled on `test/portfolixir_web/live/portfolio_benchmark_live_test.exs`. The holding rises 5 % before the benchmark's first quote; the benchmark then makes 10 %.

_(scratch test source and run command: in the private evidence held by the owner)_

Control: the same file with the holding's quotes as the suite's own late-benchmark fixture has them (`[{start, "100"}, {Date.add(today, -1), "120"}]`, the portfolio flat until the benchmark starts), saved as `test/audit_scratch/g2_01c_test.exs` and run the same way.

Counts: `grep -rn "anchored_returns\|overlay_labels\|overlay_cell\|overlay_lookups" lib test` and `grep -rn "perf-summary-table" test`.

**Observed output.**

```
CONTEXT rebase_day=today-15 window.start=today-14
CONTEXT first point today-14 cumulative_return=0.000000
CONTEXT last point today0 cumulative_return=0.100000
CONTEXT bought_once.benchmark_return=0.100000 portfolio_ttwror=0.122581
PORTFOLIO cumulative_ttwror on rebase day=0.050000 end=0.178710
API benchmark_return=0.1
API series first=%{"cumulative_return" => "0", "date" => "2026-11-02"}
API series last=%{"cumulative_return" => "0.1", "date" => "2026-11-16"}
CARD bought once: +12.3% vs +10.0%
TOOLTIP today-15: "+5.0% · 1,050.00 EUR"
TOOLTIP today-14: "+5.0% · 1,050.00 EUR · Late Bench +5.0%"
TOOLTIP today-13: "+5.0% · 1,050.00 EUR · Late Bench +5.0%"
TOOLTIP today-1: "+17.9% · 1,740.00 EUR · Late Bench +15.5%"
TOOLTIP today0: "+17.9% · 1,740.00 EUR · Late Bench +15.5%"
TABLE head: ["Month", "Start value (EUR)", "End value (EUR)", "TTWROR", "Net flows (EUR)", "Late Bench"]
TABLE row (label withheld): ttwror=+5.0% benchmark=—
TABLE row (label withheld): ttwror=+12.3% benchmark=+15.5%
LEGEND Portfolio (TTWROR) Late Bench · bought once
1 test, 0 failures
```
One fixture, one benchmark, one day: the context, the API and the card say 10.0 %; the tooltip and the table say 15.5 % (1.05 x 1.10 - 1). On the benchmark's first covered day the API says 0 and the tooltip "+5.0%", which is the portfolio's own return.

Control (the portfolio flat until the benchmark's first quote, the suite's fixture):
```
CONTEXT bought_once.benchmark_return=0.100000 portfolio_ttwror=0.133333
PORTFOLIO cumulative_ttwror on rebase day=0.000000 end=0.133333
CARD bought once: +13.3% vs +10.0%
TOOLTIP today-14: "0.0% · 1,000.00 EUR · Late Bench 0.0%"
TOOLTIP today0: "+13.3% · 1,700.00 EUR · Late Bench +10.0%"
TABLE row (label withheld): ttwror=0.0% benchmark=—
TABLE row (label withheld): ttwror=+13.3% benchmark=+10.0%
```

Counts: `anchored_returns` is named on three lines, all in `portfolio_live.ex` (`:4518`, `:4536`, `:4538`); no test names it, `overlay_labels/2` or `overlay_cell/2`. `perf-summary-table` is named in the benchmark test on four lines (`:87`, `:88`, `:303` assert the column's header, `:189` refutes it); none reads a cell of the column.

**Cost of leaving it.**

- 21 lines (`portfolio_live.ex:4536-4556`) feed three outputs: the drawn line, the tooltip, the table column. Two of the three print a number.
- The printed figure differs from the benchmark's return by `(anchor - 1) x (1 + r)`, where `anchor - 1` is the portfolio's own cumulative return up to the benchmark's first priced day: 5.5 points in the run; a portfolio at +60 % when a benchmark starts that then makes +40 % reads "+124.0%" in the tooltip and "+40.0%" on the card. On the benchmark's first covered day the tooltip prints the portfolio's return where the benchmark's is 0.
- The direction of the comparison is not turned over (both sides carry the same factor), so "who is ahead" reads the same in the tooltip as on the card; the benchmark's own figure is what is misstated.
- 0 tests assert a printed benchmark figure; the one late-benchmark fixture has the anchor at 1.
- Met at the default period (1Y) only by a benchmark with less than a year of stored quotes; at Max, 5Y and 3Y by every benchmark security whose stored history is shorter than the portfolio's.

**Proposed fix.**

The context owns the figure. The tooltip and the table print the comparison's own `cumulative_return` for the day (the figure the API serves), and the line keeps its drawn level; or, if the anchored level is the figure wanted, `Benchmark` returns it as a named series with its basis (so the API and MCP read it too) and the tooltip names it as a level, not as the benchmark's return. Either way the late-benchmark test gets a fixture in which the portfolio has moved before the benchmark's first quote, and one assertion on a printed figure. Size S (hours). Needs an amendment of ADR-0046 (§2 says "rebased to the period start"; how a late benchmark is drawn, and which figure is printed beside it, is written nowhere), and a board first, since the words on the Wealth chart change.

**Second reading.**

- Lens: reach (can the operator or the agent get there?). Refuted: no. Severity it would defend: S2.

  Reach holds; I could not refute it. No guard sits between coverage/2's window shift (benchmark.ex:318-334) and anchored_returns (portfolio_live.ex:4536-4556). The chart opens in TTWROR mode (:640-641), so the overlay is on by default. The sync stores a security's whole listed history (quote_sync/yahoo.ex:77), so any benchmark younger than the shown window triggers it. The repository's own demo data does at period max (uat-sprint11-2026-09-15/walkthrough.md:26-28). The reproduction rendered the real page from ordinary fixtures, not an internal call. The Wealth polish list (#1366) and ideas.md carry no line on it.

  S1 does not hold: the two surfaces answer for different windows, not one question. The card's pair is over the covered window on both sides (benchmark.ex:397-398, portfolio_live.ex:1989-1992). The tooltip's portfolio figure is the requested period's cumulative TTWROR (:4203). In the evidence run the portfolio itself reads +12.3% on the card and +17.9% in the tooltip, by the same 1.05 factor as the benchmark's +10.0% and +15.5%. The ratio is identical (1.1787/1.155 = 1.1226/1.10), so no comparison is misanswered. The bare r beside +17.9% would overstate the gap. The table comment says "as plotted" (:4152). Nothing stored or served to the agent is wrong.

  It stays a defect at S2, the ladder's "figure contradicted between two surfaces" (sprint-workflow.md:116-118). The code's own comment (:4225-4226) and the walkthrough (:47) call the tooltip figure the "bought-once return", and it is printed under the bare name with no basis. On the first covered day it shows the portfolio's +5.0% as the benchmark's.

- Lens: decided (is it already decided or tracked?). Refuted: no. Severity it would defend: S2.

  Not refuted; S1 does not hold, S2 does.

  Searched for a decision: docs/decisions/0046-benchmark-comparison.md (§2 :71-72, both amendments) never mentions an anchor or a late benchmark; ideas.md rows I17, I18, F8 and F30 touch benchmarks, none this; the security triages and the security lens have no entry on the overlay; docs/product-documentation.md:2430-2432 and docs/integration/api-and-mcp.md:2953-2956 say only "rebased".

  Decided in part: the anchored line with its table column is a built story (portfolio_benchmark_live_test.exs:271-282), the column's comment says "as plotted (UX-DR10)" (portfolio_live.ex:4151-4152), and the Sprint 11 retrospective names both (:101-103, :125). So the verifier's "nothing written decides the printed figure" is too strong for the table. For the tooltip the records stand against the behaviour: portfolio_live.ex:4225-4226 and uat-sprint11-2026-09-15/walkthrough.md:47 both say "bought-once return". The label is undecided, so the finding stands.

  Severity: this is not one question answered twice. The card's pair runs over the covered window, the tooltip's pair on the period's chain. In the evidence's own output the portfolio's figure differs the same way (+12.3% against +17.9%), and both pairs carry the same ratio (1.1226/1.10 = 1.1787/1.155 = 1.0205). No derivation is wrong and nothing is stored; a deliberately drawn level is printed without its basis under the benchmark's name. That is the ladder's S2, "a figure contradicted between two surfaces" (docs/development/sprint-workflow.md:116-118), display only, as the evidence itself concedes.

The verifier graded this S1. The second reading defends S2, with the reasons above; the audit lead follows it.

### R-023 (G2-02), S2: The performance table prints each row's own slice TTWROR beside the benchmark's cumulative return since the period's start, under the benchmark's bare name and a line that says "return ... per period"; with the benchmark as the portfolio's only holding, the last row reads "+10.0%" against "+21.0%"

- **Class:** duplicate computation (two columns of one row on two bases, both derived in the LiveView); missing pin
- **Stands against:** `lib/portfolixir_web/live/portfolio_live.ex:4131`, the table's stated purpose: "Start/end value, return and flows per period — the chart, summarised."; `:4121-4124`: "one row per year — per month for short periods — with start/end value, the slice's TTWROR and net external flows." The column's basis is stated in a code comment only (`:4151-4152`: "the benchmark's cumulative return at the slice's end, as plotted (UX-DR10)"); the page's head for it is the benchmark's name alone (`:4153-4155`) beside the head "TTWROR" (`:4147`). Nothing else is written: ADR-0046, the Sprint 11 plan and the design language name no basis for the column. No ADR to amend.
- **Locations:** `lib/portfolixir_web/live/portfolio_live.ex:4147`, `:4153-4155`, `:4163-4169`, `:4492-4497` (`overlay_cell/2` reads the plotted fraction at `row.end_date`), `:5911-5935` (`table_summary/1`), `:5949-5957` (`slice_ttwror/2`: `(1 + cum_end) / (1 + cum_start) - 1`), `:1989-1992` (the card's like-for-like pair)
- **Who meets it:** the operator on Wealth (Holdings, the TTWROR chart, a benchmark selected, "Data as table" opened), in every row after the first. Not the agent: neither cell is in a payload.
- **Fix size:** S. **ADR amendment:** none
- **On the later `main` (read, not run):** still stands. The Wealth page file changed only in the benchmark picker. The table's heads, its purpose line, overlay_cell (prints the plotted cumulative point) and slice_ttwror (the row's own return) are identical on origin/main.

**What is wrong.**

1. A row's "TTWROR" is the slice's own return, chained out of the cumulative series: `slice_ttwror(start_cum, chunk_last.cumulative_ttwror)` (`lib/portfolixir_web/live/portfolio_live.ex:5930`, `:5949-5957`), since 2026-08-14 (`37f28f54`, #564).
2. The benchmark column arrived a month later (`9f3738bb`, 2026-09-15) and reads the overlay's plotted point on the row's last day (`:4167-4168`, `:4492-4497`): the benchmark's cumulative return since the period's start (for a late benchmark the anchored level of R-022 (G2-01)).
3. So from the second row on, the two percent columns of one row are on different bases. The page says neither: the heads are "TTWROR" and the benchmark's name (`:4147`, `:4153-4155`), and the line above the table says "return and flows per period" (`:4131`).
4. The card above the chart compares like with like (`bought_once.portfolio_ttwror` against `bought_once.benchmark_return`, `:1989-1992`), and so does the chart (two cumulative lines). The table is the one place that does not.

**Reproduction.**

A scratch test, saved as `test/audit_scratch/g2_02_test.exs` in the slot's checkout (removed afterwards). The benchmark is the portfolio's only holding and no cash is left, so the portfolio's return and the benchmark's are one series on every day.

_(scratch test source and run command: in the private evidence held by the owner)_

Counts: `grep -rn "perf-summary-table" test`; `git log --format='%h %ad %s' --date=short -S"defp table_summary" -- lib/portfolixir_web/live/portfolio_live.ex | tail -1` and the same with `-S"defp overlay_cell"`.

**Observed output.**

```
TODAY 2026-11-16 START 2026-09-07 +10% on 2026-10-07 +10% on 2026-11-15
CARD bought once: +21.0% vs +21.0%
PURPOSE Start/end value, return and flows per period — the chart, summarised.
HEAD ["Month", "Start value (EUR)", "End value (EUR)", "TTWROR", "Net flows (EUR)", "Bench ETF"]
ROW ["2026-09", "1,000.00", "1,000.00", "0.0%", "1,000.00", "0.0%"]
ROW ["2026-10", "1,000.00", "1,100.00", "+10.0%", "0.00", "+10.0%"]
ROW ["2026-11", "1,100.00", "1,210.00", "+10.0%", "0.00", "+21.0%"]
1 test, 0 failures
```
The card says the portfolio is the benchmark ("+21.0% vs +21.0%"). The November row says "+10.0%" for the portfolio and "+21.0%" for the same security as its benchmark.

`perf-summary-table` is read by six test lines in three files; the four in `test/portfolixir_web/live/portfolio_benchmark_live_test.exs` (`:87`, `:88`, `:189`, `:303`) read the column's `th` only, the other two (`displayed_dates_live_test.exs:289`, `performance_table_summary_test.exs:42`) have no benchmark. `git log`: `37f28f54 2026-08-14 feat(ui): wealth chart data table becomes per-period summaries (#564)`; `9f3738bb 2026-09-15 fix(web): the benchmark card and picker after the design-critic round ...`.

**Cost of leaving it.**

- One percent column per selected benchmark (up to two) on another basis than the "TTWROR" column beside it; every row but the first. In a table by year (a series over 366 days) the difference is every earlier year's return compounded.
- 0 tests read a cell of the column.
- The agent cannot check the row: neither the slice return nor a per-slice benchmark return is in a payload.
- In R-022 (G2-01)'s case the cell is in addition the anchored level, not the benchmark's cumulative return.

**Proposed fix.**

The benchmark column prints the benchmark's return over the row's slice, chained out of the plotted points with the function the portfolio's column already uses (`slice_ttwror/2`, one function for both columns); or the column's head names its basis (`since <period start>`). The first makes the row comparable, which is what a table of per-period returns is read for; it also takes R-022 (G2-01)'s anchor out of the cell, because the anchor is a common factor of a slice's two ends. Size S (hours). No ADR amendment; a board for the column, since a figure on the Wealth page changes, and one test that reads a cell. If the table summary later moves into the performance payload, the benchmark's slice return belongs beside it in the comparison payload, so that the agent reads the same row.

**Second reading.**

- Lens: reach and decided. Refuted: no. Severity it would defend: S2.

  Not refuted. Reach: no guard separates the two bases. table_summary/1 chains each row's slice return (portfolio_live.ex:5930, :5949-5957) while overlay_cell/2 prints the plotted cumulative fraction at row.end_date (:4167-4168, :4492-4497); the head is the bare label (:4153-4155) under 'return ... per period' (:4131). The fixture's state is documented ('it may still be held, and then it is simply both', product-documentation.md:691-694) and the mismatch needs none of it: any benchmark, TTWROR mode, the default 1Y period (monthly rows), every row after the first. Decided: only in part. The cumulative basis was chosen in Sprint 11's closing act (commit 9f3738bb's message; the comment at :4151-4152; retro :100-101), so replacing the cell changes that choice and needs a board; no ADR, idea row, plan, polish list (#1366) or doc (product-documentation.md:2301-2304 omits the column) decides the head or the purpose line. Severity: S2 at its low end holds, because the purpose line states a basis that is false for the column, the class the severity pass rated S2 (#1317, #1343). Mitigations that stop short of S3: no figure is wrong, the last row's cell equals the card's, the disclosure is closed by default (.decision-log.md:169), and no payload carries either cell.

### R-024 (O1-02), S2: When one of two depots holding a security has no derivable cost, the Overview reads "Unrealised —" and the Holdings tab's "Total" row reads the other depot's result beside the value of both, with no note naming the row left out

- **Class:** duplicate computation in the web layer
- **Stands against:** `_bmad-output/planning-artifacts/design-language/DESIGN.md:1675-1676` (UX-DR25): "When an aggregate cannot include a row, the surface states **how many** and **which** — beside the figure, not in a tooltip and not only in the payload."; the page's own comment at `lib/portfolixir_web/live/securities_live.ex:2051-2052`: "A total is only a total when every row carries the figure; one unpriced depot makes the sum a dash, never a silently smaller number."
- **Locations:** `lib/portfolixir_web/live/securities_live.ex:2028-2057`, `lib/portfolixir_web/live/securities_live.ex:1874-1890`, `lib/portfolixir_web/live/securities_live.ex:3005-3017`, `lib/portfolixir_web/live/securities_live.ex:3136-3152`, `lib/portfolixir_web/live/securities_live.ex:3157-3171`, `lib/portfolixir_web/live/securities_live.ex:3835-3840`, `lib/portfolixir/ledger.ex:613-641`, `lib/portfolixir/ledger.ex:1009-1016`, `lib/portfolixir/ledger.ex:829-834`
- **Who meets it:** the operator on Securities → a security held in two depots → Overview against the Holdings tab
- **Fix size:** M. **ADR amendment:** none
- **On the later `main` (read, not run):** still stands. Ledger unchanged. Fifteen commits touched the security page file; the Overview's all-or-nothing sum, the Holdings tab's partial sum, its Total row and the price-only note are identical, moved about 145 to 223 lines down.

**What is wrong.**

1. `Ledger.holdings_for_security/2` prices every row with one point (`lib/portfolixir/ledger.ex:614`), so a security's rows are all valued or all unvalued. What varies per row is the cost: `cost_basis` is `nil` when `lot.cost_known` is false (`:627`), which `acquisition_legs/2` sets for a cross-currency booking without a stored `security_amount` (`:829-834`). Such a row carries `current_value` and `unrealized_pnl_abs: nil` (`:1009-1016`).
2. The Overview sums all-or-nothing: `sum_known(holdings, :cost_basis)` is `nil` as soon as one row lacks its cost (`lib/portfolixir_web/live/securities_live.ex:2053-2057`), so "Unrealised" is a dash (`:2036`, `:1879-1880`).
3. The Holdings tab sums what is there: `sum_or_nil(valued, :unrealized_pnl_abs)` drops the `nil` rows (`:3835-3840`) and prints the rest in the row labelled "Total" (`:3147-3149`), beside a total value that includes every row (`:3139-3146`).
4. The note under the table lists `@unvalued` only (`:3157-3171`), which by hop 1 is either empty or every row. The row left out of the result total is explained only by a `title` on its own dash cell.
5. The Holdings tab's sum rule is the board's: `DESIGN.md:7731-7732` says "The „Gesamt“ row sums the valued rows' values and the P&L of the rows that carry one." The board's note (`DESIGN.md:7733-7737`) is written for a row with no price; a priced row without a cost has no note, which is the UX-DR25 gap, and the Overview's rule is the opposite of the board's.

**Reproduction.**

Scratch test `test/audit_scratch/o1_02_totals_test.exs`, run in a test slot.

The second booking is the fixture of `test/portfolixir/ledger/pnl_fx_decomposition_test.exs:68-85` ("An imported cross-currency booking whose native leg was never derivable").

_(scratch test source and run command: in the private evidence held by the owner)_

**Observed output.**

```
LEDGER row depot=Depot B qty=10.000000000000 cost_basis=nil current_value=Decimal.new("1100.000000000000000000") unrealized_pnl_abs=nil
LEDGER row depot=Depot A qty=10.000000000000 cost_basis=Decimal.new("1000.000000000000000000") current_value=Decimal.new("1100.000000000000000000") unrealized_pnl_abs=Decimal.new("100.000000000000000000")
OVERVIEW overview-holding: Holding 20.0000 units2 depots
OVERVIEW overview-value: Value 2,200.00 USD
OVERVIEW overview-unrealised: Unrealised — against average cost
HOLDINGS head: ["Depot", "Quantity", "Avg cost", "Current value", "Unrealised P&L", "%", "Price return", "Currency return", "Total (base)"]
HOLDINGS row: ["Depot B", "10.0000", "— USD", "1,100.00 USD", "—", "—", "—", "—", "—"]
HOLDINGS row: ["Depot A", "10.0000", "100.00 USD", "1,100.00 USD", "+100.00", "+10.0%", "—", "—", "—"]
HOLDINGS total row: ["Total", "2,200.00 USD", "+100.00", ""]
HOLDINGS unvalued note present: false
HOLDINGS notes in panel: []
HOLDINGS cell titles: ["No security-currency cost is derivable from the recorded booking (no settlement legs, no stored rate at the booking date).", "The recorded settlement leg is not in the base currency."]
1 test, 0 failures
```

One question (the security's unrealised result), two answers on two tabs: a dash on the Overview, "+100.00" under "Total" on the Holdings tab, next to "2,200.00 USD" that counts both depots. No note in the panel; the reason is a tooltip on the row's dash.

**Cost of leaving it.**

- Two summing rules for one position, 41 lines in one file (`securities_live.ex:2028-2057`, `:3011-3017`, `:3835-3840`), 1,800 lines apart, plus a third read for the agent (`lib/portfolixir_web/controllers/api/v1/security_dossier.ex:148-168`, `Valuation.holdings_by_security_report/1`) that carries no unrealised result at all.
- The operator who reads the Holdings tab takes +100.00 for the result of a 2,200.00 position; the operator who reads the Overview sees no result. The split-with for unvalued rows (`:3011`) can never split for one security (one price point for all rows), while the figure that does vary per row has no note.
- The precondition is narrow: two depots, one of them with an imported cross-currency buy whose `security_amount` was never stored.

**Proposed fix.**

The ledger answers the security's total beside its rows (rows plus a total that names the rows left out of each figure, as `Valuation.security_holding/2` already does for value); both tabs print it; the note under the Holdings table names the rows without a cost beside the result total (UX-DR25). Which rule the result total follows (the board's partial sum with a note, or the Overview's dash) is one decision for both tabs. Size M. Risk tier (cost and result). No ADR amendment; a line on `DESIGN.md:7731-7737` for the second kind of left-out row and for the Overview's tile, which is a board change (AGENTS.md, "A UI change is mocked on a board before it is built").

**Second reading.**

- Lens: reach and decided. Refuted: no. Severity it would defend: S2.

  Not refuted. Reach: no guard stops it, and both tabs read one list (securities_live.ex:1467, :1515). The fixture's own booking is transient on a live instance: after an import the rate history arrives by itself and derives buy and sell legs (applier.ex:1263; rate_sync.ex:240, :272). The state still lasts for a zero-amount lot (settlement_backfill.ex:151-156), an imported delivery booked in another currency than its security's (applier.ex:2738-2749 stores no legs; the backfill takes buys and sells only, settlement_backfill.ex:128), a date with no stored rate, and background fetch off. So the reach is not smaller than the evidence says. Decided: the Holdings tab's partial result total is the board's rule (DESIGN.md:7731-7732; comment at securities_live.ex:3006-3010); that half is no finding. Undecided: the board's note covers unpriced rows only (DESIGN.md:7733-7737) and draws no priced row without a cost; the Overview's all-or-nothing rule (securities_live.ex:2051-2057) is tested for the unpriced case only (security_detail_overview_test.exs:109-138); no idea row, polish line (issue 1365) or issue names the mixed state. S2 holds by the Sprint 22 severity pass's precedent (#1332 row against total, #1311 zero-amount lot, both S2). Not S1: neither figure is arithmetically wrong.

### R-025 (O1-04), S2: The chart's moving averages are computed in the page from the visible range only, so the default-on MA200 draws nothing on 1M, 3M and 6M and on the first three quarters of the default 1Y (63 of 262 points are drawn), and MA50 nothing on 1M, while both pills stay pressed and the grid under the chart states both values

- **Class:** duplicate computation in the web layer
- **Stands against:** `_bmad-output/planning-artifacts/design-language/DESIGN.md:290`: "SMA-50 and SMA-200 draw as the chart second and third series by default, their toggles unchanged so a reader can turn them off. Because they are on by default the chart carries a LEGEND naming every active overlay"; `_bmad-output/planning-artifacts/design-language/DESIGN.md:288`: "a moving average means its distance to the price and its crossing with the other average, and separating the figures from the series makes both unreadable (issue 824, pick D1-A)"; `docs/decisions/0047-derived-metrics-per-security-and-per-view.md:328-329`: "`sma_n` is defined over the newest `n` closes"
- **Locations:** `lib/portfolixir_web/live/securities_live.ex:3948-3979`, `lib/portfolixir_web/live/securities_live.ex:3981-3996`, `lib/portfolixir_web/live/securities_live.ex:6661-6671`, `lib/portfolixir_web/live/securities_live.ex:1347-1358`, `lib/portfolixir_web/live/securities_live.ex:1423-1436`, `lib/portfolixir_web/live/securities_live.ex:153`, `lib/portfolixir/engines/price_metrics.ex:168-191`
- **Who meets it:** the operator on Securities → a security → Chart, on every range shorter than the average's window plus what is to be drawn
- **Fix size:** M. **ADR amendment:** ADR-0047 only if the API serves the series; none for a page read
- **On the later `main` (read, not run):** still stands. Compared the securities page on origin/main: the averaging functions, default-on pills and range-only quote read are identical. Cycle work only added an aligned-mode condition to the legend and a "Zyklus" range; commits attributed by subject.

**What is wrong.**

1. The pane loads the quotes of the chosen range only (`lib/portfolixir_web/live/securities_live.ex:6661-6671`, `Quotes.adjusted_range(id, from, to)`).
2. `build_chart_overlays/6` averages over those rows alone (`:3956-3962`); `moving_average/2` emits its first point at the range's n-th quote (`:3981-3996`). The closes before the range's start, which an average at the range's first day needs, are not read.
3. An overlay without a point is dropped (`:3978`), so the line and its legend entry are gone (`:1423-1436` renders the survivors), while the pill is still `is-active` with `aria-pressed="true"` from `@detail_ma` (`:1347-1358`), which starts as `%{30 => false, 50 => true, 200 => true}` (`:153`).
4. The cell "SMA 200" under the same chart prints the engine's figure over the newest 200 stored closes (`lib/portfolixir/engines/price_metrics.ex:168-191`), whatever the range.
5. The engine computes the average in decimals from the whole series; the page's copy is a float fold over the range (`securities_live.ex:3985`, `:3988`).

**Reproduction.**

Scratch test `test/audit_scratch/o1_04_ma_test.exs`, run in a test slot.

_(scratch test source and run command: in the private evidence held by the owner)_

**Observed output.**

```
== Weekday Co: 787 stored closes
WKD default(1Y): polylines=[{["quote-line"], [262]}, {["chart-ma-50"], [213]}, {["chart-ma-200"], ~c"?"}]
WKD default(1Y): ma50 points=213 ma200 points=63 legend=["MA50", "MA200"] pills=[{50, ["true"]}, {200, ["true"]}]
WKD default(1Y): grid=["SMA 50 105.70 -5.4% 2026-09-03 – 2026-11-11 · 50 observations", "SMA 200 105.92 -5.6% 2026-02-05 – 2026-11-11 · 200 observations"]
WKD 1M: polylines=[{["quote-line"], [23]}]
WKD 1M: ma50 points=0 ma200 points=0 legend=[] pills=[{50, ["true"]}, {200, ["true"]}]
WKD 1M: grid=["SMA 50 105.70 -5.4% 2026-09-03 – 2026-11-11 · 50 observations", "SMA 200 105.92 -5.6% 2026-02-05 – 2026-11-11 · 200 observations"]
WKD 3M: polylines=[{["quote-line"], ~c"A"}, {["chart-ma-50"], [16]}]
WKD 3M: ma50 points=16 ma200 points=0 legend=["MA50"] pills=[{50, ["true"]}, {200, ["true"]}]
WKD 3M: grid=["SMA 50 105.70 -5.4% 2026-09-03 – 2026-11-11 · 50 observations", "SMA 200 105.92 -5.6% 2026-02-05 – 2026-11-11 · 200 observations"]
WKD 6M: polylines=[{["quote-line"], [129]}, {["chart-ma-50"], ~c"P"}]
WKD 6M: ma50 points=80 ma200 points=0 legend=["MA50"] pills=[{50, ["true"]}, {200, ["true"]}]
WKD 6M: grid=["SMA 50 105.70 -5.4% 2026-09-03 – 2026-11-11 · 50 observations", "SMA 200 105.92 -5.6% 2026-02-05 – 2026-11-11 · 200 observations"]
WKD 3Y: polylines=[{["quote-line"], [783]}, {["chart-ma-50"], [734]}, {["chart-ma-200"], [584]}]
WKD 3Y: ma50 points=734 ma200 points=584 legend=["MA50", "MA200"] pills=[{50, ["true"]}, {200, ["true"]}]
WKD 3Y: grid=["SMA 50 105.70 -5.4% 2026-09-03 – 2026-11-11 · 50 observations", "SMA 200 105.92 -5.6% 2026-02-05 – 2026-11-11 · 200 observations"]
1 test, 0 failures
```

(`~c"?"`, `~c"A"` and `~c"P"` are how the run printed the one-element lists `[63]`, `[65]` and `[80]`.)

With 787 stored weekday closes (three years): on 1M neither average is drawn and the legend is gone; on 3M and 6M the MA200 is missing; on the default 1Y the MA200 covers 63 of 262 points (24 %) and the MA50 213 of 262. Both pills read `aria-pressed="true"` on every range, and the grid states "SMA 200 105.92 … 200 observations" on every range.

**Cost of leaving it.**

- The crossing of the two averages, the reason pick D1-A gives for drawing them, is visible on the last quarter of the default chart and on none of 1M, 3M and 6M (three of the eight ranges; YTD depends on the date).
- A pressed MA200 pill that changes nothing when clicked on those ranges, and a legend that drops the entry without a word.
- 16 lines that restate the engine's average in floats (`securities_live.ex:3981-3996`). The one existing test seeds 400 calendar-day closes and stays on 1Y, where both lines exist (`test/portfolixir_web/live/security_metrics_events_panel_test.exs:85-96`); `grep -rn 'chart-ma-200' test` prints nothing.

**Proposed fix.**

The series comes from the engine's rule: a function beside `Catalog.SecurityMetrics.for_security/2` that answers the SMA series for a window over the whole stored history (decimals, the engine's `sma/3` rule per day), cut to the range by the caller; the page keeps only the float conversion at the chart boundary. The engine owns the rule. Size M. It needs an amendment of ADR-0047 if the API is to serve the series (a series form of `sma_n` with its basis); none if it stays a page read. A smaller step with the same visible effect: read the range's quotes with a lookback of the largest active window and cut after averaging. Size S, no ADR.

**Second reading.**

- Lens: reach and decided. Refuted: no. Severity it would defend: S2.

  Not refuted. Reach: the reproduction drives the real route and the range buttons. The default range is 1Y (securities_live.ex:72), both averages start pressed (:153), the pane reads the range's quotes only (:6661-6671; range_to_dates/2 at :7300-7313 adds no lookback), the average starts at the range's n-th quote (:3981-3996), an empty overlay is dropped (:3978) and the pill reads @detail_ma alone (:1353-1354). Every operator meets it on every security with a history. Decided: nothing accepts it, and the records point the other way. The picked board D1-A draws both averages from the left edge across the whole 1J chart (mockups/ux-design-2026-09-19/01-security-metrics.html:56-59); the product page promises a visible crossing (docs/product-documentation.md:468-471); the legend test's criterion is a legend naming every active overlay, seeded with 400 closes on 1Y only (security_metrics_events_panel_test.exs:82-88). ADR-0047 is silent on the chart's series; I6 and I42 are other matters; the Securities polish list (issue 1365) has no line. The one earlier trace, a test comment that 90 quotes are enough for the MA30 toggle to render points (securities_live_test.exs:1412), is knowledge, not a decision. S2 holds: a default-on control that draws nothing on three ranges. Not S1: the drawn points and the grid's figure are right.

### R-026 (O2-04), S2: The page's load protocol is written out once per load, and each of its five view-gone branches reloads its own section only: after the active view is deleted elsewhere, the page says "showing Everything", lists Everything's positions and keeps the deleted view's total until a reload

- **Class:** structure (many copies of one mechanism); missing pin
- **Stands against:** the page's own promise for this case, "re-check before each load and degrade to the built-in Everything scope with a small notice" (`lib/portfolixir_web/live/portfolio_live.ex:1253-1256`) and "the positions table follows the page back to Everything" (`:1272`), which hold for the section that happened to load and not for the header; nearest written contract `lib/portfolixir_web/capped_async.ex:3` ("The one way the web layer hands work to another process"), which covers how a task starts and not what a page does when a result lands. Nothing else is written. The view-gone function needs no ADR; a load helper shared by seven pages would be recorded as a decision first (section 7, in `architecture-review-splits-2026-11-24.md`, the Wealth page).
- **Locations:** `lib/portfolixir_web/live/portfolio_live.ex:870-880` (`start_loading/1`), `:882-1062` (the five loads), `:1171-1216` (`read/2`, `reconcile_reads/1`, `supersede_performance/1`), `:1257-1274` (`ensure_live_view_scope/1`, `degrade_to_everything/1`), `:1292-1509` (15 `handle_async/3` clauses and the landing helpers), `:4932-4939` (`sync_rates`), `:6021-6047` (`put_period/2`), `:465-475` (the tree switch)
- **Who meets it:** the operator on Wealth (both tabs) whose selected view is deleted in another tab or through the API or MCP while the page is open; a developer adding a load to the page
- **Fix size:** M. **ADR amendment:** none
- **On the later `main` (read, not run):** still stands. The Wealth page file changed only in the benchmark picker, drift filter and help texts. The load plumbing, the five view-gone branches, the period switch and the tree switch are identical on origin/main.

**What is wrong.**

1. Starting is one mechanism used six times: `CappedAsync.start_async/3` for `:overview` (`lib/portfolixir_web/live/portfolio_live.ex:889`), `:allocation` (`:942`), `:performance` (`:966`), `:sync_rates` (`:4936`); `CappedAsync.start_latest/3` for `:contribution` (`:991`) and `:bands` (`:1050`). This part holds.
2. Recognising a result that is no longer wanted is written four ways. `:overview` carries the classification id in its seven-tuple and compares it for the allocation part only (`:1360-1365`). `:contribution` carries `{period, {result, read}}` and compares period and view (`:1493`). `:bands` carries `{request, answer}` with `request = {stack, period, view}` (`:1095-1096`, `:1442`). `:performance` carries `{analysis, read}` with no check at landing (`:1376-1398`); its view is compared later in `reconcile_reads/1` (`:1194`). `:allocation` relies on LiveView dropping an older task of the same name (`:1370-1372`).
3. The view-gone branch exists five times, each `degrade_to_everything() |> load_X()` for its own X: `:1296`, `:1300`, `:1304`, `:1460`, `:1486`; a sixth in `assign_holding_rows/1` (`:3435-3436`); and `ensure_live_view_scope/1` (`:1257-1265`) degrades before each of the five loads starts (`:883`, `:937`, `:955`, `:984`, `:1014`). `degrade_to_everything/1` (`:1267-1274`) clears the view, sets the notice and reloads the positions; it restarts no load.
4. The consequence, no race needed. On Holdings a period switch runs `put_period/2` (`:6021-6047`): it re-chains the cached summary and calls `load_contribution/1`, whose `ensure_live_view_scope/1` finds the view gone and degrades. The contribution loads for Everything; when it lands, `reconcile_reads/1` sees `a.view != active_view_id` (`:1194`) and reloads the performance. Nothing calls `load_overview/1`: the valuation, and with it the header total, the securities and cash figures, the cash quote, the cash table and the data-quality rows, stay the deleted view's. On the Allocation tab a tree switch calls `load_allocation/1` (`:474`), which degrades the same way and reloads the allocation only; `reconcile_reads/1` returns at once because the tab never loads a contribution (`:1188-1190`, `:983`, `:999`), so the summary line keeps the deleted view's total and TTWROR.
5. Drift between copies: a `:bands` result for a request the page no longer shows is dropped and nothing is started (`:1442-1445`); the same case in the contribution copy reloads (`:1498-1500`). After another load's view-gone branch has cleared the view, the bands' own `view_not_found` answer fails the request comparison before it reaches `bands_answer/2` (`:1459-1460`): `bands` stays `nil`, `bands_failed` stays `false`, no task is in flight, and the stack shows "computing" (`:2441-2446`) until the next period or level change. This one needs the view deleted between a load's start and its read.
6. Failure has five representations: `error` for `:overview` and `:allocation` (`:1437-1439`), `performance_failed` (`:1396`, `:1434`), `contribution_failed` (`:1504`, `:1508`), `bands_failed` (`:1447`, `:1483`), `fx_sync_result: :error` (`:1424`, `:1428`). The template tests `is_nil(@performance) and not @performance_failed` six times and its opposite five times.
7. Two tests pin the private shape of one landing: `test/portfolixir_web/live/portfolio_live_test.exs:3403-3407` and `:3428-3432` call `handle_async(:overview, {:ok, {valuation, 1, allocation, nil, [], [], %{...}}}, socket)` on a bare socket with four assigns. The existing view-gone tests assert the notice (`test/portfolixir_web/live/view_scope_test.exs:539`, through the rate sync, whose success path does reload the overview) and the positions (`test/portfolixir_web/live/wealth_positions_scope_test.exs:101-117`, through a period switch); none asserts the header total after a period or tree switch.

**Reproduction.**

Scratch test `test/audit_scratch/o2_04_load_protocol_test.exs` (two EUR portfolios, a view over the second depot only; modelled on `test/portfolixir_web/live/wealth_positions_scope_test.exs`), removed after the run. The third test is the reader's, for hop 5.

_(scratch test source and run command: in the private evidence held by the owner)_

Counts, from the checkout (`F=lib/portfolixir_web/live/portfolio_live.ex`):

```
grep -cF 'CappedAsync.start_async(' $F; grep -cF 'CappedAsync.start_latest(' $F; grep -cF 'CappedAsync.landed(' $F
grep -c '^  def handle_async' $F; grep -cF 'view_not_found' $F; grep -cF 'degrade_to_everything()' $F
grep -cF 'ensure_live_view_scope(socket)' $F; grep -cF 'is_nil(@performance) and not @performance_failed' $F
grep -cE 'is_nil\(@performance\) and @performance_failed' $F
grep -rnE "CappedAsync\.(start_async|start_latest|landed)\(" lib | cut -d: -f1 | sort | uniq -c | sort -rn
```

**Observed output.**

```
== O2-04 drift one, handle_async(:bands, view_not_found for a view the page left) ==
bands: nil, bands_failed: false, bands_for: 7 (the page's view: nil)
flights after landing: %{}

== O2-04 Holdings, view deleted elsewhere, period switch ==
Everything's own page, #kpi-total  : Total incl. cash 1,720.00 EUR Securities 1,720.00 · Cash 0.00
before, scoped to the view         : Total incl. cash 220.00 EUR Securities 220.00 · Cash 0.00
after: notice                      : The selected view no longer exists — showing Everything.
after: #kpi-total                  : Total incl. cash 220.00 EUR Securities 220.00 · Cash 0.00
after: #kpi-securities             : Securities 220.00 EUR
after: positions rows              : ["Home Depot Alpha Works 10", "Second Depot Bravo Freight 4"]
after: #kpi-invested               : sis of the wealth multiple. 0.00 EUR net flows +1,200.00 EUR
after: #kpi-ttwror                 : e counts. 0.0% +520.00 EUR in the period

== O2-04 Allocation, view deleted elsewhere, tree switch ==
Everything's own page, summary line: Total incl. cash 1,720.00 EUR Cash quote 0.0% TTWROR 1Y 0.0% All key figures → Holdings
before, scoped to the view         : Total incl. cash 220.00 EUR Cash quote 0.0% TTWROR 1Y 0.0% All key figures → Holdings
after: notice                      : The selected view no longer exists — showing Everything.
after: summary line                : Total incl. cash 220.00 EUR Cash quote 0.0% TTWROR 1Y 0.0% All key figures → Holdings

3 tests, 0 failures
```

Read: after the degrade on Holdings, one page shows Everything's positions (both depots), Everything's flows and result (+1,200.00, +520.00) and the deleted view's total (220.00, where Everything's is 1,720.00). On the Allocation tab the summary line is byte-identical to the deleted view's.

Counts: `start_async(` 4, `start_latest(` 2, `landed(` 2, `def handle_async` 15, `view_not_found` 8, `degrade_to_everything()` 5, `ensure_live_view_scope(socket)` 6 (5 calls and the definition), `is_nil(@performance) and not @performance_failed` 6, its opposite 5. Call sites by file: `portfolio_live.ex` 8, `imports_live.ex` 3, `dashboard_live.ex` 2, `classifications_live.ex` 2, the two merge dialogs 1 each, `income_live.ex` 1.

**Cost of leaving it.**

- 421 lines of plumbing in this file (`:868-928`, `:954-969`, `:1166-1509`), 15 `handle_async/3` clauses whose order decides which failure state a dead load reaches (`:1431` must stay above `:1437`), 4 ways to recognise an unwanted result, 5 view-gone branches plus 2 more degrade sites, 5 failure representations. Every new load adds a copy; six other LiveView modules use `CappedAsync` with landings of their own.
- The figure a user reads wrongly: the header total (and the securities, cash and cash-quote figures, the cash table and the data-quality rows that come from the same valuation) under a notice that says "showing Everything", until the page is reloaded.
- On a stacked address, a skeleton that never resolves in the raced case of hop 5.

**Proposed fix.**

One function for "the view is gone" that clears the view and restarts every load that read it (overview, performance, contribution, bands, positions), called from every branch; that alone closes hop 4 and hop 5 (size S, with a test that asserts the header total after a period switch and after a tree switch). Then one keyed-load helper beside `PortfolixirWeb.CappedAsync` that owns the request identity, the still-wanted decision, the reload on a mismatch and one failure shape per load; the page keeps which loads exist, what a landing assigns and `reconcile_reads/1` (size M). No ADR amendment for the view-gone function. The shared helper, if it is still wanted, is recorded as a decision first, not as a module comment, because seven pages would depend on it (section 7, in `architecture-review-splits-2026-11-24.md`, the Wealth page).

**Second reading.**

- Lens: reach and decided. Refuted: no. Severity it would defend: S2.

  Not refuted; S2 stands, at its low end. Lens 1 fails on the repository's own record: the scenario is a kept user story. wealth_positions_scope_test.exs:92-117 ("whose view was deleted in another tab ... so that the rows match the scope the notice says the page now shows") runs the reproduction's exact steps (delete_view, then the ytd button) and asserts the notice and the rows, never the total; view_scope_test.exs:525-544 covers it through the rate sync. No guard exists: degrade_to_everything/1 restarts no load (:1267-1274), put_period/2 starts the contribution and the bands only (:6021-6034), reconcile_reads/1 reloads the performance (:1192-1194), and load_overview/1 has four callers, none on this path. The page subscribes to nothing. Lens 2 finds no decision: DESIGN.md:2589-2591 says the screen degrades to Everything, and :4514-4517 promises agreement for the sum and the badge only. A money total under a notice naming another scope is a misleading answer. Reach is narrow: a view deleted behind the open page, then one switch; a reload clears it; nothing is stored. The many-copies structure alone is S3. Limit: the GitHub polish lists were not read.

### R-027 (G1-03), S2: "Delete plan" leaves the cash target the same form saved: the scope does not fall back to actual-only, every tree of the view stays in target mode on the cash target alone, Wealth and the Overview then read cash held at 8 % against a stored 5 % as "92.0 pp below target · -920.00 EUR", and the editor's empty state has no control for the figure that still steers

- **Class:** seam (one form, two stored homes, one lifecycle); documentation drift
- **Stands against:** `lib/portfolixir_web/live/classifications_live.ex:1572`: "Delete this view's plan? The Wealth page falls back to actual-only for it."; `docs/product-documentation.md:1629-1630`: "**Delete plan** (*Plan löschen*) removes the view's plan; the Wealth page then falls back to **actual-only** (no target, no drift) for that view." and `:1703-1704`: "on the active plan it keeps its ADR-0020 meaning (the scope falls back to actual-only)"; `docs/integration/api-and-mcp.md:3295-3296` and `mcp-server/src/tools.ts:4659`: "Deleting the active plan leaves the scope without a plan (the allocation falls back to actual-only)."; `lib/portfolixir/portfolios/targets.ex:722-726`: "then the plan row and with it the plan's cash target … After this `plan_exists?/3` is `false`, so the portfolio page falls back to IST-only for that `(view, classification)`."; `docs/decisions/0020-view-bound-soll-plans.md:51-53`: "With no plan, the portfolio page shows that view's allocation **actual-only** (no target, no drift, no Σ-vs-100%)."
- **Locations:** `lib/portfolixir_web/live/classifications_live.ex:2073-2098` (`delete_soll_plan/1`), `:1517-1541` (the Cash row, inside the plan form), `:1568-1575` (the button and its confirm text), `:1592-1601` (the empty state: "Create plan" only), `:2114-2124` (`soll_cash_opts/2`); `lib/portfolixir/portfolios/targets.ex:495-501` (`edit_cash/4`), `:729-742` (`delete_plan/4`), `:750-754` (`delete_plan_version/2`), `:814-824` (`delete_plan_rows/2`); `lib/portfolixir/portfolios/allocation.ex:266-315` (`plan_soll/5`; a cash target alone is `has_plan: true` at `:297-304`), `:523-525`, `:566-570`, `:940-943`, `:952-953`; `lib/portfolixir_web/live/portfolio_live.ex:2570-2621`, `:2969-3003`; `lib/portfolixir_web/live/dashboard_live.ex:1167-1195`; `lib/portfolixir_web/controllers/api/v1/plan_controller.ex:76-84`
- **Who meets it:** the operator on Classifications ("Delete plan" in the Target plan section), then on Wealth → Allocation and on the Overview's "Off target" card; the agent on `DELETE /api/v1/plans/:id` (`portfolixir.plans.delete`) followed by `GET /api/v1/portfolios/:portfolio_id/allocation`.
- **Fix size:** S. **ADR amendment:** none beyond R-136 (G1-02)'s ADR-0027 amendment; the cash-only drift arithmetic is a question for ADR-0040
- **On the later `main` (read, not run):** still stands. Five cited files changed, none in the cited lines: the Wealth page (`portfolio_live.ex`), the Overview (`dashboard_live.ex`), the product documentation, the API reference and `mcp-server/src/tools.ts`. The plan editor, the targets context, the allocation engine and the plan controller are identical (compared file by file by the audit lead).
- **Audit lead's note:** The "92 pp below target" is not this finding's own defect: it is ADR-0040 §2's arithmetic on a steering that consists of the cash target alone, which ADR-0040 does not mention and no test pins (AD-3, in section 10 of `architecture-review-triage-2026-11-24.md`, names the question). The finding is that every record of "Delete plan" promises actual-only and that is false while a cash target is stored. R-136 (G1-02) is taken as its option (A): the cash target is the view's, as built and documented (section 9, in `architecture-review-triage-2026-11-24.md`), so this fix is the wording and the one control, size S. Option (B), a cash target per plan version, would change how a stored figure steers and would be the owner's to decide.

**What is wrong.**

1. The plan form saves the weights and the Cash field in one transaction (`Targets.edit_plan/5`, `lib/portfolixir/portfolios/targets.ex:459-473`). The cash value goes to the view's cash-only plan, another row than the plan being edited (`edit_cash/4`, `:495-501`; R-136 (G1-02)).
2. "Delete plan" (`lib/portfolixir_web/live/classifications_live.ex:2073-2098`) calls `Targets.delete_plan/4` for the active plan or `delete_plan_version/2` for a picked version (`targets.ex:729-742`, `:750-754`). Both delete the tree's plan row and its targets (`delete_plan_rows/2`, `:814-824`). The cash-only plan is another row and stays (run A5: `plan_exists: false`, `stored_cash_target: 0.05`). The docstring's "and with it the plan's cash target" (`:722-723`) is true of the row's own column, which no door writes.
3. `Allocation.plan_soll/5` then takes its second branch: no category plan, a cash target, so `has_plan: true` (`lib/portfolixir/portfolios/allocation.ex:297-304`; the rule is stated at `:256-259`). Run A6: `has_plan: true`, Σ 0.05, where a scope that never had a plan reads `has_plan: false` (run A0).
4. Wealth prints "Plan on Strategy · Σ target top level: 5.0% — drift against the allocated portion" and no no-plan hint (`lib/portfolixir_web/live/portfolio_live.ex:2571-2621`; run A7, A8). The same holds for every tree of that view, the built-in ones included, because the cash target is the view's (run A10, the asset-class tree).
5. With the cash target as the whole top-level sum (`allocation.ex:523-525`), `drift_base` is 0.05 (`:940-943`) and the cash row's target is divided by it (`:566-570`, `:952-953`): cash held at 8 % against a stored target of 5 % reads a drift of 0.08 - 1 = -0.92, where the same holdings read +0.03 one click earlier (run A2 against A6). Wealth's cash row reads "Cash 80.00 8.0% 5.0% -920.00 EUR" (run A9): actual above the target shown beside it, and a negative drift.
6. The Overview's "Off target" card reads the same allocation (`lib/portfolixir_web/live/dashboard_live.ex:1167-1195`): its basis line says "View Everything — no active plan on Strategy" and its row says "Cash 92.0 pp below target · -920.00 EUR" (run A9a, A9b), on a basis of 1,000.00 EUR.
7. The Classifications page now shows "No plan for this view." and "Create plan" (`classifications_live.ex:1592-1601`). The Cash field lives inside the plan form (`:1517-1541`), which is gone, so the figure that still steers is on no control of any screen (run A5: `cash_input_on_page: false`; `grep -rn "cash_target" lib/portfolixir_web/live lib/portfolixir_web/components` names no other input). The way out on the screen is four steps through a plan nobody wants: Create plan, empty the Cash field, Save plan, Delete plan (run C1 to C3); it leaves a cash-only row with a `nil` weight behind (run C4).
8. Over the API the same holds for `DELETE /api/v1/plans/:id` (`lib/portfolixir_web/controllers/api/v1/plan_controller.ex:76-84`; run B1 to B3: `top_level_target_sum` "1" becomes "0.05", `drift_basis` "allocated_portion", cash `drift_weight` "-0.92"). There the agent has a second call that clears it (`PUT …/cash_target` with `null`, run B4), which the delete's description does not mention.
9. The test that pins the delete's story runs without a cash target (`test/portfolixir_web/live/classifications_live_test.exs:641-667`: "so the portfolio page falls back to IST-only for that view"; it sets one category weight and asserts `plan_exists?` only).

**Reproduction.**

Scratch test `test/audit_scratch/g1_03_test.exs` in the slot's checkout (removed after the run), modelled on `test/portfolixir_web/live/classifications_live_test.exs:577-610` and `test/portfolixir_web/controllers/api_v1_plans_and_snapshots_test.exs`. Fixture: 1,000 deposited, 10 units bought at 92 and quoted at 92, so 920 in a security and 80 in cash. Test A is the reader's reproduction with the screens read back; B (the API) and C (the way out) are the verifier's.

_(scratch test source and run command: in the private evidence held by the owner)_

**Observed output.**

```
Running ExUnit with seed: 0, max_cases: 24
Excluding tags: [:browser]

A0 allocation, no plan yet: %{
  has_plan: false,
  top_level_target_sum: "0",
  drift_basis: "full_plan",
  cash_actual: "0.0800",
  cash_target: "0",
  cash_drift: "0.0800"
}
A1 answer to Save plan: "Note Plan saved ×"
A2 allocation, plan saved (95 % + 5 % cash): %{
  has_plan: true,
  top_level_target_sum: "1.00",
  drift_basis: "full_plan",
  cash_actual: "0.0800",
  cash_target: "0.05",
  cash_drift: "0.0300"
}
A3 the confirm text of Delete plan: ["Delete this view&#39;s plan? The Wealth page falls back to actual-only for it."]
A4 answer to Delete plan: "Note Plan deleted ×"
A5 Classifications page after the delete: %{
  plan_exists: false,
  empty_state: true,
  cash_input_on_page: false,
  stored_cash_target: Decimal.new("0.05")
}
A6 allocation after Delete plan: %{
  has_plan: true,
  top_level_target_sum: "0.05",
  drift_basis: "allocated_portion",
  cash_actual: "0.0800",
  cash_target: "0.05",
  cash_drift: "-0.9200"
}
A7 Wealth basis line: "Plan on Strategy · Σ target top level: 5.0% — drift against the allocated portion · View Everything · as of 2026-11-24"
A8 Wealth shows the no-plan hint: false
A9 Wealth cash row: "Cash 80.00 8.0% 5.0% -920.00 EUR"
A9a Overview, basis of the Off target card: "View Everything — no active plan on Strategy · Categories drifting more than ±5 pp from their target weight."
A9b Overview, the card's row: "Cash 92.0 pp below target · -920.00 EUR"
A10 allocation on the asset-class tree, same view: %{
  has_plan: true,
  top_level_target_sum: "0.05",
  drift_basis: "allocated_portion",
  cash_actual: "0.0800",
  cash_target: "0.05",
  cash_drift: "-0.9200"
}
.C1 stored cash target after Delete plan: Decimal.new("0.05")
C2 Create plan: the Cash field shows 5 again: true
C3 after create, blank Cash, save, delete: cash target, has_plan: {nil, false}
C4 plan rows left: [{nil, "active", nil}]
.B1 GET allocation with the plan: %{
  "cash" => %{
    "actual_weight" => "0.08",
    "distributed" => false,
    "drift_value" => "30",
    "drift_weight" => "0.03",
    "market_value" => "80",
[... 46 more lines in the private evidence ...]
```

**Cost of leaving it.**

- 6 sentences in 5 places promise actual-only after the delete (the confirm dialog, the product documentation twice, the API reference, the tool description, the context's docstring); 1 test pins the promise without a cash target.
- After the delete every tree of the view, 2 built-in ones included, stays in target mode; Wealth's Target and Drift columns and the Overview's card keep showing.
- The figure the operator then reads: cash 80.00 EUR of 1,000.00 EUR, stored target 5 %, shown as "92.0 pp below target · -920.00 EUR" on the Overview and "-920.00 EUR" on Wealth, where the plan a click earlier read +30.00 EUR.
- 0 controls on any screen for the stored figure once the plan form is gone; 4 steps to remove it by hand, 1 extra call for the agent.

**Proposed fix.**

It follows the decision of R-136 (G1-02). Under (A), the cash target is the view's: the confirm text says what stays ("the view's cash target of 5 % stays and keeps steering"), the empty state shows the view's cash target with its own input (or the Cash field moves out of the plan form into the section's head), the six sentences are corrected, and the delete test gains a cash target. Size S, in `classifications_live.ex` and the docs; no ADR amendment beyond R-136 (G1-02)'s. Under (B), deleting the version deletes its cash target and the sentences become true. Either way `Targets` keeps the delete; no rule moves into the web layer.

**Second reading.**

- Lens: reach and decided. Refuted: no. Severity it would defend: S2.

  Reach holds. The reproduction used the screen's own form and button and DELETE /plans/:id. delete_soll_plan (classifications_live.ex:2073-2098) and delete_plan_rows (targets.ex:814-824) remove only the tree's row; no guard clears or names the view's cash plan, and plan_soll's second branch (allocation.ex:297-304) keeps has_plan true. The only cash input on any screen sits inside the plan form (:1517-1541), not in the empty state (:1592-1601). Decided in part: the cash target is per view (ADR-0020:85), a cash target alone opens target mode (allocation.ex:255-259; DESIGN.md:2511-2514; product-documentation.md:1570-1572), and the renormalised drift is ADR-0040 §2 as built (allocation.ex:926-935). So the "92.0 pp" figure is not this finding's own defect: one PUT cash_target reaches it without any delete, and keeping the cash target is right when another tree of the view has a plan. No record accepts the delete's outcome, though: story #467's criterion, ADR-0020:51-53, targets.ex:722-726, the confirm text (:1572) and the tool description all promise actual-only, and that is false with a cash target stored. A misleading answer in normal use: S2 stands, with the fix a wording and one control.

### R-028 (G1-04), S2: Wealth's "Create a plan" link on a built-in tree opens a page that has no plan control and does not say why; the API and MCP write a plan there all the same, and that plan then steers Wealth and puts the plan dot on the tree's page, where no screen can show, edit or delete it

- **Class:** dead control; coverage (a write with two doors of three)
- **Stands against:** `lib/portfolixir_web/live/portfolio_live.ex:5975-5977`: "the no-plan hint sends the maintainer straight to the right `(view, classification)` plan rather than editing blind"; `test/portfolixir_web/live/classifications_live_test.exs:1055-1061` (the link's story): "I want the classifications editor to open with that view AND classification already selected"; `docs/decisions/0008-target-weights-and-allocation.md:65-66`: "The breakdown works for custom and built-in classifications alike (e.g. asset-class drift)."; `AGENTS.md:230-234`: "**Coverage runs both ways.** … A new agent-visible capability may ship over API and MCP alone, with the reason stated, when its human view lands in the same or the next sprint; a missing view after that is a close-out finding."; `_bmad-output/planning-artifacts/design-language/DESIGN.md:2512-2514`: "so the dot and the editor never contradict each other, and the chip's title … reads true."
- **Locations:** `lib/portfolixir_web/live/portfolio_live.ex:2604-2621` (the hint and its link, no condition on the tree), `:5981-5983` (`plan_editor_path/2`), `:2546-2550` (the classification picker), `:5585-5590`; `lib/portfolixir/classifications.ex:124-128` (`default_classification/1`), `:1057-1061` (the two built-in trees); `lib/portfolixir_web/live/classifications_live.ex:2270-2271` (`assign_soll/2`: `soll: nil` for `editable: false`), `:2804` (`editable: not built_in`), `:375-383` (nothing rendered in the editor's place), `:2247-2259` (the plan dot, for every tree); `lib/portfolixir_web/components/view_switcher.ex:53-58`, `:160`; `lib/portfolixir/portfolios/targets.ex:434-446`, `:1305-1310` (`set_targets/5` checks only that the classification exists); `lib/portfolixir_web/controllers/api/v1/target_controller.ex:340-343`; `lib/portfolixir/portfolios/allocation.ex:454`, `:519-525` (the currency tree's cash rule, engine support for a plan no screen writes)
- **Who meets it:** the operator on Wealth → Allocation with the asset-class or currency tree selected and no plan ("Create a plan"), then on Classifications; the operator of an instance whose agent wrote a plan on a built-in tree through `PUT /api/v1/portfolios/:portfolio_id/targets` (`portfolixir.targets.set`).
- **Fix size:** S. **ADR amendment:** ADR-0008 only if plans on built-in trees are refused; otherwise none (design record and pinned test change)
- **On the later `main` (read, not run):** still stands. Three cited files changed, none in the cited lines: the Wealth page (`portfolio_live.ex`; no hunk touches the hint, its link or the link's builder), `AGENTS.md` and `DESIGN.md`. The other cited files are identical (compared file by file by the audit lead).
- **Audit lead's note:** Narrowed by the second reading to the link. Targets on a built-in tree over the API are ADR-0008's design, and that such a tree has no editor and still shows the plan dot is Sprint 19's pick J10 A, pinned by a test. Wealth's Target column does show such a plan's weights, so "no screen can show it" in the title overstates. ADR-0008 and the coverage rule of AGENTS.md are therefore not what the narrowed finding stands against. What no record covers is the "Create a plan" link that leads to a page with no control. The fix is the first half of the entry's option (2): on a built-in tree the hint drops the link and says where such a plan is written, and the tree's page says so in the editor's place. Option (1) would reopen pick J10 A; no ADR is amended.

**What is wrong.**

1. `Classifications.default_classification/1` answers the first custom tree, else the asset-class tree (`lib/portfolixir/classifications.ex:124-128`); Wealth's Allocation tab takes it as its default (`lib/portfolixir_web/live/portfolio_live.ex:5585-5590`), and its picker offers every tree (`:2546-2550`). Run, lines 1 and 2: with the two built-in trees only, the default is `asset_class`.
2. With no plan, Wealth renders the hint "No target plan yet — showing actual allocation only." and the link "Create a plan" to `/classifications/<id>?view=total` (`portfolio_live.ex:2604-2621`, `:5981-5983`). Nothing between `:2604` and `:2621` looks at the tree (run, lines 3 and 4).
3. On that page `assign_soll/2` sets `soll: nil` for a tree that is not editable (`lib/portfolixir_web/live/classifications_live.ex:2270-2271`; `editable: not tree.classification.built_in`, `:2804`), and the template renders the editor only `if @soll` (`:375-383`) with nothing in its place. Run, line 5, after following the link: no `#soll-editor`, no "Create plan" button, no plan form, no "Delete plan", and the word "plan" nowhere in the page's text.
4. That a built-in tree has no editor is recorded (`_bmad-output/planning-artifacts/design-language/DESIGN.md:2515-2516`: "The row shows on every tree, built-in ones included, which have no editor."; `docs/product-documentation.md:1599-1600`: "in the **Target plan** section of a custom tree's detail pane") and pinned (`test/portfolixir_web/live/classifications_view_scope_test.exs:1053-1074`). The link that leads there and what the other two doors do are in neither record.
5. `PUT /api/v1/portfolios/:portfolio_id/targets` passes the classification on (`lib/portfolixir_web/controllers/api/v1/target_controller.ex:340-343`), and `Targets.set_targets/5` checks only that it exists (`lib/portfolixir/portfolios/targets.ex:437`, `:1305-1310`). Run, lines 6, 7 and 13: `200` on the asset-class tree and on the currency tree, and a plan exists.
6. The allocation steers by that plan: Wealth reads "Plan on Asset class · Σ target top level: 50.0% — drift against the allocated portion" and drops the hint (run, lines 8 and 9); the engine carries a rule of its own for a plan on the currency tree (`lib/portfolixir/portfolios/allocation.ex:454`, `:519-525`). Wealth then has no link into the tree's page at all (run, line 10: only the navigation's `/classifications`).
7. The tree's page still has none of the four controls (run, lines 11 and 14), and its view chip now carries the plan dot with the title "Has a target plan for the current classification" (`classifications_live.ex:2247-2259`, `lib/portfolixir_web/components/view_switcher.ex:53-58`, `:160`; run, line 12), which the design record defines as "the plan the editor below shows" (`DESIGN.md:2511`). For such a plan the operator has no screen to read its weights as inputs, change them, version it or delete it; Wealth shows its effect only.
8. The control: a custom tree on the same route gets the section and "Create plan" (run, line 15).

**Reproduction.**

Scratch test `test/audit_scratch/g1_04_test.exs` in the slot's checkout (removed after the run), modelled on `test/portfolixir_web/live/portfolio_live_test.exs:2542-2563` and `test/portfolixir_web/live/classifications_view_scope_test.exs:1056-1074`. It is the reader's reproduction with the link followed by a click, the write sent through the route instead of the context, the currency tree and the control added.

_(scratch test source and run command: in the private evidence held by the owner)_

**Observed output.**

```
Running ExUnit with seed: 0, max_cases: 24
Excluding tags: [:browser]

1 the trees of a fresh instance: [{"asset_class", true}, {"currency", true}]
2 Wealth's default tree: {"asset_class", true}
3 Wealth's hint on that tree: "No target plan yet — showing actual allocation only. Create a plan"
4 its link is the tree's page with ?view=total: true
5 the page the link opens: %{
  soll_editor: false,
  create_plan_button: false,
  plan_form: false,
  delete_plan_button: false,
  page_says_target_plan: false,
  page_says_plan_anywhere: []
}
6 PUT targets on the asset-class tree: {200, [%{"category_id" => 1122, "target_weight" => "0.5"}]}
7 a plan exists on the built-in tree: true
8 Wealth basis line with that plan: "Plan on Asset class · Σ target top level: 50.0% — drift against the allocated portion · View Everything · as of 2026-11-24"
9 Wealth still shows the hint: false
10 links from Wealth into Classifications: ["/classifications"]
11 the tree's page with a stored plan: %{
  soll_editor: false,
  create_plan_button: false,
  plan_form: false,
  delete_plan_button: false,
  page_says_target_plan: false,
  page_says_plan_anywhere: []
}
12 the plan dot on the Everything chip, and its title: {true, ["Has a target plan for the current classification"]}
13 PUT targets on the currency tree: 200
14 the currency tree's page with a stored plan: %{
  soll_editor: false,
  create_plan_button: false,
  plan_form: false,
  delete_plan_button: false,
  page_says_target_plan: false,
  page_says_plan_anywhere: []
}
15 control: a custom tree's page: %{soll_editor: true, create_plan_button: true}
.
Finished in 0.3 seconds (0.00s async, 0.3s sync)
1 test, 0 failures
```

**Cost of leaving it.**

- 1 link on the Allocation tab of every instance that has no custom tree yet (the asset-class tree is the default there), and on both built-in trees whenever they are picked, that ends on a page with 0 of the editor's 4 controls and no sentence saying why.
- 2 built-in trees on which a plan has two doors (API, MCP) and no screen: its weights, versions and delete are reachable by the agent only, while Wealth and the plan dot show that it exists (run, lines 8 and 12), and the Overview's "Off target" card reads it when the built-in tree is the default tree (traced, `lib/portfolixir_web/live/dashboard_live.ex:1099-1101`; not run).
- 1 design sentence ("the dot and the editor never contradict each other") that such a plan makes untrue.

**Proposed fix.**

Decide once whether a built-in tree carries a plan on the screen.
(1) Yes, as ADR-0008 reads: the Target plan section renders for built-in trees too. Size M; not checked here whether the editor's position rows work on a tree whose membership is derived from the security's fields. It amends the design record (`DESIGN.md:2515-2516`) and the pinned test, no ADR.
(2) No: Wealth's hint on a built-in tree drops the link and says where such a plan is written, the tree's page says so in the editor's place, and either the two doors stay with that reason stated in the reference (AGENTS.md "API And MCP Coverage") or `Targets.set_targets/5` refuses a built-in classification, which amends ADR-0008. Size S.
Either way the condition belongs to the context (one predicate "this tree takes a plan" that Wealth's hint, the Classifications page and the write share), not to a second `built_in` test in each LiveView.

**Second reading.**

- Lens: reach and decided. Refuted: no. Severity it would defend: S2.

  Half of it is decided. Targets and drift on a built-in tree over the API are ADR-0008:65-66 ("custom and built-in classifications alike"), with engine support (allocation.ex:519-525) and product-documentation.md:1773-1774. That such a tree has no editor and still gets the plan dots is the owner's pick J10 A (ux-design-2026-10-04-sprint19.md:1153-1155; DESIGN.md:2515-2516), pinned by classifications_view_scope_test.exs:1053-1074; a dot there can only mean an API-written plan. Wealth's Target column shows that plan's weights, so "no screen can show it" overstates, and the two-way rule speaks of a new capability, not a door from ADR-0008. The link survives both lenses: portfolio_live.ex:2604-2621 renders "Create a plan" without looking at the tree, plan_editor_path (:5981-5983) points at the tree's page, and assign_soll (classifications_live.ex:2270-2271) renders nothing there. No record or test covers it (the hint's tests use custom trees, portfolio_live_test.exs:2541-2563, :2630-2660). Reach is the default: only the operator or the demo seed creates a custom tree (classifications_live.ex:1631), so default_classification (classifications.ex:124-128) gives every fresh instance the asset-class tree. A dead control on the first visit: S2 for the link alone, fix size S.

### R-029 (G1-05), S2: "Delete plan" decides by the status the editor loaded: after another writer activated a successor, the click deletes the newly active plan the page never showed, keeps the plan on screen (now archived) and answers "Plan deleted"

- **Class:** seam crossed (one page, two addressing rules for the same plan: save by plan id, delete by view); missing pin
- **Stands against:** `docs/product-documentation.md:1702-1704`: "**Delete plan** on a draft or archived version removes just that version, with its category and position targets; on the active plan it keeps its ADR-0020 meaning (the scope falls back to actual-only)." The version on screen is archived at the click, and another version is removed. Also `lib/portfolixir/portfolios/targets.ex:335-336` (`writable_plan/1`): "The one rule the plan-addressed writes below, the SOLL editor and the API's `plan_id` read." and `docs/decisions/0027-plan-versions-and-depot-snapshots.md:88-94` (note of 2026-10-08: a write names its version; an archived one "is refused there: it steers nothing").
- **Locations:** `lib/portfolixir_web/live/classifications_live.ex:2073-2098` (`delete_soll_plan/1`), `:1880-1884` (the event), `:2103-2108` (`soll_scope/1`, the save's addressing), `:2051-2060` (the save's answer to "archived meanwhile"), `:2284-2300` (`build_soll/5`: `editing_version?` is read once, at load), `:1569-1575` (the button and its confirm text); `lib/portfolixir/portfolios/targets.ex:729-742` (`delete_plan/4`: resolves the scope's active plan at call time), `:750-754` (`delete_plan_version/2`), `:1223-1228` (`get_active_plan/3`)
- **Who meets it:** the operator on Classifications, "Target plan", with the editor open on the active plan while the agent (`portfolixir.plans.duplicate`, `portfolixir.targets.set` with `plan_id`, `portfolixir.plans.activate`) or a second tab activates a successor; then "Delete plan".
- **Fix size:** S. **ADR amendment:** none
- **On the later `main` (read, not run):** unchanged. Neither cited code file changed (the plan editor screen, the targets context), nor ADR-0027; the product documentation changed elsewhere, not in the cited lines (compared file by file by the audit lead).
- **Audit lead's note:** The second reading corrects two points. `writable_plan/1` and ADR-0027's note of 2026-10-08 govern writes into a version, and a delete is not one; what the finding stands against is `docs/product-documentation.md:1702-1704` alone. The fix the records state is to delete the version on screen by its id. The `:plan_archived` refusal in the proposed fix is a choice, not a recorded rule.

**What is wrong.**

1. The editor keeps `soll.plan`, the version it loaded, and `soll.editing_version?`, computed once from that version's status at load (`classifications_live.ex:2295-2300`). Nothing reloads it when another writer changes plans: the LiveView has no subscription and no `handle_info` (`grep -c "subscribe\|handle_info" lib/portfolixir_web/live/classifications_live.ex` prints 0).
2. "Save plan" names the version it shows: `soll_scope/1` sends `plan: soll.plan.id` (`:2103-2108`). If that version was archived meanwhile, the context refuses under a share lock (`targets.ex:1114-1135`, `:338`) and the page answers "Not saved: “Plan” is archived and steers nothing…" and reloads read-only (`classifications_live.ex:2051-2060`). Run as control V2 below.
3. "Delete plan" does not name the version it shows. `delete_soll_plan/1` branches on the loaded `editing_version?` (`:2078-2091`): `true` goes to `Targets.delete_plan_version/2` by id; anything else goes to `Targets.delete_plan(actor, portfolio_id, classification_id, view: …)`.
4. `Targets.delete_plan/4` looks up the scope's active plan at call time (`targets.ex:731-733`, `get_active_plan/3`) and deletes that plan and every target on it (`:737-740`, `delete_plan_rows/2`).
5. So with the editor loaded on plan A (active), and a successor B duplicated from A, edited and activated by another writer (A is now archived), the operator's click deletes B with its targets, answers "Plan deleted", clears `soll_plan_id` and reloads (`:2093-2094`): the page now shows A, archived and read-only, with the same weight it showed before the click.
6. The outcome matches the confirm text's promise for the scope ("The Wealth page falls back to actual-only for it": the scope has no active plan afterwards) and contradicts what the page shows: the plan named and displayed is kept, and the plan deleted was never on screen.
7. If the active plan was deleted meanwhile and nothing took its place, the same click deletes nothing and also answers "Plan deleted" (V3 below; harmless, it matches the draft path's "gone either way").

**Reproduction.**

Scratch test `test/audit_scratch/g1_05_test.exs` (removed after the run), modelled on `test/portfolixir_web/live/classifications_plan_versions_test.exs`.

_(scratch test source and run command: in the private evidence held by the owner)_

Counts, from the checkout's root:

```
grep -c "subscribe\|handle_info" lib/portfolixir_web/live/classifications_live.ex     # 0
grep -rnE "Targets\.delete_plan\(" lib | wc -l                                        # 1 (classifications_live.ex:2088)
grep -rnE "Targets\.delete_plan_version\(" lib | wc -l                                # 2 (classifications_live.ex:2082, plan_controller.ex:78)
```

**Observed output.**

Plan tuples are `{id, name, status, [category weights]}`.

```
V1 page loaded on plan id=80 name=Plan status=active, Equity field 50
V1 stored before the other writer: [{80, "Plan", "active", ["0.5"]}]
V1 stored after duplicate/edit/activate: [{81, "Plan 2027", "active", ["0.7"]}, {80, "Plan", "archived", ["0.5"]}]
V1 page before the click still shows Equity=50: true
V1 confirm text on the button: ["Delete this view's plan? The Wealth page falls back to actual-only for it."]
V1 answer after the click: "Note Plan deleted ×"
V1 stored after the click: [{80, "Plan", "archived", ["0.5"]}]
V1 fetch_plan(successor 81): :not_found
V1 fetch_plan(shown 80): status=archived
V1 plan_exists?(view: nil): false
V1 allocation has_plan: false
V1 picker after the click: []
V1 page after the click, Equity field value 50 present: true; Save plan button present: false
V1 journal entries written by the click (target_plan + target): 2

V2 answer after Save plan on the stale editor: "Problem Not saved: “Plan” is archived and steers nothing. Activate it or duplicate it as a draft, then edit. ×"
V2 stored after the save: [{83, "Plan 2027", "active", ["0.7"]}, {82, "Plan", "archived", ["0.5"]}]

V3 answer: "Note Plan deleted ×"; journal entries written by the click: 0; stored: []

V4 answer: "Note Plan deleted ×"; stored: [{84, "Plan", "active", ["0.5"]}]

11 tests, 0 failures   (the three scratch files of this lane in one run; this file's four tests green)
```

Read: in V1 the click removed plan 81 ("Plan 2027", 70 %, never shown) and kept plan 80 (the one on screen), and the page then shows plan 80 again, read-only. V2 is the same interleaving for "Save plan": refused, nothing written.

**Cost of leaving it.**

- 1 of the page's 6 plan writes is not addressed by the id the page shows (save, duplicate, activate and rename go by `soll.plan.id`; create is by view by nature; delete goes by view whenever the loaded status was "active").
- Per occurrence: 1 plan row and all its target rows deleted that the operator did not see (here 1 + 1; a full plan is one row per category and position), 1 journal entry each, no undo on any screen; the scope falls back to actual-only on Wealth, and the plan the operator meant to remove stays stored as archived.
- `Targets.delete_plan/4` has 1 caller in `lib/` (this one) and 2 in tests; the API and the companion only delete by id (`DELETE /api/v1/plans/:id`, `plan_controller.ex:78`).
- How often: only when another writer activates a successor in the scope while the editor stays open without an event that reloads it (the page has no subscription; a plan-picker change, a save, a duplicate, an activation or a rename each reload).

**Proposed fix.**

The page deletes the version it shows, by id, at every status (`Targets.delete_plan_version/2`), and checks first, in the same transaction, that the version still has the status the page loaded: one that was active at load and is archived at the click is answered as the save answers it (the `:plan_archived` refusal and a reload on that version), so the confirm text's promise ("falls back to actual-only") is never kept on another plan nor broken silently. `Targets.delete_plan/4` then has no caller in `lib/` and can go with its two tests. One red test: V1 above with the assertions turned round. Size S. No ADR amendment: `docs/product-documentation.md:1702-1704` and ADR-0027's note of 2026-10-08 already state the rule; ADR-0020's meaning of deleting the active plan stays.

**Second reading.**

- Lens: reach and decided. Refuted: no. Severity it would defend: S2.

  Not refuted. REACH: the click goes through the real button, and the other writer's three calls are what PlanController.duplicate/activate (plan_controller.ex:39-52), the targets PUT with plan_id and the page's own events (classifications_live.ex:1806, :1819) run. No earlier guard: unless_view_gone/3 (:1969-1977) checks only that the view exists; the page subscribes to nothing, so editing_version? (:2295) stays as loaded while delete_plan/4 (targets.ex:731) resolves the active plan at the click. The project treats this interleaving as real: the #1187 save branch (:2051), #1091's guard on delete (:1962-1968), commit 457bddf1. DECIDED: nothing in docs/decisions, ideas.md, the three triages or N-01..N-93 covers a stale delete; product-documentation.md:1702-1704 says the archived version on screen is the one removed. Weakening points, none sufficient: the scope outcome equals the confirm text and delete_plan/4's doc (targets.ex:719-727); the journal keeps the rows; the reload shows the kept plan as archived. Correction to the evidence: writable_plan/1 and ADR-0027's note of 2026-10-08 govern writes into a version, and DESIGN.md:2860-2862 says a delete is not one, so the proposed :plan_archived refusal is a choice, not a recorded rule; deleting the shown version by id is what the docs state. S2 holds: a misleading answer and an unseen plan lost; no figure is wrong, so not S1.
