defmodule PortfolixirWeb.SecurityManagementLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.SecurityCsv
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Positions
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.WorkbenchToolbar

  @security_form_defaults %{
    "name" => "",
    "symbol" => "",
    "currency_code" => "",
    "isin" => "",
    "wkn" => "",
    "exchange_code" => "",
    "provider_symbol" => "",
    "active" => "true",
    "notes" => ""
  }

  def mount(params, _session, socket) do
    security_status_filter = parse_security_status_filter(params["status"])

    currencies = Catalog.list_currencies()

    socket =
      socket
      |> assign(:currencies, currencies)
      |> assign(:security_form, default_security_form(currencies))
      |> assign(:security_form_visible, false)
      |> assign(:security_form_mode, :create)
      |> assign(:editing_security_id, nil)
      |> assign(:security_error, nil)
      |> assign(:security_success, nil)
      |> assign(:security_search, "")
      |> assign(:security_csv_input, "")
      |> assign(:security_csv_error, nil)
      |> assign(:security_csv_preview_rows, nil)
      |> assign(:selected_security_id, nil)
      |> assign(:selected_security, nil)
      |> assign(:security_status_filter, security_status_filter)
      |> load_securities()

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <AppShell.shell current_path="/securities">
      <header class="app-shell-page-header">
        <div>
          <h1><%= gettext("All Securities") %></h1>
          <p><%= gettext("Manage your securities master data for portfolio positions, transactions and future quotes.") %></p>
        </div>
      </header>

      <div id="security-workspace" class="app-shell-workspace-stack">
        <section
          id="security-listing"
          class="app-shell-section-card"
          data-priority="primary"
        >
          <WorkbenchToolbar.toolbar
            id="security-workbench-toolbar"
            title={gettext("Securities")}
            description={gettext("Core identifiers used by the ledger and valuation workspaces.")}
            search_id="security-workbench-search"
            search_placeholder={gettext("Search (planned)")}
            search_label={gettext("Search securities")}
            time_ranges={["1M", "3M", "6M", "1Y", "YTD", "ALL"]}
            active_time_range="ALL"
          />

          <div class="app-shell-form-actions">
            <a id="security-export-csv" href="/securities/export.csv" class="app-shell-secondary">
              <%= gettext("Export CSV") %>
            </a>
            <button
              id="security-add-toggle"
              type="button"
              class="app-shell-secondary"
              phx-click="toggle_security_form"
              aria-expanded={if @security_form_visible, do: "true", else: "false"}
              aria-controls="security-create"
            >
              <%= if @security_form_visible, do: gettext("Close form"), else: gettext("Add security") %>
            </button>
          </div>
          <form id="security-search-form" class="app-shell-form-actions" phx-change="search_securities">
            <input
              id="security-search"
              name="q"
              type="search"
              value={@security_search}
              placeholder={gettext("Search securities")}
            />
          </form>
          <div id="security-status-filter" class="app-shell-form-actions">
            <button
              id="security-filter-active"
              type="button"
              class={filter_button_class(@security_status_filter, :active)}
              phx-click="set_security_status_filter"
              phx-value-status="active"
            >
              <%= gettext("Active") %>
            </button>
            <button
              id="security-filter-inactive"
              type="button"
              class={filter_button_class(@security_status_filter, :inactive)}
              phx-click="set_security_status_filter"
              phx-value-status="inactive"
            >
              <%= gettext("Inactive") %>
            </button>
            <button
              id="security-filter-all"
              type="button"
              class={filter_button_class(@security_status_filter, :all)}
              phx-click="set_security_status_filter"
              phx-value-status="all"
            >
              <%= gettext("All") %>
            </button>
          </div>

          <%= if Enum.empty?(@securities) do %>
            <div id="no-securities" class="app-shell-empty-state">
              <h3><%= security_filter_empty_title(@security_status_filter, @security_total_count) %></h3>
              <p><%= security_filter_empty_description(@security_status_filter, @security_total_count) %></p>
            </div>
          <% else %>
            <div class="app-shell-table-wrapper">
              <table id="security-list">
                <thead>
                  <tr>
                    <th><%= gettext("Name") %></th>
                    <th><%= gettext("Symbol") %></th>
                    <th><%= gettext("Currency") %></th>
                    <th>ISIN</th>
                    <th>WKN</th>
                    <th><%= gettext("Latest quote") %></th>
                    <th><%= gettext("Latest quote date") %></th>
                    <th><%= gettext("Position quantity") %></th>
                    <th><%= gettext("Provider symbol") %></th>
                    <th><%= gettext("Exchange") %></th>
                    <th><%= gettext("Status") %></th>
                    <th><%= gettext("Actions") %></th>
                  </tr>
                </thead>
                <tbody>
                  <%= for security <- @securities do %>
                    <tr
                      id={"security-row-#{security.id}"}
                      class={security_row_class(security)}
                      phx-click="select_security"
                      phx-value-id={security.id}
                    >
                      <td>
                        <strong><%= security.name %></strong>
                      </td>
                      <td><%= security.symbol %></td>
                      <td><%= security.currency_code %></td>
                      <td><%= security.isin || "—" %></td>
                      <td><%= security.wkn || "—" %></td>
                      <td><%= decimal_to_string(security.latest_quote_close) %></td>
                      <td><%= iso_date_or_dash(security.latest_quote_date) %></td>
                      <td><%= decimal_to_string(security.position_quantity) %></td>
                      <td><%= security.provider_symbol || "—" %></td>
                      <td><%= security.exchange_code || "—" %></td>
                      <td>
                        <a
                          id={"security-detail-link-#{security.id}"}
                          href={"/securities/#{security.id}"}
                        >
                          <%= gettext("Open detail") %>
                        </a>
                        <%= if security.active do %>
                          <span class="app-shell-badge"><%= gettext("Active") %></span>
                        <% else %>
                          <span class="app-shell-badge app-shell-muted">
                            <%= gettext("Inactive") %>
                          </span>
                        <% end %>
                      </td>
                      <td>
                        <%= if security.active do %>
                          <button
                            id={"security-archive-#{security.id}"}
                            type="button"
                            class="app-shell-secondary"
                            phx-click="archive_security"
                            phx-value-id={security.id}
                          >
                            <%= gettext("Archive") %>
                          </button>
                        <% end %>
                        <button
                          id={"security-edit-#{security.id}"}
                          type="button"
                          class="app-shell-secondary"
                          phx-click="start_edit_security"
                          phx-value-id={security.id}
                        >
                          <%= gettext("Edit security") %>
                        </button>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        </section>

        <section id="security-selected-detail" class="app-shell-section-card" data-priority="secondary">
          <div class="app-shell-section-header">
            <div>
              <h2 class="app-shell-section-title"><%= gettext("Selected security") %></h2>
              <p class="app-shell-panel-intro"><%= gettext("Inspect one security without leaving the table.") %></p>
            </div>
          </div>

          <%= if @selected_security do %>
            <div id="security-selected-summary" class="app-shell-summary-grid">
              <p><strong><%= gettext("Name") %>:</strong> <%= @selected_security.name %></p>
              <p><strong><%= gettext("Symbol") %>:</strong> <%= @selected_security.symbol %></p>
              <p><strong><%= gettext("Latest quote") %>:</strong> <%= decimal_to_string(@selected_security.latest_quote_close) %></p>
              <p><strong><%= gettext("Latest quote date") %>:</strong> <%= iso_date_or_dash(@selected_security.latest_quote_date) %></p>
            </div>

            <div id="security-selected-chart-placeholder" class="app-shell-empty-state">
              <h3><%= gettext("Chart preview") %></h3>
              <p><%= gettext("Chart placeholder: open the full detail page for the current chart view.") %></p>
              <p>
                <a id="security-selected-open-detail" href={"/securities/#{@selected_security.id}"}>
                  <%= gettext("Open full security detail") %>
                </a>
              </p>
            </div>
          <% else %>
            <div id="security-selected-empty" class="app-shell-empty-state">
              <h3><%= gettext("No security selected") %></h3>
              <p><%= gettext("Select a row to view details here.") %></p>
            </div>
          <% end %>
        </section>

        <%= if @security_form_visible || @security_success || @security_error do %>
          <section
            id="security-create"
            class="app-shell-section-card"
            data-priority="secondary"
          >
            <div class="app-shell-section-header">
              <div>
                <h2 class="app-shell-section-title">
                  <%= if @security_form_mode == :edit, do: gettext("Edit security"), else: gettext("Add security") %>
                </h2>
                <p class="app-shell-panel-intro">
                  <%= gettext("Create one instrument at a time.") %>
                </p>
              </div>
            </div>

            <%= if @security_success do %>
              <p
                id="security-form-success"
                class="app-shell-alert app-shell-alert--success"
                role="status"
                aria-live="polite"
              >
                <%= @security_success %>
              </p>
            <% end %>

            <%= if @security_error do %>
              <p id="security-form-error" class="app-shell-alert app-shell-alert--error" role="alert">
                <%= @security_error %>
              </p>
            <% end %>

            <form id="security-form" class="app-shell-form-grid" phx-submit="save_security">
              <div class="app-shell-field app-shell-field--full">
                <label for="security-name"><%= gettext("Name") %></label>
                <input
                  id="security-name"
                  name="security[name]"
                  value={@security_form["name"]}
                />
              </div>

              <div class="app-shell-field">
                <label for="security-symbol"><%= gettext("Symbol") %></label>
                <input
                  id="security-symbol"
                  name="security[symbol]"
                  value={@security_form["symbol"]}
                />
              </div>

              <div class="app-shell-field">
                <label for="security-currency-code"><%= gettext("Currency") %></label>
                <select
                  id="security-currency-code"
                  name="security[currency_code]"
                >
                  <option value=""><%= gettext("Select currency") %></option>
                  <%= for currency <- @currencies do %>
                    <option
                      value={currency.code}
                      selected={currency.code == @security_form["currency_code"]}
                    >
                      <%= currency_option_label(currency) %>
                    </option>
                  <% end %>
                </select>
              </div>

              <div class="app-shell-field">
                <label for="security-isin"><%= gettext("ISIN (optional)") %></label>
                <input id="security-isin" name="security[isin]" value={@security_form["isin"]} />
              </div>

              <div class="app-shell-field">
                <label for="security-wkn"><%= gettext("WKN (optional)") %></label>
                <input id="security-wkn" name="security[wkn]" value={@security_form["wkn"]} />
              </div>

              <div class="app-shell-field">
                <label for="security-exchange-code"><%= gettext("Exchange code (optional)") %></label>
                <input
                  id="security-exchange-code"
                  name="security[exchange_code]"
                  value={@security_form["exchange_code"]}
                />
              </div>

              <div class="app-shell-field">
                <label for="security-provider-symbol"><%= gettext("Provider symbol (optional)") %></label>
                <input
                  id="security-provider-symbol"
                  name="security[provider_symbol]"
                  value={@security_form["provider_symbol"]}
                />
              </div>

              <div class="app-shell-field">
                <label for="security-active"><%= gettext("Status") %></label>
                <select id="security-active" name="security[active]">
                  <option value="true" selected={@security_form["active"] == "true"}><%= gettext("Active") %></option>
                  <option value="false" selected={@security_form["active"] == "false"}><%= gettext("Inactive") %></option>
                </select>
              </div>

              <div class="app-shell-field app-shell-field--full">
                <label for="security-notes"><%= gettext("Notes (optional)") %></label>
                <textarea id="security-notes" rows="2" name="security[notes]"><%= @security_form["notes"] %></textarea>
              </div>

              <div class="app-shell-form-actions">
                <%= if @security_form_mode == :edit do %>
                  <button
                    id="security-cancel-edit"
                    type="button"
                    class="app-shell-secondary"
                    phx-click="cancel_edit_security"
                  >
                    <%= gettext("Cancel") %>
                  </button>
                <% end %>
                <button type="submit" class="app-shell-primary">
                  <%= if @security_form_mode == :edit, do: gettext("Save security"), else: gettext("Add security") %>
                </button>
              </div>
            </form>
          </section>
        <% end %>

        <section id="security-csv-preview" class="app-shell-section-card" data-priority="secondary">
          <div class="app-shell-section-header">
            <div>
              <h2 class="app-shell-section-title">
                <%= gettext("Import CSV preview") %>
              </h2>
              <p class="app-shell-panel-intro">
                <%= gettext("Paste security CSV data to validate rows before import.") %>
              </p>
            </div>
          </div>

          <%= if @security_csv_error do %>
            <p
              id="security-csv-error"
              class="app-shell-alert app-shell-alert--error"
              role="alert"
            >
              <%= @security_csv_error %>
            </p>
          <% end %>

          <form id="security-csv-preview-form" class="app-shell-form-grid" phx-submit="preview_security_csv">
            <div class="app-shell-field app-shell-field--full">
              <label for="security-csv-text"><%= gettext("CSV content") %></label>
              <textarea
                id="security-csv-text"
                name="security_csv_text"
                rows="8"
              ><%= @security_csv_input %></textarea>
            </div>
            <div class="app-shell-form-actions">
              <button type="submit" class="app-shell-primary">
                <%= gettext("Preview CSV") %>
              </button>
              <%= if @security_csv_preview_rows || @security_csv_error do %>
                <button
                  type="button"
                  id="security-csv-clear-preview"
                  class="app-shell-secondary"
                  phx-click="clear_security_csv_preview"
                >
                  <%= gettext("Clear preview") %>
                </button>
              <% end %>
            </div>
          </form>

          <%= if @security_csv_preview_rows do %>
            <div class="app-shell-table-wrapper">
              <table id="security-csv-preview-table">
                <thead>
                  <tr>
                    <th><%= gettext("Row") %></th>
                    <th><%= gettext("Status") %></th>
                    <th><%= gettext("Name") %></th>
                    <th><%= gettext("Symbol") %></th>
                    <th><%= gettext("Currency") %></th>
                    <th><%= gettext("Active") %></th>
                    <th>ISIN</th>
                    <th>WKN</th>
                    <th><%= gettext("Provider symbol") %></th>
                    <th><%= gettext("Exchange") %></th>
                    <th><%= gettext("Notes") %></th>
                    <th><%= gettext("Errors") %></th>
                  </tr>
                </thead>
                <tbody>
                  <%= for row <- @security_csv_preview_rows do %>
                    <tr id={"security-preview-row-#{row.row_number}"} class={if row.status == :invalid, do: "app-shell-muted", else: ""}>
                      <td><%= row.row_number %></td>
                      <td id={"security-preview-status-#{row.row_number}"}><%= security_csv_preview_status(row.status) %></td>
                      <td><%= row.name %></td>
                      <td><%= row.symbol %></td>
                      <td><%= row.currency_code %></td>
                      <td><%= security_csv_preview_active(row.active) %></td>
                      <td><%= row.isin || "—" %></td>
                      <td><%= row.wkn || "—" %></td>
                      <td><%= row.provider_symbol || "—" %></td>
                      <td><%= row.exchange_code || "—" %></td>
                      <td><%= row.notes || "" %></td>
                      <td class="app-shell-help-text"><%= Enum.join(row.errors, ", ") %></td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        </section>

      </div>
    </AppShell.shell>
    """
  end

  def handle_event("preview_security_csv", %{"security_csv_text" => csv_text}, socket) do
    valid_currency_codes = Enum.map(socket.assigns.currencies, & &1.code)

    case SecurityCsv.preview_csv_rows(csv_text, valid_currency_codes: valid_currency_codes) do
      {:ok, %{rows: rows}} ->
        {:noreply,
         socket
         |> assign(:security_csv_input, csv_text)
         |> assign(:security_csv_preview_rows, rows)
         |> assign(:security_csv_error, nil)}

      {:error, message} ->
        {:noreply,
         socket
         |> assign(:security_csv_input, csv_text)
         |> assign(:security_csv_preview_rows, nil)
         |> assign(:security_csv_error, message)}
    end
  end

  def handle_event("preview_security_csv", _params, socket) do
    {:noreply,
     socket
     |> assign(:security_csv_error, "CSV input is empty.")
     |> assign(:security_csv_preview_rows, nil)}
  end

  def handle_event("clear_security_csv_preview", _params, socket) do
    {:noreply,
     socket
     |> assign(:security_csv_input, "")
     |> assign(:security_csv_preview_rows, nil)
     |> assign(:security_csv_error, nil)}
  end

  def handle_event("toggle_security_form", _params, socket) do
    case socket.assigns.security_form_mode do
      :edit ->
        {:noreply, exit_edit_mode(socket)}

      :create ->
        {:noreply,
         assign(socket, :security_form_visible, not socket.assigns.security_form_visible)}
    end
  end

  def handle_event("start_edit_security", %{"id" => id_string}, socket) do
    {id, ""} = Integer.parse(id_string)

    security = Catalog.get_security!(id)

    {:noreply,
     socket
     |> assign(:security_form_mode, :edit)
     |> assign(:editing_security_id, security.id)
     |> assign(:security_form_visible, true)
     |> assign(:security_form, security_form_values(security))
     |> assign(:security_success, nil)
     |> assign(:security_error, nil)}
  end

  def handle_event("cancel_edit_security", _params, socket) do
    {:noreply, exit_edit_mode(socket)}
  end

  def handle_event("set_security_status_filter", %{"status" => status}, socket) do
    new_status = parse_security_status_filter(status)

    {:noreply,
     socket
     |> assign(:security_status_filter, new_status)
     |> load_securities()}
  end

  def handle_event("search_securities", %{"q" => query}, socket) do
    {:noreply,
     socket
     |> assign(:security_search, query)
     |> load_securities()}
  end

  def handle_event("select_security", %{"id" => id_string}, socket) do
    case Integer.parse(id_string) do
      {id, ""} ->
        {:noreply,
         socket
         |> assign(:selected_security_id, id)
         |> load_securities()}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("archive_security", %{"id" => id_string}, socket) do
    {id, ""} = Integer.parse(id_string)
    security = Catalog.get_security!(id)

    case Catalog.archive_security(security) do
      {:ok, _security} ->
        {:noreply,
         socket
         |> assign(:security_success, gettext("Security archived."))
         |> assign(:security_error, nil)
         |> load_securities()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:security_error, "Failed to archive security: #{format_errors(changeset)}")
         |> assign(:security_success, nil)
         |> load_securities()}
    end
  end

  def handle_event("save_security", %{"security" => params}, socket) do
    case socket.assigns.security_form_mode do
      :edit -> save_security_edit(socket, params)
      _ -> save_security_create(socket, params)
    end
  end

  defp save_security_create(socket, params) do
    case Catalog.create_security(sanitize_security_params(params)) do
      {:ok, _security} ->
        {:noreply,
         socket
         |> assign(:security_form, default_security_form(socket.assigns.currencies))
         |> assign(:security_form_visible, true)
         |> assign(:security_error, nil)
         |> assign(:security_success, gettext("Security added."))
         |> load_securities()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:security_form, security_form_input_values(params))
         |> assign(:security_form_visible, true)
         |> assign(:security_error, format_errors(changeset))
         |> assign(:security_success, nil)
         |> load_securities()}
    end
  end

  defp save_security_edit(%{assigns: %{editing_security_id: nil}} = socket, params) do
    save_security_create(socket, params)
  end

  defp save_security_edit(socket, params) do
    security = Catalog.get_security!(socket.assigns.editing_security_id)

    case Catalog.update_security(security, sanitize_security_params(params)) do
      {:ok, _security} ->
        {:noreply,
         exit_edit_mode(socket, security_form: default_security_form(socket.assigns.currencies))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:security_form, security_form_input_values(params))
         |> assign(:security_error, format_errors(changeset))
         |> assign(:security_success, nil)
         |> assign(:security_form_visible, true)
         |> load_securities()}
    end
  end

  defp exit_edit_mode(socket, opts \\ []) do
    currencies = opts[:currencies] || socket.assigns.currencies
    security_form = opts[:security_form] || default_security_form(currencies)

    socket
    |> assign(:security_form_mode, :create)
    |> assign(:editing_security_id, nil)
    |> assign(:security_form_visible, false)
    |> assign(:security_form, security_form)
    |> assign(:security_error, nil)
    |> assign(:security_success, nil)
    |> load_securities()
  end

  defp security_form_input_values(params) do
    @security_form_defaults
    |> Map.merge(sanitize_security_params(params))
    |> Enum.into(%{}, fn {key, value} -> {key, value || ""} end)
  end

  defp security_form_values(security) do
    %{
      "name" => security.name || "",
      "symbol" => security.symbol || "",
      "currency_code" => security.currency_code || "",
      "active" => to_string(security.active),
      "isin" => security.isin || "",
      "wkn" => security.wkn || "",
      "exchange_code" => security.exchange_code || "",
      "provider_symbol" => security.provider_symbol || "",
      "notes" => security.notes || ""
    }
  end

  defp load_securities(socket) do
    all_securities = Catalog.list_securities(:all)
    search = String.trim(socket.assigns.security_search || "")

    position_quantity_by_security_id = position_quantity_by_security_id()

    quoted_and_positioned =
      Catalog.list_securities(socket.assigns.security_status_filter)
      |> Enum.map(&enrich_security(&1, position_quantity_by_security_id))
      |> maybe_filter_by_search(search)

    selected_security_id =
      choose_selected_security_id(socket.assigns.selected_security_id, quoted_and_positioned)

    selected_security = Enum.find(quoted_and_positioned, &(&1.id == selected_security_id))

    socket
    |> assign(:security_total_count, Enum.count(all_securities))
    |> assign(:securities, quoted_and_positioned)
    |> assign(:selected_security_id, selected_security_id)
    |> assign(:selected_security, selected_security)
    |> assign(:currencies, Catalog.list_currencies())
  end

  defp choose_selected_security_id(current_id, securities) do
    cond do
      current_id && Enum.any?(securities, &(&1.id == current_id)) -> current_id
      first = List.first(securities) -> first.id
      true -> nil
    end
  end

  defp enrich_security(security, position_quantity_by_security_id) do
    latest_quote = Catalog.get_latest_security_quote(security.id)
    position_quantity = Map.get(position_quantity_by_security_id, security.id, Decimal.new("0"))

    Map.merge(security, %{
      latest_quote_close: latest_quote && latest_quote.close,
      latest_quote_date: latest_quote && latest_quote.date,
      position_quantity: position_quantity
    })
  end

  defp position_quantity_by_security_id do
    Ledger.list_transactions()
    |> Positions.calculate()
    |> Enum.reduce(%{}, fn {{_account_id, security_id}, quantity}, acc ->
      Map.update(acc, security_id, quantity, &Decimal.add(&1, quantity))
    end)
  end

  defp maybe_filter_by_search(securities, ""), do: securities

  defp maybe_filter_by_search(securities, search) do
    needle = String.downcase(search)

    Enum.filter(securities, fn security ->
      [security.name, security.symbol, security.isin, security.wkn, security.provider_symbol]
      |> Enum.reject(&is_nil/1)
      |> Enum.any?(fn value -> String.contains?(String.downcase(value), needle) end)
    end)
  end

  defp security_filter_empty_title(:all, _total_count), do: gettext("No securities yet")

  defp security_filter_empty_title(:active, 0), do: gettext("No securities yet")

  defp security_filter_empty_title(:active, _), do: gettext("No active securities")
  defp security_filter_empty_title(:inactive, _), do: gettext("No inactive securities")

  defp security_filter_empty_description(:all, _),
    do: gettext("Add your first security to start building your portfolio.")

  defp security_filter_empty_description(:active, 0),
    do: gettext("Add your first security to start building your portfolio.")

  defp security_filter_empty_description(:active, _),
    do: gettext("Only active securities are shown. Mark one active to appear here.")

  defp security_filter_empty_description(:inactive, _),
    do: gettext("No inactive securities match this filter.")

  defp security_row_class(%Portfolixir.Catalog.Security{active: false}), do: "app-shell-muted"
  defp security_row_class(_), do: ""

  defp iso_date_or_dash(nil), do: "—"
  defp iso_date_or_dash(%Date{} = date), do: Date.to_iso8601(date)

  defp decimal_to_string(nil), do: "—"
  defp decimal_to_string(%Decimal{} = decimal), do: Decimal.to_string(decimal, :normal)

  defp filter_button_class(:active, :active), do: "app-shell-primary"
  defp filter_button_class(:inactive, :inactive), do: "app-shell-primary"
  defp filter_button_class(:all, :all), do: "app-shell-primary"
  defp filter_button_class(_, _), do: "app-shell-secondary"

  defp security_csv_preview_status(:valid), do: gettext("valid")
  defp security_csv_preview_status(:invalid), do: gettext("invalid")
  defp security_csv_preview_status(_), do: gettext("invalid")

  defp security_csv_preview_active(true), do: gettext("Active")
  defp security_csv_preview_active(false), do: gettext("Inactive")
  defp security_csv_preview_active("true"), do: gettext("Active")
  defp security_csv_preview_active("false"), do: gettext("Inactive")
  defp security_csv_preview_active(_), do: gettext("Inactive")

  defp parse_security_status_filter("inactive"), do: :inactive
  defp parse_security_status_filter("all"), do: :all
  defp parse_security_status_filter(_), do: :active

  defp default_security_form(currencies) do
    Map.put(@security_form_defaults, "currency_code", preferred_currency_code(currencies))
  end

  defp preferred_currency_code(currencies) do
    cond do
      Enum.any?(currencies, &(&1.code == "EUR")) -> "EUR"
      currency = List.first(currencies) -> currency.code
      true -> ""
    end
  end

  defp currency_option_label(currency) do
    "#{currency.code} - #{currency.name}"
  end

  defp sanitize_security_params(params) when is_map(params) do
    params
    |> Map.new(fn {key, value} -> {key, value} end)
    |> maybe_remove_empty_string("isin")
    |> maybe_remove_empty_string("wkn")
    |> maybe_remove_empty_string("exchange_code")
    |> maybe_remove_empty_string("provider_symbol")
    |> maybe_remove_empty_string("notes")
  end

  defp sanitize_security_params(_), do: %{}

  defp maybe_remove_empty_string(params, key) do
    case Map.get(params, key) do
      "" -> Map.put(params, key, nil)
      _ -> params
    end
  end

  defp format_errors(%Ecto.Changeset{} = changeset) do
    changeset.errors
    |> Enum.map_join(", ", fn {field, {message, _opts}} ->
      "#{Phoenix.Naming.humanize(field)} #{message}"
    end)
  end
end
