defmodule PortfolixirWeb.ImportOverviewLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Imports
  alias Portfolixir.Imports.{ImportRun, ImportSource, RawImportItem}
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo

  test "imports route renders source, run, and raw item sections", %{conn: conn} do
    {:ok, view, html} = live(conn, "/imports")

    assert has_element?(view, "h1", "Imports")
    assert has_element?(view, "#nav-imports.app-shell-nav-link.is-active")
    assert has_element?(view, "#import-sources-section")
    assert has_element?(view, "#recent-import-runs-section")
    assert has_element?(view, "#recent-raw-import-items-section")
    assert has_element?(view, "#import-sources-empty-state")
    assert has_element?(view, "#import-runs-empty-state")
    assert has_element?(view, "#import-raw-items-empty-state")
    assert has_element?(view, "a[href=\"/imports\"]")
    assert has_element?(view, "#imports-conflicts-queue-link[href=\"/imports/conflicts\"]")
    assert html =~ "/imports"
  end

  test "import sources empty state has deterministic accessible status semantics", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/imports")

    assert has_element?(
             view,
             "#import-sources-empty-state[role='status'][aria-live='polite'][aria-labelledby='import-sources-empty-state-a11y-title'][aria-describedby='import-sources-empty-state-a11y-description']"
           )

    assert has_element?(
             view,
             "#import-sources-empty-state-a11y-title.app-shell-visually-hidden",
             "No import sources yet"
           )

    assert has_element?(
             view,
             "#import-sources-empty-state-a11y-description.app-shell-visually-hidden",
             "Create or register import sources to see them here."
           )

    assert has_element?(view, "#import-sources-empty-state h3", "No import sources yet")

    assert has_element?(
             view,
             "#import-sources-empty-state p",
             "Create or register import sources to see them here."
           )
  end

  test "import runs empty state has deterministic accessible status semantics", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/imports")

    assert has_element?(
             view,
             "#import-runs-empty-state[role='status'][aria-live='polite'][aria-labelledby='import-runs-empty-state-title'][aria-describedby='import-runs-empty-state-description']"
           )

    assert has_element?(view, "#import-runs-empty-state-title", "No import runs yet")

    assert has_element?(
             view,
             "#import-runs-empty-state-description",
             "Runs will appear here after source execution."
           )
  end

  test "raw import items empty state has deterministic accessible status semantics", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/imports")

    assert has_element?(
             view,
             "#import-raw-items-empty-state[role='status'][aria-live='polite'][aria-labelledby='import-raw-items-empty-state-title'][aria-describedby='import-raw-items-empty-state-description']"
           )

    assert has_element?(view, "#import-raw-items-empty-state-title", "No raw import items yet")

    assert has_element?(
             view,
             "#import-raw-items-empty-state-description",
             "Raw items will appear here after intake."
           )
  end

  test "imports sidebar item links to /imports", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "#nav-imports[href=\"/imports\"]")
  end

  test "imports shows configured sources with counts and latest run status", %{conn: conn} do
    source = create_import_source(name: "File ingest", type: "connector", status: "active")

    {:ok, _} =
      Imports.create_import_run(%{
        import_source_id: source.id,
        status: "finished",
        started_at: ~U[2026-05-01 09:00:00Z],
        finished_at: ~U[2026-05-01 09:00:10Z]
      })

    {:ok, _} =
      Imports.create_import_run(%{
        import_source_id: source.id,
        status: "completed",
        started_at: ~U[2026-05-01 10:00:00Z],
        finished_at: ~U[2026-05-01 10:00:10Z]
      })

    {:ok, _} =
      Imports.create_raw_import_item(%{
        import_source_id: source.id,
        external_id: "source-item-1",
        content_hash: "sha256:source-item-1",
        original_filename: "import.json",
        content_type: "application/json",
        status: "new"
      })

    {:ok, view, html} = live(conn, "/imports")

    assert has_element?(
             view,
             "#import-sources-table[aria-describedby=\"import-sources-table-caption\"]"
           )

    assert has_element?(
             view,
             "#import-sources-table #import-sources-table-caption.app-shell-visually-hidden",
             "Import sources with status, run counts, and latest run timestamps"
           )

    assert has_element?(view, "#import-source-row-#{source.id}")
    assert has_element?(view, "#import-source-row-#{source.id}", "File ingest")
    assert has_element?(view, "#import-source-row-#{source.id}", "connector")
    assert has_element?(view, "#import-source-row-#{source.id}", "active")
    assert has_element?(view, "#import-source-row-#{source.id}", "2")
    assert has_element?(view, "#import-source-row-#{source.id}", "1")
    assert has_element?(view, "#import-source-row-#{source.id}", "completed")
    assert has_element?(view, "#import-source-row-#{source.id}", "2026-05-01T10:00:00Z")
    assert has_element?(view, "#import-source-row-#{source.id}", "2026-05-01T10:00:10Z")
    refute has_element?(view, "#import-sources-empty-state")

    # latest run columns are present in the rendered row
    assert html =~ "Latest run status"
    assert html =~ "Latest run started"
    assert html =~ "Latest run finished"
  end

  test "imports shows recent import runs with summary preview", %{conn: conn} do
    source =
      create_import_source(name: "Document inbox", type: "document_inbox", status: "active")

    {:ok, _} =
      Imports.create_import_run(%{
        import_source_id: source.id,
        status: "completed",
        started_at: ~U[2026-05-01 10:00:00Z],
        finished_at: ~U[2026-05-01 10:00:10Z],
        summary: %{"created" => 2, "updated" => 1, "warnings" => %{"count" => 1}}
      })

    {:ok, _} =
      Imports.create_import_run(%{
        import_source_id: source.id,
        status: "failed",
        started_at: ~U[2026-05-01 09:00:00Z],
        finished_at: ~U[2026-05-01 09:00:10Z],
        summary: %{"created" => 1}
      })

    {:ok, view, _html} = live(conn, "/imports")

    run_rows = Imports.list_recent_import_runs(2) |> Enum.map(& &1.id)
    [latest_run_id | _] = run_rows

    assert has_element?(
             view,
             "#import-runs-table[aria-describedby='import-runs-table-caption']"
           )

    assert has_element?(
             view,
             "#import-runs-table #import-runs-table-caption.app-shell-visually-hidden",
             "Recent import runs with source, status, timestamps, and summary preview"
           )

    assert has_element?(view, "#import-run-row-#{latest_run_id}")
    assert has_element?(view, "#import-run-row-#{latest_run_id}", "Document inbox")
    assert has_element?(view, "#import-run-row-#{latest_run_id}", "completed")
    assert has_element?(view, "#import-run-row-#{latest_run_id}", "2026-05-01T10:00:00Z")
    assert has_element?(view, "#import-run-row-#{latest_run_id}", "2026-05-01T10:00:10Z")
    assert has_element?(view, "#import-run-row-#{latest_run_id}", "created=2")
    assert has_element?(view, "#import-run-row-#{latest_run_id}", "updated=1")
    assert has_element?(view, "#import-run-row-#{latest_run_id}", "warnings=map(1)")
    assert has_element?(view, "#import-runs-empty-state") == false
  end

  test "imports shows recent raw import items with metadata and no payload", %{conn: conn} do
    source = create_import_source(name: "File source", type: "document_inbox", status: "active")

    {:ok, _} =
      Imports.create_raw_import_item(%{
        import_source_id: source.id,
        external_id: "ext-raw-1",
        content_hash: "sha256:raw-one",
        original_filename: "transactions.csv",
        content_type: "text/csv",
        status: "new",
        payload: %{
          "sensitive" => "do-not-show",
          "lines" => ["one", "two"]
        }
      })

    {:ok, view, html} = live(conn, "/imports")

    raw_item = hd(Imports.list_recent_raw_import_items(1))

    assert has_element?(view, "#import-raw-items-table")

    assert has_element?(
             view,
             "#import-raw-items-table caption.app-shell-visually-hidden",
             "Recent raw import items with source, metadata, status, and review links"
           )

    assert has_element?(view, "#import-raw-item-row-#{raw_item.id}")
    assert has_element?(view, "#import-raw-item-row-#{raw_item.id}", "File source")
    assert has_element?(view, "#import-raw-item-row-#{raw_item.id}", "transactions.csv")
    assert has_element?(view, "#import-raw-item-row-#{raw_item.id}", "text/csv")
    assert has_element?(view, "#import-raw-item-row-#{raw_item.id}", "ext-raw-1")
    assert has_element?(view, "#import-raw-item-row-#{raw_item.id}", "sha256:raw-one")
    assert has_element?(view, "#import-raw-item-row-#{raw_item.id}", "new")
    assert has_element?(view, "#import-raw-items-empty-state") == false
    refute String.contains?(html, "do-not-show")
  end

  test "viewing /imports performs no writes across import and ledger tables", %{conn: conn} do
    source =
      create_import_source(name: "Read-only source", type: "document_inbox", status: "active")

    {:ok, _} =
      Imports.create_import_run(%{
        import_source_id: source.id,
        status: "started"
      })

    {:ok, _} =
      Imports.create_raw_import_item(%{
        import_source_id: source.id,
        external_id: "read-only-item",
        status: "new"
      })

    before_source_count = Repo.aggregate(ImportSource, :count, :id)
    before_run_count = Repo.aggregate(ImportRun, :count, :id)
    before_item_count = Repo.aggregate(RawImportItem, :count, :id)
    before_transaction_count = Repo.aggregate(Transaction, :count, :id)

    {:ok, _view, _html} = live(conn, "/imports")

    assert Repo.aggregate(ImportSource, :count, :id) == before_source_count
    assert Repo.aggregate(ImportRun, :count, :id) == before_run_count
    assert Repo.aggregate(RawImportItem, :count, :id) == before_item_count
    assert Repo.aggregate(Transaction, :count, :id) == before_transaction_count
  end

  test "existing dashboard, securities, documents, and reports routes still render while imports route is added",
       %{conn: conn} do
    {:ok, _view, _html} = live(conn, "/")
    {:ok, _view, _html} = live(conn, "/securities")
    {:ok, _view, _html} = live(conn, "/documents/new")
    {:ok, _view, _html} = live(conn, "/reports/fund-allocations")
    {:ok, _view, html} = live(conn, "/imports")

    assert has_element?(live(conn, "/") |> elem(1), "h1", "Dashboard")
    assert has_element?(live(conn, "/securities") |> elem(1), "h1", "All Securities")
    assert has_element?(live(conn, "/documents/new") |> elem(1), "h1", "Factsheet document")

    assert has_element?(
             live(conn, "/reports/fund-allocations") |> elem(1),
             "h1",
             "Fund allocation report"
           )

    assert has_element?(_view, "#nav-imports[href=\"/imports\"].is-active")
  end

  defp create_import_source(attrs) do
    base_attrs = %{name: "Base source", type: "manual"}

    {:ok, source} = Imports.create_import_source(Map.merge(base_attrs, Map.new(attrs)))
    source
  end
end
