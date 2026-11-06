defmodule Portfolixir.Portfolios.Performance.SaleReinvestment.Fraction do
  @moduledoc """
  Exact rationals for what a switch cost (ADR-0057, as amended on
  2026-11-06): a pair `{numerator, denominator}` of integers, the
  denominator positive and the pair reduced.

  The matching rule splits proceeds pro rata, and each side of a span is one
  quotient of exact products, so the amounts are carried as exact fractions
  and rounded **once**, by `to_decimal/1`, at `Decimal`'s default context
  (34 significant digits, half-up). Two figures that are equal in exact
  arithmetic are then equal to the last digit, and an exact zero reads `0`.
  A stored `Decimal` (an amount, a close, a rate) converts without loss.
  """

  @type t :: {integer(), pos_integer()}

  @doc "A stored `Decimal` (or an integer) as an exact fraction."
  @spec new(Decimal.t() | integer()) :: t()
  def new(value) when is_integer(value), do: {value, 1}

  def new(%Decimal{sign: sign, coef: coef, exp: exp}) when is_integer(coef) do
    if exp >= 0,
      do: {sign * coef * pow10(exp), 1},
      else: reduce(sign * coef, pow10(-exp))
  end

  @doc "0."
  @spec zero() :: t()
  def zero, do: {0, 1}

  @spec add(t(), t()) :: t()
  def add({n1, d}, {n2, d}), do: reduce(n1 + n2, d)
  def add({n1, d1}, {n2, d2}), do: reduce(n1 * d2 + n2 * d1, d1 * d2)

  @spec sub(t(), t()) :: t()
  def sub(a, {n, d}), do: add(a, {-n, d})

  @spec mult(t(), t()) :: t()
  def mult({n1, d1}, {n2, d2}), do: reduce(n1 * n2, d1 * d2)

  @doc "`a / b`; `b` must not be 0."
  @spec divide(t(), t()) :: t()
  def divide(_a, {0, _d}), do: raise(ArithmeticError, "a fraction cannot be divided by 0")
  def divide({n1, d1}, {n2, d2}), do: reduce(n1 * d2, d1 * n2)

  @spec sum([t()]) :: t()
  def sum(fractions), do: Enum.reduce(fractions, zero(), &add/2)

  @spec compare(t(), t()) :: :lt | :eq | :gt
  def compare({n1, d1}, {n2, d2}) do
    left = n1 * d2
    right = n2 * d1

    cond do
      left < right -> :lt
      left > right -> :gt
      true -> :eq
    end
  end

  @spec min(t(), t()) :: t()
  def min(a, b), do: if(compare(a, b) == :gt, do: b, else: a)

  @spec positive?(t()) :: boolean()
  def positive?({n, _d}), do: n > 0

  @doc "The fraction as a `Decimal`, rounded once at the default context."
  @spec to_decimal(t()) :: Decimal.t()
  def to_decimal({n, 1}), do: Decimal.new(n)
  def to_decimal({n, d}), do: Decimal.div(Decimal.new(n), Decimal.new(d))

  defp reduce(n, d) when d < 0, do: reduce(-n, -d)

  defp reduce(n, d) do
    divisor = Integer.gcd(n, d)
    {div(n, divisor), div(d, divisor)}
  end

  defp pow10(exp), do: Integer.pow(10, exp)
end
