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
    currencies = Catalog.list_currencies()

    socket =
      socket
      |> assign(:portfolio_form, default_portfolio_form(currencies))
      |> assign(:deposit_account_form, default_deposit_account_form(currencies))
      |> assign(:securities_account_form, default_securities_account_form(currencies))
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
          <p class="app-shell-page-kicker"><%= gettext("Master data") %></p>
          <h1><%= gettext("Accounts Overview") %></h1>
          <p><%= gettext("Use this page to configure how cash and securities are grouped before ledger entries are added.") %></p>
        </div>
      </header>

      <section id="account-setup-onboarding" class="app-shell-section-card app-shell-onboarding">
        <div class="app-shell-section-header">
          <div>
            <p class="app-shell-page-kicker"><%= gettext("Account setup") %></p>
            <h2 class="app-shell-section-title"><%= gettext("How account setup works") %></h2>
          <p><%= gettext("Complete setup in this order to keep account and cash flow data consistent.") %></p>
          </div>
        </div>
        <ol>
          <li>
            <strong><%= gettext("Create portfolio") %>:</strong>
            <%= gettext("A portfolio is the container for accounts, transactions and derived reports.") %>
          </li>
          <li>
            <strong><%= gettext("Create deposit account") %>:</strong>
            <%= gettext("Cash and settlement accounts used for deposits, withdrawals, fees and trade cash impact.") %>
          </li>
          <li>
            <strong><%= gettext("Create securities account") %>:</strong>
            <%= gettext("Brokerage or custody accounts where security transactions are recorded.") %>
          </li>
          <li>
            <strong><%= gettext("Reference deposit account") %>:</strong>
            <%= gettext("Buy and sell cash impact is only reflected when a securities account has a reference deposit account.") %>
          </li>
        </ol>
      </section>

      <div id="account-workspace" class="app-shell-workspace-grid">
        <div class="app-shell-workspace-stack" data-priority="primary">
          <%= if @current_portfolio do %>
            <section id="current-portfolio-selector" class="app-shell-section-card">
              <div class="app-shell-section-header">
                <div>
                  <h2 class="app-shell-section-title"><%= gettext("Current portfolio") %></h2>
                  <p><%= gettext("Select portfolio") %></p>
                  <p class="app-shell-warning-note">
                    <%= gettext("The current portfolio controls which accounts and future transactions are shown.") %>
                  </p>
                </div>
              </div>

              <form id="current-portfolio-form" phx-change="select_current_portfolio" class="app-shell-form-grid">
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

            <section id="account-overview" class="app-shell-section-card">
              <div class="app-shell-section-header">
                <div>
                  <h2 class="app-shell-section-title"><%= gettext("Current portfolio") %></h2>
                  <p><%= gettext("The base currency for account and ledger workflows is set by the current portfolio.") %></p>
                </div>
              </div>

              <div id="current-portfolio" class="app-shell-summary-strip">
                <div class="app-shell-summary-item">
                  <span class="app-shell-summary-label"><%= gettext("Portfolio") %></span>
                  <span class="app-shell-summary-value"><%= @current_portfolio.name %></span>
                </div>
                <div class="app-shell-summary-item">
                  <span class="app-shell-summary-label"><%= gettext("Base currency") %></span>
                  <span class="app-shell-summary-value"><%= @current_portfolio.base_currency_code %></span>
                </div>
                <div class="app-shell-summary-item">
                  <span class="app-shell-summary-label"><%= gettext("Deposit accounts") %></span>
                  <span class="app-shell-summary-value"><%= Enum.count(@deposit_accounts) %></span>
                </div>
                <div class="app-shell-summary-item">
                  <span class="app-shell-summary-label"><%= gettext("Securities accounts") %></span>
                  <span class="app-shell-summary-value"><%= Enum.count(@securities_accounts) %></span>
                </div>
              </div>
            </section>

            <section id="account-kpis" class="app-shell-stat-grid" aria-label={gettext("Account summary")}>
              <div class="app-shell-stat-card">
                <span class="app-shell-stat-icon" aria-hidden="true">DA</span>
                <div>
                  <span class="app-shell-stat-label"><%= gettext("Deposit accounts") %></span>
                  <span class="app-shell-stat-value"><%= Enum.count(@deposit_accounts) %></span>
                  <span class="app-shell-stat-hint"><%= gettext("Cash and settlement") %></span>
                </div>
              </div>
              <div class="app-shell-stat-card">
                <span class="app-shell-stat-icon" aria-hidden="true">SA</span>
                <div>
                  <span class="app-shell-stat-label"><%= gettext("Securities accounts") %></span>
                  <span class="app-shell-stat-value"><%= Enum.count(@securities_accounts) %></span>
                  <span class="app-shell-stat-hint"><%= gettext("Brokerage and custody") %></span>
                </div>
              </div>
              <div class="app-shell-stat-card">
                <span class="app-shell-stat-icon" aria-hidden="true">CB</span>
                <div>
                  <span class="app-shell-stat-label"><%= gettext("Cash balances") %></span>
                  <span class="app-shell-stat-value"><%= Enum.count(@cash_balance_rows) %></span>
                  <span class="app-shell-stat-hint"><%= gettext("Calculated rows") %></span>
                </div>
              </div>
              <div class="app-shell-stat-card">
                <span class="app-shell-stat-icon" aria-hidden="true">!</span>
                <div>
                  <span class="app-shell-stat-label"><%= gettext("Cash impact warnings") %></span>
                  <span class="app-shell-stat-value"><%= Enum.count(@missing_cash_impact_rows) %></span>
                  <span class="app-shell-stat-hint"><%= gettext("Needs attention") %></span>
                </div>
              </div>
            </section>

            <section id="deposit-accounts" class="app-shell-section-card">
              <div class="app-shell-section-header">
                <div>
                  <h2 class="app-shell-section-title"><%= gettext("Deposit accounts") %></h2>
                  <p><%= gettext("Use a deposit account for cash and settlement activity and future trade cash movements.") %></p>
                </div>
                <span class="app-shell-badge"><%= ngettext("%{count} account", "%{count} accounts", Enum.count(@deposit_accounts), count: Enum.count(@deposit_accounts)) %></span>
              </div>

              <%= if Enum.empty?(@deposit_accounts) do %>
                <div
                  id={deposit_accounts_empty_state_id()}
                  class="app-shell-empty-state"
                  role="status"
                  aria-live="polite"
                  aria-labelledby={deposit_accounts_empty_state_title_id()}
                  aria-describedby={deposit_accounts_empty_state_description_id()}
                >
                  <h3 id={deposit_accounts_empty_state_title_id()}><%= gettext("No deposit accounts yet") %></h3>
                  <p id={deposit_accounts_empty_state_description_id()}><%= gettext("Add a cash or settlement account.") %></p>
                </div>
              <% else %>
                <div class="app-shell-table-wrapper">
                  <table id="deposit-account-list">
                    <caption id="deposit-account-list-caption" class="app-shell-visually-hidden">
                      <%= gettext("Deposit accounts with name, currency, and notes.") %>
                    </caption>
                    <thead>
                      <tr>
                        <th scope="col"><%= gettext("Name") %></th>
                        <th scope="col"><%= gettext("Currency") %></th>
                        <th scope="col"><%= gettext("Notes") %></th>
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
                  <h2 class="app-shell-section-title"><%= gettext("Cash balances") %></h2>
                  <p><%= gettext("Balances are calculated from ledger transactions.") %></p>
                </div>
              </div>

              <%= if Enum.empty?(@cash_balance_rows) do %>
                <div
                  id={cash_balances_empty_state_id()}
                  class="app-shell-empty-state"
                  role="status"
                  aria-live="polite"
                  aria-labelledby={cash_balances_empty_state_title_id()}
                  aria-describedby={cash_balances_empty_state_description_id()}
                >
                  <h3 id={cash_balances_empty_state_title_id()}><%= gettext("No cash balances yet") %></h3>
                  <p id={cash_balances_empty_state_description_id()}><%= gettext("Balances appear after deposit, withdrawal and trade transactions.") %></p>
                </div>
              <% else %>
                <div class="app-shell-table-wrapper">
                  <table id="cash-balance-list">
                    <caption id="cash-balance-list-caption" class="app-shell-visually-hidden">
                      <%= gettext("Cash balances by deposit account and currency.") %>
                    </caption>
                    <thead>
                      <tr>
                        <th scope="col"><%= gettext("Deposit account") %></th>
                        <th scope="col"><%= gettext("Currency") %></th>
                        <th scope="col"><%= gettext("Balance") %></th>
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
                <%= gettext("Buy and sell cash impact is only reflected when a securities account has a reference deposit account.") %>
              </p>

              <%= if not Enum.empty?(@missing_cash_impact_rows) do %>
                <div id="missing-cash-impacts" class="app-shell-alert app-shell-alert--warning" role="alert">
                  <strong><%= gettext("Missing cash impact") %></strong>
                  <div class="app-shell-table-wrapper">
                    <table id="missing-cash-impacts-table">
                      <caption id="missing-cash-impacts-table-caption" class="app-shell-visually-hidden">
                        <%= gettext("Transactions missing a reference deposit account cash impact.") %>
                      </caption>
                      <thead>
                        <tr>
                          <th scope="col"><%= gettext("Transaction") %></th>
                          <th scope="col"><%= gettext("Type") %></th>
                          <th scope="col"><%= gettext("Securities account") %></th>
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
                  <h2 class="app-shell-section-title"><%= gettext("Securities accounts") %></h2>
                  <p><%= gettext("Brokerage or custody accounts where security transactions are recorded.") %></p>
                </div>
                <span class="app-shell-badge"><%= ngettext("%{count} account", "%{count} accounts", Enum.count(@securities_accounts), count: Enum.count(@securities_accounts)) %></span>
              </div>

              <%= if Enum.empty?(@securities_accounts) do %>
                <div
                  id="no-securities-accounts"
                  class="app-shell-empty-state"
                  role="status"
                  aria-live="polite"
                  aria-labelledby="no-securities-accounts-title"
                  aria-describedby="no-securities-accounts-description"
                >
                  <h3 id="no-securities-accounts-title"><%= gettext("No securities accounts yet") %></h3>
                  <p id="no-securities-accounts-description"><%= gettext("Add a brokerage or custody account.") %></p>
                </div>
              <% else %>
                <div class="app-shell-table-wrapper">
                  <table id="securities-account-list">
                    <caption id="securities-account-list-caption" class="app-shell-visually-hidden">
                      <%= gettext("Securities accounts with reference deposit account and notes.") %>
                    </caption>
                    <thead>
                      <tr>
                        <th scope="col"><%= gettext("Name") %></th>
                        <th scope="col"><%= gettext("Currency") %></th>
                        <th scope="col"><%= gettext("Reference deposit account") %></th>
                        <th scope="col"><%= gettext("Notes") %></th>
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
          <% else %>
            <section id="portfolio-onboarding" class="app-shell-section-card app-shell-onboarding">
              <p class="app-shell-page-kicker"><%= gettext("First run") %></p>
                <h2><%= gettext("Create your first portfolio") %></h2>
                <p><%= gettext("Create this portfolio first so account setup appears next.") %></p>
              <div
                id="no-portfolio"
                class="app-shell-empty-state app-shell-empty-state--inline"
                role="status"
                aria-live="polite"
                aria-labelledby="no-portfolio-title"
                aria-describedby="no-portfolio-description"
              >
                <h3 id="no-portfolio-title"><%= gettext("No portfolio yet") %></h3>
                <p id="no-portfolio-description">
                  <%= gettext("After you create this portfolio, you can set up a deposit account and then a securities account.") %>
                </p>
              </div>
            </section>
          <% end %>
        </div>

        <div id="account-forms" class="app-shell-workspace-stack" data-priority="secondary">
            <section id="portfolio-management" class="app-shell-section-card">
            <div class="app-shell-section-header">
              <div>
                <h2 class="app-shell-section-title"><%= gettext("Portfolio setup") %></h2>
                <p id="portfolio-form-intro" class="app-shell-panel-intro"><%= gettext("Create your first portfolio, then add a deposit account and then a securities account.") %></p>
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

            <form
              id="portfolio-form"
              class="app-shell-form-grid"
              phx-submit="create_portfolio"
              aria-describedby={portfolio_form_description_ids(@portfolio_success, @portfolio_error)}
            >
              <div class="app-shell-field app-shell-field--full">
                <label for="portfolio-name"><%= gettext("Name") %></label>
                <input id="portfolio-name" name="portfolio[name]" value={@portfolio_form["name"]} />
              </div>

              <div class="app-shell-field">
                <label for="portfolio-base-currency"><%= gettext("Base currency") %></label>
                <select id="portfolio-base-currency" name="portfolio[base_currency_code]">
                  <option value=""><%= gettext("Select currency") %></option>
                  <%= for currency <- @currencies do %>
                    <option
                      value={currency.code}
                      selected={currency.code == @portfolio_form["base_currency_code"]}
                    >
                      <%= currency_option_label(currency) %>
                    </option>
                  <% end %>
                </select>
              </div>

              <div class="app-shell-field app-shell-field--full">
                <label for="portfolio-description"><%= gettext("Description (optional)") %></label>
                <textarea id="portfolio-description" rows="2" name="portfolio[description]"><%= @portfolio_form["description"] %></textarea>
              </div>

              <div class="app-shell-form-actions">
                <button type="submit" class="app-shell-primary"><%= gettext("Create portfolio") %></button>
              </div>
            </form>
          </section>

          <%= if @current_portfolio do %>
            <section id="deposit-account-create" class="app-shell-section-card">
              <div class="app-shell-section-header">
                <div>
                  <h2 class="app-shell-section-title"><%= gettext("Add deposit account") %></h2>
                  <p id="deposit-account-form-intro" class="app-shell-panel-intro"><%= gettext("Use for cash, settlement and savings accounts.") %></p>
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
                aria-describedby={
                  deposit_account_form_description_ids(
                    @deposit_account_success,
                    @deposit_account_error
                  )
                }
              >
                <div class="app-shell-field app-shell-field--full">
                  <label for="deposit-account-name"><%= gettext("Name") %></label>
                  <input
                    id="deposit-account-name"
                    name="deposit_account[name]"
                    value={@deposit_account_form["name"]}
                  />
                </div>

                <div class="app-shell-field">
                  <label for="deposit-account-currency"><%= gettext("Currency") %></label>
                  <select id="deposit-account-currency" name="deposit_account[currency_code]">
                    <option value=""><%= gettext("Select currency") %></option>
                    <%= for currency <- @currencies do %>
                      <option
                        value={currency.code}
                        selected={currency.code == @deposit_account_form["currency_code"]}
                      >
                        <%= currency_option_label(currency) %>
                      </option>
                    <% end %>
                  </select>
                </div>

                <div class="app-shell-field app-shell-field--full">
                  <label for="deposit-account-notes"><%= gettext("Notes (optional)") %></label>
                  <textarea id="deposit-account-notes" rows="2" name="deposit_account[notes]"><%= @deposit_account_form["notes"] %></textarea>
                </div>

                <div class="app-shell-form-actions">
                  <button type="submit" class="app-shell-primary"><%= gettext("Create deposit account") %></button>
                </div>
              </form>
            </section>

            <section id="securities-account-create" class="app-shell-section-card">
              <div class="app-shell-section-header">
                <div>
                  <h2 class="app-shell-section-title"><%= gettext("Add securities account") %></h2>
                  <p id="securities-account-form-intro" class="app-shell-panel-intro"><%= gettext("Link a reference deposit account when trades should affect cash balances.") %></p>
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
                aria-describedby={
                  securities_account_form_description_ids(
                    @securities_account_success,
                    @securities_account_error
                  )
                }
              >
                <div class="app-shell-field app-shell-field--full">
                  <label for="securities-account-name"><%= gettext("Name") %></label>
                  <input
                    id="securities-account-name"
                    name="securities_account[name]"
                    value={@securities_account_form["name"]}
                  />
                </div>

                <div class="app-shell-field">
                  <label for="securities-account-currency"><%= gettext("Currency") %></label>
                  <select id="securities-account-currency" name="securities_account[currency_code]">
                    <option value=""><%= gettext("Select currency") %></option>
                    <%= for currency <- @currencies do %>
                      <option
                        value={currency.code}
                        selected={currency.code == @securities_account_form["currency_code"]}
                      >
                        <%= currency_option_label(currency) %>
                      </option>
                    <% end %>
                  </select>
                </div>

                <div class="app-shell-field app-shell-field--full">
                  <label for="securities-account-reference-deposit-account">
                    <%= gettext("Reference deposit account (optional)") %>
                  </label>
                  <select
                    id="securities-account-reference-deposit-account"
                    name="securities_account[reference_deposit_account_id]"
                  >
                    <option value=""><%= gettext("None") %></option>
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
                  <label for="securities-account-notes"><%= gettext("Notes (optional)") %></label>
                  <textarea id="securities-account-notes" rows="2" name="securities_account[notes]"><%= @securities_account_form["notes"] %></textarea>
                </div>

                <div class="app-shell-form-actions">
                  <button type="submit" class="app-shell-primary"><%= gettext("Create securities account") %></button>
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
         |> assign(:portfolio_form, default_portfolio_form(socket.assigns.currencies))
         |> assign(:portfolio_error, nil)
         |> assign(:portfolio_success, gettext("Portfolio created."))
         |> load_account_state(Map.get(socket.assigns, :current_portfolio))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:portfolio_form, Map.merge(@portfolio_form_defaults, params))
         |> assign(:portfolio_error, format_errors(changeset))
         |> assign(:portfolio_success, nil)
         |> load_account_state(Map.get(socket.assigns, :current_portfolio))}
    end
  end

  def handle_event("select_current_portfolio", %{"portfolio_id" => selected_portfolio_id}, socket) do
    {:noreply, load_account_state(socket, selected_portfolio_id)}
  end

  def handle_event("select_current_portfolio", _params, socket) do
    {:noreply, load_account_state(socket, Map.get(socket.assigns, :current_portfolio))}
  end

  def handle_event("create_deposit_account", %{"deposit_account" => params}, socket) do
    current_portfolio = Map.get(socket.assigns, :current_portfolio)
    portfolio_id = current_portfolio && current_portfolio.id

    account_params =
      params
      |> sanitize_optional_fields(["notes"])
      |> Map.put("portfolio_id", portfolio_id)

    case Portfolios.create_deposit_account(account_params) do
      {:ok, _account} ->
        {:noreply,
         socket
         |> assign(:deposit_account_form, default_deposit_account_form(socket.assigns.currencies))
         |> assign(:deposit_account_error, nil)
         |> assign(:deposit_account_success, gettext("Deposit account created."))
         |> assign(:securities_account_success, nil)
         |> load_account_state(Map.get(socket.assigns, :current_portfolio))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:deposit_account_form, Map.merge(@deposit_account_form_defaults, params))
         |> assign(:deposit_account_error, format_errors(changeset))
         |> assign(:deposit_account_success, nil)
         |> load_account_state(Map.get(socket.assigns, :current_portfolio))}
    end
  end

  def handle_event("create_securities_account", %{"securities_account" => params}, socket) do
    current_portfolio = Map.get(socket.assigns, :current_portfolio)
    portfolio_id = current_portfolio && current_portfolio.id

    account_params =
      params
      |> sanitize_optional_fields(["notes", "reference_deposit_account_id"])
      |> Map.put("portfolio_id", portfolio_id)

    case Portfolios.create_securities_account(account_params) do
      {:ok, _account} ->
        {:noreply,
         socket
         |> assign(
           :securities_account_form,
           default_securities_account_form(socket.assigns.currencies)
         )
         |> assign(:securities_account_error, nil)
         |> assign(:securities_account_success, gettext("Securities account created."))
         |> assign(:deposit_account_success, nil)
         |> load_account_state(Map.get(socket.assigns, :current_portfolio))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:securities_account_form, Map.merge(@securities_account_form_defaults, params))
         |> assign(:securities_account_error, format_errors(changeset))
         |> assign(:securities_account_success, nil)
         |> load_account_state(Map.get(socket.assigns, :current_portfolio))}
    end
  end

  defp load_account_state(socket, selected_portfolio_id \\ nil) do
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
    |> assign(:portfolios, portfolios)
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

  defp default_portfolio_form(currencies) do
    Map.put(@portfolio_form_defaults, "base_currency_code", preferred_currency_code(currencies))
  end

  defp portfolio_form_description_ids(portfolio_success, portfolio_error) do
    [
      "portfolio-form-intro",
      if(portfolio_success, do: "portfolio-form-success"),
      if(portfolio_error, do: "portfolio-form-error")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp deposit_account_form_description_ids(deposit_account_success, deposit_account_error) do
    [
      "deposit-account-form-intro",
      if(deposit_account_success, do: "deposit-account-form-success"),
      if(deposit_account_error, do: "deposit-account-form-error")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp securities_account_form_description_ids(
         securities_account_success,
         securities_account_error
       ) do
    [
      "securities-account-form-intro",
      if(securities_account_success, do: "securities-account-form-success"),
      if(securities_account_error, do: "securities-account-form-error")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp deposit_accounts_empty_state_id, do: "no-deposit-accounts"
  defp deposit_accounts_empty_state_title_id, do: "no-deposit-accounts-title"

  defp deposit_accounts_empty_state_description_id,
    do: "no-deposit-accounts-description"

  defp cash_balances_empty_state_id, do: "no-cash-balances"
  defp cash_balances_empty_state_title_id, do: "no-cash-balances-title"

  defp cash_balances_empty_state_description_id,
    do: "no-cash-balances-description"

  defp default_deposit_account_form(currencies) do
    Map.put(@deposit_account_form_defaults, "currency_code", preferred_currency_code(currencies))
  end

  defp default_securities_account_form(currencies) do
    Map.put(
      @securities_account_form_defaults,
      "currency_code",
      preferred_currency_code(currencies)
    )
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
