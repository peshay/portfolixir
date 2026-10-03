defmodule PortfolixirWeb.SecuritiesQuotePhoneRowsTest do
  # Sprint 18 plan U5, pick H7.1 = A (board
  # ux-design-2026-10-02/07-phone-390, rule ①): under 560 px a security's
  # quotes give way to two-line rows, as the securities list, the history
  # and the trades lists already do (UX-DR27). Every name, close and date is
  # synthetic; dates are relative to the host's calendar day.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog.Quote, as: SecurityQuote
  alias Portfolixir.Ledger.Splits
  alias Portfolixir.Repo

  defp insert_quote!(security, date, close, source) do
    {:ok, _} =
      %SecurityQuote{}
      |> SecurityQuote.changeset(%{
        security_id: security.id,
        date: date,
        close: Decimal.new(close),
        source: source
      })
      |> Repo.insert()
  end

  defp rows(view) do
    view
    |> element("#quote-phone-rows")
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.find("li.phone-row")
  end

  defp text(node, selector) do
    node
    |> Floki.find(selector)
    |> Floki.text()
    |> String.split()
    |> Enum.join(" ")
  end

  # User story (#1012; board 07, H7.1, pick A, rule ①):
  # As the operator reading a security's quotes on a 390 px phone,
  # I want each quote as a two-line row — the date over its source, the
  # close on the right,
  # so that I can tell which closes are manual without swiping a table
  # sideways: "Quelle" is the only per-row mark of a manual close, and at
  # 390 px it sat off-screen in the table's own scroller.
  #
  # Acceptance criteria:
  # - The table keeps its wrapper, now `#quotes-table-wrapper`, which the
  #   phone lists' 560 px block hides; beside it
  #   `ul#quote-phone-rows.phone-rows` carries one row per quote of the
  #   range, in the table's order (newest first).
  # - A row: the ISO date as its name, the source badge under it, the close
  #   with the security's currency on the right.
  # - Without a split the row carries no second figure: "gespeichert …"
  #   would repeat the same number.
  # - The row has two children and no kebab.
  test "the quotes give way to two-line rows: date over source, the close on the right",
       %{conn: conn} do
    security =
      create_security!(name: "Nordwind Industrie AG", ticker: "NWI", currency_code: "EUR")

    today = Date.utc_today()

    insert_quote!(security, Date.add(today, -3), "106.80", "manual")
    insert_quote!(security, Date.add(today, -2), "111.85", "portfolio_performance")
    insert_quote!(security, Date.add(today, -1), "112.40", "portfolio_performance")

    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=quotes&locale=de")

    assert has_element?(view, "#quotes-table-wrapper > table.detail-quotes-table")

    assert has_element?(
             view,
             ~s(#detail-tab-panel-quotes ul#quote-phone-rows.phone-rows[aria-label="Kurse"])
           )

    [newest, middle, oldest] = rows(view)

    assert text(newest, ".phone-row__body .phone-row__name") ==
             Date.to_iso8601(Date.add(today, -1))

    assert text(newest, ".phone-row__ids .badge.quote-source") == "Portfolio Performance"
    assert text(newest, ".phone-row__figures .phone-row__figure") == "112,40 EUR"
    assert text(middle, ".phone-row__figure") == "111,85 EUR"
    assert text(oldest, ".phone-row__ids .badge.quote-source") == "Manuell"

    for row <- [newest, middle, oldest] do
      assert Floki.find(row, ".phone-row__figure2") == []
      assert Floki.find(row, ".row-actions__kebab") == []
      {"li", _attrs, children} = row
      assert length(children) == 2
    end
  end

  # User story (#1012; board 07, H7.1, pick A, "A nach einem Split"):
  # As the operator reading quotes on a phone after a split,
  # I want the stored value under the close where the split adjusted it,
  # so that the auditable input stays reachable on the phone, as the table's
  # "Gespeichert" column keeps it on the desktop.
  #
  # Acceptance criteria:
  # - A row whose close the split adjusted carries "gespeichert <stored>"
  #   under the close; a row the split did not touch carries none.
  # - The basis line names what the screen shows (the closing act's H7
  #   finding, board 07's rule ①): beside the table's sentence ("Die Spalte
  #   Gespeichert zeigt …") it carries the rows' ("Wo ein Split einen Kurs
  #   angepasst hat, zeigt „gespeichert“ darunter den unveränderten Wert."),
  #   and under 560 px only the rows' shows — the phone has no column.
  test "after a split the stored value stands under an adjusted close", %{conn: conn} do
    world = base_world(name: "Phone World", cash_name: "Phone Cash", depot_name: "Phone Depot")

    security =
      create_security!(name: "Nordwind Industrie AG", ticker: "NWI", asset_class: "equity")

    today = Date.utc_today()
    buy!(world, security, quantity: "10", price: "100", date: Date.add(today, -40))

    insert_quote!(security, Date.add(today, -20), "110", "manual")
    insert_quote!(security, Date.add(today, -5), "11", "manual")

    {:ok, _} =
      Splits.book_split(Actor.owner_ui(), %{
        security_id: security.id,
        date: Date.add(today, -10),
        ratio_numerator: 10,
        ratio_denominator: 1
      })

    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=quotes&locale=de")

    [after_split, before_split] = rows(view)

    assert Floki.find(after_split, ".phone-row__figure2") == []
    assert text(before_split, ".phone-row__figure") =~ "11,00"
    assert text(before_split, ".phone-row__figures .phone-row__figure2") == "gespeichert 110,00"

    # The closing act's H7 finding (board
    # ux-review-2026-10-03/03-gamma-surface-repairs, G6): the basis line
    # carries a sentence for the table and one for the rows, and the phone
    # lists' 560 px block shows the one that matches the screen.
    basis =
      view
      |> element("#detail-tab-panel-quotes [data-role='quotes-basis']")
      |> render()
      |> Floki.parse_fragment!()

    assert text(basis, ".quotes-basis__table") ==
             "Kursbasis: split-bereinigt. Die Spalte Gespeichert zeigt die unveränderten Werte."

    assert text(basis, ".quotes-basis__rows") ==
             "Kursbasis: split-bereinigt. Wo ein Split einen Kurs angepasst hat, zeigt „gespeichert“ darunter den unveränderten Wert."
  end
end
