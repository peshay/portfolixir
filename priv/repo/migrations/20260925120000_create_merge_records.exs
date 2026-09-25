defmodule Portfolixir.Repo.Migrations.CreateMergeRecords do
  @moduledoc """
  ADR-0050 §12: one **merge record** per lifecycle merge — a cash account into
  a cash account, a depot into a depot, or a security into a security.

  A record names the `kind`, the merged-away `source_id`, the surviving
  `target_id`, the `portfolio_id` of an account merge (NULL for a security),
  a `source_snapshot` of the source row, a `manifest` of every row the merge
  moved, restated, deleted, collapsed, re-pointed or dropped (with the
  operator's choices and the values of dropped colliding quotes), the
  `plan_digest` the operator approved, and the actor that ran it.

  Enforced here, at the database:

  1. **No foreign key on the source or the target** (§12): ids are never
     reused, the merge that writes this row deletes its source, and a target
     can later be merged away itself.
  2. **A source is merged once per kind**: `UNIQUE (kind, source_id)`, which is
     what makes a retry return the original record and an already merged
     source answer `already_merged` (§10).
  3. **Closed sets** as CHECK constraints mirroring
     `Portfolixir.Lifecycle.MergeRecord`: the three kinds, two different rows,
     and a portfolio exactly for an account merge.
  4. **Append-only** (§12, §16 invariant 11): UPDATE, DELETE and TRUNCATE
     raise, the way `audit_journal` and `security_notes` are protected. There
     is no unmerge; the manifest and the journal's before-images make a merge
     reconstructable by inspection.
  5. **Journal-armed from this migration** (ADR-0017, resource code
     `merge_record`): the journal-actor guard is attached where the table is
     created.
  """
  use Ecto.Migration

  def up do
    create table(:merge_records) do
      add(:kind, :string, null: false)
      add(:source_id, :bigint, null: false)
      add(:target_id, :bigint, null: false)
      add(:portfolio_id, references(:portfolios, on_delete: :restrict))
      add(:source_snapshot, :map, null: false)
      add(:manifest, :map, null: false)
      add(:plan_digest, :string, null: false)
      add(:actor_type, :string, null: false)
      add(:actor_label, :string)

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create(unique_index(:merge_records, [:kind, :source_id]))
    create(index(:merge_records, [:kind, :target_id]))
    create(index(:merge_records, [:portfolio_id]))

    create(
      constraint(:merge_records, :merge_records_kind_check,
        check: "kind IN ('cash_account', 'securities_account', 'security')"
      )
    )

    create(
      constraint(:merge_records, :merge_records_distinct_rows_check,
        check: "source_id <> target_id"
      )
    )

    # The composite foreign keys pin accounts to one portfolio, so an account
    # merge happens inside one; securities are portfolio-free.
    create(
      constraint(:merge_records, :merge_records_portfolio_check,
        check: "(kind = 'security') = (portfolio_id IS NULL)"
      )
    )

    execute("""
    CREATE OR REPLACE FUNCTION portfolixir_merge_records_append_only()
    RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION 'merge_records is append-only: % is not permitted', TG_OP
        USING ERRCODE = 'restrict_violation';
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER merge_records_no_update
      BEFORE UPDATE ON merge_records
      FOR EACH ROW EXECUTE FUNCTION portfolixir_merge_records_append_only();
    """)

    execute("""
    CREATE TRIGGER merge_records_no_delete
      BEFORE DELETE ON merge_records
      FOR EACH ROW EXECUTE FUNCTION portfolixir_merge_records_append_only();
    """)

    execute("""
    CREATE TRIGGER merge_records_no_truncate
      BEFORE TRUNCATE ON merge_records
      FOR EACH STATEMENT EXECUTE FUNCTION portfolixir_merge_records_append_only();
    """)

    execute("""
    CREATE TRIGGER merge_records_require_journal_actor
      BEFORE INSERT OR UPDATE OR DELETE ON merge_records
      FOR EACH ROW EXECUTE FUNCTION portfolixir_require_journal_actor();
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS merge_records_require_journal_actor ON merge_records;")
    execute("DROP TRIGGER IF EXISTS merge_records_no_truncate ON merge_records;")
    execute("DROP TRIGGER IF EXISTS merge_records_no_delete ON merge_records;")
    execute("DROP TRIGGER IF EXISTS merge_records_no_update ON merge_records;")
    execute("DROP FUNCTION IF EXISTS portfolixir_merge_records_append_only() CASCADE;")
    drop(table(:merge_records))
  end
end
