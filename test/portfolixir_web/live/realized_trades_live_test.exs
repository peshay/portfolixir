defmodule PortfolixirWeb.RealizedTradesLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, sell!: 3]

  # User story (#807; review C10, signed by Sprint 13's D-3 — the facet IS
  # the Trades view, and the `needs-decision` label comes off):
  # As a local portfolio maintainer,
  # I want the Realized gains facet to open on the closed trades and three
  # figures,
  # so that the facet shows what its name promises instead of one number in
  # a year × month matrix.
  #
  # Acceptance criteria:
  # - The facet opens with the realised total, the hit rate and the average
  #   holding period, then the trades list; each row links to that security's
  #   Trades tab.
  # - The matrix keeps its numbers, behind a "Realized per period" disclosure.

  defp seed_closed_trade! do
    world = base_world(name: "Facet World", cash_name: "FW Cash", depot_name: "FW Depot")
    winner = create_security!(name: "Winner Co", ticker: "WIN")
    deposit!(world, "100000", ~D[2026-01-01])
    buy!(world, winner, quantity: "10", price: "100", date: ~D[2026-01-05])
    sell!(world, winner, quantity: "10", price: "150", date: ~D[2026-03-06])
    winner
  end

  test "the facet opens on the trades and the three figures", %{conn: conn} do
    winner = seed_closed_trade!()
    {:ok, view, _html} = live(conn, "/cashflow?tab=realized")

    assert has_element?(view, "#realized-figures [data-role='realized-total']")
    assert has_element?(view, "#realized-figures [data-role='realized-hit-rate']")
    assert has_element?(view, "#realized-figures [data-role='realized-holding-period']")

    figures = view |> element("#realized-figures") |> render()
    assert figures =~ "500"
    assert figures =~ "100"

    rows = view |> element("#realized-trades-table") |> render()
    assert rows =~ "Winner Co"
    assert rows =~ "2026-01-05"
    assert rows =~ "2026-03-06"

    assert has_element?(
             view,
             "#realized-trades-table a[href='/securities/#{winner.id}?tab=trades']"
           )

    # The matrix keeps its numbers, behind the disclosure — and the section
    # keeps a heading on the ramp rather than letting the summary be it.
    assert view |> element("#realized-annual h2") |> render() =~ "Realized per period"
    assert has_element?(view, "#realized-annual-disclosure summary", "Year and month matrix")
    assert view |> element("#realized-annual") |> render() =~ "2026"
  end

  # User story (#984 rescoped, Sprint 17 T1b; UX-DR25, board G1 rule ⑤):
  # As a local portfolio maintainer with an imported history,
  # I want the sells no buy could be matched to named where the totals are
  # read,
  # so that a sale of delivered-in shares missing from every figure is a
  # stated gap, not a silent one.
  #
  # Acceptance criteria:
  # - An attention note leads the section with the count and the reason,
  #   after the currency-exclusion note when both appear, before the figures.
  # - Its disclosure lists each sell as security · date · quantity.
  # - It carries no remedy control: there is none (UX-DR25 clause 3); the
  #   basis line under the list states the limit.
  # - With no unmatched sell there is no note.
  # - The note speaks of the unmatched quantity: a sale larger than the
  #   shares bought keeps its matched part as a trade (closing act γ, the
  #   correctness lens's note).
  test "the sells no buy was matched to are named after the currency note", %{conn: conn} do
    world = base_world(name: "Delivered Facet", cash_name: "DF Cash", depot_name: "DF Depot")
    delivered = create_security!(name: "Delivered Holdings", ticker: "DHD")
    deposit!(world, "100000", ~D[2026-01-01])

    {:ok, _delivery} =
      Portfolixir.Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        security_id: delivered.id,
        type: "inbound_delivery",
        date: ~D[2026-01-10],
        quantity: "15",
        currency_code: "EUR"
      })

    sell!(world, delivered, quantity: "15", price: "20", date: ~D[2026-05-12])

    # A pound sale with no stored rate on its close date: the currency note.
    pound = create_security!(name: "Pound Holdings", ticker: "PHD", currency: "GBP")

    gbp =
      Map.merge(
        world,
        Portfolixir.WorldFixtures.add_depot(world.portfolio,
          currency: "GBP",
          cash_name: "GBP Cash",
          depot_name: "GBP Depot"
        )
      )

    buy!(gbp, pound, quantity: "2", price: "10", date: ~D[2026-01-09], currency: "GBP")
    sell!(gbp, pound, quantity: "2", price: "30", date: ~D[2026-02-20], currency: "GBP")

    {:ok, view, _html} = live(conn, "/cashflow?tab=realized")

    assert has_element?(view, "#realized-unmatched[data-role='realized-unmatched']")
    note = view |> element("#realized-unmatched") |> render()

    assert note =~
             "1 sale has no matched buy for all or part of its quantity (shares from an inbound delivery, for example): that quantity is not included in the three figures, the rows or the matrix."

    assert note =~ "Delivered Holdings"
    assert note =~ "2026-05-12"
    assert note =~ "15.0000 units"
    refute has_element?(view, "#realized-unmatched button")

    section = view |> element("#realized-trades") |> render()
    {excluded_at, _} = :binary.match(section, "realized-excluded")
    {unmatched_at, _} = :binary.match(section, "realized-unmatched")
    {figures_at, _} = :binary.match(section, "realized-figures")
    assert excluded_at < unmatched_at and unmatched_at < figures_at

    # In German, the board's copy and the German date and quantity forms.
    de_conn = Plug.Test.put_req_cookie(Phoenix.ConnTest.build_conn(), "portfolixir_locale", "de")
    {:ok, de_view, _html} = live(de_conn, "/cashflow?tab=realized")
    de_note = de_view |> element("#realized-unmatched") |> render()

    assert de_note =~
             "1 Verkauf hat für seine ganze Stückzahl oder einen Teil davon keinen zugeordneten Kauf (z. B. aus einer Einlieferung): Diese Stückzahl ist in keiner der drei Kennzahlen, keiner Zeile und nicht in der Matrix enthalten."

    assert de_note =~ "Der Verkauf"
    assert de_note =~ "12.05.2026"
    assert de_note =~ "15,0000 Stück"
  end

  test "with every sell matched there is no unmatched-sells note", %{conn: conn} do
    _winner = seed_closed_trade!()
    {:ok, view, _html} = live(conn, "/cashflow?tab=realized")

    refute has_element?(view, "#realized-unmatched")
  end

  # Acceptance criteria (the honest empty state): the average of nothing is
  # not zero, so the two derived figures read as absent rather than as 0 %
  # and 0 days.
  test "with no closed trades the derived figures read as absent, not as zero", %{conn: conn} do
    _empty = base_world(name: "No Trades", cash_name: "NT Cash", depot_name: "NT Depot")
    {:ok, view, _html} = live(conn, "/cashflow?tab=realized")

    assert view |> element("[data-role='realized-hit-rate']") |> render() =~ "—"
    assert view |> element("[data-role='realized-holding-period']") |> render() =~ "—"
    refute has_element?(view, "#realized-trades-table")
    assert has_element?(view, "#realized-trades .empty-state")
  end

  # Three closed trades on the facet (#984, pick G1-A): two held 730 days,
  # one gaining 20 % a year (1440 / 1000 over two years) and one losing 20 %
  # a year (640 / 1000), and one held 30 days, which is not annualized.
  defp seed_reach! do
    world = base_world(name: "Reach World", cash_name: "RW Cash", depot_name: "RW Depot")
    long = create_security!(name: "Longhold Industries", ticker: "LHI")
    fade = create_security!(name: "Slowfade Materials", ticker: "SFM")
    quick = create_security!(name: "Quickturn Retail", ticker: "QTR")
    deposit!(world, "100000", ~D[2023-01-02])

    buy!(world, long, quantity: "10", price: "100", date: ~D[2024-01-02])
    sell!(world, long, quantity: "10", price: "144", date: ~D[2026-01-01])
    buy!(world, fade, quantity: "10", price: "100", date: ~D[2023-06-01])
    sell!(world, fade, quantity: "10", price: "64", date: ~D[2025-05-31])
    buy!(world, quick, quantity: "4", price: "50", date: ~D[2026-02-01])
    sell!(world, quick, quantity: "4", price: "45", date: ~D[2026-03-03])

    %{long: long, fade: fade, quick: quick}
  end

  defp row(view, name) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find("#realized-trades-table tbody tr")
    |> Enum.find(&(Floki.text(&1) =~ name))
  end

  # User story (#984 rescoped, Sprint 17 T2; board G1, variant A picked):
  # As a local portfolio maintainer asking whether a trade was worth it,
  # I want the facet called "Trades" and a "p. a." column beside each result,
  # so that a two-week trade and a two-year trade with the same percentage no
  # longer read alike, and the list is found under the name I look for.
  #
  # Acceptance criteria:
  # - The facet switch reads "Trades"; the URL stays /cashflow?tab=realized.
  # - The table carries "p. a." directly left of "Result".
  # - A trade held 365 days or more shows its annualized return in its sign
  #   colour; a shorter one shows a muted dash whose reason rides the cell's
  #   title and a visually hidden sentence.
  # - A basis line under the list states the rules: deliveries open no lot,
  #   fees and taxes in cost and proceeds, income while open not included,
  #   p. a. only from 365 days of holding.
  test "the facet reads Trades and carries the p. a. column left of Result", %{conn: conn} do
    seed_reach!()
    {:ok, view, _html} = live(conn, "/cashflow?tab=realized")

    assert has_element?(
             view,
             "[data-role='cashflow-facets'] a[href='/cashflow?tab=realized'][aria-current='true']",
             "Trades"
           )

    headers =
      view
      |> render()
      |> Floki.parse_document!()
      |> Floki.find("#realized-trades-table thead th")
      |> Enum.map(&String.trim(Floki.text(&1)))

    assert Enum.take(headers, -2) == ["p. a.", "Result"]

    long = row(view, "Longhold Industries")
    assert [pa] = Floki.find(long, "td.trade-pa")
    assert Floki.attribute(pa, "class") |> hd() =~ "is-positive"
    # #1089 (Sprint 19 U2): a gain carries its "+".
    assert String.trim(Floki.text(pa)) == "+20.0%"

    fade = row(view, "Slowfade Materials")
    assert [pa] = Floki.find(fade, "td.trade-pa")
    assert Floki.attribute(pa, "class") |> hd() =~ "is-negative"
    assert String.trim(Floki.text(pa)) == "-20.0%"

    quick = row(view, "Quickturn Retail")
    assert [dash] = Floki.find(quick, "td.trade-pa.trade-pa--na")
    assert Floki.attribute(dash, "title") == ["Not annualized under one year of holding"]
    assert Floki.text(Floki.find(dash, "[aria-hidden='true']")) == "—"

    assert Floki.text(Floki.find(dash, ".visually-hidden")) ==
             "not annualized, under one year of holding"

    basis =
      view |> element("#realized-trades > p.summary-basis[data-role='trades-basis']") |> render()

    assert basis =~ "Deliveries open no lot"
    assert basis =~ "fees and taxes in cost and proceeds"
    assert basis =~ "income received while a trade was open not included"
    assert basis =~ "p. a. only from 365 days of holding"
  end

  # Acceptance criteria (UX-DR27, board G1 rule 3):
  # - Beside the table, two-line rows for under 560 px: the name over
  #   "bought → sold · days", the result over the period return and, from
  #   365 days, " · p. a." — no dash on the phone, the basis line says why.
  # - The table keeps its own wrapper, which the phone width hides.
  test "the list carries two-line phone rows beside its table", %{conn: conn} do
    seed_reach!()
    {:ok, view, _html} = live(conn, "/cashflow?tab=realized")

    assert has_element?(view, "#realized-trades-table-wrapper #realized-trades-table")

    rows =
      view
      |> render()
      |> Floki.parse_document!()
      |> Floki.find("#realized-trades-phone-rows li.phone-row")

    assert length(rows) == 3

    long = Enum.find(rows, &(Floki.text(&1) =~ "Longhold Industries"))
    assert Floki.text(Floki.find(long, ".phone-row__ids")) =~ "2024-01-02 → 2026-01-01 · 730 days"
    assert Floki.text(Floki.find(long, ".phone-row__figure")) =~ "440.00"
    figure2 = Floki.text(Floki.find(long, ".phone-row__figure2"))
    assert figure2 =~ "44.0%"
    assert figure2 =~ "20.0% p. a."

    quick = Enum.find(rows, &(Floki.text(&1) =~ "Quickturn Retail"))
    assert Floki.text(Floki.find(quick, ".phone-row__figure2")) =~ "-10.0%"
    refute Floki.text(Floki.find(quick, ".phone-row__figure2")) =~ "p. a."
    assert Floki.attribute(Floki.find(quick, "a.phone-row__target"), "href") != []
  end

  # Acceptance criteria (the German page, board G1's copy):
  # - The switch, the column, the dash's reason and the basis line in German.
  test "the Trades facet is German where the page is", %{conn: conn} do
    seed_reach!()
    de_conn = Plug.Test.put_req_cookie(conn, "portfolixir_locale", "de")
    {:ok, view, _html} = live(de_conn, "/cashflow?tab=realized")

    assert has_element?(view, "[data-role='cashflow-facets'] a[aria-current='true']", "Trades")

    assert has_element?(
             view,
             ".topbar-page p",
             "Abgeschlossene Trades und ihr realisiertes Ergebnis"
           )

    assert has_element?(view, "[data-role='facet-basis']", "FIFO je Wertpapier · alle Depots")

    quick = row(view, "Quickturn Retail")

    assert Floki.attribute(Floki.find(quick, "td.trade-pa--na"), "title") == [
             "Unter einem Jahr Haltedauer nicht annualisiert"
           ]

    assert String.trim(Floki.text(Floki.find(row(view, "Longhold Industries"), "td.trade-pa"))) ==
             "+20,0%"

    basis = view |> element("[data-role='trades-basis']") |> render()
    assert basis =~ "Einlieferungen eröffnen keinen Lot"
    assert basis =~ "p. a. erst ab 365 Tagen Haltedauer"
  end

  defp text(nodes),
    do: nodes |> Floki.text(sep: " ") |> String.replace(~r/\s+/, " ") |> String.trim()

  defp class_of(nodes), do: nodes |> Floki.attribute("class") |> List.first("")

  defp de_conn(conn), do: Plug.Test.put_req_cookie(conn, "portfolixir_locale", "de")

  defp phone_row(view, name) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find("#realized-trades-phone-rows li.phone-row")
    |> Enum.find(&(Floki.text(&1) =~ name))
  end

  # The phone row's figure line as markup, not as joined text: each coloured
  # span as {class, text}, each bare text node trimmed, whitespace dropped.
  defp figure2_nodes(row) do
    [{_tag, _attrs, children}] = Floki.find(row, ".phone-row__figure2")

    children
    |> Enum.map(fn
      text when is_binary(text) -> String.trim(text)
      {"span", _attrs, _children} = span -> {class_of(span), text(span)}
    end)
    |> Enum.reject(&(&1 == ""))
  end

  # User story (#1082, Sprint 19 PR γ U2; plan D-4, board
  # ux-design-2026-10-04/04-trades, pick J4 A):
  # As a newcomer who followed "All trades →" from the Overview, or who
  # opened the Trades facet on a phone,
  # I want the top bar to say "Trades" while that facet is open,
  # so that the page carries its name where every page carries it, even at
  # 390 px, where the subtitle is hidden.
  #
  # Acceptance criteria:
  # - On /cashflow?tab=realized the top bar's title (its live region's h1)
  #   reads "Trades"; the subtitle still names the facet.
  # - Income, Deposits & withdrawals and Costs keep "Cash flow".
  # - Switching to the facet in place retitles the page.
  # - The German page reads "Trades" on the facet and "Cashflow" elsewhere.
  # - The route and the facet switch are unchanged.
  test "the top bar reads Trades while the Trades facet is open", %{conn: conn} do
    seed_closed_trade!()

    {:ok, view, _html} = live(conn, "/cashflow?tab=realized")
    assert has_element?(view, ".topbar-page[aria-live='polite'] h1#app-topbar-title", "Trades")
    refute has_element?(view, "#app-topbar-title", "Cash flow")
    assert has_element?(view, "#app-topbar-subtitle", "Closed trades and their realized result")

    for path <- ["/cashflow", "/cashflow?tab=flows", "/cashflow?tab=costs"] do
      {:ok, other, _html} = live(conn, path)
      assert has_element?(other, "#app-topbar-title", "Cash flow"), path
    end

    {:ok, income, _html} = live(conn, "/cashflow")

    income
    |> element("[data-role='cashflow-facets'] a[href='/cashflow?tab=realized']")
    |> render_click()

    assert has_element?(income, "#app-topbar-title", "Trades")
    assert has_element?(income, "[data-role='cashflow-facets'] a[aria-current='true']", "Trades")

    {:ok, de_trades, _html} = live(de_conn(conn), "/cashflow?tab=realized")
    assert has_element?(de_trades, "#app-topbar-title", "Trades")

    {:ok, de_income, _html} = live(de_conn(conn), "/cashflow")
    assert has_element?(de_income, "#app-topbar-title", "Cashflow")
  end

  # User story (#1089, Sprint 19 PR γ U2; board 04, before/after):
  # As a local portfolio maintainer reading the Trades facet — and as one who
  # cannot tell its green from its red —
  # I want every result, percent and p. a. figure to carry its sign, and a
  # phone row without p. a. to say that its percent is the whole holding
  # period's,
  # so that a gain reads as a gain without its colour, and "-10,0%" no
  # longer stands bare on a phone.
  #
  # Acceptance criteria:
  # - The table's result, its percent and the p. a. cell carry an explicit
  #   "+" when positive, in the Overview card's form; a loss keeps its "-".
  # - The phone row does the same; a row without p. a. ends its period
  #   return in "total", the card's word.
  # - The list's basis line names both limits of p. a.: 365 days of holding,
  #   and only where a rate solves the flows.
  # - "Realized total" carries its sign and its sign colour, never the accent
  #   (board 04, found while drawing 1).
  test "every figure on the facet carries its sign, and a bare percent says total",
       %{conn: conn} do
    seed_reach!()
    {:ok, view, _html} = live(conn, "/cashflow?tab=realized")

    long = row(view, "Longhold Industries")
    assert text(Floki.find(long, "td.trade-pa")) == "+20.0%"
    assert text(Floki.find(long, "td[data-role='trade-result']")) == "+440.00 EUR +44.0%"

    fade = row(view, "Slowfade Materials")
    assert text(Floki.find(fade, "td.trade-pa")) == "-20.0%"
    assert text(Floki.find(fade, "td[data-role='trade-result']")) == "-360.00 EUR -36.0%"

    long_phone = phone_row(view, "Longhold Industries")
    assert text(Floki.find(long_phone, ".phone-row__figure")) == "+440.00 EUR"
    assert text(Floki.find(long_phone, ".phone-row__figure2")) == "+44.0% · +20.0% p. a."

    quick_phone = phone_row(view, "Quickturn Retail")
    assert text(Floki.find(quick_phone, ".phone-row__figure")) == "-20.00 EUR"
    assert text(Floki.find(quick_phone, ".phone-row__figure2")) == "-10.0% total"

    assert quick_phone |> Floki.find(".phone-row__figure2 span") |> Enum.map(&class_of/1) ==
             ["decimal-negative"]

    # "total" is the row's word, not the figure's (Sprint 19 U2 review): it
    # sits outside the coloured span, in the line's muted ink.
    assert figure2_nodes(quick_phone) == [{"decimal-negative", "-10.0%"}, "total"]

    assert figure2_nodes(long_phone) == [
             {"decimal-positive", "+44.0%"},
             "·",
             {"decimal-positive", "+20.0%"},
             "p. a."
           ]

    assert text(Floki.find(render(view) |> Floki.parse_document!(), "[data-role='trades-basis']")) =~
             "p. a. only from 365 days of holding and only where a rate solves the flows"

    assert [total] =
             view
             |> render()
             |> Floki.parse_document!()
             |> Floki.find("#realized-figures strong[data-role='realized-total']")

    assert text(total) == "+60.00 EUR"
    assert class_of(total) =~ "is-positive"
  end

  # Acceptance criteria (#1089, the second reason for a bare percent; board
  # 04's Tamarisk row, German):
  # - A trade held 600 days that no rate solves (a total loss) reads
  #   "-100,0% gesamt" on the phone, with no p. a.
  # - A realized total below zero reads with its "-" in the loss colour; the
  #   basis line names the second limit in German.
  test "a total loss reads gesamt on the German phone row", %{conn: conn} do
    world = base_world(name: "Loss Facet", cash_name: "LF Cash", depot_name: "LF Depot")
    tamarisk = create_security!(name: "Tamarisk Mining Ltd", ticker: "TML")
    deposit!(world, "10000", ~D[2024-01-02])
    buy!(world, tamarisk, quantity: "10", price: "40", date: ~D[2024-11-02])
    sell!(world, tamarisk, quantity: "10", price: "0", date: ~D[2026-06-25])

    {:ok, view, _html} = live(de_conn(conn), "/cashflow?tab=realized")

    loss = phone_row(view, "Tamarisk Mining Ltd")
    assert text(Floki.find(loss, ".phone-row__ids")) =~ "600 Tage"
    assert text(Floki.find(loss, ".phone-row__figure")) == "-400,00 EUR"
    assert text(Floki.find(loss, ".phone-row__figure2")) == "-100,0% gesamt"
    assert figure2_nodes(loss) == [{"decimal-negative", "-100,0%"}, "gesamt"]

    assert text(Floki.find(row(view, "Tamarisk Mining Ltd"), "td.trade-pa")) =~
             "kein Zinssatz löst die Zahlungen"

    doc = view |> render() |> Floki.parse_document!()
    assert [total] = Floki.find(doc, "strong[data-role='realized-total']")
    assert text(total) == "-400,00 EUR"
    assert class_of(total) =~ "is-negative"

    assert text(Floki.find(doc, "[data-role='trades-basis']")) =~
             "p. a. erst ab 365 Tagen Haltedauer und nur, wo ein Zinssatz die Zahlungen löst"
  end

  # User story (#1089; the PR γ closing act, first-look persona):
  # As the operator reading my trades on a phone, by eye or with a screen
  # reader,
  # I want a trade without p. a. to say why on its phone row, as its table
  # row does at a desktop width,
  # so that Tamarisk's "-100,0% gesamt" after 600 days of holding is not
  # left without its reason at 390 px.
  #
  # Acceptance criteria:
  # - A phone row without p. a. carries the table dash's reason, a visually
  #   hidden sentence after its figures: "nicht annualisiert, unter einem
  #   Jahr Haltedauer" under 365 days, "keine annualisierte Rendite, kein
  #   Zinssatz löst die Zahlungen dieses Trades" for a trade no rate solves.
  # - The visible row is unchanged ("-100,0% gesamt"), and a row with p. a.
  #   carries no such sentence.
  test "a phone row without p. a. says why, as the table's dash does", %{conn: conn} do
    seed_reach!()
    world = base_world(name: "Why World", cash_name: "WW Cash", depot_name: "WW Depot")
    tamarisk = create_security!(name: "Tamarisk Mining Ltd", ticker: "TML")
    deposit!(world, "10000", ~D[2024-01-02])
    buy!(world, tamarisk, quantity: "10", price: "40", date: ~D[2024-11-02])
    sell!(world, tamarisk, quantity: "10", price: "0", date: ~D[2026-06-25])

    {:ok, view, _html} = live(de_conn(conn), "/cashflow?tab=realized")

    why = fn name ->
      view |> phone_row(name) |> Floki.find(".visually-hidden[data-role='pa-absent']") |> text()
    end

    assert why.("Tamarisk Mining Ltd") ==
             "keine annualisierte Rendite, kein Zinssatz löst die Zahlungen dieses Trades"

    assert why.("Quickturn Retail") == "nicht annualisiert, unter einem Jahr Haltedauer"
    assert why.("Longhold Industries") == ""

    loss = phone_row(view, "Tamarisk Mining Ltd")
    assert text(Floki.find(loss, ".phone-row__figure2")) == "-100,0% gesamt"

    # The same reason the table's dash carries for the same trade.
    assert text(Floki.find(row(view, "Tamarisk Mining Ltd"), "td.trade-pa .visually-hidden")) ==
             why.("Tamarisk Mining Ltd")
  end

  # Acceptance criteria (board 04, found while drawing 1, the zero case):
  # - A realized total of exactly zero is directionless: no sign, body ink
  #   (`is-flat`), still never the accent.
  test "a realized total of zero carries no sign and no accent", %{conn: conn} do
    _empty = base_world(name: "Flat Facet", cash_name: "FF Cash", depot_name: "FF Depot")
    {:ok, view, _html} = live(conn, "/cashflow?tab=realized")

    doc = view |> render() |> Floki.parse_document!()
    assert [total] = Floki.find(doc, "strong[data-role='realized-total']")
    assert text(total) == "0.00 EUR"
    assert class_of(total) =~ "is-flat"
  end

  # Acceptance criteria (#1089 and board 04, the Sprint 19 U2 review: a
  # figure's sign and its colour are decided on the figure as displayed):
  # - A break-even trade reads "0.00 EUR" over "0.0%", and "0.0%" p. a. from
  #   a year of holding, with no sign: its table cells and its phone figures
  #   are `is-flat`, never a gain or loss colour.
  # - A trade whose result rounds to zero at the places it is shown at — a
  #   gain of 0.004 EUR, a loss of 0.003 EUR — reads the same: no "+0.0", no
  #   "-0.00", no gain or loss colour.
  # - A realized total that rounds to zero is unsigned and `is-flat`, not the
  #   gain colour.
  test "a trade or a total that rounds to zero reads unsigned and is-flat", %{conn: conn} do
    world = base_world(name: "Even Facet", cash_name: "EF Cash", depot_name: "EF Depot")
    deposit!(world, "10000", ~D[2024-01-02])
    level = create_security!(name: "Level Lines AG", ticker: "LVL")
    gain = create_security!(name: "Hairline Gain plc", ticker: "HLG")
    loss = create_security!(name: "Hairline Loss SE", ticker: "HLL")

    buy!(world, level, quantity: "10", price: "50", date: ~D[2024-02-01])
    sell!(world, level, quantity: "10", price: "50", date: ~D[2025-04-01])
    buy!(world, gain, quantity: "1", price: "100", date: ~D[2024-01-02])
    sell!(world, gain, quantity: "1", price: "100.004", date: ~D[2026-01-01])
    buy!(world, loss, quantity: "1", price: "100", date: ~D[2026-02-02])
    sell!(world, loss, quantity: "1", price: "99.997", date: ~D[2026-03-04])

    {:ok, view, _html} = live(conn, "/cashflow?tab=realized")

    for name <- ["Level Lines AG", "Hairline Gain plc", "Hairline Loss SE"] do
      table_row = row(view, name)
      assert [result] = Floki.find(table_row, "td[data-role='trade-result']")
      assert text(result) == "0.00 EUR 0.0%", name
      assert class_of(result) =~ "is-flat", name
      refute class_of(result) =~ ~r/is-positive|is-negative/, name

      phone = phone_row(view, name)
      assert [figure] = Floki.find(phone, ".phone-row__figure")
      assert text(figure) == "0.00 EUR", name
      assert class_of(figure) =~ "is-flat", name
      refute class_of(figure) =~ ~r/is-positive|is-negative/, name
    end

    for name <- ["Level Lines AG", "Hairline Gain plc"] do
      assert [pa] = Floki.find(row(view, name), "td.trade-pa")
      assert text(pa) == "0.0%", name
      assert class_of(pa) =~ "is-flat", name
      refute class_of(pa) =~ ~r/is-positive|is-negative/, name

      assert figure2_nodes(phone_row(view, name)) ==
               [{"is-flat", "0.0%"}, "·", {"is-flat", "0.0%"}, "p. a."],
             name
    end

    assert figure2_nodes(phone_row(view, "Hairline Loss SE")) == [{"is-flat", "0.0%"}, "total"]

    doc = view |> render() |> Floki.parse_document!()
    assert [total] = Floki.find(doc, "strong[data-role='realized-total']")
    assert text(total) == "0.00 EUR"
    assert class_of(total) =~ "is-flat"
    refute class_of(total) =~ ~r/is-positive|is-negative/

    trades = text(Floki.find(doc, "#realized-trades-table, #realized-trades-phone-rows"))
    refute trades =~ "+0."
    refute trades =~ "-0."
  end

  # Acceptance criteria (#1082, the empty state):
  # - With no depot and no cash account the page is its empty state, titled
  #   "Cash flow" whichever facet the address names, the Trades facet's
  #   included: there is no facet to name.
  test "the empty state is titled Cash flow, at the Trades address too", %{conn: conn} do
    for path <- ["/cashflow?tab=realized", "/cashflow"] do
      {:ok, view, _html} = live(conn, path)
      assert has_element?(view, ".workspace-section.empty-state"), path
      assert has_element?(view, "#app-topbar-title", "Cash flow"), path
      refute has_element?(view, "#app-topbar-title", "Trades"), path
    end
  end

  # User story (#1074's trades half, Sprint 19 PR γ U2; board 04):
  # As a local portfolio maintainer reading the English page,
  # I want a quantity of one to read "unit",
  # so that the unmatched-sells list does not say "1.0000 units".
  #
  # Acceptance criteria:
  # - One unit reads "1.0000 unit"; any other quantity, a fraction included,
  #   reads "units" (U1's count rule, `plural_count/1`).
  # - The plural follows the quantity as displayed, at four places (Sprint 19
  #   U2 review): 0.99996 reads "1.0000 unit", never "1.0000 units".
  # - German reads "Stück" in both forms.
  test "an unmatched sell of one unit reads unit", %{conn: conn} do
    world = base_world(name: "Unit Facet", cash_name: "UF Cash", depot_name: "UF Depot")
    deposit!(world, "10000", ~D[2026-01-01])
    single = create_security!(name: "Brightwater Utilities plc", ticker: "BWU")
    half = create_security!(name: "Saltmarsh Logistics SE", ticker: "SLS")
    near = create_security!(name: "Nearshore Cables AG", ticker: "NSC")

    for {security, quantity, delivered, sold} <- [
          {single, "1", ~D[2026-08-01], ~D[2026-08-24]},
          {half, "0.5", ~D[2026-07-01], ~D[2026-08-04]},
          {near, "0.99996", ~D[2026-06-01], ~D[2026-06-15]}
        ] do
      {:ok, _delivery} =
        Portfolixir.Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
          portfolio_id: world.portfolio.id,
          securities_account_id: world.depot.id,
          security_id: security.id,
          type: "inbound_delivery",
          date: delivered,
          quantity: quantity,
          currency_code: "EUR"
        })

      sell!(world, security, quantity: quantity, price: "20", date: sold)
    end

    {:ok, view, _html} = live(conn, "/cashflow?tab=realized")
    items = view |> element("[data-role='realized-unmatched-list']") |> render()
    assert items =~ ~r/1\.0000 unit\s*</
    assert items =~ "0.5000 units"
    refute items =~ "1.0000 units"

    quantities =
      view
      |> render()
      |> Floki.parse_document!()
      |> Floki.find("[data-role='realized-unmatched-list'] li")
      |> Map.new(fn li -> {text(Floki.find(li, "span:first-child")), li} end)
      |> Map.new(fn {name, li} ->
        {name, li |> Floki.find("span.num") |> List.last() |> text()}
      end)

    assert quantities["Nearshore Cables AG"] == "1.0000 unit"
    assert quantities["Brightwater Utilities plc"] == "1.0000 unit"
    assert quantities["Saltmarsh Logistics SE"] == "0.5000 units"

    {:ok, de_view, _html} = live(de_conn(conn), "/cashflow?tab=realized")
    de_items = de_view |> element("[data-role='realized-unmatched-list']") |> render()
    assert de_items =~ "1,0000 Stück"
    assert de_items =~ "0,5000 Stück"
  end

  # User story (board 04, found while drawing 2; Sprint 19 PR γ U2):
  # As a local portfolio maintainer who came from the Overview card's note
  # on a sale with no exchange rate,
  # I want the facet's note to name the same missing thing,
  # so that "kein gespeicherter Kurs" (a price) on the facet does not
  # contradict "Wechselkurs" (an exchange rate) on the card.
  #
  # Acceptance criteria:
  # - The German currency note says "kein gespeicherter Wechselkurs".
  # - The facet's ⓘ speaks of the exchange rate too.
  test "the German currency note names the exchange rate", %{conn: conn} do
    world = base_world(name: "Rate Facet", cash_name: "RF Cash", depot_name: "RF Depot")
    pound = create_security!(name: "Harborline Freight Inc.", ticker: "HFI", currency: "GBP")

    gbp =
      Map.merge(
        world,
        Portfolixir.WorldFixtures.add_depot(world.portfolio,
          currency: "GBP",
          cash_name: "GBP Cash",
          depot_name: "GBP Depot"
        )
      )

    buy!(gbp, pound, quantity: "2", price: "10", date: ~D[2026-01-09], currency: "GBP")
    sell!(gbp, pound, quantity: "2", price: "30", date: ~D[2026-02-20], currency: "GBP")

    {:ok, view, _html} = live(de_conn(conn), "/cashflow?tab=realized")

    note = view |> element("#realized-excluded") |> render()

    assert note =~
             "1 Verkauf konnte nicht konvertiert werden — kein gespeicherter Wechselkurs an " <>
               "seinem Schlussdatum — und ist aus jeder Summe ausgeschlossen: Harborline Freight Inc."

    info = view |> element("[data-role='facet-composition']") |> render()
    assert info =~ "zum Wechselkurs seines eigenen Schlusstags"
    assert info =~ "kein Wechselkurs gespeichert"
    refute info =~ "zum Kurs"
  end

  # Acceptance criteria (board G1 rules 1, 2, 3 and 6, the CSS the pick adds):
  # - The dash is muted; the list's basis line has the basis voice; under
  #   560 px the table's wrapper gives way to the rows, which take the
  #   two-child track; the sign colour of Result and p. a. holds in the
  #   table (`.data-table tbody td { color }` outranks the bare class; since
  #   #1010 the general `.data-table td.is-positive / .is-negative` restores
  #   it in every data table and rule 6's scoped copy is retired).
  # - The dash is muted inside the table too, where the same td rule
  #   outranked it (closing act γ D4); the table is a reading table that
  #   fits its wrapper, the name and dates wrapping and the figures not, so
  #   Result stays in view at laptop widths (γ D9).
  test "the stylesheet carries the pick's rules" do
    css = File.read!("priv/static/app.css")

    assert css =~ ~r/\.trade-pa--na\s*\{[^}]*color:\s*var\(--color-text-muted\)/
    assert css =~ ~r/#realized-trades-table td\.trade-pa--na\s*\{[^}]*var\(--color-text-muted\)/
    assert css =~ ~r/\.data-table-wrapper > #realized-trades-table\s*\{[^}]*min-width:\s*0/

    assert css =~
             ~r/#realized-trades-table td\.num,\s*#realized-trades-table th\.num\s*\{[^}]*nowrap/

    assert css =~ ~r/#realized-trades > \.summary-basis[^{]*\{[^}]*font-size:\s*12px/
    assert css =~ ~r/#realized-trades-phone-rows \.phone-row\s*\{[^}]*minmax\(0, 1fr\) auto/
    assert css =~ ~r/\n\.data-table td\.is-positive\s*\{[^}]*var\(--color-positive\)/
    assert css =~ ~r/\n\.data-table td\.is-negative\s*\{[^}]*var\(--color-danger\)/

    [phone_block] =
      Regex.run(~r/@media \(max-width: 560px\) \{\s*\/\* phone lists.*?\n\}/s, css)

    assert phone_block =~ "#realized-trades-table-wrapper"
  end
end
