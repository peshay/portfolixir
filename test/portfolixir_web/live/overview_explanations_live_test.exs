defmodule PortfolixirWeb.OverviewExplanationsLiveTest do
  # Board `ux-design-2026-11-01-sprint22/01-i1` on the Overview (I1, #1351,
  # variant R; pick Q1): a basis line's method clause moves into the ⓘ
  # beside its card's heading, the basis clauses stay, and every note
  # clamps, its count and its link in view. Every name is synthetic.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Knowledge.Events
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.WorldFixtures

  defp seed! do
    world = WorldFixtures.base_world(name: "Card", cash_name: "Giro", depot_name: "Depot")
    WorldFixtures.deposit!(world, "100000", ~D[2023-01-02])

    for {name, buy_date, sell_date} <- [
          {"Longhold Industries", ~D[2024-01-02], ~D[2026-01-01]},
          {"Quickturn Retail", ~D[2026-02-01], ~D[2026-03-03]}
        ] do
      security = WorldFixtures.create_security!(name: name, ticker: nil)
      WorldFixtures.buy!(world, security, quantity: "10", price: "100", date: buy_date)
      WorldFixtures.sell!(world, security, quantity: "10", price: "110", date: sell_date)
    end

    # A dated fact inside the horizon, for "Due".
    candidate = WorldFixtures.create_security!(name: "Candidate Co", ticker: "CND")

    {:ok, _} =
      Events.create_event(Actor.owner_ui(), %{
        security_id: candidate.id,
        kind: "earnings",
        timing: "exact",
        source_quality: "primary",
        date: Date.add(Portfolixir.Clock.today(), 5)
      })

    # Money the value card's total leaves out: a USD account with no rate.
    {:ok, usd} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        name: "USD Settlement",
        currency_code: "USD"
      })

    {:ok, _} =
      Ledger.set_cash_balance(Actor.owner_ui(), usd, %{
        date: Date.add(Date.utc_today(), -2),
        amount: "1850"
      })

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
    |> String.split(~r/<br\s*\/?>/)
    |> Enum.map(&(&1 |> LazyHTML.from_fragment() |> LazyHTML.text() |> squish()))
  end

  # User story (#1351, board 01 ① ② ③ on the Overview):
  # As the operator landing on the Overview,
  # I want each card to say what it shows and leave how it is computed
  # behind the ⓘ at its heading, and each note cut to two lines with its
  # count and its link in view,
  # so that the page reads at a glance and nothing it leaves out is hidden.
  #
  # Acceptance criteria:
  # - "Closed trades": the heading and the section's ⓘ sit in
  #   `.section-title` inside the card's head; the ⓘ holds "p. a. only from
  #   365 days of holding and only where a rate solves the flows"; the basis
  #   line keeps "The 2 most recently closed · result in EUR · FIFO across
  #   every depot, whatever the view" ("Die 2 zuletzt abgeschlossenen ·
  #   Ergebnis in EUR · FIFO über alle Depots, unabhängig von der Ansicht").
  # - "Due": the ⓘ holds "A date given as a range or a month counts as due
  #   when any day it could fall on is inside the horizon."; the basis line
  #   keeps "Dated facts about any security in the catalog — held or not —
  #   falling in the next 30 days."
  # - The value card's note names the money the total leaves out: it clamps
  #   and never folds, the count first ("Not in the total: …"), "Details in
  #   Wealth →" in its actions, visible under the clamp.
  # - The data-quality line clamps (it stays visible, at its severity).
  test "the Overview's method clauses sit behind the cards' ⓘ and its notes clamp",
       %{conn: conn} do
    seed!()

    {:ok, view, _html} = live(conn, "/")
    render_async(view)

    assert text(view, "#dashboard-trades .section-head .section-title > h2") == "Closed trades"

    assert tip_lines(view, "#dashboard-trades") == [
             "p. a. only from 365 days of holding and only where a rate solves the flows"
           ]

    assert text(view, "#dashboard-trades [data-role='trades-card-basis']") ==
             "The 2 most recently closed · result in EUR · FIFO across every depot, whatever the view"

    assert text(view, "#dashboard-upcoming .section-title > h2") == "Due"

    assert tip_lines(view, "#dashboard-upcoming") == [
             "A date given as a range or a month counts as due when any day it could fall on is inside the horizon."
           ]

    assert text(view, "#dashboard-upcoming [data-role='upcoming-basis']") ==
             "Dated facts about any security in the catalog — held or not — falling in the next 30 days."

    note = "#dashboard-wealth .data-note--clamped[data-role='wealth-card-excluded'][id]"
    assert text(view, note <> " .data-note__text") =~ ~r/^Not in the total: /

    assert has_element?(
             view,
             note <> " .data-note__actions a[data-role='wealth-card-excluded-link']",
             "Details in Wealth →"
           )

    assert has_element?(view, "#dashboard-data-quality #dashboard-dq-line.data-note--clamped")

    # Pick Q1, correction 2 (closing act): each finding's link, the line's
    # remedy, sits in the note's actions, never under the clamp.
    assert has_element?(view, "#dashboard-dq-line .data-note__actions a[data-role]")
    refute has_element?(view, "#dashboard-dq-line .data-note__text a")

    {:ok, de_view, _html} = live(conn, "/?locale=de")
    render_async(de_view)

    assert text(de_view, "#dashboard-trades [data-role='trades-card-basis']") ==
             "Die 2 zuletzt abgeschlossenen · Ergebnis in EUR · FIFO über alle Depots, unabhängig von der Ansicht"

    assert tip_lines(de_view, "#dashboard-upcoming") == [
             "Ein als Zeitraum oder Monat angegebener Termin gilt als fällig, sobald irgendein Tag, auf den er fallen kann, im Horizont liegt."
           ]
  end
end
