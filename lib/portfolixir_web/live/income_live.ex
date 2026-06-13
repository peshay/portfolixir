defmodule PortfolixirWeb.IncomeLive do
  @moduledoc """
  Income report: the dividends and interest already booked in the ledger, seen
  retrospectively (issue #331).

  Renders the annual year × month matrix (split into a dividends and an interest
  series, with a yearly totals column), a per-position table (security, gross,
  withheld tax, net, number of payments, last payment) and, when a year is
  selected, the per-transaction detail for that year. All figures come from
  `Portfolixir.Portfolios.Income`, the same derived read the API exposes;
  amounts are converted to the portfolio base currency through the EUR hub with
  the original currency retained.
  """

  use PortfolixirWeb, :live_view

  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Income
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Format

  @months 1..12

  @impl true
  def mount(_params, _session, socket) do
    socket = assign(socket, :current_path, "/income")

    case Portfolios.first_portfolio() do
      nil ->
        {:ok, assign(socket, portfolio: nil, income: nil, selected_year: nil)}

      portfolio ->
        income = Income.for_portfolio(portfolio.id)

        socket =
          socket
          |> assign(:portfolio, portfolio)
          |> assign(:income, income)
          |> assign(:selected_year, nil)

        {:ok, socket}
    end
  end

  @impl true
  def handle_event("select_year", %{"year" => year}, socket) do
    {:noreply, assign(socket, :selected_year, String.to_integer(year))}
  end

  def handle_event("clear_year", _params, socket) do
    {:noreply, assign(socket, :selected_year, nil)}
  end

  @impl true
  def render(%{portfolio: nil} = assigns) do
    ~H"""
    <AppShell.shell current_path={@current_path} page_title={gettext("Income")}>
      <div class="workspace-page">
        <section class="workspace-section empty-state">
          <h2><%= gettext("Income") %></h2>
          <p><%= gettext("Create one portfolio first to see received dividends and interest.") %></p>
          <.link navigate="/portfolios" class="button"><%= gettext("Create one portfolio") %></.link>
        </section>
      </div>
    </AppShell.shell>
    """
  end

  def render(assigns) do
    assigns = assign(assigns, :months, @months)

    ~H"""
    <AppShell.shell
      current_path={@current_path}
      page_title={gettext("Income")}
      page_subtitle={gettext("Received dividends and interest")}
    >
      <div class="workspace-page">
        <section class="workspace-section">
          <p class="muted"><%= @income.conversion_note %></p>
        </section>

        <section id="income-annual" class="workspace-section">
          <h2><%= gettext("Annual overview") %></h2>
          <%= if @income.annual == [] do %>
            <p class="empty-state"><%= gettext("No dividends or interest booked yet.") %></p>
          <% else %>
            <table class="data-table">
              <thead>
                <tr>
                  <th><%= gettext("Year") %></th>
                  <th><%= gettext("Series") %></th>
                  <%= for month <- @months do %>
                    <th class="num"><%= month_label(month) %></th>
                  <% end %>
                  <th class="num"><%= gettext("Total") %></th>
                </tr>
              </thead>
              <tbody>
                <%= for year <- @income.annual do %>
                  <tr class="income-year-row">
                    <td rowspan="2">
                      <button
                        type="button"
                        class="link-button"
                        phx-click="select_year"
                        phx-value-year={year.year}
                      >
                        <%= year.year %>
                      </button>
                      <span class="muted">(<%= @income.base_currency %>)</span>
                    </td>
                    <td><%= gettext("Dividends") %></td>
                    <%= for month <- @months do %>
                      <td class="num"><%= money(year.months[month].dividends) %></td>
                    <% end %>
                    <td class="num"><%= money(year.dividends_total) %></td>
                  </tr>
                  <tr class="income-year-row">
                    <td><%= gettext("Interest") %></td>
                    <%= for month <- @months do %>
                      <td class="num"><%= money(year.months[month].interest) %></td>
                    <% end %>
                    <td class="num"><%= money(year.interest_total) %></td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          <% end %>
        </section>

        <%= if @selected_year do %>
          <section id="income-detail" class="workspace-section">
            <h2>
              <%= gettext("Payments in %{year}", year: @selected_year) %>
              <button type="button" class="button button-ghost" phx-click="clear_year">
                <%= gettext("Close") %>
              </button>
            </h2>
            <table class="data-table">
              <thead>
                <tr>
                  <th><%= gettext("Date") %></th>
                  <th><%= gettext("Type") %></th>
                  <th><%= gettext("Security") %></th>
                  <th class="num"><%= gettext("Gross") %></th>
                  <th class="num"><%= gettext("Tax") %></th>
                  <th class="num"><%= gettext("Net") %></th>
                  <th><%= gettext("Currency") %></th>
                </tr>
              </thead>
              <tbody>
                <%= for tx <- detail_for(@income, @selected_year) do %>
                  <tr>
                    <td><%= tx.date %></td>
                    <td><%= kind_label(tx.kind) %></td>
                    <td><%= tx.security_name || gettext("Interest") %></td>
                    <td class="num"><%= money(tx.gross) %></td>
                    <td class="num"><%= money(tx.tax) %></td>
                    <td class="num"><%= money(tx.net) %></td>
                    <td><%= tx.currency %></td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </section>
        <% end %>

        <section id="income-positions" class="workspace-section">
          <h2><%= gettext("Per position") %></h2>
          <%= if @income.positions == [] do %>
            <p class="empty-state"><%= gettext("No dividends or interest booked yet.") %></p>
          <% else %>
            <table class="data-table">
              <thead>
                <tr>
                  <th><%= gettext("Security") %></th>
                  <th><%= gettext("Currency") %></th>
                  <th class="num"><%= gettext("Gross") %></th>
                  <th class="num"><%= gettext("Withheld tax") %></th>
                  <th class="num"><%= gettext("Net") %></th>
                  <th class="num"><%= gettext("Payments") %></th>
                  <th><%= gettext("Last payment") %></th>
                </tr>
              </thead>
              <tbody>
                <%= for row <- @income.positions do %>
                  <tr>
                    <td><%= row.security_name || gettext("Interest") %></td>
                    <td><%= row.security_currency %></td>
                    <td class="num"><%= money(row.gross) %></td>
                    <td class="num"><%= money(row.tax) %></td>
                    <td class="num"><%= money(row.net) %></td>
                    <td class="num"><%= row.payment_count %></td>
                    <td><%= row.last_payment %></td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          <% end %>
        </section>
      </div>
    </AppShell.shell>
    """
  end

  defp detail_for(income, year) do
    income.transactions
    |> Enum.filter(&(&1.year == year))
    |> Enum.sort_by(& &1.date, Date)
  end

  defp money(value), do: Format.money(value)

  defp month_label(month) do
    {:ok, date} = Date.new(2000, month, 1)
    Calendar.strftime(date, "%b")
  end

  defp kind_label("dividend"), do: gettext("Dividend")
  defp kind_label("interest"), do: gettext("Interest")
end
