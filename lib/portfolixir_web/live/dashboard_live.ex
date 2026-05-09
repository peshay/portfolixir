defmodule PortfolixirWeb.DashboardLive do
  use PortfolixirWeb, :live_view

  import Ecto.Query, only: [from: 2]

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Imports
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios.{DepositAccount, Portfolio, SecuritiesAccount}
  alias Portfolixir.Repo
  alias PortfolixirWeb.AppShell

  @dashboard_recent_limit 5

  @impl true
  def mount(_params, _session, socket) do
    portfolios_count = count_records(Portfolio)
    deposit_accounts_count = count_records(DepositAccount)
    securities_accounts_count = count_records(SecuritiesAccount)
    securities_count = count_records(Security)
    transactions_count = count_records(Transaction)
    buy_transactions_count = count_buy_transactions()
    recent_import_runs = Imports.list_recent_import_runs(@dashboard_recent_limit)
    recent_fund_documents = Catalog.list_recent_fund_documents(@dashboard_recent_limit)

    {:ok,
     assign(socket,
       portfolios_count: portfolios_count,
       tracking_accounts_count: deposit_accounts_count + securities_accounts_count,
       securities_count: securities_count,
       transactions_count: transactions_count,
       recent_import_runs: recent_import_runs,
       recent_fund_documents: recent_fund_documents,
       next_step:
         dashboard_next_step(
           portfolios_count,
           deposit_accounts_count,
           securities_accounts_count,
           securities_count,
           buy_transactions_count
         )
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell current_path="/">
      <header class="app-shell-page-header">
        <div>
          <h1><%= gettext("Dashboard") %></h1>
          <p><%= gettext("Track portfolio data manually first: setup, securities, transactions, then read-only reports.") %></p>
        </div>
        <.primary_action next_step={@next_step} />
      </header>

      <section id="dashboard-next-steps" class="app-shell-section-card app-shell-section-card--compact" data-priority="secondary">
        <div class="app-shell-section-header">
          <div>
            <h2 class="app-shell-section-title"><%= gettext("Next steps") %></h2>
            <p><%= gettext("Follow the manual MVP path before testing imports or document workflows.") %></p>
          </div>
        </div>
        <p>
          <a id="dashboard-next-step-link" class="app-shell-button" href={@next_step.path}>
            <%= @next_step.label %>
          </a>
        </p>
      </section>

      <section
        id="dashboard-mvp-path"
        class="app-shell-section-card app-shell-section-card--compact"
        aria-labelledby="dashboard-mvp-path-title"
      >
        <div class="app-shell-section-header">
          <div>
            <h2 id="dashboard-mvp-path-title" class="app-shell-section-title"><%= gettext("Manual MVP path") %></h2>
            <p><%= gettext("Use this order for a first portfolio: setup, securities, transactions, then reports and charts.") %></p>
          </div>
        </div>
        <ol class="app-shell-action-list">
          <li><a id="dashboard-mvp-step-accounts" href="/accounts"><%= gettext("1. Set up portfolio and tracking accounts") %></a></li>
          <li><a id="dashboard-mvp-step-securities" href="/securities"><%= gettext("2. Add securities") %></a></li>
          <li><a id="dashboard-mvp-step-transactions" href="/transactions"><%= gettext("3. Record buy transactions") %></a></li>
          <li><a id="dashboard-mvp-step-reports" href="/reports/fund-allocations"><%= gettext("4. Review reports and charts") %></a></li>
        </ol>
      </section>

      <section class="app-shell-workspace-grid" aria-label={gettext("Dashboard quick status")}>
        <section
          id="dashboard-status-cards"
          class="app-shell-section-card app-shell-section-card--compact"
          data-priority="primary"
        >
          <div class="app-shell-section-header">
            <div>
              <h2 class="app-shell-section-title"><%= gettext("Product status") %></h2>
              <p><%= gettext("Real counts from the manual tracking workflow.") %></p>
            </div>
          </div>
          <div class="app-shell-stat-grid">
            <article id="dashboard-portfolios-card" class="app-shell-stat-card">
              <span class="app-shell-stat-icon" aria-hidden="true">PF</span>
              <div>
                <span class="app-shell-stat-label"><%= gettext("Portfolios") %></span>
                <span id="dashboard-portfolios-value" class="app-shell-stat-value"><%= @portfolios_count %></span>
                <span class="app-shell-stat-hint"><%= gettext("Tracked portfolios") %></span>
              </div>
            </article>
            <article id="dashboard-accounts-card" class="app-shell-stat-card">
              <span class="app-shell-stat-icon" aria-hidden="true">ACC</span>
              <div>
                <span class="app-shell-stat-label"><%= gettext("Tracking accounts") %></span>
                <span id="dashboard-accounts-value" class="app-shell-stat-value"><%= @tracking_accounts_count %></span>
                <span class="app-shell-stat-hint"><%= gettext("Cash and securities accounts") %></span>
              </div>
            </article>
            <article id="dashboard-securities-card" class="app-shell-stat-card">
              <span class="app-shell-stat-icon" aria-hidden="true">S</span>
              <div>
                <span class="app-shell-stat-label"><%= gettext("Securities") %></span>
                <span id="dashboard-securities-value" class="app-shell-stat-value"><%= @securities_count %></span>
                <span class="app-shell-stat-hint"><%= gettext("Total securities") %></span>
              </div>
            </article>
            <article id="dashboard-transactions-card" class="app-shell-stat-card">
              <span class="app-shell-stat-icon" aria-hidden="true">TX</span>
              <div>
                <span class="app-shell-stat-label"><%= gettext("Transactions") %></span>
                <span id="dashboard-transactions-value" class="app-shell-stat-value"><%= @transactions_count %></span>
                <span class="app-shell-stat-hint"><%= gettext("Recorded ledger entries") %></span>
              </div>
            </article>
          </div>
        </section>
      </section>

      <section
        id="dashboard-experimental-activity"
        class="app-shell-workspace-grid"
        aria-label={gettext("Experimental import and document activity")}
      >
        <section id="dashboard-recent-import-runs" class="app-shell-section-card" data-priority="experimental">
          <div class="app-shell-section-header">
            <div>
              <p class="app-shell-page-kicker"><%= gettext("Experimental") %></p>
              <h2 class="app-shell-section-title"><%= gettext("Recent import runs") %></h2>
              <p><%= gettext("Optional import workflow activity; not required for the manual MVP path.") %></p>
            </div>
          </div>

          <%= if Enum.empty?(@recent_import_runs) do %>
            <div
              id="dashboard-recent-import-runs-empty-state"
              class="app-shell-empty-state"
              role="status"
              aria-live="polite"
              aria-labelledby="dashboard-recent-import-runs-empty-state-title"
              aria-describedby="dashboard-recent-import-runs-empty-state-description"
            >
              <span id="dashboard-recent-import-runs-empty-state-title" class="app-shell-visually-hidden">
                <%= gettext("No import runs yet") %>
              </span>
              <span
                id="dashboard-recent-import-runs-empty-state-description"
                class="app-shell-visually-hidden"
              >
                <%= gettext("Optional import runs appear here when you test experimental import flows.") %>
              </span>
              <h3><%= gettext("No import runs yet") %></h3>
              <p><%= gettext("Optional import runs appear here when you test experimental import flows.") %></p>
            </div>
          <% else %>
            <div class="app-shell-table-wrapper">
              <table id="dashboard-import-runs-table">
                <caption id="dashboard-import-runs-table-caption" class="app-shell-visually-hidden">
                  <%= gettext("Recent import runs with source, status, start time, and finish time.") %>
                </caption>
                <thead>
                  <tr>
                    <th scope="col"><%= gettext("Source") %></th>
                    <th scope="col"><%= gettext("Status") %></th>
                    <th scope="col"><%= gettext("Started") %></th>
                    <th scope="col"><%= gettext("Finished") %></th>
                  </tr>
                </thead>
                <tbody>
                  <%= for import_run <- @recent_import_runs do %>
                    <tr id={"dashboard-import-run-row-#{import_run.id}"}>
                      <td><%= import_run.import_source.name %></td>
                      <td><%= import_run.status %></td>
                      <td><%= format_datetime(import_run.started_at) %></td>
                      <td><%= format_datetime(import_run.finished_at) %></td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>

          <p>
            <a id="dashboard-import-runs-link" href="/imports">
              <%= gettext("Open experimental imports") %>
            </a>
          </p>
        </section>

        <section id="dashboard-recent-fund-documents" class="app-shell-section-card" data-priority="experimental">
          <div class="app-shell-section-header">
            <div>
              <p class="app-shell-page-kicker"><%= gettext("Experimental") %></p>
              <h2 class="app-shell-section-title"><%= gettext("Recent fund documents") %></h2>
              <p><%= gettext("Optional document workflow activity; not required for the manual MVP path.") %></p>
            </div>
          </div>

          <%= if Enum.empty?(@recent_fund_documents) do %>
            <div
              id="dashboard-recent-fund-documents-empty-state"
              class="app-shell-empty-state"
              role="status"
              aria-live="polite"
              aria-labelledby="dashboard-recent-fund-documents-empty-state-status-title"
              aria-describedby="dashboard-recent-fund-documents-empty-state-status-description"
            >
              <span
                id="dashboard-recent-fund-documents-empty-state-status-title"
                class="app-shell-visually-hidden"
              >
                <%= gettext("No fund documents yet") %>
              </span>
              <span
                id="dashboard-recent-fund-documents-empty-state-status-description"
                class="app-shell-visually-hidden"
              >
                <%= gettext("Optional factsheet uploads appear here when you test experimental document flows.") %>
              </span>
              <h3 id="dashboard-recent-fund-documents-empty-state-title"><%= gettext("No fund documents yet") %></h3>
              <p id="dashboard-recent-fund-documents-empty-state-description"><%= gettext("Optional factsheet uploads appear here when you test experimental document flows.") %></p>
            </div>
          <% else %>
            <div class="app-shell-table-wrapper">
              <table id="dashboard-fund-documents-table">
                <caption id="dashboard-fund-documents-table-caption" class="app-shell-visually-hidden">
                  <%= gettext("Recent fund documents with security, filename, extraction status, and review action.") %>
                </caption>
                <thead>
                  <tr>
                    <th scope="col"><%= gettext("Security") %></th>
                    <th scope="col"><%= gettext("Filename") %></th>
                    <th scope="col"><%= gettext("Extraction status") %></th>
                    <th scope="col"><%= gettext("Review") %></th>
                  </tr>
                </thead>
                <tbody>
                  <%= for fund_document <- @recent_fund_documents do %>
                    <tr id={"dashboard-fund-document-row-#{fund_document.id}"}>
                      <td><%= security_display_name(fund_document.security) %></td>
                      <td><%= fund_document.original_filename %></td>
                      <td><%= fund_document.extraction_status %></td>
                      <td>
                        <a
                          id={"dashboard-fund-document-review-link-#{fund_document.id}"}
                          href={"/fund-documents/#{fund_document.id}/allocations/review"}
                        >
                          <%= gettext("Review allocations") %>
                        </a>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>

          <p>
            <a id="dashboard-fund-documents-link" href="/documents/new">
              <%= gettext("Open experimental factsheet upload") %>
            </a>
          </p>
        </section>
      </section>

      <section
        id="dashboard-chart-placeholder"
        class="app-shell-section-card app-shell-onboarding app-shell-onboarding--compact"
        data-priority="secondary"
        role="region"
        aria-labelledby="dashboard-chart-placeholder-title"
        aria-describedby="dashboard-chart-placeholder-description"
      >
        <span id="dashboard-chart-placeholder-title" class="app-shell-visually-hidden">
          <%= gettext("Portfolio value chart") %>
        </span>
        <span id="dashboard-chart-placeholder-description" class="app-shell-visually-hidden">
          <%= gettext("Portfolio value chart will appear here once valuations are available.") %>
        </span>
        <p class="app-shell-page-kicker"><%= gettext("Portfolio analytics") %></p>
        <h2><%= gettext("Portfolio value chart") %></h2>
        <p>
          <%= gettext("Portfolio value chart will appear here once valuations are available.") %>
        </p>
      </section>
    </AppShell.shell>
    """
  end

  defp dashboard_next_step(
         portfolios_count,
         deposit_accounts_count,
         securities_accounts_count,
         _securities_count,
         _transactions_count
       )
       when portfolios_count == 0 or deposit_accounts_count == 0 or securities_accounts_count == 0 do
    %{label: gettext("Set up portfolio and accounts"), path: "/accounts"}
  end

  defp dashboard_next_step(
         _portfolios_count,
         _deposit_accounts_count,
         _securities_accounts_count,
         0,
         _transactions_count
       ) do
    %{label: gettext("Add your first security"), path: "/securities"}
  end

  defp dashboard_next_step(
         _portfolios_count,
         _deposit_accounts_count,
         _securities_accounts_count,
         _securities_count,
         0
       ) do
    %{label: gettext("Record a buy transaction"), path: "/transactions"}
  end

  defp dashboard_next_step(
         _portfolios_count,
         _deposit_accounts_count,
         _securities_accounts_count,
         _securities_count,
         _transactions_count
       ) do
    %{label: gettext("Review reports and charts"), path: "/reports/fund-allocations"}
  end

  defp security_display_name(nil), do: gettext("Unlinked security")

  defp security_display_name(%{name: name, symbol: symbol})
       when is_binary(symbol) and symbol != "" do
    "#{name} (#{symbol})"
  end

  defp security_display_name(%{name: name}), do: name

  defp format_datetime(nil), do: gettext("—")

  defp format_datetime(datetime) when is_struct(datetime, DateTime) do
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp format_datetime(datetime) when is_struct(datetime, NaiveDateTime) do
    datetime
    |> NaiveDateTime.truncate(:second)
    |> NaiveDateTime.to_iso8601()
  end

  defp format_datetime(_datetime), do: gettext("—")

  defp primary_action(assigns) do
    ~H"""
    <a id="dashboard-primary-action" class="app-shell-button app-shell-primary" href={@next_step.path}>
      <%= @next_step.label %>
    </a>
    """
  end

  defp count_records(schema_module) do
    Repo.aggregate(schema_module, :count, :id)
  end

  defp count_buy_transactions do
    from(t in Transaction, where: t.type == "buy")
    |> Repo.aggregate(:count, :id)
  end
end
