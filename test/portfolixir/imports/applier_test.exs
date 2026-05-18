defmodule Portfolixir.Imports.ApplierTest do
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Catalog
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Applier.Result
  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  defmodule EnrichmentAdapter do
    @moduledoc false
    @behaviour Portfolixir.Catalog.QuoteSync.Provider

    @impl true
    def id, do: :enrichment_test

    @impl true
    def fetch(security, _opts) do
      test_pid = Application.fetch_env!(:portfolixir, :quote_sync_test_pid)
      committed? = Portfolixir.Catalog.get_security(security.id) != nil
      send(test_pid, {:post_commit_quote_sync, security.id, committed?})
      {:ok, []}
    end
  end

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

    # User story:
    # As a local portfolio maintainer importing Portfolio Performance history,
    # I want newly created securities to keep their PP quote attribution,
    # so that later quote sync and logo enrichment can operate from auditable source data.
    #
    # Acceptance criteria:
    # - Import-created securities have provider `portfolio_performance`.
    # - Import-created securities have feed `PORTFOLIO_PERFORMANCE`.
    # - The result includes the created security IDs for post-commit enrichment.
    test "tags PP-created securities and returns their IDs", %{
      portfolio: portfolio,
      preview: preview
    } do
      assert {:ok, %Result{} = result} = Imports.apply(preview, %{portfolio_id: portfolio.id})

      assert length(result.created_security_ids) == 2

      securities = Enum.map(result.created_security_ids, &Catalog.get_security!/1)

      assert Enum.all?(securities, &(&1.provider == "portfolio_performance"))
      assert Enum.all?(securities, &(&1.feed == "PORTFOLIO_PERFORMANCE"))
    end

    # User story:
    # As a local portfolio maintainer importing Portfolio Performance history,
    # I want quote/logo enrichment to start only after the import transaction commits,
    # so that background work can see the created securities and tests stay network-free.
    #
    # Acceptance criteria:
    # - Import apply starts quote enrichment for created securities after commit.
    # - Tests use a fake adapter and no external network.
    # - The adapter can read the committed security row.
    test "triggers post-commit quote enrichment for import-created securities", %{
      portfolio: portfolio,
      preview: preview
    } do
      prior_cfg = Application.get_env(:portfolixir, Portfolixir.Catalog.QuoteSync, [])
      prior_logo = Application.get_env(:portfolixir, :enable_logo_discovery, false)
      prior_test_pid = Application.get_env(:portfolixir, :quote_sync_test_pid)

      Application.put_env(:portfolixir, :quote_sync_test_pid, self())
      Application.put_env(:portfolixir, :enable_logo_discovery, false)

      Application.put_env(
        :portfolixir,
        Portfolixir.Catalog.QuoteSync,
        Keyword.merge(prior_cfg,
          enabled?: true,
          adapter_for: %{"portfolio_performance" => EnrichmentAdapter}
        )
      )

      try do
        assert {:ok, %Result{} = result} = Imports.apply(preview, %{portfolio_id: portfolio.id})

        for id <- result.created_security_ids do
          assert_receive {:post_commit_quote_sync, ^id, true}, 500
        end
      after
        Application.put_env(:portfolixir, Portfolixir.Catalog.QuoteSync, prior_cfg)
        Application.put_env(:portfolixir, :enable_logo_discovery, prior_logo)

        if is_nil(prior_test_pid) do
          Application.delete_env(:portfolixir, :quote_sync_test_pid)
        else
          Application.put_env(:portfolixir, :quote_sync_test_pid, prior_test_pid)
        end
      end
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

  describe "apply/2 import_hash discriminators" do
    alias Portfolixir.Imports.Entry
    alias Portfolixir.Imports.Preview

    # Two buys of the same security on the same day with the same
    # quantity and gross_amount, but distinct intraday times and per-
    # share prices, must both end up in the ledger — the dedupe hash
    # should not collapse them.
    test "two same-day same-quantity buys at different times/prices both insert" do
      portfolio = setup_portfolio()

      security_ref = %{
        name: "Apple Inc.",
        isin: "US0378331005",
        wkn: "865985",
        ticker: "AAPL",
        currency: "EUR"
      }

      entry_at = fn time, price ->
        %Entry{
          source_row: 1,
          kind: "buy",
          date: ~D[2024-04-01],
          time: time,
          currency_code: "EUR",
          gross_amount: Decimal.new("1500.00"),
          fees: Decimal.new("0"),
          taxes: Decimal.new("0"),
          quantity: Decimal.new("10"),
          price: price,
          security: security_ref,
          pp_portfolio_name: "Test-Depot",
          pp_account_name: "Test-Cash"
        }
      end

      preview = %Preview{
        format: :json,
        entries: [
          entry_at.(~T[10:00:00], Decimal.new("150.00")),
          entry_at.(~T[15:30:00], Decimal.new("150.10"))
        ]
      }

      assert {:ok, %Result{created_transactions: 2, skipped_duplicates: 0}} =
               Imports.apply(preview, %{portfolio_id: portfolio.id})
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
