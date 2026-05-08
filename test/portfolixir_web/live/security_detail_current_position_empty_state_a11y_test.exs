defmodule PortfolixirWeb.SecurityDetailCurrentPositionEmptyStateA11yTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Catalog

  setup do
    Catalog.ensure_mvp_currencies!()
    :ok
  end

  test "current-position empty state keeps stable title and description ids", %{conn: conn} do
    security = create_security("CUR-POS-EMPTY-A11Y")

    {:ok, view, _html} = live(conn, "/securities/#{security.id}")

    assert has_element?(
             view,
             "#no-security-positions[role='status'][aria-live='polite'][aria-labelledby='no-security-positions-title'][aria-describedby='no-security-positions-description']"
           )

    assert has_element?(view, "#no-security-positions-title")
    assert has_element?(view, "#no-security-positions-description")
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
