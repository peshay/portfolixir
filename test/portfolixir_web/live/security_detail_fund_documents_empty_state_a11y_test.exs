defmodule PortfolixirWeb.SecurityDetailFundDocumentsEmptyStateA11yTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Catalog

  setup do
    Catalog.ensure_mvp_currencies!()
    :ok
  end

  test "fund documents empty state keeps stable title and description ids", %{conn: conn} do
    security = create_security("FUND-DOCS-EMPTY-A11Y")

    {:ok, view, _html} = live(conn, "/securities/#{security.id}")

    assert has_element?(
             view,
             "#security-fund-documents-empty-state[role='status'][aria-live='polite'][aria-labelledby='security-fund-documents-empty-state-title'][aria-describedby='security-fund-documents-empty-state-description']"
           )

    assert has_element?(view, "#security-fund-documents-empty-state-title")
    assert has_element?(view, "#security-fund-documents-empty-state-description")
  end

  defp create_security(symbol) do
    {:ok, security} =
      Catalog.create_security(%{
        name: "Security #{symbol}",
        symbol: symbol,
        currency_code: "EUR"
      })

    security
  end
end
