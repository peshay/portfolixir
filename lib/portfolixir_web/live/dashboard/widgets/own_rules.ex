defmodule PortfolixirWeb.Dashboard.Widgets.OwnRules do
  @moduledoc """
  The section widget „Eigene Regeln“ `own_rules` (I57; Sprint 32 W4;
  ADR-0049 §9; ADR-0062's amendment of 2026-11-25, points 3 and 7;
  planning board `ux-design-2026-11-25-sprint32/02` ②): the operator's
  own rules on Wealth's tab „Risiko“, moved here from
  `PortfolixirWeb.RiskLive` so that one code path draws the section on the
  tab (`summary/1` in its heading, `body/1` under it) and on a dashboard
  (`widget/1`).

  Its findings are `Portfolixir.Portfolios.PolicyFindings.for_portfolio/2`
  for the first portfolio and the scope, the read `GET
  /api/v1/portfolios/:portfolio_id/policy_findings?view=` answers, with
  the rules of `GET /api/v1/portfolios/:portfolio_id/policy_rules`
  (`load/2`, which the tab calls too): breached and undetermined first,
  each with the rule's words beside the measured value; the scheduled
  rules and the retired ones behind a disclosure.

  **The rule dialog stays on the tab** (ADR-0022's amendment of
  2026-11-21, point 3): on the tab a rule's name opens it; on a dashboard
  the names are text and the footer leads to the tab. **No verdict**: a
  finding says which side of the line a figure is on, not what to do.

  Its compact form is the section's own narrow layout: the same markup,
  drawn once (`widget--single-form`).
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Classifications
  alias Portfolixir.Dashboards.Widgets
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.PolicyFindings
  alias Portfolixir.Portfolios.PolicyRules
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.ClassificationName
  alias PortfolixirWeb.Dashboard.Widget
  alias PortfolixirWeb.Dashboard.Widgets.RiskLens
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.PolicyRuleLabel
  alias PortfolixirWeb.Risk.PolicyRuleFormat
  alias PortfolixirWeb.SecurityNames

  # -- the read -------------------------------------------------------------------

  @doc """
  The rules of `portfolio_id`'s context for the view `view_id` (nil:
  Everything; a view gone meanwhile reads Everything), their findings, the
  names the rules' words need and the dialog's options (ADR-0049 §9). The
  tab's read, and the widget's.
  """
  @spec load(integer(), integer() | nil) :: map()
  def load(portfolio_id, view_id) do
    findings =
      case PolicyFindings.for_portfolio(portfolio_id, view: view_id) do
        {:error, :view_not_found} -> PolicyFindings.for_portfolio(portfolio_id)
        result -> result
      end

    rules = PolicyRules.list_rules(portfolio_id, view: findings.view_id, include_retired: true)
    securities = Catalog.list_securities(sort: {:name, :asc})
    options = options(securities)

    %{
      findings: findings,
      rules: rules,
      names: names(options, securities, findings.findings),
      options: options
    }
  end

  @doc "No rules: the tab without a portfolio."
  @spec empty_names() :: map()
  def empty_names, do: %{securities: %{}, categories: %{}, views: %{}}

  @doc """
  The widget's read, in the dashboard's background task: `load/2` for the
  first portfolio and the scope `scope_id`, with the view's name.
  `%{state: :none}` without a portfolio.
  """
  @spec read(integer() | nil) :: map()
  def read(scope_id) do
    case Portfolios.first_portfolio() do
      nil ->
        %{state: :none}

      portfolio ->
        view = scope_id && Buckets.get_view(scope_id)

        portfolio.id
        |> load(view && view.id)
        |> Map.drop([:options])
        |> Map.merge(%{state: :ok, view_name: view && view.name})
    end
  end

  # The choices a new rule may pick: retired securities stay out.
  defp options(all_securities) do
    classifications = Classifications.list_classifications()
    securities = Enum.reject(all_securities, & &1.is_retired)

    # Twins are told apart by their ISIN (the closing act, UAT-13).
    tags = SecurityNames.tags(securities)

    %{
      securities: Enum.map(securities, &{&1.id, SecurityNames.label(tags, &1)}),
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

  # The names the findings' words read: every active security, plus every
  # security subject of a rule in force that the choices leave out — a
  # retired one, read from the stored row (#944, board 08.4). It resolves to
  # its name where the words fell back to "Security". A subject deleted since
  # still falls back. Every label comes from one set of tags over all of
  # them, so a retired subject and its active twin both carry what tells
  # them apart — the choices' own labels count only the active securities
  # and would leave the active twin bare.
  defp names(options, all_securities, findings) do
    subject_ids =
      MapSet.new(
        for %{subject_type: :security, security_id: id} <- findings, is_integer(id), do: id
      )

    named = Enum.filter(all_securities, &(not &1.is_retired or &1.id in subject_ids))
    tags = SecurityNames.tags(named)

    %{
      securities: Map.new(named, &{&1.id, SecurityNames.label(tags, &1)}),
      categories:
        options.categories
        |> Enum.flat_map(fn {_group, categories} -> categories end)
        |> Map.new(fn {_cid, id, name} -> {id, name} end),
      views: Map.new(options.views)
    }
  end

  @doc """
  What the section's ⓘ says (Sprint 23, Lane I): the two rule sentences,
  method.
  """
  @spec info() :: [String.t()]
  def info do
    [
      gettext(
        "Each rule names the figure it reads; a figure that cannot be read is undetermined, never met."
      ),
      gettext("A finding does not say what to do.")
    ]
  end

  # -- the section ------------------------------------------------------------------

  attr(:findings, :map, required: true)

  attr(:lead, :boolean,
    default: true,
    doc:
      "the leading „·“ that follows the title on the tab's head; a widget, whose title stands in its frame's head, draws the line without it"
  )

  @doc "The findings counted: breached, undetermined, met."
  def summary(assigns) do
    ~H"""
    <span class="section-head__meta" data-role="policy-rules-summary">
      <%= if @lead do %>· <% end %><span data-role="policy-rules-counts"><%= ngettext("%{count} breached", "%{count} breached", @findings.summary.breached) %>
      · <%= ngettext("%{count} undetermined", "%{count} undetermined", @findings.summary.undetermined) %>
      · <%= ngettext("%{count} met", "%{count} met", @findings.summary.ok) %></span>
    </span>
    """
  end

  attr(:prefix, :string,
    default: "",
    doc: "the ids' prefix: empty on the tab, the widget's on a dashboard"
  )

  attr(:findings, :map, required: true)
  attr(:rules, :list, required: true)
  attr(:names, :map, required: true)
  attr(:view_name, :string, required: true)
  attr(:editable, :boolean, default: true, doc: "whether a rule's name opens the tab's dialog")

  @doc """
  The findings with the rules' words, the basis line, the scheduled rules
  and the retired ones behind a disclosure.
  """
  def body(assigns) do
    assigns =
      assigns
      |> assign(:retired, Enum.filter(assigns.rules, &(&1.status == :retired)))
      |> assign(:scheduled, Enum.filter(assigns.rules, &(&1.status == :scheduled)))
      |> assign(:rules_by_id, Map.new(assigns.rules, &{&1.id, &1}))

    ~H"""
    <%= if @findings.findings == [] do %>
      <p class="empty-state" data-role="policy-rules-empty">
        <%= gettext("No rule in force for this view. A rule sets a line over a weight, a drift, the HHI or a portfolio metric; its finding says which side of the line the figure is on.") %>
      </p>
    <% else %>
      <div class="data-table-wrapper">
        <table class="data-table policy-findings-table risk-fit-table" id={@prefix <> "policy-findings"}>
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
                <.rule_name editable={@editable} id={finding.rule_id} class="link-button policy-rule__name"><%= finding.rule_name %></.rule_name><.author_mark author={finding.rule_name_author} lead={gettext("Named by:")} role="policy-rule-name-author" />
                <span class="policy-rule__words"><.rule_words parts={PolicyRuleFormat.word_parts(finding, @names)} /><.author_mark author={finding.author} lead={gettext("Version in force by:")} /></span>
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
        "Evaluated on read, as of %{date}, on the steerable basis of the view “%{view}”.",
        date: Format.date(@findings.as_of),
        view: @view_name
      ) %>
    </p>

    <%!-- A rule that has not started is not a finding yet, and it must
         still be reachable: to read, change or delete it before it counts
         (closing act, UAT and correctness roles). --%>
    <div :if={@scheduled != []} id={@prefix <> "policy-rules-scheduled"} class="policy-rules-scheduled">
      <h3 class="policy-rules-scheduled__title"><%= gettext("Scheduled rules") %></h3>
      <ul class="policy-rules-retired">
        <li :for={rule <- @scheduled}>
          <.rule_name editable={@editable} id={rule.id} class="link-button"><%= rule.name %></.rule_name><.author_mark author={rule.name_author} lead={gettext("Named by:")} role="policy-rule-name-author" />
          <span class="muted">
            · <%= gettext("from %{date}", date: Format.date(rule.next_version.valid_from)) %>
            · <%= PolicyRuleFormat.line(rule.next_version) %>
            <.author_mark author={rule.next_version.author} lead={gettext("Version by:")} />
          </span>
        </li>
      </ul>
    </div>

    <details :if={@retired != []} class="perf-table-disclosure" id={@prefix <> "policy-rules-retired"}>
      <summary class="disclosure-summary">
        <AppShell.icon name={:chevron_right} size={12} class="disclosure-chevron" />
        <%= ngettext("Show the retired rule (%{count})", "Show the retired rules (%{count})", length(@retired)) %>
      </summary>
      <ul class="policy-rules-retired">
        <li :for={rule <- @retired}>
          <.rule_name editable={@editable} id={rule.id} class="link-button"><%= rule.name %></.rule_name><.author_mark author={rule.name_author} lead={gettext("Named by:")} role="policy-rule-name-author" />
          <span class="muted">
            · <%= PolicyRuleFormat.period(List.last(rule.versions)) %>
            · <%= PolicyRuleFormat.line(List.last(rule.versions)) %>
            <.author_mark author={List.last(rule.versions).author} lead={gettext("Version by:")} />
          </span>
        </li>
      </ul>
    </details>
    """
  end

  attr(:editable, :boolean, required: true)
  attr(:id, :integer, required: true)
  attr(:class, :string, required: true)
  slot(:inner_block, required: true)

  # A rule's name: on the tab the button that opens its dialog; on a
  # dashboard text, the dialog staying on the tab.
  defp rule_name(assigns) do
    ~H"""
    <button :if={@editable} type="button" class={@class} phx-click="edit_rule" phx-value-id={@id}><%= render_slot(@inner_block) %></button><span :if={not @editable} class="policy-rule__name-text" data-role="policy-rule-name"><%= render_slot(@inner_block) %></span>
    """
  end

  # -- the widget ---------------------------------------------------------------------

  attr(:item, :map, required: true)
  attr(:card, :any, required: true, doc: "nil while the read runs, :error, or `read/1`'s answer")
  attr(:scope_label, :string, default: nil)

  @doc "The widget „Eigene Regeln“: the tab's findings, the dialog linked."
  def widget(assigns) do
    assigns = assign(assigns, :id, "dashboard-own-rules" <> assigns.item.uid)

    ~H"""
    <Widget.frame
      id={@id}
      item={@item}
      title={Widgets.title("own_rules")}
      class="widget--single-form"
      scope_label={@scope_label}
      full_href={full_href(@item.scope)}
      full_label={gettext("Edit rules →")}
      full_role="own-rules-edit"
    >
      <:info :for={line <- info()}><%= line %></:info>
      <:shared>
        <div :if={is_nil(@card)} class="section-skeleton" aria-busy="true" data-role="own-rules-skeleton"></div>
        <p :if={@card == :error} class="hint" data-role="own-rules-failed">
          <%= gettext("Couldn't load the rules.") %>
        </p>
        <p :if={@card == %{state: :none}} class="empty-state" data-role="own-rules-none">
          <%= gettext("No portfolio yet — risk is measured over holdings, and there are none.") %>
        </p>
        <%= if match?(%{state: :ok}, @card) do %>
          <%!-- The S32 closing act: the title stands in the frame's head, so
               the line starts with its first count, not with „·“. --%>
          <p class="widget-own-rules__summary"><.summary findings={@card.findings} lead={false} /></p>
          <.body
            prefix={@id <> "-"}
            findings={@card.findings}
            rules={@card.rules}
            names={@card.names}
            view_name={@card.view_name || gettext("Everything")}
            editable={false}
          />
        <% end %>
      </:shared>
    </Widget.frame>
    """
  end

  # The tab, where the dialog makes and changes a rule, on the scope.
  defp full_href(nil), do: "/risk"
  defp full_href(view_id), do: "/risk?" <> URI.encode_query([{"view", view_id}])

  # -- helpers moved from the tab (Sprint 32 W4) --------------------------------------

  attr(:parts, :list, required: true)

  # A rule's words, the stored subject name isolated in <bdi> (E25 S7, G20;
  # pick G12.2 = B): a direction control a legacy name still carries
  # reorders at most the name, never the line.
  defp rule_words(assigns) do
    ~H"""
    <%= for {{kind, text}, index} <- Enum.with_index(@parts) do %><%= if index > 0 do %> · <% end %><%= if kind == :stored do %><bdi><%= text %></bdi><% else %><%= text %><% end %><% end %>
    """
  end

  attr(:author, :atom, required: true)
  attr(:lead, :string, required: true, doc: "the hidden words before the author, for a reader")
  attr(:role, :string, default: "policy-rule-author", doc: "what the mark covers")

  # E25 S7, G30; pick G12.1 = A (board 12-e25-new-marks): "Agent" as the
  # last word of a rule's line when the agent wrote its version — the
  # research log's word, no badge and no colour. The operator's own rules
  # carry no word, so a portfolio without the agent's rules reads as before.
  # H14 (T-16, board 03): the same mark after a rule's name when the agent
  # gave it, its hidden lead saying which of the two it is.
  defp author_mark(assigns) do
    ~H"""
    <%= if @author == :agent do %> <span data-role={@role}>· <span class="visually-hidden"><%= @lead %> </span><%= gettext("Agent") %></span><% end %>
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
       do: RiskLens.observations_of(n, required)

  defp undetermined_reason(%{reason: reason}), do: PolicyRuleLabel.reason(reason)
end
