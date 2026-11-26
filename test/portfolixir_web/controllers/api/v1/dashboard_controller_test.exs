defmodule PortfolixirWeb.Api.V1.DashboardControllerTest do
  # Sprint 31 D2 (FR-60, ADR-0062 §1, §2, §3, §8, §11): the widget
  # catalogue and the dashboards over the API — GET /api/v1/widgets, GET
  # /api/v1/dashboards, GET /api/v1/dashboards/:id (a stored dashboard, or
  # a template as template:<key>), POST, PUT, PATCH and DELETE (with
  # dry_run). Every name is synthetic.
  #
  # group: :dashboards -- every module that creates a dashboard joins it
  # (the create's count lock, `Portfolixir.LockTable` row 30).
  use PortfolixirWeb.ConnCase, async: true, group: :dashboards

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Dashboards
  alias Portfolixir.Dashboards.Templates
  alias Portfolixir.Dashboards.Widgets
  alias Portfolixir.Journal
  alias Portfolixir.Periods

  defp authed(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  defp entries, do: Journal.list_entries(resource_type: "dashboard", order: :asc)

  defp due(col, row), do: %{"kind" => "due", "size" => "S", "col" => col, "row" => row}

  defp create!(name, layout \\ []) do
    {:ok, dashboard} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => name, "layout" => layout})

    dashboard
  end

  # --- the catalogue -------------------------------------------------------

  # User story (ADR-0062 §1, §8):
  # As the agent the operator runs,
  # I want the widget catalogue as one read,
  # so that I can compose a dashboard without reading the code.
  #
  # Acceptance criteria:
  # - GET /api/v1/widgets answers every registered kind in the registry's
  #   order, each with its key, its English title and its title key (the
  #   msgid and its context), its group, its sizes, its source (routes, the
  #   context function, the note), its period rule ("none", or the periods
  #   it answers, the source's parameter, its values, the trailing ranges
  #   and the translated ones), its scope and its compact flag.
  # - It answers the groups with their titles, the grid (12 columns, the
  #   highest row, the item cap and each grid size's columns and rows; full
  #   is a page, never placed), the dashboard periods and their default, and
  #   the two limits (50 dashboards, a name of 60 characters).
  # - It takes no parameter: one answers 422 naming it.
  test "the catalogue answers every kind and the rules a layout is checked against", %{
    conn: conn
  } do
    %{"data" => data} = conn |> authed() |> get("/api/v1/widgets") |> json_response(200)

    assert Enum.map(data["widgets"], & &1["key"]) == Widgets.keys()

    movers = Enum.find(data["widgets"], &(&1["key"] == "movers"))

    assert movers == %{
             "key" => "movers",
             "title" => "Tops and flops",
             "title_key" => %{"context" => "widget kind", "msgid" => "Tops and flops"},
             "group" => "performance",
             "sizes" => ["S", "L"],
             "source" => %{
               "routes" => ["GET /api/v1/movers", "GET /api/v1/views/:view_id/movers"],
               "function" => "Portfolixir.Portfolios.Performance.Movers.read/3",
               "note" => nil
             },
             # Sprint 32 T1: the period vocabulary's fixed keys, the
             # keyed year, and the amendment's translations.
             "period" => %{
               "periods" => Periods.keys(),
               "param" => "window",
               "values" => %{
                 "1d" => "day",
                 "1w" => "week",
                 "1m" => "month",
                 "3m" => "quarter",
                 "6m" => "quarter",
                 "1y" => "1y",
                 "3y" => "1y",
                 "5y" => "1y",
                 "max" => "1y",
                 "mtd" => "month",
                 "prev_month" => "month",
                 "qtd" => "quarter",
                 "prev_quarter" => "quarter",
                 "q1" => "quarter",
                 "q2" => "quarter",
                 "q3" => "quarter",
                 "q4" => "quarter",
                 "ytd" => "ytd",
                 "prev_year" => "1y"
               },
               "ranges" => [],
               "years" => [],
               "keyed" => %{"year:YYYY" => "1y"},
               "spans" => [
                 %{"window" => "day", "up_to_days" => 1},
                 %{"window" => "week", "up_to_days" => 7},
                 %{"window" => "month", "up_to_days" => 31},
                 %{"window" => "quarter", "up_to_days" => 184}
               ],
               "spans_else" => "1y",
               "translated" => (Periods.keys() -- ~w(ytd 1y)) ++ ["year:YYYY", "saved:<id>"]
             },
             "scope" => "view",
             "compact" => true
           }

    crashes = Enum.find(data["widgets"], &(&1["key"] == "crashes"))
    assert crashes["period"] == "none"
    assert crashes["scope"] == "none"

    for kind <- data["widgets"] do
      {:ok, registered} = Widgets.fetch(kind["key"])
      assert kind["title"] == registered.title
      assert kind["sizes"] == registered.sizes
      assert kind["source"]["routes"] == registered.source.routes
      assert Enum.all?(kind["source"]["routes"], &String.starts_with?(&1, "GET /api/v1/"))
    end

    assert data["groups"] == [
             %{"key" => "overview", "title" => "Overview"},
             %{"key" => "performance", "title" => "Performance"},
             %{"key" => "allocation", "title" => "Allocation"},
             %{"key" => "risk", "title" => "Risk"},
             %{"key" => "analyses", "title" => "Analyses"}
           ]

    assert data["grid"]["columns"] == 12
    assert data["grid"]["max_row"] == 200
    assert data["grid"]["max_items"] == 40

    # Sprint 32 E4: Apple's families, each named, rows of a fixed height,
    # and the rule each kind's sizes are read against.
    assert data["grid"]["sizes"] == %{
             "S" => %{"columns" => 3, "rows" => 2, "family" => "small", "height" => "fixed"},
             "M" => %{"columns" => 6, "rows" => 2, "family" => "medium", "height" => "fixed"},
             "L" => %{"columns" => 6, "rows" => 4, "family" => "large", "height" => "fixed"},
             "XL" => %{
               "columns" => 12,
               "rows" => 4,
               "family" => "extra large",
               "height" => "fixed"
             },
             "row" => %{"columns" => 12, "rows" => 1, "family" => nil, "height" => "content"}
           }

    assert data["grid"]["row_height"] == "7rem"
    assert data["grid"]["size_rule"] =~ "each size of a kind shows more of the same"

    assert data["grid"]["full"] =~ "never placed"

    assert data["periods"] == %{
             "values" => Periods.keys(),
             "keyed" => ["year:YYYY", "saved:<id>"],
             "default" => "1y"
           }

    assert data["max_dashboards"] == 50
    assert data["name_max"] == 60

    assert conn |> authed() |> get("/api/v1/widgets?group=risk") |> json_response(422) ==
             %{"errors" => %{"group" => ["is unknown: this request takes no parameters"]}}
  end

  # --- the reads -------------------------------------------------------------

  # User story (ADR-0062 §3, §8):
  # As the agent the operator runs,
  # I want the dashboards listed as the menu shows them, the templates
  # beside them, each marked,
  # so that I know what the operator sees first and what I can copy.
  #
  # Acceptance criteria:
  # - On a fresh instance the list is the template „Überblick“ alone,
  #   type template, key overview, read_only, in_menu true; the read writes
  #   nothing (no row, no journal entry).
  # - With dashboards stored, they come first by position, then id, each
  #   type dashboard with id, name, position, lock_version, item_count,
  #   in_menu true, read_only false; the template follows, in_menu false.
  # - The list takes no parameter.
  test "the list is the menu: the template alone on a fresh instance, else the stored ones first",
       %{conn: conn} do
    %{"data" => fresh} = conn |> authed() |> get("/api/v1/dashboards") |> json_response(200)

    # The starter „Überblick“ in the menu; the other starters (Sprint 32 W2)
    # have no address until the boot stores them, and the themes (Sprint 32
    # S5) never are.
    assert [overview | others] = fresh

    assert Enum.map(others, &{&1["key"], &1["group"], &1["in_menu"]}) == [
             {"allocation_targets", "starter", false},
             {"snapshots", "starter", false},
             {"risk", "starter", false},
             {"krypto_lover", "theme", false},
             {"pullbacks", "theme", false}
           ]

    assert [overview] == [
             %{
               "type" => "template",
               "id" => nil,
               "key" => "overview",
               "name" => "Overview",
               "group" => "starter",
               "starter" => true,
               "asks_scope" => false,
               "subtitle" => "as today's start page",
               "read_only" => true,
               "in_menu" => true,
               "item_count" => 11
             }
           ]

    assert Dashboards.list_dashboards() == []
    assert entries() == []

    second = create!("Zweites", [due(1, 1)])
    first = create!("Erstes")
    {:ok, second} = Dashboards.reposition_dashboard(Actor.owner_ui(), second.id, 3)

    %{"data" => listed} = conn |> authed() |> get("/api/v1/dashboards") |> json_response(200)

    assert [one, two, template | _themes] = listed
    assert {one["id"], two["id"]} == {first.id, second.id}

    assert Map.drop(two, ["inserted_at", "updated_at"]) == %{
             "type" => "dashboard",
             "id" => second.id,
             "key" => nil,
             "name" => "Zweites",
             "position" => 3,
             "lock_version" => 2,
             "view_id" => nil,
             "view_dangling" => false,
             "template_key" => nil,
             "read_only" => false,
             "in_menu" => true,
             "item_count" => 1
           }

    assert {:ok, _at, 0} = DateTime.from_iso8601(two["updated_at"])
    assert template["type"] == "template"
    assert template["in_menu"] == false

    assert conn |> authed() |> get("/api/v1/dashboards?type=template") |> json_response(422) ==
             %{"errors" => %{"type" => ["is unknown: this request takes no parameters"]}}
  end

  # User story (ADR-0062 §8, §11):
  # As the agent the operator runs,
  # I want one dashboard, or one template, with each widget's source route,
  # so that I can read what each widget shows from the route it names.
  #
  # Acceptance criteria:
  # - GET /api/v1/dashboards/:id answers the stored dashboard with its
  #   layout, each item its kind, size, col, row, settings, its title and
  #   its source (the registry's routes, function and note).
  # - GET /api/v1/dashboards/template:overview answers the template the same
  #   way, type template, read_only, its layout the one in code.
  # - An unknown id, a template key that names none, and an id that is
  #   neither answer 404; a template key that names none names the keys
  #   offered, as POST's 422 does (Sprint 31 closing act, A4); a parameter
  #   answers 422 naming it.
  test "one dashboard or one template, each item with its source", %{conn: conn} do
    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Synthetic short term"})

    stored =
      create!("Kurzfristig", [
        Map.put(due(1, 1), "settings", %{}),
        %{
          "kind" => "movers",
          "size" => "L",
          "col" => 1,
          "row" => 3,
          "settings" => %{"view_id" => view.id, "period" => "1w"}
        }
      ])

    %{"data" => data} =
      conn |> authed() |> get("/api/v1/dashboards/#{stored.id}") |> json_response(200)

    assert data["type"] == "dashboard"
    assert data["name"] == "Kurzfristig"
    assert data["lock_version"] == 1

    assert [due_item, movers_item] = data["layout"]

    assert movers_item == %{
             "kind" => "movers",
             "size" => "L",
             "col" => 1,
             "row" => 3,
             "settings" => %{"view_id" => view.id, "period" => "1w"},
             "title" => "Tops and flops",
             "source" => %{
               "routes" => ["GET /api/v1/movers", "GET /api/v1/views/:view_id/movers"],
               "function" => "Portfolixir.Portfolios.Performance.Movers.read/3",
               "note" => nil
             }
           }

    assert due_item["source"]["routes"] == ["GET /api/v1/events/upcoming"]

    %{"data" => template} =
      conn |> authed() |> get("/api/v1/dashboards/template:overview") |> json_response(200)

    {:ok, overview} = Templates.fetch("overview")

    assert template["type"] == "template"
    assert template["key"] == "overview"
    assert template["read_only"] == true
    assert template["id"] == nil

    assert Enum.map(template["layout"], &Map.take(&1, ~w(kind size col row settings))) ==
             overview.layout

    assert Enum.all?(template["layout"], &match?(%{"source" => %{"routes" => [_ | _]}}, &1))

    for path <- ["/api/v1/dashboards/template:nope", "/api/v1/dashboards/template:"] do
      assert conn |> authed() |> get(path) |> json_response(404) ==
               %{
                 "errors" => %{
                   "detail" =>
                     "not found: names no template; offered: overview, allocation_targets, snapshots, risk, krypto_lover, pullbacks"
                 }
               },
             path
    end

    for path <- [
          "/api/v1/dashboards/#{stored.id + 1_000}",
          "/api/v1/dashboards/overview",
          "/api/v1/dashboards/0",
          "/api/v1/dashboards/99999999999999999999"
        ] do
      assert conn |> authed() |> get(path) |> json_response(404) ==
               %{"errors" => %{"detail" => "not found"}},
             path
    end

    assert conn
           |> authed()
           |> get("/api/v1/dashboards/#{stored.id}?projection=full")
           |> json_response(422) ==
             %{"errors" => %{"projection" => ["is unknown: this request takes no parameters"]}}
  end

  # --- the writes ------------------------------------------------------------

  # User story (ADR-0062 §2, §3, §8):
  # As the agent the operator runs,
  # I want to create a dashboard, or copy a template, in one call,
  # so that „stell mir ein Dashboard für kurzfristige Bewegungen zusammen“
  # is one write, journaled under my token.
  #
  # Acceptance criteria:
  # - POST {"dashboard": {name, layout}} answers 201 with the dashboard as
  #   GET answers it, its layout normalized, at the end of the menu,
  #   lock_version 1; one journal entry, a create under the token's actor.
  # - POST {"dashboard": {template, name?}} copies the template's layout,
  #   under the name given or the template's title; the template stays as
  #   shipped.
  test "a create and a template's copy, journaled under the token", %{conn: conn} do
    body = %{
      "dashboard" => %{
        "name" => "Kurzfristig",
        "layout" => [
          %{"kind" => "movers", "size" => "L", "col" => 1, "row" => 1},
          %{"kind" => "performance", "size" => "S", "col" => 7, "row" => 1}
        ]
      }
    }

    %{"data" => created} =
      conn |> authed() |> post("/api/v1/dashboards", body) |> json_response(201)

    assert created["type"] == "dashboard"
    assert created["name"] == "Kurzfristig"
    assert created["position"] == 1
    assert created["lock_version"] == 1
    assert Enum.map(created["layout"], & &1["settings"]) == [%{}, %{}]
    assert Enum.map(created["layout"], & &1["title"]) == ["Tops and flops", "Performance"]

    assert [entry] = entries()
    assert entry.operation == :create
    assert entry.actor_type == :api_token_rw
    assert entry.resource_id == to_string(created["id"])

    %{"data" => copied} =
      conn
      |> authed()
      |> post("/api/v1/dashboards", %{"dashboard" => %{"template" => "overview"}})
      |> json_response(201)

    {:ok, overview} = Templates.fetch("overview")
    assert copied["name"] == "Overview"
    assert copied["position"] == 2

    assert Enum.map(copied["layout"], &Map.take(&1, ~w(kind size col row settings))) ==
             overview.layout

    %{"data" => named} =
      conn
      |> authed()
      |> post("/api/v1/dashboards", %{
        "dashboard" => %{"template" => "overview", "name" => "Mein Überblick"}
      })
      |> json_response(201)

    assert named["name"] == "Mein Überblick"
    assert length(entries()) == 3
    assert Templates.fetch("overview") == {:ok, overview}
  end

  # User story (ADR-0062 §2, §8):
  # As the agent the operator runs,
  # I want a refused write to name the first bad item — its index, its
  # field and the reason — and the field it lacks or does not take,
  # so that I can correct my layout without guessing.
  #
  # Acceptance criteria:
  # - A layout refused answers 422 with errors.layout (the message) and
  #   errors.layout_item {index, field, reason} (other for an overlap):
  #   an unknown kind, a size the kind lacks, a position off the grid, an
  #   overlap, a view that does not exist, a view on a kind that takes
  #   none (no_view), a pin on a kind without a period, a period the kind
  #   does not take, a key an item does not take (a route among them: a
  #   layout cannot name what a widget reads), 41 items, a layout that is
  #   not a list.
  # - A name of 61 characters, with a control character, or blank answers
  #   422 naming name.
  # - A key the create does not take, inside the wrapper or beside it,
  #   answers 422 naming it; a template beside a layout names the layout;
  #   an unknown template answers 422 naming template; a wrapper that is no
  #   object answers 422.
  # - Nothing is written on any refusal.
  test "a refused create names the first bad item and writes nothing", %{conn: conn} do
    movers = %{"kind" => "movers", "size" => "L", "col" => 1, "row" => 1}

    refusals = [
      {[Map.put(movers, "kind", "ticker_tape")],
       %{"index" => 0, "field" => "kind", "reason" => "unknown_kind"}},
      {[Map.put(movers, "size", "M")],
       %{"index" => 0, "field" => "size", "reason" => "unsupported_size"}},
      {[Map.put(movers, "col", 8)], %{"index" => 0, "field" => "col", "reason" => "off_grid"}},
      {[movers, Map.put(movers, "col", 4)],
       %{"index" => 1, "field" => "col", "reason" => "overlap", "other" => 0}},
      {[Map.put(movers, "settings", %{"view_id" => 987_654_321})],
       %{"index" => 0, "field" => "settings.view_id", "reason" => "unknown_view"}},
      {[due(1, 1), Map.put(due(4, 1), "settings", %{"view_id" => 1})],
       %{"index" => 1, "field" => "settings.view_id", "reason" => "no_view"}},
      {[Map.put(due(1, 1), "settings", %{"period" => "1y"})],
       %{"index" => 0, "field" => "settings.period", "reason" => "no_period"}},
      {[Map.put(movers, "settings", %{"period" => "6y"})],
       %{"index" => 0, "field" => "settings.period", "reason" => "unsupported_period"}},
      # source is read-only and ignored on write (C3), so route stands for
      # the key that names what a widget reads.
      {[Map.put(movers, "route", "GET /api/v1/journal")],
       %{"index" => 0, "field" => "route", "reason" => "unknown_key"}},
      {[Map.put(movers, "settings", %{"route" => "/api/v1/journal"})],
       %{"index" => 0, "field" => "settings.route", "reason" => "unknown_setting"}},
      {for(row <- 1..41, do: due(1, row)),
       %{"index" => 40, "field" => nil, "reason" => "too_many_items"}},
      {%{"0" => movers}, %{"index" => nil, "field" => nil, "reason" => "not_a_list"}}
    ]

    for {layout, item} <- refusals do
      %{"errors" => errors} =
        conn
        |> authed()
        |> post("/api/v1/dashboards", %{"dashboard" => %{"name" => "N", "layout" => layout}})
        |> json_response(422)

      assert errors["layout_item"] == item, inspect(item)
      assert [message] = errors["layout"]
      assert is_binary(message)
    end

    for name <- [String.duplicate("x", 61), "Zwei\nZeilen", "   "] do
      %{"errors" => errors} =
        conn
        |> authed()
        |> post("/api/v1/dashboards", %{"dashboard" => %{"name" => name}})
        |> json_response(422)

      assert Map.keys(errors) == ["name"], inspect(name)
    end

    for {body, field, message} <- [
          {%{"dashboard" => %{"name" => "N", "position" => 3}}, "position",
           "is unknown: dashboard takes only name, layout, view_id"},
          {%{"dashboard" => %{"name" => "N"}, "name" => "N"}, "name",
           "is unknown: this write takes its fields under dashboard"},
          {%{"dashboard" => %{"template" => "overview", "layout" => []}}, "layout",
           "is unknown: dashboard takes only template, name, view_id"}
        ] do
      assert conn |> authed() |> post("/api/v1/dashboards", body) |> json_response(422) ==
               %{"errors" => %{field => [message]}},
             inspect(body)
    end

    assert conn
           |> authed()
           |> post("/api/v1/dashboards", %{"dashboard" => %{"template" => "income"}})
           |> json_response(422) ==
             %{
               "errors" => %{
                 "template" => [
                   "names no template; offered: overview, allocation_targets, snapshots, risk, krypto_lover, pullbacks"
                 ]
               }
             }

    assert conn
           |> authed()
           |> post("/api/v1/dashboards", %{"dashboard" => "Kurzfristig"})
           |> json_response(422) == %{"errors" => %{"dashboard" => ["must be an object"]}}

    assert Dashboards.list_dashboards() == []
    assert entries() == []
  end

  # User story (ADR-0062 §2):
  # As the operator,
  # I want the 51st dashboard refused over the API as on the screen,
  # so that an agent cannot grow the menu without bound.
  #
  # Acceptance criteria:
  # - With 50 stored, a create and a template's copy answer 422 with
  #   errors.code too_many_dashboards and a detail naming 50; nothing is
  #   written.
  test "the 51st dashboard is refused", %{conn: conn} do
    for n <- 1..50, do: create!("D#{n}")
    journaled = length(entries())

    for body <- [%{"name" => "Zu viel"}, %{"template" => "overview"}] do
      assert conn
             |> authed()
             |> post("/api/v1/dashboards", %{"dashboard" => body})
             |> json_response(422) == %{
               "errors" => %{
                 "code" => "too_many_dashboards",
                 "detail" => "at most 50 dashboards are stored: delete one before adding another"
               }
             }
    end

    assert length(Dashboards.list_dashboards()) == 50
    assert length(entries()) == journaled
  end

  # User story (ADR-0062 §2, §8):
  # As the agent the operator runs, or the operator on the screen,
  # I want a replace to carry the lock_version I read, and a stale one
  # refused with the dashboard as stored,
  # so that neither of us overwrites the other's layout unseen.
  #
  # Acceptance criteria:
  # - PUT {"dashboard": {name, layout, lock_version}} with the stored
  #   lock_version answers 200, lock_version one higher, journaled.
  # - With an older one it answers 409, errors.code stale, a detail, and
  #   errors.stored: the dashboard as GET answers it; nothing is written.
  # - A missing field answers 422 naming it; a lock_version that is no whole
  #   number 422 naming lock_version; a bad layout 422 naming its item; an
  #   unknown id 404; a template 422 naming id, never edited.
  test "a replace with lock_version; a stale one answers 409 with the stored dashboard", %{
    conn: conn
  } do
    stored = create!("Kurzfristig", [due(1, 1)])
    path = "/api/v1/dashboards/#{stored.id}"

    replace = fn lock_version ->
      %{
        "dashboard" => %{
          "name" => "Bewegungen",
          "layout" => [%{"kind" => "movers", "size" => "S", "col" => 1, "row" => 1}],
          "lock_version" => lock_version
        }
      }
    end

    %{"data" => replaced} = conn |> authed() |> put(path, replace.(1)) |> json_response(200)
    assert replaced["name"] == "Bewegungen"
    assert replaced["lock_version"] == 2
    assert [%{"kind" => "movers"}] = replaced["layout"]
    journaled = length(entries())

    %{"errors" => errors} = conn |> authed() |> put(path, replace.(1)) |> json_response(409)
    assert errors["code"] == "stale"
    assert errors["detail"] =~ "lock_version 2"

    %{"data" => as_read} = conn |> authed() |> get(path) |> json_response(200)
    assert errors["stored"] == as_read
    assert length(entries()) == journaled

    assert %{"errors" => %{"lock_version" => [_]}} =
             conn
             |> authed()
             |> put(path, %{"dashboard" => %{"name" => "N", "layout" => []}})
             |> json_response(422)

    for bad <- ["2", 0, 2.5] do
      assert %{"errors" => %{"lock_version" => [_]}} =
               conn |> authed() |> put(path, replace.(bad)) |> json_response(422),
             inspect(bad)
    end

    assert %{"errors" => %{"layout_item" => %{"reason" => "unknown_kind"}}} =
             conn
             |> authed()
             |> put(path, %{
               "dashboard" => %{
                 "name" => "N",
                 "layout" => [%{"kind" => "x", "size" => "S", "col" => 1, "row" => 1}],
                 "lock_version" => 2
               }
             })
             |> json_response(422)

    assert conn
           |> authed()
           |> put("/api/v1/dashboards/#{stored.id + 1_000}", replace.(1))
           |> json_response(404) == %{"errors" => %{"detail" => "not found"}}

    assert %{"errors" => %{"id" => [read_only]}} =
             conn
             |> authed()
             |> put("/api/v1/dashboards/template:overview", replace.(1))
             |> json_response(422)

    assert read_only =~ "template"
    assert length(entries()) == journaled
  end

  # User story (ADR-0062 §2, §8, §11; Sprint 31 closing act, C3 and A2):
  # As the agent the operator runs,
  # I want to send a layout back as GET, a 409's errors.stored or a
  # template's read answered it, with only my change made,
  # so that get, modify and put is one round trip and not a rebuild of
  # every item.
  #
  # Acceptance criteria:
  # - A layout read and sent back with its items' title and source answers
  #   200; neither is stored, and the answer's are the registry's, whatever
  #   the item sent (they are read-only and ignored on write).
  # - The 409's errors.stored, changed and sent with its lock_version,
  #   answers 200; its detail says title and source are ignored on write.
  # - A template's layout as read creates a dashboard (201).
  test "a layout as read is written back as read; title and source are ignored", %{conn: conn} do
    stored =
      create!("Kurzfristig", [
        %{
          "kind" => "movers",
          "size" => "L",
          "col" => 1,
          "row" => 1,
          "settings" => %{"period" => "1w"}
        },
        due(7, 1)
      ])

    path = "/api/v1/dashboards/#{stored.id}"
    %{"data" => read} = conn |> authed() |> get(path) |> json_response(200)
    assert Enum.all?(read["layout"], &(Map.has_key?(&1, "title") and Map.has_key?(&1, "source")))

    moved =
      read["layout"]
      |> Enum.map(&Map.put(&1, "row", 2))
      |> List.update_at(
        1,
        &Map.merge(&1, %{"title" => "X", "source" => %{"routes" => ["GET /x"]}})
      )

    put_back = fn layout, lock_version ->
      %{
        "dashboard" => %{
          "name" => read["name"],
          "layout" => layout,
          "lock_version" => lock_version
        }
      }
    end

    %{"data" => written} =
      conn |> authed() |> put(path, put_back.(moved, read["lock_version"])) |> json_response(200)

    {:ok, due_kind} = Widgets.fetch("due")
    assert [%{"row" => 2}, %{"row" => 2, "title" => "Due"} = due_item] = written["layout"]
    assert due_item["source"]["routes"] == due_kind.source.routes

    assert Enum.map(Dashboards.get_dashboard(stored.id).layout, &Map.keys/1) ==
             List.duplicate(~w(col kind row settings size), 2)

    %{"errors" => errors} =
      conn |> authed() |> put(path, put_back.(moved, read["lock_version"])) |> json_response(409)

    assert errors["detail"] =~ "title and source are read-only and ignored on write"
    rebuilt = List.update_at(errors["stored"]["layout"], 0, &Map.put(&1, "row", 3))

    assert %{"data" => %{"lock_version" => 3, "layout" => [%{"row" => 3}, _]}} =
             conn
             |> authed()
             |> put(path, put_back.(rebuilt, errors["stored"]["lock_version"]))
             |> json_response(200)

    %{"data" => template} =
      conn |> authed() |> get("/api/v1/dashboards/template:overview") |> json_response(200)

    assert %{"data" => %{"layout" => copied}} =
             conn
             |> authed()
             |> post("/api/v1/dashboards", %{
               "dashboard" => %{"name" => "Kopie", "layout" => template["layout"]}
             })
             |> json_response(201)

    assert copied == template["layout"]
  end

  # User story (ADR-0062 §8; the orchestrator's decision for D2):
  # As the agent the operator runs,
  # I want to rename a dashboard or move it in the menu, and to send the
  # lock_version I read when my rename must not land on a save I have not
  # seen,
  # so that a rename racing the screen's save is never lost unseen.
  #
  # Acceptance criteria:
  # - PATCH {"dashboard": {name?, position?, lock_version?}} renames and/or
  #   moves in one journaled write, answering the dashboard.
  # - With a stale lock_version it answers 409 with the stored dashboard,
  #   writing nothing; without one it applies.
  # - Neither name nor position, a field it does not take, a position that
  #   is no whole number, an unknown id and a template are refused.
  test "a rename and a reposition, with an optional lock_version", %{conn: conn} do
    stored = create!("Erstes")
    path = "/api/v1/dashboards/#{stored.id}"

    %{"data" => both} =
      conn
      |> authed()
      |> patch(path, %{"dashboard" => %{"name" => "Kurz", "position" => 4, "lock_version" => 1}})
      |> json_response(200)

    assert {both["name"], both["position"], both["lock_version"]} == {"Kurz", 4, 2}
    journaled = length(entries())

    %{"errors" => errors} =
      conn
      |> authed()
      |> patch(path, %{"dashboard" => %{"name" => "Verloren", "lock_version" => 1}})
      |> json_response(409)

    assert errors["code"] == "stale"
    assert errors["stored"]["name"] == "Kurz"
    assert errors["stored"]["lock_version"] == 2
    assert length(entries()) == journaled

    %{"data" => renamed} =
      conn |> authed() |> patch(path, %{"dashboard" => %{"name" => "Lang"}}) |> json_response(200)

    assert {renamed["name"], renamed["position"], renamed["lock_version"]} == {"Lang", 4, 3}

    for {body, field} <- [
          {%{"dashboard" => %{"lock_version" => 3}}, "name"},
          {%{"dashboard" => %{"name" => "N", "layout" => []}}, "layout"},
          {%{"dashboard" => %{"position" => "2"}}, "position"},
          {%{"dashboard" => %{"position" => 0}}, "position"},
          {%{"dashboard" => %{"name" => "N", "lock_version" => "3"}}, "lock_version"}
        ] do
      assert %{"errors" => %{^field => [_]}} =
               conn |> authed() |> patch(path, body) |> json_response(422),
             inspect(body)
    end

    assert conn
           |> authed()
           |> patch("/api/v1/dashboards/#{stored.id + 1_000}", %{"dashboard" => %{"name" => "N"}})
           |> json_response(404) == %{"errors" => %{"detail" => "not found"}}

    assert %{"errors" => %{"id" => [_]}} =
             conn
             |> authed()
             |> patch("/api/v1/dashboards/template:overview", %{"dashboard" => %{"name" => "N"}})
             |> json_response(422)

    assert Dashboards.get_dashboard(stored.id).name == "Lang"
    assert length(entries()) == journaled + 1
  end

  # User story (ADR-0062 §2, §8):
  # As the agent the operator runs,
  # I want to ask what a delete would remove before I delete,
  # so that I see that a dashboard deletes nothing else.
  #
  # Acceptance criteria:
  # - DELETE ?dry_run=true answers 200 {dry_run: true, would_remove:
  #   {dashboards: {count: 1, ids: [id]}}}, the one kind it reaches, and
  #   deletes nothing.
  # - DELETE answers 204, journaled as a delete; the dashboard is gone.
  # - An unknown id answers 404; a dry_run that is not a boolean, or another
  #   parameter, 422; a template 422 naming id.
  test "a delete and its dry run, which says a dashboard deletes nothing else", %{conn: conn} do
    stored = create!("Weg")
    path = "/api/v1/dashboards/#{stored.id}"

    assert conn |> authed() |> delete(path <> "?dry_run=true") |> json_response(200) == %{
             "data" => %{
               "dry_run" => true,
               "would_remove" => %{"dashboards" => %{"count" => 1, "ids" => [stored.id]}}
             }
           }

    assert Dashboards.get_dashboard(stored.id)

    assert conn |> authed() |> delete(path <> "?dry_run=maybe") |> json_response(422) ==
             %{"errors" => %{"dry_run" => ["is invalid"]}}

    assert conn |> authed() |> delete(path <> "?dryRun=true") |> json_response(422) ==
             %{"errors" => %{"dryRun" => ["is unknown: this delete takes only dry_run"]}}

    assert %{"errors" => %{"id" => [_]}} =
             conn
             |> authed()
             |> delete("/api/v1/dashboards/template:overview")
             |> json_response(422)

    assert conn |> authed() |> delete(path) |> response(204) == ""
    assert Dashboards.get_dashboard(stored.id) == nil
    assert [_create, deleted] = entries()
    assert deleted.operation == :delete

    for dry_run <- ["", "?dry_run=true"] do
      assert conn |> authed() |> delete(path <> dry_run) |> json_response(404) ==
               %{"errors" => %{"detail" => "not found"}}
    end
  end

  # User story (ADR-0062 §11):
  # As the operator,
  # I want every dashboard route behind the API's bearer token,
  # so that no one without it reads or writes my layouts.
  #
  # Acceptance criteria:
  # - Each route without the token answers 401, and nothing is written.
  test "every route takes the bearer token", %{conn: conn} do
    stored = create!("Geschützt")

    for {method, path} <- [
          {:get, "/api/v1/widgets"},
          {:get, "/api/v1/dashboards"},
          {:get, "/api/v1/dashboards/#{stored.id}"},
          {:post, "/api/v1/dashboards"},
          {:put, "/api/v1/dashboards/#{stored.id}"},
          {:patch, "/api/v1/dashboards/#{stored.id}"},
          {:delete, "/api/v1/dashboards/#{stored.id}"}
        ] do
      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> dispatch(@endpoint, method, path, %{"dashboard" => %{"name" => "X"}})

      assert conn.status == 401, "#{method} #{path}"
    end

    assert [%{id: id, name: "Geschützt"}] = Dashboards.list_dashboards()
    assert id == stored.id
  end
end
