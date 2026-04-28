defmodule PortfolixirWeb.SecurityManagementLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.Catalog
  alias PortfolixirWeb.AppShell

  @security_form_defaults %{
    "name" => "",
    "symbol" => "",
    "currency_code" => "",
    "isin" => "",
    "wkn" => "",
    "exchange_code" => "",
    "provider_symbol" => "",
    "notes" => ""
  }

  def mount(_params, _session, socket) do
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

          <%= if Enum.empty?(@securities) do %>
            <div id="no-securities" class="app-shell-empty-state">
              <h3><%= gettext("No securities yet") %></h3>
              <p><%= gettext("Add your first security to start building your portfolio.") %></p>
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
                    <th><%= gettext("Provider symbol") %></th>
                    <th><%= gettext("Exchange") %></th>
                    <th><%= gettext("Actions") %></th>
                  </tr>
                </thead>
                <tbody>
                  <%= for security <- @securities do %>
                    <tr>
                      <td><strong><%= security.name %></strong></td>
                      <td><%= security.symbol %></td>
                      <td><%= security.currency_code %></td>
                      <td><%= security.isin || "—" %></td>
                      <td><%= security.wkn || "—" %></td>
                      <td><%= security.provider_symbol || "—" %></td>
                      <td><%= security.exchange_code || "—" %></td>
                      <td>
                        <button
                          id={"security-edit-#{security.id}"}
                          type="button"
                          class="app-shell-secondary"
                          phx-click="start_edit_security"
                          phx-value-id={security.id}
                        >
                          <%= gettext("Edit") %>
                        </button>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
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
      </div>
    </AppShell.shell>
    """
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
      "isin" => security.isin || "",
      "wkn" => security.wkn || "",
      "exchange_code" => security.exchange_code || "",
      "provider_symbol" => security.provider_symbol || "",
      "notes" => security.notes || ""
    }
  end

  defp load_securities(socket) do
    socket
    |> assign(:securities, Catalog.list_securities())
    |> assign(:currencies, Catalog.list_currencies())
  end

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
