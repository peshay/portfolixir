defmodule Portfolixir.Catalog.SecurityTickerFormatTest do
  # Issue #763: a ticker is placed into provider request paths, so its shape
  # is validated at the schema rather than trusted at each adapter.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Catalog.Security

  # User story:
  # As an operator,
  # I want a ticker symbol refused when it carries whitespace or URL syntax,
  # so that a mistyped or imported value can never reach a provider as anything but a symbol.
  #
  # Acceptance criteria:
  # - Real-world shapes pass: BRK-B, ^GDAXI, EURUSD=X, SAP.DE, 0005.HK, BTC-USD.
  # - Whitespace, "/", "?", "#", "%" and over-long values are refused.
  test "accepts real ticker shapes and refuses URL syntax" do
    for ticker <- ["BRK-B", "^GDAXI", "EURUSD=X", "SAP.DE", "0005.HK", "BTC-USD", "AAPL"] do
      changeset =
        Security.changeset(%Security{}, %{name: "S", currency_code: "EUR", ticker_symbol: ticker})

      assert changeset.valid?, ticker
    end

    for ticker <- ["A B", "A/B", "A?B", "A#B", "A%2FB", String.duplicate("A", 65)] do
      changeset =
        Security.changeset(%Security{}, %{name: "S", currency_code: "EUR", ticker_symbol: ticker})

      refute changeset.valid?, ticker
      assert errors_on(changeset)[:ticker_symbol]
    end
  end
end
