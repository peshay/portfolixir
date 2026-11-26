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
  alias Portfolixir.Clock
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.SnapshotComparison
  alias Portfolixir.Portfolios.Snapshots
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Dashboard.Widgets.SnapshotComparison, as: SnapshotComparisonWidget
  alias PortfolixirWeb.Dashboard.Widgets.SnapshotList, as: SnapshotListWidget
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.LiveParam
  alias PortfolixirWeb.StoredText

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

    # An id no snapshot can carry reads as absent (#868): the newest opens.
    case LiveParam.id(params["snapshot"]) do
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
    params = LiveParam.map(params)

    attrs = %{
      name: params["name"],
      as_of: params["as_of"],
      view_id: LiveParam.id(params["view_id"])
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
    case LiveParam.id(id) do
      nil -> {:noreply, socket}
      id -> {:noreply, push_patch(socket, to: snapshot_path(id))}
    end
  end

  def handle_event("delete_snapshot", %{"id" => id}, socket) do
    case LiveParam.id(id) do
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
    case LiveParam.id(id) do
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

  # The result note's × (#1366, R-157; Sprint 32 W5): the slot empties
  # until the next action, as on every other page that draws one.
  def handle_event("dismiss_result", _params, socket),
    do: {:noreply, assign(socket, :page_error, nil)}

  # An event this page does not know, or a payload it cannot read, changes
  # nothing (E25 S4, F17).
  def handle_event(_event, _params, socket), do: {:noreply, socket}

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

  # The scope's name, as the list names it (Sprint 32 W3).
  defp view_name(views, view_id), do: SnapshotListWidget.view_name(views, view_id)

  @impl true
  def render(%{portfolio: nil} = assigns) do
    ~H"""
    <AppShell.shell page_address={@page_address} current_path={@current_path} page_title={gettext("Snapshots")}>
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
    <AppShell.shell page_address={@page_address}
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
          focus_fallback="#snapshots-heading"
        />

        <%!-- The comparison is the surface (#671, #796): it renders first and
             large — the newest snapshot's without a click — the list beneath
             selects which one is compared. --%>
        <%= if @comparison do %>
          <section class="workspace-section" data-role="snapshot-comparison">
            <header class="section-head">
              <%!-- I1 (board ux-design-2026-11-03-sprint23-i1, Snapshots ①;
                   reading 3): the cost definition and the limitation are
                   method, true of any comparison, so they sit in the
                   section's ⓘ; the basis clauses stay under the chart. --%>
              <div class="section-title">
                <h2>
                  <%= StoredText.isolate(
                    gettext("Comparison against “%{name}”", name: StoredText.slot(:name)),
                    name: @comparison.snapshot.name
                  ) %>
                </h2>
                <AppShell.section_info>
                  <:line :for={line <- SnapshotComparisonWidget.method_lines()}><%= line %></:line>
                </AppShell.section_info>
              </div>
              <span class="badge" data-role="comparison-scope">
                <%= view_name(@views, @comparison.snapshot.view_id) %>
                · <%= Format.date(@comparison.as_of) %>
              </span>
            </header>

            <%!-- Sprint 32 W3: the comparison is drawn by the widget „Vergleich
                 gegen einen Snapshot“'s module, so the tab and a dashboard draw it
                 with one code path. --%>
            <SnapshotComparisonWidget.body comparison={@comparison} />
          </section>
        <% end %>

        <section class="workspace-section">
          <header class="section-head">
            <h2 id="snapshots-heading" class="result-focus-fallback" tabindex="-1">
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
                  value={Date.to_iso8601(Clock.today())}
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

          <%!-- Sprint 32 W3: the list is drawn by the widget „Snapshot-Liste“'s
               module, so the tab and a dashboard draw it with one code path; the
               row menu, which deletes, stays the tab's. --%>
          <SnapshotListWidget.table snapshots={@snapshots} views={@views} selected_id={@selected_id}>
            <:row_action :let={snapshot}>
              <AppShell.row_kebab
                id={"snapshot-kebab-#{snapshot.id}"}
                row={snapshot.name}
                open={@row_menu_id == snapshot.id}
                phx-click="open_row_menu"
                phx-value-id={snapshot.id}
              />
            </:row_action>
          </SnapshotListWidget.table>
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
end
