defmodule Portfolixir.Repo.Migrations.AddWknToSecurities do
  use Ecto.Migration

  def change do
    alter table(:securities) do
      add(:wkn, :string)
    end
  end
end
