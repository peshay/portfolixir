defmodule PortfolixirWeb.PaymentsReportLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias PortfolixirWeb.AppShell

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

        <section id="payments-group-controls" class="app-shell-section-card">
          <form id="payments-group-form" phx-change="set_group_mode" class="app-shell-form-grid">
            <div class="app-shell-field app-shell-field--full">
              <label for="payments-group-mode"><%= gettext("Group by") %></label>
              <select id="payments-group-mode" name="group_mode">
                <%= for mode <- @group_modes do %>
                  <option value={mode} selected={mode == @group_mode}><%= group_mode_label(mode) %></option>
                <% end %>
              </select>
            </div>
          </form>
        </section>

        <%= if Enum.empty?(@dividend_rows) do %>
          <section id="payments-empty-state" class="app-shell-empty-state">
            <h2><%= gettext("No dividend payments yet") %></h2>
            <p><%= gettext("Record dividend transactions to populate this report.") %></p>
          </section>
        <% else %>
          <%= if @group_mode == "list" do %>
            <section id="payments-list" class="app-shell-section-card">
              <div class="app-shell-table-wrapper">
                <table>
                  <thead>
                    <tr>
                      <th><%= gettext("Date") %></th>
                      <th><%= gettext("Security") %></th>
                      <th><%= gettext("Account") %></th>
                      <th><%= gettext("Amount") %></th>
                      <th><%= gettext("Currency") %></th>
                      <th><%= gettext("Notes") %></th>
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
                          <th><%= gettext("Date") %></th>
                          <th><%= gettext("Security") %></th>
                          <th><%= gettext("Account") %></th>
                          <th><%= gettext("Amount") %></th>
                          <th><%= gettext("Currency") %></th>
                          <th><%= gettext("Notes") %></th>
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

    security_names =
      Catalog.list_securities()
      |> Map.new(&{&1.id, &1.name})

    dividend_rows =
      transactions
      |> Enum.filter(&(&1.type == "dividend"))
      |> Enum.map(fn transaction ->
        %{
          id: transaction.id,
          date: transaction.date,
          security_name: Map.get(security_names, transaction.security_id, "—"),
          account_name: Map.get(deposit_names, transaction.deposit_account_id, "—"),
          amount: transaction.amount,
          currency_code: transaction.currency_code,
          notes: transaction.notes
        }
      end)

    socket
    |> assign(:portfolios, portfolios)
    |> assign(:current_portfolio, portfolio)
    |> assign(:dividend_rows, dividend_rows)
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
    |> Enum.group_by(& &1.security_name)
    |> Enum.map(fn {name, grouped_rows} ->
      %{id: slug(name), label: name, rows: grouped_rows}
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

  defp format_money(nil), do: "—"

  defp format_money(decimal) when is_struct(decimal, Decimal),
    do: Decimal.to_string(decimal, :normal)

  defp format_money(value), do: to_string(value)

  defp group_mode_label("list"), do: gettext("List")
  defp group_mode_label("month"), do: gettext("Month")
  defp group_mode_label("quarter"), do: gettext("Quarter")
  defp group_mode_label("year"), do: gettext("Year")
  defp group_mode_label("security"), do: gettext("Security")

  defp slug(value), do: value |> String.downcase() |> String.replace(~r/[^a-z0-9]+/u, "-")
end
