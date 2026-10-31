defmodule PortfolixirWeb.ApiV1CrossCurrencyTradesTest do
  # The ADR-0015 amendment of 2026-10-07, identity 1 (#1108, risk-tier money):
  # a cross-currency closed trade read over the API, through the security's
  # trades read and the realized-gains read, is in one currency — its fees
  # and taxes, recorded in the cash account's currency, converted at the
  # trade's own stored settlement_fx_rate — and the payloads say so. The
  # Costs roll-up reads the same fees in that account's currency (#1107,
  # identity 2).
  # Synthetic figures only.
  use PortfolixirWeb.ConnCase

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1, cross_trade!: 3]

  alias Portfolixir.Fx

  defp get_json(conn, path) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
    |> get(path)
    |> json_response(200)
  end

  defp rates! do
    {:ok, _} =
      [~D[2025-04-01], ~D[2025-05-02]]
      |> Enum.map(fn date ->
        %{base_currency: "EUR", quote_currency: "USD", date: date, rate: "1.25", source: "manual"}
      end)
      |> Fx.upsert_many()
  end

  # A trade as a Portfolio Performance import books it (ADR-0033): 10 shares
  # priced in the EUR account's currency, with the legs where given.
  defp import_form_trade!(world, fund, opts) do
    {:ok, tx} =
      Portfolixir.Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        cash_account_id: world.cash.id,
        security_id: fund.id,
        type: Keyword.fetch!(opts, :type),
        date: Keyword.fetch!(opts, :date),
        quantity: "10",
        price: Keyword.fetch!(opts, :price),
        fees: Keyword.get(opts, :fees, "0"),
        taxes: Keyword.get(opts, :taxes, "0"),
        currency_code: "EUR",
        security_amount: Keyword.get(opts, :security_amount),
        settlement_amount: Keyword.get(opts, :settlement_amount),
        settlement_fx_rate: if(Keyword.has_key?(opts, :security_amount), do: "0.8"),
        gross_amount: Keyword.fetch!(opts, :gross)
      })

    tx
  end

  # Buy 10 at 100 USD settled 800.00 EUR, fees 5.00 and taxes 1.00 EUR (cash
  # 806.00); sell 10 at 120 USD settled 960.00 EUR, fees 3.00 EUR (cash
  # 957.00). 1 EUR = 1.25 USD on both dates.
  defp seed! do
    world = base_world(name: "Wire Cross", cash_name: "Wire Cash", depot_name: "Wire Depot")
    fund = create_security!(name: "Wire Dollar Fund", ticker: "WDF", currency: "USD")

    {:ok, _} =
      [~D[2025-04-01], ~D[2025-05-02]]
      |> Enum.map(fn date ->
        %{base_currency: "EUR", quote_currency: "USD", date: date, rate: "1.25", source: "manual"}
      end)
      |> Fx.upsert_many()

    cross_trade!(world, fund,
      quantity: "10",
      price: "100",
      settled: "800.00",
      fees: "5.00",
      taxes: "1.00",
      gross: "806.00",
      date: ~D[2025-04-01]
    )

    cross_trade!(world, fund,
      type: "sell",
      quantity: "10",
      price: "120",
      settled: "960.00",
      fees: "3.00",
      gross: "957.00",
      date: ~D[2025-05-02]
    )

    fund
  end

  # User story (#1108, identity 1 over the API):
  # As the operating LLM agent,
  # I want a cross-currency closed trade's basis, proceeds and result in the
  # security's currency on the security's trades read, the fees and taxes in
  # that currency too,
  # so that the figures I quote add up and say which rate converted the fees.
  #
  # Acceptance criteria:
  # - closed_trades[0] reads basis 1007.5, proceeds 1196.25, realized_pnl_abs
  #   188.75, buy_fees 6.25, buy_taxes 1.25, sell_fees 3.75, in USD.
  # - computation_basis.fees_and_taxes says the fees and taxes are read in
  #   the cash account's currency and converted at the trade's own rate.
  test "GET /api/v1/securities/:id/trades reads identity 1 in the security's currency", %{
    conn: conn
  } do
    fund = seed!()

    %{"data" => data} = get_json(conn, "/api/v1/securities/#{fund.id}/trades")

    assert [trade] = data["closed_trades"]

    assert Map.take(trade, [
             "basis",
             "proceeds",
             "realized_pnl_abs",
             "buy_fees",
             "buy_taxes",
             "sell_fees",
             "sell_taxes",
             "currency_code"
           ]) == %{
             "basis" => "1007.5",
             "proceeds" => "1196.25",
             "realized_pnl_abs" => "188.75",
             "buy_fees" => "6.25",
             "buy_taxes" => "1.25",
             "sell_fees" => "3.75",
             "sell_taxes" => "0",
             "currency_code" => "USD"
           }

    basis = data["computation_basis"]["fees_and_taxes"]
    assert basis =~ "cash account's currency"
    assert basis =~ "settlement_fx_rate"
  end

  # User story (#1108, identity 1 over the API; D-1 criterion 2, round trip 4):
  # As the operating LLM agent,
  # I want the realized-gains read to carry the same trade and its result in
  # the base currency,
  # so that the round trip reads 151.00 EUR, the cash it moved.
  #
  # Acceptance criteria:
  # - trades[0] reads basis 1007.5, proceeds 1196.25, realized_pnl_abs 188.75
  #   in USD and realized_base 151 in EUR; summary.realized_total is 151.
  # - computation_basis.fees_and_taxes states the rule.
  test "GET /api/v1/realized_gains reads identity 1: 151.00 EUR", %{conn: conn} do
    fund = seed!()

    %{"data" => data} = get_json(conn, "/api/v1/realized_gains")

    assert [trade] = data["trades"]

    assert Map.take(trade, [
             "security_id",
             "basis",
             "proceeds",
             "realized_pnl_abs",
             "currency_code",
             "realized_base"
           ]) == %{
             "security_id" => fund.id,
             "basis" => "1007.5",
             "proceeds" => "1196.25",
             "realized_pnl_abs" => "188.75",
             "currency_code" => "USD",
             "realized_base" => "151"
           }

    assert data["summary"]["realized_total"] == "151"

    basis = data["computation_basis"]["fees_and_taxes"]
    assert basis =~ "cash account's currency"
    assert basis =~ "settlement_fx_rate"
  end

  # User story (#1198, Sprint 21 α3; the ADR-0015 amendment of 2026-10-09,
  # point 5; the AGENTS.md metric rule):
  # As the operating LLM agent quoting a closed trade's figures,
  # I want computation_basis.fees_and_taxes to say that a closed trade is in
  # its sell's currency, every lot entering through its own legs, and what
  # happens to a lot without one,
  # so that "all in currency_code" holds for every trade I read, and the
  # open decision it used to name is gone.
  #
  # Acceptance criteria:
  # - On the trades read and the realized-gains read the sentence states
  #   points 2 to 4: each lot enters in the sell's currency through its own
  #   stored legs, never a rate looked up; a lot without the leg makes the
  #   trade unavailable (missing_settlement_leg); a trade whose sell and lots
  #   share one currency reads them as booked; an imported lot's legs come
  #   from the hub rate stored for its booking date.
  # - It no longer names issue #1198 as an open decision.
  # - computation_basis.realized_pnl_pct says its currency_code holds for
  #   every trade.
  test "computation_basis.fees_and_taxes states a closed trade in one currency (#1198)", %{
    conn: conn
  } do
    fund = seed!()

    for path <- ["/api/v1/securities/#{fund.id}/trades", "/api/v1/realized_gains"] do
      %{"data" => %{"computation_basis" => %{"fees_and_taxes" => basis} = computation}} =
        get_json(conn, path)

      assert basis =~ "A closed trade is in its sell's currency_code", path
      assert basis =~ "through the lot's own stored settlement legs, never through a rate", path
      assert basis =~ "unavailable_reason missing_settlement_leg", path
      assert basis =~ "lots_missing_leg", path
      assert basis =~ "all in currency_code for every available trade", path
      assert basis =~ "the EUR hub rate stored for its booking date (ADR-0033)", path
      refute basis =~ "open decision", path
      refute basis =~ "#1198", path

      assert computation["realized_pnl_pct"] =~ "in the trade's currency_code, for every trade",
             path
    end
  end

  # User story (#1198, Sprint 21 α3; identity 2b over the API):
  # As the operating LLM agent,
  # I want a dollar share bought through the booking form and sold through a
  # euro import to read in euros, the lot at the euros it cost,
  # so that a gain never reads as a loss.
  #
  # Acceptance criteria:
  # - closed_trades[0] reads currency_code EUR, basis 806, proceeds 957,
  #   realized_pnl_abs 151 (before: basis 1007.5, realized −50.5), and
  #   unavailable_reason null; realized_gains reads realized_base 151.
  test "a form lot closed by an imported sale reads in euros over the API (identity 2b)", %{
    conn: conn
  } do
    world =
      base_world(name: "Wire Reverse", cash_name: "Reverse Cash", depot_name: "Reverse Depot")

    fund = create_security!(name: "Wire Reverse Fund", ticker: "WRF", currency: "USD")
    rates!()

    cross_trade!(world, fund,
      quantity: "10",
      price: "100",
      settled: "800.00",
      fees: "5.00",
      taxes: "1.00",
      gross: "806.00",
      date: ~D[2025-04-01]
    )

    import_form_trade!(world, fund,
      type: "sell",
      date: ~D[2025-05-02],
      price: "96",
      fees: "3",
      security_amount: "1200",
      settlement_amount: "960",
      gross: "957"
    )

    %{"data" => data} = get_json(conn, "/api/v1/securities/#{fund.id}/trades")
    assert [trade] = data["closed_trades"]

    assert Map.take(trade, [
             "currency_code",
             "basis",
             "proceeds",
             "realized_pnl_abs",
             "unavailable_reason",
             "lots_missing_leg"
           ]) == %{
             "currency_code" => "EUR",
             "basis" => "806",
             "proceeds" => "957",
             "realized_pnl_abs" => "151",
             "unavailable_reason" => nil,
             "lots_missing_leg" => []
           }

    %{"data" => gains} = get_json(conn, "/api/v1/realized_gains")
    assert [%{"realized_base" => "151"}] = gains["trades"]
  end

  # User story (#1198, Sprint 21 α3; identity 3 over the API):
  # As the operating LLM agent,
  # I want a closed trade whose lot has no leg in the sale's currency kept on
  # the trades read with its sale's figures, null for the rest, its reason
  # and the lot named, and named apart in the realized-gains read's
  # excluded,
  # so that I never sum it and I can say what fixes it.
  #
  # Acceptance criteria:
  # - closed_trades[0]: proceeds 1196.25, sell_fees 3.75, avg_sell_price 120,
  #   null basis, avg_buy_price, buy_fees, buy_taxes, realized_pnl_abs,
  #   realized_pnl_pct and annualized_return; annualized_return_reason and
  #   unavailable_reason missing_settlement_leg; lots_missing_leg
  #   [{open_date 2025-04-01, currency_code EUR}].
  # - /api/v1/realized_gains: no trade, realized_total 0, excluded count 1
  #   with by_reason.missing_settlement_leg naming the security and
  #   by_reason.no_rate empty.
  test "a lot without its leg reads unavailable and named over the API (identity 3)", %{
    conn: conn
  } do
    world =
      base_world(name: "Wire Legless", cash_name: "Legless Cash", depot_name: "Legless Depot")

    fund = create_security!(name: "Wire Legless Fund", ticker: "WLF", currency: "USD")
    rates!()

    import_form_trade!(world, fund,
      type: "buy",
      date: ~D[2025-04-01],
      price: "80",
      fees: "5",
      taxes: "1",
      gross: "806"
    )

    cross_trade!(world, fund,
      type: "sell",
      quantity: "10",
      price: "120",
      settled: "960.00",
      fees: "3.00",
      gross: "957.00",
      date: ~D[2025-05-02]
    )

    %{"data" => data} = get_json(conn, "/api/v1/securities/#{fund.id}/trades")
    assert [trade] = data["closed_trades"]

    assert Map.take(trade, [
             "proceeds",
             "sell_fees",
             "avg_sell_price",
             "basis",
             "avg_buy_price",
             "buy_fees",
             "buy_taxes",
             "realized_pnl_abs",
             "realized_pnl_pct",
             "annualized_return",
             "annualized_return_reason",
             "unavailable_reason",
             "lots_missing_leg",
             "currency_code"
           ]) == %{
             "proceeds" => "1196.25",
             "sell_fees" => "3.75",
             "avg_sell_price" => "120",
             "basis" => nil,
             "avg_buy_price" => nil,
             "buy_fees" => nil,
             "buy_taxes" => nil,
             "realized_pnl_abs" => nil,
             "realized_pnl_pct" => nil,
             "annualized_return" => nil,
             "annualized_return_reason" => "missing_settlement_leg",
             "unavailable_reason" => "missing_settlement_leg",
             "lots_missing_leg" => [%{"open_date" => "2025-04-01", "currency_code" => "EUR"}],
             "currency_code" => "USD"
           }

    %{"data" => gains} = get_json(conn, "/api/v1/realized_gains")
    assert gains["trades"] == []
    assert gains["summary"]["realized_total"] == "0"

    assert gains["excluded"] == %{
             "count" => 1,
             "securities" => ["Wire Legless Fund"],
             "by_reason" => %{
               "no_rate" => %{"count" => 0, "securities" => []},
               "missing_settlement_leg" => %{"count" => 1, "securities" => ["Wire Legless Fund"]}
             }
           }
  end

  # User story (#1107, identity 2 over the API):
  # As the operating LLM agent,
  # I want the Costs roll-up to read a cross-currency trade's fees and taxes
  # in its cash account's currency,
  # so that the costs I report are the euros the broker charged.
  #
  # Acceptance criteria:
  # - Buy 10 at 100 USD settled 790.00 EUR, fees 5.00 and taxes 1.00 EUR:
  #   the month reads fees 5, taxes 1, the year total 6 (before: 4, 0.8, 4.8).
  # - computation_basis.currency states the rule.
  test "GET /api/v1/costs reads identity 2 in the account's currency", %{conn: conn} do
    world = base_world(name: "Wire Costs", cash_name: "Wire Cost Cash", depot_name: "Wire Desk")
    fund = create_security!(name: "Wire Cost Fund", ticker: "WCF", currency: "USD")

    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2026-05-05],
          rate: "1.25",
          source: "manual"
        }
      ])

    cross_trade!(world, fund,
      quantity: "10",
      price: "100",
      settled: "790.00",
      fees: "5.00",
      taxes: "1.00",
      gross: "796.00",
      date: ~D[2026-05-05]
    )

    %{"data" => data} = get_json(conn, "/api/v1/costs")

    assert [year] = data["annual"]
    assert year["months"]["5"] == %{"fees" => "5", "taxes" => "1"}
    assert year["total"] == "6"
    assert data["excluded"] == %{"count" => 0, "currencies" => []}
    assert data["computation_basis"]["currency"] =~ "cash account's currency"
  end
end
