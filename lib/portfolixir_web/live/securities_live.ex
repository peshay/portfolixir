defmodule PortfolixirWeb.SecuritiesLive do
  use PortfolixirWeb, :live_view

  require Logger

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.AssetClasses
  alias Portfolixir.Catalog.Feeds
  alias Portfolixir.Catalog.LogoLookup
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Catalog.QuoteSync
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Catalog.SecurityFields
  alias Portfolixir.Catalog.SecurityFields.Field
  alias Portfolixir.Catalog.SecurityWithMetrics
  alias Portfolixir.Classifications
  alias Portfolixir.Ledger
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Components.SecurityChart
  alias PortfolixirWeb.Securities.ColumnPicker
  alias PortfolixirWeb.Securities.FilterPopover
  alias PortfolixirWeb.Securities.LogoOverrideDialog
  alias PortfolixirWeb.Securities.RowContextMenu
  alias PortfolixirWeb.Securities.SecurityFormDialog

  @ranges ~w(1M 3M 6M YTD 1Y 3Y 5Y MAX)
  @default_range "1Y"

  @tabs ~w(overview chart transactions trades quotes holdings classifications)
  @default_tab "overview"
  @holding_statuses ~w(all held not_held)
  @default_holding_status "all"

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:query, "")
     |> assign(:holding_status, @default_holding_status)
     |> assign(:filters, [])
     |> assign(:sort, {:name, :asc})
     |> assign(:visible_columns, SecurityFields.visible_default())
     |> assign(:open_popover, nil)
     |> assign(:dialog_open?, false)
     |> assign(:flash_message, nil)
     |> assign(:sync_running?, false)
     |> assign(:selected_security, nil)
     |> assign(:detail_tab, @default_tab)
     |> assign(:detail_fullscreen?, false)
     |> assign(:detail_range, @default_range)
     |> assign(:detail_custom_range, nil)
     |> assign(:detail_percent_mode?, false)
     |> assign(:detail_log_scale?, false)
     |> assign(:detail_show_transactions?, true)
     |> assign(:detail_ma, %{30 => false, 50 => false, 200 => false})
     |> assign(:detail_cost_basis?, false)
     |> assign(:detail_quotes, [])
     |> assign(:detail_transactions, [])
     |> assign(:detail_transaction_rows, [])
     |> assign(:detail_trades, %{open_lots: [], closed_trades: [], orphan_sells: []})
     |> assign(:detail_holdings, [])
     |> assign(:detail_latest, nil)
     |> assign(:detail_metrics, SecurityWithMetrics.empty_metrics())
     |> assign(:detail_classifications, [])
     |> assign(:detail_new_category_for, nil)
     |> assign(:row_menu_id, nil)
     |> assign(:editing_security, nil)
     |> assign(:delete_blocked, nil)
     |> assign(:logo_dialog_security, nil)
     |> load_securities()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = safe_tab(params["tab"])

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

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell
      current_path="/securities"
      page_title={gettext("Securities")}
      page_subtitle={gettext("Search, filter and curate your investable universe.")}
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

          <div
            id="holding-status-filter"
            class="segmented-control"
            role="group"
            aria-label={gettext("Holding status")}
          >
            <%= for {status, label} <- holding_status_options() do %>
              <button
                type="button"
                class={["segmented-control__option", @holding_status == status && "is-active"]}
                phx-click="set_holding_status"
                phx-value-status={status}
                aria-pressed={@holding_status == status}
              >
                <%= label %>
              </button>
            <% end %>
          </div>

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
              aria-label={gettext("Sync prices")}
              title={gettext("Sync prices")}
              disabled={@sync_running?}
            >
              <AppShell.icon name={:refresh_cw} />
            </button>

            <button
              type="button"
              id="toggle-filter-popover"
              class={["icon-button", @open_popover == :filter && "is-active"]}
              phx-click="toggle_popover"
              phx-value-popover="filter"
              aria-label={gettext("Filter")}
              aria-expanded={@open_popover == :filter}
              title={gettext("Filter")}
            >
              <AppShell.icon name={:filter} />
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
              <%= if @open_popover == :filter do %>
                <.live_component
                  module={FilterPopover}
                  id="filter-popover"
                />
              <% end %>
              <%= if @open_popover == :columns do %>
                <.live_component
                  module={ColumnPicker}
                  id="column-picker"
                  visible={@visible_columns}
                />
              <% end %>
            </div>
          </div>
        </div>

        <%= if @filters != [] do %>
          <ul class="filter-chips" id="filter-chips" aria-label={gettext("Active filters")}>
            <%= for {filter, idx} <- Enum.with_index(@filters) do %>
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

        <%= if @flash_message do %>
          <p class="alert-success" role="status" id="securities-flash"><%= @flash_message %></p>
        <% end %>

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
              data-current-columns={Jason.encode!(Enum.map(@visible_columns, &Atom.to_string/1))}
            >
              <table class="data-table">
                <thead>
                  <tr>
                    <th class="row-actions-head" aria-label={gettext("Row actions")}></th>
                    <%= for column <- visible_fields(@visible_columns) do %>
                      <th>
                        <%= if column.sortable? do %>
                          <button
                            type="button"
                            class="sort-toggle"
                            phx-click="toggle_sort"
                            phx-value-key={Atom.to_string(column.key)}
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
                    <tr>
                      <td colspan={length(visible_fields(@visible_columns)) + 1} class="empty-state">
                        <%= gettext("No securities yet — click + to add one.") %>
                      </td>
                    </tr>
                  <% end %>
                  <% visible = visible_fields(@visible_columns) %>
                  <% first_key = first_visible_key(visible) %>
                  <%= for row <- @securities do %>
                    <% sec_id = security_id(row) %>
                    <% inner_security = security_from_row(row) %>
                    <% row_path = "/securities/#{sec_id}" %>
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
    <aside
      class={["detail-pane", @detail_fullscreen? && "detail-pane--fullscreen"]}
      id="security-detail-pane"
      aria-label={gettext("Selected security")}
      aria-modal={if @detail_fullscreen?, do: "true", else: "false"}
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
              · <%= gettext("Latest") %> <%= format_decimal(@detail_latest.close, 2) %>
              (<%= Date.to_iso8601(@detail_latest.date) %>)
            <% end %>
          </p>
          </div>
        </div>
        <div class="detail-pane-head__actions">
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
            patch="/securities"
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
            </div>

            <form
              id="detail-custom-range"
              phx-submit="set_detail_custom_range"
              class="detail-custom-range"
              data-active={if @detail_custom_range, do: "true", else: "false"}
              aria-label={gettext("Custom range")}
            >
              <input
                type="date"
                name="from"
                value={@detail_custom_range && Date.to_iso8601(@detail_custom_range.from)}
                aria-label={gettext("From")}
              />
              <span aria-hidden="true">→</span>
              <input
                type="date"
                name="to"
                value={@detail_custom_range && Date.to_iso8601(@detail_custom_range.to)}
                aria-label={gettext("To")}
              />
              <button type="submit" class="chart-toggle">
                <%= gettext("Apply") %>
              </button>
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
              build_chart_overlays(@detail_quotes, @detail_transaction_rows, @detail_ma, @detail_cost_basis?)
            }
            log_scale?={@detail_log_scale? and not @detail_percent_mode?}
            percent_mode?={@detail_percent_mode?}
            show_transactions?={@detail_show_transactions?}
            currency_code={@selected_security.currency_code}
          />
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
        />
      <% end %>

      <%= if @detail_tab == "holdings" do %>
        <.holdings_tab_panel
          holdings={@detail_holdings}
          currency_code={@selected_security.currency_code}
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
              <%= format_decimal(@metrics.latest_price, 2) %>
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
        <div class="overview-metric">
          <dt><%= gettext("Day change") %></dt>
          <dd><%= signed_percent_or_dash(@metrics[:day_change_pct]) %></dd>
        </div>
        <div class="overview-metric">
          <dt>1M</dt>
          <dd><%= signed_percent_or_dash(@metrics[:performance_1m]) %></dd>
        </div>
        <div class="overview-metric">
          <dt>1Y</dt>
          <dd><%= signed_percent_or_dash(@metrics[:performance_1y]) %></dd>
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
                <th><%= gettext("Portfolio") %></th>
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
                  <td class="num"><%= format_decimal(tx.quantity, 4) %></td>
                  <td class="num">
                    <%= format_decimal(tx.price, 2) %>
                    <small><%= tx.currency_code %></small>
                  </td>
                  <td class="num"><%= format_decimal(tx.fees, 2) %></td>
                  <td class="num"><%= format_decimal(tx.taxes, 2) %></td>
                  <td class="num"><%= format_decimal(tx_gross(tx), 2) %></td>
                  <td><%= portfolio_name(tx) %></td>
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
              </tr>
            </thead>
            <tbody>
              <%= for lot <- @trades.open_lots do %>
                <tr>
                  <td><%= Date.to_iso8601(lot.open_date) %></td>
                  <td class="num"><%= format_decimal(lot.quantity, 4) %></td>
                  <td class="num"><%= format_decimal(lot.buy_price, 2) %></td>
                  <td class="num">
                    <%= if lot.latest_price do %>
                      <%= format_decimal(lot.latest_price, 2) %>
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
                  <td class="num"><%= format_decimal(trade.quantity, 4) %></td>
                  <td class="num"><%= format_decimal(trade.avg_buy_price, 2) %></td>
                  <td class="num"><%= format_decimal(trade.avg_sell_price, 2) %></td>
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

  defp holdings_tab_panel(assigns) do
    totals =
      Enum.reduce(assigns.holdings, %{value: Decimal.new(0), cost: Decimal.new(0)}, fn h, acc ->
        if h.current_value && h.avg_cost do
          cost = Decimal.mult(h.quantity, h.avg_cost)

          %{
            value: Decimal.add(acc.value, h.current_value),
            cost: Decimal.add(acc.cost, cost)
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
          <%= gettext("No open positions for this security across your portfolios.") %>
        </p>
      <% else %>
        <div class="data-table-wrap">
          <table class="data-table detail-holdings-table">
            <thead>
              <tr>
                <th><%= gettext("Portfolio") %></th>
                <th><%= gettext("Depot") %></th>
                <th class="num"><%= gettext("Quantity") %></th>
                <th class="num"><%= gettext("Avg cost") %></th>
                <th class="num"><%= gettext("Current value") %></th>
                <th class="num"><%= gettext("Unrealised P&L") %></th>
                <th class="num">%</th>
              </tr>
            </thead>
            <tbody>
              <%= for h <- @holdings do %>
                <tr>
                  <td><%= h.portfolio && h.portfolio.name %></td>
                  <td><%= h.depot && h.depot.name %></td>
                  <td class="num"><%= format_decimal(h.quantity, 4) %></td>
                  <td class="num">
                    <%= format_decimal(h.avg_cost, 2) %>
                    <small><%= @currency_code %></small>
                  </td>
                  <td class="num">
                    <%= if h.current_value do %>
                      <%= format_decimal(h.current_value, 2) %>
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
                </tr>
              <% end %>
            </tbody>
            <tfoot>
              <tr class="totals-row">
                <td colspan="4"><%= gettext("Total") %></td>
                <td class="num">
                  <%= format_decimal(@totals.value, 2) %>
                  <small><%= @currency_code %></small>
                </td>
                <td class={["num", pnl_class(@total_pnl)]}>
                  <%= signed_decimal_or_dash(@total_pnl, 2) %>
                </td>
                <td class="num"></td>
              </tr>
            </tfoot>
          </table>
        </div>
      <% end %>
    </section>
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
              <span class="sc-name"><%= entry.classification.name %></span>
              <%= unless entry.editable do %>
                <span class="badge"><%= gettext("Built-in") %></span>
              <% end %>
            </div>
            <%= if entry.editable do %>
              <form phx-change="set_security_classification" class="sc-form">
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
        <div class="data-table-wrap">
          <table class="data-table detail-quotes-table">
            <thead>
              <tr>
                <th><%= gettext("Date") %></th>
                <th class="num"><%= gettext("Closing price") %></th>
                <th><%= gettext("Source") %></th>
              </tr>
            </thead>
            <tbody>
              <%= for q <- @rows do %>
                <tr>
                  <td><%= Date.to_iso8601(q.date) %></td>
                  <td class="num">
                    <%= format_decimal(q.close, 2) %>
                    <small><%= @currency_code %></small>
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

  defp quote_source_label("auto"), do: gettext("Auto")
  defp quote_source_label("manual"), do: gettext("Manual")
  defp quote_source_label("coingecko"), do: "CoinGecko"
  defp quote_source_label("portfolio_performance"), do: "Portfolio Performance"
  defp quote_source_label(other) when is_binary(other), do: other
  defp quote_source_label(_), do: ""

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

  defp signed_decimal_or_dash(value, places), do: format_signed_decimal(value, places)

  defp tx_type_label("buy"), do: gettext("Buy")
  defp tx_type_label("sell"), do: gettext("Sell")
  defp tx_type_label(other), do: to_string(other)

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

  defp portfolio_name(%{portfolio: %{name: name}}), do: name
  defp portfolio_name(_), do: nil

  defp depot_name(%{securities_account: %{name: name}}), do: name
  defp depot_name(_), do: nil

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
        |> format_signed_decimal(2)
        |> Kernel.<>(" %")
    end
  end

  defp build_chart_overlays(quotes, transactions, ma_toggles, cost_basis?) do
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
            label: "Cost basis",
            points: cost_basis_series(quotes, transactions)
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

  defp cost_basis_series(quotes, transactions) when transactions != [] do
    sorted_txs = Enum.sort_by(transactions, & &1.date, Date)

    series =
      sorted_txs
      |> Enum.reduce({Decimal.new(0), Decimal.new(0), []}, fn tx, {qty_held, avg_cost, points} ->
        case tx.type do
          "buy" ->
            new_qty = Decimal.add(qty_held, tx.quantity)

            new_avg =
              if Decimal.equal?(new_qty, 0) do
                Decimal.new(0)
              else
                numerator =
                  Decimal.add(
                    Decimal.mult(qty_held, avg_cost),
                    Decimal.mult(tx.quantity, tx.price)
                  )

                Decimal.div(numerator, new_qty)
              end

            {new_qty, new_avg, [{tx.date, Decimal.to_float(new_avg)} | points]}

          "sell" ->
            new_qty = Decimal.sub(qty_held, tx.quantity)
            {new_qty, avg_cost, [{tx.date, Decimal.to_float(avg_cost)} | points]}

          _ ->
            {qty_held, avg_cost, points}
        end
      end)
      |> elem(2)
      |> Enum.reverse()

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

  defp cost_basis_series(_quotes, _empty), do: []

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

  defp detail_tab_path(%Security{id: id}, tab), do: "/securities/#{id}?tab=#{tab}"

  defp holding_status_options do
    [
      {"all", gettext("All")},
      {"held", gettext("Held")},
      {"not_held", gettext("Not held")}
    ]
  end

  defp selected?(nil, _row), do: false
  defp selected?(%Security{id: id}, row), do: id == security_id(row)

  defp visible_fields(visible) when is_list(visible) do
    visible
    |> Enum.map(&SecurityFields.get/1)
    |> Enum.reject(&is_nil/1)
  end

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

  # options_html is constructed entirely from AssetClasses.options() (compile-time
  # constants) with every value passed through html_escape/1 — no user input.
  # sobelow_skip ["XSS.Raw"]
  defp render_cell(%Field{key: :asset_class} = field, row) do
    case SecurityFields.value(field, row) do
      nil ->
        sec_id = to_string(security_id(row))

        options_html =
          AssetClasses.options()
          |> Enum.map_join("", fn {label, code} ->
            escaped_code = Phoenix.HTML.html_escape(code) |> safe_to_string()
            escaped_label = Phoenix.HTML.html_escape(label) |> safe_to_string()
            ~s(<option value="#{escaped_code}">#{escaped_label}</option>)
          end)

        Phoenix.HTML.raw(
          ~s[<form phx-change="quick_assign_asset_class" phx-value-id="#{sec_id}" onclick="event.stopPropagation()" class="quick-assign-form">] <>
            ~s[<select name="asset_class" class="quick-assign-select">] <>
            ~s[<option value="">—</option>] <>
            options_html <>
            ~s[</select></form>]
        )

      value ->
        Phoenix.HTML.raw(
          ~s(<span class="badge">#{Phoenix.HTML.html_escape(AssetClasses.label(value)) |> safe_to_string()}</span>)
        )
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
      value -> format_decimal(value, 2)
    end
  end

  defp render_cell(%Field{render_hint: :money_signed} = field, security) do
    case SecurityFields.value(field, security) do
      nil ->
        ""

      value ->
        formatted = format_signed_decimal(value, 2)

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
            formatted = format_signed_decimal(as_percent, 2) <> " %"

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

  defp format_decimal(value, places) do
    case decimal_for_display(value) do
      nil ->
        "—"

      decimal ->
        decimal
        |> Decimal.round(places)
        |> Decimal.to_string(:normal)
    end
  end

  defp format_signed_decimal(value, places) do
    case decimal_for_display(value) do
      nil ->
        "—"

      decimal ->
        rounded = Decimal.round(decimal, places)

        case Decimal.compare(rounded, 0) do
          :gt -> "+" <> Decimal.to_string(rounded, :normal)
          _ -> Decimal.to_string(rounded, :normal)
        end
    end
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

  defp display_value(:asset_class, value), do: AssetClasses.label(value)
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
    {:noreply, socket |> assign(:query, query) |> load_securities()}
  end

  def handle_event("set_holding_status", %{"status" => status}, socket) do
    {:noreply,
     socket
     |> assign(:holding_status, safe_holding_status(status))
     |> load_securities()}
  end

  def handle_event("toggle_popover", %{"popover" => name}, socket) do
    case safe_atom(name) do
      nil ->
        {:noreply, socket}

      key ->
        next = if socket.assigns.open_popover == key, do: nil, else: key
        {:noreply, assign(socket, :open_popover, next)}
    end
  end

  def handle_event("open_new", _params, socket) do
    {:noreply,
     socket
     |> assign(:dialog_open?, true)
     |> assign(:open_popover, nil)}
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

    {:noreply,
     socket
     |> assign(:sync_running?, true)
     |> assign(:flash_message, gettext("Syncing prices…"))}
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
           Classifications.create_category(%{"classification_id" => cid, "name" => name}),
         {:ok, _} <- Classifications.assign_security(id, cid, category.id) do
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
        case Catalog.update_security(security, %{"note" => note}) do
          {:ok, updated} ->
            {:noreply,
             socket
             |> assign(:selected_security, updated)
             |> load_securities()
             |> assign(:flash_message, gettext("Notes saved."))}

          {:error, _changeset} ->
            {:noreply, assign(socket, :flash_message, gettext("Could not save notes."))}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("save_security_details", %{"security" => params}, socket) do
    case socket.assigns.selected_security do
      %Security{} = security ->
        case Catalog.update_security(security, params) do
          {:ok, updated} ->
            {:noreply,
             socket
             |> assign(:selected_security, updated)
             |> load_detail_data()
             |> load_securities()
             |> assign(:flash_message, gettext("Security updated."))}

          {:error, _changeset} ->
            {:noreply, assign(socket, :flash_message, gettext("Could not save changes."))}
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
         {:ok, _} <- Catalog.update_security(security, %{asset_class: class}) do
      {:noreply,
       socket
       |> load_securities()
       |> assign(:flash_message, gettext("Asset class saved."))}
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
         |> push_patch(to: detail_tab_path(security, tab))}

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
       |> load_detail_data()}
    else
      {:noreply, socket}
    end
  end

  def handle_event(
        "set_detail_custom_range",
        %{"from" => from_str, "to" => to_str},
        socket
      ) do
    with %Security{} <- socket.assigns.selected_security,
         {:ok, from} <- Date.from_iso8601(from_str),
         {:ok, to} <- Date.from_iso8601(to_str),
         true <- Date.compare(from, to) != :gt do
      {:noreply,
       socket
       |> assign(:detail_custom_range, %{from: from, to: to})
       |> load_detail_data()}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("toggle_detail_percent_mode", _params, socket) do
    {:noreply, update(socket, :detail_percent_mode?, &(!&1))}
  end

  def handle_event("clear_detail_custom_range", _params, socket) do
    if socket.assigns.selected_security do
      {:noreply,
       socket
       |> assign(:detail_custom_range, nil)
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

  def handle_event("remove_filter", %{"idx" => idx}, socket) do
    idx = String.to_integer(idx)
    filters = List.delete_at(socket.assigns.filters, idx)
    {:noreply, socket |> assign(:filters, filters) |> load_securities()}
  end

  def handle_event("toggle_sort", %{"key" => key}, socket) do
    case safe_column_atom(key) do
      nil ->
        {:noreply, socket}

      key_atom ->
        sort =
          case socket.assigns.sort do
            {^key_atom, :asc} -> {key_atom, :desc}
            {^key_atom, :desc} -> {:name, :asc}
            _ -> {key_atom, :asc}
          end

        {:noreply, socket |> assign(:sort, sort) |> load_securities()}
    end
  end

  def handle_event("set_columns", %{"columns" => columns}, socket) when is_list(columns) do
    visible =
      columns
      |> Enum.map(&safe_column_atom/1)
      |> Enum.reject(&is_nil/1)

    visible = if visible == [], do: SecurityFields.visible_default(), else: visible

    {:noreply, assign(socket, :visible_columns, visible)}
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
       |> assign(:flash_message, gettext("Logo removed"))
       |> load_securities()
       |> load_detail_data()}
    else
      _ -> {:noreply, assign(socket, :flash_message, gettext("Could not remove logo"))}
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

    {:noreply,
     socket
     |> assign(:sync_running?, true)
     |> assign(:flash_message, gettext("Syncing %{name}…", name: sec.name))}
  end

  defp dispatch_row_action(socket, "retire", %Security{} = sec) do
    case Catalog.update_security(sec, %{is_retired: !sec.is_retired}) do
      {:ok, _updated} ->
        flash =
          if sec.is_retired,
            do: gettext("Reactivated %{name}", name: sec.name),
            else: gettext("Retired %{name}", name: sec.name)

        {:noreply,
         socket
         |> assign(:flash_message, flash)
         |> assign(:delete_blocked, nil)
         |> load_securities()}

      {:error, _changeset} ->
        {:noreply, assign(socket, :flash_message, gettext("Could not change status."))}
    end
  end

  defp dispatch_row_action(socket, "open", %Security{} = sec) do
    {:noreply, push_patch(socket, to: "/securities/#{sec.id}")}
  end

  defp dispatch_row_action(socket, "copy_isin", %Security{isin: isin})
       when is_binary(isin) and isin != "" do
    {:noreply,
     socket
     |> push_event("copy-to-clipboard", %{text: isin})
     |> assign(:flash_message, gettext("ISIN copied"))}
  end

  defp dispatch_row_action(socket, "copy_isin", _sec), do: {:noreply, socket}

  defp dispatch_row_action(socket, "copy_ticker", %Security{ticker_symbol: t})
       when is_binary(t) and t != "" do
    {:noreply,
     socket
     |> push_event("copy-to-clipboard", %{text: t})
     |> assign(:flash_message, gettext("Ticker copied"))}
  end

  defp dispatch_row_action(socket, "copy_ticker", _sec), do: {:noreply, socket}

  defp dispatch_row_action(socket, "delete", %Security{} = sec) do
    case Catalog.delete_security(sec) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:flash_message, gettext("Deleted %{name}", name: sec.name))
         |> assign(:delete_blocked, nil)
         |> load_securities()}

      {:error, _changeset} ->
        {:noreply, assign(socket, :delete_blocked, sec)}
    end
  end

  defp dispatch_row_action(socket, "update_logo", %Security{} = sec) do
    parent = self()
    sec_id = sec.id

    Task.Supervisor.start_child(Portfolixir.LogoSupervisor, fn ->
      result = LogoLookup.run(sec)
      send(parent, {:logo_update_done, sec_id, result})
    end)

    {:noreply, assign(socket, :flash_message, gettext("Looking up logo…"))}
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

  defp store_logo_url(socket, _sec, "") do
    {:noreply, assign(socket, :flash_message, gettext("Enter an image URL first."))}
  end

  defp store_logo_url(socket, sec, url) do
    flash =
      case Catalog.set_logo_override(sec, url, logo_opts()) do
        {:ok, _updated} -> gettext("Logo updated")
        {:error, _reason} -> gettext("Could not load that image")
      end

    {:noreply,
     socket
     |> assign(:logo_dialog_security, nil)
     |> assign(:flash_message, flash)
     |> load_securities()
     |> load_detail_data()}
  end

  # Manual logo operations reuse the same storage dir (and, in tests, the same
  # Req stub) the background discovery worker is configured with.
  defp logo_opts, do: Application.get_env(:portfolixir, :logo_discovery_opts, [])

  defp safe_column_atom(key) when is_binary(key) do
    field = Enum.find(SecurityFields.all(), &(Atom.to_string(&1.key) == key))
    field && field.key
  end

  defp safe_column_atom(_), do: nil

  defp safe_holding_status(status) when status in @holding_statuses, do: status
  defp safe_holding_status(_), do: @default_holding_status

  defp safe_atom(string) when is_binary(string) do
    String.to_existing_atom(string)
  rescue
    ArgumentError -> nil
  end

  # -- messages from child components --------------------------------------

  @impl true
  def handle_info({:columns_changed, columns}, socket) do
    columns = if columns == [], do: SecurityFields.visible_default(), else: columns
    column_strs = Enum.map(columns, &Atom.to_string/1)

    {:noreply,
     socket
     |> assign(:visible_columns, columns)
     |> push_event("column-prefs-changed", %{columns: column_strs})}
  end

  def handle_info({:filter_added, filter}, socket) do
    filters = socket.assigns.filters ++ [filter]

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:open_popover, nil)
     |> load_securities()}
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
     |> assign(:flash_message, gettext("Created %{name}", name: security.name))
     |> load_securities()}
  end

  def handle_info({:dialog, _id, {:updated, security}}, socket) do
    {:noreply,
     socket
     |> assign(:dialog_open?, false)
     |> assign(:editing_security, nil)
     |> assign(:flash_message, gettext("Updated %{name}", name: security.name))
     |> load_securities()}
  end

  def handle_info({:dialog, _id, {:open_existing, _security}}, socket) do
    {:noreply,
     socket
     |> assign(:dialog_open?, false)
     |> assign(:editing_security, nil)}
  end

  def handle_info({:logo_update_done, _sec_id, result}, socket) do
    flash =
      case result do
        {:ok, _security} -> gettext("Logo updated")
        :skip -> gettext("No logo source available")
        {:error, _reason} -> gettext("Logo lookup failed")
      end

    {:noreply,
     socket
     |> assign(:flash_message, flash)
     |> refresh_logo_dialog()
     |> load_securities()
     |> load_detail_data()}
  end

  def handle_info(:sync_done, socket) do
    handle_info({:sync_done, {:ok, %{ok: 0, skipped: 0, error: 0}}}, socket)
  end

  def handle_info({:sync_done, result}, socket) do
    {:noreply,
     socket
     |> assign(:sync_running?, false)
     |> assign(:flash_message, sync_flash(result))
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
    |> assign(:detail_transactions, [])
    |> assign(:detail_transaction_rows, [])
    |> assign(:detail_trades, %{open_lots: [], closed_trades: [], orphan_sells: []})
    |> assign(:detail_holdings, [])
    |> assign(:detail_latest, nil)
    |> assign(:detail_metrics, SecurityWithMetrics.empty_metrics())
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

    quotes =
      id
      |> Quotes.range(from, to)
      |> Enum.map(&%{date: &1.date, close: &1.close, source: &1.source})

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

    socket
    |> assign(:detail_quotes, quotes)
    |> assign(:detail_transactions, transactions)
    |> assign(:detail_transaction_rows, transaction_rows)
    |> assign(:detail_trades, Ledger.list_trades_for_security(id))
    |> assign(:detail_holdings, Ledger.holdings_for_security(id))
    |> assign(:detail_latest, Quotes.latest(id))
    |> assign(:detail_metrics, metrics)
    |> assign(:detail_classifications, load_security_classifications(id))
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
    Classifications.unassign_security(security_id, classification_id)
  end

  defp apply_classification_change(security_id, classification_id, category_id) do
    case Integer.parse(category_id) do
      {category, ""} -> Classifications.assign_security(security_id, classification_id, category)
      _ -> {:error, :invalid}
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
    securities =
      Catalog.list_securities_with_metrics(
        query: socket.assigns.query,
        holding_status: socket.assigns.holding_status,
        filters: socket.assigns.filters,
        sort: socket.assigns.sort
      )

    assign(socket, :securities, securities)
  end
end
