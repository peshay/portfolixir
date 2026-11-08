defmodule PortfolixirWeb.ApiV1NewsReadsTest do
  # ADR-0056 §6, §9, §11, §14 items 5 and 8, B4 (Sprint 27, N7): the news
  # layer's reads over the API — a security's, a category's or a story's
  # rows and the unassigned and ambiguous remainder, one story or item, and
  # the health. Items are stored through the ingest at a fixture clock
  # relative to now; synthetic names and hosts only, no socket.
  use PortfolixirWeb.ConnCase

  import Ecto.Query
  import Portfolixir.NewsFixtures, only: [category!: 0, feed!: 1, security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.News.Cluster
  alias Portfolixir.News.Feed
  alias Portfolixir.News.Ingest
  alias Portfolixir.News.Item
  alias Portfolixir.News.Parser.Item, as: Parsed
  alias Portfolixir.Repo

  @agent_token String.duplicate("a", 40)

  setup %{conn: conn} do
    previous = Application.get_env(:portfolixir, :api_tokens)
    Application.put_env(:portfolixir, :api_tokens, [{"mcp", @agent_token}])
    on_exit(fn -> Application.put_env(:portfolixir, :api_tokens, previous) end)

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer " <> @agent_token)

    %{conn: conn, now: DateTime.utc_now() |> DateTime.truncate(:second)}
  end

  defp hours_ago(now, hours), do: DateTime.add(now, -hours * 3600, :second)

  defp iso(%DateTime{} = at), do: DateTime.to_iso8601(at)

  defp issuer_feed!(security),
    do: feed!(%{class: "issuer", security_id: security.id})

  defp aggregator_feed!, do: feed!(%{class: "aggregator"})

  defp item(title, link, attrs \\ %{}),
    do: struct!(Parsed, Map.merge(%{title: title, link: link}, attrs))

  defp ingest!(feed, items, at) do
    {:ok, %{stored: stored}} = Ingest.ingest(feed, items, at)
    assert stored == length(items)
  end

  defp story_of!(url) do
    Repo.one!(from(i in Item, where: i.canonical_url == ^url, select: i.cluster_id))
  end

  defp item_id!(url), do: Repo.one!(from(i in Item, where: i.canonical_url == ^url, select: i.id))

  defp list(conn, query), do: get(conn, "/api/v1/news/stories?" <> URI.encode_query(query))

  defp watched!(name, token) do
    security = security!(name)

    {:ok, security} =
      Catalog.update_security(Actor.owner_ui(), security, %{
        news_watch: true,
        news_aliases: [%{token: token, context: [], case: "insensitive"}]
      })

    security
  end

  # User story (ADR-0056 §9, B4):
  # As the operator's agent reading what is new about a security,
  # I want one row per story — its representative's title, its tier, its
  # time and how many items it holds — newest first, compact, and only
  # what came in since my last read by the server's clock,
  # so that I read a security's news without spending context on links,
  # excerpts or what I have already seen.
  #
  # Acceptance criteria:
  # - GET /api/v1/news/stories?security_id= answers kind "stories" and one
  #   row per story: id, title, tier, at (the representative's clamped
  #   publication) and count; no url and no excerpt; newest first by the
  #   newest member's first sight.
  # - fields=std adds url and note_ids; fields=slim is the default.
  # - since= reads first_seen_at, never the feed's claim (B4): an item
  #   claimed at 09:00 and fetched at 10:00 is in a since=09:30 read; a
  #   story whose newest member was seen before since is not.
  # - tier_min=primary leaves out a story of aggregator items only.
  # - limit= pages: truncated is true with a cursor, and the cursor's read
  #   continues where the page ended; limit is echoed; as_of is the next
  #   since.
  describe "GET /api/v1/news/stories (a security's stories)" do
    test "one compact row per story, newest first", %{conn: conn, now: now} do
      security = security!("Northwind Harbour Logistics AG")
      feed = issuer_feed!(security)

      ingest!(
        feed,
        [
          item("Northwind Harbour opens a second terminal", "https://ir.example.com/a1"),
          item("Northwind Harbour opens a second terminal", "https://ir.example.com/a2")
        ],
        hours_ago(now, 5)
      )

      ingest!(
        feed,
        [item("Northwind Harbour names a new finance chief", "https://ir.example.com/b1")],
        hours_ago(now, 2)
      )

      data = conn |> list(security_id: security.id) |> json_response(200) |> Map.fetch!("data")

      assert %{"kind" => "stories", "limit" => 20, "truncated" => false} = data
      refute Map.has_key?(data, "cursor")
      assert {:ok, _as_of, 0} = DateTime.from_iso8601(data["as_of"])

      assert [newest, older] = data["rows"]

      assert newest == %{
               "id" => story_of!("https://ir.example.com/b1"),
               "title" => "Northwind Harbour names a new finance chief",
               "tier" => "primary",
               "at" => iso(hours_ago(now, 2)),
               "count" => 1
             }

      assert %{"id" => id, "count" => 2, "tier" => "primary"} = older
      assert id == story_of!("https://ir.example.com/a1")

      [std_newest, _] =
        conn
        |> list(security_id: security.id, fields: "std")
        |> json_response(200)
        |> get_in(["data", "rows"])

      assert std_newest["url"] == "https://ir.example.com/b1"
      assert std_newest["note_ids"] == []
    end

    test "since reads the server's first sight, never the feed's claim (B4)",
         %{conn: conn, now: now} do
      security = security!("Northwind Harbour Logistics AG")
      feed = issuer_feed!(security)
      fetched = hours_ago(now, 1)
      claimed = DateTime.add(fetched, -3600, :second)

      ingest!(
        feed,
        [
          item("An old claim fetched late", "https://ir.example.com/late", %{
            published_at: claimed
          })
        ],
        fetched
      )

      ingest!(feed, [item("Seen long before", "https://ir.example.com/early")], hours_ago(now, 6))

      since = DateTime.add(fetched, -1800, :second)

      rows =
        conn
        |> list(security_id: security.id, since: iso(since))
        |> json_response(200)
        |> get_in(["data", "rows"])

      assert [%{"title" => "An old claim fetched late", "at" => at}] = rows
      assert at == iso(claimed)

      echoed = conn |> list(security_id: security.id, since: iso(since)) |> json_response(200)
      assert echoed["data"]["since"] == iso(since)
    end

    test "tier_min leaves out the stories below it", %{conn: conn, now: now} do
      security = watched!("Northwind Harbour Logistics AG", "Northwind Harbour")

      ingest!(
        issuer_feed!(security),
        [item("Northwind Harbour annual report", "https://ir.example.com/r")],
        hours_ago(now, 3)
      )

      ingest!(
        aggregator_feed!(),
        [
          item("Analysts discuss Northwind Harbour freight", "https://agg.example.com/x", %{
            source_domain: "wire.example.com"
          })
        ],
        hours_ago(now, 2)
      )

      all = conn |> list(security_id: security.id) |> json_response(200)
      assert Enum.map(all["data"]["rows"], & &1["tier"]) == ["awareness", "primary"]

      primary = conn |> list(security_id: security.id, tier_min: "primary") |> json_response(200)
      assert [%{"title" => "Northwind Harbour annual report"}] = primary["data"]["rows"]

      awareness =
        conn |> list(security_id: security.id, tier_min: "awareness") |> json_response(200)

      assert length(awareness["data"]["rows"]) == 2
    end

    test "a capped page is truncated, and its cursor continues it", %{conn: conn, now: now} do
      security = security!("Northwind Harbour Logistics AG")
      feed = issuer_feed!(security)

      for n <- 1..3 do
        ingest!(
          feed,
          [item("Distinct release number #{n} about cranes #{n}", "https://ir.example.com/#{n}")],
          hours_ago(now, 10 - n)
        )
      end

      first = conn |> list(security_id: security.id, limit: 2) |> json_response(200)
      assert %{"limit" => 2, "truncated" => true, "cursor" => cursor} = first["data"]
      assert length(first["data"]["rows"]) == 2

      rest =
        conn |> list(security_id: security.id, limit: 2, cursor: cursor) |> json_response(200)

      assert %{"truncated" => false, "rows" => [last]} = rest["data"]
      refute Map.has_key?(rest["data"], "cursor")

      ids = Enum.map(first["data"]["rows"] ++ [last], & &1["id"])
      assert ids == Enum.map(3..1//-1, &story_of!("https://ir.example.com/#{&1}"))

      capped = conn |> list(security_id: security.id, limit: 500) |> json_response(200)
      assert capped["data"]["limit"] == 100
    end

    # User story (Sprint 27 closing act, ORD4; ADR-0056 B3):
    # As the agent reading the first page of a security's stories,
    # I want stories that entered their scope in the same tick ordered by
    # tier, then publication, then link — never by id —
    # so that an aggregator's flood stored after an issuer's release in the
    # same tick cannot push the release off the first page.
    #
    # Acceptance criteria:
    # - One issuer story and four aggregator stories of one tick: the
    #   issuer's is the first row of a page of two.
    # - Paged one row at a time by the cursor, the pages are the same rows
    #   in the same order as one page of all, each once.
    test "within one tick stories come by tier, publication and link, and the cursor follows",
         %{conn: conn, now: now} do
      security = watched!("Northwind Harbour Logistics AG", "Northwind")

      ingest!(
        issuer_feed!(security),
        [item("Northwind annual report", "https://ir.example.com/a")],
        now
      )

      ingest!(
        aggregator_feed!(),
        for n <- 1..4 do
          item(
            "Northwind flood #{n} item#{n}x item#{n}y",
            "https://flood-#{n}.example.com/#{n}",
            %{
              published_at: if(n <= 2, do: hours_ago(now, 1)),
              source_domain: "wire.example.com"
            }
          )
        end,
        now
      )

      first = conn |> list(security_id: security.id, limit: 2) |> json_response(200)
      assert [%{"tier" => "primary"}, _second] = first["data"]["rows"]

      all = conn |> list(security_id: security.id) |> json_response(200)
      assert length(all["data"]["rows"]) == 5

      paged =
        Stream.unfold(nil, fn
          :done ->
            nil

          cursor ->
            query =
              [security_id: security.id, limit: 1] ++ if(cursor, do: [cursor: cursor], else: [])

            data = conn |> list(query) |> json_response(200) |> Map.fetch!("data")
            {data["rows"], Map.get(data, "cursor", :done)}
        end)
        |> Enum.concat()

      assert Enum.map(paged, & &1["id"]) == Enum.map(all["data"]["rows"], & &1["id"])
    end
  end

  # User story (ADR-0056 §2, §9):
  # As the agent that resolves what the matcher could not,
  # I want the unassigned and the ambiguous items listed with their
  # candidates, a category's stories and one story's members,
  # so that I see the remainder and the duplicates without a query per item.
  #
  # Acceptance criteria:
  # - assignment=unassigned lists the aggregator items no security claims,
  #   kind "items": id, title, tier, at and domain, no candidates.
  # - assignment=ambiguous lists those several securities claim, each with
  #   its candidates (security ids, ascending).
  # - category_id= lists a thematic feed's stories; cluster_id= lists the
  #   story's member items.
  describe "GET /api/v1/news/stories (the remainder, a category, a story)" do
    test "the unassigned and the ambiguous items, with candidates", %{conn: conn, now: now} do
      north = watched!("Northwind Harbour Logistics AG", "Harbour")
      south = watched!("Southwind Harbour Shipping SE", "Harbour")
      _ = {north, south}

      ingest!(
        aggregator_feed!(),
        [
          item("Harbour strike enters day two", "https://agg.example.com/h", %{
            source_domain: "wire.example.com"
          }),
          item("Unrelated market chatter", "https://agg.example.com/u", %{
            source_domain: "wire.example.com"
          })
        ],
        hours_ago(now, 1)
      )

      unassigned = conn |> list(assignment: "unassigned") |> json_response(200)

      assert unassigned["data"]["kind"] == "items"

      assert [
               %{
                 "id" => unassigned_id,
                 "title" => "Unrelated market chatter",
                 "tier" => "awareness",
                 "domain" => "wire.example.com"
               } = row
             ] = unassigned["data"]["rows"]

      assert unassigned_id == item_id!("https://agg.example.com/u")
      refute Map.has_key?(row, "candidates")

      ambiguous = conn |> list(assignment: "ambiguous") |> json_response(200)

      assert [%{"title" => "Harbour strike enters day two", "candidates" => candidates}] =
               ambiguous["data"]["rows"]

      assert candidates == Enum.sort([north.id, south.id])
    end

    test "a category's stories and a story's members", %{conn: conn, now: now} do
      category = category!()
      thematic = feed!(%{class: "thematic", category_id: category.id})

      ingest!(
        thematic,
        [
          item("Water utilities raise tariffs", "https://theme.example.com/1"),
          item("Water utilities raise tariffs", "https://other.example.com/1")
        ],
        hours_ago(now, 4)
      )

      stories = conn |> list(category_id: category.id) |> json_response(200)
      assert [%{"id" => story_id, "count" => 2}] = stories["data"]["rows"]

      members = conn |> list(cluster_id: story_id) |> json_response(200)
      assert members["data"]["kind"] == "items"

      assert members["data"]["rows"] |> Enum.map(& &1["domain"]) |> Enum.sort() ==
               ["other.example.com", "theme.example.com"]
    end
  end

  # User story (ADR-0056 §9, §11):
  # As the operator's agent,
  # I want a read that refuses what it does not take,
  # so that a parameter of the next sprint (min_materiality, event_types)
  # or a misspelt one is never taken for a filter that ran.
  #
  # Acceptance criteria:
  # - An unknown parameter answers 422 naming it; min_materiality and
  #   event_types are unknown this sprint (labels are Sprint 28's).
  # - No selector, or two, answers 422; a selector that names nothing
  #   answers 404; tier_min, assignment, fields, limit, since and cursor
  #   outside their shapes answer 422 naming them.
  describe "GET /api/v1/news/stories (refusals)" do
    test "an unknown or malformed parameter answers 422 naming it", %{conn: conn} do
      security = security!("Northwind Harbour Logistics AG")

      for {query, key} <- [
            {[security_id: security.id, min_materiality: 2], "min_materiality"},
            {[security_id: security.id, event_types: "earnings"], "event_types"},
            {[security_id: security.id, sort: "tier"], "sort"},
            {[], "security_id"},
            {[security_id: security.id, assignment: "unassigned"], "security_id"},
            {[security_id: security.id, tier_min: "gold"], "tier_min"},
            {[security_id: security.id, tier_min: "blocked"], "tier_min"},
            {[assignment: "assigned"], "assignment"},
            {[security_id: security.id, fields: "full"], "fields"},
            {[security_id: security.id, limit: 0], "limit"},
            {[security_id: security.id, since: "yesterday"], "since"},
            {[security_id: security.id, cursor: "nope"], "cursor"},
            {[security_id: "x"], "security_id"}
          ] do
        errors = conn |> list(query) |> json_response(422) |> Map.fetch!("errors")
        assert Map.has_key?(errors, key), "#{inspect(query)}: #{inspect(errors)}"
      end

      assert conn |> list(security_id: 999_999_999) |> json_response(404)
      assert conn |> list(category_id: 999_999_999) |> json_response(404)
      assert conn |> list(cluster_id: 999_999_999) |> json_response(404)
    end
  end

  # User story (ADR-0056 §9):
  # As the operator's agent that wants to read one story before it acts,
  # I want the one read that carries the excerpt and the link: the story's
  # title, link, domain, tier, times, excerpt, up to five members, the note
  # ids and its security, or the same for one item,
  # so that lists stay compact and the full text is one call away.
  #
  # Acceptance criteria:
  # - GET /api/v1/news/stories/:id answers kind "story": id, title, url,
  #   domain, tier, language, published_at, first_seen_at, excerpt, count,
  #   members (at most five: id, domain, tier, at; the representative
  #   first), note_ids and security {id, name}, the name at most 20
  #   characters.
  # - GET /api/v1/news/items/:id answers kind "item": its story_id, title,
  #   url, domain, tier, class, assignment, status, note_ids, excerpt, and
  #   its candidates when ambiguous; a field without a value is left out.
  # - An id that names nothing answers 404.
  describe "GET /api/v1/news/stories/:id and /news/items/:id" do
    test "a story with its excerpt, link and at most five members", %{conn: conn, now: now} do
      security = security!("Northwind Harbour Logistics Aktiengesellschaft")
      feed = issuer_feed!(security)

      items =
        for n <- 1..6 do
          item("Northwind Harbour opens a second terminal", "https://ir#{n}.example.com/t", %{
            excerpt: "The terminal adds berth capacity (#{n})."
          })
        end

      ingest!(feed, items, hours_ago(now, 3))

      promoted = Repo.get_by!(Item, canonical_url: "https://ir3.example.com/t")
      promoted |> Item.changeset(%{status: :promoted, note_ids: [41]}) |> Repo.update!()

      story_id = story_of!("https://ir1.example.com/t")
      story = Repo.get!(Cluster, story_id)
      representative = Repo.get!(Item, story.representative_item_id)

      data =
        conn
        |> get("/api/v1/news/stories/#{story_id}")
        |> json_response(200)
        |> Map.fetch!("data")

      assert %{
               "id" => ^story_id,
               "kind" => "story",
               "title" => "Northwind Harbour opens a second terminal",
               "tier" => "primary",
               "language" => "en",
               "count" => 6,
               "note_ids" => [41]
             } = data

      assert data["url"] == representative.canonical_url
      assert data["domain"] == representative.domain
      assert data["excerpt"] == representative.excerpt
      assert data["published_at"] == iso(hours_ago(now, 3))
      assert data["first_seen_at"] == iso(hours_ago(now, 3))
      assert data["security"] == %{"id" => security.id, "name" => "Northwind Harbour L…"}
      assert String.length(data["security"]["name"]) == 20
      refute Map.has_key?(data, "category")

      assert length(data["members"]) == 5
      assert hd(data["members"])["id"] == representative.id

      for member <- data["members"] do
        assert Map.keys(member) |> Enum.sort() == ~w(at domain id tier)
      end

      assert conn |> get("/api/v1/news/stories/999999999") |> json_response(404)
    end

    test "an item, its story and, when ambiguous, its candidates", %{conn: conn, now: now} do
      north = watched!("Northwind Harbour Logistics AG", "Harbour")
      south = watched!("Southwind Harbour Shipping SE", "Harbour")

      ingest!(
        aggregator_feed!(),
        [
          item("Harbour strike enters day two", "https://agg.example.com/h", %{
            source_domain: "wire.example.com",
            excerpt: "Dock workers stayed out."
          })
        ],
        hours_ago(now, 1)
      )

      ingest!(
        issuer_feed!(north),
        [item("Northwind results", "https://ir.example.com/r")],
        hours_ago(now, 2)
      )

      ambiguous_id = item_id!("https://agg.example.com/h")

      data =
        conn
        |> get("/api/v1/news/items/#{ambiguous_id}")
        |> json_response(200)
        |> Map.fetch!("data")

      assert %{
               "id" => ^ambiguous_id,
               "kind" => "item",
               "title" => "Harbour strike enters day two",
               "url" => "https://agg.example.com/h",
               "domain" => "wire.example.com",
               "tier" => "awareness",
               "class" => "aggregator",
               "assignment" => "ambiguous",
               "status" => "new",
               "note_ids" => [],
               "excerpt" => "Dock workers stayed out."
             } = data

      assert data["candidates"] == Enum.sort([north.id, south.id])
      refute Map.has_key?(data, "story_id")
      refute Map.has_key?(data, "security")

      issued_id = item_id!("https://ir.example.com/r")

      issued =
        conn |> get("/api/v1/news/items/#{issued_id}") |> json_response(200) |> Map.fetch!("data")

      assert issued["story_id"] == story_of!("https://ir.example.com/r")
      assert issued["security"] == %{"id" => north.id, "name" => "Northwind Harbour L…"}
      refute Map.has_key?(issued, "candidates")
      refute Map.has_key?(issued, "excerpt")

      assert conn |> get("/api/v1/news/items/999999999") |> json_response(404)
    end
  end

  # User story (ADR-0056 §6, §14 item 5):
  # As the operator's agent watching the collector,
  # I want the health read over the API — each feed's freshness and yield,
  # and the day's unassigned, ambiguous, dropped and blocked counts —
  # with a feed silent for 24 hours marked stale,
  # so that a dead feed reads differently from a quiet security.
  #
  # Acceptance criteria:
  # - GET /api/v1/news/health answers as_of, feeds (id, class, enabled,
  #   last_ok_at, last_error, items_24h, err_24h, stale, items_30d,
  #   promoted_30d, yield_30d as a decimal string, low_yield) and day
  #   (date, unassigned, ambiguous, dropped {cap, no_source, old},
  #   blocked).
  # - A feed whose last successful fetch was 25 hours ago reads stale; one
  #   fetched an hour ago does not.
  # - A field without a value (last_error, a yield without items) is left
  #   out; an unknown parameter answers 422.
  describe "GET /api/v1/news/health" do
    test "stale after 24 hours, the yield as a decimal string", %{conn: conn, now: now} do
      fresh = issuer_feed!(security!("Northwind Harbour Logistics AG"))
      dead = issuer_feed!(security!("Southwind Harbour Shipping SE"))

      ingest!(fresh, [item("Fresh release", "https://ir.example.com/f")], hours_ago(now, 1))

      fresh
      |> Feed.health_changeset(%{last_fetch_at: hours_ago(now, 1), last_ok_at: hours_ago(now, 1)})
      |> Repo.update!()

      dead
      |> Feed.health_changeset(%{
        last_fetch_at: hours_ago(now, 25),
        last_ok_at: hours_ago(now, 25),
        last_error: "http_503"
      })
      |> Repo.update!()

      data = conn |> get("/api/v1/news/health") |> json_response(200) |> Map.fetch!("data")

      assert {:ok, _as_of, 0} = DateTime.from_iso8601(data["as_of"])
      assert %{"date" => _, "unassigned" => 0, "ambiguous" => 0, "blocked" => 0} = data["day"]
      assert data["day"]["dropped"] == %{"cap" => 0, "no_source" => 0, "old" => 0}

      by_id = Map.new(data["feeds"], &{&1["id"], &1})

      assert %{
               "class" => "issuer",
               "enabled" => true,
               "stale" => false,
               "items_24h" => 1,
               "items_30d" => 1,
               "promoted_30d" => 0,
               "yield_30d" => "0.0000",
               "low_yield" => false
             } = by_id[fresh.id]

      assert by_id[fresh.id]["last_ok_at"] == iso(hours_ago(now, 1))
      refute Map.has_key?(by_id[fresh.id], "last_error")

      assert %{"stale" => true, "last_error" => "http_503", "items_30d" => 0} = by_id[dead.id]
      refute Map.has_key?(by_id[dead.id], "yield_30d")

      assert %{"errors" => %{"verbose" => _}} =
               conn |> get("/api/v1/news/health?verbose=1") |> json_response(422)
    end
  end
end
