defmodule Portfolixir.Dashboards.ArrangeTest do
  # Sprint 32 E1 (ADR-0062's amendment of 2026-11-25, point 1; I58;
  # planning board ux-design-2026-11-25-sprint32/01 ②, A): a resize, a
  # move or an add never asks the operator to delete anything. The widget
  # acted on keeps the place it was given, what it covers makes room, then
  # every other widget floats up. A pure function of the layout and the
  # action: the screen, a test and an agent get the same answer.
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Portfolixir.Dashboards
  alias Portfolixir.Dashboards.Arrange
  alias Portfolixir.Dashboards.Layout
  alias Portfolixir.Dashboards.Widgets

  # Board 01 ② is drawn on Sprint 31's grid: S 3 × 1, M 6 × 2, T 4 × 3,
  # L 8 × 3. The arrangement reads a size only through its dimensions, so
  # the board's case is pinned on the board's own grid, whatever the
  # registry's sizes are called; `"Z"` stands for the 12 × 1 „Zeile“.
  @board %{
    "S" => {3, 1},
    "W" => {6, 1},
    "M" => {6, 2},
    "T" => {4, 3},
    "L" => {8, 3},
    "Z" => {12, 1},
    "F" => {12, 1}
  }
  defp board_dimensions(size), do: Map.fetch(@board, size)

  defp item(kind, size, col, row),
    do: %{"kind" => kind, "size" => size, "col" => col, "row" => row, "settings" => %{}}

  defp places(layout), do: Enum.map(layout, &{&1["kind"], &1["size"], &1["col"], &1["row"]})

  # User story:
  # As the operator resizing a widget on my dashboard,
  # I want the widgets it would cover to make room and the gaps to close,
  # so that I never have to delete something to make a widget larger.
  #
  # Acceptance criteria:
  # - Board 01 ② A, to the cell: „Gesamtwert“ S → M at column 1, row 1;
  #   Datenqualität and Fällig move into row 1 beside it, Abseits below
  #   Datenqualität, Wertentwicklung and Drift one row down, Tops und
  #   Flops and Crashes after them.
  # - The widget acted on keeps its place; the list keeps its order.
  test "board 01 ②: Gesamtwert from S to M, the others make room, to the cell" do
    before = [
      item("total_value", "S", 1, 1),
      item("data_quality", "S", 4, 1),
      item("due", "S", 7, 1),
      item("off_target", "S", 10, 1),
      item("performance", "L", 1, 2),
      item("allocation_drift", "T", 9, 2),
      item("movers", "M", 1, 5),
      item("crashes", "M", 7, 5)
    ]

    assert {:ok, after_resize} =
             Arrange.arrange(before, {:resize, 0, "M"}, dimensions: &board_dimensions/1)

    assert places(after_resize) == [
             {"total_value", "M", 1, 1},
             {"data_quality", "S", 7, 1},
             {"due", "S", 10, 1},
             {"off_target", "S", 7, 2},
             {"performance", "L", 1, 3},
             {"allocation_drift", "T", 9, 3},
             {"movers", "M", 1, 6},
             {"crashes", "M", 7, 6}
           ]

    assert Arrange.moved(before, after_resize) == [1, 2, 3, 4, 5, 6, 7]
  end

  # Acceptance criteria:
  # - A chain: the widget placed covers one, whose new place covers the
  #   next, whose new place covers the third; each moves on in reading
  #   order, none is lost, none overlaps.
  test "a chain of three pushed widgets, each moving on in reading order" do
    before = [
      item("a", "F", 1, 1),
      item("b", "F", 1, 2),
      item("c", "F", 1, 3),
      item("d", "F", 1, 4)
    ]

    assert {:ok, arranged} =
             Arrange.arrange(before, {:move, 3, {1, 1}}, dimensions: &board_dimensions/1)

    assert places(arranged) == [
             {"a", "F", 1, 2},
             {"b", "F", 1, 3},
             {"c", "F", 1, 4},
             {"d", "F", 1, 1}
           ]

    assert Arrange.moved(before, arranged) == [0, 1, 2, 3]
  end

  # Acceptance criteria:
  # - What the widget acted on covers moves to the first free place after
  #   its own, so it may move beside the widget rather than below it, and
  #   then every gap closes: what nothing stops floats up.
  test "a resize over two rows: the covered widgets move on, then the gaps close" do
    before = [
      item("a", "M", 1, 1),
      item("b", "M", 7, 1),
      item("c", "W", 1, 3),
      item("d", "W", 7, 3)
    ]

    # „a“ grows to L (8 × 3): it covers „b“ (columns 7 and 8), „c“ and
    # „d“ (row 3). „b“ finds no place in rows 1 to 3 and goes below „a“;
    # „c“ goes beside „b“, „d“ below „c“. Nothing can float higher.
    assert {:ok, arranged} =
             Arrange.arrange(before, {:resize, 0, "L"}, dimensions: &board_dimensions/1)

    assert places(arranged) == [
             {"a", "L", 1, 1},
             {"b", "M", 1, 4},
             {"c", "W", 7, 4},
             {"d", "W", 7, 5}
           ]

    assert no_overlap?(arranged, &board_dimensions/1)

    # Shrunk back, „a“ leaves rows 2 and 3 free: everything floats up.
    assert {:ok, shrunk} =
             Arrange.arrange(arranged, {:resize, 0, "S"}, dimensions: &board_dimensions/1)

    assert places(shrunk) == [
             {"a", "S", 1, 1},
             {"b", "M", 1, 2},
             {"c", "W", 7, 1},
             {"d", "W", 7, 2}
           ]
  end

  # Acceptance criteria:
  # - A 12 × 1 item („Zeile“) is an item like any other: placed on it, a
  #   widget pushes it down and it floats back up as far as it can; it
  #   never shrinks or leaves the full width.
  test "a 12 × 1 „Zeile“ in the way moves as any item does" do
    before = [
      item("a", "S", 1, 1),
      item("section", "Z", 1, 2),
      item("b", "M", 1, 3)
    ]

    # „a“ grows to M (6 × 2) and covers the Zeile in row 2: the Zeile moves
    # to the first place it fits after its own, row 3, which covers „b“,
    # which moves on below it.
    assert {:ok, arranged} =
             Arrange.arrange(before, {:resize, 0, "M"}, dimensions: &board_dimensions/1)

    assert places(arranged) == [
             {"a", "M", 1, 1},
             {"section", "Z", 1, 3},
             {"b", "M", 1, 4}
           ]

    # Moved onto the Zeile, a widget takes its place and the Zeile goes
    # below it; „a“, covered by nothing, stays where it is.
    assert {:ok, moved} =
             Arrange.arrange(before, {:move, 2, {1, 2}}, dimensions: &board_dimensions/1)

    assert places(moved) == [
             {"a", "S", 1, 1},
             {"section", "Z", 1, 4},
             {"b", "M", 1, 2}
           ]
  end

  # Acceptance criteria:
  # - A widget added at a place takes it; what it covers makes room,
  #   moving on to the first free place after its own in reading order.
  # - The 41st widget is refused (`:too_many_items`), the layout unread.
  test "an add takes its place, and the 41st widget is refused" do
    before = [item("a", "W", 1, 1), item("b", "W", 7, 1)]

    assert {:ok, added} =
             Arrange.arrange(before, {:add, item("c", "S", 4, 1)},
               dimensions: &board_dimensions/1
             )

    assert places(added) == [
             {"a", "W", 7, 1},
             {"b", "W", 1, 2},
             {"c", "S", 4, 1}
           ]

    forty = for n <- 0..39, do: item("x#{n}", "S", 1 + rem(n, 4) * 3, 1 + div(n, 4))

    assert Arrange.arrange(forty, {:add, item("y", "S", 1, 20)}, dimensions: &board_dimensions/1) ==
             {:error, :too_many_items}
  end

  # Acceptance criteria:
  # - When no place is left up to row 200 (a full-width widget placed at
  #   row 200 over another, which can only go below it), the step is
  #   refused (`:no_room`), never stored with an item past the grid.
  # - A place off the grid and an index the layout does not hold are
  #   refused too; a size with no dimensions is refused.
  test "no place up to row 200, a place off the grid, an unknown item: refused" do
    before = [item("a", "F", 1, 1), item("b", "F", 1, 200)]

    assert Arrange.arrange(before, {:move, 0, {1, 200}}, dimensions: &board_dimensions/1) ==
             {:error, :no_room}

    assert Arrange.arrange(before, {:move, 0, {2, 1}}, dimensions: &board_dimensions/1) ==
             {:error, :off_grid}

    assert Arrange.arrange(before, {:move, 0, {1, 201}}, dimensions: &board_dimensions/1) ==
             {:error, :off_grid}

    assert Arrange.arrange(before, {:move, 0, {1, 0}}, dimensions: &board_dimensions/1) ==
             {:error, :off_grid}

    assert Arrange.arrange(before, {:move, 2, {1, 1}}, dimensions: &board_dimensions/1) ==
             {:error, :not_found}

    assert Arrange.arrange(before, {:resize, 0, "full"}, dimensions: &board_dimensions/1) ==
             {:error, :unsupported_size}
  end

  # Acceptance criteria:
  # - A resize that would leave the grid at the widget's column moves it
  #   left as far as it needs (the place it is given), as the edit mode did.
  test "a resize past the right edge moves the widget left as far as it needs" do
    before = [item("a", "S", 10, 1), item("b", "S", 1, 1)]

    assert {:ok, arranged} =
             Arrange.arrange(before, {:resize, 0, "L"}, dimensions: &board_dimensions/1)

    assert places(arranged) == [{"a", "L", 5, 1}, {"b", "S", 1, 1}]
  end

  # Acceptance criteria:
  # - The context answers the same arrangement (ADR-0062's amendment, 1:
  #   „computed by the context“), with the registry's sizes.
  test "the context arranges with the registry's dimensions" do
    [first | _] = grid_kinds()
    {kind, [size | _]} = first
    layout = [item(kind, size, 1, 1)]

    assert Dashboards.arrange_layout(layout, {:move, 0, {1, 1}}) == {:ok, layout}
  end

  # --- the property ----------------------------------------------------------

  # Acceptance criteria (over generated layouts of registered kinds):
  # - every step answers a layout that validates (`Layout.validate/2`),
  #   with no two items overlapping;
  # - no item but the one acted on could float a row higher;
  # - the item acted on stands where it was put, at the size it was given;
  # - no item is lost or added beyond the one an add brings.
  property "every arrangement validates, closes its gaps, keeps its items and the acted one" do
    check all(
            layout <- layout_gen(),
            action <- action_gen(layout),
            max_runs: 300
          ) do
      {:ok, layout} = Layout.validate(layout)

      case Arrange.arrange(layout, action) do
        {:ok, arranged} ->
          assert {:ok, _} = Layout.validate(arranged)
          assert no_overlap?(arranged, &Widgets.dimensions/1)

          expected_count =
            if match?({:add, _}, action), do: length(layout) + 1, else: length(layout)

          assert length(arranged) == expected_count

          # Every item keeps its kind, in the order sent.
          kinds = Enum.map(layout, & &1["kind"])
          assert Enum.take(Enum.map(arranged, & &1["kind"]), length(layout)) == kinds

          {acted, expected} = acted(layout, action)
          assert Enum.at(arranged, acted) |> Map.take(~w(size col row)) == expected

          for {other, index} <- Enum.with_index(arranged), index != acted, other["row"] > 1 do
            raised = %{other | "row" => other["row"] - 1}
            rest = List.delete_at(arranged, index)

            assert Enum.any?(rest, fn rested ->
                     overlap?(raised, rested, &Widgets.dimensions/1)
                   end),
                   "item #{index} could float higher: #{inspect(places(arranged))}"
          end

        {:error, reason} ->
          # Rows stay low in the generator, so only an action off the grid
          # (a move the generator places too far right for its width) may
          # be refused.
          assert reason == :off_grid
      end
    end
  end

  defp acted(layout, {:resize, index, size}) do
    {:ok, {width, _}} = Widgets.dimensions(size)
    item = Enum.at(layout, index)

    {index,
     %{
       "size" => size,
       "col" => min(item["col"], Layout.columns() - width + 1),
       "row" => item["row"]
     }}
  end

  defp acted(layout, {:move, index, {col, row}}),
    do: {index, %{"size" => Enum.at(layout, index)["size"], "col" => col, "row" => row}}

  defp acted(layout, {:add, item}), do: {length(layout), Map.take(item, ~w(size col row))}

  defp grid_kinds do
    for kind <- Widgets.kinds(),
        sizes = Enum.filter(kind.sizes, &match?({:ok, _}, Widgets.dimensions(&1))),
        sizes != [],
        do: {kind.key, sizes}
  end

  defp kind_size_gen do
    StreamData.bind(StreamData.member_of(grid_kinds()), fn {kind, sizes} ->
      StreamData.tuple({StreamData.constant(kind), StreamData.member_of(sizes)})
    end)
  end

  # A layout: up to 14 items at random places in the top rows, each kept
  # only where it fits beside the ones before it.
  defp layout_gen do
    StreamData.list_of(
      StreamData.tuple({kind_size_gen(), StreamData.integer(1..12), StreamData.integer(1..12)}),
      max_length: 14
    )
    |> StreamData.map(fn raws ->
      Enum.reduce(raws, [], fn {{kind, size}, col, row}, acc ->
        {:ok, {width, _}} = Widgets.dimensions(size)
        candidate = item(kind, size, min(col, Layout.columns() - width + 1), row)

        if Enum.any?(acc, fn placed -> overlap?(candidate, placed, &Widgets.dimensions/1) end),
          do: acc,
          else: acc ++ [candidate]
      end)
    end)
  end

  defp add_gen do
    StreamData.map(
      StreamData.tuple({kind_size_gen(), StreamData.integer(1..12), StreamData.integer(1..14)}),
      fn {{kind, size}, col, row} ->
        {:ok, {width, _}} = Widgets.dimensions(size)
        {:add, item(kind, size, min(col, Layout.columns() - width + 1), row)}
      end
    )
  end

  # An action on the generated layout: an add, a move of one of its items
  # anywhere in the top rows, or a resize to a size its kind takes.
  defp action_gen([]), do: add_gen()

  defp action_gen(layout) do
    count = length(layout)

    StreamData.one_of([
      add_gen(),
      StreamData.tuple(
        {StreamData.constant(:move), StreamData.integer(0..(count - 1)),
         StreamData.tuple({StreamData.integer(1..12), StreamData.integer(1..14)})}
      ),
      StreamData.bind(StreamData.integer(0..(count - 1)), fn index ->
        {:ok, kind} = Widgets.fetch(Enum.at(layout, index)["kind"])
        sizes = Enum.filter(kind.sizes, &match?({:ok, _}, Widgets.dimensions(&1)))
        StreamData.map(StreamData.member_of(sizes), &{:resize, index, &1})
      end)
    ])
  end

  defp no_overlap?(layout, dimensions) do
    pairs =
      for {a, i} <- Enum.with_index(layout), {b, j} <- Enum.with_index(layout), i < j, do: {a, b}

    Enum.all?(pairs, fn {a, b} -> not overlap?(a, b, dimensions) end)
  end

  defp overlap?(a, b, dimensions) do
    {:ok, {wa, ha}} = dimensions.(a["size"])
    {:ok, {wb, hb}} = dimensions.(b["size"])

    a["col"] < b["col"] + wb and b["col"] < a["col"] + wa and a["row"] < b["row"] + hb and
      b["row"] < a["row"] + ha
  end
end
