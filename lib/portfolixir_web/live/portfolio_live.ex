defmodule PortfolixirWeb.PortfolioLive do
  @moduledoc """
  Portfolio overview: live value and cash quote, TTWROR over selectable
  periods, the value-weighted allocation donut with SOLL/IST drift, and a
  set-balance form for cash snapshots (ADR-0009/0010). All figures come from
  the same derived reads the API exposes.
  """

  use PortfolixirWeb, :live_view

  alias Portfolixir.Classifications
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Allocation
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.Valuation
  alias PortfolixirWeb.AppShell

  @donut_radius 48
  @donut_circumference 2 * :math.pi() * @donut_radius
  @unassigned_color "#9ca3af"
  @fallback_color "#6b7280"

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
          |> reload_valuation()
          |> reload_performance()
          |> reload_allocation()

        {:ok, socket}
    end
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
            <strong><%= money(@valuation.total_with_cash) %> <%= @valuation.base_currency %></strong>
          </article>
          <article id="kpi-securities" class="stat">
            <span><%= gettext("Securities") %></span>
            <strong><%= money(@valuation.total_value) %> <%= @valuation.base_currency %></strong>
          </article>
          <article id="kpi-cash" class="stat">
            <span><%= gettext("Cash") %> · <%= gettext("cash quote") %></span>
            <strong>
              <%= money(@valuation.total_cash) %> <%= @valuation.base_currency %>
              · <%= percent(@valuation.cash_quote) %>%
            </strong>
          </article>
          <article id="kpi-ttwror" class="stat">
            <span><%= gettext("TTWROR") %> (<%= period_label(@period) %>)</span>
            <strong><%= percent(@performance.ttwror) %>%</strong>
          </article>
        </section>

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
          <.performance_chart series={@performance.series} />
          <p class="hint">
            <%= gettext("True time-weighted return; deposits and withdrawals are neutralised.") %>
            <%= if @performance.start_date do %>
              <%= @performance.start_date %> – <%= @performance.end_date %>
            <% end %>
          </p>
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
                  <td><%= money(row.market_value) %></td>
                  <td><%= percent(row.actual_weight) %>%</td>
                  <td><%= percent(row.target_weight) %>%</td>
                  <td><%= money(row.drift_value) %> <%= @valuation.base_currency %></td>
                </tr>
              <% end %>
              <%= if @allocation.unassigned do %>
                <tr class="is-muted">
                  <td><%= gettext("Unassigned") %></td>
                  <td><%= money(@allocation.unassigned.market_value) %></td>
                  <td><%= percent(@allocation.unassigned.actual_weight) %>%</td>
                  <td>—</td>
                  <td>—</td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </section>

        <section id="portfolio-cash" class="workspace-section">
          <h2><%= gettext("Cash accounts") %></h2>
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
                  <td><%= money(cash.balance) %> <%= cash.currency %></td>
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
        </section>
      </div>
    </AppShell.shell>
    """
  end

  # -- components -------------------------------------------------------------

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
    if period in Performance.periods() do
      {:noreply, socket |> assign(:period, period) |> reload_performance()}
    else
      {:noreply, socket}
    end
  end

  def handle_event("select_classification", %{"classification_id" => id}, socket) do
    case coerce_id(id) do
      {:ok, classification_id} ->
        {:noreply, socket |> assign(:classification_id, classification_id) |> reload_allocation()}

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
       |> reload_valuation()
       |> reload_performance()
       |> reload_allocation()}
    else
      {:error, changeset} ->
        {:noreply, assign(socket, error: changeset_error(changeset), success: nil)}

      _other ->
        {:noreply, assign(socket, error: gettext("Account not found"), success: nil)}
    end
  end

  # -- data loading -----------------------------------------------------------

  defp reload_valuation(socket) do
    assign(socket, :valuation, Valuation.for_portfolio(socket.assigns.portfolio.id))
  end

  defp reload_performance(socket) do
    {:ok, performance} =
      Performance.for_portfolio(socket.assigns.portfolio.id, period: socket.assigns.period)

    assign(socket, :performance, performance)
  end

  defp reload_allocation(socket) do
    {:ok, allocation} =
      Allocation.for_portfolio(
        socket.assigns.portfolio.id,
        socket.assigns.classification_id
      )

    assign(socket, :allocation, allocation)
  end

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
      percent: percent(row.weight),
      length: length,
      offset: Float.round(offset, 2)
    }

    {segment, offset + length}
  end

  # -- performance chart geometry ----------------------------------------------

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

  # -- formatting ---------------------------------------------------------------

  defp money(decimal) do
    decimal |> Decimal.round(2) |> Decimal.to_string(:normal)
  end

  defp percent(decimal) do
    decimal |> Decimal.mult(100) |> Decimal.round(1) |> Decimal.to_string(:normal)
  end

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
