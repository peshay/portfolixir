defmodule Portfolixir.Valuation do
  @moduledoc "Read-only portfolio valuation helpers based on derived positions and stored quotes."

  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  @type position_valuation :: %{
          portfolio_id: integer(),
          securities_account: String.t() | nil,
          security: String.t() | nil,
          quantity: Decimal.t(),
          latest_quote_date: Date.t() | nil,
          latest_quote_close: Decimal.t() | nil,
          market_value: Decimal.t() | nil,
          currency_code: String.t() | nil,
          warning: String.t() | nil
        }

  @spec position_market_value_snapshot(integer()) :: %{
          portfolio_id: integer(),
          positions: [position_valuation()],
          totals_by_currency: %{optional(String.t()) => Decimal.t()}
        }
  def position_market_value_snapshot(portfolio_id) when is_integer(portfolio_id) do
    positions = Ledger.positions_for_portfolio(portfolio_id)

    securities_account_names =
      portfolio_id
      |> Portfolios.list_securities_accounts_for_portfolio()
      |> Map.new(&{&1.id, &1.name})

    position_rows =
      positions
      |> Enum.map(fn {{securities_account_id, security_id}, quantity} ->
        security = Catalog.get_security(security_id)
        latest_quote = Catalog.get_latest_security_quote(security_id)

        market_value = latest_quote && Decimal.mult(quantity, latest_quote.close)
        warning = if latest_quote, do: nil, else: "missing_latest_quote"

        %{
          portfolio_id: portfolio_id,
          securities_account: Map.get(securities_account_names, securities_account_id),
          security: security && security.name,
          quantity: quantity,
          latest_quote_date: latest_quote && latest_quote.date,
          latest_quote_close: latest_quote && latest_quote.close,
          market_value: market_value,
          currency_code:
            (latest_quote && latest_quote.currency_code) || (security && security.currency_code),
          warning: warning
        }
      end)
      |> Enum.sort_by(fn row -> {row.securities_account || "", row.security || ""} end)

    totals_by_currency =
      Enum.reduce(position_rows, %{}, fn row, acc ->
        if row.market_value && row.currency_code do
          Map.update(acc, row.currency_code, row.market_value, &Decimal.add(&1, row.market_value))
        else
          acc
        end
      end)

    %{
      portfolio_id: portfolio_id,
      positions: position_rows,
      totals_by_currency: totals_by_currency
    }
  end
end
