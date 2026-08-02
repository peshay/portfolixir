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

  @zero Decimal.new("0")

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
  base cost yields zero percentages (the existing P&L convention).
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

  defp pct(value, base_cost) do
    if Decimal.equal?(base_cost, @zero) do
      @zero
    else
      Decimal.div(value, base_cost)
    end
  end
end
