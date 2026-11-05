defmodule Portfolixir.SeededUpgrade.PredictionsTest do
  # ADR-0055 §1 (Sprint 25 plan, Lane F, F1): the migration that creates
  # the predictions table also adds a UNIQUE index over the research log's
  # (id, security_id), the key a prediction's note_id references together
  # with its security, so an entry of another security cannot be linked.
  # A unique index runs over every row an upgrading instance holds, so it
  # gets a seeded case (docs/development/guide.md, "Upgrade migrations over
  # legacy rows").
  #
  # async: false -- see Portfolixir.SeededUpgrade, "Where the cases run".
  use ExUnit.Case, async: false

  alias Portfolixir.SeededUpgrade

  @moduletag :seeded_upgrade

  # The migration before the predictions table.
  @before_predictions 20_261_029_121_300

  # User story (ADR-0055 §1):
  # As the operator upgrading an instance whose research log already holds
  # entries on several securities,
  # I want the upgrade that adds predictions to keep every entry and let a
  # prediction link only an entry of its own security,
  # so that the release boots and no call can point at another security's
  # thesis.
  #
  # Acceptance criteria:
  # - Seeded with two securities and three research-log entries, the
  #   database migrates to head and every entry is still there.
  # - After the upgrade, a prediction linking an entry of its own security
  #   is stored, and one linking an entry of the other security is refused
  #   by the composite foreign key.
  @tag seeded_upgrade: 20_261_105_140_000
  test "the predictions migration does not stop the upgrade over research-log entries",
       %{seeded_upgrade: migration} do
    upgrade = SeededUpgrade.upgrade!(from: @before_predictions, seed: &seed_notes/1)
    seeded = upgrade.seeded

    assert migration in upgrade.migrated
    assert List.last(upgrade.migrated) == SeededUpgrade.head()

    assert %{rows: [[3]]} = SeededUpgrade.query!(upgrade, "SELECT count(*) FROM security_notes")

    SeededUpgrade.journaled!(upgrade, fn ->
      insert_prediction!(upgrade, seeded.first, seeded.first_note)
    end)

    assert_raise Postgrex.Error, ~r/predictions_note_id_fkey/, fn ->
      SeededUpgrade.journaled!(upgrade, fn ->
        insert_prediction!(upgrade, seeded.first, seeded.second_note)
      end)
    end

    assert %{rows: [[1]]} = SeededUpgrade.query!(upgrade, "SELECT count(*) FROM predictions")
  end

  defp seed_notes(db) do
    first = insert!(db, "INSERT INTO securities #{row(~w(name currency_code))}", ["Alpha", "EUR"])
    second = insert!(db, "INSERT INTO securities #{row(~w(name currency_code))}", ["Beta", "EUR"])

    first_note = insert_note!(db, first)
    _another = insert_note!(db, first)
    second_note = insert_note!(db, second)

    %{first: first, first_note: first_note, second_note: second_note}
  end

  defp insert_note!(db, security) do
    insert!(
      db,
      """
      INSERT INTO security_notes
        (security_id, author, kind, body, source_quality, as_of, inserted_at)
      VALUES ($1, 'agent', 'thesis', 'A synthetic thesis.', 'primary', '2026-10-01',
              LOCALTIMESTAMP(0))
      RETURNING id
      """,
      [security]
    )
  end

  defp insert_prediction!(db, security, note) do
    SeededUpgrade.query!(
      db,
      """
      INSERT INTO predictions
        (security_id, direction, probability, benchmark_kind, benchmark_rate, resolves_on,
         made_at, author, model, note_id)
      VALUES ($1, 'outperform', 0.60, 'rate', 0,
              (now() AT TIME ZONE 'UTC')::date + 30, now() AT TIME ZONE 'UTC',
              'agent', 'example-model-1', $2)
      """,
      [security, note]
    )
  end

  defp row(columns) do
    placeholders = Enum.map_join(1..length(columns), ", ", &"$#{&1}")

    "(#{Enum.join(columns, ", ")}, inserted_at, updated_at) " <>
      "VALUES (#{placeholders}, LOCALTIMESTAMP(0), LOCALTIMESTAMP(0)) RETURNING id"
  end

  defp insert!(db, sql, params) do
    %{rows: [[id]]} = SeededUpgrade.query!(db, sql, params)
    id
  end
end
