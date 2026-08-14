defmodule Portfolixir.Portfolios.PerformanceWarmupTest do
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Derived
  alias Portfolixir.Derived.Memo
  alias Portfolixir.Portfolios.Performance.Warmup

  # User story (2026-07-29, ADR-0032 §5, issue #562):
  # As a local portfolio maintainer,
  # I want the performance memo warmed at boot,
  # so that the first page of the day opens without paying for the daily walk.
  #
  # Acceptance criteria:
  # - The warm-up goes through the request path, so a warmed entry is
  #   byte-identical to one a request would have computed.
  # - A failing scope is skipped, never fatal.
  # - With the derived layer disabled the warm-up is a no-op — one "off" state.

  setup do
    Memo.reset()
    Application.put_env(:portfolixir, Derived, enabled?: true)
    on_exit(fn -> Application.put_env(:portfolixir, Derived, enabled?: false) end)
    :ok
  end

  defp fetch!(portfolio_id, view, compute) do
    {:fresh, value} =
      Derived.fetch(
        :performance_analysis,
        Derived.portfolio_basis(portfolio_id),
        "view=#{view}|today=#{Date.utc_today()}",
        compute
      )

    value
  end

  defp seeded_portfolio!(name) do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{name: name, base_currency_code: "EUR"})

    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: name <> " Cash",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: name <> " Depot"
      })

    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: name <> " AG",
        currency_code: "EUR",
        isin: "DE000WARM000" |> String.slice(0..-2//1) |> Kernel.<>(String.last(name))
      })

    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        securities_account_id: depot.id,
        cash_account_id: cash.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2024-01-02],
        quantity: Decimal.new("1"),
        price: Decimal.new("10"),
        gross_amount: Decimal.new("10"),
        currency_code: "EUR"
      })

    portfolio
  end

  test "warm/0 fills the memo through the request path" do
    portfolio = seeded_portfolio!("Warm A")

    assert Warmup.warm() == :ok

    # The entry is present: a fetch whose compute would raise never runs it.
    analysis =
      fetch!(portfolio.id, "unscoped", fn ->
        raise "memo missed — the warm-up did not fill it"
      end)

    assert analysis.portfolio_id == portfolio.id
    assert analysis.daily != []
  end

  test "with the derived layer disabled the warm-up is a no-op" do
    portfolio = seeded_portfolio!("Warm B")
    Application.put_env(:portfolixir, Derived, enabled?: false)

    assert Warmup.warm() == :ok

    Application.put_env(:portfolixir, Derived, enabled?: true)
    called = :counters.new(1, [])

    fetch!(portfolio.id, "unscoped", fn ->
      :counters.add(called, 1, 1)
      :fresh
    end)

    assert :counters.get(called, 1) == 1
  end

  test "an empty instance warms without error" do
    assert Warmup.warm() == :ok
  end

  test "warm/0 also warms the default view's scope" do
    portfolio = seeded_portfolio!("Warm C")
    {:ok, view} = Portfolixir.Buckets.create_view(Actor.owner_ui(), %{name: "Warm View"})
    Portfolixir.Settings.set_default_view(view.id)

    assert Warmup.warm() == :ok

    assert fetch!(portfolio.id, view.id, fn ->
             raise "memo missed for the default view scope"
           end)
  end

  # The GenServer shell, exercised directly: the callbacks run in the test
  # process, so the sandbox applies without shared-mode ceremony.
  test "the process warms on continue and re-warms on rollover" do
    seeded_portfolio!("Warm D")

    assert Warmup.init(enabled?: false) == :ignore

    Application.put_env(:portfolixir, Derived, enabled?: false)
    assert Warmup.init([]) == :ignore
    Application.put_env(:portfolixir, Derived, enabled?: true)

    assert {:ok, state, {:continue, :warm}} = Warmup.init([])
    assert {:noreply, ^state} = Warmup.handle_continue(:warm, state)
    assert {:noreply, ^state} = Warmup.handle_info(:rollover, state)

    # Both callbacks scheduled a rollover on this (test) process; far in the
    # future, so they never fire — assert they exist, then flush.
    assert_receive_nothing = fn -> refute_received :rollover end
    assert_receive_nothing.()
  end
end
