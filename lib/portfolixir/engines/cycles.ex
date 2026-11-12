defmodule Portfolixir.Engines.Cycles do
  @moduledoc """
  The halving cycles' past (FR-58, [ADR-0060](../../docs/decisions/0060-halving-cycles-tops-and-lows-by-drawdown-projected-as-a-band.md)
  §1 to §3): the windows between a security's confirmed halvings, each
  window's top and low, and the six intervals between halvings, tops and lows
  with their n, minimum and maximum. Levels (a) and (b) of the scope ladder.

  The **engine** half of the engine/shell split (AR-2), as
  `Portfolixir.Engines.PriceMetrics` is for the per-security metrics: pure
  functions over a close series and a list of halvings; the shell
  (`Portfolixir.Catalog.SecurityCycles`) reads them and wraps the answer in
  its computation basis.

  ## The windows (§1)

  A window runs from one confirmed halving's date up to the next one's,
  **excluding the later date**: the close dated on a halving day belongs to
  the window that starts there. The last window, from the last confirmed
  halving to the newest close, is **open**. A closed window is **partial**
  when it starts more than 7 days before the series' first stored close,
  **complete** otherwise; a closed window without a single close is
  `no_closes` and is neither. A day without a close is skipped, never filled,
  and a close of zero or below is not a price.

  ## A window's top and low (§2)

  The peak and the trough of the window's maximum drawdown, through the one
  drawdown routine both metric engines share (`Statistics.drawdown/1`): the
  running peak takes an equal close, so among equal highest closes the peak is
  the **latest**; a deeper decline is strictly lower, so among equal maximum
  drawdowns the **earliest** trough wins, with its peak (ADR-0058 §2's tie
  rules). Not the highest close: that rule ignores order and picks a late
  rally above the old top, after the low (2020–2024).

  - A **partial** window has no top (`before_first_close`); its low is
    marked `partial`.
  - An **open** window's top is not final, and it is an **anchor** once the
    window's maximum drawdown so far reaches 20 %, compared exactly (the low
    at most 0.80 × the top). Its low is never final while the window is open
    and is shown as `low_so_far`.
  - A window whose closes never fell below their running peak names no top
    and no low (`no_decline`): a decline of exactly 0 is no episode.

  ## The intervals (§3)

  Per relation and window, the calendar days between its two ends and, where
  the relation has one, the change (`low / top − 1`) or the factor
  (`later / earlier`), each at scale 6. An observation exists when both ends
  do; an end is a final top or low, or the open window's anchored top. One
  with an end that is not final is `provisional`, one with a partial end is
  `partial`. Nothing is averaged and nothing is fitted.
  """

  alias Portfolixir.Engines.Statistics

  @partial_days 7
  @anchor_threshold Decimal.new("0.20")
  @anchor_ratio Decimal.sub(Decimal.new(1), @anchor_threshold)
  @zero Decimal.new(0)

  # ADR-0060 §3's table, in its order: {relation, from end, to end, figure}.
  # `:next` takes the end from the following window.
  @relations [
    {:halving_to_top, :halving_start, :top, :days},
    {:top_to_low, :top, :low, :change},
    {:low_to_top, :low, {:next, :top}, :factor},
    {:top_to_top, :top, {:next, :top}, :factor},
    {:low_to_low, :low, {:next, :low}, :factor},
    {:low_to_next_halving, :low, :halving_end, :days}
  ]

  @typedoc "A stored close in the display basis, ascending by date."
  @type close :: %{date: Date.t(), close: Decimal.t()}

  @typedoc "A halving event as the engine reads it."
  @type halving :: %{
          height: pos_integer(),
          date: Date.t(),
          date_end: Date.t() | nil,
          confirmed: boolean()
        }

  @doc "The relations of §3, in the record's order."
  @spec relations() :: [atom()]
  def relations, do: Enum.map(@relations, &elem(&1, 0))

  @doc "The fall from an open window's top that anchors it (§2), as a ratio."
  @spec anchor_threshold() :: Decimal.t()
  def anchor_threshold, do: @anchor_threshold

  @doc "The days after a window's start within which its first close makes it complete (§1)."
  @spec partial_days() :: pos_integer()
  def partial_days, do: @partial_days

  @doc """
  The windows, the intervals, the counts and the next halving of `series`
  (`%{date, close}`) over `halvings` (`%{height, date, date_end, confirmed}`).

  Windows are formed from the confirmed halvings in height order; the next
  halving is the first unconfirmed one above them, or `nil`.
  """
  @spec compute([close()], [halving()]) :: map()
  def compute(series, halvings) when is_list(series) and is_list(halvings) do
    closes =
      series
      |> Enum.filter(&(Decimal.compare(&1.close, @zero) == :gt))
      |> Enum.sort_by(& &1.date, Date)

    confirmed = halvings |> Enum.filter(& &1.confirmed) |> Enum.sort_by(& &1.height)
    series_first = closes |> List.first() |> date_of()

    windows =
      confirmed
      |> Enum.zip(tl_or_empty(confirmed) ++ [nil])
      |> Enum.map(fn {start, stop} -> window(start, stop, closes, series_first) end)

    %{
      windows: windows,
      intervals: intervals(windows),
      counts: counts(windows),
      next_halving: next_halving(halvings, confirmed),
      first_close: series_first,
      last_close: closes |> List.last() |> date_of()
    }
  end

  defp tl_or_empty([]), do: []
  defp tl_or_empty([_ | rest]), do: rest

  defp date_of(nil), do: nil
  defp date_of(%{date: date}), do: date

  defp next_halving(halvings, confirmed) do
    last = confirmed |> List.last() |> then(&(&1 && &1.height)) || 0

    halvings
    |> Enum.reject(& &1.confirmed)
    |> Enum.filter(&(&1.height > last))
    |> Enum.min_by(& &1.height, fn -> nil end)
    |> case do
      nil -> nil
      next -> %{height: next.height, date: next.date, date_end: Map.get(next, :date_end)}
    end
  end

  # ------------------------------------------------------------------ windows

  defp window(start, stop, closes, series_first) do
    points = Enum.filter(closes, &inside?(&1.date, start.date, stop && stop.date))
    open? = is_nil(stop)

    before_series? =
      not is_nil(series_first) and Date.diff(series_first, start.date) > @partial_days

    partial? = before_series? and points != []

    kind =
      cond do
        open? -> :open
        points == [] -> :no_closes
        partial? -> :partial
        true -> :complete
      end

    Map.merge(
      %{
        start: start.date,
        start_height: start.height,
        end: stop && stop.date,
        end_height: stop && stop.height,
        kind: kind,
        final: not open?,
        partial: partial?,
        closes: length(points),
        first_close: points |> List.first() |> date_of(),
        last_close: points |> List.last() |> date_of(),
        max_gap_days: max_gap_days(points)
      },
      extremes(points, open?, partial?)
    )
  end

  defp inside?(date, from, nil), do: Date.compare(date, from) != :lt

  defp inside?(date, from, to),
    do: Date.compare(date, from) != :lt and Date.compare(date, to) == :lt

  defp max_gap_days([_, _ | _] = points) do
    points
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [a, b] -> Date.diff(b.date, a.date) end)
    |> Enum.max()
  end

  defp max_gap_days(_points), do: nil

  defp extremes([], open?, _partial?) do
    %{
      top: nil,
      top_reason: :no_closes,
      low: nil,
      low_reason: :no_closes,
      low_so_far: nil,
      max_drawdown: nil,
      anchor_reason: if(open?, do: :no_top_yet)
    }
  end

  defp extremes(points, open?, partial?) do
    {top_point, low_point, value} = extreme_points(points)

    if is_nil(top_point) do
      %{
        top: nil,
        top_reason: :no_decline,
        low: nil,
        low_reason: if(open?, do: :window_open, else: :no_decline),
        low_so_far: nil,
        max_drawdown: value,
        anchor_reason: if(open?, do: :no_top_yet)
      }
    else
      top = top(top_point, low_point, open?, partial?)

      %{
        top: top,
        top_reason: if(partial?, do: :before_first_close),
        low: if(open?, do: nil, else: low(low_point, partial?)),
        low_reason: if(open?, do: :window_open),
        low_so_far:
          if(open?, do: %{date: low_point.date, close: low_point.close, partial: partial?}),
        max_drawdown: value,
        anchor_reason: if(open? and not match?(%{anchor: true}, top), do: :no_top_yet)
      }
    end
  end

  # §2 through the shared routine: the peak and the trough of the maximum
  # drawdown, with its tie rules, or no points when the decline is exactly 0.
  defp extreme_points(points) do
    drawdown = points |> Enum.map(&%{date: &1.date, value: &1.close}) |> Statistics.drawdown()

    case Statistics.without_zero_episode(drawdown) do
      %{peak_date: nil} ->
        {nil, nil, drawdown.value}

      %{peak_date: peak, trough_date: trough} ->
        {Enum.find(points, &(&1.date == peak)), Enum.find(points, &(&1.date == trough)),
         drawdown.value}
    end
  end

  defp top(_point, _low, _open?, true = _partial?), do: nil

  defp top(point, low, open?, false) do
    %{
      date: point.date,
      close: point.close,
      final: not open?,
      anchor: not open? or anchored?(point, low)
    }
  end

  # §2: the low at most (1 − 0.20) × the top, exactly — no division, no
  # rounding before the comparison.
  defp anchored?(top, low),
    do: Decimal.compare(low.close, Decimal.mult(top.close, @anchor_ratio)) != :gt

  defp low(point, partial?),
    do: %{date: point.date, close: point.close, final: true, partial: partial?}

  # ---------------------------------------------------------------- intervals

  defp intervals(windows) do
    following = tl_or_empty(windows) ++ [nil]
    pairs = Enum.zip(windows, following)
    waiting? = Enum.any?(windows, &(&1.anchor_reason == :no_top_yet))

    Map.new(@relations, fn {relation, from, to, figure} ->
      observations =
        Enum.flat_map(pairs, fn pair ->
          with %{} = a <- end_of(from, pair),
               %{} = b <- end_of(to, pair) do
            [observation(a, b, figure)]
          else
            nil -> []
          end
        end)

      {relation, summary(observations, figure, ends_on_top?(to) and waiting?)}
    end)
  end

  # §2: the relations whose later end is a top wait for the open window's
  # anchor; a relation from a top to a low needs the final low anyway.
  defp ends_on_top?(to), do: to in [:top, {:next, :top}]

  defp end_of({:next, _which}, {_window, nil}), do: nil
  defp end_of({:next, which}, {_window, next}), do: end_of(which, {next, nil})

  defp end_of(:halving_start, {w, _next}),
    do: %{
      event: :halving,
      window_start: w.start,
      date: w.start,
      close: nil,
      final: true,
      partial: false
    }

  defp end_of(:halving_end, {%{end: nil}, _next}), do: nil

  defp end_of(:halving_end, {w, _next}),
    do: %{
      event: :halving,
      window_start: w.start,
      date: w.end,
      close: nil,
      final: true,
      partial: false
    }

  defp end_of(:top, {%{top: %{anchor: true} = top} = w, _next}),
    do: %{
      event: :top,
      window_start: w.start,
      date: top.date,
      close: top.close,
      final: top.final,
      partial: false
    }

  defp end_of(:top, _pair), do: nil
  defp end_of(:low, {%{low: nil}, _next}), do: nil

  defp end_of(:low, {%{low: low} = w, _next}),
    do: %{
      event: :low,
      window_start: w.start,
      date: low.date,
      close: low.close,
      final: true,
      partial: low.partial
    }

  defp observation(a, b, figure) do
    base = %{
      from: Map.take(a, [:event, :window_start, :date, :close]),
      to: Map.take(b, [:event, :window_start, :date, :close]),
      days: Date.diff(b.date, a.date),
      provisional: not (a.final and b.final),
      partial: a.partial or b.partial
    }

    case figure do
      :days ->
        base

      :change ->
        Map.put(
          base,
          :change,
          b.close |> Decimal.div(a.close) |> Decimal.sub(1) |> Statistics.round_scale()
        )

      :factor ->
        Map.put(base, :factor, b.close |> Decimal.div(a.close) |> Statistics.round_scale())
    end
  end

  defp summary(observations, figure, waiting?) do
    %{
      n: length(observations),
      days: span(Enum.map(observations, & &1.days), &Kernel.min/2, &Kernel.max/2),
      change: if(figure == :change, do: decimal_span(observations, :change)),
      factor: if(figure == :factor, do: decimal_span(observations, :factor)),
      observations: observations,
      reason: if(waiting?, do: :no_top_yet)
    }
  end

  defp span([], _min, _max), do: nil

  defp span([first | rest], min, max),
    do: %{min: Enum.reduce(rest, first, min), max: Enum.reduce(rest, first, max)}

  defp decimal_span(observations, key) do
    observations
    |> Enum.map(&Map.fetch!(&1, key))
    |> span(&Decimal.min/2, &Decimal.max/2)
  end

  defp counts(windows) do
    %{
      cycles_complete: Enum.count(windows, &(&1.kind == :complete)),
      cycles_partial: Enum.count(windows, &(&1.kind == :partial)),
      cycle_open: Enum.any?(windows, &(&1.kind == :open))
    }
  end
end
