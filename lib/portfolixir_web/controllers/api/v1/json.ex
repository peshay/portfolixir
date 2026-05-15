defmodule PortfolixirWeb.Api.V1.JSON do
  @moduledoc false

  alias Ecto.Changeset
  alias Portfolixir.Catalog.Quote, as: SecurityQuote
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Catalog.SecuritySearch.SearchResult
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios.{CashAccount, Portfolio, SecuritiesAccount}

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
      security_id: transaction.security_id,
      type: transaction.type,
      date: date(transaction.date),
      quantity: decimal(transaction.quantity),
      price: decimal(transaction.price),
      fees: decimal(transaction.fees),
      taxes: decimal(transaction.taxes),
      currency_code: transaction.currency_code,
      notes: transaction.notes,
      inserted_at: timestamp(transaction.inserted_at),
      updated_at: timestamp(transaction.updated_at)
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

  def holding({{securities_account_id, security_id}, quantity}, portfolio_id) do
    %{
      portfolio_id: portfolio_id,
      securities_account_id: securities_account_id,
      security_id: security_id,
      quantity: decimal(quantity)
    }
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
