defmodule PortfolixirWeb.SecurityControllerTest do
  use PortfolixirWeb.ConnCase

  alias Portfolixir.Catalog

  setup do
    Catalog.ensure_mvp_currencies!()
    :ok
  end

  test "GET /securities/export.csv returns CSV with all securities", %{conn: conn} do
    {:ok, active_security} =
      Catalog.create_security(%{
        name: "Active Security",
        symbol: "AS",
        currency_code: "USD",
        active: true
      })

    {:ok, inactive_security} =
      Catalog.create_security(%{
        name: "Inactive Security",
        symbol: "IS",
        currency_code: "USD",
        active: false
      })

    conn = get(conn, "/securities/export.csv")
    body = response(conn, 200)

    assert response_content_type(conn, :csv) == "text/csv; charset=utf-8"

    assert get_resp_header(conn, "content-disposition") == [
             "attachment; filename=\"portfolixir-securities.csv\""
           ]

    assert String.starts_with?(
             body,
             "name,symbol,currency_code,active,isin,wkn,provider_symbol,exchange_code,notes\n"
           )

    assert body =~ active_security.name
    assert body =~ inactive_security.name
  end

  test "CSV export escapes special characters and includes empty cells", %{conn: conn} do
    {:ok, _} =
      Catalog.create_security(%{
        name: "Name, \"Quoted\"",
        symbol: "NQ",
        currency_code: "USD",
        notes: "Line1\nLine2"
      })

    conn = get(conn, "/securities/export.csv")
    body = response(conn, 200)

    assert body =~ "\"Name, \"\"Quoted\"\"\",NQ,USD,true,,,,,\"Line1\nLine2\""
  end
end
