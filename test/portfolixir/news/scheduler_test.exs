defmodule Portfolixir.News.SchedulerTest do
  # ADR-0056 §5, §14 item 4, B6 (Sprint 27, N3): which feeds are due, the
  # fixture clock's freshness bound, and one feed's crash or timeout never
  # stopping another. Fake answers through Req's plug path only.
  use Portfolixir.DataCase, async: true

  import Ecto.Query
  import ExUnit.CaptureLog
  import Portfolixir.NewsFixtures

  alias Portfolixir.News
  alias Portfolixir.News.Feed
  alias Portfolixir.News.Item
  alias Portfolixir.News.Scheduler
  alias Portfolixir.Repo

  @t0 ~U[2026-11-07 10:00:00.000000Z]

  defp issuer_feed!(attrs \\ %{}),
    do: feed!(Map.merge(%{class: "issuer", security_id: security!().id}, attrs))

  defp items(feed), do: Repo.all(from(i in Item, where: i.feed_id == ^feed.id))

  defp reload(feed), do: Repo.get!(Feed, feed.id)

  defp static(body) do
    serve(fn conn -> Plug.Conn.send_resp(conn, 200, body) end)
    []
  end

  # User story:
  # As the operator,
  # I want each feed fetched on its own interval — its class's default unless
  # I set one — and not while it backs off or is switched off,
  # so that a feed is neither hammered nor forgotten.
  #
  # Acceptance criteria:
  # - Defaults: regulatory 10, issuer 15, aggregator 60, thematic 180 minutes.
  # - A feed never fetched is due; one fetched is due again after its
  #   interval; a disabled feed, or one whose `retry_at` lies ahead, is not.
  describe "which feeds are due" do
    test "by interval, backoff and the enabled flag" do
      security = security!()
      category = category!()

      defaults =
        for {class, binding, minutes} <- [
              {"regulatory", %{security_id: security.id}, 10},
              {"issuer", %{security_id: security.id}, 15},
              {"aggregator", %{}, 60},
              {"thematic", %{category_id: category.id}, 180}
            ] do
          feed = feed!(Map.put(binding, :class, class))
          assert feed.interval_minutes == minutes
          feed
        end

      for feed <- defaults do
        fetched = %{feed | last_fetch_at: @t0}
        assert Scheduler.due?(%{feed | last_fetch_at: nil}, @t0)
        refute Scheduler.due?(fetched, DateTime.add(@t0, feed.interval_minutes * 60 - 1))
        assert Scheduler.due?(fetched, DateTime.add(@t0, feed.interval_minutes, :minute))
      end

      own = issuer_feed!(%{interval_minutes: 5})
      assert Scheduler.due?(%{own | last_fetch_at: @t0}, DateTime.add(@t0, 5, :minute))

      refute Scheduler.due?(%{own | enabled: false}, @t0)

      backing_off = %{own | failures: 1, retry_at: DateTime.add(@t0, 30, :minute)}
      refute Scheduler.due?(backing_off, DateTime.add(@t0, 29, :minute))
      assert Scheduler.due?(backing_off, DateTime.add(@t0, 30, :minute))
    end

    test "with no enabled feed nothing is requested" do
      test_pid = self()
      issuer_feed!(%{enabled: false})

      plug = fn conn ->
        send(test_pid, :requested)
        Plug.Conn.send_resp(conn, 200, rss([]))
      end

      serve(plug)
      assert News.fetch_due(@t0) == []
      refute_received :requested
    end
  end

  # User story:
  # As the operator whose agent reads the news,
  # I want an item a feed publishes to be stored within its interval plus
  # five minutes,
  # so that what the digest calls new is never older than the feed's rhythm.
  #
  # Acceptance criteria (§14 item 4, with a fixture clock):
  # - With the scheduler's tick, an item that appears in a feed at time t is
  #   visible by t + the feed's interval + 5 minutes, for each class default
  #   and for an item appearing just after a fetch (the worst case).
  describe "freshness (§14 item 4)" do
    test "an item appearing at t is visible by t + interval + 5 minutes" do
      assert Scheduler.default_tick_ms() <= :timer.minutes(1)
      tick_minutes = div(Scheduler.default_tick_ms(), 60_000)

      security = security!()
      category = category!()

      for {class, binding} <- [
            {"regulatory", %{security_id: security.id}},
            {"issuer", %{security_id: security.id}},
            {"aggregator", %{}},
            {"thematic", %{category_id: category.id}}
          ],
          offset <- [1, 7] do
        feed = feed!(Map.put(binding, :class, class))
        {:ok, clock} = Agent.start_link(fn -> @t0 end)
        appears_at = DateTime.add(@t0, offset, :minute)

        plug = fn conn ->
          now = Agent.get(clock, & &1)

          published =
            if DateTime.compare(now, appears_at) == :lt,
              do: [],
              else: [
                %{
                  title: "Northwind files a report",
                  link: "https://newsroom.example.com/r/#{feed.id}",
                  source: "https://wire.example.com/"
                }
              ]

          Plug.Conn.send_resp(conn, 200, rss(published))
        end

        deadline = DateTime.add(appears_at, feed.interval_minutes + 5, :minute)

        visible_at =
          Stream.iterate(@t0, &DateTime.add(&1, tick_minutes, :minute))
          |> Enum.find(fn now ->
            Agent.update(clock, fn _ -> now end)
            serve(plug)
            News.fetch_due(now, clock: fn -> now end)
            items(feed) != [] or DateTime.compare(now, deadline) == :gt
          end)

        assert items(feed) != [], "#{class}, item at +#{offset} min: never visible"

        assert DateTime.compare(visible_at, deadline) != :gt,
               "#{class}, item at +#{offset} min: visible at #{visible_at}, after #{deadline}"

        assert [%{first_seen_at: ^visible_at}] = items(feed)

        # Closing act (flaky): each tick fetches this case's feed alone. The
        # feeds of the cases before it fell due again with it, and their
        # fetch tasks queued on this test's one sandbox connection; one that
        # held it past the queue's poll (a lock another test held, or load)
        # had the others dropped, each logging `fetch_failed`.
        Repo.update_all(from(f in Feed, where: f.id == ^feed.id), set: [enabled: false])
      end
    end
  end

  # User story:
  # As the operator,
  # I want each feed fetched in its own task,
  # so that a feed whose fetch crashes or never answers costs only its own
  # freshness, and records why.
  #
  # Acceptance criteria:
  # - Of three due feeds, one whose fetch raises and one that outlives the
  #   task's time do not stop the third from being stored.
  # - The crashed feed records `fetch_failed`, the stalled one `timeout`,
  #   each counted in its day's errors.
  # - On the real path, a plug that raises and one that stalls past the
  #   deadline are recorded on their own feeds and nowhere else.
  describe "isolation (§5)" do
    # Closing act (KNOWN, flaky): the healthy feed shared a 300 ms task time
    # with the stalled one and lost it under load. No wall clock decides
    # here: the stalled feed's task ends as a task killed at its time is
    # reported (`{:exit, :timeout}`), and the healthy one has the default
    # time; the kill itself is the next test's, with no other feed racing it.
    test "a crash and a timeout in one feed's task never stop another" do
      crashing = issuer_feed!()
      stalled = issuer_feed!()
      healthy = issuer_feed!()

      fetch = fn feed, opts ->
        cond do
          feed.id == crashing.id -> raise "synthetic crash"
          feed.id == stalled.id -> exit(:timeout)
          true -> News.Fetcher.fetch(feed, opts)
        end
      end

      body =
        rss([%{title: "Northwind ships", link: "https://newsroom.example.com/s/1"}])

      {results, log} =
        with_log(fn ->
          News.fetch_due(@t0, static(body) ++ [fetch: fetch, clock: fn -> @t0 end])
          |> Map.new()
        end)

      assert log =~ "news feed #{crashing.id}: fetch_failed (synthetic crash)"
      assert log =~ "news feed #{stalled.id}: timeout"

      assert {:ok, %{stored: 1}} = results[healthy.id]
      assert {:error, "fetch_failed"} = results[crashing.id]
      assert {:error, "timeout"} = results[stalled.id]

      assert [_item] = items(healthy)
      assert reload(healthy).last_ok_at == @t0
      assert %{last_error: "fetch_failed", last_ok_at: nil} = reload(crashing)
      assert %{last_error: "timeout", last_ok_at: nil} = reload(stalled)
    end

    test "a fetch that outlives its task's time is killed and recorded as a timeout" do
      stalled = issuer_feed!()
      test_pid = self()

      fetch = fn _feed, _opts ->
        send(test_pid, {:stalling, self()})
        Process.sleep(:infinity)
      end

      {results, log} =
        with_log(fn -> News.fetch_due(@t0, fetch: fetch, timeout_ms: 50) |> Map.new() end)

      assert_received {:stalling, task}
      refute Process.alive?(task)
      assert log =~ "news feed #{stalled.id}: timeout"
      assert {:error, "timeout"} = results[stalled.id]
      assert %{last_error: "timeout", last_ok_at: nil} = reload(stalled)
    end

    test "on the real path a raising and a stalling host are each their own feed's error" do
      raising = issuer_feed!(%{url: "https://raising.example.com/feed.xml"})
      stalling = issuer_feed!(%{url: "https://stalling.example.com/feed.xml"})
      healthy = issuer_feed!(%{url: "https://healthy.example.com/feed.xml"})

      plug = fn conn ->
        case conn.host do
          "raising.example.com" ->
            raise "synthetic host failure"

          "stalling.example.com" ->
            Process.sleep(30_000)
            Plug.Conn.send_resp(conn, 200, rss([]))

          _healthy ->
            Plug.Conn.send_resp(
              conn,
              200,
              rss([%{title: "Northwind ships", link: "https://healthy.example.com/s/1"}])
            )
        end
      end

      serve(plug)
      results = @t0 |> News.fetch_due(deadline_ms: 2_000) |> Map.new()

      assert {:ok, %{stored: 1}} = results[healthy.id]
      assert {:error, "fetch_failed"} = results[raising.id]
      assert {:error, "timeout"} = results[stalling.id]
      assert reload(healthy).last_error == nil
    end

    test "fetch_now fetches one feed on demand, and refuses a disabled or unknown one" do
      feed = issuer_feed!(%{interval_minutes: 180})
      body = rss([%{title: "Northwind ships", link: "https://newsroom.example.com/s/9"}])

      assert {:ok, %{stored: 1}} = News.fetch_now(feed.id, static(body) ++ [now: @t0])
      # Not due again for three hours, and fetched again on demand anyway.
      assert {:ok, %{stored: 0, known: 1}} =
               News.fetch_now(feed.id, static(body) ++ [now: DateTime.add(@t0, 1, :minute)])

      disabled = issuer_feed!(%{enabled: false})
      assert {:error, :disabled} = News.fetch_now(disabled.id, [])
      assert {:error, :not_found} = News.fetch_now(-1, [])
    end
  end
end
