defmodule PortfolixirWeb.ApiV1HoldingsBySecurityTest do
  use PortfolixirWeb.ConnCase

  alias Portfolixir.Ledger
  alias Portfolixir.WorldFixtures

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  # User story:
  # As an API client (and the LLM I connect over MCP),
  # I want each held security's global quantity and EUR-hub market value from
  # one endpoint,
  # so that the cross-portfolio per-security valuation is reachable without a
  # LiveView.
  #
  # Acceptance criteria:
  # - GET /api/v1/holdings/by_security returns one row per held security with
  #   security_id, quantity, market_value and the valued flag.
  # - Financial values are Decimal strings; the security_id stays an integer.
  # - The response is self-describing: currency "EUR", a read-date as_of and a
  #   hub-conversion note.
  # - A security with neither quote nor trade price is returned valued: false
  #   with a null market value.
  test "returns the global per-security EUR valuation with Decimal strings", %{conn: conn} do
    world = WorldFixtures.base_world(currency: "EUR")

    held =
      WorldFixtures.create_security!(name: "Apple Inc.", ticker: "AAPL", asset_class: "equity")

    unvalued =
      WorldFixtures.create_security!(name: "Delivered Co.", ticker: "DLVR", asset_class: "equity")

    WorldFixtures.deposit!(world, "10000", ~D[2026-01-01])
    WorldFixtures.buy!(world, held, quantity: "10", price: "80")

    {:ok, _} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        security_id: unvalued.id,
        type: "inbound_delivery",
        date: ~D[2026-01-02],
        quantity: "7",
        currency_code: "EUR"
      })

    WorldFixtures.put_quote!(held, ~D[2026-06-01], "100")

    body =
      conn
      |> api_conn()
      |> get("/api/v1/holdings/by_security")
      |> json_response(200)

    data = body["data"]

    assert data["currency"] == "EUR"
    assert data["as_of"] == Date.to_iso8601(Date.utc_today())
    assert data["note"] =~ "EUR"

    held_row = Enum.find(data["holdings"], &(&1["security_id"] == held.id))
    assert held_row["security_id"] == held.id
    assert held_row["quantity"] == "10"
    assert held_row["market_value"] == "1000"
    assert held_row["valued"] == true

    unvalued_row = Enum.find(data["holdings"], &(&1["security_id"] == unvalued.id))
    assert unvalued_row["quantity"] == "7"
    assert unvalued_row["market_value"] == nil
    assert unvalued_row["valued"] == false
  end
end
