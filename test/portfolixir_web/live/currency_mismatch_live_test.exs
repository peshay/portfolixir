defmodule PortfolixirWeb.CurrencyMismatchLiveTest do
  # #1415 (Sprint 28 Q3; board ux-design-2026-11-08-sprint28/05, plan D-6):
  # the `currency_mismatch` set on the Overview's data-quality line, one
  # clause after the implausible series with its effect on the total, and
  # its one-tap chip „Währung abweichend“ beside „Kein Wechselkurs“ on the
  # securities page. Every name and figure is invented.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, put_quote!: 3]

  alias Portfolixir.Catalog

  @read_at ~U[2026-11-09 08:15:00Z]

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

  defp effect(view, role), do: text(view, ~s(#dashboard-dq-line [data-effect-of="#{role}"]))

  # A security whose provider stated `stated` at a sync.
  defp stated!(name, ticker, stated) do
    security = create_security!(name: name, ticker: ticker)

    {:ok, security} =
      Catalog.put_provider_currency(
        Portfolixir.Actor.system_job("quote_sync"),
        security,
        stated,
        @read_at
      )

    security
  end

  # The Overview leaves onboarding once a booking exists: one held security
  # whose quote matches its booking, which the line names for nothing but
  # its stale quote.
  defp booked_world! do
    world = base_world(name: "EUR Depot")
    held = create_security!(name: "Held Line AG", ticker: "HLA")
    buy!(world, held, quantity: "10", price: "50.00", date: ~D[2026-05-12])
    put_quote!(held, ~D[2026-05-12], "50.00")
    world
  end

  # The board's implausible series: bought at 48,20, quoted 4,87 that day.
  defp implausible!(world) do
    wrenfield = create_security!(name: "Wrenfield Gardens AG", ticker: "WRG")
    buy!(world, wrenfield, quantity: "20", price: "48.20", date: ~D[2026-05-12])
    put_quote!(wrenfield, ~D[2026-05-12], "4.87")
    wrenfield
  end

  # Since issue 1417 the Overview counts the held ones first: the API's
  # `holding_status=held` answers that count, the unfiltered read the
  # catalogue's.
  defp api_count(conn, extra \\ "") do
    conn
    |> Phoenix.ConnTest.recycle()
    |> put_req_header("authorization", "Bearer test-api-token")
    |> put_req_header("accept", "application/json")
    |> get("/api/v1/securities?data_quality=currency_mismatch" <> extra)
    |> json_response(200)
    |> Map.fetch!("data")
    |> length()
  end

  # User story (#1415; board 05 ②):
  # As the operator reading the Overview,
  # I want the securities whose provider reports another currency than their
  # own counted on the data-quality line, after the implausible series, with
  # what they do to the total above,
  # so that a series stored in the wrong currency is an alarm where I look
  # first, and one tap opens exactly those securities.
  #
  # Acceptance criteria:
  # - The clause reads „2 gehaltene Wertpapiere, deren Anbieter eine andere
  #   Währung meldet als ihre eigene“, links to
  #   /securities?dq=currency_mismatch&holding=held, „(im Katalog 3)“ after
  #   it to the catalogue's list, and is followed, outside the link, by
  #   „— ihre Kurse sind womöglich in der falschen Währung gespeichert; ihr
  #   Wert in der Summe oben ist daher falsch“; English "2 held securities
  #   whose provider reports another currency than their own" and "— their
  #   quotes may be stored in the wrong currency, so their value in the
  #   total above is wrong" (issue 1417: held first, no "if held").
  # - It stands right after the implausible series, and the note takes the
  #   problem severity.
  # - The count is the API's answer for the same set: a benchmark with
  #   another stated currency, and one whose provider stated its own, are
  #   in neither.
  test "the data-quality line counts the securities whose provider reports another currency",
       %{conn: conn} do
    world = base_world(name: "EUR Depot")
    implausible!(world)

    for {name, ticker, stated} <- [
          {"Dollar Line AG", "DLA", "USD"},
          {"Pence Line plc", "PLP", "GBp"},
          {"Own Line AG", "OLA", "EUR"}
        ] do
      buy!(world, stated!(name, ticker, stated), quantity: "1", price: "10", date: ~D[2026-05-12])
    end

    stated!("Sold Line AG", "SLA", "USD")

    {:ok, benchmark} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "Benchmark Line",
        currency_code: "EUR",
        is_benchmark: true
      })

    {:ok, _} =
      Catalog.put_provider_currency(
        Portfolixir.Actor.system_job("quote_sync"),
        benchmark,
        "USD",
        @read_at
      )

    {:ok, view, _html} = live(german(conn), "/")
    render_async(view)

    assert has_element?(
             view,
             ~s(#dashboard-dq-line a[data-role="dq-currency-mismatch"][href="/securities?dq=currency_mismatch&holding=held"]),
             "2 gehaltene Wertpapiere, deren Anbieter eine andere Währung meldet als ihre eigene"
           )

    assert text(view, ~s(#dashboard-dq-line a[data-role="dq-currency-mismatch"])) ==
             "2 gehaltene Wertpapiere, deren Anbieter eine andere Währung meldet als ihre eigene"

    assert has_element?(
             view,
             ~s(#dashboard-dq-line [data-catalog-of="dq-currency-mismatch"] a[href="/securities?dq=currency_mismatch"]),
             "im Katalog 3"
           )

    assert effect(view, "dq-currency-mismatch") ==
             "— ihre Kurse sind womöglich in der falschen Währung gespeichert; " <>
               "ihr Wert in der Summe oben ist daher falsch"

    refute has_element?(view, ~s(#dashboard-dq-line a [data-effect-of]))
    assert has_element?(view, "#dashboard-data-quality .data-note--problem")

    assert view |> roles("#dashboard-dq-line") |> Enum.take(-2) ==
             ["dq-implausible-quote", "dq-currency-mismatch"]

    assert api_count(conn, "&holding_status=held") == 2
    assert api_count(conn) == 3

    {:ok, view, _html} = live(conn, "/")
    render_async(view)

    assert text(view, ~s(#dashboard-dq-line a[data-role="dq-currency-mismatch"])) ==
             "2 held securities whose provider reports another currency than their own"

    assert effect(view, "dq-currency-mismatch") ==
             "— their quotes may be stored in the wrong currency, so their value in " <>
               "the total above is wrong"
  end

  test "one security on the line reads in the singular", %{conn: conn} do
    world = booked_world!()
    dollar = stated!("Dollar Line AG", "DLA", "USD")
    buy!(world, dollar, quantity: "1", price: "10", date: ~D[2026-05-12])

    {:ok, view, _html} = live(german(conn), "/")
    render_async(view)

    assert text(view, ~s(#dashboard-dq-line a[data-role="dq-currency-mismatch"])) ==
             "ein gehaltenes Wertpapier, dessen Anbieter eine andere Währung meldet als seine eigene"

    refute has_element?(view, ~s([data-catalog-of="dq-currency-mismatch"]))

    assert effect(view, "dq-currency-mismatch") ==
             "— seine Kurse sind womöglich in der falschen Währung gespeichert; " <>
               "sein Wert in der Summe oben ist daher falsch"

    assert has_element?(view, "#dashboard-data-quality .data-note--problem")
    assert api_count(conn, "&holding_status=held") == 1
    assert api_count(conn) == 1

    {:ok, view, _html} = live(conn, "/")
    render_async(view)

    assert text(view, ~s(#dashboard-dq-line a[data-role="dq-currency-mismatch"])) ==
             "one held security whose provider reports another currency than its own"

    assert effect(view, "dq-currency-mismatch") ==
             "— its quotes may be stored in the wrong currency, so its value in the " <>
               "total above is wrong"
  end

  test "a provider that stated the security's own currency, or none yet, adds no clause",
       %{conn: conn} do
    booked_world!()
    stated!("Own Line AG", "OLA", "EUR")
    create_security!(name: "Never Read AG", ticker: "NRA")

    {:ok, view, _html} = live(conn, "/")
    render_async(view)

    # The line is there (both securities are unpriced), without the clause.
    assert has_element?(view, "#dashboard-dq-line")
    refute has_element?(view, ~s([data-role="dq-currency-mismatch"]))
  end

  # User story (#1415; board 05 ③):
  # As the operator working the list,
  # I want a one-tap chip „Währung abweichend“ beside „Kein Wechselkurs“,
  # so that the securities whose provider reports another currency are one
  # tap away, as the other sets are.
  #
  # Acceptance criteria:
  # - The chip `#sec-chip-currency_mismatch` reads „Währung abweichend“ and
  #   follows `#sec-chip-missing_fx` in the chip row.
  # - Tapping it patches to ?dq=currency_mismatch, presses it and lists
  #   exactly the set; the condition is not repeated as a removable chip.
  # - The Overview's link lands on the same pressed chip.
  test "the chip „Währung abweichend“ filters the list to the set", %{conn: conn} do
    stated!("Dollar Line AG", "DLA", "USD")
    stated!("Own Line AG", "OLA", "EUR")

    {:ok, view, html} = live(german(conn), "/securities")

    assert text(view, "#sec-chip-currency_mismatch") == "Währung abweichend"

    ids =
      html
      |> Floki.parse_document!()
      |> Floki.find("#securities-filter-chips .filter-chip")
      |> Enum.flat_map(&Floki.attribute(&1, "id"))

    after_fx = ids |> Enum.drop_while(&(&1 != "sec-chip-missing_fx")) |> Enum.take(2)
    assert after_fx == ["sec-chip-missing_fx", "sec-chip-currency_mismatch"]

    view |> element("#sec-chip-currency_mismatch") |> render_click()
    assert_patch(view, "/securities?dq=currency_mismatch")

    assert view |> element("#sec-chip-currency_mismatch") |> render() =~ ~s(aria-pressed="true")
    assert has_element?(view, "td", "Dollar Line AG")
    refute has_element?(view, "td", "Own Line AG")
    refute has_element?(view, "#filter-chips")

    {:ok, linked, _html} = live(german(conn), "/securities?dq=currency_mismatch")
    assert linked |> element("#sec-chip-currency_mismatch") |> render() =~ ~s(aria-pressed="true")
    assert has_element?(linked, "td", "Dollar Line AG")
  end
end
