defmodule PortfolixirWeb.ImplausibleQuoteLiveTest do
  # #1101 (Sprint 20 β B4, plan D-7; board ux-design-2026-10-07/02-money-findings,
  # pick L2 A, problem severity): a held security whose stored quotes
  # contradict its own bookings is named where the data-quality family
  # names things — the securities list's removable chip, the Overview's
  # data-quality line and Wealth's notes.
  #
  # The data is the board's, invented: "Arbolia Inc." (USD) sold 03.04.2026
  # at 61,40 with no quote that day and 618,90 the day before; "Wrenfield
  # Gardens AG" (EUR) bought 12.05.2026 at 48,20 with 4,87 that day.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, put_quote!: 3, sell!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Classifications
  alias Portfolixir.Clock
  alias Portfolixir.Fx

  defp german(conn), do: Plug.Test.put_req_cookie(conn, "portfolixir_locale", "de")

  defp text(view, selector) do
    view
    |> element(selector)
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.text()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp roles(view, selector) do
    view
    |> element(selector)
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.attribute("[data-role]", "data-role")
  end

  # Wealth opens on a classification tree.
  defp strategy! do
    {:ok, _} = Classifications.create_classification(Actor.owner_ui(), %{name: "Strategie"})
  end

  # The board's Arbolia, held in a USD portfolio, with a current USD rate so
  # Wealth values it.
  defp arbolia! do
    usd = base_world(name: "USD Depot", currency: "USD")
    arbolia = create_security!(name: "Arbolia Inc.", ticker: "ARBL", currency: "USD")
    buy!(usd, arbolia, quantity: "50", price: "58.20", currency: "USD", date: ~D[2025-11-03])
    sell!(usd, arbolia, quantity: "10", price: "61.40", currency: "USD", date: ~D[2026-04-03])
    put_quote!(arbolia, ~D[2026-04-02], "618.90")
    put_quote!(arbolia, Clock.today(), "619.40")

    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: Clock.today(),
          rate: "1.10",
          source: "manual"
        }
      ])

    arbolia
  end

  # A bond the two-scales guard names (quotes near 100 beside a booking near
  # 1), whose own booking day's quote would trip this guard too.
  defp two_scales_bond!(world) do
    {:ok, bond} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Kestrel Anleihe 2030 2,75%",
        currency_code: "EUR",
        asset_class: "bond"
      })

    buy!(world, bond, quantity: "10000", price: "0.985", date: ~D[2026-03-12])
    put_quote!(bond, ~D[2026-03-12], "97.25")
    bond
  end

  defp wrenfield!(world) do
    wrenfield = create_security!(name: "Wrenfield Gardens AG", ticker: "WGA")
    buy!(world, wrenfield, quantity: "120", price: "48.20", date: ~D[2026-05-12])
    put_quote!(wrenfield, ~D[2026-05-12], "4.87")
    wrenfield
  end

  # User story (#1101; board 02, L2 A, the securities list):
  # As the operator following the finding to its list,
  # I want the list opened on exactly the named securities under a
  # removable chip that says why,
  # so that I see the set and can clear the filter.
  #
  # Acceptance criteria:
  # - /securities?dq=implausible_quote lists Wrenfield and not a security
  #   whose quotes match its bookings, under the removable chip "Kurs passt
  #   nicht zu Buchungen" (German) / "Quote does not match bookings"
  #   (English); there is no one-tap chip for it.
  test "the securities list opens on the set under a removable chip", %{conn: conn} do
    world = base_world(name: "Depot")
    wrenfield!(world)

    plain = create_security!(name: "Halden Robotics AG", ticker: "HRB")
    buy!(world, plain, quantity: "30", price: "10.00", date: ~D[2024-01-10])
    put_quote!(plain, ~D[2024-01-10], "10.20")

    {:ok, list, _html} = live(german(conn), "/securities?dq=implausible_quote")
    assert has_element?(list, "#filter-chips .chip", "Kurs passt nicht zu Buchungen")
    assert has_element?(list, "td", "Wrenfield Gardens AG")
    refute has_element?(list, "td", "Halden Robotics AG")
    refute has_element?(list, "#sec-chip-implausible_quote")

    {:ok, list, _html} = live(conn, "/securities?dq=implausible_quote")
    assert has_element?(list, "#filter-chips .chip", "Quote does not match bookings")
  end

  # User story (#1101; board 02, L2 A, the Overview's line):
  # As the operator reading the Overview,
  # I want the data-quality line to count the held securities whose quotes
  # do not match their own bookings, at problem severity,
  # so that a total off by a factor of ten raises the alarm a hundredfold
  # one does, and its count opens a list of the same size (#705).
  #
  # Acceptance criteria:
  # - Arbolia and Wrenfield read "2 gehaltene Wertpapiere, deren Kurse nicht
  #   zu ihren Buchungen passen" on the German line, linking to
  #   /securities?dq=implausible_quote, and the note takes the problem
  #   severity, never attention.
  # - The finding stands after the two-scales finding, which names a bond
  #   this guard therefore leaves out; the linked list holds the two named.
  # - One held security reads "ein gehaltenes Wertpapier, dessen Kurse nicht
  #   zu seinen Buchungen passen" in German, and "one held security whose
  #   quotes do not match its bookings" / "2 held securities whose quotes do
  #   not match their bookings" in English.
  test "the data-quality line counts the held securities whose quotes contradict their bookings",
       %{conn: conn} do
    world = base_world(name: "EUR Depot")
    arbolia!()
    wrenfield!(world)
    two_scales_bond!(world)

    {:ok, view, _html} = live(german(conn), "/")
    render_async(view)

    assert has_element?(
             view,
             ~s(#dashboard-dq-line a[data-role="dq-implausible-quote"][href="/securities?dq=implausible_quote"]),
             "2 gehaltene Wertpapiere, deren Kurse nicht zu ihren Buchungen passen"
           )

    assert has_element?(view, "#dashboard-data-quality .data-note--problem")
    refute has_element?(view, "#dashboard-data-quality .data-note--attention")

    assert view |> roles("#dashboard-dq-line") |> Enum.take(-2) ==
             ["dq-two-scales", "dq-implausible-quote"]

    {:ok, list, _html} = live(german(conn), "/securities?dq=implausible_quote")
    assert has_element?(list, "td", "Arbolia Inc.")
    assert has_element?(list, "td", "Wrenfield Gardens AG")
    refute has_element?(list, "td", "Kestrel Anleihe 2030 2,75%")

    {:ok, view, _html} = live(conn, "/")
    render_async(view)

    assert has_element?(
             view,
             ~s(#dashboard-dq-line a[data-role="dq-implausible-quote"]),
             "2 held securities whose quotes do not match their bookings"
           )
  end

  test "one held security on the line reads in the singular", %{conn: conn} do
    wrenfield!(base_world(name: "EUR Depot"))

    {:ok, view, _html} = live(german(conn), "/")
    render_async(view)

    assert text(view, ~s(#dashboard-dq-line a[data-role="dq-implausible-quote"])) ==
             "ein gehaltenes Wertpapier, dessen Kurse nicht zu seinen Buchungen passen"

    assert has_element?(view, "#dashboard-data-quality .data-note--problem")

    {:ok, view, _html} = live(conn, "/")
    render_async(view)

    assert text(view, ~s(#dashboard-dq-line a[data-role="dq-implausible-quote"])) ==
             "one held security whose quotes do not match its bookings"
  end

  # User story (#1101; board 02, L2 A, Wealth's notes):
  # As the operator reading the totals on Wealth,
  # I want a problem note naming each held position valued at quotes that
  # contradict its own bookings, with the booking and the quote of its day,
  # so that I know the total is wrong, why, and what to check first.
  #
  # Acceptance criteria:
  # - dq-implausible-quote is a problem note after the other problem notes
  #   (after dq-two-scales, whose bond it leaves out), reading as the board
  #   draws it: the sentence, linking to /securities?dq=implausible_quote,
  #   then "Arbolia Inc. (Verkauf 03.04.2026 zu 61,4 USD · Kurs 02.04.2026:
  #   618,9 USD, das 10,08-Fache)" and "Wrenfield Gardens AG (Kauf
  #   12.05.2026 zu 48,2 EUR · Kurs 12.05.2026: 4,87 EUR, das 0,10-Fache)".
  # - Each name links to its security's Quotes tab, the link holding the
  #   name alone.
  # - In English, for one position: "One held position is valued at quotes
  #   … then the booking:" and "(buy 2026-05-12 at 48.2 EUR · quote
  #   2026-05-12: 4.87 EUR, 0.10 times that)".
  test "Wealth names each position whose quotes contradict its bookings, in a problem note",
       %{conn: conn} do
    world = base_world(name: "EUR Depot")
    strategy!()
    arbolia = arbolia!()
    wrenfield = wrenfield!(world)
    two_scales_bond!(world)

    {:ok, wealth, _html} = live(german(conn), "/portfolio")
    render_async(wealth)

    note = text(wealth, ~s([data-role="dq-implausible-quote"]))

    assert note =~
             "2 gehaltene Positionen werden mit Kursen bewertet, die nicht zu ihren eigenen " <>
               "Buchungen passen (am Buchungstag unter der Hälfte oder über dem Doppelten des " <>
               "Preises je Stück); ihr Wert oder ihr Einstand ist daher falsch. Ihre " <>
               "Kursquellen prüfen (Ticker, Börse), dann die Buchungen:"

    assert note =~
             "Arbolia Inc. (Verkauf 03.04.2026 zu 61,4 USD · Kurs 02.04.2026: 618,9 USD, " <>
               "das 10,08-Fache)"

    assert note =~
             "Wrenfield Gardens AG (Kauf 12.05.2026 zu 48,2 EUR · Kurs 12.05.2026: 4,87 EUR, " <>
               "das 0,10-Fache)"

    refute note =~ "Kestrel"

    assert has_element?(
             wealth,
             ~s([data-role="dq-implausible-quote"].data-note--problem a[href="/securities?dq=implausible_quote"])
           )

    for security <- [arbolia, wrenfield] do
      assert has_element?(
               wealth,
               ~s([data-role="dq-implausible-quote"] a[href="/securities/#{security.id}?tab=quotes"]),
               security.name
             )
    end

    assert [_ | _] = order = roles(wealth, ~s([data-role="dq-notes"]))
    assert List.last(order) == "dq-implausible-quote"
    assert "dq-two-scales" in order
  end

  test "Wealth's note reads in English, for one position", %{conn: conn} do
    wrenfield!(base_world(name: "EUR Depot"))
    strategy!()

    {:ok, wealth, _html} = live(conn, "/portfolio")
    render_async(wealth)

    note = text(wealth, ~s([data-role="dq-implausible-quote"]))

    assert note =~
             "One held position is valued at quotes that do not match its own bookings (on a " <>
               "booking's day, below half or above twice the price per unit), so its value or " <>
               "its cost is wrong. Check its quote source (ticker, exchange), then the booking:"

    assert note =~
             "Wrenfield Gardens AG (buy 2026-05-12 at 48.2 EUR · quote 2026-05-12: 4.87 EUR, " <>
               "0.10 times that)"
  end
end
