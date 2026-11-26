defmodule PortfolixirWeb.Dashboard.Widgets.SnapshotComparison do
  @moduledoc """
  The section widget „Vergleich gegen einen Snapshot“ `snapshot_comparison`
  (I57; Sprint 32 W3; ADR-0062's amendment of 2026-11-25, points 3 and 7;
  planning board `ux-design-2026-11-25-sprint32/02` ②): the comparison
  that heads Wealth's tab „Snapshots“ (#796; ADR-0027), moved here so that
  one code path draws it on the tab (`body/1` under the section's head,
  which `PortfolixirWeb.SnapshotsLive` renders, with `method_lines/0`
  behind its ⓘ) and on a dashboard (`widget/1`).

  Every figure is `Portfolixir.Portfolios.SnapshotComparison.for_snapshot/2`
  for the snapshot compared in the first portfolio, the read `GET
  /api/v1/portfolios/:portfolio_id/snapshots/:id/comparison` answers: the
  real TTWROR since the as-of date, the frozen holdings' buy-and-hold
  return, the transaction costs since and whether the changes earned them
  back (only when trades cost something), the positions left out, and
  both series as the chart and its table. The snapshot compared is the
  newest of `GET /api/v1/snapshots` until one is picked: on the tab by its
  address, on a dashboard in the widget „Snapshot-Liste“, for the page's
  life. A snapshot is made, and deleted, on the tab (ADR-0022's amendment
  of 2026-11-21, point 3).

  Its compact form is the section's own narrow layout: the same markup,
  drawn once (`widget--single-form`).
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Buckets
  alias Portfolixir.Dashboards.Widgets
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.SnapshotComparison
  alias Portfolixir.Portfolios.Snapshots
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Components.SecurityChart
  alias PortfolixirWeb.Dashboard.Widget
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.PrivacyMode
  alias PortfolixirWeb.StoredText

  # -- the read -------------------------------------------------------------------

  @doc """
  The widget's read, in the dashboard's background task: the comparison of
  the snapshot `selected` (an id), or of the newest one when it is nil or
  no longer stored, in the first portfolio, with the name of the
  snapshot's view. `%{state: :none}` without a snapshot or a portfolio,
  `:error` when the comparison refuses.
  """
  @spec read(integer() | nil) :: map() | :error
  def read(selected) do
    snapshots = Snapshots.list_snapshots()

    with %{} = snapshot <- Enum.find(snapshots, &(&1.id == selected)) || List.first(snapshots),
         %{id: portfolio_id} <- Portfolios.first_portfolio() do
      case SnapshotComparison.for_snapshot(snapshot, portfolio_id) do
        {:ok, comparison} ->
          %{state: :ok, comparison: comparison, view_name: view_name(snapshot.view_id)}

        {:error, _reason} ->
          :error
      end
    else
      _none -> %{state: :none}
    end
  end

  defp view_name(nil), do: nil

  defp view_name(view_id) do
    case Buckets.get_view(view_id) do
      %{name: name} -> name
      nil -> nil
    end
  end

  @doc """
  What the comparison's ⓘ says (I1, board ux-design-2026-11-03-sprint23-i1,
  Snapshots ①): the cost definition and the limitation, method true of any
  comparison.
  """
  @spec method_lines() :: [String.t()]
  def method_lines do
    [
      gettext(
        "Transaction costs = fees and taxes booked on trades since then; standalone fees, taxes and dividend withholding stay inside the return on both sides"
      ),
      gettext(
        "The comparison is gross and price development only — dividends are not yet included."
      )
    ]
  end

  # -- the section ------------------------------------------------------------------

  attr(:prefix, :string,
    default: "",
    doc: "the ids' prefix: empty on the tab, the widget's on a dashboard"
  )

  attr(:comparison, :map, required: true)

  @doc """
  The comparison's body: the key figures, the notes, the chart with its
  legend, basis line and table, or a line saying there is nothing to
  compare yet.
  """
  def body(assigns) do
    ~H"""
    <%!-- The ADR-0027 figures: real and frozen always; the cost group
         (amendment §4, #708, review-blocking) only when trades cost
         something, and then all of it — the pre-cost figure is never
         rendered alone, because on its own it flatters. --%>
    <div class="grid" role="group" aria-label={gettext("Comparison key figures")}>
      <article class="stat" data-role="kpi-real">
        <span><%= gettext("Real (TTWROR since the as-of date)") %></span>
        <%= if @comparison.real_ttwror do %>
          <strong class={sign_class(@comparison.real_ttwror)}>
            <%= signed_percent(@comparison.real_ttwror) %>%
          </strong>
        <% else %>
          <%!-- Not-computable: quiet muted dash, never at value
               weight ({components.value-slot}.not-computable). --%>
          <span class="stat-empty">—</span>
        <% end %>
        <small class="hint"><%= gettext("net, all costs included") %></small>
      </article>
      <article class="stat" data-role="kpi-frozen">
        <span><%= gettext("Frozen (hold)") %></span>
        <%= if @comparison.snapshot_return do %>
          <strong class={sign_class(@comparison.snapshot_return)}>
            <%= signed_percent(@comparison.snapshot_return) %>%
          </strong>
        <% else %>
          <span class="stat-empty">—</span>
        <% end %>
        <small class="hint">
          <%= PrivacyMode.html(gettext(
            "Buy-and-hold of the holdings frozen on %{date}: %{then} → %{today} %{currency}",
            date: Format.date(@comparison.as_of),
            then: Format.money(@comparison.as_of_value),
            today: Format.money(@comparison.current_value),
            currency: @comparison.base_currency
          )) %>
        </small>
      </article>
      <div
        :if={transaction_costs?(@comparison)}
        id={@prefix <> "comparison-costs"}
        class="kpi-group"
        role="group"
        aria-label={gettext("Transaction costs since the snapshot")}
      >
        <article class="stat">
          <span><%= gettext("Real before transaction costs") %></span>
          <strong
            class={sign_class(@comparison.real_ttwror_before_costs)}
            data-role="pre-cost-return"
          >
            <%= signed_percent(@comparison.real_ttwror_before_costs) %>%
          </strong>
          <small class="hint"><%= gettext("fees and taxes on trades excluded") %></small>
        </article>
        <article class="stat">
          <span><%= gettext("Transaction costs") %></span>
          <strong data-role="transaction-costs">
            <%!-- #1321: a text space before the currency. --%>
            <%= Format.money(@comparison.transaction_costs) %> <small class="value-suffix"><%= @comparison.base_currency %></small>
          </strong>
          <small class="hint" data-role="cost-recovery">
            <%= gettext("Earned back?") %> <%= recovery_label(@comparison.cost_recovery) %>
          </small>
        </article>
      </div>
    </div>

    <%!-- Findings about this comparison as data notes (UX-DR17), one
         role="status" region around the list — never one per note. --%>
    <div class="comparison-notes" role="status">
      <%!-- I1 (board ux-design-2026-11-03-sprint23-i1, Snapshots ③
           ⑧): the note names positions left out of the comparison,
           so it clamps, never folds, and its count leads. --%>
      <%= if @comparison.gaps.unvalued_securities != [] do %>
        <AppShell.data_note
          severity={:attention}
          id={@prefix <> "comparison-gaps-note"}
          data-role="comparison-gaps"
          clamp
        >
          <%= ngettext(
            "Not included: %{count} position with no usable quote or exchange rate at the as-of date — %{names}",
            "Not included: %{count} positions with no usable quote or exchange rate at the as-of date — %{names}",
            length(@comparison.gaps.unvalued_securities),
            names: Enum.map_join(@comparison.gaps.unvalued_securities, ", ", & &1.security_name)
          ) %>
        </AppShell.data_note>
      <% end %>
    </div>

    <% chart = comparison_chart(@comparison) %>
    <%= if chart do %>
      <%!-- The shared chart (ADR-0022) with its legend: a dashed line
           without a legend is a guess. --%>
      <ul class="chart-legend" data-role="comparison-legend">
        <li class="chart-legend__item">
          <span class="chart-legend__swatch chart-legend__swatch--portfolio" aria-hidden="true">
          </span>
          <%= gettext("Frozen (buy-and-hold)") %>
        </li>
        <li :if={chart.overlays != []} class="chart-legend__item">
          <span class="chart-legend__swatch chart-benchmark-1" aria-hidden="true"></span>
          <%= gettext("Real (TTWROR)") %>
        </li>
      </ul>
      <figure class="perf-figure" data-role="comparison-chart">
        <SecurityChart.chart
          quotes={chart.quotes}
          overlays={chart.overlays}
          overlays_extend_range?={true}
          value_mode={:percent_values}
          zero_line?={true}
          show_transactions?={false}
          aria_label={
            gettext(
              "Change since the as-of date in percent: frozen buy-and-hold versus real performance"
            )
          }
        />
      </figure>
      <%!-- The chart's basis line (Part 4 rule 3 shape): what is
           compared, in which currency, on what basis. Which costs
           left the return and which stayed (ADR-0027 §4) is the
           heading's ⓘ (I1). --%>
      <p class="summary-basis" data-role="comparison-basis">
        <%= gettext("since %{date}", date: Format.date(@comparison.as_of)) %>
        · <%= gettext("in %{currency}", currency: @comparison.base_currency) %>
        · <%= gettext("gross, price development only") %>
      </p>

      <%!-- The one uniform chart-as-table disclosure (UX-DR10):
           quiet summary, defined chevron, stated purpose. --%>
      <details data-role="comparison-disclosure">
        <summary class="disclosure-summary">
          <AppShell.icon name={:chevron_right} size={12} class="disclosure-chevron" />
          <%= gettext("Data as table") %>
        </summary>
        <p class="hint" data-role="disclosure-purpose">
          <%= gettext("Both series as weekly rows — the chart data without the chart.") %>
        </p>
        <div class="data-table-wrapper">
          <table class="drift-table" data-role="comparison-table">
            <thead>
              <tr>
                <th scope="col"><%= gettext("Date") %></th>
                <th scope="col" class="num"><%= gettext("Frozen value") %></th>
                <th scope="col" class="num"><%= gettext("Frozen return") %></th>
                <th scope="col" class="num"><%= gettext("Real return") %></th>
              </tr>
            </thead>
            <tbody>
              <%= for row <- table_rows(@comparison.series) do %>
                <tr>
                  <td><%= Format.date(row.date) %></td>
                  <td class="num"><%= Format.money(row.snapshot_value) %></td>
                  <td class="num">
                    <%= if row.snapshot_indexed, do: signed_fraction(row.snapshot_indexed), else: "—" %>
                  </td>
                  <td class="num">
                    <%= if row.real_indexed, do: signed_fraction(row.real_indexed), else: "—" %>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </details>
    <% else %>
      <p class="hint" data-role="comparison-empty">
        <%= gettext("No valuable holdings at the as-of date — nothing to compare yet.") %>
      </p>
    <% end %>
    """
  end

  # -- the widget ---------------------------------------------------------------------

  attr(:item, :map, required: true)
  attr(:card, :any, required: true, doc: "nil while the read runs, :error, or `read/1`'s answer")

  @doc "The widget „Vergleich gegen einen Snapshot“: the tab's comparison in its frame."
  def widget(assigns) do
    assigns =
      assign(assigns,
        id: "dashboard-snapshot-comparison" <> assigns.item.uid,
        comparison: match?(%{state: :ok}, assigns.card) && assigns.card.comparison
      )

    ~H"""
    <Widget.frame
      id={@id}
      item={@item}
      title={Widgets.title("snapshot_comparison")}
      class="widget--single-form"
      full_href={full_href(@comparison)}
      full_label={gettext("Full view →")}
      full_role="snapshot-comparison-full-view"
    >
      <:info :for={line <- method_lines()}><%= line %></:info>
      <:scope :if={@comparison}>
        <span data-role="comparison-scope">
          <%= StoredText.isolate(
            gettext("Comparison against “%{name}”", name: StoredText.slot(:name)),
            name: @comparison.snapshot.name
          ) %>
          · <%= @card.view_name || gettext("Everything") %>
          · <%= Format.date(@comparison.as_of) %>
        </span>
      </:scope>
      <:shared>
        <div :if={is_nil(@card)} class="section-skeleton" aria-busy="true" data-role="snapshot-comparison-skeleton"></div>
        <p :if={@card == :error} class="hint" data-role="snapshot-comparison-failed">
          <%= gettext("Could not load the comparison") %>
        </p>
        <p :if={@card == %{state: :none}} class="hint" data-role="snapshot-comparison-none">
          <%= gettext("No snapshots yet.") %>
        </p>
        <div :if={@comparison} data-role="snapshot-comparison">
          <.body prefix={@id <> "-"} comparison={@comparison} />
        </div>
      </:shared>
    </Widget.frame>
    """
  end

  # The tab's comparison of the same snapshot.
  defp full_href(%{snapshot: %{id: id}}), do: "/snapshots?snapshot=#{id}"
  defp full_href(_none), do: "/snapshots"

  # -- helpers moved from the tab (Sprint 32 W3) --------------------------------------

  # The cost group renders only when a trade actually cost something in the
  # window: with nothing paid the pre-cost return IS the real return, and a
  # second identical figure beside it would be noise dressed as insight.
  defp transaction_costs?(comparison) do
    not Decimal.equal?(comparison.transaction_costs, Decimal.new(0)) and
      not is_nil(comparison.real_ttwror_before_costs)
  end

  # The three states of ADR-0027 amendment §3, in the operator's terms rather
  # than the engine's. "Partly" is the one worth the words: the changes are
  # ahead on their own merits and the costs are simply not back yet, which is a
  # different answer from "the changes were wrong".
  defp recovery_label(%{state: :recovered}), do: gettext("Yes")

  defp recovery_label(%{state: :partly_recovered, outstanding: outstanding}) do
    gettext("Not yet — %{gap} percentage points to go",
      gap: PortfolixirWeb.Format.percent(outstanding)
    )
  end

  defp recovery_label(%{state: :not_recovered}),
    do: gettext("Behind even before costs")

  # Reachable, and by a natural flow rather than an exotic one: freeze a
  # snapshot while the portfolio is still all cash ("before I restructure"),
  # then buy in with fees. Costs and the pre-cost return then EXIST -- so the
  # group above renders -- while the frozen side has no value at the as-of
  # date, so there is no return to be behind or ahead of. An earlier revision
  # omitted this clause on the claim that the render guard made it dead code,
  # and the page crashed on exactly that snapshot; the regression test in
  # snapshots_live_test.exs pins the flow.
  defp recovery_label(%{state: :not_comparable}),
    do: gettext("No comparable frozen value at the snapshot date")

  # -- comparison chart (the shared chart component, ADR-0022) ---------------

  # Both indexed series through `SecurityChart`: the frozen buy-and-hold as
  # the chart's own line, the real TTWROR as a dashed overlay, both as percent
  # change since the as-of date (value_mode: :percent_values) around the zero
  # line. Every frozen point carries a label naming both series and the
  # frozen value, so the crosshair tooltip reads the pair; the table beneath
  # stays the accessible fallback (UX-DR10). Floats only at the overlay
  # boundary (ADR-0016); the numbers on the cards and in the table stay
  # Decimal-exact. `nil` when the frozen side has no value at the as-of date —
  # there is nothing to index against.
  defp comparison_chart(%{series: series, base_currency: currency}) do
    frozen =
      for point <- series, %Decimal{} = indexed <- [point.snapshot_indexed] do
        %{date: point.date, close: percent_change(indexed), label: point_label(point, currency)}
      end

    real =
      for point <- series, %Decimal{} = indexed <- [point.real_indexed] do
        %{date: point.date, value: Decimal.to_float(percent_change(indexed))}
      end

    case frozen do
      [] ->
        nil

      _points ->
        overlays =
          if real == [],
            do: [],
            else: [%{class: "chart-benchmark-1", label: gettext("Real (TTWROR)"), points: real}]

        %{quotes: frozen, overlays: overlays}
    end
  end

  defp percent_change(indexed), do: indexed |> Decimal.sub(1) |> Decimal.mult(100)

  defp point_label(point, currency) do
    frozen = "#{gettext("Frozen")} #{signed_fraction(point.snapshot_indexed)}"

    real =
      case point.real_indexed do
        %Decimal{} = indexed -> " · #{gettext("Real")} #{signed_fraction(indexed)}"
        nil -> ""
      end

    "#{frozen}#{real} · #{Format.money(point.snapshot_value)} #{currency}"
  end

  # An indexed point's return, printed by Format as every other figure is
  # (#1366, R-047: the table printed it through a float, „0.0%“ on a German
  # page, no sign); the chart's label and the table's cells alike.
  defp signed_fraction(indexed), do: signed_percent(Decimal.sub(indexed, 1)) <> "%"

  # The table samples the daily series to weekly rows (plus the last day) so
  # the chart-as-table stays readable; the full daily data is the chart's.
  defp table_rows(series) do
    last = List.last(series)

    series
    |> Enum.take_every(7)
    |> then(fn rows ->
      if List.last(rows) == last, do: rows, else: rows ++ [last]
    end)
  end

  defp signed_percent(value), do: Format.signed_percent(value)

  # Gain/loss colour by sign, never the accent (UX-DR7), decided on the
  # percent as displayed (#1149): "0,0%" is `is-flat`, body ink, as Wealth's
  # cards are; no class would leave it the stat card's accent (the γ closing
  # act, DB1). A missing figure keeps no class.
  defp sign_class(value) do
    case Format.displayed_percent_sign(value) do
      :positive -> "is-positive"
      :negative -> "is-negative"
      :zero -> "is-flat"
      nil -> nil
    end
  end
end
