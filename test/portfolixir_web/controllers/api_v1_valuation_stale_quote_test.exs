defmodule PortfolixirWeb.ApiV1ValuationStaleQuoteTest do
  use PortfolixirWeb.ConnCase

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Catalog.DataQuality

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    %{conn: conn}
  end

  # User story (#779 and #610, Lane X step 3 — the agent's half):
  # As the operating agent reading a valuation,
  # I want each position's price_date and the count of stale-quoted
  # positions in the payload, on the portfolio scope, the view scope and the
  # by-security read alike,
  # so that "the total is current" is something I can check rather than
  # assume.
  test "the three valuation reads carry price_date and stale_priced_count", %{conn: conn} do
    world = base_world(name: "API SQ", cash_name: "ASQ Cash", depot_name: "ASQ Depot")
    stale = create_security!(name: "Stale Co", ticker: "STA")
    today = Date.utc_today()
    stale_day = Date.add(today, -(DataQuality.stale_days() + 5))

    deposit!(world, "1000", Date.add(today, -100))
    buy!(world, stale, quantity: "1", price: "10", date: Date.add(today, -50))
    put_quote!(stale, stale_day, "9")

    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Everything", include_all: true})

    %{"data" => portfolio} =
      conn |> get("/api/v1/portfolios/#{world.portfolio.id}/valuation") |> json_response(200)

    assert portfolio["stale_priced_count"] == 1
    assert [position] = portfolio["positions"]
    assert position["price_date"] == Date.to_iso8601(stale_day)
    assert position["price_source"] == "quote"
    assert portfolio["valuation_note"] =~ "price_date"

    %{"data" => scoped} = conn |> get("/api/v1/views/#{view.id}/valuation") |> json_response(200)
    assert scoped["stale_priced_count"] == 1
    assert [scoped_position] = scoped["positions"]
    assert scoped_position["price_date"] == Date.to_iso8601(stale_day)

    %{"data" => global} = conn |> get("/api/v1/holdings/by_security") |> json_response(200)
    assert [row] = global["holdings"]
    assert row["price_date"] == Date.to_iso8601(stale_day)
  end
end
