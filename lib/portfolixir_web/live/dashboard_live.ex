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
          <%!-- A portfolio is the hard prerequisite the Portfolio and Income
                screens demand first ("Create one portfolio first"); the path
                starts there so the dashboard does not contradict them. --%>
          <ol>
            <li><a href="/portfolios"><%= gettext("Create one portfolio") %></a></li>
            <li><a href="/portfolios"><%= gettext("Link one depot to one cash account") %></a></li>
            <li><a href="/securities"><%= gettext("Create securities") %></a></li>
            <li>
              <a href="/transactions"><%= gettext("Record manual buy and sell transactions") %></a>
            </li>
            <li><a href="/transactions"><%= gettext("Review current holdings") %></a></li>
          </ol>
        </section>

        <%!-- Each count card looks like a card and is the most clickable thing
              on an empty dashboard, so it links to where that data is created
              instead of being a dead <article>. --%>
        <section class="workspace-section grid" aria-label={gettext("Portfolio counts")}>
          <a href="/securities" id="dashboard-securities-count" class="stat stat--link">
            <span><%= gettext("Securities") %></span>
            <strong><%= @securities_count %></strong>
          </a>
          <a href="/portfolios" id="dashboard-portfolios-count" class="stat stat--link">
            <span><%= gettext("Portfolios") %></span>
            <strong><%= @portfolios_count %></strong>
          </a>
          <a href="/portfolios" id="dashboard-cash-accounts-count" class="stat stat--link">
            <span><%= gettext("Cash accounts") %></span>
            <strong><%= @cash_accounts_count %></strong>
          </a>
          <a href="/portfolios" id="dashboard-securities-accounts-count" class="stat stat--link">
            <span><%= gettext("Depots") %></span>
            <strong><%= @securities_accounts_count %></strong>
          </a>
          <a href="/transactions" id="dashboard-transactions-count" class="stat stat--link">
            <span><%= gettext("Transactions") %></span>
            <strong><%= @transactions_count %></strong>
          </a>
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
