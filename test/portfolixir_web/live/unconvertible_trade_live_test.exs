defmodule PortfolixirWeb.UnconvertibleTradeLiveTest do
  # #1198 (Sprint 21 α3; board 09-money-states, pick N8 A; the ADR-0015
  # amendment of 2026-10-09, point 3): a closed trade a lot of which has no
  # leg in the sale's currency is unavailable. The security's Trades tab
  # keeps its row with the reason dash and names the remedy; the Trades
  # facet and the Overview card leave it out and name it in their exclusion
  # note, apart from a sale with no close-date rate. Synthetic names and
  # figures (the board's "Arbolia Inc."). async: false: the facet and the
  # card read every security.
  use PortfolixirWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.WorldFixtures

  # An imported buy of 10 Arbolia at 80.00 EUR into the EUR account with no
  # legs (no rate was stored for its day), sold by hand at 120 USD, settled
  # 960.00 EUR, fee 3.00 EUR; beside it a EUR round trip that converts.
  defp seed! do
    world =
      WorldFixtures.base_world(name: "Muster", cash_name: "Test-Cash", depot_name: "Depot Muster")

    arbolia =
      WorldFixtures.create_security!(name: "Arbolia Inc.", ticker: "ARBL", currency: "USD")

    wren = WorldFixtures.create_security!(name: "Wrenfield Gardens AG", ticker: "WRG")

    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2026-08-14],
          rate: "1.25",
          source: "manual"
        }
      ])

    {:ok, _buy} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        cash_account_id: world.cash.id,
        security_id: arbolia.id,
        type: "buy",
        date: ~D[2025-02-12],
        quantity: "10",
        price: "80",
        fees: "5",
        taxes: "1",
        currency_code: "EUR",
        gross_amount: "806"
      })

    WorldFixtures.cross_trade!(world, arbolia,
      type: "sell",
      quantity: "10",
      price: "120",
      settled: "960.00",
      fees: "3.00",
      gross: "957.00",
      date: ~D[2026-08-14]
    )

    WorldFixtures.buy!(world, wren, quantity: "10", price: "50", fees: "1", date: ~D[2026-07-01])
    WorldFixtures.sell!(world, wren, quantity: "10", price: "60", fees: "1", date: ~D[2026-08-14])

    %{arbolia: arbolia}
  end

  defp text(html),
    do: html |> Floki.parse_fragment!() |> Floki.text(sep: " ") |> String.replace(~r/\s+/, " ")

  # User story (#1198, N8 A, the tab):
  # As the operator looking at a security whose sale closed a lot with no
  # figure in the sale's currency,
  # I want the trade kept as a row whose cost and result are a reason dash,
  # and a note that names the lot and what fixes it,
  # so that the trade that happened stays on its page and I know the remedy.
  #
  # Acceptance criteria:
  # - The row keeps Opened, Closed, Quantity, Avg sell (120.00) and Days; Avg
  #   buy, p. a., the result and "%" are four reason dashes titled "Not
  #   convertible: a buy in EUR has no figure in USD", each with the hidden
  #   sentence.
  # - The phone row says "not convertible" in the result slot.
  # - The note (data-role trades-unavailable) names the buy of 2025-02-12,
  #   EUR, USD, and the remedy; in German "1 Trade ohne Umrechnung: Der Kauf
  #   vom 12.02.2025 ist in EUR gebucht …".
  test "the Trades tab keeps the unavailable row with its reason and names the remedy", %{
    conn: conn
  } do
    %{arbolia: arbolia} = seed!()

    {:ok, view, _html} = live(conn, "/securities/#{arbolia.id}?tab=trades")

    row = view |> element("#detail-closed-trades-table tbody tr") |> render()
    cells = row |> Floki.parse_fragment!() |> Floki.find("td")
    assert length(cells) == 9
    assert text(row) =~ "120.00"

    dashes = Floki.find(cells, "td[data-role=trade-unconvertible]")
    assert length(dashes) == 4

    for dash <- dashes do
      assert Floki.attribute(dash, "title") == [
               "Not convertible: a buy in EUR has no figure in USD"
             ]

      assert Floki.text(dash) =~ "not convertible, a buy in EUR with no figure in USD"
    end

    phone = view |> element("#detail-closed-trades-phone-rows li") |> render()
    assert text(phone) =~ "not convertible"

    note = view |> element("[data-role=trades-unavailable]") |> render() |> text()

    assert note =~
             "1 trade not convertible: the buy of 2025-02-12 is booked in EUR and has no figure in USD, the sale's currency"

    assert note =~ "Remedy: a rate for 2025-02-12"

    {:ok, de_view, _html} = live(conn, "/securities/#{arbolia.id}?tab=trades&locale=de")
    de_note = de_view |> element("[data-role=trades-unavailable]") |> render() |> text()

    assert de_note =~
             "1 Trade ohne Umrechnung: Der Kauf vom 12.02.2025 ist in EUR gebucht und hat keinen Gegenwert in USD, der Währung des Verkaufs"

    assert de_view |> element("#detail-closed-trades-phone-rows li") |> render() |> text() =~
             "ohne Umrechnung"
  end

  # User story (#1198, N8 A, the tab; a trade that closes two lots):
  # As the operator whose sale closed two imported buys, neither with a
  # figure in the sale's currency,
  # I want the note to name that one trade once, with both buys,
  # so that it never reads as two trades.
  #
  # Acceptance criteria:
  # - Two legless buys of 5 Arbolia at 80.00 EUR (2025-02-12, 2025-03-12),
  #   one sale of 10 at 120 USD: the note holds one sentence, "1 trade not
  #   convertible: 2 buys it closes, of 2025-02-12, 2025-03-12, have no
  #   figure in USD, the sale's currency"; "1 trade not convertible" appears
  #   once. In German "1 Trade ohne Umrechnung: 2 Käufe, die er schließt,
  #   vom 12.02.2025, 12.03.2025, haben keinen Gegenwert in USD".
  test "a trade that closes two lots without their leg is named once, with both", %{conn: conn} do
    world =
      WorldFixtures.base_world(name: "Muster", cash_name: "Test-Cash", depot_name: "Depot Muster")

    arbolia =
      WorldFixtures.create_security!(name: "Arbolia Inc.", ticker: "ARBL", currency: "USD")

    for date <- [~D[2025-02-12], ~D[2025-03-12]] do
      {:ok, _buy} =
        Ledger.create_transaction(Actor.owner_ui(), %{
          portfolio_id: world.portfolio.id,
          securities_account_id: world.depot.id,
          cash_account_id: world.cash.id,
          security_id: arbolia.id,
          type: "buy",
          date: date,
          quantity: "5",
          price: "80",
          currency_code: "EUR",
          gross_amount: "400"
        })
    end

    WorldFixtures.cross_trade!(world, arbolia,
      type: "sell",
      quantity: "10",
      price: "120",
      settled: "960.00",
      gross: "960.00",
      date: ~D[2026-08-14]
    )

    {:ok, view, _html} = live(conn, "/securities/#{arbolia.id}?tab=trades")
    note = view |> element("[data-role=trades-unavailable]") |> render() |> text()

    assert note =~
             "1 trade not convertible: 2 buys it closes, of 2025-02-12, 2025-03-12, have no figure in USD, the sale's currency"

    assert length(String.split(note, "1 trade not convertible")) == 2

    {:ok, de_view, _html} = live(conn, "/securities/#{arbolia.id}?tab=trades&locale=de")
    de_note = de_view |> element("[data-role=trades-unavailable]") |> render() |> text()

    assert de_note =~
             "1 Trade ohne Umrechnung: 2 Käufe, die er schließt, vom 12.02.2025, 12.03.2025, haben keinen Gegenwert in USD"
  end

  # User story (#1198, N8 A, the aggregates):
  # As the operator reading the Trades facet and the Overview card,
  # I want the unavailable trade out of every row and total and named in the
  # exclusion note with a reason of its own,
  # so that the totals are right and I know it is a missing figure, not a
  # missing rate.
  #
  # Acceptance criteria:
  # - The facet's note says "1 sale is not convertible — a buy it closes has
  #   no figure in the sale's currency — and is excluded from every total:
  #   Arbolia Inc." and no no-rate sentence; the list shows Wrenfield alone.
  # - The card's note says "1 sale not convertible — … — is left out of the
  #   trades: Arbolia Inc." and points to the backfill; the card lists
  #   Wrenfield alone. In German "… fehlt bei den Trades: Arbolia Inc.".
  test "the facet and the card leave it out and name it apart", %{conn: conn} do
    seed!()

    {:ok, view, _html} = live(conn, "/cashflow?tab=realized")
    render_async(view)

    note = view |> element("#realized-excluded") |> render() |> text()

    assert note =~
             "1 sale is not convertible — a buy it closes has no figure in the sale's currency — and is excluded from every total: Arbolia Inc."

    refute has_element?(view, "[data-role=realized-excluded-no-rate]")

    {:ok, card, _html} = live(conn, "/")
    render_async(card)

    card_note =
      card
      |> element("#dashboard-trades [data-role='trades-card-excluded']")
      |> render()
      |> text()

    assert card_note =~
             "1 sale not convertible — a buy it closes has no figure in the sale's currency — is left out of the trades: Arbolia Inc."

    assert card_note =~ "The rate backfill is under “All trades”."
    assert has_element?(card, "#dashboard-trades [data-role='closed-trade']", "Wrenfield")
    refute has_element?(card, "#dashboard-trades [data-role='closed-trade']", "Arbolia")

    {:ok, de_card, _html} = live(conn, "/?locale=de")
    render_async(de_card)

    assert de_card
           |> element("#dashboard-trades [data-role='trades-card-excluded']")
           |> render()
           |> text() =~
             "1 Verkauf ohne Umrechnung — ein Kauf, den er schließt, hat keinen Gegenwert in der Währung des Verkaufs — fehlt bei den Trades: Arbolia Inc."
  end
end
