defmodule PortfolixirWeb.ApiV1FeesInFiguresTest do
  # #1212 (Sprint 21 α11, risk tier): the holdings, category-result and
  # trades reads state whether a buy's or a sell's fees and taxes are in each
  # money figure. The figures themselves do not change: the first test pins
  # every money figure of the three payloads as the base commit serves them.
  # Synthetic figures only.
  use PortfolixirWeb.ConnCase

  import Portfolixir.WorldFixtures,
    only: [
      base_world: 1,
      buy!: 3,
      create_security!: 1,
      cross_trade!: 3,
      deposit!: 3,
      put_quote!: 3,
      sell!: 3
    ]

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.Fx

  defp get_json(conn, path) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
    |> get(path)
    |> json_response(200)
  end

  # Arbolia Inc. (USD) through the EUR account "Test-Cash": buy 10 at 100 USD
  # settled 790.00 EUR, fees 5.00 and taxes 1.00 EUR (cash 796.00). 1 EUR =
  # 1.25 USD; latest close 110 USD.
  #
  # Wrenfield Gardens AG (EUR): buy 20 at 50.00 with fees 2.00 and taxes
  # 0.50; sell 5 at 60.00 with fees 1.00 and taxes 0.25; latest close 55.00.
  #
  # Both are filed under "Core" of the classification "Strategy".
  defp seed! do
    world =
      base_world(name: "Fees In Figures", cash_name: "Test-Cash", depot_name: "Depot Muster")

    arbolia = create_security!(name: "Arbolia Inc.", ticker: "ARBL", currency: "USD")
    wrenfield = create_security!(name: "Wrenfield Gardens AG", ticker: "WGA")

    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2026-03-02],
          rate: "1.25",
          source: "manual"
        }
      ])

    deposit!(world, "5000", ~D[2026-03-01])

    cross_trade!(world, arbolia,
      quantity: "10",
      price: "100",
      settled: "790.00",
      fees: "5.00",
      taxes: "1.00",
      gross: "796.00",
      date: ~D[2026-03-02]
    )

    buy!(world, wrenfield,
      quantity: "20",
      price: "50.00",
      fees: "2.00",
      taxes: "0.50",
      date: ~D[2026-03-03]
    )

    sell!(world, wrenfield,
      quantity: "5",
      price: "60.00",
      fees: "1.00",
      taxes: "0.25",
      date: ~D[2026-04-01]
    )

    put_quote!(arbolia, ~D[2026-04-02], "110")
    put_quote!(wrenfield, ~D[2026-04-02], "55.00")

    {:ok, classification} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

    {:ok, core} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Core"
      })

    for security <- [arbolia, wrenfield] do
      {:ok, _} =
        Classifications.assign_security(Actor.owner_ui(), security.id, classification.id, core.id)
    end

    %{world: world, arbolia: arbolia, wrenfield: wrenfield, classification: classification}
  end

  @holding_figures ~w(quantity avg_cost cost_basis latest_price market_value unrealized_pnl_abs
                      unrealized_pnl_pct base_cost base_currency price_return_abs
                      currency_return_abs total_return_base_abs currency_code)

  @open_lot_figures ~w(quantity original_quantity buy_price buy_price_native buy_fees buy_taxes
                       latest_price unrealized_pnl_abs unrealized_pnl_pct base_cost currency_code)

  @closed_trade_figures ~w(quantity avg_buy_price avg_sell_price buy_fees buy_taxes sell_fees
                           sell_taxes basis proceeds realized_pnl_abs realized_pnl_pct
                           currency_code)

  @category_figures ~w(invested current_value result_abs result_pct)

  # User story (#1212, Sprint 21 α11): As the operating LLM agent, I want
  # the holdings, category-result and trades reads to keep every figure they
  # served before their definitions were written down, so that stating what
  # a figure counts changes no figure I already quoted.
  #
  # Acceptance criteria (taken on the base commit, where it passes):
  # - Holdings: Arbolia cost_basis 1000 USD, avg_cost 100, base_cost 790 EUR
  #   (the settlement without the 6.00 of fees and taxes), market_value
  #   1100, unrealized_pnl_abs 100, price_return_abs 80, currency_return_abs
  #   10, total_return_base_abs 90; Wrenfield cost_basis 750, avg_cost 50,
  #   base_cost 750, market_value 825, unrealized_pnl_abs 75.
  # - Trades (Wrenfield): the open lot 15 of 20 at 50.00, buy_fees 2.00,
  #   buy_taxes 0.50, unrealized_pnl_abs 75; the closed trade's basis 250.625
  #   (5 × 50 + 0.50 + 0.125 of the buy's costs), proceeds 298.75
  #   (5 × 60 − 1.00 − 0.25), realized_pnl_abs 48.125.
  # - Category result: Core invested 1540 (790 + 750), current_value 1705
  #   (880 + 825), result_abs 165.
  test "the three payloads' money figures, as the base commit serves them", %{conn: conn} do
    s = seed!()

    %{"data" => holdings} = get_json(conn, "/api/v1/portfolios/#{s.world.portfolio.id}/holdings")

    by_security = Map.new(holdings, &{&1["security_id"], Map.take(&1, @holding_figures)})

    assert by_security[s.arbolia.id] == %{
             "quantity" => "10",
             "avg_cost" => "100",
             "cost_basis" => "1000",
             "latest_price" => "110",
             "market_value" => "1100",
             "unrealized_pnl_abs" => "100",
             "unrealized_pnl_pct" => "0.1",
             "base_cost" => "790",
             "base_currency" => "EUR",
             "price_return_abs" => "80",
             "currency_return_abs" => "10",
             "total_return_base_abs" => "90",
             "currency_code" => "USD"
           }

    assert by_security[s.wrenfield.id] == %{
             "quantity" => "15",
             "avg_cost" => "50",
             "cost_basis" => "750",
             "latest_price" => "55",
             "market_value" => "825",
             "unrealized_pnl_abs" => "75",
             "unrealized_pnl_pct" => "0.1",
             "base_cost" => "750",
             "base_currency" => "EUR",
             "price_return_abs" => "75",
             "currency_return_abs" => "0",
             "total_return_base_abs" => "75",
             "currency_code" => "EUR"
           }

    %{"data" => trades} = get_json(conn, "/api/v1/securities/#{s.wrenfield.id}/trades")

    assert [lot] = trades["open_lots"]

    assert Map.take(lot, @open_lot_figures) == %{
             "quantity" => "15",
             "original_quantity" => "20",
             "buy_price" => "50",
             "buy_price_native" => "50",
             "buy_fees" => "2",
             "buy_taxes" => "0.5",
             "latest_price" => "55",
             "unrealized_pnl_abs" => "75",
             "unrealized_pnl_pct" => "0.1",
             "base_cost" => "750",
             "currency_code" => "EUR"
           }

    assert [trade] = trades["closed_trades"]

    assert Map.take(trade, @closed_trade_figures) == %{
             "quantity" => "5",
             "avg_buy_price" => "50",
             "avg_sell_price" => "60",
             "buy_fees" => "0.5",
             "buy_taxes" => "0.125",
             "sell_fees" => "1",
             "sell_taxes" => "0.25",
             "basis" => "250.625",
             "proceeds" => "298.75",
             "realized_pnl_abs" => "48.125",
             "realized_pnl_pct" => "0.1920199501246882793017456359102244",
             "currency_code" => "EUR"
           }

    %{"data" => result} =
      get_json(
        conn,
        "/api/v1/portfolios/#{s.world.portfolio.id}/category-results" <>
          "?classification_id=#{s.classification.id}"
      )

    assert [core] = result["categories"]

    assert Map.take(core, @category_figures) == %{
             "invested" => "1540",
             "current_value" => "1705",
             "result_abs" => "165",
             "result_pct" => "0.1071428571428571428571428571428571"
           }

    positions = Map.new(core["positions"], &{&1["security_id"], Map.take(&1, ~w(invested))})
    assert positions[s.arbolia.id] == %{"invested" => "790"}
    assert positions[s.wrenfield.id] == %{"invested" => "750"}
  end

  # User story (#1212, Sprint 21 α11): As the operating LLM agent, I want
  # each of the three reads to say whether a buy's and a sell's fees and
  # taxes are in each money figure it serves, so that I never set an open
  # position's cost (790,00, the settlement without its 6,00 of costs)
  # against a closed trade's basis (which counts them) as if they meant the
  # same thing.
  #
  # Acceptance criteria (the computation basis on the payload, AGENTS.md):
  # - Holdings: computation_basis.fees_and_taxes_in_figures says cost_basis,
  #   avg_cost and base_cost are without the buys' fees and taxes, that the
  #   unrealized P&L and its decomposition are measured against them, and
  #   that a closed trade's basis counts them once the shares are sold.
  # - Trades: computation_basis.fees_and_taxes_in_figures says an open lot's
  #   buy prices, base_cost and unrealized P&L are without them, that its
  #   buy_fees and buy_taxes are the whole buy's, for original_quantity (the
  #   open lot 15 of 20 carries buy_fees 2.00 while the closed trade's basis
  #   already holds 0.50 of them), a closed trade's basis includes the
  #   buy's, prorated, its proceeds are net of the sell's, and
  #   realized_pnl_abs is after all four.
  # - Category result: basis_note says invested is the members' base_cost,
  #   without the buys' fees and taxes, so the result is before them.
  # - The statement is the same on every form of the holdings read
  #   (security_id=, fields=).
  test "each read states whether fees and taxes are in its figures", %{conn: conn} do
    s = seed!()

    holdings = get_json(conn, "/api/v1/portfolios/#{s.world.portfolio.id}/holdings")
    held = holdings["computation_basis"]["fees_and_taxes_in_figures"]

    assert held =~
             "cost_basis (quantity x price), avg_cost (cost_basis per share) and base_cost " <>
               "are without the buys' fees and taxes"

    assert held =~ "unrealized_pnl_* and the decomposition"
    assert held =~ "a closed trade's basis counts them"

    narrowed =
      get_json(
        conn,
        "/api/v1/portfolios/#{s.world.portfolio.id}/holdings" <>
          "?security_id=#{s.arbolia.id}&fields=security_id,base_cost"
      )

    assert narrowed["computation_basis"]["fees_and_taxes_in_figures"] == held

    %{"data" => trades} = get_json(conn, "/api/v1/securities/#{s.wrenfield.id}/trades")
    traded = trades["computation_basis"]["fees_and_taxes_in_figures"]

    assert traded =~
             "An open lot's buy_price, buy_price_native, base_cost and unrealized_pnl_* are " <>
               "without the buy's fees and taxes."

    assert traded =~
             "Its buy_fees and buy_taxes are the whole buy's, for original_quantity, the " <>
               "quantity the lot opened with (split-adjusted); the share already in a closed " <>
               "trade's basis is in that trade's buy_fees and buy_taxes."

    refute traded =~ "which buy_fees and buy_taxes state beside them"

    assert traded =~
             "A closed trade's basis includes the buy fees and taxes of the lots it closes"

    assert traded =~ "proceeds are net of the sell's fees and taxes"
    assert traded =~ "realized_pnl_abs, proceeds - basis, is after all four"

    %{"data" => result} =
      get_json(
        conn,
        "/api/v1/portfolios/#{s.world.portfolio.id}/category-results" <>
          "?classification_id=#{s.classification.id}"
      )

    assert result["basis_note"] =~
             "Invested is the members' base_cost, without the buys' fees and taxes, " <>
               "so the result is before them"
  end
end
