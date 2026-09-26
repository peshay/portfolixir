defmodule Portfolixir.Catalog.QuoteEnrichmentTest do
  # E25 S3, G04 (#888): the quote backfill every created security starts runs
  # through one serial, deduplicating worker — the one the import path uses —
  # instead of one unbounded task per create, and a sync of one security, or
  # the FX backfill, runs at most once at a time: a second request while one
  # runs answers 409.
  use PortfolixirWeb.ConnCase, async: false

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.QuoteEnrichment
  alias Portfolixir.Catalog.QuoteSync
  alias Portfolixir.Fx.RateSync

  defmodule BlockingQuoteAdapter do
    @moduledoc false
    @behaviour Portfolixir.Catalog.QuoteSync.Provider

    @impl true
    def id, do: :blocking

    @impl true
    def fetch(_security, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:fetching, self()})

      receive do
        :release -> {:ok, []}
      end
    end
  end

  defmodule BlockingRateProvider do
    @moduledoc false
    @behaviour Portfolixir.Fx.RateSync.Provider

    @impl true
    def id, do: :blocking

    @impl true
    def fetch(_opts), do: {:ok, []}

    @impl true
    def fetch_history(opts) do
      send(Keyword.fetch!(opts, :test_pid), {:fetching, self()})

      receive do
        :release -> {:ok, []}
      end
    end
  end

  defp security!(name, ticker) do
    {:ok, security} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: name,
        currency_code: "USD",
        provider: "coingecko",
        ticker_symbol: ticker,
        asset_class: "crypto"
      })

    security
  end

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  # A sync function that reports when it starts and waits for the test to let
  # it finish, so the test decides how long each enrichment is in flight.
  defp controlled_sync(test_pid) do
    fn id ->
      send(test_pid, {:started, id, self()})

      receive do
        :go -> send(test_pid, {:finished, id})
      end
    end
  end

  defp finish(expected_id) do
    assert_receive {:started, ^expected_id, pid}, 2_000
    refute_receive {:started, _, _}, 50
    send(pid, :go)
    assert_receive {:finished, ^expected_id}, 2_000
  end

  # User story:
  # As an operator whose agent creates securities one call after another,
  # I want each new security's quote backfill queued behind the others, one at
  # a time, and a security already waiting not queued twice,
  # so that a burst of creates cannot open a burst of provider requests and
  # database connections.
  #
  # Acceptance criteria:
  # - However many enrichments are requested at once, at most one runs.
  # - An id already queued or running is not queued again.
  # - Every requested id is enriched once, in order.
  test "the worker runs one enrichment at a time and queues an id once" do
    name = :"quote_enrichment_#{System.unique_integer([:positive])}"
    start_supervised!({QuoteEnrichment, name: name, sync: controlled_sync(self())})

    QuoteEnrichment.enqueue([1, 2, 3], name)
    assert_receive {:started, 1, first}, 2_000

    1..4
    |> Enum.map(fn _ -> Task.async(fn -> QuoteEnrichment.enqueue([2, 3, 1, 4], name) end) end)
    |> Task.await_many()

    refute_receive {:started, _, _}, 50
    send(first, :go)
    assert_receive {:finished, 1}, 2_000

    for id <- [2, 3, 4], do: finish(id)
    refute_receive {:started, _, _}, 100
  end

  # Acceptance criteria:
  # - Securities created concurrently with quote enrichment on keep at most
  #   one enrichment in flight, and each is enriched.
  test "concurrent creates keep at most one enrichment in flight" do
    previous = Application.get_env(:portfolixir, QuoteSync, [])
    Application.put_env(:portfolixir, QuoteSync, Keyword.put(previous, :enabled?, true))
    Application.put_env(:portfolixir, QuoteEnrichment, sync: controlled_sync(self()))

    on_exit(fn ->
      Application.put_env(:portfolixir, QuoteSync, previous)
      Application.delete_env(:portfolixir, QuoteEnrichment)
    end)

    ids =
      1..4
      |> Enum.map(fn n ->
        Task.async(fn -> security!("Synthetic Coin #{n}", "SYN#{n}").id end)
      end)
      |> Task.await_many()

    started =
      for _ <- ids do
        assert_receive {:started, id, pid}, 2_000
        refute_receive {:started, _, _}, 50
        send(pid, :go)
        assert_receive {:finished, ^id}, 2_000
        id
      end

    assert Enum.sort(started) == Enum.sort(ids)
  end

  # User story:
  # As the operator or the agent asking for one security's quotes,
  # I want a second sync of the same security answered as "already running"
  # while the first runs,
  # so that repeated clicks or calls do not stack provider requests.
  #
  # Acceptance criteria:
  # - While a sync of a security runs, POST .../sync_quotes for it answers 409
  #   and makes no provider call; once it finished, the next one runs.
  test "a second sync of the same security answers 409 while one runs", %{conn: conn} do
    security = security!("Synthetic Busy Coin", "SYNB")
    test_pid = self()

    first =
      Task.async(fn ->
        QuoteSync.sync_security(security,
          adapter_for: %{"coingecko" => BlockingQuoteAdapter},
          test_pid: test_pid
        )
      end)

    assert_receive {:fetching, adapter}, 2_000

    busy = conn |> api_conn() |> post("/api/v1/securities/#{security.id}/sync_quotes")
    assert %{"errors" => %{"detail" => _}} = json_response(busy, 409)

    send(adapter, :release)
    assert %{status: :ok} = Task.await(first)

    free = build_conn() |> api_conn() |> post("/api/v1/securities/#{security.id}/sync_quotes")
    assert %{"data" => %{"status" => _}} = json_response(free, 200)
  end

  # Acceptance criteria:
  # - While the FX backfill runs, a second one answers 409; once it finished,
  #   the next one runs.
  test "a second FX backfill answers 409 while one runs", %{conn: conn} do
    # The configured test provider answers the second, free backfill.
    Code.ensure_loaded!(Portfolixir.Fx.RateSync.Fake)
    test_pid = self()

    first =
      Task.async(fn -> RateSync.backfill(provider: BlockingRateProvider, test_pid: test_pid) end)

    assert_receive {:fetching, provider}, 2_000

    busy = conn |> api_conn() |> post("/api/v1/exchange_rates/sync?scope=history")
    assert %{"errors" => %{"detail" => _}} = json_response(busy, 409)

    send(provider, :release)
    assert {:ok, %{upserted: 0}} = Task.await(first)

    free = build_conn() |> api_conn() |> post("/api/v1/exchange_rates/sync?scope=history")
    assert %{"data" => _} = json_response(free, 200)
  end
end
