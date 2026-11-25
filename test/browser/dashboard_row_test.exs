defmodule PortfolixirWeb.Browser.DashboardRowTest do
  # The size „Zeile“ measured in a real browser (Sprint 32 S2; ADR-0062's
  # amendment of 2026-11-25, point 3; board
  # ux-design-2026-11-25-sprint32/02 ①, ③). LiveViewTest applies no CSS,
  # so test/portfolixir_web/live/dashboard_row_size_test.exs checks the
  # markup the CSS reads and this test measures what it draws, through
  # `dashboard_row.js` with Playwright.
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

  import Portfolixir.WorldFixtures, only: [base_world: 0, buy!: 3, sell!: 3, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Dashboards

  @moduletag :browser
  @moduletag timeout: 300_000

  @script Path.expand("dashboard_row.js", __DIR__)

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
    %{base_url: "http://localhost:#{port}", dashboard: seed!()}
  end

  # Two securities bought and sold, so „Verkaufsrückblick“ lists closed
  # trades, and a dashboard: an S, the „Zeile“ under it, an S under that.
  defp seed! do
    world = base_world()

    for {name, sold} <- [{"Alpha Werke", "110"}, {"Beta Linien", "90"}] do
      {:ok, security} =
        Portfolixir.Catalog.create_security(Actor.owner_ui(), %{name: name, currency_code: "EUR"})

      buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-10])
      sell!(world, security, quantity: "4", price: sold, date: ~D[2026-03-10])
      put_quote!(security, Portfolixir.Clock.today(), "120")
    end

    {:ok, dashboard} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{
        "name" => "Zeile",
        "layout" => [
          %{"kind" => "due", "size" => "S", "col" => 1, "row" => 1},
          %{"kind" => "sale_review", "size" => "row", "col" => 1, "row" => 3},
          %{"kind" => "data_quality", "size" => "S", "col" => 1, "row" => 4}
        ]
      })

    dashboard
  end

  # User story (board 02 ③):
  # As the operator who placed a section as „Zeile“,
  # I want it as tall as its content on the desk and on the phone, the
  # widgets after it below it,
  # so that a section is never cut or padded with a blank band.
  #
  # Acceptance criteria:
  # - At 1200 px and at 393 px, in Inter and in DejaVu Sans: nothing inside
  #   the „Zeile“ widget is cut, no blank band under its last part (within
  #   a pixel), the widget after it starts below it; at 1200 px the S above
  #   it keeps its fixed tile.
  test "a „Zeile“ widget is as tall as its content at 1200 px and at 393 px", %{
    base_url: base_url,
    dashboard: dashboard
  } do
    result = run!(base_url, dashboard, "walk")
    assert result["ok"] == true, result["error"] || inspect(result)
    assert result["measured"]["1200"]["height"] > 112
  end

  # User story (the walk's own check):
  # As the maintainer who trusts the walk,
  # I want each break it guards drawn and seen caught,
  # so that a check that measures nothing cannot pass for one.
  #
  # Acceptance criteria:
  # - At 1200 px the grid's rows all fixed: the „Zeile“ named as cut.
  # - At 393 px the widget drawn 400 px tall: named as taller than its
  #   content.
  test "the walk names a cut „Zeile“ and a blank band under one", %{
    base_url: base_url,
    dashboard: dashboard
  } do
    result = run!(base_url, dashboard, "attack")
    assert result["ok"] == true, result["error"] || inspect(result)

    wide = result["measured"]["1200"]["caught"]
    narrow = result["measured"]["393"]["caught"]

    assert Enum.any?(wide, &(&1 =~ "cuts")), inspect(wide)
    assert Enum.any?(narrow, &(&1 =~ "taller than its content")), inspect(narrow)
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
end
