defmodule PortfolixirWeb.ApiV1CategoryResultsTest do
  use PortfolixirWeb.ConnCase

  import Portfolixir.WorldFixtures,
    only: [
      add_depot: 2,
      base_world: 0,
      base_world: 1,
      create_security!: 1,
      buy!: 3,
      cross_trade!: 3,
      deposit!: 3,
      deposit!: 4,
      put_quote!: 3
    ]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Classifications
  alias Portfolixir.Fx

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

    # #1091: the portfolio form serves the excluded members too, each once.
    assert data["excluded_members"] == [
             %{
               "security_id" => world.dark.id,
               "security_name" => "Dark AG",
               "category_id" => world.core.id,
               "reason" => "no_usable_price",
               "native_costs" => []
             }
           ]
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

    # #1091: every form serves excluded_members, and every scope sentence
    # names it.
    for data <- [unscoped, narrowed, across] do
      assert data["basis_note"] =~
               "excluded_members names each member left out, once across the tree."
    end
  end

  # #1048 (pick J10.2 A) put the excluded members, once each with their
  # native costs, into the engine's result for the classification screen,
  # and kept the key internal until #1091 decided how to serve it. #1091's
  # read half decides (decision α, deferred to this read): every form serves
  # excluded_members, additively. The pin below names it; every other field
  # and figure is the one the view read had.
  test "the view read serves the excluded members beside its unchanged fields (#1091)", %{
    conn: conn
  } do
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
             ~w(base_currency basis basis_note categories classification_id excluded_members portfolio_id scope view view_id)

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

    # The list the screen shows: each excluded member once, sorted by name,
    # with the category it is filed under, its reason and, when its cost was
    # paid outside EUR, that cost in its own currency, as Decimal strings.
    assert data["excluded_members"] == [
             %{
               "security_id" => world.dark.id,
               "security_name" => "Dark AG",
               "category_id" => world.core.id,
               "reason" => "no_usable_price",
               "native_costs" => []
             },
             %{
               "security_id" => harborline.id,
               "security_name" => "Harborline Freight Inc",
               "category_id" => world.core.id,
               "reason" => "missing_base_cost",
               "native_costs" => [%{"amount" => "1500", "currency" => "USD"}]
             }
           ]
  end

  # User story (#1091, the read half; Sprint 19 plan D-7):
  # As the agent asked how each category is doing across everything the
  # operator holds, with no view picked,
  # I want the all-portfolios category result the classification screen
  # shows, in one read,
  # so that I answer the screen's figure, and name what it leaves out,
  # without a view or a portfolio to pick first.
  #
  # Acceptance criteria:
  # - GET /api/v1/category-results?classification_id= answers
  #   CategoryResult.for_all_portfolios/2: scope "all", portfolio_id and
  #   view_id null, base_currency "EUR", no view echo.
  # - A member held in a portfolio whose base currency is not EUR is out of
  #   the sum and named in excluded_members with its native cost.
  # - basis_note closes on the scope: every portfolio, in EUR, and why a
  #   non-EUR portfolio's member is out.
  # - A missing classification_id is a 422, an unknown one a 404.
  test "answers the category result across every portfolio without a scope", %{conn: conn} do
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

    data =
      get_json(conn, "/api/v1/category-results?classification_id=#{world.classification.id}")
      |> json_response(200)
      |> Map.fetch!("data")

    assert data["scope"] == "all"
    assert data["portfolio_id"] == nil
    assert data["view_id"] == nil
    assert data["base_currency"] == "EUR"
    assert data["classification_id"] == world.classification.id
    assert data["basis"] == "current_composition"
    refute Map.has_key?(data, "view")

    # Alpha alone, in EUR: Dark has no price, Harborline's cost was paid in
    # USD.
    assert [core] = data["categories"]
    assert core["invested"] == "1000"
    assert core["current_value"] == "1500"
    assert core["result_abs"] == "500"
    assert core["covered_count"] == 1
    assert core["member_count"] == 3

    assert [
             %{"security_name" => "Dark AG", "reason" => "no_usable_price", "native_costs" => []},
             %{
               "security_id" => harbor_id,
               "security_name" => "Harborline Freight Inc",
               "category_id" => category_id,
               "reason" => "missing_base_cost",
               "native_costs" => [%{"amount" => "1500", "currency" => "USD"}]
             }
           ] = data["excluded_members"]

    assert harbor_id == harborline.id
    assert category_id == world.core.id

    assert data["basis_note"] =~
             "Scope: the positions of every portfolio, each account counted once, in EUR"

    assert data["basis_note"] =~ "excluded_members"

    assert get_json(conn, "/api/v1/category-results")
           |> json_response(422) == %{"errors" => %{"classification_id" => ["is required"]}}

    assert get_json(conn, "/api/v1/category-results?classification_id=9999999")
           |> json_response(404)

    assert get_json(conn, "/api/v1/category-results?classification_id=abc")
           |> json_response(404)
  end

  # Acceptance criteria (#1091, review round):
  # - A security held in a EUR and in a USD portfolio is excluded whole from
  #   the every-portfolio read (no partial sum of a security), and its
  #   native_costs carry both slices' costs, the result's currency (EUR)
  #   first, then the others by code.
  # - excluded_members is sorted by name without regard to case, ties by
  #   security_id.
  test "names a security held in EUR and in USD once, with both costs", %{conn: conn} do
    world = seed()

    dollar =
      base_world(
        name: "Dollar",
        currency: "USD",
        cash_name: "Dollar Cash",
        depot_name: "Dollar Depot"
      )

    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2026-01-01],
          rate: "1.25",
          source: "manual"
        }
      ])

    crossing = create_security!(name: "Crossing Lines Inc", ticker: "CRL", currency: "USD")
    # Lower case on purpose: a byte-wise sort would put it after "Dark AG".
    aurora = create_security!(name: "aurora fund", ticker: "AUR")

    for security <- [crossing, aurora] do
      {:ok, _} =
        Classifications.assign_security(
          Actor.owner_ui(),
          security.id,
          world.classification.id,
          world.core.id
        )
    end

    # The EUR slice: 10 at 125 USD, settled at 1000 EUR; the USD slice: 10
    # at 150 USD. Aurora is held but never priced.
    cross_trade!(world, crossing,
      quantity: "10",
      price: "125",
      settled: "1000",
      gross: "1000",
      date: ~D[2026-01-02]
    )

    deposit!(dollar, "10000", ~D[2026-01-01], currency: "USD")
    buy!(dollar, crossing, quantity: "10", price: "150", currency: "USD")
    put_quote!(crossing, Date.utc_today(), "180")
    buy!(world, aurora, quantity: "2", price: "10")

    data =
      get_json(conn, "/api/v1/category-results?classification_id=#{world.classification.id}")
      |> json_response(200)
      |> Map.fetch!("data")

    # Alpha alone: Crossing leaves whole, Dark and Aurora have no price.
    assert [core] = data["categories"]
    assert core["invested"] == "1000"
    assert core["covered_count"] == 1
    assert core["member_count"] == 4

    assert Enum.map(data["excluded_members"], &{&1["security_name"], &1["reason"]}) == [
             {"aurora fund", "no_usable_price"},
             {"Crossing Lines Inc", "missing_base_cost"},
             {"Dark AG", "no_usable_price"}
           ]

    crossing_member = Enum.find(data["excluded_members"], &(&1["security_id"] == crossing.id))

    assert crossing_member["native_costs"] == [
             %{"amount" => "1000", "currency" => "EUR"},
             %{"amount" => "1500", "currency" => "USD"}
           ]
  end

  # Acceptance criteria (#1091, review round): the every-portfolio read takes
  # no scope; view= and portfolio_id= are ignored, as on GET
  # /api/v1/valuation, and the answer stays scope "all" with no view echo.
  test "the every-portfolio read ignores view= and portfolio_id=", %{conn: conn} do
    world = seed()
    {:ok, narrow} = Buckets.create_view(Actor.owner_ui(), %{name: "Narrow", include_all: false})
    path = "/api/v1/category-results?classification_id=#{world.classification.id}"

    plain = get_json(conn, path) |> json_response(200) |> Map.fetch!("data")

    scoped =
      get_json(conn, path <> "&view=#{narrow.id}&portfolio_id=#{world.portfolio.id}")
      |> json_response(200)
      |> Map.fetch!("data")

    assert scoped["scope"] == "all"
    assert scoped["view_id"] == nil
    refute Map.has_key?(scoped, "view")
    assert scoped == plain
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
