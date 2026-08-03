defmodule Mix.Tasks.Portfolixir.BackfillSettlementLegs do
  @shortdoc "Backfills ADR-0015 settlement legs for imported cross-currency trades (ADR-0033)"

  @moduledoc """
  Runs the one-time ADR-0033 settlement-leg backfill on demand:

      mix portfolixir.backfill_settlement_legs

  Historic Portfolio Performance imports booked cross-currency trades in the
  account currency without the ADR-0015 settlement fields, so their
  per-position P&L mixed price moves with purchase-date FX. This task derives
  `security_amount` / `settlement_amount` / `settlement_fx_rate` for every
  `buy`/`sell` whose currency differs from its security's currency, using the
  stored hub rate at each row's booking date, and journals every update under
  a `settlement_backfill` system actor (ADR-0017 — auditable, with the
  pre-image recorded).

  Idempotent: rows that already carry a `security_amount` are never touched.
  Rows whose booking date has no stored rate are skipped and listed — store a
  rate for that date and re-run; nothing is ever guessed.
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

      {:error, {transaction_id, changeset}} ->
        Mix.raise(
          "Backfill failed for transaction ##{transaction_id}: #{inspect(changeset.errors)}"
        )
    end
  end
end
