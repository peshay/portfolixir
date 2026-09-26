defmodule Portfolixir.Lifecycle.MergeFigures do
  @moduledoc """
  The per-day position folds a merge's preview states and its linearity
  check reads (ADR-0050 §7's depot check, §9's security check), and the cash
  accounts a collapse changes. Shared by the depot merge
  (`Portfolixir.Lifecycle.DepotMerge`) and the security merge
  (`Portfolixir.Lifecycle.SecurityMerge`).

  Two folds over the same legs of `Portfolixir.Ledger.Projection.effects/1`,
  replayed in the shared order (`Projection.replay_sort/1`):

    * `eod_positions/1` — the ledger's own fold, one booking at a time
      (`Portfolixir.Ledger.Positions.apply_transaction/3`): a split's scaled
      quantity is rounded once at volume scale 6 (ADR-0028 §3), exactly as
      every read of a position states it;
    * `eod_exact/1` — the same fold in exact rational arithmetic: a split
      multiplies by its ratio and rounds nothing. Every leg of the fold is
      linear, so in this fold the merged quantity equals the sum of the
      parts **exactly** whenever every booking is scaled by the same splits
      after the merge as before it. A difference here is never a rounding
      artefact: it is a split that would rescale bookings it never scaled
      (§9's refusal), where a difference in the rounded fold alone is the
      one-unit-per-split rounding §7 lists.

  Both answer `[{date, positions}]`, ascending: the positions at the end of
  each day a row falls on. `sample/2` reads a series at given dates.
  """

  import Ecto.Query

  alias Portfolixir.Ledger.Positions
  alias Portfolixir.Ledger.Projection
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Repo

  @zero Decimal.new("0")

  @typedoc "An exact quantity: `{numerator, denominator}`, reduced, the denominator positive."
  @type rational :: {integer(), pos_integer()}

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

  @doc "The same fold in exact rational arithmetic, per day (see the moduledoc)."
  @spec eod_exact([map()]) :: series()
  def eod_exact(rows) do
    ordered = Projection.replay_sort(rows)
    accounts = Projection.account_portfolios(ordered)

    ordered
    |> Enum.reduce({[], %{}}, fn row, {days, positions} ->
      positions =
        Enum.reduce(Projection.effects(row).quantities, positions, &exact_leg(&1, &2, accounts))

      {end_of_day(days, row.date, positions), positions}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  # A scale leg multiplies every position of its security in its own
  # portfolio, as `Positions` does, without the rounding.
  defp exact_leg({:scale, scale}, positions, accounts) do
    {numerator, denominator} = scale.ratio

    Map.new(positions, fn {{account_id, security_id} = key, quantity} ->
      if security_id == scale.security_id and
           Map.get(accounts, account_id) == scale.portfolio_id,
         do: {key, mult(quantity, numerator, denominator)},
         else: {key, quantity}
    end)
  end

  defp exact_leg({account_id, security_id, delta}, positions, _accounts) do
    delta = rational(delta)
    Map.update(positions, {account_id, security_id}, delta, &add(&1, delta))
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

  @doc "The exact quantity of `key` in a sampled exact series at `date` (zero when not held)."
  @spec exact(%{Date.t() => map()}, Date.t(), term()) :: rational()
  def exact(sampled, date, key),
    do: sampled |> Map.get(date, %{}) |> Map.get(key, {0, 1})

  # --- exact arithmetic ---------------------------------------------------------------

  @doc "A `Decimal` as an exact rational."
  @spec rational(Decimal.t()) :: rational()
  def rational(%Decimal{sign: sign, coef: coef, exp: exp}) when is_integer(coef) do
    if exp >= 0,
      do: {sign * coef * pow10(exp), 1},
      else: reduce(sign * coef, pow10(-exp))
  end

  @doc "The sum of two exact rationals."
  @spec add(rational(), rational()) :: rational()
  def add({a, b}, {c, d}), do: reduce(a * d + c * b, b * d)

  defp mult({a, b}, numerator, denominator), do: reduce(a * numerator, b * denominator)

  defp reduce(0, _denominator), do: {0, 1}

  defp reduce(numerator, denominator) do
    gcd = Integer.gcd(numerator, denominator)
    {div(numerator, gcd), div(denominator, gcd)}
  end

  defp pow10(n), do: Integer.pow(10, n)

  @doc """
  An exact rational as a `Decimal`, for a message: exact where it
  terminates within 12 places, rounded to 12 places otherwise.
  """
  @spec to_decimal(rational()) :: Decimal.t()
  def to_decimal({numerator, denominator}) do
    numerator
    |> Decimal.new()
    |> Decimal.div(Decimal.new(denominator))
    |> Decimal.round(12)
    |> Decimal.normalize()
  end

  # --- the cash side of a collapse ------------------------------------------------------

  @doc """
  Where a collapse moves a flow (ADR-0050 §16 invariant 9). A collapsed
  row's leg `delta` on the cash account `account_id` is no longer part of
  the running balance the account's next balance anchor states, so that
  anchor's residual — an external flow — changes by the leg, on the
  anchor's date. `anchors` are the account's balance anchors. Answers `[]`
  when no anchor follows the row in replay order or the leg is zero,
  otherwise one `:absorbed` change naming the account, the anchor, its
  date, the change and the collapsed row.
  """
  @spec absorbed(map(), term(), Decimal.t(), [map()]) :: [map()]
  def absorbed(row, account_id, delta, anchors) do
    key = Projection.replay_key(row)

    anchors
    |> Enum.filter(&(Projection.replay_key(&1) > key))
    |> Enum.min_by(&Projection.replay_key/1, fn -> nil end)
    |> absorbed_change(row, account_id, delta)
  end

  defp absorbed_change(nil, _row, _account_id, _delta), do: []

  defp absorbed_change(anchor, row, account_id, delta) do
    if Decimal.equal?(delta, @zero) do
      []
    else
      [
        %{
          kind: :absorbed,
          cash_account_id: account_id,
          transaction_id: anchor.id,
          date: anchor.date,
          change: delta,
          collapsed_transaction_id: row.id
        }
      ]
    end
  end

  @doc "The sum of `row`'s additive cash legs on `account_id` (zero when it has none)."
  @spec cash_delta(map(), term()) :: Decimal.t()
  def cash_delta(row, account_id) do
    for {^account_id, {:add, delta}} <- Projection.effects(row).cash, reduce: @zero do
      acc -> Decimal.add(acc, delta)
    end
  end

  @doc """
  The flows a collapse of `pairs` (`{source_row, target_row}`, the source
  row collapsed) moves into a set balance, for every cash account a
  collapsed row books on (`absorbed/4`), in the order of the pairs. `[]`
  without pairs.
  """
  @spec collapse_flow_changes([{map(), map()}]) :: [map()]
  def collapse_flow_changes([]), do: []

  def collapse_flow_changes(pairs) do
    ids =
      for {row, _target_row} <- pairs,
          {account_id, {:add, _delta}} <- Projection.effects(row).cash,
          account_id != nil,
          uniq: true,
          do: account_id

    anchors =
      Repo.all(
        from(t in Transaction,
          where: t.type == "balance_adjustment" and t.cash_account_id in ^ids
        )
      )
      |> Enum.group_by(& &1.cash_account_id)

    for {row, _target_row} <- pairs,
        account_id <- ids,
        change <-
          absorbed(row, account_id, cash_delta(row, account_id), anchors[account_id] || []),
        do: change
  end

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
