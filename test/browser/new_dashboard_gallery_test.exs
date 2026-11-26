defmodule PortfolixirWeb.Browser.NewDashboardGalleryTest do
  # „Neues Dashboard“'s gallery and its dialog (Sprint 32 S4; board
  # ux-design-2026-11-25-sprint32/03 ① and ②), in a real browser (the S32
  # closing act). LiveViewTest applies no CSS, so the groups' headings and
  # the dialog's footer are measured here: the test boots the endpoint on
  # a free loopback port and drives Chromium through
  # `new_dashboard_gallery.js`. The gallery's markup and its creates:
  # test/portfolixir_web/live/new_dashboard_test.exs.
  #
  # Excluded from the test job (test/test_helper.exs): run it with
  #
  #     mix test test/browser --only browser
  #
  # async: false -- the sandbox is shared with the LiveView processes the
  # browser's requests start. No data is seeded; no external network: the
  # browser talks to 127.0.0.1.
  use PortfolixirWeb.ConnCase, async: false

  @moduletag :browser
  @moduletag timeout: 180_000

  @script Path.expand("new_dashboard_gallery.js", __DIR__)

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

  # User story (board 03 ① and ②; the S32 closing act):
  # As the operator choosing a template,
  # I want the groups named by quiet labels and the dialog's buttons off
  # its edges,
  # so that the cards lead and a focused button's ring is whole.
  #
  # Acceptance criteria:
  # - At 1200 and at 393 px the two group headings are drawn at 12 px at
  #   most, in a colour other than the body text's.
  # - The dialog's „Abbrechen“ and „Anlegen“ keep 16 px or more off its
  #   left, right and bottom edges.
  test "the gallery's headings are small labels and its dialog's buttons keep off the edges", %{
    base_url: base_url
  } do
    {output, status} =
      System.cmd("node", [@script, Jason.encode!(%{base_url: base_url})], stderr_to_stdout: true)

    assert status == 0, "the browser run failed:\n" <> output

    result =
      output
      |> String.split("\n", trim: true)
      |> List.last()
      |> Jason.decode!()

    assert result == %{"ok" => true}, output
  end
end
