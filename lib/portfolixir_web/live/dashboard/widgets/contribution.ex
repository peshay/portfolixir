defmodule PortfolixirWeb.Dashboard.Widgets.Contribution do
  @moduledoc """
  The section widget „Beitrag je Position“ `contribution` (I57; Sprint 32
  W1; ADR-0062's amendment of 2026-11-25, point 3; planning board
  `ux-design-2026-11-25-sprint32/02` ①): the contribution table of
  Wealth's tab „Bestände“ (FR-41, ADR-0051 §12), drawn on a dashboard by
  the module Wealth draws it with, `PortfolixirWeb.Portfolio.ContributionTable`.

  Its figures are `Portfolixir.Portfolios.Performance.Contribution.for_view/2`'s,
  the read `GET /api/v1/performance/contribution` and `GET
  /api/v1/views/:view_id/performance/contribution` answer for the same
  parameters (`Portfolixir.Dashboards.Widgets.source_params/3`, then
  `PortfolixirWeb.Api.V1.PeriodParam.resolve/1`), in the first portfolio's
  base currency, as Wealth reads it.

    * **Zeile** — Wealth's table: the ten largest positions, „Alle
      anzeigen“ for the rest, the remainder and the sum row;
    * **L** — the five largest contributions as rows with their bar;
    * **XL** — the eight largest in two columns of four, the start and end
      value under each name;
    * **compact** — the L rows.
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Buckets
  alias Portfolixir.Clock
  alias Portfolixir.Dashboards.Widgets
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Performance.Contribution
  alias PortfolixirWeb.Api.V1.PeriodParam
  alias PortfolixirWeb.Dashboard.Widget
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.Portfolio.ContributionTable

  # The rows a fixed tile shows (board 09's tiles).
  @shown %{"L" => 5, "XL" => 8}

  # -- the read -----------------------------------------------------------------

  @doc """
  The widget's read for the scope `view_id` (`nil`: Everything) over the
  dashboard period `period`: `%{contribution, view_name}`, or `:error`
  when the read refuses. A view that vanished meanwhile reads Everything.
  """
  @spec read(integer() | nil, String.t()) :: map() | :error
  def read(view_id, period) do
    base_currency =
      case Portfolios.first_portfolio() do
        %{base_currency_code: code} -> code
        nil -> "EUR"
      end

    view = view_id && Buckets.get_view(view_id)

    with {:ok, params} <- Widgets.source_params("contribution", period, Clock.today()),
         {:ok, term} <- PeriodParam.resolve(params),
         {:ok, contribution} <-
           Contribution.for_view(view && view.id, period: term, base_currency: base_currency) do
      %{contribution: contribution, view_name: view && view.name}
    else
      _refused -> :error
    end
  end

  # -- the widget ---------------------------------------------------------------

  attr(:item, :map, required: true)
  attr(:period, :string, required: true)
  attr(:card, :any, required: true, doc: "nil while the read runs, :error, or `read/2`'s answer")
  attr(:show_all?, :boolean, default: false)
  attr(:scope_label, :string, default: nil)

  @doc "The widget „Beitrag je Position“ at its size, with its compact form."
  def widget(assigns) do
    contribution = if is_map(assigns.card), do: assigns.card.contribution
    shown = Map.get(@shown, assigns.item.size, 5)

    rows =
      if contribution,
        do: Enum.sort_by(contribution.positions, &Decimal.abs(&1.contribution), {:desc, Decimal}),
        else: []

    assigns =
      assign(assigns,
        id: "dashboard-contribution" <> assigns.item.uid,
        contribution: contribution,
        rows: Enum.take(rows, shown),
        compact_rows: Enum.take(rows, 5),
        hidden: max(length(rows) - shown, 0),
        largest: rows |> Enum.map(&Decimal.abs(&1.contribution)) |> Enum.max(fn -> nil end)
      )

    ~H"""
    <Widget.frame
      id={@id}
      item={@item}
      title={Widgets.title("contribution")}
      scope_label={@scope_label}
      full_href="/portfolio"
      full_label={gettext("Full view →")}
      full_role="contribution-full-view"
    >
      <:info><%= gettext("Contribution = end value − start value − flows + income − costs") %></:info>
      <:info><%= gettext("start value: the close of the day before the period") %></:info>
      <:info>
        <%= gettext("The contribution read over the widget's period, GET /api/v1/performance/contribution with the period's parameters, in the base currency; Wealth's table. Positions and the remainder lines add up to the period's result.") %>
      </:info>
      <:shared>
        <p :if={@card == :error} class="hint" data-role="contribution-widget-failed">
          <%= gettext("Couldn't load the contributions.") %>
        </p>
      </:shared>
      <%= if @item.size == "row" do %>
        <ContributionTable.table
          id={@id <> "-block"}
          toggle_value={@item.uid}
          titled={false}
          labelled_by={@id <> "-title"}
          contribution={@contribution}
          failed?={@card == :error}
          show_all?={@show_all?}
          period_label={Widget.period_label(@period)}
          view_name={view_name(@card)}
        />
      <% else %>
        <p :if={is_nil(@card)} class="section-skeleton" aria-busy="true" data-role="contribution-skeleton"></p>
        <p :if={@contribution && @rows == []} class="hint" data-role="contribution-widget-empty">
          <%= gettext("No position contributed in this period.") %>
        </p>
        <div class={["contribution-widget-rows", "contribution-widget-rows--" <> String.downcase(@item.size)]}>
          <.rows rows={@rows} largest={@largest} size={@item.size} currency={@contribution && @contribution.base_currency} />
        </div>
        <p :if={@hidden > 0} class="hint" data-role="contribution-widget-more">
          <%= ngettext("%{count} more in the list", "%{count} more in the list", @hidden) %>
        </p>
      <% end %>
      <:compact>
        <.rows rows={@compact_rows} largest={@largest} size="L" currency={@contribution && @contribution.base_currency} />
      </:compact>
    </Widget.frame>
    """
  end

  attr(:rows, :list, required: true)
  attr(:largest, :any, required: true)
  attr(:size, :string, required: true)
  attr(:currency, :string, default: nil)

  defp rows(assigns) do
    ~H"""
    <Widget.row
      :for={row <- @rows}
      title={row.name || row.isin || "—"}
      bar_value={row.contribution}
      bar_largest={@largest}
      data-role="contribution-item"
      data-security-id={row.security_id}
    >
      <:name><%= row.name || row.isin || "—" %></:name>
      <:sub :if={@size == "XL"}>
        <%= Format.money(row.start_value) %> → <%= Format.money(row.end_value) %> <%= @currency %>
      </:sub>
      <:figure>
        <span class={sign_class(row.contribution)}><%= Format.signed_decimal(row.contribution, 2) %></span>
      </:figure>
    </Widget.row>
    """
  end

  defp view_name(%{view_name: name}) when is_binary(name), do: name
  defp view_name(_card), do: gettext("Everything")

  defp sign_class(value) do
    case Format.displayed_sign(value, 2) do
      :positive -> "is-positive"
      :negative -> "is-negative"
      _zero -> nil
    end
  end
end
