defmodule Portfolixir.Catalog.SecuritySearch.CoinGecko do
  @moduledoc """
  Adapter for the public CoinGecko search API
  (https://api.coingecko.com/api/v3/search).

  Quote currency is *not* fixed by CoinGecko; the UI presents `"EUR"` as a
  user-editable default in the confirm step.

  An optional `COINGECKO_API_KEY` env var is honored — if set, the demo-tier
  header is attached. The adapter works without a key.
  """

  @behaviour Portfolixir.Catalog.SecuritySearch.Provider

  alias Portfolixir.Catalog.SecuritySearch.SearchResult
  alias Portfolixir.Net.Http

  @endpoint "https://api.coingecko.com/api/v3/search"
  @coins_endpoint "https://api.coingecko.com/api/v3/coins"
  @feed_id "COINGECKO"

  @impl true
  def id, do: :coingecko

  @impl true
  def search(query, opts \\ []) when is_binary(query) do
    req = req(opts)

    case Http.get(req, url: @endpoint, params: [query: query]) do
      {:ok, %Req.Response{status: 200, body: %{"coins" => coins}}} when is_list(coins) ->
        {:ok, Enum.map(coins, &to_result/1) |> Enum.reject(&is_nil/1)}

      {:ok, %Req.Response{status: 200}} ->
        {:ok, []}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Fetches the canonical large image URL for a given CoinGecko coin id.

  Returns `{:ok, url}`, `:not_found` (200 response with no image), or
  `{:error, reason}` on HTTP/transport errors.
  """
  @spec fetch_image_url(String.t(), keyword()) ::
          {:ok, String.t()} | :not_found | {:error, term()}
  def fetch_image_url(coin_id, opts \\ []) when is_binary(coin_id) do
    req = req(opts)
    url = @coins_endpoint <> "/" <> URI.encode(coin_id, &URI.char_unreserved?/1)

    case Http.get(req,
           url: url,
           params: [
             localization: "false",
             tickers: "false",
             market_data: "false",
             community_data: "false",
             developer_data: "false"
           ]
         ) do
      {:ok, %Req.Response{status: 200, body: %{"image" => %{"large" => large}}}}
      when is_binary(large) ->
        {:ok, large}

      {:ok, %Req.Response{status: 200}} ->
        :not_found

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp req(opts) do
    headers =
      [{"user-agent", "portfolixir/0.1"}] ++ api_key_header()

    base =
      Http.new(
        headers: headers,
        receive_timeout: 5_000,
        max_bytes: 2 * 1024 * 1024,
        deadline_ms: 15_000
      )

    case opts[:req] do
      nil -> base
      overrides when is_list(overrides) -> Req.merge(base, overrides)
    end
  end

  defp api_key_header do
    case System.get_env("COINGECKO_API_KEY") do
      nil -> []
      "" -> []
      key -> [{"x-cg-demo-api-key", key}]
    end
  end

  defp to_result(%{"id" => id, "name" => name} = coin)
       when is_binary(id) and is_binary(name) do
    %SearchResult{
      provider: :coingecko,
      online_id: id,
      name: name,
      ticker_symbol: coin |> Map.get("symbol") |> upcase_or_nil(),
      asset_class: "crypto",
      feed: @feed_id,
      markets: [],
      raw: %{
        "type" => "Cryptocurrency",
        "market_cap_rank" => Map.get(coin, "market_cap_rank")
      }
    }
  end

  defp to_result(_), do: nil

  defp upcase_or_nil(nil), do: nil
  defp upcase_or_nil(""), do: nil
  defp upcase_or_nil(value) when is_binary(value), do: String.upcase(String.trim(value))
end
