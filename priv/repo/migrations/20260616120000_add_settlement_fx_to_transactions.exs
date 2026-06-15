defmodule Portfolixir.Repo.Migrations.AddSettlementFxToTransactions do
  use Ecto.Migration

  # Cross-currency settlement (issue #388, ADR-0015).
  #
  # A transaction may be booked in its security's own currency while the cash
  # leg settles in a different account currency (e.g. a USD security bought
  # through a EUR account at the broker's FX rate). To keep per-position cost
  # basis and P&L FX-honest we persist the three linked figures the broker
  # confirmation already shows:
  #
  #   * security_amount    — trade amount in the security's own currency
  #                          (the same currency as `currency_code` / `price`)
  #   * settlement_amount  — cash amount debited/credited in the settlement
  #                          (cash account) currency, i.e. the cash leg
  #   * settlement_fx_rate — units of settlement currency per 1 unit of the
  #                          security currency, settlement_amount / security_amount
  #
  # All three are additive and nullable: same-currency bookings (the vast
  # majority) leave them NULL and behave exactly as before. Scale 6 matches the
  # existing money/quote columns (20,6); rate precision is the working rule
  # until the rounding policy (#344) is decided.
  #
  # Additive migration only — no applied migration is edited (ADR-0009 rule 9).

  def change do
    alter table(:transactions) do
      add(:security_amount, :decimal, precision: 20, scale: 6)
      add(:settlement_amount, :decimal, precision: 20, scale: 6)
      add(:settlement_fx_rate, :decimal, precision: 20, scale: 6)
    end
  end
end
