defmodule Portfolixir.Ledger.SettlementGuard do
  @moduledoc """
  The cross-currency settlement guard (#395, owner decision 2026-07-19;
  ADR-0015, ADR-0016): the cash a trade moves agrees with the settlement it
  records.

  A cross-currency buy or sell (ADR-0015) stores the cash leg twice over: as
  `gross_amount`, which the cash projection moves, and as `settlement_amount`,
  the trade value in the account currency, which the settlement-leg cost basis
  reads. Nothing tied the two together, so a typo in either left the cash
  balance and the cost basis telling two different stories. The relation:

    * a **buy's** `gross_amount` is inclusive of fees and taxes
      (`Ledger.Projection`), so it equals `settlement + fees + taxes`;
    * a **sell's** is already net of them, so it equals
      `settlement - fees - taxes`.

  Fees and taxes are read in the account currency, the currency of the cash
  leg they are part of. The comparison runs at full precision (ADR-0016 §5)
  and accepts a difference of at most one minor unit at the money scale
  (ADR-0016 §4, 0.01): a broker rounds each figure to the cent on its
  statement, and three cent-rounded figures can disagree with their exact sum
  by that much and no more.

  **Risk-tier (ADR-0036).** The guard is a ledger invariant. When it runs is
  fixed by the Sprint 15 plan's D-5: on insert, and on an update that changes
  `gross_amount`, `settlement_amount`, `fees`, `taxes` or the type. A row that
  predates the guard is never revalidated behind the operator's back — editing
  its note must not start failing — and `violations/0` lists such rows
  read-only; repairing one is the operator's decision (NFR-2).
  """

  import Ecto.Changeset, only: [get_field: 2, add_error: 4, changed?: 2]
  import Ecto.Query, only: [from: 2]

  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo

  @tolerance Decimal.new("0.01")
  @guarded_types ["buy", "sell"]
  @trigger_fields [:gross_amount, :settlement_amount, :fees, :taxes, :type]

  @doc "The accepted difference: one minor unit at ADR-0016's money scale."
  @spec tolerance() :: Decimal.t()
  def tolerance, do: @tolerance

  @doc """
  The cash amount a trade's settlement implies — `nil` for a kind the guard
  does not cover. Exact: nothing is rounded.
  """
  @spec expected_cash(String.t(), Decimal.t(), Decimal.t() | nil, Decimal.t() | nil) ::
          Decimal.t() | nil
  def expected_cash("buy", settlement, fees, taxes),
    do: settlement |> Decimal.add(zero(fees)) |> Decimal.add(zero(taxes))

  def expected_cash("sell", settlement, fees, taxes),
    do: settlement |> Decimal.sub(zero(fees)) |> Decimal.sub(zero(taxes))

  def expected_cash(_type, _settlement, _fees, _taxes), do: nil

  @doc """
  The changeset step (D-5): checks a cross-currency buy or sell on insert and
  on an update that changes an amount or the type; leaves every other write
  alone. The error lands on `gross_amount` and names the implied amount —
  nothing is corrected silently.
  """
  @spec validate(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def validate(%Ecto.Changeset{} = changeset) do
    if runs?(changeset), do: check(changeset), else: changeset
  end

  defp runs?(%Ecto.Changeset{data: %{__meta__: %{state: :built}}}), do: true
  defp runs?(changeset), do: Enum.any?(@trigger_fields, &changed?(changeset, &1))

  defp check(changeset) do
    type = get_field(changeset, :type)
    gross = get_field(changeset, :gross_amount)
    settlement = get_field(changeset, :settlement_amount)

    with true <- type in @guarded_types,
         %Decimal{} <- gross,
         %Decimal{} <- settlement,
         expected = expected_cash(type, settlement, fees(changeset), taxes(changeset)),
         false <- within?(gross, expected) do
      add_error(changeset, :gross_amount, message(type),
        expected: display(expected),
        tolerance: display(@tolerance),
        validation: :settlement_guard
      )
    else
      _in_agreement_or_not_guarded -> changeset
    end
  end

  defp fees(changeset), do: get_field(changeset, :fees)
  defp taxes(changeset), do: get_field(changeset, :taxes)

  defp message("buy"),
    do:
      "must equal the settlement amount plus fees and taxes (%{expected}), " <>
        "within %{tolerance}"

  defp message("sell"),
    do:
      "must equal the settlement amount less fees and taxes (%{expected}), " <>
        "within %{tolerance}"

  defp within?(gross, expected) do
    gross |> Decimal.sub(expected) |> Decimal.abs() |> Decimal.compare(@tolerance) != :gt
  end

  @doc """
  The stored cross-currency trades that miss the guard — read-only, rows
  listed and never rewritten. Each carries the stored figures, the cash
  amount the settlement implies and the difference (`gross - expected`).
  """
  @spec violations() :: [map()]
  def violations do
    from(t in Transaction,
      where:
        t.type in ^@guarded_types and not is_nil(t.settlement_amount) and
          not is_nil(t.gross_amount),
      order_by: [t.date, t.id],
      select:
        map(t, [
          :id,
          :portfolio_id,
          :date,
          :type,
          :gross_amount,
          :settlement_amount,
          :fees,
          :taxes
        ])
    )
    |> Repo.all()
    |> Enum.flat_map(fn row ->
      expected = expected_cash(row.type, row.settlement_amount, row.fees, row.taxes)

      if within?(row.gross_amount, expected) do
        []
      else
        [
          Map.merge(row, %{
            expected_cash: expected,
            difference: Decimal.sub(row.gross_amount, expected)
          })
        ]
      end
    end)
  end

  defp zero(nil), do: Decimal.new(0)
  defp zero(%Decimal{} = value), do: value

  defp display(value), do: value |> Decimal.normalize() |> Decimal.to_string(:normal)
end
