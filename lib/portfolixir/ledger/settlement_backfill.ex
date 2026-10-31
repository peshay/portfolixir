defmodule Portfolixir.Ledger.SettlementBackfill do
  @moduledoc """
  One-time, auditable backfill of the ADR-0015 settlement fields for
  imported cross-currency trades (ADR-0033, issue #569).

  A Portfolio Performance export books a cross-currency trade in the
  **account** currency, so historic imported rows carry no security-currency
  leg. For every `buy`/`sell` booked in its cash account's currency, not its
  security's, with none of the three legs stored (ADR-0015's amendment of
  2026-10-09, point 6, #1196: a row priced in a third currency, or one
  carrying any leg, is never rewritten), this backfill derives the three
  linked ADR-0015 figures from the **stored** hub rate at the row's booking
  date:

    * `settlement_amount`  — the trade amount in the booked (account)
      currency: the row's recorded cash amount net of its fees and taxes
      (`Portfolixir.Ledger.SettlementGuard.trade_amount/4`), and
      `quantity x price` only where no cash amount is recorded;
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

  Invoked via `mix portfolixir.backfill_settlement_legs`, and as the last
  step of every history backfill that stores rates
  (`Portfolixir.Fx.RateSync.backfill/1`, #1196), under the same actor.
  """

  import Ecto.Query

  alias Portfolixir.Actor
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.SettlementGuard
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo

  @doc """
  Runs the backfill. Returns `{:ok, summary}` with `updated`,
  `skipped_no_rate`, `skipped_no_rate_rows` (transaction ids with their
  dates, so the skips are actionable) and `skipped_changed` (rows that
  gained a leg after the candidate read, whose cash, fees, taxes or another
  input of their legs changed since, or were deleted: each write re-checks
  under the row's lock that none of the three legs is stored and that the
  row still reads as the legs were derived from, #1196, and a re-run
  derives the changed row from what it stores then), or
  `{:error, {transaction_id, changeset}}` on the first failing
  update (nothing further is attempted).
  An update that lost a lock cycle with a concurrent write (#1214) stops it
  the same way as `{:error, {transaction_id, :raced}}`: nothing was written
  for that row, and a re-run picks it up.
  """
  def run(%Actor{} = actor) do
    empty = %{updated: 0, skipped_no_rate: 0, skipped_no_rate_rows: [], skipped_changed: 0}

    candidates()
    |> Enum.reduce_while({:ok, empty}, fn
      transaction, {:ok, summary} ->
        case backfill_row(actor, transaction) do
          {:ok, :updated} ->
            {:cont, {:ok, %{summary | updated: summary.updated + 1}}}

          {:ok, :changed} ->
            {:cont, {:ok, %{summary | skipped_changed: summary.skipped_changed + 1}}}

          {:ok, :no_rate} ->
            row = %{transaction_id: transaction.id, date: transaction.date}

            {:cont,
             {:ok,
              %{
                summary
                | skipped_no_rate: summary.skipped_no_rate + 1,
                  skipped_no_rate_rows: summary.skipped_no_rate_rows ++ [row]
              }}}

          {:error, :raced} ->
            {:halt, {:error, {transaction.id, :raced}}}

          {:error, changeset} ->
            {:halt, {:error, {transaction.id, changeset}}}
        end
    end)
  end

  # The import form still missing its legs (ADR-0015's amendment of
  # 2026-10-09, point 6, #1196): a buy or sell booked in its cash account's
  # currency, not its security's, with none of the three legs stored. A row
  # priced in a third currency, or one carrying any leg, is never a
  # candidate: before, a stored third-currency row's rate was rewritten.
  defp candidates do
    Repo.all(
      from(t in Transaction,
        join: s in assoc(t, :security),
        join: c in assoc(t, :cash_account),
        where:
          t.type in ["buy", "sell"] and t.currency_code == c.currency_code and
            t.currency_code != s.currency_code and is_nil(t.security_amount) and
            is_nil(t.settlement_amount) and is_nil(t.settlement_fx_rate),
        order_by: [asc: t.date, asc: t.id],
        preload: [:security]
      )
    )
  end

  # The settlement leg is read off the row's cash amount where it has one
  # (the guard's relation, inverted — a rounded Kurs × quantity can miss it by
  # more than the guard's cent), else quantity × price as before: the
  # arithmetic of `Imports.Applier.derived_settlement_legs/4`, so a derived
  # row carries the legs an import stores when the rate is already there.
  defp backfill_row(actor, %Transaction{} = transaction) do
    settlement_amount =
      SettlementGuard.trade_amount(
        transaction.type,
        transaction.gross_amount,
        transaction.fees,
        transaction.taxes
      ) || Decimal.mult(transaction.quantity, transaction.price)

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

    case Ledger.derive_settlement_legs(actor, transaction, %{
           security_amount: security_amount,
           settlement_amount: settlement_amount,
           settlement_fx_rate: rate
         }) do
      {:ok, _transaction} ->
        {:ok, :updated}

      # #1196: the row gained a leg after the candidate read, its cash (or
      # another input of its legs) changed since, or it is gone; a re-run
      # derives from the row as stored then.
      {:error, reason} when reason in [:legs_stored, :inputs_changed, :not_found] ->
        {:ok, :changed}

      {:error, :raced} ->
        {:error, :raced}

      {:error, changeset} ->
        {:error, changeset}
    end
  end
end
