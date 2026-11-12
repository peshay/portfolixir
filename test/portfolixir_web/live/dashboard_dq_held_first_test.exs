defmodule PortfolixirWeb.DashboardDqHeldFirstTest do
  # Issue 1417 (Sprint 29 D2; board ux-design-2026-11-12-sprint29/04, pick
  # A; the owner's answer of 2026-11-07 to OQ-4, reversing Sprint 19 J1.2):
  # the Overview counts each data-quality set of securities over the held
  # ones first, its link opening Wertpapiere with the Held chip; the
  # catalogue count stands after it in parentheses, as its own link, where
  # the two differ. With every held count 0 the line has no clause about
  # securities; the catalogue count stays on Wertpapiere's chips and over
  # the API.
  #
  # The data is invented: "Halde Kupfer" held, "Verkauft Textil" bought
  # and sold out, "Nie Gehalten AG" never booked (a name without a legal
  # form, so no asset class is inferred from it).
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 0, buy!: 3, create_security!: 1, put_quote!: 3, sell!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Clock

  @auth {"authorization", "Bearer test-api-token"}

  defp german(conn),
    do:
      PortfolixirWeb.PreferenceCookieHelpers.put_preference_cookie(
        conn,
        "portfolixir_locale",
        "de"
      )

  defp overview(conn) do
    {:ok, view, _html} = live(conn, "/")
    render_async(view)
    view
  end

  defp text(view, selector) do
    view
    |> element(selector)
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.text()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp href(view, selector) do
    [href] =
      view
      |> element(selector)
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.attribute("href")

    href
  end

  # The list a link opens, counted as the operator sees it: its rows.
  defp rows(conn, href) do
    {:ok, list, _html} = live(conn, href)

    list
    |> render()
    |> Floki.parse_document!()
    |> Floki.find("#securities-table tbody tr.security-row")
    |> length()
  end

  # The agent's count of the same set.
  defp api_count(_conn, query) do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header(elem(@auth, 0), elem(@auth, 1))
    |> get("/api/v1/securities?" <> query)
    |> json_response(200)
    |> Map.fetch!("data")
    |> length()
  end

  # "one …" is the singular; a plural opens on its figure.
  defp leading_count(text) do
    case Regex.run(~r/^\(?(\d+)/, text, capture: :all_but_first) do
      [n] -> String.to_integer(n)
      nil -> 1
    end
  end

  # One held security with a stale quote, no logo and no class; one sold
  # out the same; one never booked, never priced, classed.
  defp seed_catalogue_wider_than_held do
    world = base_world()
    stale = Date.add(Clock.today(), -30)

    held = create_security!(name: "Halde Kupfer", ticker: "HKU", asset_class: nil)
    buy!(world, held, quantity: "10", price: "20", date: ~D[2026-03-02])
    put_quote!(held, stale, "21")

    sold = create_security!(name: "Verkauft Textil", ticker: "VTX", asset_class: nil)
    buy!(world, sold, quantity: "5", price: "40", date: ~D[2026-02-02])
    sell!(world, sold, quantity: "5", price: "42", date: ~D[2026-04-02])
    put_quote!(sold, stale, "43")

    _never = create_security!(name: "Nie Gehalten AG", ticker: "NGH")

    world
  end

  # User story (issue 1417, board 04 ② A):
  # As the operator who sold securities long ago and never retired them,
  # I want the Overview's data-quality line to count my held securities
  # first, with the catalogue count beside it where it differs,
  # so that the line clears when what I hold is in order, and the catalogue
  # stays one link away.
  #
  # Acceptance criteria:
  # - The quote, class and logo clauses count the held securities, each
  #   linking to Wertpapiere with holding=held, whose list has that many
  #   rows, as the API's holding_status=held answers.
  # - After each, "(n in the catalog)" links the catalogue list, whose rows
  #   and the API's unfiltered answer are n.
  # - The KPI cell reads "1 held stale" and links the held list.
  test "each security set counts the held first, the catalogue after it where it differs",
       %{conn: conn} do
    seed_catalogue_wider_than_held()
    view = overview(conn)

    assert text(view, ~s(#dashboard-dq-line a[data-role="dq-quotes"])) ==
             "one held security without a quote in 7 days"

    assert href(view, ~s(#dashboard-dq-line a[data-role="dq-quotes"])) ==
             "/securities?dq=stale_quote&holding=held"

    assert text(view, ~s(#dashboard-dq-line [data-catalog-of="dq-quotes"])) ==
             "(3 in the catalog)"

    assert href(view, ~s(#dashboard-dq-line [data-catalog-of="dq-quotes"] a)) ==
             "/securities?dq=stale_quote"

    assert text(view, ~s(#dashboard-dq-line a[data-role="dq-class"])) ==
             "one without an asset class"

    assert text(view, ~s(#dashboard-dq-line [data-catalog-of="dq-class"])) ==
             "(2 in the catalog)"

    assert text(view, ~s(#dashboard-dq-line a[data-role="dq-logo"])) == "one without a logo"

    assert text(view, ~s(#dashboard-dq-line [data-catalog-of="dq-logo"])) ==
             "(3 in the catalog)"

    # Each count opens a list of its size, and the agent reads the same.
    for {role, dq} <- [{"dq-quotes", "stale_quote"}, {"dq-logo", "missing_logo"}] do
      held_href = href(view, ~s(#dashboard-dq-line a[data-role="#{role}"]))
      held = leading_count(text(view, ~s(#dashboard-dq-line a[data-role="#{role}"])))
      assert held_href =~ "holding=held"
      assert rows(conn, held_href) == held
      assert api_count(conn, "data_quality=#{dq}&holding_status=held") == held

      catalog_href = href(view, ~s(#dashboard-dq-line [data-catalog-of="#{role}"] a))
      catalog = leading_count(text(view, ~s(#dashboard-dq-line [data-catalog-of="#{role}"])))
      refute catalog_href =~ "holding="
      assert rows(conn, catalog_href) == catalog
      assert api_count(conn, "data_quality=#{dq}") == catalog
    end

    class_href = href(view, ~s(#dashboard-dq-line a[data-role="dq-class"]))
    assert class_href =~ "holding=held"
    assert rows(conn, class_href) == 1
    assert rows(conn, href(view, ~s(#dashboard-dq-line [data-catalog-of="dq-class"] a))) == 2

    assert href(view, ~s(a[data-role="kpi-freshness"])) ==
             "/securities?dq=stale_quote&holding=held"

    assert text(view, ~s([data-role="kpi-freshness"] .kpi-strip__sub--attention)) ==
             "1 held stale"
  end

  # Acceptance criteria (German, board 04 ② and the KPI cell):
  # - "ein gehaltenes Wertpapier ohne Kurs seit 7 Tagen (im Katalog 3)".
  # - The KPI cell reads "1 gehaltenes veraltet".
  test "the German line and cell read the held count and the catalogue in parentheses",
       %{conn: conn} do
    seed_catalogue_wider_than_held()
    view = overview(german(conn))

    assert text(view, ~s(#dashboard-dq-line a[data-role="dq-quotes"])) ==
             "ein gehaltenes Wertpapier ohne Kurs seit 7 Tagen"

    assert text(view, ~s(#dashboard-dq-line [data-catalog-of="dq-quotes"])) ==
             "(im Katalog 3)"

    assert text(view, ~s([data-role="kpi-freshness"] .kpi-strip__sub--attention)) ==
             "1 gehaltenes veraltet"
  end

  # Acceptance criteria (board 04 ②, "where both are equal, no parenthesis"):
  # - With every flagged security held, the clauses carry no catalogue
  #   count, and their count still opens a list of its size.
  test "a set whose held and catalogue counts agree carries one link", %{conn: conn} do
    world = base_world()

    for {name, ticker} <- [{"Halde Kupfer AG", "HKU"}, {"Halde Zinn AG", "HZN"}] do
      security = create_security!(name: name, ticker: ticker)
      buy!(world, security, quantity: "10", price: "20", date: ~D[2026-03-02])
      put_quote!(security, Date.add(Clock.today(), -30), "21")
    end

    view = overview(conn)

    assert text(view, ~s(#dashboard-dq-line a[data-role="dq-quotes"])) ==
             "2 held securities without a quote in 7 days"

    refute has_element?(view, "#dashboard-dq-line [data-catalog-of]")
    assert rows(conn, href(view, ~s(#dashboard-dq-line a[data-role="dq-quotes"]))) == 2
    assert api_count(conn, "data_quality=stale_quote&holding_status=held") == 2
    assert api_count(conn, "data_quality=stale_quote") == 2
  end

  # User story (issue 1417, board 04 ⑤):
  # As the operator whose held securities are all in order,
  # I want no data-quality section on the Overview while only sold or
  # never-held securities are flagged,
  # so that the hint clears without retiring anything.
  #
  # Acceptance criteria:
  # - No section, no line, the KPI cell without its sub-line.
  # - The catalogue sets stay reachable: Wertpapiere's chip lists them,
  #   and the API answers the same count.
  test "no section while every held count is 0; the catalogue stays on Wertpapiere",
       %{conn: conn} do
    world = base_world()

    held = create_security!(name: "Halde Kupfer AG", ticker: "HKU")
    buy!(world, held, quantity: "10", price: "20", date: ~D[2026-03-02])
    put_quote!(held, Clock.today(), "21")
    {:ok, _} = Catalog.put_logo_attributes(held, %{"logo_path" => "logos/hku.png"})

    sold = create_security!(name: "Verkauft Textil AG", ticker: "VTX", asset_class: nil)
    buy!(world, sold, quantity: "5", price: "40", date: ~D[2026-02-02])
    sell!(world, sold, quantity: "5", price: "42", date: ~D[2026-04-02])
    put_quote!(sold, Date.add(Clock.today(), -30), "43")

    view = overview(conn)

    refute has_element?(view, "#dashboard-data-quality")
    refute has_element?(view, ~s([data-role="data-quality-line"]))
    refute has_element?(view, ~s([data-role="kpi-freshness"] .kpi-strip__sub))

    {:ok, list, _html} = live(conn, "/securities")
    assert has_element?(list, "#sec-chip-stale_quote")
    assert rows(conn, "/securities?dq=stale_quote") == 1
    assert api_count(conn, "data_quality=stale_quote") == 1
    assert rows(conn, "/securities?dq=missing_logo") == 1
    assert api_count(conn, "data_quality=missing_logo") == 1
  end

  # Acceptance criteria (board 04 ②, the effect text): a set counted over
  # the held loses its "if held" — every one it counts is in the total.
  test "the two-scales and currency clauses say their effect without 'if held'",
       %{conn: conn} do
    world = base_world()

    bond =
      create_security!(name: "Kestrel Anleihe 2030 2,75%", ticker: "KST", asset_class: "bond")

    buy!(world, bond, quantity: "100", price: "0.985", date: ~D[2026-03-12])
    put_quote!(bond, Date.add(Clock.today(), -1), "97.25")

    mismatched = create_security!(name: "Lerchenfeld Optik AG", ticker: "LFO")
    buy!(world, mismatched, quantity: "10", price: "20", date: ~D[2026-03-02])
    put_quote!(mismatched, Date.add(Clock.today(), -1), "21")

    {:ok, _} =
      Catalog.put_provider_currency(
        Actor.system_job("quote_sync"),
        mismatched,
        "USD",
        DateTime.utc_now()
      )

    view = overview(conn)

    assert text(view, ~s(#dashboard-dq-line a[data-role="dq-two-scales"])) ==
             "one held bond priced on two scales"

    assert href(view, ~s(#dashboard-dq-line a[data-role="dq-two-scales"])) ==
             "/securities?dq=two_scales&holding=held"

    assert text(view, ~s(#dashboard-dq-line [data-effect-of="dq-two-scales"])) ==
             "— it counts a hundredfold too high or too low in the total above"

    assert text(view, ~s(#dashboard-dq-line a[data-role="dq-currency-mismatch"])) ==
             "one held security whose provider reports another currency than its own"

    assert href(view, ~s(#dashboard-dq-line a[data-role="dq-currency-mismatch"])) ==
             "/securities?dq=currency_mismatch&holding=held"

    assert text(view, ~s(#dashboard-dq-line [data-effect-of="dq-currency-mismatch"])) ==
             "— its quotes may be stored in the wrong currency, so its value in the total above is wrong"

    german = overview(german(conn))

    assert text(german, ~s(#dashboard-dq-line [data-effect-of="dq-two-scales"])) ==
             "— sie zählt in der Summe oben hundertfach zu hoch oder zu niedrig"

    assert text(german, ~s(#dashboard-dq-line [data-effect-of="dq-currency-mismatch"])) ==
             "— seine Kurse sind womöglich in der falschen Währung gespeichert; sein Wert in der Summe oben ist daher falsch"
  end
end
