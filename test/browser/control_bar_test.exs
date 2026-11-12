defmodule PortfolixirWeb.Browser.ControlBarTest do
  # The shared bar of labelled controls (`PortfolixirWeb.ControlBar.bar/1`;
  # issue 1435, Sprint 29 L1; DESIGN.md "Labelled controls start on one
  # edge"), in a real browser. LiveViewTest renders the server's markup and
  # applies no CSS, so this test boots the endpoint on a free loopback port
  # and drives Chromium through `control_bar.js` with Playwright, as
  # `PortfolixirWeb.Browser.ClosingActLayoutTest` does.
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
  use PortfolixirWeb.ConnCase, async: false

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quotes!: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias PortfolixirWeb.PreferenceCookieHelpers

  @moduletag :browser
  @moduletag timeout: 180_000

  @script Path.expand("control_bar.js", __DIR__)

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

  defp run!(case_name, base_url, ids) do
    argument = Jason.encode!(Map.merge(ids, %{base_url: base_url, case: case_name}))
    {output, status} = System.cmd("node", [@script, argument], stderr_to_stdout: true)

    assert status == 0, "the browser run failed:\n" <> output

    result =
      output
      |> String.split("\n", trim: true)
      |> List.last()
      |> Jason.decode!()

    {result, output}
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

  # Issue 1435 (Sprint 29 L1; board
  # `ux-design-2026-11-12-sprint29/06-control-bar`, inventory §1 row 1).
  #
  # User story:
  # As the operator choosing the stack's level, classification and sort,
  # I want the stacked chart's bar to look exactly as it did once it is
  # built from the shared bar of labelled controls,
  # so that the component every other bar moves to is the one I already
  # know, and nothing on this screen moves.
  #
  # Acceptance criteria:
  # - In English and in German, at 1200 px and at 900 px (no sidebar) the
  #   bar is one line, each control 8 px after its label.
  # - At 1024 px (the sidebar leaves the bar under 760 px) and at 390 px the
  #   bar is the label column (A): every label at the bar's left edge, every
  #   control 10 px after the widest label (±1 px).
  # - At 320 px every label stands above its control, both at the bar's
  #   left edge (B).
  # - No control leaves the bar, and the page never scrolls sideways.
  test "the stacked chart's bar keeps its line, its label column and its labels above",
       %{base_url: base_url} do
    world = base_world(name: "Bar Stack", cash_name: "Giro", depot_name: "Depot")
    deposit!(world, "10000", ~D[2025-01-02])
    owner = Actor.owner_ui()
    {:ok, tree} = Classifications.create_classification(owner, %{name: "Strategy"})

    {:ok, category} =
      Classifications.create_category(owner, %{classification_id: tree.id, name: "Growth"})

    security = create_security!(name: "Synthetic Growth Fund")
    buy!(world, security, quantity: "10", price: "100", date: ~D[2025-01-02])
    put_quotes!(security, [{~D[2025-01-02], "100"}])
    {:ok, _} = Classifications.assign_security(owner, security.id, tree.id, category.id)

    {result, output} =
      run!("stack_bar_layout", base_url, %{
        path: "/portfolio?level=category&tree=#{tree.id}",
        locales: locales()
      })

    assert result == %{"ok" => true}, output
  end

  # --- L2 begin ---
  # Issue 1435 (Sprint 29 L2; board `ux-design-2026-11-12-sprint29/06-control-bar`
  # ① to ④ and its inventory §1, rows 2, 3, 5, 7 to 10): the bars that
  # broke "labelled controls start on one edge" on the review seed, and the
  # two it did not render, moved onto the shared bar. Each walks the review
  # seed (priv/demo/finding_surfaces_seed.exs), as the inventory measured
  # it, in German and in English at 390 and 1200 px.
  #
  # User story:
  # As the operator filtering a list or choosing a comparison, on a phone
  # or a wide window,
  # I want every bar of labelled controls to start its controls on one
  # edge, with each family of chips named,
  # so that I read a bar down one edge instead of hunting for where each
  # control starts and which chips belong together.
  #
  # Acceptance criteria (each bar, each locale, 390 and 1200 px):
  # - Once the bar has more than one row, the first control of every row
  #   and of every labelled group start on one edge (±1 px).
  # - Every labelled control sits after its label on the label's line, or
  #   under it on the label's edge (labels above).
  # - Wertpapiere and Transaktionen name every chip family with a visible
  #   label.
  # - The journal's chips and its form are one bar; the sale's comparison
  #   with „Fester Zins“ puts its labels above at 390 px (board 06 ①, ②).
  # - Wertpapiere's and Transaktionen's rows show at 1200 px (the phone's
  #   filter sheet takes their place at 390 px); every other bar shows at
  #   both widths.
  # - The page never scrolls sideways.
  for bar <-
        ~w(journal sale_comparison securities_chips transaction_chips) do
    test "the #{bar} bar starts its labelled controls on one edge", %{base_url: base_url} do
      seed!()

      {result, output} =
        run!("migrated_bar", base_url, %{bar: unquote(bar), locales: locales()})

      assert result == %{"ok" => true}, output
    end
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

  # --- L2 end ---
end
