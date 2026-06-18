defmodule Portfolixir.Repo.Migrations.CreateBucketsAndViews do
  @moduledoc """
  Buckets & views — tag-based wealth scoping data model (ADR-0018, FR-4).

  Buckets are overlapping tags on holdings (depots, cash accounts, and security
  positions). Assignment is depot-default + per-position override. Views are
  named, global `{include | :all, exclude}` filters over buckets (exclude wins).

  Journaling (ADR-0017): bucket and assignment writes are routed through
  `Portfolixir.Journal.record/3` by the `Portfolixir.Buckets` context (born
  actor-first). Only the root `buckets` table is guard-**armed** here: the
  assignment join tables FK-cascade from `securities_accounts` / `cash_accounts`
  / `securities`, which are still deleted through non-actor-first contexts
  (Portfolios is a later leaf-first arming slice, architecture amendment 1).
  Arming them now would make the guard reject those cascade deletes. View tables
  are never journaled (ADR-0018 §5), so they are never armed.
  """
  use Ecto.Migration

  def up do
    create table(:buckets) do
      add(:name, :string, null: false)
      add(:color, :string)
      timestamps()
    end

    create(unique_index(:buckets, [:name]))

    # Depot default bucket set (many-to-many). on_delete: delete_all from both
    # sides — a removed depot or bucket drops its links.
    create table(:securities_account_buckets) do
      add(:securities_account_id, references(:securities_accounts, on_delete: :delete_all),
        null: false
      )

      add(:bucket_id, references(:buckets, on_delete: :delete_all), null: false)
    end

    create(unique_index(:securities_account_buckets, [:securities_account_id, :bucket_id]))
    create(index(:securities_account_buckets, [:bucket_id]))

    # Cash-account bucket set (cash accounts are bucketable, ADR-0018).
    create table(:cash_account_buckets) do
      add(:cash_account_id, references(:cash_accounts, on_delete: :delete_all), null: false)
      add(:bucket_id, references(:buckets, on_delete: :delete_all), null: false)
    end

    create(unique_index(:cash_account_buckets, [:cash_account_id, :bucket_id]))
    create(index(:cash_account_buckets, [:bucket_id]))

    # Per-position override, keyed on (securities_account_id, security_id) because
    # holdings are derived and never stored (ADR-0004). A single row with a NULL
    # bucket_id is the "explicit-empty" marker (deliberately no buckets), distinct
    # from "inherit" (no rows at all). Rows with a bucket_id are the explicit set.
    create table(:position_bucket_overrides) do
      add(:securities_account_id, references(:securities_accounts, on_delete: :delete_all),
        null: false
      )

      add(:security_id, references(:securities, on_delete: :delete_all), null: false)
      add(:bucket_id, references(:buckets, on_delete: :delete_all))
    end

    # NULLS NOT DISTINCT (PostgreSQL 15+) enforces a single explicit-empty marker
    # row per (securities_account_id, security_id) alongside unique bucket rows.
    execute(
      """
      CREATE UNIQUE INDEX position_bucket_overrides_unique_index
        ON position_bucket_overrides (securities_account_id, security_id, bucket_id)
        NULLS NOT DISTINCT;
      """,
      "DROP INDEX position_bucket_overrides_unique_index;"
    )

    create(index(:position_bucket_overrides, [:bucket_id]))

    # Views: global named filters. `include_all = true` means "include :all";
    # otherwise the include set is the linked view_include_buckets. Exclude wins.
    create table(:views) do
      add(:name, :string, null: false)
      add(:include_all, :boolean, null: false, default: true)
      timestamps()
    end

    create(unique_index(:views, [:name]))

    create table(:view_include_buckets) do
      add(:view_id, references(:views, on_delete: :delete_all), null: false)
      add(:bucket_id, references(:buckets, on_delete: :delete_all), null: false)
    end

    create(unique_index(:view_include_buckets, [:view_id, :bucket_id]))

    create table(:view_exclude_buckets) do
      add(:view_id, references(:views, on_delete: :delete_all), null: false)
      add(:bucket_id, references(:buckets, on_delete: :delete_all), null: false)
    end

    create(unique_index(:view_exclude_buckets, [:view_id, :bucket_id]))

    # Arm only the root buckets table (ADR-0017 guard trigger). Assignment and
    # view tables are intentionally left un-armed (see @moduledoc).
    execute(
      """
      CREATE TRIGGER buckets_require_journal_actor
        BEFORE INSERT OR UPDATE OR DELETE ON buckets
        FOR EACH ROW EXECUTE FUNCTION portfolixir_require_journal_actor();
      """,
      "DROP TRIGGER IF EXISTS buckets_require_journal_actor ON buckets;"
    )
  end

  def down do
    execute("DROP TRIGGER IF EXISTS buckets_require_journal_actor ON buckets;")
    drop(table(:view_exclude_buckets))
    drop(table(:view_include_buckets))
    drop(table(:views))
    drop(table(:position_bucket_overrides))
    drop(table(:cash_account_buckets))
    drop(table(:securities_account_buckets))
    drop(table(:buckets))
  end
end
