defmodule Portfolixir.Repo.Migrations.CreateTaxonomies do
  use Ecto.Migration

  def change do
    create table(:taxonomies) do
      add(:name, :string, null: false)
      add(:description, :text)

      timestamps()
    end
  end
end
