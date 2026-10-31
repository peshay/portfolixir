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
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo
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

    %{arbolia: arbolia, world: world}
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
  #   EUR, USD, and the remedy, its control named as the Cash flow page
  #   labels it ("Backfill historical rates" on Cash flow → "Trades"); in
  #   German "1 Trade ohne Umrechnung: Der Kauf vom 12.02.2025 ist in EUR
  #   gebucht …" and "„Historische Kurse nachladen“ unter Cashflow →
  #   „Trades“".
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

    # #1198 (the UAT of the α closing act): the control is named as the
    # Cash flow page labels it, its facet "Trades", not "All trades".
    assert note =~
             "Remedy: a rate for 2025-02-12 — “Backfill historical rates” on Cash flow → “Trades” stores it and derives the figure from it — or the figure in USD on the booking."

    {:ok, de_view, _html} = live(conn, "/securities/#{arbolia.id}?tab=trades&locale=de")
    de_note = de_view |> element("[data-role=trades-unavailable]") |> render() |> text()

    assert de_note =~
             "1 Trade ohne Umrechnung: Der Kauf vom 12.02.2025 ist in EUR gebucht und hat keinen Gegenwert in USD, der Währung des Verkaufs"

    assert de_note =~
             "Abhilfe: ein Wechselkurs für den 12.02.2025 — „Historische Kurse nachladen“ unter Cashflow → „Trades“ speichert ihn und leitet daraus den Gegenwert ab — oder der Gegenwert in USD an der Buchung."

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
    arbolia = two_legless_lots!([~D[2025-02-12], ~D[2025-03-12]])

    {:ok, view, _html} = live(conn, "/securities/#{arbolia.id}?tab=trades")
    note = view |> element("[data-role=trades-unavailable]") |> render() |> text()

    assert note =~
             "1 trade not convertible: 2 buys it closes, of 2025-02-12, 2025-03-12, have no figure in USD, the sale's currency"

    assert length(String.split(note, "1 trade not convertible")) == 2

    assert note =~
             "Remedy: a rate for each of those dates — “Backfill historical rates” on Cash flow → “Trades” stores them and derives the figures from them — or the figures in USD on the bookings."

    {:ok, de_view, _html} = live(conn, "/securities/#{arbolia.id}?tab=trades&locale=de")
    de_note = de_view |> element("[data-role=trades-unavailable]") |> render() |> text()

    assert de_note =~
             "1 Trade ohne Umrechnung: 2 Käufe, die er schließt, vom 12.02.2025, 12.03.2025, haben keinen Gegenwert in USD"
  end

  # User story (#1198, N8 A, the tab; two lots opened the same day):
  # As the operator whose sale closed two legless buys of the same day,
  # I want the note to name that day once, the count still the two buys,
  # so that it never reads "of 2025-04-01, 2025-04-01".
  #
  # Acceptance criteria:
  # - Two legless buys of 5 Arbolia on 2025-04-01, one sale of 10: "1 trade
  #   not convertible: 2 buys it closes, of 2025-04-01, have no figure in
  #   USD"; in German "… 2 Käufe, die er schließt, vom 01.04.2025, haben
  #   keinen Gegenwert in USD".
  test "two lots of one day name their day once", %{conn: conn} do
    arbolia = two_legless_lots!([~D[2025-04-01], ~D[2025-04-01]])

    {:ok, view, _html} = live(conn, "/securities/#{arbolia.id}?tab=trades")
    note = view |> element("[data-role=trades-unavailable]") |> render() |> text()

    assert note =~
             "1 trade not convertible: 2 buys it closes, of 2025-04-01, have no figure in USD, the sale's currency"

    {:ok, de_view, _html} = live(conn, "/securities/#{arbolia.id}?tab=trades&locale=de")
    de_note = de_view |> element("[data-role=trades-unavailable]") |> render() |> text()

    assert de_note =~
             "1 Trade ohne Umrechnung: 2 Käufe, die er schließt, vom 01.04.2025, haben keinen Gegenwert in USD"
  end

  # User story (#1198, the α closing act's UAT):
  # As the operator reading the Trades facet's and the Overview card's
  # exclusion notes,
  # I want a security name that ends in a full stop to end the sentence
  # once,
  # so that the note never reads "… Arbolia Inc..".
  #
  # Acceptance criteria:
  # - Arbolia Inc.'s unavailable trade and Kestrel Inc.'s sale with no rate
  #   on its close date: the facet reads "… excluded from every total:
  #   Arbolia Inc." and "… excluded from every total: Kestrel Inc."; the
  #   card "… left out of the trades: Kestrel Inc. The rate backfill is
  #   under “All trades”." and "… left out of the trades: Arbolia Inc.";
  #   no note holds "Inc..".
  test "a name ending in a full stop ends the note's sentence once", %{conn: conn} do
    world = seed!()

    kestrel =
      WorldFixtures.create_security!(name: "Kestrel Inc.", ticker: "KSTL", currency: "USD")

    for {type, date, price} <- [{"buy", ~D[2026-01-05], "50"}, {"sell", ~D[2026-03-02], "60"}] do
      WorldFixtures.cross_trade!(world.world, kestrel,
        type: type,
        quantity: "10",
        price: price,
        settled: "#{price}0.00",
        gross: "#{price}0.00",
        date: date
      )
    end

    {:ok, view, _html} = live(conn, "/cashflow?tab=realized")
    render_async(view)

    assert view |> element("[data-role=realized-excluded-missing-leg]") |> render() |> text() =~
             ~r/excluded from every total: Arbolia Inc\.$/

    assert view |> element("[data-role=realized-excluded-no-rate]") |> render() |> text() =~
             ~r/excluded from every total: Kestrel Inc\.$/

    {:ok, card, _html} = live(conn, "/")
    render_async(card)

    card_note =
      card
      |> element("#dashboard-trades [data-role='trades-card-excluded']")
      |> render()
      |> text()

    assert card_note =~
             "left out of the trades: Kestrel Inc. The rate backfill is under “All trades”."

    assert card_note =~ "left out of the trades: Arbolia Inc."
    refute card_note =~ "Inc.."
  end

  # A buy or sell as a database stored it before #1199's refusal of a
  # booking priced in a third currency: written past the changeset, under
  # the journal's actor (as `closed_trade_currency_test.exs` writes it).
  defp stored_trade!(world, security, attrs) do
    {:ok, tx} =
      Repo.transaction(fn ->
        {type, _label} = Actor.to_columns(Actor.owner_ui())
        Repo.query!("SELECT set_config('portfolixir.journal_actor', $1, true)", [type])

        Repo.insert!(
          struct!(
            Transaction,
            Map.merge(
              %{
                portfolio_id: world.portfolio.id,
                securities_account_id: world.depot.id,
                cash_account_id: world.cash.id,
                security_id: security.id,
                taxes: Decimal.new("0")
              },
              attrs
            )
          )
        )
      end)

    tx
  end

  # A dollar fund with a euro and a franc account.
  defp third_currency_world! do
    world =
      WorldFixtures.base_world(name: "Muster", cash_name: "Test-Cash", depot_name: "Depot Muster")

    fund = WorldFixtures.create_security!(name: "Dollar Fund", ticker: "DFD", currency: "USD")

    swiss =
      Map.merge(
        world,
        WorldFixtures.add_depot(world.portfolio,
          cash_currency: "CHF",
          cash_name: "Franc Cash",
          depot_name: "Franc Depot"
        )
      )

    {world, swiss, fund}
  end

  # User story (#1198, Sprint 21 α3; the ADR-0015 amendment of 2026-10-09,
  # point 3, "a lot or a sell priced in a third currency"):
  # As the operator whose closed trade is unavailable because a booking is
  # priced in a currency that is neither its security's nor its account's,
  # I want the note and the cell's reason to say that, and the remedy to be
  # correcting that booking,
  # so that I am not told a buy in CHF has no figure in CHF, nor sent to a
  # rate backfill that cannot help.
  #
  # Acceptance criteria:
  # - A stored buy of 10 Dollar Fund at 90 CHF through the EUR account,
  #   sold at 100 CHF through the franc account: the note reads "1 trade
  #   not convertible: the buy of 2025-04-01 is priced in a currency that is
  #   neither the security's nor its account's (CHF); the trade's cost and
  #   result are missing, and it counts in no total. Remedy: correct the
  #   stored booking's currency or amounts."; the cells' title "Not
  #   convertible: a buy priced in CHF, neither the security's nor its
  #   account's currency"; no backfill named.
  # - A buy of 10 at 100 USD through the franc account and a stored sale at
  #   110 CHF through the EUR account: "1 trade not convertible: the sale of
  #   2025-05-02 is priced in a currency that is neither the security's nor
  #   its account's (CHF); … Remedy: correct the stored booking's currency
  #   or amounts."; the title "Not convertible: the sale is priced in CHF,
  #   neither the security's nor its account's currency".
  # - In German: "… Der Kauf vom 01.04.2025 ist in einer Währung bepreist,
  #   die weder die des Wertpapiers noch die seines Kontos ist (CHF); …
  #   Abhilfe: Währung oder Beträge der gespeicherten Buchung korrigieren."
  test "a lot priced in a third currency names the booking to correct, not a rate", %{
    conn: conn
  } do
    {world, swiss, fund} = third_currency_world!()

    stored_trade!(world, fund, %{
      type: "buy",
      date: ~D[2025-04-01],
      quantity: Decimal.new("10"),
      price: Decimal.new("90"),
      fees: Decimal.new("5"),
      currency_code: "CHF",
      security_amount: Decimal.new("1000"),
      settlement_amount: Decimal.new("800"),
      settlement_fx_rate: Decimal.new("0.888889"),
      gross_amount: Decimal.new("805")
    })

    {:ok, _sell} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: swiss.portfolio.id,
        securities_account_id: swiss.depot.id,
        cash_account_id: swiss.cash.id,
        security_id: fund.id,
        type: "sell",
        date: ~D[2025-05-02],
        quantity: "10",
        price: "100",
        fees: "3",
        taxes: "0",
        currency_code: "CHF",
        security_amount: "1250",
        settlement_amount: "1000",
        settlement_fx_rate: "0.8",
        gross_amount: "997"
      })

    {:ok, view, _html} = live(conn, "/securities/#{fund.id}?tab=trades")
    note = view |> element("[data-role=trades-unavailable]") |> render() |> text()

    assert note =~
             "1 trade not convertible: the buy of 2025-04-01 is priced in a currency that is neither the security's nor its account's (CHF); the trade's cost and result are missing, and it counts in no total. Remedy: correct the stored booking's currency or amounts."

    refute note =~ "backfill"

    row = view |> element("#detail-closed-trades-table tbody tr") |> render()

    for dash <- row |> Floki.parse_fragment!() |> Floki.find("td[data-role=trade-unconvertible]") do
      assert Floki.attribute(dash, "title") == [
               "Not convertible: a buy priced in CHF, neither the security's nor its account's currency"
             ]
    end

    {:ok, de_view, _html} = live(conn, "/securities/#{fund.id}?tab=trades&locale=de")
    de_note = de_view |> element("[data-role=trades-unavailable]") |> render() |> text()

    assert de_note =~
             "1 Trade ohne Umrechnung: Der Kauf vom 01.04.2025 ist in einer Währung bepreist, die weder die des Wertpapiers noch die seines Kontos ist (CHF); Einstand und Ergebnis des Trades fehlen, und er zählt in keiner Summe. Abhilfe: Währung oder Beträge der gespeicherten Buchung korrigieren."
  end

  # User story (#1198, Sprint 21 α3; point 3, the sale itself): as above,
  # for a sale priced in a currency that is neither the security's nor its
  # account's — its acceptance criteria the second item above.
  test "a sale priced in a third currency names the booking to correct, not a rate", %{
    conn: conn
  } do
    {world, swiss, fund} = third_currency_world!()

    WorldFixtures.cross_trade!(swiss, fund,
      type: "buy",
      quantity: "10",
      price: "100",
      settled: "900.00",
      fees: "2.00",
      gross: "902.00",
      date: ~D[2025-04-01]
    )

    stored_trade!(world, fund, %{
      type: "sell",
      date: ~D[2025-05-02],
      quantity: Decimal.new("10"),
      price: Decimal.new("110"),
      fees: Decimal.new("3"),
      currency_code: "CHF",
      security_amount: Decimal.new("1222.22"),
      settlement_amount: Decimal.new("1100.00"),
      settlement_fx_rate: Decimal.new("0.900000"),
      gross_amount: Decimal.new("1097.00")
    })

    {:ok, view, _html} = live(conn, "/securities/#{fund.id}?tab=trades")
    note = view |> element("[data-role=trades-unavailable]") |> render() |> text()

    assert note =~
             "1 trade not convertible: the sale of 2025-05-02 is priced in a currency that is neither the security's nor its account's (CHF); the trade's cost and result are missing, and it counts in no total. Remedy: correct the stored booking's currency or amounts."

    refute note =~ "backfill"

    row = view |> element("#detail-closed-trades-table tbody tr") |> render()

    for dash <- row |> Floki.parse_fragment!() |> Floki.find("td[data-role=trade-unconvertible]") do
      assert Floki.attribute(dash, "title") == [
               "Not convertible: the sale is priced in CHF, neither the security's nor its account's currency"
             ]
    end

    {:ok, de_view, _html} = live(conn, "/securities/#{fund.id}?tab=trades&locale=de")
    de_note = de_view |> element("[data-role=trades-unavailable]") |> render() |> text()

    assert de_note =~
             "1 Trade ohne Umrechnung: Der Verkauf vom 02.05.2025 ist in einer Währung bepreist, die weder die des Wertpapiers noch die seines Kontos ist (CHF); Einstand und Ergebnis des Trades fehlen, und er zählt in keiner Summe. Abhilfe: Währung oder Beträge der gespeicherten Buchung korrigieren."
  end

  # Legless buys of 5 Arbolia at 80.00 EUR on each of `dates` and one sale
  # of 10 at 120 USD, settled 960.00 EUR, that closes them.
  defp two_legless_lots!(dates) do
    world =
      WorldFixtures.base_world(name: "Muster", cash_name: "Test-Cash", depot_name: "Depot Muster")

    arbolia =
      WorldFixtures.create_security!(name: "Arbolia Inc.", ticker: "ARBL", currency: "USD")

    for date <- dates do
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

    arbolia
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
