defmodule PortfolixirWeb.LayoutSweepLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Classifications
  alias Portfolixir.WorldFixtures

  defp seeded_world do
    Classifications.ensure_builtins()
    world = WorldFixtures.base_world()
    share = WorldFixtures.create_security!(name: "Share Co", ticker: "SHR")
    today = Date.utc_today()
    WorldFixtures.deposit!(world, "1000", Date.add(today, -10))
    WorldFixtures.buy!(world, share, quantity: "2", price: "100", date: Date.add(today, -9))
    WorldFixtures.put_quote!(share, today, "110")
    Map.put(world, :share, share)
  end

  # User story (#790, the review's D8 and Part 4 rule 10 — every control row
  # sits inside the content grid):
  # As a local portfolio maintainer,
  # I want the view switcher and the cash-flow facet control to line up
  # with the content beside them, with a gutter on the phone,
  # so that nothing sits flush with the sidebar or the screen edge.
  #
  # Acceptance criteria:
  # - Both control rows render inside a `.workspace-section` that carries
  #   the section's horizontal padding.
  test "the view switcher and the facet control sit inside a padded section", %{conn: conn} do
    seeded_world()

    {:ok, wealth, _html} = live(conn, "/portfolio")
    render_async(wealth)
    assert has_element?(wealth, ".workspace-section--controls > .view-switcher")

    {:ok, cashflow, _html} = live(conn, "/cashflow?tab=realized")
    assert has_element?(cashflow, ".workspace-section--controls > [data-role='cashflow-facets']")
  end

  # User story (#790, the family labels): the "Changed since" family sits in
  # the same chip row as the other families, with the same label treatment.
  test "the changed-since family is part of the chip row on both lists", %{conn: conn} do
    seeded_world()

    {:ok, securities, _html} = live(conn, "/securities")

    assert has_element?(
             securities,
             "#securities-filter-chips .filter-chips__family",
             "Changed since"
           )

    {:ok, transactions, _html} = live(conn, "/transactions")
    assert has_element?(transactions, "#transaction-chips .filter-chips__family", "Changed since")
  end

  # User story (#790, the review's D10): the Trades tab's ⓘ carries a label,
  # so it is the inline, labelled tooltip, never the 20 px corner circle
  # that clipped "Kurs- & Währungsb…".
  test "the trades tab's basis affordance is the labelled inline tooltip", %{conn: conn} do
    world = seeded_world()

    {:ok, view, _html} = live(conn, "/securities/#{world.share.id}?tab=trades")

    assert has_element?(
             view,
             "[data-role='lot-decomposition-info'].metric-tooltip--inline.metric-tooltip--labelled"
           )
  end
end
