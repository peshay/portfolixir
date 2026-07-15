defmodule Portfolixir.Repo.Migrations.CreateSettings do
  use Ecto.Migration

  # Minimal keyed preference store (ADR-0024 user-facing consequences): the
  # user-settable default view and dismissed one-time notices must live
  # server-side because the LiveView mount needs them before any client
  # storage could be read. One row per key, values as plain strings.
  def change do
    create table(:settings) do
      add(:key, :string, null: false)
      add(:value, :string, null: false)

      timestamps()
    end

    create(unique_index(:settings, [:key]))
  end
end
