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
      |> assign(:transaction_error, nil)
      |> assign(:transaction_success, nil)
      |> load_transaction_state()
      |> assign_default_transaction_form()

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <AppShell.shell current_path="/transactions">
      <header class="app-shell-page-header">
        <div>
          <p class="app-shell-page-kicker"><%= gettext("Ledger") %></p>
          <h1><%= gettext("Transactions") %></h1>
          <p><%= gettext("Record cash movements, trades and income while keeping transaction history easy to scan.") %></p>
        </div>
      </header>

      <%= if @current_portfolio do %>
        <section id="current-portfolio-selector" class="app-shell-section-card">
          <div class="app-shell-section-header">
            <div>
              <h2 class="app-shell-section-title"><%= gettext("Current portfolio") %></h2>
              <p><%= gettext("Select portfolio") %></p>
              <p class="app-shell-warning-note">
                <%= gettext("The current portfolio controls which transactions and positions are shown.") %>
              </p>
            </div>
          </div>

          <form
            id="current-portfolio-form"
            phx-change="select_current_portfolio"
            class="app-shell-form-grid"
          >
            <div class="app-shell-field app-shell-field--full">
              <label for="current-portfolio-select"><%= gettext("Current portfolio") %></label>
              <select id="current-portfolio-select" name="portfolio_id">
                <%= for portfolio <- @portfolios do %>
                  <option value={portfolio.id} selected={portfolio.id == @current_portfolio.id}>
                    <%= portfolio.name %>
                  </option>
                <% end %>
              </select>
            </div>
          </form>
        </section>
        <section id="ledger-kpis" class="app-shell-stat-grid" aria-label={gettext("Ledger summary")}>
          <div class="app-shell-stat-card">
            <span class="app-shell-stat-icon" aria-hidden="true">TX</span>
            <div>
              <span class="app-shell-stat-label"><%= gettext("Transactions") %></span>
              <span class="app-shell-stat-value"><%= Enum.count(@transactions) %></span>
              <span class="app-shell-stat-hint"><%= gettext("Ledger entries") %></span>
            </div>
          </div>
          <div class="app-shell-stat-card">
            <span class="app-shell-stat-icon" aria-hidden="true">POS</span>
            <div>
              <span class="app-shell-stat-label"><%= gettext("Positions") %></span>
              <span class="app-shell-stat-value"><%= Enum.count(@position_rows) %></span>
              <span class="app-shell-stat-hint"><%= gettext("Derived from trades") %></span>
            </div>
          </div>
          <div class="app-shell-stat-card">
            <span class="app-shell-stat-icon" aria-hidden="true">DA</span>
            <div>
              <span class="app-shell-stat-label"><%= gettext("Deposit accounts") %></span>
              <span class="app-shell-stat-value"><%= Enum.count(@deposit_accounts) %></span>
              <span class="app-shell-stat-hint"><%= gettext("Available for cash") %></span>
            </div>
          </div>
          <div class="app-shell-stat-card">
            <span class="app-shell-stat-icon" aria-hidden="true">SA</span>
            <div>
              <span class="app-shell-stat-label"><%= gettext("Securities accounts") %></span>
              <span class="app-shell-stat-value"><%= Enum.count(@securities_accounts) %></span>
              <span class="app-shell-stat-hint"><%= gettext("Available for trades") %></span>
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
                  <h2 class="app-shell-section-title"><%= gettext("Transaction history") %></h2>
                  <p><%= gettext("Newest ledger entries appear first.") %></p>
                </div>
                <span class="app-shell-badge app-shell-badge--accent">
                  <%= ngettext("%{count} entry", "%{count} entries", Enum.count(@transactions), count: Enum.count(@transactions)) %>
                </span>
              </div>

              <%= if Enum.empty?(@transactions) do %>
                <div id="no-transactions" class="app-shell-empty-state">
                  <h3><%= gettext("No transactions yet") %></h3>
                  <p><%= gettext("Record the first ledger transaction.") %></p>
                </div>
              <% else %>
                <div class="app-shell-table-wrapper">
                  <table id="transaction-list">
                    <thead>
                      <tr>
                        <th><%= gettext("Date") %></th>
                        <th><%= gettext("Type") %></th>
                        <th><%= gettext("Account") %></th>
                        <th><%= gettext("Security") %></th>
                        <th><%= gettext("Quantity") %></th>
                        <th><%= gettext("Price") %></th>
                        <th><%= gettext("Amount") %></th>
                        <th><%= gettext("Currency") %></th>
                        <th><%= gettext("Notes") %></th>
                      </tr>
                    </thead>
                    <tbody>
                      <%= for transaction <- @transactions do %>
                        <tr>
                          <td><%= transaction.date %></td>
                          <td><span class="app-shell-badge"><%= transaction_type_label(transaction.type) %></span></td>
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
                  <h2 class="app-shell-section-title"><%= gettext("Positions overview") %></h2>
                  <p><%= gettext("Quantity summary derived from buy and sell transactions.") %></p>
                </div>
                <span class="app-shell-badge"><%= ngettext("%{count} position", "%{count} positions", Enum.count(@position_rows), count: Enum.count(@position_rows)) %></span>
              </div>

              <%= if Enum.empty?(@position_rows) do %>
                <div id="no-positions" class="app-shell-empty-state">
                  <h3><%= gettext("No positions yet") %></h3>
                  <p><%= gettext("Positions are derived from buy and sell transactions.") %></p>
                </div>
              <% else %>
                <div class="app-shell-table-wrapper">
                  <table id="position-list">
                    <thead>
                      <tr>
                        <th><%= gettext("Securities account") %></th>
                        <th><%= gettext("Security") %></th>
                        <th><%= gettext("Quantity") %></th>
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
                <h2 class="app-shell-section-title"><%= gettext("Add transaction") %></h2>
                <p class="app-shell-panel-intro">
                  <%= gettext("Use deposit transactions for cash movements. Use buy, sell and dividend for security-related ledger activity.") %>
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
                <legend><%= gettext("Transaction") %></legend>
                <div class="app-shell-fieldset-grid">
                  <div class="app-shell-field">
                    <label for="transaction-type"><%= gettext("Type") %></label>
                    <select id="transaction-type" name="transaction[type]">
                      <%= for type <- @transaction_types do %>
                        <option value={type} selected={type == @transaction_form["type"]}>
                          <%= transaction_type_label(type) %>
                        </option>
                      <% end %>
                    </select>
                  </div>

                  <div class="app-shell-field">
                    <label for="transaction-date"><%= gettext("Date") %></label>
                    <input
                      id="transaction-date"
                      type="date"
                      name="transaction[date]"
                      value={@transaction_form["date"]}
                    />
                  </div>

                  <div class="app-shell-field">
                    <label for="transaction-currency"><%= gettext("Currency") %></label>
                    <select id="transaction-currency" name="transaction[currency_code]">
                      <option value=""><%= gettext("Select currency") %></option>
                      <%= for currency <- @currencies do %>
                        <option
                          value={currency.code}
                          selected={currency.code == @transaction_form["currency_code"]}
                        >
                          <%= currency_option_label(currency) %>
                        </option>
                      <% end %>
                    </select>
                  </div>

                  <div class="app-shell-field">
                    <label for="transaction-amount"><%= gettext("Amount") %></label>
                    <input
                      id="transaction-amount"
                      name="transaction[amount]"
                      value={@transaction_form["amount"]}
                    />
                  </div>
                </div>
              </fieldset>

              <fieldset class="app-shell-fieldset">
                <legend><%= gettext("Accounts") %></legend>
                <div class="app-shell-fieldset-grid">
                  <div class="app-shell-field">
                    <label for="transaction-deposit-account"><%= gettext("Deposit account") %></label>
                    <select id="transaction-deposit-account" name="transaction[deposit_account_id]">
                      <option value=""><%= gettext("None") %></option>
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
                    <label for="transaction-securities-account"><%= gettext("Securities account") %></label>
                    <select id="transaction-securities-account" name="transaction[securities_account_id]">
                      <option value=""><%= gettext("None") %></option>
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
                <legend><%= gettext("Security details") %></legend>
                <div class="app-shell-fieldset-grid">
                  <div class="app-shell-field app-shell-field--full">
                    <label for="transaction-security"><%= gettext("Security") %></label>
                    <select id="transaction-security" name="transaction[security_id]">
                      <option value=""><%= gettext("None") %></option>
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
                    <label for="transaction-quantity"><%= gettext("Quantity") %></label>
                    <input
                      id="transaction-quantity"
                      name="transaction[quantity]"
                      value={@transaction_form["quantity"]}
                    />
                  </div>

                  <div class="app-shell-field">
                    <label for="transaction-price"><%= gettext("Price") %></label>
                    <input
                      id="transaction-price"
                      name="transaction[price]"
                      value={@transaction_form["price"]}
                    />
                  </div>

                  <div class="app-shell-field">
                    <label for="transaction-fees"><%= gettext("Fees (optional)") %></label>
                    <input id="transaction-fees" name="transaction[fees]" value={@transaction_form["fees"]} />
                  </div>

                  <div class="app-shell-field">
                    <label for="transaction-taxes"><%= gettext("Taxes (optional)") %></label>
                    <input id="transaction-taxes" name="transaction[taxes]" value={@transaction_form["taxes"]} />
                  </div>
                </div>
              </fieldset>

              <div class="app-shell-field app-shell-field--full">
                <label for="transaction-notes"><%= gettext("Notes (optional)") %></label>
                <textarea id="transaction-notes" rows="2" name="transaction[notes]"><%= @transaction_form["notes"] %></textarea>
              </div>

              <div class="app-shell-form-actions">
                <button type="submit" class="app-shell-primary"><%= gettext("Create transaction") %></button>
              </div>
            </form>
            </section>
          </div>
        </div>
      <% else %>
        <section
          id="transaction-first-run"
          class="app-shell-section-card app-shell-onboarding app-shell-onboarding--compact"
        >
          <p class="app-shell-page-kicker"><%= gettext("First run") %></p>
          <h2><%= gettext("Create a portfolio first") %></h2>
          <p>
            <%= gettext("Transactions need a portfolio, accounts and securities before they can be recorded.") %>
          </p>
          <div class="app-shell-onboarding-actions">
            <a href="/accounts" class="app-shell-button app-shell-primary"><%= gettext("Go to Accounts") %></a>
          </div>
        </section>
      <% end %>
    </AppShell.shell>
    """
  end

  def handle_event("create_transaction", %{"transaction" => params}, socket) do
    portfolio_id = Map.get(socket.assigns.current_portfolio || %{}, :id)

    transaction_params =
      params
      |> sanitize_transaction_params()
      |> Map.put("portfolio_id", portfolio_id)

    case Ledger.create_transaction(transaction_params) do
      {:ok, _transaction} ->
        socket =
          socket
          |> assign(:transaction_error, nil)
          |> assign(:transaction_success, gettext("Transaction created."))
          |> load_transaction_state()
          |> assign_default_transaction_form()

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:transaction_form, Map.merge(@transaction_form_defaults, params))
         |> assign(:transaction_error, format_errors(changeset))
         |> assign(:transaction_success, nil)
         |> load_transaction_state()}
    end
  end

  def handle_event("select_current_portfolio", %{"portfolio_id" => selected_portfolio_id}, socket) do
    {:noreply, load_transaction_state(socket, selected_portfolio_id)}
  end

  def handle_event("select_current_portfolio", _params, socket) do
    {:noreply, load_transaction_state(socket, Map.get(socket.assigns, :current_portfolio))}
  end

  defp load_transaction_state(socket, selected_portfolio_id \\ nil) do
    portfolios = Portfolios.list_portfolios()

    current_portfolio =
      resolve_current_portfolio(
        portfolios,
        selected_portfolio_id,
        Map.get(socket.assigns, :current_portfolio)
      )

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
    |> assign(:portfolios, portfolios)
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

  defp resolve_current_portfolio(portfolios, nil, previous_portfolio) do
    previous_portfolio || List.first(portfolios)
  end

  defp resolve_current_portfolio(portfolios, selected_portfolio_id, previous_portfolio) do
    selected_portfolio = Portfolios.get_portfolio(selected_portfolio_id)

    cond do
      selected_portfolio ->
        selected_portfolio

      previous_portfolio && Enum.any?(portfolios, &(&1.id == previous_portfolio.id)) ->
        previous_portfolio

      true ->
        List.first(portfolios)
    end
  end

  defp assign_default_transaction_form(socket) do
    assign(
      socket,
      :transaction_form,
      default_transaction_form(socket.assigns.current_portfolio, socket.assigns.currencies)
    )
  end

  defp default_transaction_form(current_portfolio, currencies) do
    currency_code =
      cond do
        current_portfolio -> current_portfolio.base_currency_code
        Enum.any?(currencies, &(&1.code == "EUR")) -> "EUR"
        currency = List.first(currencies) -> currency.code
        true -> ""
      end

    Map.put(@transaction_form_defaults, "currency_code", currency_code)
  end

  defp currency_option_label(currency) do
    "#{currency.code} - #{currency.name}"
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

  defp transaction_type_label("deposit"), do: gettext("Deposit")
  defp transaction_type_label("withdrawal"), do: gettext("Withdrawal")
  defp transaction_type_label("buy"), do: gettext("Buy")
  defp transaction_type_label("sell"), do: gettext("Sell")
  defp transaction_type_label("dividend"), do: gettext("Dividend")
  defp transaction_type_label(type), do: type

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
