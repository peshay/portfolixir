defmodule Portfolixir.News.RetentionTest do
  # ADR-0056 §12, §14 item 9, B4, B7 (Sprint 27, N6): the retention run.
  # Items are stored through the ingest at a fixture clock in the past, so
  # their stories are the clustering's own. Synthetic items and hosts only.
  use Portfolixir.DataCase, async: true

  import Ecto.Query
  import Portfolixir.NewsFixtures

  alias Portfolixir.Clock
  alias Portfolixir.News.Cluster
  alias Portfolixir.News.FeedDay
  alias Portfolixir.News.Ingest
  alias Portfolixir.News.Item
  alias Portfolixir.News.Parser
  alias Portfolixir.News.Parser.Item, as: Parsed
  alias Portfolixir.News.Retention
  alias Portfolixir.Repo

  @now ~U[2026-11-07 10:00:00.000000Z]

  # 91 and 89 days before the run's clock.
  defp days_ago(days, hours \\ 0),
    do: @now |> DateTime.add(-days, :day) |> DateTime.add(hours, :hour)

  defp parsed(n, title, attrs \\ %{}) do
    struct!(
      Parsed,
      Map.merge(
        %{
          title: title,
          link: "https://newsroom.example.com/news/#{n}",
          guid: "g-#{n}",
          published_at: nil,
          excerpt: "Synthetic.",
          source_domain: nil
        },
        attrs
      )
    )
  end

  defp ingest!(feed, items, at) do
    {:ok, %{stored: stored}} = Ingest.ingest(feed, items, at)
    assert stored == length(items)
  end

  defp item(n), do: Repo.get_by(Item, canonical_url: "https://newsroom.example.com/news/#{n}")

  defp promote!(n, note_ids, status) do
    n |> item() |> Item.changeset(%{status: status, note_ids: note_ids}) |> Repo.update!()
  end

  defp stories(security_id) do
    Repo.all(
      from(c in Cluster,
        where: c.security_id == ^security_id,
        order_by: c.earliest_url,
        preload: [:items]
      )
    )
  end

  defp urls(story), do: story.items |> Enum.map(& &1.canonical_url) |> Enum.sort()

  setup do
    security = security!()
    %{security: security, feed: feed!(%{class: "issuer", security_id: security.id})}
  end

  # User story:
  # As the operator whose news layer must never become an archive,
  # I want items kept 90 days by the server's clock of their first sight,
  # unless I promoted them or a note links them,
  # so that what is stored stays a staging area and what became knowledge
  # keeps its source.
  #
  # Acceptance criteria (§12, §14 item 9, B4):
  # - An item first seen 91 days before the run and not promoted is gone
  #   after it; one first seen 89 days before stays.
  # - A promoted item, and an item naming a note, stay whatever their age.
  # - The window is the ingest's: a claim older than it is never stored
  #   (`dropped_old`), so retention and ingest agree on 90 days.
  # - The run reads `first_seen_at`, never the claim: an old claim first
  #   seen recently stays.
  describe "which items go (§12, B4)" do
    test "91 days old goes, 89 stays, promoted and linked items stay", ctx do
      ingest!(
        ctx.feed,
        [parsed(1, "Old release"), parsed(2, "Old promoted release")],
        days_ago(91)
      )

      ingest!(ctx.feed, [parsed(3, "Old linked release")], days_ago(91))
      ingest!(ctx.feed, [parsed(4, "Recent release")], days_ago(89))

      promote!(2, [7001], :promoted)
      promote!(3, [7002], :new)

      assert {:ok, %{items: 1}} = Retention.run(@now)

      assert item(1) == nil
      assert %Item{status: :promoted} = item(2)
      assert %Item{note_ids: [7002]} = item(3)
      assert %Item{} = item(4)
    end

    test "the window is the ingest's 90 days, read from first_seen_at", ctx do
      assert Retention.days() == Ingest.retention_days()
      assert Retention.days() == 90

      # Claimed 89 days ago, first seen now: the server's clock decides.
      ingest!(ctx.feed, [parsed(1, "Late find", %{published_at: days_ago(89)})], @now)

      later = DateTime.add(@now, 2, :day)
      assert {:ok, %{items: 0}} = Retention.run(later)
      assert %Item{} = item(1)
    end

    test "an unassigned aggregator item goes too" do
      feed = feed!(%{class: "aggregator", url: "https://search.example.com/rss?q=r"})

      ingest!(
        feed,
        [parsed(1, "Markets drift", %{source_domain: "wire.example.com"})],
        days_ago(91)
      )

      assert %Item{assignment: :unassigned} = item(1)
      assert {:ok, %{items: 1}} = Retention.run(@now)
      assert item(1) == nil
    end
  end

  # User story:
  # As the operator's agent reading stories,
  # I want a story to follow its items: gone when its last item goes,
  # recounted when it loses some, split when the item that held it together
  # goes, and never pointing at a deleted representative,
  # so that a story never stands for an item that is no longer there.
  #
  # Acceptance criteria (§12, B3):
  # - A story whose every member expired is deleted.
  # - A story that lost its representative keeps its id, its count and its
  #   earliest fields recomputed, and a remaining member as representative.
  # - A story held together by an expired item splits into its components;
  #   the remaining member earliest by the survivor key keeps the id.
  # - A promoted member keeps its story.
  describe "stories follow their items (§12, B3)" do
    test "an emptied story is deleted", ctx do
      ingest!(
        ctx.feed,
        [parsed(1, "Northwind ships a crane order"), parsed(2, "Northwind ships crane order")],
        days_ago(91)
      )

      assert [%{member_count: 2}] = stories(ctx.security.id)

      assert {:ok, %{items: 2, stories_deleted: 1}} = Retention.run(@now)
      assert stories(ctx.security.id) == []
    end

    test "a story that lost its representative keeps its id and is recounted", ctx do
      ingest!(ctx.feed, [parsed(1, "Northwind ships a crane order")], days_ago(90, -1))
      ingest!(ctx.feed, [parsed(2, "Northwind ships crane order")], days_ago(90, 1))

      assert [story] = stories(ctx.security.id)
      assert story.member_count == 2
      assert story.representative_item_id == item(1).id

      assert {:ok, %{items: 1, stories_deleted: 0}} = Retention.run(@now)

      assert [kept] = stories(ctx.security.id)
      assert kept.id == story.id
      assert kept.member_count == 1
      assert kept.representative_item_id == item(2).id
      assert kept.earliest_url == "https://newsroom.example.com/news/2"
      assert kept.earliest_first_seen_at == days_ago(90, 1)
      assert kept.earliest_published_at == days_ago(90, 1)
    end

    test "a story held together by an expired item splits", ctx do
      words = for n <- 1..12, do: "w#{n}"
      title = fn range -> Enum.map_join(range, " ", &Enum.at(words, &1 - 1)) end

      # B (1..11) links A (1..10) and C (2..12); A and C are not linked.
      ingest!(ctx.feed, [parsed(2, title.(1..11))], days_ago(90, -1))
      ingest!(ctx.feed, [parsed(1, title.(1..10)), parsed(3, title.(2..12))], days_ago(90, 1))

      assert [story] = stories(ctx.security.id)
      assert story.member_count == 3

      assert {:ok, %{items: 1}} = Retention.run(@now)

      assert [first, second] = stories(ctx.security.id)
      assert urls(first) == ["https://newsroom.example.com/news/1"]
      assert urls(second) == ["https://newsroom.example.com/news/3"]

      # The old story goes with its earliest remaining member (news/1, by
      # first sight and then URL); the other component is a new story.
      assert first.id == story.id
      assert second.id != story.id
      assert {first.member_count, second.member_count} == {1, 1}
    end

    test "a promoted member keeps its story", ctx do
      ingest!(
        ctx.feed,
        [parsed(1, "Northwind ships a crane order"), parsed(2, "Northwind ships crane order")],
        days_ago(91)
      )

      promote!(2, [7003], :promoted)
      [story] = stories(ctx.security.id)

      assert {:ok, %{items: 1, stories_deleted: 0}} = Retention.run(@now)

      assert [kept] = stories(ctx.security.id)
      assert kept.id == story.id
      assert kept.member_count == 1
      assert kept.representative_item_id == item(2).id
    end
  end

  # User story:
  # As the operator reading my feeds' health,
  # I want the day counters kept as long as the health read needs them and
  # no longer,
  # so that the table of counters does not grow without bound.
  #
  # Acceptance criteria:
  # - Day rows older than 30 days before the run's server day are deleted;
  #   the row 30 days back and younger stay.
  describe "day rows" do
    test "rows older than 30 days are pruned", ctx do
      for days <- [31, 30, 0], do: Ingest.add_to_day(ctx.feed.id, days_ago(days), errors: 1)

      assert {:ok, %{feed_days: 1}} = Retention.run(@now)

      today = Clock.local_date(@now)

      assert Repo.all(from(d in FeedDay, where: d.feed_id == ^ctx.feed.id, select: d.day))
             |> Enum.sort(Date) == [Date.add(today, -30), today]
    end
  end

  # User story:
  # As the operator whose news layer stores no article,
  # I want no stored excerpt longer than 600 characters, whatever a feed
  # sends, and the database to refuse a longer one from any writer,
  # so that nothing stored is an article (§14 item 9).
  #
  # Acceptance criteria:
  # - A feed's 2,000-character description is stored as an excerpt of at
  #   most 600 characters, through the parser and the ingest.
  # - The database refuses an excerpt of 601 characters written past the
  #   changeset.
  # --- closing act, Fix-1 ---------------------------------------------------

  # User story (closing act, COR2):
  # As the agent that reads what is new,
  # I want a dateless item that retention removed to stay removed while its
  # feed keeps listing it,
  # so that an old item never comes back as new (B4: no refill).
  #
  # Acceptance criteria:
  # - Retention leaves a tombstone of each removed item that had a feed: the
  #   feed and a SHA-256 of its canonical URL, never the URL.
  # - The feed listing the same dateless item again after removal drops it
  #   as `dropped_old`; a dateless item never stored is stored.
  # - A tombstone is kept 90 days after its item's removal, then pruned.
  describe "tombstones (closing act, COR2)" do
    test "a removed dateless item is not stored again while its tombstone lasts" do
      feed = feed!(%{class: "issuer", security_id: security!().id})
      ingest!(feed, [parsed(1, "Northwind lists an undated release")], days_ago(91))

      assert {:ok, %{items: 1}} = Retention.run(@now)
      assert item(1) == nil

      assert [%{feed_id: feed_id, url_hash: hash}] =
               Repo.all(
                 from(t in "news_item_tombstones",
                   select: %{feed_id: t.feed_id, url_hash: t.url_hash}
                 )
               )

      assert feed_id == feed.id

      assert hash ==
               :sha256
               |> :crypto.hash("https://newsroom.example.com/news/1")
               |> Base.encode16(case: :lower)

      later = DateTime.add(@now, 1, :hour)

      assert {:ok, %{stored: 1, dropped_old: 1}} =
               Ingest.ingest(
                 feed,
                 [
                   parsed(1, "Northwind lists an undated release"),
                   parsed(2, "Northwind lists another undated release")
                 ],
                 later
               )

      assert item(1) == nil
      assert item(2)

      # 90 days after the removal the tombstone goes (item 2's own removal
      # in the same run leaves its own).
      Retention.run(DateTime.add(@now, 91, :day))
      refute hash in Repo.all(from(t in "news_item_tombstones", select: t.url_hash))

      # A feed's removal takes its tombstones with it.
      assert Repo.aggregate(
               from(t in "news_item_tombstones", where: t.feed_id == ^feed.id),
               :count
             ) >
               0

      assert {:ok, _removed} = Portfolixir.News.delete_feed(Portfolixir.Actor.owner_ui(), feed.id)

      assert Repo.aggregate(
               from(t in "news_item_tombstones", where: t.feed_id == ^feed.id),
               :count
             ) == 0
    end
  end

  # --- end closing act, Fix-1 -----------------------------------------------

  describe "no archive (§14 item 9)" do
    test "a long description is stored capped at 600 characters", ctx do
      body = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0"><channel><title>Synthetic</title>
      <item><title>Northwind long read</title>
      <link>https://newsroom.example.com/news/1</link>
      <description>#{String.duplicate("é word ", 300)}</description></item>
      </channel></rss>
      """

      {:ok, %{items: items}} = Parser.parse(body)
      ingest!(ctx.feed, items, @now)

      assert String.length(item(1).excerpt) <= 600

      assert %{rows: [[longest]]} =
               Repo.query!("SELECT max(char_length(excerpt)) FROM news_items")

      assert longest <= 600
    end

    test "the database refuses an excerpt over 600 characters", ctx do
      ingest!(ctx.feed, [parsed(1, "Northwind short read")], @now)

      assert_raise Postgrex.Error, ~r/news_items_excerpt_check/, fn ->
        Repo.query!("UPDATE news_items SET excerpt = $1 WHERE id = $2", [
          String.duplicate("é", 601),
          item(1).id
        ])
      end
    end
  end
end
