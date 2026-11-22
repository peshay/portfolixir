defmodule PortfolixirWeb.Browser.DashboardWidthsTest do
  # The dashboard by the window's width (ADR-0062 §1, §4, §6; idea board
  # ux-design-2026-11-21-idea-i56 03 and 06; planning board
  # ux-design-2026-11-21-sprint31/01 ① ④; Sprint 31 D8; DESIGN.md →
  # Amendment 2026-11-21, "The widget, its sizes, the compact type floor
  # and the width classes").
  # LiveViewTest renders the server's markup and applies no CSS, so the
  # class each window falls into is measured here: the test boots the
  # endpoint on a free loopback port, seeds the review seed
  # (priv/demo/finding_surfaces_seed.exs, which stores no dashboard, so `/`
  # is the template „Überblick“ with every widget filled) and drives
  # Chromium through `dashboard_widths.js` with Playwright. The server half
  # (the reading order, the forms, the template's layout) is
  # test/portfolixir_web/live/dashboard_page_test.exs; the tab bar's own
  # walk is tab_bar_test.exs.
  #
  # Excluded from the test job (test/test_helper.exs): it needs Node, the
  # Playwright test/browser/package-lock.json pins and its Chromium, which
  # CI's `browser` job installs. Run it with
  #
  #     mix test test/browser --only browser
  #
  # async: false -- the sandbox is shared, so the LiveView processes the
  # browser's requests start read the world this test seeds. Synthetic data
  # only, no external network: the browser talks to 127.0.0.1.
  #
  # group: :dashboards -- the dashboard tests share the advisory lock that
  # counts the dashboards (`Portfolixir.LockTable`).
  use PortfolixirWeb.ConnCase, async: false, group: :dashboards

  import ExUnit.CaptureIO

  alias Ecto.Adapters.SQL.Sandbox
  alias Portfolixir.Repo

  @moduletag :browser
  @moduletag timeout: 600_000

  @script Path.expand("dashboard_widths.js", __DIR__)
  @seed "priv/demo/finding_surfaces_seed.exs"

  setup %{sandbox_owner: owner} do
    # The seed and the walk hold the shared connection for longer than the
    # sandbox's two-minute ownership timeout: a fresh owner with room for
    # both replaces the case's.
    Portfolixir.DataCase.stop_sandbox(owner)
    long_owner = Sandbox.start_owner!(Repo, shared: true, ownership_timeout: 900_000)
    on_exit(fn -> Portfolixir.DataCase.stop_sandbox(long_owner) end)

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
    seed!()

    # "localhost", the endpoint's configured host, so the LiveView socket's
    # origin check passes.
    %{base_url: "http://localhost:#{port}"}
  end

  # User story (ADR-0062 §1, §4, §6; board 06):
  # As the operator who opens the dashboard on a phone, a folded-out phone,
  # a tablet or the desk,
  # I want one column of compact forms at phone type on the phone, two
  # columns between, and the 12-column grid on the desk,
  # so that every widget reads at its window's size and none is a desk
  # widget squeezed.
  #
  # Acceptance criteria:
  # - At 375, 393 and 440 px wide: one column of widgets in reading order,
  #   each in its compact form, no sideways page scroll, every widget's
  #   frame inside the window and nothing in a frame wider than it (every
  #   class holds these two), and every visible text of the grid, the
  #   dashboard's bar and the tab bar at 12 px or more; every target a
  #   thumb presses there — the scope, the period chips, „Anpassen“, each
  #   widget's ⓘ and ⋯, the footer links, and „hinzufügen ›“ on „Alle
  #   Widgets“ — at least 44 px each way (Sprint 31 closing act, Y5).
  # - At 760 × 580 and 834 px: two columns of compact forms, the reading
  #   order filled column by column.
  # - At 1200 px: the 12-column grid, each widget at its col and row with
  #   its size's span (one row's widgets share a top, a later col stands to
  #   the right, the width is the span's), no two overlapping; no blank
  #   band between the bar and the grid, 20 px at most (Sprint 31 closing
  #   act, DS2); each widget's title at 15 px with its ⓘ on the title's
  #   line, its period tag under the title at its left, and no „ohne
  #   Zeitraum“ on the grid (DS3).
  # - At 844 × 390: the rail at the side, no bar at the foot.
  # - Each class in the page's own Inter and in DejaVu Sans.
  test "the dashboard's compact, medium and wide classes, by the window's width", %{
    base_url: base_url
  } do
    result = run!(base_url, "walk")
    assert result["ok"] == true, result["error"] || inspect(result)
    measured = result["measured"]

    assert length(measured["compact"]) == 6
    assert Enum.all?(measured["compact"], &(&1["minText"] >= 12))
    assert Enum.all?(measured["compact"], &(&1["taps"] > 0))
    assert Enum.all?(measured["widgets_taps"], &(&1 > 0))
    assert Enum.all?(measured["medium"], &(length(&1["lefts"]) == 2))
    assert length(measured["wide_items"]) == 11
  end

  # User story (the walk's own check):
  # As the maintainer who trusts the walk to hold the compact type floor
  # and the grid,
  # I want each break it guards drawn on the page and seen caught,
  # so that a check that measures nothing cannot pass for one that does.
  #
  # Acceptance criteria:
  # - One label in the grid at 11 px: the floor names it.
  # - One tab's label at 11 px: the floor names it.
  # - A line wider than the window inside a widget: the widget holds a
  #   line wider than its frame, named (the page clips what overflows
  #   sideways, so the page's own scroll width never shows it).
  # - A footer link drawn 30 px tall: the tap rule names it.
  # - A widget moved onto its neighbour's col at 1200 px: the overlap and
  #   the wrong col named.
  # - The medium class drawn as one column: "1 columns of widgets, not 2".
  test "the walk fails a compact text under 12 px, a sideways scroll, an overlap and one column",
       %{base_url: base_url} do
    result = run!(base_url, "attack")
    assert result["ok"] == true, inspect(result)
    caught = result["caught"]

    for key <- ~w(grid_label tab_label) do
      shrunk = caught[key]["shrunk"]
      errors = caught[key]["errors"]

      assert length(errors) == 1, "#{key}: #{inspect(errors)}"
      assert hd(errors) =~ "a text under 12 px, 11 px: #{Jason.encode!(shrunk)}"
    end

    assert Enum.any?(caught["sideways"]["errors"], &(&1 =~ "wider than its frame")),
           inspect(caught["sideways"])

    shrunk = Jason.encode!(caught["small_target"]["shrunk"])

    assert Enum.any?(
             caught["small_target"]["errors"],
             &(&1 =~ "a target under 44 px" and &1 =~ " x 30: #{shrunk}")
           ),
           inspect(caught["small_target"])

    assert Enum.any?(caught["overlap"]["errors"], &(&1 =~ "overlap")), inspect(caught["overlap"])

    assert Enum.any?(caught["overlap"]["errors"], &(&1 =~ "starts at")),
           inspect(caught["overlap"])

    assert Enum.any?(caught["one_column"]["errors"], &(&1 =~ "1 columns of widgets, not 2")),
           inspect(caught["one_column"])
  end

  defp run!(base_url, mode) do
    {output, status} =
      System.cmd("node", [@script, Jason.encode!(%{base_url: base_url, mode: mode})],
        stderr_to_stdout: true
      )

    assert status == 0, "the browser run failed:\n" <> output

    output
    |> String.split("\n", trim: true)
    |> List.last()
    |> Jason.decode!()
  end

  defp seed! do
    conflicts = Code.get_compiler_option(:ignore_module_conflict)
    Code.put_compiler_option(:ignore_module_conflict, true)

    try do
      capture_io(fn -> Code.eval_file(@seed) end)
    after
      Code.put_compiler_option(:ignore_module_conflict, conflicts)
    end
  end
end
