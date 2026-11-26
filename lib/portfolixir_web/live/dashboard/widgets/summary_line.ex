defmodule PortfolixirWeb.Dashboard.Widgets.SummaryLine do
  @moduledoc """
  The section widget „Kennzahlen-Zeile“ `summary_line` (I57; Sprint 32 W2;
  ADR-0062's amendment of 2026-11-25, point 3; planning board
  `ux-design-2026-11-25-sprint32/02` ②): the summary line that heads
  Wealth's tab „Allokation & Ziele“ (#797), moved here so that one code
  path draws it on Wealth (`line/1`, which `PortfolixirWeb.PortfolioLive`
  renders) and on a dashboard (`widget/1`). It is not „Kennzahlen“
  (`wealth_key_figures`, the tab „Bestände“'s band) nor „Kennzahlen des
  Portfolios“ (the tab „Risiko“'s).

  Its figures: the total incl. cash and the cash quote of the view
  valuation (`Portfolixir.Portfolios.Valuation.for_view/2`, `GET
  /api/v1/valuation`), and the period's TTWROR of the performance read
  (`Portfolixir.Portfolios.Performance.for_view/2`, `GET
  /api/v1/performance` with the period's parameters), both in the first
  portfolio's base currency, as Wealth reads them. While a figure is
  read the line is busy; a failed performance read shows „—“. The line
  links to all key figures on Holdings.

  Its compact form is the line itself, which wraps: one form, drawn once
  (`widget--single-form`).
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Buckets
  alias Portfolixir.Dashboards.Widgets
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Valuation
  alias PortfolixirWeb.Dashboard.Widget
  alias PortfolixirWeb.Dashboard.Widgets.Performance, as: PerformanceWidget
  alias PortfolixirWeb.Format

  # -- the read -------------------------------------------------------------------

  @doc """
  The widget's read, in the dashboard's background task: the view
  valuation of the scope `scope_id` (nil for Everything; a vanished view
  reads Everything) and its performance over the dashboard period
  `period`, both in the first portfolio's base currency. The performance
  is `:error` where its read refuses.
  """
  @spec read(integer() | nil, String.t()) :: map()
  def read(scope_id, period) do
    base_currency =
      case Portfolios.first_portfolio() do
        %{base_currency_code: code} -> code
        nil -> "EUR"
      end

    view = scope_id && Buckets.get_view(scope_id)
    view_id = view && view.id

    case Valuation.for_view(view_id, base_currency: base_currency) do
      {:error, :view_not_found} ->
        read(nil, period)

      valuation ->
        performance =
          case PerformanceWidget.read(view_id, period, base_currency) do
            %{result: result} -> result
            :error -> :error
          end

        %{valuation: valuation, performance: performance, view_id: view_id}
    end
  end

  # -- the line -------------------------------------------------------------------

  @doc """
  Whether the line is busy (UX-DR20): while the valuation or the
  performance is read; a failed performance is not busy.
  """
  @spec busy(map() | nil, map() | nil, boolean()) :: String.t() | nil
  def busy(valuation, performance, failed?) do
    if is_nil(valuation) or (is_nil(performance) and not failed?),
      do: "true",
      else: nil
  end

  attr(:class, :string, default: "workspace-section kpi-summary")
  attr(:valuation, :any, required: true, doc: "nil while it is read")
  attr(:performance, :any, required: true, doc: "nil while it is read or superseded")
  attr(:failed, :boolean, required: true, doc: "whether the performance read failed")
  attr(:period_label, :string, required: true)
  attr(:holdings_href, :string, required: true)

  @doc """
  The summary line: the total incl. cash, the cash quote and the
  period's TTWROR, then the way to all key figures on Holdings.
  """
  def line(assigns) do
    ~H"""
    <%!-- The Allocation tab begins with the allocation; what it needs from
         the band is the reference value and the cash quote — one line,
         with a link back to Holdings that keeps the picked view (#797). --%>
    <section
      class={@class}
      aria-label={gettext("Wealth key figures")}
      aria-busy={busy(@valuation, @performance, @failed)}
      data-role="kpi-summary"
    >
      <span class="kpi-summary__item">
        <%= gettext("Total incl. cash") %>
        <strong :if={@valuation}>
          <%= Format.money(@valuation.total_with_cash) %> <%= @valuation.base_currency %>
        </strong>
        <span :if={is_nil(@valuation)} class="value-skeleton" aria-hidden="true"></span>
      </span>
      <span class="kpi-summary__item">
        <%= gettext("Cash quote") %>
        <strong :if={@valuation}><%= Format.percent(@valuation.cash_quote) %>%</strong>
        <span :if={is_nil(@valuation)} class="value-skeleton" aria-hidden="true"></span>
      </span>
      <span class="kpi-summary__item">
        <%= gettext("TTWROR") %> <%= @period_label %>
        <%!-- #1366 (board 02 ④): while a fresh walk computes over a
             superseded series, the figure is the app's busy
             placeholder, as on Holdings' card, never the old figure
             unmarked (Holdings labels it with its stale banner). --%>
        <strong :if={@performance} class={sign_class(@performance.ttwror)}>
          <%= Format.signed_percent(@performance.ttwror) %>%
        </strong>
        <strong
          :if={is_nil(@performance) and not @failed}
          class="value-slot-pending"
          aria-busy="true"
          data-waits="performance"
        >
          <span class="value-skeleton" aria-hidden="true"></span>
          <span class="recomputing-cue"><span class="spinner"></span> <%= gettext("computing") %></span>
        </strong>
        <strong :if={is_nil(@performance) and @failed} class="stat-empty">—</strong>
      </span>
      <a class="kpi-summary__link" href={@holdings_href}>
        <%= gettext("All key figures → Holdings") %>
      </a>
    </section>
    """
  end

  # #1149: the sign and its colour are decided on the percent as displayed,
  # so a figure that reads zero is unsigned and `is-flat`.
  defp sign_class(value) do
    case Format.displayed_percent_sign(value) do
      :positive -> "is-positive"
      :negative -> "is-negative"
      :zero -> "is-flat"
      nil -> nil
    end
  end

  # -- the widget -----------------------------------------------------------------

  attr(:item, :map, required: true)
  attr(:period, :string, required: true)
  attr(:card, :any, required: true, doc: "nil while the read runs, :error, or `read/2`'s answer")
  attr(:scope_label, :string, default: nil)

  @doc "The widget „Kennzahlen-Zeile“: Wealth's summary line in its frame."
  def widget(assigns) do
    assigns =
      assign(assigns,
        valuation: figure(assigns.card, :valuation),
        performance: figure(assigns.card, :performance),
        failed: assigns.card == :error or match?(%{performance: :error}, assigns.card)
      )

    ~H"""
    <Widget.frame
      id={"dashboard-summary-line" <> @item.uid}
      item={@item}
      title={Widgets.title("summary_line")}
      class="widget--single-form"
      scope_label={@scope_label}
    >
      <:info>
        <%= gettext(
          "The total incl. cash and the cash quote of the view valuation, GET /api/v1/valuation; the TTWROR of the performance read over the widget's period, GET /api/v1/performance; both in the first portfolio's base currency."
        ) %>
      </:info>
      <:shared>
        <.line
          class="kpi-summary"
          valuation={@valuation}
          performance={@performance}
          failed={@failed}
          period_label={Widget.period_label(@period)}
          holdings_href={holdings_href(@item.scope)}
        />
      </:shared>
    </Widget.frame>
    """
  end

  defp figure(%{} = card, key) do
    case Map.get(card, key) do
      %{} = figure -> figure
      _none -> nil
    end
  end

  defp figure(_card, _key), do: nil

  # Holdings' key figures on the widget's scope.
  defp holdings_href(nil), do: "/portfolio"
  defp holdings_href(view_id), do: "/portfolio?" <> URI.encode_query([{"view", view_id}])
end
