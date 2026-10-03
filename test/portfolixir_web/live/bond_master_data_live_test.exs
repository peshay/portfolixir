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
  #   the issue date, Kupon 2,50 % p. a. jährlich, Nominal im Bestand
  #   10.000,00 EUR from 100 Stück × 100 EUR with the Stückelung 1.000 EUR.
  # - The second row shows the remaining term in years and months, the
  #   current yield 2,57 % from 2,50 ÷ 97,25 with the quote's date, and the
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
    assert strip =~ "Kupon 2,50 % p. a. jährlich"
    assert strip =~ "Nominal im Bestand 10.000,00 EUR 100 Stück × 100 EUR · Stückelung 1.000 EUR"

    term = BondMetrics.remaining_term(@maturity, Clock.today())
    assert strip =~ "Restlaufzeit #{term.whole_years} J. #{term.whole_months} M."
    assert strip =~ "Laufende Rendite 2,57 % 2,50 ÷ 97,25 (2026-09-30)"
    assert strip =~ "Rendite bis Fälligkeit ≈"
    assert strip =~ "linear angenähert"

    basis = text(view, ~s([data-role="bond-basis"]))
    assert basis =~ "Ein Stück im Bestand ist ein Hundertstel des Nominals"
    assert basis =~ "(Kupon + (100 − Kurs) ÷ Restlaufzeit in Jahren) ÷ Kurs"
    assert basis =~ "das Jahr zu 365 Tagen"
    assert basis =~ "Ohne Stückzinsen, Gebühren und Steuern"

    refute has_element?(view, ~s([data-role="two-scales-note"]))
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
             "2,54 % 2,50 ÷ 98,50, letzter eigener Handelspreis"

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
    assert note =~ "gebuchter Preis je Stück um 1 (1 Kauf: 0,985 am 2026-03-12)"
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
    assert dq =~ "Musterland Anleihe 2031 (Kurs 97,25 · Preis je Stück 0,985)"

    assert has_element?(
             wealth,
             ~s([data-role="dq-two-scales"] a[href="/securities/#{face.id}?tab=transactions"])
           )

    refute dq =~ "Musterland Anleihe 2029"

    {:ok, view, _html} = live(german(conn), "/securities/#{hundredth.id}")
    refute has_element?(view, ~s([data-role="two-scales-note"]))
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

    assert text(view, ~s([data-role="bond-strip"])) =~ "Kupon 2,50 % p. a. jährlich"

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
end
