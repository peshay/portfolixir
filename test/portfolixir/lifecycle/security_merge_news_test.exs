defmodule Portfolixir.Lifecycle.SecurityMergeNewsTest do
  # ADR-0050 §9, §14 and ADR-0056 §2, §4, B7 (Sprint 27, N2): what a
  # security merge does with the news rows that name its source. The
  # disposition map declares `:repoint` for the three news keys onto
  # `securities`; this pins that the merge does it. Synthetic data only.
  use Portfolixir.DataCase, async: true

  import Ecto.Query

  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Lifecycle
  alias Portfolixir.News.Cluster
  alias Portfolixir.News.Feed
  alias Portfolixir.News.Item
  alias Portfolixir.Repo
  alias Portfolixir.WorldFixtures

  @seen ~U[2026-11-07 10:00:00.000000Z]

  defp agent, do: Actor.api_token_rw("synthetic-agent")

  # The fixtures write feeds past the context (whose writers come in N8);
  # feeds are journal-armed (B7), so the fixture names an actor first.
  defp actor!,
    do: Repo.query!("SELECT set_config('portfolixir.journal_actor', 'synthetic-fixture', true)")

  defp security!(name),
    do: WorldFixtures.create_security!(name: name, ticker: nil, asset_class: "equity")

  defp feed!(attrs) do
    actor!()

    %Feed{}
    |> Feed.changeset(
      Map.merge(
        %{url: "https://feeds.example.com/#{System.unique_integer([:positive])}", language: "en"},
        attrs
      )
    )
    |> Repo.insert!()
  end

  defp item!(feed, attrs) do
    %Item{}
    |> Item.changeset(
      Map.merge(
        %{
          feed_id: feed.id,
          class: feed.class,
          security_id: feed.security_id,
          assignment: "assigned",
          first_seen_at: @seen,
          title: "Quarterly figures",
          canonical_url: "https://news.example.com/#{System.unique_integer([:positive])}",
          domain: "news.example.com",
          tier: if(feed.class == :aggregator, do: "secondary", else: "primary"),
          language: "en",
          content_hash: String.duplicate("c", 64),
          title_norm_hash: String.duplicate("d", 64),
          title_words: ~w(quarterly figures)
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  defp cluster_of!(item) do
    cluster =
      %Cluster{}
      |> Cluster.changeset(%{
        security_id: item.security_id,
        language: item.language,
        representative_item_id: item.id,
        member_count: 1,
        earliest_first_seen_at: item.first_seen_at,
        earliest_published_at: item.published_at,
        earliest_url: item.canonical_url,
        best_tier: item.tier
      })
      |> Repo.insert!()

    item |> Item.changeset(%{cluster_id: cluster.id}) |> Repo.update!()
    cluster
  end

  # User story (ADR-0050 §9; ADR-0056 §2, §4):
  # As the operator merging a duplicate security into the one I keep,
  # I want its news feeds, stories and items to follow it onto the target,
  # so that the merge goes through and no news about the company is lost
  # or left pointing at a security that no longer exists.
  #
  # Acceptance criteria:
  # - The source's issuer feed is bound to the target, with one journal
  #   entry naming the merge's actor.
  # - The source's story and its item, and an item outside any story, name
  #   the target; the story's item follows it.
  # - An ambiguous item that listed the source and another security lists
  #   the target and that security, sorted; one that listed the source and
  #   the target is assigned to the target, its candidates empty.
  # - The source is gone; the manifest carries no news key (its every key
  #   has words on the merge records list, and B7 leaves items unjournaled).
  test "a merge moves the source's feeds, stories and items onto the target" do
    source = security!("Northwind Harbour Logistics AG")
    target = security!("Northwind Harbour Logistics AG")
    other = security!("Larkspur Robotics Inc")

    feed = feed!(%{class: "issuer", security_id: source.id})
    clustered = item!(feed, %{})
    cluster = cluster_of!(clustered)
    loose = item!(feed, %{title: "Annual meeting"})

    aggregator = feed!(%{class: "aggregator"})

    with_other =
      item!(aggregator, %{
        security_id: nil,
        assignment: "ambiguous",
        candidates: [source.id, other.id]
      })

    with_target =
      item!(aggregator, %{
        security_id: nil,
        assignment: "ambiguous",
        candidates: [source.id, target.id]
      })

    assert {:ok, preview} = Lifecycle.preview_security_merge(source.id, target.id)
    assert Enum.all?(preview.guards, & &1.passed)

    assert {:ok, record, :applied} =
             Lifecycle.merge_security(agent(), source.id, target.id, %{
               plan_digest: preview.plan_digest,
               collapse_key_equal: false
             })

    assert Repo.reload(source) == nil
    assert Repo.reload!(feed).security_id == target.id
    assert Repo.reload!(cluster).security_id == target.id
    assert Repo.reload!(clustered).security_id == target.id
    assert Repo.reload!(clustered).cluster_id == cluster.id
    assert Repo.reload!(loose).security_id == target.id

    assert %Item{assignment: :ambiguous, candidates: candidates} = Repo.reload!(with_other)
    assert candidates == Enum.sort([target.id, other.id])

    assert %Item{assignment: :assigned, security_id: assigned, candidates: []} =
             Repo.reload!(with_target)

    assert assigned == target.id

    refute Map.has_key?(record.manifest, "news")

    assert [entry] =
             Repo.all(
               from(e in Journal.Entry,
                 where: e.resource_type == "news_feed" and e.resource_id == ^to_string(feed.id)
               )
             )

    assert entry.operation == :update
    assert entry.actor_label == "synthetic-agent"
    assert entry.before["security_id"] == source.id
    assert entry.after["security_id"] == target.id
  end
end
