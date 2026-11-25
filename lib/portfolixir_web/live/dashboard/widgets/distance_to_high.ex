defmodule PortfolixirWeb.Dashboard.Widgets.DistanceToHigh do
  @moduledoc """
  The widget „Abstand zum Hoch“ `distance_to_high` (I61; Sprint 32 S5;
  planning boards `ux-design-2026-11-25-sprint32/03` ① and `05`, the note
  „Ohne neue Zahl“): the securities of the widget's scope with their
  distance to the 52-week high and their largest drawdown, sorted by the
  distance, the farthest below its high first.

  Its figures are the per-security metrics read (ADR-0047; FR-39),
  `Portfolixir.Catalog.SecurityMetrics.for_security/2`, which `GET
  /api/v1/securities/:security_id/metrics` answers: `distance_to_extremes`
  (the 52-week high, its date, `distance_to_high_pct`) and `max_drawdown`
  over its `365d` window, each security in its own currency. The
  securities are the scope's held today — a view's
  (`Portfolixir.Ledger.HeldSecurities.in_view/1`), else every depot's
  (`held_ids/0`), the rule the crash rankings and the news digest read a
  view's holdings by. A security whose read refuses (a short series) is
  listed last, its figures „—“, never a zero.

  Level (a) of the scope ladder: it reports the distance, and says nothing
  about it — no „günstig“, no „Kaufchance“, no ordering by anything but the
  figure (`test/invariants/metrics_carry_no_verdict_test.exs` walks its read
  and its words). Its ⓘ is the read's computation basis.
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Catalog.SecurityMetrics
  alias Portfolixir.Dashboards.Widgets
  alias Portfolixir.Ledger.HeldSecurities
  alias PortfolixirWeb.Dashboard.Widget
  alias PortfolixirWeb.Format

  # The rows a fixed tile shows: L four, XL eight (board 09's tiles).
  @shown %{"L" => 5, "XL" => 8}

  # -- the read -----------------------------------------------------------------

  @doc """
  The widget's read for the scope `view_id` (`nil`: every depot): one row
  per security held today, `%{security_id, name, currency, high, high_date,
  distance, drawdown}`, the figures the metrics read answers (`nil` where
  it refuses), sorted by `distance` ascending, `nil` last, then by name.
  """
  @spec read(integer() | nil) :: %{state: :ok, rows: [map()]} | %{state: :no_view}
  def read(view_id) do
    case held(view_id) do
      {:ok, ids} ->
        rows =
          ids
          |> Enum.flat_map(&row/1)
          |> Enum.sort(&before?/2)

        %{state: :ok, rows: rows}

      {:error, :view_not_found} ->
        %{state: :no_view}
    end
  end

  # The farthest below its high first; a refused distance last; then by name.
  defp before?(%{distance: nil} = a, %{distance: nil} = b), do: a.name <= b.name
  defp before?(%{distance: nil}, _b), do: false
  defp before?(_a, %{distance: nil}), do: true

  defp before?(a, b) do
    case Decimal.compare(a.distance, b.distance) do
      :lt -> true
      :gt -> false
      :eq -> a.name <= b.name
    end
  end

  defp held(nil), do: {:ok, HeldSecurities.held_ids()}
  defp held(view_id), do: HeldSecurities.in_view(view_id)

  defp row(id) do
    case SecurityMetrics.for_security(id) do
      {:ok, payload} ->
        extremes = payload.metrics.distance_to_extremes
        drawdown = Map.fetch!(payload.metrics.max_drawdown, "365d")

        [
          %{
            security_id: id,
            name: payload.security_name,
            currency: payload.currency_code,
            high: extremes.high && extremes.high.close,
            high_date: extremes.high && extremes.high.date,
            distance: extremes.distance_to_high_pct,
            drawdown: drawdown.value
          }
        ]

      {:error, :not_found} ->
        []
    end
  end

  # -- the widget ---------------------------------------------------------------

  attr(:item, :map, required: true)
  attr(:card, :any, required: true, doc: "nil while the read runs, :error, or `read/1`'s answer")
  attr(:scope_label, :string, default: nil)

  @doc "The widget „Abstand zum Hoch“ with its compact form."
  def widget(assigns) do
    ready = match?(%{state: :ok}, assigns.card)
    shown = Map.get(@shown, assigns.item.size, 5)
    rows = if ready, do: assigns.card.rows, else: []

    assigns =
      assign(assigns,
        ready: ready,
        rows: Enum.take(rows, shown),
        hidden: max(length(rows) - shown, 0)
      )

    ~H"""
    <Widget.frame
      id={"dashboard-distance" <> @item.uid}
      item={@item}
      title={Widgets.title("distance_to_high")}
      scope_label={@scope_label}
      full_href="/securities"
      full_label={gettext("Securities →")}
      full_role="distance-securities"
    >
      <:info>
        <%= gettext("Distance: the latest close against the highest close of the last 365 days, latest ÷ high − 1. Largest drawdown: the deepest fall from a running peak within the same 365 days. Each from the security's own stored closes, split-adjusted, in its own currency; a day without a close is skipped, never filled. The per-security metrics read, GET /api/v1/securities/:id/metrics.") %>
      </:info>
      <:info>
        <%= gettext("The securities the view holds today; a figure that needs more closes than are stored reads —. Sorted by the distance; it states where a price stands, nothing more.") %>
      </:info>
      <:shared>
        <p :if={is_nil(@card)} class="section-skeleton" aria-busy="true" data-role="distance-skeleton"></p>
        <p :if={@card == :error or match?(%{state: :no_view}, @card)} class="hint" data-role="distance-failed">
          <%= gettext("Couldn't load the distances.") %>
        </p>
        <p :if={@ready and @rows == []} class="hint" data-role="distance-empty">
          <%= gettext("No security held in this view.") %>
        </p>
      </:shared>
      <table :if={@rows != []} class="data-table widget-distance-table" data-role="distance-table">
        <thead>
          <tr>
            <th scope="col"><%= gettext("Security") %></th>
            <th scope="col" class="num"><%= gettext("52-week high") %></th>
            <th scope="col" class="num"><%= gettext("Distance") %></th>
            <th scope="col" class="num"><%= gettext("Largest drawdown") %></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={row <- @rows} data-role="distance-row" data-security-id={row.security_id}>
            <th scope="row"><bdi><%= row.name %></bdi></th>
            <td class="num" data-role="distance-high"><%= money(row.high, row.currency) %></td>
            <td class={["num", sign_class(row.distance)]} data-role="distance-value"><%= percent(row.distance) %></td>
            <td class={["num", sign_class(row.drawdown)]} data-role="distance-drawdown"><%= percent(row.drawdown) %></td>
          </tr>
        </tbody>
      </table>
      <p :if={@hidden > 0} class="hint" data-role="distance-more">
        <%= ngettext("%{count} more in the list", "%{count} more in the list", @hidden) %>
      </p>
      <:compact>
        <Widget.row
          :for={row <- @rows}
          href={"/securities/#{row.security_id}"}
          data-compact-role="distance-row"
          data-security-id={row.security_id}
        >
          <:name><%= row.name %></:name>
          <:sub><%= gettext("Largest drawdown %{value}", value: percent(row.drawdown)) %></:sub>
          <:figure><span class={sign_class(row.distance)}><%= percent(row.distance) %></span></:figure>
        </Widget.row>
      </:compact>
    </Widget.frame>
    """
  end

  defp money(nil, _currency), do: "—"
  defp money(%Decimal{} = value, currency), do: Format.money(value) <> " " <> currency

  @doc false
  # A ratio as a signed percent, the dashboard's one format (0.05 is +5,0%).
  def percent(%Decimal{} = ratio), do: Format.signed_percent(ratio) <> "%"
  def percent(_none), do: "—"

  defp sign_class(value) do
    case Format.displayed_percent_sign(value) do
      :positive -> "is-positive"
      :negative -> "is-negative"
      :zero -> "is-flat"
      _none -> nil
    end
  end
end
