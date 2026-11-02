defmodule PortfolixirWeb.ApiV1OpenLotsTradePriceTest do
  # #1369 (Sprint 23 R4, plan D-4; ADR-0010's amendment of 2026-06-10): the
  # open lots of GET /api/v1/securities/:security_id/trades are priced by the
  # rule the holdings read and the valuation use, the latest quote, else the
  # last own trade price, and name it per lot; the payload's computation
  # basis states the rule (the AGENTS.md metric rule). The MCP tool
  # portfolixir.trades.list passes the body through.
  #
  # The data is invented, board ux-design-2026-11-02-sprint23/02-money ①b:
  # "Helios Example SE", no quote, 15 @ 18.00 and 5 @ 19.20.
  use PortfolixirWeb.ConnCase

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quote!: 3]

  alias Portfolixir.Ledger

  defp get_json(conn, path) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
    |> get(path)
    |> json_response(200)
  end

  # User story (#1369, the payload half):
  # As the operating LLM agent reading a security's open lots,
  # I want each lot to name the price it is valued at and where it comes
  # from, by the holdings read's rule,
  # so that a lot of a security without a quote states the figure the
  # holdings and Wealth state, never null beside a holding that has one.
  #
  # Acceptance criteria:
  # - Helios' lots read latest_price "19.20", price_source "trade",
  #   price_date "2025-03-14", unrealized_pnl_abs "18.00" and "0.00".
  # - A quoted security's lot reads price_source "quote" with the quote's
  #   date.
  # - computation_basis.latest_price is the holdings read's sentence.
  test "open lots name the price they are valued at and its source", %{conn: conn} do
    world = base_world(name: "Helios API", cash_name: "Girokonto", depot_name: "Depot 1")
    deposit!(world, "5000", ~D[2025-01-02])
    helios = create_security!(name: "Helios Example SE", ticker: "HLX")
    buy!(world, helios, quantity: "15", price: "18.00", date: ~D[2025-02-12])
    buy!(world, helios, quantity: "5", price: "19.20", date: ~D[2025-03-14])

    quoted = create_security!(name: "Quoted Example AG", ticker: "QEX")
    buy!(world, quoted, quantity: "10", price: "100.00", date: ~D[2025-01-05])
    put_quote!(quoted, ~D[2025-06-30], "130.00")

    %{"data" => data} = get_json(conn, "/api/v1/securities/#{helios.id}/trades")

    assert data["computation_basis"]["latest_price"] == Ledger.holding_price_basis()

    assert [first, second] = data["open_lots"]

    for lot <- [first, second] do
      assert Decimal.equal?(Decimal.new(lot["latest_price"]), Decimal.new("19.20"))
      assert lot["price_source"] == "trade"
      assert lot["price_date"] == "2025-03-14"
    end

    assert Decimal.equal?(Decimal.new(first["unrealized_pnl_abs"]), Decimal.new("18.00"))
    assert Decimal.equal?(Decimal.new(second["unrealized_pnl_abs"]), Decimal.new("0.00"))

    %{"data" => %{"open_lots" => [lot]}} =
      get_json(conn, "/api/v1/securities/#{quoted.id}/trades")

    assert lot["price_source"] == "quote"
    assert lot["price_date"] == "2025-06-30"
  end
end
