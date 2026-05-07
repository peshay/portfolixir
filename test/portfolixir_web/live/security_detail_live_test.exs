defmodule PortfolixirWeb.SecurityDetailLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.{FundAllocation, FundAllocationItem}
  alias Portfolixir.Imports
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo
  alias Portfolixir.Portfolios

  setup do
    Catalog.ensure_mvp_currencies!()

    {:ok, portfolio} =
      Portfolios.create_portfolio(%{
        name: "Primary",
        base_currency_code: "EUR"
      })

    {:ok, deposit_account} =
      Portfolios.create_deposit_account(%{
        portfolio_id: portfolio.id,
        name: "Settlement Cash",
        currency_code: "EUR"
      })

    {:ok, securities_account} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        reference_deposit_account_id: deposit_account.id,
        name: "Main Depot",
        currency_code: "EUR"
      })

    %{
      portfolio: portfolio,
      deposit_account: deposit_account,
      securities_account: securities_account
    }
  end

  test "shows security master data with name, symbol, and identifiers", %{conn: conn} do
    security =
      create_security(%{
        name: "Synthetic ETF",
        symbol: "SYN",
        currency_code: "EUR",
        isin: "US0000000001",
        wkn: "A1B2C3",
        provider_symbol: "SYN.X"
      })

    {:ok, view, html} = live(conn, "/securities/#{security.id}")

    assert html =~ ~r/<th scope="row">Name<\/th>/
    assert html =~ ~r/<th scope="row">Symbol<\/th>/

    assert has_element?(view, "#security-detail-title", "Synthetic ETF (SYN)")
    assert has_element?(view, "#security-master-data", "Synthetic ETF")
    assert has_element?(view, "#security-master-data", "SYN")
    assert has_element?(view, "#security-master-data", "US0000000001")
    assert has_element?(view, "#security-master-data", "A1B2C3")
    assert has_element?(view, "#security-master-data", "EUR")
    assert has_element?(view, "#security-master-data", "SYN.X")
  end

  test "shows buy transactions for the selected security", %{
    conn: conn,
    securities_account: securities_account,
    portfolio: portfolio
  } do
    security = create_security(%{name: "Buy Security", symbol: "BUY", currency_code: "EUR"})

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: securities_account.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-04-01],
        currency_code: "EUR",
        quantity: Decimal.new("10.00"),
        price: Decimal.new("12.50"),
        amount: Decimal.new("125.00"),
        notes: "Initial buy"
      })

    create_quote(security.id, ~D[2026-04-01], "12.50")

    {:ok, view, _html} = live(conn, "/securities/#{security.id}")

    assert has_element?(view, "#security-transactions", "Buy")
    assert has_element?(view, "#security-transactions", "Main Depot")
    assert has_element?(view, "#security-transactions", "10")
    assert has_element?(view, "#security-transactions", "12.5")
    assert has_element?(view, "#security-transactions", "125")
    assert has_element?(view, "#security-transactions", "Initial buy")

    assert has_element?(view, "#security-price-chart-svg")
    assert has_element?(view, "#security-chart-marker-0[data-type='buy']")
  end

  test "shows sell transactions for the selected security", %{
    conn: conn,
    securities_account: securities_account,
    portfolio: portfolio
  } do
    security = create_security(%{name: "Sell Security", symbol: "SELL", currency_code: "EUR"})

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: securities_account.id,
        security_id: security.id,
        type: "sell",
        date: ~D[2026-04-02],
        currency_code: "EUR",
        quantity: Decimal.new("3.00"),
        price: Decimal.new("15.00"),
        amount: Decimal.new("45.00"),
        notes: "Partial sale"
      })

    create_quote(security.id, ~D[2026-04-02], "15.00")

    {:ok, view, _html} = live(conn, "/securities/#{security.id}")

    assert has_element?(view, "#security-transactions", "Sell")
    assert has_element?(view, "#security-transactions", "Partial sale")
    assert has_element?(view, "#security-transactions", "45")

    assert has_element?(view, "#security-price-chart-svg")
    assert has_element?(view, "#security-chart-marker-0[data-type='sell']")
  end

  test "shows dividend transactions for the selected security", %{
    conn: conn,
    deposit_account: deposit_account,
    portfolio: portfolio
  } do
    security = create_security(%{name: "Dividend Security", symbol: "DIV", currency_code: "EUR"})

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        deposit_account_id: deposit_account.id,
        security_id: security.id,
        type: "dividend",
        date: ~D[2026-04-03],
        currency_code: "EUR",
        amount: Decimal.new("11.00"),
        notes: "Dividend payment"
      })

    create_quote(security.id, ~D[2026-04-03], "11.00")

    {:ok, view, _html} = live(conn, "/securities/#{security.id}")

    assert has_element?(view, "#security-transactions", "Dividend")
    assert has_element?(view, "#security-transactions", "Dividend payment")
    assert has_element?(view, "#security-transactions", "11")

    assert has_element?(view, "#security-price-chart-svg")
    assert has_element?(view, "#security-chart-marker-0[data-type='dividend']")
  end

  test "shows neutral current position empty state when no transactions exist", %{conn: conn} do
    security =
      create_security(%{name: "Empty Security", symbol: "EMPTY", currency_code: "EUR"})

    {:ok, view, _html} = live(conn, "/securities/#{security.id}")

    assert has_element?(view, "#no-security-positions")
    assert has_element?(view, "#no-security-positions", "No current position available")

    assert has_element?(
             view,
             "#no-security-positions",
             "Current position data is unavailable for this security."
           )

    assert has_element?(view, "#no-security-transactions")
    assert has_element?(view, "#no-security-transactions", "No transactions are recorded")
    assert has_element?(view, "#security-price-chart-empty")
  end

  test "shows current derived positions per securities account", %{
    conn: conn,
    deposit_account: deposit_account,
    securities_account: securities_account,
    portfolio: portfolio
  } do
    second_deposit =
      create_deposit_account(%{
        portfolio_id: deposit_account.portfolio_id,
        name: "Secondary cash"
      })

    second_securities_account =
      create_securities_account(%{
        portfolio_id: deposit_account.portfolio_id,
        reference_deposit_account_id: second_deposit.id,
        name: "Secondary depot"
      })

    security = create_security(%{name: "Position Security", symbol: "POS", currency_code: "EUR"})

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: securities_account.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-04-04],
        currency_code: "EUR",
        quantity: Decimal.new("8.00"),
        price: Decimal.new("10.00"),
        amount: Decimal.new("80.00")
      })

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: second_securities_account.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-04-05],
        currency_code: "EUR",
        quantity: Decimal.new("5.00"),
        price: Decimal.new("10.00"),
        amount: Decimal.new("50.00")
      })

    {:ok, view, _html} = live(conn, "/securities/#{security.id}")

    assert has_element?(view, "#security-position-list")
    assert has_element?(view, "#security-position-list", "Main Depot")
    assert has_element?(view, "#security-position-list", "Secondary depot")
    assert has_element?(view, "#security-position-list", "8")
    assert has_element?(view, "#security-position-list", "5")
  end

  test "does not include transactions from other securities", %{
    conn: conn,
    securities_account: securities_account,
    deposit_account: _deposit_account,
    portfolio: portfolio
  } do
    security = create_security(%{name: "Target Security", symbol: "TGT", currency_code: "EUR"})

    other_security =
      create_security(%{name: "Other Security", symbol: "OTH", currency_code: "EUR"})

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: securities_account.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-04-06],
        currency_code: "EUR",
        quantity: Decimal.new("3.00"),
        price: Decimal.new("10.00"),
        amount: Decimal.new("30.00"),
        notes: "Target note"
      })

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: securities_account.id,
        security_id: other_security.id,
        type: "buy",
        date: ~D[2026-04-07],
        currency_code: "EUR",
        quantity: Decimal.new("1.00"),
        price: Decimal.new("20.00"),
        amount: Decimal.new("20.00"),
        notes: "Other note"
      })

    create_quote(security.id, ~D[2026-04-06], "10.00")

    {:ok, view, _html} = live(conn, "/securities/#{security.id}")

    assert has_element?(view, "#security-transactions", "Target note")
    refute has_element?(view, "#security-transactions", "Other note")
    assert has_element?(view, "#security-chart-marker-0[data-notes='Target note']")
    refute has_element?(view, "#security-chart-marker-0[data-notes='Other note']")
  end

  test "filters chart markers by selected time range", %{
    conn: conn,
    securities_account: securities_account,
    portfolio: portfolio
  } do
    security = create_security(%{name: "Range Security", symbol: "RNG", currency_code: "EUR"})

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: securities_account.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-04-01],
        currency_code: "EUR",
        quantity: Decimal.new("1.00"),
        price: Decimal.new("10.00"),
        amount: Decimal.new("10.00"),
        notes: "outside range"
      })

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: securities_account.id,
        security_id: security.id,
        type: "sell",
        date: ~D[2026-04-10],
        currency_code: "EUR",
        quantity: Decimal.new("1.00"),
        price: Decimal.new("11.00"),
        amount: Decimal.new("11.00"),
        notes: "inside range"
      })

    create_quote(security.id, ~D[2026-04-01], "10.00")
    create_quote(security.id, ~D[2026-04-10], "11.00")

    {:ok, view, _html} =
      live(conn, "/securities/#{security.id}?from=2026-04-05&to=2026-04-20")

    assert has_element?(view, "#security-chart-marker-0[data-notes='inside range']")
    refute has_element?(view, "#security-chart-marker-0[data-notes='outside range']")
  end

  test "returns a clear not found message for unknown security id", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/securities/999999")

    assert has_element?(view, "#security-detail-not-found")
    assert has_element?(view, "#security-detail-not-found", "Security not found")
  end

  test "links security list rows to their detail pages", %{conn: conn} do
    security = create_security(%{name: "Linked Security", symbol: "LNK", currency_code: "EUR"})

    {:ok, view, _html} = live(conn, "/securities")

    assert has_element?(
             view,
             "#security-detail-link-#{security.id}[href=\"/securities/#{security.id}\"]"
           )

    expected_path = "/securities/#{security.id}"

    assert {:error, {:redirect, %{to: ^expected_path}}} =
             element(view, "#security-detail-link-#{security.id}") |> render_click()
  end

  test "shows attached fund documents for selected security", %{conn: conn} do
    security =
      create_security(%{
        name: "Fact Sheet Security",
        symbol: "FUND",
        currency_code: "EUR"
      })

    _other_security =
      create_security(%{
        name: "Other Security",
        symbol: "OTHER",
        currency_code: "EUR"
      })

    first_document =
      create_fund_document(
        security.id,
        original_filename: "factsheet_current.pdf",
        extraction_status: "extracted",
        extraction_error: nil
      )

    failed_document =
      create_fund_document(
        security.id,
        original_filename: "factsheet_failed.pdf",
        extraction_status: "failed",
        extraction_error: "Unable to read text"
      )

    {:ok, view, _html} = live(conn, "/securities/#{security.id}")

    assert has_element?(view, "#security-fund-documents")
    assert has_element?(view, "#security-fund-documents", "factsheet_current.pdf")
    assert has_element?(view, "#security-fund-documents", "factsheet_failed.pdf")
    assert has_element?(view, "#security-fund-documents", "factsheet")
    assert has_element?(view, "#security-fund-documents", "upload")
    assert has_element?(view, "#security-fund-documents", "application/pdf")
    assert has_element?(view, "#security-fund-documents", "extracted")
    assert has_element?(view, "#security-fund-documents", "failed")
    assert has_element?(view, "#security-fund-documents", "Unable to read text")

    assert has_element?(
             view,
             "#security-fund-documents a[href=\"/fund-documents/#{first_document.id}/allocations/review\"]"
           )

    assert has_element?(
             view,
             "#security-fund-documents a[href=\"/fund-documents/#{failed_document.id}/allocations/review\"]"
           )
  end

  test "does not show fund documents from other securities", %{conn: conn} do
    target_security =
      create_security(%{
        name: "Target Security",
        symbol: "TARGET",
        currency_code: "EUR"
      })

    other_security =
      create_security(%{
        name: "Security Owner",
        symbol: "OWNER",
        currency_code: "EUR"
      })

    create_fund_document(target_security.id, original_filename: "target_factsheet.pdf")

    other_document =
      create_fund_document(other_security.id, original_filename: "other_factsheet.pdf")

    {:ok, view, _html} = live(conn, "/securities/#{target_security.id}")

    assert has_element?(view, "#security-fund-documents", "target_factsheet.pdf")
    refute has_element?(view, "#security-fund-documents", other_document.original_filename)
  end

  test "shows empty state when security has no factsheets", %{conn: conn} do
    security = create_security(%{name: "Empty Factsheets", symbol: "EMPTY", currency_code: "EUR"})

    {:ok, view, _html} = live(conn, "/securities/#{security.id}")

    assert has_element?(view, "#security-fund-documents-empty-state")

    assert has_element?(
             view,
             "#security-fund-documents-empty-state",
             "No factsheets attached yet."
           )

    assert has_element?(view, "#security-fund-documents-empty-state a[href=\"/documents/new\"]")
  end

  test "renders stored quote chart and filters by range", %{conn: conn} do
    security = create_security(%{name: "Chart Security", symbol: "CHRT", currency_code: "EUR"})

    {:ok, _} =
      Catalog.create_security_quote(%{
        security_id: security.id,
        date: ~D[2025-01-15],
        source: "manual",
        currency_code: "EUR",
        close: Decimal.new("100")
      })

    {:ok, _} =
      Catalog.create_security_quote(%{
        security_id: security.id,
        date: ~D[2025-12-10],
        source: "manual",
        currency_code: "EUR",
        close: Decimal.new("120")
      })

    {:ok, view, _html} = live(conn, "/securities/#{security.id}")

    assert has_element?(
             view,
             "#security-price-chart[aria-labelledby='security-price-chart-title']"
           )

    assert has_element?(view, "#security-price-chart-title", "Price chart")
    assert has_element?(view, "#security-price-chart-svg")
    assert has_element?(view, "#security-price-range-all[aria-pressed=\"true\"]")
    assert has_element?(view, "#security-price-chart-series", "2025-01-15")
    assert has_element?(view, "#security-price-chart-series", "2025-12-10")

    view
    |> element("#security-price-range-1m")
    |> render_click()

    assert has_element?(view, "#security-price-range-1m[aria-pressed=\"true\"]")
    assert has_element?(view, "#security-price-range-all[aria-pressed=\"false\"]")
    refute has_element?(view, "#security-price-chart-series", "2025-01-15")
    assert has_element?(view, "#security-price-chart-series", "2025-12-10")
  end

  test "shows empty chart state when no quotes exist", %{conn: conn} do
    security = create_security(%{name: "No Quote Security", symbol: "NQ", currency_code: "EUR"})

    {:ok, view, _html} = live(conn, "/securities/#{security.id}")

    assert has_element?(
             view,
             "#security-price-chart[aria-labelledby='security-price-chart-title']"
           )

    assert has_element?(view, "#security-price-chart-title", "Price chart")
    assert has_element?(view, "#security-price-chart-empty")
    assert has_element?(view, "#security-price-chart-empty", "No quotes yet")
  end

  test "renders security detail without a current portfolio", %{conn: conn} do
    security =
      create_security(%{name: "Portfolio-less Security", symbol: "NOP", currency_code: "EUR"})

    Repo.delete_all(Transaction)
    Repo.delete_all(Portfolixir.Portfolios.SecuritiesAccount)
    Repo.delete_all(Portfolixir.Portfolios.DepositAccount)
    Repo.delete_all(Portfolixir.Portfolios.Portfolio)

    {:ok, view, _html} = live(conn, "/securities/#{security.id}?from=invalid-date")

    assert has_element?(view, "#no-security-positions")
    assert has_element?(view, "#no-security-positions", "No current position available")

    assert has_element?(
             view,
             "#no-security-positions",
             "Current position data is unavailable for this security."
           )

    refute has_element?(view, "#security-position-list")
    refute has_element?(view, "#no-security-positions", "No trades for this security")

    assert has_element?(view, "#no-security-transactions")
    assert has_element?(view, "#security-price-chart-empty")
  end

  test "renders deposit and withdrawal labels when a security-linked cash flow exists", %{
    conn: conn,
    deposit_account: deposit_account,
    portfolio: portfolio
  } do
    security = create_security(%{name: "Cashflow Security", symbol: "CASH", currency_code: "EUR"})

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        deposit_account_id: deposit_account.id,
        security_id: security.id,
        type: "deposit",
        date: ~D[2026-04-01],
        currency_code: "EUR",
        amount: Decimal.new("100.00"),
        notes: "Security-linked deposit"
      })

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        deposit_account_id: deposit_account.id,
        security_id: security.id,
        type: "withdrawal",
        date: ~D[2026-04-02],
        currency_code: "EUR",
        amount: Decimal.new("20.00"),
        notes: "Security-linked withdrawal"
      })

    create_quote(security.id, ~D[2026-04-01], "100.00")
    create_quote(security.id, ~D[2026-04-02], "101.00")

    {:ok, view, _html} = live(conn, "/securities/#{security.id}")

    assert has_element?(view, "#security-transactions", "Deposit")
    assert has_element?(view, "#security-transactions", "Withdrawal")
    assert has_element?(view, "#security-transactions", "Security-linked deposit")
    assert has_element?(view, "#security-transactions", "Security-linked withdrawal")
  end

  test "supports all quote range selectors and marker fallback without same-day quote", %{
    conn: conn,
    securities_account: securities_account,
    portfolio: portfolio
  } do
    security = create_security(%{name: "Range Matrix", symbol: "RMAX", currency_code: "EUR"})

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: securities_account.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-05-15],
        currency_code: "EUR",
        quantity: Decimal.new("1.00"),
        price: Decimal.new("11.00"),
        amount: Decimal.new("11.00"),
        notes: "marker without quote"
      })

    create_quote(security.id, ~D[2025-03-01], "90.00")
    create_quote(security.id, ~D[2025-10-01], "95.00")
    create_quote(security.id, ~D[2026-02-01], "100.00")
    create_quote(security.id, ~D[2026-04-01], "105.00")
    create_quote(security.id, ~D[2026-05-20], "110.00")

    {:ok, from_only_view, _html} = live(conn, "/securities/#{security.id}?from=2026-05-01")

    assert has_element?(
             from_only_view,
             "#security-chart-marker-0[data-notes='marker without quote']"
           )

    assert has_element?(from_only_view, "#security-chart-marker-0[cy='180.0']")

    {:ok, to_only_view, _html} = live(conn, "/securities/#{security.id}?to=2026-05-31")

    assert has_element?(
             to_only_view,
             "#security-chart-marker-0[data-notes='marker without quote']"
           )

    {:ok, view, _html} = live(conn, "/securities/#{security.id}")

    for selector <- [
          "#security-price-range-3m",
          "#security-price-range-6m",
          "#security-price-range-1y",
          "#security-price-range-ytd",
          "#security-price-range-all"
        ] do
      view
      |> element(selector)
      |> render_click()

      assert has_element?(view, "#{selector}[aria-pressed=\"true\"]")
      assert has_element?(view, "#security-price-range-1m[aria-pressed=\"false\"]")
      assert has_element?(view, "#security-price-chart-series")
    end
  end

  test "does not create allocations, allocation items, transactions, or quotes when viewing security detail",
       %{
         conn: conn
       } do
    security = create_security(%{name: "Read-only Security", symbol: "RO", currency_code: "EUR"})

    allocations_before = Repo.aggregate(FundAllocation, :count, :id)
    items_before = Repo.aggregate(FundAllocationItem, :count, :id)
    transactions_before = Repo.aggregate(Transaction, :count, :id)
    quotes_before = Repo.aggregate(Portfolixir.Catalog.SecurityQuote, :count, :id)

    {:ok, _view, _html} = live(conn, "/securities/#{security.id}")

    assert Repo.aggregate(FundAllocation, :count, :id) == allocations_before
    assert Repo.aggregate(FundAllocationItem, :count, :id) == items_before
    assert Repo.aggregate(Transaction, :count, :id) == transactions_before
    assert Repo.aggregate(Portfolixir.Catalog.SecurityQuote, :count, :id) == quotes_before
  end

  defp create_security(attrs) do
    {:ok, security} = Catalog.create_security(attrs)
    security
  end

  defp create_quote(security_id, date, close) do
    {:ok, _quote} =
      Catalog.create_security_quote(%{
        security_id: security_id,
        date: date,
        source: "manual",
        currency_code: "EUR",
        close: Decimal.new(close)
      })
  end

  defp create_import_source(attrs) do
    unique_name = "Factsheet source #{System.unique_integer([:positive, :monotonic])}"

    {:ok, source} =
      Imports.create_import_source(
        Map.merge(
          %{
            name: unique_name,
            type: "document_inbox"
          },
          Map.new(attrs)
        )
      )

    source
  end

  defp create_raw_import_item(attrs) do
    import_source = create_import_source([])
    content_hash = "sha256:#{System.unique_integer([:positive, :monotonic])}"
    normalized_attrs = Map.new(attrs)

    {:ok, item} =
      Imports.create_raw_import_item(
        Map.merge(
          %{
            import_source_id: import_source.id,
            content_hash: content_hash,
            content_type: "application/pdf",
            original_filename: "factsheet.pdf"
          },
          normalized_attrs
        )
      )

    item
  end

  defp create_fund_document(security_id, attrs) do
    content_hash = "sha256:#{System.unique_integer([:positive, :monotonic])}"
    normalized_attrs = Map.new(attrs)

    raw_item =
      create_raw_import_item(%{
        content_hash: content_hash,
        content_type: "application/pdf",
        original_filename: Map.get(normalized_attrs, :original_filename, "factsheet.pdf")
      })

    {:ok, fund_document} =
      Catalog.create_fund_document(
        Map.merge(
          %{
            security_id: security_id,
            raw_import_item_id: raw_item.id,
            document_type: "factsheet",
            source: "upload",
            original_filename: raw_item.original_filename,
            content_type: raw_item.content_type,
            content_hash: content_hash,
            extraction_status: "extracted",
            extraction_error: nil,
            metadata: %{}
          },
          normalized_attrs
        )
      )

    fund_document
  end

  defp create_deposit_account(attrs) do
    {:ok, account} =
      Portfolios.create_deposit_account(%{
        portfolio_id: attrs[:portfolio_id],
        name: attrs[:name],
        currency_code: "EUR"
      })

    account
  end

  defp create_securities_account(attrs) do
    {:ok, account} =
      Portfolios.create_securities_account(%{
        portfolio_id: attrs[:portfolio_id],
        reference_deposit_account_id: attrs[:reference_deposit_account_id],
        name: attrs[:name],
        currency_code: "EUR"
      })

    account
  end
end
