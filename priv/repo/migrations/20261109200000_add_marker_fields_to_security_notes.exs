defmodule Portfolixir.Repo.Migrations.AddMarkerFieldsToSecurityNotes do
  @moduledoc """
  ADR-0044's amendment of 2026-11-06 (Sprint 28, N5; ADR-0056 §8, A2): a
  research-log entry may carry a `headline`, an `event_type` and a `tone`,
  and an entry written from a news story keeps the id of the label it took
  its event type or tone from.

    * `headline` — plain text, 1 to 80 code points (ADR-0054 §4's text
      rules are the changeset's; the CHECK binds the length);
    * `event_type` — one of the eight event types (ADR-0056 §7's set
      without `noise`: an entry is what was judged worth keeping);
    * `tone` — -1, 0 or +1, a stored statement, never a computed figure;
    * `news_label_id` — provenance only: the `news_labels` row an entry
      written with a `cluster_id` took its event type or tone from. No
      foreign key: a later put of the same (cluster, model, prompt version)
      rewrites that label in place (the journal keeps every version), so
      the id names where the proposal came from, not what it says now.

  The first three are accepted on `evidence` and `event_result` entries
  only (`security_notes_marker_kind_check`). All four columns are nullable
  and every stored entry reads them as absent: the CHECKs hold for every
  stored row (each is NULL), so they are added valid. The table is
  append-only, so no row is rewritten and no trigger fires.
  """
  use Ecto.Migration

  @event_types ~w(earnings guidance capital_measure legal m_and_a product regulatory macro)

  def change do
    alter table(:security_notes) do
      add(:headline, :text)
      add(:event_type, :string, size: 32)
      add(:tone, :smallint)
      add(:news_label_id, :bigint)
    end

    create(
      constraint(:security_notes, :security_notes_headline_length_check,
        check: "char_length(headline) BETWEEN 1 AND 80"
      )
    )

    create(
      constraint(:security_notes, :security_notes_event_type_check,
        check: "event_type IN (#{Enum.map_join(@event_types, ", ", &"'#{&1}'")})"
      )
    )

    create(constraint(:security_notes, :security_notes_tone_check, check: "tone IN (-1, 0, 1)"))

    create(
      constraint(:security_notes, :security_notes_marker_kind_check,
        check:
          "(headline IS NULL AND event_type IS NULL AND tone IS NULL) OR " <>
            "kind IN ('evidence', 'event_result')"
      )
    )

    create(
      constraint(:security_notes, :security_notes_news_label_id_check, check: "news_label_id > 0")
    )
  end
end
