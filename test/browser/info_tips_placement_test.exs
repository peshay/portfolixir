defmodule PortfolixirWeb.Browser.InfoTipsPlacementTest do
  # Where an ⓘ panel opens, in a real browser (the stacked PR's closing act,
  # Sprint 23: V2's merge dialog and Lane I's heading ⓘs). LiveViewTest
  # renders the server's markup and runs no client script, so this test
  # boots the endpoint on a free loopback port and drives Chromium through
  # `info_tips_placement.js` with Playwright, as
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
  alias Portfolixir.Journal
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios
  alias Portfolixir.Repo

  @moduletag :browser
  @moduletag timeout: 120_000

  @script Path.expand("info_tips_placement.js", __DIR__)

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

  # User story (stacked PR closing act; V2 and Lane I):
  # As the operator opening an ⓘ,
  # I want its panel to open where I can read all of it,
  # so that no line hides under a dialog's scroll edge or the top bar.
  #
  # Acceptance criteria:
  # - In the depot merge preview at 1280 px, the external flows section's ⓘ
  #   panel lies inside the dialog's scrolling body.
  # - A heading's ⓘ near the top of the page (Snapshots at 1280 px, Risk's
  #   "Own rules" at 390 px) opens below the sticky top bar, never over it.
  # - Each stays within the viewport's width.
  test "an ⓘ panel opens inside the box that clips it and below the top bar",
       %{base_url: base_url} do
    world = risk_world!()
    {source, target} = merge_pair!(world.portfolio)

    argument =
      Jason.encode!(%{base_url: base_url, source_id: source.id, target_id: target.id})

    {output, status} = System.cmd("node", [@script, argument], stderr_to_stdout: true)

    assert status == 0, "the browser run failed:\n" <> output

    result =
      output
      |> String.split("\n", trim: true)
      |> List.last()
      |> Jason.decode!()

    assert result == %{"ok" => true}
  end

  defp day(offset), do: Date.add(Date.utc_today(), offset)

  # Risk's world, as PortfolixirWeb.RiskExplanationsLiveTest seeds it.
  defp risk_world! do
    world = base_world()
    deposit!(world, "10000", day(-400))

    for {name, ticker, quantity, step} <- [
          {"Nordic Timber Holdings AB", "NTH", "20", 7},
          {"Helios Solar Systems SE", "HSS", "5", 5}
        ] do
      security = create_security!(name: name, ticker: ticker, asset_class: "equity")
      buy!(world, security, quantity: quantity, price: "100", date: day(-400))
      put_quotes!(security, for(o <- -400..0, do: {day(o), "#{100 + rem(o, step)}"}))
    end

    world
  end

  # Two depots with one equal inbound delivery each, so the merge preview
  # lists the external flow a collapse removes (as
  # PortfolixirWeb.AccountsMergeLiveTest seeds it).
  defp merge_pair!(portfolio) do
    security = create_security!(name: "Meridian Global Equity ETF", ticker: "MRDN")
    target = depot!(portfolio, cash!(portfolio, "Broker cash"), "Depot 1")
    source = depot!(portfolio, cash!(portfolio, "Broker cash 2"), "Depot 2")

    for depot <- [source, target], do: delivery!(portfolio, depot, security)

    {source, target}
  end

  defp cash!(portfolio, name) do
    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: name,
        currency_code: "EUR"
      })

    cash
  end

  defp depot!(portfolio, cash, name) do
    {:ok, depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: name
      })

    depot
  end

  # Written the way the Portfolio Performance importer writes a delivery.
  defp delivery!(portfolio, depot, security) do
    attrs = %{
      portfolio_id: portfolio.id,
      securities_account_id: depot.id,
      security_id: security.id,
      type: "inbound_delivery",
      date: ~D[2025-03-03],
      quantity: "10",
      price: "80.00",
      currency_code: "EUR"
    }

    {:ok, _changes} =
      Ecto.Multi.new()
      |> Ecto.Multi.insert(:transaction, Transaction.import_changeset(%Transaction{}, attrs))
      |> Journal.record(Actor.import_session(),
        resource_type: "transaction",
        operation: :create,
        source: :transaction
      )
      |> Repo.transaction()
  end
end
