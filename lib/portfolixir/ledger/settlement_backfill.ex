defmodule Portfolixir.Ledger.SettlementBackfill do
  @moduledoc """
  One-time, auditable backfill of the ADR-0015 settlement fields for
  imported cross-currency trades (ADR-0033, issue #569).

  A Portfolio Performance export books a cross-currency trade in the
  **account** currency, so historic imported rows carry no security-currency
  leg. For every `buy`/`sell` whose `currency_code` differs from its
  security's currency and whose `security_amount` is still nil, this
  backfill derives the three linked ADR-0015 figures from the **stored** hub
  rate at the row's booking date:

    * `settlement_amount`  — `quantity x price` in the booked (account)
      currency, the cash leg as recorded;
    * `security_amount`    — that amount converted into the security's own
      currency at the booking-date rate;
    * `settlement_fx_rate` — settlement units per 1 security unit.

  Every update goes through `Portfolixir.Ledger.update_transaction/3` under
  the given actor, so each row's change is journaled with its pre-image
  (ADR-0017) — a one-time data repair, not a silent mutation. A row whose
  booking date has no stored rate is **skipped and counted**, never guessed
  (ADR-0033 requirement 4): its decomposition stays honestly unavailable
  until a rate for that date is stored and the backfill is re-run. Re-running
  is safe — rows with a `security_amount` are never touched again.

  Invoked via `mix portfolixir.backfill_settlement_legs`.
  """

  import Ecto.Query

  alias Portfolixir.Actor
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo

  @doc """
  Runs the backfill. Returns `{:ok, summary}` with `updated`,
  `skipped_no_rate` and `skipped_no_rate_rows` (transaction ids with their
  dates, so the skips are actionable), or `{:error, {transaction_id,
  changeset}}` on the first failing update (nothing further is attempted).
  """
  def run(%Actor{} = actor) do
    candidates()
    |> Enum.reduce_while({:ok, %{updated: 0, skipped_no_rate: 0, skipped_no_rate_rows: []}}, fn
      transaction, {:ok, summary} ->
        case backfill_row(actor, transaction) do
          {:ok, :updated} ->
            {:cont, {:ok, %{summary | updated: summary.updated + 1}}}

          {:ok, :no_rate} ->
            row = %{transaction_id: transaction.id, date: transaction.date}

            {:cont,
             {:ok,
              %{
                summary
                | skipped_no_rate: summary.skipped_no_rate + 1,
                  skipped_no_rate_rows: summary.skipped_no_rate_rows ++ [row]
              }}}

          {:error, changeset} ->
            {:halt, {:error, {transaction.id, changeset}}}
        end
    end)
  end

  # Cross-currency trades still missing their native leg: booked currency
  # differs from the security currency and no security_amount is stored.
  defp candidates do
    Repo.all(
      from(t in Transaction,
        join: s in assoc(t, :security),
        where:
          t.type in ["buy", "sell"] and is_nil(t.security_amount) and
            t.currency_code != s.currency_code,
        order_by: [asc: t.date, asc: t.id],
        preload: [:security]
      )
    )
  end

  defp backfill_row(actor, %Transaction{} = transaction) do
    settlement_amount = Decimal.mult(transaction.quantity, transaction.price)

    case Fx.convert(
           settlement_amount,
           transaction.currency_code,
           transaction.security.currency_code,
           transaction.date
         ) do
      {:ok, %Decimal{} = security_amount} ->
        if Decimal.equal?(security_amount, 0) do
          {:ok, :no_rate}
        else
          apply_update(actor, transaction, settlement_amount, security_amount)
        end

      {:error, :no_rate} ->
        {:ok, :no_rate}
    end
  end

  defp apply_update(actor, transaction, settlement_amount, security_amount) do
    rate = settlement_amount |> Decimal.div(security_amount) |> Decimal.round(6)

    case Ledger.update_transaction(actor, transaction, %{
           security_amount: security_amount,
           settlement_amount: settlement_amount,
           settlement_fx_rate: rate
         }) do
      {:ok, _transaction} -> {:ok, :updated}
      {:error, changeset} -> {:error, changeset}
    end
  end
end
