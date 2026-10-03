defmodule Portfolixir.Engines.BondMetricsTest do
  # #330 (ADR-0052 §2–§4): the bond metrics as pure arithmetic over injected
  # master data, a price and a quantity. Every figure is invented: a 2.50 %
  # bond maturing 2031-06-15, quoted 97.25, read on 2026-10-02.
  use ExUnit.Case, async: true

  alias Portfolixir.Engines.BondMetrics

  @as_of ~D[2026-10-02]

  @terms %{coupon_rate: Decimal.new("2.5"), maturity_date: ~D[2031-06-15]}
  @quote_price %{value: Decimal.new("97.25"), date: ~D[2026-09-30], source: :quote}

  defp dec(value), do: Decimal.new(value)

  # The string, not Decimal.equal?/2: the identity names the scale.
  defp assert_scale_6(actual, expected),
    do: assert(Decimal.to_string(actual, :normal) == expected)

  # User story (#330, ADR-0052 §2 and §3):
  # As the operator checking a bond against its statement,
  # I want the nominal I hold, the remaining term, the current yield and a
  # linear yield to maturity computed from the master data and the price,
  # so that the bond reads as a bond and not as an empty name shell.
  #
  # Acceptance criteria:
  # - The nominal held is quantity × 100 (one unit is a hundredth of the face
  #   amount), exact.
  # - The remaining term counts calendar days from the read day to the
  #   maturity (1717), in years of 365 days (4.704110), and in whole years
  #   and months (4 and 8).
  # - The current yield is coupon ÷ price (0.025707), the linear yield to
  #   maturity (coupon + (100 − price) ÷ years) ÷ price (0.031718), both
  #   ratios at scale 6, the years taken at full precision.
  test "computes the nominal, the remaining term and both yields from master data and price" do
    metrics = BondMetrics.compute(@terms, @quote_price, dec("100"), @as_of)

    assert Decimal.equal?(metrics.nominal_held, dec("10000"))

    term = metrics.remaining_term
    assert term.days == 1717
    assert_scale_6(term.years, "4.704110")
    assert {term.whole_years, term.whole_months} == {4, 8}
    refute term.matured
    refute term.insufficient_data

    assert_scale_6(metrics.current_yield.value, "0.025707")
    refute metrics.current_yield.insufficient_data
    assert metrics.current_yield.missing == []

    assert_scale_6(metrics.yield_to_maturity.value, "0.031718")
    refute metrics.yield_to_maturity.insufficient_data
  end

  # User story (#330, board A4):
  # As the operator holding a bond no quote has priced yet,
  # I want the yields computed from the price the valuation uses (my own last
  # trade), and told which price that was,
  # so that the figures and the value beside them cannot disagree.
  #
  # Acceptance criteria:
  # - A trade price of 98.50 gives 0.025381 and 0.028618, and each yield
  #   carries the price, its date and its source.
  test "uses the price it is given, and carries that price's source and date" do
    price = %{value: dec("98.50"), date: ~D[2026-03-12], source: :trade}
    metrics = BondMetrics.compute(@terms, price, dec("100"), @as_of)

    assert_scale_6(metrics.current_yield.value, "0.025381")
    assert_scale_6(metrics.yield_to_maturity.value, "0.028618")
    assert metrics.current_yield.price == price
    assert metrics.yield_to_maturity.price == price
  end

  # User story (#330, board A2 and A3):
  # As the operator reading a bond whose master data is partly entered, or
  # that has matured,
  # I want each figure that cannot be computed to say which input it lacks,
  # or that the bond has matured, instead of a number,
  # so that a missing figure is never read as zero.
  #
  # Acceptance criteria:
  # - Without a coupon both yields are null, insufficient_data, missing
  #   coupon_rate; the remaining term still computes.
  # - Without a maturity the remaining term and the yield to maturity are
  #   null and name maturity_date; the current yield still computes.
  # - Without a price both yields name price.
  # - On and after the maturity date the term is matured and neither yield
  #   computes (matured, not insufficient data).
  # - A zero coupon is a current yield of exactly 0.
  test "names the missing input, or the maturity, instead of computing a number" do
    no_coupon = BondMetrics.compute(%{@terms | coupon_rate: nil}, @quote_price, dec("1"), @as_of)
    assert no_coupon.current_yield.value == nil
    assert no_coupon.current_yield.insufficient_data
    assert no_coupon.current_yield.missing == ["coupon_rate"]
    assert no_coupon.yield_to_maturity.missing == ["coupon_rate"]
    assert no_coupon.remaining_term.days == 1717

    no_maturity =
      BondMetrics.compute(%{@terms | maturity_date: nil}, @quote_price, dec("1"), @as_of)

    assert no_maturity.remaining_term.years == nil
    assert no_maturity.remaining_term.insufficient_data
    assert no_maturity.remaining_term.missing == ["maturity_date"]
    assert no_maturity.yield_to_maturity.missing == ["maturity_date"]
    assert_scale_6(no_maturity.current_yield.value, "0.025707")

    no_price = %{value: nil, date: nil, source: nil}
    unpriced = BondMetrics.compute(@terms, no_price, dec("1"), @as_of)
    assert unpriced.current_yield.missing == ["price"]
    assert unpriced.yield_to_maturity.missing == ["price"]

    for as_of <- [~D[2031-06-15], ~D[2031-07-01]] do
      matured = BondMetrics.compute(@terms, @quote_price, dec("1"), as_of)
      assert matured.remaining_term.matured
      assert matured.remaining_term.years == nil
      refute matured.remaining_term.insufficient_data

      for yield <- [matured.current_yield, matured.yield_to_maturity] do
        assert yield.value == nil
        assert yield.matured
        refute yield.insufficient_data
      end
    end

    zero = BondMetrics.compute(%{@terms | coupon_rate: dec("0")}, @quote_price, dec("1"), @as_of)
    assert Decimal.equal?(zero.current_yield.value, dec("0"))
  end

  # User story (#330, the two-scales guard; bond discovery, point 5):
  # As the operator whose export may have booked a bond's nominal as its
  # quantity,
  # I want a bond whose stored quotes sit near 100 while its booked price per
  # unit sits near 1 named as priced on two scales,
  # so that a hundredfold value the TTWROR cannot show is visible.
  #
  # Acceptance criteria:
  # - A latest quote of 97.25 against a buy at 0.985 is named, with the
  #   quote, the count of buys on the unit scale and the last of them.
  # - A buy at 98.50 (the hundredth reading) is not named, nor is a bond
  #   without a quote.
  # - The band is 20 to 500 times, both ends included; a ratio just under
  #   20 or just over 500 is not named.
  test "names a bond priced on two scales, and nothing else" do
    latest = %{close: dec("97.25"), date: ~D[2026-09-30]}

    buys = [
      %{price: dec("0.98"), date: ~D[2026-02-01]},
      %{price: dec("0.985"), date: ~D[2026-03-12]}
    ]

    finding = BondMetrics.two_scales(latest, buys)
    assert finding.latest_quote == latest
    assert finding.unit_scale_buys == 2
    assert finding.last_unit_scale_buy == %{price: dec("0.985"), date: ~D[2026-03-12]}

    assert BondMetrics.two_scales(latest, [%{price: dec("98.50"), date: ~D[2026-03-12]}]) == nil
    assert BondMetrics.two_scales(nil, buys) == nil
    assert BondMetrics.two_scales(latest, []) == nil

    at = fn close, price ->
      BondMetrics.two_scales(%{close: dec(close), date: @as_of}, [
        %{price: dec(price), date: @as_of}
      ])
    end

    assert at.("100", "5")
    assert at.("100", "0.2")
    refute at.("99.99", "5")
    refute at.("100.01", "0.2")
  end
end
