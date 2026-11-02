defmodule PortfolixirWeb.OpenLotsTradePriceLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quote!: 3]

  # Synthetic figures only: board ux-design-2026-11-02-sprint23/02-money
  # ①b. Helios has no quote; it was bought 15 @ 18.00 and 5 @ 19.20, so it
  # counts at its last own trade price, 19.20 EUR of 2025-03-14 (ADR-0010).

  setup do
    world = base_world(name: "Helios Tab", cash_name: "Girokonto", depot_name: "Depot 1")
    deposit!(world, "5000", ~D[2025-01-02])
    helios = create_security!(name: "Helios Example SE", ticker: "HLX")
    buy!(world, helios, quantity: "15", price: "18.00", date: ~D[2025-02-12])
    buy!(world, helios, quantity: "5", price: "19.20", date: ~D[2025-03-14])
    %{world: world, helios: helios}
  end

  defp text(nodes),
    do: nodes |> Floki.text(sep: " ") |> String.replace(~r/\s+/, " ") |> String.trim()

  defp de_conn(conn),
    do:
      PortfolixirWeb.PreferenceCookieHelpers.put_preference_cookie(
        conn,
        "portfolixir_locale",
        "de"
      )

  defp lot_rows(view) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find("#detail-tab-panel-trades table.detail-trades-table")
    |> List.first()
    |> Floki.find("tbody tr")
    |> Enum.map(fn row -> Enum.map(Floki.find(row, "td"), &text/1) end)
  end

  defp open_drawer_sell(view, w, security, quantity) do
    view |> element("#open-booking") |> render_click()

    view
    |> element("#transaction-form")
    |> render_change(%{
      "transaction" => %{
        "type" => "sell",
        "date" => "2025-06-01",
        "securities_account_id" => to_string(w.depot.id),
        "security_id" => to_string(security.id),
        "quantity" => quantity,
        "price" => "",
        "fees" => "0",
        "taxes" => "0",
        "notes" => ""
      }
    })
  end

  # User story (#1369; board 02 ①b):
  # As a local portfolio maintainer reading the Trades tab of a security
  # without a quote,
  # I want its open lots priced at the last own trade price, the source and
  # its date beside the price, and every result column following,
  # so that the tab reads the figure the Bestände tab and Wealth show
  # instead of "—".
  #
  # Acceptance criteria:
  # - „Letzter“ reads „19,20 Handelspreis · 14.03.2025“ on both lots.
  # - The results: 15 x (19,20 - 18,00) = +18,00 (+6,7 %), 5 x 0 = 0,00,
  #   and the EUR decomposition follows (+18,00 / 0,00 / +18,00 EUR).
  test "the Trades tab prices a security without a quote at its last trade price",
       %{conn: conn, helios: helios} do
    {:ok, view, _html} = live(de_conn(conn), "/securities/#{helios.id}?tab=trades")

    assert [first, second] = lot_rows(view)

    assert first == [
             "12.02.2025",
             "15,0000",
             "18,00",
             "19,20 Handelspreis · 14.03.2025",
             "+18,00",
             "+6,7%",
             "+18,00",
             "0,00",
             "+18,00 EUR"
           ]

    assert second == [
             "14.03.2025",
             "5,0000",
             "19,20",
             "19,20 Handelspreis · 14.03.2025",
             "0,00",
             "0,0%",
             "0,00",
             "0,00",
             "0,00 EUR"
           ]
  end

  # User story (#1369; board 02 ①b):
  # As a maintainer entering a sell of a security without a quote, with no
  # price typed yet,
  # I want the preview priced at the last own trade price and to be told so,
  # so that the gross gain is the figure the holdings imply, never "—".
  #
  # Acceptance criteria:
  # - The hint reads „Bepreist zum letzten eigenen Handelspreis: 19,20
  #   (14.03.2025).“; the English one "Priced at the last own trade price:
  #   19.20 (2025-03-14)."
  # - Selling 5 consumes 5 of the first lot: Bruttogewinn +6,00 EUR, the
  #   total +6,00 EUR.
  test "the sell preview names the trade price it is priced at", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, "/transactions?locale=de")
    open_drawer_sell(view, ctx.world, ctx.helios, "5")

    doc = view |> element("#sell-lot-preview") |> render() |> Floki.parse_fragment!()

    assert text(Floki.find(doc, "[data-role=preview-price-hint]")) ==
             "Bepreist zum letzten eigenen Handelspreis: 19,20 (14.03.2025)."

    assert [row] = Floki.find(doc, "#sell-lot-preview-table tbody tr")
    assert text(Floki.find(row, "td:nth-child(4)")) == "+6,00 EUR"
    assert text(Floki.find(doc, "[data-role=preview-total]")) == "+6,00 EUR"

    {:ok, en_view, _html} = live(conn, "/transactions?locale=en")
    open_drawer_sell(en_view, ctx.world, ctx.helios, "5")

    assert en_view |> element("[data-role=preview-price-hint]") |> render() |> text_of() ==
             "Priced at the last own trade price: 19.20 (2025-03-14)."
  end

  # User story (#1369, the regression pin on screen):
  # As a maintainer selling a quoted security,
  # I want the preview's hint to read as before,
  # so that the trade-price wording appears only where no quote exists.
  test "a quoted security's preview keeps the stored-price hint", %{conn: conn} = ctx do
    quoted = create_security!(name: "Quoted Example AG", ticker: "QEX")
    buy!(ctx.world, quoted, quantity: "10", price: "100.00", date: ~D[2025-01-05])
    put_quote!(quoted, ~D[2025-06-30], "130.00")

    {:ok, view, _html} = live(conn, "/transactions?locale=en")
    open_drawer_sell(view, ctx.world, quoted, "4")

    assert view |> element("[data-role=preview-price-hint]") |> render() |> text_of() ==
             "Priced at the latest stored price: 130.00."

    assert view |> element("[data-role=preview-total]") |> render() |> text_of() ==
             "+120.00 EUR"
  end

  defp text_of(html), do: html |> Floki.parse_fragment!() |> text()
end
