defmodule Portfolixir.Repo.Migrations.RefuseRetiringAHeldImportHash do
  @moduledoc """
  ADR-0050 §16, the 2026-10-06 note to invariant 4 (#917): the set of hashes
  live transactions hold and the set of retired hashes are disjoint, and the
  database now keeps them so from both sides.

  `20260925130000_create_retired_import_hashes` refuses a retired hash on
  `transactions`. This adds the mirror: a `BEFORE INSERT` trigger on
  `retired_import_hashes` refuses a hash that a row in `transactions` still
  holds. A merge deletes a row before it retires the row's hash, inside one
  database transaction, so it never meets the refusal; a retirement of a
  booking that is still there does.

  It raises the way the other side does: a `unique_violation` naming the
  constraint `retired_import_hashes_import_hash_held`, which
  `RetiredImportHash.changeset/1` answers as an error on `import_hash` rather
  than a crash. The table's append-only and journal-actor triggers are
  unchanged, and the table is append-only, so an insert is the only write
  that can carry a new hash.

  **One lock per hash.** Each trigger checks the other table, and under READ
  COMMITTED neither sees a row the other transaction has not committed, so a
  booking and a retirement of one hash running at once could both commit.
  Both trigger functions therefore take a transaction-scoped advisory lock on
  the hash (`pg_advisory_xact_lock(hashtext(hash))`) before their check: the
  second writer waits for the first to end and then reads what it committed.
  The lock is the one-key form; every other advisory lock of the application
  is the two-key form, a separate key space, so none can meet it. This
  migration replaces the existing function of `transactions` with the locking
  body; `down` restores the body it had.

  Additive: two functions and a trigger, over no stored row.
  """
  use Ecto.Migration

  def up do
    execute("""
    CREATE OR REPLACE FUNCTION portfolixir_refuse_held_import_hash()
    RETURNS trigger AS $$
    BEGIN
      IF NEW.import_hash IS NULL THEN
        RETURN NEW;
      END IF;

      PERFORM pg_advisory_xact_lock(hashtext(NEW.import_hash));

      IF EXISTS (
        SELECT 1 FROM transactions t WHERE t.import_hash = NEW.import_hash
      ) THEN
        RAISE EXCEPTION
          'import hash % is still held by a transaction and cannot be retired', NEW.import_hash
          USING ERRCODE = 'unique_violation',
                CONSTRAINT = 'retired_import_hashes_import_hash_held',
                TABLE = 'retired_import_hashes',
                COLUMN = 'import_hash';
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER retired_import_hashes_refuse_held_import_hash
      BEFORE INSERT ON retired_import_hashes
      FOR EACH ROW EXECUTE FUNCTION portfolixir_refuse_held_import_hash();
    """)

    execute(refuse_retired_function(lock: true))
  end

  def down do
    execute(refuse_retired_function(lock: false))

    execute(
      "DROP TRIGGER IF EXISTS retired_import_hashes_refuse_held_import_hash ON retired_import_hashes;"
    )

    execute("DROP FUNCTION IF EXISTS portfolixir_refuse_held_import_hash();")
  end

  # The function of `transactions_refuse_retired_import_hash`, as
  # `20260925130000` created it, and with the per-hash lock taken once the
  # row is known to carry a new hash.
  defp refuse_retired_function(lock: lock?) do
    lock = if lock?, do: "PERFORM pg_advisory_xact_lock(hashtext(NEW.import_hash));", else: ""

    """
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

      #{lock}

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
    """
  end
end
