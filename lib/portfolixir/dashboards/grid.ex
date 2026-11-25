defmodule Portfolixir.Dashboards.Grid do
  @moduledoc """
  Which grid a stored layout was written on, and how a layout of an earlier
  grid is read on today's (ADR-0062's amendment of 2026-11-25, point 3;
  Sprint 32 E4).

    * **Grid 1**, Sprint 31's: the sizes S (3 × 1), W (6 × 1), M (6 × 2),
      T (4 × 3) and L (8 × 3) on rows that grew with their content.
    * **Grid 2**, today's (`current/0`): Apple's families S (3 × 2), M
      (6 × 2), L (6 × 4) and XL (12 × 4) on rows of a fixed height
      (`Portfolixir.Dashboards.Widgets`).

  A dashboard stores the grid its layout was written on (`grid` on
  `dashboards`; every write of a layout stores the current one). `read/2`
  reads a layout of grid 1 as S → S, W → M, M → L, T → L and L → XL with its
  rows doubled — a size its kind no longer takes as the one of its sizes
  nearest to it — and arranges it by the edit mode's rule with no item held
  (`Portfolixir.Dashboards.Arrange.settle/2`), so a widget that grew wider
  moves on instead of lying over another. It is a read: nothing is stored
  until the dashboard's next save, which stores the layout as read, on the
  current grid. The context reads every stored dashboard through it, so the
  screen, the API and the MCP companion answer the same layout.
  """

  alias Portfolixir.Dashboards.Arrange
  alias Portfolixir.Dashboards.Widgets

  @current 2
  @sprint31 %{"S" => "S", "W" => "M", "M" => "L", "T" => "L", "L" => "XL"}

  @doc "The grid every layout is written on today."
  @spec current() :: pos_integer()
  def current, do: @current

  @doc """
  The layout stored on `grid`, as today's grid reads it. A layout of the
  current grid is answered as stored.
  """
  @spec read(term(), [map()]) :: [map()]
  def read(@current, layout), do: layout

  def read(1, layout) when is_list(layout) do
    mapped = Enum.map(layout, &sprint31_item/1)

    case Arrange.settle(mapped) do
      {:ok, arranged} -> arranged
      {:error, _reason} -> mapped
    end
  end

  def read(_grid, layout), do: layout

  defp sprint31_item(%{"size" => size, "row" => row} = item)
       when is_binary(size) and is_integer(row) do
    case Map.fetch(@sprint31, size) do
      {:ok, family} -> %{item | "size" => taken(item["kind"], family), "row" => 2 * row - 1}
      :error -> item
    end
  end

  defp sprint31_item(item), do: item

  # The family, or the kind's grid size nearest to it (by columns and rows
  # apart, the smaller on a tie) where the kind no longer takes it; a kind
  # the registry no longer holds keeps the family.
  defp taken(kind, family) do
    with {:ok, registered} <- Widgets.fetch(kind),
         false <- family in registered.sizes,
         [_ | _] = sizes <-
           Enum.filter(registered.sizes, &match?({:ok, _}, Widgets.dimensions(&1))) do
      {:ok, {w, h}} = Widgets.dimensions(family)

      Enum.min_by(sizes, fn size ->
        {:ok, {sw, sh}} = Widgets.dimensions(size)
        {abs(sw - w) + abs(sh - h), sw * sh}
      end)
    else
      _taken -> family
    end
  end
end
