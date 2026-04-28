defmodule Portfolixir.Ledger.Transaction do
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Catalog.Currency
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Portfolios.DepositAccount
  alias Portfolixir.Portfolios.Portfolio
  alias Portfolixir.Portfolios.SecuritiesAccount

  @types ["deposit", "withdrawal", "buy", "sell", "dividend"]

  schema "transactions" do
    field(:type, :string)
    field(:date, :date)
    field(:amount, :decimal)
    field(:quantity, :decimal)
    field(:price, :decimal)
    field(:fees, :decimal)
    field(:taxes, :decimal)
    field(:notes, :string)

    belongs_to(:portfolio, Portfolio)
    belongs_to(:deposit_account, DepositAccount)
    belongs_to(:securities_account, SecuritiesAccount)
    belongs_to(:security, Security)

    belongs_to(:currency, Currency,
      foreign_key: :currency_code,
      references: :code,
      type: :string,
      define_field: true
    )

    timestamps()
  end

  @doc false
  def changeset(transaction, attrs) do
    transaction
    |> cast(attrs, [
      :portfolio_id,
      :deposit_account_id,
      :securities_account_id,
      :security_id,
      :type,
      :date,
      :currency_code,
      :amount,
      :quantity,
      :price,
      :fees,
      :taxes,
      :notes
    ])
    |> validate_required([:portfolio_id, :type, :date, :currency_code])
    |> validate_inclusion(:type, @types)
    |> validate_required_for_type()
    |> assoc_constraint(:portfolio)
    |> assoc_constraint(:currency)
    |> assoc_constraint(:security)
    |> foreign_key_constraint(:deposit_account_id)
    |> foreign_key_constraint(:deposit_account_id,
      name: :transactions_deposit_account_portfolio_fkey
    )
    |> foreign_key_constraint(:securities_account_id)
    |> foreign_key_constraint(:securities_account_id,
      name: :transactions_securities_account_portfolio_fkey
    )
    |> check_constraint(:type, name: :transactions_supported_type_check)
  end

  defp validate_required_for_type(changeset) do
    case get_field(changeset, :type) do
      "deposit" ->
        validate_required(changeset, [:deposit_account_id, :amount])

      "withdrawal" ->
        validate_required(changeset, [:deposit_account_id, :amount])

      "dividend" ->
        validate_required(changeset, [:deposit_account_id, :security_id, :amount])

      type when type in ["buy", "sell"] ->
        validate_required(changeset, [
          :securities_account_id,
          :security_id,
          :quantity,
          :price,
          :amount
        ])

      _type ->
        changeset
    end
  end
end
