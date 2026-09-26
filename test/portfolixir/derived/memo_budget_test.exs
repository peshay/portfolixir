defmodule Portfolixir.Derived.MemoBudgetTest do
  # E25 S4, G03 (#889): the derived-values memo had no size bound, and some of
  # its keys carried parameters a caller chooses from a continuum — a custom
  # rate, a custom date range, the instant a walk was computed — so repeated
  # reads could grow it without end. The memo now keeps to a budget, flushing
  # the table (it is never a source of truth) when a put would leave it over,
  # and the reads memoise only fixed periods and whole-basis-point rates.
  use Portfolixir.DataCase, async: false

  import Portfolixir.WorldFixtures, only: [base_world: 1, deposit!: 3]

  alias Portfolixir.Derived.Memo
  alias Portfolixir.DerivedConfig
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.Performance.Benchmark
  alias Portfolixir.Portfolios.RiskMetrics

  setup do
    Memo.reset()
    on_exit(&Memo.reset/0)
    :ok
  end

  defp entries(analytic) do
    :ets.select(Memo, [{{{analytic, :_, :_, :_, :_}, :_, :_, :_}, [], [true]}]) |> length()
  end

  defp entry_keys(analytic) do
    :ets.select(Memo, [{{{analytic, :_, :"$1", :_, :_}, :_, :_, :_}, [], [:"$1"]}])
    |> Enum.uniq()
  end

  defp key(n), do: {:budget_probe, "basis", "entry:#{n}", 1, 1}

  # User story:
  # As the operator running the instance on a small machine,
  # I want the derived-values memo to stay within a fixed budget,
  # so that no pattern of reads can grow the node's memory until it dies.
  #
  # Acceptance criteria:
  # - Past the entry cap, a put leaves the table within the cap, and the value
  #   just put is served.
  # - Past the byte cap, likewise; a value larger than the whole budget is not
  #   kept at all.
  test "past the cap a put leaves the table within budget" do
    DerivedConfig.enable!(memo_max_entries: 5)
    now = DateTime.utc_now()

    for n <- 1..12, do: Memo.put(key(n), n, now)

    assert Memo.usage().entries <= 5
    assert {:hit, 12, _} = Memo.get(key(12))

    DerivedConfig.enable!(memo_max_entries: 1_000_000, memo_max_bytes: 200_000)
    Memo.reset()

    for n <- 1..40, do: Memo.put(key(n), Enum.to_list(1..500), now)

    assert Memo.usage().bytes <= 200_000
    assert Memo.usage().entries < 40
    assert {:hit, _, _} = Memo.get(key(40))

    Memo.put(key(:big), Enum.to_list(1..20_000), now)

    assert Memo.usage().bytes <= 200_000
    assert Memo.get(key(:big)) == :miss
  end

  # User story:
  # As the operator (and the agent) comparing against custom rates and ranges,
  # I want such one-off reads computed but not remembered,
  # so that a sweep of distinct values cannot fill the memo, while the fixed
  # periods and whole-basis-point rates the page offers stay fast.
  #
  # Acceptance criteria:
  # - Benchmark comparisons at rates finer than a basis point, or over a
  #   custom date range, add no memo entry; a whole-basis-point rate over a
  #   named period adds one.
  # - Risk metrics at risk-free rates finer than a basis point add no memo
  #   entry.
  # - Two walks of one scope share one entry key: the walk's identity is
  #   checked on the value, not carried in the key.
  test "distinct custom-rate and custom-range reads add no memo entries" do
    DerivedConfig.enable!(lifetimes: [])
    world = base_world(name: "G03")
    deposit!(world, "1000", ~D[2026-01-01])
    today = ~D[2026-01-21]
    pid = world.portfolio.id

    for rate <- ~w(0.0212345 0.0212346 0.0212347) do
      {:ok, _} = Benchmark.for_portfolio(pid, {:rate, Decimal.new(rate)}, today: today)
    end

    {:ok, _} =
      Benchmark.for_portfolio(pid, {:rate, Decimal.new("0.02")},
        today: today,
        period: {:range, ~D[2026-01-02], ~D[2026-01-09]}
      )

    assert entries(:benchmark_comparison) == 0

    {:ok, _} = Benchmark.for_portfolio(pid, {:rate, Decimal.new("0.0275")}, today: today)
    assert entries(:benchmark_comparison) == 1

    for rate <- ~w(0.0112345 0.0112346) do
      RiskMetrics.for_portfolio(pid, [], as_of: today, risk_free_rate: Decimal.new(rate))
    end

    assert entries(:portfolio_metrics) == 0

    analysis = Performance.analysis(pid, today: today)
    later = put_in(analysis, [:basis, :computed_at], DateTime.add(analysis.basis.computed_at, 60))

    Memo.reset()
    {:ok, _} = Benchmark.compare(analysis, "max", {:rate, Decimal.new("0.02")})
    {:ok, _} = Benchmark.compare(later, "max", {:rate, Decimal.new("0.02")})

    assert length(entry_keys(:benchmark_comparison)) == 1
  end
end
