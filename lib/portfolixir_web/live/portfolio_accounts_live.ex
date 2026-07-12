defmodule PortfolixirWeb.PortfolioAccountsLive do
  @moduledoc """
  Accounts & depots administration (ADR-0022 area, reshaped by ADR-0024):
  create cash accounts and depots without any portfolio decision — the
  internal compatibility binding resolves to one deterministic default
  portfolio — plus the minimal read-only list of every portfolio record
  (ADR-0024 modification 1: no invisible writable resource).
  """

  use PortfolixirWeb, :live_view

  alias Portfolixir.Actor
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.CashAccount
  alias PortfolixirWeb.AppShell

  @cash_account_form %{"name" => "", "currency_code" => "EUR", "notes" => ""}
  @securities_account_form %{"name" => "", "cash_account_id" => "", "notes" => ""}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:cash_account_form, @cash_account_form)
     |> assign(:securities_account_form, @securities_account_form)
     |> assign(:error, nil)
     |> assign(:success, nil)
     |> load_state()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell
      current_path="/portfolios"
      page_title={gettext("Accounts & depots")}
      page_subtitle={gettext("Cash account and depot setup")}
    >
      <div id="portfolios-workspace" class="workspace-page">
        <%= if @error do %>
          <p class="alert-error" role="alert"><%= @error %></p>
        <% end %>
        <%= if @success do %>
          <p class="alert-success" role="status"><%= @success %></p>
        <% end %>

        <section id="account-create" class="workspace-section">
          <div class="grid">
            <article class="panel">
              <h2><%= gettext("Create cash account") %></h2>
              <form id="cash-account-form" phx-submit="save_cash_account">
                <label>
                  <span><%= gettext("Name") %></span>
                  <input name="cash_account[name]" value={@cash_account_form["name"]} required />
                </label>
                <label>
                  <span><%= gettext("Currency") %></span>
                  <input name="cash_account[currency_code]" value={@cash_account_form["currency_code"]} maxlength="3" required />
                </label>
                <button type="submit"><%= gettext("Create cash account") %></button>
              </form>
            </article>

            <article class="panel">
              <h2><%= gettext("Create depot") %></h2>
              <form id="securities-account-form" phx-submit="save_securities_account">
                <label>
                  <span><%= gettext("Name") %></span>
                  <input name="securities_account[name]" value={@securities_account_form["name"]} required />
                </label>
                <label>
                  <span><%= gettext("Linked cash account") %></span>
                  <select name="securities_account[cash_account_id]" required>
                    <option value=""><%= gettext("Select cash account") %></option>
                    <%= for account <- @cash_accounts do %>
                      <option value={account.id}><%= account.name %> (<%= account.currency_code %>)</option>
                    <% end %>
                  </select>
                </label>
                <button type="submit"><%= gettext("Create depot") %></button>
              </form>
            </article>
          </div>
        </section>

        <section id="portfolio-list-panel" class="workspace-section">
          <h2><%= gettext("Current setup") %></h2>
          <div class="grid">
            <article>
              <h3><%= gettext("Cash accounts") %></h3>
              <ul id="cash-account-list">
                <%= for account <- @cash_accounts do %>
                  <li>
                    <%= account.name %> (<%= account.currency_code %>)
                    <label class="cash-quote-toggle">
                      <form id={"liquidity-role-form-#{account.id}"} phx-change="set_liquidity_role">
                        <input type="hidden" name="account_id" value={account.id} />
                        <select id={"liquidity-role-#{account.id}"} name="liquidity_role">
                          <option value="free_cash" selected={account.liquidity_role == "free_cash"}>
                            <%= gettext("Free cash") %>
                          </option>
                          <option
                            value="credit_line"
                            selected={account.liquidity_role == "credit_line"}
                          >
                            <%= gettext("Credit line") %>
                          </option>
                          <option value="reserve" selected={account.liquidity_role == "reserve"}>
                            <%= gettext("Reserve") %>
                          </option>
                        </select>
                      </form>
                      <span><%= gettext("Liquidity role") %></span>
                    </label>
                  </li>
                <% end %>
              </ul>
            </article>
            <article>
              <h3><%= gettext("Depots") %></h3>
              <ul id="securities-account-list">
                <%= for account <- @securities_accounts do %>
                  <li><%= account.name %> -> <%= account.cash_account && account.cash_account.name %></li>
                <% end %>
              </ul>
            </article>
          </div>
        </section>

        <%!-- ADR-0024 modification 1: every portfolio record — however it was
             created (UI, API/MCP, import, seed) — stays visible in this
             minimal read-only list, so no writable resource is invisible.
             Deliberately collapsed and without any create/edit control: the
             records are internal compatibility bindings, not a grouping. --%>
        <details :if={@portfolio_records != []} id="portfolio-admin" class="workspace-section">
          <summary>
            <%= gettext("Portfolio records (compatibility)") %>
          </summary>
          <p class="hint">
            <%= gettext(
              "Internal compatibility records kept for the deprecated API surface. Grouping happens through buckets and views."
            ) %>
          </p>
          <table class="data-table" data-role="portfolio-admin-table">
            <thead>
              <tr>
                <th><%= gettext("Name") %></th>
                <th><%= gettext("Base currency") %></th>
                <th><%= gettext("Created") %></th>
                <th><%= gettext("Source") %></th>
                <th class="num"><%= gettext("Depots") %></th>
                <th class="num"><%= gettext("Cash accounts") %></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={record <- @portfolio_records}>
                <td><%= record.name %></td>
                <td><%= record.base_currency_code %></td>
                <td><%= record.inserted_at |> NaiveDateTime.to_date() |> Date.to_iso8601() %></td>
                <td><%= source_label(record.source) %></td>
                <td class="num"><%= record.depot_count %></td>
                <td class="num"><%= record.cash_account_count %></td>
              </tr>
            </tbody>
          </table>
        </details>
      </div>
    </AppShell.shell>
    """
  end

  @impl true
  def handle_event("save_cash_account", %{"cash_account" => params}, socket) do
    # ADR-0024: the internal binding is resolved, never asked for.
    params = Map.put(params, "portfolio_id", Portfolios.default_portfolio(Actor.owner_ui()).id)

    case Portfolios.create_cash_account(Actor.owner_ui(), params) do
      {:ok, _account} ->
        {:noreply,
         socket
         |> assign(:cash_account_form, @cash_account_form)
         |> success(gettext("Cash account created"))
         |> load_state()}

      {:error, changeset} ->
        {:noreply, failure(socket, changeset_error(changeset))}
    end
  end

  def handle_event("save_securities_account", %{"securities_account" => params}, socket) do
    params = Map.put(params, "portfolio_id", Portfolios.default_portfolio(Actor.owner_ui()).id)

    case Portfolios.create_securities_account(Actor.owner_ui(), params) do
      {:ok, _account} ->
        {:noreply,
         socket
         |> assign(:securities_account_form, @securities_account_form)
         |> success(gettext("Depot created"))
         |> load_state()}

      {:error, changeset} ->
        {:noreply, failure(socket, changeset_error(changeset))}
    end
  end

  def handle_event(
        "set_liquidity_role",
        %{"account_id" => id, "liquidity_role" => role},
        socket
      ) do
    with {account_id, ""} <- Integer.parse(id),
         %CashAccount{} = account <- Portfolios.get_cash_account(account_id),
         {:ok, _updated} <-
           Portfolios.update_cash_account(Actor.owner_ui(), account, %{liquidity_role: role}) do
      {:noreply,
       socket
       |> success(gettext("Cash account updated"))
       |> load_state()}
    else
      _ -> {:noreply, failure(socket, gettext("Could not update cash account"))}
    end
  end

  defp load_state(socket) do
    assign(socket,
      cash_accounts: Portfolios.list_cash_accounts(),
      securities_accounts: Portfolios.list_securities_accounts(),
      portfolio_records: Portfolios.portfolio_admin_list()
    )
  end

  defp source_label(:ui), do: gettext("UI")
  defp source_label(:api), do: gettext("API")
  defp source_label(:import), do: gettext("Import")
  defp source_label(_seeded), do: gettext("Seeded")

  defp success(socket, message), do: assign(socket, success: message, error: nil)
  defp failure(socket, message), do: assign(socket, error: message, success: nil)

  defp changeset_error(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {message, _opts}} -> "#{field} #{message}" end)
    |> Enum.join(", ")
  end
end
