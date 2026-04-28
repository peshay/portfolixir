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
    socket =
      socket
      |> assign(:security_form, @security_form_defaults)
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
          <p class="app-shell-page-kicker">Securities</p>
          <h1>All Securities</h1>
          <p>Manage your securities master data for portfolio positions, transactions and future quotes.</p>
        </div>
      </header>

      <div id="security-actions" class="app-shell-action-row">
        <div class="app-shell-action-row-left">
          <label class="app-shell-visually-hidden" for="security-search">Search securities</label>
          <input
            id="security-search"
            class="app-shell-search"
            type="search"
            placeholder="Search securities..."
            disabled
          />
          <button
            id="security-filter"
            type="button"
            class="app-shell-secondary"
            disabled
            aria-disabled="true"
            title="Filtering is coming soon"
          >
            Filter
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
            <%= if @show_security_form, do: "Close", else: "Add Security" %>
          </button>
        </div>
      </div>

      <section id="security-kpis" class="app-shell-stat-grid" aria-label="Security summary">
        <div class="app-shell-stat-card">
          <span class="app-shell-stat-icon" aria-hidden="true">SEC</span>
          <div>
            <span class="app-shell-stat-label">Total Securities</span>
            <span class="app-shell-stat-value"><%= Enum.count(@securities) %></span>
            <span class="app-shell-stat-hint">All time</span>
          </div>
        </div>
        <div class="app-shell-stat-card">
          <span class="app-shell-stat-icon" aria-hidden="true">CCY</span>
          <div>
            <span class="app-shell-stat-label">Currencies</span>
            <span class="app-shell-stat-value"><%= unique_currency_count(@securities) %></span>
            <span class="app-shell-stat-hint">In use</span>
          </div>
        </div>
        <div class="app-shell-stat-card">
          <span class="app-shell-stat-icon" aria-hidden="true">CL</span>
          <div>
            <span class="app-shell-stat-label">Classifications</span>
            <span class="app-shell-stat-value">—</span>
            <span class="app-shell-stat-hint">Assignments later</span>
          </div>
        </div>
        <div class="app-shell-stat-card">
          <span class="app-shell-stat-icon" aria-hidden="true">UPD</span>
          <div>
            <span class="app-shell-stat-label">Last Updated</span>
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
              <h2 class="app-shell-section-title">Security master</h2>
              <p>Core identifiers used by the ledger and valuation workspaces.</p>
            </div>
            <span class="app-shell-badge app-shell-badge--accent">
              <%= Enum.count(@securities) %> total
            </span>
          </div>

          <%= if Enum.empty?(@securities) do %>
            <div id="no-securities" class="app-shell-empty-state">
              <h3>No securities yet</h3>
              <p>Add your first security to start building your portfolio.</p>
            </div>
          <% else %>
            <div class="app-shell-table-wrapper">
              <table id="security-list">
                <thead>
                  <tr>
                    <th>Name</th>
                    <th>Symbol</th>
                    <th>Currency</th>
                    <th>ISIN</th>
                    <th>WKN</th>
                    <th>Provider symbol</th>
                    <th>Exchange</th>
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
                <h2 class="app-shell-section-title">Add security</h2>
                <p class="app-shell-panel-intro">
                  Create one instrument at a time. Currency must use an ISO 4217 code such as USD or EUR.
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
              <label for="security-name">Name</label>
              <input
                id="security-name"
                name="security[name]"
                value={@security_form["name"]}
              />
            </div>

            <div class="app-shell-field">
              <label for="security-symbol">Symbol</label>
              <input
                id="security-symbol"
                name="security[symbol]"
                value={@security_form["symbol"]}
              />
            </div>

            <div class="app-shell-field">
              <label for="security-currency-code">Currency code</label>
              <input
                id="security-currency-code"
                name="security[currency_code]"
                value={@security_form["currency_code"]}
              />
            </div>

            <div class="app-shell-field">
              <label for="security-isin">ISIN (optional)</label>
              <input id="security-isin" name="security[isin]" value={@security_form["isin"]} />
            </div>

            <div class="app-shell-field">
              <label for="security-wkn">WKN (optional)</label>
              <input id="security-wkn" name="security[wkn]" value={@security_form["wkn"]} />
            </div>

            <div class="app-shell-field">
              <label for="security-exchange-code">Exchange code (optional)</label>
              <input
                id="security-exchange-code"
                name="security[exchange_code]"
                value={@security_form["exchange_code"]}
              />
            </div>

            <div class="app-shell-field">
              <label for="security-provider-symbol">Provider symbol (optional)</label>
              <input
                id="security-provider-symbol"
                name="security[provider_symbol]"
                value={@security_form["provider_symbol"]}
              />
            </div>

            <div class="app-shell-field app-shell-field--full">
              <label for="security-notes">Notes (optional)</label>
              <textarea id="security-notes" rows="2" name="security[notes]"><%= @security_form["notes"] %></textarea>
            </div>

            <div class="app-shell-form-actions">
              <button type="submit" class="app-shell-primary">
                Add security
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
         |> assign(:security_form, @security_form_defaults)
         |> assign(:show_security_form, true)
         |> assign(:security_error, nil)
         |> assign(:security_success, "Security added.")
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
    if last_security_date(securities) == Date.utc_today(), do: "Today", else: "—"
  end

  defp last_updated_hint([]), do: "Not tracked yet"

  defp last_updated_hint(securities),
    do: if(last_updated_label(securities) == "Today", do: "Just now", else: "Not today")

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
