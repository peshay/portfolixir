defmodule Portfolixir.Repo.Migrations.ReplaceCashQuoteFlagWithLiquidityRole do
  use Ecto.Migration

  # FR5-FR7 (#389): replace the per-account boolean `counts_toward_cash_quote`
  # (#317) with a 3-way `liquidity_role` enum {free_cash, credit_line, reserve}.
  # A single string column with a DB check constraint is the single source of
  # truth for whether (and how) an account's balance is real, deployable cash.
  #
  # Backfill from the boolean: an account that counted toward the quote was real
  # spendable cash -> `free_cash`; one excluded from it was a reference/holding
  # bucket -> `reserve`. Credit lines did not exist as a concept yet, so none
  # are inferred. The boolean is dropped after the backfill: keeping both would
  # let the two drift apart.

  @roles ~w(free_cash credit_line reserve)
  @check "liquidity_role IN ('free_cash', 'credit_line', 'reserve')"

  def up do
    alter table(:cash_accounts) do
      add(:liquidity_role, :string, default: "free_cash", null: false)
    end

    create(constraint(:cash_accounts, :cash_accounts_liquidity_role_check, check: @check))

    # Backfill from the #317 boolean before it is dropped: true -> free_cash
    # (already the default), false -> reserve.
    execute("""
    UPDATE cash_accounts
    SET liquidity_role = 'reserve'
    WHERE counts_toward_cash_quote = false
    """)

    alter table(:cash_accounts) do
      remove(:counts_toward_cash_quote)
    end
  end

  def down do
    alter table(:cash_accounts) do
      add(:counts_toward_cash_quote, :boolean, default: true, null: false)
    end

    # Reverse mapping: only `free_cash` accounts counted toward the quote;
    # `credit_line` and `reserve` did not.
    execute("""
    UPDATE cash_accounts
    SET counts_toward_cash_quote = false
    WHERE liquidity_role IN ('credit_line', 'reserve')
    """)

    drop(constraint(:cash_accounts, :cash_accounts_liquidity_role_check))

    alter table(:cash_accounts) do
      remove(:liquidity_role)
    end
  end

  # Documents the closed role set this migration introduces; the schema validates
  # against the same list (Portfolixir.Portfolios.CashAccount.liquidity_roles/0).
  def roles, do: @roles
end
