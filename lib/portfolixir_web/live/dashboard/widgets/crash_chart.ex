defmodule PortfolixirWeb.Dashboard.Widgets.CrashChart do
  @moduledoc """
  The widget „Crash-Chart“ `crash_chart` (I61; Sprint 32 S5; planning
  board `ux-design-2026-11-25-sprint32/11` ①, ②; the owner's description
  of 2026-11-25): the crash benchmark's stored closes over the widget's
  period, every crash window that falls into it shaded and named, the
  running one stronger. It follows the dashboard's period, so a copy
  pinned to „1M“ is the zoom.

  It reads what exists and computes no figure of its own (ADR-0058): the
  windows of `Portfolixir.Crashes.list_windows/0` (`GET /api/v1/crashes`;
  a detected window from its start to its recovery, or to today while it
  runs, a manual one from its start to its trough) and the benchmark's
  closes in their display basis, `Portfolixir.Catalog.Quotes.adjusted_range/3`
  (`GET /api/v1/securities/:security_id/quotes`, its `adjusted_close`),
  from the period's first day to today (`Portfolixir.Dashboards.Widgets.source_params/3`).
  Under it the period's first and last close, its lowest and its highest,
  so a screen reader and a test read what the line draws.

  The labels (the S32 closing act; board 11 ①, ②) stand above the plot
  in the page's type, so they keep 12 px however the chart scales; each
  runs from its window's start to the next label's and is cut there, so
  none overprints another. A window that began before the period has no
  label pinned to the left edge: the line under the chart names it, the
  running one „−11,2 % vom Hoch am 28.10. · läuft“.

  No verdict (ADR-0058 §8): the chart shows prices and names no action.
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Clock
  alias Portfolixir.Crashes
  alias Portfolixir.Dashboards.Widgets
  alias PortfolixirWeb.Dashboard.Widget
  alias PortfolixirWeb.Format

  @max_points 300
  @width 640
  @height 220
  @left 8
  @right 8
  @top 6
  @bottom 22

  # -- the read -----------------------------------------------------------------

  @doc """
  The widget's read for the dashboard period `period`: the crash
  benchmark, the period's `from` and `to`, its closes in date order
  (`%{date, close}`, the display basis) and the windows that overlap it,
  each `%{key, kind, name, start, end, decline, running}`, oldest first.
  `%{state: :no_benchmark}` when none is chosen; `:error` for a period
  that does not resolve today (a quarter not yet begun, a deleted own
  period).
  """
  @spec read(String.t()) :: map() | :error
  def read(period) do
    today = Clock.today()
    listing = Crashes.list_windows()

    case listing.benchmark do
      nil ->
        %{state: :no_benchmark}

      benchmark ->
        case Widgets.source_params("crash_chart", period, today) do
          {:ok, %{"from" => from, "to" => to}} ->
            drawn(
              listing,
              benchmark,
              period,
              Date.from_iso8601!(from),
              Date.from_iso8601!(to),
              today
            )

          {:error, _refusal} ->
            :error
        end
    end
  end

  defp drawn(listing, benchmark, period, from, to, today) do
    points =
      benchmark.id
      |> Quotes.adjusted_range(from, to)
      |> Enum.map(&%{date: &1.date, close: &1.close})

    %{
      state: :ok,
      period: period,
      benchmark: %{id: benchmark.id, name: benchmark.name, currency: benchmark.currency_code},
      from: from,
      to: to,
      points: points,
      windows:
        (listing.detected ++ listing.manual)
        |> Enum.map(&window(&1, today))
        |> Enum.filter(&overlaps?(&1, from, to))
        |> Enum.sort_by(& &1.start, Date)
    }
  end

  defp window(%{kind: "detected"} = window, today) do
    %{
      key: window.key,
      kind: "detected",
      name: window.name,
      start: window.start,
      end: window.recovered_on || today,
      decline: window.decline,
      running: Map.get(window, :provisional, false)
    }
  end

  defp window(window, _today) do
    %{
      key: window.key,
      kind: "manual",
      name: window.name,
      start: window.start,
      end: window.trough,
      decline: nil,
      running: false
    }
  end

  defp overlaps?(window, from, to),
    do: Date.compare(window.start, to) != :gt and Date.compare(window.end, from) != :lt

  # -- the widget ---------------------------------------------------------------

  attr(:item, :map, required: true)
  attr(:card, :any, required: true, doc: "nil while the read runs, :error, or `read/1`'s answer")

  @doc "The widget „Crash-Chart“ with its compact form."
  def widget(assigns) do
    ready = match?(%{state: :ok, points: [_, _ | _]}, assigns.card)

    assigns =
      assigns
      |> assign(:ready, ready)
      |> assign(:chart, if(ready, do: geometry(assigns.card), else: nil))
      |> assign(:summary, if(ready, do: summary(assigns.card.points), else: nil))

    ~H"""
    <Widget.frame
      id={"dashboard-crash-chart" <> @item.uid}
      item={@item}
      title={Widgets.title("crash_chart")}
      scope_label={gettext("Prices, no verdict")}
      full_href="/risk"
      full_label={gettext("All windows →")}
      full_role="crash-chart-all-windows"
    >
      <:info>
        <%= gettext("The crash benchmark's stored closes over the period, split-adjusted, in its own currency. Red: a crash window as the rule detects it on every read — it opens when the close falls 10% or more below its last high and closes when it is back at that high; the running one stronger. A manual window is shaded from its start to its low.") %>
      </:info>
      <:shared>
        <%!-- Sprint 32 L2 (board 07 ① 1): the head holds the kind's title
             alone, so a long fund name never cuts it; the benchmark is the
             line under it. --%>
        <p :if={match?(%{state: :ok}, @card)} class="widget-subline" data-role="crash-chart-benchmark">
          <%= @card.benchmark.name %>
        </p>
        <p :if={is_nil(@card)} class="section-skeleton" aria-busy="true" data-role="crash-chart-skeleton"></p>
        <p :if={@card == :error} class="hint" data-role="crash-chart-failed">
          <%= gettext("Couldn't load the crash windows.") %>
        </p>
        <p :if={match?(%{state: :no_benchmark}, @card)} class="hint" data-role="crash-chart-empty">
          <%= gettext("No crash benchmark chosen: the windows are detected on its closes.") %>
        </p>
        <p :if={match?(%{state: :ok}, @card) and not @ready} class="hint" data-role="crash-chart-empty">
          <%= gettext("Too few closes of the crash benchmark in this period to draw a line.") %>
        </p>
      </:shared>
      <figure :if={@ready} class="crash-chart" data-role="crash-chart">
        <%!-- The S32 closing act (board 11 ①, ②): the labels stand above
             the plot in the page's type, never scaled with it, each from
             its window's start to the next label's, cut there; a window
             that began before the period has none here, the line under
             the chart names it. --%>
        <div :if={@chart.labels != []} class="crash-chart__labels">
          <span
            :for={label <- @chart.labels}
            class={["crash-chart__label", label.running && "is-running"]}
            style={"left: #{label.left}%; max-width: #{label.room}%;"}
            title={label.text}
            data-role="crash-chart-label"
            data-key={label.key}
          ><%= label.text %></span>
        </div>
        <svg
          class="crash-chart__plot"
          viewBox={"0 0 #{@chart.width} #{@chart.height}"}
          preserveAspectRatio="none"
          role="img"
          aria-label={gettext("%{benchmark} from %{from} to %{to}", benchmark: @card.benchmark.name, from: Format.date(@card.from), to: Format.date(@card.to))}
          data-role="crash-chart-svg"
          data-points={length(@chart.points)}
        >
          <g :for={window <- @chart.windows} data-role="crash-chart-window" data-key={window.key}>
            <rect
              class={["crash-chart__window", window.running && "is-running"]}
              x={window.x}
              y={@chart.top}
              width={window.width}
              height={@chart.plot_height}
            />
          </g>
          <path class="crash-chart__line" d={@chart.path} fill="none" />
        </svg>
        <figcaption class="crash-chart__summary" data-role="crash-chart-summary">
          <span
            :for={window <- @chart.before}
            class="crash-chart__before"
            data-role="crash-chart-before"
            data-key={window.key}
          ><%= before(window) %></span>
          <span data-role="crash-chart-first"><%= Format.date(@summary.first.date) %>: <%= Format.money(@summary.first.close) %></span>
          <span data-role="crash-chart-low"><%= gettext("Low %{value}", value: Format.money(@summary.low.close)) %></span>
          <span data-role="crash-chart-high"><%= gettext("High %{value}", value: Format.money(@summary.high.close)) %></span>
          <span data-role="crash-chart-last"><%= Format.date(@summary.last.date) %>: <%= Format.money(@summary.last.close) %> <%= @card.benchmark.currency %></span>
        </figcaption>
      </figure>
      <:compact>
        <Widget.row
          :for={window <- if(@ready, do: Enum.reverse(@card.windows), else: [])}
          href="/risk"
          data-compact-role="crash-chart-window"
          data-key={window.key}
        >
          <:name><%= window.name || gettext("unnamed") %></:name>
          <:sub><%= dates(window) %></:sub>
          <:figure><span class="is-negative"><%= percent(window.decline) %></span></:figure>
        </Widget.row>
        <p :if={@ready} class="hint" data-compact-role="crash-chart-last">
          <%= Format.date(@summary.last.date) %>: <%= Format.money(@summary.last.close) %> <%= @card.benchmark.currency %>
        </p>
      </:compact>
    </Widget.frame>
    """
  end

  @doc false
  # The period's first, last, lowest and highest close (the earliest of
  # equal lows and highs).
  def summary(points) do
    %{
      first: List.first(points),
      last: List.last(points),
      low: Enum.min_by(points, & &1.close, fn a, b -> Decimal.compare(a, b) != :gt end),
      high: Enum.max_by(points, & &1.close, fn a, b -> Decimal.compare(a, b) != :lt end)
    }
  end

  # The drawing: floats only as coordinates, from the Decimal closes; the
  # line thinned to about `@max_points`, its first, last, lowest and
  # highest point kept.
  defp geometry(card) do
    points = thin(card.points)
    summary = summary(card.points)
    low = Decimal.to_float(summary.low.close)
    high = Decimal.to_float(summary.high.close)
    span = max(Date.diff(card.to, card.from), 1)
    plot_width = @width - @left - @right
    plot_height = @height - @top - @bottom

    x = fn date ->
      @left + Date.diff(clamp(date, card.from, card.to), card.from) / span * plot_width
    end

    y = fn close ->
      range = if high == low, do: 1.0, else: high - low
      @top + (high - Decimal.to_float(close)) / range * plot_height
    end

    path =
      points
      |> Enum.with_index()
      |> Enum.map_join(" ", fn {point, index} ->
        command = if index == 0, do: "M", else: "L"
        "#{command}#{round2(x.(point.date))},#{round2(y.(point.close))}"
      end)

    windows =
      Enum.map(card.windows, fn window ->
        x1 = x.(window.start)
        x2 = x.(window.end)

        Map.merge(window, %{
          x: round2(x1),
          width: round2(max(x2 - x1, 1.0))
        })
      end)

    {before, inside} = Enum.split_with(windows, &(Date.compare(&1.start, card.from) == :lt))

    %{
      width: @width,
      height: @height,
      top: @top,
      plot_height: plot_height,
      path: path,
      points: points,
      windows: windows,
      labels: labels(inside),
      before: before
    }
  end

  # The labels of the windows that begin inside the period, oldest first,
  # in per cent of the chart's width: each at its window's start, its room
  # up to the next label's start or the chart's right edge, so two labels
  # never overprint, however narrow the tile (the S32 closing act).
  defp labels(windows) do
    starts = Enum.map(windows, &(&1.x / @width * 100))
    ends = Enum.drop(starts, 1) ++ [100.0]

    [windows, starts, ends]
    |> Enum.zip()
    |> Enum.map(fn {window, left, right} ->
      %{
        key: window.key,
        running: window.running,
        text: label(window),
        left: round2(left),
        room: round2(max(right - left, 0.0))
      }
    end)
  end

  defp clamp(date, from, to) do
    cond do
      Date.compare(date, from) == :lt -> from
      Date.compare(date, to) == :gt -> to
      true -> date
    end
  end

  defp round2(value), do: Float.round(value * 1.0, 2)

  defp thin(points) when length(points) <= @max_points, do: points

  defp thin(points) do
    step = ceil(length(points) / @max_points)
    summary = summary(points)

    keep =
      MapSet.new([summary.first.date, summary.last.date, summary.low.date, summary.high.date])

    points
    |> Enum.with_index()
    |> Enum.filter(fn {point, index} -> rem(index, step) == 0 or point.date in keep end)
    |> Enum.map(&elem(&1, 0))
  end

  defp label(%{running: true} = window),
    do: gettext("running %{decline}", decline: percent(window.decline))

  defp label(%{decline: nil} = window), do: window.name || gettext("unnamed")

  defp label(window),
    do: (window.name || gettext("unnamed")) <> " " <> percent(window.decline)

  # A window that began before the period, said under the chart (board 11
  # ②): the running one as the board words it, „−11,2 % vom Hoch am 28.10.
  # · läuft“; any other by its label and its first day.
  defp before(%{running: true} = window),
    do:
      gettext("%{decline} from the high on %{date} · running",
        decline: percent(window.decline),
        date: Format.date(window.start)
      )

  defp before(window),
    do:
      gettext("%{window} · since %{date}", window: label(window), date: Format.date(window.start))

  defp dates(window),
    do:
      gettext("%{start} → %{end}",
        start: Format.date(window.start),
        end: Format.date(window.end)
      )

  defp percent(%Decimal{} = value), do: Format.signed_percent(value) <> "%"
  defp percent(_none), do: "—"
end
