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
end
