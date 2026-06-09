defmodule PortfolixirWeb.Api.V1.JSON do
  @moduledoc false

  alias Ecto.Changeset
  alias Portfolixir.Catalog.Quote, as: SecurityQuote
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Catalog.SecuritySearch.SearchResult
  alias Portfolixir.Classifications.Assignment
  alias Portfolixir.Classifications.Category
  alias Portfolixir.Classifications.Classification
  alias Portfolixir.Fx.ExchangeRate
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios.{CashAccount, Portfolio, SecuritiesAccount, Target}

  def security(%Security{} = security) do
    %{
      id: security.id,
      name: security.name,
      ticker_symbol: security.ticker_symbol,
      isin: security.isin,
      wkn: security.wkn,
      currency_code: security.currency_code,
      exchange_code: security.exchange_code,
      asset_class: security.asset_class,
      note: security.note,
      feed: security.feed,
      feed_url: security.feed_url,
      latest_feed: security.latest_feed,
      latest_feed_url: security.latest_feed_url,
      is_retired: security.is_retired,
      online_id: security.online_id,
      provider: security.provider,
      attributes: security.attributes || %{},
      inserted_at: timestamp(security.inserted_at),
      updated_at: timestamp(security.updated_at)
    }
  end

  def search_result(%SearchResult{} = result) do
    %{
      provider: provider(result.provider),
      online_id: result.online_id,
      name: result.name,
      isin: result.isin,
      wkn: result.wkn,
      ticker_symbol: result.ticker_symbol,
      asset_class: result.asset_class,
      currency_code: result.currency_code,
      feed: result.feed,
      markets: Enum.map(result.markets || [], &market/1),
      raw: result.raw || %{}
    }
  end

  def portfolio(%Portfolio{} = portfolio) do
    %{
      id: portfolio.id,
      name: portfolio.name,
      base_currency_code: portfolio.base_currency_code,
      notes: portfolio.notes,
      inserted_at: timestamp(portfolio.inserted_at),
      updated_at: timestamp(portfolio.updated_at)
    }
  end

  def cash_account(%CashAccount{} = account) do
    %{
      id: account.id,
      portfolio_id: account.portfolio_id,
      name: account.name,
      currency_code: account.currency_code,
      notes: account.notes,
      inserted_at: timestamp(account.inserted_at),
      updated_at: timestamp(account.updated_at)
    }
  end

  def securities_account(%SecuritiesAccount{} = account) do
    cash_account =
      case Ecto.assoc_loaded?(account.cash_account) do
        true -> cash_account(account.cash_account)
        false -> nil
      end

    %{
      id: account.id,
      portfolio_id: account.portfolio_id,
      cash_account_id: account.cash_account_id,
      name: account.name,
      notes: account.notes,
      cash_account: cash_account,
      inserted_at: timestamp(account.inserted_at),
      updated_at: timestamp(account.updated_at)
    }
  end

  def transaction(%Transaction{} = transaction) do
    %{
      id: transaction.id,
      portfolio_id: transaction.portfolio_id,
      securities_account_id: transaction.securities_account_id,
      cash_account_id: transaction.cash_account_id,
      counter_cash_account_id: transaction.counter_cash_account_id,
      counter_securities_account_id: transaction.counter_securities_account_id,
      security_id: transaction.security_id,
      type: transaction.type,
      date: date(transaction.date),
      quantity: decimal(transaction.quantity),
      price: decimal(transaction.price),
      gross_amount: decimal(transaction.gross_amount),
      fees: decimal(transaction.fees),
      taxes: decimal(transaction.taxes),
      currency_code: transaction.currency_code,
      notes: transaction.notes,
      import_hash: transaction.import_hash,
      inserted_at: timestamp(transaction.inserted_at),
      updated_at: timestamp(transaction.updated_at)
    }
  end

  def trades(%{open_lots: lots, closed_trades: closed, orphan_sells: orphans}) do
    %{
      open_lots: Enum.map(lots, &open_lot/1),
      closed_trades: Enum.map(closed, &closed_trade/1),
      orphan_sells: Enum.map(orphans, &orphan_sell/1)
    }
  end

  defp open_lot(lot) do
    %{
      open_date: date(lot.open_date),
      quantity: decimal(lot.quantity),
      original_quantity: decimal(lot.original_quantity),
      buy_price: decimal(lot.buy_price),
      buy_fees: decimal(lot.buy_fees),
      buy_taxes: decimal(lot.buy_taxes),
      latest_price: decimal(lot.latest_price),
      unrealized_pnl_abs: decimal(lot.unrealized_pnl_abs),
      unrealized_pnl_pct: decimal(lot.unrealized_pnl_pct),
      currency_code: lot.currency_code
    }
  end

  defp closed_trade(trade) do
    %{
      open_date: date(trade.open_date),
      close_date: date(trade.close_date),
      quantity: decimal(trade.quantity),
      avg_buy_price: decimal(trade.avg_buy_price),
      avg_sell_price: decimal(trade.avg_sell_price),
      buy_fees: decimal(trade.buy_fees),
      buy_taxes: decimal(trade.buy_taxes),
      sell_fees: decimal(trade.sell_fees),
      sell_taxes: decimal(trade.sell_taxes),
      basis: decimal(trade.basis),
      proceeds: decimal(trade.proceeds),
      realized_pnl_abs: decimal(trade.realized_pnl_abs),
      realized_pnl_pct: decimal(trade.realized_pnl_pct),
      holding_period_days: trade.holding_period_days,
      currency_code: trade.currency_code
    }
  end

  defp orphan_sell(orphan) do
    %{
      date: date(orphan.date),
      quantity: decimal(orphan.quantity),
      price: decimal(orphan.price),
      currency_code: orphan.currency_code
    }
  end

  def quote(%SecurityQuote{} = quote) do
    %{
      id: quote.id,
      security_id: quote.security_id,
      date: date(quote.date),
      close: decimal(quote.close),
      source: quote.source,
      inserted_at: timestamp(quote.inserted_at),
      updated_at: timestamp(quote.updated_at)
    }
  end

  def holding(holding, portfolio_id) do
    %{
      portfolio_id: portfolio_id,
      securities_account_id: holding.securities_account_id,
      security_id: holding.security_id,
      security_name: holding.security_name,
      currency_code: holding.currency_code,
      quantity: decimal(holding.quantity),
      avg_cost: decimal(holding.avg_cost),
      cost_basis: decimal(holding.cost_basis),
      latest_price: decimal(holding.latest_price),
      market_value: decimal(holding.market_value),
      unrealized_pnl_abs: decimal(holding.unrealized_pnl_abs),
      unrealized_pnl_pct: decimal(holding.unrealized_pnl_pct)
    }
  end

  def valuation(%{positions: positions} = valuation) do
    %{
      portfolio_id: valuation.portfolio_id,
      base_currency: valuation.base_currency,
      total_value: decimal(valuation.total_value),
      total_cash: decimal(valuation.total_cash),
      total_with_cash: decimal(valuation.total_with_cash),
      unvalued_count: valuation.unvalued_count,
      positions: Enum.map(positions, &valuation_position/1),
      cash_balances: Enum.map(valuation.cash_balances, &valuation_cash/1)
    }
  end

  defp valuation_cash(cash) do
    %{
      cash_account_id: cash.cash_account_id,
      name: cash.name,
      currency: cash.currency,
      balance: decimal(cash.balance),
      base_value: decimal(cash.base_value),
      valued: cash.valued
    }
  end

  defp valuation_position(position) do
    %{
      securities_account_id: position.securities_account_id,
      security_id: position.security_id,
      security_name: position.security_name,
      asset_class: position.asset_class,
      security_currency: position.security_currency,
      quantity: decimal(position.quantity),
      latest_price: decimal(position.latest_price),
      market_value: decimal(position.market_value),
      weight: decimal(position.weight),
      valued: position.valued
    }
  end

  def target(%Target{} = target) do
    %{
      portfolio_id: target.portfolio_id,
      classification_id: target.classification_id,
      category_id: target.category_id,
      target_weight: decimal(target.target_weight)
    }
  end

  def allocation(allocation) do
    %{
      portfolio_id: allocation.portfolio_id,
      classification_id: allocation.classification_id,
      classification_name: allocation.classification_name,
      base_currency: allocation.base_currency,
      total_value: decimal(allocation.total_value),
      unvalued_count: allocation.unvalued_count,
      categories: Enum.map(allocation.categories, &allocation_category/1),
      unassigned: allocation_unassigned(allocation.unassigned)
    }
  end

  defp allocation_category(category) do
    %{
      category_id: category.category_id,
      name: category.name,
      market_value: decimal(category.market_value),
      actual_weight: decimal(category.actual_weight),
      target_weight: decimal(category.target_weight),
      drift_weight: decimal(category.drift_weight),
      drift_value: decimal(category.drift_value)
    }
  end

  defp allocation_unassigned(nil), do: nil

  defp allocation_unassigned(unassigned) do
    %{
      market_value: decimal(unassigned.market_value),
      actual_weight: decimal(unassigned.actual_weight)
    }
  end

  def classification_tree(%{classification: classification} = tree) do
    classification
    |> classification()
    |> Map.merge(%{
      categories: Enum.map(tree.categories, &category/1),
      assignments: Enum.map(tree.assignments, &assignment/1)
    })
  end

  def classification(%Classification{} = classification) do
    %{
      id: classification.id,
      name: classification.name,
      key: classification.key,
      built_in: classification.built_in,
      position: classification.position,
      description: classification.description
    }
  end

  def category(%Category{} = category) do
    %{
      id: category.id,
      classification_id: category.classification_id,
      parent_id: category.parent_id,
      name: category.name,
      key: category.key,
      color: category.color,
      description: category.description,
      position: category.position
    }
  end

  def assignment(%Assignment{} = assignment) do
    %{
      security_id: assignment.security_id,
      classification_id: assignment.classification_id,
      category_id: assignment.category_id
    }
  end

  def assignment(%{security_id: security_id, category_id: category_id}) do
    %{security_id: security_id, category_id: category_id}
  end

  def exchange_rate(%ExchangeRate{} = rate) do
    %{
      base_currency: rate.base_currency,
      quote_currency: rate.quote_currency,
      date: date(rate.date),
      rate: decimal(rate.rate),
      source: rate.source
    }
  end

  def fx_sync_result(%{provider: provider, status: status, upserted: upserted}) do
    %{provider: to_string(provider), status: to_string(status), upserted: upserted}
  end

  def errors(%Changeset{} = changeset) do
    Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  def decimal(nil), do: nil

  def decimal(%Decimal{} = decimal) do
    decimal
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end

  def decimal(value), do: to_string(value)

  def date(nil), do: nil
  def date(%Date{} = date), do: Date.to_iso8601(date)

  def timestamp(nil), do: nil
  def timestamp(%NaiveDateTime{} = timestamp), do: NaiveDateTime.to_iso8601(timestamp)

  defp provider(nil), do: nil
  defp provider(provider) when is_atom(provider), do: Atom.to_string(provider)
  defp provider(provider), do: to_string(provider)

  defp market(market) do
    %{
      symbol: market.symbol,
      currency_code: market.currency_code,
      exchange_code: market.exchange_code,
      exchange_name: market.exchange_name,
      url: market.url
    }
  end
end
