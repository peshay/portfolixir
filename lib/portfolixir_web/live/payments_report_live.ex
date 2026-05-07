defmodule PortfolixirWeb.PaymentsReportLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.ReportState

  @group_modes ["list", "month", "quarter", "year", "security"]

  @impl true
  def mount(_params, _session, socket) do
    portfolios = Portfolios.list_portfolios()
    current_portfolio = List.first(portfolios)

    socket =
      socket
      |> assign(:portfolios, portfolios)
      |> assign(:current_portfolio, current_portfolio)
      |> assign(:group_modes, @group_modes)
      |> assign(:group_mode, "list")
      |> load_report_state()

    {:ok, socket}
  end

  @impl true
  def handle_event("select_current_portfolio", %{"portfolio_id" => portfolio_id}, socket) do
    {:noreply, load_report_state(socket, portfolio_id)}
  end

  @impl true
  def handle_event("set_group_mode", %{"group_mode" => group_mode}, socket)
      when group_mode in @group_modes do
    {:noreply, assign(socket, :group_mode, group_mode)}
  end

  def handle_event("set_group_mode", _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell current_path="/reports/payments">
      <header class="app-shell-page-header">
        <div>
          <p class="app-shell-page-kicker"><%= gettext("Reports") %></p>
          <h1><%= gettext("Payments report") %></h1>
          <p><%= gettext("Review read-only dividend transactions grouped by period or security.") %></p>
        </div>
      </header>

      <%= if @current_portfolio do %>
        <section id="payments-current-portfolio-selector" class="app-shell-section-card">
          <div class="app-shell-section-header">
            <div>
              <h2 class="app-shell-section-title"><%= gettext("Current portfolio") %></h2>
              <p><%= gettext("Select portfolio") %></p>
            </div>
          </div>

          <form id="payments-current-portfolio-form" phx-change="select_current_portfolio" class="app-shell-form-grid">
            <div class="app-shell-field app-shell-field--full">
              <label for="payments-current-portfolio-select"><%= gettext("Current portfolio") %></label>
              <select id="payments-current-portfolio-select" name="portfolio_id">
                <%= for portfolio <- @portfolios do %>
                  <option value={portfolio.id} selected={portfolio.id == @current_portfolio.id}><%= portfolio.name %></option>
                <% end %>
              </select>
            </div>
          </form>
        </section>

        <section
          id="payments-group-controls"
          class="app-shell-section-card"
          role="group"
          aria-labelledby="payments-group-controls-label"
          aria-describedby="payments-group-controls-description"
        >
          <span id="payments-group-controls-label" class="app-shell-visually-hidden">
            <%= group_controls_label() %>
          </span>
          <span id="payments-group-controls-description" class="app-shell-visually-hidden">
            <%= group_controls_description() %>
          </span>

          <form
            id="payments-group-form"
            phx-change="set_group_mode"
            class="app-shell-form-grid"
            aria-labelledby="payments-group-controls-label"
            aria-describedby="payments-group-controls-description"
          >
            <div class="app-shell-field app-shell-field--full">
              <label for="payments-group-mode"><%= gettext("Group by") %></label>
              <select
                id="payments-group-mode"
                name="group_mode"
                aria-describedby="payments-group-controls-description"
              >
                <%= for mode <- @group_modes do %>
                  <option value={mode} selected={mode == @group_mode}><%= group_mode_label(mode) %></option>
                <% end %>
              </select>
            </div>
          </form>
        </section>

        <%= if Enum.empty?(@dividend_rows) do %>
          <ReportState.empty_state
            id="payments-empty-state"
            title={gettext("No dividend payments yet")}
            description={gettext("Record dividend transactions to populate this report.")}
          />
        <% else %>
          <section
            id="payments-accumulation-chart"
            class="app-shell-section-card"
            aria-labelledby="payments-accumulation-chart-title"
            aria-describedby="payments-accumulation-chart-intro"
          >
            <div class="app-shell-section-header">
              <div>
                <h2 id="payments-accumulation-chart-title" class="app-shell-section-title"><%= gettext("Accumulated dividends") %></h2>
                <p id="payments-accumulation-chart-intro"><%= gettext("Monthly cumulative progression based on recorded dividend transactions.") %></p>
              </div>
            </div>

            <%= for {currency_code, points} <- accumulation_points_by_currency(@accumulation_points) do %>
              <article id={"payments-accumulation-currency-#{String.downcase(currency_code)}"} class="app-shell-workspace-stack">
                <h3><%= currency_code %></h3>
                <ol id={"payments-accumulation-bars-#{String.downcase(currency_code)}"} class="app-shell-list-unstyled">
                  <%= for point <- points do %>
                    <li id={"payments-accumulation-point-#{String.downcase(currency_code)}-#{point.month_label}"}>
                      <strong><%= point.month_label %></strong>
                      <span><%= format_money(point.accumulated_amount) %></span>
                      <div class="app-shell-progress" role="img" aria-label={"#{currency_code} #{point.month_label} #{format_money(point.accumulated_amount)}"}>
                        <div class="app-shell-progress-fill" style={"width: #{bar_width_percent(point.accumulated_amount, points)}%"}></div>
                      </div>
                    </li>
                  <% end %>
                </ol>
              </article>
            <% end %>
          </section>

          <section id="payments-accumulation-table" class="app-shell-section-card">
            <div class="app-shell-table-wrapper">
              <table>
                <thead>
                  <tr>
                    <th scope="col"><%= gettext("Month") %></th>
                    <th scope="col"><%= gettext("Currency") %></th>
                    <th scope="col"><%= gettext("Monthly dividends") %></th>
                    <th scope="col"><%= gettext("Accumulated dividends") %></th>
                  </tr>
                </thead>
                <tbody>
                  <%= for point <- @accumulation_points do %>
                    <tr id={"payments-accumulation-row-#{String.downcase(point.currency_code)}-#{point.month_label}"}>
                      <td><%= point.month_label %></td>
                      <td><%= point.currency_code %></td>
                      <td><%= format_money(point.monthly_amount) %></td>
                      <td><%= format_money(point.accumulated_amount) %></td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </section>

          <section id="payments-yearly-comparison" class="app-shell-section-card">
            <div class="app-shell-section-header">
              <div>
                <h2 class="app-shell-section-title"><%= gettext("Yearly comparison") %></h2>
                <p><%= gettext("Year-by-year cumulative dividend progression by month.") %></p>
              </div>
            </div>
            <div class="app-shell-table-wrapper">
              <table>
                <thead>
                  <tr>
                    <th scope="col"><%= gettext("Year") %></th>
                    <th scope="col"><%= gettext("Month") %></th>
                    <th scope="col"><%= gettext("Currency") %></th>
                    <th scope="col"><%= gettext("Year-to-date accumulated") %></th>
                  </tr>
                </thead>
                <tbody>
                  <%= for row <- @yearly_comparison_rows do %>
                    <tr id={"payments-yearly-row-#{row.year}-#{row.month_number}-#{String.downcase(row.currency_code)}"}>
                      <td><%= row.year %></td>
                      <td><%= row.month_label %></td>
                      <td><%= row.currency_code %></td>
                      <td><%= format_money(row.accumulated_amount) %></td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </section>

          <%= if @group_mode == "list" do %>
            <section id="payments-list" class="app-shell-section-card">
              <div class="app-shell-table-wrapper">
                <table>
                  <thead>
                    <tr>
                      <th scope="col"><%= gettext("Date") %></th>
                      <th scope="col"><%= gettext("Security") %></th>
                      <th scope="col"><%= gettext("Account") %></th>
                      <th scope="col"><%= gettext("Amount") %></th>
                      <th scope="col"><%= gettext("Currency") %></th>
                      <th scope="col"><%= gettext("Notes") %></th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for row <- @dividend_rows do %>
                      <tr>
                        <td><%= row.date %></td>
                        <td><%= row.security_name %></td>
                        <td><%= row.account_name %></td>
                        <td><%= format_money(row.amount) %></td>
                        <td><%= row.currency_code %></td>
                        <td><%= row.notes || "—" %></td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            </section>
          <% else %>
            <section id="payments-grouped" class="app-shell-workspace-stack">
              <%= for group <- grouped_rows(@dividend_rows, @group_mode) do %>
                <article id={"payments-group-#{group.id}"} class="app-shell-section-card">
                  <div class="app-shell-section-header">
                    <h2 class="app-shell-section-title"><%= group.label %></h2>
                    <p><%= gettext("%{count} entries", count: length(group.rows)) %></p>
                  </div>
                  <p id={"payments-group-total-#{group.id}"}><%= totals_label(group.rows) %></p>
                  <div class="app-shell-table-wrapper">
                    <table>
                      <thead>
                        <tr>
                          <th scope="col"><%= gettext("Date") %></th>
                          <th scope="col"><%= gettext("Security") %></th>
                          <th scope="col"><%= gettext("Account") %></th>
                          <th scope="col"><%= gettext("Amount") %></th>
                          <th scope="col"><%= gettext("Currency") %></th>
                          <th scope="col"><%= gettext("Notes") %></th>
                        </tr>
                      </thead>
                      <tbody>
                        <%= for row <- group.rows do %>
                          <tr>
                            <td><%= row.date %></td>
                            <td><%= row.security_name %></td>
                            <td><%= row.account_name %></td>
                            <td><%= format_money(row.amount) %></td>
                            <td><%= row.currency_code %></td>
                            <td><%= row.notes || "—" %></td>
                          </tr>
                        <% end %>
                      </tbody>
                    </table>
                  </div>
                </article>
              <% end %>
            </section>
          <% end %>
        <% end %>
      <% end %>
    </AppShell.shell>
    """
  end

  defp load_report_state(socket, selected_portfolio_id \\ nil) do
    portfolios = Portfolios.list_portfolios()

    portfolio =
      resolve_current_portfolio(
        portfolios,
        selected_portfolio_id,
        Map.get(socket.assigns, :current_portfolio)
      )

    transactions =
      if portfolio do
        Ledger.list_transactions_for_portfolio(portfolio.id)
      else
        []
      end

    deposit_names =
      if portfolio do
        portfolio.id
        |> Portfolios.list_deposit_accounts_for_portfolio()
        |> Map.new(&{&1.id, &1.name})
      else
        %{}
      end

    security_lookup =
      Catalog.list_securities()
      |> Map.new(&{&1.id, &1})

    dividend_rows =
      transactions
      |> Enum.filter(&(&1.type == "dividend"))
      |> Enum.map(fn transaction ->
        %{
          id: transaction.id,
          date: transaction.date,
          security_id: transaction.security_id,
          security_name: security_display_name(Map.get(security_lookup, transaction.security_id)),
          account_name: Map.get(deposit_names, transaction.deposit_account_id, "—"),
          amount: transaction.amount,
          currency_code: transaction.currency_code,
          notes: transaction.notes
        }
      end)

    accumulation_points = monthly_accumulation_points(dividend_rows)
    yearly_comparison_rows = yearly_comparison_rows(dividend_rows)

    socket
    |> assign(:portfolios, portfolios)
    |> assign(:current_portfolio, portfolio)
    |> assign(:dividend_rows, dividend_rows)
    |> assign(:accumulation_points, accumulation_points)
    |> assign(:yearly_comparison_rows, yearly_comparison_rows)
  end

  defp resolve_current_portfolio(portfolios, nil, previous_portfolio) do
    previous_portfolio || List.first(portfolios)
  end

  defp resolve_current_portfolio(portfolios, selected_portfolio_id, previous_portfolio) do
    selected_portfolio = Portfolios.get_portfolio(selected_portfolio_id)

    cond do
      selected_portfolio ->
        selected_portfolio

      previous_portfolio && Enum.any?(portfolios, &(&1.id == previous_portfolio.id)) ->
        previous_portfolio

      true ->
        List.first(portfolios)
    end
  end

  defp grouped_rows(rows, "security") do
    rows
    |> Enum.group_by(& &1.security_id)
    |> Enum.map(fn {security_id, grouped_rows} ->
      label = grouped_rows |> List.first() |> Map.get(:security_name, "—")
      %{id: "security-#{security_id}", label: label, rows: grouped_rows}
    end)
    |> Enum.sort_by(& &1.label)
  end

  defp grouped_rows(rows, mode) do
    rows
    |> Enum.group_by(&period_key(&1.date, mode))
    |> Enum.map(fn {key, grouped_rows} ->
      %{id: slug(key), label: key, rows: grouped_rows}
    end)
    |> Enum.sort_by(& &1.label, :desc)
  end

  defp period_key(date, "month"), do: Calendar.strftime(date, "%Y-%m")
  defp period_key(date, "quarter"), do: "#{date.year}-Q#{div(date.month - 1, 3) + 1}"
  defp period_key(date, "year"), do: Integer.to_string(date.year)

  defp totals_label(rows) do
    totals =
      rows
      |> Enum.group_by(& &1.currency_code)
      |> Enum.map(fn {currency, grouped_rows} ->
        sum =
          Enum.reduce(grouped_rows, Decimal.new("0"), fn row, acc ->
            Decimal.add(acc, row.amount)
          end)

        "#{currency}: #{Decimal.to_string(sum, :normal)}"
      end)
      |> Enum.sort()

    Enum.join(totals, " · ")
  end

  defp accumulation_points_by_currency(points) do
    points
    |> Enum.group_by(& &1.currency_code)
    |> Enum.sort_by(fn {currency_code, _points} -> currency_code end)
  end

  defp monthly_accumulation_points(rows) do
    rows
    |> Enum.group_by(fn row -> {row.currency_code, row.date.year, row.date.month} end)
    |> Enum.map(fn {{currency_code, year, month}, grouped_rows} ->
      monthly_amount =
        Enum.reduce(grouped_rows, Decimal.new("0"), fn row, acc ->
          Decimal.add(acc, row.amount)
        end)

      %{
        currency_code: currency_code,
        year: year,
        month_number: month,
        month_label: :io_lib.format("~4..0B-~2..0B", [year, month]) |> List.to_string(),
        monthly_amount: monthly_amount
      }
    end)
    |> Enum.sort_by(&{&1.currency_code, &1.year, &1.month_number})
    |> Enum.chunk_by(& &1.currency_code)
    |> Enum.flat_map(fn currency_points ->
      {points, _running_total} =
        Enum.map_reduce(currency_points, Decimal.new("0"), fn point, running_total ->
          accumulated_amount = Decimal.add(running_total, point.monthly_amount)
          {Map.put(point, :accumulated_amount, accumulated_amount), accumulated_amount}
        end)

      points
    end)
  end

  defp yearly_comparison_rows(rows) do
    rows
    |> Enum.group_by(fn row -> {row.currency_code, row.date.year, row.date.month} end)
    |> Enum.map(fn {{currency_code, year, month}, grouped_rows} ->
      monthly_amount =
        Enum.reduce(grouped_rows, Decimal.new("0"), fn row, acc ->
          Decimal.add(acc, row.amount)
        end)

      %{
        currency_code: currency_code,
        year: year,
        month_number: month,
        month_label: :io_lib.format("~2..0B", [month]) |> List.to_string(),
        monthly_amount: monthly_amount
      }
    end)
    |> Enum.sort_by(&{&1.currency_code, &1.year, &1.month_number})
    |> Enum.chunk_by(&{&1.currency_code, &1.year})
    |> Enum.flat_map(fn year_points ->
      {points, _running_total} =
        Enum.map_reduce(year_points, Decimal.new("0"), fn point, running_total ->
          accumulated_amount = Decimal.add(running_total, point.monthly_amount)
          {Map.put(point, :accumulated_amount, accumulated_amount), accumulated_amount}
        end)

      points
    end)
  end

  defp bar_width_percent(_value, []), do: 0

  defp bar_width_percent(value, points) do
    max_value =
      Enum.reduce(points, Decimal.new("0"), fn point, acc ->
        if Decimal.compare(point.accumulated_amount, acc) == :gt do
          point.accumulated_amount
        else
          acc
        end
      end)

    if Decimal.equal?(max_value, Decimal.new("0")) do
      0
    else
      value
      |> Decimal.div(max_value)
      |> Decimal.mult(Decimal.new("100"))
      |> Decimal.round(2)
      |> Decimal.to_float()
    end
  end

  defp format_money(nil), do: "—"

  defp format_money(decimal) when is_struct(decimal, Decimal),
    do: Decimal.to_string(decimal, :normal)

  defp format_money(value), do: to_string(value)

  defp security_display_name(nil), do: "—"

  defp security_display_name(security) do
    "#{security.name} (#{security.symbol})"
  end

  defp group_controls_label, do: gettext("Payments grouping controls")

  defp group_controls_description do
    gettext("Choose how to group dividend payment rows in this report.")
  end

  defp group_mode_label("list"), do: gettext("List")
  defp group_mode_label("month"), do: gettext("Month")
  defp group_mode_label("quarter"), do: gettext("Quarter")
  defp group_mode_label("year"), do: gettext("Year")
  defp group_mode_label("security"), do: gettext("Security")

  defp slug(value), do: value |> String.downcase() |> String.replace(~r/[^a-z0-9]+/u, "-")
end
