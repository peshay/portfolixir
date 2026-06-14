defmodule Portfolixir.CatalogTest do
  use Portfolixir.DataCase

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Catalog.SecuritySearch.{Market, SearchResult}
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  @png <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8,
         6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 250, 207, 0, 0,
         0, 3, 0, 1, 5, 12, 60, 192, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130>>

  describe "create_security/1" do
    test "creates with required fields and normalises codes" do
      assert {:ok, security} =
               Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
                 name: "Apple Inc.",
                 ticker_symbol: "aapl",
                 currency_code: "usd",
                 asset_class: "equity"
               })

      assert security.ticker_symbol == "AAPL"
      assert security.currency_code == "USD"
      assert security.asset_class == "equity"
      assert security.is_retired == false
      assert security.excluded_from_allocation_targets == false
      assert security.attributes == %{}
    end

    # User story:
    # As a local portfolio maintainer,
    # I want to flag a security as excluded from allocation targets,
    # so that it stays in my totals but out of the allocation steering basis.
    #
    # Acceptance criteria:
    # - The flag defaults to false and is settable via the changeset.
    # - excluded_from_allocation_target_ids/0 returns only the flagged ids.
    test "casts excluded_from_allocation_targets and lists flagged ids" do
      assert {:ok, plain} =
               Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
                 name: "Plain",
                 currency_code: "EUR"
               })

      assert {:ok, excluded} =
               Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
                 name: "Bitcoin",
                 currency_code: "EUR",
                 asset_class: "crypto",
                 excluded_from_allocation_targets: true
               })

      assert plain.excluded_from_allocation_targets == false
      assert excluded.excluded_from_allocation_targets == true

      ids = Catalog.excluded_from_allocation_target_ids()
      assert MapSet.member?(ids, excluded.id)
      refute MapSet.member?(ids, plain.id)
    end

    test "rejects an unknown asset class" do
      assert {:error, changeset} =
               Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
                 name: "Foo",
                 currency_code: "EUR",
                 asset_class: "yacht"
               })

      assert {"is invalid", _} = changeset.errors[:asset_class]
    end

    # User story:
    # As a local portfolio maintainer adding government bonds,
    # I want Portfolixir to classify obvious state debt as its own type,
    # so that the UI can use the ISIN country code for a flag fallback.
    #
    # Acceptance criteria:
    # - `government_bond` is an accepted asset class.
    # - A clearly named government bond without an explicit type is inferred
    #   as `government_bond`.
    # - The ISIN is still normalized independently of the inferred type.
    test "accepts and infers government bond asset class" do
      assert {:ok, explicit} =
               Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
                 name: "German Federal Bond",
                 isin: "de0001102614",
                 currency_code: "EUR",
                 asset_class: "government_bond"
               })

      assert explicit.asset_class == "government_bond"
      assert explicit.isin == "DE0001102614"

      assert {:ok, inferred} =
               Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
                 name: "Bundesrepublik Deutschland Bundesanleihe 2034",
                 isin: "DE000BU2Z023",
                 currency_code: "EUR"
               })

      assert inferred.asset_class == "government_bond"
    end

    test "infers Portfolio Performance style ETF, crypto and state-bond names" do
      examples = [
        {"iShares Core MSCI Emerging Markets IMI UCITS ETF", "IE00BD45KH83", "etf"},
        {"Vanguard FTSE Em.Markets U.ETF Registered Shares USD Acc.oN", "IE00BK5BR733", "etf"},
        {"AIS-Amundi Index MSCI World Act.Nom.UCITS ETF DR D oN", "LU1737652237", "etf"},
        {"Amu.S&P Wld Inds Screened UETF Reg.Shs UCITS ETF Acc o.N.", "IE000LTA2082", "etf"},
        {"Bitcoin", nil, "crypto"},
        {"Anleihe USA 20/50", "US912810SN90", "government_bond"},
        {"Anleihe Norwegen 22/42", "NO0012712506", "government_bond"},
        {"Anleihe Singapur 16/46", "SG31A7000004", "government_bond"}
      ]

      for {name, isin, expected_class} <- examples do
        assert {:ok, security} =
                 Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
                   name: name,
                   isin: isin,
                   currency_code: "EUR",
                   provider: "portfolio_performance"
                 })

        assert security.asset_class == expected_class
      end
    end

    # User story:
    # As a local portfolio maintainer creating a security,
    # I want logo lookup to start automatically after the record is inserted,
    # so that I don't have to run "Update logo" row by row.
    #
    # Acceptance criteria:
    # - With logo discovery enabled, `create_security/1` starts background
    #   logo lookup after insert.
    # - Tests pass a Req plug and temporary storage, so no external network is used.
    # - The stored security gets `attributes["logo_path"]`.
    test "starts automatic logo discovery after creating a security" do
      prior_enabled = Application.get_env(:portfolixir, :enable_logo_discovery, false)
      prior_opts = Application.get_env(:portfolixir, :logo_discovery_opts, [])

      tmp =
        Path.join(
          System.tmp_dir!(),
          "portfolixir-auto-logo-#{System.unique_integer([:positive])}"
        )

      stub = [
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
          end
        end
      ]

      Application.put_env(:portfolixir, :enable_logo_discovery, true)
      Application.put_env(:portfolixir, :logo_discovery_opts, req: stub, storage_dir: tmp)

      try do
        assert {:ok, security} =
                 Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
                   name: "Automatic Logo Inc.",
                   currency_code: "USD",
                   asset_class: "equity"
                 })

        assert wait_until(fn ->
                 Catalog.get_security(security.id).attributes["logo_path"]
               end) == "/security_logos/#{security.id}.png"

        assert File.exists?(Path.join(tmp, "#{security.id}.png"))
      after
        Application.put_env(:portfolixir, :enable_logo_discovery, prior_enabled)
        Application.put_env(:portfolixir, :logo_discovery_opts, prior_opts)
        File.rm_rf(tmp)
      end
    end
  end

  describe "list_securities/1" do
    setup do
      {:ok, a} =
        Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
          name: "Apple Inc.",
          ticker_symbol: "AAPL",
          isin: "US0378331005",
          currency_code: "USD",
          asset_class: "equity"
        })

      {:ok, b} =
        Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
          name: "Bitcoin",
          ticker_symbol: "BTC",
          currency_code: "EUR",
          asset_class: "crypto",
          attributes: %{"exchange_name" => "Coinbase"}
        })

      {:ok, c} =
        Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
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

    # User story:
    # As a local portfolio maintainer,
    # I want to filter the securities list by current holding status,
    # so that I can separate active positions from sold-out or never-held securities.
    #
    # Acceptance criteria:
    # - `:held` returns securities with a non-zero derived buy/sell quantity.
    # - `:not_held` returns securities with zero or no derived quantity.
    # - `:all` keeps the existing unfiltered list behavior.
    test "filters by derived holding status", %{a: a, b: b, c: c} do
      {portfolio, cash_account, depot} = create_trade_accounts()

      assert {:ok, _} =
               Ledger.create_transaction(%{
                 portfolio_id: portfolio.id,
                 securities_account_id: depot.id,
                 cash_account_id: cash_account.id,
                 security_id: a.id,
                 type: "buy",
                 date: ~D[2026-01-02],
                 quantity: Decimal.new("3"),
                 price: Decimal.new("10"),
                 fees: Decimal.new("0"),
                 taxes: Decimal.new("0"),
                 currency_code: "EUR"
               })

      assert {:ok, _} =
               Ledger.create_transaction(%{
                 portfolio_id: portfolio.id,
                 securities_account_id: depot.id,
                 cash_account_id: cash_account.id,
                 security_id: b.id,
                 type: "buy",
                 date: ~D[2026-01-03],
                 quantity: Decimal.new("2"),
                 price: Decimal.new("20"),
                 fees: Decimal.new("0"),
                 taxes: Decimal.new("0"),
                 currency_code: "EUR"
               })

      assert {:ok, _} =
               Ledger.create_transaction(%{
                 portfolio_id: portfolio.id,
                 securities_account_id: depot.id,
                 cash_account_id: cash_account.id,
                 security_id: b.id,
                 type: "sell",
                 date: ~D[2026-01-04],
                 quantity: Decimal.new("2"),
                 price: Decimal.new("21"),
                 fees: Decimal.new("0"),
                 taxes: Decimal.new("0"),
                 currency_code: "EUR"
               })

      assert [^a] = Catalog.list_securities(holding_status: :held, sort: {:name, :asc})
      assert [^b, ^c] = Catalog.list_securities(holding_status: :not_held, sort: {:name, :asc})
      assert [^a, ^b, ^c] = Catalog.list_securities(holding_status: :all, sort: {:name, :asc})
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

      assert {:ok, security} =
               Catalog.create_from_search_result(Portfolixir.Actor.owner_ui(), result)

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

      assert {:ok, _existing} =
               Catalog.create_from_search_result(Portfolixir.Actor.owner_ui(), result)

      assert {:conflict, conflict} =
               Catalog.create_from_search_result(Portfolixir.Actor.owner_ui(), result)

      assert conflict.online_id == "uuid-dup"
    end

    test "returns :conflict on ISIN match without online_id" do
      {:ok, _existing} =
        Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
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

      assert {:conflict, _} =
               Catalog.create_from_search_result(Portfolixir.Actor.owner_ui(), result)
    end
  end

  describe "merge_search_result/3" do
    test "updates online fields and merges attributes without clobbering note" do
      {:ok, existing} =
        Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
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

      assert {:ok, updated} =
               Catalog.merge_search_result(
                 Portfolixir.Actor.owner_ui(),
                 existing,
                 result,
                 hd(result.markets)
               )

      assert updated.note == "user note"
      assert updated.online_id == "uuid-merge"
      assert updated.attributes["local"] == "keep"
      assert updated.attributes["exchange_name"] == "Xetra"
    end
  end

  describe "backfill_inferred_asset_classes/0" do
    # User story:
    # As a local portfolio maintainer,
    # I want imported securities to be filterable by their inferred asset class,
    # so that a security shown as ETF is also returned when I filter for ETF.
    #
    # Acceptance criteria:
    # - Legacy rows with asset_class = nil get the inferred class persisted.
    # - After backfill, the column-backed asset_class filter returns the row.
    # - Rows with an explicit class, or no inferable class, are left unchanged.
    test "persists inferred classes so display and filters agree" do
      legacy = legacy_security_without_asset_class("iShares Core MSCI World UCITS ETF")
      etf_filter = [%{key: :asset_class, op: :eq, value: "etf"}]

      assert Security.effective_asset_class(legacy) == "etf"
      assert is_nil(legacy.asset_class)
      assert [] == Catalog.list_securities(filters: etf_filter)

      assert 1 == backfill_as_migration()

      assert Repo.get!(Security, legacy.id).asset_class == "etf"
      assert [%{id: id}] = Catalog.list_securities(filters: etf_filter)
      assert id == legacy.id
    end

    test "leaves explicit and non-inferable asset classes unchanged" do
      {:ok, explicit} =
        Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
          name: "Apple Inc.",
          ticker_symbol: "AAPL",
          currency_code: "USD",
          asset_class: "equity"
        })

      mystery = legacy_security_without_asset_class("Mystery Holding 2030")
      assert is_nil(Security.effective_asset_class(mystery))

      assert 0 == backfill_as_migration()

      assert Repo.get!(Security, explicit.id).asset_class == "equity"
      assert is_nil(Repo.get!(Security, mystery.id).asset_class)
    end
  end

  # Simulates a security imported before asset-class inference: a persisted row
  # whose name implies a class but whose asset_class column is nil. Created
  # through the journaled actor-first writes (the `securities` table is
  # guard-armed, FR-28): `create_security/2` infers and persists a class on
  # write, then `set_asset_class/3` clears it back to nil — reproducing the
  # legacy state without a raw, un-journaled `Repo.update`.
  defp legacy_security_without_asset_class(name) do
    actor = Portfolixir.Actor.owner_ui()

    {:ok, security} =
      Catalog.create_security(actor, %{name: name, currency_code: "EUR"})

    Catalog.set_asset_class(actor, [security.id], nil)
    Catalog.get_security!(security.id)
  end

  # `backfill_inferred_asset_classes/0` is a migration-only data backfill that
  # writes `securities` via un-journaled `update_all`. Real migrations run before
  # the `securities` guard trigger is armed (FR-28); to exercise the backfill's
  # inference logic against the already-armed test database we replay the
  # migration environment with the documented escape hatch
  # (`session_replication_role = replica`, ADR-0015), then restore it.
  defp backfill_as_migration do
    {:ok, count} =
      Repo.transaction(fn ->
        Repo.query!("SET LOCAL session_replication_role = replica")
        count = Catalog.backfill_inferred_asset_classes()
        Repo.query!("SET LOCAL session_replication_role = DEFAULT")
        count
      end)

    count
  end

  defp create_trade_accounts do
    assert {:ok, portfolio} =
             Portfolios.create_portfolio(%{
               name: "Holding Filter Portfolio",
               base_currency_code: "EUR"
             })

    assert {:ok, cash_account} =
             Portfolios.create_cash_account(%{
               portfolio_id: portfolio.id,
               name: "Holding Filter Cash",
               currency_code: "EUR"
             })

    assert {:ok, depot} =
             Portfolios.create_securities_account(%{
               portfolio_id: portfolio.id,
               cash_account_id: cash_account.id,
               name: "Holding Filter Depot"
             })

    {portfolio, cash_account, depot}
  end

  defp wait_until(fun, attempts \\ 30)

  defp wait_until(fun, attempts) when attempts > 0 do
    case fun.() do
      nil ->
        Process.sleep(25)
        wait_until(fun, attempts - 1)

      false ->
        Process.sleep(25)
        wait_until(fun, attempts - 1)

      value ->
        value
    end
  end

  defp wait_until(_fun, 0), do: nil
end
