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

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Classifications
  alias Portfolixir.Fx.RateSync
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Allocation
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.Targets
  alias Portfolixir.Portfolios.Valuation
  alias Portfolixir.Settings
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Components.SecurityChart
  alias PortfolixirWeb.Format
  import PortfolixirWeb.ViewSwitcher

  @unassigned_color "#9ca3af"
  @fallback_color "#6b7280"
  # Categories without a chosen colour cycle through this palette (in tree
  # order), so an unstyled tree still renders a readable sunburst/legend
  # instead of uniform grey (Steve UAT, reconsolidation).
  @category_palette [
    "#2563eb",
    "#0d9488",
    "#d97706",
    "#db2777",
    "#65a30d",
    "#7c3aed",
    "#0891b2",
    "#c2410c"
  ]
  # Neutral cash colour, distinct from the category palette and the grey
  # unassigned/excluded shades, for the cash segment in the basis (issue #335).
  @cash_color "#0ea5e9"
  @chart_max_points 400
  @unpriced_names_shown 6

  @impl true
  def mount(params, _session, socket) do
    wealth_tab = wealth_tab(params)

    socket =
      socket
      # The tab rides in current_path so the view/locale switchers (which
      # derive their hrefs from it) keep the user on the active tab — and an
      # explicit ?view= rides along too, so a tab or locale switch keeps the
      # picked view in the URL (ADR-0024).
      |> assign(:current_path, wealth_tab |> wealth_tab_path() |> keep_view_param(params))
      |> assign(:wealth_tab, wealth_tab)
      |> assign(:error, nil)
      |> assign(:success, nil)
      |> assign_migration_notice()

    # ADR-0024: the empty state keys on the bookkeeping entities (depots and
    # cash accounts), not on the internal portfolio compatibility record — a
    # record without accounts must not unlock a page with nothing to show.
    # Accounts always carry a portfolio FK, so `first_portfolio/0` is
    # guaranteed below; it stays the internal mechanism for the
    # portfolio-bound allocation/performance reads (documented ADR-0024 gap).
    case Portfolios.count_securities_accounts() + Portfolios.count_cash_accounts() do
      0 ->
        {:ok, assign(socket, :portfolio, nil)}

      _accounts ->
        portfolio = Portfolios.first_portfolio()
        # Built-in trees are seeded at startup (#529), not on this read path.
        classifications = Classifications.list_classifications()

        socket =
          socket
          |> assign(:portfolio, portfolio)
          |> assign(:classifications, classifications)
          # 1y default (UAT fix round): "max" grows unreadable as history
          # accumulates; the period buttons still offer it.
          |> assign(:period, "1y")
          |> assign(:chart_mode, "ttwror")
          |> assign(:classification_id, default_classification_id(classifications))
          |> assign(:valuation, nil)
          |> assign(:allocation, nil)
          |> assign(:analysis, nil)
          |> assign(:performance, nil)
          |> assign(:selected_segment, nil)
          |> assign(:expanded_categories, MapSet.new())
          |> assign(:allocation_mode, :tree)
          |> assign(:flat_sort, {:drift, :desc})
          |> assign(:fx_syncing, false)
          |> assign(:fx_sync_result, nil)
          |> assign(:category_parent_map, %{})
          |> assign(:category_parents_with_children, MapSet.new())
          |> assign_planned_view_ids()
          |> start_loading()

        {:ok, socket}
    end
  end

  # The Wealth area's active tab (ADR-0022): the tab bar navigates with plain
  # links, so the choice arrives as a query param on mount.
  defp wealth_tab(%{"tab" => "allocation"}), do: :allocation
  defp wealth_tab(_params), do: :holdings

  defp wealth_tab_path(:allocation), do: "/portfolio?tab=allocation"
  defp wealth_tab_path(_tab), do: "/portfolio"

  # Merges an explicit ?view= from the mount params into current_path (same
  # query-merging pattern as the switcher's own hrefs), so the tab bar and the
  # locale switcher — which derive their links from current_path — carry the
  # picked view along instead of dropping it.
  defp keep_view_param(path, %{"view" => view}) when is_binary(view) do
    uri = URI.parse(path)

    query =
      (uri.query || "")
      |> URI.decode_query()
      |> Map.put("view", view)
      |> URI.encode_query()

    URI.to_string(%{uri | query: query})
  end

  defp keep_view_param(path, _params), do: path

  # The one-time ADR-0024 migration notice: shown while the seeded views exist
  # and the maintainer has not dismissed it yet; two cheap indexed reads.
  defp assign_migration_notice(socket) do
    notice =
      if Settings.migration_notice_dismissed?() do
        nil
      else
        case Buckets.migration_summary() do
          %{migrated?: true} = summary -> summary
          _not_migrated -> nil
        end
      end

    assign(socket, :migration_notice, notice)
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
    base_currency = socket.assigns.portfolio.base_currency_code
    classification_id = socket.assigns.classification_id
    view_id = socket.assigns[:active_view_id]

    start_async(socket, :overview, fn ->
      # The header totals and cash come from the cross-portfolio view valuation
      # (ADR-0024): the page's primary scope is the active view — Everything
      # when none is picked — deduplicated at the account level. The allocation
      # stays on the portfolio-bound read (its per-portfolio SOLL plans,
      # ADR-0020) filtered by the same view.
      valuation = Valuation.for_view(view_id, base_currency: base_currency)
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
    {:noreply, socket |> assign(:valuation, valuation) |> assign_allocation(allocation)}
  end

  def handle_async(:allocation, {:ok, allocation}, socket) do
    {:noreply, assign_allocation(socket, allocation)}
  end

  def handle_async(:performance, {:ok, analysis}, socket) do
    {:ok, performance} = Performance.summarise(analysis, socket.assigns.period)
    {:noreply, assign(socket, analysis: analysis, performance: performance)}
  end

  # The background rate sync (issue #432, UAT fix round): the outcome lands
  # as an inline status line next to the button; a success re-values the
  # figures the same way the old synchronous path did.
  def handle_async(:sync_rates, {:ok, {:ok, %{upserted: count}}}, socket) do
    {:noreply,
     socket
     |> assign(fx_syncing: false, fx_sync_result: {:ok, count})
     |> load_overview()
     |> load_performance()}
  end

  def handle_async(:sync_rates, {:ok, {:error, _reason}}, socket) do
    {:noreply, assign(socket, fx_syncing: false, fx_sync_result: :error)}
  end

  def handle_async(:sync_rates, {:exit, _reason}, socket) do
    {:noreply, assign(socket, fx_syncing: false, fx_sync_result: :error)}
  end

  def handle_async(_name, {:exit, _reason}, socket) do
    {:noreply, assign(socket, error: gettext("Couldn't load the wealth figures."))}
  end

  # One landing spot for a loaded allocation: resolved display colours plus
  # the two lookups the collapsible tree needs (parent chain per category and
  # which categories have child categories).
  defp assign_allocation(socket, allocation) do
    allocation = with_display_colors(allocation)

    parent_map = Map.new(allocation.categories, &{&1.category_id, &1.parent_id})

    parents_with_children =
      allocation.categories
      |> Enum.map(& &1.parent_id)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    assign(socket,
      allocation: allocation,
      category_parent_map: parent_map,
      category_parents_with_children: parents_with_children
    )
  end

  # A row is visible when every ancestor on its parent chain is expanded -
  # collapsing a category folds away its whole subtree (owner request).
  defp branch_expanded?(nil, _expanded, _parents), do: true

  defp branch_expanded?(category_id, expanded, parents) do
    MapSet.member?(expanded, category_id) and
      branch_expanded?(Map.get(parents, category_id), expanded, parents)
  end

  # A chevron makes sense when the row has direct children to reveal:
  # subcategory rows and/or its own positions.
  defp has_subtree?(row, parents_with_children) do
    MapSet.member?(parents_with_children, row.category_id) or row.positions != []
  end

  # Resolves every category's display colour once: an explicitly chosen colour
  # wins, everything else cycles through the palette in tree order. Downstream
  # consumers (sunburst, legend, drift table) can then rely on `color` being
  # set.
  defp with_display_colors(allocation) do
    categories =
      allocation.categories
      |> Enum.with_index()
      |> Enum.map(fn {row, index} ->
        %{
          row
          | color: row.color || Enum.at(@category_palette, rem(index, length(@category_palette)))
        }
      end)

    %{allocation | categories: categories}
  end

  @impl true
  def render(%{portfolio: nil} = assigns) do
    ~H"""
    <AppShell.shell current_path={@current_path} page_title={gettext("Wealth")}>
      <div class="workspace-page">
        <section class="workspace-section empty-state">
          <h2><%= gettext("Wealth") %></h2>
          <p><%= gettext("Create a depot and cash account first to see value, performance and allocation.") %></p>
          <.link navigate="/portfolios" class="button"><%= gettext("Create a depot and cash account") %></.link>
        </section>
      </div>
    </AppShell.shell>
    """
  end

  def render(assigns) do
    ~H"""
    <AppShell.shell
      current_path={@current_path}
      page_title={gettext("Wealth")}
      page_subtitle={gettext("Value, performance and allocation")}
    >
      <div id="portfolio-overview" class="workspace-page portfolio-overview">
        <%= if @error do %>
          <AppShell.status_toast kind={:error} message={@error} />
        <% end %>
        <%= if @success do %>
          <AppShell.status_toast kind={:success} message={@success} />
        <% end %>

        <AppShell.area_tabs tabs={AppShell.wealth_tabs(@wealth_tab)} />

        <.view_switcher
          current_path={@current_path}
          views={@views}
          active_view={@active_view}
          planned_view_ids={@planned_view_ids}
          show_default_control={true}
          default_view_id={@default_view_id}
        />

        <%!-- One-time ADR-0024 migration notice: the seeded views exist, so
             say what happened once and get out of the way permanently. --%>
        <section
          :if={@migration_notice}
          id="portfolio-migration-notice"
          class="workspace-section"
          data-role="migration-notice"
          role="status"
        >
          <h2><%= gettext("Your portfolios are now views") %></h2>
          <p>
            <%= gettext(
              "The one-time migration turned each portfolio into a bucket and a view of the same name — fully editable, nothing was deleted. Pick a view above to scope this page."
            ) %>
          </p>
          <ul data-role="migration-views">
            <li :for={view <- @migration_notice.views}><%= view.name %></li>
          </ul>
          <button
            type="button"
            class="button-mini"
            data-role="dismiss-migration-notice"
            phx-click="dismiss_migration_notice"
          >
            <%= gettext("Got it") %>
          </button>
        </section>

        <section class="workspace-section grid" aria-label={gettext("Wealth key figures")}>
          <article id="kpi-total" class="stat">
            <span><%= gettext("Total incl. cash") %></span>
            <strong :if={@valuation}>
              <%= Format.money(@valuation.total_with_cash) %> <%= @valuation.base_currency %>
            </strong>
            <strong :if={is_nil(@valuation)}>…</strong>
            <%!-- Overlap badge (ADR-0024 modification 2): the active view's
                 buckets share at least one account. Purely informational —
                 the total already counts each account exactly once. --%>
            <small
              :if={@valuation && overlapping?(@valuation)}
              class="hint"
              data-role="overlap-badge"
              title={gettext(
                "This view's buckets share accounts. Each account is counted once, so per-bucket figures may overlap and must not be summed."
              )}
            >
              <%= gettext("Overlapping buckets — accounts counted once") %>
            </small>
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

        <%!-- Wealth tabs (ADR-0022): Holdings carries the performance chart,
             data quality and cash; Allocation & targets carries the sunburst
             and drift table. KPIs and the view switcher head both. --%>
        <%= if @wealth_tab == :holdings do %>
          <.data_quality valuation={@valuation} analysis={@analysis} />
        <% end %>

        <%= if @wealth_tab == :holdings do %>
        <section id="portfolio-performance" class="workspace-section">
          <header class="section-head">
            <h2><%= gettext("Performance") %></h2>
            <div class="section-head-controls">
              <div class="chart-toggle" role="group" aria-label={gettext("Chart series")}>
                <button
                  type="button"
                  class={["button-mini", @chart_mode == "ttwror" && "is-active"]}
                  phx-click="set_chart_mode"
                  phx-value-mode="ttwror"
                  aria-pressed={to_string(@chart_mode == "ttwror")}
                >
                  <%= gettext("% (TTWROR)") %>
                </button>
                <button
                  type="button"
                  class={["button-mini", @chart_mode == "value" && "is-active"]}
                  phx-click="set_chart_mode"
                  phx-value-mode="value"
                  aria-pressed={to_string(@chart_mode == "value")}
                >
                  <%= gettext("Value (%{currency})", currency: display_currency(assigns)) %>
                </button>
              </div>
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
            </div>
          </header>
          <%= if @performance do %>
            <p
              class={["perf-badge", perf_sign_class(@performance.ttwror)]}
              data-role="period-badge"
            >
              <strong><%= signed_percent(@performance.ttwror) %>%</strong>
              <span class="perf-badge-sep">·</span>
              <span><%= signed_money(period_value_gain(@performance)) %> <%= @performance.base_currency %></span>
              <span class="perf-badge-period">(<%= period_label(@period) %>)</span>
            </p>
            <.performance_chart
              series={downsample(@performance.series)}
              mode={@chart_mode}
              currency={@performance.base_currency}
            />
            <p class="hint">
              <%= gettext("True time-weighted return; deposits and withdrawals are neutralised.") %>
              <%= if @performance.start_date do %>
                <%= @performance.start_date %> – <%= @performance.end_date %>
              <% end %>
            </p>
            <%!-- ADR-0024 modification 4: bucket membership applies
                 retroactively, so a view-scoped series is labelled with its
                 semantics instead of pretending temporal membership. --%>
            <p :if={@active_view} class="hint" data-role="composition-label">
              <%= gettext("Composition as of today") %> —
              <%= gettext("the view's current bucket membership is applied to the whole history.") %>
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
        <% end %>

        <%= if @wealth_tab == :allocation do %>
        <section id="portfolio-allocation" class="workspace-section">
          <header class="section-head">
            <h2><%= gettext("Allocation") %></h2>
            <div class="section-head-controls">
              <%!-- Tree answers "is my structure on plan?"; Positions is the
                   flat rebalancing worklist - sorting belongs to a flat list,
                   not to a hierarchy (owner request). --%>
              <div class="chart-toggle" role="group" aria-label={gettext("Allocation view")}>
                <button
                  type="button"
                  data-role="allocation-mode-tree"
                  class={["button-mini", @allocation_mode == :tree && "is-active"]}
                  phx-click="set_allocation_mode"
                  phx-value-mode="tree"
                  aria-pressed={to_string(@allocation_mode == :tree)}
                >
                  <%= gettext("Tree") %>
                </button>
                <button
                  type="button"
                  data-role="allocation-mode-flat"
                  class={["button-mini", @allocation_mode == :flat && "is-active"]}
                  phx-click="set_allocation_mode"
                  phx-value-mode="flat"
                  aria-pressed={to_string(@allocation_mode == :flat)}
                >
                  <%= gettext("Positions") %>
                </button>
              </div>
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
            </div>
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
            <%= if @allocation_mode == :tree do %>
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

            <%!-- One expand/collapse toggle directly above the table (UAT fix
                 round): the label states the action it will perform next. --%>
            <div class="drift-table-actions">
              <button
                type="button"
                data-role="toggle-all-categories"
                class="button-mini"
                phx-click="toggle_all_categories"
              >
                <%= if all_categories_expanded?(@allocation, @expanded_categories) do %>
                  <%= gettext("Collapse all") %>
                <% else %>
                  <%= gettext("Expand all") %>
                <% end %>
              </button>
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
                          <%= gettext("Target vs. actual: drift is actual weight minus target weight. Positive = overweight (reduce to reach the target), negative = underweight (add to reach it).") %>
                        </p>
                      </details>
                    </th>
                  <% end %>
                </tr>
              </thead>
              <tbody>
                <%= for row <- @allocation.categories do %>
                  <%= if branch_expanded?(row.parent_id, @expanded_categories, @category_parent_map) do %>
                  <tr class={row.depth > 0 && "is-child"}>
                    <%!-- The whole name cell toggles the subtree (UAT fix
                         round): the chevron alone is too small a target. --%>
                    <td
                      style={"padding-left:#{0.75 + row.depth * 1.25}rem"}
                      class={has_subtree?(row, @category_parents_with_children) && "is-clickable"}
                      phx-click={
                        has_subtree?(row, @category_parents_with_children) &&
                          "toggle_category_positions"
                      }
                      phx-value-category-id={row.category_id}
                    >
                      <button
                        :if={has_subtree?(row, @category_parents_with_children)}
                        type="button"
                        class="positions-toggle"
                        data-role="toggle-positions"
                        phx-click="toggle_category_positions"
                        phx-value-category-id={row.category_id}
                        aria-expanded={to_string(expanded?(@expanded_categories, row))}
                        aria-label={gettext("Toggle the category's securities")}
                      >
                        <%= if expanded?(@expanded_categories, row), do: "▾", else: "▸" %>
                      </button>
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
                  <%!-- Drill-down (ADR-0023): the expanded category's member
                       securities, each with its share of the drift and a
                       display-only rebalancing hint. No order is created,
                       stored, or transmitted. --%>
                  <%= if expanded?(@expanded_categories, row) do %>
                    <%= for position <- row.positions do %>
                      <tr class="is-position is-muted" data-role="allocation-position">
                        <td style={"padding-left:#{2.0 + row.depth * 1.25}rem"}>
                          <%= position.security_name %>
                        </td>
                        <td class="num"><%= Format.money(position.market_value) %></td>
                        <td class="num"><%= Format.percent(position.weight) %>%</td>
                        <%= if @allocation.has_plan do %>
                          <td class="num"></td>
                          <td class={[
                            "num",
                            position.drift_value &&
                              Decimal.compare(position.drift_value, 0) == :lt &&
                              "is-negative"
                          ]}>
                            <%= if Decimal.equal?(row.target_weight, 0) or
                                     is_nil(position.drift_value) do %>
                              —
                            <% else %>
                              <%= Format.money(position.drift_value) %>
                              <%= if @valuation, do: @valuation.base_currency %>
                              <.rebalance_hint quantity={position.rebalance_quantity} />
                            <% end %>
                          </td>
                        <% end %>
                      </tr>
                    <% end %>
                  <% end %>
                  <% end %>
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
                  <%!-- The unassigned bucket expands like a category row (UAT
                       fix round), keyed by the "unassigned" sentinel id; its
                       positions carry no target/drift by definition. --%>
                  <tr class="is-muted">
                    <td
                      class="is-clickable"
                      phx-click="toggle_category_positions"
                      phx-value-category-id="unassigned"
                    >
                      <button
                        type="button"
                        class="positions-toggle"
                        data-role="toggle-positions"
                        phx-click="toggle_category_positions"
                        phx-value-category-id="unassigned"
                        aria-expanded={to_string(MapSet.member?(@expanded_categories, :unassigned))}
                        aria-label={gettext("Toggle the category's securities")}
                      >
                        <%= if MapSet.member?(@expanded_categories, :unassigned), do: "▾", else: "▸" %>
                      </button>
                      <%= gettext("Unassigned") %>
                    </td>
                    <td class="num"><%= Format.money(@allocation.unassigned.market_value) %></td>
                    <td class="num">
                      <%= Format.percent(@allocation.unassigned.actual_weight) %>%
                    </td>
                    <%= if @allocation.has_plan do %>
                      <td class="num">—</td>
                      <td class="num">—</td>
                    <% end %>
                  </tr>
                  <%= if MapSet.member?(@expanded_categories, :unassigned) do %>
                    <%= for position <- @allocation.unassigned.positions do %>
                      <tr class="is-position is-muted" data-role="allocation-position">
                        <td style="padding-left:2.0rem">
                          <%= position.security_name %>
                        </td>
                        <td class="num"><%= Format.money(position.market_value) %></td>
                        <td class="num"><%= Format.percent(position.weight) %>%</td>
                        <%= if @allocation.has_plan do %>
                          <td class="num">—</td>
                          <td class="num">—</td>
                        <% end %>
                      </tr>
                    <% end %>
                  <% end %>
                <% end %>
              </tbody>
            </table>

            <%= if @allocation.unassigned && Decimal.compare(@allocation.unassigned.actual_weight, 0) == :gt do %>
              <p class="hint" data-role="unassigned-hint">
                <%= gettext("%{pct}% of holdings aren't assigned to a category.",
                  pct: Format.percent(@allocation.unassigned.actual_weight)
                ) %>
                <.link navigate={"/classifications/#{@classification_id}"}>
                  <%= gettext("Assign them on the Classifications page") %>
                </.link>
              </p>
            <% end %>
            <% end %>

            <%!-- The flat rebalancing worklist: one row per position, ranked
                 by signed drift by default (overweight first, underweight
                 last), re-sortable via the column heads. Cash joins as a row;
                 unassigned positions carry no drift (nudging toward
                 assignment). --%>
            <%= if @allocation_mode == :flat do %>
              <table class="drift-table" data-role="flat-positions">
                <thead>
                  <tr>
                    <th><%= gettext("Security") %></th>
                    <th>
                      <button
                        type="button"
                        class="table-sort"
                        data-role="flat-sort-category"
                        phx-click="sort_flat_positions"
                        phx-value-key="category"
                      >
                        <%= gettext("Category") %><%= flat_sort_marker(@flat_sort, :category) %>
                      </button>
                    </th>
                    <th class="num">
                      <button
                        type="button"
                        class="table-sort"
                        data-role="flat-sort-value"
                        phx-click="sort_flat_positions"
                        phx-value-key="value"
                      >
                        <%= gettext("Value") %><%= flat_sort_marker(@flat_sort, :value) %>
                      </button>
                    </th>
                    <th class="num"><%= gettext("Actual") %></th>
                    <%= if @allocation.has_plan do %>
                      <th class="num">
                        <button
                          type="button"
                          class="table-sort"
                          data-role="flat-sort-drift"
                          phx-click="sort_flat_positions"
                          phx-value-key="drift"
                        >
                          <%= gettext("Drift") %><%= flat_sort_marker(@flat_sort, :drift) %>
                        </button>
                      </th>
                      <th class="num"><%= gettext("Hint") %></th>
                    <% end %>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    :for={entry <- flat_positions(@allocation, @flat_sort)}
                    class={entry.cash? && "is-muted"}
                    data-role={if entry.cash?, do: "flat-cash", else: "flat-position"}
                  >
                    <td><%= entry.security_name %></td>
                    <td>
                      <%= if entry.category_name do %>
                        <span
                          :if={entry.category_color}
                          class="cat-swatch"
                          style={"background:#{entry.category_color}"}
                          aria-hidden="true"
                        >
                        </span>
                        <%= entry.category_name %>
                      <% else %>
                        <span class="hint"><%= gettext("Unassigned") %></span>
                      <% end %>
                    </td>
                    <td class="num"><%= Format.money(entry.market_value) %></td>
                    <td class="num"><%= Format.percent(entry.weight) %>%</td>
                    <%= if @allocation.has_plan do %>
                      <td class={[
                        "num",
                        entry.drift_value && Decimal.compare(entry.drift_value, 0) == :lt &&
                          "is-negative"
                      ]}>
                        <%= if entry.drift_value do %>
                          <%= Format.money(entry.drift_value) %>
                          <%= if @valuation, do: @valuation.base_currency %>
                        <% else %>
                          —
                        <% end %>
                      </td>
                      <td class="num">
                        <%= if rebalance_hint_parts(entry.rebalance_quantity) do %>
                          <.rebalance_hint quantity={entry.rebalance_quantity} />
                        <% else %>
                          —
                        <% end %>
                      </td>
                    <% end %>
                  </tr>
                </tbody>
              </table>
            <% end %>
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
        <% end %>

        <%= if @wealth_tab == :holdings do %>
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
              <button
                type="button"
                phx-click="sync_rates"
                disabled={@fx_syncing}
                phx-disable-with={gettext("Syncing…")}
              >
                <%= gettext("Sync exchange rates") %>
              </button>
              <span :if={@fx_syncing} class="hint" data-role="fx-sync-status" role="status">
                <%= gettext("Syncing exchange rates…") %>
              </span>
              <p
                :if={@fx_sync_result}
                class={["hint", @fx_sync_result == :error && "fx-sync-error"]}
                data-role="fx-sync-result"
                role={if @fx_sync_result == :error, do: "alert", else: "status"}
              >
                <%= fx_sync_result_message(@fx_sync_result) %>
              </p>
              <p class="hint">
                <%= gettext("Fetch the latest exchange rates so foreign-currency cash is valued in the totals.") %>
              </p>
            </div>
          <% else %>
            <p class="hint loading-hint" role="status"><%= gettext("Calculating…") %></p>
          <% end %>
        </section>
        <% end %>
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

  # The display currency for user-facing labels (ADR-0024): taken from the
  # loaded valuation (the number the label describes), with the EUR hub as the
  # fallback before the async read lands — never from portfolio naming.
  defp display_currency(%{valuation: %{base_currency: currency}}), do: currency
  defp display_currency(%{performance: %{base_currency: currency}}), do: currency
  defp display_currency(_assigns), do: "EUR"

  # The portfolio chart renders through the shared SecurityChart component
  # (ADR-0022: one chart path, the security detail chart set the quality bar).
  # The TTWROR series passes its cumulative percentages as ready-made percent
  # values (value_mode: :percent_values) with the zero gain/loss line; the
  # value series is a plain absolute money series. Every point carries a
  # `label`, so the shared crosshair tooltip shows both series (date · % · €)
  # regardless of the displayed line (Steve UAT #336/#411); the data table
  # below stays the accessible fallback (UX-DR10).
  defp performance_chart(assigns) do
    assigns = assign_new(assigns, :mode, fn -> "ttwror" end)

    {quotes, value_mode, zero_line?, aria_label, currency_code} =
      case assigns.mode do
        "value" ->
          {chart_series(assigns.series, assigns.currency, :value), :absolute, false,
           gettext("Value over time"), assigns.currency}

        _ ->
          {chart_series(assigns.series, assigns.currency, :ttwror), :percent_values, true,
           gettext("Cumulative TTWROR over time"), ""}
      end

    assigns =
      assign(assigns,
        quotes: quotes,
        value_mode: value_mode,
        zero_line?: zero_line?,
        aria_label: aria_label,
        currency_code: currency_code
      )

    ~H"""
    <figure id="performance-figure" class="perf-figure" data-chart-mode={@mode}>
      <SecurityChart.chart
        quotes={@quotes}
        show_transactions?={false}
        value_mode={@value_mode}
        zero_line?={@zero_line?}
        aria_label={@aria_label}
        currency_code={@currency_code}
      />
      <details class="perf-table-disclosure">
        <summary><%= gettext("Show data as table") %></summary>
        <table class="perf-data-table">
          <caption class="sr-only"><%= gettext("Performance by date") %></caption>
          <thead>
            <tr>
              <th scope="col"><%= gettext("Date") %></th>
              <th scope="col"><%= gettext("Cumulative TTWROR") %></th>
              <th scope="col"><%= gettext("Value (%{currency})", currency: @currency) %></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={point <- @series}>
              <td><%= Date.to_iso8601(point.date) %></td>
              <td class="num"><%= Format.percent(point.cumulative_ttwror) %>%</td>
              <td class="num"><%= Format.money(point.value) %></td>
            </tr>
          </tbody>
        </table>
      </details>
    </figure>
    """
  end

  # Maps the performance series onto the shared chart's quote shape. The
  # tooltip label always carries both series (% and €), so the hover answers
  # "how much am I up" in both units whichever line is displayed.
  defp chart_series(series, currency, mode) do
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
          "#{signed_percent(point.cumulative_ttwror)}% · #{Format.money(point.value)} #{currency}"
      }
    end)
  end

  # The period badge: TTWROR % beside the absolute € gain, defined as the
  # investment result net of contributions — (end − start) − net external flows
  # — so a deposit never masquerades as performance (it stays consistent with
  # the TTWROR % beside it).
  defp period_value_gain(performance) do
    performance.end_value
    |> Decimal.sub(performance.start_value)
    |> Decimal.sub(performance.net_external_flows)
  end

  defp perf_sign_class(value) do
    case Decimal.compare(value, 0) do
      :gt -> "is-positive"
      :lt -> "is-negative"
      :eq -> "is-flat"
    end
  end

  defp signed_percent(value) do
    signed(value, Format.percent(value))
  end

  defp signed_money(value) do
    signed(value, Format.money(value))
  end

  defp signed(value, formatted) do
    if Decimal.compare(value, 0) == :gt, do: "+" <> formatted, else: formatted
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

  # Switching the chart series (% TTWROR ↔ € value) is pure presentation — the
  # same cached analysis feeds both lines, so it never recomputes and the choice
  # survives period switches (select_period leaves :chart_mode untouched).
  def handle_event("set_chart_mode", %{"mode" => mode}, socket)
      when mode in ["ttwror", "value"] do
    {:noreply, assign(socket, :chart_mode, mode)}
  end

  def handle_event("set_chart_mode", _params, socket), do: {:noreply, socket}

  def handle_event("select_classification", %{"classification_id" => id}, socket) do
    case coerce_id(id) do
      {:ok, classification_id} ->
        {:noreply,
         socket
         |> assign(:classification_id, classification_id)
         |> assign(:selected_segment, nil)
         |> assign(:expanded_categories, MapSet.new())
         |> assign_planned_view_ids()
         |> load_allocation()}

      :error ->
        {:noreply, socket}
    end
  end

  # Expands/collapses a drift-table category into its member securities
  # (ADR-0023). Pure display state; nothing is persisted. The unassigned
  # bucket has no category id, so it toggles under a fixed sentinel.
  def handle_event("toggle_category_positions", %{"category-id" => "unassigned"}, socket) do
    expanded = socket.assigns.expanded_categories

    expanded =
      if MapSet.member?(expanded, :unassigned),
        do: MapSet.delete(expanded, :unassigned),
        else: MapSet.put(expanded, :unassigned)

    {:noreply, assign(socket, :expanded_categories, expanded)}
  end

  def handle_event("toggle_category_positions", %{"category-id" => id}, socket) do
    case coerce_id(id) do
      {:ok, category_id} ->
        expanded = socket.assigns.expanded_categories

        expanded =
          if MapSet.member?(expanded, category_id),
            do: MapSet.delete(expanded, category_id),
            else: MapSet.put(expanded, category_id)

        {:noreply, assign(socket, :expanded_categories, expanded)}

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
    # The cash table is view-scoped across all portfolios (ADR-0024), so any
    # existing account listed there may take a snapshot — the old "must belong
    # to the page's portfolio" guard no longer matches the page's scope.
    with {:ok, account_id} <- coerce_id(params["cash_account_id"]),
         %{id: _} = account <- Portfolios.get_cash_account(account_id),
         {:ok, _tx} <- Ledger.set_cash_balance(Actor.owner_ui(), account, params) do
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

  # The sync runs in the background (UAT fix round): the handler only flips
  # the in-flight flag, so the button disables and the inline status shows
  # immediately; the result lands inline next to the button, not as a toast.
  def handle_event("sync_rates", _params, socket) do
    socket =
      socket
      |> assign(fx_syncing: true, fx_sync_result: nil)
      |> start_async(:sync_rates, fn -> RateSync.sync() end)

    {:noreply, socket}
  end

  def handle_event("dismiss_toast", _params, socket) do
    {:noreply, assign(socket, error: nil, success: nil)}
  end

  # Persists the active selection as the user's default view (ADR-0024): the
  # scope the Wealth page and dashboard open on when nothing explicit was
  # chosen. Everything active (`nil`) clears the preference — Everything IS
  # the built-in default.
  def handle_event("set_default_view", _params, socket) do
    :ok = Settings.set_default_view(socket.assigns.active_view_id)
    {:noreply, assign(socket, :default_view_id, socket.assigns.active_view_id)}
  end

  # Dismisses the one-time migration notice permanently (server-side, so it
  # stays dismissed across browsers and new sessions).
  def handle_event("dismiss_migration_notice", _params, socket) do
    :ok = Settings.dismiss_migration_notice()
    {:noreply, assign(socket, :migration_notice, nil)}
  end

  # One toggle (UAT fix round): expand-all reveals every level down to the
  # positions (unassigned included); once everything is open the same button
  # collapses back to the top-level bird's view.
  def handle_event("toggle_all_categories", _params, socket) do
    allocation = socket.assigns.allocation

    expanded =
      if all_categories_expanded?(allocation, socket.assigns.expanded_categories),
        do: MapSet.new(),
        else: all_expandable_ids(allocation)

    {:noreply, assign(socket, :expanded_categories, expanded)}
  end

  # Tree = structure check, Positions = flat rebalancing worklist.
  def handle_event("set_allocation_mode", %{"mode" => mode}, socket)
      when mode in ["tree", "flat"] do
    {:noreply, assign(socket, :allocation_mode, String.to_existing_atom(mode))}
  end

  # Clicking the active sort key flips its direction; a new numeric key starts
  # desc (worklist semantics: biggest lever first), the category label starts
  # asc (alphabetical reading order).
  def handle_event("sort_flat_positions", %{"key" => key}, socket)
      when key in ["value", "drift", "weight", "category"] do
    key = String.to_existing_atom(key)

    sort =
      case socket.assigns.flat_sort do
        {^key, dir} -> {key, flip_dir(dir)}
        _other -> {key, initial_dir(key)}
      end

    {:noreply, assign(socket, :flat_sort, sort)}
  end

  defp flip_dir(:desc), do: :asc
  defp flip_dir(:asc), do: :desc

  defp initial_dir(:category), do: :asc
  defp initial_dir(_key), do: :desc

  defp expanded?(expanded_categories, row) do
    MapSet.member?(expanded_categories, row.category_id)
  end

  # Every id the toggle-all button can open: all categories plus the
  # unassigned bucket's sentinel when it exists.
  defp all_expandable_ids(nil), do: MapSet.new()

  defp all_expandable_ids(allocation) do
    ids = MapSet.new(allocation.categories, & &1.category_id)
    if allocation.unassigned, do: MapSet.put(ids, :unassigned), else: ids
  end

  # "Everything expanded" drives the toggle label: only true when there is
  # something to expand and none of it is still collapsed.
  defp all_categories_expanded?(allocation, expanded) do
    all = all_expandable_ids(allocation)
    MapSet.size(all) > 0 and MapSet.subset?(all, expanded)
  end

  # Display-only rebalancing hint (ADR-0023): positive drift = sell, negative
  # = buy, at the valuation's implied unit price. Indicative only — rounded at
  # display (ADR-0016), no fee/tax modelling, never turned into an order.
  # The flat worklist rows: every category's positions (each security is
  # directly assigned to exactly one category per tree, so each appears once),
  # unassigned positions without drift, and the cash row unless cash is
  # distributed into currency buckets. Positions in untargeted categories
  # carry no drift/hint, mirroring the tree's dashes.
  defp flat_positions(allocation, sort) do
    from_categories =
      Enum.flat_map(allocation.categories, fn row ->
        untargeted? = Decimal.equal?(row.target_weight, 0)

        Enum.map(row.positions, fn position ->
          Map.merge(position, %{
            category_name: row.name,
            category_color: row.color,
            cash?: false,
            drift_value: if(untargeted?, do: nil, else: position.drift_value),
            rebalance_quantity: if(untargeted?, do: nil, else: position.rebalance_quantity)
          })
        end)
      end)

    unassigned =
      case allocation.unassigned do
        nil ->
          []

        %{positions: entries} ->
          Enum.map(
            entries,
            &Map.merge(&1, %{category_name: nil, category_color: nil, cash?: false})
          )
      end

    sort_flat(from_categories ++ unassigned ++ flat_cash_entry(allocation), sort)
  end

  defp flat_cash_entry(%{cash: %{distributed: true}}), do: []

  defp flat_cash_entry(%{cash: cash} = allocation) do
    steered? = allocation.has_plan and not Decimal.equal?(cash.target_weight, 0)

    [
      %{
        security_id: :cash,
        security_name: gettext("Cash"),
        quantity: nil,
        market_value: cash.market_value,
        weight: cash.actual_weight,
        drift_value: if(steered?, do: cash.drift_value),
        rebalance_quantity: nil,
        category_name: nil,
        category_color: nil,
        cash?: true
      }
    ]
  end

  # Rows without a sortable value (nil drift, no category) sink to the end
  # regardless of direction — the worklist ranks what is actionable.
  defp sort_flat(rows, {key, dir}) do
    {sortable, unsortable} = Enum.split_with(rows, &flat_sort_value(&1, key))
    Enum.sort_by(sortable, &flat_sort_value(&1, key), flat_sorter(key, dir)) ++ unsortable
  end

  # Signed drift (UAT fix round): most-overweight first, most-underweight
  # last — absolute ranking interleaved buys and sells.
  defp flat_sort_value(row, :drift), do: row.drift_value
  defp flat_sort_value(row, :value), do: row.market_value
  defp flat_sort_value(row, :weight), do: row.weight

  defp flat_sort_value(row, :category),
    do: row.category_name && String.downcase(row.category_name)

  # Numeric keys sort as Decimals; the category label is a plain string.
  defp flat_sorter(:category, dir), do: dir
  defp flat_sorter(_key, dir), do: {dir, Decimal}

  defp flat_sort_marker({key, :desc}, key), do: " ↓"
  defp flat_sort_marker({key, :asc}, key), do: " ↑"
  defp flat_sort_marker(_sort, _key), do: ""

  # Display-only rebalancing hint (ADR-0023), rendered in aligned parts —
  # verb | ≈ | right-aligned quantity | unit — so the columns line up
  # vertically across rows (UAT fix round).
  defp rebalance_hint(assigns) do
    assigns = assign(assigns, :parts, rebalance_hint_parts(assigns.quantity))

    ~H"""
    <span :if={@parts} class="rebalance-hint" data-role="rebalance-hint">
      <span class="rebalance-verb"><%= @parts.verb %></span>
      <span class="rebalance-approx">≈</span>
      <span class="rebalance-qty"><%= @parts.quantity %></span>
      <span class="rebalance-unit"><%= gettext("units") %></span>
    </span>
    """
  end

  defp rebalance_hint_parts(nil), do: nil

  defp rebalance_hint_parts(%Decimal{} = quantity) do
    case Decimal.compare(quantity, 0) do
      :gt -> %{verb: gettext("Sell"), quantity: Format.decimal(quantity, 2)}
      :lt -> %{verb: gettext("Buy"), quantity: Format.decimal(Decimal.abs(quantity), 2)}
      :eq -> nil
    end
  end

  # On-demand exchange-rate sync (issue #432): the rate provider only refreshes
  # on a 12 h timer, so a foreign-currency cash account stays unvalued until a
  # rate arrives. This lets the user pull rates now and re-value the figures.
  defp fx_sync_result_message({:ok, count}), do: rates_synced_message(count)
  defp fx_sync_result_message(:error), do: rate_sync_error_message()

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

  # Whether the active view's buckets share at least one account (ADR-0024
  # overlap badge). Tolerates valuations without overlap data.
  defp overlapping?(%{overlap: %{overlapping?: true}}), do: true
  defp overlapping?(_valuation), do: false

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
  # The default steering tree rule lives in the context so the dashboard's
  # drift alerts and this page never disagree (review finding, ADR-0022).
  defp default_classification_id(classifications) do
    Classifications.default_classification(classifications).id
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
        name: gettext("Unassigned"),
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
                name: gettext("Unassigned"),
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
