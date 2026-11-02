defmodule Portfolixir.Ledger.StatedCash do
  @moduledoc """
  An edit of a trade's figures states its cash (ADR-0053, amendment of
  2026-11-02, #1371).

  A buy or a sell that stores a cash amount (`gross_amount`) and no
  settlement legs is read two ways: the cash projection reads the stored
  cash, the FIFO lots (and the holding's cost, quantity × price) read the
  figures. ADR-0053 §2 keeps the two together at import, to the cent. This
  module keeps them together on every later write:

    * an update that changes the **quantity, the price, the fees or the
      taxes** of such a row, or turns a buy into a sell or back (the
      relation's sign flips), must state `gross_amount` too, or it is
      refused on `gross_amount`; the stored cash is the broker's figure, so
      it is never re-derived behind the operator's back (answer (b));
    * the stated cash must agree with the new figures **to the cent, as §2
      asks of an imported row**: `quantity × price + fees + taxes` on a
      buy, `− fees − taxes` on a sell (`SettlementGuard.expected_cash/4`),
      both sides rounded to two places as §2 rounds them, within
      `tolerance/2`: a cent, plus the stored price's own rounding (below)
      while the edit leaves the price as stored; a price the edit sets is
      exact, so its tolerance is the cent alone;
    * an update that states a cash alone, different from the stored one,
      is checked against the stored figures the same way: the row keeps
      the relation on every write (the amendment's point 1);
    * an update that changes none of these (a note, a date, an account)
      needs no cash and keeps it, even on a row whose cash already misses
      its figures: such a row is listed by `report/0`, never revalidated
      behind the operator's back.

  **The price's own rounding.** An imported price is a rounded figure: a
  Portfolio Performance CSV row stores its Kurs cell as written (two to four
  places, the display of Betrag ÷ Stück), a JSON row its cash net of fees
  and taxes ÷ shares rounded half up to the price column's six places. §2
  never relates quantity × price to the cash, so a row that passed it misses
  quantity × price ± fees and taxes by up to its quantity × half a unit of
  the price's last digit: 7 at 14.29 for a Betrag of 100.00 by 0.03, 1,234
  at 12.3457 for 15,234.56 by 0.0338, 123,456.789 at 8.099960 by 0.047.
  The stored price keeps no trace of how many places were written, so the
  last digit is read off the price as stored, its trailing zeros dropped,
  at two places at least (Portfolio Performance writes a Kurs to at least
  two) and six at most (the column's scale).

  `report/0` keeps that allowance for every stored price, so an untouched
  import is never listed; an edit allows it only for the price it leaves
  as stored, since a price the operator types carries no rounding of its
  own (100,000 shares re-priced to 0.10 would otherwise allow 500.01).

  A row with a settlement amount is ADR-0015's: the settlement guard already
  relates its legs and its cash, so it is left to it, and so is an update
  that gives a row its legs. A cross-currency row stored without its legs
  (ADR-0015, amendment of 2026-11-01) follows this rule in the currency it
  is stored in; no exchange rate enters the relation.

  **Risk tier (ADR-0036):** how a stored booking is corrected. Nothing here
  rewrites a stored row; `report/0` is read-only.
  """

  import Ecto.Changeset, only: [get_field: 2, add_error: 4, changed?: 2]
  import Ecto.Query, only: [from: 2]

  alias Portfolixir.Clock
  alias Portfolixir.Ledger.SettlementGuard
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo

  @trade_types ["buy", "sell"]
  @figure_fields [:quantity, :price, :fees, :taxes]

  @required_message "is required when quantity, price, fees, taxes or buy/sell change on a " <>
                      "booking that stores its cash"
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

  @doc """
  The difference a stated cash may show against the cash `quantity` at
  `price` derives: one cent (ADR-0016 §4) plus |quantity| × half a unit of
  the price's last digit, read at two to six places (the moduledoc's "The
  price's own rounding"). 10 at 81.00: 0.01 + 10 × 0.005 = 0.06.
  """
  @spec tolerance(Decimal.t(), Decimal.t()) :: Decimal.t()
  def tolerance(%Decimal{} = quantity, %Decimal{} = price) do
    quantity
    |> Decimal.abs()
    |> Decimal.mult(half_unit(price))
    |> Decimal.add(SettlementGuard.tolerance())
  end

  defp half_unit(price) do
    %Decimal{exp: exp} = Decimal.normalize(price)
    places = exp |> min(-2) |> max(-6)
    Decimal.new(1, 5, places - 1)
  end

  @doc """
  Whether `cash` agrees with `derived`, the cash `quantity` at `price` gives:
  both rounded to two places, as ADR-0053 §2 compares an imported row's
  readings, and apart by no more than `tolerance/2`.
  """
  @spec agrees?(Decimal.t(), Decimal.t(), Decimal.t(), Decimal.t()) :: boolean()
  def agrees?(%Decimal{} = cash, %Decimal{} = derived, quantity, price),
    do: within?(cash, derived, tolerance(quantity, price))

  defp within?(cash, derived, tolerance) do
    cash
    |> Decimal.round(2)
    |> Decimal.sub(Decimal.round(derived, 2))
    |> Decimal.abs()
    |> Decimal.compare(tolerance) != :gt
  end

  # An edit's tolerance: the stored price keeps its own rounding, a price
  # the edit sets is exact, so the cent alone (the sprint PR's closing act:
  # 100,000 at 0.10 would otherwise allow 500.01).
  defp edit_tolerance(changeset) do
    if changed?(changeset, :price),
      do: SettlementGuard.tolerance(),
      else: tolerance(get_field(changeset, :quantity), get_field(changeset, :price))
  end

  @doc """
  The update step: `changeset` is an update of a stored row built from
  `attrs`, the caller's attributes, which alone tell whether the cash was
  stated (a stated cash equal to the stored one is no change). Refuses on
  `gross_amount` an update of the four figures, or of the type between buy
  and sell, of a row the rule covers that states no cash, or states one the
  new figures do not agree with (`agrees?/4`, the cent alone when the edit
  sets the price), and a cash stated alone the stored figures do not agree
  with; leaves every other write alone.
  """
  @spec validate(Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def validate(%Ecto.Changeset{data: %Transaction{} = stored} = changeset, attrs)
      when is_map(attrs) do
    if applies?(stored) and is_nil(get_field(changeset, :settlement_amount)) and
         triggered?(changeset),
       do: check(changeset, stated?(attrs)),
       else: changeset
  end

  # The four figures, a buy turned into a sell or back (the relation's sign
  # flips), and a cash stated alone: the amendment's point 1, the row
  # "keeps the §2 relation on every write".
  defp triggered?(changeset) do
    Enum.any?(@figure_fields, &changed?(changeset, &1)) or
      (changed?(changeset, :type) and get_field(changeset, :type) in @trade_types) or
      (changed?(changeset, :gross_amount) and not is_nil(get_field(changeset, :gross_amount)))
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

    if is_nil(derived) or
         within?(cash, derived, edit_tolerance(changeset)) do
      changeset
    else
      add_error(changeset, :gross_amount, @mismatch_message,
        expected: Decimal.round(derived, 2),
        validation: :stated_cash
      )
    end
  end

  @doc """
  The stored buys and sells whose cash misses their figures (#1371;
  ADR-0053, amendment of 2026-11-02, point 4), read-only: every row the
  rule covers (a stored cash, no settlement amount) whose `gross_amount`
  does not agree (`agrees?/4`) with `quantity × price` plus fees and taxes
  on a buy, less them on a sale. A row edited before the rule keeps its
  figures here until the operator states the cash; an imported row that
  passed §2 is not listed, whatever its price's rounding.

  Returns `%{as_of, note, remedy, tolerance_rule, rows}`. Each row carries
  the stored figures, the security's name, the cash account, `stored_cash`
  (the `gross_amount` the cash projection reads), `derived_cash` (what the
  figures give, the lots' reading), `difference` (`stored_cash -
  derived_cash`) and the row's `tolerance` (`tolerance/2`), all exact
  Decimals; ordered by date, then id. Nothing is rewritten.
  """
  @spec report() :: %{
          as_of: Date.t(),
          note: String.t(),
          remedy: String.t(),
          tolerance_rule: String.t(),
          rows: [map()]
        }
  def report do
    rows =
      from(t in Transaction,
        left_join: s in assoc(t, :security),
        where:
          t.type in ^@trade_types and not is_nil(t.gross_amount) and
            is_nil(t.settlement_amount),
        order_by: [t.date, t.id],
        select: %{
          id: t.id,
          portfolio_id: t.portfolio_id,
          security_id: t.security_id,
          security_name: s.name,
          cash_account_id: t.cash_account_id,
          date: t.date,
          type: t.type,
          currency_code: t.currency_code,
          quantity: t.quantity,
          price: t.price,
          fees: t.fees,
          taxes: t.taxes,
          gross_amount: t.gross_amount
        }
      )
      |> Repo.all()
      |> Enum.flat_map(&mismatch_row/1)

    %{
      as_of: Clock.today(),
      note:
        "Stored buys and sells whose cash amount (gross_amount) misses quantity × price " <>
          "plus fees and taxes on a buy, less them on a sale, by more than its tolerance: " <>
          "the cash balance reads the stored cash, the FIFO lots, realized gains and the " <>
          "holding's cost read the figures, so they read different amounts. Trades with a " <>
          "settlement amount are the settlement check's.",
      remedy:
        "State the cash in the booking form (Edit) or as gross_amount with PATCH " <>
          "/api/v1/transactions/:id: the amount settled, or the one the figures give. " <>
          "Nothing is changed automatically.",
      tolerance_rule:
        "Both sides rounded to two places, as ADR-0053 §2 compares an imported row; a " <>
          "row is listed when they differ by more than 0.01 plus |quantity| × half a unit " <>
          "of the price's last digit (read at two to six places), the price's own rounding " <>
          "at import. An edit allows that rounding only for a price it leaves as stored; a " <>
          "price it sets is checked to the cent.",
      rows: rows
    }
  end

  # A stored buy or sell always carries its quantity and price (the
  # transactions_buy_sell_required_fields_check constraint).
  defp mismatch_row(row) do
    derived = derived_cash(row.type, row.quantity, row.price, row.fees, row.taxes)

    if is_nil(derived) or agrees?(row.gross_amount, derived, row.quantity, row.price) do
      []
    else
      {stored, row} = Map.pop!(row, :gross_amount)

      [
        Map.merge(row, %{
          stored_cash: stored,
          derived_cash: derived,
          difference: Decimal.sub(stored, derived),
          tolerance: tolerance(row.quantity, row.price)
        })
      ]
    end
  end
end
