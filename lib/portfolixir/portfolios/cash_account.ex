defmodule Portfolixir.Portfolios.CashAccount do
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Portfolios.Portfolio

  schema "cash_accounts" do
    field(:name, :string)
    field(:currency_code, :string)
    field(:notes, :string)

    belongs_to(:portfolio, Portfolio)

    timestamps()
  end

  def changeset(cash_account, attrs) do
    cash_account
    |> cast(attrs, [:portfolio_id, :name, :currency_code, :notes])
    |> normalize_currency_code()
    |> validate_required([:portfolio_id, :name, :currency_code])
    |> validate_length(:currency_code, is: 3)
    |> assoc_constraint(:portfolio)
  end

  defp normalize_currency_code(changeset) do
    update_change(changeset, :currency_code, fn
      value when is_binary(value) -> value |> String.trim() |> String.upcase()
      value -> value
    end)
  end
end
