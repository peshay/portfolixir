defmodule PortfolixirWeb.WealthExplanationsLiveTest do
  # Board `ux-design-2026-11-01-sprint22/01-i1` on Wealth → Bestände (I1,
  # #1351, variant R; pick Q1): the data-quality block leads with its
  # problems, the notes that name rows left out of the totals clamp and
  # never fold, the rest fold into one line; the contribution's method
  # sentences move into the ⓘ beside its heading and its basis clause
  # stays. Every name is synthetic.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Classifications
  alias Portfolixir.Ledger
  alias Portfolixir.WorldFixtures

  defp seed_world do
    world =
      WorldFixtures.base_world(name: "Demo Portfolio", cash_name: "Giro", depot_name: "Depot")

    {:ok, _} = Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

    security = WorldFixtures.create_security!(name: "World ETF", ticker: "WLD")
    WorldFixtures.deposit!(world, "5000", Date.add(Date.utc_today(), -60))
    WorldFixtures.buy!(world, security, quantity: "8", price: "100")
    WorldFixtures.put_quote!(security, Date.utc_today(), "110")

    world
  end

  defp security!(name, ticker, currency) do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: name,
        ticker_symbol: ticker,
        currency_code: currency,
        asset_class: "equity"
      })

    security
  end

  defp deliver!(world, security, type, quantity, days_ago) do
    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        security_id: security.id,
        type: type,
        date: Date.add(Date.utc_today(), -days_ago),
        quantity: quantity,
        currency_code: security.currency_code
      })
  end

  # Five findings, one of each kind the block's rule sorts: a problem, two
  # notes that name rows left out of the totals, and two that only qualify
  # them.
  defp seed_findings(world) do
    # Problem: an impossible negative holding.
    doomed = security!("Doomed Co.", "DOOM", "EUR")
    deliver!(world, doomed, "inbound_delivery", "100", 5)
    deliver!(world, doomed, "outbound_delivery", "500", 2)

    # Excluded rows: no price at all, and a price with no rate to EUR.
    dark = security!("Delivered Co.", "DLVR", "EUR")
    deliver!(world, dark, "inbound_delivery", "3", 5)
    spacey = security!("Space Exploration Co.", "SPACE", "USD")
    deliver!(world, spacey, "inbound_delivery", "5", 5)
    WorldFixtures.put_quote!(spacey, Date.add(Date.utc_today(), -1), "120")

    # Qualifiers: valued at its own last trade price; valued at an old quote.
    traded = WorldFixtures.create_security!(name: "Traded Co.", ticker: "TRDE")
    WorldFixtures.buy!(world, traded, quantity: "2", price: "30")
    old = WorldFixtures.create_security!(name: "Old Quote Co.", ticker: "OLDQ")
    WorldFixtures.buy!(world, old, quantity: "3", price: "20")
    WorldFixtures.put_quote!(old, Date.add(Date.utc_today(), -40), "21")
  end

  defp roles(view, selector) do
    view
    |> render()
    |> LazyHTML.from_document()
    |> LazyHTML.query(selector)
    |> Enum.map(&(&1 |> LazyHTML.attribute("data-role") |> List.first()))
  end

  # User story (#1351, board 01 ③ ④ ⑤ on Wealth; pick Q1, correction 1):
  # As the operator reading Wealth's data quality,
  # I want the problems first, the notes that say what the totals leave out
  # next, and the notes that only qualify a figure folded into one line,
  # so that the block no longer fills the page while nothing that is wrong
  # or missing from a total is hidden.
  #
  # Acceptance criteria:
  # - The status region's children, in order: the problem note(s), then
  #   the notes that name rows left out of the totals ("no price at all",
  #   "no exchange rate", "cash accounts not counted"), then one fold.
  # - Every note clamps (`data-note--clamped`, its own id); the notes that
  #   name excluded rows are never inside the fold, and the count of
  #   excluded rows leads their text.
  # - The fold holds the trade-priced note and the stale-quote note and
  #   reads "1 Attention · 1 Note — Show details".
  # - The missing-FX note's "Sync exchange rates" stays visible under the
  #   clamp, in the note's actions.
  test "Wealth's data quality: problems lead, excluded rows clamp, the rest fold",
       %{conn: conn} do
    world = seed_world()
    seed_findings(world)

    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)

    region = "#portfolio-data-quality [role='status'][data-role='dq-notes']"

    assert roles(view, region <> " > *") == [
             "dq-negative-holdings",
             "dq-no-price",
             "dq-missing-fx",
             "folded-notes"
           ]

    for role <- ["dq-negative-holdings", "dq-no-price", "dq-missing-fx"] do
      assert has_element?(view, region <> " > .data-note--clamped[data-role='#{role}'][id]")
    end

    no_price =
      view
      |> element(region <> " > [data-role='dq-no-price'] .data-note__text")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.text()
      |> String.replace(~r/\s+/u, " ")
      |> String.trim()

    assert no_price ==
             "2 held positions have no price at all and are missing from the totals: Doomed Co., Delivered Co."

    assert has_element?(
             view,
             region <>
               " > [data-role='dq-missing-fx'] .data-note__actions button[phx-click='sync_rates']",
             "Sync exchange rates"
           )

    fold = region <> " > details.data-note-group--attention[data-role='folded-notes']"
    assert has_element?(view, fold <> " > summary", "1 Attention")
    assert has_element?(view, fold <> " > summary", "1 Note")

    assert roles(view, fold <> " .data-note-group__body > .data-note--clamped") == [
             "dq-trade-priced",
             "dq-stale-priced"
           ]
  end
end
