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
    # Cross-currency settlement (issue #388, ADR-0015). For a trade booked in
    # the security's own currency but settled through a different-currency cash
    # account, these carry the three linked figures: the trade amount in the
    # security currency, the cash amount in the settlement (account) currency,
    # and the settlement FX rate (settlement units per 1 security unit). All
    # three are nil for same-currency bookings.
    field(:security_amount, :decimal)
    field(:settlement_amount, :decimal)
    field(:settlement_fx_rate, :decimal)
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

  @doc """
  Enforces currency consistency between a transaction and its linked cash
  accounts (issue #343, revised by issue #388 / ADR-0015).

  A transaction is booked in its security's own currency. When that currency
  equals the linked cash account's currency the booking settles natively and
  carries no FX fields. When it differs (e.g. a USD security bought through a
  EUR account) the booking is a **cross-currency settlement**: instead of
  rejecting it (the original #343 policy) we require a stored
  `settlement_fx_rate` so per-position cost basis stays in the security
  currency while the cash leg settles in the account currency. The rate is
  part of the transaction data — never looked up inside the pure reducer.

  For a `cash_transfer` the counter cash account's currency must still match —
  a transfer carries a single amount in one currency and only ever moves money
  between same-currency accounts here.

  `cash_currencies` is a `%{cash_account_id => currency_code}` map supplied
  by the caller (the context loads it from the database); accounts missing
  from the map are skipped so a stale or not-yet-persisted reference is left
  to the existing `assoc_constraint`. This is pure validation: no stored
  amount is FX-converted here.
  """
  @spec validate_cash_account_currency(Ecto.Changeset.t(), %{optional(term()) => String.t()}) ::
          Ecto.Changeset.t()
  def validate_cash_account_currency(changeset, cash_currencies) when is_map(cash_currencies) do
    currency_code = get_field(changeset, :currency_code)

    changeset
    |> check_account_currency(:cash_account_id, currency_code, cash_currencies)
    |> check_counter_account_currency(currency_code, cash_currencies)
  end

  # A currency mismatch is no longer a rejection (ADR-0015): it requires a
  # stored settlement FX rate so the cross-currency settlement is auditable.
  defp check_account_currency(changeset, field, currency_code, cash_currencies) do
    account_id = get_field(changeset, field)

    case Map.get(cash_currencies, account_id) do
      nil -> changeset
      account_currency when account_currency == currency_code -> changeset
      _account_currency -> require_settlement_fx_rate(changeset)
    end
  end

  defp require_settlement_fx_rate(changeset) do
    case get_field(changeset, :settlement_fx_rate) do
      %Decimal{} = rate ->
        if Decimal.compare(rate, 0) == :gt do
          changeset
        else
          add_error(
            changeset,
            :settlement_fx_rate,
            "must be greater than 0 for a cross-currency settlement"
          )
        end

      _missing ->
        add_error(
          changeset,
          :settlement_fx_rate,
          "is required for a cross-currency settlement"
        )
    end
  end

  defp check_counter_account_currency(changeset, currency_code, cash_currencies) do
    counter_id = get_field(changeset, :counter_cash_account_id)

    case Map.get(cash_currencies, counter_id) do
      nil ->
        changeset

      counter_currency when counter_currency == currency_code ->
        changeset

      _counter_currency ->
        add_error(
          changeset,
          :counter_cash_account_id,
          "must match the transaction currency (#{currency_code})"
        )
    end
  end

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
      :security_amount,
      :settlement_amount,
      :settlement_fx_rate,
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
    |> validate_gross_amount_sign()
  end

  # Amounts are positive magnitudes — the sign comes from the kind (project
  # invariant #3). The single exception is `balance_adjustment`, whose
  # `gross_amount` is an absolute balance and may be negative (overdraft, ADR-0009).
  # `validate_number/3` ignores a nil field, so kinds without a gross_amount
  # (buy/sell/deliveries/transfers) are unaffected.
  defp validate_gross_amount_sign(changeset) do
    case get_field(changeset, :type) do
      "balance_adjustment" -> changeset
      _other -> validate_number(changeset, :gross_amount, greater_than: 0)
    end
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
