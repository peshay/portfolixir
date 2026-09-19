defmodule PortfolixirWeb.Api.V1.SecurityMetricsControllerTest do
  use PortfolixirWeb.ConnCase, async: true

  import Portfolixir.WorldFixtures, only: [create_security!: 1]

  alias Portfolixir.Catalog.Quotes

  @as_of ~D[2026-09-19]

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    %{conn: conn}
  end

  defp seed_series!(security_id, closes, last \\ @as_of) do
    first = Date.add(last, -(length(closes) - 1))

    rows =
      closes
      |> Enum.with_index()
      |> Enum.map(fn {close, index} ->
        %{date: Date.add(first, index), close: Decimal.new(close), source: "manual"}
      end)

    {:ok, _count} = Quotes.upsert_many(security_id, rows)
    :ok
  end

  # User story (FR-39, ADR-0047 §9):
  # As the operator's agent,
  # I want one security's derived metrics over the JSON API,
  # so that a research run reads them instead of recomputing them from the
  # quote history.
  #
  # Acceptance criteria:
  # - The read answers 200 with every §3 metric, each carrying its window and
  #   observation count, and the payload-level computation basis.
  # - Every financial decimal is serialized as a string (AGENTS.md).
  test "answers one security's metrics with their basis, decimals as strings", %{conn: conn} do
    security = create_security!(name: "API Metric Co", ticker: "AMC", currency: "USD")
    seed_series!(security.id, List.duplicate("100", 400))

    %{"data" => data} =
      conn
      |> get("/api/v1/securities/#{security.id}/metrics", %{"as_of" => "2026-09-19"})
      |> json_response(200)

    assert data["security_id"] == security.id
    assert data["currency_code"] == "USD"
    assert data["as_of"] == "2026-09-19"
    assert data["latest_close"] == %{"date" => "2026-09-19", "close" => "100"}

    assert data["computation_basis"]["input_series"] =~ "USD"
    assert data["computation_basis"]["reference"] == nil
    assert data["computation_basis"]["assumptions"] =~ "252"

    metrics = data["metrics"]
    assert metrics["sma_50"]["value"] == "100"
    assert metrics["sma_50"]["distance_pct"] == "0"
    assert metrics["sma_50"]["observations"] == 50
    assert metrics["sma_50"]["insufficient_data"] == false

    assert metrics["sma_50"]["window"] == %{
             "start_date" => "2026-08-01",
             "end_date" => "2026-09-19"
           }

    assert metrics["volatility"]["30d"]["value"] == "0"
    assert metrics["max_drawdown"]["365d"]["value"] == "0"
    assert metrics["max_drawdown"]["365d"]["peak_date"]
    assert metrics["momentum"]["12m"]["observations"] == 2
    assert metrics["distance_to_extremes"]["high"]["close"] == "100"
  end

  # Acceptance criteria (ADR-0047 §5, identity I5):
  # - A window below its minimum answers null with insufficient_data and the
  #   observation count, at HTTP 200 — never a number, never a 500.
  test "a thin series answers a gap marker at 200, not a number and not a 500", %{conn: conn} do
    security = create_security!(name: "Thin Co", ticker: "THN")
    seed_series!(security.id, List.duplicate("100", 5))

    %{"data" => data} =
      conn
      |> get("/api/v1/securities/#{security.id}/metrics", %{"as_of" => "2026-09-19"})
      |> json_response(200)

    volatility = data["metrics"]["volatility"]["30d"]
    assert volatility["value"] == nil
    assert volatility["insufficient_data"] == true
    assert volatility["observations"] == 4
  end

  # Acceptance criteria:
  # - An unknown security is 404; a malformed as_of is 422 naming the field.
  test "refuses an unknown security and a malformed as_of", %{conn: conn} do
    security = create_security!(name: "Refuse Co", ticker: "RFC")

    assert %{"errors" => _} =
             conn |> get("/api/v1/securities/999999/metrics") |> json_response(404)

    assert %{"errors" => %{"as_of" => [_ | _]}} =
             conn
             |> get("/api/v1/securities/#{security.id}/metrics", %{"as_of" => "yesterday"})
             |> json_response(422)
  end

  # Acceptance criteria (AR-11, the API/MCP auth rule):
  # - The read is behind the local bearer token like every other API read.
  test "requires the bearer token", %{conn: conn} do
    security = create_security!(name: "Auth Co", ticker: "ATH")

    conn
    |> delete_req_header("authorization")
    |> get("/api/v1/securities/#{security.id}/metrics")
    |> json_response(401)
  end
end
