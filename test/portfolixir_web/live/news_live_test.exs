defmodule PortfolixirWeb.NewsLiveTest do
  # ADR-0056 §10 (Sprint 28, N7; board ux-design-2026-11-08-sprint28/01,
  # variant A): the page „Nachrichten“, the operator's view of what the
  # agent reads. Each region reads through the context function the API's
  # read uses, so a test per region holds the screen to the API's answer
  # for the same request (plan D-1, criterion 6). Synthetic names and
  # hosts only, no socket.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest
  import Portfolixir.NewsFixtures, only: [feed!: 1, label!: 2, story!: 2]
  import Portfolixir.WorldFixtures, only: [create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Journal
  alias Portfolixir.News.DigestConsumer
  alias Portfolixir.News.Ingest
  alias Portfolixir.News.Item
  alias Portfolixir.News.Parser.Item, as: Parsed
  alias Portfolixir.News.Sources
  alias Portfolixir.Repo
  alias PortfolixirWeb.Format

  @agent_token String.duplicate("n", 40)

  setup do
    previous = Application.get_env(:portfolixir, :api_tokens)
    Application.put_env(:portfolixir, :api_tokens, [{"mcp", @agent_token}])
    on_exit(fn -> Application.put_env(:portfolixir, :api_tokens, previous) end)
    :ok
  end

  defp api(path) do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer " <> @agent_token)
    |> get(path)
    |> json_response(200)
    |> Map.fetch!("data")
  end

  defp watched!(name, token) do
    security = create_security!(name: name, ticker: nil, asset_class: "equity")

    {:ok, security} =
      Catalog.update_security(Actor.owner_ui(), security, %{
        news_watch: true,
        news_aliases: [%{token: token, context: [], case: "insensitive"}]
      })

    security
  end

  defp aggregator_item!(feed, title) do
    link = "https://search.example.com/r?u=#{System.unique_integer([:positive])}"
    item = struct!(Parsed, %{title: title, link: link, source_domain: "wire.example.com"})
    {:ok, %{stored: 1}} = Ingest.ingest(feed, [item], DateTime.utc_now())
    Repo.get_by!(Item, canonical_url: link)
  end

  # Two watched securities, an issuer story of the first (labelled), an
  # aggregator story of it no label lets through (hidden), an item both
  # names claim (ambiguous), one neither does (unassigned), and two rated
  # sources, one by hand and one by the seed.
  defp news_world do
    northwind = watched!("Northwind Harbour Logistics AG", "Northwind Harbour")
    harbourline = watched!("Harbourline Shipping AG", "Harbourline")

    issuer = feed!(%{class: "issuer", security_id: northwind.id})
    story = story!(northwind, feed: issuer, title: "Northwind Harbour raises its outlook")
    label!(story.id, event_type: "earnings", materiality: 2)

    aggregator = feed!(%{class: "aggregator", url: "https://search.example.com/rss-n7"})
    hidden = aggregator_item!(aggregator, "Northwind Harbour wins a port contract")

    ambiguous =
      aggregator_item!(aggregator, "Northwind Harbour and Harbourline agree on a venture")

    unassigned = aggregator_item!(aggregator, "Central bank leaves rates unchanged")

    {:ok, _} = Sources.put_source(Actor.owner_ui(), "ir.example.com", "primary")

    {:ok, _} =
      Sources.put_source(Actor.owner_ui(), "wire.example.com", "secondary", set_by: :seed)

    %{
      northwind: northwind,
      harbourline: harbourline,
      issuer: issuer,
      aggregator: aggregator,
      hidden: Repo.reload!(hidden),
      ambiguous: Repo.reload!(ambiguous),
      unassigned: Repo.reload!(unassigned)
    }
  end

  defp cell_time(iso) do
    {:ok, at, 0} = DateTime.from_iso8601(iso)
    Format.date(DateTime.to_date(at)) <> " " <> Calendar.strftime(at, "%H:%M")
  end

  # User story (ADR-0056 §10; plan D-5, board 01 A):
  # As the operator who runs an agent on the news layer,
  # I want a page „Nachrichten“ in the main navigation, after Wertpapiere,
  # with the tabs Meldungen, Feeds and Quellen, each one an address,
  # so that I read what the agent reads and can hand over a link to a tab.
  #
  # Acceptance criteria:
  # - The sidebar (and with it the phone's menu) carries #nav-news after
  #   #nav-securities, current on /news and its tabs.
  # - /news opens Meldungen, /news?tab=feeds Feeds and /news?tab=sources
  #   Quellen, each the current tab; a click on a tab patches the address.
  # - An address naming a tab the page does not know opens Meldungen.
  test "the page sits after Wertpapiere, and each tab is an address and a click", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/news")

    assert has_element?(view, "#nav-news[href='/news'][aria-current='page']", "News")
    assert has_element?(view, "#app-sidebar .nav-group:first-child #nav-securities + #nav-news")
    assert has_element?(view, "#app-topbar-title", "News")
    assert has_element?(view, "#news-tabs a[aria-current='page'][href='/news']", "Reports")

    view |> element("#news-tabs a", "Feeds") |> render_click()
    assert_patch(view, "/news?tab=feeds")
    assert has_element?(view, "#news-tabs a[aria-current='page'][href='/news?tab=feeds']")
    assert has_element?(view, "#news-feeds")

    view |> element("#news-tabs a", "Sources") |> render_click()
    assert_patch(view, "/news?tab=sources")
    assert has_element?(view, "#news-sources")

    view |> element("#news-tabs a", "Reports") |> render_click()
    assert_patch(view, "/news")
    assert has_element?(view, "#news-queue")

    {:ok, linked, _html} = live(conn, "/news?tab=sources")
    assert has_element?(linked, "#news-tabs a[aria-current='page'][href='/news?tab=sources']")
    assert has_element?(linked, "#nav-news[aria-current='page']")

    {:ok, unknown, _html} = live(conn, "/news?tab=archive")
    assert has_element?(unknown, "#news-tabs a[aria-current='page'][href='/news']")
  end

  # User story (ADR-0056 §6, §9, §10; plan D-1 criterion 6):
  # As the operator who checks the agent's picture of the news,
  # I want the Meldungen tab to show the health line, the queue of items
  # no security or several claim, and the digest per security with what
  # it hid, each as the API answers it,
  # so that the screen and the agent never disagree about what is new.
  #
  # Acceptance criteria:
  # - The health line's counts are news.health's: the feeds, the stale
  #   ones, the errors of today and yesterday, the items of 24 hours, the
  #   day's unassigned and ambiguous.
  # - The queue lists the rows of news.list with assignment ambiguous and
  #   unassigned: title, domain, tier, time and the candidates by name.
  # - The digest lists news.digest's rows for the same since, stateless
  #   (no consumer, so no cursor moves): name, count, top story, tier,
  #   time, event types and materiality marked machine-made, then what it
  #   hid and how many securities were quiet.
  test "the Meldungen tab answers as news.health, news.list and news.digest do", %{conn: conn} do
    world = news_world()
    since = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.to_iso8601()

    {:ok, view, _html} = live(conn, "/news?since=#{URI.encode_www_form(since)}")

    health = api("/api/v1/news/health")
    feeds = health["feeds"]

    assert has_element?(view, "[data-role='news-health-feeds']", "#{length(feeds)} feeds")

    stale = Enum.count(feeds, & &1["stale"])
    assert has_element?(view, "[data-role='news-health-stale']", "#{stale} stale")

    errors = feeds |> Enum.map(& &1["err_24h"]) |> Enum.sum()
    assert has_element?(view, "[data-role='news-health-errors']", "#{errors} errors")

    items = feeds |> Enum.map(& &1["items_24h"]) |> Enum.sum()
    assert has_element?(view, "[data-role='news-health-items']", "#{items} items in 24 h")

    day = health["day"]

    assert has_element?(
             view,
             "[data-role='news-health-open']",
             "#{day["unassigned"]} unassigned · #{day["ambiguous"]} ambiguous"
           )

    for assignment <- ["ambiguous", "unassigned"] do
      rows = api("/api/v1/news/stories?assignment=#{assignment}")["rows"]
      assert rows != []

      for row <- rows do
        selector = "#news-queue-table tr[data-item='#{row["id"]}']"
        assert has_element?(view, selector <> " [data-role='queue-title']", row["title"])
        assert has_element?(view, selector <> " [data-role='queue-source']", row["domain"])
        assert has_element?(view, selector <> " [data-role='queue-source']", row["tier"])
        assert has_element?(view, selector <> " [data-role='queue-time']", cell_time(row["at"]))

        for candidate <- row["candidates"] || [] do
          name = Catalog.get_security!(candidate).name
          assert has_element?(view, selector <> " [data-role='queue-state']", name)
        end
      end
    end

    assert has_element?(
             view,
             "tr[data-item='#{world.ambiguous.id}'] [data-role='queue-state']",
             "ambiguous"
           )

    assert has_element?(
             view,
             "tr[data-item='#{world.unassigned.id}'] [data-role='queue-state']",
             "unassigned"
           )

    digest = api("/api/v1/news/digest?since=#{URI.encode_www_form(since)}")
    assert [row] = digest["rows"]
    assert row["id"] == world.northwind.id

    selector = "#news-digest-table tr[data-security='#{row["id"]}']"
    # The digest's short name (§9's 20 characters) is the start of the
    # whole name the page has the room for.
    full = world.northwind.name
    assert String.starts_with?(full, String.trim_trailing(row["name"], "…"))

    assert has_element?(
             view,
             selector <> " [data-role='digest-name'] a[href='/securities/#{row["id"]}']",
             full
           )

    assert has_element?(view, selector <> " [data-role='digest-count']", "#{row["count"]}")
    assert has_element?(view, selector <> " [data-role='digest-top']", row["top"]["title"])
    assert has_element?(view, selector <> " [data-role='digest-top']", row["top"]["tier"])

    assert has_element?(
             view,
             selector <> " [data-role='digest-top']",
             cell_time(row["top"]["at"])
           )

    for type <- row["event_types"] do
      assert has_element?(view, selector <> " [data-role='digest-label']", type)
    end

    assert has_element?(
             view,
             selector <> " [data-role='digest-label']",
             "materiality #{row["materiality"]}"
           )

    assert has_element?(view, selector <> " [data-role='digest-label']", "machine-made")

    assert digest["hidden"] == 1

    assert digest["quiet"] == 1

    assert has_element?(
             view,
             "[data-role='digest-left-out']",
             "1 security without news · 1 story of aggregators or themes hidden"
           )

    # The screen reads the stateless since mode: it keeps no consumer and
    # moves no agent's cursor.
    assert Repo.aggregate(DigestConsumer, :count) == 0
  end

  # User story (ADR-0056 §9, §10):
  # As the operator working the queue,
  # I want to assign an item to a security with „Zuordnen“,
  # so that it reads in that security's stories, journaled as mine.
  #
  # Acceptance criteria:
  # - Each queue row offers a security picker, its candidates first, and
  #   „Zuordnen“; the write is news.assign's (Portfolixir.News.assign_item/4).
  # - The assigned item leaves the queue and the page says where it went.
  # - The journal records one news_item update under the UI actor.
  # - Submitting without a security writes nothing and says so.
  test "Zuordnen assigns a queue item, journaled under the UI actor", %{conn: conn} do
    world = news_world()
    {:ok, view, _html} = live(conn, "/news")

    row = "tr[data-item='#{world.ambiguous.id}']"
    assert has_element?(view, row <> " option[value='#{world.harbourline.id}']")

    view
    |> form("#news-queue-table #{row} form", %{"security_id" => ""})
    |> render_submit()

    assert has_element?(view, row)
    assert has_element?(view, "#news-assign-result", "Choose a security")
    assert Journal.list_entries(resource_type: "news_item") == []

    view
    |> form("#news-queue-table #{row} form", %{"security_id" => "#{world.harbourline.id}"})
    |> render_submit()

    refute has_element?(view, row)
    assert has_element?(view, "#news-assign-result", "Harbourline Shipping AG")
    assert %Item{assignment: :assigned} = item = Repo.reload!(world.ambiguous)
    assert item.security_id == world.harbourline.id

    assert [entry] = Journal.list_entries(resource_type: "news_item")
    assert entry.actor_type == :owner_ui
    assert entry.resource_id == to_string(world.ambiguous.id)
  end

  # User story (ADR-0056 §6, A3; plan D-3):
  # As the operator who decides whether a feed earns its keep,
  # I want the Feeds tab to show each feed with news.health's fields and
  # its state, and the Quellen tab each rated domain with its tier and who
  # set it,
  # so that a dead or useless feed and a wrongly rated source are visible,
  # while registering and rating stay with the API and the agent.
  #
  # Acceptance criteria:
  # - Each feed row carries news.health's items_24h, err_24h, items_30d,
  #   promoted_30d and yield_30d (as a percentage), its last good fetch and
  #   its state chips (stale, low yield, last fetch failed, paused, else
  #   ok), beside its URL, class and binding.
  # - Each source row carries its domain, its tier and "by hand" or
  #   "default".
  # - Neither tab offers a control that writes.
  test "the Feeds and Quellen tabs answer as news.health and the stored sources", %{conn: conn} do
    world = news_world()

    {:ok, view, _html} = live(conn, "/news?tab=feeds")

    for feed <- api("/api/v1/news/health")["feeds"] do
      selector = "#news-feeds-table tr[data-feed='#{feed["id"]}']"
      assert has_element?(view, selector)

      assert has_element?(
               view,
               selector <> " [data-role='feed-items-24h']",
               "#{feed["items_24h"]}"
             )

      assert has_element?(view, selector <> " [data-role='feed-errors']", "#{feed["err_24h"]}")

      assert has_element?(
               view,
               selector <> " [data-role='feed-items-30d']",
               "#{feed["items_30d"]}"
             )

      assert has_element?(
               view,
               selector <> " [data-role='feed-promoted']",
               "#{feed["promoted_30d"]}"
             )

      yield = Format.percent(Decimal.new(feed["yield_30d"])) <> " %"
      assert has_element?(view, selector <> " [data-role='feed-yield']", yield)

      last_ok = if feed["last_ok_at"], do: cell_time(feed["last_ok_at"]), else: "—"
      assert has_element?(view, selector <> " [data-role='feed-last-ok']", last_ok)
      assert has_element?(view, selector <> " [data-role='feed-class']", feed["class"])

      state = if feed["stale"], do: "stale", else: "ok"
      assert has_element?(view, selector <> " [data-role='feed-state']", state)
    end

    assert has_element?(
             view,
             "tr[data-feed='#{world.issuer.id}'] [data-role='feed-binding']",
             "Northwind Harbour Logistics AG"
           )

    assert has_element?(
             view,
             "tr[data-feed='#{world.aggregator.id}'] [data-role='feed-binding']",
             "Universe"
           )

    refute has_element?(view, "#news-feeds form")
    refute has_element?(view, "#news-feeds button[phx-click]")

    {:ok, sources, _html} = live(conn, "/news?tab=sources")

    for source <- Sources.list() do
      selector = "#news-sources-table tr[data-source='#{source.id}']"
      assert has_element?(sources, selector <> " [data-role='source-domain']", source.domain)

      assert has_element?(
               sources,
               selector <> " [data-role='source-tier']",
               to_string(source.tier)
             )
    end

    assert has_element?(sources, "#news-sources-table tr", "ir.example.com")

    assert has_element?(
             sources,
             "#news-sources-table tr:has([data-role='source-domain'])",
             "by hand"
           )

    assert has_element?(sources, "#news-sources-table tr", "default")
    refute has_element?(sources, "#news-sources form")
  end

  # User story (ADR-0056 §9, ADR-0054 §4):
  # As the operator reading text a feed wrote,
  # I want an invisible character in a stored title or domain spelled
  # [U+XXXX], as the companion spells it for the agent,
  # so that a hidden character can neither hide nor reorder what I read.
  #
  # Acceptance criteria:
  # - A queue title with a zero-width space reads „[U+200B]“ in its place.
  test "a stored title's invisible character is spelled", %{conn: conn} do
    aggregator = feed!(%{class: "aggregator", url: "https://search.example.com/rss-spelled"})
    aggregator_item!(aggregator, "Rates\u200Bunchanged again")

    {:ok, view, _html} = live(conn, "/news")
    assert has_element?(view, "[data-role='queue-title']", "Rates[U+200B]unchanged again")
  end

  # User story (ADR-0056 §10; DESIGN.md empty states):
  # As an operator before any feed is registered,
  # I want each region to say it is empty and how it fills,
  # so that an empty table never reads as a broken page.
  #
  # Acceptance criteria:
  # - With no feed, item or source, the queue, the digest, the feeds and
  #   the sources each show their empty state and no table.
  test "each region states its empty state", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/news")
    assert has_element?(view, "#news-queue-empty", "Nothing to assign")
    refute has_element?(view, "#news-queue-table")
    assert has_element?(view, "#news-digest-empty", "Nothing new")
    refute has_element?(view, "#news-digest-table")
    assert has_element?(view, "[data-role='news-health-feeds']", "0 feeds")

    {:ok, feeds, _html} = live(conn, "/news?tab=feeds")
    assert has_element?(feeds, "#news-feeds-empty", "No feed is registered yet")
    refute has_element?(feeds, "#news-feeds-table")

    {:ok, sources, _html} = live(conn, "/news?tab=sources")
    assert has_element?(sources, "#news-sources-empty", "No source is rated yet")
    refute has_element?(sources, "#news-sources-table")
  end
end
