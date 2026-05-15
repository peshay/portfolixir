defmodule Portfolixir.Catalog.SecuritySearch.CoinGeckoTest do
  use ExUnit.Case, async: false

  alias Portfolixir.Catalog.SecuritySearch.CoinGecko
  alias Portfolixir.Catalog.SecuritySearch.SearchResult

  test "maps a bitcoin payload" do
    body = %{
      "coins" => [
        %{
          "id" => "bitcoin",
          "name" => "Bitcoin",
          "symbol" => "btc",
          "market_cap_rank" => 1
        }
      ]
    }

    {:ok, [result]} = CoinGecko.search("bitcoin", req: req_stub(body, []))

    assert %SearchResult{provider: :coingecko, online_id: "bitcoin"} = result
    assert result.name == "Bitcoin"
    assert result.ticker_symbol == "BTC"
    assert result.asset_class == "crypto"
    assert result.currency_code == nil
    assert result.feed == "COINGECKO"
    assert result.raw["market_cap_rank"] == 1
  end

  test "returns [] when coins key is missing or empty" do
    {:ok, []} = CoinGecko.search("none", req: req_stub(%{"coins" => []}, []))
    {:ok, []} = CoinGecko.search("none", req: req_stub(%{}, []))
  end

  test "passes COINGECKO_API_KEY as the demo header when set" do
    System.put_env("COINGECKO_API_KEY", "test-key")

    try do
      ref = make_ref()
      pid = self()

      stub = [
        plug: fn conn ->
          send(pid, {ref, :headers, conn.req_headers})

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, Jason.encode!(%{"coins" => []}))
        end
      ]

      {:ok, []} = CoinGecko.search("btc", req: stub)

      assert_receive {^ref, :headers, headers}

      assert Enum.any?(headers, fn {k, v} ->
               String.downcase(k) == "x-cg-demo-api-key" and v == "test-key"
             end)
    after
      System.delete_env("COINGECKO_API_KEY")
    end
  end

  defp req_stub(body, _opts) do
    [
      plug: fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(body))
      end
    ]
  end
end
