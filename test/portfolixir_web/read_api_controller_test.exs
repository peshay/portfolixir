defmodule PortfolixirWeb.ReadAPIControllerTest do
  use PortfolixirWeb.ConnCase, async: true

  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias PortfolixirWeb.Router

  defp create_currency do
    :ok = Catalog.ensure_mvp_currencies!()
    :ok
  end

  defp create_portfolio(name) do
    {:ok, portfolio} =
      Portfolios.create_portfolio(%{
        name: name,
        description: "Synthetic portfolio",
        base_currency_code: "EUR"
      })

    portfolio
  end

  defp create_accounts(portfolio) do
    {:ok, deposit_account} =
      Portfolios.create_deposit_account(%{
        portfolio_id: portfolio.id,
        name: "Cash",
        currency_code: "EUR"
      })

    {:ok, securities_account} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        name: "Depot",
        currency_code: "EUR",
        reference_deposit_account_id: deposit_account.id
      })

    {deposit_account, securities_account}
  end

  defp create_security do
    {:ok, security} =
      Catalog.create_security(%{
        name: "Synthetic ETF",
        symbol: "SYN",
        currency_code: "EUR"
      })

    security
  end

  defp post_transactions(portfolio, deposit_account, securities_account, security) do
    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        deposit_account_id: deposit_account.id,
        type: "deposit",
        date: ~D[2026-01-01],
        currency_code: "EUR",
        amount: Decimal.new("1000.00")
      })

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        deposit_account_id: deposit_account.id,
        type: "withdrawal",
        date: ~D[2026-01-02],
        currency_code: "EUR",
        amount: Decimal.new("25.00")
      })

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: securities_account.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-01-03],
        currency_code: "EUR",
        quantity: Decimal.new("10.00"),
        price: Decimal.new("10.00"),
        amount: Decimal.new("100.00")
      })

    {:ok, _} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: securities_account.id,
        security_id: security.id,
        type: "sell",
        date: ~D[2026-01-04],
        currency_code: "EUR",
        quantity: Decimal.new("4.00"),
        price: Decimal.new("12.00"),
        amount: Decimal.new("48.00")
      })
  end

  setup do
    old_auth_config = Application.get_env(:portfolixir, PortfolixirWeb.Plugs.ReadApiKeyAuth, [])

    on_exit(fn ->
      Application.put_env(:portfolixir, PortfolixirWeb.Plugs.ReadApiKeyAuth, old_auth_config)
    end)

    create_currency()
    first_portfolio = create_portfolio("Primary portfolio")
    second_portfolio = create_portfolio("Secondary portfolio")

    {first_deposit, first_securities} = create_accounts(first_portfolio)
    {second_deposit, second_securities} = create_accounts(second_portfolio)

    security = create_security()

    post_transactions(first_portfolio, first_deposit, first_securities, security)
    post_transactions(second_portfolio, second_deposit, second_securities, security)

    %{first_portfolio: first_portfolio, second_portfolio: second_portfolio}
  end

  test "returns 401 when read API auth is enabled and no key is provided", %{conn: conn} do
    Application.put_env(:portfolixir, PortfolixirWeb.Plugs.ReadApiKeyAuth,
      enabled: true,
      api_key: "test-read-key"
    )

    response = get(conn, "/api/read/positions")
    assert response.status == 401
    assert json_response(response, 401)["error"] == "unauthorized"
  end

  test "returns 401 when read API auth is enabled but key is not configured", %{conn: conn} do
    Application.put_env(:portfolixir, PortfolixirWeb.Plugs.ReadApiKeyAuth,
      enabled: true,
      api_key: nil
    )

    response = get(conn, "/api/read/positions")
    assert response.status == 401
    assert json_response(response, 401)["error"] == "unauthorized"
  end

  test "returns 200 when read API auth is enabled and valid key is provided", %{
    conn: conn,
    first_portfolio: first_portfolio
  } do
    Application.put_env(:portfolixir, PortfolixirWeb.Plugs.ReadApiKeyAuth,
      enabled: true,
      api_key: "test-read-key"
    )

    response =
      conn
      |> put_req_header("x-api-key", "test-read-key")
      |> get("/api/read/positions")

    assert json_response(response, 200)["portfolio_id"] == first_portfolio.id
  end

  test "all read endpoints return 200 JSON", %{conn: conn, first_portfolio: first_portfolio} do
    snapshot = get(conn, "/api/read/portfolio_snapshot")
    assert json_response(snapshot, 200)["portfolio"]["id"] == first_portfolio.id

    positions = get(conn, "/api/read/positions")
    assert json_response(positions, 200)["portfolio_id"] == first_portfolio.id

    transactions = get(conn, "/api/read/transactions")
    assert json_response(transactions, 200)["portfolio_id"] == first_portfolio.id

    cash_balances = get(conn, "/api/read/cash_balances")
    assert json_response(cash_balances, 200)["portfolio_id"] == first_portfolio.id
  end

  test "endpoint without portfolio_id uses the first portfolio", %{
    conn: conn,
    first_portfolio: first_portfolio
  } do
    positions = get(conn, "/api/read/positions")
    assert json_response(positions, 200)["portfolio_id"] == first_portfolio.id
  end

  test "endpoint with portfolio_id scopes data to that portfolio", %{
    conn: conn,
    second_portfolio: second_portfolio
  } do
    positions =
      get(conn, "/api/read/positions", %{"portfolio_id" => Integer.to_string(second_portfolio.id)})

    assert json_response(positions, 200)["portfolio_id"] == second_portfolio.id
    assert length(json_response(positions, 200)["positions"]) > 0
  end

  test "transactions endpoint returns only the selected portfolio transactions", %{
    conn: conn,
    first_portfolio: first_portfolio,
    second_portfolio: second_portfolio
  } do
    response =
      json_response(
        get(conn, "/api/read/transactions", %{
          "portfolio_id" => Integer.to_string(first_portfolio.id)
        }),
        200
      )

    assert length(response["transactions"]) == 4

    assert Enum.all?(
             response["transactions"],
             &(&1["type"] in ["deposit", "withdrawal", "buy", "sell"])
           )

    assert response["portfolio_id"] == first_portfolio.id
    refute response["portfolio_id"] == second_portfolio.id
  end

  test "positions endpoint reflects buy/sell derived positions", %{
    conn: conn,
    first_portfolio: first_portfolio
  } do
    response =
      json_response(
        get(conn, "/api/read/positions", %{
          "portfolio_id" => Integer.to_string(first_portfolio.id)
        }),
        200
      )

    [position] = response["positions"]
    assert Decimal.equal?(Decimal.new(position["quantity"]), Decimal.new("6"))
    assert response["portfolio_id"] == first_portfolio.id
    assert is_binary(position["quantity"])
  end

  test "cash_balances endpoint reflects deposit, withdrawal and trade cash impact", %{
    conn: conn,
    first_portfolio: first_portfolio
  } do
    response =
      json_response(
        get(conn, "/api/read/cash_balances", %{
          "portfolio_id" => Integer.to_string(first_portfolio.id)
        }),
        200
      )

    assert response["portfolio_id"] == first_portfolio.id

    [first_balance] = response["cash_balances"]["balances"]

    assert Decimal.equal?(Decimal.new(first_balance["balance"]), Decimal.new("923.00"))
  end

  test "unknown portfolio_id returns 404 JSON", %{conn: conn} do
    response = get(conn, "/api/read/positions", %{"portfolio_id" => "999999"})
    assert response.status == 404
    assert json_response(response, 404)["error"] == "portfolio not found"
  end

  test "no non-GET route is added under /api/read" do
    read_routes =
      Enum.filter(Router.__routes__(), fn route ->
        String.starts_with?(route.path, "/api/read")
      end)

    Enum.each(read_routes, fn route ->
      assert route.verb == :get
    end)
  end
end
