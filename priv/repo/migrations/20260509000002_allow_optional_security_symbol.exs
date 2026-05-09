defmodule Portfolixir.Repo.Migrations.AllowOptionalSecuritySymbol do
  use Ecto.Migration

  def change do
    alter table(:securities) do
      modify(:symbol, :string, null: true)
    end
  end
end
