defmodule PortfolixirWeb.ApiV1NewsUnfiledTest do
  # ADR-0056 B4, C3 and §6, amendment of 2026-11-24 (F5): an item a fetch
  # stored whose story could not be written. It is counted, filed by the
  # scheduler's next tick, and enters its scope when it is filed. Synthetic
  # names and hosts only; every answer comes from the test's plug.
  #
  # Not async: the failure of a story's write is a trigger on
  # `news_clusters`, created inside the test's sandbox transaction and
  # rolled back with it (its DDL locks the table until then), and the
  # scheduler's own process reads the database.
  use PortfolixirWeb.ConnCase

  import ExUnit.CaptureLog
  import Portfolixir.NewsFixtures, only: [feed!: 1, serve: 1, rss: 1]
  import Portfolixir.WorldFixtures, only: [create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.News.Item
  alias Portfolixir.News.Scheduler
  alias Portfolixir.News.Stories
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

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    %{conn: conn, now: now, earlier: DateTime.add(now, -600, :second)}
  end

  defp data(conn, path, query \\ []),
    do:
      conn |> get(path <> "?" <> URI.encode_query(query)) |> json_response(200) |> Map.get("data")

  defp watched!(name) do
    security = create_security!(name: name, ticker: nil, asset_class: "equity")
    {:ok, security} = Catalog.update_security(Actor.owner_ui(), security, %{news_watch: true})
    security
  end

  # Stands in for any failure of a story's write: the database refuses
  # every new story, or (`refuse_stories_of!/1`, after this one) those of
  # one security.
  defp refuse_stories! do
    Repo.query!("""
    CREATE FUNCTION synthetic_refused_story() RETURNS trigger LANGUAGE plpgsql
    AS $$ BEGIN RAISE EXCEPTION 'synthetic failure'; END $$
    """)

    Repo.query!("""
    CREATE TRIGGER synthetic_refused_story BEFORE INSERT ON news_clusters FOR EACH ROW
    EXECUTE FUNCTION synthetic_refused_story()
    """)
  end

  defp refuse_stories_of!(security) do
    Repo.query!("""
    CREATE TRIGGER synthetic_refused_story BEFORE INSERT ON news_clusters FOR EACH ROW
    WHEN (NEW.security_id = #{security.id}) EXECUTE FUNCTION synthetic_refused_story()
    """)
  end

  defp allow_stories!, do: Repo.query!("DROP TRIGGER synthetic_refused_story ON news_clusters")

  # One fetch of `feed` at the clock `at` whose story cannot be written.
  defp fetch_without_story!(feed, release, at) do
    serve(fn conn -> Plug.Conn.send_resp(conn, 200, rss([release])) end)
    {result, _log} = with_log(fn -> Scheduler.run_one(feed.id, clock: fn -> at end) end)
    assert result == {:error, "fetch_failed"}

    item = Repo.get_by!(Item, canonical_url: release.link)
    assert item.assignment == :assigned
    assert item.cluster_id == nil
    item
  end

  defp tick!(scheduler) do
    send(scheduler, :tick)
    wait_until(fn -> :sys.get_state(scheduler).running == nil end)
  end

  defp wait_until(check, tries \\ 200) do
    cond do
      check.() -> :ok
      tries == 0 -> flunk("condition never held")
      true -> Process.sleep(20) && wait_until(check, tries - 1)
    end
  end

  defp titles(list), do: Enum.map(list["rows"], & &1["title"])

  # User story:
  # As the operator whose agent reads the digest once a run,
  # I want an item whose story could not be written when it was fetched to
  # be filed by the scheduler's next tick, and to count as new from the
  # moment it is filed,
  # so that a stored issuer item is never left out of every read, and a
  # reader that confirmed in between still gets its story (N-15).
  #
  # Acceptance criteria:
  # - The scheduler's next tick files the item into a story, though the
  #   feed's next answer brings nothing new.
  # - The item enters its scope when it is filed (`scope_at`), later than
  #   the position a consumer confirmed in between: that consumer's next
  #   digest counts the story, and `news.list` with `since` at that
  #   position answers it.
  # - An item filed late by a later fetch's recluster is stamped the same.
  describe "an item whose story could not be written" do
    test "is filed by the next tick and read by a reader that had moved on", %{
      conn: conn,
      earlier: earlier
    } do
      security = watched!("Northwind Harbour Logistics AG")
      feed = feed!(%{class: "issuer", security_id: security.id})

      release = %{
        title: "Northwind Harbour issues a profit warning",
        link: "https://newsroom.example.com/unfiled/1"
      }

      refuse_stories!()
      stored = fetch_without_story!(feed, release, earlier)
      allow_stories!()

      # A consumer reads and confirms: its position is later than the
      # item's first sight.
      opened = data(conn, "/api/v1/news/digest", consumer: "unfiled-run")
      assert Enum.find(opened["rows"], &(&1["id"] == security.id)) == nil

      confirmed =
        data(conn, "/api/v1/news/digest", consumer: "unfiled-run", ack_cursor: opened["cursor"])

      {:ok, position, 0} = DateTime.from_iso8601(confirmed["since"])
      assert DateTime.compare(position, earlier) == :gt

      # The next tick: the feed is not due and answers nothing new.
      scheduler =
        start_supervised!({Scheduler, name: nil, enabled?: true, tick_ms: :timer.hours(1)})

      Req.Test.allow(Portfolixir.News.Fetcher, self(), scheduler)
      tick!(scheduler)

      filed = Repo.get!(Item, stored.id)
      assert is_integer(filed.cluster_id)
      assert DateTime.compare(filed.scope_at, position) == :gt
      assert DateTime.compare(filed.first_seen_at, earlier) == :eq

      digest = data(conn, "/api/v1/news/digest", consumer: "unfiled-run")
      row = Enum.find(digest["rows"], &(&1["id"] == security.id))
      assert row["count"] == 1
      assert row["top"]["title"] =~ "Northwind Harbour issues"

      listed =
        data(conn, "/api/v1/news/stories", security_id: security.id, since: confirmed["since"])

      assert titles(listed) == [release.title]
    end

    test "filed late by a later fetch, it enters its scope then", %{
      conn: conn,
      now: now,
      earlier: earlier
    } do
      security = watched!("Southwind Quay Shipping SE")
      feed = feed!(%{class: "issuer", security_id: security.id})

      first = %{
        title: "Southwind Quay issues a profit warning",
        link: "https://newsroom.example.com/unfiled/2"
      }

      second = %{
        title: "Southwind Quay names a new harbour master",
        link: "https://newsroom.example.com/unfiled/3"
      }

      refuse_stories!()
      stored = fetch_without_story!(feed, first, earlier)
      allow_stories!()

      between = DateTime.add(now, -300, :second)

      serve(fn conn -> Plug.Conn.send_resp(conn, 200, rss([first, second])) end)
      assert {:ok, %{stored: 1, known: 1}} = Scheduler.run_one(feed.id, clock: fn -> now end)

      filed = Repo.get!(Item, stored.id)
      assert is_integer(filed.cluster_id)
      assert DateTime.compare(filed.scope_at, now) == :eq

      listed =
        data(conn, "/api/v1/news/stories",
          security_id: security.id,
          since: DateTime.to_iso8601(between)
        )

      assert Enum.sort(titles(listed)) == Enum.sort([first.title, second.title])
    end
  end

  # User story:
  # As the operator's agent watching the collector,
  # I want the health read to count the assigned items that sit in no
  # story, and one scope whose stories cannot be written not to keep
  # another scope's items waiting,
  # so that a stored item no read shows is visible as a number, and a
  # scope in trouble is alone with it (N-15).
  #
  # Acceptance criteria:
  # - `GET /api/v1/news/health` answers `unfiled`: the assigned items in no
  #   story that entered their scope more than a fetch's time ago; 0 once
  #   they are filed.
  # - Filing the unfiled items reclusters each scope on its own: a scope
  #   that fails is counted and named in the log, and the others are filed.
  describe "the count and the sweep" do
    test "the health read counts the items in no story", %{conn: conn, now: now, earlier: earlier} do
      security = watched!("Westwind Pier Holdings AG")
      feed = feed!(%{class: "issuer", security_id: security.id})

      release = %{
        title: "Westwind Pier issues a profit warning",
        link: "https://newsroom.example.com/unfiled/4"
      }

      assert data(conn, "/api/v1/news/health")["unfiled"] == 0

      refuse_stories!()
      fetch_without_story!(feed, release, earlier)
      allow_stories!()

      assert data(conn, "/api/v1/news/health")["unfiled"] == 1

      assert %{scopes: 1, failed: 0} = Stories.recluster_unfiled(now)
      assert data(conn, "/api/v1/news/health")["unfiled"] == 0
    end

    test "a scope that cannot be filed keeps no other scope waiting", %{
      now: now,
      earlier: earlier
    } do
      troubled = watched!("Eastwind Dock Services AG")
      healthy = watched!("Northwind Canal Freight SE")
      true = troubled.id < healthy.id

      refuse_stories!()

      for {security, n} <- [{troubled, 5}, {healthy, 6}] do
        feed = feed!(%{class: "issuer", security_id: security.id})

        release = %{
          title: "Synthetic release number #{n}",
          link: "https://newsroom.example.com/unfiled/#{n}"
        }

        fetch_without_story!(feed, release, earlier)
      end

      allow_stories!()
      refuse_stories_of!(troubled)

      {result, log} = with_log(fn -> Stories.recluster_unfiled(now) end)

      assert result == %{scopes: 2, failed: 1}
      assert log =~ "{:security, #{troubled.id}} (en)"

      assert Repo.get_by!(Item, canonical_url: "https://newsroom.example.com/unfiled/5").cluster_id ==
               nil

      assert is_integer(
               Repo.get_by!(Item, canonical_url: "https://newsroom.example.com/unfiled/6").cluster_id
             )
    end
  end
end
