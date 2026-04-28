defmodule Portfolixir.Portfolios.DepositAccount do
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Catalog.Currency
  alias Portfolixir.Portfolios.Portfolio

  schema "deposit_accounts" do
    field(:name, :string)
    field(:active, :boolean, default: true)
    field(:notes, :string)

    belongs_to(:portfolio, Portfolio)

    belongs_to(:currency, Currency,
      foreign_key: :currency_code,
      references: :code,
      type: :string,
      define_field: true
    )

    timestamps()
  end

  @doc false
  def changeset(deposit_account, attrs) do
    deposit_account
    |> cast(attrs, [:portfolio_id, :name, :currency_code, :active, :notes])
    |> validate_required([:portfolio_id, :name, :currency_code])
    |> assoc_constraint(:portfolio)
    |> assoc_constraint(:currency)
  end
end
