defmodule Portfolixir.Repo.Migrations.CreateNewsLabels do
  @moduledoc """
  ADR-0056 §7 and §12 (Sprint 28, N1): `news_labels`, what an outside model
  says about a story, written through `news.label_put` only.

  Every rule a row's own fields can state is a CHECK here, behind the
  context's field errors (`Portfolixir.News.Labels`), so a writer that skips
  the context still cannot store a label outside §7's schema:

    * `event_type` one of the nine of §7;
    * `materiality` 0 to 3, `tone` -1, 0 or +1;
    * `confidence` a decimal from 0 to 1 with at most four places, stored as
      `numeric` (never a float, ADR-0003), and checked against its own
      truncation, because a `numeric(p, s)` column would round a fifth place
      in silence;
    * `machine_generated` always true (NFR-10: a label is a proposal);
    * `model` and `prompt_version` identifiers of 1 to 64 characters:
      letters, digits and `. _ : / @ + -`, starting with a letter or a
      digit. They are the label's identity, so a space, a control or an
      invisible character (ADR-0054 §4) could make two labels of one model
      look like one;
    * a `clause_idx` only beside a `thesis_note_id`, from 1;
    * ids positive, and `updated_at` never before `created_at`.

  **Unique:** one label per `(cluster_id, model, prompt_version)` (§7: the
  write is idempotent on that triple; a second put replaces the label in
  place, journaled).

  **No foreign key onto the story or the suggested security.** §12 keeps
  labels without limit while stories follow their items out of the
  retention window and merge away under the clustering (B3): a key that
  restricted would stop retention and every merge; one that cascaded or
  nulled would delete or blank the labeller's record. The write checks
  that the story exists, holding its row `FOR KEY SHARE` until it commits,
  and a stored label keeps naming the story it was about. The same holds
  for `suggested_security_id`: a proposal, checked at the write, that must
  never keep a security from being merged or deleted
  (`Portfolixir.Lifecycle.ForeignKeys` lists no key from here). The thesis
  note restricts: research-log entries are never deleted (ADR-0044 §3).

  **The journal:** every write is journaled under the token that made it
  (§7, §14 item 6), and the table is armed with the journal-actor guard.
  """
  use Ecto.Migration

  @event_types "('earnings', 'guidance', 'capital_measure', 'legal', 'm_and_a', 'product', " <>
                 "'regulatory', 'macro', 'noise')"
  @identifier "~ '^[A-Za-z0-9][A-Za-z0-9._:/@+-]{0,63}$'"

  def up do
    create table(:news_labels) do
      add(:cluster_id, :bigint, null: false)
      add(:model, :string, size: 64, null: false)
      add(:prompt_version, :string, size: 64, null: false)
      add(:event_type, :string, null: false)
      add(:materiality, :smallint, null: false)
      add(:tone, :smallint, null: false)
      add(:thesis_note_id, references(:security_notes, on_delete: :restrict))
      add(:clause_idx, :integer)
      add(:confidence, :decimal, null: false)
      add(:suggested_security_id, :bigint)
      add(:machine_generated, :boolean, null: false, default: true)

      timestamps(inserted_at: :created_at, type: :utc_datetime_usec)
    end

    create(
      unique_index(:news_labels, [:cluster_id, :model, :prompt_version],
        name: :news_labels_cluster_model_version_index
      )
    )

    create(index(:news_labels, [:thesis_note_id]))

    check(:cluster_id, "cluster_id > 0")
    check(:event_type, "event_type IN #{@event_types}")
    check(:materiality, "materiality BETWEEN 0 AND 3")
    check(:tone, "tone IN (-1, 0, 1)")

    check(
      :confidence,
      "confidence >= 0 AND confidence <= 1 AND confidence = trunc(confidence, 4)"
    )

    check(:machine_generated, "machine_generated")
    check(:model, "model #{@identifier}")
    check(:prompt_version, "prompt_version #{@identifier}")

    check(
      :clause,
      "clause_idx IS NULL OR (thesis_note_id IS NOT NULL AND clause_idx BETWEEN 1 AND 10000)"
    )

    check(:suggested_security_id, "suggested_security_id IS NULL OR suggested_security_id > 0")
    check(:updated_at, "updated_at >= created_at")

    execute("""
    CREATE TRIGGER news_labels_require_journal_actor
      BEFORE INSERT OR UPDATE OR DELETE ON news_labels
      FOR EACH ROW EXECUTE FUNCTION portfolixir_require_journal_actor();
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS news_labels_require_journal_actor ON news_labels")
    drop(table(:news_labels))
  end

  defp check(name, expression) do
    create(constraint(:news_labels, :"news_labels_#{name}_check", check: expression))
  end
end
