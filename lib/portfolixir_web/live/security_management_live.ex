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
      |> assign(:show_security_form, false)
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
          <p class="app-shell-page-kicker"><%= gettext("Securities") %></p>
          <h1><%= gettext("All Securities") %></h1>
          <p><%= gettext("Manage your securities master data for portfolio positions, transactions and future quotes.") %></p>
        </div>
      </header>

      <div id="security-actions" class="app-shell-action-row">
        <div class="app-shell-action-row-left">
          <label class="app-shell-visually-hidden" for="security-search"><%= gettext("Search securities") %></label>
          <input
            id="security-search"
            class="app-shell-search"
            type="search"
            placeholder={gettext("Search securities...")}
            disabled
            aria-label={gettext("Search coming soon")}
            title={gettext("Search coming soon")}
          />
          <button
            id="security-filter"
            type="button"
            class="app-shell-secondary"
            disabled
            aria-disabled="true"
            aria-label={gettext("Filter coming soon")}
            title={gettext("Filter coming soon")}
          >
            <%= gettext("Filter") %>
          </button>
        </div>
        <div class="app-shell-action-row-right">
          <button
            id="security-add-toggle"
            type="button"
            class="app-shell-primary"
            phx-click="toggle_security_form"
            aria-expanded={if @show_security_form, do: "true", else: "false"}
            aria-controls="security-create"
          >
            <%= if @show_security_form, do: gettext("Close"), else: gettext("Add Security") %>
          </button>
        </div>
      </div>

      <section id="security-kpis" class="app-shell-stat-grid" aria-label={gettext("Security summary")}>
        <div class="app-shell-stat-card">
          <span class="app-shell-stat-icon" aria-hidden="true">SEC</span>
          <div>
            <span class="app-shell-stat-label"><%= gettext("Total Securities") %></span>
            <span class="app-shell-stat-value"><%= Enum.count(@securities) %></span>
            <span class="app-shell-stat-hint"><%= gettext("All time") %></span>
          </div>
        </div>
        <div class="app-shell-stat-card">
          <span class="app-shell-stat-icon" aria-hidden="true">CCY</span>
          <div>
            <span class="app-shell-stat-label"><%= gettext("Currencies") %></span>
            <span class="app-shell-stat-value"><%= unique_currency_count(@securities) %></span>
            <span class="app-shell-stat-hint"><%= gettext("In use") %></span>
          </div>
        </div>
        <div class="app-shell-stat-card">
          <span class="app-shell-stat-icon" aria-hidden="true">CL</span>
          <div>
            <span class="app-shell-stat-label"><%= gettext("Classifications") %></span>
            <span class="app-shell-stat-value">—</span>
            <span class="app-shell-stat-hint"><%= gettext("Assignments later") %></span>
          </div>
        </div>
        <div class="app-shell-stat-card">
          <span class="app-shell-stat-icon" aria-hidden="true">UPD</span>
          <div>
            <span class="app-shell-stat-label"><%= gettext("Last Updated") %></span>
            <span class="app-shell-stat-value"><%= last_updated_label(@securities) %></span>
            <span class="app-shell-stat-hint"><%= last_updated_hint(@securities) %></span>
          </div>
        </div>
      </section>

      <div id="security-workspace" class="app-shell-workspace-stack">
        <section
          id="security-listing"
          class="app-shell-section-card"
          data-priority="primary"
        >
          <div class="app-shell-section-header">
            <div>
              <h2 class="app-shell-section-title"><%= gettext("Security master") %></h2>
              <p><%= gettext("Core identifiers used by the ledger and valuation workspaces.") %></p>
            </div>
            <span class="app-shell-badge app-shell-badge--accent">
              <%= ngettext("%{count} total", "%{count} total", Enum.count(@securities),
                count: Enum.count(@securities)
              ) %>
            </span>
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
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        </section>

        <%= if @show_security_form || @security_success || @security_error do %>
          <section
            id="security-create"
            class="app-shell-section-card"
            data-priority="secondary"
          >
            <div class="app-shell-section-header">
              <div>
                <h2 class="app-shell-section-title"><%= gettext("Add security") %></h2>
                <p class="app-shell-panel-intro">
                  <%= gettext("Create one instrument at a time. Currency is selected from first-run reference data.") %>
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

            <form id="security-form" class="app-shell-form-grid" phx-submit="create_security">
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
              <button type="submit" class="app-shell-primary">
                <%= gettext("Add security") %>
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
    {:noreply, assign(socket, :show_security_form, not socket.assigns.show_security_form)}
  end

  def handle_event("create_security", %{"security" => params}, socket) do
    case Catalog.create_security(sanitize_security_params(params)) do
      {:ok, _security} ->
        {:noreply,
         socket
         |> assign(:security_form, default_security_form(socket.assigns.currencies))
         |> assign(:show_security_form, true)
         |> assign(:security_error, nil)
         |> assign(:security_success, gettext("Security added."))
         |> load_securities()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(
           :security_form,
           @security_form_defaults |> Map.merge(sanitize_security_params(params))
         )
         |> assign(:show_security_form, true)
         |> assign(:security_error, format_errors(changeset))
         |> assign(:security_success, nil)
         |> load_securities()}
    end
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

  defp unique_currency_count(securities) do
    securities
    |> Enum.map(& &1.currency_code)
    |> Enum.uniq()
    |> Enum.count()
  end

  defp last_updated_label([]), do: "—"

  defp last_updated_label(securities) do
    if last_security_date(securities) == Date.utc_today(), do: gettext("Today"), else: "—"
  end

  defp last_updated_hint([]), do: gettext("Not tracked yet")

  defp last_updated_hint(securities),
    do:
      if(last_security_date(securities) == Date.utc_today(),
        do: gettext("Just now"),
        else: gettext("Not today")
      )

  defp last_security_date(securities) do
    securities
    |> Enum.map(& &1.updated_at)
    |> Enum.reject(&is_nil/1)
    |> Enum.max_by(&NaiveDateTime.to_erl/1, fn -> nil end)
    |> case do
      nil -> nil
      updated_at -> NaiveDateTime.to_date(updated_at)
    end
  end

  defp format_errors(%Ecto.Changeset{} = changeset) do
    changeset.errors
    |> Enum.map_join(", ", fn {field, {message, _opts}} ->
      "#{Phoenix.Naming.humanize(field)} #{message}"
    end)
  end
end
