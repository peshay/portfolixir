defmodule PortfolixirWeb.SecurityDetailTransactionsEmptyStateA11yTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Catalog

  setup do
    Catalog.ensure_mvp_currencies!()
    :ok
  end

  test "transactions empty state keeps stable title and description ids", %{conn: conn} do
    security = create_security("TX-EMPTY-A11Y")

    {:ok, view, _html} = live(conn, "/securities/#{security.id}")

    assert has_element?(
             view,
             "#no-security-transactions[role='status'][aria-live='polite'][aria-labelledby='no-security-transactions-title'][aria-describedby='no-security-transactions-description']"
           )

    assert has_element?(view, "#no-security-transactions-title")
    assert has_element?(view, "#no-security-transactions-description")
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
