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

  **One lock, shared by bookings, exclusive to a retirement.** Each trigger
  checks the other table, and under READ COMMITTED neither sees a row the
  other transaction has not committed, so a booking and a retirement of one
  hash running at once could both commit. Both trigger functions therefore
  take the **import-hash lock** before their check: the transaction-scoped
  advisory lock of the two-key form with the keys `(727_209_017, 0)`,
  reserved for these two triggers. No other advisory lock of the application
  uses the first key 727_209_017: each of the others has a first key of its
  own. A booking takes the lock shared (`pg_advisory_xact_lock_shared`), a
  retirement exclusive (`pg_advisory_xact_lock`), so a retirement waits for
  every booking transaction in flight and a booking for a retirement in
  flight; the second writer then reads what the first committed. Bookings
  never wait for each other.

  It is one key and not one per hash. A lock held until commit takes an entry
  of the database's shared lock table, and an import books every row of a
  file in one transaction, the preview's dry run too: one lock per hash ran
  the table out (`53200 out of shared memory`) at some 11,000 to 15,000 rows
  under the default `max_locks_per_transaction` of 64, below the importer's
  100,000-row cap. A transaction that takes a lock it already holds takes no
  new entry, so one key costs one entry per transaction, however many rows it
  books. Hashed keys were also taken in no fixed order and could collide, so
  two writers with no hash in common could deadlock; one key has no order.
  The cost: a retirement also waits for bookings of other hashes. That
  serializes more than it must, never less, and the only writer that retires,
  a merge, books no hash, so no transaction holds the shared lock while it
  asks for the exclusive one.

  This migration replaces the existing function of `transactions` with the
  locking body; `down` restores the body it had.

  Additive: two functions and a trigger, over no stored row.
  """
  use Ecto.Migration

  # The import-hash lock's two keys (#917): reserved for the two triggers
  # below, and named by no other advisory lock (see the moduledoc).
  @lock_keys "727209017, 0"

  def up do
    execute("""
    CREATE OR REPLACE FUNCTION portfolixir_refuse_held_import_hash()
    RETURNS trigger AS $$
    BEGIN
      IF NEW.import_hash IS NULL THEN
        RETURN NEW;
      END IF;

      PERFORM pg_advisory_xact_lock(#{@lock_keys});

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
  # `20260925130000` created it, and with the import-hash lock taken shared
  # once the row is known to carry a new hash.
  defp refuse_retired_function(lock: lock?) do
    lock = if lock?, do: "PERFORM pg_advisory_xact_lock_shared(#{@lock_keys});", else: ""

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
