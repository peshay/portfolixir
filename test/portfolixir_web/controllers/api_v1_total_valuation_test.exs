defmodule PortfolixirWeb.ApiV1TotalValuationTest do
  use PortfolixirWeb.ConnCase

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, create_security!: 1, buy!: 3, deposit!: 4, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Portfolios.Valuation
  alias PortfolixirWeb.Api.V1.JSON

  @auth {"authorization", "Bearer test-api-token"}

  defp get_json(conn, path) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header(elem(@auth, 0), elem(@auth, 1))
    |> get(path)
  end

  # Two portfolios, nothing grouped: a fresh instance after its first imports
  # has no bucket and no view.
  defp seed do
    alpha = base_world(name: "Alpha", cash_name: "Alpha Cash", depot_name: "Alpha Depot")
    beta = base_world(name: "Beta", cash_name: "Beta Cash", depot_name: "Beta Depot")

    security = create_security!(name: "World Co.", ticker: "WRLD", asset_class: "equity")
    put_quote!(security, ~D[2026-06-01], "10")

    deposit!(alpha, "300", ~D[2026-01-01], [])
    buy!(alpha, security, quantity: "10", price: "10")
    deposit!(beta, "500", ~D[2026-01-01], [])
    buy!(beta, security, quantity: "5", price: "20")

    %{alpha: alpha, beta: beta, security: security}
  end

  # User story (#1007; Sprint 18 plan D-5):
  # As the agent meeting a fresh instance,
  # I want the total across every portfolio in one read, the figure the
  # dashboard's "Gesamt" shows,
  # so that my first answer does not need a structural write (a catch-all
  # view) or a client-side sum of portfolios.
  #
  # Acceptance criteria:
  # - GET /api/v1/valuation answers the unscoped union Valuation.for_view(nil)
  #   reads: every account of every portfolio, each counted once, in EUR,
  #   without any view existing.
  # - It has the view valuation's shape with view_id null and no view echo,
  #   financial decimals as strings, and a valuation_note naming the scope.
  # - include_positions=false returns the roll-up only, as on the view read;
  #   an invalid value is a 422.
  test "answers the total across every portfolio without a view", %{conn: conn} do
    world = seed()

    assert Buckets.list_views() == []

    data =
      get_json(conn, "/api/v1/valuation")
      |> json_response(200)
      |> Map.fetch!("data")

    # Positions 100 + 50, cash 200 + 400, each account once.
    assert data["view_id"] == nil
    refute Map.has_key?(data, "view")
    assert data["base_currency"] == "EUR"
    assert data["total_value"] == "150"
    assert data["total_cash"] == "600"
    assert data["total_with_cash"] == "750"
    assert data["counting_cash"] == "600"
    assert data["cash_quote"] == "0.8"
    assert is_binary(data["as_of"])
    assert data["positions_included"] == true
    assert data["matches_no_accounts"] == false

    assert data["valuation_note"] =~
             "across ALL portfolios and every account, each counted once, with no view"

    assert [alpha_row, beta_row] = Enum.sort_by(data["positions"], & &1["securities_account_id"])
    assert alpha_row["securities_account_id"] == world.alpha.depot.id
    assert alpha_row["market_value"] == "100"
    assert beta_row["market_value"] == "50"
    assert length(data["cash_balances"]) == 2

    # The figure the dashboard's "Gesamt" reads, value for value.
    expected =
      nil
      |> Valuation.for_view()
      |> JSON.view_valuation()
      |> Jason.encode!()
      |> Jason.decode!()

    for key <- ~w(total_value total_cash counting_cash total_with_cash cash_quote positions) do
      assert data[key] == expected[key], key
    end

    rollup =
      get_json(conn, "/api/v1/valuation?include_positions=false")
      |> json_response(200)
      |> Map.fetch!("data")

    assert rollup["positions_included"] == false
    refute Map.has_key?(rollup, "positions")
    assert rollup["total_with_cash"] == "750"

    assert get_json(conn, "/api/v1/valuation?include_positions=maybe")
           |> json_response(422) == %{"errors" => %{"include_positions" => ["is invalid"]}}
  end

  test "a view that narrows nothing reads the same total as the view-less read", %{conn: conn} do
    seed()

    {:ok, everything} = Buckets.create_view(Actor.owner_ui(), %{name: "Everything"})

    total = get_json(conn, "/api/v1/valuation") |> json_response(200) |> Map.fetch!("data")

    view =
      get_json(conn, "/api/v1/views/#{everything.id}/valuation")
      |> json_response(200)
      |> Map.fetch!("data")

    for key <- ~w(total_value total_cash total_with_cash cash_quote positions cash_balances) do
      assert total[key] == view[key], key
    end
  end
end
