defmodule PortfolixirWeb.SecuritiesClassificationColumnsTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Classifications

  defp security!(name, attrs) do
    {:ok, sec} =
      Catalog.create_security(
        Actor.owner_ui(),
        Map.merge(
          %{name: name, currency_code: "EUR", asset_class: "equity", provider: "manual"},
          attrs
        )
      )

    sec
  end

  defp strategy_tree! do
    {:ok, tree} = Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

    {:ok, growth} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: tree.id,
        name: "Growth"
      })

    {:ok, tech} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: tree.id,
        name: "Tech",
        parent_id: growth.id
      })

    {:ok, stability} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: tree.id,
        name: "Stability"
      })

    %{tree: tree, growth: growth, tech: tech, stability: stability}
  end

  defp world! do
    Classifications.ensure_builtins()
    %{tree: tree, tech: tech, stability: stability} = strategy_tree!()

    alpha = security!("Alpha Corp", %{isin: "US0000000011"})
    beta = security!("Beta Corp", %{isin: "US0000000012"})
    gamma = security!("Gamma Corp", %{isin: "US0000000013"})

    {:ok, _} = Classifications.assign_security(Actor.owner_ui(), alpha.id, tree.id, tech.id)

    {:ok, _} =
      Classifications.assign_security(Actor.owner_ui(), beta.id, tree.id, stability.id)

    %{tree: tree, alpha: alpha, beta: beta, gamma: gamma}
  end

  defp row_index(html, security) do
    case :binary.match(html, "security-row-#{security.id}") do
      {index, _} -> index
      :nomatch -> flunk("row for #{security.name} not rendered")
    end
  end

  # User story (#565):
  # As a local portfolio maintainer,
  # I want to add a classification tree and level as a securities-table column,
  # so that each security's assigned category on that level is visible in the
  # list, like Portfolio Performance's classification columns.
  #
  # Acceptance criteria:
  # - The column picker offers every classification tree per level, custom and
  #   built-in alike.
  # - An enabled classification column shows each security's category on that
  #   level (the ancestor for deeper assignments, blank when unassigned or
  #   assigned above the level).
  describe "classification columns (#565)" do
    test "column picker offers classification trees per level", %{conn: conn} do
      %{tree: tree} = world!()
      asset_tree = Classifications.get_classification_by_key("asset_class")
      currency_tree = Classifications.get_classification_by_key("currency")

      {:ok, view, _html} = live(conn, "/securities")
      view |> element("#toggle-column-popover") |> render_click()

      assert has_element?(view, "#column-picker fieldset legend", "Classifications")
      assert has_element?(view, "#column-picker input[value='classification:#{tree.id}:1']")
      assert has_element?(view, "#column-picker input[value='classification:#{tree.id}:2']")
      assert has_element?(view, "#column-picker label", "Strategy (level 1)")
      assert has_element?(view, "#column-picker label", "Strategy (level 2)")

      # Built-in trees are offered too; a one-level tree needs no level suffix.
      assert has_element?(
               view,
               "#column-picker input[value='classification:#{asset_tree.id}:1']"
             )

      assert has_element?(
               view,
               "#column-picker input[value='classification:#{currency_tree.id}:1']"
             )

      refute has_element?(
               view,
               "#column-picker input[value='classification:#{currency_tree.id}:2']"
             )
    end

    test "an enabled classification column shows the category on that level", %{conn: conn} do
      %{tree: tree, alpha: alpha, beta: beta, gamma: gamma} = world!()

      {:ok, view, _html} = live(conn, "/securities")
      view |> element("#toggle-column-popover") |> render_click()

      view
      |> element("#column-picker form")
      |> render_change(%{"columns" => ["name", "classification:#{tree.id}:1"]})

      assert has_element?(view, "#securities-table thead", "Strategy (level 1)")
      assert has_element?(view, "#security-row-#{alpha.id} td", "Growth")
      assert has_element?(view, "#security-row-#{beta.id} td", "Stability")
      refute has_element?(view, "#security-row-#{gamma.id} td", "Growth")

      # Level 2: only assignments that reach that depth show a value.
      view
      |> element("#column-picker form")
      |> render_change(%{"columns" => ["name", "classification:#{tree.id}:2"]})

      assert has_element?(view, "#securities-table thead", "Strategy (level 2)")
      assert has_element?(view, "#security-row-#{alpha.id} td", "Tech")
      refute has_element?(view, "#security-row-#{beta.id} td", "Stability")
    end

    test "built-in tree columns derive their values from security data", %{conn: conn} do
      world!()
      warrantco = security!("Warrant Co", %{isin: "US0000000014", asset_class: "warrant"})
      asset_tree = Classifications.get_classification_by_key("asset_class")

      {:ok, view, _html} = live(conn, "/securities")
      view |> element("#toggle-column-popover") |> render_click()

      view
      |> element("#column-picker form")
      |> render_change(%{"columns" => ["name", "classification:#{asset_tree.id}:1"]})

      assert has_element?(view, "#security-row-#{warrantco.id} td", "Leverage products")

      view
      |> element("#column-picker form")
      |> render_change(%{"columns" => ["name", "classification:#{asset_tree.id}:2"]})

      assert has_element?(view, "#security-row-#{warrantco.id} td", "Warrant")
    end

    # User story (#565, sorting):
    # As a local portfolio maintainer,
    # I want to sort the securities list by a classification column,
    # so that securities in the same category group together.
    #
    # Acceptance criteria:
    # - The classification column header is a sort toggle like other columns.
    # - Ascending and descending sort order rows by category name; securities
    #   without a value on that level always sort last.
    test "classification columns are sortable with unassigned rows last", %{conn: conn} do
      %{tree: tree, alpha: alpha, beta: beta, gamma: gamma} = world!()

      {:ok, view, _html} = live(conn, "/securities")
      view |> element("#toggle-column-popover") |> render_click()

      view
      |> element("#column-picker form")
      |> render_change(%{"columns" => ["name", "classification:#{tree.id}:1"]})

      view
      |> element(
        "#securities-table thead button.sort-toggle[phx-value-key='classification:#{tree.id}:1']"
      )
      |> render_click()

      html = render(view)
      assert row_index(html, alpha) < row_index(html, beta)
      assert row_index(html, beta) < row_index(html, gamma)

      view
      |> element(
        "#securities-table thead button.sort-toggle[phx-value-key='classification:#{tree.id}:1']"
      )
      |> render_click()

      html = render(view)
      assert row_index(html, beta) < row_index(html, alpha)
      assert row_index(html, alpha) < row_index(html, gamma)
    end

    # User story (#565, persistence):
    # As a local portfolio maintainer,
    # I want my classification column choice to persist like the other columns,
    # so that the list looks the same on my next visit.
    #
    # Acceptance criteria:
    # - Classification columns round-trip through the existing
    #   `securities.columns` browser storage (serialized keys in the hook
    #   payload, restored via the same `set_columns` event).
    # - A stored key for a since-deleted classification is dropped silently.
    test "classification columns persist through the column-prefs hook", %{conn: conn} do
      %{tree: tree} = world!()

      {:ok, view, _html} = live(conn, "/securities")
      view |> element("#toggle-column-popover") |> render_click()

      view
      |> element("#column-picker form")
      |> render_change(%{"columns" => ["name", "classification:#{tree.id}:1"]})

      # The hook payload carries the serialized key for localStorage.
      assert view
             |> element("#securities-table")
             |> render() =~ "classification:#{tree.id}:1"

      # A fresh mount restores the column from the stored strings.
      {:ok, restored, _html} = live(conn, "/securities")

      restored
      |> element("#securities-table")
      |> render_hook("set_columns", %{"columns" => ["name", "classification:#{tree.id}:1"]})

      assert has_element?(restored, "#securities-table thead", "Strategy (level 1)")

      # Stale or unknown keys never crash and never render a column.
      {:ok, stale, _html} = live(conn, "/securities")

      stale
      |> element("#securities-table")
      |> render_hook("set_columns", %{
        "columns" => ["name", "classification:999999:1", "classification:#{tree.id}:9"]
      })

      refute has_element?(stale, "#securities-table thead", "Strategy")
      assert has_element?(stale, "#securities-table thead", "Name")
    end
  end
end
