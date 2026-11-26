defmodule PortfolixirWeb.Browser.AllocationSnapshotsStartersTest do
  # The starters of Wealth's tabs „Allokation & Ziele“ (Sprint 32 W2),
  # „Snapshots“ (W3) and „Risiko“ (W4) against the tabs, in a real
  # browser (I57; ADR-0062's amendment of 2026-11-25, points 3 and 5; plan D-7: a section widget
  # moves code, never figures; board ux-design-2026-11-25-sprint32/02 ②).
  # LiveViewTest compares each widget's figures with its route's
  # (dashboard_allocation_widgets_test.exs); this walk compares what the
  # browser draws: each starter's widgets in order, and each section's
  # parts as the dashboard draws them with the tab's, on the review seed
  # (priv/demo/finding_surfaces_seed.exs), synthetic all the way down.
  #
  # Excluded from the test job (test/test_helper.exs): run it with
  #
  #     mix test test/browser --only browser
  #
  # async: false -- the sandbox is shared, so the LiveView processes the
  # browser's requests start read the world this test seeds.
  # group: :dashboards -- a create takes the count lock (LockTable row 30).
  use PortfolixirWeb.ConnCase, async: false, group: :dashboards

  import ExUnit.CaptureIO

  alias Ecto.Adapters.SQL.Sandbox
  alias Portfolixir.Actor
  alias Portfolixir.Dashboards
  alias Portfolixir.Repo

  @moduletag :browser
  @moduletag timeout: 600_000

  @script Path.expand("allocation_snapshots_starters.js", __DIR__)
  @seed "priv/demo/finding_surfaces_seed.exs"

  # Each starter's widgets in the tab's order: the kind, the section's root
  # on the tab, and the parts compared.
  @starters [
    %{
      key: "allocation_targets",
      wealth: "/portfolio?tab=allocation",
      sections: [
        %{
          kind: "summary_line",
          wealth_root: "[data-role='kpi-summary']",
          parts: ["[data-role='kpi-summary']"]
        },
        %{
          kind: "allocation",
          wealth_root: "#portfolio-allocation",
          parts: [
            "[data-role='allocation-basis']",
            ".segmented-control",
            ".donut-legend",
            "table.drift-table"
          ]
        }
      ]
    },
    %{
      key: "snapshots",
      wealth: "/snapshots",
      sections: [
        %{
          kind: "snapshot_comparison",
          wealth_root: "[data-role='snapshot-comparison']",
          parts: [
            "[data-role='kpi-real']",
            "[data-role='kpi-frozen']",
            "[data-role='comparison-legend']",
            "[data-role='comparison-basis']",
            "[data-role='comparison-table']"
          ]
        },
        %{
          kind: "snapshot_list",
          wealth_root: "[data-role='snapshot-list']",
          parts: ["all:[data-role='snapshot-row'] td:not(.row-actions)"]
        }
      ]
    },
    # --- S32 W4 begin ---
    %{
      key: "risk",
      wealth: "/risk",
      sections: [
        %{
          kind: "own_rules",
          wealth_root: "#policy-rules",
          parts: [
            # The counts without the „·“ that follows the tab's title (the
            # S32 closing act: the widget's line starts with its count).
            "[data-role='policy-rules-counts']",
            "table.policy-findings-table tbody",
            "[data-role='policy-rules-basis']"
          ]
        },
        %{
          kind: "key_figures",
          wealth_root: "#risk-metrics",
          parts: [
            "[data-role='risk-metric-volatility']",
            "[data-role='risk-metric-max-drawdown']",
            "[data-role='risk-metric-risk-adjusted-return']",
            "[data-role='risk-metric-correlations']",
            "[data-role='risk-basis']"
          ]
        },
        %{
          kind: "crash_section",
          wealth_root: ".crash-section",
          # The S32 closing act: on the dashboard the list and the
          # universe stand in the widget's head, the window's select in
          # its body; each is compared, wherever it stands.
          parts: [
            "all:select[name='crash'] option",
            "all:[data-list]",
            "all:[data-universe]",
            "[data-role='crash-window']"
          ]
        },
        %{
          kind: "top_holdings",
          wealth_root: "#risk-top-holdings",
          parts: ["table.risk-top-table tbody"]
        },
        %{
          kind: "concentration",
          wealth_root: "[data-role='risk-hhi']",
          parts: ["[data-role='risk-hhi']"]
        },
        %{
          kind: "asset_class_limits",
          wealth_root: "[data-role='risk-caps']",
          parts: [".empty-state", "details.perf-table-disclosure"]
        }
      ]
    }
    # --- S32 W4 end ---
  ]

  setup %{sandbox_owner: owner} do
    # The seed and the walk hold the shared connection for longer than the
    # sandbox's two-minute ownership timeout.
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

    starters =
      for starter <- @starters do
        {:ok, dashboard} = Dashboards.copy_template(Actor.owner_ui(), starter.key, %{})
        Map.put(starter, :id, dashboard.id)
      end

    %{base_url: "http://localhost:#{port}", starters: starters}
  end

  # User story (board 02 ②; D-7):
  # As the operator who keeps Wealth's tabs as dashboards,
  # I want each starter to show the tab's sections in the tab's order,
  # each drawing what the tab draws,
  # so that the dashboard is the tab, changeable piece by piece.
  #
  # Acceptance criteria:
  # - Each starter's widgets stand in the board's order, and the tab's
  #   sections in the same order.
  # - Each compared part reads the same, letter for letter, on the
  #   dashboard and on the tab, in German at 1200 px; none is missing or
  #   empty.
  test "each starter draws the tab's sections, in order, as the tab draws them", %{
    base_url: base_url,
    starters: starters
  } do
    result = run!(base_url, starters, false)

    for {starter, read} <- Enum.zip(starters, result["starters"]) do
      assert read["kinds"] == Enum.map(starter.sections, & &1.kind), starter.key
      assert read["ordered"], "#{starter.key}: the tab's sections in another order"

      for text <- List.flatten(Enum.map(read["widgets"], & &1["texts"])) do
        assert is_binary(text) and text != "",
               "#{starter.key}: a part is missing: #{inspect(read)}"
      end

      assert mismatches(starter, read) == [],
             "#{starter.key}: #{inspect(mismatches(starter, read))}"
    end
  end

  # User story (the walk's own check):
  # As the maintainer who trusts the comparison,
  # I want a section that reads differently on the tab seen caught,
  # so that a comparison that compares nothing cannot pass for one.
  #
  # Acceptance criteria:
  # - With the first part of each tab's first section changed in the
  #   browser, the comparison names that part for every starter.
  test "a part that reads differently on the tab is named", %{
    base_url: base_url,
    starters: starters
  } do
    result = run!(base_url, starters, true)

    for {starter, read} <- Enum.zip(starters, result["starters"]) do
      [first | _] = hd(starter.sections).parts
      assert {hd(starter.sections).kind, first} in mismatches(starter, read), starter.key
    end
  end

  # The parts that read differently on the dashboard and on the tab, each
  # as `{kind, part}`.
  defp mismatches(starter, read) do
    for {section, widget, wealth} <- Enum.zip([starter.sections, read["widgets"], read["wealth"]]),
        {part, mine, theirs} <- Enum.zip([section.parts, widget["texts"], wealth["texts"]]),
        mine != theirs,
        do: {section.kind, part}
  end

  defp run!(base_url, starters, tamper) do
    {output, status} =
      System.cmd(
        "node",
        [@script, Jason.encode!(%{base_url: base_url, starters: starters, tamper: tamper})],
        stderr_to_stdout: true
      )

    assert status == 0, "the browser run failed:\n" <> output
    result = output |> String.split("\n", trim: true) |> List.last() |> Jason.decode!()
    assert result["ok"] == true, result["error"] || inspect(result)
    result
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
