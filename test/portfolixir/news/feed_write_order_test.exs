defmodule Portfolixir.News.FeedWriteOrderTest do
  # #1457 (Sprint 30, K2; `Portfolixir.LockTable`, row 25): a feed's write
  # holds the feed's parents `FOR KEY SHARE` before the feed, and acts on
  # the feed as read under its lock. A feed whose parent changed between the
  # caller's read and the lock is not written with a parent the write does
  # not hold: the attempt rolls back and runs again on the feed as it is
  # now, at most three times. The move runs from a handler on the repo's
  # query event, right after each attempt's lock on the parents, inside the
  # write's transaction (so each attempt's rollback undoes it too); the
  # races on two real connections are
  # `test/portfolixir/lock_race/news_feed_rebind_order_test.exs`.
  use Portfolixir.DataCase, async: true

  import Ecto.Query

  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.News
  alias Portfolixir.News.Feed
  alias Portfolixir.NewsFixtures
  alias Portfolixir.Repo

  defp agent, do: Actor.api_token_rw("synthetic-agent")

  # Moves the feed onto each of `securities` in turn, one per lock the
  # write's attempts take on the parents.
  defp moving_feed(feed, securities, write) do
    test_pid = self()
    handler = "feed-write-order-#{System.unique_integer([:positive])}"
    moves = {__MODULE__, handler}
    Process.put(moves, securities)

    :ok =
      :telemetry.attach(
        handler,
        [:portfolixir, :repo, :query],
        fn _event, _measurements, metadata, _config ->
          with true <- self() == test_pid,
               %{source: "securities", query: query} when is_binary(query) <- metadata,
               true <- query =~ "FOR KEY SHARE",
               [next | rest] <- Process.get(moves) do
            Process.put(moves, rest)

            Repo.update_all(from(f in Feed, where: f.id == ^feed.id),
              set: [security_id: next.id]
            )
          end
        end,
        nil
      )

    try do
      write.()
    after
      :telemetry.detach(handler)
      Process.delete(moves)
    end
  end

  defp entries(feed) do
    Journal.list_entries(resource_type: "news_feed", limit: 50)
    |> Enum.filter(&(&1.resource_id == to_string(feed.id) and &1.operation == :update))
  end

  test "a feed moved once between the read and the lock is written as it is then" do
    first = NewsFixtures.security!("Moved Once Harbour AG")
    moved = NewsFixtures.security!("Moved Once Harbour Second AG")
    target = NewsFixtures.security!("Moved Once Harbour Target AG")
    feed = NewsFixtures.feed!(%{class: "issuer", security_id: first.id})

    written =
      moving_feed(feed, [moved], fn ->
        News.put_feed(agent(), %{security_id: target.id}, id: feed.id)
      end)

    assert {:ok, :updated, %Feed{security_id: target_id}} = written
    assert target_id == target.id
    assert Repo.get!(Feed, feed.id).security_id == target.id
    assert [entry] = entries(feed)
    assert entry.after["security_id"] == target.id
  end

  test "a feed moved at each of three attempts answers an error on its binding" do
    first = NewsFixtures.security!("Moved Thrice Harbour AG")

    moves =
      for n <- 1..3, do: NewsFixtures.security!("Moved Thrice Harbour #{n} AG")

    target = NewsFixtures.security!("Moved Thrice Harbour Target AG")
    feed = NewsFixtures.feed!(%{class: "issuer", security_id: first.id})

    written =
      moving_feed(feed, moves, fn ->
        News.put_feed(agent(), %{security_id: target.id}, id: feed.id)
      end)

    assert {:error, %Ecto.Changeset{} = changeset} = written
    assert %{security_id: [message]} = errors_on(changeset)
    assert message =~ "three times running"
    # Every attempt rolled back, the moves with it: nothing written.
    assert Repo.get!(Feed, feed.id).security_id == first.id
    assert entries(feed) == []
  end
end
