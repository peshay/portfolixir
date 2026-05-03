defmodule PortfolixirWeb.ClassificationExposureReportLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.ClassificationExposure
  alias Portfolixir.Portfolios
  alias PortfolixirWeb.AppShell

  @impl true
  def mount(_params, _session, socket) do
    portfolio = Portfolios.first_portfolio()

    report =
      if portfolio do
        ClassificationExposure.report_for_portfolio(portfolio.id)
      else
        %{rows: [], total_value: Decimal.new("0"), warnings: []}
      end

    {:ok, assign(socket, portfolio: portfolio, report: report)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell current_path="/reports/classification-exposure">
      <header class="app-shell-page-header">
        <div>
          <p class="app-shell-page-kicker"><%= gettext("Reports") %></p>
          <h1><%= gettext("Classification exposure report") %></h1>
        </div>
      </header>

      <%= if is_nil(@portfolio) or Enum.empty?(@report.rows) do %>
        <section id="classification-exposure-empty-state" class="app-shell-empty-state">
          <h2><%= gettext("No classification exposure data yet") %></h2>
        </section>
      <% else %>
        <section id="classification-exposure-report" class="app-shell-section-card">
          <div class="app-shell-table-wrapper">
            <table>
              <thead>
                <tr>
                  <th><%= gettext("Category") %></th>
                  <th><%= gettext("Exposure") %></th>
                  <th><%= gettext("Weight") %></th>
                  <th><%= gettext("Source securities") %></th>
                </tr>
              </thead>
              <tbody>
                <%= for row <- @report.rows do %>
                  <tr id={"classification-exposure-row-#{slug(row.category_name)}"}>
                    <td><%= row.category_name %></td>
                    <td><%= decimal_to_string(row.value) %></td>
                    <td><%= decimal_to_string(row.percentage) %>%</td>
                    <td><%= Enum.join(row.source_securities, ", ") %></td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>

          <%= if @report.warnings != [] do %>
            <ul id="classification-exposure-warnings">
              <%= for warning <- @report.warnings do %>
                <li><%= warning %></li>
              <% end %>
            </ul>
          <% end %>
        </section>
      <% end %>
    </AppShell.shell>
    """
  end

  defp decimal_to_string(%Decimal{} = value), do: Decimal.to_string(value, :normal)

  defp slug(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end
end
