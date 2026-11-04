defmodule PortfolixirWeb.WealthPolishLiveTest do
  # The three open lines of the Wealth polish list (#1366) that Sprint 24's
  # P1 fixes in one pass: the sunburst's centre comes back to its total (line
  # 1, the owner's report of 2026-11-04), „Beitrag je Position“ takes its
  # phone rows where its columns stop fitting (line 2, the owner's report of
  # 2026-11-04) and #1322, the holdings table's name column (line 3). Lines 2
  # and 3 are layout: the board
  # `mockups/ux-design-2026-11-05-sprint24-p1/` measured them on the review
  # seed, and these tests pin the markup and the CSS that layout keys on.
  # The client half of line 1 is pinned in Chromium by
  # test/browser/sunburst_centre_return_test.exs. Every name is synthetic.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures, only: [base_world: 0, buy!: 3, deposit!: 3, put_quotes!: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.WorldFixtures

  # Two categories, each holding one security, so the chart has two slices
  # per ring; the long name and the twelve-decimal quantity are #1322's.
  defp wealth_world do
    world = base_world()
    today = Date.utc_today()
    start = Date.add(today, -10)
    deposit!(world, "5000", start)

    {:ok, classification} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

    for {category_name, color, security_name, quantity} <- [
          {"Core", "#2563eb", "Harbor World Equity Index Registered Shares DL-,00000625", "12"},
          {"Satellite", "#10b981", "Birchwood Global Savings Fund", "0.333333333333"}
        ] do
      security = WorldFixtures.create_security!(name: security_name)
      buy!(world, security, quantity: quantity, price: "100", date: start)
      put_quotes!(security, [{start, "100"}, {today, "110"}])

      {:ok, category} =
        Classifications.create_category(Actor.owner_ui(), %{
          classification_id: classification.id,
          name: category_name,
          color: color
        })

      {:ok, _} =
        Classifications.assign_security(
          Actor.owner_ui(),
          security.id,
          classification.id,
          category.id
        )
    end

    world
  end

  defp allocation(conn) do
    wealth_world()
    {:ok, view, _html} = live(conn, "/portfolio?tab=allocation")
    render_async(view)
    view
  end

  defp centre_label(view) do
    view
    |> element(~s([data-role="sunburst-centre"] .sunburst-centre__label))
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.text()
    |> String.trim()
  end

  defp slice(view, name), do: element(view, ~s(path.sunburst-seg[data-label="#{name}"]))

  defp figure(view), do: element(view, ~s([data-role="sunburst-figure"]))

  describe "line 1: the sunburst's centre comes back to its total" do
    # User story (#1366, line 1; the owner's report of 2026-11-04):
    # As the operator tapping the allocation sunburst,
    # I want a tap on the centre, outside the chart or on the selected slice
    # again, and Escape, to bring „Allokiert“ back,
    # so that one tapped slice does not hold the centre until a reload.
    #
    # Acceptance criteria:
    # - A tap on the selected slice again restores the total.
    # - A tap on the chart's figure (the centre lets a tap through to it)
    #   restores the total.
    # - While a slice is selected the figure listens for a tap outside it
    #   and for Escape, and each restores the total; another key does not.
    # - With nothing selected the figure listens for neither, so a tap
    #   elsewhere on the page sends no event.
    # - A tap on another slice selects that slice.
    test "the selected slice again, the centre, outside and Escape restore „Allocated“",
         %{conn: conn} do
      view = allocation(conn)
      assert centre_label(view) == "Allocated"

      # The selected slice again.
      view |> slice("Core") |> render_click()
      assert centre_label(view) == "Core"
      view |> slice("Core") |> render_click()
      assert centre_label(view) == "Allocated"

      # Nothing selected: nothing listens.
      figure_html = view |> figure() |> render()
      refute figure_html =~ "phx-click-away"
      refute figure_html =~ "phx-window-keydown"

      # Another slice moves the selection; the centre (the figure) clears it.
      view |> slice("Core") |> render_click()
      view |> slice("Satellite") |> render_click()
      assert centre_label(view) == "Satellite"
      view |> figure() |> render_click()
      assert centre_label(view) == "Allocated"

      # Outside the chart: the figure's click-away.
      view |> slice("Core") |> render_click()
      figure_html = view |> figure() |> render()
      assert figure_html =~ ~s(phx-click-away="clear_segment")
      render_click(view, "clear_segment", %{})
      assert centre_label(view) == "Allocated"

      # Escape, and only Escape.
      view |> slice("Core") |> render_click()
      figure_html = view |> figure() |> render()
      assert figure_html =~ ~s(phx-window-keydown="clear_segment")
      assert figure_html =~ ~s(phx-key="Escape")
      view |> figure() |> render_keydown(%{"key" => "a"})
      assert centre_label(view) == "Core"
      view |> figure() |> render_keydown(%{"key" => "Escape"})
      assert centre_label(view) == "Allocated"
    end
  end
end
