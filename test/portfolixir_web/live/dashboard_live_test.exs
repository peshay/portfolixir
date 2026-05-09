defmodule PortfolixirWeb.DashboardLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Catalog
  alias Portfolixir.Imports
  alias Portfolixir.Imports.{ImportRun, ImportSource, RawImportItem}
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios
  alias Portfolixir.Repo

  setup do
    Catalog.ensure_mvp_currencies!()
    :ok
  end

  test "root route renders the product dashboard", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(view, "h1", "Dashboard")
    assert has_element?(view, "#nav-dashboard.app-shell-nav-link.is-active")
    assert has_element?(view, "#dashboard-primary-action")
    assert has_element?(view, "#dashboard-portfolios-card")
    assert has_element?(view, "#dashboard-accounts-card")
    assert has_element?(view, "#dashboard-securities-card")
    assert has_element?(view, "#dashboard-transactions-card")
    assert has_element?(view, "#dashboard-mvp-path")
    assert has_element?(view, "#dashboard-chart-placeholder")
    refute has_element?(view, "#security-listing")
    refute has_element?(view, "h1", "All Securities")
    assert html =~ "Dashboard"
  end

  test "dashboard has exactly one visually dominant primary action when no data exists", %{
    conn: conn
  } do
    {:ok, view, html} = live(conn, "/")

    primary_action_matches =
      Regex.scan(
        ~r/id=\"dashboard-primary-action\"[^>]*class=\"[^\"]*app-shell-primary[^\"]*\"/,
        html
      )

    assert length(primary_action_matches) == 1
    assert has_element?(view, "#dashboard-primary-action", "Set up portfolio and accounts")
    assert has_element?(view, "#dashboard-primary-action[href=\"/accounts\"]")
    refute has_element?(view, "#dashboard-primary-action[href=\"/documents/new\"]")
  end

  test "dashboard empty state orders CTAs around the manual MVP path", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(view, "#dashboard-next-steps")
    assert has_element?(view, "#dashboard-next-step-link[href=\"/accounts\"]")
    assert has_element?(view, "#dashboard-primary-action[href=\"/accounts\"]")

    account_index = html_position!(html, "dashboard-mvp-step-accounts")
    securities_index = html_position!(html, "dashboard-mvp-step-securities")
    transactions_index = html_position!(html, "dashboard-mvp-step-transactions")
    reports_index = html_position!(html, "dashboard-mvp-step-reports")

    assert account_index < securities_index
    assert securities_index < transactions_index
    assert transactions_index < reports_index

    assert has_element?(view, "#dashboard-mvp-step-accounts[href=\"/accounts\"]")
    assert has_element?(view, "#dashboard-mvp-step-securities[href=\"/securities\"]")
    assert has_element?(view, "#dashboard-mvp-step-transactions[href=\"/transactions\"]")
    assert has_element?(view, "#dashboard-mvp-step-reports[href=\"/reports/fund-allocations\"]")
    refute has_element?(view, "#dashboard-next-step-link[href=\"/documents/new\"]")
  end

  test "dashboard advances next step from accounts to securities to transactions to reports", %{
    conn: conn
  } do
    accounts = create_mvp_accounts()

    {:ok, view, _html} = live(conn, "/")
    assert has_element?(view, "#dashboard-next-step-link[href=\"/securities\"]")
    assert has_element?(view, "#dashboard-primary-action", "Add your first security")

    security = create_security("NOWDOC")

    {:ok, view, _html} = live(conn, "/")
    assert has_element?(view, "#dashboard-next-step-link[href=\"/transactions\"]")
    assert has_element?(view, "#dashboard-primary-action", "Record a buy transaction")

    create_buy_transaction(accounts, security)

    {:ok, view, _html} = live(conn, "/")
    assert has_element?(view, "#dashboard-next-step-link[href=\"/reports/fund-allocations\"]")
    assert has_element?(view, "#dashboard-primary-action", "Review reports and charts")
  end

  test "dashboard keeps prompting for a buy transaction when only deposits exist", %{conn: conn} do
    accounts = create_mvp_accounts()
    _security = create_security("DEP-ONLY")
    create_deposit_transaction(accounts)

    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#dashboard-next-step-link[href=\"/transactions\"]")
    assert has_element?(view, "#dashboard-primary-action", "Record a buy transaction")
    refute has_element?(view, "#dashboard-primary-action", "Review reports and charts")
    assert Repo.aggregate(Transaction, :count, :id) == 1
  end

  test "dashboard recent import runs empty state has deterministic accessible status semantics",
       %{
         conn: conn
       } do
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(
             view,
             "#dashboard-recent-import-runs-empty-state[role='status'][aria-live='polite'][aria-labelledby='dashboard-recent-import-runs-empty-state-title'][aria-describedby='dashboard-recent-import-runs-empty-state-description']"
           )

    assert has_element?(
             view,
             "#dashboard-recent-import-runs-empty-state-title.app-shell-visually-hidden",
             "No import runs yet"
           )

    assert has_element?(
             view,
             "#dashboard-recent-import-runs-empty-state-description.app-shell-visually-hidden",
             "Optional import runs appear here when you test experimental import flows."
           )

    assert has_element?(
             view,
             "#dashboard-recent-import-runs-empty-state h3",
             "No import runs yet"
           )

    assert has_element?(
             view,
             "#dashboard-recent-import-runs-empty-state > p",
             "Optional import runs appear here when you test experimental import flows."
           )
  end

  test "dashboard recent fund documents empty state has deterministic accessible status semantics",
       %{
         conn: conn
       } do
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(
             view,
             "#dashboard-recent-fund-documents-empty-state[role='status'][aria-live='polite'][aria-labelledby='dashboard-recent-fund-documents-empty-state-status-title'][aria-describedby='dashboard-recent-fund-documents-empty-state-status-description']"
           )

    assert has_element?(
             view,
             "#dashboard-recent-fund-documents-empty-state-status-title.app-shell-visually-hidden",
             "No fund documents yet"
           )

    assert has_element?(
             view,
             "#dashboard-recent-fund-documents-empty-state-status-description.app-shell-visually-hidden",
             "Optional factsheet uploads appear here when you test experimental document flows."
           )

    assert has_element?(
             view,
             "#dashboard-recent-fund-documents-empty-state-title",
             "No fund documents yet"
           )

    assert has_element?(
             view,
             "#dashboard-recent-fund-documents-empty-state-description",
             "Optional factsheet uploads appear here when you test experimental document flows."
           )
  end

  test "dashboard shows recent import runs with source, status, timestamps, and import link", %{
    conn: conn
  } do
    source =
      create_import_source(
        name: "Dashboard import source",
        type: "document_inbox",
        status: "active"
      )

    {:ok, run} =
      Imports.create_import_run(%{
        import_source_id: source.id,
        status: "completed",
        started_at: ~U[2026-05-01 10:00:00Z],
        finished_at: ~U[2026-05-01 10:00:10Z]
      })

    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#dashboard-recent-import-runs")

    assert has_element?(
             view,
             "#dashboard-import-runs-table-caption.app-shell-visually-hidden",
             "Recent import runs with source, status, start time, and finish time."
           )

    assert has_element?(view, "#dashboard-import-runs-link[href=\"/imports\"]")
    assert has_element?(view, "#dashboard-import-run-row-#{run.id}")
    assert has_element?(view, "#dashboard-import-run-row-#{run.id}", source.name)
    assert has_element?(view, "#dashboard-import-run-row-#{run.id}", "completed")
    assert has_element?(view, "#dashboard-import-run-row-#{run.id}", "2026-05-01T10:00:00Z")
    assert has_element?(view, "#dashboard-import-run-row-#{run.id}", "2026-05-01T10:00:10Z")
  end

  test "dashboard shows recent fund documents with security, filename, status, and review link",
       %{conn: conn} do
    security = create_security("RECENT-FUND-DOC")

    {:ok, fund_document} =
      create_fund_document_for_security(security,
        original_filename: "dashboard-fund.pdf"
      )

    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#dashboard-recent-fund-documents")

    assert has_element?(
             view,
             "#dashboard-fund-documents-table-caption.app-shell-visually-hidden",
             "Recent fund documents with security, filename, extraction status, and review action."
           )

    assert has_element?(view, "#dashboard-fund-document-row-#{fund_document.id}")
    assert has_element?(view, "#dashboard-fund-document-row-#{fund_document.id}", security.name)
    assert has_element?(view, "#dashboard-fund-document-row-#{fund_document.id}", security.symbol)

    assert has_element?(
             view,
             "#dashboard-fund-document-row-#{fund_document.id}",
             "dashboard-fund.pdf"
           )

    assert has_element?(view, "#dashboard-fund-document-row-#{fund_document.id}", "extracted")

    assert has_element?(
             view,
             "#dashboard-fund-document-review-link-#{fund_document.id}[href=\"/fund-documents/#{fund_document.id}/allocations/review\"]"
           )
  end

  test "dashboard keeps import documents experimental and does not use them for MVP next step", %{
    conn: conn
  } do
    accounts = create_mvp_accounts()
    security = create_security("DASH-ALLOC")

    {:ok, first_doc} =
      create_fund_document_for_security(security,
        original_filename: "review-one.pdf"
      )

    {:ok, second_doc} =
      create_fund_document_for_security(security,
        original_filename: "review-two.pdf"
      )

    {:ok, _allocation} =
      Catalog.create_fund_allocation(%{
        security_id: security.id,
        source: "factsheet",
        allocation_type: "region"
      })

    create_buy_transaction(accounts, security)

    {:ok, view, _html} = live(conn, "/")

    latest_doc = if first_doc.id > second_doc.id, do: first_doc, else: second_doc
    factsheet_link = "/fund-documents/#{latest_doc.id}/allocations/review"

    assert has_element?(view, ~s(#dashboard-next-step-link[href="/reports/fund-allocations"]))
    refute has_element?(view, ~s(#dashboard-next-step-link[href="#{factsheet_link}"]))
    refute has_element?(view, ~s(#dashboard-next-step-link[href="/documents/new"]))

    assert has_element?(view, "#dashboard-experimental-activity")
    assert has_element?(view, "#dashboard-fund-document-review-link-#{latest_doc.id}")
  end

  test "manual MVP path can show a visible position without import records", %{conn: conn} do
    accounts = create_mvp_accounts()
    security = create_security("MVP-PATH")
    create_buy_transaction(accounts, security)

    {:ok, view, _html} = live(conn, "/securities")

    assert has_element?(view, "#security-list", "Dashboard MVP-PATH")
    assert has_element?(view, "#security-list", "MVP-PATH")
    assert has_element?(view, "#security-list", "1")

    assert Repo.aggregate(ImportSource, :count, :id) == 0
    assert Repo.aggregate(ImportRun, :count, :id) == 0
    assert Repo.aggregate(RawImportItem, :count, :id) == 0
  end

  test "dashboard does not render raw payloads and does not create records on read", %{conn: conn} do
    source =
      create_import_source(name: "Dashboard read-only", type: "connector", status: "active")

    {:ok, _run} =
      Imports.create_import_run(%{
        import_source_id: source.id,
        status: "completed",
        started_at: ~U[2026-05-01 10:00:00Z],
        finished_at: ~U[2026-05-01 10:00:10Z]
      })

    {:ok, _hidden_payload_item} =
      Imports.create_raw_import_item(%{
        import_source_id: source.id,
        external_id: "dash-raw-1",
        content_hash: "sha256:dash-raw-1",
        original_filename: "dashboard.csv",
        content_type: "text/csv",
        status: "new",
        payload: %{sensitive: "do-not-show", rows: ["one", "two"]}
      })

    security = create_security("READ-ONLY")

    {:ok, raw_document_item} =
      Imports.create_raw_import_item(%{
        import_source_id: source.id,
        external_id: "dash-doc-1",
        content_hash: "sha256:dash-doc-1",
        original_filename: "factsheet-dashboard.pdf",
        content_type: "application/pdf",
        status: "new",
        payload: %{source: "local_document_inbox"}
      })

    {:ok, _fund_doc} =
      Catalog.create_fund_document(%{
        security_id: security.id,
        raw_import_item_id: raw_document_item.id,
        document_type: "factsheet",
        source: "upload",
        original_filename: "factsheet-dashboard.pdf",
        content_type: "application/pdf",
        content_hash: "sha256:dashboard-doc-content",
        extraction_status: "extracted"
      })

    {:ok, _allocation} =
      Catalog.create_fund_allocation(%{
        security_id: security.id,
        source: "dashboard",
        allocation_type: "sector"
      })

    before_source_count = Repo.aggregate(ImportSource, :count, :id)
    before_run_count = Repo.aggregate(ImportRun, :count, :id)
    before_raw_item_count = Repo.aggregate(RawImportItem, :count, :id)
    before_fund_doc_count = Repo.aggregate(Catalog.FundDocument, :count, :id)
    before_allocation_count = Repo.aggregate(Catalog.FundAllocation, :count, :id)
    before_transaction_count = Repo.aggregate(Transaction, :count, :id)

    {:ok, view, _html} = live(conn, "/")

    assert Repo.aggregate(ImportSource, :count, :id) == before_source_count
    assert Repo.aggregate(ImportRun, :count, :id) == before_run_count
    assert Repo.aggregate(RawImportItem, :count, :id) == before_raw_item_count
    assert Repo.aggregate(Catalog.FundDocument, :count, :id) == before_fund_doc_count
    assert Repo.aggregate(Catalog.FundAllocation, :count, :id) == before_allocation_count
    assert Repo.aggregate(Transaction, :count, :id) == before_transaction_count

    assert render(view) =~ "Dashboard"
    refute render(view) =~ "do-not-show"
  end

  test "secondary routes still work from dashboard context", %{conn: conn} do
    {:ok, _view, _html} = live(conn, "/")

    {:ok, _view, html} = live(conn, "/imports")
    assert html =~ "Imports"

    {:ok, _view, html} = live(conn, "/documents/new")
    assert html =~ "No securities yet"

    {:ok, _view, html} = live(conn, "/securities")
    assert html =~ "All Securities"

    {:ok, _view, html} = live(conn, "/reports/fund-allocations")
    assert html =~ "Fund allocation report"
  end

  test "dashboard shows the chart placeholder and no fake value cards", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(
             view,
             "#dashboard-chart-placeholder[role='region'][aria-labelledby='dashboard-chart-placeholder-title'][aria-describedby='dashboard-chart-placeholder-description']"
           )

    assert has_element?(view, "#dashboard-chart-placeholder-title", "Portfolio value chart")

    assert has_element?(
             view,
             "#dashboard-chart-placeholder-description",
             "Portfolio value chart will appear here once valuations are available."
           )

    refute String.contains?(html, "P&L")
    refute String.contains?(html, "€")
    refute String.contains?(html, "$")
  end

  test "chart placeholder uses assistive-tech-only deterministic title and description ids", %{
    conn: conn
  } do
    conn = put_req_header(conn, "accept-language", "de-DE,de;q=0.9,en;q=0.8")

    {:ok, view, _html} = live(conn, "/")

    assert has_element?(
             view,
             "#dashboard-chart-placeholder[role='region'][aria-labelledby='dashboard-chart-placeholder-title'][aria-describedby='dashboard-chart-placeholder-description']"
           )

    assert has_element?(
             view,
             "#dashboard-chart-placeholder > span#dashboard-chart-placeholder-title.app-shell-visually-hidden"
           )

    assert has_element?(
             view,
             "#dashboard-chart-placeholder > span#dashboard-chart-placeholder-description.app-shell-visually-hidden"
           )

    refute has_element?(
             view,
             "#dashboard-chart-placeholder > h2#dashboard-chart-placeholder-title"
           )

    refute has_element?(
             view,
             "#dashboard-chart-placeholder > p#dashboard-chart-placeholder-description"
           )
  end

  test "German locale renders translated dashboard action and placeholder", %{conn: conn} do
    conn = put_req_header(conn, "accept-language", "de-DE,de;q=0.9,en;q=0.8")

    {:ok, _view, html} = live(conn, "/")

    assert html =~ "Portfolio und Konten einrichten"
    assert html =~ "Der Portfolio-Wert-Chart erscheint hier, sobald Bewertungen verfügbar sind."
  end

  defp create_mvp_accounts do
    {:ok, portfolio} =
      Portfolios.create_portfolio(%{name: "Main portfolio", base_currency_code: "EUR"})

    {:ok, deposit_account} =
      Portfolios.create_deposit_account(%{
        portfolio_id: portfolio.id,
        name: "Settlement cash",
        currency_code: "EUR"
      })

    {:ok, securities_account} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        reference_deposit_account_id: deposit_account.id,
        name: "Main depot",
        currency_code: "EUR"
      })

    %{
      portfolio: portfolio,
      deposit_account: deposit_account,
      securities_account: securities_account
    }
  end

  defp create_buy_transaction(accounts, security) do
    {:ok, transaction} =
      Ledger.create_transaction(%{
        portfolio_id: accounts.portfolio.id,
        type: "buy",
        date: ~D[2026-05-09],
        currency_code: "EUR",
        amount: Decimal.new("42"),
        quantity: Decimal.new("1"),
        price: Decimal.new("42"),
        securities_account_id: accounts.securities_account.id,
        deposit_account_id: accounts.deposit_account.id,
        security_id: security.id
      })

    transaction
  end

  defp create_deposit_transaction(accounts) do
    {:ok, transaction} =
      Ledger.create_transaction(%{
        portfolio_id: accounts.portfolio.id,
        type: "deposit",
        date: ~D[2026-05-09],
        currency_code: "EUR",
        amount: Decimal.new("42"),
        deposit_account_id: accounts.deposit_account.id
      })

    transaction
  end

  defp html_position!(html, marker) do
    {position, _length} = :binary.match(html, marker)
    position
  end

  defp create_import_source(attrs) do
    base_attrs = %{name: "Base source", type: "manual"}

    {:ok, source} =
      Imports.create_import_source(Map.merge(base_attrs, Map.new(attrs)))

    source
  end

  defp create_security(symbol) do
    {:ok, security} =
      Catalog.create_security(%{
        name: "Dashboard #{symbol}",
        symbol: symbol,
        currency_code: "EUR"
      })

    security
  end

  defp create_raw_import_item(security_id, original_filename) do
    source =
      create_import_source(name: "Raw import source #{security_id}", type: "document_inbox")

    unique_suffix = :erlang.unique_integer([:positive, :monotonic])

    {:ok, item} =
      Imports.create_raw_import_item(%{
        import_source_id: source.id,
        external_id: "dashboard-raw-#{security_id}-#{unique_suffix}",
        content_hash: "sha256:dashboard-raw-#{security_id}-#{unique_suffix}",
        original_filename: original_filename,
        content_type: "application/pdf",
        status: "new"
      })

    item
  end

  defp create_fund_document_for_security(security, opts) do
    filename = Keyword.fetch!(opts, :original_filename)
    raw_import_item = create_raw_import_item(security.id, filename)
    unique_suffix = :erlang.unique_integer([:positive, :monotonic])

    Catalog.create_fund_document(%{
      security_id: security.id,
      raw_import_item_id: raw_import_item.id,
      document_type: "factsheet",
      source: "upload",
      original_filename: filename,
      content_type: "application/pdf",
      content_hash: "sha256:#{security.symbol}-#{filename}-#{unique_suffix}",
      extraction_status: "extracted"
    })
  end
end
