defmodule Portfolixir.Repo.Migrations.CreateNewsFeedDrops do
  @moduledoc """
  ADR-0056 §6, A3, closing act COR4: which items a feed's ingest dropped on
  a server day, so the day's drop counters count an item once a day and not
  once a fetch (one old filing a feed keeps listing read `old: 144`).

  One row per feed, SHA-256 of the item's canonical URL (lower-case hex,
  never the URL), reason (`cap`, `no_source`, `old`, `blocked`) and server
  day. The ingest adds to `news_feed_days` only the drops whose row is new.
  Retention prunes the rows with the day rows (30 days); a feed's removal
  deletes them with its day rows, and the database refuses a feed removed
  past them.

  A staging table like `news_feed_days` (B7): written by the fetcher's
  system job, not journaled, never guard-armed. Upgrade-safe: a new table.
  """
  use Ecto.Migration

  def change do
    create table(:news_feed_drops) do
      add(:feed_id, references(:news_feeds, on_delete: :restrict), null: false)
      add(:url_hash, :string, size: 64, null: false)
      add(:reason, :string, size: 16, null: false)
      add(:day, :date, null: false)
    end

    create(unique_index(:news_feed_drops, [:feed_id, :url_hash, :reason, :day]))
    create(index(:news_feed_drops, [:day]))

    create(
      constraint(:news_feed_drops, :news_feed_drops_url_hash_check,
        check: "url_hash ~ '^[0-9a-f]{64}$'"
      )
    )

    create(
      constraint(:news_feed_drops, :news_feed_drops_reason_check,
        check: "reason IN ('cap', 'no_source', 'old', 'blocked')"
      )
    )
  end
end
