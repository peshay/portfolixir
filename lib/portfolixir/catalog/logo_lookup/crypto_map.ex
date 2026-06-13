defmodule Portfolixir.Catalog.LogoLookup.CryptoMap do
  @moduledoc """
  Maps a crypto security to its CoinGecko coin id so a logo can be fetched
  even when the security was not created through the CoinGecko search.

  Portfolio Performance imports cryptos with `provider =
  "portfolio_performance"` and no `online_id`, so the
  `provider = "coingecko"` logo path never triggers for them. This table
  bridges the common spellings (ticker first, then name) to the canonical
  CoinGecko id used by `CoinGecko.fetch_image_url/2`.

  The table is intentionally small and curated — it covers the majority of
  positions a German retail PP export carries. Unknown coins simply fall
  back to the initials placeholder; they can still be given a logo via the
  manual override.
  """

  alias Portfolixir.Catalog.Security

  # Ticker symbol (upper-case, without a fiat suffix) -> CoinGecko coin id.
  @by_ticker %{
    "BTC" => "bitcoin",
    "XBT" => "bitcoin",
    "ETH" => "ethereum",
    "XRP" => "ripple",
    "DOGE" => "dogecoin",
    "SOL" => "solana",
    "ADA" => "cardano",
    "DOT" => "polkadot",
    "LTC" => "litecoin",
    "LINK" => "chainlink",
    "AVAX" => "avalanche-2",
    "TRX" => "tron",
    "BCH" => "bitcoin-cash",
    "BNB" => "binancecoin",
    "USDT" => "tether",
    "USDC" => "usd-coin",
    "MATIC" => "matic-network",
    "POL" => "matic-network",
    "SHIB" => "shiba-inu",
    "XLM" => "stellar",
    "ATOM" => "cosmos",
    "UNI" => "uniswap",
    "ETC" => "ethereum-classic",
    "ALGO" => "algorand",
    "VET" => "vechain",
    "FIL" => "filecoin",
    "NEAR" => "near",
    "APT" => "aptos",
    "ARB" => "arbitrum",
    "OP" => "optimism",
    "AAVE" => "aave",
    "MKR" => "maker",
    "GRT" => "the-graph",
    "XMR" => "monero",
    "XTZ" => "tezos",
    "EOS" => "eos",
    "SAND" => "the-sandbox",
    "MANA" => "decentraland"
  }

  # Lower-case normalized name -> CoinGecko coin id, for imports that carry a
  # spelled-out name but no usable ticker.
  @by_name %{
    "bitcoin" => "bitcoin",
    "ethereum" => "ethereum",
    "ether" => "ethereum",
    "ripple" => "ripple",
    "xrp" => "ripple",
    "dogecoin" => "dogecoin",
    "solana" => "solana",
    "cardano" => "cardano",
    "polkadot" => "polkadot",
    "litecoin" => "litecoin",
    "chainlink" => "chainlink",
    "avalanche" => "avalanche-2",
    "tron" => "tron",
    "bitcoin cash" => "bitcoin-cash",
    "stellar" => "stellar",
    "stellar lumens" => "stellar",
    "polygon" => "matic-network",
    "monero" => "monero",
    "tezos" => "tezos",
    "cosmos" => "cosmos"
  }

  @doc """
  Returns the CoinGecko coin id for a security, or `nil` when it is not in
  the curated table.

  The ticker symbol is consulted first (a trailing fiat pair such as
  `BTC-EUR` or `BTC.X` is stripped), then the spelled-out name.
  """
  @spec coin_id(Security.t()) :: String.t() | nil
  def coin_id(%Security{ticker_symbol: ticker, name: name}) do
    from_ticker(ticker) || from_name(name)
  end

  def coin_id(_), do: nil

  defp from_ticker(ticker) when is_binary(ticker) do
    ticker
    |> String.upcase()
    |> String.trim()
    |> String.replace(~r/[-.\/](EUR|USD|USDT|USDC|GBP|CHF|X)\z/i, "")
    |> then(&Map.get(@by_ticker, &1))
  end

  defp from_ticker(_), do: nil

  defp from_name(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.trim()
    |> then(&Map.get(@by_name, &1))
  end

  defp from_name(_), do: nil
end
