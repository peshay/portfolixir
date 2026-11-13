defmodule Portfolixir.News.IngestTest do
  # ADR-0056 §2, §4, A3, B4, B7 (Sprint 27, N3): what the fetcher stores of
  # a parsed answer. Synthetic items and hosts only.
  use Portfolixir.DataCase, async: true

  import Ecto.Query
  import Portfolixir.NewsFixtures

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Clock
  alias Portfolixir.News.Cluster
  alias Portfolixir.News.FeedDay
  alias Portfolixir.News.Ingest
  alias Portfolixir.News.Item
  alias Portfolixir.News.Parser.Item, as: Parsed
  alias Portfolixir.News.Sources
  alias Portfolixir.News.Stories
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
               Ingest.ingest(
                 feed,
                 [parsed(1, %{title: "Record Q3 for Northwind: record!"}), future],
                 @now
               )

      assert [first, second] = items(feed)

      assert first.assignment == :assigned
      assert first.security_id == security.id
      assert first.tier == :primary
      assert first.class == :issuer
      assert first.domain == "newsroom.example.com"
      assert first.language == "en"
      assert first.first_seen_at == @now
      assert first.published_at == ~U[2026-11-07 09:00:00.000000Z]
      assert first.title == "Record Q3 for Northwind: record!"
      assert first.excerpt == "Revenue rose."

      # The clustering's own keys (`Stories.title_keys/1`), one source: the
      # distinct words sorted, the hash over the whole normalized title.
      assert first.title_words == ~w(for northwind q3 record)

      assert first.title_norm_hash ==
               :sha256
               |> :crypto.hash("record q3 for northwind record")
               |> Base.encode16(case: :lower)

      assert Map.take(first, [:title_words, :title_norm_hash]) ==
               Stories.title_keys(first.title)

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

  defp watched!(name, token) do
    {:ok, security} =
      Catalog.update_security(Actor.owner_ui(), security!(name), %{
        news_watch: true,
        news_aliases: [%{token: token, context: [], case: "insensitive"}]
      })

    security
  end

  # User story:
  # As the operator's agent reading what my feeds collected,
  # I want every item a fetch stores to land where it belongs before I read
  # it: an issuer's or a regulator's on its security whatever its title
  # names, an aggregator's on the one security of my universe it names, or
  # in the queue as unassigned or ambiguous,
  # so that identity holds end to end and nothing waits for a second pass.
  #
  # Acceptance criteria (§14 item 1, through `Ingest.ingest/3`):
  # - Aggregator items with one, none and several alias hits are stored
  #   `assigned` (to that security), `unassigned`, and `ambiguous` with the
  #   sorted candidates.
  # - Issuer and regulatory items land on their feed's security even when
  #   their title names another security of the universe.
  # --- closing act, Fix-1 ---------------------------------------------------

  # User story (closing act, COR4):
  # As the operator reading a feed's health,
  # I want an item a feed keeps listing and the ingest keeps dropping
  # counted once a day, not once a fetch,
  # so that one old filing reads as one drop, not 144.
  #
  # Acceptance criteria:
  # - The same dropped item (old, no source, blocked or over the cap) is
  #   counted once per feed, canonical URL, reason and server day, however
  #   often it is fetched; the next server day counts it once again.
  # - A fetch's own summary still reports what it dropped.
  describe "drop counters (closing act, COR4)" do
    test "a dropped item counts once per server day" do
      feed = feed!(%{class: "issuer", security_id: security!().id})
      old = parsed(1, %{published_at: DateTime.add(@now, -91, :day)})

      for minutes <- [0, 10, 20] do
        assert {:ok, %{dropped_old: 1}} =
                 Ingest.ingest(feed, [old], DateTime.add(@now, minutes, :minute))
      end

      assert %{dropped_old: 1} = day(feed)

      tomorrow = DateTime.add(@now, 1, :day)
      assert {:ok, %{dropped_old: 1}} = Ingest.ingest(feed, [old], tomorrow)
      assert {:ok, %{dropped_old: 1}} = Ingest.ingest(feed, [old], tomorrow)
      assert total(feed, :dropped_old) == 2
    end

    test "a capped and a sourceless item count once a day too" do
      feed = feed!(%{class: "issuer", security_id: security!().id})
      flood = Enum.map(1..202, &parsed/1)

      assert {:ok, %{dropped_cap: 2}} = Ingest.ingest(feed, flood, @now)

      assert {:ok, %{dropped_cap: 2}} =
               Ingest.ingest(feed, flood, DateTime.add(@now, 5, :minute))

      assert %{dropped_cap: 2} = day(feed)

      aggregator = feed!(%{class: "aggregator"})
      sourceless = parsed(9, %{link: "https://wire.example.com/n/9"})

      for minutes <- [0, 30] do
        assert {:ok, %{dropped_no_source: 1}} =
                 Ingest.ingest(aggregator, [sourceless], DateTime.add(@now, minutes, :minute))
      end

      assert %{dropped_no_source: 1} = day(aggregator)
    end
  end

  # User story (closing act, EDGE5):
  # As the agent reading the news,
  # I want an item whose title is only invisible characters skipped like
  # one without a title,
  # so that no story reads as blank.
  #
  # Acceptance criteria:
  # - A title of only format characters (`\\p{Cf}`: zero-width space, soft
  #   hyphen, a direction override) and whitespace is `incomplete`, not
  #   stored; a title with visible text and an invisible character is
  #   stored, the character kept as received (plan D-6).
  describe "invisible titles (closing act, EDGE5)" do
    test "a title of only invisible characters is incomplete" do
      feed = feed!(%{class: "issuer", security_id: security!().id})

      blank =
        for {title, n} <- Enum.with_index(["\u200B\u200B", "\u00AD", "\u202E", "\u200B \uFEFF"]) do
          parsed(n, %{title: title})
        end

      shown = parsed(10, %{title: "Northwind\u200B ships"})

      assert {:ok, %{stored: 1, incomplete: 4}} = Ingest.ingest(feed, blank ++ [shown], @now)
      assert [%{title: "Northwind\u200B ships"}] = items(feed)
    end
  end

  # --- end closing act, Fix-1 -----------------------------------------------

  describe "matching at ingest (§2, §14 item 1)" do
    test "an aggregator item with one, none and several hits" do
      northwind = watched!("Northwind Harbour Logistics AG", "Northwind Harbour")
      larkspur = watched!("Larkspur Robotics Inc", "Larkspur")
      feed = feed!(%{class: "aggregator", url: "https://search.example.com/rss?q=n"})

      items =
        for {n, title} <- [
              {1, "Northwind Harbour wins a port contract"},
              {2, "Markets drift ahead of the holiday"},
              {3, "Larkspur and Northwind Harbour agree a joint venture"}
            ] do
          parsed(n, %{
            title: title,
            link: "https://search.example.com/r?u=#{n}",
            source_domain: "wire.example.com"
          })
        end

      assert {:ok, %{stored: 3}} = Ingest.ingest(feed, items, @now)

      assert [one, none, several] = items(feed)
      assert {one.assignment, one.security_id, one.candidates} == {:assigned, northwind.id, []}
      assert {none.assignment, none.security_id, none.candidates} == {:unassigned, nil, []}

      assert {several.assignment, several.security_id, several.candidates} ==
               {:ambiguous, nil, Enum.sort([northwind.id, larkspur.id])}
    end

    test "issuer and regulatory items land on their security whatever their title names" do
      northwind = watched!("Northwind Harbour Logistics AG", "Northwind Harbour")
      _larkspur = watched!("Larkspur Robotics Inc", "Larkspur")
      issuer = feed!(%{class: "issuer", security_id: northwind.id})
      regulatory = feed!(%{class: "regulatory", security_id: northwind.id})

      title = "Northwind Harbour comments on Larkspur's offer"
      {:ok, %{stored: 1}} = Ingest.ingest(issuer, [parsed(1, %{title: title})], @now)
      {:ok, %{stored: 1}} = Ingest.ingest(regulatory, [parsed(2, %{title: title})], @now)

      for item <- items(issuer) ++ items(regulatory) do
        assert {item.assignment, item.security_id, item.candidates, item.tier} ==
                 {:assigned, northwind.id, [], :primary}
      end
    end
  end

  defp agg(n, title, domain) do
    parsed(n, %{
      title: title,
      link: "https://search.example.com/r?u=#{n}",
      source_domain: domain
    })
  end

  defp rate!(domain, tier), do: {:ok, _} = Sources.put_source(Actor.owner_ui(), domain, tier)

  defp stories(security_id, language) do
    Repo.all(
      from(c in Cluster,
        where: c.security_id == ^security_id and c.language == ^language,
        order_by: [desc: c.member_count, asc: c.earliest_url],
        preload: [:items]
      )
    )
  end

  # User story:
  # As the operator whose agent weighs a story by where it came from,
  # I want each stored item rated by the tier table, a blocked domain's
  # items never stored but counted, and an aggregator never able to claim a
  # primary source,
  # so that a hand-kept rating decides what a story stands for and a block
  # is visible in the feed's health.
  #
  # Acceptance criteria (§3, B5):
  # - A domain rated `blocked`, or a subdomain of one, is dropped at ingest
  #   and counted `dropped_blocked` in the summary and the day row.
  # - An aggregator item naming a domain rated `primary` is `secondary`; a
  #   `secondary` domain gives `secondary`; an unrated one `awareness`.
  # - An issuer item is `primary` whatever its domain's row says, unless
  #   the domain is blocked.
  describe "tiers and blocks (§3, B5)" do
    # #1424: the domains this test rates are its own. A rating is a row
    # under a unique domain, held uncommitted until a test's sandbox rolls
    # back, so an async test rating the same domain waited for this one to
    # end (and this one for it), and failed under load.
    # Closing act (flaky): its own also against every fetch. A rating holds
    # its domain's tier lock exclusive until the test ends (N1, E1), and a
    # fetch storing an item of that domain waits for it on its test's one
    # connection; `newsroom.example.com`, rated here once, is the fixtures'
    # host, so the scheduler test's fetch stalled on it, and a second fetch
    # task of that test was dropped from the connection's queue.
    test "a blocked domain's items are dropped and counted, the rest rated" do
      rate!("spam.ingest.example.net", :blocked)
      rate!("newsroom.ingest.example.com", :primary)
      rate!("wire.ingest.example.com", :secondary)
      feed = feed!(%{class: "aggregator", url: "https://search.example.com/rss?q=t"})

      batch = [
        agg(1, "Item from a blocked domain", "spam.ingest.example.net"),
        agg(2, "Item from a blocked subdomain", "eu.spam.ingest.example.net"),
        agg(3, "Item naming a primary domain", "newsroom.ingest.example.com"),
        agg(4, "Item from a secondary domain", "wire.ingest.example.com"),
        agg(5, "Item from an unrated domain", "blog.example.org")
      ]

      assert {:ok, %{stored: 3, dropped_blocked: 2}} = Ingest.ingest(feed, batch, @now)

      assert Enum.map(items(feed), &{&1.domain, &1.tier}) == [
               {"newsroom.ingest.example.com", :secondary},
               {"wire.ingest.example.com", :secondary},
               {"blog.example.org", :awareness}
             ]

      assert %{dropped_blocked: 2, items_stored: 3} = day(feed)
    end

    test "an issuer item is primary on any unblocked domain, and dropped on a blocked one" do
      rate!("newsroom.ingest.example.com", :awareness)
      rate!("mirror.example.net", :blocked)
      feed = feed!(%{class: "issuer", security_id: security!().id})

      batch = [
        parsed(1, %{link: "https://newsroom.ingest.example.com/news/1"}),
        parsed(2, %{link: "https://mirror.example.net/news/2"})
      ]

      assert {:ok, %{stored: 1, dropped_blocked: 1}} = Ingest.ingest(feed, batch, @now)
      assert [%{tier: :primary, domain: "newsroom.ingest.example.com"}] = items(feed)
    end
  end

  # User story:
  # As the operator's agent reading one row per event,
  # I want the same release, fetched from the issuer and from several
  # publishers with reworded titles, folded into one story per language as
  # it is stored, and an item the matcher files later folded in as well,
  # so that eleven items about one event read as one story.
  #
  # Acceptance criteria (§4, B3, §14 item 3, through `Ingest.ingest/3`):
  # - Constructed duplicates (the issuer's release and the same release
  #   from two domains, reworded) are one story in English, represented by
  #   the issuer's primary item; the German release is a story of its own;
  #   an unrelated item is its own story.
  # - An item the re-match of an identity change assigns is folded into the
  #   security's stories at once; an assigned item is never unassigned by it.
  describe "stories at ingest (§4, B3, §14 item 3)" do
    test "the same release from several domains is one story per language" do
      northwind = watched!("Northwind Harbour Logistics AG", "Northwind Harbour")
      search = feed!(%{class: "aggregator", url: "https://search.example.com/rss?q=s"})
      issuer = feed!(%{class: "issuer", security_id: northwind.id})
      german = feed!(%{class: "issuer", security_id: northwind.id, language: "de"})

      release = "Northwind Harbour Logistics reports record third quarter revenue"

      {:ok, %{stored: 3}} =
        Ingest.ingest(
          search,
          [
            agg(
              1,
              "Northwind Harbour Logistics reports record third-quarter revenue",
              "wire.example.com"
            ),
            agg(2, release <> " growth", "markets.example.org"),
            agg(3, "Northwind Harbour opens a terminal in the north", "wire.example.com")
          ],
          @now
        )

      later = DateTime.add(@now, 30, :minute)
      {:ok, %{stored: 1}} = Ingest.ingest(issuer, [parsed(10, %{title: release})], later)

      {:ok, %{stored: 1}} =
        Ingest.ingest(
          german,
          [
            parsed(11, %{
              title: "Northwind Harbour Logistics meldet Rekordumsatz im dritten Quartal"
            })
          ],
          later
        )

      assert [release_story, terminal] = stories(northwind.id, "en")

      assert release_story.member_count == 3
      assert release_story.best_tier == :primary
      assert Repo.get!(Item, release_story.representative_item_id).feed_id == issuer.id

      assert release_story.items |> Enum.map(& &1.domain) |> Enum.sort() ==
               ~w(markets.example.org newsroom.example.com wire.example.com)

      assert terminal.member_count == 1

      assert [%{member_count: 1, best_tier: :primary}] = stories(northwind.id, "de")

      assert Repo.aggregate(from(i in Item, where: is_nil(i.cluster_id)), :count) == 0
    end

    test "an item the re-match assigns joins its story; an assigned one stays" do
      northwind = watched!("Northwind Harbour Logistics AG", "Northwind Harbour")
      search = feed!(%{class: "aggregator", url: "https://search.example.com/rss?q=r"})
      now = DateTime.utc_now()

      {:ok, %{stored: 3}} =
        Ingest.ingest(
          search,
          [
            agg(1, "Northwind Harbour and Quillfeather sign a supply deal", "wire.example.com"),
            agg(
              2,
              "Quillfeather and Northwind Harbour sign a supply deal",
              "markets.example.org"
            ),
            agg(
              3,
              "Quillfeather and Northwind Harbour sign a supply deal today",
              "blog.example.org"
            )
          ],
          now
        )

      # Nothing matched Quillfeather yet: each is Northwind's, one story.
      assert [%{member_count: 3}] = stories(northwind.id, "en")

      quillfeather = watched!("Quillfeather Paper SE", "Quillfeather")

      # The re-match reads only unassigned and ambiguous items: the three
      # assigned ones stay on Northwind, in their story.
      assert [%{member_count: 3}] = stories(northwind.id, "en")

      {:ok, %{stored: 2}} =
        Ingest.ingest(
          search,
          [
            agg(4, "Quillfeather opens a paper mill", "wire.example.com"),
            agg(5, "Quillfeather opens a new paper mill", "markets.example.org")
          ],
          now
        )

      assert [%{member_count: 2}] = stories(quillfeather.id, "en")

      # An unassigned item the identity change assigns joins a story at once.
      {:ok, %{stored: 1}} =
        Ingest.ingest(search, [agg(6, "Larkspur opens a paper mill", "wire.example.com")], now)

      assert [%{assignment: :unassigned}] =
               Repo.all(
                 from(i in Item, where: i.canonical_url == "https://search.example.com/r?u=6")
               )

      larkspur = watched!("Larkspur Robotics Inc", "Larkspur")

      assert [story] = stories(larkspur.id, "en")
      assert story.member_count == 1
      assert [%{canonical_url: "https://search.example.com/r?u=6"}] = story.items
    end
  end
end
