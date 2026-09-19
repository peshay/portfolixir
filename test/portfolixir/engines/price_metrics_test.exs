defmodule Portfolixir.Engines.PriceMetricsTest do
  use ExUnit.Case, async: true

  alias Portfolixir.Engines.PriceMetrics

  @as_of ~D[2026-09-19]

  # A series of consecutive daily closes ending on `last`, oldest first.
  defp series(closes, last \\ @as_of) do
    first = Date.add(last, -(length(closes) - 1))

    closes
    |> Enum.with_index()
    |> Enum.map(fn {close, index} ->
      %{date: Date.add(first, index), close: Decimal.new(close)}
    end)
  end

  defp flat(count, close \\ "100"), do: series(List.duplicate(close, count))

  defp assert_decimal(actual, expected) do
    assert Decimal.equal?(actual, Decimal.new(expected)),
           "expected #{expected}, got #{inspect(actual)}"
  end

  # User story (FR-39, ADR-0047 §3):
  # As the operator's agent researching one security,
  # I want its moving averages, volatility, drawdown, momentum and distance to
  # the 52-week extremes over its own stored close series,
  # so that I can describe the instrument without recomputing it from the
  # quote history on every run.
  #
  # Acceptance criteria:
  # - Every metric of §3 is present, each with its own window and observation
  #   count (§6).
  # - A flat series has volatility exactly 0 and maximum drawdown exactly 0 —
  #   nothing moved, so nothing is reported as movement.
  # - The moving averages equal the flat level and the distance to each is 0.
  test "computes every §3 metric over the close series, with a window and an observation count each" do
    metrics = PriceMetrics.compute(flat(400), @as_of)

    assert_decimal(metrics.sma_50.value, "100")
    assert_decimal(metrics.sma_50.distance_pct, "0")
    assert metrics.sma_50.observations == 50
    refute metrics.sma_50.insufficient_data
    assert metrics.sma_50.window.end_date == @as_of
    assert metrics.sma_50.window.start_date == Date.add(@as_of, -49)

    assert_decimal(metrics.sma_200.value, "100")
    assert metrics.sma_200.observations == 200

    for period <- ~w(30d 90d 365d) do
      assert_decimal(metrics.volatility[period].value, "0")
      refute metrics.volatility[period].insufficient_data
      assert metrics.volatility[period].window.end_date == @as_of

      assert_decimal(metrics.max_drawdown[period].value, "0")
      refute metrics.max_drawdown[period].insufficient_data
    end

    assert metrics.volatility["30d"].observations == 30
    assert metrics.volatility["90d"].observations == 90
    assert metrics.volatility["365d"].observations == 365

    for period <- ~w(3m 6m 12m) do
      assert_decimal(metrics.momentum[period].value, "0")
      assert metrics.momentum[period].observations == 2
      refute metrics.momentum[period].insufficient_data
    end

    assert metrics.momentum["3m"].window.start_date == Date.shift(@as_of, month: -3)

    extremes = metrics.distance_to_extremes
    assert_decimal(extremes.high.close, "100")
    assert_decimal(extremes.low.close, "100")
    assert_decimal(extremes.distance_to_high_pct, "0")
    assert_decimal(extremes.distance_to_low_pct, "0")
    assert extremes.observations == 365
    refute extremes.insufficient_data
  end

  # User story (ADR-0047 §11, identity I2):
  # As the reviewer of a money-domain figure,
  # I want the maximum drawdown pinned on two series whose answer is known
  # exactly,
  # so that a refactor that changes the arithmetic fails the build.
  #
  # Acceptance criteria:
  # - A monotonically rising series has a maximum drawdown of exactly 0.
  # - A series that halves and recovers has exactly -0.5, with the peak, the
  #   trough and the recovery day named.
  test "I2: maximum drawdown is exactly 0 on a rising series and exactly -0.5 on one that halves" do
    rising = PriceMetrics.compute(series(Enum.map(1..31, &"#{100 + &1}")), @as_of)
    assert_decimal(rising.max_drawdown["30d"].value, "0")

    halved =
      PriceMetrics.compute(
        series(List.duplicate("100", 10) ++ ["50"] ++ List.duplicate("100", 20)),
        @as_of
      )

    drawdown = halved.max_drawdown["30d"]
    assert_decimal(drawdown.value, "-0.5")
    # The peak is last touched on the day before the halving, the trough is
    # the halved close, and the recovery is the first close back at the peak.
    assert drawdown.peak_date == Date.add(@as_of, -21)
    assert drawdown.trough_date == Date.add(@as_of, -20)
    assert drawdown.recovery_date == Date.add(@as_of, -19)
  end

  # Acceptance criteria (ADR-0047 §3):
  # - A drawdown the series has not recovered from carries a null recovery day
  #   rather than the last day of the window.
  test "an unrecovered drawdown carries a null recovery date" do
    metrics =
      PriceMetrics.compute(series(List.duplicate("100", 10) ++ List.duplicate("60", 21)), @as_of)

    drawdown = metrics.max_drawdown["30d"]
    assert_decimal(drawdown.value, "-0.4")
    assert drawdown.recovery_date == nil
  end

  # User story (ADR-0047 §5, identity I5):
  # As the operator's agent,
  # I want a metric with too little history to say so instead of answering,
  # so that a thin series never produces a confident wrong number.
  #
  # Acceptance criteria:
  # - Below its stated minimum a metric is null, carries insufficient_data and
  #   still reports the observations it had.
  # - The refusal names the window that was asked for.
  test "I5: below its minimum a metric refuses with a gap marker and its observation count" do
    metrics = PriceMetrics.compute(flat(10), @as_of)

    assert metrics.sma_50.value == nil
    assert metrics.sma_50.insufficient_data
    assert metrics.sma_50.observations == 10

    assert metrics.volatility["30d"].value == nil
    assert metrics.volatility["30d"].insufficient_data
    assert metrics.volatility["30d"].observations == 9

    assert metrics.momentum["12m"].value == nil
    assert metrics.momentum["12m"].insufficient_data
    assert metrics.momentum["12m"].window.start_date == Date.shift(@as_of, month: -12)

    assert metrics.distance_to_extremes.high == nil
    assert metrics.distance_to_extremes.insufficient_data
  end

  # User story (ADR-0047 §5):
  # As the operator holding a thinly quoted security,
  # I want a day without a stored close to produce no return observation,
  # so that carrying a price forward never manufactures a calm 0 % day.
  #
  # Acceptance criteria:
  # - The return count is the number of consecutive stored closes minus one,
  #   not the number of calendar days in the window.
  test "a day with no stored close produces no return observation, never a zero" do
    dated =
      for offset <- Enum.to_list(30..10//-1) ++ Enum.to_list(4..0//-1) do
        %{date: Date.add(@as_of, -offset), close: Decimal.new("100")}
      end

    metrics = PriceMetrics.compute(dated, @as_of)

    # 26 stored closes in the window, so 25 returns — not the 30 a
    # carried-forward series would have produced.
    assert metrics.volatility["30d"].observations == 25
    assert metrics.max_drawdown["30d"].observations == 26
  end

  # User story (ADR-0047 §3, §4):
  # As the reviewer,
  # I want the annualized volatility of a series with known daily returns to
  # equal the population standard deviation times the square root of 252,
  # so that the annualization factor and the estimator are both pinned.
  #
  # Acceptance criteria:
  # - Returns alternating +0.25 and -0.2 (a series oscillating between 80 and
  #   100) give the stated figure at scale 6.
  test "volatility is the population standard deviation of simple daily returns, annualized by √252" do
    closes = for i <- 0..30, do: if(rem(i, 2) == 0, do: "80", else: "100")
    metrics = PriceMetrics.compute(series(closes), @as_of)

    # 30 returns alternating +0.25 and -0.2 (15 each). mean = 0.025; every
    # deviation is ±0.225, so the population variance is exactly 0.050625 and
    # σ exactly 0.225. Annualized: √(0.050625 × 252) = 3.571764 at scale 6.
    assert_decimal(metrics.volatility["30d"].value, "3.571764")
    assert metrics.volatility["30d"].observations == 30
  end

  # User story (ADR-0047 §3):
  # As the operator,
  # I want the momentum figures to differ the two closes that bound the period
  # and to name both dates,
  # so that a trailing return can be checked against the series it came from.
  #
  # Acceptance criteria:
  # - A series that rises from 100 to 125 over the period reports 0.25.
  # - The window names the two closes that were differenced.
  test "momentum is the trailing return between the two closes that bound the period" do
    start_date = Date.shift(@as_of, month: -3)
    days = Date.diff(@as_of, start_date)

    closes =
      for i <- 0..days do
        if i == 0, do: "100", else: "125"
      end

    metrics = PriceMetrics.compute(series(closes), @as_of)

    assert_decimal(metrics.momentum["3m"].value, "0.25")
    assert metrics.momentum["3m"].window.start_date == start_date
    assert metrics.momentum["3m"].window.end_date == @as_of
  end

  # User story (ADR-0047 §3):
  # As the operator,
  # I want the 52-week high and low with their dates and the latest close's
  # distance to each,
  # so that I can see where the price stands inside its own year.
  #
  # Acceptance criteria:
  # - High, low and both distances are reported with the dates they fell on.
  test "distance_to_extremes reports the 52-week high and low with their dates" do
    closes = List.duplicate("100", 363) ++ ["200"] ++ ["150"]
    metrics = PriceMetrics.compute(series(closes), @as_of)

    extremes = metrics.distance_to_extremes
    assert_decimal(extremes.high.close, "200")
    assert extremes.high.date == Date.add(@as_of, -1)
    assert_decimal(extremes.low.close, "100")
    assert extremes.low.date == Date.add(@as_of, -364)
    assert_decimal(extremes.distance_to_high_pct, "-0.25")
    assert_decimal(extremes.distance_to_low_pct, "0.5")
  end

  # Acceptance criteria (ADR-0047 §6):
  # - An empty series answers every metric as a refusal with zero
  #   observations, never a crash and never a zero.
  test "an empty series refuses every metric rather than answering zero" do
    metrics = PriceMetrics.compute([], @as_of)

    assert metrics.latest == nil
    assert metrics.sma_50.value == nil
    assert metrics.sma_50.observations == 0
    assert metrics.volatility["30d"].insufficient_data
    assert metrics.max_drawdown["365d"].insufficient_data
    assert metrics.momentum["6m"].insufficient_data
    assert metrics.distance_to_extremes.insufficient_data
  end

  # Acceptance criteria (ADR-0047 §3):
  # - The latest close is the newest one on or before as_of; a close dated
  #   after as_of is not read.
  test "the latest close is the newest one on or before as_of" do
    metrics = PriceMetrics.compute(series(["100", "110", "120"], Date.add(@as_of, 5)), @as_of)

    assert metrics.latest == nil

    metrics = PriceMetrics.compute(series(["100", "110", "120"], @as_of), @as_of)
    assert_decimal(metrics.latest.close, "120")
    assert metrics.latest.date == @as_of
  end
end
