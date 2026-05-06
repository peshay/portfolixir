defmodule PortfolixirWeb.AmountFormatTest do
  use ExUnit.Case, async: true

  alias PortfolixirWeb.AmountFormat

  test "formats valuation amounts with fixed precision and currency code" do
    assert AmountFormat.format_currency_amount(Decimal.new("120"), "EUR") == "120.00 EUR"
    assert AmountFormat.format_currency_amount(Decimal.new("111.111"), " USD ") == "111.11 USD"
  end

  test "uses an explicit neutral fallback for unavailable valuation amounts" do
    assert AmountFormat.format_currency_amount(nil, "EUR") == "Unavailable"
  end
end
