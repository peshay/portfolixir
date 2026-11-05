defmodule Portfolixir.Repo.Migrations.CreatePredictions do
  @moduledoc """
  ADR-0055 §§1–2: the `predictions` table, a **permanent** record of one
  call on one security — it outperforms or underperforms a benchmark by a
  date, with a stated probability, an author and the model an agent names.
  Nothing edits, withdraws or deletes a prediction, and nothing dates one in
  the past.

  Enforced here, at the database, not only in the context:

  1. **Append-only** (§2): UPDATE, DELETE and TRUNCATE raise, the way
     `security_notes` and `audit_journal` are protected. A mistaken
     prediction stays and counts; a corrected one is a new row.
  2. **The bounds of §1 as CHECKs**, behind the changeset's field errors: a
     probability from 0.50 to 0.99 in steps of 0.01, a direction and an
     author from their closed sets, a model required for an agent and
     refused for the operator (at most 100 characters), a rationale of at
     most 4,000, and a resolution date 7 to 1,830 days after the UTC day of
     `made_at`.
  3. **The benchmark as ADR-0046's two kinds**, `benchmark_kind` with
     exactly one of `benchmark_security_id` (a foreign key, so a benchmark
     security restricts its delete as the security does) and
     `benchmark_rate` (a fixed annual rate inside the engine's bound).
  4. **A linked research-log entry of the same security**: `note_id`
     references `security_notes (id, security_id)` together, so an entry of
     another security cannot be linked even by a raw insert. The composite
     key needs a unique index on that pair; `id` is already unique, so the
     index admits every row the table holds.
  5. **Journal-armed at creation** (ADR-0017 pattern): the journal-actor
     guard is attached in this migration, so an unjournaled insert is
     refused.

  The two references onto `securities` are declared in
  `Portfolixir.Lifecycle.ForeignKeys` as `merge: :refuse`, `delete:
  :restrict` (ADR-0050 §9, §14): a scored record can neither move nor
  vanish.

  `probability` and `benchmark_rate` are unconstrained `numeric`, so the
  column never rounds a value: a probability of 0.555 is refused by the
  CHECK, not stored as 0.56.
  """
  use Ecto.Migration

  def up do
    create(unique_index(:security_notes, [:id, :security_id]))

    create table(:predictions) do
      add(:security_id, references(:securities, on_delete: :restrict), null: false)
      add(:direction, :string, null: false)
      add(:probability, :decimal, null: false)
      add(:benchmark_kind, :string, null: false)
      add(:benchmark_security_id, references(:securities, on_delete: :restrict))
      add(:benchmark_rate, :decimal)
      add(:resolves_on, :date, null: false)
      add(:made_at, :utc_datetime_usec, null: false)
      add(:author, :string, null: false)
      add(:actor, :string)
      add(:model, :string)

      add(
        :note_id,
        references(:security_notes,
          with: [security_id: :security_id],
          on_delete: :restrict,
          name: :predictions_note_id_fkey
        )
      )

      add(:rationale, :text)
    end

    create(index(:predictions, [:security_id, :resolves_on]))
    create(index(:predictions, [:benchmark_security_id]))
    create(index(:predictions, [:note_id]))
    create(index(:predictions, [:resolves_on]))
    create(index(:predictions, [:author, :model]))

    # Mirrors the closed sets and bounds in Portfolixir.Predictions.Prediction.
    create(
      constraint(:predictions, :predictions_direction_check,
        check: "direction IN ('outperform', 'underperform')"
      )
    )

    create(
      constraint(:predictions, :predictions_probability_check,
        check:
          "probability >= 0.50 AND probability <= 0.99 AND probability = round(probability, 2)"
      )
    )

    create(
      constraint(:predictions, :predictions_benchmark_check,
        check:
          "(benchmark_kind = 'security' AND benchmark_security_id IS NOT NULL " <>
            "AND benchmark_rate IS NULL) OR " <>
            "(benchmark_kind = 'rate' AND benchmark_rate IS NOT NULL " <>
            "AND benchmark_security_id IS NULL)"
      )
    )

    # Portfolixir.Portfolios.Performance.Benchmark.valid_rate?/1's bound.
    create(
      constraint(:predictions, :predictions_benchmark_rate_check,
        check: "benchmark_rate IS NULL OR (benchmark_rate >= -0.999999 AND benchmark_rate <= 10)"
      )
    )

    create(
      constraint(:predictions, :predictions_benchmark_security_check,
        check: "benchmark_security_id IS NULL OR benchmark_security_id <> security_id"
      )
    )

    # made_at is stored as UTC without a zone, so its ::date is the UTC day.
    create(
      constraint(:predictions, :predictions_resolves_on_check,
        check: "resolves_on >= (made_at::date + 7) AND resolves_on <= (made_at::date + 1830)"
      )
    )

    create(
      constraint(:predictions, :predictions_author_check,
        check: "author IN ('operator', 'agent')"
      )
    )

    create(
      constraint(:predictions, :predictions_model_check,
        check:
          "(author = 'agent' AND model IS NOT NULL AND char_length(model) BETWEEN 1 AND 100) " <>
            "OR (author = 'operator' AND model IS NULL)"
      )
    )

    create(
      constraint(:predictions, :predictions_rationale_length_check,
        check: "rationale IS NULL OR char_length(rationale) <= 4000"
      )
    )

    # Append-only at the database (§2). The application role owns the table,
    # so REVOKE is not enough; raise on any rewrite. TRUNCATE is a
    # statement-level trigger.
    execute("""
    CREATE OR REPLACE FUNCTION portfolixir_predictions_append_only()
    RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION 'predictions is append-only: % is not permitted', TG_OP
        USING ERRCODE = 'restrict_violation';
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER predictions_no_update
      BEFORE UPDATE ON predictions
      FOR EACH ROW EXECUTE FUNCTION portfolixir_predictions_append_only();
    """)

    execute("""
    CREATE TRIGGER predictions_no_delete
      BEFORE DELETE ON predictions
      FOR EACH ROW EXECUTE FUNCTION portfolixir_predictions_append_only();
    """)

    execute("""
    CREATE TRIGGER predictions_no_truncate
      BEFORE TRUNCATE ON predictions
      FOR EACH STATEMENT EXECUTE FUNCTION portfolixir_predictions_append_only();
    """)

    # Journal-armed at creation (ADR-0017 pattern, the guard function the
    # other armed tables use). INSERT is the only write the table admits; the
    # guard still covers UPDATE and DELETE, so a future relaxation of the
    # append-only triggers would not silently open an unjournaled path.
    execute("""
    CREATE TRIGGER predictions_require_journal_actor
      BEFORE INSERT OR UPDATE OR DELETE ON predictions
      FOR EACH ROW EXECUTE FUNCTION portfolixir_require_journal_actor();
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS predictions_require_journal_actor ON predictions;")
    execute("DROP TRIGGER IF EXISTS predictions_no_truncate ON predictions;")
    execute("DROP TRIGGER IF EXISTS predictions_no_delete ON predictions;")
    execute("DROP TRIGGER IF EXISTS predictions_no_update ON predictions;")
    execute("DROP FUNCTION IF EXISTS portfolixir_predictions_append_only() CASCADE;")
    drop(table(:predictions))
    drop(unique_index(:security_notes, [:id, :security_id]))
  end
end
