defmodule PortfolixirWeb.Components.SecurityChart do
  @moduledoc """
  Server-rendered SVG time-series chart — the one shared chart component
  (ADR-0022). Born as the security detail price chart; the portfolio value
  and TTWROR charts render through it too.

  Inputs:
    * `:quotes` — `[%{date: Date, close: Decimal}]` in ascending date order.
      A quote may carry an optional `:label` string, which then replaces the
      raw close as the crosshair tooltip's display value (e.g. "+8.0% ·
      1,080.00 EUR" so a tooltip can show two series at once).
    * `:transactions` — `[%{date: Date, type: "buy"|"sell", price: Decimal}]`
    * `:log_scale?` — boolean, switches the Y axis to log10
    * `:percent_mode?` — boolean, re-bases the series relative to the first
      close and shows a percent axis (the security detail's % view)
    * `:value_mode` — `:absolute` (default) or `:percent_values`, for series
      whose values already ARE percentages (e.g. cumulative TTWROR): no
      re-basing, but the axis and payload format as signed percent
    * `:zero_line?` — boolean, draws a horizontal zero line when 0 is inside
      the value range (e.g. the TTWROR gain/loss boundary)
    * `:show_transactions?` — boolean, toggles buy/sell markers
    * `:currency_code` — string label for the Y axis
    * `:aria_label` — accessible name of the rendered svg

  Reasoning: the repo has no JS bundler, so charts are produced as a
  single `<svg>` element. Interactivity (range/log) is handled at the
  LiveView level — this component is purely a renderer.
  """

  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  @width 960
  @height 320
  @padding_top 16
  @padding_right 24
  @padding_bottom 28
  @padding_left 56

  attr(:quotes, :list, required: true)
  attr(:transactions, :list, default: [])
  attr(:overlays, :list, default: [])
  attr(:log_scale?, :boolean, default: false)
  attr(:percent_mode?, :boolean, default: false)
  attr(:value_mode, :atom, default: :absolute, values: [:absolute, :percent_values])
  attr(:zero_line?, :boolean, default: false)
  attr(:show_transactions?, :boolean, default: true)
  attr(:currency_code, :string, default: "")
  # nil resolves to the localized "Price chart" at render time — a compile-time
  # attr default cannot go through gettext with the caller's locale.
  attr(:aria_label, :string, default: nil)

  def chart(assigns) do
    geometry =
      build_geometry(assigns.quotes, assigns.log_scale?, percent_mode?: assigns.percent_mode?)

    plot_left = @padding_left
    plot_top = @padding_top
    plot_right = @width - @padding_right
    plot_bottom = @height - @padding_bottom

    payload = build_payload(geometry, assigns, plot_left, plot_top, plot_right, plot_bottom)
    chart_id = "chart-" <> Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)

    assigns =
      assigns
      |> assign(:geometry, geometry)
      |> assign(:width, @width)
      |> assign(:height, @height)
      |> assign(:plot_left, plot_left)
      |> assign(:plot_top, plot_top)
      |> assign(:plot_right, plot_right)
      |> assign(:plot_bottom, plot_bottom)
      |> assign(:chart_id, chart_id)
      |> assign(:percent_axis?, assigns.percent_mode? or assigns.value_mode == :percent_values)
      |> assign(:payload_json, Jason.encode!(payload, escape: :html_safe))
      |> assign(:aria_label, assigns.aria_label || gettext("Price chart"))

    ~H"""
    <div class="chart-frame" id={@chart_id} phx-hook="ChartCrosshair" data-chart-id={@chart_id}>
      <svg
        class={["security-chart", @log_scale? && "is-log"]}
        role="img"
        aria-label={@aria_label}
        viewBox={"0 0 #{@width} #{@height}"}
        preserveAspectRatio="xMidYMid meet"
        width="100%"
      >
        <%= if @geometry == :empty do %>
          <g class="no-quotes">
            <text x={div(@width, 2)} y={div(@height, 2)} text-anchor="middle">
              <%= gettext("No price history yet.") %>
            </text>
          </g>
        <% else %>
          <%= render_axes(assigns) %>

          <line
            :if={@zero_line? and zero_in_range?(@geometry)}
            class="chart-zeroline"
            x1={@plot_left}
            y1={zero_y(@geometry, @plot_top, @plot_bottom)}
            x2={@plot_right}
            y2={zero_y(@geometry, @plot_top, @plot_bottom)}
          />

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

          <%= for overlay <- @overlays do %>
            <polyline
              class={overlay.class}
              fill="none"
              stroke-width="1.3"
              points={overlay_points(overlay, @geometry, @plot_left, @plot_top, @plot_right, @plot_bottom)}
            >
              <title><%= overlay.label %></title>
            </polyline>
          <% end %>

          <%= if @show_transactions? do %>
            <%= for marker <- transaction_markers(@transactions, @geometry, @plot_left, @plot_top, @plot_right, @plot_bottom) do %>
              <path class={"tx-marker tx-#{marker.type}"} d={marker.d}>
                <title><%= marker.label %></title>
              </path>
            <% end %>
          <% end %>
        <% end %>
      </svg>
      <script type="application/json" data-chart-payload data-chart-id={@chart_id}><%= Phoenix.HTML.raw(@payload_json) %></script>
    </div>
    """
  end

  defp build_payload(:empty, assigns, _x0, _y0, _x1, _y1) do
    %{
      points: [],
      txs: [],
      view: %{width: @width, height: @height},
      currency: assigns.currency_code,
      mode: payload_mode(assigns)
    }
  end

  defp build_payload(geometry, assigns, x0, y0, x1, y1) do
    points =
      geometry
      |> point_coords(x0, y0, x1, y1)
      |> Enum.zip(geometry.quotes)
      |> Enum.map(fn {{x, y}, {q, _idx}} ->
        [Date.to_iso8601(q.date), point_display(q), round2(x), round2(y)]
      end)

    txs =
      if assigns.show_transactions? do
        build_tx_payload(assigns.transactions, geometry, x0, y0, x1, y1)
      else
        []
      end

    %{
      points: points,
      txs: txs,
      view: %{width: @width, height: @height},
      currency: assigns.currency_code,
      mode: payload_mode(assigns)
    }
  end

  defp payload_mode(%{percent_mode?: true}), do: "percent"
  defp payload_mode(%{value_mode: :percent_values}), do: "percent"
  defp payload_mode(_), do: "absolute"

  # The crosshair tooltip's display value: a quote's explicit `:label` wins
  # (lets a caller show two series in one tooltip line), else the raw close.
  defp point_display(%{label: label}) when is_binary(label), do: label
  defp point_display(q), do: chart_decimal_string(q.close)

  # The zero line (gain/loss boundary) on the raw value scale; only rendered
  # when 0 actually sits inside the padded range.
  defp zero_in_range?(geometry) do
    geometry.y_min < 0.0 and geometry.y_max > 0.0
  end

  defp zero_y(geometry, plot_top, plot_bottom) do
    fraction = (0.0 - geometry.y_min) / (geometry.y_max - geometry.y_min)
    format_coord(plot_bottom - (plot_bottom - plot_top) * fraction)
  end

  defp build_tx_payload(transactions, geometry, x0, y0, x1, y1) do
    plot_w = x1 - x0
    plot_h = y1 - y0

    transactions
    |> Enum.filter(&trade_transaction?/1)
    |> Enum.filter(&within_range?(&1.date, geometry))
    |> Enum.flat_map(fn tx ->
      x = x0 + plot_w * x_fraction_for_date(tx.date, geometry)
      close = close_for_date(geometry, tx.date) || tx.price

      if is_nil(chart_float(close)) do
        []
      else
        y = y1 - plot_h * normalized_y(close, geometry)

        [
          %{
            date: Date.to_iso8601(tx.date),
            type: tx.type,
            quantity: chart_decimal_string(tx.quantity),
            price: chart_decimal_string(tx.price),
            x: round2(x),
            y: round2(y)
          }
        ]
      end
    end)
  end

  defp round2(value), do: Float.round(:erlang.float(value), 2)

  # ---------------------------------------------------------------------------
  # Geometry
  # ---------------------------------------------------------------------------

  defp build_geometry(quotes, log_scale?, opts) do
    quotes = Enum.filter(quotes, &valid_quote?/1)

    if quotes == [] do
      :empty
    else
      build_geometry_from_quotes(quotes, log_scale?, opts)
    end
  end

  defp build_geometry_from_quotes(quotes, log_scale?, opts) do
    percent_mode? = Keyword.get(opts, :percent_mode?, false)
    indexed = Enum.with_index(quotes)
    first_date = List.first(quotes).date
    last_date = List.last(quotes).date
    first_close = chart_float(List.first(quotes).close)

    raw_values =
      if percent_mode? and first_close != 0.0 do
        Enum.map(quotes, fn q ->
          (chart_float(q.close) - first_close) / first_close * 100.0
        end)
      else
        Enum.map(quotes, &chart_float(&1.close))
      end

    {y_min, y_max} = Enum.min_max(raw_values)
    {y_min, y_max} = pad_range(y_min, y_max)

    log_scale? = log_scale? and not percent_mode?

    {y_min, y_max} =
      if log_scale?, do: {safe_log(y_min), safe_log(y_max)}, else: {y_min, y_max}

    %{
      quotes: indexed,
      first_date: first_date,
      last_date: last_date,
      first_close: first_close,
      y_min: y_min,
      y_max: y_max,
      log_scale?: log_scale?,
      percent_mode?: percent_mode?
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

  defp polyline_points(geometry, x0, y0, x1, y1) do
    geometry
    |> point_coords(x0, y0, x1, y1)
    |> Enum.map(fn {x, y} -> "#{format_coord(x)},#{format_coord(y)}" end)
    |> Enum.join(" ")
  end

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

  defp normalized_y(close, geometry) do
    raw = chart_float(close) || 0.0

    value =
      cond do
        geometry.percent_mode? and geometry.first_close != 0.0 ->
          (raw - geometry.first_close) / geometry.first_close * 100.0

        geometry.log_scale? ->
          safe_log(raw)

        true ->
          raw
      end

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
    |> Enum.filter(&trade_transaction?/1)
    |> Enum.filter(&within_range?(&1.date, geometry))
    |> Enum.flat_map(fn tx ->
      x = x0 + plot_w * x_fraction_for_date(tx.date, geometry)
      close = close_for_date(geometry, tx.date) || tx.price

      if is_nil(chart_float(close)) do
        []
      else
        y = y1 - plot_h * normalized_y(close, geometry)

        [
          %{
            d: marker_path(tx.type, x, y),
            type: tx.type,
            label:
              "#{tx.type} on #{Date.to_iso8601(tx.date)} at #{chart_decimal_string(tx.price)}"
          }
        ]
      end
    end)
  end

  defp trade_transaction?(%{type: type}), do: type in ["buy", "sell"]
  defp trade_transaction?(_), do: false

  # Shape carries the transaction direction (UX-DR7, issue 645): the SVG is
  # role="img", so the <title> fallback inside a marker is unreachable and a
  # hue-only circle leaves no readable channel. Apex-first paths: ▲ for buy,
  # ▼ for sell.
  defp marker_path("buy", x, y) do
    "M#{format_coord(x)},#{format_coord(y - 5)} " <>
      "L#{format_coord(x + 4.5)},#{format_coord(y + 3.5)} " <>
      "L#{format_coord(x - 4.5)},#{format_coord(y + 3.5)} Z"
  end

  defp marker_path("sell", x, y) do
    "M#{format_coord(x)},#{format_coord(y + 5)} " <>
      "L#{format_coord(x + 4.5)},#{format_coord(y - 3.5)} " <>
      "L#{format_coord(x - 4.5)},#{format_coord(y - 3.5)} Z"
  end

  defp valid_quote?(%{date: %Date{}, close: close}), do: not is_nil(chart_float(close))
  defp valid_quote?(_), do: false

  defp chart_decimal_string(value) do
    case chart_decimal(value) do
      nil -> "—"
      decimal -> Decimal.to_string(decimal, :normal)
    end
  end

  defp chart_float(value) do
    case chart_decimal(value) do
      nil -> nil
      decimal -> Decimal.to_float(decimal)
    end
  end

  defp chart_decimal(nil), do: nil
  defp chart_decimal(%Decimal{} = value), do: value
  defp chart_decimal(value) when is_integer(value), do: Decimal.new(value)

  defp chart_decimal(value) when is_float(value) do
    Decimal.from_float(value)
  rescue
    _ -> nil
  end

  defp chart_decimal(value) when is_binary(value) do
    value = String.trim(value)

    if value == "" do
      nil
    else
      Decimal.new(value)
    end
  rescue
    _ -> nil
  end

  defp chart_decimal(_), do: nil

  defp overlay_points(%{points: points}, geometry, x0, y0, x1, y1) do
    plot_w = x1 - x0
    plot_h = y1 - y0

    points
    |> Enum.filter(&within_range?(&1.date, geometry))
    |> Enum.map(fn p ->
      x = x0 + plot_w * x_fraction_for_date(p.date, geometry)
      y = y1 - plot_h * normalized_overlay_y(p.value, geometry)
      "#{format_coord(x)},#{format_coord(y)}"
    end)
    |> Enum.join(" ")
  end

  defp normalized_overlay_y(value, geometry) when is_number(value) do
    transformed =
      cond do
        geometry.percent_mode? and geometry.first_close != 0.0 ->
          (value - geometry.first_close) / geometry.first_close * 100.0

        geometry.log_scale? ->
          safe_log(value)

        true ->
          value
      end

    range = geometry.y_max - geometry.y_min
    if range == 0, do: 0.5, else: (transformed - geometry.y_min) / range
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

        value =
          cond do
            assigns.percent_mode? -> raw
            assigns.geometry.log_scale? -> :math.pow(10, raw)
            true -> raw
          end

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
          <%= if @percent_axis?, do: format_percent(value), else: format_axis_value(value) %>
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

  defp format_percent(value) when is_float(value) do
    sign = if value > 0, do: "+", else: ""
    sign <> :erlang.float_to_binary(value, decimals: 1) <> " %"
  end

  defp format_percent(_), do: "—"
end
