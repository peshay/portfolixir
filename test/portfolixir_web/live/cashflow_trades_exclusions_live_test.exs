defmodule PortfolixirWeb.CashflowTradesExclusionsLiveTest do
  # Board `ux-design-2026-11-03-sprint23-i1`, Income (Cash flow → Trades,
  # Sprint 22 R5 re-read against Sprint 23 board 02 ①d; Lane I, idea I1,
  # variant R): with two or more reasons the exclusion note's lead carries
  # every count once and each reason names its sales without a second
  # count (⑧); what a reason means moves into the facet's ⓘ (①), the
  # missing rate's definition without a copy (⑥); the backfill's sentence
  # and button follow only a reason the backfill can fix (#1359). The money
  # cells read "300.00 EUR" (#1321). Synthetic names and figures (the
  # board's "Arbolia Inc."). async: false: the facet reads every security.
  use PortfolixirWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.WorldFixtures

  defp squish(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()

  defp text(view, selector) do
    view
    |> element(selector)
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.text()
    |> squish()
  end

  defp texts(view, selector) do
    view
    |> render()
    |> LazyHTML.from_document()
    |> LazyHTML.query(selector)
    |> Enum.map(&(&1 |> LazyHTML.text() |> squish()))
  end

  defp lines(view, selector) do
    view
    |> element(selector)
    |> render()
    |> String.split(~r/<br\s*\/?>/)
    |> Enum.map(&(&1 |> LazyHTML.from_fragment() |> LazyHTML.text() |> squish()))
  end

  # Two reasons a rate fixes: Kestrel Inc. has no stored rate at its close
  # date; Arbolia Inc.'s imported buy has no figure in USD. Wrenfield
  # Gardens AG converts: bought 10 at 50 EUR, fee 1; sold 10 at 60, fee 1.
  defp backfillable_world! do
    world =
      WorldFixtures.base_world(name: "Muster", cash_name: "Test-Cash", depot_name: "Depot Muster")

    arbolia =
      WorldFixtures.create_security!(name: "Arbolia Inc.", ticker: "ARBL", currency: "USD")

    kestrel =
      WorldFixtures.create_security!(name: "Kestrel Inc.", ticker: "KSTL", currency: "USD")

    wren = WorldFixtures.create_security!(name: "Wrenfield Gardens AG", ticker: "WRG")

    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2026-08-14],
          rate: "1.25",
          source: "manual"
        }
      ])

    {:ok, _buy} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        cash_account_id: world.cash.id,
        security_id: arbolia.id,
        type: "buy",
        date: ~D[2025-02-12],
        quantity: "10",
        price: "80",
        currency_code: "EUR",
        gross_amount: "800"
      })

    WorldFixtures.cross_trade!(world, arbolia,
      type: "sell",
      quantity: "10",
      price: "120",
      settled: "960.00",
      gross: "960.00",
      date: ~D[2026-08-14]
    )

    for {type, date, price} <- [{"buy", ~D[2026-01-05], "50"}, {"sell", ~D[2026-03-02], "60"}] do
      WorldFixtures.cross_trade!(world, kestrel,
        type: type,
        quantity: "10",
        price: price,
        settled: "#{price}0.00",
        gross: "#{price}0.00",
        date: date
      )
    end

    WorldFixtures.buy!(world, wren, quantity: "10", price: "50", fees: "1", date: ~D[2026-07-01])
    WorldFixtures.sell!(world, wren, quantity: "10", price: "60", fees: "1", date: ~D[2026-08-14])
    world
  end

  # Two of R5's reasons, which no rate fixes: Dollar Fund was bought through
  # a dollar account and sold through the euro account; Allotted Fund's buy
  # has an amount of zero.
  defp r5_world! do
    world =
      WorldFixtures.base_world(name: "Muster", cash_name: "Test-Cash", depot_name: "Depot Muster")

    fund = WorldFixtures.create_security!(name: "Dollar Fund", ticker: "DFD", currency: "USD")
    dollar = Map.merge(world, WorldFixtures.add_depot(world.portfolio, cash_currency: "USD"))

    WorldFixtures.buy!(dollar, fund,
      quantity: "10",
      price: "100",
      currency: "USD",
      date: ~D[2025-04-01]
    )

    {:ok, _sale} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        cash_account_id: world.cash.id,
        security_id: fund.id,
        type: "sell",
        date: ~D[2025-05-02],
        quantity: "10",
        price: "96",
        currency_code: "EUR",
        security_amount: "1200",
        settlement_amount: "960",
        settlement_fx_rate: "0.8",
        gross_amount: "960"
      })

    allotted =
      WorldFixtures.create_security!(name: "Allotted Fund", ticker: "ALF", currency: "USD")

    {:ok, _allotment} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        cash_account_id: world.cash.id,
        security_id: allotted.id,
        type: "buy",
        date: ~D[2025-04-01],
        quantity: "5",
        price: "0",
        currency_code: "EUR"
      })

    WorldFixtures.cross_trade!(world, allotted,
      type: "sell",
      quantity: "5",
      price: "120",
      settled: "480.00",
      gross: "480.00",
      date: ~D[2025-05-02]
    )

    world
  end

  # User story (board `ux-design-2026-11-03-sprint23-i1`, Income ⑧;
  # #1359's count-lead line):
  # As the operator reading why sales are left out of the Trades totals,
  # I want every count once in the lead and each reason after it naming its
  # sales,
  # so that the note reads short and no count is said twice.
  #
  # Acceptance criteria:
  # - With Kestrel Inc. (no stored rate) and Arbolia Inc. (no figure in the
  #   sale's currency), the lead stays "Excluded from every total: 1 sale
  #   with no stored rate; 1 sale whose buy has no figure in its
  #   currency.", then "No stored rate: Kestrel Inc." and "Buy without a
  #   figure in the sale's currency: Arbolia Inc." (the name's own full stop
  #   ends the sentence); in German „Ohne gespeicherten Wechselkurs:
  #   Kestrel Inc.“ and „Kauf ohne Gegenwert in der Währung des Verkaufs:
  #   Arbolia Inc.“.
  # - A rate fixes both, so the backfill's sentence reads in the note and
  #   its button sits in the actions.
  # - #1321: the converted trade's money cells and the realized total read
  #   with a text space before the currency ("501.00 EUR").
  test "two reasons a rate fixes: the lead counts, each reason names its sales, the backfill follows",
       %{conn: conn} do
    backfillable_world!()

    {:ok, view, _html} = live(conn, "/cashflow?tab=realized")
    render_async(view)

    note = "#realized-excluded.data-note--clamped"

    assert texts(view, note <> " .data-note__text > [data-role]") == [
             "Excluded from every total: 1 sale with no stored rate; 1 sale whose buy has no figure in its currency.",
             "No stored rate: Kestrel Inc.",
             "Buy without a figure in the sale's currency: Arbolia Inc.",
             "The daily rate sync cannot fill a past date. The backfill fetches the historical ECB series once, stores every published day and derives from it the settlement legs imported buys and sells lack; a day the ECB did not publish stays excluded."
           ]

    assert has_element?(view, note <> " .data-note__actions #fx-backfill-button")

    row = "#realized-trades-table tr[data-role='realized-trade']"

    assert texts(view, row <> " td.num:has(.value-suffix)") == [
             "501.00 EUR",
             "599.00 EUR",
             "+98.00 EUR +19.6%"
           ]

    assert text(view, "[data-role='realized-total']") == "+98.00 EUR"

    assert texts(view, "#realized-trades-phone-rows .phone-row__figure:has(.value-suffix)") == [
             "+98.00 EUR"
           ]

    {:ok, de_view, _html} = live(conn, "/cashflow?tab=realized&locale=de")
    render_async(de_view)

    assert text(de_view, "[data-role='realized-excluded-no-rate']") ==
             "Ohne gespeicherten Wechselkurs: Kestrel Inc."

    assert text(de_view, "[data-role='realized-excluded-missing-leg']") ==
             "Kauf ohne Gegenwert in der Währung des Verkaufs: Arbolia Inc."
  end

  # User story (board `ux-design-2026-11-03-sprint23-i1`, Income: R5's
  # reasons alone; #1359's backfill line; UX-DR25 clause 3):
  # As the operator whose sales are left out for reasons no rate fixes,
  # I want the note to name them without offering the rate backfill,
  # so that I am not sent to a remedy that cannot act.
  #
  # Acceptance criteria:
  # - With Dollar Fund (paid in another currency) and Allotted Fund (a buy
  #   of amount zero): the lead, then "Buy paid in another currency: Dollar
  #   Fund." and "Buy of amount zero: Allotted Fund."; in German „Kauf in
  #   anderer Währung bezahlt: Dollar Fund.“ and „Kauf mit Betrag null:
  #   Allotted Fund.“.
  # - No backfill sentence, no "Backfill historical rates", no actions.
  test "R5's reasons alone: each names its sales, and no backfill is offered", %{conn: conn} do
    r5_world!()

    {:ok, view, _html} = live(conn, "/cashflow?tab=realized")
    render_async(view)

    note = "#realized-excluded.data-note--clamped"

    assert texts(view, note <> " .data-note__text > [data-role]") == [
             "Excluded from every total: 1 sale whose buy was paid in another currency; 1 sale whose buy has an amount of zero.",
             "Buy paid in another currency: Dollar Fund.",
             "Buy of amount zero: Allotted Fund."
           ]

    refute has_element?(view, "[data-role='fx-backfill-reason']")
    refute has_element?(view, "#fx-backfill-button")
    refute has_element?(view, note <> " .data-note__actions")

    {:ok, de_view, _html} = live(conn, "/cashflow?tab=realized&locale=de")
    render_async(de_view)

    assert texts(de_view, note <> " .data-note__text > [data-role]") == [
             "Aus jeder Summe ausgeschlossen: 1 Verkauf, dessen Kauf in einer anderen Währung bezahlt wurde; 1 Verkauf, dessen Kauf einen Betrag von null hat.",
             "Kauf in anderer Währung bezahlt: Dollar Fund.",
             "Kauf mit Betrag null: Allotted Fund."
           ]
  end

  # User story (board `ux-design-2026-11-03-sprint23-i1`, Income ① ⑥):
  # As the operator asking what a reason in the exclusion note means,
  # I want each reason's definition behind the facet's ⓘ,
  # so that the note names the sales and the ⓘ says why they are out.
  #
  # Acceptance criteria:
  # - The facet's ⓘ keeps its text and the trades' two method lines, then,
  #   after a blank line, one definition per line for the four reasons
  #   other than a missing rate (which the facet's text already defines),
  #   in the note's order; in German the board's strings 11 to 14.
  test "the reasons' definitions sit in the facet's ⓘ", %{conn: conn} do
    r5_world!()

    {:ok, view, _html} = live(conn, "/cashflow?tab=realized")
    render_async(view)

    assert [
             "Realized gains and losses from FIFO-matched sales" <> _,
             "",
             "Deliveries open no lot",
             "p. a. only from 365 days of holding and only where a rate solves the flows",
             "",
             "Buy without a figure in the sale's currency: a buy the sale closes has no figure in the sale's currency.",
             "Third currency: the sale or a buy it closes is priced in a currency that is neither the security's nor its account's; no rate fixes it.",
             "Buy paid in another currency: a buy the sale closes was paid in another currency than the sale's, which no stored figure bridges; no rate fixes it.",
             "Buy of amount zero: a buy the sale closes has an amount of zero, which the rate backfill does not complete."
           ] = lines(view, "[data-role='facet-info'] p[role='tooltip']")

    {:ok, de_view, _html} = live(conn, "/cashflow?tab=realized&locale=de")
    render_async(de_view)

    assert de_view |> lines("[data-role='facet-info'] p[role='tooltip']") |> Enum.take(-4) == [
             "Kauf ohne Gegenwert in der Währung des Verkaufs: Ein Kauf, den der Verkauf schließt, hat keinen Gegenwert in der Währung des Verkaufs.",
             "Dritte Währung: Der Verkauf oder ein Kauf, den er schließt, ist weder in der Währung des Wertpapiers noch in der seines Kontos bepreist; kein Wechselkurs behebt das.",
             "Kauf in anderer Währung bezahlt: Ein Kauf, den der Verkauf schließt, wurde in einer anderen Währung als der des Verkaufs bezahlt, die kein gespeicherter Wert überbrückt; kein Wechselkurs behebt das.",
             "Kauf mit Betrag null: Ein Kauf, den der Verkauf schließt, hat einen Betrag von null, den das Nachladen der Kurse nicht ergänzt."
           ]
  end
end
