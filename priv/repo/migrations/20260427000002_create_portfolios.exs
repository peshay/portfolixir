defmodule Portfolixir.Repo.Migrations.CreatePortfolios do
  use Ecto.Migration

  def change do
    create table(:portfolios) do
      add(:name, :string, null: false)
      add(:description, :text)

      add(
        :base_currency_code,
        references(:currencies, column: :code, type: :string, on_delete: :restrict),
        null: false
      )

      timestamps()
    end

    create(index(:portfolios, [:base_currency_code]))
  end
end
