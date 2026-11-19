defmodule Portfolixir.LockRace.NewsFetchMergeOrderTest do
  # #1457 (Sprint 30 plan, K1): a news fetch against a security merge,
  # raced on two real connections by the lock-order harness (#996). The
  # fetch (`News.Ingest.ingest/3`) held its feed's row `FOR UPDATE` and then
  # inserted items whose foreign key takes their security `FOR KEY SHARE`;
  # the merge holds both securities `FOR UPDATE` and then asks for the
  # source's feeds `FOR NO KEY UPDATE` (`News.reassign_security/3`). Each
  # held what the other then asked for. The fetch now takes the feed's
  # parent row, its security or its category, `FOR KEY SHARE` before the
  # feed, as every other news writer takes the securities before any news
  # row (`Portfolixir.LockTable`, rows 13 and 23; ADR-0056 D4).
  #
  # The same order meets a category's delete, which holds the category
  # `FOR UPDATE` and then asks the feeds that name it `FOR KEY SHARE`
  # (the foreign key's restrict check).
  #
  # async: false -- the races share a scratch database and the barrier's
  # limits. Every name and host is synthetic.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.Lifecycle
  alias Portfolixir.LockRace
  alias Portfolixir.News.Cluster
  alias Portfolixir.News.Feed
  alias Portfolixir.News.Ingest
  alias Portfolixir.News.Item
  alias Portfolixir.News.Parser.Item, as: Parsed
  alias Portfolixir.NewsFixtures
  alias Portfolixir.Repo
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

  # Two securities of one name (the merge's resolvability guard), each with
  # an issuer feed of its own, and the operator's approved preview.
  defp world(name) do
    source = WorldFixtures.create_security!(name: "#{name} AG", ticker: nil)
    target = WorldFixtures.create_security!(name: "#{name} AG", ticker: nil)
    source_feed = feed!(%{class: "issuer", security_id: source.id})
    target_feed = feed!(%{class: "issuer", security_id: target.id})
    {:ok, preview} = Lifecycle.preview_security_merge(source.id, target.id)

    %{
      source: source,
      target: target,
      source_feed: source_feed,
      target_feed: target_feed,
      digest: preview.plan_digest
    }
  end

  defp merge(w) do
    Lifecycle.merge_security(agent(), w.source.id, w.target.id, %{
      plan_digest: w.digest,
      collapse_key_equal: false
    })
  end

  defp parsed do
    n = System.unique_integer([:positive])

    %Parsed{
      title: "Synthetic Harbour reports a quarter #{n}",
      link: "https://newsroom.example.com/release-#{n}"
    }
  end

  defp fetch(feed, item), do: Ingest.ingest(feed, [item], DateTime.utc_now())

  defp stored(item), do: Repo.get_by!(Item, canonical_url: item.link)

  # The story the stored item is in, or nil.
  defp story(item) do
    case stored(item) do
      %Item{cluster_id: nil} -> nil
      %Item{cluster_id: id} -> Repo.get!(Cluster, id)
    end
  end

  # The fetch's lock on its feed, and the merge's on the two securities.
  defp feed_lock?(%{source: "news_feeds", query: query}) when is_binary(query),
    do: query =~ "FOR UPDATE"

  defp feed_lock?(_metadata), do: false

  defp securities_lock?(%{source: "securities", query: query}) when is_binary(query),
    do: query =~ "FOR UPDATE"

  defp securities_lock?(_metadata), do: false

  # User story (#1457; ADR-0056 §4, D4; ADR-0050 §9):
  # As the operator merging a security while the fetcher stores the news of
  # its issuer feed,
  # I want the fetch and the merge to take turns,
  # so that neither is aborted by a deadlock, no fetched item is lost, and
  # every item of the merged-away security ends on the surviving one.
  #
  # Acceptance criteria:
  # - A fetch holding its feed's lock: the merge waits for it and applies;
  #   the item the fetch stored, and the feed, end on the target.
  # - A merge holding the securities' locks: the fetch of the source's feed
  #   waits for it, then stores its item on the target, where the merge
  #   moved the feed.
  # - A merge holding the securities' locks: a fetch of the target's own
  #   feed waits for it and stores its item on the target.
  # - Neither writer deadlocks (40P01) and no item is counted invalid.
  describe "a fetch and a security merge" do
    test "a fetch holding its feed's lock, then a merge that moves the feed", %{db: db} do
      w = world("Fetch First Harbour")
      item = parsed()

      # The fetch folds its item into the source's stories after its
      # commit, which the merge, released by that commit, may already be
      # removing: that recluster is then refused and logged (the moduledoc
      # of `News.Ingest`), and the merge's own full recluster of the target
      # takes the item.
      log =
        capture_log(fn ->
          {fetched, merged} =
            LockRace.race!(
              db,
              {fn -> fetch(w.source_feed, item) end, &feed_lock?/1},
              fn -> merge(w) end
            )

          send(self(), {:outcomes, fetched, merged})
        end)

      assert_received {:outcomes, fetched, merged}
      assert {:ok, %{stored: 1, invalid: 0}} = fetched
      assert {:ok, _record, :applied} = merged
      assert stored(item).security_id == w.target.id
      assert %Cluster{security_id: target_id} = story(item)
      assert target_id == w.target.id
      assert Repo.get!(Feed, w.source_feed.id).security_id == w.target.id

      for line <- String.split(log, "\n", trim: true), line =~ "[warning]" do
        assert line =~ "news stories of {:security, #{w.source.id}} (en) not written"
      end
    end

    test "a merge holding the securities' locks, then a fetch of the feed it moves",
         %{db: db} do
      w = world("Merge First Harbour")
      item = parsed()

      {merged, fetched} =
        LockRace.race!(
          db,
          {fn -> merge(w) end, &securities_lock?/1},
          fn -> fetch(w.source_feed, item) end
        )

      assert {:ok, _record, :applied} = merged
      assert {:ok, %{stored: 1, invalid: 0}} = fetched
      assert stored(item).security_id == w.target.id
      assert %Cluster{security_id: target_id} = story(item)
      assert target_id == w.target.id
      assert Repo.get!(Feed, w.source_feed.id).security_id == w.target.id
    end

    test "a merge holding the securities' locks, then a fetch of the target's feed",
         %{db: db} do
      w = world("Merge Target Harbour")
      item = parsed()

      {merged, fetched} =
        LockRace.race!(
          db,
          {fn -> merge(w) end, &securities_lock?/1},
          fn -> fetch(w.target_feed, item) end
        )

      assert {:ok, _record, :applied} = merged
      assert {:ok, %{stored: 1, invalid: 0}} = fetched
      assert stored(item).security_id == w.target.id
      assert %Cluster{security_id: target_id} = story(item)
      assert target_id == w.target.id
    end
  end

  # User story (#1457; ADR-0056 §2, §4):
  # As the operator deleting a category while the fetcher stores the news of
  # a thematic feed bound to it,
  # I want the delete to wait for the fetch and then be refused,
  # so that the fetched item is stored and the category kept, without a
  # deadlock.
  #
  # Acceptance criteria:
  # - A fetch holding its feed's lock: the delete waits for it, and is
  #   refused because a feed names the category; the item is stored.
  test "a fetch holding its feed's lock, then a delete of the feed's category", %{db: db} do
    category = NewsFixtures.category!()
    feed = feed!(%{class: "thematic", category_id: category.id})
    item = parsed()

    {fetched, deleted} =
      LockRace.race!(
        db,
        {fn -> fetch(feed, item) end, &feed_lock?/1},
        fn -> Classifications.delete_category(Actor.owner_ui(), category) end
      )

    assert {:ok, %{stored: 1, invalid: 0}} = fetched
    assert {:error, %Ecto.Changeset{}} = deleted
    assert stored(item).category_id == category.id
    assert %Cluster{category_id: category_id} = story(item)
    assert category_id == category.id
    assert Classifications.get_category(category.id)
  end
end
