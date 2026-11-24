defmodule Portfolixir.News.IngestBoundsTest do
  # ADR-0056 A1 and A3, amendment of 2026-11-24: what one feed's answer may
  # cost behind the parser. Each bound is pinned by counted work on a small
  # answer: the statements the ingest sends are counted through the
  # repository's telemetry, in this test's process only. Synthetic items
  # and hosts only; the domains rated here are this module's own
  # (`*.bounds-test.example`).
  use Portfolixir.DataCase, async: true

  import Ecto.Query
  import Portfolixir.NewsFixtures

  alias Portfolixir.Actor
  alias Portfolixir.News.Ingest
  alias Portfolixir.News.Item
  alias Portfolixir.News.Parser.Item, as: Parsed
  alias Portfolixir.News.Sources
  alias Portfolixir.Repo

  @now ~U[2026-11-24 10:00:00.000000Z]

  defp aggregated(n, domain) do
    %Parsed{
      title: "Synthetic notice #{n}",
      link: "https://search.example.com/r?u=bounds-#{n}",
      source_domain: domain
    }
  end

  defp linked(n, host),
    do: %Parsed{title: "Synthetic notice #{n}", link: "https://#{host}/n/#{n}"}

  defp items(feed), do: Repo.all(from(i in Item, where: i.feed_id == ^feed.id, order_by: i.id))

  # A domain of `labels` labels that shares no parent with another `n`'s.
  defp deep(n, labels), do: String.duplicate("a.", labels - 1) <> "t#{n}"

  # Runs `fun` and answers its value with the statements this process sent
  # meanwhile, as `{query, params}`.
  defp counting(fun) do
    test = self()
    handler = "ingest-bounds-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler,
        [:portfolixir, :repo, :query],
        fn _event, _measurements, metadata, _config ->
          if self() == test, do: send(test, {handler, metadata.query, metadata.params})
        end,
        nil
      )

    try do
      {fun.(), sent(handler, [])}
    after
      :telemetry.detach(handler)
    end
  end

  defp sent(handler, acc) do
    receive do
      {^handler, query, params} -> sent(handler, [{query, params} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp tier_locks(statements),
    do: Enum.count(statements, fn {query, _params} -> query =~ "news tier: ingest" end)

  # The entries of every list a read of the tier table was sent.
  defp tier_read_entries(statements) do
    for {query, params} <- statements,
        query =~ ~s(FROM "news_sources"),
        list <- params,
        is_list(list),
        reduce: 0 do
      sum -> sum + length(list)
    end
  end

  # User story:
  # As the operator who registers a feed from a host I do not control,
  # I want the work the ingest does for one answer's source domains bounded
  # by numbers the server chooses,
  # so that a feed naming many or very long host names costs what any other
  # answer costs (N-11).
  #
  # Acceptance criteria:
  # - An item whose host is longer than a domain name is refused before its
  #   tier is read: no tier lock is taken and no row of the tier table is
  #   read for it; it counts `invalid`, as the database would refuse it.
  # - One answer takes at most 512 tier locks, however many domains it
  #   names and however many labels each has: the items are admitted in the
  #   feed's own order while their domains' locks fit, and the rest counts
  #   `dropped_cap`, to be stored by a later fetch.
  # - The tier table is read with at most one entry per domain of the
  #   answer, and a row still decides a subdomain many labels below it.
  describe "the source domains of one answer" do
    test "a host longer than a domain name is refused before any tier work" do
      feed = feed!(%{class: "issuer", security_id: security!().id})
      hosts = for n <- 1..3, do: String.duplicate("a.", 297) <> "h#{n}.example"
      assert Enum.all?(hosts, &(byte_size(&1) > 253))

      batch = hosts |> Enum.with_index(1) |> Enum.map(fn {host, n} -> linked(n, host) end)

      {{:ok, summary}, statements} = counting(fn -> Ingest.ingest(feed, batch, @now) end)

      assert %{stored: 0, invalid: 3} = summary
      assert tier_locks(statements) == 0
      assert tier_read_entries(statements) == 0
    end

    test "an aggregator's source of that length is refused the same way" do
      feed = feed!(%{class: "aggregator", url: "https://search.example.com/rss-bounds-long"})
      long = String.duplicate("a.", 297) <> "example"

      {{:ok, summary}, statements} =
        counting(fn -> Ingest.ingest(feed, [aggregated(1, long)], @now) end)

      assert %{stored: 0, invalid: 1} = summary
      assert tier_locks(statements) == 0
    end

    test "one answer takes at most 512 tier locks, and the rest waits for a later fetch" do
      feed = feed!(%{class: "aggregator", url: "https://search.example.com/rss-bounds-deep"})
      # Twelve domains of 100 labels: 99 tier locks each, 1,188 together.
      batch = for n <- 1..12, do: aggregated(n, deep(n, 100))
      assert Enum.all?(batch, &(byte_size(&1.source_domain) <= 253))

      {{:ok, summary}, statements} = counting(fn -> Ingest.ingest(feed, batch, @now) end)

      assert tier_locks(statements) <= 512
      # Five domains' locks fit (495); the sixth's would not.
      assert %{stored: 5, dropped_cap: 7, invalid: 0} = summary
      assert Enum.map(items(feed), & &1.domain) == for(n <- 1..5, do: deep(n, 100))

      # The next fetch stores what the first left, in the feed's order.
      later = DateTime.add(@now, 60, :minute)
      assert {:ok, %{stored: 5, known: 5, dropped_cap: 2}} = Ingest.ingest(feed, batch, later)
    end

    test "the tier table is read with one entry per domain, and a row decides far below itself" do
      {:ok, _} =
        Sources.put_source(Actor.owner_ui(), "a.t3.bounds-test.example", :blocked)

      feed = feed!(%{class: "aggregator", url: "https://search.example.com/rss-bounds-read"})

      domains =
        for n <- 1..4, do: String.duplicate("a.", 40) <> "t#{n}.bounds-test.example"

      batch =
        domains |> Enum.with_index(1) |> Enum.map(fn {domain, n} -> aggregated(n, domain) end)

      {{:ok, summary}, statements} = counting(fn -> Ingest.ingest(feed, batch, @now) end)

      # The third domain lies 39 labels below the blocked row.
      assert %{stored: 3, dropped_blocked: 1} = summary
      assert Enum.map(items(feed), & &1.domain) == List.delete_at(domains, 2)

      # Read once for the whole answer and once for what it stores, each
      # time with at most one entry per domain.
      assert tier_read_entries(statements) <= 2 * length(domains)
    end
  end

  defp old(n, tag) do
    %Parsed{
      title: "Synthetic archive notice #{tag} #{n}",
      link: "https://newsroom.example.com/archive/#{tag}/#{n}",
      published_at: DateTime.add(@now, -100, :day)
    }
  end

  defp fresh(n, tag) do
    %Parsed{
      title: "Synthetic notice #{tag} #{n}",
      link: "https://newsroom.example.com/fresh/#{tag}/#{n}"
    }
  end

  defp drop_rows(feed),
    do: Repo.aggregate(from(d in "news_feed_drops", where: d.feed_id == ^feed.id), :count)

  defp day_row(feed) do
    Repo.one!(
      from(d in "news_feed_days",
        where: d.feed_id == ^feed.id,
        select: %{dropped_old: d.dropped_old, dropped_cap: d.dropped_cap}
      )
    )
  end

  # User story:
  # As the operator,
  # I want the record of which items a feed's day dropped bounded per feed
  # and day, and what is dropped past it still counted,
  # so that a feed that lists new links at every fetch costs a bounded
  # number of rows, as it costs a bounded number of items (N-13).
  #
  # Acceptance criteria:
  # - A feed keeps at most `Ingest.drop_rows_max/0` rows (1,000) of the
  #   drop record for one server day, over every reason together, however
  #   many items its answers drop.
  # - Every drop is counted in the day's row. A drop that has a row counts
  #   once that day, however often it is fetched (COR4); a drop past the
  #   bound has none and counts at every fetch that lists it.
  describe "the drop record of one feed and day" do
    test "holds at most drop_rows_max rows, whatever the answers drop" do
      feed = feed!(%{class: "issuer", security_id: security!().id})
      max = 1_000

      first = for n <- 1..(max + 300), do: old(n, "a")
      assert {:ok, %{stored: 0, dropped_old: dropped}} = Ingest.ingest(feed, first, @now)
      assert dropped == max + 300
      assert drop_rows(feed) == max
      assert day_row(feed).dropped_old == max + 300

      # Other links, a fetch later: no row is added, and each is counted.
      second = for n <- 1..(max + 300), do: old(n, "b")
      later = DateTime.add(@now, 15, :minute)
      assert {:ok, %{stored: 0, dropped_old: ^dropped}} = Ingest.ingest(feed, second, later)
      assert drop_rows(feed) == max
      assert day_row(feed).dropped_old == 2 * (max + 300)

      assert Ingest.drop_rows_max() == max
    end

    test "a drop with a row counts once a day, one past the bound at each fetch" do
      feed = feed!(%{class: "issuer", security_id: security!().id})
      max = 1_000
      answer = for n <- 1..(max + 50), do: old(n, "c")

      assert {:ok, %{dropped_old: listed}} = Ingest.ingest(feed, answer, @now)
      assert listed == max + 50
      assert day_row(feed).dropped_old == max + 50

      later = DateTime.add(@now, 15, :minute)
      assert {:ok, %{dropped_old: ^listed}} = Ingest.ingest(feed, answer, later)
      assert drop_rows(feed) == max
      assert day_row(feed).dropped_old == max + 50 + 50
    end

    test "the bound is the feed's and the day's, over every reason together" do
      feed = feed!(%{class: "issuer", security_id: security!().id})
      max = 1_000

      # 200 are stored (A3), 600 are past the cap, 600 are too old.
      answer = for(n <- 1..800, do: fresh(n, "d")) ++ for(n <- 1..600, do: old(n, "d"))

      assert {:ok, %{stored: 200, dropped_cap: 600, dropped_old: 600}} =
               Ingest.ingest(feed, answer, @now)

      assert drop_rows(feed) == max
      assert %{dropped_cap: 600, dropped_old: 600} = day_row(feed)

      # The next server day has room of its own.
      tomorrow = DateTime.add(@now, 2, :day)

      assert {:ok, %{dropped_old: 5}} =
               Ingest.ingest(feed, for(n <- 1..5, do: old(n, "e")), tomorrow)

      assert drop_rows(feed) == max + 5
    end
  end
end
