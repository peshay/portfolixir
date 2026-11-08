defmodule Portfolixir.News.HealthTest do
  # ADR-0056 §6, §14 item 5, A3 (Sprint 27, N6): the health read, at a
  # fixture clock. Items are stored through the ingest at that clock; a
  # feed's fetch record is written as the fetcher writes it. Synthetic
  # items and hosts only.
  use Portfolixir.DataCase, async: true

  import Ecto.Query
  import Portfolixir.NewsFixtures

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Clock
  alias Portfolixir.News
  alias Portfolixir.News.Feed
  alias Portfolixir.News.Ingest
  alias Portfolixir.News.Item
  alias Portfolixir.News.Parser.Item, as: Parsed
  alias Portfolixir.Repo

  @now ~U[2026-11-07 10:00:00.000000Z]

  defp parsed(n, attrs \\ %{}) do
    struct!(
      Parsed,
      Map.merge(
        %{title: "Synthetic item #{n}", link: "https://newsroom.example.com/h/#{n}"},
        attrs
      )
    )
  end

  defp ingest!(feed, items, at) do
    {:ok, %{stored: stored}} = Ingest.ingest(feed, items, at)
    assert stored == length(items)
  end

  defp fetched_ok!(feed, at) do
    feed
    |> Feed.health_changeset(%{last_fetch_at: at, last_ok_at: at})
    |> Repo.update!()
  end

  defp created_at!(feed, at) do
    Repo.update_all(from(f in Feed, where: f.id == ^feed.id), set: [inserted_at: at])
    feed
  end

  defp promote!(url, note_id) do
    Item
    |> Repo.get_by!(canonical_url: url)
    |> Item.changeset(%{status: :promoted, note_ids: [note_id]})
    |> Repo.update!()
  end

  defp health(feed, now), do: now |> News.health() |> Map.fetch!(:feeds) |> by_id(feed)

  defp by_id(feeds, feed), do: Enum.find(feeds, &(&1.id == feed.id))

  defp issuer_feed!, do: feed!(%{class: "issuer", security_id: security!().id})

  # User story:
  # As the operator who must not mistake a dead feed for a quiet one,
  # I want a feed that has had no successful fetch for 24 hours to read
  # stale, and a new feed not to read stale before it had its chance,
  # so that a dead collector is visibly dead within a day (§6, §14 item 5).
  #
  # Acceptance criteria:
  # - `stale` is false 1 µs before 24 hours after `last_ok_at` and true at
  #   exactly 24 hours.
  # - A feed never fetched is stale once it was created 24 hours ago or
  #   more, and not when it was created 1 hour ago.
  # - A disabled feed is never stale: nobody asked it to fetch.
  # - `last_ok_at` and `last_error` are reported as stored.
  describe "stale (§6, §14 item 5)" do
    test "flips at exactly 24 hours after the last successful fetch" do
      feed = issuer_feed!() |> fetched_ok!(@now)
      day_later = DateTime.add(@now, 24, :hour)

      before = health(feed, DateTime.add(day_later, -1, :microsecond))
      assert before.stale == false
      assert before.last_ok_at == @now
      assert before.last_error == nil

      assert health(feed, day_later).stale == true
    end

    test "a feed never fetched is stale 24 hours after its creation, not before" do
      old = issuer_feed!() |> created_at!(DateTime.add(@now, -24, :hour))
      young = issuer_feed!() |> created_at!(DateTime.add(@now, -1, :hour))

      assert health(old, @now).stale == true
      assert health(old, @now).last_ok_at == nil
      assert health(young, @now).stale == false
    end

    test "a disabled feed is never stale" do
      feed = issuer_feed!() |> created_at!(DateTime.add(@now, -48, :hour))

      Repo.query!("SELECT set_config('portfolixir.journal_actor', 'synthetic-health-test', true)")
      feed |> Feed.changeset(%{enabled: false}) |> Repo.update!()

      assert %{stale: false, enabled: false} = health(feed, @now)
    end
  end

  # User story:
  # As the operator,
  # I want each feed's items and errors of the last 24 hours,
  # so that a feed that answers but brings nothing, or fails half the time,
  # shows it.
  #
  # Acceptance criteria:
  # - `items_24h` counts the feed's items first seen within the 24 hours
  #   before the clock (an item first seen exactly 24 hours ago is out).
  # - `err_24h` is the errors of the feed's day rows of today and yesterday
  #   (FeedDay: overlap, never loss), not of the day before.
  describe "the last 24 hours" do
    test "items_24h and err_24h" do
      feed = issuer_feed!()

      ingest!(feed, [parsed(1)], DateTime.add(@now, -24, :hour))
      ingest!(feed, [parsed(2), parsed(3)], DateTime.add(@now, -23, :hour))

      for {days, errors} <- [{0, 1}, {1, 2}, {2, 4}],
          do: Ingest.add_to_day(feed.id, DateTime.add(@now, -days, :day), errors: errors)

      assert %{items_24h: 2, err_24h: 3} = health(feed, @now)
    end
  end

  # User story (A3; ADR-0056 amendment of 2026-11-08, C4):
  # As the operator whose agent may register feeds nobody reads,
  # I want each feed's items and promoted stories of 30 days, and no yield
  # or low-yield flag until stories can be promoted,
  # so that a feed is not called "a feed nobody reads" on its first day,
  # beside a delete tool, for a promotion no tool can make yet.
  #
  # Acceptance criteria:
  # - `items_30d` counts the feed's items first seen within 30 days.
  # - `promoted_30d` counts the promoted stories those items are in (§8: a
  #   story is promoted once a member is; an item outside a story is its
  #   own), each story once.
  # - No feed carries `yield_30d` or `low_yield`; each says
  #   `yield: :not_measured_until_promotion`, at 50 items without a
  #   promotion too.
  describe "yield (A3, C4)" do
    test "yield is not measured until promotion, at 50 items without one too" do
      feed = issuer_feed!()
      at = DateTime.add(@now, -2, :day)
      ingest!(feed, Enum.map(1..50, &parsed/1), at)

      assert %{items_30d: 50, promoted_30d: 0, yield: :not_measured_until_promotion} =
               reported = health(feed, @now)

      refute Map.has_key?(reported, :yield_30d)
      refute Map.has_key?(reported, :low_yield)

      promote!("https://newsroom.example.com/h/7", 9001)
      assert %{promoted_30d: 1, yield: :not_measured_until_promotion} = health(feed, @now)
    end

    test "a promoted story counts once, for every feed with an item in it" do
      {:ok, security} =
        Catalog.update_security(Actor.owner_ui(), security!(), %{
          news_watch: true,
          news_aliases: [%{token: "Northwind", context: [], case: "insensitive"}]
        })

      issuer = feed!(%{class: "issuer", security_id: security.id})
      search = feed!(%{class: "aggregator", url: "https://search.example.com/rss?q=y"})
      at = DateTime.add(@now, -1, :day)

      release = "Northwind ships a crane order"

      ingest!(
        issuer,
        [
          parsed(1, %{title: release}),
          parsed(2, %{title: "Northwind ships crane order"}),
          parsed(3, %{title: "Northwind names a new chair"}),
          parsed(4, %{title: "Northwind opens a terminal"})
        ],
        at
      )

      ingest!(
        search,
        [
          parsed(5, %{
            title: release <> " today",
            link: "https://search.example.com/r?u=5",
            source_domain: "wire.example.com"
          }),
          parsed(6, %{
            title: "Northwind wins an award",
            link: "https://search.example.com/r?u=6",
            source_domain: "wire.example.com"
          })
        ],
        at
      )

      # Both of the issuer's members of the story are promoted: one story.
      promote!("https://newsroom.example.com/h/1", 9002)
      promote!("https://newsroom.example.com/h/2", 9003)

      assert %{items_30d: 4, promoted_30d: 1} = health(issuer, @now)

      # The aggregator's item sits in the promoted story.
      assert %{items_30d: 2, promoted_30d: 1} = health(search, @now)

      # Beyond 30 days nothing counts.
      later = DateTime.add(at, 30, :day)
      assert %{items_30d: 0, promoted_30d: 0} = health(issuer, later)
    end
  end

  # User story:
  # As the operator's agent checking the collection each morning,
  # I want the day's unassigned and ambiguous items and what was dropped,
  # by reason, and blocked,
  # so that a queue that grows or a source that floods is seen the same day.
  #
  # Acceptance criteria (§6):
  # - `day.unassigned` and `day.ambiguous` count the items first seen on
  #   the server's day of the clock that are still unassigned or ambiguous;
  #   an item first seen the day before is not counted.
  # - `day.dropped` gives today's `cap`, `no_source` and `old` over every
  #   feed, `day.blocked` today's blocked drops; yesterday's rows are not
  #   counted.
  describe "the day's counts (§6)" do
    test "unassigned, ambiguous, dropped by reason and blocked" do
      for {name, token} <- [{"Northwind Harbour AG", "Northwind"}, {"Larkspur Inc", "Larkspur"}] do
        {:ok, _} =
          Catalog.update_security(Actor.owner_ui(), security!(name), %{
            news_watch: true,
            news_aliases: [%{token: token, context: [], case: "insensitive"}]
          })
      end

      search = feed!(%{class: "aggregator", url: "https://search.example.com/rss?q=d"})
      other = issuer_feed!()

      agg = fn n, title ->
        parsed(n, %{
          title: title,
          link: "https://search.example.com/r?u=#{n}",
          source_domain: "wire.example.com"
        })
      end

      today = Clock.local_date(@now)
      yesterday = DateTime.add(@now, -1, :day)

      ingest!(search, [agg.(1, "Markets drift")], yesterday)

      ingest!(
        search,
        [
          agg.(2, "Markets drift again"),
          agg.(3, "Northwind and Larkspur merge"),
          agg.(4, "Northwind grows")
        ],
        @now
      )

      Ingest.add_to_day(search.id, @now, dropped_cap: 1, dropped_no_source: 2, dropped_old: 3)
      Ingest.add_to_day(other.id, @now, dropped_old: 1, dropped_blocked: 4)
      Ingest.add_to_day(other.id, yesterday, dropped_cap: 9, dropped_blocked: 9)

      assert %{
               date: ^today,
               unassigned: 1,
               ambiguous: 1,
               dropped: %{cap: 1, no_source: 2, old: 4},
               blocked: 4
             } = News.health(@now).day
    end
  end
end
