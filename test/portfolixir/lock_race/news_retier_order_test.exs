defmodule Portfolixir.LockRace.NewsRetierOrderTest do
  # ADR-0056 E1 "Order" (Sprint 29, N1, #1444; the Sprint 26
  # retrospective's first carry-forward): a rating that re-rates stored
  # items, raced on two real connections by the lock-order harness (#996)
  # against a fetch storing items, a promotion of a story, an assignment by
  # hand and an overlapping rating. A deadlock, a writer that never waits
  # and a writer that raises each fail the race. The locks are rows 22 and
  # 23 of `Portfolixir.LockTable`.
  #
  # async: false -- the races share a scratch database and the barrier's
  # limits. Every name and host is synthetic, every rated domain this
  # module's own.
  use ExUnit.Case, async: false

  import Ecto.Query, only: [from: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Knowledge.SecurityNote
  alias Portfolixir.LockRace
  alias Portfolixir.News
  alias Portfolixir.News.Cluster
  alias Portfolixir.News.Ingest
  alias Portfolixir.News.Item
  alias Portfolixir.News.Parser.Item, as: Parsed
  alias Portfolixir.News.Source
  alias Portfolixir.News.Sources
  alias Portfolixir.News.Stories
  alias Portfolixir.NewsFixtures
  alias Portfolixir.Repo
  alias Portfolixir.WorldFixtures

  @moduletag :lock_race

  setup_all do
    %{db: LockRace.database!()}
  end

  setup %{db: db} do
    Repo.put_dynamic_repo(db.repo)
    :ok
  end

  defp agent, do: Actor.api_token_rw("synthetic-agent")

  # Two labels: the domain is its only suffix, so a rating takes one tier
  # lock and a fetch of it one (`Sources`), and the pause holds the lock
  # the other writer asks for.
  defp domain, do: "order-#{System.unique_integer([:positive])}.example"

  defp rate!(domain, tier), do: {:ok, %Source{}} = Sources.put_source(agent(), domain, tier)

  defp security!(name),
    do: WorldFixtures.create_security!(name: name, ticker: nil, asset_class: "equity")

  # Outside the sandbox the fixture's transaction-local actor needs a
  # transaction of its own.
  defp feed!(attrs) do
    {:ok, feed} = Repo.transaction(fn -> NewsFixtures.feed!(attrs) end)
    feed
  end

  # An aggregator item of `domain` that names no security: unassigned.
  defp parsed(domain) do
    n = System.unique_integer([:positive])

    %Parsed{
      title: "A synthetic market wrap #{n}",
      link: "https://search.example.com/r?u=order-#{n}",
      source_domain: domain
    }
  end

  # A story of `security` of one aggregator item of `domain`, stored with
  # the tier its domain has now, as the ingest stores it.
  defp story!(security, domain) do
    feed = feed!(%{class: "aggregator"})
    title = "Synthetic Quay wins a harbour tender"
    link = "https://#{domain}/r-#{System.unique_integer([:positive])}"
    at = DateTime.add(DateTime.utc_now(), -3600, :second)

    item =
      %Item{}
      |> Item.changeset(
        Map.merge(Stories.title_keys(title), %{
          feed_id: feed.id,
          class: :aggregator,
          security_id: security.id,
          assignment: :assigned,
          first_seen_at: at,
          title: title,
          canonical_url: link,
          domain: domain,
          tier: Sources.tier_for(domain, :aggregator),
          language: "en",
          content_hash: :sha256 |> :crypto.hash(link) |> Base.encode16(case: :lower)
        })
      )
      |> Repo.insert!()

    {:ok, _} = Stories.recluster({:security, security.id}, "en", DateTime.utc_now())
    {Repo.get!(Item, item.id), Repo.get!(Cluster, Repo.get!(Item, item.id).cluster_id)}
  end

  defp promote(security, story) do
    News.append_note_from_story(
      agent(),
      %{"security_id" => security.id, "author" => "agent", "body" => "Synthetic."},
      story.id
    )
  end

  defp counts(domain) do
    %Source{id: id} = Repo.get_by!(Source, domain: domain)

    [entry | _] = Journal.list_entries(resource_type: "news_source", resource_id: to_string(id))
    Map.take(entry.after, ~w(items_rerated items_removed items_kept_promoted))
  end

  # The rating's own tier lock, and the ingest's (`Sources`, rows 22, 23).
  defp rating_lock?(%{query: query}) when is_binary(query), do: query =~ "news tier: rating"
  defp rating_lock?(_metadata), do: false

  defp ingest_lock?(%{query: query}) when is_binary(query), do: query =~ "news tier: ingest"
  defp ingest_lock?(_metadata), do: false

  defp item_lock?(%{query: query}) when is_binary(query),
    do: query =~ ~s(FROM "news_items") and query =~ "FOR UPDATE"

  defp item_lock?(_metadata), do: false

  # Counts the rating's tier locks taken from now on, on any connection;
  # answers a function that reads the count and stops counting.
  defp count_rating_locks do
    test = self()
    handler = "retier-attempts-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler,
        [:portfolixir, :repo, :query],
        fn _event, _measurements, metadata, _config ->
          if rating_lock?(metadata), do: send(test, {:rating_lock, handler})
        end,
        nil
      )

    fn ->
      :telemetry.detach(handler)
      count_messages({:rating_lock, handler}, 0)
    end
  end

  defp count_messages(message, count) do
    receive do
      ^message -> count_messages(message, count + 1)
    after
      0 -> count
    end
  end

  defp matcher_lock?(%{query: query}) when is_binary(query),
    do: String.contains?(query, "/* news matcher */")

  defp matcher_lock?(_metadata), do: false

  # User story (ADR-0056 E1, "a fetch storing items while a rating is
  # written"):
  # As the operator who rates a domain while the fetcher stores its items,
  # I want each item stored either before the rating, and re-rated by it,
  # or after it, reading the new tier,
  # so that no item is stored with the old tier once the rating committed.
  #
  # Acceptance criteria:
  # - A rating holding its tier lock: the fetch waits for it, and stores
  #   the item with the new tier.
  # - A fetch holding its tier lock: the rating waits for it, and re-rates
  #   the item the fetch stored, counting it.
  describe "a fetch and a rating" do
    test "a rating holding its lock: the fetch waits, then reads the new tier", %{db: db} do
      rated = domain()
      rate!(rated, :secondary)
      feed = feed!(%{class: "aggregator"})
      item = parsed(rated)

      {rating, fetched} =
        LockRace.race!(
          db,
          {fn -> Sources.put_source(agent(), rated, :awareness) end, &rating_lock?/1},
          fn -> Ingest.ingest(feed, [item], DateTime.utc_now()) end
        )

      assert {:ok, %Source{tier: :awareness}} = rating
      assert {:ok, %{stored: 1}} = fetched
      assert %Item{tier: :awareness} = Repo.get_by!(Item, feed_id: feed.id)
      assert counts(rated)["items_rerated"] == 0
    end

    test "a fetch holding its lock: the rating waits, then re-rates what it stored",
         %{db: db} do
      rated = domain()
      rate!(rated, :secondary)
      feed = feed!(%{class: "aggregator"})
      item = parsed(rated)

      {fetched, rating} =
        LockRace.race!(
          db,
          {fn -> Ingest.ingest(feed, [item], DateTime.utc_now()) end, &ingest_lock?/1},
          fn -> Sources.put_source(agent(), rated, :awareness) end
        )

      assert {:ok, %{stored: 1}} = fetched
      assert {:ok, %Source{tier: :awareness}} = rating
      assert %Item{tier: :awareness} = Repo.get_by!(Item, feed_id: feed.id)
      assert counts(rated)["items_rerated"] == 1
    end
  end

  # User story (ADR-0056 E1, "a promotion while a rating is written"):
  # As the operator whose agent keeps a story while I rate its source,
  # I want whichever write commits first to win,
  # so that a member promoted first keeps its tier and the entry's
  # source_quality, and a member re-rated first is promoted at its new tier.
  #
  # Acceptance criteria:
  # - A promotion holding the story's scope lock: the rating waits, leaves
  #   the promoted member's tier, and counts it as kept; the entry says
  #   unverified (one secondary domain).
  # - A rating holding the member's lock: the promotion waits, and the
  #   entry says awareness, the member's new tier.
  describe "a promotion and a rating" do
    test "a promotion first: the member keeps its tier", %{db: db} do
      security = security!("Promotion First Quay AG")
      rated = domain()
      rate!(rated, :secondary)
      {member, story} = story!(security, rated)

      {promoted, rating} =
        LockRace.race!(
          db,
          {fn -> promote(security, story) end, &LockRace.lock?/1},
          fn -> Sources.put_source(agent(), rated, :awareness) end
        )

      assert {:ok, %SecurityNote{source_quality: :unverified}} = promoted
      assert {:ok, %Source{tier: :awareness}} = rating
      assert %Item{tier: :secondary, status: :promoted} = Repo.get!(Item, member.id)

      assert counts(rated) == %{
               "items_rerated" => 0,
               "items_removed" => 0,
               "items_kept_promoted" => 1
             }
    end

    test "a rating first: the member is promoted at its new tier", %{db: db} do
      security = security!("Rating First Quay AG")
      rated = domain()
      rate!(rated, :secondary)
      {member, story} = story!(security, rated)

      {rating, promoted} =
        LockRace.race!(
          db,
          {fn -> Sources.put_source(agent(), rated, :awareness) end, &item_lock?/1},
          fn -> promote(security, story) end
        )

      assert {:ok, %Source{tier: :awareness}} = rating
      assert {:ok, %SecurityNote{source_quality: :awareness}} = promoted
      assert %Item{tier: :awareness, status: :promoted} = Repo.get!(Item, member.id)
      assert counts(rated)["items_rerated"] == 1
      assert Repo.get!(Cluster, story.id).best_tier == :awareness
    end
  end

  # User story (ADR-0056 E1 with D4's lock order; the order lens):
  # As the operator whose agent assigns an item by hand while I rate its
  # source,
  # I want the rating to wait for the assignment and re-rate the item in
  # the story it was assigned to,
  # so that neither write fails and the story reads the new tier.
  #
  # Acceptance criteria:
  # - An assignment holding the matcher's lock: the rating waits, finds the
  #   item moved into a scope it did not lock, starts again (its tier lock
  #   taken twice) and re-rates it there; the item's story carries the new
  #   tier.
  describe "an assignment and a rating" do
    test "an assignment first: the rating re-rates the item in its new story", %{db: db} do
      security = security!("Assigned Quay AG")
      rated = domain()
      rate!(rated, :secondary)
      feed = feed!(%{class: "aggregator"})
      {:ok, %{stored: 1}} = Ingest.ingest(feed, [parsed(rated)], DateTime.utc_now())
      item = Repo.get_by!(Item, feed_id: feed.id)
      assert item.assignment == :unassigned

      attempts = count_rating_locks()

      {assigned, rating} =
        LockRace.race!(
          db,
          {fn -> News.assign_item(agent(), item.id, security.id) end, &matcher_lock?/1},
          fn -> Sources.put_source(agent(), rated, :awareness) end
        )

      # The rating ran twice: the first attempt found the item moved.
      assert attempts.() == 2

      assert {:ok, %Item{assignment: :assigned}} = assigned
      assert {:ok, %Source{tier: :awareness}} = rating

      assert %Item{tier: :awareness, security_id: security_id, cluster_id: cluster_id} =
               Repo.get!(Item, item.id)

      assert security_id == security.id
      assert Repo.get!(Cluster, cluster_id).best_tier == :awareness
      assert counts(rated)["items_rerated"] == 1
    end
  end

  # User story (ADR-0056 E1, "two ratings of overlapping domains"):
  # As the operator who rates a domain and one of its subdomains at once,
  # I want each rating to re-rate only what its own row decides,
  # so that the result depends on the rows, not on which write came first.
  #
  # Acceptance criteria:
  # - A rating of the subdomain holding its locks: the parent's rating
  #   waits for it; the subdomain's items carry its tier, the parent's
  #   other items the parent's.
  describe "two overlapping ratings" do
    test "the subdomain's rating first: each row keeps its own items", %{db: db} do
      parent = domain()
      child = "markets." <> parent
      feed = feed!(%{class: "aggregator"})

      {:ok, %{stored: 2}} =
        Ingest.ingest(feed, [parsed(child), parsed(parent)], DateTime.utc_now())

      items =
        Map.new(Repo.all(from(i in Item, where: i.feed_id == ^feed.id, select: {i.domain, i.id})))

      {first, second} =
        LockRace.race!(
          db,
          {fn -> Sources.put_source(agent(), child, :secondary) end, &item_lock?/1},
          fn -> Sources.put_source(agent(), parent, :blocked) end
        )

      assert {:ok, %Source{tier: :secondary}} = first
      assert {:ok, %Source{tier: :blocked}} = second
      assert %Item{tier: :secondary} = Repo.get!(Item, Map.fetch!(items, child))
      assert Repo.get(Item, Map.fetch!(items, parent)) == nil
      assert counts(child)["items_rerated"] == 1
      assert counts(parent)["items_removed"] == 1
    end
  end
end
