defmodule PortfolixirWeb.ApiV1FxBackfillTest do
  # Issue #737 (Sprint 9 D-1): the historical ECB series as a one-shot backfill
  # through the existing sync endpoint — `scope=history` — on the Sprint 8 D-1
  # fixture (a GBP sale whose close date has no stored rate).
  use PortfolixirWeb.ConnCase

  alias Portfolixir.Fx.RateSync.Fake
  alias Portfolixir.WorldFixtures

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  defp get_json(conn, path), do: conn |> api_conn() |> get(path) |> json_response(200)

  setup do
    Fake.clear_response()
    :ok
  end

  # User story (issue #737):
  # As the operating agent who read `excluded.count: 1` on the realized-gains
  # facet,
  # I want POST /api/v1/exchange_rates/sync with scope=history to backfill
  # the historical series,
  # so that the excluded sale converts at its own close-date rate — and the
  # basis statement stays "exact booking-date rate": the backfill fills
  # dates, it does not change the rule.
  #
  # Acceptance criteria:
  # - scope=history runs the backfill and answers {provider, status,
  #   upserted, scope: "history"}; the default and scope=latest run the daily
  #   sync (scope: "latest"); an unknown scope is a 422.
  # - On the D-1 fixture, excluded.count goes 1 -> 0 and the converted total
  #   is the exact Decimal; the facet's basis still says "close date".
  test "scope=history backfills the series and the excluded sale converts exactly", %{
    conn: conn
  } do
    world = WorldFixtures.base_world()
    gbp = WorldFixtures.create_security!(name: "Pound Equity", ticker: "PEQ", currency: "GBP")

    gbp_world =
      Map.merge(
        world,
        WorldFixtures.add_depot(world.portfolio,
          currency: "GBP",
          cash_name: "GBP Cash",
          depot_name: "GBP Depot"
        )
      )

    WorldFixtures.buy!(gbp_world, gbp,
      quantity: "2",
      price: "10",
      date: ~D[2026-01-09],
      currency: "GBP"
    )

    WorldFixtures.sell!(gbp_world, gbp,
      quantity: "2",
      price: "30",
      date: ~D[2026-02-20],
      currency: "GBP"
    )

    before = get_json(conn, "/api/v1/realized_gains")["data"]
    assert before["excluded"] == %{"count" => 1, "securities" => ["Pound Equity"]}
    assert before["annual"] == []

    # The historical series carries the close date (and a neighbour that must
    # NOT be used for it).
    Fake.put_history_response(
      {:ok,
       [
         %{
           base_currency: "EUR",
           quote_currency: "GBP",
           date: ~D[2026-02-19],
           rate: "0.90",
           source: "ecb"
         },
         %{
           base_currency: "EUR",
           quote_currency: "GBP",
           date: ~D[2026-02-20],
           rate: "0.85",
           source: "ecb"
         }
       ]}
    )

    backfill =
      conn
      |> api_conn()
      |> post("/api/v1/exchange_rates/sync", Jason.encode!(%{"scope" => "history"}))
      |> json_response(200)
      |> Map.fetch!("data")

    assert backfill == %{
             "provider" => "fake",
             "status" => "ok",
             "upserted" => 2,
             "scope" => "history"
           }

    after_backfill = get_json(conn, "/api/v1/realized_gains")["data"]
    assert after_backfill["excluded"] == %{"count" => 0, "securities" => []}

    # 40 GBP realized at the exact 2026-02-20 rate, in the engine's own
    # arithmetic (EUR-hub triangulation: amount × (1 / rate)), full precision.
    expected =
      Decimal.new("40")
      |> Decimal.mult(Decimal.div(Decimal.new(1), Decimal.new("0.85")))
      |> Decimal.to_string(:normal)

    assert [%{"year" => 2026, "months" => months, "total" => total}] = after_backfill["annual"]
    assert months["2"] == expected
    assert total == expected

    # The rule did not move: still the rate stored on the sale's own close date.
    assert after_backfill["computation_basis"]["reference"] =~ "close date"
    assert after_backfill["conversion_note"] =~ "its own close date"

    # The default stays the daily sync, and the scope is echoed either way.
    Fake.put_response({:ok, []})

    assert %{"data" => %{"scope" => "latest", "upserted" => 0}} =
             conn |> api_conn() |> post("/api/v1/exchange_rates/sync") |> json_response(200)

    assert %{"errors" => %{"scope" => ["is invalid"]}} =
             conn
             |> api_conn()
             |> post("/api/v1/exchange_rates/sync", Jason.encode!(%{"scope" => "everything"}))
             |> json_response(422)
  end
end
