defmodule PortfolixirWeb.Browser.BenchmarkPickerLayoutTest do
  # Holdings' benchmark picker at 1200 and 390 px, in a real browser
  # (Sprint 29, the closing act of #1416; board
  # ux-design-2026-11-12-sprint29/02 ① and ⑥). LiveViewTest lays nothing
  # out, so this test boots the endpoint on a free loopback port and
  # measures the picker in Chromium through `benchmark_picker_layout.js`
  # with Playwright.
  #
  # Excluded from the test job (test/test_helper.exs); run it with
  #
  #     mix test test/browser --only browser
  #
  # async: false -- the sandbox is shared with the LiveView processes the
  # browser's requests start. Synthetic data only, no external network.
  use PortfolixirWeb.ConnCase, async: false

  import Portfolixir.WorldFixtures,
    only: [base_world: 0, buy!: 3, create_security!: 1, deposit!: 3, put_quotes!: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog

  @moduletag :browser
  @moduletag timeout: 120_000

  @script Path.expand("benchmark_picker_layout.js", __DIR__)

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

  # User story (#1416, B2; board 02 ① and ⑥):
  # As the operator choosing a benchmark on my phone and on a wide screen,
  # I want each group of the picker to start with its label,
  # so that „Im Bestand“ and „Weitere“ never read as the last lines of the
  # group before them.
  #
  # Acceptance criteria (three groups: a flagged index, two held funds and
  # an unheld quoted fund the address names):
  # - 1200 px: the labels in one column, each beside its options' first line.
  # - 390 px: each label above its options, and the gap before every label
  #   after the first at least 12 px and larger than the gap between a label
  #   and its own options.
  # - At both widths the page never scrolls sideways.
  test "the picker's groups at 1200 and 390 px", %{base_url: base_url} do
    world = base_world()
    today = Date.utc_today()
    start = Date.add(today, -20)

    index = create_security!(name: "Synthetic Picker Index", ticker: "SPI")
    {:ok, index} = Catalog.update_security(Actor.owner_ui(), index, %{is_benchmark: true})
    put_quotes!(index, [{start, "50"}, {Date.add(today, -1), "55"}])

    deposit!(world, "10000", start)

    for {name, ticker} <- [{"Synthetic Held Fund A", "SHA"}, {"Synthetic Held Fund B", "SHB"}] do
      held = create_security!(name: name, ticker: ticker)
      put_quotes!(held, [{start, "10"}, {Date.add(today, -1), "11"}])
      buy!(world, held, quantity: "5", price: "10", date: start)
    end

    watched = create_security!(name: "Synthetic Watched Fund", ticker: "SWF")
    put_quotes!(watched, [{start, "20"}, {Date.add(today, -1), "21"}])

    query =
      URI.encode_query([
        {"benchmark[]", "security:#{index.id}"},
        {"benchmark[]", "security:#{watched.id}"}
      ])

    args = Jason.encode!(%{url: base_url <> "/portfolio?" <> query})

    {output, status} = System.cmd("node", [@script, args], stderr_to_stdout: true)

    assert status == 0, "the browser run failed:\n" <> output

    result =
      output
      |> String.split("\n", trim: true)
      |> List.last()
      |> Jason.decode!()

    assert result["ok"] == true, inspect(result)
  end
end
