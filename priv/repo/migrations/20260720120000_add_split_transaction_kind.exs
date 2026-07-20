defmodule Portfolixir.Repo.Migrations.AddSplitTransactionKind do
  use Ecto.Migration

  # Adds a 15th transaction kind, `split` (ADR-0028): a corporate action
  # recording a stock split as a first-class ledger event — the security, the
  # effective date, and the ratio as a pair of positive integers (10:1
  # forward, 1:10 reverse), normalized to lowest terms at write time. It
  # carries no cash leg and no price; its projection is a multiplicative
  # quantity leg scoped to the row's own portfolio.
  #
  # Write idempotency: a retried timeout must not compound a multiplicative
  # event, so a partial unique index backs the write — one split per
  # (portfolio, security, day).

  @with_split "type IN ('buy', 'sell', 'dividend', 'interest', 'deposit', 'removal', 'fee', 'tax', 'tax_refund', 'cash_transfer', 'inbound_delivery', 'outbound_delivery', 'security_transfer', 'balance_adjustment', 'split')"

  @without_split "type IN ('buy', 'sell', 'dividend', 'interest', 'deposit', 'removal', 'fee', 'tax', 'tax_refund', 'cash_transfer', 'inbound_delivery', 'outbound_delivery', 'security_transfer', 'balance_adjustment')"

  def up do
    alter table(:transactions) do
      add(:split_ratio_numerator, :integer)
      add(:split_ratio_denominator, :integer)
    end

    drop(constraint(:transactions, :transactions_type_check))
    create(constraint(:transactions, :transactions_type_check, check: @with_split))

    # A split records exactly security + date + normalized ratio: both ratio
    # parts positive, not equal (a normalized 1:1 pair is meaningless), and
    # none of the cash/price/quantity/settlement/counter fields of the additive
    # kinds. The forbidden-field set mirrors `@split_blank_fields` in
    # Portfolixir.Ledger.Transaction exactly, so the DB is a true backstop for a
    # split row written outside the changeset (e.g. raw SQL): a stray
    # counter_securities_account_id here would let Projection.account_portfolios
    # mis-scope the multiplicative leg. `fees`/`taxes` are NOT NULL with a `0`
    # default, so the changeset requires them zero rather than null; forcing
    # them NULL here would reject valid rows, so they stay out of this CHECK.
    create(
      constraint(:transactions, :transactions_split_required_fields_check,
        check: """
        type <> 'split' OR (
          security_id IS NOT NULL AND
          split_ratio_numerator IS NOT NULL AND
          split_ratio_denominator IS NOT NULL AND
          split_ratio_numerator > 0 AND
          split_ratio_denominator > 0 AND
          split_ratio_numerator <> split_ratio_denominator AND
          quantity IS NULL AND
          price IS NULL AND
          gross_amount IS NULL AND
          security_amount IS NULL AND
          settlement_amount IS NULL AND
          settlement_fx_rate IS NULL AND
          cash_account_id IS NULL AND
          counter_cash_account_id IS NULL AND
          securities_account_id IS NULL AND
          counter_securities_account_id IS NULL
        )
        """
      )
    )

    # The ratio columns exist only for splits.
    create(
      constraint(:transactions, :transactions_split_ratio_only_for_split_check,
        check: """
        type = 'split' OR (
          split_ratio_numerator IS NULL AND
          split_ratio_denominator IS NULL
        )
        """
      )
    )

    create(
      unique_index(:transactions, [:portfolio_id, :security_id, :date],
        where: "type = 'split'",
        name: :transactions_one_split_per_portfolio_security_day_index
      )
    )
  end

  def down do
    drop(
      index(:transactions, [:portfolio_id, :security_id, :date],
        name: :transactions_one_split_per_portfolio_security_day_index
      )
    )

    drop(constraint(:transactions, :transactions_split_ratio_only_for_split_check))
    drop(constraint(:transactions, :transactions_split_required_fields_check))
    drop(constraint(:transactions, :transactions_type_check))
    create(constraint(:transactions, :transactions_type_check, check: @without_split))

    alter table(:transactions) do
      remove(:split_ratio_numerator)
      remove(:split_ratio_denominator)
    end
  end
end
