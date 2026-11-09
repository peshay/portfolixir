defmodule PortfolixirWeb.Api.V1.ProviderCurrencyAttackControllerTest do
  # Sprint 28 plan D-8, carry-forward 1 (Q3 attack, #1415): the provider
  # currency is the quote sync's record alone, so no API write may set it.
  # The MCP tools `portfolixir.securities.create` and
  # `portfolixir.securities.update` call these routes. Every name and
  # identifier is synthetic.
  use PortfolixirWeb.ConnCase, async: true

  alias Portfolixir.Catalog
  alias Portfolixir.WorldFixtures

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    %{conn: conn}
  end

  # User story:
  # As the operator whose agent writes securities over the API,
  # I want `provider_currency` and `provider_currency_at` ignored on a create
  # and an update,
  # so that an agent can neither plant a finding in the currency_mismatch
  # set nor clear one the provider's answer stored.
  #
  # Acceptance criteria:
  # - PATCH /api/v1/securities/:id carrying both columns answers 200, lands
  #   its other fields, and leaves the stored provider currency and its time
  #   as they were (null, and a stored value alike).
  # - POST /api/v1/securities carrying both leaves them null.
  # - The set's answer over the API is unchanged by either.
  test "the API neither sets nor clears the provider currency", %{conn: conn} do
    fresh = WorldFixtures.create_security!(name: "Fresh Line", ticker: "FRSH")
    stated = WorldFixtures.create_security!(name: "Stated Line", ticker: "STAT")

    {:ok, _} =
      Catalog.put_provider_currency(
        Portfolixir.Actor.system_job("quote_sync"),
        stated,
        "USD",
        ~U[2026-11-09 08:15:00Z]
      )

    planted = %{provider_currency: "GBp", provider_currency_at: "2026-11-09T09:00:00Z"}

    assert %{"data" => %{"name" => "Fresh Line renamed"}} =
             conn
             |> patch("/api/v1/securities/#{fresh.id}", %{
               security: Map.put(planted, :name, "Fresh Line renamed")
             })
             |> json_response(200)

    assert %{provider_currency: nil, provider_currency_at: nil} = Catalog.get_security(fresh.id)

    conn
    |> patch("/api/v1/securities/#{stated.id}", %{
      security: %{provider_currency: nil, provider_currency_at: nil, note: "cleared?"}
    })
    |> json_response(200)

    assert %{provider_currency: "USD", provider_currency_at: ~U[2026-11-09 08:15:00Z]} =
             Catalog.get_security(stated.id)

    assert %{"data" => %{"id" => created_id}} =
             conn
             |> post("/api/v1/securities", %{
               security: Map.merge(planted, %{name: "Posted Line", currency_code: "EUR"})
             })
             |> json_response(201)

    assert %{provider_currency: nil} = Catalog.get_security(created_id)

    assert %{"data" => listed} =
             conn
             |> get("/api/v1/securities?data_quality=currency_mismatch")
             |> json_response(200)

    assert Enum.map(listed, & &1["id"]) == [stated.id]
  end
end
