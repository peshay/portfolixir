defmodule Portfolixir.Catalog.SecuritySearch.PortfolioPerformanceTest do
  use ExUnit.Case, async: true

  alias Portfolixir.Catalog.SecuritySearch.PortfolioPerformance
  alias Portfolixir.Catalog.SecuritySearch.SearchResult

  describe "search/2 — defensive mapping" do
    test "maps a typical Apple-style payload from the live API shape" do
      body = [
        %{
          "description" => "APPLE INC",
          "isin" => "US0378331005",
          "wkn" => "865985",
          "type" => "Common Stock",
          "provider" => "PP",
          "markets" => [
            %{"symbol" => "AAPL", "currency" => "USD", "exchange" => "XNAS"},
            %{"symbol" => "APC.DE", "currency" => "EUR", "exchange" => "XETR"}
          ]
        }
      ]

      {:ok, [result]} =
        PortfolioPerformance.search("apple", req: req_stub(body))

      assert %SearchResult{provider: :portfolio_performance} = result
      # online_id is the ISIN (PP doesn't return a stable per-result id)
      assert result.online_id == "US0378331005"
      assert result.name == "Apple Inc"
      assert result.isin == "US0378331005"
      assert result.wkn == "865985"
      assert result.ticker_symbol == "AAPL"
      assert result.currency_code == "USD"
      assert result.asset_class == "equity"
      assert length(result.markets) == 2
    end

    test "maps ETP type to etf" do
      body = [
        %{
          "description" => "LEVERAGE SHARES 3X APPLE",
          "isin" => "IE00BK5BZS07",
          "type" => "ETP",
          "markets" => [%{"symbol" => "3APE.DE", "currency" => "EUR", "exchange" => "XETR"}]
        }
      ]

      {:ok, [result]} = PortfolioPerformance.search("3x", req: req_stub(body))
      assert result.asset_class == "etf"
    end

    test "unknown type falls back to 'other'" do
      body = [%{"description" => "Mystery", "type" => "WizardThingy", "markets" => []}]
      {:ok, [result]} = PortfolioPerformance.search("mys", req: req_stub(body))
      assert result.asset_class == "other"
    end

    test "tolerates missing isin / wkn / symbol" do
      body = [
        %{
          "description" => "MYSTERY INC",
          "markets" => [%{"symbol" => "MYS"}]
        }
      ]

      {:ok, [result]} =
        PortfolioPerformance.search("mys", req: req_stub(body))

      assert result.isin == nil
      assert result.wkn == nil
      assert result.ticker_symbol == "MYS"
      assert result.currency_code == nil
      # online_id falls back to nil when ISIN is missing
      assert result.online_id == nil
    end

    test "treats missing/empty markets as []" do
      body = [
        %{"description" => "NOMARK", "markets" => []},
        %{"description" => "NO MARKETS KEY"}
      ]

      {:ok, results} =
        PortfolioPerformance.search("none", req: req_stub(body))

      assert length(results) == 2
      assert Enum.all?(results, &(&1.markets == []))
      assert Enum.all?(results, &(&1.currency_code == nil))
    end

    test "dedupes duplicate market entries within one hit" do
      body = [
        %{
          "description" => "DUP",
          "markets" => [
            %{"symbol" => "X", "currency" => "USD", "exchange" => "XNAS"},
            %{"symbol" => "X", "currency" => "USD", "exchange" => "XNAS"}
          ]
        }
      ]

      {:ok, [result]} =
        PortfolioPerformance.search("dup", req: req_stub(body))

      assert length(result.markets) == 1
    end

    test "non-list response yields empty list" do
      {:ok, []} = PortfolioPerformance.search("x", req: req_stub(%{"error" => "bad"}))
    end

    test "non-200 status surfaces an error tuple" do
      stub = [plug: fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end]
      assert {:error, {:http_status, 500}} = PortfolioPerformance.search("x", req: stub)
    end
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
