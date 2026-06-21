defmodule PortfolixirWeb.PortfolioAccountsLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.CashAccount
  alias PortfolixirWeb.AppShell

  @portfolio_form %{"name" => "", "base_currency_code" => "EUR", "notes" => ""}
  @cash_account_form %{"name" => "", "currency_code" => "EUR", "notes" => ""}
  @securities_account_form %{"name" => "", "cash_account_id" => "", "notes" => ""}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:portfolio_form, @portfolio_form)
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
      page_title={gettext("Portfolios")}
      page_subtitle={gettext("Portfolio, cash account, and depot setup")}
    >
      <div id="portfolios-workspace" class="workspace-page">
        <%= if @error do %>
          <p class="alert-error" role="alert"><%= @error %></p>
        <% end %>
        <%= if @success do %>
          <p class="alert-success" role="status"><%= @success %></p>
        <% end %>

        <section id="portfolio-create" class="workspace-section">
          <h2><%= gettext("Create portfolio") %></h2>
          <form id="portfolio-form" phx-submit="save_portfolio">
            <div class="form-grid">
              <label>
                <span><%= gettext("Name") %></span>
                <input name="portfolio[name]" value={@portfolio_form["name"]} required />
              </label>
              <label>
                <span><%= gettext("Base currency") %></span>
                <input name="portfolio[base_currency_code]" value={@portfolio_form["base_currency_code"]} maxlength="3" required />
              </label>
            </div>
            <label>
              <span><%= gettext("Notes") %></span>
              <textarea name="portfolio[notes]"><%= @portfolio_form["notes"] %></textarea>
            </label>
            <button type="submit"><%= gettext("Create portfolio") %></button>
          </form>
        </section>

        <%= if @current_portfolio do %>
          <section id="account-create" class="workspace-section">
            <%= if length(@portfolios) > 1 do %>
              <form id="target-portfolio-form" phx-change="select_portfolio">
                <label>
                  <span><%= gettext("Add to portfolio") %></span>
                  <select name="portfolio_id">
                    <%= for p <- @portfolios do %>
                      <option value={p.id} selected={p.id == @current_portfolio.id}>
                        <%= p.name %> (<%= p.base_currency_code %>)
                      </option>
                    <% end %>
                  </select>
                </label>
              </form>
            <% end %>
            <p class="muted" data-role="target-portfolio">
              <%= gettext("Adding to: %{name}", name: @current_portfolio.name) %>
            </p>
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
        <% end %>

        <section id="portfolio-list-panel" class="workspace-section">
          <h2><%= gettext("Current setup") %></h2>
          <div class="grid">
            <article>
              <h3><%= gettext("Portfolios") %></h3>
              <ul id="portfolio-list">
                <%= for portfolio <- @portfolios do %>
                  <li><%= portfolio.name %> (<%= portfolio.base_currency_code %>)</li>
                <% end %>
              </ul>
            </article>
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
      </div>
    </AppShell.shell>
    """
  end

  @impl true
  def handle_event("save_portfolio", %{"portfolio" => params}, socket) do
    case Portfolios.create_portfolio(params) do
      {:ok, _portfolio} ->
        {:noreply,
         socket
         |> assign(:portfolio_form, @portfolio_form)
         |> success(gettext("Portfolio created"))
         |> load_state()}

      {:error, changeset} ->
        {:noreply, failure(socket, changeset_error(changeset))}
    end
  end

  def handle_event("select_portfolio", %{"portfolio_id" => id}, socket) do
    {:noreply, load_state(socket, id)}
  end

  def handle_event(
        "save_cash_account",
        %{"cash_account" => _params},
        %{assigns: %{current_portfolio: nil}} = socket
      ) do
    {:noreply, failure(socket, gettext("Create a portfolio first"))}
  end

  def handle_event("save_cash_account", %{"cash_account" => params}, socket) do
    params = Map.put(params, "portfolio_id", socket.assigns.current_portfolio.id)

    case Portfolios.create_cash_account(params) do
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

  def handle_event(
        "save_securities_account",
        %{"securities_account" => _params},
        %{assigns: %{current_portfolio: nil}} = socket
      ) do
    {:noreply, failure(socket, gettext("Create a portfolio first"))}
  end

  def handle_event("save_securities_account", %{"securities_account" => params}, socket) do
    params = Map.put(params, "portfolio_id", socket.assigns.current_portfolio.id)

    case Portfolios.create_securities_account(params) do
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
         %{id: portfolio_id} <- socket.assigns.current_portfolio,
         true <- account.portfolio_id == portfolio_id,
         {:ok, _updated} <-
           Portfolios.update_cash_account(account, %{liquidity_role: role}) do
      {:noreply,
       socket
       |> success(gettext("Cash account updated"))
       |> load_state()}
    else
      _ -> {:noreply, failure(socket, gettext("Could not update cash account"))}
    end
  end

  defp load_state(socket, selected_id \\ nil) do
    portfolios = Portfolios.list_portfolios()

    current_portfolio =
      pick_portfolio(portfolios, selected_id, socket.assigns[:current_portfolio])

    cash_accounts =
      if current_portfolio do
        Portfolios.list_cash_accounts_for_portfolio(current_portfolio.id)
      else
        []
      end

    securities_accounts =
      if current_portfolio do
        Portfolios.list_securities_accounts_for_portfolio(current_portfolio.id)
      else
        []
      end

    assign(socket,
      portfolios: portfolios,
      current_portfolio: current_portfolio,
      cash_accounts: cash_accounts,
      securities_accounts: securities_accounts
    )
  end

  # Keep the user's chosen target portfolio across reloads; fall back to the
  # previously selected one, then to the first. Avoids silently retargeting
  # account/depot creation to whichever portfolio happens to be first (#490).
  defp pick_portfolio([], _selected_id, _previous), do: nil

  defp pick_portfolio(portfolios, selected_id, previous) do
    wanted = selected_id || (previous && previous.id)

    Enum.find(portfolios, fn p -> to_string(p.id) == to_string(wanted) end) ||
      List.first(portfolios)
  end

  defp success(socket, message), do: assign(socket, success: message, error: nil)
  defp failure(socket, message), do: assign(socket, error: message, success: nil)

  defp changeset_error(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {message, _opts}} -> "#{field} #{message}" end)
    |> Enum.join(", ")
  end
end
