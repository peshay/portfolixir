defmodule Portfolixir.Catalog.SecuritySearch.Fake do
  @moduledoc """
  Test-only adapter for SecuritySearch. Used in `config :test` so the test
  suite never makes real HTTP calls.

  Default behaviour returns canned results for a few fixed queries. Tests
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

  defp canned("arbolia"),
    do: [share_listing("Arbolia Inc.", "USEXMPL10014", "ARBOL1", "ARBL", "AR8")]

  # Two more listings of Arbolia's shape, each searched by one async test
  # module that also stores the security its listing matches (#1047).
  # Arbolia's ISIN is the one the Portfolio Performance sample carries, and
  # an async module imports the sample: a second async module storing a
  # security with that ISIN and online id (securities_isin_unique_index,
  # securities_provider_online_id_unique_index) made one test's insert wait
  # on the other's uncommitted row until that test ended. These two ISINs
  # are written by no other module.
  defp canned("quillmoor"),
    do: [share_listing("Quillmoor Systems Inc.", "USEXMPL40060", "QLMOR1", "QLMR", "QM8")]

  defp canned("brackenford"),
    do: [share_listing("Brackenford Corp.", "USEXMPL40078", "BRKFD1", "BRKF", "BK8")]

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

  # A share listed on NASDAQ in USD and on Xetra in EUR, the Xetra listing
  # second; its online id is its ISIN in lower case.
  defp share_listing(name, isin, wkn, nasdaq_symbol, xetra_symbol) do
    online_id = String.downcase(isin)

    %SearchResult{
      provider: :portfolio_performance,
      online_id: online_id,
      name: name,
      isin: isin,
      wkn: wkn,
      ticker_symbol: nasdaq_symbol,
      asset_class: "equity",
      currency_code: "USD",
      feed: "PORTFOLIO_PERFORMANCE",
      markets: [
        %Market{
          symbol: nasdaq_symbol,
          currency_code: "USD",
          exchange_code: "XNAS",
          exchange_name: "NASDAQ",
          url: "https://api.portfolio-performance.info/v1/quotes/#{online_id}/xnas"
        },
        %Market{
          symbol: xetra_symbol,
          currency_code: "EUR",
          exchange_code: "XETR",
          exchange_name: "Xetra",
          url: "https://api.portfolio-performance.info/v1/quotes/#{online_id}/xetr"
        }
      ],
      raw: %{"type" => "share"}
    }
  end
end
