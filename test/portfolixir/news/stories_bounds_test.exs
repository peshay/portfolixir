defmodule Portfolixir.News.StoriesBoundsTest do
  # ADR-0056 B3 and B4, amendment of 2026-11-24 (F2): what one recluster may
  # cost. The window is read on both clocks, the feed's claim and the
  # server's first sight, an item is compared with a bounded number of
  # others, and a recluster reads what the server's clock puts near its
  # seeds. Each bound is pinned on a small input: by the stories a lowered
  # limit gives, or by the rows a recluster reads, counted through the
  # repository's telemetry in this test's process. Synthetic items only.
  use Portfolixir.DataCase, async: true
  use ExUnitProperties

  import Ecto.Query
  import Portfolixir.NewsFixtures

  alias Portfolixir.News.Cluster
  alias Portfolixir.News.Ingest
  alias Portfolixir.News.Item
  alias Portfolixir.News.Parser.Item, as: Parsed
  alias Portfolixir.News.Retention
  alias Portfolixir.News.Stories
  alias Portfolixir.Repo

  @t ~U[2026-11-03 07:00:00.000000Z]
  @hour 3_600_000_000

  defp at(microseconds), do: DateTime.add(@t, microseconds, :microsecond)

  # A pure item: `seen` and `claimed` in microseconds after @t.
  defp item(key, title, claimed, seen, tier \\ :secondary) do
    Map.merge(Stories.title_keys(title), %{
      id: key,
      cluster_id: nil,
      title: title,
      canonical_url: "https://source.example/#{key}",
      tier: tier,
      published_at: at(min(claimed, seen)),
      first_seen_at: at(seen),
      content_hash: ""
    })
  end

  defp keys(stories),
    do: MapSet.new(stories, fn story -> MapSet.new(story.members, & &1.id) end)

  # User story:
  # As the operator whose agent reads stories,
  # I want two items compared only when the server saw them within the
  # window of each other, and each item compared with a bounded number of
  # others,
  # so that what a feed claims about its items' dates never decides how
  # much one recluster has to compare (N-12).
  #
  # Acceptance criteria:
  # - Two items with the same title and the same claimed time are one story
  #   when their first sights lie within the window of each other (72
  #   hours, inclusive), and two stories a microsecond beyond it.
  # - An item is compared with at most `compare_max` items first seen after
  #   it (800 by default): with the limit lowered to 2, an item and the
  #   fifth after it are not compared, whatever their titles.
  # - For any small set of items the stories are the components of the
  #   rule, C1's anchoring included, as a plain pairwise reading of the
  #   rule gives them.
  describe "cluster/2 under the server's clock" do
    test "the same claim links only within the window of the first sights" do
      a = item(:a, "Northwind Harbour names a new harbour master", 0, 0)
      b = item(:b, "Northwind Harbour names a new harbour master", 0, 72 * @hour)
      assert keys(Stories.cluster([a, b])) == MapSet.new([MapSet.new([:a, :b])])

      late = item(:b, "Northwind Harbour names a new harbour master", 0, 72 * @hour + 1)

      assert keys(Stories.cluster([a, late])) ==
               MapSet.new([MapSet.new([:a]), MapSet.new([:b])])
    end

    test "a chain of first sights still makes one story" do
      chain =
        for n <- 0..5,
            do: item(n, "Northwind Harbour names a new harbour master", 0, n * 60 * @hour)

      assert [story] = Stories.cluster(chain)
      assert length(story.members) == 6
    end

    test "an item is compared with at most compare_max items after it" do
      same = "Northwind Harbour opens a container terminal"

      items = [
        item(1, same, 0, 1),
        item(2, "Harbour cranes idle during a regional strike", 0, 2),
        item(3, "Baltic ferry timetable changes in winter", 0, 3),
        item(4, "Quarterly dividend declared by the board", 0, 4),
        item(5, same, 0, 5)
      ]

      assert Stories.compare_max() == 800
      assert MapSet.member?(keys(Stories.cluster(items)), MapSet.new([1, 5]))

      bounded = keys(Stories.cluster(items, compare_max: 2))
      assert MapSet.size(bounded) == 5
      refute MapSet.member?(bounded, MapSet.new([1, 5]))
    end

    property "the stories are the components of the rule, anchoring included" do
      titles = [
        "alpha beta gamma delta epsilon",
        "alpha beta gamma delta zeta",
        "alpha beta gamma eta zeta",
        "theta iota kappa lambda mu",
        "***"
      ]

      generator =
        list_of(
          tuple(
            {member_of(titles), integer(0..200), integer(0..200),
             member_of([:primary, :secondary, :awareness])}
          ),
          max_length: 14
        )

      check all(rows <- generator, max_runs: 150) do
        items =
          rows
          |> Enum.with_index()
          |> Enum.map(fn {{title, claimed, seen, tier}, n} ->
            item(n, title, claimed * @hour, seen * @hour, tier)
          end)

        options = [window_hours: 72, similarity: Decimal.new("0.6")]
        assert keys(Stories.cluster(Enum.shuffle(items), options)) == reference(items, 72, {3, 5})
      end
    end
  end

  # The rule read pairwise, with no bound on the work: two items are linked
  # when their publications and their first sights lie within the window
  # and their titles match; the components of the primary items, and of the
  # others; a lower component joins the primary component it is linked to
  # whose survivor key is smallest (C1).
  defp reference(items, window_hours, {numerator, denominator}) do
    window = window_hours * @hour

    linked? = fn a, b ->
      words_a = MapSet.new(a.title_words)
      words_b = MapSet.new(b.title_words)
      shared = MapSet.size(MapSet.intersection(words_a, words_b))
      union = MapSet.size(words_a) + MapSet.size(words_b) - shared

      abs(DateTime.diff(a.published_at, b.published_at, :microsecond)) <= window and
        abs(DateTime.diff(a.first_seen_at, b.first_seen_at, :microsecond)) <= window and
        MapSet.size(words_a) > 0 and MapSet.size(words_b) > 0 and
        (a.title_norm_hash == b.title_norm_hash or shared * denominator >= numerator * union)
    end

    {primary, lower} = Enum.split_with(items, &(&1.tier == :primary))
    anchors = components(primary, linked?)

    rank = %{primary: 0, secondary: 1, awareness: 2}

    survivor = fn item ->
      {rank[item.tier], DateTime.to_unix(item.first_seen_at, :microsecond), item.canonical_url}
    end

    joined =
      lower
      |> components(linked?)
      |> Enum.map(fn members ->
        linked =
          Enum.filter(anchors, fn anchor -> Enum.any?(members, &any?(anchor, &1, linked?)) end)

        case linked do
          [] ->
            {:alone, members}

          some ->
            {Enum.min_by(some, fn anchor -> anchor |> Enum.map(survivor) |> Enum.min() end),
             members}
        end
      end)

    stories =
      Enum.map(anchors, fn anchor ->
        anchor ++
          Enum.flat_map(joined, fn {to, members} -> if to == anchor, do: members, else: [] end)
      end) ++ for({:alone, members} <- joined, do: members)

    MapSet.new(stories, fn members -> MapSet.new(members, & &1.id) end)
  end

  defp any?(members, item, linked?), do: Enum.any?(members, &linked?.(&1, item))

  defp components(items, linked?) do
    Enum.reduce(items, [], fn item, groups ->
      {with_item, without} = Enum.split_with(groups, &any?(&1, item, linked?))
      [[item | List.flatten(with_item)] | without]
    end)
  end

  # -- the stored stories --------------------------------------------------------

  defp parsed(key, title, claimed) do
    %Parsed{
      title: title,
      link: "https://newsroom.example.com/bounds/#{key}",
      published_at: claimed
    }
  end

  # Runs `fun` and answers its value with the rows of `news_items` this
  # process read meanwhile.
  defp counting_item_rows(fun) do
    test = self()
    handler = "stories-bounds-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler,
        [:portfolixir, :repo, :query],
        fn _event, _measurements, metadata, _config ->
          with true <- self() == test,
               %{query: "SELECT" <> _ = query, result: {:ok, %{num_rows: rows}}} <- metadata,
               true <- query =~ ~s(FROM "news_items") do
            send(test, {handler, rows})
          end
        end,
        nil
      )

    try do
      {fun.(), read(handler, 0)}
    after
      :telemetry.detach(handler)
    end
  end

  defp read(handler, sum) do
    receive do
      {^handler, rows} -> read(handler, sum + rows)
    after
      0 -> sum
    end
  end

  defp story_of(link), do: Repo.get_by!(Item, canonical_url: link).cluster_id

  # User story:
  # As the operator,
  # I want a recluster to read the items the server saw near its seeds, and
  # a retention run to recompute the stories that lost a member,
  # so that neither a feed's claimed dates nor the size of a scope decides
  # what one fetch or one retention run has to read and compare (N-12).
  #
  # Acceptance criteria:
  # - Items first seen ten days apart that claim one publication time are
  #   not one story, though their titles are equal.
  # - A fetch's recluster reads the items first seen within the window of
  #   its own, not every item that claims the same time: with thirty older
  #   items of one claimed time in the scope it reads none of them.
  # - Removing a scope's expired items reads the stories that lost a member
  #   and the recent window, not the whole scope.
  describe "the stored stories" do
    test "a fetch's recluster reads what the server saw near its items, whatever they claim" do
      security = security!()
      feed = feed!(%{class: "issuer", security_id: security.id})
      scope = {:security, security.id}
      claim = ~U[2026-11-01 09:00:00Z]
      old = ~U[2026-11-03 10:00:00.000000Z]
      now = DateTime.add(old, 10, :day)

      older =
        [parsed(:same, "Northwind Harbour names a new harbour master", claim)] ++
          for n <- 1..29,
              do: parsed("old-#{n}", "Synthetic notice number #{n} of the series", claim)

      assert {:ok, %{stored: 30}} = Ingest.ingest(feed, older, old)

      newer = [
        parsed(:same_again, "Northwind Harbour names a new harbour master", claim),
        parsed(:new_1, "Harbour cranes idle during a regional strike", claim),
        parsed(:new_2, "Baltic ferry timetable changes in winter", claim)
      ]

      assert {:ok, %{stored: 3}} = Ingest.ingest(feed, newer, now)

      # Equal titles and equal claims, first seen ten days apart: two stories.
      assert story_of("https://newsroom.example.com/bounds/same") !=
               story_of("https://newsroom.example.com/bounds/same_again")

      assert Repo.aggregate(from(c in Cluster, where: c.security_id == ^security.id), :count) ==
               33

      {{:ok, _summary}, rows} = counting_item_rows(fn -> Stories.recluster(scope, "en", now) end)

      # The three recent items, as seeds, as their own neighbours and as
      # their stories' members: never the thirty older ones.
      assert rows <= 9
    end

    test "a retention run recomputes the stories that lost a member, not the scope" do
      security = security!()
      feed = feed!(%{class: "issuer", security_id: security.id})
      now = ~U[2026-11-24 10:00:00.000000Z]
      expired = DateTime.add(now, -91, :day)
      kept = DateTime.add(now, -89, :day)
      recent = DateTime.add(now, -10, :day)

      title = "Northwind Harbour names a new harbour master"
      assert {:ok, %{stored: 1}} = Ingest.ingest(feed, [parsed(:gone, title, nil)], expired)
      assert {:ok, %{stored: 1}} = Ingest.ingest(feed, [parsed(:stays, title, nil)], kept)

      assert story_of("https://newsroom.example.com/bounds/gone") ==
               story_of("https://newsroom.example.com/bounds/stays")

      others =
        for n <- 1..30,
            do: parsed("other-#{n}", "Synthetic notice number #{n} of the series", nil)

      assert {:ok, %{stored: 30}} = Ingest.ingest(feed, others, recent)

      {{:ok, summary}, rows} = counting_item_rows(fn -> Retention.run(now) end)

      assert summary.items == 1
      refute Repo.get_by(Item, canonical_url: "https://newsroom.example.com/bounds/gone")

      story = Repo.get!(Cluster, story_of("https://newsroom.example.com/bounds/stays"))
      assert story.member_count == 1

      # The expired item and the story's one remaining member are read, a
      # few times over; the thirty other items of the scope are not.
      assert rows < 30
    end
  end
end
