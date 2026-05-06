defmodule PortfolixirWeb.ClassificationExposureReportLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.ClassificationExposure
  alias Portfolixir.Portfolios
  alias PortfolixirWeb.AppShell

  @sunburst_root "Classification exposure"
  @sunburst_palette ["#0f766e", "#2563eb", "#7c3aed", "#d97706", "#dc2626", "#059669", "#7c2d12"]

  @impl true
  def mount(_params, _session, socket) do
    portfolio = Portfolios.first_portfolio()

    report =
      if portfolio do
        ClassificationExposure.report_for_portfolio(portfolio.id)
      else
        %{rows: [], total_value: Decimal.new("0"), warnings: []}
      end

    sunburst = build_sunburst_state(report.rows)

    {:ok,
     assign(socket,
       portfolio: portfolio,
       report: report,
       sunburst_hierarchy: sunburst.hierarchy,
       sunburst_hierarchy_json: Jason.encode!(sunburst.hierarchy),
       sunburst_legend_rows: sunburst.legend_rows,
       sunburst_gradient: sunburst.gradient
     )}
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
        <section id="classification-exposure-sunburst" class="app-shell-section-card">
          <div class="app-shell-section-header">
            <div>
              <h2 class="app-shell-section-title"><%= gettext("Sunburst") %></h2>
              <p><%= gettext("Read-only chart view based on the current classification exposure rows.") %></p>
            </div>
          </div>

          <div
            id="classification-exposure-sunburst-chart"
            role="img"
            aria-label={gettext("Classification exposure sunburst chart")}
            style={"width: 18rem; height: 18rem; border-radius: 9999px; background: #{@sunburst_gradient}; margin: 0 auto;"}
          >
          </div>

          <ol id="classification-exposure-sunburst-legend" class="app-shell-list-unstyled">
            <%= for row <- @sunburst_legend_rows do %>
              <li id={"classification-exposure-sunburst-legend-#{slug(row.category_name)}"}>
                <span
                  aria-hidden="true"
                  style={"display: inline-block; width: 0.75rem; height: 0.75rem; border-radius: 9999px; background: #{row.color}; margin-right: 0.5rem;"}
                >
                </span>
                <strong><%= row.category_name %></strong>
                <span><%= decimal_to_string(row.percentage) %>%</span>
              </li>
            <% end %>
          </ol>

          <pre id="classification-exposure-sunburst-hierarchy" style="display: none;"><%= @sunburst_hierarchy_json %></pre>
        </section>

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

  defp build_sunburst_state(rows) do
    legend_rows =
      rows
      |> Enum.sort_by(& &1.category_name)
      |> Enum.with_index()
      |> Enum.map(fn {row, index} ->
        Map.put(row, :color, Enum.at(@sunburst_palette, rem(index, length(@sunburst_palette))))
      end)

    total_percentage =
      Enum.reduce(legend_rows, Decimal.new("0"), fn row, acc ->
        Decimal.add(acc, row.percentage)
      end)

    normalized_rows =
      Enum.map(legend_rows, fn row ->
        normalized_percentage =
          if Decimal.equal?(total_percentage, Decimal.new("0")) do
            Decimal.new("0")
          else
            row.percentage
            |> Decimal.div(total_percentage)
            |> Decimal.mult(Decimal.new("100"))
            |> Decimal.round(4)
          end

        Map.put(row, :normalized_percentage, normalized_percentage)
      end)

    gradient =
      case normalized_rows do
        [] ->
          "radial-gradient(circle at center, #f8fafc 0%, #e2e8f0 100%)"

        rows_with_values ->
          {segments, _} =
            Enum.map_reduce(rows_with_values, Decimal.new("0"), fn row, start_percentage ->
              stop_percentage = Decimal.add(start_percentage, row.normalized_percentage)

              segment =
                "#{row.color} #{decimal_to_string(start_percentage)}% #{decimal_to_string(stop_percentage)}%"

              {segment, stop_percentage}
            end)

          "conic-gradient(" <> Enum.join(segments, ", ") <> ")"
      end

    hierarchy = %{
      name: @sunburst_root,
      children:
        legend_rows
        |> Enum.map(fn row ->
          %{
            name: row.category_name,
            value: decimal_to_string(row.value),
            percentage: decimal_to_string(row.percentage)
          }
        end)
    }

    %{legend_rows: legend_rows, gradient: gradient, hierarchy: hierarchy}
  end

  defp decimal_to_string(%Decimal{} = value), do: Decimal.to_string(value, :normal)

  defp slug(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end
end
