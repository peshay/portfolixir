defmodule Portfolixir.Ledger.CashBalances do
  @moduledoc "Derives cash balances from ledger transactions."

  alias Ecto.Association.NotLoaded
  alias Portfolixir.Portfolios.SecuritiesAccount

  @zero Decimal.new("0")

  def calculate(transactions) when is_list(transactions) do
    transactions
    |> Enum.reduce(%{balances: %{}, missing_cash_impacts: []}, &apply_transaction/2)
    |> reverse_missing_cash_impacts()
  end

  defp apply_transaction(%{type: "deposit"} = transaction, acc) do
    add_balance(
      acc,
      transaction.deposit_account_id,
      transaction.currency_code,
      transaction.amount
    )
  end

  defp apply_transaction(%{type: "withdrawal"} = transaction, acc) do
    add_balance(
      acc,
      transaction.deposit_account_id,
      transaction.currency_code,
      Decimal.negate(transaction.amount)
    )
  end

  defp apply_transaction(%{type: "dividend"} = transaction, acc) do
    add_balance(
      acc,
      transaction.deposit_account_id,
      transaction.currency_code,
      transaction.amount
    )
  end

  defp apply_transaction(%{type: "buy"} = transaction, acc) do
    cash_impact = transaction.amount |> Decimal.add(decimal_or_zero(transaction.fees))
    cash_impact = Decimal.add(cash_impact, decimal_or_zero(transaction.taxes))

    apply_securities_cash_impact(transaction, acc, Decimal.negate(cash_impact))
  end

  defp apply_transaction(%{type: "sell"} = transaction, acc) do
    cash_impact = transaction.amount |> Decimal.sub(decimal_or_zero(transaction.fees))
    cash_impact = Decimal.sub(cash_impact, decimal_or_zero(transaction.taxes))

    apply_securities_cash_impact(transaction, acc, cash_impact)
  end

  defp apply_transaction(_transaction, acc), do: acc

  defp apply_securities_cash_impact(transaction, acc, amount) do
    case reference_deposit_account_id(transaction) do
      nil ->
        add_missing_cash_impact(acc, transaction)

      deposit_account_id ->
        add_balance(acc, deposit_account_id, transaction.currency_code, amount)
    end
  end

  defp add_balance(acc, deposit_account_id, currency_code, amount)
       when is_integer(deposit_account_id) and is_binary(currency_code) do
    key = {deposit_account_id, currency_code}
    current = Map.get(acc.balances, key, @zero)
    balance = Decimal.add(current, amount)

    %{acc | balances: Map.put(acc.balances, key, balance)}
  end

  defp add_balance(acc, _deposit_account_id, _currency_code, _amount), do: acc

  defp add_missing_cash_impact(acc, transaction) do
    impact = %{
      transaction_id: transaction.id,
      type: transaction.type,
      reason: :missing_reference_deposit_account
    }

    %{acc | missing_cash_impacts: [impact | acc.missing_cash_impacts]}
  end

  defp reference_deposit_account_id(%{
         securities_account: %SecuritiesAccount{reference_deposit_account_id: id}
       }) do
    id
  end

  defp reference_deposit_account_id(%{securities_account: %NotLoaded{}}), do: nil
  defp reference_deposit_account_id(_transaction), do: nil

  defp decimal_or_zero(nil), do: @zero
  defp decimal_or_zero(%Decimal{} = value), do: value

  defp reverse_missing_cash_impacts(acc) do
    %{acc | missing_cash_impacts: Enum.reverse(acc.missing_cash_impacts)}
  end
end
