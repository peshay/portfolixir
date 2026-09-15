defmodule PortfolixirWeb.SnapshotsLive do
  @moduledoc """
  Depot snapshots and the ADR-0027 counterfactual comparison, as a Wealth tab.

  The maintainer freezes "the state I have right now" as a named marker (name,
  view scope, as-of date — no data copied, ADR-0004) and later reads whether
  keeping exactly those holdings would have beaten the real performance since:
  buy-and-hold of the frozen positions over the stored quote history versus
  the scope's real TTWROR (`Portfolixir.Portfolios.SnapshotComparison`).

  **The comparison is the surface** (EXPERIENCE.md → Component Patterns →
  Snapshots comparison, built by issue 796): with at least one snapshot the
  page opens on the newest one's comparison — the ADR-0027 figures, the
  shared chart with its data-table disclosure and basis line — and the list
  beneath selects which snapshot is compared (`?snapshot=<id>` addresses it).
  The create form sits behind a closed disclosure, a snapshot's deletion in
  its row menu, the explanation behind an ⓘ on the heading.

  The comparison is gross and price-return only in v1 (ADR-0027) and says so
  as a data note (UX-DR17); securities the engine had to exclude are listed
  as gaps (AR-4).
  """

  use PortfolixirWeb, :live_view

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.SnapshotComparison
  alias Portfolixir.Portfolios.Snapshots
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Components.SecurityChart
  alias PortfolixirWeb.Format

  @impl true
  def mount(_params, _session, socket) do
    socket = assign(socket, :current_path, "/snapshots")

    case Portfolios.count_securities_accounts() + Portfolios.count_cash_accounts() do
      0 ->
        {:ok,
         assign(socket,
           portfolio: nil,
           snapshots: [],
           views: [],
           comparison: nil,
           selected_id: nil
         )}

      _accounts ->
        socket =
          socket
          |> assign(:portfolio, Portfolios.first_portfolio())
          |> assign(:views, Buckets.list_views())
          |> assign(:comparison, nil)
          |> assign(:selected_id, nil)
          |> assign(:form_errors, nil)
          |> assign(:page_error, nil)
          |> assign(:row_menu_id, nil)
          |> load_snapshots()

        {:ok, socket}
    end
  end

  # `?snapshot=<id>` addresses the comparison (issue 796); without it the
  # newest snapshot's comparison opens, so the page answers without a click.
  @impl true
  def handle_params(_params, _uri, %{assigns: %{portfolio: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_params(params, _uri, socket) do
    socket = assign(socket, :row_menu_id, nil)

    case parse_int(params["snapshot"] || "") do
      nil ->
        case socket.assigns.snapshots do
          [newest | _rest] -> {:noreply, select_snapshot(socket, newest.id)}
          [] -> {:noreply, assign(socket, comparison: nil, selected_id: nil)}
        end

      id ->
        {:noreply, select_snapshot(socket, id)}
    end
  end

  @impl true
  def handle_event("create_snapshot", %{"snapshot" => params}, socket) do
    attrs = %{
      name: params["name"],
      as_of: params["as_of"],
      view_id: parse_view_id(params["view_id"])
    }

    case Snapshots.create_snapshot(Actor.owner_ui(), attrs) do
      {:ok, snapshot} ->
        socket =
          socket
          |> assign(:form_errors, nil)
          |> load_snapshots()
          |> push_patch(to: snapshot_path(snapshot.id))

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form_errors, changeset_errors(changeset))}
    end
  end

  def handle_event("select_snapshot", %{"id" => id}, socket) do
    case parse_int(id) do
      nil -> {:noreply, socket}
      id -> {:noreply, push_patch(socket, to: snapshot_path(id))}
    end
  end

  def handle_event("delete_snapshot", %{"id" => id}, socket) do
    case parse_int(id) do
      nil ->
        {:noreply, socket}

      id ->
        # A snapshot already deleted elsewhere (other tab, API, MCP) is not an
        # error — the marker is gone either way; just refresh the list.
        case Snapshots.delete_snapshot(Actor.owner_ui(), id) do
          {:ok, _} -> :ok
          {:error, :not_found} -> :ok
        end

        socket = socket |> assign(:row_menu_id, nil) |> load_snapshots()

        # Deleting the compared snapshot falls back to the newest one.
        if socket.assigns.selected_id == id do
          {:noreply, push_patch(socket, to: "/snapshots")}
        else
          {:noreply, socket}
        end
    end
  end

  # The row menu (Part 4 rule 11 of the 2026-09-12 review): deletion lives
  # behind the row's kebab, never as a standing button on every row.
  def handle_event("open_row_menu", %{"id" => id}, socket) do
    case parse_int(id) do
      nil ->
        {:noreply, socket}

      id ->
        if Enum.any?(socket.assigns.snapshots, &(&1.id == id)) do
          {:noreply, assign(socket, :row_menu_id, id)}
        else
          {:noreply, socket}
        end
    end
  end

  def handle_event("close_row_menu", _params, socket) do
    {:noreply, assign(socket, :row_menu_id, nil)}
  end

  defp load_snapshots(socket) do
    assign(socket, :snapshots, Snapshots.list_snapshots())
  end

  defp select_snapshot(socket, id) do
    case SnapshotComparison.for_snapshot(id, socket.assigns.portfolio.id) do
      {:ok, comparison} ->
        assign(socket, comparison: comparison, selected_id: id, page_error: nil)

      {:error, _reason} ->
        # The app shell shows assign-based alerts, not LiveView flash — mirror
        # the pattern the other pages use (review/coverage round).
        assign(socket,
          comparison: nil,
          selected_id: nil,
          page_error: gettext("Could not load the comparison")
        )
    end
  end

  defp snapshot_path(id), do: "/snapshots?snapshot=#{id}"

  defp parse_view_id(nil), do: nil
  defp parse_view_id(""), do: nil
  defp parse_view_id(value) when is_binary(value), do: parse_int(value)

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_int(_value), do: nil

  # Field -> messages map, so each input can carry aria-invalid and reference
  # the error text (UX-DR13; a11y review finding).
  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp form_error_text(errors) do
    Enum.map_join(errors, "; ", fn {field, messages} ->
      "#{field} #{Enum.join(messages, ", ")}"
    end)
  end

  defp invalid?(nil, _field), do: false
  defp invalid?(errors, field), do: Map.has_key?(errors, field)

  defp view_name(_views, nil), do: gettext("Everything")

  defp view_name(views, view_id) do
    case Enum.find(views, &(&1.id == view_id)) do
      nil -> gettext("Everything")
      view -> view.name
    end
  end

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

  defp signed_fraction(indexed), do: signed_percent(Decimal.sub(indexed, 1)) <> "%"

  defp percent_label(factor) do
    "#{Float.round((factor - 1.0) * 100, 1)}%"
  end

  defp to_float(nil), do: nil
  defp to_float(%Decimal{} = value), do: Decimal.to_float(value)

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

  @impl true
  def render(%{portfolio: nil} = assigns) do
    ~H"""
    <AppShell.shell current_path={@current_path} page_title={gettext("Snapshots")}>
      <div class="workspace-page">
        <section class="workspace-section empty-state">
          <h2><%= gettext("Snapshots") %></h2>
          <p><%= gettext("Snapshots need a depot with a cash account.") %></p>
          <.link navigate="/portfolios" class="button"><%= gettext("Create a depot and cash account") %></.link>
        </section>
      </div>
    </AppShell.shell>
    """
  end

  def render(assigns) do
    ~H"""
    <AppShell.shell
      current_path={@current_path}
      page_title={gettext("Snapshots")}
      page_subtitle={gettext("Freeze a depot state and compare against it")}
    >
      <div class="workspace-page">
        <AppShell.area_tabs tabs={AppShell.wealth_tabs(:snapshots)} />

        <%!-- Compare-click feedback rides the canonical inline-result slot
             (design-critic fix round): the alert region exists before the
             action, so the announcement is never lost. --%>
        <AppShell.inline_result
          id="snapshots-action-result"
          result={@page_error && {:problem, @page_error}}
        />

        <%!-- The comparison is the surface (#671, #796): it renders first and
             large — the newest snapshot's without a click — the list beneath
             selects which one is compared. --%>
        <%= if @comparison do %>
          <section class="workspace-section" data-role="snapshot-comparison">
            <header class="section-head">
              <h2>
                <%= gettext("Comparison against “%{name}”", name: @comparison.snapshot.name) %>
              </h2>
              <span class="badge" data-role="comparison-scope">
                <%= view_name(@views, @comparison.snapshot.view_id) %>
                · <%= Format.date(@comparison.as_of) %>
              </span>
            </header>

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
                  <%= gettext(
                    "Buy-and-hold of the holdings frozen on %{date}: %{then} → %{today} %{currency}",
                    date: Format.date(@comparison.as_of),
                    then: Format.money(@comparison.as_of_value),
                    today: Format.money(@comparison.current_value),
                    currency: @comparison.base_currency
                  ) %>
                </small>
              </article>
              <div
                :if={transaction_costs?(@comparison)}
                id="comparison-costs"
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
                    <%= Format.money(@comparison.transaction_costs) %><small class="value-suffix"><%= @comparison.base_currency %></small>
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
              <AppShell.data_note severity={:note} data-role="comparison-limitation">
                <%= gettext(
                  "The comparison is gross and price development only — dividends are not yet included."
                ) %>
              </AppShell.data_note>
              <%= if @comparison.gaps.unvalued_securities != [] do %>
                <AppShell.data_note severity={:attention} data-role="comparison-gaps">
                  <%= gettext("Not included (no usable quote or exchange rate at the as-of date):") %>
                  <%= Enum.map_join(@comparison.gaps.unvalued_securities, ", ", & &1.security_name) %>
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
                   compared, in which currency, on what basis, and which
                   costs left the return and which stayed (ADR-0027 §4). --%>
              <p class="summary-basis" data-role="comparison-basis">
                <%= gettext(
                  "since %{date} · in %{currency} · gross, price development only · Transaction costs = fees and taxes booked on trades since then; standalone fees, taxes and dividend withholding stay inside the return on both sides",
                  date: Format.date(@comparison.as_of),
                  currency: @comparison.base_currency
                ) %>
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
                          <td><%= row.date %></td>
                          <td class="num"><%= Format.money(row.snapshot_value) %></td>
                          <td class="num">
                            <%= if row.snapshot_indexed, do: percent_label(to_float(row.snapshot_indexed)), else: "—" %>
                          </td>
                          <td class="num">
                            <%= if row.real_indexed, do: percent_label(to_float(row.real_indexed)), else: "—" %>
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
          </section>
        <% end %>

        <section class="workspace-section">
          <header class="section-head">
            <h2>
              <%= gettext("Snapshots") %>
              <%!-- The explanation behind an ⓘ on the heading (UX-DR11),
                   not a paragraph above the list. --%>
              <details class="metric-tooltip metric-tooltip--inline" data-role="snapshots-info">
                <summary aria-label={gettext("About snapshots")}>ⓘ</summary>
                <p role="tooltip">
                  <%= gettext(
                    "A snapshot freezes the holdings held on a date — as a marker on the ledger, copying nothing. A later comparison shows whether keeping them would have beaten the real performance."
                  ) %>
                </p>
              </details>
            </h2>
          </header>

          <%!-- Kept open while errors exist: a closed details would swallow
               the error message after a failed submit (Steve UAT finding). --%>
          <details class="snapshot-create" open={@form_errors != nil}>
            <summary class="disclosure-summary">
              <AppShell.icon name={:chevron_right} size={12} class="disclosure-chevron" />
              <%= gettext("New snapshot") %>
            </summary>
            <form id="snapshot-create-form" phx-submit="create_snapshot" class="snapshot-create__form">
              <label>
                <%= gettext("Name") %>
                <input
                  type="text"
                  name="snapshot[name]"
                  required
                  maxlength="120"
                  aria-invalid={invalid?(@form_errors, :name) && "true"}
                  aria-describedby={invalid?(@form_errors, :name) && "snapshot-form-error"}
                />
              </label>
              <label>
                <%= gettext("As of") %>
                <input
                  type="text"
                  placeholder="YYYY-MM-DD"
                  pattern="[0-9]{4}-[0-9]{2}-[0-9]{2}"
                  maxlength="10"
                  name="snapshot[as_of]"
                  value={Date.to_iso8601(Date.utc_today())}
                  required
                  aria-invalid={invalid?(@form_errors, :as_of) && "true"}
                  aria-describedby={invalid?(@form_errors, :as_of) && "snapshot-form-error"}
                />
              </label>
              <label>
                <%= gettext("Scope") %>
                <select name="snapshot[view_id]">
                  <option value=""><%= gettext("Everything") %></option>
                  <%= for view <- @views do %>
                    <option value={view.id}><%= view.name %></option>
                  <% end %>
                </select>
              </label>
              <button type="submit" class="button"><%= gettext("Freeze state") %></button>
            </form>
            <p :if={@form_errors} id="snapshot-form-error" class="form-error" role="alert">
              <%= form_error_text(@form_errors) %>
            </p>
          </details>

          <%= if @snapshots == [] do %>
            <p class="hint"><%= gettext("No snapshots yet.") %></p>
          <% else %>
            <div class="data-table-wrapper">
              <table class="drift-table" data-role="snapshot-list">
                <thead>
                  <tr>
                    <th scope="col"><%= gettext("Name") %></th>
                    <th scope="col"><%= gettext("Scope") %></th>
                    <th scope="col"><%= gettext("As of") %></th>
                    <th scope="col" class="row-actions-head">
                      <span class="sr-only"><%= gettext("Actions") %></span>
                    </th>
                  </tr>
                </thead>
                <tbody>
                  <%= for snapshot <- @snapshots do %>
                    <tr
                      data-role="snapshot-row"
                      class={["snapshot-row", @selected_id == snapshot.id && "is-selected"]}
                    >
                      <td>
                        <.link
                          patch={snapshot_path(snapshot.id)}
                          class="row-target"
                          data-role="snapshot-select"
                        >
                          <%= snapshot.name %>
                        </.link>
                        <span
                          :if={@selected_id == snapshot.id}
                          class="badge"
                          data-role="in-comparison"
                        >
                          <%= gettext("In comparison") %>
                        </span>
                      </td>
                      <td><%= view_name(@views, snapshot.view_id) %></td>
                      <td><%= snapshot.as_of %></td>
                      <td class="row-actions">
                        <button
                          type="button"
                          id={"snapshot-kebab-#{snapshot.id}"}
                          class="row-actions__kebab"
                          phx-click="open_row_menu"
                          phx-value-id={snapshot.id}
                          aria-label={gettext("Open actions menu")}
                          aria-haspopup="menu"
                          aria-expanded={@row_menu_id == snapshot.id}
                        >
                          <AppShell.icon name={:ellipsis_vertical} />
                        </button>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        </section>
      </div>

      <AppShell.row_menu
        :if={@row_menu_id}
        id={"snapshot-row-menu-#{@row_menu_id}"}
        trigger={"snapshot-kebab-#{@row_menu_id}"}
        label={gettext("Snapshot actions")}
      >
        <button
          type="button"
          class="row-context-menu__item row-context-menu__item--danger"
          role="menuitem"
          phx-click="delete_snapshot"
          phx-value-id={@row_menu_id}
          data-confirm={gettext("Delete this snapshot marker? No transactions are affected.")}
        >
          <AppShell.icon name={:trash} />
          <span><%= gettext("Delete") %></span>
        </button>
      </AppShell.row_menu>
    </AppShell.shell>
    """
  end

  defp signed_percent(value) do
    formatted = Format.percent(value)
    if Decimal.compare(value, 0) == :gt, do: "+" <> formatted, else: formatted
  end

  # Gain/loss colour by sign, never the accent (UX-DR7).
  defp sign_class(value) do
    case Decimal.compare(value, 0) do
      :gt -> "is-positive"
      :lt -> "is-negative"
      :eq -> nil
    end
  end
end
