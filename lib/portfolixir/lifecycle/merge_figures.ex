defmodule Portfolixir.Lifecycle.MergeFigures do
  @moduledoc """
  The per-day position folds a merge's preview states and its linearity
  check reads (ADR-0050 §7's depot check, §9's security check), and the cash
  accounts a collapse changes. Shared by the depot merge
  (`Portfolixir.Lifecycle.DepotMerge`) and the security merge behind it.

  `eod_positions/1` is the ledger's own fold, one booking at a time
  (`Portfolixir.Ledger.Positions.apply_transaction/3`), replayed in the
  shared order (`Projection.replay_sort/1`): a split's scaled quantity is
  rounded once at volume scale 6 (ADR-0028 §3), exactly as every read of a
  position states it.

  It answers `[{date, positions}]`, ascending: the positions at the end of
  each day a row falls on. `sample/2` reads a series at given dates.
  """

  import Ecto.Query

  alias Portfolixir.Ledger.Positions
  alias Portfolixir.Ledger.Projection
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Repo

  @zero Decimal.new("0")

  @typedoc "Positions at the end of each day a row falls on, ascending by day."
  @type series :: [{Date.t(), map()}]

  @doc "The ledger's own position fold, per day (see the moduledoc)."
  @spec eod_positions([map()]) :: series()
  def eod_positions(rows) do
    ordered = Projection.replay_sort(rows)
    accounts = Projection.account_portfolios(ordered)

    ordered
    |> Enum.reduce({[], %{}}, fn row, {days, positions} ->
      positions = Positions.apply_transaction(positions, row, accounts)
      {end_of_day(days, row.date, positions), positions}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  # A later row of the same day replaces the day's positions.
  defp end_of_day([{date, _earlier} | rest] = days, day, positions) do
    if Date.compare(date, day) == :eq,
      do: [{date, positions} | rest],
      else: [{day, positions} | days]
  end

  defp end_of_day([], day, positions), do: [{day, positions}]

  @doc """
  `%{date => positions}` at the end of each of `dates`: the last day on or
  before it, or nothing. One walk over both ascending lists.
  """
  @spec sample(series(), [Date.t()]) :: %{Date.t() => map()}
  def sample(series, dates) do
    dates
    |> Enum.uniq()
    |> Enum.sort(Date)
    |> Enum.reduce({series, %{}, %{}}, fn date, {rest, current, acc} ->
      {rest, current} = advance(rest, current, date)
      {rest, current, Map.put(acc, date, current)}
    end)
    |> elem(2)
  end

  defp advance([{day, positions} | rest] = series, current, date) do
    if Date.compare(day, date) == :gt,
      do: {series, current},
      else: advance(rest, positions, date)
  end

  defp advance([], current, _date), do: {[], current}

  @doc "The rounded quantity of `key` in a sampled series at `date` (zero when not held)."
  @spec quantity(%{Date.t() => map()}, Date.t(), term()) :: Decimal.t()
  def quantity(sampled, date, key),
    do: sampled |> Map.get(date, %{}) |> Map.get(key, @zero)

  # --- the cash side of a collapse ------------------------------------------------------

  @doc """
  A collapsed booking leaves its cash account too: each cash account a row
  of `pairs` (`{source_row, target_row}`, the source row collapsed) books on,
  with its balance before and after the collapse. `[]` without pairs.
  """
  @spec collapsed_cash_accounts([{map(), map()}]) :: [map()]
  def collapsed_cash_accounts([]), do: []

  def collapsed_cash_accounts(pairs) do
    collapsed = MapSet.new(pairs, fn {row, _target_row} -> row.id end)

    ids =
      for {row, _target_row} <- pairs,
          {account_id, _leg} <- Projection.effects(row).cash,
          account_id != nil,
          uniq: true,
          do: account_id

    case ids do
      [] -> []
      ids -> cash_account_lines(ids, collapsed)
    end
  end

  defp cash_account_lines(ids, collapsed) do
    names = Map.new(Repo.all(from(a in CashAccount, where: a.id in ^ids, select: {a.id, a.name})))

    rows =
      Repo.all(
        from(t in Transaction,
          where: t.cash_account_id in ^ids or t.counter_cash_account_id in ^ids
        )
      )

    before = Projection.cash_balances(rows)

    after_collapse =
      rows |> Enum.reject(&MapSet.member?(collapsed, &1.id)) |> Projection.cash_balances()

    for id <- Enum.sort(ids) do
      %{
        id: id,
        name: Map.get(names, id),
        balance_before: Map.get(before, id, @zero),
        balance_after: Map.get(after_collapse, id, @zero)
      }
    end
  end
end
