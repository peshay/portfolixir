defmodule PortfolixirWeb.ApiV1ContractTest do
  # ADR-0044 §8 (issue #752): the contract-version read over the API.
  use PortfolixirWeb.ConnCase

  alias PortfolixirWeb.Api.V1.Contract

  defp get_json(conn, path, status \\ 200) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
    |> get(path)
    |> json_response(status)
  end

  # User story (ADR-0044 §8, issue #752):
  # As the operating agent,
  # I want one cheap read that says what the surface offers and when it last
  # changed, pollable with since=,
  # so that a capability shipped for me is not invisible until my next
  # requirements edition asks for it again.
  #
  # Acceptance criteria:
  # - GET /api/v1/contract answers version, last_changed_at, the totals and
  #   the entries newest first, each naming endpoints, tools and parameters.
  # - since=<date> narrows to entries strictly after it and answers changed;
  #   a since at or after last_changed_at answers changed: false and no
  #   entries; an invalid since is a 422.
  # - The first entry records this batch's own additions, #740's parameters
  #   included.
  test "serves the manifest, newest first, and answers since=", %{conn: conn} do
    %{"data" => data} = get_json(conn, "/api/v1/contract")

    assert data["version"] == Contract.version()
    assert data["last_changed_at"] == Date.to_iso8601(Contract.last_changed_at())
    assert data["since"] == nil
    assert data["changed"] == true
    assert data["endpoints_total"] == MapSet.size(Contract.endpoints())
    assert data["tools_total"] == MapSet.size(Contract.tools())
    assert data["contract_note"] =~ "since="

    [newest | _] = data["entries"]
    assert newest["version"] == Contract.version()

    # The newest entry says what moved — an entry that names nothing is the
    # failure mode this read exists to prevent. Which KIND of thing moved is
    # the batch's business (Sprint 11 moved parameters, Sprint 13 endpoints
    # and tools), so the assertion is on the entry saying something, plus
    # this batch's own additions below.
    assert newest["endpoints"] != [] or newest["tools"] != [] or
             newest["parameters"] != []

    # Sprint 20, commit group γ (version 17; β's 16 sits beneath it once the
    # groups are put in order): the agent's reads and writes, one entry for
    # the group, opened by C2's first surface change and extended by each
    # story after it. No route and no tool is added.
    assert newest["version"] == 17
    assert newest["date"] == "2026-10-08"
    assert newest["summary"] =~ "Sprint 20 γ"
    assert newest["endpoints"] == []
    assert newest["tools"] == []

    # #1103: the securities list takes is_retired, and a data_quality set
    # beside a narrowing it contradicts matches nothing.
    assert newest["summary"] =~ "#1103"

    assert Enum.any?(
             newest["parameters"],
             &(String.starts_with?(&1, "GET /api/v1/securities?is_retired=") and
                 &1 =~ "portfolixir.securities.list" and &1 =~ "is_benchmark=true" and
                 &1 =~ "empty list" and &1 =~ "#1103")
           )

    # #1113: a data_quality set pages after its rule.
    assert newest["summary"] =~ "#1113"

    assert Enum.any?(
             newest["parameters"],
             &(String.starts_with?(&1, "GET /api/v1/securities?data_quality=&limit=&offset=") and
                 &1 =~ "after the rule" and &1 =~ "#1113")
           )

    # #1133: the target writes take an optional plan_id, and an archived
    # plan is refused.
    assert newest["summary"] =~ "#1133"

    assert Enum.any?(
             newest["parameters"],
             &(String.starts_with?(&1, "PUT /api/v1/portfolios/:portfolio_id/targets") and
                 &1 =~ "plan_id" and &1 =~ "is archived" and
                 &1 =~ "portfolixir.targets.delete_position" and &1 =~ "#1133")
           )

    # #1143: a refused target or cash-target weight names its row.
    assert newest["summary"] =~ "#1143"

    assert Enum.any?(
             newest["parameters"],
             &(&1 =~ "PUT /api/v1/portfolios/:portfolio_id/cash_target" and &1 =~ "errors.row" and
                 &1 =~ "\"cash\"" and &1 =~ "#1143")
           )

    # #1135: the plan tools' descriptions name position targets.
    assert newest["summary"] =~ "#1135"

    assert Enum.any?(
             newest["parameters"],
             &(String.starts_with?(&1, "portfolixir.plans.duplicate and portfolixir.plans.delete") and
                 &1 =~ "position targets" and &1 =~ "#1135")
           )

    # #940 (C3): a parent past the tree's 32nd level is refused on parent_id,
    # and the category tools name the bound.
    assert newest["summary"] =~ "#940"

    assert Enum.any?(
             newest["parameters"],
             &(String.starts_with?(
                 &1,
                 "POST /api/v1/classifications/:classification_id/categories"
               ) and
                 &1 =~ "would put a category on level 33" and
                 &1 =~ "portfolixir.classifications.categories.update" and &1 =~ "#940")
           )

    # #953 (C3): an assignment's entry carries its before-image; a resent set
    # and a clear of an inheriting position leave none.
    assert newest["summary"] =~ "#953"

    assert Enum.any?(
             newest["parameters"],
             &(String.starts_with?(&1, "GET /api/v1/journal (portfolixir.journal.list)") and
                 &1 =~ "position_bucket_override" and
                 &1 =~ "a clear of a position that already inherits leaves no entry" and
                 &1 =~ "#953")
           )

    # #965 (C3): a delete's policy-rule 409 and an account merge's guard
    # name records by their ids.
    assert newest["summary"] =~ "#965"

    assert Enum.any?(
             newest["parameters"],
             &(String.starts_with?(&1, "DELETE /api/v1/securities/:id, DELETE /api/v1/views/:id") and
                 &1 =~ "is read by N policy rule(s): #<id> (<status>)" and
                 &1 =~ "portfolixir.cash_accounts.merge_preview" and
                 &1 =~ "security #<id> sits in" and &1 =~ "#965")
           )

    # #965, the γ closing act (security lens): a re-booked split's 422 names
    # its portfolio by id.
    assert Enum.any?(
             newest["parameters"],
             &(String.starts_with?(&1, "POST /api/v1/securities/:security_id/isin-change") and
                 &1 =~ "POST /api/v1/splits (portfolixir.splits.create)" and
                 &1 =~ "for portfolio #<id>" and &1 =~ "#965")
           )

    # #956 (C3) and #1137 (C4): the companion's HTTP listener compares a
    # browser's Origin whole, and binds loopback for an empty host.
    assert newest["summary"] =~ "#956"
    assert newest["summary"] =~ "#1137"

    assert Enum.any?(
             newest["parameters"],
             &(String.starts_with?(&1, "The MCP companion's HTTP listener") and
                 &1 =~ "origin not allowed" and &1 =~ "PORTFOLIXIR_MCP_ALLOWED_HOSTS" and
                 &1 =~ "[::1]" and &1 =~ "#956" and
                 &1 =~ "an empty or blank PORTFOLIXIR_MCP_HOST binds 127.0.0.1" and
                 &1 =~ "#1137")
           )

    # #974 (C4, the plan's D-11): the bearer checks compare the token first,
    # on the API and on the companion.
    assert newest["summary"] =~ "#974"

    assert Enum.any?(
             newest["parameters"],
             &(String.starts_with?(&1, "Every authenticated /api/v1 route") and
                 &1 =~ "the MCP companion's HTTP listener" and
                 &1 =~ "a correct token passes while its source is locked out" and
                 &1 =~ "a wrong token counts against its source, locked or not" and
                 &1 =~ "#974")
           )

    # #974, the γ closing act (security lens): the token compares first only
    # where the 32-byte floor holds; a from-source server reading
    # PORTFOLIXIR_API_TOKEN alone holds it to none and stays lock-first.
    assert Enum.any?(
             newest["parameters"],
             &(String.starts_with?(&1, "Every authenticated /api/v1 route") and
                 &1 =~ "while every configured token meets the 32-byte floor" and
                 &1 =~ "reads PORTFOLIXIR_API_TOKEN alone holds it to none" and
                 &1 =~ "consults the lock first, as before" and
                 not (&1 =~ "every token meets at boot"))
           )

    # #1159 (C5): a security merge records an ISIN choice and its date only
    # where it made the choice; a stored record keeps what it holds.
    assert newest["summary"] =~ "#1159"

    assert Enum.any?(
             newest["parameters"],
             &(String.starts_with?(&1, "POST /api/v1/securities/:id/merge") and
                 &1 =~ "portfolixir.merges.list" and
                 &1 =~ "manifest.choices holds identity_choice and isin_changed_on only where" and
                 &1 =~ "A record stored before keeps what it holds" and &1 =~ "#1159")
           )

    # #1159's rule on the collapse choice (D-14): every merge records
    # collapse_key_equal only where it had key-equal pairs.
    assert newest["summary"] =~ "collapse_key_equal only where it had key-equal pairs"

    assert Enum.any?(
             newest["parameters"],
             &(String.starts_with?(&1, "POST /api/v1/cash_accounts/:id/merge") and
                 &1 =~ "portfolixir.merges.list" and
                 &1 =~
                   "manifest.choices.collapse_key_equal holds the operator's choice only where" and
                 &1 =~ "a record stored before keeps what it holds" and &1 =~ "#1159")
           )

    # #1127 (C6): a security write that leaves the class empty stores bond
    # for a name with an explicit bond word; a stored class is kept.
    assert newest["summary"] =~ "#1127"

    assert Enum.any?(
             newest["parameters"],
             &(String.starts_with?(&1, "POST /api/v1/securities and PATCH") and
                 &1 =~ "stores bond where the name carries an explicit bond word" and
                 &1 =~ "A class stored before is kept" and &1 =~ "#1127")
           )

    # #1154, the γ closing act (correctness hunter): the contribution
    # analytics' stored rows gained the WKN, so both move to computation
    # version 3; the payload is unchanged.
    assert newest["summary"] =~ "#1154"

    assert Enum.any?(
             newest["parameters"],
             &(String.starts_with?(
                 &1,
                 "GET /api/v1/portfolios/:portfolio_id/performance/contribution"
               ) and
                 &1 =~ "performance_contribution and performance_view_contribution" and
                 &1 =~ "from computation version 2 to 3" and &1 =~ "carries no wkn" and
                 &1 =~ "#1154")
           )

    # Sprint 20, commit group β (version 16, after Sprint 19 PR β's 15): what
    # the ledger reports about it, the ADR-0015 amendment of 2026-10-07. B1
    # opened the entry (#1108): a cross-currency closed trade's fees and
    # taxes are converted at the trade's own rate; B2 rides it (#1107): the
    # Costs and income reports read them in the cash account's currency. No
    # route, tool or computation version moves; the four reads' figures do,
    # and the entry names them with identities 1 and 2.
    sprint20 = Enum.find(data["entries"], &(&1["version"] == 16))
    # Strictly after Sprint 19 PR β's entry (2026-10-07).
    assert sprint20["date"] == "2026-10-08"
    assert sprint20["summary"] =~ "Sprint 20 β"
    assert sprint20["summary"] =~ "ADR-0015 amendment of 2026-10-07"
    assert sprint20["summary"] =~ "cash account's currency"
    assert sprint20["summary"] =~ "No computation version moves"
    assert sprint20["endpoints"] == []
    assert sprint20["tools"] == []

    for issue <- ["#1108", "#1107", "#1051"] do
      assert sprint20["summary"] =~ issue, issue
    end

    assert Enum.any?(
             sprint20["parameters"],
             &(String.starts_with?(&1, "GET /api/v1/securities/:security_id/trades") and
                 &1 =~ "portfolixir.trades.list" and &1 =~ "settlement_fx_rate" and
                 &1 =~ "basis 1007.5, proceeds 1196.25, realized_pnl_abs 188.75" and
                 &1 =~ "computation_basis.fees_and_taxes" and &1 =~ "#1108")
           )

    # BCH-1 (closing act): the claim "all in currency_code" holds where the
    # sell and the lots it closes are booked in one currency, and the entry
    # names the case where they are not (#1198, an open decision).
    assert Enum.any?(
             sprint20["parameters"],
             &(String.starts_with?(&1, "GET /api/v1/securities/:security_id/trades") and
                 &1 =~
                   "all in currency_code where the sell and every lot it closes are " <>
                     "booked in one currency" and &1 =~ "#1198")
           )

    assert Enum.any?(
             sprint20["parameters"],
             &(String.starts_with?(&1, "GET /api/v1/realized_gains") and
                 &1 =~ "portfolixir.cashflow.realized_gains" and
                 &1 =~ "realized_base 151 EUR" and &1 =~ "#1108")
           )

    assert Enum.any?(
             sprint20["parameters"],
             &(String.starts_with?(&1, "GET /api/v1/costs") and
                 &1 =~ "portfolixir.cashflow.costs" and &1 =~ "fees 5, taxes 1, total 6 EUR" and
                 &1 =~ "computation_basis.currency" and &1 =~ "#1107")
           )

    assert Enum.any?(
             sprint20["parameters"],
             &(String.starts_with?(&1, "GET /api/v1/portfolios/:portfolio_id/income") and
                 &1 =~ "portfolixir.portfolios.income" and &1 =~ "gross 100, tax 20, net 80" and
                 &1 =~ "security_currency" and &1 =~ "#1107")
           )

    # B3 extends the entry (#1142, plan D-6): a return on no cost basis is
    # null, never "0", with its rule in the payload's computation basis,
    # on each read that serves the percentage, and annualized_return_reason
    # gains no_cost_basis.
    assert sprint20["summary"] =~ "B3, a zero cost basis has no return (#1142)"

    for {read, tool, fragments} <- [
          {"GET /api/v1/securities/:security_id/trades", "portfolixir.trades.list",
           [
             "realized_pnl_pct null",
             "unrealized_pnl_pct null",
             "annualized_return_reason no_cost_basis",
             "computation_basis.realized_pnl_pct",
             "computation_basis.unrealized_pnl_pct"
           ]},
          {"GET /api/v1/realized_gains", "portfolixir.cashflow.realized_gains",
           [
             "realized_pnl_pct null",
             "annualized_return_reason no_cost_basis",
             "computation_basis.realized_pnl_pct"
           ]},
          {"GET /api/v1/portfolios/:portfolio_id/holdings", "portfolixir.holdings.list",
           [
             "unrealized_pnl_pct null",
             "security_id=",
             "fields=",
             "computation_basis.unrealized_pnl_pct"
           ]}
        ] do
      assert Enum.any?(
               sprint20["parameters"],
               &(String.starts_with?(&1, read) and &1 =~ tool and &1 =~ "#1142" and
                   Enum.all?(fragments, fn fragment -> &1 =~ fragment end))
             ),
             read
    end

    # #1142's last sibling (D-14; D-6 answers it): the decomposition's three
    # percentages on a zero base_cost are null too, on a holding and on an
    # open lot, with the rule in computation_basis.decomposition_pct; the
    # B3 line no longer says they are unchanged.
    assert Enum.any?(
             sprint20["parameters"],
             &(String.starts_with?(&1, "GET /api/v1/portfolios/:portfolio_id/holdings") and
                 &1 =~ "portfolixir.holdings.list" and
                 &1 =~ "GET /api/v1/securities/:security_id/trades" and
                 &1 =~ "portfolixir.trades.list" and
                 &1 =~ "price_return_pct, currency_return_pct and total_return_base_pct null" and
                 &1 =~ "base_cost is \"0\"" and
                 &1 =~ "computation_basis.decomposition_pct" and &1 =~ "#1142")
           )

    refute Enum.any?(sprint20["parameters"], &(&1 =~ "of the decomposition are unchanged"))

    # B4 extends the entry (#1101, plan D-7): data_quality takes
    # implausible_quote, the held securities whose quotes contradict their
    # own bookings, with the findings and the computation basis in the
    # envelope; the MCP enum carries it.
    assert Enum.any?(
             sprint20["parameters"],
             &(String.starts_with?(&1, "GET /api/v1/securities?data_quality=") and
                 &1 =~ "portfolixir.securities.list" and &1 =~ "implausible_quote" and
                 &1 =~ "[1/2, 2]" and &1 =~ "7 days before" and &1 =~ "two_scales" and
                 &1 =~ "findings" and &1 =~ "computation_basis" and &1 =~ "#1101")
           )

    # The deposits-and-withdrawals read, the amendment's point 1 for a
    # deposit's or removal's cash (#1107).
    assert sprint20["summary"] =~ "deposits-and-withdrawals"

    assert Enum.any?(
             sprint20["parameters"],
             &(String.starts_with?(&1, "GET /api/v1/external_flows") and
                 &1 =~ "portfolixir.cashflow.external_flows" and
                 &1 =~ "reads deposits 100 EUR, where it read 80" and
                 &1 =~ "computation_basis.currency" and &1 =~ "#1107")
           )

    # Sprint 19, PR β (version 15, after PR α's 14): a stranger's first run
    # and the agent's reads, one entry for the lane PR. B5 adds the
    # performance family's Everything form and the all-portfolios category
    # result (#1056, #1091's read half, D-7), and names the survivor of a
    # merged-away benchmark security (#959); B2's missing logo file (#933)
    # and B3's companion failure modes (#1043, #1045) ride the entry. Found
    # by version from Sprint 20 on.
    beta = Enum.find(data["entries"], &(&1["version"] == 15))
    # Strictly after α's entry (2026-10-06), which since= compares against.
    assert beta["date"] == "2026-10-07"
    assert beta["summary"] =~ "Sprint 19 PR β"
    assert beta["tools"] == []

    assert beta["endpoints"] == [
             "GET /api/v1/performance",
             "GET /api/v1/performance/benchmark",
             "GET /api/v1/performance/contribution",
             "GET /api/v1/category-results"
           ]

    for issue <- ["#1056", "#1091", "#959", "#933", "#1043", "#1045"] do
      assert beta["summary"] =~ issue, issue
    end

    assert Enum.any?(
             beta["parameters"],
             &(String.starts_with?(&1, "GET /api/v1/securities/:id/merge_preview") and
                 &1 =~ "identifiers.differences" and &1 =~ "#933")
           )

    # #933, review pass 2: unambiguous about the path, and why MCP adds no tool.
    assert beta["summary"] =~ "its path is never cleared"
    assert beta["summary"] =~ "no logo-status tool"
    assert beta["summary"] =~ "projection=full"
    refute Enum.any?(beta["parameters"], &(&1 =~ "description unchanged"))

    assert Enum.any?(
             beta["parameters"],
             &(String.starts_with?(
                 &1,
                 "GET /api/v1/performance, GET /api/v1/performance/benchmark and GET /api/v1/performance/contribution"
               ) and
                 &1 =~ "EUR" and &1 =~ "first portfolio's base currency" and
                 &1 =~ "computation_basis.input_series" and &1 =~ "#1056")
           )

    assert Enum.any?(
             beta["parameters"],
             &(&1 =~ "portfolixir.views.performance" and &1 =~ "portfolixir.views.benchmark" and
                 &1 =~ "portfolixir.views.contribution" and &1 =~ "id" and &1 =~ "optional" and
                 &1 =~ "#1056")
           )

    assert Enum.any?(
             beta["parameters"],
             &(String.starts_with?(&1, "GET /api/v1/category-results") and &1 =~ "scope" and
                 &1 =~ "all" and &1 =~ "excluded_members" and &1 =~ "native_costs" and
                 &1 =~ "portfolixir.portfolios.category_results" and &1 =~ "#1091")
           )

    assert Enum.any?(
             beta["parameters"],
             &(&1 =~ "benchmark=security:" and &1 =~ "merged_into" and &1 =~ "#959")
           )

    assert Enum.any?(
             beta["parameters"],
             &(String.starts_with?(&1, "GET /api/v1/securities/:security_id/logo") and
                 &1 =~ "file_missing" and &1 =~ "has_logo" and &1 =~ "#933")
           )

    assert Enum.any?(
             beta["parameters"],
             &(String.starts_with?(&1, "GET /api/v1/securities?logo_status=") and
                 &1 =~ "data_quality=missing_logo" and &1 =~ "portfolixir.securities.list" and
                 &1 =~ "missing_logo (none and unlocked, or file gone)" and
                 &1 =~ "missing_logo (no stored logo, not locked to none)" and
                 &1 =~ "whatever its lock" and &1 =~ "#933")
           )

    assert Enum.any?(
             beta["parameters"],
             &(&1 =~ "502" and &1 =~ "504" and &1 =~ "outcome unknown" and &1 =~ "#1045")
           )

    assert Enum.any?(beta["parameters"], &(&1 =~ "exits 1" and &1 =~ "#1043"))

    # Sprint 19, PR α (version 14, after PR #1102's 13): the money a
    # stranger checks first, one entry for the lane PR. M3 opened it: the performance and the
    # contribution reads, in both forms, name a cash account that counted
    # zero for want of a rate path (#1055, ADR-0051 §10). No route and no
    # tool is added; M4, M6 and M7 extend the entry. Found by version from
    # PR β on.
    alpha = Enum.find(data["entries"], &(&1["version"] == 14))
    # M4, M6 and M7 extended the entry on 2026-10-06, so its date moved with
    # them: a since=2026-10-05 poller sees them.
    assert alpha["date"] == "2026-10-06"
    assert alpha["summary"] =~ "Sprint 19"
    assert alpha["summary"] =~ "M3"
    assert alpha["endpoints"] == []
    assert alpha["tools"] == []

    # M4 adds no field: a cross-currency trade's fees and taxes are read in
    # its cash account's currency, and the entry says which figures move,
    # a trade with no rate for its price currency included (#1051).
    assert alpha["summary"] =~ "M4"
    assert alpha["summary"] =~ "cash account's currency"
    assert alpha["summary"] =~ "#1051"
    assert alpha["summary"] =~ "a trade with no rate for its price currency"

    # M6 adds a payload field, no schema byte (D-10): every valuation read
    # counts the cash accounts it leaves out of total_cash for want of a
    # rate path, and its note says so (#1081, D-3).
    assert alpha["summary"] =~ "M6"
    assert alpha["summary"] =~ "#1081"
    assert alpha["summary"] =~ "unvalued_cash_count"

    assert Enum.any?(
             alpha["parameters"],
             &(String.starts_with?(
                 &1,
                 "GET /api/v1/portfolios/:portfolio_id/valuation, GET /api/v1/views/:view_id/valuation and GET /api/v1/valuation"
               ) and &1 =~ "portfolixir.portfolios.valuation" and
                 &1 =~ "portfolixir.views.valuation" and &1 =~ "unvalued_cash_count" and
                 &1 =~ "valuation_note" and &1 =~ "include_positions" and &1 =~ "#1081")
           )

    for read <- [
          "GET /api/v1/portfolios/:portfolio_id/performance and GET /api/v1/views/:view_id/performance",
          "GET /api/v1/portfolios/:portfolio_id/performance/contribution and " <>
            "GET /api/v1/views/:view_id/performance/contribution",
          "GET /api/v1/portfolios/:portfolio_id/performance/benchmark and " <>
            "GET /api/v1/views/:view_id/performance/benchmark"
        ] do
      assert Enum.any?(
               alpha["parameters"],
               &(String.starts_with?(&1, read) and &1 =~ "unvalued_cash_accounts" and
                   &1 =~ "first_rate_date" and &1 =~ "#1055")
             ),
             read
    end

    # M7 (#1068, D-15) adds a data_quality value and a reading field, no
    # tool: securities.list's data_quality takes two_scales, and the detail
    # read's bond.two_scales names its direction, the reverse band and the
    # master-data signal.
    assert alpha["summary"] =~ "M7"
    assert alpha["summary"] =~ "#1068"
    assert alpha["summary"] =~ "two_scales"

    assert Enum.any?(
             alpha["parameters"],
             &(String.starts_with?(&1, "GET /api/v1/securities?data_quality=") and
                 &1 =~ "portfolixir.securities.list" and &1 =~ "two_scales" and
                 &1 =~ "#1068")
           )

    assert Enum.any?(
             alpha["parameters"],
             &(String.starts_with?(&1, "GET /api/v1/securities/:id") and
                 &1 =~ "portfolixir.securities.get" and &1 =~ "direction" and
                 &1 =~ "reverse" and &1 =~ "1/500 to 1/20" and
                 &1 =~ "maturity_date or coupon_rate" and &1 =~ "now carries its figures")
           )

    # #1078 rides M7: the class a create or update stores for some names moves.
    assert alpha["summary"] =~ "#1078"
    refute alpha["summary"] =~ "with no figure changed, names a bond"

    assert Enum.any?(
             alpha["parameters"],
             &(String.starts_with?(&1, "POST /api/v1/securities and PATCH /api/v1/securities/:id") and
                 &1 =~ "Muster Computer Corp" and &1 =~ "#1078")
           )

    # The review round: the day before the window counts, and an account
    # still at zero on the last day says so.
    assert Enum.any?(
             alpha["parameters"],
             &(&1 =~ "the day before the window (the start value) included" and
                 &1 =~ "unvalued_through_end")
           )

    # Retiring over MCP (version 13, after Sprint 18's PR γ; PR #1102): the
    # update tool takes is_retired, the remedy the delete names when research
    # notes or policy-rule versions reference a security, and a retired
    # security leaves the three catalog-hygiene sets. No route or tool is
    # added. Found by version from PR α on.
    retire = Enum.find(data["entries"], &(&1["version"] == 13))
    assert retire["endpoints"] == []
    assert retire["tools"] == []
    assert retire["summary"] =~ "is_retired"

    assert Enum.any?(
             retire["parameters"],
             &(&1 =~ "portfolixir.securities.update" and &1 =~ "is_retired" and
                 &1 =~ "PATCH /api/v1/securities/:id" and &1 =~ "journaled")
           )

    assert Enum.any?(
             retire["parameters"],
             &(&1 =~ "data_quality" and &1 =~ "stale_quote" and &1 =~ "missing_quote" and
                 &1 =~ "missing_logo" and &1 =~ "retired")
           )

    # Sprint 18, PR γ (version 12, after PR β's 11): the screens a stranger
    # meets, one entry for the lane PR. U1 opened it: a split is deleted
    # whole, from any of its rows, in one journaled step (#912, ADR-0028 §1).
    # Found by version from here on.
    sprint18_gamma = Enum.find(data["entries"], &(&1["version"] == 12))
    assert sprint18_gamma["summary"] =~ "U1"
    assert sprint18_gamma["endpoints"] == ["DELETE /api/v1/splits/:transaction_id"]

    # Its MCP twin, an admin tool (the full profile only).
    assert sprint18_gamma["tools"] == ["portfolixir.splits.delete"]

    assert Enum.any?(
             sprint18_gamma["parameters"],
             &(&1 =~ "DELETE /api/v1/splits/:transaction_id" and &1 =~ "#912")
           )

    # U7 extends it: a bond's master data on the securities routes, and the
    # bond reading with each metric's computation basis on the detail read
    # (#330, ADR-0052). No endpoint is added.
    assert sprint18_gamma["summary"] =~ "U7"

    assert Enum.any?(
             sprint18_gamma["parameters"],
             &(&1 =~ "GET /api/v1/securities/:id" and &1 =~ "coupon_rate" and
                 &1 =~ "computation_basis" and &1 =~ "#330")
           )

    # The closing act on U7, finding 9: a yield is a ratio rounded at scale
    # 6, which the JSON then writes without trailing zeros, not a ratio "at
    # scale 6"; the two bond decimals follow the stored-amount rule.
    bond_entry = Enum.find(sprint18_gamma["parameters"], &(&1 =~ "coupon_rate" and &1 =~ "#330"))
    assert bond_entry =~ "rounded half up at scale 6"
    refute bond_entry =~ "a ratio at scale 6"
    assert bond_entry =~ "coupon_rate and face_value keep 6 decimal places"

    # Its MCP half: the two security writes take the fields, the detail tool
    # names the reading; no tool is added.
    assert Enum.any?(
             sprint18_gamma["parameters"],
             &(&1 =~ "portfolixir.securities.update" and &1 =~ "portfolixir.securities.get" and
                 &1 =~ "#330")
           )

    # Sprint 18, PR β (version 11): the operator's money surface, one entry
    # for the lane PR. F4 opened it: the category result takes the view scope
    # in the performance family's two forms (#901). Found by version from
    # here on.
    sprint18_beta = Enum.find(data["entries"], &(&1["version"] == 11))
    assert sprint18_beta["summary"] =~ "F4"
    assert "GET /api/v1/views/:view_id/category-results" in sprint18_beta["endpoints"]

    assert Enum.any?(
             sprint18_beta["parameters"],
             &(&1 =~ "portfolixir.portfolios.category_results" and &1 =~ "view" and
                 &1 =~ "#901")
           )

    # F5 extends it: the total across every portfolio, a read with no view,
    # reached by the view valuation tool without an id (#1007, D-5).
    assert sprint18_beta["summary"] =~ "F5"
    assert "GET /api/v1/valuation" in sprint18_beta["endpoints"]

    assert Enum.any?(
             sprint18_beta["parameters"],
             &(&1 =~ "portfolixir.views.valuation" and &1 =~ "#1007")
           )

    # F2 extends it: which position made how much of a period's result, in
    # the performance family's two forms (FR-41, ADR-0051 §6 and §11).
    assert sprint18_beta["summary"] =~ "F2"

    for endpoint <- [
          "GET /api/v1/portfolios/:portfolio_id/performance/contribution",
          "GET /api/v1/views/:view_id/performance/contribution"
        ] do
      assert endpoint in sprint18_beta["endpoints"]
    end

    assert Enum.any?(
             sprint18_beta["parameters"],
             &(&1 =~ "computation_basis" and &1 =~ "FR-41")
           )

    # Their MCP twins, read tools in every profile.
    assert "portfolixir.portfolios.contribution" in sprint18_beta["tools"]
    assert "portfolixir.views.contribution" in sprint18_beta["tools"]

    # Sprint 17, PR γ (version 10, after PR β's 9): the operator's due
    # surfaces — the annualized return on both closed-trade reads and the
    # unmatched sells (#984), the merge list's removed bookings per reason
    # (ADR-0050 §12), and the new read of a security's manual quotes with its
    # MCP twin (T-9). Found by version from here on.
    sprint17_gamma = Enum.find(data["entries"], &(&1["version"] == 10))

    assert sprint17_gamma["endpoints"] == [
             "GET /api/v1/securities/:security_id/quotes/manual"
           ]

    assert sprint17_gamma["tools"] == ["portfolixir.quotes.manual"]
    assert Enum.any?(sprint17_gamma["parameters"], &(&1 =~ "annualized_return"))
    assert Enum.any?(sprint17_gamma["parameters"], &(&1 =~ "unmatched_sells"))
    assert Enum.any?(sprint17_gamma["parameters"], &(&1 =~ "deleted_by_reason"))

    # Sprint 17's PR β (version 9): the lane's one entry, opened by the MCP
    # companion's tool profiles (A1, #992). It moves no route. Found by
    # version from here on.
    sprint17_beta = Enum.find(data["entries"], &(&1["version"] == 9))
    assert sprint17_beta["endpoints"] == []
    assert Enum.any?(sprint17_beta["parameters"], &(&1 =~ "PORTFOLIXIR_MCP_PROFILE"))
    # A2 (#993): the twin scope tools name each other, extending the entry.
    assert Enum.any?(sprint17_beta["parameters"], &(&1 =~ "Scope twin"))
    # A4 (#983): the two prompts, and why they are MCP only.
    assert Enum.any?(
             sprint17_beta["parameters"],
             &(&1 =~ "first_setup" and &1 =~ "import_converter")
           )

    assert sprint17_beta["summary"] =~ "MCP only"

    # Sprint 16 (version 8): the batch's one entry, opened by the error
    # envelope of the errors the server answers itself (E25 S2, F68). Found by
    # version from here on.
    sprint16 = Enum.find(data["entries"], &(&1["version"] == 8))
    assert Enum.any?(sprint16["parameters"], &(&1 =~ ~s({"errors": {"detail")))
    # ADR-0050 §11 L1: the identity-field freezes answer 422 on the PATCHes
    # that expose a currency, extending the same entry.
    assert Enum.any?(sprint16["parameters"], &(&1 =~ "is frozen once referenced"))

    # Sprint 15 (version 7): the policy-rules family (ADR-0049) — its reads,
    # its writes and their MCP twins. Found by version from here on.
    sprint15 = Enum.find(data["entries"], &(&1["version"] == 7))
    assert "GET /api/v1/portfolios/:portfolio_id/policy_rules" in sprint15["endpoints"]
    assert "POST /api/v1/policy_rules/:id/versions" in sprint15["endpoints"]
    assert "portfolixir.policy_rules.add_version" in sprint15["tools"]

    # Sprint 14 (version 6) moved parameters only: the portfolio metrics on
    # the risk read, `required` on both metric payloads (#838), since= on the
    # row collections (#830). Found by version, like every older entry.
    sprint14 = Enum.find(data["entries"], &(&1["version"] == 6))
    assert Enum.any?(sprint14["parameters"], &(&1 =~ "risk_free_rate"))
    assert Enum.any?(sprint14["parameters"], &(&1 =~ "required"))
    assert Enum.any?(sprint14["parameters"], &(&1 =~ "since="))

    sprint13 = Enum.find(data["entries"], &(&1["version"] == 5))
    assert "GET /api/v1/securities/:security_id/metrics" in sprint13["endpoints"]
    assert "portfolixir.securities.metrics" in sprint13["tools"]
    # Found by version, not by position: a newer entry must not move it.
    sprint9 = Enum.find(data["entries"], &(&1["version"] == 2))
    assert "GET /api/v1/securities/:security_id/notes" in sprint9["endpoints"]
    assert "GET /api/v1/contract" in sprint9["endpoints"]
    assert "portfolixir.notes.append" in sprint9["tools"]
    assert "portfolixir.contract.get" in sprint9["tools"]
    assert Enum.any?(sprint9["parameters"], &(&1 =~ "include_positions"))
    assert Enum.any?(sprint9["parameters"], &(&1 =~ "min_drift"))
    assert Enum.any?(sprint9["parameters"], &(&1 =~ "scope=latest|history"))

    # Strictly after the last change: nothing moved.
    last = Contract.last_changed_at()

    %{"data" => quiet} = get_json(conn, "/api/v1/contract?since=#{Date.to_iso8601(last)}")
    assert quiet["changed"] == false
    assert quiet["entries"] == []
    assert quiet["since"] == Date.to_iso8601(last)

    # The day before: everything dated on the last-changed day is new.
    day_before = Date.add(last, -1)
    %{"data" => moved} = get_json(conn, "/api/v1/contract?since=#{Date.to_iso8601(day_before)}")
    assert moved["changed"] == true
    assert Enum.all?(moved["entries"], &(&1["date"] > Date.to_iso8601(day_before)))

    assert %{"errors" => %{"since" => ["is invalid"]}} =
             get_json(conn, "/api/v1/contract?since=yesterday", 422)
  end

  test "a blank since means the full manifest and a non-string since is a 422", %{conn: conn} do
    assert get_json(conn, "/api/v1/contract?since=")["data"]["since"] == nil

    assert %{"errors" => %{"since" => ["is invalid"]}} =
             get_json(conn, "/api/v1/contract?since[]=x", 422)
  end
end
