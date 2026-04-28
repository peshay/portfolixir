defmodule Portfolixir.Portfolios.SecuritiesAccount do
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Catalog.Currency
  alias Portfolixir.Portfolios.DepositAccount
  alias Portfolixir.Portfolios.Portfolio

  schema "securities_accounts" do
    field(:name, :string)
    field(:active, :boolean, default: true)
    field(:notes, :string)

    belongs_to(:portfolio, Portfolio)
    belongs_to(:reference_deposit_account, DepositAccount)

    belongs_to(:currency, Currency,
      foreign_key: :currency_code,
      references: :code,
      type: :string,
      define_field: true
    )

    timestamps()
  end

  @doc false
  def changeset(securities_account, attrs) do
    securities_account
    |> cast(attrs, [
      :portfolio_id,
      :reference_deposit_account_id,
      :name,
      :currency_code,
      :active,
      :notes
    ])
    |> validate_required([:portfolio_id, :name, :currency_code])
    |> assoc_constraint(:portfolio)
    |> foreign_key_constraint(:reference_deposit_account_id)
    |> foreign_key_constraint(:reference_deposit_account_id,
      name: :securities_accounts_reference_deposit_account_portfolio_fkey
    )
    |> assoc_constraint(:currency)
  end
end
