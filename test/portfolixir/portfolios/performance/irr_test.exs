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

  # User story (#568, ADR-0034):
  # As a maintainer comparing Portfolixir's IRR against Excel/PP,
  # I want the solver to be Newton's method from guess 0.1 with a bracketed
  # bisection fallback on (−0.999999, +10],
  # so that the figure matches Excel XIRR (both float64) and a root is still
  # found when the fallback bracket shows no sign change.
  #
  # Acceptance criteria:
  # - The Excel XIRR documentation example resolves to 0.373363 (6 dp).
  # - A two-root flow pattern whose NPV is negative at both fallback-bracket
  #   ends is still solved (Newton from 0.1 lands on 0.237339).
  # - A root far above the fallback bracket's upper end is still found.

  test "matches the Excel XIRR reference example (ADR-0034)" do
    # Excel XIRR docs example, independently verified (Newton + bisection,
    # Act/365): −10000 @2008-01-01, 2750 @2008-03-01, 4250 @2008-10-30,
    # 3250 @2009-02-15, 2750 @2009-04-01 => 0.373363 (6 dp).
    cashflows = [
      cf(~D[2008-01-01], "-10000"),
      cf(~D[2008-03-01], "2750"),
      cf(~D[2008-10-30], "4250"),
      cf(~D[2009-02-15], "3250"),
      cf(~D[2009-04-01], "2750")
    ]

    irr = IRR.compute(cashflows)

    assert %Decimal{} = irr
    assert Decimal.compare(Decimal.abs(Decimal.sub(irr, dec("0.373363"))), dec("0.000001")) != :gt
  end

  test "solves a two-root pattern the fallback bracket cannot see (ADR-0034)" do
    # NPV is negative at both bracket ends (−0.999999 and +10) but has two
    # roots in between (0.237339 and 1.091886, independently verified).
    # Bisection alone returns nil here; Newton from 0.1 finds the nearer root.
    cashflows = [
      cf(~D[2024-01-01], "-1000"),
      cf(~D[2024-07-01], "2550"),
      cf(~D[2024-12-31], "-1600")
    ]

    irr = IRR.compute(cashflows)

    assert %Decimal{} = irr
    assert Decimal.compare(Decimal.abs(Decimal.sub(irr, dec("0.237339"))), dec("0.000001")) != :gt
  end

  test "finds a root far above the fallback bracket's upper end (ADR-0034)" do
    # −100 grows to 5000 in exactly one Act/365 year: r = 49 (4900% p.a.),
    # beyond the +10 fallback bracket — reachable only through Newton.
    cashflows = [cf(~D[2024-01-01], "-100"), cf(~D[2024-12-31], "5000")]

    irr = IRR.compute(cashflows)

    assert %Decimal{} = irr
    assert Decimal.compare(Decimal.abs(Decimal.sub(irr, dec("49"))), dec("0.000001")) != :gt
  end

  test "returns nil for fewer than two cashflows" do
    assert IRR.compute([]) == nil
    assert IRR.compute([cf(~D[2024-01-01], "-1000")]) == nil
  end

  test "returns nil when every flow has the same sign (no sign change)" do
    assert IRR.compute([cf(~D[2024-01-01], "-1000"), cf(~D[2024-06-01], "-500")]) == nil
    assert IRR.compute([cf(~D[2024-01-01], "1000"), cf(~D[2024-06-01], "500")]) == nil
  end

  test "invents no rate when every cashflow shares one date (review finding)" do
    # A one-day window gives money no time to weight: NPV is constant in r,
    # so when it nets to zero EVERY rate "solves" it — Newton must not hand
    # back its 10% guess as if it were a result (ADR-0034: no root is
    # invented). A non-zero constant has no root at all.
    day = ~D[2024-06-01]

    assert IRR.compute([cf(day, "-1000"), cf(day, "1000")]) == nil
    assert IRR.compute([cf(day, "-1000"), cf(day, "1200")]) == nil
  end

  test "an underflowing fallback bracket yields nil, never a raise" do
    # A 60-year span: at the bracket's lower end (rate −0.999999) the
    # discount factor underflows float64 to 0.0 and the division raises —
    # the fallback absorbs it into "no IRR". Newton is exhausted first via
    # a zero budget, forcing the bracketed path.
    cashflows = [cf(~D[1970-01-01], "-1000"), cf(~D[2030-01-01], "500")]

    assert IRR.compute(cashflows, max_iterations: 0) == nil
  end

  test "returns nil on non-convergence within the iteration budget" do
    # Root is 0.2 — deliberately away from the Newton guess (0.1), so a
    # one-step budget can converge in neither Newton nor the fallback.
    cashflows = [cf(~D[2024-01-01], "-1000"), cf(~D[2024-12-31], "1200")]

    assert IRR.compute(cashflows, max_iterations: 1, tolerance: 1.0e-12) == nil
  end

  # The de-annualization lives here so float64 stays confined to this module
  # (ADR-0034 §2 — the single sanctioned float island, review finding).
  test "period_rate/2 de-annualizes the solved rate for a window's day count" do
    # 365 days: the period rate IS the annual rate.
    assert IRR.period_rate(dec("0.1"), 365) |> Decimal.equal?(dec("0.1"))

    # 90 days at the annualized rate that 5% over 90 days solves to: back to 5%
    # (1.05^(365/90) − 1 = 0.218805 at 6 dp, independently verified).
    annualized = IRR.period_rate(dec("0.218805"), 90)

    assert Decimal.compare(Decimal.abs(Decimal.sub(annualized, dec("0.05"))), dec("0.000001")) !=
             :gt

    # Degenerate inputs stay nil, never a crash.
    assert IRR.period_rate(nil, 90) == nil
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
