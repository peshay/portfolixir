defmodule PortfolixirWeb.SecuritiesTradesTabTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, sell!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Ledger

  # One invented security with three closed trades and two sells of
  # delivered-in shares, FIFO in one queue:
  # - 2023-06-01 → 2025-05-31, 730 days, 10 × 100 → 10 × 64: -20 % a year;
  # - 2024-01-02 → 2026-01-01, 730 days, 10 × 100 → 10 × 144: +20 % a year;
  # - 2026-02-01 → 2026-03-03, 30 days, 4 × 50 → 4 × 45: not annualized;
  # - 20 shares delivered in on 2026-04-01, sold as 8 (2026-04-20) and
  #   12 (2026-05-28): no lot, so no trade.
  defp seed_nordwind! do
    world = base_world(name: "Tab World", cash_name: "Girokonto", depot_name: "Depot 1")
    deposit!(world, "100000", ~D[2023-01-02])
    nordwind = create_security!(name: "Nordwind Industrie AG", ticker: "NWI")

    buy!(world, nordwind, quantity: "10", price: "100", date: ~D[2023-06-01])
    buy!(world, nordwind, quantity: "10", price: "100", date: ~D[2024-01-02])
    sell!(world, nordwind, quantity: "10", price: "64", date: ~D[2025-05-31])
    sell!(world, nordwind, quantity: "10", price: "144", date: ~D[2026-01-01])
    buy!(world, nordwind, quantity: "4", price: "50", date: ~D[2026-02-01])
    sell!(world, nordwind, quantity: "4", price: "45", date: ~D[2026-03-03])
    deliver!(world, nordwind, "20", ~D[2026-04-01])
    sell!(world, nordwind, quantity: "8", price: "60", date: ~D[2026-04-20])
    sell!(world, nordwind, quantity: "12", price: "62", date: ~D[2026-05-28])

    %{world: world, nordwind: nordwind}
  end

  defp deliver!(world, security, quantity, date) do
    {:ok, _delivery} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        security_id: security.id,
        type: "inbound_delivery",
        date: date,
        quantity: quantity,
        currency_code: "EUR"
      })
  end

  defp text(nodes),
    do: nodes |> Floki.text(sep: " ") |> String.replace(~r/\s+/, " ") |> String.trim()

  defp document(view), do: view |> render() |> Floki.parse_document!()

  defp closed_row(doc, opened) do
    doc
    |> Floki.find("#detail-closed-trades-table tbody tr")
    |> Enum.find(&(text(Floki.find(&1, "td:first-child")) == opened))
  end

  defp phone_row(doc, opened) do
    doc
    |> Floki.find("#detail-closed-trades-phone-rows li.phone-row")
    |> Enum.find(&String.starts_with?(text(Floki.find(&1, ".phone-row__name")), opened))
  end

  defp class_of(node), do: node |> Floki.attribute("class") |> List.first("")

  defp de_conn(conn), do: Plug.Test.put_req_cookie(conn, "portfolixir_locale", "de")

  # User story (#1029, Sprint 18 F6; board ux-design-2026-10-02/01-trades-tab-pa,
  # pick H1 "after"; DESIGN.md → Amendment 2026-10-01 — Trades):
  # As a local portfolio maintainer who followed a trade from the Trades
  # facet or the Overview card to its security,
  # I want the security's own closed-trades table to show each trade's p. a.
  # figure beside its result,
  # so that the per-security trades read the API and the companion serve has
  # its human view, and a two-year trade and a two-week trade no longer read
  # alike on the page I land on.
  #
  # Acceptance criteria:
  # - "p. a." sits between "Days" and "Realised P&L", a `.num` column.
  # - From 365 days of holding the cell is the trade's annualized return,
  #   signed, one decimal, the percent sign glued on, in its sign colour.
  # - Below 365 days it is a muted dash, aria-hidden, whose reason rides the
  #   cell's title and a visually hidden sentence; a trade whose flows no
  #   rate solves carries the same dash with its own reason.
  # - A basis line under the list states the rules: across every depot,
  #   deliveries open no lot, fees and taxes in the P&L and not in the
  #   average prices, income while open not included, p. a. from 365 days.
  # - "p. a." is set with a no-break space (U+00A0) in the header, the basis
  #   line and the phone row, so the abbreviation never breaks across lines
  #   (design critic R6, board ux-review-2026-10-03/01-contribution-repairs).
  test "the closed trades carry p. a. directly left of the realised P&L", %{conn: conn} do
    %{nordwind: nordwind} = seed_nordwind!()

    {:ok, view, _html} = live(conn, "/securities/#{nordwind.id}?tab=trades")
    doc = document(view)

    assert [_table] =
             Floki.find(
               doc,
               "#detail-closed-trades-table-wrap.data-table-wrap #detail-closed-trades-table"
             )

    headers = doc |> Floki.find("#detail-closed-trades-table thead th") |> Enum.map(&text/1)

    assert headers == [
             "Opened",
             "Closed",
             "Quantity",
             "Avg buy",
             "Avg sell",
             "Days",
             "p.\u00A0a.",
             "Realised P&L",
             "%"
           ]

    assert [pa_th] = Floki.find(doc, "#detail-closed-trades-table thead th:nth-child(7)")
    assert class_of(pa_th) =~ "num"

    long = closed_row(doc, "2024-01-02")
    assert [pa] = Floki.find(long, "td:nth-child(7)")
    assert class_of(pa) =~ "trade-pa"
    assert class_of(pa) =~ "num"
    assert class_of(pa) =~ "is-positive"
    assert text(pa) == "+20.0%"
    assert text(Floki.find(long, "td:nth-child(8)")) == "+440.00"

    fade = closed_row(doc, "2023-06-01")
    assert [pa] = Floki.find(fade, "td.trade-pa")
    assert class_of(pa) =~ "is-negative"
    assert text(pa) == "-20.0%"

    quick = closed_row(doc, "2026-02-01")
    assert [dash] = Floki.find(quick, "td:nth-child(7).trade-pa.trade-pa--na")
    assert Floki.attribute(dash, "title") == ["Not annualized under one year of holding"]
    assert text(Floki.find(dash, "[aria-hidden='true']")) == "—"

    assert text(Floki.find(dash, ".visually-hidden")) ==
             "not annualized, under one year of holding"

    assert [basis] =
             Floki.find(
               doc,
               "p#detail-closed-trades-basis.detail-tab-hint[data-role='trades-basis']"
             )

    assert text(basis) ==
             "Across every depot · deliveries open no lot · fees and taxes in the realised P&L, " <>
               "not in avg buy and avg sell · income received while a trade was open not " <>
               "included · p.\u00A0a. only from 365 days of holding and only where a rate " <>
               "solves the flows"
  end

  # Acceptance criteria (board N2, a trade held long enough that no rate
  # solves — a total loss):
  # - The p. a. cell is the same muted dash, with the solver's reason.
  test "a long trade no rate solves shows the dash with its own reason", %{conn: conn} do
    world = base_world(name: "Loss World", cash_name: "Girokonto", depot_name: "Depot 1")
    deposit!(world, "10000", ~D[2021-01-04])
    halvorsen = create_security!(name: "Halvorsen Shipping AS", ticker: "HSA")
    buy!(world, halvorsen, quantity: "50", price: "12.40", date: ~D[2021-03-01])
    sell!(world, halvorsen, quantity: "50", price: "0", date: ~D[2025-12-01])

    {:ok, view, _html} = live(conn, "/securities/#{halvorsen.id}?tab=trades")
    row = closed_row(document(view), "2021-03-01")

    assert text(Floki.find(row, "td:nth-child(6)")) == "1736"
    assert [dash] = Floki.find(row, "td.trade-pa.trade-pa--na")

    assert Floki.attribute(dash, "title") == [
             "No annualized return: no rate solves this trade's flows"
           ]

    assert text(Floki.find(dash, ".visually-hidden")) ==
             "no annualized return, no rate solves this trade's flows"
  end

  # User story (#1089; the PR γ closing act, first-look persona):
  # As the operator reading a security's closed trades on a phone, by eye or
  # with a screen reader,
  # I want a trade without p. a. to say why on its phone row, as its table
  # row's dash does at a desktop width,
  # so that a total loss held 600 days does not lose its reason at 390 px.
  #
  # Acceptance criteria:
  # - A phone row without p. a. carries the dash's reason, a visually hidden
  #   sentence after its figures: the solver's reason for a trade no rate
  #   solves, the holding period's under 365 days.
  # - The visible row is unchanged, and a row with p. a. carries none.
  test "a phone row without p. a. says why, as the table's dash does", %{conn: conn} do
    %{nordwind: nordwind} = seed_nordwind!()
    world = base_world(name: "Why Tab World", cash_name: "Girokonto", depot_name: "Depot 1")
    deposit!(world, "10000", ~D[2024-01-02])
    tamarisk = create_security!(name: "Tamarisk Mining Ltd", ticker: "TML")
    buy!(world, tamarisk, quantity: "10", price: "40", date: ~D[2024-11-02])
    sell!(world, tamarisk, quantity: "10", price: "0", date: ~D[2026-06-25])

    why = fn doc, opened ->
      doc |> phone_row(opened) |> Floki.find(".visually-hidden[data-role='pa-absent']") |> text()
    end

    {:ok, view, _html} = live(conn, "/securities/#{tamarisk.id}?tab=trades")
    doc = document(view)

    assert why.(doc, "2024-11-02") == "no annualized return, no rate solves this trade's flows"
    assert text(Floki.find(phone_row(doc, "2024-11-02"), ".phone-row__figure2")) == "-100.0%"

    assert text(Floki.find(closed_row(doc, "2024-11-02"), "td.trade-pa .visually-hidden")) ==
             why.(doc, "2024-11-02")

    {:ok, view, _html} = live(conn, "/securities/#{nordwind.id}?tab=trades")
    doc = document(view)

    assert why.(doc, "2026-02-01") == "not annualized, under one year of holding"
    assert why.(doc, "2024-01-02") == ""
  end

  # User story (#1029, the warning that guessed; board pin 3, UX-DR25):
  # As a local portfolio maintainer with an imported history,
  # I want the tab to name the sells no buy was matched to, with the
  # delivery as the usual cause, where the closed trades are read,
  # so that "some data may be missing" stops reading as an error when an
  # inbound delivery simply opened no lot.
  #
  # Acceptance criteria:
  # - An attention note leads the closed-trades section, under its heading,
  #   counting the sells and naming an inbound delivery as the usual cause.
  # - Its disclosure (closed) lists each sell, newest first, as date ·
  #   unmatched quantity — the security is the page's own.
  # - No remedy control; the basis line under the list states the limit.
  # - The old warning under both tables is gone.
  test "the sells of delivered-in shares are named where the trades are read", %{conn: conn} do
    %{nordwind: nordwind} = seed_nordwind!()

    {:ok, view, _html} = live(conn, "/securities/#{nordwind.id}?tab=trades")
    doc = document(view)

    assert [note] =
             Floki.find(
               doc,
               "#detail-closed-trades-note.data-note.data-note--attention[data-role='trades-unmatched']"
             )

    assert text(Floki.find(note, ".data-note__body")) =~
             "2 sales have no matched buy for all or part of their quantity (shares from " <>
               "inbound deliveries, for example): that quantity is not included in any closed trade."

    assert [details] = Floki.find(note, "details.perf-table-disclosure")
    assert Floki.attribute(details, "open") == []
    assert text(Floki.find(details, "summary.disclosure-summary")) == "The 2 sales"

    items =
      note
      |> Floki.find(".excluded-list li")
      |> Enum.map(fn li -> li |> Floki.find("span.num") |> Enum.map(&text/1) end)

    assert items == [["2026-05-28", "12.0000 units"], ["2026-04-20", "8.0000 units"]]
    assert Floki.find(note, "button") == []

    refute has_element?(view, ".detail-tab-warning")
    refute render(view) =~ "they may indicate missing data"

    panel = view |> element("#detail-tab-panel-trades") |> render()
    {heading_at, _} = :binary.match(panel, "Closed trades (FIFO)")
    {note_at, _} = :binary.match(panel, ~s(id="detail-closed-trades-note"))
    {table_at, _} = :binary.match(panel, ~s(id="detail-closed-trades-table-wrap"))
    {basis_at, _} = :binary.match(panel, ~s(id="detail-closed-trades-basis"))
    assert heading_at < note_at and note_at < table_at and table_at < basis_at
  end

  # Acceptance criteria (board N1, only delivered-in shares were sold):
  # - The section shows its heading, the note and the basis line, no table.
  # - The empty sentence "record some buys and sells first" is dropped: there
  #   is no buy to record. A security with no trade at all keeps it.
  test "with only delivered-in shares sold the section is its note", %{conn: conn} do
    world = base_world(name: "Delivered World", cash_name: "Girokonto", depot_name: "Depot 1")
    birkenhain = create_security!(name: "Birkenhain Wasser AG", ticker: "BWA")
    deliver!(world, birkenhain, "40", ~D[2026-01-15])
    sell!(world, birkenhain, quantity: "40", price: "25", date: ~D[2026-03-09])
    untouched = create_security!(name: "Kestrel Robotik SE", ticker: "KRS")

    {:ok, view, _html} = live(conn, "/securities/#{birkenhain.id}?tab=trades")
    doc = document(view)

    assert text(Floki.find(doc, "#detail-tab-panel-trades h3")) == "Closed trades (FIFO)"

    assert text(Floki.find(doc, "#detail-closed-trades-note .data-note__body")) =~
             "1 sale has no matched buy for all or part of its quantity (shares from an " <>
               "inbound delivery, for example): that quantity is not included in any closed trade."

    assert text(Floki.find(doc, "#detail-closed-trades-note summary")) == "The sale"
    assert Floki.find(doc, "#detail-closed-trades-table") == []
    assert Floki.find(doc, "#detail-closed-trades-phone-rows") == []
    assert [_basis] = Floki.find(doc, "#detail-closed-trades-basis")
    assert Floki.find(doc, "#detail-tab-panel-trades .detail-tab-empty") == []

    {:ok, empty_view, _html} = live(conn, "/securities/#{untouched.id}?tab=trades")

    assert has_element?(
             empty_view,
             "#detail-tab-panel-trades .detail-tab-empty",
             "No matched trades yet"
           )

    refute has_element?(empty_view, "#detail-closed-trades-basis")
  end

  # Acceptance criteria (UX-DR27, board rule ④):
  # - Beside the table, two-line rows for under 560 px: opened → closed over
  #   quantity · days; the result with its currency over the period return
  #   and, from 365 days, " · p. a." — no dash on the phone, the basis line
  #   says why. Avg buy and avg sell are not on the phone.
  test "the closed trades carry two-line phone rows beside the table", %{conn: conn} do
    %{nordwind: nordwind} = seed_nordwind!()

    {:ok, view, _html} = live(conn, "/securities/#{nordwind.id}?tab=trades")
    doc = document(view)

    assert [list] = Floki.find(doc, "ul#detail-closed-trades-phone-rows.phone-rows")
    assert Floki.attribute(list, "aria-label") == ["Closed trades"]
    assert length(Floki.find(list, "li.phone-row")) == 3

    long = phone_row(doc, "2024-01-02")
    assert text(Floki.find(long, ".phone-row__name")) == "2024-01-02 → 2026-01-01"
    assert text(Floki.find(long, ".phone-row__ids")) == "10.0000 units · 730 days"
    assert [figure] = Floki.find(long, ".phone-row__figure")
    assert class_of(figure) =~ "is-positive"
    assert text(figure) == "+440.00 EUR"
    assert text(Floki.find(long, ".phone-row__figure2")) == "+44.0% · +20.0% p.\u00A0a."

    assert long |> Floki.find(".phone-row__figure2 span") |> Enum.map(&class_of/1) ==
             ["decimal-positive", "decimal-positive"]

    fade = phone_row(doc, "2023-06-01")
    assert text(Floki.find(fade, ".phone-row__figure2")) == "-36.0% · -20.0% p.\u00A0a."

    quick = phone_row(doc, "2026-02-01")
    assert text(Floki.find(quick, ".phone-row__figure2")) == "-10.0%"
  end

  # Acceptance criteria (UX-DR27; DESIGN.md → Two-line phone rows):
  # - A trade sold at exactly its cost, held for more than a year, shows its
  #   0.0% period return and its 0.0% p. a. on the phone row in neither sign
  #   colour: a figure that is neither a gain nor a loss is not coloured as
  #   one. Since the Sprint 19 U2 review it is marked directionless,
  #   `is-flat`, as on the Trades facet.
  test "a break-even trade's phone figures carry no sign colour", %{conn: conn} do
    world = base_world(name: "Even World", cash_name: "Girokonto", depot_name: "Depot 1")
    deposit!(world, "5000", ~D[2024-01-02])
    level = create_security!(name: "Level Lines AG", ticker: "LVL")
    buy!(world, level, quantity: "10", price: "50", date: ~D[2024-02-01])
    sell!(world, level, quantity: "10", price: "50", date: ~D[2025-04-01])

    {:ok, view, _html} = live(conn, "/securities/#{level.id}?tab=trades")
    even = phone_row(document(view), "2024-02-01")

    assert text(Floki.find(even, ".phone-row__figure2")) == "0.0% · 0.0% p.\u00A0a."

    assert even |> Floki.find(".phone-row__figure2 span") |> Enum.map(&class_of/1) ==
             ["is-flat", "is-flat"]
  end

  # Acceptance criteria (the German page, board H1's copy):
  # - The column, the figure, the dash's reason, the note, its list, the
  #   basis line and the phone rows in German.
  test "the Trades tab is German where the page is", %{conn: conn} do
    %{nordwind: nordwind} = seed_nordwind!()

    {:ok, view, _html} = live(de_conn(conn), "/securities/#{nordwind.id}?tab=trades")
    doc = document(view)

    headers = doc |> Floki.find("#detail-closed-trades-table thead th") |> Enum.map(&text/1)
    assert Enum.slice(headers, 5, 3) == ["Tage", "p.\u00A0a.", "Realisierter G/V"]

    # #1060 (Sprint 19 U2): the tab's dates are the German form here.
    assert text(Floki.find(closed_row(doc, "02.01.2024"), "td.trade-pa")) == "+20,0%"

    assert Floki.attribute(Floki.find(closed_row(doc, "01.02.2026"), "td.trade-pa--na"), "title") ==
             ["Unter einem Jahr Haltedauer nicht annualisiert"]

    assert text(Floki.find(doc, "#detail-closed-trades-note .data-note__word")) == "Achtung"

    assert text(Floki.find(doc, "#detail-closed-trades-note .data-note__body")) =~
             "2 Verkäufe haben für ihre ganze Stückzahl oder einen Teil davon keinen " <>
               "zugeordneten Kauf (z. B. aus Einlieferungen): Diese Stückzahl ist in keinem " <>
               "abgeschlossenen Trade enthalten."

    assert text(Floki.find(doc, "#detail-closed-trades-note summary")) == "Die 2 Verkäufe"
    assert text(Floki.find(doc, "#detail-closed-trades-note .excluded-list")) =~ "12,0000 Stück"

    assert text(Floki.find(doc, "#detail-closed-trades-basis")) ==
             "Über alle Depots · Einlieferungen eröffnen keinen Lot · Gebühren und Steuern im " <>
               "G/V, nicht in Ø Kauf und Ø Verkauf · Erträge während der Haltedauer nicht " <>
               "enthalten · p.\u00A0a. erst ab 365 Tagen Haltedauer und nur, wo ein Zinssatz " <>
               "die Zahlungen löst"

    long = phone_row(doc, "02.01.2024")
    assert text(Floki.find(long, ".phone-row__ids")) == "10,0000 Stück · 730 Tage"
    assert text(Floki.find(long, ".phone-row__figure2")) == "+44,0% · +20,0% p.\u00A0a."
  end

  # User story (#1060, Sprint 19 PR γ U2; board ux-design-2026-10-04/04-trades,
  # before/after):
  # As a local portfolio maintainer reading a security's Trades tab in German,
  # I want its dates in the German form and its "%" columns in the form the
  # rest of the app uses,
  # so that the tab no longer reads "2024-03-14" and "+27,07 %" beside a phone
  # row and a p. a. column that read "+27,1%".
  #
  # Acceptance criteria:
  # - The open lots' open date, the closed trades' two dates, the unmatched
  #   sells' list and the phone rows go through Format.date ("14.03.2024").
  # - Both "%" columns print one decimal with the sign glued on ("+18,7%",
  #   "-36,0%"), the form of the p. a. column beside them.
  test "the Trades tab prints German dates and one-decimal signed percents", %{conn: conn} do
    %{world: world, nordwind: nordwind} = seed_nordwind!()
    kestrel = create_security!(name: "Kestrel Robotik SE", ticker: "KRS")
    buy!(world, kestrel, quantity: "40", price: "52.10", date: ~D[2024-03-14])
    Portfolixir.WorldFixtures.put_quote!(kestrel, ~D[2026-10-01], "61.85")

    {:ok, lots_view, _html} = live(de_conn(conn), "/securities/#{kestrel.id}?tab=trades")
    lots_doc = document(lots_view)

    assert [lot] =
             lots_doc
             |> Floki.find("#detail-tab-panel-trades table.detail-trades-table tbody tr")
             |> Enum.take(1)

    assert text(Floki.find(lot, "td:nth-child(1)")) == "14.03.2024"
    assert text(Floki.find(lot, "td:nth-child(6)")) == "+18,7%"

    {:ok, view, _html} = live(de_conn(conn), "/securities/#{nordwind.id}?tab=trades")
    doc = document(view)

    long = closed_row(doc, "02.01.2024")
    assert text(Floki.find(long, "td:nth-child(2)")) == "01.01.2026"
    assert text(Floki.find(long, "td:nth-child(9)")) == "+44,0%"
    assert text(Floki.find(closed_row(doc, "01.06.2023"), "td:nth-child(9)")) == "-36,0%"

    items =
      doc
      |> Floki.find("#detail-closed-trades-note .excluded-list li")
      |> Enum.map(fn li -> li |> Floki.find("span.num") |> Enum.map(&text/1) end)

    assert items == [["28.05.2026", "12,0000 Stück"], ["20.04.2026", "8,0000 Stück"]]

    assert text(Floki.find(phone_row(doc, "02.01.2024"), ".phone-row__name")) ==
             "02.01.2024 → 01.01.2026"

    panel = view |> element("#detail-tab-panel-trades") |> render()
    refute panel =~ ~r/\d{4}-\d{2}-\d{2}/
    refute panel =~ ~r/\d %/
  end

  # User story (Sprint 20 β B3, board ux-design-2026-10-07/02-money-findings,
  # found while drawing 11; #1060's alignment carried to the Holdings tab):
  # As a local portfolio maintainer reading a security's Holdings tab,
  # I want its "%" column in the form the Trades tab uses, coloured by the
  # percent it shows,
  # so that "0,00 %" no longer wraps onto two lines in a narrow column, and a
  # percent that reads zero is not printed in the gain colour of the amount
  # beside it.
  #
  # Acceptance criteria:
  # - The "%" cell prints one decimal with the sign and the percent sign
  #   glued on ("+18,7%"), as the Trades tab's "%" columns do.
  # - Its colour is the percent's own as displayed: a gain of 4.00 EUR on
  #   100,000.00 is "+4.00" in the gain colour beside "0.0%", unsigned and
  #   `is-flat` (before: "+0.00 %" in the amount's gain colour).
  test "the Holdings tab's percent is the Trades tab's form, coloured by itself", %{conn: conn} do
    world = base_world(name: "Holdings Pct", cash_name: "Girokonto", depot_name: "Depot 1")
    deposit!(world, "200000", ~D[2024-01-02])
    kestrel = create_security!(name: "Kestrel Robotik SE", ticker: "KRS")
    buy!(world, kestrel, quantity: "40", price: "52.10", date: ~D[2024-03-14])
    Portfolixir.WorldFixtures.put_quote!(kestrel, ~D[2026-10-01], "61.85")

    {:ok, view, _html} = live(de_conn(conn), "/securities/#{kestrel.id}?tab=holdings")

    assert [row | _bucket_row] =
             view |> document() |> Floki.find("table.detail-holdings-table tbody tr")

    assert [percent] = Floki.find(row, "td:nth-child(6)")
    assert text(percent) == "+18,7%"
    assert class_of(percent) =~ "is-positive"

    hairline = create_security!(name: "Hairline Gain plc", ticker: "HLG")
    buy!(world, hairline, quantity: "1000", price: "100", date: ~D[2024-01-02])
    Portfolixir.WorldFixtures.put_quote!(hairline, ~D[2026-10-01], "100.004")

    {:ok, flat_view, _html} = live(conn, "/securities/#{hairline.id}?tab=holdings")

    assert [flat_row | _bucket_row] =
             flat_view |> document() |> Floki.find("table.detail-holdings-table tbody tr")

    assert text(Floki.find(flat_row, "td:nth-child(5)")) == "+4.00"
    assert [flat] = Floki.find(flat_row, "td:nth-child(6)")
    assert text(flat) == "0.0%"
    assert class_of(flat) =~ "is-flat"
    refute class_of(flat) =~ ~r/is-positive|is-negative/
  end

  # User story (#1074's trades half, Sprint 19 PR γ U2; board 04):
  # As a local portfolio maintainer reading the English page,
  # I want a quantity of one to read "unit" on the security's Trades tab,
  # so that neither the unmatched-sells list nor a phone row says
  # "1.0000 units".
  #
  # Acceptance criteria:
  # - One unit reads "1.0000 unit" in the note's list and in the phone row;
  #   any other quantity reads "units" (U1's count rule).
  test "a closed trade and an unmatched sell of one unit read unit", %{conn: conn} do
    world = base_world(name: "Unit Tab", cash_name: "Girokonto", depot_name: "Depot 1")
    deposit!(world, "5000", ~D[2026-01-02])
    single = create_security!(name: "Brightwater Utilities plc", ticker: "BWU")
    buy!(world, single, quantity: "1", price: "80", date: ~D[2026-01-12])
    sell!(world, single, quantity: "1", price: "86.88", date: ~D[2026-05-20])
    deliver!(world, single, "1", ~D[2026-08-01])
    sell!(world, single, quantity: "1", price: "90", date: ~D[2026-08-24])

    {:ok, view, _html} = live(conn, "/securities/#{single.id}?tab=trades")
    doc = document(view)

    assert text(Floki.find(phone_row(doc, "2026-01-12"), ".phone-row__ids")) ==
             "1.0000 unit · 128 days"

    assert doc
           |> Floki.find("#detail-closed-trades-note .excluded-list li span.num")
           |> Enum.map(&text/1) == ["2026-08-24", "1.0000 unit"]

    refute render(view) =~ "1.0000 units"
  end

  # User story (#1059, Sprint 19 PR γ U2; board 04 rule ④):
  # As a local portfolio maintainer on a phone or a tablet,
  # I want the labelled ⓘ pill "Price & currency return" to show its whole
  # label,
  # so that its first ~50 px no longer fall off the left edge of the screen.
  #
  # Acceptance criteria:
  # - Under `pointer: coarse` the labelled pill keeps `width: auto; height:
  #   auto` with the coarse ⓘ's 1.75rem as its minimum height.
  # - The rule comes after the coarse ⓘ circle's rule, which it overrides at
  #   the same specificity.
  # - The Trades tab's and the Holdings tab's pills both carry the class it
  #   targets.
  test "the labelled ⓘ pill keeps its width under a coarse pointer", %{conn: conn} do
    css = File.read!("priv/static/app.css")

    # The coarse block's circle rule, then — next in the same block, a
    # comment at most between them — the labelled pill's rule.
    [_rule, body] =
      Regex.run(
        ~r/@media \(pointer: coarse\) \{\s*\.metric-tooltip summary \{\s*width: 1\.75rem;[^}]*\}\s*(?:\/\*(?:[^*]|\*(?!\/))*\*\/\s*)?\.metric-tooltip--labelled summary \{([^}]*)\}/,
        css
      )

    assert body =~ ~r/width:\s*auto;/
    assert body =~ ~r/height:\s*auto;/
    assert body =~ ~r/min-height:\s*1\.75rem;/

    world = base_world(name: "Pill World", cash_name: "Girokonto", depot_name: "Depot 1")
    deposit!(world, "5000", ~D[2024-01-02])
    kestrel = create_security!(name: "Kestrel Robotik SE", ticker: "KRS")
    buy!(world, kestrel, quantity: "40", price: "52.10", date: ~D[2024-03-14])

    {:ok, view, _html} = live(conn, "/securities/#{kestrel.id}?tab=trades")

    assert has_element?(
             view,
             "details.metric-tooltip--labelled[data-role='lot-decomposition-info']"
           )

    {:ok, holdings, _html} = live(conn, "/securities/#{kestrel.id}?tab=holdings")

    assert has_element?(
             holdings,
             "details.metric-tooltip--labelled[data-role='pnl-decomposition-info']"
           )
  end

  # User story (#1089 and #1060, the Sprint 19 U2 review; board
  # ux-design-2026-10-04/04-trades):
  # As a local portfolio maintainer reading why a closed trade on a
  # security's Trades tab has no p. a. figure,
  # I want the tab's basis line to name both limits, as the facet's does,
  # so that a long trade with no rate — a total loss — is explained where
  # its phone row shows only the period return.
  #
  # Acceptance criteria:
  # - The basis line ends "p. a. only from 365 days of holding and only where
  #   a rate solves the flows"; German "p. a. erst ab 365 Tagen Haltedauer
  #   und nur, wo ein Zinssatz die Zahlungen löst", "p. a." with its no-break
  #   space.
  test "the tab's basis line names both limits of p. a.", %{conn: conn} do
    world = base_world(name: "Limit World", cash_name: "Girokonto", depot_name: "Depot 1")
    deposit!(world, "10000", ~D[2021-01-04])
    halvorsen = create_security!(name: "Halvorsen Shipping AS", ticker: "HSA")
    buy!(world, halvorsen, quantity: "50", price: "12.40", date: ~D[2021-03-01])
    sell!(world, halvorsen, quantity: "50", price: "0", date: ~D[2025-12-01])

    {:ok, view, _html} = live(conn, "/securities/#{halvorsen.id}?tab=trades")
    doc = document(view)

    assert text(Floki.find(phone_row(doc, "2021-03-01"), ".phone-row__figure2")) == "-100.0%"

    assert text(Floki.find(doc, "#detail-closed-trades-basis")) =~
             ~r/· p\.\x{00A0}a\. only from 365 days of holding and only where a rate solves the flows$/u

    {:ok, de_view, _html} = live(de_conn(conn), "/securities/#{halvorsen.id}?tab=trades")

    assert text(Floki.find(document(de_view), "#detail-closed-trades-basis")) =~
             ~r/· p\.\x{00A0}a\. erst ab 365 Tagen Haltedauer und nur, wo ein Zinssatz die Zahlungen löst$/u
  end

  # User story (the Sprint 19 U2 review; #1060 and #1089):
  # As a local portfolio maintainer reading a security's Trades tab, and as
  # one who cannot tell its green from its red,
  # I want a figure's sign and its colour decided on the figure as shown, and
  # a percent that does not exist shown as a dash,
  # so that "0.00" or "0.0%" never reads in the gain colour, and a lot with
  # no price reads as unknown rather than as zero.
  #
  # Acceptance criteria:
  # - An open lot and a closed trade whose results round to zero at the
  #   places they are shown at (a gain of 0.004 EUR, 0.004 %) read "0.00"
  #   and "0.0%" — and "0.0%" p. a. — with no sign; the cells and the phone
  #   figures are `is-flat`, never a gain or loss colour.
  # - An open lot with no stored price has no percent: its "%" cell reads
  #   "—" in no colour.
  test "a figure that rounds to zero is unsigned, a missing percent a dash", %{conn: conn} do
    world = base_world(name: "Hairline Tab", cash_name: "Girokonto", depot_name: "Depot 1")
    deposit!(world, "5000", ~D[2024-01-02])
    hairline = create_security!(name: "Hairline Gain plc", ticker: "HLG")
    buy!(world, hairline, quantity: "1", price: "100", date: ~D[2024-01-02])
    sell!(world, hairline, quantity: "1", price: "100.004", date: ~D[2026-01-01])
    buy!(world, hairline, quantity: "1", price: "100", date: ~D[2026-02-02])
    Portfolixir.WorldFixtures.put_quote!(hairline, ~D[2026-10-01], "100.004")

    {:ok, view, _html} = live(conn, "/securities/#{hairline.id}?tab=trades")
    doc = document(view)

    [lots_table | _closed] = Floki.find(doc, "#detail-tab-panel-trades table.detail-trades-table")
    assert [lot] = Floki.find(lots_table, "tbody tr")

    for column <- 5..9 do
      assert [cell] = Floki.find(lot, "td:nth-child(#{column})")
      assert class_of(cell) =~ "is-flat", "lot column #{column}"
      refute class_of(cell) =~ ~r/is-positive|is-negative/, "lot column #{column}"
      refute text(cell) =~ ~r/[+-]/, "lot column #{column}"
    end

    assert text(Floki.find(lot, "td:nth-child(5)")) == "0.00"
    assert text(Floki.find(lot, "td:nth-child(6)")) == "0.0%"

    trade = closed_row(doc, "2024-01-02")

    for column <- 7..9 do
      assert [cell] = Floki.find(trade, "td:nth-child(#{column})")
      assert class_of(cell) =~ "is-flat", "trade column #{column}"
      refute class_of(cell) =~ ~r/is-positive|is-negative/, "trade column #{column}"
    end

    assert Enum.map(7..9, &text(Floki.find(trade, "td:nth-child(#{&1})"))) ==
             ["0.0%", "0.00", "0.0%"]

    phone = phone_row(doc, "2024-01-02")
    assert [figure] = Floki.find(phone, ".phone-row__figure")
    assert text(figure) == "0.00 EUR"
    assert class_of(figure) =~ "is-flat"
    refute class_of(figure) =~ ~r/is-positive|is-negative/
    assert text(Floki.find(phone, ".phone-row__figure2")) == "0.0% · 0.0% p.\u00A0a."

    assert phone |> Floki.find(".phone-row__figure2 span") |> Enum.map(&class_of/1) ==
             ["is-flat", "is-flat"]

    unpriced = create_security!(name: "Kestrel Robotik SE", ticker: "KRS")
    buy!(world, unpriced, quantity: "40", price: "52.10", date: ~D[2024-03-14])

    {:ok, unpriced_view, _html} = live(conn, "/securities/#{unpriced.id}?tab=trades")

    assert [unpriced_lot] =
             unpriced_view
             |> document()
             |> Floki.find("#detail-tab-panel-trades table.detail-trades-table tbody tr")

    assert [percent] = Floki.find(unpriced_lot, "td:nth-child(6)")
    assert text(percent) == "—"
    refute class_of(percent) =~ ~r/is-positive|is-negative|is-flat/
  end

  # User story (#1074's trades half, the Sprint 19 U2 review):
  # As a local portfolio maintainer reading the English page,
  # I want the unit's plural decided on the quantity as it is shown,
  # so that a quantity that rounds to one at four places reads "1.0000
  # unit", never "1.0000 units".
  #
  # Acceptance criteria:
  # - A closed trade and an unmatched sell of 0.99996 units read "1.0000
  #   unit" in the phone row and in the note's list.
  test "a quantity that rounds to one unit reads unit", %{conn: conn} do
    world = base_world(name: "Round Tab", cash_name: "Girokonto", depot_name: "Depot 1")
    deposit!(world, "5000", ~D[2026-01-02])
    near = create_security!(name: "Nearshore Cables AG", ticker: "NSC")
    buy!(world, near, quantity: "0.99996", price: "80", date: ~D[2026-01-12])
    sell!(world, near, quantity: "0.99996", price: "86", date: ~D[2026-05-20])
    deliver!(world, near, "0.99996", ~D[2026-08-01])
    sell!(world, near, quantity: "0.99996", price: "90", date: ~D[2026-08-24])

    {:ok, view, _html} = live(conn, "/securities/#{near.id}?tab=trades")
    doc = document(view)

    assert text(Floki.find(phone_row(doc, "2026-01-12"), ".phone-row__ids")) ==
             "1.0000 unit · 128 days"

    assert doc
           |> Floki.find("#detail-closed-trades-note .excluded-list li span.num")
           |> Enum.map(&text/1) == ["2026-08-24", "1.0000 unit"]

    refute render(view) =~ "1.0000 units"
  end

  # Acceptance criteria (board rules ① to ④, the CSS the pick adds):
  # - Sign colour and the muted dash inside this table (`.data-table tbody td
  #   { color }` outranks the bare classes): since #1010 the sign colour is
  #   the general `.data-table td.is-positive / .is-negative`, the dash keeps
  #   its table-scoped rule.
  # - The note's list has two columns at every width; the basis line keeps
  #   its distance from the list; the phone rows take the two-child track and
  #   the 560 px block hides the table's wrapper.
  # - `.detail-tab-warning` lost its last user and is gone.
  test "the stylesheet carries the pick's rules" do
    css = File.read!("priv/static/app.css")

    assert css =~ ~r/\n\.data-table td\.is-positive\s*\{[^}]*var\(--color-positive\)/
    assert css =~ ~r/\n\.data-table td\.is-negative\s*\{[^}]*var\(--color-danger\)/

    assert css =~
             ~r/#detail-closed-trades-table td\.trade-pa--na\s*\{[^}]*var\(--color-text-muted\)/

    assert css =~ ~r/#detail-closed-trades-note\s*\{[^}]*margin:\s*0 0 var\(--space-2\)/

    assert css =~
             ~r/#detail-closed-trades-note \.excluded-list\s*\{[^}]*grid-template-columns:\s*auto auto/

    assert css =~
             ~r/#detail-closed-trades-note \.excluded-list li > :first-child\s*\{[^}]*grid-column:\s*auto/

    assert css =~ ~r/#detail-closed-trades-basis\s*\{[^}]*margin-top:\s*var\(--space-2\)/
    assert css =~ ~r/#detail-closed-trades-phone-rows \.phone-row\s*\{[^}]*minmax\(0, 1fr\) auto/

    [phone_block] =
      Regex.run(~r/@media \(max-width: 560px\) \{\s*\/\* phone lists.*?\n\}/s, css)

    assert phone_block =~ "#detail-closed-trades-table-wrap"
    refute css =~ ".detail-tab-warning"
  end
end
