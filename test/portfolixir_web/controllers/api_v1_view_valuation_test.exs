defmodule PortfolixirWeb.ApiV1ViewValuationTest do
  use PortfolixirWeb.ConnCase

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, create_security!: 1, buy!: 3, deposit!: 4, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets

  @auth {"authorization", "Bearer test-api-token"}

  defp get_json(conn, path) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header(elem(@auth, 0), elem(@auth, 1))
    |> get(path)
  end

  # User story:
  # As an API client (and the LLM I connect over MCP),
  # I want a view's total wealth across all portfolios from one endpoint,
  # so that views are the trustworthy aggregation scope without client-side
  # summing over portfolios.
  #
  # Acceptance criteria:
  # - GET /api/v1/views/:view_id/valuation returns the cross-portfolio view
  #   valuation shaped through the shared presenter, financial decimals as
  #   strings, with the active view echoed.
  # - The response reports account-level overlap data for UI badges.
  # - An account tagged into two included buckets is counted once.
  # - Unknown and non-integer view ids return 404.
  test "returns the deduplicated cross-portfolio view valuation", %{conn: conn} do
    alpha = base_world(name: "Alpha", cash_name: "Alpha Cash", depot_name: "Alpha Depot")
    beta = base_world(name: "Beta", cash_name: "Beta Cash", depot_name: "Beta Depot")

    security = create_security!(name: "World Co.", ticker: "WRLD", asset_class: "equity")
    put_quote!(security, ~D[2026-06-01], "10")

    deposit!(alpha, "300", ~D[2026-01-01], [])
    buy!(alpha, security, quantity: "10", price: "10")
    deposit!(beta, "500", ~D[2026-01-01], [])
    buy!(beta, security, quantity: "5", price: "20")

    {:ok, mine} = Buckets.create_bucket(Actor.owner_ui(), %{name: "mine"})
    {:ok, household} = Buckets.create_bucket(Actor.owner_ui(), %{name: "household"})

    # The Alpha accounts carry BOTH buckets (the overlap); Beta only household.
    :ok =
      Buckets.set_depot_default_buckets(Actor.owner_ui(), alpha.depot, [mine.id, household.id])

    :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), alpha.cash, [mine.id, household.id])
    :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), beta.depot, [household.id])
    :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), beta.cash, [household.id])

    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Both", include_all: false})
    :ok = Buckets.set_view_buckets(Actor.owner_ui(), view, [mine.id, household.id], [])

    data =
      get_json(conn, "/api/v1/views/#{view.id}/valuation")
      |> json_response(200)
      |> Map.fetch!("data")

    # Decimals are strings; the Alpha accounts count once despite two included
    # buckets: positions 100 + 50, cash 200 + 400.
    assert data["view_id"] == view.id
    assert data["base_currency"] == "EUR"
    assert data["total_value"] == "150"
    assert data["total_cash"] == "600"
    assert data["total_with_cash"] == "750"
    assert is_binary(data["as_of"])
    assert is_binary(data["valuation_note"])

    # One position row per (depot, security) across portfolios.
    assert [alpha_pos, beta_pos] =
             Enum.sort_by(data["positions"], & &1["securities_account_id"])

    assert alpha_pos["securities_account_id"] == alpha.depot.id
    assert alpha_pos["market_value"] == "100"
    assert beta_pos["securities_account_id"] == beta.depot.id
    assert beta_pos["market_value"] == "50"

    assert length(data["cash_balances"]) == 2

    # Overlap as data for UI badges: the Alpha depot and cash carry two
    # included buckets.
    assert data["overlap"] == %{
             "overlapping" => true,
             "securities_account_ids" => [alpha.depot.id],
             "cash_account_ids" => [alpha.cash.id]
           }

    # The active view is echoed (FR-13).
    assert data["view"] == %{"id" => view.id, "name" => "Both"}

    # Unknown and non-integer view ids return 404.
    assert get_json(conn, "/api/v1/views/999999/valuation") |> json_response(404)
    assert get_json(conn, "/api/v1/views/abc/valuation") |> json_response(404)
  end
end
