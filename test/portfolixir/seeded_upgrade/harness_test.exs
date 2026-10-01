defmodule Portfolixir.SeededUpgrade.HarnessTest do
  # The seeded-upgrade harness's own failure paths (Sprint 17, Lane G-1,
  # #995), run for real in CI: over a directory of two synthetic migrations,
  # a CHECK that a seeded row breaks stops the upgrade, and the case fails
  # naming the migration and the database's error -- the in-CI form of the
  # mutation evidence the Sprint 16 cases were verified with.
  #
  # async: false -- see Portfolixir.SeededUpgrade, "Where the cases run".
  use ExUnit.Case, async: false

  alias Portfolixir.SeededUpgrade

  @moduletag :seeded_upgrade

  @create 20_990_101_000_001
  @bound 20_990_101_000_002

  setup do
    dir = Path.join(System.tmp_dir!(), "seeded-upgrade-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    write_migration!(dir, "#{@create}_create_upgrade_widgets.exs", "CreateUpgradeWidgets", """
    create table(:upgrade_widgets) do
      add :size, :integer, null: false
    end
    """)

    write_migration!(dir, "#{@bound}_bound_upgrade_widgets.exs", "BoundUpgradeWidgets", """
    create constraint(:upgrade_widgets, :upgrade_widgets_size_check, check: "size > 0")
    """)

    %{migrations: dir}
  end

  # User story:
  # As the maintainer relying on a seeded case to stop a release that would
  # not boot,
  # I want the harness to fail the case when a migration stops on a seeded
  # row, naming that migration and the database's error,
  # so that the failure reads like the boot it prevents.
  #
  # Acceptance criteria:
  # - Seeded with a row the second migration's CHECK refuses, the case fails
  #   naming the version it started from, the migration it stopped at and the
  #   check violation.
  # - Seeded with a row the CHECK accepts, the upgrade runs the second
  #   migration and hands the test the seed's result and the migrated rows.
  # - A `from` that names no migration fails before any database is made.
  test "a migration that stops on a seeded row fails the case, naming it and the error", %{
    migrations: dir
  } do
    error =
      assert_raise ExUnit.AssertionError, fn ->
        SeededUpgrade.upgrade!(from: @create, seed: &widget!(&1, 0), migrations: dir)
      end

    assert error.message =~
             "the upgrade from #{@create} to head stopped at #{@bound}_bound_upgrade_widgets.exs:"

    assert error.message =~ "ERROR 23514 (check_violation)"
    assert error.message =~ "upgrade_widgets_size_check"
  end

  test "over rows the migration accepts, the upgrade runs to the directory's head", %{
    migrations: dir
  } do
    upgrade = SeededUpgrade.upgrade!(from: @create, seed: &widget!(&1, 5), migrations: dir)

    assert upgrade.migrated == [@bound]

    assert %{rows: [[5]]} =
             SeededUpgrade.query!(upgrade, "SELECT size FROM upgrade_widgets WHERE id = $1", [
               upgrade.seeded
             ])
  end

  test "a from version that names no migration fails before a database is made", %{
    migrations: dir
  } do
    assert_raise ExUnit.AssertionError, ~r/20990101000009 is not a migration in /, fn ->
      SeededUpgrade.upgrade!(from: 20_990_101_000_009, seed: &widget!(&1, 5), migrations: dir)
    end
  end

  defp widget!(db, size) do
    %{rows: [[id]]} =
      SeededUpgrade.query!(db, "INSERT INTO upgrade_widgets (size) VALUES ($1) RETURNING id", [
        size
      ])

    id
  end

  defp write_migration!(dir, file, name, body) do
    File.write!(Path.join(dir, file), """
    defmodule Portfolixir.SeededUpgrade.HarnessTest.#{name} do
      use Ecto.Migration

      def change do
    #{body}
      end
    end
    """)
  end
end
