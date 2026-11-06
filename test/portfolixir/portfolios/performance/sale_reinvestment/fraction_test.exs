defmodule Portfolixir.Portfolios.Performance.SaleReinvestment.FractionTest do
  # Sprint 26 closing act, Lane R (M1, M3): the exact fractions what a switch
  # cost carries until it shows a figure.
  use ExUnit.Case, async: true

  alias Portfolixir.Portfolios.Performance.SaleReinvestment.Fraction

  # User story (closing act M1/M3, ADR-0057 as amended on 2026-11-06):
  # As the maintainer of a pro rata split,
  # I want amounts carried as exact fractions and rounded once,
  # so that equal figures read equal and a split adds back to its whole.
  #
  # Acceptance criteria:
  # - A stored Decimal converts without loss; the arithmetic is exact.
  # - to_decimal rounds once at 34 significant digits, half-up.
  # - Thirds add back to exactly 1; comparison and min are exact.
  test "exact arithmetic, rounded once" do
    assert Fraction.new(Decimal.new("1.30")) == {13, 10}
    assert Fraction.new(Decimal.new("-2.5E+2")) == {-250, 1}
    assert Fraction.new(7) == {7, 1}

    third = Fraction.divide(Fraction.new(1), Fraction.new(3))
    assert Fraction.sum([third, third, third]) == {1, 1}
    assert Fraction.to_decimal(third) == Decimal.new("0.3333333333333333333333333333333333")

    # 1100 / 1.3 = 846.153846...: the 35th digit is 5, so it rounds up.
    assert Fraction.new(1100)
           |> Fraction.divide(Fraction.new(Decimal.new("1.3")))
           |> Fraction.to_decimal() ==
             Decimal.new("846.1538461538461538461538461538462")

    assert Fraction.compare(third, Fraction.new(Decimal.new("0.3333"))) == :gt
    assert Fraction.min(third, Fraction.new(1)) == third
    assert Fraction.sub(third, third) == Fraction.zero()
    refute Fraction.positive?(Fraction.zero())
    assert_raise ArithmeticError, fn -> Fraction.divide(third, Fraction.zero()) end
  end
end
