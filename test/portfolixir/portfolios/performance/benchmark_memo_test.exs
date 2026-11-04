defmodule Portfolixir.Portfolios.Performance.BenchmarkMemoTest do
  # The benchmark comparison under ADR-0039's memo, with the derived layer
  # ON (the test config keeps it off, so the async engine suite never sees a
  # memo hit). Closing-act findings of the risk-tier pass and both hunters:
  # a comparison built from a superseded walk must never be served as fresh.
  use Portfolixir.DataCase, async: false

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, create_security!: 1, deposit!: 3, put_quotes!: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Derived.Memo
  alias Portfolixir.DerivedConfig
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.Performance.Benchmark

  setup do
    Memo.reset()
    DerivedConfig.enable!(lifetimes: [])
    :ok
  end

  defp d(value), do: Decimal.new(value)

  # User story (closing-act finding, ADR-0039 C4):
  # As a local portfolio maintainer whose Wealth page renders the superseded
  # walk while the fresh one computes,
  # I want the benchmark comparison built from that superseded walk never to
  # be remembered as the fresh one,
  # so that the delta next to TTWROR/IRR reflects the write the walk already
  # reflects.
  #
  # Acceptance criteria:
  # - A comparison computed from a stale analysis is not memoised under the
  #   current data version; the next fresh read recomputes.
  test "a comparison built from a superseded walk never poisons the memo" do
    world = base_world(name: "M1", cash_name: "M1 Cash", depot_name: "M1 Depot")
    deposit!(world, "1000", ~D[2026-01-01])

    {:ok, first} = Benchmark.for_view(nil, {:rate, d("0")}, today: ~D[2026-01-21])
    assert Decimal.equal?(first.savings_plan.invested_capital, d("1000"))

    # A write supersedes the walk; the page serves the previous one meanwhile.
    deposit!(world, "500", ~D[2026-01-10])
    stale = Performance.previous_view_analysis(nil, today: ~D[2026-01-21])
    assert %{stale: true} = stale
    {:ok, from_stale} = Benchmark.compare(stale, "max", {:rate, d("0")})
    assert from_stale.stale == true
    assert Decimal.equal?(from_stale.savings_plan.invested_capital, d("1000"))

    # The fresh read reflects the deposit — nothing stale wearing "fresh".
    {:ok, fresh} = Benchmark.for_view(nil, {:rate, d("0")}, today: ~D[2026-01-21])
    assert fresh.stale == false
    assert Decimal.equal?(fresh.savings_plan.invested_capital, d("1500"))
  end

  test "a quote write for a benchmark the portfolio never held invalidates the memoised comparison" do
    world = base_world(name: "M2", cash_name: "M2 Cash", depot_name: "M2 Depot")
    deposit!(world, "1000", ~D[2026-01-01])
    bench = create_security!(name: "Unheld", ticker: "UNH")
    {:ok, bench} = Catalog.update_security(Actor.owner_ui(), bench, %{is_benchmark: true})
    put_quotes!(bench, [{~D[2026-01-01], "100"}, {~D[2026-01-10], "100"}])

    {:ok, first} =
      Benchmark.for_portfolio(world.portfolio.id, {:security, bench}, today: ~D[2026-01-10])

    assert Decimal.equal?(first.savings_plan.benchmark_end_value, d("1000"))
    # The same read again is served from the memo with the same figures.
    {:ok, again} =
      Benchmark.for_portfolio(world.portfolio.id, {:security, bench}, today: ~D[2026-01-10])

    assert Decimal.equal?(again.savings_plan.benchmark_end_value, d("1000"))

    put_quotes!(bench, [{~D[2026-01-10], "120"}])

    {:ok, second} =
      Benchmark.for_portfolio(world.portfolio.id, {:security, bench}, today: ~D[2026-01-10])

    assert Decimal.equal?(second.savings_plan.benchmark_end_value, d("1200"))
  end

  # User story (Sprint 24 B1; ADR-0046, amended 2026-11-04; ADR-0039 C4):
  # As the owner who books a fee or moves a cash account out of a view after
  # reading a comparison,
  # I want the next comparison's costs_paid to count it,
  # so that a remembered comparison never shows the costs of a ledger or a
  # view that has since changed.
  #
  # Acceptance criteria (exact Decimal expectations):
  # - A memoised view comparison reads fees 0; a 4.00 fee booked from the
  #   view's cash account makes the next read 4.00.
  # - Taking that cash account out of the view's bucket makes the next read
  #   0 again: the scope is read under the same memo identity as the walk.
  test "costs_paid follows a new fee and a changed view under the memo" do
    world = base_world(name: "M3", cash_name: "M3 Cash", depot_name: "M3 Depot")
    deposit!(world, "1000", ~D[2026-01-01])

    {:ok, bucket} =
      Portfolixir.Buckets.create_bucket(Actor.owner_ui(), %{
        name: "M3 Bucket #{System.unique_integer([:positive])}"
      })

    :ok = Portfolixir.Buckets.set_cash_account_buckets(Actor.owner_ui(), world.cash, [bucket.id])

    # A second account keeps the view walking once the first one leaves it.
    other =
      Portfolixir.WorldFixtures.add_depot(world.portfolio,
        cash_name: "M3 Other",
        depot_name: "M3 Other Depot"
      )

    deposit!(%{world | cash: other.cash}, "200", ~D[2026-01-01])
    :ok = Portfolixir.Buckets.set_cash_account_buckets(Actor.owner_ui(), other.cash, [bucket.id])

    {:ok, view} =
      Portfolixir.Buckets.create_view(Actor.owner_ui(), %{
        name: "M3 View #{System.unique_integer([:positive])}",
        include_all: false
      })

    :ok = Portfolixir.Buckets.set_view_buckets(Actor.owner_ui(), view, [bucket.id], [])

    read = fn ->
      {:ok, cmp} = Benchmark.for_view(view.id, {:rate, d("0")}, today: ~D[2026-01-21])
      cmp.costs_paid.fees
    end

    assert Decimal.equal?(read.(), d("0"))

    {:ok, _fee} =
      Portfolixir.Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        type: "fee",
        date: ~D[2026-01-10],
        gross_amount: "4.00",
        currency_code: "EUR"
      })

    assert Decimal.equal?(read.(), d("4.00"))

    :ok = Portfolixir.Buckets.set_cash_account_buckets(Actor.owner_ui(), world.cash, [])
    {:ok, still} = Benchmark.for_view(view.id, {:rate, d("0")}, today: ~D[2026-01-21])
    assert still.requested_window.start_date == ~D[2026-01-01]
    assert Decimal.equal?(still.costs_paid.fees, d("0"))
  end
end
