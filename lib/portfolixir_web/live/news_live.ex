defmodule PortfolixirWeb.NewsLive do
  @moduledoc """
  The page „Nachrichten“ (`/news`; Sprint 28 N7, ADR-0056 §10; board
  `ux-design-2026-11-08-sprint28/01`, variant A; plan D-5): the operator's
  view of the news reads the agent has had since Sprint 27.

  **No logic of its own.** Each region reads through the context function
  the API's read answers from, with the API's defaults, so the screen
  states what the agent reads for the same request (plan D-1, criterion
  6):

    * the health line on every tab — `Portfolixir.News.health/1`
      (`GET /api/v1/news/health`), its feeds and its day counted;
    * „Meldungen“: the queue — `Portfolixir.News.Reads.list/2` with
      `assignment` `ambiguous` and `unassigned` (`news.list`); the digest per
      security — `Portfolixir.News.Reads.digest/5` in its **stateless**
      `since` mode (`news.digest` without `consumer`: the screen keeps no
      consumer and never moves an agent's cursor), `since` the URL's (the
      API's parser) or the API's default of 24 hours;
    * „Feeds“: each registered feed (`Portfolixir.News.registry/1`, the
      read `GET /api/v1/news/registry` pages: URL, class, binding,
      language, paused) beside its `health/1` fields;
    * „Quellen“: the rated domains, from the same `registry/1`.

  **One write**, the view's only action (§10): „Zuordnen“ assigns a queue
  item through `Portfolixir.News.assign_item/4`, the function
  `news.assign` calls, journaled under the UI actor. Feeds and sources
  are registered, rated and deleted through the API and the companion; the
  page shows them (plan D-3).

  The tab is the address: `/news`, `/news?tab=feeds`, `/news?tab=sources`;
  a tab the page does not know opens „Meldungen“. Stored foreign text — a
  title, a domain, a URL, an error code — is shown with every invisible
  character spelled `[U+XXXX]` and isolated in `<bdi>` (ADR-0054 §4).
  """
  use PortfolixirWeb, :live_view

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Input.Text
  alias Portfolixir.News
  alias Portfolixir.News.Reads
  alias PortfolixirWeb.Api.V1.SinceParam
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.EventTypeLabel
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.LiveParam
  alias PortfolixirWeb.SecurityNames
  alias PortfolixirWeb.StoredText

  @tabs %{"feeds" => :feeds, "sources" => :sources}

  # The API's defaults (`PortfolixirWeb.Api.V1.NewsReadController`): a
  # list page of 20, the digest's 24 hours, its 12 rows and its
  # materiality of 2, without unlabelled stories.
  @list_limit 20
  @digest_window_seconds 24 * 60 * 60
  @digest_rows 12
  @digest_min_materiality 2

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, current_path: "/news", result: nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = Map.get(@tabs, params["tab"], :reports)

    {:noreply,
     socket
     |> assign(tab: tab, since_param: since_param(params))
     |> load()}
  end

  # The tab's reads, and the health line every tab carries.
  defp load(socket) do
    health = News.health(DateTime.utc_now())
    socket = assign(socket, :health, health)

    case socket.assigns.tab do
      :reports -> load_reports(socket)
      :feeds -> assign(socket, :feeds, feed_rows(health))
      :sources -> assign(socket, :sources, News.registry().sources)
    end
  end

  defp load_reports(socket) do
    version = News.newest_prompt_version()
    queue = read_queue(version)
    since = digest_since(socket.assigns.since_param)
    {:ok, security_ids} = Reads.digest_securities(nil)

    digest =
      Reads.digest(security_ids, since, false, @digest_rows,
        view: false,
        min_materiality: @digest_min_materiality,
        prompt_version: version,
        labelled_since: nil,
        after: {nil, nil}
      )

    {choices, names} = picker_names(News.assign_choices(), queue.rows)

    assign(socket,
      queue: queue,
      choices: choices,
      names: names,
      digest: Map.update!(digest, :rows, &full_names/1),
      since: since
    )
  end

  # The remainder, as news.list answers `assignment=ambiguous` and
  # `assignment=unassigned`: the ambiguous first, each newest first.
  defp read_queue(version) do
    opts = [
      since: nil,
      tier_min: nil,
      limit: @list_limit,
      cursor: nil,
      as_of: Reads.as_of(),
      min_materiality: 0,
      prompt_version: version
    ]

    pages =
      for assignment <- [:ambiguous, :unassigned] do
        {:ok, page} = Reads.list({:assignment, assignment}, opts)
        {assignment, page}
      end

    %{
      rows: for({assignment, page} <- pages, row <- page.rows, do: {assignment, row}),
      truncated: Enum.any?(pages, fn {_assignment, page} -> page.truncated end)
    }
  end

  # The picker's names, the universe's and the candidates', with same-named
  # securities told apart over both lists as every picker does (UAT-13;
  # the Sprint 28 closing act's UAT line on N7).
  defp picker_names(choices, rows) do
    candidates =
      rows
      |> Enum.flat_map(fn {_assignment, row} -> row.candidates end)
      |> Catalog.get_securities_by_ids()

    tags = SecurityNames.tags(choices ++ Map.values(candidates))

    {Enum.map(choices, &{&1.id, SecurityNames.label(tags, &1)}),
     Map.new(candidates, fn {id, security} -> {id, SecurityNames.label(tags, security)} end)}
  end

  # The digest names a security by its short name (§9's 20 characters, a
  # budget of the agent's); the page has the room for the whole name.
  defp full_names(rows) do
    names = rows |> Enum.map(& &1.id) |> Catalog.get_securities_by_ids()

    Enum.map(
      rows,
      &Map.put(&1, :full_name, names |> Map.get(&1.id, %{name: &1.name}) |> Map.get(:name))
    )
  end

  # `since` as the API reads it (`SinceParam`); none, or one it cannot
  # read, is the API's default window.
  defp since_param(params) do
    case SinceParam.parse(Map.take(params, ["since"])) do
      {:ok, %{cut: cut}} -> DateTime.from_naive!(cut, "Etc/UTC")
      _none -> nil
    end
  end

  defp digest_since(nil),
    do: DateTime.add(DateTime.utc_now(), -@digest_window_seconds, :second)

  defp digest_since(%DateTime{} = since), do: since

  # Each registered feed, as news.registry lists it, with its health (a
  # feed registered between the two reads shows from the next load).
  defp feed_rows(health) do
    health_by_id = Map.new(health.feeds, &{&1.id, &1})

    for registration <- News.registry().feeds,
        feed = Map.get(health_by_id, registration.id),
        do: Map.put(feed, :registration, registration)
  end

  # --- the one write ----------------------------------------------------------

  @impl true
  def handle_event("assign_item", %{"item_id" => item, "security_id" => security}, socket) do
    with {:ok, item_id} <- LiveParam.fetch_id(item),
         {:ok, security_id} <- chosen(security),
         {:ok, assigned} <- News.assign_item(Actor.owner_ui(), item_id, security_id) do
      name = Catalog.get_security!(assigned.security_id).name

      {:noreply,
       socket
       |> assign(:result, {:note, assigned_message(name)})
       |> load()}
    else
      :none ->
        {:noreply, assign(socket, :result, {:attention, gettext("Choose a security first.")})}

      _refused ->
        {:noreply,
         socket
         |> assign(
           :result,
           {:problem, gettext("The item could not be assigned; it may have moved meanwhile.")}
         )
         |> load()}
    end
  end

  def handle_event("dismiss_result", _params, socket),
    do: {:noreply, assign(socket, :result, nil)}

  # An event this page does not know, or a payload it cannot read, changes
  # nothing (E25 S4, F17).
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp chosen(value) do
    case LiveParam.fetch_id(value) do
      {:ok, id} -> {:ok, id}
      :error -> :none
    end
  end

  defp assigned_message(name) do
    StoredText.isolate(
      gettext("The item is assigned to %{security}.", security: StoredText.slot(:security)),
      security: name
    )
  end

  # --- render -----------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell page_address={@page_address}
      current_path={@current_path}
      page_title={gettext("News")}
      page_subtitle={gettext("What the feeds deliver, as the agent sees it")}
    >
      <div id="news-workspace" class="workspace-page">
        <AppShell.area_tabs id="news-tabs" patch tabs={tabs(@tab)} />

        <.health_line health={@health} />

        <%= case @tab do %>
          <% :reports -> %>
            <.queue queue={@queue} choices={@choices} names={@names} result={@result} />
            <.digest digest={@digest} since={@since} />
          <% :feeds -> %>
            <.feeds feeds={@feeds} />
          <% :sources -> %>
            <.sources sources={@sources} />
        <% end %>
      </div>
    </AppShell.shell>
    """
  end

  defp tabs(current) do
    [
      %{label: gettext("Reports"), href: "/news", current: current == :reports, icon: :newspaper},
      %{
        label: gettext("Feeds"),
        href: "/news?tab=feeds",
        current: current == :feeds,
        icon: :signal
      },
      %{
        label: gettext("Sources"),
        href: "/news?tab=sources",
        current: current == :sources,
        icon: :globe
      }
    ]
  end

  attr(:health, :map, required: true)

  # The health line (§6): news.health's feeds and its day, counted.
  defp health_line(assigns) do
    feeds = assigns.health.feeds
    day = assigns.health.day

    assigns =
      assign(assigns,
        count: length(feeds),
        stale: Enum.count(feeds, & &1.stale),
        low_yield: Enum.count(feeds, & &1.low_yield),
        errors: feeds |> Enum.map(& &1.err_24h) |> Enum.sum(),
        items: feeds |> Enum.map(& &1.items_24h) |> Enum.sum(),
        day: day,
        dropped: day.dropped.cap + day.dropped.no_source + day.dropped.old + day.blocked
      )

    ~H"""
    <section id="news-health" class="workspace-section workspace-section--controls news-health" aria-label={gettext("Collector health")}>
      <span class="badge badge--neutral" data-role="news-health-feeds">
        <%= ngettext("%{count} feed", "%{count} feeds", @count) %>
      </span>
      <span class={["badge", if(@stale > 0, do: "badge-warning", else: "badge--neutral")]} data-role="news-health-stale">
        <%= ngettext("%{count} stale", "%{count} stale", @stale) %>
      </span>
      <span :if={@low_yield > 0} class="badge badge-warning" data-role="news-health-low-yield">
        <%= ngettext("%{count} with low yield", "%{count} with low yield", @low_yield) %>
      </span>
      <span class={["badge", if(@errors > 0, do: "badge--danger", else: "badge--neutral")]} data-role="news-health-errors">
        <%= ngettext("%{count} error (today and yesterday)", "%{count} errors (today and yesterday)", @errors) %>
      </span>
      <span class="badge badge--neutral" data-role="news-health-items">
        <%= ngettext("%{count} item in 24 h", "%{count} items in 24 h", @items) %>
      </span>
      <span class="badge badge--neutral" data-role="news-health-open">
        <%= gettext("today %{unassigned} unassigned · %{ambiguous} ambiguous",
          unassigned: @day.unassigned,
          ambiguous: @day.ambiguous
        ) %>
      </span>
      <span :if={@dropped > 0} class="badge badge--neutral" data-role="news-health-dropped">
        <%= ngettext(
          "today %{count} dropped, %{blocked} of them from blocked sources",
          "today %{count} dropped, %{blocked} of them from blocked sources",
          @dropped,
          blocked: @day.blocked
        ) %>
      </span>
    </section>
    """
  end

  attr(:queue, :map, required: true)
  attr(:choices, :list, required: true)
  attr(:names, :map, required: true)
  attr(:result, :any, required: true)

  # „Zuzuordnen“: the ambiguous and unassigned items, each with the picker.
  defp queue(assigns) do
    ~H"""
    <section id="news-queue" class="workspace-section news-section" aria-labelledby="news-queue-title">
      <header class="section-head">
        <div class="section-title">
          <h2 id="news-queue-title" class="result-focus-fallback" tabindex="-1"><%= gettext("To assign") %></h2>
          <AppShell.section_info>
            <:line>
              <%= gettext(
                "An aggregator's item is filed under the one security its title names; none named leaves it unassigned, several leave it ambiguous with them as candidates."
              ) %>
            </:line>
            <:line>
              <%= gettext(
                "„Assign“ files it under the security chosen, as the agent's news.assign does, and its stories are regrouped at once; the journal records the operator as its author."
              ) %>
            </:line>
          </AppShell.section_info>
        </div>
      </header>

      <AppShell.inline_result id="news-assign-result" result={@result} focus_fallback="#news-queue-title" />

      <%= if @queue.rows == [] do %>
        <p id="news-queue-empty" class="empty-state" role="status">
          <%= gettext("Nothing to assign: every aggregator item names one security or none of the universe has come in.") %>
        </p>
      <% else %>
        <p class="summary-basis" data-role="news-queue-basis"><%= queue_basis(@queue) %></p>
        <div id="news-queue-table-wrap" class="data-table-wrapper news-table-wrap">
          <table id="news-queue-table" class="data-table news-table">
            <thead>
              <tr>
                <th><%= gettext("Item") %></th>
                <th><%= gettext("Source") %></th>
                <th><%= gettext("Time") %></th>
                <th><%= gettext("Assign") %></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={{assignment, row} <- @queue.rows} data-item={row.id}>
                <td class="news-cell-title">
                  <span class="news-title" data-role="queue-title"><%= foreign(row.title) %></span>
                  <span class="news-sub" data-role="queue-state"><%= queue_state(assignment, row, @names) %></span>
                </td>
                <td data-role="queue-source" class="news-cell-source">
                  <%= foreign(row.domain) %> <.tier tier={row.tier} />
                </td>
                <td data-role="queue-time" class="news-cell-time"><%= time(row.at) %></td>
                <td><.assign_form row={row} choices={@choices} names={@names} /></td>
              </tr>
            </tbody>
          </table>
        </div>
        <ul id="news-queue-phone-rows" class="phone-rows news-rows" aria-label={gettext("To assign")}>
          <li :for={{assignment, row} <- @queue.rows} class="phone-row" data-item={row.id}>
            <div class="phone-row__body">
              <span class="phone-row__name"><%= foreign(row.title) %></span>
              <span class="phone-row__ids">
                <%= foreign(row.domain) %> <.tier tier={row.tier} /> · <%= time(row.at) %>
              </span>
              <span class="phone-row__ids"><%= queue_state(assignment, row, @names) %></span>
              <.assign_form row={row} choices={@choices} names={@names} id_prefix="news-assign-phone" />
            </div>
          </li>
        </ul>
      <% end %>
    </section>
    """
  end

  attr(:row, :map, required: true)
  attr(:choices, :list, required: true)
  attr(:names, :map, required: true)
  attr(:id_prefix, :string, default: "news-assign")

  # The picker: the item's candidates first, then the universe.
  defp assign_form(assigns) do
    candidates = Enum.map(assigns.row.candidates, &{&1, Map.get(assigns.names, &1, "##{&1}")})
    others = Enum.reject(assigns.choices, fn {id, _name} -> id in assigns.row.candidates end)
    assigns = assign(assigns, candidates: candidates, others: others)

    ~H"""
    <form id={"#{@id_prefix}-#{@row.id}"} class="news-assign" phx-submit="assign_item">
      <input type="hidden" name="item_id" value={@row.id} />
      <label class="visually-hidden" for={"#{@id_prefix}-#{@row.id}-security"}><%= gettext("Security") %></label>
      <select id={"#{@id_prefix}-#{@row.id}-security"} name="security_id">
        <option value=""><%= gettext("— choose a security —") %></option>
        <optgroup :if={@candidates != []} label={gettext("Candidates")}>
          <option :for={{id, name} <- @candidates} value={id}><%= name %></option>
        </optgroup>
        <optgroup :if={@others != []} label={if @candidates != [], do: gettext("Other securities"), else: gettext("Securities")}>
          <option :for={{id, name} <- @others} value={id}><%= name %></option>
        </optgroup>
      </select>
      <button type="submit" class="button-ghost"><%= gettext("Assign") %></button>
    </form>
    """
  end

  attr(:digest, :map, required: true)
  attr(:since, :any, required: true)

  # „Neu je Wertpapier“: news.digest's rows, then what it left out.
  defp digest(assigns) do
    ~H"""
    <section id="news-digest" class="workspace-section news-section" aria-labelledby="news-digest-title">
      <header class="section-head">
        <div class="section-title">
          <h2 id="news-digest-title"><%= gettext("New per security") %></h2>
          <AppShell.section_info>
            <:line>
              <%= gettext(
                "The agent's digest, read without a reader of its own: opening this page moves no agent's position."
              ) %>
            </:line>
            <:line>
              <%= gettext(
                "A story counts when one of its items came in after the cut. An issuer's or a regulator's story always shows; an aggregator's or a thematic one shows when its label's materiality is 2 or more, and is counted as hidden otherwise."
              ) %>
            </:line>
            <:line>
              <%= gettext(
                "A label is an outside model's reading, marked „machine-made“; it sorts the rows and hides nothing an issuer or a regulator said."
              ) %>
            </:line>
            <%!-- Closing act of Sprint 28, ND4: the two columns pick by
                 different rules, so the ⓘ says which. --%>
            <:line>
              <%= gettext(
                "„Newest from the best source“ is the newest story of the row's best tier; „Label“ sums up all its new stories, their highest materiality and their event types, so the two can name different stories."
              ) %>
            </:line>
          </AppShell.section_info>
        </div>
      </header>

      <p class="summary-basis" data-role="news-digest-basis"><%= digest_basis(@since) %></p>

      <%= if @digest.rows == [] and (@digest.categories || []) == [] do %>
        <p id="news-digest-empty" class="empty-state" role="status">
          <%= gettext("Nothing new since the cut.") %>
        </p>
      <% else %>
        <div id="news-digest-table-wrap" class="data-table-wrapper news-table-wrap">
          <table id="news-digest-table" class="data-table news-table">
            <thead>
              <tr>
                <th><%= gettext("Security") %></th>
                <th class="num"><%= gettext("Stories") %></th>
                <th><%= gettext("Newest from the best source") %></th>
                <th><%= gettext("Label") %></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- @digest.rows} data-security={row.id}>
                <td data-role="digest-name">
                  <a href={"/securities/#{row.id}"}><%= StoredText.bdi(row.full_name) %></a>
                </td>
                <td class="num" data-role="digest-count"><%= row.count %></td>
                <td data-role="digest-top" class="news-cell-title"><.top top={row.top} /></td>
                <td data-role="digest-label"><.label row={row} /></td>
              </tr>
              <tr :for={row <- @digest.categories || []} data-category={row.id}>
                <td data-role="digest-name"><%= StoredText.bdi(row.name) %></td>
                <td class="num" data-role="digest-count"><%= row.count %></td>
                <td data-role="digest-top" class="news-cell-title"><.top top={row.top} /></td>
                <td data-role="digest-label"><.label row={row} /></td>
              </tr>
            </tbody>
          </table>
        </div>
        <ul id="news-digest-phone-rows" class="phone-rows news-rows" aria-label={gettext("New per security")}>
          <li :for={row <- @digest.rows ++ (@digest.categories || [])} class="phone-row">
            <div class="phone-row__body">
              <span class="phone-row__name"><%= StoredText.bdi(row[:full_name] || row.name) %></span>
              <span class="phone-row__ids"><.top top={row.top} /></span>
              <span class="phone-row__ids"><.label row={row} /></span>
            </div>
            <div class="phone-row__figures">
              <span class="phone-row__figure"><%= row.count %></span>
            </div>
          </li>
        </ul>
      <% end %>

      <p class="hint" data-role="digest-left-out"><%= left_out(@digest) %></p>
    </section>
    """
  end

  attr(:top, :map, required: true)

  defp top(assigns) do
    ~H"""
    <span class="news-title"><%= foreign(@top.title) %></span>
    <span class="news-sub"><.tier tier={@top.tier} /> · <%= time(@top.at) %></span>
    """
  end

  attr(:row, :map, required: true)

  # A row's label (§7): its event types in words (S28 N8,
  # `PortfolixirWeb.EventTypeLabel`) and highest materiality, marked
  # machine-made; none, „ohne Einordnung“.
  defp label(assigns) do
    ~H"""
    <%= if @row.materiality do %>
      <span class="news-label">
        <%= Enum.map_join(@row.event_types || [], ", ", &EventTypeLabel.event_type/1) %> · <%= gettext("materiality %{value}", value: @row.materiality) %>
        <span class="badge badge--neutral"><%= gettext("machine-made") %></span>
      </span>
    <% else %>
      <span class="news-label news-label--none"><%= gettext("no label") %></span>
    <% end %>
    """
  end

  attr(:feeds, :list, required: true)

  # „Feeds“: each feed with news.health's fields and its state (§6, A3).
  defp feeds(assigns) do
    ~H"""
    <section id="news-feeds" class="workspace-section news-section" aria-labelledby="news-feeds-title">
      <header class="section-head">
        <div class="section-title">
          <h2 id="news-feeds-title"><%= gettext("Feeds") %></h2>
          <AppShell.section_info>
            <:line>
              <%= gettext(
                "„Stale“: no successful fetch for 24 hours; a paused feed is never stale."
              ) %>
            </:line>
            <:line>
              <%= gettext(
                "Errors are counted per server day, today's and yesterday's, so up to 48 hours."
              ) %>
            </:line>
            <:line>
              <%= gettext(
                "Yield: the stories kept in the research log over the items of 30 days; „low yield“ is at least 50 items and none kept. Nothing switches a feed off by itself."
              ) %>
            </:line>
            <:line>
              <%= gettext(
                "Feeds are registered, changed and removed through the API and the agent; this page shows them."
              ) %>
            </:line>
          </AppShell.section_info>
        </div>
      </header>

      <%= if @feeds == [] do %>
        <p id="news-feeds-empty" class="empty-state" role="status">
          <%= gettext("No feed is registered yet. Feeds are registered over the API or MCP.") %>
        </p>
      <% else %>
        <p class="summary-basis" data-role="news-feeds-basis">
          <%= gettext("In order of registration · counts by first sight · times in UTC") %>
        </p>
        <div id="news-feeds-table-wrap" class="data-table-wrapper news-table-wrap">
          <table id="news-feeds-table" class="data-table news-table">
            <thead>
              <tr>
                <th><%= gettext("Feed") %></th>
                <th><%= gettext("Class") %></th>
                <th><%= gettext("Binding") %></th>
                <th><%= gettext("Last good fetch") %></th>
                <th class="num"><%= gettext("24 h") %></th>
                <th class="num"><%= gettext("Errors") %></th>
                <th class="num"><%= gettext("30 d") %></th>
                <th class="num"><%= gettext("Kept") %></th>
                <th class="num"><%= gettext("Yield") %></th>
                <th><%= pgettext("news feed", "State") %></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={feed <- @feeds} data-feed={feed.id}>
                <td class="news-cell-title">
                  <span class="news-url" data-role="feed-url"><%= feed_url(feed) %></span>
                  <span :if={feed.last_error} class="news-sub" data-role="feed-last-error">
                    <%= gettext("last error:") %> <%= foreign(feed.last_error) %>
                  </span>
                </td>
                <td data-role="feed-class"><%= feed.class %></td>
                <td>
                  <span data-role="feed-binding"><.feed_binding feed={feed} /></span>
                  · <span data-role="feed-language"><%= feed.registration.language %></span>
                </td>
                <td data-role="feed-last-ok" class="news-cell-time"><%= time(feed.last_ok_at) %></td>
                <td class="num" data-role="feed-items-24h"><%= feed.items_24h %></td>
                <td class="num" data-role="feed-errors"><%= feed.err_24h %></td>
                <td class="num" data-role="feed-items-30d"><%= feed.items_30d %></td>
                <td class="num" data-role="feed-promoted"><%= feed.promoted_30d %></td>
                <td class="num" data-role="feed-yield"><%= yield(feed.yield_30d) %></td>
                <td data-role="feed-state"><.feed_state feed={feed} /></td>
              </tr>
            </tbody>
          </table>
        </div>
        <ul id="news-feeds-phone-rows" class="phone-rows news-rows" aria-label={gettext("Feeds")}>
          <li :for={feed <- @feeds} class="phone-row" data-feed={feed.id}>
            <div class="phone-row__body">
              <span class="phone-row__name news-url"><%= feed_url(feed) %></span>
              <span class="phone-row__ids">
                <%= feed.class %> · <.feed_binding feed={feed} /> · <%= feed.registration.language %> · <%= time(feed.last_ok_at) %>
              </span>
              <span class="phone-row__ids">
                <%= gettext("%{items} in 30 d · %{kept} kept · yield %{yield}",
                  items: feed.items_30d,
                  kept: feed.promoted_30d,
                  yield: yield(feed.yield_30d)
                ) %>
              </span>
              <span :if={feed.last_error} class="phone-row__ids">
                <%= gettext("last error:") %> <%= foreign(feed.last_error) %>
              </span>
              <span class="phone-row__ids"><.feed_state feed={feed} /></span>
            </div>
            <div class="phone-row__figures">
              <span class="phone-row__figure"><%= feed.items_24h %></span>
              <span class="phone-row__figure2"><%= ngettext("%{count} error", "%{count} errors", feed.err_24h) %></span>
            </div>
          </li>
        </ul>
      <% end %>
    </section>
    """
  end

  attr(:feed, :map, required: true)

  defp feed_binding(assigns) do
    ~H"""
    <%= case @feed.registration do %>
      <% %{security_id: id, security_name: name} when not is_nil(id) -> %>
        <a href={"/securities/#{id}"}><%= StoredText.bdi(name) %></a>
      <% %{category_name: name} when not is_nil(name) -> %>
        <%= StoredText.bdi(name) %>
      <% _aggregator -> %>
        <%= gettext("Universe") %>
    <% end %>
    """
  end

  attr(:feed, :map, required: true)

  # The feed's state, each a chip with its word (UX-DR7): paused, stale,
  # low yield, last fetch failed; none of them, „ok“.
  defp feed_state(assigns) do
    ~H"""
    <span class="news-states">
      <span :if={!@feed.enabled} class="badge badge--undetermined"><%= gettext("paused") %></span>
      <span :if={@feed.stale} class="badge badge-warning"><%= gettext("stale") %></span>
      <span :if={@feed.low_yield} class="badge badge-warning"><%= gettext("low yield") %></span>
      <span :if={@feed.last_error} class="badge badge--danger"><%= gettext("last fetch failed") %></span>
      <span
        :if={@feed.enabled and not @feed.stale and not @feed.low_yield and is_nil(@feed.last_error)}
        class="badge badge--neutral"
      >
        <%= gettext("ok") %>
      </span>
    </span>
    """
  end

  attr(:sources, :list, required: true)

  # „Quellen“: each rated domain, its tier and who set it (§3).
  defp sources(assigns) do
    ~H"""
    <section id="news-sources" class="workspace-section news-section" aria-labelledby="news-sources-title">
      <header class="section-head">
        <div class="section-title">
          <h2 id="news-sources-title"><%= gettext("Sources") %></h2>
          <AppShell.section_info>
            <:line>
              <%= gettext(
                "A domain without a row reads as awareness; a rating covers the domain's subdomains."
              ) %>
            </:line>
            <:line>
              <%= gettext(
                "An item from a blocked domain is dropped when it is fetched and counted in the health line."
              ) %>
            </:line>
            <:line>
              <%= gettext(
                "A rating by hand is never overwritten by a default. Sources are rated through the API and the agent; this page shows them."
              ) %>
            </:line>
          </AppShell.section_info>
        </div>
      </header>

      <%= if @sources == [] do %>
        <p id="news-sources-empty" class="empty-state" role="status">
          <%= gettext("No source is rated yet: every domain reads as awareness. Sources are rated over the API or MCP.") %>
        </p>
      <% else %>
        <div id="news-sources-table-wrap" class="data-table-wrapper news-table-wrap">
          <table id="news-sources-table" class="data-table news-table">
            <thead>
              <tr>
                <th><%= gettext("Domain") %></th>
                <th><%= gettext("Tier") %></th>
                <th><%= gettext("Set") %></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={source <- @sources} data-source={source.domain}>
                <td data-role="source-domain"><%= foreign(source.domain) %></td>
                <td data-role="source-tier"><.tier tier={source.tier} /></td>
                <td data-role="source-set-by"><%= set_by(source.set_by) %></td>
              </tr>
            </tbody>
          </table>
        </div>
        <ul id="news-sources-phone-rows" class="phone-rows news-rows" aria-label={gettext("Sources")}>
          <li :for={source <- @sources} class="phone-row" data-source={source.domain}>
            <div class="phone-row__body">
              <span class="phone-row__name"><%= foreign(source.domain) %></span>
              <span class="phone-row__ids"><%= set_by(source.set_by) %></span>
            </div>
            <div class="phone-row__figures"><.tier tier={source.tier} /></div>
          </li>
        </ul>
      <% end %>
    </section>
    """
  end

  attr(:tier, :atom, required: true)

  # A tier as the code the agent reads (§3), its weight as the chip's.
  defp tier(assigns) do
    ~H"""
    <span class={["badge", tier_class(@tier)]}><%= @tier %></span>
    """
  end

  defp tier_class(:primary), do: nil
  defp tier_class(:blocked), do: "badge--danger"
  defp tier_class(_tier), do: "badge--neutral"

  # --- words ------------------------------------------------------------------

  # Foreign text as stored, its invisible characters spelled (ADR-0054 §4).
  defp foreign(nil), do: ""
  defp foreign(text), do: StoredText.bdi(Text.escape_invisible(text))

  defp feed_url(feed), do: foreign(feed.registration.url)

  defp queue_state(:ambiguous, row, names) do
    candidates = Enum.map_join(row.candidates, " · ", &Map.get(names, &1, "##{&1}"))

    StoredText.isolate(
      gettext("ambiguous · candidates: %{candidates}", candidates: StoredText.slot(:candidates)),
      candidates: candidates
    )
  end

  defp queue_state(:unassigned, _row, _names),
    do: gettext("unassigned · no security of the universe named")

  defp queue_basis(queue) do
    count = length(queue.rows)

    clauses = [
      gettext("ambiguous first, each newest first"),
      if(queue.truncated,
        do: gettext("the newest %{limit} of each", limit: @list_limit),
        else: ngettext("%{count} item", "%{count} items", count)
      ),
      gettext("times in UTC")
    ]

    Enum.join(clauses, " · ")
  end

  defp digest_basis(since) do
    Enum.join(
      [
        gettext("since %{time} UTC", time: time(since)),
        gettext("the news universe"),
        gettext("materiality 2 or more, or an issuer's or regulator's"),
        gettext("at most %{rows} rows", rows: @digest_rows)
      ],
      " · "
    )
  end

  # What the digest left out (C5): the quiet securities, the hidden
  # stories, and the rows past its cap.
  defp left_out(digest) do
    [
      ngettext(
        "%{count} security without news",
        "%{count} securities without news",
        digest.quiet
      ),
      ngettext(
        "%{count} story of aggregators or themes hidden (no label or materiality below 2)",
        "%{count} stories of aggregators or themes hidden (no label or materiality below 2)",
        digest.hidden
      ),
      digest.more &&
        ngettext("%{count} more row not shown", "%{count} more rows not shown", digest.more)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp set_by(:hand), do: gettext("by hand")
  defp set_by(:seed), do: pgettext("news source", "default")

  # A yield as a percentage (A3's decimal, ADR-0003); none without items.
  defp yield(nil), do: "—"
  defp yield(%Decimal{} = value), do: Format.percent(value) <> " %"

  # A time to the minute in UTC, its date in the page's notation.
  defp time(nil), do: "—"

  defp time(%DateTime{} = at) do
    utc = DateTime.shift_zone!(at, "Etc/UTC")
    Format.date(DateTime.to_date(utc)) <> " " <> Calendar.strftime(utc, "%H:%M")
  end
end
