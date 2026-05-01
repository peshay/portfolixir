defmodule PortfolixirWeb.FactsheetAllocationReviewLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.FactsheetDocuments
  alias Portfolixir.Catalog.{FundAllocation, FundAllocationItem}
  alias Portfolixir.Catalog.SecurityCategoryAssignment
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo
  alias Portfolixir.Taxonomies.Category

  setup do
    Catalog.ensure_mvp_currencies!()
    :ok
  end

  @fixture_text """
  Regions
  North America 62.5%
  Europe 18.3%
  Asia Pacific 12.2%

  Countries
  United States 58.1%
  Germany 5.2%
  """

  @single_region_text """
  Regions
  North America 62.5%
  Europe 18.3%
  """

  test "review page renders factsheet metadata and parsed allocation rows", %{conn: conn} do
    security = create_security("FACTSHEET-REVIEW-META")

    assert {:ok, :created, fund_document} =
             FactsheetDocuments.register_factsheet(
               security.id,
               "factsheet.pdf",
               "application/pdf",
               "PDF-LIKE\nFACTSHEET_TEXT:#{@fixture_text}\nEOF"
             )

    {:ok, view, _html} =
      live(conn, "/fund-documents/#{fund_document.id}/allocations/review")

    assert has_element?(view, "#factsheet-review-security", security.name)
    assert has_element?(view, "#factsheet-review-filename", "factsheet.pdf")
    assert has_element?(view, "#factsheet-review-status", "extracted")
    assert has_element?(view, "#factsheet-allocation-item-region-north-america", "North America")
    assert has_element?(view, "#factsheet-allocation-item-region-north-america", "62.5%")
    assert has_element?(view, "#factsheet-allocation-item-region-north-america", "1")

    assert has_element?(
             view,
             "#factsheet-allocation-item-region-north-america",
             "North America 62.5%"
           )
  end

  test "review page renders preview warnings", %{conn: conn} do
    security = create_security("FACTSHEET-REVIEW-WARN")

    assert {:ok, :created, fund_document} =
             FactsheetDocuments.register_factsheet(
               security.id,
               "factsheet.pdf",
               "application/pdf",
               """
               PDF-LIKE
               FACTSHEET_TEXT:
               Regions
               North America 62.5%
               not parseable row
               Europe 18.3%
               EOF
               """
             )

    {:ok, view, html} = live(conn, "/fund-documents/#{fund_document.id}/allocations/review")

    assert html =~ "Could not parse allocation line"
    assert has_element?(view, "#factsheet-review-warnings-list")
  end

  test "review page shows empty state when no allocation rows are parsed", %{conn: conn} do
    security = create_security("FACTSHEET-REVIEW-EMPTY")

    assert {:ok, :created, fund_document} =
             FactsheetDocuments.register_factsheet(
               security.id,
               "factsheet.pdf",
               "application/pdf",
               "PDF-LIKE\nFACTSHEET_TEXT:EOF"
             )

    {:ok, view, _html} = live(conn, "/fund-documents/#{fund_document.id}/allocations/review")

    assert has_element?(view, "#factsheet-review-empty-state")
    assert has_element?(view, "#factsheet-review-confirm-button[disabled]")
  end

  test "confirm persists allocations and items through existing import service", %{conn: conn} do
    security = create_security("FACTSHEET-REVIEW-CONFIRM")

    assert {:ok, :created, fund_document} =
             FactsheetDocuments.register_factsheet(
               security.id,
               "factsheet.pdf",
               "application/pdf",
               "PDF-LIKE\nFACTSHEET_TEXT:#{@single_region_text}\nEOF"
             )

    before_allocation_count = Repo.aggregate(FundAllocation, :count, :id)
    before_item_count = Repo.aggregate(FundAllocationItem, :count, :id)

    before_transaction_count = Repo.aggregate(Transaction, :count, :id)
    before_category_count = Repo.aggregate(Category, :count, :id)
    before_assignment_count = Repo.aggregate(SecurityCategoryAssignment, :count, :id)

    {:ok, view, _html} = live(conn, "/fund-documents/#{fund_document.id}/allocations/review")

    view
    |> element("#factsheet-review-confirm-form")
    |> render_submit()

    assert Repo.aggregate(FundAllocation, :count, :id) == before_allocation_count + 1
    assert Repo.aggregate(FundAllocationItem, :count, :id) == before_item_count + 2

    assert Repo.aggregate(Transaction, :count, :id) == before_transaction_count
    assert Repo.aggregate(Category, :count, :id) == before_category_count
    assert Repo.aggregate(SecurityCategoryAssignment, :count, :id) == before_assignment_count

    assert has_element?(view, "#factsheet-summary-created-allocations")
    assert has_element?(view, "#factsheet-summary-created-items")
    assert has_element?(view, "#factsheet-summary-created-allocations", "1")
    assert has_element?(view, "#factsheet-summary-created-items", "2")
  end

  test "confirming allocations twice is idempotent", %{conn: conn} do
    security = create_security("FACTSHEET-REVIEW-IDEMP")

    assert {:ok, :created, fund_document} =
             FactsheetDocuments.register_factsheet(
               security.id,
               "factsheet.pdf",
               "application/pdf",
               "PDF-LIKE\nFACTSHEET_TEXT:#{@single_region_text}\nEOF"
             )

    {:ok, view, _html} = live(conn, "/fund-documents/#{fund_document.id}/allocations/review")

    view
    |> element("#factsheet-review-confirm-form")
    |> render_submit()

    assert has_element?(view, "#factsheet-summary-created-allocations")
    assert has_element?(view, "#factsheet-summary-skipped-allocations")
    assert has_element?(view, "#factsheet-summary-created-allocations", "1")
    assert has_element?(view, "#factsheet-summary-skipped-allocations", "0")

    view
    |> element("#factsheet-review-confirm-form")
    |> render_submit()

    assert has_element?(view, "#factsheet-summary-created-allocations", "0")
    assert has_element?(view, "#factsheet-summary-skipped-allocations", "1")
    assert has_element?(view, "#factsheet-summary-skipped-items", "2")
  end

  test "unknown fund document id shows clear not found state", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/fund-documents/9999999/allocations/review")

    assert has_element?(view, "#factsheet-review-not-found", "Fund document not found")
  end

  defp create_security(symbol) do
    {:ok, security} =
      Catalog.create_security(%{
        name: "Factsheet #{symbol}",
        symbol: symbol,
        currency_code: "USD"
      })

    security
  end
end
