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
  @png <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8,
         6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 250, 207, 0, 0,
         0, 3, 0, 1, 5, 12, 60, 192, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130>>

  defp read!(name), do: File.read!(Path.join(@fixtures, name))

  defp logo_stub do
    [
      plug: fn conn ->
        cond do
          conn.request_path =~ "/api/rest_v1/page/summary/" ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(
              200,
              Jason.encode!(%{
                "originalimage" => %{"source" => "https://example.test/logo.png"}
              })
            )

          conn.request_path == "/logo.png" ->
            conn
            |> Plug.Conn.put_resp_content_type("image/png")
            |> Plug.Conn.send_resp(200, @png)

          true ->
            Plug.Conn.send_resp(conn, 404, "not found")
        end
      end
    ]
  end

  defp wait_until(fun, attempts \\ 40)

  defp wait_until(fun, attempts) when attempts > 0 do
    case fun.() do
      nil ->
        Process.sleep(50)
        wait_until(fun, attempts - 1)

      false ->
        Process.sleep(50)
        wait_until(fun, attempts - 1)

      value ->
        value
    end
  end

  defp wait_until(fun, _attempts), do: fun.()

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

    # User story:
    # As a local portfolio maintainer importing Portfolio Performance history,
    # I want import-created securities to start logo enrichment after commit,
    # so that Apple, Nvidia, Tesla, and ETF-provider logos appear without
    # clicking "Update logo" row by row.
    #
    # Acceptance criteria:
    # - Import-created equity and ETF securities infer an asset class during create.
    # - Logo discovery runs after commit, where the background task can reload the rows.
    # - Tests use fake Wikipedia/image responses and temporary storage only.
    test "triggers post-commit logo enrichment for import-created securities", %{
      portfolio: portfolio,
      preview: preview
    } do
      prior_enabled = Application.get_env(:portfolixir, :enable_logo_discovery, false)
      prior_opts = Application.get_env(:portfolixir, :logo_discovery_opts, [])

      tmp =
        Path.join(
          System.tmp_dir!(),
          "portfolixir-import-logos-#{System.unique_integer([:positive])}"
        )

      Application.put_env(:portfolixir, :enable_logo_discovery, true)
      Application.put_env(:portfolixir, :logo_discovery_opts, req: logo_stub(), storage_dir: tmp)

      try do
        assert {:ok, %Result{} = result} = Imports.apply(preview, %{portfolio_id: portfolio.id})

        securities = Enum.map(result.created_security_ids, &Catalog.get_security!/1)
        assert Enum.sort(Enum.map(securities, & &1.asset_class)) == ["equity", "etf"]

        assert wait_until(fn ->
                 result.created_security_ids
                 |> Enum.map(&Catalog.get_security!/1)
                 |> Enum.all?(& &1.attributes["logo_path"])
               end)

        for id <- result.created_security_ids do
          security = Catalog.get_security!(id)
          assert security.attributes["logo_path"] == "/security_logos/#{id}.png"
          assert security.attributes["logo_source"] == "wikipedia"
          assert File.exists?(Path.join(tmp, "#{id}.png"))
        end
      after
        Application.put_env(:portfolixir, :enable_logo_discovery, prior_enabled)
        Application.put_env(:portfolixir, :logo_discovery_opts, prior_opts)
        File.rm_rf(tmp)
      end
    end

    # User story:
    # As a local portfolio maintainer who imported data before automatic
    # logos worked,
    # I want a later idempotent import of the same file to enqueue missing
    # logos for already-known securities,
    # so that I am not forced to open each row and click "Update logo".
    #
    # Acceptance criteria:
    # - The second import creates no new securities or transactions.
    # - Existing securities referenced by the import are still considered for
    #   missing-logo enrichment.
    # - Tests use fake Wikipedia/image responses and temporary storage only.
    test "re-import enriches missing logos for already-known securities", %{
      portfolio: portfolio,
      preview: preview
    } do
      prior_enabled = Application.get_env(:portfolixir, :enable_logo_discovery, false)
      prior_opts = Application.get_env(:portfolixir, :logo_discovery_opts, [])

      tmp =
        Path.join(
          System.tmp_dir!(),
          "portfolixir-reimport-logos-#{System.unique_integer([:positive])}"
        )

      Application.put_env(:portfolixir, :enable_logo_discovery, false)
      Application.put_env(:portfolixir, :logo_discovery_opts, [])

      try do
        assert {:ok, %Result{} = first} = Imports.apply(preview, %{portfolio_id: portfolio.id})
        ids = first.created_security_ids

        assert ids != []

        assert Enum.all?(ids, fn id ->
                 is_nil(Catalog.get_security!(id).attributes["logo_path"])
               end)

        Application.put_env(:portfolixir, :enable_logo_discovery, true)

        Application.put_env(:portfolixir, :logo_discovery_opts,
          req: logo_stub(),
          storage_dir: tmp
        )

        assert {:ok, %Result{} = second} = Imports.apply(preview, %{portfolio_id: portfolio.id})
        assert second.created_securities == 0
        assert second.created_transactions == 0
        assert second.skipped_duplicates == 13

        assert wait_until(fn ->
                 ids
                 |> Enum.map(&Catalog.get_security!/1)
                 |> Enum.all?(& &1.attributes["logo_path"])
               end)

        for id <- ids do
          security = Catalog.get_security!(id)
          assert security.attributes["logo_path"] == "/security_logos/#{id}.png"
          assert security.attributes["logo_source"] == "wikipedia"
          assert File.exists?(Path.join(tmp, "#{id}.png"))
        end
      after
        Application.put_env(:portfolixir, :enable_logo_discovery, prior_enabled)
        Application.put_env(:portfolixir, :logo_discovery_opts, prior_opts)
        File.rm_rf(tmp)
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

  # User story:
  # As a local portfolio maintainer importing Portfolio Performance history,
  # I want the import to reject a record whose currency does not match the
  # currency of the existing cash account it resolves to and carries no
  # settlement FX rate (issue #388, ADR-0015),
  # so that a USD booking is never silently folded into my EUR cash
  # account and corrupts the balance.
  #
  # Acceptance criteria:
  # - A mismatched record with no settlement FX rate fails the apply with a
  #   readable error (cross-currency PP mapping is a tracked follow-up, #388).
  # - The whole import rolls back; no rows leak through.
  describe "apply/2 currency consistency" do
    alias Portfolixir.Imports.Entry
    alias Portfolixir.Imports.Preview

    test "rejects a mismatched record with no settlement FX rate" do
      portfolio = setup_portfolio()

      {:ok, _eur_cash} =
        Portfolios.create_cash_account(%{
          portfolio_id: portfolio.id,
          name: "EUR-Cash",
          currency_code: "EUR"
        })

      preview = %Preview{
        format: :json,
        entries: [
          %Entry{
            source_row: 1,
            kind: "deposit",
            date: ~D[2024-04-01],
            currency_code: "USD",
            gross_amount: Decimal.new("100.00"),
            fees: Decimal.new("0"),
            taxes: Decimal.new("0"),
            pp_account_name: "EUR-Cash"
          }
        ]
      }

      assert {:error, reason} = Imports.apply(preview, %{portfolio_id: portfolio.id})
      assert {:insert_failed, %Ecto.Changeset{} = changeset} = reason.reason

      assert %{settlement_fx_rate: ["is required for a cross-currency settlement"]} =
               errors_on(changeset)

      assert Ledger.list_transactions_for_portfolio(portfolio.id) == []
    end
  end

  # User story:
  # As a maintainer importing a PP export that holds a foreign-currency cash
  # account (e.g. a USD savings account), I want the mapping import to create
  # that account in its own currency, so its bookings are not rejected by the
  # cash-account currency-consistency check.
  describe "apply/2 infers created cash account currency (#369)" do
    alias Portfolixir.Imports.Entry
    alias Portfolixir.Imports.Preview

    test "creates a new cash account in the currency of its bookings" do
      preview = %Preview{
        format: :json,
        entries: [
          %Entry{
            source_row: 1,
            kind: "deposit",
            date: ~D[2025-06-08],
            currency_code: "USD",
            gross_amount: Decimal.new("19235.74"),
            fees: Decimal.new("0"),
            taxes: Decimal.new("0"),
            pp_account_name: "Bunq Savings USD"
          },
          %Entry{
            source_row: 2,
            kind: "deposit",
            date: ~D[2025-06-08],
            currency_code: "EUR",
            gross_amount: Decimal.new("100.00"),
            fees: Decimal.new("0"),
            taxes: Decimal.new("0"),
            pp_account_name: "Giro EUR"
          }
        ]
      }

      params = %{
        portfolio: {:create, %{name: "FX-Import", base_currency_code: "EUR"}},
        cash_accounts: %{
          "Bunq Savings USD" => {:create, "Bunq Savings USD"},
          "Giro EUR" => {:create, "Giro EUR"}
        },
        depots: %{}
      }

      assert {:ok, %Result{created_cash_accounts: 2}} = Imports.apply(preview, params)

      portfolio = Portfolios.list_portfolios() |> Enum.find(&(&1.name == "FX-Import"))

      currencies =
        portfolio.id
        |> Portfolios.list_cash_accounts_for_portfolio()
        |> Map.new(fn c -> {c.name, c.currency_code} end)

      assert currencies["Bunq Savings USD"] == "USD"
      assert currencies["Giro EUR"] == "EUR"

      # Both deposits were accepted (USD matched the created USD account).
      assert length(Ledger.list_transactions_for_portfolio(portfolio.id)) == 2
    end
  end
end
