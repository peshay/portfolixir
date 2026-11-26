defmodule PortfolixirWeb.Browser.WidgetAnatomyTest do
  # The widget anatomy and the one surface measured in a real browser
  # (Sprint 32 L1; board ux-design-2026-11-25-sprint32/07 ② and 10 D;
  # D-12, D-14; DESIGN.md → "The widget anatomy and the one surface").
  # LiveViewTest applies no CSS, so
  # test/portfolixir_web/live/dashboard_anatomy_test.exs checks the markup
  # the anatomy's components draw and this test measures what the browser
  # draws of it, through `widget_anatomy.js` with Playwright, on a
  # dashboard holding every kind in every grid size it takes, filled by the
  # review seed (priv/demo/finding_surfaces_seed.exs).
  #
  # Excluded from the test job (test/test_helper.exs): run it with
  #
  #     mix test test/browser --only browser
  #
  # async: false -- the sandbox is shared, so the LiveView processes the
  # browser's requests start read the world this test seeds. Synthetic data
  # only, no external network: the browser talks to 127.0.0.1.
  #
  # group: :dashboards -- a create takes the count lock (LockTable row 30).
  use PortfolixirWeb.ConnCase, async: false, group: :dashboards

  import ExUnit.CaptureIO

  alias Ecto.Adapters.SQL.Sandbox
  alias Portfolixir.Actor
  alias Portfolixir.Dashboards
  alias Portfolixir.Dashboards.Layout
  alias Portfolixir.Dashboards.Widgets
  alias Portfolixir.Repo

  @moduletag :browser
  @moduletag timeout: 600_000

  @script Path.expand("widget_anatomy.js", __DIR__)
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
    %{base_url: "http://localhost:#{port}", dashboards: every_kind!()}
  end

  # User story (board 07 ②, 1, 2 and 6; board 10 D):
  # As the operator reading a dashboard on the desk, a tablet or a phone,
  # I want every widget built the same way — its head on one line, its
  # figures never cut, a warning as one line instead of a box — on one
  # surface with hairlines between the widgets,
  # so that the dashboard reads as one calm page, not as eleven designs.
  #
  # Acceptance criteria:
  # - At 1200, 834 and 393 px, in Inter and in DejaVu Sans, every kind in
  #   every grid size it takes: at 1200 px the title one line and its ⓘ,
  #   the period mark, the widget's switch and ⋯ on the title's line; at
  #   834 and 393 px (the compact forms) the title never cut; no
  #   headline or row figure cut sideways; no boxed data note in a widget.
  # - Sprint 32 L2 and L3: at 1200 px no title cut either (each kind's
  #   title fits its smallest tile), and no tile cuts a row of its body
  #   or its footer: a fixed tile shows what fits.
  # - The grid one frame of 1 px with a 16 px corner; no widget with a card
  #   border, a corner of its own or a shadow; at 1200 px neighbours 1 px
  #   apart.
  # - In the edit mode at 1200 px every widget's outline dashed and its
  #   handle, × and size switch inside its cell.
  test "every widget in every size keeps the anatomy on one surface", %{
    base_url: base_url,
    dashboards: dashboards
  } do
    # The kinds in their sizes outgrew one layout's 40 items (Sprint 32
    # W1): each dashboard is walked, and together they hold every one.
    results =
      for dashboard <- dashboards do
        result = run!(base_url, dashboard, "walk")
        assert result["ok"] == true, result["error"] || inspect(result)
        result
      end

    count = length(grid_items()) + 1

    for width <- ~w(1200 393) do
      assert results |> Enum.map(& &1["measured"][width]["widgets"]) |> Enum.sum() == count
    end
  end

  # User story (the walk's own check):
  # As the maintainer who trusts the walk,
  # I want each break it guards drawn on the page and seen caught,
  # so that a check that measures nothing cannot pass for one.
  #
  # Acceptance criteria:
  # - At 1200 px a title drawn over several lines: named as wrapping; a
  #   period mark set on a line of its own: the head named as wrapping.
  # - At 393 px a title cut: named as cut; at 1200 px a title too long
  #   for its tile: named as cut (Sprint 32 L2).
  # - At 1200 px a list's body cut through a row: the tile named as
  #   cutting a row (Sprint 32 L3).
  # - A row's figure drawn wider than its box: named as clipped.
  # - A boxed data note in a widget: named as a warning box.
  # - A card border on a widget: named.
  # - A 12 px gap in the wide grid: named as not the hairline.
  # - The handle drawn above its cell in the edit mode: named.
  test "the walk names a wrapped head, a cut figure, a warning box, a card border, a gap and a handle outside its cell",
       %{base_url: base_url, dashboards: [dashboard | _more]} do
    result = run!(base_url, dashboard, "attack")
    assert result["ok"] == true, result["error"] || inspect(result)

    wide = result["measured"]["1200"]["caught"]
    narrow = result["measured"]["393"]["caught"]

    assert Enum.any?(wide, &(&1 =~ "title wraps")), inspect(wide)
    assert Enum.any?(wide, &(&1 =~ "head wraps: widget-period")), inspect(wide)
    assert Enum.any?(narrow, &(&1 =~ "title is cut")), inspect(narrow)

    for caught <- [wide, narrow] do
      assert Enum.any?(caught, &(&1 =~ "clips a figure")), inspect(caught)
      assert Enum.any?(caught, &(&1 =~ "carries a warning box")), inspect(caught)
      assert Enum.any?(caught, &(&1 =~ "draws a card border")), inspect(caught)
    end

    assert Enum.any?(wide, &(&1 =~ "not the hairline")), inspect(wide)
    assert Enum.any?(wide, &(&1 =~ "title is cut")), inspect(wide)
    assert Enum.any?(wide, &(&1 =~ "tile cuts a row")), inspect(wide)
    assert Enum.any?(wide, &(&1 =~ "handle stands outside its cell")), inspect(wide)
  end

  defp run!(base_url, dashboard, mode) do
    {output, status} =
      System.cmd(
        "node",
        [@script, Jason.encode!(%{base_url: base_url, id: dashboard.id, mode: mode})],
        stderr_to_stdout: true
      )

    assert status == 0, "the browser run failed:\n" <> output

    output
    |> String.split("\n", trim: true)
    |> List.last()
    |> Jason.decode!()
  end

  # Every kind in every grid size it takes, one under the other in the
  # registry's order (board 07's contact sheets).
  defp grid_items do
    Widgets.kinds()
    |> Enum.flat_map(fn kind ->
      for size <- kind.sizes, match?({:ok, _}, Widgets.dimensions(size)), do: {kind.key, size}
    end)
  end

  # And „Tops und Flops“ at L pinned to 1W, as „Rücksetzer“ holds it: the
  # longest head — a pinned mark that reads another window, and the
  # switch (Sprint 32 L2).
  # Split at the layout's item cap (Sprint 32 W1: the section widgets took
  # the list past 40), the pinned „Tops und Flops“ on the first, each
  # dashboard's items one under the other.
  defp every_kind! do
    pinned = {"movers", "L", %{"period" => "1w"}}

    [pinned | Enum.map(grid_items(), fn {kind, size} -> {kind, size, %{}} end)]
    |> Enum.chunk_every(Layout.max_items())
    |> Enum.with_index(1)
    |> Enum.map(fn {items, n} ->
      {layout, _row} =
        Enum.map_reduce(items, 1, fn {kind, size, settings}, row ->
          {:ok, {_w, h}} = Widgets.dimensions(size)

          {%{"kind" => kind, "size" => size, "col" => 1, "row" => row, "settings" => settings},
           row + h}
        end)

      {:ok, dashboard} =
        Dashboards.create_dashboard(Actor.owner_ui(), %{
          "name" => "Anatomie #{n}",
          "layout" => layout
        })

      dashboard
    end)
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
