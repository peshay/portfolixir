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
end
