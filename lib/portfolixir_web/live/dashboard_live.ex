defmodule PortfolixirWeb.DashboardLive do
  use PortfolixirWeb, :live_view

  alias Plug.Conn.Query
  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.DataQuality
  alias Portfolixir.Classifications
  alias Portfolixir.Knowledge.Events
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Allocation
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.PricingContext
  alias Portfolixir.Portfolios.RealizedGains
  alias Portfolixir.Portfolios.Targets
  alias Portfolixir.Portfolios.Valuation
  alias Portfolixir.Settings
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.ClassificationName
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.SecurityEventLabel
  alias PortfolixirWeb.TransactionKindLabel
  alias PortfolixirWeb.ValuationNotes

  # A category counts as "needs attention" when its drift exceeds ±5 pp of the
  # steering basis (ADR-0022 dashboard; drift per ADR-0023: actual − target).
  @drift_threshold Decimal.new("0.05")
  @max_alerts 5
  # #984 (pick G1-A): the Overview's closed-trades card lists the newest five.
  @closed_trades_shown 5

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign_counts()
      |> assign(:wealth_card, nil)
      |> assign(:last_booking, nil)
      |> assign(:drift_alerts, nil)
      |> assign(:attention_basis, nil)
      |> assign(:data_quality, nil)
      # #828 (design pick D3-A): the due dates, read synchronously — the
      # calendar is a small table and the card must not depend on the
      # async overview read that carries the drift alerts.
      |> assign(:upcoming_events, upcoming_events())
      # #984 (pick G1-A): the closed-trades card appears only where a sell
      # is booked — a cheap fact read now, so a ledger without one never
      # paints a placeholder for a card that cannot appear.
      |> assign_has_sells()
      |> assign(:closed_trades, nil)
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
         data_quality_report(), last_booking()}
      end)
      |> start_closed_trades()
    else
      socket
    end
  end

  defp assign_has_sells(%{assigns: %{transactions_count: 0}} = socket),
    do: assign(socket, :has_sells, false)

  defp assign_has_sells(socket), do: assign(socket, :has_sells, Ledger.any_sell?())

  # #984 (pick G1-A): the closed trades are their own read, beside the
  # overview's — the realized report covers every depot whatever the view,
  # so it shares nothing with the view-scoped pricing pass and must not wait
  # for it. Data only: the task has no user locale, the card's words are
  # rendered at render time. #1030: the card computes only what it shows —
  # the report's newest five, its exclusions and its base currency — not
  # the whole report it used to cut down.
  defp start_closed_trades(%{assigns: %{has_sells: true}} = socket) do
    start_async(socket, :closed_trades, fn ->
      RealizedGains.newest_trades(@closed_trades_shown)
    end)
  end

  defp start_closed_trades(socket), do: socket

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

    # One daily walk serves both periods (#798): the card's YTD change signal
    # and the strip's 1Y return chain the same series.
    analysis = view_analysis(view_id, base_currency)

    %{
      # `name: nil` renders as the localized "Everything" label at render time
      # (fix round): this function runs inside `start_async`'s task process,
      # where the user's Gettext locale is NOT set — a gettext call here
      # always came out English ("EVERYTHING" after the card's CSS uppercase).
      name: view && view.name,
      valuation: everything_or_view_valuation(view_id, base_currency, context),
      ttwror: ttwror_of(summarise(analysis, "ytd")),
      one_year: summarise(analysis, "1y")
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
  def handle_async(:overview, {:ok, {wealth_card, attention, data_quality, last_booking}}, socket) do
    {:noreply,
     assign(socket,
       wealth_card: wealth_card,
       last_booking: last_booking,
       drift_alerts: attention.alerts,
       attention_basis: attention.basis,
       data_quality: data_quality
     )}
  end

  def handle_async(:overview, {:exit, _reason}, socket) do
    {:noreply, assign(socket, :error, gettext("Couldn't load the dashboard figures."))}
  end

  def handle_async(:closed_trades, {:ok, card}, socket),
    do: {:noreply, assign(socket, :closed_trades, card)}

  def handle_async(:closed_trades, {:exit, _reason}, socket),
    do: {:noreply, assign(socket, :closed_trades, :error)}

  # The overview handles no events of its own; one pushed to it changes
  # nothing (E25 S4, F17).
  @impl true
  def handle_event(_event, _params, socket), do: {:noreply, socket}

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

      <%!-- #1081 (D-3, board 01 pick J1 A): the section holds one card in
           every state, and under it the note naming what the total leaves
           out. It is not a `.grid`: a second grid item would become a second
           column, and a spanning one stops auto-fit from collapsing the
           empty tracks, so the card would shrink; `.workspace-section` is
           already a one-column grid with the gap. --%>
      <section id="dashboard-wealth" class="workspace-section" aria-label={gettext("Wealth value")}>
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
            <span><%= gettext("year to date") %></span>
            <strong class="value-slot-stale" aria-busy="true">
              <span class="visually-hidden"><%= gettext("Last known value —") %></span>
              <span class="stale-value"><%= signed_percent(@stale_ttwror.ttwror) %>%</span>
            </strong>
            <small data-role="stale-ttwror" class="recomputing-cue">
              <span class="spinner"></span>
              <%= ngettext(
                "Last known: %{ttwror}% year to date — one booking through %{last}, as of %{date}. Recomputing.",
                "Last known: %{ttwror}% year to date — %{count} bookings through %{last}, as of %{date}. Recomputing.",
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
              ><span data-count-digits><%= Format.money(@wealth_card.valuation.total_with_cash) %></span></span><small class="value-suffix"><%= @wealth_card.valuation.base_currency %></small>
            </strong>
            <%!-- The sub-line keeps the YTD change; the cash quote moved to
                 the strip's own cell (UX-DR2 as amended 2026-09-14). The
                 card is a link and cannot hold an ⓘ, so it says the period
                 in words (#1090, board 08 ③) under a msgid of its own: "YTD"
                 stays the period token of the range controls. --%>
            <small :if={@wealth_card.ttwror} data-role="card-ttwror">
              <span class={sign_class(@wealth_card.ttwror)}><%= signed_percent(@wealth_card.ttwror) %>%</span>
              <%= gettext("year to date") %>
            </small>
            <small :if={is_nil(@wealth_card.ttwror)} data-role="card-ttwror">
              <%= gettext("year to date") %> —
            </small>
          </a>
        <% end %>
        <%!-- UX-DR25 beside the figure (#1081): one status region that exists
             before the read lands (UX-DR17), so the note arriving with the
             card is announced once; empty — and taking no room — when the
             total leaves nothing out (UX-DR2: no all-clear). No whitespace
             inside it, so `:empty` holds. --%>
        <div id="dashboard-wealth-card-status" role="status" class="wealth-card-status"><.wealth_card_excluded
            :if={@wealth_card}
            valuation={@wealth_card.valuation}
          /></div>
      </section>

      <%!-- #798 (UX-DR2 as amended 2026-09-14): the four questions of the
           morning on one strip — return, cash quote, last booking, quote
           freshness — each cell stating its basis and linking to the surface
           that owns the figure. The Overview's own block, not the Wealth band
           repeated; absent in the empty state (this component renders only
           once a transaction exists). --%>
      <section id="dashboard-kpi-strip" class="workspace-section kpi-strip" aria-label={gettext("Key figures")}>
        <div class="kpi-strip__cells">
          <a href="/portfolio" class="kpi-strip__cell" data-role="kpi-ttwror">
            <span class="kpi-strip__label"><%= gettext("TTWROR") %> <%= gettext("1Y") %></span>
            <%= if @wealth_card do %>
              <strong
                :if={one_year_ttwror(@wealth_card)}
                class={sign_class(one_year_ttwror(@wealth_card))}
              >
                <%= signed_percent(one_year_ttwror(@wealth_card)) %>%
              </strong>
              <strong :if={is_nil(one_year_ttwror(@wealth_card))} class="kpi-strip__na">—</strong>
              <small class="kpi-strip__sub"><%= money_weighted_line(@wealth_card.one_year) %></small>
            <% else %>
              <.strip_pending />
            <% end %>
          </a>
          <a href="/portfolio" class="kpi-strip__cell" data-role="kpi-cash-quote">
            <span class="kpi-strip__label"><%= gettext("Cash quote") %></span>
            <%= if @wealth_card do %>
              <strong><%= Format.percent(@wealth_card.valuation.cash_quote) %>%</strong>
              <small class="kpi-strip__sub">
                <%= Format.money(@wealth_card.valuation.total_cash) %> <%= @wealth_card.valuation.base_currency %> <%= gettext(
                  "cash"
                ) %>
              </small>
            <% else %>
              <.strip_pending />
            <% end %>
          </a>
          <%!-- The ledger's newest booking, kind label localized here at
               render time (the async task has no user locale). --%>
          <a href="/transactions" class="kpi-strip__cell" data-role="kpi-last-booking">
            <span class="kpi-strip__label"><%= gettext("Last booking") %></span>
            <%= if @wealth_card do %>
              <strong :if={@last_booking}><%= Format.date(@last_booking.date) %></strong>
              <strong :if={is_nil(@last_booking)} class="kpi-strip__na">—</strong>
              <small :if={@last_booking} class="kpi-strip__sub">
                <%= TransactionKindLabel.label(@last_booking.type) %><%= if @last_booking.subject,
                  do: " · #{@last_booking.subject}" %>
              </small>
            <% else %>
              <.strip_pending />
            <% end %>
          </a>
          <%!-- Freshness: the newest stored quote across the held positions is
               the fact; the stale count is the finding, shown only when it
               exists (no all-clear badge) and linking where the data-quality
               line links. --%>
          <a href="/securities?dq=stale_quote" class="kpi-strip__cell" data-role="kpi-freshness">
            <span class="kpi-strip__label"><%= gettext("Quotes") %></span>
            <%= if @wealth_card do %>
              <strong :if={@wealth_card.valuation.newest_quote_date}>
                <%= Format.date(@wealth_card.valuation.newest_quote_date) %>
              </strong>
              <strong :if={is_nil(@wealth_card.valuation.newest_quote_date)} class="kpi-strip__na">
                —
              </strong>
              <%!-- The count is the one the link resolves to: the catalog-wide
                   stale_quote predicate, the same rule that produces the
                   data-quality finding below and the list the href opens
                   (#705). The valuation's own view-scoped count answers a
                   different question and would put two numbers for one
                   finding on one page. Since #1081 (pick J1.2 A, UX-DR26)
                   it says that scope, "n stale in the catalog", beside a
                   basis line about held positions; at 390 px it wraps, the
                   glyph on its first line. --%>
              <small
                :if={@data_quality && @data_quality.without_quote > 0}
                class="kpi-strip__sub kpi-strip__sub--attention"
              >
                <AppShell.icon name={:alert_triangle} size={12} />
                <span><%= ngettext(
                  "%{count} stale in the catalog",
                  "%{count} stale in the catalog",
                  @data_quality.without_quote
                ) %></span>
              </small>
            <% else %>
              <.strip_pending />
            <% end %>
          </a>
        </div>
        <%!-- The strip's three domain metrics carry their definition here
             rather than per cell: a cell is a link, and a <details> inside a
             link is invalid interactive nesting. One ⓘ on the basis line, the
             same sentences the Wealth band uses (EXPERIENCE.md → Voice and
             Tone: one explanation, in one place, in one form). --%>
        <div :if={@wealth_card} class="summary-basis kpi-strip__basis" data-role="kpi-strip-basis">
          <%= gettext("View %{view} · return over %{period} to %{date} · in %{currency} · quotes: the newest across held positions",
            view: @wealth_card.name || gettext("Everything"),
            period: strip_period(@wealth_card),
            date: Format.date(strip_as_of(@wealth_card)),
            currency: @wealth_card.valuation.base_currency
          ) %>
          <details class="metric-tooltip metric-tooltip--inline" data-role="kpi-strip-info">
            <summary aria-label={gettext("About these key figures")}>ⓘ</summary>
            <p role="tooltip">
              <%= gettext("TTWROR — time-weighted return for the selected period (not annualized). Deposits and withdrawals are neutralised so only investment performance counts.") %>
              <%= gettext("IRR — money-weighted return, annualized. Discounts the timing and size of cashflows over the period. Windows shorter than a year show the period MWR — the same figure, not annualized.") %>
              <%= gettext("Cash quote: deployable cash ÷ (securities value + deployable cash). Reserve and credit-line accounts are excluded.") %>
            </p>
          </details>
        </div>
      </section>

      <.closed_trades_card :if={@has_sells} card={@closed_trades} />

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
                  <%!-- #798: a decorative drift bar around zero — aria-hidden;
                       sign, colour and the direction word stay the accessible
                       channels (UX-DR7). Scaled to the worst drift listed. --%>
                  <span class="drift-bar" aria-hidden="true">
                    <span
                      class={["drift-bar__fill", drift_bar_side(alert.drift_weight)]}
                      style={"width: #{drift_bar_width(alert.drift_weight, @drift_alerts)}%"}
                    >
                    </span>
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

      <%!-- #828 (ADR-0048, design pick D3-A): what is due, in the attention
           column that already answers "does anything need me?". THE DEFAULT
           SCOPE IS THE WHOLE CATALOG, not the holdings — a row for a security
           with no position is marked and kept, never filtered away, because a
           calendar derived from the position list is exactly how a purchase
           candidate's reporting date became invisible (§2). No new route and
           no sidebar entry: ADR-0024 keeps entities as attributes. --%>
      <section
        :if={@upcoming_events != []}
        id="dashboard-upcoming"
        class="workspace-section"
      >
        <h2><%= gettext("Due") %></h2>
        <p class="hint" data-role="upcoming-basis">
          <%= gettext(
            "Dated facts about any security in the catalog — held or not — falling in the next %{days} days. A date given as a range or a month counts as due when any day it could fall on is inside the horizon.",
            days: upcoming_days()
          ) %>
        </p>
        <ul class="attention-list">
          <li :for={row <- @upcoming_events}>
            <a
              href={"/securities/#{row.event.security_id}?tab=events"}
              data-role="upcoming-event"
              class="attention-item"
            >
              <%!-- One name and one right-aligned figure, the anatomy
                   `.attention-item` is built for: a second `.attention-name`
                   span floated the kind into the middle of the row and made
                   hover underline two things as if the row were two links.
                   The kind and the timing qualifier are the name's sub-line;
                   the date is the figure, which keeps the nowrap slot short
                   enough for 390 px. --%>
              <span class="attention-name">
                <%= row.security_name %>
                <span :if={not row.held} class="badge badge--neutral" data-role="upcoming-unheld">
                  <%= gettext("no position") %>
                </span>
                <small class="attention-item__sub">
                  <%= SecurityEventLabel.kind(row.event.kind) %>
                  · <%= SecurityEventLabel.timing(row.event.timing) %>
                </small>
              </span>
              <span class="num">
                <%= Format.date(row.event.date) %>
              </span>
            </a>
          </li>
        </ul>
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

  attr(:card, :any, required: true)

  # #984 (board G1, pick A; UX-DR2 amended 2026-10-01 with a fifth block):
  # "was the trade worth it", answered where the owner lands. The newest
  # five closed trades — results, not activity: ADR-0022 §7 dropped the raw
  # recent-activity feed, and a sale is listed here for what it realised,
  # never as a booking. The card covers every depot whatever the view, as
  # the realized report does, and its basis line says so. Built from
  # existing parts: the `.attention-list` of "Off target" and "Due", the
  # `.kpi-summary__link` of "All key figures → Holdings".
  #
  # States: pending — the block skeleton (UX-DR20), no cue, the list is a
  # sub-second read; populated; a sale the rates cannot convert named in an
  # attention note (UX-DR25), pointing to the backfill on the facet; absent
  # with no closed trade and no exclusion, like "Due" without a date. A sell
  # with no matched buy is no trade, so it is not missing from the five; the
  # facet names it where the totals are read.
  defp closed_trades_card(%{card: %{trades: [], excluded: %{count: 0}}} = assigns), do: ~H""

  defp closed_trades_card(assigns) do
    ~H"""
    <section id="dashboard-trades" class="workspace-section">
      <div class="section-head">
        <h2><%= gettext("Closed trades") %></h2>
        <a class="kpi-summary__link" href="/cashflow?tab=realized"><%= gettext("All trades →") %></a>
      </div>
      <%= cond do %>
        <% is_nil(@card) -> %>
          <p class="section-skeleton" aria-busy="true" data-role="trades-card-skeleton"></p>
        <% @card == :error -> %>
          <AppShell.data_note severity={:problem} data-role="trades-card-error">
            <%= gettext("Couldn't load the closed trades.") %>
          </AppShell.data_note>
        <% true -> %>
          <AppShell.data_note
            :if={@card.excluded.count > 0}
            severity={:attention}
            data-role="trades-card-excluded"
          >
            <%= ngettext(
              "%{count} sale with no stored rate on its close date is left out of the trades: %{securities}. The rate backfill is under “All trades”.",
              "%{count} sales with no stored rate on their close dates are left out of the trades: %{securities}. The rate backfill is under “All trades”.",
              @card.excluded.count,
              securities: Enum.join(@card.excluded.securities, ", ")
            ) %>
          </AppShell.data_note>
          <p :if={@card.trades != []} class="summary-basis" data-role="trades-card-basis">
            <%!-- Counts what the card shows: five at most (closing act γ n3). --%>
            <%= ngettext(
              "The most recently closed · result in %{currency} · FIFO across every depot, whatever the view · p. a. only from 365 days of holding",
              "The %{count} most recently closed · result in %{currency} · FIFO across every depot, whatever the view · p. a. only from 365 days of holding",
              length(@card.trades),
              currency: @card.base_currency
            ) %>
          </p>
          <ul :if={@card.trades != []} class="attention-list">
            <li :for={trade <- @card.trades}>
              <a
                href={"/securities/#{trade.security_id}?tab=trades"}
                class="attention-item"
                data-role="closed-trade"
              >
                <span class="attention-name">
                  <%= trade.security_name %>
                  <small class="attention-item__sub">
                    <%= gettext("sold %{date}", date: Format.date(trade.close_date)) %> · <%= ngettext(
                      "%{count} day",
                      "%{count} days",
                      trade.holding_period_days
                    ) %>
                  </small>
                </span>
                <span class="num">
                  <span class={sign_class(trade.realized_base)}><%= Format.signed_decimal(
                    trade.realized_base,
                    2
                  ) %></span><small class="value-suffix"><%= @card.base_currency %></small>
                  <small class="attention-item__sub">
                    <%= if trade.annualized_return do %>
                      <span class={sign_class(trade.annualized_return)}><%= signed_percent(
                        trade.annualized_return
                      ) %>%</span>
                      <%= gettext("p. a.") %>
                    <% else %>
                      <%= if trade.realized_pnl_pct do %>
                        <span class={sign_class(trade.realized_pnl_pct)}><%= signed_percent(
                          trade.realized_pnl_pct
                        ) %>%</span>
                        <%= gettext("total") %>
                      <% else %>
                        <%!-- #1142 (board 02, found while drawing 9): a
                             trade on no cost has no return; the card says
                             so in words, as the facet's phone row does,
                             where "0.0% total" read as a flat trade. --%>
                        <span data-role="return-absent"><span aria-hidden="true">—</span> <%= gettext(
                            "no cost basis"
                          ) %></span>
                      <% end %>
                    <% end %>
                  </small>
                </span>
              </a>
            </li>
          </ul>
      <% end %>
    </section>
    """
  end

  attr(:valuation, :map, required: true)

  # #1081 (D-3, board 01 pick J1 A; UX-DR25 clauses 1–3): what the card's
  # total leaves out, named beside it — the cash accounts with no rate path
  # to the base currency with their native balances, the held positions with
  # no price, and those with a price but no rate path with their native
  # price. One attention note, the groups in that order, each shortened by
  # Wealth's rule (six names, then "+N"); no note when nothing is left out.
  # It reads only the valuation the card already reads, and its names come
  # from the helpers Wealth's notes use. No control: the rate sync and the
  # price are fixed on Wealth, so the note links there. The link is the
  # card's own `/portfolio` — the session's view, no `?view=`, nothing
  # stored. Localized here, at render time (the async task has no locale).
  defp wealth_card_excluded(assigns) do
    assigns = assign(assigns, :groups, ValuationNotes.excluded_groups(assigns.valuation))

    ~H"""
    <AppShell.data_note :if={@groups != []} severity={:attention} data-role="wealth-card-excluded">
      <%= excluded_sentence(Enum.join(@groups, " · ")) %>
      <a href="/portfolio" data-role="wealth-card-excluded-link"><%= gettext("Details in Wealth →") %></a>
    </AppShell.data_note>
    """
  end

  # A last name that ends in a full stop ("Harborline Freight Inc.") closes
  # the sentence itself; a second one would read "Inc..".
  defp excluded_sentence(groups) do
    if String.ends_with?(groups, ".") do
      gettext("Not in the total: %{groups}", groups: groups)
    else
      gettext("Not in the total: %{groups}.", groups: groups)
    end
  end

  # The pending footprint of a strip cell (UX-DR20): the value-sized
  # placeholder, aria-busy, no cue — the strip is a sub-second figure (#723).
  defp strip_pending(assigns) do
    ~H"""
    <strong class="value-slot-pending" aria-busy="true">
      <span class="value-skeleton" aria-hidden="true"></span>
    </strong>
    """
  end

  # The cross-portfolio view walk the card and the strip chain their periods
  # from (#577, ADR-0019 at the view boundary); nil when it cannot run yet.
  defp view_analysis(view_id, base_currency) do
    case Performance.view_analysis(view_id, base_currency: base_currency) do
      %{} = analysis -> analysis
      _error -> nil
    end
  end

  defp summarise(nil, _period), do: nil

  defp summarise(analysis, period) do
    case Performance.summarise(analysis, period) do
      {:ok, summary} -> summary
      _error -> nil
    end
  end

  # The YTD TTWROR as the card's "did anything change" signal; nil (hidden)
  # when the period cannot be computed yet.
  defp ttwror_of(%{ttwror: %Decimal{} = ttwror}), do: ttwror
  defp ttwror_of(_summary), do: nil

  defp one_year_ttwror(%{one_year: summary}), do: ttwror_of(summary)

  # The strip's money-weighted sub-line follows the Wealth band's rule
  # (ADR-0034 §2): the annualized IRR for a full year of history, the period
  # MWR for a shorter window — labelled as what it is.
  defp money_weighted_line(nil), do: gettext("IRR") <> " —"

  defp money_weighted_line(summary) do
    {label, value} =
      if short_window?(summary),
        do: {gettext("MWR"), summary.mwr},
        else: {gettext("IRR"), summary.irr}

    case value do
      %Decimal{} -> "#{label} #{signed_percent(value)}%"
      _none -> label <> " —"
    end
  end

  defp short_window?(%{start_date: %Date{} = start_date, end_date: %Date{} = end_date}),
    do: Date.diff(end_date, start_date) + 1 < 365

  defp short_window?(_summary), do: false

  # The strip's as-of date: the walk's end, else the read date.
  # The window the one-year figure actually walked. A ledger younger than a
  # year gives a shorter window, and the basis line names its start instead of
  # asserting a year the figure does not cover — the sentence then reads
  # "return over <start> to <as-of>".
  defp strip_period(%{one_year: %{start_date: %Date{} = start, end_date: %Date{} = stop}}) do
    if Date.diff(stop, start) + 1 < 365,
      do: Format.date(start),
      else: gettext("1Y")
  end

  defp strip_period(_card), do: gettext("1Y")

  defp strip_as_of(%{one_year: %{end_date: %Date{} = end_date}}), do: end_date
  defp strip_as_of(_card), do: Portfolixir.Clock.today()

  # The ledger's newest booking (#798): newest date, newest id — the order
  # the history opens on. Raw record; the kind label is localized at render
  # time, because this runs in the async task, which has no user locale.
  defp last_booking do
    case Ledger.list_transactions(limit: 1) do
      [transaction] ->
        %{
          date: transaction.date,
          type: transaction.type,
          subject: booking_subject(transaction)
        }

      [] ->
        nil
    end
  end

  defp booking_subject(%{security: %{name: name}}) when is_binary(name), do: name
  defp booking_subject(%{cash_account: %{name: name}}) when is_binary(name), do: name
  defp booking_subject(%{securities_account: %{name: name}}) when is_binary(name), do: name
  defp booking_subject(_transaction), do: nil

  # The drift bar's side and length (#798): over target grows right of the
  # zero line, under target grows left; the worst drift listed fills 45 % of
  # the track, so the rows read against each other.
  defp drift_bar_side(drift_weight) do
    if Decimal.compare(drift_weight, 0) == :lt, do: "is-under", else: "is-over"
  end

  defp drift_bar_width(drift_weight, alerts) do
    worst =
      alerts
      |> Enum.map(&Decimal.abs(&1.drift_weight))
      |> Enum.max(Decimal, fn -> Decimal.new(0) end)

    if Decimal.compare(worst, 0) == :gt do
      drift_weight
      |> Decimal.abs()
      |> Decimal.div(worst)
      |> Decimal.mult(45)
      |> Decimal.round(1)
      |> Decimal.to_string(:normal)
    else
      "0"
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

    %{
      view_name: view && view.name,
      tree: %{key: classification.key, name: classification.name},
      plan_names: plan_names
    }
  end

  defp basis_phrase(%{plan_names: []} = basis) do
    gettext("View %{view} — no active plan on %{tree}",
      view: basis_view(basis),
      tree: ClassificationName.display(basis.tree)
    )
  end

  defp basis_phrase(%{plan_names: [name]} = basis) do
    gettext("View %{view} · plan “%{plan}” on %{tree}",
      view: basis_view(basis),
      plan: name,
      tree: ClassificationName.display(basis.tree)
    )
  end

  defp basis_phrase(basis) do
    gettext("View %{view} · several active plans on %{tree}",
      view: basis_view(basis),
      tree: ClassificationName.display(basis.tree)
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
  # #828 (ADR-0048 §2, §5.2): due within the horizon across the WHOLE
  # CATALOG. Each row carries whether the security is held, so the card can
  # mark a candidate rather than hide it — the default is the requirement.
  @upcoming_days 30

  defp upcoming_days, do: @upcoming_days

  defp upcoming_events do
    events = Events.upcoming(days: @upcoming_days, limit: 8)
    securities = Map.new(Catalog.list_securities(), &{&1.id, &1})
    held = MapSet.new(Events.held_security_ids())

    for event <- events,
        security = Map.get(securities, event.security_id),
        not is_nil(security) do
      %{
        event: event,
        security_name: security.name,
        held: MapSet.member?(held, security.id)
      }
    end
  end

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
  #
  # #1081 (pick J1.2 A): the quote finding says it counts the catalog, as
  # the strip's cell does. The line's first finding carries its noun ("4
  # securities without an asset class"), so a line with no stale quote does
  # not open on a bare "4 without an asset class"; a later finding keeps its
  # short form after the first one's noun.
  #
  # #1068 (D-15, board 01 pin 5): the bonds priced on two scales, in either
  # direction, close the line with their own noun, so the finding reads the
  # same wherever it stands.
  defp dq_findings(dq) do
    [
      dq.without_quote > 0 && {:quotes, dq.without_quote},
      dq.without_class > 0 && {:class, dq.without_class},
      dq.without_logo > 0 && {:logo, dq.without_logo},
      dq.two_scales > 0 && {:two_scales, dq.two_scales}
    ]
    |> Enum.filter(& &1)
    |> Enum.with_index()
    |> Enum.map(fn {{finding, count}, index} -> dq_finding(finding, count, index == 0) end)
  end

  # The quote finding always opens the line when present, so it always
  # carries its noun.
  defp dq_finding(:quotes, count, _first?) do
    %{
      role: "dq-quotes",
      href: "/securities?dq=stale_quote",
      text:
        ngettext(
          "one security in the catalog without a quote in 7 days",
          "%{count} securities in the catalog without a quote in 7 days",
          count
        )
    }
  end

  defp dq_finding(:class, count, first?) do
    %{
      role: "dq-class",
      href:
        "/securities?" <>
          Query.encode(%{"filter" => ["asset_class:is_nil", "is_retired:is_false"]}),
      text:
        if(first?,
          do:
            ngettext(
              "one security without an asset class",
              "%{count} securities without an asset class",
              count
            ),
          else: ngettext("one without an asset class", "%{count} without an asset class", count)
        )
    }
  end

  defp dq_finding(:logo, count, first?) do
    %{
      role: "dq-logo",
      href: "/securities?dq=missing_logo",
      text:
        if(first?,
          do:
            ngettext("one security without a logo", "%{count} securities without a logo", count),
          else: ngettext("one without a logo", "%{count} without a logo", count)
        )
    }
  end

  defp dq_finding(:two_scales, count, _first?) do
    %{
      role: "dq-two-scales",
      href: "/securities?dq=two_scales",
      text:
        ngettext(
          "one bond priced on two scales",
          "%{count} bonds priced on two scales",
          count
        )
    }
  end

  # Highest severity present (UX-DR17): a bond priced on two scales counts a
  # hundredfold too high or too low in the total, so it is a problem (#1068,
  # D-15); a stale quote skews valuations, so it is attention-level; a
  # missing class or logo is a note-level catalog gap.
  defp dq_severity(%{two_scales: n}) when n > 0, do: :problem
  defp dq_severity(%{without_quote: n}) when n > 0, do: :attention
  defp dq_severity(_dq), do: :note

  # Securities needing attention (#337 data-quality card): no recent quote
  # (none at all, or older than 7 days), no persisted asset class, no logo,
  # and since #1068 a bond priced on two scales.
  defp data_quality_report do
    # The counts come from the shared predicates (#705), so each finding's
    # number is produced by the same rule as the list its link opens. The
    # asset-class finding stays an ordinary column filter: `asset_class` is a
    # stored column, so it needs no predicate of its own -- and it is keyed on
    # the STORED value per #700, which is what makes the count addressable.
    # A retired security leaves it as it leaves the predicates' sets (PR
    # #1102), and the link carries the same `is_retired:is_false` filter.
    %{
      total: length(Catalog.list_securities()),
      without_quote: DataQuality.count("stale_quote"),
      without_class:
        Enum.count(
          Catalog.list_securities(is_retired: false),
          &is_nil(&1.asset_class)
        ),
      without_logo: DataQuality.count("missing_logo"),
      two_scales: DataQuality.count("two_scales")
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
