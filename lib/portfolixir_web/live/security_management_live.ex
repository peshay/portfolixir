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
      |> assign(:security_error, nil)
      |> assign(:security_success, nil)
      |> load_securities()

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <AppShell.shell current_path="/securities">
      <header class="app-shell-page-header">
        <h1>All Securities</h1>
        <p>Track and manage the securities in your portfolio.</p>
      </header>

      <section
        id="security-listing"
        class="app-shell-section-card app-shell-section-card--primary"
      >
        <h2 class="app-shell-section-title">Securities</h2>

        <%= if Enum.empty?(@securities) do %>
          <div id="no-securities" class="app-shell-empty-state">
            <h3>No securities yet</h3>
            <p>Add your first security to start building your portfolio.</p>
          </div>
        <% else %>
          <div id="security-list">
            <table>
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
                    <td><%= security.name %></td>
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

      <section id="security-create" class="app-shell-section-card app-shell-section-card--compact">
        <h2 class="app-shell-section-title">Add security</h2>
        <p class="app-shell-help-text">Currency must use an ISO 4217 code (for example USD or EUR).</p>

        <%= if @security_success do %>
          <p id="security-form-success" class="app-shell-alert app-shell-alert--success" role="status" aria-live="polite">
            <%= @security_success %>
          </p>
        <% end %>

        <%= if @security_error do %>
          <p id="security-form-error" class="app-shell-alert app-shell-alert--error" role="status" aria-live="polite">
            <%= @security_error %>
          </p>
        <% end %>

        <form id="security-form" phx-submit="create_security">
          <label for="security-name">Name</label>
          <input
            id="security-name"
            name="security[name]"
            value={@security_form["name"]}
          />

          <label for="security-symbol">Symbol</label>
          <input
            id="security-symbol"
            name="security[symbol]"
            value={@security_form["symbol"]}
          />

          <label for="security-currency-code">Currency code</label>
          <input
            id="security-currency-code"
            name="security[currency_code]"
            value={@security_form["currency_code"]}
          />

          <label for="security-isin">ISIN (optional)</label>
          <input id="security-isin" name="security[isin]" value={@security_form["isin"]} />

          <label for="security-wkn">WKN (optional)</label>
          <input id="security-wkn" name="security[wkn]" value={@security_form["wkn"]} />

          <label for="security-exchange-code">Exchange code (optional)</label>
          <input
            id="security-exchange-code"
            name="security[exchange_code]"
            value={@security_form["exchange_code"]}
          />

          <label for="security-provider-symbol">Provider symbol (optional)</label>
          <input
            id="security-provider-symbol"
            name="security[provider_symbol]"
            value={@security_form["provider_symbol"]}
          />

          <label for="security-notes">Notes (optional)</label>
          <textarea id="security-notes" rows="2" name="security[notes]">
            <%= @security_form["notes"] %>
          </textarea>

          <button type="submit" class="app-shell-primary">
            Add security
          </button>
        </form>
      </section>
    </AppShell.shell>
    """
  end

  def handle_event("create_security", %{"security" => params}, socket) do
    case Catalog.create_security(sanitize_security_params(params)) do
      {:ok, _security} ->
        {:noreply,
         socket
         |> assign(:security_form, @security_form_defaults)
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

  defp format_errors(%Ecto.Changeset{} = changeset) do
    changeset.errors
    |> Enum.map_join(", ", fn {field, {message, _opts}} ->
      "#{Phoenix.Naming.humanize(field)} #{message}"
    end)
  end
end
