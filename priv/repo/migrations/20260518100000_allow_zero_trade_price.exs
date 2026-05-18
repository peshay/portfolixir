defmodule Portfolixir.Repo.Migrations.AllowZeroTradePrice do
  use Ecto.Migration

  # Portfolio Performance permits buy/sell rows with price = 0 (spin-offs,
  # free allotments, worthless write-offs). The original check constraint
  # required `price > 0`, which rejected legitimate PP rows on import.
  #
  # Relax to `price >= 0`. Quantity remains strictly `> 0` because zero-
  # quantity trades have no semantics in the ledger.

  def up do
    drop(constraint(:transactions, :transactions_buy_sell_required_fields_check))

    create(
      constraint(:transactions, :transactions_buy_sell_required_fields_check,
        check: """
        type NOT IN ('buy', 'sell') OR (
          security_id IS NOT NULL AND
          securities_account_id IS NOT NULL AND
          cash_account_id IS NOT NULL AND
          quantity IS NOT NULL AND quantity > 0 AND
          price IS NOT NULL AND price >= 0
        )
        """
      )
    )
  end

  def down do
    drop(constraint(:transactions, :transactions_buy_sell_required_fields_check))

    create(
      constraint(:transactions, :transactions_buy_sell_required_fields_check,
        check: """
        type NOT IN ('buy', 'sell') OR (
          security_id IS NOT NULL AND
          securities_account_id IS NOT NULL AND
          cash_account_id IS NOT NULL AND
          quantity IS NOT NULL AND quantity > 0 AND
          price IS NOT NULL AND price > 0
        )
        """
      )
    )
  end
end
