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
