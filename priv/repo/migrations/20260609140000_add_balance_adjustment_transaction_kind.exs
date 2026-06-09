defmodule Portfolixir.Repo.Migrations.AddBalanceAdjustmentTransactionKind do
  use Ecto.Migration

  # Adds a 14th transaction kind, `balance_adjustment`: a dated absolute
  # cash-balance snapshot (see ADR-0009). Unlike the other kinds it asserts the
  # account's balance as of its date rather than a signed delta; the balance
  # derivation anchors on the latest snapshot and only applies later bookings.
  #
  # Required fields mirror the deposit/removal cash kinds (cash_account_id and
  # gross_amount), but gross_amount here is the absolute balance and may be
  # negative (an overdraft), so no positivity check is added.

  @with_snapshot "type IN ('buy', 'sell', 'dividend', 'interest', 'deposit', 'removal', 'fee', 'tax', 'tax_refund', 'cash_transfer', 'inbound_delivery', 'outbound_delivery', 'security_transfer', 'balance_adjustment')"

  @without_snapshot "type IN ('buy', 'sell', 'dividend', 'interest', 'deposit', 'removal', 'fee', 'tax', 'tax_refund', 'cash_transfer', 'inbound_delivery', 'outbound_delivery', 'security_transfer')"

  def up do
    drop(constraint(:transactions, :transactions_type_check))
    create(constraint(:transactions, :transactions_type_check, check: @with_snapshot))

    create(
      constraint(:transactions, :transactions_balance_adjustment_required_fields_check,
        check: """
        type <> 'balance_adjustment' OR (
          cash_account_id IS NOT NULL AND
          gross_amount IS NOT NULL
        )
        """
      )
    )
  end

  def down do
    drop(constraint(:transactions, :transactions_balance_adjustment_required_fields_check))
    drop(constraint(:transactions, :transactions_type_check))
    create(constraint(:transactions, :transactions_type_check, check: @without_snapshot))
  end
end
