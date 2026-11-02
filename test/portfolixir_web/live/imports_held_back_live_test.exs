defmodule PortfolixirWeb.ImportsHeldBackLiveTest do
  # ADR-0050 as amended on 2026-11-01 on the Imports page (#1313; risk-tier:
  # import idempotency, ADR-0036), as the Sprint 22 board
  # `ux-design-2026-11-01-sprint22/03-drawer-import` ② draws it (Q2 = A):
  # the rows of a file another portfolio already holds stand in one
  # collapsed attention group per portfolio at the head of the preview, held
  # back, with a "Take over anyway" switch and the rows one tap away; the
  # mapping rows they alone carry ask for nothing. X1 and X2 of the
  # amendment are pinned here end to end; the domain pins them in
  # `Portfolixir.Imports.HeldBackReimportTest`.
  #
  # The board's world: `kupons-2026.json`, four entries, imported into
  # "Anleihen" by an agent; the page books into "Hauptportfolio". Every name
  # and amount is synthetic.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Mapping
  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  @coupons """
  {
    "version": 1,
    "transactions": [
      {"type": "DEPOSIT", "account": "Coupon-Cash", "date": "2026-03-12",
       "currency": "EUR", "amount": 10000.00},
      {"type": "PURCHASE", "account": "Coupon-Cash", "portfolio": "Coupon-Depot",
       "date": "2026-03-13", "time": "10:00", "currency": "EUR", "amount": 9950.00,
       "shares": 100.0,
       "security": {"name": "Larkspur Rail AG 4,00 % Anleihe 2031",
                    "isin": "XSLARKSPUR33", "currency": "EUR"}},
      {"type": "INTEREST", "account": "Coupon-Cash", "date": "2026-06-30",
       "time": "09:30", "currency": "EUR", "amount": 200.00,
       "security": {"name": "Larkspur Rail AG 4,00 % Anleihe 2031",
                    "isin": "XSLARKSPUR33", "currency": "EUR"}},
      {"type": "INTEREST", "account": "Coupon-Cash", "date": "2026-09-30",
       "time": "09:30", "currency": "EUR", "amount": 200.00,
       "security": {"name": "Larkspur Rail AG 4,00 % Anleihe 2031",
                    "isin": "XSLARKSPUR33", "currency": "EUR"}}
    ]
  }
  """

  # One purchase whose cash, 1000.00, carries a tax refund of 10.00 as a
  # negative TAX unit, which the parser splits off as a companion.
  @refunded_buy """
  {
    "version": 1,
    "transactions": [
      {"type": "PURCHASE", "account": "Refund-Cash", "portfolio": "Refund-Depot",
       "date": "2026-04-14", "time": "11:00", "currency": "EUR", "amount": 1000.00,
       "shares": 10.0,
       "units": [{"type": "TAX", "amount": -10.00}],
       "security": {"name": "Larkspur Rail AG 4,00 % Anleihe 2031",
                    "isin": "XSLARKSPUR33", "currency": "EUR"}}
    ]
  }
  """

  setup do
    main = portfolio!("Hauptportfolio")
    bonds = portfolio!("Anleihen")
    {:ok, preview} = PortfolioPerformance.parse(@coupons, filename: "kupons-2026.json")
    {:ok, %{created_transactions: 4}} = Imports.apply(preview, %{portfolio_id: bonds.id})
    %{main: main, bonds: bonds}
  end

  # User story (#1313; ADR-0050 as amended on 2026-11-01, X1):
  # As the operator whose bond history an agent imported into "Anleihen",
  # I want the Imports page to say so when I drop the file again and to book
  # nothing by default,
  # so that one confirm never books the history twice.
  #
  # Acceptance criteria (board 03 ②, variant A):
  # - One attention note at the head of the preview: "Already imported into
  #   portfolio “Anleihen”: 4 entries — not taken over", its four rows in a
  #   collapsed disclosure (date, kind, account · security, signed amount).
  # - A "Take over anyway" switch, off, with its consequence.
  # - The mapping rows read "4 bookings imported into “Anleihen” · nothing
  #   to create" and ask for no choice.
  # - The confirm books nothing; the done page names the held-back rows.
  test "X1: a file imported into another portfolio is named and held back", %{
    conn: conn,
    main: main,
    bonds: bonds
  } do
    {:ok, view, _html} = live(conn, "/imports")
    upload!(view)

    group = view |> element("[data-role='held-back']") |> render()
    assert group =~ "data-note--attention"

    assert text(group, "[data-role='held-back-group'] summary") ==
             "Already imported into portfolio “Anleihen”: 4 entries — not taken over"

    refute has_element?(view, "[data-role='held-back-group'][open]")

    assert rows(group) == [
             ["2026-03-12", "Deposit", "Coupon-Cash", "+10,000.00 EUR"],
             [
               "2026-03-13",
               "Buy",
               "Coupon-Cash · Larkspur Rail AG 4,00 % Anleihe 2031",
               "-9,950.00 EUR"
             ],
             [
               "2026-06-30",
               "Interest",
               "Coupon-Cash · Larkspur Rail AG 4,00 % Anleihe 2031",
               "+200.00 EUR"
             ],
             [
               "2026-09-30",
               "Interest",
               "Coupon-Cash · Larkspur Rail AG 4,00 % Anleihe 2031",
               "+200.00 EUR"
             ]
           ]

    toggle =
      "[data-role='held-back-include'] input[type='checkbox'][name='include_portfolio[#{bonds.id}]']"

    assert has_element?(view, toggle)
    refute has_element?(view, toggle <> "[checked]")

    assert text(group, "[data-role='held-back-include'] label") == "Take over anyway"

    assert text(group, "[data-role='held-back-include'] small") ==
             "books the 4 entries a second time, in “Hauptportfolio”; “Anleihen” keeps its own."

    assert text(
             render(view),
             "#mapping-cash-#{Mapping.row_key("cash", "Coupon-Cash")} [data-role='mapping-count']"
           ) ==
             "4 bookings imported into “Anleihen” · nothing to create"

    assert text(
             render(view),
             "#mapping-depot-#{Mapping.row_key("depot", "Coupon-Depot")} [data-role='mapping-count']"
           ) ==
             "1 booking imported into “Anleihen” · nothing to create"

    refute has_element?(view, "[data-role='nothing-to-import']")

    view |> element("form#pp-import-apply") |> render_submit()
    done = render_async(view, 1_000)
    assert done =~ "Created transactions: 0"

    assert text(done, "[data-role='held-back-result']") ==
             "Already imported into portfolio “Anleihen”: 4 entries — not taken over"

    assert Ledger.list_transactions_for_portfolio(main.id) == []
  end

  # User story (#1313; ADR-0050 as amended on 2026-11-01, X2):
  # As the operator who keeps the history in two portfolios on purpose,
  # I want to take the group over with one switch,
  # so that the second copy is my deliberate choice.
  #
  # Acceptance criteria:
  # - Switched on, the counts return to "4 bookings new" and the confirm
  #   books the four rows into the main portfolio with the file's amounts.
  # - A third drop names no group: the main portfolio holds every row now.
  test "X2: the switch takes the group over, once", %{conn: conn, main: main, bonds: bonds} do
    {:ok, view, _html} = live(conn, "/imports")
    upload!(view)

    view
    |> element("form#pp-import-apply")
    |> render_change(%{"include_portfolio" => %{"#{bonds.id}" => "true"}})

    html = render_async(view, 1_000)

    assert has_element?(
             view,
             "[data-role='held-back-include'] input[name='include_portfolio[#{bonds.id}]'][checked]"
           )

    assert text(
             html,
             "#mapping-cash-#{Mapping.row_key("cash", "Coupon-Cash")} [data-role='mapping-count']"
           ) ==
             "4 bookings new"

    view |> element("form#pp-import-apply") |> render_submit()
    assert render_async(view, 1_000) =~ "Created transactions: 4"

    assert main.id
           |> Ledger.list_transactions_for_portfolio()
           |> Enum.map(&{&1.type, &1.gross_amount})
           |> Enum.sort() == [
             {"buy", Decimal.new("9950.000000")},
             {"deposit", Decimal.new("10000.000000")},
             {"interest", Decimal.new("200.000000")},
             {"interest", Decimal.new("200.000000")}
           ]

    {:ok, again, _html} = live(conn, "/imports")
    upload!(again)
    refute has_element?(again, "[data-role='held-back']")
  end

  # User story (#1313, the closing act):
  # As the operator whose purchase with a tax refund is already in another
  # portfolio,
  # I want the held-back group to list the file's one row with the cash the
  # file states,
  # so that it reads as the file I dropped, not as the split it books.
  #
  # Acceptance criteria:
  # - The group says 1 entry and lists one row, -1,000.00 EUR (the file's
  #   amount, not the 1,010.00 the row books beside its refund).
  # - The done page counts 1 entry held back.
  test "a held-back row with a split-off refund reads as the file's one row", %{conn: conn} do
    refunds = portfolio!("Steuerdepot")
    {:ok, preview} = PortfolioPerformance.parse(@refunded_buy, filename: "erstattung.json")
    {:ok, %{created_transactions: 2}} = Imports.apply(preview, %{portfolio_id: refunds.id})

    {:ok, view, _html} = live(conn, "/imports")
    upload!(view, "erstattung.json", @refunded_buy)

    group = view |> element("[data-role='held-back']") |> render()

    assert text(group, "[data-role='held-back-group'] summary") ==
             "Already imported into portfolio “Steuerdepot”: 1 entry — not taken over"

    assert rows(group) == [
             [
               "2026-04-14",
               "Buy",
               "Refund-Cash · Larkspur Rail AG 4,00 % Anleihe 2031",
               "-1,000.00 EUR"
             ]
           ]

    view |> element("form#pp-import-apply") |> render_submit()
    done = render_async(view, 1_000)

    assert text(done, "[data-role='held-back-result']") ==
             "Already imported into portfolio “Steuerdepot”: 1 entry — not taken over"
  end

  defp upload!(view, name \\ "kupons-2026.json", content \\ @coupons) do
    file_input(view, "#pp-import-form", :pp_file, [
      %{
        name: name,
        content: content,
        type: "application/json",
        last_modified: 1_700_000_000_000
      }
    ])
    |> render_upload(name)

    render_async(view)
  end

  defp text(html, selector) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> LazyHTML.text()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp rows(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("[data-role='held-back-group'] tbody tr")
    |> Enum.map(fn row ->
      row
      |> LazyHTML.query("td")
      |> Enum.map(&(&1 |> LazyHTML.text() |> String.replace(~r/\s+/u, " ") |> String.trim()))
    end)
  end

  defp portfolio!(name) do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{name: name, base_currency_code: "EUR"})

    portfolio
  end
end
