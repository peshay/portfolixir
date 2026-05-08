defmodule PortfolixirWeb.FactsheetAllocationReviewNotFoundA11yTest do
  use ExUnit.Case, async: true
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint PortfolixirWeb.Endpoint

  test "invalid fund document id renders accessible not found state" do
    {:ok, view, _html} = live(build_conn(), "/fund-documents/not-a-number/allocations/review")

    assert has_element?(
             view,
             "#factsheet-review-not-found[role='status'][aria-labelledby='factsheet-review-not-found-title'][aria-describedby='factsheet-review-not-found-description']"
           )

    assert has_element?(view, "#factsheet-review-not-found-title", "Fund document not found")

    assert has_element?(
             view,
             "#factsheet-review-not-found-description",
             "This factsheet document is not available."
           )
  end
end
