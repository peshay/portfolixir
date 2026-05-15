defmodule PortfolixirWeb.SecuritiesLive do
  use PortfolixirWeb, :live_view

  require Logger

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.AssetClasses
  alias Portfolixir.Catalog.Feeds
  alias Portfolixir.Catalog.QuoteSync
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Catalog.SecurityFields
  alias Portfolixir.Catalog.SecurityFields.Field
  alias Portfolixir.Catalog.SecurityWithMetrics
  alias Portfolixir.Ledger
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Components.SecurityChart
  alias PortfolixirWeb.Securities.ColumnPicker
  alias PortfolixirWeb.Securities.FilterPopover
  alias PortfolixirWeb.Securities.SecurityFormDialog

  @ranges ~w(1M 3M 6M YTD 1Y 3Y 5Y MAX)
  @default_range "1Y"

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:query, "")
     |> assign(:filters, [])
     |> assign(:sort, {:name, :asc})
     |> assign(:visible_columns, SecurityFields.visible_default())
     |> assign(:open_popover, nil)
     |> assign(:dialog_open?, false)
     |> assign(:flash_message, nil)
     |> assign(:sync_running?, false)
     |> assign(:selected_security, nil)
     |> assign(:detail_range, @default_range)
     |> assign(:detail_log_scale?, false)
     |> assign(:detail_show_transactions?, true)
     |> assign(:detail_quotes, [])
     |> assign(:detail_transactions, [])
     |> assign(:detail_latest, nil)
     |> load_securities()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case params["id"] do
      nil ->
        {:noreply, clear_selection(socket)}

      id ->
        case Catalog.get_security(id) do
          %Security{} = security -> {:noreply, select_security(socket, security)}
          nil -> {:noreply, clear_selection(socket)}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell current_path="/securities">
      <header class="page-header">
        <h1><%= gettext("Securities") %></h1>
        <p><%= gettext("Search, filter and curate your investable universe.") %></p>
      </header>

      <section class="panel" id="securities-panel">
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
                  <td colspan={length(visible_fields(@visible_columns))} class="empty-state">
                    <%= gettext("No securities yet — click + to add one.") %>
                  </td>
                </tr>
              <% end %>
              <% visible = visible_fields(@visible_columns) %>
              <% first_key = first_visible_key(visible) %>
              <%= for row <- @securities do %>
                <% row_path = "/securities/#{security_id(row)}" %>
                <tr
                  id={"security-row-#{security_id(row)}"}
                  class={[
                    "security-row",
                    selected?(@selected_security, row) && "is-selected"
                  ]}
                  phx-click={Phoenix.LiveView.JS.patch(row_path)}
                  role="link"
                >
                  <%= for column <- visible do %>
                    <td>
                      <%= if column.key == first_key do %>
                        <.link patch={row_path} class="row-target" tabindex="0">
                          <%= render_cell(column, row) %>
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

        <%= if @selected_security do %>
          <%= render_detail_pane(assigns) %>
        <% end %>
      </section>

      <%= if @dialog_open? do %>
        <.live_component module={SecurityFormDialog} id="security-form-dialog" />
      <% end %>
    </AppShell.shell>
    """
  end

  defp render_detail_pane(assigns) do
    ~H"""
    <aside class="detail-pane" id="security-detail-pane" aria-label={gettext("Selected security")}>
      <header class="detail-pane-head">
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
        <.link patch="/securities" class="icon-button" aria-label={gettext("Close detail")}>
          <AppShell.icon name={:x} />
        </.link>
      </header>

      <div class="detail-pane-toolbar" role="toolbar" aria-label={gettext("Chart options")}>
        <div class="range-buttons" role="group" aria-label={gettext("Range")}>
          <%= for range <- ranges() do %>
            <button
              type="button"
              phx-click="set_detail_range"
              phx-value-range={range}
              class={["range-button", @detail_range == range && "is-active"]}
            >
              <%= range %>
            </button>
          <% end %>
        </div>

        <div class="chart-toggles">
          <button
            type="button"
            id="toggle-log"
            phx-click="toggle_detail_log"
            class={["chart-toggle", @detail_log_scale? && "is-active"]}
            aria-pressed={@detail_log_scale?}
          >
            <%= gettext("Log scale") %>
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
          <button
            type="button"
            id="detail-sync"
            phx-click="sync_now"
            class={["chart-toggle", @sync_running? && "is-busy"]}
            disabled={@sync_running?}
          >
            <%= gettext("Sync prices") %>
          </button>
        </div>
      </div>

      <SecurityChart.chart
        quotes={@detail_quotes}
        transactions={@detail_transactions}
        log_scale?={@detail_log_scale?}
        show_transactions?={@detail_show_transactions?}
        currency_code={@selected_security.currency_code}
      />
    </aside>
    """
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

  defp sort_marker({key, :asc}, key), do: " ↑"
  defp sort_marker({key, :desc}, key), do: " ↓"
  defp sort_marker(_, _), do: ""

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
      true -> "✓"
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
        # value is a fractional decimal (0.05 → +5.00 %)
        as_percent = Decimal.mult(value, Decimal.new(100))
        formatted = format_signed_decimal(as_percent, 2) <> " %"

        Phoenix.HTML.raw(
          ~s(<span class="#{decimal_class(value)}">#{Phoenix.HTML.html_escape(formatted) |> safe_to_string()}</span>)
        )
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

  defp format_decimal(%Decimal{} = value, places) do
    value
    |> Decimal.round(places)
    |> Decimal.to_string(:normal)
  end

  defp format_decimal(other, places) when is_binary(other) or is_integer(other) do
    format_decimal(Decimal.new(to_string(other)), places)
  end

  defp format_signed_decimal(%Decimal{} = value, places) do
    rounded = Decimal.round(value, places)

    case Decimal.compare(rounded, 0) do
      :gt -> "+" <> Decimal.to_string(rounded, :normal)
      _ -> Decimal.to_string(rounded, :normal)
    end
  end

  defp decimal_class(%Decimal{} = value) do
    case Decimal.compare(value, 0) do
      :gt -> "decimal-positive"
      :lt -> "decimal-negative"
      :eq -> "decimal-neutral"
    end
  end

  defp display_value(:asset_class, value), do: AssetClasses.label(value)
  defp display_value(:feed, value), do: Feeds.label(value)
  defp display_value(:latest_feed, value), do: Feeds.label(value)
  defp display_value(_key, value), do: to_string(value)

  defp safe_to_string({:safe, iodata}), do: IO.iodata_to_binary(iodata)
  defp safe_to_string(other) when is_binary(other), do: other

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
      try do
        _ = QuoteSync.sync_all()
      rescue
        exception ->
          Logger.error(
            "QuoteSync.sync_all crashed: " <> Exception.format(:error, exception, __STACKTRACE__)
          )
      catch
        kind, reason ->
          Logger.error("QuoteSync.sync_all exited: #{inspect({kind, reason})}")
      after
        # Always re-enable the UI, even on crash — otherwise the spinner
        # would hang until the page is reloaded.
        send(parent, :sync_done)
      end
    end)

    {:noreply,
     socket
     |> assign(:sync_running?, true)
     |> assign(:flash_message, gettext("Syncing prices…"))}
  end

  def handle_event("set_detail_range", %{"range" => range}, socket) do
    if range in @ranges and socket.assigns.selected_security do
      {:noreply, socket |> assign(:detail_range, range) |> load_detail_data()}
    else
      {:noreply, socket}
    end
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

  defp safe_column_atom(key) when is_binary(key) do
    field = Enum.find(SecurityFields.all(), &(Atom.to_string(&1.key) == key))
    field && field.key
  end

  defp safe_column_atom(_), do: nil

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
    {:noreply, assign(socket, :dialog_open?, false)}
  end

  def handle_info({:dialog, _id, {:created, security}}, socket) do
    {:noreply,
     socket
     |> assign(:dialog_open?, false)
     |> assign(:flash_message, gettext("Created %{name}", name: security.name))
     |> load_securities()}
  end

  def handle_info({:dialog, _id, {:updated, security}}, socket) do
    {:noreply,
     socket
     |> assign(:dialog_open?, false)
     |> assign(:flash_message, gettext("Updated %{name}", name: security.name))
     |> load_securities()}
  end

  def handle_info({:dialog, _id, {:open_existing, _security}}, socket) do
    {:noreply, assign(socket, :dialog_open?, false)}
  end

  def handle_info(:sync_done, socket) do
    {:noreply,
     socket
     |> assign(:sync_running?, false)
     |> assign(:flash_message, gettext("Prices synced."))
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
    |> assign(:detail_quotes, [])
    |> assign(:detail_transactions, [])
    |> assign(:detail_latest, nil)
  end

  defp load_detail_data(%{assigns: %{selected_security: nil}} = socket), do: socket

  defp load_detail_data(socket) do
    %Security{id: id} = socket.assigns.selected_security
    {from, to} = range_to_dates(socket.assigns.detail_range, id)

    quotes =
      id
      |> Quotes.range(from, to)
      |> Enum.map(&%{date: &1.date, close: &1.close})

    transactions =
      id
      |> Ledger.list_transactions_for_security()
      |> Enum.map(&%{date: &1.date, type: &1.type, price: &1.price, quantity: &1.quantity})

    socket
    |> assign(:detail_quotes, quotes)
    |> assign(:detail_transactions, transactions)
    |> assign(:detail_latest, Quotes.latest(id))
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
        filters: socket.assigns.filters,
        sort: socket.assigns.sort
      )

    assign(socket, :securities, securities)
  end
end
