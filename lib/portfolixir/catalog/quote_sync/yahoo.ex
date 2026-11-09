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

  Null closes (non-trading days) are dropped, and so is an implausible point
  (a close that is not positive, or a date past
  `Portfolixir.Catalog.MarketDataBounds.latest_date/0`), so one bad point never
  fails the batch (E25 S3, F26).

  The answer's `meta.currency` is compared with the security's
  `currency_code` before any row is returned (#1411): a ticker that resolves
  to another listing (a USD line, an ADR) would otherwise be stored as closes
  in the security's currency. A different currency answers
  `{:error, {:currency_mismatch, provider_currency}}` and no rows. It is
  compared as written, letter case included, so Yahoo's minor units (`GBp`
  pence, `ZAc` cents, `ILA` agorot) are another currency than `GBP`, `ZAR`
  and `ILS` and are refused the same way; a scale mapping would be its own
  decision. A stated value that is not three ASCII letters
  (`Security.provider_currency_shape?/1`) is no currency code: it answers
  `{:error, {:invalid_currency, value}}`, `value` its first 16 characters,
  and no rows (closing act, QA3). An answer that states no currency (no
  `meta`, no key, `null`, an empty string, or not a string) passes as before. An answer in the
  security's own currency carries it beside its rows,
  `{:ok, rows, %{currency: currency}}`, for the sync to keep (#1415).
  """

  @behaviour Portfolixir.Catalog.QuoteSync.Provider

  alias Portfolixir.Catalog.MarketDataBounds
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Net.Http
  alias Portfolixir.Net.PathSegment

  @endpoint "https://query1.finance.yahoo.com/v8/finance/chart"
  # The only hosts a request or a redirect hop may reach (F27).
  @allowed_hosts ["query1.finance.yahoo.com", "query2.finance.yahoo.com"]
  @interval "1d"

  @impl true
  def id, do: :yahoo

  @impl true
  def fetchable?(%Security{ticker_symbol: ticker} = security)
      when is_binary(ticker) and ticker != "",
      do: match?({:ok, _symbol}, build_symbol(security))

  def fetchable?(%Security{}), do: false

  @impl true
  def fetch(%Security{ticker_symbol: ticker}, _opts) when ticker in [nil, ""] do
    {:error, :missing_ticker}
  end

  def fetch(%Security{} = security, opts) do
    # One path segment (#763, F31): a ticker can neither change the endpoint,
    # nor the query, nor, as a relative segment, the path.
    with {:ok, symbol} <- build_symbol(security),
         {:ok, segment} <- PathSegment.encode(symbol) do
      case Http.get(req(opts),
             url: "#{@endpoint}/#{segment}",
             params: [
               period1: 0,
               period2: DateTime.utc_now() |> DateTime.to_unix(),
               interval: @interval
             ]
           ) do
        {:ok, %Req.Response{status: 200, body: body}} ->
          in_own_currency(security, body)

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

  # #1411 (Sprint 28 Q2): the rows only when the answer is in the security's
  # own currency, or states none.
  # #1415 (Q3): a stated currency travels with the rows, for the sync to keep
  # on the security.
  # Closing act, QA3: a stated value that is no currency code is refused
  # under its own reason, its first 16 characters kept for the log only.
  defp in_own_currency(%Security{currency_code: own}, body) do
    case stated_currency(body) do
      nil ->
        {:ok, decode(body)}

      ^own ->
        {:ok, decode(body), %{currency: own}}

      stated ->
        if Security.provider_currency_shape?(stated),
          do: {:error, {:currency_mismatch, stated}},
          else: {:error, {:invalid_currency, String.slice(stated, 0, 16)}}
    end
  end

  defp stated_currency(%{"chart" => %{"result" => [%{"meta" => %{"currency" => currency}} | _]}})
       when is_binary(currency) and currency != "",
       do: currency

  defp stated_currency(_body), do: nil

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
    with {:ok, dt} <- DateTime.from_unix(ts),
         date = DateTime.to_date(dt),
         true <- MarketDataBounds.plausible?(date, close, MarketDataBounds.close_column()) do
      [%{date: date, close: close |> to_string() |> Decimal.new()}]
    else
      _ -> []
    end
  end

  defp to_row(_), do: []

  defp req(opts) do
    base =
      Http.new(
        headers: [{"user-agent", "portfolixir/0.1 (+https://github.com/portfolixir)"}],
        receive_timeout: 10_000,
        allowed_hosts: @allowed_hosts,
        max_bytes: 8 * 1024 * 1024,
        deadline_ms: 30_000
      )

    case opts[:req] do
      nil -> base
      overrides when is_list(overrides) -> Req.merge(base, overrides)
    end
  end
end
