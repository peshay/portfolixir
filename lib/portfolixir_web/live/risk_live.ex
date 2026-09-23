defmodule PortfolixirWeb.RiskLive do
  @moduledoc """
  The Wealth area's **Risk** tab (Sprint 14 D-2, design pick E1-A; board
  `ux-design-2026-09-20/01-wealth-risk-surface`).

  The human half of two agent surfaces on one page, because they answer one
  question — "how concentrated am I, and how much does this portfolio move":

    * the **concentration lens** of FR-8/FR-9/FR-10 (`Portfolixir.Portfolios.Risk`),
      agent-only since it shipped: the Top-N single names with their weight and
      the threshold each is above or below, the HHI with its band, and the
      asset-class cap violations;
    * the **portfolio metrics** of FR-40 (ADR-0047 §3) that ride the same read:
      volatility, maximum drawdown, risk-adjusted return and the Top-N
      correlation matrix — the matrix behind a closed disclosure.

  Everything is on the **steerable basis**, scoped by the active view, and the
  view is named in the page header (UX-DR26). A metric below its minimum says
  what it had and what it needed (ADR-0047 §6 as amended, #838) — never a dash
  and never a number.

  **No verdict.** A threshold crossing is the lens's own arithmetic and is
  rendered as the threshold ("above 10 %"), never as advice; nothing here
  recommends, rates or signals (ADR-0047 §7), and ADR-0023's rebalancing hints
  are not built here.
  """

  use PortfolixirWeb, :live_view

  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Risk
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Format

  # The window the page reads: the one-year figure is the one a reader compares
  # across portfolios; the API carries all three.
  @window "365d"
  @etf "etf"

  @impl true
  def mount(_params, _session, socket) do
    socket = assign(socket, :current_path, "/risk")

    portfolio =
      if Portfolios.count_securities_accounts() + Portfolios.count_cash_accounts() > 0,
        do: Portfolios.first_portfolio()

    {:ok, socket |> assign(:portfolio, portfolio) |> assign(:risk, load(portfolio, socket))}
  end

  defp load(nil, _socket), do: nil

  defp load(portfolio, socket) do
    case Risk.for_portfolio(portfolio.id, view: socket.assigns[:active_view_id]) do
      {:error, :view_not_found} -> Risk.for_portfolio(portfolio.id)
      risk -> risk
    end
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        window: @window,
        defaults: Risk.defaults(),
        view_name: view_name(assigns[:active_view])
      )

    ~H"""
    <AppShell.shell
      current_path={@current_path}
      page_title={gettext("Risk")}
      page_subtitle={gettext("Concentration and movement · view: %{view}", view: @view_name)}
    >
      <div class="workspace-page">
        <AppShell.area_tabs tabs={AppShell.wealth_tabs(:risk)} />

        <%= if is_nil(@risk) do %>
          <section class="workspace-section">
            <p class="empty-state" data-role="risk-empty">
              <%= gettext("No portfolio yet — risk is measured over holdings, and there are none.") %>
            </p>
          </section>
        <% else %>
          <section class="workspace-section kpi-band" id="risk-metrics" aria-labelledby="risk-metrics-title">
            <header class="section-head">
              <h2 id="risk-metrics-title"><%= gettext("Portfolio metrics") %></h2>
            </header>
            <div class="kpi-band__support">
              <.metric_card
                role="volatility"
                label={gettext("Volatility, annualized")}
                metric={@risk.metrics.volatility[@window]}
              >
                <:value :let={m}><%= Format.percent(m.value) %><small class="value-suffix">%</small></:value>
                <:sub :let={m}>
                  <%= ngettext(
                    "1 year · %{count} observation · min. %{required}",
                    "1 year · %{count} observations · min. %{required}",
                    m.observations,
                    required: m.required
                  ) %>
                </:sub>
              </.metric_card>

              <.metric_card
                role="max-drawdown"
                label={gettext("Max. drawdown")}
                metric={@risk.metrics.max_drawdown[@window]}
              >
                <:value :let={m}>
                  <span class={negative?(m.value) && "is-negative"}><%= signed_percent(m.value) %></span><small class="value-suffix">%</small>
                </:value>
                <:sub :let={m}>
                  <%= Format.date(m.peak_date) %> → <%= Format.date(m.trough_date) %> ·
                  <%= if m.recovery_date,
                    do: gettext("recovered %{date}", date: Format.date(m.recovery_date)),
                    else: gettext("not recovered") %>
                </:sub>
              </.metric_card>

              <.metric_card
                role="risk-adjusted-return"
                label={gettext("Risk-adjusted return")}
                metric={@risk.metrics.risk_adjusted_return[@window]}
                undefined={gettext("undefined — volatility is 0")}
              >
                <:value :let={m}><%= Format.decimal(m.value, 2) %></:value>
                <:sub :let={m}>
                  <%= gettext("risk-free rate %{rate} % · return per unit of risk",
                    rate: Format.decimal(Decimal.mult(m.risk_free_rate, 100), 2)
                  ) %>
                </:sub>
              </.metric_card>

              <.correlation_card correlations={@risk.metrics.correlations} />
            </div>
            <p class="summary-basis" data-role="risk-basis">
              <%= gettext(
                "Basis: the flow-adjusted daily return factors of the TTWROR chain, in %{currency}, annualized by √365 — a deposit is not a return. A day without a return base yields no observation, never a zero. Correlations convert to %{currency} first.",
                currency: @risk.base_currency
              ) %>
            </p>
          </section>

          <section class="workspace-section" aria-labelledby="risk-top-title">
            <header class="section-head">
              <h2 id="risk-top-title"><%= gettext("Largest single names") %></h2>
            </header>
            <%= if @risk.top_holdings == [] do %>
              <p class="empty-state"><%= gettext("No valued position in this view.") %></p>
            <% else %>
              <div class="data-table-wrapper">
                <table class="data-table" id="risk-top-holdings">
                  <thead>
                    <tr>
                      <th><%= gettext("Security") %></th>
                      <th><%= gettext("Asset class") %></th>
                      <th class="num"><%= gettext("Value") %></th>
                      <th class="num"><%= gettext("Weight") %></th>
                      <th><%= gettext("Threshold") %></th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={holding <- @risk.top_holdings} data-security-id={holding.security_id}>
                      <td><%= holding.security_name %></td>
                      <td class="muted"><%= holding.asset_class || "—" %></td>
                      <td class="num"><%= Format.money(holding.market_value) %> <%= @risk.base_currency %></td>
                      <td class="num"><%= Format.decimal(holding.weight, 1) %> %</td>
                      <td>
                        <span class={["badge", severity_class(holding.severity)]} data-severity={holding.severity}>
                          <%= threshold_label(holding, @defaults) %>
                        </span>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            <% end %>
          </section>

          <section class="workspace-section" aria-labelledby="risk-hhi-title">
            <header class="section-head">
              <h2 id="risk-hhi-title"><%= gettext("Concentration (HHI)") %></h2>
            </header>
            <article class="stat stat--compact risk-hhi" data-role="risk-hhi">
              <strong data-band={@risk.hhi.band}>
                <%= Format.decimal(@risk.hhi.value, 0) %>
                <small class="value-suffix"><%= band_label(@risk.hhi.band) %></small>
              </strong>
              <div class="risk-hhi__track" aria-hidden="true">
                <span class="risk-hhi__marker" style={"left: #{hhi_position(@risk.hhi.value)}%"}></span>
              </div>
              <small class="stat__sub">
                <%= gettext("0 · low below %{low} · %{high} and above concentrated · 10,000",
                  low: Format.decimal(@defaults.hhi.low, 0),
                  high: Format.decimal(@defaults.hhi.high, 0)
                ) %>
              </small>
            </article>
          </section>

          <section class="workspace-section" data-role="risk-caps" aria-labelledby="risk-caps-title">
            <header class="section-head">
              <h2 id="risk-caps-title"><%= gettext("Asset-class caps") %></h2>
            </header>
            <p :if={@risk.asset_class_violations == []} class="empty-state">
              <%= gettext("No cap configured — there is nothing to exceed. Caps are set per request over the API.") %>
            </p>
            <ul :if={@risk.asset_class_violations != []}>
              <li :for={v <- @risk.asset_class_violations}>
                <%= v.asset_class %>: <%= Format.decimal(v.current_weight, 1) %> % /
                <%= Format.decimal(v.cap, 1) %> %
              </li>
            </ul>

            <details class="perf-table-disclosure" id="risk-correlations">
              <summary class="disclosure-summary">
                <AppShell.icon name={:chevron_right} size={12} class="disclosure-chevron" />
                <%= gettext("Show the correlations of the largest positions") %>
              </summary>
              <p class="hint">
                <%= gettext("Pearson correlation of daily returns over one year, only on days both closed; at least %{required} shared observations per pair.",
                  required: 60
                ) %>
              </p>
              <div class="data-table-wrapper">
                <table class="data-table">
                  <thead>
                    <tr>
                      <th><%= gettext("Pair") %></th>
                      <th class="num"><%= gettext("Correlation") %></th>
                      <th class="num"><%= gettext("Observations") %></th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={pair <- @risk.metrics.correlations.pairs}>
                      <td>
                        <%= name_of(@risk, pair.security_id_a) %> · <%= name_of(@risk, pair.security_id_b) %>
                      </td>
                      <td class="num">
                        <%= if pair.value,
                          do: Format.decimal(pair.value, 2),
                          else: gettext("not computable") %>
                      </td>
                      <td class="num"><%= pair.observations %> / <%= pair.required %></td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <p :if={@risk.metrics.correlations.excluded != []} class="hint">
                <%= gettext("Left out, no stored exchange-rate path: %{names}",
                  names: Enum.map_join(@risk.metrics.correlations.excluded, ", ", &name_of(@risk, &1.security_id))
                ) %>
              </p>
            </details>
          </section>
        <% end %>
      </div>
    </AppShell.shell>
    """
  end

  attr(:role, :string, required: true)
  attr(:label, :string, required: true)
  attr(:metric, :map, required: true)
  attr(:undefined, :string, default: nil)
  slot(:value, required: true)
  slot(:sub, required: true)

  # One metric card: the value with its sub-line, or — below the metric's
  # minimum — "not computable" with what it had and what it needed.
  defp metric_card(assigns) do
    ~H"""
    <article
      class="stat stat--compact"
      data-role={"risk-metric-#{@role}"}
      data-refused={@metric.insufficient_data || nil}
    >
      <span><%= @label %></span>
      <%= cond do %>
        <% @metric.insufficient_data -> %>
          <strong class="stat-empty"><%= gettext("not computable") %></strong>
          <small class="stat__sub">
            <%= observations_of(@metric.observations, @metric.required) %>
          </small>
        <% is_nil(@metric.value) -> %>
          <strong class="stat-empty"><%= @undefined %></strong>
        <% true -> %>
          <strong><%= render_slot(@value, @metric) %></strong>
          <small class="stat__sub"><%= render_slot(@sub, @metric) %></small>
      <% end %>
    </article>
    """
  end

  attr(:correlations, :map, required: true)

  # The matrix's summary card: the highest computed pair, or — when no pair
  # reached 60 shared observations — what the best-covered pair had.
  defp correlation_card(assigns) do
    computed = Enum.filter(assigns.correlations.pairs, &(&1.value != nil))

    assigns =
      assign(assigns,
        computed: computed,
        highest: Enum.max_by(computed, & &1.value, Decimal, fn -> nil end),
        best: Enum.max_by(assigns.correlations.pairs, & &1.observations, fn -> nil end)
      )

    ~H"""
    <article class="stat stat--compact" data-role="risk-metric-correlations" data-refused={is_nil(@highest) || nil}>
      <span><%= gettext("Correlations") %></span>
      <%= if @highest do %>
        <strong><%= Format.decimal(@highest.value, 2) %></strong>
        <small class="stat__sub">
          <%= ngettext(
            "highest of %{count} pair · 1 year",
            "highest of %{count} pairs · 1 year",
            length(@computed)
          ) %>
        </small>
      <% else %>
        <strong class="stat-empty"><%= gettext("not computable") %></strong>
        <small :if={@best} class="stat__sub">
          <%= observations_of(@best.observations, @best.required) %>
        </small>
        <small :if={is_nil(@best)} class="stat__sub"><%= gettext("fewer than two names") %></small>
      <% end %>
    </article>
    """
  end

  # "n of required observations": the noun follows the requirement, which is
  # never one, so both English forms read the same; the catalogue still owns
  # the plural (issue 636).
  defp observations_of(count, required) do
    ngettext(
      "%{count} of %{required} observations",
      "%{count} of %{required} observations",
      count,
      required: required
    )
  end

  defp view_name(nil), do: gettext("Everything")
  defp view_name(view), do: view.name

  defp negative?(%Decimal{} = value), do: Decimal.negative?(value)
  defp negative?(_value), do: false

  defp signed_percent(%Decimal{} = value), do: Format.signed_decimal(Decimal.mult(value, 100), 1)

  defp severity_class("hard"), do: "badge--danger"
  defp severity_class("warn"), do: "badge-warning"
  defp severity_class(_ok), do: "badge--neutral"

  # The lens's own vocabulary, not a verdict: the threshold a weight is above,
  # or the one it is still below.
  defp threshold_label(%{asset_class: @etf, severity: "warn"}, d),
    do: gettext("above %{pct} %", pct: Format.decimal(d.etf.warn, 0))

  defp threshold_label(%{asset_class: @etf}, d),
    do: gettext("below %{pct} %", pct: Format.decimal(d.etf.warn, 0))

  defp threshold_label(%{severity: "hard"}, d),
    do: gettext("above %{pct} %", pct: Format.decimal(d.stock.hard, 0))

  defp threshold_label(%{severity: "warn"}, d),
    do: gettext("above %{pct} %", pct: Format.decimal(d.stock.warn, 0))

  defp threshold_label(_ok, d),
    do: gettext("below %{pct} %", pct: Format.decimal(d.stock.warn, 0))

  defp band_label("low"), do: gettext("low")
  defp band_label("moderate"), do: gettext("moderate")
  defp band_label("concentrated"), do: gettext("concentrated")

  # 0–10000 onto the track's 0–100 %.
  defp hhi_position(value) do
    value
    |> Decimal.div(100)
    |> Decimal.min(Decimal.new(100))
    |> Decimal.round(1)
    |> Decimal.to_string()
  end

  defp name_of(risk, security_id) do
    case Enum.find(risk.top_holdings, &(&1.security_id == security_id)) do
      nil -> "##{security_id}"
      holding -> holding.security_name
    end
  end
end
