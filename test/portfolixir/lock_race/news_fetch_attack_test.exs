defmodule Portfolixir.LockRace.NewsFetchAttackTest do
  # Sprint 30 plan D-5 item 5: the attack lens on K1 (#1457) before
  # integration, raced on two real connections by the lock-order harness
  # (#996): a deadlock fails the race. K1 has a news fetch
  # (`News.Ingest.ingest/3`) take its feed's parent row, the security or the
  # category, `FOR KEY SHARE` before its feed `FOR UPDATE`, read the feed
  # again under that lock, and run again (at most three times) when the
  # feed's parent changed between the two locks (`Portfolixir.LockTable`,
  # row 23). These cases try the paths K1's own race module
  # (`news_fetch_merge_order_test.exs`) does not: the parent changing between
  # the locks, the retry's bound, the feed deleted between them, two fetches
  # of one feed, a security's delete, a category's subtree delete, a
  # category delete that holds its lock first, and a fetch of the target's
  # own feed ahead of a merge.
  #
  # async: false -- the races share a scratch database and the barrier's
  # limits. Every name and host is synthetic.
  use ExUnit.Case, async: false

  import Ecto.Query
  import ExUnit.CaptureLog

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Classifications
  alias Portfolixir.Lifecycle
  alias Portfolixir.LockRace
  alias Portfolixir.News
  alias Portfolixir.News.Feed
  alias Portfolixir.News.FeedDay
  alias Portfolixir.News.Ingest
  alias Portfolixir.News.Item
  alias Portfolixir.News.Parser.Item, as: Parsed
  alias Portfolixir.News.Scheduler
  alias Portfolixir.NewsFixtures
  alias Portfolixir.Repo
  alias Portfolixir.ScratchDatabase
  alias Portfolixir.WorldFixtures

  @moduletag :lock_race

  setup_all do
    %{db: LockRace.database!()}
  end

  setup %{db: db} do
    Repo.put_dynamic_repo(db.repo)
    :ok
  end

  defp agent, do: Actor.api_token_rw("synthetic-agent")

  # Outside the sandbox the fixture's transaction-local actor needs a
  # transaction of its own.
  defp feed!(attrs) do
    {:ok, feed} = Repo.transaction(fn -> NewsFixtures.feed!(attrs) end)
    feed
  end

  defp security!(name), do: WorldFixtures.create_security!(name: name, ticker: nil)

  defp parsed do
    n = System.unique_integer([:positive])

    %Parsed{
      title: "Synthetic Harbour reports a quarter #{n}",
      link: "https://newsroom.example.com/release-#{n}"
    }
  end

  defp fetch(feed, item), do: Ingest.ingest(feed, [item], DateTime.utc_now())

  # A fetch that raises answers what it raised: the harness fails a race
  # whose writer raises, and these cases assert on the raise.
  defp fetch_or_raise(feed, item) do
    fetch(feed, item)
  rescue
    error -> {:raised, error}
  end

  defp items(item), do: Repo.all(from(i in Item, where: i.canonical_url == ^item.link))

  defp stored(item), do: Repo.get_by!(Item, canonical_url: item.link)

  defp rebind(feed, security_id),
    do: News.put_feed(agent(), %{security_id: security_id}, id: feed.id)

  # The fetch's lock on its feed's parent, and on its feed.
  defp parent_lock?(table) do
    fn
      %{source: ^table, query: query} when is_binary(query) -> query =~ "FOR KEY SHARE"
      _metadata -> false
    end
  end

  defp feed_lock?(%{source: "news_feeds", query: query}) when is_binary(query),
    do: query =~ "FOR UPDATE"

  defp feed_lock?(_metadata), do: false

  # A writer's FOR UPDATE on a row of `table` (a merge's or a delete's).
  defp update_lock?(table) do
    fn
      %{source: ^table, query: query} when is_binary(query) -> query =~ "FOR UPDATE"
      _metadata -> false
    end
  end

  # User story (#1457; ADR-0056 §2, §4, D4):
  # As the operator re-binding a feed that has no items yet while the
  # fetcher stores its first news,
  # I want the fetch to store its items on the security the feed names when
  # it commits,
  # so that no item lands on a security the feed no longer names and none is
  # lost.
  #
  # Acceptance criteria:
  # - A fetch holding the feed's first security `FOR KEY SHARE`: the
  #   re-binding passes (it asks neither lock the fetch holds), the fetch
  #   finds the feed moved under its lock, runs again on the new security
  #   and stores its item there, counted `stored`, not `invalid`.
  describe "the feed's parent changing between the fetch's two locks" do
    test "a fetch holding the feed's security, then a re-binding of the feed", %{db: db} do
      first = security!("Rebound Harbour AG")
      second = security!("Rebound Harbour Second AG")
      feed = feed!(%{class: "issuer", security_id: first.id})
      item = parsed()

      {fetched, rebound} =
        LockRace.race!(
          db,
          {fn -> fetch(feed, item) end, parent_lock?("securities")},
          fn -> rebind(feed, second.id) end,
          second: :passes
        )

      assert {:ok, :updated, %Feed{security_id: second_id}} = rebound
      assert second_id == second.id
      assert {:ok, %{stored: 1, invalid: 0}} = fetched
      assert stored(item).security_id == second.id
    end

    # Acceptance criteria:
    # - A feed re-bound at each of the fetch's three attempts: the fetch
    #   gives up and raises, stores nothing, and the scheduler records the
    #   fetch as failed on the feed (`last_error`, one error in the day's
    #   row), so the item is not lost silently: the next fetch reads it again.
    test "a feed re-bound at every attempt: the fetch gives up after three and is recorded",
         %{db: db} do
      [s0 | rest] = for n <- 0..3, do: security!("Restless Harbour #{n} AG")
      feed = feed!(%{class: "issuer", security_id: s0.id})
      item = parsed()
      {:ok, next} = Agent.start_link(fn -> rest end)

      # Each time the fetch has locked a security, another connection
      # re-binds the feed to the next one and commits, before the fetch
      # locks the feed.
      handler = "k1-attack-#{System.unique_integer([:positive])}"

      :ok =
        :telemetry.attach(
          handler,
          [:portfolixir, :repo, :query],
          fn _event, _measurements, metadata, _config ->
            if Process.get(:k1_attack_fetch) && parent_lock?("securities").(metadata) do
              case Agent.get_and_update(next, fn
                     [] -> {nil, []}
                     [security | left] -> {security, left}
                   end) do
                nil ->
                  :ok

                security ->
                  {:ok, :updated, _feed} =
                    fn -> ScratchDatabase.run(db, fn -> rebind(feed, security.id) end) end
                    |> Task.async()
                    |> Task.await()
              end
            end
          end,
          nil
        )

      try do
        log =
          capture_log(fn ->
            result =
              Scheduler.run_one(feed.id,
                fetch: fn feed, _opts ->
                  ScratchDatabase.run(db, fn ->
                    Process.put(:k1_attack_fetch, true)
                    fetch(feed, item)
                  end)
                end
              )

            send(self(), {:result, result})
          end)

        assert_received {:result, {:error, "fetch_failed"}}
        assert log =~ "news feed #{feed.id} was rebound 3 times during one fetch"
      after
        :telemetry.detach(handler)
      end

      assert items(item) == []
      stored_feed = Repo.get!(Feed, feed.id)
      assert stored_feed.last_error == "fetch_failed"
      assert stored_feed.security_id == List.last(rest).id
      assert [%FeedDay{errors: 1}] = Repo.all(from(d in FeedDay, where: d.feed_id == ^feed.id))
    end
  end

  # User story (#1457; ADR-0056 §12):
  # As the operator removing a feed while the fetcher stores its news,
  # I want the fetch to fail cleanly on the removed feed,
  # so that no deadlock aborts the removal and no item is stored on a feed
  # that is gone.
  #
  # Acceptance criteria:
  # - A fetch holding the feed's security: the delete passes, and the fetch
  #   finds no feed under its lock and raises (the scheduler records it), as
  #   a fetch of an already deleted feed did before K1. Nothing is stored.
  # - A delete holding the feed's row: the fetch takes the security, waits
  #   at the feed, and then raises the same way.
  describe "a feed deleted around the fetch's two locks" do
    test "a fetch holding the feed's security, then the feed's delete", %{db: db} do
      security = security!("Removed Harbour AG")
      feed = feed!(%{class: "issuer", security_id: security.id})
      item = parsed()

      {fetched, deleted} =
        LockRace.race!(
          db,
          {fn -> fetch_or_raise(feed, item) end, parent_lock?("securities")},
          fn -> News.delete_feed(agent(), feed.id) end,
          second: :passes
        )

      assert {:ok, %{feed: %Feed{}}} = deleted
      assert {:raised, %Ecto.NoResultsError{}} = fetched
      assert items(item) == []
      refute Repo.get(Feed, feed.id)
    end

    test "a delete holding the feed's row, then a fetch of it", %{db: db} do
      security = security!("Removing Harbour AG")
      feed = feed!(%{class: "issuer", security_id: security.id})
      item = parsed()

      {deleted, fetched} =
        LockRace.race!(
          db,
          {fn -> News.delete_feed(agent(), feed.id) end, update_lock?("news_feeds")},
          fn -> fetch_or_raise(feed, item) end
        )

      assert {:ok, %{feed: %Feed{}}} = deleted
      assert {:raised, %Ecto.NoResultsError{}} = fetched
      assert items(item) == []
    end
  end

  # User story (#1457; ADR-0056 §4):
  # As the operator whose scheduler and a manual "fetch now" fetch one feed
  # at once,
  # I want the two fetches to take turns,
  # so that an item both read is stored once.
  #
  # Acceptance criteria:
  # - A fetch holding its feed's row: the second takes the security beside
  #   it (`KS` meets `KS`), waits at the feed, and then reads the item as
  #   known; one row.
  test "two fetches of one feed", %{db: db} do
    security = security!("Twice Harbour AG")
    feed = feed!(%{class: "issuer", security_id: security.id})
    item = parsed()

    {first, second} =
      LockRace.race!(
        db,
        {fn -> fetch(feed, item) end, &feed_lock?/1},
        fn -> fetch(feed, item) end
      )

    assert {:ok, %{stored: 1, invalid: 0}} = first
    assert {:ok, %{stored: 0, known: 1, invalid: 0}} = second
    assert [%Item{security_id: security_id}] = items(item)
    assert security_id == security.id
  end

  # User story (#1457; ADR-0050 §11; ADR-0056 §2):
  # As the operator deleting a security while the fetcher stores the news of
  # its issuer feed,
  # I want the delete and the fetch to take turns,
  # so that the delete is refused (a feed names the security) without a
  # deadlock and the fetched item is stored.
  #
  # Acceptance criteria:
  # - A fetch holding its feed's lock: the delete waits at the security and
  #   is refused as referenced; the item is stored.
  # - A delete holding the security: the fetch waits at the security, the
  #   delete is refused, and the fetch stores its item.
  describe "a fetch and a security's delete" do
    test "a fetch holding its feed's lock, then the security's delete", %{db: db} do
      security = security!("Kept Harbour AG")
      feed = feed!(%{class: "issuer", security_id: security.id})
      item = parsed()

      {fetched, deleted} =
        LockRace.race!(
          db,
          {fn -> fetch(feed, item) end, &feed_lock?/1},
          fn -> Catalog.delete_security(Actor.owner_ui(), security) end
        )

      assert {:ok, %{stored: 1, invalid: 0}} = fetched
      assert {:error, {:referenced, _referenced_by}} = deleted
      assert stored(item).security_id == security.id
    end

    test "a delete holding the security, then a fetch of its feed", %{db: db} do
      security = security!("Held Harbour AG")
      feed = feed!(%{class: "issuer", security_id: security.id})
      item = parsed()

      {deleted, fetched} =
        LockRace.race!(
          db,
          {fn -> Catalog.delete_security(Actor.owner_ui(), security) end,
           update_lock?("securities")},
          fn -> fetch(feed, item) end
        )

      assert {:error, {:referenced, _referenced_by}} = deleted
      assert {:ok, %{stored: 1, invalid: 0}} = fetched
      assert stored(item).security_id == security.id
    end
  end

  # User story (#1457; ADR-0056 §2, §4):
  # As the operator deleting a category, or the category above it, while the
  # fetcher stores the news of a thematic feed bound to it,
  # I want the delete to be refused without a deadlock,
  # so that the fetched item is stored and the category kept.
  #
  # Acceptance criteria:
  # - A delete holding the feed's category: the fetch waits at the category,
  #   the delete is refused, and the item is stored.
  # - A fetch holding its feed's lock, then a delete of the category above
  #   the feed's (the subtree delete, leaves first): the delete waits at the
  #   feed's category and is refused; the item is stored.
  describe "a thematic fetch and a category's delete" do
    test "a delete holding the feed's category, then a fetch", %{db: db} do
      category = NewsFixtures.category!()
      feed = feed!(%{class: "thematic", category_id: category.id})
      item = parsed()

      {deleted, fetched} =
        LockRace.race!(
          db,
          {fn -> Classifications.delete_category(Actor.owner_ui(), category) end,
           update_lock?("classification_categories")},
          fn -> fetch(feed, item) end
        )

      assert {:error, %Ecto.Changeset{}} = deleted
      assert {:ok, %{stored: 1, invalid: 0}} = fetched
      assert stored(item).category_id == category.id
      assert Classifications.get_category(category.id)
    end

    test "a fetch holding its feed's lock, then a delete of the category above", %{db: db} do
      parent = NewsFixtures.category!()

      {:ok, child} =
        Classifications.create_category(Actor.owner_ui(), %{
          classification_id: parent.classification_id,
          parent_id: parent.id,
          name: "Rivers"
        })

      feed = feed!(%{class: "thematic", category_id: child.id})
      item = parsed()

      {fetched, deleted} =
        LockRace.race!(
          db,
          {fn -> fetch(feed, item) end, &feed_lock?/1},
          fn -> Classifications.delete_category(Actor.owner_ui(), parent) end
        )

      assert {:ok, %{stored: 1, invalid: 0}} = fetched
      assert {:error, %Ecto.Changeset{}} = deleted
      assert stored(item).category_id == child.id
      assert Classifications.get_category(child.id)
      assert Classifications.get_category(parent.id)
    end
  end

  # User story (#1457; ADR-0050 §9, §10; ADR-0056 §4):
  # As the operator merging a security while the fetcher stores the news of
  # the surviving security's own feed,
  # I want the merge to wait for the fetch,
  # so that neither is aborted and the item stays on the survivor.
  #
  # Acceptance criteria:
  # - A fetch of the target's feed holding its lock: the merge waits at the
  #   target's row and applies; the item is on the target.
  test "a fetch of the target's feed holding its lock, then a merge", %{db: db} do
    source = security!("Survivor Harbour AG")
    target = security!("Survivor Harbour AG")
    feed!(%{class: "issuer", security_id: source.id})
    target_feed = feed!(%{class: "issuer", security_id: target.id})
    {:ok, preview} = Lifecycle.preview_security_merge(source.id, target.id)
    item = parsed()

    {fetched, merged} =
      LockRace.race!(
        db,
        {fn -> fetch(target_feed, item) end, &feed_lock?/1},
        fn ->
          Lifecycle.merge_security(agent(), source.id, target.id, %{
            plan_digest: preview.plan_digest,
            collapse_key_equal: false
          })
        end
      )

    assert {:ok, %{stored: 1, invalid: 0}} = fetched
    assert {:ok, _record, :applied} = merged
    assert stored(item).security_id == target.id
  end
end
