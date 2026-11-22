defmodule PortfolixirWeb.DashboardLive do
  @moduledoc """
  The dashboard page (ADR-0062 §3, §4, §6, §12; ADR-0022's amendment of
  2026-11-21, point 4; Sprint 31 D3): `/` and `/dashboards/:id`.

  * **Which dashboard.** With no stored dashboard, `/` shows the template
    „Überblick“ read-only, with the banner „Vorlage · mitgeliefert, nur
    lesend“ and „Anpassen“, which copies it (`Dashboards.copy_template/3`,
    the first write) and opens the copy. With stored dashboards, `/` opens
    the first by position and `/dashboards/:id` the one named; an unknown
    id opens `/`. **A read never writes**: rendering a template stores
    nothing.
  * **The scope.** The dashboard reads the user's default view, Everything
    when none is set, as the Overview did; `?scope=` (a view's id, or
    `total`) picks another for this address only, never stored. An item's
    `settings.view_id` overrides it for that widget; a view that no longer
    exists reads the dashboard's scope and the widget's footer says so
    (§2).
  * **The widgets.** Each item of the layout is drawn by its kind in the
    frame of `PortfolixirWeb.Dashboard.Widget`, in reading order, placed
    on the 12-column grid in the wide class and in one or two columns of
    compact forms below it (CSS's choice, by the window's size, §6). The
    Overview's cards are the kinds `total_value`, `data_quality`, `due`,
    `off_target`, `movers`, `bitcoin_cycle` and `sale_review`, each drawing
    exactly the read the card drew (§12). Sprint 31 D4 adds the four from
    Wealth's sections — `performance`, `allocation_drift`, `snapshots` and
    `crashes`, each drawn by its module under
    `PortfolixirWeb.Dashboard.Widgets` from its source's read for the
    widget's scope and its period (below) — gives „Gesamtwert“ and
    „Datenqualität“ their M size, and draws every widget, one with nothing
    to say with its quiet line.
  * **The period** (ADR-0062 §5; idea board 05, A; Sprint 31 D5). One
    period above every dashboard, in the top bar: 1T, 1W, 1M, 3M, YTD, 1J,
    3J, Max (the registry's `Widgets.periods/0`), 1J the default. The
    address carries it as `?period=` when it is not 1J, so a link opens a
    dashboard on its period; a value that is no period opens 1J. A pick is
    remembered per browser (the `PeriodMemory` hook under the key
    `dashboard.period`, as Wealth keeps its own), so a dashboard opened
    without one in its address reopens it; a switch to another dashboard
    on the same page keeps it and writes it into the new address. Each
    widget follows it, or the period its ⋯ menu pinned (`settings.period`,
    stored through the journaled replace with the lock_version read; a
    stale one shows the stored dashboard), and its frame says which
    (`PortfolixirWeb.Dashboard.Widget.with_period/3`).
  * **The first run.** With no transaction, the page is the onboarding
    wizard; the workflow path stays a first-run card on the template until
    the depot pair exists.
  """
  use PortfolixirWeb, :live_view

  alias Plug.Conn.Query
  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.DataQuality
  alias Portfolixir.Catalog.SecurityCycles
  alias Portfolixir.Classifications
  alias Portfolixir.Dashboards
  alias Portfolixir.Dashboards.Layout
  alias Portfolixir.Dashboards.Templates
  alias Portfolixir.Dashboards.Widgets
  alias Portfolixir.Knowledge.Events
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Allocation
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.Performance.Movers
  alias Portfolixir.Portfolios.PricingContext
  alias Portfolixir.Portfolios.RealizedGains
  alias Portfolixir.Portfolios.Targets
  alias Portfolixir.Portfolios.Valuation
  alias Portfolixir.Settings
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.CappedAsync
  alias PortfolixirWeb.ClassificationName
  alias PortfolixirWeb.Components.CycleChart
  alias PortfolixirWeb.Dashboard.Edit
  alias PortfolixirWeb.Dashboard.MoversCard
  alias PortfolixirWeb.Dashboard.Widget
  alias PortfolixirWeb.Dashboard.Widgets.AllocationDrift, as: AllocationDriftWidget
  alias PortfolixirWeb.Dashboard.Widgets.Crashes, as: CrashesWidget
  alias PortfolixirWeb.Dashboard.Widgets.Line
  alias PortfolixirWeb.Dashboard.Widgets.Performance, as: PerformanceWidget
  alias PortfolixirWeb.Dashboard.Widgets.Snapshots, as: SnapshotsWidget
  alias PortfolixirWeb.ExcludedSales
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.LiveParam
  alias PortfolixirWeb.PrivacyMode
  alias PortfolixirWeb.SecurityEventLabel
  alias PortfolixirWeb.SecurityNames
  alias PortfolixirWeb.StoredText
  alias PortfolixirWeb.TransactionKindLabel
  alias PortfolixirWeb.Transactions.LedgerChecks
  alias PortfolixirWeb.ValuationNotes

  require CappedAsync

  # A category counts as off target by the one rule both drift widgets
  # apply, `AllocationDriftWidget.off_target/1`: ±5 pp or more of the
  # steering basis, every level of the tree (ADR-0022 dashboard; drift per
  # ADR-0023: actual − target; Sprint 31 closing act, money lens MO4).
  @max_alerts 5
  # #984 (pick G1-A): the Overview's closed-trades card lists the newest five.
  @closed_trades_shown 5

  # The kinds whose figures come from the view-scoped value and drift read.
  @scoped_kinds ~w(total_value off_target)

  # A page's background reads at work at once (Sprint 31 closing act,
  # security lens SE1): the rest wait in the order asked (`read/4`).
  @max_reads 4

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign_counts()
      |> assign(
        board: nil,
        items: [],
        scope_id: nil,
        load_key: nil,
        cards: %{},
        attention: %{},
        movers: %{},
        reads: MapSet.new(),
        asked: %{},
        data_quality: nil,
        last_booking: nil,
        stale_ttwror: nil,
        period: Widgets.default_period(),
        period_addressed: false,
        pin_error: nil,
        closed_trades: nil,
        customize_error: nil,
        edit: nil,
        edit_say: nil
      )
      |> assign_widget_reads()
      # #828 (design pick D3-A): the due dates, read synchronously — the
      # calendar is a small table and the card must not depend on the
      # async overview read that carries the drift alerts.
      |> assign(:upcoming_events, upcoming_events())
      # S29 H8 (ADR-0060 §11): a card „‹Name›-Zyklus“ per security with the
      # cycle view, read synchronously like the calendar — a bound security
      # is rare, and its read is the one the chart and the API answer from.
      |> assign(:cycle_views, SecurityCycles.views())
      # #984 (pick G1-A): the closed-trades card appears only where a sell
      # is booked — a cheap fact read now, so a ledger without one never
      # paints a placeholder for a card that cannot appear.
      |> assign_has_sells()

    {:ok, socket}
  end

  # --- which dashboard, which scope (ADR-0062 §2, §3) --------------------------

  @impl true
  def handle_params(params, uri, socket) do
    case board(socket.assigns.live_action, params, socket.assigns.edit) do
      :not_found ->
        {:noreply, push_navigate(socket, to: "/")}

      board ->
        scope_id = scope_id(params, socket.assigns.views)
        {period, kept?} = address_period(params, socket, board)

        socket =
          socket
          |> assign(period: period, pin_error: nil)
          |> say_dropped_edit(board)
          |> first_arrival(Map.has_key?(params, "period"))
          |> show(board, scope_id)

        # A switch from one dashboard to another on this page keeps the
        # period, and the new address names it (ADR-0062 §5).
        if kept? and period != Widgets.default_period(),
          do: {:noreply, push_patch(socket, to: with_period(uri, period), replace: true)},
          else: {:noreply, socket}
    end
  end

  # The period an address names: one of the registry's, else 1J for a
  # value that is no period. An address that names none keeps the period
  # this page already shows only on a switch to another dashboard; the
  # same dashboard's address without one — Back from `?period=3m` — opens
  # 1J, as it says (Sprint 31 closing act, correctness lens C5). A fresh
  # page opens 1J, which the browser's memory may then replace.
  defp address_period(%{"period" => period}, _socket, _board) do
    if period in Widgets.periods(),
      do: {period, false},
      else: {Widgets.default_period(), false}
  end

  defp address_period(_params, %{assigns: %{board: %{key: shown}, period: period}}, %{key: key})
       when shown != key,
       do: {period, true}

  defp address_period(_params, _socket, _board), do: {Widgets.default_period(), false}

  # Whether the page's first address named a period: the browser's memory
  # then asks for none (`#dashboard-period-memory`, `data-addressed`).
  defp first_arrival(%{assigns: %{board: nil}} = socket, named?),
    do: assign(socket, :period_addressed, named?)

  defp first_arrival(socket, _named?), do: socket

  # `uri`'s path and query with its period replaced by `period`, named
  # after the address's other pairs, none for the default.
  defp with_period(uri, period) do
    uri = URI.parse(uri)

    kept =
      (uri.query || "")
      |> URI.query_decoder()
      |> Enum.reject(fn {key, _value} -> key == "period" end)

    case kept ++ period_pairs(period) do
      [] -> uri.path
      pairs -> uri.path <> "?" <> URI.encode_query(pairs)
    end
  end

  defp period_pairs(period) do
    if period == Widgets.default_period(), do: [], else: [{"period", period}]
  end

  # While an edit is open on `/`, an address change (a period or a scope
  # pick) keeps the dashboard it edits, read again by its id, though
  # another may have become the menu's first meanwhile; a deleted one
  # ends the edit (Sprint 31 closing act, order lens O3).
  defp board(:index, params, %Edit{dashboard: %{id: id}}) do
    case Dashboards.get_dashboard(id) do
      %Dashboards.Dashboard{} = dashboard -> stored(dashboard)
      nil -> board(:index, params)
    end
  end

  defp board(action, params, _edit), do: board(action, params)

  # An open edit the new address ends: where its dashboard was deleted
  # elsewhere the status line says so; else it says nothing of the last
  # step, which no longer stands.
  defp say_dropped_edit(%{assigns: %{edit: %Edit{dashboard: %{id: id}}}} = socket, board) do
    cond do
      match?(%{dashboard: %{id: ^id}}, board) ->
        socket

      Dashboards.get_dashboard(id) == nil ->
        assign(
          socket,
          :edit_say,
          gettext("The dashboard being edited was deleted elsewhere; the edit ended unsaved.")
        )

      true ->
        assign(socket, :edit_say, nil)
    end
  end

  defp say_dropped_edit(socket, _board), do: socket

  # The stored dashboards in the menu's order, else the template; an id
  # that names none is not found (as one past the bigint range is, which
  # `PortfolixirWeb.LiveIdRange` turns away before this runs).
  defp board(:show, %{"id" => raw}) do
    with id when is_integer(id) <- LiveParam.id(raw),
         %Dashboards.Dashboard{} = dashboard <- Dashboards.get_dashboard(id) do
      stored(dashboard)
    else
      _none -> :not_found
    end
  end

  defp board(_index, _params) do
    case Dashboards.list_dashboards() do
      [first | _rest] -> stored(first)
      [] -> template(hd(Dashboards.templates()))
    end
  end

  defp stored(dashboard),
    do: %{
      key: {:dashboard, dashboard.id},
      template: nil,
      dashboard: dashboard,
      layout: dashboard.layout,
      path: "/dashboards/#{dashboard.id}"
    }

  defp template(template),
    do: %{
      key: {:template, template.key},
      template: template,
      dashboard: nil,
      layout: template.layout,
      path: "/"
    }

  # The dashboard's scope: `?scope=` for this address (a view's id or
  # `total`), else the default view the Overview always read, Everything
  # when none is set. An id that names no view reads the default; nothing
  # is stored.
  defp scope_id(%{"scope" => "total"}, _views), do: nil

  defp scope_id(%{"scope" => raw}, views) do
    with id when is_integer(id) <- LiveParam.id(raw),
         %{} <- Enum.find(views, &(&1.id == id)) do
      id
    else
      _none -> Settings.default_view_id()
    end
  end

  defp scope_id(_params, _views), do: Settings.default_view_id()

  defp show(socket, board, scope_id) do
    key = {board.key, scope_id, board.dashboard && board.dashboard.lock_version}

    # The same dashboard on another period (D5's switch): the movers and
    # the D4 widgets read what the new period needs and they have not read.
    if socket.assigns.load_key == key do
      socket |> start_movers() |> start_widget_reads()
    else
      socket
      |> assign(
        board: board,
        scope_id: scope_id,
        load_key: key,
        edit: kept_edit(socket.assigns.edit, board),
        cards: %{},
        attention: %{},
        movers: %{},
        error: nil
      )
      |> assign_items()
      |> assign_widget_reads()
      |> assign_stale_ttwror()
      |> start_loading()
      |> start_movers()
      |> start_closed_trades()
      |> start_widget_reads()
    end
  end

  # The items the page draws: the layout being edited while the edit mode
  # is open (Sprint 31 D6), each with its edit key and its kind's grid
  # sizes, else the board's.
  defp assign_items(%{assigns: %{board: board, edit: edit} = assigns} = socket) do
    layout = if edit, do: edit.layout, else: board.layout
    items = Widget.items(layout, assigns.scope_id, assigns.views)

    items =
      if edit,
        do:
          Enum.map(
            items,
            &Map.merge(&1, %{
              editing: true,
              edit_key: Edit.key_at(edit, &1.index),
              edit_sizes: Edit.grid_sizes(&1.kind)
            })
          ),
        else: items

    assign(socket, :items, items)
  end

  # An open edit stays while the page shows its dashboard (another scope,
  # another period); another dashboard ends it unsaved.
  defp kept_edit(%Edit{dashboard: %{id: id}} = edit, %{dashboard: %{id: id}}), do: edit
  defp kept_edit(_edit, _board), do: nil

  # The scopes the items read the value and drift under, the dashboard's
  # first.
  defp scopes(items, kinds, dashboard_scope) do
    items
    |> Enum.filter(&(&1.kind in kinds))
    |> Enum.map(& &1.scope)
    |> Enum.uniq()
    |> Enum.reject(&(&1 == dashboard_scope))
  end

  # The dashboard splits on whether any transaction exists: an empty database is
  # still the onboarding wizard, but once data lands the page becomes the daily
  # attention surface (Steve UAT #337, reshaped by ADR-0022): value + change,
  # drift beyond threshold, data quality — no activity feed (the audit journal
  # keeps the forensic detail). The overview reads are expensive, so they
  # start only once the socket is connected — the first paint ships skeletons.
  defp start_loading(%{assigns: %{transactions_count: 0}} = socket), do: socket

  defp start_loading(socket) do
    if connected?(socket) do
      scope_id = socket.assigns.scope_id

      socket
      |> read({:overview, scope_id}, scope_id, fn ->
        # One value card scoped to the dashboard's view — Everything when
        # none is set (ADR-0024: views, not portfolios, are the grouping the
        # dashboard aggregates over). The drift alerts steer against the same
        # view's SOLL plans (ADR-0020: plans are view-bound).
        base_currency = base_currency()

        # ADR-0035: the card's view-wide valuation and the per-portfolio drift
        # loop price the same holdings, so the market data both need is loaded
        # ONCE here and threaded into both. It is read-scoped data — it dies
        # with this task.
        context = PricingContext.for_all_portfolios(base_currency)

        {wealth_card(scope_id, base_currency, context), attention_report(scope_id, context),
         data_quality_report(), last_booking()}
      end)
      |> start_scoped(scopes(socket.assigns.items, @scoped_kinds, scope_id))
    else
      socket
    end
  end

  # An item whose `settings.view_id` names another view reads the value and
  # the drift in it, one read per such view (ADR-0062 §2).
  defp start_scoped(socket, scopes) do
    Enum.reduce(scopes, socket, fn scope_id, socket ->
      read(socket, {:scoped, scope_id}, scope_id, fn ->
        base_currency = base_currency()
        context = PricingContext.for_all_portfolios(base_currency)

        {wealth_card(scope_id, base_currency, context), attention_report(scope_id, context)}
      end)
    end)
  end

  # Every background read of the page (Sprint 31 closing act, security
  # lens SE1): one task per `name` at a time, a later ask waiting as the
  # latest (`CappedAsync.start_latest/4`), so a burst of period switches
  # runs only the first and the last read of each name; and at most
  # `@max_reads` of the page's reads at work, the rest waiting in the
  # order asked. The task answers `{key, answer}`; `asked` keeps the key
  # last asked under each name until its read lands. A read per scope is
  # named by its scope and its slot — `:follows` for an item that follows
  # the dashboard's period, `{:pinned, period}` for a pin — so the newest
  # period wins per scope, as Wealth's walk does.
  defp read(socket, name, key, fun) do
    if connected?(socket) do
      socket
      |> update(:asked, &Map.put(&1, name, key))
      |> reading(name)
      |> CappedAsync.start_latest(name, fn -> {key, fun.()} end, max_in_flight: @max_reads)
    else
      socket
    end
  end

  # Whether `key` is loaded in `field` or the read last asked under `name`.
  defp held?(socket, field, name, key),
    do:
      Map.has_key?(Map.fetch!(socket.assigns, field), key) or
        Map.get(socket.assigns.asked, name, :none) == key

  # An item's slot for the reads it names (`read/4`).
  defp read_slot(%{period_state: :pinned, period: period}), do: {:pinned, period}
  defp read_slot(_item), do: :follows

  # --- S30 T3 begin ---
  # Sprint 30 T3 (FR-59, ADR-0061 §9; board 04, A): the card „Tops und
  # Flops“ reads in the background, one read per scope and window the
  # dashboard's movers widgets take. Since Sprint 31 D5 (ADR-0062 §5) the
  # window is the widget's period — the dashboard's, or its pin —
  # translated by the registry's rule (`movers_window/1`); a window the
  # page has read for a scope is not read again, so a period switch shows
  # the busy skeleton only where a window is new.
  #
  # The read the API answers for the widget's scope: its view, Everything
  # when none is set or it vanished meanwhile (as the value card degrades).
  # The view's name travels raw; „Everything“ is localized at render time,
  # where the user's locale is set. One read per scope at a time: a chip
  # pressed while a read runs waits for it, and only the latest window
  # lands (`CappedAsync.start_latest/3`).
  defp start_movers(%{assigns: %{transactions_count: 0}} = socket), do: socket

  defp start_movers(socket) do
    socket.assigns.items
    |> Enum.filter(&(&1.kind == "movers"))
    |> Enum.map(fn item ->
      item = Widget.with_period(item, socket.assigns.period, false)
      {{:movers, item.scope, read_slot(item)}, {item.scope, movers_window(item)}}
    end)
    |> Enum.uniq_by(fn {_name, key} -> key end)
    |> Enum.reject(fn {name, key} -> held?(socket, :movers, name, key) end)
    |> Enum.reduce(socket, fn {name, {scope_id, window} = key}, socket ->
      read(socket, name, key, fn ->
        view = scope_id && Buckets.get_view(scope_id)

        case Movers.read(view && view.id, window) do
          {:ok, result} ->
            %{result: result, view_name: view && view.name}

          {:error, :view_not_found} ->
            {:ok, result} = Movers.read(nil, window)
            %{result: result, view_name: nil}
        end
      end)
    end)
  end

  # The window of the movers read for an item `Widget.with_period/3` gave
  # its period (the pin, else the dashboard's), by the registry's rule.
  defp movers_window(%{period: period}) do
    {:ok, %{"window" => window}} =
      Widgets.source_params("movers", period, Portfolixir.Clock.today())

    window
  end

  # --- S30 T3 end ---

  defp assign_has_sells(%{assigns: %{transactions_count: 0}} = socket),
    do: assign(socket, :has_sells, false)

  defp assign_has_sells(socket), do: assign(socket, :has_sells, Ledger.any_sell?())

  # #984 (pick G1-A): the closed trades are their own read, beside the
  # overview's — the realized report covers every depot whatever the view,
  # so it shares nothing with the view-scoped pricing pass and must not wait
  # for it. Data only: the task has no user locale, the card's words are
  # rendered at render time. #1030: the card computes only what it shows —
  # the report's newest five, its exclusions and its base currency — not
  # the whole report it used to cut down.
  defp start_closed_trades(%{assigns: %{has_sells: true}} = socket) do
    if connected?(socket) and Enum.any?(socket.assigns.items, &(&1.kind == "sale_review")) do
      read(socket, :closed_trades, :once, fn ->
        # #1155 (board 08, N14 = A): a twin's identifier on each trade the
        # card lists, decided over the card's trades.
        @closed_trades_shown
        |> RealizedGains.newest_trades()
        |> Map.update!(
          :trades,
          &SecurityNames.put_catalog_twin_ids(&1, fn t -> t.security_name end)
        )
        # #1320 (Sprint 31 D3): each left-out security with what tells it
        # from a twin of its note, so two of one name read as two.
        |> Map.update!(:excluded_securities, fn by_reason ->
          Map.new(by_reason, fn {reason, named} ->
            {reason, SecurityNames.put_catalog_twin_ids(named, & &1.security_name)}
          end)
        end)
      end)
    else
      socket
    end
  end

  defp start_closed_trades(socket), do: socket

  # --- S31 D4 begin ---
  # Sprint 31 D4 (ADR-0062 §12): the reads of „Wertentwicklung“,
  # „Allokation und Drift“, „Snapshots“ and „Crashes im Vergleich“, each
  # its source's, in the background, one per scope and period (a
  # performance read), per scope (the allocation), per universe (the
  # crashes) or once (the snapshots). Each lands in its own map, so a
  # second widget of a kind on the same scope draws the same answer.
  # `start_widget_reads/1` starts only what is neither loaded nor running,
  # so a later period (D5's selector) asks it again and reads the new
  # period's alone. The L size's bands are asked of the memo first, in
  # this process (I34 step 2): a hit is drawn in the same render.
  defp assign_widget_reads(socket),
    do:
      assign(socket,
        performance: %{},
        performance_bands: %{},
        allocation_drift: %{},
        snapshots: nil,
        crashes: %{},
        crash_universe: Map.get(socket.assigns, :crash_universe, "held")
      )

  defp start_widget_reads(%{assigns: %{transactions_count: 0}} = socket), do: socket

  defp start_widget_reads(socket) do
    %{items: items, period: period} = socket.assigns

    socket
    |> start_bands_from_memo(items, period)
    |> then(fn socket ->
      if connected?(socket), do: start_widget_tasks(socket, items, period), else: socket
    end)
  end

  # The performance reads the items need, `{scope, period}` each: a
  # „Wertentwicklung“ item's own period (its pin, else the dashboard's,
  # Sprint 31 D5), and „Gesamtwert“'s, whose change it draws at every
  # size and whose strip it fills at M (Sprint 31 closing act, F1).
  # `large: true` keeps the L items alone (their bands).
  defp performance_keys(items, period, opts \\ []) do
    large? = Keyword.get(opts, :large, false)

    for item <- items,
        (item.kind == "performance" and (not large? or item.size == "L")) or
          (item.kind == "total_value" and not large?) do
      item = Widget.with_period(item, period, false)
      {{item.scope, read_slot(item)}, {item.scope, item.period}}
    end
    |> Enum.uniq_by(fn {_slot, key} -> key end)
  end

  defp start_bands_from_memo(socket, items, period) do
    items
    |> performance_keys(period, large: true)
    |> Enum.reduce(socket, fn {_slot, {scope, item_period} = key}, socket ->
      with false <- Map.has_key?(socket.assigns.performance_bands, key),
           {:ok, bands} <- PerformanceWidget.cached_bands(scope, item_period, base_currency()) do
        update(socket, :performance_bands, &Map.put(&1, key, bands))
      else
        _miss -> socket
      end
    end)
  end

  defp start_widget_tasks(socket, items, period) do
    kinds = Enum.group_by(items, & &1.kind)
    scopes = fn kind -> kinds |> Map.get(kind, []) |> Enum.map(& &1.scope) |> Enum.uniq() end

    per_scope = fn field, keys ->
      for {{scope, slot}, key} <- keys, do: {{field, scope, slot}, key}
    end

    once = fn field, keys -> for key <- keys, do: {{field, key}, key} end

    socket
    |> start_each(
      per_scope.(:performance, performance_keys(items, period)),
      :performance,
      fn {scope, period} -> PerformanceWidget.read(scope, period, base_currency()) end
    )
    |> start_each(
      per_scope.(:performance_bands, performance_keys(items, period, large: true)),
      :performance_bands,
      fn {scope, period} -> PerformanceWidget.read_bands(scope, period, base_currency()) end
    )
    |> start_each(
      once.(:allocation_drift, scopes.("allocation_drift")),
      :allocation_drift,
      &AllocationDriftWidget.read/1
    )
    |> start_each(
      once.(
        :crashes,
        if(Map.has_key?(kinds, "crashes"), do: [socket.assigns.crash_universe], else: [])
      ),
      :crashes,
      &CrashesWidget.read/1
    )
    |> start_snapshots(Map.has_key?(kinds, "snapshots"))
  end

  # One read per `{name, key}` whose key `field` neither holds nor has
  # last asked under its name (`read/4`).
  defp start_each(socket, subjects, field, fetch) do
    Enum.reduce(subjects, socket, fn {name, key}, socket ->
      if held?(socket, field, name, key),
        do: socket,
        else: read(socket, name, key, fn -> fetch.(key) end)
    end)
  end

  defp start_snapshots(%{assigns: %{snapshots: nil, reads: reads}} = socket, true) do
    if MapSet.member?(reads, :snapshots),
      do: socket,
      else: read(socket, :snapshots, :once, fn -> SnapshotsWidget.read() end)
  end

  defp start_snapshots(socket, _shown), do: socket

  # --- S31 D4 end ---

  # ADR-0032 §6 on the dashboard tile: while the overview computes, the last
  # known YTD figure renders immediately -- labelled with the data it contains,
  # never bare (owner requirement). Only the TTWROR half is served this way:
  # the valuation is not memoised, and a figure §6 cannot label honestly
  # recomputes instead of being guessed.
  defp assign_stale_ttwror(%{assigns: %{transactions_count: 0}} = socket) do
    assign(socket, :stale_ttwror, nil)
  end

  defp assign_stale_ttwror(socket) do
    first = Portfolios.first_portfolio()
    view_id = socket.assigns.scope_id

    with %{} = portfolio <- first,
         %{daily: [_ | _]} = previous <-
           Performance.previous_view_analysis(view_id,
             base_currency: portfolio.base_currency_code
           ),
         {:ok, %{ttwror: %Decimal{} = ttwror}} <- Performance.summarise(previous, "ytd") do
      assign(socket, :stale_ttwror, %{
        ttwror: ttwror,
        basis: previous.basis,
        as_of: previous.today
      })
    else
      _none -> assign(socket, :stale_ttwror, nil)
    end
  end

  # The card's data: the deduplicated cross-portfolio view valuation in the
  # first portfolio's base currency (display continuity with the Wealth page),
  # plus the YTD TTWROR as the change signal — computed over the same
  # cross-portfolio view scope as the valuation (#577), so the total and the
  # return always cover the same accounts.
  defp wealth_card(view_id, base_currency, context) do
    view = view_id && Buckets.get_view(view_id)
    # The default view can vanish between the settings read and here (fix
    # round): degrade to the Everything scope instead of crashing the async.
    view_id = view && view.id

    # The daily walk behind the card's YTD signal (#798), which also keeps
    # the memo the stale figure is read from (ADR-0032 §6).
    analysis = view_analysis(view_id, base_currency)
    valuation = everything_or_view_valuation(view_id, base_currency, context)

    %{
      # `name: nil` renders as the localized "Everything" label at render time
      # (fix round): this function runs inside `start_async`'s task process,
      # where the user's Gettext locale is NOT set — a gettext call here
      # always came out English ("EVERYTHING" after the card's CSS uppercase).
      name: view && view.name,
      # #1122: the card's own view id (nil for Everything), so the note can
      # name the session's view where Wealth would open on another.
      view_id: view_id,
      valuation: valuation,
      # #1320 (Sprint 31 D3): the twins among the positions the total
      # leaves out, so the note names each apart.
      unvalued_twin_ids: ValuationNotes.unvalued_twin_ids(valuation),
      # The YTD signal the card shows while no period read has landed;
      # the strip's return is the item's period's performance read (F1).
      ttwror: ttwror_of(summarise(analysis, "ytd"))
    }
  end

  # The card's base currency: the first portfolio's, for display continuity
  # with the Wealth page. Read before the async block's pricing pass so both
  # cover the same currency.
  defp base_currency do
    first = Portfolios.first_portfolio()
    (first && first.base_currency_code) || "EUR"
  end

  defp everything_or_view_valuation(view_id, base_currency, context) do
    opts = [base_currency: base_currency, pricing_context: context]

    case Valuation.for_view(view_id, opts) do
      {:error, :view_not_found} -> Valuation.for_view(nil, opts)
      valuation -> valuation
    end
  end

  # Every background read the page starts is in `@reads` until it lands, and
  # the grid is busy while any is (the polish list #1358, Sprint 31 D3): the
  # browser walks leave a page only once nothing on it is busy
  # (test/browser/settle.js), and a read whose widget draws no skeleton —
  # data quality, absent until its finding lands — would otherwise run past
  # the walk's wait and log from a page already gone.
  #
  # A read a later ask superseded (`read/4`) still lands its answer under
  # its own key, which is a true answer for that key, and stays busy: the
  # latest ask runs now. A superseded read that failed lands nothing.
  @impl true
  def handle_async(name, result, socket) do
    {state, socket} = CappedAsync.landed(socket, name)

    socket =
      case {state, result} do
        {_state, {:ok, {key, answer}}} ->
          land(name, key, {:ok, answer}, socket)

        {:current, {:exit, reason}} ->
          land(name, socket.assigns.asked[name], {:exit, reason}, socket)

        {:superseded, {:exit, _reason}} ->
          socket
      end

    case state do
      :superseded ->
        {:noreply, socket}

      :current ->
        {:noreply,
         socket
         |> update(:reads, &MapSet.delete(&1, name))
         |> update(:asked, &Map.delete(&1, name))}
    end
  end

  defp land(
         {:overview, _name},
         scope_id,
         {:ok, {wealth_card, attention, data_quality, last_booking}},
         socket
       ) do
    socket
    |> update(:cards, &Map.put(&1, scope_id, wealth_card))
    |> update(:attention, &Map.put(&1, scope_id, attention))
    |> assign(data_quality: data_quality, last_booking: last_booking)
  end

  defp land({:scoped, _name}, scope_id, {:ok, {wealth_card, attention}}, socket) do
    socket
    |> update(:cards, &Map.put(&1, scope_id, wealth_card))
    |> update(:attention, &Map.put(&1, scope_id, attention))
  end

  defp land({read, _name}, _scope_id, {:exit, _reason}, socket) when read in [:overview, :scoped],
    do: assign(socket, :error, gettext("Couldn't load the dashboard figures."))

  # --- S30 T3 begin ---
  defp land({:movers, _scope, _slot}, key, result, socket) do
    card =
      case result do
        {:ok, card} -> card
        {:exit, _reason} -> :error
      end

    update(socket, :movers, &Map.put(&1, key, card))
  end

  # --- S30 T3 end ---

  # --- S31 D4 begin ---
  defp land(name, key, result, socket)
       when elem(name, 0) in [:performance, :performance_bands, :allocation_drift, :crashes] do
    answer =
      case result do
        {:ok, {:ok, bands}} -> bands
        {:ok, answer} -> answer
        {:exit, _reason} -> :error
      end

    update(socket, elem(name, 0), &Map.put(&1, key, answer))
  end

  defp land(:snapshots, _key, {:ok, card}, socket), do: assign(socket, :snapshots, card)
  defp land(:snapshots, _key, {:exit, _reason}, socket), do: assign(socket, :snapshots, :error)

  # --- S31 D4 end ---

  defp land(:closed_trades, _key, {:ok, card}, socket), do: assign(socket, :closed_trades, card)

  defp land(:closed_trades, _key, {:exit, _reason}, socket),
    do: assign(socket, :closed_trades, :error)

  defp reading(socket, name), do: update(socket, :reads, &MapSet.put(&1, name))

  # „Anpassen“ (ADR-0062 §3): the template copied into a stored dashboard
  # under the UI's actor — the first write — and the copy opened. Only a
  # template answers it; a stored dashboard has nothing to copy here.
  @impl true
  def handle_event("customize", _params, %{assigns: %{board: %{template: %{} = t}}} = socket) do
    case Dashboards.copy_template(Actor.owner_ui(), t.key, %{}) do
      {:ok, dashboard} ->
        {:noreply, push_navigate(socket, to: "/dashboards/#{dashboard.id}")}

      {:error, :too_many_dashboards} ->
        {:noreply,
         assign(
           socket,
           :customize_error,
           gettext("Fifty dashboards are stored, the most an instance keeps.")
         )}

      {:error, _refusal} ->
        {:noreply, assign(socket, :customize_error, gettext("Couldn't copy the template."))}
    end
  end

  # A pick in the top bar (ADR-0062 §5): the address follows it, so every
  # link built from the address keeps it, and the browser's memory keeps
  # it for a dashboard opened without one.
  def handle_event("set_period", %{"period" => period}, socket) when is_binary(period) do
    if period in Widgets.periods() do
      {:noreply,
       socket
       |> assign(:period, period)
       |> push_event("period-memory", %{period: %{"period" => period}})
       |> push_patch(to: with_period(socket.assigns.page_address, period))}
    else
      {:noreply, socket}
    end
  end

  # The browser's memory (the PeriodMemory hook) asks for the period it
  # kept, on an address that named none; the page patches to it in place.
  # An address that named a period wins, and a kept value that is no
  # period changes nothing.
  def handle_event(
        "restore_period",
        %{"period" => period},
        %{assigns: %{period_addressed: false}} = socket
      )
      when is_binary(period) do
    if period in Widgets.periods() and period != socket.assigns.period,
      do:
        {:noreply,
         push_patch(socket, to: with_period(socket.assigns.page_address, period), replace: true)},
      else: {:noreply, socket}
  end

  # A pin from a widget's ⋯ menu (ADR-0062 §5): stored in the item's
  # `settings.period` through the journaled replace with the lock_version
  # the page read; `unpin_period` drops it. Only a stored dashboard takes
  # one, only for an item of its layout, and only a period its kind
  # answers (the layout's validation refuses any other).
  def handle_event("pin_period", %{"index" => index, "period" => period}, socket)
      when is_binary(period) do
    {:noreply, pin(socket, index, &Map.put(&1, "period", period))}
  end

  def handle_event("unpin_period", %{"index" => index}, socket) do
    {:noreply, pin(socket, index, &Map.delete(&1, "period"))}
  end

  # Sprint 31 D4: „Im Depot · Katalog“ on „Crashes im Vergleich“ (as on
  # Risk › Crashes); a universe the widget does not know reads „Im Depot“.
  def handle_event("crash_universe", %{"universe" => universe}, socket) do
    socket = assign(socket, :crash_universe, CrashesWidget.universe(universe))
    {:noreply, start_widget_reads(socket)}
  end

  # --- S31 D6 begin ---
  # The edit mode (ADR-0062 §7; board 03; Sprint 31 D6). „Bearbeiten“ on a
  # stored dashboard opens it; a template has none („Anpassen“ copies it
  # first). Each step is `PortfolixirWeb.Dashboard.Edit`'s, validated on
  # the server and said in the polite live region `#dashboard-edit-status`;
  # a refused step is said, not applied. Nothing is written until
  # „Fertig“, which replaces the dashboard once with the lock_version the
  # edit read: one journal entry per save.
  def handle_event(
        "edit_start",
        _params,
        %{assigns: %{board: %{dashboard: %Dashboards.Dashboard{} = dashboard}, edit: nil}} =
          socket
      ) do
    edit = Edit.start(dashboard)

    # The focus goes to the first widget's handle, else „Fertig“ (Sprint 31
    # closing act, Y3: the button pressed is gone from the page).
    focus =
      case Edit.reading_keys(edit) do
        [first | _rest] -> ["dashboard-edit-handle-#{first}", "dashboard-edit-done"]
        [] -> ["dashboard-edit-done"]
      end

    {:noreply,
     socket
     |> assign(edit: edit, edit_say: gettext("Editing: nothing is stored until “Done”."))
     |> assign_items()
     |> push_event("dashboard-edit-focus", %{ids: focus})}
  end

  # The keyboard path: the keys the handle sends (`phx-keydown`).
  def handle_event(
        "edit_key",
        %{"item" => raw, "key" => key},
        %{assigns: %{edit: %Edit{}}} = socket
      )
      when is_binary(key) do
    focus = if key in ["Delete", "Backspace"], do: :remove, else: :handle

    edit_step(socket, raw, focus, fn edit, item ->
      case key do
        "ArrowLeft" -> Edit.move(edit, item, :left)
        "ArrowRight" -> Edit.move(edit, item, :right)
        "ArrowUp" -> Edit.move(edit, item, :up)
        "ArrowDown" -> Edit.move(edit, item, :down)
        delete when delete in ["Delete", "Backspace"] -> Edit.remove(edit, item)
        _other -> :error
      end
    end)
  end

  # The pointer path: the DashboardEdit hook's drop on the wide grid.
  def handle_event(
        "edit_place",
        %{"item" => raw, "col" => col, "row" => row},
        %{assigns: %{edit: %Edit{}}} = socket
      ) do
    places = 1..Layout.max_row()

    edit_step(socket, raw, :handle, fn edit, item ->
      Edit.place(edit, item, LiveParam.integer(col, places), LiveParam.integer(row, places))
    end)
  end

  def handle_event(
        "edit_resize",
        %{"item" => raw, "size" => size},
        %{assigns: %{edit: %Edit{}}} = socket
      ),
      do: edit_step(socket, raw, {:resize, size}, &Edit.resize(&1, &2, size))

  def handle_event("edit_remove", %{"item" => raw}, %{assigns: %{edit: %Edit{}}} = socket),
    do: edit_step(socket, raw, :remove, &Edit.remove/2)

  def handle_event(
        "edit_reorder",
        %{"item" => raw, "direction" => direction},
        %{assigns: %{edit: %Edit{}}} = socket
      ) do
    edit_step(socket, raw, {:reorder, direction}, fn edit, item ->
      case direction do
        "up" -> Edit.reorder(edit, item, :up)
        "down" -> Edit.reorder(edit, item, :down)
        _other -> :error
      end
    end)
  end

  def handle_event("edit_add", %{"kind" => kind}, %{assigns: %{edit: %Edit{} = edit}} = socket),
    do: {:noreply, stepped(socket, Edit.add(edit, kind), :handle)}

  def handle_event("edit_reset", _params, %{assigns: %{edit: %Edit{} = edit}} = socket) do
    {:noreply,
     socket
     |> assign(edit: Edit.reset(edit), edit_say: gettext("Unsaved changes discarded."))
     |> assign_items()
     |> start_added_reads()}
  end

  def handle_event("edit_done", _params, %{assigns: %{edit: %Edit{} = edit}} = socket) do
    if Edit.changed?(edit) do
      case replace_layout(edit.dashboard, edit.layout) do
        {:ok, dashboard} ->
          {:noreply, saved(socket, dashboard, gettext("Dashboard saved."))}

        {:error, :stale, stored} ->
          {:noreply,
           assign(socket,
             edit: Edit.stale(edit, stored),
             edit_say: stale_sentence()
           )}

        {:error, :not_found} ->
          {:noreply, push_navigate(socket, to: "/")}

        {:error, _refusal} ->
          {:noreply, assign(socket, :edit_say, gettext("Couldn't save the dashboard."))}
      end
    else
      case Dashboards.get_dashboard(edit.dashboard.id) do
        %Dashboards.Dashboard{} = dashboard ->
          {:noreply, saved(socket, dashboard, gettext("No changes to save."))}

        nil ->
          {:noreply, push_navigate(socket, to: "/")}
      end
    end
  end

  # After a stale save: „Gespeicherte Fassung laden“ ends the edit and
  # draws the dashboard as stored; „Weiter bearbeiten“ keeps the edit on
  # the stored version, so the next „Fertig“ replaces what was shown.
  def handle_event(
        "edit_load_stored",
        _params,
        %{assigns: %{edit: %Edit{stale: %Dashboards.Dashboard{} = stored}}} = socket
      ) do
    {:noreply,
     socket
     |> assign(edit: nil, edit_say: gettext("The stored version is shown."))
     |> show(stored(stored), socket.assigns.scope_id)
     |> push_event("dashboard-edit-focus", %{ids: ["dashboard-edit-start"]})}
  end

  def handle_event("edit_keep", _params, %{assigns: %{edit: %Edit{stale: %{}} = edit}} = socket) do
    {:noreply,
     socket
     |> assign(
       edit: Edit.rebase(edit),
       edit_say: gettext("Editing continues; “Done” replaces the stored version shown before.")
     )
     |> push_event("dashboard-edit-focus", %{ids: ["dashboard-edit-done"]})}
  end

  # --- S31 D6 end ---

  # The overview handles no other events; one pushed to it changes nothing
  # (E25 S4, F17).
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # --- S31 D6 begin ---
  defp edit_step(%{assigns: %{edit: edit}} = socket, raw, focus, step) do
    case Edit.key(edit, raw) do
      nil -> {:noreply, socket}
      item -> {:noreply, stepped(socket, step.(edit, item), focus)}
    end
  end

  # A step applied: the edit drawn, its sentence said, the focus on the
  # control the step names, and a read started for a widget the page has
  # not read yet. A refused step is said and changes nothing else.
  #
  # The focus goes to the first of a list of ids the page has drawn and
  # shows (the DashboardEdit hook), since the compact class hides the
  # handle and the wide class the ↑ and ↓ (Sprint 31 closing act, Y1): the
  # control just used, on the widget it moved — ↑ or ↓ after a reorder, a
  # size after a resize —, else that widget's handle; after a removal the
  # next widget's handle or ×; „Fertig“ when no widget is left.
  defp stepped(socket, {:ok, edit, say, key}, focus) do
    socket
    |> assign(edit: edit, edit_say: say)
    |> assign_items()
    |> push_event("dashboard-edit-focus", %{ids: focus_ids(focus, key)})
    |> start_added_reads()
  end

  # A refusal said again is said with a no-break space more or less at its
  # end, so the live region's text changes and a screen reader announces it
  # again; the words stay the same (Sprint 31 closing act, the a11y lens).
  defp stepped(socket, {:refused, say}, _focus) do
    case socket.assigns.edit_say do
      ^say -> assign(socket, :edit_say, say <> "\u00A0")
      _other -> assign(socket, :edit_say, say)
    end
  end

  defp stepped(socket, :error, _focus), do: socket

  defp focus_ids(_focus, nil), do: ["dashboard-edit-done"]

  defp focus_ids({:reorder, direction}, key),
    do: [
      "dashboard-edit-#{direction}-#{key}",
      "dashboard-edit-handle-#{key}",
      "dashboard-edit-done"
    ]

  defp focus_ids({:resize, size}, key),
    do: [
      "dashboard-edit-handle-#{key}",
      "dashboard-edit-size-#{key}-#{size}",
      "dashboard-edit-done"
    ]

  defp focus_ids(:remove, key),
    do: ["dashboard-edit-handle-#{key}", "dashboard-edit-remove-#{key}", "dashboard-edit-done"]

  defp focus_ids(:handle, key),
    do: ["dashboard-edit-handle-#{key}", "dashboard-edit-up-#{key}", "dashboard-edit-done"]

  defp start_added_reads(socket) do
    socket
    |> start_movers()
    |> start_widget_reads()
    |> start_added_closed_trades()
  end

  defp start_added_closed_trades(%{assigns: %{closed_trades: nil, reads: reads}} = socket) do
    if MapSet.member?(reads, :closed_trades), do: socket, else: start_closed_trades(socket)
  end

  defp start_added_closed_trades(socket), do: socket

  # The edit saved, or closed with nothing to save: the dashboard drawn as
  # stored, with its ⋯ menus, the reads it holds kept.
  # The focus goes back to „Bearbeiten“ (Y3).
  defp saved(socket, dashboard, say) do
    socket
    |> assign(edit: nil, edit_say: say)
    |> then(&pinned_board({:ok, dashboard}, &1))
    |> push_event("dashboard-edit-focus", %{ids: ["dashboard-edit-start"]})
  end

  defp stale_sentence,
    do:
      gettext(
        "This dashboard was changed elsewhere since the edit began. Nothing was saved; the stored version is shown with the edit."
      )

  # --- S31 D6 end ---

  # The edit mode hides the ⋯ menu; a pin sent meanwhile would write under
  # the edit's lock_version, so it changes nothing.
  defp pin(%{assigns: %{edit: %Edit{}}} = socket, _index, _change), do: socket

  defp pin(
         %{assigns: %{board: %{dashboard: %Dashboards.Dashboard{} = dashboard}}} = socket,
         index,
         change
       ) do
    with index when is_integer(index) <- layout_index(index, dashboard.layout),
         layout = List.update_at(dashboard.layout, index, &pinned(&1, change)),
         true <- layout != dashboard.layout do
      dashboard
      |> replace_layout(layout)
      |> pinned_board(socket)
    else
      _nothing -> socket
    end
  end

  defp pin(socket, _index, _change), do: socket

  defp pinned(item, change), do: Map.put(item, "settings", change.(item["settings"] || %{}))

  defp layout_index(_raw, []), do: nil
  defp layout_index(raw, layout), do: LiveParam.integer(raw, 0..(length(layout) - 1))

  defp replace_layout(dashboard, layout) do
    Dashboards.replace_dashboard(Actor.owner_ui(), dashboard.id, %{
      "name" => dashboard.name,
      "layout" => layout,
      "lock_version" => dashboard.lock_version
    })
  end

  # The stored dashboard drawn in place: its items with their pins, the
  # reads it already holds kept, a movers window or a performance period
  # it has not read started (Sprint 31 D4). A refusal changes
  # nothing on the screen but its note.
  defp pinned_board({:ok, dashboard}, socket) do
    board = stored(dashboard)

    socket
    |> assign(
      board: board,
      load_key: {board.key, socket.assigns.scope_id, dashboard.lock_version},
      pin_error: nil
    )
    |> assign_items()
    |> start_movers()
    |> start_widget_reads()
  end

  # Another write passed the lock_version the page read: the stored
  # dashboard is drawn and read as on arrival, since its layout may differ
  # in more than this pin.
  defp pinned_board({:error, :stale, stored}, socket) do
    socket
    |> show(stored(stored), socket.assigns.scope_id)
    |> assign(
      :pin_error,
      gettext(
        "This dashboard was changed elsewhere and is shown as stored; the period was not set."
      )
    )
  end

  defp pinned_board({:error, _refusal}, socket),
    do: assign(socket, :pin_error, gettext("Couldn't store the widget's period."))

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell page_address={@page_address}
      current_path={if @board, do: @board.path, else: "/"}
      page_title={board_title(@board)}
      switcher={@board != nil}
      page_subtitle={gettext("Local portfolio tracking")}
    >
      <div id="dashboard-workspace" class="workspace-page">
        <.dashboard_bar
          :if={@board}
          board={@board}
          scope_id={@scope_id}
          views={@views}
          customize_error={@customize_error}
          pin_error={@pin_error}
          period={@period}
          period_addressed={@period_addressed}
          edit={@edit}
          edit_say={@edit_say}
        />
        <%!-- Sprint 31 D7 („Neues Dashboard“ → „Leer beginnen“): a stored
             dashboard with no widget says so and where widgets come from,
             until the edit mode opens the catalogue itself. --%>
        <p
          :if={@board && @board.dashboard && @board.layout == [] && is_nil(@edit)}
          class="hint dashboard-empty"
          data-role="dashboard-empty"
        >
          <%= StoredText.isolate(
            gettext("This dashboard is empty. Add widgets from %{catalogue}.",
              catalogue: StoredText.slot(:catalogue)
            ),
            catalogue: StoredText.link("/widgets", gettext("All widgets"))
          ) %>
        </p>
        <%= if @transactions_count == 0 do %>
          <.wizard {assigns} />
        <% else %>
          <.workflow_path :if={first_run?(assigns)} />
          <.overview {assigns} />
        <% end %>
      </div>
    </AppShell.shell>
    """
  end

  defp board_title(nil), do: gettext("Overview")
  defp board_title(%{dashboard: %{name: name}}), do: name
  defp board_title(%{template: template}), do: Templates.title(template.key)

  # The workflow path stays a first-run card on the template until the
  # depot pair exists (a depot is always linked to its cash account).
  defp first_run?(assigns),
    do: match?(%{template: %{}}, assigns.board) and assigns.securities_accounts_count == 0

  attr(:board, :map, required: true)
  attr(:scope_id, :any, required: true)
  attr(:views, :list, required: true)
  attr(:customize_error, :string, default: nil)
  attr(:pin_error, :string, default: nil)
  attr(:period, :string, required: true)
  attr(:period_addressed, :boolean, default: false)
  attr(:edit, :any, default: nil)
  attr(:edit_say, :string, default: nil)

  # The bar above the widgets (planning board 01 ①): the dashboard's scope
  # („Gesamt ▾“), the period (board 05 A: 1T … Max, on a narrow window a
  # strip that scrolls sideways, ADR-0062 §6), and on a template the
  # banner „Vorlage · mitgeliefert, nur lesend“ with „Anpassen“. The
  # scope's choices are links that keep it, and the period, in the address
  # only; the session's view and the default stay as they are.
  defp dashboard_bar(assigns) do
    assigns =
      assign(assigns,
        scope_name: scope_name(assigns.scope_id, assigns.views),
        choices:
          [{"total", gettext("Everything"), is_nil(assigns.scope_id)}] ++
            Enum.map(assigns.views, &{to_string(&1.id), &1.name, &1.id == assigns.scope_id})
      )

    ~H"""
    <section
      id="dashboard-bar"
      class="workspace-section workspace-section--controls dashboard-bar"
      aria-label={gettext("Dashboard")}
    >
      <div class="dashboard-bar__row">
        <details class="dashboard-scope" id="dashboard-scope" data-role="dashboard-scope">
          <summary aria-label={gettext("Scope: %{name}", name: @scope_name)}>
            <span data-role="dashboard-scope-name"><%= @scope_name %></span>
            <span aria-hidden="true">▾</span>
          </summary>
          <nav class="dashboard-scope__menu" aria-label={gettext("Scope")}>
            <.link
              :for={{value, name, active?} <- @choices}
              patch={scope_href(@board.path, value, @period)}
              class={["dashboard-scope__option", active? && "is-active"]}
              aria-current={if active?, do: "true"}
              data-scope={value}
            ><%= name %></.link>
          </nav>
        </details>
        <%!-- The compact strip scrolls a chip the keyboard focuses whole
             into view (Sprint 31 closing act, Y4). --%>
        <div
          id="dashboard-period-strip"
          class="dashboard-period"
          data-role="dashboard-period-strip"
          phx-hook="ScrollFocused"
        >
          <div
            class="segmented-control dashboard-period__control"
            data-role="dashboard-period"
            role="group"
            aria-label={gettext("Period")}
          >
            <button
              :for={period <- Widgets.periods()}
              type="button"
              class={["segmented-control__option", @period == period && "is-active"]}
              phx-click="set_period"
              phx-value-period={period}
              aria-pressed={to_string(@period == period)}
              data-period={period}
            >
              <%= Widget.period_label(period) %>
            </button>
          </div>
        </div>
        <%!-- The browser's memory of the last period picked (ADR-0062 §5),
             read when the address names none and written at each pick;
             nothing of it reaches the server's storage. --%>
        <div
          id="dashboard-period-memory"
          phx-hook="PeriodMemory"
          data-storage-key="dashboard.period"
          data-addressed={to_string(@period_addressed)}
          hidden
        >
        </div>
        <%!-- Sprint 31 D6 (ADR-0062 §7; board 03): „Bearbeiten“ on a stored
             dashboard; in the edit mode „Zurücksetzen“ and „Fertig“. --%>
        <div :if={@board.dashboard} class="dashboard-edit-actions">
          <%= if @edit do %>
            <span class="dashboard-edit-actions__label"><%= gettext("editing") %></span>
            <button
              type="button"
              class="button-secondary"
              phx-click="edit_reset"
              data-role="edit-reset"
            >
              <%= gettext("Reset") %>
            </button>
            <button
              type="button"
              id="dashboard-edit-done"
              class="button-primary"
              phx-click="edit_done"
              data-role="edit-done"
            >
              <%= gettext("Done") %>
            </button>
          <% else %>
            <button
              type="button"
              id="dashboard-edit-start"
              class="button-secondary"
              phx-click="edit_start"
              data-role="edit-start"
            >
              <%= gettext("Edit") %>
            </button>
          <% end %>
        </div>
      </div>
      <%!-- Every edit step is said here, a refusal too (ADR-0062 §7); the
           region exists before the first step, so the first is heard. No
           whitespace inside, so `:empty` holds. --%>
      <p
        id="dashboard-edit-status"
        class="dashboard-edit-status"
        role="status"
        aria-live="polite"
      ><%= @edit_say %></p>
      <p :if={@edit} id="dashboard-edit-hint" class="visually-hidden">
        <%= gettext("The arrow keys move the widget one grid step; Delete removes it.") %>
      </p>
      <.stale_edit :if={@edit && @edit.stale} stored={@edit.stale} />
      <div :if={@board.template} class="dashboard-banner" data-role="template-banner">
        <span>
          <strong><%= gettext("Template") %></strong> · <%= gettext("shipped, read-only") %>
        </span>
        <button
          type="button"
          class="button-primary"
          phx-click="customize"
          data-role="customize"
        >
          <%= gettext("Customize") %>
        </button>
      </div>
      <div id="dashboard-customize-status" class="dashboard-status" role="status"><AppShell.data_note
          :if={@customize_error}
          severity={:problem}
        ><%= @customize_error %></AppShell.data_note><AppShell.data_note
          :if={@pin_error}
          severity={:problem}
          data-role="period-pin-status"
        ><%= @pin_error %></AppShell.data_note></div>
    </section>
    """
  end

  attr(:stored, :map, required: true)

  # A stale save (ADR-0062 §2, §7): the dashboard as stored now, in its
  # reading order, each widget with its size and place on a small grid,
  # beside the edit, and the two ways on; nothing is lost unseen.
  defp stale_edit(assigns) do
    assigns =
      assign(
        assigns,
        :items,
        Enum.map(
          Widget.items(assigns.stored.layout, nil, []),
          &Map.put(&1, :title, Widgets.title(&1.kind))
        )
      )

    ~H"""
    <div class="dashboard-edit-stale" data-role="edit-stale">
      <AppShell.data_note severity={:problem}>
        <%= stale_sentence() %>
      </AppShell.data_note>
      <ol class="dashboard-edit-stale__grid" aria-label={gettext("Stored version")}>
        <li
          :for={item <- @items}
          data-role="stored-item"
          style={"--widget-col: #{item.col}; --widget-row: #{item.row}; --widget-w: #{item.w}; --widget-h: #{item.h};"}
        >
          <strong><%= item.title %></strong>
          <span><%= gettext("%{size} · column %{col}, row %{row}",
            size: item.size,
            col: item.col,
            row: item.row
          ) %></span>
        </li>
      </ol>
      <div class="dashboard-edit-stale__actions">
        <button
          type="button"
          class="button-primary"
          phx-click="edit_load_stored"
          data-role="edit-load-stored"
        >
          <%= gettext("Load the stored version") %>
        </button>
        <button type="button" class="button-secondary" phx-click="edit_keep" data-role="edit-keep">
          <%= gettext("Keep editing") %>
        </button>
      </div>
    </div>
    """
  end

  # The catalogue beside the grid (board 03, „Widget hinzufügen“): every
  # registered kind under its group, with its grid sizes; a tap adds it at
  # the first free place in its first size. The compact class has none
  # (ADR-0062 §7: no placement there).
  defp catalogue(assigns) do
    assigns =
      assign(
        assigns,
        :groups,
        Widgets.groups()
        |> Enum.map(fn group ->
          {group, Enum.filter(Dashboards.widgets(), &(&1.group == group))}
        end)
        |> Enum.reject(fn {_group, kinds} -> kinds == [] end)
      )

    ~H"""
    <aside
      id="dashboard-catalogue"
      class="dashboard-catalogue"
      data-role="edit-catalogue"
      aria-labelledby="dashboard-catalogue-title"
    >
      <h2 id="dashboard-catalogue-title"><%= gettext("Add widget") %></h2>
      <section :for={{group, kinds} <- @groups} class="dashboard-catalogue__group">
        <h3><%= Widgets.group_title(group) %></h3>
        <button
          :for={kind <- kinds}
          type="button"
          class="dashboard-catalogue__item"
          phx-click="edit_add"
          phx-value-kind={kind.key}
          data-role="edit-add"
          data-kind={kind.key}
        >
          <span><%= Widgets.title(kind.key) %></span>
          <span class="dashboard-catalogue__sizes"><%= Enum.join(Edit.grid_sizes(kind.key), " ") %></span>
        </button>
      </section>
      <p class="dashboard-catalogue__note">
        <%= gettext("A tap adds a widget at the first free place. An agent can do the same over the API and MCP.") %>
      </p>
    </aside>
    """
  end

  defp scope_href(path, value, period),
    do: path <> "?" <> URI.encode_query([{"scope", value}] ++ period_pairs(period))

  defp scope_name(nil, _views), do: gettext("Everything")

  defp scope_name(id, views) do
    case Enum.find(views, &(&1.id == id)) do
      %{name: name} -> name
      nil -> gettext("Everything")
    end
  end

  # Empty-database onboarding: the ordered workflow plus the count cards that
  # link to where each entity is created.
  defp wizard(assigns) do
    ~H"""
    <.workflow_path :if={first_run?(assigns)} />

    <.count_cards {assigns} />

    <.cycle_cards views={@cycle_views} />
    """
  end

  defp workflow_path(assigns) do
    ~H"""
    <section id="workflow-path" class="workspace-section">
      <h2><%= gettext("Workflow path") %></h2>
      <%!-- The depot + cash account pair is the prerequisite the Wealth and
            Income screens demand first (ADR-0024: no portfolio decision
            anywhere); the path starts there so the dashboard does not
            contradict them. --%>
      <ol>
        <li><a href="/portfolios"><%= gettext("Create one cash account") %></a></li>
        <li><a href="/portfolios"><%= gettext("Link one depot to one cash account") %></a></li>
        <li><a href="/securities"><%= gettext("Create securities") %></a></li>
        <li>
          <a href="/transactions"><%= gettext("Record manual buy and sell transactions") %></a>
        </li>
        <li><a href="/transactions"><%= gettext("Review current holdings") %></a></li>
      </ol>
    </section>
    """
  end

  attr(:views, :list, required: true)

  # --- S29 H8 begin ---
  # ADR-0060 §11 (idea board 01, A's shortcut): one card „‹Name›-Zyklus“
  # per security with the cycle view, ordered by name, after the dated
  # facts; its link opens the chart with cycles on and the range „Zyklus“.
  # On the wizard too: a watched coin needs no transaction.
  defp cycle_cards(assigns) do
    ~H"""
    <CycleChart.card
      :for={payload <- @views}
      payload={payload}
      href={"/securities/#{payload.security_id}?tab=chart&cycles=1"}
    />
    """
  end

  # --- S29 H8 end ---

  # The populated dashboard: the layout's widgets in reading order on the
  # grid (ADR-0062 §4, §6). Load failure is a page-level condition, not an
  # action result: one data note in flow, announced from a region that
  # exists on load, no floating toast and no timer (#566, UX-DR17).
  defp overview(assigns) do
    ~H"""
    <div id="dashboard-overview" class="dashboard">
      <%!-- No whitespace inside, so `:empty` holds and the empty region
           takes no gap (Sprint 31 closing act, DS2). --%>
      <div id="dashboard-load-error" class="dashboard-status" role="status"><AppShell.data_note
          :if={@error}
          severity={:problem}
        ><%= @error %></AppShell.data_note></div>
      <div
        id="dashboard-grid"
        class="dashboard-grid"
        data-role="dashboard-grid"
        phx-hook="DashboardEdit"
        data-editing={to_string(not is_nil(@edit))}
        aria-busy={if MapSet.size(@reads) > 0, do: "true"}
      >
        <.widget
          :for={item <- periods(@items, @period, @board)}
          item={item}
          period={item.period}
          {widget_assigns(assigns)}
        />
      </div>
      <.catalogue :if={@edit} />
    </div>
    """
  end

  # Each item with its period (ADR-0062 §5): the pin where it holds one,
  # else the dashboard's; a template's items follow and cannot pin. A
  # widget receives it as `period` (nil for a kind that takes none).
  defp periods(items, period, board),
    do: Enum.map(items, &Widget.with_period(&1, period, is_nil(board.template)))

  defp widget_assigns(assigns) do
    Map.take(assigns, [
      :cards,
      :attention,
      :movers,
      :data_quality,
      :last_booking,
      :stale_ttwror,
      :scope_id,
      :error,
      :views,
      :active_view,
      :privacy_mode,
      :closed_trades,
      :has_sells,
      :upcoming_events,
      :cycle_views,
      :board,
      :performance,
      :performance_bands,
      :allocation_drift,
      :snapshots,
      :crashes,
      :crash_universe
    ])
  end

  # The footer's scope (ADR-0062 §2): the view the widget reads; where its
  # item named a view that no longer exists, that it reads the dashboard's
  # scope instead. None for a kind that takes no view.
  defp scope_label(%{takes_view: false}, _views), do: nil

  defp scope_label(%{dangling: true, scope: scope_id}, views),
    do:
      gettext("Its view no longer exists · reads %{scope}",
        scope: scope_name(scope_id, views)
      )

  defp scope_label(%{scope: scope_id}, views),
    do: gettext("View %{view}", view: scope_name(scope_id, views))

  # --- the widgets ------------------------------------------------------------
  #
  # One clause per kind; each draws exactly the read its Overview card drew
  # (ADR-0062 §12), in the frame, with its compact form. Since Sprint 31 D4
  # a widget with nothing to say (data quality, due, closed trades, the
  # cycle) is drawn with one quiet line, so the grid keeps its shape; it
  # still makes no claim before its read has landed (UX-DR2).

  defp widget(%{item: %{kind: "total_value"}} = assigns) do
    assigns =
      assigns
      |> assign(:card, Map.get(assigns.cards, assigns.item.scope))
      |> assign(:stale, assigns.item.scope == assigns.scope_id && assigns.stale_ttwror)
      |> assign(:uid, assigns.item.uid)
      # Sprint 31 D4 (board ①): at S the total, its change over the
      # item's period and the period's value line; at M the total, the
      # same change and the strip, whose return is the item's period's
      # too, as its head says (Sprint 31 closing act, F1).
      |> assign(
        :change,
        Map.get(assigns.performance, {assigns.item.scope, assigns.item.period})
      )
      # Wealth on the item's period, as „Wertentwicklung“'s link opens it
      # (Sprint 31 closing act, C2/MO1): the card's figures are its.
      |> assign(:wealth_href, PerformanceWidget.wealth_href(assigns.item.period, "S"))

    ~H"""
    <Widget.frame
      id={"dashboard-wealth" <> @uid}
      item={@item}
      title={Widgets.title("total_value")}
      scope_label={scope_label(@item, @views)}
      full_href={@wealth_href}
      full_label={gettext("View in Wealth →")}
    >
      <:info>
        <%= gettext("TTWROR — time-weighted return for the selected period (not annualized). Deposits and withdrawals are neutralised so only investment performance counts.") %>
      </:info>
      <:info>
        <%= gettext("IRR — money-weighted return, annualized. Discounts the timing and size of cashflows over the period. Windows shorter than a year show the period MWR — the same figure, not annualized.") %>
      </:info>
      <:info>
        <%= gettext("Cash quote: deployable cash ÷ (securities value + deployable cash). Reserve and credit-line accounts are excluded.") %>
      </:info>
      <:shared>
        <%!-- UX-DR25 beside the figure (#1081): one status region that exists
             before the read lands (UX-DR17), so the note arriving with the
             card is announced once; empty — and taking no room — when the
             total leaves nothing out (UX-DR2: no all-clear). No whitespace
             inside it, so `:empty` holds. --%>
        <div id={"dashboard-wealth-card-status" <> @uid} role="status" class="wealth-card-status"><.wealth_card_excluded
            :if={@card && @item.size != "S"}
            uid={@uid}
            valuation={@card.valuation}
            card={@card}
            active_view={@active_view}
            wealth_href={@wealth_href}
          /><.wealth_card_excluded_short
            :if={@card && @item.size == "S"}
            valuation={@card.valuation}
            wealth_href={@wealth_href}
          /></div>
      </:shared>
      <.wealth_value
        card={@card}
        stale={@stale}
        error={@error}
        uid={@uid}
        change={{@change, @item.period}}
        wealth_href={@wealth_href}
        size={@item.size}
      />
      <Line.sparkline
        :if={@item.size == "S" && is_map(@change)}
        values={Enum.map(@change.result.series, & &1.value)}
        role="total-spark"
      />
      <.kpi_strip
        :if={@item.size != "S"}
        card={@card}
        data_quality={@data_quality}
        last_booking={@last_booking}
        uid={@uid}
        change={{@change, @item.period}}
        wealth_href={@wealth_href}
      />
      <:compact>
        <.total_value_compact
          card={@card}
          data_quality={@data_quality}
          last_booking={@last_booking}
          wealth_href={@wealth_href}
          change={{@change, @item.period}}
        />
      </:compact>
    </Widget.frame>
    """
  end

  # Sprint 31 D4: always drawn (a widget leaves no gap in the grid): busy
  # while the read runs, one quiet line when nothing is found; at S each
  # finding as a short counted line (board ①), at M the full sentences.
  defp widget(%{item: %{kind: "data_quality"}} = assigns) do
    assigns = assign(assigns, :findings, dq_findings(assigns.data_quality))

    ~H"""
    <Widget.frame
      id={"dashboard-data-quality" <> @item.uid}
      item={@item}
      title={Widgets.title("data_quality")}
      full_href="/securities?holding=held"
      full_label={if @item.size == "S", do: gettext("Check →"), else: gettext("To the securities →")}
    >
      <:info>
        <%= gettext("Each set is counted over the held securities, by the rule the list its link opens applies; the catalogue's count follows where it differs. The ledger's checks count bookings.") %>
      </:info>
      <:shared>
        <p :if={is_nil(@data_quality)} class="section-skeleton" aria-busy="true" data-role="data-quality-skeleton"></p>
        <p :if={@data_quality && @findings == []} class="hint" data-role="data-quality-empty">
          <%= gettext("No open points.") %>
        </p>
      </:shared>
      <%= if @findings != [] do %>
        <%= if @item.size == "S" do %>
          <ul class="widget-findings" data-role="data-quality-short">
            <li :for={finding <- @findings} class={"widget-findings__item is-" <> Atom.to_string(dq_severity_of(finding))}>
              <a href={finding.href} data-role={finding.role}><%= finding.short %></a>
            </li>
          </ul>
        <% else %>
          <.data_quality_line data_quality={@data_quality} uid={@item.uid} />
        <% end %>
      <% end %>
      <:compact>
        <Widget.row
          :for={finding <- @findings}
          href={finding.href}
          data-compact-role={finding.role}
        >
          <:name><%= finding.text %></:name>
          <:sub :if={finding[:effect]}><%= finding.effect %></:sub>
        </Widget.row>
      </:compact>
    </Widget.frame>
    """
  end

  defp widget(%{item: %{kind: "due"}} = assigns) do
    ~H"""
    <%!-- #828 (ADR-0048, design pick D3-A): what is due. THE DEFAULT SCOPE
         IS THE WHOLE CATALOG, not the holdings — a row for a security with
         no position is marked and kept, never filtered away, because a
         calendar derived from the position list is exactly how a purchase
         candidate's reporting date became invisible (§2). --%>
    <Widget.frame
      id={"dashboard-upcoming" <> @item.uid}
      item={@item}
      title={Widgets.title("due")}
    >
      <%!-- I1 (#1351, board ux-design-2026-11-01-sprint22/01-i1 ① ②):
           the set and the window stay as the basis line; the rule for a
           range or a month moves into the heading's ⓘ. --%>
      <:info>
        <%= gettext(
          "A date given as a range or a month counts as due when any day it could fall on is inside the horizon."
        ) %>
      </:info>
      <:shared>
        <p class="hint" data-role="upcoming-basis">
          <%= gettext(
            "Dated facts about any security in the catalog — held or not — falling in the next %{days} days.",
            days: upcoming_days()
          ) %>
        </p>
        <%!-- Sprint 31 D4: drawn when nothing is due, its quiet line in
             place of the list (a widget leaves no gap in the grid). --%>
        <p :if={@upcoming_events == []} class="hint" data-role="upcoming-empty">
          <%= gettext("Nothing due in the next %{days} days.", days: upcoming_days()) %>
        </p>
      </:shared>
      <ul :if={@upcoming_events != []} class="attention-list">
        <li :for={row <- @upcoming_events}>
          <a
            href={"/securities/#{row.event.security_id}?tab=events"}
            data-role="upcoming-event"
            class="attention-item"
          >
            <%!-- One name and one right-aligned figure, the anatomy
                 `.attention-item` is built for: a second `.attention-name`
                 span floated the kind into the middle of the row and made
                 hover underline two things as if the row were two links.
                 The kind and the timing qualifier are the name's sub-line;
                 the date is the figure, which keeps the nowrap slot short
                 enough for 390 px. --%>
            <span class="attention-name">
              <%= row.security_name %>
              <span :if={not row.held} class="badge badge--neutral" data-role="upcoming-unheld">
                <%= gettext("no position") %>
              </span>
              <small class="attention-item__sub">
                <%= SecurityEventLabel.kind(row.event.kind) %>
                · <%= SecurityEventLabel.timing(row.event.timing) %>
              </small>
            </span>
            <span class="num">
              <%= Format.date(row.event.date) %>
            </span>
          </a>
        </li>
      </ul>
      <:compact>
        <Widget.row
          :for={row <- @upcoming_events}
          href={"/securities/#{row.event.security_id}?tab=events"}
          data-compact-role="upcoming-event"
        >
          <:name><%= row.security_name %></:name>
          <:sub>
            <%= SecurityEventLabel.kind(row.event.kind) %><%= unless row.held,
              do: " · " <> gettext("no position") %>
          </:sub>
          <:figure><%= Format.date(row.event.date) %></:figure>
        </Widget.row>
      </:compact>
    </Widget.frame>
    """
  end

  defp widget(%{item: %{kind: "off_target"}} = assigns) do
    assigns =
      assigns
      |> assign(:report, Map.get(assigns.attention, assigns.item.scope))

    ~H"""
    <%!-- ADR-0022: the dashboard answers "does anything need me?". Drift
         alerts (ADR-0023 sign: positive = overweight) link straight into
         the Allocation & targets tab; the audit journal keeps the forensic
         detail that the old activity feed restated. #718 (UX-DR21 — a
         surface names what it aggregates): the card is named for its
         content, categories off their target weight, not for an urgency or
         the reaction it hopes to cause. --%>
    <Widget.frame
      id={"dashboard-attention" <> @item.uid}
      item={@item}
      title={Widgets.title("off_target")}
      scope_label={scope_label(@item, @views)}
      full_href="/portfolio?tab=allocation"
      full_label={gettext("View in Wealth →")}
    >
      <:info>
        <%= gettext("Drift is the actual weight minus the target weight of the active plan, per category of the steering tree; a category without a target is not listed.") %>
      </:info>
      <:shared>
        <%!-- Say WHY these items surface (UAT fix round): the threshold rule,
             derived from the same threshold the filter uses — and
             WHAT they are computed against (#673, {components.needs-
             attention-card}.basis-line): the view, the plan and the tree.
             Names come raw from the async read; gettext runs here, at
             render time, where the user's locale is set. --%>
        <%!-- At S in the wide form the count's line says the rule, so the
             explainer keeps its basis and leaves the rule's sentence out of
             the drawing (Sprint 31 closing act, DS1). --%>
        <p class="hint" data-role="attention-explainer">
          <span
            :if={@item.size == "S" && @report && @report.alerts != []}
            class="attention-beyond"
            data-role="off-target-beyond"
          ><%= gettext("beyond ±%{pp} pp", pp: threshold_pp()) %> · </span><span
            :if={@report && @report.basis}
            data-role="attention-basis"
          ><%= basis_phrase(
              @report.basis
            ) %></span><span class="attention-rule"><%= if @report && @report.basis,
              do: " · " %><%= if @report && @report.basis && @report.basis.several_portfolios,
              do:
                gettext(
                  "Categories ±%{pp} pp or more off their target weight, at every tree level, in every portfolio.",
                  pp: threshold_pp()
                ),
              else:
                gettext(
                  "Categories ±%{pp} pp or more off their target weight, at every tree level.",
                  pp: threshold_pp()
                ) %></span>
        </p>
        <%!-- #723: the drift report is a sub-second figure — the block
             skeleton (UX-DR20) carries the wait without the cue, which at
             that latency only registers as flicker. --%>
        <p
          :if={is_nil(@report)}
          class="section-skeleton"
          aria-busy="true"
          data-role="attention-skeleton"
        >
        </p>
        <p :if={@report && @report.alerts == []} class="hint" data-role="all-clear">
          <%= gettext("All targets within ±5 pp — nothing needs rebalancing.") %>
        </p>
      </:shared>
      <%!-- Sprint 31 closing act, DS1 (board 02 ①): at S the count of the
           categories off target and the rule, within the S row's height;
           the list is the M size's (drawn from M; at S it stays in the
           markup only, out of the drawing, and the footer leads to
           Wealth's allocation). --%>
      <div
        :if={@item.size == "S" && @report && @report.alerts != []}
        class="widget-figure"
        data-role="off-target-count"
      >
        <strong class="widget-figure__value"><%= @report.count %><small class="value-suffix"><%= ngettext(
              "category",
              "categories",
              @report.count
            ) %></small></strong>
      </div>
      <ul
        :if={@report && @report.alerts != []}
        class={["attention-list", @item.size == "S" && "widget-offtarget__list"]}
      >
        <li :for={alert <- @report.alerts}>
          <a href="/portfolio?tab=allocation" data-role="drift-alert" class="attention-item">
            <span class="attention-name">
              <%= alert.name %>
            </span>
            <%!-- #798: a decorative drift bar around zero — aria-hidden;
                 sign, colour and the direction word stay the accessible
                 channels (UX-DR7). Scaled to the worst drift listed. --%>
            <span class="drift-bar" aria-hidden="true">
              <span
                class={["drift-bar__fill", drift_bar_side(alert.drift_weight)]}
                style={"width: #{drift_bar_width(alert.drift_weight, @report.alerts)}%"}
              >
              </span>
            </span>
            <span class={["num", drift_sign_class(alert.drift_weight)]}>
              <%= drift_phrase(alert.drift_weight) %>
              · <%= Format.money(alert.drift_value) %> <%= alert.base_currency %>
            </span>
          </a>
        </li>
      </ul>
      <:compact>
        <Widget.row
          :for={alert <- (@report && @report.alerts) || []}
          href="/portfolio?tab=allocation"
          data-compact-role="drift-alert"
        >
          <:name><%= alert.name %></:name>
          <:sub><%= Format.money(alert.drift_value) %> <%= alert.base_currency %></:sub>
          <:figure>
            <span class={drift_sign_class(alert.drift_weight)}><%= drift_points(
              alert.drift_weight
            ) %></span>
          </:figure>
        </Widget.row>
      </:compact>
    </Widget.frame>
    """
  end

  defp widget(%{item: %{kind: "movers"}} = assigns) do
    window = movers_window(assigns.item)

    assigns =
      assign(assigns, card: Map.get(assigns.movers, {assigns.item.scope, window}), window: window)

    ~H"""
    <%!-- Sprint 30 T3 (ADR-0061 §9; board 04, A): which names moved the
         scope the widget names. --%>
    <MoversCard.card
      item={@item}
      window={@window}
      card={@card}
      privacy_mode={@privacy_mode}
      active_view={@active_view}
      scope_label={scope_label(@item, @views)}
    />
    """
  end

  defp widget(%{item: %{kind: "bitcoin_cycle"}} = assigns) do
    ~H"""
    <%!-- S29 H8 (ADR-0060 §11): the card „‹Name›-Zyklus“ per security
         with the cycle view, each its own read; its compact form is the
         card's list itself, which is already one event per line. --%>
    <Widget.frame
      id={"dashboard-cycles" <> @item.uid}
      item={@item}
      title={Widgets.title("bitcoin_cycle")}
      class="widget--single-form"
    >
      <:info>
        <%= gettext(
          "The range the stored cycles give from the current anchors, with its n and both ends: not a forecast."
        ) %>
      </:info>
      <:shared>
        <.cycle_cards views={@cycle_views} />
        <p :if={@cycle_views == []} class="hint" data-role="cycles-empty">
          <%= gettext("No security shows the cycle view yet.") %>
        </p>
      </:shared>
    </Widget.frame>
    """
  end

  defp widget(%{item: %{kind: "sale_review"}} = assigns) do
    ~H"""
    <.closed_trades_card card={if @has_sells, do: @closed_trades, else: :none} item={@item} />
    """
  end

  # --- S31 D4 begin ---
  # The four kinds Sprint 31's D4 draws (ADR-0062 §12), each in its own
  # module under `PortfolixirWeb.Dashboard.Widgets`.
  defp widget(%{item: %{kind: "performance"} = item} = assigns) do
    assigns =
      assign(assigns,
        card: Map.get(assigns.performance, {item.scope, assigns.period}),
        bands: Map.get(assigns.performance_bands, {item.scope, assigns.period})
      )

    ~H"""
    <PerformanceWidget.widget
      item={@item}
      period={@period}
      card={@card}
      bands={@bands}
      scope_label={scope_label(@item, @views)}
    />
    """
  end

  defp widget(%{item: %{kind: "allocation_drift"} = item} = assigns) do
    assigns = assign(assigns, :card, Map.get(assigns.allocation_drift, item.scope))

    ~H"""
    <AllocationDriftWidget.widget item={@item} card={@card} scope_label={scope_label(@item, @views)} />
    """
  end

  defp widget(%{item: %{kind: "snapshots"}} = assigns) do
    ~H"""
    <SnapshotsWidget.widget item={@item} card={@snapshots} />
    """
  end

  defp widget(%{item: %{kind: "crashes"}} = assigns) do
    assigns = assign(assigns, :card, Map.get(assigns.crashes, assigns.crash_universe))

    ~H"""
    <CrashesWidget.widget item={@item} universe={@crash_universe} card={@card} />
    """
  end

  # --- S31 D4 end ---

  attr(:card, :any, required: true)
  attr(:stale, :any, required: true)
  attr(:error, :any, required: true)
  attr(:uid, :string, required: true)

  attr(:change, :any,
    default: nil,
    doc: "`{read, period}`, the item's period's performance read (Sprint 31 D4, F1)"
  )

  attr(:wealth_href, :string, required: true)
  attr(:size, :string, default: "M")

  # #1081 (D-3, board 01 pick J1 A): the value in every state.
  defp wealth_value(assigns) do
    ~H"""
    <%= cond do %>
      <% @card && @size == "S" -> %>
      <%!-- Sprint 31 closing act, DS2 (board 02 ①, as planning board 01 ①
           draws it): at S the widget draws the figure itself, no card in
           the card — the total with its currency, then the change over the
           item's period; the scope is the footer's, and the link's name. --%>
      <a id={"dashboard-wealth-card" <> @uid} href={@wealth_href} class="widget-total">
        <span class="visually-hidden"><%= @card.name || gettext("Everything") %></span>
        <strong class="widget-total__figure">
          <span
            id={"count-wealth-card" <> @uid}
            class="count-up"
            phx-hook="CountUp"
            data-count-to={Format.amount_attribute(@card.valuation.total_with_cash)}
            data-decimals="2"
          ><span data-count-digits><%= Format.money(@card.valuation.total_with_cash) %></span></span><small class="value-suffix"><%= @card.valuation.base_currency %></small>
        </strong>
        <.period_change :if={@change} change={@change} />
      </a>
      <% is_nil(@card) -> %>
      <%!-- Pending with a prior value (UX-DR20, owner pick P2): the last
           known value stays in place, dimmed, with a real-text staleness
           marker BEFORE the digits and the recomputing cue beneath. The
           slot carries aria-busy and sits in no live region. --%>
      <article
        :if={@stale && is_nil(@error)}
        class="stat"
        data-role="overview-stale"
      >
        <span><%= gettext("year to date") %></span>
        <strong class="value-slot-stale" aria-busy="true">
          <span class="visually-hidden"><%= gettext("Last known value —") %></span>
          <span class="stale-value"><%= signed_percent(@stale.ttwror) %>%</span>
        </strong>
        <small data-role="stale-ttwror" class="recomputing-cue">
          <span class="spinner"></span>
          <%= ngettext(
            "Last known: %{ttwror}% year to date — one booking through %{last}, as of %{date}. Recomputing.",
            "Last known: %{ttwror}% year to date — %{count} bookings through %{last}, as of %{date}. Recomputing.",
            @stale.basis.booking_count,
            ttwror: signed_percent(@stale.ttwror),
            last: Format.date(@stale.basis.last_booking_date),
            date: Format.date(@stale.as_of)
          ) %>
        </small>
      </article>
      <article
        :if={!@stale && is_nil(@error)}
        class="stat"
        aria-busy="true"
        data-role="overview-skeleton"
      >
        <strong><span class="value-skeleton" aria-hidden="true"></span></strong>
        <small class="recomputing-cue">
          <span class="spinner"></span> <%= gettext("computing") %>
        </small>
      </article>
      <% true -> %>
      <%!-- #1122 (board 01 ④, option 3): the card's period travels,
           read on arrival and never stored; no `?view=`. --%>
      <a id={"dashboard-wealth-card" <> @uid} href={@wealth_href} class="stat stat--link">
        <span><%= @card.name || gettext("Everything") %></span>
        <strong>
          <span
            id={"count-wealth-card" <> @uid}
            class="count-up"
            phx-hook="CountUp"
            data-count-to={Format.amount_attribute(@card.valuation.total_with_cash)}
            data-decimals="2"
          ><span data-count-digits><%= Format.money(@card.valuation.total_with_cash) %></span></span><small class="value-suffix"><%= @card.valuation.base_currency %></small>
        </strong>
        <%!-- The sub-line keeps the YTD change; the cash quote moved to
             the strip's own cell (UX-DR2 as amended 2026-09-14). The
             card is a link and cannot hold an ⓘ, so it says the period
             in words (#1090, board 08 ③) under a msgid of its own: "YTD"
             stays the period token of the range controls. --%>
        <%= if @change do %>
          <.period_change change={@change} />
        <% else %>
          <small :if={@card.ttwror} data-role="card-ttwror">
            <span class={sign_class(@card.ttwror)}><%= signed_percent(@card.ttwror) %>%</span>
            <%= gettext("year to date") %>
          </small>
          <small :if={is_nil(@card.ttwror)} data-role="card-ttwror">
            <%= gettext("year to date") %> —
          </small>
        <% end %>
      </a>
    <% end %>
    """
  end

  attr(:change, :any, required: true)

  # Sprint 31 D4 (board ①; ADR-0062 §5): the total's change at S, the
  # period's TTWROR as `GET /api/v1/performance` answers it for the
  # dashboard's period, labelled with the period; the figure's slot is
  # held while the read runs.
  defp period_change(%{change: {read, period}} = assigns) do
    assigns = assign(assigns, read: read, label: Widget.period_label(period))

    ~H"""
    <small data-role="card-period-change">
      <.change_figure read={@read} />
      <%= gettext("TTWROR · %{period}", period: @label) %>
    </small>
    """
  end

  attr(:read, :any, required: true)

  # The period's TTWROR, signed and coloured; its slot held while the read
  # runs, a dash when it failed.
  defp change_figure(assigns) do
    ~H"""
    <%= if is_map(@read) do %>
      <span class={sign_class(@read.result.ttwror)}><%= signed_percent(@read.result.ttwror) %>%</span>
    <% else %>
      <span :if={is_nil(@read)} class="value-skeleton" aria-hidden="true"></span>
      <span :if={@read == :error}>—</span>
    <% end %>
    """
  end

  attr(:card, :any, required: true)
  attr(:data_quality, :any, required: true)
  attr(:last_booking, :any, required: true)
  attr(:uid, :string, required: true)

  attr(:change, :any,
    required: true,
    doc: "`{read, period}`, the item's period's performance read"
  )

  attr(:wealth_href, :string, required: true)

  # #798 (UX-DR2 as amended 2026-09-14): the four questions of the morning
  # on one strip — return, cash quote, last booking, quote freshness — each
  # cell stating its basis and linking to the surface that owns the figure.
  # In the widget „Gesamtwert“ under the value it explains (ADR-0062 §12:
  # the Overview's value block is one widget). The return is the item's
  # period's, labelled with it (Sprint 31 closing act, F1).
  defp kpi_strip(%{change: {read, period}} = assigns) do
    assigns = assign(assigns, read: read, label: Widget.period_label(period))

    ~H"""
    <div id={"dashboard-kpi-strip" <> @uid} class="kpi-strip" aria-label={gettext("Key figures")} role="group">
      <div class="kpi-strip__cells">
        <a href={@wealth_href} class="kpi-strip__cell" data-role="kpi-ttwror">
          <span class="kpi-strip__label"><%= gettext("TTWROR · %{period}", period: @label) %></span>
          <%= cond do %>
            <% is_map(@read) -> %>
              <strong class={sign_class(@read.result.ttwror)}>
                <%= signed_percent(@read.result.ttwror) %>%
              </strong>
              <small class="kpi-strip__sub"><%= money_weighted_line(@read.result) %></small>
            <% @read == :error -> %>
              <strong class="kpi-strip__na">—</strong>
              <small class="kpi-strip__sub"><%= money_weighted_line(nil) %></small>
            <% true -> %>
              <.strip_pending />
          <% end %>
        </a>
        <a href="/portfolio" class="kpi-strip__cell" data-role="kpi-cash-quote">
          <span class="kpi-strip__label"><%= gettext("Cash quote") %></span>
          <%= if @card do %>
            <strong><%= Format.percent(@card.valuation.cash_quote) %>%</strong>
            <small class="kpi-strip__sub">
              <%= Format.money(@card.valuation.total_cash) %> <%= @card.valuation.base_currency %> <%= gettext(
                "cash"
              ) %>
            </small>
          <% else %>
            <.strip_pending />
          <% end %>
        </a>
        <%!-- The ledger's newest booking, kind label localized here at
             render time (the async task has no user locale). --%>
        <a href="/transactions" class="kpi-strip__cell" data-role="kpi-last-booking">
          <span class="kpi-strip__label"><%= gettext("Last booking") %></span>
          <%= if @card do %>
            <strong :if={@last_booking}><%= Format.date(@last_booking.date) %></strong>
            <strong :if={is_nil(@last_booking)} class="kpi-strip__na">—</strong>
            <small :if={@last_booking} class="kpi-strip__sub">
              <%= TransactionKindLabel.label(@last_booking.type) %><%= if @last_booking.subject,
                do: " · #{@last_booking.subject}" %>
            </small>
          <% else %>
            <.strip_pending />
          <% end %>
        </a>
        <%!-- Freshness: the newest stored quote across the held positions is
             the fact; the stale count is the finding, shown only when it
             exists (no all-clear badge) and linking where the data-quality
             line's quote count links: the held list (issue 1417). --%>
        <a
          href="/securities?dq=stale_quote&holding=held"
          class="kpi-strip__cell"
          data-role="kpi-freshness"
        >
          <span class="kpi-strip__label"><%= gettext("Quotes") %></span>
          <%= if @card do %>
            <strong :if={@card.valuation.newest_quote_date}>
              <%= Format.date(@card.valuation.newest_quote_date) %>
            </strong>
            <strong :if={is_nil(@card.valuation.newest_quote_date)} class="kpi-strip__na">
              —
            </strong>
            <%!-- The count is the one the link resolves to: the stale_quote
                 predicate over the held securities, the same rule and
                 scope as the data-quality finding and the list the href
                 opens (#705). Issue 1417: "n held stale". --%>
            <small
              :if={@data_quality && @data_quality.without_quote > 0}
              class="kpi-strip__sub kpi-strip__sub--attention"
            >
              <AppShell.icon name={:alert_triangle} size={12} />
              <span><%= ngettext(
                "%{count} held stale",
                "%{count} held stale",
                @data_quality.without_quote
              ) %></span>
            </small>
          <% else %>
            <.strip_pending />
          <% end %>
        </a>
      </div>
      <%!-- The strip's three domain metrics carry their definition in the
           widget's ⓘ: a cell is a link, and a <details> inside a link is
           invalid interactive nesting. The basis line names the view, the
           period, the date and the currency. --%>
      <div :if={@card} class="summary-basis kpi-strip__basis" data-role="kpi-strip-basis">
        <%= gettext("View %{view} · return over %{period} to %{date} · in %{currency} · quotes: the newest across held positions",
          view: @card.name || gettext("Everything"),
          period: @label,
          date: Format.date(strip_as_of(@read)),
          currency: @card.valuation.base_currency
        ) %>
      </div>
    </div>
    """
  end

  attr(:card, :any, required: true)
  attr(:data_quality, :any, required: true)
  attr(:last_booking, :any, required: true)
  attr(:wealth_href, :string, required: true)

  attr(:change, :any,
    required: true,
    doc: "`{read, period}`, the item's period's performance read"
  )

  # The compact form of „Gesamtwert“ (board 06): the view, the total at
  # figure size, the item's period's change under it, then the strip's
  # four figures one per row, the return the same period's (F1).
  defp total_value_compact(%{change: {read, period}} = assigns) do
    assigns = assign(assigns, read: read, label: Widget.period_label(period))

    ~H"""
    <%= if @card do %>
      <a class="widget-total" href={@wealth_href} data-compact-role="total">
        <span class="widget-total__label"><%= @card.name || gettext("Everything") %></span>
        <strong class="widget-total__figure num">
          <%= Format.money(@card.valuation.total_with_cash) %>
          <small class="value-suffix"><%= @card.valuation.base_currency %></small>
        </strong>
        <small class="widget-total__sub">
          <.change_figure read={@read} />
          <%= gettext("TTWROR · %{period}", period: @label) %>
        </small>
      </a>
      <Widget.row href={@wealth_href} data-compact-role="kpi-ttwror">
        <:name><%= gettext("TTWROR · %{period}", period: @label) %></:name>
        <:sub><%= money_weighted_line(if is_map(@read), do: @read.result) %></:sub>
        <:figure><.change_figure read={@read} /></:figure>
      </Widget.row>
      <Widget.row href="/portfolio" data-compact-role="kpi-cash-quote">
        <:name><%= gettext("Cash quote") %></:name>
        <:sub>
          <%= Format.money(@card.valuation.total_cash) %> <%= @card.valuation.base_currency %> <%= gettext("cash") %>
        </:sub>
        <:figure><%= Format.percent(@card.valuation.cash_quote) %>%</:figure>
      </Widget.row>
      <Widget.row href="/transactions" data-compact-role="kpi-last-booking">
        <:name><%= gettext("Last booking") %></:name>
        <:sub :if={@last_booking}><%= TransactionKindLabel.label(@last_booking.type) %></:sub>
        <:figure>
          <%= if @last_booking, do: Format.date(@last_booking.date), else: "—" %>
        </:figure>
      </Widget.row>
      <Widget.row href="/securities?dq=stale_quote&holding=held" data-compact-role="kpi-freshness">
        <:name><%= gettext("Quotes") %></:name>
        <:sub :if={@data_quality && @data_quality.without_quote > 0}>
          <%= ngettext("%{count} held stale", "%{count} held stale", @data_quality.without_quote) %>
        </:sub>
        <:figure>
          <%= if @card.valuation.newest_quote_date,
            do: Format.date(@card.valuation.newest_quote_date),
            else: "—" %>
        </:figure>
      </Widget.row>
    <% else %>
      <p class="section-skeleton" aria-busy="true"></p>
    <% end %>
    """
  end

  attr(:data_quality, :map, required: true)
  attr(:uid, :string, required: true)

  # Data quality is ONE line (UX-DR2, decided 2026-07-12, adopted
  # 2026-08-05): drawn only when a count is non-zero, no green all-clear
  # badge, each count linking to the securities list PRE-FILTERED to the
  # offending set (#561, unblocked by #651). While the overview computes,
  # the widget is simply absent — a finding surface makes no claim before a
  # finding exists. One data-note at the highest severity present
  # (UX-DR17); the remedy links live inside the note, in its actions, so
  # the clamp never cuts them (#1351, pick Q1, correction 2). role="status"
  # sits on the region so the async arrival announces once.
  defp data_quality_line(assigns) do
    ~H"""
    <div role="status">
      <AppShell.data_note
        severity={dq_severity(@data_quality)}
        id={"dashboard-dq-line" <> @uid}
        data-role="data-quality-line"
        clamp
      >
        <:actions>
          <%= for {finding, index} <- Enum.with_index(dq_findings(@data_quality)) do %>
            <%= if index > 0 do %>
              <span aria-hidden="true"> · </span>
            <% end %>
            <a href={finding.href} data-role={finding.role}><%= finding.text %></a>
            <%!-- Issue 1417 (board ux-design-2026-11-12-sprint29/04 ② A):
                 the count is the held securities'; the catalogue's
                 stands after it in parentheses, as its own link, only
                 where the two differ. --%>
            <span :if={finding[:catalog]} class="dq-catalog" data-catalog-of={finding.role}>(<a href={finding.catalog.href}><%= ngettext("%{count} in the catalog", "%{count} in the catalog", finding.catalog.count) %></a>)</span>
            <%!-- #1121 (board 01 ③, pick N3 A): a finding in the total
                 says what it does to the total above, after its link and
                 outside it, so the link still names the list it opens.
                 The card stays silent (#703's split, D-7). Keyed by
                 `data-effect-of`, so the line's `data-role`s stay one per
                 finding. --%>
            <span :if={finding[:effect]} data-effect-of={finding.role}><%= finding.effect %></span>
          <% end %>
        </:actions>
      </AppShell.data_note>
    </div>
    """
  end

  attr(:card, :any, required: true)
  attr(:item, :map, required: true)

  # #984 (board G1, pick A; UX-DR2 amended 2026-10-01 with a fifth block):
  # "was the trade worth it", answered where the owner lands. The newest
  # five closed trades — results, not activity: ADR-0022 §7 dropped the raw
  # recent-activity feed, and a sale is listed here for what it realised,
  # never as a booking. The card covers every depot whatever the view, as
  # the realized report does, and its basis line says so. Built from
  # existing parts: the `.attention-list` of "Off target" and "Due". Since
  # Sprint 31 D3 the widget „Verkaufsrückblick“ (ADR-0062 §12): the same
  # read, in the widget's frame, its link to every trade in the footer.
  #
  # States: pending — the block skeleton (UX-DR20), no cue, the list is a
  # sub-second read; populated; a sale the rates cannot convert named in an
  # attention note (UX-DR25), pointing to the backfill on the facet; absent
  # with no closed trade and no exclusion, like "Due" without a date. A sell
  # with no matched buy is no trade, so it is not missing from the five; the
  # facet names it where the totals are read.
  defp closed_trades_card(%{card: %{trades: [], excluded: %{count: 0}}} = assigns),
    do: closed_trades_card(%{assigns | card: :none})

  defp closed_trades_card(assigns) do
    assigns = assign(assigns, :ready, is_map(assigns.card))

    ~H"""
    <Widget.frame
      id={"dashboard-trades" <> @item.uid}
      item={@item}
      title={Widgets.title("sale_review")}
      scope_label={gettext("Every depot, whatever the view")}
      full_href="/cashflow?tab=realized"
      full_label={gettext("All trades →")}
    >
      <%!-- I1 (#1351, board 01 ① ②): the p. a. rule in the heading's ⓘ;
           the set, the currency and the depots stay as the basis line. --%>
      <:info>
        <%= gettext("p. a. only from 365 days of holding and only where a rate solves the flows") %>
      </:info>
      <:shared>
        <p
          :if={is_nil(@card)}
          class="section-skeleton"
          aria-busy="true"
          data-role="trades-card-skeleton"
        >
        </p>
        <%!-- Sprint 31 D4: drawn with no closed trade, its quiet line in
             place of the list (a widget leaves no gap in the grid). --%>
        <p :if={@card == :none} class="hint" data-role="trades-card-empty">
          <%= gettext("No closed sales booked yet.") %>
        </p>
        <AppShell.data_note
          :if={@card == :error}
          severity={:problem}
          id={"trades-card-error" <> @item.uid}
          data-role="trades-card-error"
          clamp
        >
          <%= gettext("Couldn't load the closed trades.") %>
        </AppShell.data_note>
        <.trades_excluded :if={@ready} card={@card} uid={@item.uid} />
      </:shared>
      <%= if @ready do %>
      <p :if={@card.trades != []} class="summary-basis" data-role="trades-card-basis">
        <%!-- Counts what the card shows: five at most (closing act γ n3).
             #1171 (board 01 ⑤): both limits of p. a., the facet's clause
             word for word (DESIGN.md → The list's basis line). --%>
        <%= ngettext(
          "The most recently closed · result in %{currency} · FIFO across every depot, whatever the view",
          "The %{count} most recently closed · result in %{currency} · FIFO across every depot, whatever the view",
          length(@card.trades),
          currency: @card.base_currency
        ) %>
      </p>
      <ul :if={@card.trades != []} class="attention-list">
        <li :for={trade <- @card.trades}>
          <a
            href={"/securities/#{trade.security_id}?tab=trades"}
            class="attention-item"
            data-role="closed-trade"
          >
            <span class="attention-name">
              <%= trade.security_name %><SecurityNames.twin_id tag={trade.twin_id} />
              <small class="attention-item__sub">
                <%= gettext("sold %{date}", date: Format.date(trade.close_date)) %> · <%= ngettext(
                  "%{count} day",
                  "%{count} days",
                  trade.holding_period_days
                ) %>
              </small>
            </span>
            <span class="num">
              <span class={money_sign_class(trade.realized_base)}><%= Format.signed_decimal(
                trade.realized_base,
                2
              ) %></span><small class="value-suffix"><%= @card.base_currency %></small>
              <small class="attention-item__sub">
                <%= if trade.annualized_return do %>
                  <span class={sign_class(trade.annualized_return)}><%= signed_percent(
                    trade.annualized_return
                  ) %>%</span>
                  <%= gettext("p. a.") %>
                <% else %>
                  <%= if trade.realized_pnl_pct do %>
                    <span class={sign_class(trade.realized_pnl_pct)}><%= signed_percent(
                      trade.realized_pnl_pct
                    ) %>%</span>
                    <%= gettext("total") %>
                  <% else %>
                    <%!-- #1142 (board 02, found while drawing 9): a
                         trade on no cost has no return; the card says
                         so in words, as the facet's phone row does,
                         where "0.0% total" read as a flat trade. --%>
                    <span data-role="return-absent"><span aria-hidden="true">—</span> <%= gettext(
                        "no cost basis"
                      ) %></span>
                  <% end %>
                <% end %>
              </small>
            </span>
          </a>
        </li>
      </ul>
      <% end %>
      <:compact>
        <Widget.row
          :for={trade <- (@ready && @card.trades) || []}
          href={"/securities/#{trade.security_id}?tab=trades"}
          data-compact-role="closed-trade"
        >
          <:name>
            <%= trade.security_name %><SecurityNames.twin_id tag={trade.twin_id} />
          </:name>
          <:sub><%= gettext("sold %{date}", date: Format.date(trade.close_date)) %></:sub>
          <:figure>
            <span class={money_sign_class(trade.realized_base)}><%= Format.signed_decimal(
              trade.realized_base,
              2
            ) %></span>
          </:figure>
          <:figure_sub><%= @card.base_currency %></:figure_sub>
        </Widget.row>
      </:compact>
    </Widget.frame>
    """
  end

  # The names of one reason's left-out sales, each security once, a twin
  # with what tells it apart (#1320).
  defp excluded_names(card, reason) do
    card.excluded_securities
    |> Map.fetch!(reason)
    |> Enum.map_join(", ", &SecurityNames.twin_name(&1.security_name, &1.twin_id))
  end

  attr(:card, :map, required: true)
  attr(:uid, :string, required: true)

  # The sales the rates cannot convert, named (UX-DR25).
  defp trades_excluded(assigns) do
    ~H"""
      <AppShell.data_note
        :if={@card.excluded.count > 0}
        severity={:attention}
        id={"trades-card-excluded" <> @uid}
        data-role="trades-card-excluded"
        clamp
      >
        <%!-- #1351 closing act (pick Q1; DESIGN.md ③): with two or more
             reasons every reason's count leads, so none falls below the
             clamp. --%>
        <span
          :if={counts = ExcludedSales.counts(@card.excluded.by_reason)}
          data-role="trades-card-excluded-counts"
        ><%= gettext("Left out of the trades: %{counts}.", counts: counts) %> </span>
        <%!-- The polish list #1358 (Sprint 31 D3): the sentences no rate can
           fix (#1310, #1311) come first, so the backfill's pointer stands
           last, right after the sentences it helps with. --%>
      <%!-- #1310: a sale or a buy priced in a third currency, which no
             rate fixes, in a sentence of its own, with no backfill
             pointer. --%>
        <span
          :if={@card.excluded.by_reason.third_currency.count > 0}
          data-role="trades-card-excluded-third-currency"
        ><%= StoredText.ending_on(
          excluded_names(@card, :third_currency),
          &ngettext(
            "%{count} sale not convertible — it or a buy it closes is priced in a currency that is neither the security's nor its account's — is left out of the trades: %{securities}.",
            "%{count} sales not convertible — each or a buy it closes is priced in a currency that is neither the security's nor its account's — are left out of the trades: %{securities}.",
            @card.excluded.by_reason.third_currency.count,
            securities: &1
          ),
          &ngettext(
            "%{count} sale not convertible — it or a buy it closes is priced in a currency that is neither the security's nor its account's — is left out of the trades: %{securities}",
            "%{count} sales not convertible — each or a buy it closes is priced in a currency that is neither the security's nor its account's — are left out of the trades: %{securities}",
            @card.excluded.by_reason.third_currency.count,
            securities: &1
          )
        ) %></span>
        <%!-- #1310: a buy paid in a currency no leg bridges; no backfill pointer. --%>
        <span
          :if={@card.excluded.by_reason.other_account_currency.count > 0}
          data-role="trades-card-excluded-other-account"
        ><%= StoredText.ending_on(
          excluded_names(@card, :other_account_currency),
          &ngettext(
            "%{count} sale not convertible — a buy it closes was paid in another currency than the sale's, which no stored figure bridges — is left out of the trades: %{securities}.",
            "%{count} sales not convertible — a buy each closes was paid in another currency than its sale's, which no stored figure bridges — are left out of the trades: %{securities}.",
            @card.excluded.by_reason.other_account_currency.count,
            securities: &1
          ),
          &ngettext(
            "%{count} sale not convertible — a buy it closes was paid in another currency than the sale's, which no stored figure bridges — is left out of the trades: %{securities}",
            "%{count} sales not convertible — a buy each closes was paid in another currency than its sale's, which no stored figure bridges — are left out of the trades: %{securities}",
            @card.excluded.by_reason.other_account_currency.count,
            securities: &1
          )
        ) %></span>
        <%!-- #1311: a buy of zero amount; no backfill pointer. --%>
        <span
          :if={@card.excluded.by_reason.zero_amount.count > 0}
          data-role="trades-card-excluded-zero-amount"
        ><%= StoredText.ending_on(
          excluded_names(@card, :zero_amount),
          &ngettext(
            "%{count} sale not convertible — a buy it closes has an amount of zero, which the rate backfill does not complete — is left out of the trades: %{securities}.",
            "%{count} sales not convertible — a buy each closes has an amount of zero, which the rate backfill does not complete — are left out of the trades: %{securities}.",
            @card.excluded.by_reason.zero_amount.count,
            securities: &1
          ),
          &ngettext(
            "%{count} sale not convertible — a buy it closes has an amount of zero, which the rate backfill does not complete — is left out of the trades: %{securities}",
            "%{count} sales not convertible — a buy each closes has an amount of zero, which the rate backfill does not complete — are left out of the trades: %{securities}",
            @card.excluded.by_reason.zero_amount.count,
            securities: &1
          )
        ) %></span>
        <%!-- #1198 (board 09, pick N8 A): the second reason in a
             sentence of its own, the existing pointer to the backfill
             after it. --%>
        <span
          :if={@card.excluded.by_reason.no_rate.count > 0}
          data-role="trades-card-excluded-no-rate"
        ><%= StoredText.ending_on(
          excluded_names(@card, :no_rate),
          &ngettext(
            "%{count} sale with no stored rate on its close date is left out of the trades: %{securities}. The rate backfill is under “All trades”.",
            "%{count} sales with no stored rate on their close dates are left out of the trades: %{securities}. The rate backfill is under “All trades”.",
            @card.excluded.by_reason.no_rate.count,
            securities: &1
          ),
          &ngettext(
            "%{count} sale with no stored rate on its close date is left out of the trades: %{securities} The rate backfill is under “All trades”.",
            "%{count} sales with no stored rate on their close dates are left out of the trades: %{securities} The rate backfill is under “All trades”.",
            @card.excluded.by_reason.no_rate.count,
            securities: &1
          )
        ) %></span>
        <span
          :if={@card.excluded.by_reason.missing_settlement_leg.count > 0}
          data-role="trades-card-excluded-missing-leg"
        ><%= StoredText.ending_on(
          excluded_names(@card, :missing_settlement_leg),
          &ngettext(
            "%{count} sale not convertible — a buy it closes has no figure in the sale's currency — is left out of the trades: %{securities}.",
            "%{count} sales not convertible — a buy each closes has no figure in its sale's currency — are left out of the trades: %{securities}.",
            @card.excluded.by_reason.missing_settlement_leg.count,
            securities: &1
          ),
          &ngettext(
            "%{count} sale not convertible — a buy it closes has no figure in the sale's currency — is left out of the trades: %{securities}",
            "%{count} sales not convertible — a buy each closes has no figure in its sale's currency — are left out of the trades: %{securities}",
            @card.excluded.by_reason.missing_settlement_leg.count,
            securities: &1
          )
        ) %><%= if @card.excluded.by_reason.no_rate.count == 0,
          do: " " <> gettext("The rate backfill is under “All trades”.") %></span>
      </AppShell.data_note>

    """
  end

  attr(:valuation, :map, required: true)
  attr(:card, :map, required: true)
  attr(:active_view, :any, default: nil)
  attr(:uid, :string, default: "")
  attr(:wealth_href, :string, required: true)

  # #1081 (D-3, board 01 pick J1 A; UX-DR25 clauses 1–3): what the card's
  # total leaves out, named beside it — the cash accounts with no rate path
  # to the base currency with their native balances, the held positions with
  # no price, and those with a price but no rate path with their native
  # price. One attention note, the groups in that order, each shortened by
  # Wealth's rule (six names, then "+N"); no note when nothing is left out.
  # It reads only the valuation the card already reads, and its names come
  # from the helpers Wealth's notes use. No control: the rate sync and the
  # price are fixed on Wealth, so the note links there. The link is the
  # card's own — Wealth on the card's period, read on arrival;
  # the session's view, no `?view=`, nothing stored (#1122, board 01 ④,
  # option 3). Where the session's view is not the card's, one sentence
  # before the link names both, so the reader knows Wealth will show
  # another scope. Localized here, at render time (the async task has no
  # locale).
  defp wealth_card_excluded(assigns) do
    assigns =
      assigns
      |> assign(
        :groups,
        ValuationNotes.excluded_groups(assigns.valuation, assigns.card.unvalued_twin_ids)
      )
      |> assign(:counts, ValuationNotes.excluded_counts(assigns.valuation))
      |> assign(:active_id, assigns.active_view && assigns.active_view.id)

    ~H"""
    <%!-- I1 (#1351, board 01 ③): the note names what the total leaves
         out, so it clamps and never folds; its count leads the text, and
         the link stays visible under the clamp. --%>
    <AppShell.data_note
      :if={@groups != []}
      severity={:attention}
      id={"wealth-card-excluded" <> @uid}
      data-role="wealth-card-excluded"
      clamp
    >
      <%!-- #1351 closing act (pick Q1; DESIGN.md ③): with two or more
           groups every group's count leads, so none falls below the clamp;
           the groups with their names follow. --%>
      <%= if length(@groups) > 1 do %>
        <span data-role="wealth-card-excluded-counts"><%= gettext("Not in the total: %{counts}.", counts: Enum.join(@counts, ", ")) %> </span><%= PrivacyMode.html(excluded_groups_sentence(Enum.join(@groups, " · "))) %>
      <% else %>
        <%= PrivacyMode.html(excluded_sentence(Enum.join(@groups, " · "))) %>
      <% end %>
      <%!-- The space before the link is the sentence's own: a parser that
           drops whitespace-only text between two elements keeps it. --%>
      <span :if={@active_id != @card.view_id} data-role="wealth-card-view"><%= view_sentence(@active_view, @card) %> </span>
      <:actions>
        <a href={@wealth_href} data-role="wealth-card-excluded-link"><%= gettext("Details in Wealth →") %></a>
      </:actions>
    </AppShell.data_note>
    <%!-- #1222 (the polish list #1358; Sprint 31 D3): where the total
         leaves nothing out there is no note to carry the sentence, so it
         stands alone, a quiet line, whenever Wealth would open on another
         view than the total counts. --%>
    <p
      :if={@groups == [] and @active_id != @card.view_id}
      class="hint"
      data-role="wealth-card-view"
    ><%= view_sentence(@active_view, @card) %></p>
    """
  end

  attr(:valuation, :map, required: true)
  attr(:wealth_href, :string, required: true)

  # Sprint 31 D4 (the orchestrator's follow-up 1; board ①): at S what the
  # total leaves out in one line, each group's count and the link to
  # Wealth's notes; the names stay in the full note at M and on Wealth.
  defp wealth_card_excluded_short(assigns) do
    assigns = assign(assigns, :counts, ValuationNotes.excluded_counts(assigns.valuation))

    ~H"""
    <p :if={@counts != []} class="widget-warning" data-role="wealth-card-excluded-short">
      <AppShell.icon name={:alert_triangle} size={12} />
      <span><%= gettext("Not in the total: %{counts}.", counts: Enum.join(@counts, ", ")) %></span>
      <a href={@wealth_href}><%= gettext("Details in Wealth →") %></a>
    </p>
    """
  end

  # Both names are stored text, each in its own `<bdi>` (H8.8).
  defp view_sentence(active_view, card) do
    StoredText.isolate(
      gettext("Wealth is currently scoped to the view “%{active}”; this total counts “%{card}”.",
        active: StoredText.slot(:active),
        card: StoredText.slot(:card)
      ),
      active: (active_view && active_view.name) || gettext("Everything"),
      card: card.name || gettext("Everything")
    )
  end

  # A last name that ends in a full stop ("Harborline Freight Inc.") closes
  # the sentence itself; a second one would read "Inc.." (M6, on the shared
  # helper since #1208).
  # The groups after their counts: the sentence ends once, as
  # `excluded_sentence/1`'s does, on a name that ends in a full stop.
  defp excluded_groups_sentence(groups), do: StoredText.ending_on(groups, &(&1 <> "."), & &1)

  defp excluded_sentence(groups) do
    StoredText.ending_on(
      groups,
      &gettext("Not in the total: %{groups}.", groups: &1),
      &gettext("Not in the total: %{groups}", groups: &1)
    )
  end

  # The pending footprint of a strip cell (UX-DR20): the value-sized
  # placeholder, aria-busy, no cue — the strip is a sub-second figure (#723).
  defp strip_pending(assigns) do
    ~H"""
    <strong class="value-slot-pending" aria-busy="true">
      <span class="value-skeleton" aria-hidden="true"></span>
    </strong>
    """
  end

  # The cross-portfolio view walk the card and the strip chain their periods
  # from (#577, ADR-0019 at the view boundary); nil when it cannot run yet.
  defp view_analysis(view_id, base_currency) do
    case Performance.view_analysis(view_id, base_currency: base_currency) do
      %{} = analysis -> analysis
      _error -> nil
    end
  end

  defp summarise(nil, _period), do: nil

  defp summarise(analysis, period) do
    case Performance.summarise(analysis, period) do
      {:ok, summary} -> summary
      _error -> nil
    end
  end

  # The YTD TTWROR as the card's "did anything change" signal; nil (hidden)
  # when the period cannot be computed yet.
  defp ttwror_of(%{ttwror: %Decimal{} = ttwror}), do: ttwror
  defp ttwror_of(_summary), do: nil

  # The strip's money-weighted sub-line follows the Wealth band's rule
  # (ADR-0034 §2): the annualized IRR for a full year of history, the period
  # MWR for a shorter window — labelled as what it is.
  defp money_weighted_line(nil), do: gettext("IRR") <> " —"

  defp money_weighted_line(summary) do
    {label, value} =
      if short_window?(summary),
        do: {gettext("MWR"), summary.mwr},
        else: {gettext("IRR"), summary.irr}

    case value do
      %Decimal{} -> "#{label} #{signed_percent(value)}%"
      _none -> label <> " —"
    end
  end

  defp short_window?(%{start_date: %Date{} = start_date, end_date: %Date{} = end_date}),
    do: Date.diff(end_date, start_date) + 1 < 365

  defp short_window?(_summary), do: false

  # The date the strip's return runs to: its read's end, today while it
  # runs.
  defp strip_as_of(%{result: %{end_date: %Date{} = end_date}}), do: end_date
  defp strip_as_of(_read), do: Portfolixir.Clock.today()

  # The ledger's newest booking (#798): newest date, newest id — the order
  # the history opens on. Raw record; the kind label is localized at render
  # time, because this runs in the async task, which has no user locale.
  defp last_booking do
    case Ledger.list_transactions(limit: 1) do
      [transaction] ->
        %{
          date: transaction.date,
          type: transaction.type,
          subject: booking_subject(transaction)
        }

      [] ->
        nil
    end
  end

  defp booking_subject(%{security: %{name: name}}) when is_binary(name), do: name
  defp booking_subject(%{cash_account: %{name: name}}) when is_binary(name), do: name
  defp booking_subject(%{securities_account: %{name: name}}) when is_binary(name), do: name
  defp booking_subject(_transaction), do: nil

  # The drift bar's side and length (#798): over target grows right of the
  # zero line, under target grows left; the worst drift listed fills 45 % of
  # the track, so the rows read against each other.
  defp drift_bar_side(drift_weight) do
    if Decimal.compare(drift_weight, 0) == :lt, do: "is-under", else: "is-over"
  end

  defp drift_bar_width(drift_weight, alerts) do
    worst =
      alerts
      |> Enum.map(&Decimal.abs(&1.drift_weight))
      |> Enum.max(Decimal, fn -> Decimal.new(0) end)

    if Decimal.compare(worst, 0) == :gt do
      drift_weight
      |> Decimal.abs()
      |> Decimal.div(worst)
      |> Decimal.mult(45)
      |> Decimal.round(1)
      |> Decimal.to_string(:normal)
    else
      "0"
    end
  end

  # Categories drifting beyond ±5 pp against the default steering tree's plan
  # for the default view (ADR-0020: SOLL plans are view-bound; `nil` view =
  # the Gesamt plan) — the same tree the Wealth page defaults to (first custom
  # classification, else asset class; review finding) — worst offenders first.
  # Only rows that carry a target count — an untargeted parent's "drift" is
  # not an alert. The cash row joins under the same rule when a cash target is
  # steered. The allocation read is still portfolio-bound, so portfolios are
  # iterated as the mechanism; the view is the user-facing scope.
  defp attention_report(view_id, context) do
    case Classifications.default_classification() do
      nil ->
        %{alerts: [], count: 0, basis: nil}

      classification ->
        alerts =
          Portfolios.list_portfolios()
          |> Enum.flat_map(&alerts_for(&1, classification, view_id, context))
          |> Enum.sort_by(&Decimal.abs(&1.drift_value), {:desc, Decimal})

        # The count is of every category off target, the list the worst
        # five (Sprint 31 closing act, DS1: at S the widget says the count).
        %{
          alerts: Enum.take(alerts, @max_alerts),
          count: length(alerts),
          basis: attention_basis(classification, view_id)
        }
    end
  end

  # The names the basis line states (#673): the view, the steering tree, and
  # the active plan(s) behind the drift figures. Portfolios are the iteration
  # mechanism (ADR-0024), so several portfolios may each carry an active plan
  # for the same (view, tree) — the line then says so instead of silently
  # naming one. Raw names only; localisation happens at render time.
  defp attention_basis(classification, view_id) do
    view = view_id && Buckets.get_view(view_id)

    plan_names =
      Portfolios.list_portfolios()
      |> Enum.flat_map(fn portfolio ->
        Targets.list_plans(portfolio.id,
          classification_id: classification.id,
          view: view && view.id
        )
      end)
      |> Enum.filter(&(&1.status == "active"))
      |> Enum.map(& &1.name)
      |> Enum.uniq()

    %{
      view_name: view && view.name,
      tree: %{key: classification.key, name: classification.name},
      plan_names: plan_names,
      # The card reads every portfolio, and says so where there are
      # several (MO4).
      several_portfolios: length(Portfolios.list_portfolios()) > 1
    }
  end

  defp basis_phrase(%{plan_names: []} = basis) do
    gettext("View %{view} — no active plan on %{tree}",
      view: basis_view(basis),
      tree: ClassificationName.display(basis.tree)
    )
  end

  defp basis_phrase(%{plan_names: [name]} = basis) do
    gettext("View %{view} · plan “%{plan}” on %{tree}",
      view: basis_view(basis),
      plan: name,
      tree: ClassificationName.display(basis.tree)
    )
  end

  defp basis_phrase(basis) do
    gettext("View %{view} · several active plans on %{tree}",
      view: basis_view(basis),
      tree: ClassificationName.display(basis.tree)
    )
  end

  defp basis_view(%{view_name: nil}), do: gettext("Everything")
  defp basis_view(%{view_name: name}), do: name

  defp alerts_for(portfolio, classification, view_id, context) do
    opts = [view: view_id, pricing_context: context]

    case Allocation.for_portfolio(portfolio.id, classification.id, opts) do
      {:ok, %{has_plan: true} = allocation} ->
        allocation
        |> AllocationDriftWidget.off_target()
        |> Enum.map(fn row ->
          # ADR-0024: the portfolio is the iteration mechanism only — its name
          # is not surfaced as a grouping label.
          %{
            name: if(row.name == :cash, do: gettext("Cash"), else: row.name),
            drift_weight: row.drift_weight,
            drift_value: row.drift_value,
            base_currency: allocation.base_currency
          }
        end)

      _ ->
        []
    end
  end

  # Decided on the drift as displayed, one-decimal percentage points
  # (#1149). The card lists only drifts beyond the threshold, so a drift
  # that reads zero never reaches it; the rule is kept for one reading.
  defp drift_sign_class(drift_weight) do
    if Format.displayed_percent_sign(drift_weight) == :negative, do: "is-negative", else: nil
  end

  # Readable item text (UAT fix round): "7.2 pp above target" instead of a
  # bare signed number — the direction word carries the meaning.
  defp drift_phrase(drift_weight) do
    pp = Format.percent(Decimal.abs(drift_weight))

    if Format.displayed_percent_sign(drift_weight) == :negative do
      gettext("%{pp} pp below target", pp: pp)
    else
      gettext("%{pp} pp above target", pp: pp)
    end
  end

  # The compact form's figure (board 06): the drift alone, signed, in
  # percentage points; the direction is the sign, the colour follows it.
  defp drift_points(drift_weight) do
    sign =
      case Format.displayed_percent_sign(drift_weight) do
        :negative -> "−"
        :positive -> "+"
        _zero -> ""
      end

    gettext("%{pp} pp", pp: sign <> Format.percent(Decimal.abs(drift_weight)))
  end

  # The ±5 pp threshold as a plain "5" for the explainer copy.
  # #828 (ADR-0048 §2, §5.2): due within the horizon across the WHOLE
  # CATALOG. Each row carries whether the security is held, so the card can
  # mark a candidate rather than hide it — the default is the requirement.
  @upcoming_days 30

  defp upcoming_days, do: @upcoming_days

  defp upcoming_events do
    events = Events.upcoming(days: @upcoming_days, limit: 8)
    securities = Map.new(Catalog.list_securities(), &{&1.id, &1})
    held = MapSet.new(Events.held_security_ids())

    for event <- events,
        security = Map.get(securities, event.security_id),
        not is_nil(security) do
      %{
        event: event,
        security_name: security.name,
        held: MapSet.member?(held, security.id)
      }
    end
  end

  defp threshold_pp, do: AllocationDriftWidget.threshold_pp()

  defp signed_percent(value), do: Format.signed_percent(value)

  # Gain/loss colour by sign, never the accent (UX-DR7, issue 637), decided
  # on the figure as displayed (#1149, board 04 found while drawing 3): a
  # percent at its one decimal, so "0,0%" is `is-flat`; money at two.
  defp sign_class(value), do: value |> Format.displayed_percent_sign() |> flat_sign_class()

  defp money_sign_class(value), do: value |> Format.displayed_sign(2) |> flat_sign_class()

  defp flat_sign_class(:positive), do: "is-positive"
  defp flat_sign_class(:negative), do: "is-negative"
  defp flat_sign_class(:zero), do: "is-flat"
  defp flat_sign_class(nil), do: nil

  # The data-quality line's findings, each with the pre-filtered securities
  # URL that fixes it (#561/#651). Only non-zero counts appear; when the list
  # is empty the whole section is absent — no all-clear badge (UX-DR2).
  #
  # Issue 1417 (board ux-design-2026-11-12-sprint29/04 ② A; the owner's
  # answer of 2026-11-07 to OQ-4, reversing J1.2 A of #1081): every set of
  # securities is counted over the held ones, its link opening the list
  # with the Held chip (`holding=held`), so a sold, unretired security no
  # longer keeps the line open. The catalogue count follows in parentheses
  # as its own link where it differs (`catalog/3`). A clause appears only
  # when its held count is above zero; the ledger's three checks count
  # bookings and are unchanged. The line's first finding carries its noun
  # ("4 held securities without an asset class"); a later one keeps its
  # short form after the first one's noun.
  #
  # #1068 (D-15, board 01 pin 5): the bonds priced on two scales, in either
  # direction, close the securities' part with their own noun; #1101 (D-7,
  # board 02 L2 A) the securities whose quotes contradict their bookings,
  # and #1415 those whose provider reports another currency, follow.
  defp dq_findings(nil), do: []

  defp dq_findings(dq) do
    [
      dq.without_quote > 0 && {:quotes, dq.without_quote},
      dq.without_class > 0 && {:class, dq.without_class},
      dq.without_logo > 0 && {:logo, dq.without_logo},
      dq.two_scales > 0 && {:two_scales, dq.two_scales},
      dq.implausible_quote > 0 && {:implausible_quote, dq.implausible_quote},
      dq.currency_mismatch > 0 && {:currency_mismatch, dq.currency_mismatch},
      dq.cash_mismatch > 0 && {:cash_mismatch, dq.cash_mismatch},
      dq.rate_only > 0 && {:rate_only, dq.rate_only},
      dq.incomplete_split > 0 && {:incomplete_split, dq.incomplete_split}
    ]
    |> Enum.filter(& &1)
    |> Enum.with_index()
    |> Enum.map(fn {{finding, count}, index} ->
      finding
      |> dq_finding(count, index == 0)
      |> catalog(count, dq.catalog[finding])
      |> Map.merge(%{short: dq_short(finding, count), finding: finding})
    end)
  end

  # Sprint 31 D4 (board ①: „2 Kurse älter als 5 Tage“, „1 Wertpapier ohne
  # Kategorie“): each finding at S as one short counted line, the count the
  # full sentence's, the link the same list.
  defp dq_short(:quotes, n),
    do: ngettext("%{count} quote older than 7 days", "%{count} quotes older than 7 days", n)

  defp dq_short(:class, n),
    do:
      ngettext(
        "%{count} security without an asset class",
        "%{count} securities without an asset class",
        n
      )

  defp dq_short(:logo, n),
    do: ngettext("%{count} security without a logo", "%{count} securities without a logo", n)

  defp dq_short(:two_scales, n),
    do: ngettext("%{count} bond on two price scales", "%{count} bonds on two price scales", n)

  defp dq_short(:implausible_quote, n),
    do:
      ngettext(
        "%{count} quote series against its bookings",
        "%{count} quote series against their bookings",
        n
      )

  defp dq_short(:currency_mismatch, n),
    do: ngettext("%{count} quote currency in doubt", "%{count} quote currencies in doubt", n)

  defp dq_short(:cash_mismatch, n),
    do:
      ngettext(
        "%{count} booking with mismatched cash",
        "%{count} bookings with mismatched cash",
        n
      )

  defp dq_short(:rate_only, n),
    do:
      ngettext(
        "%{count} booking with a rate and no cash",
        "%{count} bookings with a rate and no cash",
        n
      )

  defp dq_short(:incomplete_split, n),
    do: ngettext("%{count} incomplete split", "%{count} incomplete splits", n)

  # A short line's mark: the full line's severity for that finding alone.
  defp dq_severity_of(%{finding: :quotes}), do: :attention
  defp dq_severity_of(%{finding: finding}) when finding in [:class, :logo], do: :note
  defp dq_severity_of(_finding), do: :problem

  # The catalogue count beside a held one, only where the two differ (board
  # 04 ②: "(im Katalog 26)"); a ledger check has none.
  defp catalog(finding, held, %{count: count} = catalog) when count != held,
    do: Map.put(finding, :catalog, catalog)

  defp catalog(finding, _held, _catalog), do: finding

  # The quote finding always opens the line when present, so it always
  # carries its noun.
  defp dq_finding(:quotes, count, _first?) do
    %{
      role: "dq-quotes",
      href: "/securities?dq=stale_quote&holding=held",
      text:
        ngettext(
          "one held security without a quote in 7 days",
          "%{count} held securities without a quote in 7 days",
          count
        )
    }
  end

  defp dq_finding(:class, count, first?) do
    %{
      role: "dq-class",
      href: "/securities?" <> Query.encode(class_filter(%{"holding" => "held"})),
      text:
        if(first?,
          do:
            ngettext(
              "one held security without an asset class",
              "%{count} held securities without an asset class",
              count
            ),
          else: ngettext("one without an asset class", "%{count} without an asset class", count)
        )
    }
  end

  defp dq_finding(:logo, count, first?) do
    %{
      role: "dq-logo",
      href: "/securities?dq=missing_logo&holding=held",
      text:
        if(first?,
          do:
            ngettext(
              "one held security without a logo",
              "%{count} held securities without a logo",
              count
            ),
          else: ngettext("one without a logo", "%{count} without a logo", count)
        )
    }
  end

  # Issue 1417: the count is the held bonds', each one in the total above,
  # so the effect has no "if held" any more.
  defp dq_finding(:two_scales, count, _first?) do
    %{
      role: "dq-two-scales",
      href: "/securities?dq=two_scales&holding=held",
      text:
        ngettext(
          "one held bond priced on two scales",
          "%{count} held bonds priced on two scales",
          count
        ),
      effect:
        ngettext(
          "— it counts a hundredfold too high or too low in the total above",
          "— each counts a hundredfold too high or too low in the total above",
          count
        )
    }
  end

  defp dq_finding(:implausible_quote, count, _first?) do
    %{
      role: "dq-implausible-quote",
      href: "/securities?dq=implausible_quote&holding=held",
      text:
        ngettext(
          "one held security whose quotes do not match its bookings",
          "%{count} held securities whose quotes do not match their bookings",
          count
        ),
      effect:
        ngettext(
          "— so its value in the total above, or its cost, is wrong",
          "— so their value in the total above, or their cost, is wrong",
          count
        )
    }
  end

  # #1415 (Sprint 28 Q3; board ux-design-2026-11-08-sprint28/05 ②, plan
  # D-6): the securities whose provider stated another currency than their
  # own, right after the implausible series, always with their noun, and
  # what a series stored in the wrong currency does to the total above —
  # since issue 1417 without "if held", the count being the held ones'.
  defp dq_finding(:currency_mismatch, count, _first?) do
    %{
      role: "dq-currency-mismatch",
      href: "/securities?dq=currency_mismatch&holding=held",
      text:
        ngettext(
          "one held security whose provider reports another currency than its own",
          "%{count} held securities whose provider reports another currency than their own",
          count
        ),
      effect:
        ngettext(
          "— its quotes may be stored in the wrong currency, so its value in the total above is wrong",
          "— their quotes may be stored in the wrong currency, so their value in the total above is wrong",
          count
        )
    }
  end

  # Sprint 23 V1 (board ux-design-2026-11-02-sprint23/01 ①a, pick Q1 A):
  # the ledger's read-only checks, each the agent's read over the API and
  # one finding here. Its link opens the history filtered to exactly the
  # read's rows; its count is the read's row count (`LedgerChecks.count/1`).
  defp dq_finding(:cash_mismatch, count, _first?) do
    %{
      role: "dq-cash-mismatch",
      href: "/transactions?dq=cash_mismatch",
      text:
        ngettext(
          "one booking whose cash misses its quantity × price, fees and taxes",
          "%{count} bookings whose cash misses their quantity × price, fees and taxes",
          count
        ),
      effect: gettext("— so the cash balance and the cost read different amounts")
    }
  end

  defp dq_finding(:rate_only, count, _first?) do
    %{
      role: "dq-rate-only",
      href: "/transactions?dq=rate_only",
      text:
        ngettext(
          "one cross-currency buy or sell with a rate and no cash amount",
          "%{count} cross-currency buys or sells with a rate and no cash amount",
          count
        ),
      effect:
        ngettext(
          "— it books quantity × price to the account unconverted",
          "— they book quantity × price to the account unconverted",
          count
        )
    }
  end

  defp dq_finding(:incomplete_split, count, _first?) do
    %{
      role: "dq-incomplete-split",
      href: "/transactions?dq=incomplete_split",
      text:
        ngettext(
          "one split missing a portfolio that held the security",
          "%{count} splits each missing a portfolio that held the security",
          count
        ),
      effect: gettext("— there the lots are split and the holding is not")
    }
  end

  # Highest severity present (UX-DR17): a bond priced on two scales counts a
  # hundredfold too high or too low in the total, so it is a problem (#1068,
  # D-15), and so is a held security whose quotes contradict its own
  # bookings — two stored facts about one day, one of them wrong, and a
  # figure in the totals with it (#1101, D-7, pick L2 A); a stale quote
  # skews valuations, so it is attention-level; a missing class or logo is
  # a note-level catalog gap.
  #
  # A ledger check (Sprint 23 V1, pick Q2 problem) can make a figure wrong:
  # a cash balance and a cost that read two amounts.
  defp dq_severity(%{cash_mismatch: n}) when n > 0, do: :problem
  defp dq_severity(%{rate_only: n}) when n > 0, do: :problem
  defp dq_severity(%{incomplete_split: n}) when n > 0, do: :problem
  defp dq_severity(%{two_scales: n}) when n > 0, do: :problem
  defp dq_severity(%{implausible_quote: n}) when n > 0, do: :problem
  # #1415: a series stored in another currency is a value in the total that
  # is wrong, as an implausible one is.
  defp dq_severity(%{currency_mismatch: n}) when n > 0, do: :problem
  defp dq_severity(%{without_quote: n}) when n > 0, do: :attention
  defp dq_severity(_dq), do: :note

  # Securities needing attention (#337 data-quality card): no recent quote
  # (none at all, or older than 7 days), no persisted asset class, no logo,
  # since #1068 a bond priced on two scales, since #1101 a security whose
  # quotes contradict its own bookings, and since #1415 a security whose
  # provider stated another currency than its own — each counted over the
  # held securities since issue 1417, with the catalogue's count under
  # `catalog` for the sets whose held count is above zero.
  defp data_quality_report do
    # The counts come from the shared predicates (#705), so each finding's
    # number is produced by the same rule as the list its link opens, with
    # `holding_status: :held` as the list's Held chip applies it. The
    # asset-class finding stays an ordinary column filter: `asset_class` is a
    # stored column, so it needs no predicate of its own -- and it is keyed on
    # the STORED value per #700, which is what makes the count addressable.
    # A retired security leaves it as it leaves the predicates' sets (PR
    # #1102), and the link carries the same `is_retired:is_false` filter, so
    # the held count never exceeds the catalogue's.
    held = [holding_status: :held]

    sets = %{
      quotes: &DataQuality.count("stale_quote", &1),
      class: &without_class/1,
      logo: &DataQuality.count("missing_logo", &1),
      two_scales: &DataQuality.count("two_scales", &1),
      implausible_quote: &DataQuality.count("implausible_quote", &1),
      currency_mismatch: &DataQuality.count("currency_mismatch", &1)
    }

    counts = Map.new(sets, fn {set, count} -> {set, count.(held)} end)

    %{
      without_quote: counts.quotes,
      without_class: counts.class,
      without_logo: counts.logo,
      two_scales: counts.two_scales,
      implausible_quote: counts.implausible_quote,
      currency_mismatch: counts.currency_mismatch,
      # The catalogue is read only for a set the line shows.
      catalog:
        for {set, count} <- sets, counts[set] > 0, into: %{} do
          {set, %{count: count.([]), href: catalog_href(set)}}
        end,
      cash_mismatch: LedgerChecks.count("cash_mismatch"),
      rate_only: LedgerChecks.count("rate_only"),
      incomplete_split: LedgerChecks.count("incomplete_split")
    }
  end

  defp without_class(opts) do
    opts
    |> Keyword.put(:is_retired, false)
    |> Catalog.list_securities()
    |> Enum.count(&is_nil(&1.asset_class))
  end

  defp class_filter(extra \\ %{}),
    do: Map.merge(%{"filter" => ["asset_class:is_nil", "is_retired:is_false"]}, extra)

  # The catalogue list of each set: the held one's link without the chip.
  defp catalog_href(:quotes), do: "/securities?dq=stale_quote"
  defp catalog_href(:class), do: "/securities?" <> Query.encode(class_filter())
  defp catalog_href(:logo), do: "/securities?dq=missing_logo"
  defp catalog_href(:two_scales), do: "/securities?dq=two_scales"
  defp catalog_href(:implausible_quote), do: "/securities?dq=implausible_quote"
  defp catalog_href(:currency_mismatch), do: "/securities?dq=currency_mismatch"

  defp count_cards(assigns) do
    ~H"""
    <%!-- Each count card looks like a card and is the most clickable thing on
          the dashboard, so it links to where that data is created instead of
          being a dead <article>. --%>
    <section class="workspace-section grid" aria-label={gettext("Setup counts")}>
      <a href="/securities" id="dashboard-securities-count" class="stat stat--link">
        <span><%= gettext("Securities") %></span>
        <strong><%= @securities_count %></strong>
      </a>
      <a href="/portfolios" id="dashboard-cash-accounts-count" class="stat stat--link">
        <span><%= gettext("Cash accounts") %></span>
        <strong><%= @cash_accounts_count %></strong>
      </a>
      <a href="/portfolios" id="dashboard-securities-accounts-count" class="stat stat--link">
        <span><%= gettext("Depots") %></span>
        <strong><%= @securities_accounts_count %></strong>
      </a>
      <a href="/transactions" id="dashboard-transactions-count" class="stat stat--link">
        <span><%= gettext("Transactions") %></span>
        <strong><%= @transactions_count %></strong>
      </a>
    </section>
    """
  end

  defp assign_counts(socket) do
    assign(socket,
      securities_count: Catalog.count_securities(),
      cash_accounts_count: Portfolios.count_cash_accounts(),
      securities_accounts_count: Portfolios.count_securities_accounts(),
      transactions_count: Ledger.count_transactions(),
      error: nil
    )
  end
end
