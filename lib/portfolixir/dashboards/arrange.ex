defmodule Portfolixir.Dashboards.Arrange do
  @moduledoc """
  The arrangement of a layout after one action (ADR-0062's amendment of
  2026-11-25, point 1; I58; planning board
  `ux-design-2026-11-25-sprint32/01` ②, A): the others make room.

  A pure function of a layout and one action — `{:resize, index, size}`,
  `{:move, index, {col, row}}` or `{:add, item}` — so the edit mode, the
  API's `arrange: "push"`, a test and an agent get the same answer. It
  reads nothing and writes nothing.

  The rule:

    1. **The item acted on keeps the place it was given** (a resize keeps
       its column, moved left only as far as the grid needs; a move and an
       add take the place sent) and its size.
    2. **What it covers makes room, in reading order.** Every other item,
       in the reading order of its own place (row, then column), keeps its
       place when nothing placed before it holds a cell of it; otherwise it
       moves to the first free place after its own place in reading order
       (on along its row, then the rows below, from the first column). An
       item that move covers moves on in its turn, and so on. This is the
       board's „Datenqualität, Fällig und Abseits rücken in die frei
       gebliebenen Felder rechts daneben, alles darunter rückt um eine
       Reihe“ to the cell (`test/portfolixir/dashboards/arrange_test.exs`).
    3. **Then the gaps close.** Every item but the one acted on, in reading
       order, floats up as far as no other item stops it, until none can.

  An item is read only through its dimensions (`Portfolixir.Dashboards.Widgets.dimensions/1`,
  or the `dimensions:` option), so a 12 × 1 item („Zeile“) is arranged as
  any item is.

  The refusals left: `:too_many_items` (an add to a layout that already
  holds `Portfolixir.Dashboards.Layout.max_items/0`), `:no_room` (an item
  would start below `Portfolixir.Dashboards.Layout.max_row/0` once the gaps
  are closed), `:off_grid` (the place given leaves the grid),
  `:unsupported_size` (a size with no dimensions), `:not_found` (an index
  the layout does not hold).

  The answer keeps the items in the order sent (an add appended last),
  each with its fields as sent and only `"col"`, `"row"` and, for a resize,
  `"size"` changed. `settle/2` applies steps 2 and 3 with no item acted
  on: it is how a layout read from an earlier grid is set on this one.
  """

  alias Portfolixir.Dashboards.Layout
  alias Portfolixir.Dashboards.Widgets

  @type item :: Layout.item()
  @type action ::
          {:resize, non_neg_integer(), String.t()}
          | {:move, non_neg_integer(), {integer(), integer()}}
          | {:add, item()}
  @type reason :: :too_many_items | :no_room | :off_grid | :unsupported_size | :not_found

  @doc """
  The layout arranged after `action`: `{:ok, layout}` or `{:error, reason}`.
  Option `dimensions:` reads a size's `{width, height}` (default
  `Portfolixir.Dashboards.Widgets.dimensions/1`).
  """
  @spec arrange([item()], action(), keyword()) :: {:ok, [item()]} | {:error, reason()}
  def arrange(layout, action, opts \\ []) when is_list(layout) do
    dimensions = Keyword.get(opts, :dimensions, &Widgets.dimensions/1)

    with {:ok, layout, index} <- apply_action(layout, action, dimensions),
         :ok <- on_grid(Enum.at(layout, index), dimensions) do
      around(layout, index, dimensions)
    end
  end

  @doc """
  The layout with steps 2 and 3 applied and no item held: each item, in
  reading order, kept where it fits beside the ones before it (moved left
  where it would leave the grid), else moved on to the first free place
  after its own; then every gap closed. `{:error, :no_room}` when an item
  would start below the last row; `{:error, :unsupported_size}` for a size
  with no dimensions.
  """
  @spec settle([item()], keyword()) :: {:ok, [item()]} | {:error, :no_room | :unsupported_size}
  def settle(layout, opts \\ []) when is_list(layout) do
    dimensions = Keyword.get(opts, :dimensions, &Widgets.dimensions/1)

    if Enum.all?(layout, &match?({:ok, _}, dimensions.(&1["size"]))),
      do: around(layout, nil, dimensions),
      else: {:error, :unsupported_size}
  end

  @doc """
  The indexes (in `before`'s order) of the items whose place differs in
  `after_layout`: what the edit mode marks as moved. An item added in
  `after_layout` is not among them; the item acted on is, when its place
  changed.
  """
  @spec moved([item()], [item()]) :: [non_neg_integer()]
  def moved(before, after_layout) do
    before
    |> Enum.zip(after_layout)
    |> Enum.with_index()
    |> Enum.flat_map(fn {{old, new}, index} ->
      if {old["col"], old["row"]} == {new["col"], new["row"]}, do: [], else: [index]
    end)
  end

  # --- the action ---------------------------------------------------------------

  defp apply_action(layout, {:resize, index, size}, dimensions) when is_integer(index) do
    with {:ok, item} <- fetch(layout, index),
         {:ok, {width, _height}} <- size_of(size, dimensions) do
      col = min(item["col"], Layout.columns() - width + 1)
      {:ok, List.replace_at(layout, index, %{item | "size" => size, "col" => col}), index}
    end
  end

  defp apply_action(layout, {:move, index, {col, row}}, _dimensions)
       when is_integer(index) and is_integer(col) and is_integer(row) do
    with {:ok, item} <- fetch(layout, index) do
      {:ok, List.replace_at(layout, index, %{item | "col" => col, "row" => row}), index}
    end
  end

  defp apply_action(layout, {:add, %{"col" => col, "row" => row} = item}, dimensions)
       when is_integer(col) and is_integer(row) do
    cond do
      length(layout) >= Layout.max_items() ->
        {:error, :too_many_items}

      size_of(item["size"], dimensions) == {:error, :unsupported_size} ->
        {:error, :unsupported_size}

      true ->
        {:ok, layout ++ [item], length(layout)}
    end
  end

  defp apply_action(_layout, _action, _dimensions), do: {:error, :not_found}

  defp fetch(layout, index) when index >= 0 and index < length(layout),
    do: {:ok, Enum.at(layout, index)}

  defp fetch(_layout, _index), do: {:error, :not_found}

  defp size_of(size, dimensions) do
    case dimensions.(size) do
      {:ok, {width, height}} -> {:ok, {width, height}}
      :error -> {:error, :unsupported_size}
    end
  end

  defp on_grid(%{"col" => col, "row" => row, "size" => size}, dimensions) do
    {:ok, {width, _height}} = size_of(size, dimensions)

    if col >= 1 and col + width - 1 <= Layout.columns() and row >= 1 and row <= Layout.max_row(),
      do: :ok,
      else: {:error, :off_grid}
  end

  # --- steps 2 and 3 --------------------------------------------------------------

  # `held` is the index of the item acted on, or nil (settle).
  defp around(layout, held, dimensions) do
    rects =
      layout
      |> Enum.with_index()
      |> Map.new(fn {item, index} ->
        {:ok, {width, height}} = dimensions.(item["size"])
        {index, {item["col"], item["row"], width, height}}
      end)

    pushed = push(rects, held)
    floated = float(pushed, held)

    if Enum.all?(floated, fn {_index, {_col, row, _w, _h}} -> row <= Layout.max_row() end) do
      {:ok,
       layout
       |> Enum.with_index()
       |> Enum.map(fn {item, index} ->
         {col, row, _w, _h} = Map.fetch!(floated, index)
         %{item | "col" => col, "row" => row}
       end)}
    else
      {:error, :no_room}
    end
  end

  # Step 2: the held item first, then every other in the reading order of
  # its own place, each at the first free place at or after it.
  defp push(rects, held) do
    start = if held, do: %{held => Map.fetch!(rects, held)}, else: %{}

    rects
    |> Enum.reject(fn {index, _rect} -> index == held end)
    |> Enum.sort_by(fn {index, {col, row, _w, _h}} -> {row, col, index} end)
    |> Enum.reduce(start, fn {index, rect}, placed ->
      Map.put(placed, index, first_free(rect, Map.values(placed)))
    end)
  end

  # The first place at or after `{col, row}` in reading order, on the grid
  # for its width, that overlaps none of `placed`. Rows past the last are
  # searched too: step 3 may lift the item back, and `around/3` refuses
  # one left below the last row.
  defp first_free({col, row, width, height}, placed) do
    last_col = Layout.columns() - width + 1
    col = col |> min(last_col) |> max(1)

    Stream.iterate(row, &(&1 + 1))
    |> Stream.flat_map(fn r ->
      from = if r == row, do: col, else: 1
      Stream.map(from..last_col//1, &{&1, r, width, height})
    end)
    |> Enum.find(fn rect -> not Enum.any?(placed, &overlap?(&1, rect)) end)
  end

  # Step 3: every item but the held one, in reading order, as high as it
  # goes; repeated until no item moves.
  defp float(rects, held) do
    order =
      rects
      |> Enum.reject(fn {index, _rect} -> index == held end)
      |> Enum.sort_by(fn {index, {col, row, _w, _h}} -> {row, col, index} end)
      |> Enum.map(&elem(&1, 0))

    {floated, moved?} =
      Enum.reduce(order, {rects, false}, fn index, {acc, moved?} ->
        {col, row, width, height} = Map.fetch!(acc, index)
        others = acc |> Map.delete(index) |> Map.values()
        top = rise(col, row, width, height, others)
        {Map.put(acc, index, {col, top, width, height}), moved? or top != row}
      end)

    if moved?, do: float(floated, held), else: floated
  end

  defp rise(col, row, width, height, others) do
    if row > 1 and not Enum.any?(others, &overlap?(&1, {col, row - 1, width, height})),
      do: rise(col, row - 1, width, height, others),
      else: row
  end

  defp overlap?({c1, r1, w1, h1}, {c2, r2, w2, h2}),
    do: c1 < c2 + w2 and c2 < c1 + w1 and r1 < r2 + h2 and r2 < r1 + h1
end
