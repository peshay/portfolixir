defmodule PortfolixirWeb.CashflowExplanationsLiveTest do
  # Board `ux-design-2026-11-01-sprint22/01-i1` on Cash flow (I1, #1351,
  # variant R; pick Q1): the Trades list's method clauses move into the
  # facet's ⓘ, its gross/net clauses stay, and every facet's note clamps
  # while its remedy stays in view. Every name is synthetic.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Ledger
  alias Portfolixir.WorldFixtures

  # GBP has no stored rate: a closed trade, a deposit, a fee and a dividend
  # in it are excluded on all four facets. A delivered security sold is a
  # sale with no matched buy.
  defp seed! do
    world = WorldFixtures.base_world(name: "Realized", currency: "EUR")
    gbp = WorldFixtures.create_security!(name: "Pound Equity", ticker: "PGB", currency: "GBP")

    gbp_world =
      Map.merge(
        world,
        WorldFixtures.add_depot(world.portfolio,
          currency: "GBP",
          cash_name: "GBP Cash",
          depot_name: "GBP Depot"
        )
      )

    WorldFixtures.deposit!(gbp_world, "100", ~D[2026-01-05], currency: "GBP")

    WorldFixtures.buy!(gbp_world, gbp,
      quantity: "2",
      price: "10",
      date: ~D[2026-01-09],
      currency: "GBP"
    )

    WorldFixtures.sell!(gbp_world, gbp,
      quantity: "2",
      price: "30",
      date: ~D[2026-02-20],
      currency: "GBP"
    )

    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: gbp_world.cash.id,
        type: "fee",
        date: ~D[2026-02-20],
        gross_amount: "5",
        currency_code: "GBP"
      })

    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: gbp_world.cash.id,
        security_id: gbp.id,
        type: "dividend",
        date: ~D[2026-02-10],
        gross_amount: "3",
        currency_code: "GBP"
      })

    delivered = WorldFixtures.create_security!(name: "Delivered Co", ticker: "DLV")
    WorldFixtures.deposit!(world, "1000", ~D[2026-01-02])

    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        security_id: delivered.id,
        type: "inbound_delivery",
        date: ~D[2026-01-10],
        quantity: "5",
        currency_code: "EUR"
      })

    WorldFixtures.sell!(world, delivered, quantity: "5", price: "20", date: ~D[2026-03-01])
    world
  end

  defp squish(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()

  defp text(view, selector) do
    view
    |> element(selector)
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.text()
    |> squish()
  end

  defp lines(view, selector) do
    view
    |> element(selector)
    |> render()
    |> String.split(~r/<br\s*\/?>/)
    |> Enum.map(&(&1 |> LazyHTML.from_fragment() |> LazyHTML.text() |> squish()))
  end

  # User story (#1351, board 01 ① ② ③ on Cash flow → Trades):
  # As the operator reading the Trades facet,
  # I want the list's method behind the facet's ⓘ and its gross/net basis
  # under the list, and the notes cut to two lines with their remedy in view,
  # so that the excluded sales are counted first and the backfill stays one
  # press away.
  #
  # Acceptance criteria:
  # - The facet's ⓘ keeps its composition and, after a blank line, "Deliveries
  #   open no lot" and "p. a. only from 365 days of holding and only where a
  #   rate solves the flows", one per line; after another blank line the
  #   four exclusion reasons' definitions (Sprint 23 Lane I, Income ①).
  # - The list's basis line keeps "fees and taxes in cost and proceeds ·
  #   income received while a trade was open not included".
  # - Both exclusion notes clamp and never fold: the excluded sales' count
  #   leads; the backfill's reason ("The daily rate sync cannot fill a past
  #   date. …") reads in the note's text, and its button sits in the note's
  #   actions; the unmatched sales' list ("The sale") sits in its actions.
  test "Trades: the method sits in the facet's ⓘ, the notes clamp and keep their remedy",
       %{conn: conn} do
    seed!()

    {:ok, view, _html} = live(conn, "/cashflow?tab=realized")
    render_async(view)

    assert [
             "Realized gains and losses from FIFO-matched sales" <> _,
             "",
             "Deliveries open no lot",
             pa,
             "",
             "Buy without a figure in the sale's currency: " <> _,
             "Third currency: " <> _,
             "Buy paid in another currency: " <> _,
             "Buy of amount zero: " <> _
           ] =
             lines(view, "[data-role='facet-info'] p[role='tooltip']")

    assert pa == "p. a. only from 365 days of holding and only where a rate solves the flows"

    assert text(view, "#realized-trades [data-role='trades-basis']") ==
             "fees and taxes in cost and proceeds · income received while a trade was open not included"

    excluded = "#realized-excluded.data-note--clamped"
    assert text(view, excluded <> " .data-note__text") =~ ~r/^1 sale could not be converted/

    assert text(view, excluded <> " .data-note__text") =~
             "The daily rate sync cannot fill a past date."

    assert has_element?(view, excluded <> " .data-note__actions #fx-backfill-button")

    unmatched = "#realized-unmatched.data-note--clamped"
    assert text(view, unmatched <> " .data-note__text") =~ ~r/^1 sale has no matched buy/

    assert has_element?(
             view,
             unmatched <> " .data-note__actions [data-role='realized-unmatched-list']"
           )
  end

  # User story (#1351, board 01 ③ on Cash flow's other facets):
  # As the operator reading Income, Flows or Costs,
  # I want each facet's exclusion note cut to two lines with its backfill in
  # view,
  # so that the facet reads as its figures, and what they leave out is
  # counted first and one tap from its names.
  #
  # Acceptance criteria:
  # - `#income-excluded`, `#flows-excluded` and `#costs-excluded` clamp; the
  #   backfill's reason reads in the text, its button in the actions.
  test "Income, Flows and Costs: the exclusion notes clamp, the backfill in view",
       %{conn: conn} do
    seed!()

    for {tab, id} <- [
          {"income", "income-excluded"},
          {"flows", "flows-excluded"},
          {"costs", "costs-excluded"}
        ] do
      {:ok, view, _html} = live(conn, "/cashflow?tab=#{tab}")
      render_async(view)

      note = "##{id}.data-note--clamped"
      assert text(view, note <> " .data-note__text") =~ ~r/^1 \w+ could not be converted/

      assert text(view, note <> " .data-note__text") =~
               "The daily rate sync cannot fill a past date."

      assert has_element?(view, note <> " .data-note__actions #fx-backfill-button")
    end
  end
end
