defmodule PortfolixirWeb.Dashboard.Widgets.RiskLens do
  @moduledoc """
  The section widgets of Wealth's tab „Risiko“ that read the concentration
  lens and its portfolio metrics (I57; Sprint 32 W4; ADR-0062's amendment
  of 2026-11-25, points 3 and 7; planning board
  `ux-design-2026-11-25-sprint32/02` ②), moved here from
  `PortfolixirWeb.RiskLive` so that one code path draws each section on the
  tab (`metrics/1`, `top_holdings/1`, `hhi/1`, `caps/1` under the
  sections' heads, which the tab keeps) and on a dashboard:

    * **Kennzahlen des Portfolios** `key_figures` (`key_figures_widget/1`;
      Zeile, M): volatility, maximum drawdown, the risk-adjusted return and
      the correlations' card over one year (ADR-0047 §3), each refusing
      below its minimum with what it had and needed; M the first three;
    * **Größte Einzelpositionen** `top_holdings` (`top_holdings_widget/1`;
      Zeile): the Top-N single names with their weight and the generic
      threshold each is above or below;
    * **Klumpenrisiko** `concentration` (`concentration_widget/1`; Zeile,
      S): the HHI with its band on its track;
    * **Anlageklassen-Obergrenzen** `asset_class_limits`
      (`asset_class_limits_widget/1`; Zeile): the caps (none configured on
      the tab, so none to exceed) and the correlations behind a
      disclosure.

  Every figure is `Portfolixir.Portfolios.Risk.for_portfolio/2` for the
  first portfolio and the scope, the read `GET
  /api/v1/portfolios/:portfolio_id/risk?view=` answers (`load/2`, which
  the tab calls too), on the steerable basis. **No verdict** (ADR-0047 §7):
  a threshold or a band is the lens's own arithmetic, said as the
  threshold; nothing recommends or rates.

  Each section's compact form is its own narrow layout: the same markup,
  drawn once (`widget--single-form`).
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Buckets
  alias Portfolixir.Catalog.AssetClasses
  alias Portfolixir.Dashboards.Widgets
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Risk
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Dashboard.Widget
  alias PortfolixirWeb.Format

  # The window the tab reads: the one-year figure is the one a reader
  # compares across portfolios; the API carries all three.
  @window "365d"
  @etf "etf"

  # -- the read -------------------------------------------------------------------

  @doc "The metrics' window the sections draw: one year."
  @spec window() :: String.t()
  def window, do: @window

  @doc """
  The lens of `portfolio_id` for the view `view_id` (nil: Everything); a
  view gone meanwhile reads Everything. The tab's read, and the widgets'.
  """
  @spec load(integer(), integer() | nil) :: map()
  def load(portfolio_id, view_id) do
    case Risk.for_portfolio(portfolio_id, view: view_id) do
      {:error, :view_not_found} -> Risk.for_portfolio(portfolio_id)
      risk -> risk
    end
  end

  @doc """
  The widgets' read, in the dashboard's background task: the lens of the
  first portfolio for the scope `scope_id`, with the lens's shipped
  defaults. `%{state: :none}` without a portfolio.
  """
  @spec read(integer() | nil) :: map()
  def read(scope_id) do
    case Portfolios.first_portfolio() do
      nil ->
        %{state: :none}

      portfolio ->
        view = scope_id && Buckets.get_view(scope_id)
        %{state: :ok, risk: load(portfolio.id, view && view.id), defaults: Risk.defaults()}
    end
  end

  @doc """
  What the metrics' ⓘ says (Sprint 23, Lane I): the gap rule and the
  correlations' rule, method sentences.
  """
  @spec metrics_info(map()) :: [String.t()]
  def metrics_info(risk) do
    [
      gettext("A day without a return base yields no observation, never a zero."),
      if risk.metrics.correlations.leading_names >= 2 do
        ngettext(
          "Correlations convert to %{currency} first and run over the %{count} largest position.",
          "Correlations convert to %{currency} first and run over the %{count} largest positions.",
          risk.metrics.correlations.leading_names,
          currency: risk.base_currency
        )
      else
        gettext("Correlations convert to %{currency} first.", currency: risk.base_currency)
      end
    ]
  end

  @doc "What the caps' ⓘ says."
  @spec caps_info() :: String.t()
  def caps_info, do: gettext("Caps are set per request over the API.")

  # -- the sections -----------------------------------------------------------------

  attr(:risk, :map, required: true)

  @doc """
  The portfolio metrics: volatility, maximum drawdown, the risk-adjusted
  return and the correlations' card, then the basis line.
  """
  def metrics(assigns) do
    assigns = assign(assigns, :window, @window)

    ~H"""
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
          <span class={drawdown_class(m.value)}><%= signed_percent(m.value) %></span><small class="value-suffix">%</small>
        </:value>
        <:sub :let={m}>
          <%!-- #1343 (board 02 ④): a drawdown of exactly 0 is no
               episode; the payload serves no dates for it. --%>
          <%= if m.peak_date do %>
            <%= Format.date(m.peak_date) %> → <%= Format.date(m.trough_date) %> ·
            <%= if m.recovery_date,
              do: gettext("recovered %{date}", date: Format.date(m.recovery_date)),
              else: gettext("not recovered") %>
          <% else %>
            <%= gettext("no decline in the period") %>
          <% end %>
        </:sub>
      </.metric_card>

      <.metric_card
        role="risk-adjusted-return"
        label={gettext("Risk-adjusted return")}
        metric={@risk.metrics.risk_adjusted_return[@window]}
        undefined={gettext("undefined — volatility is 0")}
      >
        <:value :let={m}><%= Format.plain_decimal(m.value, 2) %></:value>
        <:sub :let={m}>
          <%= gettext("risk-free rate %{rate} % · return per unit of risk",
            rate: Format.plain_decimal(Decimal.mult(m.risk_free_rate, 100), 2)
          ) %>
        </:sub>
      </.metric_card>

      <.correlation_card correlations={@risk.metrics.correlations} />
    </div>
    <%!-- E25 S4, F72 (board 11, part 3): the number of leading names
         comes from the answer; it reads in the heading's ⓘ since Sprint
         23's Lane I. --%>
    <p class="summary-basis" data-role="risk-basis">
      <%= gettext(
        "Basis: the flow-adjusted daily return factors of the TTWROR chain, in %{currency}, annualized by √365 — a deposit is not a return.",
        currency: @risk.base_currency
      ) %>
    </p>
    """
  end

  attr(:risk, :map, required: true)
  attr(:defaults, :map, required: true)
  attr(:table_id, :string, default: "risk-top-holdings")

  @doc "The Top-N single names with their weight and generic threshold."
  def top_holdings(assigns) do
    ~H"""
    <%= if @risk.top_holdings == [] do %>
      <p class="empty-state"><%= gettext("No valued position in this view.") %></p>
    <% else %>
      <div class="data-table-wrapper">
        <table class="data-table risk-top-table risk-fit-table" id={@table_id}>
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
              <td class="num"><%= Format.plain_decimal(holding.weight, 1) %> %</td>
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
    """
  end

  attr(:risk, :map, required: true)
  attr(:defaults, :map, required: true)
  attr(:scale, :boolean, default: true, doc: "the scale line under the track")

  @doc "The HHI with its band on its track."
  def hhi(assigns) do
    ~H"""
    <article class="stat stat--compact risk-hhi" data-role="risk-hhi">
      <strong data-band={@risk.hhi.band}>
        <%= Format.plain_decimal(@risk.hhi.value, 0) %>
        <small class="value-suffix"><%= band_label(@risk.hhi.band) %></small>
      </strong>
      <div class="risk-hhi__track" aria-hidden="true">
        <span class="risk-hhi__marker" style={"left: #{hhi_position(@risk.hhi.value)}%"}></span>
      </div>
      <small :if={@scale} class="stat__sub">
        <%= gettext("0 · low below %{low} · %{high} and above concentrated · 10,000",
          low: Format.plain_decimal(@defaults.hhi.low, 0),
          high: Format.plain_decimal(@defaults.hhi.high, 0)
        ) %>
      </small>
    </article>
    """
  end

  attr(:risk, :map, required: true)

  attr(:prefix, :string,
    default: "",
    doc: "the ids' prefix: empty on the tab, the widget's on a dashboard"
  )

  @doc """
  The asset-class caps — none configured on the tab, so none to exceed —
  and the correlations of the largest positions behind a disclosure.
  """
  def caps(assigns) do
    ~H"""
    <%!-- The tab reads the lens with its shipped defaults, and caps are
         opt-in per request (FR9): no cap is ever configured here, so the
         section says so rather than rendering a list that can only be
         empty. --%>
    <p class="empty-state">
      <%= gettext("No cap configured — there is nothing to exceed.") %>
    </p>

    <details class="perf-table-disclosure" id={@prefix <> "risk-correlations"}>
      <summary class="disclosure-summary">
        <AppShell.icon name={:chevron_right} size={12} class="disclosure-chevron" />
        <%= gettext("Show the correlations of the largest positions") %>
      </summary>
      <%!-- The closing act (board 11 part 3, F72): the line read beside
           the pairs says how many leading names they cover, from the
           answer, as the summary's basis line does. --%>
      <p class="hint" data-role="risk-correlations-basis">
        <%= if @risk.metrics.correlations.leading_names >= 2 do %>
          <%= ngettext(
            "Pearson correlation of daily returns over one year between the %{count} largest position, only on days both closed; at least %{required} shared observations per pair.",
            "Pearson correlation of daily returns over one year between the %{count} largest positions, only on days both closed; at least %{required} shared observations per pair.",
            @risk.metrics.correlations.leading_names,
            required: 60
          ) %>
        <% else %>
          <%= gettext("Pearson correlation of daily returns over one year, only on days both closed; at least %{required} shared observations per pair.",
            required: 60
          ) %>
        <% end %>
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
                  do: Format.plain_decimal(pair.value, 2),
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
    """
  end

  # -- the widgets --------------------------------------------------------------------

  attr(:item, :map, required: true)
  attr(:card, :any, required: true, doc: "nil while the read runs, :error, or `read/1`'s answer")
  attr(:scope_label, :string, default: nil)

  @doc "The widget „Kennzahlen des Portfolios“: the metrics, at M the first three."
  def key_figures_widget(assigns) do
    assigns = assign(assigns, :window, @window)

    ~H"""
    <.frame
      kind="key_figures"
      item={@item}
      card={@card}
      scope_label={@scope_label}
      info={if match?(%{state: :ok}, @card), do: metrics_info(@card.risk), else: []}
    >
      <:body :let={%{risk: risk}}>
        <div :if={@item.size != "M"} class="kpi-band" data-role="risk-metrics">
          <.metrics risk={risk} />
        </div>
        <%!-- M (the size rule: the figure with two companions): the three
             figures on the anatomy's headline, each refusing as the tab's
             card does; the dates, the correlations and the basis line are
             the Zeile's. --%>
        <div :if={@item.size == "M"} class="widget-risk-figures" data-role="risk-metrics-m">
          <.m_figure
            label={gettext("Volatility, annualized")}
            role="volatility"
            metric={risk.metrics.volatility[@window]}
            value={&(Format.percent(&1.value) <> " %")}
          />
          <.m_figure
            label={gettext("Max. drawdown")}
            role="max-drawdown"
            metric={risk.metrics.max_drawdown[@window]}
            value={&(signed_percent(&1.value) <> " %")}
            sign={drawdown_sign(risk.metrics.max_drawdown[@window])}
          />
          <.m_figure
            label={gettext("Risk-adjusted return")}
            role="risk-adjusted-return"
            metric={risk.metrics.risk_adjusted_return[@window]}
            value={&Format.plain_decimal(&1.value, 2)}
            undefined={gettext("undefined — volatility is 0")}
          />
        </div>
      </:body>
    </.frame>
    """
  end

  attr(:item, :map, required: true)
  attr(:card, :any, required: true)
  attr(:scope_label, :string, default: nil)

  @doc "The widget „Größte Einzelpositionen“."
  def top_holdings_widget(assigns) do
    ~H"""
    <.frame
      kind="top_holdings"
      item={@item}
      card={@card}
      scope_label={@scope_label}
      info={[
        gettext(
          "Generic thresholds, not policy rules: the lens's shipped lines over each single name's weight on the steerable basis."
        )
      ]}
    >
      <:body :let={%{risk: risk, defaults: defaults}}>
        <.top_holdings
          risk={risk}
          defaults={defaults}
          table_id={"dashboard-top-holdings" <> @item.uid <> "-table"}
        />
      </:body>
    </.frame>
    """
  end

  attr(:item, :map, required: true)
  attr(:card, :any, required: true)
  attr(:scope_label, :string, default: nil)

  @doc "The widget „Klumpenrisiko“: the HHI, at S without its scale line."
  def concentration_widget(assigns) do
    ~H"""
    <.frame
      kind="concentration"
      item={@item}
      card={@card}
      scope_label={@scope_label}
      info={[
        gettext(
          "The Herfindahl index of the single names' weights on the steerable basis, from 0 to 10,000, with the lens's bands."
        )
      ]}
    >
      <:body :let={%{risk: risk, defaults: defaults}}>
        <.hhi risk={risk} defaults={defaults} scale={@item.size != "S"} />
      </:body>
    </.frame>
    """
  end

  attr(:item, :map, required: true)
  attr(:card, :any, required: true)
  attr(:scope_label, :string, default: nil)

  @doc "The widget „Anlageklassen-Obergrenzen“, with the correlations."
  def asset_class_limits_widget(assigns) do
    ~H"""
    <.frame
      kind="asset_class_limits"
      item={@item}
      card={@card}
      scope_label={@scope_label}
      info={[caps_info()]}
    >
      <:body :let={%{risk: risk}}>
        <.caps risk={risk} prefix={"dashboard-asset-class-limits" <> @item.uid <> "-"} />
      </:body>
    </.frame>
    """
  end

  attr(:kind, :string, required: true)
  attr(:item, :map, required: true)
  attr(:card, :any, required: true)
  attr(:scope_label, :string, default: nil)
  attr(:info, :list, default: [], doc: "the ⓘ's lines")
  slot(:body, required: true)

  # The four widgets' one frame: the title, the ⓘ, the scope, the tab as
  # the full view; the read's states, then the section.
  defp frame(assigns) do
    assigns =
      assign(
        assigns,
        :id,
        "dashboard-" <> String.replace(assigns.kind, "_", "-") <> assigns.item.uid
      )

    ~H"""
    <Widget.frame
      id={@id}
      item={@item}
      title={Widgets.title(@kind)}
      class="widget--single-form"
      scope_label={@scope_label}
      full_href={full_href(@item.scope)}
      full_label={gettext("Full view →")}
      full_role={@kind <> "-full-view"}
    >
      <:info :for={line <- @info}><%= line %></:info>
      <:shared>
        <div :if={is_nil(@card)} class="section-skeleton" aria-busy="true" data-role={"#{@kind}-skeleton"}></div>
        <p :if={@card == :error} class="hint" data-role={"#{@kind}-failed"}>
          <%= gettext("Couldn't load the risk figures.") %>
        </p>
        <p :if={@card == %{state: :none}} class="empty-state" data-role={"#{@kind}-none"}>
          <%= gettext("No portfolio yet — risk is measured over holdings, and there are none.") %>
        </p>
        <%= if match?(%{state: :ok}, @card), do: render_slot(@body, @card) %>
      </:shared>
    </Widget.frame>
    """
  end

  # The tab on the widget's scope.
  defp full_href(nil), do: "/risk"
  defp full_href(view_id), do: "/risk?" <> URI.encode_query([{"view", view_id}])

  attr(:label, :string, required: true)
  attr(:role, :string, required: true)
  attr(:metric, :map, required: true)
  attr(:value, :any, required: true, doc: "the metric to its figure's text")
  attr(:sign, :any, default: nil)
  attr(:undefined, :string, default: nil)

  # One figure of M: the metric's value, or below its minimum „nicht
  # berechenbar“ with what it had and needed, never a dash or a number.
  defp m_figure(assigns) do
    ~H"""
    <Widget.figure label={@label} size={:secondary} role={"risk-m-" <> @role} sign={@sign}>
      <%= cond do %>
        <% @metric.insufficient_data -> %><span class="stat-empty"><%= gettext("not computable") %></span>
        <% is_nil(@metric.value) -> %><span class="stat-empty"><%= @undefined %></span>
        <% true -> %><%= @value.(@metric) %>
      <% end %>
      <:sub :if={@metric.insufficient_data}><%= observations_of(@metric.observations, @metric.required) %></:sub>
    </Widget.figure>
    """
  end

  # The drawdown's colour as the tab decides it: a loss, or none at zero.
  defp drawdown_sign(%{value: %Decimal{} = value}),
    do: if(negative?(value), do: :negative, else: nil)

  defp drawdown_sign(_metric), do: nil

  # -- helpers moved from the tab (Sprint 32 W4) --------------------------------------

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
        <strong><%= Format.plain_decimal(@highest.value, 2) %></strong>
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

  @doc """
  "n of required observations": the noun follows the requirement, which is
  never one, so both English forms read the same; the catalogue still owns
  the plural (issue 636).
  """
  @spec observations_of(integer(), integer()) :: String.t()
  def observations_of(count, required) do
    ngettext(
      "%{count} of %{required} observations",
      "%{count} of %{required} observations",
      count,
      required: required
    )
  end

  defp asset_class_label(nil), do: "—"
  defp asset_class_label(code), do: AssetClasses.label(code)

  # Decided on the drawdown as displayed, percentage points with one decimal
  # (`signed_percent/1`; #1149): a drawdown that reads "0,0" is not a loss.
  defp negative?(%Decimal{} = value),
    do: value |> Decimal.mult(100) |> Format.displayed_sign(1) == :negative

  defp negative?(_value), do: false

  # A drawdown reads as a loss, or, where it reads zero, in body ink: no
  # class would leave it the stat card's accent (#1149; the γ closing act,
  # DB1).
  defp drawdown_class(value), do: if(negative?(value), do: "is-negative", else: "is-flat")

  defp signed_percent(%Decimal{} = value),
    do: Format.plain_signed_decimal(Decimal.mult(value, 100), 1)

  defp severity_class("hard"), do: "badge--danger"
  defp severity_class("warn"), do: "badge-warning"
  defp severity_class(_ok), do: "badge--neutral"

  # The lens's own vocabulary, not a verdict: the threshold a weight is above,
  # or the one it is still below.
  defp threshold_label(%{asset_class: @etf, severity: "warn"}, d),
    do: gettext("above %{pct} %", pct: Format.plain_decimal(d.etf.warn, 0))

  defp threshold_label(%{asset_class: @etf}, d),
    do: gettext("below %{pct} %", pct: Format.plain_decimal(d.etf.warn, 0))

  defp threshold_label(%{severity: "hard"}, d),
    do: gettext("above %{pct} %", pct: Format.plain_decimal(d.stock.hard, 0))

  defp threshold_label(%{severity: "warn"}, d),
    do: gettext("above %{pct} %", pct: Format.plain_decimal(d.stock.warn, 0))

  defp threshold_label(_ok, d),
    do: gettext("below %{pct} %", pct: Format.plain_decimal(d.stock.warn, 0))

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
