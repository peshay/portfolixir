defmodule Portfolixir.CatalogTest do
  use Portfolixir.DataCase

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.SecuritySearch.{Market, SearchResult}

  describe "create_security/1" do
    test "creates with required fields and normalises codes" do
      assert {:ok, security} =
               Catalog.create_security(%{
                 name: "Apple Inc.",
                 ticker_symbol: "aapl",
                 currency_code: "usd",
                 asset_class: "equity"
               })

      assert security.ticker_symbol == "AAPL"
      assert security.currency_code == "USD"
      assert security.asset_class == "equity"
      assert security.is_retired == false
      assert security.attributes == %{}
    end

    test "rejects an unknown asset class" do
      assert {:error, changeset} =
               Catalog.create_security(%{
                 name: "Foo",
                 currency_code: "EUR",
                 asset_class: "yacht"
               })

      assert {"is invalid", _} = changeset.errors[:asset_class]
    end
  end

  describe "list_securities/1" do
    setup do
      {:ok, a} =
        Catalog.create_security(%{
          name: "Apple Inc.",
          ticker_symbol: "AAPL",
          isin: "US0378331005",
          currency_code: "USD",
          asset_class: "equity"
        })

      {:ok, b} =
        Catalog.create_security(%{
          name: "Bitcoin",
          ticker_symbol: "BTC",
          currency_code: "EUR",
          asset_class: "crypto",
          attributes: %{"exchange_name" => "Coinbase"}
        })

      {:ok, c} =
        Catalog.create_security(%{
          name: "Caterpillar",
          ticker_symbol: "CAT",
          currency_code: "USD",
          asset_class: "equity",
          is_retired: true
        })

      %{a: a, b: b, c: c}
    end

    test "query filters by name/ticker/isin/wkn (case-insensitive)", %{a: a} do
      assert [^a] = Catalog.list_securities(query: "apple")
      assert [^a] = Catalog.list_securities(query: "us03783")
    end

    test "enum filter on asset_class returns matching rows", %{b: b} do
      assert [^b] =
               Catalog.list_securities(filters: [%{key: :asset_class, op: :eq, value: "crypto"}])
    end

    test "boolean filter on is_retired", %{c: c} do
      assert [^c] =
               Catalog.list_securities(filters: [%{key: :is_retired, op: :is_true, value: true}])
    end

    test "JSONB attribute filter is rejected by the whitelist (not filterable in v1)", %{
      a: a,
      b: b,
      c: c
    } do
      # Filter is dropped silently — list returns everything unfiltered.
      results =
        Catalog.list_securities(
          filters: [%{key: :attr_exchange_name, op: :eq, value: "Coinbase"}],
          sort: {:name, :asc}
        )

      assert [^a, ^b, ^c] = results
    end

    test "invalid filters are silently dropped", %{a: a, b: b, c: c} do
      # gt on a string field is not allowed → filter is dropped, all rows returned
      results =
        Catalog.list_securities(
          filters: [%{key: :name, op: :gt, value: "A"}],
          sort: {:name, :asc}
        )

      assert [^a, ^b, ^c] = results
    end

    test "unknown sort key falls back to name asc", %{a: a, b: b, c: c} do
      assert [^a, ^b, ^c] = Catalog.list_securities(sort: {:nope, :asc})
    end

    test "sort by ticker_symbol descending", %{a: a, b: b, c: c} do
      assert [^c, ^b, ^a] = Catalog.list_securities(sort: {:ticker_symbol, :desc})
    end
  end

  describe "create_from_search_result/3" do
    test "creates a new security with provider+online_id attribution" do
      result = %SearchResult{
        provider: :portfolio_performance,
        online_id: "uuid-1",
        name: "Test Inc.",
        isin: "US0000000001",
        ticker_symbol: "TST",
        asset_class: "equity",
        currency_code: "USD",
        feed: "PORTFOLIO_PERFORMANCE",
        markets: []
      }

      assert {:ok, security} = Catalog.create_from_search_result(result)
      assert security.provider == "portfolio_performance"
      assert security.online_id == "uuid-1"
      assert security.feed == "PORTFOLIO_PERFORMANCE"
    end

    test "returns :conflict when provider+online_id already exists" do
      result = %SearchResult{
        provider: :portfolio_performance,
        online_id: "uuid-dup",
        name: "Dup Inc.",
        ticker_symbol: "DUP",
        asset_class: "equity",
        currency_code: "USD",
        feed: "PORTFOLIO_PERFORMANCE",
        markets: []
      }

      assert {:ok, _existing} = Catalog.create_from_search_result(result)
      assert {:conflict, conflict} = Catalog.create_from_search_result(result)
      assert conflict.online_id == "uuid-dup"
    end

    test "returns :conflict on ISIN match without online_id" do
      {:ok, _existing} =
        Catalog.create_security(%{
          name: "Foo SA",
          ticker_symbol: "FOO",
          currency_code: "EUR",
          asset_class: "equity",
          isin: "DE0000000001"
        })

      result = %SearchResult{
        provider: :portfolio_performance,
        online_id: nil,
        name: "Foo SA",
        isin: "DE0000000001",
        ticker_symbol: "FOO",
        currency_code: "EUR",
        feed: "PORTFOLIO_PERFORMANCE",
        markets: []
      }

      assert {:conflict, _} = Catalog.create_from_search_result(result)
    end
  end

  describe "merge_search_result/3" do
    test "updates online fields and merges attributes without clobbering note" do
      {:ok, existing} =
        Catalog.create_security(%{
          name: "Foo",
          ticker_symbol: "FOO",
          currency_code: "EUR",
          asset_class: "equity",
          isin: "DE0000000002",
          note: "user note",
          attributes: %{"local" => "keep"}
        })

      result = %SearchResult{
        provider: :portfolio_performance,
        online_id: "uuid-merge",
        name: "Foo NEW",
        isin: "DE0000000002",
        currency_code: "EUR",
        ticker_symbol: "FOO",
        asset_class: "equity",
        feed: "PORTFOLIO_PERFORMANCE",
        markets: [%Market{symbol: "FOO", currency_code: "EUR", exchange_name: "Xetra"}]
      }

      assert {:ok, updated} = Catalog.merge_search_result(existing, result, hd(result.markets))
      assert updated.note == "user note"
      assert updated.online_id == "uuid-merge"
      assert updated.attributes["local"] == "keep"
      assert updated.attributes["exchange_name"] == "Xetra"
    end
  end
end
