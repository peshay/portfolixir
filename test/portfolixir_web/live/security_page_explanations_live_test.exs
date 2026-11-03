defmodule PortfolixirWeb.SecurityPageExplanationsLiveTest do
  # Sprint 23 Lane I, board `ux-design-2026-11-03-sprint23-i1` on the
  # security page (I1, variant R with Sprint 22's Q1 corrections): each
  # tab's method sentences sit in an ⓘ — beside „Closed trades (FIFO)“ on
  # Trades, ending the kept basis line on Chart, Quotes, Research and Dates
  # (reading 1) — its basis stays on the page, and every note clamps with
  # its remedy in view. Also the lines of the polish list #1365 the board
  # assigns to the page. Every name, identifier, figure and date is
  # invented.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Clock
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo
  alias Portfolixir.WorldFixtures

  defp squish(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()

  defp text(view, selector) do
    view
    |> element(selector)
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.text(sep: " ")
    |> squish()
  end

  # A line's own text, without the ⓘ that ends it.
  defp line_text(view, selector) do
    view
    |> element(selector)
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.filter_out("details")
    |> Floki.text(sep: " ")
    |> squish()
  end

  # An ⓘ panel's lines, one per `<br>`.
  defp lines(view, selector) do
    view
    |> element(selector)
    |> render()
    |> String.split(~r/<br\s*\/?>/)
    |> Enum.map(&(&1 |> Floki.parse_fragment!() |> Floki.text() |> squish()))
  end

  # The board's Tamarisk: held, sold on a day whose quote is ten times its
  # price, so the Overview leads with the implausible-quote problem.
  defp implausible! do
    usd = WorldFixtures.base_world(name: "USD Depot", currency: "USD")

    tamarisk =
      WorldFixtures.create_security!(
        name: "Tamarisk Systems Inc.",
        ticker: "TMSK",
        currency: "USD"
      )

    WorldFixtures.buy!(usd, tamarisk,
      quantity: "50",
      price: "4.12",
      currency: "USD",
      date: ~D[2025-11-03]
    )

    WorldFixtures.sell!(usd, tamarisk,
      quantity: "10",
      price: "4.12",
      currency: "USD",
      date: ~D[2026-04-03]
    )

    WorldFixtures.put_quote!(tamarisk, ~D[2026-04-02], "41.20")
    WorldFixtures.put_quote!(tamarisk, Clock.today(), "41.80")
    tamarisk
  end

  # The board's Arbolia (`unconvertible_trade_live_test.exs`): an imported
  # buy in EUR with no legs, sold by hand in USD, so the closed trade is
  # unavailable and its note names the lot and the backfill.
  defp unavailable! do
    world =
      WorldFixtures.base_world(name: "Muster", cash_name: "Test-Cash", depot_name: "Depot Muster")

    arbolia =
      WorldFixtures.create_security!(name: "Arbolia Inc.", ticker: "ARBL", currency: "USD")

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

    arbolia
  end

  # User story (I1, board `ux-design-2026-11-03-sprint23-i1` ⑤ ③ on the
  # security's Overview):
  # As the operator opening a security whose quotes contradict its bookings,
  # I want the problem cut to two lines with its two links below the cut,
  # so that the note leads the tab without hiding where the fix is made.
  #
  # Acceptance criteria:
  # - `implausible-quote-note` clamps (`data-note--clamped`), still the
  #   first child of the Overview panel; its text keeps the sentence through
  #   "then the booking:", with no link in it.
  # - „Quotes · Transactions“ sit in the note's actions, Quotes first.
  test "Overview: the implausible-quote problem clamps and its links sit in its actions",
       %{conn: conn} do
    tamarisk = implausible!()

    {:ok, view, _html} = live(conn, "/securities/#{tamarisk.id}")

    note = ~s(#detail-tab-panel-overview > [data-role="implausible-quote-note"])
    assert has_element?(view, note <> ".data-note--problem.data-note--clamped")

    assert text(view, note <> " .data-note__text") =~
             ~r/^Quote does not match the bookings: .* then the booking:$/

    refute has_element?(view, note <> " .data-note__text a")

    links =
      view
      |> element(note <> " .data-note__actions")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.attribute("a", "href")

    assert links == [
             "/securities/#{tamarisk.id}?tab=quotes",
             "/securities/#{tamarisk.id}?tab=transactions"
           ]
  end

  # User story (I1, board ① ② ③ on the Trades tab):
  # As the operator reading a security's closed trades,
  # I want the list's rules behind the ⓘ beside „Closed trades (FIFO)“ and
  # its gross/net basis under the list, and the unavailable trade's note cut
  # to two lines,
  # so that the tab reads as its trades, the rules one press away.
  #
  # Acceptance criteria:
  # - Beside the heading, in `div.section-title`, one section ⓘ
  #   („About this section“) holds "Deliveries open no lot" and "p. a. only
  #   from 365 days of holding and only where a rate solves the flows", one
  #   per line.
  # - The basis line keeps "Across every depot · fees and taxes in the
  #   realised P&L, not in avg buy and avg sell · income received while a
  #   trade was open not included", the two rules gone from it.
  # - The unavailable trade's note clamps; its text keeps its count and its
  #   remedy sentence ("Remedy: a rate for 2025-02-12 — …").
  # - In German the basis line reads „Über alle Depots · Gebühren und
  #   Steuern im G/V, nicht in Ø Kauf und Ø Verkauf · Erträge während der
  #   Haltedauer nicht enthalten“ and the ⓘ „Einlieferungen eröffnen keinen
  #   Lot“ first.
  test "Trades: the rules sit in the heading's ⓘ, the basis stays, the note clamps",
       %{conn: conn} do
    arbolia = unavailable!()

    {:ok, view, _html} = live(conn, "/securities/#{arbolia.id}?tab=trades")

    title = "#detail-tab-panel-trades div.section-title"
    assert text(view, title <> " h3") == "Closed trades (FIFO)"

    tip = title <> ~s( details.metric-tooltip--section[data-role="section-info"])
    assert has_element?(view, tip <> ~s( summary[aria-label="About this section"]))

    assert lines(view, tip <> ~s( p[role="tooltip"])) == [
             "Deliveries open no lot",
             "p. a. only from 365 days of holding and only where a rate solves the flows"
           ]

    assert text(view, ~s([data-role="trades-basis"])) ==
             "Across every depot · fees and taxes in the realised P&L, not in avg buy and avg sell · " <>
               "income received while a trade was open not included"

    note = "#detail-closed-trades-unavailable.data-note--clamped"

    assert text(view, note <> " .data-note__text") =~
             ~r/^1 trade not convertible: the buy of 2025-02-12 .* Remedy: a rate for 2025-02-12 — /

    {:ok, de_view, _html} = live(conn, "/securities/#{arbolia.id}?tab=trades&locale=de")

    assert text(de_view, ~s([data-role="trades-basis"])) ==
             "Über alle Depots · Gebühren und Steuern im G/V, nicht in Ø Kauf und Ø Verkauf · " <>
               "Erträge während der Haltedauer nicht enthalten"

    assert [
             "Einlieferungen eröffnen keinen Lot",
             "p. a. erst ab 365 Tagen Haltedauer und nur, wo ein Zinssatz die Zahlungen löst"
           ] = lines(de_view, tip <> ~s( p[role="tooltip"]))
  end

  # A buy or sell as a database stored it before #1199's refusal of a
  # booking priced in a third currency (`unconvertible_trade_live_test.exs`).
  defp stored_trade!(world, security, attrs) do
    {:ok, tx} =
      Repo.transaction(fn ->
        {type, _label} = Actor.to_columns(Actor.owner_ui())
        Repo.query!("SELECT set_config('portfolixir.journal_actor', $1, true)", [type])

        Repo.insert!(
          struct!(
            Transaction,
            Map.merge(
              %{
                portfolio_id: world.portfolio.id,
                securities_account_id: world.depot.id,
                cash_account_id: world.cash.id,
                security_id: security.id,
                taxes: Decimal.new("0")
              },
              attrs
            )
          )
        )
      end)

    tx
  end

  # User story (#1365's line "Trades tab: a trade blocked by two reasons at
  # once …", found by the Sprint 22 closing act):
  # As the operator whose sale closes a buy priced in a third currency and a
  # free allotment of zero amount,
  # I want the note to name both buys, each with its remedy,
  # so that correcting the franc booking is not the end of it.
  #
  # Acceptance criteria:
  # - A zero-amount buy of 5 Dollar Fund on 2025-03-03 and a stored buy of 5
  #   at 90 CHF on 2025-04-01, both through the EUR account, sold by hand at
  #   120 USD: the note names the franc buy first, then "Beside it, the buy
  #   of 2025-03-03 has an amount of zero and no figure in USD, the sale's
  #   currency, which the rate backfill does not complete. Remedy: enter the
  #   buy's figures in USD on the booking by hand."; it names no backfill.
  # - In German „Daneben hat der Kauf vom 03.03.2025 einen Betrag von null
  #   und keinen Gegenwert in USD …“.
  test "Trades: a trade blocked by a third-currency and a zero-amount buy names both",
       %{conn: conn} do
    world =
      WorldFixtures.base_world(name: "Muster", cash_name: "Test-Cash", depot_name: "Depot Muster")

    fund =
      WorldFixtures.create_security!(name: "Dollar Fund", ticker: "DFD", currency: "USD")

    {:ok, _allotment} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        cash_account_id: world.cash.id,
        security_id: fund.id,
        type: "buy",
        date: ~D[2025-03-03],
        quantity: "5",
        price: "0",
        currency_code: "EUR"
      })

    stored_trade!(world, fund, %{
      type: "buy",
      date: ~D[2025-04-01],
      quantity: Decimal.new("5"),
      price: Decimal.new("90"),
      fees: Decimal.new("5"),
      currency_code: "CHF",
      security_amount: Decimal.new("500"),
      settlement_amount: Decimal.new("400"),
      settlement_fx_rate: Decimal.new("0.888889"),
      gross_amount: Decimal.new("405")
    })

    WorldFixtures.cross_trade!(world, fund,
      type: "sell",
      quantity: "10",
      price: "120",
      settled: "960.00",
      fees: "3.00",
      gross: "957.00",
      date: ~D[2025-05-02]
    )

    {:ok, view, _html} = live(conn, "/securities/#{fund.id}?tab=trades")
    note = text(view, "[data-role=trades-unavailable]")

    assert note =~
             "1 trade not convertible: the buy of 2025-04-01 is priced in a currency that is neither the security's nor its account's (CHF)"

    assert note =~
             "Beside it, the buy of 2025-03-03 has an amount of zero and no figure in USD, the sale's currency, which the rate backfill does not complete. Remedy: enter the buy's figures in USD on the booking by hand."

    refute note =~ "Backfill"

    {:ok, de_view, _html} = live(conn, "/securities/#{fund.id}?tab=trades&locale=de")

    assert text(de_view, "[data-role=trades-unavailable]") =~
             "Daneben hat der Kauf vom 03.03.2025 einen Betrag von null und keinen Gegenwert in USD, der Währung des Verkaufs, den das Nachladen der Kurse nicht ergänzt. Abhilfe: die Beträge des Kaufs in USD von Hand auf der Buchung erfassen."
  end

  # User story (#1321 on the security page, assigned by the board):
  # As the operator copying or hearing a closed trade's result,
  # I want a space between the figure and its currency,
  # so that it reads "98.00 EUR", never "98.00EUR".
  #
  # Acceptance criteria:
  # - The closed trades' result cell and its phone row read the figure, a
  #   space, then the currency.
  test "Trades: the result reads with a space before its currency", %{conn: conn} do
    world = WorldFixtures.base_world(name: "Muster")
    wren = WorldFixtures.create_security!(name: "Wrenfield Gardens AG", ticker: "WRG")

    WorldFixtures.buy!(world, wren, quantity: "10", price: "50", fees: "1", date: ~D[2026-07-01])
    WorldFixtures.sell!(world, wren, quantity: "10", price: "60", fees: "1", date: ~D[2026-08-14])

    {:ok, view, _html} = live(conn, "/securities/#{wren.id}?tab=trades")

    cell =
      view
      |> element("#detail-closed-trades-table tbody tr")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.find("td")
      |> Enum.at(7)
      |> Floki.text()
      |> squish()

    assert cell =~ ~r/^\+[\d.,]+ EUR$/

    assert text(view, "#detail-closed-trades-phone-rows li .phone-row__figure") =~
             ~r/^\+[\d.,]+ EUR$/
  end

  # User story (I1, board ① ② on the Chart tab, reading 1):
  # As the operator reading a security's derived metrics,
  # I want the series they are computed over on the page and how they are
  # computed behind the ⓘ that ends that line,
  # so that the grid reads as its figures.
  #
  # Acceptance criteria:
  # - `[data-role=metrics-basis]` is a `div` (a `<details>` is not phrasing
  #   content) that keeps "Over this security's own split-adjusted closes in
  #   USD, never converted." and ends in a section ⓘ holding the gap rule,
  #   the volatility's formula and "Reported, not evaluated: …", one per
  #   line.
  test "Chart: the metrics' basis keeps its series and ends in its ⓘ", %{conn: conn} do
    arbolia = unavailable!()

    {:ok, view, _html} = live(conn, "/securities/#{arbolia.id}?tab=chart")

    basis = ~s(div.detail-tab-hint[data-role="metrics-basis"])

    assert line_text(view, basis) ==
             "Over this security's own split-adjusted closes in USD, never converted."

    assert lines(view, basis <> ~s( > details[data-role="section-info"] p[role="tooltip"])) == [
             "A day without a stored close produces no return observation, so nothing is carried forward and differenced.",
             "Volatility is the population standard deviation of the window's daily returns, annualized by the square root of 252.",
             "Reported, not evaluated: no signal, rating or recommendation is derived here."
           ]
  end

  # User story (I1, board ① ② ③ on the Quotes tab; found while drawing 1):
  # As the operator reading a security's stored quotes,
  # I want the price basis said once, what the Stored column shows behind
  # the ⓘ that ends that line, and the manual-quote note cut to two lines
  # with „Release…“ below it,
  # so that the table starts right under its basis.
  #
  # Acceptance criteria:
  # - `[data-role=quotes-basis]` is a `div` reading "Price basis: as
  #   recorded." once; its ⓘ holds "The stored column keeps the unmodified
  #   values." and "Where a split adjusted a close, “stored” under it shows
  #   the unmodified value.", one per line. In German „Kursbasis: wie
  #   erfasst.“ once.
  # - The manual-quote note clamps; its text keeps both sentences, the
  #   precedence one ("A manual quote has precedence: …") among them, and
  #   „Release…“ sits in its actions.
  test "Quotes: the price basis once, the Stored column in its ⓘ, the note clamps",
       %{conn: conn} do
    world = WorldFixtures.base_world(name: "Muster")

    harborline =
      WorldFixtures.create_security!(name: "Harborline Freight Inc", ticker: "HBLF")

    WorldFixtures.buy!(world, harborline, quantity: "2", price: "33", date: Clock.today())
    WorldFixtures.put_quote!(harborline, Clock.today(), "33.00")

    {:ok, view, _html} = live(conn, "/securities/#{harborline.id}?tab=quotes")

    basis = ~s(div.detail-tab-hint[data-role="quotes-basis"])
    assert line_text(view, basis) == "Price basis: as recorded."

    assert lines(view, basis <> ~s( > details[data-role="section-info"] p[role="tooltip"])) == [
             "The stored column keeps the unmodified values.",
             "Where a split adjusted a close, “stored” under it shows the unmodified value."
           ]

    note = ~s([data-role="manual-quotes-note"].data-note--clamped)

    assert text(view, note <> " .data-note__text") =~
             "A manual quote has precedence: the quote sync leaves it standing until it is released."

    assert has_element?(
             view,
             note <> ~s( .data-note__actions [data-role="release-manual-quotes"])
           )

    {:ok, de_view, _html} = live(conn, "/securities/#{harborline.id}?tab=quotes&locale=de")
    assert line_text(de_view, basis) == "Kursbasis: wie erfasst."
  end

  # User story (I1, board ① ② on the Research and Dates tabs, reading 1):
  # As the operator opening a security's research log or its dates,
  # I want the set on the page and the rule behind the ⓘ that ends it,
  # so that the tab starts with its entries.
  #
  # Acceptance criteria:
  # - Research: the line keeps "Dated, sourced entries about this
  #   security."; its ⓘ holds "Entries are never edited or removed; …".
  # - Dates: `[data-role=events-basis]` keeps "Dated calendar facts about
  #   this security."; its ⓘ holds "An event books nothing: …".
  test "Research and Dates: the set stays, the rule sits in the line's ⓘ", %{conn: conn} do
    harborline =
      WorldFixtures.create_security!(name: "Harborline Freight Inc", ticker: "HBLF")

    {:ok, view, _html} = live(conn, "/securities/#{harborline.id}?tab=research")

    research = "#detail-tab-panel-research > div.detail-tab-hint"
    assert line_text(view, research) == "Dated, sourced entries about this security."

    assert lines(view, research <> ~s( > details[data-role="section-info"] p[role="tooltip"])) ==
             [
               "Entries are never edited or removed; a wrong finding is withdrawn by a retraction that supersedes it, and both stay visible."
             ]

    {:ok, view, _html} = live(conn, "/securities/#{harborline.id}?tab=events")

    events = ~s(div.detail-tab-hint[data-role="events-basis"])
    assert line_text(view, events) == "Dated calendar facts about this security."

    assert lines(view, events <> ~s( > details[data-role="section-info"] p[role="tooltip"])) == [
             "An event books nothing: when a dividend is actually paid it is booked through the ledger as always and the event is marked confirmed."
           ]
  end

  # User story (#1334 on the security page, assigned by the board):
  # As the operator opening an international bond,
  # I want its avatar to be its initial, not a flag that stands for no
  # country,
  # so that "XS" never reads as a country.
  #
  # Acceptance criteria:
  # - A bond whose ISIN starts "XS" shows the initial avatar ("L") in the
  #   detail pane and no flag; a German bond keeps its flag.
  test "an international bond's avatar is its initial, not a flag", %{conn: conn} do
    {:ok, larkspur} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Larkspur Supranational 2033",
        isin: "XSLARKSPUR33",
        currency_code: "EUR",
        asset_class: "bond"
      })

    {:ok, view, _html} = live(conn, "/securities/#{larkspur.id}")

    refute has_element?(view, "#security-detail-pane .security-logo--flag")
    assert text(view, "#security-detail-pane .security-logo--initial") == "L"

    {:ok, gravonia} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Gravonia Federal Bond",
        isin: "DEEXMPL20530",
        currency_code: "EUR",
        asset_class: "bond"
      })

    {:ok, view, _html} = live(conn, "/securities/#{gravonia.id}")
    assert has_element?(view, "#security-detail-pane .security-logo--flag")
  end
end
