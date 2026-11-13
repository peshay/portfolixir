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

  defp german(conn),
    do:
      PortfolixirWeb.PreferenceCookieHelpers.put_preference_cookie(
        conn,
        "portfolixir_locale",
        "de"
      )

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
  #   /securities?dq=implausible_quote&holding=held, and the note takes the
  #   problem severity, never attention.
  # - Since #1414 (Sprint 29 D1) the set holds sold securities too; the line
  #   still counts the held ones it names, so a sold-out "Linden Optik AG"
  #   whose quotes contradict its bookings is not counted, and its link
  #   carries holding=held so the count opens a list of the same size.
  # - The finding stands after the two-scales finding, which names a bond
  #   this guard therefore leaves out; the linked list holds the two named,
  #   the list without the holding filter the sold one as well.
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

    linden = create_security!(name: "Linden Optik AG", ticker: "LOP")
    buy!(world, linden, quantity: "10", price: "400.00", date: ~D[2023-03-01])
    sell!(world, linden, quantity: "10", price: "420.00", date: ~D[2024-06-03])
    put_quote!(linden, ~D[2024-06-03], "105.00")

    {:ok, view, _html} = live(german(conn), "/")
    render_async(view)

    assert has_element?(
             view,
             ~s(#dashboard-dq-line a[data-role="dq-implausible-quote"][href="/securities?dq=implausible_quote&holding=held"]),
             "2 gehaltene Wertpapiere, deren Kurse nicht zu ihren Buchungen passen"
           )

    assert has_element?(view, "#dashboard-data-quality .data-note--problem")
    refute has_element?(view, "#dashboard-data-quality .data-note--attention")

    assert view |> roles("#dashboard-dq-line") |> Enum.take(-2) ==
             ["dq-two-scales", "dq-implausible-quote"]

    {:ok, list, _html} = live(german(conn), "/securities?dq=implausible_quote&holding=held")
    assert has_element?(list, "td", "Arbolia Inc.")
    assert has_element?(list, "td", "Wrenfield Gardens AG")
    refute has_element?(list, "td", "Kestrel Anleihe 2030 2,75%")
    refute has_element?(list, "td", "Linden Optik AG")

    {:ok, list, _html} = live(german(conn), "/securities?dq=implausible_quote")
    assert has_element?(list, "td", "Linden Optik AG")

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
  #   (after dq-two-scales, whose bond it leaves out; the problems lead the
  #   block since I1, #1351), reading as the board
  #   draws it: the sentence, linking to
  #   /securities?dq=implausible_quote&holding=held (the held positions it
  #   counts, since #1414 widened the set to sold ones; PR 2 closing act),
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
             ~s([data-role="dq-implausible-quote"].data-note--problem a[href="/securities?dq=implausible_quote&holding=held"])
           )

    for security <- [arbolia, wrenfield] do
      assert has_element?(
               wealth,
               ~s([data-role="dq-implausible-quote"] .data-note__actions a[href="/securities/#{security.id}?tab=quotes"]),
               security.name
             )

      # Pick Q1, correction 2 (closing act): each entry's link, the remedy,
      # sits in the note's actions, never under the clamp.
      refute has_element?(
               wealth,
               ~s([data-role="dq-implausible-quote"] .data-note__text a[href="/securities/#{security.id}?tab=quotes"])
             )
    end

    # The last of the problem notes, which lead the block since I1 (#1351,
    # board 01 ⑤): the notes that name excluded rows and the fold follow.
    assert [_ | _] = order = roles(wealth, ~s([data-role="dq-notes"]))

    problems =
      Enum.filter(
        order,
        &(&1 in ~w(dq-negative-holdings dq-two-scales dq-two-scales-reverse dq-implausible-quote))
      )

    assert List.last(problems) == "dq-implausible-quote"
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

  # The line's text after the finding's link, up to the next finding.
  defp effect(view, role), do: text(view, ~s(#dashboard-dq-line [data-effect-of="#{role}"]))

  # User story (#1121, the card half, Sprint 21 γ1; board 01 ③, pick N3 A):
  # As the operator reading the Overview's total, I want the data-quality
  # line to say what a bond on two scales and a held security whose quotes
  # contradict its bookings do to the total above, so that I know the figure
  # I just read is wrong, not only that a list somewhere has entries.
  #
  # Acceptance criteria:
  # - After the two-scales link, outside it, in the note's body: "— sie
  #   zählt in der Summe oben hundertfach zu hoch oder zu niedrig" for one
  #   bond (English "— it counts a hundredfold too high or too low in the
  #   total above"); since issue 1417 the count is the held bonds', so the
  #   clause has no "if held".
  # - After the implausible-quote link, outside it: "— ihr Wert in der Summe
  #   oben oder ihr Einstand ist daher falsch" for two (English "— so their
  #   value in the total above, or their cost, is wrong").
  # - Each link keeps its count and noun alone, to its pre-filtered list.
  # - The card stays silent: no note in the card's section names either
  #   finding, and the line keeps the problem severity.
  test "the line says what each wrongly valued finding does to the total above", %{conn: conn} do
    world = base_world(name: "EUR Depot")
    arbolia!()
    wrenfield!(world)
    two_scales_bond!(world)

    {:ok, view, _html} = live(german(conn), "/")
    render_async(view)

    assert text(view, ~s(#dashboard-dq-line a[data-role="dq-two-scales"])) ==
             "eine gehaltene Anleihe auf zwei Skalen bepreist"

    assert effect(view, "dq-two-scales") ==
             "— sie zählt in der Summe oben hundertfach zu hoch oder zu niedrig"

    assert text(view, ~s(#dashboard-dq-line a[data-role="dq-implausible-quote"])) ==
             "2 gehaltene Wertpapiere, deren Kurse nicht zu ihren Buchungen passen"

    assert effect(view, "dq-implausible-quote") ==
             "— ihr Wert in der Summe oben oder ihr Einstand ist daher falsch"

    # The clause is the note's body text, never inside the link.
    refute has_element?(view, ~s(#dashboard-dq-line a [data-effect-of]))
    assert has_element?(view, "#dashboard-data-quality .data-note--problem")
    refute has_element?(view, "#dashboard-wealth .data-note", "Skalen")
    refute has_element?(view, "#dashboard-wealth .data-note", "Buchungen")

    {:ok, view, _html} = live(conn, "/")
    render_async(view)

    assert effect(view, "dq-two-scales") ==
             "— it counts a hundredfold too high or too low in the total above"

    assert effect(view, "dq-implausible-quote") ==
             "— so their value in the total above, or their cost, is wrong"
  end

  test "the effect clauses read in their other number", %{conn: conn} do
    world = base_world(name: "EUR Depot")
    wrenfield!(world)
    two_scales_bond!(world)

    {:ok, bond} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Plover Anleihe 2029 1,50%",
        currency_code: "EUR",
        asset_class: "bond"
      })

    buy!(world, bond, quantity: "5000", price: "0.97", date: ~D[2026-03-12])
    put_quote!(bond, ~D[2026-03-12], "96.80")

    {:ok, view, _html} = live(german(conn), "/")
    render_async(view)

    assert text(view, ~s(#dashboard-dq-line a[data-role="dq-two-scales"])) ==
             "2 gehaltene Anleihen auf zwei Skalen bepreist"

    assert effect(view, "dq-two-scales") ==
             "— jede zählt in der Summe oben hundertfach zu hoch oder zu niedrig"

    assert effect(view, "dq-implausible-quote") ==
             "— sein Wert in der Summe oben oder sein Einstand ist daher falsch"

    {:ok, view, _html} = live(conn, "/")
    render_async(view)

    assert effect(view, "dq-two-scales") ==
             "— each counts a hundredfold too high or too low in the total above"

    assert effect(view, "dq-implausible-quote") ==
             "— so its value in the total above, or its cost, is wrong"
  end
end
