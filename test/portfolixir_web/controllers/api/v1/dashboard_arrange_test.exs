defmodule PortfolixirWeb.Api.V1.DashboardArrangeTest do
  # Sprint 32 E3 (ADR-0062's amendment of 2026-11-25, point 2; I58): the
  # API stays strict. A replace that overlaps is still refused with 422 and
  # nothing is repaired silently; an agent that wants the others to make
  # room sends `arrange: "push"` and `arranged_index`, the index of the
  # item it changed in the layout it sends, inside `dashboard`, and the
  # server applies the arrangement (`Portfolixir.Dashboards.Arrange`, the
  # edit mode's rule) before it validates. Every name is synthetic.
  #
  # group: :dashboards -- every module that creates a dashboard joins it
  # (the create's count lock, `Portfolixir.LockTable` row 30).
  use PortfolixirWeb.ConnCase, async: true, group: :dashboards

  alias Portfolixir.Actor
  alias Portfolixir.Dashboards
  alias Portfolixir.Journal

  defp authed(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  defp item(kind, size, col, row),
    do: %{"kind" => kind, "size" => size, "col" => col, "row" => row}

  defp create!(layout) do
    {:ok, dashboard} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Arranged", "layout" => layout})

    dashboard
  end

  defp put_dashboard(conn, dashboard, body, status) do
    conn
    |> authed()
    |> put("/api/v1/dashboards/#{dashboard.id}", %{
      "dashboard" =>
        Map.merge(
          %{"name" => dashboard.name, "lock_version" => dashboard.lock_version},
          body
        )
    })
    |> json_response(status)
  end

  defp places(layout), do: Enum.map(layout, &{&1["kind"], &1["size"], &1["col"], &1["row"]})

  defp journal_count, do: length(Journal.list_entries(resource_type: "dashboard"))

  # A two-row dashboard: Tops und Flops and Crashes side by side under
  # Snapshots. The agent widens Snapshots to cover Tops und Flops.
  defp before,
    do: [
      item("snapshots", "S", 1, 1),
      item("movers", "M", 1, 2),
      item("crashes", "M", 7, 2)
    ]

  defp widened, do: List.replace_at(before(), 0, item("snapshots", "W", 1, 2))

  # User story:
  # As the agent the operator runs,
  # I want to ask the server to make room for the item I changed,
  # so that I can resize or move one widget without placing every other
  # one myself, and still never have a layout rearranged I did not ask for.
  #
  # Acceptance criteria:
  # - The same overlapping layout without `arrange` is refused with 422
  #   naming the item it overlaps, and nothing is written.
  # - With `arrange: "push"` and `arranged_index: 0`, the item sent at
  #   index 0 keeps the place it was given, what it covers moves on to the
  #   next free place after its own in reading order, then every gap closes;
  #   the answer and the stored layout are that arrangement, one journal
  #   entry more, lock_version up by one.
  test "arrange: push makes room for the changed item; without it an overlap is 422",
       %{conn: conn} do
    dashboard = create!(before())

    assert %{"errors" => %{"layout_item" => %{"reason" => "overlap", "index" => 1, "other" => 0}}} =
             put_dashboard(conn, dashboard, %{"layout" => widened()}, 422)

    assert Dashboards.get_dashboard(dashboard.id).lock_version == dashboard.lock_version
    assert journal_count() == 1

    %{"data" => data} =
      put_dashboard(
        conn,
        dashboard,
        %{"layout" => widened(), "arrange" => "push", "arranged_index" => 0},
        200
      )

    # Snapshots W at row 2 covers Tops und Flops (columns 1 to 6, row 2):
    # Tops und Flops moves on to the next free place after its own, column
    # 7 of row 2, which Crashes then gives up for the next after its own,
    # row 3; then the gaps close: Tops und Flops floats to row 1, Crashes
    # stays under Snapshots, and Snapshots keeps the place it was given.
    assert places(data["layout"]) == [
             {"snapshots", "W", 1, 2},
             {"movers", "M", 7, 1},
             {"crashes", "M", 1, 3}
           ]

    stored = Dashboards.get_dashboard(dashboard.id)
    assert places(stored.layout) == places(data["layout"])
    assert stored.lock_version == dashboard.lock_version + 1
    assert journal_count() == 2
  end

  # Acceptance criteria (the refusals, each 422, nothing written):
  # - `arrange` other than "push", `arrange` without `arranged_index`,
  #   `arranged_index` without `arrange`, and an `arranged_index` that is
  #   no whole number naming an item of the layout sent, each naming the
  #   field.
  # - A layout whose items are bad in themselves is refused as it would be
  #   without `arrange`, naming the first bad item: the arrangement repairs
  #   no item, it only moves the others.
  # - A layout that has no place left up to row 200 for what must move is
  #   refused with `layout_item.reason` `no_room` at the item arranged.
  test "the arrangement's own refusals", %{conn: conn} do
    dashboard = create!(before())

    refused = fn body ->
      put_dashboard(conn, dashboard, Map.put(body, "layout", widened()), 422)["errors"]
    end

    assert %{"arrange" => [_]} = refused.(%{"arrange" => "always", "arranged_index" => 0})
    assert %{"arrange" => [_]} = refused.(%{"arrange" => true, "arranged_index" => 0})
    assert %{"arranged_index" => [_]} = refused.(%{"arrange" => "push"})
    assert %{"arrange" => [_]} = refused.(%{"arranged_index" => 0})
    assert %{"arranged_index" => [_]} = refused.(%{"arrange" => "push", "arranged_index" => 3})
    assert %{"arranged_index" => [_]} = refused.(%{"arrange" => "push", "arranged_index" => -1})
    assert %{"arranged_index" => [_]} = refused.(%{"arrange" => "push", "arranged_index" => "0"})

    assert %{"layout_item" => %{"index" => 3, "field" => "kind", "reason" => "unknown_kind"}} =
             put_dashboard(
               conn,
               dashboard,
               %{
                 "layout" => widened() ++ [item("nonsense", "S", 1, 9)],
                 "arrange" => "push",
                 "arranged_index" => 0
               },
               422
             )["errors"]

    # Wertentwicklung placed at row 200 over Tops und Flops: what it covers
    # finds no place beside it and can only go below row 200.
    tall = [item("performance", "L", 1, 1), item("movers", "M", 1, 200)]
    tall_dashboard = create!(tall)

    assert %{"layout_item" => %{"index" => 0, "reason" => "no_room"}} =
             put_dashboard(
               conn,
               tall_dashboard,
               %{
                 "layout" => List.replace_at(tall, 0, item("performance", "L", 1, 200)),
                 "arrange" => "push",
                 "arranged_index" => 0
               },
               422
             )["errors"]

    assert Dashboards.get_dashboard(dashboard.id).layout == dashboard.layout
    assert journal_count() == 2
  end
end
