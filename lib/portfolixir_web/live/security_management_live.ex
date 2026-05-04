defmodule PortfolixirWeb.SecurityManagementLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.SecurityCsv
  alias PortfolixirWeb.AppShell

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

  @security_column_storage_key "portfolixir.securities.visibleColumns"
  @security_table_columns [
    %{key: "name", label: "Name", required?: true},
    %{key: "symbol", label: "Symbol"},
    %{key: "currency", label: "Currency"},
    %{key: "isin", label: "ISIN"},
    %{key: "wkn", label: "WKN"},
    %{key: "provider_symbol", label: "Provider symbol"},
    %{key: "exchange", label: "Exchange"},
    %{key: "status", label: "Status"},
    %{key: "actions", label: "Actions", required?: true}
  ]
  @default_security_column_keys Enum.map(@security_table_columns, & &1.key)

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
      |> assign(:security_csv_input, "")
      |> assign(:security_csv_error, nil)
      |> assign(:security_csv_preview_rows, nil)
      |> assign(:security_status_filter, security_status_filter)
      |> assign(:security_table_columns, @security_table_columns)
      |> assign(:security_column_storage_key, @security_column_storage_key)
      |> assign(:visible_security_column_keys, @default_security_column_keys)
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
          <div class="app-shell-section-header">
            <div>
              <h2 class="app-shell-section-title"><%= gettext("Securities") %></h2>
              <p><%= gettext("Core identifiers used by the ledger and valuation workspaces.") %></p>
            </div>
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

          <details id="security-column-menu" class="app-shell-column-menu">
            <summary
              id="security-column-menu-button"
              class="app-shell-secondary"
              role="button"
              aria-label={gettext("Choose visible security table columns")}
            >
              <%= gettext("Columns") %>
            </summary>
            <form
              id="security-column-form"
              class="app-shell-column-menu-panel"
              phx-change="set_security_columns"
              data-storage-key={@security_column_storage_key}
              aria-label={gettext("Visible security table columns")}
            >
              <fieldset>
                <legend><%= gettext("Visible columns") %></legend>
                <p class="app-shell-help-text">
                  <%= gettext("Choose which security table columns are shown. Your browser saves the selection locally.") %>
                </p>
                <%= for column <- @security_table_columns do %>
                  <label for={"security-column-#{column.key}"}>
                    <input
                      id={"security-column-#{column.key}"}
                      type="checkbox"
                      name="columns[]"
                      value={column.key}
                      checked={security_column_visible?(@visible_security_column_keys, column.key)}
                      disabled={Map.get(column, :required?, false)}
                    />
                    <%= security_column_label(column.key) %>
                  </label>
                  <%= if Map.get(column, :required?, false) do %>
                    <input type="hidden" name="columns[]" value={column.key} />
                  <% end %>
                <% end %>
              </fieldset>
            </form>
          </details>

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
                    <%= for column <- @security_table_columns, security_column_visible?(@visible_security_column_keys, column.key) do %>
                      <th data-column-key={column.key}><%= security_column_label(column.key) %></th>
                    <% end %>
                  </tr>
                </thead>
                <tbody>
                  <%= for security <- @securities do %>
                    <tr class={security_row_class(security)}>
                      <%= if security_column_visible?(@visible_security_column_keys, "name") do %>
                        <td data-column-key="name">
                          <a
                            id={"security-detail-link-#{security.id}"}
                            href={"/securities/#{security.id}"}
                          >
                            <strong><%= security.name %></strong>
                          </a>
                        </td>
                      <% end %>
                      <%= if security_column_visible?(@visible_security_column_keys, "symbol") do %>
                        <td data-column-key="symbol"><%= security.symbol %></td>
                      <% end %>
                      <%= if security_column_visible?(@visible_security_column_keys, "currency") do %>
                        <td data-column-key="currency"><%= security.currency_code %></td>
                      <% end %>
                      <%= if security_column_visible?(@visible_security_column_keys, "isin") do %>
                        <td data-column-key="isin"><%= security.isin || "—" %></td>
                      <% end %>
                      <%= if security_column_visible?(@visible_security_column_keys, "wkn") do %>
                        <td data-column-key="wkn"><%= security.wkn || "—" %></td>
                      <% end %>
                      <%= if security_column_visible?(@visible_security_column_keys, "provider_symbol") do %>
                        <td data-column-key="provider_symbol"><%= security.provider_symbol || "—" %></td>
                      <% end %>
                      <%= if security_column_visible?(@visible_security_column_keys, "exchange") do %>
                        <td data-column-key="exchange"><%= security.exchange_code || "—" %></td>
                      <% end %>
                      <%= if security_column_visible?(@visible_security_column_keys, "status") do %>
                        <td data-column-key="status">
                          <%= if security.active do %>
                            <span class="app-shell-badge"><%= gettext("Active") %></span>
                          <% else %>
                            <span class="app-shell-badge app-shell-muted">
                              <%= gettext("Inactive") %>
                            </span>
                          <% end %>
                        </td>
                      <% end %>
                      <%= if security_column_visible?(@visible_security_column_keys, "actions") do %>
                        <td data-column-key="actions">
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
                      <% end %>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        </section>

        <script id="security-column-preferences-script">
          (function () {
            var form = document.getElementById("security-column-form");

            if (!form || !window.localStorage) {
              return;
            }

            var storageKey = form.getAttribute("data-storage-key");
            var checkboxSelector = "input[type='checkbox'][name='columns[]']";

            function checkedValues() {
              return Array.prototype.slice.call(form.querySelectorAll(checkboxSelector))
                .filter(function (input) { return input.checked || input.disabled; })
                .map(function (input) { return input.value; });
            }

            function persist() {
              localStorage.setItem(storageKey, JSON.stringify(checkedValues()));
            }

            function restore() {
              var stored = localStorage.getItem(storageKey);
              if (!stored) { return; }

              try {
                var visible = JSON.parse(stored);
                if (!Array.isArray(visible)) { return; }

                Array.prototype.slice.call(form.querySelectorAll(checkboxSelector)).forEach(function (input) {
                  if (!input.disabled) {
                    input.checked = visible.indexOf(input.value) !== -1;
                  }
                });

                form.dispatchEvent(new Event("change", { bubbles: true }));
              } catch (_error) {
                localStorage.removeItem(storageKey);
              }
            }

            form.addEventListener("change", persist);
            restore();
          })();
        </script>

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

  def handle_event("set_security_columns", params, socket) do
    {:noreply,
     assign(socket, :visible_security_column_keys, visible_security_column_keys(params))}
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

    socket
    |> assign(:security_total_count, Enum.count(all_securities))
    |> assign(:securities, Catalog.list_securities(socket.assigns.security_status_filter))
    |> assign(:currencies, Catalog.list_currencies())
  end

  defp visible_security_column_keys(%{"columns" => keys}) when is_list(keys) do
    allowed_keys = MapSet.new(Enum.map(@security_table_columns, & &1.key))
    selected_keys = Enum.filter(keys, &MapSet.member?(allowed_keys, &1))

    selected_keys
    |> Kernel.++(required_security_column_keys())
    |> Enum.uniq()
    |> then(fn
      [] -> @default_security_column_keys
      keys -> keys
    end)
  end

  defp visible_security_column_keys(_), do: @default_security_column_keys

  defp required_security_column_keys do
    @security_table_columns
    |> Enum.filter(&Map.get(&1, :required?, false))
    |> Enum.map(& &1.key)
  end

  defp security_column_visible?(visible_keys, key), do: key in visible_keys

  defp security_column_label("name"), do: gettext("Name")
  defp security_column_label("symbol"), do: gettext("Symbol")
  defp security_column_label("currency"), do: gettext("Currency")
  defp security_column_label("isin"), do: "ISIN"
  defp security_column_label("wkn"), do: "WKN"
  defp security_column_label("provider_symbol"), do: gettext("Provider symbol")
  defp security_column_label("exchange"), do: gettext("Exchange")
  defp security_column_label("status"), do: gettext("Status")
  defp security_column_label("actions"), do: gettext("Actions")

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
