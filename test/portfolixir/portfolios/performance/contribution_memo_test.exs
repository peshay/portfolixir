defmodule Portfolixir.Portfolios.Performance.ContributionMemoTest do
  # The contribution under ADR-0039's memo, with the derived layer ON (the
  # test config keeps it off, so the async engine suite never sees a hit).
  # The memo table is global, hence async: false.
  use Portfolixir.DataCase, async: false

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1, deposit!: 3]

  alias Portfolixir.Derived.Memo
  alias Portfolixir.Derived.Registry
  alias Portfolixir.DerivedConfig
  alias Portfolixir.Portfolios.Performance.Contribution
  alias Portfolixir.WorldFixtures

  @today ~D[2026-06-30]

  setup do
    Memo.reset()
    on_exit(&Memo.reset/0)
    DerivedConfig.enable!(lifetimes: [])
    :ok
  end

  defp entry_keys(analytic) do
    :ets.select(Memo, [{{{analytic, :_, :"$1", :_, :_}, :_, :_, :_}, [], [:"$1"]}])
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp contribution_of(result, security),
    do: Enum.find(result.positions, &(&1.security_id == security.id)).contribution

  # User story (FR-41, ADR-0051 §12, ADR-0039):
  # As a local portfolio maintainer switching periods on the Wealth page,
  # I want the contribution served as its own derived value per scope and
  # period, and recomputed after any write,
  # so that switching back to a period is cheap and the table is never older
  # than my ledger.
  #
  # Acceptance criteria:
  # - `performance_contribution` (portfolio basis) and
  #   `performance_view_contribution` (global basis) are registered at
  #   computation version 1 with the default lifetime `:request`; the walk
  #   analytics keep their computation version.
  # - A fixed-period read is memoised under its analytic, one entry per
  #   scope, walk end date and period; repeating it returns the same figures.
  # - A ledger write is in the next read.
  # - A custom range is computed on every read and never remembered (the
  #   memo budget's rule, E25 S4 G03).
  # - The contribution's walk is never stored as a walk analytic.
  test "the contribution is its own request-lifetime analytic per scope and period" do
    assert Registry.computation_version!(:performance_contribution) == 1
    assert Registry.computation_version!(:performance_view_contribution) == 1
    assert Registry.lifetime(:performance_contribution) == :request
    assert Registry.lifetime(:performance_view_contribution) == :request
    assert Registry.computation_version!(:performance_analysis) == 3

    world = base_world(name: "Memo", cash_name: "Cash", depot_name: "Depot")
    fund = create_security!(name: "Memo Fund", ticker: "MMF")
    deposit!(world, "1000", ~D[2026-01-05])
    WorldFixtures.buy!(world, fund, quantity: "5", price: "100", date: ~D[2026-01-05])
    WorldFixtures.put_quotes!(fund, [{~D[2026-01-05], "100"}, {~D[2026-03-02], "110"}])
    pid = world.portfolio.id

    {:ok, first} = Contribution.for_portfolio(pid, period: "ytd", today: @today)
    {:ok, again} = Contribution.for_portfolio(pid, period: "ytd", today: @today)
    {:ok, _year} = Contribution.for_portfolio(pid, period: {:year, 2026}, today: @today)
    {:ok, _view} = Contribution.for_view(nil, period: "ytd", today: @today)

    assert again == first
    assert first.stale == false
    assert Decimal.equal?(contribution_of(first, fund), Decimal.new("50"))

    assert entry_keys(:performance_contribution) == [
             "view=unscoped|today=2026-06-30|period=year:2026",
             "view=unscoped|today=2026-06-30|period=ytd"
           ]

    assert entry_keys(:performance_view_contribution) == [
             "view=unscoped|base=EUR|today=2026-06-30|period=ytd"
           ]

    assert entry_keys(:performance_analysis) == []

    # A write supersedes the memoised table: one more bought at 105, the
    # newest price observation, so 6 x 105 - 605.
    WorldFixtures.buy!(world, fund, quantity: "1", price: "105", date: ~D[2026-04-01])
    {:ok, later} = Contribution.for_portfolio(pid, period: "ytd", today: @today)
    assert Decimal.equal?(contribution_of(later, fund), Decimal.new("25"))

    # A custom range is computed, never remembered.
    range = {:range, ~D[2026-02-01], ~D[2026-05-31]}
    {:ok, ranged} = Contribution.for_portfolio(pid, period: range, today: @today)
    assert ranged.start_date == ~D[2026-02-01]
    refute Enum.any?(entry_keys(:performance_contribution), &String.contains?(&1, "range"))
  end
end
