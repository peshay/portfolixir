defmodule PortfolixirWeb.Components.CycleChart do
  @moduledoc """
  The halving cycles on the security chart (FR-58, ADR-0060 §11, ADR-0059
  §8; Sprint 29 H7; the idea boards `ux-design-2026-11-10-idea-i12/01` to
  `03` as adopted and board `ux-design-2026-11-12-sprint29/07`): every part
  of the view the cycles read (`Portfolixir.Catalog.SecurityCycles`) gives a
  security, drawn from that read's payload and nothing else.

    * `bar/1` — the cycle bar under the chart's toolbar: „Zyklen“ with
      „Zeitachse“ and „Ausgerichtet“, the three line switches („Strecken“)
      and the chain source's health line (`health/1`).
    * `timeline_back/1` and `timeline_front/1` — the layers
      `PortfolixirWeb.Components.SecurityChart` draws on the time axis when
      its `cycles` attribute is set: behind the price line the halvings,
      the bands with „beide Wege“ and the cones; in front of it the
      segments between tops and lows, the ▲ and ▼ marks and their labels.

  **What is drawn** (ADR-0060 §5, §6): one band per event, the hull of its
  parts, with `agree` shaded as „beide Wege“; no shade where `agree` is
  `null` (`one_price_relation` draws the band with a dashed edge,
  `parts_disjoint` the hull as an outline with its parts filled inside,
  board 07 Q7 A). Each line switch that is on draws its segments, each
  with its days and its change, and continues from its last anchor as a
  **cone** into its own relation's part, never as a line past the anchor;
  an event a cone goes into is drawn as an outline, the cones showing its
  parts. A band never names a single date or price.

  **The privacy mode** (plan row H7): a price is an amount. The chart's axis
  is in percent as before; a top's or a low's label names its month, a
  band's label its kind, dates, agreement and state, and no label carries a
  price. Days, changes and factors are ratios and stay.

  **The geometry** comes from the security chart: `scale` carries the plot's
  corners, the axis' first and last date, and the functions that place a
  date and a price on it (the chart's own log or percent transform), so a
  mark sits where the price line does. Everything right of the last close is
  clipped to the plot; the range that reaches past today is H8's.
  """

  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias PortfolixirWeb.Format
  alias PortfolixirWeb.PrivacyMode

  @lines ~w(top_low top_top low_low)

  # Which event a cone's relation goes into (ADR-0060 §4's table).
  @relation_event %{
    top_to_low: :next_low,
    low_to_low: :next_low,
    top_to_top: :next_top,
    low_to_top: :next_top,
    halving_to_top: :next_top
  }

  @doc "The three line switches, in the bar's order."
  @spec lines() :: [String.t()]
  def lines, do: @lines

  @doc "The switches when cycles are turned on: „Top ↔ Tief“ on (ADR-0060 §6)."
  @spec default_lines() :: %{String.t() => boolean()}
  def default_lines, do: %{"top_low" => true, "top_top" => false, "low_low" => false}

  @doc """
  Whether the payload is a view (ADR-0060 §1): the read names no reason and
  has its windows. The toggle is shown only then (board 07 Q3 A).
  """
  @spec view?(map() | nil) :: boolean()
  def view?(%{reason: nil, cycles: [_ | _]}), do: true
  def view?(_payload), do: false

  # ---------------------------------------------------------------- the bar

  attr(:mode, :string, required: true)
  attr(:lines, :map, required: true)
  attr(:payload, :map, required: true)
  attr(:hosts, :map, default: nil)
  attr(:now, :any, default: nil)

  @doc "The cycle bar (board 07 ③, ⑧): the mode, the line switches, the health line."
  def bar(assigns) do
    ~H"""
    <div class="cycle-bar" data-role="cycle-bar" role="group" aria-label={gettext("Cycles")}>
      <div class="cycle-bar__group">
        <span class="cycle-bar__label" id="cycle-mode-label"><%= gettext("Cycles") %></span>
        <div class="segmented-control" role="group" aria-labelledby="cycle-mode-label">
          <button
            :for={{mode, label} <- [{"timeline", pgettext("halving cycles", "Timeline")}, {"aligned", pgettext("halving cycles", "Aligned")}]}
            type="button"
            id={"cycle-mode-#{mode}"}
            phx-click="set_detail_cycles_mode"
            phx-value-mode={mode}
            class={["segmented-control__option", @mode == mode && "is-active"]}
            aria-pressed={to_string(@mode == mode)}
          >
            <%= label %>
          </button>
        </div>
      </div>
      <div :if={@mode == "timeline"} class="cycle-bar__group">
        <span class="cycle-bar__label" id="cycle-lines-label"><%= gettext("Segments") %></span>
        <div class="cycle-bar__switches" role="group" aria-labelledby="cycle-lines-label">
          <button
            :for={line <- lines()}
            type="button"
            id={"cycle-line-#{line}"}
            phx-click="toggle_detail_cycle_line"
            phx-value-line={line}
            class={["chart-toggle", @lines[line] && "is-active"]}
            aria-pressed={to_string(@lines[line] == true)}
          >
            <%= line_label(line) %>
          </button>
        </div>
      </div>
      <.health
        source={@payload.chain_source}
        chain={@payload.chain}
        hosts={@hosts}
        now={@now || DateTime.utc_now()}
      />
    </div>
    """
  end

  defp line_label("top_low"), do: gettext("Top ↔ low")
  defp line_label("top_top"), do: gettext("Top – top")
  defp line_label("low_low"), do: gettext("Low – low")

  # ------------------------------------------------------- the health line

  attr(:source, :map, default: nil, doc: "the cycles read's chain_source")
  attr(:chain, :string, default: nil)
  attr(:hosts, :map, default: nil, doc: "Portfolixir.Chains.source_hosts/1")
  attr(:now, :any, required: true)

  @doc """
  The chain source's health line (ADR-0059 §8; board 07 ③, Q4 A): the host
  and the age of the last read, the fallback named as such; for a source
  without a successful run for 24 hours the record's sentence with the last
  host and time; a refused own URL with its host and its reason; a chain
  without a source says its halvings are entered by hand. `data-status`
  names the state: `by_hand`, `never_read`, `current`, `failed`, `stale`,
  `refused`.
  """
  def health(assigns) do
    {status, text} = health_text(assigns.source, assigns.chain, assigns.hosts, assigns.now)
    assigns = assign(assigns, status: status, text: text)

    ~H"""
    <p class={["cycle-health", "cycle-health--#{@status}"]} data-role="cycle-health" data-status={@status}>
      <span class="cycle-health__dot" aria-hidden="true"></span>
      <span class="cycle-health__text"><%= @text %></span>
    </p>
    """
  end

  defp health_text(%{has_source: true} = source, _chain, hosts, now) do
    cond do
      refused = refusal(source[:last_error]) ->
        {:refused, refused_text(refused, source, hosts)}

      source[:stale] == true ->
        {:stale, stale_text(source, now)}

      is_nil(source[:last_ok_at]) and is_nil(source[:last_tried_at]) ->
        {:never_read, gettext("Chain source: not read yet")}

      is_nil(source[:last_ok_at]) ->
        {:failed,
         gettext("Chain source: no answer yet · last attempt: %{error}",
           error: error_text(source[:last_error])
         )}

      failed_since_ok?(source) ->
        {:failed,
         current_text(source, hosts, now) <>
           " · " <>
           gettext("last attempt failed: %{error}", error: error_text(source[:last_error]))}

      true ->
        {:current, current_text(source, hosts, now)}
    end
  end

  defp health_text(_no_source, chain, _hosts, _now) do
    {:by_hand,
     gettext("Halvings entered by hand · no chain source for %{chain}", chain: chain_name(chain))}
  end

  defp failed_since_ok?(source) do
    is_binary(source[:last_error]) and match?(%DateTime{}, source[:last_tried_at]) and
      DateTime.compare(source.last_tried_at, source.last_ok_at) == :gt
  end

  defp current_text(source, hosts, now) do
    gettext("Chain source: %{host} · read %{age}",
      host: host_text(source[:source_host], hosts),
      age: age_text(source[:last_ok_at], now)
    )
  end

  defp host_text(host, %{own?: false, hosts: [first | _rest]}) when host != first,
    do: gettext("%{host} (fallback)", host: host)

  defp host_text(host, _hosts), do: host || "—"

  defp stale_text(%{last_ok_at: %DateTime{} = ok_at} = source, now) do
    gettext(
      "Chain source without an answer for %{hours} h · last %{host}, %{at} · halving estimate from then",
      hours: div(DateTime.diff(now, ok_at, :second), 3600),
      host: source[:source_host] || "—",
      at: Format.utc_instant(ok_at)
    )
  end

  defp stale_text(source, _now) do
    gettext("Chain source has never answered · last attempt: %{error}",
      error: error_text(source[:last_error])
    )
  end

  defp refused_text({host, reason}, source, hosts) do
    line =
      if match?(%{own?: true}, hosts),
        do: gettext("Own chain source refused: %{host} %{reason}", host: host, reason: reason),
        else: gettext("Chain source refused: %{host} %{reason}", host: host, reason: reason)

    since =
      case source[:last_ok_at] do
        %DateTime{} = at ->
          gettext("nothing read since %{date}", date: Format.date(DateTime.to_date(at)))

        _never ->
          gettext("nothing read yet")
      end

    line <> " · " <> since
  end

  # A refused URL fails the run with `url_not_allowed:<reason>` before any
  # request (ADR-0059 §3, `Portfolixir.Chains.Esplora`); the state row keeps
  # it as "host: url_not_allowed:reason".
  defp refusal(error) when is_binary(error) do
    case Regex.run(~r/(?:^|; )([^\s:;]+): url_not_allowed:([a-z_]+)/, error) do
      [_all, host, reason] -> {host, refusal_reason(reason)}
      nil -> nil
    end
  end

  defp refusal(_error), do: nil

  defp refusal_reason("private_address"), do: gettext("resolves to a private address")
  defp refusal_reason("scheme"), do: gettext("is not an https address")
  defp refusal_reason("userinfo"), do: gettext("carries a user name or a password")
  defp refusal_reason("query"), do: gettext("carries a query or a fragment")
  defp refusal_reason("host"), do: gettext("names no valid host")
  defp refusal_reason("host_not_allowed"), do: gettext("is not an allowed host")
  defp refusal_reason("unresolvable"), do: gettext("cannot be resolved")
  defp refusal_reason(code), do: code

  # The run's failures as "host: code; host: code": each code in words where
  # board 07 names one, else the code as stored.
  defp error_text(error) when is_binary(error) do
    error
    |> String.split("; ")
    |> Enum.map_join("; ", fn failure ->
      case String.split(failure, ": ", parts: 2) do
        [host, code] -> host <> ": " <> error_code_text(code)
        [code] -> error_code_text(code)
      end
    end)
  end

  defp error_text(_none), do: "—"

  defp error_code_text("wrong_chain"),
    do: gettext("wrong chain: the genesis block does not match")

  defp error_code_text("tip_behind"), do: gettext("the source lags behind")
  defp error_code_text("timeout"), do: gettext("no answer in time")
  defp error_code_text(code), do: code

  defp age_text(%DateTime{} = at, now) do
    seconds = max(DateTime.diff(now, at, :second), 0)

    cond do
      seconds < 3600 -> gettext("%{minutes} min ago", minutes: div(seconds, 60))
      seconds < 48 * 3600 -> gettext("%{hours} h ago", hours: div(seconds, 3600))
      true -> gettext("on %{date}", date: Format.date(DateTime.to_date(at)))
    end
  end

  defp age_text(_never, _now), do: "—"

  @doc "A registered chain's name as the screen writes it."
  @spec chain_name(String.t() | atom() | nil) :: String.t()
  def chain_name(chain) when chain in ["bitcoin", :bitcoin], do: "Bitcoin"
  def chain_name(chain) when chain in ["bitcoin_cash", :bitcoin_cash], do: "Bitcoin Cash"
  def chain_name(chain) when chain in ["litecoin", :litecoin], do: "Litecoin"
  def chain_name(chain) when is_binary(chain), do: chain
  def chain_name(_none), do: "—"

  # ------------------------------------------------- the time axis' layers

  @doc """
  The prices the time axis must hold for the cycles drawn on it: each band's
  and each shown cone's part's ends, where its window meets the axis
  (`first` to `last`). The chart widens its value range by them, so a band
  above or below every close stays on the plot.
  """
  @spec timeline_values(map(), Date.t(), Date.t()) :: [float()]
  def timeline_values(%{payload: payload, lines: lines}, first, last) do
    bands =
      for event <- events(payload),
          band = event.band,
          overlaps?(band.window, first, last),
          do: [band.price.from, band.price.to]

    cones =
      for cone <- shown_cones(payload, lines),
          overlaps?(cone.window, first, last),
          do: [cone.price.from, cone.price.to, cone.apex.close]

    (bands ++ cones) |> List.flatten() |> Enum.reject(&is_nil/1) |> Enum.map(&Decimal.to_float/1)
  end

  attr(:cycles, :map, required: true, doc: "%{payload: the cycles read, lines: the switches}")
  attr(:scale, :map, required: true)
  attr(:clip, :string, required: true, doc: "the id of the plot's clipPath")

  @doc "Behind the price line: the halvings, the bands and the cones."
  def timeline_back(assigns) do
    assigns = assign(assigns, :marks, back_marks(assigns.cycles, assigns.scale))

    ~H"""
    <g class="cycle-layer cycle-layer--back" clip-path={"url(##{@clip})"}>
      <line
        :for={h <- @marks.halvings}
        class={["cycle-halving", h.estimate? && "is-estimate"]}
        data-date={Date.to_iso8601(h.date)}
        x1={h.x}
        x2={h.x}
        y1={@scale.y0}
        y2={@scale.y1}
      />
      <%= for band <- @marks.bands do %>
        <rect
          class={[
            "cycle-band",
            "cycle-band--#{band.kind}",
            band.outline? && "is-outline",
            band.single? && "is-single",
            band.disjoint? && "is-disjoint"
          ]}
          data-event={band.event}
          data-from={Date.to_iso8601(band.from)}
          data-to={Date.to_iso8601(band.to)}
          x={band.rect.x}
          y={band.rect.y}
          width={band.rect.w}
          height={band.rect.h}
        />
        <rect
          :if={band.agree}
          class={["cycle-band__agree", "cycle-band__agree--#{band.kind}"]}
          data-event={band.event}
          x={band.agree.x}
          y={band.agree.y}
          width={band.agree.w}
          height={band.agree.h}
        />
        <rect
          :for={part <- band.parts}
          class={["cycle-band__part", "cycle-band__part--#{band.kind}"]}
          data-relation={part.relation}
          x={part.rect.x}
          y={part.rect.y}
          width={part.rect.w}
          height={part.rect.h}
        />
      <% end %>
      <g
        :for={cone <- @marks.cones}
        class={["cycle-cone", "cycle-cone--#{cone.line}"]}
        data-line={cone.line}
        data-relation={cone.relation}
      >
        <path class="cycle-cone__area" d={cone.area} />
        <line
          :for={{x2, y2} <- cone.corners}
          class="cycle-cone__edge"
          x1={cone.apex_x}
          y1={cone.apex_y}
          x2={x2}
          y2={y2}
        />
        <rect class="cycle-cone__part" x={cone.rect.x} y={cone.rect.y} width={cone.rect.w} height={cone.rect.h} />
      </g>
    </g>
    """
  end

  @doc "In front of the price line: the segments, the ▲ and ▼ marks, the labels."
  def timeline_front(assigns) do
    assigns = assign(assigns, :marks, front_marks(assigns.cycles, assigns.scale))

    ~H"""
    <g class="cycle-layer cycle-layer--front">
      <g clip-path={"url(##{@clip})"}>
        <line
          :for={s <- @marks.segments}
          class={["cycle-segment", "cycle-segment--#{s.line}"]}
          data-line={s.line}
          data-from={Date.to_iso8601(s.from)}
          data-to={Date.to_iso8601(s.to)}
          x1={s.x1}
          y1={s.y1}
          x2={s.x2}
          y2={s.y2}
        />
        <path
          :for={m <- @marks.extremes}
          class={[
            "cycle-#{m.kind}",
            m.provisional? && "is-provisional",
            m.so_far? && "is-so-far"
          ]}
          data-date={Date.to_iso8601(m.date)}
          d={m.d}
        >
          <title><%= m.title %></title>
        </path>
      </g>
      <text
        :for={h <- @marks.halving_labels}
        class={["cycle-label", "cycle-label--halving", h.estimate? && "is-estimate"]}
        x={h.x}
        y={h.y}
      >
        <%= h.text %>
      </text>
      <text
        :for={s <- @marks.segment_labels}
        class={["cycle-label", "cycle-label--segment", "cycle-label--#{s.line}"]}
        data-line={s.line}
        x={s.x}
        y={s.y}
        text-anchor="middle"
      >
        <%= s.text %>
      </text>
      <text
        :for={m <- @marks.extreme_labels}
        class={["cycle-label", "cycle-label--#{m.kind}"]}
        data-date={Date.to_iso8601(m.date)}
        x={m.x}
        y={m.y}
        text-anchor="middle"
      >
        <tspan :for={{line, index} <- Enum.with_index(m.lines)} x={m.x} dy={if index == 0, do: "0", else: "1.2em"}>
          <%= line %>
        </tspan>
      </text>
      <text
        :for={b <- @marks.band_labels}
        class={["cycle-label", "cycle-label--band", "cycle-label--#{b.kind}"]}
        data-event={b.event}
        x={b.x}
        y={b.y}
        text-anchor={b.anchor}
      >
        <tspan :for={{line, index} <- Enum.with_index(b.lines)} x={b.x} dy={if index == 0, do: "0", else: "1.2em"}>
          <%= line %>
        </tspan>
      </text>
    </g>
    """
  end

  # -- the marks behind the line ---------------------------------------------

  defp back_marks(%{payload: payload, lines: lines}, scale) do
    cones = shown_cones(payload, lines)
    coned = MapSet.new(cones, &Map.fetch!(@relation_event, &1.relation))

    %{
      halvings: halving_marks(payload, scale),
      bands: Enum.flat_map(events(payload), &band_mark(&1, coned, payload, scale)),
      cones: Enum.flat_map(cones, &cone_mark(&1, scale))
    }
  end

  defp halving_marks(payload, scale) do
    confirmed =
      for h <- payload.halvings, h.confirmed, within?(h.date, scale) do
        %{date: h.date, x: coord(scale.x.(h.date)), x_value: scale.x.(h.date), estimate?: false}
      end

    estimate =
      case payload.next_halving do
        %{date: %Date{} = date} ->
          if within?(date, scale),
            do: [
              %{date: date, x: coord(scale.x.(date)), x_value: scale.x.(date), estimate?: true}
            ],
            else: []

        _none ->
          []
      end

    confirmed ++ estimate
  end

  defp band_mark(%{band: nil}, _coned, _payload, _scale), do: []

  defp band_mark(event, coned, _payload, scale) do
    band = event.band

    if overlaps?(band.window, scale.first, scale.last) do
      disjoint? = event.agree_reason == :parts_disjoint

      [
        %{
          event: event.event,
          kind: event_kind(event.event),
          from: band.window.from,
          to: band.window.to,
          rect: rect(band.window, band.price, scale),
          outline?: disjoint? or MapSet.member?(coned, event.event),
          single?: event.agree_reason == :one_price_relation,
          disjoint?: disjoint?,
          agree: event.agree && rect(band.window, event.agree, scale),
          parts:
            if(disjoint?,
              do:
                for(
                  part <- event.parts,
                  part.reason == nil and part.own_price,
                  do: %{relation: part.relation, rect: rect(part.window, part.price, scale)}
                ),
              else: []
            )
        }
      ]
    else
      []
    end
  end

  defp cone_mark(cone, scale) do
    apex_x = scale.x.(cone.apex.date)
    apex_y = scale.y.(cone.apex.close)
    near_x = scale.x.(cone.window.from)
    high_y = scale.y.(cone.price.to)
    low_y = scale.y.(cone.price.from)

    [
      %{
        line: cone.line,
        relation: cone.relation,
        apex_x: coord(apex_x),
        apex_y: coord(apex_y),
        corners: [{coord(near_x), coord(high_y)}, {coord(near_x), coord(low_y)}],
        area:
          "M#{coord(apex_x)},#{coord(apex_y)} L#{coord(near_x)},#{coord(high_y)} " <>
            "L#{coord(near_x)},#{coord(low_y)} Z",
        rect: rect(cone.window, cone.price, scale)
      }
    ]
  end

  # -- the marks in front of the line ----------------------------------------

  defp front_marks(%{payload: payload, lines: lines}, scale) do
    segments = segments(payload, lines, scale)
    extremes = extremes(payload, scale)

    %{
      segments: segments,
      segment_labels:
        for(
          s <- segments,
          s.label_visible?,
          do: Map.take(s, [:line, :text]) |> Map.merge(s.label)
        ),
      extremes: extremes,
      extreme_labels: extremes,
      halving_labels: halving_labels(payload, scale),
      band_labels: Enum.flat_map(events(payload), &band_label(&1, payload, scale))
    }
  end

  # ADR-0060 §6: „Top ↔ Tief“ joins each top to the low after it and each
  # final low to the next top; „Top – Top“ the tops, „Tief – Tief“ the lows.
  # The relations' own observations are those segments, with their days and
  # their change or factor (§3), and none runs past the last anchor.
  defp segments(payload, lines, scale) do
    intervals = payload.intervals || %{}

    for {line, relations} <- [
          {"top_low", [:top_to_low, :low_to_top]},
          {"top_top", [:top_to_top]},
          {"low_low", [:low_to_low]}
        ],
        lines[line] == true,
        relation <- relations,
        obs <- observations(intervals, relation),
        obs.from.close != nil and obs.to.close != nil,
        overlaps?(%{from: obs.from.date, to: obs.to.date}, scale.first, scale.last) do
      x1 = scale.x.(obs.from.date)
      y1 = scale.y.(obs.from.close)
      x2 = scale.x.(obs.to.date)
      y2 = scale.y.(obs.to.close)
      mid = Date.add(obs.from.date, div(Date.diff(obs.to.date, obs.from.date), 2))

      %{
        line: line,
        from: obs.from.date,
        to: obs.to.date,
        x1: coord(x1),
        y1: coord(y1),
        x2: coord(x2),
        y2: coord(y2),
        text: observation_text(obs),
        label_visible?: within?(mid, scale),
        label: %{x: coord((x1 + x2) / 2), y: coord((y1 + y2) / 2 - 4)}
      }
    end
  end

  defp observations(intervals, relation) do
    case Map.get(intervals, relation) do
      %{observations: observations} when is_list(observations) -> observations
      _none -> []
    end
  end

  @doc false
  def observation_text(obs) do
    days = gettext("%{days} d", days: obs.days)

    cond do
      Map.get(obs, :change) -> days <> " · " <> Format.signed_percent(obs.change) <> " %"
      Map.get(obs, :factor) -> days <> " · " <> factor_text(obs.factor)
      true -> days
    end
  end

  @doc false
  def factor_text(%Decimal{} = factor) do
    places = if Decimal.compare(factor, 10) == :lt, do: 1, else: 0
    "×" <> Format.plain_decimal(factor, places)
  end

  # The ▲ over a window's top and the ▼ under its low, each pointing at its
  # close (boards 01 and 07): the open window's anchored top provisional,
  # its low so far hollow.
  defp extremes(payload, scale) do
    currency = payload.currency_code

    Enum.flat_map(payload.cycles, fn cycle ->
      top =
        case cycle.top do
          %{date: %Date{} = date, close: %Decimal{} = close} = top ->
            [extreme(:top, date, close, top.final == false, false, currency, scale)]

          _none ->
            []
        end

      low =
        case {cycle.low, cycle.low_so_far} do
          {%{date: %Date{} = date, close: %Decimal{} = close} = low, _so_far} ->
            [extreme(:low, date, close, false, false, currency, scale, low.partial)]

          {nil, %{date: %Date{} = date, close: %Decimal{} = close}} ->
            [extreme(:low, date, close, true, true, currency, scale)]

          _none ->
            []
        end

      Enum.filter(top ++ low, & &1)
    end)
  end

  defp extreme(kind, date, close, provisional?, so_far?, currency, scale, partial? \\ false) do
    if within?(date, scale) do
      x = scale.x.(date)
      y = scale.y.(close)

      {d, label_y} =
        case kind do
          :top -> {triangle_down(x, y - 3), y - 16}
          :low -> {triangle_up(x, y + 3), y + 22}
        end

      %{
        kind: kind,
        date: date,
        d: d,
        x: coord(x),
        y: coord(clamp(label_y, scale.y0 + 9, scale.y1 - 4)),
        provisional?: provisional?,
        so_far?: so_far?,
        lines: extreme_lines(kind, date, close, provisional?, so_far?, partial?, currency),
        title: extreme_title(kind, date, close, currency)
      }
    end
  end

  defp extreme_lines(kind, date, close, provisional?, so_far?, partial?, currency) do
    head =
      cond do
        so_far? and PrivacyMode.on?() ->
          gettext("so far · %{month}", month: Format.month(date))

        so_far? ->
          gettext("so far %{price} · %{month}",
            price: price(close, currency),
            month: Format.month(date)
          )

        PrivacyMode.on?() ->
          Format.month(date)

        true ->
          price(close, currency) <> " · " <> Format.month(date)
      end

    note =
      cond do
        so_far? -> [pgettext("halving cycles", "provisional")]
        kind == :top and provisional? -> [gettext("anchored · provisional")]
        partial? -> [gettext("low of the partial cycle")]
        true -> []
      end

    [head | note]
  end

  defp extreme_title(kind, date, close, currency) do
    what =
      if kind == :top,
        do: pgettext("halving cycles", "Top"),
        else: pgettext("halving cycles", "Low")

    if PrivacyMode.on?(),
      do: what <> " · " <> Format.date(date),
      else: what <> " · " <> Format.date(date) <> " · " <> price(close, currency)
  end

  defp halving_labels(payload, scale) do
    for h <- halving_marks(payload, scale) do
      text =
        if h.estimate?,
          do: gettext("Halving ≈ %{date} (estimate)", date: Format.date(h.date)),
          else: gettext("Halving %{date}", date: Format.date(h.date))

      %{x: coord(h.x_value + 3), y: coord(scale.y0 + 9), text: text, estimate?: h.estimate?}
    end
  end

  defp band_label(%{band: nil}, _payload, _scale), do: []

  defp band_label(event, payload, scale) do
    band = event.band

    if overlaps?(band.window, scale.first, scale.last) do
      left = scale.x.(band.window.from)
      right = scale.x.(band.window.to)
      top = scale.y.(band.price.to)
      middle = (scale.x0 + scale.x1) / 2

      {x, anchor} =
        if (left + right) / 2 > middle,
          do: {max(left - 4, scale.x0 + 4), "end"},
          else: {min(right + 4, scale.x1 - 4), "start"}

      [
        %{
          event: event.event,
          kind: event_kind(event.event),
          x: coord(x),
          y: coord(clamp(top + 9, scale.y0 + 9, scale.y1 - 40)),
          anchor: anchor,
          lines: band_lines(event, payload.currency_code)
        }
      ]
    else
      []
    end
  end

  @doc false
  def band_lines(event, currency) do
    band = event.band

    head =
      case event.event do
        :next_low -> gettext("Low band")
        :next_top -> gettext("Top band")
      end

    head =
      if PrivacyMode.on?(),
        do: head,
        else: head <> " " <> price_range(band.price, currency)

    [
      head,
      Format.date(band.window.from) <> " – " <> Format.date(band.window.to),
      agree_text(event, currency),
      state_text(event)
    ]
  end

  @doc false
  def agree_text(%{agree: %{} = agree}, currency) do
    if PrivacyMode.on?(),
      do: gettext("both ways"),
      else: gettext("both ways %{range}", range: price_range(agree, currency))
  end

  def agree_text(%{agree_reason: :one_price_relation}, _currency),
    do: gettext("one price way, no „both ways“")

  def agree_text(%{agree_reason: :parts_disjoint}, _currency),
    do: gettext("the ways disagree: no way leads in between")

  def agree_text(_event, _currency), do: ""

  @doc """
  A band's or a part's state in words (board 07 Q6): „offen“, „läuft“,
  „erreicht“, „verfehlt“, with „· Fenster vorbei“ once its window has
  ended; no state where an input postdates its window.
  """
  @spec state_text(map()) :: String.t()
  def state_text(%{state: nil, state_reason: :input_after_window}),
    do: gettext("no state: an input lies after its window")

  def state_text(%{state: nil}), do: "—"

  def state_text(%{state: state} = item) do
    word =
      case state do
        :open -> pgettext("halving cycles", "open")
        :running -> pgettext("halving cycles", "running")
        :reached -> pgettext("halving cycles", "reached")
        :missed -> pgettext("halving cycles", "missed")
      end

    if item[:window_ended] == true, do: word <> " · " <> gettext("window over"), else: word
  end

  # -- shared --------------------------------------------------------------------

  defp events(%{projection: %{} = projection}),
    do: Enum.filter([projection[:next_low], projection[:next_top]], & &1)

  defp events(_payload), do: []

  defp shown_cones(%{projection: %{cones: cones}}, lines) when is_list(cones) do
    Enum.filter(cones, fn cone ->
      lines[Atom.to_string(cone.line)] == true and cone.reason == nil and
        is_map(cone.apex) and is_map(cone.window) and is_map(cone.price)
    end)
  end

  defp shown_cones(_payload, _lines), do: []

  defp event_kind(:next_low), do: "low"
  defp event_kind(:next_top), do: "top"

  defp overlaps?(%{from: from, to: to}, first, last),
    do: Date.compare(from, last) != :gt and Date.compare(to, first) != :lt

  defp within?(date, scale),
    do: Date.compare(date, scale.first) != :lt and Date.compare(date, scale.last) != :gt

  # A window and a price range as the chart's rectangle; a day's width at
  # least, so a one-day window is still seen.
  defp rect(window, price, scale) do
    x1 = scale.x.(window.from)
    x2 = scale.x.(window.to)
    ya = scale.y.(price.from)
    yb = scale.y.(price.to)

    %{
      x: coord(x1),
      y: coord(min(ya, yb)),
      w: coord(max(x2 - x1, 1.0)),
      h: coord(max(abs(ya - yb), 1.0))
    }
  end

  defp triangle_down(x, apex_y) do
    "M#{coord(x)},#{coord(apex_y)} L#{coord(x + 4.5)},#{coord(apex_y - 8)} " <>
      "L#{coord(x - 4.5)},#{coord(apex_y - 8)} Z"
  end

  defp triangle_up(x, apex_y) do
    "M#{coord(x)},#{coord(apex_y)} L#{coord(x + 4.5)},#{coord(apex_y + 8)} " <>
      "L#{coord(x - 4.5)},#{coord(apex_y + 8)} Z"
  end

  defp clamp(value, low, high), do: value |> max(low) |> min(high)

  @doc false
  def price(%Decimal{} = value, currency) do
    places =
      cond do
        Decimal.compare(Decimal.abs(value), 100) != :lt -> 0
        Decimal.compare(Decimal.abs(value), 1) != :lt -> 2
        true -> 4
      end

    "#{Format.decimal(value, places)} #{currency}"
  end

  @doc false
  def price_range(%{from: from, to: to}, currency) do
    [low, high] = Enum.sort([from, to], Decimal)
    "#{price(low, "") |> String.trim()}–#{price(high, currency)}"
  end

  defp coord(value) do
    value
    |> :erlang.float()
    |> Float.round(2)
    |> Float.to_string()
  end
end
