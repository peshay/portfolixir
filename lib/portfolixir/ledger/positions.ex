defmodule Portfolixir.Ledger.Positions do
  @moduledoc """
  Derives currently held quantities per `{securities_account, security}`.

  Quantities move with `buy`/`sell` trades, `inbound_delivery`/
  `outbound_delivery` (shares enter or leave without a cash leg, e.g. a depot
  transfer from another bank), and `security_transfer` between own depots.
  Cost basis and P&L stay with the moving-average holdings view, which only
  considers priced trades — a delivery carries no own cost.
  """

  @zero Decimal.new("0")

  def calculate(transactions) when is_list(transactions) do
    Enum.reduce(transactions, %{}, &apply_transaction/2)
  end

  defp apply_transaction(%{type: type} = transaction, positions)
       when type in ["buy", "inbound_delivery"] do
    add_quantity(positions, transaction.securities_account_id, transaction, transaction.quantity)
  end

  defp apply_transaction(%{type: type} = transaction, positions)
       when type in ["sell", "outbound_delivery"] do
    add_quantity(
      positions,
      transaction.securities_account_id,
      transaction,
      Decimal.negate(transaction.quantity)
    )
  end

  defp apply_transaction(%{type: "security_transfer"} = transaction, positions) do
    positions
    |> add_quantity(
      transaction.securities_account_id,
      transaction,
      Decimal.negate(transaction.quantity)
    )
    |> add_quantity(
      transaction.counter_securities_account_id,
      transaction,
      transaction.quantity
    )
  end

  defp apply_transaction(_transaction, positions), do: positions

  defp add_quantity(positions, securities_account_id, transaction, quantity) do
    key = {securities_account_id, transaction.security_id}

    positions
    |> Map.update(key, quantity, &Decimal.add(&1, quantity))
    |> Enum.reject(fn {_key, value} -> Decimal.equal?(value, @zero) end)
    |> Map.new()
  end
end
