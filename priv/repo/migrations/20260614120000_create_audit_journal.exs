defmodule Portfolixir.Repo.Migrations.CreateAuditJournal do
  @moduledoc """
  Append-only audit journal (ADR-0015, FR-28).

  Creates the `audit_journal` table, protects it against UPDATE/DELETE/TRUNCATE
  at the database level, and defines the reusable guard-trigger function used to
  arm journaled business tables. This migration deliberately arms **no** business
  table: per-context arming lands with each context's actor-first refactor
  (architecture amendment 1, leaf-first order), so existing write paths keep
  working unchanged.
  """
  use Ecto.Migration

  def up do
    create table(:audit_journal) do
      add(:actor_type, :string, null: false)
      add(:actor_label, :string)
      add(:operation, :string, null: false)
      add(:resource_type, :string, null: false)
      add(:resource_id, :string)
      add(:before, :map)
      add(:after, :map)
      add(:scenario_id, :bigint)

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create(index(:audit_journal, [:resource_type, :resource_id]))
    create(index(:audit_journal, [:actor_type]))
    create(index(:audit_journal, [:inserted_at]))
    create(index(:audit_journal, [:scenario_id]))

    # Append-only: the application role owns the table, so REVOKE is not enough.
    # Raise on any rewrite of journal rows. TRUNCATE is a statement-level trigger.
    execute("""
    CREATE OR REPLACE FUNCTION portfolixir_audit_journal_append_only()
    RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION 'audit_journal is append-only: % is not permitted', TG_OP
        USING ERRCODE = 'restrict_violation';
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER audit_journal_no_update
      BEFORE UPDATE ON audit_journal
      FOR EACH ROW EXECUTE FUNCTION portfolixir_audit_journal_append_only();
    """)

    execute("""
    CREATE TRIGGER audit_journal_no_delete
      BEFORE DELETE ON audit_journal
      FOR EACH ROW EXECUTE FUNCTION portfolixir_audit_journal_append_only();
    """)

    execute("""
    CREATE TRIGGER audit_journal_no_truncate
      BEFORE TRUNCATE ON audit_journal
      FOR EACH STATEMENT EXECUTE FUNCTION portfolixir_audit_journal_append_only();
    """)

    # Reusable guard for journaled business tables. A journaled write must carry
    # a transaction-local actor (set by Portfolixir.Journal.record/3 via
    # `set_config('portfolixir.journal_actor', actor, true)`). `missing_ok = true`
    # makes an absent variable return NULL instead of PostgreSQL's
    # `unrecognized configuration parameter`.
    #
    # The check rejects NULL *and* the empty string: once a custom GUC has been
    # set on a (pooled) connection, resetting it via `set_config(name, NULL,
    # true)` leaves an empty string behind, not NULL — so a later un-journaled
    # write on the same recycled connection would otherwise slip through the
    # guard. Treating "" as "no actor" closes that gap (verified against
    # PostgreSQL 16). Defined here; attached to business tables per-context.
    execute("""
    CREATE OR REPLACE FUNCTION portfolixir_require_journal_actor()
    RETURNS trigger AS $$
    DECLARE
      actor text;
    BEGIN
      actor := current_setting('portfolixir.journal_actor', true);
      IF actor IS NULL OR actor = '' THEN
        RAISE EXCEPTION
          'write to % requires a journal actor; route the write through Portfolixir.Journal', TG_TABLE_NAME
          USING ERRCODE = 'restrict_violation';
      END IF;
      IF TG_OP = 'DELETE' THEN
        RETURN OLD;
      ELSE
        RETURN NEW;
      END IF;
    END;
    $$ LANGUAGE plpgsql;
    """)
  end

  def down do
    execute("DROP FUNCTION IF EXISTS portfolixir_require_journal_actor() CASCADE;")
    execute("DROP TRIGGER IF EXISTS audit_journal_no_truncate ON audit_journal;")
    execute("DROP TRIGGER IF EXISTS audit_journal_no_delete ON audit_journal;")
    execute("DROP TRIGGER IF EXISTS audit_journal_no_update ON audit_journal;")
    execute("DROP FUNCTION IF EXISTS portfolixir_audit_journal_append_only() CASCADE;")
    drop(table(:audit_journal))
  end
end
