defmodule PortfolixirWeb.Api.V1.Contract do
  @moduledoc """
  The **contract-version read** (ADR-0044 §8, issue #752): what the API and
  MCP surface offers and when it last changed, pollable the way `?since=` is
  pollable for rows.

  A code-maintained manifest: dated entries, each naming the endpoints,
  tools and MCP prompts the change touched (and the parameters it added to
  existing ones). The newest entry's `version` and `date` are the contract's.
  A meta-test (`test/portfolixir_web/controllers/api_v1_contract_meta_test.exs`)
  ties the router's `/api/v1` inventory and the MCP companion's tool and
  prompt inventories to the union of these entries in **both directions**, so
  a route, tool or prompt added, renamed or removed without a manifest entry
  fails the build — the surface cannot change without saying so.

  Not a changelog document and not a description rewrite: an entry is one
  dated statement of *which parts of the surface moved*, for a consumer that
  cached its tool descriptions at connect time.

  Maintaining it: append a new entry at the **head** of `@entries` with the
  next integer `version`, today's date, a one-sentence `summary`, the
  `endpoints` ("VERB /api/v1/path"), `tools` and `prompts` it adds, and
  `parameters` (free text, one per changed read) for a parameter added to an
  existing surface. Removals are listed under `removed_endpoints` /
  `removed_tools` / `removed_prompts` so the union stays exact.
  """

  @type entry :: %{
          version: pos_integer(),
          date: Date.t(),
          summary: String.t(),
          endpoints: [String.t()],
          tools: [String.t()],
          parameters: [String.t()],
          removed_endpoints: [String.t()],
          removed_tools: [String.t()],
          prompts: [String.t()],
          removed_prompts: [String.t()]
        }

  # Newest first.
  @entries [
    %{
      version: 16,
      # Sprint 20's commit group β (what the ledger reports about it), after
      # Sprint 19 PR β's 15: the group's one entry, opened by its first
      # surface change (B1); B2 rides it, and B3 and B4 extend it.
      date: ~D[2026-10-08],
      summary:
        "Sprint 20 β, what the ledger reports about it, the ADR-0015 amendment of " <>
          "2026-10-07: a booking's fees and taxes are in its cash account's currency, the " <>
          "currency of the cash leg they are part of, and every reader now converts them " <>
          "from it. B1, a cross-currency closed trade is in one currency: the FIFO matcher " <>
          "adds a trade's fees and taxes to quantity x price only after converting them " <>
          "into the price's currency at the trade's own stored settlement_fx_rate (fee / " <>
          "rate), never a hub rate, so basis, proceeds, realized_pnl_abs and " <>
          "realized_pnl_pct, a lot's buy_fees and buy_taxes, a closed trade's sell_fees and " <>
          "sell_taxes and the annualized return move on such a trade, and realized_base " <>
          "with them; a trade booked in its account's currency or in a third currency, a " <>
          "trade without a stored rate and a same-currency trade read byte-identical figures " <>
          "(#1108). B2, the Costs " <>
          "report reads each fee and tax in its cash account's currency and converts it at " <>
          "the EUR hub rate of its booking date, as the performance walk has since #1051, so " <>
          "a cross-currency trade's fees and taxes move and an unconvertible cost is named " <>
          "by the account's currency (#1107); the income report reads a dividend's cash and " <>
          "withheld tax in its cash account's currency too, so a foreign security's dividend " <>
          "credited to an account in another currency moves, and its detail's currency " <>
          "names the account's; and the deposits-and-withdrawals report reads a deposit's or " <>
          "removal's cash in its cash account's currency, so one booked in another currency " <>
          "with a stored settlement rate moves. B3, a zero cost basis has no return (#1142), " <>
          "plan D-6: a closed trade whose basis is 0 and a holding or open lot whose cost is " <>
          "0 answer realized_pnl_pct or unrealized_pnl_pct null, never \"0\", on every read " <>
          "that serves them, with the rule in the payload's computation_basis, and " <>
          "annualized_return_reason gains no_cost_basis, before the 365-day rule and the " <>
          "solver's. No computation version moves: none of these reads is a " <>
          "registered derived analytic (ADR-0039), so no stored value serves the old " <>
          "figures, and the walk's analytics keep theirs, the walk having read the account's " <>
          "currency since #1051 (entry 14). No route or tool is added; B3's two tool " <>
          "descriptions name the new reason, and the schema budget's ceilings move down (D-10).",
      endpoints: [],
      tools: [],
      parameters: [
        "GET /api/v1/securities/:security_id/trades (portfolixir.trades.list): on a cross-currency trade booked in the security's currency (ADR-0015), each open lot's buy_fees and buy_taxes and each closed trade's buy_fees, buy_taxes, sell_fees and sell_taxes are converted from the cash account's currency at the trade's own stored settlement_fx_rate (fee / rate), so they, basis, proceeds, realized_pnl_abs, realized_pnl_pct, the lots' costs and annualized_return are all in currency_code. Identity 1: buy 10 at 100 USD settled 800.00 EUR with 5.00 fees and 1.00 taxes, sell 10 at 120 USD settled 960.00 EUR with 3.00 fees: basis 1007.5, proceeds 1196.25, realized_pnl_abs 188.75 USD, where they read 1006, 1197 and 191. A trade booked in its account's currency or in a third currency, one without a stored rate and a same-currency trade are unchanged. computation_basis.fees_and_taxes, new, states the rule (B1, #1108)",
        "GET /api/v1/realized_gains (portfolixir.cashflow.realized_gains): each trade's basis, proceeds, realized_pnl_abs, realized_pnl_pct and annualized_return move as on the trades read, and realized_base, summary.realized_total, the hit rate and the annual matrix with them; identity 1 reads realized_base 151 EUR, the cash the round trip moved (957.00 - 806.00), where it read 152.8. computation_basis.fees_and_taxes, new, states the rule; the close-date conversion is unchanged (B1, #1108)",
        "GET /api/v1/costs (portfolixir.cashflow.costs): each fee and tax, a trade's legs and a standalone cost's cash alike, is read in its cash account's currency and converted from it at the EUR hub rate of its booking date, where it was read in the booking's currency, which on a cross-currency trade is the security's; a booking without a cash account is read in its own. Identity 2: buy 10 at 100 USD settled 790.00 EUR with 5.00 fees and 1.00 taxes reads fees 5, taxes 1, total 6 EUR, where it read 4, 0.8 and 4.8, equal to the walk's trade costs of the day. An unconvertible cost is excluded and named by the account's currency. computation_basis.currency, new, states the rule; series, window, reference and gaps are unchanged (B2, #1107)",
        "GET /api/v1/portfolios/:portfolio_id/income (portfolixir.portfolios.income): a booking's cash and withheld tax are read in its cash account's currency and converted from it, where they were read in the booking's currency, so a dividend of a USD security credited 80.00 EUR net with 20.00 EUR withheld to a EUR account reads gross 100, tax 20, net 80 EUR, where it read 80, 16 and 64, and its transactions row's currency is the account's (EUR), the currency native_gross, native_tax and native_net are in; positions keep grouping by and naming the booking's currency in security_currency. conversion_note says it (B2, #1107)",
        "GET /api/v1/external_flows (portfolixir.cashflow.external_flows): a deposit's or removal's cash is read in its cash account's currency and converted from it, where it was read in the booking's currency, so a deposit booked in USD with a stored settlement rate, 100.00 credited to a EUR account, 1 EUR = 1.25 USD, reads deposits 100 EUR, where it read 80; a flow without a cash account is read in its own currency, and an excluded flow is still named by its cash account. computation_basis.currency, new, states the rule, and conversion_note says it; series, window, reference, gaps and excludes are unchanged (B2, #1107)",
        "GET /api/v1/securities/:security_id/trades (portfolixir.trades.list): a closed trade whose basis is \"0\" (a buy booked at a price of 0 with no fees or taxes, a bonus or free share) reads realized_pnl_pct null, where it read \"0\", and annualized_return null with annualized_return_reason no_cost_basis, where it read no_sign_change or holding_period_under_365_days: the reason comes first, with no cost there is nothing to annualize. An open lot whose cost, quantity x buy_price_native, is \"0\" keeps its unrealized_pnl_abs and reads unrealized_pnl_pct null, where it read \"0\". 12 bonus shares at 0.00, 8 sold at 41.25: realized_pnl_abs 330, realized_pnl_pct null; the 4 left at a latest close of 41.80: unrealized_pnl_abs 167.2, unrealized_pnl_pct null. computation_basis.realized_pnl_pct and computation_basis.unrealized_pnl_pct, new, state the rules, and computation_basis.annualized_return names the reason; the description names it in fewer bytes (B3, #1142)",
        "GET /api/v1/realized_gains (portfolixir.cashflow.realized_gains): a trade whose basis is \"0\" reads realized_pnl_pct null, where it read \"0\", and annualized_return_reason no_cost_basis, as on the trades read; realized_pnl_abs, realized_base and every figure over them are unchanged. computation_basis.realized_pnl_pct, new, states the rule; the description names it in fewer bytes (B3, #1142)",
        "GET /api/v1/portfolios/:portfolio_id/holdings (portfolixir.holdings.list): a holding whose cost_basis is \"0\" (shares delivered in at no cost, a spin-off, or bought at a price of 0) keeps its unrealized_pnl_abs and reads unrealized_pnl_pct null, where it read \"0\"; 15 delivered in and valued at 22.40 read unrealized_pnl_abs 336, unrealized_pnl_pct null. The same null under security_id= (one position) and under fields=. The envelope's computation_basis.unrealized_pnl_pct, new, states the rule (B3, #1142)",
        "GET /api/v1/portfolios/:portfolio_id/holdings (portfolixir.holdings.list) and GET /api/v1/securities/:security_id/trades (portfolixir.trades.list), #1142's last sibling: a holding or an open lot whose base_cost is \"0\" keeps its price_return_abs, currency_return_abs and total_return_base_abs and reads price_return_pct, currency_return_pct and total_return_base_pct null, where they read \"0\" beside the null unrealized_pnl_pct; 15 delivered in at 22.40 read total_return_base_abs 336, the 4 bonus shares left 167.2, every percentage null. computation_basis.decomposition_pct, new on both envelopes, states the rule (B3, #1142)"
      ],
      removed_endpoints: [],
      removed_tools: [],
      prompts: [],
      removed_prompts: []
    },
    %{
      version: 15,
      # Sprint 19's PR β (a stranger's first run, and the agent's reads), after
      # PR α's 14: the lane PR's one entry, opened by its first surface change
      # (B5); B2's and B3's surface changes ride it. Dated at promotion, the
      # day after α's entry: entries_since/1 is strictly after, so an agent
      # that polled after α landed (2026-10-06) still sees this one.
      date: ~D[2026-10-07],
      summary:
        "Sprint 19 PR β, a stranger's first run and the agent's reads: B5, the performance, " <>
          "the benchmark comparison and the contribution analysis read the Everything scope " <>
          "with no view, every account in every portfolio, each counted once, in EUR, the hub, " <>
          "where the screen's Everything scope is computed in the first portfolio's base " <>
          "currency (#1056, D-7); the classification screen's all-portfolios category result " <>
          "is a read, and every category-result form names the members it leaves out " <>
          "(#1091's read half); a benchmark= security a merge took away is still refused, now " <>
          "naming the survivor when that is a benchmark security (#959). B2, a stored logo " <>
          "whose file is gone from the logo directory is marked at startup, and its path is " <>
          "never cleared: the logo status read carries file_missing, has_logo is false for " <>
          "such a logo while its path, source and lock read as stored, and the missing-logo " <>
          "sets include it whatever its lock, as portfolixir.securities.list's description " <>
          "says; there is no logo-status tool, and an MCP client reads the mark as " <>
          "logo_file_missing in a security's attributes (securities.get, or securities.list " <>
          "under projection=full) (#933). B3, the " <>
          "companion answers a gateway error on a write, or a write's " <>
          "unreadable answer, as an unknown outcome, names a body that is not JSON by its " <>
          "status and an excerpt, and exits 1 when its HTTP port is taken or invalid (#1043, " <>
          "#1045).",
      endpoints: [
        "GET /api/v1/performance",
        "GET /api/v1/performance/benchmark",
        "GET /api/v1/performance/contribution",
        "GET /api/v1/category-results"
      ],
      tools: [],
      parameters: [
        "GET /api/v1/performance, GET /api/v1/performance/benchmark and GET /api/v1/performance/contribution, new: the view reads of the performance family with no view, over Performance.for_view(nil), Benchmark.for_view(nil) and Contribution.for_view(nil), every account of every portfolio, each counted once, beside GET /api/v1/valuation. Each answers in EUR, the hub, never in the first portfolio's base currency, in its view form's shape with view_id null (and portfolio_id null on the contribution) and no view echo, and takes its view form's parameters: period=, year=, from=/to=, series= where the view form takes it, and benchmark= on the comparison, required as there. None takes a scope: a view= or a portfolio_id= is ignored, as on GET /api/v1/valuation. A bad period is a 422 on period, a missing or refused benchmark a 422 on benchmark. computation_basis.input_series closes on the scope, every account in every portfolio with no view, and the currency, EUR through the hub, and says that the screen's Everything scope is computed in the first portfolio's base currency, so the two differ when that is not EUR. Every figure is the engine's; no computation version moves, and the view and portfolio forms are unchanged (B5, #1056, D-7)",
        "portfolixir.views.performance, portfolixir.views.benchmark and portfolixir.views.contribution: id is optional now, as on portfolixir.views.valuation; omitted, each reads its view-less route above (GET /api/v1/performance, /performance/benchmark, /performance/contribution), benchmark staying required on the comparison; with an id each is unchanged. The scope-twin sentences of the three pairs say the view tool reads every account in EUR with no id, where they said it needs an existing view id and that the portfolio tool is the only read until a view exists. The schema budget pays for it: the needs-a-view text the six descriptions carried is dropped and the ceilings are lowered to the figures measured (B5, #1056, D-10)",
        "GET /api/v1/category-results?classification_id=, new: the per-category result across every portfolio with no view, CategoryResult.for_all_portfolios/2, the roll-up the classification screen shows: scope all, portfolio_id and view_id null, base_currency EUR, no view echo; a member held in a portfolio whose base currency is not EUR has no EUR cost and is excluded as missing_base_cost, and basis_note closes on that scope. A missing classification_id is a 422, an unknown one a 404. Every form of the read (the portfolio read, its view= narrowing, the view read and this one) now also carries excluded_members: each member the roll-up leaves out, once across the tree, sorted by name without regard to case, ties by security_id, with security_id, security_name, category_id (the category it is filed under), reason and native_costs (its cost in the currency it was paid in, [{amount, currency}] with amount a Decimal string, the result's currency first and the others by code, when only that currency keeps it out of a EUR sum, else []), and every form's basis_note names it; every other field and figure is unchanged. The every-portfolio read takes no view= or portfolio_id=: either is ignored, as on GET /api/v1/valuation. portfolixir.portfolios.category_results takes neither portfolio_id nor view for this read, which it used to refuse, and its description names excluded_members (B5, #1091's read half)",
        "benchmark=security:<id> on GET /api/v1/portfolios/:portfolio_id/performance/benchmark, GET /api/v1/views/:view_id/performance/benchmark and GET /api/v1/performance/benchmark (portfolixir.portfolios.benchmark and portfolixir.views.benchmark, which pass the body through): a security a merge took away is still refused with 422 errors.benchmark [\"is not a benchmark security\"] and, when the survivor at the live end of its merge chain is a flagged benchmark security, now also carries errors.merged_into {kind: \"security\", id} naming it, as the merged-away reads do (ADR-0050 §12), so a retry with that id compares. A survivor that is not flagged, a chain that ends at a row deleted since, an id no merge names and a security that is not flagged answer the body they answered before; the benchmark selector's description on portfolixir.portfolios.benchmark names merged_into (B5, #959)",
        "GET /api/v1/securities/:security_id/logo, and the PUT, DELETE and discover answers that carry the same status, add file_missing (a boolean): true when the instance's startup reconciliation found no file in the logo directory for the stored path. has_logo is now false for such a logo; path, source and locked read as stored. Storing a logo (PUT, discover, background discovery) or removing one (DELETE) clears it, and the next start clears it when the file is back (B2, #933)",
        "GET /api/v1/securities?logo_status= and ?data_quality=missing_logo (portfolixir.securities.list, whose data_quality sentence now reads \"missing_logo (none and unlocked, or file gone)\" where it read \"missing_logo (no stored logo, not locked to none)\", in fewer bytes): missing now also holds a stored logo whose file is gone, whatever its lock, a manual one included, beside a security with no logo that is not locked to none; present holds a stored logo whose file is not missing. data_quality=missing_logo still leaves out a benchmark and a retired security, and the Overview's logo count and the securities page's dq=missing_logo list are the same set. An MCP client has no logo-status tool; it reads the mark as logo_file_missing: true in the security's attributes, which portfolixir.securities.get returns and portfolixir.securities.list returns under projection=full (B2, #933)",
        "GET /api/v1/securities/:id/merge_preview (portfolixir.securities.merge_preview): a logo whose file is marked missing is no logo in identifiers.differences, so a marked logo on the source is left out and one on the target reads null against the source's present logo; the logo still follows the target, as before (B2, #933)",
        "The MCP companion: a write answered by a gateway 502, 504, 520 or 524 (except a 502 in the API's own errors envelope), or a 2xx whose body it cannot read, answers outcome unknown, with the advice to re-read before retrying, as a lost connection does; a body that is not JSON is named by its status and a short excerpt, never surfaced as a parse error; a read keeps its rule and is never an unknown outcome (B3, #1045)",
        "The MCP companion over HTTP (PORTFOLIXIR_MCP_TRANSPORT=http): when its port is taken or invalid it exits 1, naming the address and the cause, where it printed its listening line and exited 0 serving nothing (B3, #1043)"
      ],
      removed_endpoints: [],
      removed_tools: [],
      prompts: [],
      removed_prompts: []
    },
    %{
      version: 14,
      # Sprint 19's PR α (the money a stranger checks first), after PR #1102's
      # 13: the lane PR's one entry, opened by its first surface change (M3);
      # M4, M6 and M7 extend it, each item named by its story. The date is the
      # entry's latest change, so a since= poller sees each extension.
      date: ~D[2026-10-06],
      summary:
        "Sprint 19 PR α, the money a stranger checks first: M3, a foreign-currency " <>
          "cash account whose balance counted zero on some days of the window because " <>
          "its currency had no rate path to the base currency is named on the " <>
          "performance, the contribution and the benchmark reads, in both forms, with its " <>
          "balance in its own currency, its days and the date its first rate arrived, so the jump " <>
          "that first rate brings into the money result and the currency effect on " <>
          "cash reads as what it is (#1055, ADR-0051 §10). M4, with no field added and no " <>
          "computation version moved beyond M3's, converts a cross-currency trade's fees " <>
          "and taxes to the base currency from its cash account's currency, the currency " <>
          "they are recorded in, not from its price currency: on such a trade the " <>
          "contribution read's position costs, contributions, totals and row order and its " <>
          "cash_currency_effect move, a trade with no rate for its price currency moves its " <>
          "fees and taxes from net_flows into costs, and the snapshot comparison's " <>
          "transaction_costs, real_ttwror_before_costs and cost_recovery move (#1051). " <>
          "M6, with no figure changed and no schema byte added, has every valuation read " <>
          "count the cash accounts it leaves out of total_cash for want of a rate path " <>
          "(unvalued_cash_count) and say so in its valuation_note, with or without the " <>
          "position rows, so the routine roll-up read no longer hides that gap (#1081, D-3). " <>
          "M7 names a bond priced on two scales in either direction and reads a security " <>
          "with no asset class, stored or inferred, that carries bond master data as a bond: " <>
          "the detail read now answers a non-null bond reading, with its figures, for such a " <>
          "security; bond.two_scales carries its direction, forward or reverse; and " <>
          "data_quality takes two_scales, the Overview's set (#1068, D-15). It also changes " <>
          "the asset class a create or update stores for a security written without one: " <>
          "legal forms and structured-product words match as whole words, so a name like " <>
          "\"Muster Computer Corp\" is now stored as equity and a name that only contains " <>
          "\"sa\" or \"actions\" inside a word is now stored unclassified (#1078).",
      endpoints: [],
      tools: [],
      parameters: [
        "GET /api/v1/portfolios/:portfolio_id/performance and GET /api/v1/views/:view_id/performance (portfolixir.portfolios.performance, portfolixir.views.performance) carry unvalued_cash_accounts: one entry per cash account in the scope that held a non-zero balance and counted zero for want of a rate path to the base currency on at least one day of the window or on the day before it, whose close is the start value, with cash_account_id, name, currency_code, balance (its native balance on the last such day, a Decimal string in that currency, never converted), unvalued_days (its days, the day before the window (the start value) included), unvalued_reason (no_rate), unvalued_through_end (true when it still counted zero on the window's last day) and first_rate_date (the ISO date its currency's first rate path arrived, when that falls inside the window and the account held money at zero on the day before — the day its whole balance entered the money result — else null), sorted by name; [] when every balance was valued and on an empty window. computation_basis.gaps names the field. Every other field and figure is unchanged (M3, #1055)",
        "GET /api/v1/portfolios/:portfolio_id/performance/contribution and GET /api/v1/views/:view_id/performance/contribution (portfolixir.portfolios.contribution, portfolixir.views.contribution) carry the same unvalued_cash_accounts for the contribution's window, equal to the performance read's of the same scope and window: the first rate brings such a balance's whole value into remainder.cash_currency_effect, and first_rate_date names the day. computation_basis.gaps names the field where it said that no account is named. Every other field and figure is unchanged; the MCP tools pass the field through, their descriptions unchanged (M3, #1055)",
        "GET /api/v1/portfolios/:portfolio_id/performance/benchmark and GET /api/v1/views/:view_id/performance/benchmark (portfolixir.portfolios.benchmark, portfolixir.views.benchmark) carry the same unvalued_cash_accounts (balance, unvalued_days, unvalued_through_end, first_rate_date) for the covered window, whose portfolio_ttwror and end_value_delta hold the jump a first rate brings; [] on a comparison with no covered window. computation_basis.gaps names the field. Every other field and figure is unchanged (M3, #1055)",
        "GET /api/v1/portfolios/:portfolio_id/valuation, GET /api/v1/views/:view_id/valuation and GET /api/v1/valuation (portfolixir.portfolios.valuation, and portfolixir.views.valuation with and without an id) carry unvalued_cash_count, with and without include_positions: the cash accounts in scope whose currency has no stored rate path to the base currency and whose balance is not zero, which total_cash and total_with_cash leave out; an empty such account is listed in cash_balances with valued: false and not counted. Each form's valuation_note states the rule. total_cash, total_with_cash and every other field and figure are unchanged; the MCP tools pass the field through, their descriptions unchanged (M6, #1081, D-3)",
        "GET /api/v1/securities?data_quality= (portfolixir.securities.list, whose data_quality enum and description now carry it) takes two_scales: every security the bond two-scales guard names, catalog-wide and in either direction, which is the set the Overview's data-quality line counts and the securities page's dq=two_scales lists. A member is read as a bond (below) and has a stored quote and a booked price per unit (a buy or a priced inbound delivery) on the other scale. Like missing_fx it is no catalog-hygiene set, so a retired or benchmark bond stays in it; an unknown value is still a 422 on data_quality (M7, #1068, D-15)",
        "GET /api/v1/securities/:id (portfolixir.securities.get): bond, the reading, is served for a security whose effective asset class is bond or government_bond, as before, and now also for one with no asset class, stored or inferred, that carries a maturity_date or coupon_rate and whose name is not a structured product's; such a security's bond was null and now carries its figures. A security shown under any other class, stored or inferred, keeps bond null whatever master data it carries. bond.two_scales gains direction: forward (the latest stored quote 20 to 500 times a booked price per unit, quotes near 100 beside bookings near 1, every money figure a hundred times too high) or reverse (the quote 1/500 to 1/20 of one and itself at most 5, quotes near 1 beside bookings near 100, the bond a hundred times too low in every total); unit_scale_bookings and last_unit_scale_booking keep their names and hold the bookings in the band either way, the forward finding is reported where both occur, and rule states both bands and the bond signal. Nothing is converted; every other field is unchanged (M7, #1068, D-15)",
        "POST /api/v1/securities and PATCH /api/v1/securities/:id (portfolixir.securities.create, portfolixir.securities.update) store a different asset_class for some names written without one: the inference reads S.A., SA, SAS, Actions and Aandelen as legal forms, and Turbo, Disc, Discount, Call(s), Put(s), O.End and Em.-u.Handelsg.mbH as structured-product words, only as whole words, so \"Muster Computer Corp\" is now stored as equity rather than unclassified, and a name that has only \"sa\", \"actions\" or \"aandelen\" inside a word (\"Global Transactions Group\") is now stored unclassified rather than equity. A stored class is never changed by this; the effective class GET answers for a security that stores none can change the same way (#1078)"
      ],
      removed_endpoints: [],
      removed_tools: [],
      prompts: [],
      removed_prompts: []
    },
    %{
      version: 13,
      # After Sprint 18's PR γ (PR #1102): retiring a security reached over
      # MCP — the operator's way to take a sold-out or delisted security out
      # of the catalog-hygiene checks, and the remedy
      # portfolixir.securities.delete names when research notes or
      # policy-rule versions reference a security — and the sets it clears.
      date: ~D[2026-10-05],
      summary:
        "An MCP client can retire a security: portfolixir.securities.update takes " <>
          "is_retired, which takes a sold-out or delisted security out of the catalog-hygiene " <>
          "checks and is the remedy portfolixir.securities.delete names when research notes or " <>
          "policy-rule versions reference it; a retired security, like a benchmark, is in none " <>
          "of stale_quote, missing_quote and missing_logo, so the Overview's quote, asset-class " <>
          "and logo counts drop with it (PR #1102).",
      endpoints: [],
      tools: [],
      parameters: [
        "portfolixir.securities.update takes is_retired (a boolean; anything else is refused before a request is sent) and sends it to PATCH /api/v1/securities/:id as given, where the update is journaled under the calling token like every security update: true retires a sold-out or delisted security, false restores it, and a retired security's stale quote stops counting as a price measurement in performance as before, which can restate its TTWROR history (#610). The tool stays in the book profile. portfolixir.securities.delete names portfolixir.securities.update for the retire remedy, given when research notes or policy-rule versions reference the security (bookings, quotes and events answer merge). The schema budget pays for it: securities.update's description and its currency_code, treat_quotes_as_raw and is_benchmark properties, securities.list's data_quality sentence and the delete's referenced_by example are tightened, every tested statement kept (D-10)",
        "GET /api/v1/securities?data_quality= (portfolixir.securities.list, whose description now says so), the Overview's data-quality counts and the securities page's dq= filter: a retired security is in none of stale_quote, missing_quote and missing_logo — it used to stay under missing_quote when never priced and under missing_logo always — and reactivating it puts it back in the sets it matches. The exclusion runs in the query, before limit and offset, so a paged read returns full pages; missing_fx is unchanged and keeps it. The page's dq= filters now leave out a benchmark as well, as the API and the Overview always did; the Overview's asset-class count leaves out a retired security and its link carries filter[]=is_retired:is_false; the Wealth no-price and trade-priced rows leave out a retired holding; the missing-logo lookup leaves out a retired and a benchmark security (PR #1102)"
      ],
      removed_endpoints: [],
      removed_tools: [],
      prompts: [],
      removed_prompts: []
    },
    %{
      version: 12,
      # Sprint 18's PR γ (the screens a stranger meets), after PR β's 11: the
      # lane PR's one entry, opened by its first surface change (U1); every
      # later surface change of the PR extends it, each item named by its
      # story.
      date: ~D[2026-10-03],
      summary:
        "Sprint 18, the screens a stranger meets: U1, a split is deleted the way it was " <>
          "booked, as one fact — every portfolio's row of the event in one journaled step, " <>
          "from any of its rows — so the corrected ratio can be booked right after; the " <>
          "screen's delete of a split row runs the same write, and the agent's tool is an " <>
          "admin tool (#912, ADR-0028 §1); U7, a bond's master data (coupon, payment " <>
          "frequency, maturity, issue date, denomination) is set and read on the securities " <>
          "routes, and the detail read of a bond carries the nominal held, the remaining term " <>
          "and two display-only yields, each with its computation basis, and names a bond " <>
          "priced on two scales (#330, ADR-0052).",
      endpoints: ["DELETE /api/v1/splits/:transaction_id"],
      tools: ["portfolixir.splits.delete"],
      parameters: [
        "DELETE /api/v1/splits/:transaction_id, new: deletes the split event the row belongs to, every split row sharing its security, date and normalized ratio in every portfolio, in one transaction, each row journaled with its before-image under the token; answers 200 with data.transactions, the removed rows in the transaction shape ordered by portfolio; an unknown or already deleted row is a 404, a booking of another kind a 422 on transaction_id naming DELETE /api/v1/transactions/:id; a failure on any row deletes nothing. DELETE /api/v1/transactions/:id on a split row still removes that row alone. PATCH /api/v1/transactions/:id on a split row's date, security, portfolio, type or ratio still answers 422, its message now naming DELETE /api/v1/splits/:transaction_id where it named a row-by-row delete (U1, #912)",
        "portfolixir.splits.delete, new: transaction_id (any row of the split) to DELETE /api/v1/splits/:transaction_id, hinted destructive and idempotent, in the admin set, so the full profile lists it and book and read do not; portfolixir.transactions.delete and portfolixir.transactions.update name it for a split (U1, #912)",
        "POST /api/v1/securities and PATCH /api/v1/securities/:id take, and every security payload answers, coupon_rate (percent of face per year, a Decimal string from 0 to 100, 2.5 not 0.025), coupon_frequency (annual or semi_annual), maturity_date and issue_date (ISO dates, the maturity after the issue date), face_value (the denomination, a Decimal string above 0) and face_value_currency_code; each is nullable, null clears it, an impossible value is a 422 naming its field, and they are kept when the asset class changes. coupon_rate and face_value keep 6 decimal places: a finer value is rounded half up before it is checked, as every stored amount is (3.1234567 is stored and answered as 3.123457), and a JSON number is cast as every decimal field casts one, a string being the documented form. GET /api/v1/securities/:id of a security whose effective asset class is bond or government_bond carries bond: as_of, quantity, nominal_held {amount = quantity × 100 under the hundredth convention, currency_code}, remaining_term {days, years rounded half up at scale 6, whole_years, whole_months, matured}, current_yield and yield_to_maturity {value, a ratio rounded half up at scale 6 and written without trailing zeros (0.03685, 0), price {value, date, source quote|trade}, matured, insufficient_data, missing, price_on_unit_scale (true, with value null, while the price is the last own trade price at most 5, the two-scales band's mirror)} — the yield to maturity the linear approximation (coupon + (100 − price) ÷ remaining years) ÷ price — each with computation_basis (input_series, window, reference, gaps, assumptions), and two_scales (null, or latest_quote, unit_scale_bookings and last_unit_scale_booking, the bookings on the unit scale, and the rule: a quote 20 to 500 times a booked price per unit, a buy's or a priced inbound delivery's); bond is null for any other security and on every other read (U7, #330, ADR-0052)",
        "portfolixir.securities.create and portfolixir.securities.update take the six bond fields (decimals and dates as strings, coupon_frequency annual or semi_annual, the update also null to clear), each date stating its bounded range; portfolixir.securities.get names the bond reading and its computation_basis; the sparse-fieldset enum of portfolixir.securities.list gains the six fields and bond. The schema budget pays for it: the shared bounded-date sentence and the descriptions of securities.list, .get, .create, .update and .metrics are tightened, every tested statement kept; face_value_currency_code states its code set (ISO 4217, the set currency_code takes), paid for by tightening the bond fields' and securities.update's property descriptions (U7, #330, D-10)"
      ],
      removed_endpoints: [],
      removed_tools: [],
      prompts: [],
      removed_prompts: []
    },
    %{
      version: 11,
      # Sprint 18's PR β (the operator's money surface): the lane PR's one
      # entry, opened by its first surface change (F4); every later surface
      # change of the PR extends it, each item named by its story.
      date: ~D[2026-10-03],
      summary:
        "Sprint 18, the operator's money surface: F4, the category result takes the view " <>
          "scope in the performance family's two forms, the portfolio read narrowed with " <>
          "view= and a view read across every portfolio, and states the scope it was " <>
          "computed over (#901); F5, the total across every portfolio, always in EUR over " <>
          "every account, is one read with no view to create first (#1007); F2, " <>
          "which position made how much of a period's money result, with the remainder " <>
          "lines the positions do not hold, summing exactly to the result beside the " <>
          "TTWROR, read for a portfolio or a view in the performance family's two forms, " <>
          "each with its MCP tool (FR-41, ADR-0051).",
      endpoints: [
        "GET /api/v1/views/:view_id/category-results",
        "GET /api/v1/valuation",
        "GET /api/v1/portfolios/:portfolio_id/performance/contribution",
        "GET /api/v1/views/:view_id/performance/contribution"
      ],
      tools: ["portfolixir.portfolios.contribution", "portfolixir.views.contribution"],
      parameters: [
        "GET /api/v1/portfolios/:portfolio_id/category-results (portfolixir.portfolios.category_results) takes view= (a view id): only the portfolio's positions matching the view roll up, and the active view is echoed as view: {id, name}; a malformed view is a 422, an unknown one a 404. GET /api/v1/views/:view_id/category-results, new, rolls up the positions matching the view across every portfolio, each account counted once, in EUR, a member whose cost was not paid in EUR excluded as missing_base_cost; the MCP tool reaches it with view and no portfolio_id, which is now optional (one of the two is required). Both forms answer scope (portfolio or view), portfolio_id, view_id and base_currency, and basis_note closes on a sentence naming it; every other field the read served before is unchanged (F4, #901)",
        "GET /api/v1/valuation, new: the total across every portfolio and every account, each counted once, in EUR, with no view — the unscoped union, which equals the dashboard's total when the first portfolio's base currency is EUR and no default view is set — in the view valuation's shape with view_id null and no view echo; include_positions=false returns the roll-up only, as on the view read. portfolixir.views.valuation reads it when id is omitted, id being optional now; with an id it is unchanged. No view-less performance or benchmark read is added (F5, #1007, D-5)",
        "GET /api/v1/portfolios/:portfolio_id/performance/contribution, new, with view=, period=, year= and from=/to= as on the performance read, and GET /api/v1/views/:view_id/performance/contribution, new, across every portfolio in EUR: per position security_id, name, isin, start_value, end_value, net_flows, income, costs, contribution (end_value − start_value − net_flows + income − costs), held_at_start, held_at_end, unvalued_days and unvalued_reason (no_price, no_rate or null; a day without a price or a rate path counts zero and the position stays in the sum), sorted largest first with no rank or label; remainder (interest, standalone_fees_and_taxes, cash_currency_effect, each summed from its own bookings); totals (result, the performance read's end_value − start_value − net_external_flows, positions, remainder; positions + remainder = result). Both forms carry portfolio_id and view_id (portfolio_id null on the view form), echo an active view, carry as_of and stale, and computation_basis with assumptions (the definition, the identity, base currency with the currency move included, exact while conversion quotients terminate and to 34 significant digits otherwise, the settlement difference in the currency line). An empty window answers start_date null, no positions and \"0\" lines and totals. Malformed view= or period is a 422, an unknown portfolio or view a 404. MCP: portfolixir.portfolios.contribution (portfolio_id, view, period, year, from, to) and portfolixir.views.contribution (id, period, year, from, to), read tools in every profile and scope twins of each other (F2, FR-41)"
      ],
      removed_endpoints: [],
      removed_tools: [],
      prompts: [],
      removed_prompts: []
    },
    %{
      version: 10,
      # PR γ's one entry (Sprint 17, the operator's due surfaces), after PR β's
      # 9: every later surface change of the PR extends it.
      date: ~D[2026-10-02],
      summary:
        "Sprint 17, the operator's due surfaces: every closed round-trip carries its " <>
          "annualized return, the money-weighted return per year of the trade's own flows, " <>
          "or null with the reason, on both reads that serve closed trades — and the " <>
          "realized-gains read names the sells no buy was matched to instead of dropping " <>
          "them (#984) — and the two human views due under the two-way rule landed: the " <>
          "merge-record list on Accounts & depots, whose read now counts the removed " <>
          "bookings per reason (ADR-0050 §12), and the release of manual quotes on a " <>
          "security's Quotes tab, with a new read of which quotes are manual (T-9).",
      endpoints: ["GET /api/v1/securities/:security_id/quotes/manual"],
      tools: ["portfolixir.quotes.manual"],
      parameters: [
        "GET /api/v1/realized_gains (portfolixir.cashflow.realized_gains) and GET /api/v1/securities/:security_id/trades (portfolixir.trades.list): every closed trade carries annualized_return, the round-trip's money-weighted return per year (the XIRR solver over each consumed lot's buy on its open date for its prorated cost and the sell's proceeds on the close date, in the trade's own currency, rounded to 6 places) as a decimal string, or null with annualized_return_reason: holding_period_under_365_days below 365 days of the trade's holding_period_days, or the solver's no_sign_change, no_root or amount_out_of_range; computation_basis.annualized_return states the rule, and the trades read gains computation_basis for it. Every field both reads served before is unchanged (#984)",
        "GET /api/v1/realized_gains (portfolixir.cashflow.realized_gains) carries unmatched_sells: count, and per sell security_id, security_name, date and quantity (the part no lot covered, a decimal string), newest first — the sells the FIFO matcher could not pair with a buy (an inbound delivery opens no lot; a sell larger than the shares bought leaves its remainder), which are in none of the figures, the list or the matrix; computation_basis.unmatched_sells says why. They used to be dropped without a word. GET /api/v1/securities/:security_id/trades keeps naming the same sells as orphan_sells, and its computation_basis.orphan_sells says so (#984)",
        "GET /api/v1/merges (portfolixir.merges.list): each record's manifest_summary.transactions gains deleted_by_reason, the removed bookings counted per reason (internal_transfer, collapsed_duplicate, folded_anchor, collapsed_split; only the reasons present, {} when none); transactions.deleted keeps its meaning, every removed booking (ADR-0050 §12)",
        "GET /api/v1/securities/:security_id/quotes/manual (portfolixir.quotes.manual), new: count, first and last date and the stretches of the security's manual quotes over its whole stored history, whether the quote sync can fetch it (sync_adapter), and with from and/or to the count in that inclusive range; limit (the list family's bound) caps the stretches. It is what a release of manual quotes (portfolixir.quotes.release) would remove (T-9)"
      ],
      removed_endpoints: [],
      removed_tools: [],
      prompts: [],
      removed_prompts: []
    },
    %{
      version: 9,
      # Sprint 17's PR β (Lane A, the agent's first contact): the first surface
      # change of the lane PR opened it, every later change of the lane extends
      # it. No route changes: the lane moves the MCP companion only.
      date: ~D[2026-10-01],
      summary:
        "Sprint 17, the agent's first contact: the MCP companion's tool profiles " <>
          "(PORTFOLIXIR_MCP_PROFILE read, book or full; book leaves out the admin set, every " <>
          "removal, the merges, the ISIN change and a rule's retirement), with the read-only " <>
          "switch kept as read — and " <>
          "the twin scope tools steered: valuation, performance and the benchmark comparison " <>
          "at the portfolio and the view scope each name the other, with the difference — and " <>
          "two MCP prompts, first_setup and import_converter. The prompts are MCP only: a " <>
          "prompt is an instruction to the user's agent, and the API has nothing to serve it to.",
      endpoints: [],
      tools: [],
      parameters: [
        "The MCP companion advertises the prompts capability and offers two prompts under every profile (prompts/list, prompts/get), each carrying the no-advice framing: first_setup (no argument) checks the instance with portfolixir.contract.get and names the active profile, reads what exists, proposes cash accounts, depots, buckets and views (one view with include_all for the total across everything), explains how data gets in, and writes nothing without the operator's confirmation; import_converter (optional argument export_file) guides the user's agent to write and run, on the operator's machine, a converter from a bank or broker export to a Portfolio Performance CSV v1 file for the Imports page, stating the format exactly (with a JSON v1 variant for other currencies and ISINs), forbidding broker sync and any network or model call, and saying that booking the rows one by one through portfolixir.transactions.create is not a substitute because it skips the preview and the content-hash idempotency. An unknown prompt answers an InvalidParams error. MCP only: no route serves a prompt (Sprint 17 A4, #983)",
        "portfolixir.portfolios.valuation, .performance and .benchmark and portfolixir.views.valuation, .performance and .benchmark each end their description with \"Scope twin: <the other tool>\" and the difference: the portfolio tool answers one portfolio record in its base currency, its view narrowing within that portfolio; the view tool answers a view across every portfolio, each account counted once, in EUR, and needs an existing view id (a view created with include_all and no exclusion matches every account); until a view exists the portfolio tool is the only read, its totals over several portfolios add up only when they share one base currency, and returns never add up. No tool is removed or renamed (Sprint 17 A2, #993; plan D-6)",
        "The MCP companion takes PORTFOLIXIR_MCP_PROFILE, read, book or full (default full; any case): read lists and calls only the tools with readOnlyHint, as PORTFOLIXIR_MCP_READ_ONLY=true did and still does; book lists and calls every tool but the admin set, an explicit list in mcp-server/src/profiles.ts drawn as implemented, removal-shaped tools are admin (every removal, the three merges, the ISIN change, a rule's retirement and the release of manual quotes) and replace-shaped writes stay in book, the same write sent the former value undoing them (a second explicit list, each with its reason; a plan's activation among them), except two residues the reasons name: a rename back keeps the in-between name as a former name, and an upsert over a provider date stays manual until the admin quote release; full lists and calls every tool. A call outside the profile, listed or not, is refused as a tool error naming the profile and the variable, with no API request, and the server instructions name the active profile in one clause. PORTFOLIXIR_MCP_READ_ONLY=true beside PORTFOLIXIR_MCP_PROFILE=book or full, or any other value of either, stops the companion with the variables named; READ_ONLY=false never conflicts. A profile narrows the companion, not the API token (Sprint 17 A1, #992)"
      ],
      removed_endpoints: [],
      removed_tools: [],
      prompts: ["first_setup", "import_converter"],
      removed_prompts: []
    },
    %{
      version: 8,
      # Sprint 16's one entry: the first surface change of the batch opened it,
      # every later change of the batch extends it.
      date: ~D[2026-09-25],
      summary:
        "Sprint 16: the second security pass (E25) — errors the server answers " <>
          "itself carry the documented errors envelope with their own status — and the " <>
          "lifecycle's hardened deletes (ADR-0050 §11): a referenced cash account, depot or " <>
          "security answers 409 naming what references it, counted, and the remedy; its " <>
          "identity fields freeze once referenced, answering 422 — and the re-import contract's " <>
          "former names (ADR-0050 §4): a cash account and a depot list the names a Portfolio " <>
          "Performance import still books onto them, a rename keeps the previous name, a name " <>
          "another account answers to is refused, and a former name is removable — and a " <>
          "policy rule's rename (ADR-0049 §4 as amended, #872): the name is a label outside the " <>
          "versioning, so a rename creates no version and changes none — and every authored " <>
          "quote write journaled, with a journaled release of manual quotes back to provider " <>
          "data (T-9) — and journal before-images read under the write's own lock (F49) — " <>
          "and view definitions journaled, a bucket delete journaling its cascade with an " <>
          "emptied override kept explicit-empty (F45, T-10) — and every other delete " <>
          "journaling the rows it removes, one entry each (F43) — and a delta read's as_of " <>
          "that no long write can slip under (G06) — and the races and integrity round: " <>
          "assignment writes that hold their account, one position row per security, rule " <>
          "writes that hold their rule, the settlement guard on the cash booked, split rows " <>
          "changed through the split flow only, a cash target written only when asked, one " <>
          "tax identity per taxpayer, and one clock (G10, G13, F48, F71, G07, G18, G21, G22, G08) " <>
          "— and the cash-account merge (ADR-0050 §7, §8, §10, #328): a preview that states " <>
          "every figure for both answers to the duplicate question under a plan digest, and " <>
          "an apply under that digest that moves the history onto the account kept, restates " <>
          "its balance anchors, retires the hash of every row it removes and remembers the " <>
          "merged-away name for the next import — and the depot merge (ADR-0050 §7, #328): a " <>
          "preview that states every affected position's quantity, moving-average cost and " <>
          "realized result before and after for both answers to the duplicate question, and " <>
          "an apply under its digest that moves the depot's bookings onto the depot kept, " <>
          "keeps each position's view membership, checks every day's quantity and remembers " <>
          "the merged-away name — and the security merge (ADR-0050 §9, #608): a preview that " <>
          "states every position, quote, configuration row, event and identifier the merge " <>
          "touches for both answers to the duplicate question and each identity choice, and an " <>
          "apply under its digest that moves the duplicate's history onto the security kept, " <>
          "gap-fills its quotes, carries its configuration and identifiers and refuses to leave " <>
          "any of its identities unresolved — and a merged-away id answering 404 with the " <>
          "survivor (ADR-0050 §12) — and the merge records listed, newest first, as the audit " <>
          "read of a destructive write (ADR-0050 §12, agent-first until its view lands).",
      endpoints: [
        "DELETE /api/v1/cash_accounts/:id/former_names",
        "DELETE /api/v1/securities_accounts/:id/former_names",
        "PATCH /api/v1/policy_rules/:id",
        "POST /api/v1/securities/:security_id/quotes/release",
        "GET /api/v1/cash_accounts/:id/merge_preview",
        "POST /api/v1/cash_accounts/:id/merge",
        "GET /api/v1/securities_accounts/:id/merge_preview",
        "POST /api/v1/securities_accounts/:id/merge",
        "GET /api/v1/securities/:id/merge_preview",
        "POST /api/v1/securities/:id/merge",
        "GET /api/v1/merges"
      ],
      tools: [
        "portfolixir.cash_accounts.remove_former_name",
        "portfolixir.securities_accounts.remove_former_name",
        "portfolixir.policy_rules.rename",
        "portfolixir.quotes.release",
        "portfolixir.cash_accounts.merge_preview",
        "portfolixir.cash_accounts.merge",
        "portfolixir.securities_accounts.merge_preview",
        "portfolixir.securities_accounts.merge",
        "portfolixir.securities.merge_preview",
        "portfolixir.securities.merge",
        "portfolixir.merges.list"
      ],
      parameters: [
        "Every /api/v1 error the server answers itself rather than an endpoint (an unreadable body 400, a body over the size bound 413, an unknown route 404, an internal error 500) answers {\"errors\": {\"detail\": <reason phrase>}} with its own status (E25 S2, F68); it used to be {\"status\", \"error\"} for 404 and 500 and a bodyless 500 for every other status",
        "The MCP companion's HTTP transport checks the origin and the bearer token before it reads a request body, and answers the errors it raises itself, an unknown path's 404 among them, {\"errors\": {\"detail\": <reason phrase>}} with no stack trace; the MCP protocol's own refusals on /mcp keep their JSON-RPC error shape (E25 S2, F19)",
        "DELETE /api/v1/cash_accounts/:id, /securities_accounts/:id and /securities/:id (portfolixir.cash_accounts.delete, portfolixir.securities_accounts.delete, portfolixir.securities.delete) answer a referenced row 409 with errors.referenced_by (the referencing tables, counted; a transaction once whichever leg references the account), errors.remedy (merge, or retire for a security research notes or policy-rule versions reference) and errors.remedy_route (GET /api/v1/<kind>/:id/merge_preview?target_id=, or PATCH /api/v1/securities/:id); it used to be a bare detail. A delete of a row that has gone answers 404, and an unreferenced row's bucket links, position overrides, category assignments, position targets and ISIN aliases are removed first, each journaled (ADR-0050 §11, L1); a delete that loses a race to a concurrent writer (a lock cycle, a lock wait past the session's lock_timeout, or a security override written between the delete's depot lookup and its lock on the security) answers 409 with errors.detail alone when nothing references the row afterwards, deleting nothing, never a 500 (#954)",
        "PATCH /api/v1/cash_accounts/:id (portfolixir.cash_accounts.update) answers a currency_code change 422 once a transaction references the account through either leg or a securities account links to it, and PATCH /api/v1/securities/:id (portfolixir.securities.update) once the security has a transaction or a quote, with errors.currency_code [\"is frozen once referenced (<the references, counted>)\"] and nothing written; it used to re-denominate the booked history silently. Resending the stored currency is no change, and the other fields stay editable (ADR-0050 §11, L1)",
        "Every cash-account and securities-account payload (GET /api/v1/cash_accounts, /cash_accounts/:id, /securities_accounts, /securities_accounts/:id and the create, update and removal answers; portfolixir.cash_accounts.* and portfolixir.securities_accounts.*) carries former_names, a list of strings: the names a Portfolio Performance import still resolves to that account after its live name (ADR-0050 §4, L2)",
        "PATCH /api/v1/cash_accounts/:id and /securities_accounts/:id (portfolixir.cash_accounts.update, portfolixir.securities_accounts.update): a rename appends the previous name to former_names, and a rename back to a former name consumes it; while another account of the kind in the portfolio still carries the previous name as its live name, it is not kept. POST and PATCH answer 422 with errors.name when the name is another account's live or former name of the kind in the portfolio; it used to allow duplicate names. A name is stored without leading or trailing spaces, so one that differs from another account's only by them is that name, and a rename that only adds them changes nothing (ADR-0050 §4, L2)",
        "DELETE /api/v1/cash_accounts/:id/former_names?name= and /securities_accounts/:id/former_names?name= (portfolixir.cash_accounts.remove_former_name, portfolixir.securities_accounts.remove_former_name) remove one former name, journaled, and answer the account; a name the account does not carry answers 404, a missing name 422. A name stored before invisible characters were refused may be given in the [U+XXXX] spelling the MCP companion lists it in; a stored name of those very letters is matched first (E25 S7 review round). An import that still names it then creates a new account (ADR-0050 §4, L2)",
        "POST /api/v1/securities and PATCH /api/v1/securities/:id (portfolixir.securities.create, .update) answer 422 with errors.ticker_symbol for a ticker made only of dots, and with errors.online_id for a provider id made only of dots, carrying whitespace or URL syntax, or longer than 128 characters: both travel in provider request paths as one segment (E25 S3, F31)",
        "PUT /api/v1/securities/:security_id/quotes (portfolixir.quotes.upsert) answers 422 with errors.date for a date later than tomorrow (the instance's calendar day plus one day of zone slack) and errors.close for a close that is not positive once rounded half up to its 6 decimal places or that has more than 14 digits before the decimal point, and writes nothing (a finer close is stored rounded, never as 0); POST /api/v1/securities/:security_id/sync_quotes and POST /api/v1/exchange_rates/sync drop a provider point or rate outside the same bound (a rate judged at its 15 decimal places) instead of failing the run; the latest-quote and latest-rate reads (the valuation price, latest_price on the securities reads, the stale_quote set, the rates a conversion uses) never serve a stored row dated past it (E25 S3, F26)",
        "GET /api/v1/portfolios/:portfolio_id/risk (portfolixir.portfolios.risk) and GET /api/v1/securities/:security_id/metrics (portfolixir.securities.metrics) answer a volatility, a risk_adjusted_return or a correlation pair whose square root lies outside the double range, a magnitude only implausible stored prices or rates reach, as null without insufficient_data, and computation_basis.gaps says so; the read used to fail with a 500 (E25 S3, F73)",
        "POST /api/v1/securities/:security_id/sync_quotes (portfolixir.quotes.sync) stores a history of any length (written in chunks inside one transaction) and answers status error with reason persist_failed when the fetched quotes cannot be stored; the scheduled sync keeps going past such a security. POST /api/v1/exchange_rates/sync (portfolixir.exchange_rates.sync) stores the full history in one call and answers 502 with nothing stored when the rates cannot be stored; it used to answer 500 (E25 S3, F28)",
        "GET /api/v1/securities/search (portfolixir.securities.search_online) type-checks and size-bounds every provider field of a hit: a field of the wrong type or over its bound is absent, a hit without a usable name is dropped, markets keep bounded fields and scalar properties, and raw carries only type and market_cap_rank instead of the provider's whole entry; the attributes a hit writes pass the same scalar-and-length rule. POST /api/v1/securities and PATCH /api/v1/securities/:id (portfolixir.securities.create, .update) answer 422 on a name, feed_url or latest_feed_url over 255 characters, which used to fail in the database (E25 S3, F29)",
        "POST /api/v1/securities/:security_id/sync_quotes (portfolixir.quotes.sync) answers 409 with a fixed detail while a sync of the same security runs on any path, the background backfill a newly created security starts included, and calls no provider; POST /api/v1/exchange_rates/sync with scope=history (portfolixir.exchange_rates.sync) answers 409 while another backfill runs. A created security's quote backfill, over the API, the page or an import, runs on one serial queue, one security at a time (E25 S3, G04)",
        "Every write that stores a date (the transactions, set_balance, splits, policy-rule versions and retirements, depot and tax statement snapshots, tax profiles, research-log entries, security events, ISIN changes and quotes, over the API and their MCP tools) answers 422 naming the field for a date outside 1900-01-01 to 2999-12-31 or sent in any form other than YYYY-MM-DD (an object of parts, a date-time), and stores nothing; it used to accept any year the cast could build. A provider quote or rate dated before the range is dropped like any implausible point, and a Portfolio Performance import names a row dated after it as a row error (E25 S4, F70)",
        "GET /api/v1/portfolios/:portfolio_id/allocation and /position_targets (portfolixir.portfolios.allocation, portfolixir.targets.list_positions) answer min_drift=NaN, Infinity or -Infinity with 422 naming min_drift; it used to answer 500. The risk read's thresholds and risk_free_rate and the benchmark's rate: selector share the same finite-decimal parser (E25 S4, G15)",
        "POST /api/v1/transactions, PATCH /api/v1/transactions/:id and POST /api/v1/cash_accounts/:id/balance (portfolixir.transactions.create, .update, portfolixir.cash_accounts.set_balance) round a money field or price to 6 decimal places and a quantity to 12, half up, before the checks, so the stored, answered and journaled value is the rounded one and a positive amount that rounds to 0 answers 422; a value with more than 14 digits before the decimal point (a quantity more than 18) answers 422 naming the field; both used to reach the database, which rounded after validation or failed with a 500 (E25 S4, G16, G17)",
        "PUT /api/v1/tax/parameters, POST and PATCH /api/v1/tax/profiles, PUT /api/v1/tax/allowance_orders and POST and PATCH /api/v1/tax/statement_snapshots (portfolixir.tax_parameters.upsert, portfolixir.tax_profiles.create, .update, portfolixir.allowance_orders.put, portfolixir.tax_snapshots.create, .update) round every money field to 6 decimal places and every rate to 4, half up, before the checks, so the stored and answered value is the rounded one; a money value with more than 14 digits before the decimal point answers 422 naming the field; it used to fail in the database with a 500 (E25 S4, G16, G17)",
        "Every write that stores a name, an identifier or free text (portfolios, cash and securities accounts, securities, classifications and categories, buckets, views, plans, snapshots, policy rules and their versions, research-log entries, security events, tax profiles, statement snapshots and allowance orders, ISIN aliases, transactions' notes; over the API and their MCP tools) answers 422 naming the field for one-line text longer than its column in Unicode code points or carrying a control character or line break, and for free text carrying a control character other than tab and line break; it used to fail in the database with a 500. POST /api/v1/securities/:security_id/isin-change (portfolixir.securities.isin_change) answers 422 on new_isin unless it is twelve characters of the ISIN shape, and on an alias note over 255 characters (E25 S4, G17, G24)",
        "POST /api/v1/securities and PATCH /api/v1/securities/:id (portfolixir.securities.create, .update) answer 422 on attributes when a key, at any depth, is longer than 255 characters or carries a control character or line break, or a text value carries a control character other than tab and line break; it used to fail in the database with a 500. GET /api/v1/securities/search (portfolixir.securities.search_online) drops a provider property that breaks the same rule (E25 S4, G24)",
        "GET /api/v1/transactions and /securities/:security_id/quotes and /trades (from, to), /securities/:security_id/metrics and /portfolios/:portfolio_id/policy_rules (as_of) (portfolixir.transactions.list, portfolixir.quotes.list, portfolixir.trades.list, portfolixir.securities.metrics, portfolixir.policy_rules.list) answer a date outside 1900-01-01 to 2999-12-31, or not YYYY-MM-DD, with 422 naming the parameter; GET /api/v1/securities (query), /journal (resource_type, resource_id), /tax/parameters (jurisdiction), /tax/profiles, /tax/allowance_orders, /tax/statement_snapshots and /tax/trim_budget (holder, institution) answer a text filter longer than 255 characters, carrying a control character or not a string with 422 naming it; both used to reach the database and fail with a 500 (E25 S4, F70, G24)",
        "PUT /api/v1/securities/:security_id/quotes (portfolixir.quotes.upsert) answers a batch that names one date twice with 422 on date naming that date, and a row that is not an object with 422 on quotes, and writes nothing; both used to answer 500 (E25 S4, F13)",
        "PUT /api/v1/views/:id/buckets (portfolixir.views.set_buckets) counts a bucket named twice in include or exclude once; it used to answer 500 (E25 S4, F12)",
        "PUT /api/v1/portfolios/:portfolio_id/targets (portfolixir.targets.set) answers a batch that names one category row twice with 422 (errors.detail names the category), and a batch longer than one row per category and one per security assigned in the classification, or than 10000 rows, with 422 on targets, and writes nothing; the MCP schema carries maxItems 10000 (E25 S4, G11)",
        "PUT /api/v1/portfolios/:portfolio_id/targets, PUT .../cash_target and POST/PATCH /api/v1/portfolios with cash_target_weight (portfolixir.targets.set, the cash-target tool, portfolixir.portfolios.create) answer 422 on the weight for more than 6 decimal places, and the database refuses such a weight on every writer (on an instance that already held a finer weight when upgraded, the changesets alone refuse it, and a duplicate or a SOLL save rounds the stored weight half up to 6 places). GET /api/v1/portfolios/:portfolio_id/allocation (portfolixir.portfolios.allocation) answers drift_value and rebalance_quantity null for a position valued at 0 without its own target (it used to answer a signed zero) and, with the position rows, carries computation_basis (the drift share's basis and the gaps where it is null) (E25 S4, G14)",
        "POST /api/v1/classifications/:classification_id/categories and PATCH .../categories/:id (portfolixir.classifications.categories.create, .update) answer 422 on parent_id for a parent from another classification, and PATCH for the category itself or one of its descendants as its parent, and write nothing; both used to store a tree that loops (E25 S4, F11)",
        "GET /api/v1/portfolios/:portfolio_id/risk (portfolixir.portfolios.risk) caps top_n at 1000 and echoes the applied top_n (10 when absent); the MCP schema carries maximum 1000. metrics.correlations covers at most the 20 leading names of the Top-N list and carries leading_names, how many it ran over, and metrics.computation_basis.input_series states the bound; both used to grow with an unbounded top_n (E25 S4, F72)",
        "POST /api/v1/splits/preview and POST /api/v1/splits (portfolixir.splits.preview, .create) answer 422 on ratio when the security's splits, each counted by its own magnitude, would multiply past 10^12 with the new one included, and write nothing. The performance reads' irr (and mwr) are null when an amount lies outside the range the solver's one float step carries, and computation_basis.gaps names why irr can be null; such a read used to fail with a 500 (E25 S4, G12)",
        "POST /api/v1/securities/:security_id/isin-change (portfolixir.securities.isin_change) answers 422 on new_isin when its check digit does not agree, as well as for the shape. PATCH /api/v1/securities/:id (portfolixir.securities.update) answers 422 naming the field for an isin, wkn or ticker_symbol it changes that fails the catalog's rules: an ISIN of the shape with a check digit that agrees, a WKN of six letters or digits, a ticker of printable ASCII; resending the stored value is no change, and POST /api/v1/securities keeps what a new security is created with. POST and PATCH store a security's name without Unicode format characters (E25 S5, G23)",
        "PUT /api/v1/securities/:security_id/quotes (portfolixir.quotes.upsert) stores every row as manual whatever source it names, and the MCP schema offers source manual only and lets it be omitted; the write is journaled under the token (resource_type security_quotes, filed under the security's id, operation upsert) with the stored rows it replaced as the before-image, and the answer carries replaced, the ISO dates whose stored row the write changed, beside upserted; a call that changes nothing writes no journal entry. It used to store the named source and replace a provider close with no trace (E25 S6, F20, G27, T-9)",
        "POST /api/v1/securities/:security_id/quotes/release (portfolixir.quotes.release) takes from and to (both required, inclusive) and removes the security's manual quotes in the range, journaled (operation delete) with the released rows as the before-image, answering {security_id, from, to, released}; provider rows stay, and the next quote sync stores the provider's close for a released date. A missing or invalid date answers 422 naming it, to before from 422 on to, an unknown security 404. Agent-first: its control on the security page lands no later than Sprint 17 (E25 S6, T-9)",
        "POST /api/v1/securities/:security_id/notes (portfolixir.notes.append) answers 422 on as_of for a date after the instance's calendar day and appends nothing; valid_until and time_stop may still lie in the future. GET /api/v1/notes/unreviewed (portfolixir.notes.unreviewed) and the thesis_state's last_reviewed_at count an entry as a review no later than the day after it was written, so a stored future as_of cannot keep a position off the review read (E25 S6, F44)",
        "POST /api/v1/securities/:security_id/events and PATCH /api/v1/security_events/:id (portfolixir.events.create, .update) answer 422 on checked_at for a date later than tomorrow (the instance's calendar day plus one day of zone slack) and write nothing; GET /api/v1/events/stale (portfolixir.events.stale) lists an event whose stored checked_at lies after tomorrow, with a negative days_since_checked (E25 S6, G09)",
        "POST /api/v1/securities/:security_id/notes (portfolixir.notes.append) answers 422 on body past 20000 characters and on invalidation_condition past 10000; POST .../events and PATCH /api/v1/security_events/:id (portfolixir.events.create, .update) on note past 10000; POST /api/v1/portfolios/:portfolio_id/policy_rules and POST /api/v1/policy_rules/:id/versions (portfolixir.policy_rules.create, .add_version) on the version's note past 10000 — characters counted as Unicode code points, a database CHECK of the same cap behind each, and the MCP schemas carry the caps as maxLength. The thesis_state of the security and notes reads loads the current thesis's text only (E25 S6, G01)",
        "Every write of a free-text note or description (portfolios, cash and securities accounts, transactions, securities, classifications, tax profiles, allowance orders and statement snapshots, over the API and their MCP tools) answers 422 naming the field past 10000 characters (a category's description 2000), counted as Unicode code points, with a database CHECK of the same bound behind it; POST /api/v1/securities and PATCH /api/v1/securities/:id (portfolixir.securities.create, .update) answer 422 on attributes when the map as stored, merged with the stored attributes, is past 65536 bytes as compact JSON, and store nothing. A Portfolio Performance import names a row whose note is past the bound. An update that changes nothing writes no row and no journal entry (E25 S6, G02)",
        "POST and PATCH /api/v1/tax/statement_snapshots (portfolixir.tax_snapshots.create, .update) never take source from the body: a recorded statement's source is manual, and the MCP schemas no longer offer it; it used to store a caller's pdf_import (E25 S6, F20)",
        "PATCH /api/v1/policy_rules/:id (portfolixir.policy_rules.rename) takes {\"name\"} only and answers the rule with its versions, none added or changed; journaled under the token with the previous name; allowed on a retired rule; names need not be unique. A blank, missing or non-text name answers 422 on name; a predicate field, a version, the version keys of the rule's read shape (version_in_force, next_version, versions) or the context (view_id, portfolio_id) in the same body answers 422 naming each such field, and nothing is written; any other key is ignored, as on PATCH /api/v1/plans/:id; a rule deleted since it was read answers 404 (ADR-0049 §4 and §8 as amended by the Sprint 16 plan D-6, #872)",
        "GET /api/v1/journal (portfolixir.journal.list): an update's or a delete's before is the row as stored when the write took its lock, and an update's after is the row as stored after the write, decimals at their column's scale; both used to be the caller's earlier read, with the change applied for after, so two writes made from one read both claimed the same before. Every PATCH, PUT or DELETE of a record deleted between its read and the write's lock answers 404 and journals nothing; it used to answer 500 (E25 S6, F49)",
        "PATCH /api/v1/views/:id, PUT /api/v1/views/:id/buckets and DELETE /api/v1/views/:id (portfolixir.views.update, .set_buckets, .delete) journal one resource_type view entry, filed under the view, whose before and after (a delete: before) carry the whole definition: name, include_all, include_bucket_ids, exclude_bucket_ids; resending the stored definition journals nothing, and a view gone answers 404. View-definition writes used to leave no entry although a policy rule in force reads the view; creating a view stays unjournaled (E25 S6, F45; ADR-0018 and ADR-0049 amended)",
        "DELETE /api/v1/buckets/:id (portfolixir.buckets.delete) first rewrites every view and assignment naming the bucket through its journaled writer, one entry per view, depot default set, cash-account set and position override, and keeps a position override that loses its last bucket explicit-empty instead of letting it inherit the depot's set; the bucket's delete entry carries every membership it had (memberships: view_include, view_exclude, depot_defaults, cash_accounts, position_overrides) as its before-image, and a bucket gone answers 404. Removing the bucket from a set never re-checks the exclusive scope dimension, so a set stored before that rule held never blocks the delete, and a set it cannot be removed from answers 422 with nothing deleted, never a 500. It used to remove the memberships by database cascade with no entry, turning such an override into inheritance (E25 S6, G19, G29, T-10; review round)",
        "DELETE /api/v1/classifications/:id, DELETE /api/v1/classifications/:classification_id/categories/:id, DELETE /api/v1/plans/:id and DELETE /api/v1/views/:id (portfolixir.classifications.delete, portfolixir.classifications.categories.delete, portfolixir.plans.delete, portfolixir.views.delete) journal every row they remove as its own delete ahead of the parent's entry: categories, lowest first; stored assignments; plans with their targets; a view's depot snapshots. They used to remove those rows by database cascade, the journal recording the parent only. A bulk asset-class move journals every affected security with the asset class it had as its entry's before-image (E25 S6, F43)",
        "Every ?since= delta read (GET /api/v1/securities, /transactions, /securities/:security_id/notes and /events, /portfolios/:portfolio_id/targets, /position_targets and /policy_rules; the MCP tools that forward since) answers as_of no later than one second before the start of the oldest transaction that has written and is still open, or before the read instant when none is; it used to be the read instant less one second, so a row a long write stamped before a poll and committed after it was never delivered by the next poll. The next read may re-deliver a row; the delta_note and the tool descriptions say so (E25 S6, G06; commit-ordered cursors are issue #897)",
        "PUT /api/v1/securities_accounts/:id/buckets, PUT /api/v1/cash_accounts/:id/buckets and PUT and DELETE /api/v1/securities_accounts/:id/positions/:security_id/buckets (portfolixir.securities_accounts.set_buckets, portfolixir.cash_accounts.set_buckets, portfolixir.securities_accounts.set_position_buckets, .clear_position_buckets) hold the account while they replace its set, so two writes to one account leave the set of the one that commits last, never a mix of both, and an account deleted meanwhile answers 404 with nothing written; the position override writes hold the security after the depot, the order the hardened security delete takes, and a security deleted meanwhile answers 404 with nothing written or journaled, never a constraint error (#919); a position whose stored override is damaged reads as explicit_empty on every read instead of failing the view-scoped reads with a 500 (E25 S6, G10)",
        "PUT /api/v1/portfolios/:portfolio_id/targets (portfolixir.targets.set) answers the one-position-per-security 422 also when a concurrent write filed the security under another category after this write's check; a unique index on (plan, security) holds the rule in the database, so a plan never stores two position rows for one security, and an instance that already holds such a pair stops the upgrade naming each (E25 S6, G13)",
        "POST /api/v1/policy_rules/:id/versions, POST /api/v1/policy_rules/:id/retire and DELETE /api/v1/policy_rules/:id (portfolixir.policy_rules.add_version, .retire, .delete) hold the rule while they read its versions, so a version added concurrently with a retirement is judged after it and never survives it; a rule deleted since it was read answers 404 on all three (the version add used to answer 422) (E25 S6, F48)",
        "POST /api/v1/transactions and PATCH /api/v1/transactions/:id (portfolixir.transactions.create, .update) check a cross-currency buy or sell without gross_amount against the cash the ledger books for it, quantity × price with fees and taxes, and answer 422 on gross_amount naming both amounts when it misses the settlement by more than 0.01; such a trade used to pass unchecked and book the security currency's units as the account's cash. On a booking without gross_amount a PATCH of quantity or price re-checks it (E25 S6, F71)",
        "PATCH /api/v1/transactions/:id (portfolixir.transactions.update) changes only the notes of a stored split row: a change of its date, security_id, portfolio_id, type or split ratio answers 422 naming the field, and a wrong split is deleted and booked again through POST /api/v1/splits; it used to re-date, re-rate or re-target a split past the split flow's checks (E25 S6, G07)",
        "PATCH /api/v1/portfolios/:portfolio_id (deprecated) and POST /api/v1/portfolios (portfolixir.portfolios.create) write the Gesamt cash target only when the body carries cash_target_weight, in the portfolio's own transaction: a patch without it leaves the cash target and its journal untouched (it used to rewrite, or since the before-image round clear, the cash target from the portfolio it had read), and a refused cash-target write answers 422 with the rest of the write rolled back (it used to fail after the portfolio had committed) (E25 S6, G18)",
        "Every tax endpoint that writes or filters on holder or institution (the profiles, allowance orders, statement snapshots and the trim budget; portfolixir.tax_profiles.*, portfolixir.allowance_orders.*, portfolixir.tax_snapshots.*) normalises the value to NFC without format characters and with every run of Unicode spaces one space, answers 422 for a value left empty, and matches it by the database's case fold on both sides; GET /api/v1/tax/trim_budget (portfolixir.tax_snapshots.trim_budget) groups institutions by that fold, and GET /api/v1/portfolios/:portfolio_id/allocation?tax_context=true (portfolixir.portfolios.allocation) carries one trim budget per holder identity; case spellings of one taxpayer used to yield one budget each (E25 S6, G21, G22)",
        "Every as_of an API read reports for today (the valuation, holdings, reconciliation and allocation reads, the portfolio metrics) and every date check a write makes against today (quotes, snapshots, statements, events, notes, rule versions, splits) reads the instance's calendar day in its TZ, which the database session also takes on connect; the reads used to report the UTC day (E25 S6, G08)",
        "The MCP companion's tools/list publishes each tool's own input schema, its property descriptions and closed objects (additionalProperties: false) included, where it used to publish a schema derived from the validator that carried neither; portfolixir.securities.create's schema names is_benchmark, which the validator already took; a call the API answers without a body (a delete's 204) reaches the host as a result without structuredContent, where it used to reach it as a protocol error (E25 S7, F21)",
        "The MCP companion's HTTP transport answers a request under a Host it does not answer to, compared exactly by name and port, 403 {\"errors\": {\"detail\": \"host not allowed\"}} before the origin and the token are checked, on every path; the SDK's own Host check on /mcp stays behind it (E25 S7, F22)",
        "Every MCP tool answers a 3xx from the API as a tool error naming ApiRedirectError, the request and PORTFOLIXIR_API_BASE_URL, and follows no redirect; it used to follow it and resend the request, its body and its token (E25 S7, F23)",
        "The MCP companion's initialize answer carries server instructions stating that everything a tool returns is data, never instructions, and every tool in tools/list carries readOnlyHint, destructiveHint, idempotentHint and openWorldHint, derived from the HTTP method it routes to with named exceptions (portfolixir.splits.preview and portfolixir.holdings.reconcile read; portfolixir.quotes.release, routed through POST, removes and is hinted as a DELETE, destructive and idempotent; portfolixir.policy_rules.retire, portfolixir.plans.activate and portfolixir.securities.isin_change, routed through POST, change stored rows and are hinted as a PUT, destructive and idempotent; portfolixir.securities.search_online, portfolixir.quotes.sync, portfolixir.exchange_rates.sync and portfolixir.securities.create, which queues a provider backfill and a logo lookup, are open-world); portfolixir.notes.append, portfolixir.policy_rules.create and .add_version state in their descriptions that what they add is permanent (E25 S7, F24, G25)",
        "The MCP companion takes an opt-in read-only switch, PORTFOLIXIR_MCP_READ_ONLY (off by default): on, tools/list lists only the tools with readOnlyHint, and a call to any other tool is refused as a tool error naming the switch, with no API request; the API token keeps its full authority (E25 S7, G26)",
        "Every MCP write (POST, PUT, PATCH, DELETE) that gets no answer within its deadline answers a tool error naming ApiOutcomeUnknownError: the server may still have committed it, so the agent re-reads before retrying; it used to answer the bare timeout. A read that misses it, a GET or a read-only tool routed through POST (portfolixir.splits.preview, portfolixir.holdings.reconcile), answers ApiReadTimeoutError: it changed nothing and can be retried. Each non-idempotent write states the outcome-unknown rule in its description, and the server instructions state it once (E25 S7, G31; review round)",
        "portfolixir.classifications.delete, portfolixir.classifications.categories.delete and portfolixir.views.delete name in their descriptions every kind of row one call removes with the object and that the audit journal keeps each removed row as its own delete; portfolixir.policy_rules.create and .add_version state that a version is permanent once in force (E25 S7, G28)",
        "GET /api/v1/portfolios/:portfolio_id/policy_rules (rules_note) and /policy_findings (findings_note), and the portfolixir.policy_rules.* tools and portfolixir.portfolios.policy_findings in their titles, descriptions and schemas, call a rule a stored rule rather than the operator's own, and the rules note and the list, show, create and add_version descriptions point to the audit journal (resource_type policy_rule, policy_rule_version) for who wrote it; an API token writes rules as the Risk page does (E25 S7, G30, the wording half)",
        "GET /api/v1/cash_accounts/:id/merge_preview?target_id= (portfolixir.cash_accounts.merge_preview) is a read: 200 with plan_digest, source and target (balance, transaction_count, bucket_ids, former_names), guards (code, check, passed, detail), internal_transfers, key_equal_pairs, choice_required, linked_depots, former_names (appended, not_kept, after) and outcome_by_collapse_key_equal with \"false\" and \"true\" (balance, transaction_count, moved_transaction_ids, deleted with reason internal_transfer, collapsed_duplicate or folded_anchor, restated_anchors as stated + other_balance = after, flow_changes — kind removed or absorbed, each with cash_account_id, the source's or a third account's for a collapsed transfer, transaction_id, date, change and collapsed_transaction_id —, other_accounts, positions), balance_basis (the computation basis of the balances and the restated anchors) and reimport_note (what the merge does to the next import), every decimal a string; a pair a guard forbids answers 409 with errors.code (same_account, not_live, portfolio_mismatch, currency_mismatch, liquidity_role_mismatch, buckets_mismatch, legacy_hashed_anchor, unstorable_anchor — a restated anchor whose exact amount needs more than the amount column's 6 places, because a trade was booked without its amount — each of the two with errors.anchors naming the anchors, unstorable_anchor with errors.bookings naming the trades) and errors.guards, an unknown source 404, a source already merged 409 already_merged with errors.merged_into, a missing target_id 422 (ADR-0050 §7, §8, §10)",
        "POST /api/v1/cash_accounts/:id/merge (portfolixir.cash_accounts.merge) takes target_id, plan_digest (required) and collapse_key_equal (required, a boolean, when the preview lists key-equal pairs) and answers 201 with the merge record (kind, source_id, target_id, portfolio_id, source_snapshot, manifest, plan_digest, actor_type, actor_label, inserted_at) and already_applied false, or 200 with the original record and already_applied true for a retry of a completed merge of the same pair, journaling nothing; a digest that no longer matches answers 409 plan_changed with the fresh preview in errors.preview, a guard 409 with its code, identity_check_failed and write_refused 409, a missing digest or choice 422 — each writing nothing. The source's bookings, anchors and linked depots move onto the target, one journal entry per row; transfers between the two and collapsed rows are deleted with their content hashes retired; the source is deleted and its names become former names of the target (ADR-0050 §7, §8, §10, §12)",
        "GET /api/v1/securities_accounts/:id/merge_preview?target_id= (portfolixir.securities_accounts.merge_preview) is a read: 200 with plan_digest, source and target (cash_account_id, bucket_ids — the default buckets —, former_names, transaction_count), guards, internal_transfers (the security transfers between the two), key_equal_pairs, choice_required, position_buckets (per security the source holds or overrides: both effective bucket sets, both overrides and the action none, carry, drop_redundant, drop_unheld or clear_target), former_names (appended, not_kept, after), outcome_by_collapse_key_equal with \"false\" and \"true\" (transaction_count, moved_transaction_ids, deleted with reason internal_transfer or collapsed_duplicate, positions — per security the source holds, source and target before and after, each quantity, cost_basis, avg_cost and realized_result —, rounding_differences per split where the combined position rounded once differs from the two rounded apart, cash_accounts a collapse changes with balance_before and balance_after, flow_changes a collapse moves into a later balance anchor of such a cash account, kind absorbed, as in the cash merge preview, other_depots a collapsed transfer with a third depot changes, with securities_account_id, security_id, quantity_before and quantity_after; each key-equal pair names both depot legs, securities_account_id and counter_securities_account_id), positions_basis, the computation basis of those figures, and reimport_note, what the merge does to the next import; every quantity and decimal a string. A pair a guard forbids answers 409 with errors.code (same_account, not_live, portfolio_mismatch, buckets_mismatch, position_buckets_mismatch naming the positions) and errors.guards, an unknown source 404, a source already merged 409 already_merged with errors.merged_into, a missing target_id 422 (ADR-0050 §7, §8, §10)",
        "POST /api/v1/securities_accounts/:id/merge (portfolixir.securities_accounts.merge) takes target_id, plan_digest (required) and collapse_key_equal (required, a boolean, when the preview lists key-equal pairs) and answers 201 with the merge record and already_applied false, or 200 with the original record and already_applied true for a retry of a completed merge of the same pair, journaling nothing; a digest that no longer matches answers 409 plan_changed with the fresh preview in errors.preview, a guard 409 with its code, identity_check_failed and write_refused 409, a missing digest or choice 422 — each writing nothing. The source's bookings move onto the target on whichever depot leg names the source, one journal entry per row, each keeping its cash leg (the target keeps its own linked cash account); transfers between the two and collapsed rows are deleted with their content hashes retired; every day's quantity per security is checked against the fold of both depots' bookings; each position's override is carried, dropped or cleared so its view membership is unchanged; the source is deleted and its names become former names of the target (ADR-0050 §7, §8, §10, §12)",
        "GET /api/v1/securities/:id/merge_preview?target_id= (portfolixir.securities.merge_preview) is a read: 200 with plan_digest, source and target (name, currency_code, isin, wkn, ticker_symbol, feed, asset_class, the flags, transaction_count, split_events), guards, key_equal_pairs, choice_required, identity_choice_required, splits (collapsed, moved), split_events (source, target, after), position_buckets per depot, quotes (source_count, moved_count, collision_count, manual_collisions with date, source_close, target_close and target_source), configuration (category_assignments with action move or drop; position_targets with plan, plan_status, category, target_weight, action move or drop and reason collides or stale), events (moved, possible_duplicates), identifiers (choice_required, after_by_identity_choice with keep_target_isin and adopt_source_isin when both carry an ISIN, otherwise after — each isin, wkn, ticker_symbol, feed, name, asset_class, former_isins —, adopted, differences — a WKN or ticker the catalog's rules refuse on a change among them, never adopted, with the target's null —, aliases_reassigned), reverse (mergeable, refused), outcome_by_collapse_key_equal with \"false\" and \"true\" (transaction_count, moved_transaction_ids, deleted with reason collapsed_duplicate or collapsed_split, positions per depot the source holds with source, target and after figures, rounding_differences, cash_accounts, flow_changes), positions_basis and reimport_note; every quantity, close, weight and decimal a string. A pair a guard forbids answers 409 with errors.code (same_security, not_live, currency_mismatch, benchmark_mismatch, retired_target, quote_basis_mismatch, research_notes, policy_rules with errors.policy_rules, position_buckets_mismatch, split_ratio_mismatch, split_event_mismatch, split_linearity, legacy_hashed_split with errors.splits naming a split to move that still carries an import hash, invalid_source_isin for a source ISIN whose check digit fails, identity_unresolvable with errors.unresolvable naming each identity — security_id, identity stored, imported, former_isin, or merged_stored and merged_imported for a security merged into either before, under its own id, ref, outcome — that would no longer resolve to the target) and errors.guards, an unknown source 404, a source already merged 409 already_merged with errors.merged_into, a missing target_id 422 (ADR-0050 §9, §10)",
        "POST /api/v1/securities/:id/merge (portfolixir.securities.merge) takes target_id, plan_digest (required), collapse_key_equal (required, a boolean, when the preview lists key-equal pairs), identity_choice (required when both securities carry an ISIN: keep_target_isin or adopt_source_isin, never preselected) and isin_changed_on (optional YYYY-MM-DD, the former ISIN's changed_on; the merge date otherwise) and answers 201 with the merge record and already_applied false, or 200 with the original record and already_applied true for a retry of a completed merge of the same pair, journaling nothing; a digest that no longer matches answers 409 plan_changed with the fresh preview in errors.preview, a guard 409 with its code, identity_check_failed, identity_unresolvable (found after the writes, with errors.unresolvable) and write_refused 409, a missing digest or choice 422 naming it, an unknown identity_choice or an isin_changed_on that is no date 422 — each writing nothing. The source's bookings move onto the target, one journal entry per row; key-equal pairs collapse by choice with their content hashes retired, a split the target carries on the same day in the same portfolio always collapses; its quotes fill the target's gaps, the target's winning a collision, row by row without a journal entry, each moved and dropped quote listed in the manifest with the dropped closes; its category assignments, position targets and events move or are dropped as the preview listed, one journal entry per row; its former ISINs are reassigned, its ISIN written by the identity choice, its WKN, ticker and feed adopted where the target lacks them; the source is deleted (ADR-0050 §9, §10, §12, §13)",
        "GET /api/v1/securities/:id, /cash_accounts/:id and /securities_accounts/:id (portfolixir.securities.get) of a row a merge took away answer 404 with errors.merged_into {kind, id}, as does every route under /api/v1/securities/:security_id/ (quotes, trades, metrics, notes, events, logo, reads and writes, the ISIN change and the delete of an identifier alias) for a merged-away security — the row its history lives on now, following every later merge to the live end — and a detail naming both; an id no merge names answers the plain 404 as before, and so does one whose chain ends at a row deleted since, its detail naming that row (ADR-0050 §12)",
        "GET /api/v1/merges (portfolixir.merges.list) is a read: the merge records, newest first (inserted_at, then id), each with id, kind, source {id, name} (the name the merge recorded), target {id, name, merged_into} (merged_into null while the target lives, otherwise the live end of the chain, and null when the chain ends at a row deleted since), portfolio_id (null for a security), actor_type, actor_label, inserted_at and manifest_summary (the manifest with every list replaced by its count, the operator's choices as given); meta carries order, count and limit. limit is the list family's: default 100, capped at 1000, a non-positive or non-numeric value 422 (ADR-0050 §12; agent-first, its list view lands no later than Sprint 17)",
        "GET /api/v1/portfolios/:portfolio_id/performance/benchmark and /views/:view_id/performance/benchmark (portfolixir.portfolios.benchmark, portfolixir.views.benchmark): computation_basis.reference and .input_series name a benchmark security as \"security <id> (<currency>)\"; they used to carry its stored name, which stays in benchmark.name as data (E25 S7, F75)",
        "Every /api/v1 write is journaled under the name of the token entry the presented bearer token matched, as actor_label on GET /api/v1/journal (portfolixir.journal.list) and, for a lifecycle merge, on its merge record (the merge answers and GET /api/v1/merges, portfolixir.merges.list), never under anything the request says: API tokens may be configured as PORTFOLIXIR_API_TOKENS name=token entries, each with the same full authority, and PORTFOLIXIR_API_TOKEN stays the default, journaled with actor_label null as before unless PORTFOLIXIR_API_PRINCIPAL names it; the Compose deployment gives the companion's token the name mcp that way (E25 S7, G26, the architecture's FU-6)",
        "Every policy-rule version carries author, \"operator\" or \"agent\" (GET /api/v1/portfolios/:portfolio_id/policy_rules on version_in_force and next_version, GET /api/v1/policy_rules/:id on every version, and the create, add_version, retire and rename answers; portfolixir.policy_rules.*), and every finding the author of its version (GET /api/v1/portfolios/:portfolio_id/policy_findings, portfolixir.portfolios.policy_findings): derived from the write's credential — an API or MCP token writes as the agent, the Risk page as the operator — and never read from the body, where an author key is ignored; a version stored before this entry takes the author its journaled creation names, null only without one, and the database refuses a change of a recorded author. When a rule is in force does not depend on it (E25 S7, G30, the author half; T-8; ADR-0049 amended)",
        "Every write that stores a name, an identifier or free text (the writers and MCP tools of the E25 S4 text rule, research-log bodies and invalidation conditions, event notes, policy-rule names and version notes among them) answers 422 naming the field and the characters by code point — \"must not contain invisible characters (U+200B); retype the text without them\" — for text carrying a Unicode tag character, a bidirectional control, another invisible format character (the soft hyphen, the zero-width space and joiners, the byte-order mark, among others) or a run of two or more variation selectors, and stores nothing; a single variation selector passes, and so does a zero-width joiner between two pictographs (an emoji sequence), while the tag-built subdivision flags and the zero-width non-joiner stay refused. A security's name still loses its format characters as it is stored (E25 S5, G23). A Portfolio Performance import names such a row as a row error; a search provider's property carrying one is dropped; a read's text filter carrying one answers 422 (E25 S7, G20)",
        "Every MCP tool's result, and every tool error the companion raises from an API answer, carries each such character of a stored row, in a value or a key at any depth, spelled [U+XXXX] (upper-case hex, at least four digits; a variation selector only within a run of two or more), the spelling the operator's screen shows; the JSON API answers stored text as stored, and the server instructions say so (E25 S7, G20, the MCP boundary)"
      ],
      removed_endpoints: [],
      removed_tools: [],
      prompts: [],
      removed_prompts: []
    },
    %{
      version: 7,
      # The date the batch lands on main; an entry sharing its predecessor's
      # date would be invisible to a poller that read that one (since= is
      # strictly after), so it is never backdated onto Sprint 14's.
      date: ~D[2026-09-24],
      summary:
        "Sprint 15: policy rules as first-class objects (ADR-0049, FR-43, gate B3.6) — the " <>
          "operator's caps, floors and bands over a weight, a drift, the HHI or a portfolio " <>
          "metric, stored as versioned, effective-dated objects: an edit is a new version, a " <>
          "version that has been in force is never changed or deleted, and the standard in " <>
          "force on any date is a read — and the findings read, which evaluates the rules in " <>
          "force today over the figures the product already serves into ok, breached or " <>
          "undetermined (never a pass), with no action on any finding.",
      endpoints: [
        "GET /api/v1/portfolios/:portfolio_id/policy_rules",
        "POST /api/v1/portfolios/:portfolio_id/policy_rules",
        "GET /api/v1/policy_rules/:id",
        "POST /api/v1/policy_rules/:id/versions",
        "POST /api/v1/policy_rules/:id/retire",
        "DELETE /api/v1/policy_rules/:id",
        "GET /api/v1/portfolios/:portfolio_id/policy_findings"
      ],
      tools: [
        "portfolixir.policy_rules.list",
        "portfolixir.policy_rules.get",
        "portfolixir.policy_rules.create",
        "portfolixir.policy_rules.add_version",
        "portfolixir.policy_rules.retire",
        "portfolixir.policy_rules.delete",
        "portfolixir.portfolios.policy_findings"
      ],
      parameters: [
        "GET /api/v1/portfolios/:portfolio_id/policy_rules and portfolixir.policy_rules.list take as_of= (the standard in force on a date), include_retired=, view= (one evaluation context; absent is every context), since= (a rule counts as changed when its row or any version did) and limit=",
        "GET /api/v1/portfolios/:portfolio_id/policy_findings and portfolixir.portfolios.policy_findings take view= (the evaluation context) and status= (a comma-separated set of breached, undetermined, ok; status=breached is the pull-only alarm list); since= deliberately does not apply — findings are a derived projection (#849). An undetermined finding's reason includes unvalued (a subject held but not valued); a drift finding's computation_basis carries drift_basis (full_plan or allocated_portion)",
        "DELETE /api/v1/securities/:id, /classifications/:id, /classifications/:classification_id/categories/:id and /views/:id answer 409 with errors.policy_rules (id, name, status) when a policy rule reads the object (ADR-0049 §8); a view counts as read both as a rule's context and as its subject",
        "The policy-rule reads (portfolixir.policy_rules.list, .get, portfolixir.portfolios.policy_findings) state in their descriptions that a Portfolio Performance re-import does not destroy the policy rules (ADR-0049 §8, #831's lesson)",
        "POST /api/v1/transactions and PATCH /api/v1/transactions/:id (portfolixir.transactions.create, .update) answer 422 on gross_amount when a cross-currency buy's cash differs from settlement_amount + fees + taxes, or a sell's from settlement_amount - fees - taxes, by more than 0.01 (#395); a PATCH that changes none of gross_amount, settlement_amount, fees, taxes and type is not re-checked"
      ],
      removed_endpoints: [],
      removed_tools: [],
      prompts: [],
      removed_prompts: []
    },
    %{
      version: 6,
      date: ~D[2026-09-23],
      summary:
        "Sprint 14: the portfolio and view derived metrics (ADR-0047, FR-40) on the one " <>
          "risk read — volatility, maximum drawdown and risk-adjusted return over the " <>
          "TTWROR chain's flow-adjusted factors, and the Top-N correlation matrix converted " <>
          "to the base currency; `required` on every metric of both metric payloads (#838); " <>
          "since= on the row collections a scheduled run polls (#830), deliberately not on " <>
          "the derived projections or the time-derived queues; the re-import guarantee in " <>
          "the descriptions of the reads it protects (#831).",
      endpoints: [],
      tools: [],
      parameters: [
        "GET /api/v1/portfolios/:portfolio_id/risk and portfolixir.portfolios.risk carry metrics (ADR-0047 §3, FR-40): volatility, max_drawdown (peak/trough/recovery dates) and risk_adjusted_return over 30d/90d/365d from the TTWROR chain's flow-adjusted daily return factors, annualized by √365, and correlations — the Top-N names' Pearson matrix converted to the base currency first, each pair with its overlap count, a currency with no rate path listed in excluded; metrics.computation_basis states the basis once. The risk family keeps exactly one endpoint; the view arrives as view=",
        "GET /api/v1/portfolios/:portfolio_id/risk and portfolixir.portfolios.risk take risk_free_rate= (a Decimal fraction, default 0, ADR-0046's fixed-rate bound and daily compounding); a malformed or out-of-bound rate is a 422 naming the field",
        "GET /api/v1/securities/:security_id/metrics and the risk read's metrics carry required on every metric in both states (ADR-0047 §6 as amended, #838): n for sma_n, 20 for volatility and risk_adjusted_return, 2 for max_drawdown and momentum, 1 for distance_to_extremes, 60 per correlation pair; a refused sma_n keeps window null",
        "GET /api/v1/securities/:security_id/notes and portfolixir.notes.list take since= (FR-38, #830): entries appended strictly after it, by inserted_at; thesis_state still derives from the whole log",
        "GET /api/v1/securities/:security_id/events and portfolixir.events.list take since= (#830): rows created or updated strictly after it",
        "GET /api/v1/portfolios/:portfolio_id/targets and /position_targets and portfolixir.targets.list / list_positions take since= (#830): a row counts as changed when it or its plan changed; effective_targets stays whole-plan",
        "The six time-derived queues (/notes/unreviewed, /notes/expiring, /notes/uncorroborated, /events/upcoming, /events/stale, /events/unconfirmed) deliberately ignore since= (D-5): their membership changes because time passes, with no row changing",
        "The eight research-log and security-events tools state the re-import guarantee in their descriptions (#831)"
      ],
      removed_endpoints: [],
      removed_tools: [],
      prompts: [],
      removed_prompts: []
    },
    %{
      version: 5,
      date: ~D[2026-09-19],
      summary:
        "Sprint 13: the per-security derived metrics (ADR-0047, FR-39) — moving averages, " <>
          "realized volatility, maximum drawdown, momentum and the distance to the 52-week " <>
          "extremes over the security's own split-adjusted close series, every metric " <>
          "carrying its window and observation count and the payload its computation basis; " <>
          "level (a) reports and carries no signal, rating or action. Security events " <>
          "(ADR-0048, FR-44) — a dated calendar fact that books nothing, tracked for the " <>
          "WHOLE CATALOG rather than the holdings, with the four reads of §5 and the three " <>
          "writes that keep them current.",
      endpoints: [
        "GET /api/v1/securities/:security_id/metrics",
        "GET /api/v1/securities/:security_id/events",
        "POST /api/v1/securities/:security_id/events",
        "PATCH /api/v1/security_events/:id",
        "DELETE /api/v1/security_events/:id",
        "GET /api/v1/events/upcoming",
        "GET /api/v1/events/unconfirmed",
        "GET /api/v1/events/stale"
      ],
      tools: [
        "portfolixir.securities.metrics",
        "portfolixir.events.list",
        "portfolixir.events.create",
        "portfolixir.events.update",
        "portfolixir.events.delete",
        "portfolixir.events.upcoming",
        "portfolixir.events.unconfirmed",
        "portfolixir.events.stale"
      ],
      parameters: [
        "GET /api/v1/realized_gains and portfolixir.cashflow.realized_gains carry trades (the closed round-trips themselves, newest close first) and summary (realized_total, hit_rate, average_holding_period_days, trade_count) beside the annual matrix; the three figures are derived from the same converted set, and computation_basis.summary states their rules — limit= still cuts only the matrix's years (#807)",
        "GET /api/v1/journal and portfolixir.journal.list take limit= through the family's shared parser (#811): absent is the default 100, an oversized value is capped at 1000 and echoed in meta.filters.limit, and zero, a negative or a non-number is a 422 naming the field — the read carried its own identical copy of that parser until now"
      ],
      removed_endpoints: [],
      removed_tools: [],
      prompts: [],
      removed_prompts: []
    },
    %{
      version: 4,
      date: ~D[2026-09-15],
      summary:
        "Sprint 11: the limit surface finished (#776) — the four research-log reads, the " <>
          "snapshot list and the three cash-flow roll-ups take a bounded limit on the API and " <>
          "their MCP twins, the trades read records from/to as its bound, every bounded payload " <>
          "of the family echoes the limit it applied; the valuations carry price_date per " <>
          "position and stale_priced_count (#779, #610); the benchmark comparison — the " <>
          "portfolio's own flows replayed into a fixed rate or a flagged security — on both " <>
          "performance scopes (#572, ADR-0046).",
      endpoints: [
        "GET /api/v1/portfolios/:portfolio_id/performance/benchmark",
        "GET /api/v1/views/:view_id/performance/benchmark"
      ],
      tools: [
        "portfolixir.portfolios.benchmark",
        "portfolixir.views.benchmark"
      ],
      parameters: [
        "GET /api/v1/securities/:security_id/notes and portfolixir.notes.list take limit= (default 1000, maximum 10000): the newest entries; thesis_state still derives from the whole log (#776)",
        "GET /api/v1/notes/unreviewed, /notes/uncorroborated and /notes/expiring and their MCP twins take limit= (default 1000, maximum 10000): the most overdue positions, the newest entries, the soonest-expiring entries (#776)",
        "GET /api/v1/snapshots and portfolixir.snapshots.list take limit= (default 1000, maximum 10000): the newest snapshots (#776)",
        "GET /api/v1/realized_gains, /external_flows and /costs and the portfolixir.cashflow.* twins take limit= as a number of years (default 100, maximum 1000): the newest years of the annual matrix, computation_basis.window naming a cut (#776)",
        "GET /api/v1/securities/:security_id/trades and portfolixir.trades.list take no limit: from/to is the bound, stated in the payload's basis (#776)",
        "The eight bounded reads answer the limit they applied as limit in the data envelope; a malformed limit is 422 (#776)",
        "GET /api/v1/portfolios/:portfolio_id/valuation, /views/:view_id/valuation and /holdings/by_security and their MCP twins: every position carries price_date, and the two valuations carry stale_priced_count — quoted positions whose quote is older than the data-quality threshold, retired holdings left out (#779, #610)",
        "GET /api/v1/securities and portfolixir.securities.list take is_benchmark=true|false; the securities read, create and update carry the is_benchmark field (ADR-0046 §1, #572)"
      ],
      removed_endpoints: [],
      removed_tools: [],
      prompts: [],
      removed_prompts: []
    },
    %{
      version: 3,
      date: ~D[2026-09-05],
      summary:
        "Sprint 10 (ADR-0045, E21 security hardening): provenance fields are system-set — " <>
          "notes.append no longer takes author or machine_generated and transactions refuse " <>
          "import_hash (#766); every list read takes a bounded limit and the quote upsert a row " <>
          "cap (#771); the logo endpoint validates its URL and answers fixed messages (#762); " <>
          "repeated wrong bearer tokens are answered 429 with Retry-After (#771).",
      endpoints: [],
      tools: [],
      parameters: [
        "POST /api/v1/securities/:security_id/notes and portfolixir.notes.append: author is derived from the credential and machine_generated is reserved; both are ignored in the body (#766)",
        "POST and PATCH /api/v1/transactions and the MCP transaction writes refuse import_hash with 422 (#766)",
        "PATCH /api/v1/securities/:id and portfolixir.securities.update: attributes merge into the stored map, a null removes a key, logo_* keys are dropped (#766)",
        "GET /api/v1/transactions, /securities, /exchange_rates and /securities/:id/quotes and their MCP twins take limit= (defaults 10000 / 5000 / 50000 / 20000, maxima 50000 / 20000 / 200000 / 50000); a malformed limit is 422 (#771)",
        "PUT /api/v1/securities/:id/quotes and portfolixir.quotes.upsert refuse more than 10000 rows per request (#771)",
        "PUT /api/v1/securities/:id/logo: the URL must be https to a public address; refusals and download failures carry fixed messages (#762)",
        "Every /api/v1 route answers 429 with Retry-After after repeated wrong bearer tokens from one source (#771)"
      ],
      removed_endpoints: [],
      removed_tools: [],
      prompts: [],
      removed_prompts: []
    },
    %{
      version: 2,
      date: ~D[2026-09-03],
      summary:
        "Sprint 9 (ADR-0044, E20): the security research log — append and the four reads — " <>
          "with the thesis state in the security read; include_positions reaches the view valuation " <>
          "and min_drift the position-target listing (#740); the exchange-rate sync gains the " <>
          "historical backfill scope (#737); this contract read (#752).",
      endpoints: [
        "GET /api/v1/securities/:security_id/notes",
        "POST /api/v1/securities/:security_id/notes",
        "GET /api/v1/notes/unreviewed",
        "GET /api/v1/notes/uncorroborated",
        "GET /api/v1/notes/expiring",
        "GET /api/v1/contract"
      ],
      tools: [
        "portfolixir.notes.list",
        "portfolixir.notes.append",
        "portfolixir.notes.unreviewed",
        "portfolixir.notes.uncorroborated",
        "portfolixir.notes.expiring",
        "portfolixir.contract.get"
      ],
      parameters: [
        "GET /api/v1/securities/:id and portfolixir.securities.get carry thesis_state (ADR-0044 §1); fields= can select it",
        "GET /api/v1/views/:view_id/valuation and portfolixir.views.valuation take include_positions=false (#740)",
        "GET /api/v1/portfolios/:portfolio_id/position_targets and portfolixir.targets.list_positions take min_drift= and answer position_targets_total, drift_basis and drift_weight on kept rows (#740)",
        "POST /api/v1/exchange_rates/sync and portfolixir.exchange_rates.sync take scope=latest|history and answer scope (#737)"
      ],
      removed_endpoints: [],
      removed_tools: [],
      prompts: [],
      removed_prompts: []
    },
    %{
      version: 1,
      date: ~D[2026-09-03],
      summary:
        "Baseline: the surface as released in 0.8.0 (Sprint 8, 2026-08-22), recorded when the " <>
          "contract read was introduced so its first entry can name this batch's own additions.",
      endpoints: [
        "DELETE /api/v1/buckets/:id",
        "DELETE /api/v1/cash_accounts/:id",
        "DELETE /api/v1/classifications/:classification_id/assignments/:security_id",
        "DELETE /api/v1/classifications/:classification_id/categories/:id",
        "DELETE /api/v1/classifications/:id",
        "DELETE /api/v1/plans/:id",
        "DELETE /api/v1/portfolios/:portfolio_id/position_targets/:category_id/:security_id",
        "DELETE /api/v1/portfolios/:portfolio_id/targets/:category_id",
        "DELETE /api/v1/securities/:id",
        "DELETE /api/v1/securities/:security_id/identifier_aliases/:id",
        "DELETE /api/v1/securities/:security_id/logo",
        "DELETE /api/v1/securities_accounts/:id",
        "DELETE /api/v1/securities_accounts/:id/positions/:security_id/buckets",
        "DELETE /api/v1/snapshots/:id",
        "DELETE /api/v1/tax/allowance_orders/:id",
        "DELETE /api/v1/tax/profiles/:id",
        "DELETE /api/v1/tax/statement_snapshots/:id",
        "DELETE /api/v1/transactions/:id",
        "DELETE /api/v1/views/:id",
        "GET /api/v1/buckets",
        "GET /api/v1/buckets/:id",
        "GET /api/v1/cash_accounts",
        "GET /api/v1/cash_accounts/:id",
        "GET /api/v1/classifications",
        "GET /api/v1/costs",
        "GET /api/v1/exchange_rates",
        "GET /api/v1/external_flows",
        "GET /api/v1/holdings/by_security",
        "GET /api/v1/holdings/negative",
        "GET /api/v1/journal",
        "GET /api/v1/portfolios",
        "GET /api/v1/portfolios/:portfolio_id/allocation",
        "GET /api/v1/portfolios/:portfolio_id/cash_target",
        "GET /api/v1/portfolios/:portfolio_id/category-results",
        "GET /api/v1/portfolios/:portfolio_id/holdings",
        "GET /api/v1/portfolios/:portfolio_id/income",
        "GET /api/v1/portfolios/:portfolio_id/performance",
        "GET /api/v1/portfolios/:portfolio_id/plans",
        "GET /api/v1/portfolios/:portfolio_id/position_targets",
        "GET /api/v1/portfolios/:portfolio_id/risk",
        "GET /api/v1/portfolios/:portfolio_id/snapshots/:id/comparison",
        "GET /api/v1/portfolios/:portfolio_id/targets",
        "GET /api/v1/portfolios/:portfolio_id/valuation",
        "GET /api/v1/realized_gains",
        "GET /api/v1/securities",
        "GET /api/v1/securities/:id",
        "GET /api/v1/securities/:security_id/logo",
        "GET /api/v1/securities/:security_id/quotes",
        "GET /api/v1/securities/:security_id/trades",
        "GET /api/v1/securities/search",
        "GET /api/v1/securities_accounts",
        "GET /api/v1/securities_accounts/:id",
        "GET /api/v1/settings/default_view",
        "GET /api/v1/snapshots",
        "GET /api/v1/tax/allowance_orders",
        "GET /api/v1/tax/parameters",
        "GET /api/v1/tax/profiles",
        "GET /api/v1/tax/statement_snapshots",
        "GET /api/v1/tax/statement_snapshots/:id",
        "GET /api/v1/tax/trim_budget",
        "GET /api/v1/transactions",
        "GET /api/v1/transactions/:id",
        "GET /api/v1/views",
        "GET /api/v1/views/:id",
        "GET /api/v1/views/:view_id/performance",
        "GET /api/v1/views/:view_id/valuation",
        "PATCH /api/v1/buckets/:id",
        "PATCH /api/v1/cash_accounts/:id",
        "PATCH /api/v1/classifications/:classification_id/categories/:id",
        "PATCH /api/v1/classifications/:id",
        "PATCH /api/v1/plans/:id",
        "PATCH /api/v1/portfolios/:portfolio_id",
        "PATCH /api/v1/securities/:id",
        "PATCH /api/v1/securities_accounts/:id",
        "PATCH /api/v1/tax/profiles/:id",
        "PATCH /api/v1/tax/statement_snapshots/:id",
        "PATCH /api/v1/transactions/:id",
        "PATCH /api/v1/views/:id",
        "POST /api/v1/buckets",
        "POST /api/v1/cash_accounts",
        "POST /api/v1/cash_accounts/:id/balance",
        "POST /api/v1/classifications",
        "POST /api/v1/classifications/:classification_id/categories",
        "POST /api/v1/exchange_rates/sync",
        "POST /api/v1/holdings/reconcile",
        "POST /api/v1/plans/:id/activate",
        "POST /api/v1/plans/:id/duplicate",
        "POST /api/v1/portfolios",
        "POST /api/v1/securities",
        "POST /api/v1/securities/:security_id/isin-change",
        "POST /api/v1/securities/:security_id/logo/discover",
        "POST /api/v1/securities/:security_id/sync_quotes",
        "POST /api/v1/securities_accounts",
        "POST /api/v1/snapshots",
        "POST /api/v1/splits",
        "POST /api/v1/splits/preview",
        "POST /api/v1/tax/profiles",
        "POST /api/v1/tax/statement_snapshots",
        "POST /api/v1/transactions",
        "POST /api/v1/views",
        "PUT /api/v1/cash_accounts/:id/buckets",
        "PUT /api/v1/classifications/:classification_id/assignments",
        "PUT /api/v1/classifications/:classification_id/assignments/bulk",
        "PUT /api/v1/portfolios/:portfolio_id/cash_target",
        "PUT /api/v1/portfolios/:portfolio_id/targets",
        "PUT /api/v1/securities/:security_id/logo",
        "PUT /api/v1/securities/:security_id/quotes",
        "PUT /api/v1/securities_accounts/:id/buckets",
        "PUT /api/v1/securities_accounts/:id/positions/:security_id/buckets",
        "PUT /api/v1/settings/default_view",
        "PUT /api/v1/tax/allowance_orders",
        "PUT /api/v1/tax/parameters",
        "PUT /api/v1/views/:id/buckets"
      ],
      tools: [
        "portfolixir.securities.list",
        "portfolixir.securities.get",
        "portfolixir.securities.create",
        "portfolixir.securities.update",
        "portfolixir.securities.delete",
        "portfolixir.securities.isin_change",
        "portfolixir.securities.delete_isin_alias",
        "portfolixir.securities.search_online",
        "portfolixir.quotes.sync",
        "portfolixir.quotes.list",
        "portfolixir.quotes.upsert",
        "portfolixir.portfolios.list",
        "portfolixir.portfolios.create",
        "portfolixir.cash_accounts.list",
        "portfolixir.cash_accounts.create",
        "portfolixir.cash_accounts.update",
        "portfolixir.cash_accounts.delete",
        "portfolixir.securities_accounts.list",
        "portfolixir.securities_accounts.create",
        "portfolixir.securities_accounts.update",
        "portfolixir.securities_accounts.delete",
        "portfolixir.transactions.list",
        "portfolixir.transactions.create",
        "portfolixir.transactions.update",
        "portfolixir.transactions.delete",
        "portfolixir.splits.preview",
        "portfolixir.splits.create",
        "portfolixir.holdings.list",
        "portfolixir.cashflow.realized_gains",
        "portfolixir.cashflow.external_flows",
        "portfolixir.cashflow.costs",
        "portfolixir.holdings.by_security",
        "portfolixir.holdings.negative",
        "portfolixir.holdings.reconcile",
        "portfolixir.portfolios.valuation",
        "portfolixir.exchange_rates.list",
        "portfolixir.exchange_rates.sync",
        "portfolixir.classifications.list",
        "portfolixir.classifications.create",
        "portfolixir.classifications.categories.create",
        "portfolixir.classifications.update",
        "portfolixir.classifications.delete",
        "portfolixir.classifications.categories.update",
        "portfolixir.classifications.categories.delete",
        "portfolixir.classifications.assign",
        "portfolixir.classifications.assign_bulk",
        "portfolixir.classifications.unassign",
        "portfolixir.trades.list",
        "portfolixir.targets.list",
        "portfolixir.targets.set",
        "portfolixir.targets.delete",
        "portfolixir.targets.list_positions",
        "portfolixir.targets.delete_position",
        "portfolixir.portfolios.allocation",
        "portfolixir.portfolios.category_results",
        "portfolixir.portfolios.risk",
        "portfolixir.portfolios.cash_target",
        "portfolixir.portfolios.set_cash_target",
        "portfolixir.cash_accounts.set_balance",
        "portfolixir.portfolios.income",
        "portfolixir.portfolios.performance",
        "portfolixir.journal.list",
        "portfolixir.buckets.list",
        "portfolixir.buckets.get",
        "portfolixir.buckets.create",
        "portfolixir.buckets.update",
        "portfolixir.buckets.delete",
        "portfolixir.views.list",
        "portfolixir.views.get",
        "portfolixir.views.create",
        "portfolixir.views.update",
        "portfolixir.views.delete",
        "portfolixir.views.set_buckets",
        "portfolixir.views.valuation",
        "portfolixir.views.performance",
        "portfolixir.securities_accounts.set_buckets",
        "portfolixir.cash_accounts.set_buckets",
        "portfolixir.securities_accounts.set_position_buckets",
        "portfolixir.securities_accounts.clear_position_buckets",
        "portfolixir.settings.get_default_view",
        "portfolixir.settings.set_default_view",
        "portfolixir.plans.list",
        "portfolixir.plans.duplicate",
        "portfolixir.plans.activate",
        "portfolixir.plans.rename",
        "portfolixir.plans.delete",
        "portfolixir.snapshots.list",
        "portfolixir.snapshots.create",
        "portfolixir.snapshots.delete",
        "portfolixir.snapshots.comparison",
        "portfolixir.tax_parameters.list",
        "portfolixir.tax_parameters.upsert",
        "portfolixir.tax_profiles.list",
        "portfolixir.tax_profiles.create",
        "portfolixir.tax_profiles.update",
        "portfolixir.tax_profiles.delete",
        "portfolixir.allowance_orders.list",
        "portfolixir.allowance_orders.put",
        "portfolixir.allowance_orders.delete",
        "portfolixir.tax_snapshots.list",
        "portfolixir.tax_snapshots.get",
        "portfolixir.tax_snapshots.create",
        "portfolixir.tax_snapshots.update",
        "portfolixir.tax_snapshots.delete",
        "portfolixir.tax_snapshots.trim_budget"
      ],
      parameters: [],
      removed_endpoints: [],
      removed_tools: [],
      prompts: [],
      removed_prompts: []
    }
  ]

  @doc "The manifest, newest entry first."
  @spec entries() :: [entry()]
  def entries, do: @entries

  @doc "The current contract version — the newest entry's `version`."
  @spec version() :: pos_integer()
  def version, do: hd(@entries).version

  @doc "When the surface last changed — the newest entry's `date`."
  @spec last_changed_at() :: Date.t()
  def last_changed_at, do: hd(@entries).date

  @doc """
  The entries dated **strictly after** `since` (a `Date`), newest first — the
  `?since=` idea applied to the contract: an agent that stored
  `last_changed_at` asks for what moved since then.
  """
  @spec entries_since(Date.t()) :: [entry()]
  def entries_since(%Date{} = since),
    do: Enum.filter(@entries, &(Date.compare(&1.date, since) == :gt))

  @doc "Every endpoint the surface offers today: the union of the entries, removals applied."
  @spec endpoints() :: MapSet.t(String.t())
  def endpoints, do: current(:endpoints, :removed_endpoints)

  @doc "Every MCP tool the surface offers today: the union of the entries, removals applied."
  @spec tools() :: MapSet.t(String.t())
  def tools, do: current(:tools, :removed_tools)

  @doc "Every MCP prompt the companion offers today: the union of the entries, removals applied."
  @spec prompts() :: MapSet.t(String.t())
  def prompts, do: current(:prompts, :removed_prompts)

  # Oldest first: an entry may only remove what an earlier entry added.
  defp current(add_key, remove_key) do
    @entries
    |> Enum.reverse()
    |> Enum.reduce(MapSet.new(), fn entry, acc ->
      acc
      |> MapSet.union(MapSet.new(Map.get(entry, add_key, [])))
      |> MapSet.difference(MapSet.new(Map.get(entry, remove_key, [])))
    end)
  end
end
