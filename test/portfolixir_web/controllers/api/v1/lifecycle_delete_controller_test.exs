defmodule PortfolixirWeb.Api.V1.LifecycleDeleteControllerTest do
  # ADR-0050 §11 over the API (risk-tier: audit, ADR-0036): the three delete
  # routes answer a referenced row with 409, naming what references it,
  # counted, and the remedy with its route; an unreferenced row's memberships
  # are removed journaled under the API token before the row goes.
  use PortfolixirWeb.ConnCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Journal
  alias Portfolixir.Knowledge
  alias Portfolixir.Portfolios
  alias Portfolixir.WorldFixtures

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    %{conn: conn}
  end

  # User story:
  # As the agent tidying up accounts over the API,
  # I want a refused delete to tell me what references the account, counted,
  # and the route of the remedy,
  # so that I merge the account instead of guessing why the delete failed.
  #
  # Acceptance criteria:
  # - DELETE /api/v1/cash_accounts/:id of an account a transaction or a depot
  #   references answers 409 with errors.referenced_by (the referencing
  #   tables, counted), errors.remedy "merge" and errors.remedy_route naming
  #   GET /api/v1/cash_accounts/:id/merge_preview?target_id=.
  # - The detail says the same in words, and the account survives.
  test "a referenced cash account answers 409 with what references it and the merge route",
       %{conn: conn} do
    world = WorldFixtures.base_world(cash_name: "Giro")
    WorldFixtures.deposit!(world, "100", ~D[2026-01-02])
    id = world.cash.id

    assert %{"errors" => errors} =
             conn |> delete("/api/v1/cash_accounts/#{id}") |> json_response(409)

    assert errors["referenced_by"] == %{"transactions" => 1, "securities_accounts" => 1}
    assert errors["remedy"] == "merge"
    assert errors["remedy_route"] == "GET /api/v1/cash_accounts/#{id}/merge_preview?target_id="

    assert errors["detail"] =~
             "cash account is referenced by existing records (1 securities account, 1 transaction)"

    assert errors["detail"] =~ "merge it into"
    assert errors["detail"] =~ "GET /api/v1/cash_accounts/#{id}/merge_preview?target_id="
    assert Portfolios.get_cash_account(id)
  end

  # User story:
  # As the agent tidying up depots over the API,
  # I want the same answer for a referenced depot,
  # so that one reading of the 409 serves both kinds of account.
  #
  # Acceptance criteria:
  # - DELETE /api/v1/securities_accounts/:id of a depot a transaction
  #   references answers 409 with the transactions counted, remedy "merge" and
  #   the depot's merge preview route.
  test "a referenced depot answers 409 with what references it and the merge route",
       %{conn: conn} do
    world = WorldFixtures.base_world()
    security = WorldFixtures.create_security!()
    WorldFixtures.buy!(world, security)
    WorldFixtures.sell!(world, security)
    id = world.depot.id

    assert %{"errors" => errors} =
             conn |> delete("/api/v1/securities_accounts/#{id}") |> json_response(409)

    assert errors["referenced_by"] == %{"transactions" => 2}
    assert errors["remedy"] == "merge"

    assert errors["remedy_route"] ==
             "GET /api/v1/securities_accounts/#{id}/merge_preview?target_id="

    assert errors["detail"] =~
             "securities account is referenced by existing records (2 transactions)"

    assert Portfolios.get_securities_account(id)
  end

  # User story:
  # As the agent removing a duplicate security over the API,
  # I want the 409 to count what references it and point me at the remedy
  # that can actually work,
  # so that I merge a duplicate, and retire a security whose research log
  # can neither move nor vanish.
  #
  # Acceptance criteria:
  # - A security with bookings and quotes answers 409 with both counted,
  #   remedy "merge" and GET /api/v1/securities/:id/merge_preview?target_id=.
  # - A security with a research note answers 409 with remedy "retire" and
  #   PATCH /api/v1/securities/:id as its route, because a merge refuses a
  #   source with notes (ADR-0050 §9).
  test "a referenced security answers 409 with the remedy a merge could honour",
       %{conn: conn} do
    world = WorldFixtures.base_world()
    booked = WorldFixtures.create_security!(name: "Booked ETF", ticker: "BKD")
    WorldFixtures.buy!(world, booked)
    WorldFixtures.put_quote!(booked, ~D[2026-01-02], "100")

    assert %{"errors" => errors} =
             conn |> delete("/api/v1/securities/#{booked.id}") |> json_response(409)

    assert errors["referenced_by"] == %{"transactions" => 1, "security_quotes" => 1}
    assert errors["remedy"] == "merge"

    assert errors["remedy_route"] ==
             "GET /api/v1/securities/#{booked.id}/merge_preview?target_id="

    assert errors["detail"] =~
             "security is referenced by existing records (1 quote, 1 transaction)"

    noted = WorldFixtures.create_security!(name: "Noted ETF", ticker: "NTD")

    {:ok, _note} =
      Knowledge.append_note(Actor.owner_ui(), %{
        security_id: noted.id,
        author: "agent",
        kind: "evidence",
        body: "a dated finding",
        source_quality: "primary",
        as_of: ~D[2026-08-01]
      })

    assert %{"errors" => errors} =
             conn |> delete("/api/v1/securities/#{noted.id}") |> json_response(409)

    assert errors["referenced_by"] == %{"security_notes" => 1}
    assert errors["remedy"] == "retire"
    assert errors["remedy_route"] == "PATCH /api/v1/securities/#{noted.id}"
    assert errors["detail"] =~ "retire it instead"
    assert Catalog.get_security(booked.id)
    assert Catalog.get_security(noted.id)
  end

  # User story:
  # As the operator reading the journal after the agent deleted an account,
  # I want the account's bucket links removed under the agent's token,
  # journaled, before the account's own delete,
  # so that the API path leaves the same record the context does.
  #
  # Acceptance criteria:
  # - DELETE of an unreferenced cash account with bucket links answers 204.
  # - Its links are gone and one cash_account_bucket_assignment entry,
  #   attributed to the API token, records their removal.
  # - DELETE of an unreferenced depot with default buckets answers 204 and
  #   journals their removal the same way.
  test "an unreferenced account's bucket links are removed journaled under the token",
       %{conn: conn} do
    world = WorldFixtures.base_world()
    {:ok, family} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Family", dimension: "tag"})

    {:ok, spare} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        name: "Spare",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        name: "Spare Depot"
      })

    :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), spare, [family.id])
    :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), depot, [family.id])

    assert conn |> delete("/api/v1/cash_accounts/#{spare.id}") |> response(204)
    assert conn |> delete("/api/v1/securities_accounts/#{depot.id}") |> response(204)

    assert Buckets.cash_account_bucket_ids(spare.id) == []
    assert Buckets.depot_default_bucket_ids(depot.id) == []

    assert [%{actor_type: :api_token_rw, after: %{"bucket_ids" => []}}] =
             Journal.list_entries(resource_type: "cash_account_bucket_assignment")
             |> Enum.filter(&(&1.after["cash_account_id"] == spare.id))
             |> Enum.filter(&(&1.actor_type == :api_token_rw))

    assert [%{actor_type: :api_token_rw, after: %{"bucket_ids" => []}}] =
             Journal.list_entries(resource_type: "depot_bucket_assignment")
             |> Enum.filter(&(&1.after["securities_account_id"] == depot.id))
             |> Enum.filter(&(&1.actor_type == :api_token_rw))
  end

  test "a delete of an id that is gone answers 404", %{conn: conn} do
    world = WorldFixtures.base_world()

    {:ok, spare} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        name: "Spare",
        currency_code: "EUR"
      })

    assert conn |> delete("/api/v1/cash_accounts/#{spare.id}") |> response(204)
    assert conn |> delete("/api/v1/cash_accounts/#{spare.id}") |> json_response(404)
  end
end
