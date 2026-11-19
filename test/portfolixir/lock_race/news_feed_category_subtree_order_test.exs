defmodule Portfolixir.LockRace.NewsFeedCategorySubtreeOrderTest do
  # Sprint 30 closing act, the edge-case and order lens, finding 1 (#1457,
  # `Portfolixir.LockTable`, row 25): a feed's write held its old and new
  # categories `FOR KEY SHARE` in id order, while a category's subtree
  # delete deletes its categories leaves first
  # (`Classifications.delete_category/2`), each DELETE taking the row
  # `FOR UPDATE`. A thematic feed re-bound from a parent category to its
  # child (the child created later, so of the higher id) asked the two rows
  # in the order opposite to the delete's, and deadlocked. The write now
  # takes only the category it binds the feed to. A deadlock fails the race.
  #
  # async: false -- the races share a scratch database. Every name is
  # synthetic.
  use ExUnit.Case, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.LockRace
  alias Portfolixir.News
  alias Portfolixir.NewsFixtures
  alias Portfolixir.Repo

  @moduletag :lock_race

  setup_all do
    %{db: LockRace.database!()}
  end

  setup %{db: db} do
    Repo.put_dynamic_repo(db.repo)
    :ok
  end

  defp feed!(attrs) do
    {:ok, feed} = Repo.transaction(fn -> NewsFixtures.feed!(attrs) end)
    feed
  end

  # The delete's DELETE of a category row (the child's, leaves first).
  defp category_delete?(%{query: query}) when is_binary(query),
    do: query =~ ~s(DELETE FROM "classification_categories")

  defp category_delete?(_metadata), do: false

  test "a subtree delete holding the child, then a re-binding from the parent to it",
       %{db: db} do
    parent = NewsFixtures.category!()

    {:ok, child} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: parent.classification_id,
        parent_id: parent.id,
        name: "Synthetic Rivers"
      })

    assert child.id > parent.id
    feed = feed!(%{class: "thematic", category_id: parent.id})

    {deleted, rebound} =
      LockRace.race!(
        db,
        {fn -> Classifications.delete_category(Actor.owner_ui(), parent) end,
         &category_delete?/1},
        fn -> News.put_feed(Actor.owner_ui(), %{category_id: child.id}, id: feed.id) end
      )

    # Whichever order the two take, neither is aborted by a deadlock: the
    # delete is refused (a feed names the parent, or then the child) or the
    # re-binding finds the child gone.
    assert match?({:error, _}, deleted) or match?({:ok, _}, deleted)
    assert match?({:ok, _, _}, rebound) or match?({:error, _}, rebound)
  end
end
