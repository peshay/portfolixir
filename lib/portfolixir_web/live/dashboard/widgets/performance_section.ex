defmodule PortfolixirWeb.Dashboard.Widgets.PerformanceSection do
  @moduledoc """
  The section widget „Performance“: the kind `performance` at the size
  „Zeile“ (I57; Sprint 32 W1; ADR-0062's amendment of 2026-11-25, point 3;
  planning board `ux-design-2026-11-25-sprint32/02` ①). Wealth's section
  „Performance“ of the tab „Bestände“ — the % or value series, the level,
  the benchmark picker, the period's badge, the chart and „Daten als
  Tabelle“ — drawn by the code Wealth draws it with: `series_toggle/1`,
  `benchmark_picker/1`, `badge/1` and `chart/1` moved here from
  `PortfolixirWeb.PortfolioLive`, which renders them. The contribution
  table under Wealth's chart is its own widget, „Beitrag je Position“.

  **Its state.** On Wealth the series, the level and the filter ride the
  address, as before. On a dashboard the series and the level are the
  page's state for each widget (`DashboardLive`'s assigns, by the item's
  id suffix), not stored: a layout holds what a widget shows, never a
  passing view of it, and the dashboard's address already carries its own
  period and scope. The benchmark selection is the operator's one
  selection, remembered by `PortfolixirWeb.BenchmarkScope` in the session
  and a cookie: the picker is the same GET form, sent to the dashboard's
  own address, so Wealth and every dashboard compare against the same
  benchmarks. Its period is the top bar's (or the widget's pin), Wealth's
  custom range an own period (`saved:<id>`).

  **Its figures** are the performance family's for the widget's scope and
  period, as `GET /api/v1/performance` answers them
  (`Portfolixir.Portfolios.Performance`, summarised from the view's walk),
  the comparisons `GET /api/v1/performance/benchmark` answers
  (`Portfolixir.Portfolios.Performance.Benchmark.compare/3`), and at a
  level the bands `GET /api/v1/performance/bands` answers
  (`Portfolixir.Portfolios.Performance.Bands.for_view/2`), in the first
  portfolio's base currency, as Wealth reads them.
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Buckets
  alias Portfolixir.Catalog.BenchmarkSecurity
  alias Portfolixir.Clock
  alias Portfolixir.Dashboards.Widgets
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.Performance.Bands
  alias Portfolixir.Portfolios.Performance.Benchmark
  alias PortfolixirWeb.Api.V1.PeriodParam
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.BenchmarkChoices
  alias PortfolixirWeb.BenchmarkScope
  alias PortfolixirWeb.Components.SecurityChart
  alias PortfolixirWeb.Dashboard.Widget
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.LiveParam
  alias PortfolixirWeb.Portfolio.CategoryColors
  alias PortfolixirWeb.Portfolio.StackedChart
  alias PortfolixirWeb.PrivacyMode

  @chart_max_points 400
  @levels ~w(total category security)
  @modes ~w(ttwror value)

  @doc "The levels a dashboard's „Performance“ Zeile offers: Gesamt, Kategorien, Wertpapiere."
  @spec levels() :: [String.t()]
  def levels, do: @levels

  @doc "The series: % (TTWROR) or the value."
  @spec modes() :: [String.t()]
  def modes, do: @modes

  # -- the read -----------------------------------------------------------------

  @doc """
  The widget's read, in the page's background task, for the scope
  `view_id` (`nil`: Everything) over the dashboard period `period`, at
  `level` in the series `mode`, against the benchmark selectors
  `selectors`: `%{performance, benchmarks, comparisons, bands}` (`bands`
  nil at „Gesamt“, `:error` where its read refuses), or `:error`.
  """
  @spec read({integer() | nil, String.t(), String.t(), String.t()}, [String.t()]) ::
          map() | :error
  def read({view_id, period, level, mode}, selectors) do
    base_currency =
      case Portfolios.first_portfolio() do
        %{base_currency_code: code} -> code
        nil -> "EUR"
      end

    view_id = view_id && Buckets.get_view(view_id) && view_id

    with {:ok, params} <- Widgets.source_params("performance", period, Clock.today()),
         {:ok, term} <- PeriodParam.resolve(params),
         %{} = analysis <- Performance.view_analysis(view_id, base_currency: base_currency),
         {:ok, performance} <- Performance.summarise(analysis, term) do
      benchmarks = resolve_benchmarks(selectors)

      %{
        performance: performance,
        benchmarks: benchmarks,
        comparisons:
          for(
            benchmark <- benchmarks,
            {:ok, comparison} <- [Benchmark.compare(analysis, term, benchmark)],
            do: comparison
          ),
        bands: bands(view_id, term, base_currency, level, mode)
      }
    else
      _refused -> :error
    end
  end

  defp bands(_view_id, _term, _base, "total", _mode), do: nil

  defp bands(view_id, term, base_currency, level, mode) do
    opts = [
      period: term,
      base_currency: base_currency,
      level: if(level == "security", do: :security, else: :category),
      scale: if(mode == "ttwror", do: :ttwror, else: :value)
    ]

    case Bands.for_view(view_id, opts) do
      {:ok, result} -> result
      _refused -> :error
    end
  end

  # -- Wealth's section, moved ---------------------------------------------------

  attr(:mode, :string, required: true)
  attr(:value_label, :string, required: true)
  attr(:item, :string, default: nil, doc: "a dashboard widget's id suffix; nil on Wealth")

  @doc """
  The series toggle (issue 669; the app's one segmented control): % (TTWROR)
  or the value. Wealth answers `set_chart_mode` by its address, a
  dashboard by the widget named in `phx-value-item`.
  """
  def series_toggle(assigns) do
    ~H"""
    <div
      class="segmented-control"
      data-role="chart-series"
      role="group"
      aria-label={gettext("Chart series")}
    >
      <button
        type="button"
        class={["segmented-control__option", @mode == "ttwror" && "is-active"]}
        phx-click="set_chart_mode"
        phx-value-item={@item}
        phx-value-mode="ttwror"
        aria-pressed={to_string(@mode == "ttwror")}
      >
        <%= gettext("% (TTWROR)") %>
      </button>
      <button
        type="button"
        class={["segmented-control__option", @mode == "value" && "is-active"]}
        phx-click="set_chart_mode"
        phx-value-item={@item}
        phx-value-mode="value"
        aria-pressed={to_string(@mode == "value")}
      >
        <%= @value_label %>
      </button>
    </div>
    """
  end

  attr(:benchmarks, :list, required: true)
  attr(:groups, :list, required: true)
  attr(:action, :string, required: true, doc: "the page the GET form is sent to")
  attr(:id, :string, default: "benchmark-picker")

  @doc """
  The benchmark picker (ADR-0046 §4): a plain GET form the BenchmarkScope
  plug remembers in the session and a cookie, sent to the page it stands
  on.
  """
  def benchmark_picker(assigns) do
    # Wealth's ids as before; a dashboard picker's under its own id.
    wealth? = assigns.id == "benchmark-picker"

    assigns =
      assign(assigns,
        group_id: if(wealth?, do: "benchmark-group-", else: assigns.id <> "-group-"),
        rate_id: if(wealth?, do: "benchmark-rate", else: assigns.id <> "-rate")
      )

    ~H"""
    <details
      id={@id}
      class="period-disclosure"
      data-role="benchmark-picker"
      phx-hook="DisclosureState"
    >
      <summary class="disclosure-summary">
        <AppShell.icon name={:chevron_right} size={12} class="disclosure-chevron" />
        <%= gettext("Benchmark…") %>
        <span
          :if={@benchmarks != []}
          class="benchmark-picker__active"
          data-role="benchmark-active"
        >
          <span
            :for={{benchmark, index} <- Enum.with_index(@benchmarks, 1)}
            class="benchmark-chip"
            data-role="benchmark-chip"
          >
            <span
              class={["chart-legend__swatch", "chart-benchmark-#{index}"]}
              aria-hidden="true"
            >
            </span>
            <%= benchmark_name(benchmark) %>
          </span>
        </span>
      </summary>
      <form
        method="get"
        action={@action}
        class="period-disclosure__body benchmark-form"
        data-role="benchmark-form"
      >
        <%!-- The empty entry marks an explicit choice, so a form
             submitted with nothing ticked clears the selection. --%>
        <input type="hidden" name="benchmark[]" value="" />
        <%!-- The closing act (#1416): the chosen securities in the
             address's order, so „Anwenden“ keeps it for the boxes
             still ticked (`PortfolixirWeb.BenchmarkScope`). --%>
        <input
          type="hidden"
          name="benchmark_order"
          value={benchmark_order(@benchmarks)}
        />
        <%!-- #1416 (B2; board 02, Q1 A): two labelled groups,
             „Benchmarks“ then „Im Bestand“, each label in one
             column and its options from one edge; „Weitere“
             only while the address chose a security neither
             offers (`PortfolixirWeb.BenchmarkChoices`). --%>
        <div :if={@groups != []} class="bm-groups" data-role="benchmark-groups">
          <%= for group <- @groups do %>
            <span class="bm-groups__label" id={"#{@group_id}#{group.key}"}>
              <%= group.label %>
            </span>
            <span
              class="bm-groups__options"
              role="group"
              aria-labelledby={"#{@group_id}#{group.key}"}
              data-group={group.key}
            >
              <label :for={option <- group.securities} class="benchmark-form__option">
                <input
                  type="checkbox"
                  name="benchmark[]"
                  value={"security:#{option.id}"}
                  checked={benchmark_selected?(@benchmarks, option)}
                />
                <%= BenchmarkChoices.label(group, option) %>
              </label>
            </span>
          <% end %>
        </div>
        <span :if={@groups == []} class="hint" data-role="benchmark-none">
          <%= gettext("No benchmark securities yet — mark one on the Securities page.") %>
        </span>
        <label class="benchmark-form__rate" for={@rate_id}>
          <%= gettext("Fixed rate % p.a.") %>
        </label>
        <input
          type="number"
          id={@rate_id}
          name="benchmark_rate"
          step="0.01"
          min="-99.99"
          max="1000"
          value={active_rate_percent(@benchmarks)}
        />
        <button type="submit"><%= gettext("Apply") %></button>
        <span class="hint">
          <%= gettext("Up to two benchmarks — the first two ticked apply.") %>
        </span>
      </form>
    </details>
    """
  end

  attr(:performance, :map, required: true)
  attr(:period_label, :string, required: true)

  @doc "The period's badge: the TTWROR beside the result in money."
  def badge(assigns) do
    ~H"""
    <p
      class={["perf-badge", perf_sign_class(@performance.ttwror)]}
      data-role="period-badge"
    >
      <strong><%= signed_percent(@performance.ttwror) %>%</strong>
      <span class="perf-badge-sep">·</span>
      <%!-- The money figure's sign is its own: a deposit before a
           fall gives a positive TTWROR and a money loss, and the
           loss must read red, as the contribution table's sum of
           the same figure does (DESIGN.md → Colors). --%>
      <span
        class={money_sign_class(result(@performance))}
        data-role="period-badge-money"
      ><%= signed_money(result(@performance)) %> <%= @performance.base_currency %></span>
      <span class="perf-badge-period">(<%= @period_label %>)</span>
    </p>
    """
  end

  # The privacy mode's 100 % of the value series, as the shared chart takes
  # it: the window's first value, or, when that is not above zero (a buy
  # booked before its money), the first value that is. `{date, value,
  # first?}`, or `:none` when no day's value is above zero and the axis
  # carries no label (the S6 lens of the Sprint 28 closing act; the stacked
  # chart's index, #1433).
  defp value_base(series) do
    series
    |> Enum.with_index()
    |> Enum.find_value(:none, fn {point, i} ->
      if Decimal.gt?(point.value, 0), do: {point.date, point.value, i == 0}
    end)
  end

  # Board 02 (Sprint 26 P2): the line under the value series says what its
  # percent axis is a percent of, and that it is no return.
  defp privacy_value_basis({_date, _value, true}),
    do:
      gettext(
        "In privacy mode the axis shows the value in percent of the value at the window’s start, deposits and withdrawals included; the return is TTWROR."
      )

  defp privacy_value_basis({date, _value, false}),
    do:
      gettext(
        "In privacy mode the axis shows the value in percent of the value on %{date}, the first day it is above zero, deposits and withdrawals included; the return is TTWROR.",
        date: Format.date(date)
      )

  defp privacy_value_basis(:none),
    do:
      gettext(
        "In privacy mode the axis has no labels: the value is above zero on no day of the window; the return is TTWROR."
      )

  # Board 02 (Sprint 26 P2): in the privacy mode the value series is drawn
  # in percent of the window's first value, and its name says so.
  @doc "The value series' name: its currency, or percent in the privacy mode."
  @spec value_series_label(String.t()) :: String.t()
  def value_series_label(currency) do
    if PrivacyMode.on?(),
      do: gettext("Value (%)"),
      else: gettext("Value (%{currency})", currency: currency)
  end

  # The portfolio chart renders through the shared SecurityChart component
  # (ADR-0022: one chart path, the security detail chart set the quality bar).
  # The TTWROR series passes its cumulative percentages as ready-made percent
  # values (value_mode: :percent_values) with the zero gain/loss line; the
  # value series is a plain absolute money series. Every point carries a
  # `label`, so the shared crosshair tooltip shows both series (date · % · €)
  # regardless of the displayed line (Steve UAT #336/#411); the data table
  # below stays the accessible fallback (UX-DR10).
  @doc "Wealth's performance chart and its „Daten als Tabelle“."
  def chart(assigns) do
    assigns =
      assigns
      |> assign_new(:id, fn -> "performance-figure" end)
      |> assign_new(:mode, fn -> "ttwror" end)
      |> assign_new(:overlays, fn -> [] end)
      |> assign_new(:axis_start, fn -> :window end)
      |> assign_new(:zero_axis, fn -> nil end)

    {quotes, value_mode, zero_line?, aria_label, currency_code} =
      case assigns.mode do
        "value" ->
          {chart_series(assigns.series, assigns.currency, :value, []), :absolute, false,
           gettext("Value over time"), assigns.currency}

        _ ->
          {chart_series(assigns.series, assigns.currency, :ttwror, assigns.overlays),
           :percent_values, true, overlay_aria_label(assigns.overlays), ""}
      end

    assigns =
      assign(assigns,
        quotes: quotes,
        value_mode: value_mode,
        zero_line?: zero_line?,
        aria_label: aria_label,
        currency_code: currency_code,
        # The table's benchmark columns read the full overlays (UX-DR10).
        overlay_lookups:
          Enum.map(
            assigns.overlays,
            &{&1.label, Map.new(&1.points, fn p -> {p.date, p.fraction} end)}
          )
      )

    ~H"""
    <figure id={@id} class="perf-figure" data-chart-mode={@mode}>
      <SecurityChart.chart
        quotes={@quotes}
        show_transactions?={false}
        value_mode={@value_mode}
        zero_line?={@zero_line?}
        aria_label={@aria_label}
        currency_code={@currency_code}
        overlays={Enum.map(@overlays, &%{&1 | points: downsample(&1.points)})}
        overlays_extend_range?={true}
        axis_start={if @mode == "value", do: @axis_start, else: :window}
        zero_axis={@zero_axis}
      />
      <%!-- Board 02 (Sprint 26 P2): the value in percent is no return,
           since a deposit raises it; the line says so. --%>
      <p :if={@mode == "value" and PrivacyMode.on?()} class="hint" data-role="perf-privacy-basis">
        <%= privacy_value_basis(value_base(@series)) %>
      </p>
      <%!-- ADR-0046 §2: the bought-once overlays, named — a dashed line
           without a legend is a guess. --%>
      <ul :if={@overlays != []} class="chart-legend" data-role="benchmark-legend">
        <li class="chart-legend__item">
          <span class="chart-legend__swatch chart-legend__swatch--portfolio" aria-hidden="true">
          </span>
          <%= gettext("Portfolio (TTWROR)") %>
        </li>
        <li :for={overlay <- @overlays} class="chart-legend__item">
          <span class={["chart-legend__swatch", overlay.class]} aria-hidden="true"></span>
          <%= overlay.label %> · <%= gettext("bought once") %>
        </li>
      </ul>
      <%!-- Insight-level summaries instead of a downsampled daily dump
           (#564): one row per year — per month for short periods — with
           start/end value, the slice's TTWROR and net external flows. The
           one uniform disclosure (UX-DR10), wording of record. --%>
      <details class="perf-table-disclosure">
        <summary class="disclosure-summary">
          <AppShell.icon name={:chevron_right} size={12} class="disclosure-chevron" />
          <%= gettext("Data as table") %>
        </summary>
        <p class="muted" data-role="perf-table-purpose">
          <%= gettext("Start/end value, return and flows per period — the chart, summarised.") %>
        </p>
        <div class="data-table-wrapper">
          <table class="perf-data-table" data-role="perf-summary-table">
            <caption class="sr-only"><%= gettext("Performance by period") %></caption>
            <thead>
              <tr>
                <th scope="col">
                  <%= if @summary.unit == :year, do: gettext("Year"), else: gettext("Month") %>
                </th>
                <th scope="col" class="num">
                  <%= gettext("Start value (%{currency})", currency: @currency) %>
                </th>
                <th scope="col" class="num">
                  <%= gettext("End value (%{currency})", currency: @currency) %>
                </th>
                <th scope="col" class="num"><%= gettext("TTWROR") %></th>
                <th scope="col" class="num">
                  <%= gettext("Net flows (%{currency})", currency: @currency) %>
                </th>
                <%!-- One column per drawn overlay: the benchmark's cumulative
                     return at the slice's end, as plotted (UX-DR10). --%>
                <th :for={{label, _lookup} <- @overlay_lookups} scope="col" class="num">
                  <%= label %>
                </th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- @summary.rows}>
                <td><%= row.label %></td>
                <td class="num"><%= Format.money(row.start_value) %></td>
                <td class="num"><%= Format.money(row.end_value) %></td>
                <td class="num">
                  <%= if row.ttwror, do: "#{signed_percent(row.ttwror)}%", else: "—" %>
                </td>
                <td class="num"><%= Format.money(row.net_flows) %></td>
                <td :for={{_label, lookup} <- @overlay_lookups} class="num">
                  <%= overlay_cell(lookup, row.end_date) %>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </details>
    </figure>
    """
  end

  # Maps the performance series onto the shared chart's quote shape. The
  # tooltip label always carries both series (% and €), so the hover answers
  # "how much am I up" in both units whichever line is displayed.
  defp chart_series(series, currency, mode, overlays) do
    lookups =
      Enum.map(overlays, &{&1.label, Map.new(&1.points, fn p -> {p.date, p.fraction} end)})

    base =
      case value_base(series) do
        {_date, value, _first?} -> value
        :none -> nil
      end

    Enum.map(series, fn point ->
      close =
        case mode do
          :value -> point.value
          :ttwror -> Decimal.mult(point.cumulative_ttwror, 100)
        end

      %{
        date: point.date,
        close: close,
        label:
          "#{signed_percent(point.cumulative_ttwror)}% · #{value_label(mode, point.value, base, currency)}" <>
            overlay_labels(lookups, point.date)
      }
    end)
  end

  # The tooltip's second figure: the value in its currency, or, for the
  # value series in the privacy mode, the value in percent of its base, as
  # the axis shows it ("Value +12.3%", board 02). In the TTWROR series, and
  # where no day is above zero, the value stays an amount, hidden by the
  # formatter.
  defp value_label(:value, value, %Decimal{} = base, currency) do
    if PrivacyMode.on?() do
      change = value |> Decimal.sub(base) |> Decimal.div(base)
      gettext("Value %{percent}", percent: "#{signed_percent(change)}%")
    else
      "#{Format.money(value)} #{currency}"
    end
  end

  defp value_label(_mode, value, _first, currency), do: "#{Format.money(value)} #{currency}"

  # The crosshair tooltip names each benchmark's bought-once return on the
  # hovered day, after the portfolio's own pair (ADR-0046 §4).
  defp overlay_labels(lookups, date) do
    Enum.map_join(lookups, "", fn {name, by_date} ->
      case Map.get(by_date, date) do
        %Decimal{} = fraction -> " · #{name} #{signed_percent(fraction)}%"
        nil -> ""
      end
    end)
  end

  # The selectors the BenchmarkScope plug remembered, resolved against the
  # catalog: a security the API would take (any with a stored quote, #1416)
  # or a fixed rate. Anything else — an unquoted or vanished security, a
  # malformed selector — is dropped silently, so the picker shows what is
  # actually active.
  @doc false
  def resolve_benchmarks(selectors) when is_list(selectors) do
    selectors
    |> Enum.flat_map(fn
      "security:" <> id -> resolve_benchmark_security(id)
      "rate:" <> rate -> resolve_benchmark_rate(rate)
      _other -> []
    end)
    |> Enum.take(2)
  end

  def resolve_benchmarks(_selectors), do: []

  # ADR-0058 F5 (#1416, B2): the API's one rule — any security with a
  # stored quote, flagged or not — so a held fund picked is never dropped.
  # A merged-away id is redirected to its survivor before this (§12).
  defp resolve_benchmark_security(id) do
    with {:ok, id} <- LiveParam.fetch_id(id),
         {:ok, security} <- BenchmarkSecurity.resolve(id) do
      [{:security, security}]
    else
      _unquoted_or_missing -> []
    end
  end

  @doc false
  def benchmark_groups(benchmarks),
    do: BenchmarkChoices.groups(for {:security, security} <- benchmarks, do: security)

  # The plug's one bound (E25 S4, F06), so the page resolves exactly the
  # selectors the plug would store.
  defp resolve_benchmark_rate(rate) do
    case BenchmarkScope.parse_rate(rate) do
      {:ok, rate} -> [{:rate, rate}]
      :error -> []
    end
  end

  @doc false
  def benchmark_name({:security, security}), do: security.name

  def benchmark_name({:rate, rate}),
    do: gettext("%{rate} % p.a.", rate: Format.plain_decimal(Decimal.mult(rate, 100), 2))

  @doc false
  def comparison_name(%{kind: :security, name: name}), do: name
  def comparison_name(%{kind: :rate, annual_rate: rate}), do: benchmark_name({:rate, rate})

  defp benchmark_order(benchmarks) do
    Enum.map_join(for({:security, %{id: id}} <- benchmarks, do: id), ",", &"security:#{&1}")
  end

  defp benchmark_selected?(benchmarks, option) do
    Enum.any?(benchmarks, fn
      {:security, %{id: id}} -> id == option.id
      _rate -> false
    end)
  end

  defp active_rate_percent(benchmarks) do
    Enum.find_value(benchmarks, fn
      {:rate, rate} ->
        rate |> Decimal.mult(100) |> Decimal.normalize() |> Decimal.to_string(:normal)

      _security ->
        nil
    end)
  end

  defp overlay_cell(lookup, date) do
    case Map.get(lookup, date) do
      %Decimal{} = fraction -> signed_percent(fraction) <> "%"
      nil -> "—"
    end
  end

  # The chart's accessible name carries the drawn benchmarks: the overlay
  # `<title>`s are unreachable inside `role="img"`.
  defp overlay_aria_label([]), do: gettext("Cumulative TTWROR over time")

  defp overlay_aria_label(overlays) do
    gettext("Cumulative TTWROR over time") <>
      " · " <> gettext("benchmarks: %{names}", names: Enum.map_join(overlays, ", ", & &1.label))
  end

  # The bought-once overlays for the TTWROR chart (ADR-0046 §2): each
  # benchmark's cumulative return, anchored to the portfolio's own chain at
  # the day before the comparison's covered window — when the benchmark's
  # history starts inside the period, the overlay starts where the portfolio
  # then stood instead of pretending both began at zero. The value chart
  # carries no overlay: a rebased return has no € axis.
  @doc false
  def benchmark_overlays("ttwror", comparisons, series) do
    comparisons
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {comparison, index} ->
      case anchored_returns(comparison, series) do
        [] ->
          []

        points ->
          [
            %{
              class: "chart-benchmark-#{index}",
              label: comparison_name(comparison.benchmark),
              points: points
            }
          ]
      end
    end)
  end

  def benchmark_overlays(_mode, _comparisons, _series), do: []

  defp anchored_returns(%{bought_once: %{series: []}}, _series), do: []

  defp anchored_returns(%{bought_once: %{series: points}, window: %{start_date: start}}, series) do
    anchor_day = Date.add(start, -1)

    anchor =
      case Enum.find(series, &(Date.compare(&1.date, anchor_day) == :eq)) do
        %{cumulative_ttwror: cumulative} -> Decimal.add(1, cumulative)
        nil -> Decimal.new(1)
      end

    Enum.map(points, fn point ->
      fraction = anchor |> Decimal.mult(Decimal.add(1, point.cumulative_return)) |> Decimal.sub(1)

      %{
        date: point.date,
        fraction: fraction,
        value: Decimal.to_float(Decimal.mult(fraction, 100))
      }
    end)
  end

  # Long histories produce thousands of daily points; the polyline never needs
  # more than the chart can show, so sample evenly and always keep the last.
  # Insight-level table rows for the chart's data-as-table disclosure (#564):
  # the FULL daily series (never the downsampled one) grouped into calendar
  # slices — years when the series spans more than a year, months otherwise.
  # Each row: start value (the value at the slice boundary, i.e. the previous
  # slice's last point), end value, the slice's own TTWROR chained out of the
  # cumulative series ((1+cum_end)/(1+cum_start) - 1), and the summed net
  # external flows. All Decimal; display-only derivation of stored values.
  @doc false
  def table_summary([]), do: %{unit: :month, rows: []}

  def table_summary(series) do
    first = List.first(series)
    last = List.last(series)
    unit = if Date.diff(last.date, first.date) > 366, do: :year, else: :month

    {rows, _prev} =
      series
      |> Enum.chunk_by(&slice_key(&1.date, unit))
      |> Enum.map_reduce(nil, fn chunk, prev ->
        chunk_first = List.first(chunk)
        chunk_last = List.last(chunk)
        start_value = if prev, do: prev.value, else: chunk_first.value
        start_cum = if prev, do: prev.cumulative_ttwror, else: Decimal.new(0)

        row = %{
          label: slice_label(chunk_first.date, unit),
          end_date: chunk_last.date,
          start_value: start_value,
          end_value: chunk_last.value,
          ttwror: slice_ttwror(start_cum, chunk_last.cumulative_ttwror),
          net_flows: Enum.reduce(chunk, Decimal.new(0), &Decimal.add(&1.flow, &2))
        }

        {row, chunk_last}
      end)

    %{unit: unit, rows: rows}
  end

  defp slice_key(date, :year), do: date.year
  defp slice_key(date, :month), do: {date.year, date.month}

  defp slice_label(date, :year), do: Integer.to_string(date.year)

  defp slice_label(date, :month), do: Format.month(date)

  # The slice return chained out of the cumulative series; nil (rendered as a
  # quiet dash) when the growth base is zero and no ratio exists.
  defp slice_ttwror(start_cum, end_cum) do
    base = Decimal.add(1, start_cum)

    if Decimal.compare(base, 0) == :eq do
      nil
    else
      Decimal.add(1, end_cum) |> Decimal.div(base) |> Decimal.sub(1)
    end
  end

  @doc false
  def downsample(series) when length(series) <= @chart_max_points, do: series

  def downsample(series) do
    step = series |> length() |> Kernel./(@chart_max_points) |> Float.ceil() |> trunc()
    sampled = Enum.take_every(series, step)
    last = List.last(series)

    if List.last(sampled) == last, do: sampled, else: sampled ++ [last]
  end

  # -- the dashboard's Zeile ---------------------------------------------------------

  attr(:item, :map, required: true)
  attr(:period, :string, required: true)
  attr(:card, :any, required: true, doc: "nil while the read runs, :error, or `read/2`'s answer")
  attr(:state, :map, required: true, doc: "%{mode, level} of this widget")
  attr(:action, :string, required: true, doc: "the dashboard's address, for the picker")
  attr(:scope_label, :string, default: nil)

  @doc "The section „Performance“ as a dashboard widget at „Zeile“."
  def widget(assigns) do
    card = if is_map(assigns.card), do: assigns.card

    assigns =
      assign(assigns,
        uid: assigns.item.uid,
        performance: card && card.performance,
        comparisons: (card && card.comparisons) || [],
        benchmarks: (card && card.benchmarks) || [],
        bands: card && card.bands,
        currency: card && card.performance.base_currency
      )

    ~H"""
    <Widget.frame
      id={"dashboard-performance-section" <> @uid}
      item={@item}
      title={Widgets.title("performance")}
      scope_label={@scope_label}
      full_href="/portfolio"
      full_label={gettext("Full view →")}
      full_role="performance-section-full-view"
    >
      <:info>
        <%= gettext("TTWROR — time-weighted return for the selected period (not annualized). Deposits and withdrawals are neutralised so only investment performance counts.") %>
      </:info>
      <:info>
        <%= gettext("The view's daily walk over the widget's period, as Wealth's chart reads it: GET /api/v1/performance, at a level GET /api/v1/performance/bands, the benchmarks GET /api/v1/performance/benchmark (bought once, from the period's start).") %>
      </:info>
      <:switch>
        <.series_toggle
          mode={@state.mode}
          value_label={value_series_label(@currency || "EUR")}
          item={@uid}
        />
        <div class="segmented-control" data-role="performance-level" role="group" aria-label={gettext("Level")}>
          <button
            :for={level <- levels()}
            type="button"
            class={["segmented-control__option", level == @state.level && "is-active"]}
            phx-click="performance_level"
            phx-value-level={level}
            phx-value-item={@uid}
            aria-pressed={to_string(level == @state.level)}
          ><%= level_label(level) %></button>
        </div>
      </:switch>
      <:controls>
        <.benchmark_picker
          id={"dashboard-benchmark-picker" <> @uid}
          benchmarks={@benchmarks}
          groups={benchmark_groups(@benchmarks)}
          action={@action}
        />
      </:controls>
      <:shared>
        <p :if={is_nil(@card)} class="section-skeleton" aria-busy="true" data-role="performance-section-skeleton"></p>
        <p :if={@card == :error} class="hint" data-role="performance-section-failed">
          <%= gettext("Computation failed. Reload retries.") %>
        </p>
      </:shared>
      <%= if @performance do %>
        <.badge performance={@performance} period_label={Widget.period_label(@period)} />
        <%= cond do %>
          <% @state.level == "total" -> %>
            <.chart
              id={"dashboard-performance-figure" <> @uid}
              series={downsample(@performance.series)}
              summary={table_summary(@performance.series)}
              mode={@state.mode}
              currency={@performance.base_currency}
              overlays={benchmark_overlays(@state.mode, @comparisons, @performance.series)}
            />
          <% @bands == :error -> %>
            <p class="hint" data-role="stack-failed"><%= gettext("Computation failed. Reload retries.") %></p>
          <% @state.mode == "ttwror" -> %>
            <StackedChart.lines
              result={@bands}
              colors={band_colors(@bands)}
              drill_paths={%{}}
              id_suffix={"-section" <> @uid}
            />
          <% true -> %>
            <StackedChart.figure
              result={@bands}
              colors={band_colors(@bands)}
              drill_paths={%{}}
              id_suffix={"-section" <> @uid}
            />
        <% end %>
        <p :if={@performance.start_date} class="hint" data-role="performance-basis">
          <%= Format.date(@performance.start_date) %> – <%= Format.date(@performance.end_date) %>
        </p>
      <% end %>
      <:compact>
        <%= if @performance do %>
          <.badge performance={@performance} period_label={Widget.period_label(@period)} />
          <.chart
            id={"dashboard-performance-figure-compact" <> @uid}
            series={downsample(@performance.series)}
            summary={table_summary(@performance.series)}
            mode={@state.mode}
            currency={@performance.base_currency}
            overlays={[]}
          />
        <% end %>
      </:compact>
    </Widget.frame>
    """
  end

  defp level_label("total"), do: gettext("Total")
  defp level_label("category"), do: gettext("Categories")
  defp level_label("security"), do: gettext("Securities")

  # Wealth's colours where no sunburst is read: a category's own colour,
  # else the palette at its place; a security the palette in order; cash,
  # the unassigned rest and „Other“ their own.
  defp band_colors(result) do
    result.bands
    |> Enum.with_index()
    |> Map.new(fn {band, index} -> {band.key, band_color(band, index)} end)
  end

  defp band_color(%{kind: :cash}, _index), do: CategoryColors.cash()
  defp band_color(%{kind: :unclassified}, _index), do: CategoryColors.unassigned()
  defp band_color(%{kind: :other}, _index), do: :other

  defp band_color(%{kind: :category} = band, _index),
    do: Map.get(band, :color) || CategoryColors.at(Map.get(band, :tree_index) || 0)

  defp band_color(_band, index), do: CategoryColors.at(index)

  defp signed_percent(value), do: Format.signed_percent(value)
  defp signed_money(value), do: Format.signed_decimal(value, 2)

  defp perf_sign_class(value), do: value |> Format.displayed_percent_sign() |> flat_sign_class()
  defp money_sign_class(value), do: value |> Format.displayed_sign(2) |> flat_sign_class()

  defp flat_sign_class(:positive), do: "is-positive"
  defp flat_sign_class(:negative), do: "is-negative"
  defp flat_sign_class(:zero), do: "is-flat"
  defp flat_sign_class(nil), do: nil

  defp result(performance) do
    performance.end_value
    |> Decimal.sub(performance.start_value)
    |> Decimal.sub(performance.net_external_flows)
  end
end
