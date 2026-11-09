defmodule PortfolixirWeb.Browser.PeriodMemoryTest do
  # Wealth's period, remembered per browser (#1432, Sprint 28 S5; plan
  # amendment D-A1). LiveViewTest renders the server's markup and runs no
  # client script, so the PeriodMemory hook's storage is read here: the test
  # boots the endpoint on a free loopback port, seeds a synthetic world and
  # drives Chromium through `period_memory.js` with Playwright. The server
  # half (the address, the restore event, the fallback line) is
  # test/portfolixir_web/live/wealth_period_address_live_test.exs.
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

  alias Portfolixir.Clock

  @moduletag :browser
  @moduletag timeout: 120_000

  @script Path.expand("period_memory.js", __DIR__)

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

    # Invented names and figures: one deposit and one buy on 10 January of
    # last year, so the analysis walks last year and this one.
    today = Clock.today()
    start = Date.new!(today.year - 1, 1, 10)
    world = base_world(name: "Memory World", cash_name: "Giro", depot_name: "Depot")
    deposit!(world, "1000", start)
    security = create_security!(name: "Memory Synthetic ETF")
    buy!(world, security, quantity: "8", price: "100", date: start)
    put_quotes!(security, [{start, "100"}, {today, "121"}])

    # "localhost", the endpoint's configured host, so the LiveView socket's
    # origin check passes.
    %{base_url: "http://localhost:#{port}", from: Date.new!(today.year - 1, 12, 31), to: today}
  end

  # User story (#1432, D-A1):
  # As the operator who picked a custom range on Wealth,
  # I want it back when I return to Wealth through the sidebar,
  # so that I do not pick it again on every visit.
  #
  # Acceptance criteria:
  # - A custom range picked in the popover, then another page opened from
  #   the sidebar and Wealth again from the sidebar: Wealth reopens the
  #   range, its address naming it.
  # - With the browser's storage blocked (every access throws), the page
  #   opens at 1 year, a pick still works, and the return through the
  #   sidebar opens at 1 year, with no script error.
  test "a picked range survives a return through the sidebar; blocked storage leaves 1 year", %{
    base_url: base_url,
    from: from,
    to: to
  } do
    {output, status} =
      System.cmd("node", [@script, base_url, Date.to_iso8601(from), Date.to_iso8601(to)],
        stderr_to_stdout: true
      )

    assert status == 0, "the browser run failed:\n" <> output

    result =
      output
      |> String.split("\n", trim: true)
      |> List.last()
      |> Jason.decode!()

    assert result == %{"ok" => true}, inspect(result)
  end
end
