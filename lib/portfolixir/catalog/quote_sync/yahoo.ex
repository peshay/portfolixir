defmodule Portfolixir.Catalog.QuoteSync.Yahoo do
  @moduledoc """
  Fetches historical daily quotes from Yahoo Finance for both equities and
  crypto, using the chart endpoint:

      GET query1.finance.yahoo.com/v8/finance/chart/<symbol>
          ?period1=0&period2=<now>&interval=1d

  We use `period1`/`period2` (not `range=max`) on purpose. Yahoo silently
  downsamples `range=max` to monthly for long-history assets — AAPL
  returns 167 monthly points with `range=max` vs 11k+ daily points with
  `period1=0`. CoinGecko's free tier caps history at 365 days
  (`error_code 10012`); routing crypto through Yahoo gives us full daily
  history (BTC-USD goes back to 2014) without a paid plan.

  Symbol building by `Security.provider`:
    * `"portfolio_performance"` — bare `ticker_symbol` (e.g. `AAPL`, `APC.DE`).
    * `"coingecko"` — `<ticker_symbol>-<currency_code>` (e.g. `BTC-USD`).

  Null closes (non-trading days) are dropped.
  """

  @behaviour Portfolixir.Catalog.QuoteSync.Provider

  alias Portfolixir.Catalog.Security
  alias Portfolixir.Net.Http

  @endpoint "https://query1.finance.yahoo.com/v8/finance/chart"
  @interval "1d"

  @impl true
  def id, do: :yahoo

  @impl true
  def fetch(%Security{ticker_symbol: ticker}, _opts) when ticker in [nil, ""] do
    {:error, :missing_ticker}
  end

  def fetch(%Security{} = security, opts) do
    case build_symbol(security) do
      {:error, _} = err ->
        err

      {:ok, symbol} ->
        req = req(opts)
        # One unreserved path segment (#763): a ticker can neither change
        # the endpoint nor the query.
        url = "#{@endpoint}/#{URI.encode(symbol, &URI.char_unreserved?/1)}"

        case Http.get(req,
               url: url,
               params: [
                 period1: 0,
                 period2: DateTime.utc_now() |> DateTime.to_unix(),
                 interval: @interval
               ]
             ) do
          {:ok, %Req.Response{status: 200, body: body}} ->
            {:ok, decode(body)}

          {:ok, %Req.Response{status: status}} ->
            {:error, {:http_status, status}}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp build_symbol(%Security{
         provider: "coingecko",
         ticker_symbol: ticker,
         currency_code: currency
       })
       when is_binary(currency) and currency != "" do
    {:ok, "#{String.upcase(ticker)}-#{String.upcase(currency)}"}
  end

  defp build_symbol(%Security{provider: "coingecko"}), do: {:error, :missing_currency}

  defp build_symbol(%Security{ticker_symbol: ticker}), do: {:ok, ticker}

  defp decode(%{"chart" => %{"result" => [result | _]}}) when is_map(result) do
    timestamps = result["timestamp"] || []
    closes = get_in(result, ["indicators", "quote", Access.at(0), "close"]) || []

    timestamps
    |> Enum.zip(closes)
    |> Enum.flat_map(&to_row/1)
    |> Enum.uniq_by(& &1.date)
    |> Enum.sort_by(& &1.date, Date)
  end

  defp decode(_), do: []

  defp to_row({_ts, nil}), do: []

  defp to_row({ts, close}) when is_integer(ts) and is_number(close) do
    case DateTime.from_unix(ts) do
      {:ok, dt} -> [%{date: DateTime.to_date(dt), close: close |> to_string() |> Decimal.new()}]
      _ -> []
    end
  end

  defp to_row(_), do: []

  defp req(opts) do
    base =
      Http.new(
        headers: [{"user-agent", "portfolixir/0.1 (+https://github.com/portfolixir)"}],
        receive_timeout: 10_000,
        max_bytes: 8 * 1024 * 1024,
        deadline_ms: 30_000
      )

    case opts[:req] do
      nil -> base
      overrides when is_list(overrides) -> Req.merge(base, overrides)
    end
  end
end
