defmodule PortfolixirWeb.ImportConflictQueueLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Imports
  alias Portfolixir.Imports.{ImportConflict, ImportRun, ImportSource, RawImportItem}
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo

  test "conflict queue route renders explicit empty state", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/imports/conflicts")

    assert has_element?(view, "h1", "Import conflicts")
    assert has_element?(view, "#nav-imports.app-shell-nav-link.is-active")

    assert has_element?(
             view,
             "#import-conflicts-empty-state[role='status'][aria-live='polite'][aria-labelledby='import-conflicts-empty-state-title'][aria-describedby='import-conflicts-empty-state-description']"
           )

    assert has_element?(view, "#import-conflicts-empty-state-title", "No import conflicts queued")

    assert has_element?(
             view,
             "#import-conflicts-empty-state-description",
             "Open and resolved conflicts will appear here after import runs."
           )
  end

  test "open conflicts empty state has deterministic accessible region semantics", %{conn: conn} do
    source = create_import_source(name: "Resolved-only source")
    {:ok, run} = Imports.create_import_run(%{import_source_id: source.id, status: "finished"})

    {:ok, _resolved_conflict} =
      Imports.create_import_conflict(%{
        import_source_id: source.id,
        import_run_id: run.id,
        conflict_type: "duplicate_transaction",
        status: "resolved",
        summary: "Already resolved"
      })

    {:ok, view, _html} = live(conn, "/imports/conflicts")

    assert has_element?(
             view,
             "#import-conflicts-open-empty-state[role='region'][aria-labelledby='import-conflicts-open-empty-state-title']"
           )

    assert has_element?(view, "#import-conflicts-open-empty-state-title", "No open conflicts")
  end

  test "resolved conflicts empty state has deterministic accessible status semantics", %{
    conn: conn
  } do
    source = create_import_source(name: "Open-only source")
    {:ok, run} = Imports.create_import_run(%{import_source_id: source.id, status: "finished"})

    {:ok, _open_conflict} =
      Imports.create_import_conflict(%{
        import_source_id: source.id,
        import_run_id: run.id,
        conflict_type: "missing_security",
        summary: "Needs review"
      })

    {:ok, view, _html} = live(conn, "/imports/conflicts")

    assert has_element?(
             view,
             "#import-conflicts-resolved-empty-state[role='status'][aria-live='polite'][aria-labelledby='import-conflicts-resolved-empty-state-title'][aria-describedby='import-conflicts-resolved-empty-state-description']"
           )

    assert has_element?(
             view,
             "#import-conflicts-resolved-empty-state-title",
             "No resolved conflicts"
           )

    assert has_element?(
             view,
             "#import-conflicts-resolved-empty-state-description",
             "Historical conflicts that were already resolved."
           )
  end

  test "conflict queue groups open/resolved conflicts deterministically with review links", %{
    conn: conn
  } do
    source = create_import_source(name: "Conflicts source")
    {:ok, run} = Imports.create_import_run(%{import_source_id: source.id, status: "finished"})

    {:ok, raw_item} =
      Imports.create_raw_import_item(%{
        import_source_id: source.id,
        import_run_id: run.id,
        external_id: "conflict-raw-item"
      })

    {:ok, open_older} =
      Imports.create_import_conflict(%{
        import_source_id: source.id,
        import_run_id: run.id,
        conflict_type: "missing_security",
        summary: "Missing mapped security"
      })

    {:ok, open_newer} =
      Imports.create_import_conflict(%{
        import_source_id: source.id,
        import_run_id: run.id,
        raw_import_item_id: raw_item.id,
        conflict_type: "duplicate_transaction",
        summary: "Duplicate external transaction id"
      })

    {:ok, resolved_older} =
      Imports.create_import_conflict(%{
        import_source_id: source.id,
        import_run_id: run.id,
        conflict_type: "stale_position",
        status: "resolved",
        summary: "Position already closed"
      })

    {:ok, resolved_newer} =
      Imports.create_import_conflict(%{
        import_source_id: source.id,
        import_run_id: run.id,
        conflict_type: "duplicate_transaction",
        status: "resolved",
        summary: "Duplicate resolved"
      })

    {:ok, view, html} = live(conn, "/imports/conflicts")

    assert has_element?(view, "#import-conflicts-open-table")
    assert has_element?(view, "#import-conflicts-resolved-table")

    assert has_element?(
             view,
             "#import-conflicts-open-table[aria-describedby='import-conflicts-open-table-caption']"
           )

    assert has_element?(
             view,
             "#import-conflicts-open-table #import-conflicts-open-table-caption.app-shell-visually-hidden",
             "Open import conflicts table with source, run, type, summary, raised timestamp, and raw item review link."
           )

    assert has_element?(
             view,
             "#import-conflicts-resolved-table[aria-describedby='import-conflicts-resolved-table-caption']"
           )

    assert has_element?(
             view,
             "#import-conflicts-resolved-table #import-conflicts-resolved-table-caption.app-shell-visually-hidden",
             "Resolved import conflicts table with source, run, type, summary, raised timestamp, and raw item review link."
           )

    assert has_element?(view, "#import-conflict-open-row-#{open_newer.id}")
    assert has_element?(view, "#import-conflict-open-row-#{open_older.id}")
    assert has_element?(view, "#import-conflict-resolved-row-#{resolved_newer.id}")
    assert has_element?(view, "#import-conflict-resolved-row-#{resolved_older.id}")

    assert has_element?(
             view,
             "#import-conflict-review-link-#{open_newer.id}[href='/imports/raw-items/#{raw_item.id}/review']"
           )

    assert has_element?(view, "#import-conflict-no-review-link-#{open_older.id}", "—")

    assert row_offset(html, "import-conflict-open-row-#{open_newer.id}") <
             row_offset(html, "import-conflict-open-row-#{open_older.id}")

    assert row_offset(html, "import-conflict-resolved-row-#{resolved_newer.id}") <
             row_offset(html, "import-conflict-resolved-row-#{resolved_older.id}")
  end

  test "imports overview links to the conflict review queue", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/imports")

    assert has_element?(
             view,
             "#imports-conflicts-queue-link[href='/imports/conflicts']",
             "Open import conflict review queue"
           )
  end

  test "viewing /imports/conflicts performs no writes", %{conn: conn} do
    source = create_import_source(name: "Read-only source")
    {:ok, run} = Imports.create_import_run(%{import_source_id: source.id, status: "finished"})

    {:ok, _conflict} =
      Imports.create_import_conflict(%{
        import_source_id: source.id,
        import_run_id: run.id,
        conflict_type: "duplicate_transaction",
        summary: "Read-only queue conflict"
      })

    before_conflict_count = Repo.aggregate(ImportConflict, :count, :id)
    before_source_count = Repo.aggregate(ImportSource, :count, :id)
    before_run_count = Repo.aggregate(ImportRun, :count, :id)
    before_item_count = Repo.aggregate(RawImportItem, :count, :id)
    before_transaction_count = Repo.aggregate(Transaction, :count, :id)

    {:ok, _view, _html} = live(conn, "/imports/conflicts")

    assert Repo.aggregate(ImportConflict, :count, :id) == before_conflict_count
    assert Repo.aggregate(ImportSource, :count, :id) == before_source_count
    assert Repo.aggregate(ImportRun, :count, :id) == before_run_count
    assert Repo.aggregate(RawImportItem, :count, :id) == before_item_count
    assert Repo.aggregate(Transaction, :count, :id) == before_transaction_count
  end

  defp row_offset(html, row_id) do
    case :binary.match(html, row_id) do
      {position, _length} -> position
      :nomatch -> flunk("row id #{row_id} missing from html")
    end
  end

  defp create_import_source(attrs) do
    {:ok, source} =
      Imports.create_import_source(
        Map.merge(%{name: "Base source", type: "manual", status: "active"}, Map.new(attrs))
      )

    source
  end
end
