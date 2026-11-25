defmodule PortfolixirWeb.Browser.DashboardPeriodTest do
  # One period above every dashboard (ADR-0062 §5, §6; idea board
  # ux-design-2026-11-21-idea-i56 05, A; Sprint 31 D5), remembered per
  # browser. LiveViewTest renders the server's markup and runs no client
  # script, so the PeriodMemory hook's storage under `dashboard.period` is
  # read here: the test boots the endpoint on a free loopback port, seeds a
  # synthetic world and two dashboards, and drives Chromium through
  # `dashboard_period.js` with Playwright. The server half (the address, the
  # restore event, the pin) is
  # test/portfolixir_web/live/dashboard_period_test.exs.
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
  @moduletag timeout: 180_000

  @script Path.expand("dashboard_period.js", __DIR__)

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
    world = base_world(name: "Period World", cash_name: "Giro", depot_name: "Depot")
    deposit!(world, "1000", start)
    security = create_security!(name: "Period Synthetic ETF")
    buy!(world, security, quantity: "8", price: "100", date: start)
    put_quotes!(security, [{start, "100"}, {Date.add(today, -100), "110"}, {today, "121"}])

    layout = [
      %{"kind" => "performance", "size" => "XL", "col" => 1, "row" => 1},
      %{"kind" => "movers", "size" => "L", "col" => 1, "row" => 5},
      %{"kind" => "crashes", "size" => "L", "col" => 7, "row" => 5}
    ]

    pinned =
      Enum.map(layout, fn
        %{"kind" => "movers"} = item -> Map.put(item, "settings", %{"period" => "max"})
        item -> item
      end)

    {:ok, alpha} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Alpha", "layout" => layout})

    {:ok, beta} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Beta", "layout" => pinned})

    # "localhost", the endpoint's configured host, so the LiveView socket's
    # origin check passes.
    %{
      base_url: "http://localhost:#{port}",
      paths: ["/dashboards/#{alpha.id}", "/dashboards/#{beta.id}"]
    }
  end

  # User story (ADR-0062 §5, board 05 A):
  # As the operator who picked a period on one dashboard,
  # I want every dashboard I open next to show the same period,
  # so that two dashboards never show two spans unasked.
  #
  # Acceptance criteria:
  # - A pick on one dashboard is kept under `dashboard.period`; another
  #   dashboard opened fresh, its address naming none, opens on it and its
  #   address names it; a pinned widget keeps its own period.
  # - 1J picked is kept too; an address that names a period wins.
  # - At 393 px the period is a strip of its own row that scrolls
  #   sideways, its chips at least 44 px tall, „Max“ reachable, and the
  #   page never scrolls sideways.
  # - With the browser's storage blocked, the page opens on 1J, a pick
  #   works, the next dashboard opens on 1J, with no script error.
  test "the period is remembered per browser and kept across dashboards", %{
    base_url: base_url,
    paths: paths
  } do
    {output, status} =
      System.cmd("node", [@script, Jason.encode!(%{base_url: base_url, paths: paths})],
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
end
