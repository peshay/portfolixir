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

  After the metrics sits the **Crashes** section (Sprint 29 C6, FR-54,
  ADR-0058 §9; `PortfolixirWeb.Risk.CrashSection`): the crash windows'
  ranked lists over the view's holdings or the catalogue, its choice kept in
  the address.

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

  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Risk
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Dashboard.Widgets.OwnRules
  alias PortfolixirWeb.Dashboard.Widgets.RiskLens
  alias PortfolixirWeb.LiveParam
  alias PortfolixirWeb.Risk.CrashSection
  alias PortfolixirWeb.Risk.PolicyRuleDialog

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
     |> assign(:crash_params, %{})
     |> load_rules()}
  end

  # Sprint 29 C6 (board ux-design-2026-11-12-sprint29/01, P4): the Crashes
  # section's window, list and universe are kept in the address; the
  # section reads them from here.
  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :crash_params, Map.filter(params, fn {_k, v} -> is_binary(v) end))}
  end

  # ADR-0049 §9: the rules of the active view's context, their findings, and
  # the names the rules' words need. The dialog's options are loaded with it.
  defp load_rules(%{assigns: %{portfolio: nil}} = socket) do
    assign(socket, findings: nil, rules: [], names: empty_names(), options: nil)
  end

  # Sprint 32 W4: the read is the widget „Eigene Regeln“'s module's.
  defp load_rules(socket) do
    loaded = OwnRules.load(socket.assigns.portfolio.id, socket.assigns[:active_view_id])
    assign(socket, Map.take(loaded, [:findings, :rules, :names, :options]))
  end

  defp empty_names, do: OwnRules.empty_names()

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

  # The result's dismiss (#1064): the slot empties until the next action.
  def handle_event("dismiss_result", _params, socket) do
    {:noreply, assign(socket, :notice, nil)}
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

  # Sprint 32 W4: the read is the lens widgets' module's.
  defp load(portfolio, socket), do: RiskLens.load(portfolio.id, socket.assigns[:active_view_id])

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        defaults: Risk.defaults(),
        view_name: view_name(assigns[:active_view])
      )

    ~H"""
    <AppShell.shell page_address={@page_address}
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

          <%!-- #1366 (board ux-design-2026-11-15-sprint30/02 ⑥): the crash
               lists over the whole catalogue need no portfolio, so they stay
               within reach under the empty line. --%>
          <.live_component
            :if={is_nil(@portfolio)}
            module={CrashSection}
            id="risk-crashes-section"
            params={@crash_params}
            view_id={nil}
            base_currency={nil}
            catalogue_only={true}
          />
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
              <%!-- Sprint 23, Lane I (board ux-design-2026-11-03-sprint23-i1
                   ①): the gap rule and the correlations' rule are method
                   sentences, in the heading's ⓘ; the series, the currency
                   and the annualisation stay as the basis line (②). --%>
              <div class="section-title">
                <h2 id="risk-metrics-title"><%= gettext("Portfolio metrics") %></h2>
                <AppShell.section_info>
                  <:line :for={line <- RiskLens.metrics_info(@risk)}><%= line %></:line>
                </AppShell.section_info>
              </div>
            </header>
            <%!-- Sprint 32 W4: drawn by the widget „Kennzahlen des
                 Portfolios“'s module, one code path for both. --%>
            <RiskLens.metrics risk={@risk} />
          </section>

          <%!-- Sprint 29 C6 (board ux-design-2026-11-12-sprint29/01, P1 A):
               the Crashes section after the portfolio metrics, whose
               „Max. Rückgang“ is the same notion on the view. --%>
          <.live_component
            module={CrashSection}
            id="risk-crashes-section"
            params={@crash_params}
            view_id={@active_view_id}
            base_currency={@portfolio.base_currency_code}
          />

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
            <%!-- Sprint 32 W4: the widget „Größte Einzelpositionen“'s module. --%>
            <RiskLens.top_holdings risk={@risk} defaults={@defaults} />
          </section>

          <section class="workspace-section" aria-labelledby="risk-hhi-title">
            <header class="section-head">
              <h2 id="risk-hhi-title"><%= gettext("Concentration (HHI)") %></h2>
            </header>
            <%!-- Sprint 32 W4: the widget „Klumpenrisiko“'s module. --%>
            <RiskLens.hhi risk={@risk} defaults={@defaults} />
          </section>

          <section class="workspace-section" data-role="risk-caps" aria-labelledby="risk-caps-title">
            <header class="section-head">
              <div class="section-title">
                <h2 id="risk-caps-title"><%= gettext("Asset-class caps") %></h2>
                <AppShell.section_info>
                  <:line><%= RiskLens.caps_info() %></:line>
                </AppShell.section_info>
              </div>
            </header>
            <%!-- Sprint 32 W4: the widget „Anlageklassen-Obergrenzen“'s
                 module. --%>
            <RiskLens.caps risk={@risk} />
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
    ~H"""
    <section class="workspace-section policy-rules" id="policy-rules" aria-labelledby="policy-rules-title">
      <header class="section-head">
        <%!-- Sprint 23, Lane I (board ux-design-2026-11-03-sprint23-i1 ①):
             the two rule sentences are method, in the heading's ⓘ; the
             as-of and the view stay as the basis line (②). --%>
        <div class="section-title">
          <h2 id="policy-rules-title" class="result-focus-fallback" tabindex="-1">
            <%= gettext("Own rules") %>
            <OwnRules.summary findings={@findings} />
          </h2>
          <AppShell.section_info>
            <:line :for={line <- OwnRules.info()}><%= line %></:line>
          </AppShell.section_info>
        </div>
        <button type="button" class="button-secondary" phx-click="new_rule">
          <%= gettext("New rule") %>
        </button>
      </header>

      <%!-- #1064 (pick J7 = A, board 07): the rule dialog's answer is an
           inline result, a note with its word and glyph. --%>
      <AppShell.inline_result
        id="policy-rules-result"
        class="inline-result--page"
        result={@notice && {:note, @notice}}
        focus_fallback="#policy-rules-title"
      />

      <%!-- Sprint 32 W4: the findings are drawn by the widget „Eigene
           Regeln“'s module; a rule's name opens the dialog here. --%>
      <OwnRules.body findings={@findings} rules={@rules} names={@names} view_name={@view_name} />
    </section>
    """
  end

  defp view_name(nil), do: gettext("Everything")
  defp view_name(view), do: view.name
end
