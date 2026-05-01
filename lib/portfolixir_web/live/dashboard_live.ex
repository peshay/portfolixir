defmodule PortfolixirWeb.DashboardLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.Catalog.Security
  alias Portfolixir.Imports.{ImportSource, RawImportItem}
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo
  alias PortfolixirWeb.AppShell

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       securities_count: count_records(Security),
       transactions_count: count_records(Transaction),
       import_sources_count: count_records(ImportSource),
       raw_import_items_count: count_records(RawImportItem)
     )}
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        has_data: assigns.securities_count > 0
      )

    ~H"""
    <AppShell.shell current_path="/">
      <header class="app-shell-page-header">
        <div>
          <h1><%= gettext("Dashboard") %></h1>
          <p><%= gettext("Your product entry point with quick access to imports, positions, and activity.") %></p>
        </div>
        <.primary_action has_data={@has_data} />
      </header>

      <section class="app-shell-workspace-grid" aria-label={gettext("Dashboard quick status")}>
        <section
          id="dashboard-status-cards"
          class="app-shell-section-card app-shell-section-card--compact"
          data-priority="primary"
        >
          <div class="app-shell-section-header">
            <div>
              <h2 class="app-shell-section-title"><%= gettext("Product status") %></h2>
              <p><%= gettext("Real counts from your current workspace.") %></p>
            </div>
          </div>
          <div class="app-shell-stat-grid">
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
            <article id="dashboard-imports-card" class="app-shell-stat-card">
              <span class="app-shell-stat-icon" aria-hidden="true">IM</span>
              <div>
                <span class="app-shell-stat-label"><%= gettext("Import sources") %></span>
                <span id="dashboard-import-sources-value" class="app-shell-stat-value"><%= @import_sources_count %></span>
                <span class="app-shell-stat-hint"><%= gettext("Raw import items") %>: <%= @raw_import_items_count %></span>
              </div>
            </article>
          </div>
        </section>
      </section>

      <section
        id="dashboard-chart-placeholder"
        class="app-shell-section-card app-shell-onboarding app-shell-onboarding--compact"
        data-priority="secondary"
      >
        <p class="app-shell-page-kicker"><%= gettext("Portfolio analytics") %></p>
        <h2><%= gettext("Portfolio value chart") %></h2>
        <p><%= gettext("Portfolio value chart will appear here once valuations are available.") %></p>
      </section>
    </AppShell.shell>
    """
  end

  defp primary_action(assigns) do
    assigns =
      assign_new(assigns, :has_data, fn ->
        false
      end)

    ~H"""
    <a
      id="dashboard-primary-action"
      class="app-shell-button app-shell-primary"
      href={if @has_data, do: "/documents/new", else: "/securities"}
    >
      <%= if @has_data, do: gettext("Add document"), else: gettext("Import portfolio data") %>
    </a>
    """
  end

  defp count_records(schema_module) do
    Repo.aggregate(schema_module, :count, :id)
  end
end
