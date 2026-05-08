defmodule PortfolixirWeb.ClassificationExposureReportLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.ClassificationExposure
  alias Portfolixir.Portfolios
  alias PortfolixirWeb.AmountFormat
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.ReportState

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
       sunburst_gradient: sunburst.gradient,
       selected_category_name: nil,
       selected_drilldown_row: nil
     )}
  end

  @impl true
  def handle_event("select_category_drilldown", %{"category-name" => category_name}, socket) do
    selected_row = find_category_row(socket.assigns.report.rows, category_name)

    {:noreply,
     assign(socket,
       selected_category_name: if(selected_row, do: category_name, else: nil),
       selected_drilldown_row: selected_row
     )}
  end

  @impl true
  def handle_event("clear_category_drilldown", _params, socket) do
    {:noreply, assign(socket, selected_category_name: nil, selected_drilldown_row: nil)}
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
        <section
          id="classification-exposure-empty-state"
          class="app-shell-empty-state"
          role="status"
          aria-live="polite"
          aria-labelledby="classification-exposure-empty-state-status-title"
          aria-describedby="classification-exposure-empty-state-status-description"
        >
          <h2 id="classification-exposure-empty-state-title">
            <%= gettext("No classification exposure data yet") %>
          </h2>
          <p id="classification-exposure-empty-state-description">
            <%= gettext("Add positions and category mappings to populate this report.") %>
          </p>
          <span id="classification-exposure-empty-state-status-title" class="app-shell-visually-hidden">
            <%= gettext("No classification exposure data yet") %>
          </span>
          <span
            id="classification-exposure-empty-state-status-description"
            class="app-shell-visually-hidden"
          >
            <%= gettext("Add positions and category mappings to populate this report.") %>
          </span>
        </section>
      <% else %>
        <section
          id="classification-exposure-sunburst"
          class="app-shell-section-card"
          aria-labelledby="classification-exposure-sunburst-heading"
          aria-describedby="classification-exposure-sunburst-description"
        >
          <div class="app-shell-section-header">
            <div>
              <h2 id="classification-exposure-sunburst-heading" class="app-shell-section-title">
                <%= gettext("Sunburst") %>
              </h2>
              <p id="classification-exposure-sunburst-description">
                <%= gettext("Read-only chart view based on the current classification exposure rows.") %>
              </p>
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
                <span><%= format_percentage(row.percentage) %></span>
              </li>
            <% end %>
          </ol>

          <pre id="classification-exposure-sunburst-hierarchy" style="display: none;"><%= @sunburst_hierarchy_json %></pre>
        </section>

        <section id="classification-exposure-report" class="app-shell-section-card">
          <div class="app-shell-table-wrapper">
            <table id="classification-exposure-table" aria-describedby="classification-exposure-table-caption">
              <caption id="classification-exposure-table-caption" class="app-shell-visually-hidden">
                <%= gettext("Classification exposure report table with category, exposure, weight, and source securities.") %>
              </caption>
              <thead>
                <tr>
                  <th scope="col"><%= gettext("Category") %></th>
                  <th scope="col"><%= gettext("Exposure") %></th>
                  <th scope="col"><%= gettext("Weight") %></th>
                  <th scope="col"><%= gettext("Source securities") %></th>
                </tr>
              </thead>
              <tbody>
                <%= for row <- @report.rows do %>
                  <tr id={"classification-exposure-row-#{slug(row.category_name)}"}>
                    <th scope="row" data-column-key="category">
                      <button
                        id={"classification-exposure-select-#{slug(row.category_name)}"}
                        type="button"
                        phx-click="select_category_drilldown"
                        phx-value-category-name={row.category_name}
                      >
                        <%= row.category_name %>
                        <%= if @selected_category_name == row.category_name do %>
                          <span aria-hidden="true">•</span>
                        <% end %>
                      </button>
                    </th>
                    <td><%= format_exposure_amount(row, @portfolio.base_currency_code) %></td>
                    <td><%= format_percentage(row.percentage) %></td>
                    <td><%= Enum.join(row.source_securities, ", ") %></td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>

          <section
            id="classification-exposure-drilldown"
            class="app-shell-section-card"
            data-priority="secondary"
            aria-labelledby="classification-exposure-drilldown-heading"
            aria-describedby="classification-exposure-drilldown-description"
          >
            <div class="app-shell-section-header">
              <div>
                <h2 id="classification-exposure-drilldown-heading" class="app-shell-section-title">
                  <%= gettext("Category drilldown details") %>
                </h2>
                <p id="classification-exposure-drilldown-description">
                  <%= gettext("Read-only detail view from the existing classification exposure rows.") %>
                </p>
              </div>
            </div>

            <%= if @selected_drilldown_row do %>
              <div id="classification-exposure-drilldown-summary" class="app-shell-summary-grid">
                <p><strong><%= gettext("Category") %>:</strong> <%= @selected_drilldown_row.category_name %></p>
                <p><strong><%= gettext("Exposure") %>:</strong> <%= format_exposure_amount(@selected_drilldown_row, @portfolio.base_currency_code) %></p>
                <p><strong><%= gettext("Weight") %>:</strong> <%= format_percentage(@selected_drilldown_row.percentage) %></p>
              </div>

              <div class="app-shell-table-wrapper">
                <table
                  id="classification-exposure-drilldown-detail-table"
                  aria-describedby="classification-exposure-drilldown-detail-table-caption"
                >
                  <caption
                    id="classification-exposure-drilldown-detail-table-caption"
                    class="app-shell-visually-hidden"
                  >
                    <%= gettext("Category drilldown detail table for %{category} with source type, status, security, input, exposure, and note rows.",
                      category: @selected_drilldown_row.category_name
                    ) %>
                  </caption>
                  <thead>
                    <tr>
                      <th scope="col"><%= gettext("Source") %></th>
                      <th scope="col"><%= gettext("Status") %></th>
                      <th scope="col"><%= gettext("Security") %></th>
                      <th scope="col"><%= gettext("Input") %></th>
                      <th scope="col"><%= gettext("Exposure") %></th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for detail <- @selected_drilldown_row.drilldown_details do %>
                      <tr id={"classification-exposure-drilldown-detail-#{slug(@selected_drilldown_row.category_name)}-#{slug(detail.security_name)}-#{slug(detail.source_type)}-#{slug(detail.status)}-#{slug(detail.source_label || detail.allocation_type || "none")}"}>
                        <td><%= source_type_label(detail.source_type) %></td>
                        <td><%= status_label(detail.status) %></td>
                        <td><%= detail.security_name %></td>
                        <td><%= input_label(detail) %></td>
                        <td><%= format_detail_amount(detail, @portfolio.base_currency_code) %></td>
                      </tr>

                      <%= if detail.note do %>
                        <tr id={"classification-exposure-drilldown-note-#{slug(@selected_drilldown_row.category_name)}-#{slug(detail.security_name)}-#{slug(detail.source_type)}-#{slug(detail.status)}-#{slug(detail.source_label || detail.allocation_type || detail.note)}"}>
                          <td colspan="5">
                            <strong><%= gettext("Note") %>:</strong> <%= detail.note %>
                          </td>
                        </tr>
                      <% end %>
                    <% end %>
                  </tbody>
                </table>
              </div>

              <button id="classification-exposure-drilldown-clear" type="button" phx-click="clear_category_drilldown">
                <%= gettext("Clear selection") %>
              </button>
            <% else %>
              <section
                id="classification-exposure-drilldown-empty"
                class="app-shell-empty-state app-shell-empty-state--inline"
                role="status"
                aria-live="polite"
                aria-labelledby="classification-exposure-drilldown-empty-status-title"
                aria-describedby="classification-exposure-drilldown-empty-status-description"
              >
                <h3 id="classification-exposure-drilldown-empty-title">
                  <%= gettext("No category selected") %>
                </h3>
                <p id="classification-exposure-drilldown-empty-description">
                  <%= gettext("Select a category row to inspect direct-assignment and weighted-allocation source details.") %>
                </p>
                <span
                  id="classification-exposure-drilldown-empty-status-title"
                  class="app-shell-visually-hidden"
                >
                  <%= gettext("No category selected") %>
                </span>
                <span
                  id="classification-exposure-drilldown-empty-status-description"
                  class="app-shell-visually-hidden"
                >
                  <%= gettext("Select a category row to inspect direct-assignment and weighted-allocation source details.") %>
                </span>
              </section>
            <% end %>
          </section>

          <%= if @report.warnings != [] do %>
            <ReportState.warning_state
              id="classification-exposure-warnings"
              title={gettext("Exposure warnings")}
              warnings={Enum.map(@report.warnings, &format_exposure_warning/1)}
            />
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

  defp find_category_row(rows, category_name) do
    Enum.find(rows, &(&1.category_name == category_name))
  end

  defp source_type_label("direct-assignment"), do: "Direct assignment"
  defp source_type_label("weighted-allocation"), do: "Weighted allocation"
  defp source_type_label(other), do: other

  defp status_label("mapped"), do: "Mapped"
  defp status_label("unmapped"), do: "Unmapped"
  defp status_label("unknown"), do: "Unknown"
  defp status_label(other), do: other

  defp input_label(%{source_type: "direct-assignment", status: "mapped"}),
    do: "Direct category assignment"

  defp input_label(%{source_type: "direct-assignment", status: "unmapped"}),
    do: "No direct category assignment"

  defp input_label(%{
         source_type: "weighted-allocation",
         allocation_type: allocation_type,
         source_label: source_label
       })
       when is_binary(allocation_type) and is_binary(source_label),
       do: "#{allocation_type}: #{source_label}"

  defp input_label(%{source_type: "weighted-allocation"}), do: "Unknown weighted allocation input"

  defp input_label(_detail), do: "Unknown"

  defp decimal_to_string(%Decimal{} = value), do: Decimal.to_string(value, :normal)

  defp format_exposure_amount(%{valuation_unavailable?: true}, _currency_code),
    do: AmountFormat.missing_amount_label()

  defp format_exposure_amount(%{value: value}, currency_code),
    do: AmountFormat.format_currency_amount(value, currency_code)

  defp format_detail_amount(%{valuation_unavailable?: true}, _currency_code),
    do: AmountFormat.missing_amount_label()

  defp format_detail_amount(%{value: value}, currency_code),
    do: AmountFormat.format_currency_amount(value, currency_code)

  defp format_percentage(value), do: "#{AmountFormat.format_decimal(value)}%"

  defp format_exposure_warning("missing_quote_fallback_quantity:" <> security_id) do
    "missing_quote_fallback_quantity:#{security_id} — Missing latest quote; exposure falls back to zero market value for this security."
  end

  defp format_exposure_warning("stale_quote_fallback_quantity:" <> warning_tail) do
    "stale_quote_fallback_quantity:#{warning_tail} — Stale latest quote detected; verify quote recency before using this exposure value."
  end

  defp format_exposure_warning(warning), do: warning

  defp slug(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end
end
