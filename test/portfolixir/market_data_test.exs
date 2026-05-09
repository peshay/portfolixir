defmodule Portfolixir.MarketDataTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.MarketData
  alias Portfolixir.FakeMarketDataProvider

  test "search normalizes Yahoo-style security candidates through provider abstraction" do
    assert {:ok, [candidate]} = MarketData.search_securities(FakeMarketDataProvider, %{}, "Apple")

    assert candidate.name == "Apple Inc."
    assert candidate.provider_symbol == "AAPL"
    assert candidate.currency_code == "USD"
    assert candidate.exchange_code == "NMS"
    assert candidate.provider_source == "yahoo"
  end

  test "AAPL and MSFT searches are served without live HTTP" do
    assert {:ok, [%{provider_symbol: "AAPL"}]} =
             MarketData.search_securities(FakeMarketDataProvider, %{}, "AAPL")

    assert {:ok, [%{provider_symbol: "MSFT"}]} =
             MarketData.search_securities(FakeMarketDataProvider, %{}, "MSFT")
  end

  test "preview and historical quotes keep provider source and close data" do
    assert {:ok, [candidate]} = MarketData.search_securities(FakeMarketDataProvider, %{}, "AAPL")
    assert {:ok, preview} = MarketData.preview_security(FakeMarketDataProvider, %{}, candidate)

    assert preview.latest_close == "185.64"
    assert preview.latest_close_date == ~D[2024-01-03]
    assert preview.provider_source == "yahoo"

    assert {:ok, quotes} =
             MarketData.historical_quotes(FakeMarketDataProvider, %{}, preview, %{
               range: "1y",
               interval: "1d"
             })

    assert Enum.map(quotes, & &1.close) == ["184.25", "185.64"]
    assert Enum.all?(quotes, &(&1.source == "yahoo"))
  end

  test "unsupported write-like capabilities return explicit error" do
    for capability <- ["place_order", "create_payment", "withdraw", "transfer", "trade"] do
      assert {:error, {:unsupported_capability, ^capability}} =
               MarketData.call(FakeMarketDataProvider, capability, %{}, %{}, %{})
    end
  end
end
