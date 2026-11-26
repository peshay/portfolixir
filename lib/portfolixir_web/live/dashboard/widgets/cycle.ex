defmodule PortfolixirWeb.Dashboard.Widgets.Cycle do
  @moduledoc """
  The widget „Bitcoin-Zyklus“ `bitcoin_cycle` (ADR-0060 §11; ADR-0062
  §12; Sprint 31 closing act, DS5; Sprint 32 L2 and L3, board
  `ux-design-2026-11-25-sprint32/07` ③ and 09 ③).

  At L the card „‹Name›-Zyklus“ per security with the cycle view: the
  next low's and the next top's windows, price ranges, states and parts,
  each security's name a sub-line, the frame's title the heading. At XL
  the first security's chart beside the card, as its page draws it on the
  range „Zyklus“: the stored closes from three months before the last
  confirmed halving to four months after the later band, on a logarithmic
  axis, with the cycle bands and the default lines (`CycleChart`), the
  shared chart (`SecurityChart`). Every figure is the cycles read
  `GET /api/v1/securities/:id/cycles` answers and the security's stored
  closes; the sentence that the band is no forecast stands behind ⓘ.
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Dashboards.Widgets
  alias PortfolixirWeb.Components.CycleChart
  alias PortfolixirWeb.Components.SecurityChart
  alias PortfolixirWeb.Dashboard.Widget
  alias PortfolixirWeb.PrivacyMode

  @doc """
  The closes the XL chart draws, read once on the page's mount: the first
  security's adjusted closes over its cycle range, `nil` without a
  security with the view.
  """
  @spec closes([map()]) ::
          %{security_id: integer(), quotes: [map()], range: {Date.t(), Date.t()}} | nil
  def closes([payload | _rest]) do
    case CycleChart.cycle_range(payload) do
      {from, to} ->
        %{
          security_id: payload.security_id,
          quotes: Quotes.adjusted_range(payload.security_id, from, to),
          range: {from, to}
        }

      nil ->
        nil
    end
  end

  def closes(_none), do: nil

  attr(:item, :map, required: true)
  attr(:views, :list, required: true, doc: "the cycles reads of the securities with the view")
  attr(:closes, :any, default: nil, doc: "`closes/1`, for the XL chart")
  attr(:href, :any, required: true, doc: "a payload's chart link, a function")

  @doc "The widget at its size."
  def widget(assigns) do
    assigns =
      assign(assigns,
        chart:
          assigns.item.size == "XL" and is_map(assigns.closes) and
            length(assigns.closes.quotes) > 1
      )

    ~H"""
    <%!-- S29 H8 (ADR-0060 §11): the card „‹Name›-Zyklus“ per security
         with the cycle view, each its own read; its compact form is the
         card's list itself, which is already one event per line. --%>
    <%!-- Sprint 31 closing act, DS5 (board 02 ⑤): the frame's title is
         the widget's heading, each security's name a sub-line, and the
         first one's chart the footer's „Ganze Ansicht →“. --%>
    <Widget.frame
      id={"dashboard-cycles" <> @item.uid}
      item={@item}
      title={Widgets.title("bitcoin_cycle")}
      class="widget--single-form"
      full_href={@href.(List.first(@views))}
      full_label={gettext("Full view →")}
    >
      <:info>
        <%= gettext(
          "The range the stored cycles give from the current anchors, with its n and both ends: not a forecast."
        ) %>
      </:info>
      <:shared>
        <div class={["widget-cycle", @chart && "widget-cycle--chart"]}>
          <%!-- Sprint 32 L3 (board 09 ③): XL draws the chart the
               security's page draws on the range „Zyklus“. --%>
          <div :if={@chart} class="widget-cycle__chart" data-role="cycle-widget-chart">
            <SecurityChart.chart
              quotes={@closes.quotes}
              show_transactions?={false}
              log_scale?={not PrivacyMode.on?()}
              percent_mode?={PrivacyMode.on?()}
              cycles={%{payload: hd(@views), lines: CycleChart.default_lines()}}
              axis_from={elem(@closes.range, 0)}
              axis_to={elem(@closes.range, 1)}
              currency_code={hd(@views).currency_code}
              price_axis?={true}
              aria_label={gettext("%{name} cycle", name: hd(@views).security_name)}
            />
          </div>
          <div class="widget-cycle__cards">
            <CycleChart.card
              :for={payload <- @views}
              payload={payload}
              href={@href.(payload)}
              in_widget
              linked={length(@views) > 1}
            />
          </div>
        </div>
        <p :if={@views == []} class="hint" data-role="cycles-empty">
          <%= gettext("No security shows the cycle view yet.") %>
        </p>
      </:shared>
    </Widget.frame>
    """
  end
end
