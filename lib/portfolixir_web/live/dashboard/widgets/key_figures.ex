defmodule PortfolixirWeb.Dashboard.Widgets.KeyFigures do
  @moduledoc """
  The section widget „Kennzahlen“ `wealth_key_figures` (I57; Sprint 32 W1;
  ADR-0062's amendment of 2026-11-25, point 3; plan D-12; planning boards
  `ux-design-2026-11-25-sprint32/02` ① and `06` ①, variant A): Wealth's
  key-figure band of the tab „Bestände“, drawn as the owner picked it on
  board 06 — the total with its split into securities and cash, the
  period's Ergebnis, TTWROR and IRR on one line, and under them the value
  bridge Anfang + Nettoflüsse + Ergebnis = heute with the multiplier.

  **No new figure.** The total, the securities, the cash and the cash
  quote are the view valuation's (ADR-0024),
  `Portfolixir.Portfolios.Valuation.for_view/2`, the read `GET
  /api/v1/valuation` and `GET /api/v1/views/:view_id/valuation` answer; the
  rest is the performance read's over the widget's period,
  `Portfolixir.Portfolios.Performance.for_view/2`, which `GET
  /api/v1/performance` answers for the same parameters
  (`Portfolixir.Dashboards.Widgets.source_params/3`, then
  `PortfolixirWeb.Api.V1.PeriodParam.resolve/1`, as the route reads them).
  Both are read in the first portfolio's base currency, as Wealth reads
  them. The figure functions Wealth's band draws with live here
  (`result/1`, `money_weighted_value/1`, `short_window?/1`), so the band
  and the widget compute each figure by one function.

  **The bridge adds up, or says it does not** (`bridge/1`): its four
  figures are the read's own, each as it reads at two places; where the
  rounded start, flows and result do not sum to the rounded end, the gap
  is drawn beside it, and no figure is moved to hide it. A period that
  has ended ends its bridge „am“ its last day, not „heute“; a window the
  read walked no day of draws no bridge. Where the performance read's end
  value of a window that ends today is not the valuation's total at the
  cent, the footer says so in one line; the total is today's, so a period
  that has ended is never set against it.

    * **Zeile** — board 06's variant A;
    * **S** — the total and its split;
    * **M** — the total and the three returns;
    * **compact** — the total, then the three returns and the bridge as
      rows.
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Buckets
  alias Portfolixir.Clock
  alias Portfolixir.Dashboards.Widgets
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.Valuation
  alias PortfolixirWeb.Api.V1.PeriodParam
  alias PortfolixirWeb.Dashboard.Widget
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.Portfolio.CategoryColors

  # -- the read -----------------------------------------------------------------

  @doc """
  The widget's read for the scope `view_id` (`nil`: Everything) over the
  dashboard period `period`, in the page's background task: `%{valuation,
  performance}`, the performance `:error` when its read refuses. A view
  that vanished meanwhile reads Everything, as the value card does.
  """
  @spec read(integer() | nil, String.t()) :: %{valuation: map(), performance: map() | :error}
  def read(view_id, period) do
    base_currency =
      case Portfolios.first_portfolio() do
        %{base_currency_code: code} -> code
        nil -> "EUR"
      end

    view_id = view_id && Buckets.get_view(view_id) && view_id
    opts = [base_currency: base_currency]

    valuation =
      case Valuation.for_view(view_id, opts) do
        {:error, :view_not_found} -> Valuation.for_view(nil, opts)
        valuation -> valuation
      end

    performance =
      with {:ok, params} <- Widgets.source_params("wealth_key_figures", period, Clock.today()),
           {:ok, term} <- PeriodParam.resolve(params),
           {:ok, result} <- Performance.for_view(view_id, [period: term] ++ opts) do
        result
      else
        _refused -> :error
      end

    %{valuation: valuation, performance: performance}
  end

  # -- the figures, one function each for Wealth's band and the widget ------------

  @doc """
  The period's result, which Wealth's band calls the period's gain: the
  end value minus the start value minus the net external flows, so a
  deposit never reads as performance (it stays consistent with the
  TTWROR beside it).
  """
  @spec result(map()) :: Decimal.t()
  def result(performance) do
    performance.end_value
    |> Decimal.sub(performance.start_value)
    |> Decimal.sub(performance.net_external_flows)
  end

  @doc """
  Whether the window is shorter than a year (ADR-0034 §2): the window
  counts its days inclusively, so a full calendar year still reads as
  annualized IRR.
  """
  @spec short_window?(map()) :: boolean()
  def short_window?(%{start_date: %Date{} = start_date, end_date: %Date{} = end_date}),
    do: Date.diff(end_date, start_date) + 1 < 365

  def short_window?(_performance), do: false

  @doc "The money-weighted figure: the IRR, or the period MWR under a year."
  @spec money_weighted_value(map()) :: Decimal.t() | nil
  def money_weighted_value(performance) do
    if short_window?(performance), do: performance.mwr, else: performance.irr
  end

  @typedoc "The value bridge's figures, each as it reads at two places, and its gap."
  @type bridge :: %{
          start: Decimal.t(),
          flows: Decimal.t(),
          result: Decimal.t(),
          end: Decimal.t(),
          gap: Decimal.t() | nil
        }

  @doc """
  The value bridge Anfang + Nettoflüsse + Ergebnis = heute from the
  performance read's own figures, each rounded to the cent as it is
  displayed: `gap` is the rounded end minus the sum of the other three,
  `nil` when they add up. No figure is adjusted to close it.
  """
  @spec bridge(map()) :: bridge()
  def bridge(performance) do
    start = cents(performance.start_value)
    flows = cents(performance.net_external_flows)
    result = cents(result(performance))
    finish = cents(performance.end_value)
    gap = Decimal.sub(finish, start |> Decimal.add(flows) |> Decimal.add(result))

    %{
      start: start,
      flows: flows,
      result: result,
      end: finish,
      gap: if(Decimal.eq?(gap, 0), do: nil, else: gap)
    }
  end

  defp cents(%Decimal{} = value), do: Decimal.round(value, 2)

  # -- the widget ---------------------------------------------------------------

  attr(:item, :map, required: true)
  attr(:period, :string, required: true)
  attr(:card, :any, required: true, doc: "nil while the read runs, :error, or `read/2`'s answer")
  attr(:scope_label, :string, default: nil)

  @doc "The widget „Kennzahlen“ at its size, with its compact form."
  def widget(assigns) do
    {valuation, performance} =
      case assigns.card do
        %{valuation: %{} = valuation, performance: %{} = performance} -> {valuation, performance}
        %{valuation: %{} = valuation} -> {valuation, nil}
        _none -> {nil, nil}
      end

    assigns =
      assign(assigns,
        valuation: valuation,
        performance: performance,
        label: Widget.period_label(assigns.period),
        # A window the read walked no day of (start_date nil: before the
        # first booking, or nothing booked yet) has no bridge to draw.
        bridge: walked?(performance) && bridge(performance),
        apart: performance && valuation && apart(performance, valuation, Clock.today())
      )

    ~H"""
    <Widget.frame
      id={"dashboard-wealth-key-figures" <> @item.uid}
      item={@item}
      title={Widgets.title("wealth_key_figures")}
      class="widget-key-figures"
      scope_label={@scope_label}
      full_href="/portfolio"
      full_label={gettext("Full view →")}
      full_role="key-figures-full-view"
    >
      <:info>
        <%= gettext("The total incl. cash, the securities, the cash and the cash quote: the view valuation, GET /api/v1/valuation and GET /api/v1/views/:id/valuation. The cash is every valued cash account's, reserves and credit lines included (total_cash); the cash quote is deployable cash ÷ (securities + deployable cash), a reserve or a credit line left out of it.") %>
      </:info>
      <:info>
        <%= gettext("Result, TTWROR and IRR: the performance read over the widget's period, GET /api/v1/performance with the period's parameters. Result: end value − start value − net external flows. TTWROR time-weighted, not annualized; IRR money-weighted and annualized, under a year the period MWR, not annualized.") %>
      </:info>
      <:info>
        <%= gettext("The bridge: start value + net flows + result = end value of the same read, each figure rounded to the cent; where the rounded figures do not add up, the gap is shown and no figure is changed. Multiple: end value ÷ invested capital (start value + net flows).") %>
      </:info>
      <:warning :if={@apart} role="key-figures-apart">
        <%= gettext("Today by the performance read %{end}, the total %{total}: %{gap} apart",
          end: Format.money(@performance.end_value),
          total: Format.money(@valuation.total_with_cash),
          gap: Format.signed_decimal(@apart, 2)
        ) %>
      </:warning>
      <:shared>
        <p :if={is_nil(@card)} class="section-skeleton" aria-busy="true" data-role="key-figures-skeleton"></p>
        <p :if={@card == :error} class="hint" data-role="key-figures-failed">
          <%= gettext("Couldn't load the key figures.") %>
        </p>
      </:shared>
      <div :if={@valuation} class={["key-figures", "key-figures--" <> String.downcase(@item.size)]}>
        <div class="key-figures__total">
          <%!-- At S the secondary size: the total and its currency fit
               the 3-column tile in every font (the anatomy walk). --%>
          <.total valuation={@valuation} size={if @item.size == "S", do: :secondary, else: :m} />
          <.split :if={@item.size != "M"} valuation={@valuation} />
        </div>
        <div :if={@item.size != "S"} class="key-figures__returns">
          <.returns performance={@performance} label={@label} />
        </div>
      </div>
      <.bridge_line
        :if={@bridge && @item.size == "row"}
        bridge={@bridge}
        currency={@performance.base_currency}
        start_date={@performance.start_date}
        end_date={@performance.end_date}
        multiple={@performance.wealth_multiple}
      />
      <:compact>
        <%= if @valuation do %>
          <%!-- A row, whose figure is never cut: in the compact class two S
               stand side by side. --%>
          <Widget.row title={pgettext("key figures", "Total value")} data-compact-role="key-figures-total">
            <:name><%= pgettext("key figures", "Total value") %></:name>
            <:figure><%= Format.money(@valuation.total_with_cash) %> <%= @valuation.base_currency %></:figure>
          </Widget.row>
          <.split valuation={@valuation} />
          <%= if @performance do %>
            <Widget.row title={gettext("Result")} data-compact-role="key-figures-result">
              <:name><%= gettext("Result") %> · <%= @label %></:name>
              <:figure><span class={sign_class(result(@performance))}><%= Format.signed_decimal(result(@performance), 2) %></span></:figure>
            </Widget.row>
            <Widget.row title={gettext("TTWROR")} data-compact-role="key-figures-ttwror">
              <:name><%= gettext("TTWROR") %> · <%= @label %></:name>
              <:figure><span class={sign_class(@performance.ttwror)}><%= percent(@performance.ttwror) %></span></:figure>
            </Widget.row>
            <Widget.row title={money_weighted_label(@performance)} data-compact-role="key-figures-irr">
              <:name><%= money_weighted_label(@performance) %> · <%= @label %></:name>
              <:figure><span class={sign_class(money_weighted_value(@performance))}><%= percent(money_weighted_value(@performance)) %></span></:figure>
            </Widget.row>
          <% end %>
        <% end %>
      </:compact>
    </Widget.frame>
    """
  end

  attr(:valuation, :map, required: true)
  attr(:size, :atom, required: true)

  defp total(assigns) do
    ~H"""
    <Widget.figure label={pgettext("key figures", "Total value")} size={@size} role="kf-total">
      <%= Format.money(@valuation.total_with_cash) %>
      <:unit><%= @valuation.base_currency %></:unit>
    </Widget.figure>
    """
  end

  attr(:valuation, :map, required: true)

  # The total's split into securities and cash: the legend names both
  # amounts, the cash every valued account's (total_cash), and then the
  # cash quote, named, since it counts the deployable share only; the bar
  # draws that quote.
  defp split(assigns) do
    {securities, cash} = share(assigns.valuation.cash_quote)
    assigns = assign(assigns, securities_share: securities, cash_share: cash)

    ~H"""
    <div class="key-figures__split">
      <span class="key-figures__bar" aria-hidden="true">
        <span class="key-figures__bar-securities" style={"width: #{@securities_share}%"}></span><span
          class="key-figures__bar-cash"
          style={"width: #{@cash_share}%; background: #{CategoryColors.cash()}"}
        ></span>
      </span>
      <p class="key-figures__legend">
        <span data-role="kf-securities"><span class="key-figures__swatch key-figures__swatch--securities" aria-hidden="true"></span><%= gettext("Securities") %> <b class="num"><%= Format.money(@valuation.total_value) %></b></span>
        <span data-role="kf-cash"><span class="key-figures__swatch" style={"background: #{CategoryColors.cash()}"} aria-hidden="true"></span><%= gettext("Cash") %> <b class="num"><%= Format.money(@valuation.total_cash) %></b> · <%= gettext("Cash quote") %> <%= Format.percent(@valuation.cash_quote) %> %</span>
      </p>
    </div>
    """
  end

  # The cash quote as the bar's share, in percent of the track, 0 to 100,
  # and the securities' share beside it; a CSS width, never a figure.
  defp share(%Decimal{} = quote) do
    cash =
      quote
      |> Decimal.mult(100)
      |> Decimal.max(Decimal.new(0))
      |> Decimal.min(Decimal.new(100))
      |> Decimal.round(1)

    {Decimal.to_string(Decimal.sub(100, cash), :normal), Decimal.to_string(cash, :normal)}
  end

  defp share(_quote), do: {"100", "0"}

  attr(:performance, :map, default: nil)
  attr(:label, :string, required: true)

  defp returns(assigns) do
    ~H"""
    <Widget.figure label={gettext("Result") <> " · " <> @label} size={:secondary} role="kf-result" sign={@performance && result(@performance)}>
      <span data-role="kf-result-value"><%= if @performance, do: Format.signed_decimal(result(@performance), 2), else: "—" %></span>
      <:unit :if={@performance}><%= @performance.base_currency %></:unit>
      <:sub><%= gettext("after inflows and outflows") %></:sub>
    </Widget.figure>
    <Widget.figure label={gettext("TTWROR") <> " · " <> @label} size={:secondary} role="kf-ttwror" sign={@performance && @performance.ttwror}>
      <span data-role="kf-ttwror-value"><%= if @performance, do: percent(@performance.ttwror), else: "—" %></span>
      <:sub><%= gettext("time-weighted") %></:sub>
    </Widget.figure>
    <Widget.figure
      label={money_weighted_label(@performance) <> " · " <> @label}
      size={:secondary}
      role="kf-irr"
      sign={@performance && money_weighted_value(@performance)}
    >
      <span data-role="kf-irr-value"><%= if @performance, do: percent(money_weighted_value(@performance)), else: "—" %></span>
      <:sub><%= money_weighted_sub(@performance) %></:sub>
    </Widget.figure>
    """
  end

  attr(:bridge, :map, required: true)
  attr(:currency, :string, required: true)
  attr(:start_date, :any, required: true)

  attr(:end_date, :any,
    default: nil,
    doc: "the read's end_date: a day before today names the end by its date"
  )

  attr(:multiple, :any, required: true)

  @doc """
  The value bridge under the figures (board 06 ① A): Anfang with its date
  + Nettoflüsse + Ergebnis = heute, the multiplier at the right; where the
  rounded figures do not add up, the gap beside them (`bridge/1`). A
  period that has ended (prev_year, a past quarter, `year:YYYY`, a saved
  period with its `to`) ends on its last day, so its end reads „am“ that
  day, never „heute“.
  """
  def bridge_line(assigns) do
    assigns = assign(assigns, :end_label, end_label(assigns.end_date, Clock.today()))

    ~H"""
    <p class="key-figures__bridge" data-role="key-figures-bridge">
      <span data-role="bridge-start"><%= gettext("Start %{date}", date: Format.date(@start_date)) %> <b class="num"><%= Format.money(@bridge.start) %></b></span>
      <span class="key-figures__op" aria-hidden="true">+</span>
      <span data-role="bridge-flows"><%= gettext("Net flows") %> <b class="num"><%= Format.signed_decimal(@bridge.flows, 2) %></b></span>
      <span class="key-figures__op" aria-hidden="true">+</span>
      <span data-role="bridge-result"><%= gettext("Result") %> <b class={["num", sign_class(@bridge.result)]}><%= Format.signed_decimal(@bridge.result, 2) %></b></span>
      <span class="key-figures__op" aria-hidden="true">=</span>
      <span data-role="bridge-end"><%= @end_label %> <b class="num"><%= Format.money(@bridge.end) %></b> <%= @currency %></span>
      <span :if={@bridge.gap} class="key-figures__gap" data-role="bridge-gap">
        <%= gettext("⚠ rounding gap %{gap}: each figure is rounded to the cent, none is changed",
          gap: Format.signed_decimal(@bridge.gap, 2)
        ) %>
      </span>
      <span :if={@multiple} class="key-figures__multiple" data-role="bridge-multiple"><%= gettext("Multiple") %> <b class="num">×<%= Format.plain_decimal(@multiple, 2) %></b></span>
    </p>
    """
  end

  defp walked?(%{start_date: %Date{}}), do: true
  defp walked?(_performance), do: false

  # The bridge's end: „heute“ for a period that ends today, else the day
  # the period ended.
  defp end_label(%Date{} = end_date, today) do
    if Date.before?(end_date, today),
      do: gettext("on %{date}", date: Format.date(end_date)),
      else: gettext("today")
  end

  defp end_label(_none, _today), do: gettext("today")

  # The performance read's end value against the valuation's total, at the
  # cent: the difference, or nil where they agree. The valuation is
  # today's, so only a walked window that ends today is set against it; a
  # period that has ended ends on another day's value, and a window with
  # nothing in it (start_date nil) has no value of its own.
  defp apart(%{start_date: %Date{}, end_date: today} = performance, valuation, today) do
    gap = Decimal.sub(cents(performance.end_value), cents(valuation.total_with_cash))
    if Decimal.eq?(gap, 0), do: nil, else: gap
  end

  defp apart(_performance, _valuation, _today), do: nil

  defp money_weighted_label(%{} = performance) do
    if short_window?(performance), do: gettext("MWR"), else: gettext("IRR")
  end

  defp money_weighted_label(_none), do: gettext("IRR")

  defp money_weighted_sub(%{} = performance) do
    if short_window?(performance),
      do: gettext("money-weighted, not annualized"),
      else: gettext("money-weighted, p. a.")
  end

  defp money_weighted_sub(_none), do: gettext("money-weighted, p. a.")

  defp percent(%Decimal{} = value), do: Format.signed_percent(value) <> "%"
  defp percent(_none), do: "—"

  defp sign_class(value) do
    case Format.displayed_sign(value, 2) do
      :positive -> "is-positive"
      :negative -> "is-negative"
      _zero -> nil
    end
  end
end
