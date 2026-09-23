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

  alias Portfolixir.Fx.RateSync
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Costs
  alias Portfolixir.Portfolios.ExternalFlows
  alias Portfolixir.Portfolios.Income
  alias Portfolixir.Portfolios.RealizedGains
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Format

  @months 1..12

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:current_path, "/cashflow")
      |> assign(:fx_backfilling, false)
      |> assign(:fx_backfill_result, nil)

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
  @facets ["income", "realized", "flows", "costs"]
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

  defp load_facet(%{assigns: %{facet: "costs", portfolio: %{}}} = socket) do
    assign_new(socket, :costs, fn -> Costs.report() end)
  end

  defp load_facet(socket), do: socket

  attr(:backfilling, :boolean, required: true)
  attr(:result, :any, default: nil)

  # The remedy control inside the exclusion note (UX-DR25: no dead control;
  # UX-DR26: the limit that remains is stated). The daily sync cannot fill a
  # past date; the backfill fetches the whole published ECB series once. A
  # date the ECB never published (a weekend, an unlisted currency) stays
  # excluded and named — the rule is unchanged, only the dates are filled.
  defp fx_backfill_control(assigns) do
    ~H"""
    <div class="fx-backfill" data-role="fx-backfill">
      <span class="muted">
        <%= gettext(
          "The daily rate sync cannot fill a past date. The backfill fetches the historical ECB series once and stores every published day; a day the ECB did not publish stays excluded."
        ) %>
      </span>
      <button
        type="button"
        id="fx-backfill-button"
        class="button-mini"
        phx-click="backfill_rates"
        disabled={@backfilling}
        phx-disable-with={gettext("Backfilling…")}
      >
        <%= if @backfilling do %>
          <span class="spinner" aria-hidden="true"></span> <%= gettext("Backfilling…") %>
        <% else %>
          <%= gettext("Backfill historical rates") %>
        <% end %>
      </button>
      <span :if={@backfilling} class="hint" data-role="fx-backfill-status" role="status">
        <%= gettext("Fetching the historical series…") %>
      </span>
      <span
        :if={match?({:ok, _}, @result)}
        class="hint"
        data-role="fx-backfill-result"
        role="status"
      >
        <%= ngettext(
          "Backfill stored %{count} rate.",
          "Backfill stored %{count} rates.",
          elem(@result, 1),
          count: elem(@result, 1)
        ) %>
      </span>
      <span
        :if={@result == :error}
        class="hint fx-sync-error"
        data-role="fx-backfill-result"
        role="status"
      >
        <%= gettext("Backfill failed — the provider did not answer.") %>
      </span>
    </div>
    """
  end

  defp facet(tab) when tab in @facets, do: tab
  defp facet(_tab), do: @default_facet

  @impl true
  def handle_event("select_year", %{"year" => year}, socket) do
    {:noreply, assign(socket, :selected_year, String.to_integer(year))}
  end

  def handle_event("clear_year", _params, socket) do
    {:noreply, assign(socket, :selected_year, nil)}
  end

  # Issue #737 (Sprint 9 D-1): the exclusion notices regain a live control —
  # the one-shot backfill of the historical ECB series through the existing
  # rate-sync path. It runs in the background like the Wealth page's sync;
  # the result lands inline in the note, and every loaded facet is re-read so
  # a sale whose close date just gained its rate leaves the exclusion at once.
  def handle_event("backfill_rates", _params, socket) do
    socket =
      socket
      |> assign(fx_backfilling: true, fx_backfill_result: nil)
      |> start_async(:backfill_rates, fn -> RateSync.backfill() end)

    {:noreply, socket}
  end

  @impl true
  def handle_async(:backfill_rates, {:ok, {:ok, %{upserted: count}}}, socket) do
    {:noreply,
     socket
     |> assign(fx_backfilling: false, fx_backfill_result: {:ok, count})
     |> reload_facets()}
  end

  def handle_async(:backfill_rates, {:ok, {:error, _reason}}, socket) do
    {:noreply, assign(socket, fx_backfilling: false, fx_backfill_result: :error)}
  end

  def handle_async(:backfill_rates, {:exit, _reason}, socket) do
    {:noreply, assign(socket, fx_backfilling: false, fx_backfill_result: :error)}
  end

  # Re-reads whatever this session already loaded (the facets are lazy), so the
  # figures on screen reflect the rates that just landed.
  defp reload_facets(%{assigns: %{portfolio: %{id: portfolio_id}}} = socket) do
    socket
    |> assign(:income, Income.for_portfolio(portfolio_id))
    |> reload_if_loaded(:realized, &RealizedGains.report/0)
    |> reload_if_loaded(:flows, &ExternalFlows.report/0)
    |> reload_if_loaded(:costs, &Costs.report/0)
  end

  defp reload_facets(socket), do: socket

  defp reload_if_loaded(socket, key, loader) do
    if Map.has_key?(socket.assigns, key), do: assign(socket, key, loader.()), else: socket
  end

  @impl true
  def render(%{portfolio: nil} = assigns) do
    ~H"""
    <AppShell.shell current_path={@current_path} page_title={gettext("Cash flow")}>
      <div class="workspace-page">
        <section class="workspace-section empty-state">
          <h2><%= gettext("Income") %></h2>
          <p><%= gettext("Income needs a depot with a cash account.") %></p>
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
      page_subtitle={facet_subtitle(@facet)}
    >
      <div class="workspace-page">
        <AppShell.area_tabs tabs={AppShell.wealth_tabs(:income)} />

        <%!-- #724: with a second facet read the second-level tab row appears
             (the #672 rule: never an empty shell, never a row of one). The
             facets are query state on this one route. --%>
        <div class="workspace-section workspace-section--controls">
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
          <.link
            patch="/cashflow?tab=costs"
            class={["segmented-control__option", @facet == "costs" && "is-active"]}
            aria-current={if @facet == "costs", do: "true"}
          >
            <%= gettext("Costs") %>
          </.link>
        </nav>
        </div>

        <%= if @facet == "realized" do %>
          <section class="workspace-section">
            <div class="summary-basis" data-role="facet-basis">
              <%= gettext("Amounts in %{currency} · FIFO-matched sales · all portfolios", currency: @realized.base_currency) %>
              <details class="metric-tooltip metric-tooltip--inline" data-role="facet-info">
                <summary aria-label={gettext("About this facet")}>ⓘ</summary>
                <p role="tooltip" data-role="facet-composition">
                  <%= gettext(
                    "Realized gains and losses from FIFO-matched sales booked in the ledger, across every portfolio, by each sale's close date. Excludes dividends and interest, deposits and withdrawals, and costs — each has its own Cash flow facet. Each sale converted to %{currency} via the EUR hub at the rate stored on its own close date; a sale with no stored rate for that day is excluded from the totals and named here — never converted at a neighbouring date's rate.",
                    currency: @realized.base_currency
                  ) %>
                </p>
              </details>
            </div>
          </section>

          <%!-- #807 (review C10, Part 5 Q2, signed by Sprint 13's D-3): the
               facet IS the Trades view. It opens with the three figures and
               the closed round-trips it aggregates; the year x month matrix
               it used to open with is the disclosure beneath. --%>
          <section id="realized-trades" class="workspace-section kpi-band">
            <%!-- UX-DR25: the count and the names of what an aggregate could
                 NOT include belong BESIDE the figure. The three figures, the
                 trades table and the matrix are all computed over the reduced
                 set, so the note leads the section rather than sitting under
                 the matrix — where the closing act's design critic found it
                 collapsed inside a disclosure, below every number it
                 qualifies, with its backfill remedy collapsed with it. --%>
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
                <.fx_backfill_control
                  backfilling={@fx_backfilling}
                  result={@fx_backfill_result}
                />
              </AppShell.data_note>
            <% end %>

            <%!-- Three lead figures in the built band (DESIGN.md → stat,
                 kpi-band__lead), not a new component. --%>
            <div id="realized-figures" class="kpi-band__lead" data-role="realized-figures">
              <article class="stat stat--lead">
                <span><%= gettext("Realized total") %></span>
                <strong data-role="realized-total">
                  <%= money(@realized.summary.realized_total) %><small class="value-suffix"><%= @realized.base_currency %></small>
                </strong>
              </article>
              <article class="stat stat--lead">
                <span><%= gettext("Hit rate") %></span>
                <strong data-role="realized-hit-rate">
                  <%= if @realized.summary.hit_rate do %>
                    <%= PortfolixirWeb.Format.percent(@realized.summary.hit_rate) %>%
                  <% else %>
                    —
                  <% end %>
                </strong>
                <small :if={@realized.summary.trade_count > 0} class="stat__sub">
                  <%= ngettext("over %{count} closed trade", "over %{count} closed trades",
                    @realized.summary.trade_count,
                    count: @realized.summary.trade_count
                  ) %>
                </small>
              </article>
              <article class="stat stat--lead">
                <span><%= gettext("Average holding period") %></span>
                <strong data-role="realized-holding-period">
                  <%= if @realized.summary.average_holding_period_days do %>
                    <%= ngettext(
                      "%{count} day",
                      "%{count} days",
                      @realized.summary.average_holding_period_days,
                      count: @realized.summary.average_holding_period_days
                    ) %>
                  <% else %>
                    —
                  <% end %>
                </strong>
              </article>
            </div>

            <%= if @realized.trades == [] do %>
              <p class="empty-state"><%= gettext("No closed sales booked yet.") %></p>
            <% else %>
              <div class="data-table-wrapper">
                <table id="realized-trades-table" class="data-table">
                  <thead>
                    <tr>
                      <th><%= gettext("Security") %></th>
                      <th><%= gettext("Bought → sold") %></th>
                      <th class="num"><%= gettext("Holding period") %></th>
                      <th class="num"><%= gettext("Quantity") %></th>
                      <th class="num"><%= gettext("Cost") %></th>
                      <th class="num"><%= gettext("Proceeds") %></th>
                      <th class="num col-subject"><%= gettext("Result") %></th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={trade <- @realized.trades} data-role="realized-trade">
                      <td>
                        <.link navigate={"/securities/#{trade.security_id}?tab=trades"}>
                          <%= trade.security_name %>
                        </.link>
                      </td>
                      <td>
                        <%= PortfolixirWeb.Format.date(trade.open_date) %> → <%= PortfolixirWeb.Format.date(
                          trade.close_date
                        ) %>
                      </td>
                      <td class="num">
                        <%= ngettext("%{count} day", "%{count} days", trade.holding_period_days,
                          count: trade.holding_period_days
                        ) %>
                      </td>
                      <td class="num"><%= PortfolixirWeb.Format.decimal(trade.quantity, 4) %></td>
                      <td class="num">
                        <%= money(trade.basis) %><small class="value-suffix"><%= trade.currency_code %></small>
                      </td>
                      <td class="num">
                        <%= money(trade.proceeds) %><small class="value-suffix"><%= trade.currency_code %></small>
                      </td>
                      <%!-- DESIGN.md → "semantic colour applies wherever a
                           sign exists, at every level of a table". The
                           percent sign is the caller's job (Format.percent/2
                           says so), and the sub-line is {components.stat}'s
                           `.stat__sub`, which is the shipped name. --%>
                      <td
                        class={["num", "col-subject", trade_sign_class(trade.realized_base)]}
                        data-role="trade-result"
                      >
                        <%= money(trade.realized_base) %><small class="value-suffix"><%= @realized.base_currency %></small>
                        <span class="stat__sub">
                          <%= PortfolixirWeb.Format.percent(trade.realized_pnl_pct) %>%
                        </span>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            <% end %>
          </section>

          <section id="realized-annual" class="workspace-section">
            <%!-- The section keeps its heading on the h1/h2/h3 ramp; only the
                 matrix itself is the disclosure, and the summary names what
                 opens rather than repeating the heading. --%>
            <h2><%= gettext("Realized per period") %></h2>
            <details id="realized-annual-disclosure" class="section-disclosure">
              <summary class="disclosure-summary">
                <AppShell.icon name={:chevron_right} class="disclosure-chevron" />
                <%= gettext("Year and month matrix") %>
              </summary>
              <p class="detail-tab-hint">
                <%= gettext(
                  "The same closed trades, aggregated by year and month."
                ) %>
              </p>
            <%= if @realized.annual == [] do %>
              <p class="empty-state"><%= gettext("No closed sales booked yet.") %></p>
            <% else %>
              <%!-- UX-DR15: the year x month matrix is wider than a phone, so it
                   owns its scroller. Without one the months are clipped by
                   .workspace-page and the sticky total column renders on top of
                   them (design-critic finding, measured at 390 px). --%>
              <div class="data-table-wrapper">
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
              </div>
            <% end %>
            </details>
          </section>
        <% end %>

        <%= if @facet == "flows" do %>
          <section class="workspace-section">
            <div class="summary-basis" data-role="facet-basis">
              <%= gettext("Amounts in %{currency} · external deposits and withdrawals · all portfolios", currency: @flows.base_currency) %>
              <details class="metric-tooltip metric-tooltip--inline" data-role="facet-info">
                <summary aria-label={gettext("About this facet")}>ⓘ</summary>
                <p role="tooltip" data-role="facet-composition">
                  <%= gettext(
                    "Money paid in and taken out — the booked deposits and removals across every portfolio, by booking date. Excludes dividends and interest, realized gains, and costs — each has its own Cash flow facet. Securities delivered in or out and balance-snapshot jumps are not counted here; the performance's invested-capital figure includes them, which is why the two can differ. Each flow converted to %{currency} via the EUR hub at the rate stored on its own booking date; a flow with no stored rate for that day is excluded from the totals and named here — never converted at a neighbouring date's rate.",
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
                <.fx_backfill_control
                  backfilling={@fx_backfilling}
                  result={@fx_backfill_result}
                />
              </AppShell.data_note>
            <% end %>
            <%= if @flows.annual == [] do %>
              <p class="empty-state"><%= gettext("No deposits or withdrawals booked yet.") %></p>
            <% else %>
              <%!-- UX-DR15: the year x month matrix is wider than a phone, so it
                   owns its scroller. Without one the months are clipped by
                   .workspace-page and the sticky total column renders on top of
                   them (design-critic finding, measured at 390 px). --%>
              <div class="data-table-wrapper">
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
              </div>
            <% end %>
          </section>
        <% end %>

        <%= if @facet == "costs" do %>
          <section class="workspace-section">
            <div class="summary-basis" data-role="facet-basis">
              <%= gettext("Amounts in %{currency} · fees and taxes at overview level · all portfolios", currency: @costs.base_currency) %>
              <details class="metric-tooltip metric-tooltip--inline" data-role="facet-info">
                <summary aria-label={gettext("About this facet")}>ⓘ</summary>
                <p role="tooltip" data-role="facet-composition">
                  <%= gettext(
                    "The fee and tax legs riding any transaction plus standalone fee and tax bookings across every portfolio, with tax refunds netted against taxes, by booking date. Gross amounts are never summed: a buy's gross includes its legs while a sell's is net of them. Excludes dividends and interest, realized gains, and deposits and withdrawals — each has its own Cash flow facet. This facet stays at overview level on purpose: totals per year, and no breakdown per security or per transaction. Each cost converted to %{currency} via the EUR hub at the rate stored on its own booking date; a cost with no stored rate for that day is excluded from the totals and named here — never converted at a neighbouring date's rate.",
                    currency: @costs.base_currency
                  ) %>
                </p>
              </details>
            </div>
          </section>

          <section id="costs-annual" class="workspace-section">
            <h2><%= gettext("Fees and taxes per period") %></h2>
            <%= if @costs.excluded.count > 0 do %>
              <AppShell.data_note
                severity={:attention}
                id="costs-excluded"
                data-role="costs-excluded"
              >
                <%= ngettext(
                  "%{count} cost could not be converted — no stored rate at its booking date — and is excluded from every total. Affected currency: %{currencies}.",
                  "%{count} costs could not be converted — no stored rate at their booking dates — and are excluded from every total. Affected currencies: %{currencies}.",
                  @costs.excluded.count,
                  count: @costs.excluded.count,
                  currencies: Enum.join(@costs.excluded.currencies, ", ")
                ) %>
                <.fx_backfill_control
                  backfilling={@fx_backfilling}
                  result={@fx_backfill_result}
                />
              </AppShell.data_note>
            <% end %>
            <%= if @costs.annual == [] do %>
              <p class="empty-state"><%= gettext("No fees or taxes booked yet.") %></p>
            <% else %>
              <%!-- UX-DR15: the year x month matrix is wider than a phone, so it
                   owns its scroller. Without one the months are clipped by
                   .workspace-page and the sticky total column renders on top of
                   them (design-critic finding, measured at 390 px). --%>
              <div class="data-table-wrapper">
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
                    <%= for year <- @costs.annual do %>
                      <tr>
                        <td rowspan="3">
                          <%= year.year %>
                          <span class="muted">(<%= @costs.base_currency %>)</span>
                        </td>
                        <td><%= gettext("Fees") %></td>
                        <%= for month <- @months do %>
                          <td class="num"><%= money(year.months[month].fees) %></td>
                        <% end %>
                        <td class="num col-subject"><%= money(year.fees_total) %></td>
                      </tr>
                      <tr>
                        <td><%= gettext("Taxes") %></td>
                        <%= for month <- @months do %>
                          <td class="num"><%= money(year.months[month].taxes) %></td>
                        <% end %>
                        <td class="num col-subject"><%= money(year.taxes_total) %></td>
                      </tr>
                      <tr class="totals-row">
                        <td><%= gettext("Total") %></td>
                        <td class="num" colspan="12"></td>
                        <td class="num col-subject"><%= money(year.total) %></td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
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
          <div class="summary-basis" data-role="facet-basis">
              <%= gettext("Amounts in %{currency} · dividends and interest · this portfolio", currency: @income.base_currency) %>
              <details class="metric-tooltip metric-tooltip--inline" data-role="facet-info">
                <summary aria-label={gettext("About this facet")}>ⓘ</summary>
                <p role="tooltip" data-role="facet-composition">
                  <%= gettext(
                    "Dividends and interest booked in the ledger for this portfolio; the other three facets cover every portfolio, so with more than one portfolio their figures are wider than this one. Excludes realized gains from sales, deposits and withdrawals, and costs — each has its own Cash flow facet. Amounts converted to %{currency} via the EUR hub at each booking date's stored rate; original currency retained.",
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
              <%!-- The stack says what it stacks (UX-DR7, issue 794): a legend
                    names the two series, and a segment tall enough carries its
                    value as text. --%>
              <ul class="chart-legend income-legend" data-role="income-legend">
                <li class="chart-legend__item">
                  <span class="chart-legend__swatch income-legend__swatch--dividends" aria-hidden="true">
                  </span>
                  <%= gettext("Dividends") %>
                </li>
                <li class="chart-legend__item">
                  <span class="chart-legend__swatch income-legend__swatch--interest" aria-hidden="true">
                  </span>
                  <%= gettext("Interest") %>
                </li>
              </ul>
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
                  <%!-- A year without bookings keeps its slot (issue 794):
                        a baseline tick, so time is not misrepresented. --%>
                  <rect
                    :if={bar.empty?}
                    class="income-bar income-bar--empty"
                    data-year={bar.year}
                    data-empty="true"
                    x={index + 0.1}
                    y="99.4"
                    width="0.8"
                    height="0.6"
                  />
                  <rect
                    :if={not bar.empty?}
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
                    :if={not bar.empty?}
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
              <%!-- Direct labels (UX-DR7, issue 794): the value inside a
                    segment at least 24 px tall, as HTML over the stretched SVG
                    so the digits never distort. Decorative — the table and
                    the year labels carry the numbers. --%>
              <div class="income-bar-values" aria-hidden="true">
                <%= for {bar, index} <- Enum.with_index(@income_bars) do %>
                  <span
                    :if={bar.dividends_label?}
                    class="income-bar-value income-bar-value--dividends"
                    data-year={bar.year}
                    data-series="dividends"
                    style={"left: #{value_x(index, length(@income_bars))}%; top: #{Float.round(100 - bar.height + bar.dividends_height / 2, 2)}%"}
                  >
                    <%= money(bar.dividends) %>
                  </span>
                  <span
                    :if={bar.interest_label?}
                    class="income-bar-value income-bar-value--interest"
                    data-year={bar.year}
                    data-series="interest"
                    style={"left: #{value_x(index, length(@income_bars))}%; top: #{Float.round(100 - bar.interest_height / 2, 2)}%"}
                  >
                    <%= money(bar.interest) %>
                  </span>
                <% end %>
              </div>
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
                  <span><%= if bar.empty?, do: "–", else: money(bar.total) %></span>
                </button>
              </div>
              </div>
            </div>

            <%!-- The one uniform chart-as-table disclosure (UX-DR10, issue
                 794): adjacency was not the disclosure. UX-DR15: the year x
                 month matrix is wider than a phone, so it owns its scroller.
                 Without one the months are clipped by .workspace-page and the
                 sticky total column renders on top of them (design-critic
                 finding, measured at 390 px). --%>
            <details class="perf-table-disclosure" data-role="income-annual-disclosure">
            <summary class="disclosure-summary">
              <AppShell.icon name={:chevron_right} size={12} class="disclosure-chevron" />
              <%= gettext("Data as table") %>
            </summary>
            <p class="hint" data-role="disclosure-purpose">
              <%= gettext("Year × month, dividends and interest apart — the chart data without the chart.") %>
            </p>
            <div class="data-table-wrapper">
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
                        <td class="num"><%= matrix_cell(year.months[month].dividends) %></td>
                      <% end %>
                      <td class="num is-total"><%= money(year.dividends_total) %></td>
                    </tr>
                    <tr class="income-year-row">
                      <td><%= gettext("Interest") %></td>
                      <%= for month <- @months do %>
                        <td class="num"><%= matrix_cell(year.months[month].interest) %></td>
                      <% end %>
                      <td class="num is-total"><%= money(year.interest_total) %></td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
            </details>
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

            <%!-- The drilled year's table behind the same disclosure (UX-DR10,
                 issue 794); the wrapper owns its scroller (UX-DR15). --%>
            <details class="perf-table-disclosure" data-role="income-payments-disclosure">
            <summary class="disclosure-summary">
              <AppShell.icon name={:chevron_right} size={12} class="disclosure-chevron" />
              <%= gettext("Data as table") %>
            </summary>
            <p class="hint" data-role="disclosure-purpose">
              <%= gettext("Every payment of the year with gross, tax and net.") %>
            </p>
            <div class="data-table-wrapper">
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
            </div>
            </details>
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
            <%!-- UX-DR15: the year x month matrix is wider than a phone, so it
                 owns its scroller. Without one the months are clipped by
                 .workspace-page and the sticky total column renders on top of
                 them (design-critic finding, measured at 390 px). --%>
            <div class="data-table-wrapper">
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
            </div>
          <% end %>
        </section>
        <% end %>
      </div>
    </AppShell.shell>
    """
  end

  # The plot is 140 px tall (`.income-bars` in app.css); a segment carries its
  # value as text from 24 px (issue 794). The two constants are the pixel
  # arithmetic behind the label flags below.
  @chart_height_px 140
  @label_min_px 24

  # Year bars for the income overview (#415): height as a 0–100 percentage of
  # the biggest year, so the tallest bar fills the plot and the rest scale to
  # it. Every year between the first and the last booking gets a slot (issue
  # 794), an empty one marked, so the axis never skips time.
  defp income_bars([]), do: []

  defp income_bars(annual) do
    max = annual |> Enum.map(& &1.total) |> Enum.reduce(Decimal.new(0), &Decimal.max/2)
    by_year = Map.new(annual, &{&1.year, &1})
    {first, last} = annual |> Enum.map(& &1.year) |> Enum.min_max()

    for year <- first..last do
      case Map.get(by_year, year) do
        nil ->
          %{
            year: year,
            empty?: true,
            total: Decimal.new(0),
            dividends: Decimal.new(0),
            interest: Decimal.new(0),
            height: 0.0,
            dividends_height: 0.0,
            interest_height: 0.0,
            dividends_label?: false,
            interest_label?: false
          }

        row ->
          # The segment heights are computed against the SAME max as the whole
          # bar, so the two stack to exactly the bar's height and the visual
          # sum is the table's total rather than a re-scaled approximation.
          dividends_height = bar_height(row.dividends_total, max)
          interest_height = bar_height(row.interest_total, max)

          %{
            year: year,
            empty?: false,
            total: row.total,
            dividends: row.dividends_total,
            interest: row.interest_total,
            height: bar_height(row.total, max),
            dividends_height: dividends_height,
            interest_height: interest_height,
            dividends_label?: labelled?(dividends_height),
            interest_label?: labelled?(interest_height)
          }
      end
    end
  end

  defp labelled?(height_percent), do: height_percent / 100 * @chart_height_px >= @label_min_px

  # The label's horizontal centre over bar `index` of `count`, in percent of
  # the plot width — the same slot the stretched SVG gives the bar.
  defp value_x(index, count), do: Float.round((index + 0.5) / count * 100, 2)

  # A zero cell in the matrix is a quiet dash (Part 4 rule 6 of the 2026-09-12
  # review), so the non-zero cells are what the eye finds; totals stay
  # figures.
  defp matrix_cell(value) do
    if Decimal.equal?(value, 0) do
      Phoenix.HTML.raw(~s(<span class="matrix-zero">–</span>))
    else
      money(value)
    end
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
  # A realised result is signed, so it carries the sign colour every other
  # signed figure in the app carries; a break-even trade carries none.
  defp trade_sign_class(%Decimal{} = value) do
    case Decimal.compare(value, Decimal.new(0)) do
      :gt -> "is-positive"
      :lt -> "is-negative"
      :eq -> nil
    end
  end

  defp trade_sign_class(_value), do: nil

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

  # The subtitle names the facet (UX-DR21 extended, 2026-09-12): the parent's
  # first facet is never the subtitle of its siblings.
  defp facet_subtitle("realized"), do: gettext("Realized gains and losses from sales")
  defp facet_subtitle("flows"), do: gettext("Deposits and withdrawals")
  defp facet_subtitle("costs"), do: gettext("Fees and taxes")
  defp facet_subtitle(_income), do: gettext("Received dividends and interest")
end
