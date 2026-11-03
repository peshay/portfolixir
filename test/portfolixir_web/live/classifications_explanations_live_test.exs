defmodule PortfolixirWeb.ClassificationsExplanationsLiveTest do
  # Board `ux-design-2026-11-03-sprint23-i1` on Klassifizierungen (Sprint 23,
  # Lane I; I1's anatomy, variant R with its Q1 corrections). Every name is
  # synthetic.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures

  alias Portfolixir.Actor
  alias Portfolixir.Classifications

  # A tree with one priced member, two members no rule can value (delivered
  # in, never traded or quoted) and one held security filed nowhere.
  defp tree! do
    world = base_world()
    deposit!(world, "10000", ~D[2026-01-01])

    {:ok, classification} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

    {:ok, core} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Core"
      })

    alpha = create_security!(name: "Alpha Freight AG", ticker: "AFR")
    buy!(world, alpha, quantity: "10", price: "100", date: ~D[2026-01-02])
    put_quote!(alpha, Date.utc_today(), "150")

    dark = create_security!(name: "Dunmore Holdings AG", ticker: "DNM")
    dim = create_security!(name: "Dimwater Estates AG", ticker: "DMW")
    deliver_untraded!(world, dark, "10")
    deliver_untraded!(world, dim, "4")

    for security <- [alpha, dark, dim] do
      {:ok, _} =
        Classifications.assign_security(Actor.owner_ui(), security.id, classification.id, core.id)
    end

    loose = create_security!(name: "Loose Ends plc", ticker: "LSE")
    buy!(world, loose, quantity: "1", price: "50", date: ~D[2026-01-02])

    %{classification: classification}
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

  # User story (Sprint 23, Lane I, Klassifizierungen; board
  # ux-design-2026-11-03-sprint23-i1 ③):
  # As the operator reading a classification tree,
  # I want each note that names rows left out cut to two lines with its
  # count first and its remedy in view,
  # so that the tree stays near the top and nothing it leaves out is hidden.
  #
  # Acceptance criteria:
  # - The assignment nudge clamps (`data-note--clamped`, an id) and never
  #   folds; its sentence is the clamped text and „Nicht zugeordnet“
  #   ("Unsorted") sits in its actions, not in the text.
  # - The category result's exclusion note clamps the same way, the count
  #   first; the disclosure „Die 2 Positionen“ ("The 2 positions") sits in
  #   its actions, not in the text.
  # - The basis line stays whole and ends in its own ⓘ.
  test "the tree's two notes clamp with their remedy in view", %{conn: conn} do
    %{classification: classification} = tree!()

    {:ok, view, _html} = live(conn, "/classifications/#{classification.id}?locale=de")
    render_async(view)

    nudge = "#assignment-nudge.data-note--clamped[data-role='assignment-nudge']"

    assert text(view, nudge <> " .data-note__text") ==
             "1 Wertpapier ist noch keiner Kategorie zugeordnet und fließt nicht in die SOLL-IST-Allokation ein."

    assert text(view, nudge <> " .data-note__actions a[href='#unsorted']") == "Nicht zugeordnet"
    refute has_element?(view, nudge <> " .data-note__text a")

    excluded = "[data-role='category-result-excluded'].data-note--clamped[id]"

    assert text(view, excluded <> " .data-note__text") =~
             ~r/^2 Positionen sind in „Einstand“ und „Ergebnis“ nicht enthalten\./

    assert text(
             view,
             excluded <>
               " .data-note__actions details[data-role='category-result-excluded-list'] > summary"
           ) == "Die 2 Positionen"

    refute has_element?(view, excluded <> " .data-note__text details")

    assert has_element?(
             view,
             "[data-role='category-result-basis'] details.metric-tooltip[data-role='category-result-info']"
           )
  end
end
