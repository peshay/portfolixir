defmodule PortfolixirWeb.Browser.StorageBlockedTest do
  # The page with the browser's site storage blocked, in a real browser
  # (Sprint 29 M4, #1439). A browser that blocks site data throws a
  # SecurityError on the first read of `window.localStorage`; the theme
  # boot script, the theme control and the LiveView client all read it.
  # LiveViewTest renders the server's markup and runs no client script, so
  # this test boots the endpoint on a free loopback port and drives
  # Chromium through `storage_blocked.js` with Playwright.
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

  @script Path.expand("storage_blocked.js", __DIR__)

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
    # "localhost", the endpoint's configured host, so the LiveView socket's
    # origin check passes.
    %{base_url: "http://localhost:#{port}"}
  end

  # User story (M4, #1439):
  # As the operator whose browser blocks site data,
  # I want the page to come up and keep working,
  # so that a privacy setting does not leave me with a page that never
  # connects.
  #
  # Acceptance criteria:
  # - With every read of `localStorage` and `sessionStorage` throwing, the
  #   page connects and no script on it throws.
  # - It comes up in the system theme and the default accent, with the
  #   controls marking both, and follows the system's colour scheme (dark,
  #   then light).
  # - The theme and accent controls still change the page; a LiveView update
  #   keeps the controls marking what the page shows.
  test "with site storage blocked the page connects in the system theme and keeps working", %{
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
