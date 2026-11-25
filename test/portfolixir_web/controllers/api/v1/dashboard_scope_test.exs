defmodule PortfolixirWeb.Api.V1.DashboardScopeTest do
  # Sprint 32 S1 (ADR-0062's amendment of 2026-11-25, point 4; I61): a
  # dashboard's own view and its origin over the API, as the screen reads
  # them. Every name is synthetic.
  #
  # group: :dashboards -- every module that creates a dashboard joins it
  # (the create's count lock, `Portfolixir.LockTable` row 30).
  use PortfolixirWeb.ConnCase, async: true, group: :dashboards

  alias Portfolixir.Actor
  alias Portfolixir.Buckets

  defp authed(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  defp view!(name) do
    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: name, include_all: true})
    view
  end

  # User story:
  # As the agent composing a dashboard for one part of the operator's
  # holdings,
  # I want to give it a view of its own on create, on a template's copy and
  # by PATCH, and to read it back with the template it came from,
  # so that I compose what the operator's gallery composes.
  #
  # Acceptance criteria:
  # - POST with `view_id` answers 201 with `view_id`, `view_dangling: false`
  #   and `template_key: null`; a copy with `template` answers its key.
  # - A `view_id` that names no view answers 422 on `view_id`; a
  #   `template_key` sent answers 422 naming it (no write takes it).
  # - PATCH with `view_id` alone changes it; `null` clears it.
  # - After the view's delete, GET answers the stored id with
  #   `view_dangling: true`; the list answers the same.
  test "a dashboard's own view is written on create, copy and PATCH, and read back", %{
    conn: conn
  } do
    krypto = view!("Krypto")

    created =
      conn
      |> authed()
      |> post("/api/v1/dashboards", %{
        "dashboard" => %{"name" => "Eigenes", "layout" => [], "view_id" => krypto.id}
      })
      |> json_response(201)
      |> Map.fetch!("data")

    assert %{"view_id" => id, "view_dangling" => false, "template_key" => nil} = created
    assert id == krypto.id

    copied =
      conn
      |> authed()
      |> post("/api/v1/dashboards", %{
        "dashboard" => %{"template" => "overview", "view_id" => krypto.id}
      })
      |> json_response(201)
      |> Map.fetch!("data")

    assert copied["template_key"] == "overview"
    assert copied["view_id"] == krypto.id

    refused =
      conn
      |> authed()
      |> post("/api/v1/dashboards", %{
        "dashboard" => %{"name" => "X", "layout" => [], "view_id" => 999_999_999}
      })
      |> json_response(422)

    assert refused["errors"]["view_id"] == ["names no view"]

    for body <- [
          %{"name" => "X", "layout" => [], "template_key" => "overview"},
          %{"template" => "overview", "template_key" => "overview"}
        ] do
      answer =
        conn
        |> authed()
        |> post("/api/v1/dashboards", %{"dashboard" => body})
        |> json_response(422)

      assert Map.has_key?(answer["errors"], "template_key")
    end

    other = view!("Andere")

    patched =
      conn
      |> authed()
      |> patch("/api/v1/dashboards/#{created["id"]}", %{"dashboard" => %{"view_id" => other.id}})
      |> json_response(200)
      |> Map.fetch!("data")

    assert patched["view_id"] == other.id

    {:ok, _} = Buckets.delete_view(Actor.owner_ui(), other)

    read = conn |> authed() |> get("/api/v1/dashboards/#{created["id"]}") |> json_response(200)
    assert %{"view_id" => dangling, "view_dangling" => true} = read["data"]
    assert dangling == other.id

    listed = conn |> authed() |> get("/api/v1/dashboards") |> json_response(200)
    entry = Enum.find(listed["data"], &(&1["id"] == created["id"]))
    assert {entry["view_id"], entry["view_dangling"]} == {other.id, true}

    cleared =
      conn
      |> authed()
      |> patch("/api/v1/dashboards/#{created["id"]}", %{"dashboard" => %{"view_id" => nil}})
      |> json_response(200)

    assert cleared["data"]["view_id"] == nil
    assert cleared["data"]["view_dangling"] == false
  end

  # User story (Sprint 32 S4; board 03 ①):
  # As the agent composing a dashboard from a template,
  # I want each template the gallery offers with its group, whether it is a
  # starter, whether it asks for a scope, and its line,
  # so that I offer the operator what the gallery offers.
  #
  # Acceptance criteria:
  # - GET /api/v1/dashboards lists every offered template with `group`
  #   (`starter` or `theme`), `starter`, `asks_scope` and `subtitle`; the
  #   template read answers the same.
  test "a template entry names its group, whether it asks for a scope, and its line", %{
    conn: conn
  } do
    listed = conn |> authed() |> get("/api/v1/dashboards") |> json_response(200)
    templates = Enum.filter(listed["data"], &(&1["type"] == "template"))

    assert Enum.map(templates, & &1["key"]) ==
             Enum.map(Portfolixir.Dashboards.templates(), & &1.key)

    overview = Enum.find(templates, &(&1["key"] == "overview"))

    assert Map.take(overview, ~w(group starter asks_scope subtitle)) == %{
             "group" => "starter",
             "starter" => true,
             "asks_scope" => false,
             "subtitle" => "as today's start page"
           }

    read =
      conn |> authed() |> get("/api/v1/dashboards/template:overview") |> json_response(200)

    assert read["data"]["group"] == "starter"
    assert read["data"]["asks_scope"] == false
  end
end
