defmodule Portfolixir.SeededUpgrade.SourceUrlWidthTest do
  # ADR-0056 E2 (#1443, Sprint 29 N2): `security_notes.source_url` and
  # `security_events.source_url` widen from 255 to 2,048 characters, the
  # news parser's own cap, so an aggregator's redirect link can become an
  # entry's or an event's source. The research log is append-only: the
  # widening runs over the rows an instance holds and rewrites none of them
  # (docs/development/guide.md, "Upgrade migrations over legacy rows").
  # Every value is synthetic.
  #
  # async: false -- see Portfolixir.SeededUpgrade, "Where the cases run".
  use ExUnit.Case, async: false

  alias Portfolixir.SeededUpgrade

  @moduletag :seeded_upgrade

  # The migration before the widening, and the widening itself.
  @before_widening 20_261_109_200_000
  @widening 20_261_112_150_000

  @prefix "https://example.invalid/?q="

  defp link(length), do: @prefix <> String.duplicate("a", length - String.length(@prefix))

  # User story (ADR-0056 E2):
  # As the operator upgrading an instance whose research log and calendar
  # hold entries and events with links,
  # I want the two link columns widened to 2,048 characters without a stored
  # row being rewritten,
  # so that the append-only log stays as it was written and a story whose
  # links are all long can become an entry.
  #
  # Acceptance criteria:
  # - Seeded with an entry and an event whose links are 255 characters, the
  #   database migrates through the widening; both columns are
  #   character varying(2048), and both rows keep their link, their
  #   transaction id (xmin) and their place (ctid): no row was rewritten.
  # - After the upgrade a 2,048-character link is stored in each table and a
  #   2,049-character one is refused by the database.
  # - The widening's down, with a 2,048-character link stored, is refused
  #   rather than cutting the link.
  @tag seeded_upgrade: 20_261_112_150_000
  test "the widening rewrites no stored row and holds a 2,048-character link",
       %{seeded_upgrade: migration} do
    upgrade = SeededUpgrade.upgrade!(from: @before_widening, to: @widening, seed: &seed/1)

    assert upgrade.migrated == [migration]
    %{security: security, rows: before} = upgrade.seeded

    assert %{rows: widths} =
             SeededUpgrade.query!(
               upgrade,
               "SELECT table_name, data_type, character_maximum_length " <>
                 "FROM information_schema.columns WHERE column_name = 'source_url' " <>
                 "AND table_name IN ('security_notes', 'security_events') ORDER BY table_name"
             )

    assert widths == [
             ["security_events", "character varying", 2048],
             ["security_notes", "character varying", 2048]
           ]

    assert rows(upgrade) == before
    assert Enum.all?(before, fn [_table, url, _xmin, _ctid] -> url == link(255) end)

    SeededUpgrade.journaled!(upgrade, fn ->
      insert_note!(upgrade, security, link(2048))
      insert_event!(upgrade, security, link(2048))
    end)

    for insert <- [&insert_note!/3, &insert_event!/3] do
      assert_raise Postgrex.Error, ~r/value too long for type character varying\(2048\)/, fn ->
        SeededUpgrade.journaled!(upgrade, fn -> insert.(upgrade, security, link(2049)) end)
      end
    end

    assert_raise Postgrex.Error, ~r/value too long for type character varying\(255\)/, fn ->
      SeededUpgrade.down!(upgrade, 1)
    end
  end

  defp seed(db) do
    %{rows: [[security]]} =
      SeededUpgrade.query!(
        db,
        "INSERT INTO securities (name, currency_code, inserted_at, updated_at) " <>
          "VALUES ('Alpha', 'EUR', LOCALTIMESTAMP(0), LOCALTIMESTAMP(0)) RETURNING id"
      )

    insert_note!(db, security, link(255))
    insert_event!(db, security, link(255))

    %{security: security, rows: rows(db)}
  end

  defp rows(db) do
    %{rows: rows} =
      SeededUpgrade.query!(
        db,
        """
        SELECT 'security_notes', source_url, xmin::text, ctid::text FROM security_notes
        UNION ALL
        SELECT 'security_events', source_url, xmin::text, ctid::text FROM security_events
        ORDER BY 1
        """
      )

    rows
  end

  defp insert_note!(db, security, url) do
    SeededUpgrade.query!(
      db,
      """
      INSERT INTO security_notes
        (security_id, author, kind, body, source_quality, as_of, source_url, inserted_at)
      VALUES ($1, 'agent', 'evidence', 'A synthetic entry.', 'primary', '2026-10-01', $2,
              LOCALTIMESTAMP(0))
      """,
      [security, url]
    )
  end

  defp insert_event!(db, security, url) do
    SeededUpgrade.query!(
      db,
      """
      INSERT INTO security_events
        (security_id, kind, date, timing, source_quality, source_url, inserted_at, updated_at)
      VALUES ($1, 'earnings', '2026-11-20', 'exact', 'primary', $2,
              LOCALTIMESTAMP(0), LOCALTIMESTAMP(0))
      """,
      [security, url]
    )
  end
end
