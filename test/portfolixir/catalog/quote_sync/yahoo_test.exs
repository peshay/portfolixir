defmodule Portfolixir.Catalog.QuoteSync.YahooTest do
  use ExUnit.Case, async: true

  alias Portfolixir.Catalog.QuoteSync.Yahoo
  alias Portfolixir.Catalog.Security

  # User story:
  # As a local portfolio maintainer,
  # I want stock/ETF quotes pulled from Yahoo Finance (which is what
  # Portfolio Performance uses under the hood for most equity feeds),
  # so that the chart shows real historical closes for tickers I added
  # via the PP search.
  #
  # Acceptance criteria:
  # - The adapter parses Yahoo's `chart` payload — pairing UNIX
  #   `timestamp` seconds with the matching `indicators.quote[0].close`.
  # - Null closes (Yahoo emits these for non-trading days) are dropped.
  # - Securities without a `ticker_symbol` short-circuit with
  #   `{:error, :missing_ticker}` so we don't hit the wrong URL.
  # - HTTP errors surface as `{:error, {:http_status, status}}`.

  test "maps Yahoo's chart payload into ascending {date, close} rows" do
    body = %{
      "chart" => %{
        "result" => [
          %{
            "meta" => %{"currency" => "USD"},
            "timestamp" => [
              1_715_001_600,
              1_715_088_000,
              1_715_174_400
            ],
            "indicators" => %{
              "quote" => [
                %{"close" => [100.10, nil, 105.25]}
              ]
            }
          }
        ]
      }
    }

    security = %Security{
      id: 1,
      provider: "portfolio_performance",
      ticker_symbol: "AAPL"
    }

    {:ok, rows} = Yahoo.fetch(security, req: req_stub(body))

    assert [
             %{date: ~D[2024-05-06], close: c1},
             %{date: ~D[2024-05-08], close: c2}
           ] = rows

    assert Decimal.equal?(c1, Decimal.new("100.10"))
    assert Decimal.equal?(c2, Decimal.new("105.25"))
  end

  test "returns empty when chart.result is missing or empty" do
    security = %Security{id: 1, ticker_symbol: "AAPL"}

    assert {:ok, []} =
             Yahoo.fetch(security, req: req_stub(%{"chart" => %{"result" => []}}))

    assert {:ok, []} =
             Yahoo.fetch(security, req: req_stub(%{"chart" => %{}}))
  end

  test "missing ticker short-circuits" do
    security = %Security{id: 1, ticker_symbol: nil}
    assert {:error, :missing_ticker} = Yahoo.fetch(security, req: req_stub(%{}))
  end

  test "non-200 responses surface as http_status errors" do
    plug = fn conn -> Plug.Conn.send_resp(conn, 429, "") end

    security = %Security{id: 1, ticker_symbol: "AAPL"}
    assert {:error, {:http_status, 429}} = Yahoo.fetch(security, req: [plug: plug])
  end

  test "queries Yahoo with period1=0..now and interval=1d for true MAX history" do
    parent = self()
    ref = make_ref()

    plug = fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      send(parent, {ref, conn.query_params, conn.request_path})

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{"chart" => %{"result" => []}}))
    end

    security = %Security{id: 1, ticker_symbol: "AAPL", provider: "portfolio_performance"}
    assert {:ok, []} = Yahoo.fetch(security, req: [plug: plug])

    assert_receive {^ref, params, path}
    assert path =~ "AAPL"
    assert params["period1"] == "0"
    assert params["interval"] == "1d"
    {now_ish, ""} = Integer.parse(params["period2"])
    assert now_ish > 1_700_000_000
  end

  test "builds <TICKER>-<CURRENCY> symbols for CoinGecko-provider crypto" do
    parent = self()
    ref = make_ref()

    plug = fn conn ->
      send(parent, {ref, conn.request_path})

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{"chart" => %{"result" => []}}))
    end

    security = %Security{
      id: 1,
      provider: "coingecko",
      ticker_symbol: "btc",
      currency_code: "EUR"
    }

    assert {:ok, []} = Yahoo.fetch(security, req: [plug: plug])
    assert_receive {^ref, "/" <> path}
    assert String.ends_with?(path, "/BTC-EUR")
  end

  test "crypto without a currency short-circuits" do
    security = %Security{
      id: 1,
      provider: "coingecko",
      ticker_symbol: "BTC",
      currency_code: nil
    }

    assert {:error, :missing_currency} = Yahoo.fetch(security, req: req_stub(%{}))
  end

  defp req_stub(body) do
    [
      plug: fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(body))
      end
    ]
  end
end
