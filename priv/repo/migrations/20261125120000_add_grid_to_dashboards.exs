defmodule Portfolixir.Repo.Migrations.AddGridToDashboards do
  @moduledoc """
  Sprint 32 E4 (ADR-0062's amendment of 2026-11-25, point 3): the grid a
  dashboard's layout was written on. Every dashboard stored before this
  migration was written on Sprint 31's grid (1: the sizes S, W, M, T and L
  on rows that grew with their content) and reads 1; every write of a
  layout from now on stores today's grid (2: Apple's families S, M, L and
  XL on rows of a fixed height). `Portfolixir.Dashboards.Grid` reads a
  layout of grid 1 on grid 2; nothing is rewritten here, so the next save
  stores it, journaled under its actor.
  """
  use Ecto.Migration

  def up do
    alter table(:dashboards) do
      add(:grid, :smallint, null: false, default: 1)
    end

    execute("ALTER TABLE dashboards ALTER COLUMN grid SET DEFAULT 2")
    create(constraint(:dashboards, :dashboards_grid_check, check: "grid IN (1, 2)"))
  end

  def down do
    drop(constraint(:dashboards, :dashboards_grid_check))

    alter table(:dashboards) do
      remove(:grid)
    end
  end
end
