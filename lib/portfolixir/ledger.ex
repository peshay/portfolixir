defmodule Portfolixir.Ledger do
  @moduledoc """
  Transaction ledger.

  Tracks the full set of Portfolio-Performance transaction kinds (see
  `Portfolixir.Ledger.Transaction.kinds/0`): manual `buy`/`sell` trades
  plus the cash-, dividend-, fee-, tax- and transfer-flavoured events
  required to ingest external exports.

  Holdings (`positions_for_portfolio/1`, `holdings_for_security/2`) and
  the FIFO trade matcher consider only the `buy`/`sell` kinds; the other
  kinds change cash balance or move shares without re-pricing existing
  lots.
  """

  import Ecto.Query

  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Ledger.Positions
  alias Portfolixir.Ledger.TradeMatcher
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios.SecuritiesAccount
  alias Portfolixir.Repo

  def list_transactions(opts \\ []) when is_list(opts) do
    ordered_transactions()
    |> filter_transactions(opts)
    |> preload([:security, :cash_account, :securities_account])
    |> Repo.all()
  end

  defp filter_transactions(query, opts) do
    query
    |> filter_transaction_eq(:portfolio_id, opts[:portfolio_id])
    |> filter_transaction_eq(:security_id, opts[:security_id])
    |> filter_transaction_from(opts[:from])
    |> filter_transaction_to(opts[:to])
  end

  defp filter_transaction_eq(query, _field, nil), do: query

  defp filter_transaction_eq(query, :portfolio_id, id),
    do: where(query, [t], t.portfolio_id == ^id)

  defp filter_transaction_eq(query, :security_id, id),
    do: where(query, [t], t.security_id == ^id)

  defp filter_transaction_from(query, nil), do: query
  defp filter_transaction_from(query, %Date{} = from), do: where(query, [t], t.date >= ^from)

  defp filter_transaction_to(query, nil), do: query
  defp filter_transaction_to(query, %Date{} = to), do: where(query, [t], t.date <= ^to)

  def list_transactions_for_portfolio(portfolio_id) when is_integer(portfolio_id) do
    Repo.all(
      from(transaction in ordered_transactions(),
        where: transaction.portfolio_id == ^portfolio_id,
        preload: [:security, :cash_account, :securities_account]
      )
    )
  end

  def list_transactions_for_security(security_id) when is_integer(security_id) do
    Repo.all(
      from(transaction in Transaction,
        where: transaction.security_id == ^security_id,
        order_by: [asc: transaction.date, asc: transaction.id],
        preload: [:portfolio, :securities_account, :cash_account]
      )
    )
  end

  @doc """
  Returns the current cash balance of each cash account, keyed by
  `cash_account_id`, derived on read from the stored transactions (balances are
  not persisted; see ADR-0004).

  Amounts are stored as positive magnitudes and the transaction `type` implies
  the direction of the cash flow. Each balance is in its own account's currency;
  no FX conversion is applied here. Pass `:portfolio_id` to scope the calculation
  to one portfolio. Accounts with no cash-affecting transaction are omitted and
  should be treated as a zero balance by callers.
  """
  def cash_balances(opts \\ []) when is_list(opts) do
    Transaction
    |> scope_portfolio(opts[:portfolio_id])
    |> Repo.all()
    |> Enum.reduce(%{}, fn transaction, balances ->
      transaction
      |> cash_effects()
      |> Enum.reduce(balances, fn {account_id, delta}, acc ->
        add_cash_delta(acc, account_id, delta)
      end)
    end)
  end

  defp scope_portfolio(query, nil), do: query

  defp scope_portfolio(query, portfolio_id) when is_integer(portfolio_id),
    do: where(query, [t], t.portfolio_id == ^portfolio_id)

  # Per-kind cash effects as `{cash_account_id, signed_delta}` tuples. Stored
  # amounts are positive magnitudes; the sign here comes from the kind.
  defp cash_effects(%Transaction{type: type} = t)
       when type in ["deposit", "dividend", "interest", "tax_refund"],
       do: [{t.cash_account_id, gross_amount(t)}]

  defp cash_effects(%Transaction{type: type} = t)
       when type in ["removal", "fee", "tax"],
       do: [{t.cash_account_id, Decimal.negate(gross_amount(t))}]

  defp cash_effects(%Transaction{type: "sell"} = t),
    do: [{t.cash_account_id, sell_proceeds(t)}]

  defp cash_effects(%Transaction{type: "buy"} = t),
    do: [{t.cash_account_id, Decimal.negate(buy_cost(t))}]

  defp cash_effects(%Transaction{type: "cash_transfer"} = t) do
    amount = gross_amount(t)
    [{t.cash_account_id, Decimal.negate(amount)}, {t.counter_cash_account_id, amount}]
  end

  # Deliveries and security transfers move shares, not cash.
  defp cash_effects(%Transaction{}), do: []

  defp add_cash_delta(balances, nil, _delta), do: balances

  defp add_cash_delta(balances, account_id, delta),
    do: Map.update(balances, account_id, delta, &Decimal.add(&1, delta))

  defp gross_amount(%Transaction{gross_amount: %Decimal{} = amount}), do: amount
  defp gross_amount(%Transaction{}), do: Decimal.new("0")

  # buy `gross_amount` is inclusive of fees/taxes; sell `gross_amount` is already
  # net of them. When it was not recorded, reconstruct from quantity*price.
  defp buy_cost(%Transaction{gross_amount: %Decimal{} = amount}), do: amount
  defp buy_cost(%Transaction{} = t), do: Decimal.add(base_amount(t), fees_and_taxes(t))

  defp sell_proceeds(%Transaction{gross_amount: %Decimal{} = amount}), do: amount
  defp sell_proceeds(%Transaction{} = t), do: Decimal.sub(base_amount(t), fees_and_taxes(t))

  defp base_amount(%Transaction{quantity: %Decimal{} = q, price: %Decimal{} = p}),
    do: Decimal.mult(q, p)

  defp base_amount(%Transaction{}), do: Decimal.new("0")

  defp fees_and_taxes(%Transaction{fees: fees, taxes: taxes}),
    do: Decimal.add(fees || Decimal.new("0"), taxes || Decimal.new("0"))

  @doc """
  Lists FIFO-matched trades for a security: closed round-trips, open
  remaining lots (with unrealised P&L vs. the latest known quote close),
  and any orphan sells.

  Pass `:latest_price` (Decimal) to inject the comparison price for
  tests; otherwise the function reads it from `Catalog.Quotes.latest/1`.
  """
  def list_trades_for_security(security_id, opts \\ []) when is_integer(security_id) do
    latest_price =
      Keyword.get_lazy(opts, :latest_price, fn ->
        case Quotes.latest(security_id) do
          %{close: close} -> close
          _ -> nil
        end
      end)

    transactions =
      security_id
      |> list_transactions_for_security()
      |> Enum.map(&transaction_for_matcher/1)

    result = TradeMatcher.match(transactions)

    %{
      result
      | open_lots: Enum.map(result.open_lots, &decorate_open_lot(&1, latest_price))
    }
  end

  @doc """
  Returns the current holdings of a single security, split by
  (portfolio, depot). Computes a moving-average cost basis from the
  chronological buy/sell stream within each grouping.

  Pass `:latest_price` to inject the comparison price for tests;
  otherwise reads it from `Catalog.Quotes.latest/1`.
  """
  def holdings_for_security(security_id, opts \\ []) when is_integer(security_id) do
    latest_price =
      Keyword.get_lazy(opts, :latest_price, fn ->
        case Quotes.latest(security_id) do
          %{close: close} -> close
          _ -> nil
        end
      end)

    security_id
    |> list_transactions_for_security()
    |> Enum.group_by(fn tx -> {tx.portfolio_id, tx.securities_account_id} end)
    |> Enum.map(fn {{_pid, _depot_id}, txs} ->
      summary = moving_average(txs)

      base_row = %{
        portfolio: List.first(txs).portfolio,
        depot: List.first(txs).securities_account,
        quantity: summary.quantity,
        avg_cost: summary.avg_cost
      }

      decorate_holding(base_row, latest_price)
    end)
    |> Enum.reject(&Decimal.equal?(&1.quantity, 0))
    |> Enum.sort_by(& &1.portfolio.name)
  end

  defp moving_average(transactions) do
    Enum.reduce(transactions, %{quantity: Decimal.new(0), avg_cost: Decimal.new(0)}, fn tx, acc ->
      case tx.type do
        "buy" ->
          new_qty = Decimal.add(acc.quantity, tx.quantity)

          new_avg =
            if Decimal.equal?(new_qty, 0) do
              Decimal.new(0)
            else
              numerator =
                Decimal.add(
                  Decimal.mult(acc.quantity, acc.avg_cost),
                  Decimal.mult(tx.quantity, tx.price)
                )

              Decimal.div(numerator, new_qty)
            end

          %{quantity: new_qty, avg_cost: new_avg}

        "sell" ->
          %{acc | quantity: Decimal.sub(acc.quantity, tx.quantity)}

        _ ->
          acc
      end
    end)
  end

  defp decorate_holding(row, nil) do
    Map.merge(row, %{
      latest_price: nil,
      current_value: nil,
      unrealized_pnl_abs: nil,
      unrealized_pnl_pct: nil
    })
  end

  defp decorate_holding(row, %Decimal{} = latest_price) do
    current_value = Decimal.mult(row.quantity, latest_price)
    cost = Decimal.mult(row.quantity, row.avg_cost)
    abs_pnl = Decimal.sub(current_value, cost)
    pct_pnl = if Decimal.equal?(cost, 0), do: Decimal.new(0), else: Decimal.div(abs_pnl, cost)

    Map.merge(row, %{
      latest_price: latest_price,
      current_value: current_value,
      unrealized_pnl_abs: abs_pnl,
      unrealized_pnl_pct: pct_pnl
    })
  end

  defp transaction_for_matcher(%Transaction{} = tx) do
    %{
      type: tx.type,
      date: tx.date,
      quantity: tx.quantity,
      price: tx.price,
      fees: tx.fees,
      taxes: tx.taxes,
      currency_code: tx.currency_code
    }
  end

  defp decorate_open_lot(lot, nil) do
    Map.merge(lot, %{
      latest_price: nil,
      unrealized_pnl_abs: nil,
      unrealized_pnl_pct: nil
    })
  end

  defp decorate_open_lot(lot, %Decimal{} = latest_price) do
    basis_per_unit = lot.buy_price
    current_value = Decimal.mult(lot.quantity, latest_price)
    cost = Decimal.mult(lot.quantity, basis_per_unit)
    abs_pnl = Decimal.sub(current_value, cost)
    pct_pnl = if Decimal.equal?(cost, 0), do: Decimal.new(0), else: Decimal.div(abs_pnl, cost)

    Map.merge(lot, %{
      latest_price: latest_price,
      unrealized_pnl_abs: abs_pnl,
      unrealized_pnl_pct: pct_pnl
    })
  end

  def count_transactions do
    Repo.aggregate(Transaction, :count, :id)
  end

  def create_transaction(attrs) when is_map(attrs) do
    with {:ok, attrs} <- maybe_derive_linked_cash_account(attrs) do
      %Transaction{}
      |> Transaction.changeset(attrs)
      |> Repo.insert()
    end
  end

  def get_transaction(id) when is_integer(id), do: Repo.get(Transaction, id)

  def update_transaction(%Transaction{} = transaction, attrs) when is_map(attrs) do
    transaction
    |> Transaction.changeset(attrs)
    |> Repo.update()
  end

  def delete_transaction(%Transaction{} = transaction), do: Repo.delete(transaction)

  defp maybe_derive_linked_cash_account(attrs) do
    case get_attr(attrs, :type) do
      type when type in ["buy", "sell"] -> derive_linked_cash_account(attrs)
      _other -> {:ok, attrs}
    end
  end

  def change_transaction(%Transaction{} = transaction, attrs \\ %{}) do
    Transaction.changeset(transaction, attrs)
  end

  def positions_for_portfolio(portfolio_id) when is_integer(portfolio_id) do
    portfolio_id
    |> list_transactions_for_portfolio()
    |> Positions.calculate()
  end

  defp ordered_transactions do
    from(transaction in Transaction,
      order_by: [desc: transaction.date, desc: transaction.id]
    )
  end

  defp derive_linked_cash_account(attrs) do
    with {:ok, securities_account_id} <- fetch_integer(attrs, :securities_account_id),
         %SecuritiesAccount{} = securities_account <-
           Repo.get(SecuritiesAccount, securities_account_id) do
      validate_selected_portfolio(attrs, securities_account)
    else
      :missing -> {:ok, attrs}
      :invalid -> {:ok, attrs}
      nil -> {:ok, attrs}
    end
  end

  defp validate_selected_portfolio(attrs, securities_account) do
    case fetch_integer(attrs, :portfolio_id) do
      {:ok, portfolio_id} when portfolio_id != securities_account.portfolio_id ->
        {:error,
         invalid_transaction(
           attrs,
           :securities_account_id,
           "must belong to the selected portfolio"
         )}

      _portfolio_ok ->
        validate_selected_cash_account(attrs, securities_account)
    end
  end

  defp validate_selected_cash_account(attrs, securities_account) do
    case fetch_integer(attrs, :cash_account_id) do
      {:ok, cash_account_id} when cash_account_id != securities_account.cash_account_id ->
        {:error, invalid_transaction(attrs, :cash_account_id, "must match the selected depot")}

      _missing_or_matching ->
        {:ok, put_attr(attrs, :cash_account_id, securities_account.cash_account_id)}
    end
  end

  defp invalid_transaction(attrs, field, message) do
    %Transaction{}
    |> Transaction.changeset(attrs)
    |> Ecto.Changeset.add_error(field, message)
    |> Map.put(:action, :insert)
  end

  defp fetch_integer(attrs, field) do
    value = get_attr(attrs, field)

    cond do
      is_integer(value) ->
        {:ok, value}

      is_binary(value) ->
        case Integer.parse(value) do
          {integer, ""} -> {:ok, integer}
          _invalid -> :invalid
        end

      is_nil(value) ->
        :missing

      true ->
        :invalid
    end
  end

  defp get_attr(attrs, field) do
    Map.get(attrs, field) || Map.get(attrs, Atom.to_string(field))
  end

  defp put_attr(attrs, field, value) do
    if Enum.any?(Map.keys(attrs), &is_binary/1) do
      Map.put(attrs, Atom.to_string(field), value)
    else
      Map.put(attrs, field, value)
    end
  end
end
