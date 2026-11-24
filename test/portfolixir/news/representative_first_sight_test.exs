defmodule Portfolixir.News.RepresentativeFirstSightTest do
  # ADR-0056 B3, B4 and B5, amendment of 2026-11-24 (F9): a story's
  # representative is the member of the best tier the server saw first;
  # a claimed publication time orders only the items of one first sight.
  # Synthetic names and hosts only, every rated domain this module's own
  # (`*.representative-test.example.org`).
  use Portfolixir.DataCase, async: true

  import Ecto.Query
  import Portfolixir.NewsFixtures

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Clock
  alias Portfolixir.News.Cluster
  alias Portfolixir.News.Ingest
  alias Portfolixir.News.Item
  alias Portfolixir.News.Parser.Item, as: Parsed
  alias Portfolixir.News.Promotion
  alias Portfolixir.News.Reads
  alias Portfolixir.News.Sources
  alias Portfolixir.News.Stories
  alias Portfolixir.Repo

  @t ~U[2026-11-03 07:00:00.000000Z]

  defp at(hours), do: DateTime.add(@t, round(hours * 3600), :second)

  defp item(key, tier, claimed, seen) do
    title = "Northwind Harbour names a new harbour master"

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

  defp representative(items) do
    assert [%{representative: representative}] = Stories.cluster(Enum.shuffle(items))
    representative.id
  end

  # User story:
  # As the operator and the agent who read a story by its representative,
  # I want the member of the best tier that the server saw first to stand
  # for the story,
  # so that a publication time a later item claims never changes a story's
  # title, link or date (N-19).
  #
  # Acceptance criteria:
  # - Within a tier the member first seen is the representative, though a
  #   member seen later claims an earlier publication.
  # - The tier still comes first: a primary member seen last represents a
  #   story of secondary members.
  # - Among members of one first sight the earliest claim decides, then the
  #   smaller link.
  describe "cluster/2" do
    test "within a tier the first sight decides, before the claim" do
      first = item(:first, :secondary, 10, 10)
      claims_earlier = item(:claims_earlier, :secondary, -50, 11)

      assert representative([first, claims_earlier]) == :first
    end

    test "the tier comes first, and one first sight is ordered by claim and link" do
      secondary = item(:secondary, :secondary, 0, 1)
      primary = item(:primary, :primary, 3, 3)
      assert representative([secondary, primary]) == :primary

      later_claim = item(:a, :secondary, 5, 6)
      earlier_claim = item(:b, :secondary, 4, 6)
      assert representative([later_claim, earlier_claim]) == :b

      same_claim = item(:c, :secondary, 4, 6)
      assert representative([earlier_claim, same_claim]) == :b
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

  defp aggregated(title, link, published, source) do
    %Parsed{title: title, link: link, published_at: published, source_domain: source}
  end

  # User story:
  # As the operator who keeps a story in the research log,
  # I want a story other sources reported to keep its title, its link and
  # its date when one more feed's item joins it with an earlier claimed
  # date,
  # so that the entry written from the story names the source the server
  # saw first and the day that source stated (N-19).
  #
  # Acceptance criteria:
  # - A story of two items of one feed, joined by an item of another feed
  #   that is first seen later and claims a publication 71 hours earlier,
  #   keeps its representative: the list answers the same title and link,
  #   and the entry's proposal the same `source_url` and `as_of`.
  describe "a stored story" do
    test "keeps its representative when a later item claims an earlier date" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      hours_ago = fn hours -> DateTime.add(now, -hours * 3600, :second) end

      wire = "wire.representative-test.example.org"
      press = "press.representative-test.example.org"
      {:ok, _} = Sources.put_source(Actor.owner_ui(), wire, :secondary)
      {:ok, _} = Sources.put_source(Actor.owner_ui(), press, :secondary)

      security = watched!("Reprowind Harbour Logistics AG", "Reprowind Harbour")
      first_title = "Reprowind Harbour raises its guidance for the fiscal year"
      later_title = "Reprowind Harbour cuts its guidance for the fiscal year"

      first_feed = feed!(%{class: "aggregator", url: "https://search.example.com/rss-rep-1"})
      later_feed = feed!(%{class: "aggregator", url: "https://feeds.example.net/rss-rep-2"})

      assert {:ok, %{stored: 2}} =
               Ingest.ingest(
                 first_feed,
                 [
                   aggregated(
                     first_title,
                     "https://search.example.com/r?u=rep-a1",
                     hours_ago.(1),
                     wire
                   ),
                   aggregated(
                     first_title,
                     "https://search.example.com/r?u=rep-a2",
                     hours_ago.(1),
                     press
                   )
                 ],
                 DateTime.add(now, -1800, :second)
               )

      [before] = Repo.all(from(c in Cluster, where: c.security_id == ^security.id))
      kept = Repo.get!(Item, before.representative_item_id)
      assert kept.title == first_title

      assert {:ok, %{stored: 1}} =
               Ingest.ingest(
                 later_feed,
                 [
                   aggregated(
                     later_title,
                     "https://feeds.example.net/rep-x1",
                     hours_ago.(72),
                     wire
                   )
                 ],
                 now
               )

      [story] = Repo.all(from(c in Cluster, where: c.security_id == ^security.id))
      assert story.id == before.id
      assert story.member_count == 3
      assert story.representative_item_id == kept.id

      assert {:ok, %{rows: [row]}} =
               Reads.list({:security, security.id}, limit: 20, title_max: 160)

      assert row.title == first_title

      assert {:ok, proposal} = Promotion.proposal(story.id, security.id)
      assert proposal["headline"] == first_title
      assert proposal["source_url"] == kept.canonical_url
      assert proposal["as_of"] == Clock.local_date(hours_ago.(1))
    end
  end
end
