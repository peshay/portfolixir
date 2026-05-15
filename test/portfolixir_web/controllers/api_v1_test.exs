defmodule PortfolixirWeb.ApiV1Test do
  use PortfolixirWeb.ConnCase

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.QuoteSync.Fake, as: QuoteSyncFake
  @auth {"authorization", "Bearer test-api-token"}

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header(elem(@auth, 0), elem(@auth, 1))
  end

  defp post_json(conn, path, body) do
    conn |> api_conn() |> post(path, Jason.encode!(body))
  end

  defp patch_json(conn, path, body) do
    conn |> api_conn() |> patch(path, Jason.encode!(body))
  end

  defp put_json(conn, path, body) do
    conn |> api_conn() |> put(path, Jason.encode!(body))
  end

  # User story:
  # As a local portfolio maintainer,
  # I want the local API to require a configured bearer token,
  # so that portfolio data is not exposed by accident when API and MCP access
  # are enabled.
  #
  # Acceptance criteria:
  # - Missing or invalid credentials return 401 JSON.
  # - A valid bearer token can access API resources.
  test "requires bearer token authentication for api v1", %{conn: conn} do
    conn = get(conn, "/api/v1/securities")
    assert json_response(conn, 401) == %{"errors" => %{"detail" => "unauthorized"}}

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer wrong")
      |> get("/api/v1/securities")

    assert json_response(conn, 401) == %{"errors" => %{"detail" => "unauthorized"}}

    conn = build_conn() |> api_conn() |> get("/api/v1/securities")
    assert json_response(conn, 200) == %{"data" => []}
  end

  # User story:
  # As a local portfolio maintainer,
  # I want the manual portfolio workflow available through JSON API calls,
  # so that non-browser clients and the MCP companion can perform the same
  # local actions as the UI.
  #
  # Acceptance criteria:
  # - The API can create securities, one portfolio, linked cash/depot accounts,
  #   and manual buy/sell transactions.
  # - Decimal values are accepted and returned as strings, not floats.
  # - Holdings are derived from the recorded transactions.
  test "creates the manual portfolio workflow and returns decimal strings", %{conn: conn} do
    security =
      conn
      |> post_json("/api/v1/securities", %{
        "security" => %{
          "name" => "Synthetic Global ETF",
          "ticker_symbol" => "SYN",
          "currency_code" => "EUR",
          "asset_class" => "equity",
          "provider" => "manual"
        }
      })
      |> json_response(201)
      |> Map.fetch!("data")

    assert security["ticker_symbol"] == "SYN"

    portfolio =
      conn
      |> post_json("/api/v1/portfolios", %{
        "portfolio" => %{"name" => "Local Portfolio", "base_currency_code" => "EUR"}
      })
      |> json_response(201)
      |> Map.fetch!("data")

    cash_account =
      conn
      |> post_json("/api/v1/cash_accounts", %{
        "cash_account" => %{
          "portfolio_id" => portfolio["id"],
          "name" => "Cash EUR",
          "currency_code" => "EUR"
        }
      })
      |> json_response(201)
      |> Map.fetch!("data")

    depot =
      conn
      |> post_json("/api/v1/securities_accounts", %{
        "securities_account" => %{
          "portfolio_id" => portfolio["id"],
          "cash_account_id" => cash_account["id"],
          "name" => "Depot"
        }
      })
      |> json_response(201)
      |> Map.fetch!("data")

    transaction =
      conn
      |> post_json("/api/v1/transactions", %{
        "transaction" => %{
          "portfolio_id" => portfolio["id"],
          "securities_account_id" => depot["id"],
          "security_id" => security["id"],
          "type" => "buy",
          "date" => "2026-05-15",
          "quantity" => "3.25",
          "price" => "101.23",
          "fees" => "1.50",
          "taxes" => "0",
          "currency_code" => "EUR"
        }
      })
      |> json_response(201)
      |> Map.fetch!("data")

    assert transaction["quantity"] == "3.25"
    assert transaction["price"] == "101.23"
    assert transaction["fees"] == "1.5"
    assert transaction["taxes"] == "0"
    assert is_binary(transaction["quantity"])

    holdings =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{portfolio["id"]}/holdings")
      |> json_response(200)
      |> Map.fetch!("data")

    assert [
             %{
               "portfolio_id" => portfolio_id,
               "securities_account_id" => securities_account_id,
               "security_id" => security_id,
               "quantity" => "3.25"
             }
           ] = holdings

    assert portfolio_id == portfolio["id"]
    assert securities_account_id == depot["id"]
    assert security_id == security["id"]
  end

  # User story:
  # As a local portfolio maintainer,
  # I want online security search and quote maintenance exposed through the API,
  # so that MCP can wrap these actions without adding a second domain layer.
  #
  # Acceptance criteria:
  # - Online search uses the configured provider abstraction.
  # - Manual quote upserts and quote sync return Decimal closes as strings.
  # - Tests use fake providers and make no real network calls.
  test "searches online securities and manages quote history through fake providers", %{
    conn: conn
  } do
    QuoteSyncFake.clear_responses()

    search =
      conn
      |> api_conn()
      |> get("/api/v1/securities/search?query=apple&type=security")
      |> json_response(200)
      |> Map.fetch!("data")

    assert [%{"name" => "Apple Inc.", "provider" => "portfolio_performance"}] = search

    {:ok, security} =
      Catalog.create_security(%{
        name: "Manual Sync",
        currency_code: "USD",
        provider: "manual"
      })

    QuoteSyncFake.put_response(
      security.id,
      {:ok, [%{date: ~D[2026-05-15], close: Decimal.new("42.50")}]}
    )

    prior_cfg = Application.get_env(:portfolixir, Portfolixir.Catalog.QuoteSync, [])

    Application.put_env(
      :portfolixir,
      Portfolixir.Catalog.QuoteSync,
      Keyword.put(prior_cfg, :adapter_for, %{"manual" => QuoteSyncFake})
    )

    try do
      sync =
        conn
        |> post_json("/api/v1/securities/#{security.id}/sync_quotes", %{})
        |> json_response(200)

      assert sync == %{"data" => %{"status" => "ok"}}
    after
      Application.put_env(:portfolixir, Portfolixir.Catalog.QuoteSync, prior_cfg)
    end

    quotes =
      conn
      |> put_json("/api/v1/securities/#{security.id}/quotes", %{
        "quotes" => [
          %{"date" => "2026-05-16", "close" => "43.75", "source" => "manual"}
        ]
      })
      |> json_response(200)
      |> Map.fetch!("data")

    assert quotes["upserted"] == 1

    quote_history =
      conn
      |> api_conn()
      |> get("/api/v1/securities/#{security.id}/quotes?from=2026-05-01&to=2026-05-31")
      |> json_response(200)
      |> Map.fetch!("data")

    assert Enum.map(quote_history, & &1["close"]) == ["42.5", "43.75"]
  end

  # User story:
  # As a local portfolio maintainer using API clients,
  # I want updates, deletes, and validation errors to be predictable,
  # so that clients can recover without scraping HTML or stack traces.
  #
  # Acceptance criteria:
  # - PATCH updates an existing security and DELETE removes it.
  # - Validation errors are returned as structured JSON field errors.
  # - Invalid external action inputs are rejected without creating atoms.
  test "updates deletes and reports structured validation errors", %{conn: conn} do
    {:ok, security} =
      Catalog.create_security(%{
        name: "Old Name",
        currency_code: "EUR",
        provider: "manual"
      })

    updated =
      conn
      |> patch_json("/api/v1/securities/#{security.id}", %{
        "security" => %{"name" => "New Name", "ticker_symbol" => "new"}
      })
      |> json_response(200)
      |> Map.fetch!("data")

    assert updated["name"] == "New Name"
    assert updated["ticker_symbol"] == "NEW"

    invalid =
      conn
      |> post_json("/api/v1/securities", %{"security" => %{"name" => ""}})
      |> json_response(422)

    assert %{"errors" => %{"currency_code" => [_], "name" => [_]}} = invalid

    invalid_search =
      conn
      |> api_conn()
      |> get("/api/v1/securities/search?query=apple&type=__bad__")
      |> json_response(422)

    assert invalid_search == %{"errors" => %{"type" => ["is invalid"]}}

    invalid_sort =
      conn
      |> api_conn()
      |> get("/api/v1/securities?sort=__bad__")
      |> json_response(422)

    assert invalid_sort == %{"errors" => %{"sort" => ["is invalid"]}}

    missing_quote_target =
      conn
      |> put_json("/api/v1/securities/999999/quotes", %{
        "quotes" => [%{"date" => "2026-05-16", "close" => "43.75", "source" => "manual"}]
      })
      |> json_response(404)

    assert missing_quote_target == %{"errors" => %{"detail" => "not found"}}

    conn = build_conn() |> api_conn() |> delete("/api/v1/securities/#{security.id}")
    assert response(conn, 204) == ""
    assert Catalog.get_security(security.id) == nil
  end
end
