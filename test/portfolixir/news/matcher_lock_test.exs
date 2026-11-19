defmodule Portfolixir.News.MatcherLockTest do
  # ADR-0056 §2 (Sprint 27 closing act, ORD5): the matcher compiles the
  # universe after it has locked the items, under the advisory lock the
  # re-match shares, so an alias change's re-match is never overwritten by
  # a match against the aliases before it. The other writer runs at the
  # exact point through `Portfolixir.Interleave`. Synthetic names only.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Interleave
  alias Portfolixir.News
  alias Portfolixir.News.Feed
  alias Portfolixir.News.Item
  alias Portfolixir.News.Stories
  alias Portfolixir.Repo
  alias Portfolixir.WorldFixtures

  @title "Northwind Harbour reports third quarter 2026 results"

  defp alias_of(token), do: %{token: token, context: [], case: "insensitive"}

  # User story (ADR-0056 §2):
  # As the operator who adds an alias that makes a headline ambiguous,
  # I want the ingest's match that was already running not to write an
  # assignment read from the aliases before my change over my re-match,
  # so that the item reads ambiguous, as the aliases now say.
  #
  # Acceptance criteria:
  # - An alias change committed after the matcher has read the universe
  #   and before it writes leaves the item `ambiguous` with both candidates.
  test "an alias change between the matcher's lock and its write is not overwritten" do
    owner = Actor.owner_ui()

    northwind =
      WorldFixtures.create_security!(
        name: "Northwind Harbour AG",
        ticker: nil,
        asset_class: "equity"
      )

    harbourline =
      WorldFixtures.create_security!(name: "Harbourline AG", ticker: nil, asset_class: "equity")

    {:ok, northwind} =
      Catalog.update_security(owner, northwind, %{
        news_watch: true,
        news_aliases: [alias_of("Northwind Harbour")]
      })

    {:ok, harbourline} =
      Catalog.update_security(owner, harbourline, %{news_watch: true, news_aliases: []})

    Repo.query!("SELECT set_config('portfolixir.journal_actor', 'synthetic-fixture', true)")

    aggregator =
      %Feed{}
      |> Feed.changeset(%{
        class: "aggregator",
        url: "https://feeds.example.com/agg",
        language: "en"
      })
      |> Repo.insert!()

    item =
      %Item{}
      |> Item.changeset(
        Map.merge(Stories.title_keys(@title), %{
          feed_id: aggregator.id,
          class: :aggregator,
          assignment: :unassigned,
          first_seen_at: DateTime.utc_now(),
          title: @title,
          canonical_url: "https://press.example.com/1",
          domain: "press.example.com",
          tier: :secondary,
          language: "en",
          content_hash: String.duplicate("a", 64)
        })
      )
      |> Repo.insert!()

    # #1457 (Sprint 30, K2): the matcher holds the securities it matches
    # before it locks the items, off a first, unlocked read of the items and
    # the universe, and runs each attempt in a savepoint, which it rolls
    # back to when the universe compiled under the items' locks names a
    # security it does not hold. An alias change interleaved here, on the
    # matcher's own connection, inside that savepoint would be rolled back
    # with it, which a commit on another connection never is; so it runs
    # right after the first read of the universe, the earliest point the
    # change can miss: the first step holds only Northwind, and the match
    # under the items' locks, which reads the change, runs again holding
    # Harbourline too. The race on two connections is
    # `test/portfolixir/lock_race/news_matcher_order_test.exs`.
    first_universe_read? = fn metadata ->
      query = to_string(metadata[:query])
      metadata[:source] == "securities" and not (query =~ "FOR ")
    end

    {{:ok, _counts}, {:ok, _}} =
      Interleave.run(
        first_universe_read?,
        fn ->
          Catalog.update_security(owner, harbourline, %{
            news_aliases: [alias_of("Northwind Harbour")]
          })
        end,
        fn -> News.assign_aggregator_items([item.id]) end
      )

    stored = Repo.reload!(item)
    assert stored.assignment == :ambiguous
    assert stored.candidates == Enum.sort([northwind.id, harbourline.id])
  end
end
