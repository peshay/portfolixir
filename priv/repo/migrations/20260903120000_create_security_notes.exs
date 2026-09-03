defmodule Portfolixir.Repo.Migrations.CreateSecurityNotes do
  @moduledoc """
  ADR-0044 §§1–5: the security research log — an **append-only** table of
  dated knowledge entries per security. The current thesis state is derived
  from these rows (`Portfolixir.Knowledge.ThesisState`), never stored beside
  them.

  Three properties are enforced here, at the database, not only in the
  context:

  1. **Append-only** (§1, §3): UPDATE, DELETE and TRUNCATE raise, the same way
     `audit_journal` is protected. A refuted finding is withdrawn by adding a
     `retraction` entry that supersedes it; both stay readable.
  2. **Closed sets** (§2): `kind`, `source_quality`, `author` and the thesis
     `conviction` tier are CHECK-constrained to the values the schema module
     resolves with `String.to_existing_atom/1`.
  3. **Journaled from the first migration** (§5, a signed clause): the
     journal-actor guard trigger is attached in the same migration that
     creates the table, so the new agent write path adds nothing to the
     rollout debt.

  `as_of` is the statement's cut-off date and is distinct from `inserted_at`
  (the write time); `valid_until` carries dated blocks; `supersedes_id` points
  at the earlier entry an entry replaces (same security, enforced in the
  context, the superseded row stays visible).
  """
  use Ecto.Migration

  def up do
    create table(:security_notes) do
      add(:security_id, references(:securities, on_delete: :restrict), null: false)
      add(:author, :string, null: false)
      add(:machine_generated, :boolean, null: false, default: false)
      add(:kind, :string, null: false)
      add(:body, :text, null: false)
      add(:source_url, :string)
      add(:source_quality, :string, null: false)
      add(:as_of, :date, null: false)
      add(:supersedes_id, references(:security_notes, on_delete: :restrict))
      add(:valid_until, :date)
      # Fields of the `thesis` kind (the B4.1 projection inputs).
      add(:conviction, :string)
      add(:invalidation_condition, :text)
      add(:time_stop, :date)

      timestamps(updated_at: false)
    end

    create(index(:security_notes, [:security_id, :as_of]))
    create(index(:security_notes, [:supersedes_id]))
    create(index(:security_notes, [:valid_until]))
    create(index(:security_notes, [:source_quality]))

    # Mirrors the closed sets in Portfolixir.Knowledge.SecurityNote exactly.
    create(
      constraint(:security_notes, :security_notes_kind_check,
        check:
          "kind IN ('thesis', 'evidence', 'invalidation_check', 'event_result', 'risk', 'retraction', 'decision')"
      )
    )

    create(
      constraint(:security_notes, :security_notes_source_quality_check,
        check: "source_quality IN ('primary', 'secondary_multi', 'awareness', 'unverified')"
      )
    )

    create(
      constraint(:security_notes, :security_notes_author_check,
        check: "author IN ('operator', 'agent', 'local_model')"
      )
    )

    create(
      constraint(:security_notes, :security_notes_conviction_check,
        check: "conviction IS NULL OR conviction IN ('low', 'medium', 'high')"
      )
    )

    # §4: an extracted entry is a proposal carrying its source.
    create(
      constraint(:security_notes, :security_notes_machine_generated_source_check,
        check: "machine_generated = false OR source_url IS NOT NULL"
      )
    )

    # §3: a retraction withdraws something — it always supersedes an entry.
    create(
      constraint(:security_notes, :security_notes_retraction_supersedes_check,
        check: "kind <> 'retraction' OR supersedes_id IS NOT NULL"
      )
    )

    # Append-only at the database (§1, §3). The application role owns the
    # table, so REVOKE is not enough; raise on any rewrite. TRUNCATE is a
    # statement-level trigger.
    execute("""
    CREATE OR REPLACE FUNCTION portfolixir_security_notes_append_only()
    RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION 'security_notes is append-only: % is not permitted', TG_OP
        USING ERRCODE = 'restrict_violation';
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER security_notes_no_update
      BEFORE UPDATE ON security_notes
      FOR EACH ROW EXECUTE FUNCTION portfolixir_security_notes_append_only();
    """)

    execute("""
    CREATE TRIGGER security_notes_no_delete
      BEFORE DELETE ON security_notes
      FOR EACH ROW EXECUTE FUNCTION portfolixir_security_notes_append_only();
    """)

    execute("""
    CREATE TRIGGER security_notes_no_truncate
      BEFORE TRUNCATE ON security_notes
      FOR EACH STATEMENT EXECUTE FUNCTION portfolixir_security_notes_append_only();
    """)

    # §5: journal-armed at creation (ADR-0017 pattern, same guard function the
    # other armed tables use). INSERT is the only write the table admits; the
    # guard still covers UPDATE/DELETE so a future relaxation of the
    # append-only triggers would not silently open an unjournaled path.
    execute("""
    CREATE TRIGGER security_notes_require_journal_actor
      BEFORE INSERT OR UPDATE OR DELETE ON security_notes
      FOR EACH ROW EXECUTE FUNCTION portfolixir_require_journal_actor();
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS security_notes_require_journal_actor ON security_notes;")
    execute("DROP TRIGGER IF EXISTS security_notes_no_truncate ON security_notes;")
    execute("DROP TRIGGER IF EXISTS security_notes_no_delete ON security_notes;")
    execute("DROP TRIGGER IF EXISTS security_notes_no_update ON security_notes;")
    execute("DROP FUNCTION IF EXISTS portfolixir_security_notes_append_only() CASCADE;")
    drop(table(:security_notes))
  end
end
