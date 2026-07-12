defmodule PortfolixirWeb.DashboardLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.Catalog
  alias Portfolixir.Classifications
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Allocation
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.Valuation
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Format

  # A category counts as "needs attention" when its drift exceeds ±5 pp of the
  # steering basis (ADR-0022 dashboard; drift per ADR-0023: actual − target).
  @drift_threshold Decimal.new("0.05")
  @max_alerts 5

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign_counts()
      |> assign(:portfolio_cards, nil)
      |> assign(:drift_alerts, nil)
      |> assign(:data_quality, nil)
      |> start_loading()

    {:ok, socket}
  end

  # The dashboard splits on whether any transaction exists: an empty database is
  # still the onboarding wizard, but once data lands the page becomes the daily
  # attention surface (Steve UAT #337, reshaped by ADR-0022): value + change,
  # drift beyond threshold, data quality — no activity feed (the audit journal
  # keeps the forensic detail). The overview reads are expensive, so they
  # start only once the socket is connected — the first paint ships skeletons.
  defp start_loading(%{assigns: %{transactions_count: 0}} = socket), do: socket

  defp start_loading(socket) do
    if connected?(socket) do
      start_async(socket, :overview, fn ->
        portfolio_cards =
          Portfolios.list_portfolios()
          |> Enum.map(fn portfolio ->
            {portfolio, Valuation.for_portfolio(portfolio.id), ytd_ttwror(portfolio.id)}
          end)

        {portfolio_cards, drift_alerts(), data_quality_report()}
      end)
    else
      socket
    end
  end

  @impl true
  def handle_async(:overview, {:ok, {portfolio_cards, drift_alerts, data_quality}}, socket) do
    {:noreply,
     assign(socket,
       portfolio_cards: portfolio_cards,
       drift_alerts: drift_alerts,
       data_quality: data_quality
     )}
  end

  def handle_async(:overview, {:exit, _reason}, socket) do
    {:noreply, assign(socket, :error, gettext("Couldn't load the dashboard figures."))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell
      current_path="/"
      page_title={gettext("Overview")}
      page_subtitle={gettext("Local portfolio tracking")}
    >
      <div id="dashboard-workspace" class="workspace-page">
        <%= if @transactions_count == 0 do %>
          <.wizard {assigns} />
        <% else %>
          <.overview {assigns} />
        <% end %>
      </div>
    </AppShell.shell>
    """
  end

  # Empty-database onboarding: the ordered workflow plus the count cards that
  # link to where each entity is created.
  defp wizard(assigns) do
    ~H"""
    <section id="workflow-path" class="workspace-section">
      <h2><%= gettext("Workflow path") %></h2>
      <%!-- A portfolio is the hard prerequisite the Portfolio and Income
            screens demand first ("Create one portfolio first"); the path
            starts there so the dashboard does not contradict them. --%>
      <ol>
        <li><a href="/portfolios"><%= gettext("Create one portfolio") %></a></li>
        <li><a href="/portfolios"><%= gettext("Link one depot to one cash account") %></a></li>
        <li><a href="/securities"><%= gettext("Create securities") %></a></li>
        <li>
          <a href="/transactions"><%= gettext("Record manual buy and sell transactions") %></a>
        </li>
        <li><a href="/transactions"><%= gettext("Review current holdings") %></a></li>
      </ol>
    </section>

    <.count_cards {assigns} />
    """
  end

  # Populated dashboard (ADR-0022): per-portfolio value cards (each in its own
  # base currency, so no cross-currency aggregation is invented here) with the
  # YTD TTWROR as the change signal, the drift attention list, and the
  # data-quality card. Deliberately no activity feed and no entity counts —
  # the audit journal and the admin pages own those.
  defp overview(assigns) do
    ~H"""
    <div id="dashboard-overview">
      <%= if @error do %>
        <AppShell.status_toast kind={:error} message={@error} />
      <% end %>

      <section class="workspace-section grid" aria-label={gettext("Portfolio values")}>
        <%= if is_nil(@portfolio_cards) do %>
          <article class="stat section-skeleton" data-role="overview-skeleton">
            <span><%= gettext("Loading…") %></span>
          </article>
        <% else %>
          <a
            :for={{portfolio, valuation, ttwror} <- @portfolio_cards}
            id={"dashboard-portfolio-#{portfolio.id}"}
            href="/portfolio"
            class="stat stat--link"
          >
            <span><%= portfolio.name %></span>
            <strong>
              <%= Format.money(valuation.total_with_cash) %> <%= valuation.base_currency %>
            </strong>
            <small :if={ttwror} data-role="card-ttwror">
              <%= signed_percent(ttwror) %>% <%= gettext("YTD") %>
              · <%= gettext("Cash") %> <%= Format.percent(valuation.cash_quote) %>%
            </small>
            <small :if={is_nil(ttwror)}>
              <%= gettext("Cash") %> <%= Format.percent(valuation.cash_quote) %>%
            </small>
          </a>
        <% end %>
      </section>

      <%!-- ADR-0022: the dashboard answers "does anything need me?". Drift
           alerts (ADR-0023 sign: positive = overweight) link straight into
           the Allocation & targets tab; the audit journal keeps the forensic
           detail that the old activity feed restated. --%>
      <section id="dashboard-attention" class="workspace-section">
        <h2><%= gettext("Needs attention") %></h2>
        <%!-- Say WHY these items surface (UAT fix round): the threshold rule,
             derived from the same @drift_threshold the filter uses. --%>
        <p class="hint" data-role="attention-explainer">
          <%= gettext("Categories drifting more than ±%{pp} pp from their target weight.",
            pp: threshold_pp()
          ) %>
        </p>
        <%= if is_nil(@drift_alerts) do %>
          <p class="section-skeleton" data-role="attention-skeleton">
            <%= gettext("Loading…") %>
          </p>
        <% else %>
          <%= if @drift_alerts == [] do %>
            <p class="hint" data-role="all-clear">
              <%= gettext("All targets within ±5 pp — nothing needs rebalancing.") %>
            </p>
          <% else %>
            <ul class="attention-list">
              <li :for={alert <- @drift_alerts}>
                <a href="/portfolio?tab=allocation" data-role="drift-alert" class="attention-item">
                  <span class="attention-name">
                    <%= alert.name %>
                    <span class="hint">(<%= alert.portfolio_name %>)</span>
                  </span>
                  <span class={["num", drift_sign_class(alert.drift_weight)]}>
                    <%= drift_phrase(alert.drift_weight) %>
                    · <%= Format.money(alert.drift_value) %> <%= alert.base_currency %>
                  </span>
                </a>
              </li>
            </ul>
          <% end %>
        <% end %>
      </section>

      <section id="dashboard-data-quality" class="workspace-section">
        <h2><%= gettext("Data quality") %></h2>
        <%= if is_nil(@data_quality) do %>
          <p class="section-skeleton" data-role="data-quality-skeleton">
            <%= gettext("Loading…") %>
          </p>
        <% else %>
          <%!-- Counts of securities needing attention. Links land on the
                securities surface (its filters are not URL-addressable yet, so
                deep-linking to a pre-applied filter is a further step). --%>
          <div class="grid" aria-label={gettext("Data quality")}>
            <a href="/securities" class="stat stat--link" data-role="dq-quotes">
              <span><%= gettext("No quote in 7 days") %></span>
              <strong><%= @data_quality.without_quote %></strong>
              <small><%= gettext("of %{n} securities", n: @data_quality.total) %></small>
            </a>
            <a href="/securities" class="stat stat--link" data-role="dq-class">
              <span><%= gettext("No asset class") %></span>
              <strong><%= @data_quality.without_class %></strong>
            </a>
            <a href="/securities" class="stat stat--link" data-role="dq-logo">
              <span><%= gettext("No logo") %></span>
              <strong><%= @data_quality.without_logo %></strong>
            </a>
          </div>
        <% end %>
      </section>
    </div>
    """
  end

  # The YTD TTWROR as the card's "did anything change" signal; nil (hidden)
  # when the period cannot be computed yet.
  defp ytd_ttwror(portfolio_id) do
    case Performance.for_portfolio(portfolio_id, period: "ytd") do
      {:ok, %{ttwror: %Decimal{} = ttwror}} -> ttwror
      _ -> nil
    end
  end

  # Categories drifting beyond ±5 pp against the default steering tree's
  # portfolio-wide (Gesamt) plan — the same tree the Wealth page defaults to
  # (first custom classification, else asset class; review finding) — worst
  # offenders first. Only rows that carry a target count — an untargeted
  # parent's "drift" is not an alert. The cash row joins under the same rule
  # when a cash target is steered.
  defp drift_alerts do
    case Classifications.default_classification() do
      nil ->
        []

      classification ->
        Enum.flat_map(Portfolios.list_portfolios(), &alerts_for(&1, classification))
    end
    |> Enum.sort_by(&Decimal.abs(&1.drift_value), {:desc, Decimal})
    |> Enum.take(@max_alerts)
  end

  defp alerts_for(portfolio, classification) do
    case Allocation.for_portfolio(portfolio.id, classification.id) do
      {:ok, %{has_plan: true} = allocation} ->
        rows = allocation.categories ++ [Map.put(allocation.cash, :name, gettext("Cash"))]

        rows
        |> Enum.filter(&targeted_beyond_threshold?/1)
        |> Enum.map(fn row ->
          %{
            name: row.name,
            portfolio_name: portfolio.name,
            drift_weight: row.drift_weight,
            drift_value: row.drift_value,
            base_currency: allocation.base_currency
          }
        end)

      _ ->
        []
    end
  end

  defp targeted_beyond_threshold?(row) do
    Decimal.compare(row.target_weight, 0) == :gt and
      Decimal.compare(Decimal.abs(row.drift_weight), @drift_threshold) == :gt
  end

  defp drift_sign_class(drift_weight) do
    if Decimal.compare(drift_weight, 0) == :lt, do: "is-negative", else: nil
  end

  # Readable item text (UAT fix round): "7.2 pp above target" instead of a
  # bare signed number — the direction word carries the meaning.
  defp drift_phrase(drift_weight) do
    pp = Format.percent(Decimal.abs(drift_weight))

    if Decimal.compare(drift_weight, 0) == :lt do
      gettext("%{pp} pp below target", pp: pp)
    else
      gettext("%{pp} pp above target", pp: pp)
    end
  end

  # The ±5 pp threshold as a plain "5" for the explainer copy.
  defp threshold_pp do
    @drift_threshold
    |> Decimal.mult(100)
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end

  defp signed_percent(value) do
    formatted = Format.percent(value)
    if Decimal.compare(value, 0) == :gt, do: "+" <> formatted, else: formatted
  end

  # Securities needing attention (#337 data-quality card): no recent quote
  # (none at all, or older than 7 days), no persisted asset class, no logo.
  defp data_quality_report do
    today = Date.utc_today()
    rows = Catalog.list_securities_with_metrics()

    %{
      total: length(rows),
      without_quote: Enum.count(rows, &stale_quote?(&1, today)),
      without_class: Enum.count(rows, &is_nil(&1.security.asset_class)),
      without_logo: length(Catalog.list_securities(logo_status: :missing))
    }
  end

  defp stale_quote?(row, today) do
    case row.metrics.latest_price_date do
      nil -> true
      %Date{} = date -> Date.diff(today, date) > 7
      _ -> true
    end
  end

  defp count_cards(assigns) do
    ~H"""
    <%!-- Each count card looks like a card and is the most clickable thing on
          the dashboard, so it links to where that data is created instead of
          being a dead <article>. --%>
    <section class="workspace-section grid" aria-label={gettext("Portfolio counts")}>
      <a href="/securities" id="dashboard-securities-count" class="stat stat--link">
        <span><%= gettext("Securities") %></span>
        <strong><%= @securities_count %></strong>
      </a>
      <a href="/portfolios" id="dashboard-portfolios-count" class="stat stat--link">
        <span><%= gettext("Portfolios") %></span>
        <strong><%= @portfolios_count %></strong>
      </a>
      <a href="/portfolios" id="dashboard-cash-accounts-count" class="stat stat--link">
        <span><%= gettext("Cash accounts") %></span>
        <strong><%= @cash_accounts_count %></strong>
      </a>
      <a href="/portfolios" id="dashboard-securities-accounts-count" class="stat stat--link">
        <span><%= gettext("Depots") %></span>
        <strong><%= @securities_accounts_count %></strong>
      </a>
      <a href="/transactions" id="dashboard-transactions-count" class="stat stat--link">
        <span><%= gettext("Transactions") %></span>
        <strong><%= @transactions_count %></strong>
      </a>
    </section>
    """
  end

  defp assign_counts(socket) do
    assign(socket,
      securities_count: Catalog.count_securities(),
      portfolios_count: Portfolios.count_portfolios(),
      cash_accounts_count: Portfolios.count_cash_accounts(),
      securities_accounts_count: Portfolios.count_securities_accounts(),
      transactions_count: Ledger.count_transactions(),
      error: nil
    )
  end
end
