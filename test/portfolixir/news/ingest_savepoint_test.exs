defmodule Portfolixir.News.IngestSavepointTest do
  # Closing act, SEC2/EDGE1 (ADR-0056 §2, A1): one item the database refuses
  # never costs the batch. Not async: one test adds a CHECK to news_items
  # inside its sandbox transaction (rolled back with it), which locks the
  # table for every other test meanwhile.
  use Portfolixir.DataCase, async: false

  @moduletag :capture_log

  import Ecto.Query
  import Portfolixir.NewsFixtures

  alias Portfolixir.News.Feed
  alias Portfolixir.News.Fetcher
  alias Portfolixir.News.Ingest
  alias Portfolixir.News.Item
  alias Portfolixir.News.Parser.Item, as: Parsed
  alias Portfolixir.Repo

  @now ~U[2026-11-07 10:00:00.000000Z]

  defp parsed(n, link),
    do: %Parsed{title: "Northwind reports item #{n}", link: link, excerpt: "Revenue rose."}

  defp links(feed),
    do:
      Repo.all(
        from(i in Item, where: i.feed_id == ^feed.id, order_by: i.id, select: i.canonical_url)
      )

  # User story (closing act, SEC2/EDGE1):
  # As the operator whose feed may carry one malformed item,
  # I want that item refused alone, and the rest of the answer stored,
  # so that one hostile link cannot stop a feed from storing anything.
  #
  # Acceptance criteria:
  # - A link with a Unicode space (U+3000, U+2028, U+2000 to U+200A,
  #   U+1680) is refused by the item's own check, counted `invalid`, and the
  #   other items are stored; the feed's fetch is recorded as a success.
  # - An item the database refuses where the changeset did not is counted
  #   `invalid` in its own savepoint; the batch's other items are stored.
  describe "one refused item (closing act, SEC2/EDGE1)" do
    test "a link with a Unicode space is invalid and the rest is stored" do
      feed = feed!(%{class: "issuer", security_id: security!().id})

      items =
        for {space, n} <- Enum.with_index(["\u3000", "\u2028", "\u2000", "\u200A", "\u1680"]) do
          parsed(n, "https://newsroom.example.com/bad/#{n}" <> space <> "x")
        end

      good = [
        parsed(10, "https://newsroom.example.com/n/1"),
        parsed(11, "https://newsroom.example.com/n/3")
      ]

      assert {:ok, %{stored: 2, invalid: 5}} = Ingest.ingest(feed, good ++ items, @now)

      assert links(feed) == [
               "https://newsroom.example.com/n/1",
               "https://newsroom.example.com/n/3"
             ]
    end

    test "a fetch with such a link stores the rest and records a success" do
      feed = feed!(%{class: "issuer", security_id: security!().id})

      serve(fn conn ->
        Plug.Conn.send_resp(
          conn,
          200,
          rss([
            %{title: "Good one", link: "https://newsroom.example.com/n/1"},
            %{title: "Hostile", link: "https://newsroom.example.com/n/2\u3000x"},
            %{title: "Good two", link: "https://newsroom.example.com/n/3"}
          ])
        )
      end)

      assert {:ok, %{stored: 2}} = Fetcher.fetch(feed, now: @now)
      assert %{last_error: nil, last_ok_at: @now} = Repo.get!(Feed, feed.id)
      assert length(links(feed)) == 2
    end

    test "an item the database refuses is invalid alone" do
      feed = feed!(%{class: "issuer", security_id: security!().id})

      Repo.query!(
        "ALTER TABLE news_items ADD CONSTRAINT synthetic_refusal " <>
          "CHECK (title <> 'Refused by the database')"
      )

      refused = %{
        parsed(2, "https://newsroom.example.com/n/2")
        | title: "Refused by the database"
      }

      assert {:ok, %{stored: 2, invalid: 1}} =
               Ingest.ingest(
                 feed,
                 [
                   parsed(1, "https://newsroom.example.com/n/1"),
                   refused,
                   parsed(3, "https://newsroom.example.com/n/3")
                 ],
                 @now
               )

      assert links(feed) == [
               "https://newsroom.example.com/n/1",
               "https://newsroom.example.com/n/3"
             ]
    end
  end
end
