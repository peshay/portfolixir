defmodule Portfolixir.Engines.PortfolioMetricsTest do
  use ExUnit.Case, async: true

  alias Portfolixir.Engines.PortfolioMetrics
  alias Portfolixir.Portfolios.Performance.Benchmark

  @as_of ~D[2026-09-19]

  # Return observations `%{date, factor}` on consecutive days ending on `last`,
  # oldest first. A factor is `1 + r_d` of the TTWROR chain (ADR-0047 §2).
  defp observations(factors, last \\ @as_of) do
    first = Date.add(last, -(length(factors) - 1))

    factors
    |> Enum.with_index()
    |> Enum.map(fn {factor, index} ->
      %{date: Date.add(first, index), factor: Decimal.new(factor)}
    end)
  end

  # Consecutive daily closes ending on `last`, oldest first.
  defp closes(values, last \\ @as_of) do
    first = Date.add(last, -(length(values) - 1))

    values
    |> Enum.with_index()
    |> Enum.map(fn {close, index} ->
      %{date: Date.add(first, index), close: Decimal.new(close)}
    end)
  end

  # `Decimal.equal?/2` ignores the scale, which is how Sprint 13 found I2
  # passing while unpinned. Where an identity names the scale, the rendered
  # string is what gets asserted (Sprint 14 plan, Lane A1).
  defp assert_scale_6(actual, expected) do
    assert Decimal.to_string(actual, :normal) == expected,
           "expected #{expected} at scale 6, got #{inspect(actual)}"
  end

  # A series whose simple daily returns alternate +1 % / -1 % around a level.
  defp alternating(count) do
    Enum.map(1..count, fn index -> if rem(index, 2) == 0, do: "0.99", else: "1.01" end)
  end

  # User story (FR-40, ADR-0047 §2 and §11, identity I1):
  # As the operator who saves into the portfolio every month,
  # I want the portfolio's volatility and drawdown measured over the TTWROR
  # chain's flow-adjusted return factors,
  # so that a deposit or a withdrawal is never reported as movement.
  #
  # Acceptance criteria:
  # - A chain whose every factor is exactly 1 has volatility exactly 0 and a
  #   maximum drawdown exactly 0, at scale 6, in every window.
  # - The risk-adjusted return of such a chain is undefined (volatility 0) and
  #   renders null rather than a division by zero.
  test "I1: a chain of unit factors has volatility exactly 0 and drawdown exactly 0" do
    metrics = PortfolioMetrics.compute(observations(List.duplicate("1", 400)), @as_of)

    for window <- ~w(30d 90d 365d) do
      assert_scale_6(metrics.volatility[window].value, "0.000000")
      refute metrics.volatility[window].insufficient_data
      assert_scale_6(metrics.max_drawdown[window].value, "0.000000")
      refute metrics.max_drawdown[window].insufficient_data
      assert metrics.risk_adjusted_return[window].value == nil
      refute metrics.risk_adjusted_return[window].insufficient_data
    end

    assert metrics.volatility["30d"].observations == 30
    assert metrics.volatility["365d"].observations == 365
    assert metrics.volatility["30d"].window == %{start_date: ~D[2026-08-20], end_date: @as_of}
  end

  # Acceptance criteria (ADR-0047 §4, identity I4):
  # - The calendar walk annualizes by √365, and the engine says so.
  # - Alternating +1 % / -1 % daily returns have a population standard
  #   deviation of exactly 0.01 per day, so the annualized figure is
  #   0.01 × √365 = 0.191050 at scale 6.
  test "I4: the calendar walk annualizes by √365" do
    assert PortfolioMetrics.days_per_year() == 365

    metrics = PortfolioMetrics.compute(observations(alternating(30)), @as_of)

    assert_scale_6(metrics.volatility["30d"].value, "0.191050")
    assert metrics.volatility["30d"].observations == 30
  end

  # Acceptance criteria (ADR-0047 §3, §4):
  # - risk_adjusted_return = (annualized mean daily return − risk-free) /
  #   annualized volatility, the risk-free rate compounded daily as ADR-0046's
  #   fixed rate is.
  # - At the default rate 0 the figure is return per unit of risk.
  test "risk_adjusted_return divides the annualized excess return by the volatility" do
    # Mean daily return 0.001, deviation 0.01: 0.001 × 365 / (0.01 × √365)
    # = 0.1 × √365 / 1 = 1.910497…
    factors = Enum.map(1..30, fn i -> if rem(i, 2) == 0, do: "0.991", else: "1.011" end)

    metrics = PortfolioMetrics.compute(observations(factors), @as_of)
    assert_scale_6(metrics.risk_adjusted_return["30d"].value, "1.910497")
    assert Decimal.equal?(metrics.risk_adjusted_return["30d"].risk_free_rate, Decimal.new(0))

    with_rate =
      PortfolioMetrics.compute(observations(factors), @as_of,
        risk_free_rate: Decimal.new("0.05"),
        daily_rate_factor: &Benchmark.daily_rate_factor/1
      )

    # The daily risk-free factor (1.05)^(1/365) lowers the excess return.
    assert Decimal.compare(
             with_rate.risk_adjusted_return["30d"].value,
             metrics.risk_adjusted_return["30d"].value
           ) == :lt

    assert Decimal.equal?(
             with_rate.risk_adjusted_return["30d"].risk_free_rate,
             Decimal.new("0.05")
           )
  end

  # Acceptance criteria (ADR-0047 §3, over the chained return index):
  # - A chain that halves and recovers has a maximum drawdown of exactly -0.5
  #   at scale 6, with the peak, trough and recovery dates.
  # - The index starts at 1 on the day before the first observation, so a
  #   first-day fall is a drawdown rather than the peak.
  test "max_drawdown runs over the chained return index with its three dates" do
    factors = List.duplicate("1", 20) ++ ["0.5"] ++ List.duplicate("1", 3) ++ ["2"] ++ ["1"]
    metrics = PortfolioMetrics.compute(observations(factors), @as_of)
    drawdown = metrics.max_drawdown["30d"]

    assert_scale_6(drawdown.value, "-0.500000")
    first = Date.add(@as_of, -(length(factors) - 1))
    assert drawdown.peak_date == Date.add(first, 19)
    assert drawdown.trough_date == Date.add(first, 20)
    assert drawdown.recovery_date == Date.add(first, 24)
    # Baseline point plus one index point per observation.
    assert drawdown.observations == length(factors) + 1
    assert drawdown.window.start_date == Date.add(first, -1)

    first_day_fall = PortfolioMetrics.compute(observations(["0.9", "1"]), @as_of)
    assert_scale_6(first_day_fall.max_drawdown["30d"].value, "-0.100000")
    assert first_day_fall.max_drawdown["30d"].recovery_date == nil
  end

  # Acceptance criteria (ADR-0047 §5, identity I5, and the #838 amendment):
  # - Below its minimum a metric is null with insufficient_data, its
  #   observation count, and `required`; the window is the span it asked for.
  # - `required` rides every metric in both states.
  test "I5: below the minimum a metric refuses and carries what it needed" do
    metrics = PortfolioMetrics.compute(observations(List.duplicate("1.01", 14)), @as_of)
    volatility = metrics.volatility["30d"]

    assert volatility.value == nil
    assert volatility.insufficient_data
    assert volatility.observations == 14
    assert volatility.required == 20
    assert volatility.window == %{start_date: Date.add(@as_of, -30), end_date: @as_of}

    assert metrics.risk_adjusted_return["30d"].value == nil
    assert metrics.risk_adjusted_return["30d"].insufficient_data
    assert metrics.risk_adjusted_return["30d"].required == 20

    # Computed metrics carry `required` too.
    refute metrics.max_drawdown["30d"].insufficient_data
    assert metrics.max_drawdown["30d"].required == 2

    empty = PortfolioMetrics.compute([], @as_of)
    assert empty.max_drawdown["365d"].insufficient_data
    assert empty.max_drawdown["365d"].observations == 0
    assert empty.max_drawdown["365d"].required == 2
  end

  # Acceptance criteria (ADR-0047 §5):
  # - A day with no return base is not an observation: the engine is handed
  #   only observed days, and a missing day shrinks the count rather than
  #   entering as a zero return.
  test "a skipped day is absent, never a zero return" do
    full = observations(alternating(30))
    gapped = Enum.reject(full, &(&1.date == Date.add(@as_of, -3)))

    metrics = PortfolioMetrics.compute(gapped, @as_of)
    assert metrics.volatility["30d"].observations == 29
  end

  # User story (FR-40, ADR-0047 §3 and §11, identity I3):
  # As the operator's agent asking whether the largest positions move together,
  # I want the pairwise correlation of their daily returns,
  # so that concentration that hides behind several names becomes visible.
  #
  # Acceptance criteria:
  # - A series correlated with itself is 1 at scale 6; with its negation, -1.
  # - Each pair carries its overlap count and `required` (60).
  test "I3: a series correlates 1 with itself and -1 with its negation, at scale 6" do
    up_down = Enum.map(0..70, fn i -> if rem(i, 3) == 0, do: "100", else: "#{100 + i}" end)

    # The negation of a return series: a close series whose simple returns
    # are exactly the negative of the first one's.
    returns =
      up_down
      |> Enum.map(&Decimal.new/1)
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] -> b |> Decimal.sub(a) |> Decimal.div(a) end)

    negated =
      Enum.scan(returns, Decimal.new(1000), fn r, prev ->
        Decimal.mult(prev, Decimal.sub(Decimal.new(1), r))
      end)

    negated_closes =
      [%{date: Date.add(@as_of, -70), close: Decimal.new(1000)}] ++
        closes(Enum.map(negated, &Decimal.to_string/1))

    result =
      PortfolioMetrics.correlations(
        [{1, closes(up_down)}, {2, closes(up_down)}, {3, negated_closes}],
        @as_of
      )

    [pair_12, pair_13, pair_23] = result.pairs

    assert {pair_12.security_id_a, pair_12.security_id_b} == {1, 2}
    assert_scale_6(pair_12.value, "1.000000")
    assert pair_12.observations == 70
    assert pair_12.required == 60
    refute pair_12.insufficient_data

    assert {pair_13.security_id_a, pair_13.security_id_b} == {1, 3}
    assert_scale_6(pair_13.value, "-1.000000")
    assert_scale_6(pair_23.value, "-1.000000")

    assert result.window == %{start_date: Date.add(@as_of, -365), end_date: @as_of}
  end

  # Acceptance criteria (ADR-0047 §3, §5):
  # - A pair is computed over the days on which BOTH securities have a close.
  # - Below 60 overlapping observations the pair refuses with its count.
  # - A pair where either side never moves has no defined correlation: null,
  #   not a guess.
  test "a pair reads only the days both securities closed on, and refuses below 60" do
    a = closes(Enum.map(0..80, &"#{100 + rem(&1, 7)}"))
    # b closes only every other day.
    b = a |> Enum.take_every(2) |> Enum.map(&%{&1 | close: Decimal.add(&1.close, 5)})

    [pair] = PortfolioMetrics.correlations([{1, a}, {2, b}], @as_of).pairs
    assert pair.observations == 40
    assert pair.insufficient_data
    assert pair.value == nil

    flat = closes(List.duplicate("50", 81))
    [flat_pair] = PortfolioMetrics.correlations([{1, a}, {2, flat}], @as_of).pairs
    assert flat_pair.observations == 80
    refute flat_pair.insufficient_data
    assert flat_pair.value == nil
  end

  test "the declared window sets are exactly the keys the payload carries" do
    metrics = PortfolioMetrics.compute([], @as_of)
    labels = Enum.map(PortfolioMetrics.day_windows(), &elem(&1, 0))

    for key <- [:volatility, :max_drawdown, :risk_adjusted_return] do
      assert Enum.sort(Map.keys(metrics[key])) == Enum.sort(labels)
    end
  end
end
