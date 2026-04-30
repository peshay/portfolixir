defmodule Portfolixir.Repo.Migrations.CreateFundAllocationItems do
  use Ecto.Migration

  def change do
    create table(:fund_allocation_items) do
      add(:fund_allocation_id, references(:fund_allocations, on_delete: :delete_all), null: false)
      add(:label, :string, null: false)
      add(:weight, :decimal, null: false)
      add(:confidence, :decimal)
      add(:metadata, :map, null: false, default: "{}")

      timestamps()
    end

    create(index(:fund_allocation_items, [:fund_allocation_id]))

    create(
      unique_index(
        :fund_allocation_items,
        [:fund_allocation_id, :label],
        name: :fund_allocation_items_fund_allocation_id_label_unique_index
      )
    )
  end
end
