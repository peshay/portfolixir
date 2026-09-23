defmodule PortfolixirWeb.ApiV1RiskTest do
  use PortfolixirWeb.ConnCase

  import Portfolixir.WorldFixtures,
    only: [base_world: 0, create_security!: 1, buy!: 3, deposit!: 3]

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
  # quotes (so the API path needs no test-only price overrides).
  defp risk_world do
    world = base_world()

    stock_big = equity!("Stock Big", "BIG")
    stock_mid = equity!("Stock Mid", "MID")
    stock_small = equity!("Stock Small", "SML")
    big_etf = etf!("Big World ETF", "WRLD")

    deposit!(world, "2000", ~D[2026-01-01])

    buy!(world, stock_big, quantity: "6", price: "100")
    buy!(world, stock_mid, quantity: "9", price: "10")
    buy!(world, stock_small, quantity: "5", price: "10")
    buy!(world, big_etf, quantity: "26", price: "10")

    quote!(stock_big, "100")
    quote!(stock_mid, "10")
    quote!(stock_small, "10")
    quote!(big_etf, "10")

    Map.merge(world, %{
      stock_big: stock_big,
      stock_mid: stock_mid,
      stock_small: stock_small,
      big_etf: big_etf
    })
  end

  # User story:
  # As an API client (and the LLM I connect over MCP),
  # I want the portfolio's risk/concentration lens from one endpoint,
  # so that single-name and asset-class concentration are visible without
  # joining the valuation and the classifications by hand.
  #
  # Acceptance criteria:
  # - GET /portfolios/:id/risk returns the Top-N single names (weight Decimal
  #   string + severity), the HHI value/band and the steerable basis.
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

  test "hhi_bands override reclassifies the HHI band", %{conn: conn} do
    world = risk_world()

    body =
      conn
      |> api_conn()
      |> get(
        "/api/v1/portfolios/#{world.portfolio.id}/risk" <>
          "?hhi_bands[low]=5000&hhi_bands[high]=6000"
      )
      |> json_response(200)

    # HHI 4382 now falls below the raised low cutoff of 5000.
    assert body["data"]["hhi"]["value"] == "4382"
    assert body["data"]["hhi"]["band"] == "low"
  end

  test "stock_thresholds override reclassifies single-name severity", %{conn: conn} do
    world = risk_world()

    weights =
      conn
      |> api_conn()
      |> get(
        "/api/v1/portfolios/#{world.portfolio.id}/risk" <>
          "?stock_thresholds[warn]=50&stock_thresholds[hard]=70"
      )
      |> json_response(200)
      |> get_in(["data", "top_holdings"])
      |> Map.new(&{&1["security_id"], &1})

    # 60% now sits between the raised warn(50)/hard(70) cutoffs -> warn, not hard.
    assert weights[world.stock_big.id]["severity"] == "warn"
    assert weights[world.stock_mid.id]["severity"] == "ok"
  end

  test "etf_thresholds override reclassifies ETF severity", %{conn: conn} do
    world = risk_world()

    weights =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{world.portfolio.id}/risk?etf_thresholds[warn]=50")
      |> json_response(200)
      |> get_in(["data", "top_holdings"])
      |> Map.new(&{&1["security_id"], &1})

    # The 26% ETF drops below the raised warn cutoff of 50 -> ok.
    assert weights[world.big_etf.id]["severity"] == "ok"
  end

  test "rejects a malformed asset-class cap with 422", %{conn: conn} do
    world = risk_world()

    body =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{world.portfolio.id}/risk?asset_class_caps[equity]=abc")
      |> json_response(422)

    assert body["errors"]["asset_class_caps"] == ["is invalid"]
  end

  test "rejects a negative asset-class cap with 422", %{conn: conn} do
    world = risk_world()

    body =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{world.portfolio.id}/risk?asset_class_caps[equity]=-5")
      |> json_response(422)

    assert body["errors"]["asset_class_caps"] == ["is invalid"]
  end

  test "rejects a non-map asset_class_caps with 422", %{conn: conn} do
    world = risk_world()

    body =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{world.portfolio.id}/risk?asset_class_caps=5")
      |> json_response(422)

    assert body["errors"]["asset_class_caps"] == ["is invalid"]
  end

  test "rejects malformed hhi_bands with 422", %{conn: conn} do
    world = risk_world()

    body =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{world.portfolio.id}/risk?hhi_bands[low]=abc")
      |> json_response(422)

    assert body["errors"]["hhi_bands"] == ["is invalid"]
  end

  test "rejects a non-map hhi_bands with 422", %{conn: conn} do
    world = risk_world()

    body =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{world.portfolio.id}/risk?hhi_bands=5")
      |> json_response(422)

    assert body["errors"]["hhi_bands"] == ["is invalid"]
  end

  test "rejects malformed stock_thresholds with 422", %{conn: conn} do
    world = risk_world()

    body =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{world.portfolio.id}/risk?stock_thresholds[hard]=abc")
      |> json_response(422)

    assert body["errors"]["stock_thresholds"] == ["is invalid"]
  end

  test "rejects a non-map stock_thresholds with 422", %{conn: conn} do
    world = risk_world()

    body =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{world.portfolio.id}/risk?stock_thresholds=5")
      |> json_response(422)

    assert body["errors"]["stock_thresholds"] == ["is invalid"]
  end

  test "rejects malformed etf_thresholds with 422", %{conn: conn} do
    world = risk_world()

    body =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{world.portfolio.id}/risk?etf_thresholds[warn]=abc")
      |> json_response(422)

    assert body["errors"]["etf_thresholds"] == ["is invalid"]
  end

  test "rejects a non-map etf_thresholds with 422", %{conn: conn} do
    world = risk_world()

    body =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{world.portfolio.id}/risk?etf_thresholds=5")
      |> json_response(422)

    assert body["errors"]["etf_thresholds"] == ["is invalid"]
  end

  # User story (FR-40, ADR-0047 §3, §6 and §9):
  # As the operator's agent reading a portfolio's risk,
  # I want the portfolio's volatility, drawdown, risk-adjusted return and the
  # Top-N correlation matrix on the risk read I already poll,
  # so that I do not rebuild them from the daily valuation series myself.
  #
  # Acceptance criteria:
  # - The risk read carries `metrics`, additively: every metric per window with
  #   value (a Decimal string or null), window, observations, required and
  #   insufficient_data; the shared computation_basis sits once inside it.
  # - At the default risk_free_rate the basis's reference says the figure is
  #   return per unit of risk; the rate is echoed on each window.
  # - A risk_free_rate that is not a Decimal, or lies outside ADR-0046's rate
  #   bound, is a 422 naming the field.
  test "carries the portfolio metrics additively, with required on every metric", %{conn: conn} do
    world = risk_world()

    data =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{world.portfolio.id}/risk")
      |> json_response(200)
      |> Map.fetch!("data")

    # The lens is unchanged.
    assert data["hhi"]["band"]
    metrics = data["metrics"]

    for key <- ~w(volatility max_drawdown risk_adjusted_return),
        window <- ~w(30d 90d 365d) do
      metric = metrics[key][window]

      assert Map.has_key?(metric, "value")
      assert is_nil(metric["value"]) or is_binary(metric["value"])
      assert %{"start_date" => _, "end_date" => _} = metric["window"]
      assert is_integer(metric["observations"])
      assert is_integer(metric["required"])
      assert is_boolean(metric["insufficient_data"])
    end

    assert metrics["volatility"]["30d"]["required"] == 20
    assert metrics["max_drawdown"]["30d"]["required"] == 2
    assert metrics["risk_adjusted_return"]["90d"]["risk_free_rate"] == "0"
    assert metrics["computation_basis"]["reference"] =~ "return per unit of risk"
    assert metrics["computation_basis"]["input_series"] =~ "flow-adjusted"
    assert metrics["computation_basis"]["assumptions"] =~ "√365"

    correlations = metrics["correlations"]
    assert length(correlations["security_ids"]) == 4
    assert length(correlations["pairs"]) == 6
    assert correlations["excluded"] == []

    for pair <- correlations["pairs"] do
      assert pair["required"] == 60
      assert is_integer(pair["observations"])
    end
  end

  test "takes risk_free_rate as a Decimal string and refuses a malformed one", %{conn: conn} do
    world = risk_world()
    path = "/api/v1/portfolios/#{world.portfolio.id}/risk"

    metrics =
      conn
      |> api_conn()
      |> get(path, %{"risk_free_rate" => "0.02"})
      |> json_response(200)
      |> get_in(["data", "metrics"])

    assert metrics["risk_adjusted_return"]["30d"]["risk_free_rate"] == "0.02"
    assert metrics["computation_basis"]["reference"] =~ "0.02"

    for bad <- ["abc", "11", "-1", ""] do
      body = conn |> api_conn() |> get(path, %{"risk_free_rate" => bad}) |> json_response(422)
      assert body["errors"]["risk_free_rate"] == ["is invalid"], "#{inspect(bad)} was accepted"
    end
  end
end
