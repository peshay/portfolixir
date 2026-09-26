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

  alias Portfolixir.Buckets
  alias Portfolixir.Catalog.DataQuality
  alias Portfolixir.Classifications
  alias Portfolixir.Fx.RateSync
  alias Portfolixir.Input.BoundedDate
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Allocation
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.Performance.Benchmark
  alias Portfolixir.Portfolios.PricingContext
  alias Portfolixir.Portfolios.Targets
  alias Portfolixir.Portfolios.Valuation
  alias Portfolixir.Settings
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.BenchmarkScope
  alias PortfolixirWeb.ClassificationName
  alias PortfolixirWeb.ColumnPicker
  alias PortfolixirWeb.Components.SecurityChart
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.LiveParam
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
  # The drift-threshold steps the allocation table offers, in percentage
  # points. 5 pp is the dashboard's own attention threshold, so the alert list
  # and the filtered table agree on what "needs attention" means; 1 and 2 pp
  # are for a plan steered more tightly than that. A fixed set, because the
  # value round-trips through the URL and a whitelist beats parsing.
  # #814: the human half of the holdings projection's `fields=` sparse
  # fieldset. The columns are the API's own (`Ledger.holdings_for_portfolio/1`
  # through `JSON.holding_fields/0`), so the picker offers the figures an
  # agent reads rather than a second calculation — one projection, two
  # surfaces. The picker left with the Transactions holdings panel in #803;
  # this is where the review put the holdings.
  @holdings_column_defaults ["depot", "security", "quantity"]

  # The one place the key is written: the hook restores from the table's
  # `data-storage-key` and the handler pushes to it, and a picker that only
  # ever reads the key is a preference that silently never persists.
  @holdings_storage_key "wealth.holdings.columns"

  defp holdings_storage_key, do: @holdings_storage_key

  @holdings_column_keys @holdings_column_defaults ++
                          [
                            "isin",
                            "wkn",
                            "currency",
                            "avg_cost",
                            "latest_price",
                            "market_value",
                            "unrealized_pnl_abs",
                            "unrealized_pnl_pct"
                          ]

  @drift_steps ["1", "2", "5"]
  @unpriced_names_shown 6

  @impl true
  def mount(params, session, socket) do
    # ADR-0050 §12: a remembered or linked benchmark naming a security a
    # merge took away redirects to the same page naming its survivor, so the
    # BenchmarkScope plug remembers the survivor, and the page says so once.
    case merged_benchmarks(socket.assigns[:active_benchmark_selectors]) do
      [] ->
        mount_page(params, session, socket)

      merged ->
        selectors = socket.assigns[:active_benchmark_selectors]
        {:ok, redirect(socket, to: survivor_benchmark_path(params, selectors, merged))}
    end
  end

  defp mount_page(params, _session, socket) do
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
      |> assign(:view_gone_notice, false)
      |> assign(:classification_gone_notice, false)
      |> assign(:benchmark_merged, benchmark_merged_notes(params, socket))
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
          |> assign(:range_error, nil)
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
          # ADR-0046 §4: the remembered benchmark selection, resolved against
          # the catalog; the comparisons follow the performance summary.
          |> assign(:benchmarks, resolve_benchmarks(socket.assigns[:active_benchmark_selectors]))
          |> assign(:benchmark_options, Portfolixir.Catalog.list_securities(is_benchmark: true))
          |> assign(:comparisons, [])
          |> assign(:selected_segment, nil)
          |> assign(:expanded_categories, MapSet.new())
          |> assign(:allocation_mode, param_allocation_mode(params))
          |> assign(:min_drift_pp, param_min_drift_pp(params))
          |> assign(:flat_sort, {:drift, :desc})
          |> assign(:holdings_columns, @holdings_column_defaults)
          |> assign(:column_picker_open?, false)
          |> assign(:holding_rows, holding_rows(portfolio))
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
    min_drift_pp = param_min_drift_pp(params)

    current_path =
      case socket.assigns.wealth_tab do
        :allocation ->
          allocation_current_path(
            params["view"],
            classification_id,
            allocation_mode,
            min_drift_pp
          )

        # Other tabs have no allocation controls; keep mount's tab+view path.
        _other ->
          socket.assigns.current_path
      end

    socket =
      socket
      |> assign(:allocation_mode, allocation_mode)
      |> assign(:min_drift_pp, min_drift_pp)
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
        present_but_stale?(params["alloc"], allocation_mode_param(socket.assigns.allocation_mode)) or
        present_but_stale?(params["drift"], socket.assigns.min_drift_pp)

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
         {:ok, parsed} <- LiveParam.fetch_id(id),
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

  # Reads the drift threshold from the URL. The chips offer a fixed set of
  # steps and the URL carries the chosen one verbatim, so parsing is a
  # whitelist match rather than a Decimal parse of arbitrary input — a garbled
  # or removed value degrades to "no threshold" (show everything), never a
  # crash and never a silently different filter.
  defp param_min_drift_pp(%{"drift" => pp}) when pp in @drift_steps, do: pp
  defp param_min_drift_pp(_params), do: nil

  defp drift_steps, do: @drift_steps

  # The rows a threshold keeps, for the summary line's count. Same predicate
  # as the table itself, so the number can never disagree with the rows.
  defp threshold_rows(categories, pp),
    do: Enum.filter(categories, &Allocation.drift_at_least?(&1, min_drift_decimal(pp)))

  # The chips speak percentage points because that is how a plan is read
  # ("5 pp off target"); the predicate — and the API's `min_drift=` — speak the
  # weight fraction the drift itself is in. One conversion, here.
  #
  # Which drift: `drift_weight`, the one the Drift column and the dashboard's
  # attention list use. Under ADR-0040 that is measured against the plan
  # renormalised to the allocated portion, so on a plan summing to 83 % the pp
  # a chip filters by is NOT what subtracting the table's raw Target column
  # from its Actual column gives. Deliberate: one number across chips, column,
  # dashboard and API beats a chip that agrees with the columns and with
  # nothing else.
  defp min_drift_decimal(nil), do: nil

  defp min_drift_decimal(pp) when is_binary(pp),
    do: Decimal.div(Decimal.new(pp), 100)

  # The category rows the drift table renders. Without a threshold that is the
  # tree as expanded; with one it is the flat set of rows meeting it, using the
  # SAME predicate as the API's `min_drift=` filter so the two surfaces cannot
  # select different categories. A filtered row is shown regardless of its
  # ancestors' expansion — its parent may well be under the threshold and gone.
  defp visible_category_rows(categories, nil, expanded, parent_map),
    do: Enum.filter(categories, &branch_expanded?(&1.parent_id, expanded, parent_map))

  defp visible_category_rows(categories, %Decimal{} = min_drift, _expanded, _parent_map),
    do: Enum.filter(categories, &Allocation.drift_at_least?(&1, min_drift))

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
  defp allocation_current_path(view, classification_id, allocation_mode, min_drift_pp) do
    pairs =
      [{"tab", "allocation"}] ++
        view_pairs(view) ++
        [
          {"classification", Integer.to_string(classification_id)},
          {"alloc", allocation_mode_param(allocation_mode)}
        ] ++ drift_pairs(min_drift_pp)

    "/portfolio?" <> URI.encode_query(pairs)
  end

  # Only a chosen threshold rides the URL: the unfiltered table is the default,
  # and a default in the address bar is noise a shared link carries forever.
  defp drift_pairs(pp) when is_binary(pp), do: [{"drift", pp}]
  defp drift_pairs(_pp), do: []

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
        serve_previous_summary(socket, previous)

      _none ->
        socket
        |> assign(:performance_stale, false)
        |> assign(:performance_failed, false)
    end
  end

  # A superseded series that cannot be summarised is not served: the page
  # waits for the fresh one instead (E25 S4, G12).
  defp serve_previous_summary(socket, previous) do
    case Performance.summarise(previous, socket.assigns.period) do
      {:ok, performance} ->
        socket
        |> assign(:analysis, previous)
        |> assign(:performance, performance)
        |> assign(:performance_stale, true)
        |> assign(:performance_failed, false)
        |> assign_comparisons()

      {:error, _reason} ->
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

  # A summary the walk cannot give is the failed-performance state, the same
  # one a dead recomputation lands in, never a crash (E25 S4, G12).
  def handle_async(:performance, {:ok, analysis}, socket) do
    case Performance.summarise(analysis, socket.assigns.period) do
      {:ok, performance} ->
        {:noreply,
         socket
         |> assign(
           analysis: analysis,
           performance: performance,
           performance_stale: false,
           performance_failed: false
         )
         |> assign_comparisons()}

      {:error, _reason} ->
        {:noreply, assign(socket, performance_failed: true)}
    end
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
          <p><%= gettext("Wealth needs a depot with a cash account.") %></p>
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
        <%!-- Load failure is a page-level condition, not an action result:
             one data note in flow, announced from a region that exists on
             load, no floating toast and no timer (#566, UX-DR17). --%>
        <div id="portfolio-load-error" role="status">
          <%= if @error do %>
            <AppShell.data_note severity={:problem}><%= @error %></AppShell.data_note>
          <% end %>
        </div>

        <AppShell.area_tabs tabs={AppShell.wealth_tabs(@wealth_tab)} />

        <%!-- Issue 790: a control row sits inside the content grid, with the
             section's horizontal padding and none of its band. --%>
        <div class="workspace-section workspace-section--controls">
          <.view_switcher
            current_path={@current_path}
            views={@views}
            active_view={@active_view}
            planned_view_ids={@planned_view_ids}
            show_default_control={true}
            default_view_id={@default_view_id}
          />
        </div>

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
            "This view matches no accounts — its included buckets are empty or no longer assigned. Edit the view under Views or tag accounts into its buckets."
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
              "The one-time migration turned each portfolio into a bucket and a view of the same name — fully editable, nothing was deleted."
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

        <%!-- #797 (review C1, variant A): two tiers — three lead figures at
             full size, four supporting figures at half height, the currency
             as a small suffix so a value never wraps, a card's second figure
             on its sub-line. Holdings only: the Allocation tab carries one
             summary line linking back here instead of repeating the band. --%>
        <%= if @wealth_tab == :holdings do %>
        <section class="workspace-section kpi-band" aria-label={gettext("Wealth key figures")}>
          <div class="kpi-band__lead">
            <article id="kpi-total" class="stat stat--lead">
              <span><%= gettext("Total incl. cash") %></span>
              <strong :if={@valuation}>
                <span
                  id="count-kpi-total"
                  class="count-up"
                  phx-hook="CountUp"
                  data-count-to={Decimal.to_string(@valuation.total_with_cash, :normal)}
                  data-decimals="2"
                ><span data-count-digits><%= Format.money(@valuation.total_with_cash) %></span></span><small class="value-suffix"><%= @valuation.base_currency %></small>
              </strong>
              <strong
                :if={is_nil(@valuation)}
                class="value-slot-pending"
                aria-busy="true"
                data-waits="valuation"
              >
                <%!-- #723: a sub-second figure (ADR-0039 measurement) keeps
                     the silent skeleton — the cue is for the seconds class. --%>
                <span class="value-skeleton" aria-hidden="true"></span>
              </strong>
              <small :if={@valuation} class="stat__sub" data-role="total-composition">
                <%= gettext("Securities") %> <b><%= Format.money(@valuation.total_value) %></b>
                · <%= gettext("Cash") %> <b><%= Format.money(@valuation.total_cash) %></b>
              </small>
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
            <article id="kpi-ttwror" class="stat stat--lead" role="group" aria-describedby="tip-ttwror">
              <div class="stat__head">
                <span><%= gettext("TTWROR") %> (<%= period_label(@period) %>)</span>
                <details class="metric-tooltip metric-tooltip--inline">
                  <summary aria-label={gettext("TTWROR info")}>ⓘ</summary>
                  <p id="tip-ttwror" role="tooltip">
                    <%= gettext("TTWROR — time-weighted return for the selected period (not annualized). Deposits and withdrawals are neutralised so only investment performance counts.") %>
                  </p>
                </details>
              </div>
              <%!-- Signed metric: gain/loss colour plus sign, never the accent
                   (UX-DR7, issue 637). --%>
              <strong :if={@performance} class={perf_sign_class(@performance.ttwror)}>
                <%= signed_percent(@performance.ttwror) %>%
              </strong>
              <strong
                :if={is_nil(@performance) and not @performance_failed}
                class="value-slot-pending"
                aria-busy="true"
                data-waits="performance"
              >
                <span class="value-skeleton" aria-hidden="true"></span>
                <span class="recomputing-cue"><span class="spinner"></span> <%= gettext("computing") %></span>
              </strong>
              <strong :if={is_nil(@performance) and @performance_failed} class="stat-empty">—</strong>
              <%!-- The absolute result beside the rate: (end − start) − net
                   external flows, so a deposit never reads as performance. --%>
              <small :if={@performance} class="stat__sub" data-role="period-gain">
                <b class={perf_sign_class(period_value_gain(@performance))}><%= signed_money(
                    period_value_gain(@performance)
                  ) %></b>
                <%= @performance.base_currency %> <%= gettext("in the period") %>
              </small>
            </article>
            <article id="kpi-irr" class="stat stat--lead" role="group" aria-describedby="tip-irr">
              <div class="stat__head">
                <span><%= money_weighted_label(@performance) %> (<%= period_label(@period) %>)</span>
                <details class="metric-tooltip metric-tooltip--inline">
                  <summary aria-label={money_weighted_info_label(@performance)}>ⓘ</summary>
                  <p id="tip-irr" role="tooltip">
                    <%= gettext("IRR — money-weighted return, annualized. Discounts the timing and size of cashflows over the period. Windows shorter than a year show the period MWR — the same figure, not annualized.") %>
                  </p>
                </details>
              </div>
              <strong
                :if={@performance && money_weighted_value(@performance)}
                class={perf_sign_class(money_weighted_value(@performance))}
              >
                <%= signed_percent(money_weighted_value(@performance)) %>%
              </strong>
              <strong
                :if={@performance && is_nil(money_weighted_value(@performance))}
                class="stat-empty"
              >
                —
              </strong>
              <strong
                :if={is_nil(@performance) and not @performance_failed}
                class="value-slot-pending"
                aria-busy="true"
                data-waits="performance"
              >
                <span class="value-skeleton" aria-hidden="true"></span>
                <span class="recomputing-cue"><span class="spinner"></span> <%= gettext("computing") %></span>
              </strong>
              <strong :if={is_nil(@performance) and @performance_failed} class="stat-empty">—</strong>
              <small
                :if={@performance && money_weighted_value(@performance)}
                class="stat__sub"
                data-role="money-weighted-basis"
              >
                <%= money_weighted_basis(@performance) %>
              </small>
            </article>
          </div>
          <div class="kpi-band__support">
            <article id="kpi-securities" class="stat stat--compact">
              <span><%= gettext("Securities") %></span>
              <strong :if={@valuation}>
                <span
                  id="count-kpi-securities"
                  class="count-up"
                  phx-hook="CountUp"
                  data-count-to={Decimal.to_string(@valuation.total_value, :normal)}
                  data-decimals="2"
                ><span data-count-digits><%= Format.money(@valuation.total_value) %></span></span><small class="value-suffix"><%= @valuation.base_currency %></small>
              </strong>
              <strong
                :if={is_nil(@valuation)}
                class="value-slot-pending"
                aria-busy="true"
                data-waits="valuation"
              >
                <span class="value-skeleton" aria-hidden="true"></span>
              </strong>
            </article>
            <article id="kpi-cash" class="stat stat--compact" role="group" aria-describedby="tip-cash-quote">
              <div class="stat__head">
                <span><%= gettext("Cash quote") %></span>
                <details class="metric-tooltip metric-tooltip--inline">
                  <summary aria-label={gettext("Cash quote info")}>ⓘ</summary>
                  <p id="tip-cash-quote" role="tooltip">
                    <%= gettext("Cash quote: deployable cash ÷ (securities value + deployable cash). Reserve and credit-line accounts are excluded.") %>
                  </p>
                </details>
              </div>
              <strong :if={@valuation}><%= Format.percent(@valuation.cash_quote) %>%</strong>
              <strong
                :if={is_nil(@valuation)}
                class="value-slot-pending"
                aria-busy="true"
                data-waits="valuation"
              >
                <span class="value-skeleton" aria-hidden="true"></span>
              </strong>
              <small :if={@valuation} class="stat__sub" data-role="cash-amount">
                <b><%= Format.money(@valuation.total_cash) %></b> <%= @valuation.base_currency %> <%= gettext(
                  "cash"
                ) %>
              </small>
            </article>
            <%!-- Invested capital as two labeled numbers — opening value and
                 net period flows, never one merged figure (ADR-0034 §3). --%>
            <article id="kpi-invested" class="stat stat--compact" role="group" aria-describedby="tip-invested">
              <div class="stat__head">
                <span>
                  <%= gettext("Opening value") %> · <%= gettext("net flows") %> (<%= period_label(
                    @period
                  ) %>)
                </span>
                <details class="metric-tooltip metric-tooltip--inline">
                  <summary aria-label={gettext("Invested capital info")}>ⓘ</summary>
                  <p id="tip-invested" role="tooltip">
                    <%= gettext("Invested capital for the period: value at the period start plus net external flows (deposits minus withdrawals, deliveries at transaction value). Basis of the wealth multiple.") %>
                  </p>
                </details>
              </div>
              <strong :if={@performance}>
                <%= Format.money(@performance.start_value) %><small class="value-suffix"><%= @performance.base_currency %></small>
              </strong>
              <strong
                :if={is_nil(@performance) and not @performance_failed}
                class="value-slot-pending"
                aria-busy="true"
                data-waits="performance"
              >
                <span class="value-skeleton" aria-hidden="true"></span>
                <span class="recomputing-cue"><span class="spinner"></span> <%= gettext("computing") %></span>
              </strong>
              <strong :if={is_nil(@performance) and @performance_failed} class="stat-empty">—</strong>
              <small :if={@performance} class="stat__sub" data-role="net-flows">
                <%= gettext("net flows") %>
                <b class={perf_sign_class(@performance.net_external_flows)}><%= Format.signed_decimal(
                    @performance.net_external_flows,
                    2
                  ) %></b> <%= @performance.base_currency %>
              </small>
            </article>
            <article id="kpi-multiple" class="stat stat--compact" role="group" aria-describedby="tip-multiple">
              <div class="stat__head">
                <span><%= gettext("Wealth multiple") %> (<%= period_label(@period) %>)</span>
                <details class="metric-tooltip metric-tooltip--inline">
                  <summary aria-label={gettext("Wealth multiple info")}>ⓘ</summary>
                  <p id="tip-multiple" role="tooltip">
                    <%= gettext("Wealth multiple — end value ÷ invested capital: what the money put in has become. n/a when net invested capital is zero or negative.") %>
                  </p>
                </details>
              </div>
              <strong :if={@performance && @performance.wealth_multiple}>
                ×<%= Format.decimal(@performance.wealth_multiple, 2) %>
              </strong>
              <strong :if={@performance && is_nil(@performance.wealth_multiple)} class="stat-empty">
                <%= gettext("n/a") %>
              </strong>
              <strong
                :if={is_nil(@performance) and not @performance_failed}
                class="value-slot-pending"
                aria-busy="true"
                data-waits="performance"
              >
                <span class="value-skeleton" aria-hidden="true"></span>
                <span class="recomputing-cue"><span class="spinner"></span> <%= gettext("computing") %></span>
              </strong>
              <strong :if={is_nil(@performance) and @performance_failed} class="stat-empty">—</strong>
            </article>
          </div>
          <%!-- ADR-0046 §4: the comparison block next to TTWROR/IRR — one row
               per active benchmark, the savings-plan delta as the figure with
               the bought-once and IRR pairs beside it. The definition lives
               in the ⓘ (UX-DR11); the covered window is a basis line. --%>
          <article
            :if={@benchmarks != []}
            id="kpi-benchmark"
            class="stat stat--wide"
            role="group"
            aria-describedby="tip-benchmark"
          >
            <span><%= gettext("Benchmark comparison") %> (<%= period_label(@period) %>)</span>
            <ul :if={@comparisons != []} class="benchmark-rows" data-role="benchmark-rows">
              <li
                :for={{comparison, index} <- Enum.with_index(@comparisons, 1)}
                class="benchmark-row"
                data-role="benchmark-row"
              >
                <span class="benchmark-row__name">
                  <span
                    class={["chart-legend__swatch", "chart-benchmark-#{index}"]}
                    aria-hidden="true"
                  >
                  </span>
                  <%= comparison_name(comparison.benchmark) %>
                </span>
                <strong
                  :if={comparison.savings_plan.end_value_delta}
                  class={perf_sign_class(comparison.savings_plan.end_value_delta)}
                  data-role="benchmark-delta"
                >
                  <span class="benchmark-row__figure-label"><%= gettext("savings plan") %>:</span>
                  <%= signed_money(comparison.savings_plan.end_value_delta) %> <%= comparison.base_currency %>
                </strong>
                <strong :if={is_nil(comparison.savings_plan.end_value_delta)} data-role="benchmark-delta">
                  <span class="benchmark-row__figure-label"><%= gettext("savings plan") %>:</span> —
                </strong>
                <span class="benchmark-row__detail">
                  <span data-role="benchmark-bought-once">
                    <%= gettext("bought once") %>: <%= return_pair(
                      comparison.bought_once.portfolio_ttwror,
                      comparison.bought_once.benchmark_return
                    ) %>
                  </span>
                  <span class="perf-badge-sep">·</span>
                  <span data-role="benchmark-irr"><%= money_weighted_pair(comparison) %></span>
                </span>
                <span
                  :if={comparison.excluded_flows != []}
                  class="benchmark-row__coverage hint"
                  data-role="benchmark-coverage"
                >
                  <%= coverage_note(comparison) %>
                </span>
              </li>
            </ul>
            <strong
              :if={@comparisons == [] and is_nil(@performance) and not @performance_failed}
              class="value-slot-pending"
              aria-busy="true"
              data-waits="performance"
            >
              <span class="value-skeleton" aria-hidden="true"></span>
              <span class="recomputing-cue"><span class="spinner"></span> <%= gettext("computing") %></span>
            </strong>
            <strong :if={@comparisons == [] and (@performance || @performance_failed)}>—</strong>
            <details class="metric-tooltip">
              <summary aria-label={gettext("Benchmark comparison info")}>ⓘ</summary>
              <p id="tip-benchmark" role="tooltip">
                <%= gettext(
                  "Savings plan: the period's opening value and every deposit or withdrawal invested into the benchmark on the same days at that day's price, without fees or taxes; the figure is the actual end value minus that. Bought once: the period's TTWROR against the benchmark held throughout. Pairs read portfolio vs benchmark; flows before the benchmark's first priced day enter through the opening value."
                ) %>
              </p>
            </details>
          </article>
        </section>
        <% else %>
        <%!-- The Allocation tab begins with the allocation; what it needs from
             the band is the reference value and the cash quote — one line,
             with a link back to Holdings that keeps the picked view (#797). --%>
        <section
          class="workspace-section kpi-summary"
          aria-label={gettext("Wealth key figures")}
          aria-busy={summary_busy(@valuation, @performance, @performance_failed)}
          data-role="kpi-summary"
        >
          <span class="kpi-summary__item">
            <%= gettext("Total incl. cash") %>
            <strong :if={@valuation}>
              <%= Format.money(@valuation.total_with_cash) %> <%= @valuation.base_currency %>
            </strong>
            <span :if={is_nil(@valuation)} class="value-skeleton" aria-hidden="true"></span>
          </span>
          <span class="kpi-summary__item">
            <%= gettext("Cash quote") %>
            <strong :if={@valuation}><%= Format.percent(@valuation.cash_quote) %>%</strong>
            <span :if={is_nil(@valuation)} class="value-skeleton" aria-hidden="true"></span>
          </span>
          <span class="kpi-summary__item">
            <%= gettext("TTWROR") %> <%= period_label(@period) %>
            <strong :if={@performance} class={perf_sign_class(@performance.ttwror)}>
              <%= signed_percent(@performance.ttwror) %>%
            </strong>
            <span
              :if={is_nil(@performance) and not @performance_failed}
              class="value-skeleton"
              aria-hidden="true"
            >
            </span>
            <strong :if={is_nil(@performance) and @performance_failed} class="stat-empty">—</strong>
          </span>
          <a class="kpi-summary__link" href={holdings_path(@current_path)}>
            <%= gettext("All key figures → Holdings") %>
          </a>
        </section>
        <% end %>

        <%!-- Wealth tabs (ADR-0022): Holdings carries the performance chart,
             data quality and cash; Allocation & targets carries the sunburst
             and drift table. KPIs and the view switcher head both. --%>
        <%= if @wealth_tab == :holdings do %>
          <.data_quality
            valuation={@valuation}
            analysis={@analysis}
            negative={@negative_report}
            fx_syncing={@fx_syncing}
            fx_sync_flash={@fx_sync_flash}
            fx_sync_result={@fx_sync_result}
          />
        <% end %>

        <%= if @wealth_tab == :holdings do %>
        <section id="portfolio-performance" class="workspace-section">
          <header class="section-head">
            <h2><%= gettext("Performance") %></h2>
            <%!-- Issue 669: the series toggle and the period tokens are the
                 app's one segmented control ({components.selected-segment});
                 the previous-year re-chain and the custom range live behind
                 a disclosure, never as permanent chrome
                 ({components.period-control}). --%>
            <div class="section-head-controls">
              <div
                class="segmented-control"
                data-role="chart-series"
                role="group"
                aria-label={gettext("Chart series")}
              >
                <button
                  type="button"
                  class={["segmented-control__option", @chart_mode == "ttwror" && "is-active"]}
                  phx-click="set_chart_mode"
                  phx-value-mode="ttwror"
                  aria-pressed={to_string(@chart_mode == "ttwror")}
                >
                  <%= gettext("% (TTWROR)") %>
                </button>
                <button
                  type="button"
                  class={["segmented-control__option", @chart_mode == "value" && "is-active"]}
                  phx-click="set_chart_mode"
                  phx-value-mode="value"
                  aria-pressed={to_string(@chart_mode == "value")}
                >
                  <%= gettext("Value (%{currency})", currency: display_currency(assigns)) %>
                </button>
              </div>
              <div
                class="segmented-control"
                data-role="period-tokens"
                role="group"
                aria-label={gettext("Period")}
              >
                <%= for period <- Performance.periods() do %>
                  <button
                    type="button"
                    class={["segmented-control__option", period == @period && "is-active"]}
                    phx-click="select_period"
                    phx-value-period={period}
                    aria-pressed={to_string(period == @period)}
                  >
                    <%= period_label(period) %>
                  </button>
                <% end %>
                <%!-- #721 (D5): an applied custom range shows itself here,
                     in the same active treatment as a preset token — the
                     control must answer "what am I looking at". --%>
                <button
                  :if={custom_period?(@period)}
                  type="button"
                  class="segmented-control__option is-active"
                  data-role="custom-period-chip"
                  aria-pressed="true"
                >
                  <%= custom_period_label(@period) %>
                </button>
              </div>
              <%!-- #801 (review C5, variant A): the custom range is a popover
                   on its trigger — from/to in one row, the walked years as
                   chips, Cancel and Apply — so the heading and the chart
                   stay put; Esc closes it and returns focus; an applied year
                   or range closes it through the close-popover event. --%>
              <details
                id="period-custom"
                class="period-disclosure"
                data-role="period-custom"
                phx-hook="PopoverDisclosure"
              >
                <summary class="disclosure-summary">
                  <AppShell.icon name={:chevron_right} size={12} class="disclosure-chevron" />
                  <%= gettext("Custom range…") %>
                </summary>
                <div class="period-disclosure__body period-popover">
                  <%!-- #721 (D5): a labelled pair that validates as a
                       range — the violation lands on the field that can fix
                       it, never on a silently empty chart. --%>
                  <form class="period-range" phx-submit="select_range" data-role="period-range">
                    <div class="period-range__pair">
                      <div class="period-range__field">
                        <label for="performance-from"><%= gettext("From") %></label>
                        <input
                          type="text"
                          placeholder="YYYY-MM-DD"
                          pattern="[0-9]{4}-[0-9]{2}-[0-9]{2}"
                          maxlength="10"
                          id="performance-from"
                          name="from"
                          value={range_from(@period, @performance)}
                          aria-invalid={@range_error == :from && "true"}
                          aria-describedby={@range_error == :from && "performance-range-error"}
                        />
                      </div>
                      <span class="period-range__dash" aria-hidden="true">–</span>
                      <div class="period-range__field">
                        <label for="performance-to"><%= gettext("To") %></label>
                        <input
                          type="text"
                          placeholder="YYYY-MM-DD"
                          pattern="[0-9]{4}-[0-9]{2}-[0-9]{2}"
                          maxlength="10"
                          id="performance-to"
                          name="to"
                          value={range_to(@period, @performance)}
                          aria-invalid={@range_error in [:to, :order] && "true"}
                          aria-describedby={@range_error in [:to, :order] && "performance-range-error"}
                        />
                      </div>
                    </div>
                      <p
                      :if={@range_error}
                      id="performance-range-error"
                      class="hint"
                      data-role="range-error"
                      role="alert"
                      >
                      <%= range_error_message(@range_error) %>
                      </p>
                    <%!-- #563: a single previous year is a pure re-chain of
                         the cached analysis, exactly like the buttons — no
                         new walk. --%>
                    <div
                      :if={available_years(@analysis) != []}
                      class="period-years"
                      data-role="period-year"
                      role="group"
                      aria-label={gettext("Year")}
                    >
                      <button
                        :for={year <- available_years(@analysis)}
                        type="button"
                        class={["filter-chip", @period == {:year, year} && "is-active"]}
                        aria-pressed={to_string(@period == {:year, year})}
                        phx-click="select_year"
                        phx-value-year={year}
                      >
                        <%= year %>
                      </button>
                    </div>
                    <div class="period-popover__foot">
                      <button
                        type="button"
                        id="period-custom-cancel"
                        class="button-ghost"
                        phx-click="cancel_period_popover"
                      >
                        <%= gettext("Cancel") %>
                      </button>
                      <button type="submit" class="button-primary"><%= gettext("Apply") %></button>
                    </div>
                  </form>
                </div>
              </details>
              <%!-- ADR-0046 §4: the benchmark selection is explicit per
                   request — a plain GET form the BenchmarkScope plug
                   remembers in the session and a cookie, like the active
                   view. Up to two, the same disclosure the custom range
                   uses ({components.period-control}). --%>
              <details class="period-disclosure" data-role="benchmark-picker">
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
                  action="/portfolio"
                  class="period-disclosure__body benchmark-form"
                  data-role="benchmark-form"
                >
                  <%!-- The empty entry marks an explicit choice, so a form
                       submitted with nothing ticked clears the selection. --%>
                  <input type="hidden" name="benchmark[]" value="" />
                  <label :for={option <- @benchmark_options} class="benchmark-form__option">
                    <input
                      type="checkbox"
                      name="benchmark[]"
                      value={"security:#{option.id}"}
                      checked={benchmark_selected?(@benchmarks, option)}
                    />
                    <%= option.name %>
                  </label>
                  <span :if={@benchmark_options == []} class="hint" data-role="benchmark-none">
                    <%= gettext("No benchmark securities yet — mark one on the Securities page.") %>
                  </span>
                  <label class="benchmark-form__rate" for="benchmark-rate">
                    <%= gettext("Fixed rate % p.a.") %>
                  </label>
                  <input
                    type="number"
                    id="benchmark-rate"
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
            </div>
          </header>
          <%!-- #563: a backwards or unparsable range is refused with a terse
               note; the shown period keeps. --%>
          <%!-- ADR-0032 §6: a superseded series never renders unlabelled. The
               banner names the data it CONTAINS (booking count, newest booking,
               compute time), not just its age; a failed recomputation flips to
               an error state instead of letting the old number settle. --%>
          <%!-- ADR-0050 §12 (board 13): the benchmark link named a security
               a merge took away; the page compares with its survivor and
               says so once, until the next navigation or the dismiss. --%>
          <div :if={@benchmark_merged != []} class="inline-result" role="status">
            <AppShell.data_note severity={:note} data-role="benchmark-merged">
              <%= for note <- @benchmark_merged do %>
                <%= gettext(
                  "The benchmark named a security that was merged into “%{name}” on %{date}; the comparison now uses it.",
                  name: note.name,
                  date: Format.date(note.merged_on)
                ) %>
              <% end %>
              <button
                type="button"
                class="inline-result__dismiss"
                phx-click="dismiss_benchmark_merged"
                aria-label={gettext("Dismiss")}
                title={gettext("Dismiss")}
              >
                &times;
              </button>
            </AppShell.data_note>
          </div>
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
          <%!-- A cold-start failure has no cached series to label — without
               this the KPI slots would claim "computing" forever. --%>
          <p
            :if={@performance_failed and is_nil(@analysis)}
            class="alert-error"
            role="alert"
            data-role="performance-failed"
          >
            <%= gettext("Computation failed. Reload retries.") %>
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
              summary={table_summary(@performance.series)}
              mode={@chart_mode}
              currency={@performance.base_currency}
              overlays={benchmark_overlays(@chart_mode, @comparisons, @performance.series)}
            />
            <%!-- UX-DR26: a deliberate limit is stated where the overlay is
                 missing — a rebased return has no € axis. --%>
            <p
              :if={@chart_mode == "value" and @benchmarks != []}
              class="hint"
              data-role="benchmark-value-hint"
            >
              <%= gettext("Benchmarks are drawn in the %% (TTWROR) view only — they have no value in %{currency}.",
                currency: @performance.base_currency
              ) %>
            </p>
            <%!-- UX-DR11 (Sprint 5 Lane D, decided outcome: split, then
                 delete half): the TTWROR definition lives ONLY in the
                 kpi-ttwror ⓘ tooltip; the chart keeps the period basis. --%>
            <p :if={@performance.start_date} class="hint" data-role="performance-basis">
              <%= @performance.start_date %> – <%= @performance.end_date %>
              <%!-- ADR-0039 C4 (FR-1 property 3): a served series is never
                   silent about freshness. For a durable value the compute
                   instant can predate the mount — data unchanged since. --%>
              <span :if={@performance.as_of} data-role="performance-as-of">
                · <%= gettext("computed %{at}",
                  at: Calendar.strftime(@performance.as_of, "%Y-%m-%d %H:%M UTC")
                ) %>
              </span>
            </p>
            <%!-- ADR-0024 modification 4: bucket membership applies
                 retroactively, so a view-scoped series is labelled with its
                 semantics instead of pretending temporal membership. This is
                 a basis line (UX-DR11 inventory), not a definition — no ⓘ. --%>
            <p :if={@active_view} class="hint" data-role="composition-label">
              <%= gettext("Composition as of today") %> —
              <%= gettext("the view's current bucket membership is applied to the whole history.") %>
            </p>
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
              <%!-- #875: the segmented group ({components.selected-segment}),
                   so the two states look different, not only sound different. --%>
              <div class="segmented-control" role="group" aria-label={gettext("Allocation view")}>
                <button
                  type="button"
                  data-role="allocation-mode-tree"
                  class={["segmented-control__option", @allocation_mode == :tree && "is-active"]}
                  phx-click="set_allocation_mode"
                  phx-value-mode="tree"
                  aria-pressed={to_string(@allocation_mode == :tree)}
                >
                  <%= gettext("Tree") %>
                </button>
                <button
                  type="button"
                  data-role="allocation-mode-flat"
                  class={["segmented-control__option", @allocation_mode == :flat && "is-active"]}
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
                      <%= ClassificationName.display(classification) %>
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
            <%!-- The chart's basis line (issue 793, Part 4 rule 9): the plan
                 with its top-level Σ — the sentence that floated above the
                 chart, folded in — the view and the as-of date. A 0% top
                 level over a plan steered deeper in the tree is explained,
                 not left as a contradiction (fix round). --%>
            <p class="summary-basis allocation-basis" data-role="allocation-basis">
              <%= if @allocation.has_plan do %>
                <%= gettext("Plan on %{classification}",
                  classification: allocation_tree_name(@allocation)
                ) %>
                <%!-- #875: the warning colour only above 100 % (ADR-0040 §3,
                     DESIGN.md D3); a plan that allocates less says what its
                     drift measures against (§2) — the Σ before it is that
                     allocated portion. --%>
                · <span
                  class={["target-sum", plan_overshoot(@allocation) && "is-target-mismatch"]}
                  data-role="target-sum-top-level"
                >
                  <%= gettext("Σ target top level:") %>
                  <%= Format.percent(@allocation.top_level_target_sum) %>%
                  <%= if deep_targets_below?(@allocation) do %>
                    — <%= gettext("targets deeper in the tree:") %>
                    <%= Format.percent(@allocation.deep_target_sum) %>%
                  <% end %>
                  <span
                    :if={Map.get(@allocation, :drift_basis) == "allocated_portion"}
                    data-role="drift-basis"
                  >
                    — <%= gettext("drift against the allocated portion") %>
                  </span>
                </span>
              <% else %>
                <%= gettext("Actual allocation on %{classification}",
                  classification: allocation_tree_name(@allocation)
                ) %>
              <% end %>
              · <%= gettext("View %{name}", name: active_view_name(@active_view)) %>
              · <%= gettext("as of %{date}", date: Format.date(Portfolixir.Clock.today())) %>
            </p>
            <%= if not @allocation.has_plan do %>
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
                <div class="sunburst-figure">
                  <.allocation_sunburst segments={sunburst_segments(@allocation)} />
                  <.sunburst_centre centre={sunburst_centre(@selected_segment, @allocation)} />
                </div>
              </div>
              <ul class="donut-legend">
                <%= for segment <- legend_segments(@allocation) do %>
                  <li>
                    <span class="cat-swatch" style={"background:#{segment.color}"} aria-hidden="true">
                    </span>
                    <span class="legend-name"><%= segment.name %></span>
                    <span class="legend-value">
                      <%= segment.percent %>%<%= if segment[:value], do: " · #{segment.value}" %>
                    </span>
                  </li>
                <% end %>
              </ul>
            </div>

            <%!-- #719 (D3): findings are {components.data-note} rows above
                 the table, never pills inside data cells — over-100 % sums at
                 attention, position-vs-category conflicts at problem, stale
                 position targets at attention. One status region wraps the
                 list (data-note aria rule). --%>
            <div
              :if={
                @allocation.has_plan and
                  (conflicted_categories(@allocation) != [] or
                     stale_categories(@allocation) != [] or plan_overshoot(@allocation))
              }
              role="status"
              class="allocation-findings"
            >
              <AppShell.data_note
                :if={plan_overshoot(@allocation)}
                severity={:attention}
                id="plan-overshoot-note"
                data-role="plan-overshoot-note"
              >
                <%= gettext(
                  "The plan's top-level targets sum to %{sum} % — more than 100 %. Drift keeps steering against the stored weights;",
                  sum: Format.percent(plan_overshoot(@allocation))
                ) %>
                <a href="/classifications"><%= gettext("trim the plan on the Classifications page.") %></a>
              </AppShell.data_note>
              <AppShell.data_note
                :if={conflicted_categories(@allocation) != []}
                severity={:problem}
                id="target-conflict-note"
                data-role="target-conflict-note"
              >
                <%= gettext(
                  "The position targets steer in %{categories}: their sum overrides the stored category weight.",
                  categories: Enum.join(conflicted_categories(@allocation), ", ")
                ) %>
                <a href="/classifications">
                  <%= gettext("Align the position targets and the category weight on the Classifications page.") %>
                </a>
              </AppShell.data_note>
              <AppShell.data_note
                :if={stale_categories(@allocation) != []}
                severity={:attention}
                id="stale-target-note"
                data-role="stale-target-note"
              >
                <%= gettext(
                  "A position target filed in %{categories} is stale: its security was moved or unassigned. It keeps counting there",
                  categories: Enum.join(stale_categories(@allocation), ", ")
                ) %>
                <a href="/classifications"><%= gettext("until re-filed on the Classifications page.") %></a>
              </AppShell.data_note>
            </div>

            <%!-- One expand/collapse toggle directly above the table (UAT fix
                 round): the label states the action it will perform next.
                 Beside it the drift threshold — the human half of the API's
                 `min_drift=`, same predicate, same rows. --%>
            <%!-- The one uniform chart-as-table disclosure (UX-DR10, issue
                 793): the drift table beneath IS the sunburst's table and
                 gains the disclosure head. --%>
            <details class="perf-table-disclosure" data-role="allocation-disclosure">
            <summary class="disclosure-summary">
              <AppShell.icon name={:chevron_right} size={12} class="disclosure-chevron" />
              <%= gettext("Data as table") %>
            </summary>
            <p class="hint" data-role="allocation-table-purpose">
              <%= gettext("Category, value, actual, target and drift — the sunburst as rows.") %>
            </p>
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
              <%!-- The same chip component the transaction history filters
                   with: one interaction, one visual. Pressed state is border
                   plus aria-pressed, not hue alone (UX-DR7). --%>
              <div
                :if={@allocation.has_plan}
                class="filter-chips"
                role="group"
                aria-label={gettext("Drift threshold")}
              >
                <span class="filter-chips__family"><%= gettext("Deviating by") %></span>
                <button
                  :for={pp <- drift_steps()}
                  type="button"
                  data-role="drift-chip"
                  phx-click="set_drift_threshold"
                  phx-value-pp={pp}
                  class={["filter-chip", @min_drift_pp == pp && "is-active"]}
                  aria-pressed={to_string(@min_drift_pp == pp)}
                >
                  <%= gettext("≥ %{pp} pp", pp: pp) %>
                </button>
              </div>
            </div>
            <%!-- A filtered table says what it is showing (UX-DR21), so a
                 short list is never mistaken for a short plan. --%>
            <p class="drift-filter-summary" data-role="drift-filter-summary">
              <%= if @min_drift_pp do %>
                <%= gettext(
                  "Showing %{shown} of %{total} categories, those deviating by at least %{pp} pp. Cash and unassigned always show.",
                  shown: length(threshold_rows(@allocation.categories, @min_drift_pp)),
                  total: length(@allocation.categories),
                  pp: @min_drift_pp
                ) %>
              <% else %>
                <%= gettext("Showing all %{total} categories.",
                  total: length(@allocation.categories)
                ) %>
              <% end %>
            </p>

            <div class="data-table-wrapper">
              <table class="drift-table" aria-describedby="tip-soll-ist">
                <thead>
                  <tr>
                    <th><%= gettext("Category") %></th>
                    <th class="num"><%= gettext("Value") %></th>
                    <th class="num"><%= gettext("Actual") %></th>
                    <%= if @allocation.has_plan do %>
                      <th class="num"><%= gettext("Target") %></th>
                      <th class="num col-subject">
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
                  <%= for row <- visible_category_rows(
                        @allocation.categories,
                        min_drift_decimal(@min_drift_pp),
                        @expanded_categories,
                        @category_parent_map
                      ) do %>
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
                        <%!-- #719 (D3): the category-cell pill is retired —
                             conflict and stale findings render as data notes
                             above the table (UX-DR17). --%>
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
                          "col-subject",
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
                              "col-subject",
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
                          "col-subject",
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
                              "col-subject",
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
            </div>

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
            </details>
            <% end %>

            <%!-- The flat rebalancing worklist: one row per position, ranked
                 by signed drift by default (overweight first, underweight
                 last), re-sortable via the column heads. Cash joins as a row;
                 unassigned positions carry no drift (nudging toward
                 assignment). --%>
            <%= if @allocation_mode == :flat do %>
              <div class="data-table-wrapper">
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
                        <%!-- #875: cash is never "unassigned" — it has its own
                             target and its own drift; its cell is empty like any
                             cell without a value. --%>
                        <%= cond do %>
                          <% entry.cash? -> %>
                            —
                          <% entry.category_name -> %>
                            <span
                              :if={entry.category_color}
                              class="cat-swatch"
                              style={"background:#{entry.category_color}"}
                              aria-hidden="true"
                            >
                            </span>
                            <%= entry.category_name %>
                          <% true -> %>
                            <span class="hint"><%= gettext("Unassigned") %></span>
                        <% end %>
                      </td>
                      <td class="num">
                        <%= Format.money(entry.market_value) %>
                        <AppShell.quote_stale :if={stale_flat_entry?(entry)} date={entry.price_date} />
                      </td>
                      <td class="num"><%= Format.percent(entry.weight) %>%</td>
                      <%= if @allocation.has_plan do %>
                        <td class={[
                          "num",
                          "col-subject",
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
              </div>
            <% end %>
          <% else %>
            <%!-- #723: allocation is a sub-second figure — the block
                 skeleton (UX-DR20) carries the wait without the cue. --%>
            <div
              class="section-skeleton section-skeleton--allocation"
              data-role="allocation-skeleton"
              aria-busy="true"
            >
            </div>
          <% end %>
        </section>
        <% end %>

        <%!-- #814: the holdings projection's own positions, with the column
             picker that is the human half of the API's `fields=` sparse
             fieldset. It left with the Transactions holdings panel (#803) and
             the projection's valuation fields were agent-only until here. --%>
        <%= if @wealth_tab == :holdings do %>
        <section id="portfolio-positions" class="workspace-section">
          <header class="section-head">
            <h2><%= gettext("Positions") %></h2>
            <%!-- #850: the shared grouped popover (DESIGN.md → Overlays, pick
                 E3). It sits in the head now that it opens over the table:
                 the <details> it replaces had to live in the body flow,
                 because opening it re-centred the heading. Not offered over
                 an empty state — picking columns for a table that is not
                 there is an offer with nothing behind it. --%>
            <div :if={@holding_rows != []} class="popover-container">
              <ColumnPicker.toggle
                id="holdings-column-toggle"
                open={@column_picker_open?}
                on_toggle="toggle_column_picker"
              />
              <ColumnPicker.picker
                :if={@column_picker_open?}
                id="holdings-column-picker"
                form_id="holdings-column-form"
                on_change="set_holdings_columns"
                on_close="close_column_picker"
                toggle_id="holdings-column-toggle"
                groups={holdings_column_groups()}
                selected={@holdings_columns}
              />
            </div>
          </header>
          <p class="summary-basis" data-role="positions-basis">
            <%= gettext(
              "The holdings projection this instance serves over the API: one row per depot and security, valued at the latest stored price. The columns are that projection's own fields."
            ) %>
          </p>
          <%= if @holding_rows == [] do %>
            <div id="no-positions" class="empty-state" role="status">
              <%= gettext("No holdings yet") %>
            </div>
          <% else %>
            <div
              id="holdings-positions-wrapper"
              class="data-table-wrapper"
              phx-hook="ColumnPrefs"
              data-storage-key={holdings_storage_key()}
              data-restore-event="set_holdings_columns"
              data-current-columns={Jason.encode!(@holdings_columns)}
            >
              <table id="holdings-positions-table" class="data-table">
                <thead>
                  <tr>
                    <th :for={key <- @holdings_columns} {holdings_num_attrs(key)}>
                      <%= holdings_column_label(key) %>
                    </th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={row <- @holding_rows} data-role="holdings-position">
                    <td :for={key <- @holdings_columns} {holdings_num_attrs(key)}>
                      <%= holdings_cell(row, key) %><small
                        :if={holdings_currency(row, key)}
                        class="value-suffix"
                      ><%= row.currency_code %></small>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          <% end %>
        </section>
        <% end %>

        <%= if @wealth_tab == :holdings do %>
        <section id="portfolio-cash" class="workspace-section">
          <h2><%= gettext("Cash accounts") %></h2>
          <%= if @valuation do %>
            <div class="data-table-wrapper">
              <table class="cash-table">
                <thead>
                  <tr>
                    <th><%= gettext("Account") %></th>
                    <th class="num"><%= gettext("Balance") %></th>
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
                      <td class="num">
                        <%= Format.money(cash.balance) %> <%= cash.currency %>
                        <span
                          :if={not cash.valued}
                          class="cash-unvalued"
                          data-role="cash-unvalued"
                        >
                          ⚠ <%= gettext("no exchange rate") %>
                        </span>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>

            <%!-- Issue 670 (UX-DR3/UX-DR11): setting a balance moved into the
                 account row on Accounts & depots, where the account is
                 already chosen. This surface keeps the read-only table. --%>
            <p data-role="cash-edit-pointer">
              <a href="/portfolios"><%= gettext("Set balances on Accounts & depots") %></a>
            </p>

          <% else %>
            <%!-- #723: the valuation is sub-second — silent skeleton. --%>
            <div class="section-skeleton" data-role="cash-skeleton" aria-busy="true"></div>
          <% end %>
        </section>
        <% end %>
      </div>
    </AppShell.shell>
    """
  end

  # -- #814 holdings column registry ------------------------------------------

  # #850: the picker's groups, every key of `@holdings_column_keys` in
  # exactly one.
  defp holdings_column_groups do
    [
      {gettext("Position"), ~w(depot security quantity)},
      {gettext("Identifiers"), ~w(isin wkn)},
      {gettext("Valuation"),
       ~w(currency avg_cost latest_price market_value unrealized_pnl_abs unrealized_pnl_pct)}
    ]
    |> Enum.map(fn {legend, keys} ->
      {legend, Enum.map(keys, &{&1, holdings_column_label(&1)})}
    end)
  end

  # The rows are the API's projection, decorated with the depot's name so the
  # human column reads as a name where the payload carries an id.
  defp holding_rows(nil), do: []

  defp holding_rows(portfolio) do
    names = Map.new(Portfolios.list_securities_accounts(), &{&1.id, &1.name})

    portfolio.id
    |> Ledger.holdings_for_portfolio()
    |> Enum.map(fn row ->
      Map.put(
        row,
        :securities_account_name,
        Map.get(names, row.securities_account_id, gettext("Unknown depot"))
      )
    end)
    |> Enum.sort_by(&{&1.securities_account_name, &1.security_name})
  end

  defp holdings_num_attrs(key)
       when key in ~w(quantity avg_cost latest_price market_value unrealized_pnl_abs unrealized_pnl_pct),
       do: %{class: "num"}

  defp holdings_num_attrs(_key), do: %{}

  defp holdings_column_label("depot"), do: gettext("Depot")
  defp holdings_column_label("security"), do: gettext("Security")
  defp holdings_column_label("quantity"), do: gettext("Quantity")
  defp holdings_column_label("isin"), do: gettext("ISIN")
  defp holdings_column_label("wkn"), do: gettext("WKN")
  defp holdings_column_label("currency"), do: gettext("Currency")
  defp holdings_column_label("avg_cost"), do: gettext("Avg cost")
  defp holdings_column_label("latest_price"), do: gettext("Latest price")
  defp holdings_column_label("market_value"), do: gettext("Market value")
  defp holdings_column_label("unrealized_pnl_abs"), do: gettext("P&L")
  defp holdings_column_label("unrealized_pnl_pct"), do: gettext("P&L %")

  defp holdings_cell(row, "depot"), do: row.securities_account_name
  defp holdings_cell(row, "security"), do: row.security_name
  defp holdings_cell(row, "quantity"), do: holdings_decimal(row.quantity)
  defp holdings_cell(row, "isin"), do: row.isin
  defp holdings_cell(row, "wkn"), do: row.wkn
  defp holdings_cell(row, "currency"), do: row.currency_code
  defp holdings_cell(row, "avg_cost"), do: holdings_decimal(row.avg_cost)
  defp holdings_cell(row, "latest_price"), do: holdings_decimal(row.latest_price)
  defp holdings_cell(row, "market_value"), do: holdings_decimal(row.market_value)
  defp holdings_cell(row, "unrealized_pnl_abs"), do: holdings_decimal(row.unrealized_pnl_abs)
  defp holdings_cell(row, "unrealized_pnl_pct"), do: holdings_decimal(row.unrealized_pnl_pct)

  # The projection's own values, unrounded: this table is the human read of
  # what the API serves, so a figure here is the figure there. The separators
  # are the reader's, though — `1234.5` beside a neighbouring table's
  # `1.234,50` is the page disagreeing with itself for no gain. An absent
  # value is an em dash rather than a blank cell.
  defp holdings_decimal(nil), do: "—"

  defp holdings_decimal(%Decimal{} = value), do: PortfolixirWeb.Format.exact(value)

  defp holdings_decimal(value), do: to_string(value)

  # The money columns carry the row's own currency, because `currency` is an
  # opt-in column and a bare market value with no currency states less than
  # the payload it mirrors (EXPERIENCE.md → Voice and Tone: numbers state
  # their basis where it is cheap).
  defp holdings_money?(key), do: key in ~w(avg_cost latest_price market_value unrealized_pnl_abs)

  defp holdings_currency(row, key) do
    if holdings_money?(key) and holdings_cell(row, key) != "—", do: row.currency_code
  end

  # -- components -------------------------------------------------------------

  # Surfaces why the totals can deviate from the user's expectation: positions
  # valued at a stale trade price, positions with no price at all, positions
  # priced in a currency without a stored FX path (#406 — a distinct, honest
  # state: the price exists and is shown), bookings whose dates are
  # implausible (import typos like 0219-03-07), and cash accounts excluded
  # because no FX rate to the base currency exists.
  defp data_quality(assigns) do
    assigns =
      assigns
      |> assign(:no_price, unvalued_entries(assigns.valuation, :no_price))
      |> assign(:missing_fx, unvalued_entries(assigns.valuation, :missing_fx))
      |> assign(:trade_priced, trade_priced_entries(assigns.valuation))
      |> assign(:stale_priced, stale_priced_entries(assigns.valuation))
      |> assign(:suspect_dates, suspect_dates(assigns.analysis))
      |> assign(:unvalued_cash, unvalued_cash(assigns.valuation))
      |> assign(:negative_entries, negative_entries(assigns.negative))

    ~H"""
    <section
      :if={
        @no_price.count > 0 or @missing_fx.count > 0 or @trade_priced.count > 0 or
          @stale_priced.count > 0 or @suspect_dates != [] or @unvalued_cash != [] or
          @negative_entries != []
      }
      id="portfolio-data-quality"
      class="workspace-section data-quality"
    >
      <h2><%= gettext("Data quality") %></h2>
      <%!-- UX-DR17 (issue 792): one data note per finding at its own severity,
           glyph and word included, the remedy inside the note; one status
           region for the list, never a role per note. --%>
      <div role="status" data-role="dq-notes">
        <AppShell.data_note :if={@trade_priced.count > 0} severity={:note} data-role="dq-trade-priced">
          <%!-- The finding links to where it is fixed (#561): the securities
               list pre-filtered to stale quotes.

               Overview and Wealth both surface this condition, and that is a
               role split rather than a duplication (#703): the Overview is the
               "does anything need me?" surface and keeps the bare count as the
               ALARM, while this page is where the number is distorted and so
               states the CONSEQUENCE for the total and names the positions.
               Naming them also makes this row consistent with every one of its
               siblings, all of which join their entries. --%>
          <a href="/securities?dq=stale_quote">
            <%= ngettext(
              "One held position is valued at its last trade price, so the total is not current:",
              "%{count} held positions are valued at their last trade price, so the total is not current:",
              @trade_priced.count
            ) %>
          </a>
          <%= Enum.join(@trade_priced.names, ", ") %>
        </AppShell.data_note>
        <AppShell.data_note
          :if={@stale_priced.count > 0}
          severity={:attention}
          data-role="dq-stale-priced"
        >
          <%!-- #779 / #610 (Sprint 11 Lane X): a quoted position whose feed
               has stopped reads as live without this row. It names the
               positions with the date each price is from and the remedy —
               the retired flag is what the performance walk keys on. --%>
          <a href="/securities?dq=stale_quote&holding=held">
            <%= ngettext(
              "One held position is valued at a quote older than %{days} days, so the totals may be stale — mark it retired if its listing ended, or sync its quotes:",
              "%{count} held positions are valued at quotes older than %{days} days, so the totals may be stale — mark them retired if their listings ended, or sync their quotes:",
              @stale_priced.count,
              days: @stale_priced.days
            ) %>
          </a>
          <%= Enum.join(@stale_priced.names, ", ") %>
        </AppShell.data_note>
        <AppShell.data_note :if={@no_price.count > 0} severity={:attention} data-role="dq-no-price">
          <a href="/securities?dq=missing_quote">
            <%= ngettext(
              "One held position has no price at all and is missing from the totals:",
              "%{count} held positions have no price at all and are missing from the totals:",
              @no_price.count
            ) %>
          </a>
          <%= Enum.join(@no_price.names, ", ") %>
        </AppShell.data_note>
        <AppShell.data_note :if={@missing_fx.count > 0} severity={:attention} data-role="dq-missing-fx">
          <%= ngettext(
            "One held position has a price but no exchange rate to %{base} stored, so it is missing from the totals: %{entries}.",
            "%{count} held positions have a price but no exchange rate to %{base} stored, so they are missing from the totals: %{entries}.",
            @missing_fx.count,
            base: @valuation.base_currency,
            entries: Enum.join(@missing_fx.names, ", ")
          ) %>
          <.fx_sync_control syncing={@fx_syncing} flash={@fx_sync_flash} result={@fx_sync_result} />
        </AppShell.data_note>
        <AppShell.data_note :if={@suspect_dates != []} severity={:attention} data-role="dq-suspect-dates">
          <%= gettext(
            "Bookings dated before 1970 (%{dates}) are applied on the first plausible day — fix those dates in the source and re-import.",
            dates: Enum.map_join(@suspect_dates, ", ", &Date.to_iso8601/1)
          ) %>
        </AppShell.data_note>
        <AppShell.data_note :if={@unvalued_cash != []} severity={:attention} data-role="dq-unvalued-cash">
          <%= ngettext(
            "One cash account is not counted in the totals because there is no exchange rate to %{base}: %{names}.",
            "%{count} cash accounts are not counted in the totals because there is no exchange rate to %{base}: %{names}.",
            length(@unvalued_cash),
            base: @valuation.base_currency,
            names: Enum.map_join(@unvalued_cash, ", ", &"#{&1.name} (#{&1.currency})")
          ) %>
          <.fx_sync_control
            :if={@missing_fx.count == 0}
            syncing={@fx_syncing}
            flash={@fx_sync_flash}
            result={@fx_sync_result}
          />
        </AppShell.data_note>
        <AppShell.data_note
          :if={@negative_entries != []}
          severity={:problem}
          data-role="dq-negative-holdings"
        >
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
        </AppShell.data_note>
      </div>
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
    assigns =
      assigns
      |> assign_new(:mode, fn -> "ttwror" end)
      |> assign_new(:overlays, fn -> [] end)

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
    <figure id="performance-figure" class="perf-figure" data-chart-mode={@mode}>
      <SecurityChart.chart
        quotes={@quotes}
        show_transactions?={false}
        value_mode={@value_mode}
        zero_line?={@zero_line?}
        aria_label={@aria_label}
        currency_code={@currency_code}
        overlays={Enum.map(@overlays, &%{&1 | points: downsample(&1.points)})}
        overlays_extend_range?={true}
      />
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
          "#{signed_percent(point.cumulative_ttwror)}% · #{Format.money(point.value)} #{currency}" <>
            overlay_labels(lookups, point.date)
      }
    end)
  end

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

  # -- benchmark comparison (ADR-0046 §4) ---------------------------------------

  # The selectors the BenchmarkScope plug remembered, resolved against the
  # catalog: a flagged security or a fixed rate. Anything else — an unflagged
  # or vanished security, a malformed selector — is dropped silently, so the
  # picker shows what is actually active.
  defp resolve_benchmarks(selectors) when is_list(selectors) do
    selectors
    |> Enum.flat_map(fn
      "security:" <> id -> resolve_benchmark_security(id)
      "rate:" <> rate -> resolve_benchmark_rate(rate)
      _other -> []
    end)
    |> Enum.take(2)
  end

  defp resolve_benchmarks(_selectors), do: []

  # The selectors naming a security a merge took away, each with the live
  # end of its merge chain: `[{old_id, survivor_id}]`.
  defp merged_benchmarks(selectors) when is_list(selectors) do
    for "security:" <> raw <- selectors,
        {:ok, id} <- [LiveParam.fetch_id(raw)],
        is_nil(Portfolixir.Catalog.get_security(id)),
        survivor = Portfolixir.Lifecycle.merged_into(:security, id),
        is_integer(survivor),
        do: {id, survivor}
  end

  defp merged_benchmarks(_selectors), do: []

  # The same page — every other parameter of the link kept — with every
  # active selector, remembered or linked, naming the survivor, the rate
  # kept, and the merged ids in `benchmark_merged` for the note. The
  # selectors ride as `benchmark[]`, so the plug remembers them.
  defp survivor_benchmark_path(params, active, merged) do
    survivors = Map.new(merged)

    selectors =
      Enum.map(active, fn
        "security:" <> raw = selector ->
          case LiveParam.fetch_id(raw) do
            {:ok, id} -> if s = survivors[id], do: "security:#{s}", else: selector
            :error -> selector
          end

        selector ->
          selector
      end)

    query =
      params
      |> Map.drop(["benchmark", "benchmark_merged"])
      |> Enum.sort()
      |> Enum.flat_map(&kept_param/1)
      |> Kernel.++(Enum.map(Enum.uniq(selectors), &{"benchmark[]", &1}))
      |> Kernel.++([{"benchmark_merged", Enum.map_join(merged, ",", &elem(&1, 0))}])
      |> URI.encode_query()

    "/portfolio?" <> query
  end

  # Every other parameter of the link rides along as it came (review finding
  # M-8): the redirect changes the benchmark only, never the period or the
  # view a bookmark carries. A list stays a list; anything else is dropped.
  defp kept_param({key, value}) when is_binary(key) and is_binary(value), do: [{key, value}]

  defp kept_param({key, values}) when is_binary(key) and is_list(values),
    do: for(value <- values, is_binary(value), do: {key <> "[]", value})

  defp kept_param(_other), do: []

  # The note says only what the records say: each id in `benchmark_merged`
  # must name a security a merge took away into an active benchmark.
  defp benchmark_merged_notes(%{"benchmark_merged" => raw}, socket) when is_binary(raw) do
    active =
      for "security:" <> id <- socket.assigns[:active_benchmark_selectors] || [],
          {:ok, parsed} <- [LiveParam.fetch_id(id)],
          do: parsed

    for part <- raw |> String.split(",") |> Enum.take(2),
        {:ok, from} <- [LiveParam.fetch_id(part)],
        survivor = Portfolixir.Lifecycle.merged_into(:security, from),
        survivor in active,
        record = Portfolixir.Lifecycle.merge_of(:security, from),
        security = Portfolixir.Catalog.get_security(survivor),
        not is_nil(record) and not is_nil(security),
        do: %{name: security.name, merged_on: Portfolixir.Clock.local_date(record.inserted_at)}
  end

  defp benchmark_merged_notes(_params, _socket), do: []

  defp resolve_benchmark_security(id) do
    with {:ok, id} <- LiveParam.fetch_id(id),
         %Portfolixir.Catalog.Security{is_benchmark: true} = security <-
           Portfolixir.Catalog.get_security(id) do
      [{:security, security}]
    else
      _unflagged_or_missing -> []
    end
  end

  # The plug's one bound (E25 S4, F06), so the page resolves exactly the
  # selectors the plug would store.
  defp resolve_benchmark_rate(rate) do
    case BenchmarkScope.parse_rate(rate) do
      {:ok, rate} -> [{:rate, rate}]
      :error -> []
    end
  end

  # One comparison per active benchmark over the shown period, re-chained
  # from the cached analysis exactly like the performance summary (memoised,
  # ADR-0046 §5) — a period switch is instant here too.
  defp assign_comparisons(
         %{assigns: %{analysis: %{} = analysis, period: period, benchmarks: benchmarks}} = socket
       ) do
    comparisons =
      for benchmark <- benchmarks,
          {:ok, comparison} <- [Benchmark.compare(analysis, period, benchmark)],
          do: comparison

    assign(socket, :comparisons, comparisons)
  end

  defp assign_comparisons(socket), do: assign(socket, :comparisons, [])

  defp benchmark_name({:security, security}), do: security.name

  defp benchmark_name({:rate, rate}),
    do: gettext("%{rate} % p.a.", rate: Format.decimal(Decimal.mult(rate, 100), 2))

  defp comparison_name(%{kind: :security, name: name}), do: name
  defp comparison_name(%{kind: :rate, annual_rate: rate}), do: benchmark_name({:rate, rate})

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

  # "portfolio vs benchmark", each a signed percent or a dash.
  defp return_pair(portfolio, benchmark) do
    gettext("%{portfolio} vs %{benchmark}",
      portfolio: percent_or_dash(portfolio),
      benchmark: percent_or_dash(benchmark)
    )
  end

  defp percent_or_dash(%Decimal{} = value), do: signed_percent(value) <> "%"
  defp percent_or_dash(_nil), do: "—"

  # The covered window as a basis line (UX-DR13) when it is narrower than the
  # period: where the comparison starts and how many earlier flows enter
  # through its opening value instead of on their own day — or, when the
  # benchmark has no priced day at all, that nothing is covered.
  defp coverage_note(%{window: %{start_date: nil}, excluded_flows: excluded}) do
    ngettext(
      "no covered window — %{count} flow before the benchmark's first priced day",
      "no covered window — %{count} flows before the benchmark's first priced day",
      length(excluded)
    )
  end

  defp coverage_note(%{window: %{start_date: start_date}, excluded_flows: excluded}) do
    ngettext(
      "from %{date} — %{count} earlier flow enters through the opening value",
      "from %{date} — %{count} earlier flows enter through the opening value",
      length(excluded),
      date: start_date
    )
  end

  # The money-weighted pair, labelled and chosen like the sibling card's
  # figure (ADR-0034 §2): the non-annualized period MWR for a window shorter
  # than a year, the annualized IRR otherwise — over the comparison's own
  # window, which can be narrower than the period.
  defp money_weighted_pair(comparison) do
    if short_window?(comparison.window) do
      gettext("MWR") <>
        ": " <>
        return_pair(comparison.savings_plan.portfolio_mwr, comparison.savings_plan.benchmark_mwr)
    else
      gettext("IRR") <>
        ": " <>
        return_pair(comparison.savings_plan.portfolio_irr, comparison.savings_plan.benchmark_irr)
    end
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
  defp benchmark_overlays("ttwror", comparisons, series) do
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

  defp benchmark_overlays(_mode, _comparisons, _series), do: []

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
      <%!-- The click payload says `amount`, not `value`: LiveView's client
           overwrites a `phx-value-value` with the element's own DOM value, so
           the name is unusable on anything that has one. Kept uniform here
           even though an SVG path has no `value`, so the rule stays absolute
           and its meta-test needs no exception. --%>
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
          data-target={segment.target}
          phx-click="select_segment"
          phx-value-name={segment.name}
          phx-value-percent={segment.percent}
          phx-value-amount={segment.value}
          phx-value-target={segment.target}
          phx-value-color={segment.color}
        >
          <title><%= segment.name %> · <%= segment.percent %>%</title>
        </path>
      <% end %>
    </svg>
    """
  end

  # The centre of the sunburst (issue 793, DESIGN.md → Sunburst centre): the
  # touched segment — name, value, actual against target — or, untouched,
  # the reference value the shares are of. A polite live region of real
  # text, so a tap reads out on a touch device where there is no hover; the
  # SunburstTooltip hook paints the hovered slice into it and restores the
  # server's text from the data attributes on leave.
  attr(:centre, :map, required: true)

  defp sunburst_centre(assigns) do
    ~H"""
    <div
      class="sunburst-centre"
      data-role="sunburst-centre"
      aria-live="polite"
      data-label={@centre.label}
      data-value={@centre.value}
      data-sub={@centre.sub}
      data-currency={@centre.currency}
      data-target-word={gettext("target")}
    >
      <span class="sunburst-centre__label"><%= @centre.label %></span>
      <strong class="sunburst-centre__value"><%= @centre.value %></strong>
      <span class="sunburst-centre__sub"><%= @centre.sub %></span>
    </div>
    """
  end

  defp sunburst_centre(nil, allocation) do
    %{
      label: gettext("Allocated"),
      value: "#{Format.money(allocation.total_value)} #{allocation.base_currency}",
      sub: "#{Format.percent(Decimal.new(1))} %",
      currency: allocation.base_currency
    }
  end

  defp sunburst_centre(segment, allocation) do
    target =
      case segment.target do
        "" -> ""
        target -> " · #{gettext("target")} #{target} %"
      end

    %{
      label: segment.name,
      value: "#{segment.value} #{allocation.base_currency}",
      sub: "#{segment.percent} %#{target}",
      currency: allocation.base_currency
    }
  end

  defp active_view_name(nil), do: gettext("Everything")
  defp active_view_name(%{name: name}), do: name

  # Progressive fill (owner pick F1, DESIGN.md → Motion): reveals spread
  # across 1.2s, so with each 0.3s fade the whole build lands at ~1.5s.
  # Opacity only — geometry is final from the first frame.
  defp seg_reveal_delay(_index, count) when count <= 1, do: 0
  defp seg_reveal_delay(index, count), do: div(index * 1200, count)

  # -- events -----------------------------------------------------------------

  # The empty page (no depot, no cash account) offers no control, so an event
  # pushed to it meets none of the state a control assumes, and changes
  # nothing (E25 S4, F17).
  @impl true
  def handle_event("dismiss_benchmark_merged", _params, socket) do
    {:noreply, assign(socket, :benchmark_merged, [])}
  end

  def handle_event(_event, _params, %{assigns: %{portfolio: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("select_period", %{"period" => period}, socket) do
    if period in Performance.periods() do
      apply_period(socket, period)
    else
      {:noreply, socket}
    end
  end

  # #563: a single calendar year, offered for every year with data. The picked
  # year is validated against the cached analysis' own range.
  # #801: Cancel closes the popover through the same event the apply path
  # uses, so the hook's closeAndFocus returns focus to the summary. Removing
  # the `open` attribute client-side would leave focus on a button that has
  # just been hidden.
  def handle_event("cancel_period_popover", _params, socket),
    do: {:noreply, push_event(socket, "close-popover", %{id: "period-custom"})}

  def handle_event("select_year", %{"year" => raw}, socket) do
    with year when is_integer(year) <- LiveParam.year(raw),
         true <- year in available_years(socket.assigns.analysis) do
      apply_period(socket, {:year, year})
    else
      _invalid -> {:noreply, socket}
    end
  end

  def handle_event("select_year", _params, socket), do: {:noreply, socket}

  # #563 / #721 (D5): a custom from/to range. A backwards or unparsable
  # range is refused with the violation reported against the field that can
  # fix it (UX-DR13); the shown period keeps.
  def handle_event("select_range", %{"from" => from, "to" => to}, socket) do
    case parse_range(from, to) do
      {:ok, from, to} -> apply_period(socket, {:range, from, to})
      {:error, field} -> {:noreply, assign(socket, :range_error, field)}
    end
  end

  def handle_event("select_range", _params, socket) do
    {:noreply, assign(socket, :range_error, :from)}
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
    with {:ok, classification_id} <- LiveParam.fetch_id(id),
         true <- Enum.any?(socket.assigns.classifications, &(&1.id == classification_id)),
         false <- classification_id == socket.assigns.classification_id do
      {:noreply,
       push_patch(socket,
         to:
           allocation_current_path(
             current_view_param(socket.assigns.current_path),
             classification_id,
             socket.assigns.allocation_mode,
             socket.assigns.min_drift_pp
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
    case LiveParam.fetch_id(id) do
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
      name: LiveParam.string(params["name"]) || "",
      percent: LiveParam.string(params["percent"]) || "",
      value: LiveParam.string(params["amount"]) || "",
      target: LiveParam.string(params["target"]) || "",
      color: safe_color(params["color"])
    }

    {:noreply, assign(socket, :selected_segment, segment)}
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
  # #814: the picker's own event, and the ColumnPrefs hook's restore event —
  # the same pair the transaction history's picker uses, so the two behave
  # identically. An empty selection falls back to the defaults rather than
  # rendering a table with no columns.
  def handle_event("set_holdings_columns", %{"columns" => columns}, socket)
      when is_list(columns) do
    chosen =
      case Enum.filter(@holdings_column_keys, &(&1 in columns)) do
        [] -> @holdings_column_defaults
        picked -> picked
      end

    {:noreply,
     socket
     |> assign(:holdings_columns, chosen)
     |> push_event("column-prefs-changed", %{key: @holdings_storage_key, columns: chosen})}
  end

  def handle_event("set_holdings_columns", _params, socket), do: {:noreply, socket}

  def handle_event("toggle_column_picker", _params, socket) do
    {:noreply, update(socket, :column_picker_open?, &(not &1))}
  end

  def handle_event("close_column_picker", _params, socket) do
    {:noreply, assign(socket, :column_picker_open?, false)}
  end

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
             requested,
             socket.assigns.min_drift_pp
           )
       )}
    end
  end

  # Forged-event parity with the set_chart_mode fallback (async-hardening
  # round): a malformed payload degrades instead of crashing the LiveView.
  def handle_event("set_allocation_mode", _params, socket), do: {:noreply, socket}

  # The drift threshold rides the URL like the tree and the mode do, so a
  # reconnect or a shared link reopens the same filtered table. Clicking the
  # active step clears it (the chip is a toggle), and an unknown step is a
  # no-op rather than a crash.
  def handle_event("set_drift_threshold", %{"pp" => pp}, socket) when pp in @drift_steps do
    requested = if pp == socket.assigns.min_drift_pp, do: nil, else: pp

    {:noreply,
     push_patch(socket,
       to:
         allocation_current_path(
           current_view_param(socket.assigns.current_path),
           socket.assigns.classification_id,
           socket.assigns.allocation_mode,
           requested
         )
     )}
  end

  def handle_event("set_drift_threshold", _params, socket), do: {:noreply, socket}

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

  # An event this page does not know, or a payload it cannot read, changes
  # nothing (E25 S4, F17).
  def handle_event(_event, _params, socket), do: {:noreply, socket}

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

  # A held entry valued at a stale close is marked beside its value (issue
  # 789) under the one threshold the data-quality finding uses; a retired
  # holding's stopped feed is expected. Trade-priced entries are the
  # finding's own note, not this marker.
  defp stale_flat_entry?(entry) do
    Map.get(entry, :price_source) == :quote and not Map.get(entry, :retired, false) and
      DataQuality.stale_quote?(Map.get(entry, :price_date), Portfolixir.Clock.today())
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
  # #719 (D3): the note helpers that replaced the category-cell pill. The
  # "Σ-Konflikt" label died with it — the notes state the consequence in a
  # sentence and name the categories.
  defp conflicted_categories(allocation),
    do: for(row <- allocation.categories, row.conflict, do: row.name)

  defp stale_categories(allocation),
    do: for(row <- allocation.categories, row.has_stale, do: row.name)

  defp plan_overshoot(%{has_plan: true, top_level_target_sum: %Decimal{} = sum}) do
    if Decimal.gt?(sum, 1), do: sum
  end

  defp plan_overshoot(_allocation), do: nil

  defp rebalance_hint_parts(nil), do: nil

  # A hint that rounds to nothing is no hint (#875): "Sell ≈ 0.00 units" asks
  # for an action that is nothing. The drift stays, and the API keeps the
  # unrounded quantity — the suppression is display only.
  defp rebalance_hint_parts(%Decimal{} = quantity) do
    shown = quantity |> Decimal.abs() |> Decimal.round(2)

    cond do
      Decimal.eq?(shown, 0) -> nil
      Decimal.gt?(quantity, 0) -> %{verb: gettext("Sell"), quantity: Format.decimal(shown, 2)}
      true -> %{verb: gettext("Buy"), quantity: Format.decimal(shown, 2)}
    end
  end

  # On-demand exchange-rate sync (issue #432): the rate provider only refreshes
  # on a 12 h timer, so a foreign-currency cash account stays unvalued until a
  # rate arrives. This lets the user pull rates now and re-value the figures.
  # Since issue 792 the control is the remedy inside the finding that needs it
  # (the missing-rate note), with the same background run, busy state and
  # inline result the standalone button under the cash table carried before.
  # The confirmation flashes in the button while the note stands; the result
  # line stays compact — count plus the local wall-clock time of the run
  # (display-only formatting; domain data stays day-granular).
  attr(:syncing, :boolean, required: true)
  attr(:flash, :boolean, required: true)
  attr(:result, :any, required: true)

  defp fx_sync_control(assigns) do
    ~H"""
    <span class="fx-sync" data-role="fx-sync">
      <button
        type="button"
        phx-click="sync_rates"
        disabled={@syncing or @flash}
        phx-disable-with={gettext("Syncing…")}
      >
        <%= cond do %>
          <% @syncing -> %>
            <span class="spinner" aria-hidden="true"></span> <%= gettext("Syncing…") %>
          <% @flash -> %>
            ✓ <%= gettext("Up to date") %>
          <% true -> %>
            <%= gettext("Sync exchange rates") %>
        <% end %>
      </button>
      <span :if={@syncing} class="hint" data-role="fx-sync-status">
        <%= gettext("Syncing exchange rates…") %>
      </span>
      <span
        :if={@result}
        class={["hint", @result == :error && "fx-sync-error"]}
        data-role="fx-sync-result"
        role={if @result == :error, do: "alert"}
      >
        <%= fx_sync_result_message(@result) %>
      </span>
    </span>
    """
  end

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

  # Mirrors unvalued_entries/2: the row names what it found, shortened by the
  # same rule so a long list does not swamp the section (#703).
  defp trade_priced_entries(nil), do: %{count: 0, names: []}

  defp trade_priced_entries(valuation) do
    names =
      valuation.positions
      |> Enum.filter(&(&1.price_source == :trade))
      |> Enum.map(&(&1.security_name || gettext("Unsorted")))
      |> Enum.uniq()

    %{count: length(names), names: shorten_list(names)}
  end

  # The stale-quoted positions (#779 / #610), each named with the date its
  # price is from, under the one staleness threshold DataQuality states.
  defp stale_priced_entries(nil), do: %{count: 0, names: [], days: DataQuality.stale_days()}

  defp stale_priced_entries(valuation) do
    today = Portfolixir.Clock.today()
    days = DataQuality.stale_days()

    names =
      valuation.positions
      |> Enum.filter(fn position ->
        # A retired holding is left out: the finding's own remedy (#610).
        not Map.get(position, :retired, false) and position.price_source == :quote and
          match?(%Date{}, position.price_date) and Date.diff(today, position.price_date) > days
      end)
      |> Enum.map(
        &"#{&1.security_name || gettext("Unsorted")} (#{Date.to_iso8601(&1.price_date)})"
      )
      |> Enum.uniq()

    %{count: length(names), names: shorten_list(names), days: days}
  end

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

  # The hole is the centre's reading room (issue 793): wide enough for a
  # value at 16 px, so the rings start at 42 % of the outer radius.
  @sunburst_inner 28
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
          target: row.target_weight && Format.percent(row.target_weight),
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
      target: Map.get(node, :target),
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
          percent: Format.percent(row.actual_weight),
          value: Format.money(row.market_value)
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
                  percent: Format.percent(weight),
                  value: Format.money(value)
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
      %{actual_weight: weight, market_value: value, distributed: false} ->
        if Decimal.compare(weight, 0) == :gt do
          with_unassigned ++
            [
              %{
                name: gettext("Cash"),
                color: @cash_color,
                percent: Format.percent(weight),
                value: Format.money(value)
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
  # Insight-level table rows for the chart's data-as-table disclosure (#564):
  # the FULL daily series (never the downsampled one) grouped into calendar
  # slices — years when the series spans more than a year, months otherwise.
  # Each row: start value (the value at the slice boundary, i.e. the previous
  # slice's last point), end value, the slice's own TTWROR chained out of the
  # cumulative series ((1+cum_end)/(1+cum_start) - 1), and the summed net
  # external flows. All Decimal; display-only derivation of stored values.
  defp table_summary([]), do: %{unit: :month, rows: []}

  defp table_summary(series) do
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

  defp slice_label(date, :month),
    do: "#{date.year}-#{String.pad_leading(Integer.to_string(date.month), 2, "0")}"

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

  # The basis line names the tree the way the picker above it does: a
  # built-in tree's stored name is English by design (#729), so it localizes
  # at render time rather than reaching the screen as data.
  defp allocation_tree_name(allocation) do
    ClassificationName.display(%{
      key: Map.get(allocation, :classification_key),
      name: allocation.classification_name
    })
  end

  # One landing spot for a validated period term (a button string, a year or a
  # range): re-chain the cached analysis instantly, or — while the walk is
  # still computing — remember the choice for the async completion.
  defp apply_period(socket, period) do
    socket = assign(socket, :range_error, nil)

    if socket.assigns.analysis do
      # The analysis is cached — re-chaining a period is pure and instant.
      case Performance.summarise(socket.assigns.analysis, period) do
        {:ok, performance} ->
          {:noreply,
           socket
           |> assign(period: period, performance: performance)
           |> assign_comparisons()
           |> push_event("close-popover", %{id: "period-custom"})}

        {:error, _reason} ->
          {:noreply,
           socket
           |> assign(period: period, performance: nil, performance_failed: true)
           |> push_event("close-popover", %{id: "period-custom"})}
      end
    else
      {:noreply,
       socket
       |> assign(:period, period)
       |> push_event("close-popover", %{id: "period-custom"})}
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

  # The money-weighted card's sub-line states its basis (#797): annualized or
  # the period figure, and the walk's as-of date.
  defp money_weighted_basis(performance) do
    basis =
      if short_window?(performance),
        do: gettext("not annualized"),
        else: gettext("annualized")

    case performance.as_of do
      %DateTime{} = as_of ->
        gettext("%{basis} · as of %{date}",
          basis: basis,
          date: Format.date(DateTime.to_date(as_of))
        )

      _none ->
        basis
    end
  end

  # The Allocation tab's summary line is busy while either figure it carries
  # is still computing (UX-DR20); a failed walk is not "busy".
  defp summary_busy(valuation, performance, performance_failed) do
    if is_nil(valuation) or (is_nil(performance) and not performance_failed),
      do: "true",
      else: nil
  end

  # The summary line's way back to Holdings keeps the picked view (#797).
  defp holdings_path(current_path) do
    case current_view_param(current_path) do
      nil -> "/portfolio"
      view -> "/portfolio?" <> URI.encode_query(%{"view" => view})
    end
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
  # The shared date rule (E25 S4): an ISO date inside the ledger's range, so a
  # typed or pushed year far outside it is the field's error, not a period.
  defp parse_range(from_str, to_str) do
    with {:from, {:ok, from}} <- {:from, BoundedDate.parse(from_str)},
         {:to, {:ok, to}} <- {:to, BoundedDate.parse(to_str)},
         {:order, false} <- {:order, Date.compare(from, to) == :gt} do
      {:ok, from, to}
    else
      {:from, _} -> {:error, :from}
      {:to, _} -> {:error, :to}
      {:order, _} -> {:error, :order}
    end
  end

  # #801: a picked year is a custom period too — it lives in the popover, so
  # the segmented group has to echo it the way it echoes a range.
  defp custom_period?({:range, _from, _to}), do: true
  defp custom_period?({:year, _year}), do: true
  defp custom_period?(_period), do: false

  defp custom_period_label({:range, from, to}),
    do: "#{Date.to_iso8601(from)} – #{Date.to_iso8601(to)}"

  defp custom_period_label({:year, year}), do: Integer.to_string(year)

  defp range_error_message(:order),
    do: gettext("The end date is before the start date.")

  defp range_error_message(_field),
    do: gettext("Not a date — use YYYY-MM-DD.")

  defp range_from({:range, from, _to}, _performance), do: from
  defp range_from(_period, %{start_date: %Date{} = start_date}), do: start_date
  defp range_from(_period, _performance), do: nil

  defp range_to({:range, _from, to}, _performance), do: to
  defp range_to(_period, %{end_date: %Date{} = end_date}), do: end_date
  defp range_to(_period, _performance), do: nil

  # The colour lands in a style attribute, so only a literal hex colour from
  # our own render is accepted — anything else falls back to neutral grey.
  defp safe_color(value) when is_binary(value) do
    if value =~ ~r/^#[0-9a-fA-F]{6}$/, do: value, else: @fallback_color
  end

  defp safe_color(_value), do: @fallback_color

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
