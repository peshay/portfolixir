defmodule PortfolixirWeb.Components.ChartAxis do
  @moduledoc """
  The axis that starts at 0: the stacked chart's range and its round steps
  (Sprint 28 D2), shared with the line chart's „ab 0“ (I43, Sprint 30 W1;
  board `ux-design-2026-11-15-sprint30/01-axis-start` ③ and ④), so the
  Total line at „ab 0“ is drawn on the very axis the stack at „Kategorien“
  is drawn on and meets its top edge day by day.

  Floats here are coordinates only, never stored.
  """

  @doc """
  The range of an axis that starts at 0: from 0, or the lowest value where
  it lies below 0, to the highest value, or 0, plus a twentieth of the
  span; a flat range at its floor spans one unit. `{lo, hi}`.
  """
  @spec zero_range(float(), float()) :: {float(), float()}
  def zero_range(lowest, highest) do
    lo = min(lowest, 0.0)
    top = max(highest, 0.0)
    hi = if top == lo, do: lo + 1.0, else: top + (top - lo) * 0.05
    {lo, hi}
  end

  @doc """
  The ticks in round steps (D2): the multiples of a round step in the
  axis's own unit that lie between `lo` and `hi`, 0 among them whenever
  the range reaches below zero, about five of them. `unit` is one unit of
  the axis (`{unit, min_step}`: the size of one unit and the smallest step
  in units). `{tick values, step in the unit}`.
  """
  @spec round_ticks(float(), float(), {float(), float()}) :: {[float()], float()}
  def round_ticks(lo, hi, {unit, min_step}) do
    step = max(round_step((hi - lo) / unit / 5), min_step)
    first = Float.ceil(lo / unit / step - 1.0e-9)
    last = Float.floor(hi / unit / step + 1.0e-9)
    ticks = for k <- trunc(first)..trunc(last)//1, do: k * step * unit
    {ticks, step}
  end

  @doc """
  The floor of an axis whose range reaches below zero (#1366, board
  `ux-design-2026-11-15-sprint30/02-wealth-polish` ③): the next multiple at
  or below `lo` of the step `round_ticks/3` takes for the data's range, in
  each of `units` (the money's and the privacy mode's percent), the lowest
  of them, so the lowest value sits on a labelled tick or above one in
  either unit, however shallow the dip, and the range, so the picture, is
  the same in both. A range from 0 up keeps its floor.
  """
  @spec floor_below_zero(float(), float(), [{float(), float()}]) :: float()
  def floor_below_zero(lo, _hi, _units) when lo >= 0, do: lo

  def floor_below_zero(lo, hi, units) do
    units
    |> Enum.map(fn {unit, _min_step} = one ->
      {_ticks, step} = round_ticks(lo, hi, one)
      Float.floor(lo / unit / step + 1.0e-9) * step * unit
    end)
    |> Enum.min()
  end

  @doc """
  The ticks at a given `step` (in the unit) between `lo` and `hi`: the
  step the data's range asked for, on a range `floor_below_zero/3` widened.
  """
  @spec ticks(float(), float(), {float(), float()}, float()) :: [float()]
  def ticks(lo, hi, {unit, _min_step}, step) do
    first = Float.ceil(lo / unit / step - 1.0e-9)
    last = Float.floor(hi / unit / step + 1.0e-9)
    for k <- trunc(first)..trunc(last)//1, do: k * step * unit
  end

  @doc """
  The smallest round step, 1, 2, 2.5 or 5 times a power of ten, at least
  `raw`.
  """
  @spec round_step(float()) :: float()
  def round_step(raw) do
    magnitude = :math.pow(10, Float.floor(:math.log10(raw)))
    Enum.find([1, 2, 2.5, 5, 10], &(&1 * magnitude >= raw)) * magnitude
  end

  @doc "The decimal places a tick of `step` prints: none for whole steps."
  @spec places(number()) :: 0 | 1 | 2
  def places(step) do
    cond do
      step >= 1 and Float.round(step * 1.0) == step -> 0
      Float.round(step * 10.0) == step * 10 -> 1
      true -> 2
    end
  end
end
