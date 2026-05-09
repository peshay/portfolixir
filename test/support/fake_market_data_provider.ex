defmodule Portfolixir.FakeMarketDataProvider do
  @moduledoc false

  @behaviour Portfolixir.MarketData.Provider

  @candidates [
    %{
      name: "Apple Inc.",
      symbol: "AAPL",
      provider_symbol: "AAPL",
      currency_code: "USD",
      exchange_code: "NMS",
      market: "NasdaqGS",
      instrument_type: "EQUITY",
      provider_source: "yahoo",
      metadata: %{}
    },
    %{
      name: "Microsoft Corporation",
      symbol: "MSFT",
      provider_symbol: "MSFT",
      currency_code: "USD",
      exchange_code: "NMS",
      market: "NasdaqGS",
      instrument_type: "EQUITY",
      provider_source: "yahoo",
      metadata: %{}
    }
  ]

  @quotes [
    %{
      date: ~D[2024-01-02],
      close: "184.25",
      currency_code: "USD",
      source: "yahoo",
      metadata: %{fixture: true}
    },
    %{
      date: ~D[2024-01-03],
      close: "185.64",
      currency_code: "USD",
      source: "yahoo",
      metadata: %{fixture: true}
    }
  ]

  @impl true
  def capabilities(_config),
    do: {:ok, ["search_securities", "preview_security", "read_historical_quotes"]}

  @impl true
  def search_securities(_config, query) when is_binary(query) do
    normalized_query = String.downcase(String.trim(query))

    {:ok,
     Enum.filter(@candidates, fn candidate ->
       String.contains?(String.downcase(candidate.name), normalized_query) or
         String.contains?(String.downcase(candidate.provider_symbol), normalized_query)
     end)}
  end

  @impl true
  def preview_security(_config, security_ref) when is_map(security_ref) do
    {:ok,
     security_ref
     |> Map.put(:latest_close, "185.64")
     |> Map.put(:latest_close_date, ~D[2024-01-03])}
  end

  @impl true
  def historical_quotes(_config, _security_ref, _opts), do: {:ok, @quotes}
end
