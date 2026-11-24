defmodule PortfolixirWeb.ApiV1DeleteParamsTest do
  @moduledoc """
  Every `DELETE /api/v1/...` answers 422 for a query or body parameter it
  does not take, naming it (N-07; Sprint 25 retrospective, carry-forward 2):
  a parameter of a delete is honoured or refused, never dropped.

  The routes are read from the router rather than written out, so a DELETE
  route added later is swept by the same assertions without anyone having to
  remember to list it.
  """
  use PortfolixirWeb.ConnCase, async: true
  @moduletag :sweep

  import Portfolixir.WorldFixtures

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  @no_parameters "is unknown: this request takes no parameters"

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    %{conn: conn}
  end

  # User story (security review 2026-11, N-07; decision D-4):
  # As an agent that asks a delete a question before it deletes,
  # I want every DELETE route to refuse a parameter it does not take,
  # so that a safety parameter is honoured or refused and never ignored.
  #
  # Acceptance criteria:
  # - Every DELETE route under /api/v1 answers 422 for a query key and for a
  #   JSON body key it does not take, naming the key, and deletes nothing.
  # - `dry_run` is taken by the routes that offer a dry run and refused by
  #   every other DELETE route, in the query and in the body.
  # - The parameters a DELETE route takes are declared on the route in the
  #   router; the routes that declare any are pinned here.
  # - A declared parameter still reaches its action, and no other method is
  #   touched.
  test "every DELETE route refuses a parameter it does not take, in the query and in the body",
       %{conn: conn} do
    routes = delete_routes()
    assert length(routes) >= 27, "the router lists only #{length(routes)} DELETE routes"

    for route <- routes do
      path = concrete(route.path)
      refusal = [refusal(route)]

      assert %{"errors" => %{"dryRun" => ^refusal}} =
               conn |> delete(path <> "?dryRun=true") |> json_response(422),
             "DELETE #{route.path} with an unknown query key"

      assert %{"errors" => %{"confirm" => ^refusal}} =
               conn
               |> put_req_header("content-type", "application/json")
               |> delete(path, Jason.encode!(%{"confirm" => false}))
               |> json_response(422),
             "DELETE #{route.path} with an unknown body key"
    end
  end

  test "dry_run is taken by the routes that offer a dry run and refused by every other",
       %{conn: conn} do
    for route <- delete_routes() do
      path = concrete(route.path)

      if "dry_run" in takes(route) do
        # The dry run's own answer for a record that does not exist: the
        # parameter reached the action, and nothing answered 204.
        assert conn |> delete(path <> "?dry_run=true") |> json_response(404),
               "DELETE #{route.path}?dry_run=true"
      else
        refusal = [refusal(route)]

        assert %{"errors" => %{"dry_run" => ^refusal}} =
                 conn |> delete(path <> "?dry_run=true") |> json_response(422),
               "DELETE #{route.path}?dry_run=true"

        assert %{"errors" => %{"dry_run" => ^refusal}} =
                 conn
                 |> put_req_header("content-type", "application/json")
                 |> delete(path, Jason.encode!(%{"dry_run" => true}))
                 |> json_response(422),
               "DELETE #{route.path} with dry_run in the body"
      end
    end
  end

  test "a refused delete deletes nothing", %{conn: conn} do
    world =
      base_world(name: "Delete Params", cash_name: "Params Cash", depot_name: "Params Depot")

    security = create_security!(name: "Harrow Vale Mills plc", ticker: "HVM")
    buy = buy!(world, security, quantity: "10", price: "80")
    {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Params Core"})

    spare = base_world(name: "Delete Params Spare", cash_name: "Spare Cash", depot_name: "Spare")

    for {path, still_there?} <- [
          {"/api/v1/buckets/#{bucket.id}", fn -> Buckets.get_bucket(bucket.id) end},
          {"/api/v1/transactions/#{buy.id}", fn -> Ledger.get_transaction(buy.id) end},
          {"/api/v1/cash_accounts/#{spare.cash.id}",
           fn -> Portfolios.get_cash_account(spare.cash.id) end},
          {"/api/v1/securities_accounts/#{spare.depot.id}",
           fn -> Portfolios.get_securities_account(spare.depot.id) end}
        ] do
      assert %{"errors" => %{"dry_run" => [@no_parameters]}} =
               conn |> delete(path <> "?dry_run=true") |> json_response(422)

      assert %{"errors" => %{"dry_run" => [@no_parameters]}} =
               conn
               |> put_req_header("content-type", "application/json")
               |> delete(path, Jason.encode!(%{"dry_run" => true}))
               |> json_response(422)

      assert still_there?.(), "#{path} was deleted by a refused request"
    end

    # The same routes without a parameter are the delete itself.
    assert conn |> delete("/api/v1/buckets/#{bucket.id}") |> response(204)
    assert Buckets.get_bucket(bucket.id) == nil
  end

  test "the DELETE routes that take a parameter declare it in the router" do
    declared =
      for route <- delete_routes(), takes(route) != [], into: %{} do
        {String.replace_prefix(route.path, "/api/v1", ""), takes(route)}
      end

    assert declared == %{
             "/classifications/:id" => ~w(dry_run),
             "/classifications/:classification_id/categories/:id" => ~w(dry_run),
             "/views/:id" => ~w(dry_run),
             "/dashboards/:id" => ~w(dry_run),
             "/portfolios/:portfolio_id/targets/:category_id" => ~w(view plan_id),
             "/portfolios/:portfolio_id/position_targets/:category_id/:security_id" =>
               ~w(view plan_id),
             "/cash_accounts/:id/former_names" => ~w(name),
             "/securities_accounts/:id/former_names" => ~w(name)
           }
  end

  test "a declared parameter reaches its action", %{conn: conn} do
    world = base_world(name: "Declared", cash_name: "Declared Cash", depot_name: "Declared Depot")

    # The action's own answers, none of them the refusal of an unknown key.
    assert %{"errors" => %{"detail" => "not a former name of this account"}} =
             conn
             |> delete("/api/v1/cash_accounts/#{world.cash.id}/former_names?name=Never")
             |> json_response(404)

    assert %{"errors" => %{"detail" => "not a former name of this account"}} =
             conn
             |> delete("/api/v1/securities_accounts/#{world.depot.id}/former_names?name=Never")
             |> json_response(404)

    assert %{"errors" => %{"plan_id" => [_message]}} =
             conn
             |> delete("/api/v1/portfolios/#{world.portfolio.id}/targets/1?plan_id=1")
             |> json_response(422)

    assert conn
           |> delete("/api/v1/portfolios/#{world.portfolio.id}/targets/1?view=1")
           |> json_response(404)

    assert %{"errors" => %{"name" => ["is unknown: this delete takes only view, plan_id"]}} =
             conn
             |> delete("/api/v1/portfolios/#{world.portfolio.id}/targets/1?name=Never")
             |> json_response(422)
  end

  test "a read or a write of another method is not held to a delete's parameters", %{conn: conn} do
    assert conn |> get("/api/v1/buckets?dry_run=true") |> json_response(200)

    assert %{"data" => %{"name" => "Other Method"}} =
             conn
             |> put_req_header("content-type", "application/json")
             |> post(
               "/api/v1/buckets?dry_run=true",
               Jason.encode!(%{bucket: %{name: "Other Method"}})
             )
             |> json_response(201)
  end

  defp delete_routes do
    PortfolixirWeb.Router
    |> Phoenix.Router.routes()
    |> Enum.filter(&(&1.verb == :delete and String.starts_with?(&1.path, "/api/v1/")))
  end

  defp takes(route), do: Map.get(route.metadata, :delete_takes, [])

  defp refusal(route) do
    case takes(route) do
      [] -> @no_parameters
      takes -> "is unknown: this delete takes only " <> Enum.join(takes, ", ")
    end
  end

  # The route's path with every parameter filled by an id no record has.
  defp concrete(path) do
    path
    |> String.split("/")
    |> Enum.map_join("/", fn
      ":" <> _param -> "1"
      segment -> segment
    end)
  end
end
