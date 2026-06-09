defmodule Portfolixir.Ledger.Transaction do
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Catalog.Security
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.Portfolio
  alias Portfolixir.Portfolios.SecuritiesAccount

  @manual_trade_types ["buy", "sell"]
  @kinds [
    "buy",
    "sell",
    "dividend",
    "interest",
    "deposit",
    "removal",
    "fee",
    "tax",
    "tax_refund",
    "cash_transfer",
    "inbound_delivery",
    "outbound_delivery",
    "security_transfer",
    "balance_adjustment"
  ]

  schema "transactions" do
    field(:type, :string)
    field(:date, :date)
    field(:quantity, :decimal)
    field(:price, :decimal)
    field(:fees, :decimal, default: Decimal.new("0"))
    field(:taxes, :decimal, default: Decimal.new("0"))
    field(:gross_amount, :decimal)
    field(:currency_code, :string)
    field(:notes, :string)
    field(:import_hash, :string)

    belongs_to(:portfolio, Portfolio)
    belongs_to(:securities_account, SecuritiesAccount)
    belongs_to(:cash_account, CashAccount)
    belongs_to(:security, Security)
    belongs_to(:counter_cash_account, CashAccount, foreign_key: :counter_cash_account_id)

    belongs_to(:counter_securities_account, SecuritiesAccount,
      foreign_key: :counter_securities_account_id
    )

    timestamps()
  end

  def manual_trade_types, do: @manual_trade_types
  def kinds, do: @kinds

  def changeset(transaction, attrs) do
    transaction
    |> cast(attrs, [
      :portfolio_id,
      :securities_account_id,
      :cash_account_id,
      :counter_cash_account_id,
      :counter_securities_account_id,
      :security_id,
      :type,
      :date,
      :quantity,
      :price,
      :fees,
      :taxes,
      :gross_amount,
      :currency_code,
      :notes,
      :import_hash
    ])
    |> normalize_currency_code()
    |> put_decimal_default(:fees)
    |> put_decimal_default(:taxes)
    |> validate_required([:portfolio_id, :type, :date, :currency_code])
    |> validate_inclusion(:type, @kinds)
    |> validate_length(:currency_code, is: 3)
    |> validate_required_for_kind()
    |> validate_decimal_signs()
    |> assoc_constraint(:portfolio)
    |> assoc_constraint(:security)
    |> assoc_constraint(:cash_account)
    |> assoc_constraint(:securities_account)
    |> assoc_constraint(:counter_cash_account)
    |> assoc_constraint(:counter_securities_account)
    |> foreign_key_constraint(:cash_account_id, name: :transactions_cash_account_portfolio_fkey)
    |> foreign_key_constraint(:securities_account_id,
      name: :transactions_securities_account_portfolio_fkey
    )
    |> foreign_key_constraint(:counter_cash_account_id,
      name: :transactions_counter_cash_account_portfolio_fkey
    )
    |> foreign_key_constraint(:counter_securities_account_id,
      name: :transactions_counter_securities_account_portfolio_fkey
    )
    |> check_constraint(:type, name: :transactions_type_check)
    |> check_constraint(:type, name: :transactions_buy_sell_required_fields_check)
    |> check_constraint(:type, name: :transactions_dividend_required_fields_check)
    |> check_constraint(:type, name: :transactions_cash_only_required_fields_check)
    |> check_constraint(:type, name: :transactions_fee_tax_required_fields_check)
    |> check_constraint(:type, name: :transactions_cash_transfer_required_fields_check)
    |> check_constraint(:type, name: :transactions_delivery_required_fields_check)
    |> check_constraint(:type, name: :transactions_security_transfer_required_fields_check)
    |> check_constraint(:type, name: :transactions_balance_adjustment_required_fields_check)
    |> unique_constraint(:import_hash, name: :transactions_import_hash_unique_index)
  end

  # Per-kind required-field matrix. Keep this aligned with the per-kind
  # CHECK constraints in
  # priv/repo/migrations/20260517100000_extend_transactions_for_pp_import.exs.
  defp validate_required_for_kind(changeset) do
    case get_field(changeset, :type) do
      kind when kind in ["buy", "sell"] ->
        # `price >= 0` (not strict > 0) so spin-offs, free-allotments
        # and worthless write-offs in PP exports import cleanly.
        changeset
        |> validate_required([
          :security_id,
          :securities_account_id,
          :cash_account_id,
          :quantity,
          :price
        ])
        |> validate_number(:quantity, greater_than: 0)
        |> validate_number(:price, greater_than_or_equal_to: 0)

      "dividend" ->
        changeset
        |> validate_required([:security_id, :cash_account_id, :gross_amount])

      kind when kind in ["interest", "deposit", "removal"] ->
        changeset
        |> validate_required([:cash_account_id, :gross_amount])

      # gross_amount is the absolute balance, so it may be negative (overdraft).
      "balance_adjustment" ->
        changeset
        |> validate_required([:cash_account_id, :gross_amount])

      kind when kind in ["fee", "tax", "tax_refund"] ->
        changeset
        |> validate_required([:cash_account_id, :gross_amount])

      "cash_transfer" ->
        changeset
        |> validate_required([:cash_account_id, :counter_cash_account_id, :gross_amount])
        |> validate_distinct_accounts(:cash_account_id, :counter_cash_account_id)

      kind when kind in ["inbound_delivery", "outbound_delivery"] ->
        changeset
        |> validate_required([:security_id, :securities_account_id, :quantity])
        |> validate_number(:quantity, greater_than: 0)

      "security_transfer" ->
        changeset
        |> validate_required([
          :security_id,
          :securities_account_id,
          :counter_securities_account_id,
          :quantity
        ])
        |> validate_distinct_accounts(:securities_account_id, :counter_securities_account_id)
        |> validate_number(:quantity, greater_than: 0)

      _other ->
        changeset
    end
  end

  defp validate_distinct_accounts(changeset, field, counter_field) do
    a = get_field(changeset, field)
    b = get_field(changeset, counter_field)

    if not is_nil(a) and not is_nil(b) and a == b do
      add_error(changeset, counter_field, "must differ from #{field}")
    else
      changeset
    end
  end

  defp validate_decimal_signs(changeset) do
    changeset
    |> validate_number(:fees, greater_than_or_equal_to: 0)
    |> validate_number(:taxes, greater_than_or_equal_to: 0)
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
