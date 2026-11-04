defmodule PortfolixirWeb.Browser.SunburstCentreReturnTest do
  # The sunburst's centre comes back to its total, in a real browser (Sprint
  # 24 P1, #1366's first line, the owner's report of 2026-11-04). The
  # LiveView test (PortfolixirWeb.WealthPolishLiveTest) pins the events and
  # the attributes; only a browser shows that a tap on the centre, whose
  # text lets the pointer through to the chart, and a tap outside the chart
  # reach them. This test boots the endpoint on a free loopback port and
  # drives Chromium through `sunburst_centre_return.js` with Playwright, as
  # `PortfolixirWeb.Browser.InfoTipsClickAwayTest` does.
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
    only: [base_world: 0, buy!: 3, create_security!: 1, deposit!: 3, put_quotes!: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Classifications

  @moduletag :browser
  @moduletag timeout: 120_000

  @script Path.expand("sunburst_centre_return.js", __DIR__)

  setup do
    server =
      start_supervised!(
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

  # Two categories, each holding one security, so the chart has two slices
  # in each ring.
  defp allocation_world do
    world = base_world()
    today = Date.utc_today()
    start = Date.add(today, -10)
    deposit!(world, "5000", start)

    {:ok, classification} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

    for {category_name, color, security_name, quantity} <- [
          {"Core", "#2563eb", "Harbor World ETF", "12"},
          {"Satellite", "#10b981", "Fernhill Tools AG", "8"}
        ] do
      security = create_security!(name: security_name)
      buy!(world, security, quantity: quantity, price: "100", date: start)
      put_quotes!(security, [{start, "100"}, {today, "110"}])

      {:ok, category} =
        Classifications.create_category(Actor.owner_ui(), %{
          classification_id: classification.id,
          name: category_name,
          color: color
        })

      {:ok, _} =
        Classifications.assign_security(
          Actor.owner_ui(),
          security.id,
          classification.id,
          category.id
        )
    end

    world
  end

  # User story (#1366, line 1):
  # As the operator tapping the allocation sunburst on a phone,
  # I want a tap on the centre, outside the chart or on the selected slice
  # again, and Escape, to bring the total back,
  # so that one tapped slice does not hold the centre until a reload.
  #
  # Acceptance criteria:
  # - A tap on a slice shows that slice in the centre.
  # - A tap on the centre, a tap outside the chart, a second tap on the
  #   selected slice and Escape each show „Allocated“ with the total again.
  test "a tap on the centre, outside or on the same slice, and Escape, restore the total",
       %{base_url: base_url} do
    allocation_world()

    {output, status} =
      System.cmd("node", [@script, base_url <> "/portfolio?tab=allocation"],
        stderr_to_stdout: true
      )

    assert status == 0, "the browser run failed:\n" <> output

    result =
      output
      |> String.split("\n", trim: true)
      |> List.last()
      |> Jason.decode!()

    assert result == %{"ok" => true}
  end
end
