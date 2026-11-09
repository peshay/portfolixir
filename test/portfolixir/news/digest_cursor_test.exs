defmodule Portfolixir.News.DigestCursorTest do
  # ADR-0056 §9 (Sprint 28, N3), plan D-1 criterion 4 and D-8's order lens:
  # the consumer cursor under interleaved writers. A second confirmation
  # runs at the exact point of the first through `Portfolixir.Interleave`,
  # as Sprint 27's ORD tests did. Synthetic names only.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Interleave
  alias Portfolixir.News
  alias Portfolixir.News.DigestConsumer
  alias Portfolixir.Repo

  @now ~U[2026-11-09 12:00:00Z]
  @key :crypto.hash(:sha256, "synthetic cursor key")

  defp at(hours), do: DateTime.add(@now, -hours * 3600, :second)

  defp position(name), do: Repo.get_by!(DigestConsumer, name: name).position

  defp consumer_query?(%{query: query}), do: query =~ "news_digest_consumers"

  # User story (ADR-0056 §9; plan D-1 criterion 4, D-8 carry-forward 5):
  # As the operator whose agent runs twice at once by mistake,
  # I want two confirmations of one consumer that race to end at the newer
  # position, never the older,
  # so that a slow run confirming late cannot make the next run skip back
  # and re-read, nor — worse — a fast run's newer cursor be undone.
  #
  # Acceptance criteria:
  # - A confirmation of the newer cursor committed while a confirmation of
  #   an older one is between its read of the consumer and its write leaves
  #   the newer position.
  # - The other order (older committed in between, newer confirming) ends
  #   at the newer position too.
  test "racing confirmations of one consumer end at the newer position" do
    {:ok, consumer} = News.digest_consumer("racer", nil, @now, @key)
    older = News.issue_digest_cursor(consumer, at(10), @key)
    newer = News.issue_digest_cursor(consumer, at(5), @key)

    {{:ok, _}, {:ok, _}} =
      Interleave.run(
        &consumer_query?/1,
        fn -> News.digest_consumer("racer", newer, @now, @key) end,
        fn -> News.digest_consumer("racer", older, @now, @key) end
      )

    assert DateTime.compare(position("racer"), at(5)) == :eq

    {:ok, other} = News.digest_consumer("racer-2", nil, @now, @key)
    older = News.issue_digest_cursor(other, at(10), @key)
    newer = News.issue_digest_cursor(other, at(5), @key)

    {{:ok, _}, {:ok, _}} =
      Interleave.run(
        &consumer_query?/1,
        fn -> News.digest_consumer("racer-2", older, @now, @key) end,
        fn -> News.digest_consumer("racer-2", newer, @now, @key) end
      )

    assert DateTime.compare(position("racer-2"), at(5)) == :eq
  end

  test "a consumer starts 24 hours back and is not moved by a read" do
    {:ok, consumer} = News.digest_consumer("reader", nil, @now, @key)
    assert DateTime.compare(consumer.position, at(24)) == :eq

    {:ok, again} = News.digest_consumer("reader", nil, DateTime.add(@now, 3600, :second), @key)
    assert DateTime.compare(again.position, at(24)) == :eq
  end

  test "two consumers never move each other" do
    {:ok, one} = News.digest_consumer("one", nil, @now, @key)
    {:ok, two} = News.digest_consumer("two", nil, @now, @key)

    {:ok, _} = News.digest_consumer("one", News.issue_digest_cursor(one, at(1), @key), @now, @key)

    assert DateTime.compare(position("one"), at(1)) == :eq
    assert DateTime.compare(position("two"), at(24)) == :eq

    assert {:error, :not_issued} =
             News.digest_consumer("two", News.issue_digest_cursor(one, at(1), @key), @now, @key)

    assert DateTime.compare(position("two"), at(24)) == :eq
    assert two.id != one.id
  end
end
