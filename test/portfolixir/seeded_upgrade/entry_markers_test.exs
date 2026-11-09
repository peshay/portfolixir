defmodule Portfolixir.SeededUpgrade.EntryMarkersTest do
  # ADR-0044's amendment of 2026-11-06 (Sprint 28, N5): the migration that
  # adds `headline`, `event_type`, `tone` and `news_label_id` to the
  # append-only research log, with CHECKs, runs over the entries an instance
  # already holds (docs/development/guide.md, "Upgrade migrations over
  # legacy rows"). Every value is synthetic.
  #
  # async: false -- see Portfolixir.SeededUpgrade, "Where the cases run".
  use ExUnit.Case, async: false

  alias Portfolixir.SeededUpgrade

  @moduletag :seeded_upgrade

  # The migration before the marker fields.
  @before_markers 20_261_109_160_300

  # User story (ADR-0044, amendment of 2026-11-06):
  # As the operator upgrading an instance whose research log holds entries
  # of several kinds,
  # I want the fields of a headline, an event type and a tone added without
  # touching a stored entry,
  # so that the release boots, every old entry reads them as absent, and a
  # new entry can carry them.
  #
  # Acceptance criteria:
  # - Seeded with a thesis, an evidence and an event_result entry, the
  #   database migrates to head; the three are still there and read
  #   headline, event_type, tone and news_label_id as NULL.
  # - After the upgrade, an evidence entry with all three is stored; a
  #   thesis entry with a headline is refused by the kind CHECK.
  @tag seeded_upgrade: 20_261_109_200_000
  test "the marker fields do not stop the upgrade over stored entries",
       %{seeded_upgrade: migration} do
    upgrade = SeededUpgrade.upgrade!(from: @before_markers, seed: &seed_notes/1)

    assert migration in upgrade.migrated
    assert List.last(upgrade.migrated) == SeededUpgrade.head()

    assert %{rows: rows} =
             SeededUpgrade.query!(
               upgrade,
               "SELECT kind, headline, event_type, tone, news_label_id FROM security_notes " <>
                 "ORDER BY id"
             )

    assert rows == [
             ["thesis", nil, nil, nil, nil],
             ["evidence", nil, nil, nil, nil],
             ["event_result", nil, nil, nil, nil]
           ]

    SeededUpgrade.journaled!(upgrade, fn ->
      insert_note!(upgrade, upgrade.seeded, "evidence", "'A headline', 'earnings', 1")
    end)

    assert_raise Postgrex.Error, ~r/security_notes_marker_kind_check/, fn ->
      SeededUpgrade.journaled!(upgrade, fn ->
        insert_note!(upgrade, upgrade.seeded, "thesis", "'A headline', NULL, NULL")
      end)
    end

    assert %{rows: [[4]]} = SeededUpgrade.query!(upgrade, "SELECT count(*) FROM security_notes")
  end

  defp seed_notes(db) do
    %{rows: [[security]]} =
      SeededUpgrade.query!(
        db,
        "INSERT INTO securities (name, currency_code, inserted_at, updated_at) " <>
          "VALUES ('Alpha', 'EUR', LOCALTIMESTAMP(0), LOCALTIMESTAMP(0)) RETURNING id"
      )

    for kind <- ~w(thesis evidence event_result) do
      SeededUpgrade.query!(
        db,
        """
        INSERT INTO security_notes
          (security_id, author, kind, body, source_quality, as_of, inserted_at)
        VALUES ($1, 'agent', $2, 'A synthetic entry.', 'primary', '2026-10-01',
                LOCALTIMESTAMP(0))
        """,
        [security, kind]
      )
    end

    security
  end

  defp insert_note!(db, security, kind, markers) do
    SeededUpgrade.query!(
      db,
      """
      INSERT INTO security_notes
        (security_id, author, kind, body, source_quality, as_of, inserted_at,
         headline, event_type, tone)
      VALUES ($1, 'agent', $2, 'A synthetic entry.', 'primary', '2026-10-01',
              LOCALTIMESTAMP(0), #{markers})
      """,
      [security, kind]
    )
  end
end
