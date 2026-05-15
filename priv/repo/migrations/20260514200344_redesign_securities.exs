defmodule Portfolixir.Repo.Migrations.RedesignSecurities do
  use Ecto.Migration

  def up do
    drop_if_exists(unique_index(:security_quotes, [:security_id, :source, :date]))
    drop_if_exists(index(:security_quotes, [:security_id, :date]))
    drop_if_exists(table(:security_quotes))

    drop_if_exists(unique_index(:securities, [:symbol, :currency_code]))
    drop_if_exists(index(:securities, [:symbol]))

    rename(table(:securities), :symbol, to: :ticker_symbol)
    rename(table(:securities), :notes, to: :note)

    alter table(:securities) do
      modify(:ticker_symbol, :string, null: true)
      add(:wkn, :string)
      add(:asset_class, :string)
      add(:feed, :string)
      add(:feed_url, :string)
      add(:latest_feed, :string)
      add(:latest_feed_url, :string)
      add(:is_retired, :boolean, default: false, null: false)
      add(:online_id, :string)
      add(:provider, :string)
      add(:attributes, :map, default: %{}, null: false)
    end

    create(index(:securities, [:ticker_symbol]))
    create(index(:securities, [:asset_class]))
    create(index(:securities, [:provider]))

    create(
      unique_index(:securities, [:provider, :online_id],
        where: "online_id IS NOT NULL",
        name: :securities_provider_online_id_unique_index
      )
    )

    create(
      unique_index(:securities, [:isin],
        where: "isin IS NOT NULL",
        name: :securities_isin_unique_index
      )
    )
  end

  def down do
    drop_if_exists(unique_index(:securities, [:isin], name: :securities_isin_unique_index))

    drop_if_exists(
      unique_index(:securities, [:provider, :online_id],
        name: :securities_provider_online_id_unique_index
      )
    )

    drop_if_exists(index(:securities, [:provider]))
    drop_if_exists(index(:securities, [:asset_class]))
    drop_if_exists(index(:securities, [:ticker_symbol]))

    alter table(:securities) do
      remove(:attributes)
      remove(:provider)
      remove(:online_id)
      remove(:is_retired)
      remove(:latest_feed_url)
      remove(:latest_feed)
      remove(:feed_url)
      remove(:feed)
      remove(:asset_class)
      remove(:wkn)
      modify(:ticker_symbol, :string, null: false)
    end

    rename(table(:securities), :note, to: :notes)
    rename(table(:securities), :ticker_symbol, to: :symbol)

    create(index(:securities, [:symbol]))
    create(unique_index(:securities, [:symbol, :currency_code]))

    create table(:security_quotes) do
      add(:security_id, references(:securities, on_delete: :restrict), null: false)
      add(:date, :date, null: false)
      add(:source, :string, null: false, default: "manual")
      add(:currency_code, :string, null: false)
      add(:open, :decimal, precision: 20, scale: 6)
      add(:high, :decimal, precision: 20, scale: 6)
      add(:low, :decimal, precision: 20, scale: 6)
      add(:close, :decimal, precision: 20, scale: 6, null: false)
      add(:volume, :decimal, precision: 30, scale: 6)

      timestamps()
    end

    create(index(:security_quotes, [:security_id, :date]))
    create(unique_index(:security_quotes, [:security_id, :source, :date]))
  end
end
