defmodule PortfolixirWeb.DashboardTradesCardTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Fx
  alias Portfolixir.WorldFixtures

  # User story (#984 rescoped, Sprint 17 T2; board G1, variant A picked;
  # UX-DR2 amended 2026-10-01 with a fifth block):
  # As a local portfolio maintainer landing on the Overview,
  # I want the last five closed trades there, each with its result and its
  # return — per year from 365 days of holding, over the whole holding
  # period below — and a way to all of them,
  # so that "was the trade worth it" is answered where I look, without two
  # levels of navigation.
  #
  # Acceptance criteria:
  # - A "Closed trades" card sits under the KPI strip, before "Off target",
  #   with "All trades →" in its head linking to /cashflow?tab=realized.
  # - Its basis line says it shows the most recently closed (counted), the result
  #   currency, and that it covers every depot whatever the view.
  # - At most five rows, newest close first, each linking to its security's
  #   Trades tab: the name over "sold <date> · <days>", the signed result in
  #   the base currency over "+x% p. a." from 365 days, else "+y% total".
  # - The card lists results, not activity: no booking kind, no buy.

  # Six closed trades: two held 730 days (+20 % and -20 % a year), four short
  # ones closing later, the oldest close of all (Oldest Close Co) is the one
  # the card leaves out.
  defp seed! do
    world = WorldFixtures.base_world(name: "Card", cash_name: "Giro", depot_name: "Depot")
    WorldFixtures.deposit!(world, "100000", ~D[2023-01-02])

    trade = fn name, buy_date, sell_date, buy_price, sell_price ->
      security = WorldFixtures.create_security!(name: name, ticker: nil)
      WorldFixtures.buy!(world, security, quantity: "10", price: buy_price, date: buy_date)
      WorldFixtures.sell!(world, security, quantity: "10", price: sell_price, date: sell_date)
      security
    end

    %{
      oldest: trade.("Oldest Close Co", ~D[2023-02-01], ~D[2023-03-01], "10", "11"),
      fade: trade.("Slowfade Materials", ~D[2023-06-01], ~D[2025-05-31], "100", "64"),
      long: trade.("Longhold Industries", ~D[2024-01-02], ~D[2026-01-01], "100", "144"),
      quick: trade.("Quickturn Retail", ~D[2026-02-01], ~D[2026-03-03], "50", "45"),
      second: trade.("Second Short Co", ~D[2026-03-01], ~D[2026-04-01], "10", "12"),
      third: trade.("Third Short Co", ~D[2026-04-01], ~D[2026-05-01], "10", "10.5")
    }
  end

  defp text(nodes),
    do: nodes |> Floki.text(sep: " ") |> String.replace(~r/\s+/, " ") |> String.trim()

  defp document(view), do: view |> render() |> Floki.parse_document!()

  # The security's name: the name slot's own text, before its sub-line.
  defp row_name(row) do
    [{_tag, _attrs, [name | _sub]}] = Floki.find(row, ".attention-name")
    String.trim(name)
  end

  defp card_row(doc, name),
    do:
      doc
      |> Floki.find("#dashboard-trades [data-role='closed-trade']")
      |> Enum.find(&(text(&1) =~ name))

  test "the Overview lists the last five closed trades under the KPI strip", %{conn: conn} do
    %{long: long, quick: quick} = seed!()

    {:ok, view, _html} = live(conn, "/")
    render_async(view)
    html = render(view)
    doc = Floki.parse_document!(html)

    {strip_at, _} = :binary.match(html, ~s(id="dashboard-kpi-strip"))
    {card_at, _} = :binary.match(html, ~s(id="dashboard-trades"))
    {attention_at, _} = :binary.match(html, ~s(id="dashboard-attention"))
    assert strip_at < card_at and card_at < attention_at

    assert text(Floki.find(doc, "#dashboard-trades h2")) == "Closed trades"

    assert [link] = Floki.find(doc, "#dashboard-trades .section-head a")
    assert Floki.attribute(link, "href") == ["/cashflow?tab=realized"]
    assert text(link) == "All trades →"

    basis = text(Floki.find(doc, "#dashboard-trades [data-role='trades-card-basis']"))
    assert basis =~ "The 5 most recently closed"
    assert basis =~ "result in EUR"
    assert basis =~ "every depot, whatever the view"
    assert basis =~ "p. a. only from 365 days of holding"

    rows = Floki.find(doc, "#dashboard-trades [data-role='closed-trade']")
    assert length(rows) == 5

    assert Enum.map(rows, &row_name/1) == [
             "Third Short Co",
             "Second Short Co",
             "Quickturn Retail",
             "Longhold Industries",
             "Slowfade Materials"
           ]

    refute Floki.text(Floki.find(doc, "#dashboard-trades")) =~ "Oldest Close Co"

    long_row = card_row(doc, "Longhold Industries")
    assert Floki.attribute(long_row, "href") == ["/securities/#{long.id}?tab=trades"]

    assert text(Floki.find(long_row, ".attention-name .attention-item__sub")) ==
             "sold 2026-01-01 · 730 days"

    assert text(Floki.find(long_row, ".num .is-positive") |> Enum.take(1)) == "+440.00"
    assert text(Floki.find(long_row, ".num .attention-item__sub")) == "+20.0% p. a."

    quick_row = card_row(doc, "Quickturn Retail")
    assert Floki.attribute(quick_row, "href") == ["/securities/#{quick.id}?tab=trades"]
    assert text(Floki.find(quick_row, ".num .is-negative") |> Enum.take(1)) == "-50.00"
    assert text(Floki.find(quick_row, ".num .attention-item__sub")) == "-10.0% total"

    fade_row = card_row(doc, "Slowfade Materials")
    assert text(Floki.find(fade_row, ".num .attention-item__sub")) == "-20.0% p. a."
  end

  # Acceptance criteria (UX-DR20; board G1, the card while it computes):
  # - While the trades compute, the card keeps its head and shows the block
  #   skeleton, aria-busy, with no cue word.
  # - With no sell booked the card is absent from the first paint on: no
  #   placeholder for a card that cannot appear.
  test "the card pends with the block skeleton, and is absent without a sell", %{conn: conn} do
    seed!()
    {:ok, view, html} = live(conn, "/")
    doc = Floki.parse_document!(html)

    assert text(Floki.find(doc, "#dashboard-trades h2")) == "Closed trades"
    assert [skeleton] = Floki.find(doc, "#dashboard-trades p.section-skeleton")
    assert Floki.attribute(skeleton, "aria-busy") == ["true"]
    assert Floki.find(doc, "#dashboard-trades [data-role='closed-trade']") == []

    # The reads settle before the test ends, so no task outlives its owner.
    render_async(view)
    assert has_element?(view, "#dashboard-trades [data-role='closed-trade']")
  end

  test "without a closed trade the card is absent", %{conn: conn} do
    world = WorldFixtures.base_world(name: "No Sells", cash_name: "Giro", depot_name: "Depot")
    held = WorldFixtures.create_security!(name: "Held Co", ticker: "HLD")
    WorldFixtures.deposit!(world, "1000", ~D[2026-01-02])
    WorldFixtures.buy!(world, held, quantity: "1", price: "100", date: ~D[2026-01-05])

    {:ok, view, html} = live(conn, "/")
    refute html =~ ~s(id="dashboard-trades")
    render_async(view)
    refute has_element?(view, "#dashboard-trades")
  end

  # Acceptance criteria (UX-DR25 on the card; board G1, the exclusion state):
  # - A sale whose close-date rate is not stored is named on the card in an
  #   attention note, which points to the backfill under "All trades".
  test "a sale the rates cannot convert is named on the card", %{conn: conn} do
    world = WorldFixtures.base_world(name: "Fx Card", cash_name: "Giro", depot_name: "Depot")
    euro = WorldFixtures.create_security!(name: "Euro Co", ticker: "EUC")
    WorldFixtures.buy!(world, euro, quantity: "1", price: "100", date: ~D[2026-01-05])
    WorldFixtures.sell!(world, euro, quantity: "1", price: "110", date: ~D[2026-02-05])

    pound = WorldFixtures.create_security!(name: "Pound Co", ticker: "PDC", currency: "GBP")

    gbp =
      Map.merge(
        world,
        WorldFixtures.add_depot(world.portfolio,
          currency: "GBP",
          cash_name: "GBP Cash",
          depot_name: "GBP Depot"
        )
      )

    WorldFixtures.buy!(gbp, pound,
      quantity: "2",
      price: "10",
      date: ~D[2026-01-09],
      currency: "GBP"
    )

    WorldFixtures.sell!(gbp, pound,
      quantity: "2",
      price: "30",
      date: ~D[2026-02-20],
      currency: "GBP"
    )

    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "GBP",
          date: ~D[2026-03-01],
          rate: "0.85",
          source: "manual"
        }
      ])

    {:ok, view, _html} = live(conn, "/")
    render_async(view)

    note = view |> element("#dashboard-trades [data-role='trades-card-excluded']") |> render()
    assert note =~ "Attention"

    assert note =~
             "1 sale with no stored rate on its close date is left out of the trades: Pound Co."

    assert note =~ "All trades"
    assert has_element?(view, "#dashboard-trades [data-role='closed-trade']", "Euro Co")

    # One trade: the basis line counts what the card shows (closing act γ
    # n3), and in German the missing rate is an exchange rate (γ n4).
    assert view |> element("#dashboard-trades [data-role='trades-card-basis']") |> render() =~
             "The most recently closed ·"

    {:ok, de_view, _html} = live(conn, "/?locale=de")
    render_async(de_view)

    assert de_view |> element("#dashboard-trades [data-role='trades-card-basis']") |> render() =~
             "Der zuletzt abgeschlossene ·"

    assert de_view |> element("#dashboard-trades [data-role='trades-card-excluded']") |> render() =~
             "1 Verkauf ohne gespeicherten Wechselkurs an seinem Schlussdatum fehlt bei den Trades: Pound Co. Das Nachladen der Wechselkurse steht unter „Alle Trades“."
  end

  test "the card is German where the page is", %{conn: conn} do
    seed!()

    {:ok, view, _html} = live(conn, "/?locale=de")
    render_async(view)
    doc = document(view)

    assert text(Floki.find(doc, "#dashboard-trades h2")) == "Abgeschlossene Trades"
    assert text(Floki.find(doc, "#dashboard-trades .section-head a")) == "Alle Trades →"

    basis = text(Floki.find(doc, "#dashboard-trades [data-role='trades-card-basis']"))
    assert basis =~ "Die 5 zuletzt abgeschlossenen"
    assert basis =~ "unabhängig von der Ansicht"

    long_row = card_row(doc, "Longhold Industries")

    assert text(Floki.find(long_row, ".attention-name .attention-item__sub")) ==
             "verkauft 01.01.2026 · 730 Tage"

    assert text(Floki.find(long_row, ".num .attention-item__sub")) == "+20,0% p. a."

    assert text(Floki.find(card_row(doc, "Quickturn Retail"), ".num .attention-item__sub")) ==
             "-10,0% gesamt"
  end
end
