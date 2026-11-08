defmodule PortfolixirWeb.ApiV1NewsDigestTest do
  # ADR-0056 §7, §9, §11, §14 items 2, 5 and 8, B4 (Sprint 27, N7): the
  # digest without labels and without a consumer cursor, and the size
  # budgets of the agent's reads on a 40-security fixture over 24 hours.
  # Items are stored through the ingest at fixture times relative to now;
  # synthetic names and hosts only, no socket.
  #
  # The budgets are counted as characters / 4 of the API's JSON body. The
  # companion passes that body through and answers it as compact JSON (pinned
  # in mcp-server/test/news-reads.test.ts), so for this fixture's text, which
  # holds no character the companion spells as [U+XXXX], the figure is what
  # the MCP tool returns.
  use PortfolixirWeb.ConnCase

  import Portfolixir.NewsFixtures, only: [category!: 0, feed!: 1]
  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
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

  defp hours_ago(now, hours), do: DateTime.add(now, -round(hours * 3600), :second)

  defp iso(%DateTime{} = at), do: DateTime.to_iso8601(at)

  defp item(title, link, attrs \\ %{}),
    do: struct!(Parsed, Map.merge(%{title: title, link: link}, attrs))

  defp ingest!(feed, items, at) do
    {:ok, %{stored: stored}} = Ingest.ingest(feed, items, at)
    assert stored == length(items)
  end

  defp issuer_feed!(security), do: feed!(%{class: "issuer", security_id: security.id})

  defp digest(conn, query \\ []),
    do: get(conn, "/api/v1/news/digest?" <> URI.encode_query(query))

  defp held!(world, name, aliases \\ []) do
    security = create_security!(name: name, ticker: nil, asset_class: "equity")
    buy!(world, security, quantity: "1", price: "10")

    if aliases != [] do
      {:ok, security} =
        Catalog.update_security(Actor.owner_ui(), security, %{
          news_aliases: Enum.map(aliases, &%{token: &1, context: [], case: "insensitive"})
        })

      security
    else
      security
    end
  end

  defp story_of!(url), do: Repo.get_by!(Item, canonical_url: url).cluster_id

  # User story (ADR-0056 §7, §9, §11):
  # As the operator's agent starting a run,
  # I want one call that says which securities of a view have something new
  # since my last run — each with a short name, a count and its top story —
  # how many are quiet, and how many items no security claims,
  # so that I spend context only on what changed, and an issuer's or a
  # regulator's story is never hidden behind a filter.
  #
  # Acceptance criteria:
  # - GET /api/v1/news/digest?view_id=&since= answers one row per security
  #   the view holds with a story first seen after since: id, name (at most
  #   20 characters), count and top {id, title, tier, at}; the top story is
  #   the best tier, then the newest; its title is cut to 100 characters
  #   with an ellipsis (the whole title is list's and get's).
  # - Issuer and regulatory stories always count; a story of aggregator
  #   items only, and a thematic story, only with include_unlabeled=true
  #   (§7: include_unlabeled acts on aggregator and thematic stories); the
  #   thematic ones then appear per category under categories.
  # - quiet counts the view's securities without a row and without a story
  #   the flag left out; hidden counts the aggregator and thematic stories
  #   include_unlabeled left out (C5), so news only from an aggregator never
  #   reads as quiet; unassigned and ambiguous count the aggregator items
  #   that became so after since that no security, or several, claim.
  # - since defaults to 24 hours before now and is echoed; as_of is the next
  #   since; a security the view does not hold has no row.
  # - max_rows caps the rows: truncated is true and more counts the rows
  #   left out.
  describe "GET /api/v1/news/digest" do
    test "one row per security with something new; aggregator stories only with include_unlabeled",
         %{conn: conn, now: now} do
      world = base_world(name: "Digest", cash_name: "Cash", depot_name: "Depot")
      north = held!(world, "Northwind Harbour Logistics AG", ["Northwind"])
      south = held!(world, "Southwind Shipping SE", ["Southwind"])
      quiet = held!(world, "Quiet Mills plc")
      outside = create_security!(name: "Outside Holdings", ticker: nil, asset_class: "equity")

      ingest!(
        issuer_feed!(north),
        [item("Northwind wins a port concession", "https://ir.example.com/n1")],
        hours_ago(now, 5)
      )

      ingest!(
        issuer_feed!(north),
        [item("Northwind names a new finance chief", "https://ir.example.com/n2")],
        hours_ago(now, 2)
      )

      ingest!(
        issuer_feed!(quiet),
        [item("Quiet Mills annual report", "https://ir.example.com/q")],
        hours_ago(now, 48)
      )

      ingest!(
        issuer_feed!(outside),
        [item("Outside Holdings news", "https://ir.example.com/o")],
        hours_ago(now, 1)
      )

      ingest!(
        feed!(%{class: "aggregator"}),
        [
          item("Southwind freight volumes slip", "https://agg.example.com/s", %{
            source_domain: "wire.example.com"
          }),
          item("Northwind and Southwind share a berth", "https://agg.example.com/ns", %{
            source_domain: "wire.example.com"
          }),
          item("Unrelated market chatter", "https://agg.example.com/u", %{
            source_domain: "wire.example.com"
          })
        ],
        hours_ago(now, 3)
      )

      category = category!()

      ingest!(
        feed!(%{class: "thematic", category_id: category.id}),
        [item("Water tariffs rise across the region", "https://theme.example.com/w")],
        hours_ago(now, 4)
      )

      response = conn |> digest() |> json_response(200)
      data = response["data"]

      assert {:ok, since, 0} = DateTime.from_iso8601(data["since"])
      assert abs(DateTime.diff(since, hours_ago(now, 24))) <= 5
      assert {:ok, _as_of, 0} = DateTime.from_iso8601(data["as_of"])

      assert data["rows"] == [
               %{
                 "id" => north.id,
                 "name" => "Northwind Harbour L…",
                 "count" => 2,
                 "top" => %{
                   "id" => story_of!("https://ir.example.com/n2"),
                   "title" => "Northwind names a new finance chief",
                   "tier" => "primary",
                   "at" => iso(hours_ago(now, 2))
                 }
               }
             ]

      # Without a view: the news universe (held, targeted or watched), so
      # Outside Holdings, held by no one, is not in it either. Southwind's
      # only story is an aggregator's: hidden, so Southwind is not quiet;
      # the thematic story is hidden too.
      assert data["quiet"] == 1
      assert data["hidden"] == 2
      assert data["unassigned"] == 1
      assert data["ambiguous"] == 1
      assert data["truncated"] == false
      refute Map.has_key?(data, "categories")
      refute Map.has_key?(data, "more")

      unlabeled =
        conn |> digest(include_unlabeled: true) |> json_response(200) |> Map.fetch!("data")

      assert Enum.map(unlabeled["rows"], &{&1["id"], &1["count"]}) == [
               {north.id, 2},
               {south.id, 1}
             ]

      assert [south_row] = Enum.filter(unlabeled["rows"], &(&1["id"] == south.id))
      assert south_row["top"]["tier"] == "awareness"
      assert unlabeled["quiet"] == 1
      assert unlabeled["hidden"] == 0

      assert [%{"id" => category_id, "count" => 1, "top" => %{"title" => title}}] =
               unlabeled["categories"]

      assert category_id == category.id
      assert title == "Water tariffs rise across the region"

      narrow = conn |> digest(since: iso(hours_ago(now, 3))) |> json_response(200)
      assert [%{"id" => id, "count" => 1}] = narrow["data"]["rows"]
      assert id == north.id

      capped = conn |> digest(include_unlabeled: true, max_rows: 1) |> json_response(200)
      assert %{"truncated" => true, "more" => 1, "rows" => [%{"id" => first}]} = capped["data"]
      assert first == north.id
    end

    test "a view's digest reads the securities that view holds", %{conn: conn, now: now} do
      kept = base_world(name: "Kept", cash_name: "Kept cash", depot_name: "Kept depot")
      other = base_world(name: "Other", cash_name: "Other cash", depot_name: "Other depot")
      inside = held!(kept, "Inside Holdings")
      outside = held!(other, "Outside Holdings")

      {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Digest bucket"})
      :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), kept.depot, [bucket.id])
      {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Digest", include_all: false})
      :ok = Buckets.set_view_buckets(Actor.owner_ui(), view, [bucket.id], [])

      ingest!(
        issuer_feed!(inside),
        [item("Inside news", "https://ir.example.com/i")],
        hours_ago(now, 1)
      )

      ingest!(
        issuer_feed!(outside),
        [item("Outside news", "https://ir.example.com/o")],
        hours_ago(now, 1)
      )

      data = conn |> digest(view_id: view.id) |> json_response(200) |> Map.fetch!("data")

      assert data["view_id"] == view.id
      assert [%{"id" => id}] = data["rows"]
      assert id == inside.id
      assert data["quiet"] == 0

      everything = conn |> digest() |> json_response(200) |> Map.fetch!("data")
      assert length(everything["rows"]) == 2

      assert conn |> digest(view_id: 999_999_999) |> json_response(404)
    end

    # The consumer cursor and the labels are Sprint 28's (§11): their
    # parameters are refused, never taken for a filter that ran.
    test "an unknown or malformed parameter answers 422 naming it", %{conn: conn} do
      for {query, key} <- [
            {[consumer: "agent"], "consumer"},
            {[ack_cursor: "c"], "ack_cursor"},
            {[min_materiality: 2], "min_materiality"},
            {[tier_min: "secondary"], "tier_min"},
            {[include_unlabeled: "yes"], "include_unlabeled"},
            {[max_rows: 0], "max_rows"},
            {[max_rows: "many"], "max_rows"},
            {[since: "yesterday"], "since"},
            {[view_id: "x"], "view_id"}
          ] do
        errors = conn |> digest(query) |> json_response(422) |> Map.fetch!("errors")
        assert Map.has_key?(errors, key), "#{inspect(query)}: #{inspect(errors)}"
      end
    end
  end

  # -- the budgets (§14 item 2) on a 40-security fixture over 24 hours -------

  @title_length 160
  @excerpt_length 600

  # A title of exactly 160 characters whose words are its own, so no two
  # fixture stories are near each other (B3) unless the fixture means them
  # to be.
  defp title(security_n, story_n) do
    "Synthetic Holding #{security_n} release #{story_n}:"
    |> Stream.unfold(fn acc ->
      {acc, acc <> " w#{security_n}s#{story_n}t#{String.length(acc)}"}
    end)
    |> Enum.find(&(String.length(&1) >= @title_length))
    |> String.slice(0, @title_length)
    |> String.trim_trailing()
    |> String.pad_trailing(@title_length, "x")
  end

  defp excerpt(n),
    do: "Excerpt #{n}. " |> String.duplicate(60) |> String.slice(0, @excerpt_length)

  defp link(security_n, story_n, copy),
    do:
      "https://newsroom-#{copy}.example.com/press-releases/2026/11/holding-#{security_n}/" <>
        "release-#{story_n}-quarterly-update-and-outlook.html"

  # 40 securities held in one portfolio, each with an issuer feed, names up
  # to 31 characters. Over the 24 hours before now, 14 of them publish three
  # stories each (one story fetched from two links, so it counts two items),
  # every title 160 characters and every excerpt 600; the other 26 are quiet
  # (each with a story two days old). An aggregator adds items that name a
  # held security (assigned: shown only with include_unlabeled) and items no
  # security claims (unassigned).
  defp forty!(now) do
    world = base_world(name: "Forty", cash_name: "Cash", depot_name: "Depot")

    securities =
      for n <- 1..40 do
        held!(world, "Holding #{n} Synthetic Group AG", ["Holding#{n}"])
      end

    securities
    |> Enum.with_index(1)
    |> Enum.each(fn {security, n} ->
      feed = issuer_feed!(security)

      if n <= 14 do
        for story <- 1..3 do
          copies = if story == 1, do: [1, 2], else: [1]

          ingest!(
            feed,
            Enum.map(copies, &item(title(n, story), link(n, story, &1), %{excerpt: excerpt(n)})),
            hours_ago(now, 22 - n - story * 0.5)
          )
        end
      else
        ingest!(
          feed,
          [item(title(n, 0), link(n, 0, 1), %{excerpt: excerpt(n)})],
          hours_ago(now, 48)
        )
      end
    end)

    ingest!(
      feed!(%{class: "aggregator"}),
      for n <- 1..8 do
        named = if n <= 4, do: "Holding#{n} ", else: ""

        item("#{named}aggregator report #{n} on markets", "https://agg.example.com/#{n}", %{
          source_domain: "wire.example.com"
        })
      end,
      hours_ago(now, 6)
    )

    securities
  end

  defp tokens(%Plug.Conn{resp_body: body}), do: String.length(body) / 4

  # User story (ADR-0056 §9, §14 item 2):
  # As the operator whose agent pays for every token it reads,
  # I want the digest, a list page and one story to stay within their
  # budgets on a portfolio of 40 securities over a day,
  # so that reading the news costs the agent a known, small context.
  #
  # Acceptance criteria (characters / 4 of the JSON the tool returns):
  # - the digest over the last 24 hours, at its default max_rows (12, C5)
  #   with 14 securities active: 12 rows, truncated, at most 800 tokens;
  #   with nothing new: at most 100;
  # - 20 rows of news.list: at most 1,500;
  # - news.get of a story with a 160-character title and a 600-character
  #   excerpt (the worst case the ingest stores): at most 400.
  describe "the budgets (§14 item 2)" do
    test "digest, list and get stay within their budgets on 40 securities over 24 hours",
         %{conn: conn, now: now} do
      securities = forty!(now)

      day = digest(conn)
      # The default max_rows (12, C5) holds the budget: 14 securities have
      # news, 12 rows are shown and the other two said.
      assert %{"rows" => rows, "quiet" => 26, "unassigned" => 4} =
               data = json_response(day, 200)["data"]

      assert length(rows) == 12
      assert %{"truncated" => true, "more" => 2} = data

      # A caller may still ask for up to 40.
      wide = conn |> digest(max_rows: 40) |> json_response(200) |> Map.fetch!("data")
      assert length(wide["rows"]) == 14 and wide["truncated"] == false
      assert Enum.all?(rows, &(&1["count"] == 3 and String.length(&1["top"]["title"]) == 100))
      assert Enum.all?(rows, &String.ends_with?(&1["top"]["title"], "…"))
      assert tokens(day) <= 800, "digest: #{tokens(day)} tokens"

      unlabeled = digest(conn, include_unlabeled: true)
      assert length(json_response(unlabeled, 200)["data"]["rows"]) == 12

      nothing = digest(conn, since: iso(now))
      assert %{"rows" => [], "quiet" => 40} = json_response(nothing, 200)["data"]
      assert tokens(nothing) <= 100, "empty digest: #{tokens(nothing)} tokens"

      # 20 rows of one list page: the remainder of 40 securities' stories,
      # read as an agent pages a busy security.
      busy = hd(securities)
      busy_feed = issuer_feed!(busy)

      for story <- 4..23 do
        ingest!(busy_feed, [item(title(1, story), link(1, story, 1))], hours_ago(now, 1))
      end

      page = get(conn, "/api/v1/news/stories?security_id=#{busy.id}")
      assert length(json_response(page, 200)["data"]["rows"]) == 20
      assert json_response(page, 200)["data"]["truncated"] == true
      assert tokens(page) <= 1_500, "20 list rows: #{tokens(page)} tokens"

      story_id = story_of!(link(1, 1, 1))
      one = get(conn, "/api/v1/news/stories/#{story_id}")
      story = json_response(one, 200)["data"]
      assert String.length(story["title"]) == 160
      assert String.length(story["excerpt"]) == 600
      assert tokens(one) <= 400, "get: #{tokens(one)} tokens"

      item_id = Repo.get_by!(Item, canonical_url: link(1, 1, 1)).id
      one_item = get(conn, "/api/v1/news/items/#{item_id}")
      assert tokens(one_item) <= 400, "get (item): #{tokens(one_item)} tokens"
    end

    # User story (ADR-0056 §7, §14 item 8):
    # As the operator whose labeller may never have run,
    # I want every read to answer normally with no label stored at all,
    # so that nothing waits for the labeller.
    #
    # Acceptance criteria:
    # - With no label (none exists before Sprint 28), digest, list and get
    #   answer 200 with their rows, and no answer carries a label field.
    test "fail-open: with no label at all, digest, list and get answer normally (§14 item 8)",
         %{conn: conn, now: now} do
      [first | _] = forty!(now)

      for path <- [
            "/api/v1/news/digest",
            "/api/v1/news/stories?security_id=#{first.id}",
            "/api/v1/news/stories/#{story_of!(link(1, 1, 1))}"
          ] do
        response = get(conn, path)
        assert json_response(response, 200)["data"] != %{}, path
        refute response.resp_body =~ "label", path
        refute response.resp_body =~ "materiality", path
      end
    end
  end
end
