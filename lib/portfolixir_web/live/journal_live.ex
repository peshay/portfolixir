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
  and both users read one list. Its filters are exactly the API's: the
  actor and the operation as chips, the kind as a select, the what-if
  scenarios as a checkbox, and „Nur dieser Eintrag“ for one entry
  (`resource_type` + `resource_id`). Each writes its parameter into the URL
  (`push_patch`), so a narrowed view is a link. Read-only: nothing here
  writes.

  `since` (Sprint 24 J3, I16; decision D-4, board
  `ux-design-2026-11-04-sprint24/01-journal-since`, pick Q1 = A) is the
  API's cut too, read by the same parser: a date, an instant or the cursor
  the API answered. The page lists the entries after it newest first, where
  the API answers them oldest first: the same rows, so a link
  `/journal?since=…` opens the slice the agent read, and „Ältere Einträge
  zeigen“ pages within the cut.
  """
  use PortfolixirWeb, :live_view

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Journal.Entry
  alias PortfolixirWeb.Api.V1.JournalQuery
  alias PortfolixirWeb.Api.V1.SinceParam
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.Journal.Row
  alias PortfolixirWeb.StoredText

  # The actor chips, in the board's order. A read-only token cannot write,
  # so it has no entry and no chip; the API's filter still takes it.
  @actor_chips [:owner_ui, :api_token_rw, :import_session, :system_job]

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
    security_names = security_names(entries)

    {:noreply,
     assign(socket,
       opts: opts,
       rows: Enum.map(entries, &Row.build(&1, security_names)),
       truncated: truncated
     )}
  end

  # The names of the securities the page's entries name only by id, read in
  # one query for the page (`Row.security_ids/1`), never one per row.
  defp security_names(entries) do
    entries
    |> Row.security_ids()
    |> Catalog.get_securities_by_ids()
    |> Map.new(fn {id, security} -> {id, security.name} end)
  end

  # A parameter the API would refuse with a 422 reads as absent here: the
  # page falls back to its default for it, as every page does with a URL it
  # cannot read (LiveParam, #868). The parser names only a parameter the
  # URL carries, so each round drops one and the reading ends.
  defp read_opts(params) do
    case JournalQuery.parse(params) do
      {:ok, opts} -> opts
      {:error, field} -> read_opts(Map.delete(params, Atom.to_string(field)))
    end
  end

  # A filter change starts the list from its newest page again.
  @impl true
  def handle_event("filter_actor", %{"actor_type" => value}, socket) when is_binary(value) do
    case enum_value(value, Actor.types()) do
      {:ok, actor_type} -> {:noreply, patch(socket, actor_type: actor_type, limit: nil)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("toggle_operation", %{"operation" => value}, socket) when is_binary(value) do
    case enum_value(value, Entry.operations()) do
      {:ok, operation} ->
        operation = if socket.assigns.opts[:operation] == operation, do: nil, else: operation
        {:noreply, patch(socket, operation: operation, limit: nil)}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("filter_form", %{"resource_type" => kind} = params, socket)
      when is_binary(kind) do
    kind = if kind == "", do: nil, else: kind

    # Another kind leaves the one entry „Nur dieser Eintrag“ chose.
    resource_id =
      if kind == socket.assigns.opts[:resource_type], do: socket.assigns.opts[:resource_id]

    {:noreply,
     patch(socket,
       resource_type: kind,
       resource_id: resource_id,
       since: form_since(params["since"], socket.assigns.opts[:since]),
       include_scenarios: params["include_scenarios"] == "true",
       limit: nil
     )}
  end

  # An event this page does not know, or a payload it cannot read, changes
  # nothing (E25 S4, F17).
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # The field „Seit“ (board 01 ①) holds a date. A cut handed over as an
  # instant or a cursor shows as its UTC date and is kept as handed over
  # while the field still shows that date, so another filter change does
  # not widen it to the day; an empty field is no cut. A value it cannot
  # read keeps the current cut (closing act, J3): a mistyped digit never
  # widens the list to the whole journal, and as nothing patches, the field
  # keeps the typed text with its `:invalid` mark (`pattern`).
  defp form_since(value, current) do
    cond do
      current && value == since_value(current) ->
        current

      value in [nil, ""] ->
        nil

      is_binary(value) ->
        case SinceParam.parse_page(%{"since" => value}) do
          {:ok, since} -> since
          {:error, :since} -> current
        end

      true ->
        current
    end
  end

  # The date the field shows for a cut: its UTC date, or empty.
  defp since_value(nil), do: ""
  defp since_value(%{cut: cut}), do: cut |> NaiveDateTime.to_date() |> Date.to_iso8601()

  defp enum_value("", _allowed), do: {:ok, nil}

  defp enum_value(value, allowed) do
    case Enum.find(allowed, &(Atom.to_string(&1) == value)) do
      nil -> :error
      atom -> {:ok, atom}
    end
  end

  # A change that leaves the page's URL as it is patches nothing, so the
  # page renders nothing anew and a field keeps what was typed into it.
  defp patch(socket, changes) do
    to = path(Keyword.merge(socket.assigns.opts, changes))
    if to == path(socket.assigns.opts), do: socket, else: push_patch(socket, to: to)
  end

  # The page's URL for `opts`, its parameters in one fixed order so a view
  # has one link: only what differs from the API's default is written.
  @doc false
  @spec path(keyword()) :: String.t()
  def path(opts) do
    default_limit = JournalQuery.default_limit()

    query =
      [
        resource_type: opts[:resource_type],
        resource_id: opts[:resource_id],
        actor_type: opts[:actor_type],
        operation: opts[:operation],
        since: opts[:since] && opts[:since].raw,
        include_scenarios: opts[:include_scenarios] == true || nil,
        limit: if(opts[:limit] in [nil, default_limit], do: nil, else: opts[:limit])
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    if query == [], do: "/journal", else: "/journal?" <> URI.encode_query(query)
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :actor_chips, @actor_chips)

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

          <%!-- Chips are toggles, so they carry aria-pressed (UX-DR7). --%>
          <div id="journal-chips" class="filter-chips" role="group" aria-label={gettext("Filter the journal")}>
            <span>
              <span class="filter-chips__family"><%= gettext("Actor") %></span>
              <button
                type="button"
                id="journal-chip-actor-all"
                class={["filter-chip", @opts[:actor_type] == nil && "is-active"]}
                aria-pressed={to_string(@opts[:actor_type] == nil)}
                phx-click="filter_actor"
                phx-value-actor_type=""
              >
                <%= gettext("All") %>
              </button>
              <button
                :for={type <- @actor_chips}
                type="button"
                id={"journal-chip-actor-#{type}"}
                class={["filter-chip", @opts[:actor_type] == type && "is-active"]}
                aria-pressed={to_string(@opts[:actor_type] == type)}
                phx-click="filter_actor"
                phx-value-actor_type={type}
              >
                <%= Row.actor_label(type) %>
              </button>
            </span>
            <span>
              <span class="filter-chips__family"><%= gettext("Operation") %></span>
              <button
                :for={operation <- Entry.operations()}
                type="button"
                id={"journal-chip-operation-#{operation}"}
                class={["filter-chip", @opts[:operation] == operation && "is-active"]}
                aria-pressed={to_string(@opts[:operation] == operation)}
                phx-click="toggle_operation"
                phx-value-operation={operation}
              >
                <%= Row.operation_label(operation) %>
              </button>
            </span>
          </div>

          <%!-- Enter in „Seit“ submits the form: to the page itself, read
               like a change, so the chips' filters stay (closing act, J3);
               a form without phx-submit would GET /journal from its own
               fields alone. --%>
          <form id="journal-filters" class="journal-filters" phx-change="filter_form" phx-submit="filter_form">
            <label class="journal-filters__kind">
              <span class="visually-hidden"><%= gettext("Kind") %></span>
              <select id="journal-kind" name="resource_type">
                <option value=""><%= gettext("All kinds") %></option>
                <option :for={kind <- kind_options(@opts)} value={kind} selected={@opts[:resource_type] == kind}>
                  <%= Row.kind_label(kind) %>
                </option>
              </select>
            </label>
            <%!-- The cut (board 01 ①): the app's ISO date input (UX-DR19),
                 empty for none, sent on blur so a half-typed date never
                 patches the cut away. --%>
            <label class="journal-filters__since">
              <%= gettext("Since") %>
              <input
                type="text"
                id="journal-since"
                name="since"
                value={since_value(@opts[:since])}
                placeholder="YYYY-MM-DD"
                pattern="[0-9]{4}-[0-9]{2}-[0-9]{2}"
                maxlength="10"
                autocomplete="off"
                phx-debounce="blur"
              />
            </label>
            <label class="journal-filters__scenarios">
              <input type="hidden" name="include_scenarios" value="false" />
              <input
                type="checkbox"
                id="journal-scenarios"
                name="include_scenarios"
                value="true"
                checked={@opts[:include_scenarios] == true}
              />
              <%= gettext("Include what-if scenarios") %>
            </label>
          </form>

          <p class="summary-basis" data-role="journal-basis"><%= basis(@opts, @rows, @truncated) %></p>

          <p :if={@opts[:resource_id]} class="hint" data-role="journal-entity-filter">
            <.link patch="/journal"><%= gettext("Show every entry") %></.link>
          </p>

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
                    <th><%= gettext("Change") %></th>
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
                    <td class="cell-name">
                      <.entity row={row} />
                      <small :if={row.resource_id} class="cell-note">
                        <.link patch={only_path(row)}><%= gettext("Only this entry") %></.link>
                      </small>
                    </td>
                    <td class="journal-change"><.change change={row.change} /></td>
                  </tr>
                </tbody>
              </table>
            </div>

            <%!-- Under 560 px the table gives way to two-line rows
                 (UX-DR27), as board 03's phone frame draws them: time,
                 operation and actor over the entry and its change. No
                 figure, so the row is one column and the fold opens full
                 width beneath. --%>
            <ul class="phone-rows journal-rows" aria-label={gettext("Entries")}>
              <li :for={row <- @rows} class="phone-row" data-entry={row.id}>
                <div class="phone-row__body">
                  <span class="phone-row__name">
                    <%= row.time %> · <%= row.operation %> · <%= row.actor %><span :if={row.actor_name}> (<%= StoredText.bdi(row.actor_name) %>)</span>
                  </span>
                  <span class="phone-row__ids">
                    <.entity row={row} />
                    <.link :if={row.resource_id} patch={only_path(row)}><%= gettext("Only this entry") %></.link>
                  </span>
                </div>
                <div class="journal-change"><.change change={row.change} /></div>
              </li>
            </ul>

            <%!-- Paged like the API (#1254): the limit grows by one page
                 until the API's maximum, which a filter reaches past. --%>
            <p :if={@truncated and not at_max?(@opts)} class="journal-more">
              <.link patch={path(Keyword.put(@opts, :limit, next_limit(@opts)))} data-role="journal-more">
                <%= gettext("Show older entries") %>
              </.link>
            </p>
            <p :if={@truncated and at_max?(@opts)} class="hint" data-role="journal-at-max">
              <%= gettext(
                "The newest %{max} are shown, the most one page holds; a filter reaches older entries.",
                max: JournalQuery.max_limit()
              ) %>
            </p>
          <% end %>
        </section>
      </div>
    </AppShell.shell>
    """
  end

  attr(:row, :map, required: true)

  # The entry links its page where it has one; a deleted one reads as text.
  defp entity(assigns) do
    ~H"""
    <a :if={@row.href} href={@row.href}><%= StoredText.bdi(@row.entity) %></a>
    <span :if={!@row.href}><%= StoredText.bdi(@row.entity) %></span>
    """
  end

  attr(:change, :map, required: true)

  # One line per changed field, the old value struck and muted, then the
  # stored values folded, reduced to the fields that changed (board 03 ③).
  # A delete reads the operation: „gelöscht, mit allen Werten“.
  defp change(assigns) do
    ~H"""
    <%= for line <- @change.lines do %>
      <%= case line do %>
        <% :deleted -> %>
          <span class="journal-change__line"><%= gettext("deleted, with every value") %></span>
        <% {field, from, to} -> %>
          <span class="journal-change__line"><%= change_line(field, from, to) %></span>
      <% end %>
    <% end %>
    <details :if={@change.values != []} class="journal-values">
      <summary class="disclosure-summary">
        <AppShell.icon name={:chevron_right} size={12} class="disclosure-chevron" />
        <%= gettext("Stored values") %>
      </summary>
      <table>
        <thead>
          <tr>
            <th scope="col"><%= gettext("Field") %></th>
            <th scope="col"><%= gettext("Before") %></th>
            <th scope="col"><%= gettext("After") %></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={{field, before, after_value} <- @change.values}>
            <td><%= field %></td>
            <td><%= StoredText.bdi(before) %></td>
            <td><%= StoredText.bdi(after_value) %></td>
          </tr>
        </tbody>
      </table>
    </details>
    """
  end

  # „name: Festgeld → Festgeld Plus“: the old value struck and muted, the
  # arrow for the eye and „geändert in“ for a screen reader. Built as one
  # piece of markup so its spaces sit inside its text, not between tags.
  defp change_line(field, from, to) do
    {:safe,
     [
       ~s(<span class="journal-change__field">),
       escape(field),
       ": </span>",
       ~s(<span class="journal-change__from">),
       safe(StoredText.bdi(from)),
       "</span>",
       ~s(<span class="journal-change__arrow" aria-hidden="true"> → </span>),
       ~s(<span class="visually-hidden"> ),
       escape(gettext("changed to")),
       " </span>",
       safe(StoredText.bdi(to))
     ]}
  end

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> safe()
  defp safe({:safe, iodata}), do: iodata

  # „Nur dieser Eintrag“: the entry's own history, every actor and operation.
  defp only_path(row), do: path(resource_type: row.resource_type, resource_id: row.resource_id)

  # The kinds the select offers; a kind the URL names that no label knows
  # yet is offered too, so the select shows what the list is filtered by.
  defp kind_options(opts) do
    kinds = Row.kinds()

    case opts[:resource_type] do
      nil -> kinds
      kind -> if kind in kinds, do: kinds, else: kinds ++ [kind]
    end
  end

  # The basis line restates what the list is (UX-DR11): its order, its
  # size, the filters it applies and the time zone of its times.
  defp basis(opts, rows, truncated) do
    clauses = [
      gettext("Newest first"),
      opts[:since] && gettext("since %{date} (UTC)", date: cut_label(opts[:since])),
      count_clause(length(rows), truncated),
      opts[:actor_type] && gettext("actor %{actor}", actor: Row.actor_label(opts[:actor_type])),
      opts[:operation] &&
        gettext("operation %{operation}", operation: Row.operation_label(opts[:operation])),
      entity_clause(opts),
      if(opts[:include_scenarios],
        do: gettext("with what-if scenarios"),
        else: gettext("without what-if scenarios")
      ),
      gettext("times in UTC")
    ]

    clauses |> Enum.reject(&(&1 in [nil, false])) |> Enum.join(" · ")
  end

  # The cut as it was handed over (board 01 ②): a date as the date, an
  # instant (or the API's cursor) as its UTC time to the second. A date is
  # the `since` that reads as its own cut's day; the parser has read it.
  defp cut_label(%{raw: raw, cut: cut} = since) do
    if raw == since_value(since),
      do: cut |> NaiveDateTime.to_date() |> Format.date(),
      else: cut |> DateTime.from_naive!("Etc/UTC") |> Row.time()
  end

  # A cut answer says so (UX-DR26): "the newest 100", never "100".
  defp count_clause(count, true = _truncated),
    do: ngettext("the newest %{count} entry", "the newest %{count} entries", count)

  defp count_clause(count, false = _truncated),
    do: ngettext("%{count} entry", "%{count} entries", count)

  # The API's paging: a larger limit, until its maximum.
  defp next_limit(opts),
    do: min(opts[:limit] + JournalQuery.default_limit(), JournalQuery.max_limit())

  defp at_max?(opts), do: opts[:limit] >= JournalQuery.max_limit()

  defp entity_clause(opts) do
    case {opts[:resource_type], opts[:resource_id]} do
      {nil, nil} ->
        nil

      {nil, id} ->
        gettext("only %{entry}", entry: id)

      {kind, nil} ->
        gettext("kind %{kind}", kind: Row.kind_label(kind))

      {kind, id} ->
        gettext("only %{entry}", entry: Row.kind_label(kind) <> " " <> id)
    end
  end
end
