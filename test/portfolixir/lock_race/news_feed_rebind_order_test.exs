defmodule Portfolixir.LockRace.NewsFeedRebindOrderTest do
  # Sprint 30 plan D-5 item 5, the attack lens on K1 (#1457), break 1: a
  # feed's re-binding (`News.put_feed/3`, a feed with no items, COR1)
  # against a security merge, raced on two real connections by the
  # lock-order harness (#996). The re-binding held the feed `FOR NO KEY
  # UPDATE` (the journal's lock step) and then its UPDATE's foreign key took
  # the new security `FOR KEY SHARE`; the merge holds both securities
  # `FOR UPDATE` and then asks the source's feeds `FOR NO KEY UPDATE`
  # (`News.reassign_security/3`). Each held what the other then asked for.
  # The re-binding now takes the feed's old and new parent `FOR KEY SHARE`
  # before the feed, as a fetch does (`Portfolixir.LockTable`, rows 13, 23
  # and 25).
  #
  # async: false -- the races share a scratch database and the barrier's
  # limits. Every name and host is synthetic.
  use ExUnit.Case, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Lifecycle
  alias Portfolixir.LockRace
  alias Portfolixir.News
  alias Portfolixir.News.Feed
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

  defp feed_row_lock?(%{source: "news_feeds", query: query}) when is_binary(query),
    do: query =~ "FOR NO KEY UPDATE"

  defp feed_row_lock?(_metadata), do: false

  # User story (#1457; ADR-0056 §9, B1; ADR-0050 §9):
  # As the operator re-binding an issuer feed while a merge of its security
  # runs,
  # I want the re-binding and the merge to take turns,
  # so that neither is aborted by a deadlock and the feed ends on the
  # surviving security.
  #
  # Acceptance criteria:
  # - A merge holding the securities' locks: the re-binding of the source's
  #   feed onto the target waits for it, then finds the feed already there.
  # - A merge holding the securities' locks: a re-binding of the source's
  #   feed onto a third security waits for it, then moves the feed from the
  #   target, where the merge left it, onto the third.
  # - A re-binding holding the feed's lock: the merge waits for it and
  #   applies; the feed is on the target.
  # - Neither writer deadlocks (40P01).
  describe "a feed's re-binding onto the merge's target" do
    test "a merge holding the securities, then a re-binding of the source's feed", %{db: db} do
      source = WorldFixtures.create_security!(name: "Rebind Merge Harbour AG", ticker: nil)
      target = WorldFixtures.create_security!(name: "Rebind Merge Harbour AG", ticker: nil)
      feed = feed!(%{class: "issuer", security_id: source.id})

      {merged, rebound} =
        LockRace.race!(
          db,
          {fn -> merge(source, target) end, &securities_lock?/1},
          fn -> News.put_feed(agent(), %{security_id: target.id}, id: feed.id) end
        )

      assert {:ok, _record, :applied} = merged
      assert {:ok, :updated, %Feed{security_id: target_id}} = rebound
      assert target_id == target.id
      assert Repo.get!(Feed, feed.id).security_id == target.id
    end

    # The re-binding read the feed on the source before the merge; it waits
    # at the source, then writes the feed as the merge left it, re-bound
    # from the target onto the third security.
    test "a merge holding the securities, then a re-binding of the source's feed elsewhere",
         %{db: db} do
      source = WorldFixtures.create_security!(name: "Rebind Away Harbour AG", ticker: nil)
      target = WorldFixtures.create_security!(name: "Rebind Away Harbour AG", ticker: nil)
      third = WorldFixtures.create_security!(name: "Rebind Third Harbour AG", ticker: nil)
      feed = feed!(%{class: "issuer", security_id: source.id})

      {merged, rebound} =
        LockRace.race!(
          db,
          {fn -> merge(source, target) end, &securities_lock?/1},
          fn -> News.put_feed(agent(), %{security_id: third.id}, id: feed.id) end
        )

      assert {:ok, _record, :applied} = merged
      assert {:ok, :updated, %Feed{security_id: third_id}} = rebound
      assert third_id == third.id
      assert Repo.get!(Feed, feed.id).security_id == third.id
    end

    test "a re-binding holding the source's feed, then a merge", %{db: db} do
      source = WorldFixtures.create_security!(name: "Rebind First Harbour AG", ticker: nil)
      target = WorldFixtures.create_security!(name: "Rebind First Harbour AG", ticker: nil)
      feed = feed!(%{class: "issuer", security_id: source.id})

      {rebound, merged} =
        LockRace.race!(
          db,
          {fn -> News.put_feed(agent(), %{security_id: target.id}, id: feed.id) end,
           &feed_row_lock?/1},
          fn -> merge(source, target) end
        )

      assert {:ok, :updated, %Feed{security_id: target_id}} = rebound
      assert target_id == target.id
      assert {:ok, _record, :applied} = merged
      assert Repo.get!(Feed, feed.id).security_id == target.id
    end
  end
end
