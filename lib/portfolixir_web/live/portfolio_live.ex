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
  alias Portfolixir.Input.BoundedDate
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Allocation
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.Performance.Bands
  alias Portfolixir.Portfolios.Performance.Benchmark
  alias Portfolixir.Portfolios.Performance.Contribution
  alias Portfolixir.Portfolios.PricingContext
  alias Portfolixir.Portfolios.Targets
  alias Portfolixir.Portfolios.Valuation
  alias Portfolixir.Settings
  alias PortfolixirWeb.AccountNames
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.CappedAsync
  alias PortfolixirWeb.Dashboard.Widgets.Allocation, as: AllocationWidget
  alias PortfolixirWeb.Dashboard.Widgets.CashAccounts, as: CashAccountsWidget
  alias PortfolixirWeb.Dashboard.Widgets.DataNotes, as: DataNotesWidget
  alias PortfolixirWeb.Dashboard.Widgets.KeyFigures, as: KeyFiguresWidget
  alias PortfolixirWeb.Dashboard.Widgets.PerformanceSection
  alias PortfolixirWeb.Dashboard.Widgets.Positions, as: PositionsWidget
  alias PortfolixirWeb.Dashboard.Widgets.SummaryLine, as: SummaryLineWidget
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.LiveParam
  alias PortfolixirWeb.Portfolio.CategoryColors
  alias PortfolixirWeb.Portfolio.ContributionTable
  alias PortfolixirWeb.Portfolio.StackedChart
  alias PortfolixirWeb.PrivacyMode
  alias PortfolixirWeb.StoredText

  require CappedAsync
  import PortfolixirWeb.ViewSwitcher

  # The colours live in one module with the stacked chart's (I23): a
  # category looks the same on the sunburst and on the stack.
  @unassigned_color CategoryColors.unassigned()
  @cash_color CategoryColors.cash()
  # The drift-threshold steps the allocation table offers, in percentage
  # points. 5 pp is the dashboard's own attention threshold, so the alert list
  # and the filtered table agree on what "needs attention" means; 1 and 2 pp
  # are for a plan steered more tightly than that. A fixed set, because the
  # value round-trips through the URL and a whitelist beats parsing.
  # Sprint 32 W2: the chips' steps are the allocation section's.
  @drift_steps AllocationWidget.drift_steps()

  # #814: the human half of the holdings projection's `fields=` sparse
  # fieldset. The picker left with the Transactions holdings panel in #803;
  # this is where the review put the holdings. Sprint 32 W1: the columns,
  # their key in the browser and the pick's rule live with the section
  # widget „Positionen“ (`PositionsWidget`).

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

  defp mount_page(params, session, socket) do
    wealth_tab = wealth_tab(params)
    carried_view = carried_view(params, session)

    socket =
      socket
      # The tab rides in current_path so the view/locale switchers (which
      # derive their hrefs from it) keep the user on the active tab — and an
      # explicit, remembered ?view= rides along too, so a tab or locale switch
      # keeps the picked view in the URL (ADR-0024).
      |> assign(:carried_view, carried_view)
      |> assign(:current_path, wealth_tab |> wealth_tab_path() |> keep_view_param(carried_view))
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
          # accumulates; the period buttons still offer it. #1122 let a link
          # name a token (`?period=ytd` from the Overview's total), read on
          # arrival and stored nowhere; #1432 (plan amendment D-A1) reverses
          # the second half, because a period kept nowhere fell back to 1
          # year at every privacy, language, view or tab switch and reload:
          # every pick now rides the address (`address_period/1`), and the
          # browser, never the server, remembers the last one.
          |> assign_arrival_period(params)
          # I23 (FR-53): the stacked chart's level, tree, sort and drilled
          # category ride the address, so a link handed over reopens them;
          # a named level opens the value series, or with `scale=ttwror` the
          # TTWROR series' lines (FR-57).
          |> assign(:stack, param_stack(params, classifications))
          |> then(&assign(&1, :chart_mode, chart_mode_of(&1.assigns.stack)))
          |> assign(
            bands: nil,
            bands_colors: %{},
            bands_ancestors: [],
            bands_for: nil,
            bands_failed: false,
            stack_axis: nil,
            stack_axis_for: nil
          )
          # The classification tree and the tree/positions mode round-trip
          # through the URL (mobile-reconnect fix): a socket reconnect remounts
          # at the current URL, so reading them from the mount params here
          # reconstructs the user's selection instead of snapping back to the
          # defaults. handle_params re-reads the same params (idempotent on the
          # initial mount) and is the only path that reloads on a later change.
          |> assign(:classification_id, param_classification_id(params, classifications))
          |> assign(:valuation, nil)
          |> assign(:negative_report, nil)
          |> assign(:two_scales, [])
          |> assign(:implausible_quotes, [])
          |> assign(:allocation, nil)
          |> assign(:analysis, nil)
          |> assign(:analysis_read, nil)
          |> assign(:performance, nil)
          |> assign(:performance_stale, false)
          |> assign(:performance_failed, false)
          # FR-41 (ADR-0051 §12): the contribution table under the chart,
          # computed per period and view; "show all" survives a period switch.
          |> assign(:contribution, nil)
          |> assign(:contribution_read, nil)
          |> assign(:contribution_failed, false)
          |> assign(:contribution_show_all, false)
          # ADR-0046 §4: the remembered benchmark selection, resolved against
          # the catalog; the comparisons follow the performance summary.
          |> assign(:benchmarks, resolve_benchmarks(socket.assigns[:active_benchmark_selectors]))
          # #1416 (B2; board 02, Q1 A): the picker's labelled groups,
          # „Benchmarks“ then „Im Bestand“, one rule with the API's.
          |> then(&assign(&1, :benchmark_groups, benchmark_groups(&1.assigns.benchmarks)))
          |> assign(:comparisons, [])
          |> assign(:selected_segment, nil)
          |> assign(:expanded_categories, MapSet.new())
          |> assign(:allocation_mode, param_allocation_mode(params))
          |> assign(:min_drift_pp, param_min_drift_pp(params))
          |> assign(:flat_sort, AllocationWidget.default_sort())
          |> assign(:holdings_columns, PositionsWidget.default_columns())
          |> assign(:column_picker_open?, false)
          |> assign_holding_rows()
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

  # -- the period on the address (#1432, plan amendment D-A1) -------------------

  # The keys a period takes on the address: `period=` a token, `year=` a
  # calendar year, `from=` and `to=` a custom range.
  @period_keys ["period", "year", "from", "to"]

  # The period an address names: `{:ok, period}`, `:none` when it names
  # none, or `:invalid` for one that is no period at all (an unknown token,
  # a year out of range, an unparsable or backwards range). A range takes
  # the same date rule as the popover's form. Whether a year or a range
  # lies inside the analysis is asked once the analysis is there
  # (`period_within?/2`).
  defp address_period(params) do
    cond do
      Map.has_key?(params, "from") or Map.has_key?(params, "to") ->
        case parse_range(params["from"], params["to"]) do
          {:ok, from, to} -> {:ok, {:range, from, to}}
          {:error, _field} -> :invalid
        end

      Map.has_key?(params, "year") ->
        case LiveParam.year(params["year"]) do
          year when is_integer(year) -> {:ok, {:year, year}}
          _invalid -> :invalid
        end

      Map.has_key?(params, "period") ->
        if params["period"] in Performance.periods(), do: {:ok, params["period"]}, else: :invalid

      true ->
        :none
    end
  end

  # The arrival: the address's period (an invalid one is 1 year with the
  # line saying so), else 1 year; a year or a range is checked against the
  # analysis when it lands. Whether the address named one tells the
  # browser's memory not to reopen another (`#period-memory`).
  defp assign_arrival_period(socket, params) do
    {period, error} =
      case address_period(params) do
        {:ok, period} -> {period, nil}
        :none -> {"1y", nil}
        :invalid -> {"1y", :arrival}
      end

    assign(socket,
      period: period,
      range_error: error,
      period_unchecked: not is_binary(period),
      period_addressed: address_period(params) != :none
    )
  end

  # The address pairs of a period, in this order; 1 year, the default,
  # names none.
  defp period_pairs("1y"), do: []
  defp period_pairs(token) when is_binary(token), do: [{"period", token}]
  defp period_pairs({:year, year}), do: [{"year", Integer.to_string(year)}]

  defp period_pairs({:range, from, to}),
    do: [{"from", Date.to_iso8601(from)}, {"to", Date.to_iso8601(to)}]

  # What the browser keeps of a pick: its address pairs, 1 year named too,
  # so a pick of 1 year replaces an older one.
  defp period_memory("1y"), do: %{"period" => "1y"}
  defp period_memory(period), do: Map.new(period_pairs(period))

  # `path` with its period replaced by `period`'s pairs, appended after the
  # path's own pairs, which keep their order.
  defp with_period(path, period) do
    uri = URI.parse(path)

    kept =
      (uri.query || "")
      |> URI.query_decoder()
      |> Enum.reject(fn {key, _value} -> key in @period_keys end)

    case kept ++ period_pairs(period) do
      [] -> uri.path
      pairs -> uri.path <> "?" <> URI.encode_query(pairs)
    end
  end

  # Whether a year or a range lies inside the analysis' range: a year with
  # walked data, a range that meets the walked history. A token always does.
  defp period_within?(token, _analysis) when is_binary(token), do: true

  defp period_within?({:year, year}, analysis), do: year in available_years(analysis)

  defp period_within?({:range, from, to}, %{first_date: %Date{} = first, today: %Date{} = today}),
    do: Date.compare(from, today) != :gt and Date.compare(to, first) != :lt

  defp period_within?(_period, _analysis), do: false

  # The address's period applied after a patch (a reload, a link, the
  # browser's memory, back and forward): an invalid one is 1 year with the
  # line; one the page already shows changes nothing.
  defp sync_period(socket, params) do
    case address_period(params) do
      :invalid ->
        socket = if socket.assigns.period == "1y", do: socket, else: put_period(socket, "1y")
        assign(socket, :range_error, :arrival)

      found ->
        period = with {:ok, period} <- found, do: period, else: (_none -> "1y")

        if period == socket.assigns.period do
          socket
        else
          socket |> assign(:period_unchecked, not is_binary(period)) |> put_period(period)
        end
    end
  end

  # An arrival's year or range outside the analysis (a link to a year
  # without bookings, a range before the history) is 1 year with one line
  # saying so; the address is replaced and the browser's memory told, so a
  # return does not ask for it again.
  defp check_period(socket, analysis \\ nil)

  defp check_period(%{assigns: %{period_unchecked: true}} = socket, analysis)
       when is_map(analysis) or is_map(socket.assigns.analysis) do
    analysis = analysis || socket.assigns.analysis
    socket = assign(socket, :period_unchecked, false)

    if period_within?(socket.assigns.period, analysis) do
      socket
    else
      socket
      |> put_period("1y")
      |> assign(:range_error, :arrival)
      |> push_event("period-memory", %{period: period_memory("1y")})
      |> push_patch(to: with_period(socket.assigns.current_path, "1y"), replace: true)
    end
  end

  defp check_period(socket, _analysis), do: socket

  # The Wealth area's active tab (ADR-0022): the tab bar navigates with plain
  # links, so the choice arrives as a query param on mount.
  defp wealth_tab(%{"tab" => "allocation"}), do: :allocation
  defp wealth_tab(_params), do: :holdings

  defp wealth_tab_path(:allocation), do: "/portfolio?tab=allocation"
  defp wealth_tab_path(_tab), do: "/portfolio"

  # The Wealth tabs (#1432): Holdings and Allocation & targets are this
  # page, so their links keep the period; the other tabs are pages of
  # their own.
  defp wealth_tabs(current, period) do
    for tab <- AppShell.wealth_tabs(current) do
      if String.starts_with?(tab.href, "/portfolio"),
        do: %{tab | href: with_period(tab.href, period)},
        else: tab
    end
  end

  # The explicit ?view= the page's links may carry: the one in the address
  # when it is the remembered choice the session holds. A view that arrived
  # from another site is not in the session (`PortfolixirWeb.FetchSite`), so
  # the page shows it but its links do not pass it on: a click on one is a
  # request from the instance, which would remember it (E25 S7 review round,
  # S7E-2).
  defp carried_view(%{"view" => view}, session) when is_binary(view) do
    if PortfolixirWeb.ViewScope.choice(view) ==
         Map.get(session, PortfolixirWeb.ViewScope.session_key()),
       do: view
  end

  defp carried_view(_params, _session), do: nil

  # Merges the carried ?view= into current_path (same query-merging pattern as
  # the switcher's own hrefs), so the tab bar and the locale switcher — which
  # derive their links from current_path — carry the picked view along
  # instead of dropping it.
  defp keep_view_param(path, view) when is_binary(view) do
    uri = URI.parse(path)

    query =
      (uri.query || "")
      |> URI.decode_query()
      |> Map.put("view", view)
      |> URI.encode_query()

    URI.to_string(%{uri | query: query})
  end

  defp keep_view_param(path, _view), do: path

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
          # The mount's carried view, never the address's own (S7E-2): an
          # allocation patch keeps what the page's links may pass on.
          allocation_current_path(
            socket.assigns.carried_view,
            classification_id,
            allocation_mode,
            min_drift_pp,
            "1y"
          )

        # Holdings carries the stacked chart's choices (I23), so a locale
        # or privacy switch keeps them; an address naming no level keeps
        # naming none, so it reopens the TTWROR series (FR-56, FR-57).
        _holdings ->
          stack_path(
            socket.assigns.carried_view,
            param_stack(params, socket.assigns.classifications),
            "1y"
          )
      end

    socket = sync_period(socket, params)

    socket =
      socket
      |> assign(:allocation_mode, allocation_mode)
      |> assign(:min_drift_pp, min_drift_pp)
      # #1432: the period rides every link the page builds from here.
      |> assign(:current_path, with_period(current_path, socket.assigns.period))
      |> apply_stack(param_stack(params, socket.assigns.classifications))
      |> check_period()

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
        socket.assigns.classification_id && Integer.to_string(socket.assigns.classification_id)
      ) or
        present_but_stale?(params["alloc"], allocation_mode_param(socket.assigns.allocation_mode)) or
        present_but_stale?(params["drift"], socket.assigns.min_drift_pp) or
        address_period(params) == :invalid

    if connected?(socket) and stale? do
      # current_path IS the canonical allocation path (assigned above).
      push_patch(socket, to: socket.assigns.current_path, replace: true)
    else
      socket
    end
  end

  # An invalid period on the address (#1432) is replaced by the page's own
  # address, which names 1 year by naming none.
  defp maybe_canonicalize_patch(socket, params) do
    if connected?(socket) and address_period(params) == :invalid do
      push_patch(socket, to: socket.assigns.current_path, replace: true)
    else
      socket
    end
  end

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

  # -- the stacked chart's address (I23, FR-53) ----------------------------------

  # The stack the address names: the level (`category` unless `level=total`
  # or `level=security`: „Kategorien“ is the screen's default, FR-56; the
  # API's own default is unchanged), the tree (`tree=`, a loaded classification, else
  # the bands' own default), the filter (`category=`, a category's id or
  # `unclassified`, at every level, FR-56) and the sort (`sort=change`, else
  # size). Every value is matched against a whitelist or parsed as an id,
  # never made an atom (AGENTS.md); an unknown one falls back to its default.
  #
  # FR-57 (Sprint 28 S4): the series rides the address as it did, by the
  # level: an address naming a level opens the value series, and with
  # `scale=ttwror` the TTWROR series at that level, each band a line. An
  # address naming none (`named: false`) opens the TTWROR series at „Gesamt“,
  # today's line and its benchmarks; „Wert“ from there opens „Kategorien“,
  # the value series' default (S1). Once a level is named, both series keep
  # it, and the filter.
  defp param_stack(params, classifications) do
    named = stack_addressed?(params)

    if named,
      do: named_stack(params, classifications),
      else: %{
        level: :total,
        tree: nil,
        category: nil,
        sort: :size,
        scale: :ttwror,
        axis: :window,
        named: false
      }
  end

  defp named_stack(params, classifications) do
    level =
      case params["level"] do
        "total" -> :total
        "security" -> :security
        _other -> :category
      end

    category = param_filter(params["category"])

    tree =
      with true <- level != :total or not is_nil(category),
           raw when is_binary(raw) <- params["tree"],
           {:ok, id} <- LiveParam.fetch_id(raw),
           true <- Enum.any?(classifications, &(&1.id == id)) do
        id
      else
        _none -> nil
      end

    sort = if level != :total and params["sort"] == "change", do: :change, else: :size
    scale = if params["scale"] == "ttwror", do: :ttwror, else: :value
    # I43 (Sprint 30 W1): where the Total line's axis starts, „ab 0“ only
    # by name; anything else is the default, „Ausschnitt“.
    axis = if params["axis"] == "zero", do: :zero, else: :window

    %{
      level: level,
      tree: tree,
      category: category,
      sort: sort,
      scale: scale,
      axis: axis,
      named: true
    }
  end

  # The filter on the address: a category's id or the unassigned rest.
  defp param_filter("unclassified"), do: :unclassified

  defp param_filter(raw) when is_binary(raw) do
    case LiveParam.fetch_id(raw) do
      {:ok, id} -> id
      _invalid -> nil
    end
  end

  defp param_filter(_none), do: nil

  # The stack's own basis line stands under its figure once its bands
  # have landed with a window (#1366, board 07 ②), or its lines (FR-57).
  defp stack_basis_shown?(stack, %{bands: [_ | _]}), do: stacked?(stack)
  defp stack_basis_shown?(stack, %{parent: %{}}), do: stacked?(stack)
  defp stack_basis_shown?(_stack, _bands), do: false

  # UX-DR26: the deliberate limit stated where the overlay is missing — a
  # rebased return has no value axis. One „%“ (#1366: `%%` printed as is).
  defp benchmark_value_note(currency),
    do:
      gettext(
        "Benchmarks are drawn in the % (TTWROR) view only — they have no value in %{currency}.",
        currency: currency
      )

  # FR-57: the benchmarks are drawn over the view's own line, the TTWROR
  # series at „Gesamt“ without a filter; the lines say so behind their ⓘ.
  defp benchmark_lines_note,
    do:
      gettext(
        "Benchmarks are drawn over the view's own line, at the level Total without a filter."
      )

  # I43 (board 01, answer C): the axis switch stands where the chart under
  # the bar is the Total value line in an amount: „Gesamt“ without a filter,
  # „Wert“, not in the privacy mode, whose axis reads in percent. nil hides
  # it.
  defp axis_switch(%{level: :total, category: nil, scale: :value, axis: axis}) do
    if PrivacyMode.on?(), do: nil, else: axis
  end

  defp axis_switch(_stack), do: nil

  # The stack draws bands: every level but the plain total, which is today's
  # value line; the total with a filter is the filter's own band (FR-56).
  defp stacked?(%{level: :total, category: nil}), do: false
  defp stacked?(_stack), do: true

  # The series a stack is drawn in (FR-57): the value series, or the
  # TTWROR series, at its level.
  defp chart_mode_of(%{scale: :value}), do: "value"
  defp chart_mode_of(_stack), do: "ttwror"

  defp stack_addressed?(params), do: params["level"] in ["total", "category", "security"]

  # The address of a stack on Holdings: the carried view, then the level
  # (always, so the link opens the series it names), the tree, the category,
  # the sort and the TTWROR series (FR-57), each only when it is not the
  # default, in this order so the links compare equal; the period last
  # (#1432). A stack whose level the address does not name is the carried
  # view alone: the TTWROR series at „Gesamt“. I43 (board 01): `axis=zero`
  # right after the level, only when chosen; it rides every link of the
  # bar, so a way through „Kategorien“ back to „Gesamt“ keeps it.
  defp stack_path(view, %{named: false}, period),
    do: pairs_path(view_pairs(view) ++ period_pairs(period))

  defp stack_path(view, stack, period) do
    pairs =
      view_pairs(view) ++
        [{"level", Atom.to_string(stack.level)}] ++
        if(stack.axis == :zero, do: [{"axis", "zero"}], else: []) ++
        if(stack.tree && stacked?(stack),
          do: [{"tree", Integer.to_string(stack.tree)}],
          else: []
        ) ++
        if(stack.category, do: [{"category", category_param(stack.category)}], else: []) ++
        if(stack.sort == :change and stack.level != :total, do: [{"sort", "change"}], else: []) ++
        if(stack.scale == :ttwror, do: [{"scale", "ttwror"}], else: []) ++
        period_pairs(period)

    pairs_path(pairs)
  end

  # The stack a series switch asks for (FR-57): the level and the filter
  # kept; from an address naming no level, the value series opens at
  # „Kategorien“, its default (FR-56).
  defp series_stack(stack, "ttwror"), do: %{stack | scale: :ttwror}
  defp series_stack(%{named: true} = stack, "value"), do: %{stack | scale: :value}

  defp series_stack(stack, "value"),
    do: %{stack | scale: :value, level: :category, named: true}

  defp category_param(:unclassified), do: "unclassified"
  defp category_param(id), do: Integer.to_string(id)

  defp pairs_path([]), do: "/portfolio"
  defp pairs_path(pairs), do: "/portfolio?" <> URI.encode_query(pairs)

  # The address with one choice of the bar made: a level keeps the filter
  # (FR-56, board 02 ③).
  defp stack_choice(stack, level) when level in [:total, :category, :security],
    do: %{stack | level: level, named: true}

  defp stack_choice(stack, sort) when sort in [:size, :change],
    do: %{stack | sort: sort, named: true}

  defp stack_choice(stack, axis) when axis in [:window, :zero],
    do: %{stack | axis: axis, named: true}

  defp stack_paths(view, stack, period) do
    Map.new([:total, :category, :security, :size, :change, :window, :zero], fn choice ->
      {choice, stack_path(view, stack_choice(stack, choice), period)}
    end)
  end

  # The breadcrumb: where the filter is in its tree, each step up a link
  # that keeps the level (FR-56: one level at a time), „All categories“ the
  # stack without a filter. The plain total has none.
  defp stack_crumbs(view, %{category: category} = stack, bands, ancestors, period)
       when not is_nil(category) do
    up = fn id -> stack_path(view, %{stack | category: id}, period) end

    name =
      case {category, bands} do
        {:unclassified, _bands} -> gettext("Unassigned")
        {id, %{category: %{id: id, name: name}}} -> name
        _loading -> "…"
      end

    [{gettext("All categories"), up.(nil)}] ++
      Enum.map(ancestors, fn ancestor -> {ancestor.name, up.(ancestor.id)} end) ++
      [{name, nil}]
  end

  defp stack_crumbs(_view, stack, _bands, _ancestors, _period) do
    if stacked?(stack), do: [{gettext("All categories"), nil}], else: []
  end

  # The tree the bar's chooser shows: the one the stack answered with, else
  # the address's.
  defp stack_classification_id(_stack, %{classification: %{id: id}}), do: id
  defp stack_classification_id(stack, _bands), do: stack.tree

  # The addresses a band and its legend row open at the category level
  # (FR-56): a category, or the unassigned rest, as the filter, the level,
  # the tree and the sort kept. Cash, „Other“, „(direct)“ and the filter's
  # own band open nothing.
  defp drill_paths(view, stack, %{level: :category, bands: bands} = result, period) do
    for band <- bands, filter = band_filter(band, result), into: %{} do
      {band.key, stack_path(view, %{stack | category: filter}, period)}
    end
  end

  defp drill_paths(_view, _stack, _bands, _period), do: %{}

  defp band_filter(%{kind: :category, id: id}, %{category_id: filter}) when id != filter, do: id
  defp band_filter(%{kind: :unclassified}, %{category_id: nil}), do: :unclassified
  defp band_filter(_band, _result), do: nil

  # The filter a band's click asks for, when a band of the stack shown
  # offers it.

  defp clicked_filter(raw, %{level: :category, bands: bands} = result) do
    Enum.find_value(bands, fn band ->
      filter = band_filter(band, result)
      if filter && category_param(filter) == raw, do: filter
    end)
  end

  defp clicked_filter(_raw, _result), do: nil

  # A new stack from the address: the value series it belongs to, and its
  # bands loaded. The same stack again (the initial mount, a patch of
  # another choice) changes nothing.
  defp apply_stack(%{assigns: %{stack: stack}} = socket, stack), do: socket

  defp apply_stack(socket, stack) do
    socket =
      socket
      |> focus_crumb_after_drill(socket.assigns.stack, stack)
      |> assign(:stack, stack)

    socket
    |> assign(:chart_mode, chart_mode_of(stack))
    |> load_bands()
  end

  # The internal mode atom as the short URL value (`:flat` reads as "positions",
  # matching the button label and the flat worklist).
  defp allocation_mode_param(:flat), do: "positions"
  defp allocation_mode_param(:tree), do: "tree"

  # The tree/positions toggle button values map to the internal atoms without
  # `String.to_atom/1` on raw input (AGENTS.md): explicit whitelist only.

  # The allocation tab's canonical path: tab, the active view (only when
  # explicitly chosen), the classification and the mode, in a deterministic
  # order so the switchers merge cleanly and a reconnect reconstructs the state.
  defp allocation_current_path(view, classification_id, allocation_mode, min_drift_pp, period) do
    pairs =
      [{"tab", "allocation"}] ++
        view_pairs(view) ++
        classification_pairs(classification_id) ++
        [{"alloc", allocation_mode_param(allocation_mode)}] ++
        drift_pairs(min_drift_pp) ++ period_pairs(period)

    "/portfolio?" <> URI.encode_query(pairs)
  end

  # #1366: without any classification there is no tree to name.
  defp classification_pairs(id) when is_integer(id),
    do: [{"classification", Integer.to_string(id)}]

  defp classification_pairs(_id), do: []

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
      |> load_contribution()
      |> load_bands()
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

    CappedAsync.start_async(socket, :overview, fn ->
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
             allocation_for(portfolio_id, classification_id,
               view: view_id,
               pricing_context: context
             ) do
        # Negative-holdings debris (#570) is a property of the dataset, not
        # of the active view, so the report is global and loads with the
        # other data-quality inputs. A bond priced on two scales (#330,
        # ADR-0052) is named where it inflates this total: among the
        # positions the valuation holds; so is a position whose quotes
        # contradict its own bookings (#1101, D-7). The twin cash accounts'
        # portfolio tags (#1333) load here too, not in the page process each
        # time this lands (#1366).
        {valuation, classification_id, allocation, Ledger.negative_holdings_report(),
         DataNotesWidget.two_scales_in(valuation),
         DataNotesWidget.implausible_quotes_in(valuation), AccountNames.load_portfolio_tags()}
      else
        {:error, :view_not_found} -> :view_not_found
        {:error, :not_found} -> :classification_not_found
      end
    end)
  end

  # #1366: no classification, no allocation; the tab says so. Sprint 32
  # W2: the read is the allocation section's, the widget's too.
  defp allocation_for(portfolio_id, classification_id, opts),
    do: AllocationWidget.allocation_for(portfolio_id, classification_id, opts)

  defp load_allocation(socket) do
    socket = ensure_live_view_scope(socket)
    portfolio_id = socket.assigns.portfolio.id
    classification_id = socket.assigns.classification_id
    view_id = socket.assigns[:active_view_id]

    CappedAsync.start_async(socket, :allocation, fn ->
      case allocation_for(portfolio_id, classification_id, view: view_id) do
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
    |> assign(:analysis_read, nil)
    |> serve_previous_analysis(view_id, base_currency)
    |> CappedAsync.start_async(:performance, fn ->
      read(view_id, fn -> Performance.view_analysis(view_id, base_currency: base_currency) end)
    end)
  end

  # FR-41 (ADR-0051 §12, board pick A): the contribution table under the
  # chart reads the section's period and the page's view over the walk's own
  # scope — the view across all portfolios, Everything when none is picked —
  # in the same base currency, so its sum row is the badge's money figure.
  # Unlike the badge it is not a re-chain of the cached walk: each period
  # runs its own windowed walk (ADR-0051 §5), so it loads async on every
  # period change. The result names the period and view it was computed
  # for; one that no longer matches the page reloads instead of landing.
  # Only Holdings shows the table, so the other tab never pays for it.
  # One walk at a time (#1058): a period switch while a walk runs waits for
  # it as the latest ask, so a burst of switches runs the first walk and the
  # last, never one per period passed (`CappedAsync.start_latest/3`).
  defp load_contribution(%{assigns: %{wealth_tab: :holdings}} = socket) do
    socket = ensure_live_view_scope(socket)
    view_id = socket.assigns[:active_view_id]
    base_currency = socket.assigns.portfolio.base_currency_code
    period = socket.assigns.period

    socket
    |> assign(contribution: nil, contribution_read: nil, contribution_failed: false)
    |> CappedAsync.start_latest(:contribution, fn ->
      {period,
       read(view_id, fn ->
         Contribution.for_view(view_id, period: period, base_currency: base_currency)
       end)}
    end)
  end

  defp load_contribution(socket), do: socket

  # I23 (FR-53): the stacked chart's bands, read when the value series shows
  # a stacked level on Holdings, for the section's period and the page's
  # view over the walk's own scope, as the bands read answers it
  # (`GET /api/v1/performance/bands`, `…/views/:id/performance/bands`). Each
  # read runs its own windowed walk, so it loads one at a time as the
  # contribution table does; a result for another request is dropped.
  defp load_bands(%{assigns: %{wealth_tab: :holdings, stack: stack}} = socket) do
    cond do
      stacked?(stack) -> start_bands(socket)
      axis_switch(stack) == :zero -> start_stack_axis(socket)
      true -> socket
    end
  end

  defp load_bands(socket), do: socket

  # „ab 0“ (I43; the Sprint 30 closing act's design critic, finding 1): the
  # Total line is drawn on the axis of the stack at „Kategorien“ for the
  # same window and view, its floor below 0 included, so it reads the
  # stack's bands, the read „Kategorien“ itself makes (and the analytic
  # keeps for it). Until they land, and when they fail, the line spans
  # its own values from 0, which is the stack's axis wherever no band
  # dips below 0.
  defp start_stack_axis(socket) do
    socket = ensure_live_view_scope(socket)
    view_id = socket.assigns[:active_view_id]
    request = {:stack_axis, socket.assigns.period, view_id}

    if socket.assigns.stack_axis_for == request do
      socket
    else
      opts = [
        period: socket.assigns.period,
        base_currency: socket.assigns.portfolio.base_currency_code,
        level: :category
      ]

      socket
      |> assign(stack_axis: nil, stack_axis_for: request)
      |> CappedAsync.start_latest(:stack_axis, fn ->
        {request,
         case Bands.for_view(view_id, opts) do
           {:ok, result} -> StackedChart.value_axis(result)
           _error -> nil
         end}
      end)
    end
  end

  defp start_bands(socket) do
    socket = ensure_live_view_scope(socket)
    request = bands_request(socket)

    if socket.assigns.bands_for == request and not socket.assigns.bands_failed do
      socket
    else
      %{stack: stack, period: period} = socket.assigns
      view_id = socket.assigns[:active_view_id]
      portfolio_id = socket.assigns.portfolio.id
      base_currency = socket.assigns.portfolio.base_currency_code
      known = socket.assigns.allocation

      # A category names its own tree; the unassigned rest is the rest of
      # the tree the address names.
      opts =
        [
          period: period,
          base_currency: base_currency,
          level: stack.level,
          sort: stack.sort,
          scale: stack.scale
        ] ++
          if(stack.category, do: [category_id: stack.category], else: []) ++
          if(stack.tree && not is_integer(stack.category),
            do: [classification_id: stack.tree],
            else: []
          )

      # I34 step 2: the memo is asked first, in this process. A hit is
      # drawn in this render, never behind the skeleton; a miss loads in
      # the background as before. A read still running for an earlier
      # request lands later and is dropped (`bands_landed/2`).
      case Bands.cached_for_view(view_id, opts) do
        {:ok, result} ->
          socket
          |> assign(:bands_for, request)
          |> assign_bands(
            result,
            band_colors(result, portfolio_id, view_id, known),
            filter_ancestors(result)
          )

        :miss ->
          socket
          |> assign(
            bands: nil,
            bands_colors: %{},
            bands_ancestors: [],
            bands_for: request,
            bands_failed: false
          )
          |> CappedAsync.start_latest(:bands, fn ->
            {request,
             case Bands.for_view(view_id, opts) do
               {:ok, result} ->
                 {:ok, result, band_colors(result, portfolio_id, view_id, known),
                  filter_ancestors(result)}

               error ->
                 error
             end}
          end)
      end
    end
  end

  # The filtered category's ancestors, its root first, for the breadcrumb's
  # steps up (FR-56); a broken or cyclic parent chain stops where it breaks.
  defp filter_ancestors(%{category: %{id: id}}) do
    case Classifications.get_category(id) do
      nil -> []
      category -> ancestors(category.parent_id, [id])
    end
  end

  defp filter_ancestors(_result), do: []

  defp ancestors(nil, _seen), do: []

  defp ancestors(id, seen) do
    with false <- id in seen,
         %{} = category <- Classifications.get_category(id) do
      ancestors(category.parent_id, [id | seen]) ++ [%{id: category.id, name: category.name}]
    else
      _stop -> []
    end
  end

  # A drill into a category, or the breadcrumb's way back, removes the link
  # that had the focus; the focus moves to the breadcrumb's current item,
  # never to <body> (the closing act's design critic, D5; WCAG 2.4.3).
  defp focus_crumb_after_drill(socket, %{category: before}, %{category: now})
       when before != now,
       do: push_event(socket, "focus-into-view", %{id: "stack-crumbs-current"})

  defp focus_crumb_after_drill(socket, _before, _now), do: socket

  # The axis (I43) is the line's, never the bands'.
  defp bands_request(socket),
    do:
      {Map.delete(socket.assigns.stack, :axis), socket.assigns.period,
       socket.assigns[:active_view_id]}

  # Each band's colour (the owner, 2026-11-07): a category the colour the
  # allocation sunburst draws it in for the same tree and view, so it looks
  # the same on both tabs; a category the sunburst does not draw (nothing
  # held today, no target) its own colour, else the palette at its place in
  # the tree. Securities take the palette's hues in order of size, the
  # largest first, whatever the sort; cash the cash colour, the unclassified
  # rest grey, "Other" the neutral token (`:other`, drawn by CSS). Under a
  # filter the sub-categories take the palette in order of size too, as a
  # drilled category's securities do, and „‹name› (direct)“ the colour after
  # them, the last (FR-56, plan D-6, board 02).
  defp band_colors(result, portfolio_id, view_id, known) do
    sunburst =
      case result do
        %{level: :category, category_id: nil, classification: %{id: id}} ->
          sunburst_colors(id, portfolio_id, view_id, known)

        _other ->
          %{}
      end

    ranked = if result.category_id, do: [:security, :category], else: [:security]

    ranks =
      result.bands
      |> Enum.filter(&(&1.kind in ranked))
      |> Enum.sort_by(&{Decimal.negate(&1.end_value), &1.name}, fn {a, an}, {b, bn} ->
        case Decimal.compare(a, b) do
          :lt -> true
          :gt -> false
          :eq -> an <= bn
        end
      end)
      |> Enum.with_index()
      |> Map.new(fn {band, index} -> {band.key, index} end)

    Map.new(result.bands, fn band -> {band.key, band_color(band, sunburst, ranks)} end)
  end

  defp band_color(%{kind: :direct}, _sunburst, ranks), do: CategoryColors.at(map_size(ranks))

  defp band_color(%{kind: :category, key: key}, _sunburst, ranks)
       when is_map_key(ranks, key),
       do: CategoryColors.at(Map.fetch!(ranks, key))

  defp band_color(%{kind: :cash}, _sunburst, _ranks), do: @cash_color
  defp band_color(%{kind: :unclassified}, _sunburst, _ranks), do: @unassigned_color
  defp band_color(%{kind: :other}, _sunburst, _ranks), do: :other

  defp band_color(%{kind: :security, key: key}, _sunburst, ranks),
    do: CategoryColors.at(Map.fetch!(ranks, key))

  defp band_color(%{kind: :category} = band, sunburst, _ranks),
    do: Map.get(sunburst, band.id) || band.color || CategoryColors.at(band.tree_index || 0)

  defp band_color(_band, _sunburst, _ranks), do: nil

  # The sunburst's colours for one tree: the page's loaded allocation when
  # it is that tree's, else the same allocation read the sunburst makes.
  defp sunburst_colors(id, _portfolio_id, _view_id, %{classification_id: id} = known),
    do: Map.new(known.categories, &{&1.category_id, &1.color})

  defp sunburst_colors(id, portfolio_id, view_id, _known) do
    case Allocation.for_portfolio(portfolio_id, id, view: view_id) do
      {:ok, allocation} -> CategoryColors.by_category(allocation.categories)
      {:error, _reason} -> %{}
    end
  end

  # Which data a read answered from (FR-41 review round): its view, and the
  # day and the global data version (`Performance.data_state/0`) taken before
  # and after it ran. A write that lands while it runs makes it `:unsettled`
  # — the walk reads in several queries, so it may have seen part of that
  # write.
  defp read(view_id, fun) do
    before = Performance.data_state()
    result = fun.()
    {result, %{view: view_id, state: settled(before, Performance.data_state())}}
  end

  defp settled(state, state), do: state
  defp settled(_before, _after), do: :unsettled

  # The table's sum is the badge's money figure only when both answer from
  # the same data (ADR-0051 §12), but the badge re-chains the walk the page
  # cached while the table walks afresh per period: a write behind the open
  # page (a second tab, an agent, an import, the background sync), a view
  # deleted in another tab or midnight passing would let the two disagree
  # without a word. Once both have landed, the one that read older data is
  # read again: a superseded badge as ADR-0032 §6's labelled stale series,
  # which keeps the table on its skeleton until the fresh walk lands.
  defp reconcile_reads(%{assigns: %{analysis_read: a, contribution_read: c}} = socket)
       when is_nil(a) or is_nil(c),
       do: socket

  defp reconcile_reads(%{assigns: %{analysis_read: a, contribution_read: c}} = socket) do
    cond do
      a.view != socket.assigns[:active_view_id] -> supersede_performance(socket)
      c.state == :unsettled -> load_contribution(socket)
      a.state == :unsettled -> supersede_performance(socket)
      a.state == c.state -> socket
      newer?(c.state, a.state) -> supersede_performance(socket)
      true -> load_contribution(socket)
    end
  end

  defp newer?({day, version}, {other_day, other_version}) do
    case Date.compare(day, other_day) do
      :eq -> version > other_version
      order -> order == :gt
    end
  end

  # The shown series is superseded: it stays on screen, labelled stale, until
  # the fresh walk lands (ADR-0032 §6) — even when no memoised previous walk
  # exists to serve in its place.
  defp supersede_performance(socket) do
    socket = load_performance(socket)
    assign(socket, :performance_stale, not is_nil(socket.assigns.analysis))
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
    # #1124: the positions table follows the page back to Everything.
    |> assign_holding_rows()
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

  def handle_async(:performance, {:ok, {{:error, :view_not_found}, _read}}, socket) do
    {:noreply, socket |> degrade_to_everything() |> load_performance()}
  end

  # #1058: a walk an ask waited for is dropped, and the waiting walk, just
  # started, is the one whose result lands.
  # I23: the stack lands only for the request the page still shows.
  def handle_async(:bands, result, socket) do
    case CappedAsync.landed(socket, :bands) do
      {:superseded, socket} -> {:noreply, socket}
      {:current, socket} -> bands_landed(result, socket)
    end
  end

  def handle_async(:stack_axis, result, socket) do
    case CappedAsync.landed(socket, :stack_axis) do
      {:superseded, socket} -> {:noreply, socket}
      {:current, socket} -> {:noreply, stack_axis_landed(result, socket)}
    end
  end

  def handle_async(:contribution, result, socket) do
    case CappedAsync.landed(socket, :contribution) do
      {:superseded, socket} -> {:noreply, socket}
      {:current, socket} -> contribution_landed(result, socket)
    end
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
        {:ok,
         {valuation, classification_id, allocation, negative_report, two_scales,
          implausible_quotes, account_portfolio_tags}},
        socket
      ) do
    socket =
      socket
      |> assign(:valuation, valuation)
      # #1333 (D-9's finding for U2): a twin cash account's portfolio beside
      # its name in the cash table, decided over every account.
      |> assign(:account_portfolio_tags, account_portfolio_tags)
      # #1332 (D-9): the positions' market values are the ones this total
      # sums, so they land with it.
      |> assign_base_values(valuation)
      |> assign(:negative_report, negative_report)
      |> assign(:two_scales, two_scales)
      |> assign(:implausible_quotes, implausible_quotes)

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
  def handle_async(:performance, {:ok, {analysis, read}}, socket) do
    # #1432: an arrival's year or range is checked against the analysis
    # first, so the summary below is the period the page will show.
    socket = check_period(socket, analysis)

    case Performance.summarise(analysis, socket.assigns.period) do
      {:ok, performance} ->
        {:noreply,
         socket
         |> assign(
           analysis: analysis,
           analysis_read: read,
           performance: performance,
           performance_stale: false,
           performance_failed: false
         )
         |> assign_comparisons()
         |> reconcile_reads()}

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
     |> load_performance()
     |> load_contribution()
     |> assign(bands_for: nil, stack_axis_for: nil)
     |> load_bands()}
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

  defp bands_landed({:ok, {request, answer}}, socket) do
    if request == bands_request(socket),
      do: bands_answer(answer, socket),
      else: {:noreply, socket}
  end

  defp bands_landed({:exit, _reason}, socket), do: {:noreply, assign(socket, :bands_failed, true)}

  # A failed read leaves the line on its own axis from 0.
  defp stack_axis_landed({:ok, {request, axis}}, %{assigns: %{stack_axis_for: request}} = socket),
    do: assign(socket, :stack_axis, axis)

  defp stack_axis_landed(_other, socket), do: socket

  defp bands_answer({:ok, result, colors, ancestors}, socket),
    do: {:noreply, assign_bands(socket, result, colors, ancestors)}

  defp bands_answer({:error, :view_not_found}, socket),
    do: {:noreply, socket |> degrade_to_everything() |> assign(:bands_for, nil) |> load_bands()}

  # A filtered category or a tree that is gone (deleted in another tab, a
  # stale link) falls back to the same level without the filter (FR-56):
  # the address is replaced once, so it never advertises a stack the page
  # does not show.
  defp bands_answer({:error, reason}, socket)
       when reason in [
              :category_not_found,
              :category_outside_classification,
              :classification_not_found
            ] do
    stack = %{socket.assigns.stack | category: nil}
    stack = if reason == :classification_not_found, do: %{stack | tree: nil}, else: stack

    {:noreply,
     push_patch(socket,
       to: stack_path(socket.assigns.carried_view, stack, socket.assigns.period),
       replace: true
     )}
  end

  defp bands_answer({:error, _reason}, socket),
    do: {:noreply, assign(socket, :bands_failed, true)}

  # A stack's answer on the page: landed from its read, or a memo hit.
  defp assign_bands(socket, result, colors, ancestors),
    do:
      assign(socket,
        bands: result,
        bands_colors: colors,
        bands_ancestors: ancestors,
        bands_failed: false
      )

  defp contribution_landed({:ok, {_period, {{:error, :view_not_found}, _read}}}, socket) do
    {:noreply, socket |> degrade_to_everything() |> load_contribution()}
  end

  # FR-41: the table lands only for the period and view the page still
  # shows; a result for another (the view degraded to Everything meanwhile)
  # is recomputed for the current one rather than left as a skeleton.
  defp contribution_landed({:ok, {period, {{:ok, contribution}, read}}}, socket) do
    if period == socket.assigns.period and read.view == socket.assigns[:active_view_id] do
      {:noreply,
       socket
       |> assign(contribution: contribution, contribution_read: read, contribution_failed: false)
       |> reconcile_reads()}
    else
      {:noreply, load_contribution(socket)}
    end
  end

  defp contribution_landed({:ok, {_period, {{:error, _reason}, _read}}}, socket) do
    {:noreply, assign(socket, :contribution_failed, true)}
  end

  defp contribution_landed({:exit, _reason}, socket) do
    {:noreply, assign(socket, :contribution_failed, true)}
  end

  @impl true
  # Ends the transient "✓ Up to date" confirmation in the sync button.
  def handle_info(:clear_fx_flash, socket) do
    {:noreply, assign(socket, :fx_sync_flash, false)}
  end

  # One landing spot for a loaded allocation: resolved display colours plus
  # the two lookups the collapsible tree needs (parent chain per category and
  # which categories have child categories).
  defp assign_allocation(socket, nil), do: assign(socket, :allocation, nil)

  # Sprint 32 W2: made ready by the allocation section's module.
  defp assign_allocation(socket, allocation) do
    %{allocation: allocation, parent_map: parent_map, parents_with_children: parents} =
      AllocationWidget.prepare(allocation)

    assign(socket,
      allocation: allocation,
      category_parent_map: parent_map,
      category_parents_with_children: parents
    )
  end

  @impl true
  def render(%{portfolio: nil} = assigns) do
    ~H"""
    <AppShell.shell page_address={@page_address} current_path={@current_path} page_title={gettext("Wealth")}>
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
    <AppShell.shell page_address={@page_address}
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

        <AppShell.area_tabs tabs={wealth_tabs(@wealth_tab, @period)} />

        <%!-- #1432 (D-A1): the browser's memory of the last period
             picked, read when the address names none and written at each
             pick; nothing of it reaches the server's storage. --%>
        <div
          id="period-memory"
          phx-hook="PeriodMemory"
          data-storage-key="wealth.period"
          data-addressed={to_string(@period_addressed)}
          hidden
        >
        </div>

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
        <section id="portfolio-kpis" class="workspace-section kpi-band" aria-label={gettext("Wealth key figures")}>
          <div class="kpi-band__lead">
            <article id="kpi-total" class="stat stat--lead">
              <span><%= gettext("Total incl. cash") %></span>
              <strong :if={@valuation}>
                <span
                  id="count-kpi-total"
                  class="count-up"
                  phx-hook="CountUp"
                  data-count-to={Format.amount_attribute(@valuation.total_with_cash)}
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
                <b class={money_sign_class(period_value_gain(@performance))}><%= signed_money(
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
                  data-count-to={Format.amount_attribute(@valuation.total_value)}
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
                  <%!-- #1086 (board 06): a no-break space binds "·" to the word
                       before it, so on a half-width card the separator ends
                       the label's first line instead of opening its second. --%>
                  <%= gettext("Opening value") %>&nbsp;· <%= gettext("net flows") %> (<%= period_label(
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
                <b class={money_sign_class(@performance.net_external_flows)}><%= Format.signed_decimal(
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
                ×<%= Format.plain_decimal(@performance.wealth_multiple, 2) %>
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
                  class={money_sign_class(comparison.savings_plan.end_value_delta)}
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
            <%!-- ADR-0046, amended 2026-11-04 (I17; board 02, A): the fees and
                 taxes the real portfolio booked in the comparison's window
                 and scope, once under the rows (the payload's costs_paid is
                 the same for every benchmark of one request). Beside the
                 gap, never subtracted from it, and no residual named. --%>
            <p :if={@comparisons != []} class="benchmark-costs" data-role="benchmark-costs">
              <%= costs_paid_line(hd(@comparisons)) %><%= costs_excluded_clause(
                hd(@comparisons).costs_paid.excluded
              ) %>
            </p>
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
                <span class="benchmark-costs__info"><%= costs_paid_info(@active_view_id) %></span>
              </p>
            </details>
          </article>
        </section>
        <% else %>
        <%!-- Sprint 32 W2: the line is drawn by the widget „Kennzahlen-Zeile“'s
             module, so Wealth and a dashboard draw it with one code path. --%>
        <SummaryLineWidget.line
          valuation={@valuation}
          performance={summary_performance(@performance, @performance_stale)}
          failed={@performance_failed}
          period_label={period_label(@period)}
          holdings_href={holdings_path(@current_path, @period)}
        />
        <% end %>

        <%!-- Wealth tabs (ADR-0022): Holdings carries the performance chart,
             data quality and cash; Allocation & targets carries the sunburst
             and drift table. KPIs and the view switcher head both. --%>
        <%= if @wealth_tab == :holdings do %>
          <.data_quality
            valuation={@valuation}
            analysis={@analysis}
            negative={@negative_report}
            two_scales={@two_scales}
            implausible_quotes={@implausible_quotes}
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
              <PerformanceSection.series_toggle mode={@chart_mode} value_label={value_series_label(assigns)} />
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
                      :if={@range_error in [:from, :to, :order]}
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
                   uses ({components.period-control}). LiveView removes
                   every attribute the server did not render, `open`
                   included, so a picker opened while the page's loads ran
                   folded shut when they landed; the shell's
                   `DisclosureState` hook restores it after each patch. --%>
              <PerformanceSection.benchmark_picker
                benchmarks={@benchmarks}
                groups={@benchmark_groups}
                action="/portfolio"
              />
            </div>
          </header>
          <%!-- #1432 (D-A1): a period the address asked for that is no
               period, or lies outside the analysis, opens at 1 year, and
               one line says so until the next pick. --%>
          <div :if={@range_error == :arrival} class="inline-result" role="status">
            <AppShell.data_note severity={:note} data-role="period-fallback">
              <%= gettext("The period asked for does not fit the data, so 1 year is shown.") %>
            </AppShell.data_note>
          </div>
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
            <PerformanceSection.badge performance={@performance} period_label={period_label(@period)} />
            <%!-- I23 (FR-53, board 01 A): the bar above the chart, in both
                 series since FR-57 (board 03); at the level Total without a
                 filter the chart under it is today's, unchanged. --%>
            <StackedChart.bar
              stack={@stack}
              paths={stack_paths(@carried_view, @stack, @period)}
              crumbs={stack_crumbs(@carried_view, @stack, @bands, @bands_ancestors, @period)}
              classifications={@classifications}
              classification_id={stack_classification_id(@stack, @bands)}
              axis={axis_switch(@stack)}
            />
            <%= if stacked?(@stack) do %>
              <%= cond do %>
                <% @bands && @bands.scale == :ttwror -> %>
                  <%!-- FR-57 (board 03): one line per band, the view's or
                       the filter's bold. --%>
                  <StackedChart.lines
                    result={@bands}
                    colors={@bands_colors}
                    drill_paths={drill_paths(@carried_view, @stack, @bands, @period)}
                    benchmark_note={if @benchmarks != [], do: benchmark_lines_note()}
                  />
                <% @bands -> %>
                  <StackedChart.figure
                    result={@bands}
                    colors={@bands_colors}
                    drill_paths={drill_paths(@carried_view, @stack, @bands, @period)}
                    benchmark_note={
                      if @benchmarks != [],
                        do: benchmark_value_note(@performance.base_currency)
                    }
                  />
                <% @bands_failed -> %>
                  <p class="alert-error" role="alert" data-role="stack-failed">
                    <%= gettext("Computation failed. Reload retries.") %>
                  </p>
                <% true -> %>
                  <div class="section-skeleton" data-role="stack-skeleton" role="status" aria-busy="true">
                    <span class="recomputing-cue">
                      <span class="spinner"></span> <%= gettext("computing") %>
                    </span>
                  </div>
              <% end %>
            <% else %>
              <PerformanceSection.chart
                series={PerformanceSection.downsample(@performance.series)}
                summary={PerformanceSection.table_summary(@performance.series)}
                mode={@chart_mode}
                currency={@performance.base_currency}
                overlays={PerformanceSection.benchmark_overlays(@chart_mode, @comparisons, @performance.series)}
                axis_start={@stack.axis}
                zero_axis={@stack_axis}
              />
            <% end %>
            <%!-- UX-DR26: a deliberate limit is stated where the overlay is
                 missing — a rebased return has no € axis. --%>
            <p
              :if={@chart_mode == "value" and @benchmarks != [] and not stacked?(@stack)}
              class="hint"
              data-role="benchmark-value-hint"
            >
              <%= benchmark_value_note(@performance.base_currency) %>
            </p>
            <%!-- UX-DR11 (Sprint 5 Lane D, decided outcome: split, then
                 delete half): the TTWROR definition lives ONLY in the
                 kpi-ttwror ⓘ tooltip; the chart keeps the period basis. --%>
            <%!-- The stack's own basis line carries the window and the
                 compute instant (board 07 ②), so it is not repeated. --%>
            <p
              :if={@performance.start_date && not stack_basis_shown?(@stack, @bands)}
              class="hint"
              data-role="performance-basis"
            >
              <%= Format.date(@performance.start_date) %> – <%= Format.date(@performance.end_date) %>
              <%!-- ADR-0039 C4 (FR-1 property 3): a served series is never
                   silent about freshness. For a durable value the compute
                   instant can predate the mount — data unchanged since. --%>
              <span :if={@performance.as_of} data-role="performance-as-of">
                · <%= gettext("computed %{at}", at: Format.utc_instant(@performance.as_of)) %>
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
            <%!-- FR-41 (ADR-0051 §12, board pick A): which position made how
                 much of the badge's money figure, directly under the chart,
                 under the same period control and view. While the badge shows
                 a superseded series the table waits, so its sum never answers
                 a figure the badge no longer shows. --%>
            <ContributionTable.table
              contribution={if @performance_stale, do: nil, else: @contribution}
              failed?={@contribution_failed or @performance_failed}
              show_all?={@contribution_show_all}
              period_label={period_label(@period)}
              view_name={active_view_name(@active_view)}
            />
          <% else %>
            <div class="section-skeleton" data-role="performance-skeleton" role="status" aria-busy="true">
              <span class="recomputing-cue">
                <span class="spinner"></span> <%= gettext("computing") %>
              </span>
            </div>
          <% end %>
        </section>
        <% end %>

        <%= if @wealth_tab == :allocation do %>
        <%!-- Sprint 32 W2: the section is drawn by the widget „Allokation“'s
             module, so Wealth and a dashboard draw it with one code path. --%>
        <section id="portfolio-allocation" class="workspace-section">
          <header class="section-head">
            <h2><%= gettext("Allocation") %></h2>
            <div class="section-head-controls">
              <AllocationWidget.controls
                mode={@allocation_mode}
                classifications={@classifications}
                classification_id={@classification_id}
              />
            </div>
          </header>
          <AllocationWidget.body
            allocation={@allocation}
            mode={@allocation_mode}
            classification_id={@classification_id}
            selected_segment={@selected_segment}
            expanded={@expanded_categories}
            parent_map={@category_parent_map}
            parents_with_children={@category_parents_with_children}
            min_drift_pp={@min_drift_pp}
            flat_sort={@flat_sort}
            currency={@valuation && @valuation.base_currency}
            view_id={@active_view_id}
            view_name={@active_view && @active_view.name}
          />
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
            <%!-- Sprint 32 W1: the picker and the table are the section
                 widget's „Positionen“, one code path for Wealth and a
                 dashboard. --%>
            <PositionsWidget.picker
              rows={@holding_rows}
              columns={@holdings_columns}
              picker_open?={@column_picker_open?}
            />
          </header>
          <PositionsWidget.table
            rows={@holding_rows}
            columns={@holdings_columns}
            base_currency={@portfolio.base_currency_code}
          />
        </section>
        <% end %>

        <%= if @wealth_tab == :holdings do %>
        <section id="portfolio-cash" class="workspace-section">
          <h2><%= gettext("Cash accounts") %></h2>
          <%!-- Sprint 32 W1: the table is the section widget's
               „Verrechnungskonten“, one code path for Wealth and a
               dashboard. --%>
          <%= if @valuation do %>
            <CashAccountsWidget.table valuation={@valuation} tags={@account_portfolio_tags} />
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

  # -- #814 holdings, Sprint 32 W1 ---------------------------------------------

  # The section's rows, cells and picker moved to the section widget
  # „Positionen“ (`PortfolixirWeb.Dashboard.Widgets.Positions`), which
  # Wealth and a dashboard draw with. #1124 (Sprint 20 plan D-8): the rows
  # read the scope the page reads (ADR-0024); a view gone since the page
  # resolved it degrades the page to Everything, the way every other
  # section's read does.
  defp assign_holding_rows(socket) do
    case PositionsWidget.rows(socket.assigns[:active_view_id]) do
      {:ok, rows} ->
        assign(socket, :holding_rows, base_values(rows, socket.assigns[:valuation], socket))

      {:error, :view_not_found} ->
        degrade_to_everything(socket)
    end
  end

  # #1332 and the D-9 finding (board 02 ①): the market value is the view
  # valuation's own for the same (depot, security), in the page
  # portfolio's base currency (`PositionsWidget.put_base_values/3`).
  defp assign_base_values(%{assigns: %{holding_rows: rows}} = socket, valuation),
    do: assign(socket, :holding_rows, base_values(rows, valuation, socket))

  defp assign_base_values(socket, _valuation), do: socket

  defp base_values(rows, valuation, socket),
    do:
      PositionsWidget.put_base_values(
        rows,
        valuation,
        socket.assigns.portfolio.base_currency_code
      )

  # -- components -------------------------------------------------------------

  # Surfaces why the totals can deviate from the user's expectation (the
  # section „Data quality“). Sprint 32 W1: its notes and their findings are
  # the section widget's „Datenhinweise“ (`DataNotesWidget`), one code path
  # for Wealth and a dashboard; the exchange-rate remedy, a write, stays
  # here as the notes' `fx_sync` slot.
  defp data_quality(assigns) do
    assigns = assign(assigns, :f, DataNotesWidget.findings(assigns))

    ~H"""
    <section
      :if={DataNotesWidget.any?(@f)}
      id="portfolio-data-quality"
      class="workspace-section data-quality"
    >
      <h2><%= gettext("Data quality") %></h2>
      <DataNotesWidget.notes f={@f}>
        <:fx_sync>
          <.fx_sync_control syncing={@fx_syncing} flash={@fx_sync_flash} result={@fx_sync_result} />
        </:fx_sync>
      </DataNotesWidget.notes>
    </section>
    """
  end

  # The raw render of the two-scales entries is pinned against this name
  # (bond_master_data_live_test.exs); the entries live with the notes.
  @doc false
  def two_scales_entries(assigns), do: DataNotesWidget.two_scales_entries(assigns)

  # The display currency for user-facing labels (ADR-0024): taken from the
  # loaded valuation (the number the label describes), with the EUR hub as the
  # fallback before the async read lands — never from portfolio naming.
  defp display_currency(%{valuation: %{base_currency: currency}}), do: currency
  defp display_currency(%{performance: %{base_currency: currency}}), do: currency
  defp display_currency(_assigns), do: "EUR"

  # -- benchmark comparison (ADR-0046 §4) ---------------------------------------

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
      # Every other parameter of the link rides along as it came (M-8): the
      # redirect changes the benchmark only, never the period or the view.
      |> LiveParam.carried()
      |> Kernel.++(Enum.map(Enum.uniq(selectors), &{"benchmark[]", &1}))
      |> Kernel.++([{"benchmark_merged", Enum.map_join(merged, ",", &elem(&1, 0))}])
      |> URI.encode_query()

    "/portfolio?" <> query
  end

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
  # The costs line (ADR-0046, amended 2026-11-04; board 02, A): the payload's
  # two sums as the money formatter writes them, each figure in its own span.
  # The space before each figure is a no-break space, in every language, so
  # a narrow line never ends on „Steuern“ with its figure below (closing
  # act, B2).
  defp costs_paid_line(%{costs_paid: costs, base_currency: currency}) do
    gettext("Paid in the period: fees %{fees} · taxes %{taxes}; the benchmark pays none.",
      fees: StoredText.slot(:fees),
      taxes: StoredText.slot(:taxes)
    )
    |> String.replace(~r/ (?=\x{0})/u, "\u00a0")
    |> StoredText.isolate(
      fees: costs_figure(costs.fees, currency),
      taxes: costs_figure(costs.taxes, currency)
    )
  end

  # A cost with no stored rate on its booking day is in neither sum and
  # named on the line by count and currency (the amendment's point 2), as
  # the payload's costs_paid.excluded names it.
  defp costs_excluded_clause(%{count: 0}), do: ""

  defp costs_excluded_clause(%{count: count, currencies: currencies}) do
    {:safe,
     [
       " ",
       ~s(<span class="benchmark-costs__excluded" data-role="benchmark-costs-excluded">),
       Phoenix.HTML.safe_to_string(
         Phoenix.HTML.html_escape(
           ngettext(
             "%{count} cost in %{currencies} has no stored rate on its booking day and is not included.",
             "%{count} costs in %{currencies} have no stored rate on their booking days and are not included.",
             count,
             currencies: Enum.join(currencies, ", ")
           )
         )
       ),
       "</span>"
     ]}
  end

  # The ⓘ's sentence names what was summed for the page's scope: the total
  # spans every portfolio; a view counts a cost where its cash account
  # counts (the amendment's point 3), so only a view speaks of "this view".
  defp costs_paid_info(nil) do
    gettext(
      "Paid in the period: the fees and taxes booked in the same period across all portfolios, converted at their booking day's rate; refunds reduce the taxes. Not included is the return the money paid would otherwise have earned."
    )
  end

  defp costs_paid_info(_view_id) do
    gettext(
      "Paid in the period: the fees and taxes paid in the same period from the cash accounts in this view, converted at their booking day's rate; refunds reduce the taxes. Not included is the return the money paid would otherwise have earned."
    )
  end

  defp costs_figure(amount, currency) do
    {:safe,
     [
       ~s(<span class="benchmark-costs__fig">),
       Phoenix.HTML.safe_to_string(PrivacyMode.html("#{Format.money(amount)} #{currency}")),
       "</span>"
     ]}
  end

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
      date: Format.date(start_date)
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

  # The period badge: TTWROR % beside the absolute € gain, defined as the
  # investment result net of contributions — (end − start) − net external flows
  # — so a deposit never masquerades as performance. Sprint 32 W1: the one
  # function the widget „Kennzahlen“ draws its Ergebnis with.
  defp period_value_gain(performance), do: KeyFiguresWidget.result(performance)

  # #1149 (board 04, found while drawing 2): the sign and its colour are
  # decided on the figure as displayed (`Format.displayed_sign/2`), a percent
  # at its one decimal, money at two, so a figure that reads zero is unsigned
  # and `is-flat` — never "+0,0%" in the gain colour.
  defp perf_sign_class(value), do: value |> Format.displayed_percent_sign() |> flat_sign_class()

  defp money_sign_class(value), do: value |> Format.displayed_sign(2) |> flat_sign_class()

  defp flat_sign_class(:positive), do: "is-positive"
  defp flat_sign_class(:negative), do: "is-negative"
  defp flat_sign_class(:zero), do: "is-flat"
  defp flat_sign_class(nil), do: nil

  defp signed_percent(value), do: Format.signed_percent(value)

  defp signed_money(value), do: Format.signed_decimal(value, 2)

  defp active_view_name(nil), do: gettext("Everything")
  defp active_view_name(%{name: name}), do: name

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

  # #1432 (D-A1): the browser's memory (the PeriodMemory hook) asks for the
  # period it kept, on an address that names none; the page patches to it
  # in place and checks it as any arrival. An address that names a period
  # wins, and a kept value that is no period changes nothing.
  def handle_event("restore_period", params, %{assigns: %{period_addressed: false}} = socket) do
    case address_period(Map.take(params, @period_keys)) do
      {:ok, period} when period != socket.assigns.period ->
        {:noreply,
         push_patch(socket, to: with_period(socket.assigns.current_path, period), replace: true)}

      _other ->
        {:noreply, socket}
    end
  end

  def handle_event("restore_period", _params, socket), do: {:noreply, socket}

  # Switching the chart series (% TTWROR ↔ € value) keeps the level and the
  # filter (FR-57) and rides the address, so a reload, a link handed over and
  # a period switch keep it; at „Gesamt“ without a filter the same cached
  # analysis feeds both lines, at a level each series reads its own bands.
  def handle_event("set_chart_mode", %{"mode" => mode}, socket)
      when mode in ["ttwror", "value"] do
    stack = socket.assigns.stack

    case series_stack(stack, mode) do
      ^stack ->
        {:noreply, socket}

      target ->
        {:noreply,
         push_patch(socket,
           to: stack_path(socket.assigns.carried_view, target, socket.assigns.period)
         )}
    end
  end

  # FR-56: a click on a band sets its filter and keeps the level, as its
  # legend row's link does; only a filter a band of the stack shown offers.
  def handle_event("drill_stack", %{"category" => raw}, socket) do
    with %{} = result <- socket.assigns.bands,
         filter when not is_nil(filter) <- clicked_filter(raw, result) do
      stack = %{socket.assigns.stack | category: filter}

      {:noreply,
       push_patch(socket,
         to: stack_path(socket.assigns.carried_view, stack, socket.assigns.period)
       )}
    else
      _other -> {:noreply, socket}
    end
  end

  def handle_event("drill_stack", _params, socket), do: {:noreply, socket}

  # The bar's classification: the category stack of the chosen tree, the
  # sort kept. Only a loaded tree.
  def handle_event("select_stack_classification", %{"tree" => raw}, socket) do
    with {:ok, id} <- LiveParam.fetch_id(raw),
         true <- Enum.any?(socket.assigns.classifications, &(&1.id == id)) do
      stack = %{socket.assigns.stack | level: :category, category: nil, tree: id}

      {:noreply,
       push_patch(socket,
         to: stack_path(socket.assigns.carried_view, stack, socket.assigns.period)
       )}
    else
      _other -> {:noreply, socket}
    end
  end

  def handle_event("select_stack_classification", _params, socket), do: {:noreply, socket}

  def handle_event("set_chart_mode", _params, socket), do: {:noreply, socket}

  # FR-41 (board pick A): above ten positions the contribution table shows
  # the ten largest; this opens the rest, or closes them again. Pure
  # presentation over the loaded table — nothing recomputes.
  def handle_event("toggle_contribution_all", _params, socket) do
    {:noreply, update(socket, :contribution_show_all, &(not &1))}
  end

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
             socket.assigns.min_drift_pp,
             socket.assigns.period
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
  # bucket has no category id, so it toggles under a fixed sentinel
  # (`AllocationWidget.toggle_category/2`, Sprint 32 W2).
  def handle_event("toggle_category_positions", %{"category-id" => id}, socket) do
    case AllocationWidget.toggle_category(socket.assigns.expanded_categories, id) do
      {:ok, expanded} -> {:noreply, assign(socket, :expanded_categories, expanded)}
      :error -> {:noreply, socket}
    end
  end

  # The mobile substitute for hover: tapping a slice echoes it below the chart.
  # Values are display strings straight from our own render; HEEx escapes them.
  # #1366 line 1: a tap on the selected slice again brings the total back.
  def handle_event("select_segment", params, socket) do
    selected = AllocationWidget.select_segment(socket.assigns.selected_segment, params)
    {:noreply, assign(socket, :selected_segment, selected)}
  end

  # #1366 line 1: a tap on the centre or outside the chart, or Escape, brings
  # the total back. The keydown binding names Escape (`phx-key`); another key
  # pushed by hand changes nothing.
  def handle_event("clear_segment", %{"key" => key}, socket) when key != "Escape",
    do: {:noreply, socket}

  def handle_event("clear_segment", _params, socket),
    do: {:noreply, assign(socket, :selected_segment, nil)}

  # #1366 (the lifecycle audit's #32; ADR-0059 §9: busy is one encoding,
  # with a server-side guard): the disabled button is the page's only brake
  # a client sees, so a sync_rates pushed while the sync runs is refused
  # here, as the securities page refuses a second sync_now.
  def handle_event("sync_rates", _params, %{assigns: %{fx_syncing: true}} = socket),
    do: {:noreply, socket}

  # The sync runs in the background (UAT fix round): the handler only flips
  # the in-flight flag, so the button disables and the inline status shows
  # immediately; the result lands inline next to the button, not as a toast.
  def handle_event("sync_rates", _params, socket) do
    socket =
      socket
      |> assign(fx_syncing: true, fx_sync_result: nil)
      |> CappedAsync.start_async(:sync_rates, fn -> RateSync.sync() end)

    {:noreply, socket}
  end

  # Persists the active selection as the user's default view (ADR-0024): the
  # scope the Wealth page and dashboard open on when nothing explicit was
  # chosen. Everything active (`nil`) clears the preference — Everything IS
  # the built-in default.
  def handle_event("set_default_view", _params, socket) do
    :ok = Settings.set_default_view(Actor.owner_ui(), socket.assigns.active_view_id)
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
    expanded =
      AllocationWidget.toggle_all(socket.assigns.allocation, socket.assigns.expanded_categories)

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
    chosen = PositionsWidget.choose(columns)

    {:noreply,
     socket
     |> assign(:holdings_columns, chosen)
     |> push_event("column-prefs-changed", %{
       key: PositionsWidget.storage_key(),
       columns: chosen
     })}
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
    {:ok, requested} = AllocationWidget.mode(mode)

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
             socket.assigns.min_drift_pp,
             socket.assigns.period
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
           requested,
           socket.assigns.period
         )
     )}
  end

  def handle_event("set_drift_threshold", _params, socket), do: {:noreply, socket}

  # Clicking the active sort key flips its direction; a new numeric key starts
  # desc (worklist semantics: biggest lever first), the category label starts
  # asc (alphabetical reading order).
  # (`AllocationWidget.sort/2`, Sprint 32 W2.)
  def handle_event("sort_flat_positions", %{"key" => key}, socket) do
    case AllocationWidget.sort(socket.assigns.flat_sort, key) do
      {:ok, sort} -> {:noreply, assign(socket, :flat_sort, sort)}
      :error -> {:noreply, socket}
    end
  end

  # An event this page does not know, or a payload it cannot read, changes
  # nothing (E25 S4, F17).
  def handle_event(_event, _params, socket), do: {:noreply, socket}

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

  # Whether the active view's buckets share at least one account (ADR-0024
  # overlap badge). Tolerates valuations without overlap data.
  defp overlapping?(%{overlap: %{overlapping?: true}}), do: true
  defp overlapping?(_valuation), do: false

  # Whether the active view's resolution matches zero accounts (fix round
  # hint). Tolerates valuations without the flag (and the pre-async nil).
  defp matches_no_accounts?(%{matches_no_accounts: true}), do: true
  defp matches_no_accounts?(_valuation), do: false

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
        (not is_nil(classification_id) and
           Targets.plan_exists?(portfolio_id, classification_id, view: view_id)) or
          not is_nil(Targets.get_cash_target(portfolio_id, view: view_id))
      end)

    assign(socket, :planned_view_ids, planned)
  end

  # Prefer the first custom tree (the user's own strategy); otherwise fall back
  # to the built-in asset-class tree, which always exists after seeding.
  # The default steering tree rule lives in the context so the dashboard's
  # drift alerts and this page never disagree (review finding, ADR-0022).
  #
  # #1366: a database without any classification (only a test meets it; the
  # seed creates the built-in trees) has no default tree, so no id.
  defp default_classification_id(classifications) do
    case Classifications.default_classification(classifications) do
      nil -> nil
      classification -> classification.id
    end
  end

  # -- performance chart geometry ----------------------------------------------

  # Sprint 32 W1: the chart, its series, the benchmark selection and the
  # badge moved to the section widget „Performance“ (`PerformanceSection`),
  # which Wealth and a dashboard draw with; Wealth keeps its state.
  defp value_series_label(assigns),
    do: PerformanceSection.value_series_label(display_currency(assigns))

  defp resolve_benchmarks(selectors), do: PerformanceSection.resolve_benchmarks(selectors)
  defp benchmark_groups(benchmarks), do: PerformanceSection.benchmark_groups(benchmarks)
  defp comparison_name(benchmark), do: PerformanceSection.comparison_name(benchmark)

  # -- misc ---------------------------------------------------------------------

  # Why a non-deployable cash row is left out of the cash quote (FR6/FR7): a
  # reserve or credit line never contributes, and an overdrawn free_cash account
  # has no spendable balance.

  # A pick on the page (#1432, D-A1): applied at once, as before, then the
  # address follows it, so every link built from the address keeps it, and
  # the browser's memory keeps it for a return through the sidebar.
  defp apply_period(socket, period) do
    socket = socket |> assign(:period_unchecked, false) |> put_period(period)

    {:noreply,
     socket
     |> push_event("period-memory", %{period: period_memory(period)})
     |> push_patch(to: with_period(socket.assigns.current_path, period))}
  end

  # One landing spot for a validated period term (a button string, a year or a
  # range): re-chain the cached analysis instantly, or — while the walk is
  # still computing — remember the choice for the async completion. The
  # contribution table (FR-41) recomputes for the new period either way.
  defp put_period(socket, period) do
    socket = assign(socket, :range_error, nil)

    if socket.assigns.analysis do
      # The analysis is cached — re-chaining a period is pure and instant.
      case Performance.summarise(socket.assigns.analysis, period) do
        {:ok, performance} ->
          socket
          |> assign(period: period, performance: performance)
          |> assign_comparisons()
          |> load_contribution()
          |> load_bands()
          |> push_event("close-popover", %{id: "period-custom"})

        {:error, _reason} ->
          socket
          |> assign(period: period, performance: nil, performance_failed: true)
          |> push_event("close-popover", %{id: "period-custom"})
      end
    else
      socket
      |> assign(:period, period)
      |> load_contribution()
      |> load_bands()
      |> push_event("close-popover", %{id: "period-custom"})
    end
  end

  # Windows shorter than one year show the non-annualized period MWR
  # (ADR-0034 §2); the window counts its days inclusively, so a full
  # calendar year still reads as annualized IRR.
  # Sprint 32 W1: the rule lives with the widget „Kennzahlen“, which draws
  # the same figure.
  defp short_window?(performance), do: KeyFiguresWidget.short_window?(performance)

  defp money_weighted_label(performance) do
    if short_window?(performance), do: gettext("MWR"), else: gettext("IRR")
  end

  # Callers guard with `@performance &&`, so nil never reaches this.
  defp money_weighted_value(performance), do: KeyFiguresWidget.money_weighted_value(performance)

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

  # The Allocation summary's figure: the performance once it is current; a
  # superseded one serving while the fresh walk computes reads as busy
  # (#1366, board 02 ④), and a failed one reads "—".
  defp summary_performance(performance, stale?) do
    if stale?, do: nil, else: performance
  end

  # The summary line's way back to Holdings keeps the picked view (#797)
  # and the period (#1432).
  defp holdings_path(current_path, period) do
    case current_view_param(current_path) do
      nil -> "/portfolio"
      view -> "/portfolio?" <> URI.encode_query(%{"view" => view})
    end
    |> with_period(period)
  end

  defp period_label("ytd"), do: gettext("YTD")
  defp period_label("1y"), do: gettext("1Y")
  defp period_label("3y"), do: gettext("3Y")
  defp period_label("5y"), do: gettext("5Y")
  defp period_label("max"), do: gettext("Max")
  defp period_label({:year, year}), do: Integer.to_string(year)
  defp period_label({:range, from, to}), do: range_label(from, to)

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

  defp custom_period_label({:range, from, to}), do: range_label(from, to)

  defp custom_period_label({:year, year}), do: Integer.to_string(year)

  # A custom range as every place that names the period says it — the chip,
  # the KPI heads, the badge, the contribution scope — in the page's
  # language (Sprint 19 U3).
  defp range_label(from, to), do: "#{Format.date(from)} – #{Format.date(to)}"

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
      at: Format.utc_instant(basis.computed_at),
      date: Format.date(today)
    )
  end

  defp series_basis_label(%{today: today}) do
    gettext("as of %{date}", date: Format.date(today))
  end
end
