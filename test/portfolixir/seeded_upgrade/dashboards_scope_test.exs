defmodule Portfolixir.SeededUpgrade.DashboardsScopeTest do
  # Sprint 32 S1 (ADR-0062's amendment of 2026-11-25, point 4): the
  # migration that adds a dashboard's own view and its origin, run over the
  # dashboards an upgrading instance holds (docs/development/guide.md,
  # "Upgrade migrations over legacy rows"). Every name is synthetic.
  #
  # async: false -- see Portfolixir.SeededUpgrade, "Where the cases run".
  use ExUnit.Case, async: false

  alias Portfolixir.SeededUpgrade

  @moduletag :seeded_upgrade

  # The migration before this one (Lane T's saved periods, after E4's grid
  # column), and this one.
  @before 20_261_125_130_000
  @scope 20_261_125_140_000

  # User story (ADR-0062's amendment of 2026-11-25, point 4):
  # As the operator upgrading an instance that stores dashboards,
  # I want each to come through the update with no view of its own and no
  # origin, its layout untouched,
  # so that the update adds a choice and changes nothing I see.
  #
  # Acceptance criteria:
  # - Seeded with two dashboards, the database migrates through the new
  #   columns; both read `view_id` and `template_key` null, their layouts
  #   and lock_versions as stored.
  # - The new checks refuse a `view_id` below 1 and an empty or 41-character
  #   `template_key`.
  @tag seeded_upgrade: 20_261_125_140_000
  test "the own view and the origin arrive empty on every stored dashboard",
       %{seeded_upgrade: migration} do
    upgrade = SeededUpgrade.upgrade!(from: @before, to: @scope, seed: &seed/1)

    assert upgrade.migrated == [migration]
    [first, _second] = upgrade.seeded

    assert %{rows: rows} =
             SeededUpgrade.query!(
               upgrade,
               "SELECT view_id, template_key, layout, lock_version FROM dashboards ORDER BY id"
             )

    assert rows == [
             [nil, nil, [%{"kind" => "due", "size" => "S", "col" => 1, "row" => 1}], 3],
             [nil, nil, [], 1]
           ]

    for {sql, constraint} <- [
          {"UPDATE dashboards SET view_id = 0 WHERE id = $1", "dashboards_view_id_check"},
          {"UPDATE dashboards SET template_key = '' WHERE id = $1",
           "dashboards_template_key_check"},
          {"UPDATE dashboards SET template_key = repeat('k', 41) WHERE id = $1", nil}
        ] do
      error =
        assert_raise Postgrex.Error, fn ->
          SeededUpgrade.journaled!(upgrade, fn -> SeededUpgrade.query!(upgrade, sql, [first]) end)
        end

      if constraint, do: assert(%{postgres: %{constraint: ^constraint}} = error)
    end
  end

  defp seed(db) do
    for {name, position, layout, version} <- [
          {"Erstes", 1, [%{"kind" => "due", "size" => "S", "col" => 1, "row" => 1}], 3},
          {"Leer", 2, [], 1}
        ] do
      %{rows: [[id]]} =
        SeededUpgrade.query!(
          db,
          """
          INSERT INTO dashboards (name, position, layout, lock_version, inserted_at, updated_at)
          VALUES ($1, $2, $3, $4, now(), now())
          RETURNING id
          """,
          [name, position, layout, version]
        )

      id
    end
  end
end
