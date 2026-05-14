defmodule Portfolixir.Ledger.Transaction do
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Catalog.Security
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.Portfolio
  alias Portfolixir.Portfolios.SecuritiesAccount

  @manual_trade_types ["buy", "sell"]

  schema "transactions" do
    field(:type, :string)
    field(:date, :date)
    field(:quantity, :decimal)
    field(:price, :decimal)
    field(:fees, :decimal, default: Decimal.new("0"))
    field(:taxes, :decimal, default: Decimal.new("0"))
    field(:currency_code, :string)
    field(:notes, :string)

    belongs_to(:portfolio, Portfolio)
    belongs_to(:securities_account, SecuritiesAccount)
    belongs_to(:cash_account, CashAccount)
    belongs_to(:security, Security)

    timestamps()
  end

  def manual_trade_types, do: @manual_trade_types

  def changeset(transaction, attrs) do
    transaction
    |> cast(attrs, [
      :portfolio_id,
      :securities_account_id,
      :cash_account_id,
      :security_id,
      :type,
      :date,
      :quantity,
      :price,
      :fees,
      :taxes,
      :currency_code,
      :notes
    ])
    |> normalize_currency_code()
    |> put_decimal_default(:fees)
    |> put_decimal_default(:taxes)
    |> validate_required([
      :portfolio_id,
      :securities_account_id,
      :cash_account_id,
      :security_id,
      :type,
      :date,
      :quantity,
      :price,
      :fees,
      :taxes,
      :currency_code
    ])
    |> validate_inclusion(:type, @manual_trade_types)
    |> validate_length(:currency_code, is: 3)
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:price, greater_than: 0)
    |> validate_number(:fees, greater_than_or_equal_to: 0)
    |> validate_number(:taxes, greater_than_or_equal_to: 0)
    |> assoc_constraint(:portfolio)
    |> assoc_constraint(:security)
    |> assoc_constraint(:cash_account)
    |> assoc_constraint(:securities_account)
    |> foreign_key_constraint(:cash_account_id, name: :transactions_cash_account_portfolio_fkey)
    |> foreign_key_constraint(:securities_account_id,
      name: :transactions_securities_account_portfolio_fkey
    )
    |> check_constraint(:type, name: :transactions_manual_trade_type_check)
  end

  defp normalize_currency_code(changeset) do
    update_change(changeset, :currency_code, fn
      value when is_binary(value) -> value |> String.trim() |> String.upcase()
      value -> value
    end)
  end

  defp put_decimal_default(changeset, field) do
    case get_field(changeset, field) do
      nil -> put_change(changeset, field, Decimal.new("0"))
      _value -> changeset
    end
  end
end
