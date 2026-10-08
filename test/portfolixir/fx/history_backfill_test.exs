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
  import Portfolixir.WorldFixtures, only: [base_world: 1, deposit!: 4, put_quote!: 3]

  alias Portfolixir.Fx
  alias Portfolixir.Fx.HistoryGaps
  alias Portfolixir.Fx.RateSync
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Applier.Result
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.Performance.Contribution

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
  # - A fetch that answers with no rates is such a failed run too: nothing
  #   is recorded, and the next run fetches again (found by the α closing
  #   act).
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

    test "an empty series records nothing, and the next run fetches again" do
      booked!("USD", "500", ~D[2022-03-15], "Dollar")

      log =
        capture_log(fn ->
          assert {:error, :empty_history} =
                   RateSync.backfill_when_needed(
                     provider: HistoryFeed,
                     test_pid: self(),
                     history: {:ok, []}
                   )
        end)

      assert log =~ "fx history fetch via #{inspect(HistoryFeed)} returned no rates"
      assert HistoryGaps.sought() == []
      assert HistoryGaps.due() == %{"USD" => ~D[2022-03-15]}

      assert {:ok, %{sought: ["USD"], upserted: 1}} =
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

      # The manual run stored no rate, so the dollar is still due; this
      # series closes it.
      closing = Keyword.put(feed, :history, {:ok, [row("USD", ~D[2022-03-14], "1.25")]})
      automatic = Task.async(fn -> RateSync.backfill_when_needed(closing) end)
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

  # -- the triggers: after an import apply, after the boot sync ---------------

  @today ~D[2026-09-30]

  # A switcher's two-year history in dollars, as Portfolio Performance's JSON
  # export writes it: 10,000 USD paid into "Broker USD" on 2024-10-01 and
  # 10 shares of a dollar-priced share bought from it the same day at
  # 100 USD.
  @usd_history """
  {
    "version": 1,
    "transactions": [
      {"type": "DEPOSIT", "account": "Broker USD", "date": "2024-10-01",
       "time": "09:00", "currency": "USD", "amount": 10000.00},
      {"type": "PURCHASE", "account": "Broker USD", "portfolio": "Depot USD",
       "date": "2024-10-01", "time": "10:00", "currency": "USD",
       "amount": 1000.00, "shares": 10.0,
       "security": {"name": "Examplia Robotics Corp.", "ticker": "EXRB",
                    "currency": "USD"}}
    ]
  }
  """

  # The ECB's series as the fake serves it: EUR/USD 1.25 from 2024-09-30
  # (1 USD = 0.80 EUR), 1.0 from 2025-09-30, 1.6 from 2026-09-29
  # (1 USD = 0.625 EUR). Every reciprocal terminates, so every figure below
  # is exact (ADR-0051, I1).
  @usd_series [
    {~D[2024-09-30], "1.25"},
    {~D[2025-09-30], "1.0"},
    {~D[2026-09-29], "1.6"}
  ]

  # The same switcher's share bought from a euro account, as Portfolio
  # Performance's JSON export writes it and the import books it (ADR-0033):
  # 1,000.00 EUR paid into "Giro" on 2024-10-01 and 10 shares of the
  # dollar-priced share bought from it the same day for 800.00 EUR, booked
  # in EUR (100 USD a share at 0.80 EUR).
  @eur_account_history """
  {
    "version": 1,
    "transactions": [
      {"type": "DEPOSIT", "account": "Giro", "date": "2024-10-01",
       "time": "09:00", "currency": "EUR", "amount": 1000.00},
      {"type": "PURCHASE", "account": "Giro", "portfolio": "Depot",
       "date": "2024-10-01", "time": "10:00", "currency": "EUR",
       "amount": 800.00, "shares": 10.0,
       "security": {"name": "Examplia Robotics Corp.", "ticker": "EXRB",
                    "currency": "USD"}}
    ]
  }
  """

  defp usd_series, do: Enum.map(@usd_series, fn {date, rate} -> row("USD", date, rate) end)

  # A fresh instance's boot sync stored the day's rate before anything was
  # imported: EUR/USD 1.6 on 2026-09-29, the only USD rate it holds.
  defp fresh_instance! do
    {:ok, 1} = Fx.upsert_many([row("USD", ~D[2026-09-29], "1.6")])
    :ok
  end

  # The Imports page's apply: no portfolio chosen (the internal default one,
  # ADR-0024), the file's account and depot created under their own names.
  defp import!(body, cash \\ "Broker USD", depot \\ "Depot USD") do
    {:ok, preview} = Imports.parse_portfolio_performance(body, filename: "Dollar.json")
    assert preview.errors == []

    assert {:ok, %Result{created_transactions: created}} =
             Imports.apply(preview, %{
               cash_accounts: %{cash => {:create, cash}},
               depots: %{depot => %{target: {:create, depot}, cash: cash}}
             })

    {Portfolios.first_portfolio(), created}
  end

  # The trigger configuration, as config/{dev,prod,runtime}.exs set it, with
  # this module's fake and the test process told when a background history
  # run ends.
  defp scheduled!(enabled?, feed) do
    previous = Application.get_env(:portfolixir, RateSync, [])
    previous_feed = Application.get_env(:portfolixir, :fx_history_feed)

    on_exit(fn ->
      Application.put_env(:portfolixir, RateSync, previous)

      if previous_feed,
        do: Application.put_env(:portfolixir, :fx_history_feed, previous_feed),
        else: Application.delete_env(:portfolixir, :fx_history_feed)
    end)

    Application.put_env(
      :portfolixir,
      RateSync,
      Keyword.merge(previous, enabled?: enabled?, provider: HistoryFeed, notify: self())
    )

    Application.put_env(:portfolixir, :fx_history_feed, Keyword.put(feed, :test_pid, self()))
  end

  # Waits for a background history run to end and answers its result, or
  # :no_history_run when none ended within the wait.
  defp await_history_run(timeout \\ 5_000) do
    receive do
      {RateSync, :history, result} -> result
    after
      timeout -> :no_history_run
    end
  end

  defp reads(portfolio_id) do
    {:ok, performance} = Performance.for_portfolio(portfolio_id, period: "max", today: @today)
    {:ok, contribution} = Contribution.for_portfolio(portfolio_id, period: "max", today: @today)
    {performance, contribution}
  end

  defp assert_eur(actual, expected, label) do
    assert Decimal.equal?(actual, Decimal.new(expected)),
           "#{label}: expected #{expected}, got #{actual}"
  end

  # The jump #1120 names, as the reads carry it on a history whose rates
  # never arrived: the dollars count zero from 2024-10-01 to 2026-09-28
  # (728 days), and on 2026-09-29 the whole balance, 9,000 USD = 5,625.00
  # EUR, enters the currency effect on cash, and the share, 1,000 USD =
  # 625.00 EUR, its contribution: a result of 6,250.00 EUR, none of it
  # earned. The account is named with the day its first rate came.
  defp assert_first_rate_jump(portfolio_id) do
    {performance, contribution} = reads(portfolio_id)
    [position] = contribution.positions

    assert_eur(
      contribution.remainder.cash_currency_effect,
      "5625",
      "remainder.cash_currency_effect"
    )

    assert_eur(position.contribution, "625", "position.contribution")
    assert_eur(contribution.totals.result, "6250", "totals.result")
    assert_eur(performance.net_external_flows, "0", "performance.net_external_flows")
    assert_eur(performance.end_value, "6250", "performance.end_value")

    for read <- [performance, contribution] do
      assert [account] = read.unvalued_cash_accounts
      assert account.name == "Broker USD"
      assert_eur(account.balance, "9000", "account.balance")
      assert account.unvalued_days == 728
      assert account.first_rate_date == ~D[2026-09-29]
    end
  end

  # User story (#1120; D-1 criterion 2, round trip 3):
  # As a switcher whose fresh instance gets a two-year history with a USD
  # security and a USD cash account,
  # I want the historical rates to arrive without my pressing anything,
  # so that the history is valued from its first day and no first-rate jump
  # sits in the result as a gain I did not make.
  #
  # Acceptance criteria:
  # - After the import's apply, the history backfill runs by itself in the
  #   background (the apply does not wait for it) and stores the fake
  #   provider's series.
  # - The performance and contribution reads over the whole history carry
  #   no jump: the dollars are a flow of 8,000.00 EUR on 2024-10-01, the
  #   currency effect on cash is the balance's real revaluation, -1,575.00
  #   EUR (9,000 USD at 0.80, then 1.00, then 0.625 EUR), the share's
  #   contribution -175.00 EUR, the result -1,750.00 EUR, and
  #   `unvalued_cash_accounts` is empty on both reads.
  # - Before A4 the same reads carried the jump (assert_first_rate_jump/1):
  #   that was this test's red run.
  describe "the round trip (D-1 criterion 2.3)" do
    test "a fresh instance's two-year dollar history is valued from its first day, untouched" do
      fresh_instance!()
      scheduled!(true, history: {:ok, usd_series()})

      {portfolio, 2} = import!(@usd_history)
      run = await_history_run()

      {performance, contribution} = reads(portfolio.id)
      [position] = contribution.positions

      assert_eur(
        contribution.remainder.cash_currency_effect,
        "-1575",
        "remainder.cash_currency_effect"
      )

      assert_eur(position.contribution, "-175", "position.contribution")
      assert_eur(position.net_flows, "800", "position.net_flows")
      assert_eur(position.end_value, "625", "position.end_value")
      assert_eur(contribution.totals.result, "-1750", "totals.result")
      assert contribution.unvalued_cash_accounts == []

      assert_eur(performance.start_value, "0", "performance.start_value")
      assert_eur(performance.net_external_flows, "8000", "performance.net_external_flows")
      assert_eur(performance.end_value, "6250", "performance.end_value")
      assert_eur(performance.ttwror, "-0.21875", "performance.ttwror")
      assert performance.unvalued_cash_accounts == []

      assert {:ok, %{scope: :history, upserted: 3, sought: ["USD"]}} = run
      assert_received {:fetched, :history, _provider}
      assert HistoryGaps.open() == %{}
    end

    # #1120's position half (found by the α closing act): the import books
    # a dollar share bought from a euro account in EUR (ADR-0033), so
    # neither the booking's currency nor its account's names the dollar the
    # position is valued in. Before HistoryGaps read the security's
    # currency, no run was due (`:not_needed`), the position counted zero
    # for 728 days (`unvalued_reason: :no_rate`) and entered at 625.00 EUR
    # on the first rate's day: TTWROR +3.125 from a value of 200.00 EUR.
    test "a dollar share bought from a euro account is valued from its first day, untouched" do
      fresh_instance!()
      scheduled!(true, history: {:ok, usd_series()})

      {portfolio, 2} = import!(@eur_account_history, "Giro", "Depot")
      run = await_history_run()

      [%{security_id: security_id} = buy] =
        Enum.filter(Ledger.list_transactions(portfolio_id: portfolio.id), &(&1.type == "buy"))

      assert buy.currency_code == "EUR"
      assert_eur(buy.price, "80", "buy.price")
      put_quote!(security_id, ~D[2024-10-01], "100")

      {performance, contribution} = reads(portfolio.id)
      [position] = contribution.positions

      assert position.unvalued_days == 0
      assert position.unvalued_reason == nil
      assert_eur(position.net_flows, "800", "position.net_flows")
      assert_eur(position.end_value, "625", "position.end_value")
      assert_eur(position.contribution, "-175", "position.contribution")
      assert_eur(contribution.remainder.cash_currency_effect, "0", "cash_currency_effect")
      assert_eur(contribution.totals.result, "-175", "totals.result")

      # 1,000.00 EUR on 2024-10-01 (200.00 cash, 10 x 100 USD at 0.80),
      # 825.00 EUR on the last day (200.00 cash, 10 x 100 USD at 0.625).
      assert_eur(performance.net_external_flows, "1000", "performance.net_external_flows")
      assert_eur(performance.end_value, "825", "performance.end_value")
      assert_eur(performance.ttwror, "-0.175", "performance.ttwror")

      assert {:ok, %{scope: :history, upserted: 3, sought: ["USD"]}} = run
      assert HistoryGaps.open() == %{}
    end
  end

  # User story (#1120, D-5):
  # As an operator,
  # I want the history backfill to run by itself after the boot sync and
  # after an import, at most once for a gap no fetch can close, never with
  # background fetches off, and quietly when the provider cannot be reached,
  # so that the instance calls out only when a booking needs it and only
  # when I allowed it to.
  #
  # Acceptance criteria:
  # - The boot sync fetches the day's rates, then the history when a
  #   booking predates its currency's rates.
  # - A currency the provider does not publish (TWD) is sought once: a
  #   second boot and a later import ask the provider for no history.
  # - With background fetches off (PORTFOLIXIR_BACKGROUND_FETCH=off sets
  #   the scheduler's enabled? to false, release_background_fetch_test.exs),
  #   neither the boot nor an import asks the provider anything, and the
  #   reads keep today's note and figures.
  # - Without a network the import still applies, the backfill fails
  #   quietly (a warning in the log), and the reads keep today's note.
  describe "the triggers" do
    test "the boot sync fetches the history after the day's rates, and only once" do
      booked!("TWD", "9000", ~D[2024-04-01], "Taiwan")

      scheduled!(true,
        daily: {:ok, [row("USD", ~D[2026-09-29], "1.6")]},
        history: {:ok, usd_series()}
      )

      boot = [enabled?: true, startup_delay_ms: 0, provider: HistoryFeed, notify: self()]

      start_supervised!({RateSync, Keyword.put(boot, :name, :fx_history_first_boot)})

      assert_receive {:fetched, :daily, _provider}, 2_000
      assert_receive {:fetched, :history, _provider}, 2_000
      assert {:ok, %{sought: ["TWD"], upserted: 3}} = await_history_run()
      stop_supervised!(:fx_history_first_boot)

      start_supervised!({RateSync, Keyword.put(boot, :name, :fx_history_second_boot)})

      assert_receive {:fetched, :daily, _provider}, 2_000
      assert await_history_run() == :not_needed
      stop_supervised!(:fx_history_second_boot)

      {_portfolio, 2} = import!(@usd_history)

      assert await_history_run() == :not_needed
      refute_received {:fetched, :history, _provider}
      assert HistoryGaps.open() == %{"TWD" => ~D[2024-04-01]}
    end

    test "with background fetches off, neither the boot nor an import asks the provider" do
      fresh_instance!()
      scheduled!(false, daily: {:ok, []}, history: {:ok, usd_series()})

      config = Application.get_env(:portfolixir, RateSync)

      start_supervised!(
        {RateSync, Keyword.merge(config, name: :fx_history_off, startup_delay_ms: 0)}
      )

      {portfolio, 2} = import!(@usd_history)

      assert await_history_run(500) == :no_history_run
      refute_received {:fetched, _feed, _provider}
      assert HistoryGaps.due() == %{"USD" => ~D[2024-10-01]}
      assert_first_rate_jump(portfolio.id)
    end

    test "without a network the import applies and the backfill fails quietly" do
      fresh_instance!()
      scheduled!(true, history: {:error, %Req.TransportError{reason: :econnrefused}})

      {{portfolio, 2}, log} =
        with_log(fn ->
          imported = import!(@usd_history)
          assert {:error, %Req.TransportError{reason: :econnrefused}} = await_history_run()
          imported
        end)

      assert log =~ "fx history fetch failed via #{inspect(HistoryFeed)}"
      assert HistoryGaps.sought() == []
      assert_first_rate_jump(portfolio.id)
    end
  end
end
