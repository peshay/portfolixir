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

  Above both sits the operator's **own rules** section (ADR-0049 §9, Sprint 15
  pick F1-A, board `ux-design-2026-09-23/01-policy-rules-surface`): the rules
  in force for the active view evaluated into findings, breached and
  undetermined first, each with the rule's words beside the measured value,
  and a native dialog to create, edit (a new version) and retire a rule. The
  lens's Top-N below is titled as generic thresholds, so the two mechanisms
  never read as one (§7) — they do not read each other either.

  **No verdict.** A threshold crossing is the lens's own arithmetic and is
  rendered as the threshold ("above 10 %"), never as advice; nothing here
  recommends, rates or signals (ADR-0047 §7), and ADR-0023's rebalancing hints
  are not built here.
  """

  use PortfolixirWeb, :live_view

  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.AssetClasses
  alias Portfolixir.Classifications
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.PolicyFindings
  alias Portfolixir.Portfolios.PolicyRules
  alias Portfolixir.Portfolios.Risk
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.ClassificationName
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.LiveParam
  alias PortfolixirWeb.PolicyRuleLabel
  alias PortfolixirWeb.Risk.PolicyRuleDialog
  alias PortfolixirWeb.Risk.PolicyRuleFormat

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

    {:ok,
     socket
     |> assign(:portfolio, portfolio)
     |> assign(:risk, load(portfolio, socket))
     |> assign(:rule_dialog, nil)
     |> assign(:notice, nil)
     |> load_rules()}
  end

  # ADR-0049 §9: the rules of the active view's context, their findings, and
  # the names the rules' words need. The dialog's options are loaded with it.
  defp load_rules(%{assigns: %{portfolio: nil}} = socket) do
    assign(socket, findings: nil, rules: [], names: empty_names(), options: nil)
  end

  defp load_rules(socket) do
    portfolio = socket.assigns.portfolio
    view_id = socket.assigns[:active_view_id]

    findings =
      case PolicyFindings.for_portfolio(portfolio.id, view: view_id) do
        {:error, :view_not_found} -> PolicyFindings.for_portfolio(portfolio.id)
        result -> result
      end

    rules = PolicyRules.list_rules(portfolio.id, view: findings.view_id, include_retired: true)
    options = options()

    assign(socket,
      findings: findings,
      rules: rules,
      names: names(options),
      options: options
    )
  end

  defp empty_names, do: %{securities: %{}, categories: %{}, views: %{}}

  defp options do
    classifications = Classifications.list_classifications()

    %{
      securities:
        [sort: {:name, :asc}]
        |> Catalog.list_securities()
        |> Enum.reject(& &1.is_retired)
        |> Enum.map(&{&1.id, &1.name}),
      categories:
        Enum.map(classifications, fn classification ->
          {ClassificationName.display(classification),
           classification.id
           |> Classifications.list_categories()
           |> Enum.map(
             &{classification.id, &1.id, ClassificationName.category(classification, &1)}
           )}
        end),
      classifications: Enum.map(classifications, &{&1.id, ClassificationName.display(&1)}),
      views: Enum.map(Buckets.list_views(), &{&1.id, &1.name})
    }
  end

  defp names(options) do
    %{
      securities: Map.new(options.securities),
      categories:
        options.categories
        |> Enum.flat_map(fn {_group, categories} -> categories end)
        |> Map.new(fn {_cid, id, name} -> {id, name} end),
      views: Map.new(options.views)
    }
  end

  @impl true
  def handle_event("new_rule", _params, socket) do
    {:noreply, socket |> assign(:rule_dialog, :new) |> assign(:notice, nil)}
  end

  def handle_event("edit_rule", %{"id" => id}, socket) do
    with {:ok, rule_id} <- LiveParam.fetch_id(id),
         %{} = rule <- Enum.find(socket.assigns.rules, &(&1.id == rule_id)) do
      {:noreply, socket |> assign(:rule_dialog, rule) |> assign(:notice, nil)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("close_policy_rule_dialog", _params, socket) do
    {:noreply, assign(socket, :rule_dialog, nil)}
  end

  # An event this page does not know, or a payload it cannot read, changes
  # nothing (E25 S4, F17).
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({PolicyRuleDialog, {:saved, message}}, socket) do
    {:noreply,
     socket
     |> assign(:rule_dialog, nil)
     |> assign(:notice, message)
     |> load_rules()}
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
          <.policy_rules
            findings={@findings}
            rules={@rules}
            names={@names}
            notice={@notice}
            view_name={@view_name}
          />

          <.live_component
            :if={@rule_dialog}
            module={PolicyRuleDialog}
            id="policy-rule-dialog"
            rule={if @rule_dialog == :new, do: nil, else: @rule_dialog}
            portfolio_id={@portfolio.id}
            view_id={@findings.view_id}
            view_name={@view_name}
            options={@options}
          />

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
            <%!-- E25 S4, F72 (board 11, part 3): the number comes from the
                 answer, how many leading names the matrix actually ran over,
                 so the sentence stays true below the list's length. --%>
            <p class="summary-basis" data-role="risk-basis">
              <%= if @risk.metrics.correlations.leading_names >= 2 do %>
                <%= ngettext(
                  "Basis: the flow-adjusted daily return factors of the TTWROR chain, in %{currency}, annualized by √365 — a deposit is not a return. A day without a return base yields no observation, never a zero. Correlations convert to %{currency} first and run over the %{count} largest position.",
                  "Basis: the flow-adjusted daily return factors of the TTWROR chain, in %{currency}, annualized by √365 — a deposit is not a return. A day without a return base yields no observation, never a zero. Correlations convert to %{currency} first and run over the %{count} largest positions.",
                  @risk.metrics.correlations.leading_names,
                  currency: @risk.base_currency
                ) %>
              <% else %>
                <%= gettext(
                  "Basis: the flow-adjusted daily return factors of the TTWROR chain, in %{currency}, annualized by √365 — a deposit is not a return. A day without a return base yields no observation, never a zero. Correlations convert to %{currency} first.",
                  currency: @risk.base_currency
                ) %>
              <% end %>
            </p>
          </section>

          <section class="workspace-section" aria-labelledby="risk-top-title">
            <header class="section-head">
              <%!-- ADR-0049 §7: the lens's shipped thresholds are generic,
                   and the title says so, so a weight carrying two badges —
                   the operator's rule and the generic line — reads as two
                   statements, not a contradiction. --%>
              <h2 id="risk-top-title">
                <%= gettext("Largest single names") %>
                <span class="section-head__meta">
                  · <%= gettext("generic thresholds, not policy rules") %>
                </span>
              </h2>
            </header>
            <%= if @risk.top_holdings == [] do %>
              <p class="empty-state"><%= gettext("No valued position in this view.") %></p>
            <% else %>
              <div class="data-table-wrapper">
                <table class="data-table risk-top-table risk-fit-table" id="risk-top-holdings">
                  <thead>
                    <tr>
                      <th><%= gettext("Security") %></th>
                      <th class="risk-col-optional"><%= gettext("Asset class") %></th>
                      <th class="num risk-col-optional"><%= gettext("Value") %></th>
                      <th class="num"><%= gettext("Weight") %></th>
                      <th><%= gettext("Generic threshold") %></th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={holding <- @risk.top_holdings} data-security-id={holding.security_id}>
                      <td><%= holding.security_name %></td>
                      <td class="muted risk-col-optional"><%= asset_class_label(holding.asset_class) %></td>
                      <td class="num risk-col-optional"><%= Format.money(holding.market_value) %> <%= @risk.base_currency %></td>
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
            <%!-- The page reads the lens with its shipped defaults, and caps
                 are opt-in per request (FR9): no cap is ever configured here,
                 so the section says so rather than rendering a list that can
                 only be empty. --%>
            <p class="empty-state">
              <%= gettext("No cap configured — there is nothing to exceed. Caps are set per request over the API.") %>
            </p>

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
                <table class="data-table risk-fit-table">
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

  attr(:findings, :map, required: true)
  attr(:rules, :list, required: true)
  attr(:names, :map, required: true)
  attr(:notice, :string, default: nil)
  attr(:view_name, :string, required: true)

  # The operator's own rules (ADR-0049 §9, pick F1-A): the findings, breached
  # and undetermined first, with the rule's words beside the measured value;
  # retired rules readable behind a closed disclosure.
  defp policy_rules(assigns) do
    assigns =
      assigns
      |> assign(:retired, Enum.filter(assigns.rules, &(&1.status == :retired)))
      |> assign(:scheduled, Enum.filter(assigns.rules, &(&1.status == :scheduled)))
      |> assign(:rules_by_id, Map.new(assigns.rules, &{&1.id, &1}))

    ~H"""
    <section class="workspace-section policy-rules" id="policy-rules" aria-labelledby="policy-rules-title">
      <header class="section-head">
        <h2 id="policy-rules-title">
          <%= gettext("Own rules") %>
          <span class="section-head__meta" data-role="policy-rules-summary">
            · <%= ngettext("%{count} breached", "%{count} breached", @findings.summary.breached) %>
            · <%= ngettext("%{count} undetermined", "%{count} undetermined", @findings.summary.undetermined) %>
            · <%= ngettext("%{count} met", "%{count} met", @findings.summary.ok) %>
          </span>
        </h2>
        <button type="button" class="button-secondary" phx-click="new_rule">
          <%= gettext("New rule") %>
        </button>
      </header>

      <p :if={@notice} class="alert-success" role="status"><%= @notice %></p>

      <%= if @findings.findings == [] do %>
        <p class="empty-state" data-role="policy-rules-empty">
          <%= gettext("No rule in force for this view. A rule sets a line over a weight, a drift, the HHI or a portfolio metric; its finding says which side of the line the figure is on.") %>
        </p>
      <% else %>
        <div class="data-table-wrapper">
          <table class="data-table policy-findings-table risk-fit-table" id="policy-findings">
            <thead>
              <tr>
                <th><%= gettext("Rule") %></th>
                <th class="num"><%= gettext("Measured") %></th>
                <th class="num policy-col-line"><%= gettext("Line") %></th>
                <th><%= gettext("State") %></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={finding <- @findings.findings} data-state={finding.state} data-rule-id={finding.rule_id}>
                <td>
                  <button
                    type="button"
                    class="link-button policy-rule__name"
                    phx-click="edit_rule"
                    phx-value-id={finding.rule_id}
                  >
                    <%= finding.rule_name %>
                  </button>
                  <span class="policy-rule__words"><%= PolicyRuleFormat.words(finding, @names) %><.author_mark author={finding.author} lead={gettext("Version in force by:")} /></span>
                  <%!-- A planned change is part of the rule's standard; it
                       is shown where the rule is, with the day it starts. --%>
                  <span
                    :if={next = next_version(@rules_by_id, finding.rule_id)}
                    class="policy-rule__next"
                    data-role="policy-rule-next"
                  >
                    <%= gettext("From %{date}: line %{line}",
                      date: Format.date(next.valid_from),
                      line: PolicyRuleFormat.line(next)
                    ) %>
                  </span>
                </td>
                <td class="num">
                  <%= PolicyRuleFormat.value(finding.measure, finding.value) %>
                  <span class="policy-rule__line-sub">
                    <%= gettext("Line %{line}", line: PolicyRuleFormat.line(finding)) %>
                  </span>
                </td>
                <td class="num policy-col-line"><%= PolicyRuleFormat.line(finding) %></td>
                <td>
                  <span class={["badge", state_class(finding)]} data-state={finding.state}>
                    <%= PolicyRuleLabel.state(finding.state) %><%= if finding.state == :breached do %>
                      · <%= PolicyRuleFormat.distance(finding.measure, finding.distance) %>
                    <% end %>
                  </span>
                  <span :if={finding.state == :undetermined} class="policy-rule__reason">
                    <%= undetermined_reason(finding) %>
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      <% end %>

      <p class="summary-basis" data-role="policy-rules-basis">
        <%= gettext(
          "Evaluated on read, as of %{date}, on the steerable basis of the view “%{view}”. Each rule names the figure it reads; a figure that cannot be read is undetermined, never met. A finding does not say what to do.",
          date: Format.date(@findings.as_of),
          view: @view_name
        ) %>
      </p>

      <%!-- A rule that has not started is not a finding yet, and it must
           still be reachable: to read, change or delete it before it counts
           (closing act, UAT and correctness roles). --%>
      <div :if={@scheduled != []} id="policy-rules-scheduled" class="policy-rules-scheduled">
        <h3 class="policy-rules-scheduled__title"><%= gettext("Scheduled rules") %></h3>
        <ul class="policy-rules-retired">
          <li :for={rule <- @scheduled}>
            <button type="button" class="link-button" phx-click="edit_rule" phx-value-id={rule.id}>
              <%= rule.name %>
            </button>
            <span class="muted">
              · <%= gettext("from %{date}", date: Format.date(rule.next_version.valid_from)) %>
              · <%= PolicyRuleFormat.line(rule.next_version) %>
              <.author_mark author={rule.next_version.author} lead={gettext("Version by:")} />
            </span>
          </li>
        </ul>
      </div>

      <details :if={@retired != []} class="perf-table-disclosure" id="policy-rules-retired">
        <summary class="disclosure-summary">
          <AppShell.icon name={:chevron_right} size={12} class="disclosure-chevron" />
          <%= ngettext("Show the retired rule (%{count})", "Show the retired rules (%{count})", length(@retired)) %>
        </summary>
        <ul class="policy-rules-retired">
          <li :for={rule <- @retired}>
            <button type="button" class="link-button" phx-click="edit_rule" phx-value-id={rule.id}>
              <%= rule.name %>
            </button>
            <span class="muted">
              · <%= PolicyRuleFormat.period(List.last(rule.versions)) %>
              · <%= PolicyRuleFormat.line(List.last(rule.versions)) %>
              <.author_mark author={List.last(rule.versions).author} lead={gettext("Version by:")} />
            </span>
          </li>
        </ul>
      </details>
    </section>
    """
  end

  attr(:author, :atom, required: true)
  attr(:lead, :string, required: true, doc: "the hidden words before the author, for a reader")

  # E25 S7, G30; pick G12.1 = A (board 12-e25-new-marks): "Agent" as the
  # last word of a rule's line when the agent wrote its version — the
  # research log's word, no badge and no colour. The operator's own rules
  # carry no word, so a portfolio without the agent's rules reads as before.
  defp author_mark(assigns) do
    ~H"""
    <%= if @author == :agent do %> <span data-role="policy-rule-author">· <span class="visually-hidden"><%= @lead %> </span><%= gettext("Agent") %></span><% end %>
    """
  end

  defp next_version(rules_by_id, rule_id) do
    case Map.get(rules_by_id, rule_id) do
      %{status: :in_force, next_version: %{} = next} -> next
      _none -> nil
    end
  end

  defp state_class(%{state: :breached, severity: :hard}), do: "badge--danger"
  defp state_class(%{state: :breached}), do: "badge-warning"
  defp state_class(%{state: :undetermined}), do: "badge--undetermined"
  defp state_class(_ok), do: "badge--neutral"

  defp undetermined_reason(%{reason: :insufficient_data, observations: n, required: required})
       when is_integer(n) and is_integer(required),
       do: observations_of(n, required)

  defp undetermined_reason(%{reason: reason}), do: PolicyRuleLabel.reason(reason)

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

  defp asset_class_label(nil), do: "—"
  defp asset_class_label(code), do: AssetClasses.label(code)

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
