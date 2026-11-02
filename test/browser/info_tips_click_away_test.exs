defmodule PortfolixirWeb.Browser.InfoTipsClickAwayTest do
  # The ⓘ panels as one popover, in a real browser (Sprint 23 C1, the
  # owner's report of 2026-11-02; plan D-11, D-1 criterion 5). LiveViewTest
  # renders the server's markup and runs no client script, so this test
  # boots the endpoint on a free loopback port and drives Chromium through
  # `info_tips_click_away.js` with Playwright.
  #
  # Excluded by default (test/test_helper.exs): it needs Node, the
  # `playwright` package on Node's module path and its Chromium, which the
  # CI test job does not install. Run it with
  #
  #     mix test test/browser --only browser
  #
  # async: false -- the sandbox is shared, so the LiveView processes the
  # browser's requests start read the world this test seeds. Synthetic data
  # only, no external network: the browser talks to 127.0.0.1.
  use PortfolixirWeb.ConnCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.WorldFixtures

  @moduletag :browser
  @moduletag timeout: 120_000

  @script Path.expand("info_tips_click_away.js", __DIR__)

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

  # User story (C1):
  # As the operator reading a page full of ⓘ,
  # I want the ⓘ panels to behave as one popover,
  # so that a panel I have read does not stay open over the figures beside
  # it once I move on.
  #
  # Acceptance criteria:
  # - Opening an ⓘ, by pointer or keyboard, closes any other open ⓘ.
  # - A click or a tap inside an open panel leaves it open.
  # - A click or a tap anywhere else closes it; the click still lands where
  #   it was aimed and the focus goes where the click put it, never back to
  #   the ⓘ.
  # - Escape still closes the ⓘ and returns the focus to its summary (#1342).
  test "opening one ⓘ closes the other, and a click elsewhere closes it", %{base_url: base_url} do
    # Wealth's world, as PortfolixirWeb.InfoTipsTest seeds it.
    WorldFixtures.base_world(name: "Demo Portfolio")
    {:ok, _} = Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

    {output, status} =
      System.cmd("node", [@script, base_url <> "/portfolio"], stderr_to_stdout: true)

    assert status == 0, "the browser run failed:\n" <> output

    result =
      output
      |> String.split("\n", trim: true)
      |> List.last()
      |> Jason.decode!()

    assert result == %{"ok" => true}
  end
end
