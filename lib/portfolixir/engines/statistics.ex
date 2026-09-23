defmodule Portfolixir.Engines.Statistics do
  @moduledoc """
  The arithmetic the two metric engines of [ADR-0047](../../docs/decisions/0047-derived-metrics-per-security-and-per-view.md)
  share: `Portfolixir.Engines.PriceMetrics` (per security, FR-39) and
  `Portfolixir.Engines.PortfolioMetrics` (per portfolio or view, FR-40).

  Pure functions over Decimals. Two series are never mixed here — the callers
  decide what a series *is*; this module only knows how to take a deviation, a
  drawdown and a correlation of one.

  ## The float island

  `Decimal` has no square root, so the deviation and the correlation cross the
  contained float island of AR-3 through **`:math.sqrt/1` and nothing else**
  (ADR-0047 §4). `square_root/1` is that crossing, in one place for both
  engines: Decimals in, one float operation, `Decimal.from_float/1` out, and
  the callers round at scale 6 — the IRR solver's boundary convention. Nothing
  float is persisted.
  """

  @scale 6
  @zero Decimal.new(0)

  @doc "The scale every metric is rounded to on the way out (ADR-0047 §4)."
  @spec scale() :: pos_integer()
  def scale, do: @scale

  @doc "Rounds a figure to the metric scale; `nil` stays `nil`."
  @spec round_scale(Decimal.t() | nil) :: Decimal.t() | nil
  def round_scale(nil), do: nil
  def round_scale(%Decimal{} = value), do: Decimal.round(value, @scale)

  @doc "The arithmetic mean of a non-empty list of Decimals."
  @spec mean([Decimal.t(), ...]) :: Decimal.t()
  def mean([_ | _] = values) do
    values |> Enum.reduce(&Decimal.add/2) |> Decimal.div(Decimal.new(length(values)))
  end

  @doc """
  The **population** variance of a non-empty list — divided by the count, not
  by one less (ADR-0047 §3, the convention both engines state in their basis).
  """
  @spec population_variance([Decimal.t(), ...]) :: Decimal.t()
  def population_variance([_ | _] = values) do
    average = mean(values)

    values
    |> Enum.map(fn value -> value |> Decimal.sub(average) |> square() end)
    |> Enum.reduce(&Decimal.add/2)
    |> Decimal.div(Decimal.new(length(values)))
  end

  @doc """
  The population standard deviation of `returns`, annualized by
  `√observations_per_year`, rounded at scale 6. The annualization factor is
  the caller's statement about its series (§4): 252 for stored closes, 365
  for the calendar walk.
  """
  @spec annualized_deviation([Decimal.t(), ...], pos_integer()) :: Decimal.t()
  def annualized_deviation([_ | _] = returns, observations_per_year) do
    returns
    |> population_variance()
    |> Decimal.mult(observations_per_year)
    |> square_root()
    |> round_scale()
  end

  @doc """
  The Pearson correlation of two equally long return lists, rounded at scale
  6, or `nil` when either side has no variance — a series that never moves
  has no defined correlation with anything, and a guess would be a number
  the reader could act on.
  """
  @spec pearson([Decimal.t(), ...], [Decimal.t(), ...]) :: Decimal.t() | nil
  def pearson([_ | _] = xs, [_ | _] = ys) when length(xs) == length(ys) do
    mean_x = mean(xs)
    mean_y = mean(ys)
    dx = Enum.map(xs, &Decimal.sub(&1, mean_x))
    dy = Enum.map(ys, &Decimal.sub(&1, mean_y))

    covariance = dx |> Enum.zip(dy) |> Enum.map(fn {a, b} -> Decimal.mult(a, b) end) |> sum()
    spread_x = dx |> Enum.map(&square/1) |> sum()
    spread_y = dy |> Enum.map(&square/1) |> sum()

    if zero?(spread_x) or zero?(spread_y) do
      nil
    else
      # One square root of the product, so the island is crossed once per pair.
      covariance
      |> Decimal.div(square_root(Decimal.mult(spread_x, spread_y)))
      |> round_scale()
    end
  end

  @doc """
  The largest peak-to-trough decline of `points` (`%{date, value}`, ascending,
  at least one), as a ratio at scale 6 with its three dates.

  The running peak takes a value **equal** to it as well, so `peak_date` is the
  day the peak was last touched before the decline. `recovery_date` is the
  first point at or after the trough back at that peak, and `nil` while
  unrecovered; a drawdown of exactly 0 recovers on its own day — the series was
  never below its peak, which is a different statement from "not yet".
  """
  @spec drawdown([%{date: Date.t(), value: Decimal.t()}, ...]) :: map()
  def drawdown([first | _] = points) do
    worst =
      Enum.reduce(
        points,
        %{
          peak: first.value,
          peak_date: first.date,
          value: @zero,
          worst_peak: first.value,
          worst_peak_date: first.date,
          trough_date: first.date
        },
        &step_drawdown/2
      )

    %{
      value: round_scale(worst.value),
      peak_date: worst.worst_peak_date,
      trough_date: worst.trough_date,
      recovery_date: recovery_date(points, worst)
    }
  end

  defp step_drawdown(point, state) do
    state =
      if Decimal.compare(point.value, state.peak) != :lt,
        do: %{state | peak: point.value, peak_date: point.date},
        else: state

    decline =
      if positive?(state.peak),
        do: point.value |> Decimal.sub(state.peak) |> Decimal.div(state.peak),
        else: @zero

    if Decimal.compare(decline, state.value) == :lt do
      %{
        state
        | value: decline,
          worst_peak: state.peak,
          worst_peak_date: state.peak_date,
          trough_date: point.date
      }
    else
      state
    end
  end

  defp recovery_date(points, worst) do
    points
    |> Enum.find(fn point ->
      Date.compare(point.date, worst.trough_date) != :lt and
        Decimal.compare(point.value, worst.worst_peak) != :lt
    end)
    |> case do
      nil -> nil
      point -> point.date
    end
  end

  @doc """
  AR-3's float island, for the one operation `Decimal` does not have (§4).
  Unrounded — every caller rounds its own figure at scale 6.
  """
  @spec square_root(Decimal.t()) :: Decimal.t()
  def square_root(%Decimal{} = value) do
    value |> Decimal.to_float() |> :math.sqrt() |> Decimal.from_float()
  end

  defp square(value), do: Decimal.mult(value, value)
  defp sum(values), do: Enum.reduce(values, @zero, &Decimal.add/2)
  defp zero?(value), do: Decimal.equal?(value, @zero)
  defp positive?(%Decimal{} = value), do: Decimal.compare(value, @zero) == :gt
end
