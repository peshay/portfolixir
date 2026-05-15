defmodule PortfolixirWeb.Components.SecurityChart do
  @moduledoc """
  Server-rendered SVG price chart for the security detail view.

  Inputs:
    * `:quotes` — `[%{date: Date, close: Decimal}]` in ascending date order
    * `:transactions` — `[%{date: Date, type: "buy"|"sell", price: Decimal}]`
    * `:log_scale?` — boolean, switches the Y axis to log10
    * `:show_transactions?` — boolean, toggles buy/sell markers
    * `:currency_code` — string label for the Y axis

  Reasoning: the repo has no JS bundler, so charts are produced as a
  single `<svg>` element. Interactivity (range/log) is handled at the
  LiveView level — this component is purely a renderer.
  """

  use Phoenix.Component

  @width 960
  @height 320
  @padding_top 16
  @padding_right 24
  @padding_bottom 28
  @padding_left 56

  attr(:quotes, :list, required: true)
  attr(:transactions, :list, default: [])
  attr(:log_scale?, :boolean, default: false)
  attr(:show_transactions?, :boolean, default: true)
  attr(:currency_code, :string, default: "")

  def chart(assigns) do
    geometry = build_geometry(assigns.quotes, assigns.log_scale?)

    assigns =
      assigns
      |> assign(:geometry, geometry)
      |> assign(:width, @width)
      |> assign(:height, @height)
      |> assign(:plot_left, @padding_left)
      |> assign(:plot_top, @padding_top)
      |> assign(:plot_right, @width - @padding_right)
      |> assign(:plot_bottom, @height - @padding_bottom)

    ~H"""
    <svg
      class={["security-chart", @log_scale? && "is-log"]}
      role="img"
      aria-label="Price chart"
      viewBox={"0 0 #{@width} #{@height}"}
      preserveAspectRatio="none"
      width="100%"
      height="320"
    >
      <%= if @geometry == :empty do %>
        <g class="no-quotes">
          <text x={div(@width, 2)} y={div(@height, 2)} text-anchor="middle">
            No price history yet.
          </text>
        </g>
      <% else %>
        <%= render_axes(assigns) %>

        <path
          class="quote-area"
          d={area_path(@geometry, @plot_left, @plot_top, @plot_right, @plot_bottom)}
        />

        <polyline
          class="quote-line"
          fill="none"
          stroke="currentColor"
          stroke-width="1.6"
          points={polyline_points(@geometry, @plot_left, @plot_top, @plot_right, @plot_bottom)}
        />

        <%= if @show_transactions? do %>
          <%= for marker <- transaction_markers(@transactions, @geometry, @plot_left, @plot_top, @plot_right, @plot_bottom) do %>
            <circle
              class={"tx-marker tx-#{marker.type}"}
              cx={marker.cx}
              cy={marker.cy}
              r="4"
            >
              <title><%= marker.label %></title>
            </circle>
          <% end %>
        <% end %>
      <% end %>
    </svg>
    """
  end

  # ---------------------------------------------------------------------------
  # Geometry
  # ---------------------------------------------------------------------------

  defp build_geometry([], _log_scale?), do: :empty

  defp build_geometry(quotes, log_scale?) do
    indexed = Enum.with_index(quotes)
    first_date = List.first(quotes).date
    last_date = List.last(quotes).date

    {y_min, y_max} =
      quotes
      |> Enum.map(&Decimal.to_float(&1.close))
      |> Enum.min_max()

    {y_min, y_max} = pad_range(y_min, y_max)
    {y_min, y_max} = if log_scale?, do: {safe_log(y_min), safe_log(y_max)}, else: {y_min, y_max}

    %{
      quotes: indexed,
      first_date: first_date,
      last_date: last_date,
      y_min: y_min,
      y_max: y_max,
      log_scale?: log_scale?
    }
  end

  defp pad_range(min, max) when min == max do
    pad = if min == 0.0, do: 1.0, else: abs(min) * 0.05
    {min - pad, max + pad}
  end

  defp pad_range(min, max) do
    range = max - min
    pad = range * 0.05
    {min - pad, max + pad}
  end

  defp safe_log(value) when value > 0, do: :math.log10(value)
  defp safe_log(_), do: 0.0

  defp polyline_points(:empty, _, _, _, _), do: ""

  defp polyline_points(geometry, x0, y0, x1, y1) do
    geometry
    |> point_coords(x0, y0, x1, y1)
    |> Enum.map(fn {x, y} -> "#{format_coord(x)},#{format_coord(y)}" end)
    |> Enum.join(" ")
  end

  defp area_path(:empty, _, _, _, _), do: ""

  defp area_path(geometry, x0, y0, x1, y1) do
    case point_coords(geometry, x0, y0, x1, y1) do
      [] ->
        ""

      [{xf, yf} | _] = points ->
        {xl, _yl} = List.last(points)

        body =
          points
          |> Enum.map_join(" ", fn {x, y} -> "L#{format_coord(x)},#{format_coord(y)}" end)

        "M#{format_coord(xf)},#{format_coord(yf)} " <>
          body <>
          " L#{format_coord(xl)},#{format_coord(y1)}" <>
          " L#{format_coord(xf)},#{format_coord(y1)} Z"
    end
  end

  defp point_coords(geometry, x0, y0, x1, y1) do
    plot_w = x1 - x0
    plot_h = y1 - y0

    Enum.map(geometry.quotes, fn {q, _idx} ->
      x = x0 + plot_w * x_fraction_for_date(q.date, geometry)
      y = y1 - plot_h * normalized_y(q.close, geometry)
      {x, y}
    end)
  end

  defp x_fraction_for_date(date, geometry) do
    span = date_span_days(geometry)
    if span == 0, do: 0.0, else: Date.diff(date, geometry.first_date) / span
  end

  defp date_span_days(geometry), do: Date.diff(geometry.last_date, geometry.first_date)

  defp normalized_y(%Decimal{} = close, geometry) do
    value =
      if geometry.log_scale?, do: safe_log(Decimal.to_float(close)), else: Decimal.to_float(close)

    range = geometry.y_max - geometry.y_min
    if range == 0, do: 0.5, else: (value - geometry.y_min) / range
  end

  defp format_coord(value) do
    value
    |> :erlang.float()
    |> Float.round(2)
    |> Float.to_string()
  end

  defp transaction_markers(transactions, geometry, x0, y0, x1, y1) do
    plot_w = x1 - x0
    plot_h = y1 - y0

    transactions
    |> Enum.filter(&within_range?(&1.date, geometry))
    |> Enum.map(fn tx ->
      x = x0 + plot_w * x_fraction_for_date(tx.date, geometry)
      close = close_for_date(geometry, tx.date) || tx.price
      y = y1 - plot_h * normalized_y(close, geometry)

      %{
        cx: format_coord(x),
        cy: format_coord(y),
        type: tx.type,
        label: "#{tx.type} on #{Date.to_iso8601(tx.date)} at #{Decimal.to_string(tx.price)}"
      }
    end)
  end

  defp within_range?(date, geometry) do
    Date.compare(date, geometry.first_date) != :lt and
      Date.compare(date, geometry.last_date) != :gt
  end

  defp close_for_date(geometry, date) do
    geometry.quotes
    |> Enum.reverse()
    |> Enum.find_value(fn {q, _idx} ->
      if Date.compare(q.date, date) != :gt, do: q.close
    end)
  end

  # ---------------------------------------------------------------------------
  # Axes (very lightweight — 4 horizontal grid lines + edge date labels)
  # ---------------------------------------------------------------------------

  defp render_axes(assigns) do
    ticks = 4

    y_values =
      for i <- 0..ticks do
        frac = i / ticks
        raw = assigns.geometry.y_min + (assigns.geometry.y_max - assigns.geometry.y_min) * frac
        value = if assigns.log_scale?, do: :math.pow(10, raw), else: raw
        y_pixel = assigns.plot_bottom - (assigns.plot_bottom - assigns.plot_top) * frac
        {value, y_pixel}
      end

    assigns = assign(assigns, :y_ticks, y_values)

    ~H"""
    <g class="chart-axes" stroke="currentColor" stroke-opacity="0.15">
      <%= for {_value, y} <- @y_ticks do %>
        <line x1={@plot_left} y1={y} x2={@plot_right} y2={y} />
      <% end %>
    </g>
    <g class="chart-axis-labels">
      <%= for {value, y} <- @y_ticks do %>
        <text x={@plot_left - 6} y={y} text-anchor="end" dominant-baseline="central">
          <%= format_axis_value(value) %>
        </text>
      <% end %>
      <text x={@plot_left} y={@height - 6} text-anchor="start">
        <%= Date.to_iso8601(@geometry.first_date) %>
      </text>
      <text x={@plot_right} y={@height - 6} text-anchor="end">
        <%= Date.to_iso8601(@geometry.last_date) %>
      </text>
    </g>
    """
  end

  defp format_axis_value(value) when is_float(value) do
    cond do
      value >= 1000 -> :erlang.float_to_binary(value, decimals: 0)
      value >= 1 -> :erlang.float_to_binary(value, decimals: 2)
      true -> :erlang.float_to_binary(value, decimals: 4)
    end
  end

  defp format_axis_value(value), do: to_string(value)
end
