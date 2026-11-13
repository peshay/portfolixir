defmodule PortfolixirWeb.Browser.CycleChartTest do
  # The halving cycles on the security chart in a real browser (Sprint 29
  # H7; ADR-0060 §11, ADR-0059 §8; board ux-design-2026-11-12-sprint29/07,
  # ③ and ⑧). LiveViewTest runs no client script and lays nothing out, so
  # this test boots the endpoint on a free loopback port and drives the
  # chart in Chromium through `cycle_chart.js` with Playwright: in both
  # themes at 1200 and 390 px, and in the privacy mode.
  #
  # Excluded from the test job (test/test_helper.exs); run it with
  #
  #     mix test test/browser --only browser
  #
  # async: false -- the sandbox is shared with the LiveView processes the
  # browser's requests start. Synthetic data only, no external network.
  use PortfolixirWeb.ConnCase, async: false

  import Portfolixir.CycleFixtures, only: [synthetic_cycle_coin!: 0]

  @moduletag :browser
  @moduletag timeout: 300_000

  @script Path.expand("cycle_chart.js", __DIR__)

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
    %{base_url: "http://localhost:#{port}"}
  end

  # User story (ADR-0060 §11; plan row H7):
  # As the operator reading a coin's chart on the desk and on the phone,
  # in either theme and in the privacy mode,
  # I want the cycles, their bar and their tables to fit the screen,
  # so that I can switch them as I read and nothing runs off the page.
  #
  # Acceptance criteria (both themes, 1200 and 390 px; the privacy mode at
  # both widths):
  # - after „Max“ and „Zyklen“, then „Top – Top“, „Ausgerichtet“ and back,
  #   and with „Bänder und ihre Teile“ open, the page never scrolls
  #   sideways and the cycle bar stays inside the viewport;
  # - at 390 px each bar label stands over its controls (board 07 ⑧);
  # - every cycle label shown is at least 7 CSS px tall;
  # - the four halvings and the next low's band are drawn;
  # - in the privacy mode the axis is in percent and no price shows.
  test "the cycles fit at 1200 and 390 px, in both themes and the privacy mode", %{
    base_url: base_url
  } do
    coin = synthetic_cycle_coin!()

    {output, status} =
      System.cmd("node", [@script, base_url <> "/securities/#{coin.id}?tab=chart"],
        stderr_to_stdout: true
      )

    assert status == 0, "the browser run failed:\n" <> output

    result =
      output
      |> String.split("\n", trim: true)
      |> List.last()
      |> Jason.decode!()

    assert result["ok"] == true, inspect(result)
  end
end
