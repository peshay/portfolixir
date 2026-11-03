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
  #   gebucht …" and "„Historische Wechselkurse nachladen“ unter Cashflow →
  #   „Trades“" (the button's label since #1150).
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
             "Abhilfe: ein Wechselkurs für den 12.02.2025 — „Historische Wechselkurse nachladen“ unter Cashflow → „Trades“ speichert ihn und leitet daraus den Gegenwert ab — oder der Gegenwert in USD an der Buchung."

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
  # - One day is one rate (the closing act): "Remedy: a rate for that date
  #   — … stores it and derives the figures from it — …", never "for each
  #   of those dates"; in German "ein Wechselkurs für diesen Tag".
  test "two lots of one day name their day once", %{conn: conn} do
    arbolia = two_legless_lots!([~D[2025-04-01], ~D[2025-04-01]])

    {:ok, view, _html} = live(conn, "/securities/#{arbolia.id}?tab=trades")
    note = view |> element("[data-role=trades-unavailable]") |> render() |> text()

    assert note =~
             "1 trade not convertible: 2 buys it closes, of 2025-04-01, have no figure in USD, the sale's currency"

    assert note =~
             "Remedy: a rate for that date — “Backfill historical rates” on Cash flow → “Trades” stores it and derives the figures from it — or the figures in USD on the bookings."

    refute note =~ "each of those dates"

    {:ok, de_view, _html} = live(conn, "/securities/#{arbolia.id}?tab=trades&locale=de")
    de_note = de_view |> element("[data-role=trades-unavailable]") |> render() |> text()

    assert de_note =~
             "1 Trade ohne Umrechnung: 2 Käufe, die er schließt, vom 01.04.2025, haben keinen Gegenwert in USD"

    assert de_note =~ "Abhilfe: ein Wechselkurs für diesen Tag"
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
  #   on its close date: the facet, two reasons, names each reason's sales
  #   (Sprint 23 Lane I, Income ⑧): "Buy without a figure in the sale's
  #   currency: Arbolia Inc." and "No stored rate: Kestrel Inc."; the
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
             ~r/^\s*Buy without a figure in the sale's currency: Arbolia Inc\.\s*$/

    assert view |> element("[data-role=realized-excluded-no-rate]") |> render() |> text() =~
             ~r/^\s*No stored rate: Kestrel Inc\.\s*$/

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

  # User story (#1208, Sprint 21 γ1; board 01 ⑥): As the operator reading
  # the Overview card's and the Trades facet's exclusion notes in German, I
  # want a name that ends in a full stop to end each sentence once, the
  # sentence going on where it goes on, so that no note reads "Inc..".
  #
  # Acceptance criteria:
  # - The card: "1 Verkauf ohne gespeicherten Wechselkurs an seinem
  #   Schlussdatum fehlt bei den Trades: Kestrel Inc. Das Nachladen der
  #   Wechselkurse steht unter „Alle Trades“." and "1 Verkauf ohne Umrechnung
  #   — … — fehlt bei den Trades: Arbolia Inc."
  # - The facet, two reasons (Sprint 23 Lane I, Income ⑧): "Ohne
  #   gespeicherten Wechselkurs: Kestrel Inc." and "Kauf ohne Gegenwert in
  #   der Währung des Verkaufs: Arbolia Inc."
  # - Each sentence takes the msgid without the stop (one shared helper,
  #   `StoredText.ending_on/3`), so no note holds "Inc..".
  test "in German too, a name ending in a full stop ends each note's sentence once",
       %{conn: conn} do
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

    {:ok, view, _html} = live(conn, "/cashflow?tab=realized&locale=de")
    render_async(view)

    assert view |> element("[data-role=realized-excluded-no-rate]") |> render() |> text() =~
             ~r/^\s*Ohne gespeicherten Wechselkurs: Kestrel Inc\.\s*$/

    assert view |> element("[data-role=realized-excluded-missing-leg]") |> render() |> text() =~
             ~r/^\s*Kauf ohne Gegenwert in der Währung des Verkaufs: Arbolia Inc\.\s*$/

    {:ok, card, _html} = live(conn, "/?locale=de")
    render_async(card)

    no_rate =
      card |> element("[data-role='trades-card-excluded-no-rate']") |> render() |> text()

    assert String.trim(no_rate) ==
             "1 Verkauf ohne gespeicherten Wechselkurs an seinem Schlussdatum fehlt bei den " <>
               "Trades: Kestrel Inc. Das Nachladen der Wechselkurse steht unter „Alle Trades“."

    missing_leg =
      card |> element("[data-role='trades-card-excluded-missing-leg']") |> render() |> text()

    assert String.trim(missing_leg) ==
             "1 Verkauf ohne Umrechnung — ein Kauf, den er schließt, hat keinen Gegenwert in " <>
               "der Währung des Verkaufs — fehlt bei den Trades: Arbolia Inc."

    refute no_rate =~ "Inc.."
    refute missing_leg =~ "Inc.."
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

  # User story (#1310, Sprint 22 R5; the ADR-0015 amendment of 2026-10-09,
  # point 3):
  # As the operator whose dollar sale closes a buy stored at a franc price
  # through my euro account,
  # I want the note to name the franc buy as the booking to correct, read off
  # the trade's own reason,
  # so that I am not sent to a rate backfill because the sale is in another
  # currency than the buy.
  #
  # Acceptance criteria:
  # - A stored buy of 10 Dollar Fund at 90 CHF through the EUR account,
  #   sold by hand at 120 USD (settled 960.00 EUR, fee 3.00 EUR): the note
  #   reads "1 trade not convertible: the buy of 2025-04-01 is priced in a
  #   currency that is neither the security's nor its account's (CHF); …
  #   Remedy: correct the stored booking's currency or amounts."; the cells'
  #   title "Not convertible: a buy priced in CHF, neither the security's nor
  #   its account's currency"; no backfill named. Before: "the buy of
  #   2025-04-01 is booked in CHF and has no figure in USD … Remedy: a rate
  #   for 2025-04-01".
  test "a franc lot sold in dollars names the booking to correct, not a rate", %{conn: conn} do
    {world, _swiss, fund} = third_currency_world!()

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

    WorldFixtures.cross_trade!(world, fund,
      type: "sell",
      quantity: "10",
      price: "120",
      settled: "960.00",
      fees: "3.00",
      gross: "957.00",
      date: ~D[2025-05-02]
    )

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
  end

  # User story (#1310, the closing act):
  # As the operator whose sale closes a buy without its leg and a buy
  # priced in a third currency,
  # I want the note to name both buys, each with its own remedy,
  # so that correcting the franc booking is not the end of it.
  #
  # Acceptance criteria:
  # - A legless buy of 5 Dollar Fund at 80.00 EUR on 2025-03-03 and a stored
  #   buy of 5 at 90 CHF on 2025-04-01, both through the EUR account, sold
  #   by hand at 120 USD: the note names the franc buy as the booking to
  #   correct, then "Beside it, the buy of 2025-03-03 has no figure in USD,
  #   the sale's currency. Remedy: a rate for 2025-03-03 — “Backfill
  #   historical rates” on Cash flow → “Trades” stores it and derives the
  #   figure from it — or the figure in USD on the booking."; in German
  #   "Daneben hat der Kauf vom 03.03.2025 keinen Gegenwert in USD".
  test "a trade with a legless and a third-currency lot names both", %{conn: conn} do
    {world, _swiss, fund} = third_currency_world!()

    {:ok, _legless} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        cash_account_id: world.cash.id,
        security_id: fund.id,
        type: "buy",
        date: ~D[2025-03-03],
        quantity: "5",
        price: "80",
        currency_code: "EUR",
        gross_amount: "400"
      })

    stored_trade!(world, fund, %{
      type: "buy",
      date: ~D[2025-04-01],
      quantity: Decimal.new("5"),
      price: Decimal.new("90"),
      fees: Decimal.new("5"),
      currency_code: "CHF",
      security_amount: Decimal.new("500"),
      settlement_amount: Decimal.new("400"),
      settlement_fx_rate: Decimal.new("0.888889"),
      gross_amount: Decimal.new("405")
    })

    WorldFixtures.cross_trade!(world, fund,
      type: "sell",
      quantity: "10",
      price: "120",
      settled: "960.00",
      fees: "3.00",
      gross: "957.00",
      date: ~D[2025-05-02]
    )

    {:ok, view, _html} = live(conn, "/securities/#{fund.id}?tab=trades")
    note = view |> element("[data-role=trades-unavailable]") |> render() |> text()

    assert note =~
             "1 trade not convertible: the buy of 2025-04-01 is priced in a currency that is neither the security's nor its account's (CHF)"

    assert note =~
             "Beside it, the buy of 2025-03-03 has no figure in USD, the sale's currency. Remedy: a rate for 2025-03-03 — “Backfill historical rates” on Cash flow → “Trades” stores it and derives the figure from it — or the figure in USD on the booking."

    {:ok, de_view, _html} = live(conn, "/securities/#{fund.id}?tab=trades&locale=de")
    de_note = de_view |> element("[data-role=trades-unavailable]") |> render() |> text()

    assert de_note =~ "Daneben hat der Kauf vom 03.03.2025 keinen Gegenwert in USD"
  end

  # User story (#1310 and #1311, Sprint 22 R5):
  # As the operator whose closed trade is unavailable for a cause no rate
  # fixes, a buy paid through an account in another currency than the
  # sale's, or a buy of zero amount the rate backfill does not complete,
  # I want the note to name that buy and the remedy that fits,
  # so that I am not sent to a rate backfill that changes nothing.
  #
  # Acceptance criteria:
  # - A buy of 10 Dollar Fund at 100 USD through a dollar account, sold by
  #   import at 96.00 EUR through the euro account (legs 960.00 EUR,
  #   1,200.00 USD, 0.800000): "1 trade not convertible: the buy of
  #   2025-04-01 was paid in another currency than the sale's (EUR), and
  #   none of its stored figures can be in EUR; the trade's cost and result
  #   are missing, and it counts in no total. Remedy: correct the stored
  #   bookings' currency or amounts."; the cells' title "Not convertible: a
  #   buy paid in another currency than EUR, the sale's"; no backfill named.
  # - A free allotment, an import-form buy of 5 at 0.00 EUR without legs,
  #   sold by hand at 120 USD (settled 480.00 EUR): "1 trade not convertible:
  #   the buy of 2025-04-01 has an amount of zero and no figure in USD, the
  #   sale's currency, which the rate backfill does not complete; the
  #   trade's cost and result are missing, and it counts in no total.
  #   Remedy: enter the buy's figures in USD on the booking by hand."; the
  #   title "Not convertible: a buy of zero amount has no figure in USD";
  #   no backfill named. In German "… Abhilfe: die Beträge des Kaufs in USD
  #   von Hand auf der Buchung erfassen.".
  # Before: both read "… has no figure in … Remedy: a rate for 2025-04-01 —
  # “Backfill historical rates” …".
  test "a buy paid in another currency, or of zero amount, names a remedy no rate is", %{
    conn: conn
  } do
    {world, _swiss, fund} = third_currency_world!()
    dollar = Map.merge(world, WorldFixtures.add_depot(world.portfolio, cash_currency: "USD"))

    WorldFixtures.buy!(dollar, fund,
      quantity: "10",
      price: "100",
      currency: "USD",
      date: ~D[2025-04-01]
    )

    {:ok, _sale} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        cash_account_id: world.cash.id,
        security_id: fund.id,
        type: "sell",
        date: ~D[2025-05-02],
        quantity: "10",
        price: "96",
        fees: "0",
        taxes: "0",
        currency_code: "EUR",
        security_amount: "1200",
        settlement_amount: "960",
        settlement_fx_rate: "0.8",
        gross_amount: "960"
      })

    {:ok, view, _html} = live(conn, "/securities/#{fund.id}?tab=trades")
    note = view |> element("[data-role=trades-unavailable]") |> render() |> text()

    assert note =~
             "1 trade not convertible: the buy of 2025-04-01 was paid in another currency than the sale's (EUR), and none of its stored figures can be in EUR; the trade's cost and result are missing, and it counts in no total. Remedy: correct the stored bookings' currency or amounts."

    refute note =~ "backfill"

    row = view |> element("#detail-closed-trades-table tbody tr") |> render()

    for dash <- row |> Floki.parse_fragment!() |> Floki.find("td[data-role=trade-unconvertible]") do
      assert Floki.attribute(dash, "title") == [
               "Not convertible: a buy paid in another currency than EUR, the sale's"
             ]
    end

    allotted =
      WorldFixtures.create_security!(name: "Allotted Fund", ticker: "ALF", currency: "USD")

    {:ok, _allotment} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        cash_account_id: world.cash.id,
        security_id: allotted.id,
        type: "buy",
        date: ~D[2025-04-01],
        quantity: "5",
        price: "0",
        currency_code: "EUR"
      })

    WorldFixtures.cross_trade!(world, allotted,
      type: "sell",
      quantity: "5",
      price: "120",
      settled: "480.00",
      gross: "480.00",
      date: ~D[2025-05-02]
    )

    {:ok, view, _html} = live(conn, "/securities/#{allotted.id}?tab=trades")
    note = view |> element("[data-role=trades-unavailable]") |> render() |> text()

    assert note =~
             "1 trade not convertible: the buy of 2025-04-01 has an amount of zero and no figure in USD, the sale's currency, which the rate backfill does not complete; the trade's cost and result are missing, and it counts in no total. Remedy: enter the buy's figures in USD on the booking by hand."

    refute note =~ "backfill historical"
    refute note =~ "Backfill"

    row = view |> element("#detail-closed-trades-table tbody tr") |> render()

    for dash <- row |> Floki.parse_fragment!() |> Floki.find("td[data-role=trade-unconvertible]") do
      assert Floki.attribute(dash, "title") == [
               "Not convertible: a buy of zero amount has no figure in USD"
             ]
    end

    {:ok, de_view, _html} = live(conn, "/securities/#{allotted.id}?tab=trades&locale=de")
    de_note = de_view |> element("[data-role=trades-unavailable]") |> render() |> text()

    assert de_note =~
             "Abhilfe: die Beträge des Kaufs in USD von Hand auf der Buchung erfassen."
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
  # - The backfill control beside it says it "stores every published day
  #   and derives from it the settlement legs imported buys and sells lack"
  #   (board 09's strings, last row); in German "… und leitet daraus die
  #   Gegenwerte ab, die importierten Käufen und Verkäufen fehlen; …".
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

    # Board 09's strings, last row (#1196, ADR-0015 point 6): the control
    # beside the note says it also derives the legs the trade lacks, as the
    # Trades tab's remedy says it does. Since I1 (#1351) that reason reads in
    # the note's text and the button sits in its actions.
    assert view
           |> element("#realized-excluded [data-role=fx-backfill-reason]")
           |> render()
           |> text() =~
             "The daily rate sync cannot fill a past date. The backfill fetches the historical ECB series once, stores every published day and derives from it the settlement legs imported buys and sells lack; a day the ECB did not publish stays excluded."

    {:ok, de_view, _html} = live(conn, "/cashflow?tab=realized&locale=de")
    render_async(de_view)

    assert de_view
           |> element("#realized-excluded [data-role=fx-backfill-reason]")
           |> render()
           |> text() =~
             "Das Nachladen holt die historische EZB-Reihe einmalig, speichert jeden veröffentlichten Tag und leitet daraus die Gegenwerte ab, die importierten Käufen und Verkäufen fehlen; ein Tag, den die EZB nicht veröffentlicht hat, bleibt ausgeschlossen."

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

  # User story (#1310, Sprint 22 R5; the aggregates):
  # As the operator reading the Trades facet and the Overview card,
  # I want a sale left out because it or a buy it closes is priced in a
  # third currency named in a sentence of its own,
  # so that I am not told a buy lacks a figure a rate would give it.
  #
  # Acceptance criteria:
  # - A buy of 10 Dollar Fund at 100 USD through the franc account and a
  #   stored sale at 110 CHF through the euro account: the facet's note says
  #   "1 sale is not convertible — it or a buy it closes is priced in a
  #   currency that is neither the security's nor its account's — and is
  #   excluded from every total: Dollar Fund." and no missing-leg sentence;
  #   in German "1 Verkauf ist ohne Umrechnung — er oder ein Kauf, den er
  #   schließt, ist weder in der Währung des Wertpapiers noch in der seines
  #   Kontos bepreist — und aus jeder Summe ausgeschlossen: Dollar Fund.".
  # - The card's note says "1 sale not convertible — it or a buy it closes
  #   is priced in a currency that is neither the security's nor its
  #   account's — is left out of the trades: Dollar Fund." with no backfill
  #   pointer. Before: both notes empty of any sentence, the trade counted in
  #   excluded.count alone.
  test "the facet and the card name a third-currency sale apart", %{conn: conn} do
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

    {:ok, view, _html} = live(conn, "/cashflow?tab=realized")
    render_async(view)

    note = view |> element("#realized-excluded") |> render() |> text()

    assert note =~
             "1 sale is not convertible — it or a buy it closes is priced in a currency that is neither the security's nor its account's — and is excluded from every total: Dollar Fund."

    refute has_element?(view, "[data-role=realized-excluded-missing-leg]")

    {:ok, de_view, _html} = live(conn, "/cashflow?tab=realized&locale=de")
    render_async(de_view)

    assert de_view |> element("#realized-excluded") |> render() |> text() =~
             "1 Verkauf ist ohne Umrechnung — er oder ein Kauf, den er schließt, ist weder in der Währung des Wertpapiers noch in der seines Kontos bepreist — und aus jeder Summe ausgeschlossen: Dollar Fund."

    {:ok, card, _html} = live(conn, "/")
    render_async(card)

    card_note =
      card
      |> element("#dashboard-trades [data-role='trades-card-excluded']")
      |> render()
      |> text()

    assert card_note =~
             "1 sale not convertible — it or a buy it closes is priced in a currency that is neither the security's nor its account's — is left out of the trades: Dollar Fund."

    refute card_note =~ "backfill"
  end

  # User story (#1310 and #1311, Sprint 22 R5; the aggregates):
  # As the operator reading the Trades facet and the Overview card,
  # I want a sale left out because a buy it closes was paid in a currency no
  # leg bridges, or has an amount of zero, named in a sentence of its own,
  # so that I am not pointed to a rate backfill that changes nothing.
  #
  # Acceptance criteria:
  # - A dollar-account buy sold through the euro account (Dollar Fund) and a
  #   free allotment sold by hand (Allotted Fund): the facet's note, two
  #   reasons, names each reason's sales (Sprint 23 Lane I, Income ⑧): "Buy
  #   paid in another currency: Dollar Fund." and "Buy of amount zero:
  #   Allotted Fund.", and no missing-leg sentence; the card says both with
  #   "is left out of the trades", and no backfill pointer.
  test "the facet and the card name a bridgeless and a zero-amount sale apart", %{conn: conn} do
    {world, _swiss, fund} = third_currency_world!()
    dollar = Map.merge(world, WorldFixtures.add_depot(world.portfolio, cash_currency: "USD"))

    WorldFixtures.buy!(dollar, fund,
      quantity: "10",
      price: "100",
      currency: "USD",
      date: ~D[2025-04-01]
    )

    {:ok, _sale} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        cash_account_id: world.cash.id,
        security_id: fund.id,
        type: "sell",
        date: ~D[2025-05-02],
        quantity: "10",
        price: "96",
        currency_code: "EUR",
        security_amount: "1200",
        settlement_amount: "960",
        settlement_fx_rate: "0.8",
        gross_amount: "960"
      })

    allotted =
      WorldFixtures.create_security!(name: "Allotted Fund", ticker: "ALF", currency: "USD")

    {:ok, _allotment} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        cash_account_id: world.cash.id,
        security_id: allotted.id,
        type: "buy",
        date: ~D[2025-04-01],
        quantity: "5",
        price: "0",
        currency_code: "EUR"
      })

    WorldFixtures.cross_trade!(world, allotted,
      type: "sell",
      quantity: "5",
      price: "120",
      settled: "480.00",
      gross: "480.00",
      date: ~D[2025-05-02]
    )

    {:ok, view, _html} = live(conn, "/cashflow?tab=realized")
    render_async(view)
    note = view |> element("#realized-excluded") |> render() |> text()

    assert note =~ "Buy paid in another currency: Dollar Fund."
    assert note =~ "Buy of amount zero: Allotted Fund."

    refute has_element?(view, "[data-role=realized-excluded-missing-leg]")

    {:ok, card, _html} = live(conn, "/")
    render_async(card)

    card_note =
      card
      |> element("#dashboard-trades [data-role='trades-card-excluded']")
      |> render()
      |> text()

    assert card_note =~
             "1 sale not convertible — a buy it closes was paid in another currency than the sale's, which no stored figure bridges — is left out of the trades: Dollar Fund."

    assert card_note =~
             "1 sale not convertible — a buy it closes has an amount of zero, which the rate backfill does not complete — is left out of the trades: Allotted Fund."

    refute card_note =~ "backfill is under"
  end

  # User story (#1351 closing act, pick Q1; DESIGN.md ③ "every count"):
  # As the operator reading a clamped note that names sales left out for
  # more than one reason, on a phone,
  # I want every reason's count in the note's first line,
  # so that no excluded sale hides behind "more".
  #
  # Acceptance criteria:
  # - With a sale with no stored rate (Kestrel Inc.) and one whose buy has no
  #   figure in its currency (Arbolia Inc.), the facet's note opens with
  #   "Excluded from every total: 1 sale with no stored rate; 1 sale whose
  #   buy has no figure in its currency.", the card's with "Left out of the
  #   trades: …", each the first element of the note's text, before the
  #   reason sentences; in German "Aus jeder Summe ausgeschlossen: 1 Verkauf
  #   ohne gespeicherten Wechselkurs; 1 Verkauf, dessen Kauf keinen
  #   Gegenwert in seiner Währung hat." and "Fehlt bei den Trades: …".
  # - With one reason only, no count line: the reason sentence leads.
  test "a note with two reasons leads with every reason's count", %{conn: conn} do
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

    counts = "1 sale with no stored rate; 1 sale whose buy has no figure in its currency."

    de_counts =
      "1 Verkauf ohne gespeicherten Wechselkurs; " <>
        "1 Verkauf, dessen Kauf keinen Gegenwert in seiner Währung hat."

    for {locale, lead, card_lead, all} <- [
          {"en", "Excluded from every total: ", "Left out of the trades: ", counts},
          {"de", "Aus jeder Summe ausgeschlossen: ", "Fehlt bei den Trades: ", de_counts}
        ] do
      {:ok, view, _html} = live(conn, "/cashflow?tab=realized&locale=#{locale}")
      render_async(view)

      first =
        "#realized-excluded .data-note__text > :first-child[data-role=realized-excluded-counts]"

      assert String.trim(view |> element(first) |> render() |> text()) == lead <> all

      {:ok, card, _html} = live(conn, "/?locale=#{locale}")
      render_async(card)

      first =
        "#trades-card-excluded .data-note__text > :first-child[data-role=trades-card-excluded-counts]"

      assert String.trim(card |> element(first) |> render() |> text()) == card_lead <> all
    end
  end

  test "a note with one reason has no count line", %{conn: conn} do
    seed!()

    {:ok, view, _html} = live(conn, "/cashflow?tab=realized")
    render_async(view)
    assert has_element?(view, "#realized-excluded [data-role=realized-excluded-missing-leg]")
    refute has_element?(view, "[data-role=realized-excluded-counts]")

    {:ok, card, _html} = live(conn, "/")
    render_async(card)
    assert has_element?(card, "#trades-card-excluded")
    refute has_element?(card, "[data-role=trades-card-excluded-counts]")
  end
end
