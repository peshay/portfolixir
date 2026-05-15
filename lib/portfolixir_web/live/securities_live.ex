defmodule PortfolixirWeb.SecuritiesLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.AssetClasses
  alias Portfolixir.Catalog.Feeds
  alias Portfolixir.Catalog.SecurityFields
  alias Portfolixir.Catalog.SecurityFields.Field
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Securities.ColumnPicker
  alias PortfolixirWeb.Securities.FilterPopover
  alias PortfolixirWeb.Securities.SecurityFormDialog

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
     |> load_securities()}
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
              <%= for security <- @securities do %>
                <tr id={"security-row-#{security.id}"}>
                  <%= for column <- visible_fields(@visible_columns) do %>
                    <td><%= render_cell(column, security) %></td>
                  <% end %>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </section>

      <%= if @dialog_open? do %>
        <.live_component module={SecurityFormDialog} id="security-form-dialog" />
      <% end %>
    </AppShell.shell>
    """
  end

  defp visible_fields(visible) when is_list(visible) do
    visible
    |> Enum.map(&SecurityFields.get/1)
    |> Enum.reject(&is_nil/1)
  end

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

  defp render_cell(field, security) do
    case SecurityFields.value(field, security) do
      nil -> ""
      value -> display_value(field.key, value)
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
    key = String.to_existing_atom(name)
    next = if socket.assigns.open_popover == key, do: nil, else: key
    {:noreply, assign(socket, :open_popover, next)}
  end

  def handle_event("open_new", _params, socket) do
    {:noreply,
     socket
     |> assign(:dialog_open?, true)
     |> assign(:open_popover, nil)}
  end

  def handle_event("remove_filter", %{"idx" => idx}, socket) do
    idx = String.to_integer(idx)
    filters = List.delete_at(socket.assigns.filters, idx)
    {:noreply, socket |> assign(:filters, filters) |> load_securities()}
  end

  def handle_event("toggle_sort", %{"key" => key}, socket) do
    key_atom = String.to_existing_atom(key)

    sort =
      case socket.assigns.sort do
        {^key_atom, :asc} -> {key_atom, :desc}
        {^key_atom, :desc} -> {:name, :asc}
        _ -> {key_atom, :asc}
      end

    {:noreply, socket |> assign(:sort, sort) |> load_securities()}
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

  defp load_securities(socket) do
    securities =
      Catalog.list_securities(
        query: socket.assigns.query,
        filters: socket.assigns.filters,
        sort: socket.assigns.sort
      )

    assign(socket, :securities, securities)
  end
end
