defmodule PortfolixirWeb.DashboardLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Catalog
  alias Portfolixir.Imports
  alias Portfolixir.Imports.{ImportRun, ImportSource, RawImportItem}
  alias Portfolixir.Ledger.Transaction
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
    assert has_element?(view, "#dashboard-securities-card")
    assert has_element?(view, "#dashboard-transactions-card")
    assert has_element?(view, "#dashboard-imports-card")
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
    assert has_element?(view, "#dashboard-primary-action", "Import portfolio data")
    refute has_element?(view, "#dashboard-primary-action[href=\"/documents/new\"]")
  end

  test "dashboard no-security state links primary action and next step to /securities", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#dashboard-next-steps")
    assert has_element?(view, "#dashboard-next-step-link[href=\"/securities\"]")
    assert has_element?(view, "#dashboard-primary-action[href=\"/securities\"]")
  end

  test "dashboard with securities but no fund documents links next step to /documents/new", %{
    conn: conn
  } do
    {:ok, _security} =
      Catalog.create_security(%{
        name: "Security without factsheet",
        symbol: "NOWDOC",
        currency_code: "EUR"
      })

    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#dashboard-primary-action", "Add document")
    assert has_element?(view, "#dashboard-primary-action[href=\"/documents/new\"]")
    assert has_element?(view, "#dashboard-next-step-link[href=\"/documents/new\"]")
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
             "#dashboard-recent-import-runs-empty-state-title",
             "No import runs yet"
           )

    assert has_element?(
             view,
             "#dashboard-recent-import-runs-empty-state-description",
             "Run imports to build recent activity here."
           )
  end

  test "dashboard recent fund documents empty state has deterministic accessible status semantics",
       %{
         conn: conn
       } do
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(
             view,
             "#dashboard-recent-fund-documents-empty-state[role='status'][aria-live='polite'][aria-labelledby='dashboard-recent-fund-documents-empty-state-title'][aria-describedby='dashboard-recent-fund-documents-empty-state-description']"
           )

    assert has_element?(
             view,
             "#dashboard-recent-fund-documents-empty-state-title",
             "No fund documents yet"
           )

    assert has_element?(
             view,
             "#dashboard-recent-fund-documents-empty-state-description",
             "Upload a factsheet to populate this list."
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

  test "dashboard points next step to latest factsheet review if no allocations exist", %{
    conn: conn
  } do
    security = create_security("DASH-NO-ALLOC")

    {:ok, first_doc} =
      create_fund_document_for_security(security,
        original_filename: "review-one.pdf"
      )

    {:ok, second_doc} =
      create_fund_document_for_security(security,
        original_filename: "review-two.pdf"
      )

    {:ok, view, _html} = live(conn, "/")

    latest_doc = if first_doc.id > second_doc.id, do: first_doc, else: second_doc
    expected_link = "/fund-documents/#{latest_doc.id}/allocations/review"

    assert has_element?(view, "#dashboard-next-step-link[href=\"#{expected_link}\"]")
  end

  test "dashboard points next step to allocations report when fund allocations exist", %{
    conn: conn
  } do
    security = create_security("DASH-ALLOC")

    {:ok, _fund_document} =
      create_fund_document_for_security(security,
        original_filename: "seed-factsheet.pdf"
      )

    {:ok, _allocation} =
      Catalog.create_fund_allocation(%{
        security_id: security.id,
        source: "factsheet",
        allocation_type: "region"
      })

    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#dashboard-next-step-link[href=\"/reports/fund-allocations\"]")
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

  test "German locale renders translated dashboard action and placeholder", %{conn: conn} do
    conn = put_req_header(conn, "accept-language", "de-DE,de;q=0.9,en;q=0.8")

    {:ok, _view, html} = live(conn, "/")

    assert html =~ "Portfoliodaten importieren"
    assert html =~ "Der Portfolio-Wert-Chart erscheint hier, sobald Bewertungen verfügbar sind."
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
