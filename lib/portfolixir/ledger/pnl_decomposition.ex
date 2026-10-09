defmodule Portfolixir.Ledger.PnlDecomposition do
  @moduledoc """
  The ADR-0033 per-position P&L decomposition.

  A position's base-currency P&L is split into two named components over a
  security-currency cost basis, with the fixed, residual-free convention:

      price    = (MV_native - native_cost) x r1
      currency = native_cost x r1 - base_cost
      total    = price + currency          (exact in Decimal, no cross-term)

  where `MV_native` is the market value in the security's own currency,
  `native_cost` the security-currency cost basis, `base_cost` the
  base-currency amount actually paid (the ADR-0015 settlement leg) and `r1`
  the current hub rate the valuation already uses. The price leg is valued at
  the current rate and the currency leg on the invested native cost; the
  mirrored convention is equally exact but must never be mixed with this one.

  Everything is pure `Decimal` arithmetic at full precision (ADR-0016 —
  rounding is a display concern). Rates enter as arguments, never as lookups
  (ADR-0015).
  """

  @unavailable %{
    price_return_abs: nil,
    price_return_pct: nil,
    currency_return_abs: nil,
    currency_return_pct: nil,
    total_return_base_abs: nil,
    total_return_base_pct: nil,
    decomposed: false
  }

  @doc """
  Decomposes a position into price/currency/total components.

  All four arguments are Decimals; `rate` is the current rate converting one
  unit of the security currency into the base currency. The component
  percentages share the `base_cost` denominator, so they add exactly; a zero
  base cost yields `nil` percentages beside the amounts (#1142, plan D-6:
  a return on no cost is undefined, and 0 would read as flat; `pct_basis/0`).
  """
  def decompose(
        %Decimal{} = market_value_native,
        %Decimal{} = native_cost,
        %Decimal{} = base_cost,
        %Decimal{} = rate
      ) do
    price = market_value_native |> Decimal.sub(native_cost) |> Decimal.mult(rate)
    currency = native_cost |> Decimal.mult(rate) |> Decimal.sub(base_cost)
    total = Decimal.add(price, currency)

    %{
      price_return_abs: price,
      price_return_pct: pct(price, base_cost),
      currency_return_abs: currency,
      currency_return_pct: pct(currency, base_cost),
      total_return_base_abs: total,
      total_return_base_pct: pct(total, base_cost),
      decomposed: true,
      undecomposed_reason: nil
    }
  end

  @doc """
  The honest empty shape: every component nil, `decomposed` false, with the
  given reason (`:missing_native_cost` | `:missing_base_cost` | `:missing_fx`
  | `:no_price`). Never a guessed number (ADR-0033 requirement 4).
  """
  def unavailable(reason) when is_atom(reason) do
    Map.put(@unavailable, :undecomposed_reason, reason)
  end

  @doc """
  The rule of the three decomposition percentages, as the sentence the
  holdings and trades payloads carry (#1142's last sibling, plan D-6; the
  AGENTS.md metric rule): `nil` where `base_cost` is zero.
  """
  @spec pct_basis() :: String.t()
  def pct_basis do
    "price_return_pct, currency_return_pct and total_return_base_pct are price_return_abs, " <>
      "currency_return_abs and total_return_base_abs / base_cost, fractions (0.1 = 10 %) in " <>
      "base_currency that add exactly. They are null where their amounts are (decomposed " <>
      "false), and null, never 0, where base_cost is 0, shares delivered in at no cost or " <>
      "bought at a price of 0: a return on no cost is undefined, and 0 would read as flat. " <>
      "The amounts still state the gain."
  end

  # #1142 (plan D-6): no percentage on no cost, as `unrealized_pnl_pct`.
  defp pct(_value, %Decimal{coef: 0}), do: nil
  defp pct(value, base_cost), do: Decimal.div(value, base_cost)
end
