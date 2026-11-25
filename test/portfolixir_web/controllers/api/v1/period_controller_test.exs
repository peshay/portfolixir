defmodule PortfolixirWeb.Api.V1.PeriodControllerTest do
  # Sprint 32 T2 (I59; ADR-0062's amendment of 2026-11-25, point 6): the
  # stored periods over the API — GET, POST, PUT and DELETE
  # /api/v1/periods — and `saved:<id>` wherever the vocabulary is read.
  # Every name is synthetic.
  #
  # group: :periods -- every module that creates a period joins it (the
  # create's count lock, `Portfolixir.LockTable` row 31).
  use PortfolixirWeb.ConnCase, async: true, group: :periods

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quotes!: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Clock
  alias Portfolixir.Journal
  alias Portfolixir.Periods

  defp authed(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  defp entries, do: Journal.list_entries(resource_type: "period", order: :asc)

  # User story:
  # As the agent the operator runs,
  # I want to list, create, change and delete the operator's own periods,
  # so that „Sommer 2026“ the agent made is the operator's choice on every
  # device, and a change I make reaches every widget pinned to it.
  #
  # Acceptance criteria:
  # - POST {period: {name, from, to?}} answers 201 with id, key
  #   (saved:<id>), name, from, to (null: until today) and lock_version 1;
  #   journaled under the token.
  # - GET lists them in the order made; PUT {period: {name, from, to,
  #   lock_version}} replaces, a stale lock_version answers 409 with
  #   errors.stored; DELETE answers 204.
  # - A refused write answers 422 naming the field: an empty and a
  #   41-character name, a control character, from after to, a key the
  #   write does not take; the 51st answers 422 too_many_periods.
  # - An unknown id answers 404.
  test "a period is created, listed, replaced and deleted, journaled under the token",
       %{conn: conn} do
    %{"data" => created} =
      conn
      |> authed()
      |> post("/api/v1/periods", %{
        "period" => %{"name" => "Seit Umschichtung", "from" => "2025-03-01"}
      })
      |> json_response(201)

    id = created["id"]

    assert created == %{
             "id" => id,
             "key" => "saved:#{id}",
             "name" => "Seit Umschichtung",
             "from" => "2025-03-01",
             "to" => nil,
             "lock_version" => 1
           }

    assert [%{operation: :create, actor_type: :api_token_rw}] = entries()

    assert %{"data" => [^created]} =
             conn |> authed() |> get("/api/v1/periods") |> json_response(200)

    %{"data" => replaced} =
      conn
      |> authed()
      |> put("/api/v1/periods/#{id}", %{
        "period" => %{
          "name" => "Seit Umschichtung",
          "from" => "2025-04-01",
          "to" => "2025-12-31",
          "lock_version" => 1
        }
      })
      |> json_response(200)

    assert replaced["lock_version"] == 2
    assert replaced["to"] == "2025-12-31"

    %{"errors" => errors} =
      conn
      |> authed()
      |> put("/api/v1/periods/#{id}", %{
        "period" => %{"name" => "Alt", "from" => "2025-01-01", "to" => nil, "lock_version" => 1}
      })
      |> json_response(409)

    assert errors["code"] == "stale"
    assert errors["stored"] == replaced

    assert conn |> authed() |> delete("/api/v1/periods/#{id}") |> response(204)
    assert %{"data" => []} = conn |> authed() |> get("/api/v1/periods") |> json_response(200)
    assert conn |> authed() |> delete("/api/v1/periods/#{id}") |> json_response(404)

    assert conn
           |> authed()
           |> put("/api/v1/periods/#{id}", %{
             "period" => %{
               "name" => "X",
               "from" => "2025-01-01",
               "to" => nil,
               "lock_version" => 2
             }
           })
           |> json_response(404)

    assert Enum.map(entries(), & &1.operation) == [:create, :update, :delete]
  end

  test "a refused write names its field and writes nothing", %{conn: conn} do
    post = fn body ->
      conn |> authed() |> post("/api/v1/periods", %{"period" => body}) |> json_response(422)
    end

    for {body, field} <- [
          {%{"name" => "", "from" => "2025-01-01"}, "name"},
          {%{"name" => String.duplicate("x", 41), "from" => "2025-01-01"}, "name"},
          {%{"name" => "Zwei\nZeilen", "from" => "2025-01-01"}, "name"},
          {%{"name" => "Rückwärts", "from" => "2026-05-02", "to" => "2026-05-01"}, "to"},
          {%{"name" => "Ohne Anfang"}, "from"},
          {%{"name" => "Extra", "from" => "2025-01-01", "lock_version" => 1}, "lock_version"}
        ] do
      assert %{"errors" => %{^field => [_ | _]}} = post.(body), inspect(body)
    end

    assert %{"errors" => %{"color" => [_]}} =
             conn
             |> authed()
             |> post("/api/v1/periods?color=red", %{
               "period" => %{"name" => "X", "from" => "2025-01-01"}
             })
             |> json_response(422)

    assert Periods.list_saved() == []
    assert entries() == []

    for n <- 1..50 do
      {:ok, _} =
        Periods.create_saved(Actor.owner_ui(), %{
          "name" => "Synthetic #{n}",
          "from" => "2025-01-01"
        })
    end

    assert %{"errors" => %{"code" => "too_many_periods"}} =
             post.(%{"name" => "Synthetic 51", "from" => "2025-01-01"})
  end

  # User story:
  # As the agent the operator runs,
  # I want `period=saved:<id>` on the performance family's reads,
  # so that the figure I quote for „Seit Umschichtung“ is the one the
  # operator's widget pinned to it shows.
  #
  # Acceptance criteria:
  # - GET /api/v1/performance?period=saved:<id> answers what from/to over
  #   the stored span answers; an open period ends today.
  # - A deleted period's key answers 422 on period, as an unknown key does.
  test "saved:<id> on a performance read answers its span; a deleted one 422", %{conn: conn} do
    today = Clock.today()
    first = Date.new!(today.year - 1, 1, 2)
    world = base_world(name: "Saved", cash_name: "Cash", depot_name: "Depot")
    fund = create_security!(name: "Saved Fund", ticker: "SVF")
    deposit!(world, "5000", first)
    buy!(world, fund, quantity: "10", price: "100", date: first)
    put_quotes!(fund, [{first, "100"}, {Date.new!(today.year - 1, 7, 31), "120"}, {today, "130"}])

    {:ok, period} =
      Periods.create_saved(Actor.owner_ui(), %{
        "name" => "Seit Juli",
        "from" => Date.new!(today.year - 1, 7, 1)
      })

    data = fn query ->
      conn
      |> authed()
      |> get("/api/v1/performance?" <> query)
      |> json_response(200)
      |> Map.fetch!("data")
    end

    by_key = data.("period=saved:#{period.id}")
    spelled = data.("from=#{period.from}&to=#{today}")
    assert Map.drop(by_key, ~w(as_of stale)) == Map.drop(spelled, ~w(as_of stale))

    {:ok, _} = Periods.delete_saved(Actor.owner_ui(), period.id)

    assert conn
           |> authed()
           |> get("/api/v1/performance?period=saved:#{period.id}")
           |> json_response(422) == %{"errors" => %{"period" => ["is invalid"]}}
  end
end
