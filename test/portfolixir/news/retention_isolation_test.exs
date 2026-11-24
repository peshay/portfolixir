defmodule Portfolixir.News.RetentionIsolationTest do
  # ADR-0056 §12, amendment of 2026-11-24 (F4): a retention run in which one
  # scope's removal fails, and the scheduler's record of the day. Synthetic
  # items and hosts only.
  #
  # Not async: one test installs a trigger on `news_items` inside its
  # sandbox transaction (rolled back with it), whose DDL locks the table
  # until then, and the scheduler's own process reads the database.
  use Portfolixir.DataCase, async: false

  import Ecto.Query
  import ExUnit.CaptureLog
  import Portfolixir.NewsFixtures

  alias Portfolixir.Clock
  alias Portfolixir.HeapCap
  alias Portfolixir.News.DigestConsumer
  alias Portfolixir.News.DigestCursor
  alias Portfolixir.News.FeedDay
  alias Portfolixir.News.Ingest
  alias Portfolixir.News.Item
  alias Portfolixir.News.Parser.Item, as: Parsed
  alias Portfolixir.News.Retention
  alias Portfolixir.News.Scheduler
  alias Portfolixir.Repo

  # Two securities with one expired issuer item each, an expired item no
  # security claims, day rows older than 30 days, and a digest consumer not
  # confirmed for 91 days.
  defp world!(now) do
    old = DateTime.add(now, -91, :day)
    first = security!("Synthetic Alpha AG")
    second = security!("Synthetic Beta AG")
    true = first.id < second.id

    for {security, tag} <- [{first, "alpha"}, {second, "beta"}] do
      feed = feed!(%{class: "issuer", security_id: security.id})
      item = %Parsed{title: "Old release #{tag}", link: "https://newsroom.example.com/#{tag}/1"}
      {:ok, %{stored: 1}} = Ingest.ingest(feed, [item], old)
    end

    aggregator = feed!(%{class: "aggregator", url: "https://search.example.com/rss-isolation"})

    unclaimed = %Parsed{
      title: "Synthetic market wrap naming no company",
      link: "https://search.example.com/r?u=isolation",
      source_domain: "wire.example.com"
    }

    {:ok, %{stored: 1}} = Ingest.ingest(aggregator, [unclaimed], old)

    {:ok, _consumer} =
      DigestCursor.consumer("isolation-stale", nil, now, String.duplicate("k", 32))

    Repo.update_all(from(c in DigestConsumer, where: c.name == "isolation-stale"),
      set: [updated_at: old]
    )

    %{first: first, second: second}
  end

  defp counts(now, %{first: first, second: second}) do
    oldest = now |> Clock.local_date() |> Date.add(-30)

    %{
      first: Repo.aggregate(from(i in Item, where: i.security_id == ^first.id), :count),
      second: Repo.aggregate(from(i in Item, where: i.security_id == ^second.id), :count),
      unclaimed: Repo.aggregate(from(i in Item, where: i.assignment == :unassigned), :count),
      old_day_rows: Repo.aggregate(from(d in FeedDay, where: d.day < ^oldest), :count),
      stale_consumers:
        Repo.aggregate(from(c in DigestConsumer, where: c.name == "isolation-stale"), :count)
    }
  end

  # Stands in for any failure of one scope's removal: the database refuses
  # the delete of this security's items.
  defp refuse_removal_of!(security) do
    Repo.query!("""
    CREATE FUNCTION synthetic_refused_removal() RETURNS trigger LANGUAGE plpgsql
    AS $$ BEGIN RAISE EXCEPTION 'synthetic failure'; END $$
    """)

    Repo.query!("""
    CREATE TRIGGER synthetic_refused_removal BEFORE DELETE ON news_items FOR EACH ROW
    WHEN (OLD.security_id = #{security.id}) EXECUTE FUNCTION synthetic_refused_removal()
    """)
  end

  # User story:
  # As the operator whose news layer must stay a staging area,
  # I want a retention run to finish for every scope but the one whose
  # removal failed,
  # so that one scope in trouble never keeps another scope's expired items,
  # the unclaimed items, the old day rows or an abandoned consumer (N-14).
  #
  # Acceptance criteria:
  # - With the removal of the first scope failing, the run answers
  #   `{:ok, summary}`: the second scope's expired item, the expired item no
  #   security claims, the day rows older than 30 days and the consumer not
  #   confirmed for 90 days are gone.
  # - The failing scope keeps its items, is counted in `scopes_failed` and
  #   named in the log; the next run tries it again.
  describe "a run with a failing scope" do
    test "prunes everything else and counts the scope" do
      now = DateTime.utc_now()
      world = world!(now)

      assert %{first: 1, second: 1, unclaimed: 1, stale_consumers: 1} = counts(now, world)
      assert counts(now, world).old_day_rows >= 1

      refuse_removal_of!(world.first)

      {result, log} = with_log(fn -> Retention.run(now) end)

      assert {:ok, %{scopes_failed: 1, items: 2, consumers: 1}} = result
      assert log =~ "{:security, #{world.first.id}} (en) kept for the next run"

      assert counts(now, world) ==
               %{first: 1, second: 0, unclaimed: 0, old_day_rows: 0, stale_consumers: 0}
    end

    test "with no failing scope the run counts none" do
      now = DateTime.utc_now()
      world = world!(now)

      assert {:ok, %{scopes_failed: 0, items: 3}} = Retention.run(now)

      assert counts(now, world) ==
               %{first: 0, second: 0, unclaimed: 0, old_day_rows: 0, stale_consumers: 0}
    end
  end

  defp scheduler!(opts) do
    serve(fn conn -> Plug.Conn.send_resp(conn, 200, rss([])) end)

    scheduler =
      start_supervised!(
        {Scheduler, [name: nil, enabled?: true, tick_ms: :timer.hours(1)] ++ opts}
      )

    Req.Test.allow(Portfolixir.News.Fetcher, self(), scheduler)
    scheduler
  end

  defp tick(scheduler) do
    send(scheduler, :tick)
    wait_until(fn -> :sys.get_state(scheduler).running == nil end)
    :sys.get_state(scheduler)
  end

  defp wait_until(check, tries \\ 200) do
    cond do
      check.() -> :ok
      tries == 0 -> flunk("condition never held")
      true -> Process.sleep(20) && wait_until(check, tries - 1)
    end
  end

  # User story:
  # As the operator,
  # I want a server day to count as retained only once a retention run
  # finished, a run that failed tried again after a bounded wait, and the
  # run held to the heap cap,
  # so that a failed run is neither forgotten until tomorrow nor repeated
  # at every tick, and cannot grow without limit (N-14).
  #
  # Acceptance criteria:
  # - A run that raises leaves the day unretained; the next tick does not
  #   run it again before the wait is over (an hour by default), and the
  #   first tick after it does.
  # - A run that finished is not run again that server day.
  # - The task that runs the retention carries the heap cap.
  describe "the scheduler's record of the day" do
    test "a failed run is not recorded, and is tried again only after the wait" do
      test_pid = self()

      failing = fn _now ->
        send(test_pid, :retention_ran)
        raise "synthetic failure"
      end

      waiting = scheduler!(retention: failing)

      {state, log} = with_log(fn -> tick(waiting) end)
      assert_received :retention_ran
      assert log =~ "news retention failed: synthetic failure"
      assert state.retained_on == nil

      # An hour's wait has not passed: this tick does not run it.
      tick(waiting)
      refute_received :retention_ran

      stop_supervised!(Scheduler)

      {:ok, calls} = Agent.start_link(fn -> 0 end)

      once = fn now ->
        send(test_pid, :retention_ran)
        if Agent.get_and_update(calls, &{&1, &1 + 1}) == 0, do: raise("synthetic failure")
        Retention.run(now)
      end

      retrying = scheduler!(retention: once, retention_retry_ms: 0)

      {state, _log} = with_log(fn -> tick(retrying) end)
      assert_received :retention_ran
      assert state.retained_on == nil

      state = tick(retrying)
      assert_received :retention_ran
      assert state.retained_on == Clock.local_date(DateTime.utc_now())

      tick(retrying)
      refute_received :retention_ran
    end

    test "the retention runs under the heap cap" do
      test_pid = self()

      retention = fn now ->
        send(test_pid, {:heap, Process.info(self(), :max_heap_size)})
        Retention.run(now)
      end

      tick(scheduler!(retention: retention))

      assert_received {:heap, {:max_heap_size, flag}}
      assert flag.size == HeapCap.max_heap_words()
      assert flag.kill
    end
  end
end
