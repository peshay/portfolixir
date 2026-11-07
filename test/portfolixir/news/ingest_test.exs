defmodule Portfolixir.News.IngestTest do
  # ADR-0056 §2, §4, A3, B4, B7 (Sprint 27, N3): what the fetcher stores of
  # a parsed answer. Synthetic items and hosts only.
  use Portfolixir.DataCase, async: true

  import Ecto.Query
  import Portfolixir.NewsFixtures

  alias Portfolixir.Clock
  alias Portfolixir.News.FeedDay
  alias Portfolixir.News.Ingest
  alias Portfolixir.News.Item
  alias Portfolixir.News.Parser.Item, as: Parsed
  alias Portfolixir.Repo

  @now ~U[2026-11-07 10:00:00.000000Z]

  defp parsed(n, attrs \\ %{}) do
    struct!(
      Parsed,
      Map.merge(
        %{
          title: "Northwind reports item #{n}",
          link: "https://newsroom.example.com/news/#{n}",
          guid: "g-#{n}",
          published_at: ~U[2026-11-07 09:00:00Z],
          excerpt: "Revenue rose.",
          source_domain: nil
        },
        attrs
      )
    )
  end

  defp items(feed), do: Repo.all(from(i in Item, where: i.feed_id == ^feed.id, order_by: i.id))

  defp total(feed, counter),
    do:
      Repo.one(from(d in FeedDay, where: d.feed_id == ^feed.id, select: sum(field(d, ^counter))))

  defp day(feed), do: Repo.get_by!(FeedDay, feed_id: feed.id, day: Clock.local_date(@now))

  # User story:
  # As the operator whose agent reads what my registered feeds say,
  # I want each item stored once, on the security or category its feed is
  # bound to, with the server's clock deciding what is new and a claimed date
  # that cannot run ahead of it,
  # so that a feed's own claims never reorder or refill what I read.
  #
  # Acceptance criteria:
  # - An issuer or regulatory item is `assigned` to its feed's security,
  #   `primary`, its domain the link's host; a thematic one to its category.
  # - `first_seen_at` is the fetch's clock; a future claim is clamped to it.
  # - The title's normalized words and hashes are stored.
  describe "items by construction" do
    test "an issuer item lands on its security, primary, with the server's clock" do
      security = security!()
      feed = feed!(%{class: "issuer", security_id: security.id})

      future = parsed(2, %{published_at: ~U[2026-11-09 00:00:00Z]})

      assert {:ok, %{stored: 2}} =
               Ingest.ingest(feed, [parsed(1, %{title: "Northwind: Q3, record!"}), future], @now)

      assert [first, second] = items(feed)

      assert first.assignment == :assigned
      assert first.security_id == security.id
      assert first.tier == :primary
      assert first.class == :issuer
      assert first.domain == "newsroom.example.com"
      assert first.language == "en"
      assert first.first_seen_at == @now
      assert first.published_at == ~U[2026-11-07 09:00:00.000000Z]
      assert first.title == "Northwind: Q3, record!"
      assert first.excerpt == "Revenue rose."
      assert first.title_words == ~w(northwind q3 record)

      assert first.title_norm_hash ==
               :sha256 |> :crypto.hash("northwind q3 record") |> Base.encode16(case: :lower)

      assert first.content_hash =~ ~r/\A[0-9a-f]{64}\z/

      # B4: a claim later than the first sight is clamped to it.
      assert second.published_at_claimed == ~U[2026-11-09 00:00:00.000000Z]
      assert second.published_at == @now
    end

    test "a regulatory item is primary on its security, a thematic one on its category" do
      security = security!()
      category = category!()
      regulatory = feed!(%{class: "regulatory", security_id: security.id})
      thematic = feed!(%{class: "thematic", category_id: category.id})

      {:ok, _} = Ingest.ingest(regulatory, [parsed(1)], @now)
      {:ok, _} = Ingest.ingest(thematic, [parsed(2)], @now)

      assert [%{tier: :primary, security_id: id, assignment: :assigned}] = items(regulatory)
      assert id == security.id

      assert [%{tier: :awareness, category_id: cid, security_id: nil, assignment: :assigned}] =
               items(thematic)

      assert cid == category.id
    end

    test "the canonical URL drops the fragment, default port, tracking parameters and case" do
      feed = feed!(%{class: "issuer", security_id: security!().id})

      link = "HTTPS://NewsRoom.Example.com:443/News/1?utm_source=x&id=7&fbclid=y#top"
      {:ok, _} = Ingest.ingest(feed, [parsed(1, %{link: link})], @now)

      assert [%{canonical_url: "https://newsroom.example.com/News/1?id=7"}] = items(feed)
    end

    test "an item without a title or a link is not stored" do
      feed = feed!(%{class: "issuer", security_id: security!().id})

      assert {:ok, %{stored: 0, incomplete: 2}} =
               Ingest.ingest(feed, [parsed(1, %{title: nil}), parsed(2, %{link: nil})], @now)

      assert items(feed) == []
    end
  end

  # User story:
  # As the operator,
  # I want an aggregator's item to name the publisher it came from, or not to
  # be stored, and to wait for the matcher unassigned,
  # so that dedupe and tiers are never blind and no redirect is followed.
  #
  # Acceptance criteria:
  # - The domain is the item's `<source>` domain; without one the item is
  #   dropped and counted `dropped_no_source`.
  # - The item is `unassigned`, with no candidates, and never `primary`.
  describe "aggregator items (§2)" do
    test "take the source's domain, or are dropped and counted" do
      feed = feed!(%{class: "aggregator", url: "https://search.example.com/rss?q=x"})

      items = [
        parsed(1, %{link: "https://search.example.com/r?u=1", source_domain: "wire.example.com"}),
        parsed(2, %{link: "https://search.example.com/r?u=2", source_domain: nil})
      ]

      assert {:ok, %{stored: 1, dropped_no_source: 1}} = Ingest.ingest(feed, items, @now)

      assert [item] = items(feed)
      assert item.domain == "wire.example.com"
      assert item.assignment == :unassigned
      assert item.candidates == []
      assert item.security_id == nil
      assert item.tier == :awareness

      assert %{dropped_no_source: 1, items_stored: 1} = day(feed)
    end
  end

  # User story:
  # As the operator,
  # I want a feed that keeps listing old items not to refill what retention
  # removed, a re-fetch to store nothing twice, and a flooding feed capped,
  # so that the staging area stays bounded whatever a feed sends.
  #
  # Acceptance criteria:
  # - A claim older than 90 days is not stored and counts `dropped_old` (B4).
  # - A re-fetch of the same items stores nothing and counts nothing again.
  # - At most 200 items in 24 hours per feed: the first 200 in the feed's
  #   own order; the rest count `dropped_cap` (A3).
  describe "bounds" do
    test "a claim older than the retention window is dropped and counted" do
      feed = feed!(%{class: "issuer", security_id: security!().id})

      old = parsed(1, %{published_at: DateTime.add(@now, -91, :day)})
      edge = parsed(2, %{published_at: DateTime.add(@now, -89, :day)})

      assert {:ok, %{stored: 1, dropped_old: 1}} = Ingest.ingest(feed, [old, edge], @now)
      assert [%{canonical_url: "https://newsroom.example.com/news/2"}] = items(feed)
      assert %{dropped_old: 1, items_stored: 1} = day(feed)
    end

    test "a re-fetch stores nothing again and counts nothing again" do
      feed = feed!(%{class: "issuer", security_id: security!().id})
      batch = [parsed(1), parsed(2), parsed(1)]

      assert {:ok, %{stored: 2, known: 0}} = Ingest.ingest(feed, batch, @now)

      later = DateTime.add(@now, 10, :minute)
      assert {:ok, %{stored: 0, known: 2}} = Ingest.ingest(feed, batch, later)

      assert length(items(feed)) == 2
      assert %{items_stored: 2, dropped_cap: 0} = day(feed)
    end

    test "a feed past 200 items in 24 hours keeps its first 200 in its own order" do
      feed = feed!(%{class: "issuer", security_id: security!().id})
      flood = Enum.map(1..205, &parsed/1)

      assert {:ok, %{stored: 200, dropped_cap: 5}} = Ingest.ingest(feed, flood, @now)

      stored = items(feed) |> Enum.map(& &1.canonical_url) |> MapSet.new()
      assert MapSet.member?(stored, "https://newsroom.example.com/news/200")
      refute MapSet.member?(stored, "https://newsroom.example.com/news/201")

      # Still inside the 24 hours: the same five and one more are capped.
      in_window = DateTime.add(@now, 23, :hour)

      assert {:ok, %{stored: 0, known: 200, dropped_cap: 6}} =
               Ingest.ingest(feed, flood ++ [parsed(206)], in_window)

      assert total(feed, :dropped_cap) == 11
      assert total(feed, :items_stored) == 200

      # Past it, the window has room again.
      next_day = DateTime.add(@now, 25, :hour)
      assert {:ok, %{stored: 6}} = Ingest.ingest(feed, flood ++ [parsed(206)], next_day)
    end
  end
end
