defmodule PortfolixirWeb.DashboardLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Valuation
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Format

  @recent_limit 5

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign_counts()
      |> assign(:portfolio_cards, nil)
      |> assign(:recent_transactions, nil)
      |> start_loading()

    {:ok, socket}
  end

  # The dashboard splits on whether any transaction exists: an empty database is
  # still the onboarding wizard, but once data lands the page becomes the daily
  # wealth overview (Steve UAT #337). The overview reads are expensive, so they
  # start only once the socket is connected — the first paint ships skeletons.
  defp start_loading(%{assigns: %{transactions_count: 0}} = socket), do: socket

  defp start_loading(socket) do
    if connected?(socket) do
      start_async(socket, :overview, fn ->
        portfolio_cards =
          Portfolios.list_portfolios()
          |> Enum.map(fn portfolio ->
            {portfolio, Valuation.for_portfolio(portfolio.id)}
          end)

        recent = Ledger.list_transactions(limit: @recent_limit)

        {portfolio_cards, recent}
      end)
    else
      socket
    end
  end

  @impl true
  def handle_async(:overview, {:ok, {portfolio_cards, recent}}, socket) do
    {:noreply, assign(socket, portfolio_cards: portfolio_cards, recent_transactions: recent)}
  end

  def handle_async(:overview, {:exit, _reason}, socket) do
    {:noreply, assign(socket, :error, gettext("Couldn't load the dashboard figures."))}
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
        <%= if @transactions_count == 0 do %>
          <.wizard {assigns} />
        <% else %>
          <.overview {assigns} />
        <% end %>
      </div>
    </AppShell.shell>
    """
  end

  # Empty-database onboarding: the ordered workflow plus the count cards that
  # link to where each entity is created.
  defp wizard(assigns) do
    ~H"""
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

    <.count_cards {assigns} />
    """
  end

  # Populated dashboard: per-portfolio value cards (each in its own base
  # currency, so no cross-currency aggregation is invented here) plus the most
  # recent activity. Richer widgets (sparkline, top/bottom movers, data-quality
  # card) are the approval-gated follow-up tracked on #337.
  defp overview(assigns) do
    ~H"""
    <div id="dashboard-overview">
      <%= if @error do %>
        <AppShell.status_toast kind={:error} message={@error} />
      <% end %>

      <section class="workspace-section grid" aria-label={gettext("Portfolio values")}>
        <%= if is_nil(@portfolio_cards) do %>
          <article class="stat section-skeleton" data-role="overview-skeleton">
            <span><%= gettext("Loading…") %></span>
          </article>
        <% else %>
          <a
            :for={{portfolio, valuation} <- @portfolio_cards}
            id={"dashboard-portfolio-#{portfolio.id}"}
            href="/portfolio"
            class="stat stat--link"
          >
            <span><%= portfolio.name %></span>
            <strong>
              <%= Format.money(valuation.total_with_cash) %> <%= valuation.base_currency %>
            </strong>
            <small>
              <%= gettext("Cash") %> <%= Format.percent(valuation.cash_quote) %>%
            </small>
          </a>
        <% end %>
      </section>

      <section id="dashboard-recent" class="workspace-section">
        <h2><a href="/transactions"><%= gettext("Recent activity") %></a></h2>
        <%= if is_nil(@recent_transactions) do %>
          <p class="section-skeleton" data-role="recent-skeleton"><%= gettext("Loading…") %></p>
        <% else %>
          <ul class="recent-list">
            <li
              :for={transaction <- @recent_transactions}
              data-role="recent-transaction"
              class="recent-item"
            >
              <span class="recent-date"><%= transaction.date %></span>
              <span class="recent-type"><%= transaction.type %></span>
              <span class="recent-security">
                <%= transaction.security && transaction.security.name %>
              </span>
            </li>
          </ul>
        <% end %>
      </section>

      <.count_cards {assigns} />
    </div>
    """
  end

  defp count_cards(assigns) do
    ~H"""
    <%!-- Each count card looks like a card and is the most clickable thing on
          the dashboard, so it links to where that data is created instead of
          being a dead <article>. --%>
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
    """
  end

  defp assign_counts(socket) do
    assign(socket,
      securities_count: Catalog.count_securities(),
      portfolios_count: Portfolios.count_portfolios(),
      cash_accounts_count: Portfolios.count_cash_accounts(),
      securities_accounts_count: Portfolios.count_securities_accounts(),
      transactions_count: Ledger.count_transactions(),
      error: nil
    )
  end
end
