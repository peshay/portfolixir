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
      ticker_symbol: "ARBL",
      currency_code: "USD"
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
    security = %Security{id: 1, ticker_symbol: "ARBL"}

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

    security = %Security{id: 1, ticker_symbol: "ARBL"}
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

    security = %Security{id: 1, ticker_symbol: "ARBL", provider: "portfolio_performance"}
    assert {:ok, []} = Yahoo.fetch(security, req: [plug: plug])

    assert_receive {^ref, params, path}
    assert path =~ "ARBL"
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

  # User story (#1411, Sprint 28 Q2):
  # As a local portfolio maintainer,
  # I want the Yahoo adapter to refuse a chart answer whose stated currency is
  # not the security's own,
  # so that a ticker that resolves to another listing never stores USD
  # closes as EUR closes, and every figure built on them stays right.
  #
  # Acceptance criteria:
  # - `meta.currency` equal to `currency_code` answers the rows as before.
  # - A different `meta.currency` answers `{:error, {:currency_mismatch,
  #   provider_currency}}` and no rows.
  # - Yahoo's minor-unit codes (`GBp` pence, `ZAc` cents, `ILA` agorot) are
  #   another currency than `GBP`, `ZAR` and `ILS`: refused the same way,
  #   compared as written, letter case included.
  # - A missing `meta.currency` (no `meta`, no key, `null`, an empty string)
  #   passes as today.
  test "a USD answer for a EUR security is refused as a currency mismatch" do
    security = %Security{id: 1, ticker_symbol: "ARBL", currency_code: "EUR"}

    assert {:error, {:currency_mismatch, "USD"}} =
             Yahoo.fetch(security, req: req_stub(chart("USD")))
  end

  test "a minor-unit answer is refused against its major currency" do
    for {stated, own} <- [{"GBp", "GBP"}, {"ZAc", "ZAR"}, {"ILA", "ILS"}] do
      security = %Security{id: 1, ticker_symbol: "ARBL", currency_code: own}

      assert Yahoo.fetch(security, req: req_stub(chart(stated))) ==
               {:error, {:currency_mismatch, stated}},
             "#{stated} against #{own}"
    end
  end

  test "an answer in the security's own currency returns its rows" do
    security = %Security{id: 1, ticker_symbol: "ARBL", currency_code: "EUR"}

    assert {:ok, [%{date: ~D[2024-05-06], close: close}]} =
             Yahoo.fetch(security, req: req_stub(chart("EUR")))

    assert Decimal.equal?(close, Decimal.new("100.10"))
  end

  test "an answer that states no currency passes as before" do
    security = %Security{id: 1, ticker_symbol: "ARBL", currency_code: "EUR"}

    for meta <- [:no_meta, %{}, %{"currency" => nil}, %{"currency" => ""}] do
      assert match?(
               {:ok, [%{date: ~D[2024-05-06]}]},
               Yahoo.fetch(security, req: req_stub(chart_with_meta(meta)))
             ),
             inspect(meta)
    end
  end

  defp chart(currency), do: chart_with_meta(%{"currency" => currency})

  defp chart_with_meta(meta) do
    result = %{
      "timestamp" => [1_715_001_600],
      "indicators" => %{"quote" => [%{"close" => [100.10]}]}
    }

    result = if meta == :no_meta, do: result, else: Map.put(result, "meta", meta)
    %{"chart" => %{"result" => [result]}}
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
