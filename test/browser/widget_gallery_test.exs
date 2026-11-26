defmodule PortfolixirWeb.Browser.WidgetGalleryTest do
  # The widget gallery for the docs (Sprint 32 L4; plan D-13; the owner on
  # 2026-11-25: „das brauchen wir auch für die Doku“; board
  # ux-design-2026-11-25-sprint32/08): every registered kind in every grid
  # size it takes, light and dark, photographed at a device scale factor of
  # 2 and cropped to its tile, into docs/assets/widgets/, which the widget
  # catalogue (docs/guides/widgets.md, docs/de/guides/widgets.md) shows.
  #
  # The kinds and sizes are the registry's (`Portfolixir.Dashboards.Widgets`),
  # so a kind registered later is photographed with no change here; the
  # throwaway dashboards hold them one under the other, split where a
  # layout's item cap or row cap would refuse more. The data is the review
  # seed (priv/demo/finding_surfaces_seed.exs), synthetic all the way down.
  #
  # It writes into the repository, so neither the test job nor the browser
  # job runs it (`:gallery` is excluded in test/test_helper.exs). Regenerate
  # it, after any change that touches a widget, with
  #
  #     mix test test/browser/widget_gallery_test.exs --only gallery
  #
  # and commit docs/assets/widgets/. It needs what the browser walks need:
  # Node, test/browser's Playwright and its Chromium (AGENTS.md, Required
  # Local Checks).
  #
  # async: false, group: :dashboards -- the seed and the stored dashboards
  # share the count lock (LockTable row 30).
  use PortfolixirWeb.ConnCase, async: false, group: :dashboards

  import ExUnit.CaptureIO

  alias Ecto.Adapters.SQL.Sandbox
  alias Portfolixir.Actor
  alias Portfolixir.Dashboards
  alias Portfolixir.Dashboards.Layout
  alias Portfolixir.Dashboards.Widgets
  alias Portfolixir.Repo

  @moduletag :gallery
  @moduletag timeout: 900_000

  @script Path.expand("widget_gallery.js", __DIR__)
  @seed "priv/demo/finding_surfaces_seed.exs"
  @out "docs/assets/widgets"
  @themes ~w(light dark)

  setup %{sandbox_owner: owner} do
    # The seed and the photographs hold the shared connection for longer
    # than the sandbox's two-minute ownership timeout.
    Portfolixir.DataCase.stop_sandbox(owner)
    long_owner = Sandbox.start_owner!(Repo, shared: true, ownership_timeout: 1_200_000)
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
    %{base_url: "http://localhost:#{port}"}
  end

  # User story (D-13):
  # As the reader of the docs choosing widgets for a dashboard,
  # I want a picture of every widget in every size it takes, light and
  # dark, as the app draws it,
  # so that I see what each size shows before I place it.
  #
  # Acceptance criteria:
  # - One PNG per registered kind, grid size and theme, named
  #   `<kind>-<size>-<theme>.png`, the size in lower case, at 2× and
  #   cropped to the tile; none left over from a kind or size no longer
  #   registered.
  # - Every file the catalogue pages link exists, and every PNG is linked
  #   from both pages.
  # - Sprint 32 W5: a picture changes only with its widget: the throwaway
  #   grids draw no rounded corner, which clipped a widget only where it
  #   stood first or last, and an instant a walk was computed at reads as
  #   its day at 00:00 UTC.
  test "every registered kind in every grid size, light and dark, into docs/assets/widgets",
       %{base_url: base_url} do
    expected =
      for {kind, size} <- grid_items(), theme <- @themes do
        "#{kind}-#{String.downcase(size)}-#{theme}.png"
      end

    File.mkdir_p!(@out)
    for stale <- Path.wildcard(Path.join(@out, "*.png")), do: File.rm!(stale)

    ids = Enum.map(dashboards!(), & &1.id)

    {output, status} =
      System.cmd(
        "node",
        [@script, Jason.encode!(%{base_url: base_url, ids: ids, out: Path.expand(@out)})],
        stderr_to_stdout: true
      )

    assert status == 0, "the browser run failed:\n" <> output
    result = output |> String.split("\n", trim: true) |> List.last() |> Jason.decode!()
    assert result["ok"] == true, result["error"] || inspect(result)

    # Sprint 32 W5: each picture depends on its widget alone — no rounded
    # corner of the throwaway grid, no instant to the minute.
    assert result["unsteady"] != []

    for page <- result["unsteady"] do
      assert page["radius"] == "0px", "a gallery grid rounds its corners: #{page["radius"]}"
      assert page["instants"] == [], "an instant in a picture: #{inspect(page["instants"])}"
    end

    written = @out |> Path.join("*.png") |> Path.wildcard() |> Enum.map(&Path.basename/1)
    assert Enum.sort(written) == Enum.sort(expected)

    for file <- written do
      assert <<0x89, "PNG", _rest::binary>> = File.read!(Path.join(@out, file)), file
    end

    for page <- ["docs/guides/widgets.md", "docs/de/guides/widgets.md"] do
      text = File.read!(page)
      linked = ~r{/assets/widgets/([\w-]+\.png)} |> Regex.scan(text) |> Enum.map(&List.last/1)
      assert Enum.sort(Enum.uniq(linked)) == Enum.sort(expected), page
    end
  end

  # Every kind in every grid size it takes, in the registry's order.
  defp grid_items do
    for kind <- Widgets.kinds(),
        size <- kind.sizes,
        match?({:ok, _}, Widgets.dimensions(size)),
        do: {kind.key, size}
  end

  # The items one under the other, on as many dashboards as the layout's
  # item and row caps need.
  defp dashboards! do
    grid_items()
    |> Enum.chunk_while(
      {[], 1},
      fn {kind, size}, {items, row} ->
        {:ok, {_w, h}} = Widgets.dimensions(size)
        item = %{"kind" => kind, "size" => size, "col" => 1, "row" => row}

        if length(items) < Layout.max_items() and row + h - 1 <= Layout.max_row() do
          {:cont, {[item | items], row + h}}
        else
          {:cont, Enum.reverse(items), {[%{item | "row" => 1}], 1 + h}}
        end
      end,
      fn {items, _row} -> {:cont, Enum.reverse(items), {[], 1}} end
    )
    |> Enum.with_index(1)
    |> Enum.map(fn {layout, n} ->
      {:ok, dashboard} =
        Dashboards.create_dashboard(Actor.owner_ui(), %{
          "name" => "Gallery #{n}",
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
