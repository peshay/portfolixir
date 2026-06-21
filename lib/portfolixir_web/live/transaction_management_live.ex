defmodule PortfolixirWeb.TransactionManagementLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias PortfolixirWeb.AppShell

  @transaction_form %{
    "type" => "buy",
    "date" => "",
    "securities_account_id" => "",
    "security_id" => "",
    "quantity" => "",
    "price" => "",
    "fees" => "0",
    "taxes" => "0",
    "currency_code" => "EUR",
    "notes" => ""
  }

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:transaction_form, @transaction_form)
     |> assign(:error, nil)
     |> assign(:success, nil)
     |> load_state()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell
      current_path="/transactions"
      page_title={gettext("Transactions")}
      page_subtitle={gettext("Manual buy and sell ledger")}
    >
      <div id="transactions-workspace" class="workspace-page">
        <%= if @error do %>
          <p class="alert-error" role="alert"><%= @error %></p>
        <% end %>
        <%= if @success do %>
          <p class="alert-success" role="status"><%= @success %></p>
        <% end %>

        <%= if @current_portfolio do %>
          <div
            id="transaction-portfolio-strip"
            class="view-switcher"
            role="group"
            aria-label={gettext("Active portfolio")}
          >
            <span class="view-switcher__label"><%= gettext("Portfolio:") %></span>
            <nav class="view-switcher__options">
              <%= for portfolio <- @portfolios do %>
                <button
                  type="button"
                  id={"portfolio-switch-#{portfolio.id}"}
                  class={[
                    "view-chip",
                    portfolio.id == @current_portfolio.id && "is-active"
                  ]}
                  phx-click="select_portfolio"
                  phx-value-id={portfolio.id}
                  aria-current={if portfolio.id == @current_portfolio.id, do: "true", else: nil}
                >
                  <%= portfolio.name %> (<%= portfolio.base_currency_code %>)
                </button>
              <% end %>
            </nav>
          </div>

          <section id="transaction-create" class="workspace-section">
            <h2><%= gettext("Record transaction") %></h2>
            <form id="transaction-form" phx-submit="save_transaction">
              <div class="form-grid">
                <label>
                  <span><%= gettext("Type") %></span>
                  <select name="transaction[type]">
                    <%= for type <- ["buy", "sell"] do %>
                      <option value={type} selected={type == @transaction_form["type"]}><%= type %></option>
                    <% end %>
                  </select>
                </label>
                <label>
                  <span><%= gettext("Date") %></span>
                  <input type="date" name="transaction[date]" value={@transaction_form["date"]} required />
                </label>
                <label>
                  <span><%= gettext("Depot") %></span>
                  <select name="transaction[securities_account_id]" required>
                    <option value=""><%= gettext("Select depot") %></option>
                    <%= for account <- @securities_accounts do %>
                      <option value={account.id}>
                        <%= account.name %> -> <%= linked_cash_account_name(account) %>
                      </option>
                    <% end %>
                  </select>
                </label>
                <p class="form-help">
                  <%= gettext("Linked cash account is derived from the selected depot.") %>
                </p>
                <label>
                  <span><%= gettext("Security") %></span>
                  <select name="transaction[security_id]" required>
                    <option value=""><%= gettext("Select security") %></option>
                    <%= for security <- @securities do %>
                      <option value={security.id}><%= security.name %> (<%= security.ticker_symbol %>)</option>
                    <% end %>
                  </select>
                </label>
                <label>
                  <span><%= gettext("Quantity") %></span>
                  <input name="transaction[quantity]" value={@transaction_form["quantity"]} inputmode="decimal" required />
                </label>
                <label>
                  <span><%= gettext("Price") %></span>
                  <input name="transaction[price]" value={@transaction_form["price"]} inputmode="decimal" required />
                </label>
                <label>
                  <span><%= gettext("Fees") %></span>
                  <input name="transaction[fees]" value={@transaction_form["fees"]} inputmode="decimal" />
                </label>
                <label>
                  <span><%= gettext("Taxes") %></span>
                  <input name="transaction[taxes]" value={@transaction_form["taxes"]} inputmode="decimal" />
                </label>
                <label>
                  <span><%= gettext("Currency") %></span>
                  <input name="transaction[currency_code]" value={@transaction_form["currency_code"]} maxlength="3" required />
                </label>
              </div>
              <label>
                <span><%= gettext("Notes") %></span>
                <textarea name="transaction[notes]"><%= @transaction_form["notes"] %></textarea>
              </label>
              <button type="submit"><%= gettext("Record transaction") %></button>
            </form>
          </section>
        <% else %>
          <section id="transaction-setup-empty" class="empty-state" role="status">
            <%= gettext("Create a portfolio and linked accounts before recording transactions.") %>
          </section>
        <% end %>

        <section id="holdings-panel" class="workspace-section">
          <h2><%= gettext("Current holdings") %></h2>
          <%= if Enum.empty?(@position_rows) do %>
            <div id="no-holdings" class="empty-state" role="status">
              <%= gettext("No holdings yet") %>
            </div>
          <% else %>
            <table id="holdings-table">
              <thead>
                <tr>
                  <th><%= gettext("Depot") %></th>
                  <th><%= gettext("Security") %></th>
                  <th><%= gettext("Quantity") %></th>
                </tr>
              </thead>
              <tbody>
                <%= for row <- @position_rows do %>
                  <tr>
                    <td><%= row.securities_account_name %></td>
                    <td><%= row.security_name %></td>
                    <td><%= format_decimal(row.quantity) %></td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          <% end %>
        </section>

        <section id="transaction-list-panel" class="workspace-section">
          <h2><%= gettext("Transaction history") %></h2>
          <%= if Enum.empty?(@transactions) do %>
            <div id="no-transactions" class="empty-state" role="status">
              <%= gettext("No transactions yet") %>
            </div>
          <% else %>
            <table id="transaction-list">
              <thead>
                <tr>
                  <th><%= gettext("Date") %></th>
                  <th><%= gettext("Type") %></th>
                  <th><%= gettext("Security") %></th>
                  <th><%= gettext("Quantity") %></th>
                  <th><%= gettext("Price") %></th>
                  <th><%= gettext("Currency") %></th>
                </tr>
              </thead>
              <tbody>
                <%= for transaction <- @transactions do %>
                  <tr>
                    <td><%= transaction.date %></td>
                    <td><%= transaction.type %></td>
                    <td><%= transaction.security && transaction.security.name %></td>
                    <td><%= format_decimal(transaction.quantity) %></td>
                    <td><%= format_decimal(transaction.price) %></td>
                    <td><%= transaction.currency_code %></td>
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
  def handle_event(
        "save_transaction",
        %{"transaction" => _params},
        %{assigns: %{current_portfolio: nil}} = socket
      ) do
    {:noreply, failure(socket, gettext("Create a portfolio first"))}
  end

  def handle_event("select_portfolio", %{"id" => id}, socket) do
    socket =
      case Integer.parse(to_string(id)) do
        {portfolio_id, ""} ->
          case Enum.find(socket.assigns.portfolios, &(&1.id == portfolio_id)) do
            nil -> socket
            portfolio -> assign(socket, :current_portfolio, portfolio)
          end

        _ ->
          socket
      end

    {:noreply, socket |> assign(:transaction_form, @transaction_form) |> load_state()}
  end

  def handle_event("save_transaction", %{"transaction" => params}, socket) do
    params = Map.put(params, "portfolio_id", socket.assigns.current_portfolio.id)

    case Ledger.create_transaction(params) do
      {:ok, _transaction} ->
        {:noreply,
         socket
         |> assign(:transaction_form, @transaction_form)
         |> success(gettext("Transaction recorded"))
         |> load_state()}

      {:error, changeset} ->
        {:noreply,
         socket |> assign(:transaction_form, params) |> failure(changeset_error(changeset))}
    end
  end

  defp load_state(socket) do
    portfolios = Portfolios.list_portfolios()
    current_portfolio = resolve_current_portfolio(portfolios, socket.assigns[:current_portfolio])
    securities = Catalog.list_securities()

    {securities_accounts, transactions, position_rows} =
      if current_portfolio do
        securities_accounts =
          Portfolios.list_securities_accounts_for_portfolio(current_portfolio.id)

        transactions = Ledger.list_transactions_for_portfolio(current_portfolio.id)

        position_rows =
          current_portfolio.id
          |> Ledger.positions_for_portfolio()
          |> position_rows(securities_accounts, securities)

        {securities_accounts, transactions, position_rows}
      else
        {[], [], []}
      end

    assign(socket,
      portfolios: portfolios,
      current_portfolio: current_portfolio,
      securities_accounts: securities_accounts,
      securities: securities,
      transactions: transactions,
      position_rows: position_rows
    )
  end

  # Keep the user's chosen portfolio across reloads (after a save or a switch);
  # fall back to the first portfolio on initial mount or if the selection is gone.
  defp resolve_current_portfolio(portfolios, %{id: id}) do
    Enum.find(portfolios, List.first(portfolios), &(&1.id == id))
  end

  defp resolve_current_portfolio(portfolios, _), do: List.first(portfolios)

  defp position_rows(positions, securities_accounts, securities) do
    securities_account_names = Map.new(securities_accounts, &{&1.id, &1.name})
    security_names = Map.new(securities, &{&1.id, "#{&1.name} (#{&1.ticker_symbol})"})

    positions
    |> Enum.map(fn {{securities_account_id, security_id}, quantity} ->
      %{
        securities_account_name:
          Map.get(securities_account_names, securities_account_id, gettext("Unknown depot")),
        security_name: Map.get(security_names, security_id, gettext("Unknown security")),
        quantity: quantity
      }
    end)
    |> Enum.sort_by(fn row -> {row.securities_account_name, row.security_name} end)
  end

  defp format_decimal(nil), do: ""
  defp format_decimal(decimal), do: Decimal.to_string(decimal, :normal)

  defp linked_cash_account_name(%{cash_account: %{name: name}}), do: name
  defp linked_cash_account_name(_account), do: gettext("Missing linked cash account")

  defp success(socket, message), do: assign(socket, success: message, error: nil)
  defp failure(socket, message), do: assign(socket, error: message, success: nil)

  defp changeset_error(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {message, _opts}} -> "#{field} #{message}" end)
    |> Enum.join(", ")
  end
end
