defmodule PortfolixirWeb.Browser.HoldingsStarterTest do
  # The starter „Bestände“ against Wealth's tab „Bestände“ in a real
  # browser (Sprint 32 W1; I57; ADR-0062's amendment of 2026-11-25, point
  # 5; board ux-design-2026-11-25-sprint32/02 ①), through
  # `holdings_starter.js` with Playwright, on the review seed
  # (priv/demo/finding_surfaces_seed.exs), the starters stored as the boot
  # stores them (`Portfolixir.Dashboards.Starters.seed/0`).
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
  alias Portfolixir.Dashboards
  alias Portfolixir.Dashboards.Starters
  alias Portfolixir.Repo

  @moduletag :browser
  @moduletag timeout: 600_000

  @script Path.expand("holdings_starter.js", __DIR__)
  @seed "priv/demo/finding_surfaces_seed.exs"
  @sections ~w(wealth_key_figures data_notes performance contribution positions cash_accounts)

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
    %{base_url: "http://localhost:#{port}", dashboard: holdings_starter!()}
  end

  # User story (board 02 ①):
  # As the operator who opens the starter „Bestände“,
  # I want it to show Wealth's tab „Bestände“ section by section,
  # so that the dashboard I can change looks like the tab I know.
  #
  # Acceptance criteria:
  # - On the review seed at 1200 px, the starter's widgets are, in reading
  #   order, the tab's sections in the tab's order, each a „Zeile“:
  #   Kennzahlen, Datenhinweise, Performance, Beitrag je Position,
  #   Positionen, Verrechnungskonten.
  # - Each widget draws its section's figure as the tab does: the total,
  #   the data notes, the period's badge, the contribution's sum, the
  #   position rows, the cash accounts.
  # - The check's attack: two sections swapped, or a figure not the tab's,
  #   is named.
  test "the starter „Bestände“ draws the tab's sections, in order, as the tab does", %{
    base_url: base_url,
    dashboard: dashboard
  } do
    result = run!(base_url, dashboard)
    assert result["ok"] == true, result["error"] || inspect(result)

    starter = result["starter"]
    wealth = result["wealth"]
    assert problems(starter, wealth) == []

    # The check's own attack: the same answer with two sections swapped,
    # or one figure that differs from the tab's, is named.
    [first, second | rest] = starter
    assert {:order, _} = List.keyfind(problems([second, first | rest], wealth), :order, 0)

    changed = [Map.put(first, "figure", "1,00 EUR") | tl(starter)]
    assert {:figure, "wealth_key_figures"} in problems(changed, wealth)
  end

  # What a starter's answer gets wrong against the tab's: the sections or
  # their order, a size other than „Zeile“, a figure missing or not the
  # tab's.
  defp problems(starter, wealth) do
    order =
      if Enum.map(starter, & &1["kind"]) == @sections and
           Enum.map(wealth, & &1["kind"]) == @sections,
         do: [],
         else: [{:order, {Enum.map(starter, & &1["kind"]), Enum.map(wealth, & &1["kind"])}}]

    sizes = for mine <- starter, mine["size"] != "row", do: {:size, mine["kind"]}

    figures =
      for {mine, tab} <- Enum.zip(starter, wealth),
          mine["kind"] == tab["kind"],
          mine["figure"] in [nil, ""] or figure(mine) != figure(tab),
          do: {:figure, mine["kind"]}

    order ++ sizes ++ figures
  end

  # The total is compared as its amount; Wealth's card carries its
  # currency and its composition beside it.
  defp figure(%{"kind" => "wealth_key_figures", "figure" => text}),
    do: Regex.run(~r/[\d.]+,\d{2}/, text)

  defp figure(%{"figure" => text}), do: text

  defp run!(base_url, dashboard) do
    {output, status} =
      System.cmd("node", [@script, Jason.encode!(%{base_url: base_url, id: dashboard.id})],
        stderr_to_stdout: true
      )

    assert status == 0, "the browser run failed:\n" <> output

    output
    |> String.split("\n", trim: true)
    |> List.last()
    |> Jason.decode!()
  end

  # The starters as the boot stores them; „Bestände“ is the copy of the
  # template „holdings“.
  defp holdings_starter! do
    {:ok, %{stored: stored}} = Starters.seed()
    assert "holdings" in stored
    Enum.find(Dashboards.list_dashboards(), &(&1.template_key == "holdings"))
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
