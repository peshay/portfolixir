defmodule Portfolixir.Repo.Migrations.ExtendTransactionsForPpImport do
  use Ecto.Migration

  # Extends the `transactions` table from the buy/sell-only MVP to the full
  # set of 13 Portfolio-Performance transaction kinds:
  #
  #   buy, sell, dividend, interest, deposit, removal,
  #   fee, tax, tax_refund, cash_transfer,
  #   inbound_delivery, outbound_delivery, security_transfer
  #
  # The `type` column keeps its name (existing rows stay valid). New kinds
  # have different field requirements, enforced by per-kind CHECK
  # constraints below. Quantity/price/security_id/securities_account_id
  # become nullable at the table level; the per-kind checks tighten this
  # by-row.
  #
  # `import_hash` is a SHA-256 over the import payload (kind+date+security
  # +quantity+gross_amount+source-accounts), unique when present, so that
  # re-importing the same PP export is idempotent and produces zero
  # duplicate rows.

  def change do
    alter table(:transactions) do
      modify(:security_id, references(:securities, on_delete: :restrict),
        null: true,
        from: references(:securities, on_delete: :restrict)
      )

      modify(:securities_account_id, references(:securities_accounts, on_delete: :restrict),
        null: true,
        from: references(:securities_accounts, on_delete: :restrict)
      )

      modify(:cash_account_id, references(:cash_accounts, on_delete: :restrict),
        null: true,
        from: references(:cash_accounts, on_delete: :restrict)
      )

      modify(:quantity, :decimal,
        precision: 30,
        scale: 12,
        null: true,
        from: {:decimal, [precision: 30, scale: 12, null: false]}
      )

      modify(:price, :decimal,
        precision: 20,
        scale: 6,
        null: true,
        from: {:decimal, [precision: 20, scale: 6, null: false]}
      )

      add(:counter_cash_account_id, references(:cash_accounts, on_delete: :restrict))
      add(:counter_securities_account_id, references(:securities_accounts, on_delete: :restrict))
      add(:gross_amount, :decimal, precision: 20, scale: 6)
      add(:import_hash, :string)
    end

    drop(constraint(:transactions, :transactions_manual_trade_type_check))

    create(
      constraint(:transactions, :transactions_type_check,
        check:
          "type IN ('buy', 'sell', 'dividend', 'interest', 'deposit', 'removal', 'fee', 'tax', 'tax_refund', 'cash_transfer', 'inbound_delivery', 'outbound_delivery', 'security_transfer')"
      )
    )

    create(
      unique_index(:transactions, [:import_hash],
        where: "import_hash IS NOT NULL",
        name: :transactions_import_hash_unique_index
      )
    )

    create(index(:transactions, [:counter_cash_account_id]))
    create(index(:transactions, [:counter_securities_account_id]))

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

    create(
      constraint(:transactions, :transactions_dividend_required_fields_check,
        check: """
        type <> 'dividend' OR (
          security_id IS NOT NULL AND
          cash_account_id IS NOT NULL AND
          gross_amount IS NOT NULL
        )
        """
      )
    )

    create(
      constraint(:transactions, :transactions_cash_only_required_fields_check,
        check: """
        type NOT IN ('interest', 'deposit', 'removal') OR (
          cash_account_id IS NOT NULL AND
          gross_amount IS NOT NULL
        )
        """
      )
    )

    create(
      constraint(:transactions, :transactions_fee_tax_required_fields_check,
        check: """
        type NOT IN ('fee', 'tax', 'tax_refund') OR (
          cash_account_id IS NOT NULL AND
          gross_amount IS NOT NULL
        )
        """
      )
    )

    create(
      constraint(:transactions, :transactions_cash_transfer_required_fields_check,
        check: """
        type <> 'cash_transfer' OR (
          cash_account_id IS NOT NULL AND
          counter_cash_account_id IS NOT NULL AND
          cash_account_id <> counter_cash_account_id AND
          gross_amount IS NOT NULL
        )
        """
      )
    )

    create(
      constraint(:transactions, :transactions_delivery_required_fields_check,
        check: """
        type NOT IN ('inbound_delivery', 'outbound_delivery') OR (
          security_id IS NOT NULL AND
          securities_account_id IS NOT NULL AND
          quantity IS NOT NULL AND quantity > 0
        )
        """
      )
    )

    create(
      constraint(:transactions, :transactions_security_transfer_required_fields_check,
        check: """
        type <> 'security_transfer' OR (
          security_id IS NOT NULL AND
          securities_account_id IS NOT NULL AND
          counter_securities_account_id IS NOT NULL AND
          securities_account_id <> counter_securities_account_id AND
          quantity IS NOT NULL AND quantity > 0
        )
        """
      )
    )

    execute(
      """
      ALTER TABLE transactions
      ADD CONSTRAINT transactions_counter_cash_account_portfolio_fkey
      FOREIGN KEY (counter_cash_account_id, portfolio_id)
      REFERENCES cash_accounts(id, portfolio_id)
      """,
      """
      ALTER TABLE transactions
      DROP CONSTRAINT transactions_counter_cash_account_portfolio_fkey
      """
    )

    execute(
      """
      ALTER TABLE transactions
      ADD CONSTRAINT transactions_counter_securities_account_portfolio_fkey
      FOREIGN KEY (counter_securities_account_id, portfolio_id)
      REFERENCES securities_accounts(id, portfolio_id)
      """,
      """
      ALTER TABLE transactions
      DROP CONSTRAINT transactions_counter_securities_account_portfolio_fkey
      """
    )
  end
end
