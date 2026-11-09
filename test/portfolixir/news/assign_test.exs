defmodule Portfolixir.News.AssignTest do
  # ADR-0056 §9 (Sprint 28, N4): news.assign, an aggregator item assigned by
  # hand or given back to the matcher, journaled under its actor, its
  # stories re-clustered in its transaction; and the order lens of plan D-8
  # (carry-forward 5): an assignment racing the matcher and retention, the
  # other writer at the exact point through `Portfolixir.Interleave`.
  # Synthetic names and hosts only, no socket.
  use Portfolixir.DataCase, async: true

  import Ecto.Query
  import Portfolixir.NewsFixtures, only: [feed!: 1, label!: 2]
  import Portfolixir.WorldFixtures, only: [create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Derived.BlastRadius
  alias Portfolixir.Interleave
  alias Portfolixir.Journal
  alias Portfolixir.News
  alias Portfolixir.News.Cluster
  alias Portfolixir.News.Ingest
  alias Portfolixir.News.Item
  alias Portfolixir.News.Parser.Item, as: Parsed
  alias Portfolixir.News.Stories
  alias Portfolixir.Repo

  @agent Actor.api_token_rw("synthetic-agent")
  @title "Northwind Harbour reports third quarter results"

  defp watched!(name, token) do
    security = create_security!(name: name, ticker: nil, asset_class: "equity")

    {:ok, security} =
      Catalog.update_security(Actor.owner_ui(), security, %{
        news_watch: true,
        news_aliases: [%{token: token, context: [], case: "insensitive"}]
      })

    security
  end

  defp now, do: DateTime.utc_now()

  defp ingest!(feed, title, link, attrs \\ %{}) do
    item = struct!(Parsed, Map.merge(%{title: title, link: link}, attrs))
    {:ok, %{stored: 1}} = Ingest.ingest(feed, [item], now())
    Repo.get_by!(Item, canonical_url: link)
  end

  defp aggregator_item!(title) do
    n = System.unique_integer([:positive])
    feed = feed!(%{class: "aggregator", url: "https://search.example.com/rss-#{n}"})

    ingest!(feed, title, "https://search.example.com/r?u=#{n}", %{
      source_domain: "wire.example.com"
    })
  end

  defp issuer_item!(security, title) do
    n = System.unique_integer([:positive])

    ingest!(
      feed!(%{class: "issuer", security_id: security.id}),
      title,
      "https://ir.example.com/#{n}"
    )
  end

  defp reload(item), do: Repo.get!(Item, item.id)

  defp story(item), do: Repo.get!(Cluster, reload(item).cluster_id)

  defp entries, do: Journal.list_entries(resource_type: "news_item", order: :asc)

  setup do
    northwind = watched!("Northwind Harbour Logistics AG", "Northwind Harbour")
    harbourline = watched!("Harbourline Shipping AG", "Harbourline")
    %{northwind: northwind, harbourline: harbourline}
  end

  # User story (ADR-0056 §9):
  # As the operator whose agent finds an aggregator's item filed under the
  # wrong security, or under none,
  # I want to assign it by hand, or give it back to the matcher, in one
  # journaled write that re-clusters the stories it leaves and joins,
  # so that the item reads in the right security's stories at once and the
  # journal says who moved it.
  #
  # Acceptance criteria:
  # - An aggregator item assigned to a security leaves its story there and
  #   joins the target's stories in the same transaction: the old story is
  #   recounted, and the item joins the target's story of the same event.
  # - Assigning null gives the item back to the matcher's answer now: here
  #   the security its title names, back in that security's story.
  # - Each move is one journal entry, `news_item` update, under the actor,
  #   with the item before and after; assigning what the item already has
  #   writes and journals nothing.
  # - The item enters the target's scope at the assignment (`scope_at`, C3),
  #   never before its first sight.
  # - An issuer item, an unknown item and a security that does not exist
  #   are refused, and nothing is written.
  test "an item assigned by hand moves between stories in one journaled write", %{
    northwind: northwind,
    harbourline: harbourline
  } do
    release = issuer_item!(northwind, @title)
    other = issuer_item!(harbourline, @title)
    item = aggregator_item!(@title)

    assert %Item{assignment: :assigned, security_id: id} = reload(item)
    assert id == northwind.id
    assert story(item).id == story(release).id
    assert story(release).member_count == 2

    assert {:ok, moved} = News.assign_item(@agent, item.id, harbourline.id)
    assert %Item{assignment: :assigned, candidates: []} = moved
    assert moved.security_id == harbourline.id
    assert story(item).id == story(other).id
    assert story(other).member_count == 2
    assert story(release).member_count == 1
    assert DateTime.compare(moved.scope_at, item.scope_at) == :gt

    # The same assignment again changes nothing and records nothing.
    assert {:ok, _same} = News.assign_item(@agent, item.id, harbourline.id)
    assert [entry] = entries()
    assert {entry.actor_label, entry.operation} == {"synthetic-agent", :update}
    assert entry.resource_id == to_string(item.id)
    assert entry.before["security_id"] == northwind.id
    assert entry.after["security_id"] == harbourline.id
    # An item is read by no walk, quote, rate or rule: no derived value moves.
    assert BlastRadius.for_write("news_item", %Item{}) == []
    assert BlastRadius.securities_for_write("news_item", %Item{}) == []

    # Back to the matcher: the title names Northwind Harbour.
    assert {:ok, back} = News.assign_item(@agent, item.id, nil)
    assert back.security_id == northwind.id
    assert story(item).id == story(release).id
    assert story(release).member_count == 2
    assert story(other).member_count == 1
    assert length(entries()) == 2

    assert {:error, %{"news_id" => [message]}} =
             News.assign_item(@agent, release.id, harbourline.id)

    assert message =~ "issuer"
    assert {:error, %{"security_id" => [_]}} = News.assign_item(@agent, item.id, 2_000_000_000)
    assert {:error, :not_found} = News.assign_item(@agent, 2_000_000_000, harbourline.id)
    assert length(entries()) == 2
  end

  test "null gives an item the matcher's answer now: ambiguous, out of any story", %{
    northwind: northwind,
    harbourline: harbourline
  } do
    item = aggregator_item!("Northwind Harbour and Harbourline agree on a joint venture")
    assert %Item{assignment: :ambiguous, cluster_id: nil} = reload(item)

    {:ok, assigned} = News.assign_item(@agent, item.id, harbourline.id)
    assert %Item{assignment: :assigned, cluster_id: cluster_id} = assigned
    assert is_integer(cluster_id)

    {:ok, undone} = News.assign_item(@agent, item.id, nil)
    assert %Item{assignment: :ambiguous, cluster_id: nil, security_id: nil} = undone
    assert undone.candidates == Enum.sort([northwind.id, harbourline.id])
    refute Repo.get(Cluster, cluster_id)
  end

  # User story (ADR-0056 §7, §9): a label's suggestion is a proposal.
  # As the operator whose labeller suggests another security for a story,
  # I want the suggestion never to move an item by itself,
  # so that only news.assign assigns.
  #
  # Acceptance criteria:
  # - A label with suggested_security_id leaves every item where it was.
  test "a label's suggestion moves nothing", %{northwind: northwind, harbourline: harbourline} do
    item = aggregator_item!(@title)
    label!(reload(item).cluster_id, suggested_security_id: harbourline.id)
    assert reload(item).security_id == northwind.id
  end

  # User story (plan D-8 carry-forward 5, the order lens):
  # As the operator whose agent assigns an item while the matcher or
  # retention is at work on it,
  # I want the assignment to act on the item as it is when it holds the
  # item's lock, never on what it read before,
  # so that no story is left pointing at an item that moved, and no item is
  # written that retention has removed.
  #
  # Acceptance criteria:
  # - The matcher assigning the item (and folding it into a story) between
  #   the assignment's first read and its lock: the assignment takes it out
  #   of that story and into the target's; no story of the matcher's
  #   security holds it.
  # - Retention removing the item at that point: the assignment answers
  #   not found and journals nothing.
  test "an assignment racing the matcher acts on the item the matcher left", %{
    northwind: northwind,
    harbourline: harbourline
  } do
    issuer_item!(harbourline, @title)
    item = aggregator_item!("Northwind Harbur reports third quarter results")
    assert %Item{assignment: :unassigned, cluster_id: nil} = reload(item)

    first_read? = fn %{query: query, params: params} ->
      query =~ ~s(FROM "news_items") and params == [item.id]
    end

    # The matcher, meanwhile, learns the misspelt name: the identity
    # change's re-match files the item under Northwind and into a story.
    matcher = fn ->
      {:ok, _} =
        Catalog.update_security(Actor.owner_ui(), northwind, %{
          news_aliases: [
            %{token: "Northwind Harbour", context: [], case: "insensitive"},
            %{token: "Northwind Harbur", context: [], case: "insensitive"}
          ]
        })

      Repo.get!(Item, item.id)
    end

    {result, matched} =
      Interleave.run(first_read?, matcher, fn ->
        News.assign_item(@agent, item.id, harbourline.id)
      end)

    assert %Item{security_id: matched_id, cluster_id: story_id} = matched
    assert matched_id == northwind.id and is_integer(story_id)

    assert {:ok, %Item{security_id: target}} = result
    assert target == harbourline.id
    assert reload(item).security_id == harbourline.id
    assert story(item).security_id == harbourline.id

    refute Repo.exists?(
             from(c in Cluster,
               join: i in Item,
               on: i.cluster_id == c.id,
               where: c.security_id == ^northwind.id and i.id == ^item.id
             )
           )
  end

  test "an assignment racing retention answers not found", %{
    northwind: northwind,
    harbourline: harbourline
  } do
    item = aggregator_item!(@title)
    assert reload(item).security_id == northwind.id

    first_read? = fn %{query: query, params: params} ->
      query =~ ~s(FROM "news_items") and params == [item.id]
    end

    retention = fn ->
      Stories.remove(
        {:security, northwind.id},
        "en",
        from(i in Item, where: i.id == ^item.id),
        now()
      )
    end

    {result, {:ok, %{items: 1}}} =
      Interleave.run(first_read?, retention, fn ->
        News.assign_item(@agent, item.id, harbourline.id)
      end)

    # The removal ran inside the assignment's transaction (Interleave), so
    # the assignment's rollback takes it back: only the answer is read.
    assert result == {:error, :not_found}
    assert entries() == []
  end
end
