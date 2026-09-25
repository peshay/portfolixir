defmodule PortfolixirWeb.AllocationPositionsModeTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.Portfolios.Allocation
  alias Portfolixir.Portfolios.Targets

  # Board ux-design-2026-09-24/09-allocation-positions (#875), synthetic
  # figures only. 10 000 deposited; 5 units of a gold ETC at 1 000 (quoted
  # 1 000.10) and 40 of an equity at 100; 1 000 stays in cash; one more
  # security is held but filed nowhere. The plan puts 40 % on each category:
  # it allocates 80 %, so drift measures against the allocated portion
  # (ADR-0040 §2) and the gold position sits a few cents off its target.
  defp world do
    world = base_world(name: "Positionen")
    deposit!(world, "10000", ~D[2026-01-01])

    gold = create_security!(name: "Corvid Physical Test ETC", ticker: "CPT")
    kestrel = create_security!(name: "Kestrel Industrial Test NV", ticker: "KIT")
    loose = create_security!(name: "Loose Test Fund", ticker: "LTF")

    buy!(world, gold, quantity: "5", price: "1000", date: ~D[2026-01-02])
    buy!(world, kestrel, quantity: "40", price: "100", date: ~D[2026-01-02])
    buy!(world, loose, quantity: "1", price: "0.01", date: ~D[2026-01-02])
    put_quote!(gold, Date.utc_today(), "1000.1")
    put_quote!(kestrel, Date.utc_today(), "100")
    put_quote!(loose, Date.utc_today(), "0.01")

    owner = Actor.owner_ui()
    {:ok, tree} = Classifications.create_classification(owner, %{name: "Strategy"})

    {:ok, commodities} =
      Classifications.create_category(owner, %{classification_id: tree.id, name: "Commodities"})

    {:ok, growth} =
      Classifications.create_category(owner, %{classification_id: tree.id, name: "Growth"})

    {:ok, _} = Classifications.assign_security(owner, gold.id, tree.id, commodities.id)
    {:ok, _} = Classifications.assign_security(owner, kestrel.id, tree.id, growth.id)

    plan!(world, tree, commodities, growth, "0.4")

    Map.merge(world, %{
      tree: tree,
      commodities: commodities,
      growth: growth,
      gold: gold,
      kestrel: kestrel
    })
  end

  defp plan!(world, tree, commodities, growth, weight) do
    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), world.portfolio.id, tree.id, [
        %{category_id: commodities.id, target_weight: weight},
        %{category_id: growth.id, target_weight: weight}
      ])
  end

  defp open(conn, w) do
    {:ok, view, _html} = live(conn, "/portfolio?tab=allocation&classification_id=#{w.tree.id}")
    render_async(view)
    view
  end

  defp flat_row(view, selector) do
    view
    |> element(~s([data-role="flat-positions"]))
    |> render()
    |> Floki.parse_document!()
    |> Floki.find(selector)
  end

  defp position_row(view, name) do
    view
    |> flat_row(~s(tr[data-role="flat-position"]))
    |> Enum.find(&(Floki.text(&1) =~ name))
  end

  defp cells(row), do: row |> Floki.find("td") |> Enum.map(&(Floki.text(&1) |> String.trim()))

  # User story (#875; board 09, before/after; ADR-0023 hints, ADR-0040 §2/§3,
  # DESIGN.md D3 and Selected state):
  # As the operator working the Positions list on a phone,
  # I want every row to say only what is true — no "Sell ≈ 0.00 units", cash
  # never "Unassigned", a toggle that shows which mode is on — and the drift to
  # say what it measures against,
  # so that the worklist can be acted on without a second guess.
  #
  # Acceptance criteria:
  # - A hint whose quantity rounds to 0.00 is not shown; the row's hint cell
  #   reads "—" and its drift stays. The tree shows no hint for it either.
  # - The cash row's category reads "—"; a held security filed nowhere keeps
  #   "Unassigned".
  # - The Tree/Positions toggle is the segmented control: the active option is
  #   filled (`is-active`) and pressed, the other not.
  # - With a plan allocating 80 %, the basis line's Σ carries no warning colour
  #   and adds "— drift against the allocated portion"; above 100 % the warning
  #   stays and the clause does not appear.
  test "the Positions list says only what is true", %{conn: conn} do
    w = world()

    # The fixture's premise, from the engine: the gold hint rounds to nothing.
    {:ok, allocation} = Allocation.for_portfolio(w.portfolio.id, w.tree.id, view: nil)
    [commodities] = Enum.filter(allocation.categories, &(&1.category_id == w.commodities.id))
    [gold] = commodities.positions
    assert Decimal.eq?(Decimal.round(Decimal.abs(gold.rebalance_quantity), 2), 0)
    refute Decimal.eq?(gold.rebalance_quantity, 0)
    assert allocation.drift_basis == "allocated_portion"

    view = open(conn, w)
    view |> element(~s([data-role="toggle-all-categories"])) |> render_click()

    tree_row =
      view
      |> element("#portfolio-allocation")
      |> render()
      |> Floki.parse_document!()
      |> Floki.find(~s([data-role="allocation-position"]))
      |> Enum.find(&(Floki.text(&1) =~ "Corvid"))

    assert tree_row, "the gold position is listed in the expanded tree"
    assert Floki.find(tree_row, ~s([data-role="rebalance-hint"])) == []

    view |> element(~s([data-role="allocation-mode-flat"])) |> render_click()

    [_name, category, _value, _weight, drift, hint] = cells(position_row(view, "Corvid"))
    assert category =~ "Commodities"
    assert drift =~ "EUR"
    assert hint == "—"

    refute view |> element(~s([data-role="flat-positions"])) |> render() =~
             ~s(class="rebalance-qty">0.00<)

    [_name, _category, _value, _weight, _drift, kestrel_hint] =
      cells(position_row(view, "Kestrel"))

    assert kestrel_hint =~ "Buy"

    [cash] = flat_row(view, ~s(tr[data-role="flat-cash"]))
    assert Enum.at(cells(cash), 1) == "—"
    assert Enum.at(cells(position_row(view, "Loose")), 1) =~ "Unassigned"

    assert has_element?(
             view,
             ~s(.segmented-control[role="group"] .segmented-control__option.is-active[data-role="allocation-mode-flat"][aria-pressed="true"])
           )

    assert has_element?(
             view,
             ~s(.segmented-control .segmented-control__option[data-role="allocation-mode-tree"][aria-pressed="false"])
           )

    refute has_element?(
             view,
             ~s(.segmented-control__option.is-active[data-role="allocation-mode-tree"])
           )

    sum = view |> element(~s([data-role="target-sum-top-level"])) |> render()
    assert sum =~ "80.0"
    refute sum =~ "is-target-mismatch"

    assert has_element?(
             view,
             ~s([data-role="target-sum-top-level"] [data-role="drift-basis"]),
             "drift against the allocated portion"
           )

    plan!(w, w.tree, w.commodities, w.growth, "0.6")
    view = open(conn, w)
    sum = view |> element(~s([data-role="target-sum-top-level"])) |> render()
    assert sum =~ "120.0"
    assert sum =~ "is-target-mismatch"
    refute has_element?(view, ~s([data-role="drift-basis"]))
  end

  # The basis clause in the page's language.
  test "the drift's basis clause is German on a German page", %{conn: conn} do
    w = world()
    conn = Plug.Test.put_req_cookie(conn, "portfolixir_locale", "de")
    view = open(conn, w)

    assert has_element?(
             view,
             ~s([data-role="drift-basis"]),
             "Abweichung gegen den verteilten Anteil"
           )
  end

  # User story (#875, Lane C review round DC-C2; board 09 ④, DESIGN.md →
  # {components.selected-segment}):
  # As the operator moving through Allocation with the keyboard,
  # I want the Tree / Positions toggle to show which option has the focus,
  # so that tabbing to "Positions" is not a step into nothing.
  #
  # Acceptance criteria:
  # - The group does not clip its options: no `overflow: hidden`, which cut
  #   the outset ring off at the track's edge (Positions, next to the filled
  #   Tree, showed no focus at all).
  # - The outer options round their own outer corners, so the active fill
  #   still follows the track's radius without the clip.
  # - Focus stays the 2 px accent outline at a 2 px offset (board 09 ④,
  #   DESIGN.md: at least 2 px wherever the option's own fill is the accent),
  #   and the focused option paints above its neighbours.
  test "the segmented toggle's focus ring is not clipped by its track" do
    app_css = File.read!("priv/static/app.css")

    [group] = Regex.run(~r/\n\.segmented-control \{[^}]*\}/s, app_css)
    refute group =~ "overflow: hidden"
    assert group =~ "border-radius: var(--radius-md)"

    assert app_css =~
             ~r/\.segmented-control__option:first-child \{[^}]*border-start-start-radius: calc\(var\(--radius-md\) - 1px\);[^}]*border-end-start-radius: calc\(var\(--radius-md\) - 1px\);/s

    assert app_css =~
             ~r/\.segmented-control__option:last-child \{[^}]*border-start-end-radius: calc\(var\(--radius-md\) - 1px\);[^}]*border-end-end-radius: calc\(var\(--radius-md\) - 1px\);/s

    [focus] = Regex.run(~r/\.segmented-control__option:focus-visible \{[^}]*\}/s, app_css)
    assert focus =~ "outline: 2px solid var(--color-accent)"
    assert focus =~ "outline-offset: 2px"
    assert focus =~ "position: relative"
    assert focus =~ "z-index: 1"
  end
end
