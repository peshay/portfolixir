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
    <AppShell.shell current_path="/">
      <header class="page-header">
        <h1><%= gettext("Dashboard") %></h1>
        <p><%= gettext("Local portfolio tracking MVP") %></p>
      </header>

      <section id="mvp-path" class="panel">
        <h2><%= gettext("MVP path") %></h2>
        <ol>
          <li><a href="/securities"><%= gettext("Create securities") %></a></li>
          <li><a href="/portfolios"><%= gettext("Create one portfolio") %></a></li>
          <li><a href="/portfolios"><%= gettext("Link one depot to one cash account") %></a></li>
          <li><a href="/transactions"><%= gettext("Record manual buy and sell transactions") %></a></li>
          <li><a href="/transactions"><%= gettext("Review current holdings") %></a></li>
          <li><a href="/securities"><%= gettext("Store and display quote history") %></a></li>
        </ol>
      </section>

      <section class="grid" aria-label={gettext("MVP counts")}>
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
        <article id="dashboard-quotes-count" class="stat">
          <span><%= gettext("Quotes") %></span>
          <strong><%= @quotes_count %></strong>
        </article>
      </section>
    </AppShell.shell>
    """
  end

  defp assign_counts(socket) do
    assign(socket,
      securities_count: Catalog.count_securities(),
      portfolios_count: Portfolios.count_portfolios(),
      cash_accounts_count: Portfolios.count_cash_accounts(),
      securities_accounts_count: Portfolios.count_securities_accounts(),
      transactions_count: Ledger.count_transactions(),
      quotes_count: Catalog.count_security_quotes()
    )
  end
end
