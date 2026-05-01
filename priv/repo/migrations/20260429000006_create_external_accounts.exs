defmodule Portfolixir.Repo.Migrations.CreateExternalAccounts do
  use Ecto.Migration

  def change do
    create table(:external_accounts) do
      add(:provider, :string, null: false)
      add(:external_id, :string, null: false)
      add(:external_name, :string)
      add(:external_type, :string)
      add(:currency_code, :string)
      add(:status, :string, default: "active", null: false)
      add(:deposit_account_id, references(:deposit_accounts, on_delete: :restrict))
      add(:securities_account_id, references(:securities_accounts, on_delete: :restrict))
      add(:metadata, :map, default: "{}")

      timestamps()
    end

    create(index(:external_accounts, [:provider]))
    create(index(:external_accounts, [:external_id]))
    create(index(:external_accounts, [:deposit_account_id]))
    create(index(:external_accounts, [:securities_account_id]))

    create(
      unique_index(
        :external_accounts,
        [:provider, :external_id],
        name: :external_accounts_provider_external_id_uq
      )
    )
  end
end
