defmodule PortfolixirWeb.ApiV1NegativeHoldingsTest do
  use PortfolixirWeb.ConnCase

  alias Portfolixir.Ledger
  alias Portfolixir.WorldFixtures

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  # User story (#570):
  # As an API client (and the LLM I connect over MCP),
  # I want the negative-holdings data-quality report over the API,
  # so that import debris from unmodeled corporate actions is visible to
  # automation the same way the Wealth page reports it.
  #
  # Acceptance criteria:
  # - GET /api/v1/holdings/negative lists every (depot, security) position
  #   with a negative derived quantity, with names, plus per-security totals
  #   across all depots.
  # - Quantities are Decimal strings; the response is self-describing
  #   (as_of read date and a note).
  # - Without debris the lists are empty.
  test "returns negative positions per depot with per-security totals", %{conn: conn} do
    world = WorldFixtures.base_world(depot_name: "Main Depot")

    doomed =
      WorldFixtures.create_security!(name: "Doomed Co.", ticker: "DOOM", asset_class: "equity")

    fine = WorldFixtures.create_security!(name: "Fine Co.", ticker: "FINE", asset_class: "equity")
    WorldFixtures.buy!(world, fine, quantity: "10", price: "5")

    {:ok, _} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        security_id: doomed.id,
        type: "outbound_delivery",
        date: ~D[2026-02-02],
        quantity: "500",
        currency_code: "EUR"
      })

    body =
      conn
      |> api_conn()
      |> get("/api/v1/holdings/negative")
      |> json_response(200)

    data = body["data"]
    assert data["as_of"] == Date.to_iso8601(Date.utc_today())
    assert data["note"] =~ "negative"

    assert [row] = data["rows"]
    assert row["security_id"] == doomed.id
    assert row["security_name"] == "Doomed Co."
    assert row["securities_account_id"] == world.depot.id
    assert row["depot_name"] == "Main Depot"
    assert row["portfolio_id"] == world.portfolio.id
    assert row["quantity"] == "-500"
    assert is_binary(row["quantity"])

    assert [total] = data["totals"]
    assert total["security_id"] == doomed.id
    assert total["total_quantity"] == "-500"
  end

  test "returns empty lists without negative holdings", %{conn: conn} do
    world = WorldFixtures.base_world()
    fine = WorldFixtures.create_security!(name: "Fine Co.", ticker: "FINE", asset_class: "equity")
    WorldFixtures.buy!(world, fine, quantity: "10", price: "5")

    body =
      conn
      |> api_conn()
      |> get("/api/v1/holdings/negative")
      |> json_response(200)

    assert body["data"]["rows"] == []
    assert body["data"]["totals"] == []
  end
end
