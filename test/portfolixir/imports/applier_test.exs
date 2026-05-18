defmodule Portfolixir.Imports.ApplierTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Catalog
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Applier.Result
  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  @fixtures Path.expand("../../support/fixtures/portfolio_performance", __DIR__)

  defp read!(name), do: File.read!(Path.join(@fixtures, name))

  # User story:
  # As a local portfolio maintainer who has parsed my PP export and
  # picked the Portfolixir portfolio to import into,
  # I want the applier to atomically create the missing securities,
  # cash accounts and depots, then insert one transaction per entry —
  # skipping any duplicates I have already imported,
  # so that re-running the import is safe and the final ledger matches
  # the source export exactly.
  #
  # Acceptance criteria:
  # - The applier creates the union of securities/accounts/depots
  #   referenced in the preview.
  # - The applier inserts one row per supported entry kind.
  # - A second apply of the same preview produces zero new
  #   transactions and increments `skipped_duplicates`.
  # - On a real changeset failure (negative quantity etc.), the entire
  #   transaction rolls back and no rows leak through.

  defp setup_portfolio do
    {:ok, portfolio} =
      Portfolios.create_portfolio(%{name: "Import target", base_currency_code: "EUR"})

    portfolio
  end

  defp sample_preview do
    {:ok, preview} = PortfolioPerformance.parse(read!("sample.json"), filename: "sample.json")
    preview
  end

  describe "apply/2 on the JSON sample" do
    setup do
      portfolio = setup_portfolio()
      preview = sample_preview()
      {:ok, portfolio: portfolio, preview: preview}
    end

    test "creates the union of missing securities, accounts and depots", %{
      portfolio: portfolio,
      preview: preview
    } do
      assert {:ok, %Result{} = result} = Imports.apply(preview, %{portfolio_id: portfolio.id})

      # Sample has 2 distinct ISINs (Apple, iShares MSCI World).
      assert result.created_securities == 2

      # Sample has 3 distinct cash account names (Test-Cash, Test-Cash-2)
      # plus the depot-only entries which do not touch cash.
      assert result.created_cash_accounts == 2

      # Sample has 2 distinct depots (Test-Depot, Test-Depot-2).
      assert result.created_securities_accounts == 2

      # 13 entries in the fixture, all supported kinds.
      assert result.created_transactions == 13
      assert result.skipped_duplicates == 0
      assert result.skipped_entries == []
    end

    test "applies again as a no-op (idempotent on import_hash)", %{
      portfolio: portfolio,
      preview: preview
    } do
      assert {:ok, %Result{created_transactions: 13}} =
               Imports.apply(preview, %{portfolio_id: portfolio.id})

      assert {:ok, %Result{} = second} = Imports.apply(preview, %{portfolio_id: portfolio.id})
      assert second.created_transactions == 0
      assert second.created_securities == 0
      assert second.created_cash_accounts == 0
      assert second.created_securities_accounts == 0
      assert second.skipped_duplicates == 13
    end

    test "links each created transaction to the chosen portfolio", %{
      portfolio: portfolio,
      preview: preview
    } do
      {:ok, _} = Imports.apply(preview, %{portfolio_id: portfolio.id})

      txs = Ledger.list_transactions_for_portfolio(portfolio.id)
      assert length(txs) == 13
      assert Enum.all?(txs, &(&1.portfolio_id == portfolio.id))
    end

    test "reuses an existing security matched by ISIN rather than duplicating it", %{
      portfolio: portfolio,
      preview: preview
    } do
      {:ok, existing} =
        Catalog.create_security(%{
          name: "Apple Inc.",
          isin: "US0378331005",
          ticker_symbol: "AAPL",
          currency_code: "EUR"
        })

      {:ok, result} = Imports.apply(preview, %{portfolio_id: portfolio.id})

      # Only the second ISIN (iShares) needed to be created.
      assert result.created_securities == 1

      txs = Ledger.list_transactions_for_portfolio(portfolio.id)
      apple_txs = Enum.filter(txs, &(&1.security_id == existing.id))
      # buy + sell + dividend on Apple in the fixture
      assert length(apple_txs) == 3
    end
  end

  describe "apply/2 with explicit mapping (Story 6.B)" do
    test "creates the portfolio inline when chosen as {:create, …}" do
      preview = sample_preview()

      params = %{
        portfolio: {:create, %{name: "Mapping-Portfolio", base_currency_code: "EUR"}},
        cash_accounts: %{
          "Test-Cash" => {:create, "Test-Cash"},
          "Test-Cash-2" => {:create, "Test-Cash-2"}
        },
        depots: %{
          "Test-Depot" => %{target: {:create, "Test-Depot"}, cash: "Test-Cash"},
          "Test-Depot-2" => %{target: {:create, "Test-Depot-2"}, cash: "Test-Cash"}
        }
      }

      assert {:ok, %Result{} = result} = Imports.apply(preview, params)

      portfolio = Portfolios.list_portfolios() |> Enum.find(&(&1.name == "Mapping-Portfolio"))
      assert portfolio

      assert result.created_cash_accounts == 2
      assert result.created_securities_accounts == 2

      cash_names =
        Portfolios.list_cash_accounts_for_portfolio(portfolio.id)
        |> Enum.map(& &1.name)
        |> Enum.sort()

      assert cash_names == ["Test-Cash", "Test-Cash-2"]
    end

    test "rolls back when a depot mapping references a cash account that is not in the map" do
      _portfolio = setup_portfolio()
      preview = sample_preview()

      params = %{
        portfolio: {:create, %{name: "Bad-Mapping", base_currency_code: "EUR"}},
        cash_accounts: %{},
        depots: %{
          "Test-Depot" => %{target: {:create, "Test-Depot"}, cash: "Missing-Cash"}
        }
      }

      assert {:error, {:unresolved_depot_cash_ref, "Missing-Cash"}} =
               Imports.apply(preview, params)

      refute Portfolios.list_portfolios() |> Enum.find(&(&1.name == "Bad-Mapping"))
    end
  end

  describe "apply/2 rollback on real failure" do
    test "rolls back the entire transaction when one entry's changeset rejects" do
      portfolio = setup_portfolio()
      preview = sample_preview()

      # Corrupt one entry so its changeset will fail.
      [bad | rest] = preview.entries
      bad = %{bad | quantity: Decimal.new("-1")}
      preview = %{preview | entries: [bad | rest]}

      assert {:error, _reason} = Imports.apply(preview, %{portfolio_id: portfolio.id})

      # Nothing should have leaked through.
      assert Ledger.list_transactions_for_portfolio(portfolio.id) == []
      assert Portfolios.list_cash_accounts_for_portfolio(portfolio.id) == []
      assert Portfolios.list_securities_accounts_for_portfolio(portfolio.id) == []
    end
  end
end
