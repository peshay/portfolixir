defmodule Portfolixir.Portfolios.Valuation do
  @moduledoc """
  Read-time market valuation of a portfolio.

  Prices each currently held position from its latest quote close, converts it
  into the portfolio's `base_currency_code` (see `Portfolixir.Fx`), sums the
  valued positions into a total, and reports each valued position's share
  (weight) of that total.

  Nothing is stored: like holdings and FIFO trades, the valuation is derived
  from transactions, quote history, and exchange rates on read (see ADR-0004,
  ADR-0007). A held position is reported as unvalued when it has no quote **or**
  no exchange-rate path to the base currency, so a missing price or rate never
  silently distorts the total or the weights.
  """

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  @zero Decimal.new("0")

  @doc """
  Returns the live valuation for one portfolio, in the portfolio base currency.

  Options (for tests):
    * `:prices` – `%{security_id => Decimal}` native prices; missing securities
      fall back to `Catalog.Quotes.latest/1`.
    * `:base_currency` – overrides the portfolio's base currency.
  """
  def for_portfolio(portfolio_id, opts \\ []) when is_integer(portfolio_id) do
    prices = Keyword.get(opts, :prices, %{})

    base_currency =
      Keyword.get_lazy(opts, :base_currency, fn -> base_currency_for(portfolio_id) end)

    positions =
      portfolio_id
      |> Ledger.positions_for_portfolio()
      |> Enum.map(fn {{securities_account_id, security_id}, quantity} ->
        build_position(securities_account_id, security_id, quantity, prices, base_currency)
      end)

    total = total_value(positions)

    positions =
      positions
      |> Enum.map(&put_weight(&1, total))
      |> Enum.sort_by(& &1.security_id)

    cash = cash_for(portfolio_id, base_currency)

    %{
      portfolio_id: portfolio_id,
      base_currency: base_currency,
      total_value: total,
      total_cash: cash.total,
      total_with_cash: Decimal.add(total, cash.total),
      cash_balances: cash.balances,
      positions: positions,
      unvalued_count: Enum.count(positions, &(not &1.valued))
    }
  end

  # Per-account cash balances (in account currency) plus their sum converted to
  # the portfolio base currency. An account whose currency has no rate path to
  # the base is reported unvalued and left out of `total_cash`, mirroring how
  # unpriceable positions are handled.
  defp cash_for(portfolio_id, base_currency) do
    balances = Ledger.cash_balances(portfolio_id: portfolio_id)

    entries =
      portfolio_id
      |> Portfolios.list_cash_accounts_for_portfolio()
      |> Enum.map(fn account ->
        balance = Map.get(balances, account.id, @zero)
        {base_value, valued?} = convert_cash(balance, account.currency_code, base_currency)

        %{
          cash_account_id: account.id,
          name: account.name,
          currency: account.currency_code,
          balance: balance,
          base_value: base_value,
          valued: valued?
        }
      end)
      |> Enum.sort_by(& &1.cash_account_id)

    total =
      entries
      |> Enum.filter(& &1.valued)
      |> Enum.reduce(@zero, fn entry, acc -> Decimal.add(acc, entry.base_value) end)

    %{balances: entries, total: total}
  end

  defp convert_cash(%Decimal{} = balance, from, base) when is_binary(from) and is_binary(base) do
    case Fx.convert(balance, from, base) do
      {:ok, converted} -> {converted, true}
      {:error, _reason} -> {nil, false}
    end
  end

  defp convert_cash(_balance, _from, _base), do: {nil, false}

  defp build_position(securities_account_id, security_id, quantity, prices, base_currency) do
    security = Catalog.get_security(security_id)
    price = price_for(security_id, prices)
    security_currency = security && security.currency_code

    {market_value, valued?} = market_value(quantity, price, security_currency, base_currency)

    %{
      securities_account_id: securities_account_id,
      security_id: security_id,
      security_name: security && security.name,
      asset_class: security && Security.effective_asset_class(security),
      security_currency: security_currency,
      quantity: quantity,
      latest_price: price,
      market_value: market_value,
      weight: nil,
      valued: valued?
    }
  end

  defp market_value(quantity, %Decimal{} = price, from, base)
       when is_binary(from) and is_binary(base) do
    native = Decimal.mult(quantity, price)

    case Fx.convert(native, from, base) do
      {:ok, converted} -> {converted, true}
      {:error, _reason} -> {nil, false}
    end
  end

  defp market_value(_quantity, _price, _from, _base), do: {nil, false}

  defp price_for(security_id, prices) do
    case Map.get(prices, security_id) do
      %Decimal{} = price -> price
      _ -> latest_close(security_id)
    end
  end

  defp latest_close(security_id) do
    case Quotes.latest(security_id) do
      %{close: %Decimal{} = close} -> close
      _ -> nil
    end
  end

  defp base_currency_for(portfolio_id) do
    case Portfolios.get_portfolio(portfolio_id) do
      %{base_currency_code: code} -> code
      _ -> nil
    end
  end

  defp total_value(positions) do
    positions
    |> Enum.filter(& &1.valued)
    |> Enum.reduce(@zero, fn position, acc -> Decimal.add(acc, position.market_value) end)
  end

  defp put_weight(%{valued: false} = position, _total), do: position

  defp put_weight(%{valued: true} = position, total) do
    weight =
      if Decimal.equal?(total, @zero) do
        @zero
      else
        Decimal.div(position.market_value, total)
      end

    %{position | weight: weight}
  end
end
