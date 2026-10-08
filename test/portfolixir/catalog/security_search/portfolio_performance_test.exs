defmodule Portfolixir.Catalog.SecuritySearch.PortfolioPerformanceTest do
  use ExUnit.Case, async: true

  alias Portfolixir.Catalog.SecuritySearch.PortfolioPerformance
  alias Portfolixir.Catalog.SecuritySearch.SearchResult

  describe "search/2 — defensive mapping" do
    test "maps a typical Arbolia-style payload from the live API shape" do
      body = [
        %{
          "description" => "ARBOLIA INC",
          "isin" => "USEXMPL10014",
          "wkn" => "ARBOL1",
          "type" => "Common Stock",
          "provider" => "PP",
          "markets" => [
            %{"symbol" => "ARBL", "currency" => "USD", "exchange" => "XNAS"},
            %{"symbol" => "AR8.DE", "currency" => "EUR", "exchange" => "XETR"}
          ]
        }
      ]

      {:ok, [result]} =
        PortfolioPerformance.search("arbolia", req: req_stub(body))

      assert %SearchResult{provider: :portfolio_performance} = result
      # online_id is the ISIN (PP doesn't return a stable per-result id)
      assert result.online_id == "USEXMPL10014"
      assert result.name == "Arbolia Inc"
      assert result.isin == "USEXMPL10014"
      assert result.wkn == "ARBOL1"
      assert result.ticker_symbol == "ARBL"
      assert result.currency_code == "USD"
      assert result.asset_class == "equity"
      assert length(result.markets) == 2
    end

    test "maps ETP type to etf" do
      body = [
        %{
          "description" => "LEVERAGE SHARES 3X ARBOLIA",
          "isin" => "IEEXMPL20059",
          "type" => "ETP",
          "markets" => [%{"symbol" => "3ARB.DE", "currency" => "EUR", "exchange" => "XETR"}]
        }
      ]

      {:ok, [result]} = PortfolioPerformance.search("3x", req: req_stub(body))
      assert result.asset_class == "etf"
    end

    # User story:
    # As a local portfolio maintainer importing state bonds from Portfolio
    # Performance search,
    # I want government bond hits to carry their own asset class,
    # so that the security list can render the ISIN country flag immediately.
    #
    # Acceptance criteria:
    # - Explicit government/sovereign bond result types map to
    #   `government_bond`.
    # - Generic bond types with a clear government-bond description also map
    #   to `government_bond`.
    test "maps government bond results to government_bond" do
      body = [
        %{
          "description" => "REPUBLIC OF EXAMPLIA 0% 2034",
          "isin" => "DEEXMPL20340",
          "type" => "Bond",
          "markets" => [%{"symbol" => "EXMP.DE", "currency" => "EUR", "exchange" => "XETR"}]
        },
        %{
          "description" => "EXAMPLIA TREASURY NOTE 2032",
          "isin" => "USEXMPL23215",
          "type" => "Government Bond",
          "markets" => [%{"symbol" => "EXMPL2321", "currency" => "USD", "exchange" => "XNAS"}]
        }
      ]

      {:ok, results} = PortfolioPerformance.search("treasury", req: req_stub(body))
      assert Enum.map(results, & &1.asset_class) == ["government_bond", "government_bond"]
    end

    test "unknown type falls back to 'other'" do
      body = [%{"description" => "Mystery", "type" => "WizardThingy", "markets" => []}]
      {:ok, [result]} = PortfolioPerformance.search("mys", req: req_stub(body))
      assert result.asset_class == "other"
    end

    # User story (#314, the refactor under Credo's complexity ceiling of 12):
    # As a local portfolio maintainer adding a security from a search hit,
    # I want every type Portfolio Performance names to keep the class it
    # had,
    # so that tightening the code gate changes no proposal.
    #
    # Acceptance criteria:
    # - Every type the mapping knows, in any case and with spaces around it,
    #   maps to its class; a bond type with a government-bond description is
    #   government_bond; an unknown type is "other".
    # - A hit without a type is government_bond on such a description,
    #   "other" otherwise.
    test "every known type keeps its class" do
      expected = [
        {"Government Bond", "Muster Industrie 2030", "government_bond"},
        {" sovereign bond ", nil, "government_bond"},
        {"Treasury", nil, "government_bond"},
        {"treasury bond", nil, "government_bond"},
        {"Treasury Note", nil, "government_bond"},
        {"treasury bill", nil, "government_bond"},
        {"GOVT BOND", nil, "government_bond"},
        {"public bond", nil, "government_bond"},
        {"Staatsanleihe", nil, "government_bond"},
        {"Bundesanleihe", nil, "government_bond"},
        {"Bond", "BUNDESREPUBLIK EXAMPLIA 2031", "government_bond"},
        {"Fixed Income", "KINGDOM OF EXAMPLIA 2029", "government_bond"},
        {"Bond", "MUSTER INDUSTRIE AG 2030", "bond"},
        {"fixed income", "MUSTER INDUSTRIE AG 2030", "bond"},
        {"Common Stock", nil, "equity"},
        {"Preferred Stock", nil, "equity"},
        {"Stock", nil, "equity"},
        {"Share", nil, "equity"},
        {"Equity", nil, "equity"},
        {"ADR", nil, "equity"},
        {"GDR", nil, "equity"},
        {"ETF", nil, "etf"},
        {"Exchange-Traded Fund", nil, "etf"},
        {"ETP", nil, "etf"},
        {"ETN", nil, "etf"},
        {"ETC", nil, "etf"},
        {"Mutual Fund", nil, "fund"},
        {"Open-End Fund", nil, "fund"},
        {"Fund", nil, "fund"},
        {"Investment Fund", nil, "fund"},
        {"Cryptocurrency", nil, "crypto"},
        {"Crypto", nil, "crypto"},
        {"Commodity", nil, "commodity"},
        {"Futures", nil, "commodity"},
        {"Index", nil, "index"},
        {"WizardThingy", "REPUBLIC OF EXAMPLIA", "other"},
        {nil, "REPUBLIC OF EXAMPLIA 2034", "government_bond"},
        {nil, "MUSTER INDUSTRIE AG", "other"}
      ]

      body =
        for {type, description, _class} <- expected do
          %{"description" => description || "MUSTER", "type" => type, "markets" => []}
        end

      {:ok, results} = PortfolioPerformance.search("muster", req: req_stub(body))

      assert Enum.zip_with(expected, results, fn {type, _, class}, result ->
               {type, result.asset_class, class}
             end)
             |> Enum.reject(fn {_type, got, class} -> got == class end) == []

      assert length(results) == length(expected)
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
