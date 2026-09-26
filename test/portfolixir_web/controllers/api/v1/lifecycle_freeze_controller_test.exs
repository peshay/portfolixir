defmodule PortfolixirWeb.Api.V1.LifecycleFreezeControllerTest do
  # ADR-0050 §11 first bullet and §16 invariant 15 over the API (risk-tier:
  # money and identity, ADR-0036): a frozen identity field answers 422 with
  # a field error that counts what froze it, and the row is left alone. The
  # MCP tools `portfolixir.cash_accounts.update` and
  # `portfolixir.securities.update` call these routes and say so in their
  # descriptions (mcp-server/test/tools.test.ts).
  use PortfolixirWeb.ConnCase, async: true

  alias Portfolixir.Catalog
  alias Portfolixir.Journal
  alias Portfolixir.Portfolios
  alias Portfolixir.WorldFixtures

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    %{conn: conn}
  end

  defp updates(resource_type, id) do
    Journal.list_entries(
      resource_type: resource_type,
      operation: :update,
      resource_id: to_string(id)
    )
  end

  # User story:
  # As the agent correcting an account over the API,
  # I want a currency change on a booked account refused with a field error
  # that says what froze it,
  # so that I never re-denominate booked history by accident and know why the
  # change did not land.
  #
  # Acceptance criteria:
  # - PATCH /api/v1/cash_accounts/:id with a new `currency_code` on an account
  #   a transaction or a depot references answers 422 with
  #   errors.currency_code counting the references; the account keeps its
  #   currency and nothing is journaled.
  # - The same PATCH with only a name, or with the stored currency resent,
  #   answers 200.
  test "a booked cash account answers 422 on a currency change", %{conn: conn} do
    world = WorldFixtures.base_world(cash_name: "Giro")
    WorldFixtures.deposit!(world, "100", ~D[2026-01-02])
    id = world.cash.id

    assert %{"errors" => errors} =
             conn
             |> patch("/api/v1/cash_accounts/#{id}", %{cash_account: %{currency_code: "USD"}})
             |> json_response(422)

    assert errors == %{
             "currency_code" => [
               "is frozen once referenced (1 securities account, 1 transaction)"
             ]
           }

    assert Portfolios.get_cash_account(id).currency_code == "EUR"
    assert updates("cash_account", id) == []

    assert %{"data" => %{"name" => "Giro (main)", "currency_code" => "EUR"}} =
             conn
             |> patch("/api/v1/cash_accounts/#{id}", %{
               cash_account: %{name: "Giro (main)", currency_code: "eur"}
             })
             |> json_response(200)
  end

  # User story:
  # As the agent correcting a security's master data over the API,
  # I want a currency change on a security with bookings or quotes refused
  # with a field error,
  # so that its price history and bookings keep the currency they are stated
  # in.
  #
  # Acceptance criteria:
  # - PATCH /api/v1/securities/:id with a new `currency_code` on a security
  #   with a transaction or a quote answers 422 with errors.currency_code
  #   counting them; the security keeps its currency.
  # - A security with neither still changes currency over the same route.
  test "a security with bookings or quotes answers 422 on a currency change", %{conn: conn} do
    world = WorldFixtures.base_world()
    booked = WorldFixtures.create_security!(name: "Booked ETF", ticker: "BKD")
    WorldFixtures.buy!(world, booked)
    WorldFixtures.put_quote!(booked, ~D[2026-01-02], "100")
    fresh = WorldFixtures.create_security!(name: "Fresh ETF", ticker: "FRSH")

    assert %{"errors" => errors} =
             conn
             |> patch("/api/v1/securities/#{booked.id}", %{security: %{currency_code: "USD"}})
             |> json_response(422)

    assert errors == %{"currency_code" => ["is frozen once referenced (1 quote, 1 transaction)"]}
    assert Catalog.get_security(booked.id).currency_code == "EUR"
    assert updates("security", booked.id) == []

    assert %{"data" => %{"currency_code" => "USD"}} =
             conn
             |> patch("/api/v1/securities/#{fresh.id}", %{security: %{currency_code: "USD"}})
             |> json_response(200)
  end

  # User story:
  # As the maintainer of the composite keys that pin bookings to their
  # portfolio,
  # I want the API never to move an account or a depot to another portfolio,
  # so that the frozen binding of a referenced account holds on this path
  # too — here more strictly than the changeset's freeze, because the API
  # never forwards `portfolio_id` on an update at all (ADR-0024; ADR-0050 §14
  # puts moving accounts between portfolios out of scope).
  #
  # Acceptance criteria:
  # - A PATCH carrying `portfolio_id` for a referenced cash account or depot
  #   leaves the binding unchanged; the other fields in the same PATCH land.
  test "the API never moves a referenced account or depot to another portfolio", %{conn: conn} do
    world = WorldFixtures.base_world()
    WorldFixtures.deposit!(world, "100", ~D[2026-01-02])

    {:ok, other} =
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "Other",
        base_currency_code: "EUR"
      })

    conn
    |> patch("/api/v1/cash_accounts/#{world.cash.id}", %{
      cash_account: %{portfolio_id: other.id, name: "Moved?"}
    })
    |> json_response(200)

    conn
    |> patch("/api/v1/securities_accounts/#{world.depot.id}", %{
      securities_account: %{portfolio_id: other.id, name: "Moved depot?"}
    })
    |> json_response(200)

    assert %{portfolio_id: portfolio_id, name: "Moved?"} =
             Portfolios.get_cash_account(world.cash.id)

    assert portfolio_id == world.portfolio.id

    assert %{portfolio_id: ^portfolio_id, name: "Moved depot?"} =
             Portfolios.get_securities_account(world.depot.id)
  end
end
