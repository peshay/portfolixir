defmodule PortfolixirWeb.Dashboard.Widgets.Line do
  @moduledoc """
  The two small line drawings the D4 widgets share (ADR-0062 §12; planning
  board `ux-design-2026-11-21-sprint31/01` ①; idea board
  `ux-design-2026-11-21-idea-i56/01`, sizes S and M; Sprint 31 D4):

    * `sparkline/1` — the S size's and the compact form's line under a
      figure: decorative (`aria-hidden`), its figure is the text above it;
    * `chart/1` — the M size's value line, with its lowest and highest
      value on the axis and its first and last date under it, described
      for a screen reader by its first and last point.

  Both draw the values they are handed and nothing else: the points are
  the source read's, in its order, thinned to about `@max_points` with
  the first, the last, the lowest and the highest always kept, so the
  line reaches the two values the axis names (Sprint 31 closing act,
  money lens MO5). The geometry is computed from the
  `Decimal` values; floats exist only as coordinates and are never stored
  (as `PortfolixirWeb.Portfolio.StackedChart` does).
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias PortfolixirWeb.Format
  alias PortfolixirWeb.PrivacyMode

  @max_points 160

  @spark_width 120
  @spark_height 32

  @chart_width 480
  @chart_height 180
  @chart_left 64
  @chart_right 8
  @chart_top 8
  @chart_bottom 24

  attr(:values, :list, required: true, doc: "the source's values in date order (Decimal)")
  attr(:role, :string, default: nil)

  @doc "A decorative line of `values` (S and compact forms)."
  def sparkline(assigns) do
    assigns =
      assign(assigns,
        d: path(assigns.values, {0, @spark_width}, {2, @spark_height - 2}),
        width: @spark_width,
        height: @spark_height
      )

    ~H"""
    <svg
      :if={@d}
      class="widget-spark"
      data-role={@role}
      viewBox={"0 0 #{@width} #{@height}"}
      preserveAspectRatio="none"
      aria-hidden="true"
      focusable="false"
    >
      <path d={@d} fill="none" stroke="currentColor" stroke-width="1.5" vector-effect="non-scaling-stroke" />
    </svg>
    """
  end

  attr(:points, :list,
    required: true,
    doc: "`%{date: Date.t(), value: Decimal.t()}` in date order"
  )

  attr(:currency, :string, required: true)
  attr(:id, :string, required: true)

  @doc """
  The M size's value line: the period's lowest and highest value as the
  axis's two labels, the first and the last date under the plot.
  """
  def chart(assigns) do
    points = thin(assigns.points)
    values = Enum.map(points, & &1.value)
    # The axis states the period's own lowest and highest value, every
    # day's, not only the drawn points'.
    all = assigns.points |> Enum.map(& &1.value) |> Enum.filter(&match?(%Decimal{}, &1))

    assigns =
      assign(assigns,
        thinned: points,
        d:
          path(
            values,
            {@chart_left, @chart_width - @chart_right},
            {@chart_top, @chart_height - @chart_bottom}
          ),
        low: all != [] && Enum.min(all, Decimal),
        high: all != [] && Enum.max(all, Decimal),
        width: @chart_width,
        height: @chart_height,
        left: @chart_left,
        right: @chart_width - @chart_right,
        top: @chart_top,
        bottom: @chart_height - @chart_bottom,
        privacy?: PrivacyMode.on?()
      )

    ~H"""
    <svg
      :if={@d}
      id={@id}
      class="widget-line"
      role="img"
      aria-label={aria(@thinned, @currency, @privacy?)}
      viewBox={"0 0 #{@width} #{@height}"}
      preserveAspectRatio="none"
      data-role="performance-line"
      data-points={length(@thinned)}
    >
      <g stroke="currentColor" stroke-opacity="0.15">
        <line x1={@left} y1={@top} x2={@right} y2={@top} />
        <line x1={@left} y1={@bottom} x2={@right} y2={@bottom} />
      </g>
      <path
        d={@d}
        fill="none"
        stroke="currentColor"
        stroke-width="2"
        vector-effect="non-scaling-stroke"
        class="widget-line__path"
      />
      <g class="chart-axis-labels">
        <text
          :if={not @privacy?}
          class="chart-axis-y"
          x={@left - 6}
          y={@top}
          text-anchor="end"
          dominant-baseline="hanging"
          data-role="line-high"
        ><%= Format.money(@high) %></text>
        <text
          :if={not @privacy?}
          class="chart-axis-y"
          x={@left - 6}
          y={@bottom}
          text-anchor="end"
          data-role="line-low"
        ><%= Format.money(@low) %></text>
        <text class="chart-axis-x" x={@left} y={@height - 4} text-anchor="start" data-role="line-first">
          <%= Format.date(hd(@thinned).date) %>
        </text>
        <text class="chart-axis-x" x={@right} y={@height - 4} text-anchor="end" data-role="line-last">
          <%= Format.date(List.last(@thinned).date) %>
        </text>
      </g>
    </svg>
    """
  end

  defp aria(points, currency, privacy?) do
    first = hd(points)
    last = List.last(points)

    if privacy? do
      gettext("Value line from %{from} to %{to}",
        from: Format.date(first.date),
        to: Format.date(last.date)
      )
    else
      gettext("Value line from %{from} (%{start} %{currency}) to %{to} (%{end} %{currency})",
        from: Format.date(first.date),
        start: Format.money(first.value),
        to: Format.date(last.date),
        end: Format.money(last.value),
        currency: currency
      )
    end
  end

  @doc """
  `@max_points` of `items`, evenly spaced, the first and the last always
  kept, and beside them the lowest and the highest value (a `Decimal`, or
  a point's `value`), in their order: at most two more. Fewer are
  returned as they are.
  """
  @spec thin(list()) :: list()
  def thin(items) when length(items) <= @max_points, do: items

  def thin(items) do
    count = length(items)
    step = (count - 1) / (@max_points - 1)
    even = for i <- 0..(@max_points - 1), into: MapSet.new(), do: round(i * step)
    tuple = List.to_tuple(items)

    even
    |> MapSet.union(extremes(items))
    |> Enum.sort()
    |> Enum.map(&elem(tuple, &1))
  end

  # The indexes of the lowest and the highest value among `items`.
  defp extremes(items) do
    numbered =
      items
      |> Enum.with_index()
      |> Enum.filter(fn {item, _index} -> match?(%Decimal{}, value_of(item)) end)

    case numbered do
      [] ->
        MapSet.new()

      _some ->
        {_low, low} = Enum.min_by(numbered, &value_of(elem(&1, 0)), Decimal)
        {_high, high} = Enum.max_by(numbered, &value_of(elem(&1, 0)), Decimal)
        MapSet.new([low, high])
    end
  end

  defp value_of(%{value: value}), do: value
  defp value_of(value), do: value

  # The SVG path through `values` (Decimal) across `{x0, x1}` and, top to
  # bottom, `{y0, y1}`; nil with fewer than two values or none a number.
  defp path(values, {x0, x1}, {y0, y1}) do
    values = values |> thin() |> Enum.filter(&match?(%Decimal{}, &1))

    case values do
      [_, _ | _] ->
        low = Enum.min(values, Decimal)
        high = Enum.max(values, Decimal)
        span = Decimal.sub(high, low)
        steps = length(values) - 1

        values
        |> Enum.with_index()
        |> Enum.map_join(" ", fn {value, i} ->
          x = x0 + (x1 - x0) * i / steps
          y = y1 - (y1 - y0) * fraction(value, low, span)
          "#{if i == 0, do: "M", else: "L"}#{coord(x)} #{coord(y)}"
        end)

      _short ->
        nil
    end
  end

  # A flat line sits in the middle.
  defp fraction(value, low, span) do
    if Decimal.equal?(span, 0),
      do: 0.5,
      else: value |> Decimal.sub(low) |> Decimal.div(span) |> Decimal.to_float()
  end

  defp coord(value), do: :erlang.float_to_binary(value / 1, decimals: 1)
end
