defmodule Portfolixir.SeededUpgrade.DashboardsGridTest do
  # Sprint 32 E4 (ADR-0062's amendment of 2026-11-25, point 3): the
  # migration that records the grid a dashboard's layout was written on,
  # run over the dashboards an upgrading Sprint 31 instance holds
  # (docs/development/guide.md, "Upgrade migrations over legacy rows").
  # Every name is synthetic.
  #
  # async: false -- see Portfolixir.SeededUpgrade, "Where the cases run".
  use ExUnit.Case, async: false

  alias Portfolixir.Dashboards
  alias Portfolixir.Dashboards.Layout
  alias Portfolixir.Dashboards.Templates
  alias Portfolixir.ScratchDatabase
  alias Portfolixir.SeededUpgrade

  @moduletag :seeded_upgrade

  # Sprint 31's migration that created the table, and this one.
  @dashboards 20_261_121_120_000
  @grid 20_261_125_120_000

  # „Überblick“ exactly as Sprint 31 stored every copy of it, in the old
  # names (S 3 × 1, W 6 × 1, M 6 × 2, T 4 × 3, L 8 × 3).
  @sprint31_overview [
    %{"kind" => "total_value", "size" => "S", "col" => 1, "row" => 1, "settings" => %{}},
    %{"kind" => "data_quality", "size" => "S", "col" => 4, "row" => 1, "settings" => %{}},
    %{"kind" => "due", "size" => "S", "col" => 7, "row" => 1, "settings" => %{}},
    %{"kind" => "off_target", "size" => "S", "col" => 10, "row" => 1, "settings" => %{}},
    %{"kind" => "performance", "size" => "L", "col" => 1, "row" => 2, "settings" => %{}},
    %{"kind" => "allocation_drift", "size" => "T", "col" => 9, "row" => 2, "settings" => %{}},
    %{"kind" => "movers", "size" => "M", "col" => 1, "row" => 5, "settings" => %{}},
    %{"kind" => "crashes", "size" => "M", "col" => 7, "row" => 5, "settings" => %{}},
    %{"kind" => "bitcoin_cycle", "size" => "M", "col" => 1, "row" => 7, "settings" => %{}},
    %{"kind" => "sale_review", "size" => "M", "col" => 7, "row" => 7, "settings" => %{}},
    %{"kind" => "snapshots", "size" => "S", "col" => 1, "row" => 9, "settings" => %{}}
  ]

  # User story (ADR-0062's amendment of 2026-11-25, point 3):
  # As the operator upgrading an instance that stores Sprint 31's
  # „Überblick“,
  # I want it to come through the update whole and read on the new sizes,
  # so that the update changes how my dashboard looks, never what it holds.
  #
  # Acceptance criteria:
  # - Seeded with a copy of Sprint 31's „Überblick“ and an empty dashboard,
  #   the database migrates through the grid's column; both read grid 1,
  #   their layouts as stored, nothing rewritten.
  # - Read through the context after the upgrade, the copy is the new
  #   template on Apple's families: all eleven widgets, in their order, no
  #   two overlapping.
  # - A dashboard stored after the upgrade without naming its grid reads
  #   2; a grid other than 1 or 2 is refused by the database's check.
  @tag seeded_upgrade: 20_261_125_120_000
  test "the grid column keeps every stored layout and reads it on the families",
       %{seeded_upgrade: migration} do
    upgrade = SeededUpgrade.upgrade!(from: @dashboards, to: @grid, seed: &seed_dashboards/1)

    assert upgrade.migrated == [migration]
    [copy, empty] = upgrade.seeded

    assert %{rows: [[1, stored], [1, []]]} =
             SeededUpgrade.query!(upgrade, "SELECT grid, layout FROM dashboards ORDER BY id")

    assert stored == @sprint31_overview

    # The context reads today's schema (Sprint 32 S1 added the dashboard's
    # own view and origin after this migration), so the read runs on the
    # head; no later migration rewrites a layout.
    ScratchDatabase.migrate!(upgrade, SeededUpgrade.head(), upgrade.migrations)

    read = ScratchDatabase.run(upgrade, fn -> Dashboards.get_dashboard(copy) end)
    {:ok, template} = Templates.fetch("overview")
    assert read.layout == template.layout
    assert {:ok, _} = Layout.validate(read.layout)
    assert ScratchDatabase.run(upgrade, fn -> Dashboards.get_dashboard(empty) end).layout == []

    SeededUpgrade.journaled!(upgrade, fn ->
      SeededUpgrade.query!(
        upgrade,
        "INSERT INTO dashboards (name, position, inserted_at, updated_at) " <>
          "VALUES ('Danach', 3, now(), now())"
      )
    end)

    assert %{rows: [[2]]} =
             SeededUpgrade.query!(upgrade, "SELECT grid FROM dashboards WHERE name = 'Danach'")

    error =
      assert_raise Postgrex.Error, fn ->
        SeededUpgrade.journaled!(upgrade, fn ->
          SeededUpgrade.query!(upgrade, "UPDATE dashboards SET grid = 3 WHERE id = $1", [copy])
        end)
      end

    assert %{postgres: %{constraint: "dashboards_grid_check"}} = error
  end

  defp seed_dashboards(db) do
    for {name, position, layout} <- [{"Überblick", 1, @sprint31_overview}, {"Leer", 2, []}] do
      %{rows: [[id]]} =
        SeededUpgrade.query!(
          db,
          """
          INSERT INTO dashboards (name, position, layout, inserted_at, updated_at)
          VALUES ($1, $2, $3, now(), now())
          RETURNING id
          """,
          [name, position, layout]
        )

      id
    end
  end
end
