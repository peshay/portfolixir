defmodule PortfolixirWeb.ApiV1Test do
  use PortfolixirWeb.ConnCase

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Catalog.QuoteSync.Fake, as: QuoteSyncFake
  alias Portfolixir.Fx.RateSync.Fake, as: FxRateFake
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
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
  # As an API client creating master data,
  # I want the securities API to accept government bond as a first-class type,
  # so that local tools can create state bonds that get flag fallbacks in the UI.
  #
  # Acceptance criteria:
  # - `asset_class=government_bond` is accepted by POST /api/v1/securities.
  # - The response serializes the asset class as the stable string code.
  test "creates a government bond security through the API", %{conn: conn} do
    response =
      conn
      |> post_json("/api/v1/securities", %{
        "security" => %{
          "name" => "German Federal Bond",
          "isin" => "DE0001102614",
          "currency_code" => "EUR",
          "asset_class" => "government_bond"
        }
      })
      |> json_response(201)

    assert response["data"]["asset_class"] == "government_bond"
    assert response["data"]["isin"] == "DE0001102614"
  end

  # User story:
  # As an API client listing securities,
  # I want to filter by derived holding status,
  # so that MCP and other local clients can request active or inactive securities without duplicating ledger logic.
  #
  # Acceptance criteria:
  # - `holding_status=held` returns securities with non-zero net buy/sell quantity.
  # - `holding_status=not_held` returns sold-out and never-held securities.
  # - Invalid holding_status values return a field-specific 422 error.
  test "lists securities with a derived holding_status filter", %{conn: conn} do
    {:ok, held} =
      Catalog.create_security(%{
        name: "Held API ETF",
        ticker_symbol: "HAPI",
        currency_code: "EUR",
        asset_class: "equity"
      })

    {:ok, flat} =
      Catalog.create_security(%{
        name: "Flat API ETF",
        ticker_symbol: "FAPI",
        currency_code: "EUR",
        asset_class: "equity"
      })

    {:ok, _never} =
      Catalog.create_security(%{
        name: "Never API ETF",
        ticker_symbol: "NAPI",
        currency_code: "EUR",
        asset_class: "equity"
      })

    {:ok, portfolio} =
      Portfolios.create_portfolio(%{name: "API Filter Portfolio", base_currency_code: "EUR"})

    {:ok, cash_account} =
      Portfolios.create_cash_account(%{
        portfolio_id: portfolio.id,
        name: "API Filter Cash",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        cash_account_id: cash_account.id,
        name: "API Filter Depot"
      })

    for {security, type, quantity, date} <- [
          {held, "buy", "5", ~D[2026-01-02]},
          {flat, "buy", "2", ~D[2026-01-03]},
          {flat, "sell", "2", ~D[2026-01-04]}
        ] do
      assert {:ok, _} =
               Ledger.create_transaction(%{
                 portfolio_id: portfolio.id,
                 securities_account_id: depot.id,
                 cash_account_id: cash_account.id,
                 security_id: security.id,
                 type: type,
                 date: date,
                 quantity: Decimal.new(quantity),
                 price: Decimal.new("10"),
                 fees: Decimal.new("0"),
                 taxes: Decimal.new("0"),
                 currency_code: "EUR"
               })
    end

    held_names =
      conn
      |> api_conn()
      |> get("/api/v1/securities?holding_status=held&sort=name&direction=asc")
      |> json_response(200)
      |> Map.fetch!("data")
      |> Enum.map(& &1["name"])

    assert held_names == ["Held API ETF"]

    not_held_names =
      build_conn()
      |> api_conn()
      |> get("/api/v1/securities?holding_status=not_held&sort=name&direction=asc")
      |> json_response(200)
      |> Map.fetch!("data")
      |> Enum.map(& &1["name"])

    assert not_held_names == ["Flat API ETF", "Never API ETF"]

    invalid =
      build_conn()
      |> api_conn()
      |> get("/api/v1/securities?holding_status=__bad__")
      |> json_response(422)

    assert invalid == %{"errors" => %{"holding_status" => ["is invalid"]}}
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
  # As an API client triggering quote sync,
  # I want skipped syncs to include a reason,
  # so that clients do not treat missing provider setup as fresh quote data.
  #
  # Acceptance criteria:
  # - `sync_quotes` returns `status: "skipped"` for skipped syncs.
  # - The response includes a stable `reason`.
  # - The response remains under the existing `data` envelope.
  test "quote sync API reports skipped status and reason", %{conn: conn} do
    {:ok, security} =
      Catalog.create_security(%{
        name: "No Adapter Security",
        currency_code: "USD",
        provider: "manual"
      })

    prior_cfg = Application.get_env(:portfolixir, Portfolixir.Catalog.QuoteSync, [])

    Application.put_env(
      :portfolixir,
      Portfolixir.Catalog.QuoteSync,
      Keyword.put(prior_cfg, :adapter_for, %{})
    )

    try do
      response =
        conn
        |> post_json("/api/v1/securities/#{security.id}/sync_quotes", %{})
        |> json_response(200)

      assert response == %{
               "data" => %{"status" => "skipped", "reason" => "no_provider_adapter"}
             }
    after
      Application.put_env(:portfolixir, Portfolixir.Catalog.QuoteSync, prior_cfg)
    end
  end

  # User story:
  # As a local portfolio maintainer preserving auditable price history,
  # I want quote history to block security deletion through the API,
  # so that recorded quotes are not silently removed with their security.
  #
  # Acceptance criteria:
  # - Deleting a security referenced only by quote history returns 409 JSON.
  # - The security record is preserved.
  # - The quote history row is preserved.
  test "delete returns conflict when quote history references the security", %{conn: conn} do
    {:ok, security} =
      Catalog.create_security(%{
        name: "Quoted Security",
        currency_code: "EUR",
        provider: "manual"
      })

    assert {:ok, 1} =
             Quotes.upsert_many(security.id, [
               %{"date" => "2026-05-16", "close" => "43.75", "source" => "manual"}
             ])

    conflict =
      conn
      |> api_conn()
      |> delete("/api/v1/securities/#{security.id}")
      |> json_response(409)

    assert conflict == %{"errors" => %{"detail" => "security is referenced by existing records"}}
    assert Catalog.get_security(security.id)
    assert [%{close: close}] = Quotes.range(security.id, ~D[2026-05-01], ~D[2026-05-31])
    assert Decimal.equal?(close, Decimal.new("43.75"))
  end

  # User story:
  # As an API client requesting derived holdings,
  # I want syntactically valid but unknown portfolio IDs to return not found,
  # so that an empty holdings list is reserved for existing portfolios with no positions.
  #
  # Acceptance criteria:
  # - `GET /api/v1/portfolios/:portfolio_id/holdings` returns 404 for a missing portfolio.
  # - The response uses the normal JSON not-found shape.
  test "holdings returns not found for a syntactically valid missing portfolio", %{conn: conn} do
    response =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/999999/holdings")
      |> json_response(404)

    assert response == %{"errors" => %{"detail" => "not found"}}
  end

  # User story:
  # As an API client (and the LLM behind it),
  # I want a live portfolio valuation endpoint,
  # so that I can read current market values and actual weights as decimal strings.
  #
  # Acceptance criteria:
  # - `GET /api/v1/portfolios/:portfolio_id/valuation` returns a total and per-position weights.
  # - Market values, weights, and the total serialize as decimal strings.
  # - A missing portfolio returns the normal 404 JSON shape.
  test "values a portfolio and returns decimal-string weights", %{conn: conn} do
    {:ok, security} =
      Catalog.create_security(%{
        name: "Synthetic ETF",
        ticker_symbol: "SYN",
        currency_code: "EUR",
        asset_class: "etf"
      })

    {:ok, portfolio} =
      Portfolios.create_portfolio(%{name: "Valued Portfolio", base_currency_code: "EUR"})

    {:ok, cash} =
      Portfolios.create_cash_account(%{
        portfolio_id: portfolio.id,
        name: "Cash EUR",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Depot"
      })

    {:ok, _tx} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: depot.id,
        cash_account_id: cash.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-01-02],
        quantity: "4",
        price: "10",
        fees: "0",
        taxes: "0",
        currency_code: "EUR"
      })

    {:ok, _} =
      Quotes.upsert_many(security.id, [%{date: ~D[2026-06-01], close: "25", source: "manual"}])

    valuation =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{portfolio.id}/valuation")
      |> json_response(200)
      |> Map.fetch!("data")

    assert valuation["total_value"] == "100"
    assert valuation["unvalued_count"] == 0

    # FR-13: the valuation is self-describing about its read date and that totals
    # are in base_currency via the EUR hub, with staleness shown per position.
    assert valuation["as_of"] == Date.to_iso8601(Date.utc_today())
    assert valuation["base_currency"] == "EUR"
    assert valuation["valuation_note"] =~ "base_currency"
    assert valuation["valuation_note"] =~ "EUR hub"
    assert valuation["valuation_note"] =~ "price_source"
    assert valuation["valuation_note"] =~ "valued"

    assert [position] = valuation["positions"]
    assert position["security_id"] == security.id
    assert position["market_value"] == "100"
    assert position["weight"] == "1"
    assert position["valued"] == true
    assert is_binary(position["market_value"])

    missing =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/999999/valuation")
      |> json_response(404)

    assert missing == %{"errors" => %{"detail" => "not found"}}
  end

  # User story:
  # As an API/MCP client managing a depot,
  # I want cash balances surfaced per account and folded into the valuation,
  # so that I can compute cash quote and floors directly.
  test "reports cash balances per account and in the valuation", %{conn: conn} do
    {:ok, security} =
      Catalog.create_security(%{name: "ETF", currency_code: "EUR", asset_class: "etf"})

    {:ok, portfolio} =
      Portfolios.create_portfolio(%{name: "Cash Portfolio", base_currency_code: "EUR"})

    {:ok, cash} =
      Portfolios.create_cash_account(%{
        portfolio_id: portfolio.id,
        name: "Cash EUR",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Depot"
      })

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        type: "deposit",
        date: ~D[2026-01-01],
        gross_amount: "1000",
        currency_code: "EUR"
      })

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: depot.id,
        cash_account_id: cash.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-01-02],
        quantity: "4",
        price: "10",
        currency_code: "EUR"
      })

    accounts =
      conn
      |> api_conn()
      |> get("/api/v1/cash_accounts")
      |> json_response(200)
      |> Map.fetch!("data")

    # 1000 deposited - 40 spent on the buy (4 * 10).
    assert [account] = accounts
    assert account["balance"] == "960"

    valuation =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{portfolio.id}/valuation")
      |> json_response(200)
      |> Map.fetch!("data")

    assert valuation["total_cash"] == "960"
    assert [cash_entry] = valuation["cash_balances"]
    assert cash_entry["cash_account_id"] == cash.id
    assert cash_entry["balance"] == "960"
    assert cash_entry["valued"] == true
  end

  # User story:
  # As an API/MCP client correcting a mis-imported booking,
  # I want to filter, patch and delete transactions,
  # so that I can fix the ledger instead of only appending to it.
  test "filters, updates and deletes transactions", %{conn: conn} do
    {:ok, security} =
      Catalog.create_security(%{name: "ETF", currency_code: "EUR", asset_class: "etf"})

    {:ok, portfolio} =
      Portfolios.create_portfolio(%{name: "P", base_currency_code: "EUR"})

    {:ok, cash} =
      Portfolios.create_cash_account(%{
        portfolio_id: portfolio.id,
        name: "Cash",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Depot"
      })

    {:ok, deposit} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        type: "deposit",
        date: ~D[2026-01-01],
        gross_amount: "1000",
        currency_code: "EUR"
      })

    {:ok, buy} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: depot.id,
        cash_account_id: cash.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-02-01],
        quantity: "4",
        price: "10",
        currency_code: "EUR"
      })

    by_date =
      conn
      |> api_conn()
      |> get("/api/v1/transactions?from=2026-02-01")
      |> json_response(200)
      |> Map.fetch!("data")

    assert Enum.map(by_date, & &1["id"]) == [buy.id]

    by_security =
      conn
      |> api_conn()
      |> get("/api/v1/transactions?security_id=#{security.id}")
      |> json_response(200)
      |> Map.fetch!("data")

    assert Enum.map(by_security, & &1["id"]) == [buy.id]

    bad =
      conn
      |> api_conn()
      |> get("/api/v1/transactions?from=nope")
      |> json_response(422)

    assert bad["errors"]["from"] == ["is invalid"]

    updated =
      conn
      |> patch_json("/api/v1/transactions/#{deposit.id}", %{
        "transaction" => %{"notes" => "opening balance"}
      })
      |> json_response(200)
      |> Map.fetch!("data")

    assert updated["notes"] == "opening balance"

    deleted = conn |> api_conn() |> delete("/api/v1/transactions/#{buy.id}")
    assert response(deleted, 204) == ""
    assert Ledger.get_transaction(buy.id) == nil
  end

  # User story:
  # As an API/MCP client cleaning up account setup,
  # I want to rename accounts and be stopped from deleting ones still in use,
  # so that I never orphan a referenced transaction.
  test "updates accounts and refuses to delete referenced ones", %{conn: conn} do
    {:ok, security} =
      Catalog.create_security(%{name: "ETF", currency_code: "EUR", asset_class: "etf"})

    {:ok, portfolio} =
      Portfolios.create_portfolio(%{name: "P", base_currency_code: "EUR"})

    {:ok, cash} =
      Portfolios.create_cash_account(%{
        portfolio_id: portfolio.id,
        name: "Cash",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Depot"
      })

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: depot.id,
        cash_account_id: cash.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-01-02],
        quantity: "1",
        price: "10",
        currency_code: "EUR"
      })

    renamed_cash =
      conn
      |> patch_json("/api/v1/cash_accounts/#{cash.id}", %{"cash_account" => %{"name" => "Main"}})
      |> json_response(200)
      |> Map.fetch!("data")

    assert renamed_cash["name"] == "Main"

    renamed_depot =
      conn
      |> patch_json("/api/v1/securities_accounts/#{depot.id}", %{
        "securities_account" => %{"name" => "Main Depot"}
      })
      |> json_response(200)
      |> Map.fetch!("data")

    assert renamed_depot["name"] == "Main Depot"

    assert conn
           |> api_conn()
           |> delete("/api/v1/securities_accounts/#{depot.id}")
           |> json_response(409) ==
             %{"errors" => %{"detail" => "securities account is referenced by existing records"}}

    assert conn
           |> api_conn()
           |> delete("/api/v1/cash_accounts/#{cash.id}")
           |> json_response(409) ==
             %{"errors" => %{"detail" => "cash account is referenced by existing records"}}

    {:ok, spare} =
      Portfolios.create_cash_account(%{
        portfolio_id: portfolio.id,
        name: "Spare",
        currency_code: "EUR"
      })

    deleted = conn |> api_conn() |> delete("/api/v1/cash_accounts/#{spare.id}")
    assert response(deleted, 204) == ""
    assert Portfolios.get_cash_account(spare.id) == nil
  end

  # User story:
  # As an API/MCP client inspecting a large portfolio,
  # I want to filter holdings by security,
  # so that I do not fetch every position to read one.
  test "filters holdings by security", %{conn: conn} do
    {:ok, s1} =
      Catalog.create_security(%{name: "A", currency_code: "EUR", asset_class: "etf"})

    {:ok, s2} =
      Catalog.create_security(%{name: "B", currency_code: "EUR", asset_class: "etf"})

    {:ok, portfolio} =
      Portfolios.create_portfolio(%{name: "P", base_currency_code: "EUR"})

    {:ok, cash} =
      Portfolios.create_cash_account(%{
        portfolio_id: portfolio.id,
        name: "Cash",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Depot"
      })

    for security <- [s1, s2] do
      {:ok, _} =
        Ledger.create_transaction(%{
          portfolio_id: portfolio.id,
          securities_account_id: depot.id,
          cash_account_id: cash.id,
          security_id: security.id,
          type: "buy",
          date: ~D[2026-01-02],
          quantity: "1",
          price: "10",
          currency_code: "EUR"
        })
    end

    all =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{portfolio.id}/holdings")
      |> json_response(200)
      |> Map.fetch!("data")

    assert length(all) == 2

    filtered =
      conn
      |> api_conn()
      |> get("/api/v1/portfolios/#{portfolio.id}/holdings?security_id=#{s1.id}")
      |> json_response(200)
      |> Map.fetch!("data")

    assert Enum.map(filtered, & &1["security_id"]) == [s1.id]
  end

  # User story:
  # As an API client (and the LLM behind it),
  # I want to refresh and read exchange rates,
  # so that multi-currency valuations convert into the portfolio base currency.
  #
  # Acceptance criteria:
  # - `POST /api/v1/exchange_rates/sync` returns the provider sync result.
  # - `GET /api/v1/exchange_rates` lists the stored rates as decimal strings.
  test "syncs and lists exchange rates", %{conn: conn} do
    FxRateFake.clear_response()

    FxRateFake.put_response(
      {:ok,
       [
         %{
           base_currency: "EUR",
           quote_currency: "USD",
           date: ~D[2026-06-04],
           rate: "1.25",
           source: "ecb"
         }
       ]}
    )

    sync =
      conn
      |> api_conn()
      |> post("/api/v1/exchange_rates/sync")
      |> json_response(200)
      |> Map.fetch!("data")

    assert sync["provider"] == "fake"
    assert sync["status"] == "ok"
    assert sync["upserted"] == 1

    rates =
      conn
      |> api_conn()
      |> get("/api/v1/exchange_rates")
      |> json_response(200)
      |> Map.fetch!("data")

    assert [
             %{
               "base_currency" => "EUR",
               "quote_currency" => "USD",
               "rate" => "1.25",
               "source" => "ecb"
             }
           ] = rates
  end

  # User story:
  # As an API client (and the LLM behind it),
  # I want to read classification trees and build custom ones with assignments,
  # so that securities can be organised like folders, alongside the locked
  # built-in asset-class and currency trees.
  test "lists built-in classifications and manages custom trees", %{conn: conn} do
    {:ok, security} =
      Catalog.create_security(%{name: "Apple", currency_code: "USD", asset_class: "equity"})

    trees =
      conn
      |> api_conn()
      |> get("/api/v1/classifications")
      |> json_response(200)
      |> Map.fetch!("data")

    asset = Enum.find(trees, &(&1["key"] == "asset_class"))
    assert asset["built_in"] == true
    assert Enum.any?(asset["categories"], &(&1["key"] == "equity"))

    classification =
      conn
      |> post_json("/api/v1/classifications", %{"classification" => %{"name" => "My Strategy"}})
      |> json_response(201)
      |> Map.fetch!("data")

    refute classification["built_in"]

    category =
      conn
      |> post_json("/api/v1/classifications/#{classification["id"]}/categories", %{
        "category" => %{"name" => "Core", "color" => "#7C3AED"}
      })
      |> json_response(201)
      |> Map.fetch!("data")

    assert category["color"] == "#7c3aed"

    assignment =
      conn
      |> put_json("/api/v1/classifications/#{classification["id"]}/assignments", %{
        "security_id" => security.id,
        "category_id" => category["id"]
      })
      |> json_response(200)
      |> Map.fetch!("data")

    assert assignment["category_id"] == category["id"]

    # Built-in trees reject structural edits.
    locked =
      conn
      |> post_json("/api/v1/classifications/#{asset["id"]}/categories", %{
        "category" => %{"name" => "Nope"}
      })
      |> json_response(422)

    assert locked["errors"]["detail"] =~ "built-in"
  end

  # User story:
  # As an API/MCP client refining a taxonomy,
  # I want to update and delete classifications and categories and bulk-assign
  # securities, so that I can maintain trees in place rather than only create.
  test "updates, bulk-assigns and deletes custom classification trees", %{conn: conn} do
    {:ok, s1} =
      Catalog.create_security(%{name: "Alpha", currency_code: "EUR", asset_class: "equity"})

    {:ok, s2} =
      Catalog.create_security(%{name: "Beta", currency_code: "EUR", asset_class: "equity"})

    classification =
      conn
      |> post_json("/api/v1/classifications", %{"classification" => %{"name" => "Strategy"}})
      |> json_response(201)
      |> Map.fetch!("data")

    cid = classification["id"]

    parent =
      conn
      |> post_json("/api/v1/classifications/#{cid}/categories", %{
        "category" => %{"name" => "Equity"}
      })
      |> json_response(201)
      |> Map.fetch!("data")

    child =
      conn
      |> post_json("/api/v1/classifications/#{cid}/categories", %{
        "category" => %{"name" => "Core"}
      })
      |> json_response(201)
      |> Map.fetch!("data")

    # Patch classification metadata in place.
    updated =
      conn
      |> patch_json("/api/v1/classifications/#{cid}", %{
        "classification" => %{"name" => "Strategy v2", "description" => "Core/satellite"}
      })
      |> json_response(200)
      |> Map.fetch!("data")

    assert updated["name"] == "Strategy v2"
    assert updated["description"] == "Core/satellite"

    # Patch a category: description, color and re-home it under a parent.
    recolored =
      conn
      |> patch_json("/api/v1/classifications/#{cid}/categories/#{child["id"]}", %{
        "category" => %{
          "description" => "Core holdings",
          "color" => "#2563EB",
          "parent_id" => parent["id"]
        }
      })
      |> json_response(200)
      |> Map.fetch!("data")

    assert recolored["description"] == "Core holdings"
    assert recolored["color"] == "#2563eb"
    assert recolored["parent_id"] == parent["id"]

    # A single assign reports that it created a fresh slot.
    created =
      conn
      |> put_json("/api/v1/classifications/#{cid}/assignments", %{
        "security_id" => s1.id,
        "category_id" => child["id"]
      })
      |> json_response(200)
      |> Map.fetch!("data")

    assert created["status"] == "created"

    # Bulk assign moves several securities to one category in one call.
    bulk =
      conn
      |> put_json("/api/v1/classifications/#{cid}/assignments/bulk", %{
        "category_id" => parent["id"],
        "security_ids" => [s1.id, s2.id]
      })
      |> json_response(200)
      |> Map.fetch!("data")

    assert bulk["assigned"] == 2

    # Re-assigning the moved security now reports a move, not a create.
    moved =
      conn
      |> put_json("/api/v1/classifications/#{cid}/assignments", %{
        "security_id" => s1.id,
        "category_id" => child["id"]
      })
      |> json_response(200)
      |> Map.fetch!("data")

    assert moved["status"] == "moved"
    assert moved["previous_category_id"] == parent["id"]

    # Deleting a category cascades its assignments; deleting the tree cascades all.
    assert conn
           |> api_conn()
           |> delete("/api/v1/classifications/#{cid}/categories/#{child["id"]}")
           |> json_response(200)
           |> Map.fetch!("data") == %{"deleted" => true}

    assert conn
           |> api_conn()
           |> delete("/api/v1/classifications/#{cid}")
           |> json_response(200)
           |> Map.fetch!("data") == %{"deleted" => true}
  end

  # User story:
  # As an API/MCP client paging a large catalog,
  # I want limit/offset on the securities list,
  # so that responses stay small instead of dumping the whole table.
  test "paginates the securities list with limit and offset", %{conn: conn} do
    for name <- ["Aaa", "Bbb", "Ccc"] do
      {:ok, _} = Catalog.create_security(%{name: name, currency_code: "EUR"})
    end

    page1 =
      conn
      |> api_conn()
      |> get("/api/v1/securities?limit=2")
      |> json_response(200)
      |> Map.fetch!("data")

    assert Enum.map(page1, & &1["name"]) == ["Aaa", "Bbb"]

    page2 =
      conn
      |> api_conn()
      |> get("/api/v1/securities?limit=2&offset=2")
      |> json_response(200)
      |> Map.fetch!("data")

    assert Enum.map(page2, & &1["name"]) == ["Ccc"]

    invalid =
      conn
      |> api_conn()
      |> get("/api/v1/securities?limit=-1")
      |> json_response(422)

    assert invalid["errors"]["limit"] == ["is invalid"]
  end

  # User story:
  # As an API client filtering quote history by date,
  # I want invalid date parameters to return field-specific validation errors,
  # so that clients can distinguish malformed filters from missing securities.
  #
  # Acceptance criteria:
  # - Invalid `from` returns 422 with a `from` error.
  # - Invalid `to` returns 422 with a `to` error.
  # - The existing security is not treated as missing when only date params are invalid.
  test "quote list returns field errors for invalid date filters", %{conn: conn} do
    {:ok, security} =
      Catalog.create_security(%{
        name: "Date Filter Security",
        currency_code: "EUR",
        provider: "manual"
      })

    invalid_from =
      conn
      |> api_conn()
      |> get("/api/v1/securities/#{security.id}/quotes?from=not-a-date")
      |> json_response(422)

    assert invalid_from == %{"errors" => %{"from" => ["is invalid"]}}

    invalid_to =
      build_conn()
      |> api_conn()
      |> get("/api/v1/securities/#{security.id}/quotes?to=2026-99-99")
      |> json_response(422)

    assert invalid_to == %{"errors" => %{"to" => ["is invalid"]}}
  end

  # User story:
  # As a local portfolio maintainer using API clients,
  # I want updates, deletes, and validation errors to be predictable,
  # so that clients can recover without scraping HTML or stack traces.
  #
  # Acceptance criteria:
  # - PATCH updates an existing security and DELETE removes it.
  # - DELETE returns 409 JSON when existing transactions still reference the security.
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

    {:ok, protected_security} =
      Catalog.create_security(%{
        name: "Referenced Security",
        currency_code: "EUR",
        provider: "manual"
      })

    {:ok, portfolio} =
      Portfolios.create_portfolio(%{name: "Delete Guard Portfolio", base_currency_code: "EUR"})

    {:ok, cash_account} =
      Portfolios.create_cash_account(%{
        portfolio_id: portfolio.id,
        name: "Delete Guard Cash",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        cash_account_id: cash_account.id,
        name: "Delete Guard Depot"
      })

    assert {:ok, _transaction} =
             Ledger.create_transaction(%{
               portfolio_id: portfolio.id,
               securities_account_id: depot.id,
               cash_account_id: cash_account.id,
               security_id: protected_security.id,
               type: "buy",
               date: ~D[2026-05-15],
               quantity: Decimal.new("1"),
               price: Decimal.new("100"),
               fees: Decimal.new("0"),
               taxes: Decimal.new("0"),
               currency_code: "EUR"
             })

    conflict =
      build_conn()
      |> api_conn()
      |> delete("/api/v1/securities/#{protected_security.id}")
      |> json_response(409)

    assert conflict == %{"errors" => %{"detail" => "security is referenced by existing records"}}
    assert Catalog.get_security(protected_security.id)

    conn = build_conn() |> api_conn() |> delete("/api/v1/securities/#{security.id}")
    assert response(conn, 204) == ""
    assert Catalog.get_security(security.id) == nil
  end

  # User story:
  # As a non-browser client (or the MCP companion),
  # I want to request the FIFO-matched trades for a security,
  # so that I can show realised P&L and open exposure outside the UI.
  #
  # Acceptance criteria:
  # - GET /api/v1/securities/:id/trades returns open_lots, closed_trades and
  #   orphan_sells.
  # - Decimal financial values are serialized as strings.
  # - Unknown ids return 404.
  test "exposes FIFO trades through GET /api/v1/securities/:id/trades", %{conn: _conn} do
    {:ok, security} =
      Catalog.create_security(%{
        name: "Apple Inc.",
        ticker_symbol: "AAPL",
        currency_code: "USD",
        asset_class: "equity"
      })

    {:ok, portfolio} =
      Portfolios.create_portfolio(%{name: "Trades Portfolio", base_currency_code: "USD"})

    {:ok, cash} =
      Portfolios.create_cash_account(%{
        portfolio_id: portfolio.id,
        name: "USD",
        currency_code: "USD"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "USD Depot"
      })

    common = %{
      portfolio_id: portfolio.id,
      securities_account_id: depot.id,
      cash_account_id: cash.id,
      security_id: security.id,
      fees: Decimal.new("0"),
      taxes: Decimal.new("0"),
      currency_code: "USD"
    }

    {:ok, _} =
      Ledger.create_transaction(
        Map.merge(common, %{
          type: "buy",
          date: ~D[2026-01-10],
          quantity: Decimal.new("10"),
          price: Decimal.new("100.00")
        })
      )

    {:ok, _} =
      Ledger.create_transaction(
        Map.merge(common, %{
          type: "sell",
          date: ~D[2026-04-10],
          quantity: Decimal.new("4"),
          price: Decimal.new("150.00")
        })
      )

    response =
      build_conn()
      |> api_conn()
      |> get("/api/v1/securities/#{security.id}/trades")
      |> json_response(200)

    assert %{
             "data" => %{
               "method" => "fifo",
               "open_lots" => [_],
               "closed_trades" => [closed],
               "orphan_sells" => []
             }
           } = response

    # Decimals are strings, not floats
    assert is_binary(closed["realized_pnl_abs"])
    assert closed["quantity"] == "4"
    assert closed["realized_pnl_abs"] == "200"
    assert closed["holding_period_days"] == 90

    not_found =
      build_conn()
      |> api_conn()
      |> get("/api/v1/securities/999999/trades")
      |> json_response(404)

    assert not_found == %{"errors" => %{"detail" => "not found"}}
  end

  # User story:
  # As a local portfolio maintainer steering a cash quote (issue #335),
  # I want to set a portfolio's cash target weight through the API,
  # so that non-browser clients and the MCP companion can manage the SOLL cash
  # share like the UI.
  #
  # Acceptance criteria:
  # - PATCH /api/v1/portfolios/:portfolio_id with a valid cash_target_weight in
  #   [0, 1] returns 200 and the stored value as a decimal string.
  # - An out-of-range cash_target_weight returns 422 with a field error.
  # - A non-numeric cash_target_weight returns 422 with a field error.
  # - A syntactically valid but unknown portfolio id returns the normal 404 JSON.
  # - A non-numeric portfolio id in the path returns the normal 404 JSON.
  test "patches a portfolio's cash target weight and reports errors", %{conn: conn} do
    {:ok, portfolio} =
      Portfolios.create_portfolio(%{name: "Cash Target Portfolio", base_currency_code: "EUR"})

    updated =
      conn
      |> patch_json("/api/v1/portfolios/#{portfolio.id}", %{
        "portfolio" => %{"cash_target_weight" => "0.05"}
      })
      |> json_response(200)
      |> Map.fetch!("data")

    assert updated["id"] == portfolio.id
    assert updated["cash_target_weight"] == "0.05"

    out_of_range =
      conn
      |> patch_json("/api/v1/portfolios/#{portfolio.id}", %{
        "portfolio" => %{"cash_target_weight" => "2"}
      })
      |> json_response(422)

    assert %{"errors" => %{"cash_target_weight" => [_]}} = out_of_range

    not_a_number =
      conn
      |> patch_json("/api/v1/portfolios/#{portfolio.id}", %{
        "portfolio" => %{"cash_target_weight" => "not-a-number"}
      })
      |> json_response(422)

    assert %{"errors" => %{"cash_target_weight" => [_]}} = not_a_number

    missing =
      conn
      |> patch_json("/api/v1/portfolios/999999", %{
        "portfolio" => %{"cash_target_weight" => "0.05"}
      })
      |> json_response(404)

    assert missing == %{"errors" => %{"detail" => "not found"}}

    invalid_id =
      conn
      |> patch_json("/api/v1/portfolios/not-an-id", %{
        "portfolio" => %{"cash_target_weight" => "0.05"}
      })
      |> json_response(404)

    assert invalid_id == %{"errors" => %{"detail" => "not found"}}
  end
end
