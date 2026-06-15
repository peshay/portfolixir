defmodule PortfolixirWeb.ApiV1RiskTest do
  use PortfolixirWeb.ConnCase

  import Portfolixir.WorldFixtures,
    only: [base_world: 0, create_security!: 1, buy!: 3, deposit!: 3]

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  defp equity!(name, ticker),
    do: create_security!(name: name, ticker: ticker, asset_class: "equity")

  defp etf!(name, ticker),
    do: create_security!(name: name, ticker: ticker, asset_class: "etf")

  defp quote!(security, close) do
    {:ok, _} =
      Quotes.upsert_many(security.id, [%{date: ~D[2026-01-03], close: close, source: "manual"}])
  end

  # Builds a world whose steerable basis is exactly 1000 EUR, priced from stored
  # quotes (so the API path needs no test-only price overrides), plus an excluded
  # crypto of 500 that must stay out of the basis.
  defp risk_world do
    world = base_world()

    stock_big = equity!("Stock Big", "BIG")
    stock_mid = equity!("Stock Mid", "MID")
    stock_small = equity!("Stock Small", "SML")
    big_etf = etf!("Big World ETF", "WRLD")

    {:ok, crypto} =
      Catalog.create_security(%{
        name: "Store Of Value",
        currency_code: "EUR",
        asset_class: "crypto",
        excluded_from_allocation_targets: true
      })

    deposit!(world, "2000", ~D[2026-01-01])

    buy!(world, stock_big, quantity: "6", price: "100")
    buy!(world, stock_mid, quantity: "9", price: "10")
    buy!(world, stock_small, quantity: "5", price: "10")
    buy!(world, big_etf, quantity: "26", price: "10")
    buy!(world, crypto, quantity: "5", price: "100")

    quote!(stock_big, "100")
    quote!(stock_mid, "10")
    quote!(stock_small, "10")
    quote!(big_etf, "10")
    quote!(crypto, "100")

    Map.merge(world, %{
      stock_big: stock_big,
      stock_mid: stock_mid,
      stock_small: stock_small,
      big_etf: big_etf,
      crypto: crypto
    })
  end

  # User story:
  # As an API client (and the LLM I connect over MCP),
  # I want the portfolio's risk/concentration lens from one endpoint,
  # so that single-name and asset-class concentration are visible without
  # joining the valuation, the exclusion flag and the classifications by hand.
  #
  # Acceptance criteria:
  # - GET /portfolios/:id/risk returns the Top-N single names (weight Decimal
  #   string + severity), the HHI value/band and the steerable basis.
  # - Positions flagged excluded_from_allocation_targets stay out of the basis.
  # - Asset-class caps are opt-in via a request param; only classes over cap come
  #   back, with the overage in percentage points.
  # - top_n overrides the default of 10. An unknown portfolio returns 404.
  test "returns the risk lens with Decimal strings and severities", %{conn: conn} do
    world = risk_world()

    body =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{world.portfolio.id}/risk")
      |> json_response(200)

    data = body["data"]

    assert data["portfolio_id"] == world.portfolio.id
    assert data["base_currency"] == "EUR"
    assert data["steerable_basis"] == "1000"

    weights = Map.new(data["top_holdings"], &{&1["security_id"], &1})

    assert Enum.map(data["top_holdings"], & &1["security_id"]) == [
             world.stock_big.id,
             world.big_etf.id,
             world.stock_mid.id,
             world.stock_small.id
           ]

    assert weights[world.stock_big.id]["weight"] == "60"
    assert weights[world.stock_big.id]["severity"] == "hard"
    assert weights[world.stock_mid.id]["severity"] == "warn"
    assert weights[world.stock_small.id]["severity"] == "ok"
    assert weights[world.big_etf.id]["weight"] == "26"
    assert weights[world.big_etf.id]["severity"] == "warn"

    # The excluded crypto never surfaces as a single-name exposure.
    refute Map.has_key?(weights, world.crypto.id)

    assert data["hhi"]["value"] == "4382"
    assert data["hhi"]["band"] == "concentrated"

    # Caps are opt-in: none requested -> no violations.
    assert data["asset_class_violations"] == []
  end

  test "returns asset-class cap violations when caps are requested", %{conn: conn} do
    world = risk_world()

    body =
      conn
      |> api_conn()
      |> get(
        "/api/v1/portfolios/#{world.portfolio.id}/risk" <>
          "?asset_class_caps[equity]=50&asset_class_caps[etf]=30"
      )
      |> json_response(200)

    # Equity = 74% > 50% cap; ETF = 26% <= 30% so it is omitted.
    assert [violation] = body["data"]["asset_class_violations"]
    assert violation["asset_class"] == "equity"
    assert violation["current_weight"] == "74"
    assert violation["cap"] == "50"
    assert violation["overage"] == "24"
  end

  test "top_n overrides the default Top-N length", %{conn: conn} do
    world = risk_world()

    body =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{world.portfolio.id}/risk?top_n=2")
      |> json_response(200)

    assert Enum.map(body["data"]["top_holdings"], & &1["security_id"]) == [
             world.stock_big.id,
             world.big_etf.id
           ]
  end

  test "rejects an invalid top_n with 422", %{conn: conn} do
    world = risk_world()

    body =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{world.portfolio.id}/risk?top_n=0")
      |> json_response(422)

    assert body["errors"]["top_n"] == ["is invalid"]
  end

  test "returns 404 for an unknown portfolio", %{conn: conn} do
    body =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/999999/risk")
      |> json_response(404)

    assert body["errors"]["detail"] == "not found"
  end
end
