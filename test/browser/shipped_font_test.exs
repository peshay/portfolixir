defmodule PortfolixirWeb.Browser.ShippedFontTest do
  # The app's own Inter, in a real browser (Sprint 30 F1, #1221; plan D-4
  # and D-1 criterion 1, board ux-design-2026-11-15-sprint30/03). Until F1
  # `--font-sans` named Inter but no font file shipped, so a device without
  # Inter drew every page in its own sans and every width floor depended on
  # it. LiveViewTest loads no font and runs no layout, so this test boots
  # the endpoint on a free loopback port and drives Chromium through
  # `shipped_font.js` with Playwright.
  #
  # Excluded from the test job (test/test_helper.exs): it needs Node, the
  # Playwright test/browser/package-lock.json pins and its Chromium, which
  # CI's `browser` job installs. Run it with
  #
  #     mix test test/browser --only browser
  #
  # async: false -- the sandbox is shared, so the LiveView processes the
  # browser's requests start read the world this test seeds (none: an empty
  # instance). No external network: the browser talks to 127.0.0.1, and the
  # test asserts that no request leaves for another origin.
  use PortfolixirWeb.ConnCase, async: false

  @moduletag :browser
  @moduletag timeout: 120_000

  @script Path.expand("shipped_font.js", __DIR__)

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

  # User story (Sprint 30 F1, #1221):
  # As an operator on a device without Inter installed,
  # I want every page to draw in the app's own Inter, and to come up in the
  # fallback when the font file cannot load,
  # so that the pages read as they were measured, and a missing font never
  # costs me a working page.
  #
  # Acceptance criteria:
  # - The Overview loads Inter from the app's own /fonts/ (the latin face,
  #   loaded), the walks' font check passes, and no request leaves the
  #   app's origin.
  # - With every request under /fonts/ refused, the page connects, its text
  #   draws in the stack after Inter (the same width as that stack), the
  #   Inter faces stand at `error`, and the walks' font check refuses the
  #   page: a walk never measures the fallback as Inter.
  # - The check refuses a page whose Inter comes from `local()`, one that
  #   declares no Inter face, and one whose face names a file the app does
  #   not serve; it passes the app's own faces drawn on a walk's page.
  test "the page draws in its own Inter, and in the fallback, connected, when the font is blocked",
       %{base_url: base_url} do
    {output, status} = System.cmd("node", [@script, base_url], stderr_to_stdout: true)
    assert status == 0, "the browser run failed:\n" <> output

    result =
      output
      |> String.split("\n", trim: true)
      |> List.last()
      |> Jason.decode!()

    assert result["ok"] == true, output

    own = result["own"]
    assert own["check"] == nil, output
    assert own["font"]["loaded"] == true, output
    assert "/fonts/inter-latin-wght-normal.woff2" in own["font"]["fetched"], output
    assert own["foreign"] == [], output

    blocked = result["blocked"]
    assert blocked["connected"] == true, output
    assert blocked["heading"] == true, output
    assert "/fonts/inter-latin-wght-normal.woff2" in blocked["blocked"], output
    assert blocked["font"]["loaded"] == false, output
    refute "loaded" in blocked["font"]["faces"], output
    assert "error" in blocked["font"]["faces"], output
    assert blocked["widths"]["own"] == blocked["widths"]["rest"], output
    assert blocked["check"] =~ "did not load it: no Inter face loaded", output

    attacks = result["attacks"]
    assert attacks["own"] == nil, output
    assert attacks["local"] =~ "loads from elsewhere than /fonts/", output
    assert attacks["none"] =~ "declares no @font-face for Inter", output
    assert attacks["missing"] =~ "no Inter face loaded", output
  end
end
