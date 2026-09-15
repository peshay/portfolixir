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
    # #798: the freshness read — the newest stored quote across the quoted
    # positions — rides the same payloads, its basis stated in the note.
    assert portfolio["newest_quote_date"] == Date.to_iso8601(stale_day)
    assert portfolio["valuation_note"] =~ "newest_quote_date"

    %{"data" => scoped} = conn |> get("/api/v1/views/#{view.id}/valuation") |> json_response(200)
    assert scoped["stale_priced_count"] == 1
    assert scoped["newest_quote_date"] == Date.to_iso8601(stale_day)
    assert scoped["valuation_note"] =~ "newest_quote_date"
    assert [scoped_position] = scoped["positions"]
    assert scoped_position["price_date"] == Date.to_iso8601(stale_day)

    %{"data" => global} = conn |> get("/api/v1/holdings/by_security") |> json_response(200)
    assert [row] = global["holdings"]
    assert row["price_date"] == Date.to_iso8601(stale_day)
  end

  # Closing-act finding (UAT persona, Sprint 11): the count leaves a retired
  # holding out — the remedy the finding names clears it, on every scope.
  test "a retired holding is not in stale_priced_count", %{conn: conn} do
    world = base_world(name: "SQR", cash_name: "SQR Cash", depot_name: "SQR Depot")
    retired = create_security!(name: "Delisted Co", ticker: "DLS")
    today = Date.utc_today()

    deposit!(world, "1000", Date.add(today, -100))
    buy!(world, retired, quantity: "1", price: "10", date: Date.add(today, -50))
    put_quote!(retired, Date.add(today, -(DataQuality.stale_days() + 1)), "9")

    {:ok, _} = Portfolixir.Catalog.update_security(Actor.owner_ui(), retired, %{is_retired: true})
    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "All"})

    # A retired holding is out of the freshness read too: with no other
    # quoted position the newest quote date is null, not the stopped feed's.
    assert %{"data" => %{"stale_priced_count" => 0, "newest_quote_date" => nil}} =
             json_response(get(conn, "/api/v1/portfolios/#{world.portfolio.id}/valuation"), 200)

    assert %{"data" => %{"stale_priced_count" => 0, "newest_quote_date" => nil}} =
             json_response(
               get(
                 recycle(conn)
                 |> put_req_header("accept", "application/json")
                 |> put_req_header("authorization", "Bearer test-api-token"),
                 "/api/v1/views/#{view.id}/valuation"
               ),
               200
             )
  end

  # #798: the freshness cell's value is the newest quote across the held,
  # quoted positions — the max, not the first row's date.
  test "newest_quote_date is the newest quote across the quoted positions", %{conn: conn} do
    world = base_world(name: "NQD", cash_name: "NQD Cash", depot_name: "NQD Depot")
    today = Date.utc_today()
    older = create_security!(name: "Older Co", ticker: "OLD")
    newer = create_security!(name: "Newer Co", ticker: "NEW")

    deposit!(world, "1000", Date.add(today, -100))
    buy!(world, older, quantity: "1", price: "10", date: Date.add(today, -50))
    buy!(world, newer, quantity: "1", price: "10", date: Date.add(today, -50))
    put_quote!(older, Date.add(today, -3), "9")
    put_quote!(newer, Date.add(today, -1), "11")

    assert %{"data" => %{"newest_quote_date" => date}} =
             json_response(get(conn, "/api/v1/portfolios/#{world.portfolio.id}/valuation"), 200)

    assert date == Date.to_iso8601(Date.add(today, -1))
  end
end
