defmodule PortfolixirWeb.Browser.WealthPolishTest do
  # Sprint 30 W2, the Wealth polish pass (#1366; board
  # `mockups/ux-design-2026-11-15-sprint30/02-wealth-polish`, plan D-7):
  # the lines whose fix is a box on the screen, measured in a real browser.
  # LiveViewTest renders the server's markup and applies no CSS and runs no
  # client script, so this test boots the endpoint on a free loopback port
  # and drives Chromium through `wealth_polish.js` with Playwright, on the
  # review seed (priv/demo/finding_surfaces_seed.exs) the board measured.
  #
  # Excluded from the test job (test/test_helper.exs); run it with
  #
  #     mix test test/browser --only browser
  #
  # async: false -- the sandbox is shared with the LiveView processes the
  # browser's requests start. Synthetic data only, no external network: the
  # browser talks to 127.0.0.1.
  use PortfolixirWeb.ConnCase, async: false

  alias Portfolixir.Derived.Memo
  alias Portfolixir.DerivedConfig
  alias PortfolixirWeb.PreferenceCookieHelpers

  @moduletag :browser
  @moduletag timeout: 180_000

  @script Path.expand("wealth_polish.js", __DIR__)

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

  defp seed! do
    conflicts = Code.get_compiler_option(:ignore_module_conflict)
    Code.put_compiler_option(:ignore_module_conflict, true)

    try do
      ExUnit.CaptureIO.capture_io(fn -> Code.eval_file("priv/demo/finding_surfaces_seed.exs") end)
    after
      Code.put_compiler_option(:ignore_module_conflict, conflicts)
    end
  end

  defp locales do
    Map.new(["en", "de"], fn locale ->
      {locale,
       "portfolixir_locale"
       |> PreferenceCookieHelpers.cookie_pair(locale)
       |> String.split("=", parts: 2)
       |> List.last()}
    end)
  end

  defp run!(case_name, base_url) do
    argument = Jason.encode!(%{base_url: base_url, case: case_name, locales: locales()})
    {output, status} = System.cmd("node", [@script, argument], stderr_to_stdout: true)

    assert status == 0, "the browser run failed:\n" <> output

    result =
      output
      |> String.split("\n", trim: true)
      |> List.last()
      |> Jason.decode!()

    {result, output}
  end

  # User story (#1366; board 02 ①, plan D-7 answer A; Sprint 24's design
  # critic on #1388):
  # As the operator reading Wealth's positions at 1200 px with all eight
  # figure columns,
  # I want a figure's note under it on one line and each depot on one line,
  # so that a noted row is as tall as the others and the table fits its
  # scroller.
  #
  # Acceptance criteria (the review seed, /portfolio at 1200 px, the eight
  # columns of #1322, German and English, in Inter and in DejaVu Sans):
  # - A note's first phrase („ohne Wechselkurs“, „kein Preis“,
  #   „Handelspreis“) never breaks, and every note is one line: a row with
  #   a note is at most one note line (17 px) taller than the plainest row,
  #   unless its name alone, wrapping in its column, asks for more.
  # - Every depot cell is one line, a name past 7rem cut with an ellipsis
  #   and whole in its title.
  # - In Inter the table fits its scroller (no sideways scroll); in DejaVu
  #   Sans, the fallback, the scroller stays the fallback it always was.
  test "the holdings' notes and depots are one line each at 1200 px", %{base_url: base_url} do
    seed!()
    {result, output} = run!("holdings", base_url)
    assert result == %{"ok" => true}, output
  end

  # User story (#1366; board 02 ②; Sprint 27's closing act, UAT
  # screenshots 01 and 04; the owner on a tablet, 2026-11-11):
  # As the operator reading the stacked chart beside its legend,
  # I want the axis values beside the plot, not over its bands,
  # so that a value never sits on a solid band behind a heavy halo.
  #
  # Acceptance criteria (the review seed, /portfolio?level=category):
  # - At 1200 px the chart beside its legend keeps its values outside the
  #   plot: no `data-axis-inside`, every value's right edge left of the
  #   plot's left edge, inside the chart's box, in Inter and DejaVu Sans.
  # - At 390 px the values stand inside the plot, as before.
  test "the stacked chart's values stand outside the plot beside its legend",
       %{base_url: base_url} do
    seed!()
    {result, output} = run!("stack_gutter", base_url)
    assert result == %{"ok" => true}, output
  end

  # User story (#1366; Sprint 24 P1's build on #1388):
  # As the operator tapping the allocation's sunburst on a phone,
  # I want no floating tooltip left behind by a tap,
  # so that the centre, which reads the tapped slice, is the one answer and
  # nothing stays over the chart once the selection clears.
  #
  # Acceptance criteria (the review seed, /portfolio?tab=allocation, 390 px,
  # touch):
  # - A tap on a slice selects it (the centre reads it) and shows no
  #   floating tooltip.
  # - Escape clears the selection and no tooltip shows.
  test "a tapped slice leaves no tooltip behind", %{base_url: base_url} do
    seed!()
    {result, output} = run!("touch_tooltip", base_url)
    assert result == %{"ok" => true}, output
  end

  # User story (I34 step 2, Sprint 31 P2; M6: every warm switch rendered
  # the skeleton first and the chart second):
  # As the operator switching the stacked chart between periods,
  # I want a period whose chart is remembered drawn at once,
  # so that the chart does not flash "computing" for a figure already known.
  #
  # Acceptance criteria (the review seed, /portfolio?level=category, the
  # derived layer on for this test only):
  # - A switch to 3 years, not yet read, shows the stack's skeleton while
  #   it walks (the watch sees a skeleton when there is one).
  # - A switch back to 1 year, and to 3 years again, both remembered, never
  #   shows `stack-skeleton` between the click and the chart.
  test "a warm period switch draws the stack without the skeleton", %{base_url: base_url} do
    Memo.reset()
    on_exit(&Memo.reset/0)
    DerivedConfig.enable!(lifetimes: [])
    seed!()
    {result, output} = run!("warm_switch", base_url)
    assert result == %{"ok" => true}, output
  end
end
