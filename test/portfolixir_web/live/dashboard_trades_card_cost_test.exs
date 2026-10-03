defmodule PortfolixirWeb.DashboardTradesCardCostTest do
  # #1030 (Sprint 18 F7): the Overview card "Closed trades" ran the whole
  # realized report on every mount — every transaction, the open-lot
  # decoration and the latest close of every sold security, an annualized
  # return for every closed trade, the matrix and the figures — to show five
  # rows. It now computes only what it shows. No rendered difference: the
  # first test pins the card as the whole report rendered it, before the
  # computation changed.
  use PortfolixirWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [add_depot: 2, base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, sell!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.TradeReturn
  alias Portfolixir.Portfolios.RealizedGains

  # Nine closed trades over eight securities, chosen for what decides the
  # five rows and their order:
  # - a tie on the close date across two securities (Birchway, Cedar Row) and
  #   two sells of one security on one day (Dunmore), so the order of equal
  #   close dates is pinned too;
  # - one sell consuming two lots (Birchway);
  # - a pound trade converted at its close-date rate (Gorse Lane) and one with
  #   no rate that day, excluded and named (Fernhill);
  # - a total loss (Elmstead), a long gain (Alder Kiln) and the oldest close
  #   (Ivybridge), which fall outside the five;
  # - the newest sell of all sells delivered-in shares (Hollowmere): no lot,
  #   so no trade, and not one of the five.
  defp seed! do
    world = base_world(name: "Card Cost", cash_name: "Girokonto", depot_name: "Depot 1")
    deposit!(world, "100000", ~D[2023-01-02])

    gbp =
      Map.merge(
        world,
        add_depot(world.portfolio,
          currency: "GBP",
          cash_name: "GBP Konto",
          depot_name: "GBP Depot"
        )
      )

    alder = create_security!(name: "Alder Kiln AG", ticker: nil)
    birchway = create_security!(name: "Birchway Foods SE", ticker: nil)
    cedar = create_security!(name: "Cedar Row Retail", ticker: nil)
    dunmore = create_security!(name: "Dunmore Tools", ticker: nil)
    elmstead = create_security!(name: "Elmstead Mining", ticker: nil)
    fernhill = create_security!(name: "Fernhill Energy plc", ticker: nil, currency: "GBP")
    gorse = create_security!(name: "Gorse Lane plc", ticker: nil, currency: "GBP")
    hollowmere = create_security!(name: "Hollowmere Water", ticker: nil)
    ivybridge = create_security!(name: "Ivybridge Optics", ticker: nil)

    buy!(world, ivybridge, quantity: "3", price: "100", date: ~D[2023-02-01])
    sell!(world, ivybridge, quantity: "3", price: "110", date: ~D[2023-03-01])

    buy!(world, elmstead, quantity: "10", price: "40", date: ~D[2023-03-01])
    sell!(world, elmstead, quantity: "10", price: "0", date: ~D[2025-11-01])

    buy!(world, alder, quantity: "10", price: "100", date: ~D[2024-01-02])
    sell!(world, alder, quantity: "10", price: "144", date: ~D[2026-01-01])

    buy!(world, birchway, quantity: "5", price: "100", date: ~D[2024-03-01])
    buy!(world, birchway, quantity: "5", price: "110", date: ~D[2024-09-02])
    sell!(world, birchway, quantity: "10", price: "120", date: ~D[2026-03-10])

    buy!(world, cedar, quantity: "4", price: "50", date: ~D[2026-02-02])
    sell!(world, cedar, quantity: "4", price: "45", date: ~D[2026-03-10])

    buy!(world, dunmore, quantity: "10", price: "10", date: ~D[2025-01-06])
    sell!(world, dunmore, quantity: "4", price: "12", date: ~D[2026-04-01])
    sell!(world, dunmore, quantity: "6", price: "9", date: ~D[2026-04-01])

    buy!(gbp, fernhill, quantity: "2", price: "10", date: ~D[2026-01-09], currency: "GBP")
    sell!(gbp, fernhill, quantity: "2", price: "30", date: ~D[2026-02-20], currency: "GBP")

    buy!(gbp, gorse, quantity: "2", price: "10", date: ~D[2025-01-09], currency: "GBP")
    sell!(gbp, gorse, quantity: "2", price: "20", date: ~D[2026-04-15], currency: "GBP")

    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "GBP",
          date: ~D[2026-04-15],
          rate: "0.80",
          source: "manual"
        }
      ])

    {:ok, _delivery} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        security_id: hollowmere.id,
        type: "inbound_delivery",
        date: ~D[2026-01-10],
        quantity: "5",
        currency_code: "EUR"
      })

    sell!(world, hollowmere, quantity: "5", price: "20", date: ~D[2026-05-01])

    [alder, birchway, cedar, dunmore, elmstead, fernhill, gorse, hollowmere, ivybridge]
  end

  defp text(nodes),
    do: nodes |> Floki.text(sep: " ") |> String.replace(~r/\s+/, " ") |> String.trim()

  # The card as the reader gets it: every text, every link (the security's
  # id spelled as its name, since ids differ between runs) and every sign
  # class, row by row.
  defp card_snapshot(view, securities) do
    names = Map.new(securities, &{"/securities/#{&1.id}?tab=trades", &1.name})
    card = view |> render() |> Floki.parse_document!() |> Floki.find("#dashboard-trades")

    %{
      head: text(Floki.find(card, ".section-head")),
      notes: card |> Floki.find(".data-note") |> Enum.map(&text/1),
      basis: text(Floki.find(card, "[data-role='trades-card-basis']")),
      rows:
        card
        |> Floki.find("[data-role='closed-trade']")
        |> Enum.map(fn row ->
          [href] = Floki.attribute(row, "href")

          {Map.fetch!(names, href), text(row),
           row |> Floki.find(".is-positive, .is-negative, .is-flat") |> Enum.map(&sign/1)}
        end)
    }
  end

  defp sign(node) do
    [class] = Floki.attribute(node, "class")
    {class, text(node)}
  end

  # Characterization (written and run green before the computation changed):
  # As a local portfolio maintainer landing on the Overview,
  # I want the closed-trades card to show the same five rows, in the same
  # order, with the same figures and the same exclusion note, after the card
  # stopped running the whole realized report,
  # so that a cheaper card is not a different card.
  test "the card renders the newest five as the whole report did", %{conn: conn} do
    securities = seed!()

    {:ok, view, _html} = live(conn, "/")
    render_async(view)

    assert card_snapshot(view, securities) == %{
             head: "Closed trades All trades →",
             notes: [
               "Attention 1 sale with no stored rate on its close date is left out of the " <>
                 "trades: Fernhill Energy plc. The rate backfill is under “All trades”."
             ],
             basis:
               "The 5 most recently closed · result in EUR · FIFO across every depot, " <>
                 "whatever the view · p. a. only from 365 days of holding",
             rows: [
               {"Gorse Lane plc",
                "Gorse Lane plc sold 2026-04-15 · 461 days +25.00 EUR +73.1% p. a.",
                [{"is-positive", "+25.00"}, {"is-positive", "+73.1%"}]},
               {"Dunmore Tools",
                "Dunmore Tools sold 2026-04-01 · 450 days +8.00 EUR +15.9% p. a.",
                [{"is-positive", "+8.00"}, {"is-positive", "+15.9%"}]},
               {"Dunmore Tools", "Dunmore Tools sold 2026-04-01 · 450 days -6.00 EUR -8.2% p. a.",
                [{"is-negative", "-6.00"}, {"is-negative", "-8.2%"}]},
               {"Cedar Row Retail",
                "Cedar Row Retail sold 2026-03-10 · 36 days -20.00 EUR -10.0% total",
                [{"is-negative", "-20.00"}, {"is-negative", "-10.0%"}]},
               {"Birchway Foods SE",
                "Birchway Foods SE sold 2026-03-10 · 647 days +150.00 EUR +7.9% p. a.",
                [{"is-positive", "+150.00"}, {"is-positive", "+7.9%"}]}
             ]
           }
  end

  # User story (#1030):
  # As a local portfolio maintainer whose Overview is the landing page,
  # I want the closed-trades card to compute only the rows it shows,
  # so that its cost does not grow with every security I ever sold and
  # every trade I ever closed.
  #
  # Acceptance criteria:
  # - The card's read does not run the whole realized report, and not the
  #   per-security trades read with its open-lot decoration and latest close.
  # - It annualizes only the five trades it shows, not every closed trade.
  # - The read is the realized report's own projection — the same rows, order
  #   and exclusions (pinned in Portfolixir.Portfolios.RealizedGainsNewestTest).
  test "the card computes only the rows it shows", %{conn: conn} do
    seed!()

    counts =
      calls_by_new_processes(
        [
          {RealizedGains, :report, 1},
          {Ledger, :list_trades_for_security, 2},
          {TradeReturn, :annualized, 2}
        ],
        fn ->
          {:ok, view, _html} = live(conn, "/")
          render_async(view)
          assert has_element?(view, "#dashboard-trades [data-role='closed-trade']")
        end
      )

    # Nine closed trades over nine sold securities: the whole report annualized
    # all nine and read every security's trades with its open lots.
    assert Map.get(counts, {RealizedGains, :report, 1}, 0) == 0
    assert Map.get(counts, {Ledger, :list_trades_for_security, 2}, 0) == 0
    assert Map.get(counts, {TradeReturn, :annualized, 2}, 0) == 5
  end

  # Counts the calls to `mfas`, local calls included, made by every process
  # `fun` starts — the LiveView and its async reads — collected by a separate
  # tracer process, after every trace message has been delivered.
  defp calls_by_new_processes(mfas, fun) do
    collector = spawn_link(fn -> collect(%{}) end)

    for {module, _function, _arity} = mfa <- mfas do
      Code.ensure_loaded!(module)
      :erlang.trace_pattern(mfa, true, [:local])
    end

    :erlang.trace(:new_processes, true, [:call, {:tracer, collector}])

    try do
      fun.()
    after
      :erlang.trace(:new_processes, false, [:call])
      for mfa <- mfas, do: :erlang.trace_pattern(mfa, false, [:local])
    end

    ref = :erlang.trace_delivered(:all)

    receive do
      {:trace_delivered, :all, ^ref} -> :ok
    end

    send(collector, {:counts, self()})

    receive do
      {:counts, counts} -> counts
    end
  end

  defp collect(counts) do
    receive do
      {:trace, _pid, :call, {module, function, args}} ->
        collect(Map.update(counts, {module, function, length(args)}, 1, &(&1 + 1)))

      {:counts, from} ->
        send(from, {:counts, counts})
    end
  end
end
