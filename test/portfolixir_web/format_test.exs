defmodule PortfolixirWeb.FormatTest do
  use ExUnit.Case, async: true

  alias PortfolixirWeb.Format

  # User story:
  # As a German-speaking portfolio maintainer,
  # I want money shown as 1.234.567,89 (thousands dot, decimal comma, exactly
  # two decimals) and percentages as 18,5 when the app language is German,
  # so that the numbers read naturally in my locale — while English keeps
  # 1,234,567.89.
  #
  # Acceptance criteria:
  # - German money formatting groups thousands with "." and uses "," for cents.
  # - English money formatting groups thousands with "," and uses "." for cents.
  # - Money always shows exactly two decimals; percent shows one.
  # - Negative values keep the sign in front of the grouped digits.
  # - Non-Decimal input renders an em dash instead of crashing.
  test "formats money and percent per locale" do
    big = Decimal.new("1234567.891")

    assert Format.money(big, "de") == "1.234.567,89"
    assert Format.money(big, "en") == "1,234,567.89"

    assert Format.money(Decimal.new("4250"), "de") == "4.250,00"
    assert Format.money(Decimal.new("4250"), "en") == "4,250.00"

    assert Format.money(Decimal.new("-98765.4"), "de") == "-98.765,40"
    assert Format.money(Decimal.new("-98765.4"), "en") == "-98,765.40"

    assert Format.money(Decimal.new("0.5"), "de") == "0,50"
    assert Format.money(Decimal.new("12"), "en") == "12.00"

    assert Format.percent(Decimal.new("0.185"), "de") == "18,5"
    assert Format.percent(Decimal.new("0.185"), "en") == "18.5"
    assert Format.percent(Decimal.new("3"), "de") == "300,0"

    assert Format.money(nil) == "—"
    assert Format.percent(nil) == "—"
  end

  test "defaults to the current gettext locale" do
    previous = Gettext.get_locale(PortfolixirWeb.Gettext)

    try do
      Gettext.put_locale(PortfolixirWeb.Gettext, "de")
      assert Format.money(Decimal.new("1234.5")) == "1.234,50"

      Gettext.put_locale(PortfolixirWeb.Gettext, "en")
      assert Format.money(Decimal.new("1234.5")) == "1,234.50"
    after
      Gettext.put_locale(PortfolixirWeb.Gettext, previous)
    end
  end

  # User story:
  # As a portfolio maintainer viewing securities detail, holdings, and transaction
  # tables, I want all displayed Decimal numbers (quantities, prices, fees, etc.)
  # to use the locale-aware Format.decimal/2 helper, so that DE users see
  # "1.234,50" and EN users see "1,234.50" for the same value — consistently
  # with how money and percentages are already formatted.
  #
  # Acceptance criteria:
  # - Format.decimal/3 formats with N decimal places and applies locale separators.
  # - Format.signed_decimal/3 prepends "+" for positive values and applies
  #   locale separators.
  # - Non-Decimal inputs return an em dash for both functions.
  test "Format.decimal/3 applies locale separators with given decimal places" do
    assert Format.decimal(Decimal.new("1234.5"), 2, "de") == "1.234,50"
    assert Format.decimal(Decimal.new("1234.5"), 2, "en") == "1,234.50"
    assert Format.decimal(Decimal.new("1234.5678"), 4, "de") == "1.234,5678"
    assert Format.decimal(Decimal.new("1234.5678"), 4, "en") == "1,234.5678"
    assert Format.decimal(Decimal.new("0"), 2, "de") == "0,00"
    assert Format.decimal(Decimal.new("0"), 2, "en") == "0.00"
    assert Format.decimal(nil, 2, "en") == "—"
    assert Format.decimal("not_a_decimal", 2, "de") == "—"
  end

  test "Format.signed_decimal/3 prepends + for positive values with locale separators" do
    assert Format.signed_decimal(Decimal.new("500"), 2, "de") == "+500,00"
    assert Format.signed_decimal(Decimal.new("500"), 2, "en") == "+500.00"
    assert Format.signed_decimal(Decimal.new("1234.5"), 2, "de") == "+1.234,50"
    assert Format.signed_decimal(Decimal.new("1234.5"), 2, "en") == "+1,234.50"
    assert Format.signed_decimal(Decimal.new("-500"), 2, "de") == "-500,00"
    assert Format.signed_decimal(Decimal.new("-500"), 2, "en") == "-500.00"
    assert Format.signed_decimal(Decimal.new("0"), 2, "en") == "0.00"
    assert Format.signed_decimal(nil, 2, "en") == "—"
  end

  # User story (E17 closing-act review, finding 10):
  # As a German-locale user reading a dialog error that names a date,
  # I want dates formatted under the active locale,
  # so that copy does not mix German text with bare ISO dates.
  #
  # Acceptance criteria:
  # - "de" renders DD.MM.YYYY, other locales the ISO form.
  # - Without an explicit locale the current gettext locale applies.
  # - Non-dates render as an em dash.
  test "Format.date/2 localizes dates (German dotted, ISO elsewhere)" do
    assert Format.date(~D[2026-07-22], "de") == "22.07.2026"
    assert Format.date(~D[2026-07-22], "en") == "2026-07-22"
    assert Format.date(nil, "de") == "—"

    previous = Gettext.get_locale(PortfolixirWeb.Gettext)

    try do
      Gettext.put_locale(PortfolixirWeb.Gettext, "de")
      assert Format.date(~D[2026-01-05]) == "05.01.2026"
    after
      Gettext.put_locale(PortfolixirWeb.Gettext, previous)
    end
  end

  # User story (#1055, review round; UX-DR25 clause 2):
  # As a local portfolio maintainer reading a balance no rate converts,
  # I want it in the house's two decimals, and every further digit it
  # carries,
  # so that a balance of a fraction of a cent never reads as 0,00 next to a
  # finding that says it holds money.
  #
  # Acceptance criteria:
  # - At least two places: 2000 reads "2.000,00", and a stored scale of six
  #   trailing zeros reads the same.
  # - More when the amount carries more: 0.004 reads "0,004", -0.0015 reads
  #   "-0,0015".
  # - Non-numbers render as an em dash.
  test "Format.native_amount/2 keeps two places and every further digit" do
    assert Format.native_amount(Decimal.new("2000"), "de") == "2.000,00"
    assert Format.native_amount(Decimal.new("2000.000000"), "de") == "2.000,00"
    assert Format.native_amount(Decimal.new("1850.5"), "en") == "1,850.50"
    assert Format.native_amount(Decimal.new("0.004"), "de") == "0,004"
    assert Format.native_amount(Decimal.new("-0.0015"), "en") == "-0.0015"
    assert Format.native_amount(nil, "de") == "—"
  end

  # User story (#1089 and #1060, Sprint 19 PR γ U2; board
  # ux-design-2026-10-04/04-trades):
  # As a local portfolio maintainer reading a trade's return,
  # I want every signed percent on the trades surfaces formatted by one
  # helper,
  # so that the facet, the security's Trades tab and the Overview card print
  # the same return the same way — "+27,1%", never "27,1%" or "+27,07 %".
  #
  # Acceptance criteria:
  # - Format.signed_percent/2 formats a Decimal fraction with one decimal
  #   and locale separators, the percent sign left to the caller like
  #   Format.percent/2.
  # - A positive value carries an explicit "+", a negative one its "-", a
  #   zero none.
  # - The sign is decided on the percent as displayed, rounded to its one
  #   decimal (Sprint 19 U2 review): a value that rounds to 0.0 reads "0.0"
  #   from either side, never "+0.0" or "-0.0".
  # - Non-Decimal inputs render as an em dash.
  test "Format.signed_percent/2 signs a fraction as a one-decimal percent" do
    assert Format.signed_percent(Decimal.new("0.2707"), "de") == "+27,1"
    assert Format.signed_percent(Decimal.new("0.2707"), "en") == "+27.1"
    assert Format.signed_percent(Decimal.new("-0.051"), "de") == "-5,1"
    assert Format.signed_percent(Decimal.new("12.345"), "de") == "+1.234,5"
    assert Format.signed_percent(Decimal.new("0"), "en") == "0.0"
    assert Format.signed_percent(Decimal.new("0.0004"), "en") == "0.0"
    assert Format.signed_percent(Decimal.new("0.00004"), "de") == "0,0"
    assert Format.signed_percent(Decimal.new("-0.0004"), "en") == "0.0"
    assert Format.signed_percent(Decimal.new("-0.00004"), "de") == "0,0"
    assert Format.signed_percent(Decimal.new("0.0005"), "en") == "+0.1"
    assert Format.signed_percent(Decimal.new("-0.0005"), "en") == "-0.1"
    assert Format.signed_percent(nil, "en") == "—"
    assert Format.signed_percent("0.1", "en") == "—"
  end

  # User story (Sprint 19 PR γ U2 review; DESIGN.md → Trades):
  # As a local portfolio maintainer reading a signed figure, and as one who
  # cannot tell its green from its red,
  # I want its sign and its colour decided on the figure as it is displayed,
  # so that a value that rounds to zero never reads "+0,0", "-0,00", or
  # "0,00" in the gain colour.
  #
  # Acceptance criteria:
  # - Format.signed_decimal/3 prints a value that rounds to zero without a
  #   sign from either side: -0.004 at two places reads "0,00", not "-0,00".
  # - Format.displayed_sign/2 is the sign of the value rounded to the places
  #   it is displayed at: :positive, :negative or :zero; nil for a
  #   non-number. The colour classes follow it.
  # - Format.displayed_percent_sign/1 is the same at the precision of a
  #   one-decimal percent (Format.percent/2, Format.signed_percent/2).
  test "a figure that rounds to zero is unsigned and directionless" do
    assert Format.signed_decimal(Decimal.new("-0.004"), 2, "de") == "0,00"
    assert Format.signed_decimal(Decimal.new("0.004"), 2, "de") == "0,00"
    assert Format.signed_decimal(Decimal.new("-0.004"), 2, "en") == "0.00"
    assert Format.signed_decimal(Decimal.new("0.005"), 2, "en") == "+0.01"
    assert Format.signed_decimal(Decimal.new("-0.005"), 2, "en") == "-0.01"
    assert Format.signed_decimal(Decimal.new("-1234.5"), 2, "de") == "-1.234,50"

    assert Format.displayed_sign(Decimal.new("0.004"), 2) == :zero
    assert Format.displayed_sign(Decimal.new("-0.004"), 2) == :zero
    assert Format.displayed_sign(Decimal.new("0"), 2) == :zero
    assert Format.displayed_sign(Decimal.new("0.005"), 2) == :positive
    assert Format.displayed_sign(Decimal.new("-0.005"), 2) == :negative
    assert Format.displayed_sign(nil, 2) == nil

    assert Format.displayed_percent_sign(Decimal.new("0.00004")) == :zero
    assert Format.displayed_percent_sign(Decimal.new("-0.00049")) == :zero
    assert Format.displayed_percent_sign(Decimal.new("0.0005")) == :positive
    assert Format.displayed_percent_sign(Decimal.new("-0.0005")) == :negative
    assert Format.displayed_percent_sign("0.1") == nil
  end

  test "Format.decimal/2 and Format.signed_decimal/2 default to current gettext locale" do
    previous = Gettext.get_locale(PortfolixirWeb.Gettext)

    try do
      Gettext.put_locale(PortfolixirWeb.Gettext, "de")
      assert Format.decimal(Decimal.new("1234.5"), 2) == "1.234,50"
      assert Format.signed_decimal(Decimal.new("1234.5"), 2) == "+1.234,50"

      Gettext.put_locale(PortfolixirWeb.Gettext, "en")
      assert Format.decimal(Decimal.new("1234.5"), 2) == "1,234.50"
      assert Format.signed_decimal(Decimal.new("1234.5"), 2) == "+1,234.50"
    after
      Gettext.put_locale(PortfolixirWeb.Gettext, previous)
    end
  end
end
