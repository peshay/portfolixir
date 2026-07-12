defmodule PortfolixirWeb.ApiV1PortfolioDeprecationTest do
  use PortfolixirWeb.ConnCase

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

  # User story (ADR-0024 modification 1):
  # As an API/MCP consumer still writing portfolios,
  # I want portfolio write endpoints to keep working but signal deprecation,
  # so that automation learns to move to buckets/views before the records are
  # merged away, while nothing breaks in phase 1.
  #
  # Acceptance criteria:
  # - POST /api/v1/portfolios still creates (201) and carries
  #   `Deprecation: true`.
  # - PATCH /api/v1/portfolios/:id still updates (200) and carries
  #   `Deprecation: true`.
  # - Read endpoints (GET /api/v1/portfolios) carry no deprecation header.
  test "portfolio write endpoints keep working and signal deprecation", %{conn: conn} do
    create =
      post_json(conn, "/api/v1/portfolios", %{
        "portfolio" => %{"name" => "Compat", "base_currency_code" => "EUR"}
      })

    created = create |> json_response(201) |> Map.fetch!("data")
    assert get_resp_header(create, "deprecation") == ["true"]

    update =
      patch_json(conn, "/api/v1/portfolios/#{created["id"]}", %{
        "portfolio" => %{"name" => "Compat Renamed"}
      })

    assert update |> json_response(200) |> get_in(["data", "name"]) == "Compat Renamed"
    assert get_resp_header(update, "deprecation") == ["true"]

    index = conn |> api_conn() |> get("/api/v1/portfolios")
    assert json_response(index, 200)
    assert get_resp_header(index, "deprecation") == []
  end

  # User story (ADR-0024):
  # As an API/MCP consumer creating bookkeeping entities,
  # I want cash accounts and depots to be creatable without naming a
  # portfolio,
  # so that the internal compatibility record never forces a grouping
  # decision on clients either.
  #
  # Acceptance criteria:
  # - POST /api/v1/cash_accounts without portfolio_id binds the account to
  #   the deterministic internal default portfolio.
  # - POST /api/v1/securities_accounts without portfolio_id does the same.
  # - An explicit portfolio_id keeps winning (compatibility).
  test "cash accounts and depots are creatable without a portfolio id", %{conn: conn} do
    cash =
      conn
      |> post_json("/api/v1/cash_accounts", %{
        "cash_account" => %{"name" => "Cash EUR", "currency_code" => "EUR"}
      })
      |> json_response(201)
      |> Map.fetch!("data")

    default = Portfolios.get_cash_account(cash["id"]).portfolio_id
    assert Portfolios.get_portfolio(default).name == "Default"

    depot =
      conn
      |> post_json("/api/v1/securities_accounts", %{
        "securities_account" => %{"name" => "Depot", "cash_account_id" => cash["id"]}
      })
      |> json_response(201)
      |> Map.fetch!("data")

    assert Portfolios.get_securities_account(depot["id"]).portfolio_id == default

    # Explicit binding still wins for compatibility clients.
    explicit =
      conn
      |> post_json("/api/v1/portfolios", %{
        "portfolio" => %{"name" => "Explicit", "base_currency_code" => "EUR"}
      })
      |> json_response(201)
      |> Map.fetch!("data")

    bound =
      conn
      |> post_json("/api/v1/cash_accounts", %{
        "cash_account" => %{
          "portfolio_id" => explicit["id"],
          "name" => "Bound Cash",
          "currency_code" => "EUR"
        }
      })
      |> json_response(201)
      |> Map.fetch!("data")

    assert Portfolios.get_cash_account(bound["id"]).portfolio_id == explicit["id"]
  end
end
