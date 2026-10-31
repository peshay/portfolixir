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

  **The cash compared is the cash booked** (E25 S6, F71). Without a
  `gross_amount` the projection books `quantity × price`, plus fees and taxes
  on a buy and less them on a sale (`Ledger.Projection`), so that is what
  the settlement is compared with. A trade priced in the security's currency
  and sent without its cash amount would otherwise book that currency's
  units as the account's cash. The error still lands on `gross_amount`: the
  remedy is recording the cash the broker settled. A row the settlement
  backfill or the Portfolio Performance import stored without a cash amount
  carries `quantity × price` as its settlement, so it meets the guard by
  construction.

  **A rate is not a cash amount** (security review 2026-10-12, H35; owner
  decision T-19). A trade booked in another currency than its cash
  account's that carries a `settlement_fx_rate` but neither a
  `gross_amount` nor a `settlement_amount` has nothing to compare, and the
  projection never applies the rate to the cash leg: it would book
  `quantity × price` in the booking currency as the account's cash. Such a
  trade is refused on `gross_amount` until it carries the cash the broker
  settled (`validate_rate_only/1`, run by the cash account's currency
  check); nothing is derived from the rate. `violations/0` lists a stored
  one against the cash its own rate implies.

  **Risk-tier (ADR-0036).** The guard is a ledger invariant. When it runs was
  fixed by the Sprint 15 plan's D-5 and widened by the ADR-0015 amendment of
  2026-10-09, point 1 (H35): on insert, and on an update that changes
  `gross_amount`, `settlement_amount`, `fees`, `taxes`, the type, the
  currency, the cash account or the depot — and, for a row without a cash
  amount, its quantity or price, which then change the cash booked (F71). A row that predates the guard is never revalidated
  behind the operator's back — editing its note must not start failing — and
  `violations/0` lists such rows read-only; repairing one is the operator's
  decision (NFR-2).
  """

  import Ecto.Changeset, only: [get_field: 2, add_error: 4, changed?: 2]
  import Ecto.Query, only: [from: 2]

  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Repo

  @tolerance Decimal.new("0.01")
  @guarded_types ["buy", "sell"]
  # The currency, the cash account and the depot decide whether a trade is
  # cross-currency at all (the ADR-0015 amendment of 2026-10-09, point 1; H35).
  @trigger_fields [
    :gross_amount,
    :settlement_amount,
    :fees,
    :taxes,
    :type,
    :currency_code,
    :cash_account_id,
    :securities_account_id
  ]
  # Without a cash amount the booked cash follows these as well (F71).
  @fallback_trigger_fields [:quantity, :price]

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
  The guard's relation inverted: the trade amount in the account currency a
  cash amount implies — `gross - fees - taxes` for a buy, `gross + fees +
  taxes` for a sell — or `nil` without a cash amount or for another kind.

  Where a row is derived rather than typed (the Portfolio Performance import,
  the settlement backfill), the cash amount is the figure the broker settled
  and the per-share price a rounded display, so the settlement leg is read off
  the cash: the row then meets the guard by construction.
  """
  @spec trade_amount(String.t(), Decimal.t() | nil, Decimal.t() | nil, Decimal.t() | nil) ::
          Decimal.t() | nil
  def trade_amount("buy", %Decimal{} = gross, fees, taxes),
    do: gross |> Decimal.sub(zero(fees)) |> Decimal.sub(zero(taxes))

  def trade_amount("sell", %Decimal{} = gross, fees, taxes),
    do: gross |> Decimal.add(zero(fees)) |> Decimal.add(zero(taxes))

  def trade_amount(_type, _gross, _fees, _taxes), do: nil

  @doc """
  The cash the projection books for a trade (F71): `gross_amount` where it
  is recorded, else `quantity × price` plus fees and taxes on a buy and less
  them on a sale — `Ledger.Projection`'s own fallback — or `nil` for another
  kind or without the figures. Exact: nothing is rounded.
  """
  @spec booked_cash(String.t(), map()) :: Decimal.t() | nil
  def booked_cash(type, %{gross_amount: %Decimal{} = gross}) when type in @guarded_types,
    do: gross

  def booked_cash(type, %{quantity: %Decimal{} = quantity, price: %Decimal{} = price} = row)
      when type in @guarded_types,
      do: expected_cash(type, Decimal.mult(quantity, price), row.fees, row.taxes)

  def booked_cash(_type, _row), do: nil

  @doc """
  The changeset step (D-5, widened by the ADR-0015 amendment of 2026-10-09):
  checks a cross-currency buy or sell on insert and on an update that changes
  an amount, the type, the currency, the cash account or the depot; leaves
  every other write alone. The error lands on `gross_amount` and names the implied amount —
  nothing is corrected silently.
  """
  @spec validate(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def validate(%Ecto.Changeset{} = changeset) do
    if runs?(changeset), do: check(changeset), else: changeset
  end

  @doc """
  The rate-only step (H35, T-19): a buy or sell booked in another currency
  than its cash account's that carries a `settlement_fx_rate` but neither a
  `gross_amount` nor a `settlement_amount` is refused on `gross_amount`,
  the message naming the cash `quantity × price` with fees and taxes would
  book. It runs when `validate/1` runs (its triggers), and only where the caller has
  found the currencies to differ — `Transaction.validate_cash_account_currency/2`,
  which alone knows the account's currency — so a trade booked in its
  account's currency with a rate stored beside it is left alone.
  """
  @spec validate_rate_only(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def validate_rate_only(%Ecto.Changeset{} = changeset) do
    type = get_field(changeset, :type)
    row = figures(changeset)

    if runs?(changeset) and
         rate_only?(
           type,
           get_field(changeset, :settlement_amount),
           row,
           get_field(changeset, :settlement_fx_rate)
         ),
       do: refuse_rate_only(changeset, type, row),
       else: changeset
  end

  defp rate_only?(type, nil, %{gross_amount: nil}, %Decimal{}) when type in @guarded_types,
    do: true

  defp rate_only?(_type, _settlement, _row, _rate), do: false

  defp refuse_rate_only(changeset, type, row) do
    case booked_cash(type, row) do
      %Decimal{} = booked ->
        add_error(changeset, :gross_amount, rate_only_message(type),
          booked: display(booked),
          validation: :settlement_guard
        )

      nil ->
        add_error(changeset, :gross_amount, rate_only_message(nil), validation: :settlement_guard)
    end
  end

  defp runs?(%Ecto.Changeset{data: %{__meta__: %{state: :built}}}), do: true

  defp runs?(changeset) do
    Enum.any?(@trigger_fields, &changed?(changeset, &1)) or
      (is_nil(get_field(changeset, :gross_amount)) and
         Enum.any?(@fallback_trigger_fields, &changed?(changeset, &1)))
  end

  defp check(changeset) do
    type = get_field(changeset, :type)
    settlement = get_field(changeset, :settlement_amount)
    row = figures(changeset)

    with true <- type in @guarded_types,
         %Decimal{} <- settlement,
         %Decimal{} = booked <- booked_cash(type, row),
         expected = expected_cash(type, settlement, row.fees, row.taxes),
         false <- within?(booked, expected) do
      add_error(changeset, :gross_amount, message(type, row.gross_amount),
        expected: display(expected),
        booked: display(booked),
        tolerance: display(@tolerance),
        validation: :settlement_guard
      )
    else
      _in_agreement_or_not_guarded -> changeset
    end
  end

  defp figures(changeset) do
    Map.new([:gross_amount, :quantity, :price, :fees, :taxes], &{&1, get_field(changeset, &1)})
  end

  defp message("buy", %Decimal{}),
    do:
      "must equal the settlement amount plus fees and taxes (%{expected}), " <>
        "within %{tolerance}"

  defp message("sell", %Decimal{}),
    do:
      "must equal the settlement amount less fees and taxes (%{expected}), " <>
        "within %{tolerance}"

  # No cash amount: the cash booked is quantity × price with fees and taxes.
  defp message("buy", nil),
    do:
      "is missing, so quantity × price plus fees and taxes (%{booked}) would be booked; " <>
        "it must equal the settlement amount plus fees and taxes (%{expected}), " <>
        "within %{tolerance}"

  defp message("sell", nil),
    do:
      "is missing, so quantity × price less fees and taxes (%{booked}) would be booked; " <>
        "it must equal the settlement amount less fees and taxes (%{expected}), " <>
        "within %{tolerance}"

  defp rate_only_message("buy"),
    do:
      "is required for a cross-currency trade without a settlement amount: " <>
        "quantity × price plus fees and taxes (%{booked}) would be booked in the " <>
        "security's currency as the account's cash; record the cash the broker settled"

  defp rate_only_message("sell"),
    do:
      "is required for a cross-currency trade without a settlement amount: " <>
        "quantity × price less fees and taxes (%{booked}) would be booked in the " <>
        "security's currency as the account's cash; record the cash the broker settled"

  defp rate_only_message(nil),
    do:
      "is required for a cross-currency trade without a settlement amount; " <>
        "record the cash the broker settled"

  defp within?(gross, expected) do
    gross |> Decimal.sub(expected) |> Decimal.abs() |> Decimal.compare(@tolerance) != :gt
  end

  @doc """
  The stored cross-currency trades that miss the guard — read-only, rows
  listed and never rewritten. Each carries the stored figures, the cash the
  projection books for it (`booked_cash`: the gross amount, or quantity ×
  price with fees and taxes where none is recorded — F71), the cash amount
  the settlement implies and the difference (`booked - expected`).

  A stored trade with a rate and neither amount (H35), booked in another
  currency than its cash account's, is listed too: its settlement is read
  as `quantity × price × settlement_fx_rate`, the cash its own rate implies,
  so the listing shows by how much the cash booked misses it. The listing
  keeps the cash-difference filter for every row, so a rate-only row whose
  implied cash lies within a cent of the cash booked is not listed; the money
  it misses is under a cent (#1290 lists the rows unconditionally on a
  surface of their own).
  """
  @spec violations() :: [map()]
  def violations do
    from(t in Transaction,
      left_join: c in CashAccount,
      on: c.id == t.cash_account_id,
      where:
        t.type in ^@guarded_types and
          (not is_nil(t.settlement_amount) or
             (not is_nil(t.settlement_fx_rate) and is_nil(t.gross_amount) and
                t.currency_code != c.currency_code)),
      order_by: [t.date, t.id],
      select:
        map(t, [
          :id,
          :portfolio_id,
          :date,
          :type,
          :gross_amount,
          :quantity,
          :price,
          :settlement_amount,
          :settlement_fx_rate,
          :fees,
          :taxes
        ])
    )
    |> Repo.all()
    |> Enum.flat_map(fn row ->
      booked = booked_cash(row.type, row)
      expected = expected_cash(row.type, stored_settlement(row), row.fees, row.taxes)

      if is_nil(booked) or within?(booked, expected) do
        []
      else
        [
          Map.merge(row, %{
            booked_cash: booked,
            expected_cash: expected,
            difference: Decimal.sub(booked, expected)
          })
        ]
      end
    end)
  end

  defp stored_settlement(%{settlement_amount: %Decimal{} = settlement}), do: settlement

  defp stored_settlement(%{quantity: quantity, price: price, settlement_fx_rate: rate}),
    do: quantity |> Decimal.mult(price) |> Decimal.mult(rate)

  defp zero(nil), do: Decimal.new(0)
  defp zero(%Decimal{} = value), do: value

  defp display(value), do: value |> Decimal.normalize() |> Decimal.to_string(:normal)
end
