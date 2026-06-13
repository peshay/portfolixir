defmodule Portfolixir.Portfolios.Performance.IRRTest do
  use ExUnit.Case, async: true

  alias Portfolixir.Portfolios.Performance.IRR

  # User story:
  # As a local portfolio maintainer (and the LLM I connect over MCP),
  # I want the portfolio's money-weighted return (IRR) alongside TTWROR,
  # so that I can also see how the timing of my deposits and withdrawals
  # affected the outcome, the way Portfolio Performance shows it.
  #
  # Acceptance criteria:
  # - IRR is solved deterministically from dated cashflows (Σ cf/(1+r)^(d/365)).
  # - A known multi-flow example resolves to its expected rate within a
  #   documented tolerance.
  # - Degenerate inputs return nil and never crash: fewer than two flows, all
  #   flows the same sign / no sign change, and non-convergence within the
  #   iteration budget.

  defp dec(value), do: Decimal.new(value)
  defp cf(date, amount), do: {date, dec(amount)}

  test "solves a known multi-flow cashflow example to its expected IRR" do
    # Python-verified (bisection on Σ cf/(1+r)^(days/365)):
    #   -10000 @2024-01-01, -2000 @2024-03-01, +3000 @2024-07-01, +12000 @2025-01-01
    #   => 0.292517 (6 dp)
    cashflows = [
      cf(~D[2024-01-01], "-10000"),
      cf(~D[2024-03-01], "-2000"),
      cf(~D[2024-07-01], "3000"),
      cf(~D[2025-01-01], "12000")
    ]

    irr = IRR.compute(cashflows)

    assert %Decimal{} = irr
    assert Decimal.compare(Decimal.abs(Decimal.sub(irr, dec("0.292517"))), dec("0.000001")) != :gt
  end

  test "an exact one-year double in value resolves to 10%" do
    cashflows = [cf(~D[2024-01-01], "-1000"), cf(~D[2024-12-31], "1100")]

    assert IRR.compute(cashflows) |> Decimal.equal?(dec("0.1"))
  end

  test "returns nil for fewer than two cashflows" do
    assert IRR.compute([]) == nil
    assert IRR.compute([cf(~D[2024-01-01], "-1000")]) == nil
  end

  test "returns nil when every flow has the same sign (no sign change)" do
    assert IRR.compute([cf(~D[2024-01-01], "-1000"), cf(~D[2024-06-01], "-500")]) == nil
    assert IRR.compute([cf(~D[2024-01-01], "1000"), cf(~D[2024-06-01], "500")]) == nil
  end

  test "returns nil on non-convergence within the iteration budget" do
    cashflows = [cf(~D[2024-01-01], "-1000"), cf(~D[2024-12-31], "1100")]

    assert IRR.compute(cashflows, max_iterations: 1, tolerance: 1.0e-12) == nil
  end

  test "derives a cashflow vector from a summary with the series flow sign" do
    summary = %{
      start_date: ~D[2024-01-01],
      end_date: ~D[2024-12-31],
      start_value: dec("0"),
      end_value: dec("1100"),
      series: [
        %{date: ~D[2024-01-01], flow: dec("1000")},
        %{date: ~D[2024-06-01], flow: dec("0")}
      ]
    }

    # A +1000 inflow to the portfolio becomes a −1000 investor cashflow; the
    # end value is the terminal inflow. Zero-flow days are dropped.
    assert IRR.cashflows(summary) == [
             {~D[2024-01-01], dec("-1000")},
             {~D[2024-12-31], dec("1100")}
           ]

    assert IRR.for_summary(summary) |> Decimal.equal?(dec("0.1"))
  end
end
