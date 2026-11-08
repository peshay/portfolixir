defmodule Portfolixir.Repo.Migrations.AddScopeAtToNewsItems do
  @moduledoc """
  ADR-0056 amendment of 2026-11-08, C3: each news item carries `scope_at`,
  the server's time it entered its security's or category's scope — its
  first sight for an item bound by construction or matched at ingest, the
  time of the assignment for one matched later, re-matched, merged or left
  the only candidate. `since` in `news.list` and the digest reads it;
  retention keeps reading `first_seen_at` (B4).

  Upgrade-safe: every stored row takes its own `first_seen_at`, which the
  CHECK accepts (an item never enters a scope before it is first seen).
  """
  use Ecto.Migration

  def up do
    alter table(:news_items) do
      add(:scope_at, :utc_datetime_usec)
    end

    execute("UPDATE news_items SET scope_at = first_seen_at")
    execute("ALTER TABLE news_items ALTER COLUMN scope_at SET NOT NULL")

    create(
      constraint(:news_items, :news_items_scope_at_check, check: "scope_at >= first_seen_at")
    )

    create(index(:news_items, [:security_id, :scope_at]))
    create(index(:news_items, [:category_id, :scope_at]))
    create(index(:news_items, [:assignment, :scope_at]))
  end

  def down do
    drop(index(:news_items, [:assignment, :scope_at]))
    drop(index(:news_items, [:category_id, :scope_at]))
    drop(index(:news_items, [:security_id, :scope_at]))
    drop(constraint(:news_items, :news_items_scope_at_check))

    alter table(:news_items) do
      remove(:scope_at)
    end
  end
end
