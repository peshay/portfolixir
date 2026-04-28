defmodule Portfolixir.Ledger.Positions do
  @moduledoc "Derives security positions from ledger transactions."

  @zero Decimal.new("0")

  def calculate(transactions) when is_list(transactions) do
    Enum.reduce(transactions, %{}, &apply_transaction/2)
  end

  defp apply_transaction(%{type: "buy"} = transaction, positions) do
    add_position(positions, transaction, transaction.quantity)
  end

  defp apply_transaction(%{type: "sell"} = transaction, positions) do
    add_position(positions, transaction, Decimal.negate(transaction.quantity))
  end

  defp apply_transaction(_transaction, positions), do: positions

  defp add_position(positions, transaction, quantity) do
    key = {transaction.securities_account_id, transaction.security_id}
    current = Map.get(positions, key, @zero)

    Map.put(positions, key, Decimal.add(current, quantity))
  end
end
