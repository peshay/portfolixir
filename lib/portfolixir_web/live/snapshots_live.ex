defmodule PortfolixirWeb.SnapshotsLive do
  @moduledoc """
  Depot snapshots and the ADR-0027 counterfactual comparison, as a Wealth tab.

  The maintainer freezes "the state I have right now" as a named marker (name,
  view scope, as-of date — no data copied, ADR-0004) and later reads whether
  keeping exactly those holdings would have beaten the real performance since:
  buy-and-hold of the frozen positions over the stored quote history versus
  the scope's real TTWROR (`Portfolixir.Portfolios.SnapshotComparison`).

  The comparison is gross and price-return only in v1 (ADR-0027) and says so
  on the surface (UX-DR11); the chart's data is also reachable as a table
  (UX-DR10); securities the engine had to exclude are listed as gaps (AR-4).
  """

  use PortfolixirWeb, :live_view

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.SnapshotComparison
  alias Portfolixir.Portfolios.Snapshots
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Format

  @impl true
  def mount(_params, _session, socket) do
    socket = assign(socket, :current_path, "/snapshots")

    case Portfolios.count_securities_accounts() + Portfolios.count_cash_accounts() do
      0 ->
        {:ok, assign(socket, portfolio: nil, snapshots: [], views: [], comparison: nil)}

      _accounts ->
        socket =
          socket
          |> assign(:portfolio, Portfolios.first_portfolio())
          |> assign(:views, Buckets.list_views())
          |> assign(:comparison, nil)
          |> assign(:selected_id, nil)
          |> assign(:form_errors, nil)
          |> assign(:page_error, nil)
          |> load_snapshots()

        {:ok, socket}
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
          |> select_snapshot(snapshot.id)

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form_errors, changeset_errors(changeset))}
    end
  end

  def handle_event("select_snapshot", %{"id" => id}, socket) do
    case parse_int(id) do
      nil -> {:noreply, socket}
      id -> {:noreply, select_snapshot(socket, id)}
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

        socket =
          socket
          |> load_snapshots()
          |> then(fn socket ->
            if socket.assigns.selected_id == id do
              assign(socket, comparison: nil, selected_id: nil)
            else
              socket
            end
          end)

        {:noreply, socket}
    end
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

  defp parse_view_id(nil), do: nil
  defp parse_view_id(""), do: nil
  defp parse_view_id(value) when is_binary(value), do: parse_int(value)

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  # Field -> messages map, so each input can carry aria-invalid and reference
  # the error text (UX-DR13; a11y review finding).
  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp form_error_text(nil), do: nil

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

  # No clause for :not_comparable, and that is deliberate rather than an
  # omission: the guard above renders this group only when a cost was paid AND
  # a pre-cost return exists, and both are absent exactly when the comparison
  # has no comparable pair. A catch-all here would be code that cannot run.
  # A fourth state added later raises in the first test that renders it, which
  # is the loud failure this repo prefers over a silent fallback label.

  # -- comparison chart (server-rendered SVG, display boundary) ---------------

  # Both indexed series drawn into one 640×220 plot. Floats are fine here:
  # this is the chart/display boundary (ADR-0016); the numbers next to the
  # chart and in the table stay Decimal-exact.
  defp chart_geometry(series) do
    points =
      series
      |> Enum.map(fn point ->
        {point.date, to_float(point.snapshot_indexed), to_float(point.real_indexed)}
      end)
      |> Enum.filter(fn {_date, snapshot, _real} -> is_number(snapshot) end)

    values =
      Enum.flat_map(points, fn {_date, snapshot, real} ->
        [snapshot | if(is_number(real), do: [real], else: [])]
      end)

    case {points, values} do
      {[], _} ->
        nil

      {_, values} ->
        min_value = Enum.min(values)
        max_value = Enum.max(values)
        span = max(max_value - min_value, 1.0e-9)

        %{
          points: points,
          min: min_value,
          max: max_value,
          span: span,
          count: max(length(points) - 1, 1)
        }
    end
  end

  defp to_float(nil), do: nil
  defp to_float(%Decimal{} = value), do: Decimal.to_float(value)

  defp polyline(geometry, accessor) do
    geometry.points
    |> Enum.with_index()
    |> Enum.flat_map(fn {{_date, snapshot, real}, index} ->
      value = if accessor == :snapshot, do: snapshot, else: real

      if is_number(value) do
        x = 40 + index / geometry.count * 580
        y = 200 - (value - geometry.min) / geometry.span * 180
        ["#{Float.round(x, 2)},#{Float.round(y, 2)}"]
      else
        []
      end
    end)
    |> Enum.join(" ")
  end

  defp percent_label(factor) do
    "#{Float.round((factor - 1.0) * 100, 1)}%"
  end

  # The viewBox y of the ±0% level (factor 1.0), or nil when the whole series
  # sits above/below it (no line beats a misleading one).
  defp baseline_y(geometry) do
    if geometry.min <= 1.0 and 1.0 <= geometry.max do
      Float.round(200 - (1.0 - geometry.min) / geometry.span * 180, 2)
    end
  end

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
          <p><%= gettext("Create a depot and cash account first to freeze and compare a depot state.") %></p>
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

        <%!-- The comparison is the surface (#671, EXPERIENCE.md → Snapshots
             comparison): it renders primary and large; the snapshot list is
             secondary beneath it, the create form behind a disclosure. --%>
        <%= if @comparison do %>
          <section class="workspace-section" data-role="snapshot-comparison">
            <h2>
              <%= gettext("What if I had kept it? — %{name}", name: @comparison.snapshot.name) %>
            </h2>
            <%!-- Basis line: what is being compared, in the operator's terms
                 (ADR-0027); the domain is fixed by the snapshot's as-of date,
                 so there is no period control. --%>
            <p class="muted" data-role="comparison-basis">
              <%= gettext(
                "Buy-and-hold of the holdings frozen on %{date} versus the real performance (TTWROR) since, in %{currency}. Transaction costs are the fees and taxes booked on trades since then; standalone fees, taxes and dividend withholding stay inside the return on both sides.",
                date: Date.to_iso8601(@comparison.as_of),
                currency: @comparison.base_currency
              ) %>
            </p>

            <div class="grid" role="group" aria-label={gettext("Comparison key figures")}>
              <article class="stat">
                <span><%= gettext("Frozen value then") %></span>
                <strong>
                  <%= Format.money(@comparison.as_of_value) %> <%= @comparison.base_currency %>
                </strong>
              </article>
              <article class="stat">
                <span><%= gettext("Frozen value today") %></span>
                <strong>
                  <%= Format.money(@comparison.current_value) %> <%= @comparison.base_currency %>
                </strong>
              </article>
              <article class="stat">
                <span><%= gettext("Snapshot return (price)") %></span>
                <%= if @comparison.snapshot_return do %>
                  <strong class={sign_class(@comparison.snapshot_return)}>
                    <%= signed_percent(@comparison.snapshot_return) %>%
                  </strong>
                <% else %>
                  <%!-- Not-computable: quiet muted dash, never at value
                       weight ({components.value-slot}.not-computable). --%>
                  <span class="stat-empty">—</span>
                <% end %>
              </article>
              <article class="stat">
                <span><%= gettext("Real TTWROR since") %></span>
                <%= if @comparison.real_ttwror do %>
                  <strong class={sign_class(@comparison.real_ttwror)}>
                    <%= signed_percent(@comparison.real_ttwror) %>%
                  </strong>
                <% else %>
                  <span class="stat-empty">—</span>
                <% end %>
              </article>
            </div>

            <%!-- ADR-0027 amendment §4 (#708), review-blocking: the pre-cost
                 return is NEVER rendered alone. This group renders only when
                 costs were actually paid, and when it renders it carries all
                 three — the pre-cost figure, what the trades cost, and whether
                 that is earned back. On its own the first is a number that
                 flatters, and the value of this system rests on figures that
                 can embarrass their author. --%>
            <div
              :if={transaction_costs?(@comparison)}
              id="comparison-costs"
              class="grid"
              role="group"
              aria-label={gettext("Transaction costs since the snapshot")}
            >
              <article class="stat">
                <span><%= gettext("Real TTWROR before transaction costs") %></span>
                <strong
                  class={sign_class(@comparison.real_ttwror_before_costs)}
                  data-role="pre-cost-return"
                >
                  <%= signed_percent(@comparison.real_ttwror_before_costs) %>%
                </strong>
              </article>
              <article class="stat">
                <span><%= gettext("Transaction costs") %></span>
                <strong data-role="transaction-costs">
                  <%= PortfolixirWeb.Format.money(@comparison.transaction_costs) %>
                  <small><%= @comparison.base_currency %></small>
                </strong>
              </article>
              <article class="stat">
                <span><%= gettext("Earned back?") %></span>
                <strong data-role="cost-recovery">
                  <%= recovery_label(@comparison.cost_recovery) %>
                </strong>
              </article>
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

            <% geometry = chart_geometry(@comparison.series) %>
            <%= if geometry do %>
              <figure class="snapshot-chart">
                <%!-- Min/max labels as HTML beside the SVG: text inside a
                     preserveAspectRatio="none" viewBox would distort
                     (design-review finding). --%>
                <div class="snapshot-chart__scale" aria-hidden="true">
                  <span><%= percent_label(geometry.max) %></span>
                  <span><%= percent_label(geometry.min) %></span>
                </div>
                <svg
                  viewBox="0 0 640 220"
                  role="img"
                  aria-label={gettext("Change since the as-of date: snapshot buy-and-hold versus real performance")}
                  preserveAspectRatio="none"
                >
                  <%!-- Reference line at the ±0% start level, not at the series
                       minimum — the minimum floats when performance dips
                       (design-review finding). --%>
                  <%= if baseline_y = baseline_y(geometry) do %>
                    <line
                      x1="40"
                      y1={baseline_y}
                      x2="620"
                      y2={baseline_y}
                      class="chart-axis"
                      vector-effect="non-scaling-stroke"
                    />
                  <% end %>
                  <polyline
                    points={polyline(geometry, :snapshot)}
                    class="snapshot-series"
                    fill="none"
                    vector-effect="non-scaling-stroke"
                  />
                  <polyline
                    points={polyline(geometry, :real)}
                    class="real-series"
                    fill="none"
                    stroke-dasharray="6 4"
                    vector-effect="non-scaling-stroke"
                  />
                </svg>
                <div class="snapshot-chart__dates" aria-hidden="true">
                  <span><%= Date.to_iso8601(@comparison.as_of) %></span>
                  <span><%= Date.to_iso8601(@comparison.today) %></span>
                </div>
                <figcaption class="snapshot-chart__legend">
                  <span class="legend-swatch legend-swatch--solid" aria-hidden="true"></span>
                  <%= gettext("Snapshot (buy-and-hold)") %>
                  <span class="legend-swatch legend-swatch--dashed" aria-hidden="true"></span>
                  <%= gettext("Real (TTWROR)") %>
                  <span class="muted">
                    <%= gettext("change since %{date}, in percent", date: Date.to_iso8601(@comparison.as_of)) %>
                  </span>
                </figcaption>
              </figure>

              <%!-- The one uniform chart-as-table disclosure (UX-DR10):
                   quiet summary, defined chevron, stated purpose. --%>
              <details data-role="comparison-disclosure">
                <summary class="disclosure-summary">
                  <AppShell.icon name={:chevron_right} size={12} class="disclosure-chevron" />
                  <%= gettext("Data as table") %>
                </summary>
                <p class="muted" data-role="disclosure-purpose">
                  <%= gettext("Both series as weekly rows — the chart data without the chart.") %>
                </p>
                <div class="table-scroll">
                  <table class="drift-table" data-role="comparison-table">
                    <thead>
                      <tr>
                        <th scope="col"><%= gettext("Date") %></th>
                        <th scope="col" class="num"><%= gettext("Snapshot value") %></th>
                        <th scope="col" class="num"><%= gettext("Snapshot return") %></th>
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
              <p class="muted" data-role="comparison-empty">
                <%= gettext("No valuable holdings at the as-of date — nothing to compare yet.") %>
              </p>
            <% end %>
          </section>
        <% end %>

        <section class="workspace-section">
          <header class="section-head">
            <h2><%= gettext("Snapshots") %></h2>
          </header>
          <p class="muted">
            <%= gettext(
              "A snapshot freezes the holdings held on a date — as a marker on the ledger, copying nothing. A later comparison shows whether keeping them would have beaten the real performance."
            ) %>
          </p>

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
            <p class="muted"><%= gettext("No snapshots yet.") %></p>
          <% else %>
            <div class="table-scroll">
              <table class="drift-table" data-role="snapshot-list">
              <thead>
                <tr>
                  <th scope="col"><%= gettext("Name") %></th>
                  <th scope="col"><%= gettext("Scope") %></th>
                  <th scope="col"><%= gettext("As of") %></th>
                  <th scope="col"></th>
                </tr>
              </thead>
              <tbody>
                <%= for snapshot <- @snapshots do %>
                  <tr data-role="snapshot-row" class={@selected_id == snapshot.id && "is-selected"}>
                    <td><%= snapshot.name %></td>
                    <td><%= view_name(@views, snapshot.view_id) %></td>
                    <td><%= snapshot.as_of %></td>
                    <td class="num">
                      <button
                        type="button"
                        class="button"
                        phx-click="select_snapshot"
                        phx-value-id={snapshot.id}
                      >
                        <%= gettext("Compare") %>
                      </button>
                      <button
                        type="button"
                        class="button-danger"
                        phx-click="delete_snapshot"
                        phx-value-id={snapshot.id}
                        data-confirm={gettext("Delete this snapshot marker? No transactions are affected.")}
                      >
                        <%= gettext("Delete") %>
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
