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

    # ADR-0024: the empty state keys on the bookkeeping entities, not on the
    # internal portfolio compatibility record. Accounts always carry a
    # portfolio FK, so `first_portfolio/0` is guaranteed in the second branch;
    # it stays the internal mechanism of the portfolio-bound income read.
    case Portfolios.count_securities_accounts() + Portfolios.count_cash_accounts() do
      0 ->
        {:ok, assign(socket, portfolio: nil, income: nil, selected_year: nil)}

      _accounts ->
        portfolio = Portfolios.first_portfolio()
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
          <p><%= gettext("Create a depot and cash account first to see received dividends and interest.") %></p>
          <.link navigate="/portfolios" class="button"><%= gettext("Create a depot and cash account") %></.link>
        </section>
      </div>
    </AppShell.shell>
    """
  end

  def render(assigns) do
    assigns =
      assigns
      |> assign(:months, @months)
      |> assign(:income_bars, income_bars(assigns.income.annual))
      |> assign(:top_contributors, Enum.take(assigns.income.positions, 5))

    ~H"""
    <AppShell.shell
      current_path={@current_path}
      page_title={gettext("Income")}
      page_subtitle={gettext("Received dividends and interest")}
    >
      <div class="workspace-page">
        <AppShell.area_tabs tabs={AppShell.wealth_tabs(:income)} />

        <section class="workspace-section">
          <p class="muted">
            <%= gettext(
              "Amounts converted to %{currency} via the EUR hub at each booking date's stored rate; original currency retained.",
              currency: @income.base_currency
            ) %>
          </p>
        </section>

        <section id="income-annual" class="workspace-section">
          <h2><%= gettext("Annual overview") %></h2>
          <%= if @income.annual == [] do %>
            <p class="empty-state"><%= gettext("No dividends or interest booked yet.") %></p>
          <% else %>
            <%!-- A visual read of total income per year sits above the matrix,
                  which stays as the backing data (chart-as-table, UX-DR10). The
                  bars are plain server-rendered SVG with no animation, so
                  prefers-reduced-motion needs nothing extra (UX-DR5). --%>
            <div id="income-chart" class="income-chart">
              <svg
                class="income-bars"
                viewBox={"0 0 #{max(length(@income_bars), 1)} 100"}
                preserveAspectRatio="none"
                role="img"
                aria-label={gettext("Total income per year")}
              >
                <rect
                  :for={{bar, index} <- Enum.with_index(@income_bars)}
                  class="income-bar"
                  data-year={bar.year}
                  x={index + 0.1}
                  y={100 - bar.height}
                  width="0.8"
                  height={bar.height}
                  phx-click="select_year"
                  phx-value-year={bar.year}
                >
                  <title><%= bar.year %>: <%= money(bar.total) %></title>
                </rect>
              </svg>
              <%!-- The year labels are drill buttons: clicking one opens that
                    year's detail + per-month breakdown below (#415 follow-up). --%>
              <div class="income-bar-labels">
                <button
                  :for={bar <- @income_bars}
                  type="button"
                  class={["income-bar-label", @selected_year == bar.year && "is-active"]}
                  data-year={bar.year}
                  phx-click="select_year"
                  phx-value-year={bar.year}
                  aria-pressed={to_string(@selected_year == bar.year)}
                >
                  <strong><%= bar.year %></strong>
                  <span><%= money(bar.total) %></span>
                </button>
              </div>
            </div>

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

            <%!-- Per-month breakdown of the drilled year; the payments table
                  below stays as the backing data (UX-DR10). --%>
            <div id="income-month-chart" class="income-chart">
              <svg
                class="income-bars"
                viewBox="0 0 12 100"
                preserveAspectRatio="none"
                role="img"
                aria-label={gettext("Income per month in %{year}", year: @selected_year)}
              >
                <rect
                  :for={bar <- month_bars(@income, @selected_year)}
                  class="income-bar income-month-bar"
                  data-month={bar.month}
                  x={bar.month - 1 + 0.1}
                  y={100 - bar.height}
                  width="0.8"
                  height={bar.height}
                >
                  <title><%= month_label(bar.month) %>: <%= money(bar.total) %></title>
                </rect>
              </svg>
              <div class="income-bar-labels" aria-hidden="true">
                <span :for={bar <- month_bars(@income, @selected_year)} class="income-bar-label income-month-label">
                  <%= month_label(bar.month) %>
                </span>
              </div>
            </div>

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

        <%= if @top_contributors != [] do %>
          <section id="income-top-contributors" class="workspace-section">
            <h2><%= gettext("Top contributors") %></h2>
            <ol class="contributor-list">
              <li :for={row <- @top_contributors} class="contributor-row">
                <span class="contributor-name">
                  <%= row.security_name || gettext("Interest") %>
                </span>
                <span class="contributor-figures">
                  <strong><%= money(row.gross) %></strong>
                  <span class="muted">
                    <%= gettext("net %{net}", net: money(row.net)) %>
                  </span>
                </span>
              </li>
            </ol>
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

  # Year bars for the income overview (#415): height as a 0–100 percentage of
  # the biggest year, so the tallest bar fills the plot and the rest scale to
  # it. Sorted chronologically so the trend reads left-to-right.
  defp income_bars([]), do: []

  defp income_bars(annual) do
    max = annual |> Enum.map(& &1.total) |> Enum.reduce(Decimal.new(0), &Decimal.max/2)

    annual
    |> Enum.sort_by(& &1.year)
    |> Enum.map(fn year ->
      %{year: year.year, total: year.total, height: bar_height(year.total, max)}
    end)
  end

  # Per-month income totals (dividends + interest) for one drilled year, scaled
  # to the busiest month (#415 follow-up). Always 12 slots so the x-axis is
  # stable; months with nothing booked render as a zero-height bar.
  defp month_bars(income, year) do
    months =
      case Enum.find(income.annual, &(&1.year == year)) do
        %{months: m} -> m
        _ -> %{}
      end

    totals =
      for month <- 1..12 do
        cell = Map.get(months, month, %{dividends: Decimal.new(0), interest: Decimal.new(0)})
        {month, Decimal.add(cell.dividends, cell.interest)}
      end

    max = totals |> Enum.map(&elem(&1, 1)) |> Enum.reduce(Decimal.new(0), &Decimal.max/2)

    Enum.map(totals, fn {month, total} ->
      %{month: month, total: total, height: bar_height(total, max)}
    end)
  end

  defp bar_height(total, max) do
    if Decimal.compare(max, 0) == :gt do
      total |> Decimal.div(max) |> Decimal.mult(100) |> Decimal.to_float() |> Float.round(2)
    else
      0.0
    end
  end

  defp detail_for(income, year) do
    income.transactions
    |> Enum.filter(&(&1.year == year))
    |> Enum.sort_by(& &1.date, Date)
  end

  defp money(value), do: Format.money(value)

  # Month abbreviations through gettext, so the German matrix reads
  # Mär/Mai/Okt/Dez instead of leaking strftime's English %b output
  # (Steve UAT, reconsolidation).
  defp month_label(1), do: gettext("Jan")
  defp month_label(2), do: gettext("Feb")
  defp month_label(3), do: gettext("Mar")
  defp month_label(4), do: gettext("Apr")
  defp month_label(5), do: gettext("May")
  defp month_label(6), do: gettext("Jun")
  defp month_label(7), do: gettext("Jul")
  defp month_label(8), do: gettext("Aug")
  defp month_label(9), do: gettext("Sep")
  defp month_label(10), do: gettext("Oct")
  defp month_label(11), do: gettext("Nov")
  defp month_label(12), do: gettext("Dec")

  defp kind_label("dividend"), do: gettext("Dividend")
  defp kind_label("interest"), do: gettext("Interest")
end
