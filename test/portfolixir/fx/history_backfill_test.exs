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

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Fx
  alias Portfolixir.Fx.HistoryGaps
  alias Portfolixir.Fx.RateSync
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Applier.Result
  alias Portfolixir.Imports.SecurityResolver
  alias Portfolixir.Journal
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.Performance.Contribution
  alias Portfolixir.Portfolios.SecuritiesAccount

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

  # A provider whose id/0 raises: every store of what it fetched raises past
  # the fetch's own rescue, as nothing else in the path can.
  defmodule CrashingFeed do
    @moduledoc false
    @behaviour Portfolixir.Fx.RateSync.Provider

    @impl true
    def id, do: raise("synthetic provider failure")

    @impl true
    def fetch(_opts), do: {:ok, []}

    @impl true
    def fetch_history(_opts) do
      {:ok,
       [
         %{
           base_currency: "EUR",
           quote_currency: "USD",
           date: ~D[2022-03-14],
           rate: "1.25",
           source: "ecb"
         }
       ]}
    end
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

    # The α closing act, coverage: the info line a completed run writes.
    test "a completed run logs the currencies it sought and the rates it stored" do
      booked!("USD", "500", ~D[2022-03-15], "Dollar")
      previous = Logger.level()
      Logger.configure(level: :info)
      on_exit(fn -> Logger.configure(level: previous) end)

      log =
        capture_log([level: :info], fn ->
          assert {:ok, %{sought: ["USD"]}} =
                   RateSync.backfill_when_needed(
                     provider: HistoryFeed,
                     test_pid: self(),
                     history: {:ok, [row("USD", ~D[2022-03-14], "1.25")]}
                   )
        end)

      assert log =~ "fx history backfill ran by itself for USD: 1 rate(s) stored"
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

      # #1196 (ADR-0015's amendment of 2026-10-09, point 6): the run that
      # stored the rates derived the legs the import could not store.
      assert stored_legs(buy) == {"800.000000", "1000.000000", "0.800000"}

      assert %{settlement_legs: %{status: :completed, derived: 1, skipped_no_rate: 0}} =
               elem(run, 1)

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

  # -- #1196: the legs after a history backfill ------------------------------

  # Identity 6's file, as Portfolio Performance's CSV export writes it: two
  # dollar shares bought from a euro account on 2024-10-01, each settled
  # 800.00 EUR with fees 5.00 and taxes 1.00 EUR (cash 806.00), the second
  # priced at a Kurs PP rounded (7 x 114.29 = 800.03).
  defp identity_six_csv(cash, depot) do
    """
    Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle
    2024-10-01 10:00:00;Kauf;Examplia Robotics Corp.;10;80,00;800,00;5,00;1,00;806,00;#{depot};#{cash};;
    2024-10-01 11:00:00;Kauf;Examplia Robotics Corp.;7;114,29;800,00;5,00;1,00;806,00;#{depot};#{cash};;
    """
  end

  defp import_identity_six!(security, cash, depot) do
    {:ok, preview} =
      Imports.parse_portfolio_performance(identity_six_csv(cash, depot), filename: "#{cash}.csv")

    assert preview.errors == []
    key = SecurityResolver.key(SecurityResolver.effective_ref(hd(preview.entries)))

    assert {:ok, %Result{created_transactions: 2}} =
             Imports.apply(preview, %{
               cash_accounts: %{cash => {:create, cash}},
               depots: %{depot => %{target: {:create, depot}, cash: cash}},
               security_mappings: %{key => {:existing, security.id}}
             })

    cash_account = Repo.one!(from(c in CashAccount, where: c.name == ^cash))
    depot_account = Repo.one!(from(d in SecuritiesAccount, where: d.name == ^depot))

    buys =
      Repo.all(
        from(t in Transaction,
          where: t.cash_account_id == ^cash_account.id and t.type == "buy",
          order_by: [desc: t.quantity]
        )
      )

    {cash_account, depot_account, buys}
  end

  defp legs(%Transaction{} = transaction) do
    {transaction.settlement_amount, transaction.security_amount, transaction.settlement_fx_rate}
  end

  # The three legs as the database stores them, at its scale of six places.
  defp stored_legs(%Transaction{} = transaction) do
    transaction
    |> legs()
    |> Tuple.to_list()
    |> Enum.map(&(&1 && Decimal.to_string(&1)))
    |> List.to_tuple()
  end

  defp reload_legs(transactions), do: Enum.map(transactions, &legs(Repo.get!(Transaction, &1.id)))

  defp journal_entries(transactions) do
    ids = Enum.map(transactions, &to_string(&1.id))

    Repo.all(
      from(e in Journal.Entry,
        where: e.resource_type == "transaction" and e.resource_id in ^ids,
        order_by: [asc: e.id]
      )
    )
  end

  # User story (#1196, Sprint 21 α2; ADR-0015's amendment of 2026-10-09,
  # point 6 and identity 6):
  # As the switcher whose fresh instance imported dollar shares bought from
  # a euro account before any rate was stored,
  # I want the run that stores the history to derive the settlement legs
  # those rates make derivable, in the same single-flight run, journaled
  # under a system actor,
  # so that my first import's trades carry the legs a later import would
  # have stored, without my running a task, and nothing else is rewritten.
  #
  # Acceptance criteria:
  # - Imported with no rate stored, the two buys keep no legs. The history
  #   run (1 EUR = 1.25 USD) derives them: 800.00 EUR, 1,000.00 USD and
  #   0.800000 for each, the rounded row's read off its cash, not off 7 x
  #   114.29 = 800.03; each derivation is journaled under the system actor
  #   `settlement_backfill`. The run answers its counts: 2 derived, 0
  #   skipped for a missing rate.
  # - Field for field, the derived legs equal what the same file stores
  #   when the rate is there before the import.
  # - A booking-form sale with its legs, the rows that got their legs when
  #   imported, and a stored third-currency row with a rate and no
  #   security_amount are not touched: no journal entry, no field changed.
  # - A manual backfill run afterwards derives nothing and answers 0.
  describe "the legs after a history backfill (identity 6)" do
    test "the run that stores the rates derives a first import's legs, as an import stores them" do
      fresh_instance!()

      {:ok, security} =
        Catalog.create_security(Actor.owner_ui(), %{
          name: "Examplia Robotics Corp.",
          ticker_symbol: "EXRB",
          currency_code: "USD",
          asset_class: "equity"
        })

      {cash, depot, [first, rounded] = fresh_buys} =
        import_identity_six!(security, "Giro", "Depot")

      assert reload_legs(fresh_buys) == [{nil, nil, nil}, {nil, nil, nil}]

      # Identity 1's booking-form sale, its legs beside it.
      {:ok, sale} =
        Ledger.create_transaction(Actor.owner_ui(), %{
          portfolio_id: cash.portfolio_id,
          securities_account_id: depot.id,
          cash_account_id: cash.id,
          security_id: security.id,
          type: "sell",
          date: ~D[2024-10-02],
          quantity: "10",
          price: "120",
          fees: "3.00",
          currency_code: "USD",
          security_amount: "1200.00",
          settlement_amount: "960.00",
          settlement_fx_rate: "0.800000",
          gross_amount: "957.00"
        })

      # A row priced in a third currency, as stored before #1199's check:
      # CHF through the EUR account, its rate and no security_amount.
      {:ok, third_currency} =
        Repo.transaction(fn ->
          Repo.query!("SELECT set_config('portfolixir.journal_actor', 'legacy_row', true)")

          Repo.insert!(%Transaction{
            portfolio_id: cash.portfolio_id,
            securities_account_id: depot.id,
            cash_account_id: cash.id,
            security_id: security.id,
            type: "buy",
            date: ~D[2024-10-01],
            quantity: Decimal.new("1"),
            price: Decimal.new("90.00"),
            fees: Decimal.new("0"),
            taxes: Decimal.new("0"),
            gross_amount: Decimal.new("85.00"),
            currency_code: "CHF",
            settlement_fx_rate: Decimal.new("0.944444")
          })
        end)

      untouched = [sale, third_currency]
      untouched_legs = reload_legs(untouched)
      untouched_journal = journal_entries(untouched)

      series = {:ok, [row("CHF", ~D[2024-09-30], "0.90") | usd_series()]}

      assert {:ok, %{scope: :history, settlement_legs: counts}} =
               RateSync.backfill_when_needed(
                 provider: HistoryFeed,
                 test_pid: self(),
                 history: series
               )

      assert counts == %{status: :completed, derived: 2, skipped_no_rate: 0}

      for buy <- fresh_buys do
        assert stored_legs(Repo.get!(Transaction, buy.id)) ==
                 {"800.000000", "1000.000000", "0.800000"}
      end

      for buy <- [first, rounded] do
        assert [%{actor_type: :system_job, actor_label: "settlement_backfill"}] =
                 journal_entries([buy]) |> Enum.filter(&(&1.operation == :update))
      end

      assert reload_legs(untouched) == untouched_legs
      assert journal_entries(untouched) == untouched_journal

      # The same file, imported with the rate already stored, stores the
      # same legs, field for field.
      {_cash, _depot, imported_buys} = import_identity_six!(security, "Giro Zwei", "Depot Zwei")
      assert reload_legs(imported_buys) == reload_legs(fresh_buys)

      # A manual run derives nothing more and journals nothing.
      settled = untouched ++ fresh_buys ++ imported_buys
      settled_journal = journal_entries(settled)

      assert {:ok, %{settlement_legs: %{status: :completed, derived: 0, skipped_no_rate: 0}}} =
               RateSync.backfill(provider: HistoryFeed, history: series)

      assert journal_entries(settled) == settled_journal
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

    # The α closing act, coverage: the scheduler's later ticks, and a run
    # that raises past the provider's own rescue.
    test "a later tick fetches the day's rates and, disabled, schedules no next one" do
      scheduled!(false, daily: {:ok, []})

      pid =
        start_supervised!(
          {RateSync,
           [name: :fx_history_tick, enabled?: false, interval_ms: 50, provider: HistoryFeed]}
        )

      send(pid, :tick)
      assert_receive {:fetched, :daily, _provider}, 2_000
      refute_receive {:fetched, :daily, _provider}, 200
      assert Process.alive?(pid)
    end

    test "a boot whose sync and history run raise logs both and stays up" do
      booked!("USD", "500", ~D[2022-03-15], "Dollar")

      log =
        capture_log(fn ->
          pid =
            start_supervised!(
              {RateSync,
               [
                 name: :fx_history_crash,
                 enabled?: true,
                 startup_delay_ms: 0,
                 provider: CrashingFeed,
                 notify: self()
               ]}
            )

          assert await_history_run() == {:error, :crashed}
          assert Process.alive?(pid)
        end)

      assert log =~ "fx rate sync tick crashed: synthetic provider failure"
      assert log =~ "fx history backfill crashed: synthetic provider failure"
      assert HistoryGaps.sought() == []
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
