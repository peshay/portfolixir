defmodule Portfolixir.Dashboards.FirstFreeTest do
  # Sprint 31 D7 (ADR-0062 §1, §4; planning board
  # ux-design-2026-11-21-sprint31/01 ②): „hinzufügen“ in „Alle Widgets“
  # places a widget at the first free place of a stored dashboard's
  # 12-column grid, scanning row by row, left to right. A pure function of
  # the layout: it reads nothing and writes nothing; the write is the
  # journaled replace.
  use ExUnit.Case, async: true

  alias Portfolixir.Dashboards.Layout
  alias Portfolixir.Dashboards.Templates

  defp item(kind, size, col, row),
    do: %{"kind" => kind, "size" => size, "col" => col, "row" => row, "settings" => %{}}

  # User story:
  # As the operator adding a widget from the catalogue to a dashboard,
  # I want it placed at the first place on the grid where it fits,
  # so that it lands where I will see it and never on another widget.
  #
  # Acceptance criteria:
  # - An empty layout places any size at column 1, row 1.
  # - The scan reads row by row, left to right: an S beside three S in row 1
  #   goes to column 10; a widget too wide for the gap goes below the S
  #   (two rows each since Sprint 32 E4), to row 3.
  # - A tall widget's rows count as taken: on the template (Apple's
  #   families), whose rows are full down to row 14 and whose Verkaufs-
  #   rückblick (L) holds rows 15 to 18 on the left, an S goes beside
  #   Snapshots in row 15.
  # - The place found for every grid size validates with the layout.
  test "the first free place, row by row, left to right" do
    assert Layout.first_free([], "M") == {:ok, %{"col" => 1, "row" => 1}}

    three = [
      item("total_value", "S", 1, 1),
      item("due", "S", 4, 1),
      item("off_target", "S", 7, 1)
    ]

    assert Layout.first_free(three, "S") == {:ok, %{"col" => 10, "row" => 1}}
    assert Layout.first_free(three, "M") == {:ok, %{"col" => 1, "row" => 3}}

    {:ok, overview} = Templates.fetch("overview")

    for size <- ~w(S M L XL) do
      assert {:ok, place} = Layout.first_free(overview.layout, size)

      # Validated with a kind that takes the size.
      kind =
        %{
          "S" => "due",
          "M" => "snapshots",
          "L" => "movers",
          "XL" => "performance"
        }[size]

      placed = overview.layout ++ [Map.merge(item(kind, size, 0, 0), place)]
      assert {:ok, _} = Layout.validate(placed), "#{size} at #{inspect(place)} does not validate"
    end

    assert Layout.first_free(overview.layout, "S") == {:ok, %{"col" => 10, "row" => 15}}
  end

  # User story:
  # As the operator adding a widget to a full dashboard,
  # I want to be told it does not fit, not to see it dropped or stacked,
  # so that nothing is placed where the grid has no room.
  #
  # Acceptance criteria:
  # - A layout of 40 items, the most a dashboard holds, has no place.
  # - `full` and an unknown size are no grid size and have no place.
  test "a full layout, a page size and an unknown size have no place" do
    forty = for row <- 1..40, do: item("due", "S", 1, 2 * row - 1)

    assert Layout.first_free(forty, "S") == {:error, :too_many_items}
    assert Layout.first_free([], "full") == {:error, :unsupported_size}
    assert Layout.first_free([], "W") == {:error, :unsupported_size}
    assert Layout.first_free([], nil) == {:error, :unsupported_size}
  end
end
