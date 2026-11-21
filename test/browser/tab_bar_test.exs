defmodule PortfolixirWeb.Browser.TabBarTest do
  # The menu by the window's size (ADR-0022's amendment of 2026-11-21,
  # point 5; ADR-0062 §6; planning board ux-design-2026-11-21-sprint31/01 ④;
  # Sprint 31 D7): the compact window's tab bar with „Mehr“ at 393 px, the
  # short-wide window's rail at 844 × 390, the sidebar from 900 px.
  # LiveViewTest renders the server's markup and applies no CSS, so the
  # class each window falls into is measured here: the test boots the
  # endpoint on a free loopback port, seeds two dashboards and drives
  # Chromium through `tab_bar.js` with Playwright. The server half (the
  # groups, the tabs, the sheet's entries, the switcher) is
  # test/portfolixir_web/live/menu_test.exs.
  #
  # Excluded from the test job (test/test_helper.exs): it needs Node, the
  # Playwright test/browser/package-lock.json pins and its Chromium, which
  # CI's `browser` job installs. Run it with
  #
  #     mix test test/browser --only browser
  #
  # async: false -- the sandbox is shared, so the LiveView processes the
  # browser's requests start read the dashboards this test seeds. Synthetic
  # names only, no external network: the browser talks to 127.0.0.1.
  #
  # group: :dashboards -- a create takes the advisory lock that counts the
  # dashboards (`Portfolixir.LockTable`).
  use PortfolixirWeb.ConnCase, async: false, group: :dashboards

  alias Portfolixir.Actor
  alias Portfolixir.Dashboards

  @moduletag :browser
  @moduletag timeout: 180_000

  @script Path.expand("tab_bar.js", __DIR__)

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

    layout = [%{"kind" => "due", "size" => "S", "col" => 1, "row" => 1}]

    {:ok, alpha} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Alpha", "layout" => layout})

    {:ok, beta} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Beta", "layout" => layout})

    # "localhost", the endpoint's configured host, so the LiveView socket's
    # origin check passes.
    %{
      base_url: "http://localhost:#{port}",
      paths: ["/dashboards/#{alpha.id}", "/dashboards/#{beta.id}"]
    }
  end

  # User story (ADR-0022's amendment, point 5; ADR-0062 §6):
  # As the operator on a phone, upright or turned sideways,
  # I want the menu as a bar at the foot, or a rail at the side when the
  # window is short and wide, and the sidebar on a wider window,
  # so that I reach every page with a thumb and the page keeps its room.
  #
  # Acceptance criteria:
  # - At 393 × 852 the bar sits at the foot, four tabs of at least 44 px in
  #   one row, no burger, no sideways scroll, the page's end above the
  #   bar; the title opens the dashboard switcher; „Mehr“ opens a sheet
  #   above the bar with rows of at least 44 px, whose „Alle Widgets“
  #   opens that page with „Mehr“ marked.
  # - At 844 × 390 the bar is a 72 px rail at the side, its tabs one under
  #   the other, the page beside it and „Mehr“ opening beside it.
  # - At 915 × 412 and 1200 × 800 the sidebar is the menu: no bar and no
  #   switcher.
  test "the tab bar, „Mehr“ and the side rail, by the window's size", %{
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
