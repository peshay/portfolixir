defmodule PortfolixirWeb.PrivacyModeFormatTest do
  # Sprint 26 P1 (I22, FR-51; plan D-4, D-5; board 01, look C): while the
  # privacy mode is on, every figure the formatters render in a currency or
  # as a quantity is replaced on the server by one constant placeholder, so
  # neither its digits nor its length reach the page. The mode is set for
  # the process that renders (`PortfolixirWeb.PrivacyMode.put/1`), so no
  # call site can forget it.
  use ExUnit.Case, async: true

  alias Phoenix.HTML.Safe
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.PrivacyMode

  # The mode lives in the test's own process, which ends with the test.
  defp html(value), do: value |> Safe.to_iodata() |> IO.iodata_to_binary()

  # User story (P1):
  # As the operator showing my portfolio on a screen others can see,
  # I want every amount and every quantity hidden while the privacy mode is on,
  # so that neither the figure nor its length can be read off the page.
  #
  # Acceptance criteria:
  # - In the mode, money/2, native_amount/2, exact/2, decimal/3 and
  #   signed_decimal/3 render one constant placeholder, the same for any
  #   value and any locale, holding no digit.
  # - The placeholder renders as look C's bar (`pf-mask`) with an
  #   accessible name and no text, and reads as a digit-free text where a
  #   string is needed (an interpolation, a JSON payload).
  # - Percentages (percent/2, signed_percent/2) and the plain forms for a
  #   figure that is no amount (a ratio, a rate) stay; a missing value still
  #   reads as an em dash.
  # - Off, every formatter renders the figure as before.
  test "the formatters hide every amount and quantity behind one constant placeholder" do
    PrivacyMode.put(true)

    big = Decimal.new("88307.02")
    small = Decimal.new("-19.5")

    masked = [
      Format.money(big, "de"),
      Format.money(small, "en"),
      Format.native_amount(big),
      Format.exact(Decimal.new("30")),
      Format.decimal(big, 2),
      Format.decimal(Decimal.new("0"), 4),
      Format.signed_decimal(small, 2)
    ]

    rendered = Enum.map(masked, &html/1)
    assert rendered |> Enum.uniq() |> length() == 1
    [bar] = Enum.uniq(rendered)
    assert bar =~ "pf-mask"
    assert bar =~ "aria-label"
    refute bar =~ ~r/\d/

    texts = masked |> Enum.map(&to_string/1) |> Enum.uniq()
    assert [text] = texts
    refute text =~ ~r/\d/
    assert Jason.encode!(%{"a" => Format.money(big)}) == Jason.encode!(%{"a" => text})
    refute "#{Format.money(big)} EUR" =~ ~r/\d/

    assert Format.percent(Decimal.new("0.185"), "de") == "18,5"
    assert Format.signed_percent(Decimal.new("0.09"), "de") == "+9,0"
    assert Format.plain_decimal(Decimal.new("1.0912"), 2, "de") == "1,09"
    assert Format.plain_signed_decimal(Decimal.new("12.34"), 1, "de") == "+12,3"
    assert Format.plain_exact(Decimal.new("1.08"), "de") == "1,08"
    assert Format.money(nil) == "—"
    assert Format.decimal(nil, 2) == "—"

    PrivacyMode.put(false)
    assert Format.money(big, "de") == "88.307,02"
    assert Format.signed_decimal(small, 2, "en") == "-19.50"
    assert Format.exact(Decimal.new("30"), "en") == "30"
  end
end
