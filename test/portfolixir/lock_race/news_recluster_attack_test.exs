defmodule Portfolixir.LockRace.NewsReclusterAttackTest do
  # Sprint 31 plan, K1's attack lens (#1470; `Portfolixir.LockTable`,
  # row 28): the scope's lock (`Stories.lock_scope/2`, behind
  # `recluster/4`, `remove/5` and `lock/2`) takes the scope's parent, its
  # security or its category, `FOR KEY SHARE` before its advisory lock.
  # These races pin what that order meets beyond the recluster against a
  # merge: retention against a merge, a category's recluster against the
  # category's subtree delete and a feed's re-binding, a security's delete
  # against a merge (the delete's re-homed candidates fall to the merge's
  # source), an assignment whose item a merge moves under it, and a
  # recluster of a scope whose parent was deleted while it waited. Each
  # pauses one writer after a lock and runs the other on a second
  # connection; a deadlock (40P01) fails the race.
  #
  # async: false -- the races share a scratch database and the barrier's
  # limits. Every name and host is synthetic.
  use ExUnit.Case, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Classifications
  alias Portfolixir.Lifecycle
  alias Portfolixir.LockRace
  alias Portfolixir.News
  alias Portfolixir.News.Cluster
  alias Portfolixir.News.Item
  alias Portfolixir.News.Retention
  alias Portfolixir.News.Sources
  alias Portfolixir.News.Stories
  alias Portfolixir.NewsFixtures
  alias Portfolixir.Repo
  alias Portfolixir.WorldFixtures

  import Ecto.Query

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

  # An item of the scope `binding` with the one title, first seen `age`
  # seconds ago, on a feed of its own: an assigned aggregator item of a
  # security, a thematic item of a category, or an aggregator item
  # ambiguous between two securities.
  defp item!(binding, age \\ 3600) do
    domain = "rattack-#{System.unique_integer([:positive])}.example"
    link = "https://#{domain}/r-#{System.unique_integer([:positive])}"
    at = DateTime.add(DateTime.utc_now(), -age, :second)

    {feed, class, attrs} =
      case binding do
        {:security, id} ->
          {feed!(%{class: "aggregator"}), :aggregator, %{security_id: id, assignment: :assigned}}

        {:category, id} ->
          {feed!(%{class: "thematic", category_id: id}), :thematic,
           %{category_id: id, assignment: :assigned}}

        {:ambiguous, ids} ->
          {feed!(%{class: "aggregator"}), :aggregator, %{candidates: ids, assignment: :ambiguous}}
      end

    %Item{}
    |> Item.changeset(
      @title
      |> Stories.title_keys()
      |> Map.merge(attrs)
      |> Map.merge(%{
        feed_id: feed.id,
        class: class,
        first_seen_at: at,
        published_at: at,
        title: @title,
        canonical_url: link,
        domain: domain,
        tier: Sources.tier_for(domain, class),
        language: "en",
        content_hash: :sha256 |> :crypto.hash(link) |> Base.encode16(case: :lower)
      })
    )
    |> Repo.insert!()
  end

  defp security!(name), do: WorldFixtures.create_security!(name: name, ticker: nil)

  defp merge(source, target) do
    {:ok, preview} = Lifecycle.preview_security_merge(source.id, target.id)

    Lifecycle.merge_security(agent(), source.id, target.id, %{
      plan_digest: preview.plan_digest,
      collapse_key_equal: false
    })
  end

  defp recluster(scope), do: Stories.recluster(scope, "en", DateTime.utc_now())

  # The securities' row locks (the merge's, the delete's).
  defp securities_lock?(%{source: "securities", query: query}) when is_binary(query),
    do: query =~ "FOR UPDATE"

  defp securities_lock?(_metadata), do: false

  # The advisory lock of one scope and language (row 28's second lock): the
  # race pauses on this scope's, not on another's a run reaches first.
  defp scope_lock?({kind, id}) do
    key = :erlang.phash2({kind, id, "en"})

    fn
      %{query: query, params: params} when is_binary(query) and is_list(params) ->
        query =~ "pg_advisory_xact_lock" and key in params

      _metadata ->
        false
    end
  end

  defp items_write?(%{query: query}) when is_binary(query),
    do: String.starts_with?(query, ~s(UPDATE "news_items"))

  defp items_write?(_metadata), do: false

  defp category_delete?(%{query: query}) when is_binary(query),
    do: query =~ ~s(DELETE FROM "classification_categories")

  defp category_delete?(_metadata), do: false

  defp story_of!(item_id) do
    %Item{cluster_id: cluster_id} = item = Repo.get!(Item, item_id)
    assert %Cluster{} = story = Repo.get!(Cluster, cluster_id)
    {item, story}
  end

  # User story (#1470; ADR-0056 §4, §12, D4; ADR-0050 §9):
  # As the operator whose news layer is pruned, reclustered and re-bound
  # while securities and categories are merged and deleted,
  # I want every one of those writers to take turns at the scope's parent,
  # so that none is aborted by a deadlock and no item or story is left on
  # a row that no longer exists.
  #
  # Acceptance criteria:
  # - Retention holding a source's scope: the merge waits, and applies; the
  #   expired item and its story are gone, the fresh one is the target's.
  # - A merge holding the securities: retention waits, finds the source's
  #   scope empty and removes nothing of it; every item is the target's.
  # - A category's recluster holding the category: its subtree delete waits
  #   and is refused (stories name the category); a feed's re-binding to
  #   the child passes it without a wait.
  # - A subtree delete holding the categories: a recluster of a deleted
  #   category waits, then writes nothing.
  # - A security's delete holding an item it re-homes to another security:
  #   a merge of that other security waits and applies; the item ends the
  #   target's. And the merge holding the securities: the delete waits.
  # - A merge moving an item between an assignment's read and its lock: the
  #   assignment runs again and lands on its target.
  # - A recluster of a deleted security's scope waits and writes nothing.
  # - Neither writer deadlocks (40P01).
  describe "retention and a security merge" do
    test "retention holding the source's scope, then a merge", %{db: db} do
      source = security!("Retention Merge Quay AG")
      target = security!("Retention Merge Quay AG")
      old = item!({:security, source.id}, 100 * 86_400)
      fresh = item!({:security, source.id})
      {:ok, _} = Stories.recluster({:security, source.id}, "en", DateTime.utc_now(), full: true)
      {_old, old_story} = story_of!(old.id)

      {retained, merged} =
        LockRace.race!(
          db,
          {fn -> Retention.run(DateTime.utc_now()) end, scope_lock?({:security, source.id})},
          fn -> merge(source, target) end
        )

      assert {:ok, %{items: removed}} = retained
      assert removed >= 1
      assert {:ok, _record, :applied} = merged
      assert Repo.get(Item, old.id) == nil
      assert Repo.get(Cluster, old_story.id) == nil
      {item, story} = story_of!(fresh.id)
      assert item.security_id == target.id
      assert story.security_id == target.id
    end

    test "a merge holding the securities, then retention", %{db: db} do
      source = security!("Merge Retention Quay AG")
      target = security!("Merge Retention Quay AG")
      old = item!({:security, source.id}, 100 * 86_400)
      fresh = item!({:security, source.id})
      {:ok, _} = Stories.recluster({:security, source.id}, "en", DateTime.utc_now(), full: true)

      {merged, retained} =
        LockRace.race!(
          db,
          {fn -> merge(source, target) end, &securities_lock?/1},
          fn -> Retention.run(DateTime.utc_now()) end
        )

      assert {:ok, _record, :applied} = merged
      assert {:ok, _summary} = retained
      refute Catalog.get_security(source.id)
      # The expired item moved to the target before retention read the
      # source's scope: it waits for the next run, in the target's story.
      for id <- [old.id, fresh.id] do
        {item, story} = story_of!(id)
        assert item.security_id == target.id
        assert story.security_id == target.id
      end

      assert Repo.aggregate(from(c in Cluster, where: c.security_id == ^source.id), :count) == 0

      # Leave no expired item for another race's retention run.
      {:ok, _} = Retention.run(DateTime.utc_now())
      assert Repo.get(Item, old.id) == nil
    end
  end

  describe "a category's recluster" do
    test "a recluster holding the category, then the category's subtree delete", %{db: db} do
      parent = NewsFixtures.category!()

      {:ok, _child} =
        Classifications.create_category(Actor.owner_ui(), %{
          classification_id: parent.classification_id,
          parent_id: parent.id,
          name: "Synthetic Canals"
        })

      item = item!({:category, parent.id})

      {reclustered, deleted} =
        LockRace.race!(
          db,
          {fn -> recluster({:category, parent.id}) end, scope_lock?({:category, parent.id})},
          fn -> Classifications.delete_category(Actor.owner_ui(), parent) end
        )

      assert {:ok, %{stories: 1, created: 1}} = reclustered
      # The feed, the item and now its story name the category: refused.
      assert {:error, _reason} = deleted
      {_item, story} = story_of!(item.id)
      assert story.category_id == parent.id
      assert Classifications.get_category(parent.id)
    end

    test "a subtree delete holding a category, then a recluster of its scope", %{db: db} do
      parent = NewsFixtures.category!()

      {:ok, child} =
        Classifications.create_category(Actor.owner_ui(), %{
          classification_id: parent.classification_id,
          parent_id: parent.id,
          name: "Synthetic Weirs"
        })

      {deleted, reclustered} =
        LockRace.race!(
          db,
          {fn -> Classifications.delete_category(Actor.owner_ui(), parent) end,
           &category_delete?/1},
          fn -> recluster({:category, child.id}) end
        )

      assert {:ok, _category} = deleted
      # The category went while the recluster waited at it: nothing to
      # write, and no story names it.
      assert {:ok, %{stories: 0}} = reclustered
      refute Classifications.get_category(child.id)
      assert Repo.aggregate(from(c in Cluster, where: c.category_id == ^child.id), :count) == 0
    end

    test "a recluster holding the parent, then a feed re-bound from it to its child",
         %{db: db} do
      parent = NewsFixtures.category!()

      {:ok, child} =
        Classifications.create_category(Actor.owner_ui(), %{
          classification_id: parent.classification_id,
          parent_id: parent.id,
          name: "Synthetic Locks"
        })

      item!({:category, parent.id})
      empty = feed!(%{class: "thematic", category_id: parent.id})

      # The re-binding takes the child `FOR KEY SHARE` and the feed's row;
      # the recluster holds the parent `FOR KEY SHARE`: they share nothing.
      {reclustered, rebound} =
        LockRace.race!(
          db,
          {fn -> recluster({:category, parent.id}) end, scope_lock?({:category, parent.id})},
          fn -> News.put_feed(Actor.owner_ui(), %{category_id: child.id}, id: empty.id) end,
          second: :passes
        )

      assert {:ok, %{stories: 1}} = reclustered
      assert {:ok, _written, feed} = rebound
      assert feed.category_id == child.id
    end
  end

  describe "a security's delete and a merge of the security its candidates fall to" do
    # The delete holds its security, then re-homes the item ambiguous
    # between it and `other` (`News.forget_security/2`: the item's row, then
    # `other` FOR KEY SHARE by the foreign key) and reclusters `other`'s
    # stories; the merge of `other` holds both securities, then writes the
    # items that list `other`.
    test "the delete holding the re-homed item, then a merge of the other security",
         %{db: db} do
      doomed = security!("Doomed Candidate Quay AG")
      other = security!("Surviving Candidate Quay AG")
      target = security!("Surviving Candidate Quay AG")
      ambiguous = item!({:ambiguous, [doomed.id, other.id]})

      {deleted, merged} =
        LockRace.race!(
          db,
          {fn -> Catalog.delete_security(Actor.owner_ui(), doomed) end, &items_write?/1},
          fn -> merge(other, target) end
        )

      assert {:ok, _deleted} = deleted
      assert {:ok, _record, :applied} = merged
      {item, story} = story_of!(ambiguous.id)
      assert %Item{assignment: :assigned, candidates: []} = item
      assert item.security_id == target.id
      assert story.security_id == target.id
    end
  end

  describe "an assignment and a merge" do
    # The assignment reads the item in the source's scope and holds the
    # securities it names, in id order; the merge, holding the source
    # first, moves the item to its target. The assignment then finds it in
    # a scope whose security it does not hold (its late scope lock takes
    # that security `FOR KEY SHARE`), rolls back and runs again.
    test "a merge holding the securities, then an assignment of a source's item",
         %{db: db} do
      third = security!("Assign Third Quay AG")
      source = security!("Assign Merge Quay AG")
      target = security!("Assign Merge Quay AG")
      item = item!({:security, source.id})

      {merged, assigned} =
        LockRace.race!(
          db,
          {fn -> merge(source, target) end, &securities_lock?/1},
          fn -> News.assign_item(agent(), item.id, third.id) end
        )

      assert {:ok, _record, :applied} = merged
      assert {:ok, %Item{security_id: third_id, assignment: :assigned}} = assigned
      assert third_id == third.id
      {_item, story} = story_of!(item.id)
      assert story.security_id == third.id
    end
  end

  describe "a recluster of a deleted security's scope" do
    test "a delete holding the security, then a recluster of its scope", %{db: db} do
      doomed = security!("Vanishing Scope Quay AG")

      {deleted, reclustered} =
        LockRace.race!(
          db,
          {fn -> Catalog.delete_security(Actor.owner_ui(), doomed) end, &securities_lock?/1},
          fn -> recluster({:security, doomed.id}) end
        )

      assert {:ok, _deleted} = deleted
      assert {:ok, %{stories: 0}} = reclustered
      refute Catalog.get_security(doomed.id)
    end
  end
end
