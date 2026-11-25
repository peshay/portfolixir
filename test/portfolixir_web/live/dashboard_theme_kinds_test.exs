defmodule PortfolixirWeb.DashboardThemeKindsTest do
  # Sprint 32 S5 (I61; boards ux-design-2026-11-25-sprint32/03, 11): the
  # themes' new kinds on the page itself, stored on a dashboard and drawn
  # by its background reads — each kind's frame, its period (a pin is the
  # zoom) and its quiet line with no crash benchmark chosen. Their figures
  # against the routes: dashboard_crash_chart_widget_test.exs and
  # dashboard_distance_widget_test.exs (this module stores a dashboard and
  # so cannot choose the crash benchmark, whose group is another).
  #
  # group: :dashboards -- a create takes the count lock (LockTable row 30).
  use PortfolixirWeb.ConnCase, async: true, group: :dashboards

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures, only: [base_world: 0, deposit!: 3]
  import PortfolixirWeb.PreferenceCookieHelpers

  alias Portfolixir.Actor
  alias Portfolixir.Dashboards

  defp item(kind, size, col, row, settings \\ %{}),
    do: %{"kind" => kind, "size" => size, "col" => col, "row" => row, "settings" => settings}

  # User story (board 11 ①, ②):
  # As the operator who placed the crash chart twice, once pinned to 1M,
  # I want each drawn in its frame with its period said, and told why it is
  # empty while no crash benchmark is chosen,
  # so that the pinned copy reads as the zoom and nothing reads as a fall
  # that is not there.
  #
  # Acceptance criteria:
  # - Two „Crash-Chart“ widgets: the XL one „folgt · 1J“, the L one „📌
  #   eigener: 1M“; with no crash benchmark both say „Kein
  #   Crash-Benchmark gewählt“ and draw no chart.
  test "„Crash-Chart“ follows the period or its pin, and says when no benchmark is chosen",
       %{conn: conn} do
    deposit!(base_world(), "100", Portfolixir.Clock.today())

    {:ok, board} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{
        "name" => "Rücksetzer",
        "layout" => [
          item("crash_chart", "XL", 1, 1),
          item("crash_chart", "L", 1, 5, %{"period" => "1m"})
        ]
      })

    conn = put_preference_cookie(conn, "portfolixir_locale", "de")
    {:ok, view, _html} = live(conn, "/dashboards/#{board.id}")
    render_async(view)

    assert has_element?(view, "#dashboard-crash-chart h2", "Crash-Chart")
    assert has_element?(view, "#dashboard-crash-chart [data-role='widget-period']", "folgt · 1J")

    assert has_element?(
             view,
             "#dashboard-crash-chart-2 [data-role='widget-period']",
             "eigener: 1M"
           )

    for id <- ~w(dashboard-crash-chart dashboard-crash-chart-2) do
      assert has_element?(
               view,
               "##{id} [data-role='crash-chart-empty']",
               "Kein Crash-Benchmark gewählt"
             )

      refute has_element?(view, "##{id} [data-role='crash-chart']")
    end
  end
end
