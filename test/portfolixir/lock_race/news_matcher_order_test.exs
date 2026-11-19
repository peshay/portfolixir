defmodule Portfolixir.LockRace.NewsMatcherOrderTest do
  # Sprint 30 plan D-5 item 5, the attack lens on K1 (#1457), break 2: the
  # news matcher (`News.assign_aggregator_items/2`, here through
  # `News.rematch_recent/1`, which `Catalog`'s identity change runs) against
  # a security merge and a security's delete, raced on two real connections
  # by the lock-order harness (#996). The matcher took `adv(matcher)`, then
  # the open items `FOR UPDATE`, then the securities they match
  # `FOR KEY SHARE`; the merge holds both securities `FOR UPDATE` and then
  # UPDATEs the items ambiguous between the two (`News.reassign_security/3`),
  # and the delete holds its security and then UPDATEs the items that list
  # it (`News.forget_security/2`). Each held what the other then asked for,
  # and a re-match outside a transaction lost that way was only logged,
  # its items left unmatched. The matcher now takes the securities first,
  # off an unlocked read of the items, as news.assign does
  # (`Portfolixir.LockTable`, rows 13, 21 and 26).
  #
  # async: false -- the races share a scratch database and the barrier's
  # limits. Every name and host is synthetic.
  use ExUnit.Case, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Lifecycle
  alias Portfolixir.LockRace
  alias Portfolixir.News
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

  defp merge(source, target) do
    {:ok, preview} = Lifecycle.preview_security_merge(source.id, target.id)

    Lifecycle.merge_security(agent(), source.id, target.id, %{
      plan_digest: preview.plan_digest,
      collapse_key_equal: false
    })
  end

  defp securities_lock?(%{source: "securities", query: query}) when is_binary(query),
    do: query =~ "FOR UPDATE"

  defp securities_lock?(_metadata), do: false

  # The matcher's lock on the items it writes.
  defp items_lock?(%{source: "news_items", query: query}) when is_binary(query),
    do: query =~ "FOR UPDATE"

  defp items_lock?(_metadata), do: false

  # User story (#1457; ADR-0056 §2, ORD5; ADR-0050 §9):
  # As the operator merging or deleting a security while the matcher
  # re-matches the week's open aggregator items,
  # I want the matcher and the merge (or the delete) to take turns,
  # so that neither is aborted by a deadlock and no item is left matched
  # against a security that no longer exists.
  #
  # Acceptance criteria:
  # - A merge holding the securities' locks: the re-match waits for it; the
  #   item ambiguous between the two is assigned to the target.
  # - A re-match holding the items' locks: the merge waits for it and
  #   applies; the item ends assigned to the target.
  # - A delete holding its security's lock: the re-match waits for it; the
  #   item that listed it with one other security is assigned to the other.
  # - Neither writer deadlocks (40P01).
  describe "a re-match and a security merge" do
    test "a merge holding the securities, then a re-match of an item ambiguous between them",
         %{db: db} do
      n = System.unique_integer([:positive])
      source = watched!("Ambiguous Harbour AG", "Sourcetoken#{n}")
      target = watched!("Ambiguous Harbour AG", "Targettoken#{n}")
      item = aggregator_item!("Sourcetoken#{n} and Targettoken#{n} sign a joint venture")
      assert %Item{assignment: :ambiguous} = Repo.get!(Item, item.id)

      {merged, rematched} =
        LockRace.race!(
          db,
          {fn -> merge(source, target) end, &securities_lock?/1},
          fn -> News.rematch_recent(DateTime.utc_now()) end
        )

      assert {:ok, _record, :applied} = merged
      assert {:ok, _counts} = rematched
      assert %Item{assignment: :assigned, security_id: target_id} = Repo.get!(Item, item.id)
      assert target_id == target.id
    end

    test "a re-match holding the items, then a merge of the securities they match",
         %{db: db} do
      n = System.unique_integer([:positive])
      source = watched!("Rematch First Harbour AG", "Firstsource#{n}")
      target = watched!("Rematch First Harbour AG", "Firsttarget#{n}")
      item = aggregator_item!("Firstsource#{n} and Firsttarget#{n} sign a joint venture")
      assert %Item{assignment: :ambiguous} = Repo.get!(Item, item.id)

      {rematched, merged} =
        LockRace.race!(
          db,
          {fn -> News.rematch_recent(DateTime.utc_now()) end, &items_lock?/1},
          fn -> merge(source, target) end
        )

      assert {:ok, %{ambiguous: ambiguous}} = rematched
      assert ambiguous >= 1
      assert {:ok, _record, :applied} = merged
      assert %Item{assignment: :assigned, security_id: target_id} = Repo.get!(Item, item.id)
      assert target_id == target.id
    end
  end

  describe "a re-match and a security's delete" do
    test "a delete holding a security, then a re-match of an item ambiguous with it",
         %{db: db} do
      n = System.unique_integer([:positive])
      doomed = watched!("Doomed Harbour AG", "Doomedtoken#{n}")
      other = watched!("Other Harbour AG", "Othertoken#{n}")
      item = aggregator_item!("Doomedtoken#{n} and Othertoken#{n} sign a joint venture")
      assert %Item{assignment: :ambiguous} = Repo.get!(Item, item.id)

      {deleted, rematched} =
        LockRace.race!(
          db,
          {fn -> Catalog.delete_security(Actor.owner_ui(), doomed) end, &securities_lock?/1},
          fn -> News.rematch_recent(DateTime.utc_now()) end
        )

      assert {:ok, _deleted} = deleted
      assert {:ok, _counts} = rematched
      assert %Item{assignment: :assigned, security_id: other_id} = Repo.get!(Item, item.id)
      assert other_id == other.id
    end

    test "a re-match holding the items, then a delete of a security they match", %{db: db} do
      n = System.unique_integer([:positive])
      doomed = watched!("Doomed First Harbour AG", "Doomedfirst#{n}")
      other = watched!("Other First Harbour AG", "Otherfirst#{n}")
      item = aggregator_item!("Doomedfirst#{n} and Otherfirst#{n} sign a joint venture")
      assert %Item{assignment: :ambiguous} = Repo.get!(Item, item.id)

      {rematched, deleted} =
        LockRace.race!(
          db,
          {fn -> News.rematch_recent(DateTime.utc_now()) end, &items_lock?/1},
          fn -> Catalog.delete_security(Actor.owner_ui(), doomed) end
        )

      assert {:ok, _counts} = rematched
      assert {:ok, _deleted} = deleted
      assert %Item{assignment: :assigned, security_id: other_id} = Repo.get!(Item, item.id)
      assert other_id == other.id
    end
  end

  # The fetch's own match after its commit (`News.Ingest`, row 23) takes
  # the same order: a merge holding the securities makes it wait, and the
  # item it stored is then matched against the target alone.
  test "a merge holding the securities, then a fetch whose item matches the source",
       %{db: db} do
    n = System.unique_integer([:positive])
    source = watched!("Fetch Match Harbour AG", "Fetchsource#{n}")
    target = watched!("Fetch Match Harbour AG", "Fetchtarget#{n}")
    feed = feed!(%{class: "aggregator", url: "https://search.example.com/rss-f#{n}"})
    link = "https://search.example.com/r?u=f#{n}"

    parsed =
      struct!(Parsed, %{
        title: "Fetchsource#{n} opens a harbour office",
        link: link,
        source_domain: "wire.example.com"
      })

    {merged, fetched} =
      LockRace.race!(
        db,
        {fn -> merge(source, target) end, &securities_lock?/1},
        fn -> Ingest.ingest(feed, [parsed], DateTime.utc_now()) end
      )

    assert {:ok, _record, :applied} = merged
    assert {:ok, %{stored: 1}} = fetched
    stored = Repo.get_by!(Item, canonical_url: link)
    refute stored.security_id == source.id
    refute source.id in stored.candidates
    assert Catalog.get_security(target.id)
  end

  defp watched!(name, token) do
    security = WorldFixtures.create_security!(name: name, ticker: nil, asset_class: "equity")

    {:ok, security} =
      Catalog.update_security(Actor.owner_ui(), security, %{
        news_watch: true,
        news_aliases: [%{token: token, context: [], case: "insensitive"}]
      })

    security
  end

  defp aggregator_item!(title) do
    n = System.unique_integer([:positive])
    feed = feed!(%{class: "aggregator", url: "https://search.example.com/rss-#{n}"})
    link = "https://search.example.com/r?u=#{n}"
    item = struct!(Parsed, %{title: title, link: link, source_domain: "wire.example.com"})
    {:ok, %{stored: 1}} = Ingest.ingest(feed, [item], DateTime.utc_now())
    Repo.get_by!(Item, canonical_url: link)
  end
end
