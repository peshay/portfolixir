defmodule PortfolixirWeb.BondMasterDataLiveTest do
  # #330 (ADR-0052; Sprint 18 pick H3 = A, board
  # ux-design-2026-10-02/03-bond-master-data): the bond strip on a bond's
  # Overview, its states, the dialog's bond section, the two-scales note on
  # the Overview and in Wealth → Holdings → data quality. German pages, as
  # the board draws them. Every bond, ISIN, figure and date is invented.
  use PortfolixirWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures, only: [base_world: 0, buy!: 3, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Classifications
  alias Portfolixir.Clock
  alias Portfolixir.Engines.BondMetrics
  alias Portfolixir.Portfolios.Bonds
  alias Portfolixir.Repo

  @maturity ~D[2031-06-15]

  defp german(conn), do: Plug.Test.put_req_cookie(conn, "portfolixir_locale", "de")

  defp bond!(attrs \\ %{}) do
    {:ok, security} =
      Catalog.create_security(
        Actor.owner_ui(),
        Map.merge(
          %{
            name: "Musterland Anleihe 2031",
            isin: "XSLIVEBD0318",
            currency_code: "EUR",
            asset_class: "government_bond",
            coupon_rate: "2.5",
            coupon_frequency: "annual",
            maturity_date: @maturity,
            issue_date: ~D[2021-06-15],
            face_value: "1000"
          },
          attrs
        )
      )

    security
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

  # User story (#330, pick H3-A, A1):
  # As the operator reading a bond I hold at a hundredth of its face amount,
  # I want its Overview to show the maturity, the coupon and the nominal I
  # hold, and beneath them the remaining term and both yields with their
  # basis,
  # so that I can check the bond against its statement on the page where
  # its price and value already stand.
  #
  # Acceptance criteria:
  # - Under the six figures a block headed "Anleihe" shows Fälligkeit with
  #   the issue date, Kupon 2,5 % p. a. jährlich, Nominal im Bestand
  #   10.000,00 EUR from 100 Stück × 100 EUR with the Stückelung 1.000 EUR.
  # - The second row shows the remaining term in years and months, the
  #   current yield 2,57 % from 2,5 ÷ 97,25 with the quote's date, and the
  #   yield to maturity with "≈" and "linear angenähert".
  # - One basis line states the hundredth convention, both formulas, the
  #   365-day year and what is excluded.
  # - Nothing is named as priced on two scales.
  test "a bond's Overview shows its master data, the nominal held and the metrics", %{
    conn: conn
  } do
    bond = bond!()
    buy!(base_world(), bond, quantity: "100", price: "98.50", date: ~D[2026-03-12])
    put_quote!(bond, ~D[2026-09-30], "97.25")

    {:ok, view, _html} = live(german(conn), "/securities/#{bond.id}")

    strip = text(view, ~s([data-role="bond-strip"]))
    assert strip =~ "Anleihe"
    assert strip =~ "Fälligkeit 2031-06-15 Emission 2021-06-15"
    assert strip =~ "Kupon 2,5 % p. a. jährlich"
    assert strip =~ "Nominal im Bestand 10.000,00 EUR 100 Stück × 100 EUR · Stückelung 1.000 EUR"

    term = BondMetrics.remaining_term(@maturity, Clock.today())
    assert strip =~ "Restlaufzeit #{term.whole_years} J. #{term.whole_months} M."
    assert strip =~ "Laufende Rendite 2,57 % 2,5 ÷ 97,25 (2026-09-30)"
    assert strip =~ "Rendite bis Fälligkeit ≈"
    assert strip =~ "linear angenähert"

    basis = text(view, ~s([data-role="bond-basis"]))
    assert basis =~ "Ein Stück im Bestand ist ein Hundertstel des Nominals"
    assert basis =~ "(Kupon + (100 − Kurs) ÷ Restlaufzeit in Jahren) ÷ Kurs"
    assert basis =~ "das Jahr zu 365 Tagen"
    assert basis =~ "Ohne Stückzinsen, Gebühren und Steuern"

    refute has_element?(view, ~s([data-role="two-scales-note"]))
  end

  # User story (#330, closing act on U7, finding 2):
  # As the operator checking a bond's coupon and price against the statement,
  # I want the block to show the coupon I entered and the price the yield
  # used as they are stored,
  # so that a 4,125 % coupon does not read as 4,13 % beside a yield computed
  # from 4,125.
  #
  # Acceptance criteria:
  # - A coupon of 4.125 reads "Kupon 4,125 %", trailing zeros trimmed.
  # - The current yield's ratio line reads "4,125 ÷ 97,125" for a quote of
  #   97.125; the computed yields keep their two places.
  test "the coupon and the price in the ratio line read as stored", %{conn: conn} do
    bond = bond!(%{coupon_rate: "4.125"})
    buy!(base_world(), bond, quantity: "100", price: "98.50", date: ~D[2026-03-12])
    put_quote!(bond, ~D[2026-09-30], "97.125")

    {:ok, view, _html} = live(german(conn), "/securities/#{bond.id}")

    assert text(view, ~s([data-role="bond-coupon"])) == "Kupon 4,125 % p. a. jährlich"

    assert text(view, ~s([data-role="bond-current-yield"])) ==
             "Laufende Rendite 4,25 % 4,125 ÷ 97,125 (2026-09-30)"
  end

  # User story (#330, board A2, A3 and A4):
  # As the operator reading a bond whose master data is missing, partly
  # entered, unpriced by any quote, or matured,
  # I want the block to say what it cannot compute and why, and offer the
  # dialog where the data is entered,
  # so that a missing figure is never shown as a number.
  #
  # Acceptance criteria:
  # - With no master data one sentence says what is missing, its remedy
  #   "Anleihedaten erfassen…" opens the security dialog with the bond
  #   section, and the nominal held still stands with the convention.
  # - Trade-priced, the yields use the last own trade price and say so.
  # - Matured, the term reads "fällig seit …" and both yields "nicht
  #   berechenbar".
  # - A share has no bond block.
  test "the block names what it cannot compute, and its remedy opens the dialog", %{conn: conn} do
    world = base_world()

    bare =
      bond!(%{
        name: "Musterland Anleihe 2029",
        isin: "XSLIVEBD0292",
        coupon_rate: nil,
        coupon_frequency: nil,
        maturity_date: nil,
        issue_date: nil,
        face_value: nil
      })

    buy!(world, bare, quantity: "100", price: "99.10", date: ~D[2026-03-12])

    {:ok, view, _html} = live(german(conn), "/securities/#{bare.id}")

    assert text(view, ~s([data-role="bond-empty"])) =~
             "Kupon, Fälligkeit und Stückelung sind nicht erfasst"

    assert text(view, ~s([data-role="bond-nominal-hint"])) =~
             "Nominal im Bestand: 10.000,00 EUR, 100 Stück × 100 EUR (ein Stück ist ein Hundertstel des Nominals)."

    view |> element(~s([data-role="bond-empty"] button)) |> render_click()
    assert has_element?(view, ~s(#security-dialog-form [data-role="bond-fields"]))

    trade_priced = bond!()
    buy!(world, trade_priced, quantity: "100", price: "98.50", date: ~D[2026-03-12])
    {:ok, view, _html} = live(german(conn), "/securities/#{trade_priced.id}")

    assert text(view, ~s([data-role="bond-current-yield"])) =~
             "2,54 % 2,5 ÷ 98,5, letzter eigener Handelspreis"

    matured =
      bond!(%{
        name: "Musterland Anleihe 2025",
        isin: "XSLIVEBD0250",
        maturity_date: ~D[2025-06-15],
        issue_date: ~D[2015-06-15]
      })

    buy!(world, matured, quantity: "10", price: "99", date: ~D[2024-03-12])
    {:ok, view, _html} = live(german(conn), "/securities/#{matured.id}")

    assert text(view, ~s([data-role="bond-remaining-term"])) =~ "fällig seit 2025-06-15"
    assert text(view, ~s([data-role="bond-current-yield"])) =~ "nicht berechenbar"
    assert text(view, ~s([data-role="bond-yield-to-maturity"])) =~ "nicht berechenbar"

    {:ok, share} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Nordwind Industrie AG",
        currency_code: "EUR",
        asset_class: "equity"
      })

    {:ok, view, _html} = live(german(conn), "/securities/#{share.id}")
    refute has_element?(view, ~s([data-role="bond-strip"]))
  end

  # User story (#330, closing act on U7, finding 3; board
  # ux-review-2026-10-03/04-bond-repairs, B2):
  # As the operator whose export booked a bond's nominal as its quantity,
  # with no quote stored yet,
  # I want the block to say the yields cannot be computed from my trade
  # price of 0,984 per unit, and why,
  # so that "254,07 %" and "≈ 2.393,17 %" never stand beside the bond.
  #
  # Acceptance criteria:
  # - Both yield cells read "nicht berechenbar" with the reason
  #   "Handelspreis 0,984 je Stück, keine Prozentnotiz"; no percent figure
  #   stands in either.
  # - The nominal held stays as booked, 1.000.000,00 EUR.
  test "a trade price on the unit scale gives no yield, and the block says why", %{conn: conn} do
    bond = bond!()
    buy!(base_world(), bond, quantity: "10000", price: "0.984", date: ~D[2026-03-12])

    {:ok, view, _html} = live(german(conn), "/securities/#{bond.id}")

    for cell <- ~w(bond-current-yield bond-yield-to-maturity) do
      reading = text(view, ~s([data-role="#{cell}"]))
      assert reading =~ "nicht berechenbar"
      assert reading =~ "Handelspreis 0,984 je Stück, keine Prozentnotiz"
      refute reading =~ "%"
    end

    assert text(view, ~s([data-role="bond-nominal"])) =~ "1.000.000,00 EUR"
  end

  # User story (#330, the two-scales guard W1 and W2; bond discovery,
  # point 5):
  # As the operator whose export booked a bond's nominal as its quantity,
  # I want a problem note on the bond's Overview and in Wealth → Holdings →
  # data quality naming the two scales, with the way to the bookings,
  # so that the hundredfold value the return hides cannot pass unnoticed.
  #
  # Acceptance criteria:
  # - Bought 10.000 at 0,985 and quoted 97,25: the Overview's problem note
  #   names both scales, the buy and its date, the consequence, and links to
  #   the security's Transactions tab; the figures stay as they are.
  # - Wealth → Holdings lists the bond in a problem note linking to the same
  #   tab, with its quote and price per unit.
  # - A bond in the hundredth reading, held beside it, raises neither note.
  test "a bond priced on two scales is named on its Overview and in Wealth data quality", %{
    conn: conn
  } do
    world = base_world()
    # The Wealth page reads its allocation against a classification.
    {:ok, _tree} = Classifications.create_classification(Actor.owner_ui(), %{name: "Strategie"})
    face = bond!()
    buy!(world, face, quantity: "10000", price: "0.985", date: ~D[2026-03-12])
    put_quote!(face, ~D[2026-09-30], "97.25")

    hundredth = bond!(%{name: "Musterland Anleihe 2029", isin: "XSLIVEBD0292"})
    buy!(world, hundredth, quantity: "100", price: "99.10", date: ~D[2026-03-12])
    put_quote!(hundredth, ~D[2026-09-30], "98.40")

    {:ok, view, _html} = live(german(conn), "/securities/#{face.id}")

    note = text(view, ~s([data-role="two-scales-note"]))
    assert note =~ "Problem"
    assert note =~ "Auf zwei Skalen bepreist: Kurse um 100 (zuletzt 97,25 am 2026-09-30)"
    assert note =~ "gebuchter Preis je Stück um 1 (1 Buchung: 0,985 am 2026-03-12)"
    assert note =~ "Wert, Gewinn und Gewicht sind hundertfach zu hoch"
    assert note =~ "die Rendite (TTWROR) zeigt es nicht"

    assert has_element?(
             view,
             ~s([data-role="two-scales-note"] a[href="/securities/#{face.id}?tab=transactions"])
           )

    assert text(view, ~s([data-role="bond-strip"])) =~ "Nominal im Bestand 1.000.000,00 EUR"

    {:ok, wealth, _html} = live(german(conn), "/portfolio")
    render_async(wealth)

    dq = text(wealth, ~s([data-role="dq-two-scales"]))
    assert dq =~ "Eine Anleihe ist auf zwei Skalen bepreist"
    assert dq =~ "Stückzahl ihrer Buchungen gegen das Nominal der Abrechnung prüfen"
    assert dq =~ "Musterland Anleihe 2031 (Kurs 97,25 · Preis je Stück 0,985)"

    assert has_element?(
             wealth,
             ~s([data-role="dq-two-scales"] a[href="/securities/#{face.id}?tab=transactions"])
           )

    refute dq =~ "Musterland Anleihe 2029"

    {:ok, view, _html} = live(german(conn), "/securities/#{hundredth.id}")
    refute has_element?(view, ~s([data-role="two-scales-note"]))
  end

  # User story (#1068, D-15; board 02, pins 3 and 4):
  # As the operator whose bonds may be priced on two scales either way, or
  # carry master data but no asset class,
  # I want Wealth's data quality to name a bond whose quotes sit near 1
  # beside bookings near 100 in a problem note of its own, with the way to
  # its quotes, and to mark a named bond that has no asset class,
  # so that a bond counting a hundredfold too low is named, and I see why a
  # security the catalog does not call a bond is named.
  #
  # Acceptance criteria:
  # - A bond bought at 98,40 and quoted 0,981 is named in
  #   dq-two-scales-reverse, a problem note reading as board 02 draws it,
  #   its name linking to its Quotes tab with "Kurs 0,981 · Preis je Stück
  #   98,4" (both figures as Format.exact writes them, as the forward note's).
  # - The forward note keeps its sentence, now in the plural for two bonds,
  #   and names the unclassed bond with its maturity date beside the classed
  #   one; only the unclassed one carries the neutral "ohne Anlageklasse"
  #   badge. Each link's text is the name alone, and one space separates
  #   the entries (closing act, UAT).
  # - An unclassed security with no master data, quoted 25 times its buy
  #   price, is named in neither note, and its Overview has no bond block.
  # - The unclassed bond's own Overview shows the bond block and the forward
  #   note; the reverse bond's shows the block and no two-scales note, since
  #   that note's sentence states the forward direction only.
  test "Wealth names the reverse case in a note of its own, and marks a bond without a class",
       %{conn: conn} do
    world = base_world()
    {:ok, _tree} = Classifications.create_classification(Actor.owner_ui(), %{name: "Strategie"})

    forward = bond!(%{name: "Kestrel Anleihe 2030 2,75%", isin: "XSLIVEBD0301"})
    buy!(world, forward, quantity: "10000", price: "0.985", date: ~D[2026-03-12])
    put_quote!(forward, ~D[2026-09-30], "97.25")

    {:ok, unclassed} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Ostsee Logistik 4,10% 2028/2033",
        currency_code: "EUR",
        maturity_date: ~D[2033-06-30]
      })

    assert unclassed.asset_class == nil
    buy!(world, unclassed, quantity: "10000", price: "0.991", date: ~D[2026-03-12])
    put_quote!(unclassed, ~D[2026-09-30], "99.10")

    reverse = bond!(%{name: "Birkenhain Wasser Anleihe 2029 1,50%", isin: "XSLIVEBD0293"})
    buy!(world, reverse, quantity: "100", price: "98.40", date: ~D[2026-03-12])
    put_quote!(reverse, ~D[2026-09-30], "0.981")

    {:ok, share} =
      Catalog.create_security(Actor.owner_ui(), %{name: "Ostsee Holz", currency_code: "EUR"})

    buy!(world, share, quantity: "10", price: "4", date: ~D[2026-03-12])
    put_quote!(share, ~D[2026-09-30], "100")

    {:ok, wealth, _html} = live(german(conn), "/portfolio")
    render_async(wealth)

    reverse_note = text(wealth, ~s([data-role="dq-two-scales-reverse"]))

    assert reverse_note =~
             "Eine Anleihe ist auf zwei Skalen bepreist (Kurse um 1, gebuchter Preis je Stück um 100) " <>
               "und zählt hundertfach zu niedrig in den Summen. Ihre gespeicherten Kurse prüfen — " <>
               "ein Kurs um 1 ist kein Prozent vom Nennwert:"

    assert reverse_note =~
             "Birkenhain Wasser Anleihe 2029 1,50% (Kurs 0,981 · Preis je Stück 98,4)"

    assert reverse_note =~ "Problem"
    refute reverse_note =~ "Kestrel"

    assert has_element?(
             wealth,
             ~s([data-role="dq-two-scales-reverse"].data-note--problem a[href="/securities/#{reverse.id}?tab=quotes"])
           )

    forward_note = text(wealth, ~s([data-role="dq-two-scales"]))

    assert forward_note =~
             "2 Anleihen sind auf zwei Skalen bepreist (Kurse um 100, gebuchter Preis je Stück um 1) " <>
               "und zählen hundertfach zu hoch in den Summen; die Rendite zeigt es nicht. " <>
               "Stückzahl ihrer Buchungen gegen das Nominal der Abrechnung prüfen:"

    assert forward_note =~ "Kestrel Anleihe 2030 2,75% (Kurs 97,25 · Preis je Stück 0,985)"

    assert forward_note =~
             "Ostsee Logistik 4,10% 2028/2033 ohne Anlageklasse (Kurs 99,1 · Preis je Stück 0,991)"

    refute forward_note =~ "Birkenhain"

    # Closing act (UAT): each link's text is the name alone, so its
    # underline ends at the name (the space between entries is pinned on
    # the raw render below, which this page's DOM does not keep).
    assert wealth
           |> element(~s([data-role="dq-two-scales"]))
           |> render()
           |> Floki.parse_fragment!()
           |> Floki.find("a")
           |> Enum.map(&Floki.text/1) == [
             "Kestrel Anleihe 2030 2,75%",
             "Ostsee Logistik 4,10% 2028/2033"
           ]

    assert has_element?(
             wealth,
             ~s([data-role="dq-two-scales"] a[href="/securities/#{unclassed.id}?tab=transactions"])
           )

    assert [_one] =
             wealth
             |> element(~s([data-role="dq-two-scales"]))
             |> render()
             |> Floki.parse_fragment!()
             |> Floki.find(".badge.badge--neutral")

    refute render(wealth) =~ "Ostsee Holz ("

    # The unclassed bond is read as a bond on its own Overview too; the
    # reverse case has no Overview note yet, and never the forward sentence.
    {:ok, detail, _html} = live(german(conn), "/securities/#{unclassed.id}")
    assert has_element?(detail, ~s([data-role="bond-strip"]))
    assert text(detail, ~s([data-role="two-scales-note"])) =~ "Kurse um 100"

    {:ok, detail, _html} = live(german(conn), "/securities/#{reverse.id}")
    assert has_element?(detail, ~s([data-role="bond-strip"]))
    refute has_element?(detail, ~s([data-role="two-scales-note"]))

    {:ok, detail, _html} = live(german(conn), "/securities/#{share.id}")
    refute has_element?(detail, ~s([data-role="bond-strip"]))
  end

  # User story (closing act of Sprint 19 PR α, UAT):
  # As the operator reading a two-scales note that names several bonds,
  # I want one space between the entries and each link ending at the name,
  # so that the note reads "… 0,985) Ostsee …" rather than running the
  # entries together, and no underline runs over a trailing space.
  #
  # Acceptance criteria:
  # - The entries, rendered as the page sends them, are separated by one
  #   space outside them: an entry is an inline block, whose own edge
  #   whitespace does not render. (The test DOM drops whitespace-only text,
  #   so this reads the raw render.)
  # - Each link's text is the name alone; the first entry has no space
  #   before it.
  test "two-scales entries are set apart by one space, each link ending at the name" do
    finding = fn id, name ->
      %{
        security_id: id,
        name: name,
        effective_asset_class: "bond",
        latest_quote: %{close: Decimal.new("97.25")},
        last_unit_scale_booking: %{price: Decimal.new("0.985")}
      }
    end

    html =
      render_component(&PortfolixirWeb.PortfolioLive.two_scales_entries/1,
        findings: [finding.(1, "Kestrel Anleihe 2030 2,75%"), finding.(2, "Ostsee Logistik")],
        tab: "transactions"
      )

    assert html =~ ~r{\)\s*</span> <span class="dq-negative-entry">}
    assert [_first, _second] = Regex.scan(~r{<span class="dq-negative-entry">}, html)
    refute html =~ ~r{^\s}
    assert html =~ ~r{<a [^>]*>Kestrel Anleihe 2030 2,75%</a>}
    assert html =~ ~r{<a [^>]*>Ostsee Logistik</a>}
  end

  # User story (#1068, review): the two notes in English, and the badge in
  # the reverse note.
  #
  # Acceptance criteria:
  # - On an English page the forward note keeps its English sentence and
  #   the reverse note reads "One bond is priced on two scales (quotes
  #   around 1, booked price per unit around 100) and counts a hundred times
  #   too low in the totals. Check its stored quotes — a quote around 1 is
  #   not a percent of face:".
  # - An unclassed bond read by its coupon, on the reverse scales, is named
  #   there with the "no asset class" badge, linking to its Quotes tab.
  test "the two-scales notes read in English, and the reverse note carries the badge", %{
    conn: conn
  } do
    world = base_world()
    {:ok, _tree} = Classifications.create_classification(Actor.owner_ui(), %{name: "Strategie"})

    forward = bond!(%{name: "Kestrel Anleihe 2030 2,75%"})
    buy!(world, forward, quantity: "10000", price: "0.985", date: ~D[2026-03-12])
    put_quote!(forward, ~D[2026-09-30], "97.25")

    {:ok, reverse} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Ostsee Hafen Anleihe",
        currency_code: "EUR",
        coupon_rate: "3"
      })

    buy!(world, reverse, quantity: "100", price: "98.40", date: ~D[2026-03-12])
    put_quote!(reverse, ~D[2026-09-30], "0.981")

    {:ok, wealth, _html} = live(conn, "/portfolio")
    render_async(wealth)

    assert text(wealth, ~s([data-role="dq-two-scales"])) =~
             "One bond is priced on two scales (quotes around 100, booked price per unit around 1) " <>
               "and counts a hundred times too high in the totals; the return does not show it."

    reverse_note = text(wealth, ~s([data-role="dq-two-scales-reverse"]))

    assert reverse_note =~
             "One bond is priced on two scales (quotes around 1, booked price per unit around 100) " <>
               "and counts a hundred times too low in the totals. Check its stored quotes — " <>
               "a quote around 1 is not a percent of face:"

    assert reverse_note =~
             "Ostsee Hafen Anleihe no asset class (quote 0.981 · price per unit 98.4)"

    assert has_element?(
             wealth,
             ~s([data-role="dq-two-scales-reverse"] .badge.badge--neutral[data-role="dq-two-scales-unclassed"])
           )

    assert has_element?(
             wealth,
             ~s([data-role="dq-two-scales-reverse"] a[href="/securities/#{reverse.id}?tab=quotes"])
           )

    refute has_element?(wealth, ~s([data-role="dq-two-scales"] .badge))
  end

  # User story (#1068, D-15; review of the master-data signal):
  # As the operator whose security shows no asset class but carries a
  # maturity date and a coupon, and is therefore read as a bond,
  # I want the dialog's bond section to show that data while the class reads
  # blank,
  # so that the data that brings it under the guard can be seen and cleared
  # where it was entered.
  #
  # Acceptance criteria:
  # - Editing it, the class select is blank and the bond section shows the
  #   stored maturity and coupon.
  # - Emptying both and saving clears them; the security is then no bond.
  test "the dialog's bond section shows for a blank class carrying a maturity or coupon", %{
    conn: conn
  } do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Ostsee Logistik 4,10% 2028/2033",
        currency_code: "EUR",
        coupon_rate: "4.1",
        maturity_date: ~D[2033-06-30]
      })

    assert security.asset_class == nil

    {:ok, view, _html} = live(german(conn), "/securities/#{security.id}")
    view |> element("#detail-edit") |> render_click()

    refute has_element?(
             view,
             ~s(#security-dialog-form select[name="security[asset_class]"] option[selected])
           )

    assert has_element?(view, ~s([data-role="bond-fields"]))

    assert has_element?(
             view,
             ~s([data-role="bond-fields"] input[name="security[maturity_date]"][value="2033-06-30"])
           )

    assert has_element?(
             view,
             ~s([data-role="bond-fields"] input[name="security[coupon_rate]"][value="4,1"])
           )

    view
    |> form("#security-dialog-form", security: %{coupon_rate: "", maturity_date: ""})
    |> render_submit()

    cleared = Repo.reload!(security)
    assert cleared.coupon_rate == nil
    assert cleared.maturity_date == nil
    refute Bonds.bond?(cleared)
  end

  # User story (#330, the dialog's bond section F1 and F2):
  # As the operator entering a bond's master data on a German page,
  # I want a bond section in the security dialog while the asset class reads
  # Anleihe or Staatsanleihe, with figures typed the way the page writes
  # them and errors on their fields,
  # so that I enter the data where all master data is entered, and a typo
  # is refused where I made it.
  #
  # Acceptance criteria:
  # - Editing a share shows no bond section; switching the asset class to
  #   Staatsanleihe shows it, its denomination currency preset to the
  #   security's, with the convention stated once.
  # - Saving "2,5" %, jährlich, a maturity and a denomination of 1000 stores
  #   them, and the Overview's bond block shows them at once.
  # - A maturity on the issue date is refused on the maturity field in
  #   German, and so is a grouped coupon; nothing is stored.
  # - Emptying a field clears it.
  test "the dialog's bond section appears for the two bond classes, saves, refuses and clears", %{
    conn: conn
  } do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Musterland Anleihe 2031",
        isin: "XSLIVEBD0318",
        currency_code: "EUR",
        asset_class: "equity"
      })

    {:ok, view, _html} = live(german(conn), "/securities/#{security.id}")
    view |> element("#detail-edit") |> render_click()
    refute has_element?(view, ~s([data-role="bond-fields"]))

    view
    |> form("#security-dialog-form", security: %{asset_class: "government_bond"})
    |> render_change()

    assert has_element?(view, ~s([data-role="bond-fields"]))
    assert text(view, ~s([data-role="bond-fields"] legend)) == "Anleihedaten"

    assert has_element?(
             view,
             ~s([data-role="bond-fields"] select[name="security[face_value_currency_code]"] option[value="EUR"][selected])
           )

    assert text(view, ~s([data-role="bond-fields"] .form-help)) =~
             "Im Bestand ist ein Stück ein Hundertstel des Nominals"

    refused =
      view
      |> form("#security-dialog-form",
        security: %{
          asset_class: "government_bond",
          coupon_rate: "2.500,0",
          maturity_date: "2021-06-15",
          issue_date: "2021-06-15"
        }
      )
      |> render_submit()

    assert refused =~ "ist mehrdeutig: ohne Tausendertrennzeichen eingeben"
    assert Repo.reload!(security).coupon_rate == nil

    refused =
      view
      |> form("#security-dialog-form",
        security: %{
          asset_class: "government_bond",
          coupon_rate: "2,5",
          maturity_date: "2021-06-15",
          issue_date: "2021-06-15"
        }
      )
      |> render_submit()

    assert refused =~ "muss nach dem Emissionstag liegen"
    assert Repo.reload!(security).coupon_rate == nil

    view
    |> form("#security-dialog-form",
      security: %{
        asset_class: "government_bond",
        coupon_rate: "2,5",
        coupon_frequency: "annual",
        maturity_date: "2031-06-15",
        issue_date: "2021-06-15",
        face_value: "1000",
        face_value_currency_code: "EUR"
      }
    )
    |> render_submit()

    stored = Repo.reload!(security)
    assert Decimal.equal?(stored.coupon_rate, Decimal.new("2.5"))
    assert stored.coupon_frequency == "annual"
    assert stored.maturity_date == ~D[2031-06-15]
    assert Decimal.equal?(stored.face_value, Decimal.new("1000"))

    assert text(view, ~s([data-role="bond-strip"])) =~ "Kupon 2,5 % p. a. jährlich"

    view |> element("#detail-edit") |> render_click()

    assert has_element?(
             view,
             ~s(#security-dialog-form input[name="security[coupon_rate]"][value="2,5"])
           )

    view
    |> form("#security-dialog-form", security: %{coupon_rate: "", issue_date: ""})
    |> render_submit()

    cleared = Repo.reload!(security)
    assert cleared.coupon_rate == nil
    assert cleared.issue_date == nil
    assert cleared.maturity_date == ~D[2031-06-15]
  end

  # User story (#330, closing act on U7, finding 7; board
  # ux-review-2026-10-03/04-bond-repairs, B5):
  # As the operator correcting a bond's master data on a German page,
  # I want every refusal of one save shown at once, a figure the page
  # cannot read and a date the security cannot carry alike,
  # so that I fix the form in one round instead of meeting the next error
  # after the first is fixed.
  #
  # Acceptance criteria:
  # - "1.000" as the coupon with a maturity before the issue date: the
  #   coupon's ambiguity and "muss nach dem Emissionstag liegen" under the
  #   maturity stand together after one save.
  # - Nothing is stored.
  test "the dialog names a refused figure and the changeset's errors in one round", %{
    conn: conn
  } do
    bond = bond!()

    {:ok, view, _html} = live(german(conn), "/securities/#{bond.id}")
    view |> element("#detail-edit") |> render_click()

    refused =
      view
      |> form("#security-dialog-form",
        security: %{coupon_rate: "1.000", maturity_date: "2020-06-15", issue_date: "2021-06-15"}
      )
      |> render_submit()

    assert refused =~ "ist mehrdeutig: ohne Tausendertrennzeichen eingeben"
    assert refused =~ "muss nach dem Emissionstag liegen"

    assert has_element?(
             view,
             ~s(#security-dialog-form input[name="security[maturity_date]"][aria-invalid="true"])
           )

    stored = Repo.reload!(bond)
    assert Decimal.equal?(stored.coupon_rate, Decimal.new("2.5"))
    assert stored.maturity_date == @maturity
  end

  # User story (#330, closing act on U7, finding 8):
  # As the operator editing a bond that has no denomination,
  # I want a save that touches no denomination to write no denomination
  # currency,
  # so that the currency select starting on the security's currency is a
  # convenience, not a value stored behind my back.
  #
  # Acceptance criteria:
  # - Editing a bond without a denomination and saving a new coupon leaves
  #   face_value_currency_code empty, though the select showed EUR.
  # - Entering a denomination writes the currency the select shows with it.
  test "the denomination's currency is written only with a denomination", %{conn: conn} do
    bond = bond!(%{face_value: nil})

    {:ok, view, _html} = live(german(conn), "/securities/#{bond.id}")
    view |> element("#detail-edit") |> render_click()

    assert has_element?(
             view,
             ~s(#security-dialog-form select[name="security[face_value_currency_code]"] option[value="EUR"][selected])
           )

    view |> form("#security-dialog-form", security: %{coupon_rate: "3"}) |> render_submit()

    plain = Repo.reload!(bond)
    assert Decimal.equal?(plain.coupon_rate, Decimal.new("3"))
    assert plain.face_value_currency_code == nil

    view |> element("#detail-edit") |> render_click()

    view
    |> form("#security-dialog-form",
      security: %{face_value: "1000", face_value_currency_code: "USD"}
    )
    |> render_submit()

    denominated = Repo.reload!(bond)
    assert Decimal.equal?(denominated.face_value, Decimal.new("1000"))
    assert denominated.face_value_currency_code == "USD"
  end

  # The fake search provider's one listing (`arbolia`, NASDAQ in USD) matches
  # this bond by provider and online id, so picking it shows the conflict.
  # The bond's terms are invented.
  defp listed_bond! do
    {:ok, bond} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Arbolia Inc. Anleihe 2031",
        ticker_symbol: "ARBL",
        isin: "USEXMPL10014",
        currency_code: "USD",
        asset_class: "bond",
        provider: "portfolio_performance",
        online_id: "usexmpl10014",
        coupon_rate: "3.75",
        coupon_frequency: "annual",
        maturity_date: ~D[2031-06-15],
        issue_date: ~D[2021-06-15],
        face_value: "1000"
      })

    bond
  end

  # Search, pick the listing and its market: the dialog shows the conflict.
  # The listing reads as a share, so the asset class is set back to bond,
  # and the bond section stands with blank fields, its currency select on
  # the listing's currency.
  defp conflict_dialog(conn) do
    {:ok, view, _html} = live(conn, "/securities")
    view |> element("#open-new-dialog") |> render_click()
    view |> element("button[phx-value-mode='security']") |> render_click()

    view
    |> element("#security-form-dialog form")
    |> render_change(%{"dialog_query" => "arbolia"})

    view |> element("#security-form-dialog .search-result") |> render_click()

    view
    |> element("#security-form-dialog .market-list button[phx-value-idx='0']")
    |> render_click()

    assert has_element?(view, "#security-form-dialog", "This security already exists")

    view
    |> element("#security-dialog-form")
    |> render_change(%{"security" => %{"asset_class" => "bond"}})

    assert has_element?(
             view,
             ~s(#security-dialog-form input[name="security[coupon_rate]"][value=""])
           )

    view
  end

  defp assert_terms_kept(bond) do
    kept = Repo.reload!(bond)

    assert Decimal.equal?(kept.coupon_rate, Decimal.new("3.75"))
    assert kept.maturity_date == ~D[2031-06-15]
    assert kept.issue_date == ~D[2021-06-15]
    assert Decimal.equal?(kept.face_value, Decimal.new("1000"))
    assert kept.face_value_currency_code == nil, "a denomination currency nobody chose"
    kept
  end

  # User story (#330, closing act on U7, finding 1):
  # As the operator adding a listing of a bond the catalog already holds,
  # I want "Update existing" to leave the bond's master data alone unless I
  # type a value into its section,
  # so that resolving a duplicate never wipes the coupon, maturity and
  # denomination entered before.
  #
  # Acceptance criteria:
  # - With the conflict shown and the bond section blank, "Update existing"
  #   keeps the coupon, maturity, issue date and denomination, and writes no
  #   denomination currency: the select only starts on the listing's.
  # - A bond field chosen in that form is written: the payment becomes
  #   semi-annual.
  test "Update existing keeps a bond's master data the form left blank", %{conn: conn} do
    bond = listed_bond!()
    view = conflict_dialog(conn)

    view
    |> form("#security-dialog-form", security: %{coupon_frequency: "semi_annual"})
    |> render_submit()

    refute has_element?(view, "#security-dialog-form")
    assert assert_terms_kept(bond).coupon_frequency == "semi_annual"
  end

  # User story (#330, closing act on U7, finding 1):
  # As the operator merging a listing's online fields into a bond the
  # catalog already holds,
  # I want the merge to leave the bond's master data alone,
  # so that "Merge online fields" brings the listing's fields and nothing
  # else changes.
  #
  # Acceptance criteria:
  # - With the conflict shown and the bond section blank, "Merge online
  #   fields" keeps the coupon, its payment, the maturity, the issue date and
  #   the denomination, and writes no denomination currency.
  test "Merge online fields keeps a bond's master data the form left blank", %{conn: conn} do
    bond = listed_bond!()
    view = conflict_dialog(conn)

    # Every field of the form as the page holds it, the blank bond fields
    # and the preset currency select included.
    view |> form("#security-dialog-form") |> render_change()

    view
    |> element("#security-form-dialog button", "Merge online fields")
    |> render_click()

    refute has_element?(view, "#security-dialog-form")
    assert assert_terms_kept(bond).coupon_frequency == "annual"
  end
end
