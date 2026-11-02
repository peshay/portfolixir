defmodule PortfolixirWeb.JournalLive do
  @moduledoc """
  The Audit journal page (`/journal`; Sprint 23 V3, idea U2; board
  `ux-design-2026-11-02-sprint23/03-journal`, picks Q5 = A and Q6): the
  operator's view of `GET /api/v1/journal`, the read the agent has had since
  Sprint 19.

  One page in the API's shape: every entry newest first, the time in UTC,
  who made it, what was done and to which entry. The page reads its
  parameters from the URL with `PortfolixirWeb.Api.V1.JournalQuery`, the
  API's own reading, so a link the agent hands over opens the rows it read,
  and both users read one list. Read-only: nothing here writes.
  """
  use PortfolixirWeb, :live_view

  alias PortfolixirWeb.Api.V1.JournalQuery
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Journal.Row
  alias PortfolixirWeb.StoredText

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :current_path, "/journal")}
  end

  # The URL is the page's state, as `?since=` is the history's (#731): the
  # same parameters as the API, read by the API's own parser.
  @impl true
  def handle_params(params, _uri, socket) do
    opts = read_opts(params)
    {entries, truncated} = JournalQuery.list(opts)

    {:noreply,
     assign(socket,
       opts: opts,
       rows: Enum.map(entries, &Row.build/1),
       truncated: truncated
     )}
  end

  # A parameter the API would refuse with a 422 reads as absent here: the
  # page falls back to its default for it, as every page does with a URL it
  # cannot read (LiveParam, #868).
  defp read_opts(params, tries \\ 6)

  defp read_opts(params, tries) when tries > 0 do
    case JournalQuery.parse(params) do
      {:ok, opts} -> opts
      {:error, field} -> read_opts(Map.delete(params, Atom.to_string(field)), tries - 1)
    end
  end

  defp read_opts(_params, _tries) do
    {:ok, opts} = JournalQuery.parse(%{})
    opts
  end

  # An event this page does not know, or a payload it cannot read, changes
  # nothing (E25 S4, F17).
  @impl true
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell
      current_path="/journal"
      page_title={gettext("Audit journal")}
      page_subtitle={gettext("Every stored change, who made it and what stood before")}
    >
      <div id="journal-workspace" class="workspace-page">
        <section id="journal-panel" class="workspace-section" aria-labelledby="journal-title">
          <header class="section-head">
            <h2 id="journal-title"><%= gettext("Entries") %></h2>
          </header>

          <p class="summary-basis" data-role="journal-basis"><%= basis(@opts, @rows, @truncated) %></p>

          <%= if @rows == [] do %>
            <p id="journal-empty" class="empty-state" role="status">
              <%= gettext("No entry matches these filters.") %>
              <.link patch="/journal"><%= gettext("Show every entry") %></.link>
            </p>
          <% else %>
            <div class="data-table-wrapper journal-table-wrap">
              <table class="data-table journal-table">
                <thead>
                  <tr>
                    <th><%= gettext("Time (UTC)") %></th>
                    <th><%= gettext("Actor") %></th>
                    <th><%= gettext("Operation") %></th>
                    <th><%= gettext("Entry") %></th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={row <- @rows} id={"journal-entry-#{row.id}"} data-entry={row.id}>
                    <td class="cell-date"><%= row.time %></td>
                    <td class="cell-actor">
                      <%= row.actor %>
                      <small :if={row.actor_name} class="cell-note"><%= StoredText.bdi(row.actor_name) %></small>
                    </td>
                    <td class="cell-kind"><%= row.operation %></td>
                    <td class="cell-name"><%= StoredText.bdi(row.entity) %></td>
                  </tr>
                </tbody>
              </table>
            </div>
          <% end %>
        </section>
      </div>
    </AppShell.shell>
    """
  end

  # The basis line restates what the list is (UX-DR11): its order, its
  # size, the filters it applies and the time zone of its times.
  defp basis(opts, rows, _truncated) do
    count = ngettext("%{count} entry", "%{count} entries", length(rows))

    scenarios =
      if opts[:include_scenarios],
        do: gettext("with what-if scenarios"),
        else: gettext("without what-if scenarios")

    Enum.join([gettext("Newest first"), count, scenarios, gettext("times in UTC")], " · ")
  end
end
