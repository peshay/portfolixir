defmodule PortfolixirWeb.PortfolioLive do
  @moduledoc """
  Portfolio overview: live value and cash quote, TTWROR over selectable
  periods, the value-weighted allocation donut with SOLL/IST drift, and a
  set-balance form for cash snapshots (ADR-0009/0010). All figures come from
  the same derived reads the API exposes.

  The heavy reads run as async assigns after the socket connects: the page
  paints immediately and each section fills in when its data arrives. The
  daily performance walk is computed once (`Performance.analysis/2`) and
  cached on the socket — switching periods is a pure re-chain of that series,
  so the buttons respond instantly. The chart is downsampled to a bounded
  number of points before it hits the DOM.
  """

  use PortfolixirWeb, :live_view

  alias Portfolixir.Classifications
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Allocation
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.Valuation
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Format

  @donut_radius 48
  @donut_circumference 2 * :math.pi() * @donut_radius
  @unassigned_color "#9ca3af"
  @fallback_color "#6b7280"
  @chart_max_points 400
  @unpriced_names_shown 6

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:current_path, "/portfolio")
      |> assign(:error, nil)
      |> assign(:success, nil)

    case Portfolios.first_portfolio() do
      nil ->
        {:ok, assign(socket, :portfolio, nil)}

      portfolio ->
        Classifications.ensure_builtins()
        classifications = Classifications.list_classifications()

        socket =
          socket
          |> assign(:portfolio, portfolio)
          |> assign(:classifications, classifications)
          |> assign(:period, "max")
          |> assign(:classification_id, default_classification_id(classifications))
          |> assign(:valuation, nil)
          |> assign(:allocation, nil)
          |> assign(:analysis, nil)
          |> assign(:performance, nil)
          |> start_loading()

        {:ok, socket}
    end
  end

  # The dead render ships skeletons only; the expensive reads start once the
  # socket is connected, so the page paints fast and is computed exactly once.
  defp start_loading(socket) do
    if connected?(socket) do
      socket
      |> load_overview()
      |> load_performance()
    else
      socket
    end
  end

  defp load_overview(socket) do
    portfolio_id = socket.assigns.portfolio.id
    classification_id = socket.assigns.classification_id

    start_async(socket, :overview, fn ->
      valuation = Valuation.for_portfolio(portfolio_id)
      {:ok, allocation} = Allocation.for_portfolio(portfolio_id, classification_id)
      {valuation, allocation}
    end)
  end

  defp load_allocation(socket) do
    portfolio_id = socket.assigns.portfolio.id
    classification_id = socket.assigns.classification_id

    start_async(socket, :allocation, fn ->
      {:ok, allocation} = Allocation.for_portfolio(portfolio_id, classification_id)
      allocation
    end)
  end

  defp load_performance(socket) do
    portfolio_id = socket.assigns.portfolio.id

    start_async(socket, :performance, fn ->
      Performance.analysis(portfolio_id)
    end)
  end

  @impl true
  def handle_async(:overview, {:ok, {valuation, allocation}}, socket) do
    {:noreply, assign(socket, valuation: valuation, allocation: allocation)}
  end

  def handle_async(:allocation, {:ok, allocation}, socket) do
    {:noreply, assign(socket, :allocation, allocation)}
  end

  def handle_async(:performance, {:ok, analysis}, socket) do
    {:ok, performance} = Performance.summarise(analysis, socket.assigns.period)
    {:noreply, assign(socket, analysis: analysis, performance: performance)}
  end

  def handle_async(_name, {:exit, _reason}, socket) do
    {:noreply, assign(socket, :error, gettext("Couldn't load the portfolio figures."))}
  end

  @impl true
  def render(%{portfolio: nil} = assigns) do
    ~H"""
    <AppShell.shell current_path={@current_path} page_title={gettext("Portfolio")}>
      <div class="workspace-page">
        <section class="workspace-section empty-state">
          <h2><%= gettext("Portfolio") %></h2>
          <p><%= gettext("Create one portfolio first to see value, performance and allocation.") %></p>
          <.link navigate="/portfolios" class="button"><%= gettext("Create one portfolio") %></.link>
        </section>
      </div>
    </AppShell.shell>
    """
  end

  def render(assigns) do
    ~H"""
    <AppShell.shell
      current_path={@current_path}
      page_title={@portfolio.name}
      page_subtitle={gettext("Value, performance and allocation")}
    >
      <div id="portfolio-overview" class="workspace-page portfolio-overview">
        <%= if @error do %>
          <p class="alert-error" role="alert"><%= @error %></p>
        <% end %>
        <%= if @success do %>
          <p class="alert-success" role="status"><%= @success %></p>
        <% end %>

        <section class="workspace-section grid" aria-label={gettext("Portfolio key figures")}>
          <article id="kpi-total" class="stat">
            <span><%= gettext("Total incl. cash") %></span>
            <strong :if={@valuation}>
              <%= Format.money(@valuation.total_with_cash) %> <%= @valuation.base_currency %>
            </strong>
            <strong :if={is_nil(@valuation)}>…</strong>
          </article>
          <article id="kpi-securities" class="stat">
            <span><%= gettext("Securities") %></span>
            <strong :if={@valuation}>
              <%= Format.money(@valuation.total_value) %> <%= @valuation.base_currency %>
            </strong>
            <strong :if={is_nil(@valuation)}>…</strong>
          </article>
          <article id="kpi-cash" class="stat">
            <span><%= gettext("Cash") %> · <%= gettext("cash quote") %></span>
            <strong :if={@valuation}>
              <%= Format.money(@valuation.total_cash) %> <%= @valuation.base_currency %>
              · <%= Format.percent(@valuation.cash_quote) %>%
            </strong>
            <strong :if={is_nil(@valuation)}>…</strong>
          </article>
          <article id="kpi-ttwror" class="stat">
            <span><%= gettext("TTWROR") %> (<%= period_label(@period) %>)</span>
            <strong :if={@performance}><%= Format.percent(@performance.ttwror) %>%</strong>
            <strong :if={is_nil(@performance)}>…</strong>
          </article>
        </section>

        <.data_quality valuation={@valuation} analysis={@analysis} />

        <section id="portfolio-performance" class="workspace-section">
          <header class="section-head">
            <h2><%= gettext("Performance") %></h2>
            <div class="period-buttons" role="group" aria-label={gettext("Period")}>
              <%= for period <- Performance.periods() do %>
                <button
                  type="button"
                  class={["button-mini", period == @period && "is-active"]}
                  phx-click="select_period"
                  phx-value-period={period}
                >
                  <%= period_label(period) %>
                </button>
              <% end %>
            </div>
          </header>
          <%= if @performance do %>
            <.performance_chart series={downsample(@performance.series)} />
            <p class="hint">
              <%= gettext("True time-weighted return; deposits and withdrawals are neutralised.") %>
              <%= if @performance.start_date do %>
                <%= @performance.start_date %> – <%= @performance.end_date %>
              <% end %>
            </p>
          <% else %>
            <p class="hint loading-hint" role="status"><%= gettext("Calculating…") %></p>
          <% end %>
        </section>

        <section id="portfolio-allocation" class="workspace-section">
          <header class="section-head">
            <h2><%= gettext("Allocation") %></h2>
            <form phx-change="select_classification">
              <label class="visually-hidden" for="allocation-classification">
                <%= gettext("Classification") %>
              </label>
              <select id="allocation-classification" name="classification_id">
                <%= for classification <- @classifications do %>
                  <option value={classification.id} selected={classification.id == @classification_id}>
                    <%= classification.name %>
                  </option>
                <% end %>
              </select>
            </form>
          </header>

          <%= if @allocation do %>
            <div class="donut-wrap">
              <.allocation_donut segments={donut_segments(@allocation)} />
              <ul class="donut-legend">
                <%= for segment <- donut_segments(@allocation) do %>
                  <li>
                    <span class="cat-swatch" style={"background:#{segment.color}"} aria-hidden="true">
                    </span>
                    <span class="legend-name"><%= segment.name %></span>
                    <span class="legend-value"><%= segment.percent %>%</span>
                  </li>
                <% end %>
              </ul>
            </div>

            <table class="drift-table">
              <thead>
                <tr>
                  <th><%= gettext("Category") %></th>
                  <th><%= gettext("Value") %></th>
                  <th><%= gettext("Actual") %></th>
                  <th><%= gettext("Target") %></th>
                  <th><%= gettext("Drift") %></th>
                </tr>
              </thead>
              <tbody>
                <%= for row <- @allocation.categories do %>
                  <tr>
                    <td><%= row.name %></td>
                    <td><%= Format.money(row.market_value) %></td>
                    <td><%= Format.percent(row.actual_weight) %>%</td>
                    <td><%= Format.percent(row.target_weight) %>%</td>
                    <td>
                      <%= Format.money(row.drift_value) %>
                      <%= if @valuation, do: @valuation.base_currency %>
                    </td>
                  </tr>
                <% end %>
                <%= if @allocation.unassigned do %>
                  <tr class="is-muted">
                    <td><%= gettext("Unassigned") %></td>
                    <td><%= Format.money(@allocation.unassigned.market_value) %></td>
                    <td><%= Format.percent(@allocation.unassigned.actual_weight) %>%</td>
                    <td>—</td>
                    <td>—</td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          <% else %>
            <p class="hint loading-hint" role="status"><%= gettext("Calculating…") %></p>
          <% end %>
        </section>

        <section id="portfolio-cash" class="workspace-section">
          <h2><%= gettext("Cash accounts") %></h2>
          <%= if @valuation do %>
            <table class="cash-table">
              <thead>
                <tr>
                  <th><%= gettext("Account") %></th>
                  <th><%= gettext("Balance") %></th>
                </tr>
              </thead>
              <tbody>
                <%= for cash <- @valuation.cash_balances do %>
                  <tr>
                    <td><%= cash.name %></td>
                    <td><%= Format.money(cash.balance) %> <%= cash.currency %></td>
                  </tr>
                <% end %>
              </tbody>
            </table>

            <form phx-submit="set_balance" class="inline-form balance-form">
              <label>
                <span><%= gettext("Account") %></span>
                <select name="balance[cash_account_id]">
                  <%= for cash <- @valuation.cash_balances do %>
                    <option value={cash.cash_account_id}><%= cash.name %></option>
                  <% end %>
                </select>
              </label>
              <label>
                <span><%= gettext("Date") %></span>
                <input type="date" name="balance[date]" value={Date.to_iso8601(Date.utc_today())} />
              </label>
              <label>
                <span><%= gettext("Balance") %></span>
                <input name="balance[amount]" inputmode="decimal" required placeholder="4250.00" />
              </label>
              <button type="submit"><%= gettext("Set balance") %></button>
            </form>
            <p class="hint">
              <%= gettext("State the balance your bank shows; only later bookings adjust it.") %>
            </p>
          <% else %>
            <p class="hint loading-hint" role="status"><%= gettext("Calculating…") %></p>
          <% end %>
        </section>
      </div>
    </AppShell.shell>
    """
  end

  # -- components -------------------------------------------------------------

  # Surfaces why the totals can deviate from the user's expectation: positions
  # valued at a stale trade price, positions with no price at all, and
  # bookings whose dates are implausible (import typos like 0217-12-05).
  defp data_quality(assigns) do
    assigns =
      assigns
      |> assign(:unpriced, unpriced_names(assigns.valuation))
      |> assign(:trade_priced, trade_priced_count(assigns.valuation))
      |> assign(:suspect_dates, suspect_dates(assigns.analysis))

    ~H"""
    <section
      :if={@unpriced != [] or @trade_priced > 0 or @suspect_dates != []}
      id="portfolio-data-quality"
      class="workspace-section data-quality"
    >
      <h2><%= gettext("Data quality") %></h2>
      <ul>
        <li :if={@trade_priced > 0}>
          <%= gettext(
            "%{count} held positions have no current quote and are valued at their last trade price.",
            count: @trade_priced
          ) %>
        </li>
        <li :if={@unpriced != []}>
          <%= gettext("%{count} held positions have no price at all and are missing from the totals:",
            count: length(@unpriced)
          ) %>
          <%= Enum.join(@unpriced, ", ") %>
        </li>
        <li :if={@suspect_dates != []}>
          <%= gettext(
            "Bookings dated before 1970 (%{dates}) are applied on the first plausible day — fix those dates in the source and re-import.",
            dates: Enum.map_join(@suspect_dates, ", ", &Date.to_iso8601/1)
          ) %>
        </li>
      </ul>
    </section>
    """
  end

  defp performance_chart(assigns) do
    assigns = assign(assigns, :zero_y, chart_geometry(assigns.series).zero_y)

    ~H"""
    <svg
      class="perf-chart"
      viewBox="0 0 720 180"
      preserveAspectRatio="none"
      role="img"
      aria-label={gettext("Cumulative TTWROR over time")}
    >
      <line x1="0" y1={@zero_y} x2="720" y2={@zero_y} class="perf-zeroline" />
      <polyline class="perf-line" fill="none" points={performance_points(@series)} />
    </svg>
    """
  end

  defp allocation_donut(assigns) do
    assigns = assign(assigns, circumference: @donut_circumference, radius: @donut_radius)

    ~H"""
    <svg class="donut" viewBox="0 0 120 120" role="img" aria-label={gettext("Allocation")}>
      <g transform="rotate(-90 60 60)">
        <circle cx="60" cy="60" r={@radius} class="donut-track" fill="none" />
        <%= for segment <- @segments do %>
          <circle
            cx="60"
            cy="60"
            r={@radius}
            fill="none"
            stroke={segment.color}
            stroke-width="18"
            stroke-dasharray={"#{segment.length} #{@circumference}"}
            stroke-dashoffset={-segment.offset}
          />
        <% end %>
      </g>
    </svg>
    """
  end

  # -- events -----------------------------------------------------------------

  @impl true
  def handle_event("select_period", %{"period" => period}, socket) do
    cond do
      period not in Performance.periods() ->
        {:noreply, socket}

      # The analysis is cached — re-chaining a period is pure and instant.
      socket.assigns.analysis ->
        {:ok, performance} = Performance.summarise(socket.assigns.analysis, period)
        {:noreply, assign(socket, period: period, performance: performance)}

      # Still computing; the async completion summarises the chosen period.
      true ->
        {:noreply, assign(socket, :period, period)}
    end
  end

  def handle_event("select_classification", %{"classification_id" => id}, socket) do
    case coerce_id(id) do
      {:ok, classification_id} ->
        {:noreply, socket |> assign(:classification_id, classification_id) |> load_allocation()}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("set_balance", %{"balance" => params}, socket) do
    with {:ok, account_id} <- coerce_id(params["cash_account_id"]),
         %{portfolio_id: pid} = account <- Portfolios.get_cash_account(account_id),
         true <- pid == socket.assigns.portfolio.id,
         {:ok, _tx} <- Ledger.set_cash_balance(account, params) do
      {:noreply,
       socket
       |> assign(success: gettext("Balance updated"), error: nil)
       |> assign(:analysis, nil)
       |> assign(:performance, nil)
       |> load_overview()
       |> load_performance()}
    else
      {:error, changeset} ->
        {:noreply, assign(socket, error: changeset_error(changeset), success: nil)}

      _other ->
        {:noreply, assign(socket, error: gettext("Account not found"), success: nil)}
    end
  end

  # -- data quality helpers ----------------------------------------------------

  defp unpriced_names(nil), do: []

  defp unpriced_names(valuation) do
    valuation.positions
    |> Enum.reject(& &1.valued)
    |> Enum.map(&(&1.security_name || gettext("Unsorted")))
    |> Enum.uniq()
    |> shorten_list()
  end

  defp shorten_list(names) when length(names) <= @unpriced_names_shown, do: names

  defp shorten_list(names) do
    {shown, rest} = Enum.split(names, @unpriced_names_shown)
    shown ++ ["+#{length(rest)}"]
  end

  defp trade_priced_count(nil), do: 0
  defp trade_priced_count(valuation), do: valuation.trade_priced_count

  defp suspect_dates(nil), do: []
  defp suspect_dates(analysis), do: analysis.suspect_dates

  # Prefer the first custom tree (the user's own strategy); otherwise fall back
  # to the built-in asset-class tree, which always exists after seeding.
  defp default_classification_id(classifications) do
    custom = Enum.find(classifications, &(not &1.built_in))
    asset_class = Enum.find(classifications, &(&1.key == "asset_class"))
    (custom || asset_class).id
  end

  # -- donut geometry ----------------------------------------------------------

  # Value-weighted slices: each category's share of the valued positions, plus
  # one grey slice for unassigned holdings. Zero-value rows are skipped.
  defp donut_segments(allocation) do
    rows =
      allocation.categories
      |> Enum.map(fn row ->
        %{name: row.name, color: row.color || @fallback_color, weight: row.actual_weight}
      end)
      |> append_unassigned(allocation.unassigned)
      |> Enum.reject(&(Decimal.compare(&1.weight, 0) != :gt))

    {segments, _offset} = Enum.map_reduce(rows, 0.0, &donut_segment/2)
    segments
  end

  defp append_unassigned(rows, nil), do: rows

  defp append_unassigned(rows, unassigned) do
    rows ++
      [
        %{
          name: gettext("Unsorted"),
          color: @unassigned_color,
          weight: unassigned.actual_weight
        }
      ]
  end

  defp donut_segment(row, offset) do
    fraction = Decimal.to_float(row.weight)
    length = Float.round(fraction * @donut_circumference, 2)

    segment = %{
      name: row.name,
      color: row.color,
      percent: Format.percent(row.weight),
      length: length,
      offset: Float.round(offset, 2)
    }

    {segment, offset + length}
  end

  # -- performance chart geometry ----------------------------------------------

  # Long histories produce thousands of daily points; the polyline never needs
  # more than the chart can show, so sample evenly and always keep the last.
  defp downsample(series) when length(series) <= @chart_max_points, do: series

  defp downsample(series) do
    step = series |> length() |> Kernel./(@chart_max_points) |> Float.ceil() |> trunc()
    sampled = Enum.take_every(series, step)
    last = List.last(series)

    if List.last(sampled) == last, do: sampled, else: sampled ++ [last]
  end

  defp chart_geometry([]), do: %{min: -0.01, max: 0.01, zero_y: 90.0}

  defp chart_geometry(series) do
    values = Enum.map(series, &Decimal.to_float(&1.cumulative_ttwror))
    min = Enum.min([0.0 | values])
    max = Enum.max([0.0 | values])
    {min, max} = pad_flat(min, max)
    %{min: min, max: max, zero_y: y_for(0.0, min, max)}
  end

  defp pad_flat(min, max) when max - min < 1.0e-9, do: {min - 0.01, max + 0.01}
  defp pad_flat(min, max), do: {min, max}

  defp y_for(value, min, max), do: Float.round(170 - (value - min) / (max - min) * 160, 2)

  defp performance_points([]), do: ""

  defp performance_points(series) do
    %{min: min, max: max} = chart_geometry(series)
    last = max(length(series) - 1, 1)

    series
    |> Enum.with_index()
    |> Enum.map_join(" ", fn {point, index} ->
      x = Float.round(index / last * 720, 2)
      y = y_for(Decimal.to_float(point.cumulative_ttwror), min, max)
      "#{x},#{y}"
    end)
  end

  # -- misc ---------------------------------------------------------------------

  defp period_label("ytd"), do: gettext("YTD")
  defp period_label("1y"), do: gettext("1Y")
  defp period_label("3y"), do: gettext("3Y")
  defp period_label("5y"), do: gettext("5Y")
  defp period_label("max"), do: gettext("Max")

  defp coerce_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _ -> :error
    end
  end

  defp coerce_id(_value), do: :error

  defp changeset_error(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {message, _opts}} -> "#{field} #{message}" end)
    |> Enum.join(", ")
  end
end
