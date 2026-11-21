defmodule PortfolixirWeb.Dashboard.Widgets.Performance do
  @moduledoc """
  The widget „Wertentwicklung“ `performance` (ADR-0062 §12; planning board
  `ux-design-2026-11-21-sprint31/01` ①; idea boards
  `ux-design-2026-11-21-idea-i56` 01 (the sizes), 03 and 06 (the compact
  form); Sprint 31 D4).

  Every figure is the performance family's for the widget's scope and the
  dashboard's period (`Portfolixir.Dashboards.Widgets.source_params/3`,
  then `PortfolixirWeb.Api.V1.PeriodParam.resolve/1`, as the routes read
  it): `Portfolixir.Portfolios.Performance.for_view/2`, the read
  `GET /api/v1/performance` and `GET /api/v1/views/:view_id/performance`
  answer, and at L its bands, `Portfolixir.Portfolios.Performance.Bands`'
  `for_view/2` at the level „Kategorien“, the read
  `GET /api/v1/performance/bands?level=category` answers. Both are computed
  in the first portfolio's base currency, as the value card and Wealth do.

    * **S** — the period's TTWROR at figure size, its period, and a
      sparkline of the period's daily value;
    * **M** — the TTWROR and the end value over the value line of the
      period (`PortfolixirWeb.Dashboard.Widgets.Line.chart/1`);
    * **L** — „Wertentwicklung nach Kategorien“: Wealth's stacked chart
      (`PortfolixirWeb.Portfolio.StackedChart.figure/1`), served from the
      memo when the warmup (Lane P) holds it, else read in the background;
    * **compact** (board 06) — the S form at phone type.

  „Ganze Ansicht →“ opens Wealth's chart on the same period (at L on the
  level „Kategorien“). The page loads; this module only draws, and turns
  the dashboard's period into the source's.
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Buckets
  alias Portfolixir.Clock
  alias Portfolixir.Dashboards.Widgets
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.Performance.Bands
  alias PortfolixirWeb.Api.V1.PeriodParam
  alias PortfolixirWeb.Dashboard.Widget
  alias PortfolixirWeb.Dashboard.Widgets.Line
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.Portfolio.CategoryColors
  alias PortfolixirWeb.Portfolio.StackedChart

  # -- the reads ----------------------------------------------------------------

  @doc """
  The source's period for the dashboard period `period` on `today`: the
  term the routes resolve from the same query parameters, or `:error` for
  a period the kind does not answer.
  """
  @spec period_term(String.t(), Date.t()) :: {:ok, term()} | :error
  def period_term(period, today \\ Clock.today()) do
    with {:ok, params} <- Widgets.source_params("performance", period, today),
         {:ok, term} <- PeriodParam.resolve(params) do
      {:ok, term}
    else
      _refused -> :error
    end
  end

  @doc """
  The widget's read, in the page's background task: the performance of
  the scope `scope_id` (nil for Everything) over `period` in
  `base_currency`, with its daily series; a view that vanished reads
  Everything, as the value card does. `:error` when the read refuses.
  """
  @spec read(integer() | nil, String.t(), String.t()) :: map() | :error
  def read(scope_id, period, base_currency) do
    view = scope_id && Buckets.get_view(scope_id)

    with {:ok, term} <- period_term(period),
         {:ok, result} <-
           Performance.for_view(view && view.id, period: term, base_currency: base_currency) do
      %{result: result, view_name: view && view.name}
    else
      {:error, :view_not_found} -> read(nil, period, base_currency)
      _refused -> :error
    end
  end

  @doc """
  The L size's bands from the memo, in the page's own process (I34 step
  2): `{:ok, result}` when the warmup or an earlier read holds them, else
  `:miss`, and the page reads them in the background (`read_bands/3`).
  """
  @spec cached_bands(integer() | nil, String.t(), String.t()) :: {:ok, map()} | :miss
  def cached_bands(scope_id, period, base_currency) do
    case period_term(period) do
      {:ok, term} -> Bands.cached_for_view(scope_id, bands_opts(term, base_currency))
      :error -> :miss
    end
  end

  @doc "The L size's bands, read: `{:ok, result}` or `:error`."
  @spec read_bands(integer() | nil, String.t(), String.t()) :: {:ok, map()} | :error
  def read_bands(scope_id, period, base_currency) do
    with {:ok, term} <- period_term(period),
         {:ok, result} <- Bands.for_view(scope_id, bands_opts(term, base_currency)) do
      {:ok, result}
    else
      {:error, :view_not_found} -> read_bands(nil, period, base_currency)
      _refused -> :error
    end
  end

  # What Wealth sends for „Kategorien €“ and the warmup warms: the level
  # alone, no sort, scale, tree or filter.
  defp bands_opts(term, base_currency),
    do: [period: term, base_currency: base_currency, level: :category]

  # -- the widget ---------------------------------------------------------------

  attr(:item, :map, required: true)
  attr(:period, :string, required: true)
  attr(:card, :any, required: true, doc: "nil while the read runs, :error, or `read/3`'s answer")
  attr(:bands, :any, default: nil, doc: "at L: nil while read, :error, or the bands")
  attr(:scope_label, :string, default: nil)

  @doc "The widget „Wertentwicklung“ at its size, with its compact form."
  def widget(assigns) do
    assigns =
      assigns
      |> assign(:uid, assigns.item.uid)
      |> assign(:result, if(is_map(assigns.card), do: assigns.card.result))
      |> assign(:label, Widget.period_label(assigns.period))

    ~H"""
    <Widget.frame
      id={"dashboard-performance" <> @uid}
      item={@item}
      title={if @item.size == "L", do: gettext("Performance by category"), else: Widgets.title("performance")}
      scope_label={@scope_label}
      full_href={wealth_href(@period, @item.size)}
      full_label={gettext("Full view →")}
      full_role="performance-full-view"
    >
      <:info>
        <%= gettext("TTWROR — time-weighted return for the selected period (not annualized). Deposits and withdrawals are neutralised so only investment performance counts.") %>
      </:info>
      <:info :if={@result}>
        <%= gettext("The daily value of the scope's accounts from %{from} to %{to}, in %{currency}, as Wealth's chart reads it.",
          from: Format.date(@result.start_date),
          to: Format.date(@result.end_date),
          currency: @result.base_currency
        ) %>
      </:info>
      <:info :if={@item.size == "L"}>
        <%= gettext("The bands are the categories of the steering tree on each day; the method is behind the chart's own ⓘ.") %>
      </:info>
      <:shared>
        <p :if={is_nil(@card) and @item.size != "L"} class="section-skeleton" aria-busy="true" data-role="performance-skeleton"></p>
        <p :if={@card == :error} class="hint" data-role="performance-failed">
          <%= gettext("Computation failed. Reload retries.") %>
        </p>
      </:shared>
      <%= if @item.size == "L" do %>
        <p :if={@result} class="hint" data-role="performance-stack-line">
          <%= gettext("Value · level Categories") %> ·
          <span class={sign_class(@result.ttwror)} data-role="performance-ttwror"><%= percent(@result.ttwror) %></span>
          <%= gettext("TTWROR in %{period}", period: @label) %>
        </p>
        <.stack bands={@bands} uid={@uid} />
      <% else %>
        <.headline :if={@result} result={@result} label={@label} end_value={@item.size == "M"} />
        <Line.sparkline
          :if={@result && @item.size == "S"}
          values={Enum.map(@result.series, & &1.value)}
          role="performance-spark"
        />
        <Line.chart
          :if={@result && @item.size == "M"}
          id={"performance-line" <> @uid}
          points={@result.series}
          currency={@result.base_currency}
        />
      <% end %>
      <:compact>
        <div :if={@result} class="widget-figure" data-compact-role="performance">
          <strong class={["widget-figure__value num", sign_class(@result.ttwror)]}><%= percent(@result.ttwror) %></strong>
          <small class="widget-figure__sub"><%= gettext("TTWROR · %{period}", period: @label) %></small>
          <Line.sparkline values={Enum.map(@result.series, & &1.value)} />
        </div>
      </:compact>
    </Widget.frame>
    """
  end

  attr(:result, :map, required: true)
  attr(:label, :string, required: true)
  attr(:end_value, :boolean, default: false)

  defp headline(assigns) do
    ~H"""
    <div class="widget-figure" data-role="performance-figure">
      <strong class={["widget-figure__value num", sign_class(@result.ttwror)]} data-role="performance-ttwror"><%= percent(@result.ttwror) %></strong>
      <small class="widget-figure__sub">
        <%= gettext("TTWROR · %{period}", period: @label) %>
        <span :if={@end_value} data-role="performance-end-value">
          · <%= gettext("value on %{date}", date: Format.date(@result.end_date)) %>
          <span class="num"><%= Format.money(@result.end_value) %></span> <%= @result.base_currency %>
        </span>
      </small>
    </div>
    """
  end

  attr(:bands, :any, required: true)
  attr(:uid, :string, required: true)

  defp stack(%{bands: nil} = assigns) do
    ~H"""
    <div class="section-skeleton" data-role="stack-skeleton" role="status" aria-busy="true">
      <span class="recomputing-cue">
        <span class="spinner"></span> <%= gettext("computing") %>
      </span>
    </div>
    """
  end

  defp stack(%{bands: :error} = assigns) do
    ~H"""
    <p class="hint" data-role="stack-failed"><%= gettext("Computation failed. Reload retries.") %></p>
    """
  end

  defp stack(assigns) do
    assigns = assign(assigns, :colors, band_colors(assigns.bands))

    ~H"""
    <StackedChart.figure result={@bands} colors={@colors} drill_paths={%{}} id_suffix={"-widget" <> @uid} />
    """
  end

  # Wealth's colours for the level „Kategorien“ without a filter: a
  # category's own colour, else the palette at its place in the tree; cash
  # and the unassigned rest their own (`PortfolixirWeb.Portfolio.CategoryColors`).
  defp band_colors(result) do
    Map.new(result.bands, fn band -> {band.key, band_color(band)} end)
  end

  defp band_color(%{kind: :cash}), do: CategoryColors.cash()
  defp band_color(%{kind: :unclassified}), do: CategoryColors.unassigned()
  defp band_color(%{kind: :other}), do: :other

  defp band_color(%{kind: :category} = band),
    do: Map.get(band, :color) || CategoryColors.at(Map.get(band, :tree_index) || 0)

  defp band_color(_band), do: nil

  @doc """
  Wealth's chart on the dashboard's period, its address as Wealth writes
  it: the level first, then the period's pairs, one year (Wealth's
  default) naming none.
  """
  @spec wealth_href(String.t(), String.t()) :: String.t()
  def wealth_href(period, size) do
    level = if size == "L", do: [{"level", "category"}], else: []

    period_pairs =
      case Widgets.source_params("performance", period, Clock.today()) do
        {:ok, %{"period" => "1y"}} -> []
        {:ok, %{"period" => token}} -> [{"period", token}]
        {:ok, %{"from" => from, "to" => to}} -> [{"from", from}, {"to", to}]
        _none -> []
      end

    case level ++ period_pairs do
      [] -> "/portfolio"
      pairs -> "/portfolio?" <> URI.encode_query(pairs)
    end
  end

  defp percent(%Decimal{} = value), do: Format.signed_percent(value) <> "%"
  defp percent(_none), do: "—"

  defp sign_class(value) do
    case Format.displayed_percent_sign(value) do
      :positive -> "is-positive"
      :negative -> "is-negative"
      :zero -> "is-flat"
      nil -> nil
    end
  end
end
