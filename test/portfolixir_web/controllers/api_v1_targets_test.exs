defmodule PortfolixirWeb.ApiV1TargetsTest do
  use PortfolixirWeb.ConnCase

  import Portfolixir.WorldFixtures,
    only: [base_world: 0, create_security!: 1, buy!: 3, put_quote!: 3, deposit!: 3]

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
  defp patch_json(conn, path, body), do: conn |> api_conn() |> patch(path, Jason.encode!(body))
  defp delete_json(conn, path), do: conn |> api_conn() |> delete(path)

  defp setup_world do
    world = base_world()

    {:ok, classification} = Classifications.create_classification(%{name: "Strategy"})

    {:ok, core} =
      Classifications.create_category(%{classification_id: classification.id, name: "Core"})

    security = create_security!(name: "Core Equity", ticker: "CORE", asset_class: "equity")
    {:ok, _} = Classifications.assign_security(security.id, classification.id, core.id)

    # Fund the cash account so the buy leaves it at zero: counting cash is 0, so
    # the allocation basis here is securities only (issue #335).
    deposit!(world, "1000", ~D[2026-01-01])
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

    # The allocation carries a cash row (here cash is 0) and the Σ top level.
    assert data["cash"]["market_value"] == "0"
    assert data["cash"]["actual_weight"] == "0"
    assert data["cash"]["target_weight"] == "0"
    assert data["top_level_target_sum"] == "0.8"

    # Core has no children carrying a target, so its advisory child_target_sum is
    # null (issue #378): the consumer can tell "no comparison offered" apart from
    # "the children sum to zero".
    assert category["child_target_sum"] == nil
  end

  # User story:
  # As an API client (and the LLM I connect over MCP),
  # I want each allocation row to carry the advisory sum of its direct children's
  # targets (child_target_sum) as a Decimal string,
  # so that I can flag target-tree inconsistency without recomputing it.
  #
  # Acceptance criteria:
  # - A parent row whose direct children carry targets exposes child_target_sum
  #   as a Decimal string (the sum of those children's targets).
  # - A row without child targets exposes child_target_sum as null.
  test "exposes the advisory child_target_sum per allocation row", %{conn: conn} do
    %{portfolio: portfolio, classification: classification, core: core} = setup_world()

    {:ok, tech} =
      Classifications.create_category(%{
        classification_id: classification.id,
        name: "Tech",
        parent_id: core.id
      })

    {:ok, emerging} =
      Classifications.create_category(%{
        classification_id: classification.id,
        name: "Emerging",
        parent_id: core.id
      })

    {:ok, _} =
      Portfolixir.Portfolios.Targets.set_targets(portfolio.id, classification.id, [
        %{"category_id" => core.id, "target_weight" => "0.6"},
        %{"category_id" => tech.id, "target_weight" => "0.3"},
        %{"category_id" => emerging.id, "target_weight" => "0.2"}
      ])

    data =
      get_json(
        conn,
        "/api/v1/portfolios/#{portfolio.id}/allocation?classification_id=#{classification.id}"
      )
      |> json_response(200)
      |> Map.fetch!("data")

    rows = Map.new(data["categories"], &{&1["category_id"], &1})

    # Core's direct children (Tech 0.3 + Emerging 0.2) sum to 0.5, rendered as a
    # Decimal string.
    core_row = rows[core.id]
    assert core_row["child_target_sum"] == "0.5"
    assert is_binary(core_row["child_target_sum"])

    # The leaf children have no targeted children of their own, so null.
    assert rows[tech.id]["child_target_sum"] == nil
    assert rows[emerging.id]["child_target_sum"] == nil
  end

  # User story:
  # As an API client (and the LLM I connect over MCP) steering a cash quote,
  # I want to set the portfolio's cash target and read the allocation cash row,
  # so that cash is part of the same SOLL/IST basis as the categories.
  #
  # Acceptance criteria:
  # - PATCH /portfolios/:id sets cash_target_weight; it is returned and feeds the
  #   allocation cash row and the Σ top level.
  # - The 100% basis is securities + counting cash, so a category percentage
  #   shrinks once cash is present.
  test "sets the cash target and reports it in the allocation cash row", %{conn: conn} do
    world = setup_world()
    %{portfolio: portfolio, classification: classification} = world

    # Add 120 EUR of counting cash on top of the (funded) 1200 EUR of securities:
    # basis becomes 1320; the core category is 1200/1320 and cash is 120/1320.
    deposit!(world, "120", ~D[2026-06-02])

    patched =
      patch_json(conn, "/api/v1/portfolios/#{portfolio.id}", %{
        "portfolio" => %{"cash_target_weight" => "0.05"}
      })

    assert %{"data" => updated} = json_response(patched, 200)
    assert updated["cash_target_weight"] == "0.05"

    data =
      get_json(
        conn,
        "/api/v1/portfolios/#{portfolio.id}/allocation?classification_id=#{classification.id}"
      )
      |> json_response(200)
      |> Map.fetch!("data")

    assert data["total_value"] == "1320"
    assert data["cash"]["market_value"] == "120"
    assert data["cash"]["target_weight"] == "0.05"
    assert data["top_level_target_sum"] == "0.05"

    [category] = data["categories"]
    # Shrunk from 1 (securities-only) to 1200/1320 once cash joins the basis.
    refute category["actual_weight"] == "1"
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
