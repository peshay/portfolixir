defmodule PortfolixirWeb.Browser.DashboardEditTest do
  # The dashboard's edit mode (ADR-0062 §7; idea board
  # ux-design-2026-11-21-idea-i56 03; Sprint 31 D6), in a real browser.
  # LiveViewTest renders the server's markup and runs no client script, so
  # the DashboardEdit hook (the drag on the wide grid, the focus kept on a
  # handle, the arrow keys kept from scrolling) is read here: the test
  # boots the endpoint on a free loopback port, seeds a synthetic world and
  # one dashboard, drives Chromium through `dashboard_edit.js` with
  # Playwright, and then reads the layout the save stored. The server half
  # (every step, refusal, announcement and the one journal entry) is
  # test/portfolixir_web/live/dashboard_edit_test.exs.
  #
  # Excluded from the test job (test/test_helper.exs): it needs Node, the
  # Playwright test/browser/package-lock.json pins and its Chromium, which
  # CI's `browser` job installs. Run it with
  #
  #     mix test test/browser --only browser
  #
  # async: false -- the sandbox is shared, so the LiveView processes the
  # browser's requests start read the world this test seeds. Synthetic data
  # only, no external network: the browser talks to 127.0.0.1.
  #
  # group: :dashboards -- a create takes the advisory lock that counts the
  # dashboards (`Portfolixir.LockTable` row 30).
  use PortfolixirWeb.ConnCase, async: false, group: :dashboards

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quotes!: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Clock
  alias Portfolixir.Dashboards
  alias Portfolixir.Journal

  @moduletag :browser
  @moduletag timeout: 180_000

  @script Path.expand("dashboard_edit.js", __DIR__)

  setup do
    server =
      PortfolixirWeb.TestListener.start!(
        {Bandit,
         plug: PortfolixirWeb.Endpoint,
         scheme: :http,
         ip: {127, 0, 0, 1},
         port: 0,
         startup_log: false}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)

    # Invented names and figures: one deposit and one buy a year and a
    # half ago, a close then and today.
    today = Clock.today()
    start = Date.add(today, -540)
    world = base_world(name: "Edit World", cash_name: "Giro", depot_name: "Depot")
    deposit!(world, "1000", start)
    security = create_security!(name: "Edit Synthetic ETF")
    buy!(world, security, quantity: "8", price: "100", date: start)
    put_quotes!(security, [{start, "100"}, {Date.add(today, -100), "110"}, {today, "121"}])

    layout = [
      %{"kind" => "performance", "size" => "L", "col" => 1, "row" => 1},
      %{"kind" => "movers", "size" => "L", "col" => 7, "row" => 1},
      %{"kind" => "crashes", "size" => "L", "col" => 1, "row" => 5}
    ]

    {:ok, dashboard} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Alpha", "layout" => layout})

    # "localhost", the endpoint's configured host, so the LiveView socket's
    # origin check passes.
    %{base_url: "http://localhost:#{port}", dashboard: dashboard}
  end

  defp run(base_url, args) do
    {output, status} =
      System.cmd("node", [@script, Jason.encode!(Map.put(args, :base_url, base_url))],
        stderr_to_stdout: true
      )

    assert status == 0, "the browser run failed:\n" <> output

    result =
      output
      |> String.split("\n", trim: true)
      |> List.last()
      |> Jason.decode!()

    assert result == %{"ok" => true}, output
  end

  # User story (S32 closing act; board ux-design-2026-11-25-sprint32/01 ③;
  # EXPERIENCE.md's edit mode: "the widgets keep their content"):
  # As the operator arranging „Überblick“,
  # I want the edit controls to lie over each tile, not to push its
  # content out,
  # so that I see what I move, also in the small tiles.
  #
  # Acceptance criteria:
  # - At 1200 px, in the edit mode, every widget's title stands no lower
  #   and its footer as deep in its tile as outside the mode; the size switch
  #   lies inside the tile, clear of the footer's words; the handle and ×
  #   lie clear of the title and its ⓘ.
  # - „Gesamtwert“ sized to M shows its figure inside its tile.
  test "the edit controls lie over the tiles, and „Gesamtwert“ at M keeps its figure", %{
    base_url: base_url
  } do
    {:ok, overview} = Dashboards.copy_template(Actor.owner_ui(), "overview", %{})
    run(base_url, %{path: "/dashboards/#{overview.id}", mode: "tiles"})
  end

  # User story (ADR-0062 §7, board 03):
  # As the operator rearranging a dashboard by keyboard or by pointer,
  # I want each step said aloud and the save to store what I see,
  # so that the edit mode works without a mouse and without sight, and a
  # drag lands where I dropped it.
  #
  # Acceptance criteria:
  # - On the wide grid, an arrow key on a widget's handle moves it one
  #   column and the polite live region at the widget says so; a step onto
  #   other widgets moves them on (Sprint 32 E2); the focus stays on the
  #   handle and the page does not scroll.
  # - A drag of a handle below the grid places the widget in the row under
  #   the last, at the column under its corner, and says so.
  # - Board ux-design-2026-11-25-sprint32/01 ①: a size clicked on the last
  #   widget, scrolled to the page's foot, is answered under the widget,
  #   inside the window, with „Undo“; Ctrl+Z takes the step back.
  # - „Done“ stores the layout drawn, as one journal entry after the create.
  # - At 393 px the edit mode offers reorder, size and remove (44 px
  #   targets), no handle and no catalogue, and the page never scrolls
  #   sideways; a reorder is said with its position.
  test "the edit mode moves by keyboard and by drag, says each step, and saves once", %{
    base_url: base_url,
    dashboard: dashboard
  } do
    {output, status} =
      System.cmd(
        "node",
        [@script, Jason.encode!(%{base_url: base_url, path: "/dashboards/#{dashboard.id}"})],
        stderr_to_stdout: true
      )

    assert status == 0, "the browser run failed:\n" <> output

    result =
      output
      |> String.split("\n", trim: true)
      |> List.last()
      |> Jason.decode!()

    assert result == %{"ok" => true}, output

    stored = Dashboards.get_dashboard(dashboard.id)
    assert stored.lock_version == dashboard.lock_version + 1

    assert [
             %{"kind" => "performance", "col" => 1, "row" => 1},
             %{"kind" => "movers", "col" => 7, "row" => movers_row},
             %{"kind" => "crashes", "col" => 7, "row" => 1}
           ] = stored.layout

    assert movers_row > 5

    assert [%{operation: :create}, %{operation: :update}] =
             Journal.list_entries(resource_type: "dashboard") |> Enum.sort_by(& &1.id)
  end
end
