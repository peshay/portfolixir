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

    assert has_element?(
             view,
             "#raw-import-item-review-metadata-table-caption.app-shell-visually-hidden",
             "Raw import item metadata with source, status, identifiers, content details, and created timestamp"
           )

    assert has_element?(view, "#raw-import-item-review", "Connector source")
    assert has_element?(view, "#raw-import-item-review", "raw-connector-1")
    assert has_element?(view, "#raw-import-item-review", "sha256:abc")
    assert has_element?(view, "#raw-import-item-review", "application/json")
    assert has_element?(view, "#raw-import-item-review", "import.json")
    assert has_element?(view, "#raw-import-item-review", "2026")

    assert has_element?(
             view,
             "#raw-import-item-payload-preview-title",
             "Sanitized payload preview"
           )

    assert has_element?(view, "#raw-import-item-payload-preview", "field_count: 3")
    assert has_element?(view, "#raw-import-item-payload-preview", "string_fields: 3")
    refute html =~ "must-not-render"
    refute html =~ "source: connector"
    refute html =~ "record_type: transaction"
  end

  test "review page shows accessible not found state for unknown raw item", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/imports/raw-items/999999/review")

    assert has_element?(
             view,
             "#raw-import-item-not-found[role='status'][aria-labelledby='raw-import-item-not-found-title'][aria-describedby='raw-import-item-not-found-description']"
           )

    assert has_element?(view, "#raw-import-item-not-found-title", "Raw import item not found")

    assert has_element?(
             view,
             "#raw-import-item-not-found-description",
             "The requested raw import item does not exist."
           )
  end

  test "review page shows accessible not found state for invalid raw item id", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/imports/raw-items/not-a-number/review")

    assert has_element?(
             view,
             "#raw-import-item-not-found[role='status'][aria-labelledby='raw-import-item-not-found-title'][aria-describedby='raw-import-item-not-found-description']"
           )

    assert has_element?(view, "#raw-import-item-not-found-title", "Raw import item not found")

    assert has_element?(
             view,
             "#raw-import-item-not-found-description",
             "The requested raw import item does not exist."
           )
  end

  test "review page summarizes mixed payload value types", %{conn: conn} do
    source = create_import_source(name: "Mixed payload source", type: "manual", status: "active")

    {:ok, raw_item} =
      Imports.create_raw_import_item(%{
        import_source_id: source.id,
        external_id: "mixed-payload-item",
        status: "new",
        payload: %{
          "symbol" => "ABC",
          "weight" => 12.5,
          "active" => true,
          "nullable" => nil,
          "regions" => ["eu"],
          "meta" => %{"sector" => "tech"}
        }
      })

    {:ok, view, _html} = live(conn, "/imports/raw-items/#{raw_item.id}/review")

    assert has_element?(view, "#raw-import-item-payload-preview", "field_count: 6")
    assert has_element?(view, "#raw-import-item-payload-preview", "string_fields: 1")
    assert has_element?(view, "#raw-import-item-payload-preview", "number_fields: 1")
    assert has_element?(view, "#raw-import-item-payload-preview", "boolean_fields: 1")
    assert has_element?(view, "#raw-import-item-payload-preview", "null_fields: 1")
    assert has_element?(view, "#raw-import-item-payload-preview", "list_fields: 1")
    assert has_element?(view, "#raw-import-item-payload-preview", "map_fields: 1")
    assert has_element?(view, "#raw-import-item-payload-preview", "other_fields: 0")
  end

  test "review page shows accessible empty preview state when payload is not a map", %{conn: conn} do
    source = create_import_source(name: "No preview source", type: "manual", status: "active")

    {:ok, raw_item} =
      Imports.create_raw_import_item(%{
        import_source_id: source.id,
        external_id: "string-payload-item",
        status: "new",
        payload: nil
      })

    {:ok, view, _html} = live(conn, "/imports/raw-items/#{raw_item.id}/review")

    assert has_element?(
             view,
             "#raw-import-item-payload-preview-title",
             "Sanitized payload preview"
           )

    assert has_element?(
             view,
             "#raw-import-item-payload-preview [role='status'][aria-labelledby='raw-import-item-payload-preview-title'][aria-describedby='raw-import-item-payload-preview-no-preview-description']"
           )

    assert has_element?(
             view,
             "#raw-import-item-payload-preview-no-preview-description",
             "No safe compact payload preview is available for this item."
           )
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
