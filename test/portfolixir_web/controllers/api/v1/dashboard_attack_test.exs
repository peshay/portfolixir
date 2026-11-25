defmodule PortfolixirWeb.Api.V1.DashboardAttackTest do
  # Sprint 31 D2's attack lens on the routes (ADR-0062 §11; AGENTS.md,
  # "Never create atoms from external input"): thousands of distinct
  # unknown keys sent over the API — beside the wrapper, inside it, in a
  # layout item and its settings, in the query — and fresh template keys,
  # all refused without one new atom; and a layout that names a route is
  # refused, or its read-only source ignored, so a stored layout cannot
  # make the server read one.
  #
  # async: false -- the atom table is the VM's, and the synchronous modules
  # run after every asynchronous one, so no other test makes atoms while
  # this one counts. It stores one dashboard, which no other module sees.
  use PortfolixirWeb.ConnCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Dashboards

  @keys 2_000

  defp fresh(prefix), do: "#{prefix}_dq#{System.unique_integer([:positive])}z"

  defp many(prefix), do: Map.new(1..@keys, &{fresh("#{prefix}#{&1}"), &1})

  defp authed(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  defp attempt(id) do
    item = %{"kind" => "movers", "size" => "L", "col" => 1, "row" => 1}
    path = "/api/v1/dashboards/#{id}"

    requests = [
      {:post, "/api/v1/dashboards", Map.put(many("beside"), "dashboard", %{"name" => "N"})},
      {:post, "/api/v1/dashboards", %{"dashboard" => Map.put(many("inside"), "name", "N")}},
      {:post, "/api/v1/dashboards",
       %{"dashboard" => %{"name" => "N", "layout" => [Map.merge(item, many("item"))]}}},
      {:post, "/api/v1/dashboards",
       %{
         "dashboard" => %{
           "name" => "N",
           "layout" => [Map.put(item, "settings", many("setting"))]
         }
       }},
      {:post, "/api/v1/dashboards",
       %{"dashboard" => %{"name" => "N", "layout" => [Map.put(item, "kind", fresh("kind"))]}}},
      {:post, "/api/v1/dashboards", %{"dashboard" => %{"template" => fresh("template")}}},
      {:put, path,
       %{
         "dashboard" =>
           Map.merge(many("put"), %{"name" => "N", "layout" => [], "lock_version" => 1})
       }},
      {:patch, path, %{"dashboard" => Map.put(many("patch"), "name", "N")}},
      {:delete, path, many("delete")},
      {:get, "/api/v1/widgets", many("widgets")},
      {:get, "/api/v1/dashboards", many("index")},
      {:get, "/api/v1/dashboards/template:" <> fresh("template"), %{}},
      {:put, "/api/v1/dashboards/template:" <> fresh("template"), %{"dashboard" => many("t")}}
    ]

    for {method, route, params} <- requests do
      conn = build_conn() |> authed() |> dispatch(@endpoint, method, route, params)
      true = conn.status in [404, 422]
    end
  end

  # User story (ADR-0062 §11):
  # As the operator,
  # I want a request carrying thousands of unknown keys, or a template or
  # kind no release has, to make no atom on any dashboard route,
  # so that a crafted request cannot fill the VM's atom table.
  #
  # Acceptance criteria:
  # - Five rounds of thirteen requests, each key fresh, leave the atom count
  #   unchanged, each answered 404 or 422, and the stored dashboard as it
  #   was.
  test "unknown keys sent over the API make no atom", %{conn: _conn} do
    {:ok, stored} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Fest", "layout" => []})

    attempt(stored.id)
    before = :erlang.system_info(:atom_count)

    for _round <- 1..5, do: attempt(stored.id)

    assert :erlang.system_info(:atom_count) == before
    assert [%{name: "Fest", lock_version: 1}] = Dashboards.list_dashboards()
  end

  # User story (ADR-0062 §11):
  # As the operator,
  # I want a layout that names a route or a function refused, a source it
  # sends ignored, and every item's source answered from the registry,
  # so that a stored layout cannot make the server, or a reader following
  # it, read an arbitrary route.
  #
  # Acceptance criteria:
  # - An item carrying route, routes, function or url, or settings carrying
  #   any of them or source, answers 422 naming that key; nothing is stored.
  # - An item carrying source or title is accepted with them ignored: both
  #   are read-only, the registry's for the kind, so a layout read and sent
  #   back is taken as read (Sprint 31 closing act, C3/A2, the
  #   orchestrator's decision); neither is stored, and the answer's source
  #   is still the kind's registered routes, never the one sent.
  test "a layout cannot name what a widget reads", %{conn: conn} do
    item = %{"kind" => "due", "size" => "S", "col" => 1, "row" => 1}

    refusals =
      for(key <- ~w(route routes function url), do: {:item, key}) ++
        for key <- ~w(source title route routes function url), do: {:settings, key}

    for {place, key} <- refusals do
      layout =
        case place do
          :item -> [Map.put(item, key, "GET /api/v1/journal")]
          :settings -> [Map.put(item, "settings", %{key => "/api/v1/journal"})]
        end

      %{"errors" => %{"layout_item" => refused}} =
        conn
        |> authed()
        |> post("/api/v1/dashboards", %{"dashboard" => %{"name" => "N", "layout" => layout}})
        |> json_response(422)

      field = if place == :item, do: key, else: "settings." <> key
      assert refused["field"] == field
    end

    assert Dashboards.list_dashboards() == []

    # source and title are read-only: sent, they are ignored, not refused.
    sent =
      Map.merge(item, %{
        "source" => %{"routes" => ["GET /api/v1/journal"], "function" => "x", "note" => "x"},
        "title" => "Journal"
      })

    %{"data" => %{"layout" => [stored]}} =
      conn
      |> authed()
      |> post("/api/v1/dashboards", %{"dashboard" => %{"name" => "N", "layout" => [sent]}})
      |> json_response(201)

    assert stored["source"]["routes"] == ["GET /api/v1/events/upcoming"]
    assert stored["title"] == "Due"
    assert [%{layout: [kept]}] = Dashboards.list_dashboards()
    assert Map.keys(kept) == ~w(col kind row settings size)
  end
end
