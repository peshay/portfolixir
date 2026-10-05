defmodule Portfolixir.Portfolios.PerformanceUnvaluedCashTest do
  # #1055 (Sprint 19 PR α, M3; ADR-0051 §10 and its 2026-10-03 amendment;
  # board J2, pick A): a foreign-currency cash balance the walk counts zero
  # for want of a rate path is named on the performance and the
  # contribution reads, instead of reaching the currency effect unnamed.
  # Invented names, figures and dates only.
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, deposit!: 3, deposit!: 4]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.Performance.Contribution

  @today ~D[2026-09-30]

  # The keys each read answered before #1055: the list is the only addition.
  @performance_keys ~w(as_of base_currency computation_basis end_date end_value
                       invested_capital irr mwr net_external_flows period
                       portfolio_id series start_date start_value stale
                       suspect_dates ttwror view_id wealth_multiple)a

  @contribution_keys ~w(as_of base_currency computation_basis end_date period
                        portfolio_id positions remainder start_date stale totals
                        view_id)a

  @point_keys [:basis, :date, :flow, :trade_costs, :value]

  defp rate!(quote_currency, date, rate) do
    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: quote_currency,
          date: date,
          rate: rate,
          source: "manual"
        }
      ])
  end

  defp franc_account!(portfolio, name) do
    {:ok, account} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: name,
        currency_code: "CHF"
      })

    %{portfolio: portfolio, cash: account}
  end

  defp removal!(%{portfolio: portfolio, cash: cash}, amount, date) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        type: "removal",
        date: date,
        gross_amount: amount,
        currency_code: cash.currency_code
      })

    tx
  end

  # Board J2's data, in this test's figures. A EUR portfolio with a Giro in
  # EUR and a "Tagesgeld CHF":
  #
  #   2026-07-01  deposit 1000 EUR into the Giro
  #   2026-07-14  deposit 2000 CHF into Tagesgeld CHF
  #   2026-08-01  CHF's first stored rate, EUR/CHF 0.8 (1 CHF = 1.25 EUR)
  #
  # The walk counts the CHF balance zero from 07-14 to 07-31 (18 days) and
  # at 2500 EUR from 08-01, so the money result of the whole history is
  # 3500 − 0 − 1000 = 2500, all of it in the currency effect on cash.
  defp franc_world(name \\ "Franc World") do
    world = base_world(name: name, cash_name: "Giro", depot_name: "Depot")
    franc = franc_account!(world.portfolio, "Tagesgeld CHF")
    deposit!(world, "1000", ~D[2026-07-01])
    deposit!(franc, "2000", ~D[2026-07-14], currency: "CHF")
    rate!("CHF", ~D[2026-08-01], "0.8")
    Map.merge(world, %{franc: franc})
  end

  defp equal?(decimal, expected), do: Decimal.equal?(decimal, Decimal.new(expected))

  # An entry with its balance checked apart, so a stored scale never matters.
  defp entry!(list, account, balance) do
    entry = Enum.find(list, &(&1.cash_account_id == account.id))
    assert entry, "#{account.name} is not listed"
    assert equal?(entry.balance, balance), "#{account.name}: #{entry.balance}"
    Map.delete(entry, :balance)
  end

  defp reads(pid, period) do
    {:ok, performance} = Performance.for_portfolio(pid, period: period, today: @today)
    {:ok, contribution} = Contribution.for_portfolio(pid, period: period, today: @today)
    [performance: performance, contribution: contribution]
  end

  # User story (#1055, ADR-0051 §10, board J2 A):
  # As a local portfolio maintainer who paid money into a CHF account before
  # the instance held any CHF rate,
  # I want both period reads to name that account, with its balance in its
  # own currency, the days it counted zero and the date its first rate came,
  # so that the jump in the currency effect on cash reads as a deposit that
  # became visible, not as a currency gain.
  #
  # Acceptance criteria:
  # - The performance read and the contribution read of the window both carry
  #   `unvalued_cash_accounts`: the account's id, name, currency code, native
  #   balance, 18 unvalued days, the reason `:no_rate` and the first rate's
  #   date, 2026-08-01, which falls inside the window.
  # - Every figure is unchanged: start and end value, flows, TTWROR, the
  #   currency effect on cash and the result; every key either read answered
  #   before is still there, and the list is the only key added.
  # - The walk records the account per day only on the days it counted zero;
  #   every other point keeps its shape, and the analysis names the account
  #   and its currency's first rate date.
  test "a balance held before its currency's first rate is named on both reads" do
    world = franc_world()
    pid = world.portfolio.id
    [performance: performance, contribution: contribution] = reads(pid, "max")

    expected = %{
      cash_account_id: world.franc.cash.id,
      name: "Tagesgeld CHF",
      currency_code: "CHF",
      unvalued_days: 18,
      unvalued_reason: :no_rate,
      first_rate_date: ~D[2026-08-01]
    }

    for read <- [performance, contribution] do
      assert [_one] = read.unvalued_cash_accounts
      assert entry!(read.unvalued_cash_accounts, world.franc.cash, "2000") == expected
    end

    # Every figure is the walk's as before.
    assert performance.start_date == ~D[2026-07-01]
    assert equal?(performance.start_value, "0")
    assert equal?(performance.end_value, "3500")
    assert equal?(performance.net_external_flows, "1000")
    assert equal?(performance.ttwror, "2.5")
    assert contribution.positions == []
    assert equal?(contribution.remainder.cash_currency_effect, "2500")
    assert equal?(contribution.remainder.interest, "0")
    assert equal?(contribution.remainder.standalone_fees_and_taxes, "0")
    assert equal?(contribution.totals.result, "2500")
    assert equal?(contribution.totals.remainder, "2500")

    # Only the list is added.
    assert Enum.sort(Map.keys(performance)) ==
             Enum.sort([:unvalued_cash_accounts | @performance_keys])

    assert Enum.sort(Map.keys(contribution)) ==
             Enum.sort([:unvalued_cash_accounts | @contribution_keys])

    # The walk: the account and its native balance on each zero day only.
    analysis = Performance.analysis(pid, today: @today)

    for point <- analysis.daily do
      if Date.compare(point.date, ~D[2026-07-14]) != :lt and
           Date.compare(point.date, ~D[2026-07-31]) != :gt do
        assert Enum.sort(Map.keys(point)) == Enum.sort([:unvalued_cash | @point_keys])
        assert [{id, balance}] = Map.to_list(point.unvalued_cash)
        assert id == world.franc.cash.id
        assert equal?(balance, "2000")
      else
        assert Enum.sort(Map.keys(point)) == @point_keys, "#{point.date}"
      end
    end

    assert analysis.cash_labels == %{
             world.franc.cash.id => %{name: "Tagesgeld CHF", currency_code: "CHF"}
           }

    assert analysis.first_rate_dates == %{"CHF" => ~D[2026-08-01]}
  end

  # User story (#1055, ADR-0051 §10):
  # As a local portfolio maintainer switching periods,
  # I want the account named exactly when the period holds days it counted
  # zero, and its first rate's date only when that rate arrived inside it,
  # so that the note changes with the period, as the jump does.
  #
  # Acceptance criteria:
  # - A window ending before the first rate lists the account with the days
  #   inside it and no first-rate date.
  # - A window holding zero days and the first rate lists the days inside it
  #   and the date.
  # - A window starting on or after the first rate, a window before the
  #   history and an empty window list nothing.
  test "the list follows the window" do
    world = franc_world()
    pid = world.portfolio.id

    cases = [
      {{:range, ~D[2026-07-01], ~D[2026-07-31]}, 18, nil},
      {{:range, ~D[2026-07-01], ~D[2026-07-20]}, 7, nil},
      {{:range, ~D[2026-07-20], ~D[2026-08-15]}, 12, ~D[2026-08-01]},
      {"ytd", 18, ~D[2026-08-01]}
    ]

    for {period, days, first_rate_date} <- cases,
        {read_name, read} <- reads(pid, period) do
      label = "#{read_name} #{inspect(period)}"
      assert [entry] = read.unvalued_cash_accounts, label
      assert entry.unvalued_days == days, label
      assert entry.first_rate_date == first_rate_date, label
      assert equal?(entry.balance, "2000"), label
    end

    for period <- [
          {:range, ~D[2026-08-01], ~D[2026-09-30]},
          {:range, ~D[2026-08-02], ~D[2026-09-30]},
          {:range, ~D[2025-01-01], ~D[2025-12-31]},
          {:year, 2027}
        ],
        {read_name, read} <- reads(pid, period) do
      assert read.unvalued_cash_accounts == [], "#{read_name} #{inspect(period)}"
    end
  end

  # User story (#1055, ADR-0051 §10):
  # As a local portfolio maintainer whose CHF account was emptied for a few
  # days before any rate existed,
  # I want only the days a balance actually counted zero to be counted,
  # so that an empty account is never named for money it did not hold.
  #
  # Acceptance criteria:
  # - A day on which the account's balance is zero is not counted, though
  #   its currency has no rate.
  # - The balance named is the native balance on the last counted day.
  # - The second deposit keeps the first rate's date.
  test "a day the account is empty does not count" do
    world = base_world(name: "Emptied World", cash_name: "Giro", depot_name: "Depot")
    franc = franc_account!(world.portfolio, "Tagesgeld CHF")
    deposit!(world, "1000", ~D[2026-07-01])
    deposit!(franc, "500", ~D[2026-07-14], currency: "CHF")
    removal!(franc, "500", ~D[2026-07-20])
    deposit!(franc, "300", ~D[2026-07-25], currency: "CHF")
    rate!("CHF", ~D[2026-08-01], "0.8")

    for {read_name, read} <- reads(world.portfolio.id, "max") do
      # 07-14 to 07-19 and 07-25 to 07-31.
      assert entry!(read.unvalued_cash_accounts, franc.cash, "300") == %{
               cash_account_id: franc.cash.id,
               name: "Tagesgeld CHF",
               currency_code: "CHF",
               unvalued_days: 13,
               unvalued_reason: :no_rate,
               first_rate_date: ~D[2026-08-01]
             },
             "#{read_name}"
    end
  end

  # User story (#1055, ADR-0051 §6 and §10):
  # As a local portfolio maintainer reading a view across my portfolios,
  # I want every account that counted zero in the view named, and none the
  # view leaves out,
  # so that the view's note speaks about the same accounts as its total.
  #
  # Acceptance criteria:
  # - Two portfolios with one CHF account each: the Everything view's
  #   performance and contribution reads list both, sorted by name.
  # - A view holding one portfolio's accounts lists that one, across
  #   portfolios and on the portfolio narrowed by it; the other portfolio
  #   narrowed by it lists none.
  # - A portfolio whose every balance was valued lists none.
  test "a view lists the accounts in its scope" do
    first = franc_world()
    second = base_world(name: "Second Franc", cash_name: "Giro Two", depot_name: "Depot Two")
    savings = franc_account!(second.portfolio, "Sparkonto CHF")
    deposit!(second, "100", ~D[2026-07-01])
    deposit!(savings, "400", ~D[2026-07-21], currency: "CHF")

    valued = base_world(name: "Valued World", cash_name: "Giro Three", depot_name: "Depot Three")
    deposit!(valued, "100", ~D[2026-07-01])

    {:ok, everything} = Performance.for_view(nil, period: "max", today: @today)
    {:ok, everything_c} = Contribution.for_view(nil, period: "max", today: @today)

    for read <- [everything, everything_c] do
      assert Enum.map(read.unvalued_cash_accounts, & &1.name) == [
               "Sparkonto CHF",
               "Tagesgeld CHF"
             ]

      assert %{unvalued_days: 11, first_rate_date: ~D[2026-08-01]} =
               entry!(read.unvalued_cash_accounts, savings.cash, "400")

      assert %{unvalued_days: 18, first_rate_date: ~D[2026-08-01]} =
               entry!(read.unvalued_cash_accounts, first.franc.cash, "2000")
    end

    {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Franc Bucket"})
    :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), first.cash, [bucket.id])
    :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), first.franc.cash, [bucket.id])
    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Francs", include_all: false})
    :ok = Buckets.set_view_buckets(Actor.owner_ui(), view, [bucket.id], [])

    {:ok, across} = Performance.for_view(view.id, period: "max", today: @today)
    {:ok, across_c} = Contribution.for_view(view.id, period: "max", today: @today)

    {:ok, narrowed} =
      Performance.for_portfolio(first.portfolio.id, view: view.id, period: "max", today: @today)

    {:ok, narrowed_c} =
      Contribution.for_portfolio(first.portfolio.id, view: view.id, period: "max", today: @today)

    for read <- [across, across_c, narrowed, narrowed_c] do
      assert Enum.map(read.unvalued_cash_accounts, & &1.cash_account_id) == [
               first.franc.cash.id
             ]
    end

    {:ok, other} =
      Performance.for_portfolio(second.portfolio.id, view: view.id, period: "max", today: @today)

    assert other.unvalued_cash_accounts == []

    for {_read_name, read} <- reads(valued.portfolio.id, "max") do
      assert read.unvalued_cash_accounts == []
    end

    refute Map.has_key?(Performance.analysis(valued.portfolio.id, today: @today), :cash_labels)
  end

  # User story (#1055; AGENTS.md metric rule):
  # As the operator's agent reading either period read,
  # I want the basis to say where an account that counted zero is named,
  # so that I read the list instead of guessing why the currency line jumped.
  #
  # Acceptance criteria:
  # - Both reads' computation_basis.gaps name unvalued_cash_accounts; the
  #   contribution's no longer says that no account is named.
  test "both bases name the list" do
    world = franc_world()
    [performance: performance, contribution: contribution] = reads(world.portfolio.id, "max")

    assert performance.computation_basis.gaps =~ "unvalued_cash_accounts"
    assert contribution.computation_basis.gaps =~ "unvalued_cash_accounts"
    refute contribution.computation_basis.gaps =~ "no account is named"
  end
end
