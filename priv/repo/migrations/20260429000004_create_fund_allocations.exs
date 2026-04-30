defmodule Portfolixir.Repo.Migrations.CreateFundAllocations do
  use Ecto.Migration

  def change do
    create table(:fund_allocations) do
      add(:security_id, references(:securities, on_delete: :restrict), null: false)
      add(:source, :string, null: false)
      add(:allocation_type, :string, null: false)
      add(:as_of_date, :date)
      add(:status, :string, null: false, default: "active")
      add(:metadata, :map, null: false, default: "{}")

      timestamps()
    end

    create(index(:fund_allocations, [:security_id]))

    create(
      unique_index(
        :fund_allocations,
        [:security_id, :allocation_type, :source, :as_of_date],
        name: :fund_allocation_uniq_not_null,
        where: "as_of_date IS NOT NULL"
      )
    )

    create(
      unique_index(
        :fund_allocations,
        [:security_id, :allocation_type, :source],
        name: :fund_allocation_uniq_null,
        where: "as_of_date IS NULL"
      )
    )
  end
end
