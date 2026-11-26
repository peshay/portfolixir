defmodule PortfolixirWeb.Browser.DashboardCrashChartTest do
  # The widget „Crash-Chart“ (Sprint 32 S5; board
  # ux-design-2026-11-25-sprint32/11 ① and ②), its window labels in a real
  # browser (the S32 closing act). LiveViewTest renders the server's markup
  # and lays nothing out, so the labels' size and their overprint are
  # measured here: the test boots the endpoint on a free loopback port,
  # seeds a synthetic crash world and a copy of „Rücksetzer“, and drives
  # Chromium through `dashboard_crash_chart.js`. The labels' words against
  # the crash route: test/portfolixir_web/live/dashboard_crash_chart_widget_test.exs.
  #
  # Excluded from the test job (test/test_helper.exs): run it with
  #
  #     mix test test/browser --only browser
  #
  # async: false -- the sandbox is shared, so the LiveView processes the
  # browser's requests start read the world this test seeds. Synthetic data
  # only, no external network: the browser talks to 127.0.0.1.
  #
  # group: :dashboards -- a create takes the advisory lock that counts the
  # dashboards (`Portfolixir.LockTable` row 30); a module that runs alone
  # (async: false) may choose the crash benchmark too.
  use PortfolixirWeb.ConnCase, async: false, group: :dashboards

  import Portfolixir.WorldFixtures,
    only: [base_world: 0, create_security!: 1, deposit!: 3, put_quotes!: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Clock
  alias Portfolixir.Crashes
  alias Portfolixir.Dashboards
  alias Portfolixir.Settings

  @moduletag :browser
  @moduletag timeout: 180_000

  @script Path.expand("dashboard_crash_chart.js", __DIR__)

  defp day(offset), do: Date.add(Clock.today(), offset)

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

    # Invented names and figures: an index that fell and recovered, and is
    # falling again since five weeks; a manual window a few days before
    # that, which also began before the last month. Both start before the
    # zoom's first day and lay their labels at its left edge.
    deposit!(base_world(), "1000", day(-720))
    index = create_security!(name: "Synthetic Crash Index", ticker: "SCI")

    put_quotes!(index, [
      {day(-700), "120"},
      {day(-600), "90"},
      {day(-500), "125"},
      {day(-60), "130"},
      {day(-45), "110"},
      {day(-35), "131"},
      {day(-5), "115"},
      {day(-1), "118"}
    ])

    {:ok, _} = Settings.set_crash_benchmark(Actor.owner_ui(), index.id)

    {:ok, _} =
      Crashes.create_manual_window(Actor.owner_ui(), %{
        "name" => "Synthetic manual dip",
        "start" => day(-38),
        "trough" => day(-20)
      })

    {:ok, dashboard} = Dashboards.copy_template(Actor.owner_ui(), "pullbacks", %{})

    # "localhost", the endpoint's configured host, so the LiveView socket's
    # origin check passes.
    %{base_url: "http://localhost:#{port}", path: "/dashboards/#{dashboard.id}"}
  end

  # User story (board 11 ① and ②; the S32 closing act):
  # As the operator reading the last falls over the year and in the zoom,
  # I want every window's name legible and none printed over another,
  # so that I can tell the falls apart in the small chart too.
  #
  # Acceptance criteria:
  # - At 1200 px, in the chart over the year (XL) and the one pinned to 1M
  #   (L), no two window labels overprint, every label stays inside its
  #   chart, and none is drawn under 12 px.
  test "the crash chart's window labels are legible and never overprint", %{
    base_url: base_url,
    path: path
  } do
    {output, status} =
      System.cmd("node", [@script, Jason.encode!(%{base_url: base_url, path: path})],
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
