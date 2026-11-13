defmodule PortfolixirWeb.Browser.CrashSectionLayoutTest do
  # The Crashes section on Wealth › Risk at 1200 and 390 px, in a real
  # browser (Sprint 29 C6; board ux-design-2026-11-12-sprint29/01 ① and ⑨,
  # plan D-5 P2 and P5). LiveViewTest lays nothing out, so this test boots
  # the endpoint on a free loopback port and measures the section in
  # Chromium through `crash_section_layout.js` with Playwright.
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
  alias Portfolixir.Buckets
  alias Portfolixir.Crashes
  alias Portfolixir.Settings

  @moduletag :browser
  @moduletag timeout: 120_000

  @script Path.expand("crash_section_layout.js", __DIR__)

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

  # User story (Sprint 29 C6; board 01 ① and ⑨, P2 and P5):
  # As the operator reading the Crashes section on a wide screen and on my
  # phone,
  # I want the bar of labelled controls on one line where it fits and its
  # controls on one edge where it wraps, and each entry's bar beside or
  # under its name,
  # so that the section reads as the board draws it at 1200 and 390 px.
  #
  # Acceptance criteria (the 2022 window's losers over the catalogue):
  # - 1200 px: the window's select, the list and the universe on one line,
  #   the select first; each row one line, its bar in its track.
  # - 390 px: the three controls stacked from one edge; each row's figure
  #   beside its name and its bar under it, inside the section.
  # - At both widths the benchmark's dashed line stays inside each track,
  #   and the page never scrolls sideways.
  # - The closing act (board 01 ①, ⑥, ⑨; P2): with a manual window of a
  #   long name in the select and a security of 55 characters, the bar
  #   stays one line at 1200 px; the rebounders' six columns fit the
  #   section; the windows table's actions are inside it; and at 390 px
  #   the dashed lines never cross the name line of a two-line row.
  # - PR 2's closing act (board 06 ⑫): a manual window of a short name, as
  #   the review seed's „Synthetic dip · … · manuell“, reads whole in the
  #   select at 1200 px.
  test "the Crashes section at 1200 and 390 px", %{base_url: base_url} do
    world = base_world()
    index = create_security!(name: "Synthetic Crash Index", ticker: "SCI")

    put_quotes!(index, [
      {~D[2022-01-03], "120"},
      {~D[2022-10-12], "90"},
      {~D[2023-06-01], "125"}
    ])

    securities =
      for {name, from, to} <- [
            {"Synthetic Faller With A Rather Long Company Name Hold A", "50", "30"},
            {"Synthetic Riser", "20", "22"},
            {"Synthetic Outsider", "10", "8"}
          ] do
        security = create_security!(name: name, ticker: nil)

        # Each back above its start by the end of the recovery span, so
        # every rebounder draws a bar.
        put_quotes!(security, [
          {~D[2022-01-03], from},
          {~D[2022-10-12], to},
          {~D[2023-01-12], Decimal.mult(Decimal.new(from), Decimal.new("1.2"))}
        ])

        security
      end

    {:ok, _manual} =
      Crashes.create_manual_window(Actor.owner_ui(), %{
        "name" => "Synthetic war leg drawn by hand over a long stretch of the bear market",
        "start" => "2022-02-23",
        "trough" => "2022-03-07"
      })

    {:ok, _short} =
      Crashes.create_manual_window(Actor.owner_ui(), %{
        "name" => "Synthetic dip",
        "start" => "2022-08-15",
        "trough" => "2022-08-29"
      })

    deposit!(world, "10000", ~D[2021-05-04])
    buy!(world, hd(securities), quantity: "10", price: "45", date: ~D[2021-05-04])

    {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Synthetic Crash Bucket"})
    :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), world.depot, [bucket.id])

    {:ok, view} =
      Buckets.create_view(Actor.owner_ui(), %{name: "Synthetic Crash View", include_all: false})

    :ok = Buckets.set_view_buckets(Actor.owner_ui(), view, [bucket.id], [])
    {:ok, _index} = Settings.set_crash_benchmark(Actor.owner_ui(), index.id)

    query = fn list ->
      URI.encode_query(
        view: view.id,
        crash: "d:#{index.id}:2022-01-03",
        crash_list: list,
        crash_universe: "catalogue"
      )
    end

    args =
      Jason.encode!(%{
        url: base_url <> "/risk?" <> query.("losers"),
        rebounders: base_url <> "/risk?" <> query.("rebounders")
      })

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
