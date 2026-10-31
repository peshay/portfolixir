defmodule PortfolixirWeb.ClassificationCostTooltipTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures

  alias Portfolixir.Actor
  alias Portfolixir.Classifications

  # Synthetic figures only: Wrenfield Gardens AG (EUR), bought 10 at 100,00
  # with fees 2,00 and taxes 0,50 (cash 1.002,50), closing at 110,00.
  defp tree do
    world = base_world(name: "Cost Tooltip", cash_name: "Test-Cash", depot_name: "Depot Muster")
    wrenfield = create_security!(name: "Wrenfield Gardens AG", ticker: "WGA", currency: "EUR")

    deposit!(world, "5000", ~D[2026-01-01])

    buy!(world, wrenfield,
      quantity: "10",
      price: "100",
      fees: "2.00",
      taxes: "0.50",
      date: ~D[2026-01-02]
    )

    put_quote!(wrenfield, ~D[2026-01-05], "110")

    {:ok, classification} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

    {:ok, core} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Core"
      })

    {:ok, _} =
      Classifications.assign_security(Actor.owner_ui(), wrenfield.id, classification.id, core.id)

    classification
  end

  defp text(nodes),
    do: nodes |> Floki.text(sep: " ") |> String.replace(~r/\s+/, " ") |> String.trim()

  # User story (#1212, Sprint 21 α11): As the operator reading a category's
  # Einstand, I want its ⓘ to say that the figure leaves out the buys' fees
  # and taxes while a closed trade's Einstand counts them, so that I do not
  # read the 1.000,00 of an open position against a sold one's basis as the
  # same kind of figure.
  #
  # Acceptance criteria:
  # - The category's Einstand reads 1.000,00 (10 × 100,00; the 2,50 of costs
  #   are not in it), its result +100,00: the figures do not change.
  # - The ⓘ's German text says „Der Einstand ist, was die Anteile ohne
  #   Gebühren und Steuern der Käufe gekostet haben, das Ergebnis also vor
  #   ihnen; der Einstand eines abgeschlossenen Trades enthält sie.“; the
  #   English says the same.
  test "the category result's ⓘ says the cost leaves out the buys' fees and taxes",
       %{conn: conn} do
    classification = tree()

    {:ok, view, _html} = live(conn, "/classifications/#{classification.id}?locale=de")
    render_async(view)
    doc = view |> render() |> Floki.parse_document!()

    assert text(Floki.find(doc, ~s([data-role="category-invested"]))) == "1.000,00"
    assert text(Floki.find(doc, ~s([data-role="category-result"]))) =~ "+100,00"

    assert text(Floki.find(doc, ~s([data-role="category-result-info"] p))) =~
             "Der Einstand ist, was die Anteile ohne Gebühren und Steuern der Käufe " <>
               "gekostet haben, das Ergebnis also vor ihnen; der Einstand eines " <>
               "abgeschlossenen Trades enthält sie."

    {:ok, view, _html} = live(conn, "/classifications/#{classification.id}")
    render_async(view)
    doc = view |> render() |> Floki.parse_document!()

    assert text(Floki.find(doc, ~s([data-role="category-result-info"] p))) =~
             "Cost is what the shares cost without the buys' fees and taxes, so the " <>
               "result is before them; a closed trade's cost includes them."
  end
end
