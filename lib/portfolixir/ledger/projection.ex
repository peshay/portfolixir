defmodule Portfolixir.Ledger.Projection do
  @moduledoc """
  The single per-kind reducer (ADR-0011): one canonical place stating what
  each booking kind does to the ledger's read models.

  `effects/1` maps a transaction to its effect — signed cash legs (or an
  absolute balance anchor, see ADR-0009), signed quantity legs, and whether
  the booking is an **external flow** for performance purposes (money or
  securities entering/leaving the portfolio, as opposed to internal movement
  or return). Cash balances, positions and the performance daily walk are
  generic folds over these effects; none of them dispatches on the kind.

  Adding a booking kind therefore means adding one `effects/1` clause here
  (plus its `Portfolixir.Ledger.Transaction` validation). A kind the
  projection has not been taught raises, so it cannot silently drift through
  one read model and not another.

  Deliberately *not* fed from here: the cost side of the read models. The
  holdings cost fold (`Portfolixir.Ledger` `cost_lots/1`) moves cost along
  the same quantity-bearing kinds but needs per-kind cost semantics this
  projection does not carry, and the FIFO trade matcher considers only the
  priced `buy`/`sell` kinds by definition. Held *quantities* everywhere
  (positions and the holdings views) do fold this projection's quantity
  legs.
  """

  @zero Decimal.new("0")

  # ADR-0028 §3: the one named exception to ADR-0016's no-intermediate-rounding
  # rule — a scale leg's resulting quantity quantizes once at volume scale 6.
  @volume_scale 6

  @typedoc """
  The canonical effect of one transaction.

    * `:cash` — `{cash_account_id, {:add, delta} | {:set, absolute}}` legs in
      the account's own currency. Stored amounts are positive magnitudes; the
      sign of a delta comes from the kind. `{:set, absolute}` anchors the
      account to a stated balance (a `balance_adjustment` snapshot).
    * `:quantities` — additive `{securities_account_id, security_id,
      signed_delta}` legs moving held shares, or the multiplicative
      `{:scale, %{portfolio_id: id, security_id: id, ratio: {p, q}}}` leg of
      a `split` (ADR-0028). The scale leg is deliberately a tagged shape,
      structurally distinct from the 3-tuple, so a fold that has not been
      taught it fails loudly instead of silently dropping it. It scales only
      the `{account, security}` positions of its own portfolio, from each
      fold's own pre-split state.
    * `:external` — whether the applied effects are external flows that a
      time-weighted return must neutralise.
  """
  @type scale_leg ::
          {:scale,
           %{portfolio_id: term(), security_id: term(), ratio: {pos_integer(), pos_integer()}}}
  @type effect :: %{
          cash: [{term(), {:add | :set, Decimal.t()}}],
          quantities: [{term(), term(), Decimal.t()} | scale_leg()],
          external: boolean()
        }

  @doc """
  The canonical effect of one transaction. Raises `FunctionClauseError` for a
  kind the projection has not been taught.
  """
  @spec effects(map()) :: effect()
  def effects(%{type: "deposit"} = tx),
    do: effect(cash: [{tx.cash_account_id, {:add, gross(tx)}}], external: true)

  def effects(%{type: "removal"} = tx),
    do: effect(cash: [{tx.cash_account_id, {:add, Decimal.negate(gross(tx))}}], external: true)

  def effects(%{type: type} = tx) when type in ["dividend", "interest", "tax_refund"],
    do: effect(cash: [{tx.cash_account_id, {:add, gross(tx)}}])

  def effects(%{type: type} = tx) when type in ["fee", "tax"],
    do: effect(cash: [{tx.cash_account_id, {:add, Decimal.negate(gross(tx))}}])

  def effects(%{type: "buy"} = tx) do
    effect(
      cash: [{tx.cash_account_id, {:add, Decimal.negate(buy_cost(tx))}}],
      quantities: [{tx.securities_account_id, tx.security_id, tx.quantity}]
    )
  end

  def effects(%{type: "sell"} = tx) do
    effect(
      cash: [{tx.cash_account_id, {:add, sell_proceeds(tx)}}],
      quantities: [{tx.securities_account_id, tx.security_id, Decimal.negate(tx.quantity)}]
    )
  end

  def effects(%{type: "cash_transfer"} = tx) do
    amount = gross(tx)

    effect(
      cash: [
        {tx.cash_account_id, {:add, Decimal.negate(amount)}},
        {tx.counter_cash_account_id, {:add, amount}}
      ]
    )
  end

  def effects(%{type: "inbound_delivery"} = tx) do
    effect(
      quantities: [{tx.securities_account_id, tx.security_id, tx.quantity}],
      external: true
    )
  end

  def effects(%{type: "outbound_delivery"} = tx) do
    effect(
      quantities: [{tx.securities_account_id, tx.security_id, Decimal.negate(tx.quantity)}],
      external: true
    )
  end

  def effects(%{type: "security_transfer"} = tx) do
    effect(
      quantities: [
        {tx.securities_account_id, tx.security_id, Decimal.negate(tx.quantity)},
        {tx.counter_securities_account_id, tx.security_id, tx.quantity}
      ]
    )
  end

  # The stated balance replaces the derived one as of its date (ADR-0009); the
  # residual jump is money that moved outside the recorded bookings.
  def effects(%{type: "balance_adjustment"} = tx),
    do: effect(cash: [{tx.cash_account_id, {:set, gross(tx)}}], external: true)

  # A split (ADR-0028) is a multiplicative quantity event: nothing enters or
  # leaves the portfolio (`external: false`), so TTWROR needs no flow
  # neutralisation. The tagged leg carries the row's portfolio because the
  # scale is scoped to it — a split row scales only its own portfolio's
  # positions of the security.
  def effects(%{type: "split"} = tx) do
    effect(
      quantities: [
        {:scale,
         %{
           portfolio_id: tx.portfolio_id,
           security_id: tx.security_id,
           ratio: {tx.split_ratio_numerator, tx.split_ratio_denominator}
         }}
      ]
    )
  end

  defp effect(parts), do: Map.merge(%{cash: [], quantities: [], external: false}, Map.new(parts))

  @doc """
  Replay order within one day: a split applies first (start-of-day, ADR-0028
  §3 — same-day trades are booked in post-split units), and a balance
  snapshot states the balance *including* the rest of its day, so it applies
  after the day's other bookings. Sort by `{intra_day_order(tx), tx.id}`
  within a day — or use `replay_sort/1` for the full chronological order.
  """
  @spec intra_day_order(map()) :: 0 | 1 | 2
  def intra_day_order(%{type: "split"}), do: 0
  def intra_day_order(%{type: "balance_adjustment"}), do: 2
  def intra_day_order(%{type: _other}), do: 1

  @doc """
  The shared chronological replay key, `{date, intra_day_order, id}`
  (ADR-0028 §3). Multiplicative legs do not commute with additive ones, so
  **every** fold over the projection's quantity or cash legs must replay in
  this order — sorting by `{date, id}` alone would apply a same-day split
  after the day's trades.
  """
  @spec replay_key(map()) :: {:calendar.date(), 0 | 1 | 2, term()}
  def replay_key(tx), do: {Date.to_erl(tx.date), intra_day_order(tx), Map.get(tx, :id, 0)}

  @doc "Sorts transactions by `replay_key/1`, oldest first."
  @spec replay_sort([map()]) :: [map()]
  def replay_sort(transactions) when is_list(transactions),
    do: Enum.sort_by(transactions, &replay_key/1)

  @doc """
  Applies a scale leg's ratio `{p, q}` to a held quantity: the result is
  `quantity * p / q`, quantized once at volume scale #{@volume_scale} — the
  narrow, named exception to ADR-0016 (ADR-0028 §3). Deterministic
  quantization at the fold lets a subsequent broker-stated sell (e.g.
  `3.333333` after `10 x 1:3`) zero the position exactly instead of leaving
  an undroppable dust row. Prices and cost totals keep full precision.
  """
  @spec scale_quantity(Decimal.t(), {pos_integer(), pos_integer()}) :: Decimal.t()
  def scale_quantity(%Decimal{} = quantity, {numerator, denominator}) do
    quantity
    |> Decimal.mult(numerator)
    |> Decimal.div(denominator)
    |> Decimal.round(@volume_scale)
  end

  @doc """
  `%{securities_account_id => portfolio_id}` derived from a transaction
  stream. Scale legs are scoped per portfolio while position folds key on
  `{account, security}`; every account was introduced to a fold by some
  transaction of its own portfolio (enforced by FK), so the stream itself
  carries the mapping.
  """
  @spec account_portfolios([map()]) :: %{term() => term()}
  def account_portfolios(transactions) when is_list(transactions) do
    Enum.reduce(transactions, %{}, fn tx, acc ->
      portfolio_id = Map.get(tx, :portfolio_id)

      acc
      |> put_account(Map.get(tx, :securities_account_id), portfolio_id)
      |> put_account(Map.get(tx, :counter_securities_account_id), portfolio_id)
    end)
  end

  defp put_account(acc, nil, _portfolio_id), do: acc
  defp put_account(acc, _account_id, nil), do: acc
  defp put_account(acc, account_id, portfolio_id), do: Map.put_new(acc, account_id, portfolio_id)

  @doc """
  Folds transactions into `%{cash_account_id => balance}`, each balance in
  its own account's currency. Transactions are replayed chronologically with
  snapshots last within their day; an `{:set, absolute}` leg replaces the
  account's balance, so only bookings after the latest snapshot adjust it and
  the latest snapshot wins. Legs without a cash account are skipped.
  """
  @spec cash_balances([map()]) :: %{term() => Decimal.t()}
  def cash_balances(transactions) when is_list(transactions) do
    transactions
    |> replay_sort()
    |> Enum.reduce(%{}, fn transaction, balances ->
      Enum.reduce(effects(transaction).cash, balances, &apply_cash_leg/2)
    end)
  end

  @doc """
  Folds transactions into the running balance of **one** cash account:
  `%{transaction_id => balance_after_that_transaction}`, in the account's own
  currency.

  This is `cash_balances/1` unrolled rather than a second arithmetic (#414): it
  replays the same `effects/1` legs in the same `replay_sort/1` order, so the
  last entry of the series equals the account's balance by construction, and a
  `balance_adjustment` snapshot resets the running figure exactly as it resets
  the balance.

  Two consequences a caller must not paper over. The series is keyed by
  transaction id, so a transaction that never touches the account is simply
  **absent** rather than carrying the previous row's figure — a repeated
  balance on an untouched row would read as "nothing happened here" when the
  truth is "this row is not this account's". And because it is a *running*
  figure, it must be computed over the account's whole history even when the
  surface shows a filtered slice; the balance after a booking does not depend
  on which rows are on screen.
  """
  @spec cash_balance_series([map()], term()) :: %{term() => Decimal.t()}
  def cash_balance_series(transactions, cash_account_id) when is_list(transactions) do
    transactions
    |> replay_sort()
    |> Enum.reduce({%{}, @zero}, fn transaction, {series, balance} ->
      case account_legs(effects(transaction).cash, cash_account_id) do
        [] ->
          {series, balance}

        legs ->
          balance = Enum.reduce(legs, balance, &apply_balance_leg/2)
          {Map.put(series, Map.get(transaction, :id), balance), balance}
      end
    end)
    |> elem(0)
  end

  defp account_legs(legs, cash_account_id),
    do: for({^cash_account_id, amount} <- legs, do: amount)

  defp apply_balance_leg({:add, delta}, balance), do: Decimal.add(balance, delta)
  defp apply_balance_leg({:set, absolute}, _balance), do: absolute

  defp apply_cash_leg({nil, _amount}, balances), do: balances

  defp apply_cash_leg({account_id, {:add, delta}}, balances),
    do: Map.update(balances, account_id, delta, &Decimal.add(&1, delta))

  defp apply_cash_leg({account_id, {:set, absolute}}, balances),
    do: Map.put(balances, account_id, absolute)

  defp gross(%{gross_amount: %Decimal{} = amount}), do: amount
  defp gross(_tx), do: @zero

  # A buy's `gross_amount` is inclusive of fees/taxes; a sell's is already net
  # of them. When it was not recorded, reconstruct from quantity * price.
  defp buy_cost(%{gross_amount: %Decimal{} = amount}), do: amount
  defp buy_cost(tx), do: tx.quantity |> Decimal.mult(tx.price) |> Decimal.add(fees_and_taxes(tx))

  defp sell_proceeds(%{gross_amount: %Decimal{} = amount}), do: amount

  defp sell_proceeds(tx),
    do: tx.quantity |> Decimal.mult(tx.price) |> Decimal.sub(fees_and_taxes(tx))

  defp fees_and_taxes(tx), do: Decimal.add(tx.fees || @zero, tx.taxes || @zero)
end
