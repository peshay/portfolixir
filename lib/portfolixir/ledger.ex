defmodule Portfolixir.Ledger do
  @moduledoc """
  Transaction ledger.

  Tracks the full set of Portfolio-Performance transaction kinds (see
  `Portfolixir.Ledger.Transaction.kinds/0`): manual `buy`/`sell` trades
  plus the cash-, dividend-, fee-, tax- and transfer-flavoured events
  required to ingest external exports.

  Position quantities (`positions_for_portfolio/1`) move with trades,
  deliveries and security transfers; the moving-average holdings view and
  the FIFO trade matcher consider only the priced `buy`/`sell` kinds — the
  remaining kinds change cash balance without re-pricing existing lots.
  """

  import Ecto.Query

  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Ledger.Positions
  alias Portfolixir.Ledger.Projection
  alias Portfolixir.Ledger.TradeMatcher
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios.CashAccount
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
    |> filter_transaction_eq(:securities_account_id, opts[:securities_account_id])
    |> filter_transaction_from(opts[:from])
    |> filter_transaction_to(opts[:to])
  end

  defp filter_transaction_eq(query, _field, nil), do: query

  defp filter_transaction_eq(query, :portfolio_id, id),
    do: where(query, [t], t.portfolio_id == ^id)

  defp filter_transaction_eq(query, :security_id, id),
    do: where(query, [t], t.security_id == ^id)

  defp filter_transaction_eq(query, :securities_account_id, id),
    do: where(query, [t], t.securities_account_id == ^id)

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
  the direction of the cash flow; the per-kind semantics live in
  `Portfolixir.Ledger.Projection` (ADR-0011). Each balance is in its own
  account's currency; no FX conversion is applied here. Pass `:portfolio_id` to
  scope the calculation to one portfolio. Accounts with no cash-affecting
  transaction are omitted and should be treated as a zero balance by callers.

  A `balance_adjustment` (see ADR-0009) is an absolute-balance snapshot, not a
  delta: it anchors the account to a stated balance as of its date, and only
  bookings dated strictly after it adjust the result. This lets an external
  account be kept current by stating its balance now and then, without mirroring
  every booking. An anchored account always appears in the result (even with no
  later bookings).
  """
  def cash_balances(opts \\ []) when is_list(opts) do
    Transaction
    |> scope_portfolio(opts[:portfolio_id])
    |> Repo.all()
    |> Projection.cash_balances()
  end

  defp scope_portfolio(query, nil), do: query

  defp scope_portfolio(query, portfolio_id) when is_integer(portfolio_id),
    do: where(query, [t], t.portfolio_id == ^portfolio_id)

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
  Returns the current holdings of a whole portfolio, one row per
  (depot, security), enriched with a moving-average cost basis and the
  unrealised P&L against each security's latest known quote close.

  Like `holdings_for_security/2`, the cost basis is price-based (it follows
  `moving_average/1`, so fees and taxes are not folded into the unit cost) and
  every monetary figure is in the security's own currency — no FX conversion is
  applied here (that is the job of `Portfolixir.Portfolios.Valuation`). A holding
  whose security has no quote is returned with `nil` price, market value and
  P&L, so a missing price never distorts the rest of the list.

  Pass `:prices` (`%{security_id => Decimal}`) to inject comparison prices for
  tests; missing securities fall back to `Catalog.Quotes.latest/1`.
  """
  def holdings_for_portfolio(portfolio_id, opts \\ []) when is_integer(portfolio_id) do
    prices = Keyword.get(opts, :prices, %{})

    portfolio_id
    |> portfolio_trades()
    |> Enum.group_by(fn tx -> {tx.securities_account_id, tx.security_id} end)
    |> Enum.map(fn {{account_id, security_id}, txs} ->
      build_holding_row(account_id, security_id, txs, holding_price(security_id, prices))
    end)
    |> Enum.reject(&Decimal.equal?(&1.quantity, 0))
    |> Enum.sort_by(&{&1.security_id, &1.securities_account_id})
  end

  # Buy/sell transactions of one portfolio in chronological order, with the
  # security preloaded so each holding can carry its name and currency. Ordering
  # ascending is required for the moving-average fold to be correct.
  defp portfolio_trades(portfolio_id) do
    Repo.all(
      from(transaction in Transaction,
        where: transaction.portfolio_id == ^portfolio_id and transaction.type in ["buy", "sell"],
        order_by: [asc: transaction.date, asc: transaction.id],
        preload: [:security]
      )
    )
  end

  defp build_holding_row(account_id, security_id, txs, latest_price) do
    summary = moving_average(txs)
    security = List.first(txs).security

    base = %{
      securities_account_id: account_id,
      security_id: security_id,
      security_name: security && security.name,
      currency_code: security && security.currency_code,
      quantity: summary.quantity,
      avg_cost: summary.avg_cost,
      cost_basis: Decimal.mult(summary.quantity, summary.avg_cost)
    }

    put_holding_valuation(base, latest_price)
  end

  defp put_holding_valuation(row, nil) do
    Map.merge(row, %{
      latest_price: nil,
      market_value: nil,
      unrealized_pnl_abs: nil,
      unrealized_pnl_pct: nil
    })
  end

  defp put_holding_valuation(row, %Decimal{} = latest_price) do
    market_value = Decimal.mult(row.quantity, latest_price)
    abs_pnl = Decimal.sub(market_value, row.cost_basis)

    pct_pnl =
      if Decimal.equal?(row.cost_basis, 0),
        do: Decimal.new(0),
        else: Decimal.div(abs_pnl, row.cost_basis)

    Map.merge(row, %{
      latest_price: latest_price,
      market_value: market_value,
      unrealized_pnl_abs: abs_pnl,
      unrealized_pnl_pct: pct_pnl
    })
  end

  defp holding_price(security_id, prices) do
    case Map.get(prices, security_id) do
      %Decimal{} = price -> price
      _ -> holding_latest_close(security_id)
    end
  end

  defp holding_latest_close(security_id) do
    case Quotes.latest(security_id) do
      %{close: %Decimal{} = close} -> close
      _ -> nil
    end
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

  @doc """
  Records an absolute cash-balance snapshot for one cash account (see ADR-0009).

  Stores a `balance_adjustment` transaction anchoring the account to `amount`
  (the absolute balance, which may be negative) as of `date`. The portfolio and
  currency are taken from the cash account. Returns `{:ok, transaction}` or
  `{:error, changeset}`.
  """
  def set_cash_balance(%CashAccount{} = cash_account, attrs) when is_map(attrs) do
    create_transaction(%{
      type: "balance_adjustment",
      portfolio_id: cash_account.portfolio_id,
      cash_account_id: cash_account.id,
      currency_code: cash_account.currency_code,
      date: get_attr(attrs, :date),
      gross_amount: get_attr(attrs, :amount),
      notes: get_attr(attrs, :notes)
    })
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

  def positions_for_portfolio(portfolio_id) when is_integer(portfolio_id) do
    portfolio_id
    |> list_transactions_for_portfolio()
    |> Positions.calculate()
  end

  @doc """
  The most recent own trade price per security in one portfolio.

  A buy or sell is a price observation; the valuation and the performance
  walk fall back to it when a security has no quote yet (Portfolio
  Performance seeds prices from bookings the same way). Returns
  `%{security_id => %{price: Decimal, currency: String.t(), date: Date.t()}}`.
  """
  def latest_trade_prices(portfolio_id) when is_integer(portfolio_id) do
    Repo.all(
      from(t in Transaction,
        where:
          t.portfolio_id == ^portfolio_id and t.type in ["buy", "sell"] and not is_nil(t.price),
        order_by: [asc: t.security_id, desc: t.date, desc: t.id],
        distinct: t.security_id,
        select: {t.security_id, %{price: t.price, currency: t.currency_code, date: t.date}}
      )
    )
    |> Map.new()
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
