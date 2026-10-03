defmodule PortfolixirWeb.SecuritiesDetailTabsArrivalTest do
  # Sprint 18 plan U5, H7.2 (board ux-design-2026-10-02/07-phone-390, rule ②;
  # DESIGN.md → Tab row overflow, D6): the detail pane's tab row gains the
  # mount half of the area tab row's hook, so the selected tab is in view on
  # arrival. The scrolling itself runs in the browser; what a LiveView test
  # can hold is the server's markup and the hook's source.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures, only: [create_security!: 1]

  # The DetailTabs hook's object literal in layout_view.ex: up to its own
  # closing brace, so the next hook's comment is not read as this hook.
  defp detail_tabs_hook do
    "lib/portfolixir_web/layout_view.ex"
    |> File.read!()
    |> String.split("Hooks.DetailTabs = {")
    |> Enum.at(1)
    |> String.split("\n            };\n")
    |> hd()
  end

  # User story (#1033; board 07, H7.2):
  # As the operator arriving on a security's tab from a link, a reload, back
  # or forward, or a shared URL on a 390 px phone,
  # I want the selected tab to be in view in the tab row,
  # so that "Kurse" is not half under the right fade, and "Termine" — where
  # the Overview's "Fällig" rows link — is not wholly outside the row.
  #
  # Acceptance criteria:
  # - The row keeps its DetailTabs hook and the server renders it resting at
  #   its start (`data-scroll-start`), so the first paint, before the hook
  #   runs, carries only the right fade (D6: without script the row keeps
  #   the one-sided fade).
  # - On mount the hook scrolls the selected tab into the row's view — the
  #   row, never the page (`scrollTo`, no `scrollIntoView`) — without
  #   animation under prefers-reduced-motion, to the last tab start at or
  #   before its centring target at which the tab is whole (#876's
  #   arithmetic).
  # - It gives the row a trailing inset (`--detail-tabs-tail`) so the row's
  #   end is a tab boundary, marks the edges it rests on
  #   (`data-scroll-start`, `data-scroll-end`), and restores both after a
  #   patch and on resize.
  # - A selection the server changes is revealed after the patch; a tab
  #   already in view is not scrolled.
  # - The keyboard half stays (Arrow keys, Home, End).
  test "the detail tab row arrives at its start and its hook reveals the selected tab",
       %{conn: conn} do
    security = create_security!(name: "Nordwind Industrie AG", ticker: "NWI")

    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=events")

    assert has_element?(
             view,
             ~s(nav#detail-pane-tabs[phx-hook="DetailTabs"][data-scroll-start])
           )

    refute has_element?(view, "nav#detail-pane-tabs[data-scroll-end]")
    assert has_element?(view, ~s(#detail-tab-events[aria-selected="true"]))

    hook = detail_tabs_hook()

    assert hook =~ ~s([aria-selected="true"])
    assert hook =~ "prefers-reduced-motion"
    assert hook =~ ~s(toggleAttribute("data-scroll-start")
    assert hook =~ ~s(toggleAttribute("data-scroll-end")
    assert hook =~ ~s(setProperty("--detail-tabs-tail")
    refute hook =~ "scrollIntoView"

    assert hook =~
             ~r/mounted: function \(\) \{.*this\.fitTail\(\);.*this\.reveal\(\);.*this\.markEdges\(\);/s

    assert hook =~
             ~r/updated: function \(\) \{.*this\.fitTail\(\);.*this\.selectedWhole\(\).*this\.markEdges\(\);/s

    assert hook =~ ~r/addEventListener\("resize", this\.onResize\)/
    assert hook =~ ~r/removeEventListener\("resize", this\.onResize\)/
    assert hook =~ ~r/left: this\.restingLeft\(/
    assert hook =~ ~r/querySelectorAll\("\.detail-pane-tab"\)/

    for key <- ~w(ArrowRight ArrowLeft Home End) do
      assert hook =~ ~s("#{key}")
    end
  end
end
