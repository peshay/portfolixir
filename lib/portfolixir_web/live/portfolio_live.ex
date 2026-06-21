defmodule PortfolixirWeb.PortfolioLive do
  @moduledoc """
  Portfolio overview: live value and cash quote, TTWROR and money-weighted
  IRR over selectable periods, the value-weighted allocation donut with
  SOLL/IST drift, and a
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
  alias Portfolixir.Fx.RateSync
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Allocation
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.Targets
  alias Portfolixir.Portfolios.Valuation
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Format
  import PortfolixirWeb.ViewSwitcher

  @unassigned_color "#9ca3af"
  @fallback_color "#6b7280"
  # Neutral cash colour, distinct from the category palette and the grey
  # unassigned/excluded shades, for the cash segment in the basis (issue #335).
  @cash_color "#0ea5e9"
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
          |> assign(:selected_segment, nil)
          |> assign_planned_view_ids()
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
    view_id = socket.assigns[:active_view_id]

    start_async(socket, :overview, fn ->
      valuation = Valuation.for_portfolio(portfolio_id, view: view_id)
      {:ok, allocation} = Allocation.for_portfolio(portfolio_id, classification_id, view: view_id)
      {valuation, allocation}
    end)
  end

  defp load_allocation(socket) do
    portfolio_id = socket.assigns.portfolio.id
    classification_id = socket.assigns.classification_id
    view_id = socket.assigns[:active_view_id]

    start_async(socket, :allocation, fn ->
      {:ok, allocation} = Allocation.for_portfolio(portfolio_id, classification_id, view: view_id)
      allocation
    end)
  end

  defp load_performance(socket) do
    portfolio_id = socket.assigns.portfolio.id
    view_id = socket.assigns[:active_view_id]

    start_async(socket, :performance, fn ->
      Performance.analysis(portfolio_id, view: view_id)
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
    {:noreply, assign(socket, error: gettext("Couldn't load the portfolio figures."))}
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
          <AppShell.status_toast kind={:error} message={@error} />
        <% end %>
        <%= if @success do %>
          <AppShell.status_toast kind={:success} message={@success} />
        <% end %>

        <.view_switcher
          current_path={@current_path}
          views={@views}
          active_view={@active_view}
          planned_view_ids={@planned_view_ids}
        />

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
          <article id="kpi-cash" class="stat" role="group" aria-describedby="tip-cash-quote">
            <span><%= gettext("Cash") %> · <%= gettext("cash quote") %></span>
            <strong :if={@valuation}>
              <%= Format.money(@valuation.total_cash) %> <%= @valuation.base_currency %>
              · <%= Format.percent(@valuation.cash_quote) %>%
            </strong>
            <strong :if={is_nil(@valuation)}>…</strong>
            <details class="metric-tooltip">
              <summary aria-label={gettext("Cash quote info")}>ⓘ</summary>
              <p id="tip-cash-quote" role="tooltip">
                <%= gettext("Cash quote: deployable cash ÷ (securities value + deployable cash). Reserve and credit-line accounts are excluded.") %>
              </p>
            </details>
          </article>
          <article id="kpi-ttwror" class="stat" role="group" aria-describedby="tip-ttwror">
            <span><%= gettext("TTWROR") %> (<%= period_label(@period) %>)</span>
            <strong :if={@performance}><%= Format.percent(@performance.ttwror) %>%</strong>
            <strong :if={is_nil(@performance)}>…</strong>
            <details class="metric-tooltip">
              <summary aria-label={gettext("TTWROR info")}>ⓘ</summary>
              <p id="tip-ttwror" role="tooltip">
                <%= gettext("TTWROR — time-weighted return for the selected period (not annualized). Deposits and withdrawals are neutralised so only investment performance counts.") %>
              </p>
            </details>
          </article>
          <article id="kpi-irr" class="stat" role="group" aria-describedby="tip-irr">
            <span><%= gettext("IRR") %> (<%= period_label(@period) %>)</span>
            <strong :if={@performance && @performance.irr}>
              <%= Format.percent(@performance.irr) %>%
            </strong>
            <strong :if={@performance && is_nil(@performance.irr)}>—</strong>
            <strong :if={is_nil(@performance)}>…</strong>
            <details class="metric-tooltip">
              <summary aria-label={gettext("IRR info")}>ⓘ</summary>
              <p id="tip-irr" role="tooltip">
                <%= gettext("IRR — money-weighted return, annualized. Discounts the timing and size of cashflows over the period.") %>
              </p>
            </details>
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
            <div
              class="section-skeleton"
              data-role="performance-skeleton"
              role="status"
              aria-label={gettext("Calculating…")}
            >
            </div>
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
            <%!-- The SOLL side follows the active view's plan (ADR-0020). With a
                 plan the Σ-vs-100% header shows; without one the allocation is
                 IST-only and a hint deep-links into the per-view plan editor. --%>
            <%= if @allocation.has_plan do %>
              <p
                class={[
                  "hint",
                  "target-sum",
                  target_mismatch?(@allocation.top_level_target_sum, 1) && "is-target-mismatch"
                ]}
                data-role="target-sum-top-level"
              >
                <%= gettext("Σ target top level:") %>
                <%= Format.percent(@allocation.top_level_target_sum) %>%
              </p>
            <% else %>
              <p class="hint no-plan-hint" data-role="no-plan-hint" role="status">
                <%= gettext("No target plan for this view — showing actual allocation only.") %>
                <.link navigate={plan_editor_path(@classification_id, @active_view_id)}>
                  <%= gettext("Create a plan for this view") %>
                </.link>
              </p>
            <% end %>
            <div class="donut-wrap">
              <div class="sunburst-pane">
                <.allocation_sunburst segments={sunburst_segments(@allocation)} />
                <p :if={@selected_segment} class="sunburst-detail" role="status">
                  <span class="cat-swatch" style={"background:#{@selected_segment.color}"}></span>
                  <strong><%= @selected_segment.name %></strong>
                  · <%= @selected_segment.percent %>%
                  · <%= @selected_segment.value %>
                  <%= if @valuation, do: @valuation.base_currency %>
                </p>
                <p :if={is_nil(@selected_segment)} class="hint">
                  <%= gettext("Tap or hover a slice for details.") %>
                </p>
              </div>
              <ul class="donut-legend">
                <%= for segment <- legend_segments(@allocation) do %>
                  <li>
                    <span class="cat-swatch" style={"background:#{segment.color}"} aria-hidden="true">
                    </span>
                    <span class="legend-name"><%= segment.name %></span>
                    <span class="legend-value"><%= segment.percent %>%</span>
                  </li>
                <% end %>
              </ul>
            </div>

            <table class="drift-table" aria-describedby="tip-soll-ist">
              <thead>
                <tr>
                  <th><%= gettext("Category") %></th>
                  <th class="num"><%= gettext("Value") %></th>
                  <th class="num"><%= gettext("Actual") %></th>
                  <%= if @allocation.has_plan do %>
                    <th class="num"><%= gettext("Target") %></th>
                    <th class="num">
                      <%= gettext("Drift") %>
                      <details class="metric-tooltip">
                        <summary aria-label={gettext("Target/actual drift info")}>ⓘ</summary>
                        <p id="tip-soll-ist" role="tooltip">
                          <%= gettext("Target vs. actual: target weight vs. actual weight (drift). Drift is the amount needed to reach the target allocation.") %>
                        </p>
                      </details>
                    </th>
                  <% end %>
                </tr>
              </thead>
              <tbody>
                <%= for row <- @allocation.categories do %>
                  <tr class={row.depth > 0 && "is-child"}>
                    <td style={"padding-left:#{0.75 + row.depth * 1.25}rem"}>
                      <span
                        :if={row.color}
                        class="cat-swatch"
                        style={"background:#{row.color}"}
                        aria-hidden="true"
                      >
                      </span>
                      <%= row.name %>
                      <span
                        :if={@allocation.has_plan and row.child_target_sum}
                        class={["hint", "target-consistency", target_mismatch?(row.child_target_sum, row.target_weight) && "is-target-mismatch"]}
                        data-role="target-consistency-hint"
                      >
                        <%= gettext("subcategories:") %>
                        <%= Format.percent(row.child_target_sum) %>% <%= gettext("of") %>
                        <%= Format.percent(row.target_weight) %>%
                      </span>
                    </td>
                    <td class="num"><%= Format.money(row.market_value) %></td>
                    <td class="num"><%= Format.percent(row.actual_weight) %>%</td>
                    <%= if @allocation.has_plan do %>
                      <td class="num">
                        <%= if Decimal.equal?(row.target_weight, 0) do %>
                          —
                        <% else %>
                          <%= Format.percent(row.target_weight) %>%
                        <% end %>
                      </td>
                      <td class={[
                        "num",
                        Decimal.compare(row.drift_value, 0) == :lt && "is-negative"
                      ]}>
                        <%= if Decimal.equal?(row.target_weight, 0) do %>
                          —
                        <% else %>
                          <%= Format.money(row.drift_value) %>
                          <%= if @valuation, do: @valuation.base_currency %>
                        <% end %>
                      </td>
                    <% end %>
                  </tr>
                <% end %>
                <%!-- In the currency classification cash is distributed into
                     currency buckets (issue #407), so the separate Cash row
                     is suppressed. All other classifications keep it. --%>
                <%= unless @allocation.cash.distributed do %>
                  <tr id="allocation-cash" data-role="allocation-cash">
                    <td>
                      <span
                        class="cat-swatch"
                        style={"background:#{cash_color()}"}
                        aria-hidden="true"
                      >
                      </span>
                      <%= gettext("Cash") %>
                    </td>
                    <td class="num"><%= Format.money(@allocation.cash.market_value) %></td>
                    <td class="num"><%= Format.percent(@allocation.cash.actual_weight) %>%</td>
                    <%= if @allocation.has_plan do %>
                      <td class="num">
                        <%= if Decimal.equal?(@allocation.cash.target_weight, 0) do %>
                          —
                        <% else %>
                          <%= Format.percent(@allocation.cash.target_weight) %>%
                        <% end %>
                      </td>
                      <td class={[
                        "num",
                        Decimal.compare(@allocation.cash.drift_value, 0) == :lt && "is-negative"
                      ]}>
                        <%= if Decimal.equal?(@allocation.cash.target_weight, 0) do %>
                          —
                        <% else %>
                          <%= Format.money(@allocation.cash.drift_value) %>
                          <%= if @valuation, do: @valuation.base_currency %>
                        <% end %>
                      </td>
                    <% end %>
                  </tr>
                <% end %>
                <%= if @allocation.unassigned do %>
                  <tr class="is-muted">
                    <td><%= gettext("Unassigned") %></td>
                    <td class="num"><%= Format.money(@allocation.unassigned.market_value) %></td>
                    <td class="num">
                      <%= Format.percent(@allocation.unassigned.actual_weight) %>%
                    </td>
                    <%= if @allocation.has_plan do %>
                      <td class="num">—</td>
                      <td class="num">—</td>
                    <% end %>
                  </tr>
                <% end %>
              </tbody>
            </table>
          <% else %>
            <div
              class="section-skeleton section-skeleton--allocation"
              data-role="allocation-skeleton"
              role="status"
              aria-label={gettext("Calculating…")}
            >
            </div>
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
                  <tr class={if cash.deployable, do: nil, else: "is-muted"}>
                    <td>
                      <%= cash.name %>
                      <%= if not cash.deployable do %>
                        <span class="hint"><%= liquidity_role_hint(cash.liquidity_role) %></span>
                      <% end %>
                    </td>
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
              <button type="submit" phx-disable-with={gettext("Updating…")}>
                <%= gettext("Set balance") %>
              </button>
            </form>
            <p class="hint">
              <%= gettext("State the balance your bank shows; only later bookings adjust it.") %>
            </p>

            <div class="cash-actions">
              <button type="button" phx-click="sync_rates" phx-disable-with={gettext("Syncing…")}>
                <%= gettext("Sync exchange rates") %>
              </button>
              <p class="hint">
                <%= gettext("Fetch the latest exchange rates so foreign-currency cash is valued in the totals.") %>
              </p>
            </div>
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
  # valued at a stale trade price, positions with no price at all, bookings
  # whose dates are implausible (import typos like 0217-12-05), and cash
  # accounts excluded because no FX rate to the base currency exists.
  defp data_quality(assigns) do
    assigns =
      assigns
      |> assign(:unpriced, unpriced_names(assigns.valuation))
      |> assign(:trade_priced, trade_priced_count(assigns.valuation))
      |> assign(:suspect_dates, suspect_dates(assigns.analysis))
      |> assign(:unvalued_cash, unvalued_cash(assigns.valuation))

    ~H"""
    <section
      :if={@unpriced != [] or @trade_priced > 0 or @suspect_dates != [] or @unvalued_cash != []}
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
        <li :if={@unvalued_cash != []}>
          <%= gettext(
            "%{count} cash account(s) are not counted in the totals because there is no exchange rate to %{base}: %{names}. Sync exchange rates to include them.",
            count: length(@unvalued_cash),
            base: @valuation.base_currency,
            names: Enum.map_join(@unvalued_cash, ", ", &"#{&1.name} (#{&1.currency})")
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

  # Concentric rings of annular-sector paths: the innermost ring is the
  # top-level categories, each further ring breaks one level down, the
  # outermost ring shows the individual positions (Portfolio Performance's
  # sunburst). Like PP the slices carry no in-chart text. Each slice exposes
  # data-label/data-value/data-percent that the SunburstTooltip JS hook reads
  # to show an instant custom tooltip on hover (the native <title> stays as a
  # no-JS fallback). Slices are also tappable — `select_segment` echoes the
  # slice below the chart, which is the mobile substitute for hover.
  defp allocation_sunburst(assigns) do
    ~H"""
    <svg
      id="allocation-sunburst"
      class="donut sunburst"
      viewBox="0 0 140 140"
      role="img"
      aria-label={gettext("Allocation")}
      phx-hook="SunburstTooltip"
    >
      <circle cx="70" cy="70" r="20" class="donut-center" />
      <%= for segment <- @segments do %>
        <path
          d={segment.path}
          fill={segment.color}
          fill-opacity={segment.opacity}
          class="sunburst-seg"
          data-label={segment.name}
          data-percent={segment.percent}
          data-value={segment.value}
          phx-click="select_segment"
          phx-value-name={segment.name}
          phx-value-percent={segment.percent}
          phx-value-value={segment.value}
          phx-value-color={segment.color}
        >
          <title><%= segment.name %> · <%= segment.percent %>%</title>
        </path>
      <% end %>
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
        {:noreply,
         socket
         |> assign(:classification_id, classification_id)
         |> assign(:selected_segment, nil)
         |> assign_planned_view_ids()
         |> load_allocation()}

      :error ->
        {:noreply, socket}
    end
  end

  # The mobile substitute for hover: tapping a slice echoes it below the chart.
  # Values are display strings straight from our own render; HEEx escapes them.
  def handle_event("select_segment", params, socket) do
    segment = %{
      name: to_string(params["name"] || ""),
      percent: to_string(params["percent"] || ""),
      value: to_string(params["value"] || ""),
      color: safe_color(params["color"])
    }

    {:noreply, assign(socket, :selected_segment, segment)}
  end

  def handle_event("set_balance", %{"balance" => params}, socket) do
    with {:ok, account_id} <- coerce_id(params["cash_account_id"]),
         %{portfolio_id: pid} = account <- Portfolios.get_cash_account(account_id),
         true <- pid == socket.assigns.portfolio.id,
         {:ok, _tx} <- Ledger.set_cash_balance(account, params) do
      {:noreply,
       socket
       # No success toast on balance update: the submit button's busy state
       # (phx-disable-with) plus the figures refreshing in place are
       # confirmation enough. (Same "quiet feedback" theme as PR #442.)
       |> assign(success: nil, error: nil)
       |> load_overview()
       |> load_performance()}
    else
      {:error, changeset} ->
        {:noreply, assign(socket, error: changeset_error(changeset), success: nil)}

      _other ->
        {:noreply, assign(socket, error: gettext("Account not found"), success: nil)}
    end
  end

  def handle_event("sync_rates", _params, socket) do
    case RateSync.sync() do
      {:ok, %{upserted: count}} ->
        {:noreply,
         socket
         |> assign(success: rates_synced_message(count), error: nil)
         |> load_overview()
         |> load_performance()}

      {:error, _reason} ->
        {:noreply, assign(socket, error: rate_sync_error_message(), success: nil)}
    end
  end

  def handle_event("dismiss_toast", _params, socket) do
    {:noreply, assign(socket, error: nil, success: nil)}
  end

  # On-demand exchange-rate sync (issue #432): the rate provider only refreshes
  # on a 12 h timer, so a foreign-currency cash account stays unvalued until a
  # rate arrives. This lets the user pull rates now and re-value the figures.
  defp rates_synced_message(count) do
    gettext("Exchange rates synced (%{count} updated). Recalculating figures…", count: count)
  end

  defp rate_sync_error_message do
    gettext(
      "Couldn't reach the exchange-rate provider. Please check the connection and try again."
    )
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

  # Returns cash balance entries (name + currency) whose FX rate to the
  # portfolio base currency is missing — they are excluded from the totals.
  defp unvalued_cash(nil), do: []

  defp unvalued_cash(valuation) do
    Enum.filter(valuation.cash_balances, &(not &1.valued))
  end

  # Which views (and Gesamt, marked by `nil`) carry a SOLL plan for the active
  # classification, for the subtle plan marker on the switcher chips (#468). A
  # view "has a plan" when it carries a category plan OR a cash target — the same
  # definition the allocation engine uses for `has_plan`, so the marker and the
  # portfolio table never disagree. Computed over the few views in memory; cheap.
  defp assign_planned_view_ids(%{assigns: %{portfolio: nil}} = socket) do
    assign(socket, :planned_view_ids, [])
  end

  defp assign_planned_view_ids(socket) do
    portfolio_id = socket.assigns.portfolio.id
    classification_id = socket.assigns.classification_id
    candidate_ids = [nil | Enum.map(socket.assigns.views, & &1.id)]

    planned =
      Enum.filter(candidate_ids, fn view_id ->
        Targets.plan_exists?(portfolio_id, classification_id, view: view_id) or
          not is_nil(Targets.get_cash_target(portfolio_id, view: view_id))
      end)

    assign(socket, :planned_view_ids, planned)
  end

  # Prefer the first custom tree (the user's own strategy); otherwise fall back
  # to the built-in asset-class tree, which always exists after seeding.
  defp default_classification_id(classifications) do
    custom = Enum.find(classifications, &(not &1.built_in))
    asset_class = Enum.find(classifications, &(&1.key == "asset_class"))
    (custom || asset_class).id
  end

  # -- sunburst geometry -------------------------------------------------------

  @sunburst_inner 22
  @sunburst_outer 66

  # One annular-sector path per node, ring radii derived from the actual tree
  # depth (categories per level, individual positions outermost) so any tree
  # fits the viewBox. Zero-size slices (a category kept only for its target)
  # render nothing.
  defp sunburst_segments(allocation) do
    nodes = sunburst_nodes(allocation)
    max_depth = nodes |> Enum.map(& &1.depth) |> Enum.max(fn -> 0 end)
    ring_width = (@sunburst_outer - @sunburst_inner) / (max_depth + 1)

    nodes
    |> Enum.reject(&(&1.fraction_end - &1.fraction_start < 0.0005))
    |> Enum.map(&sector_segment(&1, ring_width))
  end

  # Lays out each category's arc within its parent's start offset, recursing the
  # kept tree so children sit under their parent; the unassigned remainder is a
  # top-level grey node. A category's directly-held securities sit in the
  # trailing part of its span (children occupy the leading part), all on one
  # outermost ring. Offsets are kept as a fraction of the full turn so each
  # ring scales them to its own circumference.
  defp sunburst_nodes(allocation) do
    by_parent = Enum.group_by(allocation.categories, & &1.parent_id)
    roots = layout_level(Map.get(by_parent, nil, []), 0.0, 0)
    category_nodes = roots ++ layout_children(roots, by_parent)
    unassigned_node = unassigned_node(allocation.unassigned, roots)
    cash_node = cash_node(allocation.cash, roots ++ unassigned_node)

    max_depth = category_nodes |> Enum.map(& &1.depth) |> Enum.max(fn -> 0 end)
    security_depth = max_depth + 1

    securities =
      security_nodes(category_nodes, security_depth) ++
        unassigned_security_nodes(allocation.unassigned, unassigned_node, security_depth)

    category_nodes ++ unassigned_node ++ cash_node ++ securities
  end

  # The cash segment: a top-level slice in its own neutral colour for the cash
  # that counts toward the basis (issue #335), placed after the categories and
  # the unassigned remainder. Rendered only when there is counting cash and the
  # cash has not already been distributed into currency buckets (issue #407).
  defp cash_node(%{market_value: value, actual_weight: weight, distributed: false}, preceding) do
    fraction = Decimal.to_float(weight)
    last_end = preceding |> Enum.map(& &1.fraction_end) |> Enum.max(fn -> 0.0 end)

    if fraction > 0.0 do
      [
        %{
          name: gettext("Cash"),
          color: @cash_color,
          percent: Format.percent(weight),
          value: Format.money(value),
          depth: 0,
          opacity: "1.0",
          positions: [],
          fraction_start: last_end,
          fraction_end: last_end + fraction
        }
      ]
    else
      []
    end
  end

  # Cash distributed into currency buckets — no separate sunburst node (issue #407).
  defp cash_node(%{distributed: true}, _preceding), do: []

  defp cash_node(_cash, _preceding), do: []

  defp unassigned_node(nil, _roots), do: []

  defp unassigned_node(%{actual_weight: weight, market_value: value}, roots) do
    fraction = Decimal.to_float(weight)
    last_root_end = roots |> Enum.map(& &1.fraction_end) |> Enum.max(fn -> 0.0 end)

    [
      %{
        name: gettext("Unsorted"),
        color: @unassigned_color,
        percent: Format.percent(weight),
        value: Format.money(value),
        depth: 0,
        opacity: "1.0",
        positions: [],
        fraction_start: last_root_end,
        fraction_end: last_root_end + fraction
      }
    ]
  end

  defp layout_level(rows, start_fraction, depth) do
    {nodes, _} =
      Enum.map_reduce(rows, start_fraction, fn row, offset ->
        fraction = Decimal.to_float(row.actual_weight)

        node = %{
          name: row.name,
          color: row.color || @fallback_color,
          percent: Format.percent(row.actual_weight),
          value: Format.money(row.market_value),
          depth: depth,
          opacity: "1.0",
          category_id: row.category_id,
          positions: row.positions,
          fraction_start: offset,
          fraction_end: offset + fraction
        }

        {node, offset + fraction}
      end)

    nodes
  end

  defp layout_children(parent_nodes, by_parent) do
    Enum.flat_map(parent_nodes, fn parent ->
      children_rows = Map.get(by_parent, parent.category_id, [])
      child_nodes = layout_level(children_rows, parent.fraction_start, parent.depth + 1)
      child_nodes ++ layout_children(child_nodes, by_parent)
    end)
  end

  # The PP-style outermost ring: each category's direct positions, placed in
  # the trailing remainder of the category's span (its children occupy the
  # leading part), shaded by cycling opacity on the category colour.
  defp security_nodes(category_nodes, depth) do
    Enum.flat_map(category_nodes, fn node ->
      own_fraction = node.positions |> Enum.map(&Decimal.to_float(&1.weight)) |> Enum.sum()
      layout_positions(node.positions, node.fraction_end - own_fraction, node.color, depth)
    end)
  end

  defp unassigned_security_nodes(nil, _nodes, _depth), do: []

  defp unassigned_security_nodes(%{positions: positions}, [node], depth) do
    layout_positions(positions, node.fraction_start, @unassigned_color, depth)
  end

  defp layout_positions(positions, start_fraction, color, depth) do
    {nodes, _} =
      positions
      |> Enum.with_index()
      |> Enum.map_reduce(start_fraction, fn {position, index}, offset ->
        fraction = Decimal.to_float(position.weight)

        node = %{
          name: position.security_name || "?",
          color: color,
          percent: Format.percent(position.weight),
          value: Format.money(position.market_value),
          depth: depth,
          opacity: Enum.at(["1.0", "0.72", "0.5"], rem(index, 3)),
          fraction_start: offset,
          fraction_end: offset + fraction
        }

        {node, offset + fraction}
      end)

    nodes
  end

  # Radial padding between rings, so the slices read as separated bands.
  @ring_gap 0.6

  defp sector_segment(node, ring_width) do
    r_in = @sunburst_inner + node.depth * ring_width + @ring_gap
    r_out = @sunburst_inner + (node.depth + 1) * ring_width - @ring_gap

    %{
      name: node.name,
      color: node.color,
      percent: node.percent,
      value: node.value,
      opacity: node.opacity,
      path: sector_path(r_in, r_out, node.fraction_start, node.fraction_end)
    }
  end

  # Annular sector: outer arc forward, line inward, inner arc back. A slice of
  # (almost) the full turn keeps a visible notch so the arc endpoints stay
  # distinct after rounding — equal endpoints make SVG drop the arc entirely.
  defp sector_path(r_in, r_out, f0, f1) do
    f1 = min(f1, f0 + 0.9985)
    large = if f1 - f0 > 0.5, do: 1, else: 0
    {x0o, y0o} = polar(r_out, f0)
    {x1o, y1o} = polar(r_out, f1)
    {x0i, y0i} = polar(r_in, f0)
    {x1i, y1i} = polar(r_in, f1)

    "M #{x0o} #{y0o} " <>
      "A #{r2(r_out)} #{r2(r_out)} 0 #{large} 1 #{x1o} #{y1o} " <>
      "L #{x1i} #{y1i} " <>
      "A #{r2(r_in)} #{r2(r_in)} 0 #{large} 0 #{x0i} #{y0i} Z"
  end

  # Fraction of the full turn (0 = twelve o'clock, clockwise) to a point.
  defp polar(radius, fraction) do
    theta = fraction * 2 * :math.pi() - :math.pi() / 2
    {r2(70 + radius * :math.cos(theta)), r2(70 + radius * :math.sin(theta))}
  end

  defp r2(value), do: Float.round(value * 1.0, 2)

  # The legend lists the top-level categories (plus unassigned) only, so it
  # stays readable when a tree has many leaves.
  defp legend_segments(allocation) do
    roots =
      allocation.categories
      |> Enum.filter(&(&1.depth == 0 and Decimal.compare(&1.actual_weight, 0) == :gt))
      |> Enum.map(fn row ->
        %{
          name: row.name,
          color: row.color || @fallback_color,
          percent: Format.percent(row.actual_weight)
        }
      end)

    with_unassigned =
      case allocation.unassigned do
        nil ->
          roots

        %{actual_weight: weight} ->
          roots ++
            [
              %{
                name: gettext("Unsorted"),
                color: @unassigned_color,
                percent: Format.percent(weight)
              }
            ]
      end

    # Cash distributed into currency buckets (issue #407): no separate Cash
    # legend entry; the currency category slices already include the cash.
    case allocation.cash do
      %{actual_weight: weight, distributed: false} ->
        if Decimal.compare(weight, 0) == :gt do
          with_unassigned ++
            [
              %{
                name: gettext("Cash"),
                color: @cash_color,
                percent: Format.percent(weight)
              }
            ]
        else
          with_unassigned
        end

      _ ->
        with_unassigned
    end
  end

  # Advisory target-consistency check: the children sum vs. the parent target,
  # or the top-level sum vs. 100% (`1`). Exact `Decimal.equal?/2` comparison —
  # a free-form weight is only flagged when it does not match to the stored
  # precision. Display-only; it never blocks saving targets.
  defp target_mismatch?(sum, %Decimal{} = expected) do
    not Decimal.equal?(sum, expected)
  end

  defp target_mismatch?(sum, expected) when is_integer(expected) do
    not Decimal.equal?(sum, Decimal.new(expected))
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

  # The neutral cash colour, exposed for the template's cash row swatch.
  defp cash_color, do: @cash_color

  # Deep-link into the classifications SOLL editor with the view + classification
  # pre-selected (ADR-0020): the no-plan hint sends the maintainer straight to
  # the right `(view, classification)` plan rather than editing blind. `nil` =
  # the portfolio-wide Gesamt plan ("total"); a view id rides along as `soll_view`.
  defp plan_editor_path(classification_id, view_id) do
    "/classifications/#{classification_id}?soll_view=#{view_param(view_id)}"
  end

  defp view_param(nil), do: "total"
  defp view_param(id) when is_integer(id), do: Integer.to_string(id)

  # Why a non-deployable cash row is left out of the cash quote (FR6/FR7): a
  # reserve or credit line never contributes, and an overdrawn free_cash account
  # has no spendable balance.
  defp liquidity_role_hint("credit_line"), do: gettext("credit line")
  defp liquidity_role_hint("reserve"), do: gettext("reserve")
  defp liquidity_role_hint(_role), do: gettext("not in cash quote")

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

  # The colour lands in a style attribute, so only a literal hex colour from
  # our own render is accepted — anything else falls back to neutral grey.
  defp safe_color(value) when is_binary(value) do
    if value =~ ~r/^#[0-9a-fA-F]{6}$/, do: value, else: @fallback_color
  end

  defp safe_color(_value), do: @fallback_color

  defp changeset_error(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {message, _opts}} -> "#{field} #{message}" end)
    |> Enum.join(", ")
  end
end
