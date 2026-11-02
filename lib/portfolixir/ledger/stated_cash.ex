defmodule Portfolixir.Ledger.StatedCash do
  @moduledoc """
  An edit of a trade's figures states its cash (ADR-0053, amendment of
  2026-11-02, #1371).

  A buy or a sell that stores a cash amount (`gross_amount`) and no
  settlement legs is read two ways: the cash projection and the holding's
  cost read the stored cash, the FIFO lots read `quantity × price` with the
  fees and taxes. ADR-0053 §2 keeps the two together at import, to the cent.
  This module keeps them together on every later write:

    * an update that changes the **quantity, the price, the fees or the
      taxes** of such a row must state `gross_amount` too, or it is refused
      on `gross_amount`; the stored cash is the broker's figure, so it is
      never re-derived behind the operator's back (answer (b));
    * the stated cash must agree with the new figures **to the cent**:
      `quantity × price + fees + taxes` on a buy, `− fees − taxes` on a sell
      (`SettlementGuard.expected_cash/4`, the relation the settlement guard
      and the projection's own fallback use), within
      `SettlementGuard.tolerance/0`;
    * an update that changes none of the four (a note, a date, an account)
      needs no cash and keeps it, even on a row whose cash already misses
      its figures: such a row is never revalidated behind the operator's
      back.

  A row with a settlement amount is ADR-0015's: the settlement guard already
  relates its legs and its cash, so it is left to it, and so is an update
  that gives a row its legs. A cross-currency row stored without its legs
  (ADR-0015, amendment of 2026-11-01) follows this rule in the currency it
  is stored in; no exchange rate enters the relation.

  **Risk tier (ADR-0036):** how a stored booking is corrected. Nothing here
  rewrites a stored row.
  """

  import Ecto.Changeset, only: [get_field: 2, add_error: 4, changed?: 2]

  alias Portfolixir.Ledger.SettlementGuard
  alias Portfolixir.Ledger.Transaction

  @trade_types ["buy", "sell"]
  @figure_fields [:quantity, :price, :fees, :taxes]

  @required_message "is required when quantity, price, fees or taxes change on a booking " <>
                      "that stores its cash"
  @mismatch_message "does not match quantity × price, fees and taxes — expected %{expected}"

  @doc "The four fields whose change requires the cash to be stated."
  @spec figure_fields() :: [atom()]
  def figure_fields, do: @figure_fields

  @doc """
  Whether a stored booking falls under the rule: a buy or a sell that stores
  its cash and no settlement amount.
  """
  @spec applies?(Transaction.t() | map()) :: boolean()
  def applies?(%{type: type, gross_amount: %Decimal{}, settlement_amount: nil})
      when type in @trade_types,
      do: true

  def applies?(_row), do: false

  @doc """
  The cash `quantity × price` with the fees and taxes gives: plus them on a
  buy, less them on a sell. Exact, nothing rounded; `nil` for another kind
  or without a quantity and a price.
  """
  @spec derived_cash(String.t(), Decimal.t() | nil, Decimal.t() | nil, term(), term()) ::
          Decimal.t() | nil
  def derived_cash(type, %Decimal{} = quantity, %Decimal{} = price, fees, taxes)
      when type in @trade_types,
      do: SettlementGuard.expected_cash(type, Decimal.mult(quantity, price), fees, taxes)

  def derived_cash(_type, _quantity, _price, _fees, _taxes), do: nil

  @doc "Whether `cash` lies within one cent of `derived` (ADR-0016 §4)."
  @spec within_a_cent?(Decimal.t(), Decimal.t()) :: boolean()
  def within_a_cent?(%Decimal{} = cash, %Decimal{} = derived) do
    cash
    |> Decimal.sub(derived)
    |> Decimal.abs()
    |> Decimal.compare(SettlementGuard.tolerance()) != :gt
  end

  @doc """
  The update step: `changeset` is an update of a stored row built from
  `attrs`, the caller's attributes, which alone tell whether the cash was
  stated (a stated cash equal to the stored one is no change). Refuses on
  `gross_amount` an update of the four figures of a row the rule covers
  that states no cash, or states one the new figures miss by more than a
  cent; leaves every other write alone.
  """
  @spec validate(Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def validate(%Ecto.Changeset{data: %Transaction{} = stored} = changeset, attrs)
      when is_map(attrs) do
    if applies?(stored) and is_nil(get_field(changeset, :settlement_amount)) and
         Enum.any?(@figure_fields, &changed?(changeset, &1)),
       do: check(changeset, stated?(attrs)),
       else: changeset
  end

  defp stated?(attrs),
    do: Map.has_key?(attrs, :gross_amount) or Map.has_key?(attrs, "gross_amount")

  defp check(changeset, stated?) do
    cash = get_field(changeset, :gross_amount)

    cond do
      not stated? or is_nil(cash) ->
        add_error(changeset, :gross_amount, @required_message, validation: :stated_cash)

      changeset.errors[:gross_amount] ->
        changeset

      true ->
        check_agreement(changeset, cash)
    end
  end

  defp check_agreement(changeset, cash) do
    derived =
      derived_cash(
        get_field(changeset, :type),
        get_field(changeset, :quantity),
        get_field(changeset, :price),
        get_field(changeset, :fees),
        get_field(changeset, :taxes)
      )

    if is_nil(derived) or within_a_cent?(cash, derived) do
      changeset
    else
      add_error(changeset, :gross_amount, @mismatch_message,
        expected: Decimal.round(derived, 2),
        validation: :stated_cash
      )
    end
  end
end
