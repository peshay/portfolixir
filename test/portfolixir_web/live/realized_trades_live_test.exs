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
    assert String.trim(Floki.text(pa)) == "20.0%"

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
             "20,0%"

    basis = view |> element("[data-role='trades-basis']") |> render()
    assert basis =~ "Einlieferungen eröffnen keinen Lot"
    assert basis =~ "p. a. erst ab 365 Tagen Haltedauer"
  end

  # Acceptance criteria (board G1 rules 1, 2, 3 and 6, the CSS the pick adds):
  # - The dash is muted; the list's basis line has the basis voice; under
  #   560 px the table's wrapper gives way to the rows, which take the
  #   two-child track; the sign colour of Result and p. a. is restored in
  #   #realized-trades-table only (`.data-table tbody td { color }`
  #   outranks the bare class elsewhere, a follow-up).
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
    assert css =~ ~r/#realized-trades-table td\.is-positive\s*\{[^}]*var\(--color-positive\)/
    assert css =~ ~r/#realized-trades-table td\.is-negative\s*\{[^}]*var\(--color-danger\)/

    [phone_block] =
      Regex.run(~r/@media \(max-width: 560px\) \{\s*\/\* phone lists.*?\n\}/s, css)

    assert phone_block =~ "#realized-trades-table-wrapper"
  end
end
