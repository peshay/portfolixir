defmodule Portfolixir.Engines.PriceMetrics do
  @moduledoc """
  The per-security derived metrics of [ADR-0047](../../docs/decisions/0047-derived-metrics-per-security-and-per-view.md)
  §3 (FR-39, scope-ladder level (a)).

  This is an **engine** (architecture D2/P3): pure functions over an injected
  close series — no `Repo`, no clock, no config. `Portfolixir.Catalog.SecurityMetrics`
  loads the split-adjusted series (ADR-0028 §2) in the security's own currency
  and wraps the result in its computation basis.

  ## What each metric is measured over

  The input is **one** series: the security's own stored closes, already in the
  display basis, ascending by date. Nothing here converts a currency, reads a
  portfolio or touches a valuation walk — a price metric is a statement about
  the instrument (ADR-0047 §1, identity I7).

    * `sma_50` / `sma_200` — the mean of the newest `n` closes, with the latest
      close's distance to it. Refused below `n` closes.
    * `volatility` — the **population** standard deviation of the window's
      simple daily returns (divided by the observation count, not by one less),
      annualized by `√252` (§4). Refused below 20 return observations.
    * `max_drawdown` — the largest peak-to-trough decline in the window, with
      the day the peak was last touched, the day of the trough, and the first
      day back at the peak (`nil` while unrecovered). Refused below 2 closes.
    * `momentum` — the trailing return between the newest close on or before
      the period's start and the latest close. Refused when the series does not
      reach back to the period's start: a "12M" figure computed over one month
      of history is a confident wrong number, not a rough one.
    * `distance_to_extremes` — the 52-week high and low with their dates and
      the latest close's distance to each, over the same coverage rule.

  ## The two conventions a reader has to know

  **A gap produces no observation, never a zero** (§5). Returns are taken
  between *consecutive stored closes*; a day with no close is not carried
  forward and then differenced, because that manufactures a calm 0 % day and
  drags the standard deviation toward zero. **A close of zero or below is not
  a price at all** and is dropped before any metric reads the series, so one
  bad row cannot be the 52-week low in one figure and be skipped in the next;
  the `observations` counts say how many prices were actually read.

  **A metric refuses in both directions.** Momentum is refused when the series
  does not reach *back* to the period's start — a "12M" figure computed over
  one month of history is a confident wrong number, not a rough one — and
  equally when it does not reach *forward* into the period at all, which is
  what a security whose quotes stopped two years ago looks like. The moving
  averages are deliberately not bound that way: an SMA is defined over the
  last `n` closes rather than over a date range, so it stays a true statement
  about those closes, and their dates are in its `window`.

  **`observations` is how many inputs the metric actually read**: closes for the
  moving averages, the drawdown and the extremes; daily *returns* for the
  volatility (which is what §5's minimum counts); the two bounding closes for
  the momentum. It travels with every metric, including a refused one, so a
  gap marker says how far short it fell.

  `window` is the span the metric was measured over when it produced a number,
  and the span it was asked for when it refused.

  ## The float island

  `Decimal` has no square root, so the standard deviation crosses the contained
  float island of AR-3 through **`:math.sqrt/1` and nothing else** (§4, the
  amendment this record carries). Decimals in, one float operation, back out
  through `Decimal.from_float/1` and `Decimal.round/2` at scale 6 — the IRR
  solver's boundary convention. Nothing float is persisted. The crossing lives
  in `Portfolixir.Engines.Statistics.square_root/1`, shared with the
  portfolio engine so the island stays one operation in one place.

  ## `required`

  Every metric carries `required` — the minimum `observations` of §5 — in both
  states (§6 as amended 2026-09-19, #838): `n` for `sma_n`, 20 for the
  volatility, 2 for the drawdown and the momentum, 1 for the extremes. Where a
  metric also needs a close at each end of its window (momentum, extremes) the
  integer is the count floor only and the coverage rule stays in the basis.
  """

  alias Portfolixir.Engines.Statistics

  @trading_days_per_year 252

  # §3: the three windows every metric takes unless it names its own.
  @day_windows [{"30d", 30}, {"90d", 90}, {"365d", 365}]
  @month_windows [{"3m", 3}, {"6m", 6}, {"12m", 12}]
  @extremes_window_days 364

  # §5, the stated minima.
  @min_return_observations 20
  @min_drawdown_closes 2
  # The count floor only: momentum and the extremes ALSO need a close at each
  # end of the window, a coverage rule that stays in the basis's `gaps` prose
  # because a coverage condition is not a number (#838).
  @momentum_endpoints 2
  @min_extremes_closes 1

  @zero Decimal.new(0)

  @type point :: %{date: Date.t(), close: Decimal.t()}

  @doc """
  Every §3 metric over `points`, as of `as_of`.

  `points` is a list of `%{date, close}` — order is not assumed and closes
  dated after `as_of` are not read. The shape of the answer is the same
  whatever the series holds: a metric that cannot be computed is `nil` with
  `insufficient_data: true` and its observation count, never a guess and never
  an omitted key (§5, identity I5).
  """
  @spec compute([point()], Date.t()) :: map()
  def compute(points, %Date{} = as_of) when is_list(points) do
    series =
      points
      |> Enum.filter(&(Date.compare(&1.date, as_of) != :gt))
      |> Enum.filter(&positive?(&1.close))
      |> Enum.sort_by(& &1.date, Date)

    latest = List.last(series)

    %{
      latest: latest && %{date: latest.date, close: latest.close},
      sma_50: sma(series, latest, 50),
      sma_200: sma(series, latest, 200),
      volatility: by_day_window(series, as_of, &volatility/3),
      max_drawdown: by_day_window(series, as_of, &max_drawdown/3),
      momentum: by_month_window(series, latest, as_of),
      distance_to_extremes: extremes(series, latest, as_of)
    }
  end

  @doc "The annualization factor's basis, for the payload (§4, identity I4)."
  @spec trading_days_per_year() :: pos_integer()
  def trading_days_per_year, do: @trading_days_per_year

  @doc "The minimum return observations a volatility figure needs (§5)."
  @spec min_return_observations() :: pos_integer()
  def min_return_observations, do: @min_return_observations

  @doc "The day span of the 52-week extremes window (§3)."
  @spec extremes_window_days() :: pos_integer()
  def extremes_window_days, do: @extremes_window_days

  @doc "The labelled day windows every windowed metric is computed over (§3)."
  @spec day_windows() :: [{String.t(), pos_integer()}]
  def day_windows, do: @day_windows

  @doc "The labelled trailing-return periods (§3)."
  @spec month_windows() :: [{String.t(), pos_integer()}]
  def month_windows, do: @month_windows

  defp by_day_window(series, as_of, fun) do
    Map.new(@day_windows, fn {label, days} ->
      {label, fun.(slice(series, as_of, days), as_of, days)}
    end)
  end

  defp by_month_window(series, latest, as_of) do
    Map.new(@month_windows, fn {label, months} ->
      {label, momentum(series, latest, as_of, months)}
    end)
  end

  # ---------------------------------------------------------------- averages

  defp sma(series, latest, n) do
    count = length(series)

    if is_nil(latest) or count < n do
      %{
        value: nil,
        distance_pct: nil,
        window: nil,
        observations: count,
        required: n,
        insufficient_data: true
      }
    else
      used = Enum.take(series, -n)
      average = used |> Enum.map(& &1.close) |> Enum.reduce(&Decimal.add/2) |> divide(n)

      %{
        value: round_scale(average),
        distance_pct: ratio(latest.close, average),
        window: measured_window(used),
        observations: n,
        required: n,
        insufficient_data: false
      }
    end
  end

  # -------------------------------------------------------------- volatility

  defp volatility(slice, as_of, days) do
    returns = daily_returns(slice)
    observations = length(returns)

    if observations < @min_return_observations do
      %{
        value: nil,
        window: requested_window(as_of, days),
        observations: observations,
        required: @min_return_observations,
        insufficient_data: true
      }
    else
      %{
        value: Statistics.annualized_deviation(returns, @trading_days_per_year),
        window: measured_window(slice),
        observations: observations,
        required: @min_return_observations,
        insufficient_data: false
      }
    end
  end

  # §5: one observation per pair of CONSECUTIVE STORED closes. A day the series
  # does not carry is simply not a day here.
  defp daily_returns(slice) do
    slice
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.flat_map(fn [previous, current] ->
      if positive?(previous.close),
        do: [current.close |> Decimal.sub(previous.close) |> Decimal.div(previous.close)],
        else: []
    end)
  end

  # ---------------------------------------------------------------- drawdown

  defp max_drawdown([], as_of, days), do: refused_drawdown(as_of, days, 0)

  defp max_drawdown(slice, _as_of, _days) when length(slice) >= @min_drawdown_closes do
    slice
    |> Enum.map(&%{date: &1.date, value: &1.close})
    |> Statistics.drawdown()
    |> Map.merge(%{
      window: measured_window(slice),
      observations: length(slice),
      required: @min_drawdown_closes,
      insufficient_data: false
    })
  end

  defp max_drawdown(slice, as_of, days), do: refused_drawdown(as_of, days, length(slice))

  defp refused_drawdown(as_of, days, observations) do
    %{
      value: nil,
      peak_date: nil,
      trough_date: nil,
      recovery_date: nil,
      window: requested_window(as_of, days),
      observations: observations,
      required: @min_drawdown_closes,
      insufficient_data: true
    }
  end

  # ---------------------------------------------------------------- momentum

  defp momentum(series, latest, as_of, months) do
    start_date = Date.shift(as_of, month: -months)
    opening = newest_on_or_before(series, start_date)
    # The symmetric half of the coverage rule: a series that stops before the
    # period even begins resolves `opening` to the same point as `latest`, and
    # the honest answer is "no figure", not "0 % over zero days".
    reaches_forward? = not is_nil(latest) and Date.compare(latest.date, start_date) == :gt

    if is_nil(latest) or is_nil(opening) or not reaches_forward? or not positive?(opening.close) do
      %{
        value: nil,
        window: requested_window(as_of, start_date),
        observations: resolved_endpoints(latest, opening),
        required: @momentum_endpoints,
        insufficient_data: true
      }
    else
      %{
        value: ratio(latest.close, opening.close),
        window: %{start_date: opening.date, end_date: latest.date},
        observations: @momentum_endpoints,
        required: @momentum_endpoints,
        insufficient_data: false
      }
    end
  end

  defp resolved_endpoints(latest, opening) do
    Enum.count([latest, opening], &(not is_nil(&1)))
  end

  # ---------------------------------------------------------------- extremes

  defp extremes(series, latest, as_of) do
    start_date = Date.add(as_of, -@extremes_window_days)
    window_points = slice(series, as_of, @extremes_window_days)
    covered? = not is_nil(newest_on_or_before(series, start_date))

    if is_nil(latest) or window_points == [] or not covered? do
      %{
        high: nil,
        low: nil,
        distance_to_high_pct: nil,
        distance_to_low_pct: nil,
        window: requested_window(as_of, start_date),
        observations: length(window_points),
        required: @min_extremes_closes,
        insufficient_data: true
      }
    else
      high = extreme(window_points, :gt)
      low = extreme(window_points, :lt)

      %{
        high: %{close: high.close, date: high.date},
        low: %{close: low.close, date: low.date},
        distance_to_high_pct: ratio(latest.close, high.close),
        distance_to_low_pct: ratio(latest.close, low.close),
        window: measured_window(window_points),
        observations: length(window_points),
        required: @min_extremes_closes,
        insufficient_data: false
      }
    end
  end

  # Ties keep the EARLIEST date: the series is ascending and `reduce` only
  # replaces on a strict improvement.
  defp extreme([first | rest], direction) do
    Enum.reduce(rest, first, fn point, best ->
      if Decimal.compare(point.close, best.close) == direction, do: point, else: best
    end)
  end

  # ----------------------------------------------------------------- helpers

  defp slice(series, as_of, days) do
    from = Date.add(as_of, -days)
    Enum.filter(series, &(Date.compare(&1.date, from) != :lt))
  end

  defp newest_on_or_before(series, %Date{} = date) do
    series
    |> Enum.reverse()
    |> Enum.find(&(Date.compare(&1.date, date) != :gt))
  end

  defp measured_window(points) do
    %{start_date: List.first(points).date, end_date: List.last(points).date}
  end

  defp requested_window(as_of, days) when is_integer(days),
    do: %{start_date: Date.add(as_of, -days), end_date: as_of}

  defp requested_window(as_of, %Date{} = start_date),
    do: %{start_date: start_date, end_date: as_of}

  defp ratio(_value, baseline) when baseline == nil, do: nil

  defp ratio(value, baseline) do
    if positive?(baseline) do
      value |> Decimal.sub(baseline) |> Decimal.div(baseline) |> round_scale()
    else
      nil
    end
  end

  defp divide(sum, count), do: Decimal.div(sum, Decimal.new(count))

  defp round_scale(%Decimal{} = value), do: Statistics.round_scale(value)

  defp positive?(%Decimal{} = value), do: Decimal.compare(value, @zero) == :gt
  defp positive?(_value), do: false
end
