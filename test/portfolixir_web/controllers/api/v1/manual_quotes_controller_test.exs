defmodule PortfolixirWeb.Api.V1.ManualQuotesControllerTest do
  # Sprint 17 V2 (T-9, pick G3-A) under the two-way rule: the summary of a
  # security's manual quotes the release dialog reads is the agent's read as
  # well — GET /api/v1/securities/:security_id/quotes/manual. Every name,
  # close and date is synthetic.
  use PortfolixirWeb.ConnCase, async: true

  import Portfolixir.WorldFixtures, only: [create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog.Quotes

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    security = create_security!(name: "Meridian Global Equity ETF", ticker: nil)

    {:ok, _} =
      Quotes.upsert_many(security.id, [
        %{date: ~D[2026-06-29], close: "100.00", source: "portfolio_performance"},
        %{date: ~D[2026-07-06], close: "100.50", source: "portfolio_performance"}
      ])

    {:ok, _} =
      Quotes.upsert_authored(Actor.api_token_rw("synthetic"), security.id, [
        %{"date" => "2026-06-30", "close" => "104.00"},
        %{"date" => "2026-07-01", "close" => "104.10"},
        %{"date" => "2026-09-14", "close" => "105.95"},
        %{"date" => "2026-09-15", "close" => "106.10"}
      ])

    %{conn: conn, security: security}
  end

  # User story:
  # As the agent asked to release a security's pinned closes,
  # I want to read which of its stored quotes are manual over the whole
  # history — how many, from when to when, in which stretches — and whether
  # the quote sync can refill a released day,
  # so that I release the range the operator means and can say what follows.
  #
  # Acceptance criteria:
  # - 200 with security_id, count, first, last, stored_count, stretch_count,
  #   stretches (from, to, count; ascending) and sync_adapter; dates ISO.
  # - meta.limit is the stretches' bound (default 100, capped at 1000).
  # - No range is given, so the answer carries no range.
  test "summarizes the manual quotes of the whole history", %{conn: conn, security: security} do
    body =
      conn |> get("/api/v1/securities/#{security.id}/quotes/manual") |> json_response(200)

    assert body["data"] == %{
             "security_id" => security.id,
             "count" => 4,
             "first" => "2026-06-30",
             "last" => "2026-09-15",
             "stored_count" => 6,
             "stretch_count" => 2,
             "stretches" => [
               %{"from" => "2026-06-30", "to" => "2026-07-01", "count" => 2},
               %{"from" => "2026-09-14", "to" => "2026-09-15", "count" => 2}
             ],
             "sync_adapter" => false
           }

    assert body["meta"] == %{"limit" => 100}
  end

  # User story:
  # As the agent previewing a release,
  # I want the count of manual quotes in the range I would release,
  # so that I can say how many closes it removes before I write.
  #
  # Acceptance criteria:
  # - from and/or to add range {from, to, count}: the manual quotes in the
  #   range, both bounds inclusive; an absent bound is open.
  # - to before from answers 422 on to, an invalid date 422 naming it, as
  #   the release does.
  # - limit keeps the newest stretches; 0 or a non-number answers 422.
  test "counts a range and keeps the list family's limit", %{conn: conn, security: security} do
    path = "/api/v1/securities/#{security.id}/quotes/manual"

    assert %{"range" => %{"from" => "2026-06-30", "to" => "2026-07-06", "count" => 2}} =
             conn
             |> get(path <> "?from=2026-06-30&to=2026-07-06")
             |> json_response(200)
             |> Map.fetch!("data")

    assert %{"range" => %{"from" => "2026-09-01", "to" => nil, "count" => 2}} =
             conn |> get(path <> "?from=2026-09-01") |> json_response(200) |> Map.fetch!("data")

    assert %{"errors" => %{"to" => ["must be on or after from"]}} =
             conn |> get(path <> "?from=2026-09-01&to=2026-06-30") |> json_response(422)

    assert %{"errors" => %{"from" => ["is invalid"]}} =
             conn |> get(path <> "?from=2026-13-01") |> json_response(422)

    assert %{
             "data" => %{"stretches" => [%{"from" => "2026-09-14"}], "stretch_count" => 2},
             "meta" => %{"limit" => 1}
           } =
             conn |> get(path <> "?limit=1") |> json_response(200)

    assert %{"errors" => %{"limit" => [_]}} =
             conn |> get(path <> "?limit=0") |> json_response(422)
  end

  # User story:
  # As the agent,
  # I want an unknown security answered like every other read under it,
  # so that a stale id reads as one.
  #
  # Acceptance criteria:
  # - An id no security carries answers 404.
  test "answers 404 for an unknown security", %{conn: conn} do
    assert %{"errors" => %{"detail" => _}} =
             conn |> get("/api/v1/securities/999999999/quotes/manual") |> json_response(404)
  end
end
