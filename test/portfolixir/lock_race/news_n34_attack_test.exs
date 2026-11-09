defmodule Portfolixir.LockRace.NewsN34AttackTest do
  # Sprint 28 plan D-8 (carry-forwards 1 and 5): the order lens's attack on
  # news.assign (N4) and the digest consumer's creation (N3), raced on two
  # real connections by the lock-order harness (#996): a deadlock fails the
  # race. Cases tagged `:n34_attack_red` show a lock cycle the attack found
  # and fail until it is fixed.
  #
  # news.assign took the matcher's advisory lock, the scope lock of the
  # item's security, the item's row FOR UPDATE, and then the target security
  # FOR KEY SHARE. A security merge takes both securities FOR UPDATE first
  # and the source's items' rows later (`Portfolixir.News.reassign_security/3`).
  # So each held what the other waited for. Since the closing act (AT4)
  # news.assign holds the securities first, in id order
  # (`Portfolixir.LockTable`, row 21).
  #
  # async: false -- the races share a scratch database and the barrier's
  # limits.
  #
  # Every name is synthetic.
  use ExUnit.Case, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Lifecycle
  alias Portfolixir.LockRace
  alias Portfolixir.News
  alias Portfolixir.News.DigestConsumer
  alias Portfolixir.News.DigestCursor
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
    # Outside the sandbox the fixture's transaction-local actor needs a
    # transaction of its own.
    {:ok, feed} =
      Repo.transaction(fn ->
        NewsFixtures.feed!(%{class: "aggregator", url: "https://search.example.com/rss-#{n}"})
      end)

    link = "https://search.example.com/r?u=#{n}"
    item = struct!(Parsed, %{title: title, link: link, source_domain: "wire.example.com"})
    {:ok, %{stored: 1}} = Ingest.ingest(feed, [item], DateTime.utc_now())
    Repo.get_by!(Item, canonical_url: link)
  end

  # Two securities of one name (the merge's resolvability guard), the
  # source matched by the item's title, the target by another token.
  defp world(name) do
    n = System.unique_integer([:positive])
    source = watched!("#{name} AG", "Sourcetoken#{n}")
    target = watched!("#{name} AG", "Targettoken#{n}")
    item = aggregator_item!("Sourcetoken#{n} reports third quarter results")
    assert %Item{assignment: :assigned, security_id: source_id} = Repo.get!(Item, item.id)
    assert source_id == source.id
    {:ok, preview} = Lifecycle.preview_security_merge(source.id, target.id)
    %{source: source, target: target, item: item, digest: preview.plan_digest}
  end

  defp merge(w) do
    Lifecycle.merge_security(agent(), w.source.id, w.target.id, %{
      plan_digest: w.digest,
      collapse_key_equal: false
    })
  end

  defp item_lock?(%{query: query}) when is_binary(query),
    do: query =~ ~s(FROM "news_items") and query =~ "FOR UPDATE"

  defp item_lock?(_metadata), do: false

  defp securities_lock?(%{source: "securities", query: query}) when is_binary(query),
    do: query =~ "FOR UPDATE"

  defp securities_lock?(_metadata), do: false

  # User story (plan D-8 carry-forward 5, the order lens):
  # As the operator merging a security while my agent assigns one of its
  # news items by hand,
  # I want the two writes to wait for each other in one order,
  # so that neither fails with a deadlock and the item ends where the later
  # write puts it.
  #
  # Acceptance criteria:
  # - The assignment holding the item's row lock while the merge starts:
  #   no deadlock, both answer.
  # - The merge holding the securities' locks while the assignment starts:
  #   no deadlock, both answer.
  test "an assignment holding the item's lock, then a merge of its security", %{db: db} do
    w = world("Assign First Harbour")

    {assigned, merged} =
      LockRace.race!(
        db,
        {fn -> News.assign_item(agent(), w.item.id, w.target.id) end, &item_lock?/1},
        fn -> merge(w) end
      )

    assert {:ok, _item} = assigned
    assert {:ok, _record, :applied} = merged
    assert Repo.get!(Item, w.item.id).security_id == w.target.id
  end

  test "a merge holding the securities' locks, then an assignment of the source's item",
       %{db: db} do
    w = world("Merge First Harbour")

    {merged, assigned} =
      LockRace.race!(
        db,
        {fn -> merge(w) end, &securities_lock?/1},
        fn -> News.assign_item(agent(), w.item.id, w.target.id) end
      )

    assert {:ok, _record, :applied} = merged
    assert match?({:ok, _item}, assigned) or match?({:error, %{"security_id" => _}}, assigned)
    assert Repo.get!(Item, w.item.id).security_id == w.target.id
  end

  # User story (ADR-0056 C3, §9 at least once; closing act, AT8):
  # As the operator whose agent assigns an item while another write holds
  # the target security,
  # I want the item to enter its new scope at the time the assignment
  # writes, not at the time it started waiting,
  # so that a consumer that confirmed a position while it waited still
  # reads the item as new.
  #
  # Acceptance criteria:
  # - An assignment that waited on a lock of the target security stamps
  #   scope_at after the holder's last statement, not before its wait.
  test "an assignment that waited on its target stamps scope_at after the wait", %{db: db} do
    _source = watched!("Waiting Harbour AG", "Waitingharbour")
    target = watched!("Quay Holding AG", "Quayholding")
    item = aggregator_item!("Waitingharbour reports third quarter results")

    {released_at, assigned} =
      LockRace.race!(
        db,
        {fn ->
           {:ok, at} =
             Repo.transaction(fn ->
               Repo.query!("SELECT id FROM securities WHERE id = $1 FOR UPDATE", [target.id])
               DateTime.utc_now()
             end)

           at
         end, LockRace.query?("FOR UPDATE")},
        fn -> News.assign_item(agent(), item.id, target.id) end
      )

    assert {:ok, %Item{scope_at: scope_at}} = assigned

    assert DateTime.compare(scope_at, released_at) == :gt,
           "scope_at #{scope_at} was read before the wait, which ended after #{released_at}"
  end

  # User story (ADR-0056 §9, the cap; plan D-8 security lens):
  # As the operator whose agents name consumers concurrently,
  # I want two new consumers racing for the last slot to leave exactly 32,
  # so that the cap holds under concurrency.
  #
  # Acceptance criteria:
  # - With 31 stored, two creations racing: one is stored, the other is
  #   refused with the cap; the second waits on the first's creation lock.
  test "two new consumers racing for the 32nd slot: one stored, one refused", %{db: db} do
    Repo.delete_all(DigestConsumer)
    key = :crypto.strong_rand_bytes(32)
    now = DateTime.utc_now()
    for n <- 1..31, do: {:ok, _} = DigestCursor.consumer("slot-#{n}", nil, now, key)

    {first, second} =
      LockRace.race!(
        db,
        {fn -> DigestCursor.consumer("racer-a", nil, now, key) end,
         LockRace.query?("pg_advisory_xact_lock")},
        fn -> DigestCursor.consumer("racer-b", nil, now, key) end
      )

    assert {:ok, %DigestConsumer{name: "racer-a"}} = first
    assert second == {:error, {:cap, 32}}
    assert Repo.aggregate(DigestConsumer, :count) == 32
  end
end
