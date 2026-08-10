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
  alias Portfolixir.Portfolios.PricingContext
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
      |> assign(:view_gone_notice, false)
      |> assign(:classification_gone_notice, false)
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
          |> assign(:range_error, false)
          |> assign(:chart_mode, "ttwror")
          # The classification tree and the tree/positions mode round-trip
          # through the URL (mobile-reconnect fix): a socket reconnect remounts
          # at the current URL, so reading them from the mount params here
          # reconstructs the user's selection instead of snapping back to the
          # defaults. handle_params re-reads the same params (idempotent on the
          # initial mount) and is the only path that reloads on a later change.
          |> assign(:classification_id, param_classification_id(params, classifications))
          |> assign(:valuation, nil)
          |> assign(:negative_report, nil)
          |> assign(:allocation, nil)
          |> assign(:analysis, nil)
          |> assign(:performance, nil)
          |> assign(:performance_stale, false)
          |> assign(:performance_failed, false)
          |> assign(:selected_segment, nil)
          |> assign(:expanded_categories, MapSet.new())
          |> assign(:allocation_mode, param_allocation_mode(params))
          |> assign(:flat_sort, {:drift, :desc})
          |> assign(:fx_syncing, false)
          |> assign(:fx_sync_result, nil)
          |> assign(:fx_sync_flash, false)
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

  @impl true
  # URL → state for the allocation selections (mobile-reconnect fix). mount
  # already reads the same params, so on the initial mount this is idempotent:
  # the classification matches what mount set, so the expensive allocation read
  # is NOT re-triggered here (the overview/performance async reads stay in
  # mount's start_loading and never run in handle_params). A later push_patch
  # from `select_classification`/`set_allocation_mode` is the only path that
  # actually changes a selection — a classification change reloads the
  # allocation exactly once; a mode change reloads nothing.
  def handle_params(_params, _uri, %{assigns: %{portfolio: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_params(params, _uri, socket) do
    classification_id = param_classification_id(params, socket.assigns.classifications)
    allocation_mode = param_allocation_mode(params)

    current_path =
      case socket.assigns.wealth_tab do
        :allocation ->
          allocation_current_path(params["view"], classification_id, allocation_mode)

        # Other tabs have no allocation controls; keep mount's tab+view path.
        _other ->
          socket.assigns.current_path
      end

    socket =
      socket
      |> assign(:allocation_mode, allocation_mode)
      |> assign(:current_path, current_path)

    socket =
      if classification_id == socket.assigns.classification_id do
        socket
      else
        socket
        |> assign(:classification_id, classification_id)
        |> assign(:selected_segment, nil)
        |> assign(:expanded_categories, MapSet.new())
        |> assign_planned_view_ids()
        |> load_allocation()
      end

    {:noreply, maybe_canonicalize_patch(socket, params)}
  end

  # URL ↔ state convergence (async-hardening round): when a requested param was
  # present but fell back (stale tree id, garbled mode), replace-patch the URL
  # once to the canonical path so the address bar never keeps advertising a
  # state the page does not show. Loop-safe: the patch only fires when a
  # requested value is present AND differs from the canonical one, and the
  # canonical params round-trip verbatim. Connected sockets only — the dead
  # render must not turn into an HTTP redirect.
  defp maybe_canonicalize_patch(%{assigns: %{wealth_tab: :allocation}} = socket, params) do
    stale? =
      present_but_stale?(
        params["classification"],
        Integer.to_string(socket.assigns.classification_id)
      ) or
        present_but_stale?(params["alloc"], allocation_mode_param(socket.assigns.allocation_mode))

    if connected?(socket) and stale? do
      # current_path IS the canonical allocation path (assigned above).
      push_patch(socket, to: socket.assigns.current_path, replace: true)
    else
      socket
    end
  end

  defp maybe_canonicalize_patch(socket, _params), do: socket

  defp present_but_stale?(nil, _canonical), do: false
  defp present_but_stale?(requested, canonical), do: requested != canonical

  # Reads the classification tree from the URL, validating it still names a
  # loaded tree; a missing, malformed, or stale (deleted) id degrades to the
  # default tree instead of crashing.
  defp param_classification_id(params, classifications) do
    with id when is_binary(id) <- Map.get(params, "classification"),
         {:ok, parsed} <- coerce_id(id),
         true <- Enum.any?(classifications, &(&1.id == parsed)) do
      parsed
    else
      _ -> default_classification_id(classifications)
    end
  end

  # Reads the tree/positions mode from the URL. Explicit whitelist match — never
  # `String.to_atom/1` on external input (AGENTS.md). Default `:tree`.
  defp param_allocation_mode(%{"alloc" => "positions"}), do: :flat
  defp param_allocation_mode(%{"alloc" => "tree"}), do: :tree
  defp param_allocation_mode(_params), do: :tree

  # The internal mode atom as the short URL value (`:flat` reads as "positions",
  # matching the button label and the flat worklist).
  defp allocation_mode_param(:flat), do: "positions"
  defp allocation_mode_param(:tree), do: "tree"

  # The tree/positions toggle button values map to the internal atoms without
  # `String.to_atom/1` on raw input (AGENTS.md): explicit whitelist only.
  defp allocation_mode_atom("flat"), do: :flat
  defp allocation_mode_atom("tree"), do: :tree

  # The allocation tab's canonical path: tab, the active view (only when
  # explicitly chosen), the classification and the mode, in a deterministic
  # order so the switchers merge cleanly and a reconnect reconstructs the state.
  defp allocation_current_path(view, classification_id, allocation_mode) do
    pairs =
      [{"tab", "allocation"}] ++
        view_pairs(view) ++
        [
          {"classification", Integer.to_string(classification_id)},
          {"alloc", allocation_mode_param(allocation_mode)}
        ]

    "/portfolio?" <> URI.encode_query(pairs)
  end

  defp view_pairs(view) when is_binary(view) and view != "", do: [{"view", view}]
  defp view_pairs(_view), do: []

  # The `?view=` value carried by the current path, so an allocation patch keeps
  # the active view alongside the classification/mode it changes.
  defp current_view_param(path) do
    case URI.parse(path).query do
      nil -> nil
      query -> query |> URI.decode_query() |> Map.get("view")
    end
  end

  # The one-time ADR-0024 migration notice: shown while the seeded views exist
  # and the maintainer has not dismissed it yet; two cheap indexed reads.
  # No seeded views left (all deleted, only buckets remain) means there is
  # nothing to announce — the notice must not render an empty list (fix round).
  defp assign_migration_notice(socket) do
    notice =
      if Settings.migration_notice_dismissed?() do
        nil
      else
        case Buckets.migration_summary() do
          %{migrated?: true, views: [_ | _]} = summary -> summary
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
    socket = ensure_live_view_scope(socket)
    portfolio_id = socket.assigns.portfolio.id
    base_currency = socket.assigns.portfolio.base_currency_code
    classification_id = socket.assigns.classification_id
    view_id = socket.assigns[:active_view_id]

    start_async(socket, :overview, fn ->
      # The header totals and cash come from the cross-portfolio view valuation
      # (ADR-0024): the page's primary scope is the active view — Everything
      # when none is picked — deduplicated at the account level. The allocation
      # stays on the portfolio-bound read (its per-portfolio SOLL plans,
      # ADR-0020) filtered by the same view. A view deleted between the check
      # above and this read degrades via `handle_async` (fix round). The result
      # carries the classification it was computed for, so a stale mount-era
      # completion can never overwrite a newer tree's allocation
      # (async-hardening round). A tree deleted mid-read degrades the same way
      # the allocation read does.
      #
      # ADR-0035: the header total and the allocation price the same holdings,
      # so this block loads its market data ONCE and threads it into both.
      context = PricingContext.for_all_portfolios(base_currency)

      with %{} = valuation <-
             Valuation.for_view(view_id, base_currency: base_currency, pricing_context: context),
           {:ok, allocation} <-
             Allocation.for_portfolio(portfolio_id, classification_id,
               view: view_id,
               pricing_context: context
             ) do
        # Negative-holdings debris (#570) is a property of the dataset, not
        # of the active view, so the report is global and loads with the
        # other data-quality inputs.
        {valuation, classification_id, allocation, Ledger.negative_holdings_report()}
      else
        {:error, :view_not_found} -> :view_not_found
        {:error, :not_found} -> :classification_not_found
      end
    end)
  end

  defp load_allocation(socket) do
    socket = ensure_live_view_scope(socket)
    portfolio_id = socket.assigns.portfolio.id
    classification_id = socket.assigns.classification_id
    view_id = socket.assigns[:active_view_id]

    start_async(socket, :allocation, fn ->
      case Allocation.for_portfolio(portfolio_id, classification_id, view: view_id) do
        {:ok, allocation} -> allocation
        {:error, :view_not_found} -> :view_not_found
        # The tree was deleted in another tab between selection and this read
        # (async-hardening round): degrade via `handle_async` instead of
        # crashing the async with a CaseClauseError.
        {:error, :not_found} -> :classification_not_found
      end
    end)
  end

  defp load_performance(socket) do
    socket = ensure_live_view_scope(socket)
    view_id = socket.assigns[:active_view_id]
    # The cross-portfolio view walk (#577): the TTWROR/IRR cover exactly the
    # accounts the header total covers — the active view's deduplicated
    # account scope, Everything when none is picked — valued in the same base
    # currency as the header valuation.
    base_currency = socket.assigns.portfolio.base_currency_code

    socket
    |> serve_previous_analysis(view_id, base_currency)
    |> start_async(:performance, fn ->
      Performance.view_analysis(view_id, base_currency: base_currency)
    end)
  end

  # ADR-0032 §6: while the fresh walk computes, render the superseded series
  # instead of a skeleton -- ALWAYS labelled (as-of, booking basis, recomputing
  # marker), swapped atomically when the fresh one lands, and turned into an
  # error state if the recomputation dies. Never an unlabelled old number.
  defp serve_previous_analysis(socket, view_id, base_currency) do
    case Performance.previous_view_analysis(view_id, base_currency: base_currency) do
      %{daily: [_ | _]} = previous ->
        {:ok, performance} = Performance.summarise(previous, socket.assigns.period)

        socket
        |> assign(:analysis, previous)
        |> assign(:performance, performance)
        |> assign(:performance_stale, true)
        |> assign(:performance_failed, false)

      _none ->
        socket
        |> assign(:performance_stale, false)
        |> assign(:performance_failed, false)
    end
  end

  # The active view can be deleted in another tab while this page still holds
  # its id (fix round): re-check before each load and degrade to the built-in
  # Everything scope with a small notice instead of a dead "Couldn't load"
  # toast.
  defp ensure_live_view_scope(socket) do
    view_id = socket.assigns[:active_view_id]

    if view_id && is_nil(Buckets.get_view(view_id)) do
      degrade_to_everything(socket)
    else
      socket
    end
  end

  defp degrade_to_everything(socket) do
    socket
    |> assign(:active_view, nil)
    |> assign(:active_view_id, nil)
    |> assign(:view_gone_notice, true)
  end

  # The selected classification tree was deleted in another tab while this
  # page still offered it (async-hardening round, mirroring the view-gone
  # pattern): refresh the tree list, fall back to the default tree, and say so
  # with a small notice instead of the generic error toast.
  defp degrade_to_default_classification(socket) do
    classifications = Classifications.list_classifications()

    socket
    |> assign(:classifications, classifications)
    |> assign(:classification_id, default_classification_id(classifications))
    |> assign(:selected_segment, nil)
    |> assign(:expanded_categories, MapSet.new())
    |> assign_planned_view_ids()
    |> assign(:classification_gone_notice, true)
  end

  @impl true
  # The view vanished mid-read (fix round TOCTOU): degrade and re-load the
  # section under the Everything scope.
  def handle_async(:overview, {:ok, :view_not_found}, socket) do
    {:noreply, socket |> degrade_to_everything() |> load_overview()}
  end

  def handle_async(:allocation, {:ok, :view_not_found}, socket) do
    {:noreply, socket |> degrade_to_everything() |> load_allocation()}
  end

  def handle_async(:performance, {:ok, {:error, :view_not_found}}, socket) do
    {:noreply, socket |> degrade_to_everything() |> load_performance()}
  end

  # The tree vanished mid-read (async-hardening round): degrade to the default
  # tree and re-load the affected section under it.
  def handle_async(:overview, {:ok, :classification_not_found}, socket) do
    {:noreply, socket |> degrade_to_default_classification() |> load_overview()}
  end

  def handle_async(:allocation, {:ok, :classification_not_found}, socket) do
    {:noreply, socket |> degrade_to_default_classification() |> load_allocation()}
  end

  def handle_async(
        :overview,
        {:ok, {valuation, classification_id, allocation, negative_report}},
        socket
      ) do
    socket =
      socket
      |> assign(:valuation, valuation)
      |> assign(:negative_report, negative_report)

    # Cross-key staleness guard (async-hardening round): LiveView's ref pruning
    # only cancels same-key tasks, so a mount-era :overview can land after the
    # user already patched to another tree and its :allocation task delivered.
    # The valuation is classification-independent and always lands; the
    # allocation only lands when it still matches the selected tree — on a
    # mismatch the newer tree's allocation (loaded or in flight) is kept.
    socket =
      if classification_id == socket.assigns.classification_id do
        assign_allocation(socket, allocation)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_async(:allocation, {:ok, allocation}, socket) do
    {:noreply, assign_allocation(socket, allocation)}
  end

  def handle_async(:performance, {:ok, analysis}, socket) do
    {:ok, performance} = Performance.summarise(analysis, socket.assigns.period)

    {:noreply,
     assign(socket,
       analysis: analysis,
       performance: performance,
       performance_stale: false,
       performance_failed: false
     )}
  end

  # The background rate sync (issue #432, UAT fix rounds): the outcome lands
  # as a compact inline status line next to the button; a success re-values
  # the figures the same way the old synchronous path did. Because the sync
  # completes sub-second, success also flashes IN the button ("✓ Up to date",
  # disabled) until :clear_fx_flash fires — otherwise the disabled state is
  # invisible and the button feels like it did nothing.
  def handle_async(:sync_rates, {:ok, {:ok, %{upserted: count}}}, socket) do
    Process.send_after(self(), :clear_fx_flash, 3000)

    {:noreply,
     socket
     |> assign(
       fx_syncing: false,
       fx_sync_flash: true,
       fx_sync_result: {:ok, count, NaiveDateTime.local_now()}
     )
     |> load_overview()
     |> load_performance()}
  end

  def handle_async(:sync_rates, {:ok, {:error, _reason}}, socket) do
    {:noreply, assign(socket, fx_syncing: false, fx_sync_result: :error)}
  end

  def handle_async(:sync_rates, {:exit, _reason}, socket) do
    {:noreply, assign(socket, fx_syncing: false, fx_sync_result: :error)}
  end

  def handle_async(:performance, {:exit, _reason}, socket) do
    # §6: a failed recomputation becomes an ERROR state; the superseded series
    # may stay on screen but its marker must say failed, never quietly settle.
    {:noreply, assign(socket, performance_failed: true)}
  end

  def handle_async(_name, {:exit, _reason}, socket) do
    {:noreply, assign(socket, error: gettext("Couldn't load the wealth figures."))}
  end

  @impl true
  # Ends the transient "✓ Up to date" confirmation in the sync button.
  def handle_info(:clear_fx_flash, socket) do
    {:noreply, assign(socket, :fx_sync_flash, false)}
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

        <%!-- The picked view was deleted (another tab, fix round): the page
             degraded to the Everything scope instead of a dead error toast. --%>
        <p :if={@view_gone_notice} class="hint" data-role="view-gone-notice" role="status">
          <%= gettext("The selected view no longer exists — showing Everything.") %>
        </p>

        <%!-- The picked classification tree was deleted (another tab,
             async-hardening round): the page degraded to the default tree
             instead of a dead error toast. --%>
        <p
          :if={@classification_gone_notice}
          class="hint"
          data-role="classification-gone-notice"
          role="status"
        >
          <%= gettext("The selected classification no longer exists — showing the default tree.") %>
        </p>

        <%!-- Matches-nothing hint (fix round): the active view resolves to
             zero accounts, so the 0 total is a definition issue, not data. --%>
        <p
          :if={@active_view && matches_no_accounts?(@valuation)}
          class="hint"
          data-role="view-matches-nothing"
          role="status"
        >
          <%= gettext(
            "This view matches no accounts — its included buckets are empty or no longer assigned. Edit the view under Manage… or tag accounts into its buckets."
          ) %>
        </p>

        <%!-- One-time ADR-0024 migration notice: the seeded views exist, so
             say what happened once and get out of the way permanently. --%>
        <section
          :if={@migration_notice}
          id="portfolio-migration-notice"
          class="workspace-section"
          data-role="migration-notice"
          role="status"
        >
          <h2><%= gettext("Portfolios are now views") %></h2>
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
              <span
                id="count-kpi-total"
                class="count-up"
                phx-hook="CountUp"
                data-count-to={Decimal.to_string(@valuation.total_with_cash, :normal)}
                data-decimals="2"
              ><span data-count-digits><%= Format.money(@valuation.total_with_cash) %></span></span>
              <%= @valuation.base_currency %>
            </strong>
            <strong :if={is_nil(@valuation)} class="value-slot-pending" aria-busy="true">
              <span class="value-skeleton" aria-hidden="true"></span>
              <span class="recomputing-cue"><span class="spinner"></span> <%= gettext("computing") %></span>
            </strong>
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
              <span
                id="count-kpi-securities"
                class="count-up"
                phx-hook="CountUp"
                data-count-to={Decimal.to_string(@valuation.total_value, :normal)}
                data-decimals="2"
              ><span data-count-digits><%= Format.money(@valuation.total_value) %></span></span>
              <%= @valuation.base_currency %>
            </strong>
            <strong :if={is_nil(@valuation)} class="value-slot-pending" aria-busy="true">
              <span class="value-skeleton" aria-hidden="true"></span>
              <span class="recomputing-cue"><span class="spinner"></span> <%= gettext("computing") %></span>
            </strong>
          </article>
          <article id="kpi-cash" class="stat" role="group" aria-describedby="tip-cash-quote">
            <span><%= gettext("Cash") %> · <%= gettext("cash quote") %></span>
            <strong :if={@valuation}>
              <%= Format.money(@valuation.total_cash) %> <%= @valuation.base_currency %>
              · <%= Format.percent(@valuation.cash_quote) %>%
            </strong>
            <strong :if={is_nil(@valuation)} class="value-slot-pending" aria-busy="true">
              <span class="value-skeleton" aria-hidden="true"></span>
              <span class="recomputing-cue"><span class="spinner"></span> <%= gettext("computing") %></span>
            </strong>
            <details class="metric-tooltip">
              <summary aria-label={gettext("Cash quote info")}>ⓘ</summary>
              <p id="tip-cash-quote" role="tooltip">
                <%= gettext("Cash quote: deployable cash ÷ (securities value + deployable cash). Reserve and credit-line accounts are excluded.") %>
              </p>
            </details>
          </article>
          <article id="kpi-ttwror" class="stat" role="group" aria-describedby="tip-ttwror">
            <span><%= gettext("TTWROR") %> (<%= period_label(@period) %>)</span>
            <%!-- Signed metric: gain/loss colour plus sign, never the accent
                 (UX-DR7, issue 637). --%>
            <strong :if={@performance} class={perf_sign_class(@performance.ttwror)}>
              <%= signed_percent(@performance.ttwror) %>%
            </strong>
            <strong :if={is_nil(@performance)} class="value-slot-pending" aria-busy="true">
              <span class="value-skeleton" aria-hidden="true"></span>
              <span class="recomputing-cue"><span class="spinner"></span> <%= gettext("computing") %></span>
            </strong>
            <details class="metric-tooltip">
              <summary aria-label={gettext("TTWROR info")}>ⓘ</summary>
              <p id="tip-ttwror" role="tooltip">
                <%= gettext("TTWROR — time-weighted return for the selected period (not annualized). Deposits and withdrawals are neutralised so only investment performance counts.") %>
              </p>
            </details>
          </article>
          <article id="kpi-irr" class="stat" role="group" aria-describedby="tip-irr">
            <span><%= money_weighted_label(@performance) %> (<%= period_label(@period) %>)</span>
            <strong
              :if={@performance && money_weighted_value(@performance)}
              class={perf_sign_class(money_weighted_value(@performance))}
            >
              <%= signed_percent(money_weighted_value(@performance)) %>%
            </strong>
            <strong :if={@performance && is_nil(money_weighted_value(@performance))}>—</strong>
            <strong :if={is_nil(@performance)} class="value-slot-pending" aria-busy="true">
              <span class="value-skeleton" aria-hidden="true"></span>
              <span class="recomputing-cue"><span class="spinner"></span> <%= gettext("computing") %></span>
            </strong>
            <details class="metric-tooltip">
              <summary aria-label={money_weighted_info_label(@performance)}>ⓘ</summary>
              <p id="tip-irr" role="tooltip">
                <%= gettext("IRR — money-weighted return, annualized. Discounts the timing and size of cashflows over the period. Windows shorter than a year show the period MWR — the same figure, not annualized.") %>
              </p>
            </details>
          </article>
          <%!-- Invested capital as two labeled numbers — opening value and
               net period flows, never one merged figure (ADR-0034 §3). --%>
          <article id="kpi-invested" class="stat" role="group" aria-describedby="tip-invested">
            <span>
              <%= gettext("Opening value") %> · <%= gettext("net flows") %> (<%= period_label(
                @period
              ) %>)
            </span>
            <strong :if={@performance}>
              <%= Format.money(@performance.start_value) %>
              · <span class={perf_sign_class(@performance.net_external_flows)}><%= Format.signed_decimal(
                  @performance.net_external_flows,
                  2
                ) %></span> <%= @performance.base_currency %>
            </strong>
            <strong :if={is_nil(@performance)} class="value-slot-pending" aria-busy="true">
              <span class="value-skeleton" aria-hidden="true"></span>
              <span class="recomputing-cue"><span class="spinner"></span> <%= gettext("computing") %></span>
            </strong>
            <details class="metric-tooltip">
              <summary aria-label={gettext("Invested capital info")}>ⓘ</summary>
              <p id="tip-invested" role="tooltip">
                <%= gettext("Invested capital for the period: value at the period start plus net external flows (deposits minus withdrawals, deliveries at transaction value). Basis of the wealth multiple.") %>
              </p>
            </details>
          </article>
          <article id="kpi-multiple" class="stat" role="group" aria-describedby="tip-multiple">
            <span><%= gettext("Wealth multiple") %> (<%= period_label(@period) %>)</span>
            <strong :if={@performance && @performance.wealth_multiple}>
              ×<%= Format.decimal(@performance.wealth_multiple, 2) %>
            </strong>
            <strong :if={@performance && is_nil(@performance.wealth_multiple)}>
              <%= gettext("n/a") %>
            </strong>
            <strong :if={is_nil(@performance)} class="value-slot-pending" aria-busy="true">
              <span class="value-skeleton" aria-hidden="true"></span>
              <span class="recomputing-cue"><span class="spinner"></span> <%= gettext("computing") %></span>
            </strong>
            <details class="metric-tooltip">
              <summary aria-label={gettext("Wealth multiple info")}>ⓘ</summary>
              <p id="tip-multiple" role="tooltip">
                <%= gettext("Wealth multiple — end value ÷ invested capital: what the money put in has become. n/a when net invested capital is zero or negative.") %>
              </p>
            </details>
          </article>
        </section>

        <%!-- Wealth tabs (ADR-0022): Holdings carries the performance chart,
             data quality and cash; Allocation & targets carries the sunburst
             and drift table. KPIs and the view switcher head both. --%>
        <%= if @wealth_tab == :holdings do %>
          <.data_quality valuation={@valuation} analysis={@analysis} negative={@negative_report} />
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
              <%!-- #563: a single previous year and a custom range are pure
                   re-chains of the cached analysis, exactly like the buttons
                   — no new walk. --%>
              <form id="period-year-form" class="period-year" phx-change="select_year" data-role="period-year">
                <label class="visually-hidden" for="performance-year"><%= gettext("Year") %></label>
                <select
                  id="performance-year"
                  name="year"
                  disabled={available_years(@analysis) == []}
                >
                  <option value="" selected={not match?({:year, _year}, @period)}>
                    <%= gettext("Year…") %>
                  </option>
                  <option
                    :for={year <- available_years(@analysis)}
                    value={year}
                    selected={@period == {:year, year}}
                  >
                    <%= year %>
                  </option>
                </select>
              </form>
              <form class="period-range" phx-submit="select_range" data-role="period-range">
                <label class="visually-hidden" for="performance-from"><%= gettext("From") %></label>
                <input
                  type="text"
                  inputmode="numeric"
                  placeholder="YYYY-MM-DD"
                  pattern="[0-9]{4}-[0-9]{2}-[0-9]{2}"
                  maxlength="10"
                  id="performance-from"
                  name="from"
                  value={range_from(@period, @performance)}
                />
                <label class="visually-hidden" for="performance-to"><%= gettext("To") %></label>
                <input
                  type="text"
                  inputmode="numeric"
                  placeholder="YYYY-MM-DD"
                  pattern="[0-9]{4}-[0-9]{2}-[0-9]{2}"
                  maxlength="10"
                  id="performance-to"
                  name="to"
                  value={range_to(@period, @performance)}
                />
                <button type="submit" class="button-mini"><%= gettext("Apply") %></button>
              </form>
            </div>
          </header>
          <%!-- #563: a backwards or unparsable range is refused with a terse
               note; the shown period keeps. --%>
          <p :if={@range_error} class="hint" data-role="range-error" role="alert">
            <%= gettext("Invalid range — from must be on or before to.") %>
          </p>
          <%!-- ADR-0032 §6: a superseded series never renders unlabelled. The
               banner names the data it CONTAINS (booking count, newest booking,
               compute time), not just its age; a failed recomputation flips to
               an error state instead of letting the old number settle. --%>
          <p
            :if={@performance_stale and not @performance_failed and @analysis}
            class="perf-stale-banner"
            role="status"
            data-role="performance-stale"
          >
            <%= stale_series_label(@analysis) %>
          </p>
          <p
            :if={@performance_failed and @analysis}
            class="alert-error"
            role="alert"
            data-role="performance-failed"
          >
            <%= gettext(
              "Recomputation failed. The shown series is superseded: %{basis}. Reload retries.",
              basis: series_basis_label(@analysis)
            ) %>
          </p>
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
            <%!-- UX-DR11 (Sprint 5 Lane D): the sightline keeps the period
                 basis; the methodology sentence lives in the ⓘ tooltip. --%>
            <div class="hint" data-role="performance-basis">
              <%= if @performance.start_date do %>
                <span><%= @performance.start_date %> – <%= @performance.end_date %></span>
              <% end %>
              <details class="metric-tooltip">
                <summary aria-label={gettext("TTWROR info")}>ⓘ</summary>
                <p role="tooltip">
                  <%= gettext("True time-weighted return; deposits and withdrawals are neutralised.") %>
                </p>
              </details>
            </div>
            <%!-- ADR-0024 modification 4: bucket membership applies
                 retroactively, so a view-scoped series is labelled with its
                 semantics instead of pretending temporal membership. --%>
            <div :if={@active_view} class="hint" data-role="composition-label">
              <%= gettext("Composition as of today") %>
              <details class="metric-tooltip">
                <summary aria-label={gettext("Composition info")}>ⓘ</summary>
                <p role="tooltip">
                  <%= gettext("the view's current bucket membership is applied to the whole history.") %>
                </p>
              </details>
            </div>
          <% else %>
            <div class="section-skeleton" data-role="performance-skeleton" role="status">
              <span class="recomputing-cue">
                <span class="spinner"></span> <%= gettext("computing") %>
              </span>
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
              <form id="allocation-classification-form" phx-change="select_classification">
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
                <%!-- A 0% top level over a plan steered deeper in the tree is
                     explained, not left as a contradiction (fix round). --%>
                <%= if deep_targets_below?(@allocation) do %>
                  — <%= gettext("targets deeper in the tree:") %>
                  <%= Format.percent(@allocation.deep_target_sum) %>%
                <% end %>
              </p>
            <% else %>
              <%!-- Scope-aware copy (fix round): only a named view may talk
                   about "this view"; the Gesamt scope speaks plainly. --%>
              <p class="hint no-plan-hint" data-role="no-plan-hint" role="status">
                <%= if @active_view_id do %>
                  <%= gettext("No target plan for this view — showing actual allocation only.") %>
                <% else %>
                  <%= gettext("No target plan yet — showing actual allocation only.") %>
                <% end %>
                <.link navigate={plan_editor_path(@classification_id, @active_view_id)}>
                  <%= if @active_view_id do %>
                    <%= gettext("Create a plan for this view") %>
                  <% else %>
                    <%= gettext("Create a plan") %>
                  <% end %>
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
                      <%!-- A parent without an own weight gets an honest hint
                           (fix round): its children's Σ is stated without
                           the nonsensical "of 0.0%" comparison. --%>
                      <span
                        :if={@allocation.has_plan and row.child_target_sum}
                        class={["hint", "target-consistency", subcategory_mismatch?(row) && "is-target-mismatch"]}
                        data-role="target-consistency-hint"
                      >
                        <%= if Decimal.equal?(row.target_weight, 0) do %>
                          <%= gettext("subcategories Σ") %>
                          <%= Format.percent(row.child_target_sum) %>%
                          <%= gettext("(no own weight)") %>
                        <% else %>
                          <%= gettext("subcategories:") %>
                          <%= Format.percent(row.child_target_sum) %>% <%= gettext("of") %>
                          <%= Format.percent(row.target_weight) %>%
                        <% end %>
                      </span>
                      <%!-- ADR-0030 slice 2a: badge a category whose SOLL is
                           position-steered against a diverging explicit weight
                           (conflict) or carries a stale position row. Focusable
                           text badge with microcopy (UX-DR7/UX-DR11); the
                           details/summary pattern matches the drift tooltip. --%>
                      <details
                        :if={@allocation.has_plan and (row.conflict or row.has_stale)}
                        class="metric-tooltip target-plan-badge"
                        data-role="category-target-badge"
                      >
                        <summary aria-label={gettext("Position-target notice")}>
                          <%= category_badge_label(row) %>
                        </summary>
                        <p role="tooltip">
                          <%!-- Position-sum-wins rule per ADR-0030; the ADR
                               reference stays out of user-facing copy. --%>
                          <%= if row.conflict do %>
                            <%= gettext("The category's position targets steer here: their sum overrides the stored category weight. Align the position targets and the category weight on the Classifications page.") %>
                          <% end %>
                          <%= if row.has_stale do %>
                            <%= gettext("A position target filed here is stale: its security was moved or unassigned. It keeps counting here until re-filed on the Classifications page.") %>
                          <% end %>
                        </p>
                      </details>
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
                          <%!-- ADR-0030 slice 2a: a SOLL-only row (IST 0) is
                               marked with text, never hue alone (UX-DR7);
                               scope-aware inside a view (fix round). --%>
                          <span :if={not position.held} class="not-held-chip" data-role="not-held">
                            <%= not_held_label(@active_view_id) %>
                          </span>
                          <.position_soll_chips position={position} />
                        </td>
                        <td class="num"><%= Format.money(position.market_value) %></td>
                        <td class="num"><%= Format.percent(position.weight) %>%</td>
                        <%= if @allocation.has_plan do %>
                          <td class="num">
                            <%!-- The position's own SOLL (ADR-0030 slice 2a);
                                 blank without one, as before. --%>
                            <%= if position.target_weight do %>
                              <%= Format.percent(position.target_weight) %>%
                            <% end %>
                          </td>
                          <td class={[
                            "num",
                            position.drift_value &&
                              Decimal.compare(position.drift_value, 0) == :lt &&
                              "is-negative"
                          ]}>
                            <%= if position_drift_shown?(position, row) do %>
                              <%= Format.money(position.drift_value) %>
                              <%= if @valuation, do: @valuation.base_currency %>
                              <.rebalance_hint
                                quantity={position.rebalance_quantity}
                                quote_date={position.quote_date}
                              />
                            <% else %>
                              —
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
                       fix round), keyed by the "unassigned" sentinel id. An
                       unassigned position can still carry a (stale) position
                       SOLL (fix round) — that SOLL steers its filed
                       category's Σ, so the row shows it instead of a dash. --%>
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
                          <.position_soll_chips position={position} />
                        </td>
                        <td class="num"><%= Format.money(position.market_value) %></td>
                        <td class="num"><%= Format.percent(position.weight) %>%</td>
                        <%= if @allocation.has_plan do %>
                          <td class="num">
                            <%= if position.target_weight do %>
                              <%= Format.percent(position.target_weight) %>%
                            <% else %>
                              —
                            <% end %>
                          </td>
                          <td class={[
                            "num",
                            position.drift_value &&
                              Decimal.compare(position.drift_value, 0) == :lt &&
                              "is-negative"
                          ]}>
                            <%= if position.drift_value do %>
                              <%= Format.money(position.drift_value) %>
                              <%= if @valuation, do: @valuation.base_currency %>
                              <.rebalance_hint
                                quantity={position.rebalance_quantity}
                                quote_date={position.quote_date}
                              />
                            <% else %>
                              —
                            <% end %>
                          </td>
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
                    <td>
                      <%= entry.security_name %>
                      <%!-- ADR-0030 slice 2a: SOLL-only rows are marked with
                           text, never hue alone (UX-DR7); scope-aware inside
                           a view (fix round). --%>
                      <span :if={not entry.held} class="not-held-chip" data-role="not-held">
                        <%= not_held_label(@active_view_id) %>
                      </span>
                      <.position_soll_chips position={entry} />
                    </td>
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
                          <.rebalance_hint
                            quantity={entry.rebalance_quantity}
                            quote_date={Map.get(entry, :quote_date)}
                          />
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
            >
              <span class="recomputing-cue">
                <span class="spinner"></span> <%= gettext("computing") %>
              </span>
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
                <input type="text" inputmode="numeric" placeholder="YYYY-MM-DD" pattern="[0-9]{4}-[0-9]{2}-[0-9]{2}" maxlength="10" name="balance[date]" value={Date.to_iso8601(Date.utc_today())} />
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
              <%= gettext("State the balance the bank shows; only later bookings adjust it.") %>
            </p>

            <div class="cash-actions">
              <button
                type="button"
                phx-click="sync_rates"
                disabled={@fx_syncing or @fx_sync_flash}
                phx-disable-with={gettext("Syncing…")}
              >
                <%= cond do %>
                  <% @fx_syncing -> %>
                    <span class="spinner" aria-hidden="true"></span> <%= gettext("Syncing…") %>
                  <% @fx_sync_flash -> %>
                    ✓ <%= gettext("Up to date") %>
                  <% true -> %>
                    <%= gettext("Sync exchange rates") %>
                <% end %>
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
            <p class="hint loading-hint recomputing-cue" role="status">
              <span class="spinner"></span> <%= gettext("computing") %>
            </p>
          <% end %>
        </section>
        <% end %>
      </div>
    </AppShell.shell>
    """
  end

  # -- components -------------------------------------------------------------

  # Surfaces why the totals can deviate from the user's expectation: positions
  # valued at a stale trade price, positions with no price at all, positions
  # priced in a currency without a stored FX path (#406 — a distinct, honest
  # state: the price exists and is shown), bookings whose dates are
  # implausible (import typos like 0217-12-05), and cash accounts excluded
  # because no FX rate to the base currency exists.
  defp data_quality(assigns) do
    assigns =
      assigns
      |> assign(:no_price, unvalued_entries(assigns.valuation, :no_price))
      |> assign(:missing_fx, unvalued_entries(assigns.valuation, :missing_fx))
      |> assign(:trade_priced, trade_priced_count(assigns.valuation))
      |> assign(:suspect_dates, suspect_dates(assigns.analysis))
      |> assign(:unvalued_cash, unvalued_cash(assigns.valuation))
      |> assign(:negative_entries, negative_entries(assigns.negative))

    ~H"""
    <section
      :if={
        @no_price.count > 0 or @missing_fx.count > 0 or @trade_priced > 0 or
          @suspect_dates != [] or @unvalued_cash != [] or @negative_entries != []
      }
      id="portfolio-data-quality"
      class="workspace-section data-quality"
    >
      <h2><%= gettext("Data quality") %></h2>
      <ul>
        <li :if={@trade_priced > 0}>
          <%= ngettext(
            "One held position has no current quote and is valued at its last trade price.",
            "%{count} held positions have no current quote and are valued at their last trade price.",
            @trade_priced
          ) %>
        </li>
        <li :if={@no_price.count > 0} data-role="dq-no-price">
          <%= ngettext(
            "One held position has no price at all and is missing from the totals:",
            "%{count} held positions have no price at all and are missing from the totals:",
            @no_price.count
          ) %>
          <%= Enum.join(@no_price.names, ", ") %>
        </li>
        <li :if={@missing_fx.count > 0} data-role="dq-missing-fx">
          <%= ngettext(
            "One held position has a price but no exchange rate to %{base} stored, so it is missing from the totals: %{entries}. Sync exchange rates to include it.",
            "%{count} held positions have a price but no exchange rate to %{base} stored, so they are missing from the totals: %{entries}. Sync exchange rates to include them.",
            @missing_fx.count,
            base: @valuation.base_currency,
            entries: Enum.join(@missing_fx.names, ", ")
          ) %>
        </li>
        <li :if={@suspect_dates != []}>
          <%= gettext(
            "Bookings dated before 1970 (%{dates}) are applied on the first plausible day — fix those dates in the source and re-import.",
            dates: Enum.map_join(@suspect_dates, ", ", &Date.to_iso8601/1)
          ) %>
        </li>
        <li :if={@unvalued_cash != []}>
          <%= ngettext(
            "One cash account is not counted in the totals because there is no exchange rate to %{base}: %{names}. Sync exchange rates to include it.",
            "%{count} cash accounts are not counted in the totals because there is no exchange rate to %{base}: %{names}. Sync exchange rates to include them.",
            length(@unvalued_cash),
            base: @valuation.base_currency,
            names: Enum.map_join(@unvalued_cash, ", ", &"#{&1.name} (#{&1.currency})")
          ) %>
        </li>
        <li :if={@negative_entries != []} data-role="dq-negative-holdings">
          <%= ngettext(
            "One security has an impossible negative holding quantity — likely an unmodeled corporate action from an imported history. Repair the transaction history:",
            "%{count} securities have an impossible negative holding quantity — likely an unmodeled corporate action from an imported history. Repair the transaction history:",
            length(@negative_entries)
          ) %>
          <span :for={entry <- @negative_entries} class="dq-negative-entry">
            <.link navigate={"/securities/#{entry.security_id}?tab=transactions"}>
              <%= entry.name %>
            </.link>
            (<%= Enum.map_join(
              entry.depots,
              ", ",
              &"#{&1.depot_name}: #{Format.decimal(&1.quantity, 2)}"
            ) %> · <%= gettext("total across depots") %> <%= Format.decimal(entry.total, 2) %>)
          </span>
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
      <%= for {segment, seg_index} <- Enum.with_index(@segments) do %>
        <path
          d={segment.path}
          fill={segment.color}
          fill-opacity={segment.opacity}
          class="sunburst-seg"
          style={"--seg-delay: #{seg_reveal_delay(seg_index, length(@segments))}ms"}
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

  # Progressive fill (owner pick F1, DESIGN.md → Motion): reveals spread
  # across 1.2s, so with each 0.3s fade the whole build lands at ~1.5s.
  # Opacity only — geometry is final from the first frame.
  defp seg_reveal_delay(_index, count) when count <= 1, do: 0
  defp seg_reveal_delay(index, count), do: div(index * 1200, count)

  # -- events -----------------------------------------------------------------

  @impl true
  def handle_event("select_period", %{"period" => period}, socket) do
    if period in Performance.periods() do
      apply_period(socket, period)
    else
      {:noreply, socket}
    end
  end

  # #563: a single calendar year, offered for every year with data. The picked
  # year is validated against the cached analysis' own range.
  def handle_event("select_year", %{"year" => raw}, socket) do
    with {year, ""} <- Integer.parse(raw),
         true <- year in available_years(socket.assigns.analysis) do
      apply_period(socket, {:year, year})
    else
      _invalid -> {:noreply, socket}
    end
  end

  def handle_event("select_year", _params, socket), do: {:noreply, socket}

  # #563: a custom from/to range. A backwards or unparsable range is refused
  # with a terse inline note; the shown period keeps.
  def handle_event("select_range", %{"from" => from, "to" => to}, socket) do
    with {:ok, from} <- Date.from_iso8601(from),
         {:ok, to} <- Date.from_iso8601(to),
         false <- Date.compare(from, to) == :gt do
      apply_period(socket, {:range, from, to})
    else
      _invalid -> {:noreply, assign(socket, :range_error, true)}
    end
  end

  def handle_event("select_range", _params, socket) do
    {:noreply, assign(socket, :range_error, true)}
  end

  # Switching the chart series (% TTWROR ↔ € value) is pure presentation — the
  # same cached analysis feeds both lines, so it never recomputes and the choice
  # survives period switches (select_period leaves :chart_mode untouched).
  def handle_event("set_chart_mode", %{"mode" => mode}, socket)
      when mode in ["ttwror", "value"] do
    {:noreply, assign(socket, :chart_mode, mode)}
  end

  def handle_event("set_chart_mode", _params, socket), do: {:noreply, socket}

  # Round-trips the chosen tree through the URL (mobile-reconnect fix) so a
  # socket reconnect restores it; handle_params applies the change, resets the
  # tree's transient state (selected segment, expanded rows), refreshes the plan
  # markers, and reloads the allocation exactly once. The id is validated
  # against the loaded trees BEFORE the patch (async-hardening round), so the
  # address bar can never end up on an unknown ?classification= while the page
  # shows the default; re-selecting the active tree is a no-op — no duplicate
  # history entry.
  def handle_event("select_classification", %{"classification_id" => id}, socket) do
    with {:ok, classification_id} <- coerce_id(id),
         true <- Enum.any?(socket.assigns.classifications, &(&1.id == classification_id)),
         false <- classification_id == socket.assigns.classification_id do
      {:noreply,
       push_patch(socket,
         to:
           allocation_current_path(
             current_view_param(socket.assigns.current_path),
             classification_id,
             socket.assigns.allocation_mode
           )
       )}
    else
      _invalid_or_current -> {:noreply, socket}
    end
  end

  # Forged-event parity with the set_chart_mode fallback (async-hardening
  # round): a malformed payload degrades instead of crashing the LiveView.
  def handle_event("select_classification", _params, socket), do: {:noreply, socket}

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

  # Tree = structure check, Positions = flat rebalancing worklist. The choice
  # round-trips through the URL (mobile-reconnect fix) so a reconnect restores
  # it; handle_params switches the mode (pure presentation — no reload).
  def handle_event("set_allocation_mode", %{"mode" => mode}, socket)
      when mode in ["tree", "flat"] do
    requested = allocation_mode_atom(mode)

    # Clicking the already-active mode button is a no-op (async-hardening
    # round): no patch, no duplicate history entry.
    if requested == socket.assigns.allocation_mode do
      {:noreply, socket}
    else
      {:noreply,
       push_patch(socket,
         to:
           allocation_current_path(
             current_view_param(socket.assigns.current_path),
             socket.assigns.classification_id,
             requested
           )
       )}
    end
  end

  # Forged-event parity with the set_chart_mode fallback (async-hardening
  # round): a malformed payload degrades instead of crashing the LiveView.
  def handle_event("set_allocation_mode", _params, socket), do: {:noreply, socket}

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
          # A position with its own SOLL (ADR-0030 slice 2a) keeps its own
          # drift/hint even in an untargeted category; only the SOLL-less
          # category-share figures are blanked as before.
          own_soll? = not is_nil(position.target_weight)

          Map.merge(position, %{
            category_name: row.name,
            category_color: row.color,
            cash?: false,
            drift_value: if(untargeted? and not own_soll?, do: nil, else: position.drift_value),
            rebalance_quantity:
              if(untargeted? and not own_soll?, do: nil, else: position.rebalance_quantity)
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
        cash?: true,
        held: true,
        stale: false,
        quote_date: nil
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
  # vertically across rows (UAT fix round). An unheld row's hint is priced at
  # a stored quote, so it states that quote's date as its basis (fix round
  # F7/UX-DR11); held rows price at the live valuation and carry no date.
  defp rebalance_hint(assigns) do
    assigns =
      assigns
      |> assign(:parts, rebalance_hint_parts(assigns.quantity))
      |> assign_new(:quote_date, fn -> nil end)

    ~H"""
    <span
      :if={@parts}
      class="rebalance-hint"
      data-role="rebalance-hint"
      title={@quote_date && gettext("at quote from %{date}", date: @quote_date)}
    >
      <span class="rebalance-verb"><%= @parts.verb %></span>
      <span class="rebalance-approx">≈</span>
      <span class="rebalance-qty"><%= @parts.quantity %></span>
      <span class="rebalance-unit"><%= gettext("units") %></span>
    </span>
    """
  end

  # Row-level position-SOLL markers (fix round): the stale chip names the row
  # whose SOLL row went stale (UAT — the category badge alone made the reader
  # hunt), the no-quote chip explains a missing unit hint on a SOLL-only row.
  # Text chips, never hue alone (UX-DR7).
  defp position_soll_chips(assigns) do
    ~H"""
    <span
      :if={Map.get(@position, :stale, false)}
      class="stale-chip"
      data-role="stale-target"
      title={
        gettext(
          "This position target is stale: the security was moved or unassigned. It keeps counting under the category it was filed under until re-filed on the Classifications page."
        )
      }
    >
      <%= gettext("stale target") %>
    </span>
    <span
      :if={no_quote?(@position)}
      class="no-quote-chip"
      data-role="no-quote"
      title={gettext("no quote — add a price to get a unit hint")}
    >
      <%= gettext("no quote") %>
    </span>
    <span
      :if={negative_quantity?(@position)}
      class="negative-holding-chip"
      data-role="negative-holding"
      title={
        gettext(
          "The derived holding quantity is negative — likely an unmodeled corporate action from an imported history. Repair the security's transaction history."
        )
      }
    >
      <%= gettext("negative quantity") %>
    </span>
    """
  end

  # Import debris marker (#570): a derived quantity below zero is impossible
  # for a real holding and must not blend into the allocation.
  defp negative_quantity?(%{quantity: %Decimal{} = quantity}),
    do: Decimal.compare(quantity, 0) == :lt

  defp negative_quantity?(_position), do: false

  # Scope-aware not-held chip (fix round): inside a named view "not held"
  # only means "not held in this view"; the plain label is reserved for the
  # Gesamt scope, where it really means not held at all.
  defp not_held_label(nil), do: gettext("not held")
  defp not_held_label(_view_id), do: gettext("not held in this view")

  # A SOLL-only row whose hint cell would stay blank because no quote exists
  # at all (fix round, UAT): quote_date nil distinguishes "no stored quote"
  # from "quote present but unconvertible" (no FX path — no chip, the missing
  # rate is a data-quality concern the FX surfaces own).
  defp no_quote?(position) do
    not position.held and is_nil(position.rebalance_quantity) and
      is_nil(Map.get(position, :quote_date))
  end

  # The Σ header explains a 0% top level that hides a deeper plan (fix round
  # F5): only when no top-level category carries an effective target while
  # deeper categories do.
  defp deep_targets_below?(allocation) do
    deep = Map.get(allocation, :deep_target_sum)

    Decimal.equal?(allocation.top_level_target_sum, 0) and
      not is_nil(deep) and Decimal.compare(deep, 0) == :gt
  end

  # The subcategory-Σ hint only flags a mismatch when the parent actually
  # carries an own weight to compare against (fix round): with no own
  # weight the hint states the children's Σ, and there is nothing to miss.
  defp subcategory_mismatch?(row) do
    not Decimal.equal?(row.target_weight, 0) and
      target_mismatch?(row.child_target_sum, row.target_weight)
  end

  # A position's drift cell renders when the position carries its OWN SOLL
  # (ADR-0030 slice 2a — its drift is actual weight − its target, meaningful
  # even in an otherwise untargeted category), or — for SOLL-less entries —
  # when the category is targeted and a category-share drift exists (the
  # pre-slice behaviour, unchanged).
  defp position_drift_shown?(%{target_weight: %Decimal{}}, _row), do: true

  defp position_drift_shown?(position, row) do
    not Decimal.equal?(row.target_weight, 0) and not is_nil(position.drift_value)
  end

  # The compact text label of the category's position-target badge (UX-DR7:
  # words, never hue alone). Both conditions can hold at once.
  defp category_badge_label(%{conflict: true, has_stale: true}),
    do: gettext("Σ conflict · stale")

  defp category_badge_label(%{conflict: true}), do: gettext("Σ conflict")
  defp category_badge_label(_row), do: gettext("stale target")

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
  # The success line is compact — count plus the local wall-clock time of the
  # run (display-only formatting; domain data stays day-granular).
  defp fx_sync_result_message({:ok, count, synced_at}) do
    ngettext("One rate updated", "%{count} rates updated", count) <>
      " · " <> Calendar.strftime(synced_at, "%H:%M")
  end

  defp fx_sync_result_message(:error), do: rate_sync_error_message()

  defp rate_sync_error_message do
    gettext(
      "Couldn't reach the exchange-rate provider. Please check the connection and try again."
    )
  end

  # -- data quality helpers ----------------------------------------------------

  # Unvalued positions of one honest state (#406): `:no_price` lists names
  # only (there is nothing to show), `:missing_fx` shows each position's
  # known native price with its currency (owner decision 2026-07-31). The
  # count is taken before the display list is shortened, so it stays truthful
  # when names are elided.
  defp unvalued_entries(nil, _reason), do: %{count: 0, names: []}

  defp unvalued_entries(valuation, reason) do
    names =
      valuation.positions
      |> Enum.filter(&(&1.unvalued_reason == reason))
      |> Enum.map(&unvalued_entry_label(&1, reason))
      |> Enum.uniq()

    %{count: length(names), names: shorten_list(names)}
  end

  defp unvalued_entry_label(position, :missing_fx) do
    name = position.security_name || gettext("Unsorted")
    "#{name} (#{Format.decimal(position.latest_price, 2)} #{position.price_currency})"
  end

  defp unvalued_entry_label(position, _reason),
    do: position.security_name || gettext("Unsorted")

  # Negative-holdings debris grouped per security (#570): each entry keeps
  # its negative depot rows and the security's total across all depots, so
  # the report shows both, and links to the transaction history (no repair
  # wizard beyond splits, ADR-0028).
  defp negative_entries(nil), do: []

  defp negative_entries(report) do
    report.rows
    |> Enum.group_by(&{&1.security_id, &1.security_name})
    |> Enum.map(fn {{security_id, security_name}, rows} ->
      %{
        security_id: security_id,
        name: security_name || gettext("Unsorted"),
        depots: rows,
        total: hd(rows).total_quantity
      }
    end)
    |> Enum.sort_by(& &1.name)
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

  # Whether the active view's resolution matches zero accounts (fix round
  # hint). Tolerates valuations without the flag (and the pre-async nil).
  defp matches_no_accounts?(%{matches_no_accounts: true}), do: true
  defp matches_no_accounts?(_valuation), do: false

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

  # A pot whose value is not positive (import debris, #570 review fix) has no
  # drawable angular span: skip the slice — and with it the outer ring and
  # legend entry — instead of laying its healthy members' arcs over the span
  # the Cash slice occupies.
  defp unassigned_node(%{market_value: value}, _roots)
       when not is_struct(value, Decimal),
       do: []

  defp unassigned_node(%{market_value: value} = unassigned, roots) do
    if Decimal.compare(value, 0) == :gt do
      positive_unassigned_node(unassigned, roots)
    else
      []
    end
  end

  defp positive_unassigned_node(%{actual_weight: weight, market_value: value}, roots) do
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

  # No slice was drawn for the pot (non-positive value, #570 review fix):
  # no outer ring either.
  defp unassigned_security_nodes(_unassigned, [], _depth), do: []

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
        # No legend entry for a pot without a drawable slice (non-positive
        # value, #570 review fix) — the data-quality report carries it.
        %{actual_weight: weight, market_value: %Decimal{} = value} ->
          if Decimal.compare(value, 0) == :gt do
            roots ++
              [
                %{
                  name: gettext("Unassigned"),
                  color: @unassigned_color,
                  percent: Format.percent(weight)
                }
              ]
          else
            roots
          end

        _ ->
          roots
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

  # One landing spot for a validated period term (a button string, a year or a
  # range): re-chain the cached analysis instantly, or — while the walk is
  # still computing — remember the choice for the async completion.
  defp apply_period(socket, period) do
    socket = assign(socket, :range_error, false)

    if socket.assigns.analysis do
      # The analysis is cached — re-chaining a period is pure and instant.
      {:ok, performance} = Performance.summarise(socket.assigns.analysis, period)
      {:noreply, assign(socket, period: period, performance: performance)}
    else
      {:noreply, assign(socket, :period, period)}
    end
  end

  # Windows shorter than one year show the non-annualized period MWR
  # (ADR-0034 §2); the window counts its days inclusively, so a full
  # calendar year still reads as annualized IRR.
  defp short_window?(%{start_date: %Date{} = start_date, end_date: %Date{} = end_date}),
    do: Date.diff(end_date, start_date) + 1 < 365

  defp short_window?(_performance), do: false

  defp money_weighted_label(performance) do
    if short_window?(performance), do: gettext("MWR"), else: gettext("IRR")
  end

  # Callers guard with `@performance &&`, so nil never reaches this.
  defp money_weighted_value(performance) do
    if short_window?(performance), do: performance.mwr, else: performance.irr
  end

  # The ⓘ affordance follows the visible card label (review finding): a
  # screen reader must not hear "IRR info" on a card labeled MWR.
  defp money_weighted_info_label(performance) do
    if short_window?(performance), do: gettext("MWR info"), else: gettext("IRR info")
  end

  defp period_label("ytd"), do: gettext("YTD")
  defp period_label("1y"), do: gettext("1Y")
  defp period_label("3y"), do: gettext("3Y")
  defp period_label("5y"), do: gettext("5Y")
  defp period_label("max"), do: gettext("Max")
  defp period_label({:year, year}), do: Integer.to_string(year)
  defp period_label({:range, from, to}), do: "#{from} – #{to}"

  # The years the cached analysis can chain (#563): first walked year through
  # today's, newest first. Empty while the walk still computes.
  defp available_years(%{first_date: %Date{} = first, today: %Date{} = today}),
    do: Enum.to_list(today.year..first.year//-1)

  defp available_years(_analysis), do: []

  # Prefill for the range inputs: the picked range, else the shown period's
  # effective bounds (honest clamping included), else blank.
  defp range_from({:range, from, _to}, _performance), do: from
  defp range_from(_period, %{start_date: %Date{} = start_date}), do: start_date
  defp range_from(_period, _performance), do: nil

  defp range_to({:range, _from, to}, _performance), do: to
  defp range_to(_period, %{end_date: %Date{} = end_date}), do: end_date
  defp range_to(_period, _performance), do: nil

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

  # ADR-0032 §6 provenance: what the shown series contains, stated, so a
  # superseded number is never bare. "Bookings" is the honest unit -- the memo
  # key's version says WHETHER data changed; this says WHAT was included.
  defp stale_series_label(analysis) do
    gettext("Superseded series — %{basis}. Recomputing.",
      basis: series_basis_label(analysis)
    )
  end

  defp series_basis_label(%{basis: basis, today: today}) do
    ngettext(
      "One booking through %{last}, computed %{at}, as of %{date}",
      "%{count} bookings through %{last}, computed %{at}, as of %{date}",
      basis.booking_count,
      last: Format.date(basis.last_booking_date),
      at: Calendar.strftime(basis.computed_at, "%Y-%m-%d %H:%M UTC"),
      date: Format.date(today)
    )
  end

  defp series_basis_label(%{today: today}) do
    gettext("as of %{date}", date: Format.date(today))
  end
end
