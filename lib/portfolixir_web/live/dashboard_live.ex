defmodule PortfolixirWeb.DashboardLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias PortfolixirWeb.AppShell

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign_counts(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell
      current_path="/"
      page_title={gettext("Dashboard")}
      page_subtitle={gettext("Local portfolio tracking")}
    >
      <div id="dashboard-workspace" class="workspace-page">
        <section id="workflow-path" class="workspace-section">
          <h2><%= gettext("Workflow path") %></h2>
          <ol>
            <li><a href="/securities"><%= gettext("Create securities") %></a></li>
            <li><a href="/portfolios"><%= gettext("Create one portfolio") %></a></li>
            <li><a href="/portfolios"><%= gettext("Link one depot to one cash account") %></a></li>
            <li>
              <a href="/transactions"><%= gettext("Record manual buy and sell transactions") %></a>
            </li>
            <li><a href="/transactions"><%= gettext("Review current holdings") %></a></li>
          </ol>
        </section>

        <section class="workspace-section grid" aria-label={gettext("Portfolio counts")}>
          <article id="dashboard-securities-count" class="stat">
            <span><%= gettext("Securities") %></span>
            <strong><%= @securities_count %></strong>
          </article>
          <article id="dashboard-portfolios-count" class="stat">
            <span><%= gettext("Portfolios") %></span>
            <strong><%= @portfolios_count %></strong>
          </article>
          <article id="dashboard-cash-accounts-count" class="stat">
            <span><%= gettext("Cash accounts") %></span>
            <strong><%= @cash_accounts_count %></strong>
          </article>
          <article id="dashboard-securities-accounts-count" class="stat">
            <span><%= gettext("Depots") %></span>
            <strong><%= @securities_accounts_count %></strong>
          </article>
          <article id="dashboard-transactions-count" class="stat">
            <span><%= gettext("Transactions") %></span>
            <strong><%= @transactions_count %></strong>
          </article>
        </section>
      </div>
    </AppShell.shell>
    """
  end

  defp assign_counts(socket) do
    assign(socket,
      securities_count: Catalog.count_securities(),
      portfolios_count: Portfolios.count_portfolios(),
      cash_accounts_count: Portfolios.count_cash_accounts(),
      securities_accounts_count: Portfolios.count_securities_accounts(),
      transactions_count: Ledger.count_transactions()
    )
  end
end
