defmodule Portfolixir.Quotes do
  @moduledoc "Read-only quote provider wrapper with capability checks and shape normalization."

  @read_capabilities ["read_latest_quote", "read_historical_quotes"]
  @write_like_capabilities ["place_order", "create_payment", "withdraw", "transfer", "trade"]

  @spec capabilities() :: [String.t()]
  def capabilities, do: @read_capabilities

  @spec historical_quotes(module(), map(), map()) ::
          {:ok, [map()]} | {:error, {:unsupported_capability, String.t()} | term()}
  def historical_quotes(provider, config, security_ref)
      when is_atom(provider) and is_map(config) and is_map(security_ref) do
    with :ok <- ensure_capability(provider, config, "read_historical_quotes"),
         {:ok, quotes} <- provider.historical_quotes(config, security_ref) do
      {:ok, Enum.map(quotes, &normalize_quote/1)}
    end
  end

  @spec latest_quote(module(), map(), map()) ::
          {:ok, map() | nil} | {:error, {:unsupported_capability, String.t()} | term()}
  def latest_quote(provider, config, security_ref)
      when is_atom(provider) and is_map(config) and is_map(security_ref) do
    with :ok <- ensure_capability(provider, config, "read_latest_quote"),
         {:ok, quote} <- provider.latest_quote(config, security_ref) do
      {:ok, if(quote, do: normalize_quote(quote), else: nil)}
    end
  end

  @spec call(module(), String.t(), map(), map()) ::
          {:ok, map() | [map()] | nil}
          | {:error,
             {:unsupported_capability, String.t()} | {:invalid_capability, term()} | term()}
  def call(provider, capability, config, security_ref)
      when is_atom(provider) and is_binary(capability) and is_map(config) and is_map(security_ref) do
    case capability do
      "read_historical_quotes" -> historical_quotes(provider, config, security_ref)
      "read_latest_quote" -> latest_quote(provider, config, security_ref)
      cap when cap in @write_like_capabilities -> unsupported_capability(cap)
      cap -> unsupported_capability(cap)
    end
  end

  def call(_provider, capability, _config, _security_ref),
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

  defp unsupported_capability(capability), do: {:error, {:unsupported_capability, capability}}
end
