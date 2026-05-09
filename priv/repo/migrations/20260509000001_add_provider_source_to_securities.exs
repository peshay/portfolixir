defmodule Portfolixir.Repo.Migrations.AddProviderSourceToSecurities do
  use Ecto.Migration

  def change do
    alter table(:securities) do
      add(:provider_source, :string)
    end

    create(index(:securities, [:provider_source]))
  end
end
