defmodule PortfolixirWeb.Portfolio.CategoryColors do
  @moduledoc """
  The colours Wealth draws categories, cash and the unclassified rest in,
  one source for the allocation sunburst and the stacked value chart (I23,
  FR-53), so a category looks the same on both tabs (the owner, 2026-11-07).

  A category wears the colour the operator chose for it; one without
  cycles through the palette in the order the allocation lists its rows,
  the tree's preorder of the categories it keeps (`resolve/1`). Cash has
  its own neutral colour, the unclassified rest a grey; both stay apart
  from the palette.
  """

  # Categories without a chosen colour cycle through this palette (in tree
  # order), so an unstyled tree still renders a readable sunburst/legend
  # instead of uniform grey (Steve UAT, reconsolidation).
  @palette [
    "#2563eb",
    "#0d9488",
    "#d97706",
    "#db2777",
    "#65a30d",
    "#7c3aed",
    "#0891b2",
    "#c2410c"
  ]

  # Neutral cash colour, distinct from the category palette and the grey
  # unassigned/excluded shades, for the cash segment in the basis (issue #335).
  @cash "#0ea5e9"
  @unassigned "#9ca3af"

  @doc "The category palette, in the order it is handed out."
  def palette, do: @palette

  @doc "The palette's colour at `index`, cycling."
  def at(index) when is_integer(index) and index >= 0,
    do: Enum.at(@palette, rem(index, length(@palette)))

  @doc "The cash colour."
  def cash, do: @cash

  @doc "The grey of the unclassified rest."
  def unassigned, do: @unassigned

  @doc """
  The allocation's category rows with every display colour resolved: an
  explicitly chosen colour wins, everything else cycles through the palette
  in the rows' order. Downstream consumers (sunburst, legend, drift table,
  the stacked chart) can then rely on `color` being set.
  """
  def resolve(categories) when is_list(categories) do
    categories
    |> Enum.with_index()
    |> Enum.map(fn {row, index} -> %{row | color: row.color || at(index)} end)
  end

  @doc "The resolved colours of the allocation's rows by category id."
  def by_category(categories) when is_list(categories),
    do: categories |> resolve() |> Map.new(&{&1.category_id, &1.color})
end
