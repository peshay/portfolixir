defmodule PortfolixirWeb.AreaTabsDesignTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  # User story (#668, DESIGN.md → Components → Tabs / UX-DR16, UX-DR6):
  # As a local portfolio maintainer navigating the Wealth area on any device,
  # I want first-level tabs to carry an icon and a label, meet the coarse-
  # pointer touch-target floor, and expose their nesting level structurally,
  # so that the tab system matches the design language instead of rendering
  # plain text links.
  #
  # Acceptance criteria:
  # - First-level area tabs render an aria-hidden icon plus a real-text label.
  # - The icon vocabulary is shared with the navigation: the tab for the
  #   sidebar's own destination uses the sidebar's glyph.
  # - Both tab levels take the 44px touch-target floor under pointer: coarse;
  #   the first level carries a desktop min-height instead of being
  #   padding-derived.
  # - The nesting is carried structurally (data-tab-level), not only by the
  #   sighted-only "first level has icons" cue.
  # - The active-tab weight change is width-reserved (UX-DR18 technique:
  #   invisible bold shadow text), so the row does not shift.
  describe "first-level area tabs (#668)" do
    test "wealth tabs carry icon plus label", %{conn: conn} do
      alias Portfolixir.{Actor, Classifications, Portfolios}

      Classifications.ensure_builtins()

      {:ok, portfolio} =
        Portfolios.create_portfolio(Actor.owner_ui(), %{name: "Main", base_currency_code: "EUR"})

      {:ok, cash} =
        Portfolios.create_cash_account(Actor.owner_ui(), %{
          portfolio_id: portfolio.id,
          name: "Giro",
          currency_code: "EUR"
        })

      {:ok, _depot} =
        Portfolios.create_securities_account(Actor.owner_ui(), %{
          portfolio_id: portfolio.id,
          cash_account_id: cash.id,
          name: "Depot"
        })

      {:ok, view, _html} = live(conn, "/portfolio")

      tabs = view |> element(~s(nav[data-role="area-tabs"])) |> render()

      # Icon present and hidden from assistive tech; the label is real text.
      assert tabs =~ ~s(class="area-tab__icon")
      assert tabs =~ ~s(aria-hidden="true")
      assert tabs =~ "Holdings"
      assert tabs =~ "Snapshots"

      # The nav announces its level structurally.
      assert has_element?(view, ~s(nav[data-role="area-tabs"][data-tab-level="1"]))
    end

    test "transactions tabs carry icon plus label", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/transactions")

      tabs = view |> element(~s(nav[data-role="area-tabs"])) |> render()
      assert tabs =~ ~s(class="area-tab__icon")
      assert tabs =~ "History"
      assert tabs =~ "Import"
    end

    test "the securities detail tabs are marked second-level", %{conn: conn} do
      {:ok, security} =
        Portfolixir.Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
          name: "Tabbed Co.",
          ticker_symbol: "TAB",
          currency_code: "EUR",
          asset_class: "equity"
        })

      {:ok, view, _html} = live(conn, "/securities/#{security.id}")

      assert has_element?(view, ~s(#detail-pane-tabs[data-tab-level="2"]))
    end

    test "the stylesheet grants both tab levels the coarse-pointer floor" do
      app_css = File.read!("priv/static/app.css")

      # Desktop: the first level is no longer padding-derived.
      assert app_css =~ ~r/\.area-tab \{[^}]*min-height: 34px/s

      # Coarse pointer: both levels take the 44px floor (UX-DR6).
      assert app_css =~
               ~r/@media \(pointer: coarse\) \{\s*\.area-tab,\s*\.detail-pane-tab \{\s*min-height: 44px/s

      # Width reserve (UX-DR18): invisible bold shadow text on the label.
      assert app_css =~ ~r/\.area-tab__label::after \{[^}]*content: attr\(data-label\)/s
      assert app_css =~ ~r/\.area-tab__label::after \{[^}]*font-weight: 600/s
    end
  end

  # User story (#702, regression from #668; feedback triage 2026-08-15 F3):
  # As a local portfolio maintainer checking my wealth on a phone,
  # I want the Wealth tab row to scroll horizontally when its tabs do not fit,
  # so that the fifth tab is reachable at 390 px instead of being clipped off
  # the edge of the screen with no way to get to it.
  #
  # Acceptance criteria:
  # - `.area-tabs` scrolls horizontally instead of clipping (`overflow-x: auto`).
  # - Tabs do not compress to fit: each keeps its intrinsic width (`flex: none`),
  #   otherwise "it fits" is achieved by squashing the labels rather than by
  #   scrolling, which is the same defect wearing a different shape.
  # - The scroller carries a scroll-snap affordance so a tab does not come to
  #   rest half-cut -- being half-cut is what made the fourth tab read as the
  #   last one.
  # - An edge fade marks the row as continuing past the viewport, so the
  #   scrollability is discoverable without horizontal scrollbars (which phones
  #   do not render).
  # - The row does not become a second vertical stack: no `flex-wrap: wrap`.
  describe "the area tab row survives a 390px viewport (#702)" do
    test "the stylesheet makes the tab row scroll instead of clipping" do
      app_css = File.read!("priv/static/app.css")

      [area_tabs_rule] = Regex.run(~r/\.area-tabs \{[^}]*\}/s, app_css)

      # Scrolls rather than clips.
      assert area_tabs_rule =~ "overflow-x: auto"

      # ...and is not "fixed" by wrapping into a second row, which changes the
      # navigation model rather than the overflow behaviour. That question
      # belongs to the design engagement (#707), not to this defect fix.
      refute area_tabs_rule =~ "flex-wrap: wrap"

      # Tabs keep their intrinsic width, so overflow is real overflow.
      assert app_css =~ ~r/\.area-tab \{[^}]*flex: none/s

      # Comes to rest on a tab boundary rather than mid-label.
      assert area_tabs_rule =~ "scroll-snap-type"
      assert app_css =~ ~r/\.area-tab \{[^}]*scroll-snap-align/s

      # The edge fade: the affordance that the row continues.
      assert area_tabs_rule =~ "mask-image"
    end

    test "every wealth tab is present and reachable in the markup", %{conn: conn} do
      alias Portfolixir.{Actor, Classifications, Portfolios}

      Classifications.ensure_builtins()

      {:ok, portfolio} =
        Portfolios.create_portfolio(Actor.owner_ui(), %{name: "Main", base_currency_code: "EUR"})

      {:ok, cash} =
        Portfolios.create_cash_account(Actor.owner_ui(), %{
          portfolio_id: portfolio.id,
          name: "Giro",
          currency_code: "EUR"
        })

      {:ok, _depot} =
        Portfolios.create_securities_account(Actor.owner_ui(), %{
          portfolio_id: portfolio.id,
          cash_account_id: cash.id,
          name: "Depot"
        })

      {:ok, view, _html} = live(conn, "/portfolio")

      # The fifth tab -- the one that was unreachable at 390 px -- is a real
      # link, not merely rendered text.
      assert has_element?(view, ~s([data-role="area-tabs"] a[href="/tax"]))
      assert has_element?(view, ~s([data-role="area-tabs"] a[href="/snapshots"]))
    end
  end
end
