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

  Every field comes from a provider payload, so `bound/1` type-matches and
  size-bounds each of them before a hit reaches a response or a security
  (E25 S3, F29): a text field of the wrong type or over its bound is dropped,
  a hit without a usable name is dropped, markets keep bounded fields and
  bounded scalar properties, and `raw` keeps only the allow-listed keys the
  attributes read, as bounded scalars — never the provider's whole entry.
  """

  alias Portfolixir.Catalog.SecuritySearch.Market
  alias Portfolixir.Catalog.SecuritySearch.Properties

  @type t :: %__MODULE__{}

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

  # Codepoint bounds per text field: the column's width where a field lands in
  # one, the provider-id and ticker bounds of the security changeset, and a
  # short bound for codes.
  @text_bounds [
    online_id: 128,
    name: 255,
    isin: 32,
    wkn: 32,
    ticker_symbol: 64,
    asset_class: 64,
    currency_code: 16,
    feed: 64
  ]
  @market_bounds [
    symbol: 64,
    currency_code: 16,
    exchange_code: 64,
    exchange_name: 255,
    url: 255
  ]
  @max_markets 50
  @raw_keys ~w(type market_cap_rank)

  @doc """
  The hit with every provider-derived field type-matched and bounded, or
  `nil` when it has no usable name. Idempotent, so the adapters and the search
  orchestrator may both apply it.
  """
  @spec bound(t()) :: t() | nil
  def bound(%__MODULE__{} = result) do
    bounded =
      Enum.reduce(@text_bounds, result, fn {field, max}, acc ->
        Map.update!(acc, field, &text(&1, max))
      end)

    case bounded.name do
      nil -> nil
      _name -> %{bounded | markets: bound_markets(result.markets), raw: bound_raw(result.raw)}
    end
  end

  def bound(_not_a_result), do: nil

  @doc "A provider text value within `max` codepoints, trimmed, or `nil`."
  @spec text(term(), pos_integer()) :: String.t() | nil
  def text(value, max) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed != "" and String.valid?(trimmed) and codepoints_within?(trimmed, max),
      do: trimmed,
      else: nil
  end

  def text(_value, _max), do: nil

  defp codepoints_within?(value, max),
    do: byte_size(value) <= max or length(String.codepoints(value)) <= max

  defp bound_markets(markets) when is_list(markets) do
    markets
    |> Enum.flat_map(&bound_market/1)
    |> Enum.take(@max_markets)
  end

  defp bound_markets(_markets), do: []

  # A listing without a symbol of the right shape is not a listing.
  defp bound_market(%Market{} = market) do
    bounded =
      Enum.reduce(@market_bounds, market, fn {field, max}, acc ->
        Map.update!(acc, field, &text(&1, max))
      end)

    case bounded.symbol do
      nil -> []
      _symbol -> [%{bounded | properties: Properties.sanitize(market.properties)}]
    end
  end

  defp bound_market(_other), do: []

  defp bound_raw(raw) when is_map(raw), do: raw |> Map.take(@raw_keys) |> Properties.sanitize()
  defp bound_raw(_raw), do: %{}

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

  # Every provider-derived attribute passes the scalar-and-length rule the
  # market properties pass (F29), whatever the hit's path here.
  defp build_attributes(%__MODULE__{} = result, market) do
    result
    |> base_attributes(market)
    |> Properties.sanitize()
  end

  defp base_attributes(%__MODULE__{} = result, nil) do
    raw = if is_map(result.raw), do: result.raw, else: %{}

    %{}
    |> maybe_put("type", Map.get(raw, "type"))
    |> maybe_put("market_cap_rank", Map.get(raw, "market_cap_rank"))
  end

  defp base_attributes(%__MODULE__{} = result, %Market{} = market) do
    result
    |> base_attributes(nil)
    |> maybe_put("exchange_name", market.exchange_name)
    |> maybe_put("market_url", market.url)
    |> maybe_merge(market.properties)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_merge(map, props) when is_map(props), do: Map.merge(map, props)
  defp maybe_merge(map, _props), do: map

  defp drop_nil(map) do
    map
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
