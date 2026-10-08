defmodule PortfolixirWeb.ApiV1CrossCurrencyTradesTest do
  # The ADR-0015 amendment of 2026-10-07, identity 1 (#1108, risk-tier money):
  # a cross-currency closed trade read over the API, through the security's
  # trades read and the realized-gains read, is in one currency — its fees
  # and taxes, recorded in the cash account's currency, converted at the
  # trade's own stored settlement_fx_rate — and the payloads say so.
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
end
