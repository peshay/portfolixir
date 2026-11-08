defmodule Portfolixir.Repo.Migrations.CreateNewsItemTombstones do
  @moduledoc """
  ADR-0056 B4, closing act COR2: what retention removed, so a feed that
  keeps listing a dateless item does not refill it as new.

  One row per feed and removed item: the feed, a SHA-256 of the item's
  canonical URL in lower-case hex (never the URL: what retention removed is
  not kept), and the server's time of the removal. Retention writes a row
  for each item it removes that still has a feed and prunes the rows 90
  days after their removal; the ingest drops an item whose URL a row of its
  feed names, counted `dropped_old`. A feed's removal deletes its rows, as
  it deletes its day rows (`Portfolixir.News.delete_feed/2`); the database
  refuses a feed removed past them.

  A staging table like `news_items` (B7): written by the registered system
  jobs, not journaled, never guard-armed. Upgrade-safe: a new table.
  """
  use Ecto.Migration

  def change do
    create table(:news_item_tombstones) do
      add(:feed_id, references(:news_feeds, on_delete: :restrict), null: false)
      add(:url_hash, :string, size: 64, null: false)
      add(:removed_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:news_item_tombstones, [:feed_id, :url_hash]))
    create(index(:news_item_tombstones, [:removed_at]))

    create(
      constraint(:news_item_tombstones, :news_item_tombstones_url_hash_check,
        check: "url_hash ~ '^[0-9a-f]{64}$'"
      )
    )
  end
end
