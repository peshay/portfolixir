defmodule PortfolixirWeb.ApiV1SecuritiesAccountsTest do
  use PortfolixirWeb.ConnCase

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1, buy!: 3]

  @auth {"authorization", "Bearer test-api-token"}

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header(elem(@auth, 0), elem(@auth, 1))
  end

  defp get_json(conn, path), do: conn |> api_conn() |> get(path)
  defp post_json(conn, path, body), do: conn |> api_conn() |> post(path, Jason.encode!(body))
  defp patch_json(conn, path, body), do: conn |> api_conn() |> patch(path, Jason.encode!(body))
  defp delete_json(conn, path), do: conn |> api_conn() |> delete(path)

  # User story:
  # As an API client (and the LLM I connect over MCP),
  # I want full CRUD over securities accounts (depots) with clear errors,
  # so that I can manage where holdings live entirely through the JSON API.
  #
  # Acceptance criteria:
  # - GET lists depots and GET /:id returns one; an unknown or non-numeric id
  #   returns 404.
  # - POST creates a depot (201) and rejects invalid attrs (422).
  # - PATCH updates a depot, never moves it to another portfolio, and returns
  #   404 for unknown ids / 422 for invalid attrs.
  # - DELETE removes an unreferenced depot (204), returns 404 for unknown ids,
  #   and 409 when the depot is referenced by transactions.

  test "lists and shows securities accounts", %{conn: conn} do
    %{depot: depot} = base_world(name: "Depots")

    listed = get_json(conn, "/api/v1/securities_accounts") |> json_response(200)
    assert Enum.any?(listed["data"], &(&1["id"] == depot.id))

    shown = get_json(conn, "/api/v1/securities_accounts/#{depot.id}") |> json_response(200)
    assert shown["data"]["id"] == depot.id
    assert shown["data"]["name"] == "Main Depot"
  end

  test "show returns 404 for unknown and non-numeric ids", %{conn: conn} do
    assert get_json(conn, "/api/v1/securities_accounts/999999") |> json_response(404) ==
             %{"errors" => %{"detail" => "not found"}}

    assert get_json(conn, "/api/v1/securities_accounts/not-a-number") |> json_response(404) ==
             %{"errors" => %{"detail" => "not found"}}
  end

  test "creates a depot and rejects invalid attributes", %{conn: conn} do
    %{portfolio: portfolio, cash: cash} = base_world(name: "Create")

    created =
      post_json(conn, "/api/v1/securities_accounts", %{
        "securities_account" => %{
          "portfolio_id" => portfolio.id,
          "cash_account_id" => cash.id,
          "name" => "Second Depot"
        }
      })

    assert %{"data" => data} = json_response(created, 201)
    assert data["name"] == "Second Depot"
    assert data["portfolio_id"] == portfolio.id

    rejected =
      post_json(conn, "/api/v1/securities_accounts", %{"securities_account" => %{"name" => ""}})

    assert %{"errors" => errors} = json_response(rejected, 422)
    assert errors != %{}
  end

  test "updates a depot without moving it to another portfolio", %{conn: conn} do
    %{portfolio: portfolio, depot: depot} = base_world(name: "Update")

    updated =
      patch_json(conn, "/api/v1/securities_accounts/#{depot.id}", %{
        "securities_account" => %{"name" => "Renamed Depot", "portfolio_id" => 999_999}
      })

    assert %{"data" => data} = json_response(updated, 200)
    assert data["name"] == "Renamed Depot"
    # portfolio_id is dropped from the update, so the depot stays put.
    assert data["portfolio_id"] == portfolio.id
  end

  test "update returns 404 for unknown ids and 422 for invalid attrs", %{conn: conn} do
    %{depot: depot} = base_world(name: "UpdateErr")

    assert patch_json(conn, "/api/v1/securities_accounts/999999", %{
             "securities_account" => %{"name" => "x"}
           })
           |> json_response(404) == %{"errors" => %{"detail" => "not found"}}

    assert patch_json(conn, "/api/v1/securities_accounts/not-a-number", %{
             "securities_account" => %{"name" => "x"}
           })
           |> json_response(404) == %{"errors" => %{"detail" => "not found"}}

    invalid =
      patch_json(conn, "/api/v1/securities_accounts/#{depot.id}", %{
        "securities_account" => %{"name" => ""}
      })

    assert %{"errors" => errors} = json_response(invalid, 422)
    assert errors != %{}
  end

  test "deletes an unreferenced depot and 404s for unknown ids", %{conn: conn} do
    %{portfolio: portfolio, cash: cash} = base_world(name: "Delete")

    {:ok, spare} =
      Portfolixir.Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Spare Depot"
      })

    assert delete_json(conn, "/api/v1/securities_accounts/#{spare.id}") |> response(204)

    assert delete_json(conn, "/api/v1/securities_accounts/999999") |> json_response(404) ==
             %{"errors" => %{"detail" => "not found"}}

    assert delete_json(conn, "/api/v1/securities_accounts/not-a-number") |> json_response(404) ==
             %{"errors" => %{"detail" => "not found"}}
  end

  test "refuses to delete a depot referenced by a transaction", %{conn: conn} do
    world = base_world(name: "Referenced")
    security = create_security!(name: "Held", ticker: "HELD")
    buy!(world, security, quantity: "1", price: "100")

    response = delete_json(conn, "/api/v1/securities_accounts/#{world.depot.id}")

    assert %{"errors" => %{"detail" => detail}} = json_response(response, 409)
    assert detail =~ "referenced"
  end
end
