defmodule PortfolixirWeb.Dashboard.Widgets.SnapshotList do
  @moduledoc """
  The section widget „Snapshot-Liste“ `snapshot_list` (I57; Sprint 32 W3;
  ADR-0062's amendment of 2026-11-25, points 3 and 7; planning board
  `ux-design-2026-11-25-sprint32/02` ②): the list of Wealth's tab
  „Snapshots“, moved here so that one code path draws it on the tab
  (`table/1`, which `PortfolixirWeb.SnapshotsLive` renders under the
  section's head and its form) and on a dashboard (`widget/1`).

  Its rows are `Portfolixir.Portfolios.Snapshots.list_snapshots/1`, the
  list `GET /api/v1/snapshots` answers, newest as-of first: each
  snapshot's name, its scope (its view's name, „Alles“ without one) and
  its as-of date; the one compared is marked „Im Vergleich“. A name picks
  the snapshot compared: on the tab by its address, as before; on a
  dashboard in the widget „Vergleich gegen einen Snapshot“, for the
  page's life, nothing stored.

  **Write forms stay on the tab** (ADR-0022's amendment of 2026-11-21,
  point 3): a snapshot is made with „Neuer Snapshot →“, which leads to the
  tab and its form, and deleted from its row's menu there.

  Its compact form is the section's own narrow layout: the same table,
  drawn once (`widget--single-form`).
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Buckets
  alias Portfolixir.Dashboards.Widgets
  alias Portfolixir.Portfolios.Snapshots
  alias PortfolixirWeb.Dashboard.Widget
  alias PortfolixirWeb.Format

  # -- the read -------------------------------------------------------------------

  @doc """
  The widget's read, in the dashboard's background task: the snapshots,
  newest as-of first, and the views their scopes name.
  """
  @spec read() :: %{snapshots: [map()], views: [map()]}
  def read, do: %{snapshots: Snapshots.list_snapshots(), views: Buckets.list_views()}

  @doc "The name of a snapshot's scope: its view's, „Alles“ without one or once it is gone."
  @spec view_name([map()], integer() | nil) :: String.t()
  def view_name(_views, nil), do: gettext("Everything")

  def view_name(views, view_id) do
    case Enum.find(views, &(&1.id == view_id)) do
      nil -> gettext("Everything")
      view -> view.name
    end
  end

  # -- the list -------------------------------------------------------------------

  attr(:snapshots, :list, required: true)
  attr(:views, :list, required: true)
  attr(:selected_id, :any, required: true, doc: "the snapshot compared, or nil")

  attr(:pick, :atom,
    default: :patch,
    doc: ":patch on the tab (the address names it), :event on a dashboard"
  )

  slot(:row_action, doc: "the tab's row menu, given the snapshot")

  @doc """
  The list: each snapshot's name, which picks it, its scope and its as-of
  date, the one compared marked; „Noch keine Snapshots.“ without one.
  """
  def table(assigns) do
    ~H"""
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
              <th :if={@row_action != []} scope="col" class="row-actions-head">
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
                    :if={@pick == :patch}
                    patch={snapshot_path(snapshot.id)}
                    class="row-target"
                    data-role="snapshot-select"
                  >
                    <%= snapshot.name %>
                  </.link>
                  <%!-- On a dashboard the name picks the snapshot its
                       comparison widget compares (Sprint 32 W3). --%>
                  <button
                    :if={@pick == :event}
                    type="button"
                    class="link-button row-target"
                    data-role="snapshot-select"
                    phx-click="select_snapshot"
                    phx-value-id={snapshot.id}
                    aria-pressed={to_string(@selected_id == snapshot.id)}
                  >
                    <%= snapshot.name %>
                  </button>
                  <span
                    :if={@selected_id == snapshot.id}
                    class="badge"
                    data-role="in-comparison"
                  >
                    <%= gettext("In comparison") %>
                  </span>
                </td>
                <td><%= view_name(@views, snapshot.view_id) %></td>
                <td><%= Format.date(snapshot.as_of) %></td>
                <td :if={@row_action != []} class="row-actions">
                  <%= render_slot(@row_action, snapshot) %>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    <% end %>
    """
  end

  defp snapshot_path(id), do: "/snapshots?snapshot=#{id}"

  # -- the widget ---------------------------------------------------------------------

  attr(:item, :map, required: true)
  attr(:card, :any, required: true, doc: "nil while the read runs, :error, or `read/0`'s answer")
  attr(:selected_id, :any, required: true, doc: "the snapshot the dashboard compares")

  @doc "The widget „Snapshot-Liste“: the tab's list in its frame, the form linked."
  def widget(assigns) do
    ~H"""
    <Widget.frame
      id={"dashboard-snapshot-list" <> @item.uid}
      item={@item}
      title={Widgets.title("snapshot_list")}
      class="widget--single-form"
      full_href="/snapshots"
      full_label={gettext("New snapshot →")}
      full_role="snapshot-new"
    >
      <:info>
        <%= gettext(
          "The snapshots of GET /api/v1/snapshots, newest as-of date first: each one's name, scope and as-of date. A name picks the snapshot this dashboard compares; a snapshot is made and deleted on the Snapshots page."
        ) %>
      </:info>
      <:shared>
        <div :if={is_nil(@card)} class="section-skeleton" aria-busy="true" data-role="snapshot-list-skeleton"></div>
        <p :if={@card == :error} class="hint" data-role="snapshot-list-failed">
          <%= gettext("Couldn't load the snapshots.") %>
        </p>
        <.table
          :if={is_map(@card)}
          snapshots={@card.snapshots}
          views={@card.views}
          selected_id={@selected_id}
          pick={:event}
        />
      </:shared>
    </Widget.frame>
    """
  end
end
