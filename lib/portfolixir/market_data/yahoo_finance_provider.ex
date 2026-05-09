defmodule Portfolixir.MarketData.YahooFinanceProvider do
  @moduledoc "Yahoo Finance market data provider for security lookup and historical closes."

  @behaviour Portfolixir.MarketData.Provider

  @source "yahoo"
  @search_url "https://query1.finance.yahoo.com/v1/finance/search"
  @chart_url "https://query1.finance.yahoo.com/v8/finance/chart/"
  @default_headers [{~c"accept", ~c"application/json"}, {~c"user-agent", ~c"Portfolixir/0.1"}]

  @impl true
  def capabilities(_config),
    do: {:ok, ["search_securities", "preview_security", "read_historical_quotes"]}

  @impl true
  def search_securities(_config, query) when is_binary(query) do
    query = String.trim(query)

    if query == "" do
      {:ok, []}
    else
      params = %{"q" => query, "quotesCount" => "8", "newsCount" => "0"}

      with {:ok, body} <- http_get(@search_url, params),
           {:ok, decoded} <- Jason.decode(body) do
        candidates =
          decoded
          |> Map.get("quotes", [])
          |> Enum.filter(&security_quote?/1)
          |> Enum.map(&candidate_from_search_quote/1)

        {:ok, candidates}
      end
    end
  end

  @impl true
  def preview_security(config, security_ref) when is_map(security_ref) do
    provider_symbol = provider_symbol!(security_ref)

    case chart(config, provider_symbol, %{range: "5d", interval: "1d"}) do
      {:ok, %{meta: meta, quotes: quotes}} ->
        latest_quote = List.last(quotes)
        candidate = candidate_from_security_ref(security_ref)

        {:ok,
         candidate
         |> Map.merge(%{
           currency_code: Map.get(meta, "currency") || candidate[:currency_code],
           exchange_code: Map.get(meta, "exchangeName") || candidate[:exchange_code],
           market: Map.get(meta, "fullExchangeName") || candidate[:market],
           latest_close: latest_quote && latest_quote.close,
           latest_close_date: latest_quote && latest_quote.date,
           metadata: Map.merge(candidate[:metadata] || %{}, %{provider_meta: compact_meta(meta)})
         })}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def historical_quotes(config, security_ref, opts) when is_map(security_ref) and is_map(opts) do
    provider_symbol = provider_symbol!(security_ref)
    range = Map.get(opts, :range, Map.get(opts, "range", "1y"))
    interval = Map.get(opts, :interval, Map.get(opts, "interval", "1d"))

    with {:ok, %{meta: meta, quotes: quotes}} <-
           chart(config, provider_symbol, %{range: range, interval: interval}) do
      currency_code = Map.get(meta, "currency") || security_ref[:currency_code]

      {:ok,
       Enum.map(quotes, fn quote ->
         quote
         |> Map.take([:date, :open, :high, :low, :close, :volume])
         |> Map.merge(%{
           currency_code: currency_code,
           source: @source,
           metadata: %{provider_symbol: provider_symbol}
         })
       end)}
    end
  end

  defp chart(_config, provider_symbol, opts) do
    url = @chart_url <> URI.encode(provider_symbol)

    params = %{
      "range" => to_string(Map.fetch!(opts, :range)),
      "interval" => to_string(Map.fetch!(opts, :interval))
    }

    with {:ok, body} <- http_get(url, params),
         {:ok, decoded} <- Jason.decode(body),
         {:ok, result} <- chart_result(decoded) do
      {:ok, result}
    end
  end

  defp chart_result(%{"chart" => %{"result" => [result | _]}}) do
    meta = Map.get(result, "meta", %{})
    timestamps = Map.get(result, "timestamp", [])

    indicators =
      result |> Map.get("indicators", %{}) |> Map.get("quote", []) |> List.first() || %{}

    adjclose =
      result
      |> Map.get("indicators", %{})
      |> Map.get("adjclose", [])
      |> List.first()
      |> case do
        %{"adjclose" => closes} -> closes
        _ -> Map.get(indicators, "close", [])
      end

    quotes =
      timestamps
      |> Enum.with_index()
      |> Enum.flat_map(fn {unix, index} ->
        close = Enum.at(adjclose, index)

        if is_nil(close) do
          []
        else
          [
            %{
              date: DateTime.from_unix!(unix) |> DateTime.to_date(),
              open: Enum.at(Map.get(indicators, "open", []), index),
              high: Enum.at(Map.get(indicators, "high", []), index),
              low: Enum.at(Map.get(indicators, "low", []), index),
              close: close,
              volume: Enum.at(Map.get(indicators, "volume", []), index)
            }
          ]
        end
      end)

    {:ok, %{meta: meta, quotes: quotes}}
  end

  defp chart_result(%{"chart" => %{"error" => error}}) when not is_nil(error), do: {:error, error}
  defp chart_result(_), do: {:error, :invalid_yahoo_chart_response}

  defp http_get(url, params) do
    query = URI.encode_query(params)
    request_url = String.to_charlist(url <> "?" <> query)

    case :httpc.request(:get, {request_url, @default_headers}, [{:timeout, 10_000}],
           body_format: :binary
         ) do
      {:ok, {{_, status, _}, _headers, body}} when status in 200..299 -> {:ok, body}
      {:ok, {{_, status, _}, _headers, _body}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp security_quote?(%{"symbol" => symbol}) when is_binary(symbol), do: true
  defp security_quote?(_), do: false

  defp candidate_from_search_quote(quote) do
    provider_symbol = Map.fetch!(quote, "symbol")

    %{
      name: Map.get(quote, "longname") || Map.get(quote, "shortname") || provider_symbol,
      symbol: provider_symbol,
      provider_symbol: provider_symbol,
      currency_code: Map.get(quote, "currency"),
      exchange_code: Map.get(quote, "exchange"),
      market: Map.get(quote, "exchDisp"),
      instrument_type: Map.get(quote, "quoteType") || Map.get(quote, "typeDisp"),
      provider_source: @source,
      metadata: %{
        yahoo_score: Map.get(quote, "score"),
        yahoo_quote_type: Map.get(quote, "quoteType")
      }
    }
  end

  defp candidate_from_security_ref(security_ref) do
    provider_symbol = provider_symbol!(security_ref)

    %{
      name: string_key(security_ref, :name) || provider_symbol,
      symbol: string_key(security_ref, :symbol) || provider_symbol,
      provider_symbol: provider_symbol,
      currency_code: string_key(security_ref, :currency_code),
      exchange_code: string_key(security_ref, :exchange_code),
      market: string_key(security_ref, :market),
      instrument_type: string_key(security_ref, :instrument_type),
      provider_source: string_key(security_ref, :provider_source) || @source,
      metadata: Map.get(security_ref, :metadata) || Map.get(security_ref, "metadata") || %{}
    }
  end

  defp compact_meta(meta) do
    meta
    |> Map.take([
      "currency",
      "exchangeName",
      "fullExchangeName",
      "instrumentType",
      "regularMarketPrice"
    ])
  end

  defp provider_symbol!(security_ref) do
    string_key(security_ref, :provider_symbol) || string_key(security_ref, :symbol) ||
      raise ArgumentError, "provider symbol is required"
  end

  defp string_key(map, key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end
