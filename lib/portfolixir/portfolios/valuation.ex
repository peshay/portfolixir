defmodule Portfolixir.Portfolios.Valuation do
  @moduledoc """
  Read-time market valuation of a portfolio.

  Prices each currently held position from its latest quote close, sums the
  valued positions into a portfolio total, and reports each valued position's
  share (weight) of that total.

  Nothing is stored: like holdings and FIFO trades, the valuation is derived
  from transactions and quote history on read (see ADR-0004). A held position
  without any quote is reported as unvalued so a missing price never silently
  distorts the total or the weights.
  """

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Ledger

  @zero Decimal.new("0")

  @doc """
  Returns the live valuation for one portfolio.

  Pass `:prices` (a `%{security_id => Decimal}` map) to inject prices in tests;
  any security missing from the map falls back to `Catalog.Quotes.latest/1`.
  """
  def for_portfolio(portfolio_id, opts \\ []) when is_integer(portfolio_id) do
    prices = Keyword.get(opts, :prices, %{})

    positions =
      portfolio_id
      |> Ledger.positions_for_portfolio()
      |> Enum.map(fn {{securities_account_id, security_id}, quantity} ->
        build_position(securities_account_id, security_id, quantity, prices)
      end)

    total = total_value(positions)

    positions =
      positions
      |> Enum.map(&put_weight(&1, total))
      |> Enum.sort_by(& &1.security_id)

    %{
      portfolio_id: portfolio_id,
      total_value: total,
      positions: positions,
      unvalued_count: Enum.count(positions, &(not &1.valued))
    }
  end

  defp build_position(securities_account_id, security_id, quantity, prices) do
    security = Catalog.get_security(security_id)
    price = price_for(security_id, prices)

    {market_value, valued?} =
      case price do
        %Decimal{} -> {Decimal.mult(quantity, price), true}
        _ -> {nil, false}
      end

    %{
      securities_account_id: securities_account_id,
      security_id: security_id,
      security_name: security && security.name,
      asset_class: security && Security.effective_asset_class(security),
      quantity: quantity,
      latest_price: price,
      market_value: market_value,
      weight: nil,
      valued: valued?
    }
  end

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
