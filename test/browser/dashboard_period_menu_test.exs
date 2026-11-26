defmodule PortfolixirWeb.Browser.DashboardPeriodMenuTest do
  # The period menu above every dashboard (Sprint 32 T4; ADR-0062's
  # amendment of 2026-11-25, point 6; board
  # ux-design-2026-11-25-sprint32/04 ① and ②). LiveViewTest renders the
  # server's markup and runs no client script, so the keyboard's path, the
  # focus, the native dialog and the sheet at a phone's width are walked
  # here: the test boots the endpoint on a free loopback port, seeds a
  # synthetic world and drives Chromium through `dashboard_period_menu.js`.
  # The server half is test/portfolixir_web/live/dashboard_period_menu_test.exs.
  #
  # Excluded from the test job (test/test_helper.exs): run it with
  #
  #     mix test test/browser --only browser
  #
  # async: false -- the sandbox is shared, so the LiveView processes the
  # browser's requests start read the world this test seeds. Synthetic data
  # only, no external network: the browser talks to 127.0.0.1.
  #
  # group: :periods -- the walk stores an own period, whose create takes
  # the count lock of `Portfolixir.LockTable` row 31.
  use PortfolixirWeb.ConnCase, async: false, group: :periods

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quotes!: 2]

  alias Portfolixir.Clock

  @moduletag :browser
  @moduletag timeout: 180_000

  @script Path.expand("dashboard_period_menu.js", __DIR__)

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
    # half ago, a close then, one in between and today.
    today = Clock.today()
    start = Date.add(today, -540)
    world = base_world(name: "Menu World", cash_name: "Giro", depot_name: "Depot")
    deposit!(world, "1000", start)
    security = create_security!(name: "Menu Synthetic ETF")
    buy!(world, security, quantity: "8", price: "100", date: start)
    put_quotes!(security, [{start, "100"}, {Date.add(today, -100), "110"}, {today, "121"}])

    %{base_url: "http://localhost:#{port}", path: "/"}
  end

  # User story (T4):
  # As the operator, with a keyboard, a pointer or a thumb,
  # I want to open the period menu, pick a period and get back to where I
  # was, and to make an own period in its dialog,
  # so that every period is reachable without the bar growing.
  #
  # Acceptance criteria:
  # - At 1280 px and at 393 px: Enter on the button opens the menu, which
  #   lies inside the window; Enter on 3M applies it, closes the menu and
  #   puts the focus back on the button, which names 3M; Escape closes the
  #   menu without a pick, the focus back on the button; the page never
  #   scrolls sideways.
  # - At 393 px the menu is a sheet on the bottom edge, standing on the tab
  #   bar, the window's width, every target in it at least 44 px tall and,
  #   scrolled into the sheet's view, the element a tap at its centre
  #   reaches; a thumb taps the last year and it applies (S32 closing act).
  # - The group headings are small muted labels (12 px at most), and the
  #   dialog's buttons keep 16 px or more off its edges (S32 closing act).
  # - A star puts Vorquartal into the bar; „Eigenen Zeitraum anlegen …“
  #   opens the native dialog; „Speichern und anwenden“ stores the period
  #   and applies it, the button naming it and its dates beside it.
  test "the menu is walked by keyboard, at a wide and a phone width, and its dialog stores", %{
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
