defmodule Mix.Tasks.Portfolixir.BackfillSettlementLegs do
  @shortdoc "Backfills ADR-0015 settlement legs for imported cross-currency trades (ADR-0033)"

  @moduledoc """
  Runs the one-time ADR-0033 settlement-leg backfill on demand:

      mix portfolixir.backfill_settlement_legs

  Historic Portfolio Performance imports booked cross-currency trades in the
  account currency without the ADR-0015 settlement fields, so their
  per-position P&L mixed price moves with purchase-date FX. This task derives
  `security_amount` / `settlement_amount` / `settlement_fx_rate` for every
  `buy`/`sell` booked in its cash account's currency, not its security's,
  with none of the three fields stored (ADR-0015's amendment of 2026-10-09,
  point 6, #1196), using the stored hub rate at each row's booking date, and
  journals every update under a `settlement_backfill` system actor
  (ADR-0017 — auditable, with the pre-image recorded). Every history
  backfill that stores rates runs the same derivation as its last step.

  Idempotent: a row that carries any of the three fields, or is priced in a
  third currency, is never touched, and neither is one that gains a field
  while the task runs. Rows whose booking date has no stored rate are
  skipped and listed — store a rate for that date and re-run; nothing is
  ever guessed.
  """

  use Mix.Task

  alias Portfolixir.Actor
  alias Portfolixir.Ledger.SettlementBackfill

  @requirements ["app.start"]

  @impl Mix.Task
  def run(_args) do
    actor = Actor.system_job("settlement_backfill")

    case SettlementBackfill.run(actor) do
      {:ok, summary} ->
        Mix.shell().info("""
        Settlement-leg backfill complete:
          rows updated:          #{summary.updated}
          skipped (no rate):     #{summary.skipped_no_rate}
        """)

        Enum.each(summary.skipped_no_rate_rows, fn row ->
          Mix.shell().info(
            "  skipped transaction ##{row.transaction_id} (#{row.date}): " <>
              "no stored rate at or before the booking date"
          )
        end)

      # #1214: the row's update lost a lock cycle with a concurrent write.
      {:error, {transaction_id, :raced}} ->
        Mix.raise(
          "Backfill stopped at transaction ##{transaction_id}: its update lost a lock cycle " <>
            "with a concurrent write and nothing was written for it. Re-run the task."
        )

      {:error, {transaction_id, changeset}} ->
        Mix.raise(
          "Backfill failed for transaction ##{transaction_id}: #{inspect(changeset.errors)}"
        )
    end
  end
end
