defmodule PortfolixirWeb.ApiV1BucketsTest do
  use PortfolixirWeb.ConnCase

  import Portfolixir.WorldFixtures,
    only: [base_world: 0, create_security!: 1, buy!: 3, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets

  @auth {"authorization", "Bearer test-api-token"}

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header(elem(@auth, 0), elem(@auth, 1))
  end

  defp get_json(conn, path), do: conn |> api_conn() |> get(path)
  defp post_json(conn, path, body), do: conn |> api_conn() |> post(path, Jason.encode!(body))
  defp put_json(conn, path, body), do: conn |> api_conn() |> put(path, Jason.encode!(body))
  defp patch_json(conn, path, body), do: conn |> api_conn() |> patch(path, Jason.encode!(body))
  defp delete_json(conn, path), do: conn |> api_conn() |> delete(path)

  # User story:
  # As an API client (and the LLM I connect over MCP),
  # I want to manage buckets through the JSON API,
  # so that I can build the tag-based wealth-scoping model without the web UI.
  #
  # Acceptance criteria:
  # - POST creates a bucket; GET lists/show it; PATCH renames it; DELETE removes it.
  # - A blank name returns 422; an unknown id returns 404.
  # - Every bucket-definition write is journaled (actor-first, ADR-0017).
  test "manages buckets through the API", %{conn: conn} do
    created =
      post_json(conn, "/api/v1/buckets", %{"bucket" => %{"name" => "Retirement"}})
      |> json_response(201)

    assert %{"data" => bucket} = created
    assert bucket["name"] == "Retirement"
    id = bucket["id"]

    assert get_json(conn, "/api/v1/buckets") |> json_response(200) ==
             %{
               "data" => [
                 %{
                   "id" => id,
                   "name" => "Retirement",
                   "color" => nil,
                   "inserted_at" => bucket["inserted_at"],
                   "updated_at" => bucket["updated_at"]
                 }
               ]
             }

    assert get_json(conn, "/api/v1/buckets/#{id}") |> json_response(200) == %{"data" => bucket}

    patched =
      patch_json(conn, "/api/v1/buckets/#{id}", %{"bucket" => %{"name" => "Pension"}})
      |> json_response(200)

    assert patched["data"]["name"] == "Pension"

    assert delete_json(conn, "/api/v1/buckets/#{id}") |> response(204) == ""
    assert get_json(conn, "/api/v1/buckets/#{id}") |> json_response(404)

    # The bucket-definition writes are journaled.
    ops =
      Portfolixir.Journal.list_entries(resource_type: "bucket", resource_id: to_string(id))
      |> Enum.map(& &1.operation)
      |> Enum.sort()

    assert ops == [:create, :delete, :update]
  end

  test "rejects a blank bucket name with 422 and unknown ids with 404", %{conn: conn} do
    assert %{"errors" => %{"name" => [_ | _]}} =
             post_json(conn, "/api/v1/buckets", %{"bucket" => %{"name" => ""}})
             |> json_response(422)

    assert get_json(conn, "/api/v1/buckets/999999") |> json_response(404)
    assert patch_json(conn, "/api/v1/buckets/999999", %{"bucket" => %{}}) |> json_response(404)
    assert delete_json(conn, "/api/v1/buckets/999999") |> json_response(404)
  end

  # User story:
  # As an API client,
  # I want to manage views and their include/exclude bucket sets,
  # so that I can define reusable scopes over my buckets.
  #
  # Acceptance criteria:
  # - POST creates a view (include_all defaults to true); PATCH/DELETE work.
  # - PUT /views/:id/buckets sets the include/exclude bucket sets.
  # - A malformed bucket id list returns 422; an unknown view returns 404.
  test "manages views and their bucket sets through the API", %{conn: conn} do
    {:ok, included} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Liquid"})
    {:ok, excluded} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Illiquid"})

    created =
      post_json(conn, "/api/v1/views", %{"view" => %{"name" => "Liquid only"}})
      |> json_response(201)

    view = created["data"]
    assert view["include_all"] == true
    assert view["include"] == "all"
    assert view["exclude"] == []
    vid = view["id"]

    set =
      put_json(conn, "/api/v1/views/#{vid}/buckets", %{
        "include" => [included.id],
        "exclude" => [excluded.id]
      })
      |> json_response(200)

    # include_all is unchanged here, so include still serializes as "all" until
    # the flag is turned off; the include/exclude link sets are stored regardless.
    assert set["data"]["exclude"] == [excluded.id]

    patched =
      patch_json(conn, "/api/v1/views/#{vid}", %{"view" => %{"include_all" => false}})
      |> json_response(200)

    assert patched["data"]["include_all"] == false
    assert patched["data"]["include"] == [included.id]

    assert %{"errors" => %{"include" => [_ | _]}} =
             put_json(conn, "/api/v1/views/#{vid}/buckets", %{"include" => ["x"]})
             |> json_response(422)

    assert delete_json(conn, "/api/v1/views/#{vid}") |> response(204) == ""
    assert get_json(conn, "/api/v1/views/#{vid}") |> json_response(404)
  end

  # User story:
  # As an API client,
  # I want to assign buckets to depots, cash accounts and individual positions,
  # so that the analytics views can scope my holdings.
  #
  # Acceptance criteria:
  # - PUT /securities_accounts/:id/buckets and /cash_accounts/:id/buckets set the
  #   default bucket sets.
  # - PUT/DELETE .../positions/:security_id/buckets set and clear the override,
  #   with the explicit-empty state distinct from inherit.
  test "assigns buckets to depots, cash accounts and positions", %{conn: conn} do
    world = base_world()
    %{depot: depot, cash: cash} = world
    security = create_security!(name: "ACME", ticker: "ACME")
    {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Core"})

    depot_resp =
      put_json(conn, "/api/v1/securities_accounts/#{depot.id}/buckets", %{
        "bucket_ids" => [bucket.id]
      })
      |> json_response(200)

    assert depot_resp["data"]["bucket_ids"] == [bucket.id]

    cash_resp =
      put_json(conn, "/api/v1/cash_accounts/#{cash.id}/buckets", %{"bucket_ids" => [bucket.id]})
      |> json_response(200)

    assert cash_resp["data"]["bucket_ids"] == [bucket.id]

    # An explicit per-position override wins over the depot default.
    override =
      put_json(
        conn,
        "/api/v1/securities_accounts/#{depot.id}/positions/#{security.id}/buckets",
        %{"bucket_ids" => [bucket.id]}
      )
      |> json_response(200)

    assert override["data"]["override"] == "explicit"
    assert override["data"]["effective_bucket_ids"] == [bucket.id]

    # An empty list is the explicit-empty state (deliberately no buckets).
    empty =
      put_json(
        conn,
        "/api/v1/securities_accounts/#{depot.id}/positions/#{security.id}/buckets",
        %{"bucket_ids" => []}
      )
      |> json_response(200)

    assert empty["data"]["override"] == "explicit_empty"
    assert empty["data"]["effective_bucket_ids"] == []

    # Clearing returns the position to inheriting the depot default.
    cleared =
      delete_json(
        conn,
        "/api/v1/securities_accounts/#{depot.id}/positions/#{security.id}/buckets"
      )
      |> json_response(200)

    assert cleared["data"]["override"] == "inherit"
    assert cleared["data"]["effective_bucket_ids"] == [bucket.id]
  end

  # User story:
  # As an API client,
  # I want to pass a view scope to the analytics endpoints,
  # so that valuation/allocation/performance/risk describe only the holdings in
  # that view, with the active view echoed back.
  #
  # Acceptance criteria:
  # - GET valuation?view=<id> excludes positions outside the view and echoes the
  #   active view; the unscoped call is unchanged.
  # - An unknown view id returns 404; a malformed id returns 422.
  test "scopes the valuation by an optional view param", %{conn: conn} do
    world = base_world()
    %{portfolio: portfolio, depot: depot} = world

    in_view = create_security!(name: "In View", ticker: "INV")
    out_view = create_security!(name: "Out View", ticker: "OUT")
    buy!(world, in_view, quantity: "10", price: "100")
    buy!(world, out_view, quantity: "5", price: "100")
    put_quote!(in_view, ~D[2026-06-01], "100")
    put_quote!(out_view, ~D[2026-06-01], "100")

    {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Core"})

    :ok =
      Buckets.set_position_override(
        Actor.owner_ui(),
        depot,
        in_view,
        [bucket.id]
      )

    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Core view", include_all: false})
    :ok = Buckets.set_view_buckets(Actor.owner_ui(), view, [bucket.id], [])

    # Unscoped: both positions are present.
    unscoped =
      get_json(conn, "/api/v1/portfolios/#{portfolio.id}/valuation")
      |> json_response(200)
      |> Map.fetch!("data")

    assert length(unscoped["positions"]) == 2
    refute Map.has_key?(unscoped, "view")

    # Scoped to the view: only the in-view position remains, and the active view
    # is echoed (decimals stay strings).
    scoped =
      get_json(conn, "/api/v1/portfolios/#{portfolio.id}/valuation?view=#{view.id}")
      |> json_response(200)
      |> Map.fetch!("data")

    assert [position] = scoped["positions"]
    assert position["security_id"] == in_view.id
    assert is_binary(position["market_value"])
    assert scoped["view"] == %{"id" => view.id, "name" => "Core view"}

    # Unknown / malformed view ids.
    assert get_json(conn, "/api/v1/portfolios/#{portfolio.id}/valuation?view=999999")
           |> json_response(404)

    assert get_json(conn, "/api/v1/portfolios/#{portfolio.id}/valuation?view=abc")
           |> json_response(422)
  end

  test "scopes the allocation by an optional view param", %{conn: conn} do
    world = base_world()
    %{portfolio: portfolio} = world
    security = create_security!(name: "ACME", ticker: "ACME", asset_class: "equity")
    buy!(world, security, quantity: "10", price: "100")
    put_quote!(security, ~D[2026-06-01], "100")

    {:ok, classification} = Portfolixir.Classifications.create_classification(%{name: "Strategy"})
    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "All", include_all: true})

    data =
      get_json(
        conn,
        "/api/v1/portfolios/#{portfolio.id}/allocation?classification_id=#{classification.id}&view=#{view.id}"
      )
      |> json_response(200)
      |> Map.fetch!("data")

    assert data["view"] == %{"id" => view.id, "name" => "All"}

    # Malformed view id is a 422.
    assert get_json(
             conn,
             "/api/v1/portfolios/#{portfolio.id}/allocation?classification_id=#{classification.id}&view=abc"
           )
           |> json_response(422)
  end

  test "scopes performance and risk by an optional view param", %{conn: conn} do
    world = base_world()
    %{portfolio: portfolio} = world
    security = create_security!(name: "ACME", ticker: "ACME")
    buy!(world, security, quantity: "10", price: "100")
    put_quote!(security, ~D[2026-06-01], "100")

    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "All", include_all: true})

    perf =
      get_json(conn, "/api/v1/portfolios/#{portfolio.id}/performance?view=#{view.id}")
      |> json_response(200)
      |> Map.fetch!("data")

    assert perf["view"] == %{"id" => view.id, "name" => "All"}

    risk =
      get_json(conn, "/api/v1/portfolios/#{portfolio.id}/risk?view=#{view.id}")
      |> json_response(200)
      |> Map.fetch!("data")

    assert risk["view"] == %{"id" => view.id, "name" => "All"}
  end
end
