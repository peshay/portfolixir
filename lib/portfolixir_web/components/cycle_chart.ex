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
  mark sits where the price line does. Everything outside the axis is
  clipped to the plot.

  **The range „Zyklus“** (Sprint 29 H8, ADR-0060 §11; board 07 ⑤):
  `cycle_range/1` gives its dates, from three months before the last
  confirmed halving to four months after the later end of the two bands,
  which reaches past today. Right of today the axis holds only the next
  halving's window (`rect.cycle-halving-window`), the bands and the cones
  into them, and a „heute“ line marks where the closes end.
  """

  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Clock
  alias PortfolixirWeb.ControlBar
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
  # S29 H8: „Jetzt lesen“ for a chain with a source, `%{wait: seconds,
  # busy?: boolean}`; nil for a chain the app does not read.
  attr(:read, :map, default: nil)

  @doc "The cycle bar (board 07 ③, ⑧): the mode, the line switches, the health line."
  def bar(assigns) do
    ~H"""
    <div class="cycle-bar" data-role="cycle-bar" role="group" aria-label={gettext("Cycles")}>
      <%!-- Issue 1435 (integration): the labelled controls on the shared
      bar; at 560 px and under every label stands above its controls
      (board 07 ⑧). --%>
      <ControlBar.bar floor={560} class="cycle-bar__controls">
        <:group label={gettext("Cycles")} label_id="cycle-mode-label">
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
        </:group>
        <:group :if={@mode == "timeline"} label={gettext("Segments")} label_id="cycle-lines-label">
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
        </:group>
      </ControlBar.bar>
      <div class="cycle-bar__health">
        <.health
          source={@payload.chain_source}
          chain={@payload.chain}
          hosts={@hosts}
          now={@now || DateTime.utc_now()}
        />
        <.read_now :if={@read} wait={@read.wait} busy?={@read.busy?} />
      </div>
    </div>
    """
  end

  # --- S29 H8 begin ---
  attr(:wait, :integer, default: 0, doc: "seconds until the chain may be read again")
  attr(:busy?, :boolean, default: false)
  attr(:target, :any, default: nil, doc: "the component that handles the click, if any")

  @doc """
  „Jetzt lesen“ (ADR-0059 §11; board 07 Q5): one on-demand read of the
  chain (`Portfolixir.Chains.refresh/2`), beside the health line in the
  cycle bar and in the edit form. While the chain waits for its ten
  minutes the button is disabled and says when it may read again; while a
  read runs it says so. The event is `read_chain_now`.
  """
  def read_now(assigns) do
    assigns = assign(assigns, :minutes, div(assigns.wait + 59, 60))

    ~H"""
    <span class="cycle-read" data-role="chain-read">
      <button
        type="button"
        class="button-ghost cycle-read__button"
        data-role="chain-read-now"
        phx-click="read_chain_now"
        phx-target={@target}
        disabled={@busy? or @wait > 0}
      >
        <%= if @busy?, do: gettext("Reading…"), else: gettext("Read now") %>
      </button>
      <span :if={@wait > 0 and not @busy?} class="cycle-read__wait" data-role="chain-read-wait">
        <%= gettext("read less than 10 minutes ago · again in %{minutes} min", minutes: @minutes) %>
      </span>
    </span>
    """
  end

  @doc """
  Whether the chain source's last error is a refused URL (ADR-0059 §3,
  `url_not_allowed`): the edit form then says that no halving is written
  and what an own URL must be (board 07 ①, Q4 A).
  """
  @spec refused?(map() | nil) :: boolean()
  def refused?(%{} = source), do: refusal(source[:last_error]) != nil
  def refused?(_none), do: false

  # --- S29 H8 end ---

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
  # it as "host: url_not_allowed:reason". Anchored on ": url_not_allowed:",
  # since an IPv6 literal's host has colons of its own ("::1").
  defp refusal(error) when is_binary(error) do
    case Regex.run(~r/(?:^|; )([^\s;]+): url_not_allowed:([a-z_]+)/, error) do
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

  # --- S29 closing act begin ---
  @doc """
  The basis sentence under the chart while the bands are drawn on the time
  axis (board 07 ④, ⑤; ⑨ item 1): the series, the windows, the extremes,
  the anchor and the band rule, ending „no forecast“; on the range
  „Zyklus“ (`cycle_range?`) the range's own sentence first.
  """
  @spec basis_text(map(), boolean()) :: String.t()
  def basis_text(payload, cycle_range?) do
    basis =
      gettext(
        "Basis: stored daily closes in %{currency}, gaps skipped, never filled · windows from halving to halving (the close on a halving day belongs to the new window) · top and low = peak and trough of the largest decline in the window · an open top is an anchor from 20 % below it, a low only once the window closes · band: time min to max, price from the last factor to one log step further; hull of the parts, no average, no forecast.",
        currency: payload.currency_code
      )

    if cycle_range?,
      do:
        gettext(
          "Range „Cycle“: three months before the last confirmed halving to four months after the end of the later band; right of „today“ only the halving window and the bands."
        ) <> " " <> basis,
      else: basis
  end

  # --- S29 closing act end ---

  # --- S29 H8 begin ---
  @doc """
  The range „Zyklus“ of a cycles read with the view (ADR-0060 §11; board
  07 ⑥): from three months before the last confirmed halving to four
  months after the later end of the next low's and the next top's bands,
  or after today where neither has a band. `nil` without the view.
  """
  @spec cycle_range(map() | nil) :: {Date.t(), Date.t()} | nil
  def cycle_range(payload) do
    with true <- view?(payload),
         %{date: %Date{} = last} <- payload.halvings |> Enum.filter(& &1.confirmed) |> List.last() do
      ends =
        case for(event <- events(payload), event.band, do: event.band.window.to) do
          [] -> [Clock.today()]
          ends -> ends
        end

      {Date.shift(last, month: -3), Date.shift(Enum.max(ends, Date), month: 4)}
    else
      _no_view -> nil
    end
  end

  # --- S29 H8 end ---

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
      <rect
        :for={w <- @marks.halving_windows}
        class="cycle-halving-window"
        data-date={Date.to_iso8601(w.from)}
        data-to={Date.to_iso8601(w.to)}
        x={w.x}
        y={@scale.y0}
        width={w.w}
        height={@scale.y1 - @scale.y0}
      />
      <line
        :if={@marks.today}
        class="cycle-today"
        data-date={Date.to_iso8601(@marks.today.date)}
        x1={@marks.today.x}
        x2={@marks.today.x}
        y1={@scale.y0}
        y2={@scale.y1}
      />
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
        :if={@marks.today_label}
        class="cycle-label cycle-label--today"
        x={@marks.today_label.x}
        y={@marks.today_label.y}
        text-anchor="middle"
      >
        <%= pgettext("halving cycles", "today") %>
      </text>
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
        x={m.label_x}
        y={m.y}
        text-anchor={m.anchor}
      >
        <tspan :for={{line, index} <- Enum.with_index(m.lines)} x={m.label_x} dy={if index == 0, do: "0", else: "1.2em"}>
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
        <tspan
          :for={{line, index} <- Enum.with_index(b.lines)}
          class={index > 0 && "cycle-label__more"}
          x={b.x}
          dy={if index == 0, do: "0", else: "1.2em"}
        >
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
      halving_windows: halving_windows(payload, scale),
      today: today_mark(scale),
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
        %{date: %Date{} = date} = next ->
          if within?(date, scale),
            do: [
              %{
                date: date,
                date_end: next[:date_end],
                x: coord(scale.x.(date)),
                x_value: scale.x.(date),
                estimate?: true
              }
            ],
            else: []

        _none ->
          []
      end

    confirmed ++ estimate
  end

  # --- S29 H8 begin ---
  # The next halving's window (ADR-0059 §6), between its two dates, where
  # the read stores one.
  defp halving_windows(%{next_halving: %{date: %Date{} = from, date_end: %Date{} = to}}, scale) do
    if overlaps?(%{from: from, to: to}, scale.first, scale.last) do
      x1 = scale.x.(from)

      [
        %{
          from: from,
          to: to,
          x: coord(x1),
          w: coord(max(scale.x.(to) - x1, 1.0))
        }
      ]
    else
      []
    end
  end

  defp halving_windows(_payload, _scale), do: []

  # „heute“, only where the axis reaches past today (the range „Zyklus“).
  defp today_mark(scale) do
    today = Clock.today()

    if within?(today, scale) and Date.compare(scale.last, today) == :gt,
      do: %{date: today, x: coord(scale.x.(today)), x_value: scale.x.(today)}
  end

  # --- S29 H8 end ---

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
      today_label: today_label(scale),
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
      lines = extreme_lines(kind, date, close, provisional?, so_far?, partial?, currency)
      {label_x, anchor} = edge_anchor(x, scale.x0, scale.x1)

      {d, label_y} =
        case kind do
          :top -> {triangle_down(x, y - 3), clamp(y - 16, scale.y0 + 22, scale.y1 - 4)}
          :low -> {triangle_up(x, y + 3), low_label_y(y, length(lines), scale)}
        end

      %{
        kind: kind,
        date: date,
        d: d,
        x: coord(x),
        label_x: coord(label_x),
        anchor: anchor,
        y: coord(label_y),
        provisional?: provisional?,
        so_far?: so_far?,
        lines: lines,
        title: extreme_title(kind, date, close, currency)
      }
    end
  end

  # Board 07 ⑨ item 3 (the closing act's design lens): a label near the
  # plot's right edge ends at the edge, one near its left edge starts at
  # it, so no label is cut off; elsewhere it is centred on its marker.
  @edge_room 70

  defp edge_anchor(x, x0, x1) do
    cond do
      x > x1 - @edge_room -> {min(x + 6, x1 - 2), "end"}
      x < x0 + @edge_room -> {max(x - 6, x0 + 2), "start"}
      true -> {x, "middle"}
    end
  end

  # A low's label stands under its marker; where its lines would run off
  # the floor, above it, so it never covers the marker (board 07 ⑨ item 3).
  @label_line 11

  defp low_label_y(y, lines, scale) do
    below = y + 22

    if below + (lines - 1) * @label_line > scale.y1 - 4,
      do: max(y - 6 - (lines - 1) * @label_line, scale.y0 + 10),
      else: below
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

  # „heute“ on the time axis' own row, under its line, where the first and
  # the last date leave it room.
  defp today_label(scale) do
    with %{x_value: x} <- today_mark(scale),
         fraction = (x - scale.x0) / max(scale.x1 - scale.x0, 1),
         true <- fraction > 0.12 and fraction < 0.88 do
      %{x: coord(x), y: coord(scale.y1 + 22)}
    else
      _none -> nil
    end
  end

  defp halving_labels(payload, scale) do
    for h <- halving_marks(payload, scale) do
      text =
        cond do
          not h.estimate? ->
            gettext("Halving %{date}", date: Format.date(h.date))

          # S29 H8: the window the chain reader stores (ADR-0059 §6).
          match?(%Date{}, h[:date_end]) ->
            gettext("Halving ≈ %{from} – %{to} (estimate)",
              from: Format.date(h.date),
              to: Format.date(h.date_end)
            )

          true ->
            gettext("Halving ≈ %{date} (estimate)", date: Format.date(h.date))
        end

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

  # ------------------------------------------------------ „Ausgerichtet“

  @aligned_width 960
  @aligned_height 320
  @aligned_plot {56, 16, 936, 292}

  attr(:payload, :map, required: true, doc: "the cycles read with include: :aligned")

  @doc """
  „Ausgerichtet“ (ADR-0060 §11; board 01, A): the windows laid over each
  other from their halving, each close indexed to its halving day's close
  (`aligned` in the read) on a log scale, the open window drawn strong; the
  tops and lows at their cycle day; the next low's band in the open
  window's days. Its axis is an index (×) and its x the days since the
  halving, so it carries no amount and the privacy mode keeps it.
  """
  def aligned(assigns) do
    assigns = assign(assigns, :g, aligned_geometry(assigns.payload))

    ~H"""
    <div class="cycle-aligned" data-role="cycle-aligned">
      <div class="chart-frame" id="cycle-aligned-frame" phx-hook="ChartScale">
        <svg
          class="security-chart cycle-aligned-chart"
          role="img"
          aria-label={gettext("The cycles laid over each other from their halving")}
          viewBox={"0 0 #{@g.width} #{@g.height}"}
          preserveAspectRatio="xMidYMid meet"
          width="100%"
        >
          <g class="chart-axes" stroke="currentColor" stroke-opacity="0.15">
            <line :for={t <- @g.y_ticks} x1={@g.x0} y1={t.y} x2={@g.x1} y2={t.y} />
            <line :for={t <- @g.x_ticks} x1={t.x} y1={@g.y0} x2={t.x} y2={@g.y1} />
          </g>
          <line class="cycle-aligned__base" x1={@g.x0} x2={@g.x1} y1={@g.base_y} y2={@g.base_y} />
          <g :if={@g.band} class="cycle-layer">
            <rect
              class="cycle-band cycle-band--low"
              data-event="next_low"
              data-from-day={@g.band.from_day}
              data-to-day={@g.band.to_day}
              x={@g.band.rect.x}
              y={@g.band.rect.y}
              width={@g.band.rect.w}
              height={@g.band.rect.h}
            />
            <rect
              :if={@g.band.agree}
              class="cycle-band__agree cycle-band__agree--low"
              data-event="next_low"
              x={@g.band.agree.x}
              y={@g.band.agree.y}
              width={@g.band.agree.w}
              height={@g.band.agree.h}
            />
          </g>
          <polyline
            :for={w <- @g.windows}
            class={[
              "cycle-aligned__line",
              "cycle-aligned__line--#{w.tone}",
              w.open? && "is-open",
              w.partial? && "is-partial"
            ]}
            data-start={Date.to_iso8601(w.start)}
            fill="none"
            points={w.points}
          />
          <path
            :for={m <- @g.marks}
            class={["cycle-#{m.kind}", m.so_far? && "is-so-far"]}
            data-days={m.days}
            d={m.d}
          >
            <title><%= m.text %></title>
          </path>
          <g class="chart-axis-labels">
            <text
              :for={{t, index} <- Enum.with_index(@g.y_ticks)}
              class={["chart-axis-y", index == length(@g.y_ticks) - 1 && "is-top"]}
              x={@g.x0 - 6}
              y={t.y}
              text-anchor="end"
              dominant-baseline="central"
            >
              <%= t.text %>
            </text>
            <text
              :for={t <- @g.x_ticks}
              class="chart-axis-x"
              x={t.x}
              y={@g.height - 6}
              text-anchor="middle"
            >
              <%= t.text %>
            </text>
          </g>
          <text
            :for={m <- @g.marks}
            class={["cycle-label", "cycle-label--#{m.kind}"]}
            x={m.label_x}
            y={m.label_y}
            text-anchor={m.anchor}
          >
            <%= m.text %>
          </text>
          <text
            :if={@g.band}
            class="cycle-label cycle-label--band"
            data-event="next_low"
            x={@g.band.label_x}
            y={@g.band.label_y}
            text-anchor="start"
          >
            <%= @g.band.text %>
          </text>
        </svg>
      </div>
      <ul class="chart-legend" data-role="cycle-aligned-legend">
        <li :for={w <- @g.legend} class="chart-legend__item">
          <svg :if={w.tone} class="chart-legend__swatch--line" viewBox="0 0 18 2" width="18" height="2" aria-hidden="true">
            <line x1="0" y1="1" x2="18" y2="1" class={"cycle-aligned__line cycle-aligned__line--#{w.tone}"} stroke-width="2" />
          </svg>
          <%= w.text %>
        </li>
      </ul>
      <p class="detail-tab-hint" data-role="cycle-aligned-basis">
        <%= gettext(
          "x: calendar days since the halving · y: close ÷ the last close on or before the halving day, on a log scale · a window without such a close is left out"
        ) %>
      </p>
    </div>
    """
  end

  defp aligned_geometry(payload) do
    {x0, y0, x1, y1} = @aligned_plot
    cycles = Map.new(payload.cycles, &{&1.start, &1})
    drawn = Enum.filter(Map.get(payload, :aligned, []), &(&1.reason == nil and &1.points != []))
    open = Enum.find(payload.cycles, &(&1.kind == :open))
    open_base = open && Enum.find_value(drawn, &(&1.start == open.start && &1.base.close))
    band = aligned_band(payload, open, open_base)

    marks = Enum.flat_map(drawn, &aligned_marks(&1, Map.get(cycles, &1.start)))

    indices =
      Enum.flat_map(drawn, fn w -> Enum.map(w.points, & &1.index) end) ++
        Enum.map(marks, & &1.index) ++
        if(band, do: [band.price.from, band.price.to], else: [])

    logs =
      indices
      |> Enum.map(&Decimal.to_float/1)
      |> Enum.filter(&(&1 > 0))
      |> Enum.map(&:math.log10/1)

    {lmin, lmax} = pad_log(Enum.min([0.0 | logs]), Enum.max([0.0 | logs]))

    max_day =
      Enum.max(
        [1461] ++
          Enum.flat_map(drawn, fn w -> Enum.map(w.points, & &1.days) end) ++
          if(band, do: [band.to_day], else: [])
      )

    x = fn days -> x0 + (x1 - x0) * days / max_day end

    y = fn index ->
      value = index |> to_float() |> max(1.0e-9) |> :math.log10()
      y1 - (y1 - y0) * (value - lmin) / (lmax - lmin)
    end

    windows =
      drawn
      |> Enum.with_index()
      |> Enum.map(fn {w, i} ->
        cycle = Map.get(cycles, w.start)

        %{
          start: w.start,
          open?: match?(%{kind: :open}, cycle),
          partial?: match?(%{kind: :partial}, cycle),
          tone: if(match?(%{kind: :open}, cycle), do: "open", else: "past-#{rem(i, 3)}"),
          points: Enum.map_join(w.points, " ", &"#{coord(x.(&1.days))},#{coord(y.(&1.index))}")
        }
      end)

    %{
      width: @aligned_width,
      height: @aligned_height,
      x0: x0,
      y0: y0,
      x1: x1,
      y1: y1,
      base_y: coord(y.(1)),
      windows: windows,
      legend: aligned_legend(payload, windows),
      marks: marks |> Enum.map(&place_mark(&1, x, y)) |> separate_labels({x0, y0, x1, y1}),
      band: band && place_band(band, x, y, {x0, y0, x1, y1}),
      y_ticks: index_ticks(lmin, lmax) |> Enum.map(&%{y: coord(y.(&1)), text: index_text(&1)}),
      x_ticks:
        for(
          day <- 0..max_day//365,
          do: %{x: coord(x.(day)), text: gettext("day %{days}", days: day)}
        )
    }
  end

  defp aligned_marks(window, cycle) do
    base = window.base.close

    top =
      case cycle && cycle.top do
        %{date: %Date{} = date, close: %Decimal{} = close} ->
          days = Date.diff(date, window.start)

          [
            %{
              kind: :top,
              days: days,
              index: Decimal.div(close, base),
              so_far?: false,
              text: gettext("Top day %{days}", days: days)
            }
          ]

        _none ->
          []
      end

    low =
      case cycle && {cycle.low, cycle.low_so_far} do
        {%{date: %Date{} = date, close: %Decimal{} = close}, _so_far} ->
          days = Date.diff(date, window.start)

          [
            %{
              kind: :low,
              days: days,
              index: Decimal.div(close, base),
              so_far?: false,
              text: gettext("Low day %{days}", days: days)
            }
          ]

        {nil, %{date: %Date{} = date, close: %Decimal{} = close}} ->
          days = Date.diff(date, window.start)

          [
            %{
              kind: :low,
              days: days,
              index: Decimal.div(close, base),
              so_far?: true,
              text: gettext("Low so far, day %{days} (provisional)", days: days)
            }
          ]

        _none ->
          []
      end

    top ++ low
  end

  defp place_mark(mark, x, y) do
    mx = x.(mark.days)
    my = y.(mark.index)

    {d, label_y} =
      case mark.kind do
        :top -> {triangle_down(mx, my - 3), my - 16}
        :low -> {triangle_up(mx, my + 3), my + 22}
      end

    Map.merge(mark, %{mx: mx, ly: label_y, x: coord(mx), d: d})
  end

  # Board 07 ⑨ item 3: two windows' marks a day apart put their labels on
  # top of each other. Taken from left to right, a label that would cover
  # one already placed steps a line away from its marker (down for a low,
  # up for a top) until it is clear; then each is anchored at the plot's
  # edges as on the time axis.
  @label_clear_x 90
  @label_clear_y 12

  defp separate_labels(marks, {x0, y0, x1, y1}) do
    marks
    |> Enum.with_index()
    |> Enum.sort_by(fn {mark, _index} -> mark.mx end)
    |> Enum.reduce([], fn {mark, index}, placed ->
      [{%{mark | ly: clear_y(mark, Enum.map(placed, &elem(&1, 0)), y0, y1)}, index} | placed]
    end)
    |> Enum.sort_by(&elem(&1, 1))
    |> Enum.map(fn {mark, _index} ->
      {label_x, anchor} = edge_anchor(mark.mx, x0, x1)
      Map.merge(mark, %{label_x: coord(label_x), anchor: anchor, label_y: coord(mark.ly)})
    end)
  end

  defp clear_y(mark, placed, y0, y1, tries \\ 6)
  defp clear_y(mark, _placed, _y0, _y1, 0), do: mark.ly

  defp clear_y(mark, placed, y0, y1, tries) do
    covered? =
      Enum.any?(
        placed,
        &(abs(&1.mx - mark.mx) < @label_clear_x and abs(&1.ly - mark.ly) < @label_clear_y)
      )

    if covered? do
      step = if mark.kind == :low, do: @label_clear_y, else: -@label_clear_y
      clear_y(%{mark | ly: clamp(mark.ly + step, y0 + 10, y1 + 18)}, placed, y0, y1, tries - 1)
    else
      mark.ly
    end
  end

  # The next low's band in the open window's days, indexed to its halving
  # day's close (ADR-0060 §11).
  defp aligned_band(
         %{projection: %{next_low: %{band: %{} = band} = event}},
         %{start: start},
         %Decimal{} = base
       ) do
    %{
      from_day: Date.diff(band.window.from, start),
      to_day: Date.diff(band.window.to, start),
      price: %{from: Decimal.div(band.price.from, base), to: Decimal.div(band.price.to, base)},
      agree:
        event.agree &&
          %{from: Decimal.div(event.agree.from, base), to: Decimal.div(event.agree.to, base)},
      n: event.parts |> Enum.filter(&(&1.reason == nil)) |> Enum.map(& &1.n_time)
    }
  end

  defp aligned_band(_payload, _open, _base), do: nil

  defp place_band(band, x, y, {_x0, y0, _x1, y1}) do
    left = x.(band.from_day)
    right = x.(band.to_day)

    box = fn %{from: from, to: to} ->
      ya = y.(from)
      yb = y.(to)

      %{
        x: coord(left),
        y: coord(min(ya, yb)),
        w: coord(max(right - left, 1.0)),
        h: coord(max(abs(ya - yb), 1.0))
      }
    end

    Map.merge(band, %{
      rect: box.(band.price),
      agree: band.agree && box.(band.agree),
      label_x: coord(right + 4),
      label_y: coord(clamp(y.(band.price.to) + 9, y0 + 9, y1 - 4)),
      text: gettext("Low band, days %{from}–%{to}", from: band.from_day, to: band.to_day)
    })
  end

  defp aligned_legend(payload, windows) do
    drawn = MapSet.new(windows, & &1.start)
    tones = Map.new(windows, &{&1.start, &1.tone})

    for cycle <- payload.cycles do
      year = Integer.to_string(cycle.start.year)

      text =
        cond do
          not MapSet.member?(drawn, cycle.start) ->
            gettext("%{year}: no close on its halving day", year: year)

          cycle.kind == :open ->
            gettext("%{year} (running)", year: year)

          cycle.kind == :partial ->
            gettext("%{year} (partial)", year: year)

          true ->
            year
        end

      %{tone: Map.get(tones, cycle.start), text: text}
    end
  end

  defp pad_log(min, max) when min == max, do: {min - 0.3, max + 0.3}
  defp pad_log(min, max), do: {min - (max - min) * 0.06, max + (max - min) * 0.06}

  # Powers of two between the ends, at most six: ×0.25, ×1, ×4, ×16 …
  defp index_ticks(lmin, lmax) do
    low = ceil(lmin / :math.log10(2))
    high = floor(lmax / :math.log10(2))
    count = high - low + 1
    step = max(1, ceil(count / 6))

    for e <- low..high//step, do: :math.pow(2, e)
  end

  defp index_text(value) do
    places = if value >= 1, do: 0, else: 2
    "×" <> Format.plain_decimal(Decimal.from_float(value * 1.0), places)
  end

  defp to_float(%Decimal{} = value), do: Decimal.to_float(value)
  defp to_float(value) when is_number(value), do: value * 1.0

  # ------------------------------------------------------ the interval table

  @relations [
    :halving_to_top,
    :top_to_low,
    :low_to_top,
    :top_to_top,
    :low_to_low,
    :low_to_next_halving
  ]

  attr(:payload, :map, required: true)

  @doc """
  The count line and the interval table under the chart (ADR-0060 §3, §11,
  §12; board 07 ④, Q9): a column per window from its halving year (the
  partial one marked „Teil“, the open one „offen“), a row per relation with
  each observation's days and change or factor, its n and which of its
  observations are provisional or from the partial window.
  """
  def intervals(assigns) do
    ~H"""
    <div class="cycle-intervals">
      <p class="cycle-count" data-role="cycle-count"><%= count_text(@payload) %></p>
      <div class="data-table-wrapper">
        <table class="data-table cycle-intervals-table" data-role="cycle-intervals">
          <thead>
            <tr>
              <th scope="col"><%= gettext("Segment · from cycle") %></th>
              <th :for={cycle <- @payload.cycles} scope="col" class="num" data-window={Date.to_iso8601(cycle.start)}>
                <%= cycle.start.year %>
                <span :if={cycle.kind == :partial} class="badge"><%= pgettext("halving cycles", "Part") %></span>
                <span :if={cycle.kind == :open} class="badge badge--derived"><%= pgettext("halving cycles", "open") %></span>
              </th>
              <th scope="col" class="num">n</th>
              <th scope="col"><%= gettext("Marks") %></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={relation <- relations()} data-relation={relation}>
              <th scope="row"><%= relation_label(relation) %></th>
              <td
                :for={cycle <- @payload.cycles}
                class="num"
                data-window={Date.to_iso8601(cycle.start)}
              >
                <% obs = observation_in(@payload, relation, cycle.start) %>
                <%= if obs do %>
                  <%= observation_text(obs) %>
                  <span :if={obs.partial} class="badge"><%= pgettext("halving cycles", "Part") %></span>
                  <span :if={obs.provisional} class="badge badge--derived"><%= pgettext("halving cycles", "provisional") %></span>
                <% else %>
                  —
                <% end %>
              </td>
              <td class="num" data-role="n">n = <%= relation_n(@payload, relation) %></td>
              <td data-role="marks"><%= relation_marks(@payload, relation) %></td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  @doc false
  def relations, do: @relations

  defp count_text(payload) do
    counts = get_in(payload, [:computation_basis, :counts]) || %{}
    first = get_in(payload, [:computation_basis, :series, :first_close])

    gettext(
      "Cycles: %{complete} complete, %{partial} partial, %{open} open · closes from %{month}",
      complete: Map.get(counts, :cycles_complete, 0),
      partial: Map.get(counts, :cycles_partial, 0),
      open: if(Map.get(counts, :cycle_open), do: 1, else: 0),
      month: Format.month(first)
    )
  end

  defp observation_in(payload, relation, start) do
    payload.intervals
    |> observations(relation)
    |> Enum.find(&(&1.from.window_start == start))
  end

  defp relation_n(payload, relation) do
    case Map.get(payload.intervals || %{}, relation) do
      %{n: n} -> n
      _none -> 0
    end
  end

  defp relation_marks(payload, relation) do
    obs = observations(payload.intervals || %{}, relation)
    provisional = Enum.count(obs, & &1.provisional)
    partial = Enum.count(obs, & &1.partial)

    [
      provisional > 0 && ngettext("%{count} provisional", "%{count} provisional", provisional),
      partial > 0 &&
        ngettext("%{count} from the partial cycle", "%{count} from the partial cycle", partial)
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end

  @doc "A relation's name as the screen writes it."
  @spec relation_label(atom()) :: String.t()
  def relation_label(:halving_to_top), do: gettext("Halving → top")
  def relation_label(:top_to_low), do: gettext("Top → low")
  def relation_label(:low_to_top), do: gettext("Low → top")
  def relation_label(:top_to_top), do: gettext("Top → top")
  def relation_label(:low_to_low), do: gettext("Low → low")
  def relation_label(:low_to_next_halving), do: gettext("Low → next halving")

  # ------------------------------------------- „Bänder und ihre Teile“

  attr(:payload, :map, required: true)

  @doc """
  The disclosure „Bänder und ihre Teile“ (ADR-0060 §4, §5, §7; board 07
  ⑤, Q8): each event's band (the hull of its parts) with its window, its
  price range, where the ways agree and its state, then each part with
  where it is read from and its n, or why it is absent. Prices are amounts:
  the privacy mode hides them as every amount (`Format.decimal/3`).
  """
  def bands(assigns) do
    ~H"""
    <details class="perf-table-disclosure cycle-bands" data-role="cycle-bands">
      <summary class="disclosure-summary">
        <PortfolixirWeb.AppShell.icon name={:chevron_right} size={12} class="disclosure-chevron" />
        <%= gettext("Bands and their parts") %>
      </summary>
      <p class="detail-tab-hint">
        <%= gettext(
          "Not a forecast: each band is the range the stored cycles' intervals and factors give from the current anchors, with its n and both ends; never a single date or price, nothing fitted, nothing averaged."
        ) %>
      </p>
      <div class="data-table-wrapper">
        <table class="data-table cycle-bands-table">
          <thead>
            <tr>
              <th scope="col"><%= gettext("Band · part") %></th>
              <th scope="col"><%= gettext("Read from") %></th>
              <th scope="col" class="num"><%= pgettext("halving cycles", "Window") %></th>
              <th scope="col" class="num"><%= pgettext("halving cycles", "Price") %></th>
              <th scope="col"><%= gettext("Where the ways agree") %></th>
              <th scope="col"><%= gettext("State") %></th>
            </tr>
          </thead>
          <tbody>
            <%= for event <- events(@payload) do %>
              <tr class="cycle-bands__event" data-row={event.event}>
                <th scope="row"><%= event_label(event.event) %></th>
                <td data-role="origin"><%= event_origin(event) %></td>
                <td class="num" data-role="window"><%= event.band && window_text(event.band.window) %></td>
                <td class="num" data-role="price"><%= event.band && price_text(event.band.price, @payload.currency_code) %></td>
                <td data-role="agree">
                  <%= agree_cell(event, @payload.currency_code) %>
                  <code :if={event.agree_reason} class="cycle-bands__reason"><%= event.agree_reason %></code>
                </td>
                <td data-role="state"><%= state_text(event) %></td>
              </tr>
              <tr :for={part <- event.parts} class="cycle-bands__part" data-relation={part.relation}>
                <th scope="row"><%= relation_label(part.relation) %></th>
                <td data-role="origin">
                  <%= part_origin(part) %>
                  <%!-- Board 07 ⑨ item 5: a part that is absent carries no badge. --%>
                  <span :if={part.partial and is_nil(part.reason)} class="badge"><%= pgettext("halving cycles", "Part") %></span>
                  <span :if={part.provisional and is_nil(part.reason)} class="badge badge--derived"><%= pgettext("halving cycles", "provisional") %></span>
                </td>
                <td class="num" data-role="window"><%= part.window && window_text(part.window) %></td>
                <td class="num" data-role="price"><%= part.price && price_text(part.price, @payload.currency_code) %></td>
                <td></td>
                <td data-role="state"><%= if part.reason, do: "—", else: state_text(part) %></td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </details>
    """
  end

  # --- S29 H8 begin ---
  attr(:payload, :map, required: true, doc: "the cycles read of a security with the view")
  attr(:href, :string, required: true)

  @doc """
  The dashboard card „‹Name›-Zyklus“ (ADR-0060 §11; idea board 01, A's
  shortcut): the next low's and the next top's windows, price ranges and
  states, each band's parts with their n, the sentence that the band is no
  forecast, and the link that opens the security's chart with cycles on
  and the range „Zyklus“. The prices are hidden in the privacy mode, as in
  the disclosure; an event without a band says why.
  """
  def card(assigns) do
    ~H"""
    <section
      class="workspace-section cycle-card"
      data-role="cycle-card"
      data-security-id={@payload.security_id}
    >
      <div class="section-head">
        <h2><%= gettext("%{name} cycle", name: @payload.security_name) %></h2>
        <a class="kpi-summary__link" href={@href} data-role="cycle-card-open">
          <%= gettext("Open in chart →") %>
        </a>
      </div>
      <dl class="cycle-card__events">
        <div :for={event <- events(@payload)} class="cycle-card__event" data-event={event.event}>
          <dt><%= event_label(event.event) %></dt>
          <%= if event.band do %>
            <dd class="num" data-role="window"><%= window_text(event.band.window) %></dd>
            <dd class="num" data-role="price"><%= price_text(event.band.price, @payload.currency_code) %></dd>
            <dd data-role="state"><%= state_text(event) %></dd>
            <dd class="cycle-card__parts" data-role="parts"><%= parts_text(event) %></dd>
          <% else %>
            <dd data-role="reason"><%= absent_text(event.reason, event) %></dd>
          <% end %>
        </div>
      </dl>
      <p class="hint cycle-card__basis">
        <%= gettext(
          "The range the stored cycles give from the current anchors, with its n and both ends: not a forecast."
        ) %>
      </p>
    </section>
    """
  end

  # Each part a band is the hull of, with its time n (ADR-0060 §4).
  defp parts_text(event) do
    event.parts
    |> Enum.filter(&is_nil(&1.reason))
    |> Enum.map_join(" · ", &(relation_label(&1.relation) <> " n = " <> to_string(&1.n_time)))
  end

  # --- S29 H8 end ---

  defp event_label(:next_low), do: gettext("Next low")
  defp event_label(:next_top), do: gettext("Next top")

  defp event_origin(%{band: nil} = event), do: absent_text(event.reason, event)
  defp event_origin(_event), do: gettext("hull of the parts")

  defp window_text(%{from: from, to: to}), do: Format.date(from) <> " – " <> Format.date(to)

  # Two places, the house's amount form, hidden in the privacy mode.
  defp price_text(%{from: from, to: to}, currency) do
    if PrivacyMode.on?(),
      do: PrivacyMode.hidden(),
      else: "#{Format.decimal(from, 2)} – #{Format.decimal(to, 2)} #{currency}"
  end

  defp agree_cell(%{agree: %{} = agree}, currency) do
    if PrivacyMode.on?(),
      do: gettext("both ways"),
      else: gettext("both ways %{range}", range: price_text(agree, currency))
  end

  defp agree_cell(event, currency), do: agree_text(event, currency)

  defp part_origin(%{reason: reason} = part) when not is_nil(reason),
    do: absent_text(reason, part)

  defp part_origin(part) do
    from = anchor_text(part.anchor)

    n =
      if part.price_from,
        do:
          gettext("time n = %{time}, price from %{relation}",
            time: part.n_time,
            relation: relation_label(part.price_from)
          ),
        else:
          gettext("time n = %{time}, price n = %{price}", time: part.n_time, price: part.n_price)

    rule =
      if part.price_rule == :min_max,
        do: [" · " <> gettext("price from the minimum to the maximum: no log step")],
        else: []

    Enum.join([from, " · ", n | rule])
  end

  defp anchor_text(%{event: :top, date: date}),
    do: gettext("from the top of %{month}", month: Format.month(date))

  defp anchor_text(%{event: :low, date: date}),
    do: gettext("from the low of %{month}", month: Format.month(date))

  defp anchor_text(%{event: :halving}), do: gettext("from the halving window")
  defp anchor_text(_none), do: "—"

  defp absent_text(:too_few_observations, item),
    do:
      gettext("too few observations (time n = %{time}, price n = %{price})",
        time: item[:n_time] || 0,
        price: item[:n_price] || 0
      )

  defp absent_text(:no_top_yet, _item),
    do: gettext("waits until the open window's top anchors (a fall of 20 %)")

  defp absent_text(:low_not_final, _item),
    do: gettext("waits until the running cycle's low is final (at the next halving)")

  defp absent_text(:zero_width, _item), do: gettext("a point, not a range: no part")
  defp absent_text(:no_parts, _item), do: gettext("no part has enough data")
  defp absent_text(reason, _item), do: to_string(reason)

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
