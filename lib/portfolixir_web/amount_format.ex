defmodule PortfolixirWeb.AmountFormat do
  @moduledoc "Deterministic read-only formatting helpers for financial amounts."

  @missing_amount "Valuation unavailable"

  def format_currency_amount(nil, _currency_code), do: @missing_amount

  def format_currency_amount(%Decimal{} = amount, currency_code) do
    amount
    |> format_decimal()
    |> append_currency_code(currency_code)
  end

  def format_currency_amount(_amount, _currency_code), do: @missing_amount

  def format_decimal(nil), do: "—"

  def format_decimal(%Decimal{} = amount) do
    amount
    |> Decimal.round(2)
    |> Decimal.to_string(:normal)
  end

  def format_decimal(amount), do: to_string(amount)

  def missing_amount_label, do: @missing_amount

  defp append_currency_code(amount, nil), do: amount

  defp append_currency_code(amount, currency_code) do
    case currency_code |> to_string() |> String.trim() do
      "" -> amount
      code -> "#{amount} #{code}"
    end
  end
end
