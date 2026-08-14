defmodule Portfolixir.Repo.Migrations.CreateDerivedValues do
  use Ecto.Migration

  # ADR-0039: durable derived values. Both tables are materializations of the
  # single ledger truth — rebuildable, versioned, never journaled (a
  # derived-value write is not a financial write; `write_actor_test.exs` names
  # this table class explicitly) and never read by a write path (I7).
  def change do
    # Append-only version events: a basis's data version is the highest event
    # id recorded for it. Deliberately NOT an incremented counter row — an
    # `UPDATE ... SET version = version + 1` would hold a row lock for the
    # whole writing transaction, serializing every concurrent financial write
    # on the shared "global" row. Inserts never contend.
    create table(:derived_data_version_events) do
      add(:basis, :string, null: false)
    end

    create(index(:derived_data_version_events, [:basis, :id]))

    create table(:derived_values) do
      add(:analytic_id, :string, null: false)
      add(:basis, :string, null: false)
      add(:entry_key, :string, null: false)
      add(:data_version, :bigint, null: false)
      add(:computation_version, :integer, null: false)
      add(:as_of, :utc_datetime, null: false)
      add(:payload, :binary, null: false)

      timestamps(type: :utc_datetime)
    end

    create(unique_index(:derived_values, [:analytic_id, :basis, :entry_key]))
  end
end
