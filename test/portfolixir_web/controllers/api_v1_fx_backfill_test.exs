defmodule PortfolixirWeb.ApiV1FxBackfillTest do
  # Issue #737 (Sprint 9 D-1): the historical ECB series as a one-shot backfill
  # through the existing sync endpoint — `scope=history` — on the Sprint 8 D-1
  # fixture (a GBP sale whose close date has no stored rate).
  use PortfolixirWeb.ConnCase, async: false

  import ExUnit.CaptureLog

  alias Portfolixir.Actor
  alias Portfolixir.Fx.RateSync.Fake
  alias Portfolixir.Ledger
  alias Portfolixir.LostLockCycle
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

    assert before["excluded"] == %{
             "count" => 1,
             "securities" => ["Pound Equity"],
             # #1198 (Sprint 21 α3): by_reason tells a missing rate from a missing leg.
             "by_reason" => %{
               "no_rate" => %{"count" => 1, "securities" => ["Pound Equity"]},
               "missing_settlement_leg" => %{"count" => 0, "securities" => []}
             }
           }

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

    # #1196: the history run's answer carries the legs it derived; the GBP
    # sale is booked in its security's currency, so there are none.
    assert backfill == %{
             "provider" => "fake",
             "status" => "ok",
             "upserted" => 2,
             "scope" => "history",
             "settlement_legs" => %{
               "status" => "completed",
               "derived" => 0,
               "skipped_no_rate" => 0,
               "skipped_changed" => 0,
               "stopped_at_transaction_id" => nil
             }
           }

    after_backfill = get_json(conn, "/api/v1/realized_gains")["data"]

    assert after_backfill["excluded"] == %{
             "count" => 0,
             "securities" => [],
             "by_reason" => %{
               "no_rate" => %{"count" => 0, "securities" => []},
               "missing_settlement_leg" => %{"count" => 0, "securities" => []}
             }
           }

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

    # The daily sync derives no legs (#1196's limit): its answer says so.
    assert %{"data" => %{"scope" => "latest", "upserted" => 0, "settlement_legs" => nil}} =
             conn |> api_conn() |> post("/api/v1/exchange_rates/sync") |> json_response(200)

    assert %{"errors" => %{"scope" => ["is invalid"]}} =
             conn
             |> api_conn()
             |> post("/api/v1/exchange_rates/sync", Jason.encode!(%{"scope" => "everything"}))
             |> json_response(422)
  end

  # A EUR-booked buy of a USD security, as a Portfolio Performance import
  # stores it when no rate was there: 10 at 80.00 EUR, cash 806.00 EUR,
  # fees 5.00 and taxes 1.00 EUR, no legs (identity 6's first row).
  defp legless_import_buy!(notes \\ nil) do
    world = WorldFixtures.base_world(name: "Legs World", cash_name: "Legs Cash")

    usd =
      WorldFixtures.create_security!(name: "Legs Dollar Share", ticker: "LDS", currency: "USD")

    {:ok, buy} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        cash_account_id: world.cash.id,
        security_id: usd.id,
        type: "buy",
        date: ~D[2026-01-21],
        quantity: "10",
        price: "80.00",
        fees: "5.00",
        taxes: "1.00",
        gross_amount: "806.00",
        currency_code: "EUR",
        notes: notes
      })

    buy
  end

  defp usd_history(dates) do
    {:ok,
     Enum.map(dates, fn date ->
       %{base_currency: "EUR", quote_currency: "USD", date: date, rate: "1.25", source: "ecb"}
     end)}
  end

  defp history!(conn, status) do
    conn
    |> api_conn()
    |> post("/api/v1/exchange_rates/sync", Jason.encode!(%{"scope" => "history"}))
    |> json_response(status)
  end

  # User story (#1196, Sprint 21 α2; ADR-0015's amendment of 2026-10-09,
  # point 6):
  # As the operating agent that runs the history backfill after a first
  # import,
  # I want its answer to count the settlement legs the run derived and the
  # rows it skipped for a missing rate,
  # so that I can tell whether the import's cross-currency trades now carry
  # their legs without reading the ledger row by row.
  #
  # Acceptance criteria:
  # - scope=history over a EUR-booked buy of a USD security with no legs,
  #   and a second one dated before any rate, answers settlement_legs
  #   {status "completed", derived 1, skipped_no_rate 1}; the first buy now
  #   carries 800.00 EUR, 1,000.00 USD and 0.800000.
  test "scope=history answers the settlement legs it derived and skipped", %{conn: conn} do
    buy = legless_import_buy!()

    {:ok, early} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: buy.portfolio_id,
        securities_account_id: buy.securities_account_id,
        cash_account_id: buy.cash_account_id,
        security_id: buy.security_id,
        type: "buy",
        date: ~D[2025-12-01],
        quantity: "1",
        price: "80.00",
        gross_amount: "80.00",
        currency_code: "EUR"
      })

    Fake.put_history_response(usd_history([~D[2026-01-21]]))

    assert %{"data" => %{"upserted" => 1, "settlement_legs" => legs}} = history!(conn, 200)

    assert legs == %{
             "status" => "completed",
             "derived" => 1,
             "skipped_no_rate" => 1,
             "skipped_changed" => 0,
             "stopped_at_transaction_id" => nil
           }

    derived = Ledger.get_transaction(buy.id)
    assert Decimal.to_string(derived.settlement_amount) == "800.000000"
    assert Decimal.to_string(derived.security_amount) == "1000.000000"
    assert Decimal.to_string(derived.settlement_fx_rate) == "0.800000"
    assert Ledger.get_transaction(early.id).security_amount == nil
  end

  # User story (#1196; ADR-0015's amendment of 2026-10-09, point 6):
  # As the operating agent,
  # I want a derivation the ledger stops to leave the stored rates in place
  # and to name the booking it stopped at,
  # so that I know the rates arrived and that a re-run finishes the legs.
  #
  # Acceptance criteria:
  # - A booking whose update loses a lock cycle (40P01) stops the
  #   derivation: 200 with the rates' count, settlement_legs {status
  #   "stopped", stopped_at_transaction_id: its id, the counts null}; the
  #   rate is stored, the booking keeps no leg, and the stop is logged.
  # - A second history run, once the booking can be written, completes and
  #   derives its legs (derived 1).
  test "a derivation the ledger stops keeps the rates and names the booking", %{conn: conn} do
    marker = "a lost lock cycle in the history run"
    :ok = LostLockCycle.install!(marker)
    buy = legless_import_buy!(marker)

    Fake.put_history_response(usd_history([~D[2026-01-21]]))

    {response, log} = with_log(fn -> history!(conn, 200) end)

    assert %{"data" => %{"upserted" => 1, "scope" => "history", "settlement_legs" => legs}} =
             response

    assert legs == %{
             "status" => "stopped",
             "derived" => nil,
             "skipped_no_rate" => nil,
             "skipped_changed" => nil,
             "stopped_at_transaction_id" => buy.id
           }

    assert Ledger.get_transaction(buy.id).security_amount == nil
    assert {:ok, _rate} = Portfolixir.Fx.rate_on("USD", "EUR", ~D[2026-01-21])
    assert log =~ "settlement-leg derivation stopped at transaction ##{buy.id}"

    # A re-run derives the rest (review round S3): once the booking can be
    # written again, a second history run completes and derives its legs.
    {:ok, _cleared} =
      Ledger.update_transaction(Actor.owner_ui(), Ledger.get_transaction(buy.id), %{
        notes: "cleared"
      })

    Fake.put_history_response(usd_history([~D[2026-01-21]]))

    assert %{"data" => %{"settlement_legs" => rerun}} = history!(conn, 200)

    assert rerun == %{
             "status" => "completed",
             "derived" => 1,
             "skipped_no_rate" => 0,
             "skipped_changed" => 0,
             "stopped_at_transaction_id" => nil
           }

    assert Decimal.to_string(Ledger.get_transaction(buy.id).settlement_fx_rate) == "0.800000"
  end

  defmodule NoHistoryProvider do
    @moduledoc false
    @behaviour Portfolixir.Fx.RateSync.Provider
    @impl true
    def id, do: :no_history
    @impl true
    def fetch(_opts), do: {:ok, []}
  end

  # Review round: a provider failure is a 502 and a provider without a history
  # is a 422 naming scope — the sync endpoint's error contract carries over.
  test "scope=history answers 502 on a provider failure and 422 without a history", %{conn: conn} do
    Fake.put_history_response({:error, :boom})

    log =
      capture_log(fn ->
        assert %{"errors" => %{"detail" => "the rate provider could not be reached"}} =
                 conn
                 |> api_conn()
                 |> post("/api/v1/exchange_rates/sync", Jason.encode!(%{"scope" => "history"}))
                 |> json_response(502)
      end)

    assert log =~ "fx history fetch failed via #{inspect(Fake)}: :boom"
    assert log =~ "exchange-rate sync failed: :boom"

    previous = Application.get_env(:portfolixir, Portfolixir.Fx.RateSync, [])
    on_exit(fn -> Application.put_env(:portfolixir, Portfolixir.Fx.RateSync, previous) end)

    Application.put_env(
      :portfolixir,
      Portfolixir.Fx.RateSync,
      Keyword.put(previous, :provider, NoHistoryProvider)
    )

    assert %{"errors" => %{"scope" => [message]}} =
             conn
             |> api_conn()
             |> post("/api/v1/exchange_rates/sync", Jason.encode!(%{"scope" => "history"}))
             |> json_response(422)

    assert message =~ "publishes no history"
  end
end
