defmodule PortfolixirWeb.DashboardLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Imports
  alias Portfolixir.Imports.{ImportSource, RawImportItem}
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo
  alias PortfolixirWeb.AppShell

  @dashboard_recent_limit 5

  @impl true
  def mount(_params, _session, socket) do
    securities_count = count_records(Security)
    recent_import_runs = Imports.list_recent_import_runs(@dashboard_recent_limit)
    recent_fund_documents = Catalog.list_recent_fund_documents(@dashboard_recent_limit)

    {:ok,
     assign(socket,
       has_data: securities_count > 0,
       securities_count: securities_count,
       transactions_count: count_records(Transaction),
       import_sources_count: count_records(ImportSource),
       raw_import_items_count: count_records(RawImportItem),
       recent_import_runs: recent_import_runs,
       recent_fund_documents: recent_fund_documents,
       next_step:
         dashboard_next_step(
           securities_count,
           Catalog.count_fund_documents(),
           Catalog.count_fund_allocations(),
           recent_fund_documents
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
          <p><%= gettext("Your product entry point with quick access to imports, positions, and activity.") %></p>
        </div>
        <.primary_action has_data={@has_data} />
      </header>

      <section id="dashboard-next-steps" class="app-shell-section-card app-shell-section-card--compact" data-priority="secondary">
        <div class="app-shell-section-header">
          <div>
            <h2 class="app-shell-section-title"><%= gettext("Next steps") %></h2>
            <p><%= gettext("Continue your workflow from current progress.") %></p>
          </div>
        </div>
        <p>
          <a id="dashboard-next-step-link" class="app-shell-button" href={@next_step.path}>
            <%= @next_step.label %>
          </a>
        </p>
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
        id="dashboard-recent-activity"
        class="app-shell-workspace-grid"
        aria-label={gettext("Recent dashboard activity")}
      >
        <section id="dashboard-recent-import-runs" class="app-shell-section-card">
          <div class="app-shell-section-header">
            <div>
              <h2 class="app-shell-section-title"><%= gettext("Recent import runs") %></h2>
              <p><%= gettext("Latest import run attempts with status and timestamps.") %></p>
            </div>
          </div>

          <%= if Enum.empty?(@recent_import_runs) do %>
            <div id="dashboard-recent-import-runs-empty-state" class="app-shell-empty-state">
              <h3><%= gettext("No import runs yet") %></h3>
              <p><%= gettext("Run imports to build recent activity here.") %></p>
            </div>
          <% else %>
            <div class="app-shell-table-wrapper">
              <table id="dashboard-import-runs-table">
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
              <%= gettext("Open imports") %>
            </a>
          </p>
        </section>

        <section id="dashboard-recent-fund-documents" class="app-shell-section-card">
          <div class="app-shell-section-header">
            <div>
              <h2 class="app-shell-section-title"><%= gettext("Recent fund documents") %></h2>
              <p><%= gettext("Recently uploaded factsheets and extraction status.") %></p>
            </div>
          </div>

          <%= if Enum.empty?(@recent_fund_documents) do %>
            <div id="dashboard-recent-fund-documents-empty-state" class="app-shell-empty-state">
              <h3><%= gettext("No fund documents yet") %></h3>
              <p><%= gettext("Upload a factsheet to populate this list.") %></p>
            </div>
          <% else %>
            <div class="app-shell-table-wrapper">
              <table id="dashboard-fund-documents-table">
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
              <%= gettext("Upload a factsheet") %>
            </a>
          </p>
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

  defp dashboard_next_step(
         0,
         _fund_documents_count,
         _fund_allocations_count,
         _recent_fund_documents
       ) do
    %{label: gettext("Import portfolio data"), path: "/securities"}
  end

  defp dashboard_next_step(_securities_count, 0, _fund_allocations_count, _recent_fund_documents) do
    %{label: gettext("Add document"), path: "/documents/new"}
  end

  defp dashboard_next_step(_securities_count, _fund_documents_count, 0, [latest_fund_document | _]) do
    %{
      label: gettext("Review latest factsheet"),
      path: "/fund-documents/#{latest_fund_document.id}/allocations/review"
    }
  end

  defp dashboard_next_step(_securities_count, _fund_documents_count, 0, _recent_fund_documents) do
    %{label: gettext("Upload a factsheet"), path: "/documents/new"}
  end

  defp dashboard_next_step(
         _securities_count,
         _fund_documents_count,
         _fund_allocations_count,
         _recent_fund_documents
       ) do
    %{label: gettext("Open allocations report"), path: "/reports/fund-allocations"}
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
