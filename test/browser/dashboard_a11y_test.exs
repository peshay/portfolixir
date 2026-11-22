defmodule PortfolixirWeb.Browser.DashboardA11yTest do
  # The dashboard's keyboard, focus and touch paths in a real browser
  # (ADR-0062 §6, §7; Sprint 31 closing act, the accessibility lens's
  # findings Y1 to Y5; planning board ux-design-2026-11-21-sprint31/02 ⑥).
  # LiveViewTest renders the server's markup and runs neither the client
  # script nor CSS, so where the focus lands after a step, which tab stops
  # are on screen and how large a target is drawn are read here: the test
  # boots the endpoint on a free loopback port, seeds a synthetic world and
  # one dashboard and drives Chromium through `dashboard_a11y.js` with
  # Playwright. The walk answers one result per check; the test asserts
  # each, naming the ones that failed.
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

  @moduletag :browser
  @moduletag timeout: 300_000

  @script Path.expand("dashboard_a11y.js", __DIR__)

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
    today = Clock.today()
    start = Date.add(today, -540)
    world = base_world(name: "A11y World", cash_name: "Giro", depot_name: "Depot")
    deposit!(world, "1000", start)
    security = create_security!(name: "A11y Synthetic ETF")
    buy!(world, security, quantity: "8", price: "100", date: start)
    put_quotes!(security, [{start, "100"}, {Date.add(today, -100), "110"}, {today, "121"}])

    layout = [
      %{"kind" => "performance", "size" => "L", "col" => 1, "row" => 1},
      %{"kind" => "movers", "size" => "M", "col" => 1, "row" => 4},
      %{"kind" => "crashes", "size" => "M", "col" => 7, "row" => 4}
    ]

    {:ok, dashboard} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Alpha", "layout" => layout})

    # "localhost", the endpoint's configured host, so the LiveView socket's
    # origin check passes.
    %{base_url: "http://localhost:#{port}", dashboard: dashboard}
  end

  # User story (ADR-0062 §7; Sprint 31 closing act, Y1):
  # As the operator who reorders a phone's dashboard with a keyboard or a
  # switch device,
  # I want the focus to stay on the control I used, on the widget I moved,
  # so that the next press moves it again instead of starting over at the
  # top of the page.
  #
  # Acceptance criteria:
  # - At 393 px, after ↑ on a widget the focus is on that widget's ↑, shown.
  # - After × the focus is on a shown control of the next widget, and the
  #   next Tab stays in the dashboard.
  #
  # User story (ADR-0022, amendment of 2026-11-21; Y2):
  # As the operator who tabs through a page on a phone, a phone turned
  # sideways or a tablet,
  # I want every tab stop to be one I can see,
  # so that I never press Tab thirteen times through a menu that is not
  # on the screen.
  #
  # Acceptance criteria:
  # - At 393 × 852, 852 × 393 and 834 × 1112 the first 16 Tab stops are
  #   on screen; the closed sidebar is hidden (no shadow at the edge).
  # - Where the tab bar or the rail is the menu, the sidebar's toggle is
  #   hidden too.
  #
  # User story (ADR-0062 §7; Y3):
  # As the operator who opens and closes the edit mode with a keyboard,
  # I want the focus on the next thing I will press,
  # so that the button I pressed vanishing does not drop me at the top.
  #
  # Acceptance criteria:
  # - After „Bearbeiten“ the focus is on the first widget's handle.
  # - After a stale save's „Weiter bearbeiten“ it is on „Fertig“.
  # - After „Fertig“ (a save, or nothing to save) it is on „Bearbeiten“.
  #
  # User story (ADR-0062 §6; Y4):
  # As the operator who picks a period on a phone with a keyboard,
  # I want the chip I tab to scrolled into the strip,
  # so that I see which period I am on before I press it.
  #
  # Acceptance criteria:
  # - At 375 and 393 px, Tab from „3J“ to „Max“ shows „Max“ whole inside
  #   the strip.
  test "the focus, the tab stops and the targets of the dashboard", %{
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

    result = output |> String.split("\n", trim: true) |> List.last() |> Jason.decode!()
    assert result["ok"] == true, result["error"] || inspect(result)
    failed = Enum.reject(result["checks"], & &1["ok"])
    assert failed == [], Enum.map_join(failed, "\n", &"#{&1["id"]}: #{&1["detail"]}")
  end
end
