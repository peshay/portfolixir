defmodule PortfolixirWeb.InfoTipsTest do
  # The ⓘ definition affordance (UX-DR11, `details.metric-tooltip`) as one
  # component family, board `ux-design-2026-11-01-sprint22/01-i1` (I1,
  # #1351): the view switcher's ⓘ floats like every other (#1350, ⑥), a
  # panel stays inside the viewport (#1336, ⑦), and Escape closes it
  # (#1342, ⑧). LiveViewTest renders the server's markup and runs no
  # client script, so the behaviour the client owns is pinned on the
  # script's source and the stylesheet. Synthetic data only.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.WorldFixtures

  @css File.read!("priv/static/app.css")

  # The body of the first rule whose selector list is exactly `selector`.
  defp rule(selector) do
    pattern = ~r/(?:^|\n)#{Regex.escape(selector)} \{([^}]*)\}/

    case Regex.run(pattern, @css) do
      [_, body] -> body
      nil -> flunk("no rule for #{selector}")
    end
  end

  defp seed_world do
    world = WorldFixtures.base_world(name: "Demo Portfolio")
    {:ok, _} = Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})
    world
  end

  # User story (#1350):
  # As the operator reading Wealth,
  # I want the ⓘ beside "Views" to open as a floating panel,
  # so that its explanation does not drop onto a line of its own and push
  # the KPI cards down.
  #
  # Acceptance criteria:
  # - `details.view-switcher__help` is also `metric-tooltip
  #   metric-tooltip--inline`, so it takes the elevated, absolutely
  #   positioned panel every other ⓘ has; its summary keeps its accessible
  #   name "About views" and its body stays `p[role="tooltip"]`.
  # - The switcher's own rule keeps the ⓘ beside its neighbour: no inline
  #   margin of its own (`margin-left: 0`).
  test "the view switcher's ⓘ is a metric tooltip", %{conn: conn} do
    seed_world()
    {:ok, view, _html} = live(conn, "/portfolio")

    help = "details.view-switcher__help.metric-tooltip.metric-tooltip--inline"
    assert has_element?(view, help <> " > summary[aria-label='About views']", "ⓘ")
    assert has_element?(view, help <> " > p[role='tooltip']", "A view narrows every figure")

    assert rule(".view-switcher__help.metric-tooltip") =~ ~r/margin-left:\s*0;/
  end

  # The client script's block that serves every ⓘ, from its marker comment
  # to the next hook.
  defp info_tip_source do
    "lib/portfolixir_web/layout_view.ex"
    |> File.read!()
    |> String.split("// ⓘ panels (issue 1336")
    |> Enum.at(1, "")
    |> String.split("Hooks.")
    |> hd()
  end

  # User story (#1336):
  # As the operator reading Cash flow on a phone,
  # I want a facet's ⓘ panel to open where I can read it,
  # so that its first lines do not start above the top of the screen or run
  # past its right edge.
  #
  # Acceptance criteria:
  # - Every ⓘ on Cash flow is a `details.metric-tooltip`, the element the
  #   client places; the server renders no placement of its own.
  # - On toggle (one capture listener for every ⓘ, opened by pointer or
  #   keyboard) the client measures the open panel: it opens upward unless
  #   its top would be above the viewport, then below
  #   (`data-place="below"`); it is shifted (`--tip-shift`) so that both
  #   edges stay 1 rem (16 px) inside the viewport's width. Closing clears
  #   both. A LiveView patch strips attributes the server did not render, so
  #   an observer puts the measured placement back while the panel is open.
  # - The stylesheet reads both: `[data-place="below"]` puts the panel
  #   under its ⓘ, and every panel is translated by `--tip-shift`.
  test "an ⓘ panel stays inside the viewport", %{conn: conn} do
    seed_world()

    for tab <- ["income", "realized", "flows", "costs"] do
      {:ok, view, _html} = live(conn, "/cashflow?tab=#{tab}")

      assert has_element?(
               view,
               "details.metric-tooltip[data-role='facet-info'] > p[role='tooltip']"
             )

      refute has_element?(view, "details.metric-tooltip[data-place]")
    end

    js = info_tip_source()
    assert js =~ ~r/document\.addEventListener\("toggle", function \(event\) \{.*?\}, true\);/s
    assert js =~ ~s|matches("details.metric-tooltip")|
    assert js =~ ~r/rect\.top < 0/
    assert js =~ ~s|setAttribute("data-place", "below")|
    assert js =~ ~r/var edge = 16;/
    assert js =~ ~s|style.setProperty("--tip-shift"|
    assert js =~ ~s|removeAttribute("data-place")|
    assert js =~ ~s|style.removeProperty("--tip-shift")|
    assert js =~ ~r/new MutationObserver\(.*attributeFilter: \["data-place", "style"\]/s

    assert rule(~s(.metric-tooltip[data-place="below"] p)) =~
             ~r/top:\s*calc\(100% \+ 0\.4rem\);\s*bottom:\s*auto;/

    assert rule(".metric-tooltip") =~ ~r/--tip-shift:\s*0px;/
    assert rule(".metric-tooltip p") =~ ~r/translate:\s*var\(--tip-shift\) 0;/
  end

  # User story (#1342, the ⓘ half):
  # As the keyboard user who opened an ⓘ,
  # I want Escape to close it and give the focus back to its ⓘ,
  # so that I need not Tab back to the summary and press it again.
  #
  # Acceptance criteria:
  # - One capture listener on the document answers Escape whose target is
  #   inside an open `details.metric-tooltip` (its summary, or a link in
  #   its panel): it closes that ⓘ and focuses its summary.
  # - It consumes the key (`preventDefault`, `stopPropagation`), so an ⓘ
  #   inside a drawer or a dialog closes alone and the dialog stays open.
  # - Every ⓘ on the page is such an element: Wealth's KPI ⓘ, the view
  #   switcher's and the Cash flow facets' alike.
  test "Escape closes an open ⓘ and returns the focus to its summary", %{conn: conn} do
    seed_world()
    {:ok, view, _html} = live(conn, "/portfolio")
    assert has_element?(view, "#portfolio-kpis details.metric-tooltip > summary")
    assert has_element?(view, "details.view-switcher__help.metric-tooltip > summary")

    js = info_tip_source()

    [_, listener] =
      Regex.run(
        ~r/document\.addEventListener\("keydown", function \(event\) \{(.*?)\}, true\);/s,
        js
      ) ||
        flunk("no capture keydown listener for the ⓘ")

    assert listener =~ ~s|event.key !== "Escape"|
    assert listener =~ ~s|closest("details.metric-tooltip[open]")|
    assert listener =~ "event.preventDefault();"
    assert listener =~ "event.stopPropagation();"
    assert listener =~ ~s|tip.removeAttribute("open");|
    assert listener =~ ~r/summary\.focus\(\)/
  end
end
