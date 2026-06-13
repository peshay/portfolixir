defmodule PortfolixirWeb.ApiV1TargetsTest do
  use PortfolixirWeb.ConnCase

  import Portfolixir.WorldFixtures,
    only: [base_world: 0, create_security!: 1, buy!: 3, put_quote!: 3]

  alias Portfolixir.Classifications

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
    world = base_world()

    {:ok, classification} = Classifications.create_classification(%{name: "Strategy"})

    {:ok, core} =
      Classifications.create_category(%{classification_id: classification.id, name: "Core"})

    security = create_security!(name: "Core Equity", ticker: "CORE", asset_class: "equity")
    {:ok, _} = Classifications.assign_security(security.id, classification.id, core.id)

    buy!(world, security, quantity: "10", price: "100")
    put_quote!(security, ~D[2026-06-01], "120")

    Map.merge(world, %{classification: classification, core: core})
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

  test "rejects a malformed targets list with 422 instead of crashing", %{conn: conn} do
    %{portfolio: portfolio, classification: classification} = setup_world()

    response =
      put_json(conn, "/api/v1/portfolios/#{portfolio.id}/targets", %{
        "classification_id" => classification.id,
        "targets" => [1]
      })

    assert %{"errors" => %{"targets" => [_ | _]}} = json_response(response, 422)
  end
end
