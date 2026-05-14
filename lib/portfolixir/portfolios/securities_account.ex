defmodule Portfolixir.Portfolios.SecuritiesAccount do
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.Portfolio

  schema "securities_accounts" do
    field(:name, :string)
    field(:notes, :string)

    belongs_to(:portfolio, Portfolio)
    belongs_to(:cash_account, CashAccount)

    timestamps()
  end

  def changeset(securities_account, attrs) do
    securities_account
    |> cast(attrs, [:portfolio_id, :cash_account_id, :name, :notes])
    |> validate_required([:portfolio_id, :cash_account_id, :name])
    |> assoc_constraint(:portfolio)
    |> assoc_constraint(:cash_account)
    |> foreign_key_constraint(:cash_account_id,
      name: :securities_accounts_cash_account_portfolio_fkey
    )
  end
end
