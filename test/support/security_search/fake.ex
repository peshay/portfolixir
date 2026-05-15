defmodule Portfolixir.Catalog.SecuritySearch.Fake do
  @moduledoc """
  Test-only adapter for SecuritySearch. Used in `config :test` so the test
  suite never makes real HTTP calls.

  Default behaviour returns canned results for a few well-known queries. Tests
  can override the response with `put_response/2` (registered via the process
  dictionary so each async test is isolated).

      Fake.put_response("foo", [%SearchResult{...}])
      Fake.search("foo", [])
  """

  @behaviour Portfolixir.Catalog.SecuritySearch.Provider

  alias Portfolixir.Catalog.SecuritySearch.{Market, SearchResult}

  @impl true
  def id, do: :fake

  @impl true
  def search(query, _opts) when is_binary(query) do
    normalized = query |> String.trim() |> String.downcase()

    cond do
      override = get_override(normalized) ->
        {:ok, override}

      results = canned(normalized) ->
        {:ok, results}

      true ->
        {:ok, []}
    end
  end

  @doc "Test helper. Registers a canned response for `query` in this process."
  def put_response(query, results) when is_binary(query) and is_list(results) do
    Process.put({__MODULE__, String.downcase(String.trim(query))}, results)
    :ok
  end

  @doc "Test helper. Removes a per-process override."
  def clear_responses do
    Process.get_keys()
    |> Enum.filter(&match?({__MODULE__, _}, &1))
    |> Enum.each(&Process.delete/1)
  end

  defp get_override(normalized), do: Process.get({__MODULE__, normalized})

  defp canned("apple") do
    [
      %SearchResult{
        provider: :portfolio_performance,
        online_id: "us0378331005",
        name: "Apple Inc.",
        isin: "US0378331005",
        wkn: "865985",
        ticker_symbol: "AAPL",
        asset_class: "equity",
        currency_code: "USD",
        feed: "PORTFOLIO_PERFORMANCE",
        markets: [
          %Market{
            symbol: "AAPL",
            currency_code: "USD",
            exchange_code: "XNAS",
            exchange_name: "NASDAQ",
            url: "https://api.portfolio-performance.info/v1/quotes/us0378331005/xnas"
          },
          %Market{
            symbol: "APC",
            currency_code: "EUR",
            exchange_code: "XETR",
            exchange_name: "Xetra",
            url: "https://api.portfolio-performance.info/v1/quotes/us0378331005/xetr"
          }
        ],
        raw: %{"type" => "share"}
      }
    ]
  end

  defp canned("bitcoin") do
    [
      %SearchResult{
        provider: :coingecko,
        online_id: "bitcoin",
        name: "Bitcoin",
        ticker_symbol: "BTC",
        asset_class: "crypto",
        currency_code: nil,
        feed: "COINGECKO",
        markets: [],
        raw: %{"type" => "Cryptocurrency", "market_cap_rank" => 1}
      }
    ]
  end

  defp canned(_), do: nil
end
