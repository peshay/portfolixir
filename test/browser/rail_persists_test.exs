defmodule PortfolixirWeb.Browser.RailPersistsTest do
  # The sidebar's collapsed rail across pages, in a real browser (Sprint 24
  # P2, #1357's rail line, the owner's report of 2026-11-04). LiveViewTest
  # renders the server's markup and runs no client script or CSS, so this
  # test boots the endpoint on a free loopback port and drives Chromium
  # through `rail_persists.js` with Playwright. The server half, the cookie
  # and the render, is test/portfolixir_web/plugs/rail_preference_test.exs.
  #
  # Excluded from the test job (test/test_helper.exs): it needs Node, the
  # Playwright test/browser/package-lock.json pins and its Chromium, which
  # CI's `browser` job installs. Run it with
  #
  #     mix test test/browser --only browser
  #
  # async: false -- the sandbox is shared, so the LiveView processes the
  # browser's requests start read the world this test seeds (none: an empty
  # instance). No external network: the browser talks to 127.0.0.1.
  use PortfolixirWeb.ConnCase, async: false

  @moduletag :browser
  @moduletag timeout: 120_000

  @script Path.expand("rail_persists.js", __DIR__)

  setup do
    server =
      start_supervised!(
        {Bandit,
         plug: PortfolixirWeb.Endpoint,
         scheme: :http,
         ip: {127, 0, 0, 1},
         port: 0,
         startup_log: false}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    # "localhost", the endpoint's configured host, so the LiveView socket's
    # origin check passes.
    %{base_url: "http://localhost:#{port}"}
  end

  # User story (P2):
  # As the operator who collapsed the sidebar to its rail on a phone,
  # I want the rail to stay collapsed when I follow a menu item,
  # so that the navigation does not open again over the page at every step.
  #
  # Acceptance criteria:
  # - On a phone held sideways (915 px, wider than the 900 px breakpoint),
  #   the toggle collapses the rail and asks the server to remember it.
  # - A live redirect (data-phx-link="redirect") keeps the rail collapsed,
  #   with no frame showing it expanded.
  # - A sidebar link, a full page load, renders the rail collapsed before
  #   any script runs, and it stays collapsed once the page is connected;
  #   the checkbox is checked while the rail is collapsed.
  # - Expanded again, the next full load opens expanded.
  # - Turned upright (390 px), the remembered rail does not open the
  #   off-canvas sidebar.
  test "a collapsed rail stays collapsed through a live redirect and a sidebar link", %{
    base_url: base_url
  } do
    {output, status} = System.cmd("node", [@script, base_url], stderr_to_stdout: true)

    assert status == 0, "the browser run failed:\n" <> output

    result =
      output
      |> String.split("\n", trim: true)
      |> List.last()
      |> Jason.decode!()

    assert result == %{"ok" => true}
  end
end
