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
  alias Portfolixir.Portfolios.ExternalFlows
  alias Portfolixir.Portfolios.Income
  alias Portfolixir.Portfolios.RealizedGains
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Format

  @months 1..12

  @impl true
  def mount(_params, _session, socket) do
    socket = assign(socket, :current_path, "/cashflow")

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

  # The Cash-flow facets are query state on one route (#672, decided
  # 2026-08-05), mirroring `/portfolio?tab=allocation`. Only Income has a read
  # today; the others appear as second-level tabs when theirs does, never as an
  # empty shell — which is also why no tab ROW renders yet: a row of one tab
  # answers no question.
  @facets ["income", "realized", "flows"]
  @default_facet "income"

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, socket |> assign(:facet, facet(params["tab"])) |> load_facet()}
  end

  # Each facet loads its own read once, on first visit (the income read stays
  # eager in mount — it is the default facet).
  defp load_facet(%{assigns: %{facet: "realized", portfolio: %{}}} = socket) do
    assign_new(socket, :realized, fn -> RealizedGains.report() end)
  end

  defp load_facet(%{assigns: %{facet: "flows", portfolio: %{}}} = socket) do
    assign_new(socket, :flows, fn -> ExternalFlows.report() end)
  end

  defp load_facet(socket), do: socket

  defp facet(tab) when tab in @facets, do: tab
  defp facet(_tab), do: @default_facet

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
    <AppShell.shell current_path={@current_path} page_title={gettext("Cash flow")}>
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
      page_title={gettext("Cash flow")}
      page_subtitle={gettext("Received dividends and interest")}
    >
      <div class="workspace-page">
        <AppShell.area_tabs tabs={AppShell.wealth_tabs(:income)} />

        <%!-- #724: with a second facet read the second-level tab row appears
             (the #672 rule: never an empty shell, never a row of one). The
             facets are query state on this one route. --%>
        <nav
          class="segmented-control"
          data-role="cashflow-facets"
          aria-label={gettext("Cash flow facet")}
        >
          <.link
            patch="/cashflow"
            class={["segmented-control__option", @facet == "income" && "is-active"]}
            aria-current={if @facet == "income", do: "true"}
          >
            <%= gettext("Income") %>
          </.link>
          <.link
            patch="/cashflow?tab=realized"
            class={["segmented-control__option", @facet == "realized" && "is-active"]}
            aria-current={if @facet == "realized", do: "true"}
          >
            <%= gettext("Realized gains") %>
          </.link>
          <.link
            patch="/cashflow?tab=flows"
            class={["segmented-control__option", @facet == "flows" && "is-active"]}
            aria-current={if @facet == "flows", do: "true"}
          >
            <%= gettext("Deposits & withdrawals") %>
          </.link>
        </nav>

        <%= if @facet == "realized" do %>
          <section class="workspace-section">
            <p class="muted" data-role="facet-composition">
              <%= gettext(
                "Realized gains and losses from FIFO-matched sales booked in the ledger, by each sale's close date. Excludes dividends and interest, deposits and withdrawals, and costs — each has its own Cash flow facet."
              ) %>
            </p>
            <div class="muted" data-role="realized-conversion">
              <span><%= gettext("Amounts in %{currency}", currency: @realized.base_currency) %></span>
              <details class="metric-tooltip metric-tooltip--inline">
                <summary aria-label={gettext("Conversion info")}>ⓘ</summary>
                <p role="tooltip">
                  <%= gettext(
                    "Each sale converted to %{currency} via the EUR hub at the most recent stored rate on or before its close date. A sale with no stored rate at that date is excluded from the totals and named here — never converted at a neighbouring date's rate.",
                    currency: @realized.base_currency
                  ) %>
                </p>
              </details>
            </div>
          </section>

          <section id="realized-annual" class="workspace-section">
            <h2><%= gettext("Realized per period") %></h2>
            <%= if @realized.excluded.count > 0 do %>
              <AppShell.data_note
                severity={:attention}
                id="realized-excluded"
                data-role="realized-excluded"
              >
                <%= ngettext(
                  "%{count} sale could not be converted — no stored rate at its close date — and is excluded from every total: %{securities}.",
                  "%{count} sales could not be converted — no stored rate at their close dates — and are excluded from every total: %{securities}.",
                  @realized.excluded.count,
                  count: @realized.excluded.count,
                  securities: Enum.join(@realized.excluded.securities, ", ")
                ) %>
                <a href="/portfolios"><%= gettext("Store the missing exchange rates.") %></a>
              </AppShell.data_note>
            <% end %>
            <%= if @realized.annual == [] do %>
              <p class="empty-state"><%= gettext("No closed sales booked yet.") %></p>
            <% else %>
              <table class="data-table">
                <thead>
                  <tr>
                    <th><%= gettext("Year") %></th>
                    <%= for month <- @months do %>
                      <th class="num"><%= month_label(month) %></th>
                    <% end %>
                    <th class="num col-subject"><%= gettext("Total") %></th>
                  </tr>
                </thead>
                <tbody>
                  <%= for year <- @realized.annual do %>
                    <tr>
                      <td>
                        <%= year.year %>
                        <span class="muted">(<%= @realized.base_currency %>)</span>
                      </td>
                      <%= for month <- @months do %>
                        <td class="num"><%= money(year.months[month]) %></td>
                      <% end %>
                      <td class="num col-subject"><%= money(year.total) %></td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            <% end %>
          </section>
        <% end %>

        <%= if @facet == "flows" do %>
          <section class="workspace-section">
            <p class="muted" data-role="facet-composition">
              <%= gettext(
                "Money paid in and taken out — the booked deposits and removals, by booking date. Excludes dividends and interest, realized gains, and costs — each has its own Cash flow facet. Securities delivered in or out and balance-snapshot jumps are not counted here; the performance's invested-capital figure includes them, which is why the two can differ."
              ) %>
            </p>
            <div class="muted" data-role="flows-conversion">
              <span><%= gettext("Amounts in %{currency}", currency: @flows.base_currency) %></span>
              <details class="metric-tooltip metric-tooltip--inline">
                <summary aria-label={gettext("Conversion info")}>ⓘ</summary>
                <p role="tooltip">
                  <%= gettext(
                    "Each flow converted to %{currency} via the EUR hub at the most recent stored rate on or before its booking date. A flow with no stored rate at that date is excluded from the totals and named here.",
                    currency: @flows.base_currency
                  ) %>
                </p>
              </details>
            </div>
          </section>

          <section id="flows-annual" class="workspace-section">
            <h2><%= gettext("Deposits and withdrawals per period") %></h2>
            <%= if @flows.excluded.count > 0 do %>
              <AppShell.data_note
                severity={:attention}
                id="flows-excluded"
                data-role="flows-excluded"
              >
                <%= ngettext(
                  "%{count} flow could not be converted — no stored rate at its booking date — and is excluded from every total. Affected account: %{accounts}.",
                  "%{count} flows could not be converted — no stored rate at their booking dates — and are excluded from every total. Affected accounts: %{accounts}.",
                  @flows.excluded.count,
                  count: @flows.excluded.count,
                  accounts: Enum.join(@flows.excluded.accounts, ", ")
                ) %>
                <a href="/portfolios"><%= gettext("Store the missing exchange rates.") %></a>
              </AppShell.data_note>
            <% end %>
            <%= if @flows.annual == [] do %>
              <p class="empty-state"><%= gettext("No deposits or withdrawals booked yet.") %></p>
            <% else %>
              <table class="data-table">
                <thead>
                  <tr>
                    <th><%= gettext("Year") %></th>
                    <th><%= gettext("Series") %></th>
                    <%= for month <- @months do %>
                      <th class="num"><%= month_label(month) %></th>
                    <% end %>
                    <th class="num col-subject"><%= gettext("Total") %></th>
                  </tr>
                </thead>
                <tbody>
                  <%= for year <- @flows.annual do %>
                    <tr>
                      <td rowspan="3">
                        <%= year.year %>
                        <span class="muted">(<%= @flows.base_currency %>)</span>
                      </td>
                      <td><%= gettext("Deposits") %></td>
                      <%= for month <- @months do %>
                        <td class="num"><%= money(year.months[month].deposits) %></td>
                      <% end %>
                      <td class="num col-subject"><%= money(year.deposits_total) %></td>
                    </tr>
                    <tr>
                      <td><%= gettext("Withdrawals") %></td>
                      <%= for month <- @months do %>
                        <td class="num"><%= money(year.months[month].withdrawals) %></td>
                      <% end %>
                      <td class="num col-subject"><%= money(year.withdrawals_total) %></td>
                    </tr>
                    <tr class="totals-row">
                      <td><%= gettext("Net") %></td>
                      <td class="num" colspan="12"></td>
                      <td class="num col-subject"><%= money(year.net_total) %></td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            <% end %>
          </section>
        <% end %>

        <%= if @facet == "income" do %>
        <section class="workspace-section">
          <%!-- The facet states its composition ONCE, in the operator's terms,
               and names what it leaves out (#672, EXPERIENCE.md "Every
               aggregate names what it aggregates", rules 1 and 4). The
               omissions are not trivia: they are the reason the sibling
               Cash-flow facets exist, and a reader who does not know them
               reads this page as "all the money that came in". --%>
          <p class="muted" data-role="facet-composition">
            <%= gettext("Dividends and interest booked in the ledger. Excludes realized gains from sales, deposits and withdrawals, and costs — each has its own Cash flow facet.") %>
          </p>
          <%!-- UX-DR11 (Sprint 5 Lane D): terse basis line in the sightline,
               conversion methodology behind the ⓘ tooltip. --%>
          <div class="muted" data-role="income-conversion">
            <span><%= gettext("Amounts in %{currency}", currency: @income.base_currency) %></span>
            <details class="metric-tooltip metric-tooltip--inline">
              <summary aria-label={gettext("Conversion info")}>ⓘ</summary>
              <p role="tooltip">
                <%= gettext(
                  "Amounts converted to %{currency} via the EUR hub at each booking date's stored rate; original currency retained.",
                  currency: @income.base_currency
                ) %>
              </p>
            </details>
          </div>
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
              <%!-- Track keeps the labels' intrinsic width so the container
                    scrolls on narrow viewports instead of clipping (#560,
                    UX-DR15). --%>
              <div class="income-chart-track">
              <%!-- Stacked, not summed (#672, rule 3): the matrix below splits
                    dividends from interest, and a chart that silently adds them
                    would disagree with its own backing table about what the
                    number is. Each segment is addressable, so the split
                    survives for anything reading the DOM. --%>
              <svg
                class="income-bars"
                viewBox={"0 0 #{max(length(@income_bars), 1)} 100"}
                preserveAspectRatio="none"
                role="img"
                aria-label={gettext("Dividends and interest per year")}
              >
                <g :for={{bar, index} <- Enum.with_index(@income_bars)}>
                  <rect
                    class="income-bar income-bar--dividends"
                    data-series="dividends"
                    data-year={bar.year}
                    x={index + 0.1}
                    y={100 - bar.height}
                    width="0.8"
                    height={bar.dividends_height}
                    phx-click="select_year"
                    phx-value-year={bar.year}
                  >
                    <title>
                      <%= bar.year %> · <%= gettext("Dividends") %>: <%= money(bar.dividends) %>
                    </title>
                  </rect>
                  <rect
                    class="income-bar income-bar--interest"
                    data-series="interest"
                    data-year={bar.year}
                    x={index + 0.1}
                    y={100 - bar.height + bar.dividends_height}
                    width="0.8"
                    height={bar.interest_height}
                    phx-click="select_year"
                    phx-value-year={bar.year}
                  >
                    <title>
                      <%= bar.year %> · <%= gettext("Interest") %>: <%= money(bar.interest) %>
                    </title>
                  </rect>
                </g>
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
              <div class="income-chart-track">
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
            </div>

            <%!-- The running total across the year (#672, the owner's Portfolio
                  Performance walkthrough of 2026-08-05). It answers a different
                  question from the bars beside it: not "what came in in April"
                  but "where did the year stand by April", which is what makes a
                  quiet month legible as a plateau rather than as a gap. Plain
                  server-rendered SVG, no animation (UX-DR5); the bars above
                  stay the backing data (UX-DR10). --%>
            <div id="income-accumulated-chart" class="income-chart">
              <div class="income-chart-track">
                <svg
                  class="income-bars income-accumulated"
                  viewBox="0 0 11 100"
                  preserveAspectRatio="none"
                  role="img"
                  aria-label={
                    gettext("Accumulated dividends and interest through %{year}",
                      year: @selected_year
                    )
                  }
                >
                  <polyline
                    class="income-accumulated-line"
                    fill="none"
                    points={accumulated_points(@income, @selected_year)}
                  />
                </svg>
                <div class="income-bar-labels">
                  <span
                    :for={point <- accumulated_months(@income, @selected_year)}
                    class="income-bar-label income-month-label"
                    data-month={point.month}
                    data-total={Decimal.to_string(Decimal.normalize(point.total), :normal)}
                  >
                    <strong><%= month_label(point.month) %></strong>
                    <span><%= money(point.total) %></span>
                  </span>
                </div>
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
        <% end %>
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
      # The segment heights are computed against the SAME max as the whole bar,
      # so the two stack to exactly the bar's height and the visual sum is the
      # table's total rather than a re-scaled approximation of it.
      %{
        year: year.year,
        total: year.total,
        dividends: year.dividends_total,
        interest: year.interest_total,
        height: bar_height(year.total, max),
        dividends_height: bar_height(year.dividends_total, max),
        interest_height: bar_height(year.interest_total, max)
      }
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

  # The running total, month by month, through the drilled year. A month with
  # nothing booked repeats the previous month's figure rather than dropping to
  # zero -- that is what "accumulated" means, and a dip would read as money
  # leaving.
  defp accumulated_months(income, year) do
    months =
      case Enum.find(income.annual, &(&1.year == year)) do
        %{months: m} -> m
        _ -> %{}
      end

    {points, _running} =
      Enum.map_reduce(1..12, Decimal.new(0), fn month, running ->
        cell = Map.get(months, month, %{dividends: Decimal.new(0), interest: Decimal.new(0)})
        running = running |> Decimal.add(cell.dividends) |> Decimal.add(cell.interest)
        {%{month: month, total: running}, running}
      end)

    points
  end

  # The polyline in the 0..11 x 0..100 viewBox. Scaled against the YEAR's total
  # (the last accumulated point), so the line ends at the top of the plot and
  # the shape reads as "how much of the year was in by month".
  defp accumulated_points(income, year) do
    points = accumulated_months(income, year)
    max = points |> List.last() |> Map.fetch!(:total)

    points
    |> Enum.map_join(" ", fn point ->
      "#{point.month - 1},#{100 - bar_height(point.total, max)}"
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
