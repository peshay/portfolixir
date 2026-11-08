defmodule Portfolixir.News.MergeReclusterTest do
  # ADR-0056 §4, B3 and the amendment of 2026-11-08, C3 (Sprint 27 closing
  # act, ORD2): a security merge leaves the target's stories the components
  # of its items. Synthetic names and hosts only.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.News
  alias Portfolixir.News.Cluster
  alias Portfolixir.News.Feed
  alias Portfolixir.News.Item
  alias Portfolixir.News.Sources
  alias Portfolixir.News.Stories
  alias Portfolixir.Repo
  alias Portfolixir.WorldFixtures

  @t ~U[2026-11-03 07:00:00.000000Z]
  @agent Actor.api_token_rw("synthetic-agent")
  @results "Northwind Harbour reports third quarter 2026 results"
  @resigns "Northwind Harbour chief executive resigns with immediate effect"

  defp at(hours), do: DateTime.add(@t, round(hours * 3600), :second)

  defp feed!(attrs) do
    Repo.query!("SELECT set_config('portfolixir.journal_actor', 'synthetic-fixture', true)")

    %Feed{}
    |> Feed.changeset(
      Map.merge(
        %{url: "https://feeds.example.com/#{System.unique_integer([:positive])}", language: "en"},
        attrs
      )
    )
    |> Repo.insert!()
  end

  defp item!(feed, security_id, url, title, hours, language \\ "en") do
    domain = URI.parse(url).host

    %Item{}
    |> Item.changeset(
      Map.merge(Stories.title_keys(title), %{
        feed_id: feed.id,
        class: feed.class,
        security_id: security_id,
        assignment: :assigned,
        first_seen_at: at(hours),
        published_at_claimed: at(hours),
        title: title,
        canonical_url: url,
        domain: domain,
        tier: Sources.tier_for(domain, feed.class),
        language: language,
        content_hash: :sha256 |> :crypto.hash(url) |> Base.encode16(case: :lower)
      })
    )
    |> Repo.insert!()
  end

  defp components(security_id, language) do
    from(i in Item, where: i.security_id == ^security_id and i.language == ^language)
    |> Repo.all()
    |> Stories.cluster()
    |> MapSet.new(fn story -> MapSet.new(story.members, & &1.canonical_url) end)
  end

  defp stored(security_id, language) do
    from(c in Cluster,
      where: c.security_id == ^security_id and c.language == ^language,
      preload: :items
    )
    |> Repo.all()
    |> MapSet.new(fn story -> MapSet.new(story.items, & &1.canonical_url) end)
  end

  # User story (ADR-0056 §4, B3; the amendment of 2026-11-08, C3):
  # As the agent reading a merged security's news,
  # I want the merge to leave the target's stories the components of its
  # items, in every language the source had,
  # so that one event reported for both securities is one story at once,
  # not two for good.
  #
  # Acceptance criteria:
  # - Right after `reassign_security/3`, the target's stored stories equal
  #   the pure rule's components of its items, per language; an item the
  #   source and the target shared as candidates is in a story too.
  # - A later incremental recluster keeps them so.
  # - The moved items enter the target's scope at the merge (`scope_at`),
  #   their first sight unchanged.
  test "the target is reclustered in full for each language the merge moved" do
    source = WorldFixtures.create_security!(name: "Northwind Harbour dup", ticker: nil)
    target = WorldFixtures.create_security!(name: "Northwind Harbour", ticker: nil)
    aggregator = feed!(%{class: "aggregator"})
    aggregator_de = feed!(%{class: "aggregator", language: "de"})

    moved = item!(aggregator, source.id, "https://daily.example.com/1", @results, 0)
    item!(aggregator_de, source.id, "https://daily.example.de/1", @results, 0, "de")
    {:ok, _} = Stories.recluster({:security, source.id}, "en", at(0))
    {:ok, _} = Stories.recluster({:security, source.id}, "de", at(0))
    item!(aggregator, target.id, "https://wire.example.com/1", @results, 1)
    item!(aggregator_de, target.id, "https://wire.example.de/1", @results, 1, "de")
    {:ok, _} = Stories.recluster({:security, target.id}, "en", at(1))
    {:ok, _} = Stories.recluster({:security, target.id}, "de", at(1))

    shared =
      %Item{}
      |> Item.changeset(
        Map.merge(Stories.title_keys(@results), %{
          feed_id: aggregator.id,
          class: :aggregator,
          assignment: :ambiguous,
          candidates: [source.id, target.id],
          first_seen_at: at(2),
          title: @results,
          canonical_url: "https://chatter.example.org/1",
          domain: "chatter.example.org",
          tier: :awareness,
          language: "en",
          content_hash: String.duplicate("c", 64)
        })
      )
      |> Repo.insert!()

    Repo.transaction(fn ->
      {:ok, _} = News.reassign_security(@agent, source.id, target.id)
      Repo.delete!(Repo.reload!(source))
    end)

    for language <- ["en", "de"] do
      assert stored(target.id, language) == components(target.id, language), language
      assert MapSet.size(stored(target.id, language)) == 1, language
    end

    assert Repo.reload!(shared).cluster_id

    moved = Repo.reload!(moved)
    assert moved.first_seen_at == at(0)
    assert DateTime.compare(moved.scope_at, at(2)) == :gt

    # Days later, new news of the target: an incremental recluster.
    item!(aggregator, target.id, "https://wire.example.com/2", @resigns, 100)
    {:ok, _} = Stories.recluster({:security, target.id}, "en", at(100))
    assert stored(target.id, "en") == components(target.id, "en")
  end
end
