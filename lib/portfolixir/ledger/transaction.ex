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
    "balance_adjustment",
    "split"
  ]

  # A split (ADR-0028) records only security + date + ratio; every
  # cash/price/quantity field of the additive kinds must stay blank.
  @split_blank_fields [
    :quantity,
    :price,
    :gross_amount,
    :security_amount,
    :settlement_amount,
    :settlement_fx_rate,
    :cash_account_id,
    :counter_cash_account_id,
    :securities_account_id,
    :counter_securities_account_id
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
    # Split ratio as a pair of positive integers (ADR-0028): 10:1 forward,
    # 1:10 reverse. Normalized to lowest terms at write time; nil for every
    # other kind. Integers keep a 1:3 reverse split exact where a decimal
    # ratio cannot.
    field(:split_ratio_numerator, :integer)
    field(:split_ratio_denominator, :integer)

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

  @public_fields [
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
    :split_ratio_numerator,
    :split_ratio_denominator
  ]

  @doc """
  The public changeset: what the UI and the API may set. `import_hash` is not
  among the fields and is refused when present (#766): it says "this row came
  from an import", and only the importer may say so — a caller-set hash could
  make a later import skip a row or fail its unique index.
  """
  def changeset(transaction, attrs) do
    transaction
    |> cast(attrs, @public_fields)
    |> refuse_import_hash(attrs)
    |> validate_changeset()
  end

  @doc """
  The importer's changeset (#766): the public fields plus `import_hash`, the
  SHA-256 content hash `Portfolixir.Imports.Applier` computes.
  """
  def import_changeset(transaction, attrs) do
    transaction
    |> cast(attrs, [:import_hash | @public_fields])
    |> validate_changeset()
  end

  defp refuse_import_hash(changeset, attrs) do
    if Map.has_key?(attrs, :import_hash) or Map.has_key?(attrs, "import_hash") do
      add_error(changeset, :import_hash, "is set by the importer")
    else
      changeset
    end
  end

  defp validate_changeset(changeset) do
    changeset
    |> normalize_currency_code()
    |> put_decimal_default(:fees)
    |> put_decimal_default(:taxes)
    |> validate_required([:portfolio_id, :type, :date, :currency_code])
    |> validate_inclusion(:type, @kinds)
    |> validate_length(:currency_code, is: 3)
    |> validate_required_for_kind()
    |> validate_split_ratio_scope()
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
    |> check_constraint(:type, name: :transactions_split_required_fields_check)
    |> check_constraint(:type, name: :transactions_split_ratio_only_for_split_check)
    |> unique_constraint(:import_hash, name: :transactions_import_hash_unique_index)
    |> unique_constraint(:date,
      name: :transactions_one_split_per_portfolio_security_day_index,
      message: "a split for this security and portfolio is already booked on this date"
    )
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

      # A split (ADR-0028 §1) is security + effective date + positive integer
      # ratio pair, normalized to lowest terms at write time. It has no cash
      # leg and no price, so every additive-kind field must stay blank.
      "split" ->
        changeset
        |> validate_required([:security_id, :split_ratio_numerator, :split_ratio_denominator])
        |> validate_number(:split_ratio_numerator, greater_than: 0)
        |> validate_number(:split_ratio_denominator, greater_than: 0)
        |> normalize_split_ratio()
        |> validate_split_changes_share_count()
        |> validate_blank_split_fields()

      _other ->
        changeset
    end
  end

  # Marker encoding, import dedup identity and event equality all use the
  # normalized pair (ADR-0028 §1), so lowest terms are enforced at write time.
  defp normalize_split_ratio(changeset) do
    numerator = get_field(changeset, :split_ratio_numerator)
    denominator = get_field(changeset, :split_ratio_denominator)

    if is_integer(numerator) and is_integer(denominator) and numerator > 0 and denominator > 0 do
      gcd = Integer.gcd(numerator, denominator)

      changeset
      |> put_change(:split_ratio_numerator, div(numerator, gcd))
      |> put_change(:split_ratio_denominator, div(denominator, gcd))
    else
      changeset
    end
  end

  # A pair that normalizes to 1:1 (1:1, 5:5, ...) scales nothing and is
  # rejected as meaningless.
  defp validate_split_changes_share_count(changeset) do
    numerator = get_field(changeset, :split_ratio_numerator)
    denominator = get_field(changeset, :split_ratio_denominator)

    if numerator == 1 and denominator == 1 do
      add_error(
        changeset,
        :split_ratio_numerator,
        "must change the share count (a 1:1 split is meaningless)"
      )
    else
      changeset
    end
  end

  defp validate_blank_split_fields(changeset) do
    changeset =
      Enum.reduce(@split_blank_fields, changeset, fn field, acc ->
        case get_field(acc, field) do
          nil -> acc
          _present -> add_error(acc, field, "must be blank for a split")
        end
      end)

    # Fees and taxes default to zero on every kind; a split just may not
    # carry a non-zero amount (it has no cash leg).
    Enum.reduce([:fees, :taxes], changeset, fn field, acc ->
      case get_field(acc, field) do
        nil -> acc
        %Decimal{} = value -> if Decimal.equal?(value, 0), do: acc, else: blank_error(acc, field)
        _other -> blank_error(acc, field)
      end
    end)
  end

  defp blank_error(changeset, field), do: add_error(changeset, field, "must be blank for a split")

  # The ratio columns exist only for splits (mirrors the
  # `transactions_split_ratio_only_for_split_check` constraint).
  defp validate_split_ratio_scope(changeset) do
    case get_field(changeset, :type) do
      "split" ->
        changeset

      _other ->
        Enum.reduce([:split_ratio_numerator, :split_ratio_denominator], changeset, fn field,
                                                                                      acc ->
          case get_field(acc, field) do
            nil -> acc
            _present -> add_error(acc, field, "is only allowed for a split")
          end
        end)
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

  # The taxes rule keeps ONE representation of a refund; the message names it
  # (issue #686 gap D1) so every surface — API, MCP, any future form — hands
  # the remedy over at the exact moment the caller's intent is unambiguous.
  defp validate_decimal_signs(changeset) do
    changeset
    |> validate_number(:fees, greater_than_or_equal_to: 0)
    |> validate_number(:taxes,
      greater_than_or_equal_to: 0,
      message:
        "must be greater than or equal to 0 — a refunded tax is booked as a " <>
          "separate tax_refund transaction whose positive gross_amount credits " <>
          "the cash account"
    )
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
