defmodule Portfolixir.Repo.Migrations.CreateSecurityQuotes do
  use Ecto.Migration

  def change do
    create table(:security_quotes) do
      add(:security_id, references(:securities, on_delete: :restrict), null: false)
      add(:date, :date, null: false)
      add(:source, :string, null: false)

      add(
        :currency_code,
        references(:currencies, column: :code, type: :string, on_delete: :restrict),
        null: false
      )

      add(:open, :decimal)
      add(:high, :decimal)
      add(:low, :decimal)
      add(:close, :decimal, null: false)
      add(:volume, :decimal)
      add(:metadata, :map, null: false, default: "{}")

      timestamps()
    end

    create(index(:security_quotes, [:security_id]))
    create(index(:security_quotes, [:date]))
    create(index(:security_quotes, [:security_id, :date]))
    create(index(:security_quotes, [:security_id, :source, :date]))

    create(
      unique_index(:security_quotes, [:security_id, :source, :date],
        name: :security_quotes_security_id_source_date_unique_index
      )
    )
  end
end
