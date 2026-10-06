defmodule PortfolixirWeb.ApiV1CategoryResultsTest do
  use PortfolixirWeb.ConnCase

  import Portfolixir.WorldFixtures,
    only: [
      add_depot: 2,
      base_world: 0,
      base_world: 1,
      create_security!: 1,
      buy!: 3,
      deposit!: 3,
      deposit!: 4,
      put_quote!: 3
    ]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Classifications

  @auth {"authorization", "Bearer test-api-token"}

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header(elem(@auth, 0), elem(@auth, 1))
  end

  defp get_json(conn, path), do: conn |> api_conn() |> get(path)

  defp seed do
    world = base_world()

    {:ok, classification} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

    {:ok, core} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Core"
      })

    alpha = create_security!(name: "Alpha AG", ticker: "ALP")
    dark = create_security!(name: "Dark AG", ticker: "DRK")

    for security <- [alpha, dark] do
      {:ok, _} =
        Classifications.assign_security(
          Actor.owner_ui(),
          security.id,
          classification.id,
          core.id
        )
    end

    deposit!(world, "10000", ~D[2026-01-01])
    buy!(world, alpha, quantity: "10", price: "100")
    buy!(world, dark, quantity: "10", price: "50")

    # Alpha is priced at 150 (invested 1000, now 1500); Dark has no quote at
    # all, so its result is not derivable.
    Portfolixir.WorldFixtures.put_quote!(alpha, Date.utc_today(), "150")

    Map.merge(world, %{classification: classification, core: core, alpha: alpha, dark: dark})
  end

  # User story (#712, ADR-0041 §7):
  # As the LLM agent maintaining this portfolio,
  # I want each category's invested, current value and result in one call, with
  # the rows behind it and the rows it could not cover,
  # so that I can answer "how is Core doing?" without joining holdings to the
  # classification tree myself — and without mistaking a gap for a zero.
  #
  # Acceptance criteria:
  # - Financial values serialize as Decimal STRINGS (AR-11).
  # - The payload carries the one-line computation basis of ADR-0041 §1.
  # - It carries covered/total member counts and the excluded rows with their
  #   reasons, so an aggregate always has an address.
  # - The member positions ship with the aggregate (§3), never as a follow-up.
  test "reports the money-weighted category roll-up with its members and gaps", %{conn: conn} do
    world = seed()

    data =
      get_json(
        conn,
        "/api/v1/portfolios/#{world.portfolio.id}/category-results" <>
          "?classification_id=#{world.classification.id}"
      )
      |> json_response(200)
      |> Map.fetch!("data")

    # §1: the basis is one line, and it is stated rather than implied.
    assert data["basis"] == "current_composition"

    assert [core] = data["categories"]
    assert core["category_id"] == world.core.id
    assert core["name"] == "Core"

    # Decimal strings, not numbers (AR-11).
    assert core["invested"] == "1000"
    assert core["current_value"] == "1500"
    assert core["result_abs"] == "500"
    assert core["result_pct"] == "0.5"

    # §4: the unpriceable member is out of BOTH sides of the sum and named.
    assert core["covered_count"] == 1
    assert core["member_count"] == 2
    assert [excluded] = core["excluded"]
    assert excluded["security_name"] == "Dark AG"
    assert excluded["reason"] == "no_usable_price"

    # §3: the rows behind the aggregate ship with it.
    assert [position] = core["positions"]
    assert position["security_name"] == "Alpha AG"
    assert position["invested"] == "1000"
    assert position["result_abs"] == "500"
    assert position["result_pct"] == "0.5"
  end

  # User story (#901; ADR-0041 §1, ADR-0051 §6):
  # As the LLM agent maintaining this portfolio,
  # I want the category result at the scopes the performance family reads —
  # one portfolio narrowed with view=, or a view across every portfolio —
  # so that I can answer "how is Core doing in my retirement view?" in one
  # call, at the scope the operator's question names.
  #
  # Acceptance criteria:
  # - GET /api/v1/portfolios/:portfolio_id/category-results takes view= and
  #   rolls up only the portfolio's positions matching it, echoing the view.
  # - GET /api/v1/views/:view_id/category-results rolls up the positions
  #   matching the view across every portfolio, each account once, in EUR.
  # - Financial values stay Decimal strings, and the payload states its scope:
  #   scope, portfolio_id, view_id, base_currency, and a basis_note naming it.
  # - The unscoped read is unchanged but for the scope it now states.
  test "takes the view scope in the performance family's two forms", %{conn: conn} do
    world = seed()

    second =
      base_world(name: "Second", cash_name: "Second Cash", depot_name: "Second Depot")

    {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Retirement"})
    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Retired", include_all: false})
    :ok = Buckets.set_view_buckets(Actor.owner_ui(), view, [bucket.id], [])

    # The first depot holds Alpha and Dark; a second depot of the same
    # portfolio holds Gamma, untagged; the second portfolio holds Alpha, tagged.
    %{depot: untagged, cash: untagged_cash} =
      add_depot(world.portfolio, depot_name: "Untagged", cash_name: "Untagged Cash")

    gamma = create_security!(name: "Gamma AG", ticker: "GAM")

    {:ok, _} =
      Classifications.assign_security(
        Actor.owner_ui(),
        gamma.id,
        world.classification.id,
        world.core.id
      )

    deposit!(%{world | depot: untagged, cash: untagged_cash}, "10000", ~D[2026-01-01])
    buy!(%{world | depot: untagged, cash: untagged_cash}, gamma, quantity: "4", price: "25")
    put_quote!(gamma, Date.utc_today(), "25")

    deposit!(second, "10000", ~D[2026-01-01])
    buy!(second, world.alpha, quantity: "5", price: "120")

    :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), world.depot, [bucket.id])
    :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), second.depot, [bucket.id])

    path = "/category-results?classification_id=#{world.classification.id}"

    # The shipped read, unscoped: Alpha 1000 and Gamma 100; it states its scope.
    unscoped =
      get_json(conn, "/api/v1/portfolios/#{world.portfolio.id}" <> path)
      |> json_response(200)
      |> Map.fetch!("data")

    assert [core] = unscoped["categories"]
    assert core["invested"] == "1100"
    assert unscoped["scope"] == "portfolio"
    assert unscoped["portfolio_id"] == world.portfolio.id
    assert unscoped["view_id"] == nil
    assert unscoped["base_currency"] == "EUR"
    refute Map.has_key?(unscoped, "view")
    assert unscoped["basis_note"] =~ "Scope: the positions of portfolio #{world.portfolio.id}"

    # Form one: the portfolio narrowed with view=. Gamma's depot is untagged.
    narrowed =
      get_json(conn, "/api/v1/portfolios/#{world.portfolio.id}" <> path <> "&view=#{view.id}")
      |> json_response(200)
      |> Map.fetch!("data")

    assert [core] = narrowed["categories"]
    assert core["invested"] == "1000"
    assert core["current_value"] == "1500"
    assert core["result_abs"] == "500"
    assert core["result_pct"] == "0.5"
    assert core["member_count"] == 2
    assert [%{"security_name" => "Dark AG"}] = core["excluded"]
    assert narrowed["scope"] == "portfolio"
    assert narrowed["portfolio_id"] == world.portfolio.id
    assert narrowed["view_id"] == view.id
    assert narrowed["view"] == %{"id" => view.id, "name" => "Retired"}
    assert narrowed["basis"] == "current_composition"
    assert narrowed["basis_note"] =~ "that match view #{view.id}"

    # Form two: the view across every portfolio, each account once, in EUR.
    across =
      get_json(conn, "/api/v1/views/#{view.id}" <> path)
      |> json_response(200)
      |> Map.fetch!("data")

    assert [core] = across["categories"]
    # Alpha 10 at 100 plus 5 at 120; 15 units at 150.
    assert core["invested"] == "1600"
    assert core["current_value"] == "2250"
    assert core["result_abs"] == "650"
    assert core["result_pct"] == "0.40625"
    assert [position] = core["positions"]
    assert position["quantity"] == "15"
    assert across["scope"] == "view"
    assert across["portfolio_id"] == nil
    assert across["view_id"] == view.id
    assert across["base_currency"] == "EUR"
    assert across["view"] == %{"id" => view.id, "name" => "Retired"}
    assert across["basis_note"] =~ "across every portfolio, each account counted once, in EUR"
  end

  # #1048 (pick J10.2 A): the engine's result now carries the excluded
  # members once each, with their native costs, for the classification
  # screen. That key is internal until #1091 decides how to serve it, so the
  # view read's JSON keeps exactly the fields and figures it had.
  test "the view read's payload is unchanged by the excluded-members list (#1048)", %{conn: conn} do
    world = seed()

    dollar =
      base_world(
        name: "Dollar",
        currency: "USD",
        cash_name: "Dollar Cash",
        depot_name: "Dollar Depot"
      )

    harborline =
      create_security!(name: "Harborline Freight Inc", ticker: "HBF", currency: "USD")

    {:ok, _} =
      Classifications.assign_security(
        Actor.owner_ui(),
        harborline.id,
        world.classification.id,
        world.core.id
      )

    deposit!(dollar, "10000", ~D[2026-01-01], currency: "USD")
    buy!(dollar, harborline, quantity: "10", price: "150", currency: "USD")
    put_quote!(harborline, Date.utc_today(), "180")

    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Everything"})

    data =
      get_json(
        conn,
        "/api/v1/views/#{view.id}/category-results?classification_id=#{world.classification.id}"
      )
      |> json_response(200)
      |> Map.fetch!("data")

    assert data |> Map.keys() |> Enum.sort() ==
             ~w(base_currency basis basis_note categories classification_id portfolio_id scope view view_id)

    assert [core] = data["categories"]

    assert core |> Map.keys() |> Enum.sort() ==
             ~w(category_id covered_count current_value excluded invested member_count name parent_id positions result_abs result_pct)

    # Alpha alone: Dark has no price, and Harborline's cost was paid in USD.
    assert core["invested"] == "1000"
    assert core["result_abs"] == "500"
    assert core["covered_count"] == 1
    assert core["member_count"] == 3

    assert [
             %{"security_name" => "Dark AG", "reason" => "no_usable_price"} = dark,
             %{"security_name" => "Harborline Freight Inc", "reason" => "missing_base_cost"} =
               harbor
           ] = Enum.sort_by(core["excluded"], & &1["security_name"])

    for entry <- [dark, harbor] do
      assert entry |> Map.keys() |> Enum.sort() == ~w(reason security_id security_name)
    end
  end

  test "answers the view scope's errors as the performance family does", %{conn: conn} do
    world = seed()
    portfolio_path = "/api/v1/portfolios/#{world.portfolio.id}/category-results"
    classification = "classification_id=#{world.classification.id}"

    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Everything"})

    # Form one: a malformed view is a 422 naming it, an unknown one a 404.
    assert get_json(conn, portfolio_path <> "?#{classification}&view=abc")
           |> json_response(422) == %{"errors" => %{"view" => ["is invalid"]}}

    assert get_json(conn, portfolio_path <> "?#{classification}&view=9999999")
           |> json_response(404)

    # Form two: an unknown or malformed view id is a 404, a missing
    # classification a 422, an unknown classification a 404.
    assert get_json(conn, "/api/v1/views/9999999/category-results?#{classification}")
           |> json_response(404)

    assert get_json(conn, "/api/v1/views/abc/category-results?#{classification}")
           |> json_response(404)

    assert get_json(conn, "/api/v1/views/#{view.id}/category-results")
           |> json_response(422) == %{"errors" => %{"classification_id" => ["is required"]}}

    assert get_json(conn, "/api/v1/views/#{view.id}/category-results?classification_id=9999999")
           |> json_response(404)
  end

  test "requires a classification and 404s an unknown portfolio", %{conn: conn} do
    world = seed()

    assert get_json(conn, "/api/v1/portfolios/#{world.portfolio.id}/category-results")
           |> json_response(422) == %{"errors" => %{"classification_id" => ["is required"]}}

    assert get_json(conn, "/api/v1/portfolios/9999999/category-results?classification_id=1")
           |> json_response(404)

    # A non-numeric id is a 404, not a 500.
    assert get_json(conn, "/api/v1/portfolios/not-an-id/category-results?classification_id=1")
           |> json_response(404)

    # ...and so is a classification that does not exist: the engine's
    # {:error, :not_found} must not surface as a crash.
    assert get_json(
             conn,
             "/api/v1/portfolios/#{world.portfolio.id}/category-results" <>
               "?classification_id=9999999"
           )
           |> json_response(404)
  end
end
