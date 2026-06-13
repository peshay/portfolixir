defmodule Portfolixir.Repo.Migrations.AddExcludedFromAllocationTargetsToSecurities do
  use Ecto.Migration

  def change do
    alter table(:securities) do
      add(:excluded_from_allocation_targets, :boolean, default: false, null: false)
    end
  end
end
