defmodule PortfolixirWeb.ApiV1PlansAndSnapshotsTest do
  use PortfolixirWeb.ConnCase

  import Portfolixir.WorldFixtures,
    only: [base_world: 0, create_security!: 1, buy!: 3, put_quote!: 3, deposit!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.Portfolios.Snapshots
  alias Portfolixir.Portfolios.Targets

  @auth {"authorization", "Bearer test-api-token"}

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header(elem(@auth, 0), elem(@auth, 1))
  end

  defp get_json(conn, path), do: conn |> api_conn() |> get(path)
  defp post_json(conn, path, body), do: conn |> api_conn() |> post(path, Jason.encode!(body))
  defp patch_json(conn, path, body), do: conn |> api_conn() |> patch(path, Jason.encode!(body))
  defp delete_json(conn, path), do: conn |> api_conn() |> delete(path)

  # User story (Andi, 2026-07-16, ADR-0027):
  # As an agent operating Portfolixir over the JSON API,
  # I want plan versions (list/duplicate/activate/rename) and depot snapshots
  # (list/create/delete/compare) at parity with the UI,
  # so that the restructuring workflow is fully automatable (FR-13/14, AR-11).
  #
  # Acceptance criteria:
  # - GET /api/v1/portfolios/:id/plans lists versions with name and status.
  # - POST /api/v1/plans/:id/duplicate creates a draft copy;
  #   POST /api/v1/plans/:id/activate swaps it in (previous active archived);
  #   PATCH /api/v1/plans/:id renames.
  # - /api/v1/snapshots supports GET/POST/DELETE; the comparison endpoint is
  #   self-describing (basis, base currency) with decimals as strings.

  defp plan_world do
    world = base_world()

    {:ok, classification} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

    {:ok, category} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Equity"
      })

    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), world.portfolio.id, classification.id, [
        %{category_id: category.id, target_weight: Decimal.new("0.8")}
      ])

    Map.merge(world, %{classification: classification, category: category})
  end

  test "lists, duplicates, renames and activates plan versions", %{conn: conn} do
    %{portfolio: portfolio, classification: classification} = plan_world()

    response =
      conn
      |> get_json("/api/v1/portfolios/#{portfolio.id}/plans")
      |> json_response(200)

    assert [%{"status" => "active", "id" => active_id, "name" => "Plan"}] =
             response["data"]["plans"]

    duplicated =
      conn
      |> post_json("/api/v1/plans/#{active_id}/duplicate", %{name: "Plan 2027"})
      |> json_response(201)

    assert %{"status" => "draft", "name" => "Plan 2027", "id" => draft_id} =
             duplicated["data"]

    renamed =
      conn
      |> patch_json("/api/v1/plans/#{draft_id}", %{name: "Plan 2028"})
      |> json_response(200)

    assert renamed["data"]["name"] == "Plan 2028"

    activated =
      conn
      |> post_json("/api/v1/plans/#{draft_id}/activate", %{})
      |> json_response(200)

    assert activated["data"]["status"] == "active"

    statuses =
      Targets.list_plans(portfolio.id, classification_id: classification.id)
      |> Map.new(&{&1.id, &1.status})

    assert statuses[draft_id] == "active"
    assert statuses[active_id] == "archived"
  end

  test "unknown plan returns 404", %{conn: conn} do
    plan_world()
    assert conn |> post_json("/api/v1/plans/999999/activate", %{}) |> json_response(404)
  end

  test "creates, lists, compares and deletes snapshots", %{conn: conn} do
    world = base_world()
    security = create_security!(name: "EUR Stock", ticker: "EURS", currency: "EUR")
    deposit!(world, "10000", ~D[2026-01-02])
    buy!(world, security, quantity: "5", price: "100", date: ~D[2026-01-05])
    put_quote!(security, ~D[2026-02-14], "110")
    put_quote!(security, ~D[2026-03-10], "120")

    created =
      conn
      |> post_json("/api/v1/snapshots", %{name: "Before restructuring", as_of: "2026-02-15"})
      |> json_response(201)

    assert %{"id" => id, "name" => "Before restructuring", "as_of" => "2026-02-15"} =
             created["data"]

    listed = conn |> get_json("/api/v1/snapshots") |> json_response(200)
    assert [%{"id" => ^id}] = listed["data"]["snapshots"]

    comparison =
      conn
      |> get_json("/api/v1/portfolios/#{world.portfolio.id}/snapshots/#{id}/comparison")
      |> json_response(200)

    data = comparison["data"]
    assert data["as_of_value"] == "550"
    assert data["current_value"] == "600"
    assert data["base_currency"] == "EUR"
    assert data["basis"]["gross"] == true
    assert data["basis"]["price_return_only"] == true
    assert is_list(data["series"])
    assert is_binary(hd(data["series"])["snapshot_value"])

    # ADR-0027 amendment (#708): the cost decomposition travels with the
    # comparison, and the pre-cost figure is never served without the other
    # two. Decimal strings like everything else (AR-11).
    assert is_binary(data["transaction_costs"])
    assert Map.has_key?(data, "real_ttwror_before_costs")

    assert data["cost_recovery"]["state"] in ~w(recovered partly_recovered not_recovered not_comparable)

    # §5: the basis names the window and both sides of the cost boundary, so a
    # reader never has to infer which charges left the return.
    assert data["basis"]["window"] == %{
             "from" => "2026-02-15",
             "to" => Date.to_iso8601(Date.utc_today())
           }

    assert data["basis"]["costs_removed"] == ["trade_fees", "trade_taxes"]
    assert "dividend_withholding" in data["basis"]["costs_kept"]

    assert conn |> delete_json("/api/v1/snapshots/#{id}") |> json_response(200)
    assert Snapshots.list_snapshots() == []
  end

  test "rejects an invalid snapshot payload with 422", %{conn: conn} do
    base_world()

    response =
      conn
      |> post_json("/api/v1/snapshots", %{name: "", as_of: "2099-01-01"})
      |> json_response(422)

    assert response["errors"]
  end

  test "plan endpoints reject garbage and unknown ids consistently", %{conn: conn} do
    %{portfolio: portfolio} = plan_world()

    # index: garbage/unknown portfolio -> 404; classification filter narrows.
    assert conn |> get_json("/api/v1/portfolios/abc/plans") |> json_response(404)
    assert conn |> get_json("/api/v1/portfolios/999999/plans") |> json_response(404)

    filtered =
      conn
      |> get_json("/api/v1/portfolios/#{portfolio.id}/plans?classification_id=999999")
      |> json_response(200)

    assert filtered["data"]["plans"] == []

    # duplicate/activate/rename/delete: garbage and unknown ids -> 404.
    for path <- ["duplicate", "activate"] do
      assert conn |> post_json("/api/v1/plans/abc/#{path}", %{}) |> json_response(404)
      assert conn |> post_json("/api/v1/plans/999999/#{path}", %{}) |> json_response(404)
    end

    assert conn |> patch_json("/api/v1/plans/999999", %{name: "X"}) |> json_response(404)
    assert conn |> delete_json("/api/v1/plans/999999") |> json_response(404)
  end

  test "plan rename validates the name; duplicate validates the copy", %{conn: conn} do
    %{portfolio: portfolio, classification: classification} = plan_world()
    [plan] = Targets.list_plans(portfolio.id, classification_id: classification.id)

    missing = conn |> patch_json("/api/v1/plans/#{plan.id}", %{}) |> json_response(422)
    assert missing["errors"]["name"]

    too_long =
      conn
      |> post_json("/api/v1/plans/#{plan.id}/duplicate", %{name: String.duplicate("x", 121)})
      |> json_response(422)

    assert too_long["errors"]["name"]
  end

  test "deletes a plan version over the API", %{conn: conn} do
    %{portfolio: portfolio, classification: classification} = plan_world()
    [plan] = Targets.list_plans(portfolio.id, classification_id: classification.id)

    {:ok, draft} = Targets.duplicate_plan(Actor.owner_ui(), plan.id, %{name: "Doomed"})

    deleted = conn |> delete_json("/api/v1/plans/#{draft.id}") |> json_response(200)
    assert deleted["data"]["id"] == draft.id
    assert [%{id: kept}] = Targets.list_plans(portfolio.id, classification_id: classification.id)
    assert kept == plan.id
  end

  test "snapshot endpoints reject garbage and unknown ids; gaps serialize", %{conn: conn} do
    world = base_world()
    security = create_security!(name: "EUR Stock", ticker: "EURS", currency: "EUR")
    ghost = create_security!(name: "Unquoted", ticker: "GHST", currency: "EUR")
    deposit!(world, "10000", ~D[2026-01-02])
    buy!(world, security, quantity: "5", price: "100", date: ~D[2026-01-05])
    buy!(world, ghost, quantity: "3", price: "10", date: ~D[2026-01-20])
    put_quote!(security, ~D[2026-02-14], "110")

    assert conn |> delete_json("/api/v1/snapshots/abc") |> json_response(404)
    assert conn |> delete_json("/api/v1/snapshots/999999") |> json_response(404)

    created =
      conn
      |> post_json("/api/v1/snapshots", %{name: "Marker", as_of: "2026-02-15"})
      |> json_response(201)

    id = created["data"]["id"]

    assert conn
           |> get_json("/api/v1/portfolios/abc/snapshots/#{id}/comparison")
           |> json_response(404)

    assert conn
           |> get_json("/api/v1/portfolios/999999/snapshots/#{id}/comparison")
           |> json_response(404)

    assert conn
           |> get_json("/api/v1/portfolios/#{world.portfolio.id}/snapshots/999999/comparison")
           |> json_response(404)

    comparison =
      conn
      |> get_json("/api/v1/portfolios/#{world.portfolio.id}/snapshots/#{id}/comparison")
      |> json_response(200)

    # The excluded security is listed under gaps with its reason (AR-4).
    assert [gap] = comparison["data"]["gaps"]["unvalued_securities"]
    assert gap["security_name"] == "Unquoted"
    assert gap["reason"] == "no_quote_at_as_of"
  end
end
