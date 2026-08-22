defmodule PortfolixirWeb.DashboardLive do
  use PortfolixirWeb, :live_view

  alias Plug.Conn.Query
  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.DataQuality
  alias Portfolixir.Classifications
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Allocation
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.PricingContext
  alias Portfolixir.Portfolios.Targets
  alias Portfolixir.Portfolios.Valuation
  alias Portfolixir.Settings
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
      |> assign(:wealth_card, nil)
      |> assign(:drift_alerts, nil)
      |> assign(:attention_basis, nil)
      |> assign(:data_quality, nil)
      |> assign_stale_ttwror()
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
        # One value card scoped to the user's default view — Everything when
        # none is set (ADR-0024: views, not portfolios, are the grouping the
        # dashboard aggregates over). The drift alerts steer against the same
        # view's SOLL plans (ADR-0020: plans are view-bound).
        view_id = Settings.default_view_id()
        base_currency = base_currency()

        # ADR-0035: the card's view-wide valuation and the per-portfolio drift
        # loop price the same holdings, so the market data both need is loaded
        # ONCE here and threaded into both. It is read-scoped data — it dies
        # with this task.
        context = PricingContext.for_all_portfolios(base_currency)

        {wealth_card(view_id, base_currency, context), attention_report(view_id, context),
         data_quality_report()}
      end)
    else
      socket
    end
  end

  # ADR-0032 §6 on the dashboard tile: while the overview computes, the last
  # known YTD figure renders immediately -- labelled with the data it contains,
  # never bare (owner requirement). Only the TTWROR half is served this way:
  # the valuation is not memoised, and a figure §6 cannot label honestly
  # recomputes instead of being guessed.
  defp assign_stale_ttwror(%{assigns: %{transactions_count: 0}} = socket) do
    assign(socket, :stale_ttwror, nil)
  end

  defp assign_stale_ttwror(socket) do
    first = Portfolios.first_portfolio()
    view_id = Settings.default_view_id()

    with %{} = portfolio <- first,
         %{daily: [_ | _]} = previous <-
           Performance.previous_view_analysis(view_id,
             base_currency: portfolio.base_currency_code
           ),
         {:ok, %{ttwror: %Decimal{} = ttwror}} <- Performance.summarise(previous, "ytd") do
      assign(socket, :stale_ttwror, %{
        ttwror: ttwror,
        basis: previous.basis,
        as_of: previous.today
      })
    else
      _none -> assign(socket, :stale_ttwror, nil)
    end
  end

  # The card's data: the deduplicated cross-portfolio view valuation in the
  # first portfolio's base currency (display continuity with the Wealth page),
  # plus the YTD TTWROR as the change signal — computed over the same
  # cross-portfolio view scope as the valuation (#577), so the total and the
  # return always cover the same accounts.
  defp wealth_card(view_id, base_currency, context) do
    view = view_id && Buckets.get_view(view_id)
    # The default view can vanish between the settings read and here (fix
    # round): degrade to the Everything scope instead of crashing the async.
    view_id = view && view.id

    %{
      # `name: nil` renders as the localized "Everything" label at render time
      # (fix round): this function runs inside `start_async`'s task process,
      # where the user's Gettext locale is NOT set — a gettext call here
      # always came out English ("EVERYTHING" after the card's CSS uppercase).
      name: view && view.name,
      valuation: everything_or_view_valuation(view_id, base_currency, context),
      ttwror: ytd_ttwror(view_id, base_currency)
    }
  end

  # The card's base currency: the first portfolio's, for display continuity
  # with the Wealth page. Read before the async block's pricing pass so both
  # cover the same currency.
  defp base_currency do
    first = Portfolios.first_portfolio()
    (first && first.base_currency_code) || "EUR"
  end

  defp everything_or_view_valuation(view_id, base_currency, context) do
    opts = [base_currency: base_currency, pricing_context: context]

    case Valuation.for_view(view_id, opts) do
      {:error, :view_not_found} -> Valuation.for_view(nil, opts)
      valuation -> valuation
    end
  end

  @impl true
  def handle_async(:overview, {:ok, {wealth_card, attention, data_quality}}, socket) do
    {:noreply,
     assign(socket,
       wealth_card: wealth_card,
       drift_alerts: attention.alerts,
       attention_basis: attention.basis,
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
      <%!-- The depot + cash account pair is the prerequisite the Wealth and
            Income screens demand first (ADR-0024: no portfolio decision
            anywhere); the path starts there so the dashboard does not
            contradict them. --%>
      <ol>
        <li><a href="/portfolios"><%= gettext("Create one cash account") %></a></li>
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

  # Populated dashboard (ADR-0022, reshaped by ADR-0024): one value card
  # scoped to the default view (Everything when none is set) with the YTD
  # TTWROR as the change signal, the drift attention list, and the
  # data-quality card. Deliberately no activity feed and no entity counts —
  # the audit journal and the admin pages own those.
  defp overview(assigns) do
    ~H"""
    <div id="dashboard-overview">
      <%!-- Load failure is a page-level condition, not an action result: one
           data note in flow, announced from a region that exists on load, no
           floating toast and no timer (#566, UX-DR17). --%>
      <div id="dashboard-load-error" role="status">
        <%= if @error do %>
          <AppShell.data_note severity={:problem}><%= @error %></AppShell.data_note>
        <% end %>
      </div>

      <section class="workspace-section grid" aria-label={gettext("Wealth value")}>
        <%= if is_nil(@wealth_card) do %>
          <%!-- Pending with a prior value (UX-DR20, owner pick P2): the last
               known value stays in place, dimmed, with a real-text staleness
               marker BEFORE the digits and the recomputing cue beneath. The
               slot carries aria-busy and sits in no live region. --%>
          <article
            :if={not is_nil(@stale_ttwror) and is_nil(@error)}
            class="stat"
            data-role="overview-stale"
          >
            <span><%= gettext("YTD") %></span>
            <strong class="value-slot-stale" aria-busy="true">
              <span class="visually-hidden"><%= gettext("Last known value —") %></span>
              <span class="stale-value"><%= signed_percent(@stale_ttwror.ttwror) %>%</span>
            </strong>
            <small data-role="stale-ttwror" class="recomputing-cue">
              <span class="spinner"></span>
              <%= ngettext(
                "Last known: %{ttwror}% YTD — one booking through %{last}, as of %{date}. Recomputing.",
                "Last known: %{ttwror}% YTD — %{count} bookings through %{last}, as of %{date}. Recomputing.",
                @stale_ttwror.basis.booking_count,
                ttwror: signed_percent(@stale_ttwror.ttwror),
                last: Format.date(@stale_ttwror.basis.last_booking_date),
                date: Format.date(@stale_ttwror.as_of)
              ) %>
            </small>
          </article>
          <article
            :if={is_nil(@stale_ttwror) and is_nil(@error)}
            class="stat"
            aria-busy="true"
            data-role="overview-skeleton"
          >
            <strong><span class="value-skeleton" aria-hidden="true"></span></strong>
            <small class="recomputing-cue">
              <span class="spinner"></span> <%= gettext("computing") %>
            </small>
          </article>
        <% else %>
          <a id="dashboard-wealth-card" href="/portfolio" class="stat stat--link">
            <span><%= @wealth_card.name || gettext("Everything") %></span>
            <strong>
              <span
                id="count-wealth-card"
                class="count-up"
                phx-hook="CountUp"
                data-count-to={Decimal.to_string(@wealth_card.valuation.total_with_cash, :normal)}
                data-decimals="2"
              ><span data-count-digits><%= Format.money(@wealth_card.valuation.total_with_cash) %></span></span>
              <%= @wealth_card.valuation.base_currency %>
            </strong>
            <small :if={@wealth_card.ttwror} data-role="card-ttwror">
              <span class={sign_class(@wealth_card.ttwror)}><%= signed_percent(@wealth_card.ttwror) %>%</span>
              <%= gettext("YTD") %>
              · <%= gettext("Cash") %> <%= Format.percent(@wealth_card.valuation.cash_quote) %>%
            </small>
            <small :if={is_nil(@wealth_card.ttwror)}>
              <%= gettext("Cash") %> <%= Format.percent(@wealth_card.valuation.cash_quote) %>%
            </small>
          </a>
        <% end %>
      </section>

      <%!-- ADR-0022: the dashboard answers "does anything need me?". Drift
           alerts (ADR-0023 sign: positive = overweight) link straight into
           the Allocation & targets tab; the audit journal keeps the forensic
           detail that the old activity feed restated. --%>
      <%!-- #718 (UX-DR21 — a surface names what it aggregates): the card is
           named for its content, categories off their target weight, not for
           an urgency or the reaction it hopes to cause. --%>
      <section id="dashboard-attention" class="workspace-section">
        <h2><%= gettext("Off target") %></h2>
        <%!-- Say WHY these items surface (UAT fix round): the threshold rule,
             derived from the same @drift_threshold the filter uses — and
             WHAT they are computed against (#673, {components.needs-
             attention-card}.basis-line): the view, the plan and the tree.
             Names come raw from the async read; gettext runs here, at
             render time, where the user's locale is set. --%>
        <p class="hint" data-role="attention-explainer">
          <span :if={@attention_basis} data-role="attention-basis"><%= basis_phrase(
              @attention_basis
            ) %> · </span><%= gettext(
            "Categories drifting more than ±%{pp} pp from their target weight.",
            pp: threshold_pp()
          ) %>
        </p>
        <%= if is_nil(@drift_alerts) do %>
          <%!-- A whole absent section keeps its block skeleton (UX-DR20);
               the cue is the substance, the shimmer stays gated. --%>
          <%!-- #723: the drift report is a sub-second figure — the block
               skeleton (UX-DR20) carries the wait without the cue, which at
               that latency only registers as flicker. --%>
          <p class="section-skeleton" aria-busy="true" data-role="attention-skeleton"></p>
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

      <%!-- Data quality is ONE line (UX-DR2, decided 2026-07-12, adopted
           2026-08-05): rendered only when a count is non-zero, no green
           all-clear badge, each count linking to the securities list
           PRE-FILTERED to the offending set (#561, unblocked by #651).
           While the overview computes, the section is simply absent — a
           finding surface makes no claim before a finding exists. --%>
      <section
        :if={@data_quality && dq_findings(@data_quality) != []}
        id="dashboard-data-quality"
        class="workspace-section"
      >
        <h2><%= gettext("Data quality") %></h2>
        <%!-- One data-note at the highest severity present (UX-DR17); the
             remedy links live inside the note. role="status" sits on the
             region so the async arrival announces once. --%>
        <div role="status">
          <AppShell.data_note
            severity={dq_severity(@data_quality)}
            id="dashboard-dq-line"
            data-role="data-quality-line"
          >
            <%= for {finding, index} <- Enum.with_index(dq_findings(@data_quality)) do %>
              <%= if index > 0 do %>
                <span aria-hidden="true"> · </span>
              <% end %>
              <a href={finding.href} data-role={finding.role}><%= finding.text %></a>
            <% end %>
          </AppShell.data_note>
        </div>
      </section>
    </div>
    """
  end

  # The YTD TTWROR as the card's "did anything change" signal, scoped to the
  # same cross-portfolio view as the valuation (#577, ADR-0019 at the view
  # boundary); nil (hidden) when the period cannot be computed yet.
  defp ytd_ttwror(view_id, base_currency) do
    case Performance.for_view(view_id, period: "ytd", base_currency: base_currency) do
      {:ok, %{ttwror: %Decimal{} = ttwror}} -> ttwror
      _ -> nil
    end
  end

  # Categories drifting beyond ±5 pp against the default steering tree's plan
  # for the default view (ADR-0020: SOLL plans are view-bound; `nil` view =
  # the Gesamt plan) — the same tree the Wealth page defaults to (first custom
  # classification, else asset class; review finding) — worst offenders first.
  # Only rows that carry a target count — an untargeted parent's "drift" is
  # not an alert. The cash row joins under the same rule when a cash target is
  # steered. The allocation read is still portfolio-bound, so portfolios are
  # iterated as the mechanism; the view is the user-facing scope.
  defp attention_report(view_id, context) do
    case Classifications.default_classification() do
      nil ->
        %{alerts: [], basis: nil}

      classification ->
        alerts =
          Portfolios.list_portfolios()
          |> Enum.flat_map(&alerts_for(&1, classification, view_id, context))
          |> Enum.sort_by(&Decimal.abs(&1.drift_value), {:desc, Decimal})
          |> Enum.take(@max_alerts)

        %{alerts: alerts, basis: attention_basis(classification, view_id)}
    end
  end

  # The names the basis line states (#673): the view, the steering tree, and
  # the active plan(s) behind the drift figures. Portfolios are the iteration
  # mechanism (ADR-0024), so several portfolios may each carry an active plan
  # for the same (view, tree) — the line then says so instead of silently
  # naming one. Raw names only; localisation happens at render time.
  defp attention_basis(classification, view_id) do
    view = view_id && Buckets.get_view(view_id)

    plan_names =
      Portfolios.list_portfolios()
      |> Enum.flat_map(fn portfolio ->
        Targets.list_plans(portfolio.id,
          classification_id: classification.id,
          view: view && view.id
        )
      end)
      |> Enum.filter(&(&1.status == "active"))
      |> Enum.map(& &1.name)
      |> Enum.uniq()

    %{view_name: view && view.name, tree: classification.name, plan_names: plan_names}
  end

  defp basis_phrase(%{plan_names: []} = basis) do
    gettext("View %{view} — no active plan on %{tree}",
      view: basis_view(basis),
      tree: basis.tree
    )
  end

  defp basis_phrase(%{plan_names: [name]} = basis) do
    gettext("View %{view} · plan “%{plan}” on %{tree}",
      view: basis_view(basis),
      plan: name,
      tree: basis.tree
    )
  end

  defp basis_phrase(basis) do
    gettext("View %{view} · several active plans on %{tree}",
      view: basis_view(basis),
      tree: basis.tree
    )
  end

  defp basis_view(%{view_name: nil}), do: gettext("Everything")
  defp basis_view(%{view_name: name}), do: name

  defp alerts_for(portfolio, classification, view_id, context) do
    opts = [view: view_id, pricing_context: context]

    case Allocation.for_portfolio(portfolio.id, classification.id, opts) do
      {:ok, %{has_plan: true} = allocation} ->
        rows = allocation.categories ++ [Map.put(allocation.cash, :name, gettext("Cash"))]

        rows
        |> Enum.filter(&targeted_beyond_threshold?/1)
        |> Enum.map(fn row ->
          # ADR-0024: the portfolio is the iteration mechanism only — its name
          # is not surfaced as a grouping label.
          %{
            name: row.name,
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

  # Gain/loss colour by sign, never the accent (UX-DR7, issue 637).
  defp sign_class(value) do
    case Decimal.compare(value, 0) do
      :gt -> "is-positive"
      :lt -> "is-negative"
      :eq -> "is-flat"
    end
  end

  # The data-quality line's findings, each with the pre-filtered securities
  # URL that fixes it (#561/#651). Only non-zero counts appear; when the list
  # is empty the whole section is absent — no all-clear badge (UX-DR2).
  defp dq_findings(dq) do
    [
      dq.without_quote > 0 &&
        %{
          role: "dq-quotes",
          href: "/securities?dq=stale_quote",
          text:
            ngettext(
              "one security without a quote in 7 days",
              "%{count} securities without a quote in 7 days",
              dq.without_quote
            )
        },
      dq.without_class > 0 &&
        %{
          role: "dq-class",
          href: "/securities?" <> Query.encode(%{"filter" => ["asset_class:is_nil"]}),
          text:
            ngettext(
              "one without an asset class",
              "%{count} without an asset class",
              dq.without_class
            )
        },
      dq.without_logo > 0 &&
        %{
          role: "dq-logo",
          href: "/securities?dq=missing_logo",
          text: ngettext("one without a logo", "%{count} without a logo", dq.without_logo)
        }
    ]
    |> Enum.filter(& &1)
  end

  # Highest severity present (UX-DR17): a stale quote skews valuations, so it
  # is attention-level; a missing class or logo is a note-level catalog gap.
  defp dq_severity(%{without_quote: n}) when n > 0, do: :attention
  defp dq_severity(_dq), do: :note

  # Securities needing attention (#337 data-quality card): no recent quote
  # (none at all, or older than 7 days), no persisted asset class, no logo.
  defp data_quality_report do
    # The counts come from the shared predicates (#705), so each finding's
    # number is produced by the same rule as the list its link opens. The
    # asset-class finding stays an ordinary column filter: `asset_class` is a
    # stored column, so it needs no predicate of its own -- and it is keyed on
    # the STORED value per #700, which is what makes the count addressable.
    %{
      total: length(Catalog.list_securities()),
      without_quote: DataQuality.count("stale_quote"),
      without_class: Enum.count(Catalog.list_securities(), &is_nil(&1.asset_class)),
      without_logo: DataQuality.count("missing_logo")
    }
  end

  defp count_cards(assigns) do
    ~H"""
    <%!-- Each count card looks like a card and is the most clickable thing on
          the dashboard, so it links to where that data is created instead of
          being a dead <article>. --%>
    <section class="workspace-section grid" aria-label={gettext("Setup counts")}>
      <a href="/securities" id="dashboard-securities-count" class="stat stat--link">
        <span><%= gettext("Securities") %></span>
        <strong><%= @securities_count %></strong>
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
      cash_accounts_count: Portfolios.count_cash_accounts(),
      securities_accounts_count: Portfolios.count_securities_accounts(),
      transactions_count: Ledger.count_transactions(),
      error: nil
    )
  end
end
