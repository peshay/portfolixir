defmodule PortfolixirWeb.AccountManagementLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias PortfolixirWeb.AppShell

  @portfolio_form_defaults %{
    "name" => "",
    "base_currency_code" => "",
    "description" => ""
  }

  @deposit_account_form_defaults %{
    "name" => "",
    "currency_code" => "",
    "notes" => ""
  }

  @securities_account_form_defaults %{
    "name" => "",
    "currency_code" => "",
    "reference_deposit_account_id" => "",
    "notes" => ""
  }

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:portfolio_form, @portfolio_form_defaults)
      |> assign(:deposit_account_form, @deposit_account_form_defaults)
      |> assign(:securities_account_form, @securities_account_form_defaults)
      |> assign(:portfolio_error, nil)
      |> assign(:portfolio_success, nil)
      |> assign(:deposit_account_error, nil)
      |> assign(:deposit_account_success, nil)
      |> assign(:securities_account_error, nil)
      |> assign(:securities_account_success, nil)
      |> load_account_state()

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <AppShell.shell current_path="/accounts">
      <header class="app-shell-page-header">
        <div>
          <p class="app-shell-page-kicker">Master data</p>
          <h1>Accounts</h1>
          <p>Organize the portfolio, cash accounts and securities accounts that ledger activity posts to.</p>
        </div>
      </header>

      <div id="account-workspace" class="app-shell-workspace-grid">
        <div class="app-shell-workspace-stack" data-priority="primary">
          <section id="account-overview" class="app-shell-section-card">
            <div class="app-shell-section-header">
              <div>
                <h2 class="app-shell-section-title">Current portfolio</h2>
                <p>The active portfolio sets the base currency for account and ledger workflows.</p>
              </div>
            </div>

            <%= if @current_portfolio do %>
              <div id="current-portfolio" class="app-shell-summary-strip">
                <div class="app-shell-summary-item">
                  <span class="app-shell-summary-label">Portfolio</span>
                  <span class="app-shell-summary-value"><%= @current_portfolio.name %></span>
                </div>
                <div class="app-shell-summary-item">
                  <span class="app-shell-summary-label">Base currency</span>
                  <span class="app-shell-summary-value"><%= @current_portfolio.base_currency_code %></span>
                </div>
                <div class="app-shell-summary-item">
                  <span class="app-shell-summary-label">Deposit accounts</span>
                  <span class="app-shell-summary-value"><%= Enum.count(@deposit_accounts) %></span>
                </div>
                <div class="app-shell-summary-item">
                  <span class="app-shell-summary-label">Securities accounts</span>
                  <span class="app-shell-summary-value"><%= Enum.count(@securities_accounts) %></span>
                </div>
              </div>
            <% else %>
              <div id="no-portfolio" class="app-shell-empty-state">
                <h3>No portfolio yet</h3>
                <p>Create a portfolio first.</p>
              </div>
            <% end %>
          </section>

          <%= if @current_portfolio do %>
            <section id="deposit-accounts" class="app-shell-section-card">
              <div class="app-shell-section-header">
                <div>
                  <h2 class="app-shell-section-title">Deposit accounts</h2>
                  <p>Cash and settlement accounts used for deposits, withdrawals, fees and trade cash impact.</p>
                </div>
                <span class="app-shell-badge"><%= Enum.count(@deposit_accounts) %> accounts</span>
              </div>

              <%= if Enum.empty?(@deposit_accounts) do %>
                <div id="no-deposit-accounts" class="app-shell-empty-state">
                  <h3>No deposit accounts yet</h3>
                  <p>Add a cash or settlement account.</p>
                </div>
              <% else %>
                <div class="app-shell-table-wrapper">
                  <table id="deposit-account-list">
                    <thead>
                      <tr>
                        <th>Name</th>
                        <th>Currency</th>
                        <th>Notes</th>
                      </tr>
                    </thead>
                    <tbody>
                      <%= for account <- @deposit_accounts do %>
                        <tr>
                          <td><strong><%= account.name %></strong></td>
                          <td><%= account.currency_code %></td>
                          <td><%= account.notes || "—" %></td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              <% end %>
            </section>

            <section id="cash-balances" class="app-shell-section-card">
              <div class="app-shell-section-header">
                <div>
                  <h2 class="app-shell-section-title">Cash balances</h2>
                  <p>Balances are calculated from ledger transactions.</p>
                </div>
              </div>

              <%= if Enum.empty?(@cash_balance_rows) do %>
                <div id="no-cash-balances" class="app-shell-empty-state">
                  <h3>No cash balances yet</h3>
                  <p>Balances appear after deposit, withdrawal and trade transactions.</p>
                </div>
              <% else %>
                <div class="app-shell-table-wrapper">
                  <table id="cash-balance-list">
                    <thead>
                      <tr>
                        <th>Deposit account</th>
                        <th>Currency</th>
                        <th>Balance</th>
                      </tr>
                    </thead>
                    <tbody>
                      <%= for row <- @cash_balance_rows do %>
                        <tr>
                          <td><%= row.account_name %></td>
                          <td><%= row.currency_code %></td>
                          <td><%= format_money(row.balance) %></td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              <% end %>

              <p class="app-shell-warning-note">
                Buy and sell cash impact is only reflected when a securities account has a reference deposit account.
              </p>

              <%= if not Enum.empty?(@missing_cash_impact_rows) do %>
                <div id="missing-cash-impacts" class="app-shell-alert app-shell-alert--warning" role="alert">
                  <strong>Missing cash impact</strong>
                  <div class="app-shell-table-wrapper">
                    <table>
                      <thead>
                        <tr>
                          <th>Transaction</th>
                          <th>Type</th>
                          <th>Securities account</th>
                        </tr>
                      </thead>
                      <tbody>
                        <%= for row <- @missing_cash_impact_rows do %>
                          <tr>
                            <td><%= row.transaction_id %></td>
                            <td><%= row.type %></td>
                            <td><%= row.securities_account_name %></td>
                          </tr>
                        <% end %>
                      </tbody>
                    </table>
                  </div>
                </div>
              <% end %>
            </section>

            <section
              id="securities-accounts"
              class="app-shell-section-card"
              data-priority="primary"
            >
              <div class="app-shell-section-header">
                <div>
                  <h2 class="app-shell-section-title">Securities accounts</h2>
                  <p>Brokerage or custody accounts where security transactions are recorded.</p>
                </div>
                <span class="app-shell-badge"><%= Enum.count(@securities_accounts) %> accounts</span>
              </div>

              <%= if Enum.empty?(@securities_accounts) do %>
                <div id="no-securities-accounts" class="app-shell-empty-state">
                  <h3>No securities accounts yet</h3>
                  <p>Add a brokerage or custody account.</p>
                </div>
              <% else %>
                <div class="app-shell-table-wrapper">
                  <table id="securities-account-list">
                    <thead>
                      <tr>
                        <th>Name</th>
                        <th>Currency</th>
                        <th>Reference deposit account</th>
                        <th>Notes</th>
                      </tr>
                    </thead>
                    <tbody>
                      <%= for account <- @securities_accounts do %>
                        <tr>
                          <td><strong><%= account.name %></strong></td>
                          <td><%= account.currency_code %></td>
                          <td><%= reference_deposit_account_name(account, @deposit_accounts) %></td>
                          <td><%= account.notes || "—" %></td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              <% end %>
            </section>
          <% end %>
        </div>

        <div class="app-shell-workspace-stack" data-priority="secondary">
          <section id="portfolio-management" class="app-shell-section-card">
            <div class="app-shell-section-header">
              <div>
                <h2 class="app-shell-section-title">Portfolio setup</h2>
                <p class="app-shell-panel-intro">Create the initial portfolio before adding accounts.</p>
              </div>
            </div>

            <%= if @portfolio_success do %>
              <p
                id="portfolio-form-success"
                class="app-shell-alert app-shell-alert--success"
                role="status"
                aria-live="polite"
              >
                <%= @portfolio_success %>
              </p>
            <% end %>

            <%= if @portfolio_error do %>
              <p id="portfolio-form-error" class="app-shell-alert app-shell-alert--error" role="alert">
                <%= @portfolio_error %>
              </p>
            <% end %>

            <form id="portfolio-form" class="app-shell-form-grid" phx-submit="create_portfolio">
              <div class="app-shell-field app-shell-field--full">
                <label for="portfolio-name">Name</label>
                <input id="portfolio-name" name="portfolio[name]" value={@portfolio_form["name"]} />
              </div>

              <div class="app-shell-field">
                <label for="portfolio-base-currency">Base currency</label>
                <select id="portfolio-base-currency" name="portfolio[base_currency_code]">
                  <option value="">Select currency</option>
                  <%= for currency <- @currencies do %>
                    <option
                      value={currency.code}
                      selected={currency.code == @portfolio_form["base_currency_code"]}
                    >
                      <%= currency.code %>
                    </option>
                  <% end %>
                </select>
              </div>

              <div class="app-shell-field app-shell-field--full">
                <label for="portfolio-description">Description (optional)</label>
                <textarea id="portfolio-description" rows="2" name="portfolio[description]"><%= @portfolio_form["description"] %></textarea>
              </div>

              <div class="app-shell-form-actions">
                <button type="submit" class="app-shell-primary">Create portfolio</button>
              </div>
            </form>
          </section>

          <%= if @current_portfolio do %>
            <section id="deposit-account-create" class="app-shell-section-card">
              <div class="app-shell-section-header">
                <div>
                  <h2 class="app-shell-section-title">Add deposit account</h2>
                  <p class="app-shell-panel-intro">Use for cash, settlement and savings accounts.</p>
                </div>
              </div>

              <%= if @deposit_account_success do %>
                <p
                  id="deposit-account-form-success"
                  class="app-shell-alert app-shell-alert--success"
                  role="status"
                  aria-live="polite"
                >
                  <%= @deposit_account_success %>
                </p>
              <% end %>

              <%= if @deposit_account_error do %>
                <p id="deposit-account-form-error" class="app-shell-alert app-shell-alert--error" role="alert">
                  <%= @deposit_account_error %>
                </p>
              <% end %>

              <form
                id="deposit-account-form"
                class="app-shell-form-grid"
                phx-submit="create_deposit_account"
              >
                <div class="app-shell-field app-shell-field--full">
                  <label for="deposit-account-name">Name</label>
                  <input
                    id="deposit-account-name"
                    name="deposit_account[name]"
                    value={@deposit_account_form["name"]}
                  />
                </div>

                <div class="app-shell-field">
                  <label for="deposit-account-currency">Currency</label>
                  <select id="deposit-account-currency" name="deposit_account[currency_code]">
                    <option value="">Select currency</option>
                    <%= for currency <- @currencies do %>
                      <option
                        value={currency.code}
                        selected={currency.code == @deposit_account_form["currency_code"]}
                      >
                        <%= currency.code %>
                      </option>
                    <% end %>
                  </select>
                </div>

                <div class="app-shell-field app-shell-field--full">
                  <label for="deposit-account-notes">Notes (optional)</label>
                  <textarea id="deposit-account-notes" rows="2" name="deposit_account[notes]"><%= @deposit_account_form["notes"] %></textarea>
                </div>

                <div class="app-shell-form-actions">
                  <button type="submit" class="app-shell-primary">Create deposit account</button>
                </div>
              </form>
            </section>

            <section id="securities-account-create" class="app-shell-section-card">
              <div class="app-shell-section-header">
                <div>
                  <h2 class="app-shell-section-title">Add securities account</h2>
                  <p class="app-shell-panel-intro">Link a reference deposit account when trades should affect cash balances.</p>
                </div>
              </div>

              <%= if @securities_account_success do %>
                <p
                  id="securities-account-form-success"
                  class="app-shell-alert app-shell-alert--success"
                  role="status"
                  aria-live="polite"
                >
                  <%= @securities_account_success %>
                </p>
              <% end %>

              <%= if @securities_account_error do %>
                <p id="securities-account-form-error" class="app-shell-alert app-shell-alert--error" role="alert">
                  <%= @securities_account_error %>
                </p>
              <% end %>

              <form
                id="securities-account-form"
                class="app-shell-form-grid"
                phx-submit="create_securities_account"
              >
                <div class="app-shell-field app-shell-field--full">
                  <label for="securities-account-name">Name</label>
                  <input
                    id="securities-account-name"
                    name="securities_account[name]"
                    value={@securities_account_form["name"]}
                  />
                </div>

                <div class="app-shell-field">
                  <label for="securities-account-currency">Currency</label>
                  <select id="securities-account-currency" name="securities_account[currency_code]">
                    <option value="">Select currency</option>
                    <%= for currency <- @currencies do %>
                      <option
                        value={currency.code}
                        selected={currency.code == @securities_account_form["currency_code"]}
                      >
                        <%= currency.code %>
                      </option>
                    <% end %>
                  </select>
                </div>

                <div class="app-shell-field app-shell-field--full">
                  <label for="securities-account-reference-deposit-account">
                    Reference deposit account (optional)
                  </label>
                  <select
                    id="securities-account-reference-deposit-account"
                    name="securities_account[reference_deposit_account_id]"
                  >
                    <option value="">None</option>
                    <%= for account <- @deposit_accounts do %>
                      <option
                        value={account.id}
                        selected={
                          "#{account.id}" ==
                            @securities_account_form["reference_deposit_account_id"]
                        }
                      >
                        <%= account.name %>
                      </option>
                    <% end %>
                  </select>
                </div>

                <div class="app-shell-field app-shell-field--full">
                  <label for="securities-account-notes">Notes (optional)</label>
                  <textarea id="securities-account-notes" rows="2" name="securities_account[notes]"><%= @securities_account_form["notes"] %></textarea>
                </div>

                <div class="app-shell-form-actions">
                  <button type="submit" class="app-shell-primary">Create securities account</button>
                </div>
              </form>
            </section>
          <% end %>
        </div>
      </div>
    </AppShell.shell>
    """
  end

  def handle_event("create_portfolio", %{"portfolio" => params}, socket) do
    case Portfolios.create_portfolio(sanitize_optional_fields(params, ["description"])) do
      {:ok, _portfolio} ->
        {:noreply,
         socket
         |> assign(:portfolio_form, @portfolio_form_defaults)
         |> assign(:portfolio_error, nil)
         |> assign(:portfolio_success, "Portfolio created.")
         |> load_account_state()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:portfolio_form, Map.merge(@portfolio_form_defaults, params))
         |> assign(:portfolio_error, format_errors(changeset))
         |> assign(:portfolio_success, nil)
         |> load_account_state()}
    end
  end

  def handle_event("create_deposit_account", %{"deposit_account" => params}, socket) do
    portfolio_id = socket.assigns.current_portfolio.id

    account_params =
      params
      |> sanitize_optional_fields(["notes"])
      |> Map.put("portfolio_id", portfolio_id)

    case Portfolios.create_deposit_account(account_params) do
      {:ok, _account} ->
        {:noreply,
         socket
         |> assign(:deposit_account_form, @deposit_account_form_defaults)
         |> assign(:deposit_account_error, nil)
         |> assign(:deposit_account_success, "Deposit account created.")
         |> assign(:securities_account_success, nil)
         |> load_account_state()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:deposit_account_form, Map.merge(@deposit_account_form_defaults, params))
         |> assign(:deposit_account_error, format_errors(changeset))
         |> assign(:deposit_account_success, nil)
         |> load_account_state()}
    end
  end

  def handle_event("create_securities_account", %{"securities_account" => params}, socket) do
    portfolio_id = socket.assigns.current_portfolio.id

    account_params =
      params
      |> sanitize_optional_fields(["notes", "reference_deposit_account_id"])
      |> Map.put("portfolio_id", portfolio_id)

    case Portfolios.create_securities_account(account_params) do
      {:ok, _account} ->
        {:noreply,
         socket
         |> assign(:securities_account_form, @securities_account_form_defaults)
         |> assign(:securities_account_error, nil)
         |> assign(:securities_account_success, "Securities account created.")
         |> assign(:deposit_account_success, nil)
         |> load_account_state()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:securities_account_form, Map.merge(@securities_account_form_defaults, params))
         |> assign(:securities_account_error, format_errors(changeset))
         |> assign(:securities_account_success, nil)
         |> load_account_state()}
    end
  end

  defp load_account_state(socket) do
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

    cash_result =
      if current_portfolio do
        Ledger.cash_balances_for_portfolio(current_portfolio.id)
      else
        %{balances: %{}, missing_cash_impacts: []}
      end

    deposit_account_names = name_lookup(deposit_accounts)
    securities_account_names = name_lookup(securities_accounts)

    socket
    |> assign(:currencies, Catalog.list_currencies())
    |> assign(:current_portfolio, current_portfolio)
    |> assign(:deposit_accounts, deposit_accounts)
    |> assign(:securities_accounts, securities_accounts)
    |> assign(:cash_balance_rows, cash_balance_rows(cash_result.balances, deposit_account_names))
    |> assign(
      :missing_cash_impact_rows,
      missing_cash_impact_rows(
        cash_result.missing_cash_impacts,
        transactions,
        securities_account_names
      )
    )
  end

  defp sanitize_optional_fields(params, optional_fields) when is_map(params) do
    params
    |> Map.new(fn {key, value} -> {key, value} end)
    |> then(fn clean_params ->
      Enum.reduce(optional_fields, clean_params, &maybe_remove_empty_string(&2, &1))
    end)
  end

  defp reference_deposit_account_name(account, deposit_accounts) do
    case Enum.find(deposit_accounts, &(&1.id == account.reference_deposit_account_id)) do
      nil -> "—"
      deposit_account -> deposit_account.name
    end
  end

  defp cash_balance_rows(balances, deposit_account_names) do
    balances
    |> Enum.map(fn {{deposit_account_id, currency_code}, balance} ->
      %{
        account_name: Map.get(deposit_account_names, deposit_account_id, "—"),
        currency_code: currency_code,
        balance: balance
      }
    end)
    |> Enum.sort_by(&{&1.account_name, &1.currency_code})
  end

  defp missing_cash_impact_rows(missing_cash_impacts, transactions, securities_account_names) do
    transaction_lookup = Map.new(transactions, &{&1.id, &1})

    Enum.map(missing_cash_impacts, fn impact ->
      transaction = Map.get(transaction_lookup, impact.transaction_id)
      securities_account_id = transaction && transaction.securities_account_id

      %{
        transaction_id: impact.transaction_id,
        type: impact.type,
        securities_account_name: Map.get(securities_account_names, securities_account_id, "—")
      }
    end)
  end

  defp name_lookup(records) do
    Map.new(records, &{&1.id, &1.name})
  end

  defp format_money(nil), do: "—"

  defp format_money(decimal) do
    decimal
    |> Decimal.round(2)
    |> Decimal.to_string(:normal)
  end

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
