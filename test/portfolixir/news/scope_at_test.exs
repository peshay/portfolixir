defmodule Portfolixir.News.ScopeAtTest do
  # ADR-0056 amendment of 2026-11-08, C3 (Sprint 27 closing act, COR3):
  # `since` reads the moment an item entered its scope. Synthetic names and
  # hosts only, no socket.
  use Portfolixir.DataCase, async: true

  import Portfolixir.NewsFixtures, only: [feed!: 1, security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.News.Ingest
  alias Portfolixir.News.Item
  alias Portfolixir.News.Parser.Item, as: Parsed
  alias Portfolixir.News.Reads
  alias Portfolixir.Repo

  defp parsed(title, link),
    do: %Parsed{title: title, link: link, source_domain: "wire.example.com"}

  # User story (ADR-0056 amendment of 2026-11-08, C3; B4):
  # As the agent that reads news with `since` and passes `as_of` on,
  # I want an aggregator item that a re-match assigns after its first
  # sight to read as new to its security from that assignment on,
  # so that "overlap, never loss" holds for an item matched late.
  #
  # Acceptance criteria:
  # - An item bound at ingest enters its scope at its first sight.
  # - An unassigned item assigned by the 7-day re-match after an alias
  #   change carries `scope_at`, the time of the assignment, and keeps its
  #   `first_seen_at` (retention's clock).
  # - The database refuses a `scope_at` before the first sight.
  # - `news.list` with a `since` between the first sight and the
  #   assignment answers its story, and the digest with that `since`
  #   counts it.
  test "an item re-matched after an alias change reads as new from its assignment" do
    security = security!("Epsilon Rail AG")
    {:ok, security} = Catalog.update_security(Actor.owner_ui(), security, %{news_watch: true})
    aggregator = feed!(%{class: "aggregator"})
    issuer = feed!(%{class: "issuer", security_id: security.id})

    first_sight = DateTime.add(DateTime.utc_now(), -2 * 3600)

    {:ok, %{stored: 1}} =
      Ingest.ingest(
        aggregator,
        [parsed("Kestrel line wins tender", "https://agg.example.com/a/1")],
        first_sight
      )

    {:ok, %{stored: 1}} =
      Ingest.ingest(
        issuer,
        [parsed("Epsilon Rail opens a depot", "https://ir.example.com/1")],
        first_sight
      )

    bound = Repo.get_by!(Item, canonical_url: "https://ir.example.com/1")
    assert bound.scope_at == bound.first_seen_at

    # The reader's run half an hour later found nothing of the item's; its
    # next `since`.
    since = DateTime.add(first_sight, 1800)

    {:ok, _} =
      Catalog.update_security(Actor.owner_ui(), security, %{
        news_aliases: [%{token: "Kestrel", context: [], case: "sensitive"}]
      })

    item = Repo.get_by!(Item, canonical_url: "https://agg.example.com/a/1")
    assert item.assignment == :assigned and item.security_id == security.id
    assert item.first_seen_at == first_sight
    assert DateTime.compare(item.scope_at, since) == :gt

    {:ok, page} = Reads.list({:security, security.id}, limit: 20, since: since)
    assert [%{title: "Kestrel line wins tender"}] = page.rows

    digest = Reads.digest([security.id], since, true, 12)
    assert [%{count: 1, top: %{title: "Kestrel line wins tender"}}] = digest.rows

    # The database refuses a scope entered before the first sight.
    assert_raise Postgrex.Error, ~r/news_items_scope_at_check/, fn ->
      Repo.update_all(from(i in Item, where: i.id == ^item.id),
        set: [scope_at: DateTime.add(first_sight, -1)]
      )
    end
  end
end
