defmodule Portfolixir.LockRace.NewsMergeThirdPathTest do
  # Sprint 30 closing act, the edge-case and order lens: a third path into
  # the security merge's rows (#1457's rule, "every news writer takes the
  # securities before any news row"; `Portfolixir.LockTable`, row 13). A
  # merge holds both securities `FOR UPDATE` and then UPDATEs the source's
  # items and stories (`News.reassign_security/3`). Finding 2: a promotion
  # held its story's members `FOR UPDATE` and then INSERTed the note, whose
  # foreign key asked the security `FOR KEY SHARE`; it now takes the
  # security first. A deadlock fails the race.
  #
  # async: false -- the races share a scratch database. Every name and host
  # is synthetic.
  use ExUnit.Case, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Lifecycle
  alias Portfolixir.LockRace
  alias Portfolixir.News
  alias Portfolixir.News.Cluster
  alias Portfolixir.News.Item
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

  defp feed!(attrs) do
    {:ok, feed} = Repo.transaction(fn -> NewsFixtures.feed!(attrs) end)
    feed
  end

  defp story!(security) do
    feed = feed!(%{class: "aggregator"})
    domain = "lorder-#{System.unique_integer([:positive])}.example"
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
    Repo.get!(Cluster, Repo.get!(Item, item.id).cluster_id)
  end

  defp world(name) do
    source = WorldFixtures.create_security!(name: "#{name} AG", ticker: nil)
    target = WorldFixtures.create_security!(name: "#{name} AG", ticker: nil)
    story = story!(source)
    {:ok, preview} = Lifecycle.preview_security_merge(source.id, target.id)
    %{source: source, target: target, story: story, digest: preview.plan_digest}
  end

  defp merge(w) do
    Lifecycle.merge_security(agent(), w.source.id, w.target.id, %{
      plan_digest: w.digest,
      collapse_key_equal: false
    })
  end

  defp securities_update?(%{query: query}) when is_binary(query),
    do: query =~ ~s(FROM "securities") and query =~ "FOR UPDATE"

  defp securities_update?(_metadata), do: false

  defp item_lock?(%{query: query}) when is_binary(query),
    do: query =~ ~s(FROM "news_items") and query =~ "FOR UPDATE"

  defp item_lock?(_metadata), do: false

  test "a promotion holding its story's members, then a merge of the story's security",
       %{db: db} do
    w = world("Promotion Merge Quay")

    {promoted, merged} =
      LockRace.race!(
        db,
        {fn ->
           News.append_note_from_story(
             agent(),
             %{"security_id" => w.source.id, "author" => "agent", "body" => "Synthetic."},
             w.story.id
           )
         end, &item_lock?/1},
        fn -> merge(w) end
      )

    # The promotion commits first; the merge, released, then finds a note on
    # its source and refuses on its `research_notes` guard -- never a
    # deadlock.
    assert {:ok, _note} = promoted
    assert {:error, {:refused, guards}} = merged
    assert :research_notes in for(%{passed: false, code: code} <- guards, do: code)
  end

  test "a merge holding the securities, then a promotion of the source's story", %{db: db} do
    w = world("Merge Promotion Quay")

    {merged, promoted} =
      LockRace.race!(
        db,
        {fn -> merge(w) end, &securities_update?/1},
        fn ->
          News.append_note_from_story(
            agent(),
            %{"security_id" => w.source.id, "author" => "agent", "body" => "Synthetic."},
            w.story.id
          )
        end
      )

    # The promotion waits at the security, holding nothing; the merge moves
    # the story to the target, and the promotion, released, refuses it as
    # another security's story.
    assert {:ok, _record, :applied} = merged
    assert {:error, %{"cluster_id" => [_refused]}} = promoted
  end
end
