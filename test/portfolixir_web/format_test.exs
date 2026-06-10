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
end
