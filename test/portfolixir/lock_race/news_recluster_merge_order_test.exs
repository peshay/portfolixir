defmodule Portfolixir.LockRace.NewsReclusterMergeOrderTest do
  # #1470 (Sprint 31 plan, K1): a recluster of a security's stories against
  # a merge of that security, raced on two real connections by the
  # lock-order harness (#996). The recluster (`Stories.recluster/4`) takes
  # its scope's advisory lock, writes the stories (an UPDATE takes each
  # story's row) and then moves the items into them (an UPDATE of each
  # item's row). The merge holds both securities `FOR UPDATE` and then
  # writes the source's items (`scope_at`), its stories (`security_id`, a
  # column of a unique index, so each story `FOR UPDATE`) and its items
  # again (`News.reassign_security/3`). A recluster holding a story and a
  # merge holding its items each ask what the other holds. The recluster
  # now takes its scope's parent row, the security, `FOR KEY SHARE` before
  # its advisory lock, as every other news writer takes the securities
  # before any news row (`Portfolixir.LockTable`, rows 13 and 28; ADR-0056
  # D4), so the two meet at the security.
  #
  # async: false -- the races share a scratch database and the barrier's
  # limits. Every name and host is synthetic.
  use ExUnit.Case, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Lifecycle
  alias Portfolixir.LockRace
  alias Portfolixir.News.Cluster
  alias Portfolixir.News.Ingest
  alias Portfolixir.News.Item
  alias Portfolixir.News.Parser.Item, as: Parsed
  alias Portfolixir.News.Sources
  alias Portfolixir.News.Stories
  alias Portfolixir.NewsFixtures
  alias Portfolixir.Repo
  alias Portfolixir.WorldFixtures

  @moduletag :lock_race

  @title "Synthetic Quay wins a harbour tender"

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

  # An assigned item of `security` with the one title, on an aggregator
  # feed of its own, not yet in any story.
  defp item!(security) do
    feed = feed!(%{class: "aggregator"})
    domain = "rorder-#{System.unique_integer([:positive])}.example"
    link = "https://#{domain}/r-#{System.unique_integer([:positive])}"
    at = DateTime.add(DateTime.utc_now(), -3600, :second)

    %Item{}
    |> Item.changeset(
      Map.merge(Stories.title_keys(@title), %{
        feed_id: feed.id,
        class: :aggregator,
        security_id: security.id,
        assignment: :assigned,
        first_seen_at: at,
        title: @title,
        canonical_url: link,
        domain: domain,
        tier: Sources.tier_for(domain, :aggregator),
        language: "en",
        content_hash: :sha256 |> :crypto.hash(link) |> Base.encode16(case: :lower)
      })
    )
    |> Repo.insert!()
  end

  # Two securities of one name (the merge's resolvability guard), the
  # source with one story of one item, and the operator's approved preview.
  defp world(name) do
    source = WorldFixtures.create_security!(name: "#{name} AG", ticker: nil)
    target = WorldFixtures.create_security!(name: "#{name} AG", ticker: nil)
    first = item!(source)
    {:ok, _} = Stories.recluster({:security, source.id}, "en", DateTime.utc_now())
    {:ok, preview} = Lifecycle.preview_security_merge(source.id, target.id)

    %{
      source: source,
      target: target,
      story_id: Repo.get!(Item, first.id).cluster_id,
      digest: preview.plan_digest
    }
  end

  defp merge(w) do
    Lifecycle.merge_security(agent(), w.source.id, w.target.id, %{
      plan_digest: w.digest,
      collapse_key_equal: false
    })
  end

  defp recluster(w), do: Stories.recluster({:security, w.source.id}, "en", DateTime.utc_now())

  # The recluster's write of a story, and the merge's first write of the
  # source's items.
  defp story_write?(%{query: query}) when is_binary(query),
    do: String.starts_with?(query, ~s(UPDATE "news_clusters"))

  defp story_write?(_metadata), do: false

  defp items_write?(%{query: query}) when is_binary(query),
    do: String.starts_with?(query, ~s(UPDATE "news_items"))

  defp items_write?(_metadata), do: false

  # The story the item is in, which must be one of the target's.
  defp target_story!(item_id, w) do
    %Item{cluster_id: cluster_id, security_id: security_id} = Repo.get!(Item, item_id)
    assert security_id == w.target.id
    assert %Cluster{security_id: story_security} = Repo.get!(Cluster, cluster_id)
    assert story_security == w.target.id
    cluster_id
  end

  # User story (#1470; ADR-0056 §4, D4; ADR-0050 §9):
  # As the operator merging a security while its news stories are
  # rewritten,
  # I want the recluster and the merge to take turns,
  # so that neither is aborted by a deadlock and every item of the
  # merged-away security ends in a story of the surviving one.
  #
  # Acceptance criteria:
  # - A recluster holding a story of the source: the merge waits for it and
  #   applies; the item the recluster folded in ends in the target's story.
  # - A merge holding the source's items: the recluster of the source waits
  #   for it, and then finds nothing left to write; the merge's own
  #   recluster of the target folds the item in.
  # - A fetch's recluster after its commit, holding a story of the source:
  #   the merge waits for it and applies.
  # - Neither writer deadlocks (40P01).
  describe "a recluster and a security merge" do
    test "a recluster holding a story of the source, then a merge", %{db: db} do
      w = world("Recluster First Quay")
      second = item!(w.source)

      {reclustered, merged} =
        LockRace.race!(db, {fn -> recluster(w) end, &story_write?/1}, fn -> merge(w) end)

      assert {:ok, %{stories: 1, moved: 1}} = reclustered
      assert {:ok, _record, :applied} = merged
      assert target_story!(second.id, w) == w.story_id
    end

    test "a merge holding the source's items, then a recluster of the source", %{db: db} do
      w = world("Merge First Quay")
      second = item!(w.source)

      {merged, reclustered} =
        LockRace.race!(db, {fn -> merge(w) end, &items_write?/1}, fn -> recluster(w) end)

      assert {:ok, _record, :applied} = merged
      assert {:ok, %{stories: 0}} = reclustered
      assert target_story!(second.id, w) == w.story_id
    end

    test "a fetch's recluster after its commit, holding a story, then a merge", %{db: db} do
      w = world("Fetch Recluster Quay")
      feed = feed!(%{class: "issuer", security_id: w.source.id})
      parsed = %Parsed{title: @title, link: "https://newsroom.example.com/k1-tender"}

      {fetched, merged} =
        LockRace.race!(
          db,
          {fn -> Ingest.ingest(feed, [parsed], DateTime.utc_now()) end, &story_write?/1},
          fn -> merge(w) end
        )

      assert {:ok, %{stored: 1, invalid: 0}} = fetched
      assert {:ok, _record, :applied} = merged
      item = Repo.get_by!(Item, canonical_url: parsed.link)
      assert target_story!(item.id, w) == w.story_id
    end
  end
end
