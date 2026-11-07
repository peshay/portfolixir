defmodule Portfolixir.News.AssignmentTest do
  # ADR-0056 §2 and §14 item 1 (Sprint 27, N4): identity. Aggregator items
  # are matched against the universe and written `assigned`, `unassigned`
  # or `ambiguous` with their candidates; issuer, regulatory and thematic
  # items are bound by construction and never touched by the matcher; a
  # change to a security's news identity re-matches the unassigned and
  # ambiguous aggregator items of the last 7 days. Items are inserted
  # directly (the fetcher is N3's). Synthetic names only.
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Classifications
  alias Portfolixir.News
  alias Portfolixir.News.Cluster
  alias Portfolixir.News.Feed
  alias Portfolixir.News.Item
  alias Portfolixir.Repo

  @hash String.duplicate("a", 64)

  defp owner, do: Actor.owner_ui()

  # Feeds are journal-armed (B7); a feed written past the context names an
  # actor for the guard first.
  defp actor!,
    do: Repo.query!("SELECT set_config('portfolixir.journal_actor', 'synthetic-n4-test', true)")

  defp feed!(attrs) do
    actor!()

    %Feed{}
    |> Feed.changeset(
      Map.merge(
        %{
          url: "https://feeds.example.com/#{System.unique_integer([:positive])}.xml",
          language: "en"
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  defp item!(feed, title, attrs \\ %{}) do
    %Item{}
    |> Item.changeset(
      Map.merge(
        %{
          feed_id: feed.id,
          class: feed.class,
          security_id: feed.security_id,
          category_id: feed.category_id,
          assignment: if(feed.class == :aggregator, do: "unassigned", else: "assigned"),
          first_seen_at: DateTime.utc_now(),
          title: title,
          canonical_url: "https://press.example.com/#{System.unique_integer([:positive])}",
          domain: "press.example.com",
          tier: if(feed.class == :aggregator, do: "secondary", else: "primary"),
          language: "en",
          content_hash: @hash,
          title_norm_hash: @hash
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  defp watched!(name, aliases, opts \\ []) do
    security =
      create_security!(name: name, ticker: nil, asset_class: Keyword.get(opts, :class, "equity"))

    {:ok, security} =
      Catalog.update_security(owner(), security, %{news_watch: true, news_aliases: aliases})

    security
  end

  defp insensitive(token, context \\ []),
    do: %{token: token, context: context, case: "insensitive"}

  defp reload(item), do: Repo.get!(Item, item.id)

  defp days_ago(days), do: DateTime.add(DateTime.utc_now(), -days * 86_400, :second)

  setup do
    northwind = watched!("Northwind Harbour Logistics AG", [insensitive("Northwind Harbour")])
    larkspur = watched!("Larkspur Robotics Inc", [insensitive("Larkspur")])
    aggregator = feed!(%{class: "aggregator"})

    %{northwind: northwind, larkspur: larkspur, aggregator: aggregator}
  end

  # User story:
  # As the operator's agent reading what the news layer collected,
  # I want an aggregator item filed on the one security it names, left
  # unassigned when it names none, and marked ambiguous with the candidates
  # when it names several,
  # so that nothing is guessed and the queue of the unassigned and ambiguous
  # is what needs a look.
  #
  # Acceptance criteria:
  # - One, none and several matching aliases give `assigned` (with the
  #   security), `unassigned`, and `ambiguous` with the sorted candidates.
  # - The counts of the three outcomes are returned.
  # - An ETF in the universe is never matched from an aggregator item.
  describe "assign_aggregator_items/1" do
    test "one, none and several matching aliases", ctx do
      one = item!(ctx.aggregator, "Northwind Harbour wins a port contract")
      none = item!(ctx.aggregator, "Markets drift ahead of the holiday")
      several = item!(ctx.aggregator, "Larkspur and Northwind Harbour agree a joint venture")

      assert {:ok, %{assigned: 1, unassigned: 1, ambiguous: 1}} =
               News.assign_aggregator_items([one, none.id, several])

      assert %Item{assignment: :assigned, candidates: []} = one = reload(one)
      assert one.security_id == ctx.northwind.id

      assert %Item{assignment: :unassigned, security_id: nil, candidates: []} = reload(none)

      assert %Item{assignment: :ambiguous, security_id: nil, candidates: candidates} =
               reload(several)

      assert candidates == Enum.sort([ctx.northwind.id, ctx.larkspur.id])
    end

    test "an ETF's aliases match no aggregator item", ctx do
      _fund =
        watched!("Synthetic Harbour Index ETF", [insensitive("Harbour Index")], class: "etf")

      item = item!(ctx.aggregator, "Harbour Index hits a record")

      assert {:ok, %{unassigned: 1}} = News.assign_aggregator_items([item])
      assert reload(item).assignment == :unassigned
    end

    test "a held security is matched without a watch flag", ctx do
      world = base_world(name: "News Portfolio")
      held = create_security!(name: "Quillfeather Paper SE", ticker: nil, asset_class: "equity")
      buy!(world, held, quantity: "4")

      {:ok, held} =
        Catalog.update_security(owner(), held, %{news_aliases: [insensitive("Quillfeather")]})

      item = item!(ctx.aggregator, "Quillfeather buys a mill")

      assert {:ok, %{assigned: 1}} = News.assign_aggregator_items([item])
      assert reload(item).security_id == held.id
    end

    test "an empty list writes nothing" do
      assert {:ok, %{assigned: 0, unassigned: 0, ambiguous: 0}} =
               News.assign_aggregator_items([])
    end
  end

  # User story:
  # As the operator whose issuer and regulatory feeds belong to a security,
  # I want their items to stay on that security whatever their titles say,
  # so that a filing that mentions another company is not moved off its
  # issuer, nor a thematic item off its category.
  #
  # Acceptance criteria:
  # - An issuer, a regulatory and a thematic item handed to the matcher are
  #   left exactly as they were, even when their titles name another
  #   security of the universe.
  # - An aggregator item already assigned, or sitting in a story, is left
  #   as it is: only unassigned and ambiguous items are matched.
  describe "items bound by construction" do
    test "issuer, regulatory and thematic items are never touched", ctx do
      issuer = feed!(%{class: "issuer", security_id: ctx.northwind.id})
      regulatory = feed!(%{class: "regulatory", security_id: ctx.northwind.id})

      {:ok, classification} =
        Classifications.create_classification(owner(), %{
          name: "Themes #{System.unique_integer([:positive])}"
        })

      {:ok, category} =
        Classifications.create_category(owner(), %{
          classification_id: classification.id,
          name: "Robotics"
        })

      thematic = feed!(%{class: "thematic", category_id: category.id})

      items = [
        item!(issuer, "Northwind Harbour comments on Larkspur's offer"),
        item!(regulatory, "Form 8-K: Larkspur named as a counterparty"),
        item!(thematic, "Larkspur leads a robotics rally")
      ]

      assert {:ok, %{assigned: 0, unassigned: 0, ambiguous: 0}} =
               News.assign_aggregator_items(items)

      for item <- items do
        stored = reload(item)
        assert stored.assignment == :assigned
        assert stored.security_id == item.security_id
        assert stored.category_id == item.category_id
        assert stored.candidates == []
        assert stored.updated_at == item.updated_at
      end

      assert Enum.map(items, &reload(&1).security_id) == [
               ctx.northwind.id,
               ctx.northwind.id,
               nil
             ]
    end

    test "an aggregator item already assigned, in a story, is left as it is", ctx do
      item =
        item!(ctx.aggregator, "Larkspur opens a plant", %{
          assignment: "assigned",
          security_id: ctx.northwind.id
        })

      story =
        %Cluster{}
        |> Cluster.changeset(%{
          security_id: ctx.northwind.id,
          language: "en",
          representative_item_id: item.id,
          member_count: 1,
          earliest_first_seen_at: item.first_seen_at,
          earliest_published_at: item.published_at,
          earliest_url: item.canonical_url,
          best_tier: item.tier
        })
        |> Repo.insert!()

      item = item |> Item.changeset(%{cluster_id: story.id}) |> Repo.update!()

      assert {:ok, %{assigned: 0, unassigned: 0, ambiguous: 0}} =
               News.assign_aggregator_items([item])

      assert %Item{assignment: :assigned, cluster_id: cluster_id, security_id: security_id} =
               reload(item)

      assert {cluster_id, security_id} == {story.id, ctx.northwind.id}
    end
  end

  # User story:
  # As the operator who just aliased a security, or corrected an alias,
  # I want the last week's unassigned and ambiguous aggregator items matched
  # again at once,
  # so that the news I missed for want of the alias is filed now, and items
  # older than the week stay as they were.
  #
  # Acceptance criteria:
  # - rematch_recent/1 re-matches unassigned and ambiguous aggregator items
  #   first seen within 7 days of the given time, and none older.
  # - A change to a security's aliases through the catalogue re-matches,
  #   after its write commits.
  # - Setting `news_watch`, or creating a watched security, re-matches; a
  #   change that leaves the news identity alone does not.
  # - An ambiguous item listing a security that no longer exists is matched
  #   afresh, the unknown id dropped.
  describe "re-matching the last 7 days" do
    test "rematch_recent/1 reaches 7 days back by first sight, not 8", ctx do
      now = DateTime.utc_now()

      recent =
        item!(ctx.aggregator, "Tidewater Rail orders trains", %{first_seen_at: days_ago(6)})

      old = item!(ctx.aggregator, "Tidewater Rail wins a tender", %{first_seen_at: days_ago(8)})

      tidewater = create_security!(name: "Tidewater Rail AG", ticker: nil, asset_class: "equity")

      # Written past the catalogue, so only the explicit call re-matches.
      tidewater
      |> Ecto.Changeset.change(news_watch: true)
      |> Ecto.Changeset.put_embed(:news_aliases, [
        %Portfolixir.News.Alias{token: "Tidewater Rail", context: [], case: :insensitive}
      ])
      |> then(fn changeset ->
        actor!()
        Repo.update!(changeset)
      end)

      assert reload(recent).assignment == :unassigned

      assert {:ok, %{assigned: 1}} = News.rematch_recent(now)
      assert reload(recent).security_id == tidewater.id
      assert reload(old).assignment == :unassigned
    end

    test "an alias change re-matches the last 7 days and not an item 8 days old", ctx do
      recent =
        item!(ctx.aggregator, "Northwind Harbour and Saltmarsh share a berth", %{
          first_seen_at: days_ago(6)
        })

      unnamed = item!(ctx.aggregator, "Saltmarsh raises prices", %{first_seen_at: days_ago(1)})
      old = item!(ctx.aggregator, "Saltmarsh cuts jobs", %{first_seen_at: days_ago(8)})
      News.assign_aggregator_items([recent, unnamed, old])
      assert reload(recent).assignment == :assigned

      saltmarsh = watched!("Saltmarsh Water plc", [])
      assert reload(unnamed).assignment == :unassigned

      {:ok, _} =
        Catalog.update_security(owner(), saltmarsh, %{news_aliases: [insensitive("Saltmarsh")]})

      assert %Item{assignment: :assigned, security_id: security_id} = reload(unnamed)
      assert security_id == saltmarsh.id
      assert reload(old).assignment == :unassigned
      # Only unassigned and ambiguous items are matched again.
      assert reload(recent).security_id == ctx.northwind.id
    end

    test "an ambiguous item becomes assigned when an alias is removed", ctx do
      item = item!(ctx.aggregator, "Larkspur and Northwind Harbour agree a joint venture")
      News.assign_aggregator_items([item])
      assert reload(item).assignment == :ambiguous

      {:ok, _} = Catalog.update_security(owner(), ctx.larkspur, %{news_aliases: []})

      assert %Item{assignment: :assigned, candidates: []} = stored = reload(item)
      assert stored.security_id == ctx.northwind.id
    end

    test "watching a security, or creating a watched one, re-matches", ctx do
      item = item!(ctx.aggregator, "Ironbark Timber expands")
      ironbark = create_security!(name: "Ironbark Timber Ltd", ticker: nil, asset_class: "equity")

      {:ok, ironbark} =
        Catalog.update_security(owner(), ironbark, %{news_aliases: [insensitive("Ironbark")]})

      # Aliased but outside the universe: nothing to match yet.
      assert reload(item).assignment == :unassigned

      {:ok, _} = Catalog.update_security(owner(), ironbark, %{news_watch: true})
      assert reload(item).security_id == ironbark.id

      other = item!(ctx.aggregator, "Fernhill Optics ships a lens")

      {:ok, fernhill} =
        Catalog.create_security(owner(), %{
          name: "Fernhill Optics AG",
          currency_code: "EUR",
          asset_class: "equity",
          news_watch: true,
          news_aliases: [insensitive("Fernhill Optics")]
        })

      assert reload(other).security_id == fernhill.id
    end

    test "a change outside the news identity does not re-match", ctx do
      world = base_world(name: "Quiet Portfolio")
      quiet = create_security!(name: "Quillfeather Paper SE", ticker: nil, asset_class: "equity")

      {:ok, quiet} =
        Catalog.update_security(owner(), quiet, %{news_aliases: [insensitive("Quillfeather")]})

      item = item!(ctx.aggregator, "Quillfeather buys a mill")
      # Held now, so in the universe; a holding is not an identity change.
      buy!(world, quiet, quantity: "1")

      {:ok, _} = Catalog.update_security(owner(), quiet, %{note: "A synthetic note"})
      assert reload(item).assignment == :unassigned

      assert {:ok, %{assigned: 1}} = News.rematch_recent(DateTime.utc_now())
      assert reload(item).security_id == quiet.id
    end

    test "a candidate that no longer exists is dropped on the re-match", ctx do
      item =
        item!(ctx.aggregator, "Northwind Harbour and a vanished company merge", %{
          assignment: "ambiguous",
          candidates: [ctx.northwind.id, 2_000_000_000]
        })

      assert {:ok, %{assigned: 1}} = News.rematch_recent(DateTime.utc_now())

      assert %Item{assignment: :assigned, candidates: []} = stored = reload(item)
      assert stored.security_id == ctx.northwind.id
    end
  end
end
