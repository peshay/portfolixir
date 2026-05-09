defmodule Portfolixir.MarketData do
  @moduledoc "Read-only market data provider abstraction for securities and quotes."

  @read_capabilities ["search_securities", "preview_security", "read_historical_quotes"]
  @write_like_capabilities ["place_order", "create_payment", "withdraw", "transfer", "trade"]

  @spec capabilities() :: [String.t()]
  def capabilities, do: @read_capabilities

  @spec default_provider() :: {module(), map()}
  def default_provider do
    Application.get_env(
      :portfolixir,
      :market_data_provider,
      {Portfolixir.MarketData.YahooFinanceProvider, %{}}
    )
  end

  @spec search_securities(String.t()) :: {:ok, [map()]} | {:error, term()}
  def search_securities(query) when is_binary(query) do
    {provider, config} = default_provider()
    search_securities(provider, config, query)
  end

  @spec search_securities(module(), map(), String.t()) :: {:ok, [map()]} | {:error, term()}
  def search_securities(provider, config, query)
      when is_atom(provider) and is_map(config) and is_binary(query) do
    with :ok <- ensure_capability(provider, config, "search_securities"),
         {:ok, candidates} <- provider.search_securities(config, String.trim(query)) do
      {:ok, Enum.map(candidates, &normalize_candidate/1)}
    end
  end

  @spec preview_security(map()) :: {:ok, map()} | {:error, term()}
  def preview_security(security_ref) when is_map(security_ref) do
    {provider, config} = default_provider()
    preview_security(provider, config, security_ref)
  end

  @spec preview_security(module(), map(), map()) :: {:ok, map()} | {:error, term()}
  def preview_security(provider, config, security_ref)
      when is_atom(provider) and is_map(config) and is_map(security_ref) do
    with :ok <- ensure_capability(provider, config, "preview_security"),
         {:ok, preview} <- provider.preview_security(config, security_ref) do
      {:ok, normalize_candidate(preview)}
    end
  end

  @spec historical_quotes(map(), map()) :: {:ok, [map()]} | {:error, term()}
  def historical_quotes(security_ref, opts \\ %{}) when is_map(security_ref) and is_map(opts) do
    {provider, config} = default_provider()
    historical_quotes(provider, config, security_ref, opts)
  end

  @spec historical_quotes(module(), map(), map(), map()) :: {:ok, [map()]} | {:error, term()}
  def historical_quotes(provider, config, security_ref, opts)
      when is_atom(provider) and is_map(config) and is_map(security_ref) and is_map(opts) do
    with :ok <- ensure_capability(provider, config, "read_historical_quotes"),
         {:ok, quotes} <- provider.historical_quotes(config, security_ref, opts) do
      {:ok, Enum.map(quotes, &normalize_quote/1)}
    end
  end

  @spec call(module(), String.t(), map(), map(), map()) ::
          {:ok, map() | [map()] | nil}
          | {:error,
             {:unsupported_capability, String.t()} | {:invalid_capability, term()} | term()}
  def call(provider, capability, config, security_ref \\ %{}, opts \\ %{})

  def call(provider, capability, config, security_ref, opts)
      when is_atom(provider) and is_binary(capability) and is_map(config) and is_map(security_ref) and
             is_map(opts) do
    case capability do
      "search_securities" ->
        search_securities(provider, config, fetch_first(security_ref, [:query, "query"]) || "")

      "preview_security" ->
        preview_security(provider, config, security_ref)

      "read_historical_quotes" ->
        historical_quotes(provider, config, security_ref, opts)

      cap when cap in @write_like_capabilities ->
        unsupported_capability(cap)

      cap ->
        unsupported_capability(cap)
    end
  end

  def call(_provider, capability, _config, _security_ref, _opts),
    do: {:error, {:invalid_capability, capability}}

  defp ensure_capability(provider, config, capability) do
    with {:ok, provider_capabilities} <- provider.capabilities(config),
         true <- capability in provider_capabilities do
      :ok
    else
      false -> unsupported_capability(capability)
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_candidate(%{} = candidate) do
    %{
      name: fetch_first(candidate, [:name, "name"]),
      symbol: fetch_first(candidate, [:symbol, "symbol"]),
      provider_symbol: fetch_first(candidate, [:provider_symbol, "provider_symbol"]),
      provider_source: fetch_first(candidate, [:provider_source, "provider_source"]),
      currency_code: fetch_first(candidate, [:currency_code, "currency_code"]),
      exchange_code: fetch_first(candidate, [:exchange_code, "exchange_code"]),
      market: fetch_first(candidate, [:market, "market"]),
      instrument_type: fetch_first(candidate, [:instrument_type, "instrument_type"]),
      latest_close: fetch_first(candidate, [:latest_close, "latest_close"]),
      latest_close_date: fetch_first(candidate, [:latest_close_date, "latest_close_date"]),
      metadata: fetch_first(candidate, [:metadata, "metadata"]) || %{}
    }
  end

  defp normalize_quote(%{} = quote) do
    %{
      date: Map.fetch!(quote, :date),
      open: Map.get(quote, :open),
      high: Map.get(quote, :high),
      low: Map.get(quote, :low),
      close: Map.fetch!(quote, :close),
      volume: Map.get(quote, :volume),
      currency_code: Map.get(quote, :currency_code),
      source: Map.get(quote, :source, "provider"),
      metadata: Map.get(quote, :metadata, %{})
    }
  end

  defp fetch_first(map, keys) do
    Enum.find_value(keys, fn key -> Map.get(map, key) end)
  end

  defp unsupported_capability(capability), do: {:error, {:unsupported_capability, capability}}
end
