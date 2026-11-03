defmodule PortfolixirWeb.RiskExplanationsLiveTest do
  # Board `ux-design-2026-11-03-sprint23-i1` on Risk (Sprint 23, Lane I; I1's
  # anatomy, variant R with its Q1 corrections): three basis lines split by
  # sentence. Each keeps its basis clauses on the page; its method sentences
  # move into a new section ⓘ beside the heading. Every name is synthetic.
  use PortfolixirWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 0, buy!: 3, create_security!: 1, deposit!: 3, put_quotes!: 2]

  defp day(offset), do: Date.add(Date.utc_today(), offset)

  # Three names with a year of daily closes, so the correlations run over
  # the three largest positions.
  defp risk_world! do
    world = base_world()
    deposit!(world, "10000", day(-400))

    for {name, ticker, quantity, step} <- [
          {"Nordic Timber Holdings AB", "NTH", "20", 7},
          {"Helios Solar Systems SE", "HSS", "5", 5},
          {"Meridian Global Equity ETF", "MGE", "70", 3}
        ] do
      security = create_security!(name: name, ticker: ticker, asset_class: "equity")
      buy!(world, security, quantity: quantity, price: "100", date: day(-400))
      put_quotes!(security, for(o <- -400..0, do: {day(o), "#{100 + rem(o, step)}"}))
    end

    world
  end

  defp squish(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()

  defp text(view, selector) do
    view
    |> element(selector)
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.text()
    |> squish()
  end

  # The section ⓘ's lines, split at its <br>.
  defp tip_lines(view, section) do
    view
    |> element(section <> " .section-title details.metric-tooltip--section p[role='tooltip']")
    |> render()
    |> String.replace(~r/^<p[^>]*>|<\/p>$/, "")
    |> String.split(~r/<br\s*\/?>/)
    |> Enum.map(&(&1 |> LazyHTML.from_fragment() |> LazyHTML.text() |> squish()))
  end

  # User story (Sprint 23, Lane I, Risk; board ux-design-2026-11-03-sprint23-i1):
  # As the operator reading Wealth → Risk,
  # I want each section to say what it reads from on the page and leave how
  # it is read behind the ⓘ at its heading,
  # so that the page reads at a glance and the method is one click away.
  #
  # Acceptance criteria:
  # - "Own rules": the heading and a section ⓘ sit in `.section-title`; the
  #   ⓘ holds "Each rule names the figure it reads; a figure that cannot be
  #   read is undetermined, never met." and "A finding does not say what to
  #   do."; the basis line keeps "Evaluated on read, as of …, on the
  #   steerable basis of the view “Everything”."
  # - "Portfolio metrics": the ⓘ holds "A day without a return base yields
  #   no observation, never a zero." and "Correlations convert to EUR first
  #   and run over the 3 largest positions."; the basis line keeps "Basis:
  #   … in EUR, annualized by √365 — a deposit is not a return." whole.
  # - "Asset-class caps": the ⓘ holds "Caps are set per request over the
  #   API."; the empty state keeps "No cap configured — there is nothing to
  #   exceed."
  # - The German reads the same sentences, their wording unchanged.
  test "Risk's method sentences sit behind three section ⓘs", %{conn: conn} do
    risk_world!()

    {:ok, view, _html} = live(conn, "/risk")

    assert text(view, "#policy-rules .section-head .section-title > h2") =~ ~r/^Own rules/

    assert tip_lines(view, "#policy-rules") == [
             "Each rule names the figure it reads; a figure that cannot be read is undetermined, never met.",
             "A finding does not say what to do."
           ]

    assert text(view, "[data-role='policy-rules-basis']") =~
             ~r/^Evaluated on read, as of \S+, on the steerable basis of the view “Everything”\.$/

    assert text(view, "#risk-metrics .section-head .section-title > h2") == "Portfolio metrics"

    assert tip_lines(view, "#risk-metrics") == [
             "A day without a return base yields no observation, never a zero.",
             "Correlations convert to EUR first and run over the 3 largest positions."
           ]

    assert text(view, "[data-role='risk-basis']") ==
             "Basis: the flow-adjusted daily return factors of the TTWROR chain, in EUR, " <>
               "annualized by √365 — a deposit is not a return."

    caps = "section[data-role='risk-caps']"
    assert text(view, caps <> " .section-head .section-title > h2") == "Asset-class caps"
    assert tip_lines(view, caps) == ["Caps are set per request over the API."]

    assert text(view, caps <> " > p.empty-state") ==
             "No cap configured — there is nothing to exceed."

    {:ok, de, _html} = live(conn, "/risk?locale=de")

    assert tip_lines(de, "#policy-rules") == [
             "Jede Regel nennt die Kennzahl, aus der sie liest; eine Zahl, die sich nicht lesen lässt, ist nicht bestimmbar, nie eingehalten.",
             "Ein Befund sagt nicht, was zu tun ist."
           ]

    assert text(de, "[data-role='policy-rules-basis']") =~
             ~r/^Ausgewertet beim Lesen, Stand \S+, auf der steuerbaren Basis der Ansicht „Alles“\.$/

    assert tip_lines(de, "#risk-metrics") == [
             "Ein Tag ohne Renditebasis liefert keine Beobachtung, nie eine Null.",
             "Korrelationen rechnen zuerst in EUR um und laufen über die 3 größten Einzelpositionen."
           ]

    assert text(de, "[data-role='risk-basis']") ==
             "Grundlage: die um Zahlungen bereinigten täglichen Renditefaktoren der TTWROR-Kette, " <>
               "in EUR, annualisiert mit √365 — eine Einzahlung ist keine Rendite."

    assert tip_lines(de, caps) == ["Obergrenzen werden pro Abfrage über die API gesetzt."]

    assert text(de, caps <> " > p.empty-state") ==
             "Keine Obergrenze konfiguriert — es gibt nichts zu überschreiten."
  end
end
