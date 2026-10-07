defmodule PortfolixirWeb.TransactionHistoryU1LiveTest do
  # Sprint 19 PR γ U1 (plan D-4; board `ux-design-2026-10-04/03-history`,
  # picks J3 = A and J3.2 = A; design Part 3): the transaction history's
  # month head, the account on a desktop row, the phone row's long name, the
  # price's stored digits, and this page's subtitle (#1083, #1084, #1073,
  # #1090's history item), plus the board's "found while drawing" item 1 —
  # a cash transfer reads from the side of the account in view.
  #
  # Every name, figure and date is synthetic.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Splits
  alias Portfolixir.WorldFixtures

  defp text(nodes),
    do: nodes |> Floki.text(sep: " ") |> String.replace(~r/\s+/, " ") |> String.trim()

  defp document(view), do: view |> render() |> Floki.parse_document!()

  defp book!(attrs) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), Map.put_new(attrs, :currency_code, "EUR"))

    tx
  end

  # The board's September, in the seed's shape: a set balance on a USD
  # account and a sale through it, two buys, a dividend and a deposit on the
  # EUR account — six bookings. The sale's shares were bought in August.
  defp september do
    world =
      WorldFixtures.base_world(name: "Demo", cash_name: "Demo Cash", depot_name: "Depot 1")

    usd =
      WorldFixtures.add_depot(world.portfolio,
        cash_currency: "USD",
        cash_name: "USD Settlement",
        depot_name: "US Depot"
      )

    kestrel = WorldFixtures.create_security!(name: "Kestrel Industrial Group NV", ticker: "KIG")
    alpine = WorldFixtures.create_security!(name: "Alpine Test Werke AG", ticker: "ATW")
    nordwind = WorldFixtures.create_security!(name: "Nordwind Industrie AG", ticker: "NWI")

    harbor =
      WorldFixtures.create_security!(
        name: "Harborline Systems Inc",
        ticker: "HBL",
        currency: "USD"
      )

    us_world = Map.put(usd, :portfolio, world.portfolio)

    WorldFixtures.buy!(us_world, harbor,
      quantity: "10",
      price: "80",
      date: ~D[2026-08-18],
      currency: "USD"
    )

    sale =
      WorldFixtures.sell!(us_world, harbor,
        quantity: "4",
        price: "90",
        date: ~D[2026-09-22],
        currency: "USD"
      )

    deposit = WorldFixtures.deposit!(world, "1500", ~D[2026-09-21])

    alpine_buy =
      WorldFixtures.buy!(world, alpine, quantity: "20", price: "48.245", date: ~D[2026-09-23])

    book!(%{
      type: "dividend",
      portfolio_id: world.portfolio.id,
      cash_account_id: world.cash.id,
      security_id: nordwind.id,
      gross_amount: "12.50",
      date: ~D[2026-09-24]
    })

    kestrel_buy =
      WorldFixtures.buy!(world, kestrel, quantity: "10", price: "24", date: ~D[2026-09-30])

    {:ok, _anchor} =
      Ledger.set_cash_balance(Actor.owner_ui(), usd.cash, %{date: ~D[2026-09-30], amount: "1850"})

    %{
      world: world,
      usd: usd,
      deposit: deposit,
      sale: sale,
      alpine_buy: alpine_buy,
      kestrel_buy: kestrel_buy
    }
  end

  # User story (#1083, pick J3 = A):
  # As the operator reading my history month by month,
  # I want each month head to carry the count of its bookings and nothing
  # else,
  # so that no figure there adds buys, deposits, sales and a set balance into
  # a sum that is neither a cash flow nor a turnover.
  #
  # Acceptance criteria:
  # - The table's month head and the phone list's month head read the month
  #   and "%{count} Transaktionen", with no amount and no currency code.
  # - The filter summary above keeps its per-kind, per-currency sums and its
  #   basis line.
  # - Deleting a booking: the head's count follows (H2, "the month subtotal
  #   follows").
  test "the month head carries the count alone, at both widths", %{conn: conn} do
    %{deposit: deposit} = september()

    {:ok, view, _html} = live(conn, "/transactions?locale=de")
    doc = document(view)

    [table_head] =
      Floki.find(doc, "#transaction-list tr.tx-group-head[data-month-group='2026-09']")

    assert text(table_head) == "September 2026 6 Transaktionen"
    assert Floki.find(table_head, ".currency-total") == []

    [phone_head] =
      Floki.find(doc, "#transaction-phone-rows li.phone-rows__group[data-month-group='2026-09']")

    assert text(phone_head) == "September 2026 6 Transaktionen"
    assert Floki.find(phone_head, ".currency-total") == []

    # The sums stay where their basis line explains them.
    summary = text(Floki.find(doc, "#transaction-summary"))
    assert summary =~ "1.850,00 USD"
    assert summary =~ "360,00 USD"
    assert summary =~ "1.500,00 EUR"
    assert has_element?(view, "#transaction-summary [data-role='summary-basis']")

    # The count follows a deleted row.
    view |> element("#tx-kebab-#{deposit.id}") |> render_click()
    view |> element("#tx-delete-#{deposit.id}") |> render_click()
    view |> element("#booking-delete-confirm") |> render_click()

    head = view |> element("#transaction-list tr.tx-group-head[data-month-group='2026-09']")

    assert head |> render() |> Floki.parse_fragment!() |> text() ==
             "September 2026 5 Transaktionen"
  end

  # User story (#1083, the singular):
  # As the operator who deleted one of a month's two bookings,
  # I want the month head to count the one left in the singular,
  # so that the head reads "1 Transaktion", not "1 Transaktionen".
  #
  # Acceptance criteria:
  # - After the delete, the table's and the phone list's head of that month
  #   read "Juli 2026" and "1 Transaktion".
  test "a month left with one booking counts it in the singular", %{conn: conn} do
    world = WorldFixtures.base_world(name: "Juli", cash_name: "Demo Cash", depot_name: "Depot 1")
    WorldFixtures.deposit!(world, "300", ~D[2026-07-03])
    second = WorldFixtures.deposit!(world, "450", ~D[2026-07-17])

    {:ok, view, _html} = live(conn, "/transactions?locale=de")

    head = fn view, selector ->
      view |> element(selector) |> render() |> Floki.parse_fragment!() |> text()
    end

    table = "#transaction-list tr.tx-group-head[data-month-group='2026-07']"
    phone = "#transaction-phone-rows li.phone-rows__group[data-month-group='2026-07']"

    assert head.(view, table) == "Juli 2026 2 Transaktionen"

    view |> element("#tx-kebab-#{second.id}") |> render_click()
    view |> element("#tx-delete-#{second.id}") |> render_click()
    view |> element("#booking-delete-confirm") |> render_click()

    assert head.(view, table) == "Juli 2026 1 Transaktion"
    assert head.(view, phone) == "Juli 2026 1 Transaktion"
  end

  # User story (#1084, pick J3.2 = A):
  # As the operator reading the history at desktop width,
  # I want a "Konto" column, on by default, that names the account each
  # booking's amount moved through,
  # so that a deposit or a set balance is never a row that names nothing,
  # and the desktop says at least what the phone row says.
  #
  # Acceptance criteria:
  # - The default columns read Datum · Typ · Wertpapier · Konto · Stückzahl ·
  #   Preis · Betrag.
  # - The cell names the cash account; a cash transfer "Sender → Empfänger",
  #   a security transfer "Depot 1 → Depot 2", each name isolated; a
  #   booking with no cash account its depot; a booking with neither (a
  #   split) nothing.
  # - The picker offers "Konto" in its "Buchung" group, checked.
  test "the desktop history names each booking's account in a Konto column", %{conn: conn} do
    %{world: world, usd: usd, deposit: deposit, sale: sale, kestrel_buy: buy} = september()

    savings =
      WorldFixtures.add_depot(world.portfolio, cash_name: "Tagesgeld", depot_name: "Depot 2")

    kestrel = buy.security_id

    transfer =
      book!(%{
        type: "cash_transfer",
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        counter_cash_account_id: savings.cash.id,
        gross_amount: "200",
        date: ~D[2026-08-10]
      })

    delivery =
      book!(%{
        type: "inbound_delivery",
        portfolio_id: world.portfolio.id,
        security_id: kestrel,
        securities_account_id: world.depot.id,
        quantity: "5",
        price: "41",
        date: ~D[2026-08-11]
      })

    # Shares move between two depots: both named, the sending one first, as
    # the delete dialog's box names them.
    moved =
      book!(%{
        type: "security_transfer",
        portfolio_id: world.portfolio.id,
        security_id: kestrel,
        securities_account_id: world.depot.id,
        counter_securities_account_id: savings.depot.id,
        quantity: "3",
        date: ~D[2026-10-01]
      })

    {:ok, [split]} =
      Splits.book_split(Actor.owner_ui(), %{
        security_id: kestrel,
        date: ~D[2026-10-02],
        ratio_numerator: 2,
        ratio_denominator: 1
      })

    {:ok, view, _html} = live(conn, "/transactions?locale=de")
    doc = document(view)

    heads =
      doc
      |> Floki.find("#transaction-list thead th")
      |> Enum.reject(&(Floki.attribute(&1, "class") == ["row-actions-head"]))
      |> Enum.map(&text/1)

    assert heads == ["Datum", "Typ", "Wertpapier", "Konto", "Stückzahl", "Preis", "Betrag"]

    account = fn tx ->
      doc
      |> Floki.find("#transaction-list tr[data-transaction='#{tx.id}'] td[data-role='account']")
      |> text()
    end

    assert account.(deposit) == "Demo Cash"
    assert account.(buy) == "Demo Cash"
    assert account.(sale) == "USD Settlement"
    assert account.(transfer) == "Demo Cash → Tagesgeld"
    assert account.(delivery) == "Depot 1"
    assert account.(moved) == "Depot 1 → Depot 2"
    assert account.(split) == ""

    [anchor] = Enum.filter(Ledger.list_transactions(), &(&1.type == "balance_adjustment"))
    assert account.(anchor) == usd.cash.name

    # Each stored name in its own <bdi>, the app's arrow outside them.
    bdis = fn tx ->
      doc
      |> Floki.find("#transaction-list tr[data-transaction='#{tx.id}'] td[data-role='account']")
      |> Floki.find("bdi")
      |> Enum.map(&text/1)
    end

    assert bdis.(transfer) == ["Demo Cash", "Tagesgeld"]
    assert bdis.(moved) == ["Depot 1", "Depot 2"]

    view |> element("#tx-column-toggle") |> render_click()
    picker = view |> element("#tx-column-form") |> render() |> Floki.parse_fragment!()

    [booking] =
      picker
      |> Floki.find("fieldset")
      |> Enum.filter(&(&1 |> Floki.find("legend") |> text() == "Buchung"))

    assert [checkbox] = Floki.find(booking, "input[value='account']")
    assert Floki.attribute(checkbox, "checked") != []
  end

  # User story (#1084, a stored column choice):
  # As the operator who shaped the history's columns before "Konto"
  # existed,
  # I want my stored choice to stay as I made it,
  # so that a new default column does not rearrange a table I shaped, and
  # "Konto" is one tick away when I want it.
  #
  # Acceptance criteria:
  # - A stored selection without `account`, restored through the
  #   ColumnPrefs hook, renders exactly its columns: no Konto head, no Konto
  #   cell.
  # - The picker offers "Konto" in its "Buchung" group, unchecked.
  test "a stored column choice without Konto is kept", %{conn: conn} do
    %{deposit: deposit} = september()

    {:ok, view, _html} = live(conn, "/transactions?locale=de")

    view
    |> element("#transaction-table-wrapper")
    |> render_hook("set_tx_columns", %{
      "columns" => ["date", "type", "security", "quantity", "price", "gross_amount"]
    })

    heads =
      view
      |> document()
      |> Floki.find("#transaction-list thead th")
      |> Enum.reject(&(Floki.attribute(&1, "class") == ["row-actions-head"]))
      |> Enum.map(&text/1)

    assert heads == ["Datum", "Typ", "Wertpapier", "Stückzahl", "Preis", "Betrag"]

    refute has_element?(
             view,
             "#transaction-list tr[data-transaction='#{deposit.id}'] td[data-role='account']"
           )

    view |> element("#tx-column-toggle") |> render_click()
    picker = view |> element("#tx-column-form") |> render() |> Floki.parse_fragment!()

    [booking] =
      picker
      |> Floki.find("fieldset")
      |> Enum.filter(&(&1 |> Floki.find("legend") |> text() == "Buchung"))

    assert [checkbox] = Floki.find(booking, "input[value='account']")
    assert Floki.attribute(checkbox, "checked") == []
  end

  # User story (U1 review, the table's width):
  # As the operator reading the history at 1200 px,
  # I want the whole row in view — Preis and Betrag included — beside a
  # long security name and a transfer that names two accounts,
  # so that the default Konto column never pushes the amounts out of the
  # table's scroller.
  #
  # Acceptance criteria:
  # - The Wertpapier and Konto cells are the names that wrap (`.cell-name`).
  # - The date (`.cell-date`) and the kind (`.cell-kind`) stay on one line,
  #   and every figure stays `.num` (the CSS invariant pins the rules; the
  #   browser measures the fit).
  test "the names are the cells that wrap; the date, the kind and the figures do not",
       %{conn: conn} do
    %{deposit: deposit, kestrel_buy: buy} = september()

    {:ok, view, _html} = live(conn, "/transactions?locale=de")
    doc = document(view)

    classes = fn tx ->
      doc
      |> Floki.find("#transaction-list tr[data-transaction='#{tx.id}'] td")
      |> Enum.map(&(&1 |> Floki.attribute("class") |> List.first()))
    end

    # Datum · Typ · Wertpapier · Konto · Stückzahl · Preis · Betrag · the
    # kebab.
    expected = ["cell-date", "cell-kind", "cell-name", "cell-name", "num", "num", "num"]
    assert Enum.take(classes.(buy), 7) == expected
    assert Enum.take(classes.(deposit), 7) == expected
  end

  # User story (#1073, the price):
  # As the operator who booked a price with four decimals,
  # I want the history's Price column and the phone row's size to show the
  # price with the digits it was stored with,
  # so that 41,1234 does not read 41,12 beside the notes drawer that shows
  # 41,1234 for the same booking.
  #
  # Acceptance criteria:
  # - A stored price keeps every digit, trailing zeros trimmed, at least two
  #   places: 41,1234 and 93,1046 as stored, 24 as 24,00 (R10c).
  # - The phone row's size and the delete dialog's box read the same.
  # - The English page reads 41.1234.
  test "the price column and the phone size keep the stored digits", %{conn: conn} do
    world = WorldFixtures.base_world(name: "Preis", cash_name: "Demo Cash", depot_name: "Depot 1")
    meridian = WorldFixtures.create_security!(name: "Meridian Global Equity ETF", ticker: "MGE")
    nordwind = WorldFixtures.create_security!(name: "Nordwind AG", ticker: "NWA")
    kestrel = WorldFixtures.create_security!(name: "Kestrel NV", ticker: "KNV")

    fine =
      WorldFixtures.buy!(world, meridian,
        quantity: "0.537",
        price: "93.1046",
        date: ~D[2026-08-28]
      )

    four =
      WorldFixtures.buy!(world, nordwind, quantity: "12", price: "41.1234", date: ~D[2026-08-14])

    whole = WorldFixtures.buy!(world, kestrel, quantity: "5", price: "24", date: ~D[2026-08-06])

    {:ok, view, _html} = live(conn, "/transactions?locale=de")
    doc = document(view)

    price = fn tx ->
      doc
      |> Floki.find("#transaction-list tr[data-transaction='#{tx.id}'] td[data-role='price']")
      |> text()
    end

    size = fn tx ->
      doc
      |> Floki.find("#transaction-phone-rows li[data-transaction='#{tx.id}'] .phone-row__figure2")
      |> text()
    end

    assert price.(fine) == "93,1046"
    assert price.(four) == "41,1234"
    assert price.(whole) == "24,00"

    assert size.(fine) == "0,537 × 93,1046"
    assert size.(four) == "12 × 41,1234"
    assert size.(whole) == "5 × 24,00"

    # The delete dialog's box reads the phone row's size (found while
    # drawing, item 3).
    view |> element("#tx-kebab-#{four.id}") |> render_click()
    view |> element("#tx-delete-#{four.id}") |> render_click()
    assert view |> element("#booking-delete-subject") |> render() =~ "12 × 41,1234"

    {:ok, view, _html} = live(conn, "/transactions")

    assert has_element?(
             view,
             "#transaction-list tr[data-transaction='#{four.id}'] td[data-role='price']",
             "41.1234"
           )
  end

  # User story (#1073, the closing act's edge-case hunter #2):
  # As the operator who imported a Portfolio Performance export,
  # I want a price the importer derived by division to read with at most
  # four decimals, the same on the history and on the security's
  # Transaktionen tab,
  # so that 1.234,56 EUR for 17 shares does not print "72,621176" — six
  # digits of rounding residue — beside "72,62" for the same booking.
  #
  # Acceptance criteria:
  # - The stored-digits rule (R10c, amended 2026-10-07) keeps every stored
  #   digit up to four decimal places, trailing zeros trimmed, at least two:
  #   72,621176 reads 72,6212, 41,1234 stays 41,1234, 24 reads 24,00.
  # - The Price column, the phone row's size and the delete dialog's box
  #   read the same, and so does the security's Transaktionen tab.
  test "a derived price reads with at most four places on the history and the security tab",
       %{conn: conn} do
    world = WorldFixtures.base_world(name: "Preis", cash_name: "Demo Cash", depot_name: "Depot 1")
    quotient = WorldFixtures.create_security!(name: "Quotient Werke AG", ticker: "QWA")
    nordwind = WorldFixtures.create_security!(name: "Nordwind AG", ticker: "NWA")
    kestrel = WorldFixtures.create_security!(name: "Kestrel NV", ticker: "KNV")

    # 1.234,56 EUR for 17 shares, as the PP JSON importer derives the price
    # (amount ÷ shares at the column's scale 6).
    derived =
      WorldFixtures.buy!(world, quotient,
        quantity: "17",
        price: "72.621176",
        date: ~D[2026-03-02]
      )

    four =
      WorldFixtures.buy!(world, nordwind, quantity: "12", price: "41.1234", date: ~D[2026-08-14])

    whole = WorldFixtures.buy!(world, kestrel, quantity: "5", price: "24", date: ~D[2026-08-06])

    {:ok, view, _html} = live(conn, "/transactions?locale=de")
    doc = document(view)

    price = fn tx ->
      doc
      |> Floki.find("#transaction-list tr[data-transaction='#{tx.id}'] td[data-role='price']")
      |> text()
    end

    size = fn tx ->
      doc
      |> Floki.find("#transaction-phone-rows li[data-transaction='#{tx.id}'] .phone-row__figure2")
      |> text()
    end

    assert price.(derived) == "72,6212"
    assert price.(four) == "41,1234"
    assert price.(whole) == "24,00"

    assert size.(derived) == "17 × 72,6212"
    assert size.(four) == "12 × 41,1234"
    assert size.(whole) == "5 × 24,00"

    view |> element("#tx-kebab-#{derived.id}") |> render_click()
    view |> element("#tx-delete-#{derived.id}") |> render_click()
    assert view |> element("#booking-delete-subject") |> render() =~ "17 × 72,6212"

    tab_price = fn security ->
      {:ok, tab, _html} = live(conn, "/securities/#{security.id}?tab=transactions&locale=de")

      tab
      |> render()
      |> Floki.parse_document!()
      |> Floki.find("#detail-tab-panel-transactions tbody td[data-role='price']")
      |> text()
    end

    assert tab_price.(quotient) == "72,6212 EUR"
    assert tab_price.(nordwind) == "41,1234 EUR"
    assert tab_price.(kestrel) == "24,00 EUR"
  end

  # User story (#1073; the PR γ closing act's cascade, layer 2):
  # As the operator who holds a penny stock or a token priced in fractions
  # of a cent,
  # I want a price under 1 to keep at least three significant digits,
  # so that a stored 0,000045 never reads "0,0000" — a price of zero — and
  # 0,001234 does not shrink to "0,0012".
  #
  # Acceptance criteria:
  # - A price under 1 keeps its stored digits up to two places past its
  #   first non-zero one, and never fewer than four: 0,000045 reads
  #   0,000045, 0,001234 reads 0,00123. A price of 1 or more keeps the
  #   four-place cap (72,621176 reads 72,6212).
  # - No non-zero price prints as zero.
  # - The Price column, the phone row's size and the security's
  #   Transaktionen tab read the same.
  test "a price under 1 keeps three significant digits on the history and the security tab",
       %{conn: conn} do
    world = WorldFixtures.base_world(name: "Preis", cash_name: "Demo Cash", depot_name: "Depot 1")
    micro = WorldFixtures.create_security!(name: "Mikro Token", ticker: "MKT")
    penny = WorldFixtures.create_security!(name: "Penny Werke AG", ticker: "PWA")

    tiny =
      WorldFixtures.buy!(world, micro,
        quantity: "1000000",
        price: "0.000045",
        date: ~D[2026-08-20]
      )

    small =
      WorldFixtures.buy!(world, penny, quantity: "5000", price: "0.001234", date: ~D[2026-08-21])

    {:ok, view, _html} = live(conn, "/transactions?locale=de")
    doc = document(view)

    price = fn tx ->
      doc
      |> Floki.find("#transaction-list tr[data-transaction='#{tx.id}'] td[data-role='price']")
      |> text()
    end

    size = fn tx ->
      doc
      |> Floki.find("#transaction-phone-rows li[data-transaction='#{tx.id}'] .phone-row__figure2")
      |> text()
    end

    assert price.(tiny) == "0,000045"
    assert price.(small) == "0,00123"

    assert size.(tiny) == "1.000.000 × 0,000045"
    assert size.(small) == "5.000 × 0,00123"

    tab_price = fn security ->
      {:ok, tab, _html} = live(conn, "/securities/#{security.id}?tab=transactions&locale=de")

      tab
      |> render()
      |> Floki.parse_document!()
      |> Floki.find("#detail-tab-panel-transactions tbody td[data-role='price']")
      |> text()
    end

    assert tab_price.(micro) == "0,000045 EUR"
    assert tab_price.(penny) == "0,00123 EUR"
  end

  # User story (#1090, the history's item):
  # As a newcomer opening Transaktionen,
  # I want the page's subtitle to say what the history holds,
  # so that a list of deposits, dividends and set balances is not titled a
  # buy and sell journal.
  #
  # Acceptance criteria:
  # - The subtitle reads "Every booking across accounts and depots" (EN) and
  #   "Alle Buchungen über alle Konten und Depots" (DE).
  test "the subtitle names what the history holds", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/transactions")

    assert view |> element("#app-topbar-subtitle") |> render() =~
             "Every booking across accounts and depots"

    {:ok, view, _html} = live(conn, "/transactions?locale=de")
    subtitle = view |> element("#app-topbar-subtitle") |> render()
    assert subtitle =~ "Alle Buchungen über alle Konten und Depots"
    refute subtitle =~ "Verkaufsjournal"
  end

  # User story (board 03, found while drawing, item 1; fixed under D-14):
  # As the operator reading the ledger of my savings account,
  # I want a transfer into it to read as money arriving,
  # so that the row does not say "-200,00" while the balance beside it rises
  # by 200.
  #
  # Acceptance criteria:
  # - With the chips selecting the transfer's receiving account and not its
  #   sender, the amount reads 200,00 in the table and on the phone row, and
  #   the delete dialog's box, which repeats the row, reads it too.
  # - With the sender in view, or no account chip, it reads -200,00.
  test "a cash transfer reads from the side of the account in view", %{conn: conn} do
    world = WorldFixtures.base_world(name: "Juli", cash_name: "Demo Cash", depot_name: "Depot 1")

    savings =
      WorldFixtures.add_depot(world.portfolio, cash_name: "Tagesgeld", depot_name: "Depot 2")

    WorldFixtures.deposit!(world, "1000", ~D[2026-07-01])

    transfer =
      book!(%{
        type: "cash_transfer",
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        counter_cash_account_id: savings.cash.id,
        gross_amount: "200",
        date: ~D[2026-07-14]
      })

    amount = fn view ->
      view
      |> element("#transaction-list tr[data-transaction='#{transfer.id}'] td[data-role='amount']")
      |> render()
      |> Floki.parse_fragment!()
      |> text()
    end

    phone = fn view ->
      view
      |> element(
        "#transaction-phone-rows li[data-transaction='#{transfer.id}'] .phone-row__figure"
      )
      |> render()
      |> Floki.parse_fragment!()
      |> text()
    end

    toggle = fn view, account ->
      view
      |> element(
        "#transaction-chips [phx-value-family='account'][phx-value-option='#{account.id}']"
      )
      |> render_click()
    end

    {:ok, view, _html} = live(conn, "/transactions?locale=de")
    assert amount.(view) == "-200,00 EUR"
    assert phone.(view) == "-200,00 EUR"

    toggle.(view, savings.cash)
    assert amount.(view) == "200,00 EUR"
    assert phone.(view) == "200,00 EUR"

    assert has_element?(
             view,
             "#transaction-list tr[data-transaction='#{transfer.id}'] [data-role='running-balance']",
             "200,00"
           )

    # The delete dialog's box says the row back as the row reads.
    view |> element("#tx-kebab-#{transfer.id}") |> render_click()
    view |> element("#tx-delete-#{transfer.id}") |> render_click()

    box =
      view
      |> element("#booking-delete-subject .phone-row__figure")
      |> render()
      |> Floki.parse_fragment!()
      |> text()

    assert box == "200,00 EUR"
    view |> element("[data-role='booking-delete-cancel']") |> render_click()

    # Both accounts in view: the sender's side, as the Konto cell names it
    # first.
    toggle.(view, world.cash)
    assert amount.(view) == "-200,00 EUR"

    # The sender alone.
    toggle.(view, savings.cash)
    assert amount.(view) == "-200,00 EUR"
  end

  # User story (U1 review, the phone row of a transfer):
  # As the operator reading my savings account's ledger on a phone,
  # I want a transfer's row to name both of its accounts,
  # so that a figure that reads as arriving does not sit under the name of
  # the account it left.
  #
  # Acceptance criteria:
  # - The phone row's subject reads "Demo Cash → Tagesgeld", sender first,
  #   each name in its own <bdi> and the arrow outside them, as the desktop
  #   Konto cell does — unfiltered and with the receiving account in view.
  # - A booking with one account still names that one alone.
  test "a cash transfer's phone row names both of its accounts", %{conn: conn} do
    world = WorldFixtures.base_world(name: "Juli", cash_name: "Demo Cash", depot_name: "Depot 1")

    savings =
      WorldFixtures.add_depot(world.portfolio, cash_name: "Tagesgeld", depot_name: "Depot 2")

    deposit = WorldFixtures.deposit!(world, "1000", ~D[2026-07-01])

    transfer =
      book!(%{
        type: "cash_transfer",
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        counter_cash_account_id: savings.cash.id,
        gross_amount: "200",
        date: ~D[2026-07-14]
      })

    subject = fn view, tx ->
      [ids] =
        view
        |> document()
        |> Floki.find("#transaction-phone-rows li[data-transaction='#{tx.id}'] .phone-row__ids")

      {text(ids), ids |> Floki.find("bdi") |> Enum.map(&text/1)}
    end

    {:ok, view, _html} = live(conn, "/transactions?locale=de")

    assert subject.(view, transfer) == {"Demo Cash → Tagesgeld", ["Demo Cash", "Tagesgeld"]}
    assert subject.(view, deposit) == {"Demo Cash", ["Demo Cash"]}

    # The receiver in view: the row reads as arriving, and still names where
    # the money came from.
    view
    |> element(
      "#transaction-chips [phx-value-family='account'][phx-value-option='#{savings.cash.id}']"
    )
    |> render_click()

    assert subject.(view, transfer) == {"Demo Cash → Tagesgeld", ["Demo Cash", "Tagesgeld"]}
  end
end
