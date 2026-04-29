defmodule Portfolixir.Repo.Migrations.AddActiveToSecurities do
  use Ecto.Migration

  def change do
    alter table(:securities) do
      add(:active, :boolean, null: false, default: true)
    end
  end
end
