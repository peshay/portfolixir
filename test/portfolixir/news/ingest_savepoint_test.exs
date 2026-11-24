defmodule Portfolixir.News.IngestSavepointTest do
  # Closing act, SEC2/EDGE1 (ADR-0056 §2, A1): one item the database refuses
  # never costs the batch. Not async: one test adds a CHECK to news_items
  # inside its sandbox transaction (rolled back with it), which locks the
  # table for every other test meanwhile.
  use Portfolixir.DataCase, async: false

  @moduletag :capture_log

  import Ecto.Query
  import Portfolixir.NewsFixtures

  alias Portfolixir.News.Cluster
  alias Portfolixir.News.Feed
  alias Portfolixir.News.Fetcher
  alias Portfolixir.News.Ingest
  alias Portfolixir.News.Item
  alias Portfolixir.News.Parser
  alias Portfolixir.News.Parser.Item, as: Parsed
  alias Portfolixir.News.Stories
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

  # User story (N-74; ADR-0056 A1, amendment of 2026-11-24, F6):
  # As the operator who reads an item's domain beside its link,
  # I want an item whose link holds a backslash refused wherever it comes
  # from,
  # so that no item is stored under a host that is not the one its link
  # opens.
  #
  # Acceptance criteria:
  # - The parser hands over no link and no source holding a backslash
  #   (closed on main by the closing act of Sprint 29; pinned here beside
  #   the item's check).
  # - An item given such a link past the parser is refused by the item's
  #   own check and counted `invalid`; the rest of the answer is stored.
  # - A link an item already has is not checked again: a row stored before
  #   the rule can still be updated, and its story can still be written.
  describe "a link with a backslash (N-74)" do
    @differing "https://first.example.org\\@second.example.org/x"

    test "the parser hands over no such link and no such source" do
      body =
        rss([
          %{title: "Good one", link: "https://newsroom.example.com/n/1"},
          %{title: "Differing", link: @differing, source: @differing}
        ])

      assert {:ok, %{items: [good, differing]}} = Parser.parse(body)
      assert good.link == "https://newsroom.example.com/n/1"
      assert differing.link == nil
      assert differing.source_domain == nil
    end

    test "the item's own check refuses it, and the rest is stored" do
      feed = feed!(%{class: "issuer", security_id: security!().id})

      batch = [
        parsed(1, "https://newsroom.example.com/n/1"),
        parsed(2, @differing),
        parsed(3, "https://newsroom.example.com/a\\b")
      ]

      assert {:ok, %{stored: 1, invalid: 2}} = Ingest.ingest(feed, batch, @now)
      assert links(feed) == ["https://newsroom.example.com/n/1"]

      changeset =
        Item.changeset(%Item{}, %{
          class: :issuer,
          security_id: feed.security_id,
          feed_id: feed.id,
          assignment: :assigned,
          first_seen_at: @now,
          title: "Differing",
          canonical_url: @differing,
          domain: "second.example.org",
          tier: :primary,
          language: "en",
          content_hash: String.duplicate("0", 64),
          title_norm_hash: String.duplicate("0", 64)
        })

      assert %{canonical_url: ["must not contain a backslash"]} = errors_on(changeset)
    end

    test "a link an item already has is left as it is" do
      feed = feed!(%{class: "issuer", security_id: security!().id})

      assert {:ok, %{stored: 1}} =
               Ingest.ingest(feed, [parsed(1, "https://newsroom.example.com/n/1")], @now)

      # A row as one stored before the rule: the table's check allows it.
      Repo.update_all(from(i in Item, where: i.feed_id == ^feed.id),
        set: [canonical_url: @differing]
      )

      [stored] = Repo.all(from(i in Item, where: i.feed_id == ^feed.id))
      assert stored.canonical_url == @differing

      assert {:ok, muted} = stored |> Item.changeset(%{status: :muted}) |> Repo.update()
      assert muted.status == :muted

      # Its story is written again with the link it has.
      scope = {:security, feed.security_id}
      assert {:ok, _summary} = Stories.recluster(scope, "en", @now, full: true)
      story = Repo.get!(Cluster, Repo.get!(Item, stored.id).cluster_id)
      assert story.earliest_url == @differing
    end
  end
end
