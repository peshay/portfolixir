defmodule PortfolixirWeb.SecuritiesLive do
  use PortfolixirWeb, :live_view

  require Logger

  alias Plug.Conn.Query
  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.AssetClasses
  alias Portfolixir.Catalog.DataQuality
  alias Portfolixir.Catalog.Feeds
  alias Portfolixir.Catalog.LogoDiscovery
  alias Portfolixir.Catalog.LogoLookup
  alias Portfolixir.Catalog.LogoStore
  alias Portfolixir.Catalog.QuoteAdjustment
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Catalog.QuoteSync
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Catalog.SecurityFields
  alias Portfolixir.Catalog.SecurityFields.Field
  alias Portfolixir.Catalog.SecurityWithMetrics
  alias Portfolixir.Classifications
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Projection
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Valuation
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.ChangedSince
  alias PortfolixirWeb.ClassificationName
  alias PortfolixirWeb.Components.SecurityChart
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.Securities.ColumnPicker
  alias PortfolixirWeb.Securities.FilterPopover
  alias PortfolixirWeb.Securities.LogoOverrideDialog
  alias PortfolixirWeb.Securities.RowContextMenu
  alias PortfolixirWeb.Securities.SecurityFormDialog
  alias PortfolixirWeb.Securities.SplitWizardDialog

  @ranges ~w(1M 3M 6M YTD 1Y 3Y 5Y MAX)
  @default_range "1Y"

  @tabs ~w(overview chart transactions trades quotes holdings classifications)
  @default_tab "overview"
  @holding_statuses ~w(all held not_held)
  @default_holding_status "all"

  # Data-quality shortcut filters (#561): conditions that are not expressible
  # as a plain column filter — stale/missing quotes are metric-derived and the
  # logo lives in JSONB attributes. URL-addressable via `?dq=` so the Overview
  # data-quality line can deep-link to the offending set (#651, UX-DR2).
  # The predicates themselves live in `Catalog.DataQuality` since #705, so this
  # list, the dashboard's counts and the API/MCP predicate are one rule.
  @dq_filters DataQuality.ids()

  # URL filter operator whitelist (#651): query params never mint atoms.
  @filter_ops %{
    "eq" => :eq,
    "neq" => :neq,
    "contains" => :contains,
    "starts_with" => :starts_with,
    "gt" => :gt,
    "lt" => :lt,
    "is_true" => :is_true,
    "is_false" => :is_false,
    "is_nil" => :is_nil
  }

  @impl true
  def mount(_params, _session, socket) do
    # Background logo discovery stores logos asynchronously; subscribe so a
    # freshly resolved logo replaces the initials/flag placeholder live.
    if connected?(socket), do: LogoStore.subscribe()

    {:ok,
     socket
     |> assign(:query, "")
     |> assign(:holding_status, @default_holding_status)
     |> assign(:filters, [])
     |> assign(:dq, nil)
     |> assign(:logo_retry_queued?, false)
     |> assign(:sort, {:name, :asc})
     |> assign(:visible_columns, SecurityFields.visible_default())
     |> assign(:classification_columns, Classifications.column_specs())
     |> assign(:open_popover, nil)
     |> assign(:dialog_open?, false)
     |> assign(:split_dialog_open?, false)
     |> assign(:action_result, nil)
     |> assign(:sync_running?, false)
     |> assign(:selected_security, nil)
     |> assign(:detail_tab, @default_tab)
     |> assign(:detail_fullscreen?, false)
     |> assign(:detail_range, @default_range)
     |> assign(:detail_custom_range, nil)
     |> assign(:detail_range_error, nil)
     |> assign(:detail_percent_mode?, false)
     |> assign(:detail_log_scale?, false)
     |> assign(:detail_show_transactions?, true)
     |> assign(:detail_ma, %{30 => false, 50 => false, 200 => false})
     |> assign(:detail_cost_basis?, false)
     |> assign(:detail_quotes, [])
     |> assign(:detail_series_basis, :empty)
     |> assign(:detail_split_events, [])
     |> assign(:detail_transactions, [])
     |> assign(:detail_transaction_rows, [])
     |> assign(:detail_trades, %{open_lots: [], closed_trades: [], orphan_sells: []})
     |> assign(:detail_holdings, [])
     |> assign(:buckets, [])
     |> assign(:detail_latest, nil)
     |> assign(:detail_metrics, SecurityWithMetrics.empty_metrics())
     |> assign(:detail_classifications, [])
     |> assign(:detail_new_category_for, nil)
     |> assign(:row_menu_id, nil)
     |> assign(:editing_security, nil)
     |> assign(:delete_blocked, nil)
     |> assign(:logo_dialog_security, nil)
     |> assign(:securities, [])}
  end

  # The URL is the single source of truth for the list-filter state (#651):
  # `q`, `holding`, `filter[]` and `dq` are parsed here, so any link can open
  # the securities list pre-filtered. UI events patch the URL instead of
  # mutating assigns directly.
  @impl true
  def handle_params(params, _uri, socket) do
    tab = safe_tab(params["tab"])

    socket =
      socket
      |> assign(:query, safe_query(params["q"]))
      |> assign(
        :holding_status,
        safe_holding_status(params["holding"] || @default_holding_status)
      )
      |> assign(:filters, parse_url_filters(params["filter"]))
      |> assign(:dq, safe_dq(params["dq"]))
      |> assign(:cur, safe_currency_list(params["cur"]))
      |> assign(:class, safe_class_list(params["class"]))
      |> assign(:since, ChangedSince.parse(params))
      |> clear_action_result_on_navigation()
      |> reset_logo_retry()
      |> load_securities()

    case params["id"] do
      nil ->
        {:noreply, clear_selection(socket) |> assign(:detail_tab, tab)}

      id ->
        case Catalog.get_security(id) do
          %Security{} = security ->
            {:noreply, socket |> assign(:detail_tab, tab) |> select_security(security)}

          nil ->
            {:noreply, clear_selection(socket) |> assign(:detail_tab, tab)}
        end
    end
  end

  defp safe_tab(tab) when is_binary(tab) and tab in @tabs, do: tab
  defp safe_tab(_), do: @default_tab

  # #717 chip families: whitelisted so query params never mint atoms and
  # junk degrades to "no chip". Currencies are matched against the catalog's
  # own set at load time; here only the shape is enforced.
  defp safe_currency_list(nil), do: []

  defp safe_currency_list(values) do
    values
    |> List.wrap()
    |> Enum.filter(&(is_binary(&1) and Regex.match?(~r/^[A-Z]{3}$/, &1)))
    |> Enum.uniq()
  end

  defp safe_class_list(nil), do: []

  defp safe_class_list(values) do
    codes = AssetClasses.codes()

    values
    |> List.wrap()
    |> Enum.filter(&(is_binary(&1) and &1 in codes))
    |> Enum.uniq()
  end

  defp safe_dq(dq) when dq in @dq_filters, do: dq
  defp safe_dq(_), do: nil

  # The inline bulk-retry result persists until the filter context changes
  # (a navigation away from the missing-logo list), never on a timer.
  defp reset_logo_retry(%{assigns: %{dq: "missing_logo"}} = socket), do: socket
  defp reset_logo_retry(socket), do: assign(socket, :logo_retry_queued?, false)

  # An inline action result persists until the next action, an explicit
  # dismiss, or a navigation (#566) — this is the navigation case. A busy
  # state survives the patch: the action is still running and its result
  # message will replace it.
  defp clear_action_result_on_navigation(socket) do
    case socket.assigns[:action_result] do
      {:busy, _message} -> socket
      nil -> socket
      _result -> assign(socket, :action_result, nil)
    end
  end

  # -- URL filter state (#651) ----------------------------------------------

  # `filter[]=key:op[:value]` — key and operator are validated against the
  # SecurityFields registry; anything unknown is dropped silently, matching
  # the context's own tolerant filter handling.
  defp parse_url_filters(nil), do: []
  defp parse_url_filters(param) when is_binary(param), do: parse_url_filter(param)

  defp parse_url_filters(params) when is_list(params),
    do: Enum.flat_map(params, &parse_url_filters/1)

  defp parse_url_filters(_), do: []

  defp parse_url_filter(param) when is_binary(param) do
    case String.split(param, ":", parts: 3) do
      [key_str, op_str] -> build_url_filter(key_str, op_str, nil)
      [key_str, op_str, value] -> build_url_filter(key_str, op_str, value)
      _ -> []
    end
  end

  defp build_url_filter(key_str, op_str, value) do
    with key when not is_nil(key) <- safe_column_atom(key_str),
         op when not is_nil(op) <- Map.get(@filter_ops, op_str) do
      value = if op in [:is_true, :is_false, :is_nil], do: op == :is_true, else: value

      if not is_nil(value) and SecurityFields.valid_filter?(key, op, value) do
        [%{key: key, op: op, value: value}]
      else
        []
      end
    else
      _ -> []
    end
  end

  defp filter_param(%{key: key, op: op}) when op in [:is_true, :is_false, :is_nil],
    do: "#{key}:#{op}"

  defp filter_param(%{key: key, op: op, value: value}), do: "#{key}:#{op}:#{value}"

  defp list_state(assigns) do
    %{
      query: assigns.query,
      holding_status: assigns.holding_status,
      filters: assigns.filters,
      dq: assigns.dq,
      cur: assigns.cur,
      class: assigns.class,
      since: assigns.since && assigns.since.raw
    }
  end

  # Builds a /securities path carrying the current (or overridden) filter
  # state, so filters survive selection, tab switches and patches (#651).
  #
  # Options:
  #   * `:id` — security id for the detail route; defaults to the current
  #     selection; pass `nil` explicitly to target the list.
  #   * `:tab` — detail tab; `:current` keeps the active one.
  #   * `:override` — map merged over the current list-filter state.
  defp securities_path(assigns, opts) do
    id =
      case Keyword.fetch(opts, :id) do
        {:ok, value} -> value
        :error -> assigns.selected_security && assigns.selected_security.id
      end

    base = if id, do: "/securities/#{id}", else: "/securities"

    tab =
      case Keyword.get(opts, :tab) do
        :current -> id && assigns.detail_tab != @default_tab && assigns.detail_tab
        tab -> tab
      end

    state = Map.merge(list_state(assigns), Keyword.get(opts, :override, %{}))

    params =
      %{}
      |> maybe_put_param("tab", tab)
      |> maybe_put_param("q", String.trim(state.query) != "" && state.query)
      |> maybe_put_param(
        "holding",
        state.holding_status != @default_holding_status && state.holding_status
      )
      |> maybe_put_param("dq", state.dq)
      |> maybe_put_param("cur", state.cur != [] && state.cur)
      |> maybe_put_param("class", state.class != [] && state.class)
      |> maybe_put_param("since", state.since)
      |> maybe_put_param(
        "filter",
        state.filters != [] && Enum.map(state.filters, &filter_param/1)
      )

    if params == %{} do
      base
    else
      base <> "?" <> Query.encode(params)
    end
  end

  defp maybe_put_param(params, _key, value) when value in [nil, false], do: params
  defp maybe_put_param(params, key, value), do: Map.put(params, key, value)

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell
      current_path="/securities"
      page_title={gettext("Securities")}
      page_subtitle={gettext("Search, filter and curate the investable universe.")}
      main_class="app-main--workspace"
    >
      <section class="workspace-panel" id="securities-panel">
        <div class="toolbar" role="toolbar" aria-label={gettext("Securities toolbar")}>
          <form class="search-field" phx-change="search" phx-submit="search" id="securities-search-form">
            <AppShell.icon name={:search} />
            <input
              type="search"
              name="query"
              value={@query}
              phx-debounce="200"
              placeholder={gettext("Search by name, ISIN, WKN or ticker…")}
              autocomplete="off"
              aria-label={gettext("Search securities")}
            />
          </form>

          <div class="toolbar-actions">
            <button
              type="button"
              id="open-new-dialog"
              class="icon-button"
              phx-click="open_new"
              aria-label={gettext("Add new")}
              title={gettext("Add new")}
            >
              <AppShell.icon name={:plus} />
            </button>

            <button
              type="button"
              id="sync-prices"
              class={["icon-button", @sync_running? && "is-busy"]}
              phx-click="sync_now"
              onclick="Portfolixir.ensureNotifyPermission()"
              aria-label={gettext("Sync prices")}
              title={gettext("Sync prices")}
              disabled={@sync_running?}
            >
              <AppShell.icon name={:refresh_cw} />
            </button>

            <button
              type="button"
              id="toggle-column-popover"
              class={["icon-button", @open_popover == :columns && "is-active"]}
              phx-click="toggle_popover"
              phx-value-popover="columns"
              aria-label={gettext("Columns")}
              aria-expanded={@open_popover == :columns}
              title={gettext("Columns")}
            >
              <AppShell.icon name={:columns} />
            </button>

            <div class="popover-container">
              <%= if @open_popover == :columns do %>
                <.live_component
                  module={ColumnPicker}
                  id="column-picker"
                  visible={@visible_columns}
                  classification_columns={@classification_columns}
                />
              <% end %>
            </div>
          </div>
        </div>

        <%!-- #717 (D2): the common filters as one-tap toggle chips; the
             builder is demoted behind "More filters" at the end of the row.
             Families compose AND; chips within the currency and class
             families compose OR (the family label marks the either/or
             groups). Every chip state rides the URL. --%>
        <div
          id="securities-filter-chips"
          class="filter-chips"
          role="group"
          aria-label={gettext("Filter the list")}
        >
          <button
            type="button"
            id="sec-chip-held"
            class={["filter-chip", @holding_status == "held" && "is-active"]}
            aria-pressed={to_string(@holding_status == "held")}
            phx-click="set_holding_status"
            phx-value-status={if @holding_status == "held", do: "all", else: "held"}
          >
            <%= gettext("Held") %>
          </button>
          <button
            type="button"
            id="sec-chip-not_held"
            class={["filter-chip", @holding_status == "not_held" && "is-active"]}
            aria-pressed={to_string(@holding_status == "not_held")}
            phx-click="set_holding_status"
            phx-value-status={if @holding_status == "not_held", do: "all", else: "not_held"}
          >
            <%= gettext("Not held") %>
          </button>
          <%!-- Keyed on the STORED class (#700): the one-tap form of the
               canonical filter[]=asset_class:is_nil URL. --%>
          <button
            type="button"
            id="sec-chip-unclassified"
            class={["filter-chip", unclassified_active?(@filters) && "is-active"]}
            aria-pressed={to_string(unclassified_active?(@filters))}
            phx-click="toggle_unclassified"
          >
            <%= gettext("Unclassified") %>
          </button>
          <%= for {id, label} <- dq_chip_options() do %>
            <button
              type="button"
              id={"sec-chip-#{id}"}
              class={["filter-chip", @dq == id && "is-active"]}
              aria-pressed={to_string(@dq == id)}
              phx-click="set_dq_chip"
              phx-value-dq={id}
            >
              <%= label %>
            </button>
          <% end %>
          <%= if length(@chip_currencies) > 1 do %>
            <span class="filter-chips__family"><%= gettext("Currency") %></span>
            <%= for currency <- @chip_currencies do %>
              <button
                type="button"
                id={"sec-chip-cur-#{currency}"}
                class={["filter-chip", currency in @cur && "is-active"]}
                aria-pressed={to_string(currency in @cur)}
                phx-click="toggle_chip_family"
                phx-value-family="cur"
                phx-value-option={currency}
              >
                <%= currency %>
              </button>
            <% end %>
          <% end %>
          <%= if @chip_classes != [] do %>
            <span class="filter-chips__family"><%= gettext("Asset class") %></span>
            <%= for code <- @chip_classes do %>
              <button
                type="button"
                id={"sec-chip-class-#{code}"}
                class={["filter-chip", code in @class && "is-active"]}
                aria-pressed={to_string(code in @class)}
                phx-click="toggle_chip_family"
                phx-value-family="class"
                phx-value-option={code}
              >
                <%= AssetClasses.label(code) %>
              </button>
            <% end %>
          <% end %>
          <%!-- The demoted builder (D2): a quiet control, not a tenth chip;
               the count keeps demotion from hiding active state. --%>
          <button
            type="button"
            id="more-filters-toggle"
            class={["more-filters-link", @open_popover == :filter && "is-active"]}
            phx-click="toggle_popover"
            phx-value-popover="filter"
            aria-expanded={@open_popover == :filter}
          >
            <AppShell.icon name={:filter} />
            <%= gettext("More filters") %>
            <span
              :if={more_filters_count(@filters, @dq) > 0}
              class="badge"
              data-role="more-filters-count"
            >
              <%= more_filters_count(@filters, @dq) %>
            </span>
          </button>
        </div>

        <div class="popover-container">
          <%= if @open_popover == :filter do %>
            <.live_component
              module={FilterPopover}
              id="filter-popover"
              dq={@dq}
            />
          <% end %>
        </div>

        <ChangedSince.chips id="changed-since-chips" since={@since} />

        <p
          :if={@since}
          id="securities-since-note"
          class="summary-basis"
          role="status"
          data-role="since-note"
        >
          <%= gettext(
            "Changed since %{cut} (UTC): only securities created or changed after this instant are listed. Deletions are not shown; clear the filter for the complete list.",
            cut: @since.raw
          ) %>
        </p>

        <%!-- #717: only the conditions with no one-tap chip render as
             removable chips — a condition a chip expresses (unclassified,
             the dq trio) shows its state on that chip instead of twice.
             `missing_logo` has no one-tap chip, so its dq state keeps the
             removable form. The index into @filters is kept from before the
             exclusion so removal stays exact. --%>
        <%= if builder_filter_count(@filters) > 0 or removable_dq?(@dq) do %>
          <ul class="filter-chips" id="filter-chips" aria-label={gettext("Active filters")}>
            <%= if removable_dq?(@dq) do %>
              <li class="chip">
                <span><%= dq_label(@dq) %></span>
                <button
                  type="button"
                  class="chip-remove"
                  phx-click="remove_dq"
                  aria-label={gettext("Remove filter")}
                >
                  <AppShell.icon name={:x} size={12} />
                </button>
              </li>
            <% end %>
            <%= for {filter, idx} <- Enum.with_index(@filters), not chip_expressible?(filter) do %>
              <li class="chip">
                <span><%= chip_label(filter) %></span>
                <button
                  type="button"
                  class="chip-remove"
                  phx-click="remove_filter"
                  phx-value-idx={idx}
                  aria-label={gettext("Remove filter")}
                >
                  <AppShell.icon name={:x} size={12} />
                </button>
              </li>
            <% end %>
          </ul>
        <% end %>

        <%!-- Bulk logo retry (#561): only on the missing-logo filtered list,
             with its result inline beside the trigger — the status region
             exists before the action so the announcement is not lost. --%>
        <%= if @dq == "missing_logo" do %>
          <div class="dq-bulk-action">
            <button
              type="button"
              id="retry-missing-logos"
              phx-click="retry_missing_logos"
              disabled={@logo_retry_queued?}
            >
              <%= gettext("Retry logo lookup for all") %>
            </button>
          </div>
        <% end %>

        <%!-- Inline busy/result slot (#566): action feedback lands in flow,
             beside the toolbar and list the actions belong to; the regions
             exist before any action runs. --%>
        <AppShell.inline_result id="securities-action-result" result={@action_result} />

        <div
          id="securities-workspace"
          class={[
            "securities-workspace",
            @selected_security && "securities-workspace--split",
            !@selected_security && "securities-workspace--list-only"
          ]}
        >
          <div id="securities-list-pane" class="securities-list-pane">
            <div
              class="data-table-wrapper"
              id="securities-table"
              phx-hook="ColumnPrefs"
              data-storage-key="securities.columns"
              data-default-columns={Jason.encode!(SecurityFields.visible_default() |> Enum.map(&Atom.to_string/1))}
              data-current-columns={Jason.encode!(Enum.map(@visible_columns, &column_key_string/1))}
            >
              <table class="data-table">
                <thead>
                  <tr>
                    <th class="row-actions-head" aria-label={gettext("Row actions")}></th>
                    <%= for column <- visible_fields(@visible_columns, @classification_columns) do %>
                      <th>
                        <%= if column.sortable? do %>
                          <button
                            type="button"
                            class="sort-toggle"
                            phx-click="toggle_sort"
                            phx-value-key={column_key_string(column.key)}
                          >
                            <%= column.label %><%= sort_marker(@sort, column.key) %>
                          </button>
                        <% else %>
                          <span><%= column.label %></span>
                        <% end %>
                      </th>
                    <% end %>
                  </tr>
                </thead>
                <tbody>
                  <%= if @securities == [] do %>
                    <%!-- UX-DR13 (issue 649): a filtered zero-match keeps the
                         controls and names the filter — telling the operator
                         their list is empty when a filter is merely narrow
                         would be a factual error about their data. The
                         holding-status segmented control is a filter too. --%>
                    <tr>
                      <%= if String.trim(@query) != "" or @filters != [] or
                            @holding_status != "all" or @dq do %>
                        <td
                          colspan={length(visible_fields(@visible_columns, @classification_columns)) + 1}
                          class="empty-state"
                          data-role="no-results"
                        >
                          <%= if String.trim(@query) != "" do %>
                            <%= gettext("No matches for \"%{query}\".", query: @query) %>
                          <% else %>
                            <%= gettext("No matches for the active filters.") %>
                          <% end %>
                        </td>
                      <% else %>
                        <td
                          colspan={length(visible_fields(@visible_columns, @classification_columns)) + 1}
                          class="empty-state"
                          data-role="empty-surface"
                        >
                          <%= gettext("No securities yet — click + to add one.") %>
                        </td>
                      <% end %>
                    </tr>
                  <% end %>
                  <% visible = visible_fields(@visible_columns, @classification_columns) %>
                  <% first_key = first_visible_key(visible) %>
                  <%= for row <- @securities do %>
                    <% sec_id = security_id(row) %>
                    <% inner_security = security_from_row(row) %>
                    <% row_path = securities_path(assigns, id: sec_id) %>
                    <tr
                      id={"security-row-#{sec_id}"}
                      class={[
                        "security-row",
                        selected?(@selected_security, row) && "is-selected",
                        inner_security.is_retired && "is-retired"
                      ]}
                      phx-click={Phoenix.LiveView.JS.patch(row_path)}
                      phx-contextmenu="open_row_menu"
                      phx-value-id={sec_id}
                      role="link"
                    >
                      <td class="row-actions">
                        <button
                          type="button"
                          id={"row-kebab-#{sec_id}"}
                          class="row-actions__kebab"
                          phx-click="open_row_menu"
                          phx-value-id={sec_id}
                          aria-label={gettext("Open actions menu")}
                          aria-haspopup="menu"
                          aria-expanded={@row_menu_id == sec_id}
                        >
                          <AppShell.icon name={:ellipsis_vertical} />
                        </button>
                      </td>
                      <%= for column <- visible do %>
                        <td>
                          <%= if column.key == first_key do %>
                            <.link patch={row_path} class="row-target row-target--with-logo" tabindex="0">
                              <.security_logo security={inner_security} variant="row" />
                              <span class="row-target__label"><%= render_cell(column, row) %></span>
                            </.link>
                          <% else %>
                            <%= render_cell(column, row) %>
                          <% end %>
                        </td>
                      <% end %>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>

          <%= if @selected_security do %>
            <div
              id="securities-detail-splitter"
              class="securities-detail-splitter"
              role="separator"
              aria-orientation="horizontal"
              aria-controls="securities-list-pane"
              aria-valuemin="220"
              aria-valuemax="720"
              aria-valuenow="360"
              tabindex="0"
              phx-hook="SecuritySplitPane"
              data-storage-key="securities.detailSplitHeight"
              data-target="securities-list-pane"
              data-min-height="220"
              data-max-height="720"
              title={gettext("Resize detail split")}
            >
              <span aria-hidden="true"></span>
            </div>
            <%= render_detail_pane(assigns) %>
          <% end %>
        </div>
      </section>

      <% open_menu_security = @row_menu_id && find_open_menu_security(@securities, @row_menu_id) %>
      <%= if open_menu_security do %>
        <RowContextMenu.menu security={open_menu_security} />
      <% end %>

      <%= if @dialog_open? do %>
        <.live_component
          module={SecurityFormDialog}
          id="security-form-dialog"
          editing={@editing_security}
        />
      <% end %>

      <%= if @split_dialog_open? and @selected_security do %>
        <.live_component
          module={SplitWizardDialog}
          id="split-wizard-dialog"
          security={@selected_security}
        />
      <% end %>

      <%= if @delete_blocked do %>
        <RowContextMenu.delete_blocked_dialog security={@delete_blocked} />
      <% end %>

      <%= if @logo_dialog_security do %>
        <LogoOverrideDialog.dialog security={@logo_dialog_security} />
      <% end %>
    </AppShell.shell>
    """
  end

  defp find_open_menu_security(securities, menu_id) do
    securities
    |> Enum.find(&(security_id(&1) == menu_id))
    |> case do
      nil -> nil
      row -> security_from_row(row)
    end
  end

  defp render_detail_pane(assigns) do
    ~H"""
    <%!-- No modality attribute here (issue 646): the pane is not a dialog,
         and asserting modality without containment splits screen-reader
         position from keyboard focus. --%>
    <aside
      class={["detail-pane", @detail_fullscreen? && "detail-pane--fullscreen"]}
      id="security-detail-pane"
      aria-label={gettext("Selected security")}
    >
      <header class="detail-pane-head">
        <div class="detail-pane-head__title">
          <.security_logo security={@selected_security} variant="lg" />
          <div>
          <h2><%= @selected_security.name %></h2>
          <p class="detail-pane-sub">
            <%= [@selected_security.isin, @selected_security.ticker_symbol, @selected_security.currency_code]
              |> Enum.reject(&(&1 in [nil, ""]))
              |> Enum.join(" · ") %>
            <%= if @detail_latest do %>
              · <%= gettext("Latest") %> <%= Format.decimal(@detail_latest.close, 2) %>
              (<%= Date.to_iso8601(@detail_latest.date) %>)
            <% end %>
          </p>
          <.detail_valuation_status
            status={@detail_status}
            held?={@detail_holdings != []}
          />
          </div>
        </div>
        <div class="detail-pane-head__actions">
          <button
            type="button"
            id="detail-record-split"
            class="button-ghost"
            phx-click="open_split_wizard"
            title={gettext("Record a stock split for this security")}
          >
            <%= gettext("Record split") %>
          </button>
          <button
            type="button"
            id="detail-pane-fullscreen-toggle"
            class="icon-button"
            phx-click="toggle_detail_fullscreen"
            aria-label={
              if @detail_fullscreen?,
                do: gettext("Exit fullscreen"),
                else: gettext("Maximize")
            }
            title={
              if @detail_fullscreen?,
                do: gettext("Exit fullscreen"),
                else: gettext("Maximize")
            }
          >
            <AppShell.icon name={if @detail_fullscreen?, do: :minimize, else: :maximize} />
          </button>
          <.link
            id="detail-pane-close"
            patch={securities_path(assigns, id: nil)}
            class="icon-button"
            aria-label={gettext("Close detail")}
            title={gettext("Close detail")}
          >
            <AppShell.icon name={:x} />
          </.link>
        </div>
      </header>

      <nav
        id="detail-pane-tabs"
        class="detail-pane-tabs"
        role="tablist"
        data-tab-level="2"
        aria-label={gettext("Security detail tabs")}
      >
        <%= for {tab, label} <- detail_tabs() do %>
          <button
            type="button"
            id={"detail-tab-#{tab}"}
            role="tab"
            phx-click="select_detail_tab"
            phx-value-tab={tab}
            aria-selected={if @detail_tab == tab, do: "true", else: "false"}
            aria-controls={"detail-tab-panel-#{tab}"}
            class={["detail-pane-tab", @detail_tab == tab && "is-active"]}
          >
            <%= label %>
          </button>
        <% end %>
      </nav>

      <%= if @detail_tab == "chart" do %>
        <section
          id="detail-tab-panel-chart"
          role="tabpanel"
          aria-labelledby="detail-tab-chart"
          class="detail-tab-panel detail-tab-panel--chart"
        >
          <div class="detail-pane-toolbar" role="toolbar" aria-label={gettext("Chart options")}>
            <div class="range-buttons" role="group" aria-label={gettext("Range")}>
              <%= for range <- ranges() do %>
                <button
                  type="button"
                  phx-click="set_detail_range"
                  phx-value-range={range}
                  class={[
                    "range-button",
                    is_nil(@detail_custom_range) and @detail_range == range && "is-active"
                  ]}
                >
                  <%= range %>
                </button>
              <% end %>
              <%!-- #721 (D5): an applied custom range shows itself in the
                   range group, in the same active treatment as a preset. --%>
              <button
                :if={@detail_custom_range}
                type="button"
                class="range-button is-active"
                data-role="custom-range-chip"
                aria-pressed="true"
              >
                <%= Date.to_iso8601(@detail_custom_range.from) %> – <%= Date.to_iso8601(
                  @detail_custom_range.to
                ) %>
              </button>
            </div>

            <%!-- #721 (D5): a labelled pair that validates as a range —
                 the violation lands on the field that can fix it, never on a
                 silently unchanged chart. --%>
            <form
              id="detail-custom-range"
              phx-submit="set_detail_custom_range"
              class="detail-custom-range"
              data-active={if @detail_custom_range, do: "true", else: "false"}
              aria-label={gettext("Custom range")}
            >
              <label for="detail-range-from"><%= gettext("From") %></label>
              <input
                type="text"
                placeholder="YYYY-MM-DD"
                pattern="[0-9]{4}-[0-9]{2}-[0-9]{2}"
                maxlength="10"
                id="detail-range-from"
                name="from"
                value={@detail_custom_range && Date.to_iso8601(@detail_custom_range.from)}
                aria-invalid={@detail_range_error == :from && "true"}
                aria-describedby={@detail_range_error == :from && "detail-range-error"}
              />
              <label for="detail-range-to"><%= gettext("To") %></label>
              <input
                type="text"
                placeholder="YYYY-MM-DD"
                pattern="[0-9]{4}-[0-9]{2}-[0-9]{2}"
                maxlength="10"
                id="detail-range-to"
                name="to"
                value={@detail_custom_range && Date.to_iso8601(@detail_custom_range.to)}
                aria-invalid={@detail_range_error in [:to, :order] && "true"}
                aria-describedby={@detail_range_error in [:to, :order] && "detail-range-error"}
              />
              <button type="submit" class="chart-toggle">
                <%= gettext("Apply") %>
              </button>
              <p
                :if={@detail_range_error}
                id="detail-range-error"
                class="hint"
                data-role="detail-range-error"
                role="alert"
              >
                <%= detail_range_error_message(@detail_range_error) %>
              </p>
            </form>

            <div class="chart-toggles">
              <button
                type="button"
                id="toggle-log"
                phx-click="toggle_detail_log"
                class={["chart-toggle", @detail_log_scale? && "is-active"]}
                aria-pressed={@detail_log_scale?}
                disabled={@detail_percent_mode?}
              >
                <%= gettext("Log scale") %>
              </button>
              <button
                type="button"
                id="toggle-percent-mode"
                phx-click="toggle_detail_percent_mode"
                class={["chart-toggle", @detail_percent_mode? && "is-active"]}
                aria-pressed={@detail_percent_mode?}
              >
                <%= gettext("Percent") %>
              </button>
              <button
                type="button"
                id="toggle-transactions"
                phx-click="toggle_detail_transactions"
                class={["chart-toggle", @detail_show_transactions? && "is-active"]}
                aria-pressed={@detail_show_transactions?}
              >
                <%= gettext("Show transactions") %>
              </button>
              <%= for window <- [30, 50, 200] do %>
                <button
                  type="button"
                  id={"toggle-ma-#{window}"}
                  phx-click="toggle_detail_ma"
                  phx-value-window={window}
                  class={["chart-toggle", @detail_ma[window] && "is-active"]}
                  aria-pressed={@detail_ma[window]}
                >
                  MA<%= window %>
                </button>
              <% end %>
              <button
                type="button"
                id="toggle-cost-basis"
                phx-click="toggle_detail_cost_basis"
                class={["chart-toggle", @detail_cost_basis? && "is-active"]}
                aria-pressed={@detail_cost_basis?}
              >
                <%= gettext("Cost basis") %>
              </button>
              <button
                type="button"
                id="detail-sync"
                phx-click="sync_now"
                onclick="Portfolixir.ensureNotifyPermission()"
                class={["chart-toggle", @sync_running? && "is-busy"]}
                disabled={@sync_running?}
              >
                <%= gettext("Sync prices") %>
              </button>
              <button
                type="button"
                id="chart-export-svg"
                class="chart-toggle"
                onclick="Portfolixir.exportChart(this, 'svg')"
              >
                <%= gettext("Export SVG") %>
              </button>
              <button
                type="button"
                id="chart-export-png"
                class="chart-toggle"
                onclick="Portfolixir.exportChart(this, 'png')"
              >
                <%= gettext("Export PNG") %>
              </button>
            </div>
          </div>

          <SecurityChart.chart
            quotes={@detail_quotes}
            transactions={@detail_transactions}
            overlays={
              build_chart_overlays(
                @detail_quotes,
                @detail_transaction_rows,
                @detail_ma,
                @detail_cost_basis?,
                @detail_split_events,
                @selected_security.currency_code
              )
            }
            log_scale?={@detail_log_scale? and not @detail_percent_mode?}
            percent_mode?={@detail_percent_mode?}
            show_transactions?={@detail_show_transactions?}
            currency_code={@selected_security.currency_code}
          />
          <p
            :if={series_basis_label(@detail_series_basis, @detail_split_events)}
            class="detail-tab-hint"
            data-role="chart-basis"
          >
            <%= gettext("Price basis: %{basis}. Stored quotes are never modified (see the Quotes tab).",
              basis: series_basis_label(@detail_series_basis, @detail_split_events)
            ) %>
          </p>
        </section>
      <% end %>

      <%= if @detail_tab == "overview" do %>
        <.overview_tab_panel
          security={@selected_security}
          latest={@detail_latest}
          metrics={@detail_metrics}
        />
      <% end %>

      <%= if @detail_tab == "transactions" do %>
        <.transactions_tab_panel transactions={@detail_transaction_rows} />
      <% end %>

      <%= if @detail_tab == "trades" do %>
        <.trades_tab_panel
          trades={@detail_trades}
          currency_code={@selected_security.currency_code}
        />
      <% end %>

      <%= if @detail_tab == "quotes" do %>
        <.quotes_tab_panel
          quotes={@detail_quotes}
          currency_code={@selected_security.currency_code}
          range={@detail_range}
          series_basis={@detail_series_basis}
          split_events={@detail_split_events}
        />
      <% end %>

      <%= if @detail_tab == "holdings" do %>
        <.holdings_tab_panel
          holdings={@detail_holdings}
          currency_code={@selected_security.currency_code}
          buckets={@buckets}
        />
      <% end %>

      <%= if @detail_tab == "classifications" do %>
        <.classifications_tab_panel
          security={@selected_security}
          classifications={@detail_classifications}
          new_category_for={@detail_new_category_for}
        />
      <% end %>

      <%= if @detail_tab not in ~w(overview chart transactions trades quotes holdings classifications) do %>
        <section
          id={"detail-tab-panel-#{@detail_tab}"}
          role="tabpanel"
          class="detail-tab-panel detail-tab-panel--placeholder"
        >
          <p class="detail-tab-empty">
            <%= gettext("This view is not implemented yet.") %>
          </p>
        </section>
      <% end %>
    </aside>
    """
  end

  # The "counted in totals?" status line (#406): rendered from the valuation's
  # own price-resolution result, so this pane and the portfolio data-quality
  # warning always tell the same story. Nothing renders for a security that
  # is not held (nothing could be counted) or valued from a current quote.
  attr(:status, :map, default: nil)
  attr(:held?, :boolean, required: true)

  defp detail_valuation_status(%{held?: false} = assigns), do: ~H""
  defp detail_valuation_status(%{status: nil} = assigns), do: ~H""

  defp detail_valuation_status(%{status: %{unvalued_reason: :no_price}} = assigns) do
    ~H"""
    <p class="detail-pane-status badge-warning" data-role="detail-valuation-status">
      <%= gettext(
        "Not counted in the portfolio totals — no price is known for this security (no quote and no own trade)."
      ) %>
    </p>
    """
  end

  defp detail_valuation_status(%{status: %{unvalued_reason: :missing_fx}} = assigns) do
    ~H"""
    <p class="detail-pane-status badge-warning" data-role="detail-valuation-status">
      <%= gettext(
        "Not counted in the portfolio totals — latest price %{price} %{currency} is known, but no exchange rate to %{bases} is stored. Sync exchange rates to include it.",
        price: Format.decimal(@status.latest_price, 2),
        currency: @status.price_currency,
        bases: Enum.join(@status.missing_rate_currencies, ", ")
      ) %>
    </p>
    """
  end

  defp detail_valuation_status(%{status: %{price_source: :trade}} = assigns) do
    ~H"""
    <p class="detail-pane-status" data-role="detail-valuation-status">
      <%= gettext(
        "No current quote — counted in the portfolio totals at the last own trade price of %{price} %{currency}%{date}.",
        price: Format.decimal(@status.latest_price, 2),
        currency: @status.price_currency,
        date: if(@status.price_date, do: " (#{Date.to_iso8601(@status.price_date)})", else: "")
      ) %>
    </p>
    """
  end

  defp detail_valuation_status(assigns), do: ~H""

  attr(:security, :map, required: true)
  attr(:latest, :map, default: nil)
  attr(:metrics, :map, required: true)

  defp overview_tab_panel(assigns) do
    ~H"""
    <section
      id="detail-tab-panel-overview"
      role="tabpanel"
      class="detail-tab-panel detail-tab-panel--overview"
    >
      <form id="overview-details-form" phx-submit="save_security_details" class="overview-form">
        <div class="overview-grid">
          <label class="overview-edit-field">
            <span><%= gettext("Name") %></span>
            <input name="security[name]" value={@security.name} required />
          </label>
          <label class="overview-edit-field">
            <span><%= gettext("ISIN") %></span>
            <input name="security[isin]" value={@security.isin} class="mono" />
          </label>
          <label class="overview-edit-field">
            <span><%= gettext("WKN") %></span>
            <input name="security[wkn]" value={@security.wkn} class="mono" />
          </label>
          <label class="overview-edit-field">
            <span><%= gettext("Ticker") %></span>
            <input name="security[ticker_symbol]" value={@security.ticker_symbol} class="mono" />
          </label>
          <label class="overview-edit-field">
            <span><%= gettext("Exchange") %></span>
            <input name="security[exchange_code]" value={@security.exchange_code} class="mono" />
          </label>
          <label class="overview-edit-field">
            <span><%= gettext("Currency") %></span>
            <input name="security[currency_code]" value={@security.currency_code} maxlength="3" class="mono" />
          </label>
          <label class="overview-edit-field">
            <span><%= gettext("Asset class") %></span>
            <select name="security[asset_class]">
              <option value=""><%= gettext("Automatic") %></option>
              <%= for {label, code} <- AssetClasses.options() do %>
                <option value={code} selected={@security.asset_class == code}><%= label %></option>
              <% end %>
            </select>
          </label>
          <label class="overview-edit-field">
            <span><%= gettext("Treat synced quotes as raw") %></span>
            <%!-- ADR-0028 §2 escape hatch for providers that never back-adjust
                  after a split: forces the raw basis (split factors apply) for
                  this security's synced rows. Hidden false + checkbox true is
                  the standard unchecked-submits-false pattern. --%>
            <input type="hidden" name="security[treat_quotes_as_raw]" value="false" />
            <input
              type="checkbox"
              name="security[treat_quotes_as_raw]"
              value="true"
              checked={@security.treat_quotes_as_raw}
            />
            <small class="dialog-help">
              <%= gettext(
                "For providers that never back-adjust pre-split quotes — the display applies the split factors instead."
              ) %>
            </small>
          </label>
        </div>
        <button type="submit" class="button"><%= gettext("Save changes") %></button>
      </form>

      <dl class="overview-grid overview-grid--readonly">
        <.overview_field label={gettext("Feed")} value={@security.feed} />
        <.overview_field label={gettext("Latest quote feed")} value={@security.latest_feed} />
        <%= if @security.is_retired do %>
          <div class="overview-field overview-field--full">
            <dt><%= gettext("Status") %></dt>
            <dd><span class="badge badge--retired"><%= gettext("Retired") %></span></dd>
          </div>
        <% end %>
      </dl>

      <dl class="overview-metrics">
        <div class="overview-metric">
          <dt><%= gettext("Latest price") %></dt>
          <dd>
            <%= if @metrics[:latest_price] do %>
              <%= Format.decimal(@metrics.latest_price, 2) %>
              <small class="overview-metric__unit"><%= @security.currency_code %></small>
              <%= if @metrics[:latest_price_date] do %>
                <small class="overview-metric__sub">
                  (<%= Date.to_iso8601(@metrics.latest_price_date) %>)
                </small>
              <% end %>
            <% else %>
              —
            <% end %>
          </dd>
        </div>
        <%!-- Signed metrics carry gain/loss colour at every level, not only
             totals (UX-DR7, issue 637). --%>
        <div class="overview-metric">
          <dt><%= gettext("Day change") %></dt>
          <dd class={pnl_class(@metrics[:day_change_pct])}>
            <%= signed_percent_or_dash(@metrics[:day_change_pct]) %>
          </dd>
        </div>
        <div class="overview-metric">
          <dt>1M</dt>
          <dd class={pnl_class(@metrics[:performance_1m])}>
            <%= signed_percent_or_dash(@metrics[:performance_1m]) %>
          </dd>
        </div>
        <div class="overview-metric">
          <dt>1Y</dt>
          <dd class={pnl_class(@metrics[:performance_1y])}>
            <%= signed_percent_or_dash(@metrics[:performance_1y]) %>
          </dd>
        </div>
      </dl>

      <form
        id="overview-notes-form"
        phx-submit="save_detail_note"
        class="overview-notes"
        aria-label={gettext("Notes")}
      >
        <label for="overview-notes-input"><%= gettext("Notes") %></label>
        <textarea
          id="overview-notes-input"
          name="security[note]"
          rows="3"
          placeholder={gettext("Add a personal note for this security…")}
        ><%= @security.note %></textarea>
        <button type="submit" class="button">
          <%= gettext("Save notes") %>
        </button>
      </form>
    </section>
    """
  end

  attr(:transactions, :list, required: true)

  defp transactions_tab_panel(assigns) do
    assigns = assign(assigns, :rows, Enum.reverse(assigns.transactions))

    ~H"""
    <section
      id="detail-tab-panel-transactions"
      role="tabpanel"
      class="detail-tab-panel detail-tab-panel--transactions"
    >
      <%= if @rows == [] do %>
        <p class="detail-tab-empty">
          <%= gettext("No transactions for this security yet.") %>
        </p>
      <% else %>
        <div class="data-table-wrap">
          <table class="data-table detail-transactions-table">
            <thead>
              <tr>
                <th><%= gettext("Date") %></th>
                <th><%= gettext("Type") %></th>
                <th class="num"><%= gettext("Quantity") %></th>
                <th class="num"><%= gettext("Price") %></th>
                <th class="num"><%= gettext("Fees") %></th>
                <th class="num"><%= gettext("Taxes") %></th>
                <th class="num"><%= gettext("Gross") %></th>
                <th><%= gettext("Depot") %></th>
                <th><%= gettext("Notes") %></th>
              </tr>
            </thead>
            <tbody>
              <%= for tx <- @rows do %>
                <tr class={"tx-row tx-row--#{tx.type}"}>
                  <td><%= Date.to_iso8601(tx.date) %></td>
                  <td>
                    <span class={"badge tx-badge tx-badge--#{tx.type}"}>
                      <%= tx_type_label(tx.type) %>
                    </span>
                  </td>
                  <%= if tx.type == "split" do %>
                    <%!-- A split has no money legs: the quantity column
                          carries the ratio, the money columns stay empty
                          instead of rendering "— EUR" / 0.00 clutter (E17
                          review, finding 7). --%>
                    <td class="num" data-role="split-ratio"><%= split_ratio_label(tx) %></td>
                    <td class="num">—</td>
                    <td class="num">—</td>
                    <td class="num">—</td>
                    <td class="num">—</td>
                  <% else %>
                    <td class="num"><%= Format.decimal(tx.quantity, 4) %></td>
                    <td class="num">
                      <%= Format.decimal(tx.price, 2) %>
                      <small><%= tx.currency_code %></small>
                    </td>
                    <td class="num"><%= Format.decimal(tx.fees, 2) %></td>
                    <td class="num"><%= Format.decimal(tx.taxes, 2) %></td>
                    <td class="num"><%= Format.decimal(tx_gross(tx), 2) %></td>
                  <% end %>
                  <td><%= depot_name(tx) %></td>
                  <td><%= tx.notes %></td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>
    </section>
    """
  end

  attr(:trades, :map, required: true)
  attr(:currency_code, :string, default: nil)

  defp trades_tab_panel(assigns) do
    ~H"""
    <section
      id="detail-tab-panel-trades"
      role="tabpanel"
      class="detail-tab-panel detail-tab-panel--trades"
    >
      <%= if @trades.open_lots == [] and @trades.closed_trades == [] do %>
        <p class="detail-tab-empty">
          <%= gettext("No matched trades yet — record some buys and sells first.") %>
        </p>
      <% end %>

      <%= if @trades.open_lots != [] do %>
        <h3 class="detail-section-title"><%= gettext("Open positions (FIFO)") %></h3>
        <%!-- ADR-0033: lots carry the same decomposition as the holdings —
             the committed copy sits behind the ⓘ tooltip. --%>
        <details class="metric-tooltip" data-role="lot-decomposition-info">
          <summary aria-label={gettext("About price and currency return")}>ⓘ <%= gettext("Price & currency return") %></summary>
          <p role="tooltip">
            <%= gettext(
              "Price return — the change of the security's own price, converted at today's rate. Currency return — the effect of the exchange rate on the amount originally invested. Together they equal the position's total gain or loss in EUR. A dash marks a lot whose decomposition cannot be derived from the recorded data."
            ) %>
          </p>
        </details>
        <div class="data-table-wrap">
          <table class="data-table detail-trades-table">
            <thead>
              <tr>
                <th><%= gettext("Open date") %></th>
                <th class="num"><%= gettext("Quantity") %></th>
                <th class="num"><%= gettext("Avg buy") %></th>
                <th class="num"><%= gettext("Latest") %></th>
                <th class="num"><%= gettext("Unrealised P&L") %></th>
                <th class="num">%</th>
                <th class="num"><%= gettext("Price return") %></th>
                <th class="num"><%= gettext("Currency return") %></th>
                <th class="num"><%= gettext("Total (base)") %></th>
              </tr>
            </thead>
            <tbody>
              <%= for lot <- @trades.open_lots do %>
                <tr>
                  <td><%= Date.to_iso8601(lot.open_date) %></td>
                  <td class="num"><%= Format.decimal(lot.quantity, 4) %></td>
                  <%!-- The security-currency basis (ADR-0033): comparable to
                       the Latest column; a dash means no native leg is
                       derivable from the recorded booking. --%>
                  <td class="num" data-role="lot-buy-price-native">
                    <%= if lot.buy_price_native do %>
                      <%= Format.decimal(lot.buy_price_native, 2) %>
                    <% else %>
                      —
                    <% end %>
                  </td>
                  <td class="num">
                    <%= if lot.latest_price do %>
                      <%= Format.decimal(lot.latest_price, 2) %>
                    <% else %>
                      —
                    <% end %>
                  </td>
                  <td class={["num", pnl_class(lot.unrealized_pnl_abs)]}>
                    <%= signed_decimal_or_dash(lot.unrealized_pnl_abs, 2) %>
                  </td>
                  <td class={["num", pnl_class(lot.unrealized_pnl_abs)]}>
                    <%= signed_percent_or_dash(lot.unrealized_pnl_pct) %>
                  </td>
                  <td class={["num", pnl_class(lot.price_return_abs)]} data-role="price-return">
                    <%= signed_decimal_or_dash(lot.price_return_abs, 2) %>
                  </td>
                  <td class={["num", pnl_class(lot.currency_return_abs)]} data-role="currency-return">
                    <%= signed_decimal_or_dash(lot.currency_return_abs, 2) %>
                  </td>
                  <td
                    class={["num", pnl_class(lot.total_return_base_abs)]}
                    data-role="total-return-base"
                    title={undecomposed_hint(lot)}
                  >
                    <%= signed_decimal_or_dash(lot.total_return_base_abs, 2) %>
                    <small :if={lot.decomposed}><%= lot.base_currency %></small>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>

      <%= if @trades.closed_trades != [] do %>
        <h3 class="detail-section-title"><%= gettext("Closed trades (FIFO)") %></h3>
        <div class="data-table-wrap">
          <table class="data-table detail-trades-table">
            <thead>
              <tr>
                <th><%= gettext("Opened") %></th>
                <th><%= gettext("Closed") %></th>
                <th class="num"><%= gettext("Quantity") %></th>
                <th class="num"><%= gettext("Avg buy") %></th>
                <th class="num"><%= gettext("Avg sell") %></th>
                <th class="num"><%= gettext("Days") %></th>
                <th class="num"><%= gettext("Realised P&L") %></th>
                <th class="num">%</th>
              </tr>
            </thead>
            <tbody>
              <%= for trade <- @trades.closed_trades do %>
                <tr>
                  <td><%= Date.to_iso8601(trade.open_date) %></td>
                  <td><%= Date.to_iso8601(trade.close_date) %></td>
                  <td class="num"><%= Format.decimal(trade.quantity, 4) %></td>
                  <td class="num"><%= Format.decimal(trade.avg_buy_price, 2) %></td>
                  <td class="num"><%= Format.decimal(trade.avg_sell_price, 2) %></td>
                  <td class="num"><%= trade.holding_period_days %></td>
                  <td class={["num", pnl_class(trade.realized_pnl_abs)]}>
                    <%= signed_decimal_or_dash(trade.realized_pnl_abs, 2) %>
                  </td>
                  <td class={["num", pnl_class(trade.realized_pnl_abs)]}>
                    <%= signed_percent_or_dash(trade.realized_pnl_pct) %>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>

      <%= if @trades.orphan_sells != [] do %>
        <p class="detail-tab-warning">
          <%= gettext(
            "Some sell transactions could not be matched to a preceding buy — they may indicate missing data."
          ) %>
        </p>
      <% end %>
    </section>
    """
  end

  attr(:holdings, :list, required: true)
  attr(:currency_code, :string, default: nil)
  attr(:buckets, :list, default: [])

  defp holdings_tab_panel(assigns) do
    totals =
      Enum.reduce(assigns.holdings, %{value: Decimal.new(0), cost: Decimal.new(0)}, fn h, acc ->
        if h.current_value && h.cost_basis do
          %{
            value: Decimal.add(acc.value, h.current_value),
            cost: Decimal.add(acc.cost, h.cost_basis)
          }
        else
          acc
        end
      end)

    total_pnl = Decimal.sub(totals.value, totals.cost)
    assigns = assign(assigns, :totals, totals) |> assign(:total_pnl, total_pnl)

    ~H"""
    <section
      id="detail-tab-panel-holdings"
      role="tabpanel"
      class="detail-tab-panel detail-tab-panel--holdings"
    >
      <%= if @holdings == [] do %>
        <p class="detail-tab-empty">
          <%= gettext("No open positions for this security in any depot.") %>
        </p>
      <% else %>
        <%!-- ADR-0033: the committed decomposition explanation lives in the
             ⓘ tooltip, not inline. --%>
        <details class="metric-tooltip" data-role="pnl-decomposition-info">
          <summary aria-label={gettext("About price and currency return")}>ⓘ <%= gettext("Price & currency return") %></summary>
          <p role="tooltip">
            <%= gettext(
              "Price return — the change of the security's own price, converted at today's rate. Currency return — the effect of the exchange rate on the amount originally invested. Together they equal the position's total gain or loss in EUR. A dash marks a position whose decomposition cannot be derived from the recorded data."
            ) %>
          </p>
        </details>
        <div class="data-table-wrap">
          <table class="data-table detail-holdings-table">
            <thead>
              <tr>
                <th><%= gettext("Depot") %></th>
                <th class="num"><%= gettext("Quantity") %></th>
                <th class="num"><%= gettext("Avg cost") %></th>
                <th class="num"><%= gettext("Current value") %></th>
                <th class="num"><%= gettext("Unrealised P&L") %></th>
                <th class="num">%</th>
                <th class="num"><%= gettext("Price return") %></th>
                <th class="num"><%= gettext("Currency return") %></th>
                <th class="num"><%= gettext("Total (base)") %></th>
              </tr>
            </thead>
            <tbody>
              <%= for h <- @holdings do %>
                <tr>
                  <td>
                    <%= h.depot && h.depot.name %>
                    <span
                      :if={Decimal.compare(h.quantity, 0) == :lt}
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
                  </td>
                  <td class={["num", Decimal.compare(h.quantity, 0) == :lt && "is-negative"]}>
                    <%= Format.decimal(h.quantity, 4) %>
                  </td>
                  <td class="num">
                    <%= Format.decimal(h.avg_cost, 2) %>
                    <small><%= @currency_code %></small>
                  </td>
                  <td class="num">
                    <%= if h.current_value do %>
                      <%= Format.decimal(h.current_value, 2) %>
                      <small><%= @currency_code %></small>
                    <% else %>
                      —
                    <% end %>
                  </td>
                  <td class={["num", pnl_class(h.unrealized_pnl_abs)]}>
                    <%= signed_decimal_or_dash(h.unrealized_pnl_abs, 2) %>
                  </td>
                  <td class={["num", pnl_class(h.unrealized_pnl_abs)]}>
                    <%= signed_percent_or_dash(h.unrealized_pnl_pct) %>
                  </td>
                  <td class={["num", pnl_class(h.price_return_abs)]} data-role="price-return">
                    <%= signed_decimal_or_dash(h.price_return_abs, 2) %>
                  </td>
                  <td class={["num", pnl_class(h.currency_return_abs)]} data-role="currency-return">
                    <%= signed_decimal_or_dash(h.currency_return_abs, 2) %>
                  </td>
                  <td
                    class={["num", pnl_class(h.total_return_base_abs)]}
                    data-role="total-return-base"
                    title={undecomposed_hint(h)}
                  >
                    <%= signed_decimal_or_dash(h.total_return_base_abs, 2) %>
                    <small :if={h.decomposed}><%= h.base_currency %></small>
                  </td>
                </tr>
                <tr :if={h.depot} class="bucket-override-row" id={"position-buckets-#{h.depot.id}"}>
                  <td colspan="9">
                    <.position_bucket_override holding={h} buckets={@buckets} />
                  </td>
                </tr>
              <% end %>
            </tbody>
            <tfoot>
              <tr class="totals-row">
                <td colspan="3"><%= gettext("Total") %></td>
                <td class="num">
                  <%= Format.decimal(@totals.value, 2) %>
                  <small><%= @currency_code %></small>
                </td>
                <td class={["num", pnl_class(@total_pnl)]}>
                  <%= signed_decimal_or_dash(@total_pnl, 2) %>
                </td>
                <td class="num" colspan="4"></td>
              </tr>
            </tfoot>
          </table>
        </div>
      <% end %>
    </section>
    """
  end

  # Per-position bucket override (issue #446), shown via progressive disclosure
  # under each holding row. The state is one of three, made visually distinct:
  #
  #   * inherit         — the position uses the depot's default buckets;
  #   * explicit-empty  — deliberately "no buckets (excluded)", NOT inheriting;
  #   * explicit list   — its own bucket set, overriding the depot default.
  #
  # A radio group picks the mode; the checklist is only meaningful for the
  # explicit list. Saving routes through `Buckets.set_position_override/4`
  # (explicit list / explicit-empty) or `Buckets.clear_position_override/3`
  # (inherit).
  attr(:holding, :map, required: true)
  attr(:buckets, :list, required: true)

  defp position_bucket_override(assigns) do
    ~H"""
    <details class="position-buckets">
      <summary>
        <%= gettext("Buckets") %>:
        <span data-role="override-state"><%= override_state_label(@holding.override) %></span>
      </summary>
      <form phx-submit="set_position_buckets" class="position-buckets__form">
        <input type="hidden" name="depot_id" value={@holding.depot.id} />

        <fieldset class="bucket-fieldset" role="radiogroup" aria-label={gettext("Bucket assignment mode")}>
          <label class="bucket-checkbox">
            <input
              type="radio"
              name="mode"
              value="inherit"
              checked={@holding.override == :inherit}
            />
            <span>
              <%= gettext("Inherit from depot") %>
              <small data-role="inherited-buckets">(<%= bucket_names(@holding.depot_default_bucket_ids, @buckets) %>)</small>
            </span>
          </label>
          <label class="bucket-checkbox">
            <input
              type="radio"
              name="mode"
              value="empty"
              checked={@holding.override == :explicit_empty}
            />
            <span><%= gettext("No buckets (excluded)") %></span>
          </label>
          <label class="bucket-checkbox">
            <input
              type="radio"
              name="mode"
              value="explicit"
              checked={match?({:explicit, _}, @holding.override)}
            />
            <span><%= gettext("Choose specific buckets") %></span>
          </label>
        </fieldset>

        <fieldset class="bucket-fieldset">
          <legend class="visually-hidden"><%= gettext("Buckets") %></legend>
          <%= for bucket <- @buckets do %>
            <label class="bucket-checkbox" for={"position-bucket-#{@holding.depot.id}-#{bucket.id}"}>
              <input
                type="checkbox"
                id={"position-bucket-#{@holding.depot.id}-#{bucket.id}"}
                name="bucket_ids[]"
                value={bucket.id}
                checked={bucket.id in @holding.explicit_bucket_ids}
              />
              <span><%= bucket.name %></span>
            </label>
          <% end %>
          <p :if={@buckets == []} class="hint"><%= gettext("Create a bucket first.") %></p>
        </fieldset>

        <button type="submit" class="button"><%= gettext("Save buckets") %></button>
      </form>
    </details>
    """
  end

  attr(:security, :map, required: true)
  attr(:classifications, :list, required: true)
  attr(:new_category_for, :integer, default: nil)

  defp classifications_tab_panel(assigns) do
    ~H"""
    <section
      id="detail-tab-panel-classifications"
      role="tabpanel"
      class="detail-tab-panel detail-tab-panel--classifications"
    >
      <p class="detail-tab-hint">
        <%= gettext("Set how this security is classified in each custom tree. Built-in trees are filled in automatically.") %>
      </p>

      <ul class="security-classifications">
        <%= for entry <- @classifications do %>
          <li class="security-classification">
            <div class="sc-head">
              <span class="sc-name"><%= ClassificationName.display(entry.classification) %></span>
              <%= unless entry.editable do %>
                <span class="badge"><%= gettext("Built-in") %></span>
              <% end %>
            </div>
            <%= if entry.editable do %>
              <form id={"sc-form-#{entry.classification.id}"} phx-change="set_security_classification" class="sc-form">
                <input type="hidden" name="classification_id" value={entry.classification.id} />
                <select name="category_id" aria-label={entry.classification.name}>
                  <option value="" selected={is_nil(entry.selected_category_id)}>
                    <%= gettext("— Unassigned —") %>
                  </option>
                  <%= for {category, depth} <- entry.categories do %>
                    <option
                      value={category.id}
                      selected={entry.selected_category_id == category.id}
                    >
                      <%= classification_indent(depth) %><%= category.name %>
                    </option>
                  <% end %>
                  <option value="__new__"><%= gettext("➕ New category…") %></option>
                </select>
              </form>
              <%= if @new_category_for == entry.classification.id do %>
                <form phx-submit="create_and_assign_category" class="sc-new-category">
                  <input type="hidden" name="classification_id" value={entry.classification.id} />
                  <input name="name" placeholder={gettext("New category name")} required />
                  <button type="submit" class="button"><%= gettext("Create & assign") %></button>
                  <button type="button" phx-click="cancel_new_category">
                    <%= gettext("Cancel") %>
                  </button>
                </form>
              <% end %>
            <% else %>
              <span class="sc-value"><%= builtin_category_name(entry) %></span>
            <% end %>
          </li>
        <% end %>
        <%= if @classifications == [] do %>
          <li class="detail-tab-empty"><%= gettext("No classifications yet.") %></li>
        <% end %>
      </ul>

      <p class="detail-tab-hint">
        <.link navigate="/classifications"><%= gettext("Manage classifications") %></.link>
      </p>
    </section>
    """
  end

  defp classification_indent(0), do: ""
  defp classification_indent(depth), do: String.duplicate("— ", depth)

  defp builtin_category_name(entry) do
    Enum.find_value(entry.categories, fn {category, _depth} ->
      category.id == entry.selected_category_id && category.name
    end) || gettext("— Unassigned —")
  end

  attr(:quotes, :list, required: true)
  attr(:currency_code, :string, default: nil)
  attr(:range, :string, default: nil)
  attr(:series_basis, :atom, default: :empty)
  attr(:split_events, :list, default: [])

  defp quotes_tab_panel(assigns) do
    assigns = assign(assigns, :rows, Enum.reverse(assigns.quotes))

    ~H"""
    <section
      id="detail-tab-panel-quotes"
      role="tabpanel"
      class="detail-tab-panel detail-tab-panel--quotes"
    >
      <%= if @rows == [] do %>
        <p class="detail-tab-empty">
          <%= gettext("No price history yet for the selected range.") %>
        </p>
      <% else %>
        <p class="detail-tab-hint">
          <%= gettext("Showing range %{range}. Adjust the Chart tab to change which quotes appear here.",
            range: @range || gettext("default")) %>
        </p>
        <p
          :if={series_basis_label(@series_basis, @split_events)}
          class="detail-tab-hint"
          data-role="quotes-basis"
        >
          <%= gettext("Price basis: %{basis}. The stored column keeps the unmodified values.",
            basis: series_basis_label(@series_basis, @split_events)
          ) %>
        </p>
        <div class="data-table-wrap">
          <table class="data-table detail-quotes-table">
            <thead>
              <tr>
                <th><%= gettext("Date") %></th>
                <th class="num"><%= gettext("Closing price") %></th>
                <th class="num"><%= gettext("Stored") %></th>
                <th><%= gettext("Source") %></th>
              </tr>
            </thead>
            <tbody>
              <%= for q <- @rows do %>
                <tr>
                  <td><%= Date.to_iso8601(q.date) %></td>
                  <td class="num">
                    <%= Format.decimal(q.close, 2) %>
                    <small><%= @currency_code %></small>
                  </td>
                  <td class="num">
                    <%= Format.decimal(q.stored_close, 2) %>
                  </td>
                  <td><span class="badge quote-source"><%= quote_source_label(q.source) %></span></td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>
    </section>
    """
  end

  @doc """
  Localized display label for a quote's source code — shared with the split
  wizard dialog so both quote tables render the same labels (E17 UX review,
  finding 6).
  """
  def quote_source_label("auto"), do: gettext("Auto")
  def quote_source_label("manual"), do: gettext("Manual")
  def quote_source_label("coingecko"), do: "CoinGecko"
  def quote_source_label("portfolio_performance"), do: "Portfolio Performance"
  def quote_source_label(other) when is_binary(other), do: other
  def quote_source_label(_), do: ""

  defp pnl_class(value) do
    case decimal_for_display(value) do
      nil ->
        nil

      d ->
        case Decimal.compare(d, 0) do
          :gt -> "is-positive"
          :lt -> "is-negative"
          _ -> nil
        end
    end
  end

  defp signed_decimal_or_dash(value, places) do
    Format.signed_decimal(decimal_for_display(value), places)
  end

  # Why a row's ADR-0033 decomposition is unavailable — terse, impersonal,
  # shown as the dash's title. Nil (no hint) for decomposed rows.
  defp undecomposed_hint(%{decomposed: true}), do: nil

  defp undecomposed_hint(%{undecomposed_reason: :missing_native_cost}),
    do:
      gettext(
        "No security-currency cost is derivable from the recorded booking (no settlement legs, no stored rate at the booking date)."
      )

  defp undecomposed_hint(%{undecomposed_reason: :missing_base_cost}),
    do: gettext("The recorded settlement leg is not in the base currency.")

  defp undecomposed_hint(%{undecomposed_reason: :missing_fx}),
    do: gettext("No stored exchange rate reaches the base currency.")

  defp undecomposed_hint(%{undecomposed_reason: :no_price}),
    do: gettext("No price is available for this security.")

  defp undecomposed_hint(_row), do: nil

  defp tx_type_label("buy"), do: gettext("Buy")
  defp tx_type_label("sell"), do: gettext("Sell")
  defp tx_type_label("split"), do: gettext("Split")
  defp tx_type_label(other), do: to_string(other)

  defp split_ratio_label(%{split_ratio_numerator: p, split_ratio_denominator: q})
       when is_integer(p) and is_integer(q),
       do: "#{p}:#{q}"

  defp split_ratio_label(_tx), do: "—"

  defp tx_gross(%{quantity: q, price: p} = tx) do
    with %Decimal{} = quantity <- decimal_for_display(q),
         %Decimal{} = price <- decimal_for_display(p) do
      Decimal.mult(quantity, price)
    else
      _ -> Map.get(tx, :gross_amount)
    end
  end

  defp tx_gross(%{gross_amount: gross}) when not is_nil(gross), do: gross

  defp tx_gross(_), do: nil

  defp depot_name(%{securities_account: %{name: name}}), do: name
  # Rows without a depot (e.g. splits) render an em dash like the money
  # columns instead of an empty cell (E17 UX review, finding 8).
  defp depot_name(_), do: "—"

  attr(:label, :string, required: true)
  attr(:value, :any, default: nil)
  attr(:mono, :boolean, default: false)

  defp overview_field(assigns) do
    ~H"""
    <%= if @value not in [nil, ""] do %>
      <div class={["overview-field", @mono && "overview-field--mono"]}>
        <dt><%= @label %></dt>
        <dd><%= @value %></dd>
      </div>
    <% end %>
    """
  end

  defp signed_percent_or_dash(value) do
    case decimal_for_display(value) do
      nil ->
        "—"

      fractional ->
        fractional
        |> Decimal.mult(Decimal.new(100))
        |> Format.signed_decimal(2)
        |> Kernel.<>(" %")
    end
  end

  defp build_chart_overlays(
         quotes,
         transactions,
         ma_toggles,
         cost_basis?,
         split_events,
         security_currency
       ) do
    ma_overlays =
      for {window, true} <- ma_toggles do
        %{
          class: "chart-ma-#{window}",
          label: "MA#{window}",
          points: moving_average(quotes, window)
        }
      end

    cost_basis_overlay =
      if cost_basis? do
        [
          %{
            class: "chart-cost-basis",
            label: gettext("Cost basis"),
            points: cost_basis_series(quotes, transactions, split_events, security_currency)
          }
        ]
      else
        []
      end

    Enum.reject(ma_overlays ++ cost_basis_overlay, &(&1.points == []))
  end

  defp moving_average(quotes, window) when window > 0 do
    quotes
    |> Enum.with_index()
    |> Enum.reduce({[], []}, fn {q, idx}, {windowed, acc} ->
      windowed = [Decimal.to_float(q.close) | windowed] |> Enum.take(window)

      if length(windowed) == window do
        avg = Enum.sum(windowed) / window
        {windowed, [%{date: q.date, value: avg, idx: idx} | acc]}
      else
        {windowed, acc}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp cost_basis_series(quotes, transactions, split_events, security_currency)
       when transactions != [] do
    # ADR-0033: the overlay folds SECURITY-currency prices onto a chart whose
    # quote series is in the security currency — a cross-currency buy without
    # a derivable native leg would poison the running average, so the overlay
    # is then honestly unavailable rather than wrong.
    case native_priced_for_overlay(transactions, security_currency) do
      :unavailable ->
        []

      native_transactions ->
        # Replay order (ADR-0028 §3): a same-day split applies before the day's
        # trades, exactly like every ledger quantity fold. The fan-out rows of
        # one booking dedupe into one security-level event first — the fold must
        # apply each ratio once per EVENT, not once per portfolio row (E17
        # review, finding 1a).
        series =
          native_transactions
          |> dedupe_split_rows()
          |> Projection.replay_sort()
          |> Enum.reduce({Decimal.new(0), Decimal.new(0), []}, &apply_cost_basis_point/2)
          |> elem(2)
          |> Enum.reverse()
          |> Enum.map(&display_basis_point(&1, split_events))

        # Extend the last value to the last visible quote date so the line is
        # visible across the chart.
        case {series, List.last(quotes)} do
          {[], _} ->
            []

          {_, nil} ->
            Enum.map(series, fn {d, v} -> %{date: d, value: v} end)

          {points, last_quote} ->
            {_d, last_v} = List.last(points)
            ext = points ++ [{last_quote.date, last_v}]
            Enum.map(ext, fn {d, v} -> %{date: d, value: v} end)
        end
    end
  end

  defp cost_basis_series(_quotes, _empty, _events, _security_currency), do: []

  # Rewrites each buy's price to its security-currency per-unit value: the
  # price itself for a same-currency booking, else the ADR-0015
  # `security_amount` divided by the quantity. A buy with no derivable
  # native leg makes the whole overlay unavailable (never a mixed fold).
  defp native_priced_for_overlay(transactions, security_currency) do
    transactions
    |> Enum.reduce_while([], fn tx, acc ->
      case tx.type do
        "buy" ->
          case overlay_native_price(tx, security_currency) do
            nil -> {:halt, :unavailable}
            price -> {:cont, [%{tx | price: price} | acc]}
          end

        _other ->
          {:cont, [tx | acc]}
      end
    end)
    |> case do
      :unavailable -> :unavailable
      reversed -> Enum.reverse(reversed)
    end
  end

  defp overlay_native_price(tx, security_currency) do
    cond do
      is_nil(security_currency) or tx.currency_code == security_currency ->
        tx.price

      match?(%Decimal{}, tx.security_amount) and match?(%Decimal{}, tx.quantity) and
          not Decimal.equal?(tx.quantity, 0) ->
        Decimal.div(tx.security_amount, tx.quantity)

      true ->
        nil
    end
  end

  # One row per (date, normalized ratio) — the identity quote consumers use
  # for security-level split events; non-split rows pass through untouched.
  defp dedupe_split_rows(transactions) do
    Enum.uniq_by(transactions, fn
      %{type: "split"} = tx ->
        {:split, tx.date, tx.split_ratio_numerator, tx.split_ratio_denominator}

      tx ->
        {:tx, tx.id}
    end)
  end

  # Each fold point carries the raw (as-traded) basis of its own era, but
  # the chart's price series is display basis — rebase by the cumulative
  # ratio of all strictly-later split events, exactly like a raw close (E17
  # review, finding 1b). Float conversion happens only here, at the chart
  # boundary.
  defp display_basis_point({date, %Decimal{} = value}, split_events) do
    {date,
     value
     |> QuoteAdjustment.display_close(date, :raw, split_events)
     |> Decimal.to_float()}
  end

  defp apply_cost_basis_point(%{type: "buy"} = tx, {qty_held, avg_cost, points}) do
    new_qty = Decimal.add(qty_held, tx.quantity)

    new_avg =
      if Decimal.equal?(new_qty, 0) do
        Decimal.new(0)
      else
        numerator =
          Decimal.add(Decimal.mult(qty_held, avg_cost), Decimal.mult(tx.quantity, tx.price))

        Decimal.div(numerator, new_qty)
      end

    {new_qty, new_avg, [{tx.date, new_avg} | points]}
  end

  defp apply_cost_basis_point(%{type: "sell"} = tx, {qty_held, avg_cost, points}) do
    {Decimal.sub(qty_held, tx.quantity), avg_cost, [{tx.date, avg_cost} | points]}
  end

  # ADR-0028 §3 for the overlay: quantity scales by the ratio, total cost is
  # invariant, so the per-share average divides — the running average moves
  # into the post-split era, and `display_basis_point/2` rebases every
  # emitted point onto the display scale afterwards.
  defp apply_cost_basis_point(%{type: "split"} = tx, {qty_held, avg_cost, points}) do
    {p, q} = {tx.split_ratio_numerator, tx.split_ratio_denominator}
    new_avg = avg_cost |> Decimal.mult(q) |> Decimal.div(p)
    new_qty = qty_held |> Decimal.mult(p) |> Decimal.div(q)
    {new_qty, new_avg, [{tx.date, new_avg} | points]}
  end

  defp apply_cost_basis_point(_tx, acc), do: acc

  defp detail_tabs do
    [
      {"overview", gettext("Overview")},
      {"chart", gettext("Chart")},
      {"transactions", gettext("Transactions")},
      {"trades", gettext("Trades")},
      {"quotes", gettext("Quotes")},
      {"holdings", gettext("Holdings")},
      {"classifications", gettext("Classifications")}
    ]
  end

  defp tab_param(tab) when tab == @default_tab, do: nil
  defp tab_param(tab), do: tab

  defp selected?(nil, _row), do: false
  defp selected?(%Security{id: id}, row), do: id == security_id(row)

  defp visible_fields(visible, classification_specs) when is_list(visible) do
    visible
    |> Enum.map(&column_field(&1, classification_specs))
    |> Enum.reject(&is_nil/1)
  end

  defp column_field({:classification, _id, _level} = key, classification_specs),
    do: classification_field(key, classification_specs)

  defp column_field(key, _classification_specs) when is_atom(key), do: SecurityFields.get(key)

  # A classification column (#565) is a virtual field: value attached into the
  # row's metrics map by `attach_classification_columns/1`, so `:metric` is the
  # source and the shared render/sort plumbing applies. Not filterable —
  # like the quote-metric columns, filters stay registry-backed in v1.
  defp classification_field({:classification, id, level} = key, classification_specs) do
    case Enum.find(classification_specs, &(&1.classification.id == id)) do
      %{classification: classification, levels: levels} when level <= levels ->
        %Field{
          key: key,
          label: classification_column_label(classification, level, levels),
          type: :string,
          source: :metric,
          group: :classifications,
          sortable?: true,
          filterable?: false,
          operators: [],
          render_hint: :text
        }

      _ ->
        nil
    end
  end

  defp classification_column_label(classification, _level, 1),
    do: ClassificationName.display(classification)

  defp classification_column_label(classification, level, _levels) do
    gettext("%{name} (level %{level})",
      name: ClassificationName.display(classification),
      level: level
    )
  end

  defp column_key_string(key) when is_atom(key), do: Atom.to_string(key)

  defp column_key_string({:classification, id, level}), do: "classification:#{id}:#{level}"

  # Maps a client-supplied column key string to a registry atom or a validated
  # `{:classification, id, level}` tuple; unknown or stale keys become nil.
  # Never mints atoms.
  defp safe_column_key(key, classification_specs) when is_binary(key) do
    case safe_column_atom(key) do
      nil -> parse_classification_key(key, classification_specs)
      atom -> atom
    end
  end

  defp safe_column_key(_key, _classification_specs), do: nil

  defp parse_classification_key("classification:" <> rest, classification_specs) do
    with [id_str, level_str] <- String.split(rest, ":"),
         {id, ""} <- Integer.parse(id_str),
         {level, ""} <- Integer.parse(level_str),
         %Field{} = field <-
           classification_field({:classification, id, level}, classification_specs) do
      field.key
    else
      _ -> nil
    end
  end

  defp parse_classification_key(_key, _classification_specs), do: nil

  defp first_visible_key([%Field{key: key} | _]), do: key
  defp first_visible_key(_), do: :name

  defp security_id(%SecurityWithMetrics{security: security}), do: security.id
  defp security_id(%{id: id}), do: id

  defp security_from_row(%SecurityWithMetrics{security: security}), do: security
  defp security_from_row(%Security{} = security), do: security

  attr(:security, :any, required: true)
  attr(:variant, :string, default: "row")

  defp security_logo(assigns) do
    path = get_in(assigns.security.attributes || %{}, ["logo_path"])
    fallback = security_logo_fallback(assigns.security)

    assigns =
      assigns
      |> assign(:path, path)
      |> assign(:fallback, fallback)

    ~H"""
    <%= if @path do %>
      <img class={"security-logo security-logo--#{@variant}"} src={@path} alt="" loading="lazy" />
    <% else %>
      <%= case @fallback do %>
        <% {:flag, flag} -> %>
          <span
            class={"security-logo security-logo--#{@variant} security-logo--flag"}
            aria-hidden="true"
          >
            <%= flag %>
          </span>
        <% {:initial, initial} -> %>
          <span
            class={"security-logo security-logo--#{@variant} security-logo--initial"}
            aria-hidden="true"
          >
            <%= initial %>
          </span>
      <% end %>
    <% end %>
    """
  end

  defp security_logo_fallback(%Security{isin: isin, name: name} = security)
       when is_binary(isin) do
    asset_class = Security.effective_asset_class(security)

    case isin_country_code(isin) do
      <<a, b>> when asset_class in ["bond", "government_bond"] -> {:flag, country_flag(a, b)}
      _ -> {:initial, initial_letter(name)}
    end
  end

  defp security_logo_fallback(%Security{name: name}), do: {:initial, initial_letter(name)}

  defp isin_country_code(isin) do
    code =
      isin
      |> String.trim()
      |> String.slice(0, 2)
      |> String.upcase()

    if code =~ ~r/^[A-Z]{2}$/, do: code
  end

  defp country_flag(a, b) do
    <<0x1F1E6 + a - ?A::utf8, 0x1F1E6 + b - ?A::utf8>>
  end

  defp initial_letter(nil), do: "?"

  defp initial_letter(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.first()
    |> case do
      nil -> "?"
      letter -> String.upcase(letter)
    end
  end

  defp initial_letter(_), do: "?"

  defp sort_marker({key, :asc}, key), do: " ↑"
  defp sort_marker({key, :desc}, key), do: " ↓"
  defp sort_marker(_, _), do: ""

  # The asset-class cell is the one place stored and effective have to be told
  # apart (#700). The decision, which #705's API/MCP predicates must match:
  #
  #   * the DISPLAY is the EFFECTIVE class, because that is what valuation and
  #     the classification trees already use -- showing the stored NULL instead
  #     would make this list disagree with the allocation;
  #   * the COUNT, the FILTER and the QUICK-ASSIGN affordance are keyed on the
  #     STORED class, because an inferred class is a guess rather than a stated,
  #     auditable fact. Keying them on effective is what made the surface
  #     contradict itself: the dashboard counted stored NULLs and opened a list
  #     in which every row already showed a class, and the quick-assign control
  #     -- which only rendered on a nil cell -- therefore never appeared, so
  #     #561's remediation loop could not open.
  #
  # A derived class is marked as derived rather than shown as if stated, and the
  # marking never rides on colour alone: it carries a real-text qualifier before
  # the value in document order plus a data attribute, so it survives
  # `forced-colors: active` (DESIGN.md → Value slot, binding since 2026-08-05).
  #
  # options_html is constructed entirely from AssetClasses.options() (compile-time
  # constants) with every value passed through html_escape/1 — no user input.
  # sobelow_skip ["XSS.Raw"]
  defp render_cell(%Field{key: :asset_class} = field, row) do
    case {security_from_row(row).asset_class, SecurityFields.value(field, row)} do
      # Stated by the operator: a plain badge, and no remediation prompt.
      {stored, _effective} when is_binary(stored) ->
        Phoenix.HTML.raw(
          ~s(<span class="badge" data-asset-class="stated">) <>
            escaped(AssetClasses.label(stored)) <>
            ~s(</span>)
        )

      # Not stated, but derivable: show what we derived, say that we derived it,
      # and still offer the control that turns it into a stated value.
      {nil, effective} when is_binary(effective) ->
        Phoenix.HTML.raw(
          ~s(<span class="badge badge--derived" data-asset-class="derived">) <>
            ~s(<span class="visually-hidden">) <>
            escaped(gettext("Derived:")) <>
            ~s( </span>) <>
            ~s(<span class="badge-derived-marker" aria-hidden="true">≈</span>) <>
            escaped(AssetClasses.label(effective)) <>
            ~s(</span>) <>
            quick_assign_form(row)
        )

      # Neither stated nor derivable.
      {nil, nil} ->
        Phoenix.HTML.raw(quick_assign_form(row))
    end
  end

  defp render_cell(%Field{render_hint: :badge, key: key} = field, security) do
    case SecurityFields.value(field, security) do
      nil ->
        ""

      value ->
        Phoenix.HTML.raw(
          ~s(<span class="badge">#{Phoenix.HTML.html_escape(display_value(key, value)) |> safe_to_string()}</span>)
        )
    end
  end

  defp render_cell(%Field{render_hint: :code, key: key} = field, security) do
    case SecurityFields.value(field, security) do
      nil ->
        ""

      value ->
        Phoenix.HTML.raw(
          ~s(<code>#{Phoenix.HTML.html_escape(display_value(key, value)) |> safe_to_string()}</code>)
        )
    end
  end

  defp render_cell(%Field{render_hint: :checkbox} = field, security) do
    case SecurityFields.value(field, security) do
      true -> <<0xE2, 0x9C, 0x93>>
      _ -> ""
    end
  end

  defp render_cell(%Field{render_hint: :money} = field, security) do
    case SecurityFields.value(field, security) do
      nil -> ""
      value -> Format.decimal(decimal_for_display(value), 2)
    end
  end

  defp render_cell(%Field{render_hint: :money_signed} = field, security) do
    case SecurityFields.value(field, security) do
      nil ->
        ""

      value ->
        formatted = Format.signed_decimal(decimal_for_display(value), 2)

        Phoenix.HTML.raw(
          ~s(<span class="#{decimal_class(value)}">#{Phoenix.HTML.html_escape(formatted) |> safe_to_string()}</span>)
        )
    end
  end

  defp render_cell(%Field{render_hint: :percent_signed} = field, security) do
    case SecurityFields.value(field, security) do
      nil ->
        ""

      value ->
        case decimal_for_display(value) do
          nil ->
            ""

          decimal ->
            # value is a fractional decimal (0.05 → +5.00 %)
            as_percent = Decimal.mult(decimal, Decimal.new(100))
            formatted = Format.signed_decimal(as_percent, 2) <> " %"

            Phoenix.HTML.raw(
              ~s(<span class="#{decimal_class(decimal)}">#{Phoenix.HTML.html_escape(formatted) |> safe_to_string()}</span>)
            )
        end
    end
  end

  defp render_cell(%Field{render_hint: :date} = field, security) do
    case SecurityFields.value(field, security) do
      nil -> ""
      %Date{} = d -> Date.to_iso8601(d)
      other -> to_string(other)
    end
  end

  defp render_cell(field, security) do
    case SecurityFields.value(field, security) do
      nil -> ""
      value -> display_value(field.key, value)
    end
  end

  defp escaped(value), do: Phoenix.HTML.html_escape(value) |> safe_to_string()

  defp quick_assign_form(row) do
    sec_id = to_string(security_id(row))

    options_html =
      AssetClasses.options()
      |> Enum.map_join("", fn {label, code} ->
        ~s(<option value="#{escaped(code)}">#{escaped(label)}</option>)
      end)

    ~s[<form id="quick-assign-#{sec_id}" phx-change="quick_assign_asset_class" phx-value-id="#{sec_id}" onclick="event.stopPropagation()" class="quick-assign-form">] <>
      ~s[<select name="asset_class" class="quick-assign-select" aria-label="#{escaped(gettext("Assign asset class"))}">] <>
      ~s[<option value="">—</option>] <>
      options_html <>
      ~s[</select></form>]
  end

  defp decimal_class(value) do
    case decimal_for_display(value) do
      nil ->
        "decimal-neutral"

      decimal ->
        case Decimal.compare(decimal, 0) do
          :gt -> "decimal-positive"
          :lt -> "decimal-negative"
          :eq -> "decimal-neutral"
        end
    end
  end

  defp decimal_for_display(nil), do: nil
  defp decimal_for_display(%Decimal{} = value), do: value
  defp decimal_for_display(value) when is_integer(value), do: Decimal.new(value)

  defp decimal_for_display(value) when is_float(value) do
    Decimal.from_float(value)
  rescue
    _ -> nil
  end

  defp decimal_for_display(value) when is_binary(value) do
    value = String.trim(value)

    if value == "" do
      nil
    else
      Decimal.new(value)
    end
  rescue
    _ -> nil
  end

  defp decimal_for_display(_), do: nil

  defp display_value(:feed, value), do: Feeds.label(value)
  defp display_value(:latest_feed, value), do: Feeds.label(value)
  defp display_value(_key, value), do: to_string(value)

  defp safe_to_string({:safe, iodata}), do: IO.iodata_to_binary(iodata)

  defp chip_label(%{key: key, op: op, value: value}) do
    field = SecurityFields.get(key)
    label = (field && field.label) || Atom.to_string(key)
    "#{label} #{operator_label(op)} #{format_value(key, value)}"
  end

  defp operator_label(:eq), do: "="
  defp operator_label(:neq), do: "≠"
  defp operator_label(:contains), do: "~"
  defp operator_label(:starts_with), do: "^"
  defp operator_label(:gt), do: ">"
  defp operator_label(:lt), do: "<"
  defp operator_label(:is_true), do: "= true"
  defp operator_label(:is_false), do: "= false"
  defp operator_label(:is_nil), do: gettext("is unclassified")
  defp operator_label(other), do: to_string(other)

  defp format_value(_key, true), do: ""
  defp format_value(_key, false), do: ""
  defp format_value(:asset_class, value), do: AssetClasses.label(value)
  defp format_value(:feed, value), do: Feeds.label(value)
  defp format_value(:latest_feed, value), do: Feeds.label(value)
  defp format_value(_key, value), do: to_string(value)

  # -- events ---------------------------------------------------------------

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    # `replace: true` — typing must not stack one history entry per keystroke.
    {:noreply,
     push_patch(socket,
       to: securities_path(socket.assigns, tab: :current, override: %{query: query}),
       replace: true
     )}
  end

  def handle_event("set_holding_status", %{"status" => status}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         securities_path(socket.assigns,
           tab: :current,
           override: %{holding_status: safe_holding_status(status)}
         )
     )}
  end

  def handle_event("set_changed_since", %{"preset" => preset}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         securities_path(socket.assigns,
           tab: :current,
           override: %{since: ChangedSince.toggle_value(socket.assigns.since, preset)}
         )
     )}
  end

  # #717 chip handlers. Each patches the URL — the chips are one-tap forms
  # of URL state, never socket-only state.
  def handle_event("set_dq_chip", %{"dq" => dq}, socket) do
    next = if socket.assigns.dq == dq, do: nil, else: safe_dq(dq)

    {:noreply,
     push_patch(socket,
       to: securities_path(socket.assigns, tab: :current, override: %{dq: next})
     )}
  end

  def handle_event("toggle_unclassified", _params, socket) do
    filters =
      if unclassified_active?(socket.assigns.filters) do
        Enum.reject(socket.assigns.filters, &unclassified_filter?/1)
      else
        socket.assigns.filters ++ [%{key: :asset_class, op: :is_nil, value: false}]
      end

    {:noreply,
     push_patch(socket,
       to: securities_path(socket.assigns, tab: :current, override: %{filters: filters})
     )}
  end

  def handle_event("toggle_chip_family", %{"family" => family, "option" => option}, socket)
      when family in ["cur", "class"] do
    key = String.to_existing_atom(family)
    active = Map.fetch!(socket.assigns, key)
    toggled = if option in active, do: List.delete(active, option), else: active ++ [option]

    {:noreply,
     push_patch(socket,
       to: securities_path(socket.assigns, tab: :current, override: %{key => toggled})
     )}
  end

  def handle_event("toggle_popover", %{"popover" => name}, socket) do
    case safe_atom(name) do
      nil ->
        {:noreply, socket}

      key ->
        next = if socket.assigns.open_popover == key, do: nil, else: key

        # The column picker offers classification columns (#565); refresh the
        # specs on open so trees created or deepened meanwhile are offerable.
        socket =
          if next == :columns do
            assign(socket, :classification_columns, Classifications.column_specs())
          else
            socket
          end

        {:noreply, assign(socket, :open_popover, next)}
    end
  end

  def handle_event("open_new", _params, socket) do
    {:noreply,
     socket
     |> assign(:dialog_open?, true)
     |> assign(:open_popover, nil)}
  end

  def handle_event("open_split_wizard", _params, socket) do
    {:noreply, assign(socket, :split_dialog_open?, true)}
  end

  def handle_event("sync_now", _params, socket) do
    parent = self()

    Task.start(fn ->
      result =
        try do
          QuoteSync.sync_all()
        rescue
          exception ->
            Logger.error(
              "QuoteSync.sync_all crashed: " <>
                Exception.format(:error, exception, __STACKTRACE__)
            )

            sync_crash_result(:crashed)
        catch
          kind, reason ->
            Logger.error("QuoteSync.sync_all exited: #{inspect({kind, reason})}")
            sync_crash_result(:exited)
        end

      send(parent, {:sync_done, result})
    end)

    # The sync button itself signals progress (spins + disabled via
    # `sync_running?`), so we no longer raise a sticky "Syncing…" toast on top.
    {:noreply,
     socket
     |> assign(:sync_running?, true)
     |> assign(:action_result, nil)}
  end

  def handle_event("toggle_detail_fullscreen", _params, socket) do
    {:noreply, update(socket, :detail_fullscreen?, &(!&1))}
  end

  def handle_event(
        "set_security_classification",
        %{"classification_id" => classification_id} = params,
        %{assigns: %{selected_security: %Security{id: id}}} = socket
      ) do
    case Integer.parse(classification_id) do
      {cid, ""} ->
        {:noreply, choose_security_category(socket, id, cid, params["category_id"])}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("set_security_classification", _params, socket), do: {:noreply, socket}

  def handle_event(
        "create_and_assign_category",
        %{"classification_id" => classification_id, "name" => name},
        %{assigns: %{selected_security: %Security{id: id}}} = socket
      ) do
    with {cid, ""} <- Integer.parse(classification_id),
         {:ok, category} <-
           Classifications.create_category(Actor.owner_ui(), %{
             "classification_id" => cid,
             "name" => name
           }),
         {:ok, _} <- Classifications.assign_security(Actor.owner_ui(), id, cid, category.id) do
      {:noreply,
       socket
       |> assign(:detail_new_category_for, nil)
       |> assign(:detail_classifications, load_security_classifications(id))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("create_and_assign_category", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_new_category", _params, socket) do
    {:noreply, assign(socket, :detail_new_category_for, nil)}
  end

  def handle_event("save_detail_note", %{"security" => %{"note" => note}}, socket) do
    case socket.assigns.selected_security do
      %Security{} = security ->
        case Catalog.update_security(Actor.owner_ui(), security, %{"note" => note}) do
          {:ok, updated} ->
            {:noreply,
             socket
             |> assign(:selected_security, updated)
             |> load_securities()
             |> put_action_result(:note, gettext("Notes saved."))}

          {:error, _changeset} ->
            {:noreply,
             socket
             |> put_action_result(:problem, gettext("Could not save notes."))}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("save_security_details", %{"security" => params}, socket) do
    case socket.assigns.selected_security do
      %Security{} = security ->
        case Catalog.update_security(Actor.owner_ui(), security, params) do
          {:ok, updated} ->
            {:noreply,
             socket
             |> assign(:selected_security, updated)
             |> load_detail_data()
             |> load_securities()
             |> put_action_result(:note, gettext("Security updated."))}

          {:error, _changeset} ->
            {:noreply,
             socket
             |> put_action_result(:problem, gettext("Could not save changes."))}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("quick_assign_asset_class", %{"asset_class" => ""}, socket),
    do: {:noreply, socket}

  def handle_event(
        "quick_assign_asset_class",
        %{"id" => id_str, "asset_class" => class},
        socket
      ) do
    with {id, ""} <- Integer.parse(to_string(id_str)),
         %Security{} = security <- Catalog.get_security(id),
         {:ok, _} <- Catalog.update_security(Actor.owner_ui(), security, %{asset_class: class}) do
      {:noreply,
       socket
       |> load_securities()
       |> put_action_result(:note, gettext("Asset class saved."))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("select_detail_tab", %{"tab" => tab}, socket) do
    tab = safe_tab(tab)

    case socket.assigns.selected_security do
      %Security{} = security ->
        {:noreply,
         socket
         |> assign(:detail_tab, tab)
         |> push_patch(to: securities_path(socket.assigns, id: security.id, tab: tab_param(tab)))}

      _ ->
        {:noreply, assign(socket, :detail_tab, tab)}
    end
  end

  def handle_event("set_detail_range", %{"range" => range}, socket) do
    if range in @ranges and socket.assigns.selected_security do
      {:noreply,
       socket
       |> assign(:detail_range, range)
       |> assign(:detail_custom_range, nil)
       |> assign(:detail_range_error, nil)
       |> load_detail_data()}
    else
      {:noreply, socket}
    end
  end

  # #721 (D5): a backwards or unparsable range is refused with the violation
  # on the field that can fix it (UX-DR13) — never silently ignored. The
  # shown range keeps.
  def handle_event(
        "set_detail_custom_range",
        %{"from" => from_str, "to" => to_str},
        socket
      ) do
    with %Security{} <- socket.assigns.selected_security,
         {:ok, from, to} <- parse_detail_range(from_str, to_str) do
      {:noreply,
       socket
       |> assign(:detail_custom_range, %{from: from, to: to})
       |> assign(:detail_range_error, nil)
       |> load_detail_data()}
    else
      {:error, field} -> {:noreply, assign(socket, :detail_range_error, field)}
      _no_selection -> {:noreply, socket}
    end
  end

  def handle_event("toggle_detail_percent_mode", _params, socket) do
    {:noreply, update(socket, :detail_percent_mode?, &(!&1))}
  end

  # Per-position bucket override (issue #446). "inherit" clears the override;
  # "empty" records the explicit-empty marker (deliberately no buckets); an
  # explicit set writes the chosen bucket ids.
  def handle_event("set_position_buckets", %{"depot_id" => depot_id} = params, socket) do
    security = socket.assigns.selected_security

    with %Security{} <- security,
         {depot_id, ""} <- Integer.parse(depot_id),
         depot when not is_nil(depot) <- Portfolios.get_securities_account(depot_id),
         {:ok, _} <- apply_position_override(depot, security, params) do
      {:noreply,
       socket
       |> put_action_result(:note, gettext("Position buckets saved"))
       |> load_detail_data()}
    else
      {:error, :bucket_ids} ->
        {:noreply,
         put_action_result(
           socket,
           :problem,
           gettext("That bucket no longer exists. Refresh and try again.")
         )}

      # ADR-0024 exclusive dimension (fix round): overrides are validated like
      # the account paths — at most one scope bucket per position.
      {:error, :exclusive_bucket_conflict} ->
        {:noreply,
         put_action_result(
           socket,
           :problem,
           gettext("A position can carry at most one scope bucket — pick one.")
         )}

      _ ->
        {:noreply,
         put_action_result(socket, :problem, gettext("Could not save position buckets"))}
    end
  end

  def handle_event("clear_detail_custom_range", _params, socket) do
    if socket.assigns.selected_security do
      {:noreply,
       socket
       |> assign(:detail_custom_range, nil)
       |> assign(:detail_range_error, nil)
       |> load_detail_data()}
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle_detail_ma", %{"window" => window_str}, socket) do
    case Integer.parse(window_str) do
      {window, ""} when window in [30, 50, 200] ->
        {:noreply, update(socket, :detail_ma, &Map.update!(&1, window, fn b -> !b end))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_detail_cost_basis", _params, socket) do
    {:noreply, update(socket, :detail_cost_basis?, &(!&1))}
  end

  def handle_event("toggle_detail_log", _params, socket) do
    {:noreply, update(socket, :detail_log_scale?, &(!&1))}
  end

  def handle_event("toggle_detail_transactions", _params, socket) do
    {:noreply, update(socket, :detail_show_transactions?, &(!&1))}
  end

  def handle_event("dismiss_result", _params, socket) do
    {:noreply, assign(socket, :action_result, nil)}
  end

  def handle_event("remove_filter", %{"idx" => idx}, socket) do
    idx = String.to_integer(idx)
    filters = List.delete_at(socket.assigns.filters, idx)

    {:noreply,
     push_patch(socket,
       to: securities_path(socket.assigns, tab: :current, override: %{filters: filters})
     )}
  end

  def handle_event("retry_missing_logos", _params, socket) do
    LogoDiscovery.enqueue_missing_security_logos()

    # Feedback rides the canonical inline-result slot (design-critic fix
    # round): data-note appearance and dismissal instead of a bare span.
    {:noreply,
     socket
     |> assign(:logo_retry_queued?, true)
     |> put_action_result(
       :note,
       gettext("Logo lookup queued for all securities without a logo.")
     )}
  end

  def handle_event("remove_dq", _params, socket) do
    {:noreply,
     push_patch(socket,
       to: securities_path(socket.assigns, tab: :current, override: %{dq: nil})
     )}
  end

  def handle_event("toggle_sort", %{"key" => key}, socket) do
    case safe_column_key(key, socket.assigns.classification_columns) do
      nil ->
        {:noreply, socket}

      column_key ->
        sort =
          case socket.assigns.sort do
            {^column_key, :asc} -> {column_key, :desc}
            {^column_key, :desc} -> {:name, :asc}
            _ -> {column_key, :asc}
          end

        {:noreply, socket |> assign(:sort, sort) |> load_securities()}
    end
  end

  def handle_event("set_columns", %{"columns" => columns}, socket) when is_list(columns) do
    visible =
      columns
      |> Enum.map(&safe_column_key(&1, socket.assigns.classification_columns))
      |> Enum.reject(&is_nil/1)

    visible = if visible == [], do: SecurityFields.visible_default(), else: visible

    {:noreply, socket |> assign(:visible_columns, visible) |> load_securities()}
  end

  def handle_event("set_columns", _params, socket), do: {:noreply, socket}

  def handle_event("open_row_menu", %{"id" => id_str}, socket) do
    with {id, ""} <- Integer.parse(to_string(id_str)),
         row when not is_nil(row) <-
           Enum.find(socket.assigns.securities, &(security_id(&1) == id)) do
      {:noreply, assign(socket, :row_menu_id, id)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("close_row_menu", _params, socket) do
    {:noreply, assign(socket, :row_menu_id, nil)}
  end

  def handle_event("close_delete_blocked", _params, socket) do
    {:noreply, assign(socket, :delete_blocked, nil)}
  end

  def handle_event("close_logo_dialog", _params, socket) do
    {:noreply, assign(socket, :logo_dialog_security, nil)}
  end

  def handle_event("save_logo_url", %{"logo" => %{"url" => url}}, socket) do
    case socket.assigns.logo_dialog_security do
      %Security{} = sec -> store_logo_url(socket, sec, String.trim(to_string(url)))
      _ -> {:noreply, socket}
    end
  end

  def handle_event("remove_logo_override", %{"id" => id_str}, socket) do
    with {id, ""} <- Integer.parse(to_string(id_str)),
         %Security{} = sec <- Catalog.get_security(id),
         {:ok, _updated} <- Catalog.remove_logo(sec, logo_opts()) do
      {:noreply,
       socket
       |> assign(:logo_dialog_security, nil)
       |> put_action_result(:note, gettext("Logo removed"))
       |> load_securities()
       |> load_detail_data()}
    else
      _ ->
        {:noreply,
         socket
         |> put_action_result(:problem, gettext("Could not remove logo"))}
    end
  end

  def handle_event("row_action", %{"action" => action, "id" => id_str}, socket) do
    with {id, ""} <- Integer.parse(to_string(id_str)),
         %Security{} = sec <- Catalog.get_security(id) do
      socket
      |> assign(:row_menu_id, nil)
      |> dispatch_row_action(action, sec)
    else
      _ -> {:noreply, assign(socket, :row_menu_id, nil)}
    end
  end

  defp dispatch_row_action(socket, "edit", %Security{} = sec) do
    {:noreply,
     socket
     |> assign(:editing_security, sec)
     |> assign(:dialog_open?, true)
     |> assign(:delete_blocked, nil)}
  end

  defp dispatch_row_action(socket, "sync", %Security{} = sec) do
    parent = self()

    Task.start(fn ->
      result =
        try do
          QuoteSync.sync_security(sec)
        rescue
          exception ->
            Logger.error(
              "QuoteSync.sync_security crashed for ##{sec.id}: " <>
                Exception.format(:error, exception, __STACKTRACE__)
            )

            %{status: :error, reason: :crashed}
        catch
          kind, reason ->
            Logger.error(
              "QuoteSync.sync_security exited for ##{sec.id}: #{inspect({kind, reason})}"
            )

            %{status: :error, reason: :exited}
        end

      send(parent, {:sync_done, result})
    end)

    # Progress is shown by the busy sync button (`sync_running?`); no toast.
    {:noreply,
     socket
     |> assign(:sync_running?, true)
     |> assign(:action_result, nil)}
  end

  defp dispatch_row_action(socket, "retire", %Security{} = sec) do
    case Catalog.update_security(Actor.owner_ui(), sec, %{is_retired: !sec.is_retired}) do
      {:ok, _updated} ->
        flash =
          if sec.is_retired,
            do: gettext("Reactivated %{name}", name: sec.name),
            else: gettext("Retired %{name}", name: sec.name)

        {:noreply,
         socket
         |> put_action_result(:note, flash)
         |> assign(:delete_blocked, nil)
         |> load_securities()}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_action_result(:problem, gettext("Could not change status."))}
    end
  end

  defp dispatch_row_action(socket, "open", %Security{} = sec) do
    {:noreply, push_patch(socket, to: securities_path(socket.assigns, id: sec.id))}
  end

  defp dispatch_row_action(socket, "copy_isin", %Security{isin: isin})
       when is_binary(isin) and isin != "" do
    {:noreply,
     socket
     |> push_event("copy-to-clipboard", %{text: isin})
     |> put_action_result(:note, gettext("ISIN copied"))}
  end

  defp dispatch_row_action(socket, "copy_isin", _sec), do: {:noreply, socket}

  defp dispatch_row_action(socket, "copy_ticker", %Security{ticker_symbol: t})
       when is_binary(t) and t != "" do
    {:noreply,
     socket
     |> push_event("copy-to-clipboard", %{text: t})
     |> put_action_result(:note, gettext("Ticker copied"))}
  end

  defp dispatch_row_action(socket, "copy_ticker", _sec), do: {:noreply, socket}

  defp dispatch_row_action(socket, "delete", %Security{} = sec) do
    case Catalog.delete_security(Actor.owner_ui(), sec) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_action_result(:note, gettext("Deleted %{name}", name: sec.name))
         |> assign(:delete_blocked, nil)
         |> load_securities()}

      {:error, _changeset} ->
        {:noreply, assign(socket, :delete_blocked, sec)}
    end
  end

  # Re-trigger protection (#566): while a lookup is running (busy state in the
  # inline-result slot) a second trigger is a no-op; the result of the running
  # lookup re-arms the action.
  defp dispatch_row_action(socket, "update_logo", %Security{} = sec) do
    if match?({:busy, _}, socket.assigns.action_result) do
      {:noreply, socket}
    else
      parent = self()
      sec_id = sec.id

      Task.Supervisor.start_child(Portfolixir.LogoSupervisor, fn ->
        result = LogoLookup.run(sec)
        send(parent, {:logo_update_done, sec_id, result})
      end)

      {:noreply, assign(socket, :action_result, {:busy, gettext("Looking up logo…")})}
    end
  end

  defp dispatch_row_action(socket, "manage_logo", %Security{} = sec) do
    {:noreply, assign(socket, :logo_dialog_security, sec)}
  end

  defp dispatch_row_action(socket, _action, _sec), do: {:noreply, socket}

  defp refresh_logo_dialog(socket) do
    case socket.assigns[:logo_dialog_security] do
      %Security{id: id} -> assign(socket, :logo_dialog_security, Catalog.get_security(id))
      _ -> socket
    end
  end

  # Patch a single security's logo into the current view after a PubSub
  # broadcast. Loads the fresh row only when the id is actually on screen
  # (in the list, selected, or open in the logo dialog) to avoid a needless
  # query for every drained logo of securities the user is not looking at.
  defp apply_logo_update(socket, id) do
    in_list? = Enum.any?(socket.assigns.securities, &(security_id(&1) == id))
    selected? = match?(%Security{id: ^id}, socket.assigns.selected_security)
    in_dialog? = match?(%Security{id: ^id}, socket.assigns[:logo_dialog_security])

    if in_list? or selected? or in_dialog? do
      case Catalog.get_security(id) do
        %Security{} = fresh ->
          patch_logo_into_view(socket, fresh, in_list?, selected?, in_dialog?)

        nil ->
          socket
      end
    else
      socket
    end
  end

  defp patch_logo_into_view(socket, %Security{} = fresh, in_list?, selected?, in_dialog?) do
    socket
    |> then(fn s -> if in_list?, do: replace_row_attributes(s, fresh), else: s end)
    |> then(fn s -> if selected?, do: assign(s, :selected_security, fresh), else: s end)
    |> then(fn s -> if in_dialog?, do: assign(s, :logo_dialog_security, fresh), else: s end)
  end

  # Only the logo lives in `attributes`; swap that in so the row keeps its
  # already-computed metrics instead of triggering a full re-query.
  defp replace_row_attributes(socket, %Security{id: id, attributes: attributes}) do
    securities =
      Enum.map(socket.assigns.securities, fn row ->
        if security_id(row) == id, do: put_row_attributes(row, attributes), else: row
      end)

    assign(socket, :securities, securities)
  end

  defp put_row_attributes(%SecurityWithMetrics{security: security} = row, attributes) do
    %{row | security: %{security | attributes: attributes}}
  end

  defp put_row_attributes(%Security{} = security, attributes) do
    %{security | attributes: attributes}
  end

  defp store_logo_url(socket, _sec, "") do
    {:noreply,
     socket
     |> put_action_result(:problem, gettext("Enter an image URL first."))}
  end

  defp store_logo_url(socket, sec, url) do
    {kind, flash} =
      case Catalog.set_logo_override(sec, url, logo_opts()) do
        {:ok, _updated} -> {:note, gettext("Logo updated")}
        {:error, _reason} -> {:problem, gettext("Could not load that image")}
      end

    {:noreply,
     socket
     |> assign(:logo_dialog_security, nil)
     |> put_action_result(kind, flash)
     |> load_securities()
     |> load_detail_data()}
  end

  # Manual logo operations reuse the same storage dir (and, in tests, the same
  # Req stub) the background discovery worker is configured with.
  defp logo_opts, do: Application.get_env(:portfolixir, :logo_discovery_opts, [])

  # URL params arrive in whatever shape the caller crafted (?q[]=foo is a
  # list); a non-binary q drops to the empty query like every other guarded
  # param instead of crashing the shared link (review finding).
  defp safe_query(q) when is_binary(q), do: q
  defp safe_query(_), do: ""

  # Both call sites guard `is_binary` themselves, so no catch-all clause:
  # Dialyzer proved one unreachable (pattern_match_cov).
  defp safe_column_atom(key) when is_binary(key) do
    field = Enum.find(SecurityFields.all(), &(Atom.to_string(&1.key) == key))
    field && field.key
  end

  defp safe_holding_status(status) when status in @holding_statuses, do: status
  defp safe_holding_status(_), do: @default_holding_status

  defp safe_atom(string) when is_binary(string) do
    String.to_existing_atom(string)
  rescue
    ArgumentError -> nil
  end

  # -- messages from child components --------------------------------------

  # The picker sends raw column-key strings; validation against the field
  # registry and the current classification specs happens here (#565).
  @impl true
  def handle_info({:columns_changed, column_strings}, socket) do
    columns =
      column_strings
      |> Enum.map(&safe_column_key(&1, socket.assigns.classification_columns))
      |> Enum.reject(&is_nil/1)

    columns = if columns == [], do: SecurityFields.visible_default(), else: columns
    column_strs = Enum.map(columns, &column_key_string/1)

    {:noreply,
     socket
     |> assign(:visible_columns, columns)
     |> load_securities()
     |> push_event("column-prefs-changed", %{key: "securities.columns", columns: column_strs})}
  end

  def handle_info({:dq_selected, dq}, socket) do
    {:noreply,
     socket
     |> assign(:open_popover, nil)
     |> push_patch(to: securities_path(socket.assigns, tab: :current, override: %{dq: dq}))}
  end

  def handle_info({:filter_added, filter}, socket) do
    filters = socket.assigns.filters ++ [filter]

    {:noreply,
     socket
     |> assign(:open_popover, nil)
     |> push_patch(
       to: securities_path(socket.assigns, tab: :current, override: %{filters: filters})
     )}
  end

  def handle_info({:dialog, "split-wizard-dialog", :close}, socket) do
    {:noreply, assign(socket, :split_dialog_open?, false)}
  end

  # A booked split changes holdings, chart basis and the transactions list —
  # reload the whole detail pane from the ledger (single source of truth).
  def handle_info({:dialog, "split-wizard-dialog", {:split_booked, count}}, socket) do
    {:noreply,
     socket
     |> assign(:split_dialog_open?, false)
     |> put_action_result(
       :note,
       ngettext("Split booked for one portfolio.", "Split booked for %{count} portfolios.", count)
     )
     |> load_detail_data()}
  end

  def handle_info({:dialog, _id, :close}, socket) do
    {:noreply,
     socket
     |> assign(:dialog_open?, false)
     |> assign(:editing_security, nil)}
  end

  def handle_info({:dialog, _id, {:created, security}}, socket) do
    {:noreply,
     socket
     |> assign(:dialog_open?, false)
     |> assign(:editing_security, nil)
     |> put_action_result(:note, gettext("Created %{name}", name: security.name))
     |> load_securities()}
  end

  def handle_info({:dialog, _id, {:updated, security}}, socket) do
    {:noreply,
     socket
     |> assign(:dialog_open?, false)
     |> assign(:editing_security, nil)
     |> put_action_result(:note, gettext("Updated %{name}", name: security.name))
     |> load_securities()}
  end

  def handle_info({:dialog, _id, {:open_existing, _security}}, socket) do
    {:noreply,
     socket
     |> assign(:dialog_open?, false)
     |> assign(:editing_security, nil)}
  end

  def handle_info({:logo_update_done, _sec_id, result}, socket) do
    {kind, flash} =
      case result do
        {:ok, _security} -> {:note, gettext("Logo updated")}
        :skip -> {:note, gettext("No logo source available")}
        {:error, _reason} -> {:problem, gettext("Logo lookup failed")}
      end

    {:noreply,
     socket
     |> put_action_result(kind, flash)
     |> notify_os(gettext("Logo lookup complete"), flash, "logo-lookup")
     |> refresh_logo_dialog()
     |> load_securities()
     |> load_detail_data()}
  end

  # Broadcast from LogoStore when a logo was stored/replaced/removed (manual
  # action elsewhere, or the background discovery queue). Patch only the
  # affected row/selection in place so a bulk import draining hundreds of
  # logos does not re-run the whole metrics query on every tick.
  def handle_info({:security_logo_updated, id}, socket) do
    {:noreply, apply_logo_update(socket, id)}
  end

  def handle_info(:sync_done, socket) do
    handle_info({:sync_done, {:ok, %{ok: 0, skipped: 0, error: 0}}}, socket)
  end

  def handle_info({:sync_done, result}, socket) do
    summary = sync_flash(result)

    {:noreply,
     socket
     |> assign(:sync_running?, false)
     |> put_action_result(:note, summary)
     |> notify_os(gettext("Price sync complete"), summary, "price-sync")
     |> load_securities()
     |> load_detail_data()}
  end

  defp select_security(socket, %Security{} = security) do
    socket
    |> assign(:selected_security, security)
    |> load_detail_data()
  end

  defp clear_selection(socket) do
    socket
    |> assign(:selected_security, nil)
    |> assign(:detail_fullscreen?, false)
    |> assign(:detail_quotes, [])
    |> assign(:detail_series_basis, :empty)
    |> assign(:detail_split_events, [])
    |> assign(:detail_transactions, [])
    |> assign(:detail_transaction_rows, [])
    |> assign(:detail_trades, %{open_lots: [], closed_trades: [], orphan_sells: []})
    |> assign(:detail_holdings, [])
    |> assign(:detail_latest, nil)
    |> assign(:detail_metrics, SecurityWithMetrics.empty_metrics())
    |> assign(:detail_status, nil)
    |> assign(:detail_classifications, [])
    |> assign(:detail_new_category_for, nil)
  end

  defp load_detail_data(%{assigns: %{selected_security: nil}} = socket), do: socket

  defp load_detail_data(socket) do
    %Security{id: id} = socket.assigns.selected_security

    {from, to} =
      case socket.assigns[:detail_custom_range] do
        %{from: from, to: to} -> {from, to}
        _ -> range_to_dates(socket.assigns.detail_range, id)
      end

    # Display-basis series (ADR-0028 §2): raw rows divided by later split
    # ratios, provider mirrors untouched; each row keeps `stored_close`
    # reachable and the series basis is stated next to chart and table
    # (UX-DR10/11).
    quotes = Quotes.adjusted_range(id, from, to)

    # Security-level split events (deduplicated across the per-portfolio
    # fan-out): the cost-basis overlay and the basis hint both key off them
    # (E17 review, findings 1 and 11).
    split_events = Quotes.split_events(id)

    transaction_rows =
      id
      |> Ledger.list_transactions_for_security()

    transactions =
      Enum.map(
        transaction_rows,
        &%{date: &1.date, type: &1.type, price: &1.price, quantity: &1.quantity}
      )

    metrics =
      case Quotes.attach_metrics([socket.assigns.selected_security]) do
        [%SecurityWithMetrics{metrics: m}] -> m
        _ -> SecurityWithMetrics.empty_metrics()
      end

    holdings = decorate_holdings_with_buckets(Ledger.holdings_for_security(id), id)

    socket
    |> assign(:detail_quotes, quotes)
    |> assign(:detail_split_events, split_events)
    |> assign(:detail_transactions, transactions)
    |> assign(:detail_transaction_rows, transaction_rows)
    |> assign(:detail_trades, Ledger.list_trades_for_security(id))
    |> assign(:detail_holdings, holdings)
    |> assign(:buckets, Buckets.list_buckets())
    # Display basis (ADR-0028 §2): a stale raw close from before a split's
    # effective date is shown divided by the cumulative later ratio.
    |> assign(:detail_latest, Quotes.adjusted_latest(id))
    |> assign(:detail_series_basis, QuoteAdjustment.series_basis(quotes))
    |> assign(:detail_metrics, metrics)
    # The shared price-resolution status (#406): computed by the valuation's
    # own semantics, against the base currencies of the portfolios actually
    # holding the security, so this pane and those portfolios' totals cannot
    # disagree (review fix: a USD-base portfolio counts a USD position
    # without any stored rate).
    |> assign(:detail_status, Valuation.security_status(id, holding_base_currencies(holdings)))
    |> assign(:detail_classifications, load_security_classifications(id))
  end

  defp holding_base_currencies(holdings) do
    holdings
    |> Enum.map(& &1.portfolio.base_currency_code)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  # UX-DR11 basis labels for the chart and its chart-as-table. Without any
  # booked split event nothing is (or could be) adjusted — the hint says
  # "as recorded" instead of claiming a split adjustment (E17 review,
  # finding 11).
  defp series_basis_label(:empty, _split_events), do: nil
  defp series_basis_label(_basis, []), do: gettext("as recorded")
  defp series_basis_label(:raw, _split_events), do: gettext("split-adjusted")
  defp series_basis_label(:provider_mirror, _split_events), do: gettext("provider-adjusted")

  defp series_basis_label(:mixed, _split_events),
    do: gettext("mixed (split-adjusted and provider-adjusted rows)")

  # Joins each holding row's per-position bucket override state and its depot's
  # default set, so the holdings tab can present inherit / explicit-empty /
  # explicit list distinctly (issue #446).
  defp decorate_holdings_with_buckets(holdings, security_id) do
    Enum.map(holdings, fn h ->
      case h.depot do
        %{id: depot_id} ->
          override = Buckets.position_override(depot_id, security_id)

          explicit =
            case override do
              {:explicit, ids} -> ids
              _ -> []
            end

          h
          |> Map.put(:override, override)
          |> Map.put(:explicit_bucket_ids, explicit)
          |> Map.put(:depot_default_bucket_ids, Buckets.depot_default_bucket_ids(depot_id))

        _ ->
          h
          |> Map.put(:override, :inherit)
          |> Map.put(:explicit_bucket_ids, [])
          |> Map.put(:depot_default_bucket_ids, [])
      end
    end)
  end

  # Routes the chosen override mode to the right Buckets write. The empty/list
  # split is what keeps explicit-empty distinct from inherit (ADR-0018).
  defp apply_position_override(depot, security, %{"mode" => "inherit"}) do
    case Buckets.clear_position_override(Actor.owner_ui(), depot, security) do
      :ok -> {:ok, :inherit}
      other -> other
    end
  end

  defp apply_position_override(depot, security, %{"mode" => "empty"}) do
    case Buckets.set_position_override(Actor.owner_ui(), depot, security, []) do
      :ok -> {:ok, :empty}
      other -> other
    end
  end

  defp apply_position_override(depot, security, params) do
    ids =
      params
      |> Map.get("bucket_ids", [])
      |> List.wrap()
      |> Enum.flat_map(fn value ->
        case Integer.parse(to_string(value)) do
          {id, ""} -> [id]
          _ -> []
        end
      end)

    case Buckets.set_position_override(Actor.owner_ui(), depot, security, ids) do
      :ok -> {:ok, :explicit}
      other -> other
    end
  end

  defp put_action_result(socket, severity, message) do
    assign(socket, :action_result, {severity, message})
  end

  defp override_state_label(:inherit), do: gettext("inherited from depot")
  defp override_state_label(:explicit_empty), do: gettext("no buckets (excluded)")
  defp override_state_label({:explicit, _ids}), do: gettext("specific buckets")

  defp bucket_names([], _buckets), do: gettext("none")

  defp bucket_names(bucket_ids, buckets) do
    names =
      buckets
      |> Enum.filter(&(&1.id in bucket_ids))
      |> Enum.map_join(", ", & &1.name)

    if names == "", do: gettext("none"), else: names
  end

  defp load_security_classifications(security_id) do
    Classifications.list_trees()
    |> Enum.map(fn tree ->
      selected =
        Enum.find_value(tree.assignments, fn assignment ->
          assignment.security_id == security_id && assignment.category_id
        end)

      %{
        classification: tree.classification,
        editable: not tree.classification.built_in,
        categories: flat_categories(tree.categories),
        selected_category_id: selected
      }
    end)
  end

  defp flat_categories(categories) do
    grouped = Enum.group_by(categories, & &1.parent_id)
    flat_categories_level(grouped, nil, 0)
  end

  defp flat_categories_level(grouped, parent_id, depth) do
    grouped
    |> Map.get(parent_id, [])
    |> Enum.flat_map(fn category ->
      [{category, depth} | flat_categories_level(grouped, category.id, depth + 1)]
    end)
  end

  defp choose_security_category(socket, security_id, classification_id, "__new__") do
    socket
    |> assign(:detail_new_category_for, classification_id)
    |> assign(:detail_classifications, load_security_classifications(security_id))
  end

  defp choose_security_category(socket, security_id, classification_id, category_id) do
    apply_classification_change(security_id, classification_id, category_id)

    socket
    |> assign(:detail_new_category_for, nil)
    |> assign(:detail_classifications, load_security_classifications(security_id))
  end

  defp apply_classification_change(security_id, classification_id, category_id)
       when category_id in [nil, ""] do
    Classifications.unassign_security(Actor.owner_ui(), security_id, classification_id)
  end

  defp apply_classification_change(security_id, classification_id, category_id) do
    case Integer.parse(category_id) do
      {category, ""} ->
        Classifications.assign_security(
          Actor.owner_ui(),
          security_id,
          classification_id,
          category
        )

      _ ->
        {:error, :invalid}
    end
  end

  defp range_to_dates(range, security_id) do
    today = Date.utc_today()

    case range do
      "1M" -> {Date.add(today, -30), today}
      "3M" -> {Date.add(today, -90), today}
      "6M" -> {Date.add(today, -180), today}
      "YTD" -> {Date.new!(today.year, 1, 1), today}
      "1Y" -> {Date.add(today, -365), today}
      "3Y" -> {Date.add(today, -3 * 365), today}
      "5Y" -> {Date.add(today, -5 * 365), today}
      "MAX" -> {oldest_date(security_id) || today, today}
      _ -> {Date.add(today, -365), today}
    end
  end

  defp sync_crash_result(reason) do
    {:ok,
     %{
       ok: 0,
       skipped: 0,
       error: 1,
       results: [%{status: :error, reason: reason}]
     }}
  end

  # Fires a browser/OS notification for a completed background action. The
  # client only surfaces it while the tab is in the background (see
  # `Portfolixir.osNotify`), so it never duplicates the on-page feedback.
  defp notify_os(socket, title, body, tag) do
    push_event(socket, "os-notify", %{title: title, body: body, tag: tag})
  end

  defp sync_flash({:ok, %{ok: ok, skipped: 0, error: 0}}) when ok > 0 do
    gettext("Prices synced.")
  end

  defp sync_flash({:ok, %{ok: ok, skipped: skipped, error: error}}) do
    gettext("Price sync finished: %{ok} synced, %{skipped} skipped, %{error} failed.",
      ok: ok,
      skipped: skipped,
      error: error
    )
  end

  defp sync_flash(%{status: :ok}), do: gettext("Prices synced.")

  defp sync_flash(%{status: :skipped, reason: reason}) do
    gettext("Price sync skipped: %{reason}", reason: sync_reason(reason))
  end

  defp sync_flash(%{status: :error, reason: reason}) do
    gettext("Price sync failed: %{reason}", reason: sync_reason(reason))
  end

  defp sync_flash(_), do: gettext("Price sync failed.")

  defp sync_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp sync_reason(reason), do: inspect(reason)

  defp oldest_date(security_id) do
    case Quotes.range(security_id, ~D[1900-01-01], Date.utc_today()) do
      [] -> nil
      [first | _] -> first.date
    end
  end

  defp ranges, do: @ranges

  defp load_securities(socket) do
    dq = socket.assigns.dq

    opts = [
      query: socket.assigns.query,
      holding_status: socket.assigns.holding_status,
      filters: socket.assigns.filters,
      sort: catalog_sort(socket.assigns.sort),
      # #717: the currency chip family — OR within the family, in the query.
      currencies: socket.assigns.cur,
      # #731: the same `updated_at > cut` query the API's `?since=` runs —
      # one semantics, two surfaces. nil passes straight through.
      updated_since: socket.assigns.since && socket.assigns.since.cut
    ]

    opts = if dq == "missing_logo", do: Keyword.put(opts, :logo_status, :missing), else: opts

    securities =
      opts
      |> Catalog.list_securities_with_metrics()
      # The metric-derived half runs post-enrichment; the query half is already
      # in `opts` above (#705). `safe_dq/1` has already reduced anything
      # unrecognised to nil, which `refine/3` passes straight through. One rule
      # with the dashboard's count, so a count of N links to a list of N by
      # construction rather than by agreement.
      |> DataQuality.refine(dq)
      # #717: the class chips filter on the EFFECTIVE class — the same value
      # the list displays — while the Unclassified chip stays a stored-column
      # filter (#700). In memory because the effective class is derived.
      |> refine_by_class(socket.assigns.class)

    socket
    |> assign(:securities, securities)
    |> assign(:chip_currencies, Catalog.currencies_in_use())
    |> assign(:chip_classes, Catalog.effective_asset_classes_in_use())
    |> attach_classification_columns()
    |> apply_classification_sort()
  end

  defp refine_by_class(rows, []), do: rows

  defp refine_by_class(rows, classes) do
    Enum.filter(rows, fn row ->
      Security.effective_asset_class(security_from_row(row)) in classes
    end)
  end

  # Classification columns (#565) are resolved outside the catalog query: the
  # catalog falls back to its default sort and the rows are sorted here once
  # the per-level category names are attached.
  defp catalog_sort({{:classification, _id, _level}, _dir}), do: {:name, :asc}
  defp catalog_sort(sort), do: sort

  # Attaches the per-level category name of every visible classification
  # column (plus a classification sort key) into each row's metrics map, so
  # the shared field/value plumbing renders and sorts them like metrics.
  defp attach_classification_columns(socket) do
    case classification_column_keys(socket) do
      [] ->
        socket

      keys ->
        rows = socket.assigns.securities
        securities = Enum.map(rows, &security_from_row/1)

        value_maps =
          Map.new(keys, fn {:classification, id, level} = key ->
            case Classifications.security_level_names(id, level, securities) do
              {:ok, names} -> {key, names}
              {:error, _} -> {key, %{}}
            end
          end)

        rows =
          Enum.map(rows, fn row ->
            sec_id = security_id(row)

            Enum.reduce(value_maps, row, fn {key, names}, acc ->
              put_row_metric(acc, key, Map.get(names, sec_id))
            end)
          end)

        assign(socket, :securities, rows)
    end
  end

  defp classification_column_keys(socket) do
    sort_key =
      case socket.assigns.sort do
        {{:classification, _, _} = key, _dir} -> [key]
        _ -> []
      end

    socket.assigns.visible_columns
    |> Enum.filter(&match?({:classification, _, _}, &1))
    |> Kernel.++(sort_key)
    |> Enum.uniq()
  end

  defp put_row_metric(%SecurityWithMetrics{metrics: metrics} = row, key, value) do
    %{row | metrics: Map.put(metrics, key, value)}
  end

  defp put_row_metric(row, _key, _value), do: row

  defp apply_classification_sort(socket) do
    case socket.assigns.sort do
      {{:classification, _, _} = key, dir} ->
        rows =
          Enum.sort_by(
            socket.assigns.securities,
            &row_metric(&1, key),
            name_comparator(dir)
          )

        assign(socket, :securities, rows)

      _ ->
        socket
    end
  end

  defp row_metric(%SecurityWithMetrics{metrics: metrics}, key), do: Map.get(metrics, key)
  defp row_metric(_row, _key), do: nil

  # Rows without a category on the sorted level stay last in both directions.
  defp name_comparator(:asc) do
    fn
      nil, nil -> true
      nil, _b -> false
      _a, nil -> true
      a, b -> a <= b
    end
  end

  defp name_comparator(:desc) do
    fn
      nil, nil -> true
      nil, _b -> false
      _a, nil -> true
      a, b -> a >= b
    end
  end

  defp parse_detail_range(from_str, to_str) do
    with {:from, {:ok, from}} <- {:from, Date.from_iso8601(to_string(from_str))},
         {:to, {:ok, to}} <- {:to, Date.from_iso8601(to_string(to_str))},
         {:order, false} <- {:order, Date.compare(from, to) == :gt} do
      {:ok, from, to}
    else
      {:from, _} -> {:error, :from}
      {:to, _} -> {:error, :to}
      {:order, _} -> {:error, :order}
    end
  end

  defp detail_range_error_message(:order),
    do: gettext("The end date is before the start date.")

  defp detail_range_error_message(_field),
    do: gettext("Not a date — use YYYY-MM-DD.")

  defp dq_label("stale_quote"),
    do: gettext("No quote in %{days} days", days: DataQuality.stale_days())

  defp dq_label("missing_quote"), do: gettext("No quote at all")
  defp dq_label("missing_logo"), do: gettext("No logo")
  defp dq_label("missing_fx"), do: gettext("Missing FX rate")

  # -- #717 chip helpers ------------------------------------------------------

  # The chip row's data-quality trio, with the spec's short chip names
  # (missing_logo stays a builder condition — it has its own overview entry
  # and is not in the fixed chip set).
  defp dq_chip_options do
    [
      {"stale_quote", gettext("Stale quote")},
      {"missing_quote", gettext("No price")},
      {"missing_fx", gettext("Missing FX")}
    ]
  end

  defp unclassified_filter?(%{key: :asset_class, op: :is_nil}), do: true
  defp unclassified_filter?(_filter), do: false

  defp unclassified_active?(filters), do: Enum.any?(filters, &unclassified_filter?/1)

  # A condition a one-tap chip expresses; everything else is the builder's,
  # and is what the "More filters" count counts.
  defp chip_expressible?(filter), do: unclassified_filter?(filter)

  defp builder_filter_count(filters), do: Enum.count(filters, &(not chip_expressible?(&1)))

  # A dq id without a one-tap chip (missing_logo) keeps the removable-chip
  # form and counts toward "More filters" — demotion never hides state.
  defp removable_dq?(dq), do: dq != nil and dq not in ~w(stale_quote missing_quote missing_fx)

  defp more_filters_count(filters, dq),
    do: builder_filter_count(filters) + if(removable_dq?(dq), do: 1, else: 0)
end
