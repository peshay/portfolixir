defmodule Portfolixir.Catalog.SecuritySearch.Market do
  @moduledoc "A single market/listing offered for a search hit."
  defstruct [
    :symbol,
    :currency_code,
    :exchange_code,
    :exchange_name,
    :url,
    properties: %{}
  ]
end

defmodule Portfolixir.Catalog.SecuritySearch.SearchResult do
  @moduledoc """
  Normalized search hit, provider-agnostic. `markets` may be empty (the UI
  skips the market-selection step) or list multiple options.
  """

  alias Portfolixir.Catalog.SecuritySearch.Market

  @enforce_keys [:provider, :name]
  defstruct [
    :provider,
    :online_id,
    :name,
    :isin,
    :wkn,
    :ticker_symbol,
    :asset_class,
    :currency_code,
    :feed,
    markets: [],
    raw: %{}
  ]

  @doc """
  Builds the attribute map passed to `Security.changeset/2`. Market overrides
  the result's defaults for ticker, currency, exchange, and feed URL when one
  is selected.
  """
  def to_security_attrs(%__MODULE__{} = result, market \\ nil) do
    %{
      name: result.name,
      ticker_symbol: pick(market && market.symbol, result.ticker_symbol),
      isin: result.isin,
      wkn: result.wkn,
      currency_code: pick(market && market.currency_code, result.currency_code),
      exchange_code: market && market.exchange_code,
      asset_class: result.asset_class,
      provider: provider_to_string(result.provider),
      online_id: result.online_id,
      feed: result.feed,
      feed_url: market && market.url,
      attributes: build_attributes(result, market)
    }
    |> drop_nil()
  end

  defp pick(nil, fallback), do: fallback
  defp pick("", fallback), do: fallback
  defp pick(value, _fallback), do: value

  defp provider_to_string(:portfolio_performance), do: "portfolio_performance"
  defp provider_to_string(:coingecko), do: "coingecko"
  defp provider_to_string(:fake), do: "manual"
  defp provider_to_string(other) when is_binary(other), do: other
  defp provider_to_string(other) when is_atom(other), do: Atom.to_string(other)

  defp build_attributes(%__MODULE__{} = result, nil) do
    %{}
    |> maybe_put("type", Map.get(result.raw, "type"))
    |> maybe_put("market_cap_rank", Map.get(result.raw, "market_cap_rank"))
  end

  defp build_attributes(%__MODULE__{} = result, %Market{} = market) do
    result
    |> build_attributes(nil)
    |> maybe_put("exchange_name", market.exchange_name)
    |> maybe_put("market_url", market.url)
    |> maybe_merge(market.properties)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_merge(map, nil), do: map
  defp maybe_merge(map, props) when is_map(props), do: Map.merge(map, props)

  defp drop_nil(map) do
    map
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
