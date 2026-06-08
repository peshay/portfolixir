defmodule PortfolixirWeb.ApiV1TargetsTest do
  use PortfolixirWeb.ConnCase

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Classifications
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  @auth {"authorization", "Bearer test-api-token"}

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header(elem(@auth, 0), elem(@auth, 1))
  end

  defp get_json(conn, path), do: conn |> api_conn() |> get(path)
  defp put_json(conn, path, body), do: conn |> api_conn() |> put(path, Jason.encode!(body))
  defp delete_json(conn, path), do: conn |> api_conn() |> delete(path)

  defp setup_world do
    {:ok, portfolio} =
      Portfolios.create_portfolio(%{name: "Local Portfolio", base_currency_code: "EUR"})

    {:ok, cash} =
      Portfolios.create_cash_account(%{
        portfolio_id: portfolio.id,
        name: "Local Cash",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Main Depot"
      })

    {:ok, classification} = Classifications.create_classification(%{name: "Strategy"})

    {:ok, core} =
      Classifications.create_category(%{classification_id: classification.id, name: "Core"})

    {:ok, security} =
      Catalog.create_security(%{
        name: "Core Equity",
        ticker_symbol: "CORE",
        currency_code: "EUR",
        asset_class: "equity"
      })

    {:ok, _} = Classifications.assign_security(security.id, classification.id, core.id)

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: depot.id,
        cash_account_id: cash.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-01-02],
        quantity: "10",
        price: "100",
        fees: "0",
        taxes: "0",
        currency_code: "EUR"
      })

    {:ok, _} =
      Quotes.upsert_many(security.id, [%{date: ~D[2026-06-01], close: "120", source: "manual"}])

    %{portfolio: portfolio, classification: classification, core: core}
  end

  # User story:
  # As an API client (and the LLM I connect over MCP),
  # I want to store target weights and read a SOLL/IST allocation breakdown,
  # so that my weekly drift check runs entirely against the Portfolixir API.
  #
  # Acceptance criteria:
  # - PUT targets stores weights and GET targets returns them.
  # - GET allocation reports market value, actual/target weight and drift per
  #   category, against the stored quote-based valuation.
  # - GET allocation without classification_id returns 422.
  # - An out-of-range weight returns 422; DELETE removes a target.
  test "stores targets and reports allocation drift through the API", %{conn: conn} do
    %{portfolio: portfolio, classification: classification, core: core} = setup_world()

    assert get_json(conn, "/api/v1/portfolios/#{portfolio.id}/targets")
           |> json_response(200) == %{"data" => %{"targets" => []}}

    set =
      put_json(conn, "/api/v1/portfolios/#{portfolio.id}/targets", %{
        "classification_id" => classification.id,
        "targets" => [%{"category_id" => core.id, "target_weight" => "0.8"}]
      })

    assert %{"data" => %{"targets" => [target]}} = json_response(set, 200)
    assert target["category_id"] == core.id
    assert target["target_weight"] == "0.8"

    allocation =
      get_json(
        conn,
        "/api/v1/portfolios/#{portfolio.id}/allocation?classification_id=#{classification.id}"
      )

    assert %{"data" => data} = json_response(allocation, 200)
    assert data["total_value"] == "1200"

    assert [category] = data["categories"]
    assert category["category_id"] == core.id
    assert category["market_value"] == "1200"
    assert category["actual_weight"] == "1"
    assert category["target_weight"] == "0.8"
    assert category["drift_weight"] == "-0.2"
    assert category["drift_value"] == "-240"
  end

  test "requires classification_id for the allocation endpoint", %{conn: conn} do
    %{portfolio: portfolio} = setup_world()

    response =
      get_json(conn, "/api/v1/portfolios/#{portfolio.id}/allocation") |> json_response(422)

    assert response == %{"errors" => %{"classification_id" => ["is required"]}}
  end

  test "rejects an out-of-range target weight and deletes targets", %{conn: conn} do
    %{portfolio: portfolio, classification: classification, core: core} = setup_world()

    rejected =
      put_json(conn, "/api/v1/portfolios/#{portfolio.id}/targets", %{
        "classification_id" => classification.id,
        "targets" => [%{"category_id" => core.id, "target_weight" => "1.5"}]
      })

    assert %{"errors" => %{"target_weight" => [_ | _]}} = json_response(rejected, 422)

    stored =
      put_json(conn, "/api/v1/portfolios/#{portfolio.id}/targets", %{
        "classification_id" => classification.id,
        "targets" => [%{"category_id" => core.id, "target_weight" => "0.5"}]
      })

    assert %{"data" => %{"targets" => [_]}} = json_response(stored, 200)

    deleted =
      delete_json(conn, "/api/v1/portfolios/#{portfolio.id}/targets/#{core.id}")
      |> json_response(200)

    assert deleted == %{"data" => %{"deleted" => 1}}
  end
end
