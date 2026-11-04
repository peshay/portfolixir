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

  @css File.read!("priv/static/app.css")

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

  # One CSS rule's body, found by its exact selector line.
  defp rule(selector) do
    case Regex.run(~r/(?:^|\n)#{Regex.escape(selector)} \{([^}]*)\}/, @css) do
      [_, body] -> body
      nil -> flunk("app.css has no rule `#{selector} {`")
    end
  end

  # The body of an at-rule block whose head is given exactly, up to the
  # first line that closes it at the left margin.
  defp at_block(head) do
    case Regex.run(~r/\n#{Regex.escape(head)} \{\n(.*?)\n\}/s, @css) do
      [_, body] -> body
      nil -> flunk("app.css has no block `#{head} {`")
    end
  end

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

  describe "line 2: „Beitrag je Position“ takes its rows where its columns stop fitting" do
    # User story (#1366, line 2; the owner's report of 2026-11-04):
    # As the operator reading the contribution table on a phone held
    # upright or a narrow window,
    # I want the two-line rows wherever the table's columns do not fit,
    # so that „Beitrag“ is never scrolled out of view with no cue.
    #
    # Acceptance criteria:
    # - The contribution block is a size container named `contribution`.
    # - Below 820 px of block (the seed's German table needs 814 px of
    #   columns and the wrapper's 2 px border; board
    #   ux-design-2026-11-05-sprint24-p1) the table's wrapper is hidden and
    #   the rows show, whatever the viewport and the sidebar.
    # - The phone lists' 560 px block no longer decides it.
    test "the block is a container, and under 820 px of it the rows replace the table",
         %{conn: conn} do
      wealth_world()
      {:ok, view, _html} = live(conn, "/portfolio")
      Enum.each(1..4, fn _round -> render_async(view) end)

      block = view |> element("#performance-contribution") |> render()
      assert block =~ ~s(id="contribution-table-wrap")
      assert block =~ ~s(id="contribution-phone-rows")

      assert rule("#performance-contribution") =~ "container: contribution / inline-size;"

      rows = at_block("@container contribution (width < 820px)")
      assert rows =~ ~r/#contribution-table-wrap \{\s*display: none;\s*\}/
      assert rows =~ ~r/#contribution-phone-rows \{\s*display: block;\s*\}/

      [_, phone_lists] =
        Regex.run(~r/phone lists \(issue 799, issue 800\)(.*?)\.filter-sheet-toggle/s, @css)

      refute phone_lists =~ "#contribution-table-wrap"
    end
  end

  describe "line 3: #1322, the holdings table's name column" do
    # User story (#1366, line 3; #1322):
    # As the operator reading Wealth's positions with the valuation columns
    # picked,
    # I want long names to wrap above a floor instead of widening the table,
    # so that G&V stays in view at 1200 px while the quantity keeps every
    # digit it has.
    #
    # Acceptance criteria:
    # - The Security column's head and cells carry `cell-name`, wherever the
    #   picker puts the column.
    # - The table fits its wrapper; the name column keeps a 12 rem floor and
    #   breaks inside its cell (#1145's anatomy); figures never wrap; a
    #   cell's note wraps between words.
    # - The quantity prints every stored digit ("0.333333333333").
    test "the name column carries the floor-and-wrap anatomy, the quantity every digit",
         %{conn: conn} do
      wealth_world()
      {:ok, view, _html} = live(conn, "/portfolio")
      render_async(view)

      render_change(view, "set_holdings_columns", %{
        "columns" =>
          ~w(depot security quantity avg_cost latest_price market_value unrealized_pnl_abs unrealized_pnl_pct)
      })

      html = view |> element("#holdings-positions-table") |> render() |> Floki.parse_fragment!()
      heads = Floki.find(html, "thead th")
      [name_head] = Enum.filter(heads, &(Floki.text(&1) =~ "Security"))

      assert "cell-name" in (name_head
                             |> Floki.attribute("class")
                             |> Enum.flat_map(&String.split/1))

      assert Enum.count(heads, &("cell-name" in class_list(&1))) == 1

      cells = Floki.find(html, ~s(td[data-column="security"]))
      assert length(cells) == 2
      assert Enum.all?(cells, &("cell-name" in class_list(&1)))

      quantities = html |> Floki.find(~s(td[data-column="quantity"])) |> Enum.map(&Floki.text/1)
      assert Enum.any?(quantities, &(String.trim(&1) == "0.333333333333"))

      # The name column moves with the picker.
      render_change(view, "set_holdings_columns", %{"columns" => ~w(security quantity)})
      html = view |> element("#holdings-positions-table") |> render() |> Floki.parse_fragment!()
      [first_head | _] = Floki.find(html, "thead th")
      assert "cell-name" in class_list(first_head)

      fits = rule(".data-table-wrapper > #holdings-positions-table")
      assert fits =~ "min-width: 0;"
      assert fits =~ "width: 100%;"
      assert rule("#holdings-positions-table th.cell-name") =~ "min-width: 12rem;"
      assert rule("#holdings-positions-table td.cell-name") =~ "overflow-wrap: anywhere;"

      assert rule("#holdings-positions-table th.num,\n#holdings-positions-table td.num") =~
               "white-space: nowrap;"

      assert rule("#holdings-positions-table td .cell-note") =~ "white-space: normal;"
    end
  end

  defp class_list(node), do: node |> Floki.attribute("class") |> Enum.flat_map(&String.split/1)
end
