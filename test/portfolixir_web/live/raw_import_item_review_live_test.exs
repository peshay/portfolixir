defmodule PortfolixirWeb.RawImportItemReviewLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Imports
  alias Portfolixir.Imports.{ImportRun, ImportSource, RawImportItem}
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo

  test "review page renders safe metadata and sanitized payload preview", %{conn: conn} do
    source = create_import_source(name: "Connector source", type: "connector", status: "active")

    {:ok, raw_item} =
      Imports.create_raw_import_item(%{
        import_source_id: source.id,
        external_id: "raw-connector-1",
        content_hash: "sha256:abc",
        original_filename: "import.json",
        content_type: "application/json",
        status: "new",
        payload: %{
          "source" => "connector",
          "record_type" => "transaction",
          "content" => "must-not-render"
        }
      })

    {:ok, view, html} = live(conn, "/imports/raw-items/#{raw_item.id}/review")

    assert has_element?(view, "#raw-import-item-review-metadata-table")
    assert has_element?(view, "#raw-import-item-review", "Connector source")
    assert has_element?(view, "#raw-import-item-review", "raw-connector-1")
    assert has_element?(view, "#raw-import-item-review", "sha256:abc")
    assert has_element?(view, "#raw-import-item-review", "application/json")
    assert has_element?(view, "#raw-import-item-review", "import.json")
    assert has_element?(view, "#raw-import-item-review", "2026")
    assert has_element?(view, "#raw-import-item-payload-preview", "source: connector")
    assert has_element?(view, "#raw-import-item-payload-preview", "record_type: transaction")
    refute html =~ "must-not-render"
  end

  test "review page shows explicit not found for unknown raw item", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/imports/raw-items/999999/review")

    assert has_element?(view, "#raw-import-item-not-found", "Raw import item not found")
  end

  test "imports overview links raw item rows to review page", %{conn: conn} do
    source = create_import_source(name: "Review source", type: "manual", status: "active")

    {:ok, raw_item} =
      Imports.create_raw_import_item(%{
        import_source_id: source.id,
        external_id: "review-item",
        status: "new"
      })

    {:ok, view, _html} = live(conn, "/imports")

    assert has_element?(
             view,
             "#import-raw-item-review-link-#{raw_item.id}[href='/imports/raw-items/#{raw_item.id}/review']"
           )
  end

  test "viewing raw import review page performs no writes", %{conn: conn} do
    source = create_import_source(name: "Read-only source", type: "manual", status: "active")

    {:ok, _run} =
      Imports.create_import_run(%{
        import_source_id: source.id,
        status: "finished"
      })

    {:ok, raw_item} =
      Imports.create_raw_import_item(%{
        import_source_id: source.id,
        external_id: "read-only-review-item",
        status: "new"
      })

    before_source_count = Repo.aggregate(ImportSource, :count, :id)
    before_run_count = Repo.aggregate(ImportRun, :count, :id)
    before_item_count = Repo.aggregate(RawImportItem, :count, :id)
    before_transaction_count = Repo.aggregate(Transaction, :count, :id)

    {:ok, _view, _html} = live(conn, "/imports/raw-items/#{raw_item.id}/review")

    assert Repo.aggregate(ImportSource, :count, :id) == before_source_count
    assert Repo.aggregate(ImportRun, :count, :id) == before_run_count
    assert Repo.aggregate(RawImportItem, :count, :id) == before_item_count
    assert Repo.aggregate(Transaction, :count, :id) == before_transaction_count
  end

  defp create_import_source(attrs) do
    {:ok, source} =
      Imports.create_import_source(
        Map.merge(%{name: "Base source", type: "manual", status: "active"}, Map.new(attrs))
      )

    source
  end
end
