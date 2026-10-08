defmodule Portfolixir.Fx.HistoryBackfillTest do
  # #1120 (Sprint 20 PR α, A4; the plan's D-5): the one-shot backfill of the
  # historical exchange rates runs by itself, once, when needed, through
  # the existing SingleFlight path. No test here reaches a network: the
  # provider is the in-module HistoryFeed fake. Invented names, figures and
  # dates only.
  #
  # async: false -- the guard's record is one settings row, and the
  # triggers' background tasks share the sandbox connection.
  use Portfolixir.DataCase, async: false

  import ExUnit.CaptureLog
  import Portfolixir.WorldFixtures, only: [base_world: 1, deposit!: 4]

  alias Portfolixir.Fx
  alias Portfolixir.Fx.HistoryGaps
  alias Portfolixir.Fx.RateSync

  # A fake rate provider: it reports each fetch to the test process and
  # answers what the call's options, or the application environment for a
  # call the test cannot hand options to, say. With `block: true` it waits
  # for :release before answering.
  defmodule HistoryFeed do
    @moduledoc false
    @behaviour Portfolixir.Fx.RateSync.Provider

    @impl true
    def id, do: :history_feed

    @impl true
    def fetch(opts), do: answer(:daily, opts)

    @impl true
    def fetch_history(opts), do: answer(:history, opts)

    defp answer(feed, opts) do
      opts = Keyword.merge(Application.get_env(:portfolixir, :fx_history_feed, []), opts)

      if pid = opts[:test_pid], do: send(pid, {:fetched, feed, self()})

      if opts[:block] do
        receive do
          :release -> :ok
        end
      end

      Keyword.get(opts, feed, {:ok, []})
    end
  end

  defmodule DailyOnly do
    @moduledoc false
    @behaviour Portfolixir.Fx.RateSync.Provider
    @impl true
    def id, do: :daily_only
    @impl true
    def fetch(_opts), do: {:ok, []}
  end

  defp row(quote_currency, date, rate) do
    %{base_currency: "EUR", quote_currency: quote_currency, date: date, rate: rate, source: "ecb"}
  end

  defp booked!(currency, amount, date, name) do
    world = base_world(name: name, cash_currency: currency, cash_name: "Konto #{currency}")
    deposit!(world, amount, date, currency: currency)
    world
  end

  defp history_fetches do
    receive do
      {:fetched, :history, _provider} -> 1 + history_fetches()
    after
      0 -> 0
    end
  end

  # User story (#1120, D-5):
  # As an operator who imported years of history in a foreign currency,
  # I want the historical rates fetched when a booking needs them, once,
  # and never beside a backfill I started by hand,
  # so that the history is valued from its first day without my pressing
  # anything, and the instance does not fetch the series again for a gap
  # no fetch can close.
  #
  # Acceptance criteria:
  # - Nothing due: :not_needed, and the provider is not asked.
  # - Something due: the provider's series is stored through the backfill's
  #   own path, and the run answers what it sought.
  # - "Once": a currency the provider does not publish (TWD) and a booking
  #   before the series (USD in 1998) stay open after a completed run, and
  #   the next run asks the provider nothing.
  # - Without a network the run fails quietly (a warning in the log, an
  #   error tuple, no raise), records nothing, and the next run tries again.
  # - It shares the manual backfill's single-flight key: while either runs,
  #   the other answers {:error, :backfill_in_progress} and asks nothing.
  # - A provider without a history answers {:error, :history_unsupported}.
  describe "backfill_when_needed/1" do
    test "asks the provider nothing when no booking predates its currency's rates" do
      booked!("USD", "500", ~D[2022-03-15], "Dollar")

      {:ok, _} = Fx.upsert_many([row("USD", ~D[2022-03-14], "1.25")])

      assert RateSync.backfill_when_needed(provider: HistoryFeed, test_pid: self()) ==
               :not_needed

      assert history_fetches() == 0
    end

    test "fetches the series once, and not again for a gap no fetch can close" do
      booked!("CHF", "800", ~D[2022-03-15], "Franken")
      booked!("TWD", "9000", ~D[2022-04-01], "Taiwan")
      booked!("USD", "500", ~D[1998-12-28], "Dollar")

      {:ok, _} = Fx.upsert_many([row("CHF", ~D[2026-09-29], "0.8")])

      series =
        {:ok,
         [
           row("CHF", ~D[2022-03-14], "1.0"),
           row("USD", ~D[1999-01-04], "1.25"),
           row("CHF", ~D[2026-09-29], "0.8")
         ]}

      assert HistoryGaps.due() == %{
               "CHF" => ~D[2022-03-15],
               "TWD" => ~D[2022-04-01],
               "USD" => ~D[1998-12-28]
             }

      assert {:ok, %{scope: :history, upserted: 3, sought: ["CHF", "TWD", "USD"]}} =
               RateSync.backfill_when_needed(
                 provider: HistoryFeed,
                 test_pid: self(),
                 history: series
               )

      assert history_fetches() == 1
      assert {:ok, rate} = Fx.rate_on("CHF", "EUR", ~D[2022-03-14])
      assert Decimal.equal?(rate, Decimal.new("1"))

      # CHF is closed; TWD (unpublished) and USD (before the series) stay open.
      assert HistoryGaps.open() == %{"TWD" => ~D[2022-04-01], "USD" => ~D[1998-12-28]}
      assert HistoryGaps.due() == %{}

      for _boot_or_import <- 1..3 do
        assert RateSync.backfill_when_needed(
                 provider: HistoryFeed,
                 test_pid: self(),
                 history: series
               ) == :not_needed
      end

      assert history_fetches() == 0
    end

    test "fails quietly without a network, records nothing, and tries again next time" do
      booked!("USD", "500", ~D[2022-03-15], "Dollar")
      unreachable = {:error, %Req.TransportError{reason: :econnrefused}}

      log =
        capture_log(fn ->
          assert {:error, %Req.TransportError{reason: :econnrefused}} =
                   RateSync.backfill_when_needed(
                     provider: HistoryFeed,
                     test_pid: self(),
                     history: unreachable
                   )
        end)

      assert log =~ "fx history fetch failed via #{inspect(HistoryFeed)}"
      assert HistoryGaps.sought() == []
      assert HistoryGaps.due() == %{"USD" => ~D[2022-03-15]}

      assert {:ok, %{sought: ["USD"]}} =
               RateSync.backfill_when_needed(
                 provider: HistoryFeed,
                 test_pid: self(),
                 history: {:ok, [row("USD", ~D[2022-03-14], "1.25")]}
               )

      assert history_fetches() == 2
      assert HistoryGaps.open() == %{}
    end

    test "never runs beside a manual backfill, either way round" do
      booked!("USD", "500", ~D[2022-03-15], "Dollar")
      test_pid = self()
      feed = [provider: HistoryFeed, test_pid: test_pid, block: true]

      manual = Task.async(fn -> RateSync.backfill(feed) end)
      assert_receive {:fetched, :history, provider}, 2_000

      assert RateSync.backfill_when_needed(provider: HistoryFeed, test_pid: test_pid) ==
               {:error, :backfill_in_progress}

      send(provider, :release)
      assert {:ok, %{scope: :history}} = Task.await(manual)
      assert history_fetches() == 0

      automatic = Task.async(fn -> RateSync.backfill_when_needed(feed) end)
      assert_receive {:fetched, :history, provider}, 2_000

      assert RateSync.backfill(provider: HistoryFeed, test_pid: test_pid) ==
               {:error, :backfill_in_progress}

      send(provider, :release)
      assert {:ok, %{sought: ["USD"]}} = Task.await(automatic)
      assert history_fetches() == 0
    end

    test "answers a provider without a history and records nothing" do
      booked!("USD", "500", ~D[2022-03-15], "Dollar")

      assert RateSync.backfill_when_needed(provider: DailyOnly) ==
               {:error, :history_unsupported}

      assert HistoryGaps.sought() == []
    end
  end
end
