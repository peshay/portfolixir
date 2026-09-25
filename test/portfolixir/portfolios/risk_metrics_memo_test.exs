defmodule Portfolixir.Portfolios.RiskMetricsMemoTest do
  # E25 S6 (#891), F46: the portfolio-metrics memo was keyed on the data
  # version read when the metrics were fetched, not on the version of the walk
  # they were computed from. A write landing between the walk and the metrics
  # stored metrics of the old walk under the new version, and they were served
  # as fresh until the next write. The derived layer is off in the test
  # config, so this file switches it on, as production runs it.
  use Portfolixir.DataCase, async: false

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quotes!: 2]

  alias Portfolixir.Derived.Memo
  alias Portfolixir.DerivedConfig
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.RiskMetrics

  @as_of ~D[2026-09-19]

  defp day(offset), do: Date.add(@as_of, offset)

  setup do
    Memo.reset()
    DerivedConfig.enable!()
    on_exit(&Memo.reset/0)
    :ok
  end

  # User story:
  # As the operator reading the risk page right after a booking or a price,
  # I want volatility and drawdown computed from the walk they claim to be
  # current for,
  # so that a figure from before the write is never served as fresh.
  #
  # Acceptance criteria:
  # - When a write lands after the walk was read and before the metrics are
  #   computed, the next read recomputes: its metrics equal the ones the
  #   layer computes with no memo at all.
  test "a write injected between walk and metrics forces recomputation on the next read" do
    world = base_world(name: "Metrics memo")
    security = create_security!(name: "Kestrel Industrial Group NV", ticker: "KIG")

    deposit!(world, "10000", day(-60))
    buy!(world, security, quantity: "10", price: "100", date: day(-60))
    put_quotes!(security, for(offset <- -60..0, do: {day(offset), "100"}))

    # The walk is read; then a price lands (the write), before the metrics.
    walk_then_write = fn portfolio_id, opts ->
      analysis = Performance.analysis(portfolio_id, opts)
      put_quotes!(security, [{day(-1), "80"}, {day(0), "120"}])
      analysis
    end

    first =
      RiskMetrics.for_portfolio(world.portfolio.id, [security.id],
        as_of: @as_of,
        analysis: walk_then_write
      )

    second = RiskMetrics.for_portfolio(world.portfolio.id, [security.id], as_of: @as_of)

    truth =
      DerivedConfig.with_layer_off(fn ->
        RiskMetrics.for_portfolio(world.portfolio.id, [security.id], as_of: @as_of)
      end)

    refute first.volatility == truth.volatility, "the injected write moved no figure"
    assert second.volatility == truth.volatility
    assert second.max_drawdown == truth.max_drawdown
  end
end
