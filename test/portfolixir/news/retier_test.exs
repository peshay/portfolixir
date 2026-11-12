defmodule Portfolixir.News.RetierTest do
  # ADR-0056 E1 (amendment of 2026-11-12; Sprint 29, N1, #1444): a write to
  # `news_sources` that changes a row's tier re-rates, in its transaction,
  # the stored items that are not promoted and that the row now decides.
  # Risk tier STORED DATA: an item's tier becomes a lasting
  # `source_quality` once it is promoted (§3, D6), so every assertion here
  # names the exact tier, story and count. The order tests (a fetch and a
  # promotion racing a rating) are on two real connections in
  # `Portfolixir.LockRace.NewsRetierOrderTest`.
  #
  # Synthetic names and hosts only; every rated domain is this module's own
  # (`retier-<n>.example.org`), so no async module holds its row.
  use Portfolixir.DataCase, async: true

  import Ecto.Query, only: [from: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Knowledge.SecurityNote
  alias Portfolixir.News
  alias Portfolixir.News.Cluster
  alias Portfolixir.News.Item
  alias Portfolixir.News.Source
  alias Portfolixir.News.Sources
  alias Portfolixir.News.Stories
  alias Portfolixir.NewsFixtures
  alias Portfolixir.Repo

  @agent Actor.api_token_rw("synthetic-agent")
  @seeder Actor.system_job("synthetic-seed")

  defp domain, do: "retier-#{System.unique_integer([:positive])}.example.org"

  defp rate!(domain, tier, opts \\ []) do
    actor = if opts[:set_by] == :seed, do: @seeder, else: @agent
    {:ok, %Source{}} = Sources.put_source(actor, domain, tier, opts)
  end

  # One stored item of `class` from `domain`, with the tier its domain has
  # now, as the ingest stores it (`Sources.tier_for/2`): bound to
  # `opts[:security]` (issuer and aggregator) or `opts[:category]`
  # (thematic), or unassigned (aggregator without a security). Published
  # `opts[:at]` seconds after a fixed hour; titled `opts[:title]`.
  defp item!(class, domain, opts) do
    n = System.unique_integer([:positive])
    at = DateTime.add(~U[2026-11-10 09:00:00.000000Z], Keyword.get(opts, :at, 0), :second)
    title = Keyword.fetch!(opts, :title)
    link = "https://#{domain}/r-#{n}"

    {feed_attrs, binding} =
      case {class, opts[:security], opts[:category]} do
        {:issuer, security, nil} ->
          {%{class: "issuer", security_id: security.id},
           %{security_id: security.id, assignment: :assigned}}

        {:aggregator, nil, nil} ->
          {%{class: "aggregator"}, %{assignment: :unassigned}}

        {:aggregator, security, nil} ->
          {%{class: "aggregator"}, %{security_id: security.id, assignment: :assigned}}

        {:thematic, nil, category} ->
          {%{class: "thematic", category_id: category.id},
           %{category_id: category.id, assignment: :assigned}}
      end

    feed = NewsFixtures.feed!(feed_attrs)

    %Item{}
    |> Item.changeset(
      Stories.title_keys(title)
      |> Map.merge(binding)
      |> Map.merge(%{
        feed_id: feed.id,
        class: feed.class,
        first_seen_at: at,
        published_at_claimed: at,
        title: title,
        canonical_url: link,
        domain: domain,
        tier: Sources.tier_for(domain, feed.class),
        language: "en",
        content_hash: :sha256 |> :crypto.hash(link) |> Base.encode16(case: :lower),
        status: :new
      })
    )
    |> Repo.insert!()
  end

  defp cluster!(security) do
    {:ok, _} = Stories.recluster({:security, security.id}, "en", DateTime.utc_now(), full: true)
  end

  defp reload(%Item{id: id}), do: Repo.get(Item, id)
  defp story_of(%Item{} = item), do: Repo.get!(Cluster, reload(item).cluster_id)

  defp members(%Cluster{id: id}),
    do: Repo.all(from(i in Item, where: i.cluster_id == ^id, select: i.id, order_by: i.id))

  defp last_entry(domain) do
    %Source{id: id} = Repo.get_by!(Source, domain: domain)

    Journal.list_entries(resource_type: "news_source", resource_id: to_string(id))
    |> hd()
  end

  defp counts(entry),
    do: Map.take(entry.after, ~w(items_rerated items_removed items_kept_promoted))

  # User story (ADR-0056 E1; triage C2 of 2026-11-10):
  # As the operator who rates a source after its items were stored,
  # I want the stored items that rating decides to carry the tier the table
  # now gives them, and each story's representative chosen again from them,
  # so that no story, digest or later research entry keeps a tier my table
  # no longer allows.
  #
  # Acceptance criteria:
  # - A write that changes a row's tier gives every unpromoted stored item
  #   it decides (the domain or a subdomain, by the longest suffix)
  #   `Sources.tier(class, rated)`, B5's cap included: an aggregator or
  #   thematic item is at most secondary; an issuer item stays primary.
  # - Each touched story's representative and best tier are chosen again by
  #   the representative rule; the story keeps its id.
  # - A row more specific than the written one keeps its items.
  # - The journal entry of the write carries, beside the prior and the new
  #   tier, items_rerated, items_removed and items_kept_promoted.
  describe "a tier change re-rates the stored items the row decides" do
    test "a downgrade re-rates them and chooses the story's representative again" do
      security = NewsFixtures.security!()
      rated = domain()
      other = domain()
      rate!(rated, :secondary)
      title = "Northwind Harbour wins a port contract"

      # The unrated domain's item is the earlier; the rated one represents
      # the story while it is secondary.
      early = item!(:aggregator, other, security: security, title: title, at: 0)
      late = item!(:aggregator, rated, security: security, title: title, at: 60)
      issuer = item!(:issuer, rated, security: security, title: "Northwind Harbour AGM date")
      open = item!(:aggregator, "markets." <> rated, title: "A market wrap", at: 30)
      cluster!(security)

      story = story_of(late)
      assert members(story) == Enum.sort([early.id, late.id])
      assert {story.representative_item_id, story.best_tier} == {late.id, :secondary}

      assert {reload(late).tier, reload(open).tier, reload(issuer).tier} ==
               {:secondary, :secondary, :primary}

      assert {:ok, %Source{tier: :awareness, set_by: :hand}} =
               Sources.put_source(@agent, rated, :awareness)

      assert reload(late).tier == :awareness
      assert reload(open).tier == :awareness
      assert reload(early).tier == :awareness
      assert reload(issuer).tier == :primary

      story = Repo.get!(Cluster, story.id)
      assert members(story) == Enum.sort([early.id, late.id])
      assert {story.representative_item_id, story.best_tier} == {early.id, :awareness}

      entry = last_entry(rated)
      assert {entry.before["tier"], entry.after["tier"]} == {"secondary", "awareness"}

      assert counts(entry) == %{
               "items_rerated" => 2,
               "items_removed" => 0,
               "items_kept_promoted" => 0
             }
    end

    test "an upgrade re-rates them up to B5's cap, the first rating of a domain included" do
      security = NewsFixtures.security!()
      category = NewsFixtures.category!()
      unrated = domain()
      other = domain()
      title = "Northwind Harbour opens a terminal"

      early = item!(:aggregator, other, security: security, title: title, at: 0)
      late = item!(:aggregator, unrated, security: security, title: title, at: 60)
      issuer = item!(:issuer, unrated, security: security, title: "Northwind Harbour dividend")
      thematic = item!(:thematic, "www." <> unrated, category: category, title: "Water week")
      cluster!(security)
      {:ok, _} = Stories.recluster({:category, category.id}, "en", DateTime.utc_now(), full: true)

      story = story_of(late)
      assert {story.representative_item_id, story.best_tier} == {early.id, :awareness}

      assert {:ok, %Source{tier: :primary}} = Sources.put_source(@agent, unrated, :primary)

      # B5: an aggregator or a thematic item is at most secondary.
      assert reload(late).tier == :secondary
      assert reload(thematic).tier == :secondary
      assert reload(issuer).tier == :primary
      assert reload(early).tier == :awareness

      story = Repo.get!(Cluster, story.id)
      assert {story.representative_item_id, story.best_tier} == {late.id, :secondary}
      assert story_of(thematic).best_tier == :secondary

      entry = last_entry(unrated)
      assert {entry.before, entry.after["tier"]} == {nil, "primary"}

      assert counts(entry) == %{
               "items_rerated" => 2,
               "items_removed" => 0,
               "items_kept_promoted" => 0
             }
    end

    test "a more specific row elsewhere keeps its items; the result follows the rows" do
      parent = domain()
      child = "markets." <> parent
      rate!(child, :awareness)

      direct = item!(:aggregator, "news." <> parent, title: "Harbour wrap one")
      covered = item!(:aggregator, child, title: "Harbour wrap two")
      deeper = item!(:aggregator, "x." <> child, title: "Harbour wrap three")

      rate!(parent, :secondary)

      assert {reload(direct).tier, reload(covered).tier, reload(deeper).tier} ==
               {:secondary, :awareness, :awareness}

      assert counts(last_entry(parent))["items_rerated"] == 1

      # Two overlapping rows: each re-rates only what its own row decides.
      rate!(child, :secondary)
      rate!(parent, :awareness)

      assert {reload(direct).tier, reload(covered).tier, reload(deeper).tier} ==
               {:awareness, :secondary, :secondary}

      assert counts(last_entry(child))["items_rerated"] == 2
      assert counts(last_entry(parent))["items_rerated"] == 1
    end
  end

  # User story (ADR-0056 E1 rule 5; ADR-0044):
  # As the operator whose research log names a story's items,
  # I want an item that was promoted to keep the tier it was promoted at,
  # whatever its source is rated later, and the rating to say how many it
  # left,
  # so that the item and the append-only entry never disagree about the
  # moment it was written.
  #
  # Acceptance criteria:
  # - A downgrade and a block leave a promoted item's tier, status and
  #   story as they are, and the note's source_quality with them.
  # - Each write counts it in items_kept_promoted, and neither re-rates nor
  #   removes it.
  describe "a promoted item keeps its tier" do
    test "a downgrade and a block leave it, and count it" do
      security = NewsFixtures.security!()
      rated = domain()
      rate!(rated, :secondary)

      member = item!(:aggregator, rated, security: security, title: "Northwind wins a tender")
      cluster!(security)
      story = story_of(member)

      {:ok, %SecurityNote{source_quality: :unverified} = note} =
        News.append_note_from_story(
          @agent,
          %{"security_id" => security.id, "author" => "agent", "body" => "Kept."},
          story.id
        )

      assert reload(member).status == :promoted

      for tier <- [:awareness, :blocked] do
        assert {:ok, %Source{tier: ^tier}} = Sources.put_source(@agent, rated, tier)

        assert %Item{tier: :secondary, status: :promoted, note_ids: [note_id]} = reload(member)
        assert note_id == note.id
        assert story_of(member).id == story.id

        assert counts(last_entry(rated)) == %{
                 "items_rerated" => 0,
                 "items_removed" => 0,
                 "items_kept_promoted" => 1
               }
      end

      assert Repo.get!(SecurityNote, note.id).source_quality == :unverified
    end
  end

  # User story (ADR-0056 E1 "Which writes"; Sprint 29 plan D-7):
  # As the operator who corrected a source by hand,
  # I want a later seed of the same domain to change nothing, stored items
  # included, while a seed onto a domain nobody rated by hand re-rates as a
  # hand write does,
  # so that a seed never undoes my correction through the items, and a
  # changed default leaves no frozen tier behind.
  #
  # Acceptance criteria:
  # - A seed write onto a hand row answers {:kept, row}, journals nothing
  #   and leaves every stored item's tier as it is.
  # - A seed write onto a seed row that changes its tier re-rates, journaled
  #   under the seed's actor with its counts.
  # - A write that changes the row but not its tier (a hand write of the
  #   seed's tier) re-rates nothing and counts zero.
  describe "which writes re-rate" do
    test "a seed onto a hand row is a no-op; onto a seed row it re-rates" do
      by_hand = domain()
      seeded = domain()
      rate!(by_hand, :secondary)
      rate!(seeded, :secondary, set_by: :seed)

      hand_item = item!(:aggregator, by_hand, title: "Harbour wrap by hand")
      seed_item = item!(:aggregator, seeded, title: "Harbour wrap seeded")
      entries_before = length(Journal.list_entries(resource_type: "news_source"))

      assert {:kept, %Source{tier: :secondary, set_by: :hand}} =
               Sources.put_source(@seeder, by_hand, :blocked, set_by: :seed)

      assert %Item{tier: :secondary} = reload(hand_item)
      assert length(Journal.list_entries(resource_type: "news_source")) == entries_before

      assert {:ok, %Source{tier: :awareness, set_by: :seed}} =
               Sources.put_source(@seeder, seeded, :awareness, set_by: :seed)

      assert reload(seed_item).tier == :awareness
      entry = last_entry(seeded)
      assert entry.actor_label == "synthetic-seed"
      assert counts(entry)["items_rerated"] == 1

      # The hand write of the seed's tier changes set_by only.
      assert {:ok, %Source{tier: :awareness, set_by: :hand}} =
               Sources.put_source(@agent, seeded, :awareness)

      assert reload(seed_item).tier == :awareness

      assert counts(last_entry(seeded)) == %{
               "items_rerated" => 0,
               "items_removed" => 0,
               "items_kept_promoted" => 0
             }
    end
  end
end
