defmodule Portfolixir.Repo.Migrations.AddCategoryDescription do
  use Ecto.Migration

  def change do
    alter table(:classification_categories) do
      add(:description, :text, null: true)
    end
  end
end
