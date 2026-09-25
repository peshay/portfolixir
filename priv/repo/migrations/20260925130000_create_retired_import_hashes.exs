defmodule Portfolixir.Repo.Migrations.CreateRetiredImportHashes do
  @moduledoc """
  ADR-0050 §3, obligation O1: the content hash of every row a merge removes is
  **retired**, so the set of hashes held by transactions or retired hashes
  only grows, and no re-import of the same or a later Portfolio Performance
  export can book a removed row a second time.

  `retired_import_hashes` holds the `import_hash` (unique), the removed row's
  id (`former_transaction_id`), the `merge_record_id` that removed it, the
  `reason` (`internal_transfer`, §5; or `collapsed_duplicate`, §8, with the
  surviving target row in `superseded_by_transaction_id`) and `inserted_at`.

  Enforced here, at the database:

  1. **Append-only** (UPDATE, DELETE and TRUNCATE raise) and **journal-armed**
     from this migration (ADR-0017, resource code `retired_import_hash`).
  2. **Every retirement belongs to a merge record.** The foreign key is
     `DEFERRABLE INITIALLY DEFERRED`: a merge may retire the hashes of the
     rows it removes before it writes its record (ADR-0050 §7's step order),
     and the check runs when the merge's transaction commits.
  3. **A retired hash is refused on `transactions`**, the database backstop
     beside `transactions_import_hash_unique_index`: a trigger refuses an
     insert, or an update of `import_hash`, carrying a retired hash. It raises
     a `unique_violation` naming the constraint
     `transactions_import_hash_retired`, so every writer's changeset answers
     it as an error on `import_hash` rather than a crash.
  4. **No balance anchor and no split carries an import hash** (§1): the rows a
     declared restatement removes (§7's folded anchors, §9's collapsed splits)
     therefore hold no hash that would have to be retired. Neither kind is
     ever imported, so no existing row is expected to violate the check.
  """
  use Ecto.Migration

  def up do
    create table(:retired_import_hashes) do
      add(:import_hash, :string, null: false)
      # The removed row is gone, and the surviving row may be deleted later
      # through the ledger: neither id is a foreign key.
      add(:former_transaction_id, :bigint, null: false)
      add(:merge_record_id, :bigint, null: false)
      add(:reason, :string, null: false)
      add(:superseded_by_transaction_id, :bigint)

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create(unique_index(:retired_import_hashes, [:import_hash]))
    create(index(:retired_import_hashes, [:merge_record_id]))

    execute("""
    ALTER TABLE retired_import_hashes
      ADD CONSTRAINT retired_import_hashes_merge_record_id_fkey
      FOREIGN KEY (merge_record_id) REFERENCES merge_records (id)
      ON DELETE RESTRICT
      DEFERRABLE INITIALLY DEFERRED;
    """)

    create(
      constraint(:retired_import_hashes, :retired_import_hashes_reason_check,
        check:
          "(reason = 'internal_transfer' AND superseded_by_transaction_id IS NULL) " <>
            "OR (reason = 'collapsed_duplicate' AND superseded_by_transaction_id IS NOT NULL)"
      )
    )

    execute("""
    CREATE OR REPLACE FUNCTION portfolixir_retired_import_hashes_append_only()
    RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION 'retired_import_hashes is append-only: % is not permitted', TG_OP
        USING ERRCODE = 'restrict_violation';
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER retired_import_hashes_no_update
      BEFORE UPDATE ON retired_import_hashes
      FOR EACH ROW EXECUTE FUNCTION portfolixir_retired_import_hashes_append_only();
    """)

    execute("""
    CREATE TRIGGER retired_import_hashes_no_delete
      BEFORE DELETE ON retired_import_hashes
      FOR EACH ROW EXECUTE FUNCTION portfolixir_retired_import_hashes_append_only();
    """)

    execute("""
    CREATE TRIGGER retired_import_hashes_no_truncate
      BEFORE TRUNCATE ON retired_import_hashes
      FOR EACH STATEMENT EXECUTE FUNCTION portfolixir_retired_import_hashes_append_only();
    """)

    execute("""
    CREATE TRIGGER retired_import_hashes_require_journal_actor
      BEFORE INSERT OR UPDATE OR DELETE ON retired_import_hashes
      FOR EACH ROW EXECUTE FUNCTION portfolixir_require_journal_actor();
    """)

    execute("""
    CREATE OR REPLACE FUNCTION portfolixir_refuse_retired_import_hash()
    RETURNS trigger AS $$
    BEGIN
      IF NEW.import_hash IS NULL THEN
        RETURN NEW;
      END IF;

      IF TG_OP = 'UPDATE' THEN
        IF NEW.import_hash IS NOT DISTINCT FROM OLD.import_hash THEN
          RETURN NEW;
        END IF;
      END IF;

      IF EXISTS (
        SELECT 1 FROM retired_import_hashes r WHERE r.import_hash = NEW.import_hash
      ) THEN
        RAISE EXCEPTION
          'import hash % was retired by a merge and cannot be booked again', NEW.import_hash
          USING ERRCODE = 'unique_violation',
                CONSTRAINT = 'transactions_import_hash_retired',
                TABLE = 'transactions',
                COLUMN = 'import_hash';
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER transactions_refuse_retired_import_hash
      BEFORE INSERT OR UPDATE OF import_hash ON transactions
      FOR EACH ROW EXECUTE FUNCTION portfolixir_refuse_retired_import_hash();
    """)

    create(
      constraint(:transactions, :transactions_import_hash_kind_check,
        check: "import_hash IS NULL OR type NOT IN ('balance_adjustment', 'split')"
      )
    )
  end

  def down do
    drop(constraint(:transactions, :transactions_import_hash_kind_check))
    execute("DROP TRIGGER IF EXISTS transactions_refuse_retired_import_hash ON transactions;")
    execute("DROP FUNCTION IF EXISTS portfolixir_refuse_retired_import_hash() CASCADE;")

    execute(
      "DROP TRIGGER IF EXISTS retired_import_hashes_require_journal_actor ON retired_import_hashes;"
    )

    execute("DROP TRIGGER IF EXISTS retired_import_hashes_no_truncate ON retired_import_hashes;")
    execute("DROP TRIGGER IF EXISTS retired_import_hashes_no_delete ON retired_import_hashes;")
    execute("DROP TRIGGER IF EXISTS retired_import_hashes_no_update ON retired_import_hashes;")
    execute("DROP FUNCTION IF EXISTS portfolixir_retired_import_hashes_append_only() CASCADE;")
    drop(table(:retired_import_hashes))
  end
end
