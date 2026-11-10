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
    * `:notes` — research notes to mark (S28 N9, ADR-0056 A2):
      `[%{date: Date, headline: String, event_type: atom | nil, tone:
      -1 | 0 | 1 | nil}]`, only entries with a headline; the caller passes
      nothing else, so a story or a raw item is never drawn
    * `:show_notes?` — boolean, toggles the note pins (default off, so a
      chart that is not a security's draws none)
    * `:currency_code` — string label for the Y axis
    * `:aria_label` — accessible name of the rendered svg

  **The privacy mode** (Sprint 26 P2, I22, board 02): while it is on, a
  series in a currency (`:value_mode` `:absolute`) is drawn in its percent
  view, re-based on the window's first value, so the axis, the tooltip and
  the payload carry percentages and no amount; a trade's line keeps its
  kind and hides its quantity and price, and the payload leaves both out.
  A series already in percent keeps its axis. The percent view's 100 % is
  the first value above zero: a window that opens at zero or below reads
  from the first day it is above, and one with no such day draws its line
  without tick labels, so no amount is printed as a percentage. A note's pin
  stays: it carries a headline, an event type, a tone and a date, and no
  amount.

  **The note pins** (S28 N9; board `ux-design-2026-11-08-sprint28/01`,
  marker A): one pin per day with notes, at the plot's top edge over a
  dashed stem to the price of that day, so it never covers a trade's
  triangle or the line. Its colour is the tone's (`note-pin--pos`, `--neg`,
  `--neu`), and its glyph says it too (a plus, a minus, none: never colour
  alone, UX-DR7). Several notes on one day are one pin: `--mixed` when
  their tones differ, with a ± and their count beside it (closing act,
  ND3; the head, the glyph and the count are sized in CSS pixels through
  `--chart-upx`, so they keep their size on a phone), and every headline in
  its title and in the tooltip, because two pins on one x would hide each
  other. The tooltip (the payload's `notes`) reads, per note, the headline
  and „event type · tone · date“ in the page's language.

  Reasoning: the repo has no JS bundler, so charts are produced as a
  single `<svg>` element. Interactivity (range/log) is handled at the
  LiveView level — this component is purely a renderer.
  """

  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias PortfolixirWeb.EventTypeLabel
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.PrivacyMode
  alias PortfolixirWeb.TransactionKindLabel
  alias PortfolixirWeb.TransactionManagementLive

  @width 960
  @height 320
  @padding_top 16
  @padding_right 24
  @padding_bottom 28
  @padding_left 56

  attr(:quotes, :list, required: true)
  attr(:transactions, :list, default: [])
  attr(:overlays, :list, default: [])
  # When true, the overlays' values widen the Y range (a benchmark that
  # outruns the portfolio stays on the plot); off by default so the moving
  # averages keep the price series' own range.
  attr(:overlays_extend_range?, :boolean, default: false)
  attr(:log_scale?, :boolean, default: false)
  attr(:percent_mode?, :boolean, default: false)
  attr(:value_mode, :atom, default: :absolute, values: [:absolute, :percent_values])
  attr(:zero_line?, :boolean, default: false)
  attr(:show_transactions?, :boolean, default: true)
  # --- S28 N9 begin ---
  attr(:notes, :list, default: [])
  attr(:show_notes?, :boolean, default: false)
  # --- S28 N9 end ---
  attr(:currency_code, :string, default: "")
  # nil resolves to the localized "Price chart" at render time — a compile-time
  # attr default cannot go through gettext with the caller's locale.
  attr(:aria_label, :string, default: nil)

  # raw/1 writes the chart's JSON payload into its <script type=
  # "application/json"> block, and it is the only raw/1 here. Jason encodes
  # it with escape: :html_safe, which escapes "<" as \u003C and "/" as \/,
  # so no stored name or note can write "</script" and close the element
  # (sobelow 0.16, #1006).
  # sobelow_skip ["XSS.Raw"]
  def chart(assigns) do
    # Board 02: an axis in a currency switches to percent in the privacy
    # mode, built here on the server, never relabelled in the browser.
    assigns =
      if PrivacyMode.on?() and assigns.value_mode == :absolute,
        do: assign(assigns, :percent_mode?, true),
        else: assigns

    geometry =
      build_geometry(assigns.quotes, assigns.log_scale?,
        percent_mode?: assigns.percent_mode?,
        extra_values: range_extending_values(assigns)
      )

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
            <%= for marker <- transaction_markers(@transactions, @geometry, @currency_code, {@plot_left, @plot_top, @plot_right, @plot_bottom}) do %>
              <path class={"tx-marker tx-#{marker.type}"} d={marker.d}>
                <title><%= marker.label %></title>
              </path>
            <% end %>
          <% end %>

          <%!-- S28 N9 (board 01, marker A): the note pins at the top edge,
               after the trades, so a stem never paints over a triangle. --%>
          <%= if @show_notes? do %>
            <%= for pin <- note_pins(@notes, @geometry, {@plot_left, @plot_top, @plot_right, @plot_bottom}) do %>
              <g class={["note-pin", "note-pin--#{pin.tone}"]} data-date={pin.date}>
                <line class="note-pin__stem" x1={pin.x} x2={pin.x} y1={pin.stem_top} y2={pin.stem_bottom} />
                <circle class="note-pin__head" cx={pin.x} cy={pin.y} r="6" />
                <path :if={pin.glyph} class="note-pin__glyph" d={pin.glyph} />
                <text :if={pin.count > 1} class="note-pin__count" x={pin.count_x} y={pin.y} dominant-baseline="central">
                  <%= pin.count %>
                </text>
                <title><%= pin.title %></title>
              </g>
            <% end %>
          <% end %>

          <%!-- J5 A (board 05, rule ③): the labels follow the series, so on
               a narrow chart, where the values sit inside the plot, their
               halo paints over the line and the fill. --%>
          <%= render_axis_labels(assigns) %>
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
        [
          payload_date(q.date),
          point_display(q, geometry, assigns),
          round2(x),
          round2(y),
          Format.date(q.date)
        ]
      end)

    txs =
      if assigns.show_transactions? do
        build_tx_payload(assigns.transactions, geometry, assigns.currency_code, {x0, y0, x1, y1})
      else
        []
      end

    %{
      points: points,
      txs: txs,
      # S28 N9: the note pins' tooltip lines, matched to the crosshair by x.
      notes: note_payload(assigns, geometry, {x0, y0, x1, y1}),
      view: %{width: @width, height: @height},
      currency: assigns.currency_code,
      mode: payload_mode(assigns)
    }
  end

  # --- S28 N9 begin ---
  defp note_payload(%{show_notes?: true, notes: notes}, geometry, plot) do
    tolerance = day_width(geometry, plot) / 2

    for pin <- note_pins(notes, geometry, plot) do
      %{
        date: pin.date,
        x: round2(pin.x_value),
        tol: round2(max(tolerance, 3.0)),
        lines: pin.lines
      }
    end
  end

  defp note_payload(_assigns, _geometry, _plot), do: []

  defp day_width(geometry, {x0, _y0, x1, _y1}) do
    case date_span_days(geometry) do
      0 -> x1 - x0
      span -> (x1 - x0) / span
    end
  end

  # One pin per day with notes in the window (see the moduledoc): its x at
  # the day, its head at the plot's top edge, its stem down to the close of
  # that day (the last on or before it).
  defp note_pins(notes, geometry, {x0, y0, x1, y1}) do
    plot_w = x1 - x0
    plot_h = y1 - y0

    notes
    |> Enum.filter(&(is_binary(&1[:headline]) and &1[:headline] != ""))
    |> Enum.filter(&within_range?(&1.date, geometry))
    |> Enum.group_by(& &1.date)
    |> Enum.sort_by(fn {date, _notes} -> date end, Date)
    |> Enum.map(fn {date, day_notes} ->
      x = x0 + plot_w * x_fraction_for_date(date, geometry)
      close = close_for_date(geometry, date)
      price_y = if chart_float(close), do: y1 - plot_h * normalized_y(close, geometry), else: y1
      head_y = y0 + 7.5
      tone = pin_tone(day_notes)
      lines = Enum.map(day_notes, &note_lines/1)

      %{
        date: payload_date(date),
        x: format_coord(x),
        x_value: x,
        y: format_coord(head_y),
        stem_top: format_coord(head_y + 6.5),
        stem_bottom: format_coord(max(price_y, head_y + 6.5)),
        tone: tone,
        glyph: pin_glyph(tone, x, head_y),
        count: length(day_notes),
        count_x: format_coord(x),
        lines: lines,
        title: Enum.map_join(lines, "\n", &Enum.join(&1, "\n"))
      }
    end)
  end

  defp pin_tone(notes) do
    case notes |> Enum.map(&tone_class(&1[:tone])) |> Enum.uniq() do
      [tone] -> tone
      _differ -> "mixed"
    end
  end

  defp tone_class(1), do: "pos"
  defp tone_class(-1), do: "neg"
  defp tone_class(_neutral_or_none), do: "neu"

  # The tone as a glyph inside the head (UX-DR7): a plus, a minus, a ± for a
  # mixed day (closing act, ND3: without it a mixed day read as a neutral
  # one), none for a neutral one. Each is centred on the head, so the CSS
  # scales it about its own centre (`--chart-upx`).
  defp pin_glyph("pos", x, y) do
    "M#{format_coord(x - 3)},#{format_coord(y)} H#{format_coord(x + 3)} " <>
      "M#{format_coord(x)},#{format_coord(y - 3)} V#{format_coord(y + 3)}"
  end

  defp pin_glyph("neg", x, y),
    do: "M#{format_coord(x - 3)},#{format_coord(y)} H#{format_coord(x + 3)}"

  defp pin_glyph("mixed", x, y) do
    "M#{format_coord(x - 2.5)},#{format_coord(y - 1.5)} H#{format_coord(x + 2.5)} " <>
      "M#{format_coord(x)},#{format_coord(y - 4)} V#{format_coord(y + 1)} " <>
      "M#{format_coord(x - 2.5)},#{format_coord(y + 4)} H#{format_coord(x + 2.5)}"
  end

  defp pin_glyph(_neutral, _x, _y), do: nil

  # A note's two lines: the headline, then „event type · tone · date“ in
  # words, each part only when the note states it.
  defp note_lines(note) do
    meta =
      [
        note[:event_type] && EventTypeLabel.event_type(note.event_type),
        note[:tone] in [-1, 0, 1] && EventTypeLabel.tone(note.tone),
        Format.date(note.date)
      ]
      |> Enum.filter(&is_binary/1)
      |> Enum.join(" · ")

    [note.headline, meta]
  end

  # --- S28 N9 end ---

  # The hook's JSON keeps ISO at `points[i][0]` and on a trade: the zoom
  # sends these dates back as the custom range. #1163 (board 02 ⑥): the
  # tooltip reads the display strings beside them, `points[i][4]` and
  # `txs[i].label`, built here in the page's language, so the hook knows no
  # locale. Wealth's and the snapshots' charts share this payload and get
  # the display date too.
  defp payload_date(date), do: Date.to_iso8601(date)

  defp payload_mode(%{percent_mode?: true}), do: "percent"
  defp payload_mode(%{value_mode: :percent_values}), do: "percent"
  defp payload_mode(_), do: "absolute"

  # The crosshair tooltip's display value: a quote's explicit `:label` wins
  # (lets a caller show two series in one tooltip line). Else, #1163: the
  # percent view prints the axis's signed percent against its base, the
  # first close above zero ("+10,4%"; "—" without one), a percent series its value with one decimal, and a price
  # series its close at two places, the Quotes table's and the pane head's
  # form, with the chart's currency ("41,40 USD"). The hook appends nothing,
  # so a label that names its currency reads it once (the review of γ2).
  defp point_display(%{label: label}, _geometry, _assigns) when is_binary(label), do: label

  defp point_display(q, %{percent_mode?: true} = geometry, _assigns) do
    base = geometry.base
    close = chart_decimal(q.close)

    if base && close do
      Format.signed_percent(Decimal.div(Decimal.sub(close, base), base)) <> "%"
    else
      "—"
    end
  end

  defp point_display(q, _geometry, %{value_mode: :percent_values}),
    do: Format.plain_signed_decimal(chart_decimal(q.close), 1) <> "%"

  defp point_display(q, _geometry, assigns) do
    case assigns.currency_code do
      code when is_binary(code) and code != "" ->
        "#{Format.decimal(chart_decimal(q.close), 2)} #{code}"

      _none ->
        Format.decimal(chart_decimal(q.close), 2)
    end
  end

  # The zero line (gain/loss boundary) on the raw value scale; only rendered
  # when 0 actually sits inside the padded range.
  defp zero_in_range?(geometry) do
    geometry.y_min < 0.0 and geometry.y_max > 0.0
  end

  defp zero_y(geometry, plot_top, plot_bottom) do
    fraction = (0.0 - geometry.y_min) / (geometry.y_max - geometry.y_min)
    format_coord(plot_bottom - (plot_bottom - plot_top) * fraction)
  end

  defp build_tx_payload(transactions, geometry, currency_code, {x0, y0, x1, y1}) do
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
            date: payload_date(tx.date),
            type: tx.type,
            label: tx_line(tx, currency_code),
            x: round2(x),
            y: round2(y)
          }
          |> put_trade_figures(tx)
        ]
      end
    end)
  end

  defp round2(value), do: Float.round(:erlang.float(value), 2)

  # A trade's quantity and price as stored, for a reader of the payload;
  # left out in the privacy mode, where they are figures to hide.
  defp put_trade_figures(entry, tx) do
    if PrivacyMode.on?() do
      entry
    else
      Map.merge(entry, %{
        quantity: chart_decimal_string(tx.quantity),
        price: chart_decimal_string(tx.price)
      })
    end
  end

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
    base = percent_base(quotes)
    base_close = base && chart_float(base)
    rebase? = percent_mode? and is_float(base_close)

    raw_values =
      if rebase? do
        Enum.map(quotes, fn q -> (chart_float(q.close) - base_close) / base_close * 100.0 end)
      else
        Enum.map(quotes, &chart_float(&1.close))
      end

    extra_values =
      opts
      |> Keyword.get(:extra_values, [])
      |> Enum.map(fn value ->
        if rebase?, do: (value - base_close) / base_close * 100.0, else: value
      end)

    {y_min, y_max} = Enum.min_max(raw_values ++ extra_values)
    {y_min, y_max} = pad_range(y_min, y_max)

    log_scale? = log_scale? and not percent_mode?

    {y_min, y_max} =
      if log_scale?, do: {safe_log(y_min), safe_log(y_max)}, else: {y_min, y_max}

    %{
      quotes: indexed,
      first_date: first_date,
      last_date: last_date,
      base: base,
      first_close: base_close,
      y_min: y_min,
      y_max: y_max,
      log_scale?: log_scale?,
      percent_mode?: percent_mode?
    }
  end

  # The percent view's 100 %: the first close above zero, as a `Decimal`,
  # or nil when none is. A value series can open at zero (a buy booked
  # before its money) or below it, and a percent of such a base would print
  # the amounts themselves as percentages, or turn the axis over; so the
  # base is the first day whose value is above zero, as the stacked chart's
  # index is (S6, #1433), and with none the axis carries no label.
  defp percent_base(quotes) do
    Enum.find_value(quotes, fn q ->
      close = chart_decimal(q.close)
      if close && Decimal.gt?(close, 0), do: close
    end)
  end

  defp range_extending_values(%{overlays_extend_range?: true, overlays: overlays}) do
    for overlay <- overlays, point <- overlay.points, is_number(point.value), do: point.value
  end

  defp range_extending_values(_assigns), do: []

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
        geometry.percent_mode? and is_float(geometry.first_close) ->
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

  defp transaction_markers(transactions, geometry, currency_code, {x0, y0, x1, y1}) do
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
            label: marker_title(tx, currency_code)
          }
        ]
      end
    end)
  end

  # #1163 (board 02 ⑥): the trade line of the tooltip and the marker's
  # title, in the page's language — the kind's label, the quantity as
  # stored, the price by the history's stored-figure rule (R10c) and the
  # booking's currency, else the chart's.
  defp tx_line(tx, currency_code) do
    gettext("%{kind} %{quantity} at %{price} %{currency}",
      kind: TransactionKindLabel.label(tx.type),
      quantity: Format.exact(chart_decimal(tx.quantity)),
      price: TransactionManagementLive.stored_figure(chart_decimal(tx.price)),
      currency: tx_currency(tx, currency_code)
    )
  end

  defp marker_title(tx, currency_code) do
    gettext("%{kind} on %{date} at %{price} %{currency}",
      kind: TransactionKindLabel.label(tx.type),
      date: Format.date(tx.date),
      price: TransactionManagementLive.stored_figure(chart_decimal(tx.price)),
      currency: tx_currency(tx, currency_code)
    )
  end

  defp tx_currency(%{currency_code: code}, _chart) when is_binary(code) and code != "", do: code
  defp tx_currency(_tx, chart), do: chart || ""

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
        geometry.percent_mode? and is_float(geometry.first_close) ->
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
    assigns = assign(assigns, :y_ticks, y_ticks(assigns))

    ~H"""
    <g class="chart-axes" stroke="currentColor" stroke-opacity="0.15">
      <%= for {_value, y} <- @y_ticks do %>
        <line x1={@plot_left} y1={y} x2={@plot_right} y2={y} />
      <% end %>
    </g>
    """
  end

  # The labels read the page's language (issue 1088): the dates through
  # `Format.date`, the values through `Format.decimal`, a percent as the
  # house's signed percent. Their classes carry J5 A's rules ② and ③: the
  # five values are `chart-axis-y`, the top one also `is-top`, the two dates
  # `chart-axis-x`.
  defp render_axis_labels(assigns) do
    assigns = assign(assigns, :y_ticks, y_ticks(assigns))

    ~H"""
    <g class="chart-axis-labels">
      <%= for {{value, y}, index} <- Enum.with_index(@y_ticks),
              not (@percent_mode? and is_nil(@geometry.base)) do %>
        <text
          class={["chart-axis-y", index == length(@y_ticks) - 1 && "is-top"]}
          x={@plot_left - 6}
          y={y}
          text-anchor="end"
          dominant-baseline="central"
        >
          <%= if @percent_axis?, do: format_percent(value), else: format_axis_value(value) %>
        </text>
      <% end %>
      <text class="chart-axis-x" x={@plot_left} y={@height - 6} text-anchor="start">
        <%= Format.date(@geometry.first_date) %>
      </text>
      <text class="chart-axis-x" x={@plot_right} y={@height - 6} text-anchor="end">
        <%= Format.date(@geometry.last_date) %>
      </text>
    </g>
    """
  end

  defp y_ticks(assigns) do
    ticks = 4

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
  end

  # A tick is a float of the chart's geometry; it becomes a Decimal only to
  # be printed, its places chosen by its size, whatever its sign: none from
  # 1 000, two from 1, four below.
  defp format_axis_value(value) when is_float(value) do
    places =
      cond do
        abs(value) >= 1000 -> 0
        abs(value) >= 1 -> 2
        true -> 4
      end

    Format.decimal(Decimal.from_float(value), places)
  end

  defp format_axis_value(value), do: to_string(value)

  # The house's signed percent, as the KPI band prints it: one decimal, the
  # sign glued on, no space before "%" ("+10,4%"); a tick that reads zero
  # carries no sign.
  defp format_percent(value) when is_float(value),
    do: Format.plain_signed_decimal(Decimal.from_float(value), 1) <> "%"

  defp format_percent(_), do: "—"
end
