defmodule PortfolixirWeb.DecimalInputTest do
  use ExUnit.Case, async: true

  alias PortfolixirWeb.DecimalInput

  # User story (#869, numeric half; board ux-design-2026-09-24/05-numeric-inputs):
  # As the operator typing a figure into any decimal field of the app,
  # I want the field to show its value in my page's language and to read back
  # what I typed by one rule,
  # so that a German page never mixes "242,00" with "1.061404" and no figure
  # is silently stored a thousand times too small or too large.
  #
  # Acceptance criteria:
  # - A value renders with the page's decimal separator — a comma in German, a
  #   point in English — never with a thousands separator, and with the
  #   caller's digits unchanged.
  # - Typed text renders back exactly as typed.
  # - The page's own separator is always the decimal separator. The other
  #   language's separator is read as one too, unless the figure has the shape
  #   of a thousands group ("1.664" on a German page, "1,664" on an English
  #   one) — that reads two ways and is refused, never guessed.
  # - A figure carrying two separators ("1.664,40", "1,664.40", "1.234.567")
  #   is refused as ambiguous; anything that is not a plain decimal
  #   ("1e3", "NaN", "12 000", "abc") is refused as invalid.
  # - Every rendered value parses back to the same Decimal in its own locale.
  describe "value/2 renders in the page's locale" do
    test "a German page shows a decimal comma, never a thousands separator" do
      assert DecimalInput.value(Decimal.new("1664.40"), "de") == "1664,40"
      assert DecimalInput.value(Decimal.new("0.913459"), "de") == "0,913459"
      assert DecimalInput.value(Decimal.new("-2.5"), "de") == "-2,5"
      assert DecimalInput.value(Decimal.new("1664"), "de") == "1664"
      assert DecimalInput.value(Decimal.new("1234567.89"), "de") == "1234567,89"
    end

    test "an English page shows a decimal point, never a thousands separator" do
      assert DecimalInput.value(Decimal.new("1664.40"), "en") == "1664.40"
      assert DecimalInput.value(Decimal.new("1234567.89"), "en") == "1234567.89"
      assert DecimalInput.value(Decimal.new("-2.5"), "en") == "-2.5"
    end

    test "the caller's digits are kept: no rounding, no padding, no trimming" do
      assert DecimalInput.value(Decimal.new("45.6"), "de") == "45,6"
      assert DecimalInput.value(Decimal.new("45.60"), "de") == "45,60"
      assert DecimalInput.value(Decimal.new("0.1234567891"), "en") == "0.1234567891"
    end

    test "typed text renders back as typed, and nothing renders as empty" do
      assert DecimalInput.value("45.60", "de") == "45.60"
      assert DecimalInput.value("1,5", "en") == "1,5"
      assert DecimalInput.value(nil, "de") == ""
    end

    test "the locale defaults to the page's gettext locale" do
      Gettext.put_locale(PortfolixirWeb.Gettext, "de")
      assert DecimalInput.value(Decimal.new("7.5")) == "7,5"

      Gettext.put_locale(PortfolixirWeb.Gettext, "en")
      assert DecimalInput.value(Decimal.new("7.5")) == "7.5"
    end
  end

  describe "parse/2 reads a German page's input" do
    test "the comma is the decimal separator" do
      assert parsed("1664,40", "de") == "1664.40"
      assert parsed("0,913459", "de") == "0.913459"
      assert parsed("1,664", "de") == "1.664"
      assert parsed("-2,5", "de") == "-2.5"
      assert parsed(",5", "de") == "0.5"
      assert parsed("  12,50 ", "de") == "12.50"
    end

    test "a point is a decimal point where it cannot be a thousands group" do
      assert parsed("45.60", "de") == "45.60"
      assert parsed("0.125", "de") == "0.125"
      assert parsed("1664.40", "de") == "1664.40"
      assert parsed("12.5", "de") == "12.5"
    end

    test "a point with the shape of a thousands group is refused, never guessed" do
      assert DecimalInput.parse("1.664", "de") == {:error, :ambiguous}
      assert DecimalInput.parse("12.500", "de") == {:error, :ambiguous}
      assert DecimalInput.parse("-999.999", "de") == {:error, :ambiguous}
    end

    test "grouped figures are refused" do
      assert DecimalInput.parse("1.664,40", "de") == {:error, :ambiguous}
      assert DecimalInput.parse("1,664.40", "de") == {:error, :ambiguous}
      assert DecimalInput.parse("1.234.567", "de") == {:error, :ambiguous}
      assert DecimalInput.parse("1,2,3", "de") == {:error, :ambiguous}
    end
  end

  describe "parse/2 reads an English page's input" do
    test "the point is the decimal separator" do
      assert parsed("1664.40", "en") == "1664.40"
      assert parsed("1.664", "en") == "1.664"
      assert parsed("0.913459", "en") == "0.913459"
      assert parsed("+3", "en") == "3"
    end

    test "a comma is a decimal comma where it cannot be a thousands group" do
      assert parsed("45,60", "en") == "45.60"
      assert parsed("0,125", "en") == "0.125"
      assert parsed("2,5", "en") == "2.5"
    end

    test "a comma with the shape of a thousands group is refused, never guessed" do
      assert DecimalInput.parse("1,664", "en") == {:error, :ambiguous}
      assert DecimalInput.parse("10,000", "en") == {:error, :ambiguous}
      assert DecimalInput.parse("1,664.40", "en") == {:error, :ambiguous}
      assert DecimalInput.parse("1.664,40", "en") == {:error, :ambiguous}
    end
  end

  describe "parse/2 in either locale" do
    test "a blank field is blank, not zero and not an error" do
      for locale <- ["de", "en"], text <- ["", "   ", nil] do
        assert DecimalInput.parse(text, locale) == :blank
      end
    end

    test "anything but a plain decimal is invalid" do
      for locale <- ["de", "en"],
          text <- ["abc", "1e3", "NaN", "Infinity", "12 000", "1.", "5,", "--1", "1-", "٣"] do
        assert DecimalInput.parse(text, locale) == {:error, :invalid},
               "#{inspect(text)} on a #{locale} page"
      end
    end

    test "an overlong figure is invalid" do
      assert DecimalInput.parse(String.duplicate("9", 41), "en") == {:error, :invalid}
    end

    test "a Decimal passes through, so a parsed map can be parsed again" do
      assert DecimalInput.parse(Decimal.new("1.664"), "de") == {:ok, Decimal.new("1.664")}
    end

    test "every rendered value reads back to the same Decimal in its own locale" do
      for locale <- ["de", "en"],
          raw <- ["1664.40", "1.664", "0.913459", "-2.5", "1234567.89", "0", "12.500"] do
        decimal = Decimal.new(raw)
        assert {:ok, back} = DecimalInput.parse(DecimalInput.value(decimal, locale), locale)
        assert Decimal.equal?(back, decimal), "#{raw} on a #{locale} page"
      end
    end
  end

  describe "cast/3 at a form's boundary" do
    test "parses the named fields to Decimals and leaves every other key alone" do
      params = %{"quantity" => "2,5", "price" => "100.50", "fees" => "", "notes" => "1,664"}

      assert {:ok, cast} = DecimalInput.cast(params, ~w(quantity price fees missing), "de")
      assert cast["quantity"] == Decimal.new("2.5")
      assert cast["price"] == Decimal.new("100.50")
      assert cast["fees"] == ""
      assert cast["notes"] == "1,664"
      refute Map.has_key?(cast, "missing")
    end

    test "names every refused field with the reason in the page's language" do
      Gettext.put_locale(PortfolixirWeb.Gettext, "de")

      assert {:error, errors} =
               DecimalInput.cast(%{"quantity" => "1.664", "price" => "abc"}, ~w(quantity price))

      assert errors["quantity"] =~ "mehrdeutig"
      assert errors["price"] == "ist ungültig"
    end
  end

  defp parsed(text, locale) do
    {:ok, decimal} = DecimalInput.parse(text, locale)
    Decimal.to_string(decimal, :normal)
  end
end
