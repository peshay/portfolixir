defmodule Portfolixir.Catalog.LogoLookup.CryptoMapTest do
  # User story:
  # As a maintainer importing cryptos from Portfolio Performance (which carry
  # no CoinGecko online_id), I want their ticker or name mapped to the right
  # CoinGecko coin id so a logo can still be fetched.
  use ExUnit.Case, async: true

  alias Portfolixir.Catalog.LogoLookup.CryptoMap
  alias Portfolixir.Catalog.Security

  test "maps known tickers to CoinGecko ids" do
    assert CryptoMap.coin_id(%Security{ticker_symbol: "BTC", name: "Bitcoin"}) == "bitcoin"
    assert CryptoMap.coin_id(%Security{ticker_symbol: "ETH", name: "Ether"}) == "ethereum"
    assert CryptoMap.coin_id(%Security{ticker_symbol: "XRP", name: "XRP"}) == "ripple"
    assert CryptoMap.coin_id(%Security{ticker_symbol: "DOGE", name: "Dogecoin"}) == "dogecoin"
  end

  test "strips a fiat pair suffix from the ticker" do
    assert CryptoMap.coin_id(%Security{ticker_symbol: "BTC-EUR", name: "x"}) == "bitcoin"
    assert CryptoMap.coin_id(%Security{ticker_symbol: "eth.x", name: "x"}) == "ethereum"
  end

  test "falls back to the spelled-out name when the ticker is unknown" do
    assert CryptoMap.coin_id(%Security{ticker_symbol: nil, name: "Bitcoin"}) == "bitcoin"
    assert CryptoMap.coin_id(%Security{ticker_symbol: "", name: "Solana"}) == "solana"
  end

  test "returns nil for coins not in the curated table" do
    assert CryptoMap.coin_id(%Security{ticker_symbol: "ZZZ", name: "Mystery Coin"}) == nil
    assert CryptoMap.coin_id(%Security{ticker_symbol: nil, name: nil}) == nil
  end
end
