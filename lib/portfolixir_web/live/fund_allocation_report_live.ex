defmodule PortfolixirWeb.FundAllocationReportLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.Catalog
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.ReportState
  alias PortfolixirWeb.WorkbenchToolbar

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :fund_allocations, Catalog.list_fund_allocations_for_report())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell current_path="/reports/fund-allocations">
      <header class="app-shell-page-header">
        <div>
          <p class="app-shell-page-kicker"><%= gettext("Reports") %></p>
          <h1><%= gettext("Fund allocation report") %></h1>
          <p><%= gettext("Review confirmed ETF allocation breakdowns imported from factsheets.") %></p>
        </div>
      </header>

      <%= if Enum.empty?(@fund_allocations) do %>
        <ReportState.empty_state
          id="fund-allocation-empty-state"
          title={gettext("No confirmed fund allocations yet")}
          description={gettext("Upload a factsheet with allocations to populate this report.")}
          action_id="fund-allocation-empty-state-link"
          action_href="/documents/new"
          action_text={gettext("Upload a factsheet")}
        />
      <% end %>

      <%= if !Enum.empty?(@fund_allocations) do %>
        <div id="fund-allocation-report" class="app-shell-workspace-stack">
          <section
            id="fund-allocation-workbench-toolbar"
            class="app-shell-section-card"
            data-priority="primary"
            aria-labelledby="fund-allocation-toolbar-title"
            aria-describedby="fund-allocation-toolbar-description"
          >
            <WorkbenchToolbar.toolbar
              id="fund-allocation-toolbar"
              title={gettext("Fund allocation workbench")}
              description={gettext("Shared report controls are visible before advanced actions are implemented.")}
              search_id="fund-allocation-search"
              search_placeholder={gettext("Search (planned)")}
              search_label={gettext("Search allocations")}
              time_ranges={["1M", "3M", "6M", "1Y", "YTD", "ALL"]}
              active_time_range="ALL"
            />
          </section>
          <%= for section <- fund_allocation_sections(@fund_allocations) do %>
            <section
              id={"fund-allocation-security-#{section.security.id}"}
              class="app-shell-section-card"
              data-priority="primary"
              aria-labelledby={"fund-allocation-security-title-#{section.security.id}"}
              aria-describedby={"fund-allocation-security-intro-#{section.security.id}"}
            >
              <div class="app-shell-section-header">
                <h2
                  id={"fund-allocation-security-title-#{section.security.id}"}
                  class="app-shell-section-title"
                >
                  <%= section.security.name %> (<%= section.security.symbol %>)
                </h2>
                <p
                  id={"fund-allocation-security-intro-#{section.security.id}"}
                  class="app-shell-panel-intro"
                >
                  <%= gettext("Imported allocation rows grouped by security") %>
                </p>
              </div>

              <div class="app-shell-table-wrapper">
                <table id={"fund-allocation-table-#{section.security.id}"}>
                  <caption class="app-shell-visually-hidden">
                    <%= gettext("Fund allocation table for %{name} (%{symbol}) with allocation type, source, as-of date, label, weight, and confidence.", name: section.security.name, symbol: section.security.symbol) %>
                  </caption>
                  <thead>
                    <tr>
                      <th scope="col"><%= gettext("Allocation type") %></th>
                      <th scope="col"><%= gettext("Source") %></th>
                      <th scope="col"><%= gettext("As-of date") %></th>
                      <th scope="col"><%= gettext("Label") %></th>
                      <th scope="col"><%= gettext("Weight") %></th>
                      <th scope="col"><%= gettext("Confidence") %></th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for allocation <- section.allocations do %>
                      <%= for item <- allocation.fund_allocation_items do %>
                        <tr id={"fund-allocation-row-#{allocation.id}-#{item.id}"}>
                          <td><%= allocation.allocation_type %></td>
                          <td><%= allocation.source %></td>
                          <td><%= format_as_of_date(allocation.as_of_date) %></td>
                          <td><%= item.label %></td>
                          <td><%= format_percent(item.weight) %></td>
                          <td><%= format_percent(item.confidence) %></td>
                        </tr>
                      <% end %>
                    <% end %>
                  </tbody>
                </table>
              </div>
            </section>
          <% end %>
        </div>
      <% end %>
    </AppShell.shell>
    """
  end

  defp fund_allocation_sections(fund_allocations) do
    fund_allocations
    |> Enum.group_by(& &1.security_id)
    |> Enum.map(fn {_security_id, allocations} ->
      %{security: hd(allocations).security, allocations: allocations}
    end)
    |> Enum.sort_by(& &1.security.name)
  end

  defp format_as_of_date(nil), do: gettext("—")
  defp format_as_of_date(date), do: Date.to_string(date)

  defp format_percent(nil), do: gettext("—")

  defp format_percent(decimal) when is_struct(decimal, Decimal),
    do: "#{Decimal.to_string(decimal, :normal)}%"

  defp format_percent(value), do: to_string(value)
end
