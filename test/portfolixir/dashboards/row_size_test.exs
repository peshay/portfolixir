defmodule Portfolixir.Dashboards.RowSizeTest do
  # Sprint 32 S2 (ADR-0062's amendment of 2026-11-25, point 3; I57; board
  # ux-design-2026-11-25-sprint32/02 ①, ③): the size „Zeile“ (`row`), the
  # full width and as tall as its content. In the stored grid it is 12
  # columns by 1 row, so validation, the arrangement and the API treat it
  # as any item; the page draws it at its content's height.
  #
  # Until Lane W's section widgets exist, one existing kind takes it:
  # „Verkaufsrückblick“ (`sale_review`), the Overview's card „Closed
  # trades“ in a frame (ADR-0062 §12), a section of today's screens whose
  # list of five reads as one band across the page.
  use ExUnit.Case, async: true

  alias Portfolixir.Dashboards.Arrange
  alias Portfolixir.Dashboards.Grid
  alias Portfolixir.Dashboards.Layout
  alias Portfolixir.Dashboards.Widgets
  alias PortfolixirWeb.Api.V1.DashboardJSON

  defp item(kind, size, col, row),
    do: %{"kind" => kind, "size" => size, "col" => col, "row" => row, "settings" => %{}}

  # User story:
  # As the operator, or the agent I run, placing a section of a screen on a
  # dashboard,
  # I want a size that spans the whole width and grows with the section,
  # checked and arranged as any other,
  # so that a section reads as it does on its screen.
  #
  # Acceptance criteria:
  # - `row` is a size with the dimensions 12 × 1, no Apple family, drawn at
  #   its content's height (`Widgets.height/1` "content", every family
  #   "fixed").
  # - `sale_review` takes L and row, as the section widgets of Sprint 32
  #   W1 take row; a kind that does not take row is
  #   refused with `unsupported_size`, a row item not at column 1 with
  #   `off_grid`, a row item over another with `overlap`.
  # - The arrangement moves what a row item covers below it and closes the
  #   gaps, as for any item; a resize to row moves the item to column 1.
  # - The catalogue names row with its columns, its rows and its height.
  # - A layout of an earlier grid keeps a row item as it is.
  test "the size „Zeile“ is 12 × 1 in validation, the arrangement and the catalogue" do
    assert Widgets.dimensions("row") == {:ok, {12, 1}}
    assert "row" in Widgets.sizes()
    assert Widgets.family("row") == nil
    assert Widgets.height("row") == "content"
    assert Enum.all?(~w(S M L XL), &(Widgets.height(&1) == "fixed"))

    {:ok, sale_review} = Widgets.fetch("sale_review")
    assert sale_review.sizes == ~w(L row)

    # Sprint 32 W2 to W4 add the sections of „Allokation & Ziele“,
    # „Snapshots“ and „Risiko“, W1 those of „Bestände“.
    taking = for kind <- Widgets.kinds(), "row" in kind.sizes, do: kind.key

    assert taking ==
             ~w(performance sale_review summary_line allocation snapshot_comparison
                snapshot_list own_rules key_figures crash_section top_holdings concentration
                asset_class_limits wealth_key_figures data_notes contribution positions
                cash_accounts)

    assert {:ok, [stored]} = Layout.validate([item("sale_review", "row", 1, 3)])
    assert stored == item("sale_review", "row", 1, 3)

    assert {:error, %{reason: :unsupported_size, field: "size"}} =
             Layout.validate([item("due", "row", 1, 1)])

    assert {:error, %{reason: :off_grid, field: "col"}} =
             Layout.validate([item("sale_review", "row", 2, 1)])

    assert {:error, %{reason: :overlap, index: 1, other: 0}} =
             Layout.validate([item("due", "S", 10, 1), item("sale_review", "row", 1, 2)])

    # The row item placed on the first row: what it covers moves below it.
    before = [item("due", "S", 1, 1), item("due", "S", 4, 1), item("sale_review", "L", 7, 3)]

    assert {:ok, arranged} = Arrange.arrange(before, {:resize, 2, "row"})

    assert Enum.map(arranged, &{&1["size"], &1["col"], &1["row"]}) == [
             {"S", 1, 1},
             {"S", 4, 1},
             {"row", 1, 3}
           ]

    # A row item moved onto the first row: both S beside it make room below.
    assert {:ok, row_first} =
             Arrange.arrange([item("sale_review", "row", 1, 3) | Enum.take(before, 2)], {
               :move,
               0,
               {1, 1}
             })

    assert Enum.map(row_first, &{&1["size"], &1["col"], &1["row"]}) == [
             {"row", 1, 1},
             {"S", 1, 2},
             {"S", 4, 2}
           ]

    assert {:ok, _valid} = Layout.validate(row_first)

    sizes = DashboardJSON.catalogue().grid.sizes

    assert sizes["row"] == %{columns: 12, rows: 1, family: nil, height: "content"}
    assert sizes["S"] == %{columns: 3, rows: 2, family: "small", height: "fixed"}

    assert Grid.read(Grid.current(), [item("sale_review", "row", 1, 1)]) ==
             [item("sale_review", "row", 1, 1)]
  end
end
