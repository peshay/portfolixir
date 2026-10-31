defmodule PortfolixirWeb.CrossCurrencyLabelsTest do
  # #1213 (Sprint 21 α11; board 09 `09-money-states`, pick N9 variant A, and
  # board 03 `03-history-drawer`): each money figure of a cross-currency row
  # names its currency. Since the ADR-0015 amendment of 2026-10-07 a
  # booking's cash, fees and taxes are in its cash account's currency, its
  # price and quantity × price in the booking's.
  #
  # Every name, figure and date is synthetic.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [add_depot: 2, base_world: 1, create_security!: 1, cross_trade!: 3, deposit!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Ledger

  setup do
    world = base_world(name: "Labels", cash_name: "Test-Cash", depot_name: "Depot Muster")
    arbolia = create_security!(name: "Arbolia Inc.", ticker: "ARBL", currency: "USD")
    deposit = deposit!(world, "5000", ~D[2026-08-01])
    %{world: world, arbolia: arbolia, deposit: deposit}
  end

  defp book!(attrs) do
    {:ok, tx} = Ledger.create_transaction(Actor.owner_ui(), attrs)
    tx
  end

  defp cells(row), do: row |> Floki.find("td") |> Enum.map(&text/1)

  defp text(node),
    do: node |> Floki.text(sep: " ") |> String.replace(~r/\s+/u, " ") |> String.trim()

  # User story (#1213, Sprint 21 α11; N9 variant A):
  # As the operator reading a USD security's Transaktionen tab bought
  # through a EUR account,
  # I want the fees, taxes and gross of a cross-currency row to name their
  # currencies, and a same-currency row to stay as it is,
  # so that I do not read euro fees and a dollar gross as both dollars
  # beside a price labelled USD.
  #
  # Acceptance criteria:
  # - The cross-currency buy (10 × 100,00 USD settled 800,00 EUR, fees 5,00
  #   and taxes 1,00 EUR) reads Gebühren "5,00 EUR", Steuern "1,00 EUR" and
  #   Brutto "1.000,00 USD".
  # - The buy booked in its account's currency (Portfolio Performance's
  #   form: 2 × 80,00 EUR, fees 1,50) stays bare: "1,50", "0,00", "160,00".
  # - A USD dividend credited 80,00 EUR with 12,00 EUR withheld names the
  #   account's currency on its fee, taxes and stored cash ("0,00 EUR",
  #   "12,00 EUR", "80,00 EUR").
  test "a cross-currency row's fees, taxes and gross name their currencies, only there",
       %{conn: conn, world: world, arbolia: arbolia} do
    cross_trade!(world, arbolia,
      quantity: "10",
      price: "100",
      settled: "800.00",
      fees: "5.00",
      taxes: "1.00",
      gross: "806.00",
      date: ~D[2026-08-12]
    )

    book!(%{
      portfolio_id: world.portfolio.id,
      securities_account_id: world.depot.id,
      cash_account_id: world.cash.id,
      security_id: arbolia.id,
      type: "buy",
      date: ~D[2026-08-10],
      quantity: "2",
      price: "80",
      fees: "1.50",
      taxes: "0",
      currency_code: "EUR"
    })

    book!(%{
      portfolio_id: world.portfolio.id,
      cash_account_id: world.cash.id,
      security_id: arbolia.id,
      type: "dividend",
      date: ~D[2026-08-20],
      gross_amount: "80.00",
      taxes: "12.00",
      settlement_fx_rate: "0.8",
      currency_code: "USD"
    })

    {:ok, view, _html} = live(conn, "/securities/#{arbolia.id}?tab=transactions&locale=de")

    [dividend, cross, same] =
      view
      |> element("#detail-tab-panel-transactions")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.find("tbody tr")

    # Datum · Typ · Stückzahl · Preis · Gebühren · Steuern · Brutto · Depot · Notizen
    assert Enum.slice(cells(cross), 3..6) == [
             "100,00 USD",
             "5,00 EUR",
             "1,00 EUR",
             "1.000,00 USD"
           ]

    assert Enum.slice(cells(same), 3..6) == ["80,00 EUR", "1,50", "0,00", "160,00"]
    assert Enum.slice(cells(dividend), 4..6) == ["0,00 EUR", "12,00 EUR", "80,00 EUR"]
  end

  # User story (#1213, Sprint 21 α11; N9 variant A):
  # As the operator reading a USD security's Transaktionen tab,
  # I want a cross-currency row's missing figure to read as a bare dash,
  # so that a currency never labels a figure that is not there.
  #
  # Acceptance criteria:
  # - An inbound delivery of 3 shares booked in USD against the EUR account
  #   "Test-Cash" (rate 0,8), with no price and no gross amount, reads
  #   Brutto "—" with no currency beside it, while its fees and taxes still
  #   read "0,00 EUR". (Fees and taxes are NOT NULL columns, so the gross is
  #   the one figure a stored cross-currency row can lack.)
  test "a cross-currency row's missing gross reads a bare dash",
       %{conn: conn, world: world, arbolia: arbolia} do
    book!(%{
      portfolio_id: world.portfolio.id,
      securities_account_id: world.depot.id,
      cash_account_id: world.cash.id,
      security_id: arbolia.id,
      type: "inbound_delivery",
      date: ~D[2026-08-15],
      quantity: "3",
      settlement_fx_rate: "0.8",
      currency_code: "USD"
    })

    {:ok, view, _html} = live(conn, "/securities/#{arbolia.id}?tab=transactions&locale=de")

    [delivery] =
      view
      |> element("#detail-tab-panel-transactions")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.find("tbody tr")

    # Datum · Typ · Stückzahl · Preis · Gebühren · Steuern · Brutto · Depot · Notizen
    assert Enum.slice(cells(delivery), 4..6) == ["0,00 EUR", "0,00 EUR", "—"]
  end

  # User story (#1213, Sprint 21 α11; N9 variant A, the issue's comment of
  # 2026-10-09):
  # As the operator reading a security's closed trades on a desktop,
  # I want the result cell to name the trade's currency, as the phone row
  # already does,
  # so that two trades of one security in two currencies cannot be read in
  # one.
  #
  # Acceptance criteria:
  # - A USD trade through a USD account (10 bought at 100,00, sold at
  #   120,00) reads Realisierter G/V "+200,00 USD" in the table; Ø Kauf and
  #   Ø Verkauf stay bare ("100,00", "120,00").
  test "the Trades tab's result cell names the trade's currency at every width",
       %{conn: conn, world: world, arbolia: arbolia} do
    usd =
      add_depot(world.portfolio, cash_name: "US Broker", depot_name: "Depot USD", currency: "USD")

    trade = fn type, date, price ->
      book!(%{
        portfolio_id: world.portfolio.id,
        securities_account_id: usd.depot.id,
        cash_account_id: usd.cash.id,
        security_id: arbolia.id,
        type: type,
        date: date,
        quantity: "10",
        price: price,
        fees: "0",
        taxes: "0",
        currency_code: "USD"
      })
    end

    trade.("buy", ~D[2026-02-02], "100")
    trade.("sell", ~D[2026-08-14], "120")

    {:ok, view, _html} = live(conn, "/securities/#{arbolia.id}?tab=trades&locale=de")

    [row] =
      view
      |> element("#detail-closed-trades-table")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.find("tbody tr")

    # Eröffnet · Geschlossen · Stückzahl · Ø Kauf · Ø Verkauf · Tage · p. a. · G/V · %
    row_cells = cells(row)
    assert Enum.slice(row_cells, 3..4) == ["100,00", "120,00"]
    assert Enum.at(row_cells, 7) == "+200,00 USD"
  end

  # User story (#1213, Sprint 21 α11; board 03, the drawer's half):
  # As the operator opening a dividend of a USD security that was credited
  # in euros to a EUR account,
  # I want the drawer to label its amount and its taxes with the account's
  # currency, as the history row does,
  # so that "80,00" does not read as dollars.
  #
  # Acceptance criteria:
  # - The notes-only drawer reads "Betrag (EUR)" with 80,00 and "Steuern
  #   (EUR)" with 12,00, never "Betrag (USD)".
  # - A deposit booked in its account's currency keeps "Betrag (EUR)".
  test "the drawer labels a cash kind's amount and taxes with the account's currency",
       %{conn: conn, world: world, arbolia: arbolia, deposit: deposit} do
    dividend =
      book!(%{
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        security_id: arbolia.id,
        type: "dividend",
        date: ~D[2026-08-20],
        gross_amount: "80.00",
        taxes: "12.00",
        settlement_fx_rate: "0.8",
        currency_code: "USD"
      })

    open_edit = fn tx ->
      {:ok, view, _html} = live(conn, "/transactions?locale=de")
      view |> element("#tx-kebab-#{tx.id}") |> render_click()
      view |> element("#tx-edit-#{tx.id}") |> render_click()

      # A cash kind stored in its account's currency opens the editable cash
      # form (#1052, α6); one stored in another currency keeps the notes-only
      # facts. Both label the amount in the account's currency.
      selector =
        if has_element?(view, "#booking-facts"), do: "#booking-facts", else: "#transaction-form"

      facts = view |> element(selector) |> render() |> Floki.parse_fragment!()
      {view, text(facts)}
    end

    {view, facts} = open_edit.(dividend)

    assert facts =~ "Betrag (EUR)"
    assert facts =~ "Steuern (EUR)"
    refute facts =~ "USD"
    assert has_element?(view, "#booking-facts input[name='note[gross_amount]'][value='80,00']")
    assert has_element?(view, "#booking-facts input[name='note[taxes]'][value='12,00']")

    {_view, facts} = open_edit.(deposit)
    assert facts =~ "Betrag (EUR)"
  end
end
