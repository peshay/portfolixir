defmodule PortfolixirWeb.ZeroCostBasisScreensTest do
  # #1142 (Sprint 20 β B3, plan D-6; board ux-design-2026-10-07/02-money-findings,
  # before/after; found while drawing 9): a return on a cost basis of zero is
  # not a number. Every cell that printed "0,0%" for it is the existing muted
  # dash with #1089's reason anatomy (Sprint 19's pick J4): a `title` and a
  # visually hidden sentence. At 390 px the reason is on the row, in words.
  #
  # The data is invented, the board's: "Larkspur Rail AG", 12 bonus shares
  # booked as a buy at 0,00 on 03.03.2025, 25 bought at 38,50 on 11.11.2025,
  # 8 sold on 13.08.2026 at 41,25 (+330,00 EUR), latest close 41,80;
  # "Fennwick Labs AG", 15 shares delivered in at no price, latest close
  # 22,40 (336,00 EUR); "Kestrel Robotik SE", held with no quote.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quote!: 3, sell!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.Ledger

  @no_return {"No return: no cost basis", "no return, no cost basis"}
  @no_pa {"No annualized return: no cost basis", "no annualized return, no cost basis"}

  setup do
    Classifications.ensure_builtins()
    world = base_world(name: "Bonus World", cash_name: "Girokonto", depot_name: "Depot 1")
    deposit!(world, "5000", ~D[2025-01-02])

    larkspur = create_security!(name: "Larkspur Rail AG", ticker: "LKR")
    buy!(world, larkspur, quantity: "12", price: "0", date: ~D[2025-03-03])
    buy!(world, larkspur, quantity: "25", price: "38.50", date: ~D[2025-11-11])
    sell!(world, larkspur, quantity: "8", price: "41.25", date: ~D[2026-08-13])
    put_quote!(larkspur, ~D[2026-10-06], "41.80")

    fennwick = create_security!(name: "Fennwick Labs AG", ticker: "FWL")

    {:ok, _delivery} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        security_id: fennwick.id,
        type: "inbound_delivery",
        date: ~D[2026-02-02],
        quantity: "15",
        currency_code: "EUR"
      })

    put_quote!(fennwick, ~D[2026-10-06], "22.40")

    kestrel = create_security!(name: "Kestrel Robotik SE", ticker: "KRS")
    buy!(world, kestrel, quantity: "40", price: "52.10", date: ~D[2025-03-14])

    %{world: world, larkspur: larkspur, fennwick: fennwick, kestrel: kestrel}
  end

  defp text(nodes),
    do: nodes |> Floki.text(sep: " ") |> String.replace(~r/\s+/, " ") |> String.trim()

  defp class_of(node), do: node |> Floki.attribute("class") |> List.first("")
  defp document(html) when is_binary(html), do: Floki.parse_document!(html)
  defp de(conn), do: Plug.Test.put_req_cookie(conn, "portfolixir_locale", "de")

  # The reason anatomy of #1089: a muted dash, aria-hidden, the reason in the
  # node's title and in a visually hidden sentence.
  defp assert_reason_dash(node, {title, sentence}, label) do
    assert class_of(node) =~ "trade-pa--na", label
    refute class_of(node) =~ ~r/is-positive|is-negative|is-flat/, label
    assert Floki.attribute(node, "title") == [title], label
    assert text(Floki.find(node, "[aria-hidden='true']")) == "—", label
    assert text(Floki.find(node, ".visually-hidden")) == sentence, label
  end

  # User story (#1142, the Trades facet; board 02 "Nachher"):
  # As a local portfolio maintainer reading the Trades facet,
  # I want a trade on no cost to show the dash with its reason where "0.0%"
  # stood, and its p. a. dash to name that reason first,
  # so that +330.00 EUR on free shares is not read as a flat trade.
  #
  # Acceptance criteria:
  # - The Result cell keeps "+330.00 EUR"; its sub-line is the muted dash,
  #   title "No return: no cost basis", hidden "no return, no cost basis".
  # - The p. a. cell's dash takes "No annualized return: no cost basis".
  # - The phone row reads "— no cost basis" where "0.0% total" stood (the
  #   dash aria-hidden, no "total"); its hidden sentence names the reason.
  # - German: "Keine Rendite: keine Kostenbasis", "Keine annualisierte
  #   Rendite: keine Kostenbasis", "— keine Kostenbasis".
  test "the Trades facet shows the reason dash for a trade on no cost", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/cashflow?tab=realized")
    doc = view |> render_async() |> document()

    assert [row] = Floki.find(doc, "#realized-trades-table tr[data-role='realized-trade']")
    assert [result] = Floki.find(row, "td[data-role='trade-result']")
    assert text(result) =~ ~r/^\+330\.00 EUR/
    refute text(result) =~ "%"
    assert [sub] = Floki.find(result, "span.stat__sub")
    assert_reason_dash(sub, @no_return, "result sub-line")

    assert [pa] = Floki.find(row, "td.trade-pa")
    assert_reason_dash(pa, @no_pa, "p. a.")

    assert [phone] = Floki.find(doc, "#realized-trades-phone-rows li.phone-row")
    assert [figure2] = Floki.find(phone, ".phone-row__figure2")
    assert text(figure2) == "— no cost basis"
    assert [absent] = Floki.find(figure2, "[data-role='return-absent']")
    assert text(Floki.find(absent, "[aria-hidden='true']")) == "—"
    assert text(Floki.find(phone, "[data-role='pa-absent']")) == "no return, no cost basis"

    {:ok, de_view, _html} = live(de(conn), "/cashflow?tab=realized")
    de_doc = de_view |> render_async() |> document()

    assert Floki.attribute(Floki.find(de_doc, "td[data-role='trade-result'] .stat__sub"), "title") ==
             ["Keine Rendite: keine Kostenbasis"]

    assert Floki.attribute(Floki.find(de_doc, "#realized-trades-table td.trade-pa"), "title") ==
             ["Keine annualisierte Rendite: keine Kostenbasis"]

    assert text(Floki.find(de_doc, "#realized-trades-phone-rows .phone-row__figure2")) ==
             "— keine Kostenbasis"
  end

  # User story (#1142, the security's Trades tab; board 02 "Nachher"):
  # As a local portfolio maintainer on Larkspur's Trades tab,
  # I want the open lot of the free shares and the closed trade on no cost
  # to show the dash with its reason,
  # so that neither reads "0.0%" beside a gain.
  #
  # Acceptance criteria:
  # - The open lot bought at 0.00 has the reason dash in its "%" cell; the
  #   lot bought at 38.50 keeps "+8.6%".
  # - The closed trade's "%" cell is the reason dash, its p. a. dash names
  #   no cost basis, and its phone row reads "— no cost basis".
  test "the Trades tab shows the reason dash on the lot and the trade on no cost", %{
    conn: conn,
    larkspur: larkspur
  } do
    {:ok, view, _html} = live(conn, "/securities/#{larkspur.id}?tab=trades")
    doc = view |> render() |> document()

    [lots_table | _closed] = Floki.find(doc, "#detail-tab-panel-trades table.detail-trades-table")
    assert [free, bought] = Floki.find(lots_table, "tbody tr")
    assert text(Floki.find(free, "td:nth-child(1)")) == "2025-03-03"
    assert [free_pct] = Floki.find(free, "td:nth-child(6)")
    assert_reason_dash(free_pct, @no_return, "open lot %")
    assert text(Floki.find(bought, "td:nth-child(6)")) == "+8.6%"

    assert [closed] = Floki.find(doc, "#detail-closed-trades-table tbody tr")
    assert [pct] = Floki.find(closed, "td:nth-child(9)")
    assert_reason_dash(pct, @no_return, "closed %")
    assert [pa] = Floki.find(closed, "td:nth-child(7)")
    assert_reason_dash(pa, @no_pa, "closed p. a.")

    assert [phone] = Floki.find(doc, "#detail-closed-trades-phone-rows li.phone-row")
    assert text(Floki.find(phone, ".phone-row__figure2")) == "— no cost basis"
    assert [_absent] = Floki.find(phone, ".phone-row__figure2 [data-role='return-absent']")
    assert text(Floki.find(phone, "[data-role='pa-absent']")) == "no return, no cost basis"
  end

  # User story (#1142, the unrealized side, the issue's own example; board 02
  # "Nachher"):
  # As a local portfolio maintainer holding shares delivered in at no cost,
  # I want the Holdings tab's "%" and Wealth's "P&L %" to show the dash with
  # its reason, in the dash's colour,
  # so that 336.00 on no cost is not printed as "0.00 %" in the gain colour.
  #
  # Acceptance criteria:
  # - Fennwick's Holdings tab "%" cell is the reason dash, not the gain
  #   colour of the amount beside it.
  # - A holding with no price keeps the plain dash, with no reason: its
  #   percentage is missing for want of a price, not of a cost.
  # - Wealth's "P&L %" cell for Fennwick is the reason dash.
  test "the Holdings tab and Wealth's P&L % show the reason dash on no cost", %{
    conn: conn,
    fennwick: fennwick,
    kestrel: kestrel
  } do
    {:ok, view, _html} = live(conn, "/securities/#{fennwick.id}?tab=holdings")
    doc = view |> render() |> document()

    assert [row | _bucket_row] = Floki.find(doc, "table.detail-holdings-table tbody tr")
    assert text(Floki.find(row, "td:nth-child(5)")) == "+336.00"
    assert [pct] = Floki.find(row, "td:nth-child(6)")
    assert_reason_dash(pct, @no_return, "holdings %")

    {:ok, unpriced, _html} = live(conn, "/securities/#{kestrel.id}?tab=holdings")
    unpriced_doc = unpriced |> render() |> document()

    assert [unpriced_row | _bucket_row] =
             Floki.find(unpriced_doc, "table.detail-holdings-table tbody tr")

    assert [plain] = Floki.find(unpriced_row, "td:nth-child(6)")
    assert text(plain) == "—"
    assert Floki.attribute(plain, "title") == []
    refute class_of(plain) =~ "trade-pa--na"

    {:ok, wealth, _html} = live(conn, "/portfolio")
    render_async(wealth)

    render_change(wealth, "set_holdings_columns", %{
      "columns" => ["security", "unrealized_pnl_pct"]
    })

    [fennwick_row] =
      wealth
      |> render()
      |> document()
      |> Floki.find("#holdings-positions-table tbody tr")
      |> Enum.filter(&(text(&1) =~ "Fennwick"))

    assert [wealth_pct] = Floki.find(fennwick_row, "td:nth-child(2)")
    assert_reason_dash(wealth_pct, @no_return, "Wealth P&L %")
  end

  # User story (#1142; board 02, found while drawing 9):
  # As a local portfolio maintainer reading the Overview's closed trades,
  # I want a trade on no cost to read "— no cost basis" where "0.0% total"
  # stood,
  # so that the card says what the facet and the tab say.
  #
  # Acceptance criteria:
  # - The card's second line is "— no cost basis", the dash aria-hidden, no
  #   "total" and no percent; German "— keine Kostenbasis".
  test "the Overview card names a trade on no cost in words", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    doc = view |> render_async() |> document()

    assert [item] = Floki.find(doc, "a[data-role='closed-trade']")
    assert [_name_sub, figure_sub] = Floki.find(item, ".attention-item__sub")
    assert text(figure_sub) == "— no cost basis"
    assert [absent] = Floki.find(figure_sub, "[data-role='return-absent']")
    assert text(Floki.find(absent, "[aria-hidden='true']")) == "—"

    {:ok, de_view, _html} = live(de(conn), "/")
    de_doc = de_view |> render_async() |> document()

    assert [_name_sub, de_sub] =
             Floki.find(de_doc, "a[data-role='closed-trade'] .attention-item__sub")

    assert text(de_sub) == "— keine Kostenbasis"
  end
end
