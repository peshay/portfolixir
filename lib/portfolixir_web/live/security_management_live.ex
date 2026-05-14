defmodule PortfolixirWeb.SecurityManagementLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.Catalog
  alias PortfolixirWeb.AppShell

  @empty_security_form %{
    "name" => "",
    "symbol" => "",
    "currency_code" => "EUR",
    "isin" => "",
    "exchange_code" => "",
    "notes" => ""
  }

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:security_form, @empty_security_form)
     |> assign(:error, nil)
     |> assign(:success, nil)
     |> load_securities()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell current_path="/securities">
      <header class="page-header">
        <h1><%= gettext("Securities") %></h1>
        <p><%= gettext("Security master data") %></p>
      </header>

      <div class="stack">
        <section id="security-create" class="panel">
          <h2><%= gettext("Add security") %></h2>
          <%= if @error do %>
            <p class="alert-error" role="alert"><%= @error %></p>
          <% end %>
          <%= if @success do %>
            <p class="alert-success" role="status"><%= @success %></p>
          <% end %>
          <form id="security-form" phx-submit="save_security">
            <div class="form-grid">
              <label>
                <span><%= gettext("Name") %></span>
                <input name="security[name]" value={@security_form["name"]} required />
              </label>
              <label>
                <span><%= gettext("Symbol") %></span>
                <input name="security[symbol]" value={@security_form["symbol"]} required />
              </label>
              <label>
                <span><%= gettext("Currency") %></span>
                <input name="security[currency_code]" value={@security_form["currency_code"]} maxlength="3" required />
              </label>
              <label>
                <span><%= gettext("ISIN") %></span>
                <input name="security[isin]" value={@security_form["isin"]} />
              </label>
              <label>
                <span><%= gettext("Exchange") %></span>
                <input name="security[exchange_code]" value={@security_form["exchange_code"]} />
              </label>
            </div>
            <label>
              <span><%= gettext("Notes") %></span>
              <textarea name="security[notes]"><%= @security_form["notes"] %></textarea>
            </label>
            <button type="submit"><%= gettext("Create security") %></button>
          </form>
        </section>

        <section id="security-list-panel" class="panel">
          <h2><%= gettext("All securities") %></h2>
          <%= if Enum.empty?(@securities) do %>
            <div id="no-securities" class="empty-state" role="status">
              <%= gettext("No securities yet") %>
            </div>
          <% else %>
            <table id="security-list">
              <thead>
                <tr>
                  <th><%= gettext("Name") %></th>
                  <th><%= gettext("Symbol") %></th>
                  <th><%= gettext("Currency") %></th>
                  <th><%= gettext("Detail") %></th>
                </tr>
              </thead>
              <tbody>
                <%= for security <- @securities do %>
                  <tr id={"security-row-#{security.id}"}>
                    <td><%= security.name %></td>
                    <td><%= security.symbol %></td>
                    <td><%= security.currency_code %></td>
                    <td><a href={"/securities/#{security.id}"}><%= gettext("Open") %></a></td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          <% end %>
        </section>
      </div>
    </AppShell.shell>
    """
  end

  @impl true
  def handle_event("save_security", %{"security" => params}, socket) do
    case Catalog.create_security(params) do
      {:ok, _security} ->
        {:noreply,
         socket
         |> assign(:security_form, @empty_security_form)
         |> assign(:error, nil)
         |> assign(:success, gettext("Security created"))
         |> load_securities()}

      {:error, changeset} ->
        {:noreply,
         assign(socket, error: changeset_error(changeset), success: nil, security_form: params)}
    end
  end

  defp load_securities(socket) do
    assign(socket, :securities, Catalog.list_securities())
  end

  defp changeset_error(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {message, _opts}} -> "#{field} #{message}" end)
    |> Enum.join(", ")
  end
end
