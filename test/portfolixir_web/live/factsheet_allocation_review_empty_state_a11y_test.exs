defmodule PortfolixirWeb.FactsheetAllocationReviewEmptyStateA11yTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.FactsheetDocuments

  setup do
    Catalog.ensure_mvp_currencies!()
    :ok
  end

  test "empty review state keeps stable title and description ids for assistive tech", %{
    conn: conn
  } do
    security = create_security("FACTSHEET-REVIEW-EMPTY-A11Y")

    assert {:ok, :created, fund_document} =
             FactsheetDocuments.register_factsheet(
               security.id,
               "factsheet.pdf",
               "application/pdf",
               "PDF-LIKE\nFACTSHEET_TEXT:EOF"
             )

    {:ok, view, _html} = live(conn, "/fund-documents/#{fund_document.id}/allocations/review")

    assert has_element?(view, "#factsheet-review-empty-state")

    assert has_element?(
             view,
             "#factsheet-review-empty-state[role='status'][aria-live='polite'][aria-labelledby='factsheet-review-empty-state-title'][aria-describedby='factsheet-review-empty-state-description']"
           )

    assert has_element?(view, "#factsheet-review-empty-state-title")
    assert has_element?(view, "#factsheet-review-empty-state-description")
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
