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

  ## The analog band's parts (§4)

  One part per relation for each coming event, read from that relation alone
  and applied to its current anchor. The **next low** is the open window's
  low: `top_to_low` from the open window's anchored top (`no_top_yet`
  before it anchors), `low_to_low` from the last final low. The **next top**
  is the top of the first window without an anchored top: `halving_to_top`
  from that window's halving (the next halving's window once the open top
  is anchored), `top_to_top` from the last anchored top, `low_to_top` from
  the last final low with no top after it (`low_not_final` while the open
  window's top is anchored and its low is not).

  - **Time:** the anchor's date + the relation's minimum to maximum days;
    for `halving_to_top`, the halving window's first day + the minimum to
    its last day + the maximum.
  - **Price:** the anchor's close × the factors from the last factor f₂ to
    f₂^(ln f₂ / ln f₁) (`log_step/2`), in either order; `top_to_low` uses
    1 + change. Where no step is defined, the minimum to the maximum of the
    stored factors (`price_rule: :min_max`, `price_reason: :no_log_step`).
    `halving_to_top` borrows `top_to_top`'s price side and is absent
    whenever that part is.
  - **Minimum data:** two observations for the time side and two factors
    for the price side, or the part is absent (`too_few_observations`) with
    its `n_time` and `n_price`. A part whose window is one day or whose price
    range is one price is absent too (`zero_width`): it would name the single
    date or price §8 rules out.

  ## One band per event, its state, the cones (§5 to §7)

  The event's band is the **hull** of its present parts; `agree` is the
  price range where every part with a price side of its own overlaps
  (`one_price_relation` with fewer than two such parts, `parts_disjoint`
  where the range is empty or one price). Nothing is averaged and nothing is
  intersected into the band. Each band and each part carries its state, read
  from the stored closes against the last one: `open`, `running`, `reached`
  (a close inside the window within the price range, inclusive), `missed`,
  with `window_ended`; none (`input_after_window`) where a close that went
  into it lies inside its window. The cones continue each line from its last
  anchor into its own relation's part. The projection is `not_a_forecast`.

  The log step is AR-3's fourth float operation (`:math.log/1`, with the
  already named `:math.pow/2`), registered in
  `test/invariants/float_island_test.exs`.
  """

  alias Portfolixir.Engines.Statistics

  @partial_days 7
  # ADR-0060 §11: the close a window is indexed to is at most this many days old.
  @halving_close_days 7
  @anchor_threshold Decimal.new("0.20")
  @anchor_ratio Decimal.sub(Decimal.new(1), @anchor_threshold)
  @zero Decimal.new(0)
  # A Decimal whose leading digit sits at 10^e for e in -307..307 converts to
  # a double without overflow or underflow (as in `Statistics`).
  @float_exponent_bound 307

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

    intervals = intervals(windows)
    next_halving = next_halving(halvings, confirmed)

    %{
      windows: windows,
      intervals: intervals,
      counts: counts(windows),
      next_halving: next_halving,
      first_close: series_first,
      last_close: closes |> List.last() |> date_of(),
      projection: projection(windows, intervals, next_halving, closes)
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

  # ------------------------------------------------------------------ aligned
  # Sprint 29 H6: ADR-0060 §11, `include=aligned`.

  @doc """
  The windows laid over each other from their halving (ADR-0060 §11,
  `include=aligned`): per window of `windows` (`compute/2`'s), in their
  order, its `start` and `start_height`, the `base` close — the last close of
  `series` on or before the halving date, at most #{@halving_close_days} days
  old — and every close inside the window as the calendar `days` since the
  halving and its `index`, close / base at scale 6; no date, which the
  window's `start` + `days` gives (the closing act's order lens on Lane H:
  the date repeated it in some 40 % of the payload). A window
  without a base is left out: `base: nil`, `points: []`, `reason:
  :no_halving_close`. Positive closes only, as in `compute/2`.
  """
  @spec aligned([close()], [map()]) :: [map()]
  def aligned(series, windows) when is_list(series) and is_list(windows) do
    closes =
      series
      |> Enum.filter(&(Decimal.compare(&1.close, @zero) == :gt))
      |> Enum.sort_by(& &1.date, Date)

    Enum.map(windows, fn window ->
      head = %{start: window.start, start_height: window.start_height}

      case halving_close(closes, window.start) do
        nil ->
          Map.merge(head, %{base: nil, points: [], reason: :no_halving_close})

        base ->
          points =
            for point <- closes, inside?(point.date, window.start, window.end) do
              %{
                days: Date.diff(point.date, window.start),
                index: point.close |> Decimal.div(base.close) |> Statistics.round_scale()
              }
            end

          Map.merge(head, %{base: base, points: points, reason: nil})
      end
    end)
  end

  @doc "How old the close a window is indexed to may be, in days (ADR-0060 §11)."
  @spec halving_close_days() :: pos_integer()
  def halving_close_days, do: @halving_close_days

  defp halving_close(closes, halving) do
    closes
    |> Enum.filter(
      &(Date.compare(&1.date, halving) != :gt and
          Date.diff(halving, &1.date) <= @halving_close_days)
    )
    |> List.last()
  end

  # --------------------------------------------------------------- projection
  # Sprint 29 H5: ADR-0060 §4, the analog band's parts.

  @doc """
  The log step of ADR-0060 §4: f₂^(ln f₂ / ln f₁) for the last two factors
  of a relation, oldest first, at scale 6 — "it goes on as last time".

  AR-3's float island, its fourth named operation (`:math.log/1`, amended
  2026-11-12) with the already named `:math.pow/2`: Decimals in,
  `Decimal.from_float/1` then `Decimal.round/2` at scale 6 out, nothing
  float kept. Total, as `Statistics.square_root/1` is: `nil` where no step
  is defined — ln f₁ or ln f₂ is 0 (a factor of exactly 1), the two differ
  in sign (the factor crossed 1), a factor is zero or below or outside the
  double range, or the step leaves the double range or rounds to 0. A step
  that grows the factor (|ln f₂| > |ln f₁|) is taken as it comes.
  """
  @spec log_step(Decimal.t(), Decimal.t()) :: Decimal.t() | nil
  def log_step(%Decimal{} = f1, %Decimal{} = f2) do
    with {:ok, x1} <- float_of(f1),
         {:ok, x2} <- float_of(f2),
         {a, b} = {:math.log(x1), :math.log(x2)},
         true <- a != 0.0 and b != 0.0 and a > 0.0 == b > 0.0,
         {:ok, step} <- power(x2, b / a),
         factor = step |> Decimal.from_float() |> Statistics.round_scale(),
         :gt <- Decimal.compare(factor, @zero) do
      factor
    else
      _undefined -> nil
    end
  end

  # A positive Decimal whose leading digit sits at 10^e for e in -307..307
  # converts to a double without overflow or underflow (Statistics' bound).
  defp float_of(%Decimal{coef: coef}) when not is_integer(coef), do: :error
  defp float_of(%Decimal{coef: 0}), do: :error
  defp float_of(%Decimal{sign: -1}), do: :error

  defp float_of(%Decimal{coef: coef, exp: exp} = value) do
    leading = exp + length(Integer.digits(coef)) - 1

    if leading >= -@float_exponent_bound and leading <= @float_exponent_bound,
      do: {:ok, Decimal.to_float(value)},
      else: :error
  end

  defp power(base, exponent) do
    {:ok, :math.pow(base, exponent)}
  rescue
    ArithmeticError -> :error
  end

  # §4's table: the next low is the open window's low (never final while
  # the window is open); the next top is the top of the first window without
  # an anchored top — the open window's own, or, once it is anchored, the
  # next window's, which starts at the next halving.
  defp projection(windows, intervals, next_halving, closes) do
    open = Enum.find(windows, &(&1.kind == :open))
    open_top = open && anchored_top(open)
    last_low = windows |> Enum.reverse() |> Enum.find_value(&final_low/1)
    last_top = windows |> Enum.reverse() |> Enum.find_value(&anchored_top/1)
    top_is_next? = not is_nil(open_top)

    top_to_top = own_part(:top_to_top, last_top, intervals)

    low_to_top =
      if top_is_next?,
        do: own_part(:low_to_top, nil, intervals, :low_not_final),
        else: own_part(:low_to_top, last_low, intervals)

    low_parts = [
      own_part(:top_to_low, open_top, intervals, :no_top_yet),
      own_part(:low_to_low, last_low, intervals)
    ]

    top_parts = [
      halving_part(halving_anchor(top_is_next?, open, next_halving), top_to_top, intervals),
      top_to_top,
      low_to_top
    ]

    next_low =
      :next_low
      |> event(low_parts, closes)
      |> Map.put(:low_so_far, open && open.low_so_far)

    next_top = event(:next_top, top_parts, closes)

    %{
      kind: :analog_band,
      not_a_forecast: true,
      next_low: next_low,
      next_top: next_top,
      cones: cones(next_low, next_top, last_top, last_low)
    }
  end

  # ---------------------------------------------- the band, agree, the state
  # Sprint 29 H5: ADR-0060 §5, §7.

  # §5: one band per event, the hull of its present parts; `agree` where the
  # parts with a price side of their own overlap. §7: the band's and every
  # part's state.
  defp event(name, parts, closes) do
    parts = Enum.map(parts, &Map.merge(&1, state_of(&1, closes)))

    case Enum.filter(parts, & &1.window) do
      [] ->
        %{
          event: name,
          band: nil,
          reason: :no_parts,
          agree: nil,
          agree_reason: nil,
          state: nil,
          state_reason: nil,
          window_ended: nil,
          parts: parts
        }

      present ->
        band = %{
          window: %{
            from: present |> Enum.map(& &1.window.from) |> Enum.min(Date),
            to: present |> Enum.map(& &1.window.to) |> Enum.max(Date)
          },
          price: %{
            from: present |> Enum.map(& &1.price.from) |> Enum.reduce(&Decimal.min/2),
            to: present |> Enum.map(& &1.price.to) |> Enum.reduce(&Decimal.max/2)
          },
          inputs_until: present |> Enum.map(& &1.inputs_until) |> latest()
        }

        {agree, agree_reason} = agree(present)

        %{event: name, band: band, reason: nil, agree: agree, agree_reason: agree_reason}
        |> Map.merge(state_of(band, closes))
        |> Map.put(:parts, parts)
    end
  end

  # The highest lower end to the lowest upper end of the parts with a price
  # side of their own, when that range is not empty. A range of one price is
  # empty here: a shade on one price would be the single figure §8 rules out.
  defp agree(present) do
    case Enum.filter(present, & &1.own_price) do
      [_, _ | _] = own ->
        from = own |> Enum.map(& &1.price.from) |> Enum.reduce(&Decimal.max/2)
        to = own |> Enum.map(& &1.price.to) |> Enum.reduce(&Decimal.min/2)

        if Decimal.compare(from, to) == :lt,
          do: {%{from: from, to: to}, nil},
          else: {nil, :parts_disjoint}

      _fewer ->
        {nil, :one_price_relation}
    end
  end

  # §7, read from the stored closes against the last one, so the same
  # closes give the same state: `open` before the window starts, `reached`
  # once a close inside the window lies within the price range (inclusive),
  # `running` while the window has started without one, `missed` once it has
  # ended without one. A band whose inputs reach into its window has none.
  defp state_of(%{window: nil}, _closes),
    do: %{state: nil, state_reason: nil, window_ended: nil}

  defp state_of(%{window: window, price: price, inputs_until: inputs_until}, closes) do
    last = closes |> List.last() |> date_of()

    if inputs_until && Date.compare(inputs_until, window.from) != :lt do
      %{state: nil, state_reason: :input_after_window, window_ended: nil}
    else
      ended? = not is_nil(last) and Date.compare(last, window.to) != :lt

      state =
        cond do
          is_nil(last) or Date.compare(last, window.from) == :lt -> :open
          Enum.any?(closes, &inside_band?(&1, window, price)) -> :reached
          ended? -> :missed
          true -> :running
        end

      %{state: state, state_reason: nil, window_ended: ended?}
    end
  end

  defp inside_band?(close, window, price) do
    Date.compare(close.date, window.from) != :lt and Date.compare(close.date, window.to) != :gt and
      Decimal.compare(close.close, price.from) != :lt and
      Decimal.compare(close.close, price.to) != :gt
  end

  # §6: each line continues as a cone from its last anchor into its own
  # relation's part. "Top ↔ Tief" goes into `top_to_low` after a top and
  # into `low_to_top` after a final low; `halving_to_top` has no line.
  defp cones(next_low, next_top, last_top, last_low) do
    after_top? =
      not is_nil(last_top) and
        (is_nil(last_low) or Date.compare(last_top.date, last_low.date) == :gt)

    zigzag =
      if after_top?,
        do: find_part(next_low, :top_to_low),
        else: find_part(next_top, :low_to_top)

    [
      cone(:top_low, zigzag),
      cone(:top_top, find_part(next_top, :top_to_top)),
      cone(:low_low, find_part(next_low, :low_to_low))
    ]
  end

  defp find_part(event, relation), do: Enum.find(event.parts, &(&1.relation == relation))

  defp cone(line, %{window: nil} = part),
    do: %{
      line: line,
      relation: part.relation,
      apex: nil,
      window: nil,
      price: nil,
      reason: part.reason
    }

  defp cone(line, part),
    do: %{
      line: line,
      relation: part.relation,
      apex: Map.take(part.anchor, [:event, :date, :close]),
      window: part.window,
      price: part.price,
      reason: nil
    }

  defp anchored_top(%{top: %{anchor: true} = top} = w),
    do: %{
      event: :top,
      window_start: w.start,
      date: top.date,
      close: top.close,
      final: top.final,
      partial: false
    }

  defp anchored_top(_window), do: nil

  defp final_low(%{low: %{} = low} = w),
    do: %{
      event: :low,
      window_start: w.start,
      date: low.date,
      close: low.close,
      final: true,
      partial: low.partial
    }

  defp final_low(_window), do: nil

  # `halving_to_top`'s time side starts from a halving's window: the next
  # halving's (ADR-0059 §6) once the open window's top is anchored, the open
  # window's own halving (one day) before that.
  defp halving_anchor(true = _top_is_next?, _open, nil), do: {:absent, :no_next_halving}

  defp halving_anchor(true, _open, next),
    do:
      {:ok,
       %{
         event: :halving,
         height: next.height,
         date: next.date,
         date_end: next.date_end || next.date,
         confirmed: false
       }}

  defp halving_anchor(false, nil, _next), do: {:absent, :no_anchor}

  defp halving_anchor(false, open, _next),
    do:
      {:ok,
       %{
         event: :halving,
         height: open.start_height,
         date: open.start,
         date_end: open.start,
         confirmed: true
       }}

  # A part with a price side of its own: time from the anchor's date + the
  # relation's minimum to maximum days, price from the anchor's close × the
  # factor range of `price_side/1`.
  defp own_part(relation, anchor, intervals, missing \\ :no_anchor) do
    summary = Map.fetch!(intervals, relation)
    factors = Enum.map(summary.observations, &factor_of(relation, &1))

    base =
      relation
      |> base_part(anchor, summary.observations, length(factors))
      |> Map.merge(%{days: summary.days, own_price: true, price_from: nil})

    cond do
      is_nil(anchor) ->
        absent(base, missing)

      length(factors) < 2 ->
        absent(base, :too_few_observations)

      true ->
        side = price_side(factors)

        base
        |> Map.merge(%{
          window: %{
            from: Date.add(anchor.date, summary.days.min),
            to: Date.add(anchor.date, summary.days.max)
          },
          price: %{
            from: anchor.close |> Decimal.mult(side.factor.from) |> Statistics.round_scale(),
            to: anchor.close |> Decimal.mult(side.factor.to) |> Statistics.round_scale()
          },
          factor: side.factor,
          factors_used: side.used,
          price_rule: side.rule,
          price_reason: side.reason
        })
        |> with_width()
    end
  end

  # `halving_to_top` has no price relation of its own: its price side is
  # `top_to_top`'s, and it is absent whenever that part is (board 07 ⑥).
  defp halving_part(anchor, lender, intervals) do
    summary = intervals.halving_to_top

    {anchor, missing} =
      case anchor do
        {:ok, anchor} -> {anchor, nil}
        {:absent, reason} -> {nil, reason}
      end

    base =
      :halving_to_top
      |> base_part(anchor, summary.observations, lender.n_price)
      |> Map.merge(%{days: summary.days, own_price: false, price_from: :top_to_top})

    cond do
      is_nil(anchor) ->
        absent(base, missing)

      not is_nil(lender.reason) ->
        absent(base, lender.reason)

      summary.n < 2 ->
        absent(base, :too_few_observations)

      true ->
        base
        |> Map.merge(%{
          window: %{
            from: Date.add(anchor.date, summary.days.min),
            to: Date.add(anchor.date_end, summary.days.max)
          },
          price: lender.price,
          factor: lender.factor,
          factors_used: lender.factors_used,
          price_rule: lender.price_rule,
          price_reason: lender.price_reason,
          provisional: base.provisional or lender.provisional,
          partial: base.partial or lender.partial,
          inputs_until: latest([base.inputs_until, lender.inputs_until])
        })
        |> with_width()
    end
  end

  defp base_part(relation, anchor, observations, n_price) do
    %{
      relation: relation,
      anchor: anchor,
      n_time: length(observations),
      n_price: n_price,
      time_rule: :min_max,
      window: nil,
      price: nil,
      factor: nil,
      factors_used: [],
      price_rule: nil,
      price_reason: nil,
      provisional: Enum.any?(observations, & &1.provisional) or not_final?(anchor),
      partial: Enum.any?(observations, & &1.partial) or match?(%{partial: true}, anchor),
      inputs_until: inputs_until(anchor, observations),
      reason: nil
    }
  end

  defp not_final?(%{event: :halving, confirmed: confirmed}), do: not confirmed
  defp not_final?(%{final: final}), do: not final
  defp not_final?(nil), do: false

  # The latest date of a close that went into the part: its anchor's and its
  # observations' ends that carry a close (a halving date is not a close).
  defp inputs_until(anchor, observations) do
    anchor_date = if match?(%{close: %Decimal{}}, anchor), do: anchor.date

    observations
    |> Enum.flat_map(fn o -> [o.from, o.to] end)
    |> Enum.filter(&match?(%{close: %Decimal{}}, &1))
    |> Enum.map(& &1.date)
    |> Enum.concat([anchor_date])
    |> latest()
  end

  defp latest(dates) do
    case Enum.reject(dates, &is_nil/1) do
      [] -> nil
      dates -> Enum.max(dates, Date)
    end
  end

  defp absent(part, reason), do: %{part | reason: reason, inputs_until: nil}

  # A part whose window is one day, or whose price range is one price, would
  # name a single date or a single price, the point forecast §8 rules out:
  # it is absent, as a part with one observation is (§4 "Minimum data").
  defp with_width(%{window: window, price: price} = part) do
    if Date.compare(window.from, window.to) == :eq or Decimal.equal?(price.from, price.to),
      do: %{
        part
        | reason: :zero_width,
          window: nil,
          price: nil,
          factor: nil,
          factors_used: [],
          price_rule: nil,
          price_reason: nil,
          inputs_until: nil
      },
      else: part
  end

  defp factor_of(:top_to_low, observation), do: Decimal.add(1, observation.change)
  defp factor_of(_relation, observation), do: observation.factor

  # §4's price side over a relation's factors, oldest first: from the last
  # factor f₂ to the log step, in either order; the minimum to the maximum
  # of every stored factor where no step is defined, with its reason.
  defp price_side(factors) do
    [f1, f2] = Enum.take(factors, -2)

    case log_step(f1, f2) do
      nil ->
        low = Enum.reduce(factors, &Decimal.min/2)
        high = Enum.reduce(factors, &Decimal.max/2)

        %{
          rule: :min_max,
          reason: :no_log_step,
          used: [low, high],
          factor: %{from: low, to: high}
        }

      step ->
        %{
          rule: :log_step_v1,
          reason: nil,
          used: [f1, f2],
          factor: %{from: Decimal.min(f2, step), to: Decimal.max(f2, step)}
        }
    end
  end
end
