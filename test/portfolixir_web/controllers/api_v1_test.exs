defmodule PortfolixirWeb.ApiV1Test do
  use PortfolixirWeb.ConnCase

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.QuoteSync.Fake, as: QuoteSyncFake
  alias Portfolixir.Catalog.Quotes
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

    assert %{"data" => %{"open_lots" => [_], "closed_trades" => [closed], "orphan_sells" => []}} =
             response

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
end
