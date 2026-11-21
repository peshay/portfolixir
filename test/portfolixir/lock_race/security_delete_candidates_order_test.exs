defmodule Portfolixir.LockRace.SecurityDeleteCandidatesOrderTest do
  # Sprint 31, K1's attack lens (#1470's family, `Portfolixir.LockTable`,
  # row 29): a security's delete against a merge, and against another
  # delete, over a news item ambiguous between two securities, raced on two
  # real connections by the lock-order harness (#996). The delete
  # (`Lifecycle.Delete.delete/2`) held its security `FOR UPDATE`, then
  # assigned each item left with one candidate to it
  # (`News.forget_security/2`): the item's row, then its foreign key's
  # `FOR KEY SHARE` on the security it falls to. A merge of that security
  # holds it `FOR UPDATE` and then rewrites the item's candidates; a delete
  # of it holds it `FOR UPDATE` and then rewrites the item too. Each held
  # what the other then asked for. The delete now takes its own security
  # `FOR UPDATE` and the securities its items fall to `FOR KEY SHARE` in one
  # pass, in id order, before any item, so the writers meet at a security.
  #
  # async: false -- the races share a scratch database and the barrier's
  # limits. Every name and host is synthetic.
  use ExUnit.Case, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Lifecycle
  alias Portfolixir.LockRace
  alias Portfolixir.News.Cluster
  alias Portfolixir.News.Item
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

  # An aggregator item ambiguous between the securities `ids`.
  defp ambiguous!(ids) do
    feed = feed!(%{class: "aggregator"})
    domain = "dorder-#{System.unique_integer([:positive])}.example"
    link = "https://#{domain}/r-#{System.unique_integer([:positive])}"
    at = DateTime.add(DateTime.utc_now(), -3600, :second)

    %Item{}
    |> Item.changeset(
      Map.merge(Stories.title_keys(@title), %{
        feed_id: feed.id,
        class: :aggregator,
        candidates: ids,
        assignment: :ambiguous,
        first_seen_at: at,
        published_at: at,
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

  defp security!(name), do: WorldFixtures.create_security!(name: name, ticker: nil)

  defp merge(source, target) do
    {:ok, preview} = Lifecycle.preview_security_merge(source.id, target.id)

    Lifecycle.merge_security(agent(), source.id, target.id, %{
      plan_digest: preview.plan_digest,
      collapse_key_equal: false
    })
  end

  defp delete(security), do: Catalog.delete_security(Actor.owner_ui(), security)

  defp securities_lock?(%{source: "securities", query: query}) when is_binary(query),
    do: query =~ "FOR UPDATE"

  defp securities_lock?(_metadata), do: false

  # The item, assigned to `security` and in one of its stories.
  defp assigned_to!(item_id, security) do
    item = Repo.get!(Item, item_id)
    assert %Item{assignment: :assigned, candidates: []} = item
    assert item.security_id == security.id
    assert %Cluster{security_id: story_security} = Repo.get!(Cluster, item.cluster_id)
    assert story_security == security.id
  end

  # User story (#1470's family; ADR-0056 §2, D4; ADR-0050 §9, §11):
  # As the operator deleting a security that a news item lists beside
  # another one while that other one is merged, or deleted too,
  # I want the two writes to take turns,
  # so that neither is aborted by a deadlock and the item ends assigned to
  # the security that survives both.
  #
  # Acceptance criteria:
  # - A merge holding the securities: the delete of the item's other
  #   candidate waits for it, then deletes and assigns the item to the
  #   merge's target.
  # - A delete holding its security and the item's other candidate: the
  #   merge of that candidate waits for it, then moves the item, now
  #   assigned to its source, onto its target.
  # - Two deletes of the item's two candidates: the second waits for the
  #   first, and is then refused, the item being assigned to it.
  # - No writer deadlocks (40P01).
  describe "a security's delete and an item ambiguous between two securities" do
    test "a merge holding the securities, then a delete of the item's other candidate",
         %{db: db} do
      doomed = security!("Doomed Candidate Quay AG")
      other = security!("Surviving Candidate Quay AG")
      target = security!("Surviving Candidate Quay AG")
      item = ambiguous!([doomed.id, other.id])

      {merged, deleted} =
        LockRace.race!(
          db,
          {fn -> merge(other, target) end, &securities_lock?/1},
          fn -> delete(doomed) end
        )

      assert {:ok, _record, :applied} = merged
      assert {:ok, _deleted} = deleted
      assert Catalog.get_security(doomed.id) == nil
      assigned_to!(item.id, target)
    end

    test "a delete holding its security and the other candidate, then a merge of that one",
         %{db: db} do
      other = security!("Merged Candidate Quay AG")
      target = security!("Merged Candidate Quay AG")
      doomed = security!("Doomed Late Quay AG")
      item = ambiguous!([doomed.id, other.id])

      {deleted, merged} =
        LockRace.race!(
          db,
          {fn -> delete(doomed) end, &securities_lock?/1},
          fn -> merge(other, target) end
        )

      assert {:ok, _deleted} = deleted
      assert {:ok, _record, :applied} = merged
      assigned_to!(item.id, target)
    end

    test "two deletes of the item's two candidates", %{db: db} do
      first = security!("Doomed One Quay AG")
      second = security!("Doomed Two Quay AG")
      item = ambiguous!([first.id, second.id])

      {deleted_second, deleted_first} =
        LockRace.race!(
          db,
          {fn -> delete(second) end, &securities_lock?/1},
          fn -> delete(first) end
        )

      assert {:ok, _deleted} = deleted_second
      assert {:error, {:referenced, %{"news_items" => 1}}} = deleted_first
      assert Catalog.get_security(first.id)
      assigned_to!(item.id, first)
    end
  end
end
