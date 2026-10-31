defmodule PortfolixirWeb.SecuritiesDqNotesTest do
  # Sprint 21 γ2, board `ux-design-2026-10-09/02-securities`: the problem
  # notes the securities pages carry for a data-quality finding — the list's
  # two-scales notes (#1121's list half, pick N3.2 A) and a security's
  # Overview notes for the reverse two scales and an implausible quote
  # (#1112, pick N7 A). German pages, as the board draws them. Every name,
  # identifier, figure and date is invented.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures, only: [base_world: 0, buy!: 3, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Clock

  @css File.read!("priv/static/app.css")

  defp german(conn),
    do:
      PortfolixirWeb.PreferenceCookieHelpers.put_preference_cookie(
        conn,
        "portfolixir_locale",
        "de"
      )

  defp bond!(attrs) do
    {:ok, security} =
      Catalog.create_security(
        Actor.owner_ui(),
        Map.merge(
          %{
            currency_code: "EUR",
            asset_class: "bond",
            coupon_rate: "3.0",
            coupon_frequency: "annual",
            maturity_date: ~D[2031-06-15],
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

  defp block(selector) do
    case Regex.run(~r/\n#{Regex.escape(selector)} \{([^}]*)\}/, @css) do
      [_, body] -> body
      nil -> flunk("no top-level rule for #{selector}")
    end
  end

  # The board's three bonds: two forward (quotes near 100 beside bookings
  # near 1), one of them with no asset class, and one reverse (quotes near 1
  # beside a booking near 100).
  defp two_scales_world do
    world = base_world()
    quoted_on = Clock.today()

    ostsee = bond!(%{name: "Ostsee Hafen 2029 3,00%", isin: "DE000000000O"})
    buy!(world, ostsee, quantity: "10000", price: "0.985", date: ~D[2026-03-12])
    put_quote!(ostsee, quoted_on, "97.25")

    {:ok, kestrel} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Kestrel Kommunal 2033 1,75%",
        currency_code: "EUR",
        maturity_date: ~D[2033-06-30]
      })

    buy!(world, kestrel, quantity: "10000", price: "1.014", date: ~D[2026-03-12])
    put_quote!(kestrel, quoted_on, "101.4")

    brackwater = bond!(%{name: "Brackwater Anleihe 2031 2,50%", isin: "DE000000000B"})
    buy!(world, brackwater, quantity: "100", price: "98.4", date: ~D[2026-03-12])
    put_quote!(brackwater, quoted_on, "0.981")

    %{ostsee: ostsee, kestrel: kestrel, brackwater: brackwater}
  end

  # User story (#1121's list half, Sprint 21 γ2; board 02, pick N3.2 A): As
  # the operator who followed the Overview's two-scales count to
  # `/securities?dq=two_scales`, I want a problem note per direction above
  # the list, each naming its bonds with both figures and linking to the tab
  # where the fix is made, so that the list says which way each bond is off
  # and what to check without a detour through Wealth.
  #
  # Acceptance criteria:
  # - One `role="status"` region (`data-role="securities-dq-notes"`) between
  #   the removable chips and the list, the forward note first, one problem
  #   note per direction present.
  # - The sentences are Wealth's with the list's scope clause, "wo immer sie
  #   bewertet wird/werden", in the singular and the plural.
  # - The entries are W2's: the name linking to Transaktionen (forward) or
  #   Kurse (reverse), the neutral "ohne Anlageklasse" badge where the bond
  #   shows none, and "(Kurs 97,25 · Preis je Stück 0,985)".
  # - A count of N opens a list of N: the notes name exactly the rows below,
  #   also when a search narrows them, and no note renders without the
  #   two-scales filter.
  test "the two-scales list opens on a note per direction naming exactly the rows below",
       %{conn: conn} do
    %{ostsee: ostsee, kestrel: kestrel, brackwater: brackwater} = two_scales_world()

    {:ok, view, _html} = live(german(conn), "/securities?dq=two_scales")

    assert has_element?(view, ~s([data-role="securities-dq-notes"][role="status"]))

    notes =
      view
      |> element(~s([data-role="securities-dq-notes"]))
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.attribute(".data-note--problem", "data-role")

    assert notes == ["securities-dq-two-scales", "securities-dq-two-scales-reverse"]

    forward = text(view, ~s([data-role="securities-dq-two-scales"]))

    assert forward =~
             "2 Anleihen sind auf zwei Skalen bepreist (Kurse um 100, gebuchter Preis je Stück um 1) " <>
               "und zählen hundertfach zu hoch, wo immer sie bewertet werden; die Rendite zeigt es nicht. " <>
               "Stückzahl ihrer Buchungen gegen das Nominal der Abrechnung prüfen:"

    assert forward =~
             "Kestrel Kommunal 2033 1,75% ohne Anlageklasse (Kurs 101,4 · Preis je Stück 1,014)"

    assert forward =~ "Ostsee Hafen 2029 3,00% (Kurs 97,25 · Preis je Stück 0,985)"
    refute forward =~ "Brackwater"

    reverse = text(view, ~s([data-role="securities-dq-two-scales-reverse"]))

    assert reverse =~
             "Eine Anleihe ist auf zwei Skalen bepreist (Kurse um 1, gebuchter Preis je Stück um 100) " <>
               "und zählt hundertfach zu niedrig, wo immer sie bewertet wird. Ihre gespeicherten Kurse " <>
               "prüfen — ein Kurs um 1 ist kein Prozent vom Nennwert:"

    assert reverse =~ "Brackwater Anleihe 2031 2,50% (Kurs 0,981 · Preis je Stück 98,4)"

    assert has_element?(
             view,
             ~s([data-role="securities-dq-two-scales"] a[href="/securities/#{ostsee.id}?tab=transactions"])
           )

    assert has_element?(
             view,
             ~s([data-role="securities-dq-two-scales"] a[href="/securities/#{kestrel.id}?tab=transactions"])
           )

    assert has_element?(
             view,
             ~s([data-role="securities-dq-two-scales-reverse"] a[href="/securities/#{brackwater.id}?tab=quotes"])
           )

    # A count of N opens a list of N: three rows, three entries.
    assert length(
             Floki.find(
               Floki.parse_document!(render(view)),
               "#securities-table tbody tr.security-row"
             )
           ) ==
             3

    # A search narrows the rows and the notes with them.
    {:ok, narrowed, _html} = live(german(conn), "/securities?dq=two_scales&q=Ostsee")

    assert has_element?(narrowed, ~s([data-role="securities-dq-two-scales"]))
    refute has_element?(narrowed, ~s([data-role="securities-dq-two-scales-reverse"]))

    assert text(narrowed, ~s([data-role="securities-dq-two-scales"])) =~
             "Eine Anleihe ist auf zwei Skalen bepreist (Kurse um 100, gebuchter Preis je Stück um 1) " <>
               "und zählt hundertfach zu hoch, wo immer sie bewertet wird; die Rendite zeigt es nicht. " <>
               "Stückzahl ihrer Buchungen gegen das Nominal der Abrechnung prüfen:"

    {:ok, unfiltered, _html} = live(german(conn), "/securities")
    refute has_element?(unfiltered, ~s([data-role="securities-dq-notes"]))
  end

  # User story (#1121's list half, Sprint 21 γ2; board 02, rule ② and found
  # while drawing 2): As the operator reading the list's notes, I want them
  # and the missing-logo bulk action inset by the gutter the panel's other
  # blocks keep, so that neither starts at the panel's edge.
  #
  # Acceptance criteria:
  # - `.workspace-panel > .securities-dq-notes` is a column with the
  #   `--space-2` gap and the `.alert-success` margin.
  # - `.workspace-panel > .dq-bulk-action` takes the same margin.
  test "the list's notes and the bulk action keep the panel's gutter" do
    notes = block(".workspace-panel > .securities-dq-notes")
    assert notes =~ ~r/display:\s*flex;/
    assert notes =~ ~r/flex-direction:\s*column;/
    assert notes =~ ~r/gap:\s*var\(--space-2\);/
    assert notes =~ ~r/margin:\s*12px clamp\(14px, 2\.2vw, 24px\) 0;/

    assert block(".workspace-panel > .dq-bulk-action") =~
             ~r/margin:\s*12px clamp\(14px, 2\.2vw, 24px\) 0;/
  end
end
