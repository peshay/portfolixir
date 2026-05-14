defmodule Portfolixir.Ledger.Positions do
  @moduledoc "Derives current holdings from manual buy and sell transactions."

  @zero Decimal.new("0")

  def calculate(transactions) when is_list(transactions) do
    Enum.reduce(transactions, %{}, &apply_transaction/2)
  end

  defp apply_transaction(%{type: "buy"} = transaction, positions) do
    add_quantity(positions, transaction, transaction.quantity)
  end

  defp apply_transaction(%{type: "sell"} = transaction, positions) do
    add_quantity(positions, transaction, Decimal.negate(transaction.quantity))
  end

  defp apply_transaction(_transaction, positions), do: positions

  defp add_quantity(positions, transaction, quantity) do
    key = {transaction.securities_account_id, transaction.security_id}

    positions
    |> Map.update(key, quantity, &Decimal.add(&1, quantity))
    |> Enum.reject(fn {_key, value} -> Decimal.equal?(value, @zero) end)
    |> Map.new()
  end
end
