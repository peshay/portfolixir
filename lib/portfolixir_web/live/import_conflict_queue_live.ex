defmodule PortfolixirWeb.ImportConflictQueueLive do
  use PortfolixirWeb, :live_view

  alias Portfolixir.Imports
  alias PortfolixirWeb.AppShell

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:open_conflicts, Imports.list_open_import_conflicts())
      |> assign(:resolved_conflicts, Imports.list_resolved_import_conflicts())

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell current_path="/imports/conflicts">
      <header class="app-shell-page-header">
        <div>
          <p class="app-shell-page-kicker"><%= gettext("Imports") %></p>
          <h1><%= gettext("Import conflicts") %></h1>
          <p>
            <%= gettext("Read-only review queue for open and resolved import conflicts.") %>
          </p>
        </div>
      </header>

      <%= if Enum.empty?(@open_conflicts) and Enum.empty?(@resolved_conflicts) do %>
        <section id="import-conflicts-empty-state" class="app-shell-empty-state">
          <h2><%= gettext("No import conflicts queued") %></h2>
          <p><%= gettext("Open and resolved conflicts will appear here after import runs.") %></p>
        </section>
      <% else %>
        <section id="import-conflicts-open-section" class="app-shell-section-card">
          <div class="app-shell-section-header">
            <div>
              <h2 class="app-shell-section-title"><%= gettext("Open conflicts") %></h2>
              <p><%= gettext("Actionable import conflicts that still require review.") %></p>
            </div>
          </div>

          <%= if Enum.empty?(@open_conflicts) do %>
            <div id="import-conflicts-open-empty-state" class="app-shell-empty-state">
              <h3><%= gettext("No open conflicts") %></h3>
            </div>
          <% else %>
            <.conflict_table id="import-conflicts-open-table" conflicts={@open_conflicts} row_prefix="open" />
          <% end %>
        </section>

        <section id="import-conflicts-resolved-section" class="app-shell-section-card">
          <div class="app-shell-section-header">
            <div>
              <h2 class="app-shell-section-title"><%= gettext("Resolved conflicts") %></h2>
              <p><%= gettext("Historical conflicts that were already resolved.") %></p>
            </div>
          </div>

          <%= if Enum.empty?(@resolved_conflicts) do %>
            <div id="import-conflicts-resolved-empty-state" class="app-shell-empty-state">
              <h3><%= gettext("No resolved conflicts") %></h3>
            </div>
          <% else %>
            <.conflict_table
              id="import-conflicts-resolved-table"
              conflicts={@resolved_conflicts}
              row_prefix="resolved"
            />
          <% end %>
        </section>
      <% end %>
    </AppShell.shell>
    """
  end

  attr(:id, :string, required: true)
  attr(:conflicts, :list, required: true)
  attr(:row_prefix, :string, required: true)

  defp conflict_table(assigns) do
    ~H"""
    <div class="app-shell-table-wrapper">
      <table id={@id} aria-describedby={"#{@id}-caption"}>
        <caption id={"#{@id}-caption"} class="app-shell-visually-hidden">
          <%= conflict_table_caption(@row_prefix) %>
        </caption>
        <thead>
          <tr>
            <th scope="col"><%= gettext("Source") %></th>
            <th scope="col"><%= gettext("Run") %></th>
            <th scope="col"><%= gettext("Type") %></th>
            <th scope="col"><%= gettext("Summary") %></th>
            <th scope="col"><%= gettext("Raised at") %></th>
            <th scope="col"><%= gettext("Raw item") %></th>
          </tr>
        </thead>
        <tbody>
          <%= for conflict <- @conflicts do %>
            <tr id={"import-conflict-#{@row_prefix}-row-#{conflict.id}"}>
              <td><%= conflict.import_source.name %></td>
              <td><%= conflict.import_run_id %></td>
              <td><%= conflict.conflict_type %></td>
              <td><%= conflict.summary %></td>
              <td><%= format_datetime(conflict.inserted_at) %></td>
              <td>
                <%= if conflict.raw_import_item_id do %>
                  <a
                    id={"import-conflict-review-link-#{conflict.id}"}
                    href={"/imports/raw-items/#{conflict.raw_import_item_id}/review"}
                  >
                    <%= gettext("Review raw item") %>
                  </a>
                <% else %>
                  <span id={"import-conflict-no-review-link-#{conflict.id}"}><%= gettext("—") %></span>
                <% end %>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  defp format_datetime(nil), do: gettext("—")

  defp format_datetime(datetime) when is_struct(datetime, DateTime) do
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp format_datetime(datetime) when is_struct(datetime, NaiveDateTime) do
    datetime
    |> NaiveDateTime.truncate(:second)
    |> NaiveDateTime.to_iso8601()
  end

  defp conflict_table_caption("open") do
    gettext(
      "Open import conflicts table with source, run, type, summary, raised timestamp, and raw item review link."
    )
  end

  defp conflict_table_caption("resolved") do
    gettext(
      "Resolved import conflicts table with source, run, type, summary, raised timestamp, and raw item review link."
    )
  end

  defp conflict_table_caption(_row_prefix) do
    gettext(
      "Import conflicts table with source, run, type, summary, raised timestamp, and raw item review link."
    )
  end
end
