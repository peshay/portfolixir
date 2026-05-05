defmodule PortfolixirWeb.SecurityControllerTest do
  use PortfolixirWeb.ConnCase

  alias Portfolixir.Catalog

  setup do
    old_auth_config =
      Application.get_env(:portfolixir, PortfolixirWeb.Plugs.BrowserApiKeyAuth, [])

    on_exit(fn ->
      Application.put_env(:portfolixir, PortfolixirWeb.Plugs.BrowserApiKeyAuth, old_auth_config)
    end)

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

  test "denies anonymous browser and CSV export access when browser auth is enabled", %{
    conn: conn
  } do
    Application.put_env(:portfolixir, PortfolixirWeb.Plugs.BrowserApiKeyAuth,
      enabled: true,
      api_key: "browser-test-key"
    )

    assert get(conn, "/accounts") |> response(401) == "unauthorized"
    assert get(conn, "/securities/export.csv") |> response(401) == "unauthorized"
  end

  test "allows browser and CSV export access with valid API key when browser auth is enabled", %{
    conn: conn
  } do
    Application.put_env(:portfolixir, PortfolixirWeb.Plugs.BrowserApiKeyAuth,
      enabled: true,
      api_key: "browser-test-key"
    )

    assert get(put_req_header(conn, "x-api-key", "browser-test-key"), "/accounts")
           |> response(200)

    csv_conn =
      conn
      |> recycle()
      |> put_req_header("x-api-key", "browser-test-key")
      |> get("/securities/export.csv")

    assert response(csv_conn, 200)
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
