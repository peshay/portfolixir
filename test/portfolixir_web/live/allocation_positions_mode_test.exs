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
    {:ok, view, _html} = live(conn, "/portfolio?tab=allocation&classification=#{w.tree.id}")
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
  # - A hint whose quantity rounds to 0.00 is not shown; the row's drift stays
  #   and its Drift cell carries no hint (since #911 the hint sits in the
  #   Drift cell, under the figure). The tree shows no hint for it either.
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

    [_name, category, _value, _weight, drift] = cells(position_row(view, "Corvid"))
    assert category =~ "Commodities"
    assert drift =~ "EUR"
    refute drift =~ "≈"

    refute view |> element(~s([data-role="flat-positions"])) |> render() =~
             ~s(class="rebalance-qty">0.00<)

    [_name, _category, _value, _weight, kestrel_drift] = cells(position_row(view, "Kestrel"))

    assert kestrel_drift =~ "Buy"

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

  # User story (#911; Sprint 18 pick H4, board
  # ux-design-2026-10-02/04-tables-conformance ④, variant A for (a) and the
  # "after" of (c); DESIGN.md → Amendment 2026-08-22, the subject column, and
  # ADR-0040 §2):
  # As the operator working the Positions list on a phone,
  # I want a position's drift and its rebalancing hint to stay on screen
  # together, pinned at the scroller's edge, and the tree's drift ⓘ to say
  # that a plan allocating less than 100 % is measured against its
  # allocated portion,
  # so that I can act on the list without scrolling sideways and reconcile
  # the target, the actual weight and the drift.
  #
  # Acceptance criteria:
  # - (a, variant A) The worklist's Drift head carries `col-subject` and the
  #   Hint column is gone: the hint sits in the Drift cell beneath the
  #   figure, as in the tree's position rows. A row without a hint shows its
  #   drift alone, with no dash for the missing hint.
  # - (c) While `drift_basis` is `allocated_portion`, the tree's drift ⓘ adds
  #   the allocated sum and the first steered category's target as scaled
  #   for the comparison (40 % of an 80 % plan counts as 50 %); a plan over
  #   100 % measures against the full plan and the sentence is absent.
  test "the worklist pins drift and hint together, and the ⓘ names the portion",
       %{conn: conn} do
    w = world()
    view = open(conn, w)
    view |> element(~s([data-role="allocation-mode-flat"])) |> render_click()

    assert has_element?(
             view,
             ~s([data-role="flat-positions"] thead th.num.col-subject [data-role="flat-sort-drift"])
           )

    refute view |> element(~s([data-role="flat-positions"] thead)) |> render() =~ "Hint"

    kestrel = position_row(view, "Kestrel")
    assert length(cells(kestrel)) == 5
    [drift] = Floki.find(kestrel, "td.col-subject")
    assert Floki.text(drift) =~ "EUR"
    assert [_hint] = Floki.find(drift, ~s([data-role="rebalance-hint"]))

    [gold_drift] = Floki.find(position_row(view, "Corvid"), "td.col-subject")
    assert Floki.find(gold_drift, ~s([data-role="rebalance-hint"])) == []
    refute Floki.text(gold_drift) =~ "—"

    # The ⓘ sits on the tree's Drift head.
    view = open(conn, w)

    assert has_element?(
             view,
             ~s(#tip-soll-ist [data-role="drift-basis-tip"]),
             "The plan allocates 80.0%: each target is scaled up to that portion before the comparison, so 40.0% counts as 50.0%. The unallocated rest does not show as drift."
           )

    plan!(w, w.tree, w.commodities, w.growth, "0.6")
    view = open(conn, w)
    assert has_element?(view, "#tip-soll-ist")
    refute has_element?(view, ~s([data-role="drift-basis-tip"]))
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

    # #911 (c): the ⓘ's sentence, in the board's German.
    assert has_element?(
             view,
             ~s([data-role="drift-basis-tip"]),
             "Der Plan verteilt 80,0%: Jedes Soll wird vor dem Vergleich auf diesen Anteil hochgerechnet, 40,0% zählen als 50,0%. Der unverteilte Rest erscheint nicht als Abweichung."
           )
  end

  # User story (#911 (c), ADR-0040 §2):
  # As the operator whose plan for a tree steers only the cash share,
  # I want the drift ⓘ to name the allocated portion without a worked
  # figure,
  # so that it never scales a category target the plan does not have.
  #
  # Acceptance criteria:
  # - A tree without category targets under a 10 % cash target measures
  #   against the allocated portion, and the ⓘ says "The plan allocates
  #   10.0%: each target is scaled up to that portion before the
  #   comparison. The unallocated rest does not show as drift." — no
  #   "counts as".
  test "a plan steering only cash names its portion without a worked figure",
       %{conn: conn} do
    w = world()
    owner = Actor.owner_ui()
    {:ok, region} = Classifications.create_classification(owner, %{name: "Region"})

    {:ok, europe} =
      Classifications.create_category(owner, %{classification_id: region.id, name: "Europe"})

    {:ok, _} = Classifications.assign_security(owner, w.gold.id, region.id, europe.id)
    :ok = Targets.set_cash_target(owner, w.portfolio.id, "0.1")

    {:ok, view, _html} = live(conn, "/portfolio?tab=allocation&classification=#{region.id}")
    render_async(view)

    assert has_element?(
             view,
             ~s(#tip-soll-ist [data-role="drift-basis-tip"]),
             "The plan allocates 10.0%: each target is scaled up to that portion before the comparison. The unallocated rest does not show as drift."
           )

    refute view |> element(~s([data-role="drift-basis-tip"])) |> render() =~ "counts as"
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

  # User story (the Sprint 16 closing act, UAT-10; DESIGN.md: a name wraps):
  # As the operator reading the rebalancing worklist on a phone,
  # I want a long security name to wrap inside its column,
  # so that the category and the figures are not all pushed off-screen by
  # one catalogue name on a single line.
  #
  # Acceptance criteria:
  # - Under 560 px, where every table keeps its cells on one line, the
  #   worklist's name column has a fixed share and wraps inside it.
  #   (Measured on the review seed at 390 px: the name column 377 → 144 px,
  #   the category head from 394 px, off-screen, to 161 px.)
  test "the worklist's security names wrap under 560 px" do
    app_css = File.read!("priv/static/app.css")

    assert app_css =~
             ~r/@media \(max-width: 560px\) \{\s*\.drift-table\[data-role="flat-positions"\] td:first-child \{[^}]*width: 9rem;[^}]*white-space: normal;/s
  end
end
