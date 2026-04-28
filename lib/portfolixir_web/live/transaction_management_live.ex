defmodule PortfolixirWeb.TransactionManagementLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias PortfolixirWeb.AppShell

  @transaction_types ["deposit", "withdrawal", "buy", "sell", "dividend"]

  @transaction_form_defaults %{
    "type" => "deposit",
    "date" => "",
    "currency_code" => "",
    "amount" => "",
    "deposit_account_id" => "",
    "securities_account_id" => "",
    "security_id" => "",
    "quantity" => "",
    "price" => "",
    "fees" => "",
    "taxes" => "",
    "notes" => ""
  }

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:transaction_form, @transaction_form_defaults)
      |> assign(:transaction_error, nil)
      |> assign(:transaction_success, nil)
      |> load_transaction_state()

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <AppShell.shell current_path="/transactions">
      <header class="app-shell-page-header">
        <div>
          <p class="app-shell-page-kicker">Ledger</p>
          <h1>Transactions</h1>
          <p>Record cash movements, trades and income while keeping transaction history easy to scan.</p>
        </div>
      </header>

      <%= if @current_portfolio do %>
        <section id="ledger-kpis" class="app-shell-stat-grid" aria-label="Ledger summary">
          <div class="app-shell-stat-card">
            <span class="app-shell-stat-icon" aria-hidden="true">TX</span>
            <div>
              <span class="app-shell-stat-label">Transactions</span>
              <span class="app-shell-stat-value"><%= Enum.count(@transactions) %></span>
              <span class="app-shell-stat-hint">Ledger entries</span>
            </div>
          </div>
          <div class="app-shell-stat-card">
            <span class="app-shell-stat-icon" aria-hidden="true">POS</span>
            <div>
              <span class="app-shell-stat-label">Positions</span>
              <span class="app-shell-stat-value"><%= Enum.count(@position_rows) %></span>
              <span class="app-shell-stat-hint">Derived from trades</span>
            </div>
          </div>
          <div class="app-shell-stat-card">
            <span class="app-shell-stat-icon" aria-hidden="true">DA</span>
            <div>
              <span class="app-shell-stat-label">Deposit accounts</span>
              <span class="app-shell-stat-value"><%= Enum.count(@deposit_accounts) %></span>
              <span class="app-shell-stat-hint">Available for cash</span>
            </div>
          </div>
          <div class="app-shell-stat-card">
            <span class="app-shell-stat-icon" aria-hidden="true">SA</span>
            <div>
              <span class="app-shell-stat-label">Securities accounts</span>
              <span class="app-shell-stat-value"><%= Enum.count(@securities_accounts) %></span>
              <span class="app-shell-stat-hint">Available for trades</span>
            </div>
          </div>
        </section>

        <div id="ledger-workspace" class="app-shell-workspace-grid">
          <div class="app-shell-workspace-stack" data-priority="primary">
            <section
              id="transaction-history-panel"
              class="app-shell-section-card"
              data-priority="primary"
            >
              <div class="app-shell-section-header">
                <div>
                  <h2 class="app-shell-section-title">Transaction history</h2>
                  <p>Newest ledger entries appear first.</p>
                </div>
                <span class="app-shell-badge app-shell-badge--accent">
                  <%= Enum.count(@transactions) %> entries
                </span>
              </div>

              <%= if Enum.empty?(@transactions) do %>
                <div id="no-transactions" class="app-shell-empty-state">
                  <h3>No transactions yet</h3>
                  <p>Record the first ledger transaction.</p>
                </div>
              <% else %>
                <div class="app-shell-table-wrapper">
                  <table id="transaction-list">
                    <thead>
                      <tr>
                        <th>Date</th>
                        <th>Type</th>
                        <th>Account</th>
                        <th>Security</th>
                        <th>Quantity</th>
                        <th>Price</th>
                        <th>Amount</th>
                        <th>Currency</th>
                        <th>Notes</th>
                      </tr>
                    </thead>
                    <tbody>
                      <%= for transaction <- @transactions do %>
                        <tr>
                          <td><%= transaction.date %></td>
                          <td><span class="app-shell-badge"><%= transaction.type %></span></td>
                          <td><%= account_name(transaction, @deposit_account_names, @securities_account_names) %></td>
                          <td><%= security_name(transaction.security_id, @security_names) %></td>
                          <td><%= format_quantity(transaction.quantity) %></td>
                          <td><%= format_money(transaction.price) %></td>
                          <td><%= format_money(transaction.amount) %></td>
                          <td><%= transaction.currency_code %></td>
                          <td><%= transaction.notes || "—" %></td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              <% end %>
            </section>
          </div>

          <div class="app-shell-workspace-stack" data-priority="secondary">
            <section id="positions" class="app-shell-section-card" data-priority="secondary">
              <div class="app-shell-section-header">
                <div>
                  <h2 class="app-shell-section-title">Positions overview</h2>
                  <p>Quantity summary derived from buy and sell transactions.</p>
                </div>
                <span class="app-shell-badge"><%= Enum.count(@position_rows) %> positions</span>
              </div>

              <%= if Enum.empty?(@position_rows) do %>
                <div id="no-positions" class="app-shell-empty-state">
                  <h3>No positions yet</h3>
                  <p>Positions are derived from buy and sell transactions.</p>
                </div>
              <% else %>
                <div class="app-shell-table-wrapper">
                  <table id="position-list">
                    <thead>
                      <tr>
                        <th>Securities account</th>
                        <th>Security</th>
                        <th>Quantity</th>
                      </tr>
                    </thead>
                    <tbody>
                      <%= for row <- @position_rows do %>
                        <tr>
                          <td><%= row.securities_account_name %></td>
                          <td><%= row.security_name %></td>
                          <td><%= format_quantity(row.quantity) %></td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              <% end %>
            </section>

            <section
              id="transaction-form-panel"
              class="app-shell-section-card"
              data-priority="secondary"
            >
            <div class="app-shell-section-header">
              <div>
                <h2 class="app-shell-section-title">Add transaction</h2>
                <p class="app-shell-panel-intro">
                  Use deposit transactions for cash movements. Use buy, sell and dividend for security-related ledger activity.
                </p>
              </div>
            </div>

            <%= if @transaction_success do %>
              <p
                id="transaction-form-success"
                class="app-shell-alert app-shell-alert--success"
                role="status"
                aria-live="polite"
              >
                <%= @transaction_success %>
              </p>
            <% end %>

            <%= if @transaction_error do %>
              <p id="transaction-form-error" class="app-shell-alert app-shell-alert--error" role="alert">
                <%= @transaction_error %>
              </p>
            <% end %>

            <form id="transaction-form" class="app-shell-form-grid" phx-submit="create_transaction">
              <fieldset class="app-shell-fieldset">
                <legend>Transaction</legend>
                <div class="app-shell-fieldset-grid">
                  <div class="app-shell-field">
                    <label for="transaction-type">Type</label>
                    <select id="transaction-type" name="transaction[type]">
                      <%= for type <- @transaction_types do %>
                        <option value={type} selected={type == @transaction_form["type"]}>
                          <%= type %>
                        </option>
                      <% end %>
                    </select>
                  </div>

                  <div class="app-shell-field">
                    <label for="transaction-date">Date</label>
                    <input
                      id="transaction-date"
                      type="date"
                      name="transaction[date]"
                      value={@transaction_form["date"]}
                    />
                  </div>

                  <div class="app-shell-field">
                    <label for="transaction-currency">Currency</label>
                    <select id="transaction-currency" name="transaction[currency_code]">
                      <option value="">Select currency</option>
                      <%= for currency <- @currencies do %>
                        <option
                          value={currency.code}
                          selected={currency.code == @transaction_form["currency_code"]}
                        >
                          <%= currency.code %>
                        </option>
                      <% end %>
                    </select>
                  </div>

                  <div class="app-shell-field">
                    <label for="transaction-amount">Amount</label>
                    <input
                      id="transaction-amount"
                      name="transaction[amount]"
                      value={@transaction_form["amount"]}
                    />
                  </div>
                </div>
              </fieldset>

              <fieldset class="app-shell-fieldset">
                <legend>Accounts</legend>
                <div class="app-shell-fieldset-grid">
                  <div class="app-shell-field">
                    <label for="transaction-deposit-account">Deposit account</label>
                    <select id="transaction-deposit-account" name="transaction[deposit_account_id]">
                      <option value="">None</option>
                      <%= for account <- @deposit_accounts do %>
                        <option
                          value={account.id}
                          selected={"#{account.id}" == @transaction_form["deposit_account_id"]}
                        >
                          <%= account.name %>
                        </option>
                      <% end %>
                    </select>
                  </div>

                  <div class="app-shell-field">
                    <label for="transaction-securities-account">Securities account</label>
                    <select id="transaction-securities-account" name="transaction[securities_account_id]">
                      <option value="">None</option>
                      <%= for account <- @securities_accounts do %>
                        <option
                          value={account.id}
                          selected={"#{account.id}" == @transaction_form["securities_account_id"]}
                        >
                          <%= account.name %>
                        </option>
                      <% end %>
                    </select>
                  </div>
                </div>
              </fieldset>

              <fieldset class="app-shell-fieldset">
                <legend>Security details</legend>
                <div class="app-shell-fieldset-grid">
                  <div class="app-shell-field app-shell-field--full">
                    <label for="transaction-security">Security</label>
                    <select id="transaction-security" name="transaction[security_id]">
                      <option value="">None</option>
                      <%= for security <- @securities do %>
                        <option
                          value={security.id}
                          selected={"#{security.id}" == @transaction_form["security_id"]}
                        >
                          <%= security.name %>
                        </option>
                      <% end %>
                    </select>
                  </div>

                  <div class="app-shell-field">
                    <label for="transaction-quantity">Quantity</label>
                    <input
                      id="transaction-quantity"
                      name="transaction[quantity]"
                      value={@transaction_form["quantity"]}
                    />
                  </div>

                  <div class="app-shell-field">
                    <label for="transaction-price">Price</label>
                    <input
                      id="transaction-price"
                      name="transaction[price]"
                      value={@transaction_form["price"]}
                    />
                  </div>

                  <div class="app-shell-field">
                    <label for="transaction-fees">Fees (optional)</label>
                    <input id="transaction-fees" name="transaction[fees]" value={@transaction_form["fees"]} />
                  </div>

                  <div class="app-shell-field">
                    <label for="transaction-taxes">Taxes (optional)</label>
                    <input id="transaction-taxes" name="transaction[taxes]" value={@transaction_form["taxes"]} />
                  </div>
                </div>
              </fieldset>

              <div class="app-shell-field app-shell-field--full">
                <label for="transaction-notes">Notes (optional)</label>
                <textarea id="transaction-notes" rows="2" name="transaction[notes]"><%= @transaction_form["notes"] %></textarea>
              </div>

              <div class="app-shell-form-actions">
                <button type="submit" class="app-shell-primary">Create transaction</button>
              </div>
            </form>
            </section>
          </div>
        </div>
      <% else %>
        <section id="transaction-empty-portfolio" class="app-shell-section-card app-shell-section-card--compact">
          <div id="no-portfolio" class="app-shell-empty-state">
            <h3>No portfolio yet</h3>
            <p>Create a portfolio first.</p>
          </div>
        </section>
      <% end %>
    </AppShell.shell>
    """
  end

  def handle_event("create_transaction", %{"transaction" => params}, socket) do
    portfolio_id = socket.assigns.current_portfolio.id

    transaction_params =
      params
      |> sanitize_transaction_params()
      |> Map.put("portfolio_id", portfolio_id)

    case Ledger.create_transaction(transaction_params) do
      {:ok, _transaction} ->
        {:noreply,
         socket
         |> assign(:transaction_form, @transaction_form_defaults)
         |> assign(:transaction_error, nil)
         |> assign(:transaction_success, "Transaction created.")
         |> load_transaction_state()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:transaction_form, Map.merge(@transaction_form_defaults, params))
         |> assign(:transaction_error, format_errors(changeset))
         |> assign(:transaction_success, nil)
         |> load_transaction_state()}
    end
  end

  defp load_transaction_state(socket) do
    current_portfolio = Portfolios.first_portfolio()

    deposit_accounts =
      if current_portfolio do
        Portfolios.list_deposit_accounts_for_portfolio(current_portfolio.id)
      else
        []
      end

    securities_accounts =
      if current_portfolio do
        Portfolios.list_securities_accounts_for_portfolio(current_portfolio.id)
      else
        []
      end

    transactions =
      if current_portfolio do
        Ledger.list_transactions_for_portfolio(current_portfolio.id)
      else
        []
      end

    positions =
      if current_portfolio do
        Ledger.positions_for_portfolio(current_portfolio.id)
      else
        %{}
      end

    securities = Catalog.list_securities()
    deposit_account_names = name_lookup(deposit_accounts)
    securities_account_names = name_lookup(securities_accounts)
    security_names = name_lookup(securities)

    socket
    |> assign(:current_portfolio, current_portfolio)
    |> assign(:currencies, Catalog.list_currencies())
    |> assign(:deposit_accounts, deposit_accounts)
    |> assign(:securities_accounts, securities_accounts)
    |> assign(:securities, securities)
    |> assign(:transactions, transactions)
    |> assign(:position_rows, position_rows(positions, securities_account_names, security_names))
    |> assign(:transaction_types, @transaction_types)
    |> assign(:deposit_account_names, deposit_account_names)
    |> assign(:securities_account_names, securities_account_names)
    |> assign(:security_names, security_names)
  end

  defp sanitize_transaction_params(params) when is_map(params) do
    params
    |> Map.new(fn {key, value} -> {key, value} end)
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      Map.put(acc, key, empty_string_to_nil(value))
    end)
  end

  defp empty_string_to_nil(""), do: nil
  defp empty_string_to_nil(value), do: value

  defp name_lookup(records) do
    Map.new(records, &{&1.id, &1.name})
  end

  defp position_rows(positions, securities_account_names, security_names) do
    positions
    |> Enum.map(fn {{securities_account_id, security_id}, quantity} ->
      %{
        securities_account_name: Map.get(securities_account_names, securities_account_id, "—"),
        security_name: Map.get(security_names, security_id, "—"),
        quantity: quantity
      }
    end)
    |> Enum.sort_by(&{&1.securities_account_name, &1.security_name})
  end

  defp account_name(transaction, deposit_account_names, securities_account_names) do
    cond do
      transaction.deposit_account_id ->
        Map.get(deposit_account_names, transaction.deposit_account_id, "—")

      transaction.securities_account_id ->
        Map.get(securities_account_names, transaction.securities_account_id, "—")

      true ->
        "—"
    end
  end

  defp security_name(nil, _security_names), do: "—"

  defp security_name(security_id, security_names) do
    Map.get(security_names, security_id, "—")
  end

  defp format_money(nil), do: "—"

  defp format_money(decimal) do
    decimal
    |> Decimal.round(2)
    |> Decimal.to_string(:normal)
  end

  defp format_quantity(nil), do: "—"

  defp format_quantity(decimal) do
    decimal
    |> Decimal.round(2)
    |> Decimal.to_string(:normal)
  end

  defp format_errors(%Ecto.Changeset{} = changeset) do
    changeset.errors
    |> Enum.map_join(", ", fn {field, {message, opts}} ->
      "#{Phoenix.Naming.humanize(field)} #{interpolate_error(message, opts)}"
    end)
  end

  defp interpolate_error(message, opts) do
    Enum.reduce(opts, message, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end
end
