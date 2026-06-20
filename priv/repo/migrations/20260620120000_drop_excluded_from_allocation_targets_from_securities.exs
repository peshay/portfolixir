defmodule Portfolixir.Repo.Migrations.DropExcludedFromAllocationTargetsFromSecurities do
  use Ecto.Migration

  # Retires the per-security `excluded_from_allocation_targets` flag (ADR-0013),
  # superseded by buckets/views (ADR-0018 §4). `remove/3` carries the original
  # type and options so Ecto can reverse this migration by re-adding the column.
  def change do
    alter table(:securities) do
      remove(:excluded_from_allocation_targets, :boolean, null: false, default: false)
    end
  end
end
