defmodule PortfolixirWeb.Browser.CycleCardTest do
  # The range „Zyklus“, the dashboard card „‹Name›-Zyklus“ and the
  # „Halving-Kette“ question in a real browser (Sprint 29 H8; ADR-0060 §11,
  # ADR-0059 §4, §11; board ux-design-2026-11-12-sprint29/07 ①, ②, ⑤, ⑧).
  # LiveViewTest runs no client script and lays nothing out, so this test
  # boots the endpoint on a free loopback port and walks the card, the
  # chart and the dialog in Chromium through `cycle_card.js` with
  # Playwright, in both themes at 1200 and 390 px.
  #
  # Excluded from the test job (test/test_helper.exs); run it with
  #
  #     mix test test/browser --only browser
  #
  # async: false -- the sandbox is shared with the LiveView processes the
  # browser's requests start. Synthetic data only, no external network: the
  # coin is bound to Bitcoin for „Jetzt lesen“, which the walk never presses.
  use PortfolixirWeb.ConnCase, async: false

  import Portfolixir.CycleFixtures, only: [synthetic_cycle_coin!: 1, recent_shift: 1]

  @moduletag :browser
  @moduletag timeout: 300_000

  @script Path.expand("cycle_card.js", __DIR__)

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

  # User story (ADR-0060 §11; ADR-0059 §4, §11; plan row H8):
  # As the operator on the desk and on the phone, in either theme,
  # I want the card, the range „Zyklus“ and the question before halving
  # events are deleted to fit the screen,
  # so that one click from the Übersicht shows the bands and nothing runs
  # off the page.
  #
  # Acceptance criteria (both themes, 1200 and 390 px):
  # - the card „‹Name›-Zyklus“ with both events stays inside the viewport;
  # - its link opens the chart with „Zyklus“ chosen, both bands and the
  #   „heute“ line drawn, the cycle bar and „Jetzt lesen“ inside the
  #   viewport;
  # - in „Bearbeiten“, „Halving-Kette“ set to none shows the warning and
  #   „Speichern und 5 Ereignisse löschen“, inside the viewport;
  # - the page never scrolls sideways.
  test "the card, the range „Zyklus“ and the question fit at 1200 and 390 px", %{
    base_url: base_url
  } do
    coin =
      synthetic_cycle_coin!(
        name: "Synthetic Cycle Coin",
        chain: :bitcoin,
        shift_days: recent_shift(Portfolixir.Clock.today()),
        next_window_days: 25
      )

    {output, status} =
      System.cmd("node", [@script, base_url, Integer.to_string(coin.id)], stderr_to_stdout: true)

    assert status == 0, "the browser run failed:\n" <> output

    result =
      output
      |> String.split("\n", trim: true)
      |> List.last()
      |> Jason.decode!()

    assert result["ok"] == true, inspect(result)
  end
end
